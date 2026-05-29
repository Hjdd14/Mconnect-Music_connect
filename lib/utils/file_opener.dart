import 'package:flutter/services.dart';

class FileOpener {
  static const _channel = MethodChannel('com.mconnect.mconnect/file_opener');

  static Future<void> openFile(String filePath) async {
    try {
      await _channel.invokeMethod('openFile', filePath);
    } on PlatformException catch (e) {
      throw Exception('无法打开文件: ${e.message}');
    }
  }

  static Future<void> openFolder(String folderPath) async {
    try {
      await _channel.invokeMethod('openFolder', folderPath);
    } on PlatformException catch (e) {
      throw Exception('无法打开文件夹: ${e.message}');
    }
  }
}
