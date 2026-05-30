import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/features/offline_cache/presentation/pages/offline_cache_page.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'mconnect_cache_page_test_',
    );
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('offline cache page exposes cache controls', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: OfflineCachePage())),
    );
    await tester.pumpAndSettle();

    for (final label in const [
      '离线缓存中心',
      '离线模式',
      '仅 Wi-Fi 下载',
      '失败自动重试',
      '自动清理',
      '缓存大小上限',
    ]) {
      await _dragUntilTextVisible(tester, label);
      expect(find.text(label), findsOneWidget);
    }
  });
}

Future<void> _dragUntilTextVisible(WidgetTester tester, String label) async {
  for (var i = 0; i < 10; i++) {
    if (find.text(label).evaluate().isNotEmpty) return;
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -260));
    await tester.pumpAndSettle();
  }
}
