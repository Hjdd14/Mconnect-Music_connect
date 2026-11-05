import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/toplist/presentation/widgets/ranked_song_tile.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/models/toplist.dart';

/// 榜单行以前只有名次方块，没有封面；数据层三平台都带封面，所以缺的只是这一行
/// 的画法。这里把「名次在左 + 封面在右 + 缺图落占位」钉死。
void main() {
  Widget wrap(RankedSong ranked, {VoidCallback? onTap}) {
    return ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: RankedSongTile(
            ranked: ranked,
            accent: const Color(0xFFEC4141),
            onTap: onTap ?? () {},
          ),
        ),
      ),
    );
  }

  RankedSong rankedSong(int rank, {String? coverUrl}) => RankedSong(
    rank: rank,
    song: Song(
      id: 'song-$rank',
      platform: PlatformType.netease,
      name: '第 $rank 首',
      artists: const <Artist>[Artist(id: 'a', name: '歌手')],
      duration: const Duration(minutes: 3),
      coverUrl: coverUrl,
    ),
  );

  testWidgets('a chart row shows the rank and the cover side by side', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        rankedSong(3, coverUrl: 'https://example.com/cover.jpg'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    // 名次还在。
    expect(find.text('3'), findsOneWidget);
    // 封面真的被请求了（CachedNetworkImage），而不是走占位分支。测试环境里
    // 所有 HTTP 都返回 400，图片会落到 errorWidget —— 这里断言的是「用了网络图
    // 组件」，不是「图片下载成功」。
    expect(find.byType(CachedNetworkImage), findsOneWidget);

    // 次序：名次在左，封面在右。
    final rankX = tester.getTopLeft(find.text('3')).dx;
    final coverX = tester
        .getTopLeft(find.byKey(const ValueKey('ranked-song-cover')))
        .dx;
    expect(rankX, lessThan(coverX));
  });

  testWidgets('a row without artwork falls back to a placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(rankedSong(7)));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('7'), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.byIcon(Icons.music_note), findsOneWidget);
    // 占位也是固定尺寸，滚动时行不会跳动。
    final size = tester.getSize(
      find.byKey(const ValueKey('ranked-song-cover')),
    );
    expect(size.width, 46);
    expect(size.height, 46);
  });

  testWidgets('tapping a row still plays it', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      wrap(rankedSong(1, coverUrl: 'https://example.com/a.jpg'), onTap: () => taps++),
    );
    await tester.pump();

    await tester.tap(find.text('第 1 首'));
    expect(taps, 1);
  });
}
