import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../../lyrics/lyrics_progress.dart';
import '../../../../lyrics/models/lyrics_line.dart';
import '../../../player/presentation/providers/lyrics_provider.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../data/floating_lyrics_models.dart';
import '../../data/floating_lyrics_service.dart';

const _floatingLyricsBoxName = 'settings';
const _floatingLyricsKey = 'floating_lyrics_settings';

final floatingLyricsProvider =
    StateNotifierProvider<FloatingLyricsNotifier, FloatingLyricsSettings>((
      ref,
    ) {
      return FloatingLyricsNotifier();
    });

final floatingLyricsSyncProvider = Provider<FloatingLyricsSyncController>((
  ref,
) {
  final controller = FloatingLyricsSyncController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});

class FloatingLyricsNotifier extends StateNotifier<FloatingLyricsSettings> {
  Future<void> ready = Future.value();

  FloatingLyricsNotifier() : super(const FloatingLyricsSettings()) {
    _load();
  }

  void _load() {
    try {
      final box = Hive.box(_floatingLyricsBoxName);
      final raw = box.get(_floatingLyricsKey);
      if (!mounted || raw is! Map) return;
      state = FloatingLyricsSettings.fromJson(raw);
    } catch (e, s) {
      debugPrint('FloatingLyricsNotifier load failed: $e');
      debugPrint('$s');
    }
  }

  Future<void> setEnabled(bool enabled) async {
    await _save(
      state.copyWith(
        enabled: enabled,
        // Turning the overlay off releases the lock: a locked overlay ignores
        // every touch, so a stale lock would strand the user outside the app.
        isLocked: enabled ? state.isLocked : false,
      ),
    );
  }

  Future<void> setTextColor(Color color) async {
    await _save(state.copyWith(textColor: color));
  }

  Future<void> setHighlightColor(Color color) async {
    await _save(state.copyWith(highlightColor: color));
  }

  Future<void> setFontSize(double fontSize) async {
    await _save(state.copyWith(fontSize: fontSize.clamp(14, 48)));
  }

  Future<void> setStrokeWidth(double strokeWidth) async {
    await _save(state.copyWith(strokeWidth: strokeWidth.clamp(0, 2)));
  }

  Future<void> setShadowOpacity(double shadowOpacity) async {
    await _save(state.copyWith(shadowOpacity: shadowOpacity.clamp(0, 1)));
  }

  Future<void> setWindowSize({required double width, required double height}) {
    return _save(
      state.copyWith(
        width: width.clamp(180, 720),
        height: height.clamp(56, 220),
      ),
    );
  }

  Future<void> setLocked(bool isLocked) async {
    await _save(state.copyWith(isLocked: isLocked));
  }

  Future<void> setPositionY(double positionY) async {
    if (positionY < 0) return;
    await _save(state.copyWith(positionY: positionY));
  }

  /// Toggles the switch from outside the settings page — currently the
  /// playback notification's lyrics button. Mirrors the settings page flow and
  /// asks for the overlay permission on the first enable.
  Future<void> toggleEnabled() async {
    if (state.enabled) {
      await setEnabled(false);
      try {
        await FloatingLyricsService.instance.hide();
      } catch (e, s) {
        debugPrint('FloatingLyricsNotifier toggleEnabled hide failed: $e');
        debugPrint('$s');
      }
      return;
    }
    try {
      final allowed = await FloatingLyricsService.instance.canDrawOverlays();
      if (!allowed) {
        await FloatingLyricsService.instance.openOverlaySettings();
      }
    } catch (e, s) {
      debugPrint('FloatingLyricsNotifier toggleEnabled permission failed: $e');
      debugPrint('$s');
    }
    await setEnabled(true);
  }

  Future<void> _save(FloatingLyricsSettings settings) async {
    state = settings;
    try {
      final box = await Hive.openBox(_floatingLyricsBoxName);
      await box.put(_floatingLyricsKey, settings.toJson());
    } catch (e, s) {
      debugPrint('FloatingLyricsNotifier save failed: $e');
      debugPrint('$s');
    }
  }
}

