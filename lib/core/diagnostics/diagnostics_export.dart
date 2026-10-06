import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants/app_constants.dart';
import 'diagnostics_redactor.dart';
import 'diagnostics_service.dart';

/// Where the export is written.
typedef DiagnosticsExportDirectoryProvider = Future<Directory> Function();

/// The redaction applied to a bundle, injectable so a test can prove that the
/// stripping is what keeps secrets out (inject a pass-through and the secret
/// reappears).
typedef DiagnosticsRedactFn = RedactionResult Function(String input);

/// What an export produced.
class DiagnosticsExportResult {
  /// The file the user can share. It lives in the OS temporary directory, so
  /// the caller must share/copy it before the next cleanup — the app never
  /// keeps it around.
  final File file;

  /// Size on disk in bytes (read back from the file, not estimated).
  final int byteSize;

  /// Number of ring-buffer events written.
  final int eventCount;

  /// Bytes of the on-disk log that made it into the bundle.
  final int logBytesIncluded;

  /// True when the log was longer than [DiagnosticsExporter.maxLogBytes] and
  /// only its tail was exported.
  final bool logTruncated;

  /// Which redaction rules fired (`cookie-header`, `url-query`, …); empty means
  /// the bundle contained nothing sensitive.
  final Set<String> redactions;

  const DiagnosticsExportResult({
    required this.file,
    required this.byteSize,
    required this.eventCount,
    required this.logBytesIncluded,
    required this.logTruncated,
    required this.redactions,
  });

  String get filePath => file.path;

  @override
  String toString() =>
      'DiagnosticsExportResult(${file.path}, ${byteSize}B, '
      'events=$eventCount, log=${logBytesIncluded}B'
      '${logTruncated ? ' (truncated)' : ''}, '
      'redactions=${redactions.isEmpty ? 'none' : redactions.join(',')})';
}

/// Raised when an export cannot be produced. [message] is user-facing Chinese
/// text (the settings entry shows it verbatim); [cause] keeps the technical
/// detail for the log.
class DiagnosticsExportException implements Exception {
  final String message;
  final Object? cause;

  const DiagnosticsExportException(this.message, [this.cause]);

  @override
  String toString() =>
      'DiagnosticsExportException: $message${cause == null ? '' : ' ($cause)'}';
}

/// Writes "recent events + the current log file" to a shareable text file.
///
/// The export is a plain `.txt` on purpose: it is meant to survive being mailed
/// as an attachment or pasted into a chat, and any structured format would
/// tempt a reader into trusting fields that the redactor has replaced anyway.
class DiagnosticsExporter {
  DiagnosticsExporter({
    required this.service,
    DiagnosticsExportDirectoryProvider? directoryProvider,
    this.redact = DiagnosticsRedactor.redact,
    this.maxLogBytes = 512 * 1024,
    this.fileNamePrefix = 'mconnect-diagnostics',
  }) : _directoryProvider = directoryProvider ?? getTemporaryDirectory;

  final DiagnosticsService service;
  final DiagnosticsRedactFn redact;
  final DiagnosticsExportDirectoryProvider _directoryProvider;

  /// Cap on the log tail included in the export. The on-disk log is already
  /// capped at 1 MB (`DiagnosticsService.maxLogBytes`), but a share target that
  /// receives a 1 MB text file on a phone is a bad experience.
  final int maxLogBytes;

  final String fileNamePrefix;

