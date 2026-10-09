import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/player/presentation/widgets/playlist_picker_sheet.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/playlist.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/models/user.dart';
import 'package:mconnect/core/storage/session_storage.dart';
import 'package:mconnect/platform/base/music_platform.dart';
import 'package:mconnect/platform/base/platform_registry.dart';

void main() {
  testWidgets('playlist picker times out instead of spinning forever', (tester) async {
    PlatformRegistry.register(
      _FakePlaylistPlatform(
        loadCompleter: Completer<List<Playlist>>(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaylistPickerSheet(
            song: _song,
            operationTimeout: const Duration(milliseconds: 20),
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 30));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('加载歌单失败'), findsOneWidget);
  });

  testWidgets('playlist picker restores tap state when add operation times out', (tester) async {
    PlatformRegistry.register(
      _FakePlaylistPlatform(
        playlists: const [
          Playlist(id: 'p1', name: '歌单 1', platform: PlatformType.netease),
        ],
        addCompleter: Completer<bool>(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaylistPickerSheet(
            song: _song,
            operationTimeout: const Duration(milliseconds: 20),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('歌单 1'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    await tester.pump(const Duration(milliseconds: 30));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.widget<ListTile>(find.widgetWithText(ListTile, '歌单 1')).enabled, isTrue);
    expect(find.text('添加失败或请求超时，请重试'), findsOneWidget);
  });

  testWidgets(
    'add targets the PLAYLIST platform, not the song platform',
    (tester) async {
      // 真实缺陷（本会话查到的）：picker 用 `widget.song.platform` 取适配器。
      // 于是一首**网易云**的歌加进 **QQ 歌单**时，请求被发去网易云、还带着一个
      // QQ 的歌单 id —— 必然失败。聚合器的意义正是跨平台加歌，所以这里必须是
      // 「目标歌单所属平台」。
      final qq = _FakePlaylistPlatform(
        platformType: PlatformType.qq,
        playlists: const [
          Playlist(id: 'qq-diss', name: 'QQ 歌单', platform: PlatformType.qq),
        ],
      );
      final netease = _FakePlaylistPlatform(
        platformType: PlatformType.netease,
        playlists: const [],
      );
      PlatformRegistry.register(qq);
      PlatformRegistry.register(netease);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaylistPickerSheet(
              song: _song, // 网易云的歌
              operationTimeout: const Duration(milliseconds: 200),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('QQ 歌单'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        qq.addCalls,
        hasLength(1),
        reason: 'QQ 歌单必须由 QQ 适配器处理（修前这里会是 0，请求跑去网易云）',
      );
      expect(qq.addCalls.single.playlistId, 'qq-diss');
      expect(qq.addCalls.single.songId, 's1');
      expect(
        netease.addCalls,
        isEmpty,
        reason: '不得把 QQ 的歌单 id 发给网易云',
      );
    },
  );
}

const _song = Song(
  id: 's1',
  platform: PlatformType.netease,
  name: '歌曲 1',
  artists: [Artist(id: 'a1', name: '歌手 1')],
);

class _FakePlaylistPlatform extends MusicPlatform {
  final List<Playlist> playlists;
  final Completer<List<Playlist>>? loadCompleter;
  final Completer<bool>? addCompleter;

  /// Which platform this fake stands in for. The registry is keyed by
  /// `platformType`, so `addSongToPlaylist` being called on the *right* fake is
  /// exactly the property under test.
  final PlatformType _type;

  /// Every add call this fake received, so a test can assert who was asked.
  final List<({String playlistId, String songId})> addCalls = [];

  _FakePlaylistPlatform({
    this.playlists = const [],
    this.loadCompleter,
    this.addCompleter,
    PlatformType platformType = PlatformType.netease,
  }) : _type = platformType;

  @override
  PlatformType get platformType => _type;

  @override
  String get platformName => 'fake-${_type.name}';

  @override
  bool get isLoggedIn => true;

  @override
  Future<List<Playlist>> getUserPlaylists() async {
    final completer = loadCompleter;
    if (completer != null) return completer.future;
    return playlists;
  }

  @override
  Future<bool> addSongToPlaylist(String playlistId, Song song) async {
    addCalls.add((playlistId: playlistId, songId: song.id));
    final completer = addCompleter;
    if (completer != null) return completer.future;
    return true;
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
  Future<LoginResult> loginByPhone(String phone, String code) => throw UnimplementedError();

  @override
  Future<LoginResult> sendPhoneCode(String phone) async =>
      const LoginResult(success: false, error: 'unsupported');

  @override
  Future<User?> getUserInfo() async => null;

  @override
  Future<void> logout() async {}

  @override
  Future<List<Song>> search(String keyword, {int page = 1, int limit = 30}) async => const [];

  @override
  Future<List<Playlist>> searchPlaylists(String keyword, {int page = 1, int limit = 30}) async => const [];

  @override
  Future<String> getSongUrl(String songId, {AudioLevel quality = AudioLevel.low}) async => '';

  @override
  Future<List<AudioQuality>> getAvailableQualities(String songId) async => const [];

  @override
  Future<String?> getLyrics(String songId) async => null;

  @override
  Future<List<Song>> getPlaylistDetail(String playlistId) async => const [];

  @override
  Future<List<Song>> getLikedSongs() async => const [];

  @override
  Future<bool> likeSong(String songId, {bool like = true}) async => false;

  @override
  Future<Playlist?> createPlaylist(String name) async => null;

  @override
  Future<bool> collectPlaylist(String playlistId, {bool collect = true}) async => false;

  @override
  Future<List<Song>> getDailyRecommendations() async => const [];

  @override
  Future<List<Song>> getRankingList() async => const [];

  @override
  Future<VipLevel> getVipStatus() async => VipLevel.free;

  @override
  Future<Playlist?> parseShareLink(String url) async => null;
}
