import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/download/data/download_scheduler.dart';
import 'package:mconnect/features/download/domain/entities/download_failure.dart';
import 'package:mconnect/features/download/domain/entities/download_task.dart';
import 'package:mconnect/features/download/presentation/providers/download_provider.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:path/path.dart' as p;

import 'download_fakes.dart';

/// The queue switches (`仅 Wi-Fi 下载` / `失败自动重试` / `自动清理` / `离线模式`)
/// and the restart behaviour. These need the Wave 2 API, so unlike
/// `download_provider_test.dart` they cannot be run against the pre-fix code —
/// before this change the switches had **no reader at all**.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mconnect_queue_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  // ---- P0-4: restart did not resume an interrupted download ----------------

  test('restores an interrupted task as paused and auto-resumes it', () async {
    final existingFile = File(p.join(tempDir.path, 'existing.mp3'));
    await existingFile.writeAsString('audio bytes');
    final completed = DownloadTask(
      id: 'netease_s1_low',
      song: _songOf('s1'),
      quality: AudioLevel.low,
      status: DownloadStatus.completed,
      progress: 1,
      downloadedBytes: 10,
      totalBytes: 10,
      filePath: existingFile.path,
      createdAt: DateTime(2026, 5, 29),
      completedAt: DateTime(2026, 5, 29, 1),
    );
    final missingCompleted = completed.copyWith(
      filePath: () => p.join(tempDir.path, 'missing.mp3'),
    );
    final interrupted = DownloadTask(
      id: 'netease_s2_low',
      song: _songOf('s2'),
      quality: AudioLevel.low,
      status: DownloadStatus.downloading,
      downloadedBytes: 3,
      totalBytes: 10,
      createdAt: DateTime(2026, 5, 29),
    );
    final failed = DownloadTask(
      id: 'netease_s3_low',
      song: _songOf('s3'),
      quality: AudioLevel.low,
      status: DownloadStatus.failed,
      error: 'timeout',
      createdAt: DateTime(2026, 5, 29),
    );

    final manager = FakeDownloadManager();
    final store = MemoryDownloadTaskStore([
      completed,
      missingCompleted,
      interrupted,
      failed,
    ]);
    final notifier = DownloadNotifier(
      manager: manager,
      taskStore: store,
      policy: () => const DownloadQueuePolicy(),
    );
    await notifier.ready;
    addTearDown(notifier.dispose);
    await pumpEventQueue();

    // A completed task whose file vanished is dropped; the interrupted one is
    // kept; the failed one keeps its reason.
    expect(notifier.state.tasks.map((task) => task.id), [
      completed.id,
      interrupted.id,
      failed.id,
    ]);
    expect(notifier.state.tasks[2].status, DownloadStatus.failed);
    expect(notifier.state.tasks[2].error, 'timeout');
    expect(store.saved.first.map((task) => task.id), [
      completed.id,
      interrupted.id,
      failed.id,
    ]);
    expect(
      manager.started,
      contains(interrupted.id),
      reason: 'auto-retry on: a mid-flight task is queued again on startup',
    );
  });

  test('with 失败自动重试 off a restored task stays paused', () async {
    final manager = FakeDownloadManager();
    final interrupted = DownloadTask(
      id: 'netease_s2_low',
      song: _songOf('s2'),
      quality: AudioLevel.low,
      status: DownloadStatus.downloading,
      createdAt: DateTime(2026, 5, 29),
    );
    final notifier = DownloadNotifier(
      manager: manager,
      taskStore: MemoryDownloadTaskStore([interrupted]),
      policy: () => const DownloadQueuePolicy(autoRetry: false),
    );
    await notifier.ready;
    addTearDown(notifier.dispose);
    await pumpEventQueue();

    expect(notifier.state.tasks.single.status, DownloadStatus.paused);
    expect(manager.started, isEmpty);
  });

  // ---- P0-3a: 仅 Wi-Fi 下载 --------------------------------------------------

  test('仅 Wi-Fi 下载 holds cache tasks on mobile and releases them on Wi-Fi',
      () async {
    final manager = FakeDownloadManager();
    final connectivity = StreamController<Object?>.broadcast();
    var onWifi = false;
    final notifier = DownloadNotifier(
      manager: manager,
      taskStore: MemoryDownloadTaskStore([]),
      policy: () => const DownloadQueuePolicy(wifiOnly: true),
      connectionCheck: () async => onWifi,
      connectivityStream: connectivity.stream,
    );
    addTearDown(() {
      notifier.dispose();
      unawaited(connectivity.close());
    });

    final report = await notifier.cacheSongs([_song], quality: AudioLevel.low);
    await pumpEventQueue();

    expect(report.blockedNoConnection, 1);
    expect(report.started, 0);
    expect(manager.started, isEmpty, reason: 'no download on mobile data');
    expect(
      notifier.state.tasks.single.status,
      DownloadStatus.waiting,
      reason: 'a held task is still visible as waiting',
    );
    expect(notifier.state.queueBlockedReason, contains('Wi-Fi'));

    // Wi-Fi comes back: the held task starts by itself.
    onWifi = true;
    connectivity.add(<Object>[]);
    await pumpEventQueue();

    expect(manager.started, ['netease_s1_low_cache']);
    expect(notifier.state.tasks.single.status, DownloadStatus.downloading);
  });

  test('仅 Wi-Fi 下载 never vetoes a download the user tapped', () async {
    final manager = FakeDownloadManager();
    final notifier = DownloadNotifier(
      manager: manager,
      taskStore: MemoryDownloadTaskStore([]),
      policy: () => const DownloadQueuePolicy(wifiOnly: true),
      connectionCheck: () async => false,
    );
    addTearDown(notifier.dispose);

    await notifier.startDownload(_song, AudioLevel.low);
    await pumpEventQueue();

    expect(
      manager.started,
      ['netease_s1_low'],
      reason: 'the switch is labelled "移动网络下不自动执行缓存任务"',
    );
    expect(notifier.state.tasks.single.status, DownloadStatus.downloading);
  });

  // ---- P0-3b: 失败自动重试 ---------------------------------------------------

  test('失败自动重试 retries a transient network failure', () async {
    final manager = FakeDownloadManager();
    final notifier = DownloadNotifier(
      manager: manager,
      taskStore: MemoryDownloadTaskStore([]),
      retryDelay: const Duration(milliseconds: 30),
      policy: () => const DownloadQueuePolicy(autoRetry: true),
    );
    addTearDown(notifier.dispose);

    await notifier.startDownload(_song, AudioLevel.low);
    await pumpEventQueue();
    expect(manager.started, hasLength(1));

    manager.fail(manager.started.first, DownloadFailure.network('socket reset'));
    await pumpEventQueue();

    // The failure is recorded (and the switch has scheduled a retry).
    expect(notifier.state.tasks.single.status, DownloadStatus.failed);
    expect(
      notifier.state.tasks.single.failureKind,
      DownloadFailureKind.network,
    );

    await Future<void>.delayed(const Duration(milliseconds: 60));
    await pumpEventQueue();

    expect(
      manager.started,
      hasLength(2),
      reason: 'a NetworkException is retryable and the switch is on',
    );

    manager.complete(manager.started.last);
    await pumpEventQueue();
    expect(notifier.state.tasks.single.status, DownloadStatus.completed);
  });

  test('失败自动重试 does not retry a login failure', () async {
    final manager = FakeDownloadManager();
    final notifier = DownloadNotifier(
      manager: manager,
      taskStore: MemoryDownloadTaskStore([]),
      retryDelay: Duration.zero,
      policy: () => const DownloadQueuePolicy(autoRetry: true),
    );
    addTearDown(notifier.dispose);

    await notifier.startDownload(_song, AudioLevel.low);
    await pumpEventQueue();
    manager.fail(
      manager.started.first,
      const DownloadFailure(
        kind: DownloadFailureKind.auth,
        message: '登录已过期，请重新登录',
      ),
    );
    await pumpEventQueue();
    await pumpEventQueue();

    expect(manager.started, hasLength(1));
    final task = notifier.state.tasks.single;
    expect(task.status, DownloadStatus.failed);
    expect(task.failureKind, DownloadFailureKind.auth);
    expect(task.error, '登录已过期，请重新登录');
  });

  test('失败自动重试 stops after the bounded number of attempts', () async {
    final manager = FakeDownloadManager();
    final notifier = DownloadNotifier(
      manager: manager,
      taskStore: MemoryDownloadTaskStore([]),
      retryDelay: Duration.zero,
      maxAutoRetries: 2,
      policy: () => const DownloadQueuePolicy(autoRetry: true),
    );
    addTearDown(notifier.dispose);

    await notifier.startDownload(_song, AudioLevel.low);
    await pumpEventQueue();
    for (var attempt = 0; attempt < 4; attempt++) {
      if (manager.started.isEmpty) break;
      manager.fail(manager.started.last, DownloadFailure.network());
      await pumpEventQueue();
      await pumpEventQueue();
    }

    expect(
      manager.started,
      hasLength(3),
      reason: '1 initial attempt + 2 retries, then it gives up',
    );
    expect(notifier.state.tasks.single.status, DownloadStatus.failed);
  });

  test('with 失败自动重试 off a failure is not retried', () async {
    final manager = FakeDownloadManager();
    final notifier = DownloadNotifier(
      manager: manager,
      taskStore: MemoryDownloadTaskStore([]),
      retryDelay: Duration.zero,
      policy: () => const DownloadQueuePolicy(autoRetry: false),
    );
    addTearDown(notifier.dispose);

    await notifier.startDownload(_song, AudioLevel.low);
    await pumpEventQueue();
    manager.fail(manager.started.first, DownloadFailure.network());
    await pumpEventQueue();
    await pumpEventQueue();

    expect(manager.started, hasLength(1));
    expect(notifier.state.tasks.single.status, DownloadStatus.failed);
  });

  // ---- P0-3c: 离线模式 ------------------------------------------------------

  test('离线模式 stops the cache queue from starting anything on its own',
      () async {
    final manager = FakeDownloadManager();
    final notifier = DownloadNotifier(
      manager: manager,
      taskStore: MemoryDownloadTaskStore([]),
      policy: () => const DownloadQueuePolicy(offlineMode: true),
    );
    addTearDown(notifier.dispose);

    final report = await notifier.cacheSongs([_song], quality: AudioLevel.low);
    await pumpEventQueue();

    expect(report.blockedOfflineMode, 1);
    expect(report.started, 0);
    expect(manager.started, isEmpty);
    expect(notifier.state.queueBlockedReason, contains('离线模式'));

    // An explicit tap still works.
    await notifier.startWaitingTask('netease_s1_low_cache');
    await pumpEventQueue();
    expect(manager.started, ['netease_s1_low_cache']);
  });

  // ---- P0-3d: 自动清理 / LRU ------------------------------------------------

  test('自动清理 runs when an offline-cache file lands and evicts by LRU',
      () async {
    final manager = FakeDownloadManager();
    final files = <String, String>{};
    Future<DownloadTask> seedTask(
      String id,
      int bytes,
      DateTime completedAt, {
      DateTime? accessedAt,
    }) async {
      final file = File(p.join(tempDir.path, '$id.bin'));
      await file.writeAsBytes(List<int>.filled(bytes, 7));
      files[id] = file.path;
      return DownloadTask(
        id: id,
        song: _songOf(id),
        quality: AudioLevel.low,
        status: DownloadStatus.completed,
        progress: 1,
        downloadedBytes: bytes,
        totalBytes: bytes,
        filePath: file.path,
        createdAt: completedAt,
        completedAt: completedAt,
        isOfflineCache: true,
        lastAccessedAt: accessedAt,
      );
    }

    // Three 400 KB entries = 1.2 MB against a 1 MB limit: exactly one eviction.
    final oldestButMostUsed = await seedTask(
      'c1',
      400 * 1024,
      DateTime(2026, 1, 1),
      accessedAt: DateTime(2026, 6, 1),
    );
    final leastRecentlyUsed = await seedTask(
      'c2',
      400 * 1024,
      DateTime(2026, 3, 1),
    );
    final newest = await seedTask('c3', 400 * 1024, DateTime(2026, 5, 1));

    final notifier = DownloadNotifier(
      manager: manager,
      initialState: DownloadState(tasks: [oldestButMostUsed, leastRecentlyUsed, newest]),
      taskStore: MemoryDownloadTaskStore([]),
      policy: () =>
          const DownloadQueuePolicy(autoCleanup: true, sizeLimitMb: 1),
    );
    addTearDown(notifier.dispose);

    await notifier.cacheSongs([_songOf('c4')], quality: AudioLevel.low);
    await pumpEventQueue();
    manager.complete('netease_c4_low_cache', bytes: 1024);
    // Auto-cleanup runs from the completion callback and stats real files, so
    // wait for the eviction instead of assuming a fixed number of event-loop
    // turns is enough.
    await _waitFor(
      () => !notifier.state.tasks.any((task) => task.id == leastRecentlyUsed.id),
    );

    final remaining = notifier.state.tasks.map((task) => task.id).toList();
    expect(
      remaining,
      isNot(contains(leastRecentlyUsed.id)),
      reason: 'LRU: the least recently used entry goes first',
    );
    expect(
      remaining,
      contains(oldestButMostUsed.id),
      reason: 'FIFO would have evicted the oldest completion instead',
    );
    expect(remaining, contains(newest.id));
    expect(notifier.state.estimatedOfflineCacheBytes, lessThan(1024 * 1024));
  });

  test('cleanupOfflineCache can be triggered by hand and respects the limit',
      () async {
    final manager = FakeDownloadManager();
    final task = DownloadTask(
      id: 'c1',
      song: _songOf('c1'),
      quality: AudioLevel.low,
      status: DownloadStatus.completed,
      progress: 1,
      downloadedBytes: 2048,
      totalBytes: 2048,
      filePath: p.join(tempDir.path, 'c1.bin'),
      createdAt: DateTime(2026, 1, 1),
      completedAt: DateTime(2026, 1, 1),
      isOfflineCache: true,
    );
    final notifier = DownloadNotifier(
      manager: manager,
      initialState: DownloadState(tasks: [task]),
      taskStore: MemoryDownloadTaskStore([]),
      policy: () => const DownloadQueuePolicy(autoCleanup: false),
    );
    addTearDown(notifier.dispose);

    expect(await notifier.cleanupOfflineCache(sizeLimitMb: 0), 0);
    expect(notifier.state.tasks, hasLength(1));
  });

  // ---- P2: cache usage is measured by scanning the disk ---------------------

  test('offline cache usage is scanned from disk, not from task records',
      () async {
    final manager = FakeDownloadManager();
    final fileA = File(p.join(tempDir.path, 'a.bin'));
    final fileB = File(p.join(tempDir.path, 'b.bin'));
    await fileA.writeAsBytes(List<int>.filled(1000, 1));
    await fileB.writeAsBytes(List<int>.filled(2000, 1));
    DownloadTask taskFor(String id, File file, int bytes) => DownloadTask(
      id: id,
      song: _songOf(id),
      quality: AudioLevel.low,
      status: DownloadStatus.completed,
      progress: 1,
      downloadedBytes: bytes,
      totalBytes: bytes,
      filePath: file.path,
      createdAt: DateTime(2026, 1, 1),
      completedAt: DateTime(2026, 1, 1),
      isOfflineCache: true,
    );

    final notifier = DownloadNotifier(
      manager: manager,
      initialState: DownloadState(
        tasks: [taskFor('a', fileA, 1000), taskFor('b', fileB, 2000)],
      ),
      taskStore: MemoryDownloadTaskStore([]),
    );
    addTearDown(notifier.dispose);

    expect(await notifier.refreshCacheUsage(), 3000);

    // The user (or another app) deletes one file: the number must follow.
    await fileA.delete();
    expect(await notifier.refreshCacheUsage(), 2000);
    expect(notifier.state.estimatedOfflineCacheBytes, 2000);
    expect(notifier.state.recordedOfflineCacheBytes, 3000);
  });

  // ---- offline playback priority hook --------------------------------------

  test('localFilePathFor prefers a manual download and stamps the access time',
      () async {
    final manager = FakeDownloadManager();
    final manualFile = File(p.join(tempDir.path, 'manual.mp3'));
    final cacheFile = File(p.join(tempDir.path, 'cache.mp3'));
    await manualFile.writeAsString('manual');
    await cacheFile.writeAsString('cache');
    final cacheTask = DownloadTask(
      id: 'netease_s1_low_cache',
      song: _song,
      quality: AudioLevel.low,
      status: DownloadStatus.completed,
      progress: 1,
      filePath: cacheFile.path,
      createdAt: DateTime(2026, 1, 1),
      completedAt: DateTime(2026, 1, 1),
      isOfflineCache: true,
    );
    final manualTask = DownloadTask(
      id: 'netease_s1_low',
      song: _song,
      quality: AudioLevel.low,
      status: DownloadStatus.completed,
      progress: 1,
      filePath: manualFile.path,
      createdAt: DateTime(2026, 1, 2),
      completedAt: DateTime(2026, 1, 2),
    );
    final notifier = DownloadNotifier(
      manager: manager,
      initialState: DownloadState(tasks: [cacheTask, manualTask]),
      taskStore: MemoryDownloadTaskStore([]),
    );
    addTearDown(notifier.dispose);

    expect(await notifier.localFilePathFor(_song), manualFile.path);
    expect(
      notifier.state.tasks
          .firstWhere((task) => task.id == manualTask.id)
          .lastAccessedAt,
      isNotNull,
      reason: 'reading a file is what LRU eviction orders by',
    );
  });

  test('localFilePathFor returns null once the file is gone', () async {
    final manager = FakeDownloadManager();
    final notifier = DownloadNotifier(
      manager: manager,
      initialState: DownloadState(
        tasks: [
          DownloadTask(
            id: 'netease_s1_low',
            song: _song,
            quality: AudioLevel.low,
            status: DownloadStatus.completed,
            progress: 1,
            filePath: p.join(tempDir.path, 'gone.mp3'),
            createdAt: DateTime(2026, 1, 1),
            completedAt: DateTime(2026, 1, 1),
          ),
        ],
      ),
      taskStore: MemoryDownloadTaskStore([]),
    );
    addTearDown(notifier.dispose);

    expect(await notifier.localFilePathFor(_song), isNull);
  });

  // ---- queue pause --------------------------------------------------------

  test('pausing the queue stops new starts and resuming restarts them',
      () async {
    final manager = FakeDownloadManager();
    final notifier = DownloadNotifier(
      manager: manager,
      taskStore: MemoryDownloadTaskStore([]),
    );
    addTearDown(notifier.dispose);

    notifier.pauseQueue();
    expect(notifier.state.queuePaused, isTrue);
    expect(notifier.state.queueBlockedReason, contains('暂停'));

    final report = await notifier.cacheSongs([
      _songOf('p1'),
      _songOf('p2'),
    ], quality: AudioLevel.low);
    await pumpEventQueue();

    expect(report.blockedQueuePaused, 2);
    expect(manager.started, isEmpty);

    await notifier.resumeQueue();
    await pumpEventQueue();

    expect(manager.started, hasLength(2));
    expect(notifier.state.queuePaused, isFalse);
    expect(notifier.state.queueBlockedReason, isNull);
  });

  test('resuming the queue restarts a download the pause had stopped',
      () async {
    final manager = FakeDownloadManager();
    final notifier = DownloadNotifier(
      manager: manager,
      taskStore: MemoryDownloadTaskStore([]),
    );
    addTearDown(notifier.dispose);

    await notifier.startDownload(_song, AudioLevel.low);
    await pumpEventQueue();
    expect(notifier.state.tasks.single.status, DownloadStatus.downloading);

    notifier.pauseQueue();
    await pumpEventQueue();

    expect(manager.pauseCalls, 1);
    expect(notifier.state.tasks.single.status, DownloadStatus.paused);

    await notifier.resumeQueue();
    await pumpEventQueue();

    expect(
      manager.started,
      hasLength(2),
      reason: '"继续队列" must put the stopped download back in the queue',
    );
    expect(notifier.state.tasks.single.status, DownloadStatus.downloading);
  });

  // ---- P1: the queue is what caps concurrency ------------------------------

  test('the queue hands slots to queued tasks as earlier ones finish',
      () async {
    final manager = FakeDownloadManager();
    final notifier = DownloadNotifier(
      manager: manager,
      taskStore: MemoryDownloadTaskStore([]),
    );
    addTearDown(notifier.dispose);

    await notifier.cacheSongs([
      _songOf('q1'),
      _songOf('q2'),
      _songOf('q3'),
      _songOf('q4'),
      _songOf('q5'),
    ], quality: AudioLevel.low);
    await pumpEventQueue();

    expect(kMaxConcurrentDownloads, 3);
    expect(manager.started, hasLength(3));

    manager.complete(manager.started[0]);
    await pumpEventQueue();
    expect(manager.started, hasLength(4));
    expect(manager.isRunning(manager.started[3]), isTrue);

    manager.complete(manager.started[1]);
    await pumpEventQueue();
    expect(manager.started, hasLength(5));
  });
}

const _song = Song(
  id: 's1',
  platform: PlatformType.netease,
  name: 'Song 1',
  artists: [Artist(id: 'a1', name: 'Artist 1')],
);

/// Waits until [predicate] holds (or fails the test after a timeout).
Future<void> _waitFor(bool Function() predicate, {int attempts = 200}) async {
  for (var i = 0; i < attempts; i++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('condition was never met');
}

Song _songOf(String id) => Song(
  id: id,
  platform: PlatformType.netease,
  name: 'Song $id',
  artists: const [Artist(id: 'a1', name: 'Artist 1')],
);
