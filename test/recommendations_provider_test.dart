import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/discovery/presentation/providers/recommendations_provider.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/playlist.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/models/user.dart';
import 'package:mconnect/core/storage/session_storage.dart';
import 'package:mconnect/platform/base/music_platform.dart';

void main() {
  test(
    'daily recommendations load only verified NetEase daily platform',
    () async {
      final calls = <PlatformType>[];
      final notifier = RecommendationsNotifier(
        supportedTypes: const [
          PlatformType.netease,
          PlatformType.qq,
          PlatformType.kugou,
        ],
        platformResolver: (platform) {
          calls.add(platform);
          return _FakeRecommendationPlatform(
            platform: platform,
            songs: [_song('${platform.name}-1', platform)],
          );
        },
      );

      await notifier.loadRecommendations();

      expect(calls, [PlatformType.netease]);
      expect(notifier.state.songsByPlatform.keys, [PlatformType.netease]);
      expect(notifier.state.songsForPlatform(PlatformType.qq), isEmpty);
      expect(notifier.state.songsForPlatform(PlatformType.kugou), isEmpty);
    },
  );

  test('daily recommendations ignore unsupported platform failures', () async {
    final notifier = RecommendationsNotifier(
      supportedTypes: const [PlatformType.netease, PlatformType.qq],
      platformResolver: (platform) {
        if (platform == PlatformType.netease) {
          return _FakeRecommendationPlatform(
            platform: platform,
            songs: [_song('netease-1', platform)],
          );
        }
        return _FakeRecommendationPlatform(
          platform: platform,
          error: StateError('qq failed'),
        );
      },
    );

    await notifier.loadRecommendations();

    expect(notifier.state.error, isNull);
    expect(notifier.state.songsForPlatform(PlatformType.netease), hasLength(1));
    expect(notifier.state.songsForPlatform(PlatformType.qq), isEmpty);
    expect(notifier.state.errorsByPlatform[PlatformType.qq], isNull);
  });

  test(
    'daily recommendations report login required only when no platforms are logged in',
    () async {
      final notifier = RecommendationsNotifier(
        supportedTypes: const [PlatformType.netease, PlatformType.qq],
        platformResolver: (platform) =>
            _FakeRecommendationPlatform(platform: platform, loggedIn: false),
      );

      await notifier.loadRecommendations();

      expect(notifier.state.songsByPlatform, isEmpty);
      expect(notifier.state.error, '请先登录平台账号');
    },
  );

  test(
    'daily recommendations do not expose QQ results when NetEase hangs',
    () async {
      final hanging = Completer<List<Song>>();
      final notifier = RecommendationsNotifier(
        supportedTypes: const [PlatformType.netease, PlatformType.qq],
        operationTimeout: const Duration(milliseconds: 40),
        platformResolver: (platform) {
          if (platform == PlatformType.netease) {
            return _FakeRecommendationPlatform(
              platform: platform,
              completer: hanging,
            );
          }
          return _FakeRecommendationPlatform(
            platform: platform,
            songs: [_song('qq-1', platform)],
          );
        },
      );

      await notifier.loadRecommendations();

      expect(notifier.state.songsForPlatform(PlatformType.qq), isEmpty);
      expect(
        notifier.state.errorsByPlatform[PlatformType.netease],
        contains('timeout'),
      );
      expect(notifier.state.error, isNull);
    },
  );

  test(
    'daily recommendations keep logged-in NetEase visible when it returns no songs',
    () async {
      final notifier = RecommendationsNotifier(
        supportedTypes: const [PlatformType.netease, PlatformType.qq],
        platformResolver: (platform) => _FakeRecommendationPlatform(
          platform: platform,
          loggedIn: platform == PlatformType.netease,
          songs: const [],
        ),
      );

      await notifier.loadRecommendations();

      expect(
        notifier.state.songsByPlatform.containsKey(PlatformType.netease),
        isTrue,
      );
      expect(
        notifier.state.songsByPlatform.containsKey(PlatformType.qq),
        isFalse,
      );
      expect(notifier.state.error, isNull);
    },
  );

  test(
    'daily recommendations keep logged-in NetEase visible when it fails',
    () async {
      final notifier = RecommendationsNotifier(
        supportedTypes: const [PlatformType.netease],
        platformResolver: (platform) => _FakeRecommendationPlatform(
          platform: platform,
          error: StateError('daily api failed'),
        ),
      );

      await notifier.loadRecommendations();

      expect(
        notifier.state.songsByPlatform.containsKey(PlatformType.netease),
        isTrue,
      );
      expect(
        notifier.state.errorsByPlatform[PlatformType.netease],
        contains('daily api failed'),
      );
      expect(notifier.state.error, isNull);
    },
  );
}

Song _song(String id, PlatformType platform) => Song(
  id: id,
  platform: platform,
  name: id,
  artists: const [Artist(id: 'artist', name: 'artist')],
);

class _FakeRecommendationPlatform implements MusicPlatform {
  final PlatformType platform;
  final bool loggedIn;
  final List<Song> songs;
  final Object? error;
  final Completer<List<Song>>? completer;

  _FakeRecommendationPlatform({
    required this.platform,
    this.loggedIn = true,
    this.songs = const [],
    this.error,
    this.completer,
  });

  @override
  PlatformType get platformType => platform;

  @override
  String get platformName => platform.name;

  @override
  bool get isLoggedIn => loggedIn;

  @override
  Future<List<Song>> getDailyRecommendations() async {
    final failure = error;
    if (failure != null) throw failure;
    final pending = completer;
    if (pending != null) return pending.future;
    return songs;
  }

  @override
  Future<void> saveSession(SessionStorage storage) async {}

  @override
  Future<void> restoreSession(SessionStorage storage) async {}

  @override
  Future<QrLoginResult> getQrCode() {
    throw UnimplementedError();
  }

  @override
  Stream<QrLoginStatus> pollQrStatus(String key) {
    throw UnimplementedError();
  }

  @override
  Future<LoginResult> loginByPhone(String phone, String code) {
    throw UnimplementedError();
  }

  @override
  Future<LoginResult> sendPhoneCode(String phone) async =>
      const LoginResult(success: false, error: 'unsupported');

  @override
  Future<User?> getUserInfo() async => null;

  @override
  Future<void> logout() async {}

  @override
  Future<List<Song>> search(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async => const [];

  @override
  Future<List<Playlist>> searchPlaylists(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async => const [];

  @override
  Future<String> getSongUrl(
    String songId, {
    AudioLevel quality = AudioLevel.low,
  }) async => '';

  @override
  Future<List<AudioQuality>> getAvailableQualities(String songId) async =>
      const [];

  @override
  Future<String?> getLyrics(String songId) async => null;

  @override
  Future<List<Playlist>> getUserPlaylists() async => const [];

  @override
  Future<List<Song>> getPlaylistDetail(String playlistId) async => const [];

  @override
  Future<List<Song>> getLikedSongs() async => const [];

  @override
  Future<bool> likeSong(String songId, {bool like = true}) async => false;

  @override
  Future<bool> addSongToPlaylist(String playlistId, Song song) async => false;

  @override
  Future<Playlist?> createPlaylist(String name) async => null;

  @override
  Future<bool> collectPlaylist(
    String playlistId, {
    bool collect = true,
  }) async => false;

  @override
  Future<List<Song>> getRankingList() async => const [];

  @override
  Future<VipLevel> getVipStatus() async => VipLevel.free;

  @override
  Future<Playlist?> parseShareLink(String url) async => null;
}
