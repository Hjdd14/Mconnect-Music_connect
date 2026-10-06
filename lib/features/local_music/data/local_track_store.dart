import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/app_database.dart';
import '../../../models/album.dart';
import '../../../models/artist.dart';
import '../../../models/audio_quality.dart';
import '../../../models/platform_type.dart';
import '../../../models/song.dart';

/// A single row of the persisted local-library index.
///
/// This is the in-memory shape of `LocalTracks` used by the scanner and the UI.
/// It is deliberately a plain value object (no drift types) so both the real
/// database-backed store and the in-memory test double can produce it, and so
/// the sort/group helpers can be unit-tested without a database.
class LocalTrackEntry {
  final String path;
  final int mtime;
  final int size;
  final String? title;
  final String? artistName;
  final String? albumName;
  final int durationMs;
  final int? trackNumber;
  final String? coverPath;
  final int? scannedAt;

  const LocalTrackEntry({
    required this.path,
    required this.mtime,
    required this.size,
    this.title,
    this.artistName,
    this.albumName,
    this.durationMs = 0,
    this.trackNumber,
    this.coverPath,
    this.scannedAt,
  });

  bool get hasTitle => title != null && title!.trim().isNotEmpty;
  bool get hasArtist => artistName != null && artistName!.trim().isNotEmpty;
  bool get hasAlbum => albumName != null && albumName!.trim().isNotEmpty;

  /// Title shown in the UI, falling back to the file name when the tags are
  /// absent (a file with no usable tag is still a playable track).
  String get displayTitle => hasTitle ? title!.trim() : _baseName(path);

  String get displayArtist =>
      hasArtist ? artistName!.trim() : LocalTrackEntry.unknownArtist;

  String get displayAlbum =>
      hasAlbum ? albumName!.trim() : LocalTrackEntry.unknownAlbum;

  String get folderPath => p.dirname(path);

  /// Last path segment, used as the "文件夹" view label.
  String get folderName {
    final folder = folderPath;
    final name = p.basename(folder);
    return name.isEmpty ? folder : name;
  }

  Duration get duration => Duration(milliseconds: durationMs);

  /// Builds the playable [Song] for this row.
  ///
  /// [coverPath] is intentionally **not** copied into `Song.coverUrl`: every
  /// cover consumer in the app goes through `CachedNetworkImage`, which cannot
  /// render a local file path (the player screen, mini bar, notification and
  /// search tile all use `imageUrl`). The local page reads the cover from the
  /// database row instead.
  Song toSong() => Song(
    id: path,
    platform: PlatformType.local,
    name: displayTitle,
    artists: [
      Artist(id: 'local', name: displayArtist),
    ],
    album: hasAlbum
        ? Album(id: '', name: displayAlbum, artistName: displayArtist)
        : null,
    duration: duration,
    trackNumber: trackNumber,
    availableQualities: const [
      AudioQuality(level: AudioLevel.low, bitrate: 0, format: 'local'),
    ],
  );

  static const unknownArtist = '未知歌手';
  static const unknownAlbum = '未知专辑';

  static String _baseName(String path) {
    final name = p.basenameWithoutExtension(path).trim();
    return name.isEmpty ? p.basename(path) : name;
  }

  LocalTrackEntry copyWith({
    String? title,
    String? artistName,
    String? albumName,
    int? durationMs,
    int? trackNumber,
    String? coverPath,
    int? scannedAt,
  }) {
    return LocalTrackEntry(
      path: path,
      mtime: mtime,
      size: size,
      title: title ?? this.title,
      artistName: artistName ?? this.artistName,
      albumName: albumName ?? this.albumName,
      durationMs: durationMs ?? this.durationMs,
      trackNumber: trackNumber ?? this.trackNumber,
      coverPath: coverPath ?? this.coverPath,
      scannedAt: scannedAt ?? this.scannedAt,
    );
  }

  @override
  String toString() => 'LocalTrackEntry($path, mtime=$mtime, size=$size)';
}

