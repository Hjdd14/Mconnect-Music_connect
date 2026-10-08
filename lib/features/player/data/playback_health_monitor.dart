part of '../presentation/providers/player_provider.dart';

/// 播放健康监测、卡死看门狗、停滞自愈、音量守护，以及串行化传输的 `_AudioMutex`。
///
/// 本文件是 `PlayerNotifier` 的 `part`（见 player_provider.dart 顶部拆分地图），
/// 不是独立模块：看门狗读的是 facade 的字段与 `state`。

/// Simple async mutex to serialize audio operations and prevent platform channel deadlocks.
///
/// It stays the **single** serialization point (running transport calls
/// concurrently is what deadlocks just_audio's platform channel), but it is no
/// longer unbounded: a wedged holder used to block every later tap at
/// `await prev` forever, which is exactly the "app freezes, must be force-killed"
/// chain from the device logs (frozen `position_ms`, `is_playing:false`,
/// six process restarts in eight minutes).
class _AudioMutex {
  _AudioMutex({
    this.onWedged,
    this.waitTimeout = const Duration(seconds: 8),
    this.maxPending = 8,
  });

  /// Invoked (fire-and-forget) when waiting for the previous holder timed out.
  final void Function(String label, int waitedMs)? onWedged;

  /// How long a waiter may block on the previous holder before it gives up and
  /// runs its own operation anyway. Every inner await of a healthy operation is
  /// bounded by its own timeout (≤10s), so exceeding this means a wedge.
  final Duration waitTimeout;

  /// Upper bound on queued waiters. Past it a waiter stops waiting (and a
  /// diagnostic is recorded) instead of growing an unbounded chain.
  final int maxPending;

  Future<void>? _last;
  int _pending = 0;

  @visibleForTesting
  int get pendingCount => _pending;

  Future<T> run<T>(Future<T> Function() fn, {String label = 'audio'}) async {
    final completer = Completer<void>();
    final prev = _last;
    _last = completer.future;
    // The `try` (and therefore the `finally`) covers everything after the
    // completer is published: a synchronous throw can no longer leave
    // `_last` pointing at a future that is never completed, which used to
    // strand every subsequent waiter forever.
    final wait = Stopwatch()..start();
    _pending++;
    try {
      if (prev != null) {
        if (_pending > maxPending) {
          // 队列超出上界：不再等待，直接执行本次操作并记诊断。
          // （无法"踢掉"已经在 await 上的最老等待者；而它的等待本身也会先于
          // 本调用被 waitTimeout 解开，所以这里放弃等待即可给队列封顶。）
          DiagnosticsService.instance.record(
            'slow_operation',
            'audio_mutex_overflow',
            data: {
              'label': label,
              'pending': _pending,
              'max_pending': maxPending,
            },
          );
        } else {
          try {
            await prev.timeout(waitTimeout);
          } on TimeoutException {
            DiagnosticsService.instance.record(
              'player',
              'audio_mutex_wedged',
              data: {
                'label': label,
                'waited_ms': wait.elapsedMilliseconds,
                'timeout_ms': waitTimeout.inMilliseconds,
              },
            );
            onWedged?.call(label, wait.elapsedMilliseconds);
          }
        }
      }
      if (kDebugMode && wait.elapsedMilliseconds > 100) {
        debugPrint('AudioMutex[$label] waited ${wait.elapsedMilliseconds}ms');
      }
      if (wait.elapsedMilliseconds > 500) {
        DiagnosticsService.instance.record(
          'slow_operation',
          'audio_mutex_wait',
          data: {'label': label, 'elapsed_ms': wait.elapsedMilliseconds},
        );
      }
      return await fn();
    } finally {
      _pending--;
      if (!completer.isCompleted) completer.complete();
    }
  }
}

