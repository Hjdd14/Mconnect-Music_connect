import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/artist/presentation/pages/artist_page.dart';
import 'package:mconnect/models/album.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';

import 'support/content_page_fakes.dart';

void main() {
  Widget wrap(FakeContentPlatform qq) {
    registerFake(qq);
    return ProviderScope(
      child: MaterialApp(
        home: const ArtistPage(
          platform: PlatformType.qq,
          artistId: '003Nz2So3XXYek',
          artistName: '陈奕迅',
        ),
      ),
    );
  }

  testWidgets('艺人页渲染头像/简介/数量/热门歌曲/专辑列表', (tester) async {
    final qq = FakeContentPlatform(
      type: PlatformType.qq,
      artist: const Artist(
        id: '003Nz2So3XXYek',
        name: '陈奕迅',
        briefDesc: '陈奕迅（Eason Chan），1974年7月27日出生于香港。',
        songCount: 1400,
        albumCount: 103,
        // 粉丝数缺失时不能显示 0 或 null。
      ),
      artistTopSongs: [
        song('t1', PlatformType.qq, name: '十年', albumName: '黑白灰'),
        song('t2', PlatformType.qq, name: '红玫瑰', albumName: '认了吧'),
      ],
      artistAlbums: const [
        Album(id: 'a1', name: '不想放手', releaseDate: null),
        Album(id: 'a2', name: '黑白灰'),
      ],
    );

    await tester.pumpWidget(wrap(qq));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('陈奕迅'), findsWidgets);
    expect(find.textContaining('1400 首歌曲'), findsOneWidget);
    expect(find.textContaining('103 张专辑'), findsOneWidget);
    expect(find.textContaining('1974年7月27日'), findsOneWidget);
    expect(find.text('专辑'), findsOneWidget);
    expect(find.text('热门歌曲'), findsOneWidget);
    expect(find.text('十年'), findsOneWidget);
    expect(find.text('红玫瑰'), findsOneWidget);
    expect(find.text('不想放手'), findsOneWidget);
    expect(find.text('黑白灰'), findsWidgets);
    expect(find.text('播放全部'), findsOneWidget);
    expect(find.textContaining('粉丝'), findsNothing, reason: 'fansCount 缺失时不显示');
  });

  testWidgets('专辑区失败不影响热门歌曲，且就地说明原因', (tester) async {
    final qq = FakeContentPlatform(
      type: PlatformType.qq,
      artist: const Artist(id: 'ar1', name: '陈奕迅'),
      artistTopSongs: [song('t1', PlatformType.qq, name: '十年')],
      artistAlbumsError: Exception('album list unavailable'),
    );

    await tester.pumpWidget(wrap(qq));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('十年'), findsOneWidget);
    expect(find.textContaining('album list unavailable'), findsOneWidget);
  });

  testWidgets('艺人信息为空时说明暂无，且这是空态而不是错误态', (tester) async {
    final empty = FakeContentPlatform(type: PlatformType.qq);
    await tester.pumpWidget(wrap(empty));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('暂无艺人信息'), findsOneWidget);

    // Changed by the W0-F three-state migration: this branch used to reuse the
    // *error* widget and offer "重试"; there is nothing for a retry to change on
    // a page that legitimately has no content, so it is now the shared
    // `AsyncStateView.empty` (no retry by contract).
    expect(find.text('重试'), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
  });

  testWidgets('平台不支持艺人页时说明暂不支持且不请求', (tester) async {
    final unsupported = FakeContentPlatform(
      type: PlatformType.qq,
      supportsArtist: false,
    );
    await tester.pumpWidget(wrap(unsupported));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('暂不支持'), findsOneWidget);
    expect(unsupported.artistCalls, isEmpty);
    // The platform throwing `UnsupportedActionException` is a real failure, so
    // it keeps a retry — and that retry is an `ElevatedButton` (contract rule 1).
    expect(find.widgetWithText(ElevatedButton, '重试'), findsOneWidget);
  });
}
