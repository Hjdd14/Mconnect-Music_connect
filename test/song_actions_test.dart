import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/share/share_links.dart';
import 'package:mconnect/core/share/song_actions.dart';
import 'package:mconnect/core/widgets/song_actions_sheet.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

const _song = Song(
  id: '1974443814',
  platform: PlatformType.netease,
  name: '夜曲',
  artists: [Artist(id: 'a1', name: '周杰伦')],
);

/// Records what the dispatcher asked for, and can be made to fail.
class _FakeDeps {
  _FakeDeps();

  final List<String> calls = [];
  Object? throwOn;
  bool playlistAdded = true;
  bool likeResult = true;
  AudioLevel level = AudioLevel.lossless;
  String? copiedText;
  Song? sharedSong;

  SongActionDeps get deps => SongActionDeps(
    playNext: (song) async {
      calls.add('playNext');
      _maybeThrow();
      return '已加入播放队列：${song.name}';
    },
    pickPlaylist: (song) async {
      calls.add('pickPlaylist');
      _maybeThrow();
      return playlistAdded;
    },
    download: (song) async {
      calls.add('download');
      _maybeThrow();
      return level;
    },
    toggleLike: (song) async {
      calls.add('toggleLike');
      _maybeThrow();
      return likeResult;
    },
    copyText: (text) async {
      calls.add('copyText');
      _maybeThrow();
      copiedText = text;
    },
    shareText: (song) async {
      calls.add('shareText');
      _maybeThrow();
      sharedSong = song;
    },
  );

  void _maybeThrow() {
    final error = throwOn;
    if (error != null) throw error;
  }
}

void main() {
  group('长按菜单动作分发', () {
    test('playNext 走「下一首播放」并把结果交给调用方', () async {
      final fake = _FakeDeps();

      final result = await performSongAction(
        action: SongAction.playNext,
        song: _song,
        deps: fake.deps,
      );

      expect(fake.calls, ['playNext']);
      expect(result.success, isTrue);
      expect(result.message, contains('夜曲'));
    });

    test('download 提示里带上实际排队音质', () async {
      final fake = _FakeDeps()..level = AudioLevel.medium;

      final result = await performSongAction(
        action: SongAction.download,
        song: _song,
        deps: fake.deps,
      );

      expect(fake.calls, ['download']);
      expect(result.message, contains('已开始下载：夜曲'));
      expect(
        result.message,
        contains(AudioLevel.medium.displayNameFor(PlatformType.netease)),
      );
    });

    test('addToPlaylist 成功/取消给出不同结果', () async {
      final ok = _FakeDeps();
      final added = await performSongAction(
        action: SongAction.addToPlaylist,
        song: _song,
        deps: ok.deps,
      );
      expect(added.success, isTrue);
      expect(added.message, '已添加到歌单');

      final cancelled = _FakeDeps()..playlistAdded = false;
      final notAdded = await performSongAction(
        action: SongAction.addToPlaylist,
        song: _song,
        deps: cancelled.deps,
      );
      expect(notAdded.success, isFalse);
      expect(notAdded.message, '未添加到歌单');
    });

    test('toggleLike 反馈收藏/取消收藏', () async {
      final liked = _FakeDeps();
      expect(
        (await performSongAction(
          action: SongAction.toggleLike,
          song: _song,
          deps: liked.deps,
        )).message,
        '已添加到我喜欢',
      );

      final unliked = _FakeDeps()..likeResult = false;
      expect(
        (await performSongAction(
          action: SongAction.toggleLike,
          song: _song,
          deps: unliked.deps,
        )).message,
        '已取消喜欢',
      );
    });

    test('copyLink 复制的是可回流的本应用歌曲链接', () async {
      final fake = _FakeDeps();

      final result = await performSongAction(
        action: SongAction.copyLink,
        song: _song,
        deps: fake.deps,
      );

      expect(fake.copiedText, ShareLinks.songLink(_song));
      expect(fake.copiedText, startsWith('mconnect://song?'));
      // …and it round-trips back into the same song.
      expect(ShareLinks.parseSongLink(fake.copiedText!)?.id, _song.id);
      expect(result.message, '已复制歌曲链接');
    });

    test('share 把歌曲交给分享通道且不额外弹提示（分享面板本身就是反馈）', () async {
      final fake = _FakeDeps();

      final result = await performSongAction(
        action: SongAction.share,
        song: _song,
        deps: fake.deps,
      );

      expect(fake.sharedSong, _song);
      expect(result.success, isTrue);
      expect(result.message, isNull);
    });

    test('任何一个动作抛异常都不会冒泡，而是变成失败提示', () async {
      final fake = _FakeDeps()..throwOn = StateError('platform exploded');

      for (final action in SongAction.values) {
        final result = await performSongAction(
          action: action,
          song: _song,
          deps: fake.deps,
        );
        expect(result.success, isFalse, reason: '$action 必须被兜住');
        expect(result.message, contains('操作失败'));
        expect(result.message, contains('platform exploded'));
      }
    });
  });

  group('冻结的长按菜单（本地歌曲规则）', () {
    // The sheet is six rows tall plus a drag handle; the default 800x600 test
    // surface is shorter than a real phone, and an overflowing Column would fail
    // the test for a layout reason that does not exist on device.
    setUp(() {
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.physicalSize = const Size(1080, 2400);
      view.devicePixelRatio = 3;
    });

    tearDown(() {
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });

    Future<SongAction?> openSheet(
      WidgetTester tester, {
      required bool isLocal,
    }) async {
      SongAction? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    picked = await showSongActionsSheet(
                      context,
                      song: _song,
                      isLocal: isLocal,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return picked;
    }

    testWidgets('在线歌曲显示全部动作，点选后以该动作关闭', (tester) async {
      await openSheet(tester, isLocal: false);

      expect(find.text('下一首播放'), findsOneWidget);
      expect(find.text('添加到歌单'), findsOneWidget);
      expect(find.text('下载'), findsOneWidget);
      expect(find.text('喜欢'), findsOneWidget);
      expect(find.text('复制链接'), findsOneWidget);
      expect(find.text('分享'), findsOneWidget);

      await tester.tap(find.text('分享'));
      await tester.pumpAndSettle();

      // The sheet closed on the tap (the value is delivered to the awaiting
      // caller; the sheet itself must be gone).
      expect(find.text('下一首播放'), findsNothing);
    });

    testWidgets('本地歌曲隐藏下载/加歌单/喜欢/分享，保留下一首播放与复制链接', (tester) async {
      await openSheet(tester, isLocal: true);

      expect(find.text('下一首播放'), findsOneWidget);
      expect(find.text('复制链接'), findsOneWidget);
      expect(find.text('添加到歌单'), findsNothing);
      expect(find.text('下载'), findsNothing);
      expect(find.text('喜欢'), findsNothing);
      expect(find.text('分享'), findsNothing);
    });

    testWidgets('已下载歌曲的下载项禁用', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showSongActionsSheet(
                    context,
                    song: _song,
                    isDownloaded: true,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('已下载'), findsOneWidget);
      // Disabled ListTile: tapping must not close the sheet.
      await tester.tap(find.text('已下载'));
      await tester.pumpAndSettle();
      expect(find.text('下一首播放'), findsOneWidget);
    });
  });
}
