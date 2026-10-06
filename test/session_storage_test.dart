import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/storage/session_storage.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/user.dart';

/// A [FlutterSecureStorage] whose backend raises like the real Android Keystore
/// does when its key is invalidated (biometric/PIN change, restored backup):
/// every call throws [PlatformException].
///
/// [SessionStorage] must never let that escape into the UI — a throw during app
/// startup (`AuthNotifier.init`) or logout would otherwise leave the app stuck.
class _UnavailableSecureStorage extends FlutterSecureStorage {
  const _UnavailableSecureStorage();

  Never _unavailable() => throw PlatformException(
    code: 'keystore_unavailable',
    message: 'Keystore key invalidated',
  );

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _unavailable();

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _unavailable();

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _unavailable();

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _unavailable();

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _unavailable();
}

/// Readable store whose per-key delete fails: the interesting half-broken case
/// for `clearAll` (readAll works, one delete keeps throwing).
class _PartiallyBrokenSecureStorage extends FlutterSecureStorage {
  _PartiallyBrokenSecureStorage(this.data, {this.brokenDeleteKey});

  final Map<String, String> data;
  final String? brokenDeleteKey;

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => {...data};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => data[key];

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (key == brokenDeleteKey) {
      throw PlatformException(code: 'keystore_unavailable');
    }
    data.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> backing;
  late SessionStorage storage;

  setUp(() {
    backing = <String, String>{};
    // The package's own in-memory platform, backed by the map above, so tests
    // exercise the real `FlutterSecureStorage` path (no seam needed for reads).
    FlutterSecureStorage.setMockInitialValues(backing);
    storage = SessionStorage();
  });

  group('cookie/user 往返', () {
    test('saveCookie 用 cookie_<platform> 作键，loadCookie 能读回', () async {
      await storage.saveCookie(PlatformType.netease, 'MUSIC_U=abc');

      expect(backing['cookie_netease'], 'MUSIC_U=abc');
      expect(await storage.loadCookie(PlatformType.netease), 'MUSIC_U=abc');
    });

    test('deleteCookie 后 loadCookie 返回 null', () async {
      await storage.saveCookie(PlatformType.qq, 'uin=1');
      await storage.deleteCookie(PlatformType.qq);

      expect(await storage.loadCookie(PlatformType.qq), isNull);
      expect(backing.containsKey('cookie_qq'), isFalse);
    });

    test('saveUser/loadUser 往返（含 VIP 字段）', () async {
      const user = User(
        id: '10001',
        nickname: 'Kugou User',
        platform: PlatformType.kugou,
        vipLevel: VipLevel.vip,
      );
      await storage.saveUser(PlatformType.kugou, user);

      final loaded = await storage.loadUser(PlatformType.kugou);

      expect(loaded, isNotNull);
      expect(loaded!.id, '10001');
      expect(loaded.nickname, 'Kugou User');
      expect(loaded.platform, PlatformType.kugou);
      expect(loaded.vipLevel, VipLevel.vip);
    });

    test('deleteUser 后 loadUser 返回 null', () async {
      await storage.saveUser(
        PlatformType.netease,
        const User(id: '1', nickname: 'n', platform: PlatformType.netease),
      );
      await storage.deleteUser(PlatformType.netease);

      expect(await storage.loadUser(PlatformType.netease), isNull);
    });

    test('损坏的 user JSON 降级为 null 而不是抛错', () async {
      backing['user_qq'] = '{not json';

      expect(await storage.loadUser(PlatformType.qq), isNull);
    });

    test('未知平台名降级为 null（不做错误平台兜底）', () async {
      backing['user_qq'] = '{"id":"1","nickname":"n","platform":"spotify"}';

      expect(await storage.loadUser(PlatformType.qq), isNull);
    });
  });

  group('clearAll 只清理本应用的会话键', () {
    test('删除 cookie_/user_ 前缀的键', () async {
      await storage.saveCookie(PlatformType.netease, 'a');
      await storage.saveCookie(PlatformType.qq, 'b');
      await storage.saveUser(
        PlatformType.netease,
        const User(id: '1', nickname: 'n', platform: PlatformType.netease),
      );

      await storage.clearAll();

      expect(backing.keys.where((k) => k.startsWith('cookie_')), isEmpty);
      expect(backing.keys.where((k) => k.startsWith('user_')), isEmpty);
    });

    test('保留非会话键（不能清空整个 secure storage）', () async {
      await storage.saveCookie(PlatformType.kugou, 'token');
      // Unrelated credentials some other feature may have stored securely.
      backing['kugou_vip_token'] = 'vip-secret';
      backing['device_id'] = 'abcdef';
      backing['app_secret_key'] = 'keep-me';

      await storage.clearAll();

      expect(backing['kugou_vip_token'], 'vip-secret');
      expect(backing['device_id'], 'abcdef');
      expect(backing['app_secret_key'], 'keep-me');
      expect(backing.containsKey('cookie_kugou'), isFalse);
    });

    test('空存储时 clearAll 是安全的空操作', () async {
      await storage.clearAll();

      expect(backing, isEmpty);
    });
  });

  group('Keystore 不可用时不得冒泡', () {
    late SessionStorage broken;

    setUp(() {
      broken = SessionStorage(storage: const _UnavailableSecureStorage());
    });

    test('loadCookie/loadUser 返回 null', () async {
      expect(await broken.loadCookie(PlatformType.netease), isNull);
      expect(await broken.loadUser(PlatformType.netease), isNull);
    });

    test('saveCookie/saveUser/deleteCookie/deleteUser 不抛错', () async {
      await expectLater(
        broken.saveCookie(PlatformType.netease, 'x'),
        completes,
      );
      await expectLater(
        broken.saveUser(
          PlatformType.netease,
          const User(id: '1', nickname: 'n', platform: PlatformType.netease),
        ),
        completes,
      );
      await expectLater(broken.deleteCookie(PlatformType.netease), completes);
      await expectLater(broken.deleteUser(PlatformType.netease), completes);
    });

    test('clearAll 不抛错', () async {
      await expectLater(broken.clearAll(), completes);
    });
  });

  test('clearAll 遇到单个 delete 失败仍清理其余会话键', () async {
    final data = <String, String>{
      'cookie_netease': 'a',
      'cookie_qq': 'b',
      'user_netease': '{}',
      'kugou_device_id': 'keep-me',
    };
    final broken = SessionStorage(
      storage: _PartiallyBrokenSecureStorage(
        data,
        brokenDeleteKey: 'cookie_netease',
      ),
    );

    await expectLater(broken.clearAll(), completes);

    expect(data.containsKey('cookie_qq'), isFalse);
    expect(data.containsKey('user_netease'), isFalse);
    expect(data['kugou_device_id'], 'keep-me');
    // The one key whose delete failed stays behind — that is the honest
    // outcome; the important part is that nothing threw and nothing else was lost.
    expect(data['cookie_netease'], 'a');
  });
}
