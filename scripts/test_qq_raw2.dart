// QQ 音乐搜索 - 深度诊断响应结构
// 运行: dart run scripts/test_qq_raw2.dart

import 'dart:convert';
import 'package:dio/dio.dart';

void main() async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
      'Referer': 'https://y.qq.com/',
      'Origin': 'https://y.qq.com',
    },
  ));

  print('=== QQ 音乐搜索深度诊断 ===\n');

  // 使用与参考项目完全一致的请求
  final res = await dio.post(
    'https://u.y.qq.com/cgi-bin/musicu.fcg',
    data: {
      'comm': {'ct': 24, 'cv': 0},
      'req_0': {
        'method': 'DoSearchForQQMusicDesktop',
        'module': 'music.search.SearchCgiService',
        'param': {
          'query': '周杰伦',
          'num_per_page': 5,
          'page_num': 1,
          'search_type': 0,
        },
      },
    },
    options: Options(
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
    ),
  );

  final data = res.data is String ? jsonDecode(res.data as String) : res.data;

  print('顶层 keys: ${(data as Map).keys.toList()}');
  print('code: ${data['code']}');

  final req0 = data['req_0'];
  if (req0 == null) {
    print('req_0 为 null!');
    return;
  }

  print('\nreq_0 keys: ${(req0 as Map).keys.toList()}');

  final reqData = req0['data'];
  if (reqData == null) {
    print('req_0.data 为 null!');
    return;
  }

  print('req_0.data keys: ${(reqData as Map).keys.toList()}');

  final body = reqData['body'];
  if (body == null) {
    print('req_0.data.body 为 null!');
    return;
  }

  print('body keys: ${(body as Map).keys.toList()}');

  final song = body['song'];
  if (song == null) {
    print('body.song 为 null!');
    // Check for other possible keys
    print('body 内容: ${jsonEncode(body).substring(0, 500)}');
    return;
  }

  print('song keys: ${(song as Map).keys.toList()}');

  final list = song['list'];
  print('song.list type: ${list.runtimeType}');
  if (list is List) {
    print('song.list length: ${list.length}');
    if (list.isNotEmpty) {
      print('第一首: ${jsonEncode(list.first).substring(0, 200)}');
    }
  } else {
    print('song.list: $list');
  }

  final meta = reqData['meta'];
  print('\nmeta: ${jsonEncode(meta).substring(0, 300)}');

  // Also dump the full req_0.data to see everything
  print('\n--- 完整 req_0.data (前1000字符) ---');
  print(jsonEncode(reqData).substring(0, 1000));
}