extension PlayerPlaybackHealthOps on PlayerNotifier {
  void _startPlaybackHealthMonitor() {
    if (!PlatformUtils.isAndroid) return;
    if (_playbackHealthCheckInterval <= Duration.zero) return;
    _playbackHealthTimer = Timer.periodic(
      _playbackHealthCheckInterval,
      (_) => unawaited(_checkPlaybackHealth()),
    );
  }

  @visibleForTesting
  Future<void> runPlaybackHealthCheckForTest() => _checkPlaybackHealth();

  @visibleForTesting
  Future<void> runStuckWatchdogForTest() => _checkStuckTransport();

  /// True while any transport-level flag is latched.
  @visibleForTesting
  bool get isTransportBusyForTest =>
      _s.isTransitioning ||
      _isSwitchingQuality ||
      _isRecoveringPlayback ||
      _restoredSourceNeedsLoad;

  // --- 卡死看门狗（独立于 12s 转场看门狗） -------------------------------
  //
  // 与 12s 停滞自愈的区别：后者只服务"Android + isPlaying + 在线歌曲"的
  // 位置停滞，而真机日志里的死法是 `is_playing:false` + 位置冻住 —— 那时
  // `_canCheckPlaybackHealth` 与新加的 `_ensurePlaybackVolume` 都因为
  // `isPlaying` 为假而永不触发。因此这条看门狗**不以 isPlaying 为前提**：
  // 只要"有当前曲目 + 处于过渡/换音质/恢复中 + 超过阈值没有任何位置或状态
  // 推进"，就强制把播放面复位到可用状态。

  void _startStuckWatchdog() {
    if (_stuckWatchdogInterval <= Duration.zero) return;
    _stuckWatchdogTimer = Timer.periodic(
      _stuckWatchdogInterval,
      (_) => unawaited(_checkStuckTransport()),
    );
  }

  bool _isTransportSuspicious() {
    if (_s.currentSong == null) return false;
    return _s.isTransitioning ||
        _isSwitchingQuality ||
        _isRecoveringPlayback ||
        _restoredSourceNeedsLoad;
  }

  Future<void> _checkStuckTransport() async {
    if (!mounted || _isForcingReset) return;
    if (!_isTransportSuspicious()) {
      // 正常播放（或空闲）：重新起算，避免把长时间的普通播放当成卡死。
      _markTransportProgress();
      return;
    }
    final last = _lastTransportProgressAt;
    if (last == null) {
      _markTransportProgress();
      return;
    }
    if (_now().difference(last) < _stuckWatchdogThreshold) return;
    await _forceResetStuckPlayback('transport_stuck');
  }

  /// 强制把播放面复位到"可再次操作"的状态。
  ///
  /// 由看门狗或 [_AudioMutex] 超时触发（两者都可能发生在**没有**持锁的情况下，
  /// 所以这里绝不进入 `_AudioMutex` —— 那正是卡死的源头）。复位会推进两个代际
  /// 令牌，让所有在途的陈旧分支在下一个守卫处立刻退出。
  Future<void> _forceResetStuckPlayback(String reason) async {
    if (!mounted || _isForcingReset) return;
    _isForcingReset = true;
    try {
      final song = _s.currentSong;
      DiagnosticsService.instance.record(
        'player',
        'player_forced_reset',
        data: {
          'reason': reason,
          'song_id': song?.id,
          'platform': song?.platform.name,
          'is_playing': _s.isPlaying,
          'is_transitioning': _s.isTransitioning,
          'is_switching_quality': _isSwitchingQuality,
          'is_recovering': _isRecoveringPlayback,
          'restored_source_needs_load': _restoredSourceNeedsLoad,
          'position_ms': _s.position.inMilliseconds,
        },
      );
      _playRequestId++;
      _qualityRequestId++;
      _isSwitchingQuality = false;
      _isRecoveringPlayback = false;
      _restoredSourceNeedsLoad = false;
      _cancelTransitionWatchdog();
      _setState(
        _s.copyWith(
          isTransitioning: false,
          error: () => '播放未能恢复，已重置播放器，请重试',
        ),
      );
      _resetPlaybackHealthWindow(applyGrace: true);
      await _recreatePlayer();
    } finally {
      _isForcingReset = false;
      _markTransportProgress();
    }
  }

