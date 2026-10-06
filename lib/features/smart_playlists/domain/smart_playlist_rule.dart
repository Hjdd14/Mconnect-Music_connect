import 'package:flutter/foundation.dart';

import '../../../models/platform_type.dart';

/// How multiple active filters of a rule combine.
///
/// * [all] — every active filter must pass (the historical behaviour, and the
///   default so existing rules keep meaning the same thing).
/// * [any] — at least one active filter must pass. The **platform scope** is
///   never part of this group: a rule that selects 网易云 must not start
///   returning QQ songs because one other filter matched.
enum SmartPlaylistMatch {
  all('同时满足'),
  any('满足任一');

  final String displayName;
  const SmartPlaylistMatch(this.displayName);

  static SmartPlaylistMatch fromName(String? name) {
    for (final value in SmartPlaylistMatch.values) {
      if (value.name == name) return value;
    }
    return SmartPlaylistMatch.all;
  }
}

/// Ordering of a generated smart playlist.
enum SmartPlaylistSortOrder {
  mostListened('听得最多'),
  mostPlayed('播放最多'),
  recentlyPlayed('最近播放'),
  titleAsc('标题升序');

  final String displayName;
  const SmartPlaylistSortOrder(this.displayName);

  static SmartPlaylistSortOrder fromName(String? name) {
    for (final value in SmartPlaylistSortOrder.values) {
      if (value.name == name) return value;
    }
    return SmartPlaylistSortOrder.mostListened;
  }
}

@immutable
class SmartPlaylistRule {
  final String id;
  final String name;
  final Set<PlatformType> platforms;
  final String keyword;
  final int minPlayCount;
  final int recentlyPlayedDays;
  final bool likedOnly;
  final bool cachedOnly;
  final int maxSongs;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Owning-platform artist ids the songs must belong to.
  final Set<String> artistIds;

  /// Owning-platform album ids the songs must belong to.
  final Set<String> albumIds;

  /// Lower bound of the track duration; 0 means "no lower bound".
  final int minDurationMs;

  /// Upper bound of the track duration; 0 means "no upper bound".
  final int maxDurationMs;

  /// Highest play count still accepted; 0 means "no upper bound". Useful for
  /// "guilty pleasures I rarely play" style playlists.
  final int maxPlayCount;

  /// Only songs **not** played within this many days (never-played songs count
  /// as not played). 0 disables the filter.
  final int notPlayedSinceDays;

  final bool localOnly;
  final bool downloadedOnly;

  /// Excludes liked songs — the counterpart of [likedOnly] for "songs I have not
  /// favourited yet".
  final bool excludeLiked;

  final SmartPlaylistMatch match;
  final SmartPlaylistSortOrder sortBy;

  const SmartPlaylistRule({
    required this.id,
    required this.name,
    this.platforms = const {},
    this.keyword = '',
    this.minPlayCount = 0,
    this.recentlyPlayedDays = 0,
    this.likedOnly = false,
    this.cachedOnly = false,
    this.maxSongs = 100,
    required this.createdAt,
    required this.updatedAt,
    this.artistIds = const {},
    this.albumIds = const {},
    this.minDurationMs = 0,
    this.maxDurationMs = 0,
    this.maxPlayCount = 0,
    this.notPlayedSinceDays = 0,
    this.localOnly = false,
    this.downloadedOnly = false,
    this.excludeLiked = false,
    this.match = SmartPlaylistMatch.all,
    this.sortBy = SmartPlaylistSortOrder.mostListened,
  });

  factory SmartPlaylistRule.create({
    required String name,
    Set<PlatformType> platforms = const {},
    String keyword = '',
    int minPlayCount = 0,
    int recentlyPlayedDays = 0,
    bool likedOnly = false,
    bool cachedOnly = false,
    int maxSongs = 100,
    Set<String> artistIds = const {},
    Set<String> albumIds = const {},
    int minDurationMs = 0,
    int maxDurationMs = 0,
    int maxPlayCount = 0,
    int notPlayedSinceDays = 0,
    bool localOnly = false,
    bool downloadedOnly = false,
    bool excludeLiked = false,
    SmartPlaylistMatch match = SmartPlaylistMatch.all,
    SmartPlaylistSortOrder sortBy = SmartPlaylistSortOrder.mostListened,
  }) {
    final now = DateTime.now();
    final durationRange = _durationRange(minDurationMs, maxDurationMs);
    return SmartPlaylistRule(
      id: 'smart_${now.microsecondsSinceEpoch}',
      name: _normalizedName(name),
      platforms: platforms,
      keyword: keyword.trim(),
      minPlayCount: minPlayCount.clamp(0, 999),
      recentlyPlayedDays: recentlyPlayedDays.clamp(0, 3650),
      likedOnly: likedOnly,
      cachedOnly: cachedOnly,
      maxSongs: maxSongs.clamp(1, 500),
      createdAt: now,
      updatedAt: now,
      artistIds: _cleanIds(artistIds),
      albumIds: _cleanIds(albumIds),
      minDurationMs: durationRange.min,
      maxDurationMs: durationRange.max,
      maxPlayCount: maxPlayCount.clamp(0, 9999),
      notPlayedSinceDays: notPlayedSinceDays.clamp(0, 3650),
      localOnly: localOnly,
      downloadedOnly: downloadedOnly,
      excludeLiked: excludeLiked,
      match: match,
      sortBy: sortBy,
    );
  }

