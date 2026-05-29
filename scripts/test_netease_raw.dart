import 'package:dio/dio.dart';
import '../lib/platform/netease/netease_crypto.dart';

void main() async {
  final dio = Dio();

  // Test 1: Manual form body (bypass Dio's form encoding)
  print('=== Test 1: Manual form body ===');
  try {
    final encrypted = NeteaseCrypto.encryptRequest({
      's': '周杰伦',
      'type': 1,
      'limit': 5,
      'offset': 0,
      'total': true,
      'csrf_token': '',
    });
    final body = 'params=${Uri.encodeComponent(encrypted['params']!)}&encSecKey=${Uri.encodeComponent(encrypted['encSecKey']!)}';
    print('Body: ${body.substring(0, 100)}...');
    print('Body length: ${body.length}');

    final res = await dio.post(
      'https://music.163.com/weapi/cloudsearch/pc',
      data: body,
      options: Options(
        contentType: 'application/x-www-form-urlencoded',
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Chrome/91.0.4472.164 NeteaseMusicDesktop/2.10.2.200154',
          'Referer': 'https://music.163.com/',
          'Origin': 'https://music.163.com',
          'Cookie': 'os=pc; appver=2.10.2.200154',
        },
      ),
    );
    print('Status: ${res.statusCode}');
    print('Content-Type: ${res.headers.value('content-type')}');
    print('Data type: ${res.data.runtimeType}');
    print('Data: ${res.data}');
  } catch (e) {
    print('Error: $e');
  }

  // Test 2: Try the old /api/cloudsearch/pc with POST (no encryption)
  print('\n=== Test 2: /api/cloudsearch/pc POST (no encryption) ===');
  try {
    final res = await dio.post(
      'https://music.163.com/api/cloudsearch/pc',
      data: {
        's': '周杰伦',
        'type': 1,
        'limit': 5,
        'offset': 0,
        'total': true,
      },
      options: Options(
        contentType: 'application/x-www-form-urlencoded',
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36',
          'Referer': 'https://music.163.com/',
          'Cookie': 'os=pc; appver=2.10.2.200154',
        },
      ),
    );
    print('Status: ${res.statusCode}');
    print('Data: ${res.data}');
  } catch (e) {
    print('Error: $e');
  }

  // Test 3: Try the old /api/cloudsearch/pc with GET
  print('\n=== Test 3: /api/cloudsearch/pc GET ===');
  try {
    final res = await dio.get(
      'https://music.163.com/api/cloudsearch/pc',
      queryParameters: {
        's': '周杰伦',
        'type': 1,
        'limit': 5,
        'offset': 0,
      },
      options: Options(
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36',
          'Referer': 'https://music.163.com/',
          'Cookie': 'os=pc; appver=2.10.2.200154',
        },
      ),
    );
    print('Status: ${res.statusCode}');
    print('Data: ${res.data}');
  } catch (e) {
    print('Error: $e');
  }

  // Test 4: Try interface.music.163.com with eapi-like request
  print('\n=== Test 4: interface.music.163.com /api/cloudsearch/pc ===');
  try {
    final res = await dio.get(
      'https://interface.music.163.com/api/cloudsearch/pc',
      queryParameters: {
        's': '周杰伦',
        'type': 1,
        'limit': 5,
        'offset': 0,
      },
      options: Options(
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36',
          'Referer': 'https://music.163.com/',
          'Cookie': 'os=pc; appver=2.10.2.200154',
        },
      ),
    );
    print('Status: ${res.statusCode}');
    print('Data: ${res.data}');
  } catch (e) {
    print('Error: $e');
  }
}
