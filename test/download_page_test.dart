import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/platform/platform_utils.dart';
import 'package:mconnect/features/download/data/download_directory_service.dart';
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
    PlatformUtils.setDebugOverride(AppPlatform.android);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
  });

  tearDown(() {
    PlatformUtils.setDebugOverride(null);
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
