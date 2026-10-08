import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/player/presentation/providers/lyrics_offset_provider.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

/// W2-A：按歌偏移持久化。
///
/// 以前 `lyrics_offset_ms` 是 Hive 里的**单个全局键**：给一首歌做了校准，其他每
/// 一首歌的歌词都会被同一份偏移平移。数据库里已经有 `lyrics_offsets`
/// (`songKey` 主键) 与 `LyricsOffsetDao`，这里把 notifier 改成绑定当前曲目。
void main() {
  test('builds the per-song key shape the DB stores', () {
    // 与 LyricsOffsets.songKey / SourceMatchCaches.songKey 同一形状。
    expect(lyricsOffsetSongKey(_song('abc', PlatformType.qq)), 'qq:abc');
    expect(
      lyricsOffsetSongKey(_song('xyz', PlatformType.netease)),
      'netease:xyz',
    );
  });

  test('binds to a song and loads that song saved offset', () async {
    final loaded = <String>[];
    final notifier = LyricsOffsetNotifier(
      load: (key) async {
        loaded.add(key);
        return const Duration(milliseconds: 1500);
      },
    );
    addTearDown(notifier.dispose);

    await notifier.bindSong('netease:a');

    expect(loaded, ['netease:a']);
    expect(notifier.songKey, 'netease:a');
    expect(notifier.state, const Duration(milliseconds: 1500));
  });

  test('switching songs replaces the previous calibration', () async {
    const saved = {
      'netease:a': Duration(milliseconds: 2000),
      'netease:b': Duration.zero,
    };
    final notifier = LyricsOffsetNotifier(load: (key) async => saved[key]!);
    addTearDown(notifier.dispose);

    await notifier.bindSong('netease:a');
    expect(notifier.state, const Duration(milliseconds: 2000));

    await notifier.bindSong('netease:b');

    expect(
      notifier.state,
      Duration.zero,
      reason: '换歌不得把上一首的校准带过去（这正是全局单键的 bug）',
    );
  });

  test('persists every change against the bound song key', () async {
    final writes = <String>[];
    final notifier = LyricsOffsetNotifier(
      persist: (key, milliseconds) async =>
          writes.add('$key=${milliseconds}ms'),
    );
    addTearDown(notifier.dispose);
    await notifier.bindSong('qq:9');

    await notifier.adjust(const Duration(milliseconds: 500));
    await notifier.reset();

    expect(writes, ['qq:9=500ms', 'qq:9=0ms']);
  });

  test('tells the store there is no song when nothing is bound', () async {
    final keys = <String?>[];
    final notifier = LyricsOffsetNotifier(
      persist: (key, milliseconds) async => keys.add(key),
    );
    addTearDown(notifier.dispose);

    await notifier.adjust(const Duration(milliseconds: 500));

    expect(
      keys,
      [null],
      reason: '没有当前曲目时由 provider 的闭包决定不落库，notifier 只如实上报 null',
    );
  });

  test('binding no song resets to zero without reading the store', () async {
    var loads = 0;
    final notifier = LyricsOffsetNotifier(
      initial: const Duration(milliseconds: 750),
      load: (_) async {
        loads++;
        return const Duration(milliseconds: 750);
      },
    );
    addTearDown(notifier.dispose);

    await notifier.bindSong(null);

    expect(loads, 0);
    expect(notifier.songKey, isNull);
    expect(notifier.state, Duration.zero);
  });

  test('clamps an out-of-range saved offset', () async {
    final notifier = LyricsOffsetNotifier(
      load: (_) async => const Duration(seconds: 30),
    );
    addTearDown(notifier.dispose);

    await notifier.bindSong('netease:c');

    expect(notifier.state, maxLyricsOffset);
  });

  test('a failing load leaves the offset at zero instead of throwing', () async {
    final notifier = LyricsOffsetNotifier(
      load: (_) async => throw StateError('db closed'),
      initial: const Duration(milliseconds: 750),
    );
    addTearDown(notifier.dispose);

    await notifier.bindSong('netease:d');

    expect(
      notifier.state,
      Duration.zero,
      reason: '读库失败时不能退回上一首的偏移，也不能把异常抛进界面',
    );
  });
}

Song _song(String id, PlatformType platform) => Song(
  id: id,
  platform: platform,
  name: 'song-$id',
  artists: const [Artist(id: 'artist', name: 'artist')],
);
