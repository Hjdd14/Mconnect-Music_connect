part of '../presentation/providers/player_provider.dart';

/// 播放通知（MediaSession）与「喜欢」状态的同步。
///
/// 本文件是 `PlayerNotifier` 的 `part`，与 facade **同一个库**：字段、`state`、
/// `_mutex` 都还在 player_provider.dart 里，这里只承载行为。
/// 它不是可以单独复用的模块（拆分地图见 player_provider.dart 顶部）。

extension PlayerNotificationStateSync on PlayerNotifier {
  Future<void> _playFromNotification() async {
    if (_restoredSourceNeedsLoad && _s.currentSong != null) {
      await _playRestoredSong();
      return;
    }
    await togglePlay();
  }

  Future<void> _toggleLikeCurrentSongFromNotification() async {
    final song = _s.currentSong;
    final toggle = _toggleSongLike;
    if (song == null || toggle == null) return;
    await toggle(song);
    _syncNotificationState();
  }

  Future<void> _toggleFloatingLyricsFromNotification() async {
    final toggle = _toggleFloatingLyrics;
    if (toggle == null) return;
    await toggle();
    _syncNotificationState();
  }

  void _syncNotificationState() {
    _notificationController.update(
      currentSong: _s.currentSong,
      playlist: _s.playlist,
      currentIndex: _s.currentIndex,
      isCurrentSongLiked:
          _s.currentSong != null &&
          _isCurrentSongLikedNow(_s.currentSong!),
      isFloatingLyricsEnabled: _isFloatingLyricsEnabled(),
      isPlaying: _s.isPlaying,
      position: _s.position,
      duration: _s.duration,
    );
  }

  /// 用整份喜欢列表刷新 key 集合（Wave 0-A / P-1）。
  ///
  /// 以前 `playerProvider` 把 `likesProvider.songs.any(...)`（最多 500 首）当
  /// [SongLikeResolver] 传进来，而它**每秒**都会被调一次（位置 tick → 状态更新 →
  /// 通知刷新，Windows 也一样）→ 每秒一次 O(n)。现在只在喜欢列表变化时重建一次
  /// `Set`，热路径上只剩一次 `Set.contains`。
  void updateLikedSongs(Iterable<Song> songs) {
    _likedSongKeys
      ..clear()
      // `likedSongKeyFor` is a static on the class and stays in the facade
      // (Dart extensions cannot declare statics), so it must be named here.
      ..addAll(songs.map(PlayerNotifier.likedSongKeyFor));
    _hasLikedSongKeys = true;
    _syncNotificationState();
  }

  bool _isCurrentSongLikedNow(Song song) {
    if (_hasLikedSongKeys) {
      return _likedSongKeys.contains(PlayerNotifier.likedSongKeyFor(song));
    }
    // 兜底：只有从未调用 [updateLikedSongs] 的构造方式（单测、嵌套用例）才走这里。
    return _isSongLiked(song);
  }

  void refreshNotificationState() {
    _syncNotificationState();
  }

  Future<void> _syncPlaybackKeepAlive(
    bool isPlaying, {
    bool force = false,
  }) async {
    if (!force && _lastKeepAlivePlaying == isPlaying) return;
    _lastKeepAlivePlaying = isPlaying;
    await _keepAliveController.setPlaying(isPlaying, force: force);
  }

  Future<void> reassertBackgroundPlayback() async {
    _syncNotificationState();
    DiagnosticsService.instance.record(
      'background_playback',
      'reassert',
      data: {
        'is_playing': _s.isPlaying,
        'position_ms': _s.position.inMilliseconds,
        'duration_ms': _s.duration.inMilliseconds,
        'song_id': _s.currentSong?.id,
        'platform': _s.currentSong?.platform.name,
      },
    );
    if (!_s.isPlaying) return;
    await _syncPlaybackKeepAlive(true, force: true);
  }

}
