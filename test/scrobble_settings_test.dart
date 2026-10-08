import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/scrobble/data/scrobble_config.dart';
import 'package:mconnect/features/scrobble/presentation/providers/scrobble_provider.dart';
import 'package:mconnect/features/settings/presentation/providers/scrobble_settings_controller.dart';
import 'package:mconnect/features/settings/presentation/widgets/scrobble_settings_section.dart';

/// 设置页「听歌记录同步」区块的用例。
///
/// 数据面通过 [ScrobbleSettingsController] 这个窄接口注入假实现（动作 + 快照），
/// 所以"点了几次、传了什么"不需要真 notifier 就能断言。
///
/// 但**区块自身会裸 watch `scrobbleStatus/Preferences/Secrets` 三个 provider**
/// （订阅刻意放在 widget 层，避免 provider 图成环），因此这三个 provider 仍会被
/// **真实构造**；两个 store 于是在 `_app` 里被 override 成内存实现。这不影响
/// "关闭时不发请求"那条断言 —— 它仍然是可断言的，而不是"看起来没动静"。
/// 依然完全不碰：keystore、网络、Hive。
///
/// 用例名与验收条目一一对应（默认关闭 / 切服务不丢凭据 / 凭据回填 /
/// 只提交改过的字段 / base URL 非法就地报错 / 测试连接 / 立即补交 / 授权页回退）。

const _switchKey = Key('scrobble-enabled-switch');
const _serviceKey = Key('scrobble-service-dropdown');
const _apiKeyKey = Key('scrobble-api-key-field');
const _apiSecretKey = Key('scrobble-api-secret-field');
const _sessionKeyKey = Key('scrobble-session-key-field');
const _tokenKey = Key('scrobble-token-field');
const _baseUrlKey = Key('scrobble-base-url-field');
const _saveKey = Key('scrobble-save-credentials');
const _testKey = Key('scrobble-test-connection');
const _drainKey = Key('scrobble-drain-now');
const _authKey = Key('scrobble-open-auth');
const _reauthKey = Key('scrobble-reauth-notice');

ScrobbleSettingsView _view({
  bool enabled = true,
  ScrobbleService service = ScrobbleService.lastfm,
  String? customBaseUrl,
  bool hasCredentials = true,
  bool needsReauth = false,
  int pendingCount = 0,
  String? lastError,
  String apiKey = '',
  String apiSecret = '',
  String sessionKey = '',
  String token = '',
}) {
  return ScrobbleSettingsView(
    enabled: enabled,
    service: service,
    customBaseUrl: customBaseUrl,
    hasCredentials: hasCredentials,
    needsReauth: needsReauth,
    pendingCount: pendingCount,
    lastError: lastError,
    apiKey: apiKey,
    apiSecret: apiSecret,
    sessionKey: sessionKey,
    token: token,
  );
}

class _FakeScrobbleController implements ScrobbleSettingsController {
  _FakeScrobbleController(this._view);

  ScrobbleSettingsView _view;

  int setEnabledCalls = 0;
  bool? lastEnabled;
  int setServiceCalls = 0;
  ScrobbleService? lastService;
  final List<String?> baseUrlCalls = <String?>[];

  /// 非 null 时模拟"实现侧拒绝该地址"。
  String? baseUrlResult;
  final List<Map<String, String?>> credentialCalls = <Map<String, String?>>[];
  int testConnectionCalls = 0;
  bool testConnectionResult = true;
  int drainCalls = 0;
  bool drainResult = true;
  final List<String> authorizeUrlCalls = <String>[];
  Uri? authorizeUrlResult = Uri.parse('https://example.test/authorize?api_key=x');

  /// 补交后要切换到的快照（用来验证"计数刷新"）。
  ScrobbleSettingsView? viewAfterDrain;

  @override
  ScrobbleSettingsView get view => _view;

