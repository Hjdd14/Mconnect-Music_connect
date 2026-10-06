import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/features/offline_cache/data/cache_settings_repository.dart';
import 'package:mconnect/features/offline_cache/presentation/pages/offline_cache_page.dart';
import 'package:mconnect/features/offline_cache/presentation/providers/offline_cache_provider.dart';

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

  testWidgets('cache page exposes the queue controls', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: OfflineCachePage())),
    );
    await tester.pumpAndSettle();

    // Visible without scrolling (it is the top card).
    expect(find.text('缓存概览'), findsOneWidget);

    // Bottom controls, in page order, so one downward scroll finds each.
    for (final label in const [
      '开始缓存队列',
      '暂停缓存队列',
      '立即清理缓存',
    ]) {
      await _dragUntilTextVisible(tester, label);
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('manual cleanup stays enabled even when 自动清理 is off', (
    tester,
  ) async {
    // The button used to be `onTap: settings.autoCleanup ? ... : null`, so
    // turning the automatic switch off also greyed out the manual action.
    final settingsNotifier = OfflineCacheSettingsNotifier(
      repository: _FakeCacheSettingsRepository(
        const OfflineCacheSettings(autoCleanup: false),
      ),
    );
    await settingsNotifier.ready;
    // No addTearDown(dispose): the ProviderScope owns the overridden notifier
    // and disposes it, and a second dispose throws.
    expect(settingsNotifier.state.autoCleanup, isFalse);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          offlineCacheSettingsProvider.overrideWith((ref) => settingsNotifier),
        ],
        child: const MaterialApp(home: OfflineCachePage()),
      ),
    );
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, '立即清理缓存');
    final tile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('立即清理缓存'),
        matching: find.byType(ListTile),
      ),
    );

    expect(tile.onTap, isNotNull);
  });
}

/// No Hive and no real file I/O: inside `testWidgets` the body runs in a
/// fake-async zone, where a real I/O future never completes.
class _FakeCacheSettingsRepository extends CacheSettingsRepository {
  _FakeCacheSettingsRepository(this._settings);

  OfflineCacheSettings _settings;

  @override
  Future<OfflineCacheSettings> load() async => _settings;

  @override
  Future<void> save(OfflineCacheSettings settings) async {
    _settings = settings;
  }
}

Future<void> _dragUntilTextVisible(WidgetTester tester, String label) async {
  for (var i = 0; i < 10; i++) {
    if (find.text(label).evaluate().isNotEmpty) return;
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -260));
    await tester.pumpAndSettle();
  }
}
