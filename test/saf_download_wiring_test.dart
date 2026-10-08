import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/download/data/download_directory_service.dart';
import 'package:mconnect/features/download/data/download_task_store.dart';
import 'package:mconnect/features/download/data/repositories/download_manager.dart';
import 'package:mconnect/features/download/data/saf_document_tree.dart';
import 'package:mconnect/features/download/data/saf_download_writer.dart';
import 'package:mconnect/features/download/data/saf_tree_store.dart';
import 'package:mconnect/features/download/domain/entities/download_failure.dart';
import 'package:mconnect/features/download/domain/entities/download_task.dart';
import 'package:mconnect/features/download/presentation/providers/download_provider.dart';
import 'package:mconnect/features/download/presentation/screens/download_page.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/platform/base/platform_registry.dart';
import 'package:path/path.dart' as p;

import 'download_fakes.dart';

/// A SAF tree that records every call, so the wiring can be asserted without a
/// device: the real storage behaviour is unverifiable here (see the report's
/// on-device checklist), but *what the app asks the platform to do* is not.
class _RecordingTree implements SafDocumentTree {
  bool granted = true;
  int? writtenBytes;
  String? displayName;
  String? documentUriOverride;
  SafDocumentTreeException? copyError;
  SafTreeSelection? pickResult;
  SafDocumentTreeException? pickError;
  bool deleteResult = true;
  bool openResult = true;

  final List<Map<String, Object?>> copyCalls = [];
  final List<String> deletedUris = [];
  final List<String> openCalls = [];
  int pickCalls = 0;

  @override
  Future<SafTreeSelection?> pickDirectory() async {
    pickCalls++;
    if (pickError != null) throw pickError!;
    return pickResult;
  }

  @override
  Future<bool> isGranted(String treeUri) async => granted;

  @override
  Future<bool> release(String treeUri) async => true;

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
      uri: documentUriOverride ?? '$treeUri/document/$fileName',
      displayName: displayName ?? fileName,
    );
  }

  @override
  Future<bool> deleteDocument(String documentUri) async {
    deletedUris.add(documentUri);
    return deleteResult;
  }

  @override
  Future<bool> openTree(String treeUri) async {
    openCalls.add(treeUri);
    return openResult;
  }
}

