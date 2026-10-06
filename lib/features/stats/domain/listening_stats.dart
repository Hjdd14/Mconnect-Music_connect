import 'package:flutter/foundation.dart';

import '../../../models/platform_type.dart';

/// One song's rolled-up listening statistics.
///
/// This is a **view** over the raw play events, not the storage: it is rebuilt
/// from `PlayEvents` on every load. The previous implementation kept the top 100
/// of these in a Hive snapshot and re-derived the index from that list, so the
/// 101st distinct song silently deleted the statistics of the least-played one
/// while `totalPlayCount`/`totalListenDuration` stayed global — the two numbers
/// could not be reconciled.
@immutable
class ListeningStatsSongEntry {
  final String songId;
  final PlatformType platform;
  final String songName;
  final String artistNames;
  final int playCount;
  final Duration listenDuration;
  final DateTime lastListenedAt;

  const ListeningStatsSongEntry({
    required this.songId,
    required this.platform,
    required this.songName,
    required this.artistNames,
    required this.playCount,
    required this.listenDuration,
    required this.lastListenedAt,
  });

  String get key => '${platform.name}_$songId';

  ListeningStatsSongEntry copyWith({
    String? songName,
    String? artistNames,
    int? playCount,
    Duration? listenDuration,
    DateTime? lastListenedAt,
  }) {
    return ListeningStatsSongEntry(
      songId: songId,
      platform: platform,
      songName: songName ?? this.songName,
      artistNames: artistNames ?? this.artistNames,
      playCount: playCount ?? this.playCount,
      listenDuration: listenDuration ?? this.listenDuration,
      lastListenedAt: lastListenedAt ?? this.lastListenedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'songId': songId,
      'platform': platform.name,
      'songName': songName,
      'artistNames': artistNames,
      'playCount': playCount,
      'listenDurationMs': listenDuration.inMilliseconds,
      'lastListenedAt': lastListenedAt.toIso8601String(),
    };
  }

