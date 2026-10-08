import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/toplist/presentation/pages/toplists_page.dart';
import 'package:mconnect/features/toplist/presentation/providers/toplists_provider.dart';
import 'package:mconnect/features/toplist/presentation/widgets/ranked_song_tile.dart';
import 'package:mconnect/models/platform_type.dart';

import 'qq_fixtures.dart';
import 'support/content_page_fakes.dart';

/// QQ 热歌榜专属界面（用户点名要的页面）。
///
/// Fixtures are the **real** response shapes captured from the live endpoints:
/// `kToplistCatalogue` (GetAll) for the header and `kHotToplistCp`
/// (fcg_v8_toplist_cp, `topid=26`) for the 300-track chart with its movement.
void main() {
  Widget wrap({
    required FakeContentPlatform qq,
    String toplistId = '26',
    String? toplistName,
  }) {
    registerFake(qq);
    return ProviderScope(
      overrides: [
        toplistsProvider.overrideWith(
          (ref) => ToplistsNotifier(
            supportedTypes: const [PlatformType.qq],
            platformResolver: (_) => qq,
          ),
        ),
      ],
      child: MaterialApp(
        home: ToplistDetailPage(
          platform: PlatformType.qq,
          toplistId: toplistId,
          toplistName: toplistName,
        ),
      ),
    );
  }

  testWidgets('QQ 热歌榜用真实响应渲染：头部信息 + 名次 + 涨跌箭头 + 300 首请求', (tester) async {
    final qq = FakeContentPlatform(
      type: PlatformType.qq,
      toplists: toplistsFromCatalogueFixture(kToplistCatalogue),
      rankedSongs: {'26': rankedSongsFromHotCpFixture(kHotToplistCp)},
    );

    await tester.pumpWidget(wrap(qq: qq));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 头部来自 GetAll 的 topId=26 行（真实字段 title/updateTips/period/groupName/intro）。
    expect(find.text('热歌榜'), findsWidgets);
    expect(find.text('3 首'), findsOneWidget);
    expect(find.text('2026-10-06'), findsOneWidget);
    expect(find.text('巅峰榜'), findsOneWidget);
    expect(find.textContaining('榜单定义'), findsOneWidget);

    // 歌曲来自 legacy toplist_cp：data 包裹层里的 songmid/songname/singer/albumname。
    expect(find.text('我不难过'), findsOneWidget);
    expect(find.text('Proof'), findsOneWidget);
    expect(find.text('神奇'), findsOneWidget);
    expect(find.textContaining('孙燕姿'), findsWidgets);

    // 涨跌：rank2 是 old_count(5)-cur_count(2) = 上升 3；rank1/rank3 持平。
    expect(find.byIcon(Icons.arrow_drop_up), findsOneWidget);
    expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
    expect(find.text('—'), findsNWidgets(2));

    // 整榜播放/缓存入口 + 300 首请求（数据层内部翻 6 页）。
    expect(find.text('播放全部'), findsOneWidget);
    expect(find.text('整榜缓存'), findsOneWidget);
    expect(qq.rankedSongCalls, hasLength(1));
    expect(qq.rankedSongCalls.single.toplistId, '26');
    expect(qq.rankedSongCalls.single.num, 300);

    // 列表行数 = 真实 fixture 的 songlist 条数。
    expect(find.byType(RankedSongTile), findsNWidgets(3));
  });

  testWidgets('上升/下降/新上榜/增长率四种标记都能渲染', (tester) async {
    final qq = FakeContentPlatform(
      type: PlatformType.qq,
      rankedSongs: {
        '58': [
          ranked(1, song('a', PlatformType.qq), change: 0),
          ranked(2, song('b', PlatformType.qq), change: 4),
          ranked(3, song('c', PlatformType.qq), change: -2),
          ranked(5, song('d', PlatformType.qq), isNew: true),
          ranked(6, song('e', PlatformType.qq), rankValue: '11%'),
        ],
      },
    );

    await tester.pumpWidget(wrap(qq: qq, toplistId: '58', toplistName: '说唱榜'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byIcon(Icons.arrow_drop_up), findsOneWidget);
    expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
    expect(find.text('新'), findsOneWidget);
    expect(find.text('11%'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('说唱榜'), findsWidgets);

    // 箭头方向来自 rankChange 的正负（QQ: old_count - cur_count）。
    final badges = tester
        .widgetList<RankMovementBadge>(find.byType(RankMovementBadge))
        .toList();
    expect(badges.map((badge) => badge.rankChange), [0, 4, -2, null, null]);
    // `null` (platform did not report movement) is not the same as `false`.
    expect(badges.map((badge) => badge.isNew), [null, null, null, true, null]);
  });

  testWidgets('空榜单给出说明，且空态不提供重试（空态不是失败）', (tester) async {
    final empty = FakeContentPlatform(type: PlatformType.qq);
    await tester.pumpWidget(wrap(qq: empty));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('该榜单暂无歌曲'), findsOneWidget);
    // 契约变更（W0-E）：空态走 `AsyncStateView.empty`，按契约（rule 3）空态没有
    // 重试按钮 —— 重试属于「加载失败」。刷新入口仍然是 AppBar 的刷新按钮与
    // 下拉刷新，所以空态并非死胡同。
    expect(find.text('重试'), findsNothing);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });

  testWidgets('加载失败给出错误信息与重试', (tester) async {
    final failing = FakeContentPlatform(
      type: PlatformType.qq,
      rankedSongsError: Exception('boom'),
    );
    await tester.pumpWidget(wrap(qq: failing));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });
}
