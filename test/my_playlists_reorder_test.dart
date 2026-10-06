import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/library/data/my_playlists_repository.dart';
import 'package:mconnect/features/library/presentation/providers/my_playlists_provider.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

Song _song(String id, String name) => Song(
  id: id,
  platform: PlatformType.netease,
  name: name,
  artists: const [Artist(id: 'a', name: '歌手')],
);

List<String> _names(List<Song> songs) => songs.map((s) => s.name).toList();

void main() {
  late Directory tempDir;
  late MyPlaylistsRepository repository;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mconnect_reorder_test');
    repository = MyPlaylistsRepository(storageDirectory: tempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<String> seedThreeSongs() async {
    final playlist = await repository.createPlaylist('拖拽歌单');
    for (final song in [_song('1', 'A'), _song('2', 'B'), _song('3', 'C')]) {
      await repository.addSong(playlist.id, song);
    }
    return playlist.id;
  }

  group('MyPlaylistsRepository.reorderSongs', () {
    test('重排后立即生效，且换一个仓库实例重开依然是新顺序', () async {
      final id = await seedThreeSongs();

      final ok = await repository.reorderSongs(id, [
        _song('3', 'C'),
        _song('1', 'A'),
        _song('2', 'B'),
      ]);

      expect(ok, isTrue);
      expect(_names(await repository.getSongs(id)), ['C', 'A', 'B']);

      // A fresh instance reads the same file: the order survives a restart.
      final reopened = MyPlaylistsRepository(storageDirectory: tempDir);
      expect(_names(await reopened.getSongs(id)), ['C', 'A', 'B']);
    });

    test('原来在中间的歌曲可以拖到末尾（A C B 之外的真实拖拽）', () async {
      final id = await seedThreeSongs();

      await repository.reorderSongs(id, [
        _song('1', 'A'),
        _song('3', 'C'),
        _song('2', 'B'),
      ]);

      expect(_names(await repository.getSongs(id)), ['A', 'C', 'B']);
      expect(await repository.reorderSongs(id, const []), isTrue);
    });

    test('未知歌单 id → false，且不抛异常', () async {
      await seedThreeSongs();

      expect(
        await repository.reorderSongs('my_missing', [_song('1', 'A')]),
        isFalse,
      );
    });

    test('空歌单重排是安全空操作（songKeys 是 const []，不能原地改）', () async {
      final playlist = await repository.createPlaylist('空歌单');

      expect(await repository.reorderSongs(playlist.id, const []), isTrue);
      expect(await repository.getSongs(playlist.id), isEmpty);
    });

    test('列表漏歌时不丢歌：遗漏的按原相对顺序补到末尾', () async {
      final id = await seedThreeSongs();

      // The caller only sent one of the three (e.g. an interrupted rebuild).
      await repository.reorderSongs(id, [_song('3', 'C')]);

      expect(_names(await repository.getSongs(id)), ['C', 'A', 'B']);
    });

    test('外来歌曲被忽略，重复项只保留一次', () async {
      final id = await seedThreeSongs();

      await repository.reorderSongs(id, [
        _song('2', 'B'),
        _song('999', '不在歌单里'),
        _song('2', 'B'),
        _song('1', 'A'),
      ]);

      expect(_names(await repository.getSongs(id)), ['B', 'A', 'C']);
    });
  });

  group('MyPlaylistsNotifier.reorderSongs', () {
    test('成功返回 true 并落盘', () async {
      final id = await seedThreeSongs();
      final notifier = MyPlaylistsNotifier(repository: repository);

      final ok = await notifier.reorderSongs(id, [
        _song('2', 'B'),
        _song('3', 'C'),
        _song('1', 'A'),
      ]);

      expect(ok, isTrue);
      expect(notifier.state.error, isNull);
      expect(_names(await repository.getSongs(id)), ['B', 'C', 'A']);
    });

    test('未知歌单 → false 并给出可见错误（拖拽失败不能静默）', () async {
      final notifier = MyPlaylistsNotifier(repository: repository);

      final ok = await notifier.reorderSongs('my_missing', [_song('1', 'A')]);

      expect(ok, isFalse);
      expect(notifier.state.error, '歌单不存在');
    });
  });
}
