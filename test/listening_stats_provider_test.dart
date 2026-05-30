import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/stats/presentation/providers/listening_stats_provider.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

void main() {
  test(
    'listening stats accumulates play count and listened duration',
    () async {
      final repository = MemoryListeningStatsRepository();
      final notifier = ListeningStatsNotifier(repository);
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
      final notifier = ListeningStatsNotifier(repository);
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
}

Song _song(String id) => Song(
  id: id,
  platform: PlatformType.netease,
  name: '歌曲 $id',
  artists: const [Artist(id: 'artist', name: '歌手')],
);