/// Persistence for the local-library index.
abstract class LocalTrackStore {
  /// Every indexed row, used by the album/artist/folder views and by the
  /// scanner's `(path, mtime, size)` skip check.
  Future<List<LocalTrackEntry>> loadAll();

  /// The skip index, keyed by absolute path.
  Future<Map<String, LocalTrackEntry>> loadIndex() async {
    final rows = await loadAll();
    return {for (final row in rows) row.path: row};
  }

  Future<void> upsertAll(Iterable<LocalTrackEntry> entries);

  Future<void> removePaths(Iterable<String> paths);

  Future<void> clear();
}

/// [LocalTrackStore] over the `LocalTracks` drift table.
///
/// Delegates to the shared `LocalTracksDao` (`app_database.dart:907`, owned by
/// the WS-F data-layer workstream and written for exactly this scanner) rather
/// than opening a second accessor on the same table. The value-object mapping
/// stays here because [LocalTrackEntry] is the local-music feature's own shape.
class DriftLocalTrackStore extends LocalTrackStore {
  DriftLocalTrackStore({AppDatabase? database}) : _db = database ?? _appDatabase();

  /// Resolves the process-wide database without shadowing it with the
  /// constructor parameter of the same name.
  static AppDatabase _appDatabase() => database;

  final AppDatabase _db;

  @override
  Future<List<LocalTrackEntry>> loadAll() async {
    final rows = await _db.localTracksDao.all();
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<void> upsertAll(Iterable<LocalTrackEntry> entries) async {
    final companions = entries.map(_toCompanion).toList(growable: false);
    if (companions.isEmpty) return;
    await _db.localTracksDao.upsertAll(companions);
  }

  @override
  Future<void> removePaths(Iterable<String> paths) async {
    final list = paths.toList(growable: false);
    if (list.isEmpty) return;
    // Removals are rare (a file or a whole folder disappeared), so the DAO's
    // per-path delete is enough; it runs in one transaction so a 1000-row
    // cleanup does not pay 1000 fsyncs.
    await _db.transaction(() async {
      for (final path in list) {
        await _db.localTracksDao.deleteByPath(path);
      }
    });
  }

  @override
  Future<void> clear() async {
    await _db.localTracksDao.clear();
  }

  static LocalTrackEntry _fromRow(LocalTrack row) => LocalTrackEntry(
    path: row.path,
    mtime: row.mtime,
    size: row.size,
    title: row.title,
    artistName: row.artistName,
    albumName: row.albumName,
    durationMs: row.durationMs,
    trackNumber: row.trackNumber,
    coverPath: row.coverPath,
    scannedAt: row.scannedAt,
  );

  static LocalTracksCompanion _toCompanion(LocalTrackEntry entry) {
    return LocalTracksCompanion(
      path: Value(entry.path),
      mtime: Value(entry.mtime),
      size: Value(entry.size),
      title: Value(entry.title),
      artistName: Value(entry.artistName),
      albumName: Value(entry.albumName),
      durationMs: Value(entry.durationMs),
      trackNumber: Value(entry.trackNumber),
      coverPath: Value(entry.coverPath),
      scannedAt: Value(entry.scannedAt),
    );
  }
}

/// In-memory [LocalTrackStore] used by tests and by the pure grouping helpers.
class MemoryLocalTrackStore extends LocalTrackStore {
  MemoryLocalTrackStore([Iterable<LocalTrackEntry> seed = const []])
    : _rows = {for (final row in seed) row.path: row};

  final Map<String, LocalTrackEntry> _rows;

  @override
  Future<List<LocalTrackEntry>> loadAll() async => _rows.values.toList();

  @override
  Future<void> upsertAll(Iterable<LocalTrackEntry> entries) async {
    for (final entry in entries) {
      _rows[entry.path] = entry;
    }
  }

  @override
  Future<void> removePaths(Iterable<String> paths) async {
    for (final path in paths) {
      _rows.remove(path);
    }
  }

  @override
  Future<void> clear() async => _rows.clear();
}
