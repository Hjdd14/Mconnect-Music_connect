import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mconnect/core/database/app_database.dart';
import 'package:mconnect/features/toplist/data/toplists_cache_store.dart';
import 'package:mconnect/features/toplist/presentation/pages/toplists_page.dart';
import 'package:mconnect/features/toplist/presentation/providers/toplists_provider.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/toplist.dart';

import 'qq_fixtures.dart';
import 'support/content_page_fakes.dart';

/// A platform whose chart catalogue never answers.
///
/// The loading state is otherwise untestable here: [FakeContentPlatform]
/// resolves in a microtask, so by the second pump the page has already left
/// `isLoading`.
///
/// **[gate] must be completed before the test ends.** `ToplistsNotifier` wraps
/// the call in `.timeout(operationTimeout)` (15 s by default —
/// `toplists_provider.dart:197`), and a still-pending `Timer` trips
/// `flutter_test`'s `!timersPending` invariant once the tree is disposed.
/// Completing the gate lets that future finish normally, which is what cancels
/// the timeout timer.
class _PendingToplistsPlatform extends FakeContentPlatform {
  _PendingToplistsPlatform() : super(type: PlatformType.qq);

  final Completer<List<Toplist>> gate = Completer<List<Toplist>>();

  @override
  Future<List<Toplist>> getToplists() => gate.future;
}

