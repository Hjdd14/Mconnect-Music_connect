// 酷狗搜索原始响应诊断
// 运行: dart run scripts/test_kugou_raw.dart

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

  print('=== 酷狗搜索原始响应 ===\n');

  // 搜索
  final res = await dio.get(
    'http://mobilecdn.kugou.com/api/v3/search/song',
    queryParameters: {
      'format': 'json',
      'keyword': '周杰伦 晴天',
      'page': 1,
      'pagesize': 3,
      'showtype': 1,
    },
  );
  final data = res.data is String ? jsonDecode(res.data as String) : res.data;

  final info = (data as Map)['data']?['info'] as List?;
  if (info == null || info.isEmpty) {
    print('无搜索结果');
    return;
  }

  print('找到 ${info.length} 首歌曲\n');

  // 打印第一首歌的所有字段
  final first = info.first;
  print('--- 第一首歌所有字段 ---');
  for (final entry in first.entries) {
    final value = entry.value;
    if (value is String && value.length > 100) {
      print('  ${entry.key}: ${value.substring(0, 100)}...');
    } else {
      print('  ${entry.key}: $value');
    }
  }

  // 测试歌词搜索
  print('\n--- 歌词搜索测试 ---');
  final songName = first['songname'] ?? '';
  final singerName = first['singername'] ?? '';
  final duration = first['duration'] ?? 0;
  final keyword = '$singerName-$songName';
  print('关键词: $keyword, 时长: ${duration}s');

  final lyricRes = await dio.get(
    'http://lyrics.kugou.com/search',
    queryParameters: {
      'ver': 1,
      'man': 'yes',
      'client': 'pc',
      'keyword': keyword,
      'duration': duration * 1000, // 酷狗用毫秒
      'hash': first['hash'] ?? '',
    },
  );
  final lyricData = lyricRes.data is String ? jsonDecode(lyricRes.data as String) : lyricRes.data;
  final candidates = (lyricData as Map)['candidates'] as List?;
  print('歌词候选数: ${candidates?.length ?? 0}');
  if (candidates != null && candidates.isNotEmpty) {
    print('第一首候选: ${jsonEncode(candidates.first)}');
  }

  // 测试 getSongInfo 看是否有封面
  print('\n--- getSongInfo 测试 ---');
  final songInfoRes = await dio.get(
    'http://m.kugou.com/app/i/getSongInfo.php',
    queryParameters: {
      'cmd': 'playInfo',
      'hash': first['hash'] ?? '',
    },
  );
  final songInfoData = songInfoRes.data is String ? jsonDecode(songInfoRes.data as String) : songInfoRes.data;
  final songInfo = (songInfoData as Map)['data'];
  if (songInfo != null) {
    print('imgUrl: ${songInfo['imgUrl']}');
    print('lyrics: ${songInfo['lyrics']?.toString().substring(0, 100)}');
    print('url: ${songInfo['url']?.toString().substring(0, 100)}');
    print('play_url: ${songInfo['play_url']?.toString().substring(0, 100)}');
  }
}
