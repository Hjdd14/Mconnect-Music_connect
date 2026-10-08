import 'dart:async';

import 'package:flutter/widgets.dart';

import 'diagnostics_redactor.dart';
import 'diagnostics_service.dart';

/// 构建期注入的崩溃上报 DSN：`--dart-define=MCONNECT_SENTRY_DSN=https://…`。
///
/// 默认（不传）是空串，即**本地模式**：`CrashReporter.hasRemote` 恒为 false，
/// 远端接缝一次都不会被调用 —— 所以"忘配 DSN 就偷偷上报"在结构上不可能发生，
/// 而不是靠"记得别上报"。
const String crashReporterDsn = String.fromEnvironment('MCONNECT_SENTRY_DSN');

/// 允许写进日志的上下文字段**白名单**。
///
/// 为什么不直接脱敏调用方的 `data`：`DiagnosticsRedactor` 只认识它被教过的键名，
/// 而真实泄漏恰恰发生在它不认识的键上（task-23 的 `sk` / `api_sig`）。所以这里
/// **默认拒绝**：不在白名单里的键整键丢弃；白名单字段的值再过一次脱敏
/// （值本身也可能带凭证，例如 `route` 上挂了一段 query）。
const Set<String> crashSafeDataKeys = <String>{
  'screen',
  'phase',
  'platform',
  'song_id',
  'route',
};

/// 一条**已经脱敏完毕**的崩溃报告。
///
/// 远端 sink 拿到的就是它 —— 脱敏发生在门面里、fan-out 之前，所以即使将来接上
/// 远端，远端也拿不到原文。`data` 同样只含白名单字段。
@immutable
class CrashReport {
  const CrashReport({
    required this.source,
    required this.text,
    required this.data,
    required this.at,
  });

  /// 出错入口，例如 `FlutterError` / `ErrorWidget` / `runZonedGuarded`。
  final String source;

  /// 已脱敏的单行文本（本地日志与远端都用它）。
  final String text;

  /// 只含 [crashSafeDataKeys] 里的字段。
  final Map<String, String> data;

  final DateTime at;
}

/// 远端上报接缝。
///
/// 今天没有实现类：`sentry_flutter` 不是本仓库的依赖，而加它要动 `pubspec.yaml`
/// 并满足 AGP ≥ 8.12.1（本仓库是 8.11.1）—— 那是"工具链现代化"那次独立决策的
/// 事。留这个接缝是为了让远端接入**不需要改门面**，也让"没有 DSN 就没有网络行为"
/// 这条约束可以被测试直接断言。
abstract class CrashSink {
  Future<void> capture(CrashReport report);
}

/// 崩溃上报门面：**本地优先，远端可选**。
///
/// 两个入口都指向同一份诊断日志（[DiagnosticsService]），也就是"导出诊断日志"
/// 里用户能自己看到的那份文件。
class CrashReporter {
  /// 字段直接用初始化形参（`this.diagnostics`）：命名参数不能带下划线前缀，
  /// 所以想让 `prefer_initializing_formals` 满意就只能让字段名等于参数名。
  CrashReporter({
    this.diagnostics,
    this.remote,
    this.dsn = crashReporterDsn,
  });

  /// 本地落点；null 表示"只算不写"（测试里可用）。
  final DiagnosticsService? diagnostics;

  /// 远端接缝；null 表示没有接缝（今天就是这种情况）。
  final CrashSink? remote;

  final String dsn;

  /// 只在"DSN 非空 **且** 有远端接缝"时为真；没有 DSN 时恒为 false。
  bool get hasRemote => dsn.isNotEmpty && remote != null;

  bool _notedMissingRemote = false;

  /// 记录一次崩溃。
  ///
  /// **永远先写本地**（同步入队，所以调用方 `unawaited(...)` 也不会丢），
  /// 然后仅在 [hasRemote] 时才转发给远端。
  Future<void> report(
    String source,
    Object error,
    StackTrace? stack, {
    Map<String, Object?>? data,
  }) {
    final report = _build(source, error, stack, data);
    _writeLocal(report);

    if (dsn.isEmpty) return Future<void>.value();
    final sink = remote;
    if (sink == null) {
      _noteMissingRemote();
      return Future<void>.value();
    }
    return sink.capture(report);
  }

  CrashReport _build(
    String source,
    Object error,
    StackTrace? stack,
    Map<String, Object?>? data,
  ) {
    final safeData = <String, String>{};
    final raw = StringBuffer()
      ..write('source=$source')
      ..write(' error=$error');
    if (data != null) {
      for (final entry in data.entries) {
        // 默认拒绝：不认识/不信任的键一律不写。
        if (!crashSafeDataKeys.contains(entry.key)) continue;
        safeData[entry.key] = '${entry.value}';
        raw.write(' ${entry.key}=${entry.value}');
      }
    }
    if (stack != null) {
      raw.write(' stack=${_compactStack(stack)}');
    }

    return CrashReport(
      source: source,
      // 整行脱敏：白名单字段的值与错误文本都可能带凭证。
      text: DiagnosticsRedactor.redactText(raw.toString()),
      data: Map<String, String>.unmodifiable(safeData),
      at: DateTime.now(),
    );
  }

  void _writeLocal(CrashReport report) {
    diagnostics?.record('crash', report.text);
  }

  /// DSN 配了却没有远端接缝时，提示**一次**就够：崩溃循环下每次崩溃都写会
  /// 把日志刷爆，反而把真正的崩溃信息挤掉。
  void _noteMissingRemote() {
    if (_notedMissingRemote) return;
    _notedMissingRemote = true;
    diagnostics?.record(
      'crash_remote_unavailable',
      'a DSN was supplied at build time but no remote sink is wired '
      '(sentry_flutter is not a dependency yet); staying local',
    );
  }

  static String _compactStack(StackTrace stack) =>
      stack.toString().split('\n').take(8).join(' | ');
}

/// `runZonedGuarded` 的 onError 形态。
typedef ZoneErrorHandler = void Function(Object error, StackTrace stack);

/// 把 [reporter] 接到进程级的三个入口：
///
/// * `FlutterError.onError` —— 先上报，再把控制权交回 [presentError]
///   （默认就是 `FlutterError.presentError`，即原来的控制台红字行为）；
/// * `ErrorWidget.builder` —— 保留调用方给的 UI（`main.dart` 的红屏文案），
///   只是顺手上报；
/// * **返回**一个 zone 回调，交给 `runZonedGuarded` 的第二个参数（返回值而不是
///   在这里直接调 `runZonedGuarded`，是为了让这条接线可以在测试里被直接驱动）。
ZoneErrorHandler installCrashHandling(
  CrashReporter reporter, {
  required Widget Function(FlutterErrorDetails details) buildErrorWidget,
  void Function(FlutterErrorDetails details)? presentError,
}) {
  final present = presentError ?? FlutterError.presentError;

  FlutterError.onError = (details) {
    unawaited(reporter.report('FlutterError', details.exception, details.stack));
    present(details);
  };

  ErrorWidget.builder = (details) {
    unawaited(reporter.report('ErrorWidget', details.exception, details.stack));
    return buildErrorWidget(details);
  };

  return (error, stack) {
    unawaited(reporter.report('runZonedGuarded', error, stack));
  };
}