class FloatingLyricsSyncController {
  final Ref _ref;
  final FloatingLyricsService _service;
  final DateTime Function() _now;
  final List<ProviderSubscription> _subscriptions = [];
  final List<StreamSubscription> _nativeSubscriptions = [];
  FloatingLyricsPayload? _lastPayload;
  String? _lastNativeSignature;
  int _syncGeneration = 0;
  Timer? _sweepTimer;
  late final LyricsProgressEstimator _positionEstimator;
  late final PlayedProgressRate _progressRate;

  FloatingLyricsSyncController(
    this._ref, {
    FloatingLyricsService? service,
    DateTime Function()? now,
  }) : _service = service ?? FloatingLyricsService.instance,
       _now = now ?? DateTime.now {
    _positionEstimator = LyricsProgressEstimator(now: _now);
    _progressRate = PlayedProgressRate();
    _subscriptions.add(
      _ref.listen<FloatingLyricsSettings>(
        floatingLyricsProvider,
        (previous, next) => unawaited(sync()),
      ),
    );
    _subscriptions.add(
      _ref.listen<Duration>(
        playerProvider.select((state) => state.position),
        (previous, next) => unawaited(sync()),
      ),
    );
    // The overlay draws its own play/pause button, so it needs the playing
    // state even when the position is not ticking (paused, ended, ...).
    _subscriptions.add(
      _ref.listen<bool>(
        playerProvider.select((state) => state.isPlaying),
        (previous, next) => unawaited(sync()),
      ),
    );
    _subscriptions.add(
      _ref.listen(lyricsProvider, (previous, next) => unawaited(sync())),
    );
    _nativeSubscriptions.add(
      _service.windowResizedStream.listen((size) async {
        await _ref
            .read(floatingLyricsProvider.notifier)
            .setWindowSize(
              width: size.width.toDouble(),
              height: size.height.toDouble(),
            );
      }),
    );
    _nativeSubscriptions.add(
      _service.closedByUserStream.listen((_) async {
        _syncGeneration++;
        _lastPayload = null;
        _lastNativeSignature = null;
        // Stop the 200 ms sweep BEFORE the first await, synchronously. Between
        // the native close and `setEnabled(false)` actually landing there is a
        // window in which a sweep tick would run `sync()` and push another
        // `update`, re-creating the window the user just closed (the
        // addView/removeView churn). Stopping the clock here fixes that at its
        // source — the native side deliberately no longer latches on `hide`,
        // because a latch that only `show()` can clear never reopens (Dart never
        // calls `show`).
        _updateSweepTimer(running: false);
        await _service.hide();
        await _ref.read(floatingLyricsProvider.notifier).setEnabled(false);
      }),
    );
    _nativeSubscriptions.add(
      _service.lockChangedStream.listen((isLocked) async {
        await _ref.read(floatingLyricsProvider.notifier).setLocked(isLocked);
      }),
    );
    _nativeSubscriptions.add(
      _service.styleChangedStream.listen((style) async {
        final notifier = _ref.read(floatingLyricsProvider.notifier);
        await notifier.setHighlightColor(style.highlightColor);
        await notifier.setFontSize(style.fontSize);
      }),
    );
    _nativeSubscriptions.add(
      _service.controlRequestedStream.listen((control) async {
        final player = _ref.read(playerProvider.notifier);
        switch (control) {
          case FloatingLyricsControl.playPause:
            await player.togglePlay();
            break;
          case FloatingLyricsControl.previous:
            await player.skipToPrevious();
            break;
          case FloatingLyricsControl.next:
            await player.skipToNext();
            break;
        }
      }),
    );
    _nativeSubscriptions.add(
      _service.positionChangedStream.listen((positionY) async {
        await _ref
            .read(floatingLyricsProvider.notifier)
            .setPositionY(positionY);
      }),
    );
  }

