import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/share/share_service.dart';
import 'package:mconnect/features/library/data/my_playlists_repository.dart';
import 'package:mconnect/features/library/presentation/pages/platform_playlists_page.dart';
import 'package:mconnect/features/library/presentation/providers/my_playlists_provider.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/playlist.dart';
import 'package:mconnect/models/song.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// W1-C increment 2: the playlist export entry.
///
/// These pump the real page because the point of this increment is that the
/// transfer formats became *reachable*; a unit test of the codecs (which already
/// exist, see `transfer_test.dart`) would not prove that.

const _playlist = Playlist(
  id: 'my_1',
  name: '我的最爱',
  platform: PlatformType.local,
  songCount: 2,
  editable: true,
);

const _songs = <Song>[
  Song(
    id: '1',
    platform: PlatformType.netease,
    name: '夜曲',
    artists: <Artist>[Artist(id: '', name: '周杰伦')],
    duration: Duration(seconds: 227),
  ),
  Song(
    id: '2',
    platform: PlatformType.qq,
    name: '富士山下',
    artists: <Artist>[Artist(id: '', name: '陈奕迅')],
    duration: Duration(seconds: 258),
  ),
];

const _link = 'mconnect://playlist?data=abc';

void main() {
  late _RecordingChannel channel;

  setUp(() {
    channel = _RecordingChannel();
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    String link = _link,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myPlaylistsProvider.overrideWith(
            (ref) => MyPlaylistsNotifier(
              repository: _FakeMyPlaylistsRepository(link: link),
            ),
          ),
          shareServiceProvider.overrideWithValue(ShareService(channel)),
        ],
        child: const MaterialApp(home: PlatformPlaylistsPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Opens the per-playlist menu and picks the export entry.
  Future<void> openExportSheet(WidgetTester tester) async {
    await tester.tap(find.byTooltip('歌单操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出歌单'));
    await tester.pumpAndSettle();
  }

  testWidgets('导出入口列出四种搬运方式，二维码也在其中', (tester) async {
    await pumpPage(tester);
    await openExportSheet(tester);

    for (final label in const <String>[
      '分享链接',
      'M3U8 播放列表',
      '纯文本（歌名 - 歌手）',
      'Mconnect JSON',
      '二维码分享',
    ]) {
      expect(find.text(label), findsOneWidget, reason: '缺少导出方式：$label');
    }
  });

  testWidgets('M3U8 导出的是完整、可另存为 .m3u8 的文本', (tester) async {
    await pumpPage(tester);
    await openExportSheet(tester);

    await tester.tap(find.text('M3U8 播放列表'));
    await tester.pumpAndSettle();

    final shared = channel.texts.single;
    expect(shared, startsWith('#EXTM3U'));
    expect(shared, contains('#PLAYLIST:我的最爱'));
    expect(shared, contains('#EXTINF:227,夜曲 - 周杰伦'));
    expect(shared, contains('#EXTINF:258,富士山下 - 陈奕迅'));
    // The default locator round-trips back into the app, which is what makes
    // export → import a real round trip rather than a dead end.
    expect(shared, contains('mconnect://song?'));
    expect(channel.subjects.single, contains('我的最爱'));
  });

  testWidgets('纯文本导出是逐行「歌名 - 歌手」', (tester) async {
    await pumpPage(tester);
    await openExportSheet(tester);

    await tester.tap(find.text('纯文本（歌名 - 歌手）'));
    await tester.pumpAndSettle();

    expect(channel.texts.single, '夜曲 - 周杰伦\n富士山下 - 陈奕迅');
  });

  testWidgets('JSON 导出带 format 标记与平台/id，可回流导入', (tester) async {
    await pumpPage(tester);
    await openExportSheet(tester);

    await tester.tap(find.text('Mconnect JSON'));
    await tester.pumpAndSettle();

    final shared = channel.texts.single;
    expect(shared, contains('"format": "mconnect.playlist"'));
    expect(shared, contains('"platform": "netease"'));
    expect(shared, contains('"id": "1"'));
  });

  testWidgets('分享链接走 ShareService.sharePlaylist（不再是死方法）', (tester) async {
    await pumpPage(tester);
    await openExportSheet(tester);

    await tester.tap(find.text('分享链接'));
    await tester.pumpAndSettle();

    // `buildPlaylistShareText` 的形状：名称（N 首）+ 来源 + 链接。
    expect(channel.texts.single, contains('我的最爱（2 首）'));
    expect(channel.texts.single, contains('Mconnect'));
    expect(channel.texts.single, contains(_link));
    expect(channel.subjects.single, '我的最爱');
  });

  testWidgets('二维码的内容就是歌单分享链接', (tester) async {
    // `QrImageView` keeps its payload in a private field (`_data`), so the
    // assertion goes through `semanticsLabel` — which the implementation sets to
    // the very same string. That field is public (`qr_image_view.dart:143`) and
    // is asserted directly rather than through the semantics tree: it pins "the
    // payload we encoded is the payload we declared", and it does not depend on
    // how qr_flutter wires its own semantics node.
    await pumpPage(tester);
    await openExportSheet(tester);

    await tester.tap(find.text('二维码分享'));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) => widget is QrImageView && widget.semanticsLabel == _link,
      ),
      findsOneWidget,
    );
    expect(find.byType(QrImageView), findsOneWidget);
    // 二维码不该同时触发一次分享。
    expect(channel.texts, isEmpty);
  });

  testWidgets('链接长到扫不动时给出提示，而不是画一个读不出来的二维码', (tester) async {
    final tooLong =
        'mconnect://playlist?data=${List<String>.filled(1300, 'a').join()}';
    await pumpPage(tester, link: tooLong);
    await openExportSheet(tester);

    await tester.tap(find.text('二维码分享'));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsNothing);
    expect(find.textContaining('二维码'), findsWidgets, reason: '必须说明为什么没有二维码');
  });
}

class _RecordingChannel implements ShareChannel {
  final List<String> texts = <String>[];
  final List<String?> subjects = <String?>[];

  @override
  Future<void> shareText(String text, {String? subject, Rect? origin}) async {
    texts.add(text);
    subjects.add(subject);
  }
}

/// In-memory stand-in for the on-disk repository: a widget test must not touch
/// the filesystem (real I/O never completes inside `testWidgets`' fake-async
/// zone).
class _FakeMyPlaylistsRepository extends MyPlaylistsRepository {
  _FakeMyPlaylistsRepository({this.link = _link});

  final String link;

  @override
  Future<List<Playlist>> getPlaylists() async => const <Playlist>[_playlist];

  @override
  Future<String?> exportPlaylistLink(String playlistId) async => link;

  @override
  Future<List<Song>> getSongs(String playlistId) async => _songs;
}
