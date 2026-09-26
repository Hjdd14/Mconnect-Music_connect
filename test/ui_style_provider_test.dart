import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/core/theme/ui_style_provider.dart';

void main() {
  late Directory tempDir;
  late Box<dynamic> settingsBox;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mconnect_ui_style_test_');
    Hive.init(tempDir.path);
    settingsBox = await Hive.openBox('settings');
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('ui style defaults to material when settings are empty', () async {
    final notifier = UiStyleNotifier();
    await notifier.ready;

    expect(notifier.state.style, UiStyle.material);
  });

  test('ui style provider exposes material by default', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(uiStyleProvider).style, UiStyle.material);
  });

  test('ui style persists miuix to the settings box', () async {
    final notifier = UiStyleNotifier();
    await notifier.ready;

    await notifier.setStyle(UiStyle.miuix);

    expect(notifier.state.style, UiStyle.miuix);
    expect(settingsBox.get('ui_style'), 'miuix');

    final restored = UiStyleNotifier();
    await restored.ready;

    expect(restored.state.style, UiStyle.miuix);
  });

  test('corrupted ui style values fall back to material', () async {
    await settingsBox.put('ui_style', 'bogus');

    final notifier = UiStyleNotifier();
    await notifier.ready;

    expect(notifier.state.style, UiStyle.material);
  });

  test('malformed ui style payloads fall back to material', () {
    expect(UiStyleSettings.fromJson(null).style, UiStyle.material);
    expect(UiStyleSettings.fromJson(42).style, UiStyle.material);
    expect(UiStyleSettings.fromJson('miuix').style, UiStyle.miuix);
    expect(UiStyleSettings.fromJson('').style, UiStyle.material);
  });

  test('ui style settings round-trip through json', () {
    const settings = UiStyleSettings(style: UiStyle.miuix);

    expect(UiStyleSettings.fromJson(settings.toJson()['style']), settings);
    expect(settings.copyWith().style, UiStyle.miuix);
    expect(
      settings.copyWith(style: UiStyle.material).style,
      UiStyle.material,
    );
  });
}
