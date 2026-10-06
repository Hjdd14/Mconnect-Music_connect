import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/local_music/domain/local_library_dedupe.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

void main() {
  Song song({
    required String id,
    required String name,
    required String artist,
    required int seconds,
    PlatformType platform = PlatformType.netease,
  }) {
    return Song(
      id: id,
      platform: platform,
      name: name,
      artists: [Artist(id: 'a', name: artist)],
      duration: Duration(seconds: seconds),
    );
  }

  Song localSong({
    required String path,
    required String name,
    required String artist,
    required int seconds,
  }) => song(
    id: path,
    name: name,
    artist: artist,
    seconds: seconds,
    platform: PlatformType.local,
  );

  test('local and online copies of the same recording merge into one row', () {
    final local = localSong(
      path: '/music/歌.flac',
      name: '歌',
      artist: '歌手',
      seconds: 240,
    );
    // Online metadata is looser: "(Live)" marker, featured artist, +1s rounding.
    final online = song(
      id: 'ne-1',
      name: '歌 (Live)',
      artist: '歌手',
      seconds: 241,
    );

    final merged = LocalLibraryDedupe.mergeLocalWithOnline(
      local: [local],
      online: [online],
    );

    expect(merged, hasLength(1), reason: '同一首歌只能出现一条');
    expect(merged.single.platform, PlatformType.local, reason: '本地优先');
  });

  test('an online-only song is appended and keeps its platform', () {
    final merged = LocalLibraryDedupe.mergeLocalWithOnline(
      local: [
        localSong(path: '/a.flac', name: '本地曲', artist: '甲', seconds: 200),
      ],
      online: [
        song(id: 'ne-2', name: '在线曲', artist: '乙', seconds: 180),
      ],
    );

    expect(merged, hasLength(2));
    expect(merged.first.platform, PlatformType.local);
    expect(merged.last.platform, PlatformType.netease);
  });

  test('preferLocal: false lets the online copy win instead', () {
    final merged = LocalLibraryDedupe.mergeLocalWithOnline(
      local: [
        localSong(path: '/same.flac', name: '同名', artist: '歌手', seconds: 100),
      ],
      online: [song(id: 'qq-1', name: '同名', artist: '歌手', seconds: 100)],
      preferLocal: false,
    );

    expect(merged, hasLength(1));
    expect(merged.single.id, 'qq-1');
    expect(merged.single.platform, PlatformType.netease);
  });

  test('duplicates inside the local library itself also collapse', () {
    final merged = LocalLibraryDedupe.mergeLocalWithOnline(
      local: [
        localSong(path: '/cd1/01.flac', name: '重复', artist: '歌手', seconds: 210),
        localSong(path: '/cd2/01.flac', name: '重复', artist: '歌手', seconds: 211),
      ],
      online: const [],
    );

    expect(merged, hasLength(1));
    expect(merged.single.id, '/cd1/01.flac', reason: '保留第一条');
  });

  test('a different artist is a different song', () {
    final merged = LocalLibraryDedupe.mergeLocalWithOnline(
      local: [
        localSong(path: '/x.flac', name: '同名', artist: '甲', seconds: 200),
      ],
      online: [song(id: 'ne-3', name: '同名', artist: '乙', seconds: 200)],
    );

    expect(merged, hasLength(2));
  });

  test('a length difference beyond the 4-second bucket is a different song', () {
    final merged = LocalLibraryDedupe.mergeLocalWithOnline(
      local: [localSong(path: '/y.flac', name: '歌', artist: '甲', seconds: 240)],
      online: [song(id: 'ne-4', name: '歌', artist: '甲', seconds: 260)],
    );

    expect(merged, hasLength(2));
  });

  test('keysOf/onlyMissing expose which songs are not local yet', () {
    final local = [
      localSong(path: '/z.flac', name: '已有', artist: '甲', seconds: 200),
    ];
    final online = [
      song(id: 'ne-5', name: '已有', artist: '甲', seconds: 200),
      song(id: 'ne-6', name: '新增', artist: '乙', seconds: 200),
    ];

    final missing = LocalLibraryDedupe.onlyMissing(online, local);

    expect(missing, hasLength(1));
    expect(missing.single.id, 'ne-6');
    expect(LocalLibraryDedupe.keysOf(local), hasLength(1));
    expect(LocalLibraryDedupe.isLocal(local.single), isTrue);
  });
}
