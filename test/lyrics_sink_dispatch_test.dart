import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/core/lyrics/lyrics_animation_catalog.dart';
import 'package:mconnect/core/lyrics/lyrics_overlay_config.dart';
import 'package:mconnect/core/lyrics/lyrics_overlay_frame.dart';
import 'package:mconnect/core/lyrics/lyrics_overlay_sink.dart';
import 'package:mconnect/features/floating_lyrics/data/sinks/desktop_lyrics_sinks.dart';
import 'package:mconnect/features/floating_lyrics/presentation/providers/floating_lyrics_provider.dart';
import 'package:mconnect/features/floating_lyrics/presentation/providers/taskbar_lyrics_provider.dart';
import 'package:mconnect/features/player/presentation/providers/lyrics_provider.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/lyrics/models/lyrics_line.dart';
import 'package:mconnect/models/album.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

import 'support/content_page_fakes.dart';

/// Guards the multi-sink dispatch: which surface receives which frame, and the
/// exact method/field sets each native window is frozen to.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mconnect_lyrics_sink_');
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(LyricsChannels.floating),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(LyricsChannels.taskbar),
          null,
        );
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  ProviderContainer buildContainer({_TestPlayerNotifier? player}) {
    final container = ProviderContainer(
      overrides: [
        playerProvider.overrideWith((ref) => player ?? _TestPlayerNotifier()),
        lyricsProvider.overrideWith((ref) async => _document),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Provider<FloatingLyricsSyncController> syncProviderWith(
    List<LyricsOverlaySink> sinks,
  ) {
    return Provider<FloatingLyricsSyncController>((ref) {
      final controller = FloatingLyricsSyncController(ref, sinks: sinks);
      ref.onDispose(controller.dispose);
      return controller;
    });
  }

  test('both enabled windows receive the same shared frame', () async {
    final floating = _RecordingSink(LyricsSurface.floating);
    final taskbar = _RecordingSink(LyricsSurface.taskbar);
    final container = buildContainer();
    await container.read(lyricsProvider.future);
    container.read(syncProviderWith(<LyricsOverlaySink>[floating, taskbar]));

    await container.read(floatingLyricsProvider.notifier).setEnabled(true);
    await pumpEventQueue();
    await container.read(taskbarLyricsProvider.notifier).setEnabled(true);
    await pumpEventQueue();

    expect(floating.frames, isNotEmpty);
    expect(floating.calls, contains('ensureAvailable'));
    expect(floating.calls, contains('configure'));
    expect(taskbar.frames, isNotEmpty);
    expect(taskbar.calls, contains('configure'));

    final frame = taskbar.frames.last;
    expect(frame.text, 'First line');
    expect(frame.songTitle, 'Sink Song');
    expect(frame.artistName, 'Sink Artist');
    expect(frame.albumName, 'Sink Album');
    expect(frame.coverUrl, 'https://example.test/cover.jpg');
    expect(frame.hasSong, isTrue);
    expect(frame.isPlaying, isFalse);
    expect(frame.revision, greaterThan(0));
    expect(floating.frames.last.text, taskbar.frames.last.text);
  });

  test('only the enabled surface is pushed to', () async {
    final floating = _RecordingSink(LyricsSurface.floating);
    final taskbar = _RecordingSink(LyricsSurface.taskbar);
    final container = buildContainer();
    await container.read(lyricsProvider.future);
    container.read(syncProviderWith(<LyricsOverlaySink>[floating, taskbar]));

    await container.read(floatingLyricsProvider.notifier).setEnabled(true);
    await pumpEventQueue();

    expect(floating.frames, isNotEmpty);
    expect(taskbar.frames, isEmpty);
  });

  test(
    'switching songs refreshes the metadata pushed to the windows',
    () async {
      final player = _TestPlayerNotifier();
      final taskbar = _RecordingSink(LyricsSurface.taskbar);
      final container = buildContainer(player: player);
      await container.read(lyricsProvider.future);
      container.read(syncProviderWith(<LyricsOverlaySink>[taskbar]));

      await container.read(taskbarLyricsProvider.notifier).setEnabled(true);
      await pumpEventQueue();
      expect(taskbar.frames.last.songTitle, 'Sink Song');

      player.setSong(_otherSong);
      await pumpEventQueue();

      expect(taskbar.frames.last.songTitle, 'Other Song');
      expect(taskbar.frames.last.artistName, 'Other Artist');
      expect(taskbar.frames.last.albumName, 'Other Album');
      expect(taskbar.frames.last.coverUrl, 'https://example.test/other.jpg');
    },
  );

  test('frameFor carries song progress, line index and word boundaries', () {
    const document = LyricsDocument(
      lines: <LyricsLine>[
        LyricsLine(
          timestamp: Duration.zero,
          text: 'ABCD EF',
          words: <WordTiming>[
            WordTiming(
              word: 'ABCD',
              start: Duration.zero,
              duration: Duration(seconds: 1),
            ),
            WordTiming(
              word: ' EF',
              start: Duration(seconds: 1),
              duration: Duration(seconds: 1),
            ),
          ],
        ),
        LyricsLine(timestamp: Duration(seconds: 2), text: 'next line'),
      ],
    );

    final frame = FloatingLyricsSyncController.frameFor(
      document,
      const Duration(milliseconds: 500),
      songDuration: const Duration(seconds: 10),
      isPlaying: true,
      hasSong: true,
      revision: 3,
      songTitle: 'T',
      artistName: 'A',
      coverUrl: 'https://example.test/c.jpg',
    );

    expect(frame.lineIndex, 0);
    expect(frame.text, 'ABCD EF');
    expect(frame.nextText, 'next line');
    expect(frame.highlightProgress, closeTo(2 / 7, 1e-9));
    expect(frame.wordSegments, isNotNull);
    expect(frame.wordSegments, hasLength(2));
    expect(frame.wordSegments!.first, closeTo(0.5, 1e-9));
    expect(frame.wordSegments!.last, closeTo(1.0, 1e-9));
    expect(frame.progress, closeTo(0.05, 1e-9));
    expect(frame.revision, 3);
    expect(frame.isPlaying, isTrue);
  });

  test(
    'a line change is pushed immediately and a seek jumps lineIndex',
    () async {
      final player = _TestPlayerNotifier();
      final taskbar = _RecordingSink(LyricsSurface.taskbar);
      final container = buildContainer(player: player);
      await container.read(lyricsProvider.future);
      final controller = container.read(
        syncProviderWith(<LyricsOverlaySink>[taskbar]),
      );

      await container.read(taskbarLyricsProvider.notifier).setEnabled(true);
      await pumpEventQueue();
      expect(taskbar.frames.last.lineIndex, 0);
      expect(taskbar.frames.last.nextText, 'Second line');

      player.setPosition(const Duration(seconds: 12));
      await pumpEventQueue();
      expect(taskbar.frames.last.lineIndex, 1);
      expect(taskbar.frames.last.text, 'Second line');

      player.setPosition(const Duration(seconds: 52));
      await pumpEventQueue();
      expect(taskbar.frames.last.lineIndex, 2);
      expect(taskbar.frames.last.text, 'Third line');
      expect(
        taskbar.frames.last.revision,
        greaterThan(taskbar.frames.first.revision),
      );
      expect(controller.frameRevisionForTest, greaterThan(0));
    },
  );

  test('no sweep and no frame while both windows are off', () async {
    final player = _TestPlayerNotifier()..setPlaying(true);
    final floating = _RecordingSink(LyricsSurface.floating);
    final taskbar = _RecordingSink(LyricsSurface.taskbar);
    final container = buildContainer(player: player);
    await container.read(lyricsProvider.future);
    container.read(syncProviderWith(<LyricsOverlaySink>[floating, taskbar]));

    await Future<void>.delayed(const Duration(milliseconds: 350));
    final hidesBefore = floating.calls.where((call) => call == 'hide').length;

    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(floating.frames, isEmpty);
    expect(taskbar.frames, isEmpty);
    expect(floating.calls, isNot(contains('update')));
    expect(taskbar.calls, isNot(contains('update')));
    // A running 200 ms sweep would keep hiding the (already hidden) window.
    expect(floating.calls.where((call) => call == 'hide').length, hidesBefore);
  });

  test('a denied overlay permission skips the frame', () async {
    final floating = _RecordingSink(LyricsSurface.floating, available: false);
    final container = buildContainer();
    await container.read(lyricsProvider.future);
    container.read(syncProviderWith(<LyricsOverlaySink>[floating]));

    await container.read(floatingLyricsProvider.notifier).setEnabled(true);
    await pumpEventQueue();

    expect(floating.calls, contains('ensureAvailable'));
    expect(floating.frames, isEmpty);
  });

  test('preview forwards the protocol argument shape', () async {
    final floating = _RecordingSink(LyricsSurface.floating);
    final taskbar = _RecordingSink(LyricsSurface.taskbar);
    final container = buildContainer();
    final controller = container.read(
      syncProviderWith(<LyricsOverlaySink>[floating, taskbar]),
    );

    final handled = await controller.preview(
      const LyricsPreviewRequest(
        animation: LyricsLineTransition.wipeRight,
        sampleLines: <LyricsPreviewLine>[
          LyricsPreviewLine(text: '样例', translation: 'sample'),
        ],
        durationMs: 1500,
      ),
    );

    expect(handled, isTrue);
    expect(floating.previews, hasLength(1));
    expect(taskbar.previews, hasLength(1));
    expect(floating.previews.single.toJson(), <String, Object?>{
      'animation': 'wipeRight',
      'sampleLines': <Object?>[
        <String, Object?>{'text': '样例', 'translation': 'sample'},
      ],
      'durationMs': 1500,
    });
  });

  test('the legacy Android sink keeps its frozen method/field sets', () async {
    const channel = MethodChannel(LyricsChannels.floating);
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'canDrawOverlays' => true,
            'hide' => true,
            'update' => true,
            _ => null,
          };
        });

    final container = buildContainer();
    await container.read(lyricsProvider.future);
    container.read(syncProviderWith(const <LyricsOverlaySink>[]));

    await container.read(floatingLyricsProvider.notifier).setEnabled(true);
    await pumpEventQueue();

    final methods = calls.map((call) => call.method).toSet();
    expect(methods, containsAll(<String>['canDrawOverlays', 'update']));
    expect(
      methods.difference(<String>{'canDrawOverlays', 'hide', 'update'}),
      isEmpty,
    );

    final update = calls.firstWhere((call) => call.method == 'update');
    final args = update.arguments as Map<Object?, Object?>;
    expect(args.keys.toSet(), _legacyAndroidKeys);
    expect(args.containsKey('lineIndex'), isFalse);
    expect(args.containsKey('songTitle'), isFalse);
  });

  test(
    'the Windows sinks split frame from style on their own channels',
    () async {
      final floatingCalls = <MethodCall>[];
      final taskbarCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(LyricsChannels.floating),
            (call) async {
              floatingCalls.add(call);
              return true;
            },
          );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(LyricsChannels.taskbar),
            (call) async {
              taskbarCalls.add(call);
              return true;
            },
          );

      final container = buildContainer();
      await container.read(lyricsProvider.future);
      container.read(
        syncProviderWith(<LyricsOverlaySink>[
          WindowsFloatingLyricsSink(),
          WindowsTaskbarLyricsSink(),
        ]),
      );

      await container.read(floatingLyricsProvider.notifier).setEnabled(true);
      await pumpEventQueue();
      await container.read(taskbarLyricsProvider.notifier).setEnabled(true);
      await pumpEventQueue();

      expect(
        floatingCalls.map((call) => call.method),
        containsAll(<String>['canDrawOverlays', 'configure', 'update']),
      );
      expect(
        taskbarCalls.map((call) => call.method),
        containsAll(<String>['configure', 'update']),
      );
      expect(
        taskbarCalls.map((call) => call.method),
        isNot(contains('canDrawOverlays')),
      );

      final floatingUpdate = floatingCalls.firstWhere(
        (call) => call.method == 'update',
      );
      final floatingArgs = floatingUpdate.arguments as Map<Object?, Object?>;
      // Superset of the old payload: the pre-rewrite native window still reads
      // the style from update, the new one ignores it.
      expect(floatingArgs['textColor'], isA<int>());
      expect(floatingArgs['lineIndex'], isA<int>());
      expect(floatingArgs['songTitle'], 'Sink Song');
      expect(floatingArgs['revision'], isA<int>());
      expect(floatingArgs['text'], 'First line');

      final taskbarUpdate = taskbarCalls.lastWhere(
        (call) => call.method == 'update',
      );
      final taskbarArgs = taskbarUpdate.arguments as Map<Object?, Object?>;
      expect(taskbarArgs.containsKey('textColor'), isFalse);
      expect(taskbarArgs.containsKey('lineAnimation'), isFalse);
      expect(taskbarArgs['lineIndex'], 0);
      expect(taskbarArgs['nextText'], 'Second line');
      expect(taskbarArgs.containsKey('nextTranslation'), isFalse);

      final taskbarConfigure = taskbarCalls.firstWhere(
        (call) => call.method == 'configure',
      );
      final configArgs = taskbarConfigure.arguments as Map<Object?, Object?>;
      expect(configArgs['enabled'], isTrue);
      expect(configArgs['anchor'], 'auto');
      expect(configArgs['lineAnimation'], 'slideLeft');
      expect(configArgs['animationDurationMs'], 200);
      expect(configArgs.containsKey('positionX'), isFalse);
    },
  );

  test('getMonitors parses the native monitor reply', () async {
    const channel = MethodChannel(LyricsChannels.floating);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'getMonitors') return null;
          return <Object?>[
            <String, Object?>{
              'deviceName': 'DISPLAY1',
              'left': 0,
              'top': 0,
              'right': 1920,
              'bottom': 1080,
              'dpi': 120,
              'isPrimary': true,
            },
          ];
        });

    final monitors = await WindowsFloatingLyricsSink().getMonitors();

    expect(monitors, hasLength(1));
    expect(monitors.single.deviceName, 'DISPLAY1');
    expect(monitors.single.dpi, 120);
    expect(monitors.single.isPrimary, isTrue);
    expect(monitors.single.bounds.width, 1920);
    expect(monitors.single.bounds.height, 1080);
  });

  test('getTaskbarInfo parses the native geometry reply', () async {
    const channel = MethodChannel(LyricsChannels.taskbar);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'refreshGeometry') return true;
          if (call.method != 'getTaskbarInfo') return null;
          return <Object?>[
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
              'trayRect': <String, Object?>{},
              'taskListRect': <String, Object?>{},
              'dpi': 96,
              'autoHide': false,
            },
          ];
        });

    final sink = WindowsTaskbarLyricsSink();
    final info = await sink.getTaskbarInfo();

    expect(info, hasLength(1));
    expect(info.single.monitor, 'DISPLAY1');
    expect(info.single.thickness, 48);
    expect(info.single.taskbarRect.top, 1032);
    expect(info.single.freeRect.right, 1400);
    expect(info.single.autoHide, isFalse);
    expect(await sink.refreshGeometry(), isTrue);
  });

  test('a disabled sink degrades to false instead of throwing', () async {
    final monitors = await WindowsFloatingLyricsSink().getMonitors();
    final hidden = await WindowsTaskbarLyricsSink().hide();

    expect(monitors, isEmpty);
    expect(hidden, isFalse);
  });

  test('native taskbar events reach the sink event stream', () async {
    final sink = WindowsTaskbarLyricsSink();
    addTearDown(sink.dispose);
    final events = <TaskbarLyricsEvent>[];
    final subscription = sink.eventStream.listen(events.add);

    await _sendNativeTaskbarCall('geometryChanged');
    await _sendNativeTaskbarCall('taskbarStateChanged', <String, Object?>{
      'autoHide': true,
      'edge': 'top',
      'spaceInsufficient': true,
    });
    await _sendNativeTaskbarCall('positionChanged', <String, Object?>{
      'offsetX': 12.0,
      'width': 640.0,
    });
    await _sendNativeTaskbarCall('closedByUser');
    await pumpEventQueue();
    await subscription.cancel();

    expect(events.map((event) => event.name), <String>[
      'geometryChanged',
      'taskbarStateChanged',
      'positionChanged',
      'closedByUser',
    ]);

    final state = events[1];
    expect(state.autoHide, isTrue);
    expect(state.edge, 'top');
    expect(state.spaceInsufficient, isTrue);

    final position = events[2];
    expect(position.offsetX, 12.0);
    expect(position.width, 640.0);
  });
}

