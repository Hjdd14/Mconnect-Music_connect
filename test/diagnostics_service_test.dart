import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/diagnostics/diagnostics_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mconnect_diag_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('records slow operations to memory and log file', () async {
    final service = DiagnosticsService(
      directoryProvider: () async => tempDir,
      slowOperationThreshold: const Duration(milliseconds: 1),
    );

    await service.initialize();
    await service.measure('test.slow', () async {
      await Future<void>.delayed(const Duration(milliseconds: 3));
      return 1;
    });
    await service.flush();

    final content = await service.logFile.readAsString();

    expect(content, contains('slow_operation'));
    expect(content, contains('test.slow'));
    expect(
      service.recentEvents.any((e) => e.message.contains('test.slow')),
      isTrue,
    );
  });

  test('records uncaught errors without throwing', () async {
    final service = DiagnosticsService(directoryProvider: () async => tempDir);

    await service.initialize();
    service.recordError(
      'test.error',
      StateError('broken'),
      StackTrace.fromString('stack line'),
    );
    await service.flush();

    final content = await service.logFile.readAsString();

    expect(content, contains('error'));
    expect(content, contains('test.error'));
    expect(content, contains('Bad state: broken'));
  });

  test('truncates oversized log files and keeps recent content', () async {
    final service = DiagnosticsService(
      directoryProvider: () async => tempDir,
      maxLogBytes: 180,
    );

    await service.initialize();
    for (var i = 0; i < 20; i++) {
      service.record('event', 'line-$i');
    }
    await service.flush();

    final content = await service.logFile.readAsString();

    expect(await service.logFile.length(), lessThanOrEqualTo(180));
    expect(content, contains('log_truncated'));
    expect(content, contains('line-19'));
  });
}