/// Serves bytes without a socket, so a wiring test stays deterministic.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({required this.body});

  final List<int> body;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final requested = options.headers['Range'] as String?;
    final offset = requested == null
        ? 0
        : int.tryParse(
                RegExp(r'bytes=(\d+)-').firstMatch(requested)?.group(1) ?? '',
              ) ??
              0;
    final payload = body.sublist(offset);
    return ResponseBody.fromBytes(
      payload,
      offset > 0 ? 206 : 200,
      headers: {
        Headers.contentLengthHeader: ['${payload.length}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _treeUri =
    'content://com.android.externalstorage.documents/tree/primary%3AMusic';

const _song = Song(
  id: 's1',
  platform: PlatformType.netease,
  name: 'Song',
  artists: [Artist(id: 'a1', name: 'Artist')],
);

class _MemoryTaskStore implements DownloadTaskStore {
  _MemoryTaskStore(this.tasks);

  List<DownloadTask> tasks;

  @override
  Future<List<DownloadTask>> load() async => tasks;

  @override
  Future<void> save(List<DownloadTask> saved) async => tasks = saved;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory stagingDir;
  late _RecordingTree tree;
  late _FakeAdapter adapter;
  late FakeDownloadPlatform platform;
  final body = List<int>.generate(4096, (index) => index % 251);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mconnect_saf_wiring_');
    stagingDir = Directory(p.join(tempDir.path, 'staging'));
    tree = _RecordingTree();
    adapter = _FakeAdapter(body: body);
    platform = FakeDownloadPlatform(url: 'https://example.invalid/song.mp3');
    PlatformRegistry.register(platform);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  DownloadDirectoryService serviceWith({SafTreeSelection? selection}) {
    return DownloadDirectoryService(
      store: MemoryDownloadDirectoryStore(),
      defaultRootProvider: () async => tempDir,
      safWriter: SafDownloadWriter(
        tree: tree,
        store: MemorySafTreeStore(selection),
        stagingDirectoryProvider: () async => stagingDir,
      ),
    );
  }

  DownloadManager managerWith(DownloadDirectoryService service) {
    return DownloadManager(
      dio: Dio()..httpClientAdapter = adapter,
      directoryService: service,
      freeSpaceProbe: (_) async => null,
    );
  }

  DownloadTask task() => DownloadTask(
    id: 'netease_s1_low',
    song: _song,
    quality: AudioLevel.low,
    totalBytes: body.length,
    createdAt: DateTime(2026, 10, 8),
  );

  SafTreeSelection selection() => SafTreeSelection(
    uri: _treeUri,
    name: 'Music',
    grantedAt: DateTime(2026, 10, 8),
  );

  /// Runs a download to completion. The stream carries progress ticks and then
  /// the terminal event, so the assertions read `events.last`.
  Future<List<DownloadProgress>> run(
    DownloadManager manager,
    DownloadTask downloadTask,
  ) => manager.download(downloadTask).toList();

  // ---------------------------------------------------------------------------
  // Constraint 1: with no SAF folder configured, nothing about the default path
  // changes — same directory, same file name, no SAF call at all.
  // ---------------------------------------------------------------------------
  test('notConfigured: the download goes to the default directory, byte for byte', () async {
    final service = serviceWith();
    final manager = managerWith(service);

    final events = await run(manager, task());
    final completed = events.last;

    final expectedDir = await service.targetDirectory(
      _song.platform,
      AudioLevel.low,
    );
    final expectedPath = p.join(expectedDir.path, task().fileName);

    expect(completed.completed, isTrue);
    // The manager joins with `/` (pre-existing behaviour); Windows reports `\`
    // for the directory part, so the comparison is normalized.
    expect(p.normalize(completed.filePath!), p.normalize(expectedPath));
    expect(File(expectedPath).existsSync(), isTrue);
    expect(await File(expectedPath).length(), body.length);

    // The default path stays `<root>/downloads/<platform>/<mp3|flac>/<name>`.
    expect(
      expectedPath,
      p.join(tempDir.path, 'downloads', 'netease', 'mp3', task().fileName),
    );
    expect(tree.copyCalls, isEmpty, reason: '未配置 SAF 时不得触碰 SAF 通道');
    expect(await service.currentTreeSelection(), isNull);
  });

  // ---------------------------------------------------------------------------
  // Constraint 2: a revoked grant fails BEFORE the transfer, with an actionable
  // reason — and never quietly writes into another folder.
  // ---------------------------------------------------------------------------
  test('permissionLost: fails before any network request, and writes nowhere', () async {
    final service = serviceWith(selection: selection());
    tree.granted = false;
    final manager = managerWith(service);
    platform.urlRequests = 0;

    final events = await run(manager, task());
    final terminal = events.last;

    expect(terminal.completed, isFalse);
    final failure = terminal.failure;
    expect(failure, isNotNull);
    expect(failure!.kind, DownloadFailureKind.storagePermission);
    expect(failure.message, contains('重新选择目录'));

    expect(platform.urlRequests, 0, reason: '权限失效必须在取流地址之前就失败');
    expect(adapter.requests, isEmpty, reason: '不得发起任何 HTTP 请求');
    expect(tree.copyCalls, isEmpty);

    // Nothing may have been written into the default directory instead.
    final defaultDir = Directory(
      p.join(tempDir.path, 'downloads', 'netease', 'mp3'),
    );
    expect(
      defaultDir.existsSync() && defaultDir.listSync().isNotEmpty,
      isFalse,
      reason: '禁止静默回退到默认目录',
    );
    expect(stagingDir.existsSync() && stagingDir.listSync().isNotEmpty, isFalse);
  });

  // ---------------------------------------------------------------------------
  // Constraint 3: the completed task records what the provider actually created,
  // not the name the app asked for.
  // ---------------------------------------------------------------------------
  test('ready: the bytes are staged, then published under the provider identity', () async {
    final service = serviceWith(selection: selection());
    tree.displayName = 'Artist - Song (1).mp3';
    tree.documentUriOverride = '$_treeUri/document/renamed-id';
    final manager = managerWith(service);

    final events = await run(manager, task());
    final completed = events.last;

    expect(completed.completed, isTrue);
    // The persisted identity is the document URI, not a filesystem path: only it
    // can be deleted or revealed later.
    expect(completed.filePath, '$_treeUri/document/renamed-id');
    expect(completed.downloadedBytes, body.length);

    expect(tree.copyCalls, hasLength(1));
    expect(tree.copyCalls.single['treeUri'], _treeUri);
    expect(tree.copyCalls.single['relativePath'], 'netease/mp3');
    expect(tree.copyCalls.single['fileName'], task().fileName);
    // The transfer happened in staging, and the staged copy was removed only
    // after the publish succeeded.
    expect(
      p.normalize(tree.copyCalls.single['sourcePath']! as String),
      p.normalize(p.join(stagingDir.path, task().fileName)),
    );
    expect(
      File(p.join(stagingDir.path, task().fileName)).existsSync(),
      isFalse,
      reason: '发布成功后必须删掉 staging 临时文件',
    );
    // The default directory was not used at all.
    expect(Directory(p.join(tempDir.path, 'downloads')).existsSync(), isFalse);
  });

  // ---------------------------------------------------------------------------
  // Constraint 6: a failed publish keeps the staged bytes so a retry resumes
  // instead of re-downloading.
  // ---------------------------------------------------------------------------
  test('a failed publish keeps the staging file and classifies the failure', () async {
    final service = serviceWith(selection: selection());
    tree.copyError = const SafDocumentTreeException(
      SafErrorCodes.sizeMismatch,
      '写入自定义目录的字节数不符',
    );
    final manager = managerWith(service);

    final events = await run(manager, task());
    final terminal = events.last;

    final failure = terminal.failure;
    expect(failure, isNotNull);
    expect(failure!.kind, DownloadFailureKind.disk);
    expect(failure.isRetryable, isTrue);
    // The failure points at the staging file, which is what a retry resumes.
    expect(
      p.normalize(terminal.filePath!),
      p.normalize(p.join(stagingDir.path, task().fileName)),
    );
    final staged = File(p.join(stagingDir.path, task().fileName));
    expect(staged.existsSync(), isTrue, reason: '发布失败必须保留临时文件');
    expect(await staged.length(), body.length);
  });

  test('a resumed SAF download continues from the staged bytes', () async {
    final service = serviceWith(selection: selection());
    final manager = managerWith(service);
    // A previous attempt already staged half the file. The task's own record has
    // to agree with what is on disk — that is the condition a resume is allowed
    // to trust (W0-C).
    final resumable = task().copyWith(downloadedBytes: 1024);
    Directory(stagingDir.path).createSync(recursive: true);
    await File(
      p.join(stagingDir.path, resumable.fileName),
    ).writeAsBytes(body.sublist(0, 1024));

    final events = await run(manager, resumable);

    expect(events.last.completed, isTrue);
    expect(
      adapter.requests.single.headers['Range'],
      'bytes=1024-',
      reason: '续传语义必须保留：SAF 只改变写到哪，不改变 Range 请求',
    );
    expect(events.last.downloadedBytes, body.length);
  });

  // ---------------------------------------------------------------------------
  // Deleting: a `content://` file cannot be removed with `File(...)`.
  // ---------------------------------------------------------------------------
  test('deleteDownloadedFile routes a document URI through SAF', () async {
    final manager = managerWith(serviceWith());
    final downloadTask = task().copyWith(
      filePath: () => '$_treeUri/document/song-id',
    );

    expect(await manager.deleteDownloadedFile(downloadTask), isTrue);
    expect(tree.deletedUris, ['$_treeUri/document/song-id']);
  });

  test('deleteDownloadedFile still deletes a plain path with the filesystem', () async {
    final manager = managerWith(serviceWith());
    final file = File(p.join(tempDir.path, 'plain.mp3'));
    await file.writeAsBytes(body);
    final downloadTask = task().copyWith(filePath: () => file.path);

    expect(await manager.deleteDownloadedFile(downloadTask), isTrue);
    expect(file.existsSync(), isFalse);
    expect(tree.deletedUris, isEmpty);
  });

  test('a refused SAF delete is reported as a failure, not as success', () async {
    final manager = managerWith(serviceWith());
    tree.deleteResult = false;
    final downloadTask = task().copyWith(filePath: () => '$_treeUri/document/x');

    expect(await manager.deleteDownloadedFile(downloadTask), isFalse);
  });

  test('partialBytesOf reports the staged bytes of a SAF task', () async {
    final service = serviceWith(selection: selection());
    final manager = managerWith(service);
    Directory(stagingDir.path).createSync(recursive: true);
    await File(
      p.join(stagingDir.path, task().fileName),
    ).writeAsBytes(body.sublist(0, 700));

    expect(await manager.partialBytesOf(task()), 700);

    await manager.discardPartialFile(task());
    expect(
      File(p.join(stagingDir.path, task().fileName)).existsSync(),
      isFalse,
    );
  });

  test('a completed SAF task reports no partial bytes and is not re-deleted', () async {
    final service = serviceWith(selection: selection());
    final manager = managerWith(service);
    // The publish succeeded, so the staging copy is gone and the file lives in
    // the user's folder under a document URI.
    final completed = task().copyWith(
      status: DownloadStatus.completed,
      filePath: () => '$_treeUri/document/published-id',
    );

    expect(await manager.partialBytesOf(completed), 0);

    // `discardPartialFile` is the "user cancelled / clean up" path: it must
    // touch only the staging file, never the document in the user's folder.
    await manager.discardPartialFile(completed);
    expect(
      tree.deletedUris,
      isEmpty,
      reason: '清理部分文件不得删除用户目录里已发布的文件',
    );

    // The real delete goes through SAF, and a refusal is reported (so the UI
    // cannot claim "deleted" while the file is still there).
    tree.deleteResult = false;
    expect(await manager.deleteDownloadedFile(completed), isFalse);
    expect(tree.deletedUris, ['$_treeUri/document/published-id']);

    tree.deleteResult = true;
    expect(await manager.deleteDownloadedFile(completed), isTrue);
  });

  // ---------------------------------------------------------------------------
  // Service-level resolution + the picker result contract.
  // ---------------------------------------------------------------------------
  group('DownloadDirectoryService.resolveDownloadDestination', () {
    test('is the plain default directory when nothing is configured', () async {
      final service = serviceWith();

      final destination = await service.resolveDownloadDestination(
        PlatformType.netease,
        AudioLevel.low,
      );

      expect(destination, isA<FileSystemDownloadDestination>());
      expect(
        (destination as FileSystemDownloadDestination).directory.path,
        p.join(tempDir.path, 'downloads', 'netease', 'mp3'),
      );
    });

    test('is a staging target with the tree sub-path when SAF is ready', () async {
      final service = serviceWith(selection: selection());

      final destination = await service.resolveDownloadDestination(
        PlatformType.qq,
        AudioLevel.lossless,
      );

      expect(destination, isA<SafDownloadDestination>());
      final saf = destination as SafDownloadDestination;
      expect(saf.stagingDirectory.path, stagingDir.path);
      expect(saf.relativePath, 'qq/flac');
      expect(saf.treeName, 'Music');
    });

    test('is unusable (never a fallback) when the grant is gone', () async {
      final service = serviceWith(selection: selection());
      tree.granted = false;

      final destination = await service.resolveDownloadDestination(
        PlatformType.netease,
        AudioLevel.low,
      );

      expect(destination, isA<UnusableDownloadDestination>());
      expect(
        (destination as UnusableDownloadDestination).failure.kind,
        DownloadFailureKind.storagePermission,
      );
      expect(await service.isSafTarget(), isFalse);
    });
  });

  group('applySafTreeDirectory', () {
    test('persists the picked folder', () async {
      final service = serviceWith();
      tree.pickResult = selection();

      final result = await service.applySafTreeDirectory();

      expect(result.isOk, isTrue);
      expect(result.displayName, 'Music');
      expect((await service.currentTreeSelection())!.uri, _treeUri);
      expect(await service.isSafTarget(), isTrue);
    });

    test('a cancelled picker is not an error', () async {
      final service = serviceWith();
      tree.pickResult = null;

      final result = await service.applySafTreeDirectory();

      expect(result.isOk, isFalse);
      expect(result.isCancelled, isTrue);
      expect(result.message, isEmpty);
      expect(await service.currentTreeSelection(), isNull);
    });

    test('a refused persistable grant is reported as unwritable', () async {
      final service = serviceWith();
      tree.pickError = const SafDocumentTreeException(
        SafErrorCodes.persistFailed,
        '无法长期保留该目录的访问权限',
      );

      final result = await service.applySafTreeDirectory();

      expect(result.isOk, isFalse);
      expect(result.isCancelled, isFalse);
      expect(result.rejection, DownloadRootRejection.notWritable);
      expect(await service.currentTreeSelection(), isNull);
    });

    test('reset releases the grant and forgets the folder', () async {
      final service = serviceWith(selection: selection());

      await service.resetSafTreeDirectory();

      expect(await service.currentTreeSelection(), isNull);
      expect(await service.isSafTarget(), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Constraint 5: "open download folder" for a SAF target.
  // ---------------------------------------------------------------------------
  group('download page open-folder', () {
    const fileOpenerChannel = MethodChannel('com.mconnect.mconnect/file_opener');
    final fileOpenerCalls = <MethodCall>[];

    setUp(() {
      fileOpenerCalls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(fileOpenerChannel, (call) async {
            fileOpenerCalls.add(call);
            return true;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(fileOpenerChannel, null);
    });

    Future<void> pumpCompletedTask(
      WidgetTester tester,
      DownloadDirectoryService service,
      DownloadTask completed,
    ) async {
      final manager = managerWith(service);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            downloadProvider.overrideWith(
              (ref) => DownloadNotifier(
                manager: manager,
                initialState: DownloadState(tasks: [completed]),
                taskStore: _MemoryTaskStore([completed]),
              ),
            ),
          ],
          child: const MaterialApp(home: DownloadPage()),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('已完成 (1)'));
      await tester.pumpAndSettle();
    }

    testWidgets('a SAF document opens through the tree, not through a path', (
      tester,
    ) async {
      final service = serviceWith(selection: selection());
      final completed = task().copyWith(
        status: DownloadStatus.completed,
        filePath: () => '$_treeUri/document/song-id',
      );

      await pumpCompletedTask(tester, service, completed);
      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pumpAndSettle();

      expect(tree.openCalls, [_treeUri]);
      expect(
        fileOpenerCalls,
        isEmpty,
        reason: 'content:// 目录不能走 FileOpener（它要求 File(path).exists()）',
      );
    });

    testWidgets('when no app can open the tree the user is told, not left in silence', (
      tester,
    ) async {
      final service = serviceWith(selection: selection());
      tree.openResult = false;
      final completed = task().copyWith(
        status: DownloadStatus.completed,
        filePath: () => '$_treeUri/document/song-id',
      );

      await pumpCompletedTask(tester, service, completed);
      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pumpAndSettle();

      expect(find.textContaining('没有可以打开该目录的应用'), findsOneWidget);
    });

    testWidgets('a plain path keeps using FileOpener', (tester) async {
      final service = serviceWith();
      final completed = task().copyWith(
        status: DownloadStatus.completed,
        filePath: () =>
            p.join(tempDir.path, 'downloads', 'netease', 'mp3', 'a.mp3'),
      );

      await pumpCompletedTask(tester, service, completed);
      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pumpAndSettle();

      expect(fileOpenerCalls.single.method, 'openFolder');
      expect(tree.openCalls, isEmpty);
    });
  });
}
