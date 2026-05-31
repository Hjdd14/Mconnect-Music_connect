import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/features/floating_lyrics/presentation/providers/floating_lyrics_provider.dart';
import 'package:mconnect/lyrics/models/lyrics_line.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'mconnect_floating_lyrics_test_',
    );
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('floating lyrics settings persist enabled and style values', () async {
    final notifier = FloatingLyricsNotifier();
    await notifier.ready;

    await notifier.setEnabled(true);
    await notifier.setTextColor(const Color(0xFF00FFAA));
    await notifier.setHighlightColor(const Color(0xFFFFCC00));
    await notifier.setFontSize(30);

    final restored = FloatingLyricsNotifier();
    await restored.ready;

    expect(restored.state.enabled, isTrue);
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