  SmartPlaylistRule copyWith({
    String? name,
    Set<PlatformType>? platforms,
    String? keyword,
    int? minPlayCount,
    int? recentlyPlayedDays,
    bool? likedOnly,
    bool? cachedOnly,
    int? maxSongs,
    DateTime? updatedAt,
    Set<String>? artistIds,
    Set<String>? albumIds,
    int? minDurationMs,
    int? maxDurationMs,
    int? maxPlayCount,
    int? notPlayedSinceDays,
    bool? localOnly,
    bool? downloadedOnly,
    bool? excludeLiked,
    SmartPlaylistMatch? match,
    SmartPlaylistSortOrder? sortBy,
  }) {
    final nextMinDuration = minDurationMs ?? this.minDurationMs;
    final nextMaxDuration = maxDurationMs ?? this.maxDurationMs;
    final durationRange = _durationRange(nextMinDuration, nextMaxDuration);
    return SmartPlaylistRule(
      id: id,
      name: name == null ? this.name : _normalizedName(name),
      platforms: platforms ?? this.platforms,
      keyword: keyword?.trim() ?? this.keyword,
      minPlayCount: (minPlayCount ?? this.minPlayCount).clamp(0, 999),
      recentlyPlayedDays: (recentlyPlayedDays ?? this.recentlyPlayedDays).clamp(
        0,
        3650,
      ),
      likedOnly: likedOnly ?? this.likedOnly,
      cachedOnly: cachedOnly ?? this.cachedOnly,
      maxSongs: (maxSongs ?? this.maxSongs).clamp(1, 500),
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      artistIds: _cleanIds(artistIds ?? this.artistIds),
      albumIds: _cleanIds(albumIds ?? this.albumIds),
      minDurationMs: durationRange.min,
      maxDurationMs: durationRange.max,
      maxPlayCount: (maxPlayCount ?? this.maxPlayCount).clamp(0, 9999),
      notPlayedSinceDays: (notPlayedSinceDays ?? this.notPlayedSinceDays).clamp(
        0,
        3650,
      ),
      localOnly: localOnly ?? this.localOnly,
      downloadedOnly: downloadedOnly ?? this.downloadedOnly,
      excludeLiked: excludeLiked ?? this.excludeLiked,
      match: match ?? this.match,
      sortBy: sortBy ?? this.sortBy,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'platforms': platforms.map((platform) => platform.name).toList(),
      'keyword': keyword,
      'minPlayCount': minPlayCount,
      'recentlyPlayedDays': recentlyPlayedDays,
      'likedOnly': likedOnly,
      'cachedOnly': cachedOnly,
      'maxSongs': maxSongs,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'artistIds': artistIds.toList(),
      'albumIds': albumIds.toList(),
      'minDurationMs': minDurationMs,
      'maxDurationMs': maxDurationMs,
      'maxPlayCount': maxPlayCount,
      'notPlayedSinceDays': notPlayedSinceDays,
      'localOnly': localOnly,
      'downloadedOnly': downloadedOnly,
      'excludeLiked': excludeLiked,
      'match': match.name,
      'sortBy': sortBy.name,
    };
  }

