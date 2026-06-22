import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../models/audio_quality.dart';
import '../../../models/platform_type.dart';

typedef DefaultDownloadRootProvider = Future<Directory> Function();

abstract class DownloadDirectoryStore {
  Future<String?> readCustomRootPath();
  Future<void> saveCustomRootPath(String path);
  Future<void> clearCustomRootPath();
}

class HiveDownloadDirectoryStore implements DownloadDirectoryStore {
  static const _boxName = 'download_settings';
  static const _customRootPathKey = 'custom_root_path';

  Future<Box> _box() => Hive.openBox(_boxName);

  @override
  Future<String?> readCustomRootPath() async {
    final box = await _box();
    final value = box.get(_customRootPathKey);
    return value is String ? value : null;
  }

  @override
  Future<void> saveCustomRootPath(String path) async {
    final box = await _box();
    await box.put(_customRootPathKey, path);
  }

  @override
  Future<void> clearCustomRootPath() async {
    final box = await _box();
    await box.delete(_customRootPathKey);
  }
}

class DownloadDirectoryService {
  final DownloadDirectoryStore store;
  final DefaultDownloadRootProvider _defaultRootProvider;

  DownloadDirectoryService({
    DownloadDirectoryStore? store,
    DefaultDownloadRootProvider? defaultRootProvider,
  }) : store = store ?? HiveDownloadDirectoryStore(),
       _defaultRootProvider =
           defaultRootProvider ?? getApplicationDocumentsDirectory;

  Future<Directory> currentRootDirectory({bool create = true}) async {
    final customRoot = await store.readCustomRootPath();
    final path = _validRootPathOrNull(customRoot);
    final dir = path != null
        ? Directory(path)
        : Directory(p.join((await _defaultRootProvider()).path, 'downloads'));
    if (create && !await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> targetDirectory(
    PlatformType platformType,
    AudioLevel quality, {
    bool create = true,
  }) async {
    final root = await currentRootDirectory(create: create);
    final dir = Directory(
      p.join(root.path, platformType.name, quality.isLossless ? 'flac' : 'mp3'),
    );
    if (create && !await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<bool> setCustomRootDirectory(String path) async {
    final normalized = _validRootPathOrNull(path);
    if (normalized == null) return false;
    final dir = Directory(normalized);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await store.saveCustomRootPath(dir.path);
    return true;
  }

  Future<void> resetCustomRootDirectory() => store.clearCustomRootPath();

  String? _validRootPathOrNull(String? path) {
    final trimmed = path?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    final normalized = p.normalize(trimmed);
    final root = p.rootPrefix(normalized);
    if (normalized == root || normalized == p.separator) return null;
    return normalized;
  }
}
