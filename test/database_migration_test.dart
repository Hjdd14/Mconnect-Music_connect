import 'dart:io';

// `drift` exports SQL `isNull`/`isNotNull` expressions that collide with the
// matcher package's matchers of the same name.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/database/app_database.dart';
import 'package:path/path.dart' as p;

/// Guards the schema upgrade path: v1 → v2 → v3.
///
/// Before v2 the database shipped with `onCreate` only. drift raises
/// `UnsupportedError` for an unhandled version bump (it does **not** silently
/// recreate the file), so without `onUpgrade` the first added column would have
/// crashed every existing install — with the user's likes, history and lyrics
/// cache behind it.
///
/// Every test here builds a **real** old database (hand-written DDL that matches
/// what that shipped version created, plus `PRAGMA user_version`) with rows in
/// it, hands it to the current [AppDatabase], and asserts the upgrade ran, kept
/// the data, and produced the new columns / tables / indexes.
///
/// The index set is asserted explicitly because it is the one part of a schema
/// change that fails silently: a missing index costs performance, never a test.
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

  group('v1 → v3', () {
    test('a v1 database upgrades straight to v3 keeping every row', () async {
      // `setup` runs against the raw sqlite3 handle *before* drift reads the
      // schema version, so this is a genuine v1 database with pre-existing data.
      final db = AppDatabase.forTesting(
        NativeDatabase(
          dbFile,
          setup: (raw) {
            _createV1Schema(raw.execute);
            _seedV1Rows(raw.execute);
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

      // --- The v2 tables exist and are empty. ---
      expect(await db.select(db.localTracks).get(), isEmpty);
      expect(await db.select(db.toplistsCache).get(), isEmpty);
      expect(await db.select(db.playEvents).get(), isEmpty);
      expect(await db.select(db.dailyStats).get(), isEmpty);
      expect(await db.select(db.smartPlaylistSnapshots).get(), isEmpty);

      // --- The v3 tables/columns are there too. ---
      expect(
        await columnsOf(db, 'local_tracks'),
        containsAll(<String>['lyrics_mtime', 'lyrics_size']),
      );
      expect(await db.select(db.lyricsOffsets).get(), isEmpty);
      expect(await db.select(db.sourceMatchCaches).get(), isEmpty);
      expect(
        await indexNames(db),
        containsAll(_v3IndexNames),
        reason: 'the v1 → v3 jump must create the v3 indexes as well',
      );

      // --- The dead v1 table is gone. ---
      final playlistsTable = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name = 'playlists'",
          )
          .get();
      expect(playlistsTable, isEmpty, reason: 'dead v1 table must be dropped');

      // --- A brand new install still reports the current schema. ---
      expect(db.schemaVersion, 3);
    });

    test('the v2 tables are usable through their DAOs after a v1 upgrade', () async {
      // Same "real v1 database" trick, then exercise each new DAO: an upgrade that
      // created a table with the wrong columns would only show up here.
      final db = AppDatabase.forTesting(
        NativeDatabase(
          dbFile,
          setup: (raw) {
            _createV1Schema(raw.execute);
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
          lyricsMtime: const Value(11),
          lyricsSize: const Value(22),
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
  });

  group('v2 → v3', () {
    test('a real v2 database keeps its rows and gains the v3 additions', () async {
      final db = AppDatabase.forTesting(
        NativeDatabase(
          dbFile,
          setup: (raw) {
            _createV2Schema(raw.execute);
            _seedV2Rows(raw.execute);
            raw.execute('PRAGMA user_version = 2');
          },
        ),
      );
      addTearDown(db.close);

      // --- Pre-v3 user data, one row per table that can hold any. ---
      final song = await db.songsDao.getSong('s1', 'netease');
      expect(song, isNotNull);
      expect(song!.name, '旧歌');
      expect(song.albumId, 'al1', reason: 'the v2 album id was already there');
      expect(await db.likesDao.isLiked('s1', 'netease'), isTrue);
      expect(await db.historyDao.countHistory(), 1);
      expect(
        await db.lyricsCacheDao.getCachedLyrics('s1', 'netease'),
        '[00:00.00]词',
      );

      // Play events and their roll-up survive the migration untouched. The
      // fixture seeds **two** events on the same day (see `_seedV2Rows`), and its
      // `daily_stats` row carries the matching `play_count = 2` — so all three
      // of these are "2", and a migration that lost or double-counted a play
      // would break the agreement between them.
      expect(await db.statsDao.countPlayEvents(), 2);
      expect((await db.statsDao.dailySeries()).single.playCount, 2);
      expect(
        (await db.statsDao.songAggregate('s1', 'netease'))!.playCount,
        2,
      );

      // The v2 local-library row survives, with the new columns null.
      final track = await db.localTracksDao.byPath('C:/music/old.mp3');
      expect(track, isNotNull);
      expect(track!.title, '旧曲');
      expect(track.mtime, 100);
      expect(track.lyricsMtime, isNull, reason: 'v3 column, nothing to backfill');
      expect(track.lyricsSize, isNull);

      expect((await db.toplistsCacheDao.byPlatform('qq')).single.name, '热歌榜');
      expect(
        await db.smartPlaylistSnapshotsDao.songKeys('rule-1'),
        ['netease:s1'],
      );

      // --- The v3 additions. ---
      expect(await db.select(db.lyricsOffsets).get(), isEmpty);
      expect(await db.select(db.sourceMatchCaches).get(), isEmpty);
      expect(
        await indexNames(db),
        containsAll(_v3IndexNames),
        reason: 'a v2 database must gain every v3 index on upgrade',
      );
    });

    test('the v3 columns are writable and the v3 DAOs work after an upgrade', () async {
      final db = AppDatabase.forTesting(
        NativeDatabase(
          dbFile,
          setup: (raw) {
            _createV2Schema(raw.execute);
            raw.execute('PRAGMA user_version = 2');
          },
        ),
      );
      addTearDown(db.close);

      await db.localTracksDao.upsert(
        LocalTracksCompanion.insert(
          path: 'C:/music/new.mp3',
          mtime: 1,
          size: 2,
          lyricsMtime: const Value(1234),
          lyricsSize: const Value(99),
        ),
      );
      final row = await db.localTracksDao.byPath('C:/music/new.mp3');
      expect(row!.lyricsMtime, 1234);
      expect(row.lyricsSize, 99);

      await db.lyricsOffsetDao.set('netease:s1', const Duration(seconds: 2));
      expect(
        await db.lyricsOffsetDao.get('netease:s1'),
        const Duration(seconds: 2),
      );
      await db.lyricsOffsetDao.set('netease:s1', Duration.zero);
      expect(await db.lyricsOffsetDao.get('netease:s1'), Duration.zero);

      await db.sourceMatchCacheDao.put(
        songKey: 'qq:s2',
        targetPlatform: 'netease',
        targetSongId: 's1',
        expiresAt: DateTime(2026, 6, 1),
      );
      final cachedMatch = await db.sourceMatchCacheDao.get(
        'qq:s2',
        'netease',
        now: DateTime(2026, 5, 30),
      );
      expect(cachedMatch!.targetSongId, 's1');
    });
  });

  group('schema parity', () {
    test('a fresh v3 database and an upgraded v2 one are the same schema', () async {
      // The upgrade path and `onCreate` are two independent code paths that must
      // agree. Without this test, a column or index added to the table definition
      // alone leaves upgraded installs quietly different from new ones forever.
      final fresh = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(fresh.close);

      final upgraded = AppDatabase.forTesting(
        NativeDatabase(
          dbFile,
          setup: (raw) {
            _createV2Schema(raw.execute);
            raw.execute('PRAGMA user_version = 2');
          },
        ),
      );
      addTearDown(upgraded.close);

      expect(await indexNames(upgraded), await indexNames(fresh));
      expect(await _tableNames(upgraded), await _tableNames(fresh));
      for (final table in const [
        'songs',
        'listening_history',
        'local_tracks',
        'play_events',
        'lyrics_offsets',
        'source_match_caches',
      ]) {
        expect(
          await columnsOf(upgraded, table),
          await columnsOf(fresh, table),
          reason: '$table must have the same columns on both paths',
        );
      }
    });

    test('a fresh database is created at v3 with every table', () async {
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
      expect(await db.select(db.lyricsOffsets).get(), isEmpty);
      expect(await db.select(db.sourceMatchCaches).get(), isEmpty);
      expect(await indexNames(db), containsAll(_v3IndexNames));
      expect(db.schemaVersion, 3);
    });
  });
}

/// The indexes schema v3 introduces, exactly as the `@TableIndex` annotations
/// name them.
const List<String> _v3IndexNames = [
  'listening_history_listened_at',
  'play_events_song_platform',
  'play_events_started_at',
  'local_tracks_path',
];

/// Non-SQLite-owned index names, sorted.
Future<List<String>> indexNames(AppDatabase db) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'index' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name",
      )
      .get();
  return [for (final row in rows) row.read<String>('name')];
}

/// Column names of [table], in declaration order.
///
/// Uses SQLite's table-valued `pragma_table_info` rather than a bare
/// `PRAGMA table_info(...)`: the function form is an ordinary `SELECT`, so it
/// goes through the same statement path as every other query in this file.
Future<List<String>> columnsOf(AppDatabase db, String table) async {
  final rows = await db
      .customSelect("SELECT name FROM pragma_table_info('$table')")
      .get();
  return [for (final row in rows) row.read<String>('name')];
}

Future<List<String>> _tableNames(AppDatabase db) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name",
      )
      .get();
  return [for (final row in rows) row.read<String>('name')];
}

/// The v1 schema exactly as the shipped v1 build created it.
///
/// `playlists` is included because v1 created it (v2 drops it); the three v2
/// columns on `songs` and every v2/v3 table are absent on purpose.
void _createV1Schema(void Function(String sql) execute) {
  execute('''
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
  execute('''
    CREATE TABLE listening_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      song_id TEXT NOT NULL,
      platform TEXT NOT NULL,
      listened_at INTEGER NOT NULL,
      duration_listened INTEGER NOT NULL DEFAULT 0,
      UNIQUE (song_id, platform, listened_at)
    );
  ''');
  execute('''
    CREATE TABLE user_likes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      song_id TEXT NOT NULL,
      platform TEXT NOT NULL,
      added_at INTEGER NOT NULL,
      UNIQUE (song_id, platform)
    );
  ''');
  execute('''
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
  execute('''
    CREATE TABLE playlists (
      id TEXT NOT NULL,
      platform TEXT NOT NULL,
      name TEXT NOT NULL,
      song_count INTEGER NOT NULL DEFAULT 0,
      synced_at INTEGER,
      PRIMARY KEY (id, platform)
    );
  ''');
}

void _seedV1Rows(void Function(String sql) execute) {
  execute(
    "INSERT INTO songs (id, platform, name, artists, album_name, "
    "duration_ms, fingerprint) VALUES "
    "('s1', 'netease', '旧歌', '旧歌手', '旧专辑', 1000, 'fp1')",
  );
  execute(
    "INSERT INTO user_likes (song_id, platform, added_at) "
    "VALUES ('s1', 'netease', 111)",
  );
  execute(
    "INSERT INTO listening_history (song_id, platform, listened_at, "
    "duration_listened) VALUES ('s1', 'netease', 222, 3000)",
  );
  execute(
    "INSERT INTO lyrics_cache (song_id, platform, content, format, "
    "synced_at) VALUES ('s1', 'netease', '[00:00.00]词', 'lrc', 333)",
  );
}

/// The v2 schema exactly as a shipped v2 build created it: the v1 shape plus the
/// v2 columns and tables, minus everything v3 adds (the two `local_tracks`
/// columns, the two cache tables and all four indexes).
void _createV2Schema(void Function(String sql) execute) {
  execute('''
    CREATE TABLE songs (
      id TEXT NOT NULL,
      platform TEXT NOT NULL,
      name TEXT NOT NULL,
      artists TEXT NOT NULL,
      album_name TEXT,
      album_cover TEXT,
      duration_ms INTEGER NOT NULL DEFAULT 0,
      fingerprint TEXT NOT NULL,
      album_id TEXT,
      artist_id TEXT,
      track_number INTEGER,
      PRIMARY KEY (id, platform)
    );
  ''');
  execute('''
    CREATE TABLE listening_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      song_id TEXT NOT NULL,
      platform TEXT NOT NULL,
      listened_at INTEGER NOT NULL,
      duration_listened INTEGER NOT NULL DEFAULT 0,
      UNIQUE (song_id, platform, listened_at)
    );
  ''');
  execute('''
    CREATE TABLE user_likes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      song_id TEXT NOT NULL,
      platform TEXT NOT NULL,
      added_at INTEGER NOT NULL,
      UNIQUE (song_id, platform)
    );
  ''');
  execute('''
    CREATE TABLE lyrics_cache (
      song_id TEXT NOT NULL,
      platform TEXT NOT NULL,
      content TEXT NOT NULL,
      format TEXT NOT NULL,
      synced_at INTEGER NOT NULL,
      PRIMARY KEY (song_id, platform)
    );
  ''');
  // v2 `local_tracks`: no lyrics_mtime / lyrics_size yet.
  execute('''
    CREATE TABLE local_tracks (
      path TEXT NOT NULL,
      mtime INTEGER NOT NULL,
      size INTEGER NOT NULL,
      title TEXT,
      artist_name TEXT,
      album_name TEXT,
      duration_ms INTEGER NOT NULL DEFAULT 0,
      track_number INTEGER,
      cover_path TEXT,
      scanned_at INTEGER,
      PRIMARY KEY (path)
    );
  ''');
  execute('''
    CREATE TABLE toplists_cache (
      platform TEXT NOT NULL,
      toplist_id TEXT NOT NULL,
      name TEXT NOT NULL,
      cover_url TEXT,
      update_frequency TEXT,
      period TEXT,
      song_count INTEGER,
      group_name TEXT,
      intro TEXT,
      fetched_at INTEGER NOT NULL,
      PRIMARY KEY (platform, toplist_id)
    );
  ''');
  execute('''
    CREATE TABLE play_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      song_id TEXT NOT NULL,
      platform TEXT NOT NULL,
      started_at INTEGER NOT NULL,
      ended_at INTEGER,
      duration_listened INTEGER NOT NULL DEFAULT 0,
      completed_ratio REAL NOT NULL DEFAULT 0,
      source TEXT
    );
  ''');
  execute('''
    CREATE TABLE daily_stats (
      day TEXT NOT NULL,
      song_id TEXT NOT NULL,
      platform TEXT NOT NULL,
      play_count INTEGER NOT NULL DEFAULT 0,
      listen_ms INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (day, song_id, platform)
    );
  ''');
  execute('''
    CREATE TABLE smart_playlist_snapshots (
      rule_id TEXT NOT NULL,
      song_keys TEXT NOT NULL,
      generated_at INTEGER NOT NULL,
      PRIMARY KEY (rule_id)
    );
  ''');
}

void _seedV2Rows(void Function(String sql) execute) {
  execute(
    "INSERT INTO songs (id, platform, name, artists, album_name, "
    "duration_ms, fingerprint, album_id, artist_id, track_number) VALUES "
    "('s1', 'netease', '旧歌', '旧歌手', '旧专辑', 1000, 'fp1', 'al1', 'ar1', 3)",
  );
  execute(
    "INSERT INTO user_likes (song_id, platform, added_at) "
    "VALUES ('s1', 'netease', 111)",
  );
  execute(
    "INSERT INTO listening_history (song_id, platform, listened_at, "
    "duration_listened) VALUES ('s1', 'netease', 222, 3000)",
  );
  execute(
    "INSERT INTO lyrics_cache (song_id, platform, content, format, "
    "synced_at) VALUES ('s1', 'netease', '[00:00.00]词', 'lrc', 333)",
  );
  execute(
    "INSERT INTO local_tracks (path, mtime, size, title, duration_ms, "
    "scanned_at) VALUES ('C:/music/old.mp3', 100, 200, '旧曲', 5000, 9)",
  );
  execute(
    "INSERT INTO toplists_cache (platform, toplist_id, name, fetched_at) "
    "VALUES ('qq', '26', '热歌榜', 1000)",
  );
  // Two plays on the same day: the roll-up must survive as a two-play row.
  execute(
    "INSERT INTO play_events (song_id, platform, started_at, "
    "duration_listened, completed_ratio, source) VALUES "
    "('s1', 'netease', 1767000000000, 60000, 0.5, 'play')",
  );
  execute(
    "INSERT INTO play_events (song_id, platform, started_at, "
    "duration_listened, completed_ratio, source) VALUES "
    "('s1', 'netease', 1767000600000, 30000, 0.25, 'play')",
  );
  final day = StatsDao.dayKey(
    DateTime.fromMillisecondsSinceEpoch(1767000000000),
  );
  execute(
    "INSERT INTO daily_stats (day, song_id, platform, play_count, listen_ms) "
    "VALUES ('$day', 's1', 'netease', 2, 90000)",
  );
  execute(
    "INSERT INTO smart_playlist_snapshots (rule_id, song_keys, generated_at) "
    "VALUES ('rule-1', '[\"netease:s1\"]', 1234)",
  );
}
