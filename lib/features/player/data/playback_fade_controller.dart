part of '../presentation/providers/player_provider.dart';

/// 淡入淡出 / 音量 / 播放选项（倍速、跳过静音、A-B 循环）。
///
/// 本文件是 `PlayerNotifier` 的 `part`（见 player_provider.dart 顶部拆分地图），
/// 不是独立模块：淡入淡出直接读写 facade 的音量与 generation 字段。

extension PlayerFadeAndVolumeOps on PlayerNotifier {
  void setFadeOptions({required bool enabled, required Duration duration}) {
    _fadeEnabled = enabled;
    _fadeGeneration++;
    _fadeDuration = duration <= Duration.zero
        ? Duration.zero
        : Duration(milliseconds: duration.inMilliseconds.clamp(200, 3000));
    if (!enabled) {
      unawaited(_safeSetVolume(1));
    }
  }

  Future<void> applyEqualizerSettings(AudioEffectsSettings settings) async {
    // Remembered so `_recreatePlayer` can push the same curve to the brand new
    // controller: a recreated player starts with the equalizer disabled.
    _lastEqualizerSettings = settings;
    try {
      await _ensureAudioController()
          .applyEqualizer(
            enabled: settings.equalizerEnabled,
            bandGains: settings.effectiveEqualizerBandGains,
          )
          .timeout(const Duration(milliseconds: 300));
    } catch (e, s) {
      debugPrint('PlayerNotifier applyEqualizer failed: $e');
      DiagnosticsService.instance.recordError(
        'player.equalizer',
        e,
        s,
        data: {'enabled': settings.equalizerEnabled},
      );
    }
  }

  /// Whether the current backend can change playback speed.
  bool get supportsPlaybackSpeed =>
      _ensureAudioController() is PlaybackSpeedCapable;

  /// Whether the current backend can skip silent passages.
  bool get supportsSkipSilence =>
      _ensureAudioController() is SkipSilenceCapable;

  /// Sets the playback speed, clamped to a sane range.
  ///
  /// Not routed through [_AudioMutex]: like the volume writes this is a single
  /// property write, not part of the stop/setUrl/seek/play transport sequence
  /// the mutex exists to serialize.
  Future<void> setPlaybackSpeed(double speed) async {
    final clamped = speed.clamp(0.5, 2.0).toDouble();
    final controller = _ensureAudioController();
    if (controller is! PlaybackSpeedCapable) {
      _setState(_s.copyWith(error: () => '当前播放后端不支持倍速播放'));
      return;
    }
    // 显式转换：Dart 不会把 PlayerAudioController 提升为不相关的接口类型。
    final speedController = controller as PlaybackSpeedCapable;
    try {
      await speedController
          .setPlaybackSpeed(clamped)
          .timeout(_audioOperationTimeout);
      _setState(_s.copyWith(playbackSpeed: clamped, error: () => null));
      _schedulePlaybackMemorySave();
    } catch (e, s) {
      DiagnosticsService.instance.recordError(
        'player.setPlaybackSpeed',
        e,
        s,
        data: {'speed': clamped},
      );
      _setState(_s.copyWith(error: () => '设置倍速失败：${_userFacingError(e)}'));
    }
  }

  Future<void> setSkipSilence(bool enabled) async {
    final controller = _ensureAudioController();
    if (controller is! SkipSilenceCapable) {
      _setState(_s.copyWith(error: () => '当前播放后端不支持跳过静音'));
      return;
    }
    final skipSilenceController = controller as SkipSilenceCapable;
    try {
      await skipSilenceController
          .setSkipSilence(enabled)
          .timeout(_audioOperationTimeout);
      _setState(_s.copyWith(skipSilence: enabled, error: () => null));
      _schedulePlaybackMemorySave();
    } catch (e, s) {
      DiagnosticsService.instance.recordError(
        'player.setSkipSilence',
        e,
        s,
        data: {'enabled': enabled},
      );
      _setState(_s.copyWith(error: () => '设置跳过静音失败：${_userFacingError(e)}'));
    }
  }

  /// Marks the start of an A-B loop at [position] (defaults to the current
  /// playback position).
  void setAbLoopStart([Duration? position]) {
    final start = position ?? _s.position;
    final end = _s.abLoopEnd;
    if (end != null && end <= start) {
      // 新的 A 落在 B 之后：丢弃已经无效的 B 而不是留下一个空区间。
      _setState(_s.copyWith(abLoopStart: () => start, abLoopEnd: () => null));
      _schedulePlaybackMemorySave();
      return;
    }
    _setState(_s.copyWith(abLoopStart: () => start));
    _schedulePlaybackMemorySave();
  }

  void setAbLoopEnd([Duration? position]) {
    final end = position ?? _s.position;
    final start = _s.abLoopStart;
    if (start == null || end <= start) {
      _setState(_s.copyWith(error: () => 'B 点必须晚于 A 点'));
      return;
    }
    _setState(_s.copyWith(abLoopEnd: () => end, error: () => null));
    _schedulePlaybackMemorySave();
  }

  void clearAbLoop() {
    if (!_s.hasAbLoop && _s.abLoopStart == null) return;
    _setState(_s.copyWith(abLoopStart: () => null, abLoopEnd: () => null));
    _schedulePlaybackMemorySave();
  }

