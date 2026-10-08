import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/album/presentation/pages/album_page.dart';
import 'package:mconnect/features/album/presentation/providers/album_provider.dart';
import 'package:mconnect/models/album.dart';
import 'package:mconnect/models/platform_type.dart';

import 'support/content_page_fakes.dart';

const _album = Album(
  id: '004VSvF52mQoQp',
  name: '未完成',
  artistName: '孙燕姿',
  artistId: '001pWERg3vFgg8',
  releaseDate: null,
  description: '孙燕姿 未完成 to be continued。',
  songCount: 2,
  company: '华纳唱片',
  genre: 'Pop 流行',
  language: '国语',
);

void main() {
  test('sortAlbumSongs 只在所有曲目都有编号时排序', () {
    final numbered = [
      song('b', PlatformType.qq, trackNumber: 2),
      song('a', PlatformType.qq, trackNumber: 1),
    ];
    expect(sortAlbumSongs(numbered).map((s) => s.id), ['a', 'b']);

    final unnumbered = [
      song('b', PlatformType.qq, trackNumber: 2),
      song('a', PlatformType.qq),
    ];
    // Half-sorted is worse than the platform's own order.
    expect(sortAlbumSongs(unnumbered).map((s) => s.id), ['b', 'a']);
  });

  Widget wrap(FakeContentPlatform qq) {
    registerFake(qq);
    return ProviderScope(
      child: MaterialApp(
        home: const AlbumPage(
          platform: PlatformType.qq,
          albumId: '004VSvF52mQoQp',
          albumName: '未完成',
        ),
      ),
    );
  }

  testWidgets('专辑页渲染封面以外的全部元数据并按 trackNumber 排列曲目', (tester) async {
    final qq = FakeContentPlatform(
      type: PlatformType.qq,
      album: _album.copyWith(releaseDate: DateTime(2003, 1, 10)),
      albumSongs: [
        song(
          's2',
          PlatformType.qq,
          name: '我不难过',
          trackNumber: 2,
          albumName: '未完成',
        ),
        song(
          's1',
          PlatformType.qq,
          name: '神奇',
          trackNumber: 1,
          albumName: '未完成',
        ),
      ],
    );

    await tester.pumpWidget(wrap(qq));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('未完成'), findsWidgets);
    expect(find.text('孙燕姿'), findsOneWidget);
    expect(find.text('2003-01-10'), findsOneWidget);
    expect(find.text('华纳唱片'), findsOneWidget);
    expect(find.text('Pop 流行'), findsOneWidget);
    expect(find.text('国语'), findsOneWidget);
    expect(find.text('2 首'), findsOneWidget);
    expect(find.textContaining('未完成 to be continued'), findsOneWidget);
    expect(find.text('播放全部'), findsOneWidget);
    expect(find.text('整张缓存'), findsOneWidget);

    final titles = tester
        .widgetList<Text>(
          find.descendant(of: find.byType(ListTile), matching: find.byType(Text)),
        )
        .map((text) => text.data)
        .whereType<String>()
        .toList();
    // trackNumber 1 在 trackNumber 2 之前。
    expect(titles.indexOf('神奇'), lessThan(titles.indexOf('我不难过')));
    expect(find.text('神奇'), findsOneWidget);
  });

  testWidgets('平台不支持专辑页时给出「暂不支持」而不是空白', (tester) async {
    final qq = FakeContentPlatform(type: PlatformType.qq, supportsAlbum: false);

    await tester.pumpWidget(wrap(qq));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('暂不支持'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    // Contract rule 1: the retry affordance is an `ElevatedButton`, never a
    // `TextButton` that reads as a link next to a full-page failure.
    expect(find.widgetWithText(ElevatedButton, '重试'), findsOneWidget);
    expect(qq.albumCalls, isEmpty, reason: '不支持时不应发起请求');
  });

  testWidgets('专辑无数据时说明暂无信息，且这是空态而不是错误态', (tester) async {
    final qq = FakeContentPlatform(type: PlatformType.qq);

    await tester.pumpWidget(wrap(qq));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('暂无专辑信息'), findsOneWidget);

    // Changed by the W0-F three-state migration: this branch used to reuse the
    // *error* widget, so an album that simply has no tracks offered a "重试"
    // button that could never help. It now goes through the shared
    // `AsyncStateView.empty`, which has no retry affordance by contract.
    expect(find.text('重试'), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
  });

  testWidgets('加载失败时显示平台错误信息并可重试', (tester) async {
    final qq = FakeContentPlatform(
      type: PlatformType.qq,
      albumError: Exception('boom'),
    );

    await tester.pumpWidget(wrap(qq));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, '重试'), findsOneWidget);
  });
}
