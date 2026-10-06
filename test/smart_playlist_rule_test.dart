import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/features/smart_playlists/data/smart_playlist_repository.dart';
import 'package:mconnect/features/smart_playlists/domain/smart_playlist_rule.dart';
import 'package:mconnect/models/platform_type.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mconnect_smart_rules_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('smart playlist rule serializes every editable filter', () {
    final rule = SmartPlaylistRule(
      id: 'rule-1',
      name: '最近常听',
      platforms: const {PlatformType.netease, PlatformType.qq},
      keyword: 'live',
      minPlayCount: 3,
      recentlyPlayedDays: 14,
      likedOnly: true,
      cachedOnly: true,
      maxSongs: 40,
      createdAt: DateTime(2026, 5, 30, 10),
      updatedAt: DateTime(2026, 5, 30, 11),
    );

    final restored = SmartPlaylistRule.fromJson(rule.toJson());

    expect(restored, rule);
    expect(restored.platforms, {PlatformType.netease, PlatformType.qq});
    expect(restored.keyword, 'live');
    expect(restored.minPlayCount, 3);
    expect(restored.recentlyPlayedDays, 14);
    expect(restored.likedOnly, isTrue);
    expect(restored.cachedOnly, isTrue);
    expect(restored.maxSongs, 40);
  });

  test('smart playlist repository persists rules locally', () async {
    final repository = HiveSmartPlaylistRepository();
    final rule = SmartPlaylistRule.create(
      name: '缓存红心',
      likedOnly: true,
      cachedOnly: true,
    );

    await repository.saveRules([rule]);

    final restored = await HiveSmartPlaylistRepository().loadRules();
    expect(restored, [rule]);
  });

  test('every extended filter survives a JSON round trip', () {
    final rule = SmartPlaylistRule.create(
      name: '深度筛选',
      platforms: const {PlatformType.netease, PlatformType.kugou},
      artistIds: const {'artist-1', 'artist-2'},
      albumIds: const {'album-9'},
      minDurationMs: const Duration(minutes: 2).inMilliseconds,
      maxDurationMs: const Duration(minutes: 8).inMilliseconds,
      maxPlayCount: 30,
      notPlayedSinceDays: 90,
      localOnly: true,
      downloadedOnly: true,
      excludeLiked: true,
      match: SmartPlaylistMatch.any,
      sortBy: SmartPlaylistSortOrder.recentlyPlayed,
    );

    final restored = SmartPlaylistRule.fromJson(rule.toJson());

    expect(restored, rule);
    expect(restored.artistIds, {'artist-1', 'artist-2'});
    expect(restored.albumIds, {'album-9'});
    expect(restored.minDurationMs, const Duration(minutes: 2).inMilliseconds);
    expect(restored.maxDurationMs, const Duration(minutes: 8).inMilliseconds);
    expect(restored.maxPlayCount, 30);
    expect(restored.notPlayedSinceDays, 90);
    expect(restored.localOnly, isTrue);
    expect(restored.downloadedOnly, isTrue);
    expect(restored.excludeLiked, isTrue);
    expect(restored.match, SmartPlaylistMatch.any);
    expect(restored.sortBy, SmartPlaylistSortOrder.recentlyPlayed);
  });

  test('a rule written by v1.3.2 still reads with the old meaning', () {
    // Exactly the JSON the previous version produced — no new keys at all.
    final legacy = {
      'id': 'rule-legacy',
      'name': '旧规则',
      'platforms': ['netease'],
      'keyword': 'live',
      'minPlayCount': 3,
      'recentlyPlayedDays': 14,
      'likedOnly': true,
      'cachedOnly': false,
      'maxSongs': 40,
      'createdAt': '2026-05-30T10:00:00.000',
      'updatedAt': '2026-05-30T11:00:00.000',
    };

    final restored = SmartPlaylistRule.fromJson(legacy);

    expect(restored.minPlayCount, 3);
    expect(restored.recentlyPlayedDays, 14);
    expect(restored.likedOnly, isTrue);
    expect(restored.artistIds, isEmpty);
    expect(restored.albumIds, isEmpty);
    expect(restored.minDurationMs, 0);
    expect(restored.maxDurationMs, 0);
    expect(restored.maxPlayCount, 0);
    expect(restored.notPlayedSinceDays, 0);
    expect(restored.localOnly, isFalse);
    expect(restored.downloadedOnly, isFalse);
    expect(restored.excludeLiked, isFalse);
    expect(restored.match, SmartPlaylistMatch.all);
    expect(restored.sortBy, SmartPlaylistSortOrder.mostListened);
  });

  test('an unknown platform name is dropped instead of becoming 网易云', () {
    final restored = SmartPlaylistRule.fromJson({
      'id': 'rule-1',
      'name': '规则',
      'platforms': ['netease', 'spotify'],
      'createdAt': '2026-05-30T10:00:00.000',
      'updatedAt': '2026-05-30T10:00:00.000',
    });

    expect(restored.platforms, {PlatformType.netease});
  });

  test('crossed duration bounds are stored ordered', () {
    final rule = SmartPlaylistRule.create(
      name: '区间',
      minDurationMs: const Duration(minutes: 9).inMilliseconds,
      maxDurationMs: const Duration(minutes: 1).inMilliseconds,
    );

    expect(rule.minDurationMs, const Duration(minutes: 1).inMilliseconds);
    expect(rule.maxDurationMs, const Duration(minutes: 9).inMilliseconds);
  });
}