  static ListeningStatsSongEntry? fromJson(dynamic value) {
    if (value is! Map) return null;
    final songId = value['songId']?.toString() ?? '';
    if (songId.isEmpty) return null;
    final platform = PlatformType.tryParse(value['platform']?.toString()) ??
        PlatformType.netease;
    return ListeningStatsSongEntry(
      songId: songId,
      platform: platform,
      songName: value['songName']?.toString() ?? '',
      artistNames: value['artistNames']?.toString() ?? '',
      playCount: _intValue(value['playCount']) ?? 0,
      listenDuration: Duration(
        milliseconds: _intValue(value['listenDurationMs']) ?? 0,
      ),
      lastListenedAt:
          DateTime.tryParse(value['lastListenedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ListeningStatsSongEntry &&
            songId == other.songId &&
            platform == other.platform &&
            songName == other.songName &&
            artistNames == other.artistNames &&
            playCount == other.playCount &&
            listenDuration == other.listenDuration &&
            lastListenedAt == other.lastListenedAt;
  }

  @override
  int get hashCode => Object.hash(
    songId,
    platform,
    songName,
    artistNames,
    playCount,
    listenDuration,
    lastListenedAt,
  );
}

/// One labelled dimension row (artist / album / platform).
@immutable
class ListeningStatsDimension {
  final String label;
  final int playCount;
  final Duration listenDuration;

  const ListeningStatsDimension({
    required this.label,
    this.playCount = 0,
    this.listenDuration = Duration.zero,
  });
}

/// One day in the daily roll-up series.
@immutable
class ListeningStatsDay {
  final String day; // 'YYYY-MM-DD'
  final int playCount;
  final Duration listenDuration;

  const ListeningStatsDay({
    required this.day,
    this.playCount = 0,
    this.listenDuration = Duration.zero,
  });
}

/// Plays bucketed by local hour of day.
@immutable
class ListeningStatsHourBucket {
  final int hour;
  final int playCount;
  final Duration listenDuration;

  const ListeningStatsHourBucket({
    required this.hour,
    this.playCount = 0,
    this.listenDuration = Duration.zero,
  });
}

/// The multi-dimensional statistics report.
@immutable
class ListeningStatsReport {
  final List<ListeningStatsDimension> artists;
  final List<ListeningStatsDimension> albums;
  final List<ListeningStatsDimension> platforms;
  final List<ListeningStatsDay> days;
  final List<ListeningStatsHourBucket> hours;

  const ListeningStatsReport({
    this.artists = const [],
    this.albums = const [],
    this.platforms = const [],
    this.days = const [],
    this.hours = const [],
  });

  bool get isEmpty =>
      artists.isEmpty &&
      albums.isEmpty &&
      platforms.isEmpty &&
      days.isEmpty &&
      hours.isEmpty;
}

/// How many songs the ranked display view carries.
///
/// This is a *display* limit only. Every aggregate lives in `PlayEvents`, so a
/// song outside the view still keeps its full statistics.
const int listeningStatsTopSongViewLimit = 100;

@immutable
class ListeningStatsState {
  final bool isLoading;
  final String? error;
  final int totalPlayCount;
  final Duration totalListenDuration;

  /// Ranked display view — **not** the storage. Never longer than
  /// [listeningStatsTopSongViewLimit].
  final List<ListeningStatsSongEntry> topSongs;

  /// Every song that has ever been played, ranked. Unbounded by design; this is
  /// what proves the old top-100 truncation is gone.
  final List<ListeningStatsSongEntry> allSongs;

  /// Distinct songs with at least one recorded play.
  final int totalSongCount;

  /// Distinct days with at least one recorded play.
  final int activeDayCount;

  const ListeningStatsState({
    this.isLoading = false,
    this.error,
    this.totalPlayCount = 0,
    this.totalListenDuration = Duration.zero,
    this.topSongs = const [],
    this.allSongs = const [],
    this.totalSongCount = 0,
    this.activeDayCount = 0,
  });

  bool get hasData => totalPlayCount > 0 || allSongs.isNotEmpty;

  /// Exact statistics for one song, or null when it was never played.
  ///
  /// Backed by [allSongs], so a song pushed out of [topSongs] is still found.
  ListeningStatsSongEntry? songStats(String songId, PlatformType platform) {
    final key = '${platform.name}_$songId';
    for (final entry in allSongs) {
      if (entry.key == key) return entry;
    }
    return null;
  }

  ListeningStatsState copyWith({
    bool? isLoading,
    String? Function()? error,
    int? totalPlayCount,
    Duration? totalListenDuration,
    List<ListeningStatsSongEntry>? topSongs,
    List<ListeningStatsSongEntry>? allSongs,
    int? totalSongCount,
    int? activeDayCount,
  }) {
    return ListeningStatsState(
      isLoading: isLoading ?? this.isLoading,
      error: error != null ? error() : this.error,
      totalPlayCount: totalPlayCount ?? this.totalPlayCount,
      totalListenDuration: totalListenDuration ?? this.totalListenDuration,
      topSongs: topSongs ?? this.topSongs,
      allSongs: allSongs ?? this.allSongs,
      totalSongCount: totalSongCount ?? this.totalSongCount,
      activeDayCount: activeDayCount ?? this.activeDayCount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'totalPlayCount': totalPlayCount,
      'totalListenMs': totalListenDuration.inMilliseconds,
      // Serialise the full list: writing only the ranked view is exactly the bug
      // this class was rewritten to remove.
      'songs': allSongs.map((song) => song.toJson()).toList(),
    };
  }

  /// Reads both the legacy `topSongs` key and the current `songs` key, so a
  /// snapshot written by v1.3.2 can still be imported.
  static ListeningStatsState fromJson(dynamic value) {
    if (value is! Map) return const ListeningStatsState();
    final rawSongs = value['songs'] ?? value['topSongs'];
    final songs = rawSongs is List
        ? rawSongs
              .map(ListeningStatsSongEntry.fromJson)
              .whereType<ListeningStatsSongEntry>()
              .toList()
        : <ListeningStatsSongEntry>[];
    songs.sort(compareSongEntries);
    return ListeningStatsState(
      totalPlayCount: _intValue(value['totalPlayCount']) ?? 0,
      totalListenDuration: Duration(
        milliseconds: _intValue(value['totalListenMs']) ?? 0,
      ),
      allSongs: songs,
      topSongs: songs.take(listeningStatsTopSongViewLimit).toList(),
      totalSongCount: songs.length,
    );
  }
}

/// Ranked view ordering: most listened first, then most played, then most recent.
int compareSongEntries(
  ListeningStatsSongEntry left,
  ListeningStatsSongEntry right,
) {
  final durationCompare = right.listenDuration.compareTo(left.listenDuration);
  if (durationCompare != 0) return durationCompare;
  final playCompare = right.playCount.compareTo(left.playCount);
  if (playCompare != 0) return playCompare;
  return right.lastListenedAt.compareTo(left.lastListenedAt);
}

int? _intValue(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}