void main() {
  group('榜单中心 provider', () {
    test('QQ 热歌榜(id 26)从真实 GetAll 目录中解析出来', () async {
      final qq = registerFake(
        FakeContentPlatform(
          type: PlatformType.qq,
          toplists: toplistsFromCatalogueFixture(kToplistCatalogue),
        ),
      );
      final notifier = ToplistsNotifier(
        supportedTypes: const [PlatformType.qq],
        platformResolver: (_) => qq,
      );

      await notifier.load();

      final hot = notifier.state.qqHotToplist;
      expect(hot, isNotNull, reason: '热歌榜必须来自 topId=26 的目录行');
      expect(hot!.id, '26');
      expect(hot.name, '热歌榜');
      expect(hot.songCount, 300);
      expect(hot.updateFrequency, '7首歌新上榜');
      expect(hot.groupName, '巅峰榜');
      expect(notifier.state.toplistsForPlatform(PlatformType.qq), hasLength(3));
    });

    test('单个平台失败不再让它从页面消失：错误进 errorsByPlatform', () async {
      final netease = FakeContentPlatform(
        type: PlatformType.netease,
        toplists: const [Toplist(id: '19723756', name: '云音乐飙升榜')],
      );
      final qq = FakeContentPlatform(
        type: PlatformType.qq,
        toplistsError: Exception('boom'),
      );
      final notifier = ToplistsNotifier(
        supportedTypes: const [PlatformType.netease, PlatformType.qq],
        platformResolver: (platform) =>
            platform == PlatformType.qq ? qq : netease,
      );

      await notifier.load();

      // 网易云照常展示，QQ 带上错误信息 —— 旧 rankingsProvider 会把 QQ 整个丢掉。
      expect(
        notifier.state.toplistsForPlatform(PlatformType.netease),
        hasLength(1),
      );
      expect(notifier.state.errorForPlatform(PlatformType.qq), isNotNull);
      expect(notifier.state.errorForPlatform(PlatformType.qq), contains('boom'));
    });

    test('离线时先发布缓存并标记为离线', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final store = ToplistsCacheStore(database: db);
      await store.saveForPlatform(
        PlatformType.qq,
        toplistsFromCatalogueFixture(kToplistCatalogue),
        fetchedAt: DateTime(2026, 10, 6),
      );

      final offlineQq = FakeContentPlatform(
        type: PlatformType.qq,
        toplistsError: Exception('offline'),
      );
      final notifier = ToplistsNotifier(
        supportedTypes: const [PlatformType.qq],
        platformResolver: (_) => offlineQq,
        cache: store,
      );

      await notifier.load();

      expect(notifier.state.toplistsForPlatform(PlatformType.qq), hasLength(3));
      expect(notifier.state.isOffline(PlatformType.qq), isTrue);
      expect(notifier.state.errorForPlatform(PlatformType.qq), isNotNull);
    });
  });

  group('榜单中心页面', () {
    testWidgets('置顶卡片进入 QQ 热歌榜真实路由 /toplist/qq/26', (tester) async {
      final qq = registerFake(
        FakeContentPlatform(
          type: PlatformType.qq,
          toplists: toplistsFromCatalogueFixture(kToplistCatalogue),
        ),
      );
      final router = GoRouter(
        initialLocation: '/toplists',
        routes: [
          GoRoute(
            path: '/toplists',
            builder: (context, state) => const ToplistsPage(),
          ),
          GoRoute(
            path: '/toplist/:platform/:id',
            builder: (context, state) => Scaffold(
              body: Text(
                'detail-${state.pathParameters['platform']}'
                '-${state.pathParameters['id']}',
              ),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            toplistsProvider.overrideWith(
              (ref) => ToplistsNotifier(
                supportedTypes: const [PlatformType.qq],
                platformResolver: (_) => qq,
              ),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('榜单中心'), findsOneWidget);
      expect(find.text('置顶'), findsOneWidget);
      expect(find.text('进入 300 首热歌榜'), findsOneWidget);

      await tester.tap(find.text('进入 300 首热歌榜'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('detail-qq-26'), findsOneWidget);
    });

    testWidgets('目录为空时置顶入口仍在（离线也能进热歌榜）', (tester) async {
      final qq = registerFake(FakeContentPlatform(type: PlatformType.qq));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            toplistsProvider.overrideWith(
              (ref) => ToplistsNotifier(
                supportedTypes: const [PlatformType.qq],
                platformResolver: (_) => qq,
              ),
            ),
          ],
          child: const MaterialApp(home: ToplistsPage()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('置顶'), findsOneWidget);
      expect(find.textContaining('热歌榜'), findsWidgets);
    });

    testWidgets('加载中显示共享骨架屏（sliver 内），没有转圈', (tester) async {
      final qq = _PendingToplistsPlatform();
      registerFake(qq);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            toplistsProvider.overrideWith(
              (ref) => ToplistsNotifier(
                supportedTypes: const [PlatformType.qq],
                platformResolver: (_) => qq,
              ),
            ),
          ],
          child: const MaterialApp(home: ToplistsPage()),
        ),
      );
      // `pump` only — the skeleton's `Shimmer` is an infinite animation, so
      // `pumpAndSettle` would time out.
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('async-skeleton-list')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // 置顶卡片必须在加载态也可见：热歌榜入口不能因为目录还没回来而消失。
      expect(find.text('置顶'), findsOneWidget);

      // 收尾：让 getToplists() 正常返回。这一步是必需的，不是清理仪式的装饰：
      // `_loadPlatform` 的 `.timeout()` 会留下一个 pending Timer，测试结束时
      // `!timersPending` 会直接失败（本用例第一次跑就是这么失败的）。
      // 不能用 pumpAndSettle —— 骨架屏的 Shimmer 是无限动画，settle 必超时。
      qq.gate.complete(const <Toplist>[]);
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const Key('async-skeleton-list')),
        findsNothing,
        reason: '加载结束后骨架屏必须消失（Shimmer 的动画也随之停止）',
      );
    });

    testWidgets('平台失败时页面显示错误行与重试按钮', (tester) async {
      final qq = registerFake(
        FakeContentPlatform(
          type: PlatformType.qq,
          toplistsError: Exception('网络连接失败'),
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            toplistsProvider.overrideWith(
              (ref) => ToplistsNotifier(
                supportedTypes: const [PlatformType.qq],
                platformResolver: (_) => qq,
              ),
            ),
          ],
          child: const MaterialApp(home: ToplistsPage()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('QQ音乐榜单加载失败'), findsOneWidget);
      // 契约变更（W0-E）：平台错误行里的重试控件从 `TextButton` 换成
      // `ElevatedButton`（`AsyncStateView` 规则 1：重试永远是 ElevatedButton）。
      // 文案不变，所以下面这条断言仍然只锁文本；上面这条锁控件类型。
      expect(
        find.widgetWithText(ElevatedButton, '重试'),
        findsOneWidget,
        reason: '重试必须是 ElevatedButton（不再接受 TextButton）',
      );
      expect(find.widgetWithText(TextButton, '重试'), findsNothing);
      expect(find.text('重试'), findsOneWidget);
    });
  });
}
