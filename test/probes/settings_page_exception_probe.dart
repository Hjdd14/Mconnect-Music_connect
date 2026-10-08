import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/features/scrobble/data/scrobble_config.dart';
import 'package:mconnect/features/scrobble/presentation/providers/scrobble_provider.dart';
import 'package:mconnect/features/settings/presentation/pages/settings_page.dart';

/// 一次性诊断工具：**把 `SettingsPage` 里发生的每个异常连同完整栈打出来**。
///
/// # 为什么文件名不是 `*_test.dart`
/// `flutter test`（无参数）只收集 `test/**/*_test.dart`。这个文件**故意**不匹配那个
/// 约定，所以它**不会**进入全量套件（上一版探针以 `_test.dart` 命名常驻套件时，
/// 污染了共享 Hive 状态、让 `diagnostics_export_test` 的截断用例红 —— 已实测）。
///
/// **跑法（显式指定文件）**：
/// ```powershell
/// flutter test test/probes/settings_page_exception_probe.dart -r expanded 2>&1 | Select-String "PROBE"
/// ```
/// 取证完可以直接删掉本文件；它不影响 `flutter analyze`（analyze 会看它，但它是合法代码）。
///
/// # 它回答什么问题
/// `tester.takeException()` 只给一个摘要（`String :: Multiple exceptions (2)…`），
/// 看不到第二个异常。这里改成**接管 `FlutterError.onError`**，把测试期间
/// `FlutterError.reportError` 报出的每一个异常都收下来，逐个打印
/// `runtimeType` + `toString()` + **完整 `stack`**。
///
/// 三个变体把"异常来自哪里"切成可判定的三段：
/// | 变体 | Hive | store override | 期望能区分出的异常源 |
/// |---|---|---|---|
/// | **V2** | 已开 | 无 | 你复跑过的形状：应看到 2 个异常 |
/// | **V3** | 已开 | 两个 store 都换内存 | 若异常清空/只剩 1 个 ⇒ 剩下的那个才是真环 |
/// | **V4** | 已开 | 只换 preference store | 若仍有异常 ⇒ 来自 **secrets 的平台通道**（`FlutterSecureStorage` 在测试里 `invokeMethod` 返回 null ⇒ `MissingPluginException`） |
///
/// 这三个变体同时告诉你"接线到底能不能留"：
/// 只要**某个变体**打印出 `section=1 backup=1 diagnostics=1` 且没有异常，接线就是有效的，
/// 剩下的问题只是"测试环境要不要 override store"。
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mconnect_exc_probe_');
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
  });

  tearDown(() async {
    try {
      await Hive.close().timeout(const Duration(seconds: 3));
    } catch (_) {
      debugPrint('PROBE tearDown: Hive.close() 未在 3s 内返回');
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// 接管 FlutterError.onError：一条测试里发生的**每一个**异常都会被收下来。
  /// 收下来之后 flutter_test 就**不会**再因为"报过一个 FlutterError"而判这条测试失败，
  /// 于是探针总能跑完并把栈打出来。
  List<FlutterErrorDetails> captureExceptions() {
    final captured = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = captured.add;
    addTearDown(() => FlutterError.onError = previous);
    return captured;
  }

  void printExceptions(List<FlutterErrorDetails> captured, String tag) {
    debugPrint(
      'PROBE $tag: capturedExceptions=${captured.length}'
      '${captured.isEmpty ? '' : '  ← 下面逐个打印类型 + 文本 + 完整栈'}',
    );
    for (var i = 0; i < captured.length; i++) {
      final details = captured[i];
      debugPrint('PROBE $tag EXC[$i] type=${details.exception.runtimeType}');
      debugPrint('PROBE $tag EXC[$i] text=${details.exception}');
      debugPrint('PROBE $tag EXC[$i] stack=${details.stack}');
      // `library`/`context` 常常直接指向出错的 widget（例如我的区块）。
      debugPrint('PROBE $tag EXC[$i] context=${details.context}');
      debugPrint('PROBE $tag EXC[$i] lib=${details.library}');
    }
  }

  void printCounters(WidgetTester tester, String tag) {
    debugPrint(
      'PROBE $tag: section=${find.text('听歌记录同步').evaluate().length} '
      'audio=${find.text('音频增强').evaluate().length} '
      'backup=${find.text('备份与恢复').evaluate().length} '
      'diagnostics=${find.text('诊断与关于').evaluate().length} '
      'transientCallbackCount=${tester.binding.transientCallbackCount}',
    );
  }

  Future<void> runVariant(
    WidgetTester tester, {
    required String tag,
    required List<Override> overrides,
  }) async {
    final captured = captureExceptions();

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    printCounters(tester, tag);
    printExceptions(captured, tag);

    // 滚一下，看看"下面没渲染出来的行"是不是被异常打断的（而不是懒构建）。
    for (var i = 0; i < 10; i++) {
      if (find.text('诊断与关于').evaluate().isNotEmpty) break;
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -260));
      for (var f = 0; f < 30; f++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }
    debugPrint(
      'PROBE $tag VERDICT: exceptions=${captured.length} '
      'diagnosticsAfterDrag=${find.text('诊断与关于').evaluate().length}',
    );

    // 收口：真实 I/O 落定，避免探针自己留下 pending。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
  }

  testWidgets('V2：无 override（你复跑的形状）—— 应看到 2 个异常', (tester) async {
    await runVariant(tester, tag: 'V2(no-override)', overrides: const <Override>[]);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('V3：两个 store 都换内存 —— 剩下的就是真环（若有）', (tester) async {
    await runVariant(
      tester,
      tag: 'V3(both-memory)',
      overrides: <Override>[
        scrobblePreferenceStoreProvider.overrideWith(
          (ref) => MemoryScrobblePreferenceStore(),
        ),
        scrobbleSecretStoreProvider.overrideWith(
          (ref) => MemoryScrobbleSecretStore(),
        ),
      ],
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('V4：只换 preference store —— 剩下的异常来自 secrets 的平台通道', (
    tester,
  ) async {
    await runVariant(
      tester,
      tag: 'V4(prefs-only)',
      overrides: <Override>[
        scrobblePreferenceStoreProvider.overrideWith(
          (ref) => MemoryScrobblePreferenceStore(),
        ),
      ],
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('V5：**开启状态**（prefs 预置 enabled）—— 验证开启路径也不炸', (tester) async {
    // 这是默认关闭之外的另一半：凭据 provider 会被构造、refresh() 会被调用
    // （它会读协调器 → 数据库；scrobble 侧把那段包在 try/catch 里）。
    // 两个 store 都换内存，避免把"平台通道/数据库在测试里不可用"混进来。
    await runVariant(
      tester,
      tag: 'V5(enabled+memory)',
      overrides: <Override>[
        scrobblePreferenceStoreProvider.overrideWith(
          (ref) => MemoryScrobblePreferenceStore(
            const ScrobblePreferences(enabled: true),
          ),
        ),
        scrobbleSecretStoreProvider.overrideWith(
          (ref) => MemoryScrobbleSecretStore(),
        ),
      ],
    );
  }, timeout: const Timeout(Duration(seconds: 30)));
}
