import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:pointycastle/export.dart' as pc;
import 'package:crypto/crypto.dart' as crypto_lib;

class NeteaseCrypto {
  NeteaseCrypto._();

  static const String _presetKey = '0CoJUm6Qyw8W8jud';
  static const String _eapiKey = 'e82ckenh8dichen8';
  static const String _pubKey =
      '010001'; // RSA public key exponent (hex)
  static const String _modulus =
      '00e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7'
      'b725152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280'
      '104e0312ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932'
      '575cce10b424d813cfe4875d3e82047b97ddef52741d546b8e289dc6935b'
      '3ece0462db0a22b8e7';

  static const int _nonceSize = 16;

  /// WeAPI encryption: AES-CBC + RSA + random nonce
  static Map<String, String> encryptRequest(Map<String, dynamic> params) {
    final text = jsonEncode(params);
    final secret = _createSecretKey();
    return {
      'params': _aesEncrypt(_aesEncrypt(text, _presetKey, secret), secret, '0102030405060708'),
      'encSecKey': _rsaEncrypt(secret),
    };
  }

  /// eapi encryption: AES-ECB + MD5 (used by NeteaseCloudMusicApi)
  static Map<String, String> encryptEapi(String url, Map<String, dynamic> params) {
    final text = jsonEncode(params);
    final message = 'nobody${url}use${text}md5forencrypt';
    final digest = crypto_lib.md5.convert(utf8.encode(message)).toString();
    final data = '$url-36cd479b6b5-$text-36cd479b6b5-$digest';

    final keyBytes = Uint8List.fromList(utf8.encode(_eapiKey));
    final encrypter = encrypt.Encrypter(encrypt.AES(
      encrypt.Key(keyBytes),
      mode: encrypt.AESMode.ecb,
    ));
    final encrypted = encrypter.encryptBytes(utf8.encode(data));
    return {
      'params': encrypted.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase(),
    };
  }

  /// Encrypt with preset key
  static String encryptWithPresetKey(Map<String, dynamic> params) {
    final text = jsonEncode(params);
    return _aesEncrypt(text, _presetKey, _eapiKey);
  }

  static String _aesEncrypt(String text, String key, String iv) {
    final keyBytes = _utf8Bytes(key);
    final ivBytes = _utf8Bytes(iv);

    final encrypter = encrypt.Encrypter(encrypt.AES(
      encrypt.Key(keyBytes),
      mode: encrypt.AESMode.cbc,
      padding: 'PKCS7',
    ));
    return encrypter.encrypt(text, iv: encrypt.IV(ivBytes)).base64;
  }

  static String _rsaEncrypt(String text) {
    final reversedBytes = Uint8List.fromList(utf8.encode(text).reversed.toList());
    final pubKey = pc.RSAPublicKey(
      BigInt.parse(_modulus, radix: 16),
      BigInt.parse(_pubKey, radix: 16),
    );
    final cipher = pc.RSAEngine()
      ..init(true, pc.PublicKeyParameter<pc.RSAPublicKey>(pubKey));
    final encrypted = cipher.process(reversedBytes);
    return encrypted.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _createSecretKey() {
    final random = Random.secure();
    final chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(_nonceSize, (_) => chars[random.nextInt(chars.length)]).join();
  }

  static Uint8List _utf8Bytes(String s) => Uint8List.fromList(utf8.encode(s));
}
