import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../../core/lyrics/lyrics_animation_catalog.dart';
import '../../../../core/lyrics/lyrics_overlay_config.dart';
import '../../../../core/lyrics/lyrics_overlay_frame.dart';
import '../../../../core/lyrics/lyrics_overlay_sink.dart';
import '../../../../lyrics/lyrics_progress.dart';
import '../../../../lyrics/models/lyrics_line.dart';
import '../../../player/presentation/providers/lyrics_offset_provider.dart';
import '../../../player/presentation/providers/lyrics_provider.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../data/floating_lyrics_models.dart';
import '../../data/floating_lyrics_service.dart';
import '../../data/sinks/android_floating_lyrics_sink.dart';
import '../../data/sinks/desktop_lyrics_sinks.dart';
import 'taskbar_lyrics_provider.dart';

const _floatingLyricsBoxName = 'settings';
const _floatingLyricsKey = 'floating_lyrics_settings';

final floatingLyricsProvider =
    StateNotifierProvider<FloatingLyricsNotifier, FloatingLyricsSettings>((
      ref,
    ) {
      return FloatingLyricsNotifier();
    });

/// The sync engine, wired with the sinks the current platform can draw on.
///
/// Android keeps the legacy overlay sink; Windows gets the rewritable floating
/// window plus the taskbar strip. Tests that build a bare
/// [FloatingLyricsSyncController] keep the Android sink, which is exactly the
/// legacy channel behaviour they assert.
final floatingLyricsSyncProvider = Provider<FloatingLyricsSyncController>((
  ref,
) {
  final controller = FloatingLyricsSyncController(
    ref,
    // Shared with the taskbar status notifier: the strip's event stream and
    // its channel call handler may only exist once, so the instances come
    // from the provider that also owns their disposal.
    sinks: ref.watch(desktopLyricsSinksProvider),
  );
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

  /// One write path for the desktop-only fields; the typed setters below use it
  /// so a new field needs no new persistence code.
  Future<void> apply(
    FloatingLyricsSettings Function(FloatingLyricsSettings current) change,
  ) {
    return _save(change(state));
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
    await _save(
      state.copyWith(fontSize: FloatingLyricsSettings.clampFontSize(fontSize)),
    );
  }

  Future<void> setStrokeWidth(double strokeWidth) async {
    await _save(
      state.copyWith(
        strokeWidth: FloatingLyricsSettings.clampStrokeWidth(strokeWidth),
      ),
    );
  }

  Future<void> setShadowOpacity(double shadowOpacity) async {
    await _save(
      state.copyWith(
        shadowOpacity: FloatingLyricsSettings.clampShadowOpacity(shadowOpacity),
      ),
    );
  }

  Future<void> setWindowSize({required double width, required double height}) {
    return _save(
      state.copyWith(
        width: FloatingLyricsSettings.clampWidth(width),
        height: FloatingLyricsSettings.clampHeight(height),
      ),
    );
  }

  /// One axis at a time for the studio sliders; both go through the same
  /// clamps the window resize path uses.
  Future<void> setWidth(double width) =>
      apply((s) => s.copyWith(width: FloatingLyricsSettings.clampWidth(width)));

  Future<void> setHeight(double height) => apply(
    (s) => s.copyWith(height: FloatingLyricsSettings.clampHeight(height)),
  );

  Future<void> setLocked(bool isLocked) async {
    await _save(state.copyWith(isLocked: isLocked));
  }

  Future<void> setPositionY(double positionY) async {
    if (positionY < 0) return;
    await _save(state.copyWith(positionY: positionY));
  }

  Future<void> setPositionX(double value) => apply(
    (s) => s.copyWith(positionX: FloatingLyricsSettings.clampPositionX(value)),
  );

  Future<void> setPositionYRatio(double value) => apply(
    (s) => s.copyWith(
      positionYRatio: FloatingLyricsSettings.clampPositionYRatio(value),
    ),
  );

  Future<void> clearPosition() =>
      apply((s) => s.copyWith(clearPositionX: true, clearPositionYRatio: true));

  Future<void> setMonitorDeviceName(String value) =>
      apply((s) => s.copyWith(monitorDeviceName: value));

  Future<void> setLineAnimation(LyricsLineTransition value) =>
      apply((s) => s.copyWith(lineAnimation: value));

  Future<void> setAnimationDurationMs(int value) => apply(
    (s) => s.copyWith(
      animationDurationMs: FloatingLyricsSettings.clampAnimationDurationMs(
        value,
      ),
    ),
  );

  Future<void> setEasing(LyricsEasing value) =>
      apply((s) => s.copyWith(easing: value));

  Future<void> setWindowAnimation(LyricsWindowTransition value) =>
      apply((s) => s.copyWith(windowAnimation: value));

  Future<void> setBackgroundMode(LyricsBackgroundMode value) =>
      apply((s) => s.copyWith(backgroundMode: value));

  Future<void> setBackgroundColor2(Color color) =>
      apply((s) => s.copyWith(backgroundColor2: color));

  Future<void> setBackgroundOpacity(double value) => apply(
    (s) => s.copyWith(
      backgroundOpacity: FloatingLyricsSettings.clampBackgroundOpacity(value),
    ),
  );

  Future<void> setCornerRadius(double value) => apply(
    (s) => s.copyWith(
      cornerRadius: FloatingLyricsSettings.clampCornerRadius(value),
    ),
  );

  Future<void> setFontFamily(String value) =>
      apply((s) => s.copyWith(fontFamily: value));

  Future<void> setFontWeight(int value) => apply(
    (s) =>
        s.copyWith(fontWeight: FloatingLyricsSettings.clampFontWeight(value)),
  );

  Future<void> setTextAlign(LyricsTextAlignment value) =>
      apply((s) => s.copyWith(textAlign: value));

  Future<void> setLineMode(LyricsLineMode value) =>
      apply((s) => s.copyWith(lineMode: value));

  Future<void> setShowTranslation(LyricsTranslationVisibility value) =>
      apply((s) => s.copyWith(showTranslation: value));

  Future<void> setLetterSpacing(double value) => apply(
    (s) => s.copyWith(
      letterSpacing: FloatingLyricsSettings.clampLetterSpacing(value),
    ),
  );

  Future<void> setLineHeight(double value) => apply(
    (s) =>
        s.copyWith(lineHeight: FloatingLyricsSettings.clampLineHeight(value)),
  );

  Future<void> setPadding(double value) => apply(
    (s) => s.copyWith(padding: FloatingLyricsSettings.clampPadding(value)),
  );

  Future<void> setShowControls(bool value) =>
      apply((s) => s.copyWith(showControls: value));

  Future<void> setClickThrough(bool value) =>
      apply((s) => s.copyWith(clickThrough: value));

  Future<void> setAlwaysOnTop(bool value) =>
      apply((s) => s.copyWith(alwaysOnTop: value));

  Future<void> setHideInFullscreen(bool value) =>
      apply((s) => s.copyWith(hideInFullscreen: value));

  Future<void> setReduceMotion(bool value) =>
      apply((s) => s.copyWith(reduceMotion: value));

  Future<void> setStrokeColor(Color color) =>
      apply((s) => s.copyWith(strokeColor: color));

  Future<void> setShadowBlur(double value) => apply(
    (s) =>
        s.copyWith(shadowBlur: FloatingLyricsSettings.clampShadowBlur(value)),
  );

  Future<void> setWordHighlight(bool value) =>
      apply((s) => s.copyWith(wordHighlight: value));

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
  final List<LyricsOverlaySink> _sinks;

  /// True when this controller built the sinks itself (the legacy Android
  /// fallback). Sinks handed in by `desktopLyricsSinksProvider` are owned by
  /// that provider and have to survive this controller.
  final bool _ownsSinks;

  final List<ProviderSubscription> _subscriptions = [];
  final List<StreamSubscription> _nativeSubscriptions = [];
  final Map<LyricsOverlaySink, String> _configuredSignatures =
      <LyricsOverlaySink, String>{};
  FloatingLyricsPayload? _lastPayload;
  String? _lastNativeSignature;
  String? _lastTaskbarSignature;
  int _syncGeneration = 0;
  int _frameRevision = 0;
  bool _floatingVisible = false;
  bool _taskbarVisible = false;
  Timer? _sweepTimer;
  late final LyricsProgressEstimator _positionEstimator;
  late final PlayedProgressRate _progressRate;

  FloatingLyricsSyncController(
    this._ref, {
    FloatingLyricsService? service,
    DateTime Function()? now,
    List<LyricsOverlaySink>? sinks,
  }) : _service = service ?? FloatingLyricsService.instance,
       _now = now ?? DateTime.now,
       _ownsSinks = sinks == null || sinks.isEmpty,
       _sinks = _resolveSinks(
         service ?? FloatingLyricsService.instance,
         sinks,
       ) {
    _positionEstimator = LyricsProgressEstimator(now: _now);
    _progressRate = PlayedProgressRate();
    _subscriptions.add(
      _ref.listen<FloatingLyricsSettings>(
        floatingLyricsProvider,
        (previous, next) => unawaited(sync()),
      ),
    );
    _subscriptions.add(
      _ref.listen<TaskbarLyricsSettings>(
        taskbarLyricsProvider,
        (previous, next) => unawaited(sync()),
      ),
    );
    _subscriptions.add(
      _ref.listen<Duration>(
        playerProvider.select((state) => state.position),
        (previous, next) => unawaited(sync()),
      ),
    );
    // The overlay must follow the manual calibration exactly like the in-app
    // player does. Without this listener a calibration made while playback is
    // paused would not reach the overlay until the position ticked again.
    _subscriptions.add(
      _ref.listen<Duration>(
        lyricsOffsetProvider,
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
    // A track change must push the new metadata (title/artist/cover) even when
    // the position has not ticked yet — the taskbar hover card reads it.
    _subscriptions.add(
      _ref.listen<String?>(
        playerProvider.select((state) => state.currentSong?.id),
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
        _floatingVisible = false;
        // Stop the 200 ms sweep BEFORE the first await, synchronously. Between
        // the native close and setEnabled(false) actually landing there is a
        // window in which a sweep tick would run sync() and push another
        // update, re-creating the window the user just closed (the
        // addView/removeView churn). Stopping the clock here fixes that at its
        // source — the native side deliberately no longer latches on hide,
        // because a latch that only show() can clear never reopens (Dart never
        // calls show).
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

  static List<LyricsOverlaySink> _resolveSinks(
    FloatingLyricsService service,
    List<LyricsOverlaySink>? sinks,
  ) {
    if (sinks != null && sinks.isNotEmpty) {
      return List<LyricsOverlaySink>.unmodifiable(sinks);
    }
    // No explicit sinks: this is the legacy Android overlay path (also what a
    // bare controller in tests uses).
    return List<LyricsOverlaySink>.unmodifiable(<LyricsOverlaySink>[
      AndroidFloatingLyricsSink(service),
    ]);
  }

  List<LyricsOverlaySink> get _floatingSinks => _sinks
      .where((sink) => sink.surface == LyricsSurface.floating)
      .toList(growable: false);

  List<LyricsOverlaySink> get _taskbarSinks => _sinks
      .where((sink) => sink.surface == LyricsSurface.taskbar)
      .toList(growable: false);

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

  /// The same frame the two Windows windows paint
  /// (docs/desktop-lyrics-protocol.md, section 2.1).
  static LyricsOverlayFrame frameFor(
    LyricsDocument? document,
    Duration position, {
    Duration? highlightPosition,
    Duration songDuration = Duration.zero,
    bool isPlaying = false,
    bool hasSong = false,
    int revision = 0,
    String? songTitle,
    String? artistName,
    String? albumName,
    String? coverUrl,
  }) {
    final progress = _songProgress(position, songDuration);
    if (document == null || document.lines.isEmpty) {
      return LyricsOverlayFrame(
        text: '',
        progress: progress,
        isPlaying: isPlaying,
        hasSong: hasSong,
        revision: revision,
        songTitle: songTitle,
        artistName: artistName,
        albumName: albumName,
        coverUrl: coverUrl,
      );
    }
    final lines = document.lines;
    final index = currentLyricLineIndex(lines, position);
    if (index < 0) {
      return LyricsOverlayFrame(
        text: '',
        progress: progress,
        isPlaying: isPlaying,
        hasSong: hasSong,
        revision: revision,
        songTitle: songTitle,
        artistName: artistName,
        albumName: albumName,
        coverUrl: coverUrl,
      );
    }
    final active = lines[index];
    final nextIndex = _nextVisibleIndex(lines, index);
    final next = nextIndex >= 0 ? lines[nextIndex] : null;
    return LyricsOverlayFrame(
      text: active.text,
      translation: active.translation,
      nextText: next?.text ?? '',
      nextTranslation: next?.translation,
      lineIndex: index,
      progress: progress,
      highlightProgress: playedFraction(
        active,
        highlightPosition ?? position,
        nextTimestamp: next?.timestamp,
      ),
      wordSegments: wordSegmentsFor(active, next),
      isPlaying: isPlaying,
      hasSong: hasSong,
      revision: revision,
      songTitle: songTitle,
      artistName: artistName,
      albumName: albumName,
      coverUrl: coverUrl,
    );
  }

  /// Cumulative word-boundary table for the native sweep (max 32 entries).
  static List<double>? wordSegmentsFor(LyricsLine line, LyricsLine? next) {
    final words = line.words;
    if (words == null || words.isEmpty) return null;
    final start = line.timestamp;
    final end = (next != null && next.timestamp > start)
        ? next.timestamp
        : start + _fallbackLineDuration;
    final span = (end - start).inMilliseconds;
    if (span <= 0) return null;
    final segments = <double>[];
    for (final word in words) {
      final boundary =
          (word.start + word.duration - start).inMilliseconds / span;
      segments.add(boundary.clamp(0.0, 1.0).toDouble());
      if (segments.length == LyricsOverlayFrame.maxWordSegments) break;
    }
    return segments;
  }

  static double _songProgress(Duration position, Duration duration) {
    if (duration <= Duration.zero) return 0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
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
      _sweepTimer = Timer.periodic(_sweepInterval, (_) => unawaited(sync()));
    } else if (!running && _sweepTimer != null) {
      _sweepTimer!.cancel();
      _sweepTimer = null;
    }
  }

  /// Guards against overlapping native round trips.
  ///
  /// Five listeners (floating settings / taskbar settings / position /
  /// isPlaying / lyrics) plus the 200 ms sweep timer can all call this within
  /// the same frame. Each call used to run canDrawOverlays() **and** update()
  /// over the platform channel — on Android that channel runs on the same
  /// thread as the UI — so a burst queued up more round trips than the overlay
  /// could drain, and the queue itself kept the main thread busy.
  ///
  /// Now at most one call is in flight, and a burst collapses into a single
  /// follow-up. Nothing is lost by collapsing: the follow-up reads the
  /// current state rather than a queued snapshot.
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
      // flip, so a caller arriving in the middle always lands in _syncQueued
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
    final taskbarSettings = _ref.read(taskbarLyricsProvider);
    final floatingEnabled = settings.enabled;
    final taskbarEnabled = taskbarSettings.enabled;
    if (!floatingEnabled && !taskbarEnabled) {
      _updateSweepTimer(running: false);
      _progressRate.reset();
      _lastPayload = null;
      _lastNativeSignature = null;
      _lastTaskbarSignature = null;
      await _hideAll();
      return;
    }

    final lyrics = _ref.read(lyricsProvider).valueOrNull;
    if (lyrics == null || lyrics.lines.isEmpty) {
      _updateSweepTimer(running: false);
      _progressRate.reset();
      _lastNativeSignature = null;
      _lastTaskbarSignature = null;
      return;
    }
    final playerState = _ref.read(playerProvider);
    _updateSweepTimer(
      running: playerState.isPlaying && playerState.currentSong != null,
    );
    // Same shift the player page applies (position + offset), through the one
    // shared definition, so the overlay can never pick a different line.
    final lyricsOffset = _ref.read(lyricsOffsetProvider);
    final position = applyLyricsOffset(playerState.position, lyricsOffset);
    final estimated = applyLyricsOffset(
      _estimatedPosition(playerState),
      lyricsOffset,
    );
    final basePayload = payloadForPosition(
      lyrics,
      position,
      highlightPosition: estimated,
    );
    if (basePayload.text.trim().isEmpty &&
        (basePayload.translation?.trim().isEmpty ?? true)) {
      _lastNativeSignature = null;
      _lastTaskbarSignature = null;
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

    final song = playerState.currentSong;
    final revision = _frameRevision + 1;
    final frame = frameFor(
      lyrics,
      position,
      highlightPosition: estimated,
      songDuration: playerState.duration,
      isPlaying: playerState.isPlaying,
      hasSong: song != null,
      revision: revision,
      songTitle: song?.name,
      artistName: song?.artistNames,
      albumName: song?.album?.name,
      coverUrl: song?.coverUrl,
    ).copyWith(highlightRate: payload.highlightRate);
    var pushedAny = false;

    if (!floatingEnabled) {
      _lastNativeSignature = null;
      if (_floatingVisible) {
        for (final sink in _floatingSinks) {
          await sink.hide();
        }
        _floatingVisible = false;
      }
    } else if (_floatingSinks.isNotEmpty) {
      final signature = _nativeSignature(frame, settings);
      if (_lastNativeSignature != signature) {
        final available = await _ensureFloatingAvailable();
        if (syncGeneration != _syncGeneration) return;
        if (available) {
          final latestSettings = _ref.read(floatingLyricsProvider);
          if (!latestSettings.enabled) {
            _updateSweepTimer(running: false);
            _lastPayload = null;
            await _hideAll();
            return;
          }
          final config = latestSettings.toOverlayConfig();
          final pushed = await _pushFloating(frame, config);
          if (syncGeneration == _syncGeneration) {
            _lastNativeSignature = signature;
            if (pushed) {
              _floatingVisible = true;
              pushedAny = true;
            }
          }
        }
      }
    }

    if (!taskbarEnabled) {
      _lastTaskbarSignature = null;
      if (_taskbarVisible) {
        for (final sink in _taskbarSinks) {
          await sink.hide();
        }
        _taskbarVisible = false;
      }
    } else if (_taskbarSinks.isNotEmpty) {
      final config = taskbarSettings.toOverlayConfig();
      final signature = _taskbarSignature(frame, config);
      if (_lastTaskbarSignature != signature) {
        final pushed = await _pushTaskbar(frame, config);
        if (syncGeneration == _syncGeneration) {
          _lastTaskbarSignature = signature;
          if (pushed) {
            _taskbarVisible = true;
            pushedAny = true;
          }
        }
      }
    }

    if (pushedAny && syncGeneration == _syncGeneration) {
      _frameRevision = revision;
    }
  }

  Future<bool> _ensureFloatingAvailable() async {
    final sinks = _floatingSinks;
    if (sinks.isEmpty) return false;
    for (final sink in sinks) {
      if (!await sink.ensureAvailable()) return false;
    }
    return true;
  }

  Future<bool> _pushFloating(
    LyricsOverlayFrame frame,
    LyricsOverlayConfig config,
  ) async {
    var pushed = false;
    final configSignature = _jsonSignature(config.toJson());
    for (final sink in _floatingSinks) {
      if (_configuredSignatures[sink] != configSignature) {
        final configured = await sink.configure(config);
        if (configured) {
          _configuredSignatures[sink] = configSignature;
        }
      }
      if (await sink.update(frame, config)) pushed = true;
    }
    return pushed;
  }

  Future<bool> _pushTaskbar(
    LyricsOverlayFrame frame,
    LyricsOverlayConfig config,
  ) async {
    var pushed = false;
    final configSignature = _jsonSignature(config.toJson());
    for (final sink in _taskbarSinks) {
      if (_configuredSignatures[sink] != configSignature) {
        final configured = await sink.configure(config);
        if (configured) {
          _configuredSignatures[sink] = configSignature;
        }
      }
      if (await sink.update(frame, config)) pushed = true;
    }
    return pushed;
  }

  Future<void> _hideAll() async {
    for (final sink in _floatingSinks) {
      await sink.hide();
    }
    _floatingVisible = false;
    if (_taskbarVisible) {
      for (final sink in _taskbarSinks) {
        await sink.hide();
      }
      _taskbarVisible = false;
    }
  }

  /// Plays one animation preview on every surface that supports it.
  ///
  /// Returns false when no native window is listening, which is what the
  /// lyrics studio uses to decide whether the in-app preview is the only one.
  Future<bool> preview(LyricsPreviewRequest request) async {
    var handled = false;
    for (final sink in _sinks) {
      if (!sink.supportsPreview) continue;
      // Preview bypasses the playback loop, so push the current style first:
      // otherwise the native window shows its default size/font instead of the
      // one the user is editing in the studio.
      final config = sink.surface == LyricsSurface.floating
          ? _ref.read(floatingLyricsProvider).toOverlayConfig()
          : _ref.read(taskbarLyricsProvider).toOverlayConfig();
      await sink.configure(config);
      if (await sink.preview(request)) handled = true;
    }
    return handled;
  }

  FloatingLyricsPayload? get lastPayloadForTest => _lastPayload;

  /// Last revision handed to a native window; tests assert it only grows.
  int get frameRevisionForTest => _frameRevision;

  void dispose() {
    _updateSweepTimer(running: false);
    for (final sub in _subscriptions) {
      sub.close();
    }
    for (final sub in _nativeSubscriptions) {
      unawaited(sub.cancel());
    }
    // Only the fallback Android sink belongs to this controller. The Windows
    // sinks are cached by desktopLyricsSinksProvider and shared with the
    // taskbar status notifier, so disposing them here would leave that one
    // holding a closed event stream.
    if (_ownsSinks) {
      for (final sink in _sinks) {
        unawaited(sink.dispose());
      }
    }
  }

  static String _nativeSignature(
    LyricsOverlayFrame frame,
    FloatingLyricsSettings settings,
  ) {
    return <Object?>[
      frame.text,
      frame.translation ?? '',
      frame.nextText,
      frame.nextTranslation ?? '',
      frame.lineIndex,
      frame.progress,
      frame.highlightProgress,
      frame.highlightRate,
      (frame.wordSegments ?? const <double>[]).join(','),
      frame.isPlaying,
      frame.hasSong,
      frame.songTitle ?? '',
      frame.artistName ?? '',
      frame.albumName ?? '',
      frame.coverUrl ?? '',
      _settingsSignature(settings),
    ].join('\u001f');
  }

  static String _taskbarSignature(
    LyricsOverlayFrame frame,
    LyricsOverlayConfig config,
  ) {
    return <Object?>[
      frame.text,
      frame.translation ?? '',
      frame.nextText,
      frame.nextTranslation ?? '',
      frame.lineIndex,
      frame.progress,
      frame.highlightProgress,
      frame.highlightRate,
      frame.isPlaying,
      frame.hasSong,
      // The strip's hover card reads the metadata, so a track change is a
      // frame change even when no lyric line moved.
      frame.songTitle ?? '',
      frame.artistName ?? '',
      frame.albumName ?? '',
      frame.coverUrl ?? '',
      _jsonSignature(config.toJson()),
    ].join('\u001f');
  }

  static String _settingsSignature(FloatingLyricsSettings settings) {
    final json = settings.toJson();
    // positionY is deliberately excluded: the Android window owns the live
    // vertical offset and only reads the persisted value when it (re)creates
    // the overlay, so persisting a drag must not trigger another update.
    json.remove('positionY');
    return _jsonSignature(json);
  }

  static String _jsonSignature(Map<String, Object?> json) {
    return json.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('\u001f');
  }
}

/// How often the played-progress highlight is re-evaluated while playing. The
/// player state itself only advances once per second, so this driver keeps the
/// sweep smooth using [LyricsProgressEstimator].
const _sweepInterval = Duration(milliseconds: 200);

/// Line span assumed when the next line is unknown, same as [playedFraction].
const _fallbackLineDuration = Duration(seconds: 4);
