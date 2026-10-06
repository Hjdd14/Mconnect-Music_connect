import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/features/search/data/search_history_store.dart';
import 'package:mconnect/features/search/presentation/providers/aggregated_search_provider.dart';
import 'package:mconnect/features/search/presentation/screens/search_screen.dart';
import 'package:mconnect/features/toplist/presentation/pages/toplists_page.dart';
import 'package:mconnect/features/toplist/presentation/providers/toplists_provider.dart';
import 'package:mconnect/models/platform_type.dart';

import 'qq_fixtures.dart';
import 'support/content_page_fakes.dart';

/// Long-press → shared song-actions menu, on the Wave 3 content pages.
///
/// `showSongActionsMenu` had exactly one call site (the playlist detail page),
/// so the menu was unreachable from 榜单/搜索/专辑/艺人/新歌. These tests drive the
/// full chain on two of them: press a row, pick 下一首播放, and assert the real
/// player queue gained the song right after the current track.
void main() {
  testWidgets('QQ 热歌榜行长按 → 菜单 → 下一首播放改变播放队列', (tester) async {
    final qq = FakeContentPlatform(
      type: PlatformType.qq,
      toplists: toplistsFromCatalogueFixture(kToplistCatalogue),
      rankedSongs: {'26': rankedSongsFromHotCpFixture(kHotToplistCp)},
    );
    registerFake(qq);

    final player = PlayerNotifier(
      audioController: IdleAudioController(),
      platformResolver: (_) => qq,
    );
    await player.playSong(song('current', PlatformType.qq, name: '正在播放'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerProvider.overrideWith((ref) => player),
          toplistsProvider.overrideWith(
            (ref) => ToplistsNotifier(
              supportedTypes: const [PlatformType.qq],
              platformResolver: (_) => qq,
            ),
          ),
        ],
        child: const MaterialApp(
          home: ToplistDetailPage(
            platform: PlatformType.qq,
            toplistId: '26',
            toplistName: '热歌榜',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('我不难过'), findsOneWidget);

    await tester.longPress(find.text('我不难过'));
    await tester.pumpAndSettle();

    expect(find.text('下一首播放'), findsOneWidget);
    expect(find.text('添加到歌单'), findsOneWidget);

    await tester.tap(find.text('下一首播放'));
    await tester.pump();

    expect(player.state.playlist.map((song) => song.name).toList(), [
      '正在播放',
      '我不难过',
    ]);
    expect(
      player.state.playlist[player.state.currentIndex + 1].name,
      '我不难过',
      reason: '「下一首播放」必须插到当前曲目之后，而不是追加到队尾',
    );

    // Drain the success snackbar's timer before the test ends.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('聚合搜索结果长按 → 菜单 → 下一首播放使用所选来源', (tester) async {
    final netease = FakeContentPlatform(
      type: PlatformType.netease,
      searchPages: {
        1: [song('n1', PlatformType.netease, name: '晴天', artist: '周杰伦')],
      },
    );
    final qq = FakeContentPlatform(
      type: PlatformType.qq,
      searchPages: {
        1: [song('q1', PlatformType.qq, name: '晴天', artist: '周杰伦')],
      },
    );
    for (final platform in [netease, qq]) {
      registerFake(platform);
    }
    final byType = {PlatformType.netease: netease, PlatformType.qq: qq};

    final player = PlayerNotifier(
      audioController: IdleAudioController(),
      platformResolver: (_) => qq,
    );
    await player.playSong(song('current', PlatformType.qq, name: '正在播放'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerProvider.overrideWith((ref) => player),
          searchHistoryStoreProvider.overrideWithValue(
            SearchHistoryStore(boxOpener: () async => throw Exception('no hive')),
          ),
          aggregatedSearchProvider.overrideWith(
            (ref) => AggregatedSearchNotifier(
              supportedTypes: const [PlatformType.netease, PlatformType.qq],
              platformResolver: (type) => byType[type]!,
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: SearchScreen())),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SearchScreen)),
    );

    container.read(searchAcrossPlatformsProvider.notifier).state = true;
    container.read(searchQueryProvider.notifier).state = '晴天';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('晴天'), findsOneWidget);
    expect(find.text('2 个来源'), findsOneWidget);

    // 选 QQ 作为来源，长按后菜单里的动作必须作用在这个来源上。
    await tester.tap(find.text('2 个来源'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('QQ音乐').last);
    await tester.pumpAndSettle();
    expect(container.read(aggregatedSearchProvider).playableSongs.single.id, 'q1');

    await tester.longPress(find.text('晴天'));
    await tester.pumpAndSettle();
    expect(find.text('下一首播放'), findsOneWidget);

    await tester.tap(find.text('下一首播放'));
    await tester.pump();

    expect(player.state.playlist.last.id, 'q1');
    expect(player.state.playlist.last.platform, PlatformType.qq);

    await tester.pump(const Duration(seconds: 5));
  });
}
