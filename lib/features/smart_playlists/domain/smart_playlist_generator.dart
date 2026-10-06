import '../../../models/platform_type.dart';
import '../../../models/song.dart';
import '../../stats/domain/listening_stats.dart';
import 'smart_playlist_rule.dart';

class SmartPlaylistSourceContext {
  final List<Song> songs;
  final Set<String> likedSongKeys;
  final Set<String> cachedSongKeys;

  /// Songs that were explicitly downloaded (as opposed to offline-cached).
  final Set<String> downloadedSongKeys;
  final Map<String, ListeningStatsSongEntry> statsBySongKey;
  final DateTime now;

  const SmartPlaylistSourceContext({
    required this.songs,
    this.likedSongKeys = const {},
    this.cachedSongKeys = const {},
    this.downloadedSongKeys = const {},
    this.statsBySongKey = const {},
    required this.now,
  });
}

class SmartPlaylistGenerator {
  const SmartPlaylistGenerator._();

  static String songKey(Song song) => '${song.platform.name}:${song.id}';

  /// Applies [rule] to [context].
  ///
  /// Two layers, on purpose:
  /// * the **platform scope** ([SmartPlaylistRule.platforms]) is always an AND —
  ///   a 网易云 rule must never return a QQ song, whatever
  ///   [SmartPlaylistRule.match] says;
  /// * everything else is a **condition group** whose members combine per
  ///   [SmartPlaylistRule.match] (`all` = AND, `any` = OR). A group with no
  ///   active condition accepts every song in scope, which is what keeps old
  ///   "everything" rules working.
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
      if (rule.localOnly && song.platform != PlatformType.local) continue;

      final stats = context.statsBySongKey[key];
      final conditions = <bool>[];

      if (keyword.isNotEmpty) {
        conditions.add(_matchesKeyword(song, keyword));
      }
      if (rule.likedOnly) {
        conditions.add(context.likedSongKeys.contains(key));
      }
      if (rule.excludeLiked) {
        conditions.add(!context.likedSongKeys.contains(key));
      }
      if (rule.cachedOnly) {
        conditions.add(context.cachedSongKeys.contains(key));
      }
      if (rule.downloadedOnly) {
        conditions.add(context.downloadedSongKeys.contains(key));
      }
      if (rule.artistIds.isNotEmpty) {
        final artistId = _artistIdOf(song);
        conditions.add(artistId != null && rule.artistIds.contains(artistId));
      }
      if (rule.albumIds.isNotEmpty) {
        final albumId = _albumIdOf(song);
        conditions.add(albumId != null && rule.albumIds.contains(albumId));
      }
      if (rule.minDurationMs > 0) {
        conditions.add(song.duration.inMilliseconds >= rule.minDurationMs);
      }
      if (rule.maxDurationMs > 0) {
        conditions.add(song.duration.inMilliseconds <= rule.maxDurationMs);
      }
      if (rule.minPlayCount > 0) {
        conditions.add((stats?.playCount ?? 0) >= rule.minPlayCount);
      }
      if (rule.maxPlayCount > 0) {
        conditions.add((stats?.playCount ?? 0) <= rule.maxPlayCount);
      }
      if (rule.recentlyPlayedDays > 0) {
        final threshold = context.now.subtract(
          Duration(days: rule.recentlyPlayedDays),
        );
        conditions.add(
          stats != null && !stats.lastListenedAt.isBefore(threshold),
        );
      }
      if (rule.notPlayedSinceDays > 0) {
        // Songs that were never played count as "not played", which is the
        // point of this filter: it is the archive/deep-cuts rule.
        final threshold = context.now.subtract(
          Duration(days: rule.notPlayedSinceDays),
        );
        conditions.add(
          stats == null || stats.lastListenedAt.isBefore(threshold),
        );
      }

      if (conditions.isNotEmpty) {
        final accepted = rule.match == SmartPlaylistMatch.any
            ? conditions.any((passed) => passed)
            : conditions.every((passed) => passed);
        if (!accepted) continue;
      }

      filtered.add(song);
    }

    filtered.sort(
      (left, right) => _compare(rule.sortBy, left, right, context),
    );
    return filtered.take(rule.maxSongs).toList();
  }

  static int _compare(
    SmartPlaylistSortOrder order,
    Song left,
    Song right,
    SmartPlaylistSourceContext context,
  ) {
    final leftStats = context.statsBySongKey[songKey(left)];
    final rightStats = context.statsBySongKey[songKey(right)];
    final leftListened = leftStats?.listenDuration ?? Duration.zero;
    final rightListened = rightStats?.listenDuration ?? Duration.zero;
    final leftPlays = leftStats?.playCount ?? 0;
    final rightPlays = rightStats?.playCount ?? 0;
    final leftPlayedAt =
        leftStats?.lastListenedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final rightPlayedAt =
        rightStats?.lastListenedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

    final int primary;
    switch (order) {
      case SmartPlaylistSortOrder.mostListened:
        primary = rightListened.compareTo(leftListened);
      case SmartPlaylistSortOrder.mostPlayed:
        primary = rightPlays.compareTo(leftPlays);
      case SmartPlaylistSortOrder.recentlyPlayed:
        primary = rightPlayedAt.compareTo(leftPlayedAt);
      case SmartPlaylistSortOrder.titleAsc:
        primary = left.name.toLowerCase().compareTo(right.name.toLowerCase());
    }
    if (primary != 0) return primary;

    // Deterministic tie-break: without it two songs with identical statistics
    // come back in whatever order the source list happened to have, so a saved
    // result and a fresh preview could disagree.
    if (order != SmartPlaylistSortOrder.mostListened) {
      final listened = rightListened.compareTo(leftListened);
      if (listened != 0) return listened;
    }
    if (order != SmartPlaylistSortOrder.mostPlayed) {
      final plays = rightPlays.compareTo(leftPlays);
      if (plays != 0) return plays;
    }
    return songKey(left).compareTo(songKey(right));
  }

  static String? _artistIdOf(Song song) {
    final direct = song.artistId;
    if (direct != null && direct.isNotEmpty) return direct;
    if (song.artists.isEmpty) return null;
    final first = song.artists.first.id;
    return first.isEmpty ? null : first;
  }

  static String? _albumIdOf(Song song) {
    final direct = song.albumId;
    if (direct != null && direct.isNotEmpty) return direct;
    final albumId = song.album?.id;
    return (albumId == null || albumId.isEmpty) ? null : albumId;
  }

  static bool _matchesKeyword(Song song, String keyword) {
    return song.name.toLowerCase().contains(keyword) ||
        song.artistNames.toLowerCase().contains(keyword) ||
        (song.album?.name.toLowerCase().contains(keyword) ?? false);
  }
}