  /// Builds the two-line overlay payload for [position].
  ///
  /// [highlightPosition] is the (usually interpolated) position used only for
  /// the played-progress highlight; line selection always follows [position] so
  /// a lyric line can never advance ahead of the player state.
  static FloatingLyricsPayload payloadForPosition(
    LyricsDocument? document,
    Duration position, {
    Duration? highlightPosition,
  }) {
    if (document == null || document.lines.isEmpty) {
      return const FloatingLyricsPayload(text: '');
    }

    final lines = document.lines;
    var activeIndex = -1;
    var firstVisibleIndex = -1;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!_hasVisibleText(line)) continue;
      if (firstVisibleIndex < 0) firstVisibleIndex = i;
      if (line.timestamp > position) break;
      activeIndex = i;
    }
    if (activeIndex < 0) activeIndex = firstVisibleIndex;
    if (activeIndex < 0) {
      return const FloatingLyricsPayload(text: '');
    }

    final active = lines[activeIndex];
    final nextIndex = _nextVisibleIndex(lines, activeIndex);
    final next = nextIndex >= 0 ? lines[nextIndex] : null;

    return FloatingLyricsPayload(
      text: active.text,
      translation: active.translation,
      nextText: next?.text ?? '',
      highlightProgress: playedFraction(
        active,
        highlightPosition ?? position,
        nextTimestamp: next?.timestamp,
      ),
    );
  }

  /// How many leading characters of [line] playback has already reached.
  ///
  /// Thin delegate to the shared helper so the overlay and the in-app player
  /// lyrics always agree. The overlay itself animates from [playedFraction],
  /// which keeps the fraction of the character being sung.
  static int highlightCharactersFor(
    LyricsLine line,
    Duration position,
    Duration? nextTimestamp,
  ) {
    return playedCharacterCount(line, position, nextTimestamp: nextTimestamp);
  }

  static int _nextVisibleIndex(List<LyricsLine> lines, int fromIndex) {
    for (var i = fromIndex + 1; i < lines.length; i++) {
      if (_hasVisibleText(lines[i])) return i;
    }
    return -1;
  }

  static bool _hasVisibleText(LyricsLine line) {
    return line.text.trim().isNotEmpty ||
        (line.translation?.trim().isNotEmpty ?? false);
  }

  /// Player state only reports the position about once per second, so the
  /// played highlight would step coarsely. The estimator extrapolates from the
  /// last state change while playing; line selection keeps the raw value.
  Duration _estimatedPosition(PlayerState playerState) {
    return _positionEstimator.estimate(
      playerState.position,
      isPlaying: playerState.isPlaying,
      duration: playerState.duration,
    );
  }

  void _updateSweepTimer({required bool running}) {
    if (running && _sweepTimer == null) {
      _sweepTimer = Timer.periodic(
        _sweepInterval,
        (_) => unawaited(sync()),
      );
    } else if (!running && _sweepTimer != null) {
      _sweepTimer!.cancel();
      _sweepTimer = null;
    }
  }

  /// Guards against overlapping native round trips.
  ///
  /// Four listeners (settings / position / isPlaying / lyrics) plus the 200 ms
  /// sweep timer can all call this within the same frame. Each call used to run
  /// `canDrawOverlays()` **and** `update()` over the platform channel — on
  /// Android that channel runs on the same thread as the UI — so a burst queued
  /// up more round trips than the overlay could drain, and the queue itself kept
  /// the main thread busy.
  ///
  /// Now at most one call is in flight, and a burst collapses into a single
  /// follow-up. Nothing is lost by collapsing: the follow-up reads the *current*
  /// state rather than a queued snapshot.
  bool _syncInFlight = false;
  bool _syncQueued = false;

  Future<void> sync() async {
    if (_syncInFlight) {
      _syncQueued = true;
      return;
    }
    _syncInFlight = true;
    try {
      // The loop body has no await between the condition check and the flag
      // flip, so a caller arriving in the middle always lands in `_syncQueued`
      // and is serviced here.
      do {
        _syncQueued = false;
        await _syncOnce();
      } while (_syncQueued);
    } finally {
      _syncInFlight = false;
    }
  }

  Future<void> _syncOnce() async {
    final syncGeneration = ++_syncGeneration;
    final settings = _ref.read(floatingLyricsProvider);
    if (!settings.enabled) {
      _updateSweepTimer(running: false);
      _progressRate.reset();
      _lastPayload = null;
      _lastNativeSignature = null;
      await _service.hide();
      return;
    }

    final lyrics = _ref.read(lyricsProvider).valueOrNull;
    if (lyrics == null || lyrics.lines.isEmpty) {
      _updateSweepTimer(running: false);
      _progressRate.reset();
      _lastNativeSignature = null;
      return;
    }
    final playerState = _ref.read(playerProvider);
    _updateSweepTimer(
      running: playerState.isPlaying && playerState.currentSong != null,
    );
    final basePayload = payloadForPosition(
      lyrics,
      playerState.position,
      highlightPosition: _estimatedPosition(playerState),
    );
    if (basePayload.text.trim().isEmpty &&
        (basePayload.translation?.trim().isEmpty ?? true)) {
      _lastNativeSignature = null;
      return;
    }
    final payload = basePayload.copyWith(
      // Rate lets the native overlay keep sweeping between two ~200ms anchors
      // instead of stepping. It drops to zero while paused or in a vocal gap.
      highlightRate: _progressRate.update(
        basePayload.highlightProgress,
        _now(),
        isPlaying: playerState.isPlaying,
      ),
      isPlaying: playerState.isPlaying,
      hasSong: playerState.currentSong != null,
    );
    _lastPayload = payload;
    final signature = _nativeSignature(payload, settings);
    if (_lastNativeSignature == signature) return;

    final hasPermission = await _service.canDrawOverlays();
    if (syncGeneration != _syncGeneration) return;
    if (!hasPermission) return;
    final latestSettings = _ref.read(floatingLyricsProvider);
    if (!latestSettings.enabled) {
      _updateSweepTimer(running: false);
      _lastPayload = null;
      await _service.hide();
      return;
    }
    await _service.update(payload, latestSettings);
    if (syncGeneration == _syncGeneration) {
      _lastNativeSignature = _nativeSignature(payload, latestSettings);
    }
  }

  FloatingLyricsPayload? get lastPayloadForTest => _lastPayload;

  void dispose() {
    _updateSweepTimer(running: false);
    for (final sub in _subscriptions) {
      sub.close();
    }
    for (final sub in _nativeSubscriptions) {
      unawaited(sub.cancel());
    }
  }

  static String _nativeSignature(
    FloatingLyricsPayload payload,
    FloatingLyricsSettings settings,
  ) {
    return [
      payload.text,
      payload.translation ?? '',
      payload.progress.clamp(0, 1),
      payload.nextText,
      payload.highlightProgress,
      payload.highlightRate,
      payload.isPlaying,
      payload.hasSong,
      settings.textColor.toARGB32(),
      settings.highlightColor.toARGB32(),
      settings.backgroundColor.toARGB32(),
      settings.fontSize,
      settings.strokeWidth,
      settings.shadowOpacity,
      settings.width,
      settings.height,
      settings.isLocked,
      // `positionY` is deliberately excluded: the native window owns the live
      // vertical offset and only reads the persisted value when it (re)creates
      // the overlay, so persisting a drag must not trigger another update.
    ].join('\u001f');
  }
}

/// How often the played-progress highlight is re-evaluated while playing. The
/// player state itself only advances once per second, so this driver keeps the
/// sweep smooth using [LyricsProgressEstimator].
const _sweepInterval = Duration(milliseconds: 200);