  void _enforceAbLoop(Duration position) {
    final start = _s.abLoopStart;
    final end = _s.abLoopEnd;
    if (start == null || end == null) return;
    if (position < end) return;
    if (_isSeekingAbLoop) return;
    _isSeekingAbLoop = true;
    unawaited(
      _safeSeek(start).whenComplete(() => _isSeekingAbLoop = false),
    );
  }

  Future<void> _safeSetVolume(double volume) async {
    final target = volume.clamp(0.0, 1.0);
    try {
      await _ensureAudioController()
          .setVolume(target)
          .timeout(const Duration(milliseconds: 300));
      _lastVolumeWriteAt = _now();
      DiagnosticsService.instance.record(
        'player',
        'volume_set',
        data: {'volume': target},
      );
    } catch (e, s) {
      debugPrint('PlayerNotifier setVolume failed: $e');
      DiagnosticsService.instance.recordError(
        'player.setVolume',
        e,
        s,
        data: {'volume': target},
      );
    }
  }

  Future<void> _runFade({
    required double from,
    required double to,
    required int generation,
  }) async {
    if (!_fadeEnabled) return;
    if (generation != _fadeGeneration) return;
    if (from == to) {
      await _safeSetVolume(to);
      return;
    }
    if (_fadeDuration == Duration.zero) {
      await _safeSetVolume(to);
      return;
    }
    const steps = 6;
    await _safeSetVolume(from);
    final stepDelay = Duration(
      milliseconds: max(1, _fadeDuration.inMilliseconds ~/ steps),
    );
    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(stepDelay);
      if (generation != _fadeGeneration) return;
      final value = from + ((to - from) * i / steps);
      await _safeSetVolume(value);
    }
  }

  int _cancelActiveFades() => ++_fadeGeneration;

  bool _shouldHandleCompletedEvent() {
    if (_s.isTransitioning || _s.currentSong == null) {
      DiagnosticsService.instance.record(
        'player',
        'ignored_completed_event',
        data: {
          'reason': _s.isTransitioning ? 'transitioning' : 'no_song',
          'song_id': _s.currentSong?.id,
          'position_ms': _s.position.inMilliseconds,
          'duration_ms': _s.duration.inMilliseconds,
        },
      );
      return false;
    }

    final effectiveDuration = _s.duration == Duration.zero
        ? _s.currentSong!.duration
        : _s.duration;
    const tolerance = Duration(seconds: 3);
    if (effectiveDuration > tolerance &&
        _s.position + tolerance < effectiveDuration) {
      DiagnosticsService.instance.record(
        'player',
        'ignored_completed_event',
        data: {
          'reason': 'before_end',
          'song_id': _s.currentSong?.id,
          'position_ms': _s.position.inMilliseconds,
          'duration_ms': effectiveDuration.inMilliseconds,
        },
      );
      return false;
    }

    return true;
  }

  /// Fades the current playback out and then pauses it.
  ///
  /// Used by the sleep timer: the previous implementation called `pause()`
  /// abruptly, cutting the audio mid-note. The ramp is written directly rather
  /// than reusing [_runFade] because that helper no-ops unless the user turned
  /// the regular fade-in/out setting on, and the sleep fade must always happen.
  Future<void> fadeOutAndPause({
    Duration duration = const Duration(milliseconds: 1500),
  }) async {
    return _mutex.run(() async {
      try {
        final controller = _ensureAudioController();
        if (!controller.playing) return;
        final generation = _cancelActiveFades();
        _isSleepFadingOut = true;
        await _rampVolume(
          from: controller.volume.clamp(0.0, 1.0),
          to: 0,
          duration: duration,
          generation: generation,
        );
        if (generation != _fadeGeneration) return;
        await controller.pause().timeout(_audioOperationTimeout);
        _setState(_s.copyWith(isPlaying: false));
        _resetPlaybackHealthWindow(applyGrace: false);
        // 淡出到 0 后把播放器音量复位，否则下一次播放会静音。
        await _safeSetVolume(1);
      } catch (e, s) {
        debugPrint('fadeOutAndPause failed: $e');
        DiagnosticsService.instance.recordError('player.fadeOutAndPause', e, s);
        await _recreatePlayer();
      } finally {
        _isSleepFadingOut = false;
      }
    }, label: 'fadeOutAndPause');
  }

  Future<void> _rampVolume({
    required double from,
    required double to,
    required Duration duration,
    required int generation,
  }) async {
    if (generation != _fadeGeneration) return;
    if (from == to || duration <= Duration.zero) {
      await _safeSetVolume(to);
      return;
    }
    const steps = 6;
    final stepDelay = Duration(
      milliseconds: max(1, duration.inMilliseconds ~/ steps),
    );
    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(stepDelay);
      if (generation != _fadeGeneration) return;
      await _safeSetVolume(from + ((to - from) * i / steps));
    }
  }

  void _schedulePlaybackVolumeRecovery(int generation) {
    if (!_fadeEnabled) return;
    final delay = _fadeDuration + const Duration(milliseconds: 150);
    Timer(delay, () {
      if (!mounted || generation != _fadeGeneration || !_s.isPlaying) {
        return;
      }
      unawaited(_safeSetVolume(1));
    });
  }

}
