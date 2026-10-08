import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:mconnect/features/player/presentation/providers/lyrics_offset_provider.dart';
import 'package:mconnect/features/player/presentation/providers/lyrics_provider.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/features/floating_lyrics/data/floating_lyrics_models.dart';
import 'package:mconnect/features/floating_lyrics/presentation/providers/floating_lyrics_provider.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/lyrics/models/lyrics_line.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'mconnect_floating_lyrics_test_',
    );
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.mconnect.mconnect/floating_lyrics'),
          null,
        );
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('floating lyrics settings persist enabled and style values', () async {
    final notifier = FloatingLyricsNotifier();
    await notifier.ready;

    await notifier.setEnabled(true);
    await notifier.setLocked(true);
    await notifier.setTextColor(const Color(0xFF00FFAA));
    await notifier.setHighlightColor(const Color(0xFFFFCC00));
    await notifier.setFontSize(30);

    final restored = FloatingLyricsNotifier();
    await restored.ready;

    expect(restored.state.enabled, isTrue);
    expect(restored.state.isLocked, isTrue);
    expect(restored.state.textColor, const Color(0xFF00FFAA));
    expect(restored.state.highlightColor, const Color(0xFFFFCC00));
    expect(restored.state.fontSize, 30);
    expect(restored.state.backgroundColor, Colors.transparent);
  });

  test('native resize event updates and persists window size', () async {
    final container = ProviderContainer();
    container.read(floatingLyricsSyncProvider);

    await _sendNativeFloatingLyricsCall('windowResized', {
      'width': 468,
      'height': 128,
    });
    await pumpEventQueue();

    expect(container.read(floatingLyricsProvider).width, 468);
    expect(container.read(floatingLyricsProvider).height, 128);
    container.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final restored = FloatingLyricsNotifier();
    addTearDown(restored.dispose);
    await restored.ready;
    expect(restored.state.width, 468);
    expect(restored.state.height, 128);
  });

  test(
    'native close event turns off and persists the floating lyrics switch',
    () async {
      final container = ProviderContainer();
      container.read(floatingLyricsSyncProvider);

      await container.read(floatingLyricsProvider.notifier).setEnabled(true);
      expect(container.read(floatingLyricsProvider).enabled, isTrue);

      await _sendNativeFloatingLyricsCall('closedByUser');
      await pumpEventQueue();

      expect(container.read(floatingLyricsProvider).enabled, isFalse);
      container.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final restored = FloatingLyricsNotifier();
      addTearDown(restored.dispose);
      await restored.ready;
      expect(restored.state.enabled, isFalse);
    },
  );

  test(
    'native lock event updates and persists the floating lyrics lock state',
    () async {
      final container = ProviderContainer();
      container.read(floatingLyricsSyncProvider);

      await _sendNativeFloatingLyricsCall('lockChanged', true);
      await pumpEventQueue();

      expect(container.read(floatingLyricsProvider).isLocked, isTrue);
      container.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final restored = FloatingLyricsNotifier();
      addTearDown(restored.dispose);
      await restored.ready;
      expect(restored.state.isLocked, isTrue);
    },
  );

  test('payloadForPosition returns the active timed lyric line', () {
    const document = LyricsDocument(
      lines: [
        LyricsLine(timestamp: Duration(seconds: 3), text: 'First'),
        LyricsLine(
          timestamp: Duration(seconds: 8),
          text: 'Second',
          translation: '第二句',
        ),
        LyricsLine(timestamp: Duration(seconds: 12), text: 'Third'),
      ],
    );

    final payload = FloatingLyricsSyncController.payloadForPosition(
      document,
      const Duration(seconds: 9),
    );

    expect(payload.text, 'Second');
    expect(payload.translation, '第二句');
  });

  test('payloadForPosition returns first text when no line is active yet', () {
    const document = LyricsDocument(
      lines: [LyricsLine(timestamp: Duration(seconds: 3), text: 'First')],
    );

    final payload = FloatingLyricsSyncController.payloadForPosition(
      document,
      const Duration(seconds: 1),
    );

    expect(payload.text, 'First');
    expect(payload.translation, isNull);
  });

  test('payloadForPosition uses the first lyric before its timestamp', () {
    const document = LyricsDocument(
      lines: [
        LyricsLine(timestamp: Duration(seconds: 3), text: 'Opening line'),
        LyricsLine(timestamp: Duration(seconds: 8), text: 'Second line'),
      ],
    );

    final payload = FloatingLyricsSyncController.payloadForPosition(
      document,
      const Duration(seconds: 1),
    );

    expect(payload.text, 'Opening line');
  });

  test('sync does not send empty native updates before lyrics load', () async {
    const channel = MethodChannel('com.mconnect.mconnect/floating_lyrics');
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
    final container = ProviderContainer();
    container.read(floatingLyricsSyncProvider);

    await container.read(floatingLyricsProvider.notifier).setEnabled(true);
    await pumpEventQueue();

    expect(calls.map((call) => call.method), isNot(contains('update')));
    container.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  test(
    'sync keeps the same lyric line while only the played progress advances',
    () async {
      const channel = MethodChannel('com.mconnect.mconnect/floating_lyrics');
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

      const document = LyricsDocument(
        lines: [
          LyricsLine(
            timestamp: Duration.zero,
            text:
                'This long lyric should stay visible while the position ticks',
          ),
          LyricsLine(timestamp: Duration(seconds: 10), text: 'Next lyric'),
        ],
      );
      final player = _FloatingLyricsTestPlayerNotifier();
      final container = ProviderContainer(
        overrides: [
          playerProvider.overrideWith((ref) => player),
          lyricsProvider.overrideWith((ref) async => document),
        ],
      );
      addTearDown(container.dispose);
      await container.read(lyricsProvider.future);
      container.read(floatingLyricsSyncProvider);

      await container.read(floatingLyricsProvider.notifier).setEnabled(true);
      await pumpEventQueue();
      player.setPosition(const Duration(seconds: 3));
      await pumpEventQueue();
      player.setPosition(const Duration(seconds: 6));
      await pumpEventQueue();

      final updates = calls.where((call) => call.method == 'update').toList();
      expect(updates, isNotEmpty);
      // Only the highlight advances; the line itself never re-sends.
      for (final call in updates) {
        expect(
          (call.arguments as Map<Object?, Object?>)['text'],
          document.lines.first.text,
        );
      }
      expect(
        updates.map(
          (call) =>
              (call.arguments as Map<Object?, Object?>)['highlightProgress'],
        ),
        [0.0, closeTo(0.3, 0.001), closeTo(0.6, 0.001)],
      );

      // Repeating the same position must not produce another update.
      final applied = updates.length;
      player.setPosition(const Duration(seconds: 6));
      await pumpEventQueue();
      expect(calls.where((call) => call.method == 'update').length, applied);
    },
  );

  test('sync updates native overlay when the active lyric changes', () async {
    const channel = MethodChannel('com.mconnect.mconnect/floating_lyrics');
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

    const document = LyricsDocument(
      lines: [
        LyricsLine(timestamp: Duration.zero, text: 'First lyric'),
        LyricsLine(timestamp: Duration(seconds: 10), text: 'Second lyric'),
      ],
    );
    final player = _FloatingLyricsTestPlayerNotifier();
    final container = ProviderContainer(
      overrides: [
        playerProvider.overrideWith((ref) => player),
        lyricsProvider.overrideWith((ref) async => document),
      ],
    );
    addTearDown(container.dispose);
    await container.read(lyricsProvider.future);
    container.read(floatingLyricsSyncProvider);

    await container.read(floatingLyricsProvider.notifier).setEnabled(true);
    await pumpEventQueue();
    player.setPosition(const Duration(seconds: 11));
    await pumpEventQueue();

    final updates = calls.where((call) => call.method == 'update').toList();
    expect(updates, hasLength(2));
    expect(
      (updates.last.arguments as Map<Object?, Object?>)['text'],
      'Second lyric',
    );
  });

  test(
    'sync updates native overlay when style changes for the same lyric',
    () async {
      const channel = MethodChannel('com.mconnect.mconnect/floating_lyrics');
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

      const document = LyricsDocument(
        lines: [LyricsLine(timestamp: Duration.zero, text: 'Styled lyric')],
      );
      final player = _FloatingLyricsTestPlayerNotifier();
      final container = ProviderContainer(
        overrides: [
          playerProvider.overrideWith((ref) => player),
          lyricsProvider.overrideWith((ref) async => document),
        ],
      );
      addTearDown(container.dispose);
      await container.read(lyricsProvider.future);
      container.read(floatingLyricsSyncProvider);

      await container.read(floatingLyricsProvider.notifier).setEnabled(true);
      await pumpEventQueue();
      await container
          .read(floatingLyricsProvider.notifier)
          .setTextColor(const Color(0xFF00FFAA));
      await pumpEventQueue();

      final updates = calls.where((call) => call.method == 'update').toList();
      expect(updates, hasLength(2));
      final latestArgs = updates.last.arguments as Map<Object?, Object?>;
      expect(latestArgs['text'], 'Styled lyric');
      expect(latestArgs['textColor'], const Color(0xFF00FFAA).toARGB32());
    },
  );

  test(
    'sync sends the current lyric again after close and re-enable',
    () async {
      const channel = MethodChannel('com.mconnect.mconnect/floating_lyrics');
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

      const document = LyricsDocument(
        lines: [LyricsLine(timestamp: Duration.zero, text: 'Reopened lyric')],
      );
      final player = _FloatingLyricsTestPlayerNotifier();
      final container = ProviderContainer(
        overrides: [
          playerProvider.overrideWith((ref) => player),
          lyricsProvider.overrideWith((ref) async => document),
        ],
      );
      addTearDown(container.dispose);
      await container.read(lyricsProvider.future);
      container.read(floatingLyricsSyncProvider);

      await container.read(floatingLyricsProvider.notifier).setEnabled(true);
      await pumpEventQueue();
      await _sendNativeFloatingLyricsCall('closedByUser');
      await pumpEventQueue();
      await container.read(floatingLyricsProvider.notifier).setEnabled(true);
      await pumpEventQueue();

      final updates = calls.where((call) => call.method == 'update').toList();
      expect(updates, hasLength(2));
      expect(
        (updates.last.arguments as Map<Object?, Object?>)['text'],
        'Reopened lyric',
      );
    },
  );

  test(
    'native close event prevents delayed sync from reopening the window',
    () async {
      const channel = MethodChannel('com.mconnect.mconnect/floating_lyrics');
      final permission = Completer<bool>();
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return switch (call.method) {
              'canDrawOverlays' => permission.future,
              'hide' => true,
              'update' => true,
              _ => null,
            };
          });

      const document = LyricsDocument(
        lines: [LyricsLine(timestamp: Duration.zero, text: 'Visible lyric')],
      );
      final player = _FloatingLyricsTestPlayerNotifier();
      final container = ProviderContainer(
        overrides: [
          playerProvider.overrideWith((ref) => player),
          lyricsProvider.overrideWith((ref) async => document),
        ],
      );
      addTearDown(container.dispose);
      await container.read(lyricsProvider.future);
      container.read(floatingLyricsSyncProvider);

      await container.read(floatingLyricsProvider.notifier).setEnabled(true);
      await pumpEventQueue();
      await _sendNativeFloatingLyricsCall('closedByUser');
      await pumpEventQueue();
      permission.complete(true);
      await pumpEventQueue();

      expect(container.read(floatingLyricsProvider).enabled, isFalse);
      expect(calls.map((call) => call.method), isNot(contains('update')));
    },
  );

  test('native style changes persist the lyric color and font size', () async {
    const channel = MethodChannel('com.mconnect.mconnect/floating_lyrics');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    final container = ProviderContainer();
    container.read(floatingLyricsSyncProvider);

    await _sendNativeFloatingLyricsCall('styleChanged', {
      'highlightColor': 0xFF4AA8FF,
      'fontSize': 30.0,
    });
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      container.read(floatingLyricsProvider).highlightColor,
      const Color(0xFF4AA8FF),
    );
    expect(container.read(floatingLyricsProvider).fontSize, 30.0);
    container.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final restored = FloatingLyricsNotifier();
    addTearDown(restored.dispose);
    await restored.ready;
    expect(restored.state.highlightColor, const Color(0xFF4AA8FF));
    expect(restored.state.fontSize, 30.0);
  });

  test(
    'native style changes clamp the font size like the settings page',
    () async {
      const channel = MethodChannel('com.mconnect.mconnect/floating_lyrics');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => null);
      final container = ProviderContainer();
      container.read(floatingLyricsSyncProvider);

      await _sendNativeFloatingLyricsCall('styleChanged', {
        'highlightColor': 0xFF4AA8FF,
        'fontSize': 99.0,
      });
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(container.read(floatingLyricsProvider).fontSize, 48.0);
      container.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    },
  );

  test('native transport taps drive the player notifier', () async {
    final player = _FloatingLyricsTestPlayerNotifier();
    final container = ProviderContainer(
      overrides: [playerProvider.overrideWith((ref) => player)],
    );
    addTearDown(container.dispose);
    container.read(floatingLyricsSyncProvider);

    await _sendNativeFloatingLyricsCall('controlRequested', {
      'action': 'playPause',
    });
    await _sendNativeFloatingLyricsCall('controlRequested', {
      'action': 'previous',
    });
    await _sendNativeFloatingLyricsCall('controlRequested', {
      'action': 'next',
    });
    await pumpEventQueue();

    expect(player.controlCalls, ['playPause', 'previous', 'next']);
  });

  test('sync forwards play state changes to the overlay', () async {
    const channel = MethodChannel('com.mconnect.mconnect/floating_lyrics');
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

    const document = LyricsDocument(
      lines: [LyricsLine(timestamp: Duration.zero, text: 'Playing lyric')],
    );
    final player = _FloatingLyricsTestPlayerNotifier();
    final container = ProviderContainer(
      overrides: [
        playerProvider.overrideWith((ref) => player),
        lyricsProvider.overrideWith((ref) async => document),
      ],
    );
    addTearDown(container.dispose);
    await container.read(lyricsProvider.future);
    container.read(floatingLyricsSyncProvider);

    await container.read(floatingLyricsProvider.notifier).setEnabled(true);
    await pumpEventQueue();
    player.setPlaying(true);
    await pumpEventQueue();

    final updates = calls.where((call) => call.method == 'update').toList();
    expect(updates, hasLength(2));
    expect(
      (updates.last.arguments as Map<Object?, Object?>)['isPlaying'],
      isTrue,
    );
  });

  test(
    'native drag end persists the vertical offset without a native update',
    () async {
      const channel = MethodChannel('com.mconnect.mconnect/floating_lyrics');
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

      const document = LyricsDocument(
        lines: [LyricsLine(timestamp: Duration.zero, text: 'Dragged lyric')],
      );
      final player = _FloatingLyricsTestPlayerNotifier();
      final container = ProviderContainer(
        overrides: [
          playerProvider.overrideWith((ref) => player),
          lyricsProvider.overrideWith((ref) async => document),
        ],
      );
      addTearDown(container.dispose);
      await container.read(lyricsProvider.future);
      container.read(floatingLyricsSyncProvider);

      await container.read(floatingLyricsProvider.notifier).setEnabled(true);
      await pumpEventQueue();
      calls.clear();

      await _sendNativeFloatingLyricsCall('positionChanged', 512.0);
      await pumpEventQueue();

      expect(container.read(floatingLyricsProvider).positionY, 512.0);
      expect(calls.where((call) => call.method == 'update'), isEmpty);
    },
  );

  test(
    'toggleEnabled asks for overlay permission and persists the switch',
    () async {
      const channel = MethodChannel('com.mconnect.mconnect/floating_lyrics');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return switch (call.method) {
              'canDrawOverlays' => true,
              'openOverlaySettings' => true,
              'hide' => true,
              _ => null,
            };
          });

      final notifier = FloatingLyricsNotifier();
      addTearDown(notifier.dispose);
      await notifier.ready;

      await notifier.toggleEnabled();
      expect(notifier.state.enabled, isTrue);
      expect(calls.map((call) => call.method), ['canDrawOverlays']);

      await notifier.toggleEnabled();
      expect(notifier.state.enabled, isFalse);
      expect(calls.map((call) => call.method), ['canDrawOverlays', 'hide']);
    },
  );

  test(
    'toggleEnabled opens the overlay settings when permission is missing',
    () async {
      const channel = MethodChannel('com.mconnect.mconnect/floating_lyrics');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return switch (call.method) {
              'canDrawOverlays' => false,
              'openOverlaySettings' => true,
              _ => null,
            };
          });

      final notifier = FloatingLyricsNotifier();
      addTearDown(notifier.dispose);
      await notifier.ready;

      await notifier.toggleEnabled();

      expect(notifier.state.enabled, isTrue);
      expect(calls.map((call) => call.method), [
        'canDrawOverlays',
        'openOverlaySettings',
      ]);
    },
  );

  test('payloadForPosition returns the next visible lyric line', () {
    const document = LyricsDocument(
      lines: [
        LyricsLine(timestamp: Duration(seconds: 3), text: 'First'),
        LyricsLine(timestamp: Duration(seconds: 8), text: '   '),
        LyricsLine(timestamp: Duration(seconds: 12), text: 'Third'),
      ],
    );

    final payload = FloatingLyricsSyncController.payloadForPosition(
      document,
      const Duration(seconds: 9),
    );

    expect(payload.text, 'First');
    expect(payload.nextText, 'Third');
  });

  test('payloadForPosition leaves the next line empty on the last lyric', () {
    const document = LyricsDocument(
      lines: [
        LyricsLine(timestamp: Duration(seconds: 3), text: 'First'),
        LyricsLine(timestamp: Duration(seconds: 12), text: 'Third'),
      ],
    );

    final payload = FloatingLyricsSyncController.payloadForPosition(
      document,
      const Duration(seconds: 13),
    );

    expect(payload.text, 'Third');
    expect(payload.nextText, '');
  });

  test('highlightCharactersFor follows word timings', () {
    const line = LyricsLine(
      timestamp: Duration(seconds: 10),
      text: 'ABCD EF',
      words: [
        WordTiming(
          word: 'ABCD',
          start: Duration(seconds: 10),
          duration: Duration(seconds: 1),
        ),
        WordTiming(
          word: ' EF',
          start: Duration(seconds: 11),
          duration: Duration(seconds: 1),
        ),
      ],
    );

    expect(
      FloatingLyricsSyncController.highlightCharactersFor(
        line,
        const Duration(seconds: 10),
        null,
      ),
      0,
    );
    expect(
      FloatingLyricsSyncController.highlightCharactersFor(
        line,
        const Duration(milliseconds: 10500),
        null,
      ),
      2,
    );
    expect(
      FloatingLyricsSyncController.highlightCharactersFor(
        line,
        const Duration(milliseconds: 11500),
        null,
      ),
      6,
    );
    expect(
      FloatingLyricsSyncController.highlightCharactersFor(
        line,
        const Duration(seconds: 12),
        null,
      ),
      7,
    );
  });

  test('highlightCharactersFor sweeps plain lines between timestamps', () {
    const line = LyricsLine(
      timestamp: Duration(seconds: 5),
      text: '1234567890',
    );

    expect(
      FloatingLyricsSyncController.highlightCharactersFor(
        line,
        const Duration(seconds: 5),
        const Duration(seconds: 10),
      ),
      0,
    );
    expect(
      FloatingLyricsSyncController.highlightCharactersFor(
        line,
        const Duration(milliseconds: 7500),
        const Duration(seconds: 10),
      ),
      5,
    );
    expect(
      FloatingLyricsSyncController.highlightCharactersFor(
        line,
        const Duration(seconds: 10),
        const Duration(seconds: 10),
      ),
      10,
    );
    // Without a following line the sweep falls back to a four second line.
    expect(
      FloatingLyricsSyncController.highlightCharactersFor(
        line,
        const Duration(seconds: 8),
        null,
      ),
      7,
    );
  });

  test('highlightCharactersFor never exceeds the lyric length', () {
    const line = LyricsLine(
      timestamp: Duration(seconds: 5),
      text: 'short',
      words: [
        WordTiming(
          word: 'a much longer word stream than the text',
          start: Duration(seconds: 5),
          duration: Duration(seconds: 1),
        ),
      ],
    );

    final characters = FloatingLyricsSyncController.highlightCharactersFor(
      line,
      const Duration(seconds: 30),
      null,
    );

    expect(characters, line.text.length);
  });

  test('sync sends an update when the played progress advances', () async {
    const channel = MethodChannel('com.mconnect.mconnect/floating_lyrics');
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

    const document = LyricsDocument(
      lines: [
        LyricsLine(timestamp: Duration.zero, text: 'Played lyric'),
        LyricsLine(timestamp: Duration(seconds: 10), text: 'Next lyric'),
      ],
    );
    final player = _FloatingLyricsTestPlayerNotifier();
    final container = ProviderContainer(
      overrides: [
        playerProvider.overrideWith((ref) => player),
        lyricsProvider.overrideWith((ref) async => document),
      ],
    );
    addTearDown(container.dispose);
    await container.read(lyricsProvider.future);
    container.read(floatingLyricsSyncProvider);

    await container.read(floatingLyricsProvider.notifier).setEnabled(true);
    await pumpEventQueue();
    player.setPosition(const Duration(seconds: 5));
    await pumpEventQueue();

    final updates = calls.where((call) => call.method == 'update').toList();
    expect(updates, hasLength(2));
    final latest = updates.last.arguments as Map<Object?, Object?>;
    expect(latest['highlightProgress'], closeTo(0.5, 0.001));
    expect(latest['nextText'], 'Next lyric');
  });

  test('sync reports a positive sweep rate while the player is playing', () async {
    const channel = MethodChannel('com.mconnect.mconnect/floating_lyrics');
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

    const document = LyricsDocument(
      lines: [
        LyricsLine(timestamp: Duration.zero, text: 'Played lyric'),
        LyricsLine(timestamp: Duration(seconds: 10), text: 'Next lyric'),
      ],
    );
    final player = _FloatingLyricsTestPlayerNotifier()..setPlaying(true);
    final container = ProviderContainer(
      overrides: [
        playerProvider.overrideWith((ref) => player),
        lyricsProvider.overrideWith((ref) async => document),
      ],
    );
    addTearDown(container.dispose);
    await container.read(lyricsProvider.future);
    container.read(floatingLyricsSyncProvider);

    await container.read(floatingLyricsProvider.notifier).setEnabled(true);
    await pumpEventQueue();
    // The 200ms sweep driver advances the interpolated position.
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final updates = calls.where((call) => call.method == 'update').toList();
    expect(updates, isNotEmpty);
    expect(
      (updates.last.arguments as Map<Object?, Object?>)['highlightRate'],
      greaterThan(0),
    );
  });

  test(
    'the sweep timer interpolates progress while the player is playing',
    () async {
      const channel = MethodChannel('com.mconnect.mconnect/floating_lyrics');
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

      const document = LyricsDocument(
        lines: [
          LyricsLine(timestamp: Duration.zero, text: 'ABCDEFGHIJ'),
          LyricsLine(timestamp: Duration(seconds: 1), text: 'Next'),
        ],
      );
      final player = _FloatingLyricsTestPlayerNotifier()..setPlaying(true);
      final container = ProviderContainer(
        overrides: [
          playerProvider.overrideWith((ref) => player),
          lyricsProvider.overrideWith((ref) async => document),
        ],
      );
      addTearDown(container.dispose);
      await container.read(lyricsProvider.future);
      container.read(floatingLyricsSyncProvider);

      await container.read(floatingLyricsProvider.notifier).setEnabled(true);
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 350));

      final updates = calls.where((call) => call.method == 'update').toList();
      expect(updates.length, greaterThan(1));
      expect(
        (updates.last.arguments
            as Map<Object?, Object?>)['highlightProgress'],
        greaterThan(0),
      );
    },
  );

  test(
    'the overlay applies the manual lyrics offset to the position it sends',
    () async {
      const channel = MethodChannel('com.mconnect.mconnect/floating_lyrics');
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

      const document = LyricsDocument(
        lines: [
          LyricsLine(timestamp: Duration.zero, text: 'First lyric'),
          LyricsLine(timestamp: Duration(seconds: 5), text: 'Second lyric'),
        ],
      );
      final player = _FloatingLyricsTestPlayerNotifier()
        ..setPosition(const Duration(seconds: 1));
      final container = ProviderContainer(
        overrides: [
          playerProvider.overrideWith((ref) => player),
          lyricsProvider.overrideWith((ref) async => document),
        ],
      );
      addTearDown(container.dispose);
      await container.read(lyricsProvider.future);
      container.read(floatingLyricsSyncProvider);

      await container.read(floatingLyricsProvider.notifier).setEnabled(true);
      await pumpEventQueue();
      expect(
        (calls.lastWhere((call) => call.method == 'update').arguments
            as Map<Object?, Object?>)['text'],
        'First lyric',
      );

      // +5s: the in-app player matches lines against `position + offset`, so the
      // overlay must send the same shifted position to the native window.
      await container
          .read(lyricsOffsetProvider.notifier)
          .setOffset(const Duration(seconds: 5));
      await pumpEventQueue();

      final updates = calls.where((call) => call.method == 'update').toList();
      expect(
        updates.length,
        greaterThan(1),
        reason: '改变偏移必须重新下发一次原生载荷（播放暂停时 position 不会自己动）',
      );
      expect(
        (updates.last.arguments as Map<Object?, Object?>)['text'],
        'Second lyric',
      );
    },
  );

  test('the native payload carries the fields the Windows overlay paints', () {
    const document = LyricsDocument(
      lines: [
        LyricsLine(timestamp: Duration.zero, text: 'Main line'),
        LyricsLine(timestamp: Duration(seconds: 5), text: 'Next line'),
      ],
    );
    const settings = FloatingLyricsSettings(
      highlightColor: Color(0xFF112233),
      textColor: Color(0xFFEEDDCC),
    );

    final payload = FloatingLyricsSyncController.payloadForPosition(
      document,
      const Duration(seconds: 1),
    );
    final json = payload.toJson(settings);

    // 这三个字段 Windows 原生窗口过去只收不使用；Dart 侧必须先保证发出来。
    expect(json['highlightColor'], const Color(0xFF112233).toARGB32());
    expect(json['textColor'], const Color(0xFFEEDDCC).toARGB32());
    expect(json['nextText'], 'Next line');
    expect(json['highlightProgress'], isA<double>());
    expect(json['highlightProgress'], closeTo(0.2, 0.0001));
  });

  test('disabling floating lyrics releases the lock', () async {
    final notifier = FloatingLyricsNotifier();
    addTearDown(notifier.dispose);
    await notifier.ready;

    await notifier.setEnabled(true);
    await notifier.setLocked(true);
    expect(notifier.state.isLocked, isTrue);

    await notifier.setEnabled(false);

    expect(notifier.state.isLocked, isFalse);
  });
}

