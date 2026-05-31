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
  testWidgets('playlist picker times out instead of spinning forever', (
    tester,
  ) async {
    PlatformRegistry.register(
      _FakePlaylistPlatform(loadCompleter: Completer<List<Playlist>>()),
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

  testWidgets(
    'playlist picker restores tap state when add operation times out',
    (tester) async {
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
      expect(
        tester.widget<ListTile>(find.widgetWithText(ListTile, '歌单 1')).enabled,
        isTrue,
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

class _FakePlaylistPlatform implements MusicPlatform {
  final List<Playlist> playlists;
  final Completer<List<Playlist>>? loadCompleter;
  final Completer<bool>? addCompleter;

  _FakePlaylistPlatform({
    this.playlists = const [],
    this.loadCompleter,
    this.addCompleter,
  });

  @override
  PlatformType get platformType => PlatformType.netease;

  @override
  String get platformName => 'fake';

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
  Future<Playlist?> createPlaylist(String name) async => null;

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
