part of '../presentation/providers/player_provider.dart';

/// 播放记忆（断点续播 + A-2 播放偏好）的读取、构造与节流落盘。
///
/// 本文件是 `PlayerNotifier` 的 `part`（见 player_provider.dart 顶部拆分地图），
/// 不是独立模块：快照要读 facade 的 `state`，落盘走 facade 的 store 字段。

extension PlayerPlaybackMemoryOps on PlayerNotifier {
  Future<void> _restorePlaybackMemory() async {
    try {
      final memory = await _playbackMemoryStore.load();
      if (!mounted || memory == null) return;
      final playlist = memory.playlist.isEmpty
          ? [memory.currentSong]
          : memory.playlist;
      var currentIndex = memory.currentIndex;
      if (currentIndex < 0 || currentIndex >= playlist.length) {
        currentIndex = playlist.indexWhere(
          (song) =>
              song.id == memory.currentSong.id &&
              song.platform == memory.currentSong.platform,
        );
      }
      if (currentIndex < 0) currentIndex = 0;
      _lastPositionSecond = memory.position.inSeconds;
      _restoredSourceNeedsLoad = true;
      _setState(
        _s.copyWith(
          currentSong: memory.currentSong,
          playlist: playlist,
          currentIndex: currentIndex,
          isPlaying: false,
          position: memory.position,
          duration: memory.duration,
          currentQuality: memory.currentQuality,
          qualityPreference: memory.qualityPreference,
          // A-2：播放偏好和"上次播到哪"一起恢复。
          playbackSpeed: memory.playbackSpeed,
          skipSilence: memory.skipSilence,
          isShuffle: memory.isShuffle,
          repeatMode: _repeatModeFromName(memory.repeatMode),
          abLoopStart: () => memory.abLoopStart,
          abLoopEnd: () => memory.abLoopEnd,
          error: () => null,
          isTransitioning: false,
        ),
      );
      await _applyRestoredPreferencesToController();
    } catch (e, s) {
      debugPrint('PlayerNotifier restore playback memory failed: $e');
      debugPrint('$s');
    }
  }

  PlayerPlaybackMemory? _buildPlaybackMemory() {
    final song = _s.currentSong;
    if (song == null) return null;
    final playlist = _s.playlist.isEmpty ? [song] : _s.playlist;
    var currentIndex = _s.currentIndex;
    if (currentIndex < 0 || currentIndex >= playlist.length) {
      currentIndex = playlist.indexWhere(
        (item) => item.id == song.id && item.platform == song.platform,
      );
    }
    return PlayerPlaybackMemory(
      currentSong: song,
      playlist: playlist,
      currentIndex: currentIndex < 0 ? 0 : currentIndex,
      position: _s.position,
      duration: _s.duration,
      currentQuality: _s.currentQuality,
      qualityPreference: _s.qualityPreference,
      // A-2：偏好跟着一起落盘，任何一次 [_schedulePlaybackMemorySave] 都会带上。
      playbackSpeed: _s.playbackSpeed,
      skipSilence: _s.skipSilence,
      isShuffle: _s.isShuffle,
      repeatMode: _s.repeatMode.name,
      abLoopStart: _s.abLoopStart,
      abLoopEnd: _s.abLoopEnd,
    );
  }

  RepeatMode _repeatModeFromName(String name) {
    return RepeatMode.values.firstWhere(
      (mode) => mode.name == name,
      orElse: () => RepeatMode.off,
    );
  }

  /// 把恢复出来的偏好推给**已经存在**的控制器。
  ///
  /// 全新控制器不需要这一步：[`_restoreControllerAudioSettings`] 会在创建/重建时
  /// 把 `state.playbackSpeed` / `state.skipSilence` 推过去。这里只覆盖"启动时已经
  /// 有注入控制器"的情况（测试与热重建）。
  Future<void> _applyRestoredPreferencesToController() async {
    final controller = _audioController;
    if (controller == null) return;
    if (controller is PlaybackSpeedCapable && _s.playbackSpeed != 1.0) {
      try {
        await (controller as PlaybackSpeedCapable)
            .setPlaybackSpeed(_s.playbackSpeed)
            .timeout(_audioOperationTimeout);
      } catch (e) {
        debugPrint('PlayerNotifier restore speed failed: $e');
      }
    }
    if (controller is SkipSilenceCapable && _s.skipSilence) {
      try {
        await (controller as SkipSilenceCapable)
            .setSkipSilence(true)
            .timeout(_audioOperationTimeout);
      } catch (e) {
        debugPrint('PlayerNotifier restore skip silence failed: $e');
      }
    }
  }

  void _schedulePlaybackMemorySave() {
    final memory = _buildPlaybackMemory();
    if (memory == null) return;
    _pendingPlaybackMemory = memory;
    if (_playbackMemorySaveInterval == Duration.zero) {
      unawaited(flushPlaybackMemory());
      return;
    }
    if (_playbackMemoryTimer?.isActive == true) return;
    _playbackMemoryTimer = Timer(
      _playbackMemorySaveInterval,
      () => unawaited(flushPlaybackMemory()),
    );
  }

  Future<void> flushPlaybackMemory() async {
    final memory = _takePlaybackMemorySnapshot();
    if (memory == null) return;
    await _savePlaybackMemory(memory);
  }

  /// 同步取出待落盘的快照，并清掉挂起的定时器。
  ///
  /// **必须同步**：快照要读 `state`，而 `StateNotifier` 在 `dispose()` 之后会对
  /// `state` 抛 "Tried to use ... after `dispose` was called"。以前 `dispose()` 里
  /// 直接 `unawaited(flushPlaybackMemory())`，快照是在那个异步体的同步段里构造的
  /// —— 只要 `dispose()` 被走到第二次（Riverpod 随 scope 销毁一次、宿主/测试收尾
  /// 再销毁一次），第二次就会读到已失效的 `state` 并抛异常（widget 用例就是这样
  /// 被带崩的）。
  PlayerPlaybackMemory? _takePlaybackMemorySnapshot() {
    final memory = _pendingPlaybackMemory ?? _buildPlaybackMemory();
    _pendingPlaybackMemory = null;
    _playbackMemoryTimer?.cancel();
    _playbackMemoryTimer = null;
    return memory;
  }

  Future<void> _savePlaybackMemory(PlayerPlaybackMemory memory) async {
    try {
      await _playbackMemoryStore.save(memory);
    } catch (e, s) {
      debugPrint('PlayerNotifier save playback memory failed: $e');
      debugPrint('$s');
    }
  }

}