  void _onAudioMutexWedged(String label, int waitedMs) {
    debugPrint(
      'PlayerNotifier: audio mutex wedged on "$label" after ${waitedMs}ms, forcing reset',
    );
    unawaited(_forceResetStuckPlayback('audio_mutex_wedged:$label'));
  }

  /// Whether a controller instance is still referenced. `dispose()` must leave
  /// this false so nothing can resurrect the disposed platform channel.
  @visibleForTesting
  bool get hasAudioControllerForTest => _audioController != null;

  String? _songKey(Song? song) =>
      song == null ? null : '${song.platform.name}:${song.id}';

  bool _isOnlineSong(Song song) => song.platform != PlatformType.local;

  bool _isNearPlaybackEnd() {
    final song = _s.currentSong;
    if (song == null) return true;
    final effectiveDuration = _s.duration == Duration.zero
        ? song.duration
        : _s.duration;
    if (effectiveDuration == Duration.zero) return false;
    return _s.position + PlayerNotifier._playbackEndTolerance >= effectiveDuration;
  }

  bool _isStalledProcessingState(ProcessingState processingState) {
    return processingState == ProcessingState.idle ||
        processingState == ProcessingState.loading ||
        processingState == ProcessingState.buffering;
  }

  bool _samePlaybackHealthFingerprint() {
    return _healthSongKey == _songKey(_s.currentSong) &&
        _healthPlayRequestId == _playRequestId &&
        _healthQualityRequestId == _qualityRequestId;
  }

  void _resetPlaybackRecoveryIfSongChanged(String? songKey) {
    if (_recoverySongKey == songKey) return;
    _recoverySongKey = songKey;
    _recoveryAttemptsForSong = 0;
    _recoveryLimitReportedSongKey = null;
  }

  void _resetPlaybackHealthWindow({
    bool applyGrace = true,
    bool resetRecoveryAttempts = false,
  }) {
    final now = _now();
    final songKey = _songKey(_s.currentSong);
    _healthSongKey = songKey;
    _healthPlayRequestId = _playRequestId;
    _healthQualityRequestId = _qualityRequestId;
    _lastPlaybackHealthPosition = _s.position;
    _lastPlaybackHealthPositionChangedAt = now;
    _lastProcessingStateChangedAt = now;
    _playbackHealthGraceUntil =
        applyGrace && _playbackStartupGracePeriod > Duration.zero
        ? now.add(_playbackStartupGracePeriod)
        : null;
    if (resetRecoveryAttempts) {
      _recoverySongKey = songKey;
      _recoveryAttemptsForSong = 0;
      _recoveryLimitReportedSongKey = null;
    }
  }

  void _observePlaybackHealthPosition(Duration position) {
    if (position + PlayerNotifier._playbackPositionAdvanceTolerance <
        _lastPlaybackHealthPosition) {
      _lastPlaybackHealthPosition = position;
      _lastPlaybackHealthPositionChangedAt = _now();
      _healthSongKey = _songKey(_s.currentSong);
      _healthPlayRequestId = _playRequestId;
      _healthQualityRequestId = _qualityRequestId;
      return;
    }
    if (position >=
        _lastPlaybackHealthPosition + PlayerNotifier._playbackPositionAdvanceTolerance) {
      _lastPlaybackHealthPosition = position;
      _lastPlaybackHealthPositionChangedAt = _now();
      _healthSongKey = _songKey(_s.currentSong);
      _healthPlayRequestId = _playRequestId;
      _healthQualityRequestId = _qualityRequestId;
    }
  }

