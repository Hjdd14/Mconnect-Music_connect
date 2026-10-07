import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/local_music/data/local_lyrics_store.dart';
import 'package:mconnect/features/local_music/data/local_music_repository.dart';
import 'package:mconnect/features/local_music/data/local_scan_root_store.dart';
import 'package:mconnect/features/local_music/data/local_track_store.dart';
import 'package:mconnect/features/local_music/data/online_library_snapshot.dart';
import 'package:mconnect/features/local_music/presentation/pages/local_music_page.dart';
import 'package:mconnect/features/local_music/presentation/providers/local_music_provider.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

void main() {
  Future<LocalMusicNotifier> notifierWithLibrary() async {
    final notifier = LocalMusicNotifier(
      scanner: _NoopScanner(),
      trackStore: MemoryLocalTrackStore([
        _track('D:/Music/rock/01.flac', '摇滚一号', artist: '乐队甲', album: '专辑一', trackNumber: 1),
        _track('D:/Music/rock/02.flac', '摇滚二号', artist: '乐队甲', album: '专辑一', trackNumber: 2),
        _track('D:/Music/jazz/03.flac', '爵士三号', artist: '歌手乙', album: '专辑二'),
      ]),
      lyricsStore: MemoryLocalLyricsStore(),
      rootStore: MemoryLocalScanRootStore('D:/Music'),
      onlineSnapshot: MemoryOnlineLibrarySnapshot(),
    );
    await notifier.loadFromIndex();
    return notifier;
  }

  Widget app(LocalMusicNotifier notifier) {
    return ProviderScope(
      overrides: [localMusicProvider.overrideWith((ref) => notifier)],
      child: const MaterialApp(home: LocalMusicPage()),
    );
  }

  testWidgets('the local page offers the four library views', (tester) async {
    final notifier = await notifierWithLibrary();

    await tester.pumpWidget(app(notifier));
    await tester.pumpAndSettle();

    expect(find.text('歌曲'), findsOneWidget);
    expect(find.text('专辑'), findsOneWidget);
    expect(find.text('歌手'), findsOneWidget);
    expect(find.text('文件夹'), findsOneWidget);
    expect(
      find.byKey(const Key('local-music-merge-switch')),
      findsOneWidget,
    );
  });

  testWidgets('the songs view lists the persisted tracks', (tester) async {
    final notifier = await notifierWithLibrary();

    await tester.pumpWidget(app(notifier));
    await tester.pumpAndSettle();

    expect(find.text('摇滚一号'), findsOneWidget);
    expect(find.text('爵士三号'), findsOneWidget);
    expect(find.text('D:/Music'), findsOneWidget);
  });

  testWidgets('the album view groups tracks and expands them', (tester) async {
    final notifier = await notifierWithLibrary();

    await tester.pumpWidget(app(notifier));
    await tester.pumpAndSettle();

    await tester.tap(find.text('专辑'));
    await tester.pumpAndSettle();

    expect(find.text('专辑一'), findsOneWidget);
    expect(find.text('专辑二'), findsOneWidget);
    // Grouped titles are hidden until the group is expanded.
    expect(find.text('摇滚一号'), findsNothing);

    await tester.tap(find.text('专辑一'));
    await tester.pumpAndSettle();

    expect(find.text('摇滚一号'), findsOneWidget);
    expect(find.text('摇滚二号'), findsOneWidget);
  });

  testWidgets('the artist and folder views group by the right key', (tester) async {
    final notifier = await notifierWithLibrary();

    await tester.pumpWidget(app(notifier));
    await tester.pumpAndSettle();

    await tester.tap(find.text('歌手'));
    await tester.pumpAndSettle();
    expect(find.text('乐队甲'), findsOneWidget);
    expect(find.text('歌手乙'), findsOneWidget);

    await tester.tap(find.text('文件夹'));
    await tester.pumpAndSettle();
    expect(find.text('rock'), findsOneWidget);
    expect(find.text('jazz'), findsOneWidget);
  });

  testWidgets('switching the merge switch loads the online snapshot', (tester) async {
    final notifier = LocalMusicNotifier(
      scanner: _NoopScanner(),
      trackStore: MemoryLocalTrackStore([
        _track('D:/Music/rock/01.flac', '在线也有的歌', artist: '乐队甲', album: '专辑一'),
      ]),
      lyricsStore: MemoryLocalLyricsStore(),
      rootStore: MemoryLocalScanRootStore('D:/Music'),
      onlineSnapshot: MemoryOnlineLibrarySnapshot([
        Song(
          id: 'ne-1',
          platform: PlatformType.netease,
          name: '在线也有的歌',
          artists: const [Artist(id: 'a', name: '乐队甲')],
          duration: const Duration(seconds: 190),
        ),
      ]),
    );
    await notifier.loadFromIndex();

    await tester.pumpWidget(app(notifier));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('local-music-merge-switch')));
    await tester.pumpAndSettle();

    expect(notifier.state.mergeWithOnline, isTrue);
    expect(notifier.state.onlineSongs, hasLength(1));
    // Local preferred: the online duplicate is hidden, so the track appears once.
    expect(find.text('在线也有的歌'), findsOneWidget);
    expect(find.textContaining('在线曲库中也有'), findsOneWidget);
  });

  testWidgets('the skipped-files banner shows up when lyrics were rejected', (tester) async {
    final notifier = LocalMusicNotifier(
      scanner: _NoopScanner(),
      trackStore: MemoryLocalTrackStore([
        _track('D:/Music/rock/01.flac', '一首', artist: '甲', album: '专辑一'),
      ]),
      lyricsStore: MemoryLocalLyricsStore(),
      rootStore: MemoryLocalScanRootStore('D:/Music'),
      onlineSnapshot: MemoryOnlineLibrarySnapshot(),
    );
    await notifier.scanDirectory('D:/Music');

    await tester.pumpWidget(app(notifier));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('local-music-scan-summary')), findsOneWidget);
  });

  testWidgets('long-pressing a local track opens the action menu without the '
      'actions a local file cannot do', (tester) async {
    final notifier = await notifierWithLibrary();

    await tester.pumpWidget(app(notifier));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('摇滚一号'));
    await tester.pumpAndSettle();

    // Applicable to a local file.
    expect(find.text('下一首播放'), findsOneWidget);
    expect(find.text('复制链接'), findsOneWidget);

    // Requires a platform song id / a network source: must not be offered.
    expect(find.text('下载'), findsNothing);
    expect(find.text('已下载'), findsNothing);
    expect(find.text('分享'), findsNothing);
    expect(find.text('添加到歌单'), findsNothing);
    expect(find.text('喜欢'), findsNothing);
    expect(find.text('取消喜欢'), findsNothing);
  });

  testWidgets('a long-press action really runs (clipboard gets the song link)', (
    tester,
  ) async {
    final clipboardWrites = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardWrites.add((call.arguments as Map)['text']);
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    final notifier = await notifierWithLibrary();
    await tester.pumpWidget(app(notifier));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('爵士三号'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制链接'));
    await tester.pumpAndSettle();

    expect(clipboardWrites, hasLength(1));
    final link = Uri.parse(clipboardWrites.single! as String);
    expect(link.scheme, 'mconnect');
    expect(link.host, 'song');
    expect(link.queryParameters['platform'], 'local');
    expect(link.queryParameters['id'], 'D:/Music/jazz/03.flac');
    expect(link.queryParameters['name'], '爵士三号');
    // The sheet is gone and the result was reported.
    expect(find.text('复制链接'), findsNothing);
    expect(find.text('已复制歌曲链接'), findsOneWidget);
  });

  testWidgets('long-pressing a track inside a group also opens the menu', (
    tester,
  ) async {
    final notifier = await notifierWithLibrary();
    await tester.pumpWidget(app(notifier));
    await tester.pumpAndSettle();

    await tester.tap(find.text('歌手'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('乐队甲'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('摇滚二号'));
    await tester.pumpAndSettle();

    expect(find.text('下一首播放'), findsOneWidget);
    expect(find.text('下载'), findsNothing);
    expect(find.text('分享'), findsNothing);
  });
}

LocalTrackEntry _track(
  String path,
  String title, {
  String? artist,
  String? album,
  int? trackNumber,
  int durationMs = 190000,
}) => LocalTrackEntry(
  path: path,
  mtime: 1,
  size: 1,
  title: title,
  artistName: artist,
  albumName: album,
  trackNumber: trackNumber,
  durationMs: durationMs,
  scannedAt: 1,
);

class _NoopScanner implements LocalMusicScanner {
  @override
  Future<LocalMusicScanResult> scanDirectory(String rootPath) async =>
      const LocalMusicScanResult();
}
