import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/storage/session_storage.dart';
import 'package:mconnect/features/download/data/download_directory_service.dart';
import 'package:mconnect/features/download/data/download_task_store.dart';
import 'package:mconnect/features/download/data/repositories/download_manager.dart';
import 'package:mconnect/features/download/domain/entities/download_task.dart';
import 'package:mconnect/features/download/presentation/providers/download_provider.dart';
import 'package:mconnect/features/download/presentation/widgets/download_button.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/playlist.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/models/user.dart';
import 'package:mconnect/platform/base/music_platform.dart';
import 'package:mconnect/platform/base/platform_registry.dart';

void main() {
  testWidgets(
    'download quality picker shows platform-specific advanced qualities',
    (tester) async {
      PlatformRegistry.register(_FakeQualityPlatform());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: DownloadButton(song: _qqSong)),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.file_download_outlined));
      await tester.pumpAndSettle();

      expect(find.text('SQ无损品质'), findsOneWidget);
      expect(find.text('Hi-Res'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('臻品全景声2.0'),
        160,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('臻品全景声2.0'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('臻品母带2.0'),
        160,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('臻品母带2.0'), findsOneWidget);
    },
  );

  testWidgets('long-press adds the song to the offline cache queue', (
    tester,
  ) async {
    // `cacheSongs` had no caller anywhere in `lib/`, so the offline-cache queue
    // could never be filled from the UI. The long press is that entry point.
    PlatformRegistry.register(_FakeQualityPlatform());
    final manager = _RecordingDownloadManager();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          downloadProvider.overrideWith(
            (ref) => DownloadNotifier(
              manager: manager,
              taskStore: _MemoryDownloadTaskStore([]),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: DownloadButton(song: _qqSong)),
        ),
      ),
    );
    await tester.pump();

    await tester.longPress(find.byIcon(Icons.file_download_outlined));
    await tester.pump();
    await tester.pump();

    expect(manager.started, ['qq_mid1_low_cache']);
    expect(find.text('已加入离线缓存：歌曲 1'), findsOneWidget);
  });

  testWidgets('a tap still opens the quality picker', (tester) async {
    PlatformRegistry.register(_FakeQualityPlatform());
    final manager = _RecordingDownloadManager();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          downloadProvider.overrideWith(
            (ref) => DownloadNotifier(
              manager: manager,
              taskStore: _MemoryDownloadTaskStore([]),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: DownloadButton(song: _qqSong)),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.file_download_outlined));
    await tester.pumpAndSettle();

    expect(find.text('选择下载音质 - 歌曲 1'), findsOneWidget);
    expect(manager.started, isEmpty);
  });
}

class _RecordingDownloadManager extends DownloadManager {
  _RecordingDownloadManager()
    : super(
        directoryService: DownloadDirectoryService(
          store: _MemoryDownloadDirectoryStore(),
          defaultRootProvider: () async => throw UnimplementedError(),
        ),
      );

  final List<String> started = <String>[];

  @override
  Stream<DownloadProgress> download(DownloadTask task) {
    started.add(task.id);
    return const Stream<DownloadProgress>.empty();
  }
}

class _MemoryDownloadDirectoryStore implements DownloadDirectoryStore {
  String? customRootPath;

  @override
  Future<void> clearCustomRootPath() async {
    customRootPath = null;
  }

  @override
  Future<String?> readCustomRootPath() async => customRootPath;

  @override
  Future<void> saveCustomRootPath(String path) async {
    customRootPath = path;
  }
}

class _MemoryDownloadTaskStore implements DownloadTaskStore {
  List<DownloadTask> tasks;

  _MemoryDownloadTaskStore(this.tasks);

  @override
  Future<List<DownloadTask>> load() async => tasks;

  @override
  Future<void> save(List<DownloadTask> tasks) async {
    this.tasks = List<DownloadTask>.from(tasks);
  }
}

const _qqSong = Song(
  id: 'mid1',
  platform: PlatformType.qq,
  name: '歌曲 1',
  artists: [Artist(id: 'a1', name: '歌手 1')],
);

class _FakeQualityPlatform extends MusicPlatform {
  @override
  PlatformType get platformType => PlatformType.qq;

  @override
  String get platformName => 'fake qq';

  @override
  bool get isLoggedIn => true;

  @override
  Future<List<AudioQuality>> getAvailableQualities(String songId) async {
    return const [
      AudioQuality(level: AudioLevel.low, bitrate: 128000, format: 'mp3'),
      AudioQuality(level: AudioLevel.medium, bitrate: 320000, format: 'mp3'),
      AudioQuality(level: AudioLevel.lossless, bitrate: 999000, format: 'flac'),
      AudioQuality(level: AudioLevel.hires, bitrate: 2400000, format: 'flac'),
      AudioQuality(level: AudioLevel.spatial, bitrate: 999000, format: 'flac'),
      AudioQuality(level: AudioLevel.master, bitrate: 999000, format: 'flac'),
    ];
  }

  @override
  Future<VipLevel> getVipStatus() async => VipLevel.svip;

  @override
  Future<String> getSongUrl(
    String songId, {
    AudioLevel quality = AudioLevel.low,
  }) async => '';

  @override
  Future<void> saveSession(SessionStorage storage) async {}

  @override
  Future<void> restoreSession(SessionStorage storage) async {}

  @override
  Future<QrLoginResult> getQrCode() => throw UnimplementedError();

  @override
  Stream<QrLoginStatus> pollQrStatus(String key) => throw UnimplementedError();

  @override
  Future<LoginResult> sendPhoneCode(String phone) async =>
      const LoginResult(success: false, error: 'unsupported');

  @override
  Future<LoginResult> loginByPhone(String phone, String code) =>
      throw UnimplementedError();

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
  Future<String?> getLyrics(String songId) async => null;

  @override
  Future<List<Playlist>> getUserPlaylists() async => const [];

  @override
  Future<bool> addSongToPlaylist(String playlistId, Song song) async => false;

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
  Future<Playlist?> parseShareLink(String url) async => null;
}
