import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/download/data/download_directory_service.dart';
import 'package:mconnect/features/download/data/repositories/download_manager.dart';
import 'package:mconnect/features/download/domain/entities/download_failure.dart';
import 'package:mconnect/features/download/domain/entities/download_task.dart';
import 'package:mconnect/features/download/presentation/providers/download_provider.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/platform/base/platform_registry.dart';
import 'package:path/path.dart' as p;

import 'download_fakes.dart';

/// P1 download resilience: resume, body validation, pre-flight disk check and
/// the Android permission gate — against a real loopback HTTP server (a raw
/// socket, so the test can deliberately advertise a Content-Length it does not
/// deliver).
void main() {
  // Widget tests install an HttpOverrides that answers every request with 400;
  // these tests need a real socket, and none of them runs in a widget test.
  setUpAll(() {
    HttpOverrides.global = null;
  });

  late Directory tempDir;
  late _RawServer server;
  late DownloadDirectoryService directoryService;
  late FakeDownloadPlatform platform;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mconnect_resume_test_');
    server = await _RawServer.start();
    directoryService = DownloadDirectoryService(
      store: MemoryDownloadDirectoryStore(),
      defaultRootProvider: () async => tempDir,
    );
    platform = FakeDownloadPlatform(url: server.url);
    PlatformRegistry.register(platform);
  });

  tearDown(() async {
    await server.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  DownloadManager managerWith({FreeSpaceProbe? freeSpaceProbe}) =>
      DownloadManager(
        directoryService: directoryService,
        freeSpaceProbe: freeSpaceProbe,
      );

  Future<String> expectedPath(DownloadTask task) async {
    final dir = await directoryService.targetDirectory(
      task.song.platform,
      task.quality,
    );
    return p.join(dir.path, task.fileName);
  }

  test('a download is validated against the declared size and completes',
      () async {
    final body = List<int>.generate(30000, (index) => index % 251);
    server.body = body;

    final manager = managerWith();
    final notifier = DownloadNotifier(
      manager: manager,
      taskStore: MemoryDownloadTaskStore([]),
      fileExists: (path) => File(path).exists(),
    );
    addTearDown(notifier.dispose);

    await notifier.startDownload(_song, AudioLevel.low);
    await _waitFor(() => notifier.state.tasks.single.status != DownloadStatus.downloading && notifier.state.tasks.single.status != DownloadStatus.waiting);

    final task = notifier.state.tasks.single;
    expect(task.status, DownloadStatus.completed);
    expect(await File(task.filePath!).length(), body.length);
  });

  test('a partial file is resumed with a Range request, not re-downloaded',
      () async {
    final body = List<int>.generate(30000, (index) => index % 251);
    server.body = body;

    final task = DownloadTask(
      id: 'netease_s1_low',
      song: _song,
      quality: AudioLevel.low,
      totalBytes: body.length,
      createdAt: DateTime(2026, 1, 1),
    );
    final path = await expectedPath(task);
    await File(path).writeAsBytes(body.sublist(0, 12000));

    final manager = managerWith();
    final notifier = DownloadNotifier(
      manager: manager,
      initialState: DownloadState(tasks: [task]),
      taskStore: MemoryDownloadTaskStore([]),
    );
    addTearDown(notifier.dispose);

    await notifier.startWaitingTask(task.id);
    await _waitFor(() => notifier.state.tasks.single.status == DownloadStatus.completed);

    expect(
      server.rangeHeaders,
      contains('bytes=12000-'),
      reason: 'the manager must ask for the missing part only',
    );
    expect(File(path).lengthSync(), body.length);
    expect(
      File(path).readAsBytesSync(),
      body,
      reason: 'the resumed file must be byte-identical to the source',
    );
  });

  test('a server that ignores Range makes the manager start over cleanly',
      () async {
    final body = List<int>.generate(20000, (index) => (index * 7) % 253);
    server.body = body;
    server.honourRange = false;

    final task = DownloadTask(
      id: 'netease_s1_low',
      song: _song,
      quality: AudioLevel.low,
      totalBytes: body.length,
      createdAt: DateTime(2026, 1, 1),
    );
    final path = await expectedPath(task);
    // A stale partial file that must NOT be appended to a full 200 response.
    await File(path).writeAsBytes(List<int>.filled(12000, 9));

    final manager = managerWith();
    final notifier = DownloadNotifier(
      manager: manager,
      initialState: DownloadState(tasks: [task]),
      taskStore: MemoryDownloadTaskStore([]),
    );
    addTearDown(notifier.dispose);

    await notifier.startWaitingTask(task.id);
    await _waitFor(() => notifier.state.tasks.single.status == DownloadStatus.completed);

    expect(server.rangeHeaders, contains('bytes=12000-'));
    expect(File(path).readAsBytesSync(), body);
  });

  test('a truncated body fails with a network failure and keeps the partial file',
      () async {
    final body = List<int>.generate(30000, (index) => index % 251);
    server.body = body;
    server.declaredLength = body.length;
    server.sendBytes = 20000;

    final manager = managerWith();
    final notifier = DownloadNotifier(
      manager: manager,
      taskStore: MemoryDownloadTaskStore([]),
    );
    addTearDown(notifier.dispose);

    await notifier.startDownload(_song, AudioLevel.low);
    await _waitFor(() => notifier.state.tasks.single.status == DownloadStatus.failed);

    final task = notifier.state.tasks.single;
    expect(task.failureKind, DownloadFailureKind.network);
    expect(
      task.downloadedBytes,
      20000,
      reason: 'the partial file must be remembered so the retry can resume',
    );
    expect(File(task.filePath!).lengthSync(), 20000);
  });

  test('a download is refused before writing when the disk is full', () async {
    final body = List<int>.generate(30000, (index) => index % 251);
    server.body = body;

    final manager = managerWith(freeSpaceProbe: (_) async => 1024);
    final notifier = DownloadNotifier(
      manager: manager,
      taskStore: MemoryDownloadTaskStore([]),
    );
    addTearDown(notifier.dispose);

    await notifier.startDownload(_song, AudioLevel.low);
    await _waitFor(() => notifier.state.tasks.single.status == DownloadStatus.failed);

    final task = notifier.state.tasks.single;
    expect(task.failureKind, DownloadFailureKind.disk);
    expect(task.error, contains('存储空间不足'));
    if (task.filePath != null) {
      expect(
        File(task.filePath!).existsSync(),
        isFalse,
        reason: 'nothing may be written when the pre-flight check fails',
      );
    }
  });

  test('an unknown free space skips the gate instead of blocking the download',
      () async {
    final body = List<int>.generate(4096, (index) => index % 251);
    server.body = body;

    final manager = managerWith(freeSpaceProbe: (_) async => null);
    final notifier = DownloadNotifier(
      manager: manager,
      taskStore: MemoryDownloadTaskStore([]),
    );
    addTearDown(notifier.dispose);

    await notifier.startDownload(_song, AudioLevel.low);
    await _waitFor(() => notifier.state.tasks.single.status == DownloadStatus.completed);

    expect(notifier.state.tasks.single.status, DownloadStatus.completed);
  });

  test('cancelling a download deletes the half-written file', () async {
    // Resume keeps partial files; an explicit cancel must not leave the orphan
    // behind for a later re-download to resume from.
    final path = p.join(tempDir.path, 'partial.mp3');
    await File(path).writeAsBytes(List<int>.filled(1000, 3));
    final task = DownloadTask(
      id: 'netease_s1_low',
      song: _song,
      quality: AudioLevel.low,
      status: DownloadStatus.waiting,
      filePath: path,
      createdAt: DateTime(2026, 1, 1),
    );
    final manager = managerWith();
    final notifier = DownloadNotifier(
      manager: manager,
      initialState: DownloadState(tasks: [task]),
      taskStore: MemoryDownloadTaskStore([]),
    );
    addTearDown(notifier.dispose);

    notifier.cancelDownload(task.id);
    await _waitFor(() => !File(path).existsSync());

    expect(File(path).existsSync(), isFalse);
    expect(notifier.state.tasks, isEmpty);
  });

  test('a snooped URL failure is classified before any request is made',
      () async {
    platform.url = 'http://127.0.0.1:1/never';
    final manager = managerWith();
    final notifier = DownloadNotifier(
      manager: manager,
      taskStore: MemoryDownloadTaskStore([]),
    );
    addTearDown(notifier.dispose);

    await notifier.startDownload(_song, AudioLevel.low);
    await _waitFor(() => notifier.state.tasks.single.status == DownloadStatus.failed);

    expect(
      notifier.state.tasks.single.failureKind,
      DownloadFailureKind.network,
    );
  });

  group('Android permission gate', () {
    test('API level is parsed from the platform version string', () {
      expect(androidApiLevelFrom('Android 13, API level 33, build/TQ1A'), 33);
      expect(androidApiLevelFrom('Android 9, API level 28'), 28);
      expect(androidApiLevelFrom('Windows 11 (10.0.22631)'), isNull);
    });

    test('the app sandbox never needs the legacy permission', () async {
      final sandbox = Directory(p.join(tempDir.path, 'app_flutter'));
      final service = DownloadDirectoryService(
        store: MemoryDownloadDirectoryStore(),
        defaultRootProvider: () async => sandbox,
      );
      final inside = Directory(p.join(sandbox.path, 'downloads'));

      // Not Android: never requests it.
      expect(await service.needsLegacyStoragePermission(inside), isFalse);
    });
  });
}

/// Waits until [predicate] holds (or fails the test after a timeout).
Future<void> _waitFor(bool Function() predicate, {int attempts = 200}) async {
  for (var i = 0; i < attempts; i++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('condition was never met');
}

const _song = Song(
  id: 's1',
  platform: PlatformType.netease,
  name: 'Song 1',
  artists: [Artist(id: 'a1', name: 'Artist 1')],
);

/// A raw HTTP/1.1 server with full control over Content-Length and Range.
class _RawServer {
  _RawServer._(this._server);

  final ServerSocket _server;
  List<int> body = const [];
  bool honourRange = true;

  /// Advertised Content-Length; defaults to the number of bytes actually sent.
  int? declaredLength;

  /// Bytes actually written to the socket (defaults to all of them).
  int? sendBytes;

  final List<String?> rangeHeaders = <String?>[];

  String get url => 'http://127.0.0.1:${_server.port}/audio.mp3';

  static Future<_RawServer> start() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final server = _RawServer._(socket);
    socket.listen(server._handle);
    return server;
  }

  Future<void> _handle(Socket socket) async {
    final received = <int>[];
    socket.listen((data) async {
      received.addAll(data);
      final text = String.fromCharCodes(received);
      if (!text.contains('\r\n\r\n')) return;

      final rangeMatch = RegExp(
        r'[Rr]ange:\s*bytes=(\d+)-',
      ).firstMatch(text);
      final requestedRange = rangeMatch?.group(1);
      rangeHeaders.add(rangeMatch == null ? null : 'bytes=$requestedRange-');

      final start = honourRange && requestedRange != null
          ? int.parse(requestedRange)
          : 0;
      final remaining = body.sublist(min(start, body.length));
      final count = sendBytes == null
          ? remaining.length
          : min(sendBytes!, remaining.length);
      final payload = remaining.sublist(0, count);
      final declared = declaredLength ?? payload.length;

      final buffer = StringBuffer()
        ..write(start > 0 ? 'HTTP/1.1 206 Partial Content\r\n' : 'HTTP/1.1 200 OK\r\n')
        ..write('Content-Type: audio/mpeg\r\n')
        ..write('Content-Length: $declared\r\n');
      if (start > 0) {
        buffer.write(
          'Content-Range: bytes $start-${body.length - 1}/${body.length}\r\n',
        );
      }
      buffer.write('Connection: close\r\n\r\n');

      socket.add(buffer.toString().codeUnits);
      socket.add(payload);
      await socket.flush();
      await socket.close();
    }, onError: (Object error) {
      // A client that aborted (disk gate / cancel) just closes the socket.
    });
  }

  Future<void> close() => _server.close();
}
