import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../models/user.dart';
import '../../models/platform_type.dart';

/// Persists the per-platform login session (cookie + user) in the OS keystore.
///
/// Every method is failure-tolerant **by design**: on Android the Keystore key
/// backing `flutter_secure_storage` is invalidated whenever the user changes
/// their biometric/PIN or restores a backup, and from that moment *every* call
/// throws `PlatformException`. A storage failure must degrade to "no stored
/// session" — it must never propagate into `AuthNotifier.init()` (app startup)
/// or `logout()`, where an exception leaves the app stuck on a stale state.
class SessionStorage {
  /// [storage] is injectable so tests can simulate a Keystore that is
  /// unavailable, without touching the real plugin.
  SessionStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _cookiePrefix = 'cookie_';
  static const _userPrefix = 'user_';

  Future<void> saveCookie(PlatformType platform, String cookie) async {
    try {
      await _storage.write(key: _cookieKey(platform), value: cookie);
    } catch (e) {
      _logFailure('saveCookie', platform, e);
    }
  }

  Future<String?> loadCookie(PlatformType platform) async {
    try {
      return await _storage.read(key: _cookieKey(platform));
    } catch (e) {
      _logFailure('loadCookie', platform, e);
      return null;
    }
  }

  Future<void> deleteCookie(PlatformType platform) async {
    try {
      await _storage.delete(key: _cookieKey(platform));
    } catch (e) {
      _logFailure('deleteCookie', platform, e);
    }
  }

  Future<void> saveUser(PlatformType platform, User user) async {
    try {
      await _storage.write(
        key: _userKey(platform),
        value: jsonEncode(user.toJson()),
      );
    } catch (e) {
      _logFailure('saveUser', platform, e);
    }
  }

  Future<User?> loadUser(PlatformType platform) async {
    try {
      final json = await _storage.read(key: _userKey(platform));
      if (json == null) return null;
      return User.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (e) {
      // Covers both an unreadable keystore and corrupt/legacy JSON.
      _logFailure('loadUser', platform, e);
      return null;
    }
  }

  Future<void> deleteUser(PlatformType platform) async {
    try {
      await _storage.delete(key: _userKey(platform));
    } catch (e) {
      _logFailure('deleteUser', platform, e);
    }
  }

  /// Removes this app's session entries only.
  ///
  /// Deliberately NOT `deleteAll()`: that wipes **everything** in the shared
  /// secure storage, including credentials owned by other features
  /// (e.g. the Kugou VIP token). Only keys this class created
  /// ([_cookiePrefix]/[_userPrefix]) are touched.
  Future<void> clearAll() async {
    try {
      // Snapshot the keys first: `readAll()` may return a live view of the
      // backing store, and deleting while iterating it throws
      // ConcurrentModificationError.
      final keys = (await _storage.readAll()).keys.toList();
      for (final key in keys) {
        if (!_isSessionKey(key)) continue;
        try {
          await _storage.delete(key: key);
        } catch (e) {
          // One key failing must not abort the sweep for the others.
          debugPrint('[SessionStorage] clearAll could not delete $key: $e');
        }
      }
    } catch (e) {
      debugPrint('[SessionStorage] clearAll failed: $e');
    }
  }

  String _cookieKey(PlatformType platform) => '$_cookiePrefix${platform.name}';

  String _userKey(PlatformType platform) => '$_userPrefix${platform.name}';

  bool _isSessionKey(String key) =>
      key.startsWith(_cookiePrefix) || key.startsWith(_userPrefix);

  void _logFailure(String op, PlatformType platform, Object error) {
    debugPrint('[SessionStorage] $op(${platform.name}) failed: $error');
  }
}
