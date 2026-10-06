import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'app_database.g.dart';

// --- Tables ---

@DataClassName('SongRecord')
class Songs extends Table {
  TextColumn get id => text()();
  TextColumn get platform => text()();
  TextColumn get name => text()();
  // NOTE: despite the name this is **not** a JSON array — writers store the
  // comma-joined artist names (likes_provider.dart:136, history_provider.dart:169),
  // which is why the platform artist id had to be added separately below.
  TextColumn get artists => text()();
  TextColumn get albumName => text().nullable()();
  TextColumn get albumCover => text().nullable()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  TextColumn get fingerprint => text()();

  /// Owning-platform album id, so a cached song can open the album page.
  TextColumn get albumId => text().nullable()();

  /// Owning-platform primary artist id, so a cached song can open the artist
  /// page. Rows written before schema v2 leave this null; the UI falls back to
  /// a name search for those (see the migration notes in `docs/`).
  TextColumn get artistId => text().nullable()();

  /// 1-based track number inside the album.
  IntColumn get trackNumber => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id, platform};
}

@DataClassName('ListeningHistoryEntry')
class ListeningHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get songId => text()();
  TextColumn get platform => text()();
  IntColumn get listenedAt => integer()(); // epoch ms
  IntColumn get durationListened => integer().withDefault(const Constant(0))();

  @override
  List<Set<Column>> get uniqueKeys => [{songId, platform, listenedAt}];
}

@DataClassName('UserLike')
class UserLikes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get songId => text()();
  TextColumn get platform => text()();
  IntColumn get addedAt => integer()(); // epoch ms

  @override
  List<Set<Column>> get uniqueKeys => [{songId, platform}];
}

class LyricsCache extends Table {
  TextColumn get songId => text()();
  TextColumn get platform => text()();
  TextColumn get content => text()();
  TextColumn get format => text()(); // lrc / qrc / krc
  IntColumn get syncedAt => integer()();

  @override
  Set<Column> get primaryKey => {songId, platform};
}

/// Local audio files discovered by the folder scanner.
///
/// Persisted so a rescan can skip unchanged files (path + mtime + size) instead
/// of walking the whole tree every time the page opens, and so tags/cover art
/// are read once rather than on every visit.
@DataClassName('LocalTrack')
class LocalTracks extends Table {
  TextColumn get path => text()();
  IntColumn get mtime => integer()();
  IntColumn get size => integer()();
  TextColumn get title => text().nullable()();
  TextColumn get artistName => text().nullable()();
  TextColumn get albumName => text().nullable()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  IntColumn get trackNumber => integer().nullable()();
  TextColumn get coverPath => text().nullable()();
  IntColumn get scannedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {path};
}

/// Cached chart listings (榜单中心), so the hub renders offline and does not
/// re-hit three platforms on every visit.
@DataClassName('ToplistCacheRow')
class ToplistsCache extends Table {
  TextColumn get platform => text()();
  TextColumn get toplistId => text()();
  TextColumn get name => text()();
  TextColumn get coverUrl => text().nullable()();
  TextColumn get updateFrequency => text().nullable()();
  TextColumn get period => text().nullable()();
  IntColumn get songCount => integer().nullable()();
  TextColumn get groupName => text().nullable()();
  TextColumn get intro => text().nullable()();
  IntColumn get fetchedAt => integer()();

  @override
  Set<Column> get primaryKey => {platform, toplistId};
}

/// One playback event per contiguous listening stretch.
///
/// Replaces the previous "keep the top 100 songs in a Hive snapshot" approach,
/// which silently destroyed the statistics of the 101st song onwards while the
/// totals stayed global (so the numbers could not be reconciled).
@DataClassName('PlayEvent')
class PlayEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get songId => text()();
  TextColumn get platform => text()();
  IntColumn get startedAt => integer()();
  IntColumn get endedAt => integer().nullable()();
  IntColumn get durationListened => integer().withDefault(const Constant(0))();
  RealColumn get completedRatio => real().withDefault(const Constant(0))();

  /// `play` / `resume` / `skip` / `seek` — lets the UI stop counting a
  /// pause-and-resume as a brand new play.
  TextColumn get source => text().nullable()();
}

