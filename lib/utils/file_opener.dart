import 'package:flutter/services.dart';

import '../core/diagnostics/diagnostics_service.dart';

/// Failure to hand a path to the operating system's file manager / viewer.
///
/// One exception type on purpose: every call site does
/// `catch (e) { showErrorSnackBar(context, e.toString()); }`, so the message
/// carried here must already be the sentence worth showing. Before this,
/// a raw `PlatformException(...)` leaked into the snackbar on Android and a
/// bare `MissingPluginException` ("No implementation found for method...")
/// leaked on every platform whose runner has no handler.
class FileOpenerException implements Exception {
  const FileOpenerException(this.message, {this.unsupported = false});

  /// The user-facing sentence. This file is a hard-coded Chinese copy zone,
  /// exactly like its callers (`download_page.dart`).
  final String message;

  /// True when the platform has no native implementation at all (a Linux dev
  /// run, a unit test) rather than "the request itself failed". Lets a caller
  /// degrade quietly instead of showing an error for a feature that cannot
  /// exist here.
  final bool unsupported;

  @override
  String toString() => message;
}

/// Opens files and folders with the platform's own handler.
///
/// Channels: `com.mconnect.mconnect/file_opener` (Android `MainActivity`, and
/// on Windows `windows/runner/desktop/file_opener_channel.cpp`). Both answer
/// `true` on success and an error code otherwise; the Windows runner also
/// validates the path before calling `ShellExecuteW`.
class FileOpener {
  static const _channel = MethodChannel('com.mconnect.mconnect/file_opener');

  static Future<void> openFile(String filePath) =>
      _invoke('openFile', filePath, target: '文件');

  static Future<void> openFolder(String folderPath) =>
      _invoke('openFolder', folderPath, target: '文件夹');

  static Future<void> _invoke(
    String method,
    String path, {
    required String target,
  }) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      throw FileOpenerException('没有可打开的$target路径');
    }

    final Object? handled;
    try {
      handled = await _channel.invokeMethod<Object?>(method, trimmed);
    } on MissingPluginException {
      DiagnosticsService.instance.record(
        'desktop',
        'file_opener_unavailable',
        data: {'method': method},
      );
      throw FileOpenerException('当前平台没有实现打开$target的原生接口', unsupported: true);
    } on PlatformException catch (error) {
      final message = error.message?.trim() ?? '';
      DiagnosticsService.instance.record(
        'desktop',
        'file_opener_failed',
        data: {'method': method, 'code': error.code, 'message': message},
      );
      throw FileOpenerException(
        message.isEmpty ? '无法打开$target（${error.code}）' : message,
      );
    }

    // Android and the Windows runner both answer `true`. A `null` reply is a
    // native side that chose not to return a value, which is not a failure;
    // only an explicit `false` is.
    if (handled == false) {
      throw FileOpenerException('无法打开$target，系统没有接受这个路径');
    }
  }
}
