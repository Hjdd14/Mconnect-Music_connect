import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/download/data/download_directory_service.dart';
import 'package:mconnect/features/download/data/download_task_store.dart';
import 'package:mconnect/features/download/data/repositories/download_manager.dart';
import 'package:mconnect/features/download/domain/entities/download_task.dart';
import 'package:mconnect/features/download/presentation/providers/download_provider.dart';
import 'package:mconnect/models/album.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/platform/base/platform_registry.dart';
import 'package:mconnect/platform/kugou/kugou_api.dart';
import 'package:mconnect/platform/kugou/kugou_platform.dart';
import 'package:path/path.dart' as p;

/// These tests use **only** the pre-Wave-2 public API
/// (`DownloadNotifier(manager:, taskStore:, initialState:)` + `DownloadProgress`
/// without `failure`), so the same file can be run against the old
/// implementation to prove the two P0 defects were real:
///
/// * `cacheSongs` never started a download (dead queue);
/// * a song enqueued for cache could never be downloaded by hand (shared id).
///
/// Tests for the queue switches live in `download_queue_policy_test.dart`,
/// because before this change those switches had no reader at all.
void main() {
  test('download task json round-trips all persistent fields', () {
    final task = DownloadTask(
      id: 'qq_s1_lossless',
      song: _richSong,
      quality: AudioLevel.lossless,
      status: DownloadStatus.failed,
      progress: 0.4,
      downloadedBytes: 400,
      totalBytes: 1000,
      filePath: 'D:/Music/song.flac',
      error: 'network failed',
      createdAt: DateTime(2026, 5, 29, 10),
      completedAt: DateTime(2026, 5, 29, 11),
      isOfflineCache: true,
    );

    final restored = DownloadTask.fromJson(task.toJson());

    expect(restored, isNotNull);
    expect(restored!.id, task.id);
    expect(restored.song.id, _richSong.id);
    expect(restored.song.platform, _richSong.platform);
    expect(restored.song.album?.name, 'Album 1');
    expect(restored.song.availableQualities.single.level, AudioLevel.lossless);
    expect(restored.quality, AudioLevel.lossless);
    expect(restored.status, DownloadStatus.failed);
    expect(restored.progress, 0.4);
    expect(restored.downloadedBytes, 400);
    expect(restored.totalBytes, 1000);
    expect(restored.filePath, 'D:/Music/song.flac');
    expect(restored.error, 'network failed');
    expect(restored.completedAt, DateTime(2026, 5, 29, 11));
    expect(restored.isOfflineCache, isTrue);
  });

  test(
    'an unknown platform in persisted JSON drops the row instead of 网易云',
    () {
      final task = DownloadTask(
        id: 'netease_s1_low',
        song: _song,
        quality: AudioLevel.low,
        createdAt: DateTime(2026, 5, 29),
      );
      final json = task.toJson();
      (json['song'] as Map<String, dynamic>)['platform'] = 'spotify';

      expect(
        DownloadTask.fromJson(json),
        isNull,
        reason: 'silently re-attributing a foreign row to 网易云 is data loss',
      );
    },
  );

  test('removing a completed download deletes the downloaded file', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'mconnect_remove_download_',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final file = File(p.join(tempDir.path, 'song.mp3'));
    await file.writeAsString('audio bytes');
    final task = DownloadTask(
      id: 'netease_s1_low',
      song: _song,
      quality: AudioLevel.low,
      status: DownloadStatus.completed,
      progress: 1,
      downloadedBytes: await file.length(),
      totalBytes: await file.length(),
      filePath: file.path,
      createdAt: DateTime(2026, 5, 29),
      completedAt: DateTime(2026, 5, 29),
    );
    final manager = DownloadManager(
      directoryService: DownloadDirectoryService(
        store: _MemoryDownloadDirectoryStore(),
        defaultRootProvider: () async => tempDir,
      ),
    );
    final store = _MemoryDownloadTaskStore([task]);
    final notifier = DownloadNotifier(
      manager: manager,
      initialState: DownloadState(tasks: [task]),
      taskStore: store,
    );
    addTearDown(notifier.dispose);

    final removed = await notifier.removeTask(task.id);

    expect(removed, isTrue);
    expect(await file.exists(), isFalse);
    expect(notifier.state.tasks, isEmpty);
    expect(store.saved.last, isEmpty);
  });

  test(
    'Kugou concept VIP session allows lossless downloads through VIP gate',
    () async {
      PlatformRegistry.register(
        KugouPlatform(api: _ConceptVipSessionWithFreeVipInfoApi()),
      );
      final notifier = DownloadNotifier(
        taskStore: _MemoryDownloadTaskStore([]),
      );
      addTearDown(notifier.dispose);

      final allowed = await notifier.checkVipForDownload(
        _kugouSong,
        AudioLevel.lossless,
      );

      expect(allowed, isTrue);
    },
  );

  // ---- P0-1: the offline cache queue was dead ------------------------------

  test('cacheSongs really starts downloads and respects the concurrency cap',
      () async {
    final manager = _FakeDownloadManager();
    final notifier = DownloadNotifier(
      manager: manager,
      taskStore: _MemoryDownloadTaskStore([]),
    );
    addTearDown(notifier.dispose);

    await notifier.cacheSongs([
      _songOf('c1'),
      _songOf('c2'),
      _songOf('c3'),
      _songOf('c4'),
    ], quality: AudioLevel.low);
    await pumpEventQueue();

    expect(notifier.state.tasks, hasLength(4));
    // The queue is real: three ran concurrently, the fourth waited for a slot.
    expect(manager.started, hasLength(3));
    expect(manager.peakConcurrent, 3);
    expect(
      notifier.state.tasks.where((t) => t.status == DownloadStatus.waiting),
      hasLength(1),
    );

    manager.complete(manager.started.first);
    await pumpEventQueue();

    expect(manager.started, hasLength(4));
    expect(
      manager.started.last,
      'netease_c4_low_cache',
      reason: 'FIFO: the last enqueued task must be the one that starts next',
    );
  });

  test('cacheSongs de-duplicates the same song within the cache queue',
      () async {
    final manager = _FakeDownloadManager();
    final notifier = DownloadNotifier(
      manager: manager,
      taskStore: _MemoryDownloadTaskStore([]),
    );
    addTearDown(notifier.dispose);

    await notifier.cacheSongs([_song, _song], quality: AudioLevel.low);

    expect(notifier.state.tasks, hasLength(1));
  });

  // ---- P0-2: a cached song could never be downloaded by hand ---------------

  test('a song enqueued for offline cache can still be downloaded by hand',
      () async {
    final manager = _FakeDownloadManager();
    final notifier = DownloadNotifier(
      manager: manager,
      taskStore: _MemoryDownloadTaskStore([]),
    );
    addTearDown(notifier.dispose);

    await notifier.cacheSongs([_song], quality: AudioLevel.low);
    await notifier.startDownload(_song, AudioLevel.low);
    await pumpEventQueue();

    expect(
      notifier.state.tasks.map((task) => task.id),
      containsAll(<String>['netease_s1_low_cache', 'netease_s1_low']),
      reason: 'cache and manual downloads are separate entries',
    );
    expect(manager.started, contains('netease_s1_low'));
  });

  test('an in-flight manual download is not duplicated', () async {
    final manager = _FakeDownloadManager();
    final notifier = DownloadNotifier(
      manager: manager,
      taskStore: _MemoryDownloadTaskStore([]),
    );
    addTearDown(notifier.dispose);

    await notifier.startDownload(_song, AudioLevel.low);
    await notifier.startDownload(_song, AudioLevel.low);
    await pumpEventQueue();

    expect(notifier.state.tasks, hasLength(1));
    expect(manager.started, hasLength(1));
  });

  test('a song already downloaded by hand needs no cache copy', () async {
    final manager = _FakeDownloadManager();
    final notifier = DownloadNotifier(
      manager: manager,
      taskStore: _MemoryDownloadTaskStore([]),
    );
    addTearDown(notifier.dispose);

    await notifier.startDownload(_song, AudioLevel.low);
    await pumpEventQueue();
    manager.complete('netease_s1_low');
    await pumpEventQueue();
    expect(notifier.state.tasks.single.status, DownloadStatus.completed);

    final report = await notifier.cacheSongs([_song], quality: AudioLevel.low);
    await pumpEventQueue();

    expect(report.skipped, 1);
    expect(notifier.state.tasks, hasLength(1));
    expect(manager.started, hasLength(1));
  });
}