Future<void> _sendNativeTaskbarCall(String method, [Object? arguments]) {
  const codec = StandardMethodCodec();
  return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        LyricsChannels.taskbar,
        codec.encodeMethodCall(MethodCall(method, arguments)),
        (_) {},
      );
}

const Set<String> _legacyAndroidKeys = <String>{
  'enabled',
  'textColor',
  'highlightColor',
  'backgroundColor',
  'fontSize',
  'strokeWidth',
  'shadowOpacity',
  'width',
  'height',
  'isLocked',
  'positionY',
  'text',
  'translation',
  'progress',
  'nextText',
  'highlightProgress',
  'highlightRate',
  'isPlaying',
  'hasSong',
};

const _song = Song(
  id: 'sink-song',
  platform: PlatformType.netease,
  name: 'Sink Song',
  artists: <Artist>[Artist(id: 'sink-artist', name: 'Sink Artist')],
  album: Album(id: 'sink-album', name: 'Sink Album'),
  coverUrl: 'https://example.test/cover.jpg',
  duration: Duration(minutes: 3),
);

const _otherSong = Song(
  id: 'sink-song-2',
  platform: PlatformType.netease,
  name: 'Other Song',
  artists: <Artist>[Artist(id: 'other-artist', name: 'Other Artist')],
  album: Album(id: 'other-album', name: 'Other Album'),
  coverUrl: 'https://example.test/other.jpg',
  duration: Duration(minutes: 3),
);