  ScrobbleSettingsView _updated({
    bool? enabled,
    ScrobbleService? service,
    String? customBaseUrl,
    bool? hasCredentials,
    bool? needsReauth,
    int? pendingCount,
    String? lastError,
    String? apiKey,
    String? token,
  }) {
    return ScrobbleSettingsView(
      enabled: enabled ?? _view.enabled,
      service: service ?? _view.service,
      customBaseUrl: customBaseUrl ?? _view.customBaseUrl,
      hasCredentials: hasCredentials ?? _view.hasCredentials,
      needsReauth: needsReauth ?? _view.needsReauth,
      pendingCount: pendingCount ?? _view.pendingCount,
      lastError: lastError ?? _view.lastError,
      apiKey: apiKey ?? _view.apiKey,
      apiSecret: _view.apiSecret,
      sessionKey: _view.sessionKey,
      token: token ?? _view.token,
    );
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    setEnabledCalls++;
    lastEnabled = enabled;
    _view = _updated(enabled: enabled);
  }

  @override
  Future<void> setService(ScrobbleService service) async {
    setServiceCalls++;
    lastService = service;
    // 真实现会顺带 loadFor(service) 把该服务的机密读回来；假实现模拟这个结果。
    _view = _updated(
      service: service,
      apiKey: service == ScrobbleService.lastfm ? 'saved-lastfm-key' : '',
      token: service == ScrobbleService.listenbrainz ? 'saved-lb-token' : '',
    );
  }

  @override
  Future<String?> setCustomBaseUrl(String? url) async {
    baseUrlCalls.add(url);
    if (baseUrlResult == null) {
      _view = _updated(customBaseUrl: url);
    }
    return baseUrlResult;
  }

  @override
  Future<void> saveCredentials({
    String? apiKey,
    String? apiSecret,
    String? sessionKey,
    String? token,
  }) async {
    credentialCalls.add(<String, String?>{
      'apiKey': apiKey,
      'apiSecret': apiSecret,
      'sessionKey': sessionKey,
      'token': token,
    });
  }

  @override
  Future<bool> testConnection() async {
    testConnectionCalls++;
    return testConnectionResult;
  }

  @override
  Future<bool> drainNow() async {
    drainCalls++;
    final after = viewAfterDrain;
    if (after != null) _view = after;
    return drainResult;
  }

  @override
  Uri? authorizeUrl(String apiKey) {
    authorizeUrlCalls.add(apiKey);
    return authorizeUrlResult;
  }

  @override
  void refresh() {}
}

Widget _app(
  _FakeScrobbleController fake, {
  Future<bool> Function(Uri uri)? launcher,
}) {
  return ProviderScope(
    overrides: <Override>[
      // 用 `overrideWith` 而不是 `overrideWithValue`：后者在 Riverpod 后续版本里
      // 有过 deprecation 讨论，而 `overrideWith` 在 2.x/3.x 都是稳的。
      scrobbleSettingsControllerProvider.overrideWith((ref) => fake),

      // ⚠️ 这两条是"订阅移到 widget"的**代价**，不能删。
      //
      // 区块的 build 里裸 watch 了 status / preferences / secrets 三个 provider
      // （订阅刻意放在 widget 层，避免 provider 图成环），所以它们在本测试里会被
      // **真实构造**。默认的 store 实现会去碰 Hive 与平台 keystore：真实 I/O 在
      // fake-async 里以"未捕获 zone 错误"的形式冒出来，栈落在
      // `ScrobblePreferencesNotifier._load` → `scrobble_provider.dart:96`。
      // 换成内存实现后：构造照旧、异步 load 立即完成、不碰任何平台通道。
      scrobblePreferenceStoreProvider.overrideWith(
        (ref) => MemoryScrobblePreferenceStore(),
      ),
      scrobbleSecretStoreProvider.overrideWith(
        (ref) => MemoryScrobbleSecretStore(),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ScrobbleSettingsSection(launcher: launcher),
        ),
      ),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  _FakeScrobbleController fake, {
  Future<bool> Function(Uri uri)? launcher,
}) async {
  // 区块很高（开关 + 服务 + 3 个输入框 + 按钮 + 补交行），默认 800x600 的测试
  // 画布会把下半截挤到屏幕外，`tester.tap` 就会打空。给一个够高的画布。
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_app(fake, launcher: launcher));
  await tester.pump();
}