const _song = Song(
  id: 's1',
  platform: PlatformType.netease,
  name: 'Song 1',
  artists: [Artist(id: 'a1', name: 'Artist 1')],
);

Song _songOf(String id) => Song(
  id: id,
  platform: PlatformType.netease,
  name: 'Song $id',
  artists: const [Artist(id: 'a1', name: 'Artist 1')],
);

const _richSong = Song(
  id: 's1',
  platform: PlatformType.qq,
  name: 'Song 1',
  artists: [
    Artist(id: 'a1', name: 'Artist 1', avatarUrl: 'https://example.com/a.png'),
  ],
  album: Album(
    id: 'al1',
    name: 'Album 1',
    artistName: 'Artist 1',
    coverUrl: 'https://example.com/c.png',
  ),
  duration: Duration(seconds: 180),
  coverUrl: 'https://example.com/song.png',
  availableQualities: [
    AudioQuality(level: AudioLevel.lossless, bitrate: 999000, format: 'flac'),
  ],
);

const _kugouSong = Song(
  id: 'hash1',
  platform: PlatformType.kugou,
  name: 'Kugou Song',
  artists: [Artist(id: 'a1', name: 'Artist 1')],
);

class _ConceptVipSessionWithFreeVipInfoApi extends KugouApi {
  _ConceptVipSessionWithFreeVipInfoApi() {
    setClientMode(KugouPlaybackClient.lite);
    setSessionFields(
      token: 'token-1',
      userid: '10001',
      vipToken: 'vip-token-1',
      vipType: '6',
    );
  }

