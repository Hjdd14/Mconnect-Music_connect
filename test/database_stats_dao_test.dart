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

  group('v3 query shapes', () {
    test('hourHistogram buckets in SQL exactly like the Dart version did', () async {
      // The reference implementation below is the pre-v3 Dart bucketing, kept in
      // the test on purpose: the SQL rewrite has to agree with it bucket for
      // bucket, including the local-time zone rules SQLite's `'localtime'` and
      // `DateTime.toLocal()` each apply.
      final base = DateTime(2026, 5, 30);
      await _insertEvent(
        db,
        'a',
        base.add(const Duration(hours: 9, minutes: 5)),
        60000,
      );
      await _insertEvent(
        db,
        'b',
        base.add(const Duration(hours: 9, minutes: 55)),
        30000,
      );
      await _insertEvent(
        db,
        'c',
        base.add(const Duration(hours: 23, minutes: 59)),
        10000,
      );
      await _insertEvent(db, 'd', base.add(const Duration(days: 1)), 5000);
      await _insertEvent(
        db,
        'e',
        base.add(const Duration(days: 1, hours: 12)),
        2000,
      );

      final histogram = await db.statsDao.hourHistogram();

      expect(histogram, hasLength(24), reason: 'every bucket is always reported');
      expect(histogram.map((row) => row.hour), List.generate(24, (i) => i));

      final reference = await _dartHourHistogram(db);
      expect(
        [for (final row in histogram) (row.playCount, row.listenMs)],
        [for (final row in reference) (row.playCount, row.listenMs)],
        reason: "SQLite 'localtime' must agree with Dart toLocal() in all 24 buckets",
      );

      // Sanity on the seeded hours, so an all-zero agreement cannot pass.
      expect(histogram[9].playCount, 2);
      expect(histogram[9].listenMs, 90000);
      expect(histogram[23].playCount, 1);
      expect(histogram[23].listenMs, 10000);
      expect(histogram[0].playCount, 1);
      expect(histogram[12].playCount, 1);
    });

    test('hourHistogram is empty-but-complete with no events', () async {
      final histogram = await db.statsDao.hourHistogram();
      expect(histogram, hasLength(24));
      expect(histogram.every((row) => row.playCount == 0), isTrue);
      expect(histogram.every((row) => row.listenMs == 0), isTrue);
    });

    test('a bulk restore inserts in one batch and folds the roll-up per group', () async {
      final base = DateTime(2026, 5, 30, 8);
      await db.statsDao.recordPlayStart(
        songId: 'existing',
        platform: 'netease',
        startedAt: base,
      );
      final existingRows = await db.statsDao.allPlayEvents();
      // `recordPlayStart` has already put one play into `base`'s day, so the
      // restore's contribution must be measured **as a delta** on top of it —
      // comparing absolute totals would silently credit the payload with a play
      // the fixture itself created.
      final rollUpBefore = await _dayRollUp(db);
      final baseDay = StatsDao.dayKey(base);
      expect(rollUpBefore[baseDay]!.plays, 1);
      expect(
        rollUpBefore[baseDay]!.listenMs,
        0,
        reason: 'recordPlayStart adds a play but no listened time',
      );

      // 600 distinct events over ~15 days and 6 songs, with mixed platforms so
      // the roll-up grouping has to keep (day, song, platform) apart.
      final payload = <PlayEvent>[
        for (var i = 0; i < 600; i++)
          PlayEvent(
            id: 0,
            songId: 'song-${i % 6}',
            platform: i.isEven ? 'netease' : 'qq',
            startedAt: base.add(Duration(minutes: i * 37)).millisecondsSinceEpoch,
            endedAt: null,
            durationListened: 1000 + i,
            completedRatio: 0.5,
            source: 'play',
          ),
      ];
      // One row that is already in the table and one duplicate inside the
      // payload: both must be skipped, and neither may touch the roll-up.
      payload
        ..add(existingRows.single)
        ..add(payload.first);

      final inserted = await db.statsDao.restorePlayEvents(payload);

      expect(
        inserted,
        600,
        reason: 'the existing row and the in-payload duplicate are both skipped',
      );
      expect(await db.statsDao.countPlayEvents(), 601);

      // What the 600 inserted events must contribute, per day.
      final expectedDelta = <String, ({int plays, int listenMs})>{};
      for (final row in payload.take(600)) {
        final day = StatsDao.dayKey(
          DateTime.fromMillisecondsSinceEpoch(row.startedAt),
        );
        final current = expectedDelta[day] ?? (plays: 0, listenMs: 0);
        expectedDelta[day] = (
          plays: current.plays + 1,
          listenMs: current.listenMs + row.durationListened,
        );
      }

      final rollUpAfter = await _dayRollUp(db);
      expect(
        rollUpAfter.keys.toSet(),
        {...rollUpBefore.keys, ...expectedDelta.keys},
        reason: 'no day may appear with a roll-up the payload never played on',
      );
      for (final entry in expectedDelta.entries) {
        final start = rollUpBefore[entry.key] ?? (plays: 0, listenMs: 0);
        expect(
          rollUpAfter[entry.key]!.plays - start.plays,
          entry.value.plays,
          reason: '${entry.key}: plays added by the payload',
        );
        expect(
          rollUpAfter[entry.key]!.listenMs - start.listenMs,
          entry.value.listenMs,
          reason: '${entry.key}: listened ms added by the payload',
        );
      }
      // The pre-existing play is still on its own row: 1 (recordPlayStart) + 26
      // payload events before midnight. This pins the absolute the delta above
      // is relative to, so the test cannot pass by shifting both sides.
      expect(rollUpAfter[baseDay]!.plays, 27);
      expect(expectedDelta[baseDay]!.plays, 26);

      // Re-importing the whole payload stays a no-op, including for the roll-up.
      expect(await db.statsDao.restorePlayEvents(payload), 0);
      expect(await db.statsDao.countPlayEvents(), 601);
      expect(await _dayRollUp(db), rollUpAfter);
    });

    test('restoring an empty list does nothing', () async {
      expect(await db.statsDao.restorePlayEvents(const []), 0);
      expect(await db.statsDao.countPlayEvents(), 0);
      expect(await db.select(db.dailyStats).get(), isEmpty);
    });
  });

  group('v3 table DAOs', () {
    test('lyrics offsets are per song, and zero clears the row', () async {
      final at = DateTime(2026, 5, 30, 12);
      await db.lyricsOffsetDao.set(
        'netease:s1',
        const Duration(milliseconds: 750),
        at: at,
      );
      await db.lyricsOffsetDao.set('qq:s2', const Duration(milliseconds: -500));

      expect(
        await db.lyricsOffsetDao.get('netease:s1'),
        const Duration(milliseconds: 750),
      );
      expect(
        (await db.lyricsOffsetDao.row('netease:s1'))!.updatedAt,
        at.millisecondsSinceEpoch,
      );
      // One song's correction must not move another song's lyrics.
      expect(
        await db.lyricsOffsetDao.get('qq:s2'),
        const Duration(milliseconds: -500),
      );
      expect(await db.lyricsOffsetDao.get('kugou:missing'), Duration.zero);

      // A zero offset is "no offset": the row is removed, not stored as 0.
      await db.lyricsOffsetDao.set('qq:s2', Duration.zero);
      expect(await db.lyricsOffsetDao.row('qq:s2'), isNull);
      expect(await db.select(db.lyricsOffsets).get(), hasLength(1));

      expect(await db.lyricsOffsetDao.clear('netease:s1'), 1);
      expect(await db.lyricsOffsetDao.get('netease:s1'), Duration.zero);
    });

    test('source matches expire, purge, clamp and replace', () async {
      final fetched = DateTime(2026, 5, 30, 12);
      await db.sourceMatchCacheDao.put(
        songKey: 'qq:s1',
        targetPlatform: 'netease',
        targetSongId: 'n1',
        url: 'https://example.test/a.mp3',
        urlFetchedAt: fetched,
        expiresAt: fetched.add(const Duration(hours: 2)),
        score: 0.87,
      );

      final cached = await db.sourceMatchCacheDao.get(
        'qq:s1',
        'netease',
        now: fetched,
      );
      expect(cached!.targetSongId, 'n1');
      expect(cached.url, 'https://example.test/a.mp3');
      expect(cached.urlFetchedAt, fetched.millisecondsSinceEpoch);
      expect(cached.score, closeTo(0.87, 1e-9));

      // Past the expiry the row is invisible (never handed out as a stream URL)
      // but still stored, and a sweep can reclaim it.
      final later = fetched.add(const Duration(hours: 3));
      expect(
        await db.sourceMatchCacheDao.get('qq:s1', 'netease', now: later),
        isNull,
      );
      expect(await db.sourceMatchCacheDao.row('qq:s1', 'netease'), isNotNull);
      expect(await db.sourceMatchCacheDao.purgeExpired(now: later), 1);
      expect(await db.sourceMatchCacheDao.row('qq:s1', 'netease'), isNull);

      // Identity-only rows (no url yet) are legal, and scores are clamped.
      await db.sourceMatchCacheDao.put(
        songKey: 'qq:s2',
        targetPlatform: 'kugou',
        targetSongId: 'k1',
        expiresAt: fetched,
        score: 4.2,
      );
      final identityOnly = await db.sourceMatchCacheDao.row('qq:s2', 'kugou');
      expect(identityOnly!.url, isNull);
      expect(identityOnly.urlFetchedAt, isNull);
      expect(identityOnly.score, 1.0);

      // A second put for the same pair replaces instead of duplicating.
      await db.sourceMatchCacheDao.put(
        songKey: 'qq:s1',
        targetPlatform: 'netease',
        targetSongId: 'n2',
        expiresAt: fetched.add(const Duration(days: 1)),
      );
      expect(
        (await db.sourceMatchCacheDao.row('qq:s1', 'netease'))!.targetSongId,
        'n2',
      );
      expect(await db.select(db.sourceMatchCaches).get(), hasLength(2));
      expect(await db.sourceMatchCacheDao.clearAll(), 2);
      expect(await db.sourceMatchCacheDao.purgeExpired(), 0);
    });
  });
}

