import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/library/data/my_playlists_repository.dart';
import 'package:mconnect/features/library/presentation/providers/my_playlists_provider.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

void main() {
  late Directory tempDir;
  late MyPlaylistsRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mconnect_my_playlists_');
    repository = MyPlaylistsRepository(storageDirectory: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('creates multiple local playlists and keeps them separate', () async {
    final first = await repository.createPlaylist('第一张歌单');
    final second = await repository.createPlaylist('第二张歌单');

    await repository.addSong(first.id, _song('s1', '歌曲 1'));
    await repository.addSong(second.id, _song('s2', '歌曲 2'));

    final firstSongs = await repository.getSongs(first.id);
    final secondSongs = await repository.getSongs(second.id);

    expect(first.id, isNot(second.id));
    expect(firstSongs.map((s) => s.id), ['s1']);
    expect(secondSongs.map((s) => s.id), ['s2']);
  });

  test(
    'imports each shared playlist as a new local playlist with original name',
    () async {
      final importedA = await repository.importPlaylist(
        name: '平台歌单',
        songs: [_song('a1', 'A1')],
      );
      final importedB = await repository.importPlaylist(
        name: '平台歌单',
        songs: [_song('b1', 'B1')],
      );

      final playlists = await repository.getPlaylists();

      expect(importedA.id, isNot(importedB.id));
      expect(playlists, hasLength(2));
      expect(playlists.every((p) => p.name == '平台歌单'), isTrue);
      expect((await repository.getSongs(importedA.id)).single.id, 'a1');
      expect((await repository.getSongs(importedB.id)).single.id, 'b1');
    },
  );

  test('does not duplicate the same song inside one local playlist', () async {
    final playlist = await repository.createPlaylist('我的歌单');
    final song = _song('s1', '歌曲 1');

    await repository.addSong(playlist.id, song);
    await repository.addSong(playlist.id, song);

    final songs = await repository.getSongs(playlist.id);
    final playlists = await repository.getPlaylists();

    expect(songs, hasLength(1));
    expect(playlists.single.songCount, 1);
  });

  test(
    'my playlists notifier adds a platform song to a local playlist',
    () async {
      final playlist = await repository.createPlaylist('我的歌单');
      final notifier = MyPlaylistsNotifier(repository: repository);
      await notifier.load();

      final ok = await notifier.addSong(playlist.id, _song('s1', '歌曲 1'));

      expect(ok, isTrue);
      expect(notifier.state.playlists.single.songCount, 1);
      expect((await repository.getSongs(playlist.id)).single.id, 's1');
    },
  );

  test(
    'imports a large playlist in one batch and keeps every unique song',
    () async {
      final songs = [
        for (var i = 0; i < 1500; i++) _song('s$i', '歌曲 $i'),
        _song('s1499', '歌曲 1499'),
      ];

      final playlist = await repository.importPlaylist(
        name: '大歌单',
        songs: songs,
      );
      final importedSongs = await repository.getSongs(playlist.id);

      expect(importedSongs, hasLength(1500));
      expect(importedSongs.first.id, 's0');
      expect(importedSongs.last.id, 's1499');
      expect((await repository.getPlaylist(playlist.id))!.songCount, 1500);
    },
  );

  test(
    'deletes local playlist and removes songs from a local playlist',
    () async {
      final playlist = await repository.importPlaylist(
        name: '可编辑歌单',
        songs: [_song('s1', '歌曲 1'), _song('s2', '歌曲 2')],
      );

      final removedSong = await repository.removeSong(
        playlist.id,
        _song('s1', '歌曲 1'),
      );
      expect(removedSong, isTrue);
      expect((await repository.getSongs(playlist.id)).map((s) => s.id), ['s2']);

      final deletedPlaylist = await repository.deletePlaylist(playlist.id);
      expect(deletedPlaylist, isTrue);
      expect(await repository.getPlaylist(playlist.id), isNull);
      expect(await repository.getSongs(playlist.id), isEmpty);
    },
  );

  test('exports and imports a Mconnect playlist share link', () async {
    final playlist = await repository.importPlaylist(
      name: '分享歌单',
      songs: [_song('s1', '歌曲 1'), _song('s2', '歌曲 2')],
    );

    final link = await repository.exportPlaylistLink(playlist.id);
    expect(link, startsWith('mconnect://playlist?data='));

    final decoded = MyPlaylistsRepository.decodeShareLink(link!);
    expect(decoded, isNotNull);
    expect(decoded!.name, '分享歌单');
    expect(decoded.songs.map((s) => s.id), ['s1', 's2']);

    final imported = await repository.importShareLink(link);
    expect(imported, isNotNull);
    expect(imported!.id, isNot(playlist.id));
    expect((await repository.getSongs(imported.id)).map((s) => s.id), [
      's1',
      's2',
    ]);
  });
}

Song _song(String id, String name) {
  return Song(
    id: id,
    platform: PlatformType.qq,
    name: name,
    artists: const [Artist(id: 'a1', name: '歌手')],
  );
}