  @override
  Future<Map<String, dynamic>> getVipInfo() async {
    return {
      'status': 1,
      'data': {'vip_type': 0},
    };
  }
}

/// Old-API-only fake: no typed `failure` on [DownloadProgress].
class _FakeDownloadManager extends DownloadManager {
  _FakeDownloadManager()
    : super(
        directoryService: DownloadDirectoryService(
          store: _MemoryDownloadDirectoryStore(),
          defaultRootProvider: () async => throw UnimplementedError(),
        ),
      );

  final List<String> started = <String>[];
  final Map<String, StreamController<DownloadProgress>> _controllers = {};
  int _running = 0;
  int _peak = 0;

  int get peakConcurrent => _peak;

  @override
  Stream<DownloadProgress> download(DownloadTask task) {
    started.add(task.id);
    _running++;
    if (_running > _peak) _peak = _running;
    final controller = StreamController<DownloadProgress>();
    _controllers[task.id] = controller;
    controller.onCancel = () => _finish(task.id);
    return controller.stream;
  }

  void complete(String taskId, {int bytes = 1024}) {
    final controller = _controllers[taskId];
    if (controller == null || controller.isClosed) return;
    controller.add(
      DownloadProgress(
        taskId: taskId,
        downloadedBytes: bytes,
        totalBytes: bytes,
        progress: 1,
        completed: true,
        filePath: '/fake/downloads/$taskId.bin',
      ),
    );
    _finish(taskId);
  }

  void _finish(String taskId) {
    final controller = _controllers.remove(taskId);
    if (controller == null) return;
    if (_running > 0) _running--;
    if (!controller.isClosed) unawaited(controller.close());
  }

  @override
  void pause(String taskId) {
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
    _finish(taskId);
  }

  @override
  Future<bool> deleteDownloadedFile(DownloadTask task) async => true;
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
  final List<List<DownloadTask>> saved = [];

  _MemoryDownloadTaskStore(this.tasks);

  @override
  Future<List<DownloadTask>> load() async => tasks;

  @override
  Future<void> save(List<DownloadTask> tasks) async {
    this.tasks = List<DownloadTask>.from(tasks);
    saved.add(List<DownloadTask>.from(tasks));
  }
}
