import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';

void main() async {
  final dio = Dio(BaseOptions(
    baseUrl: 'https://music.163.com',
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Chrome/125.0.0.0 NeteaseMusicDesktop/3.0.18.203152',
      'Referer': 'https://music.163.com/',
      'Origin': 'https://music.163.com',
    },
  ));

  // Test 1: Get anonymous token
  print('=== Anonymous Token ===');
  try {
    final res = await dio.post(
      '/api/register/anonimous',
      data: {},
      options: Options(contentType: 'application/x-www-form-urlencoded'),
    );
    final data = res.data is String ? jsonDecode(res.data) : res.data;
    print('Code: ${data['code']}');
    print('Body: ${data}');
    final cookies = res.headers['set-cookie'];
    if (cookies != null) {
      for (final c in cookies) {
        if (c.contains('MUSIC_A')) {
          print('MUSIC_A found in Set-Cookie!');
        }
      }
      print('All cookies: ${cookies.join("; ")}');
    }
  } catch (e) {
    print('Error: $e');
  }

  // Test 2: Full cookie test with anonymous token
  print('\n=== Full Cookie Test ===');
  try {
    final rng = Random();
    String randomHex(int len) => List.generate(len, (_) => rng.nextInt(16).toRadixString(16)).join();
    final nmtid = randomHex(16);
    final ntesNuid = randomHex(32);
    final deviceId = randomHex(16);
    final csrf = randomHex(16);

    final cookie = 'os=pc; appver=3.0.18.203152; osver=Microsoft-Windows-10-Professional-build-22631-64bit'
        '; deviceId=$deviceId; channel=netease'
        '; NMTID=$nmtid; _ntes_nuid=$ntesNuid'
        '; __csrf=$csrf; __remember_me=true'
        '; WEVNSM=1.0.0; resolution=1920x1080'
        '; requestId=${DateTime.now().millisecondsSinceEpoch}_${rng.nextInt(9000) + 1000}';

    final dio2 = Dio(BaseOptions(
      baseUrl: 'https://music.163.com',
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Chrome/125.0.0.0 NeteaseMusicDesktop/3.0.18.203152',
        'Referer': 'https://music.163.com/',
        'Origin': 'https://music.163.com',
        'Cookie': cookie,
      },
    ));

    // Get anonymous token
    final tokenRes = await dio2.post(
      '/api/register/anonimous',
      data: {},
      options: Options(contentType: 'application/x-www-form-urlencoded'),
    );
    final tokenData = tokenRes.data is String ? jsonDecode(tokenRes.data) : tokenRes.data;
    print('Token response: $tokenData');
    final tokenCookies = tokenRes.headers['set-cookie'];
    String? musicA;
    if (tokenCookies != null) {
      for (final c in tokenCookies) {
        final match = RegExp(r'MUSIC_A=([^;]+)').firstMatch(c);
        if (match != null) musicA = match.group(1);
      }
    }
    print('MUSIC_A: ${musicA != null ? "obtained (${musicA.length} chars)" : "not found"}');

    // Build full cookie with MUSIC_A
    var fullCookie = cookie;
    if (musicA != null) fullCookie += '; MUSIC_A=$musicA';
    dio2.options.headers['cookie'] = fullCookie;

    // Search
    final searchRes = await dio2.get('/api/cloudsearch/pc', queryParameters: {'s': '周杰伦 晴天', 'type': 1, 'limit': 1, 'offset': 0});
    final searchData = searchRes.data is String ? jsonDecode(searchRes.data) : searchRes.data;
    final songId = (searchData['result']?['songs'] as List?)?.first['id'];
    print('\nSong ID: $songId');

    // Get URL with full cookies
    final urlRes = await dio2.post(
      '/api/song/enhance/player/url/v1',
      data: {'ids': jsonEncode([songId]), 'level': 'exhigh', 'encodeType': '', 'csrf': csrf},
      options: Options(contentType: 'application/x-www-form-urlencoded'),
    );
    final urlData = urlRes.data is String ? jsonDecode(urlRes.data) : urlRes.data;
    final item = (urlData['data'] as List?)?.first;
    print('URL: ${item?['url'] != null ? "OK" : "NULL"}');
    print('Level: ${item?['level']}');
    print('BR: ${item?['br']}');
    print('FreeTrialInfo: ${item?['freeTrialInfo']}');
    print('Fee: ${item?['fee']}');
  } catch (e) {
    print('Error: $e');
  }

  print('\n=== DONE ===');
}
