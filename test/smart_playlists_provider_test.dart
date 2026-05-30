import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/smart_playlists/data/smart_playlist_repository.dart';
import 'package:mconnect/features/smart_playlists/presentation/providers/smart_playlists_provider.dart';
import 'package:mconnect/models/platform_type.dart';

void main() {
  test(
    'smart playlists notifier creates updates and deletes local rules',
    () async {
      final repository = MemorySmartPlaylistRepository();
      final notifier = SmartPlaylistsNotifier(repository: repository);
      await notifier.ready;

      final created = await notifier.createRule(
        name: '网易红心',
        platforms: const {PlatformType.netease},
        likedOnly: true,
      );
      await notifier.updateRule(
        created.copyWith(name: '网易红心缓存', cachedOnly: true),
      );
      await notifier.deleteRule(created.id);

      expect(notifier.state.rules, isEmpty);
      expect(await repository.loadRules(), isEmpty);
    },
  );

  test('smart playlists notifier keeps updated rules persisted', () async {
    final repository = MemorySmartPlaylistRepository();
    final notifier = SmartPlaylistsNotifier(repository: repository);
    await notifier.ready;

    final created = await notifier.createRule(name: '最近常听');
    final updated = created.copyWith(minPlayCount: 2, recentlyPlayedDays: 30);
    await notifier.updateRule(updated);

    expect(notifier.state.rules.single.minPlayCount, 2);
    expect(notifier.state.rules.single.recentlyPlayedDays, 30);
    expect((await repository.loadRules()).single, updated);
  });
}
