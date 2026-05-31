import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/core/diagnostics/diagnostics_service.dart';
import 'package:mconnect/core/platform/platform_utils.dart';
import 'package:mconnect/features/settings/presentation/pages/settings_page.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mconnect_settings_test_');
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
    await DiagnosticsService.instance.initializeForTest(tempDir);
    PlatformUtils.setDebugOverride(AppPlatform.android);
  });

  tearDown(() async {
    PlatformUtils.setDebugOverride(null);
    await DiagnosticsService.instance.flush();
    await DiagnosticsService.instance.resetForTest();
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('settings page exposes diagnostics log path', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsPage())),
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

  testWidgets(
    'settings page exposes theme color and floating lyrics controls',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: SettingsPage())),
      );

      expect(find.text('主题色'), findsOneWidget);

      for (final label in const ['桌面悬浮歌词', '歌词颜色', '高亮颜色', '字号']) {
        await tester.scrollUntilVisible(
          find.text(label),
          220,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(label), findsOneWidget);
      }
    },
  );

  test('floating lyrics color presets include dark options', () {
    expect(SettingsPage.lyricTextPresets, contains(const Color(0xFF111827)));
    expect(SettingsPage.lyricTextPresets, contains(const Color(0xFF0F172A)));
    expect(
      SettingsPage.lyricHighlightPresets,
      contains(const Color(0xFF1E3A8A)),
    );
    expect(
      SettingsPage.lyricHighlightPresets,
      contains(const Color(0xFF7F1D1D)),
    );
  });

  testWidgets('settings page exposes low-risk audio enhancement controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsPage())),
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

  testWidgets('settings disables Android-only controls on Windows', (
    tester,
  ) async {
    PlatformUtils.setDebugOverride(AppPlatform.windows);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsPage())),
    );
    await tester.pumpAndSettle();

    await _dragUntilIconVisible(tester, Icons.picture_in_picture_alt_outlined);
    final floatingLyricsTile = tester.widget<SwitchListTile>(
      find.ancestor(
        of: find.byIcon(Icons.picture_in_picture_alt_outlined),
        matching: find.byType(SwitchListTile),
      ),
    );

    await _dragUntilIconVisible(tester, Icons.equalizer);
    final equalizerTile = tester.widget<SwitchListTile>(
      find.ancestor(
        of: find.byIcon(Icons.equalizer),
        matching: find.byType(SwitchListTile),
      ),
    );

    expect(floatingLyricsTile.onChanged, isNull);
    expect(equalizerTile.onChanged, isNull);
  });
}

Future<void> _dragUntilTextVisible(WidgetTester tester, String label) async {
  for (var i = 0; i < 10; i++) {
    if (find.text(label).evaluate().isNotEmpty) return;
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -260));
    await tester.pumpAndSettle();
  }
}

Future<void> _dragUntilIconVisible(WidgetTester tester, IconData icon) async {
  for (var i = 0; i < 10; i++) {
    if (find.byIcon(icon).evaluate().isNotEmpty) return;
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -260));
    await tester.pumpAndSettle();
  }
}
