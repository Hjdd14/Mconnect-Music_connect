import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/player/presentation/providers/lyrics_provider.dart';
import 'package:mconnect/lyrics/models/lyrics_line.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/playlist.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/models/user.dart';
import 'package:mconnect/platform/base/music_platform.dart';

/// 歌词容错回归（任务 WS-E 批次1 第 1/6 项）：
/// * 请求必须有超时（以前全 App 唯一没有超时的关键请求，平台挂起即永久 spinner）；
/// * 全部来源都失败 → 抛 [LyricsUnavailableException]，与"平台答没有歌词"
///   （返回 null）区分，`lyrics_display.dart` 的"歌词加载失败"分支才可达；
/// * 本平台没歌词时跨源回退；
/// * 缓存写失败不得连带丢掉已取回的歌词。
void main() {
  final song = _song('netease-1', name: '晚风', duration: const Duration(seconds: 240));

  test('resolves lyrics from the song owning platform', () async {
    final netease = _FakeLyricsPlatform(
      PlatformType.netease,
      lyrics: {'netease-1': '[00:01.00]晚风'},
    );

    final document = await resolveLyricsForSong(
      song: song,
      platforms: [netease],
    );

    expect(document, isNotNull);
    expect(document!.lines.single.text, '晚风');
    expect(document.format, LyricsFormat.lrc);
  });

  test('times out a hanging platform instead of spinning forever', () async {
    final hanging = _FakeLyricsPlatform(PlatformType.netease, hang: true);

    await expectLater(
      resolveLyricsForSong(
        song: song,
        platforms: [hanging],
        timeout: const Duration(milliseconds: 30),
      ).timeout(const Duration(seconds: 2)),
      throwsA(isA<LyricsUnavailableException>()),
    );
  });

  test('falls back to another platform when the owner has no lyrics', () async {
    final netease = _FakeLyricsPlatform(
      PlatformType.netease,
      // 本平台明确回答"没有歌词"。
      lyrics: const {},
    );
    final qq = _FakeLyricsPlatform(
      PlatformType.qq,
      lyrics: {'qq-9': '[00:02.00]晚风（QQ 版）'},
      searchResults: [_song('qq-9', name: '晚风', duration: const Duration(seconds: 240))],
    );

    final document = await resolveLyricsForSong(
      song: song,
      platforms: [netease, qq],
    );

    expect(document, isNotNull);
    expect(document!.lines.single.text, '晚风（QQ 版）');
    expect(qq.searchedKeywords, isNotEmpty);
    expect(qq.requestedLyrics, ['qq-9']);
  });

  test('surfaces a distinguishable failure when every source errors', () async {
    final netease = _FakeLyricsPlatform(
      PlatformType.netease,
      failing: true,
    );
    final qq = _FakeLyricsPlatform(PlatformType.qq, failing: true);
    qq.searchResults = [_song('qq-1', name: '晚风')];

    await expectLater(
      resolveLyricsForSong(song: song, platforms: [netease, qq]),
      throwsA(isA<LyricsUnavailableException>()),
    );
  });

  test('returns null (no lyrics) when every source answered empty', () async {
    final netease = _FakeLyricsPlatform(PlatformType.netease, lyrics: const {});

    final document = await resolveLyricsForSong(
      song: song,
      platforms: [netease],
    );

    expect(document, isNull);
  });

  test('a Kugou LRC carrying "<" and "," is not misdetected as KRC', () async {
    // Sniffing on `[` + `<` + `,` alone used to send ordinary LRC to the KRC
    // parser, which found no `[start,duration]` line and returned "暂无歌词"
    // for the whole song.
    const raw = '[00:01.00]你好 <3\n[00:03.00]a, b';
    final kugou = _FakeLyricsPlatform(
      PlatformType.kugou,
      lyrics: {'kugou-1': raw},
    );

    final document = await resolveLyricsForSong(
      song: _song('kugou-1', platform: PlatformType.kugou),
      platforms: [kugou],
    );

    expect(document, isNotNull);
    expect(document!.format, LyricsFormat.lrc);
    expect(document.lines.map((line) => line.text), ['你好 <3', 'a, b']);
  });

  test('a local .lrc carrying "<" and "," still parses', () async {
    const raw = '[00:01.00]你好 <3\n[00:03.00]a, b';

    final document = await resolveLyricsForSong(
      song: _song('local-1', platform: PlatformType.local),
      localRawLyrics: raw,
    );

    expect(document, isNotNull);
    expect(document!.format, LyricsFormat.lrc);
    expect(document.lines, hasLength(2));
  });

  test('a real KRC payload is still detected as KRC', () async {
    const raw = '[0,1200]<0,600,0>你<600,600,0>好';
    final kugou = _FakeLyricsPlatform(
      PlatformType.kugou,
      lyrics: {'kugou-2': raw},
    );

    final document = await resolveLyricsForSong(
      song: _song('kugou-2', platform: PlatformType.kugou),
      platforms: [kugou],
    );

    expect(document, isNotNull);
    expect(document!.format, LyricsFormat.krc);
    expect(document.lines.single.text, '你好');
  });

  test('a KRC payload with its real header tags is not downgraded to LRC', () async {
    // The single-line fixture above cannot prove this: it has no header block,
    // so the sniffing fallback would land on LRC and still look "fine" for many
    // shapes. Kugou always ships `[ti:]/[ar:]/[al:]/[offset:]/[language:]`
    // before the timed lines, and every one of those tags makes the *LRC*
    // candidate parse zero lines — which is exactly the case that must still
    // resolve to KRC rather than to an empty "暂无歌词".
    const raw =
        '[ti:测试歌]\n'
        '[ar:测试歌手]\n'
        '[al:测试专辑]\n'
        '[by:测试]\n'
        '[offset:0]\n'
        '[language:eyJjb250ZW50IjpbXX0=]\n'
        '[0,1200]<0,600,0>你<600,600,0>好\n'
        '[1200,1500]<0,500,0>再<500,500,0>见<500,500,0>了';
    final kugou = _FakeLyricsPlatform(
      PlatformType.kugou,
      lyrics: {'kugou-3': raw},
    );

    final document = await resolveLyricsForSong(
      song: _song('kugou-3', platform: PlatformType.kugou),
      platforms: [kugou],
    );

    expect(document, isNotNull);
    expect(document!.format, LyricsFormat.krc);
    expect(document.lines.map((line) => line.text), ['你好', '再见了']);
    expect(document.lines.first.timestamp, const Duration(milliseconds: 0));
    expect(document.lines.first.words, hasLength(2));
    expect(document.lines.last.words, hasLength(3));
  });

  test('reports which platform supplied the lyrics', () async {
    final kugou = _FakeLyricsPlatform(
      PlatformType.kugou,
      lyrics: {'kugou-4': '[00:01.00]来源歌'},
    );

    final document = await resolveLyricsForSong(
      song: _song('kugou-4', platform: PlatformType.kugou),
      platforms: [kugou],
    );

    // `RawLyrics.source` was written but never read: nothing could put a "来源"
    // badge on screen. The document has to carry it.
    expect(document!.source, LyricsSource.kugou);
  });

  test('a local document reports the local source', () async {
    final document = await resolveLyricsForSong(
      song: _song('local-2', platform: PlatformType.local),
      localRawLyrics: '[00:01.00]本地词',
    );

    expect(document!.source, LyricsSource.local);
  });

  test('keeps the fetched lyrics when the cache write fails', () async {
    final netease = _FakeLyricsPlatform(
      PlatformType.netease,
      lyrics: {'netease-1': '[00:01.00]晚风'},
    );

    final document = await resolveLyricsForSong(
      song: song,
      platforms: [netease],
      writeCache: (raw, format) async => throw StateError('disk full'),
    );
    await pumpEventQueue();

    expect(document, isNotNull);
    expect(document!.lines.single.text, '晚风');
  });

  test('serves the cached document without touching the network', () async {
    final netease = _FakeLyricsPlatform(
      PlatformType.netease,
      lyrics: {'netease-1': '[00:01.00]网络版'},
    );

    final document = await resolveLyricsForSong(
      song: song,
      platforms: [netease],
      cachedLyrics: (content: '[00:01.00]缓存版', format: 'lrc'),
    );

    expect(document!.lines.single.text, '缓存版');
    expect(netease.requestedLyrics, isEmpty);
  });

  // --- W2-A：LRCLIB 兜底（只在无词/时间轴明显错时触发）---------------------

  test('falls back to LRCLIB when every platform has no lyrics', () async {
    // 本平台明确回答"没有歌词"。
    final netease = _FakeLyricsPlatform(PlatformType.netease, lyrics: const {});

    final document = await resolveLyricsForSong(
      song: song,
      platforms: [netease],
      lrclib: (queried) async {
        expect(queried.id, song.id);
        return '[00:01.00]LRCLIB 版';
      },
    );

    expect(document, isNotNull);
    expect(document!.lines.single.text, 'LRCLIB 版');
    expect(document.source, LyricsSource.lrclib);
    expect(document.format, LyricsFormat.lrc);
  });

  test('does not ask LRCLIB when the platform lyrics are fine', () async {
    final netease = _FakeLyricsPlatform(
      PlatformType.netease,
      lyrics: {'netease-1': '[00:01.00]晚风\n[00:04.00]下一句'},
    );
    var asked = 0;

    final document = await resolveLyricsForSong(
      song: song,
      platforms: [netease],
      lrclib: (queried) async {
        asked++;
        return '[00:01.00]LRCLIB 版';
      },
    );

    expect(document!.lines.first.text, '晚风');
    expect(asked, 0, reason: '平台有词就不要多等一个网络往返');
  });

  test('asks LRCLIB when the platform timeline is obviously off', () async {
    // 歌长 240s，平台给的最后一行却落在 9 分钟：时间轴明显不对。
    final netease = _FakeLyricsPlatform(
      PlatformType.netease,
      lyrics: {'netease-1': '[09:00.00]明显错位的词'},
    );

    final document = await resolveLyricsForSong(
      song: song,
      platforms: [netease],
      lrclib: (queried) async => '[00:01.00]LRCLIB 修正版',
    );

    expect(document!.lines.single.text, 'LRCLIB 修正版');
    expect(document.source, LyricsSource.lrclib);
  });

  test('still reports a load failure when LRCLIB has nothing either', () async {
    final netease = _FakeLyricsPlatform(PlatformType.netease, failing: true);

    await expectLater(
      resolveLyricsForSong(
        song: song,
        platforms: [netease],
        lrclib: (queried) async => null,
      ),
      throwsA(isA<LyricsUnavailableException>()),
    );
  });

  test('a throwing LRCLIB never hides a usable platform result', () async {
    // 平台的词明显错位 → 真的会去问 LRCLIB → 它抛了 → 仍必须回退到平台的词，
    // 既不能抛出去，也不能变成"暂无歌词"。
    final netease = _FakeLyricsPlatform(
      PlatformType.netease,
      lyrics: {'netease-1': '[09:00.00]平台的词（时间轴偏）'},
    );

    final document = await resolveLyricsForSong(
      song: song,
      platforms: [netease],
      lrclib: (queried) async => throw StateError('lrclib down'),
    );

    expect(document, isNotNull);
    expect(document!.lines.single.text, '平台的词（时间轴偏）');
    expect(document.source, LyricsSource.netease);
  });

  test('a local song without any lyrics also gets the fallback', () async {
    var asked = 0;

    final document = await resolveLyricsForSong(
      song: _song('local-9', platform: PlatformType.local),
      localRawLyrics: null,
      lrclib: (queried) async {
        asked++;
        return '[00:01.00]LRCLIB 给本地曲目的词';
      },
    );

    expect(asked, 1);
    expect(document!.lines.single.text, 'LRCLIB 给本地曲目的词');
    expect(document.source, LyricsSource.lrclib);
  });

  test('a local song with usable lyrics never asks the fallback', () async {
    var asked = 0;

    final document = await resolveLyricsForSong(
      song: _song('local-10', platform: PlatformType.local),
      localRawLyrics: '[00:01.00]本地词',
      lrclib: (queried) async {
        asked++;
        return '[00:01.00]LRCLIB 版';
      },
    );

    expect(asked, 0);
    expect(document!.lines.single.text, '本地词');
    expect(document.source, LyricsSource.local);
  });
}

