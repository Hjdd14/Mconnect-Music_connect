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
      expect(find.text('重试'), findsOneWidget);
    });
  });
}
