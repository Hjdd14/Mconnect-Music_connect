import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

typedef DiagnosticsDirectoryProvider = Future<Directory> Function();

class DiagnosticEvent {
  final DateTime timestamp;
  final String type;
  final String message;

  const DiagnosticEvent({
    required this.timestamp,
    required this.type,
    required this.message,
  });
}

class DiagnosticsService {
  static final DiagnosticsService instance = DiagnosticsService();

  final DiagnosticsDirectoryProvider _directoryProvider;
  final Duration slowOperationThreshold;
  final int maxLogBytes;
  final int maxRecentEvents;
  final Queue<DiagnosticEvent> _recentEvents = Queue<DiagnosticEvent>();
  final List<String> _pendingLines = <String>[];
  Future<void> _writeChain = Future<void>.value();
  Timer? _uiHeartbeatTimer;
  Stopwatch? _uiHeartbeatWatch;
  bool _initialized = false;
  late File _logFile;

  DiagnosticsService({
    DiagnosticsDirectoryProvider? directoryProvider,
    this.slowOperationThreshold = const Duration(milliseconds: 700),
    this.maxLogBytes = 1024 * 1024,
    this.maxRecentEvents = 200,
  }) : _directoryProvider =
           directoryProvider ?? getApplicationDocumentsDirectory;

  File get logFile => _logFile;

  List<DiagnosticEvent> get recentEvents => List.unmodifiable(_recentEvents);

  Future<void> initialize() async {
    if (_initialized) return;
    final baseDir = await _directoryProvider();
    await _initializeWithBaseDir(baseDir);
  }

  @visibleForTesting
  Future<void> initializeForTest(Directory baseDir) async {
    await resetForTest();
    await _initializeWithBaseDir(baseDir);
  }

  @visibleForTesting
  Future<void> resetForTest() async {
    dispose();
    await flush();
    _initialized = false;
    _pendingLines.clear();
    _recentEvents.clear();
    _writeChain = Future<void>.value();
  }

  Future<void> _initializeWithBaseDir(Directory baseDir) async {
    final logDir = Directory('${baseDir.path}${Platform.pathSeparator}logs');
    if (!await logDir.exists()) {
      await logDir.create(recursive: true);
    }
    _logFile = File('${logDir.path}${Platform.pathSeparator}mconnect.log');
    if (!await _logFile.exists()) {
      await _logFile.create(recursive: true);
    }
    _initialized = true;
    record('lifecycle', 'diagnostics_initialized path=${_logFile.path}');
  }

  void record(String type, String message, {Map<String, Object?>? data}) {
    if (!_initialized) {
      return;
    }
    final event = DiagnosticEvent(
      timestamp: DateTime.now(),
      type: type,
      message: data == null || data.isEmpty
          ? message
          : '$message ${jsonEncode(data)}',
    );
    _recentEvents.addLast(event);
    while (_recentEvents.length > maxRecentEvents) {
      _recentEvents.removeFirst();
    }
    _pendingLines.add(_formatEvent(event));
    _scheduleWrite();
  }

  Future<T> measure<T>(
    String name,
    FutureOr<T> Function() action, {
    Duration? threshold,
    Map<String, Object?>? data,
  }) async {
    final watch = Stopwatch()..start();
    try {
      return await action();
    } catch (error, stack) {
      recordError(name, error, stack, data: data);
      rethrow;
    } finally {
      watch.stop();
      final limit = threshold ?? slowOperationThreshold;
      if (watch.elapsed >= limit) {
        record(
          'slow_operation',
          name,
          data: {
            'elapsed_ms': watch.elapsedMilliseconds,
            if (data != null) ...data,
          },
        );
      }
    }
  }

  void recordError(
    String source,
    Object error,
    StackTrace stack, {
    Map<String, Object?>? data,
  }) {
    record(
      'error',
      source,
      data: {
        'error': error.toString(),
        'stack': _compactStack(stack),
        if (data != null) ...data,
      },
    );
  }

  void startUiHeartbeat({
    Duration interval = const Duration(seconds: 1),
    Duration freezeThreshold = const Duration(milliseconds: 2500),
  }) {
    if (!_initialized || _uiHeartbeatTimer != null) return;
    _uiHeartbeatWatch = Stopwatch()..start();
    _uiHeartbeatTimer = Timer.periodic(interval, (_) {
      final watch = _uiHeartbeatWatch;
      if (watch == null) return;
      final elapsed = watch.elapsed;
      if (elapsed > interval + freezeThreshold) {
        record(
          'ui_freeze',
          'main_isolate_heartbeat_delay',
          data: {'elapsed_ms': elapsed.inMilliseconds},
        );
      }
      watch
        ..reset()
        ..start();
    });
  }

  Future<void> flush() async {
    await _writeChain;
  }

  Future<void> clear() async {
    if (!_initialized) return;
    _pendingLines.clear();
    await flush();
    await _logFile.writeAsString('', flush: true);
    _recentEvents.clear();
    record('lifecycle', 'diagnostics_log_cleared');
  }

  void dispose() {
    _uiHeartbeatTimer?.cancel();
    _uiHeartbeatTimer = null;
  }

  String _formatEvent(DiagnosticEvent event) {
    return '${event.timestamp.toIso8601String()} [${event.type}] ${event.message}\n';
  }

  String _compactStack(StackTrace stack) {
    final lines = stack.toString().split('\n');
    return lines.take(8).join(' | ');
  }

  void _scheduleWrite() {
    _writeChain = _writeChain.then((_) async {
      if (_pendingLines.isEmpty) return;
      final lines = List<String>.from(_pendingLines);
      _pendingLines.clear();
      try {
        await _logFile.writeAsString(
          lines.join(),
          mode: FileMode.append,
          flush: false,
        );
        await _truncateIfNeeded();
      } catch (error) {
        debugPrint('Diagnostics write failed: $error');
      }
    });
  }

  Future<void> _truncateIfNeeded() async {
    final length = await _logFile.length();
    if (length <= maxLogBytes) return;
    final bytes = await _logFile.readAsBytes();
    final keep = maxLogBytes ~/ 2;
    final tail = bytes.length <= keep
        ? bytes
        : bytes.sublist(bytes.length - keep);
    final marker =
        '${DateTime.now().toIso8601String()} [lifecycle] log_truncated\n';
    await _logFile.writeAsBytes([
      ...utf8.encode(marker),
      ...tail,
    ], flush: false);
  }
}
