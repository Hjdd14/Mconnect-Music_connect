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
