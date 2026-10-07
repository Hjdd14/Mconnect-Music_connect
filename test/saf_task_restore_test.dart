import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/download/data/download_task_store.dart';
import 'package:mconnect/features/download/domain/entities/download_task.dart';
import 'package:mconnect/features/download/presentation/providers/download_provider.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

import 'download_fakes.dart';

/// A download published into the user's SAF folder is recorded as a
/// `content://` document URI, and the restore/playback code in
/// `download_provider.dart` used to treat every `filePath` as a real file path.
/// That made "downloaded into my own folder" songs disappear from the download
/// list after a restart (`File(contentUri).exists()` is always false, and
/// `_normalizeRestoredTask` then persisted the shortened list), and made offline
/// playback try to open a document URI as a path.
///
/// These tests pin the fixed behaviour, including the negative cases that must
/// NOT change: a plain path whose file is gone is still dropped on restore.
void main() {
  const song = Song(
    id: 's1',
    platform: PlatformType.netease,
    name: 'Song',
    artists: [Artist(id: 'a1', name: 'Artist')],
  );

  DownloadTask safTask({bool offlineCache = false, int totalBytes = 4096}) =>
      DownloadTask(
        id: offlineCache ? 'cache_netease_s1_low' : 'netease_s1_low',
        song: song,
        quality: AudioLevel.low,
        status: DownloadStatus.completed,
        progress: 1,
        downloadedBytes: totalBytes,
        totalBytes: totalBytes,
        filePath: 'content://tree/primary%3AMusic/document/song-id',
        createdAt: DateTime(2026, 10, 8),
        completedAt: DateTime(2026, 10, 8),
        isOfflineCache: offlineCache,
      );

  DownloadTask plainTask(String path) => DownloadTask(
    id: 'netease_s1_plain',
    song: song,
    quality: AudioLevel.low,
    status: DownloadStatus.completed,
    progress: 1,
    downloadedBytes: 3,
    totalBytes: 3,
    filePath: path,
    createdAt: DateTime(2026, 10, 8),
    completedAt: DateTime(2026, 10, 8),
  );

  group('restore', () {
    test('a completed SAF task survives a restart, and the list is not rewritten without it', () async {
      final store = _MemoryTaskStore([safTask()]);
      final notifier = DownloadNotifier(
        manager: FakeDownloadManager(),
        taskStore: store,
      );
      addTearDown(notifier.dispose);

      await notifier.ready;

      expect(notifier.state.tasks, hasLength(1));
      expect(notifier.state.tasks.single.status, DownloadStatus.completed);
      expect(
        notifier.state.tasks.single.filePath,
        'content://tree/primary%3AMusic/document/song-id',
      );
      expect(
        store.tasks,
        hasLength(1),
        reason: '恢复过程会持久化列表：任务一旦被丢就再也回不来',
      );
    });

    test('the document URI is never handed to the File existence probe', () async {
      final probed = <String>[];
      final notifier = DownloadNotifier(
        manager: FakeDownloadManager(),
        taskStore: _MemoryTaskStore([safTask()]),
        fileExists: (path) {
          probed.add(path);
          return false;
        },
      );
      addTearDown(notifier.dispose);

      await notifier.ready;

      expect(probed, isEmpty, reason: 'content:// 不能走 File(path).exists()');
      expect(notifier.state.tasks, hasLength(1));
    });

    test('a plain-path task whose file is gone is still dropped', () async {
      final missing = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'mconnect_missing_${DateTime.now().microsecondsSinceEpoch}.mp3',
      );
      expect(missing.existsSync(), isFalse);

      final notifier = DownloadNotifier(
        manager: FakeDownloadManager(),
        taskStore: _MemoryTaskStore([plainTask(missing.path)]),
      );
      addTearDown(notifier.dispose);

      await notifier.ready;

      expect(
        notifier.state.tasks,
        isEmpty,
        reason: '普通路径的既有行为必须保持不变',
      );
    });

    test('a plain-path task whose file exists is kept', () async {
      final tempDir = await Directory.systemTemp.createTemp('mconnect_restore_');
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      final file = File('${tempDir.path}${Platform.pathSeparator}song.mp3');
      await file.writeAsBytes([1, 2, 3]);

      final notifier = DownloadNotifier(
        manager: FakeDownloadManager(),
        taskStore: _MemoryTaskStore([plainTask(file.path)]),
      );
      addTearDown(notifier.dispose);

      await notifier.ready;

      expect(notifier.state.tasks, hasLength(1));
    });
  });

  group('offline playback path', () {
    test('a SAF download is never returned as a playable file path', () async {
      final notifier = DownloadNotifier(
        manager: FakeDownloadManager(),
        initialState: DownloadState(tasks: [safTask()]),
        taskStore: _MemoryTaskStore([safTask()]),
      );
      addTearDown(notifier.dispose);
      await notifier.ready;

      expect(
        await notifier.localFilePathFor(song),
        isNull,
        reason: 'content:// 不是播放路径，宁可回退在线流',
      );
    });

    test('a plain-path download is still returned', () async {
      final tempDir = await Directory.systemTemp.createTemp('mconnect_played_');
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      final file = File('${tempDir.path}${Platform.pathSeparator}song.mp3');
      await file.writeAsBytes([1, 2, 3]);
      final task = plainTask(file.path);

      final notifier = DownloadNotifier(
        manager: FakeDownloadManager(),
        initialState: DownloadState(tasks: [task]),
        taskStore: _MemoryTaskStore([task]),
      );
      addTearDown(notifier.dispose);
      await notifier.ready;

      expect(await notifier.localFilePathFor(song), file.path);
    });
  });

  group('cache accounting', () {
    test('a SAF cache row is counted with the size the app recorded', () async {
      final task = safTask(offlineCache: true, totalBytes: 8192);
      final notifier = DownloadNotifier(
        manager: FakeDownloadManager(),
        initialState: DownloadState(tasks: [task]),
        taskStore: _MemoryTaskStore([task]),
      );
      addTearDown(notifier.dispose);
      await notifier.ready;

      // `File(contentUri).length()` cannot work; the recorded total is what was
      // actually written and size-verified before the copy.
      expect(await notifier.refreshCacheUsage(), 8192);
      expect(notifier.state.offlineCacheBytes, 8192);
    });
  });
}

class _MemoryTaskStore implements DownloadTaskStore {
  _MemoryTaskStore(this.tasks);

  List<DownloadTask> tasks;

  @override
  Future<List<DownloadTask>> load() async => tasks;

  @override
  Future<void> save(List<DownloadTask> saved) async => tasks = saved;
}