const _document = LyricsDocument(
  lines: <LyricsLine>[
    LyricsLine(timestamp: Duration.zero, text: 'First line'),
    LyricsLine(timestamp: Duration(seconds: 10), text: 'Second line'),
    LyricsLine(timestamp: Duration(seconds: 50), text: 'Third line'),
  ],
);

class _TestPlayerNotifier extends PlayerNotifier {
  _TestPlayerNotifier()
    : super(
        audioController: IdleAudioController(),
        audioControllerFactory: IdleAudioController.new,
      ) {
    state = state.copyWith(
      currentSong: _song,
      playlist: const <Song>[_song],
      currentIndex: 0,
      position: Duration.zero,
      duration: const Duration(minutes: 3),
    );
  }

  void setPosition(Duration position) {
    state = state.copyWith(position: position);
  }

  void setPlaying(bool isPlaying) {
    state = state.copyWith(isPlaying: isPlaying);
  }

  void setSong(Song song) {
    state = state.copyWith(currentSong: song, playlist: <Song>[song]);
  }
}

class _RecordingSink extends LyricsOverlaySink {
  _RecordingSink(this.surface, {this.available = true});

  @override
  final LyricsSurface surface;

  final bool available;
  final List<String> calls = <String>[];
  final List<LyricsOverlayFrame> frames = <LyricsOverlayFrame>[];
  final List<LyricsOverlayConfig> configs = <LyricsOverlayConfig>[];
  final List<LyricsPreviewRequest> previews = <LyricsPreviewRequest>[];

  @override
  bool get supportsPreview => true;

  @override
  Future<bool> configure(LyricsOverlayConfig config) async {
    calls.add('configure');
    configs.add(config);
    return true;
  }

  @override
  Future<bool> update(
    LyricsOverlayFrame frame,
    LyricsOverlayConfig config,
  ) async {
    calls.add('update');
    frames.add(frame);
    return true;
  }

  @override
  Future<bool> hide() async {
    calls.add('hide');
    return true;
  }

  @override
  Future<bool> ensureAvailable() async {
    calls.add('ensureAvailable');
    return available;
  }

  @override
  Future<bool> preview(LyricsPreviewRequest request) async {
    calls.add('preview');
    previews.add(request);
    return true;
  }
}