  bool _canCheckPlaybackHealth() {
    final song = _s.currentSong;
    final controller = _audioController;
    return PlatformUtils.isAndroid &&
        song != null &&
        _isOnlineSong(song) &&
        _s.isPlaying &&
        controller != null &&
        controller.playing &&
        !_s.isTransitioning &&
        !_isSwitchingQuality &&
        !_restoredSourceNeedsLoad &&
        !_isSleepFadingOut &&
        !_isRecoveringPlayback;
  }

  Future<void> _checkPlaybackHealth() async {
    if (!mounted) return;
    await _ensurePlaybackVolume();
    if (!_canCheckPlaybackHealth()) {
      _resetPlaybackHealthWindow(applyGrace: false);
      return;
    }
    final now = _now();
    final graceUntil = _playbackHealthGraceUntil;
    if (graceUntil != null && now.isBefore(graceUntil)) return;
    if (_isNearPlaybackEnd()) {
      _resetPlaybackHealthWindow(applyGrace: false);
      return;
    }
    if (!_samePlaybackHealthFingerprint()) {
      _resetPlaybackHealthWindow(applyGrace: false);
      return;
    }

    final processingChangedAt = _lastProcessingStateChangedAt;
    final processingStalled =
        _isStalledProcessingState(_lastProcessingState) &&
        processingChangedAt != null &&
        now.difference(processingChangedAt) >= _playbackStallThreshold;
    final positionChangedAt = _lastPlaybackHealthPositionChangedAt;
    final positionStalled =
        positionChangedAt != null &&
        now.difference(positionChangedAt) >= _playbackStallThreshold;
    if (!processingStalled && !positionStalled) return;

    final reason = processingStalled
        ? 'processing_${_lastProcessingState.name}'
        : 'position_stalled';
    await _recoverStalledOnlinePlayback(reason);
  }

  // 音量守护：健康监测 tick 里把残留在非 1.0 的播放器音量拉回满音量，
  // 避免淡入淡出被打断等泄漏让后台播放只走进度没有声音。
  Future<void> _ensurePlaybackVolume() async {
    if (!mounted) return;
    final controller = _audioController;
    if (controller == null) return;
    if (_s.currentSong == null || !_s.isPlaying) return;
    if (_s.isTransitioning ||
        _isSwitchingQuality ||
        _isRecoveringPlayback ||
        _restoredSourceNeedsLoad) {
      return;
    }
    final current = controller.volume;
    if (current >= 1.0) return;
    if (_isSleepFadingOut) {
      // 睡眠定时的淡出是合法的非满音量窗口（它不依赖用户的淡入淡出开关）。
      return;
    }
    if (_fadeEnabled) {
      final lastWriteAt = _lastVolumeWriteAt;
      if (lastWriteAt != null &&
          _now().difference(lastWriteAt) <
              _fadeDuration + const Duration(seconds: 1)) {
        // 正在淡入淡出的合法非满音量窗口，不干预，避免顶掉淡入淡出。
        return;
      }
    }
    DiagnosticsService.instance.record(
      'player',
      'volume_watchdog_restore',
      data: {'volume': current, 'fade_enabled': _fadeEnabled},
    );
    await _safeSetVolume(1);
  }

