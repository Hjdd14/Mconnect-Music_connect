import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/core/diagnostics/diagnostics_service.dart';
import 'package:mconnect/features/settings/presentation/pages/settings_page.dart';

/// Wave 3 accessibility pass over the settings page (the one page this workflow
/// owns end to end).
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mconnect_a11y_test_');
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

  Widget wrap(Widget child, {double textScale = 1.0}) {
    return ProviderScope(
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: child,
        ),
      ),
    );
  }

  testWidgets('the two new entries are reachable and labelled', (tester) async {
    await tester.pumpWidget(wrap(const SettingsPage()));

    // task-12: both Wave 2 features had no entry point.
    expect(find.text('备份与恢复'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('diagnostics-export-tile')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('导出诊断日志'), findsOneWidget);

    // The entry tiles are `ListTile`s, which is what gives them button
    // semantics; assert the label reaches the semantics tree rather than only
    // the paint layer.
    expect(find.bySemanticsLabel(RegExp('备份与恢复')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('导出诊断日志')), findsWidgets);
  });

  testWidgets('the page renders at 200 % text scale without overflowing', (
    tester,
  ) async {
    // The settings page used to hard-size the boxes that hold labels
    // (`SizedBox(width: 88)` / `width: 52`), which clipped them as soon as the
    // system font was scaled up.
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const SettingsPage(), textScale: 2.0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(wrap(const SettingsAudioPage(), textScale: 2.0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      wrap(const SettingsFloatingLyricsPage(), textScale: 2.0),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('no hard-width box squeezes a text label', (tester) async {
    // The font-scaling fix as one assertion. `SizedBox(width: N, child: Text)`
    // is what made labels wrap or clip as soon as the system font grew (the page
    // carried `width: 88` on a slider label and `width: 52` on a slider value);
    // `ConstrainedBox(minWidth:)` keeps the scale-1.0 look and lets text grow.
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final pages = <Widget>[
      const SettingsPage(),
      const SettingsFloatingLyricsPage(),
      const SettingsAudioPage(),
      const SettingsAppearancePage(),
    ];

    for (final page in pages) {
      await tester.pumpWidget(wrap(page, textScale: 2.0));
      await tester.pumpAndSettle();
      // A `ListView` only builds what is visible, so walk the page to reach the
      // rows below the fold before judging.
      for (var i = 0; i < 6; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      final offenders = tester
          .widgetList<SizedBox>(find.byType(SizedBox))
          .where((box) => box.width != null && box.child is Text)
          .toList();
      expect(
        offenders,
        isEmpty,
        reason:
            '${page.runtimeType} wraps a Text in a fixed-width SizedBox; that is '
            'what clipped labels at 200 % text scale',
      );
    }
  });

  testWidgets('colour swatches expose a selected button semantic', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(const SettingsFloatingLyricsPage(), textScale: 2.0),
    );
    await tester.pumpAndSettle();

    // A bare colour disc announced nothing; the swatch now carries the
    // "custom colour" label plus its selected state.
    expect(find.bySemanticsLabel(RegExp('自定义颜色')), findsWidgets);
  });

  testWidgets('the diagnostics overflow menu is labelled for screen readers', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const SettingsDiagnosticsPage()));

    // `PopupMenuButton`'s `tooltip` is what supplies the label ("Show menu" in
    // English otherwise) and is also the desktop hover hint.
    expect(find.byTooltip('更多操作'), findsWidgets);
  });
}
