// QQ 音乐搜索 - 测试不同请求变体
// 运行: dart run scripts/test_qq_raw3.dart

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

  print('=== QQ 音乐搜索变体测试 ===\n');

  // Test 1: 标准请求 (已知返回空)
  await testVariant(dio, '标准请求', {
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
  });

  // Test 2: 使用 ct=19, cv=1845 (另一个常见配置)
  await testVariant(dio, 'ct=19 cv=1845', {
    'comm': {'ct': 19, 'cv': 1845},
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
  });

  // Test 3: ct=24, cv=12080008 (qqmusic desktop)
  await testVariant(dio, 'ct=24 cv=12080008', {
    'comm': {'ct': 24, 'cv': 12080008},
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
  });

  // Test 4: 不同的 User-Agent (模拟 QQ 音乐桌面客户端)
  print('--- 模拟桌面客户端 UA ---');
  try {
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
        headers: {
          'User-Agent': 'QQMusic/11.0 (Windows NT 10.0; Win64; x64)',
        },
      ),
    );
    final data = res.data is String ? jsonDecode(res.data as String) : res.data;
    final list = (data as Map)['req_0']?['data']?['body']?['song']?['list'] as List?;
    print('  list.length: ${list?.length ?? "null"}');
    if (list != null && list.isNotEmpty) {
      print('  第一首: ${list.first['name']}');
    }
  } catch (e) {
    print('  ❌ ${e.toString().split('\n').first}');
  }

  // Test 5: 使用不同的 API 路径 - /cgi-bin/musicu.fcg 不带 https
  await testVariant(dio, '带 cookie', {
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
  }, cookie: 'qm_keyst=; qqmusic_key=');

  // Test 6: 使用 search_type=0 + grp=1 + remoteplace
  await testVariant(dio, 'grp+remoteplace', {
    'comm': {'ct': 24, 'cv': 0},
    'req_0': {
      'method': 'DoSearchForQQMusicDesktop',
      'module': 'music.search.SearchCgiService',
      'param': {
        'query': '周杰伦',
        'num_per_page': 5,
        'page_num': 1,
        'search_type': 0,
        'grp': 1,
        'remoteplace': 'txt.yqq.song',
      },
    },
  });

  // Test 7: 不带 comm 字段
  await testVariant(dio, '无 comm 字段', {
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
  });

  // Test 8: 使用不同的 module - 测试其他搜索模块
  await testVariant(dio, 'SearchCgiService 不带 method', {
    'comm': {'ct': 24, 'cv': 0},
    'req_0': {
      'module': 'music.search.SearchCgiService',
      'param': {
        'query': '周杰伦',
        'num_per_page': 5,
        'page_num': 1,
        'search_type': 0,
      },
    },
  });

  print('\n=== 诊断完成 ===');
}

Future<void> testVariant(Dio dio, String label, Map<String, dynamic> body, {String? cookie}) async {
  print('--- $label ---');
  try {
    final options = Options(
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
    );
    if (cookie != null) {
      options.headers = {'cookie': cookie};
    }
    final res = await dio.post(
      'https://u.y.qq.com/cgi-bin/musicu.fcg',
      data: body,
      options: options,
    );
    final data = res.data is String ? jsonDecode(res.data as String) : res.data;

    final req0 = (data as Map)['req_0'];
    final list = req0?['data']?['body']?['song']?['list'] as List?;
    final meta = req0?['data']?['meta'];
    final sum = meta?['sum'] ?? 0;
    final estimate = meta?['estimate_sum'] ?? 0;
    print('  list.length: ${list?.length ?? "null"}, sum=$sum, estimate_sum=$estimate');
    if (list != null && list.isNotEmpty) {
      print('  第一首: ${list.first['name']} - ${(list.first['singer'] as List?)?.map((s) => s['name']).join(',')}');
    }
  } catch (e) {
    print('  ❌ ${e.toString().split('\n').first}');
  }
  print('');
}
