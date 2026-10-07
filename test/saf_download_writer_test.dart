import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/download/data/saf_document_tree.dart';
import 'package:mconnect/features/download/data/saf_download_writer.dart';
import 'package:mconnect/features/download/data/saf_tree_store.dart';
import 'package:mconnect/features/download/domain/entities/download_failure.dart';

/// A SAF tree that records what it was asked to do.
///
/// The interesting fields are mutable and set per test, which keeps each case
/// to the one line that differs from the happy path.
class _FakeTree implements SafDocumentTree {
  _FakeTree({this.pickError});

  bool granted = true;
  int? writtenBytes;
  String? displayName;
  SafDocumentTreeException? copyError;
  SafTreeSelection? pickResult;
  SafDocumentTreeException? pickError;
  bool openResult = true;
  SafDocumentTreeException? openError;

  int pickCalls = 0;
  int grantChecks = 0;
  int releaseCalls = 0;
  int openCalls = 0;
  final List<Map<String, Object?>> copyCalls = [];

  @override
  Future<SafTreeSelection?> pickDirectory() async {
    pickCalls++;
    if (pickError != null) throw pickError!;
    return pickResult;
  }

  @override
  Future<bool> isGranted(String treeUri) async {
    grantChecks++;
    return granted;
  }

  @override
  Future<bool> release(String treeUri) async {
    releaseCalls++;
    return true;
  }

  @override
  Future<SafCopyResult> copyToTree({
    required String treeUri,
    required String relativePath,
    required String fileName,
    required String sourcePath,
  }) async {
    copyCalls.add({
      'treeUri': treeUri,
      'relativePath': relativePath,
      'fileName': fileName,
      'sourcePath': sourcePath,
    });
    if (copyError != null) throw copyError!;
    return SafCopyResult(
      bytes: writtenBytes ?? File(sourcePath).lengthSync(),
      uri: '$treeUri/document/$fileName',
      displayName: displayName ?? fileName,
    );
  }

  @override
  Future<bool> openTree(String treeUri) async {
    openCalls++;
    if (openError != null) throw openError!;
    return openResult;
  }
}

/// A tree whose grant check fails the way an unsupported platform does.
class _ThrowingGrantTree implements SafDocumentTree {
  @override
  Future<bool> isGranted(String treeUri) async => throw const SafDocumentTreeException(
    SafErrorCodes.treeUnavailable,
    '当前平台不支持自定义目录（SAF）',
  );

  @override
  Future<SafCopyResult> copyToTree({
    required String treeUri,
    required String relativePath,
    required String fileName,
    required String sourcePath,
  }) async => throw UnimplementedError('copyToTree must not be reached');

  @override
  Future<SafTreeSelection?> pickDirectory() async => throw UnimplementedError();

  @override
  Future<bool> release(String treeUri) async => throw UnimplementedError();

  @override
  Future<bool> openTree(String treeUri) async => throw UnimplementedError();
}

