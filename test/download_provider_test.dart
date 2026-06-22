import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/download/data/download_directory_service.dart';
import 'package:mconnect/features/download/data/repositories/download_manager.dart';
import 'package:mconnect/features/download/data/download_task_store.dart';
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

  test('restores persisted downloads and normalizes active tasks', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'mconnect_restore_downloads_',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final existingFile = File(p.join(tempDir.path, 'existing.mp3'));
    await existingFile.writeAsString('audio bytes');
    final completed = DownloadTask(
      id: 'netease_s1_low',
      song: _song,
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
    final active = DownloadTask(
      id: 'netease_s2_low',
      song: const Song(
        id: 's2',
        platform: PlatformType.netease,
        name: 'Song 2',
        artists: [Artist(id: 'a1', name: 'Artist 1')],
      ),
      quality: AudioLevel.low,
      status: DownloadStatus.downloading,
      progress: 0.3,
      downloadedBytes: 3,
      totalBytes: 10,
      createdAt: DateTime(2026, 5, 29),
    );
    final failed = DownloadTask(
      id: 'netease_s3_low',
      song: const Song(
        id: 's3',
        platform: PlatformType.netease,
        name: 'Song 3',
        artists: [Artist(id: 'a1', name: 'Artist 1')],
      ),
      quality: AudioLevel.low,
      status: DownloadStatus.failed,
      error: 'timeout',
      createdAt: DateTime(2026, 5, 29),
    );
    final store = _MemoryDownloadTaskStore([
      completed,
      missingCompleted,
      active,
      failed,
    ]);

    final notifier = DownloadNotifier(taskStore: store);
    await notifier.ready;

    expect(notifier.state.tasks.map((task) => task.id), [
      completed.id,
      active.id,
      failed.id,
    ]);
    expect(notifier.state.tasks[0].status, DownloadStatus.completed);
    expect(notifier.state.tasks[1].status, DownloadStatus.paused);
    expect(notifier.state.tasks[2].status, DownloadStatus.failed);
    expect(notifier.state.tasks[2].error, 'timeout');
    expect(store.saved.single.map((task) => task.id), [
      completed.id,
      active.id,
      failed.id,
    ]);
  });

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
      final notifier = DownloadNotifier(taskStore: _MemoryDownloadTaskStore([]));

      final allowed = await notifier.checkVipForDownload(
        _kugouSong,
        AudioLevel.lossless,
      );

      expect(allowed, isTrue);
    },
  );
}

const _song = Song(
  id: 's1',
  platform: PlatformType.netease,
  name: 'Song 1',
  artists: [Artist(id: 'a1', name: 'Artist 1')],
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