Song _song(
  String id, {
  String name = 'song',
  Duration duration = Duration.zero,
  PlatformType platform = PlatformType.netease,
}) => Song(
  id: id,
  platform: platform,
  name: name,
  duration: duration,
  artists: const [Artist(id: 'artist', name: 'artist')],
);

class _FakeLyricsPlatform extends MusicPlatform {
  @override
  final PlatformType platformType;
  final Map<String, String> lyrics;
  final bool failing;
  final bool hang;
  List<Song> searchResults;

  final List<String> requestedLyrics = [];
  final List<String> searchedKeywords = [];

  _FakeLyricsPlatform(
    this.platformType, {
    this.lyrics = const {},
    this.failing = false,
    this.hang = false,
    this.searchResults = const [],
  });

  @override
  String get platformName => platformType.name;

  @override
  bool get isLoggedIn => true;

  @override
  Future<String?> getLyrics(String songId) {
    requestedLyrics.add(songId);
    if (hang) return Completer<String?>().future;
    if (failing) return Future.error(StateError('lyrics request failed'));
    return Future.value(lyrics[songId]);
  }

  @override
  Future<List<Song>> search(String keyword, {int page = 1, int limit = 30}) {
    searchedKeywords.add(keyword);
    if (failing) return Future.error(StateError('search failed'));
    return Future.value(searchResults);
  }

