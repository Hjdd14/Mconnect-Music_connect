import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/local_music/data/local_lyrics_store.dart';
import 'package:mconnect/features/local_music/data/local_music_repository.dart';
import 'package:mconnect/features/local_music/data/local_scan_root_store.dart';
import 'package:mconnect/features/local_music/data/local_track_store.dart';
import 'package:mconnect/features/local_music/data/online_library_snapshot.dart';
import 'package:mconnect/features/local_music/data/track_ratings_store.dart';
import 'package:mconnect/features/local_music/domain/local_library_query.dart';
import 'package:mconnect/features/local_music/presentation/pages/local_music_page.dart';
import 'package:mconnect/features/local_music/presentation/providers/local_music_provider.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:path/path.dart' as p;

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

  // ---- W2-C: search / sort / filter / batch selection ----------------------

  LocalTrackEntry entry(
    String path,
    String title, {
    String? artist,
    int durationMs = 0,
  }) => LocalTrackEntry(
    path: path,
    mtime: 1,
    size: 1,
    title: title,
    artistName: artist,
    durationMs: durationMs,
  );

  Future<LocalMusicNotifier> library(
    List<LocalTrackEntry> tracks, {
    MemoryTrackRatingsStore? ratings,
  }) async {
    final notifier = LocalMusicNotifier(
      scanner: _NoopScanner(),
      trackStore: MemoryLocalTrackStore(tracks),
      lyricsStore: MemoryLocalLyricsStore(),
      rootStore: MemoryLocalScanRootStore('D:/Music'),
      onlineSnapshot: MemoryOnlineLibrarySnapshot(),
      ratingsStore: ratings ?? MemoryTrackRatingsStore(),
    );
    await notifier.loadFromIndex();
    return notifier;
  }

  /// The title of the first row **inside the list** (the header's merge switch is
  /// also a `ListTile`, so the search is scoped to the `ListView`).
  String firstListedTitle(WidgetTester tester) {
    final tiles = tester
        .widgetList<ListTile>(
          find.descendant(
            of: find.byType(ListView),
            matching: find.byType(ListTile),
          ),
        )
        .toList();
    return (tiles.first.title! as Text).data!;
  }

  /// A row title, scoped to the list rows.
  ///
  /// A bare `find.text('AAA')` matches **twice** once the search box contains
  /// 'AAA' — the field's own `EditableText` holds the same string — which is the
  /// classic `find.text` trap. Anything that means "a song row" goes through this
  /// finder (or [firstListedTitle]).
  Finder listedText(String text) =>
      find.descendant(of: find.byType(ListTile), matching: find.text(text));

  /// Pumps a bounded number of frames instead of `pumpAndSettle`.
  ///
  /// `pumpAndSettle` waits for **every** scheduled frame and only gives up after
  /// its 10-minute default, so one always-on animation (this page can show the
  /// shimmer skeleton, and route transitions keep timers alive) turns a single
  /// line into a ten-minute stall that blocks the whole `flutter test` run — W0-E
  /// hit exactly this on the queue page. A fixed frame budget is enough for the
  /// animations these tests trigger, and it cannot hang.
  Future<void> settle(WidgetTester tester, {int frames = 60}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('the search box narrows the list and the clear action restores it',
      (tester) async {
    final notifier = await library([
      entry('D:/Music/a.flac', 'AAA'),
      entry('D:/Music/b.flac', 'BBB'),
    ]);
    await tester.pumpWidget(app(notifier));
    await settle(tester);

    expect(listedText('AAA'), findsOneWidget);
    expect(listedText('BBB'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('local-music-search-field')),
      'AAA',
    );
    await settle(tester);

    // Scoped to the rows: the search field itself now contains 'AAA' too.
    expect(listedText('AAA'), findsOneWidget);
    expect(listedText('BBB'), findsNothing);
    expect(find.byKey(const Key('local-music-filter-summary')), findsOneWidget);

    await tester.tap(find.byKey(const Key('local-music-search-clear')));
    await settle(tester);

    expect(listedText('BBB'), findsOneWidget);
    expect(notifier.state.query.hasKeyword, isFalse);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('the sort control offers every field and reorders by duration',
      (tester) async {
    final notifier = await library([
      entry('D:/Music/a.flac', 'AAA', durationMs: 5000),
      entry('D:/Music/b.flac', 'BBB', durationMs: 1000),
    ]);
    await tester.pumpWidget(app(notifier));
    await settle(tester);

    expect(firstListedTitle(tester), 'AAA', reason: '默认按名称');

    await tester.tap(find.byKey(const Key('local-music-sort-button')));
    await settle(tester);
    for (final label in const [
      '名称',
      '歌手',
      '专辑',
      '时长',
      '最近添加',
      '播放次数',
    ]) {
      expect(find.text(label), findsWidgets, reason: '排序菜单缺少 $label');
    }

    await tester.tap(find.text('时长').last);
    await settle(tester);

    expect(notifier.state.query.sort, LocalSortField.duration);
    expect(firstListedTitle(tester), 'BBB', reason: '1000ms 比 5000ms 短');
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('the unrated filter hides a rated track', (tester) async {
    final rated = entry('D:/Music/a.flac', 'AAA');
    final notifier = await library(
      [rated, entry('D:/Music/b.flac', 'BBB')],
      ratings: MemoryTrackRatingsStore(
        ratings: {localTrackSongKey(rated): 5},
      ),
    );
    await tester.pumpWidget(app(notifier));
    await settle(tester);

    final chip = find.byKey(const Key('local-music-filter-unrated'));
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await settle(tester);

    expect(find.text('BBB'), findsOneWidget);
    expect(find.text('AAA'), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('a keyword that matches nothing is an empty state, not an error',
      (tester) async {
    final notifier = await library([entry('D:/Music/a.flac', 'AAA')]);
    await tester.pumpWidget(app(notifier));
    await settle(tester);

    await tester.enterText(
      find.byKey(const Key('local-music-search-field')),
      'zzz',
    );
    await settle(tester);

    expect(find.text('没有匹配的歌曲'), findsOneWidget);
    expect(
      find.text('重试'),
      findsNothing,
      reason: '筛选无结果不是失败态，不该出现重试按钮',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('batch 移出曲库 removes the record but never the audio file',
      (tester) async {
    // **Synchronous** file I/O on purpose. `testWidgets` runs its body in a
    // fake-async zone, where awaiting a real I/O future (createTemp /
    // writeAsBytes / exists) never settles — that is exactly what turned this
    // case into a 30-second timeout. The `*Sync` variants need no zone at all,
    // so the fixture is set up and verified with no `runAsync` juggling and no
    // await that the fake clock cannot drive.
    final dir = Directory.systemTemp.createTempSync('mconnect_local_page_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final file = File(p.join(dir.path, 'keep-me.flac'))..writeAsBytesSync([1, 2, 3, 4]);

    final notifier = await library([
      entry(file.path, 'KEEP'),
      entry(p.join(dir.path, 'other.flac'), 'OTHER'),
    ]);
    await tester.pumpWidget(app(notifier));
    await settle(tester);

    await tester.tap(find.byKey(const Key('local-music-select-toggle')));
    await settle(tester);
    expect(find.byKey(const Key('local-music-selection-count')), findsOneWidget);

    await tester.tap(find.byKey(Key('local-music-select-${file.path}')));
    await settle(tester);
    expect(find.text('已选 1 首'), findsOneWidget);

    // The dialog must be fully on screen before its button is tapped: tapping
    // during the entrance animation is a miss, and the `showDialog` future would
    // then never complete.
    await tester.tap(find.byKey(const Key('local-music-batch-remove')));
    await settle(tester);
    expect(find.text('移出 1 首？'), findsOneWidget);

    await tester.tap(find.byKey(const Key('local-music-remove-confirm')));
    await settle(tester);

    expect(
      file.existsSync(),
      isTrue,
      reason: '页面必须走 removeSelected：只删索引记录，绝不删音频文件',
    );
    expect(file.lengthSync(), 4);
    expect(listedText('KEEP'), findsNothing);
    expect(listedText('OTHER'), findsOneWidget);
    expect(notifier.state.selectionMode, isFalse);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('the local page offers the four library views', (tester) async {
    final notifier = await notifierWithLibrary();

    await tester.pumpWidget(app(notifier));
    await settle(tester);

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
    await settle(tester);

    expect(find.text('摇滚一号'), findsOneWidget);
    expect(find.text('爵士三号'), findsOneWidget);
    expect(find.text('D:/Music'), findsOneWidget);
  });

  testWidgets('the album view groups tracks and expands them', (tester) async {
    final notifier = await notifierWithLibrary();

    await tester.pumpWidget(app(notifier));
    await settle(tester);

    await tester.tap(find.text('专辑'));
    await settle(tester);

    expect(find.text('专辑一'), findsOneWidget);
    expect(find.text('专辑二'), findsOneWidget);
    // Grouped titles are hidden until the group is expanded.
    expect(find.text('摇滚一号'), findsNothing);

    await tester.tap(find.text('专辑一'));
    await settle(tester);

    expect(find.text('摇滚一号'), findsOneWidget);
    expect(find.text('摇滚二号'), findsOneWidget);
  });

  testWidgets('the artist and folder views group by the right key', (tester) async {
    final notifier = await notifierWithLibrary();

    await tester.pumpWidget(app(notifier));
    await settle(tester);

    await tester.tap(find.text('歌手'));
    await settle(tester);
    expect(find.text('乐队甲'), findsOneWidget);
    expect(find.text('歌手乙'), findsOneWidget);

    await tester.tap(find.text('文件夹'));
    await settle(tester);
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
    await settle(tester);

    await tester.tap(find.byKey(const Key('local-music-merge-switch')));
    await settle(tester);

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
    await settle(tester);

    expect(find.byKey(const Key('local-music-scan-summary')), findsOneWidget);
  });

  testWidgets('long-pressing a local track opens the action menu without the '
      'actions a local file cannot do', (tester) async {
    final notifier = await notifierWithLibrary();

    await tester.pumpWidget(app(notifier));
    await settle(tester);

    await tester.longPress(find.text('摇滚一号'));
    await settle(tester);

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
    await settle(tester);

    await tester.longPress(find.text('爵士三号'));
    await settle(tester);
    await tester.tap(find.text('复制链接'));
    await settle(tester);

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
    await settle(tester);

    await tester.tap(find.text('歌手'));
    await settle(tester);
    await tester.tap(find.text('乐队甲'));
    await settle(tester);
    await tester.longPress(find.text('摇滚二号'));
    await settle(tester);

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
