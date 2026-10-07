import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/download/data/download_directory_service.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late _MemoryDownloadDirectoryStore store;

  /// Every guarded case injects its own in-memory guard: the whole point of the
  /// fix is that an unwritable directory must not be probed by touching a real
  /// disk in a test.
  DownloadDirectoryService serviceWith(DownloadDirectoryGuard guard) =>
      DownloadDirectoryService(
        store: store,
        defaultRootProvider: () async => Directory('/app_docs'),
        externalRootProvider: () async => null,
        guard: guard,
      );

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

  // ---- v1.4.1 guard: an unusable directory must never throw ----------------
  //
  // Every case below drives an injected guard, so no test touches a real disk
  // (the bug being fixed was an exception escaping `Directory.create`).
  // The one assertion that stays on the *old* public API — and can therefore be
  // run against the unfixed code to prove the bug — lives in
  // `download_directory_probe_test.dart`.

  group('unwritable directory guard', () {
    test('an unwritable directory is rejected, with a reason, without throwing',
        () async {
      final guard = _FakeGuard(
        dirExists: true,
        writeError: const FileSystemException(
          'Cannot write to the directory',
          '/readonly/music',
          OSError('Permission denied', 13),
        ),
      );
      final service = serviceWith(guard);

      final result = await service.applyCustomRootDirectory('/readonly/music');

      expect(result.isOk, isFalse);
      expect(result.rejection, DownloadRootRejection.notWritable);
      expect(
        result.message,
        '该目录不可写，请选择应用可写的位置',
        reason: 'the user must be told why nothing happened',
      );
      expect(result.detail, contains('Permission denied'));
      // The bad path must not be persisted.
      expect(store.customRootPath, isNull);
      // The legacy bool view agrees.
      expect(await service.setCustomRootDirectory('/readonly/music'), isFalse);
      expect(store.customRootPath, isNull);
    });

    test('a directory that cannot be created is rejected', () async {
      final guard = _FakeGuard(
        dirExists: false,
        createError: const FileSystemException(
          'Creation failed',
          '/nope/music',
          OSError('Permission denied', 13),
        ),
      );
      final service = serviceWith(guard);

      final result = await service.applyCustomRootDirectory('/nope/music');

      expect(result.isOk, isFalse);
      expect(result.rejection, DownloadRootRejection.notCreatable);
      expect(result.message, '该目录不可写，请选择应用可写的位置');
      expect(store.customRootPath, isNull);
    });

    test('a file at the chosen path is rejected as not-a-directory', () async {
      final guard = _FakeGuard(dirExists: true, isDir: false);
      final service = serviceWith(guard);

      final result = await service.applyCustomRootDirectory('/tmp/afile.mp3');

      expect(result.isOk, isFalse);
      expect(result.rejection, DownloadRootRejection.notADirectory);
      expect(store.customRootPath, isNull);
    });

    test('blank and root paths carry their own reasons', () async {
      final service = serviceWith(_FakeGuard());

      expect(
        (await service.applyCustomRootDirectory('   ')).rejection,
        DownloadRootRejection.blankPath,
      );
      expect(
        (await service.applyCustomRootDirectory('/')).rejection,
        DownloadRootRejection.filesystemRoot,
      );
      expect(store.customRootPath, isNull);
    });

    test('a store failure is reported instead of escaping', () async {
      final exploding = _MemoryDownloadDirectoryStore()..saveError = true;
      final service = DownloadDirectoryService(
        store: exploding,
        defaultRootProvider: () async => Directory(tempDir.path),
        externalRootProvider: () async => null,
        guard: _FakeGuard(dirExists: true),
      );

      final result = await service.applyCustomRootDirectory('/music');

      expect(result.isOk, isFalse);
      expect(result.rejection, DownloadRootRejection.storeFailed);
    });

    test('a writable directory is accepted, normalized and persisted', () async {
      final guard = _FakeGuard(dirExists: true);
      final service = serviceWith(guard);

      final result = await service.applyCustomRootDirectory(' /music/../music ');

      expect(result.isOk, isTrue);
      expect(result.path, p.normalize('/music'));
      expect(store.customRootPath, p.normalize('/music'));
      expect(guard.created, isEmpty, reason: 'an existing dir is not recreated');
    });

    test('a missing but creatable directory is created then probed', () async {
      final guard = _FakeGuard(dirExists: false);
      final service = serviceWith(guard);

      final result = await service.applyCustomRootDirectory('/fresh/dir');

      expect(result.isOk, isTrue);
      expect(guard.created, [p.normalize('/fresh/dir')]);
      expect(store.customRootPath, p.normalize('/fresh/dir'));
    });
  });

  group('the real write probe', () {
    const guard = DownloadDirectoryGuard();

    test('creates and removes its probe file', () async {
      final directory = Directory(p.join(tempDir.path, 'writable'));
      await directory.create(recursive: true);

      await guard.verifyWritable(directory);

      expect(
        await File(
          p.join(directory.path, DownloadDirectoryGuard.probeFileName),
        ).exists(),
        isFalse,
        reason: 'the probe must not be left behind',
      );
    });

    test('fails for a directory that does not exist', () async {
      final missing = Directory(p.join(tempDir.path, 'does_not_exist'));

      await expectLater(
        guard.verifyWritable(missing),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('available root options', () {
    test('offers the app documents root and the app-specific external root',
        () async {
      final appDocs = Directory(p.join(tempDir.path, 'app_docs'));
      final external = Directory(p.join(tempDir.path, 'ext', 'downloads'));
      final service = DownloadDirectoryService(
        store: store,
        defaultRootProvider: () async => appDocs,
        externalRootProvider: () async => external,
        guard: _FakeGuard(dirExists: true),
      );

      final options = await service.availableRootOptions();

      expect(
        options.map((option) => option.kind),
        [DownloadRootKind.appDocuments, DownloadRootKind.appExternal],
      );
      expect(
        options.map((option) => option.path),
        [p.join(appDocs.path, 'downloads'), external.path],
      );
      expect(options.first.isCurrent, isTrue);
      expect(options.last.isCurrent, isFalse);

      // Once the external root is chosen it becomes the current one.
      await service.applyCustomRootDirectory(external.path);
      final refreshed = await service.availableRootOptions();
      expect(refreshed.first.isCurrent, isFalse);
      expect(refreshed.last.isCurrent, isTrue);
    });

    test('omits the external root when the platform has none', () async {
      final service = DownloadDirectoryService(
        store: store,
        defaultRootProvider: () async => Directory(tempDir.path),
        externalRootProvider: () async => null,
        guard: _FakeGuard(dirExists: true),
      );

      final options = await service.availableRootOptions();

      expect(options, hasLength(1));
      expect(options.single.kind, DownloadRootKind.appDocuments);
    });
  });
}

/// A guard that answers from memory and can be told to fail, so the guard tests
/// never touch the filesystem.
class _FakeGuard implements DownloadDirectoryGuard {
  _FakeGuard({
    this.dirExists = false,
    this.isDir = true,
    this.createError,
    this.writeError,
  });

  bool dirExists;
  bool isDir;
  Object? createError;
  Object? writeError;
  final List<String> created = <String>[];

  @override
  Future<bool> exists(Directory directory) async => dirExists;

  @override
  Future<bool> isDirectory(Directory directory) async => isDir;

  @override
  Future<void> create(Directory directory) async {
    if (createError != null) throw createError!;
    created.add(p.normalize(directory.path));
    dirExists = true;
  }

  @override
  Future<void> verifyWritable(Directory directory) async {
    if (writeError != null) throw writeError!;
  }
}


class _MemoryDownloadDirectoryStore implements DownloadDirectoryStore {
  String? customRootPath;

  /// Makes [saveCustomRootPath] throw, to prove the service reports it instead
  /// of letting it escape.
  bool saveError = false;

  @override
  Future<void> clearCustomRootPath() async {
    customRootPath = null;
  }

  @override
  Future<String?> readCustomRootPath() async => customRootPath;

  @override
  Future<void> saveCustomRootPath(String path) async {
    if (saveError) {
      throw const FileSystemException('store closed', 'download_settings');
    }
    customRootPath = path;
  }
}
