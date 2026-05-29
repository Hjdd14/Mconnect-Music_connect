// QQ 音乐搜索原始响应诊断
// 运行: dart run scripts/test_qq_raw.dart

import 'dart:convert';
import 'package:dio/dio.dart';

void main() async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      'Referer': 'https://y.qq.com/portal/player.html',
      'Origin': 'https://y.qq.com',
    },
  ));

  print('=== QQ 音乐搜索原始响应 ===\n');

  // Test 1: 标准搜索
  await testSearch(dio, '标准请求', {
    'comm': {'ct': 24, 'cv': 0},
    'req': {
      'method': 'DoSearchForQQMusicDesktop',
      'module': 'music.search.SearchCgiService',
      'param': {
        'num_per_page': 5,
        'page_num': 1,
        'query': '周杰伦',
        'search_type': 0,
      },
    },
  });

  // Test 2: 带 grp 参数
  await testSearch(dio, '带 grp=1', {
    'comm': {'ct': 24, 'cv': 0},
    'req': {
      'method': 'DoSearchForQQMusicDesktop',
      'module': 'music.search.SearchCgiService',
      'param': {
        'num_per_page': 5,
        'page_num': 1,
        'query': '周杰伦',
        'search_type': 0,
        'grp': 1,
      },
    },
  });

  // Test 3: 使用 remoteplace 参数
  await testSearch(dio, '带 remoteplace', {
    'comm': {'ct': 24, 'cv': 0},
    'req': {
      'method': 'DoSearchForQQMusicDesktop',
      'module': 'music.search.SearchCgiService',
      'param': {
        'num_per_page': 5,
        'page_num': 1,
        'query': '周杰伦',
        'search_type': 0,
        'remoteplace': 'txt.yqq.song',
      },
    },
  });

  // Test 4: 不同的 module 名
  await testSearch(dio, '使用 musicu.fcg + req_1', {
    'comm': {'ct': 24, 'cv': 0},
    'req_1': {
      'method': 'DoSearchForQQMusicDesktop',
      'module': 'music.search.SearchCgiService',
      'param': {
        'num_per_page': 5,
        'page_num': 1,
        'query': '周杰伦',
        'search_type': 0,
      },
    },
  });

  // Test 5: 直接用 music.search.SearchC2S
  await testSearch(dio, 'SearchC2S module', {
    'comm': {'ct': 24, 'cv': 0},
    'req': {
      'method': 'SearchForQQMusicDesktop',
      'module': 'music.search.SearchC2S',
      'param': {
        'num_per_page': 5,
        'page_num': 1,
        'query': '周杰伦',
        'search_type': 0,
      },
    },
  });

  // Test 6: 不同的 search_type
  await testSearch(dio, 'search_type=1 (singer)', {
    'comm': {'ct': 24, 'cv': 0},
    'req': {
      'method': 'DoSearchForQQMusicDesktop',
      'module': 'music.search.SearchCgiService',
      'param': {
        'num_per_page': 5,
        'page_num': 1,
        'query': '周杰伦',
        'search_type': 1,
      },
    },
  });

  print('\n=== 诊断完成 ===');
}

Future<void> testSearch(Dio dio, String label, Map<String, dynamic> body) async {
  print('--- $label ---');
  try {
    final res = await dio.post(
      'https://u.y.qq.com/cgi-bin/musicu.fcg',
      data: body,
      options: Options(
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
      ),
    );
    final data = res.data is String ? jsonDecode(res.data as String) : res.data;

    // Try different response keys
    final keys = ['req', 'req_1', 'music.search.SearchCgiService', 'music.search.SearchC2S'];
    for (final key in keys) {
      if (data is Map && data[key] != null) {
        final searchData = data[key];
        final bodyList = searchData?['data']?['body']?['song']?['list'] as List?;
        final meta = searchData?['data']?['meta'];
        print('  key=$key: body.list=${bodyList?.length ?? "null"}, meta=$meta');
        if (bodyList != null && bodyList.isNotEmpty) {
          print('    第一首: ${bodyList.first['name']}');
        }
      }
    }

    // Also print top-level keys
    if (data is Map) {
      print('  响应顶层 keys: ${data.keys.toList()}');
    }
  } catch (e) {
    print('  ❌ ${e.toString().split('\n').first}');
  }
  print('');
}
