import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../models/audio_quality.dart';
import '../../../models/platform_type.dart';
import '../domain/entities/download_failure.dart';
import 'saf_download_writer.dart';
import 'saf_tree_store.dart';

typedef DefaultDownloadRootProvider = Future<Directory> Function();

/// Where the app-private **external** download root lives.
///
/// Android-only in practice (`getExternalStorageDirectory()` is null elsewhere);
/// returns `null` when the platform has no such directory.
typedef ExternalDownloadRootProvider = Future<Directory?> Function();

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

/// Why a directory was rejected as the download root.
///
/// The old API returned a bare `bool`, so the UI could only say "该目录不可用" —
/// and, worse, the failure itself came out as an uncaught `PathAccessException`
/// from `Directory.create`, freezing the settings sheet at "保存中".
enum DownloadRootRejection {
  /// Empty / whitespace-only path.
  blankPath,

  /// `/`, `C:\`, … — a filesystem root is never a place to dump downloads.
  filesystemRoot,

  /// The path exists but is a file, not a directory.
  notADirectory,

  /// The directory could not be created (permissions, missing parent, …).
  notCreatable,

  /// The directory exists but the write probe failed — this is the case that
  /// used to reach `Directory.create` and throw.
  notWritable,

  /// The directory is usable but persisting the choice failed.
  storeFailed,

  /// The user closed the picker without choosing. Not a failure: the UI stays
  /// silent, exactly like the `null` a cancelled `file_picker` returns.
  cancelled;

  /// User-facing reason. The two "cannot write there" cases share one message:
  /// the distinction is a diagnostic detail, not something a user acts on
  /// differently.
  String get message => switch (this) {
    DownloadRootRejection.cancelled => '',
    DownloadRootRejection.blankPath => '请选择有效的下载目录',
    DownloadRootRejection.filesystemRoot => '不能把磁盘根目录设为下载目录',
    DownloadRootRejection.notADirectory => '该路径不是文件夹，请重新选择',
    DownloadRootRejection.notCreatable ||
    DownloadRootRejection.notWritable => '该目录不可写，请选择应用可写的位置',
    DownloadRootRejection.storeFailed => '保存下载目录设置失败，请重试',
  };
}

/// Where the bytes of one download go, and what has to happen afterwards.
///
/// Three cases instead of a `Directory`, because "a SAF folder is configured but
/// its grant is gone" must **fail** rather than quietly land in the default
/// folder: a user who believes the file is in their own `Music` folder and finds
/// it in the app sandbox is worse off than one who sees an error.
sealed class DownloadDestination {
  const DownloadDestination();
}

/// No SAF folder configured — the pre-existing filesystem behaviour.
class FileSystemDownloadDestination extends DownloadDestination {
  const FileSystemDownloadDestination(this.directory);

  final Directory directory;
}

/// SAF folder configured and writable: write into [stagingDirectory] with the
/// existing resumable pipeline, then copy into the tree.
class SafDownloadDestination extends DownloadDestination {
  const SafDownloadDestination({
    required this.stagingDirectory,
    required this.relativePath,
    required this.treeName,
  });

  final Directory stagingDirectory;

  /// Sub-path inside the tree (`netease/mp3`, mirroring the sandbox layout).
  final String relativePath;

  /// Display name of the chosen folder, for messages.
  final String treeName;
}

/// SAF folder configured but unusable — the caller must report, not fall back.
class UnusableDownloadDestination extends DownloadDestination {
  const UnusableDownloadDestination(this.failure);

  final DownloadFailure failure;
}

/// Outcome of trying to use a directory as the download root.
class DownloadRootResult {
  /// True when [path] is now the download root.
  final bool isOk;

  /// The usable (normalized) path — or the SAF tree URI — or null on failure.
  final String? path;

  /// Display name for a SAF folder (null for plain paths).
  final String? displayName;

  /// Why it failed; null on success.
  final DownloadRootRejection? rejection;

