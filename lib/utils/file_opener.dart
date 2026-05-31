import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/platform/platform_utils.dart';

typedef WindowsFileLauncher =
    Future<ProcessResult> Function(String executable, List<String> arguments);

class FileOpener {
  static const _channel = MethodChannel('com.mconnect.mconnect/file_opener');
  static WindowsFileLauncher _windowsLauncher = _defaultWindowsLauncher;

  static Future<void> openFile(String filePath) async {
    try {
      if (PlatformUtils.isWindows) {
        await _runWindowsLauncher('cmd', ['/c', 'start', '', filePath]);
        return;
      }
      await _channel.invokeMethod('openFile', filePath);
    } on PlatformException catch (e) {
      throw Exception('无法打开文件: ${e.message}');
    }
  }

  static Future<void> openFolder(String folderPath) async {
    try {
      if (PlatformUtils.isWindows) {
        await _runWindowsLauncher('explorer.exe', [folderPath]);
        return;
      }
      await _channel.invokeMethod('openFolder', folderPath);
    } on PlatformException catch (e) {
      throw Exception('无法打开文件夹: ${e.message}');
    }
  }

  @visibleForTesting
  static void setWindowsLauncherForTest(WindowsFileLauncher launcher) {
    _windowsLauncher = launcher;
  }

  @visibleForTesting
  static void resetWindowsLauncherForTest() {
    _windowsLauncher = _defaultWindowsLauncher;
  }

  static Future<void> _runWindowsLauncher(
    String executable,
    List<String> arguments,
  ) async {
    final result = await _windowsLauncher(executable, arguments);
    if (result.exitCode != 0) {
      throw Exception(
        '无法打开文件路径: $executable ${arguments.join(' ')} '
        '(exitCode=${result.exitCode})',
      );
    }
  }

  static Future<ProcessResult> _defaultWindowsLauncher(
    String executable,
    List<String> arguments,
  ) {
    return Process.run(executable, arguments, runInShell: true);
  }
}
