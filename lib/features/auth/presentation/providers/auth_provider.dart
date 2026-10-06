import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../models/platform_type.dart';
import '../../../../models/user.dart';
import '../../../../platform/base/music_platform.dart';
import '../../../../platform/base/platform_registry.dart';
import '../../../../platform/kugou/kugou_platform.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/network/platform_http.dart';
import '../../../../core/storage/session_storage.dart';

class AuthState {
  final Map<PlatformType, User?> loggedUsers;
  final bool isLoading;

  const AuthState({this.loggedUsers = const {}, this.isLoading = false});

  AuthState copyWith({Map<PlatformType, User?>? loggedUsers, bool? isLoading}) {
    return AuthState(
      loggedUsers: loggedUsers ?? this.loggedUsers,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  bool isLoggedIn(PlatformType platform) => loggedUsers[platform] != null;

  User? userFor(PlatformType platform) => loggedUsers[platform];
}

class AuthNotifier extends StateNotifier<AuthState> {
  static final _sessionStorage = SessionStorage();

  AuthNotifier() : super(const AuthState());

  /// Restore sessions from secure storage on app startup.
  /// Only restores cookies + user data — no network calls.
  Future<void> init() async {
    try {
      // Timeout: don't block app startup for more than 8 seconds
      await _restoreSessions().timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Session restore timeout/error: $e');
    }
  }

  Future<void> _restoreSessions() async {
    final users = <PlatformType, User?>{};
    for (final platform in PlatformRegistry.supportedTypes) {
      try {
        final impl = PlatformRegistry.get(platform);
        await impl.restoreSession(_sessionStorage);
        users[platform] = await impl.getUserInfo();
      } catch (e) {
        debugPrint('Session restore error for $platform: $e');
        if (apiExceptionOf(e) is LoginExpiredException) {
          // The stored cookie is dead: forget it so every later start does not
          // repeat the same doomed request before showing the login screen.
          await _forgetPersistedSession(platform);
        }
        users[platform] = null;
      }
    }
    state = state.copyWith(loggedUsers: users);
  }

  /// Save session to secure storage after successful login
  Future<void> _saveSession(PlatformType platform) async {
    try {
      final impl = PlatformRegistry.get(platform);
      await impl.saveSession(_sessionStorage);
    } catch (e) {
      debugPrint('Save session error: $e');
    }
  }

  void _configureKugouVariant(MusicPlatform impl, String? authVariant) {
    if (impl is KugouPlatform) {
      impl.setClientVariant(authVariant);
    }
  }

  /// Fetch user info for a platform and update state.
  ///
  /// When the platform answers that the stored session is no longer valid
  /// ([LoginExpiredException], i.e. HTTP 401/403 or the platform's own
  /// "not logged in" code — see `PlatformErrorInterceptor`), the stale session
  /// is dropped instead of being silently swallowed, so the UI falls back to
  /// its logged-out state and offers a fresh login.
  Future<void> refreshUser(PlatformType platform) async {
    try {
      final impl = PlatformRegistry.get(platform);
      final user = await impl.getUserInfo();
      state = state.copyWith(
        loggedUsers: {...state.loggedUsers, platform: user},
      );
    } on Object catch (e) {
      if (apiExceptionOf(e) is LoginExpiredException) {
        await handleSessionExpired(platform);
      }
    }
  }

  /// Signals that [platform] reported an expired session
  /// ([LoginExpiredException]): forget the persisted cookie/user and return to
  /// the logged-out state so the user can log in again.
  ///
  /// Public on purpose: the platform providers (discovery / playlists /
  /// playback) that surface [LoginExpiredException] from an adapter call can
  /// report it here (`ref.read(authProvider.notifier).handleSessionExpired(p)`)
  /// instead of leaving the app on a stale "logged in" user that can no longer
  /// fetch anything.
  Future<void> handleSessionExpired(PlatformType platform) async {
    await _forgetPersistedSession(platform);
    state = state.copyWith(
      loggedUsers: {...state.loggedUsers, platform: null},
    );
  }

  /// Best-effort removal of the persisted session; storage failures must not
  /// stop the state from being reset (see [SessionStorage]).
  Future<void> _forgetPersistedSession(PlatformType platform) async {
    try {
      await _sessionStorage.deleteCookie(platform);
      await _sessionStorage.deleteUser(platform);
    } catch (e) {
      debugPrint('Forget session error for $platform: $e');
    }
  }

  /// Refresh all platforms
  Future<void> refreshAll() async {
    for (final platform in PlatformRegistry.supportedTypes) {
      await refreshUser(platform);
    }
  }

  /// Login via phone (Netease and Kugou support this)
  Future<LoginResult> sendPhoneCode(
    PlatformType platform,
    String phone, {
    String? authVariant,
  }) async {
    try {
      final impl = PlatformRegistry.get(platform);
      _configureKugouVariant(impl, authVariant);
      return await impl.sendPhoneCode(phone);
    } catch (e) {
      return LoginResult(success: false, error: e.toString());
    }
  }

  Future<LoginResult> loginByPhone(
    PlatformType platform,
    String phone,
    String code, {
    String? authVariant,
  }) async {
    try {
      final impl = PlatformRegistry.get(platform);
      _configureKugouVariant(impl, authVariant);
      final result = await impl.loginByPhone(phone, code);
      if (result.success) {
        state = state.copyWith(
          loggedUsers: {...state.loggedUsers, platform: result.user},
        );
        await _saveSession(platform);
      }
      return result;
    } catch (e) {
      return LoginResult(success: false, error: e.toString());
    }
  }

  /// Logout from a platform
  Future<void> logout(PlatformType platform) async {
    try {
      final impl = PlatformRegistry.get(platform);
      await impl.logout();
      await _sessionStorage.deleteCookie(platform);
      await _sessionStorage.deleteUser(platform);
      state = state.copyWith(
        loggedUsers: {...state.loggedUsers, platform: null},
      );
    } catch (_) {
      state = state.copyWith(
        loggedUsers: {...state.loggedUsers, platform: null},
      );
    }
  }

  /// Get QR code for a platform
  Future<QrLoginResult> getQrCode(PlatformType platform) async {
    final impl = PlatformRegistry.get(platform);
    _configureKugouVariant(impl, null);
    return impl.getQrCode();
  }

  Future<QrLoginResult> getQrCodeWithVariant(
    PlatformType platform, {
    String? authVariant,
  }) async {
    final impl = PlatformRegistry.get(platform);
    _configureKugouVariant(impl, authVariant);
    return impl.getQrCode();
  }

  /// Poll QR status for a platform
  Stream<QrLoginStatus> pollQrStatus(
    PlatformType platform,
    String key, {
    String? authVariant,
  }) async* {
    final impl = PlatformRegistry.get(platform);
    _configureKugouVariant(impl, authVariant);
    yield* impl.pollQrStatus(key);
  }

  /// Called after successful QR login to refresh state and persist session.
  Future<User?> onQrLoginSuccess(PlatformType platform) async {
    User? user;
    try {
      final impl = PlatformRegistry.get(platform);
      user = await impl.getUserInfo().timeout(const Duration(seconds: 8));
      state = state.copyWith(
        loggedUsers: {...state.loggedUsers, platform: user},
      );
    } catch (e) {
      debugPrint('QR login refresh user error: $e');
    }
    await _saveSession(platform);
    return user;
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