/// 让 UI 读到假实现**刚更新过的** `view`（假实现不是响应式的，重建一次即可）。
Future<void> _repump(WidgetTester tester, _FakeScrobbleController fake) async {
  await tester.pumpWidget(_app(fake));
  await tester.pump();
}

Future<void> _selectService(
  WidgetTester tester,
  ScrobbleService service,
) async {
  await tester.tap(find.byKey(_serviceKey));
  await tester.pumpAndSettle();
  // 下拉菜单渲染在 overlay 里，所以同名文本会出现两次（按钮上的当前值 + 菜单项），
  // `.last` 取的是 overlay 里的那一项。
  await tester.tap(find.text(service.label).last);
  await tester.pumpAndSettle();
}

/// 输入框里**真正显示**的文本（不是 widget 上的 initialValue）。
String _fieldText(WidgetTester tester, Key key) {
  final editable = tester.widget<EditableText>(
    find.descendant(of: find.byKey(key), matching: find.byType(EditableText)),
  );
  return editable.controller.text;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('默认关闭', () {
    testWidgets('关闭时：开关为 off，且不显示任何凭据输入 / 服务选择 / 补交按钮', (tester) async {
      final fake = _FakeScrobbleController(_view(enabled: false));
      await _pump(tester, fake);

      expect(tester.widget<SwitchListTile>(find.byKey(_switchKey)).value, isFalse);
      expect(find.byKey(_serviceKey), findsNothing);
      expect(find.byKey(_apiKeyKey), findsNothing);
      expect(find.byKey(_apiSecretKey), findsNothing);
      expect(find.byKey(_sessionKeyKey), findsNothing);
      expect(find.byKey(_tokenKey), findsNothing);
      expect(find.byKey(_baseUrlKey), findsNothing);
      expect(find.byKey(_saveKey), findsNothing);
      expect(find.byKey(_testKey), findsNothing);
      expect(find.byKey(_drainKey), findsNothing);
    });

    testWidgets('关闭时：一次请求都不发（不测试连接、不补交、不写凭据）', (tester) async {
      final fake = _FakeScrobbleController(_view(enabled: false));
      await _pump(tester, fake);
      await tester.pump();

      expect(fake.testConnectionCalls, 0);
      expect(fake.drainCalls, 0);
      expect(fake.credentialCalls, isEmpty);
      expect(fake.baseUrlCalls, isEmpty);
      expect(fake.setEnabledCalls, 0);
    });

    testWidgets('打开开关：只调 setEnabled(true)，不顺手发任何请求', (tester) async {
      final fake = _FakeScrobbleController(_view(enabled: false));
      await _pump(tester, fake);

      await tester.tap(find.byKey(_switchKey));
      await tester.pumpAndSettle();

      expect(fake.setEnabledCalls, 1);
      expect(fake.lastEnabled, isTrue);
      expect(fake.testConnectionCalls, 0);
      expect(fake.drainCalls, 0);
      expect(fake.credentialCalls, isEmpty);
      expect(fake.baseUrlCalls, isEmpty);
    });
  });

  group('服务与凭据输入', () {
    testWidgets('lastfm（usesApiKey）：显示 API Key / Secret / Session Key 与授权页按钮，不显示 token', (tester) async {
      final fake = _FakeScrobbleController(_view(service: ScrobbleService.lastfm));
      await _pump(tester, fake);

      expect(find.byKey(_apiKeyKey), findsOneWidget);
      expect(find.byKey(_apiSecretKey), findsOneWidget);
      expect(find.byKey(_sessionKeyKey), findsOneWidget);
      expect(find.byKey(_authKey), findsOneWidget);
      expect(find.byKey(_tokenKey), findsNothing);
      expect(find.byKey(_baseUrlKey), findsNothing);
    });

    testWidgets('librefm：与 lastfm 同一套输入（同属 api_sig 家族）', (tester) async {
      final fake = _FakeScrobbleController(_view(service: ScrobbleService.librefm));
      await _pump(tester, fake);

      expect(find.byKey(_apiKeyKey), findsOneWidget);
      expect(find.byKey(_sessionKeyKey), findsOneWidget);
      expect(find.byKey(_authKey), findsOneWidget);
      expect(find.byKey(_tokenKey), findsNothing);
    });

    testWidgets('listenbrainz（usesToken）：只显示 token，不显示 API Key 与授权页按钮', (tester) async {
      final fake = _FakeScrobbleController(
        _view(service: ScrobbleService.listenbrainz),
      );
      await _pump(tester, fake);

      expect(find.byKey(_tokenKey), findsOneWidget);
      expect(find.byKey(_apiKeyKey), findsNothing);
      expect(find.byKey(_apiSecretKey), findsNothing);
      expect(find.byKey(_sessionKeyKey), findsNothing);
      expect(find.byKey(_authKey), findsNothing);
      expect(find.byKey(_baseUrlKey), findsNothing);
    });

    testWidgets('maloja（usesCustomBaseUrl）：token 之外额外显示自定义 Base URL', (tester) async {
      final fake = _FakeScrobbleController(_view(service: ScrobbleService.maloja));
      await _pump(tester, fake);

      expect(find.byKey(_tokenKey), findsOneWidget);
      expect(find.byKey(_baseUrlKey), findsOneWidget);
    });

    testWidgets('已保存的凭据回填到输入框（让用户看得见"已经配过"）', (tester) async {
      final fake = _FakeScrobbleController(
        _view(
          service: ScrobbleService.lastfm,
          apiKey: 'saved-key',
          apiSecret: 'saved-secret',
          sessionKey: 'saved-sk',
        ),
      );
      await _pump(tester, fake);

      expect(_fieldText(tester, _apiKeyKey), 'saved-key');
      expect(_fieldText(tester, _apiSecretKey), 'saved-secret');
      expect(_fieldText(tester, _sessionKeyKey), 'saved-sk');
    });

    testWidgets('未配置凭据时给出"尚未配置凭据"提示', (tester) async {
      final fake = _FakeScrobbleController(
        _view(service: ScrobbleService.lastfm, hasCredentials: false),
      );
      await _pump(tester, fake);

      expect(find.text('尚未配置凭据'), findsOneWidget);
    });

    testWidgets('切换服务只调 setService，不写任何凭据（另一个服务已存的凭据不会丢）', (tester) async {
      final fake = _FakeScrobbleController(
        _view(service: ScrobbleService.lastfm, apiKey: 'saved-lastfm-key'),
      );
      await _pump(tester, fake);

      // 先在输入框里键入内容（还没点保存）
      await tester.enterText(find.byKey(_apiKeyKey), 'typed-api-key');
      await tester.pump();

      await _selectService(tester, ScrobbleService.listenbrainz);

      expect(fake.setServiceCalls, 1);
      expect(fake.lastService, ScrobbleService.listenbrainz);
      expect(
        fake.credentialCalls,
        isEmpty,
        reason: '切服务不能写凭据：空串在 ScrobbleCredentials 里意味着"删除该键"',
      );
    });

    testWidgets('切换服务后输入框换成新服务的已存凭据（listenbrainz → 显示它的 token）', (tester) async {
      final fake = _FakeScrobbleController(
        _view(service: ScrobbleService.lastfm, apiKey: 'saved-lastfm-key'),
      );
      await _pump(tester, fake);
      expect(_fieldText(tester, _apiKeyKey), 'saved-lastfm-key');

      await _selectService(tester, ScrobbleService.listenbrainz);
      await _repump(tester, fake);

      // 假实现在 setService 里把 token 设为 saved-lb-token（模拟 loadFor 的结果）
      expect(_fieldText(tester, _tokenKey), 'saved-lb-token');
      expect(find.byKey(_apiKeyKey), findsNothing);
    });
  });

  group('保存凭据', () {
    testWidgets('只提交用户改过的字段（没动过的传 null，不会覆盖已存密钥）', (tester) async {
      final fake = _FakeScrobbleController(
        _view(
          service: ScrobbleService.lastfm,
          apiKey: 'saved-key',
          apiSecret: 'saved-secret',
          sessionKey: 'saved-sk',
        ),
      );
      await _pump(tester, fake);

      // 只改 API Key 一个字段
      await tester.enterText(find.byKey(_apiKeyKey), 'new-key');
      await tester.pump();

      await tester.tap(find.byKey(_saveKey));
      await tester.pumpAndSettle();

      expect(fake.credentialCalls.length, 1);
      final call = fake.credentialCalls.single;
      expect(call['apiKey'], 'new-key');
      expect(call['apiSecret'], isNull, reason: '没动过的字段必须是 null，否则会把已存密钥抹掉');
      expect(call['sessionKey'], isNull);
      expect(call['token'], isNull);
      expect(find.text('已保存'), findsOneWidget);
    });

    testWidgets('清空某个字段 → 传空串（实现侧语义是"删除该键"）', (tester) async {
      final fake = _FakeScrobbleController(
        _view(service: ScrobbleService.lastfm, apiKey: 'saved-key'),
      );
      await _pump(tester, fake);

      await tester.enterText(find.byKey(_apiKeyKey), '');
      await tester.pump();

      await tester.tap(find.byKey(_saveKey));
      await tester.pumpAndSettle();

      expect(fake.credentialCalls.single['apiKey'], '');
    });
  });

  group('自定义 Base URL 校验', () {
    testWidgets('为空：就地报错且不保存、不发任何保存请求', (tester) async {
      final fake = _FakeScrobbleController(
        _view(service: ScrobbleService.maloja, customBaseUrl: null),
      );
      await _pump(tester, fake);

      await tester.tap(find.byKey(_saveKey));
      await tester.pump();

      expect(
        find.text('请填写实例地址（例如 https://maloja.example.com）'),
        findsOneWidget,
      );
      expect(fake.baseUrlCalls, isEmpty);
      expect(fake.credentialCalls, isEmpty);
    });

    testWidgets('非 http(s)：就地报错且不保存', (tester) async {
      final fake = _FakeScrobbleController(
        _view(service: ScrobbleService.maloja, customBaseUrl: null),
      );
      await _pump(tester, fake);

      await tester.enterText(find.byKey(_baseUrlKey), 'ftp://maloja.example.com');
      await tester.pump();
      expect(find.text('地址必须以 http:// 或 https:// 开头'), findsOneWidget);

      await tester.tap(find.byKey(_saveKey));
      await tester.pump();

      expect(fake.baseUrlCalls, isEmpty);
      expect(fake.credentialCalls, isEmpty);
    });

    testWidgets('合法 https：保存地址并提示已保存', (tester) async {
      final fake = _FakeScrobbleController(
        _view(service: ScrobbleService.maloja, customBaseUrl: null),
      );
      await _pump(tester, fake);

      await tester.enterText(
        find.byKey(_baseUrlKey),
        'https://maloja.example.com',
      );
      await tester.pump();
      expect(find.text('地址必须以 http:// 或 https:// 开头'), findsNothing);

      await tester.tap(find.byKey(_saveKey));
      await tester.pumpAndSettle();

      expect(fake.baseUrlCalls, <String?>['https://maloja.example.com']);
      expect(fake.credentialCalls.length, 1);
      expect(find.text('已保存'), findsOneWidget);
    });
  });

  group('测试连接', () {
    testWidgets('成功 → 成功 SnackBar', (tester) async {
      final fake = _FakeScrobbleController(_view());
      fake.testConnectionResult = true;
      await _pump(tester, fake);

      await tester.tap(find.byKey(_testKey));
      await tester.pumpAndSettle();

      expect(fake.testConnectionCalls, 1);
      expect(find.text('连接成功'), findsOneWidget);
    });

    testWidgets('失败 → 失败 SnackBar 且带上 lastError 文案', (tester) async {
      final fake = _FakeScrobbleController(
        _view(lastError: '凭据无效（错误码 9）'),
      );
      fake.testConnectionResult = false;
      await _pump(tester, fake);

      await tester.tap(find.byKey(_testKey));
      await tester.pumpAndSettle();

      expect(find.text('连接失败：凭据无效（错误码 9）'), findsOneWidget);
    });
  });

  group('立即补交', () {
    testWidgets('有待补交时可用：点击调一轮 drainNow 并刷新计数', (tester) async {
      final fake = _FakeScrobbleController(_view(pendingCount: 3));
      fake.viewAfterDrain = _view(pendingCount: 0);
      await _pump(tester, fake);

      expect(find.text('待补交 3 条'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(_drainKey)).onPressed, isNotNull);

      await tester.tap(find.byKey(_drainKey));
      await tester.pumpAndSettle();

      expect(fake.drainCalls, 1);
      expect(find.text('补交完成，待补交 0 条'), findsOneWidget);
    });

    testWidgets('没有待补交时禁用', (tester) async {
      final fake = _FakeScrobbleController(_view(pendingCount: 0));
      await _pump(tester, fake);

      expect(find.text('待补交 0 条'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(_drainKey)).onPressed, isNull);
    });

    testWidgets('needsReauth：显示"需要重新登录"、按钮禁用、点击不发请求', (tester) async {
      final fake = _FakeScrobbleController(
        _view(pendingCount: 5, needsReauth: true),
      );
      await _pump(tester, fake);

      expect(find.byKey(_reauthKey), findsOneWidget);
      expect(find.text('需要重新登录后才能继续提交'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(_drainKey)).onPressed, isNull);

      await tester.tap(find.byKey(_drainKey), warnIfMissed: false);
      await tester.pump();

      expect(fake.drainCalls, 0, reason: 'needsReauth 时不允许发起任何补交请求');
    });
  });

  group('打开授权页', () {
    testWidgets('打开失败（无浏览器）→ 复制链接并提示"授权链接已复制"', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final fake = _FakeScrobbleController(
        _view(service: ScrobbleService.lastfm, apiKey: 'saved-key'),
      );
      await _pump(tester, fake, launcher: (uri) async => false);

      await tester.tap(find.byKey(_authKey));
      await tester.pumpAndSettle();

      expect(find.text('授权链接已复制'), findsOneWidget);
      // URL 由 scrobble 侧构造（假实现给的是固定值），设置页只负责交给 launcher/剪贴板
      expect(fake.authorizeUrlCalls, <String>['saved-key']);
      final copied = calls
          .where((call) => call.method == 'Clipboard.setData')
          .toList();
      expect(copied, isNotEmpty);
      expect(
        (copied.first.arguments as Map<Object?, Object?>)['text'],
        fake.authorizeUrlResult.toString(),
      );
    });

    testWidgets('打开成功 → 不复制、不提示', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final fake = _FakeScrobbleController(_view(service: ScrobbleService.lastfm));
      Uri? opened;
      await _pump(
        tester,
        fake,
        launcher: (uri) async {
          opened = uri;
          return true;
        },
      );

      await tester.tap(find.byKey(_authKey));
      await tester.pumpAndSettle();

      expect(opened, fake.authorizeUrlResult);
      expect(find.text('授权链接已复制'), findsNothing);
      expect(calls.where((call) => call.method == 'Clipboard.setData'), isEmpty);
    });
  });
}
