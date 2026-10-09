import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/library/data/my_playlists_repository.dart';
import 'package:mconnect/features/library/presentation/pages/playlist_detail_page.dart';
import 'package:mconnect/features/library/presentation/providers/my_playlists_provider.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/playlist.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/platform/base/music_platform.dart';
import 'package:mconnect/platform/base/platform_registry.dart';

Song _song(
  String id,
  String name, [
  PlatformType platform = PlatformType.local,
]) => Song(
  id: id,
  platform: platform,
  name: name,
  artists: const [Artist(id: 'a', name: '歌手')],
);

List<String> _names(List<Song> songs) => songs.map((s) => s.name).toList();

/// In-memory playlist store.
///
/// A widget test body runs in a fake-async zone, where the page's real on-disk
/// load would never complete (the spinner would spin forever and every
/// `pumpAndSettle` would time out). The on-disk behaviour — atomic reorder,
/// reopening the file, atomic writes — is covered by
/// `test/my_playlists_reorder_test.dart`, which runs as a plain `test()` where
/// real IO is fine.
class _MemoryPlaylists extends MyPlaylistsNotifier {
  _MemoryPlaylists()
    : super(
        repository: MyPlaylistsRepository(
          storageDirectory: Directory.systemTemp.createTempSync(
            'mconnect_ui_mem',
          ),
        ),
      );

  final Map<String, List<Song>> songs = {};
  final List<Playlist> known = [];
  int reorderCalls = 0;
  ReorderCall? lastReorder;

  // --- three-state controls (W3-B) ---------------------------------------
  //
  // Defaults keep every pre-existing case behaving exactly as before; these only
  // exist so the page's loading / error / empty branches can be driven.

  /// When set, `getSongs` fails instead of returning the seeded list.
  Object? fetchError;

  /// When set, `getSongs` never completes — the loading state.
  Completer<List<Song>>? fetchPending;

  /// How many times the page asked for the songs, so "retry" can be proven to
  /// really re-fetch rather than just clear the error.
  int fetchCalls = 0;

  void seed(List<Playlist> playlists, Map<String, List<Song>> songsByPlaylist) {
    known
      ..clear()
      ..addAll(playlists);
    songs
      ..clear()
      ..addAll(songsByPlaylist);
    state = state.copyWith(playlists: playlists);
  }

  @override
  Future<void> load() async {
    // No IO: the widget test seeds [known] directly.
    state = state.copyWith(playlists: known);
  }

  @override
  Future<List<Song>> getSongs(String playlistId) async {
    fetchCalls++;
    final failure = fetchError;
    if (failure != null) throw failure;
    final pending = fetchPending;
    if (pending != null) return pending.future;
    return List<Song>.from(songs[playlistId] ?? const <Song>[]);
  }

  @override
  Future<bool> reorderSongs(String playlistId, List<Song> ordered) async {
    if (!songs.containsKey(playlistId)) return false;
    reorderCalls++;
    lastReorder = ReorderCall(playlistId, _names(ordered));
    songs[playlistId] = List<Song>.from(ordered);
    return true;
  }

  @override
  Future<bool> removeSong(String playlistId, Song song) async {
    final list = songs[playlistId];
    if (list == null) return false;
    final removed = list.length;
    list.removeWhere((s) => s.id == song.id && s.platform == song.platform);
    return list.length != removed;
  }

  @override
  Future<bool> addSong(String playlistId, Song song) async {
    final list = songs[playlistId];
    if (list == null) return false;
    list.add(song);
    return true;
  }
}

class ReorderCall {
  ReorderCall(this.playlistId, this.names);

  final String playlistId;
  final List<String> names;
}

Playlist _playlist(String id, String name) => Playlist(
  id: id,
  name: name,
  platform: PlatformType.local,
  songCount: 0,
  editable: true,
  editId: id,
);

class _FakePlaylistPlatform extends MusicPlatform {
  _FakePlaylistPlatform(this.songs);

  final List<Song> songs;

  @override
  PlatformType get platformType => PlatformType.qq;

  @override
  String get platformName => 'QQ音乐';

  @override
  bool get isLoggedIn => false;

  @override
  Future<List<Song>> getPlaylistDetail(String playlistId) async => songs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _MemoryPlaylists playlists;
  late ProviderContainer container;

