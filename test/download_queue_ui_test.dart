import 'package:flutter/material.dart';
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

/// The download page's queue-state UI, which needs the Wave 2 queue API
/// (`pauseQueue` / `queueBlockedReason`) that did not exist before.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the page explains why the queue is not starting', (
    tester,
  ) async {
    // The 仅 Wi-Fi 下载 / 离线模式 / 暂停 gates used to be invisible: a held
    // task simply sat there in `waiting` with no explanation.
    final manager = _RecordingDownloadManager();
    final task = DownloadTask(
      id: 'netease_s1_low_cache',
      song: _song,
      quality: AudioLevel.low,
      status: DownloadStatus.waiting,
      createdAt: DateTime(2026, 5, 29),
      isOfflineCache: true,
    );
    late DownloadNotifier notifier;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          downloadProvider.overrideWith((ref) {
            return notifier = DownloadNotifier(
              manager: manager,
              initialState: DownloadState(tasks: [task]),
              taskStore: _MemoryDownloadTaskStore([task]),
            );
          }),
        ],
        child: const MaterialApp(home: DownloadPage()),
      ),
    );
    await tester.pump();

    notifier.pauseQueue();
    await tester.pump();

    expect(find.textContaining('暂停'), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);

    // Resuming clears the banner.
    await notifier.resumeQueue();
    await tester.pump();
    expect(find.textContaining('下载队列已暂停'), findsNothing);
  });

  testWidgets('the queue hint shows when 仅 Wi-Fi 下载 holds a task back', (
    tester,
  ) async {
    final manager = _RecordingDownloadManager();
    late DownloadNotifier notifier;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          downloadProvider.overrideWith((ref) {
            return notifier = DownloadNotifier(
              manager: manager,
              taskStore: _MemoryDownloadTaskStore([]),
              policy: () => const DownloadQueuePolicy(wifiOnly: true),
              connectionCheck: () async => false,
            );
          }),
        ],
        child: const MaterialApp(home: DownloadPage()),
      ),
    );
    await tester.pump();

    // Nothing queued yet: no banner.
    expect(find.textContaining('Wi-Fi'), findsNothing);

    await notifier.cacheSongs([_song], quality: AudioLevel.low);
    await tester.pump();

    expect(find.textContaining('Wi-Fi'), findsOneWidget);
  });
}

const _song = Song(
  id: 's1',
  platform: PlatformType.netease,
  name: 'Song 1',
  artists: [Artist(id: 'a1', name: 'Artist 1')],
);

class _RecordingDownloadManager extends DownloadManager {
  _RecordingDownloadManager()
    : super(
        directoryService: DownloadDirectoryService(
          store: _MemoryDownloadDirectoryStore(),
          defaultRootProvider: () async => throw UnimplementedError(),
        ),
      );

  final List<String> started = <String>[];

  @override
  Stream<DownloadProgress> download(DownloadTask task) {
    started.add(task.id);
    return const Stream<DownloadProgress>.empty();
  }
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
