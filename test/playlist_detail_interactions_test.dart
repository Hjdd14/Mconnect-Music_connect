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
  Future<List<Song>> getSongs(String playlistId) async =>
      List<Song>.from(songs[playlistId] ?? const <Song>[]);

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

  testWidgets('自建歌单提供拖拽把手，拖动后顺序写入歌单', (tester) async {
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

  testWidgets('长按进入多选，批量移出会真的从歌单删除', (tester) async {
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

  testWidgets('多选状态下不再显示拖拽把手（两种手势不打架）', (tester) async {
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

  testWidgets('批量加入歌单：选择目标歌单后歌曲真的进去', (tester) async {
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

  testWidgets('⋮ 打开共享的长按菜单（动作由 dispatcher 负责）', (tester) async {
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

  testWidgets('平台歌单不可拖拽排序，但保留多选与下载入口', (tester) async {
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

    // Multi-select there offers no "移出": the platform owns the playlist.
    await tester.tap(find.byTooltip('多选'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('批量移出'), findsNothing);
    expect(find.byTooltip('批量下载'), findsOneWidget);
  });
}
