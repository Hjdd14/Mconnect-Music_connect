import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/download/data/download_directory_service.dart';
import 'package:mconnect/features/download/data/repositories/download_manager.dart';
import 'package:mconnect/features/download/domain/entities/download_task.dart';
import 'package:mconnect/features/download/presentation/providers/download_provider.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/platform/base/platform_registry.dart';
import 'package:mconnect/platform/kugou/kugou_api.dart';
import 'package:mconnect/platform/kugou/kugou_platform.dart';
import 'package:path/path.dart' as p;

void main() {
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
    final notifier = DownloadNotifier(
      manager: manager,
      initialState: DownloadState(tasks: [task]),
    );

    final removed = await notifier.removeTask(task.id);

    expect(removed, isTrue);
    expect(await file.exists(), isFalse);
    expect(notifier.state.tasks, isEmpty);
  });

  test(
    'Kugou concept VIP session allows lossless downloads through VIP gate',
    () async {
      PlatformRegistry.register(
        KugouPlatform(api: _ConceptVipSessionWithFreeVipInfoApi()),
      );
      final notifier = DownloadNotifier();

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
