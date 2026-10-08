import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
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
  // The Hive-backed store tests below need a live binding before `Hive.init`.
  TestWidgetsFlutterBinding.ensureInitialized();

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

  // ---- W0-C: one path per (song, quality) ---------------------------------
  //
  // The bug: `fileName` carried no quality and the directory only split
  // lossless from lossy, so 标准/较高/极高 all resolved to
  // `<root>/netease/mp3/歌手 - 歌名.mp3`. Two consequences, both data-losing:
  // the second task's resume used the first task's byte count as its offset (a
  // corrupt file), and deleting one row deleted the other row's file.

  test('a download file name carries the audio quality', () {
    final byQuality = <AudioLevel, String>{
      for (final quality in const [
        AudioLevel.low,
        AudioLevel.medium,
        AudioLevel.high,
      ])
        quality: DownloadTask(
          id: DownloadTask.buildId(_song, quality),
          song: _song,
          quality: quality,
          createdAt: DateTime(2026, 5, 29),
        ).fileName,
    };

    expect(
      byQuality.values.toSet(),
      hasLength(3),
      reason: 'three lossy qualities must not share one file name',
    );
    for (final entry in byQuality.entries) {
      expect(
        entry.value,
        contains(entry.key.name),
        reason: 'the file name must say which quality it holds',
      );
      expect(entry.value, endsWith('.mp3'));
    }
  });

  test('the same (song, quality) always resolves to the same file name', () {
    DownloadTask build() => DownloadTask(
      id: DownloadTask.buildId(_song, AudioLevel.low),
      song: _song,
      quality: AudioLevel.low,
      createdAt: DateTime(2026, 5, 29),
    );

    expect(build().fileName, build().fileName);

    // A manual row and an offline-cache row for one song+quality are two rows
    // for ONE file, so they must also agree on the name.
    final cacheRow = DownloadTask(
      id: DownloadTask.buildCacheId(_song, AudioLevel.low),
      song: _song,
      quality: AudioLevel.low,
      isOfflineCache: true,
      createdAt: DateTime(2026, 5, 29),
    );
    expect(cacheRow.fileName, build().fileName);
  });

  test('a file name stays free of path separators and unsafe characters', () {
    const nasty = Song(
      id: 's2',
      platform: PlatformType.netease,
      name: r'斜杠/反斜杠\冒号:星号*问号?双引号"尖括号<>竖线|',
      artists: [Artist(id: 'a1', name: r'艺人/一\二')],
    );
    final task = DownloadTask(
      id: DownloadTask.buildId(nasty, AudioLevel.low),
      song: nasty,
      quality: AudioLevel.low,
      createdAt: DateTime(2026, 5, 29),
    );

    expect(task.fileName, isNot(contains('/')));
    expect(task.fileName, isNot(contains(r'\')));
    expect(task.fileName, isNot(contains(':')));
    expect(task.fileName, endsWith('.mp3'));
  });

  // ---- W0-C: two rows that point at one file -------------------------------
  //
  // A manual download and the offline-cache row for one song+quality are two
  // rows for ONE file, and rows written before the file name carried the quality
  // share one too. The app must never rename or delete a file on its own, so the
  // duplicate is *reported*, and a removal keeps the file while another row still
  // needs it.

  group('two completed rows sharing one file', () {
    test('both are reported as duplicatePath, and neither path is rewritten',
        () async {
      final shared = p.join('D:', 'Music', 'Artist - Song [low].mp3');
      final manual = _completedTask('netease_s1_low', shared);
      final cache = _completedTask(
        'netease_s1_low_cache',
        shared,
        isOfflineCache: true,
      );

      final notifier = DownloadNotifier(
        taskStore: _MemoryDownloadTaskStore([manual, cache]),
        initialState: DownloadState(tasks: [manual, cache]),
      );
      addTearDown(notifier.dispose);

      expect(notifier.state.duplicatePathTaskIds, {
        'netease_s1_low',
        'netease_s1_low_cache',
      });
      expect(
        notifier.state.tasks.map((task) => task.filePath).toSet(),
        {shared},
        reason: '存量用户的文件名是他们的，应用不得自动改名',
      );
    });

    test('a duplicate is recognised across \\ and / separators', () async {
      final manual = _completedTask('netease_s1_low', r'D:\Music\s.mp3');
      final cache = _completedTask('netease_s1_low_cache', 'D:/Music/s.mp3');

      final notifier = DownloadNotifier(
        taskStore: _MemoryDownloadTaskStore([manual, cache]),
        initialState: DownloadState(tasks: [manual, cache]),
      );
      addTearDown(notifier.dispose);

      expect(notifier.state.duplicatePathTaskIds, hasLength(2));
    });

    test('a row that shares nothing is not reported', () async {
      final first = _completedTask('netease_s1_low', 'D:/Music/a.mp3');
      final second = _completedTask(
        'netease_s1_high',
        'D:/Music/b.mp3',
        quality: AudioLevel.high,
      );

      final notifier = DownloadNotifier(
        taskStore: _MemoryDownloadTaskStore([first, second]),
        initialState: DownloadState(tasks: [first, second]),
      );
      addTearDown(notifier.dispose);

      expect(notifier.state.duplicatePathTaskIds, isEmpty);
    });

    test('removing one of two rows keeps the file, removing the last deletes it',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('mconnect_shared_');
      addTearDown(() => tempDir.delete(recursive: true));
      final file = File(p.join(tempDir.path, 'Artist - Song [low].mp3'));
      await file.writeAsString('audio bytes');

      final manual = _completedTask('netease_s1_low', file.path);
      final cache = _completedTask(
        'netease_s1_low_cache',
        file.path,
        isOfflineCache: true,
      );
      final manager = DownloadManager(
        directoryService: DownloadDirectoryService(
          store: _MemoryDownloadDirectoryStore(),
          defaultRootProvider: () async => tempDir,
        ),
      );
      final notifier = DownloadNotifier(
        manager: manager,
        taskStore: _MemoryDownloadTaskStore([manual, cache]),
        initialState: DownloadState(tasks: [manual, cache]),
      );
      addTearDown(notifier.dispose);

      expect(await notifier.removeTask('netease_s1_low'), isTrue);

      expect(
        await file.exists(),
        isTrue,
        reason: '另一行还指着这个文件：删记录可以，删文件不行',
      );
      expect(notifier.state.keptSharedFilePath, file.path);
      expect(notifier.state.tasks.single.id, 'netease_s1_low_cache');
      // Once the second row is gone there is no duplicate left to report.
      expect(notifier.state.duplicatePathTaskIds, isEmpty);

      notifier.acknowledgeKeptSharedFile();
      expect(notifier.state.keptSharedFilePath, isNull);

      // The last row that points at it is an ordinary delete.
      expect(await notifier.removeTask('netease_s1_low_cache'), isTrue);
      expect(await file.exists(), isFalse);
    });
  });

  // ---- W0-C: A-7 progress ticks must not rewrite the whole library ---------

  group('progress persistence', () {
    test('progress ticks are coalesced into a single write', () async {
      final manager = _FakeDownloadManager();
      final store = _MemoryDownloadTaskStore(const []);
      final notifier = DownloadNotifier(
        manager: manager,
        taskStore: store,
        progressPersistInterval: const Duration(milliseconds: 150),
      );
      addTearDown(notifier.dispose);

      await notifier.startDownload(_song, AudioLevel.low);
      await pumpEventQueue();
      final writesBeforeTicks = store.saved.length;

      for (final received in [100, 200, 300]) {
        manager.progress('netease_s1_low', received: received, total: 1000);
        await pumpEventQueue();
      }

      expect(
        store.saved,
        hasLength(writesBeforeTicks),
        reason: '一个窗口内的三个进度事件不得落盘三次',
      );

      await Future<void>.delayed(const Duration(milliseconds: 400));
      await pumpEventQueue();

      expect(store.saved, hasLength(writesBeforeTicks + 1));
      expect(
        store.saved.last.single.downloadedBytes,
        300,
        reason: '合并后的唯一一次写必须带上最新进度',
      );
      expect(notifier.state.tasks.single.downloadedBytes, 300);
    });

    test('a status change is written immediately, not on the next flush',
        () async {
      final manager = _FakeDownloadManager();
      final store = _MemoryDownloadTaskStore(const []);
      final notifier = DownloadNotifier(
        manager: manager,
        taskStore: store,
        // Long enough that only an immediate write can be observed.
        progressPersistInterval: const Duration(seconds: 30),
      );
      addTearDown(notifier.dispose);

      await notifier.startDownload(_song, AudioLevel.low);
      await pumpEventQueue();

      manager.complete('netease_s1_low');
      await pumpEventQueue();

      expect(
        store.saved.last.single.status,
        DownloadStatus.completed,
        reason: '完成必须立刻落盘：重启后不能把已完成的下载看成半成品',
      );
    });
  });

  // ---- W0-C: the Hive row layout that makes the throttle possible ----------
  //
  // The throttle above is only cheap because a row can be written on its own:
  // rows live under `task/<id>` and the legacy single `tasks` list is what an
  // older build reads. These tests pin that layout and the migration.

  group('HiveDownloadTaskStore row layout', () {
    late Directory tempDir;
    late Box<dynamic> box;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('mconnect_task_box_');
      Hive.init(tempDir.path);
    });

    tearDownAll(() async {
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    setUp(() async {
      box = await Hive.openBox<dynamic>('download_tasks');
      await box.clear();
    });

    test('save writes one key per row and keeps the legacy list readable',
        () async {
      final store = HiveDownloadTaskStore();
      final task = _completedTask('netease_s1_low', 'D:/Music/a.mp3');

      await store.save([task]);

      expect(
        box.get(HiveDownloadTaskStore.taskKey(task.id)),
        isA<Map<dynamic, dynamic>>(),
      );
      final legacy =
          box.get(HiveDownloadTaskStore.legacyTasksKey) as List<dynamic>;
      expect(legacy, hasLength(1));
      final row = legacy.single as Map<dynamic, dynamic>;
      expect(
        row['id'],
        task.id,
        reason: '旧版本仍要能读到这份库',
      );
    });

    test('save prunes the row keys of tasks that no longer exist', () async {
      final store = HiveDownloadTaskStore();
      final kept = _completedTask('netease_s1_low', 'D:/Music/a.mp3');
      final removed = _completedTask('netease_s2_low', 'D:/Music/b.mp3');

      await store.save([kept, removed]);
      await store.save([kept]);

      expect(
        box.get(HiveDownloadTaskStore.taskKey(removed.id)),
        isNull,
        reason: '被删除的行不得留在自己的键下',
      );
      expect(await store.load(), hasLength(1));
    });

    test('a progress-only save rewrites just the changed row', () async {
      final store = HiveDownloadTaskStore();
      final first = _completedTask('netease_s1_low', 'D:/Music/a.mp3');
      final second = _completedTask('netease_s2_low', 'D:/Music/b.mp3');
      await store.save([first, second]);
      final legacyBefore = box.get(HiveDownloadTaskStore.legacyTasksKey);

      // Hive reports one event per key it actually writes, which is the only
      // honest way to prove a row was *skipped* rather than rewritten with
      // identical content.
      //
      // Fallback if this ever turns flaky in CI (the delivery of `box.watch()`
      // events is asynchronous, hence the wait below): drop this event assertion
      // and keep the two content assertions — the legacy list is untouched and
      // the changed row carries the new byte count. That proves less (a skipped
      // row could have been rewritten with identical content) but does not
      // depend on event delivery.
      final written = <String>[];
      final subscription = box.watch().listen(
        (event) => written.add('${event.key}'),
      );
      addTearDown(subscription.cancel);

      // One row moves; the other is byte-for-byte what is already stored.
      await store.save([first.copyWith(downloadedBytes: 4096), second]);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(
        written,
        [HiveDownloadTaskStore.taskKey(first.id)],
        reason: '只有变化的那一行可以落盘；整份列表也不得被重写',
      );
      expect(
        box.get(HiveDownloadTaskStore.legacyTasksKey),
        legacyBefore,
        reason: '进度写不得触碰 legacy 列表',
      );
      final firstRow =
          box.get(HiveDownloadTaskStore.taskKey(first.id))
              as Map<dynamic, dynamic>;
      expect(firstRow['downloadedBytes'], 4096);
    });

    test('load prefers the per-row key over a stale legacy list', () async {
      final store = HiveDownloadTaskStore();
      final task = _completedTask('netease_s1_low', 'D:/Music/a.mp3');
      await store.save([task]);

      // What the legacy key would say if the app was killed after a full save but
      // before the status change landed: still `waiting`.
      await box.put(HiveDownloadTaskStore.legacyTasksKey, [
        task.copyWith(status: DownloadStatus.waiting).toJson(),
      ]);
      await box.put(
        HiveDownloadTaskStore.taskKey(task.id),
        task.copyWith(status: DownloadStatus.completed).toJson(),
      );

      final loaded = await store.load();
      expect(loaded.single.status, DownloadStatus.completed);
    });

    test('load keeps a row that only exists under its own key', () async {
      final store = HiveDownloadTaskStore();
      final task = _completedTask('netease_s1_low', 'D:/Music/a.mp3');
      await box.put(HiveDownloadTaskStore.taskKey(task.id), task.toJson());

      final loaded = await store.load();
      expect(loaded.map((t) => t.id), [task.id]);
    });
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

/// A finished row pointing at [filePath].
DownloadTask _completedTask(
  String id,
  String filePath, {
  bool isOfflineCache = false,
  AudioLevel quality = AudioLevel.low,
  int bytes = 10,
}) => DownloadTask(
  id: id,
  song: _song,
  quality: quality,
  status: DownloadStatus.completed,
  progress: 1,
  downloadedBytes: bytes,
  totalBytes: bytes,
  filePath: filePath,
  createdAt: DateTime(2026, 5, 29),
  completedAt: DateTime(2026, 5, 29),
  isOfflineCache: isOfflineCache,
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

  /// Emits a plain progress tick (no status change).
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
