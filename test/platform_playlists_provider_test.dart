import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/storage/session_storage.dart';
import 'package:mconnect/features/library/presentation/providers/platform_playlists_provider.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/playlist.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/models/user.dart';
import 'package:mconnect/platform/base/music_platform.dart';

void main() {
  test(
    'playlist loading publishes fast platforms while another platform is still pending',
    () async {
      final hangingLoad = Completer<List<Playlist>>();
      final notifier = PlatformPlaylistsNotifier(
        supportedTypes: const [PlatformType.netease, PlatformType.qq],
        platformResolver: (platform) {
          if (platform == PlatformType.netease) {
            return _FakePlaylistPlatform(
              platform: platform,
              playlists: const [
                Playlist(
                  id: 'p1',
                  name: '歌单 1',
                  platform: PlatformType.netease,
                ),
              ],
            );
          }
          return _FakePlaylistPlatform(
            platform: platform,
            loadCompleter: hangingLoad,
          );
        },
        operationTimeout: const Duration(milliseconds: 40),
      );

      final loadFuture = notifier.load();
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(notifier.state.playlistsFor(PlatformType.netease), hasLength(1));
      expect(notifier.state.isLoadingFor(PlatformType.netease), isFalse);
      expect(notifier.state.isLoadingFor(PlatformType.qq), isTrue);

      await loadFuture;

      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.playlistsFor(PlatformType.netease), hasLength(1));
      expect(notifier.state.errorsByPlatform[PlatformType.qq], contains('超时'));
    },
  );

  test('create rejects playlists without a routeable id', () async {
    final notifier = PlatformPlaylistsNotifier(
      supportedTypes: const [PlatformType.kugou],
      platformResolver: (_) => _FakePlaylistPlatform(
        platform: PlatformType.kugou,
        createdPlaylist: const Playlist(
          id: '',
          name: '12',
          platform: PlatformType.kugou,
          editable: true,
        ),
      ),
      operationTimeout: const Duration(milliseconds: 40),
    );

    final playlist = await notifier.create(PlatformType.kugou, '12');

    expect(playlist, isNull);
    expect(notifier.state.playlistsFor(PlatformType.kugou), isEmpty);
    expect(
      notifier.state.errorsByPlatform[PlatformType.kugou],
      contains('新建歌单失败'),
    );
  });
}

class _FakePlaylistPlatform implements MusicPlatform {
  final PlatformType platform;
  final List<Playlist> playlists;
  final Completer<List<Playlist>>? loadCompleter;
  final Playlist? createdPlaylist;

  _FakePlaylistPlatform({
    required this.platform,
    this.playlists = const [],
    this.loadCompleter,
    this.createdPlaylist,
  });

  @override
  PlatformType get platformType => platform;

  @override
  String get platformName => platform.displayName;

  @override
  bool get isLoggedIn => true;

  @override
  Future<List<Playlist>> getUserPlaylists() async {
    final completer = loadCompleter;
    if (completer != null) return completer.future;
    return playlists;
  }

  @override
  Future<void> saveSession(SessionStorage storage) async {}

  @override
  Future<void> restoreSession(SessionStorage storage) async {}

  @override
  Future<QrLoginResult> getQrCode() => throw UnimplementedError();

  @override
  Stream<QrLoginStatus> pollQrStatus(String key) => throw UnimplementedError();

  @override
  Future<LoginResult> loginByPhone(String phone, String code) =>
      throw UnimplementedError();

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
  Future<List<Song>> getPlaylistDetail(String playlistId) async => const [];

  @override
  Future<List<Song>> getLikedSongs() async => const [];

  @override
  Future<bool> likeSong(String songId, {bool like = true}) async => false;

  @override
  Future<bool> addSongToPlaylist(String playlistId, Song song) async => false;

  @override
  Future<Playlist?> createPlaylist(String name) async => createdPlaylist;

  @override
  Future<bool> collectPlaylist(
    String playlistId, {
    bool collect = true,
  }) async => false;

  @override
  Future<List<Song>> getDailyRecommendations() async => const [];

  @override
  Future<List<Song>> getRankingList() async => const [];

  @override
  Future<VipLevel> getVipStatus() async => VipLevel.free;

  @override
  Future<Playlist?> parseShareLink(String url) async => null;
}