  /// Builds the bundle and writes it. Never throws anything other than
  /// [DiagnosticsExportException].
  Future<DiagnosticsExportResult> export({
    int? maxEvents,
    DateTime? now,
  }) async {
    final timestamp = now ?? DateTime.now();

    if (!service.isInitialized) {
      throw const DiagnosticsExportException('诊断服务尚未初始化，暂时无法导出日志');
    }

    // Pending lines are still in memory; without this the bundle would miss the
    // very event the user is reporting.
    await service.flush();

    final events = _recentEvents(maxEvents);
    final log = await _readLog();

    final buffer = StringBuffer()
      ..writeln('Mconnect 诊断日志')
      ..writeln('生成时间: ${timestamp.toIso8601String()}')
      ..writeln('应用版本: ${AppConstants.appVersion}')
      ..writeln('平台: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
      ..writeln('日志文件: ${service.logFile.path}')
      ..writeln('最近事件: ${events.length} 条')
      ..writeln(
        '日志内容: ${log.includedBytes} 字节'
        '${log.truncated ? '（超出上限，仅含最后 $maxLogBytes 字节）' : ''}',
      )
      ..writeln()
      ..writeln('===== 最近事件 =====');
    if (events.isEmpty) {
      buffer.writeln('(暂无事件)');
    } else {
      for (final event in events) {
        buffer.writeln(_formatEvent(event));
      }
    }
    buffer
      ..writeln()
      ..writeln('===== 日志文件 =====');
    if (log.content.isEmpty) {
      buffer.writeln('(日志文件为空或不存在)');
    } else {
      buffer.write(log.content);
      if (!log.content.endsWith('\n')) buffer.writeln();
    }

    // Redaction runs on the *assembled* bundle, so a secret cannot slip through
    // via the header, an event message, or the log body.
    final redacted = redact(buffer.toString());

    final directory = await _resolveDirectory();
    final file = File(
      p.join(directory.path, '$fileNamePrefix-${_stamp(timestamp)}.txt'),
    );
    try {
      await file.writeAsString(redacted.text, flush: true);
    } catch (error) {
      throw DiagnosticsExportException('写入导出文件失败', error);
    }

    final int size;
    try {
      size = await file.length();
    } catch (error) {
      throw DiagnosticsExportException('导出文件写入后无法读取', error);
    }

    return DiagnosticsExportResult(
      file: file,
      byteSize: size,
      eventCount: events.length,
      logBytesIncluded: log.includedBytes,
      logTruncated: log.truncated,
      redactions: redacted.rules,
    );
  }

  List<DiagnosticEvent> _recentEvents(int? maxEvents) {
    final events = service.recentEvents;
    if (maxEvents == null || events.length <= maxEvents) return events;
    return events.sublist(events.length - maxEvents);
  }

  Future<_LogSlice> _readLog() async {
    final file = service.logFile;
    if (!await file.exists()) {
      return const _LogSlice(content: '', includedBytes: 0, truncated: false);
    }
    try {
      final length = await file.length();
      if (length <= maxLogBytes) {
        return _LogSlice(
          content: await file.readAsString(),
          includedBytes: length,
          truncated: false,
        );
      }
      // Tail only: when a log is half a megabyte, the newest lines are the ones
      // worth reading.
      final bytes = await file.readAsBytes();
      final tail = bytes.sublist(bytes.length - maxLogBytes);
      final text = utf8.decode(tail, allowMalformed: true);
      // Drop a partially cut first line — but not when the only newline is the
      // trailing one, which would throw away the whole tail.
      final newline = text.indexOf('\n');
      final aligned = (newline >= 0 && newline < text.length - 1)
          ? text.substring(newline + 1)
          : text;
      return _LogSlice(
        content:
            '--- 日志文件超过 $maxLogBytes 字节，以下为最后部分 ---\n$aligned',
        includedBytes: utf8.encode(aligned).length,
        truncated: true,
      );
    } catch (error) {
      // A single unreadable log file must not sink the whole export — the ring
      // buffer still holds the interesting events.
      return _LogSlice(
        content: '(日志文件读取失败: $error)',
        includedBytes: 0,
        truncated: false,
      );
    }
  }

  Future<Directory> _resolveDirectory() async {
    final Directory directory;
    try {
      directory = await _directoryProvider();
    } catch (error) {
      throw DiagnosticsExportException('无法解析导出目录', error);
    }
    try {
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
    } catch (error) {
      throw DiagnosticsExportException('无法创建导出目录', error);
    }
    return directory;
  }

  static String _stamp(DateTime dateTime) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${dateTime.year}${two(dateTime.month)}${two(dateTime.day)}'
        '-${two(dateTime.hour)}${two(dateTime.minute)}${two(dateTime.second)}'
        '-${dateTime.millisecond.toString().padLeft(3, '0')}';
  }

  static String _formatEvent(DiagnosticEvent event) =>
      '${event.timestamp.toIso8601String()} [${event.type}] ${event.message}';
}

/// Convenience entry point for callers that just want a shareable file.
///
/// ```dart
/// final result = await exportDiagnosticsLog();
/// await SharePlus.instance.share(
///   ShareParams(files: [XFile(result.filePath)]),
/// );
/// ```
Future<DiagnosticsExportResult> exportDiagnosticsLog({
  DiagnosticsService? service,
  DiagnosticsExportDirectoryProvider? directoryProvider,
  int? maxEvents,
  DateTime? now,
  int? maxLogBytes,
}) {
  return DiagnosticsExporter(
    service: service ?? DiagnosticsService.instance,
    directoryProvider: directoryProvider,
    maxLogBytes: maxLogBytes ?? 512 * 1024,
  ).export(maxEvents: maxEvents, now: now);
}

/// `DiagnosticsService`-flavoured spelling of [exportDiagnosticsLog], so the
/// settings entry reads `await DiagnosticsService.instance.exportToFile()`.
extension DiagnosticsExportOnService on DiagnosticsService {
  Future<DiagnosticsExportResult> exportToFile({
    DiagnosticsExportDirectoryProvider? directoryProvider,
    int? maxEvents,
    DateTime? now,
    int? maxLogBytes,
  }) {
    return exportDiagnosticsLog(
      service: this,
      directoryProvider: directoryProvider,
      maxEvents: maxEvents,
      now: now,
      maxLogBytes: maxLogBytes,
    );
  }
}

class _LogSlice {
  final String content;
  final int includedBytes;
  final bool truncated;

  const _LogSlice({
    required this.content,
    required this.includedBytes,
    required this.truncated,
  });
}
