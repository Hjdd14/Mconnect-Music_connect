import 'dart:convert';
import 'package:dio/dio.dart';

void main() async {
  final dio = Dio();
  final res = await dio.get('https://music.163.com/api/cloudsearch/pc',
    queryParameters: {'s': '周杰伦', 'type': 1, 'limit': 2, 'offset': 0},
    options: Options(headers: {
      'User-Agent': 'Mozilla/5.0',
      'Referer': 'https://music.163.com/',
      'Cookie': 'os=pc; appver=2.10.2.200154',
    }),
  );
  final data = res.data is String ? jsonDecode(res.data as String) : res.data;
  final songs = (data as Map)['result']['songs'] as List;
  for (final s in songs) {
    print('name: ${s['name']}');
    print('  al.picUrl: ${s['al']?['picUrl']}');
    print('  album.picUrl: ${s['album']?['picUrl']}');
    print('  picUrl: ${s['picUrl']}');
  }
}
