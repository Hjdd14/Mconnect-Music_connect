import 'dart:convert';
import 'package:dio/dio.dart';

dynamic parseResponse(dynamic data) {
  if (data is Map) return data;
  if (data is String) {
    try {
      return jsonDecode(data);
    } catch (_) {
      return {'_raw': data};
    }
  }
  return {'_null': true};
}

void main() async {
  final dio = Dio(BaseOptions(
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Chrome/91.0.4472.164 NeteaseMusicDesktop/2.10.2.200154',
      'Referer': 'https://music.163.com/',
      'Origin': 'https://music.163.com',
      'Cookie': 'os=pc; appver=2.10.2.200154',
    },
  ));

  // Test search (GET, no encryption)
  print('=== Search (GET /api/cloudsearch/pc) ===');
  try {
    final res = await dio.get(
      'https://music.163.com/api/cloudsearch/pc',
      queryParameters: {'s': '周杰伦', 'type': 1, 'limit': 3, 'offset': 0},
    );
    final data = parseResponse(res.data);
    if (data['_raw'] != null) {
      print('  Raw string: ${(data['_raw'] as String).substring(0, (data['_raw'] as String).length.clamp(0, 200))}');
    } else {
      final songs = data['result']?['songs'] as List?;
      final songCount = data['result']?['songCount'] ?? 0;
      print('  Found $songCount songs, list: ${songs?.length ?? 0}');
      if (songs != null && songs.isNotEmpty) {
        print('  First: ${songs.first['name']} - ${(songs.first['ar'] as List).map((a) => a['name']).join(',')}');
      }
    }
  } catch (e) {
    print('  Error: $e');
  }

  // Test lyrics (GET, no encryption)
  print('\n=== Lyrics (GET /api/song/lyric) ===');
  try {
    final res = await dio.get(
      'https://music.163.com/api/song/lyric',
      queryParameters: {'id': '186016', 'lv': -1, 'tv': -1},
    );
    final data = parseResponse(res.data);
    if (data['_raw'] != null) {
      print('  Raw: ${(data['_raw'] as String).substring(0, (data['_raw'] as String).length.clamp(0, 200))}');
    } else {
      final hasLrc = data['lrc']?['lyric'] != null;
      print('  Has lyrics: $hasLrc');
      if (hasLrc) {
        final lrc = data['lrc']['lyric'] as String;
        print('  Lyrics: ${lrc.substring(0, lrc.length.clamp(0, 100))}');
      }
    }
  } catch (e) {
    print('  Error: $e');
  }

  // Test QR login key (POST with /api/, type=3)
  print('\n=== QR key (POST /api/login/qrcode/unikey) ===');
  try {
    final res = await dio.post(
      'https://music.163.com/api/login/qrcode/unikey',
      data: 'type=3',
      options: Options(contentType: 'application/x-www-form-urlencoded'),
    );
    final data = parseResponse(res.data);
    print('  code: ${data['code']}');
    print('  data: ${data['data']}');
  } catch (e) {
    print('  Error: $e');
  }

  // Test QR login key (GET)
  print('\n=== QR key (GET /api/login/qrcode/unikey) ===');
  try {
    final res = await dio.get(
      'https://music.163.com/api/login/qrcode/unikey',
      queryParameters: {'type': 3},
    );
    final data = parseResponse(res.data);
    print('  code: ${data['code']}');
    print('  data: ${data['data']}');
  } catch (e) {
    print('  Error: $e');
  }

  // Test recommend songs (GET, no encryption)
  print('\n=== Recommend (GET /api/v3/discovery/recommend/songs) ===');
  try {
    final res = await dio.get(
      'https://music.163.com/api/v3/discovery/recommend/songs',
    );
    final data = parseResponse(res.data);
    if (data['_raw'] != null) {
      print('  Raw: ${(data['_raw'] as String).substring(0, (data['_raw'] as String).length.clamp(0, 200))}');
    } else {
      final songs = data['data']?['dailySongs'] as List?;
      print('  Found ${songs?.length ?? 0} daily songs');
    }
  } catch (e) {
    print('  Error: $e');
  }
}
