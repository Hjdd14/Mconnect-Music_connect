import 'dart:async';

import 'package:mconnect/features/download/data/download_directory_service.dart';
import 'package:mconnect/features/download/data/download_task_store.dart';
import 'package:mconnect/features/download/data/repositories/download_manager.dart';
import 'package:mconnect/features/download/domain/entities/download_failure.dart';
import 'package:mconnect/features/download/domain/entities/download_task.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/playlist.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/models/user.dart';
import 'package:mconnect/platform/base/music_platform.dart';
import 'package:mconnect/core/storage/session_storage.dart';

class MemoryDownloadDirectoryStore implements DownloadDirectoryStore {
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

class MemoryDownloadTaskStore implements DownloadTaskStore {
  List<DownloadTask> tasks;
  final List<List<DownloadTask>> saved = [];

  MemoryDownloadTaskStore(this.tasks);

  @override
  Future<List<DownloadTask>> load() async => tasks;

  @override
  Future<void> save(List<DownloadTask> tasks) async {
    this.tasks = List<DownloadTask>.from(tasks);
    saved.add(List<DownloadTask>.from(tasks));
  }
}

/// A [DownloadManager] that never opens a socket.
///
/// Downloads are handed back as a controllable stream so a test can drive
/// progress, a typed failure, a pause, or a successful completion at will.
class FakeDownloadManager extends DownloadManager {
  FakeDownloadManager()
    : super(
        directoryService: DownloadDirectoryService(
          store: MemoryDownloadDirectoryStore(),
          defaultRootProvider: () async => throw UnimplementedError(),
        ),
      );

  /// Task ids handed to [download], in order.
  final List<String> started = <String>[];

  final Map<String, StreamController<DownloadProgress>> _controllers = {};

  int _running = 0;
  int _peak = 0;
  int pauseCalls = 0;
  int cancelCalls = 0;

  /// One-shot failure injected into the next started download.
  DownloadFailure? failNextWith;

  int get runningCount => _running;
  int get peakConcurrent => _peak;

  bool isRunning(String taskId) => _controllers.containsKey(taskId);

  @override
  Stream<DownloadProgress> download(DownloadTask task) {
    started.add(task.id);
    _running++;
    if (_running > _peak) _peak = _running;

    final controller = StreamController<DownloadProgress>();
    _controllers[task.id] = controller;
    controller.onCancel = () {
      _finish(task.id);
    };
    return controller.stream;
  }

  /// Emits a successful completion and ends the stream.
  void complete(String taskId, {int bytes = 1024, String? filePath}) {
    final controller = _controllers[taskId];
    if (controller == null || controller.isClosed) return;
    controller.add(
      DownloadProgress(
        taskId: taskId,
        downloadedBytes: bytes,
        totalBytes: bytes,
        progress: 1,
        completed: true,
        filePath: filePath ?? '/fake/downloads/$taskId.bin',
      ),
    );
    _finish(taskId);
  }

  /// Emits a classified failure and ends the stream.
  void fail(String taskId, DownloadFailure failure) {
    final controller = _controllers[taskId];
    if (controller == null || controller.isClosed) return;
    controller.add(
      DownloadProgress(
        taskId: taskId,
        downloadedBytes: 0,
        totalBytes: 0,
        progress: 0,
        error: failure.message,
        failure: failure,
      ),
    );
    _finish(taskId);
  }

  /// Emits a plain string error (the pre-Wave-2 shape) and ends the stream.
  void failWithString(String taskId, String error) {
    final controller = _controllers[taskId];
    if (controller == null || controller.isClosed) return;
    controller.add(
      DownloadProgress(
        taskId: taskId,
        downloadedBytes: 0,
        totalBytes: 0,
        progress: 0,
        error: error,
      ),
    );
    _finish(taskId);
  }

  /// Emits a progress tick (no completion).
  void progress(String taskId, {required int received, required int total}) {
    final controller = _controllers[taskId];
    if (controller == null || controller.isClosed) return;
    controller.add(
      DownloadProgress(
        taskId: taskId,
        downloadedBytes: received,
        totalBytes: total,
        progress: total == 0 ? 0 : received / total,
      ),
    );
  }

  void _finish(String taskId) {
    final controller = _controllers.remove(taskId);
    if (controller == null) return;
    if (_running > 0) _running--;
    if (!controller.isClosed) {
      unawaited(controller.close());
    }
  }

  @override
  void pause(String taskId) {
    pauseCalls++;
    final controller = _controllers[taskId];
    if (controller == null || controller.isClosed) return;
    controller.add(
      DownloadProgress(
        taskId: taskId,
        downloadedBytes: 0,
        totalBytes: 0,
        progress: 0,
        paused: true,
      ),
    );
    _finish(taskId);
  }

  @override
  void cancel(String taskId) {
    cancelCalls++;
    final controller = _controllers[taskId];
    if (controller == null || controller.isClosed) return;
    _finish(taskId);
  }

  @override
  Future<bool> deleteDownloadedFile(DownloadTask task) async => true;
}

/// A platform adapter that only exists to hand the download manager a URL.
class FakeDownloadPlatform extends MusicPlatform {
  FakeDownloadPlatform({
    required this.url,
    this.platform = PlatformType.netease,
  });

  String url;
  final PlatformType platform;

  int urlRequests = 0;

  @override
  PlatformType get platformType => platform;

  @override
  String get platformName => 'fake ${platform.name}';

  @override
  bool get isLoggedIn => true;

  @override
  Future<String> getSongUrl(
    String songId, {
    AudioLevel quality = AudioLevel.low,
  }) async {
    urlRequests++;
    return url;
  }

  @override
  Future<List<AudioQuality>> getAvailableQualities(String songId) async =>
      const [AudioQuality(level: AudioLevel.low, bitrate: 128000, format: 'mp3')];

  @override
  Future<VipLevel> getVipStatus() async => VipLevel.svip;

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
  Future<List<Song>> search(String keyword, {int page = 1, int limit = 30}) async =>
      const [];

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
