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
  TextColumn get artists => text()(); // JSON array
  TextColumn get albumName => text().nullable()();
  TextColumn get albumCover => text().nullable()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  TextColumn get fingerprint => text()();

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

class Playlists extends Table {
  TextColumn get id => text()();
  TextColumn get platform => text()();
  TextColumn get name => text()();
  IntColumn get songCount => integer().withDefault(const Constant(0))();
  IntColumn get syncedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id, platform};
}

// --- DAOs ---

@DriftAccessor(tables: [Songs, ListeningHistory, UserLikes, LyricsCache, Playlists])
class SongsDao extends DatabaseAccessor<AppDatabase> with _$SongsDaoMixin {
  SongsDao(AppDatabase db) : super(db);

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
  HistoryDao(AppDatabase db) : super(db);

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
  LikesDao(AppDatabase db) : super(db);

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
  LyricsCacheDao(AppDatabase db) : super(db);

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

@DriftDatabase(tables: [
  Songs,
  ListeningHistory,
  UserLikes,
  LyricsCache,
  Playlists,
], daos: [
  SongsDao,
  HistoryDao,
  LikesDao,
  LyricsCacheDao,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
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