Future<void> _sendNativeFloatingLyricsCall(String method, [Object? arguments]) {
  const codec = StandardMethodCodec();
  return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        'com.mconnect.mconnect/floating_lyrics',
        codec.encodeMethodCall(MethodCall(method, arguments)),
        (_) {},
      );
}

const _floatingLyricsSong = Song(
  id: 'floating-lyrics-song',
  platform: PlatformType.netease,
  name: 'Floating Lyrics Song',
  artists: [Artist(id: 'artist', name: 'Artist')],
);

class _FloatingLyricsTestPlayerNotifier extends PlayerNotifier {
  _FloatingLyricsTestPlayerNotifier()
    : super(
        audioController: _FloatingLyricsIdleAudioController(),
        audioControllerFactory: () => _FloatingLyricsIdleAudioController(),
      ) {
    state = state.copyWith(
      currentSong: _floatingLyricsSong,
      playlist: const [_floatingLyricsSong],
      currentIndex: 0,
      position: Duration.zero,
      duration: const Duration(minutes: 3),
    );
  }

  final List<String> controlCalls = [];

  void setPosition(Duration position) {
    state = state.copyWith(position: position);
  }

  void setPlaying(bool isPlaying) {
    state = state.copyWith(isPlaying: isPlaying);
  }

  @override
  Future<void> togglePlay() async {
    controlCalls.add('playPause');
  }

  @override
  Future<void> skipToPrevious() async {
    controlCalls.add('previous');
  }

  @override
  Future<void> skipToNext() async {
    controlCalls.add('next');
  }
}

class _FloatingLyricsIdleAudioController implements PlayerAudioController {
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _playerStateController =
      StreamController<AudioPlaybackState>.broadcast();

  @override
  bool get playing => false;

  @override
  Duration get position => Duration.zero;

  @override
  double get volume => 1.0;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<AudioPlaybackState> get playerStateStream =>
      _playerStateController.stream;

  @override
  Future<void> stop() async {}

  @override
  Future<void> setUrl(String url) async {}

  @override
  Future<void> play() async {
    _playerStateController.add(
      const AudioPlaybackState(
        playing: true,
        processingState: just_audio.ProcessingState.ready,
      ),
    );
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> applyEqualizer({
    required bool enabled,
    required List<double> bandGains,
  }) async {}

  @override
  Future<void> dispose() async {
    await _positionController.close();
    await _durationController.close();
    await _playerStateController.close();
  }
}
