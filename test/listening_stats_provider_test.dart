import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/database/app_database.dart';
import 'package:mconnect/features/stats/presentation/providers/listening_stats_provider.dart';
import 'package:mconnect/models/album.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

void main() {
  test(
    'listening stats starts loading without explicitly reading ready',
    () async {
      final repository = MemoryListeningStatsRepository();
      final notifier = ListeningStatsNotifier(
        repository,
        importLegacySnapshot: false,
      );

      await Future<void>.delayed(Duration.zero);

      expect(notifier.state.isLoading, isFalse);
    },
  );

  test(
    'listening stats accumulates play count and listened duration',
    () async {
      final repository = MemoryListeningStatsRepository();
      final notifier = ListeningStatsNotifier(
        repository,
        importLegacySnapshot: false,
      );
      await notifier.ready;

      final song = _song('song-1');
      await notifier.recordSongStarted(song);
      await notifier.addListenedDuration(song, const Duration(seconds: 75));

      expect(notifier.state.totalPlayCount, 1);
      expect(notifier.state.totalListenDuration, const Duration(seconds: 75));
      expect(notifier.state.topSongs.single.songId, 'song-1');
      expect(notifier.state.topSongs.single.playCount, 1);
      expect(
        notifier.state.topSongs.single.listenDuration,
        const Duration(seconds: 75),
      );
    },
  );

  test(
    'listening stats tracker ignores seek jumps while counting real progress',
    () async {
      final repository = MemoryListeningStatsRepository();
      final notifier = ListeningStatsNotifier(
        repository,
        importLegacySnapshot: false,
      );
      await notifier.ready;
      final tracker = ListeningStatsTracker(
        notifier: notifier,
        flushInterval: Duration.zero,
      );

      final song = _song('tracked');
      await tracker.handlePlaybackSnapshot(
        previous: const ListeningPlaybackSnapshot(),
        next: ListeningPlaybackSnapshot(
          song: song,
          isPlaying: true,
          position: Duration.zero,
        ),
      );
      await tracker.handlePlaybackSnapshot(
        previous: ListeningPlaybackSnapshot(
          song: song,
          isPlaying: true,
          position: Duration.zero,
        ),
        next: ListeningPlaybackSnapshot(
          song: song,
          isPlaying: true,
          position: const Duration(seconds: 3),
        ),
      );
      await tracker.handlePlaybackSnapshot(
        previous: ListeningPlaybackSnapshot(
          song: song,
          isPlaying: true,
          position: const Duration(seconds: 3),
        ),
        next: ListeningPlaybackSnapshot(
          song: song,
          isPlaying: true,
          position: const Duration(minutes: 1),
        ),
      );

      expect(notifier.state.totalPlayCount, 1);
      expect(notifier.state.totalListenDuration, const Duration(seconds: 3));
    },
  );

  // Red → green: before the fix the play count was incremented on every
  // `isPlaying` rising edge, so pausing and resuming mid-song was counted as a
  // second play (`listening_stats_provider.dart` old line 342).
  test('pausing and resuming mid-song is not a new play', () async {
    final repository = MemoryListeningStatsRepository();
    final notifier = ListeningStatsNotifier(
      repository,
      importLegacySnapshot: false,
    );
    await notifier.ready;
    final tracker = ListeningStatsTracker(
      notifier: notifier,
      flushInterval: Duration.zero,
    );

    final song = _song('resumed');
    await tracker.handlePlaybackSnapshot(
      previous: const ListeningPlaybackSnapshot(),
      next: ListeningPlaybackSnapshot(
        song: song,
        isPlaying: true,
        position: Duration.zero,
      ),
    );
    // Pause at 30s...
    await tracker.handlePlaybackSnapshot(
      previous: ListeningPlaybackSnapshot(
        song: song,
        isPlaying: true,
        position: const Duration(seconds: 30),
      ),
      next: ListeningPlaybackSnapshot(
        song: song,
        isPlaying: false,
        position: const Duration(seconds: 30),
      ),
    );
    // ...and resume where it stopped.
    await tracker.handlePlaybackSnapshot(
      previous: ListeningPlaybackSnapshot(
        song: song,
        isPlaying: false,
        position: const Duration(seconds: 30),
      ),
      next: ListeningPlaybackSnapshot(
        song: song,
        isPlaying: true,
        position: const Duration(seconds: 30),
      ),
    );

    expect(notifier.state.totalPlayCount, 1);
  });

  test('restarting the same song from the top is a new play', () async {
    final repository = MemoryListeningStatsRepository();
    final notifier = ListeningStatsNotifier(
      repository,
      importLegacySnapshot: false,
    );
    await notifier.ready;
    final tracker = ListeningStatsTracker(
      notifier: notifier,
      flushInterval: Duration.zero,
    );

    final song = _song('restarted');
    await tracker.handlePlaybackSnapshot(
      previous: const ListeningPlaybackSnapshot(),
      next: ListeningPlaybackSnapshot(
        song: song,
        isPlaying: true,
        position: Duration.zero,
      ),
    );
    await tracker.handlePlaybackSnapshot(
      previous: ListeningPlaybackSnapshot(
        song: song,
        isPlaying: true,
        position: const Duration(minutes: 3),
      ),
      next: ListeningPlaybackSnapshot(
        song: song,
        isPlaying: true,
        position: const Duration(seconds: 1),
      ),
    );

    expect(notifier.state.totalPlayCount, 2);
  });

  test('switching songs still counts one play per song', () async {
    final repository = MemoryListeningStatsRepository();
    final notifier = ListeningStatsNotifier(
      repository,
      importLegacySnapshot: false,
    );
    await notifier.ready;
    final tracker = ListeningStatsTracker(
      notifier: notifier,
      flushInterval: Duration.zero,
    );

    final first = _song('first');
    final second = _song('second');
    await tracker.handlePlaybackSnapshot(
      previous: const ListeningPlaybackSnapshot(),
      next: ListeningPlaybackSnapshot(
        song: first,
        isPlaying: true,
        position: Duration.zero,
      ),
    );
    await tracker.handlePlaybackSnapshot(
      previous: ListeningPlaybackSnapshot(
        song: first,
        isPlaying: true,
        position: const Duration(minutes: 2),
      ),
      next: ListeningPlaybackSnapshot(
        song: second,
        isPlaying: true,
        position: Duration.zero,
      ),
    );

    expect(notifier.state.totalPlayCount, 2);
    expect(notifier.state.totalSongCount, 2);
  });

  // The regression this whole rewrite exists for: the store used to keep only
  // the top 100 songs, so song number 101 deleted the statistics of the
  // least-played song while the global totals stayed complete.
  test('160 songs keep every song detail (no top-100 truncation)', () async {
    final repository = MemoryListeningStatsRepository();
    final notifier = ListeningStatsNotifier(
      repository,
      importLegacySnapshot: false,
    );
    await notifier.ready;

    for (var index = 0; index < 160; index++) {
      final song = _song('song-$index');
      await notifier.recordSongStarted(song);
      // Increasing duration so the first songs rank last and would be the ones
      // pushed out of a top-100 list.
      await notifier.addListenedDuration(
        song,
        Duration(seconds: 10 + index),
      );
    }

    final state = notifier.state;
    expect(state.totalPlayCount, 160);
    expect(state.totalSongCount, 160);
    expect(state.allSongs, hasLength(160));
    expect(
      state.topSongs.length,
      listeningStatsTopSongViewLimit,
      reason: 'the ranked view is capped…',
    );

    // …but song #1, which is far outside that view, keeps its exact numbers.
    final first = state.songStats('song-0', PlatformType.netease);
    expect(first, isNotNull, reason: 'a song outside the view must survive');
    expect(first!.playCount, 1);
    expect(first.listenDuration, const Duration(seconds: 10));
    expect(first.key, 'netease_song-0');

    // Totals must reconcile with the per-song detail.
    final detailPlayCount = state.allSongs.fold<int>(
      0,
      (sum, entry) => sum + entry.playCount,
    );
    final detailDuration = state.allSongs.fold<Duration>(
      Duration.zero,
      (sum, entry) => sum + entry.listenDuration,
    );
    expect(detailPlayCount, state.totalPlayCount);
    expect(detailDuration, state.totalListenDuration);
  });

  test('a song missing from the ranked view is still queryable by key', () async {
    final repository = MemoryListeningStatsRepository();
    for (var index = 0; index < 120; index++) {
      final song = _song('song-$index');
      await repository.recordSongStarted(song);
      await repository.addListenedDuration(song, Duration(seconds: 60 + index));
    }

    final state = await repository.load();
    expect(state.topSongs, hasLength(listeningStatsTopSongViewLimit));
    expect(state.topSongs.any((entry) => entry.songId == 'song-0'), isFalse);
    final lookup = await repository.songStats('song-0', PlatformType.netease);
    expect(lookup, isNotNull);
    expect(lookup!.listenDuration, const Duration(seconds: 60));
  });

  test('statistics report covers artists, albums, platforms and hours', () async {
    final clock = DateTime(2026, 5, 30, 9, 15);
    final repository = MemoryListeningStatsRepository(clock: () => clock);
    final morning = Song(
      id: 'morning',
      platform: PlatformType.netease,
      name: '晨间曲',
      artists: const [Artist(id: 'a1', name: '歌手甲')],
      album: const Album(id: 'al1', name: '专辑一'),
    );
    final night = Song(
      id: 'night',
      platform: PlatformType.qq,
      name: '夜曲',
      artists: const [Artist(id: 'a2', name: '歌手乙')],
      album: const Album(id: 'al2', name: '专辑二'),
    );

    await repository.recordSongStarted(morning, at: clock);
    await repository.addListenedDuration(
      morning,
      const Duration(minutes: 5),
      at: clock,
    );
    final evening = DateTime(2026, 5, 30, 22, 5);
    await repository.recordSongStarted(night, at: evening);
    await repository.addListenedDuration(
      night,
      const Duration(minutes: 1),
      at: evening,
    );

    final report = await repository.loadReport();
    expect(report.artists.map((row) => row.label), ['歌手甲', '歌手乙']);
    expect(report.albums.map((row) => row.label), ['专辑一', '专辑二']);
    expect(
      report.platforms.map((row) => row.label),
      ['网易云音乐', 'QQ音乐'],
    );
    expect(report.days.single.day, '2026-05-30');
    expect(report.days.single.playCount, 2);
    expect(report.hours[9].playCount, 1);
    expect(report.hours[22].playCount, 1);
    expect(report.hours[9].listenDuration, const Duration(minutes: 5));
  });

  test('legacy Hive snapshot migrates once and keeps the totals', () async {
    final legacy = ListeningStatsState(
      totalPlayCount: 7,
      totalListenDuration: const Duration(minutes: 21),
      allSongs: [
        ListeningStatsSongEntry(
          songId: 'old-1',
          platform: PlatformType.netease,
          songName: '老歌一',
          artistNames: '老歌手',
          playCount: 5,
          listenDuration: const Duration(minutes: 15),
          lastListenedAt: DateTime(2026, 1, 2),
        ),
        ListeningStatsSongEntry(
          songId: 'old-2',
          platform: PlatformType.qq,
          songName: '老歌二',
          artistNames: '老歌手',
          playCount: 2,
          listenDuration: const Duration(minutes: 6),
          lastListenedAt: DateTime(2026, 1, 3),
        ),
      ],
      topSongs: const [],
      totalSongCount: 2,
    );
    final source = _FakeLegacyStatsSource(legacy);
    final repository = MemoryListeningStatsRepository(
      clock: () => DateTime(2026, 2, 1),
    );

    final migration = ListeningStatsLegacyMigration(
      legacyStore: source,
      target: repository,
    );

    expect(await migration.run(), LegacyStatsMigration.imported);
    final state = await repository.load();
    expect(state.totalPlayCount, 7);
    expect(state.totalListenDuration, const Duration(minutes: 21));
    expect(state.totalSongCount, 2);
    expect(
      state.songStats('old-1', PlatformType.netease)!.playCount,
      5,
    );

    // Second run must be a no-op: otherwise every app start would duplicate the
    // whole history.
    expect(await migration.run(), LegacyStatsMigration.skippedAlreadyMigrated);
    expect((await repository.load()).totalPlayCount, 7);
  });

  test('legacy snapshot import is skipped when the database already has events',
      () async {
    final repository = MemoryListeningStatsRepository();
    await repository.recordSongStarted(_song('fresh'));
    final source = _FakeLegacyStatsSource(
      ListeningStatsState(
        totalPlayCount: 3,
        totalListenDuration: const Duration(minutes: 3),
        allSongs: [
          ListeningStatsSongEntry(
            songId: 'stale',
            platform: PlatformType.netease,
            songName: '不该出现',
            artistNames: '',
            playCount: 3,
            listenDuration: const Duration(minutes: 3),
            lastListenedAt: DateTime(2026, 1, 1),
          ),
        ],
      ),
    );

    final result = await ListeningStatsLegacyMigration(
      legacyStore: source,
      target: repository,
    ).run();

    expect(result, LegacyStatsMigration.skippedAlreadyMigrated);
    final state = await repository.load();
    expect(state.totalSongCount, 1);
    expect(state.songStats('stale', PlatformType.netease), isNull);
  });

  test('clearing statistics drops the detail and the totals together', () async {
    final repository = MemoryListeningStatsRepository();
    final notifier = ListeningStatsNotifier(
      repository,
      importLegacySnapshot: false,
    );
    await notifier.ready;
    final song = _song('clear-me');
    await notifier.recordSongStarted(song);
    await notifier.addListenedDuration(song, const Duration(minutes: 1));

    await notifier.clear();

    expect(notifier.state.totalPlayCount, 0);
    expect(notifier.state.totalListenDuration, Duration.zero);
    expect(notifier.state.allSongs, isEmpty);
    expect(notifier.state.hasData, isFalse);
  });

  test('play events record where they came from', () async {
    final repository = MemoryListeningStatsRepository();
    final notifier = ListeningStatsNotifier(
      repository,
      importLegacySnapshot: false,
    );
    await notifier.ready;

    await notifier.recordSongStarted(_song('sourced'), source: PlayEventSource.seek);
    expect(notifier.state.totalPlayCount, 1);
  });

  test('flushed listened time is handed to the history backfill hook', () async {
    final repository = MemoryListeningStatsRepository();
    final notifier = ListeningStatsNotifier(
      repository,
      importLegacySnapshot: false,
    );
    await notifier.ready;
    final tracker = ListeningStatsTracker(
      notifier: notifier,
      flushInterval: Duration.zero,
    );
    final backfilled = <({String songId, String platform, Duration duration})>[];
    tracker.onListenedDuration = (songId, platform, duration) async {
      backfilled.add((songId: songId, platform: platform, duration: duration));
    };

    final song = _song('history-duration');
    await tracker.handlePlaybackSnapshot(
      previous: ListeningPlaybackSnapshot(
        song: song,
        isPlaying: true,
        position: Duration.zero,
      ),
      next: ListeningPlaybackSnapshot(
        song: song,
        isPlaying: true,
        position: const Duration(seconds: 7),
      ),
    );

    expect(backfilled, hasLength(1));
    expect(backfilled.single.songId, 'history-duration');
    expect(backfilled.single.platform, 'netease');
    expect(backfilled.single.duration, const Duration(seconds: 7));
    expect(notifier.state.totalListenDuration, const Duration(seconds: 7));
  });
}

Song _song(String id) => Song(
  id: id,
  platform: PlatformType.netease,
  name: '歌曲 $id',
  artists: const [Artist(id: 'artist', name: '歌手')],
);

class _FakeLegacyStatsSource implements LegacyStatsSource {
  _FakeLegacyStatsSource(this.state);

  final ListeningStatsState state;

  @override
  Future<bool> hasSnapshot() async => true;

  @override
  Future<ListeningStatsState> read() async => state;
}
