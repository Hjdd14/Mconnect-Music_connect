import 'dart:io';

// `drift` exports SQL `isNull`/`isNotNull` expressions that collide with the
// matcher package's matchers of the same name.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/database/app_database.dart';
import 'package:path/path.dart' as p;

/// Guards the v1 → v2 schema upgrade.
///
/// Before v2 the database shipped with `onCreate` only. drift raises
/// `UnsupportedError` for an unhandled version bump (it does **not** silently
/// recreate the file), so without `onUpgrade` the first added column would have
/// crashed every existing install — with the user's likes, history and lyrics
/// cache behind it.
///
/// The test builds a **real schema-v1 database** with rows in it, hands it to
/// the current [AppDatabase], and asserts that the upgrade ran, kept the data,
/// added the new columns/tables and dropped the dead `Playlists` table.
void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mconnect_migration_test');
    dbFile = File(p.join(tempDir.path, 'mconnect.sqlite'));
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('upgrading a v1 database keeps rows and adds v2 columns and tables', () async {
    // `setup` runs against the raw sqlite3 handle *before* drift reads the
    // schema version, so this is a genuine v1 database with pre-existing data.
    final db = AppDatabase.forTesting(
      NativeDatabase(
        dbFile,
        setup: (raw) {
          raw.execute('''
            CREATE TABLE songs (
              id TEXT NOT NULL,
              platform TEXT NOT NULL,
              name TEXT NOT NULL,
              artists TEXT NOT NULL,
              album_name TEXT,
              album_cover TEXT,
              duration_ms INTEGER NOT NULL DEFAULT 0,
              fingerprint TEXT NOT NULL,
              PRIMARY KEY (id, platform)
            );
          ''');
          raw.execute('''
            CREATE TABLE listening_history (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              song_id TEXT NOT NULL,
              platform TEXT NOT NULL,
              listened_at INTEGER NOT NULL,
              duration_listened INTEGER NOT NULL DEFAULT 0
            );
          ''');
          raw.execute('''
            CREATE TABLE user_likes (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              song_id TEXT NOT NULL,
              platform TEXT NOT NULL,
              added_at INTEGER NOT NULL
            );
          ''');
          raw.execute('''
            CREATE TABLE lyrics_cache (
              song_id TEXT NOT NULL,
              platform TEXT NOT NULL,
              content TEXT NOT NULL,
              format TEXT NOT NULL,
              synced_at INTEGER NOT NULL,
              PRIMARY KEY (song_id, platform)
            );
          ''');
          // The v1-only dead table: created, never written, no DAO.
          raw.execute('''
            CREATE TABLE playlists (
              id TEXT NOT NULL,
              platform TEXT NOT NULL,
              name TEXT NOT NULL,
              song_count INTEGER NOT NULL DEFAULT 0,
              synced_at INTEGER,
              PRIMARY KEY (id, platform)
            );
          ''');

          // Pre-upgrade user data.
          raw.execute(
            "INSERT INTO songs (id, platform, name, artists, album_name, "
            "duration_ms, fingerprint) VALUES "
            "('s1', 'netease', '旧歌', '旧歌手', '旧专辑', 1000, 'fp1')",
          );
          raw.execute(
            "INSERT INTO user_likes (song_id, platform, added_at) "
            "VALUES ('s1', 'netease', 111)",
          );
          raw.execute(
            "INSERT INTO listening_history (song_id, platform, listened_at, "
            "duration_listened) VALUES ('s1', 'netease', 222, 3000)",
          );
          raw.execute(
            "INSERT INTO lyrics_cache (song_id, platform, content, format, "
            "synced_at) VALUES ('s1', 'netease', '[00:00.00]词', 'lrc', 333)",
          );

          // This is what makes drift run `onUpgrade` instead of `onCreate`.
          raw.execute('PRAGMA user_version = 1');
        },
      ),
    );
    addTearDown(db.close);

    // --- The upgrade must have run: v2 columns are readable and null. ---
    final song = await db.songsDao.getSong('s1', 'netease');
    expect(song, isNotNull, reason: 'pre-existing song row must survive');
    expect(song!.name, '旧歌');
    expect(song.artists, '旧歌手');
    expect(song.albumId, isNull, reason: 'v2 column, no backfill possible');
    expect(song.artistId, isNull, reason: 'v2 column, no backfill possible');
    expect(song.trackNumber, isNull);

    // --- Pre-existing rows in the other tables survive. ---
    expect(await db.likesDao.isLiked('s1', 'netease'), isTrue);
    final history = await db.historyDao.getRecentHistory();
    expect(history, hasLength(1));
    expect(history.single.durationListened, 3000);
    expect(
      await db.lyricsCacheDao.getCachedLyrics('s1', 'netease'),
      '[00:00.00]词',
    );

    // --- The new v2 tables exist and are empty. ---
    expect(await db.select(db.localTracks).get(), isEmpty);
    expect(await db.select(db.toplistsCache).get(), isEmpty);
    expect(await db.select(db.playEvents).get(), isEmpty);
    expect(await db.select(db.dailyStats).get(), isEmpty);
    expect(await db.select(db.smartPlaylistSnapshots).get(), isEmpty);

    // --- The dead v1 table is gone. ---
    final playlistsTable = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name = 'playlists'",
        )
        .get();
    expect(playlistsTable, isEmpty, reason: 'dead v1 table must be dropped');

    // --- A brand new install still reports schema v2. ---
    expect(db.schemaVersion, 2);
  });

  test('the v2 tables are usable through their DAOs after an upgrade', () async {
    // Same "real v1 database" trick, then exercise each new DAO: an upgrade that
    // created a table with the wrong columns would only show up here.
    final db = AppDatabase.forTesting(
      NativeDatabase(
        dbFile,
        setup: (raw) {
          raw.execute('''
            CREATE TABLE songs (
              id TEXT NOT NULL,
              platform TEXT NOT NULL,
              name TEXT NOT NULL,
              artists TEXT NOT NULL,
              album_name TEXT,
              album_cover TEXT,
              duration_ms INTEGER NOT NULL DEFAULT 0,
              fingerprint TEXT NOT NULL,
              PRIMARY KEY (id, platform)
            );
          ''');
          raw.execute('''
            CREATE TABLE listening_history (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              song_id TEXT NOT NULL,
              platform TEXT NOT NULL,
              listened_at INTEGER NOT NULL,
              duration_listened INTEGER NOT NULL DEFAULT 0
            );
          ''');
          raw.execute('''
            CREATE TABLE user_likes (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              song_id TEXT NOT NULL,
              platform TEXT NOT NULL,
              added_at INTEGER NOT NULL
            );
          ''');
          raw.execute('''
            CREATE TABLE lyrics_cache (
              song_id TEXT NOT NULL,
              platform TEXT NOT NULL,
              content TEXT NOT NULL,
              format TEXT NOT NULL,
              synced_at INTEGER NOT NULL,
              PRIMARY KEY (song_id, platform)
            );
          ''');
          raw.execute('PRAGMA user_version = 1');
        },
      ),
    );
    addTearDown(db.close);

    await db.statsDao.recordPlayStart(
      songId: 's1',
      platform: 'netease',
      startedAt: DateTime(2026, 5, 30, 10),
    );
    await db.statsDao.addListenedDuration(
      songId: 's1',
      platform: 'netease',
      duration: const Duration(minutes: 3),
    );
    expect(await db.statsDao.countPlayEvents(), 1);
    expect(await db.statsDao.activeDayCount(), 1);
    expect(
      (await db.statsDao.songAggregate('s1', 'netease'))!.listenMs,
      const Duration(minutes: 3).inMilliseconds,
    );

    await db.localTracksDao.upsertAll([
      LocalTracksCompanion.insert(
        path: 'C:/music/upgraded.mp3',
        mtime: 1,
        size: 2,
      ),
    ]);
    expect(await db.localTracksDao.count(), 1);

    await db.toplistsCacheDao.replaceForPlatform('qq', [
      ToplistsCacheCompanion.insert(
        platform: 'qq',
        toplistId: '26',
        name: '热歌榜',
        fetchedAt: 1,
      ),
    ]);
    expect(await db.toplistsCacheDao.byPlatform('qq'), hasLength(1));

    await db.smartPlaylistSnapshotsDao.saveSnapshot(
      ruleId: 'rule-1',
      songKeys: const ['netease:s1'],
    );
    expect(
      await db.smartPlaylistSnapshotsDao.songKeys('rule-1'),
      ['netease:s1'],
    );
  });

  test('a fresh database is created at v2 with every table', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.songsDao.insertSong(
      const SongsCompanion(
        id: Value('fresh'),
        platform: Value('qq'),
        name: Value('新歌'),
        artists: Value('歌手'),
        fingerprint: Value('fp'),
      ),
    );

    expect(await db.songsDao.getSong('fresh', 'qq'), isNotNull);
    expect(await db.select(db.playEvents).get(), isEmpty);
    expect(await db.select(db.localTracks).get(), isEmpty);
  });
}
