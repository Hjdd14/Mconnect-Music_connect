import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/network/api_exception.dart';
import 'package:mconnect/features/new_songs/presentation/pages/new_songs_page.dart';
import 'package:mconnect/features/new_songs/presentation/providers/new_songs_provider.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/platform/base/music_platform.dart';

import 'support/content_page_fakes.dart';

void main() {
  Widget wrap(List<FakeContentPlatform> platforms) {
    for (final platform in platforms) {
      registerFake(platform);
    }
    final byType = {for (final p in platforms) p.type: p};
    return ProviderScope(
      overrides: [
        newSongsProvider.overrideWith(
          (ref) => NewSongsNotifier(
            supportedTypes: platforms.map((p) => p.type).toList(),
            platformResolver: (type) => byType[type]!,
          ),
        ),
      ],
      child: const MaterialApp(home: NewSongsPage()),
    );
  }

  testWidgets('地区 chips 覆盖 NewSongRegion 全部六项', (tester) async {
    await tester.pumpWidget(
      wrap([FakeContentPlatform(type: PlatformType.qq)]),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    for (final label in const ['全部', '华语', '欧美', '日本', '韩国', '港台']) {
      expect(find.text(label), findsOneWidget, reason: '缺少地区 $label');
    }
  });

  testWidgets('网易云港台新歌为空时明示该地区不支持，而不是留白', (tester) async {
    final netease = FakeContentPlatform(
      type: PlatformType.netease,
      newSongsError: UnsupportedActionException(
        '网易云音乐',
        details: '新歌速递不提供港台地区（areaId 6/14/60 实测均返回空）',
      ),
    );

    await tester.pumpWidget(wrap([netease]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('港台'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(netease.newSongCalls.last.region, NewSongRegion.hongKongTaiwan);
    expect(find.textContaining('暂不支持'), findsOneWidget);
    expect(find.textContaining('新歌速递不提供港台地区'), findsOneWidget);
  });

  testWidgets('酷狗不支持新歌时说明原因且不发起请求', (tester) async {
    final kugou = FakeContentPlatform(
      type: PlatformType.kugou,
      supportsNewSongsFlag: false,
    );

    await tester.pumpWidget(wrap([kugou]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('酷狗音乐暂不支持新歌速递'), findsOneWidget);
    expect(kugou.newSongCalls, isEmpty);
  });

  testWidgets('QQ 按地区返回新歌并可切换地区', (tester) async {
    final qq = FakeContentPlatform(
      type: PlatformType.qq,
      newSongs: [
        song('n1', PlatformType.qq, name: '自由的你'),
        song('n2', PlatformType.qq, name: '蜚蜚'),
      ],
    );

    await tester.pumpWidget(wrap([qq]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('自由的你'), findsOneWidget);
    expect(find.text('蜚蜚'), findsOneWidget);
    expect(qq.newSongCalls.last.region, NewSongRegion.all);

    await tester.tap(find.text('韩国'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(qq.newSongCalls.last.region, NewSongRegion.korean);
  });

  testWidgets('全部地区没有新歌时说明暂无数据', (tester) async {
    final qq = FakeContentPlatform(type: PlatformType.qq);

    await tester.pumpWidget(wrap([qq]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('暂无新歌数据'), findsOneWidget);
  });

  testWidgets('平台请求失败时显示错误与重试', (tester) async {
    final qq = FakeContentPlatform(
      type: PlatformType.qq,
      newSongsError: NetworkException(),
    );

    await tester.pumpWidget(wrap([qq]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('网络连接失败，请检查网络后重试'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });
}
