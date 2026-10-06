import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/database/app_database.dart';
import 'package:mconnect/features/stats/data/listening_stats_repository.dart';
import 'package:mconnect/features/stats/domain/listening_stats.dart';
import 'package:mconnect/models/album.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('statistics detail', () {
    test('160 songs keep full detail and the totals reconcile', () async {
      final repository = DriftListeningStatsRepository(db);
      final anchor = DateTime(2026, 5, 30, 20);

      for (var index = 0; index < 160; index++) {
        final song = _song('song-$index', duration: const Duration(minutes: 3));
        await repository.recordSongStarted(
          song,
          at: anchor.add(Duration(minutes: index)),
        );
        await repository.addListenedDuration(
          song,
          Duration(seconds: 10 + index),
          at: anchor.add(Duration(minutes: index)),
        );
      }

      final state = await repository.load();
      expect(state.totalSongCount, 160);
      expect(state.totalPlayCount, 160);
      expect(state.allSongs, hasLength(160));
      expect(state.topSongs, hasLength(listeningStatsTopSongViewLimit));

      // Song #1 is far outside the ranked view and still fully intact — the old
      // Hive store truncated the list to 100 and rebuilt its index from it, so
      // this row would have been destroyed for good.
      expect(state.topSongs.any((entry) => entry.songId == 'song-0'), isFalse);
      final first = await repository.songStats('song-0', PlatformType.netease);
      expect(first, isNotNull);
      expect(first!.playCount, 1);
      expect(first.listenDuration, const Duration(seconds: 10));

      final detailDuration = state.allSongs.fold<Duration>(
        Duration.zero,
        (sum, entry) => sum + entry.listenDuration,
      );
      expect(detailDuration, state.totalListenDuration);
      expect(
        state.allSongs.fold<int>(0, (sum, entry) => sum + entry.playCount),
        state.totalPlayCount,
      );
    });

    test('the SQL aggregate agrees with the in-memory implementation', () async {
      final drift = DriftListeningStatsRepository(db);
      final memory = MemoryListeningStatsRepository();
      final anchor = DateTime(2026, 5, 30, 12);

      for (var index = 0; index < 12; index++) {
        final song = _song('song-$index');
        final at = anchor.add(Duration(minutes: index));
        await drift.recordSongStarted(song, at: at);
        await drift.addListenedDuration(
          song,
          Duration(seconds: 30 + index),
          at: at,
        );
        await memory.recordSongStarted(song, at: at);
        await memory.addListenedDuration(
          song,
          Duration(seconds: 30 + index),
          at: at,
        );
      }

      final driftState = await drift.load();
      final memoryState = await memory.load();
      expect(driftState.totalPlayCount, memoryState.totalPlayCount);
      expect(driftState.totalListenDuration, memoryState.totalListenDuration);
      expect(driftState.totalSongCount, memoryState.totalSongCount);
      expect(
        _byKey(driftState),
        _byKey(memoryState),
        reason: 'both implementations must produce identical per-song numbers',
      );
    });

    test('per-song aggregate is computed from the raw events', () async {
      final repository = DriftListeningStatsRepository(db);
      final song = _song('repeat');
      final anchor = DateTime(2026, 5, 30, 8);

      for (var index = 0; index < 3; index++) {
        await repository.recordSongStarted(
          song,
          at: anchor.add(Duration(hours: index)),
        );
        await repository.addListenedDuration(
          song,
          const Duration(minutes: 2),
          at: anchor.add(Duration(hours: index)),
        );
      }

      final aggregate = await db.statsDao.songAggregate('repeat', 'netease');
      expect(aggregate!.playCount, 3);
      expect(
        aggregate.listenMs,
        const Duration(minutes: 6).inMilliseconds,
        reason: 'three 2-minute stretches',
      );
      expect(
        aggregate.lastPlayedAt,
        anchor.add(const Duration(hours: 2)).millisecondsSinceEpoch,
      );
      // Completion ratio is derived from the platform-reported duration.
      final events = await db.statsDao.allPlayEvents();
      expect(events.every((event) => event.completedRatio > 0), isTrue);
    });

    test('daily roll-up buckets plays by local day', () async {
      final repository = DriftListeningStatsRepository(db);
      final song = _song('daily');

      await repository.recordSongStarted(song, at: DateTime(2026, 5, 29, 23));
      await repository.addListenedDuration(
        song,
        const Duration(minutes: 4),
        at: DateTime(2026, 5, 29, 23, 4),
      );
      await repository.recordSongStarted(song, at: DateTime(2026, 5, 30, 1));
      await repository.addListenedDuration(
        song,
        const Duration(minutes: 2),
        at: DateTime(2026, 5, 30, 1, 2),
      );

      final state = await repository.load();
      expect(state.activeDayCount, 2);

      final series = await db.statsDao.dailySeries();
      expect(series.map((row) => row.day), ['2026-05-30', '2026-05-29']);
      expect(series.first.playCount, 1);
      expect(series.first.listenMs, const Duration(minutes: 2).inMilliseconds);
    });

    test('dimensions join the cached song metadata', () async {
      final repository = DriftListeningStatsRepository(db);
      final morning = Song(
        id: 'm',
        platform: PlatformType.netease,
        name: '晨间曲',
        artists: const [Artist(id: 'a1', name: '歌手甲')],
        album: const Album(id: 'al1', name: '专辑一'),
        duration: const Duration(minutes: 3),
      );
      final night = Song(
        id: 'n',
        platform: PlatformType.qq,
        name: '夜曲',
        artists: const [Artist(id: 'a2', name: '歌手乙')],
        album: const Album(id: 'al2', name: '专辑二'),
        duration: const Duration(minutes: 3),
      );

      await repository.recordSongStarted(morning, at: DateTime(2026, 5, 30, 9));
      await repository.addListenedDuration(
        morning,
        const Duration(minutes: 5),
        at: DateTime(2026, 5, 30, 9, 5),
      );
      await repository.recordSongStarted(night, at: DateTime(2026, 5, 30, 22));
      await repository.addListenedDuration(
        night,
        const Duration(minutes: 1),
        at: DateTime(2026, 5, 30, 22, 1),
      );

      final report = await repository.loadReport();
      expect(report.artists.map((row) => row.label), ['歌手甲', '歌手乙']);
      expect(report.albums.map((row) => row.label), ['专辑一', '专辑二']);
      expect(
        report.platforms.map((row) => row.label).toSet(),
        {'netease', 'qq'},
      );
      expect(report.days.single.day, '2026-05-30');
      expect(report.hours[9].playCount, 1);
      expect(report.hours[22].playCount, 1);
      expect(report.hours[9].listenDuration, const Duration(minutes: 5));
    });

    test('clearing statistics empties both the detail and the roll-up', () async {
      final repository = DriftListeningStatsRepository(db);
      await repository.recordSongStarted(_song('gone'));
      await repository.addListenedDuration(
        _song('gone'),
        const Duration(minutes: 1),
      );

      await repository.clear();

      expect(await db.statsDao.countPlayEvents(), 0);
      expect(await db.select(db.dailyStats).get(), isEmpty);
      final state = await repository.load();
      expect(state.totalPlayCount, 0);
      expect(state.totalSongCount, 0);
    });

    test('a duration without a recorded start is kept, not dropped', () async {
      final repository = DriftListeningStatsRepository(db);
      final song = _song('orphan');
      await repository.addListenedDuration(song, const Duration(minutes: 2));

      final state = await repository.load();
      expect(state.totalListenDuration, const Duration(minutes: 2));
      // `seek` marks the event as time-only rather than a real play count.
      expect((await db.statsDao.allPlayEvents()).single.source, 'seek');
    });
  });

  group('history de-duplication', () {
    test('listens inside the dedupe window merge into one row', () async {
      final base = DateTime(2026, 5, 30, 10);
      await db.historyDao.recordListen('s1', 'netease', at: base);
      await db.historyDao.recordListen(
        's1',
        'netease',
        at: base.add(const Duration(seconds: 5)),
      );

      expect(await db.historyDao.countHistory(), 1);
    });

    test('listens outside the dedupe window create a second row', () async {
      final base = DateTime(2026, 5, 30, 10);
      await db.historyDao.recordListen('s1', 'netease', at: base);
      await db.historyDao.recordListen(
        's1',
        'netease',
        at: base.add(HistoryDao.dedupeWindow + const Duration(seconds: 1)),
      );

      expect(await db.historyDao.countHistory(), 2);
    });

    test('a legacy row with the same millisecond is not needed for dedupe', () async {
      // The old `uniqueKeys {songId, platform, listenedAt}` could never fire
      // because `listenedAt` is "now" at insert time. The window is what
      // enforces it, and it stays independent of the clock resolution.
      final base = DateTime(2026, 5, 30, 10);
      await db.historyDao.recordListen('s1', 'netease', at: base);
      await db.historyDao.recordListen('s1', 'netease', at: base);
      expect(await db.historyDao.countHistory(), 1);
    });

    test('duration backfill adds listened time to the newest row', () async {
      final base = DateTime(2026, 5, 30, 10);
      await db.historyDao.recordListen('s1', 'netease', at: base);
      await db.historyDao.backfillListenedDuration(
        's1',
        'netease',
        const Duration(minutes: 3),
        at: base.add(const Duration(minutes: 1)),
      );

      final rows = await db.historyDao.getRecentHistory();
      expect(rows, hasLength(1));
      expect(rows.single.durationListened, const Duration(minutes: 3).inMilliseconds);
    });

    test('duration backfill outside the window starts a fresh row', () async {
      final base = DateTime(2026, 5, 30, 10);
      await db.historyDao.recordListen('s1', 'netease', at: base);
      await db.historyDao.backfillListenedDuration(
        's1',
        'netease',
        const Duration(minutes: 2),
        at: base.add(HistoryDao.backfillWindow + const Duration(minutes: 1)),
      );

      expect(await db.historyDao.countHistory(), 2);
    });

    test('backfill keeps the largest duration when a listen is merged', () async {
      final base = DateTime(2026, 5, 30, 10);
      await db.historyDao.recordListen(
        's1',
        'netease',
        durationMs: 90000,
        at: base,
      );
      await db.historyDao.recordListen(
        's1',
        'netease',
        durationMs: 40000,
        at: base.add(const Duration(seconds: 3)),
      );

      final rows = await db.historyDao.getRecentHistory();
      expect(rows, hasLength(1));
      expect(rows.single.durationListened, 90000);
    });
  });

  group('v2 table DAOs', () {
    test('local tracks CRUD, stamps and stale cleanup', () async {
      await db.localTracksDao.upsertAll([
        LocalTracksCompanion.insert(
          path: 'C:/music/a.mp3',
          mtime: 100,
          size: 1000,
          title: const Value('A'),
        ),
        LocalTracksCompanion.insert(
          path: 'C:/music/b.mp3',
          mtime: 200,
          size: 2000,
        ),
      ]);

      expect(await db.localTracksDao.count(), 2);
      expect(
        (await db.localTracksDao.stamps())['C:/music/a.mp3'],
        (mtime: 100, size: 1000),
      );
      expect((await db.localTracksDao.byPath('C:/music/b.mp3'))!.mtime, 200);

      // Unchanged files are skipped by the scanner; deleted ones are dropped.
      expect(
        await db.localTracksDao.deleteMissing({'C:/music/a.mp3'}),
        1,
      );
      expect(await db.localTracksDao.allPaths(), ['C:/music/a.mp3']);

      await db.localTracksDao.deleteByPath('C:/music/a.mp3');
      expect(await db.localTracksDao.count(), 0);
      expect(await db.localTracksDao.clear(), 0);
    });

    test('chart cache replaces one platform at a time', () async {
      await db.toplistsCacheDao.replaceForPlatform('qq', [
        ToplistsCacheCompanion.insert(
          platform: 'qq',
          toplistId: '26',
          name: '热歌榜',
          fetchedAt: 1000,
        ),
      ]);
      await db.toplistsCacheDao.replaceForPlatform('netease', [
        ToplistsCacheCompanion.insert(
          platform: 'netease',
          toplistId: '3778678',
          name: '热歌榜',
          fetchedAt: 2000,
        ),
      ]);

      expect((await db.toplistsCacheDao.byPlatform('qq')).single.toplistId, '26');
      expect(
        (await db.toplistsCacheDao.lastFetchedAt('netease'))!.millisecondsSinceEpoch,
        2000,
      );

      // A refresh of one platform must not wipe the other's cache.
      await db.toplistsCacheDao.replaceForPlatform('qq', [
        ToplistsCacheCompanion.insert(
          platform: 'qq',
          toplistId: '27',
          name: '新歌榜',
          fetchedAt: 3000,
        ),
      ]);
      expect(
        (await db.toplistsCacheDao.byPlatform('qq')).map((row) => row.toplistId),
        ['27'],
      );
      expect(await db.toplistsCacheDao.byPlatform('netease'), hasLength(1));

      expect(await db.toplistsCacheDao.clearPlatform('netease'), 1);
      expect(await db.toplistsCacheDao.clearAll(), 1);
    });

    test('smart playlist snapshots round-trip their song keys', () async {
      await db.smartPlaylistSnapshotsDao.saveSnapshot(
        ruleId: 'rule-1',
        songKeys: const ['netease:1', 'qq:2'],
        generatedAt: DateTime(2026, 5, 30, 9),
      );

      final row = await db.smartPlaylistSnapshotsDao.snapshot('rule-1');
      expect(
        SmartPlaylistSnapshotsDao.decodeSongKeys(row!.songKeys),
        ['netease:1', 'qq:2'],
      );
      expect(
        await db.smartPlaylistSnapshotsDao.songKeys('rule-1'),
        ['netease:1', 'qq:2'],
      );

      // Corrupt payloads degrade to "nothing saved" instead of throwing.
      expect(SmartPlaylistSnapshotsDao.decodeSongKeys('{not json'), isEmpty);

      await db.smartPlaylistSnapshotsDao.saveSnapshot(
        ruleId: 'rule-2',
        songKeys: const ['kugou:3'],
      );
      expect(await db.smartPlaylistSnapshotsDao.deleteMissing({'rule-1'}), 1);
      expect(await db.smartPlaylistSnapshotsDao.all(), hasLength(1));

      expect(await db.smartPlaylistSnapshotsDao.deleteSnapshot('rule-1'), 1);
      await db.smartPlaylistSnapshotsDao.saveSnapshot(
        ruleId: 'rule-3',
        songKeys: const ['kugou:4'],
      );
      expect(await db.smartPlaylistSnapshotsDao.clear(), 1);
      expect(await db.smartPlaylistSnapshotsDao.all(), isEmpty);
    });

    test('play events restored from a backup are deduped', () async {
      final base = DateTime(2026, 5, 30, 10);
      await db.statsDao.recordPlayStart(
        songId: 's1',
        platform: 'netease',
        startedAt: base,
      );
      final existing = await db.statsDao.allPlayEvents();

      final inserted = await db.statsDao.restorePlayEvents(existing);
      expect(inserted, 0, reason: 're-importing the same event must be a no-op');
      expect(await db.statsDao.countPlayEvents(), 1);

      final restored = await db.statsDao.restorePlayEvents([
        PlayEvent(
          id: 0,
          songId: 's2',
          platform: 'qq',
          startedAt: base.add(const Duration(hours: 1)).millisecondsSinceEpoch,
          endedAt: null,
          durationListened: 60000,
          completedRatio: 0.5,
          source: 'play',
        ),
      ]);
      expect(restored, 1);
      expect(await db.statsDao.countPlayEvents(), 2);
      // The daily roll-up is rebuilt from the restored events as well.
      expect(
        (await db.statsDao.dailySeries()).single.playCount,
        2,
      );
    });
  });
}

Song _song(String id, {Duration duration = const Duration(minutes: 3)}) {
  return Song(
    id: id,
    platform: PlatformType.netease,
    name: '歌曲 $id',
    artists: const [Artist(id: 'artist', name: '歌手')],
    album: const Album(id: 'album', name: '专辑'),
    duration: duration,
  );
}

Map<String, String> _byKey(ListeningStatsState state) {
  return {
    for (final entry in state.allSongs)
      entry.key: '${entry.playCount}:${entry.listenDuration.inMilliseconds}',
  };
}
