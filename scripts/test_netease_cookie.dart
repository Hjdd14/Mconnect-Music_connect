import 'dart:convert';
import 'package:dio/dio.dart';

/// Test Netease API with different cookie/header configurations
/// to find what causes the Android vs CLI difference
void main() async {
  // Test 1: Minimal headers (like a fresh Android app)
  print('=== Test 1: Minimal headers (no cookie) ===');
  await testConfig('Minimal', {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36',
  });

  // Test 2: Desktop headers (like the app currently uses)
  print('\n=== Test 2: Desktop headers with default cookie ===');
  await testConfig('Desktop', {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Chrome/91.0.4472.164 NeteaseMusicDesktop/2.10.2.200154',
    'Referer': 'https://music.163.com/',
    'Origin': 'https://music.163.com',
    'Cookie': 'os=pc; appver=2.10.2.200154',
  });

  // Test 3: Android User-Agent
  print('\n=== Test 3: Android User-Agent ===');
  await testConfig('Android', {
    'User-Agent': 'NeteaseMusic/2.10.2.200154 (Android; Pixel 5)',
    'Referer': 'https://music.163.com/',
    'Origin': 'https://music.163.com',
    'Cookie': 'os=android; appver=2.10.2.200154',
  });

  // Test 4: No Origin/Referer
  print('\n=== Test 4: No Origin/Referer ===');
  await testConfig('NoOrigin', {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36',
    'Cookie': 'os=pc; appver=2.10.2.200154',
  });

  // Test 5: With csrf token
  print('\n=== Test 5: With csrf token ===');
  await testConfig('WithCsrf', {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Chrome/91.0.4472.164 NeteaseMusicDesktop/2.10.2.200154',
    'Referer': 'https://music.163.com/',
    'Origin': 'https://music.163.com',
    'Cookie': 'os=pc; appver=2.10.2.200154; __csrf=test',
  });

  // Test 6: POST with JSON content-type instead of form-urlencoded
  print('\n=== Test 6: POST with JSON content-type ===');
  try {
    final dio = Dio(BaseOptions(
      baseUrl: 'https://music.163.com',
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36',
        'Referer': 'https://music.163.com/',
        'Origin': 'https://music.163.com',
        'Cookie': 'os=pc; appver=2.10.2.200154',
      },
    ));
    final searchRes = await dio.get('/api/cloudsearch/pc', queryParameters: {'s': '周杰伦', 'type': 1, 'limit': 1, 'offset': 0});
    final searchData = searchRes.data is String ? jsonDecode(searchRes.data) : searchRes.data;
    final songId = (searchData['result']?['songs'] as List?)?.first['id'];

    final res = await dio.post(
      '/api/song/enhance/player/url/v1',
      data: {'ids': jsonEncode([songId]), 'level': 'exhigh', 'encodeType': '', 'csrf': ''},
      options: Options(contentType: 'application/json'),
    );
    final data = res.data is String ? jsonDecode(res.data) : res.data;
    final item = (data['data'] as List?)?.first;
    print('JSON content-type: url=${item?['url'] != null ? "OK" : "NULL"}');
    if (item?['url'] != null) {
      print('  URL: ${(item['url'] as String).substring(0, 80)}...');
    }
  } catch (e) {
    print('JSON content-type error: $e');
  }

  print('\n=== DONE ===');
}

Future<void> testConfig(String name, Map<String, String> headers) async {
  try {
    final dio = Dio(BaseOptions(
      baseUrl: 'https://music.163.com',
      headers: headers,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ));

    // Search
    final searchRes = await dio.get('/api/cloudsearch/pc', queryParameters: {'s': '周杰伦 晴天', 'type': 1, 'limit': 1, 'offset': 0});
    final searchData = searchRes.data is String ? jsonDecode(searchRes.data) : searchRes.data;
    final songs = searchData['result']?['songs'] as List?;
    if (songs == null || songs.isEmpty) {
      print('[$name] Search: NO RESULTS');
      return;
    }
    final songId = songs[0]['id'].toString();
    final songName = songs[0]['name'];
    final dt = songs[0]['dt'];
    final coverUrl = songs[0]['al']?['picUrl'];
    print('[$name] Search OK: $songName (id=$songId, dt=${dt}ms, cover=${coverUrl != null ? "YES" : "NO"})');

    // Get URL
    final urlRes = await dio.post(
      '/api/song/enhance/player/url/v1',
      data: {'ids': jsonEncode([songId]), 'level': 'exhigh', 'encodeType': '', 'csrf': ''},
      options: Options(contentType: 'application/x-www-form-urlencoded'),
    );
    final urlData = urlRes.data is String ? jsonDecode(urlRes.data) : urlRes.data;
    final urlItem = (urlData['data'] as List?)?.first;
    final url = urlItem?['url'] as String?;
    print('[$name] URL: ${url != null ? "OK (${urlItem?['level']}, ${urlItem?['br']}bps)" : "NULL - ${jsonEncode(urlItem)}"}');

    // Get Lyrics
    final lyricRes = await dio.get('/api/song/lyric', queryParameters: {'id': songId, 'lv': -1, 'tv': -1});
    final lyricData = lyricRes.data is String ? jsonDecode(lyricRes.data) : lyricRes.data;
    final lrc = lyricData['lrc']?['lyric'] as String?;
    print('[$name] Lyrics: ${lrc != null ? "OK (${lrc.length} chars)" : "NULL"}');
  } catch (e) {
    print('[$name] ERROR: $e');
  }
}