/// Daily roll-up derived from [PlayEvents], for fast charts on the stats page.
@DataClassName('DailyStat')
class DailyStats extends Table {
  TextColumn get day => text()(); // 'YYYY-MM-DD', local time
  TextColumn get songId => text()();
  TextColumn get platform => text()();
  IntColumn get playCount => integer().withDefault(const Constant(0))();
  IntColumn get listenMs => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {day, songId, platform};
}

/// A generated smart-playlist result, so previews can be saved and reopened.
@DataClassName('SmartPlaylistSnapshot')
class SmartPlaylistSnapshots extends Table {
  TextColumn get ruleId => text()();
  TextColumn get songKeys => text()(); // JSON array of "platform:id"
  IntColumn get generatedAt => integer()();

  @override
  Set<Column> get primaryKey => {ruleId};
}

// --- DAOs ---

@DriftAccessor(
  tables: [Songs, ListeningHistory, UserLikes, LyricsCache],
)
class SongsDao extends DatabaseAccessor<AppDatabase> with _$SongsDaoMixin {
  SongsDao(super.db);

  Future<void> insertSong(SongsCompanion song) async {
    await into(songs).insert(song, mode: InsertMode.insertOrReplace);
  }

  Future<void> insertSongs(List<SongsCompanion> songList) async {
    await batch((batch) {
      batch.insertAll(songs, songList, mode: InsertMode.insertOrReplace);
    });
  }

  Future<SongRecord?> getSong(String id, String platform) async {
    return (select(songs)
          ..where((t) => t.id.equals(id) & t.platform.equals(platform)))
        .getSingleOrNull();
  }

  Future<List<SongRecord>> getSongsByIds(List<({String id, String platform})> keys) async {
    if (keys.isEmpty) return [];
    final results = <SongRecord>[];
    // Process in batches of 50 to avoid SQL variable limit
    for (var i = 0; i < keys.length; i += 50) {
      final batch = keys.skip(i).take(50).toList();
      final query = select(songs)..where((t) {
        final conditions = batch.map((k) =>
          t.id.equals(k.id) & t.platform.equals(k.platform));
        return conditions.reduce((a, b) => a | b);
      });
      results.addAll(await query.get());
    }
    return results;
  }
}

@DriftAccessor(tables: [Songs, ListeningHistory])
class HistoryDao extends DatabaseAccessor<AppDatabase> with _$HistoryDaoMixin {
  HistoryDao(super.db);

  Future<void> recordListen(String songId, String platform, {int durationMs = 0}) async {
    await into(listeningHistory).insert(ListeningHistoryCompanion.insert(
      songId: songId,
      platform: platform,
      listenedAt: DateTime.now().millisecondsSinceEpoch,
      durationListened: Value(durationMs),
    ));
  }

  Future<List<ListeningHistoryEntry>> getRecentHistory({int limit = 50}) async {
    return (select(listeningHistory)
          ..orderBy([(t) => OrderingTerm.desc(t.listenedAt)])
          ..limit(limit))
        .get();
  }

  Future<void> clearHistory() async {
    await delete(listeningHistory).go();
  }
}

@DriftAccessor(tables: [Songs, UserLikes])
class LikesDao extends DatabaseAccessor<AppDatabase> with _$LikesDaoMixin {
  LikesDao(super.db);

