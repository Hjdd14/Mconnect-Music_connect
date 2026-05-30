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
}
