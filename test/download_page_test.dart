import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/download/data/download_directory_service.dart';
import 'package:mconnect/features/download/data/download_task_store.dart';
import 'package:mconnect/features/download/data/repositories/download_manager.dart';
import 'package:mconnect/features/download/domain/entities/download_task.dart';
import 'package:mconnect/features/download/presentation/providers/download_provider.dart';
import 'package:mconnect/features/download/presentation/screens/download_page.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.mconnect.mconnect/file_opener');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('completed download folder action opens the containing folder', (
    tester,
  ) async {
    final filePath = p.join(
      'D:',
      'MconnectTestDownloads',
      'netease',
      'mp3',
      'Artist - Song.mp3',
    );
    final task = DownloadTask(
      id: 'netease_s1_low',
      song: _song,
      quality: AudioLevel.low,
      status: DownloadStatus.completed,
      progress: 1,
      downloadedBytes: 10,
      totalBytes: 10,
      filePath: filePath,
      createdAt: DateTime(2026, 5, 29),
      completedAt: DateTime(2026, 5, 29),
    );
    final manager = DownloadManager(
      directoryService: DownloadDirectoryService(
        store: _MemoryDownloadDirectoryStore(),
        defaultRootProvider: () async => throw UnimplementedError(),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          downloadProvider.overrideWith(
            (ref) => DownloadNotifier(
              manager: manager,
              initialState: DownloadState(tasks: [task]),
              taskStore: _MemoryDownloadTaskStore([task]),
            ),
          ),
        ],
        child: const MaterialApp(home: DownloadPage()),
      ),
    );

    await tester.pump();
    await tester.tap(find.text('已完成 (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.folder_open));
    await tester.pump();

    expect(calls, hasLength(1));
    expect(calls.single.method, 'openFolder');
    expect(calls.single.arguments, p.dirname(filePath));
  });

  testWidgets('completed download delete asks for confirmation first', (
    tester,
  ) async {
    final task = DownloadTask(
      id: 'netease_s1_low',
      song: _song,
      quality: AudioLevel.low,
      status: DownloadStatus.completed,
      progress: 1,
      downloadedBytes: 10,
      totalBytes: 10,
      filePath: p.join('D:', 'MconnectTestDownloads', 'Artist - Song.mp3'),
      createdAt: DateTime(2026, 5, 29),
      completedAt: DateTime(2026, 5, 29),
    );
    final manager = _DeleteOkDownloadManager();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          downloadProvider.overrideWith(
            (ref) => DownloadNotifier(
              manager: manager,
              initialState: DownloadState(tasks: [task]),
              taskStore: _MemoryDownloadTaskStore([task]),
            ),
          ),
        ],
        child: const MaterialApp(home: DownloadPage()),
      ),
    );

    await tester.pump();
    await tester.tap(find.text('已完成 (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('删除下载文件'), findsOneWidget);
    expect(find.textContaining('会删除本地文件'), findsOneWidget);
    expect(find.text('已完成 (1)'), findsOneWidget);
    expect(manager.deleteCalls, 0);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('已完成 (1)'), findsOneWidget);
    expect(manager.deleteCalls, 0);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(manager.deleteCalls, 1);
    expect(find.text('已完成 (0)'), findsOneWidget);
  });
}

const _song = Song(
  id: 's1',
  platform: PlatformType.netease,
  name: 'Song',
  artists: [Artist(id: 'a1', name: 'Artist')],
);

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

class _MemoryDownloadTaskStore implements DownloadTaskStore {
  List<DownloadTask> tasks;

  _MemoryDownloadTaskStore(this.tasks);

  @override
  Future<List<DownloadTask>> load() async => tasks;

  @override
  Future<void> save(List<DownloadTask> tasks) async {
    this.tasks = List<DownloadTask>.from(tasks);
  }
}

class _DeleteOkDownloadManager extends DownloadManager {
  int deleteCalls = 0;

  _DeleteOkDownloadManager()
      : super(
          directoryService: DownloadDirectoryService(
            store: _MemoryDownloadDirectoryStore(),
            defaultRootProvider: () async => throw UnimplementedError(),
          ),
        );

  @override
  Future<bool> deleteDownloadedFile(DownloadTask task) async {
    deleteCalls++;
    return true;
  }
}