void main() {
  late Directory tempDir;
  late File staging;
  late _FakeTree tree;
  late MemorySafTreeStore store;

  const treeUri = 'content://com.android.externalstorage.documents/tree/primary%3AMusic';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mconnect_saf_writer_');
    staging = File('${tempDir.path}${Platform.pathSeparator}song.mp3');
    await staging.writeAsBytes(List<int>.filled(8, 7));
    tree = _FakeTree();
    store = MemorySafTreeStore(
      SafTreeSelection(uri: treeUri, name: 'Music', grantedAt: DateTime(2026)),
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  SafDownloadWriter writer() => SafDownloadWriter(
    tree: tree,
    store: store,
    stagingDirectoryProvider: () async => tempDir,
  );

  test('a successful commit copies, verifies the size and removes the staging file', () async {
    final result = await writer().commit(
      stagingFile: staging,
      relativePath: 'netease/mp3',
      fileName: 'song.mp3',
    );

    expect(tree.copyCalls, hasLength(1));
    expect(tree.copyCalls.single['treeUri'], treeUri);
    expect(tree.copyCalls.single['relativePath'], 'netease/mp3');
    expect(tree.copyCalls.single['fileName'], 'song.mp3');
    expect(tree.copyCalls.single['sourcePath'], staging.path);

    expect(result.bytes, 8);
    expect(result.documentUri, '$treeUri/document/song.mp3');
    expect(result.stagingRemoved, isTrue);
    expect(staging.existsSync(), isFalse, reason: '拷完并校验后必须删掉临时文件');
  });

  test('the provider may rename the document, and the caller gets that name', () async {
    tree.displayName = 'song (1).mp3';

    final result = await writer().commit(
      stagingFile: staging,
      relativePath: '',
      fileName: 'song.mp3',
    );

    expect(result.displayName, 'song (1).mp3');
  });

  test('a byte-count mismatch fails and keeps the staging file for a retry', () async {
    tree.writtenBytes = 5;

    await expectLater(
      writer().commit(stagingFile: staging, relativePath: '', fileName: 'song.mp3'),
      throwsA(
        isA<SafDownloadException>()
            .having((e) => e.kind, 'kind', DownloadFailureKind.disk)
            .having((e) => e.failure.detail, 'detail', contains('expected=8')),
      ),
    );
    expect(staging.existsSync(), isTrue, reason: '失败要保留临时文件，重试不必重新下载');
  });

  test('a revoked grant fails before copying anything, with a re-pick message', () async {
    tree.granted = false;

    await expectLater(
      writer().commit(stagingFile: staging, relativePath: '', fileName: 'song.mp3'),
      throwsA(
        isA<SafDownloadException>()
            .having((e) => e.kind, 'kind', DownloadFailureKind.storagePermission)
            .having((e) => e.needsFolderRepick, 'needsFolderRepick', isTrue)
            .having((e) => e.failure.message, 'message', contains('重新选择目录')),
      ),
    );

    expect(tree.grantChecks, 1);
    expect(tree.copyCalls, isEmpty, reason: '权限失效时不得尝试写入（不得静默回退）');
    expect(staging.existsSync(), isTrue);
  });

  test('a PERMISSION_LOST from the platform is classified as re-pickable', () async {
    tree.copyError = const SafDocumentTreeException(
      SafErrorCodes.permissionLost,
      '自定义目录的写入权限已失效，请重新选择目录',
    );

    await expectLater(
      writer().commit(stagingFile: staging, relativePath: '', fileName: 'song.mp3'),
      throwsA(
        isA<SafDownloadException>().having(
          (e) => e.kind,
          'kind',
          DownloadFailureKind.storagePermission,
        ),
      ),
    );
  });

  test('a TREE_UNAVAILABLE (folder deleted) is classified as re-pickable', () async {
    tree.copyError = const SafDocumentTreeException(
      SafErrorCodes.treeUnavailable,
      '无法访问已保存的目录，请重新选择',
    );

    await expectLater(
      writer().commit(stagingFile: staging, relativePath: '', fileName: 'song.mp3'),
      throwsA(
        isA<SafDownloadException>()
            .having((e) => e.needsFolderRepick, 'needsFolderRepick', isTrue)
            .having((e) => e.failure.message, 'message', contains('重新选择目录')),
      ),
    );
  });

  test('a mid-write failure is retryable and keeps the staging file', () async {
    tree.copyError = const SafDocumentTreeException(
      SafErrorCodes.writeFailed,
      '磁盘写入失败',
    );

    await expectLater(
      writer().commit(stagingFile: staging, relativePath: '', fileName: 'song.mp3'),
      throwsA(
        isA<SafDownloadException>()
            .having((e) => e.kind, 'kind', DownloadFailureKind.disk)
            .having((e) => e.failure.isRetryable, 'isRetryable', isTrue),
      ),
    );
    expect(staging.existsSync(), isTrue);
  });

  test('no persisted folder means a clear error, not a silent default', () async {
    final emptyStore = MemorySafTreeStore();

    await expectLater(
      SafDownloadWriter(tree: tree, store: emptyStore).commit(
        stagingFile: staging,
        relativePath: '',
        fileName: 'song.mp3',
      ),
      throwsA(
        isA<SafDownloadException>().having(
          (e) => e.failure.message,
          'message',
          '尚未选择自定义下载目录',
        ),
      ),
    );
    expect(tree.copyCalls, isEmpty);
  });

  test('a vanished staging file is reported as such', () async {
    await staging.delete();

    await expectLater(
      writer().commit(stagingFile: staging, relativePath: '', fileName: 'song.mp3'),
      throwsA(
        isA<SafDownloadException>()
            .having((e) => e.kind, 'kind', DownloadFailureKind.unknown)
            .having((e) => e.failure.message, 'message', contains('临时文件不存在')),
      ),
    );
    expect(tree.copyCalls, isEmpty);
  });

  test('isReady() needs both a stored folder and a live grant', () async {
    expect(await writer().isReady(), isTrue);

    tree.granted = false;
    expect(await writer().isReady(), isFalse);

    expect(await SafDownloadWriter(tree: tree, store: MemorySafTreeStore()).isReady(), isFalse);
  });

  test('targetState() separates "never chose SAF" from "the grant died"', () async {
    expect(await writer().targetState(), SafTargetState.ready);

    tree.granted = false;
    expect(await writer().targetState(), SafTargetState.permissionLost);

    // No folder chosen is the normal case: the caller uses the default
    // directory without bothering the user. A dead grant is not.
    expect(
      await SafDownloadWriter(tree: tree, store: MemorySafTreeStore()).targetState(),
      SafTargetState.notConfigured,
    );
  });

  test('a platform that cannot answer counts as a lost grant, not as ready', () async {
    final state = await SafDownloadWriter(
      tree: _ThrowingGrantTree(),
      store: MemorySafTreeStore(
        SafTreeSelection(uri: 'content://x', name: 'x', grantedAt: DateTime(2026)),
      ),
    ).targetState();

    // Never "ready": falling into the tree with an unknown grant is exactly the
    // silent failure this state exists to prevent.
    expect(state, SafTargetState.permissionLost);
    expect(await SafDownloadWriter(tree: _ThrowingGrantTree(), store: MemorySafTreeStore()).isReady(), isFalse);
  });

  test('pickDirectory() persists the grant, and a persist failure does not', () async {
    final selection = SafTreeSelection(
      uri: 'content://tree/primary%3ADownloads',
      name: 'Downloads',
      grantedAt: DateTime(2026, 10, 8),
    );
    tree.pickResult = selection;

    final picked = await writer().pickDirectory();

    expect(picked?.uri, selection.uri);
    expect((await store.read())!.name, 'Downloads');

    final failingTree = _FakeTree(
      pickError: const SafDocumentTreeException(
        SafErrorCodes.persistFailed,
        '无法长期保留该目录的访问权限',
      ),
    );
    final failingStore = MemorySafTreeStore();
    await expectLater(
      SafDownloadWriter(tree: failingTree, store: failingStore).pickDirectory(),
      throwsA(
        isA<SafDownloadException>()
            .having((e) => e.kind, 'kind', DownloadFailureKind.storagePermission)
            .having((e) => e.failure.message, 'message', contains('无法长期保留')),
      ),
    );
    expect(await failingStore.read(), isNull, reason: '授权失败不得记住这个目录');
  });

  test('a cancelled picker persists nothing and returns null', () async {
    tree.pickResult = null;
    final emptyStore = MemorySafTreeStore();

    expect(
      await SafDownloadWriter(tree: tree, store: emptyStore).pickDirectory(),
      isNull,
    );
    expect(await emptyStore.read(), isNull);
  });

  test('clear() releases the platform grant as well as the stored uri', () async {
    await writer().clear();

    expect(tree.releaseCalls, 1);
    expect(await store.read(), isNull);
  });

  test('openDirectory() returns false instead of throwing when unsupported', () async {
    expect(await writer().openDirectory(), isTrue);

    tree.openError = const SafDocumentTreeException(
      SafErrorCodes.openFailed,
      '没有应用可以打开该目录',
    );
    expect(await writer().openDirectory(), isFalse);

    expect(
      await SafDownloadWriter(tree: tree, store: MemorySafTreeStore()).openDirectory(),
      isFalse,
      reason: '没有选过目录时不应调用平台',
    );
  });

  test('stagingDirectory() creates the configured directory', () async {
    final nested = Directory('${tempDir.path}${Platform.pathSeparator}staging');
    final created = await SafDownloadWriter(
      tree: tree,
      store: store,
      stagingDirectoryProvider: () async => nested,
    ).stagingDirectory();

    expect(created.path, nested.path);
    expect(nested.existsSync(), isTrue);
  });
}
