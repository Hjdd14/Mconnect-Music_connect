import 'package:drift/drift.dart' show Value;
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../../models/song.dart';
import '../../../../models/platform_type.dart';
import '../../../../models/artist.dart';
import '../../../../models/album.dart';
import '../../../player/presentation/providers/player_provider.dart';

class HistoryEntry {
  final Song song;
  final DateTime listenedAt;
  final int durationListenedMs;

  const HistoryEntry({
    required this.song,
    required this.listenedAt,
    this.durationListenedMs = 0,
  });
}

class HistoryState {
  final List<HistoryEntry> entries;
  final bool isLoading;
  final String? error;

  const HistoryState({
    this.entries = const [],
    this.isLoading = false,
    this.error,
  });

  HistoryState copyWith({
    List<HistoryEntry>? entries,
    bool? isLoading,
    String? Function()? error,
  }) {
    return HistoryState(
      entries: entries ?? this.entries,
      isLoading: isLoading ?? this.isLoading,
      error: error != null ? error() : this.error,
    );
  }
}

class HistoryNotifier extends StateNotifier<HistoryState> {
  final HistoryDao _historyDao;
  final SongsDao _songsDao;
  String? _lastListenedSongId;
  DateTime? _lastListenedAt;
  Timer? _pendingRecordTimer;
  String? _pendingRecordKey;

  HistoryNotifier(this._historyDao, this._songsDao)
    : super(const HistoryState()) {
    loadHistory();
  }

  Future<void> loadHistory() async {
    state = state.copyWith(isLoading: true);
    try {
      final records = await _historyDao.getRecentHistory(limit: 200);
      // Batch query instead of N+1
      final keys = records
          .map((r) => (id: r.songId, platform: r.platform))
          .toList();
      final songRecords = await _songsDao.getSongsByIds(keys);
      final songMap = {for (final r in songRecords) '${r.platform}_${r.id}': r};
      final entries = <HistoryEntry>[];
      for (final record in records) {
        final songRecord = songMap['${record.platform}_${record.songId}'];
        if (songRecord != null) {
          entries.add(
            HistoryEntry(
              song: _recordToSong(songRecord),
              listenedAt: DateTime.fromMillisecondsSinceEpoch(
                record.listenedAt,
              ),
              durationListenedMs: record.durationListened,
            ),
          );
        }
      }
      state = state.copyWith(
        entries: entries,
        isLoading: false,
        error: () => null,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: () => '加载历史失败');
    }
  }

  Future<void> recordListen(Song song, {int durationMs = 0}) async {
    final songKey = '${song.platform.name}_${song.id}';
    final now = DateTime.now();

    // Time-based cooldown: ignore if same song recorded within 10 seconds
    if (_lastListenedSongId == songKey &&
        _lastListenedAt != null &&
        now.difference(_lastListenedAt!).inSeconds < 10) {
      return;
    }

    _lastListenedSongId = songKey;
    _lastListenedAt = now;

    try {
      await _songsDao.insertSong(_songToCompanion(song));
      await _historyDao.recordListen(
        song.id,
        song.platform.name,
        durationMs: durationMs,
      );

      // Update in-memory state so the UI sees the new entry immediately
      final newEntry = HistoryEntry(
        song: song,
        listenedAt: now,
        durationListenedMs: durationMs,
      );
      state = state.copyWith(entries: [newEntry, ...state.entries]);
    } catch (e) {
      debugPrint('recordListen error: $e');
    }
  }

  void scheduleRecordAfterPlaybackStarts(Song song) {
    final songKey = '${song.platform.name}_${song.id}';
    if (_pendingRecordKey == songKey) return;
    _pendingRecordKey = songKey;
    _pendingRecordTimer?.cancel();
    _pendingRecordTimer = Timer(const Duration(seconds: 3), () {
      _pendingRecordKey = null;
      recordListen(song);
    });
  }

  Future<void> clearHistory() async {
    try {
      await _historyDao.clearHistory();
      _lastListenedSongId = null;
      _lastListenedAt = null;
      state = const HistoryState();
    } catch (e) {
      state = state.copyWith(error: () => '清空失败');
    }
  }

  @override
  void dispose() {
    _pendingRecordTimer?.cancel();
    super.dispose();
  }

  Song _recordToSong(SongRecord record) {
    final platformType = PlatformType.values.firstWhere(
      (p) => p.name == record.platform,
      orElse: () => PlatformType.netease,
    );
    final artistsList = record.artists.isNotEmpty
        ? record.artists
              .split(',')
              .map((a) => Artist(id: '', name: a.trim()))
              .toList()
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

final historyProvider = StateNotifierProvider<HistoryNotifier, HistoryState>((
  ref,
) {
  final db = database;
  final notifier = HistoryNotifier(db.historyDao, db.songsDao);

  ref.listen<PlayerState>(playerProvider, (prev, next) {
    final song = next.currentSong;
    final changedSong =
        prev?.currentSong?.id != song?.id ||
        prev?.currentSong?.platform != song?.platform;
    final startedPlaying =
        next.isPlaying && (prev?.isPlaying != true || changedSong);
    if (song != null && startedPlaying) {
      notifier.scheduleRecordAfterPlaybackStarts(song);
    }
  });

  return notifier;
});
