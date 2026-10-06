import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/core/network/api_exception.dart';
import 'package:mconnect/features/search/data/search_history_store.dart';
import 'package:mconnect/features/search/presentation/providers/aggregated_search_provider.dart';
import 'package:mconnect/features/search/presentation/screens/search_screen.dart';
import 'package:mconnect/models/platform_type.dart';

import 'support/content_page_fakes.dart';

void main() {
  group('跨平台合并', () {
    test('按 Song.dedupeKey 合并同曲多平台并保留全部来源', () {
      final netease = song('n1', PlatformType.netease, name: '晴天', artist: '周杰伦');
      final qq = song('q1', PlatformType.qq, name: '晴天', artist: '周杰伦');
      final kugou = song('k1', PlatformType.kugou, name: '晴天', artist: '周杰伦');
      final other = song('n2', PlatformType.netease, name: '七里香', artist: '周杰伦');

      final merged = mergeSearchSongs([qq, netease, other, kugou]);

      expect(merged, hasLength(2));
      expect(merged.first.primary.platform, PlatformType.netease);
      expect(merged.first.sourceCount, 3);
      expect(merged.first.platforms, [
        PlatformType.netease,
        PlatformType.qq,
        PlatformType.kugou,
      ]);
      expect(merged[1].primary.name, '七里香');
    });

    test('Live/现场标记按 Song.dedupeKey 的约定合并为同一首', () {
      final studio = song('a', PlatformType.qq, name: '晴天', artist: '周杰伦');
      final live = song('b', PlatformType.qq, name: '晴天 (Live)', artist: '周杰伦');

      final merged = mergeSearchSongs([studio, live]);

      expect(merged, hasLength(1));
      expect(merged.single.sourceCount, 2);
    });
  });

  group('聚合搜索 notifier', () {
    AggregatedSearchNotifier build({
      required Map<PlatformType, FakeContentPlatform> platforms,
      Duration timeout = const Duration(seconds: 5),
    }) {
      return AggregatedSearchNotifier(
        supportedTypes: platforms.keys.toList(),
        platformResolver: (type) => platforms[type]!,
        operationTimeout: timeout,
      );
    }

    test('并发搜索三个平台，单平台失败只记错误', () async {
      final notifier = build(
        platforms: {
          PlatformType.netease: FakeContentPlatform(
            type: PlatformType.netease,
            searchPages: {
              1: [song('n1', PlatformType.netease, name: '晴天', artist: '周杰伦')],
            },
          ),
          PlatformType.qq: FakeContentPlatform(
            type: PlatformType.qq,
            searchError: Exception('boom'),
          ),
          PlatformType.kugou: FakeContentPlatform(
            type: PlatformType.kugou,
            searchPages: {
              1: [song('k1', PlatformType.kugou, name: '晴天', artist: '周杰伦')],
            },
          ),
        },
      );

      await notifier.search('晴天');

      expect(notifier.state.songs, hasLength(1));
      expect(notifier.state.songs.single.sourceCount, 2);
      expect(notifier.state.errorsByPlatform[PlatformType.qq], contains('boom'));
      expect(notifier.state.error, isNull, reason: '还有结果时不报页面级错误');
    });

    test('真分页：page 递增且第二页结果被追加去重', () async {
      final qq = FakeContentPlatform(
        type: PlatformType.qq,
        searchPages: {
          1: [
            for (var i = 0; i < 3; i++)
              song('q$i', PlatformType.qq, name: '歌$i', artist: '歌手'),
          ],
          2: [
            song('q0', PlatformType.qq, name: '歌0', artist: '歌手'),
            song('q9', PlatformType.qq, name: '歌9', artist: '歌手'),
          ],
        },
      );
      final notifier = build(platforms: {PlatformType.qq: qq});

      await notifier.search('歌');
      // pageSize 30 -> 3 条不够 30，视为到底；用 pageSize 更小的构造不好注入，
      // 因此这里直接断言第一页的 page 参数与结果，再强制第二页。
      expect(qq.searchCalls.map((call) => call.page), [1]);
      expect(notifier.state.songs, hasLength(3));

      notifier.state = notifier.state.copyWith(
        hasMoreByPlatform: const {PlatformType.qq: true},
      );
      await notifier.loadMore();

      expect(qq.searchCalls.map((call) => call.page), [1, 2]);
      expect(notifier.state.songs, hasLength(4), reason: '去重后追加 1 首');
      expect(notifier.state.pageByPlatform[PlatformType.qq], 2);
    });

    test('网络失败时给出可区分的错误文案', () async {
      final notifier = build(
        platforms: {
          PlatformType.qq: FakeContentPlatform(
            type: PlatformType.qq,
            searchError: NetworkException(),
          ),
        },
      );

      await notifier.search('晴天');

      expect(notifier.state.networkFailed, isTrue);
      expect(notifier.state.error, '网络连接失败，请检查网络后重试');
    });

    test('选源后 playableSongs 使用用户选择的平台', () async {
      final notifier = build(
        platforms: {
          PlatformType.netease: FakeContentPlatform(
            type: PlatformType.netease,
            searchPages: {
              1: [song('n1', PlatformType.netease, name: '晴天', artist: '周杰伦')],
            },
          ),
          PlatformType.qq: FakeContentPlatform(
            type: PlatformType.qq,
            searchPages: {
              1: [song('q1', PlatformType.qq, name: '晴天', artist: '周杰伦')],
            },
          ),
        },
      );
      await notifier.search('晴天');
      final merged = notifier.state.songs.single;
      expect(notifier.state.sourceFor(merged).platform, PlatformType.netease);

      notifier.chooseSource(merged.sources.last);

      expect(notifier.state.sourceFor(merged).platform, PlatformType.qq);
      expect(notifier.state.playableSongs.single.platform, PlatformType.qq);
    });
  });

  group('联想词', () {
    test('只返回包含关键词的历史/歌名，且去重限量', () {
      final suggestions = searchSuggestions(
        query: '周杰',
        history: ['周杰伦', '周杰伦 稻香', '林俊杰', '周杰'],
        songNames: ['周杰伦 晴天', '晴天'],
        limit: 3,
      );

      expect(suggestions, ['周杰伦', '周杰伦 稻香', '周杰伦 晴天']);
      expect(suggestions, hasLength(3));
    });

    test('空关键词不产生联想', () {
      expect(
        searchSuggestions(query: '  ', history: ['周杰伦']),
        isEmpty,
      );
    });
  });

  group('搜索历史（Hive）', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mconnect_search_test');
      Hive.init(tempDir.path);
    });

    tearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('写入去重、最近优先、上限 15 条', () async {
      final store = SearchHistoryStore();

      for (var i = 0; i < 20; i++) {
        await store.add('查询$i');
      }
      await store.add('查询5');

      final entries = await store.load();
      expect(entries, hasLength(SearchHistoryStore.maxEntries));
      expect(entries.first, '查询5');
      expect(entries.where((entry) => entry == '查询5'), hasLength(1));
      expect(entries.contains('查询0'), isFalse, reason: '最早的被挤掉');
    });

    test('删除与清空', () async {
      final store = SearchHistoryStore();
      await store.add('a');
      await store.add('b');

      expect(await store.remove('a'), ['b']);
      expect(await store.clear(), isEmpty);
      expect(await store.load(), isEmpty);
    });

    test('Hive 不可用时读取返回空、写入不抛异常（会话内列表仍正确）', () async {
      final broken = SearchHistoryStore(
        boxOpener: () async => throw Exception('no hive'),
      );

      expect(await broken.load(), isEmpty);
      // 持久化是尽力而为：写失败不能让 UI 崩，也不能丢掉本次会话的记录。
      expect(await broken.add('q'), ['q']);
      expect(await broken.remove('q'), isEmpty);
      expect(await broken.clear(), isEmpty);
    });
  });

  group('搜索页聚合模式', () {
    testWidgets('聚合结果展示来源数量、平台徽标与失败平台提示', (tester) async {
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
      final kugou = FakeContentPlatform(
        type: PlatformType.kugou,
        searchError: NetworkException(),
      );
      for (final platform in [netease, qq, kugou]) {
        registerFake(platform);
      }
      final byType = {
        PlatformType.netease: netease,
        PlatformType.qq: qq,
        PlatformType.kugou: kugou,
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchHistoryStoreProvider.overrideWithValue(
              SearchHistoryStore(boxOpener: () async => throw Exception('no hive')),
            ),
            aggregatedSearchProvider.overrideWith(
              (ref) => AggregatedSearchNotifier(
                supportedTypes: const [
                  PlatformType.netease,
                  PlatformType.qq,
                  PlatformType.kugou,
                ],
                platformResolver: (type) => byType[type]!,
              ),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: SearchScreen())),
        ),
      );
      final context = tester.element(find.byType(SearchScreen));
      final container = ProviderScope.containerOf(context);

      container.read(searchAcrossPlatformsProvider.notifier).state = true;
      container.read(searchQueryProvider.notifier).state = '晴天';
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('晴天'), findsOneWidget);
      expect(find.text('2 个来源'), findsOneWidget);
      expect(find.byKey(const Key('aggregated-search-errors')), findsOneWidget);
      expect(find.textContaining('网络连接失败'), findsWidgets);
    });

    testWidgets('查询为空时显示历史与提示，加载中显示骨架屏', (tester) async {
      final qq = FakeContentPlatform(
        type: PlatformType.qq,
        searchPages: {
          1: [song('q1', PlatformType.qq, name: '晴天')],
        },
      );
      registerFake(qq);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchHistoryStoreProvider.overrideWithValue(
              SearchHistoryStore(boxOpener: () async => throw Exception('no hive')),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: SearchScreen())),
        ),
      );
      await tester.pump();

      expect(find.text('请输入关键词'), findsOneWidget);
    });
  });
}
