import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/discovery/presentation/providers/recommendations_provider.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/playlist.dart';
import 'package:mconnect/models/recommendation_source.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/models/user.dart';
import 'package:mconnect/core/storage/session_storage.dart';
import 'package:mconnect/platform/base/music_platform.dart';

void main() {
  test(
    'daily recommendations query only platforms that advertise support',
    () async {
      final queried = <PlatformType>[];
      RecommendationsNotifier build() => RecommendationsNotifier(
        supportedTypes: const [
          PlatformType.netease,
          PlatformType.qq,
          PlatformType.kugou,
        ],
        platformResolver: (platform) => _FakeRecommendationPlatform(
          platform: platform,
          // Only 网易云 advertises the capability in this fixture.
          supportsDaily: platform == PlatformType.netease,
          songs: [_song('${platform.name}-1', platform)],
          onLoad: () => queried.add(platform),
        ),
      );

      final notifier = build();
      await notifier.loadRecommendations();

      expect(queried, [PlatformType.netease]);
      expect(notifier.state.songsByPlatform.keys, [PlatformType.netease]);
      expect(notifier.state.songsForPlatform(PlatformType.qq), isEmpty);
      expect(notifier.state.songsForPlatform(PlatformType.kugou), isEmpty);
    },
  );

  test(
    'daily recommendations load every platform that advertises support',
    () async {
      final notifier = RecommendationsNotifier(
        supportedTypes: const [
          PlatformType.netease,
          PlatformType.qq,
          PlatformType.kugou,
        ],
        platformResolver: (platform) => _FakeRecommendationPlatform(
          platform: platform,
          supportsDaily: true,
          songs: [_song('${platform.name}-1', platform)],
        ),
      );

      await notifier.loadRecommendations();

      expect(
        notifier.state.songsByPlatform.keys,
        containsAll(<PlatformType>[
          PlatformType.netease,
          PlatformType.qq,
          PlatformType.kugou,
        ]),
      );
      expect(notifier.state.songsForPlatform(PlatformType.qq), hasLength(1));
      expect(notifier.state.songsForPlatform(PlatformType.kugou), hasLength(1));
    },
  );

  test('daily recommendations expose each platform source', () async {
    final notifier = RecommendationsNotifier(
      supportedTypes: const [PlatformType.qq, PlatformType.kugou],
      platformResolver: (platform) => _FakeRecommendationPlatform(
        platform: platform,
        supportsDaily: true,
        songs: [_song('${platform.name}-1', platform)],
        source: RecommendationSource(
          platform: platform,
          kind: platform == PlatformType.qq
              ? RecommendationKind.personalPrivate
              : RecommendationKind.fallbackHomepage,
          label: platform == PlatformType.qq ? '今日私享' : '酷狗推荐',
          note: platform == PlatformType.kugou ? '官方推荐接口不可用，已回退首页推荐' : null,
        ),
      ),
    );

    await notifier.loadRecommendations();

    final qq = notifier.state.sourceForPlatform(PlatformType.qq);
    expect(qq, isNotNull);
    expect(qq!.kind, RecommendationKind.personalPrivate);
    expect(qq.isPersonalized, isTrue);
    expect(qq.label, '今日私享');

    final kugou = notifier.state.sourceForPlatform(PlatformType.kugou);
    expect(kugou, isNotNull);
    expect(kugou!.kind, RecommendationKind.fallbackHomepage);
    expect(kugou.isPersonalized, isFalse);
    expect(kugou.note, isNotNull);
  });

  test(
    'a timed-out platform is reported as unavailable without hiding others',
    () async {
      final hanging = Completer<List<Song>>();
      final notifier = RecommendationsNotifier(
        supportedTypes: const [PlatformType.netease, PlatformType.qq],
        operationTimeout: const Duration(milliseconds: 40),
        platformResolver: (platform) {
          if (platform == PlatformType.netease) {
            return _FakeRecommendationPlatform(
              platform: platform,
              supportsDaily: true,
              completer: hanging,
            );
          }
          return _FakeRecommendationPlatform(
            platform: platform,
            supportsDaily: true,
            songs: [_song('qq-1', platform)],
          );
        },
      );

      await notifier.loadRecommendations();

      // The healthy platform still renders.
      expect(
        notifier.state.songsForPlatform(PlatformType.qq),
        hasLength(1),
      );
      expect(
        notifier.state.errorsByPlatform[PlatformType.netease],
        contains('timeout'),
      );
      final neteaseSource = notifier.state.sourceForPlatform(
        PlatformType.netease,
      );
      expect(neteaseSource, isNotNull);
      expect(neteaseSource!.kind, RecommendationKind.unavailable);
      expect(notifier.state.error, isNull);
    },
  );

  test('daily recommendations ignore unsupported platform failures', () async {
    final notifier = RecommendationsNotifier(
      supportedTypes: const [PlatformType.netease, PlatformType.qq],
      platformResolver: (platform) {
        if (platform == PlatformType.netease) {
          return _FakeRecommendationPlatform(
            platform: platform,
            supportsDaily: true,
            songs: [_song('netease-1', platform)],
          );
        }
        // QQ does not advertise support, so it must not be queried at all.
        return _FakeRecommendationPlatform(
          platform: platform,
          supportsDaily: false,
          error: StateError('qq failed'),
        );
      },
    );

    await notifier.loadRecommendations();

    expect(notifier.state.error, isNull);
    expect(
      notifier.state.songsForPlatform(PlatformType.netease),
      hasLength(1),
    );
    expect(notifier.state.songsForPlatform(PlatformType.qq), isEmpty);
    expect(notifier.state.errorsByPlatform[PlatformType.qq], isNull);
  });

  test(
    'daily recommendations report login required only when nothing is produced',
    () async {
      final notifier = RecommendationsNotifier(
        supportedTypes: const [PlatformType.netease, PlatformType.qq],
        platformResolver: (platform) => _FakeRecommendationPlatform(
          platform: platform,
          supportsDaily: true,
          loggedIn: false,
        ),
      );

      await notifier.loadRecommendations();

      expect(notifier.state.songsByPlatform, isEmpty);
      expect(notifier.state.error, '请先登录平台账号');
    },
  );

  test(
    'daily recommendations keep a logged-in platform visible when it returns no songs',
    () async {
      final notifier = RecommendationsNotifier(
        supportedTypes: const [PlatformType.netease, PlatformType.qq],
        platformResolver: (platform) => _FakeRecommendationPlatform(
          platform: platform,
          supportsDaily: true,
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
    'daily recommendations keep a logged-in platform visible when it fails',
    () async {
      final notifier = RecommendationsNotifier(
        supportedTypes: const [PlatformType.netease],
        platformResolver: (platform) => _FakeRecommendationPlatform(
          platform: platform,
          supportsDaily: true,
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

class _FakeRecommendationPlatform extends MusicPlatform {
  final PlatformType platform;
  final bool loggedIn;
  final bool supportsDaily;
  final List<Song> songs;
  final RecommendationSource? source;
  final Object? error;
  final Completer<List<Song>>? completer;
  final void Function()? onLoad;

  _FakeRecommendationPlatform({
    required this.platform,
    this.loggedIn = true,
    this.supportsDaily = true,
    this.songs = const [],
    this.source,
    this.error,
    this.completer,
    this.onLoad,
  });

  @override
  PlatformType get platformType => platform;

  @override
  String get platformName => platform.name;

  @override
  bool get isLoggedIn => loggedIn;

  @override
  bool get supportsDailyRecommendations => supportsDaily;

  @override
  Future<List<Song>> getDailyRecommendations() async {
    onLoad?.call();
    final failure = error;
    if (failure != null) throw failure;
    final pending = completer;
    if (pending != null) return pending.future;
    return songs;
  }

  @override
  Future<RecommendationResult> getDailyRecommendation() async {
    final loaded = await getDailyRecommendations();
    return RecommendationResult(songs: loaded, source: source);
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