  Future<void> likeSong(String songId, String platform) async {
    await into(userLikes).insert(
      UserLikesCompanion.insert(
        songId: songId,
        platform: platform,
        addedAt: DateTime.now().millisecondsSinceEpoch,
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  Future<void> unlikeSong(String songId, String platform) async {
    await (delete(userLikes)
          ..where((t) => t.songId.equals(songId) & t.platform.equals(platform)))
        .go();
  }

  Future<bool> isLiked(String songId, String platform) async {
    final result = await (select(userLikes)
          ..where((t) => t.songId.equals(songId) & t.platform.equals(platform))
          ..limit(1))
        .get();
    return result.isNotEmpty;
  }

  Future<List<UserLike>> getAllLikes({int limit = 100}) async {
    return (select(userLikes)
          ..orderBy([(t) => OrderingTerm.desc(t.addedAt)])
          ..limit(limit))
        .get();
  }
}

@DriftAccessor(tables: [LyricsCache])
class LyricsCacheDao extends DatabaseAccessor<AppDatabase> with _$LyricsCacheDaoMixin {
  LyricsCacheDao(super.db);

  Future<String?> getCachedLyrics(String songId, String platform) async {
    final result = await (select(lyricsCache)
          ..where((t) => t.songId.equals(songId) & t.platform.equals(platform))
          ..limit(1))
        .get();
    return result.isNotEmpty ? result.first.content : null;
  }

  Future<({String content, String format})?> getCachedLyricsWithFormat(String songId, String platform) async {
    final result = await (select(lyricsCache)
          ..where((t) => t.songId.equals(songId) & t.platform.equals(platform))
          ..limit(1))
        .get();
    if (result.isEmpty) return null;
    return (content: result.first.content, format: result.first.format);
  }

  Future<void> cacheLyrics(String songId, String platform, String content, String format) async {
    await into(lyricsCache).insert(
      LyricsCacheCompanion.insert(
        songId: songId,
        platform: platform,
        content: content,
        format: format,
        syncedAt: DateTime.now().millisecondsSinceEpoch,
      ),
      mode: InsertMode.insertOrReplace,
    );
  }
}

// --- Main Database ---

@DriftDatabase(
  tables: [
    Songs,
    ListeningHistory,
    UserLikes,
    LyricsCache,
    LocalTracks,
    ToplistsCache,
    PlayEvents,
    DailyStats,
    SmartPlaylistSnapshots,
  ],
  daos: [SongsDao, HistoryDao, LikesDao, LyricsCacheDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  /// v1 → v2 adds the album/artist ids on [Songs], the local-library and chart
  /// caches, the play-event statistics tables, and drops the never-populated
  /// `Playlists` table.
  @override
  int get schemaVersion => 2;

  /// Schema evolution.
  ///
  /// v1 shipped with `onCreate` only. Because drift raises `UnsupportedError`
  /// for an unhandled version bump (it does **not** silently recreate the
  /// database), the very first column added would have crashed every existing
  /// install on upgrade. From v2 onwards an upgrade path exists and is covered
  /// by `test/database_migration_test.dart`.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // Pre-existing data is preserved: the new columns stay null, and the
        // library falls back to a name-based lookup for records written before
        // the artist/album ids were captured.
        await m.addColumn(songs, songs.albumId);
        await m.addColumn(songs, songs.artistId);
        await m.addColumn(songs, songs.trackNumber);
        await m.createTable(localTracks);
        await m.createTable(toplistsCache);
        await m.createTable(playEvents);
        await m.createTable(dailyStats);
        await m.createTable(smartPlaylistSnapshots);
        // `Playlists` was created in v1 but never written to and has no DAO.
        // Guarded, so installing over a database that somehow lacks it works.
        await m.database.customStatement('DROP TABLE IF EXISTS playlists');
      }
    },
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'mconnect.sqlite'));
    return NativeDatabase.createInBackground(file, setup: (rawDb) {
      rawDb.execute('PRAGMA journal_mode=WAL;');
      rawDb.execute('PRAGMA busy_timeout=5000;');
    });
  });
}

// --- Singleton ---
AppDatabase? _database;

AppDatabase get database {
  _database ??= AppDatabase();
  return _database!;
}
