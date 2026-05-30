import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/core/theme/theme_provider.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mconnect_theme_test_');
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('theme settings default to system mode and pink seed color', () async {
    final notifier = ThemeSettingsNotifier();
    await notifier.ready;

    expect(notifier.state.mode, ThemeMode.system);
    expect(notifier.state.seedColor, const Color(0xFFE91E63));
  });

  test('theme settings persist mode and seed color', () async {
    final notifier = ThemeSettingsNotifier();
    await notifier.ready;

    await notifier.setMode(ThemeMode.dark);
    await notifier.setSeedColor(const Color(0xFF31C27C));

    final restored = ThemeSettingsNotifier();
    await restored.ready;

    expect(restored.state.mode, ThemeMode.dark);
    expect(restored.state.seedColor, const Color(0xFF31C27C));
  });
}