  /// Technical detail (OS error text) for logs/diagnostics.
  final String? detail;

  const DownloadRootResult.success(String this.path, {this.displayName})
    : isOk = true,
      rejection = null,
      detail = null;

  const DownloadRootResult.failure(this.rejection, {this.detail})
    : isOk = false,
      path = null,
      displayName = null;

  /// The user closed the picker: not an error, so the UI stays silent.
  bool get isCancelled => rejection == DownloadRootRejection.cancelled;

  /// Message to show the user.
  String get message => isOk
      ? '下载目录已更新'
      : (rejection ?? DownloadRootRejection.notWritable).message;

  @override
  String toString() =>
      'DownloadRootResult(${isOk ? 'ok' : rejection?.name}: '
      '${displayName ?? path}$detail)';
}

/// One entry in the "download directory" picker.
///
/// The picker offers a **known-writable set** instead of a free-form path: the
/// app's own documents directory and the app-specific external directory. Both
/// need no runtime permission and survive as long as the app is installed.
class DownloadRootOption {
  final DownloadRootKind kind;

  /// Absolute directory path.
  final String path;

  /// Whether this is the currently configured root.
  final bool isCurrent;

  const DownloadRootOption({
    required this.kind,
    required this.path,
    required this.isCurrent,
  });
}

enum DownloadRootKind {
  /// `<app documents>/downloads` — private, removed with the app.
  appDocuments('默认位置', '应用私有目录，卸载应用时一并删除'),

  /// `<app-specific external>/downloads` — Android 10+ needs no permission.
  appExternal('外部存储（应用专属）', 'Android 10+ 无需权限，系统清理时可能被删除'),

  /// Anything the user picked by hand (may be unwritable → the guard applies).
  custom('自定义位置', '你选择的目录，可能不可写');

  final String label;
  final String description;
  const DownloadRootKind(this.label, this.description);
}

/// The filesystem operations the root guard performs.
///
/// Injectable so the guard can be unit-tested — including the unwritable case —
/// without touching a real disk.
class DownloadDirectoryGuard {
  const DownloadDirectoryGuard();

  /// Name of the temporary file written by [verifyWritable].
  static const probeFileName = '.mconnect_write_probe';

  Future<bool> exists(Directory directory) => directory.exists();

  Future<void> create(Directory directory) =>
      directory.create(recursive: true);

  /// True when the path is a directory (not a file that merely exists there).
  Future<bool> isDirectory(Directory directory) =>
      FileSystemEntity.isDirectory(directory.path);

  /// Creates and removes a probe file inside [directory], proving the app can
  /// actually write there.
  Future<void> verifyWritable(Directory directory) async {
    final probe = File(p.join(directory.path, probeFileName));
    try {
      await probe.writeAsString('mconnect', flush: true);
    } finally {
      // Never leave the probe behind; a failed delete still proves writability.
      try {
        if (await probe.exists()) await probe.delete();
      } catch (_) {}
    }
  }
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
  final ExternalDownloadRootProvider _externalRootProvider;
  final DownloadDirectoryGuard guard;
  final SafDownloadWriter safWriter;

  DownloadDirectoryService({
    DownloadDirectoryStore? store,
    DefaultDownloadRootProvider? defaultRootProvider,
    ExternalDownloadRootProvider? externalRootProvider,
    DownloadDirectoryGuard? guard,
    SafDownloadWriter? safWriter,
  }) : store = store ?? HiveDownloadDirectoryStore(),
       _defaultRootProvider =
           defaultRootProvider ?? getApplicationDocumentsDirectory,
       _externalRootProvider = externalRootProvider ?? _defaultExternalRoot,
       guard = guard ?? const DownloadDirectoryGuard(),
       safWriter = safWriter ?? SafDownloadWriter();

