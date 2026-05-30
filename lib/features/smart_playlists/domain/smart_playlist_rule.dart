import 'package:flutter/foundation.dart';

import '../../../models/platform_type.dart';

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
  }) {
    final now = DateTime.now();
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
  }) {
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
    );
  }

  static Set<PlatformType> _platformsFromJson(dynamic value) {
    if (value is! List) return const {};
    final platforms = <PlatformType>{};
    for (final item in value) {
      final name = item.toString();
      for (final platform in PlatformType.values) {
        if (platform.name == name) {
          platforms.add(platform);
          break;
        }
      }
    }
    return platforms;
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
            updatedAt == other.updatedAt;
  }

  @override
  int get hashCode => Object.hash(
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
  );
}
