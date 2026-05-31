import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

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
    await _save(state.copyWith(enabled: enabled));
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
  final List<ProviderSubscription> _subscriptions = [];
  final List<StreamSubscription> _nativeSubscriptions = [];
  FloatingLyricsPayload? _lastPayload;
  String? _lastNativeSignature;
  int _syncGeneration = 0;

  FloatingLyricsSyncController(this._ref, {FloatingLyricsService? service})
    : _service = service ?? FloatingLyricsService.instance {
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
        await _service.hide();
        await _ref.read(floatingLyricsProvider.notifier).setEnabled(false);
      }),
    );
    _nativeSubscriptions.add(
      _service.lockChangedStream.listen((isLocked) async {
        await _ref.read(floatingLyricsProvider.notifier).setLocked(isLocked);
      }),
    );
  }

  static FloatingLyricsPayload payloadForPosition(
    LyricsDocument? document,
    Duration position,
  ) {
    if (document == null || document.lines.isEmpty) {
      return const FloatingLyricsPayload(text: '');
    }

    LyricsLine? active;
    LyricsLine? firstVisible;
    for (final line in document.lines) {
      if (!_hasVisibleText(line)) continue;
      firstVisible ??= line;
      if (line.timestamp > position) break;
      active = line;
    }
    active ??= firstVisible;
    if (active == null) {
      return const FloatingLyricsPayload(text: '');
    }

    return FloatingLyricsPayload(
      text: active.text,
      translation: active.translation,
    );
  }

  static bool _hasVisibleText(LyricsLine line) {
    return line.text.trim().isNotEmpty ||
        (line.translation?.trim().isNotEmpty ?? false);
  }

  Future<void> sync() async {
    final syncGeneration = ++_syncGeneration;
    final settings = _ref.read(floatingLyricsProvider);
    if (!settings.enabled) {
      _lastPayload = null;
      _lastNativeSignature = null;
      await _service.hide();
      return;
    }

    final lyrics = _ref.read(lyricsProvider).valueOrNull;
    if (lyrics == null || lyrics.lines.isEmpty) {
      _lastNativeSignature = null;
      return;
    }
    final position = _ref.read(playerProvider).position;
    final payload = payloadForPosition(lyrics, position);
    if (payload.text.trim().isEmpty &&
        (payload.translation?.trim().isEmpty ?? true)) {
      _lastNativeSignature = null;
      return;
    }
    _lastPayload = payload;
    final signature = _nativeSignature(payload, settings);
    if (_lastNativeSignature == signature) return;

    final hasPermission = await _service.canDrawOverlays();
    if (syncGeneration != _syncGeneration) return;
    if (!hasPermission) return;
    final latestSettings = _ref.read(floatingLyricsProvider);
    if (!latestSettings.enabled) {
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
      settings.textColor.toARGB32(),
      settings.highlightColor.toARGB32(),
      settings.backgroundColor.toARGB32(),
      settings.fontSize,
      settings.strokeWidth,
      settings.shadowOpacity,
      settings.width,
      settings.height,
      settings.isLocked,
    ].join('\u001f');
  }
}