  // --- 以下仅为满足 MusicPlatform 的抽象成员，歌词路径不使用 ---

  @override
  Future<String> getSongUrl(
    String songId, {
    AudioLevel quality = AudioLevel.low,
  }) async => 'https://example.test/$songId.mp3';

  @override
  Future<List<AudioQuality>> getAvailableQualities(String songId) async =>
      const [];

  @override
  Future<QrLoginResult> getQrCode() => throw UnimplementedError();

  @override
  Stream<QrLoginStatus> pollQrStatus(String key) => throw UnimplementedError();

  @override
  Future<LoginResult> loginByPhone(String phone, String code) =>
      throw UnimplementedError();

  @override
  Future<void> logout() async {}

  @override
  Future<User?> getUserInfo() async => null;

  @override
  Future<List<Playlist>> getUserPlaylists() async => const [];

  @override
  Future<List<Song>> getPlaylistDetail(String playlistId) async => const [];

  @override
  Future<List<Song>> getLikedSongs() async => const [];

  @override
  Future<bool> likeSong(String songId, {bool like = true}) async => false;

  @override
  Future<List<Song>> getDailyRecommendations() async => const [];

  @override
  Future<List<Song>> getRankingList() async => const [];

  @override
  Future<VipLevel> getVipStatus() async => VipLevel.free;

  @override
  Future<Playlist?> parseShareLink(String url) async => null;
}
