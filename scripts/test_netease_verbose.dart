import 'package:dio/dio.dart';
import '../lib/platform/netease/netease_crypto.dart';

void main() async {
  final dio = Dio();
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      print('REQUEST: ${options.method} ${options.uri}');
      final data = options.data;
      if (data is Map) {
        print('Body is Map with keys: ${data.keys.toList()}');
        print('params length: ${data["params"]?.length}');
        print('encSecKey length: ${data["encSecKey"]?.length}');
      }
      handler.next(options);
    },
    onResponse: (response, handler) {
      print('RESPONSE: ${response.statusCode}');
      print('Content-Type: ${response.headers.value("content-type")}');
      print('Body type: ${response.data.runtimeType}');
      if (response.data != null) {
        final s = response.data.toString();
        print('Body length: ${s.length}');
        print('Body preview: ${s.substring(0, s.length.clamp(0, 500))}');
      } else {
        print('Body is null!');
        // Try to get raw bytes
        print('Response extra: ${response.extra}');
      }
      handler.next(response);
    },
    onError: (error, handler) {
      print('ERROR: ${error.type} ${error.message}');
      if (error.response != null) {
        print('Error status: ${error.response?.statusCode}');
        print('Error body: ${error.response?.data}');
      }
      handler.next(error);
    },
  ));

  final encrypted = NeteaseCrypto.encryptRequest({
    's': '周杰伦',
    'type': 1,
    'limit': 5,
    'offset': 0,
    'total': true,
    'csrf_token': '',
  });

  print('=== Testing Netease Search (with cookie) ===');
  try {
    final res = await dio.post(
      'https://music.163.com/weapi/cloudsearch/pc',
      data: encrypted,
      options: Options(
        contentType: 'application/x-www-form-urlencoded',
        headers: {
          'Referer': 'https://music.163.com/',
          'Origin': 'https://music.163.com',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Chrome/91.0.4472.164 NeteaseMusicDesktop/2.10.2.200154',
          'Cookie': 'os=pc; appver=2.10.2.200154',
        },
      ),
    );
    print('Final status: ${res.statusCode}');
    print('Final data: ${res.data}');
  } catch (e) {
    print('Caught: $e');
  }

  // Also test the old unencrypted endpoint
  print('\n=== Testing Netease Search (old /api/search/pc, no encryption) ===');
  try {
    final res = await dio.get(
      'https://music.163.com/api/search/pc',
      queryParameters: {
        's': '周杰伦',
        'type': 1,
        'limit': 5,
        'offset': 0,
      },
      options: Options(
        headers: {
          'Referer': 'https://music.163.com/',
          'Origin': 'https://music.163.com',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Chrome/91.0.4472.164 NeteaseMusicDesktop/2.10.2.200154',
          'Cookie': 'os=pc; appver=2.10.2.200154',
        },
      ),
    );
    print('Final status: ${res.statusCode}');
    final data = res.data;
    if (data is Map) {
      final songs = data['result']?['songs'] as List?;
      print('Found ${songs?.length ?? 0} songs');
      if (songs != null && songs.isNotEmpty) {
        print('First: ${songs.first['name']}');
      }
    } else {
      print('Data: ${data?.toString().substring(0, data.toString().length.clamp(0, 300))}');
    }
  } catch (e) {
    print('Caught: $e');
  }
}