  static SmartPlaylistRule fromJson(dynamic value) {
    if (value is! Map) {
      return SmartPlaylistRule.create(name: '智能歌单');
    }
    final id = value['id']?.toString();
    final createdAt =
        DateTime.tryParse(value['createdAt']?.toString() ?? '') ??
        DateTime.now();
    // A rule written before v1.4.0 has none of the fields below; every one of
    // them must fall back to the behaviour that rule already had.
    return SmartPlaylistRule(
      id: id == null || id.isEmpty
          ? 'smart_${createdAt.microsecondsSinceEpoch}'
          : id,
      name: _normalizedName(value['name']?.toString() ?? '智能歌单'),
      platforms: _platformsFromJson(value['platforms']),
      keyword: value['keyword']?.toString().trim() ?? '',
      minPlayCount: (_intValue(value['minPlayCount']) ?? 0).clamp(0, 999),
      recentlyPlayedDays: (_intValue(value['recentlyPlayedDays']) ?? 0).clamp(
        0,
        3650,
      ),
      likedOnly: value['likedOnly'] == true,
      cachedOnly: value['cachedOnly'] == true,
      maxSongs: (_intValue(value['maxSongs']) ?? 100).clamp(1, 500),
      createdAt: createdAt,
      updatedAt:
          DateTime.tryParse(value['updatedAt']?.toString() ?? '') ?? createdAt,
      artistIds: _idsFromJson(value['artistIds']),
      albumIds: _idsFromJson(value['albumIds']),
      minDurationMs: (_intValue(value['minDurationMs']) ?? 0).clamp(0, 7200000),
      maxDurationMs: (_intValue(value['maxDurationMs']) ?? 0).clamp(0, 7200000),
      maxPlayCount: (_intValue(value['maxPlayCount']) ?? 0).clamp(0, 9999),
      notPlayedSinceDays: (_intValue(value['notPlayedSinceDays']) ?? 0).clamp(
        0,
        3650,
      ),
      localOnly: value['localOnly'] == true,
      downloadedOnly: value['downloadedOnly'] == true,
      excludeLiked: value['excludeLiked'] == true,
      match: SmartPlaylistMatch.fromName(value['match']?.toString()),
      sortBy: SmartPlaylistSortOrder.fromName(value['sortBy']?.toString()),
    );
  }

  static Set<PlatformType> _platformsFromJson(dynamic value) {
    if (value is! List) return const {};
    final platforms = <PlatformType>{};
    for (final item in value) {
      final platform = PlatformType.tryParse(item.toString());
      if (platform != null) platforms.add(platform);
    }
    return platforms;
  }

  static Set<String> _idsFromJson(dynamic value) {
    if (value is! List) return const {};
    return _cleanIds(value.map((item) => item.toString()));
  }

  static Set<String> _cleanIds(Iterable<String> values) {
    return {
      for (final value in values)
        if (value.trim().isNotEmpty) value.trim(),
    };
  }

  /// Keeps a 0/0 duration pair meaning "unbounded", and swaps the bounds rather
  /// than storing an impossible range when only one of them is edited.
  static ({int min, int max}) _durationRange(int min, int max) {
    var low = min.clamp(0, 7200000);
    var high = max.clamp(0, 7200000);
    if (low > 0 && high > 0 && low > high) {
      final swap = low;
      low = high;
      high = swap;
    }
    return (min: low, max: high);
  }

  static int? _intValue(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  static String _normalizedName(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? '智能歌单' : trimmed;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SmartPlaylistRule &&
            id == other.id &&
            name == other.name &&
            setEquals(platforms, other.platforms) &&
            keyword == other.keyword &&
            minPlayCount == other.minPlayCount &&
            recentlyPlayedDays == other.recentlyPlayedDays &&
            likedOnly == other.likedOnly &&
            cachedOnly == other.cachedOnly &&
            maxSongs == other.maxSongs &&
            createdAt == other.createdAt &&
            updatedAt == other.updatedAt &&
            setEquals(artistIds, other.artistIds) &&
            setEquals(albumIds, other.albumIds) &&
            minDurationMs == other.minDurationMs &&
            maxDurationMs == other.maxDurationMs &&
            maxPlayCount == other.maxPlayCount &&
            notPlayedSinceDays == other.notPlayedSinceDays &&
            localOnly == other.localOnly &&
            downloadedOnly == other.downloadedOnly &&
            excludeLiked == other.excludeLiked &&
            match == other.match &&
            sortBy == other.sortBy;
  }

  @override
  int get hashCode => Object.hash(
    Object.hash(
      id,
      name,
      Object.hashAllUnordered(platforms),
      keyword,
      minPlayCount,
      recentlyPlayedDays,
      likedOnly,
      cachedOnly,
      maxSongs,
      createdAt,
      updatedAt,
    ),
    Object.hash(
      Object.hashAllUnordered(artistIds),
      Object.hashAllUnordered(albumIds),
      minDurationMs,
      maxDurationMs,
      maxPlayCount,
      notPlayedSinceDays,
      localOnly,
      downloadedOnly,
      excludeLiked,
      match,
      sortBy,
    ),
  );
}
