import 'dart:convert';
import 'package:dio/dio.dart';

void main() async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36',
    },
  ));

  // Use a known hash from search
  final hash = 'b3a52a7a958bf0aed0ebfba2e9a818b7';
  print('=== getSongInfo for hash: $hash ===\n');

  try {
    final res = await dio.get(
      'http://m.kugou.com/app/i/getSongInfo.php',
      queryParameters: {
        'cmd': 'playInfo',
        'hash': hash,
      },
    );
    final data = res.data is String ? jsonDecode(res.data as String) : res.data;
    final map = data as Map;
    print('顶层 keys: ${map.keys.toList()}');

    final songData = map['data'];
    if (songData is Map) {
      print('\ndata keys: ${songData.keys.toList()}');
      print('imgUrl: ${songData['imgUrl']}');
      print('lyrics: ${songData['lyrics']?.toString().substring(0, 200)}');
      print('url: ${songData['url']}');
      print('play_url: ${songData['play_url']}');
    } else {
      print('data: $songData');
    }

    // Also try with filename parameter
    print('\n=== 带 filename 的 getSongInfo ===');
    final res2 = await dio.get(
      'http://m.kugou.com/app/i/getSongInfo.php',
      queryParameters: {
        'cmd': 'playInfo',
        'hash': hash,
        'filename': '周杰伦 - 晴天',
      },
    );
    final data2 = res2.data is String ? jsonDecode(res2.data as String) : res2.data;
    final songData2 = (data2 as Map)['data'];
    if (songData2 is Map) {
      print('imgUrl: ${songData2['imgUrl']}');
      print('play_url: ${songData2['play_url']}');
    }
  } catch (e) {
    print('Error: $e');
  }
}
