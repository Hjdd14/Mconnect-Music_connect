// 网易云 QR 登录诊断
// 运行: dart run scripts/test_netease_qr.dart

import 'dart:convert';
import 'package:dio/dio.dart';

void main() async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Chrome/91.0.4472.164 NeteaseMusicDesktop/2.10.2.200154',
      'Referer': 'https://music.163.com/',
      'Origin': 'https://music.163.com',
      'Cookie': 'os=pc; appver=2.10.2.200154',
    },
  ));

  print('=== 网易云 QR 登录诊断 ===\n');

  // 1. 获取 QR key
  print('--- 1. 获取 QR key ---');
  final keyRes = await dio.post(
    'https://music.163.com/api/login/qrcode/unikey',
    data: {'type': 3},
    options: Options(contentType: 'application/x-www-form-urlencoded'),
  );
  final keyData = keyRes.data is String ? jsonDecode(keyRes.data as String) : keyRes.data;
  print('  响应: ${jsonEncode(keyData)}');

  final keyMap = keyData as Map;
  final unikey = keyMap['data']?['unikey'] ?? keyMap['unikey'];
  if (unikey == null) {
    print('  unikey 为 null! 响应: ${jsonEncode(keyMap)}');
    return;
  }
  print('  unikey: $unikey');

  final qrUrl = 'https://music.163.com/login?codekey=$unikey';
  print('  QR URL: $qrUrl');

  // 2. 检查 QR 状态（未扫码）
  print('\n--- 2. 检查 QR 状态（未扫码） ---');
  final checkRes = await dio.post(
    'https://music.163.com/api/login/qrcode/client/login',
    data: {'key': unikey, 'type': 3},
    options: Options(contentType: 'application/x-www-form-urlencoded'),
  );
  final checkData = checkRes.data is String ? jsonDecode(checkRes.data as String) : checkRes.data;
  print('  响应: ${jsonEncode(checkData)}');

  // 打印所有响应头
  print('\n--- 响应头 ---');
  checkRes.headers.forEach((key, values) {
    print('  $key: $values');
  });

  // 3. 打印 Set-Cookie
  final setCookie = checkRes.headers.value('set-cookie');
  print('\n  Set-Cookie: $setCookie');

  print('\n=== 请用手机扫描二维码: $qrUrl ===');
  print('扫码后程序会继续检查状态...');

  // 4. 轮询 QR 状态
  for (var i = 0; i < 30; i++) {
    await Future.delayed(const Duration(seconds: 3));
    try {
      final pollRes = await dio.post(
        'https://music.163.com/api/login/qrcode/client/login',
        data: {'key': unikey, 'type': 3},
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );
      final pollData = pollRes.data is String ? jsonDecode(pollRes.data as String) : pollRes.data;
      final code = (pollData as Map)['code'];
      print('\n[$i] code=$code, 响应: ${jsonEncode(pollData)}');

      // Check Set-Cookie header
      final sc = pollRes.headers.value('set-cookie');
      if (sc != null) print('  Set-Cookie: $sc');

      if (code == 803) {
        print('\n=== 登录成功! ===');
        final cookie = pollData['cookie'];
        print('  cookie 字段: $cookie');
        print('  Set-Cookie header: $sc');

        // Try to get user info
        if (sc != null && sc.contains('MUSIC_U')) {
          final musicU = RegExp(r'MUSIC_U=([^;]+)').firstMatch(sc);
          if (musicU != null) {
            final musicUCookie = 'MUSIC_U=${musicU.group(1)}';
            print('\n  使用 cookie 获取用户信息...');
            dio.options.headers['cookie'] = musicUCookie;
            final userRes = await dio.post(
              'https://music.163.com/api/nuser/account/get',
              data: {},
              options: Options(contentType: 'application/x-www-form-urlencoded'),
            );
            final userData = userRes.data is String ? jsonDecode(userRes.data as String) : userRes.data;
            print('  用户信息: ${jsonEncode(userData)}');
          }
        }
        return;
      } else if (code == 800) {
        print('二维码已过期');
        return;
      }
    } catch (e) {
      print('[$i] 错误: $e');
    }
  }
  print('超时');
}