  setUp(() {
    playlists = _MemoryPlaylists();
    container = ProviderContainer(
      overrides: [myPlaylistsProvider.overrideWith((ref) => playlists)],
    );
    // A tall surface so every row of a short list is laid out.
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1200, 2400);
    view.devicePixelRatio = 3;
  });

  tearDown(() {
    container.dispose();
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    required PlatformType platform,
    required String playlistId,
    String name = '测试歌单',
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: PlaylistDetailPage(
            platform: platform,
            playlistId: playlistId,
            playlistName: name,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Bounded `testWidgets` — a hang is undiagnosable, so a never-completing
  /// future must fail in 30 s rather than eat the runner's 10-minute default.
  void widgetTest(
    String description,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(
      description,
      body,
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }

  // The page migrated onto `AsyncStateView` with no assertion that could tell:
  // deleting the retry, or letting `_loading` stay true forever, left every test
  // in this file green. One case per branch.

  widgetTest('歌单详情：加载中是共享 loading，且不给重试', (tester) async {
    playlists.seed([_playlist('p1', '加载中')], {});
    playlists.fetchPending = Completer<List<Song>>();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: PlaylistDetailPage(
            platform: PlatformType.local,
            playlistId: 'p1',
            playlistName: '加载中',
          ),
        ),
      ),
    );
    // Deliberately **not** `pumpAndSettle`: this state has a live spinner *and* a
    // future that never completes, so settling would sit there until the timeout.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.text('重试'),
      findsNothing,
      reason: '加载中不是失败，不能给重试',
    );

    // Let the fetch finish so nothing is left pending into teardown.
    playlists.fetchPending!.complete(const <Song>[]);
    playlists.fetchPending = null;
    await tester.pump(const Duration(milliseconds: 16));
  });

  widgetTest('歌单详情：读取失败是共享错误态，重试真的再读一次', (tester) async {
    playlists.seed([_playlist('p1', '失败')], {});
    playlists.fetchError = Exception('playlist fetch boom');

    await pumpPage(tester, platform: PlatformType.local, playlistId: 'p1');

    expect(find.text('加载歌单失败'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, '重试'), findsOneWidget);
    expect(playlists.fetchCalls, 1);

    // Let the retry succeed, so the assertion proves the whole retry path rather
    // than only that a second call happened to fail again.
    playlists.fetchError = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(
      playlists.fetchCalls,
      2,
      reason: '点重试必须真的再读一次，而不是只把错误清掉',
    );
    expect(find.text('歌单暂无歌曲'), findsOneWidget);
  });

  widgetTest('歌单详情：空歌单是空态，不是错误态', (tester) async {
    playlists.seed([_playlist('p1', '空')], {'p1': const <Song>[]});

    await pumpPage(tester, platform: PlatformType.local, playlistId: 'p1');

    expect(find.text('歌单暂无歌曲'), findsOneWidget);
    expect(
      find.text('重试'),
      findsNothing,
      reason: '空歌单不是失败，给重试会让用户以为出错了',
    );
  });

  widgetTest('自建歌单提供拖拽把手，拖动后顺序写入歌单', (tester) async {
    playlists.seed(
      [_playlist('p1', '拖拽歌单')],
      {
        'p1': [_song('a', 'A'), _song('b', 'B'), _song('c', 'C')],
      },
    );
    await pumpPage(tester, platform: PlatformType.local, playlistId: 'p1');

    expect(find.byType(ReorderableListView), findsOneWidget);
    expect(find.byIcon(Icons.drag_handle), findsNWidgets(3));

    // Drag the first row past the second one. The first move must clear the
    // touch slop *before* the tile's long-press timer fires (which would enter
    // multi-select and replace the reorderable list), then one bigger move
    // carries the row below its neighbour.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.drag_handle).first),
    );
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(playlists.reorderCalls, 1, reason: '拖动必须触发一次持久化');
    expect(playlists.lastReorder!.playlistId, 'p1');
    expect(_names(playlists.songs['p1']!), ['B', 'A', 'C']);
    expect(playlists.lastReorder!.names, ['B', 'A', 'C']);
  });

  widgetTest('长按进入多选，批量移出会真的从歌单删除', (tester) async {
    playlists.seed(
      [_playlist('p1', '待整理')],
      {
        'p1': [_song('a', 'A'), _song('b', 'B'), _song('c', 'C')],
      },
    );
    await pumpPage(tester, platform: PlatformType.local, playlistId: 'p1');

    await tester.longPress(find.text('B'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 首'), findsOneWidget);

    await tester.tap(find.byTooltip('全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 3 首'), findsOneWidget);

    await tester.tap(find.byTooltip('批量移出'));
    await tester.pumpAndSettle();

    expect(playlists.songs['p1'], isEmpty);
    expect(find.text('歌单暂无歌曲'), findsOneWidget);
  });

  widgetTest('多选状态下不再显示拖拽把手（两种手势不打架）', (tester) async {
    playlists.seed(
      [_playlist('p1', '多选')],
      {
        'p1': [_song('a', 'A'), _song('b', 'B')],
      },
    );
    await pumpPage(tester, platform: PlatformType.local, playlistId: 'p1');

    expect(find.byIcon(Icons.drag_handle), findsNWidgets(2));
    await tester.longPress(find.text('A'));
    await tester.pumpAndSettle();

    expect(find.byType(Checkbox), findsNWidgets(2));
    expect(find.byIcon(Icons.drag_handle), findsNothing);

    await tester.tap(find.byTooltip('退出多选'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.drag_handle), findsNWidgets(2));
  });

  widgetTest('批量加入歌单：选择目标歌单后歌曲真的进去', (tester) async {
    playlists.seed(
      [_playlist('p1', '来源歌单'), _playlist('p2', '目标歌单')],
      {
        'p1': [_song('a', 'A'), _song('b', 'B')],
        'p2': <Song>[],
      },
    );
    await pumpPage(tester, platform: PlatformType.local, playlistId: 'p1');

    expect(
      container.read(myPlaylistsProvider).playlists.map((p) => p.name).toList(),
      ['来源歌单', '目标歌单'],
      reason: '目标歌单选择表读的是 provider 状态，先确认状态里有数据',
    );

    await tester.longPress(find.text('A'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('批量加入歌单'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('把 1 首加入歌单'), findsOneWidget);
    expect(find.text('目标歌单'), findsOneWidget);
    await tester.tap(find.text('目标歌单'));
    await tester.pumpAndSettle();

    expect(_names(playlists.songs['p2']!), ['A']);
  });

  widgetTest('⋮ 打开共享的长按菜单（动作由 dispatcher 负责）', (tester) async {
    playlists.seed(
      [_playlist('p1', '菜单')],
      {
        'p1': [_song('a', 'A')],
      },
    );
    await pumpPage(tester, platform: PlatformType.local, playlistId: 'p1');

    await tester.tap(find.byTooltip('歌曲操作'));
    await tester.pumpAndSettle();

    expect(find.text('下一首播放'), findsOneWidget);
    expect(find.text('复制链接'), findsOneWidget);
    // Local files cannot be shared/queued to a platform: the frozen sheet hides
    // those actions.
    expect(find.text('分享'), findsNothing);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('下一首播放'), findsNothing);
  });

  widgetTest('平台歌单不可拖拽排序，但保留多选与下载入口', (tester) async {
    PlatformRegistry.register(
      _FakePlaylistPlatform([
        _song('s1', 'S1', PlatformType.qq),
        _song('s2', 'S2', PlatformType.qq),
      ]),
    );
    await pumpPage(
      tester,
      platform: PlatformType.qq,
      playlistId: 'remote-1',
      name: 'QQ 歌单',
    );

    expect(find.byType(ReorderableListView), findsNothing);
    expect(find.byIcon(Icons.drag_handle), findsNothing);
    expect(find.byTooltip('多选'), findsOneWidget);
    expect(find.byIcon(Icons.file_download_outlined), findsNWidgets(2));

    await tester.tap(find.byTooltip('多选'));
    await tester.pumpAndSettle();

    // 这条断言原先写的是"平台歌单不提供批量移出"—— 那正是用户报的
    // 「无法删除歌单内歌曲」。排序仍归平台（上面两条不变），但**移出歌曲**现在
    // 走平台适配器 `removeSongFromPlaylist`：平台支持就成功，不支持就如实提示
    // "暂不支持"，而不是把这个入口藏起来让用户以为功能不存在。
    expect(find.byTooltip('批量移出'), findsOneWidget);
    expect(find.byTooltip('批量下载'), findsOneWidget);
  });
}
