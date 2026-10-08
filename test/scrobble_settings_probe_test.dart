import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/core/source_matching/source_match_settings.dart';
import 'package:mconnect/features/settings/presentation/pages/settings_page.dart';

/// 「设置页卡死」的**诊断探针**（不是功能用例）。
///
/// # 背景
/// `test/settings_page_test.dart` 里那条 `the 自动换源 switch is wired to the
/// provider and flips it` 被 `skip: true` 了：body 的六个 STEP 全部打印之后，
/// 测试仍在自己的 30s 超时上死掉。二进制搜索已经把范围缩到 **teardown /
/// pending-async**（不是 body 里的 await，也不是 `pumpAndSettle`）。
///
/// # 本文件要证伪/证实的假设
/// **假设**：`AutoSourceSwitchNotifier.setEnabled` 在点击回调里 `unawaited(box.put(...))`
/// 起了一次**真实文件 I/O**。`testWidgets` 的 body 跑在 FakeAsync 里，这次写入的
/// continuation 因此排在**假时钟的微任务队列**上，body 结束后再也没人排空它 →
/// 文件里 `tearDown` 的 `await Hive.close()` 一直等这个写入收口 → 30s 超时。
///
/// 三个探针把这条链切成可观测的三段：
/// * **A** 只 pump 页面、**不点**开关 → 期望 `Hive.close()` 正常返回；
/// * **B** pump + 点开关、**不做真实收口** → 期望 `Hive.close()` 超时（复现）；
/// * **C** pump + 点开关 + `tester.runAsync` 让真实 I/O 收口 → 期望正常返回（修复方案）。
///
/// # 为什么探针不会把套件拖住（与那条 skip 用例的关键差别）
/// 每个 `Hive.close()` 都套了 `.timeout(3s)`，并且都在 `tester.runAsync`（真实事件循环）
/// 里跑；`tearDown` 里的 close 同样带上限。所以最坏情况是"打印 TIMEOUT 然后继续"，
/// 而不是"卡 30 秒"。
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mconnect_probe_test_');
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
  });

  tearDown(() async {
    // 有意不裸 await：若 pending 源就是那条 Hive 写入，这里同样会等不到。
    // 探针的价值在打印诊断，不在复现卡死。
    try {
      await Hive.close().timeout(const Duration(seconds: 3));
    } catch (_) {
      debugPrint(
        'PROBE tearDown: Hive.close() 未在 3s 内返回 —— pending 源的指纹（见文件头注释）',
      );
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// 有界 pump：这一页不能用 `pumpAndSettle`（见 test/settings_page_test.dart 的注释）。
  Future<void> pumpFrames(WidgetTester tester, {int frames = 60}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// 滚到「自动换源」可见（有界：最多 10 次 drag，每次 30 帧）。
  Future<void> dragUntilAutoSourceVisible(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      if (find.text('自动换源').evaluate().isNotEmpty) return;
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -260));
      await pumpFrames(tester, frames: 30);
    }
  }

  void printCounters(WidgetTester tester, String tag) {
    debugPrint(
      'PROBE $tag: transientCallbackCount=${tester.binding.transientCallbackCount} '
      'hasScheduledFrame=${tester.binding.hasScheduledFrame} '
      'hiveBoxOpen=${Hive.isBoxOpen('settings')}',
    );
  }

  /// 在真实事件循环里收口一次 `Hive.close()`，最多等 3s。
  Future<String> probeHiveClose(WidgetTester tester) async {
    final result = await tester.runAsync(() async {
      try {
        await Hive.close().timeout(const Duration(seconds: 3));
        return 'closed-ok';
      } on TimeoutException {
        return 'closed-TIMEOUT(3s)';
      }
    });
    return result ?? 'runAsync-null';
  }

  testWidgets('PROBE A：只 pump 页面、不点开关 → Hive.close() 应正常返回', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsAudioPage())),
    );
    await pumpFrames(tester);
    printCounters(tester, 'A(before-drag)');

    // 直接检验那条注释里的说法（"这一页有常驻动画，所以 pumpAndSettle 会挂"）。
    // 用**有界**的 pumpAndSettle：3 秒内收不住就说明确实一直有帧在排队 ——
    // 而这一页（AuthPage 之外）我读过全部 build：没有任何 Animation/Progress
    // 组件，所以"常驻动画"更可能是"某个 pending 的异步每帧 setState"。
    String settleVerdict = 'settled';
    try {
      await tester.pumpAndSettle(
        const Duration(milliseconds: 16),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 3),
      );
    } catch (error) {
      settleVerdict = 'NOT-settled(${error.runtimeType})';
    }
    debugPrint('PROBE A: boundedPumpAndSettle=$settleVerdict');

    await dragUntilAutoSourceVisible(tester);
    printCounters(tester, 'A(after-drag)');

    final close = await probeHiveClose(tester);
    debugPrint('PROBE A VERDICT: hiveClose=$close boundedPumpAndSettle=$settleVerdict');
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('PROBE B：点了开关但不用 runAsync 收口 → 期望 close 超时（复现）', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsAudioPage())),
    );
    await pumpFrames(tester);
    await dragUntilAutoSourceVisible(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsAudioPage)),
    );
    final before = container.read(autoSourceSwitchProvider).enabled;
    await tester.tap(find.text('自动换源'));
    await pumpFrames(tester);
    final after = container.read(autoSourceSwitchProvider).enabled;
    debugPrint('PROBE B: provider $before → $after（内存状态是同步翻转的，这一步必然成功）');
    printCounters(tester, 'B(after-tap)');

    final close = await probeHiveClose(tester);
    debugPrint(
      'PROBE B VERDICT: hiveClose=$close'
      '${close.startsWith('closed-TIMEOUT') ? '  ← 复现成功：pending 源是点击触发的 Hive 写入' : ''}',
    );

    // 兜底：不让探针本身把套件留在"有 pending 真实 I/O"的状态里。
    // （若是 pending 源，这一步会让那次写入真正收口；先打印诊断，再收口。）
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('PROBE C：点了开关并 runAsync 收口 → Hive.close() 应正常返回（修复方案）', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsAudioPage())),
    );
    await pumpFrames(tester);
    await dragUntilAutoSourceVisible(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsAudioPage)),
    );
    final before = container.read(autoSourceSwitchProvider).enabled;
    await tester.tap(find.text('自动换源'));
    await pumpFrames(tester);
    final after = container.read(autoSourceSwitchProvider).enabled;

    // 关键一行：把 FakeAsync 里起的那次真实文件 I/O 交给真实事件循环跑完。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );

    final close = await probeHiveClose(tester);
    debugPrint('PROBE C VERDICT: hiveClose=$close');

    // 顺带把 A-6a 那个空缺补上：widget 层真的点到 provider 了（双向）。
    expect(after, isNot(before), reason: '点击必须翻转 provider');
    expect(
      tester
          .widget<SwitchListTile>(
            find.ancestor(
              of: find.text('自动换源'),
              matching: find.byType(SwitchListTile),
            ),
          )
          .value,
      after,
      reason: '开关本体必须跟着 provider 走',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));
}
