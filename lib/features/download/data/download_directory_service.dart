import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../models/audio_quality.dart';
import '../../../models/platform_type.dart';

typedef DefaultDownloadRootProvider = Future<Directory> Function();

/// Extracts the Android API level from `Platform.operatingSystemVersion`.
///
/// Example input: `"Android 13, API level 33, build/TQ1A.230205.002"`.
/// Returns `null` when the string is not an Android one (or is shaped
/// differently), which callers must read as "unknown", not as a level.
int? androidApiLevelFrom(String operatingSystemVersion) {
  final match = RegExp(r'API level (\d+)').firstMatch(operatingSystemVersion);
  final raw = match?.group(1);
  if (raw == null) return null;
  return int.tryParse(raw);
}

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

  /// Whether the legacy `Permission.storage` request is both **needed** and
  /// **meaningful** for [target].
  ///
  /// Two reasons it usually is not:
  /// * the default root (`<app documents>/downloads`) lives inside the app
  ///   sandbox, which needs no permission at all — asking for it there only
  ///   produces a prompt (or, worse, a denial that fails the download);
  /// * on Android 13+ (API 33) `Permission.storage` can never be granted;
  ///   scoped storage replaced it, and a non-sandbox directory has to go
  ///   through SAF (`takePersistableUriPermission`), which this build does not
  ///   implement — the write itself then fails with EACCES and is classified as
  ///   [DownloadFailureKind.storagePermission].
  Future<bool> needsLegacyStoragePermission(Directory target) async {
    if (!Platform.isAndroid) return false;
    final apiLevel = androidApiLevelFrom(Platform.operatingSystemVersion);
    if (apiLevel != null && apiLevel >= 33) return false;
    final sandbox = await _defaultRootProvider();
    final targetPath = p.normalize(target.absolute.path);
    final sandboxPath = p.normalize(sandbox.absolute.path);
    if (p.equals(targetPath, sandboxPath)) return false;
    return !p.isWithin(sandboxPath, targetPath);
  }

  String? _validRootPathOrNull(String? path) {
    final trimmed = path?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    final normalized = p.normalize(trimmed);
    final root = p.rootPrefix(normalized);
    if (normalized == root || normalized == p.separator) return null;
    return normalized;
  }
}
