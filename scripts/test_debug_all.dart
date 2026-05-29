import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

void main() async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Chrome/91.0.4472.164 NeteaseMusicDesktop/2.10.2.200154',
      'Referer': 'https://music.163.com/',
      'Origin': 'https://music.163.com',
      'Cookie': 'os=pc; appver=2.10.2.200154',
    },
  ));

  // ===== TEST 1: Netease search to get a song ID =====
  print('=== TEST 1: Netease Search ===');
  try {
    final searchRes = await dio.get(
      'https://music.163.com/api/cloudsearch/pc',
      queryParameters: {'s': '周杰伦', 'type': 1, 'limit': 3, 'offset': 0},
    );
    final searchData = searchRes.data is String ? jsonDecode(searchRes.data) : searchRes.data;
    final songs = searchData['result']?['songs'] as List?;
    if (songs != null && songs.isNotEmpty) {
      final song = songs[0];
      final songId = song['id'];
      final songName = song['name'];
      final duration = song['dt'];
      final coverUrl = song['al']?['picUrl'];
      print('Song: $songName, ID: $songId, Duration: ${duration}ms, Cover: $coverUrl');

      // ===== TEST 2: Netease song URL =====
      print('\n=== TEST 2: Netease Song URL ===');
      final urlRes = await dio.post(
        'https://music.163.com/api/song/enhance/player/url/v1',
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
        print('URL: ${item['url']}');
        print('Size: ${item['size']}');
        print('Level: ${item['level']}');
        print('BR: ${item['br']}');
        print('Type: ${item['type']}');
      } else {
        print('ERROR: No data returned!');
        print('Full response: ${jsonEncode(urlData)}');
      }

      // ===== TEST 3: Netease Lyrics =====
      print('\n=== TEST 3: Netease Lyrics ===');
      final lyricRes = await dio.get(
        'https://music.163.com/api/song/lyric',
        queryParameters: {'id': songId, 'lv': -1, 'tv': -1},
      );
      final lyricData = lyricRes.data is String ? jsonDecode(lyricRes.data) : lyricRes.data;
      print('Response code: ${lyricData['code']}');
      final lrc = lyricData['lrc']?['lyric'] as String?;
      if (lrc != null && lrc.isNotEmpty) {
        print('Lyrics length: ${lrc.length}');
        print('First 300 chars: ${lrc.substring(0, lrc.length > 300 ? 300 : lrc.length)}');
      } else {
        print('ERROR: No lyrics returned!');
        print('Full lrc field: ${lyricData['lrc']}');
      }
    } else {
      print('ERROR: No songs found in search');
    }
  } catch (e) {
    print('Netease error: $e');
  }

  // ===== TEST 4: QQ Lyrics =====
  print('\n=== TEST 4: QQ Lyrics ===');
  try {
    final qqDio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://y.qq.com/portal/player.html',
        'Origin': 'https://y.qq.com',
      },
    ));
    // First search for a QQ song
    final qqSearchRes = await qqDio.post(
      'https://u.y.qq.com/cgi-bin/musicu.fcg',
      data: {
        'comm': {'ct': 19, 'cv': 1845},
        'req_0': {
          'method': 'DoSearchForQQMusicDesktop',
          'module': 'music.search.SearchCgiService',
          'param': {'num_per_page': 1, 'page_num': 1, 'query': '周杰伦', 'search_type': 0},
        },
      },
      options: Options(contentType: Headers.jsonContentType, responseType: ResponseType.json),
    );
    final qqSearchData = qqSearchRes.data is String ? jsonDecode(qqSearchRes.data) : qqSearchRes.data;
    final qqSongs = qqSearchData['req_0']?['data']?['body']?['song']?['list'] as List?;
    if (qqSongs != null && qqSongs.isNotEmpty) {
      final songMid = qqSongs[0]['mid'];
      final songName = qqSongs[0]['name'];
      print('QQ Song: $songName, mid: $songMid');

      final lyricRes = await qqDio.get(
        'https://i.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg',
        queryParameters: {'songmid': songMid, 'format': 'json', 'nobase64': 1},
      );
      final lyricData = lyricRes.data is String ? jsonDecode(lyricRes.data) : lyricRes.data;
      final qqLrc = lyricData['lyric'] as String?;
      if (qqLrc != null && qqLrc.isNotEmpty) {
        print('QQ Lyrics length: ${qqLrc.length}');
        print('First 300 chars: ${qqLrc.substring(0, qqLrc.length > 300 ? 300 : qqLrc.length)}');
        print('Contains <L: ${qqLrc.contains('<L ')}');
        print('Contains <P: ${qqLrc.contains('<P ')}');
      } else {
        print('ERROR: No QQ lyrics!');
        print('Full response keys: ${lyricData.keys.toList()}');
        print('Full response: ${jsonEncode(lyricData).substring(0, 500)}');
      }
    }
  } catch (e) {
    print('QQ error: $e');
  }

  // ===== TEST 5: Kugou Lyrics =====
  print('\n=== TEST 5: Kugou Lyrics ===');
  try {
    final kgDio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36',
      },
    ));
    // Search for a Kugou song to get hash
    final kgSearchRes = await kgDio.get(
      'http://mobilecdn.kugou.com/api/v3/search/song',
      queryParameters: {'format': 'json', 'keyword': '周杰伦', 'page': 1, 'pagesize': 1, 'showtype': 1},
    );
    final kgSearchData = kgSearchRes.data is String ? jsonDecode(kgSearchRes.data) : kgSearchRes.data;
    final kgSongs = kgSearchData['data']?['info'] as List?;
    if (kgSongs != null && kgSongs.isNotEmpty) {
      final hash = kgSongs[0]['hash'];
      final songName = kgSongs[0]['songname'];
      print('Kugou Song: $songName, hash: $hash');

      // Get song info for singer name
      final infoRes = await kgDio.get(
        'http://m.kugou.com/app/i/getSongInfo.php',
        queryParameters: {'cmd': 'playInfo', 'hash': hash},
      );
      final infoData = infoRes.data is String ? jsonDecode(infoRes.data) : infoRes.data;
      final singer = infoData['singerName'] ?? infoData['author_name'] ?? '';
      final kgSongName = infoData['songName'] ?? '';
      final timeLength = infoData['timeLength'] ?? 0;
      print('Singer: $singer, SongName: $kgSongName, TimeLength: $timeLength');

      if (singer.isNotEmpty && kgSongName.isNotEmpty) {
        final keyword = '$singer-$kgSongName';
        print('Lyrics keyword: $keyword');

        final lyricsSearchRes = await kgDio.get(
          'http://lyrics.kugou.com/search',
          queryParameters: {'ver': 1, 'man': 'yes', 'client': 'pc', 'keyword': keyword, 'duration': timeLength, 'hash': ''},
        );
        final lyricsData = lyricsSearchRes.data is String ? jsonDecode(lyricsSearchRes.data) : lyricsSearchRes.data;
        final candidates = lyricsData['candidates'] as List?;
        print('Lyrics candidates: ${candidates?.length ?? 0}');
        if (candidates != null && candidates.isNotEmpty) {
          final first = candidates[0];
          print('First candidate: id=${first['id']}, accesskey=${first['accesskey']}, songname=${first['songname']}');

          // Download KRC
          final dlRes = await kgDio.get(
            'http://lyrics.kugou.com/download',
            queryParameters: {'ver': 1, 'client': 'pc', 'id': first['id'], 'accesskey': first['accesskey'], 'fmt': 'krc', 'charset': 'utf8'},
          );
          final dlData = dlRes.data is String ? jsonDecode(dlRes.data) : dlRes.data;
          final content = dlData['content'] as String?;
          if (content != null) {
            print('KRC content length: ${content.length}');
            // Try to decrypt
            try {
              final decoded = base64Decode(content);
              print('Base64 decoded length: ${decoded.length}');
              if (decoded.length > 4) {
                final encrypted = decoded.sublist(4);
                const key = [0x40, 0x47, 0x61, 0x77, 0x5e, 0x32, 0x74, 0x47, 0x51, 0x36, 0x31, 0x2d, 0xce, 0xd2, 0x6e, 0x69];
                final decrypted = List<int>.generate(encrypted.length, (i) => encrypted[i] ^ key[i % key.length]);
                final decompressed = zlib.decode(decrypted);
                if (decompressed.isNotEmpty) {
                  final text = utf8.decode(decompressed.sublist(1));
                  print('Decrypted KRC length: ${text.length}');
                  print('First 300 chars: ${text.substring(0, text.length > 300 ? 300 : text.length)}');
                }
              }
            } catch (e) {
              print('KRC decrypt error: $e');
            }
          } else {
            print('ERROR: No KRC content!');
          }
        } else {
          print('ERROR: No lyrics candidates found!');
        }
      }
    }
  } catch (e) {
    print('Kugou error: $e');
  }

  print('\n=== DONE ===');
}
