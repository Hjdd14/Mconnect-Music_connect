import '../../../core/database/app_database.dart';
import '../../../core/database/song_record_mapping.dart';
import '../../../models/song.dart';

/// A saved smart-playlist result.
///
/// Until v1.4.0 a generated smart playlist existed only as a preview: leaving
/// the page threw it away and there was no way to open it again. Results are now
/// persisted in `SmartPlaylistSnapshots` (keys) plus the cached `Songs` rows
/// (metadata), so they survive a restart.
class SavedSmartPlaylist {
  final String ruleId;
  final DateTime generatedAt;
  final List<Song> songs;

  /// Keys that were in the snapshot but had no cached song row any more.
  final int missingSongCount;

  const SavedSmartPlaylist({
    required this.ruleId,
    required this.generatedAt,
    this.songs = const [],
    this.missingSongCount = 0,
  });

  bool get isEmpty => songs.isEmpty;
}

abstract class SmartPlaylistSnapshotRepository {
  /// Persists [songs] for [ruleId], replacing any previous snapshot.
  Future<SavedSmartPlaylist> save(
    String ruleId,
    List<Song> songs, {
    DateTime? generatedAt,
  });

  Future<SavedSmartPlaylist?> load(String ruleId);

  Future<Map<String, SavedSmartPlaylist>> loadAll();

  Future<void> delete(String ruleId);

  /// Drops snapshots whose rule has been deleted.
  Future<void> deleteMissing(Set<String> ruleIds);

  Future<void> clear();
}

/// Backed by the `SmartPlaylistSnapshots` table.
///
/// The snapshot column stores `"platform:id"` keys (the frozen contract of that
/// table), so the song metadata has to be cached in `Songs` too — [save] does
/// that, which also means the saved playlist keeps working after a restart.
class DriftSmartPlaylistSnapshotRepository
    implements SmartPlaylistSnapshotRepository {
  DriftSmartPlaylistSnapshotRepository(this._db);

  final AppDatabase _db;

  @override
  Future<SavedSmartPlaylist> save(
    String ruleId,
    List<Song> songs, {
    DateTime? generatedAt,
  }) async {
    final at = generatedAt ?? DateTime.now();
    await _db.songsDao.insertSongs(
      songs.map(songsCompanionFromSong).toList(),
    );
    await _db.smartPlaylistSnapshotsDao.saveSnapshot(
      ruleId: ruleId,
      songKeys: songs.map(_songKey).toList(),
      generatedAt: at,
    );
    return SavedSmartPlaylist(
      ruleId: ruleId,
      generatedAt: at,
      songs: List<Song>.unmodifiable(songs),
    );
  }

  @override
  Future<SavedSmartPlaylist?> load(String ruleId) async {
    final row = await _db.smartPlaylistSnapshotsDao.snapshot(ruleId);
    if (row == null) return null;
    return _resolve(row.ruleId, row.generatedAt, row.songKeys);
  }

  @override
  Future<Map<String, SavedSmartPlaylist>> loadAll() async {
    final rows = await _db.smartPlaylistSnapshotsDao.all();
    final result = <String, SavedSmartPlaylist>{};
    for (final row in rows) {
      result[row.ruleId] = await _resolve(
        row.ruleId,
        row.generatedAt,
        row.songKeys,
      );
    }
    return result;
  }

  @override
  Future<void> delete(String ruleId) =>
      _db.smartPlaylistSnapshotsDao.deleteSnapshot(ruleId);

  @override
  Future<void> deleteMissing(Set<String> ruleIds) =>
      _db.smartPlaylistSnapshotsDao.deleteMissing(ruleIds);

  @override
  Future<void> clear() => _db.smartPlaylistSnapshotsDao.clear();

  Future<SavedSmartPlaylist> _resolve(
    String ruleId,
    int generatedAt,
    String rawKeys,
  ) async {
    final keys = SmartPlaylistSnapshotsDao.decodeSongKeys(rawKeys);
    if (keys.isEmpty) {
      return SavedSmartPlaylist(
        ruleId: ruleId,
        generatedAt: DateTime.fromMillisecondsSinceEpoch(generatedAt),
      );
    }
    final parsed = <({String id, String platform})>[];
    for (final key in keys) {
      final separator = key.indexOf(':');
      if (separator <= 0) continue;
      parsed.add(
        (
          id: key.substring(separator + 1),
          platform: key.substring(0, separator),
        ),
      );
    }
    final records = await _db.songsDao.getSongsByIds(parsed);
    final byKey = {
      for (final record in records) '${record.platform}:${record.id}': record,
    };
    final songs = <Song>[];
    for (final key in keys) {
      final record = byKey[key];
      if (record == null) continue;
      songs.add(songFromSongRecord(record));
    }
    return SavedSmartPlaylist(
      ruleId: ruleId,
      generatedAt: DateTime.fromMillisecondsSinceEpoch(generatedAt),
      songs: songs,
      missingSongCount: keys.length - songs.length,
    );
  }

  static String _songKey(Song song) => '${song.platform.name}:${song.id}';
}

/// In-memory counterpart used by tests.
class MemorySmartPlaylistSnapshotRepository
    implements SmartPlaylistSnapshotRepository {
  final Map<String, SavedSmartPlaylist> _saved = {};

  @override
  Future<SavedSmartPlaylist> save(
    String ruleId,
    List<Song> songs, {
    DateTime? generatedAt,
  }) async {
    final saved = SavedSmartPlaylist(
      ruleId: ruleId,
      generatedAt: generatedAt ?? DateTime.now(),
      songs: List<Song>.unmodifiable(songs),
    );
    _saved[ruleId] = saved;
    return saved;
  }

  @override
  Future<SavedSmartPlaylist?> load(String ruleId) async => _saved[ruleId];

  @override
  Future<Map<String, SavedSmartPlaylist>> loadAll() async =>
      Map<String, SavedSmartPlaylist>.from(_saved);

  @override
  Future<void> delete(String ruleId) async {
    _saved.remove(ruleId);
  }

  @override
  Future<void> deleteMissing(Set<String> ruleIds) async {
    _saved.removeWhere((ruleId, _) => !ruleIds.contains(ruleId));
  }

  @override
  Future<void> clear() async => _saved.clear();
}
