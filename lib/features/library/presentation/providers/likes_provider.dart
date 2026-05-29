import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../../models/song.dart';
import '../../../../models/platform_type.dart';
import '../../../../models/artist.dart';
import '../../../../models/album.dart';

class LikesState {
  final List<Song> songs;
  final bool isLoading;
  final PlatformType? filterPlatform;
  final String? error;

  const LikesState({
    this.songs = const [],
    this.isLoading = false,
    this.filterPlatform,
    this.error,
  });

  LikesState copyWith({
    List<Song>? songs,
    bool? isLoading,
    PlatformType? Function()? filterPlatform,
    String? Function()? error,
  }) {
    return LikesState(
      songs: songs ?? this.songs,
      isLoading: isLoading ?? this.isLoading,
      filterPlatform: filterPlatform != null ? filterPlatform() : this.filterPlatform,
      error: error != null ? error() : this.error,
    );
  }

  List<Song> get filteredSongs {
    if (filterPlatform == null) return songs;
    return songs.where((s) => s.platform == filterPlatform).toList();
  }
}

class LikesNotifier extends StateNotifier<LikesState> {
  final LikesDao _likesDao;
  final SongsDao _songsDao;
  bool _isToggling = false;

  LikesNotifier(this._likesDao, this._songsDao) : super(const LikesState()) {
    loadLikes();
  }

  Future<void> loadLikes() async {
    state = state.copyWith(isLoading: true);
    try {
      final userLikes = await _likesDao.getAllLikes(limit: 500);
      // Batch query instead of N+1
      final keys = userLikes.map((l) => (id: l.songId, platform: l.platform)).toList();
      final songRecords = await _songsDao.getSongsByIds(keys);
      final songMap = {for (final r in songRecords) '${r.platform}_${r.id}': r};
      final songs = <Song>[];
      for (final like in userLikes) {
        final record = songMap['${like.platform}_${like.songId}'];
        if (record != null) {
          songs.add(_recordToSong(record));
        }
      }
      state = state.copyWith(songs: songs, isLoading: false, error: () => null);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: () => '加载喜欢列表失败');
    }
  }

  Future<bool> toggleLike(Song song) async {
    if (_isToggling) return false;
    _isToggling = true;
    try {
      final isLiked = await _likesDao.isLiked(song.id, song.platform.name);
      if (isLiked) {
        // Optimistically remove from state
        state = state.copyWith(
          songs: state.songs.where((s) => !(s.id == song.id && s.platform == song.platform)).toList(),
        );
        await _likesDao.unlikeSong(song.id, song.platform.name);
        return false;
      } else {
        // Optimistically add to state
        state = state.copyWith(songs: [song, ...state.songs]);
        await _songsDao.insertSong(_songToCompanion(song));
        await _likesDao.likeSong(song.id, song.platform.name);
        return true;
      }
    } catch (e) {
      debugPrint('toggleLike error: $e');
      // Re-sync on failure
      await loadLikes();
      return false;
    } finally {
      _isToggling = false;
    }
  }

  Future<bool> isLiked(String songId, PlatformType platform) async {
    return _likesDao.isLiked(songId, platform.name);
  }

  void setFilter(PlatformType? platform) {
    state = state.copyWith(filterPlatform: () => platform);
  }

  Song _recordToSong(SongRecord record) {
    final platformType = PlatformType.values.firstWhere(
      (p) => p.name == record.platform,
      orElse: () => PlatformType.netease,
    );
    final artistsList = record.artists.isNotEmpty
        ? (record.artists.split(',').map((a) => Artist(id: '', name: a.trim())).toList())
        : <Artist>[];
    return Song(
      id: record.id,
      platform: platformType,
      name: record.name,
      artists: artistsList,
      album: record.albumName != null
          ? Album(id: '', name: record.albumName!, coverUrl: record.albumCover)
          : null,
      duration: Duration(milliseconds: record.durationMs),
      coverUrl: record.albumCover,
    );
  }

  SongsCompanion _songToCompanion(Song song) {
    return SongsCompanion.insert(
      id: song.id,
      platform: song.platform.name,
      name: song.name,
      artists: song.artists.map((a) => a.name).join(','),
      albumName: Value(song.album?.name),
      albumCover: Value(song.coverUrl ?? song.album?.coverUrl),
      durationMs: Value(song.duration.inMilliseconds),
      fingerprint: song.fingerprint,
    );
  }
}

final likesProvider = StateNotifierProvider<LikesNotifier, LikesState>((ref) {
  final db = database;
  return LikesNotifier(db.likesDao, db.songsDao);
});
