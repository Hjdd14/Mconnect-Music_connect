import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mconnect/features/scrobble/data/scrobble_config.dart';
import 'package:mconnect/features/scrobble/presentation/providers/scrobble_provider.dart';

/// 设置页「听歌记录同步」区块看到的一份只读快照。
///
/// 为什么不直接暴露 `ScrobbleStatus`：那是 scrobble 侧的模型，字段会随实现演进。
/// 设置页只需要下面这些已经稳定的量；把适配收在
/// [RiverpodScrobbleSettingsController] 一个类里，scrobble 侧改字段名时只有那一个
/// 类需要跟着改，UI 与用例都不动。
class ScrobbleSettingsView {
  const ScrobbleSettingsView({
    required this.enabled,
    required this.service,
    this.customBaseUrl,
    this.hasCredentials = false,
    this.needsReauth = false,
    this.pendingCount = 0,
    this.lastError,
    this.apiKey = '',
    this.apiSecret = '',
    this.sessionKey = '',
    this.token = '',
  });

  /// 默认关闭。**关闭时设置页不显示凭据输入**（provider 层已经保证不构造后端、
  /// 不发请求 —— 见 `scrobbleBackendProvider` 在 enabled=false 时返回 null）。
  final bool enabled;

  final ScrobbleService service;

  /// 用户填的自定义 base URL（未填为 null）。它是**全局一个**字段
  /// （`ScrobblePreferences.customBaseUrl`），UI 只在
  /// `service.usesCustomBaseUrl`（目前仅 Maloja）时显示它。
  final String? customBaseUrl;

  /// 当前服务的凭据是否齐全（用于"尚未配置"提示）。
  final bool hasCredentials;

  /// 凭据被服务端拒绝（Last.fm 错误码 9 / HTTP 401 之类）→ 显示
  /// 「需要重新登录」并**禁止**再发请求。
  final bool needsReauth;

  /// 待补交条数（用于「待补交 N 条」与「立即补交」的可用性）。
  final int pendingCount;

  /// 最近一次失败文案（「测试连接」失败时显示它）。
  final String? lastError;

  /// 已保存的凭据。用来喂输入框的 `initialValue`：让用户看得见"已经配过"，
  /// 而不是面对三个永远空着的框（obscureText 会遮住内容）。
  final String apiKey;
  final String apiSecret;
  final String sessionKey;
  final String token;
}

/// 设置页与 scrobble 实现之间的**窄接口**。
///
/// 存在的唯一理由是**可测**：真实实现跨两个 notifier（偏好 / 机密）与平台存储，
/// 而 widget 测试需要一个十几行的假对象。UI 只依赖这个接口。
abstract class ScrobbleSettingsController {
  /// 当前快照。实现方保证它是一次 **build 期的捕获**（不持有活 Ref），
  /// 所以异步动作之后仍可安全读取。
  ScrobbleSettingsView get view;

  Future<void> setEnabled(bool enabled);

  /// 切服务。实现方要负责让机密随之重新载入（`loadFor`），
  /// 但**绝不能**把凭据写成空值 —— 另一个服务已存的凭据必须原样留在 keystore 里。
  Future<void> setService(ScrobbleService service);

  /// 保存自定义 base URL。返回 **null = 成功**；返回**非 null = 就地显示的错误文案**。
  Future<String?> setCustomBaseUrl(String? url);

  /// 保存凭据。**null = 用户没动过这个字段（不要写）**；
  /// 非 null（含空串）= 用户改过 → 交给实现写入（按约定空串 = 删除该键）。
  /// 这个区分是必要的：把没动过的字段当空串写下去，会把已存的密钥抹掉。
  Future<void> saveCredentials({
    String? apiKey,
    String? apiSecret,
    String? sessionKey,
    String? token,
  });

  /// 测试连接。false 时 UI 用快照里的 `lastError` 作为失败文案。
  Future<bool> testConnection();

  /// 立即补交一轮。返回 false 表示这一轮以**致命失败**结束（例如凭据被拒）。
  Future<bool> drainNow();

  /// 授权页 URL（由 scrobble 侧构造，设置页不自己拼字符串）。
  /// [apiKey] 用用户当前输入或已保存的值。返回 null → 该服务没有授权页。
  Uri? authorizeUrl(String apiKey);

  /// 让快照重新取值（补交/测试连接之后调用，刷新「待补交 N 条」）。
  void refresh();
}

