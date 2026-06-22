import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/core/diagnostics/diagnostics_service.dart';
import 'package:mconnect/features/settings/presentation/pages/settings_page.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mconnect_settings_test_');
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
    await DiagnosticsService.instance.initializeForTest(tempDir);
  });

  tearDown(() async {
    await DiagnosticsService.instance.flush();
    await DiagnosticsService.instance.resetForTest();
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('settings page exposes diagnostics log path', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsDiagnosticsPage())),
    );

    await tester.scrollUntilVisible(
      find.text('诊断日志'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('诊断日志'), findsOneWidget);
    expect(find.textContaining('mconnect.log'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsWidgets);
  });

  testWidgets('settings page shows the current app version', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsDiagnosticsPage())),
    );

    await tester.scrollUntilVisible(
      find.text('版本'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('v1.2.4'), findsOneWidget);
  });

  testWidgets(
    'settings home exposes section entry points',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: SettingsPage())),
      );

      for (final label in const [
        '账号管理',
        '外观',
        '悬浮歌词',
        '音频增强',
        '诊断与关于',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
    },
  );

  testWidgets(
    'appearance settings page exposes theme color and background controls',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: SettingsAppearancePage())),
      );

      expect(find.text('主题色'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('app-background-tile')),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('app-background-tile')), findsOneWidget);
    },
  );

  testWidgets(
    'floating lyrics settings page exposes lyrics controls',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: SettingsFloatingLyricsPage()),
        ),
      );

      for (final label in const ['桌面悬浮歌词', '歌词颜色', '高亮颜色', '字号']) {
        await _dragUntilTextVisible(tester, label);
        expect(find.text(label), findsOneWidget);
      }
    },
  );

  testWidgets('floating lyrics color rows open a full color picker', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: SettingsFloatingLyricsPage()),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('floating-lyrics-text-color-tile')),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    final colorTile = tester.widget<ListTile>(
      find.descendant(
        of: find.byKey(const Key('floating-lyrics-text-color-tile')),
        matching: find.byType(ListTile),
      ),
    );
    colorTile.onTap!();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('floating-color-picker-dialog')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('floating-color-picker-hue')), findsOneWidget);
    expect(
      find.byKey(const Key('floating-color-picker-saturation')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('floating-color-picker-value')),
      findsOneWidget,
    );
  });

  testWidgets('floating lyrics rows expose a clear custom color entry', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: SettingsFloatingLyricsPage()),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('floating-lyrics-text-color-tile')),
      220,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('自定义颜色'), findsWidgets);
    final colorTile = tester.widget<ListTile>(
      find.descendant(
        of: find.byKey(const Key('floating-lyrics-text-color-tile')),
        matching: find.byType(ListTile),
      ),
    );
    colorTile.onTap!();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('floating-color-picker-dialog')),
      findsOneWidget,
    );
  });

  testWidgets('settings page exposes low-risk audio enhancement controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsAudioPage())),
    );

    for (final label in const [
      '淡入淡出',
      '淡入淡出时长',
      '均衡器',
      '均衡器预设',
      '低频',
      '中频',
      '高频',
      '睡眠定时',
      '定时时长',
    ]) {
      await _dragUntilTextVisible(tester, label);
      expect(find.text(label), findsOneWidget);
    }
  });

  test('background editor uses a landscape crop shape on wide windows', () {
    final crop = backgroundCropViewportSize(const Size(1200, 800));

    expect(crop.width / crop.height, greaterThan(1));
  });

  test('background editor uses a portrait crop shape on tall windows', () {
    final crop = backgroundCropViewportSize(const Size(390, 844));

    expect(crop.width / crop.height, lessThan(1));
  });

  test('background destination paths are unique', () {
    final first = createBackgroundDestinationPath(
      backgroundsDirPath: 'D:\\App\\backgrounds',
      originalName: 'wallpaper.jpg',
      now: DateTime.fromMicrosecondsSinceEpoch(100),
    );
    final second = createBackgroundDestinationPath(
      backgroundsDirPath: 'D:\\App\\backgrounds',
      originalName: 'wallpaper.jpg',
      now: DateTime.fromMicrosecondsSinceEpoch(101),
    );

    expect(first, isNot(second));
    expect(first, contains('custom_background_100.jpg'));
    expect(second, contains('custom_background_101.jpg'));
  });

  test('small background images are accepted for black padded placement', () {
    expect(
      canUseDecodedBackgroundImage(imageWidth: 32, imageHeight: 24),
      isTrue,
    );
  });
}

Future<void> _dragUntilTextVisible(WidgetTester tester, String label) async {
  for (var i = 0; i < 10; i++) {
    if (find.text(label).evaluate().isNotEmpty) return;
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -260));
    await tester.pumpAndSettle();
  }
}
