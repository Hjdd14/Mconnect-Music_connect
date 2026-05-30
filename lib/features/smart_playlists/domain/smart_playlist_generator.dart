import '../../../models/song.dart';
import '../../stats/presentation/providers/listening_stats_provider.dart';
import 'smart_playlist_rule.dart';

class SmartPlaylistSourceContext {
  final List<Song> songs;
  final Set<String> likedSongKeys;
  final Set<String> cachedSongKeys;
  final Map<String, ListeningStatsSongEntry> statsBySongKey;
  final DateTime now;

  const SmartPlaylistSourceContext({
    required this.songs,
    this.likedSongKeys = const {},
    this.cachedSongKeys = const {},
    this.statsBySongKey = const {},
    required this.now,
  });
}

class SmartPlaylistGenerator {
  const SmartPlaylistGenerator._();

  static String songKey(Song song) => '${song.platform.name}:${song.id}';

  static List<Song> generate(
    SmartPlaylistRule rule,
    SmartPlaylistSourceContext context,
  ) {
    final keyword = rule.keyword.trim().toLowerCase();
    final seen = <String>{};
    final filtered = <Song>[];

    for (final song in context.songs) {
      final key = songKey(song);
      if (!seen.add(key)) continue;
      if (rule.platforms.isNotEmpty &&
          !rule.platforms.contains(song.platform)) {
        continue;
      }
      if (keyword.isNotEmpty && !_matchesKeyword(song, keyword)) {
        continue;
      }
      if (rule.likedOnly && !context.likedSongKeys.contains(key)) {
        continue;
      }
      if (rule.cachedOnly && !context.cachedSongKeys.contains(key)) {
        continue;
      }

      final stats = context.statsBySongKey[key];
      if (rule.minPlayCount > 0 &&
          (stats == null || stats.playCount < rule.minPlayCount)) {
        continue;
      }
      if (rule.recentlyPlayedDays > 0) {
        if (stats == null) continue;
        final threshold = context.now.subtract(
          Duration(days: rule.recentlyPlayedDays),
        );
        if (stats.lastListenedAt.isBefore(threshold)) continue;
      }

      filtered.add(song);
    }

    filtered.sort((left, right) {
      final leftStats = context.statsBySongKey[songKey(left)];
      final rightStats = context.statsBySongKey[songKey(right)];
      final listenCompare = (rightStats?.listenDuration ?? Duration.zero)
          .compareTo(leftStats?.listenDuration ?? Duration.zero);
      if (listenCompare != 0) return listenCompare;
      final playCompare = (rightStats?.playCount ?? 0).compareTo(
        leftStats?.playCount ?? 0,
      );
      if (playCompare != 0) return playCompare;
      return (rightStats?.lastListenedAt ??
              DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(
            leftStats?.lastListenedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
          );
    });

    return filtered.take(rule.maxSongs).toList();
  }

  static bool _matchesKeyword(Song song, String keyword) {
    return song.name.toLowerCase().contains(keyword) ||
        song.artistNames.toLowerCase().contains(keyword) ||
        (song.album?.name.toLowerCase().contains(keyword) ?? false);
  }
}
