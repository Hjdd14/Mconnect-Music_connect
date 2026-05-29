import 'dart:convert';
import 'package:dio/dio.dart';

/// Mimics exactly what NeteaseApi and NeteasePlatform do
void main() async {
  final dio = Dio(BaseOptions(
    baseUrl: 'https://music.163.com',
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Chrome/91.0.4472.164 NeteaseMusicDesktop/2.10.2.200154',
      'Referer': 'https://music.163.com/',
      'Origin': 'https://music.163.com',
      'Cookie': 'os=pc; appver=2.10.2.200154',
    },
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
  ));

  // === Search exactly like NeteaseApi.search() ===
  print('=== Search ===');
  final searchRes = await dio.get(
    '/api/cloudsearch/pc',
    queryParameters: {'s': '周杰伦 晴天', 'type': 1, 'limit': 5, 'offset': 0},
  );
  final searchData = searchRes.data is String ? jsonDecode(searchRes.data) : searchRes.data;
  final songs = searchData['result']?['songs'] as List?;
  if (songs == null || songs.isEmpty) {
    print('No songs found!');
    return;
  }

  for (var i = 0; i < songs.length && i < 3; i++) {
    final s = songs[i];
    print('\n--- Song ${i + 1} ---');
    print('id: ${s['id']}');
    print('name: ${s['name']}');
    print('dt (duration ms): ${s['dt']}');
    print('ar (artists): ${s['ar']}');
    print('al (album): ${s['al']}');
    print('al.picUrl: ${s['al']?['picUrl']}');

    // Parse exactly like NeteasePlatform._parseSong()
    final songId = s['id'].toString();
    final durationMs = s['dt'] ?? 0;
    final coverUrl = s['al']?['picUrl'];
    print('Parsed duration: ${Duration(milliseconds: durationMs)}');
    print('Parsed coverUrl: $coverUrl');

    // === Get song URL exactly like NeteaseApi.getSongUrl() ===
    print('\n--- Get URL for $songId ---');
    final urlRes = await dio.post(
      '/api/song/enhance/player/url/v1',
      data: {
        'ids': jsonEncode([songId]),
        'level': 'exhigh',
        'encodeType': '',
        'csrf': '',
      },
      options: Options(contentType: 'application/x-www-form-urlencoded'),
    );
    final urlData = urlRes.data is String ? jsonDecode(urlRes.data) : urlRes.data;
    print('Response code: ${urlData['code']}');
    final urlList = urlData['data'] as List?;
    if (urlList != null && urlList.isNotEmpty) {
      final item = urlList[0];
      print('url: ${item['url']}');
      print('size: ${item['size']}');
      print('level: ${item['level']}');
      print('br: ${item['br']}');
      print('type: ${item['type']}');
      print('freeTrialInfo: ${item['freeTrialInfo']}');

      // Check if URL is null (VIP only)
      if (item['url'] == null) {
        print('WARNING: URL is null - likely VIP only!');
        print('full item: ${jsonEncode(item)}');
      }
    } else {
      print('ERROR: No data array!');
      print('full response: ${jsonEncode(urlData)}');
    }

    // === Get lyrics ===
    print('\n--- Get Lyrics for $songId ---');
    final lyricRes = await dio.get(
      '/api/song/lyric',
      queryParameters: {'id': songId, 'lv': -1, 'tv': -1},
    );
    final lyricData = lyricRes.data is String ? jsonDecode(lyricRes.data) : lyricRes.data;
    final lrc = lyricData['lrc']?['lyric'] as String?;
    print('Lyrics: ${lrc != null ? "${lrc.length} chars" : "null"}');
    if (lrc != null && lrc.isNotEmpty) {
      print('First 200: ${lrc.substring(0, lrc.length > 200 ? 200 : lrc.length)}');
    }
  }

  print('\n=== DONE ===');
}