  /// `getExternalStorageDirectory()` is Android-only; everywhere else this is
  /// null and the picker simply offers one fewer option.
  static Future<Directory?> _defaultExternalRoot() async {
    if (!Platform.isAndroid) return null;
    try {
      final directory = await getExternalStorageDirectory();
      if (directory == null) return null;
      return Directory(p.join(directory.path, 'downloads'));
    } catch (error) {
      // Some Android builds / emulator images do not expose it.
      debugPrint('external storage directory unavailable: $error');
      return null;
    }
  }

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

  /// The directories the settings sheet offers: the two app-owned roots that are
  /// writable without any runtime permission.
  ///
  /// Deliberately does **no I/O** (no `exists()`), so the sheet can render
  /// synchronously on a device where the paths are slow or missing — and it
  /// never throws: a provider that fails (or Hive being closed) costs the user
  /// one option, not the whole sheet.
  Future<List<DownloadRootOption>> availableRootOptions() async {
    String? current;
    try {
      current = _validRootPathOrNull(await store.readCustomRootPath());
    } catch (error) {
      debugPrint('download root store read failed: $error');
    }
    final options = <DownloadRootOption>[];

    try {
      final documents = p.normalize(
        p.join((await _defaultRootProvider()).path, 'downloads'),
      );
      options.add(
        DownloadRootOption(
          kind: DownloadRootKind.appDocuments,
          path: documents,
          isCurrent: current == null || p.equals(current, documents),
        ),
      );
    } catch (error) {
      debugPrint('default download root unavailable: $error');
    }

    try {
      final external = await _externalRootProvider();
      if (external != null) {
        final externalPath = p.normalize(external.path);
        options.add(
          DownloadRootOption(
            kind: DownloadRootKind.appExternal,
            path: externalPath,
            isCurrent: current != null && p.equals(current, externalPath),
          ),
        );
      }
    } catch (error) {
      debugPrint('external download root unavailable: $error');
    }
    return options;
  }

  /// Makes [path] the download root, **never throwing**.
  ///
  /// Before this, an unwritable path threw `PathAccessException` out of
  /// `Directory.create` — an uncaught async error — and the caller's
  /// `isSaving` flag was never reset, so the sheet stayed stuck on "保存中".
  ///
  /// The path must pass a real **write probe**: creating a directory is not
  /// proof that the app may write files into it (Android 11+ returns an existing
  /// directory for several protected locations).
  Future<DownloadRootResult> applyCustomRootDirectory(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return const DownloadRootResult.failure(
        DownloadRootRejection.blankPath,
      );
    }
    final normalized = _validRootPathOrNull(trimmed);
    if (normalized == null) {
      return const DownloadRootResult.failure(
        DownloadRootRejection.filesystemRoot,
      );
    }

    final directory = Directory(normalized);
    try {
      if (await guard.exists(directory)) {
        if (!await guard.isDirectory(directory)) {
          return const DownloadRootResult.failure(
            DownloadRootRejection.notADirectory,
          );
        }
      } else {
        await guard.create(directory);
      }
    } on Object catch (error) {
      return DownloadRootResult.failure(
        DownloadRootRejection.notCreatable,
        detail: error.toString(),
      );
    }

    try {
      await guard.verifyWritable(directory);
    } on Object catch (error) {
      return DownloadRootResult.failure(
        DownloadRootRejection.notWritable,
        detail: error.toString(),
      );
    }

    try {
      await store.saveCustomRootPath(directory.path);
    } on Object catch (error) {
      return DownloadRootResult.failure(
        DownloadRootRejection.storeFailed,
        detail: error.toString(),
      );
    }

