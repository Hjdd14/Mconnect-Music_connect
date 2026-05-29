import 'dart:convert';
import 'package:dio/dio.dart';

void main() async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      'Referer': 'https://y.qq.com/portal/player.html',
      'Origin': 'https://y.qq.com',
    },
  ));

  // Search for a song first
  final searchRes = await dio.post(
    'https://u.y.qq.com/cgi-bin/musicu.fcg',
    data: {
      'comm': {'ct': 19, 'cv': 1845},
      'req_0': {
        'method': 'DoSearchForQQMusicDesktop',
        'module': 'music.search.SearchCgiService',
        'param': {'num_per_page': 1, 'page_num': 1, 'query': '周杰伦 晴天', 'search_type': 0},
      },
    },
    options: Options(contentType: Headers.jsonContentType, responseType: ResponseType.json),
  );
  final searchData = searchRes.data is String ? jsonDecode(searchRes.data) : searchRes.data;
  final songs = searchData['req_0']?['data']?['body']?['song']?['list'] as List?;
  if (songs == null || songs.isEmpty) {
    print('No songs found');
    return;
  }
  final songMid = songs[0]['mid'];
  final songName = songs[0]['name'];
  print('Song: $songName, mid: $songMid');

  // Try different lyrics endpoints
  print('\n=== Test 1: i.y.qq.com (original) ===');
  try {
    final res = await dio.get(
      'https://i.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg',
      queryParameters: {'songmid': songMid, 'format': 'json', 'nobase64': 1},
    );
    final data = res.data;
    if (data is Map && data['lyric'] != null) {
      final lrc = data['lyric'] as String;
      print('SUCCESS: ${lrc.length} chars');
      print('First 200: ${lrc.substring(0, lrc.length > 200 ? 200 : lrc.length)}');
    } else {
      print('FAIL: no lyric field');
      print('Response type: ${data.runtimeType}');
      if (data is String) {
        print('Response (first 300): ${data.substring(0, data.length > 300 ? 300 : data.length)}');
      } else {
        print('Response keys: ${data is Map ? data.keys.toList() : 'N/A'}');
      }
    }
  } catch (e) {
    print('Error: $e');
  }

  print('\n=== Test 2: c.y.qq.com (alternative) ===');
  try {
    final res = await dio.get(
      'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg',
      queryParameters: {'songmid': songMid, 'format': 'json', 'nobase64': 1},
    );
    final data = res.data;
    if (data is Map && data['lyric'] != null) {
      final lrc = data['lyric'] as String;
      print('SUCCESS: ${lrc.length} chars');
      print('First 200: ${lrc.substring(0, lrc.length > 200 ? 200 : lrc.length)}');
    } else {
      print('FAIL: no lyric field');
      if (data is String) {
        print('Response (first 300): ${data.substring(0, data.length > 300 ? 300 : data.length)}');
      }
    }
  } catch (e) {
    print('Error: $e');
  }

  print('\n=== Test 3: musicu.fcg lyrics module ===');
  try {
    final res = await dio.post(
      'https://u.y.qq.com/cgi-bin/musicu.fcg',
      data: {
        'comm': {'ct': 19, 'cv': 1845},
        'req_0': {
          'module': 'music.musichallSong.LyricReader',
          'method': 'GetLyricReader',
          'param': {'songMID': songMid, 'songID': 0},
        },
      },
      options: Options(contentType: Headers.jsonContentType, responseType: ResponseType.json),
    );
    final data = res.data is String ? jsonDecode(res.data) : res.data;
    print('Response: ${jsonEncode(data).substring(0, 500)}');
    final lyric = data['req_0']?['data']?['lyric'];
    if (lyric != null) {
      print('Lyric field: ${lyric.toString().substring(0, 200)}');
    }
  } catch (e) {
    print('Error: $e');
  }

  print('\n=== DONE ===');
}
