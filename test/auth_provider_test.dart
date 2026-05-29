import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/storage/session_storage.dart';
import 'package:mconnect/features/auth/presentation/providers/auth_provider.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/user.dart';
import 'package:mconnect/platform/base/music_platform.dart';
import 'package:mconnect/platform/base/platform_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
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
}

class _FakeQrAuthPlatform implements MusicPlatform {
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
