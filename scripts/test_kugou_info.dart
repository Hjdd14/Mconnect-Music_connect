import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

void main() async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'User-Agent': 'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36'},
  ));

  // Search for a song to get hash
  final searchRes = await dio.get(
    'http://mobilecdn.kugou.com/api/v3/search/song',
    queryParameters: {'format': 'json', 'keyword': '周杰伦 晴天', 'page': 1, 'pagesize': 1, 'showtype': 1},
  );
  final searchData = searchRes.data is String ? jsonDecode(searchRes.data) : searchRes.data;
  final songs = searchData['data']?['info'] as List?;
  if (songs == null || songs.isEmpty) { print('No songs'); return; }
  final hash = songs[0]['hash'];
  print('Hash: $hash');

  // Get song info - check full response structure
  final infoRes = await dio.get(
    'http://m.kugou.com/app/i/getSongInfo.php',
    queryParameters: {'cmd': 'playInfo', 'hash': hash},
  );
  final infoData = infoRes.data is String ? jsonDecode(infoRes.data) : infoRes.data;
  print('\n=== Full response keys: ${infoData.keys.toList()}');
  print('singerName (top): ${infoData['singerName']}');
  print('songName (top): ${infoData['songName']}');
  print('timeLength (top): ${infoData['timeLength']}');
  if (infoData['data'] is Map) {
    print('\n--- data wrapper ---');
    final d = infoData['data'];
    print('data keys: ${d.keys.toList()}');
    print('singerName (data): ${d['singerName']}');
    print('songName (data): ${d['songName']}');
    print('timeLength (data): ${d['timeLength']}');
  }

  // Test hash-based lyrics search
  print('\n=== Hash-based lyrics search ===');
  try {
    final lyricsSearchRes = await dio.get(
      'http://krcs.kugou.com/search',
      queryParameters: {
        'ver': 1, 'man': 'yes', 'client': 'mobi',
        'keyword': '', 'duration': '', 'hash': hash, 'album_audio_id': '',
      },
    );
    final lyricsData = lyricsSearchRes.data is String ? jsonDecode(lyricsSearchRes.data) : lyricsSearchRes.data;
    final candidates = lyricsData['candidates'] as List?;
    print('Candidates: ${candidates?.length ?? 0}');
    if (candidates != null && candidates.isNotEmpty) {
      final first = candidates[0];
      print('First: id=${first['id']}, accesskey=${first['accesskey']}, songname=${first['songname']}');

      // Download
      final dlRes = await dio.get(
        'http://lyrics.kugou.com/download',
        queryParameters: {'ver': 1, 'client': 'pc', 'id': first['id'], 'accesskey': first['accesskey'], 'fmt': 'krc', 'charset': 'utf8'},
      );
      final dlData = dlRes.data is String ? jsonDecode(dlRes.data) : dlRes.data;
      final content = dlData['content'] as String?;
      if (content != null) {
        final decoded = base64Decode(content);
        if (decoded.length > 4) {
          final encrypted = decoded.sublist(4);
          const key = [0x40, 0x47, 0x61, 0x77, 0x5e, 0x32, 0x74, 0x47, 0x51, 0x36, 0x31, 0x2d, 0xce, 0xd2, 0x6e, 0x69];
          final decrypted = List<int>.generate(encrypted.length, (i) => encrypted[i] ^ key[i % key.length]);
          final decompressed = zlib.decode(decrypted);
          if (decompressed.isNotEmpty) {
            final text = utf8.decode(decompressed.sublist(1));
            print('KRC length: ${text.length}');
            print('First 200: ${text.substring(0, text.length > 200 ? 200 : text.length)}');
          }
        }
      }
    }
  } catch (e) {
    print('Error: $e');
  }

  // Also test keyword-based search for comparison
  print('\n=== Keyword-based lyrics search ===');
  try {
    final lyricsSearchRes = await dio.get(
      'http://lyrics.kugou.com/search',
      queryParameters: {
        'ver': 1, 'man': 'yes', 'client': 'pc',
        'keyword': '周杰伦-晴天', 'duration': infoData['timeLength'] ?? 0, 'hash': '',
      },
    );
    final lyricsData = lyricsSearchRes.data is String ? jsonDecode(lyricsSearchRes.data) : lyricsSearchRes.data;
    final candidates = lyricsData['candidates'] as List?;
    print('Candidates: ${candidates?.length ?? 0}');
  } catch (e) {
    print('Error: $e');
  }

  print('\n=== DONE ===');
}
