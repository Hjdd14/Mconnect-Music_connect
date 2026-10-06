import '../../../core/database/app_database.dart';
import '../../../models/album.dart';
import '../../../models/artist.dart';
import '../../../models/audio_quality.dart';
import '../../../models/platform_type.dart';
import '../../../models/song.dart';

/// Loads the songs already cached in the local database (`Songs` is written by
/// likes / history / playlists / stats) — the "online library" side of the
/// local-vs-online dedupe.
///
/// Abstract so the provider can be tested without a database.
abstract class OnlineLibrarySnapshot {
  Future<List<Song>> load();
}

/// Reads the `Songs` cache table.
///
/// Read-only: the local-music workstream does not own writes to that table.
class DriftOnlineLibrarySnapshot implements OnlineLibrarySnapshot {
  DriftOnlineLibrarySnapshot({AppDatabase? database})
    : _db = database ?? _appDatabase();

  static AppDatabase _appDatabase() => database;

  final AppDatabase _db;

  @override
  Future<List<Song>> load() async {
    final rows = await _db.select(_db.songs).get();
    return [for (final row in rows) _toSong(row)];
  }

  static Song _toSong(SongRecord row) {
    final artistNames = row.artists
        .split(',')
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
    return Song(
      id: row.id,
      platform: PlatformType.tryParse(row.platform) ?? PlatformType.local,
      name: row.name,
      artists: [
        for (final name in artistNames.isEmpty ? [row.artists] : artistNames)
          Artist(id: 'cached', name: name),
      ],
      album: row.albumName == null
          ? null
          : Album(id: '', name: row.albumName!, coverUrl: row.albumCover),
      duration: Duration(milliseconds: row.durationMs),
      coverUrl: row.albumCover,
      albumId: row.albumId,
      artistId: row.artistId,
      trackNumber: row.trackNumber,
      availableQualities: const [
        AudioQuality(level: AudioLevel.low, bitrate: 0, format: 'cached'),
      ],
    );
  }
}

/// In-memory snapshot for tests.
class MemoryOnlineLibrarySnapshot implements OnlineLibrarySnapshot {
  MemoryOnlineLibrarySnapshot([this.songs = const []]);

  final List<Song> songs;

  @override
  Future<List<Song>> load() async => songs;
}
