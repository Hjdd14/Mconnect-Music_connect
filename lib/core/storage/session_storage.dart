import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../models/user.dart';
import '../../models/platform_type.dart';

class SessionStorage {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const _cookiePrefix = 'cookie_';
  static const _userPrefix = 'user_';

  Future<void> saveCookie(PlatformType platform, String cookie) async {
    await _storage.write(key: '${_cookiePrefix}${platform.name}', value: cookie);
  }

  Future<String?> loadCookie(PlatformType platform) async {
    return _storage.read(key: '${_cookiePrefix}${platform.name}');
  }

  Future<void> deleteCookie(PlatformType platform) async {
    await _storage.delete(key: '${_cookiePrefix}${platform.name}');
  }

  Future<void> saveUser(PlatformType platform, User user) async {
    await _storage.write(
      key: '${_userPrefix}${platform.name}',
      value: jsonEncode(user.toJson()),
    );
  }

  Future<User?> loadUser(PlatformType platform) async {
    final json = await _storage.read(key: '${_userPrefix}${platform.name}');
    if (json == null) return null;
    try {
      return User.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteUser(PlatformType platform) async {
    await _storage.delete(key: '${_userPrefix}${platform.name}');
  }

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
