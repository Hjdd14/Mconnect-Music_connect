import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/download/data/download_directory_service.dart';
import 'package:path/path.dart' as p;

/// The download-root guard, asserted through the **old public API only**.
///
/// This file exists on purpose: the rest of the guard tests
/// (`download_directory_service_test.dart`, `download_page_test.dart`) use the
/// new result/guard API, so they cannot even compile against the unfixed code.
/// Keeping the P0 assertions on `Future<bool> setCustomRootDirectory` means the
/// very same tests can be run before and after the fix — the recorded red run
/// shows the first one failing with
/// `FileSystemException: Cannot create file, path = '.../not_a_directory/sub'`.
void main() {
  late Directory tempDir;
  late _MemoryDownloadDirectoryStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mconnect_dir_guard_');
    store = _MemoryDownloadDirectoryStore();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  DownloadDirectoryService service() => DownloadDirectoryService(
    store: store,
    defaultRootProvider: () async => Directory(tempDir.path),
  );

  test('a path that cannot be created is rejected without throwing (P0)',
      () async {
    // `Directory.create(recursive: true)` cannot build a directory under a file.
    final blocker = File(p.join(tempDir.path, 'not_a_directory'));
    await blocker.writeAsString('x');

    await expectLater(
      service().setCustomRootDirectory(p.join(blocker.path, 'sub')),
      completion(isFalse),
      reason: 'the service must report the failure, never throw it',
    );
    expect(store.customRootPath, isNull);
  });

  test('nothing is persisted when the directory is rejected', () async {
    final blocker = File(p.join(tempDir.path, 'blocker'));
    await blocker.writeAsString('x');

    expect(await service().setCustomRootDirectory('   '), isFalse);
    expect(
      await service().setCustomRootDirectory(p.join(blocker.path, 'sub')),
      isFalse,
    );
    expect(store.customRootPath, isNull);
  });

  test('a writable temp directory is still accepted', () async {
    final root = Directory(p.join(tempDir.path, 'downloads'));

    expect(await service().setCustomRootDirectory(root.path), isTrue);
    expect(store.customRootPath, root.path);
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