/// 生产实现：把 scrobble 侧的 provider 适配成上面的窄接口。
///
/// 这是**唯一** import `scrobble_provider.dart` 的地方（测试里的假实现当然不算）。
///
/// 生命周期与两个刻意的选择：
/// * `_status` / `_preferences` / `_secrets` 是 provider build 时捕获的快照，
///   `view` 只读它们（不碰 `Ref`），所以异步动作之后仍能安全读文案；
/// * 刷新用 **notifier 的 `refresh()`**，不是 `ref.invalidate(scrobbleStatusProvider)`
///   —— 后者会把 `StateNotifierProvider` 的 notifier 整个重建、状态退回初始值，
///   而 `refresh()` 才是 scrobble 侧提供的正确刷新方式；
/// * 机密 setter 在**另一个** notifier 上（两半来自不同存储：Hive vs keystore），
///   UI 侧的输入框因此要跟着 `scrobbleSecretsProvider` 重建。
class RiverpodScrobbleSettingsController implements ScrobbleSettingsController {
  RiverpodScrobbleSettingsController(
    this._ref,
    this._status,
    this._preferences,
    this._secrets,
    this._backendLastErrorOf,
  );

  final Ref _ref;
  final ScrobbleStatus _status;
  final ScrobblePreferences _preferences;
  final ScrobbleSecrets _secrets;

  /// A closure, not a `String?`: reading `backendLastError` goes through
  /// `scrobbleBackendProvider`, and doing that **eagerly inside this provider's
  /// build** re-entered the build (Riverpod reports `CircularDependencyError`,
  /// and the stack shows this very line repeatedly). Deferring the read to the
  /// moment the UI asks for `view` keeps it outside the provider build.
  final String? Function() _backendLastErrorOf;

  @override
  ScrobbleSettingsView get view => ScrobbleSettingsView(
    enabled: _status.enabled,
    service: _status.service,
    customBaseUrl: _preferences.customBaseUrl,
    hasCredentials: _status.hasCredentials,
    needsReauth: _status.needsReauth,
    pendingCount: _status.pendingCount,
    // transport 自己的措辞优先（`backendLastError`），状态里的 lastError 兜底。
    lastError: _status.lastError ?? _backendLastErrorOf(),
    apiKey: _secrets.apiKey,
    apiSecret: _secrets.apiSecret,
    sessionKey: _secrets.sessionKey,
    token: _secrets.token,
  );

  @override
  Future<void> setEnabled(bool enabled) async {
    await _ref.read(scrobblePreferencesProvider.notifier).setEnabled(enabled);
    refresh();
  }

  @override
  Future<void> setService(ScrobbleService service) async {
    await _ref.read(scrobblePreferencesProvider.notifier).setService(service);
    // 机密是**按服务**存的：切服务后把该服务的已存凭据读回来喂输入框。
    // 这一步不做任何写入，所以另一个服务的凭据不会丢。
    await _ref.read(scrobbleSecretsProvider.notifier).loadFor(service);
    refresh();
  }

  @override
  Future<String?> setCustomBaseUrl(String? url) async {
    final ok = await _ref
        .read(scrobblePreferencesProvider.notifier)
        .setCustomBaseUrl(url);
    refresh();
    return ok ? null : '无法保存该地址';
  }

  @override
  Future<void> saveCredentials({
    String? apiKey,
    String? apiSecret,
    String? sessionKey,
    String? token,
  }) async {
    final secrets = _ref.read(scrobbleSecretsProvider.notifier);
    // null = 用户没动过 → 跳过，避免把已存的值抹成空串。
    if (apiKey != null) await secrets.setApiKey(apiKey);
    if (apiSecret != null) await secrets.setApiSecret(apiSecret);
    if (sessionKey != null) await secrets.setSessionKey(sessionKey);
    if (token != null) await secrets.setToken(token);
    refresh();
  }

  @override
  Future<bool> testConnection() async {
    final ok = await _ref
        .read(scrobblePreferencesProvider.notifier)
        .testConnection();
    refresh();
    return ok;
  }

  @override
  Future<bool> drainNow() async {
    final outcome = await _ref.read(scrobbleStatusProvider.notifier).drainNow();
    refresh();
    // null = 这一轮什么都没做（例如没配置），按失败呈现，文案由 lastError 决定。
    return outcome != null && !outcome.fatal;
  }

  @override
  Uri? authorizeUrl(String apiKey) => scrobbleAuthorizeUrl(
    service: _status.service,
    apiKey: apiKey,
    preferences: _preferences,
  );

  @override
  void refresh() {
    // 不能用 invalidate：那会重建 notifier 并丢掉它的内存状态。
    unawaited(_ref.read(scrobbleStatusProvider.notifier).refresh());
  }
}

/// 设置页的注入点。测试用
/// `overrideWith((ref) => FakeController())` 替换它
/// （见 `test/scrobble_settings_test.dart`）。
final scrobbleSettingsControllerProvider = Provider<ScrobbleSettingsController>(
  (ref) => RiverpodScrobbleSettingsController(
    ref,
    ref.watch(scrobbleStatusProvider),
    ref.watch(scrobblePreferencesProvider),
    ref.watch(scrobbleSecretsProvider),
    // A closure: see [_backendLastErrorOf]. Reading it eagerly here made the
    // provider's own build re-enter itself.
    () => ref.read(scrobblePreferencesProvider.notifier).backendLastError,
  ),
);
