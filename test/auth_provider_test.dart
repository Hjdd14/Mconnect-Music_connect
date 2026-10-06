import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/network/api_exception.dart';
import 'package:mconnect/core/storage/session_storage.dart';
import 'package:mconnect/features/auth/presentation/providers/auth_provider.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/user.dart';
import 'package:mconnect/platform/base/music_platform.dart';
import 'package:mconnect/platform/base/platform_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> backing;
  late SessionStorage storage;

  setUp(() {
    backing = <String, String>{};
    FlutterSecureStorage.setMockInitialValues(backing);
    storage = SessionStorage();
  });

  test(
    'QR login success refreshes auth state before saving the session',
    () async {
      final platform = _FakeQrAuthPlatform();
      PlatformRegistry.register(platform);
      final notifier = AuthNotifier();

      await notifier.onQrLoginSuccess(PlatformType.kugou);

      expect(notifier.state.isLoggedIn(PlatformType.kugou), isTrue);
      expect(
        notifier.state.userFor(PlatformType.kugou)?.nickname,
        'Kugou User',
      );
      expect(platform.savedSessions, 1);
    },
  );

  group('会话过期（LoginExpiredException）引导重登', () {
    test('refreshUser 拿到 401 时清空内存会话与持久化凭据', () async {
      final platform = _FakeExpiryPlatform();
      PlatformRegistry.register(platform);
      final notifier = AuthNotifier();

      // Seed a healthy logged-in session first.
      await notifier.onQrLoginSuccess(PlatformType.netease);
      expect(notifier.state.isLoggedIn(PlatformType.netease), isTrue);
      expect(await storage.loadCookie(PlatformType.netease), 'MUSIC_U=abc');
      expect(await storage.loadUser(PlatformType.netease), isNotNull);

      // The platform now rejects the stored cookie.
      platform.userInfoError = LoginExpiredException();
      await notifier.refreshUser(PlatformType.netease);

      expect(notifier.state.isLoggedIn(PlatformType.netease), isFalse);
      expect(notifier.state.userFor(PlatformType.netease), isNull);
      expect(await storage.loadCookie(PlatformType.netease), isNull);
      expect(await storage.loadUser(PlatformType.netease), isNull);
    });

    test('refreshUser 拿到普通错误时保留会话（不误判为过期）', () async {
      final platform = _FakeExpiryPlatform();
      PlatformRegistry.register(platform);
      final notifier = AuthNotifier();

      await notifier.onQrLoginSuccess(PlatformType.netease);
      platform.userInfoError = NetworkException();
      await notifier.refreshUser(PlatformType.netease);

      expect(notifier.state.isLoggedIn(PlatformType.netease), isTrue);
      expect(await storage.loadCookie(PlatformType.netease), 'MUSIC_U=abc');
    });

    test('handleSessionExpired 可被平台 provider 直接调用', () async {
      final platform = _FakeExpiryPlatform();
      PlatformRegistry.register(platform);
      final notifier = AuthNotifier();

      await notifier.onQrLoginSuccess(PlatformType.netease);
      await notifier.handleSessionExpired(PlatformType.netease);

      expect(notifier.state.isLoggedIn(PlatformType.netease), isFalse);
      expect(await storage.loadCookie(PlatformType.netease), isNull);
    });

    test('启动恢复阶段拿到 401 也会丢弃已死 cookie', () async {
      final platform = _FakeExpiryPlatform();
      PlatformRegistry.register(platform);
      final notifier = AuthNotifier();

      await notifier.onQrLoginSuccess(PlatformType.netease);
      platform.userInfoError = LoginExpiredException();

      await notifier.init();

      expect(notifier.state.userFor(PlatformType.netease), isNull);
      expect(await storage.loadCookie(PlatformType.netease), isNull);
      expect(await storage.loadUser(PlatformType.netease), isNull);
    });
  });
}

class _FakeQrAuthPlatform extends MusicPlatform {
  int savedSessions = 0;
  final _user = const User(
    id: '10001',
    nickname: 'Kugou User',
    platform: PlatformType.kugou,
  );

  @override
  PlatformType get platformType => PlatformType.kugou;

  @override
  String get platformName => 'Kugou';

  @override
  bool get isLoggedIn => true;

  @override
  Future<User?> getUserInfo() async => _user;

  @override
  Future<void> saveSession(SessionStorage storage) async {
    savedSessions++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Logged-in platform whose [getUserInfo] can be made to fail on demand, so the
/// "stored cookie was rejected" path can be exercised without a network.
class _FakeExpiryPlatform extends MusicPlatform {
  Object? userInfoError;
  String? loadedCookie;

  final _user = const User(
    id: '20002',
    nickname: 'Netease User',
    platform: PlatformType.netease,
  );

  @override
  PlatformType get platformType => PlatformType.netease;

  @override
  String get platformName => '网易云';

  @override
  bool get isLoggedIn => loadedCookie != null;

  @override
  Future<User?> getUserInfo() async {
    final error = userInfoError;
    if (error != null) throw error;
    return _user;
  }

  @override
  Future<void> saveSession(SessionStorage storage) async {
    await storage.saveCookie(platformType, 'MUSIC_U=abc');
    await storage.saveUser(platformType, _user);
  }

  @override
  Future<void> restoreSession(SessionStorage storage) async {
    loadedCookie = await storage.loadCookie(platformType);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
