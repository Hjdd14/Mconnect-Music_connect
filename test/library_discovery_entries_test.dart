import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/discovery/presentation/providers/playlist_recommendations_provider.dart';
import 'package:mconnect/features/discovery/presentation/screens/discovery_screen.dart';
import 'package:mconnect/features/library/presentation/screens/library_screen.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

import 'support/content_page_fakes.dart';

/// Guards where the three content entries live and what shape they take.
///
/// * 榜单中心 / 新歌速递 belong to the 发现 tab, not the library list. Re-adding
///   the library copy makes that list long enough to push 设置 below the fold on
///   a compact screen, for two destinations already one tab away; dropping the
///   discovery entry without the library one would make `/toplists` and
///   `/new-songs` unreachable.
/// * On 发现 they are three equal side-by-side buttons: 每日推荐 / 榜单中心 /
///   新歌速递. 榜单中心 used to appear twice (a full-width card *and* a tile) and
///   艺人 / 专辑 only handed over to the search tab, which is already a bottom
///   destination.
///
/// The library assertion deliberately inspects the ListView's **declared**
/// children rather than the laid-out ones. `ListView` only builds what is near
/// the viewport, so a `find.text(...)` / `findsNothing` pair would pass on the
/// old code too (the removed rows sat low enough to be off-screen) - a test with
/// no teeth. `SliverChildListDelegate.children` holds every child as a widget
/// regardless of scrolling, which is what makes the negative assertion real.
void main() {
  List<String?> libraryEntryTitles(WidgetTester tester) {
    final listView = tester.widget<ListView>(find.byType(ListView));
    // Throws if the page stops using ListView(children: ...): a loud failure is
    // better than silently asserting over an empty list.
    final delegate = listView.childrenDelegate as SliverChildListDelegate;
    return delegate.children
        .whereType<ListTile>()
        .map((tile) => (tile.title as Text?)?.data)
        .toList();
  }

  group('library vs discovery entries', () {
    testWidgets('the library screen no longer lists them', (tester) async {
      // A Scaffold supplies the Material ancestor ListTile requires (a bare
      // MaterialApp throws during build, which would make a red run look right
      // for the wrong reason); the real app gets it from the route shell.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: LibraryScreen())),
      );

      final titles = libraryEntryTitles(tester);

      expect(
        titles,
        isNot(contains('榜单中心')),
        reason: 'the chart hub belongs to the 发现 tab',
      );
      expect(
        titles,
        isNot(contains('新歌速递')),
        reason: 'new releases belong to the 发现 tab',
      );

      // The library's own destinations - including the last one, which proves
      // the whole declaration list was inspected - are untouched.
      expect(
        titles,
        containsAll(<String>[
          '我喜欢的音乐',
          '听歌历史',
          '听歌统计',
          '本地音乐',
          '离线缓存',
          '智能歌单',
          '歌单',
          '导入歌单',
          '下载管理',
          '设置',
        ]),
      );
    });

    testWidgets('the discovery screen shows exactly three side-by-side entries', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // An empty platform list means loadRecommendations() iterates over
            // nothing: the pump touches no network, no database and no platform,
            // while the entries the screen renders itself are unaffected.
            playlistRecommendationsProvider.overrideWith(
              (ref) => PlaylistRecommendationsNotifier(supportedTypes: const []),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: DiscoveryScreen())),
        ),
      );
      await tester.pump();

      // Exactly one of each - this is what pins "no duplicate 榜单中心".
      expect(find.text('每日推荐'), findsOneWidget);
      expect(find.text('榜单中心'), findsOneWidget);
      expect(find.text('新歌速递'), findsOneWidget);

      // The 艺人 / 专辑 hand-off to the search tab was removed.
      expect(find.text('艺人 / 专辑'), findsNothing);

      // ...and they are laid out horizontally, left to right in this order.
      final daily = tester.getCenter(find.text('每日推荐'));
      final charts = tester.getCenter(find.text('榜单中心'));
      final newSongs = tester.getCenter(find.text('新歌速递'));

      expect(daily.dy, closeTo(charts.dy, 1));
      expect(charts.dy, closeTo(newSongs.dy, 1));
      expect(daily.dx, lessThan(charts.dx));
      expect(charts.dx, lessThan(newSongs.dx));
    });
  });

  /// W0-F: `发现` used to render `recState.error ?? '登录后查看更多'` in one
  /// branch, so a platform that had actually thrown looked exactly like "not
  /// signed in" — and offered no way to try again. The two are now separate
  /// states with different affordances.
  group('discovery recommendation states', () {
    Widget wrapWithNotifier(PlaylistRecommendationsNotifier notifier) {
      return ProviderScope(
        overrides: [
          playlistRecommendationsProvider.overrideWith((ref) => notifier),
        ],
        child: const MaterialApp(home: Scaffold(body: DiscoveryScreen())),
      );
    }

    testWidgets('lays out in landscape without a RenderFlex overflow', (
      tester,
    ) async {
      // 真机事故（2026-10-09，横屏）：截图里那条黄黑警示条
      //   BOTTOM OVERFLOWED BY 35 PIXELS
      // App 诊断日志在同一次会话里记录了 13 / 35 / 87 像素三种溢出量级：
      //   23:02:10  13 pixels   23:02:11  35 pixels   23:02:30  87 pixels
      // 本用例把常见横屏尺寸逐一钉住：任何一处溢出都会让 `takeException()` 非空。
      //
      // 发现页是一个**不可滚动**的 Column（标题 + 三张卡片 + 标题行 + Expanded），
      // 横屏时可用高度骤降，固定部分就装不下了。
      for (final size in const <Size>[
        // 实测 MuMu 模拟器（截图那台）：physical 2160x3840，density 960 → 缩放 6.0
        //   portrait  360 x 640
        //   landscape 640 x 360   ← 用户看到溢出的真实逻辑尺寸
        // 高度只有 360，比我第一版猜的 600 少了 40%，所以之前测不出来。
        Size(640, 360),
        Size(360, 640), // 竖屏一并守住
        Size(800, 360), // 更宽但同样矮
        Size(1024, 600), // 平板/桌面横屏
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          wrapWithNotifier(
            PlaylistRecommendationsNotifier(supportedTypes: const []),
          ),
        );
        await tester.pump();

        expect(
          tester.takeException(),
          isNull,
          reason: '$size 下发现页不得溢出（真机横屏量到 35px）',
        );
      }
    });

    testWidgets('a platform failure is an error state with a retry', (
      tester,
    ) async {
      final platform = _ThrowingRecommendationPlatform();

      await tester.pumpWidget(
        wrapWithNotifier(
          PlaylistRecommendationsNotifier(
            supportedTypes: const [PlatformType.qq],
            platformResolver: (_) => platform,
          ),
        ),
      );
      // One pump for the `initState` post-frame callback that starts the load,
      // then settle so its completion is rendered.
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('已登录平台推荐加载失败'), findsOneWidget);
      // Contract rule 1 + 3: a real failure must offer a way out, and that
      // affordance is an `ElevatedButton`.
      expect(find.widgetWithText(ElevatedButton, '重试'), findsOneWidget);
    });

    testWidgets('not being signed in is an empty state with no retry', (
      tester,
    ) async {
      // No supported platforms means every platform is skipped, which is the
      // provider's "loggedInCount == 0" path: an explanation, not a failure.
      await tester.pumpWidget(
        wrapWithNotifier(
          PlaylistRecommendationsNotifier(supportedTypes: const []),
        ),
      );
      await tester.pump();

      expect(find.text('请先登录平台账号'), findsOneWidget);
      // Contract rule 3: an empty state never pretends to be an error, so there
      // is nothing to retry — this is the assertion the old single branch failed.
      expect(find.text('重试'), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
    });
  });
}

/// A logged-in platform whose daily recommendations always fail, so the page has
/// to render a real error rather than an empty list.
class _ThrowingRecommendationPlatform extends FakeContentPlatform {
  _ThrowingRecommendationPlatform()
    : super(type: PlatformType.qq, loggedIn: true);

  @override
  Future<List<Song>> getDailyRecommendations() async {
    throw Exception('recommend down');
  }
}
