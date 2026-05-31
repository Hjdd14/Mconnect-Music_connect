import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:mconnect/features/player/presentation/providers/lyrics_provider.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
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
