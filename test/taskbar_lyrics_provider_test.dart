import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/lyrics/lyrics_animation_catalog.dart';
import 'package:mconnect/core/lyrics/lyrics_overlay_sink.dart';
import 'package:mconnect/features/floating_lyrics/data/sinks/desktop_lyrics_sinks.dart';
import 'package:mconnect/features/floating_lyrics/presentation/providers/taskbar_lyrics_provider.dart';

/// Guards the taskbar status pipeline: the native events the strip emits
/// (geometryChanged / taskbarStateChanged / positionChanged / closedByUser) must
/// reach Dart, and refresh() must actually ask the native channel for the real
/// taskbar geometry instead of guessing it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const taskbarChannel = MethodChannel(LyricsChannels.taskbar);
  const floatingChannel = MethodChannel(LyricsChannels.floating);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(taskbarChannel, null)
      ..setMockMethodCallHandler(floatingChannel, null);
  });

  test('the status starts as an empty, hidden strip', () {
    const status = TaskbarLyricsStatus();

    expect(status.found, isFalse);
    expect(status.spaceInsufficient, isFalse);
    expect(status.autoHide, isFalse);
    expect(status.edge, 'bottom');
    expect(status.monitors, isEmpty);
    expect(status.taskbars, isEmpty);
    expect(status.lastError, isNull);
  });

  test('native taskbar events update the status state', () async {
    final events = StreamController<TaskbarLyricsEvent>.broadcast();
    final notifier = TaskbarLyricsStatusNotifier();
    addTearDown(notifier.dispose);
    notifier.attach(events.stream);

    events.add(
      const TaskbarLyricsEvent('taskbarStateChanged', <String, Object?>{
        'autoHide': true,
        'edge': 'top',
        'spaceInsufficient': false,
      }),
    );
    await pumpEventQueue();

    expect(notifier.state.autoHide, isTrue);
    expect(notifier.state.edge, 'top');
    expect(notifier.state.spaceInsufficient, isFalse);
    expect(notifier.state.found, isTrue);

    events.add(
      const TaskbarLyricsEvent('taskbarStateChanged', <String, Object?>{
        'autoHide': true,
        'edge': 'left',
        'spaceInsufficient': true,
      }),
    );
    await pumpEventQueue();

    expect(notifier.state.edge, 'left');
    expect(notifier.state.spaceInsufficient, isTrue);

    events.add(
      const TaskbarLyricsEvent('positionChanged', <String, Object?>{
        'offsetX': 24.0,
        'width': 720.0,
      }),
    );
    await pumpEventQueue();

    expect(notifier.state.offsetX, 24.0);
    expect(notifier.state.width, 720.0);

    await events.close();
  });

  test('the live placement reaches the status (the slider answer)', () async {
    final events = StreamController<TaskbarLyricsEvent>.broadcast();
    final notifier = TaskbarLyricsStatusNotifier();
    addTearDown(notifier.dispose);
    notifier.attach(events.stream);

    events.add(
      const TaskbarLyricsEvent('taskbarPlacement', <String, Object?>{
        'left': 1200.0,
        'top': 1392.0,
        'width': 980.0,
        'height': 56.0,
        'visible': true,
      }),
    );
    await pumpEventQueue();

    final rect = notifier.state.placement;
    expect(rect, isNotNull);
    expect(rect!.left, 1200.0);
    expect(rect.top, 1392.0);
    expect(rect.width, 980.0);
    expect(rect.height, 56.0);

    // Hiding the strip clears the rectangle instead of leaving a stale one.
    events.add(
      const TaskbarLyricsEvent('taskbarPlacement', <String, Object?>{
        'visible': false,
      }),
    );
    await pumpEventQueue();
    expect(notifier.state.placement, isNull);

    await events.close();
  });

  test('a dragged offset is committed once, after the drag settles', () async {
    final events = StreamController<TaskbarLyricsEvent>.broadcast();
    final committed = <double>[];
    final notifier = TaskbarLyricsStatusNotifier(
      onDragOffset: committed.add,
    );
    addTearDown(notifier.dispose);
    notifier.attach(events.stream);

    for (final offset in <double>[40, 90, 150]) {
      events.add(
        TaskbarLyricsEvent('dragOffset', <String, Object?>{
          'offsetX': offset,
          'width': 980.0,
        }),
      );
    }
    await pumpEventQueue();
    // Nothing written while the pointer is still moving.
    expect(committed, isEmpty);
    expect(notifier.state.offsetX, 150.0);

    await Future<void>.delayed(const Duration(milliseconds: 260));
    expect(committed, <double>[150]);

    await events.close();
  });

  test('refresh asks the native channels for geometry and monitors', () async {
    final taskbarCalls = <MethodCall>[];
    final floatingCalls = <MethodCall>[];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(floatingChannel, (call) async {
        floatingCalls.add(call);
        if (call.method != 'getMonitors') return null;
        return <Object?>[
          <String, Object?>{
            'deviceName': 'DISPLAY1',
            'left': 0,
            'top': 0,
            'right': 1920,
            'bottom': 1080,
            'dpi': 96,
            'isPrimary': true,
          },
        ];
      })
      ..setMockMethodCallHandler(taskbarChannel, (call) async {
        taskbarCalls.add(call);
        return switch (call.method) {
          'refreshGeometry' => true,
          'getTaskbarInfo' => <Object?>[
            <String, Object?>{
              'monitor': 'DISPLAY1',
              'edge': 'bottom',
              'thickness': 48,
              'taskbarRect': <String, Object?>{
                'left': 0,
                'top': 1032,
                'right': 1920,
                'bottom': 1080,
              },
              'freeRect': <String, Object?>{
                'left': 0,
                'top': 1032,
                'right': 1400,
                'bottom': 1080,
              },
              'dpi': 96,
              'autoHide': false,
            },
          ],
          _ => null,
        };
      });

    final notifier = TaskbarLyricsStatusNotifier(
      sinks: <LyricsOverlaySink>[
        WindowsFloatingLyricsSink(),
        WindowsTaskbarLyricsSink(),
      ],
    );
    addTearDown(notifier.dispose);

    await notifier.refresh();

    expect(
      taskbarCalls.map((call) => call.method),
      containsAll(<String>['refreshGeometry', 'getTaskbarInfo']),
    );
    expect(floatingCalls.map((call) => call.method), contains('getMonitors'));

    expect(notifier.state.monitors, hasLength(1));
    expect(notifier.state.monitors.single.deviceName, 'DISPLAY1');
    expect(notifier.state.taskbars, hasLength(1));
    expect(notifier.state.taskbars.single.thickness, 48);
    expect(notifier.state.found, isTrue);
    expect(notifier.state.edge, 'bottom');
    expect(notifier.state.autoHide, isFalse);
    expect(notifier.state.spaceInsufficient, isFalse);
    expect(notifier.state.lastError, isNull);
  });

  test('refresh without a native strip reports "not found"', () async {
    final notifier = TaskbarLyricsStatusNotifier();
    addTearDown(notifier.dispose);

    await notifier.refresh();

    expect(notifier.state.found, isFalse);
    expect(notifier.state.taskbars, isEmpty);
    expect(notifier.state.monitors, isEmpty);
  });

  test(
    'the sinks provider hands the status notifier the shared instances',
    () async {
      final taskbar = _RecordingTaskbarSink();
      final container = ProviderContainer(
        overrides: <Override>[
          desktopLyricsSinksProvider.overrideWithValue(<LyricsOverlaySink>[
            taskbar,
          ]),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(taskbarLyricsStatusProvider.notifier);
      await notifier.refresh();

      expect(
        taskbar.calls,
        containsAll(<String>['refreshGeometry', 'getTaskbarInfo']),
      );
      expect(notifier.state.found, isTrue);
    },
  );

  test('the sinks provider caches one set of instances', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final first = container.read(desktopLyricsSinksProvider);
    final second = container.read(desktopLyricsSinksProvider);

    expect(identical(first, second), isTrue);
  });
}

class _RecordingTaskbarSink extends LyricsOverlaySink {
  final List<String> calls = <String>[];

  @override
  LyricsSurface get surface => LyricsSurface.taskbar;

  @override
  Future<bool> refreshGeometry() async {
    calls.add('refreshGeometry');
    return true;
  }

  @override
  Future<List<LyricsTaskbarInfo>> getTaskbarInfo() async {
    calls.add('getTaskbarInfo');
    return const <LyricsTaskbarInfo>[
      LyricsTaskbarInfo(
        monitor: 'DISPLAY1',
        edge: 'bottom',
        thickness: 48,
        autoHide: false,
      ),
    ];
  }
}
