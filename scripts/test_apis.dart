// API 可用性测试脚本
// 运行方式: dart run scripts/test_apis.dart

import 'dart:convert';
import 'package:dio/dio.dart';

void main() async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    },
  ));

  print('=== Mconnect API 可用性测试 ===\n');

  await testNetease(dio);
  await testQqMusic(dio);
  await testKugou(dio);

  print('\n=== 测试完成 ===');
}

Future<void> testNetease(Dio dio) async {
  print('--- 网易云音乐 ---');

  // 搜索 (GET /api/cloudsearch/pc, 无加密)
  await _testEndpoint(dio, '搜索', () async {
    final res = await dio.get(
      'https://music.163.com/api/cloudsearch/pc',
      queryParameters: {'s': '周杰伦', 'type': 1, 'limit': 5, 'offset': 0},
      options: Options(headers: {
        'Referer': 'https://music.163.com/',
        'Cookie': 'os=pc; appver=2.10.2.200154',
      }),
    );
    final data = _parse(res.data);
    final songs = data['result']?['songs'] as List?;
    final count = data['result']?['songCount'] ?? 0;
    print('    找到 $count 首歌曲, 列表: ${songs?.length ?? 0}');
    if (songs != null && songs.isNotEmpty) {
      print('    第一首: ${songs.first['name']} - ${(songs.first['ar'] as List?)?.map((a) => a['name']).join(',')}');
    }
    return res.statusCode;
  });

  // 歌词 (GET /api/song/lyric)
  await _testEndpoint(dio, '歌词', () async {
    final res = await dio.get(
      'https://music.163.com/api/song/lyric',
      queryParameters: {'id': '186016', 'lv': -1, 'tv': -1},
      options: Options(headers: {'Cookie': 'os=pc; appver=2.10.2.200154'}),
    );
    final data = _parse(res.data);
    final hasLrc = data['lrc']?['lyric'] != null;
    print('    歌词: ${hasLrc ? "有" : "无"}');
    return res.statusCode;
  });

  // 推荐 (GET /api/v3/discovery/recommend/songs)
  await _testEndpoint(dio, '每日推荐', () async {
    final res = await dio.get(
      'https://music.163.com/api/v3/discovery/recommend/songs',
      options: Options(headers: {'Cookie': 'os=pc; appver=2.10.2.200154'}),
    );
    final data = _parse(res.data);
    final songs = data['data']?['dailySongs'] as List?;
    print('    推荐: ${songs?.length ?? 0} 首');
    return res.statusCode;
  });

  print('');
}

Future<void> testQqMusic(Dio dio) async {
  print('--- QQ音乐 ---');

  // 搜索 (POST musicu.fcg, JSON body, req_0 key)
  await _testEndpoint(dio, '搜索', () async {
    final res = await dio.post(
      'https://u.y.qq.com/cgi-bin/musicu.fcg',
      data: {
        'comm': {'ct': 19, 'cv': 1845},
        'req_0': {
          'method': 'DoSearchForQQMusicDesktop',
          'module': 'music.search.SearchCgiService',
          'param': {
            'num_per_page': 5,
            'page_num': 1,
            'query': '周杰伦',
            'search_type': 0,
          },
        },
      },
      options: Options(
        contentType: Headers.jsonContentType,
        headers: {
          'Referer': 'https://y.qq.com/portal/player.html',
          'Origin': 'https://y.qq.com',
        },
      ),
    );
    final data = _parse(res.data);
    final searchData = data['req_0'];
    final body = searchData?['data']?['body']?['song']?['list'] as List?;
    final count = body?.length ?? 0;
    final estimate = searchData?['data']?['meta']?['estimate_sum'] ?? 0;
    print('    找到 $count 首歌曲 (估计: $estimate)');
    if (body != null && body.isNotEmpty) {
      print('    第一首: ${body.first['name']} - ${(body.first['singer'] as List?)?.map((a) => a['name']).join(',')}');
    }
    return res.statusCode;
  });

  print('');
}

Future<void> testKugou(Dio dio) async {
  print('--- 酷狗音乐 ---');

  // 搜索 (GET)
  await _testEndpoint(dio, '搜索', () async {
    final res = await dio.get(
      'http://mobilecdn.kugou.com/api/v3/search/song',
      queryParameters: {
        'format': 'json',
        'keyword': '周杰伦',
        'page': 1,
        'pagesize': 5,
        'showtype': 1,
      },
    );
    final data = _parse(res.data);
    final total = data['data']?['total'] ?? 0;
    print('    找到 $total 首歌曲');
    return res.statusCode;
  });

  // 歌词搜索 (GET)
  await _testEndpoint(dio, '歌词搜索', () async {
    final res = await dio.get(
      'http://lyrics.kugou.com/search',
      queryParameters: {
        'ver': 1,
        'man': 'yes',
        'client': 'pc',
        'keyword': '周杰伦-晴天',
        'duration': 269000,
        'hash': '',
      },
    );
    final data = _parse(res.data);
    final candidates = data['candidates']?.length ?? 0;
    print('    找到 $candidates 个歌词候选');
    return res.statusCode;
  });

  print('');
}

dynamic _parse(dynamic data) {
  if (data is Map) return data;
  if (data is String) {
    try {
      return jsonDecode(data);
    } catch (_) {
      return {};
    }
  }
  return {};
}

Future<void> _testEndpoint(
  Dio dio,
  String name,
  Future<int?> Function() test,
) async {
  try {
    final start = DateTime.now();
    final statusCode = await test();
    final elapsed = DateTime.now().difference(start).inMilliseconds;
    final status = statusCode != null && statusCode >= 200 && statusCode < 400
        ? '✅'
        : '⚠️';
    print('  $status $name - HTTP $statusCode (${elapsed}ms)');
  } catch (e) {
    print('  ❌ $name - ${e.toString().split('\n').first}');
  }
}
