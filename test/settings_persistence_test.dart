import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/core/source_matching/source_match_settings.dart';
import 'package:mconnect/features/audio_effects/presentation/providers/audio_effects_provider.dart';
import 'package:mconnect/features/settings/presentation/pages/settings_page.dart';

/// 持久化 seam 的用例（`AutoSourceSwitchStore` / `AudioEffectsSettingsStore`）。
///
/// # 为什么这个文件存在
/// A-6a 的根因由诊断探针确证（原文见 `test/scrobble_settings_probe_test.dart` 的注释）：
/// ```
/// PROBE A: 不点任何开关       → hiveClose=closed-ok
/// PROBE B: 点「自动换源」      → hiveClose=closed-TIMEOUT(3s)
/// PROBE C: 点 + runAsync 收口 → hiveClose=closed-TIMEOUT(3s)     ← runAsync 救不回来
/// PROBE D: 点「淡入淡出」      → hiveClose=closed-TIMEOUT(3s)     ← 与具体开关无关
/// ```
/// 即：**UI 回调里 fire-and-forget 的真实 Hive 写**的 continuation 留在 FakeAsync 队列里，
/// 文件级 `tearDown` 的 `Hive.close()` 一直等它。修法是让持久化成为可注入的 seam。
///
/// 本文件把这件事钉成两半，**缺一不可**：
/// 1. **持久化本身仍然真的落盘**（Hive store 的单测，plain `test()` 里没有 FakeAsync，
///    真实 I/O 正常完成）——否则"点击只改内存"就是新的假绿；
/// 2. **widget 测试用内存 store 覆盖后，点击不再卡 teardown**，并且**断言 store 收到了
///    写入请求**（证明点击确实要求落盘了，只是落到了内存）。
///
/// 第 2 组与 `test/settings_page_test.dart` 的 A-6a 用例**只差一个 provider override**
/// （同样的 Hive setUp、同样的页面、同样的两次 tap），所以它就是那条用例的红→绿形态。

/// 滚到某段文字可见，然后点它所在的 SwitchListTile。
Future<bool> _tapSwitch(WidgetTester tester, String label) async {
  for (var i = 0; i < 10; i++) {
    if (find.text(label).evaluate().isNotEmpty) break;
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -260));
    for (var f = 0; f < 30; f++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }
  final row = find.ancestor(
    of: find.text(label),
    matching: find.byType(SwitchListTile),
  );
  if (row.evaluate().isEmpty) return false;
  await tester.tap(row.first);
  for (var f = 0; f < 30; f++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  return true;
}

void main() {
  group('持久化单测：Hive store 仍然真的落盘（plain test 里真实 I/O 能完成）', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mconnect_persist_test_');
      Hive.init(tempDir.path);
      await Hive.openBox('settings');
    });

    tearDown(() async {
      // 有界：本组的写入都是 await 过的，正常会在毫秒级返回；加限只是不让
      // 任何意外把整个套件拖住。
      try {
        await Hive.close().timeout(const Duration(seconds: 3));
      } catch (_) {}
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('AutoSourceSwitch：写进去、新实例读回来', () async {
      const store = HiveAutoSourceSwitchStore();
      expect(store.read(), isNull, reason: '空 box = 没存过 ⇒ 调用方用默认值 true');

      await store.write(false);
      expect(store.read(), isFalse);

      // 新实例（模拟"下次启动"）也读得到 ⇒ 确实落到了 Hive，不是内存
      expect(const HiveAutoSourceSwitchStore().read(), isFalse);

      await store.write(true);
      expect(const HiveAutoSourceSwitchStore().read(), isTrue);
    });

    test('AudioEffectsSettings：JSON 往返（含非默认值）', () async {
      const store = HiveAudioEffectsSettingsStore();
      final settings = const AudioEffectsSettings().copyWith(
        fadeEnabled: true,
        fadeDuration: const Duration(milliseconds: 1200),
      );

      await store.write(settings.toJson());

      final restored = AudioEffectsSettings.fromJson(
        const HiveAudioEffectsSettingsStore().read(),
      );
      expect(restored.fadeEnabled, isTrue);
      expect(restored.fadeDuration, const Duration(milliseconds: 1200));
    });

    test('box 未打开时 read() 返回 null 而不是抛异常（W1-A 的降级约定）', () async {
      await Hive.close();
      expect(const HiveAutoSourceSwitchStore().read(), isNull);
      expect(const HiveAudioEffectsSettingsStore().read(), isNull);
    });

    test('内存 store：记录每一次写入请求（可断言"要求落盘"）', () async {
      final memory = MemoryAutoSourceSwitchStore();
      expect(memory.read(), isNull);

      await memory.write(false);
      await memory.write(true);

      expect(memory.value, isTrue);
      expect(memory.writes, <bool>[false, true]);

      final effects = MemoryAudioEffectsSettingsStore();
      expect(effects.read(), isNull);
      await effects.write(const AudioEffectsSettings().toJson());
      expect(effects.writes, hasLength(1));
    });
  });

  group('A-6a 的红→绿：内存 store 覆盖后点击不再卡 teardown', () {
    late Directory tempDir;

    setUp(() async {
      // 与 test/settings_page_test.dart 的 setUp 保持一致：**唯一的差别**只有
      // 下面那两个 provider override。
      tempDir = await Directory.systemTemp.createTemp('mconnect_persist_widget_');
      Hive.init(tempDir.path);
      await Hive.openBox('settings');
    });

    tearDown(() async {
      try {
        await Hive.close().timeout(const Duration(seconds: 3));
      } catch (_) {
        debugPrint('tearDown: Hive.close() 未在 3s 内返回（说明仍有 pending 真实 I/O）');
      }
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets('点「自动换源」+「淡入淡出」都正常结束，且都要求了落盘', (tester) async {
      final switchStore = MemoryAutoSourceSwitchStore();
      final effectsStore = MemoryAudioEffectsSettingsStore();

      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            autoSourceSwitchStoreProvider.overrideWithValue(switchStore),
            audioEffectsSettingsStoreProvider.overrideWithValue(effectsStore),
          ],
          child: const MaterialApp(home: SettingsAudioPage()),
        ),
      );
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettingsAudioPage)),
      );

      // ① 自动换源：默认开 → 点一下关。内存 store 必须收到那次写请求。
      expect(await _tapSwitch(tester, '自动换源'), isTrue);
      expect(container.read(autoSourceSwitchProvider).enabled, isFalse);
      expect(
        switchStore.writes,
        <bool>[false],
        reason: '点击必须要求落盘（只是落到了内存 store）—— 否则就是"只改内存"的假绿',
      );

      // ② 淡入淡出：同一个页面上的另一个"点击即持久化"路径（PROBE D 证明过它同样卡）。
      expect(await _tapSwitch(tester, '淡入淡出'), isTrue);
      expect(container.read(audioEffectsSettingsProvider).fadeEnabled, isTrue);
      expect(
        effectsStore.writes,
        isNotEmpty,
        reason: '音频增强设置也必须要求落盘',
      );

      // ③ 用内存 store 重建一个 notifier，证明"写进去的东西读得回来"
      //    （不依赖 toJson 的具体键名，避免把测试钉在实现细节上）。
      final restored = AudioEffectsSettingsNotifier(effectsStore);
      expect(restored.state.fadeEnabled, isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
