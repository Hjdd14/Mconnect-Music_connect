// 酷狗封面和歌词修复验证
// 运行: dart run scripts/test_kugou_fix.dart

import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

void main() async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36',
    },
  ));

  print('=== 酷狗修复验证 ===\n');

  // 1. 测试搜索封面
  print('--- 搜索封面测试 ---');
  final searchRes = await dio.get(
    'http://mobilecdn.kugou.com/api/v3/search/song',
    queryParameters: {
      'format': 'json',
      'keyword': '周杰伦 晴天',
      'page': 1,
      'pagesize': 3,
      'showtype': 1,
    },
  );
  final searchData = searchRes.data is String ? jsonDecode(searchRes.data as String) : searchRes.data;
  final info = (searchData as Map)['data']?['info'] as List?;
  if (info != null && info.isNotEmpty) {
    final first = info.first;
    final transParam = first['trans_param'];
    String? coverUrl;
    if (transParam is Map) {
      final unionCover = transParam['union_cover']?.toString();
      if (unionCover != null && unionCover.isNotEmpty) {
        coverUrl = unionCover.replaceFirst('{size}', '480');
      }
    }
    print('  歌曲: ${first['songname']} - ${first['singername']}');
    print('  coverUrl: $coverUrl');
    print('  原始 union_cover: ${transParam?['union_cover']}');
  }

  // 2. 测试歌词（通过 getSongInfo 获取关键词）
  print('\n--- 歌词测试（新方法） ---');
  final hash = info?.first['hash'] ?? '';
  print('  hash: $hash');

  // 获取歌曲信息
  final songInfoRes = await dio.get(
    'http://m.kugou.com/app/i/getSongInfo.php',
    queryParameters: {
      'cmd': 'playInfo',
      'hash': hash,
    },
  );
  final songInfoData = songInfoRes.data is String ? jsonDecode(songInfoRes.data as String) : songInfoRes.data;
  final songInfoMap = songInfoData as Map;
  final singer = songInfoMap['singerName'] ?? songInfoMap['author_name'] ?? '';
  final songName = songInfoMap['songName'] ?? '';
  final duration = songInfoMap['timeLength'] ?? 0;
  print('  singerName: $singer, songName: $songName, duration: $duration');

  if (singer.isNotEmpty && songName.isNotEmpty) {
    final keyword = '$singer-$songName';
    print('  歌词搜索关键词: $keyword');

    final lyricRes = await dio.get(
      'http://lyrics.kugou.com/search',
      queryParameters: {
        'ver': 1,
        'man': 'yes',
        'client': 'pc',
        'keyword': keyword,
        'duration': duration,
        'hash': hash,
      },
    );
    final lyricData = lyricRes.data is String ? jsonDecode(lyricRes.data as String) : lyricRes.data;
    final candidates = (lyricData as Map)['candidates'] as List?;
    print('  歌词候选数: ${candidates?.length ?? 0}');

    if (candidates != null && candidates.isNotEmpty) {
      final first = candidates.first;
      final id = first['id']?.toString();
      final accesskey = first['accesskey']?.toString();
      print('  第一首: ${first['singer']}-${first['song']}, id=$id');

      // 下载歌词
      final downloadRes = await dio.get(
        'http://lyrics.kugou.com/download',
        queryParameters: {
          'ver': 1,
          'client': 'pc',
          'id': id,
          'accesskey': accesskey,
          'fmt': 'krc',
          'charset': 'utf8',
        },
      );
      final downloadData = downloadRes.data is String ? jsonDecode(downloadRes.data as String) : downloadRes.data;
      final content = (downloadData as Map)['content'] as String?;
      if (content != null) {
        // Decrypt KRC
        final decrypted = _decryptKrc(content);
        if (decrypted != null) {
          print('  歌词前200字: ${decrypted.substring(0, 200)}');
        } else {
          print('  歌词解密失败');
        }
      }
    }
  }
}

String? _decryptKrc(String encrypted) {
  try {
    final data = base64Decode(encrypted);
    if (data.length < 4) return null;
    final encryptedBytes = data.sublist(4);
    const key = [
      0x40, 0x47, 0x61, 0x77, 0x5e, 0x32, 0x74, 0x47,
      0x51, 0x36, 0x31, 0x2d, 0xce, 0xd2, 0x6e, 0x69,
    ];
    final decrypted = List<int>.generate(
      encryptedBytes.length,
      (i) => encryptedBytes[i] ^ key[i % key.length],
    );
    final decompressed = zlib.decode(decrypted);
    if (decompressed.isEmpty) return null;
    return utf8.decode(decompressed.sublist(1));
  } catch (e) {
    print('  KRC decrypt error: $e');
    return null;
  }
}