    return DownloadRootResult.success(directory.path);
  }

  /// `bool` view of [applyCustomRootDirectory].
  ///
  /// Kept because `DownloadManager` exposes this signature; it discards the
  /// rejection reason, so callers that need to tell the user **why** must use
  /// [applyCustomRootDirectory].
  Future<bool> setCustomRootDirectory(String path) async =>
      (await applyCustomRootDirectory(path)).isOk;

  Future<void> resetCustomRootDirectory() => store.clearCustomRootPath();

  // --- SAF custom folder ------------------------------------------------------

  /// The folder the user granted through SAF, or null when none is configured.
  Future<SafTreeSelection?> currentTreeSelection() => safWriter.currentSelection();

  /// Whether downloads currently target a SAF folder (as opposed to a plain
  /// filesystem path).
  Future<bool> isSafTarget() async =>
      await safWriter.targetState() == SafTargetState.ready;

  /// Resolves where one download's bytes go.
  ///
  /// * **No SAF folder** → `targetDirectory(...)`, byte for byte the old
  ///   behaviour (this is the branch every existing install takes);
  /// * **SAF folder, grant alive** → the staging directory plus the sub-path to
  ///   copy into afterwards;
  /// * **SAF folder, grant gone** → an [UnusableDownloadDestination] carrying a
  ///   [DownloadFailureKind.storagePermission] failure. The caller reports it
  ///   and stops; it must not fall back to another folder.
  ///
  /// [create] is false for path *resolution* (see `DownloadManager`), where
  /// creating a directory would be an unwanted side effect.
  Future<DownloadDestination> resolveDownloadDestination(
    PlatformType platformType,
    AudioLevel quality, {
    bool create = true,
  }) async {
    final state = await safWriter.targetState();
    switch (state) {
      case SafTargetState.notConfigured:
        return FileSystemDownloadDestination(
          await targetDirectory(platformType, quality, create: create),
        );
      case SafTargetState.permissionLost:
        return const UnusableDownloadDestination(
          DownloadFailure(
            kind: DownloadFailureKind.storagePermission,
            message: '自定义下载目录的访问权限已失效，请在下载设置中重新选择目录',
          ),
        );
      case SafTargetState.ready:
        final selection = await safWriter.currentSelection();
        return SafDownloadDestination(
          stagingDirectory: await safWriter.stagingDirectory(create: create),
          // `平台/音质`, mirroring the sandbox layout. Approved as-is for
          // v1.4.1: a provider that refuses to create these sub-directories
          // surfaces `CREATE_DIR_FAILED` (classified `unknown`, not auto-retried)
          // and flattening to the tree root is a decision for after a real-device
          // report, not a guess made now.
          relativePath:
              '${platformType.name}/${quality.isLossless ? 'flac' : 'mp3'}',
          treeName: selection?.name ?? '自定义目录',
        );
    }
  }

  /// Opens the SAF folder picker and makes the result the download root.
  ///
  /// Never throws (same contract as [applyCustomRootDirectory]): a cancelled
  /// picker and a refused grant both come back as a [DownloadRootResult]. The
  /// legacy plain path is deliberately **left in place** — switching to a SAF
  /// folder must not destroy the directory an earlier build saved, so switching
  /// back to "默认位置" still works after a reset.
  Future<DownloadRootResult> applySafTreeDirectory() async {
    try {
      final selection = await safWriter.pickDirectory();
      if (selection == null) {
        return const DownloadRootResult.failure(
          DownloadRootRejection.cancelled,
        );
      }
      return DownloadRootResult.success(selection.uri, displayName: selection.name);
    } on SafDownloadException catch (error) {
      return DownloadRootResult.failure(
        DownloadRootRejection.notWritable,
        detail: error.failure.detail ?? error.failure.message,
      );
    } on Object catch (error) {
      return DownloadRootResult.failure(
        DownloadRootRejection.notWritable,
        detail: error.toString(),
      );
    }
  }

  /// Stops using the SAF folder: releases the platform grant and forgets it.
  ///
  /// The legacy `custom_root_path` is untouched, so the plain-path behaviour
  /// comes straight back.
  Future<void> resetSafTreeDirectory() => safWriter.clear();

  /// Opens the configured SAF folder in a file manager, if one accepts it.
  Future<bool> openSafDirectory() => safWriter.openDirectory();


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
