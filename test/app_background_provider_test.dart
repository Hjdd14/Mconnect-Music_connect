import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/core/theme/app_background_provider.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mconnect_background_');
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('background settings default to disabled', () async {
    final notifier = AppBackgroundSettingsNotifier();
    await notifier.ready;

    expect(notifier.state.enabled, isFalse);
    expect(notifier.state.imagePath, isNull);
    expect(notifier.state.scale, 1);
    expect(notifier.state.offsetX, 0);
    expect(notifier.state.offsetY, 0);
  });

  test(
    'background settings restore synchronously from an open Hive box',
    () async {
      final box = Hive.box('settings');
      await box.put('app_background_settings', {
        'imagePath': 'D:\\Pictures\\restored.jpg',
        'imageWidth': 1440,
        'imageHeight': 900,
        'scale': 1.35,
        'offsetX': -18,
        'offsetY': 24,
        'cropViewportWidth': 1280,
        'cropViewportHeight': 720,
      });

      final notifier = AppBackgroundSettingsNotifier();

      expect(notifier.state.enabled, isTrue);
      expect(notifier.state.imagePath, 'D:\\Pictures\\restored.jpg');
      expect(notifier.state.cropViewportWidth, 1280);
      expect(notifier.state.cropViewportHeight, 720);
      await notifier.ready;
    },
  );

  test('background settings remain compatible with old stored json', () async {
    final restored = AppBackgroundSettings.fromJson({
      'imagePath': 'D:\\Pictures\\old.jpg',
      'imageWidth': 1080,
      'imageHeight': 1920,
      'scale': 1.5,
      'offsetX': 10,
      'offsetY': -20,
    });

    expect(restored.enabled, isTrue);
    expect(restored.cropViewportWidth, 0);
    expect(restored.cropViewportHeight, 0);
  });

  test('background settings persist image transform choices', () async {
    final notifier = AppBackgroundSettingsNotifier();
    await notifier.ready;

    await notifier.save(
      const AppBackgroundSettings(
        imagePath: 'D:\\Pictures\\wallpaper.jpg',
        imageWidth: 1200,
        imageHeight: 1800,
        scale: 1.8,
        offsetX: -24,
        offsetY: 36,
        cropViewportWidth: 390,
        cropViewportHeight: 844,
      ),
    );

    final restored = AppBackgroundSettingsNotifier();
    await restored.ready;

    expect(restored.state.enabled, isTrue);
    expect(restored.state.imagePath, 'D:\\Pictures\\wallpaper.jpg');
    expect(restored.state.imageWidth, 1200);
    expect(restored.state.imageHeight, 1800);
    expect(restored.state.scale, 1.8);
    expect(restored.state.offsetX, -24);
    expect(restored.state.offsetY, 36);
    expect(restored.state.cropViewportWidth, 390);
    expect(restored.state.cropViewportHeight, 844);

    await restored.clear();
    expect(restored.state.enabled, isFalse);
  });
}