  Future<void> _recoverStalledOnlinePlayback(String reason) async {
    if (_isRecoveringPlayback) return;
    final song = _s.currentSong;
    if (song == null || !_isOnlineSong(song)) return;
    final songKey = _songKey(song);
    _resetPlaybackRecoveryIfSongChanged(songKey);

    final now = _now();
    final lastRecoveryAt = _lastPlaybackRecoveryAt;
    if (_playbackRecoveryCooldown > Duration.zero &&
        lastRecoveryAt != null &&
        now.difference(lastRecoveryAt) < _playbackRecoveryCooldown) {
      return;
    }
    if (_recoveryAttemptsForSong >= PlayerNotifier._maxPlaybackRecoveryAttemptsPerSong) {
      if (_recoveryLimitReportedSongKey != songKey) {
        _recoveryLimitReportedSongKey = songKey;
        DiagnosticsService.instance.record(
          'player',
          'playback_recovery_limit_reached',
          data: {
            'song_id': song.id,
            'platform': song.platform.name,
            'reason': reason,
            'attempts': _recoveryAttemptsForSong,
          },
        );
        _setState(
          _s.copyWith(
            error: () => 'Playback stalled repeatedly. Please switch tracks.',
          ),
        );
      }
      return;
    }

    final requestId = _playRequestId;
    final qualityRequestId = _qualityRequestId;
    final quality = _s.currentQuality;
    final resumePosition = _s.position;
    _isRecoveringPlayback = true;
    _recoveryAttemptsForSong++;
    _lastPlaybackRecoveryAt = now;
    DiagnosticsService.instance.record(
      'player',
      'playback_stall_recovery_start',
      data: {
        'song_id': song.id,
        'platform': song.platform.name,
        'reason': reason,
        'position_ms': resumePosition.inMilliseconds,
        'attempt': _recoveryAttemptsForSong,
      },
    );

    // 自愈必须走 _AudioMutex：它做的是 stop/setUrl/seek/play 这一整套传输序列，
    // 以前被当作"内部恢复"豁免、裸奔执行，于是和持锁的 playSong 并发抢同一个
    // 控制器（可表现为点了 B 却在放 A）。锁自身不嵌套——内部没有任何
    // `_mutex.run`。
    try {
      await _mutex.run(() async {
        // 等锁期间播放可能已经换曲/换音质，重新确认后立即放弃。
        if (!mounted) return;
        if (requestId != _playRequestId || qualityRequestId != _qualityRequestId) {
          return;
        }
        final platform = _platformResolver(song.platform);
        final url = await DiagnosticsService.instance.measure(
          'platform.getSongUrl.stallRecovery',
          () => platform
              .getSongUrl(song.id, quality: quality)
              .timeout(const Duration(seconds: 10)),
          data: {
            'platform': song.platform.name,
            'song_id': song.id,
            'quality': quality.name,
          },
        );
        final stillSamePlayback =
            mounted &&
            requestId == _playRequestId &&
            qualityRequestId == _qualityRequestId &&
            _s.currentSong?.id == song.id &&
            _s.currentSong?.platform == song.platform;
        if (!stillSamePlayback) return;

        final fadeGeneration = _cancelActiveFades();
        await _safeStop();
        if (requestId != _playRequestId) return;
        await _setUrlWithRecovery(url, 'playbackStallRecovery');
        if (requestId != _playRequestId) return;
        if (resumePosition > Duration.zero) {
          await _safeSeek(resumePosition);
        }
        if (requestId != _playRequestId) return;
        await _safeSetVolume(1);
        _safePlay(requestId: requestId);
        _schedulePlaybackVolumeRecovery(fadeGeneration);
        _setState(
          _s.copyWith(
            isPlaying: true,
            isTransitioning: false,
            position: resumePosition,
            error: () => null,
          ),
        );
        _resetPlaybackHealthWindow(applyGrace: true);
        DiagnosticsService.instance.record(
          'player',
          'playback_stall_recovery_success',
          data: {
            'song_id': song.id,
            'platform': song.platform.name,
            'position_ms': resumePosition.inMilliseconds,
            'attempt': _recoveryAttemptsForSong,
          },
        );
      }, label: 'stallRecovery');
    } catch (error, stack) {
      if (!mounted) return;
      DiagnosticsService.instance.recordError(
        'player.playbackStallRecovery',
        error,
        stack,
        data: {
          'song_id': song.id,
          'platform': song.platform.name,
          'reason': reason,
          'attempt': _recoveryAttemptsForSong,
        },
      );
      _setState(
        _s.copyWith(error: () => '播放恢复失败：${_userFacingError(error)}'),
      );
    } finally {
      _isRecoveringPlayback = false;
    }
  }

}
