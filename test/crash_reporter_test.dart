import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/diagnostics/crash_reporter.dart';
import 'package:mconnect/core/diagnostics/diagnostics_service.dart';

/// 崩溃上报门面（W3-C ①）。
///
/// 要守住的两条硬约束：
/// 1. **没有 DSN 就绝无网络行为** —— 默认构建（不带 `--dart-define`）里连远端接缝
///    都不存在，所以"忘配 DSN 就偷偷上报"在结构上不可能；
/// 2. **日志里不得出现未知/敏感字段** —— task-23 的 `sk` / `api_sig` 就是这类字段，
///    而 `DiagnosticsRedactor` 只认识它被教过的键名，所以门面**只写白名单字段**，
///    再把整行过一次脱敏，而不是把调用方的 `data` 原样塞进去。
void main() {
  late Directory tempDir;
  late DiagnosticsService diagnostics;

  /// 记录远端收到的报告；同时可断言"根本没被调用"。
  final captured = <CrashReport>[];
  final remoteSink = _SpySink(captured);

  setUp(() async {
    captured.clear();
    tempDir = await Directory.systemTemp.createTemp('mconnect_crash_test_');
    diagnostics = DiagnosticsService(directoryProvider: () async => tempDir);
    await diagnostics.initialize();
  });

  tearDown(() async {
    diagnostics.dispose();

    // 先把已经排进写链的日志落地再动目录：`File.writeAsString` 会短暂持有文件
    // 句柄，句柄没释放时 Windows 上的 `Directory.delete(recursive: true)` 会以
    // errno 32（ERROR_SHARING_VIOLATION，"另一个程序正在使用此文件"）失败。
    // 不是每条用例都会读回日志（例如"远端拿到的是脱敏文本"那条只断言 spy），
    // 所以这里必须自己 flush，不能指望上一条 `logText()`。
    await diagnostics.flush();
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } on FileSystemException {
      // Windows：句柄可能刚好还在关闭中。把临时目录留给系统清理是可以接受的，
      // 因为清理失败而让一条**行为正确**的用例变红是不可以接受的。
      // （注意这是容错，不是"不删"：正常情况下目录仍会被删掉。）
    }
  });

  Future<String> logText() async {
    // 先让已经排进写链的本地记录落地（`report` 在第一个 await 之前就同步排好），
    // 再 flush 读文件。
    await Future<void>.delayed(Duration.zero);
    await diagnostics.flush();
    return diagnostics.logFile.readAsString();
  }

  group('本地优先 / 零账号依赖', () {
    test('没有 DSN：不上报远端，只写本地诊断日志', () async {
      final reporter = CrashReporter(diagnostics: diagnostics, remote: remoteSink);

      await reporter.report(
        'FlutterError',
        StateError('boom'),
        StackTrace.fromString('stack line'),
      );

      expect(
        reporter.hasRemote,
        isFalse,
        reason: '没有 DSN 时连"有远端"都不该成立',
      );
      expect(
        captured,
        isEmpty,
        reason: '没有 DSN 时不得有任何远端调用（也就没有任何网络行为）',
      );
      final text = await logText();
      expect(text, contains('FlutterError'));
      expect(text, contains('Bad state: boom'));
    });

    test('默认构造（无 DSN、无远端接缝）也不崩，且只写本地', () async {
      final reporter = CrashReporter(diagnostics: diagnostics);
      await reporter.report('runZonedGuarded', 'plain string error', null);

      expect(reporter.hasRemote, isFalse);
      expect(await logText(), contains('plain string error'));
    });

    test('给了 DSN 且有远端接缝：本地与远端都收到，且远端拿到的是脱敏后的文本', () async {
      final reporter = CrashReporter(
        diagnostics: diagnostics,
        remote: remoteSink,
        dsn: 'https://example.invalid/1',
      );

      await reporter.report(
        'FlutterError',
        Exception('failed at https://api.example/x?song=1&token=SECRETTOKEN'),
        StackTrace.fromString('stack line'),
      );

      expect(reporter.hasRemote, isTrue);
      expect(captured, hasLength(1));
      expect(
        captured.single.text,
        isNot(contains('SECRETTOKEN')),
        reason: '远端必须拿到已经脱敏的文本，而不是原文',
      );
      // 注意：脱敏器对 URL 的策略是**整段 query 一起换掉**（它的文档写明：漏一个
      // 参数就是漏一个凭证，丢一个参数只是日志难读一点），所以 `song=1` 也会被
      // 一起抹掉 —— 这里只能断言"路径还在、query 变成 <redacted>"。
      // 这条断言第一版写成了 `contains('song=1')`，与脱敏器的既有契约冲突，
      // 是**测试写错了**，不是脱敏器该改。
      expect(captured.single.text, contains('https://api.example/x'));
      expect(captured.single.text, contains('<redacted>'));
    });

    test('给了 DSN 但没有远端接缝：不崩、仍写本地，且只记一次"远端不可用"', () async {
      // 这就是今天的现实：`sentry_flutter` 还不是依赖（见交付摘要），所以给了 DSN
      // 也只能走本地 —— 但必须**说清楚**，而不是静默降级。
      final reporter = CrashReporter(
        diagnostics: diagnostics,
        dsn: 'https://example.invalid/1',
      );

      await reporter.report('FlutterError', StateError('one'), null);
      await reporter.report('FlutterError', StateError('two'), null);

      final text = await logText();
      expect(text, contains('Bad state: one'));
      expect(text, contains('Bad state: two'));
      expect(
        RegExp('crash_remote_unavailable').allMatches(text).length,
        1,
        reason: '缺远端接缝只提示一次，否则崩溃循环会把日志刷爆',
      );
    });
  });

  group('脱敏与字段白名单', () {
    test('URL 查询串与凭证不出现在日志里', () async {
      final reporter = CrashReporter(diagnostics: diagnostics);

      await reporter.report(
        'FlutterError',
        Exception('GET https://api.example/player?token=SECRETTOKEN&sign=DEADBEEF'),
        StackTrace.fromString('at foo (x.dart:1)'),
      );

      final text = await logText();
      expect(text, contains('<redacted>'));
      expect(text, isNot(contains('SECRETTOKEN')));
      expect(text, isNot(contains('DEADBEEF')));
    });

    test('data 只保留白名单字段：未知键（如 api_sig / sk）整键丢弃', () async {
      final reporter = CrashReporter(diagnostics: diagnostics);

      await reporter.report(
        'FlutterError',
        StateError('boom'),
        null,
        data: {
          'screen': 'player',
          // 脱敏器**不认识**这些键名（task-23 修过的就是这类），所以门面必须在
          // 白名单这一层就把它们挡掉，不能指望脱敏正则。
          'api_sig': 'SIGVALUE',
          'sk': 'SKVALUE',
          'random_blob': 'BLOBVALUE',
        },
      );

      final text = await logText();
      expect(text, contains('screen=player'));
      expect(text, isNot(contains('SIGVALUE')));
      expect(text, isNot(contains('SKVALUE')));
      expect(text, isNot(contains('BLOBVALUE')));
      expect(text, isNot(contains('api_sig')));
    });

    test('白名单字段本身若含凭证，也会被脱敏', () async {
      final reporter = CrashReporter(diagnostics: diagnostics);

      await reporter.report(
        'FlutterError',
        StateError('boom'),
        null,
        data: {'route': '/import-playlist?token=ROUTETOKEN'},
      );

      final text = await logText();
      expect(text, isNot(contains('ROUTETOKEN')));
    });
  });

  group('三个入口的接线', () {
    late FlutterExceptionHandler? previousOnError;
    late ErrorWidgetBuilder previousErrorWidget;

    setUp(() {
      previousOnError = FlutterError.onError;
      previousErrorWidget = ErrorWidget.builder;
    });

    tearDown(() {
      FlutterError.onError = previousOnError;
      ErrorWidget.builder = previousErrorWidget;
    });

    test('接管 FlutterError.onError：先上报，再交回原有呈现逻辑', () async {
      final reporter = CrashReporter(diagnostics: diagnostics);
      final details = FlutterErrorDetails(exception: StateError('framework boom'));

      var presented = 0;
      installCrashHandling(
        reporter,
        buildErrorWidget: (_) => const SizedBox.shrink(),
        presentError: (_) => presented++,
      );

      FlutterError.onError!(details);

      expect(presented, 1, reason: '原有 presentError 必须仍然被调用');
      expect(await logText(), contains('Bad state: framework boom'));
    });

    test('接管 ErrorWidget.builder：保留原有 UI，同时上报', () async {
      final reporter = CrashReporter(diagnostics: diagnostics);
      const sentinel = SizedBox.shrink();
      final details = FlutterErrorDetails(exception: StateError('widget boom'));

      installCrashHandling(reporter, buildErrorWidget: (_) => sentinel);

      expect(
        identical(ErrorWidget.builder(details), sentinel),
        isTrue,
        reason: 'ErrorWidget.builder 必须保留原有 UI（只是顺手上报）',
      );
      expect(await logText(), contains('Bad state: widget boom'));
    });

    test('返回的 zone 回调落进同一份诊断日志', () async {
      final reporter = CrashReporter(diagnostics: diagnostics);
      final onZoneError = installCrashHandling(
        reporter,
        buildErrorWidget: (_) => const SizedBox.shrink(),
      );

      // main.dart 就是把这个回调交给 `runZonedGuarded` 的第二个参数。
      onZoneError(StateError('zone boom'), StackTrace.fromString('zone stack'));

      final text = await logText();
      expect(text, contains('runZonedGuarded'));
      expect(text, contains('Bad state: zone boom'));
    });
  });
}

class _SpySink implements CrashSink {
  _SpySink(this.captured);

  final List<CrashReport> captured;

  @override
  Future<void> capture(CrashReport report) async {
    captured.add(report);
  }
}
