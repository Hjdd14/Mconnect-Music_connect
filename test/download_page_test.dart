import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/widgets/miuix_bottom_stack.dart';
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

  testWidgets('a waiting download offers start and cancel actions', (
    tester,
  ) async {
    // P0-1: a `waiting` row (offline-cache rows and anything held back by the
    // Wi-Fi gate) rendered **no** action at all, so a queued task could not be
    // started or cancelled from the UI.
    final manager = _StubStartDownloadManager();
    final task = DownloadTask(
      id: 'netease_s1_low_cache',
      song: _song,
      quality: AudioLevel.low,
      status: DownloadStatus.waiting,
      createdAt: DateTime(2026, 5, 29),
      isOfflineCache: true,
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

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();

    expect(manager.started, ['netease_s1_low_cache']);
  });

  testWidgets('cancelling a waiting download removes it from the list', (
    tester,
  ) async {
    final manager = _StubStartDownloadManager();
    final task = DownloadTask(
      id: 'netease_s1_low_cache',
      song: _song,
      quality: AudioLevel.low,
      status: DownloadStatus.waiting,
      createdAt: DateTime(2026, 5, 29),
      isOfflineCache: true,
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

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(find.text('暂无内容'), findsOneWidget);
  });

  // ---- v1.4.1 directory guard: the sheet must never freeze or stay silent ----

  testWidgets('a rejected directory clears 保存中 and explains why', (
    tester,
  ) async {
    // The regression: `Directory.create` threw, nothing caught it, `isSaving`
    // stayed true forever — spinner spinning, every control greyed out, no
    // message — and the user had to kill the sheet.
    final store = _MemoryDownloadDirectoryStore();
    final manager = DownloadManager(
      directoryService: _directoryService(
        store: store,
        guard: const _UnwritableDirectoryGuard(),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          downloadProvider.overrideWith(
            (ref) => _StubPathDownloadNotifier(
              manager: manager,
              initialState: const DownloadState(tasks: []),
              taskStore: _MemoryDownloadTaskStore(const []),
            ),
          ),
        ],
        child: const MaterialApp(home: DownloadPage()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.folder_copy_outlined));
    await tester.pumpAndSettle();
    expect(find.text('外部存储（应用专属）'), findsOneWidget);

    await tester.tap(find.text('外部存储（应用专属）'));
    await tester.pumpAndSettle();

    expect(
      find.text('该目录不可写，请选择应用可写的位置'),
      findsWidgets,
      reason: 'the user must be told why nothing happened',
    );
    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason: 'isSaving must be reset even on failure',
    );
    final tile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('外部存储（应用专属）'),
        matching: find.byType(ListTile),
      ),
    );
    expect(tile.enabled, isTrue, reason: 'the sheet must stay usable');
    expect(
      store.customRootPath,
      isNull,
      reason: 'a directory that failed the write probe must not be persisted',
    );
  });

  testWidgets('the 保存中 spinner is visible while applying and then cleared', (
    tester,
  ) async {
    final notifier = _ControllableRootNotifier(
      manager: DownloadManager(
        directoryService: _directoryService(
          store: _MemoryDownloadDirectoryStore(),
        ),
      ),
      taskStore: _MemoryDownloadTaskStore(const []),
      initialState: const DownloadState(tasks: []),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [downloadProvider.overrideWith((ref) => notifier)],
        child: const MaterialApp(home: DownloadPage()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.folder_copy_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('外部存储（应用专属）'));
    await tester.pump();

    expect(
      find.byType(CircularProgressIndicator),
      findsOneWidget,
      reason: 'a slow apply shows progress',
    );
    expect(notifier.appliedPaths, [p.join('D:', 'ext_downloads')]);

    notifier.completeApply(
      const DownloadRootResult.failure(DownloadRootRejection.notWritable),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('该目录不可写，请选择应用可写的位置'), findsWidgets);
  });

  testWidgets('a cancelled picker stays silent and changes nothing', (
    tester,
  ) async {
    // Lead's ruling (v1.4.1): `null` means "the user cancelled" — its dominant
    // meaning — so it must not raise an error. `file_picker` also folds
    // `PlatformException("unknown_path")` into the same null and the two cases
    // cannot be told apart; the cheaper default is silence. The failure that
    // actually matters (an unwritable directory) is caught by the write probe.
    final store = _MemoryDownloadDirectoryStore();
    final manager = DownloadManager(
      directoryService: _directoryService(store: store),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          downloadProvider.overrideWith(
            (ref) => _StubPathDownloadNotifier(
              manager: manager,
              initialState: const DownloadState(tasks: []),
              taskStore: _MemoryDownloadTaskStore(const []),
            ),
          ),
        ],
        child: MaterialApp(
          home: DownloadPage(pickDirectory: (_) async => null),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.folder_copy_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择其他位置…'));
    await tester.pumpAndSettle();

    expect(
      find.text('该位置无法作为下载目录，请换一个文件夹'),
      findsNothing,
      reason: 'cancelling is a normal action, not an error',
    );
    expect(find.text('该目录不可写，请选择应用可写的位置'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(store.customRootPath, isNull);

    // Still interactive: a cancel must not freeze the sheet either.
    final tile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('外部存储（应用专属）'),
        matching: find.byType(ListTile),
      ),
    );
    expect(tile.enabled, isTrue);
  });

  testWidgets('a picker that throws is reported, not swallowed', (tester) async {
    final store = _MemoryDownloadDirectoryStore();
    final manager = DownloadManager(
      directoryService: _directoryService(store: store),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          downloadProvider.overrideWith(
            (ref) => _StubPathDownloadNotifier(
              manager: manager,
              initialState: const DownloadState(tasks: []),
              taskStore: _MemoryDownloadTaskStore(const []),
            ),
          ),
        ],
        child: MaterialApp(
          home: DownloadPage(
            pickDirectory: (_) async =>
                throw PlatformException(code: 'unknown_path'),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.folder_copy_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择其他位置…'));
    await tester.pumpAndSettle();

    expect(find.text('该位置无法作为下载目录，请换一个文件夹'), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(store.customRootPath, isNull);
  });

  testWidgets('the directory sheet offers only app-writable roots', (
    tester,
  ) async {
    final manager = DownloadManager(
      directoryService: _directoryService(
        store: _MemoryDownloadDirectoryStore(),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          downloadProvider.overrideWith(
            (ref) => _StubPathDownloadNotifier(
              manager: manager,
              initialState: const DownloadState(tasks: []),
              taskStore: _MemoryDownloadTaskStore(const []),
            ),
          ),
        ],
        child: const MaterialApp(home: DownloadPage()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.folder_copy_outlined));
    await tester.pumpAndSettle();

    expect(find.text('默认位置'), findsOneWidget);
    expect(find.text('外部存储（应用专属）'), findsOneWidget);
    expect(find.text('选择其他位置…'), findsOneWidget);
    expect(find.text('恢复默认目录'), findsOneWidget);

    // The existing "open the download folder" entry is kept.
    await tester.ensureVisible(find.text('打开下载文件夹'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开下载文件夹'));
    await tester.pump();
    expect(calls, hasLength(1));
    expect(calls.single.method, 'openFolder');
    expect(calls.single.arguments, p.join('D:', 'MconnectTestDownloads'));
  });

  testWidgets('a shell-nested sheet is pushed above the floating chrome', (
    tester,
  ) async {
    // `DownloadPage` is a home tab, so it lives in go_router's *nested* navigator,
    // inside `AppRouteShell`'s `MiuixBottomStack`. That stack paints the mini player
    // and the nav capsule **after** (i.e. on top of) its child.
    //
    // The nested navigator now fills the screen (it must, or a routed frosted sheet
    // cannot reach the bottom edge), so a sheet pushed on the *nearest* navigator
    // would be laid out under the capsule area — the chrome drawn over it. Pushing on
    // the root navigator puts the sheet above the whole shell, which is what a modal
    // sheet should cover.
    //
    // Asserted structurally rather than by pixels: "the sheet is not inside the shell
    // subtree" is exactly the property that stops the chrome drawing over it.
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
            (ref) => _StubPathDownloadNotifier(
              manager: manager,
              initialState: const DownloadState(tasks: []),
              taskStore: _MemoryDownloadTaskStore(const []),
            ),
          ),
        ],
        child: MaterialApp(
          // Stands in for `AppRouteShell`: a full-bleed stack hosting a nested
          // navigator, with the chrome painted above it.
          home: MiuixBottomStack(
            showPlayer: false,
            insetChild: false,
            child: Navigator(
              onGenerateRoute: (_) =>
                  MaterialPageRoute<void>(builder: (_) => const DownloadPage()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.folder_copy_outlined));
    await tester.pumpAndSettle();

    expect(
      find.byType(BottomSheet),
      findsOneWidget,
      reason: 'the download directory sheet must actually open',
    );
    expect(
      find.descendant(
        of: find.byType(MiuixBottomStack),
        matching: find.byType(BottomSheet),
      ),
      findsNothing,
      reason:
          'a sheet pushed on the nested navigator would be painted beneath the mini '
          'player / nav capsule; it must go on the root navigator',
    );
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

/// Resolves the download root without touching the filesystem.
///
/// The real path goes through `Directory.exists()` / `create()`, and real I/O
/// futures never complete inside a widget test's fake-async zone — the sheet would
/// simply never open, and the test would fail for a reason unrelated to what it
/// checks. This test is about paint order, so it stubs the lookup.
class _StubPathDownloadNotifier extends DownloadNotifier {
  _StubPathDownloadNotifier({
    required super.manager,
    required super.initialState,
    required super.taskStore,
  });

  @override
  Future<String> currentDownloadRootPath() async =>
      p.join('D:', 'MconnectTestDownloads');
}

/// The notifier used by the directory-sheet tests: it stubs only the I/O-bound
/// path lookup, so `availableDownloadRoots()` / `setCustomDownloadRoot()` still
/// run the real code.
class _ControllableRootNotifier extends _StubPathDownloadNotifier {
  _ControllableRootNotifier({
    required super.manager,
    required super.taskStore,
    required super.initialState,
  });

  final List<String> appliedPaths = <String>[];
  final Completer<DownloadRootResult> _apply = Completer<DownloadRootResult>();

  @override
  Future<DownloadRootResult> setCustomDownloadRoot(String path) {
    appliedPaths.add(path);
    return _apply.future;
  }

  void completeApply(DownloadRootResult result) => _apply.complete(result);
}

DownloadDirectoryService _directoryService({
  required DownloadDirectoryStore store,
  DownloadDirectoryGuard? guard,
}) => DownloadDirectoryService(
  store: store,
  // A path, not a real lookup: no I/O may happen in a widget test.
  defaultRootProvider: () async => Directory(p.join('D:', 'app_docs')),
  externalRootProvider: () async => Directory(p.join('D:', 'ext_downloads')),
  guard: guard ?? const _WritableDirectoryGuard(),
);

/// Accepts everything; the guard tests themselves live in
/// `download_directory_service_test.dart`.
class _WritableDirectoryGuard implements DownloadDirectoryGuard {
  const _WritableDirectoryGuard();

  @override
  Future<bool> exists(Directory directory) async => true;

  @override
  Future<bool> isDirectory(Directory directory) async => true;

  @override
  Future<void> create(Directory directory) async {}

  @override
  Future<void> verifyWritable(Directory directory) async {}
}

/// A guard for a directory the app may open but not write to (Android 11+
/// returns such a directory for several protected locations).
class _UnwritableDirectoryGuard implements DownloadDirectoryGuard {
  const _UnwritableDirectoryGuard();

  @override
  Future<bool> exists(Directory directory) async => true;

  @override
  Future<bool> isDirectory(Directory directory) async => true;

  @override
  Future<void> create(Directory directory) async {}

  @override
  Future<void> verifyWritable(Directory directory) async {
    throw const FileSystemException(
      'Cannot write to the directory',
      '',
      OSError('Permission denied', 13),
    );
  }
}

/// Records `download()` calls and keeps the stream open, so a started task stays
/// in the `downloading` state for the assertion.
class _StubStartDownloadManager extends DownloadManager {
  _StubStartDownloadManager()
    : super(
        directoryService: DownloadDirectoryService(
          store: _MemoryDownloadDirectoryStore(),
          defaultRootProvider: () async => throw UnimplementedError(),
        ),
      );

  final List<String> started = <String>[];
  final List<StreamController<DownloadProgress>> _controllers =
      <StreamController<DownloadProgress>>[];

  @override
  Stream<DownloadProgress> download(DownloadTask task) {
    started.add(task.id);
    final controller = StreamController<DownloadProgress>();
    _controllers.add(controller);
    return controller.stream;
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      if (!controller.isClosed) unawaited(controller.close());
    }
    _controllers.clear();
    super.dispose();
  }
}
