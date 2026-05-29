import 'dart:convert';
import 'package:dio/dio.dart';

void main() async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {'User-Agent': 'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36'},
  ));

  final hash = 'b3a52a7a958bf0aed0ebfba2e9a818b7'; // 晴天

  // Test getSongInfo
  final res = await dio.get(
    'http://m.kugou.com/app/i/getSongInfo.php',
    queryParameters: {'cmd': 'playInfo', 'hash': hash},
  );
  final data = res.data is String ? jsonDecode(res.data as String) : res.data;
  final map = data as Map;

  // Print all top-level keys and their values (skip long ones)
  for (final e in map.entries) {
    final v = e.value;
    if (v is String && v.length > 80) {
      print('${e.key}: (${v.length} chars) ${v.substring(0, 80)}...');
    } else if (v is Map) {
      print('${e.key}: {${v.keys.join(', ')}}');
    } else {
      print('${e.key}: $v');
    }
  }
}
