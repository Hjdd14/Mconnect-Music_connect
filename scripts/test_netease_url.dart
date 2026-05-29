import 'dart:convert';
import 'package:dio/dio.dart';

void main() async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36',
    },
  ));

  // Get a song URL first
  final searchRes = await Dio().get(
    'https://music.163.com/api/cloudsearch/pc',
    queryParameters: {'s': '周杰伦 晴天', 'type': 1, 'limit': 1, 'offset': 0},
  );
  final searchData = searchRes.data is String ? jsonDecode(searchRes.data) : searchRes.data;
  final songs = searchData['result']?['songs'] as List?;
  if (songs == null || songs.isEmpty) return;
  final songId = songs[0]['id'].toString();
  print('Song ID: $songId');

  // Get URL
  final urlRes = await Dio().post(
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
  final item = (urlData['data'] as List?)?.first;
  final url = item?['url'] as String?;
  if (url == null) {
    print('No URL!');
    return;
  }
  print('Original URL: $url');

  // Test 1: HEAD request to check if URL is accessible
  print('\n=== Test: HEAD request ===');
  try {
    final headRes = await dio.head(
      url,
      options: Options(validateStatus: (_) => true),
    );
    print('Status: ${headRes.statusCode}');
    print('Content-Type: ${headRes.headers.value('content-type')}');
    print('Content-Length: ${headRes.headers.value('content-length')}');
    print('Location: ${headRes.headers.value('location')}');
  } catch (e) {
    print('HEAD error: $e');
  }

  // Test 2: GET with followRedirects=false
  print('\n=== Test: GET (no redirect) ===');
  try {
    final getRes = await dio.get(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: false,
        validateStatus: (_) => true,
      ),
    );
    print('Status: ${getRes.statusCode}');
    print('Location: ${getRes.headers.value('location')}');
    print('Content-Type: ${getRes.headers.value('content-type')}');
    print('Content-Length: ${getRes.headers.value('content-length')}');
  } catch (e) {
    print('GET error: $e');
  }

  // Test 3: GET with followRedirects=true
  print('\n=== Test: GET (with redirect) ===');
  try {
    final getRes = await dio.get(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: true,
        validateStatus: (_) => true,
      ),
    );
    print('Status: ${getRes.statusCode}');
    print('Content-Type: ${getRes.headers.value('content-type')}');
    print('Content-Length: ${getRes.headers.value('content-length')}');
    final bytes = getRes.data as List<int>;
    print('Body length: ${bytes.length} bytes');
  } catch (e) {
    print('GET error: $e');
  }

  print('\n=== DONE ===');
}