/// `day → (plays, listenMs)` from the daily roll-up.
///
/// Used for delta assertions: a test that seeds a play of its own (through
/// `recordPlayStart`) must compare the roll-up *before* and *after* the call it
/// is testing, or the fixture's own play gets credited to the code under test.
Future<Map<String, ({int plays, int listenMs})>> _dayRollUp(
  AppDatabase db,
) async {
  return {
    for (final row in await db.statsDao.dailySeries(limit: 100))
      row.day: (plays: row.playCount, listenMs: row.listenMs),
  };
}

/// Inserts one play event directly, with full control over its timestamp and
/// listened time (the DAO's own record path decides those itself).
Future<void> _insertEvent(
  AppDatabase db,
  String songId,
  DateTime startedAt,
  int listenMs,
) async {
  await db.into(db.playEvents).insert(
    PlayEventsCompanion.insert(
      songId: songId,
      platform: 'netease',
      startedAt: startedAt.millisecondsSinceEpoch,
      durationListened: Value(listenMs),
    ),
  );
}

/// The pre-v3 implementation of `hourHistogram`, kept as the reference the SQL
/// rewrite has to match: read every row, bucket it by the local hour.
Future<List<({int hour, int playCount, int listenMs})>> _dartHourHistogram(
  AppDatabase db,
) async {
  final events = await db.statsDao.allPlayEvents();
  final plays = List<int>.filled(24, 0);
  final listenMs = List<int>.filled(24, 0);
  for (final event in events) {
    final hour =
        DateTime.fromMillisecondsSinceEpoch(event.startedAt).toLocal().hour;
    plays[hour] += 1;
    listenMs[hour] += event.durationListened;
  }
  return [
    for (var hour = 0; hour < 24; hour++)
      (hour: hour, playCount: plays[hour], listenMs: listenMs[hour]),
  ];
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
