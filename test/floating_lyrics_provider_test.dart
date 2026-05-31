import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/features/floating_lyrics/presentation/providers/floating_lyrics_provider.dart';
import 'package:mconnect/lyrics/models/lyrics_line.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.mconnect.mconnect/floating_lyrics');
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'mconnect_floating_lyrics_test_',
    );
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => true);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await Hive.close();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (await tempDir.exists()) {
      await _deleteTempDirWithRetry(tempDir);
    }
  });

  test('floating lyrics settings persist enabled and style values', () async {
    final notifier = FloatingLyricsNotifier();
    addTearDown(notifier.dispose);
    await notifier.ready;

    await notifier.setEnabled(true);
    await notifier.setTextColor(const Color(0xFF00FFAA));
    await notifier.setHighlightColor(const Color(0xFFFFCC00));
    await notifier.setFontSize(30);
    await notifier.setLocked(true);

    final restored = FloatingLyricsNotifier();
    addTearDown(restored.dispose);
    await restored.ready;

    expect(restored.state.enabled, isTrue);
    expect(restored.state.textColor, const Color(0xFF00FFAA));
    expect(restored.state.highlightColor, const Color(0xFFFFCC00));
    expect(restored.state.fontSize, 30);
    expect(restored.state.backgroundColor, Colors.transparent);
    expect(restored.state.isLocked, isTrue);
  });

  test('native close event disables and persists the Flutter switch', () async {
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
  });

  test('native lock event updates and persists lock state', () async {
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
  });

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

  test('payloadForPosition returns empty text when no line is active', () {
    const document = LyricsDocument(
      lines: [LyricsLine(timestamp: Duration(seconds: 3), text: 'First')],
    );

    final payload = FloatingLyricsSyncController.payloadForPosition(
      document,
      const Duration(seconds: 1),
    );

    expect(payload.text, isEmpty);
    expect(payload.translation, isNull);
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

Future<void> _deleteTempDirWithRetry(Directory dir) async {
  for (var attempt = 0; attempt < 5; attempt++) {
    try {
      await dir.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 4) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }
}
