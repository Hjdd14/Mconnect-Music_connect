import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/core/diagnostics/diagnostics_export.dart';
import 'package:mconnect/core/diagnostics/diagnostics_service.dart';
import 'package:mconnect/features/settings/presentation/pages/settings_page.dart';

/// task-12 wiring: the 「导出诊断日志」 row must actually call the exporter, and
/// must not be able to run twice concurrently.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mconnect_export_test_');
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

  DiagnosticsExportResult fakeResult(File file) => DiagnosticsExportResult(
    file: file,
    byteSize: 12,
    eventCount: 1,
    logBytesIncluded: 0,
    logTruncated: false,
    redactions: const {},
  );

  Future<void> pumpPage(
    WidgetTester tester,
    Future<DiagnosticsExportResult> Function() export,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: SettingsPage(
            diagnosticsExport: export,
            // share_plus' platform channel never answers in a widget test;
            // injecting a no-op share is what lets the flow reach its end state.
            diagnosticsShare: (_) async {},
          ),
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('diagnostics-export-tile')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
  }

  testWidgets('one tap exports exactly once', (tester) async {
    var calls = 0;
    final file = File('${tempDir.path}/bundle.txt')..writeAsStringSync('x');

    await pumpPage(tester, () async {
      calls += 1;
      return fakeResult(file);
    });

    await tester.tap(find.byKey(const Key('diagnostics-export-tile')));
    await tester.pumpAndSettle();

    expect(calls, 1);
    // Sharing has no platform implementation in a widget test, so the row falls
    // back to copying the path — either way the user is told something happened.
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('a second tap while the first is running is ignored', (
    tester,
  ) async {
    var calls = 0;
    final gate = Completer<void>();
    final file = File('${tempDir.path}/bundle.txt')..writeAsStringSync('x');

    await pumpPage(tester, () async {
      calls += 1;
      await gate.future;
      return fakeResult(file);
    });

    await tester.tap(find.byKey(const Key('diagnostics-export-tile')));
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('diagnostics-export-tile')),
      warnIfMissed: false,
    );
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();

    expect(calls, 1);
  });

  testWidgets('an export failure is reported with the message from the error', (
    tester,
  ) async {
    await pumpPage(
      tester,
      () async => throw const DiagnosticsExportException('诊断服务尚未初始化，暂时无法导出日志'),
    );

    await tester.tap(find.byKey(const Key('diagnostics-export-tile')));
    await tester.pumpAndSettle();

    expect(find.textContaining('诊断服务尚未初始化'), findsOneWidget);
  });
}
