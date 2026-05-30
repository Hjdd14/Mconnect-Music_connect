import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../models/song.dart';
import '../../../download/presentation/providers/download_provider.dart';
import '../../../library/presentation/providers/history_provider.dart';
import '../../../library/presentation/providers/likes_provider.dart';
import '../../../stats/presentation/providers/listening_stats_provider.dart';
import '../../domain/smart_playlist_generator.dart';
import '../../domain/smart_playlist_rule.dart';

final smartPlaylistPreviewProvider =
    Provider.family<List<Song>, SmartPlaylistRule>((ref, rule) {
      final likes = ref.watch(likesProvider.select((state) => state.songs));
      final history = ref.watch(
        historyProvider.select((state) => state.entries),
      );
      final stats = ref.watch(
        listeningStatsProvider.select((state) => state.topSongs),
      );
      final downloads = ref.watch(downloadProvider);

      final songs = <Song>[...likes, ...history.map((entry) => entry.song)];
      final likedKeys = likes.map(SmartPlaylistGenerator.songKey).toSet();
      final cachedKeys = downloads.completedOfflineCacheTasks
          .map((task) => SmartPlaylistGenerator.songKey(task.song))
          .toSet();
      final statsByKey = {
        for (final item in stats) '${item.platform.name}:${item.songId}': item,
      };

      return SmartPlaylistGenerator.generate(
        rule,
        SmartPlaylistSourceContext(
          songs: songs,
          likedSongKeys: likedKeys,
          cachedSongKeys: cachedKeys,
          statsBySongKey: statsByKey,
          now: DateTime.now(),
        ),
      );
    });
