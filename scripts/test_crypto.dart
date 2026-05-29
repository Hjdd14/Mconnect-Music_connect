import 'dart:convert';
import '../lib/platform/netease/netease_crypto.dart';

void main() {
  final params = {
    's': '周杰伦',
    'type': 1,
    'limit': 5,
    'offset': 0,
    'total': true,
    'csrf_token': '',
  };

  final text = jsonEncode(params);
  print('Plaintext: $text');
  print('Plaintext length: ${text.length} bytes');

  final encrypted = NeteaseCrypto.encryptRequest(params);
  print('\nEncrypted params: ${encrypted['params']}');
  print('Params length: ${encrypted['params']?.length}');
  print('\nEncrypted encSecKey: ${encrypted['encSecKey']}');
  print('encSecKey length: ${encrypted['encSecKey']?.length}');

  // Verify encSecKey is valid hex
  final encSecKey = encrypted['encSecKey'] ?? '';
  final isHex = RegExp(r'^[0-9a-f]+$').hasMatch(encSecKey);
  print('\nencSecKey is valid hex: $isHex');

  // Verify params is valid base64
  final paramsStr = encrypted['params'] ?? '';
  final isBase64 = RegExp(r'^[A-Za-z0-9+/]+=*$').hasMatch(paramsStr);
  print('params is valid base64: $isBase64');

  // Simulate what Dio sends as form body
  final formBody = 'params=${Uri.encodeComponent(paramsStr)}&encSecKey=${Uri.encodeComponent(encSecKey)}';
  print('\nForm body length: ${formBody.length}');
  print('Form body preview: ${formBody.substring(0, formBody.length.clamp(0, 200))}...');

  // Test multiple times to check randomness
  print('\n--- Multiple encryption test ---');
  for (var i = 0; i < 3; i++) {
    final e = NeteaseCrypto.encryptRequest(params);
    print('Run ${i + 1}: params=${e['params']?.length}, encSecKey=${e['encSecKey']?.length}');
  }
}
