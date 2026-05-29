import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/download/data/download_directory_service.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late _MemoryDownloadDirectoryStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mconnect_download_dir_');
    store = _MemoryDownloadDirectoryStore();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('uses app documents downloads directory by default', () async {
    final appDocs = Directory(p.join(tempDir.path, 'app_docs'));
    final service = DownloadDirectoryService(
      store: store,
      defaultRootProvider: () async => appDocs,
    );

    final root = await service.currentRootDirectory();
    final target = await service.targetDirectory(
      PlatformType.netease,
      AudioLevel.lossless,
    );

    expect(root.path, p.join(appDocs.path, 'downloads'));
    expect(target.path, p.join(appDocs.path, 'downloads', 'netease', 'flac'));
    expect(await target.exists(), isTrue);
  });

  test('persists custom root directory and can reset to default', () async {
    final appDocs = Directory(p.join(tempDir.path, 'app_docs'));
    final customRoot = Directory(p.join(tempDir.path, 'music_downloads'));
    final service = DownloadDirectoryService(
      store: store,
      defaultRootProvider: () async => appDocs,
    );

    final saved = await service.setCustomRootDirectory(customRoot.path);
    final target = await service.targetDirectory(
      PlatformType.qq,
      AudioLevel.low,
    );

    expect(saved, isTrue);
    expect(store.customRootPath, customRoot.path);
    expect(target.path, p.join(customRoot.path, 'qq', 'mp3'));

    await service.resetCustomRootDirectory();

    final resetRoot = await service.currentRootDirectory();
    expect(store.customRootPath, isNull);
    expect(resetRoot.path, p.join(appDocs.path, 'downloads'));
  });

  test('rejects empty and filesystem root custom directories', () async {
    final service = DownloadDirectoryService(
      store: store,
      defaultRootProvider: () async => Directory(p.join(tempDir.path, 'docs')),
    );

    expect(await service.setCustomRootDirectory(''), isFalse);
    expect(await service.setCustomRootDirectory('   '), isFalse);
    expect(await service.setCustomRootDirectory('/'), isFalse);
    expect(store.customRootPath, isNull);
  });
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
