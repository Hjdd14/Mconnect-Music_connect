import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mconnect/features/scrobble/data/scrobble_config.dart';
import 'package:mconnect/features/scrobble/presentation/providers/scrobble_provider.dart';

/// 设置页「听歌记录同步」区块看到的一份只读快照。
///
/// 为什么不直接暴露 `ScrobbleStatus`：那是 scrobble 侧的模型，字段会随实现演进。
/// 设置页只需要下面这些稳定的量；把适配收在
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

  /// 默认关闭。**关闭时设置页不显示凭据输入**（provider 层已保证 enabled=false 时
  /// `scrobbleBackendProvider` 返回 null、coordinator 不 start，即不构造后端、不发请求）。
  final bool enabled;

  final ScrobbleService service;

  /// 用户填的自定义 base URL（未填为 null）。它是全局一个字段
  /// （`ScrobblePreferences.customBaseUrl`），UI 只在 `service.usesCustomBaseUrl` 时显示。
  final String? customBaseUrl;

  /// 当前服务的凭据是否齐全（用于「尚未配置凭据」提示）。
  final bool hasCredentials;

  /// 凭据被服务端拒绝 → 显示「需要重新登录」并禁止再发请求。
  final bool needsReauth;

  /// 待补交条数（用于「待补交 N 条」与「立即补交」的可用性）。
  final int pendingCount;

  /// 最近一次失败文案（「测试连接」失败时显示它）。
  final String? lastError;

  /// 已保存的凭据，用来喂输入框的 `initialValue`（obscureText 遮住内容）。
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
  /// 当前快照。实现方保证它是**延迟读**（每次调用取最新值、不持有活快照），
  /// 所以异步动作之后仍能安全读到新文案。
  ScrobbleSettingsView get view;

  Future<void> setEnabled(bool enabled);

  /// 切服务。实现方负责让机密随之重新载入（`loadFor`），
  /// 但**绝不能**把凭据写成空值 —— 另一个服务已存的凭据必须原样留在 keystore 里。
  Future<void> setService(ScrobbleService service);

  /// 保存自定义 base URL。返回 **null = 成功**；返回**非 null = 就地显示的错误文案**。
  Future<String?> setCustomBaseUrl(String? url);

  /// 保存凭据。**null = 用户没动过这个字段（不要写）**；
  /// 非 null（含空串）= 用户改过 → 交给实现写入（按约定空串 = 删除该键）。
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
  Uri? authorizeUrl(String apiKey);

  /// 让快照重新取值（补交/测试连接之后调用，刷新「待补交 N 条」）。
  void refresh();
}

/// 生产实现：把 scrobble 侧的 provider 适配成上面的窄接口。
///
/// 这是**唯一** import `scrobble_provider.dart` 的地方（测试里的假实现当然不算）。
///
/// # 这个类现在的形状是被一次实测故障决定的，**别再改回去**
/// 早期版本在 `scrobbleSettingsControllerProvider` 的 build 里
/// `ref.watch` 了 status/preferences/secrets 三份状态，并在 build 期**即时**读了一次
/// `backendLastError`（它会 `read(scrobbleBackendProvider)`）。于是 provider 图里出现了
/// `scrobbleSettingsControllerProvider → scrobbleStatusProvider → coordinator →
/// backend → preferences/secrets → 回到 controller` 的环。把区块挂进 `SettingsPage`
/// 的 ListView 时，`PROBE S`（`test/scrobble_settings_probe_test.dart`）量到：
/// ```
/// takeException=CircularDependencyError
/// section=1 audio=1 backup=0 diagnostics=0
/// ```
/// 即**区块自身的 build 抛异常、它后面的条目不再渲染**（"懒构建/滚动窗口"的解释
/// 已被证伪：滚一下也不会出现）。
///
/// 现在的形状把**所有 scrobble 依赖都变成延迟读**：
/// * 本 provider 的 build **不 watch 任何 scrobble provider**（只有 `ref` 本身）⇒
///   它在 provider 图里是"无边"的，环不可能存在；
/// * `view` 在**被 UI 读取时**才 `read` 那三份状态（`read` 不建立依赖边）；
/// * 订阅交给 **widget**：`ScrobbleSettingsSection.build` 里显式
///   `ref.watch(...)` —— widget 订阅不参与 provider 图，所以不会成环；
/// * 动作全部是 `read` + 调用，同样不引入边。
class RiverpodScrobbleSettingsController implements ScrobbleSettingsController {
  RiverpodScrobbleSettingsController(this._ref);

  final Ref _ref;

  @override
  ScrobbleSettingsView get view {
    final status = _ref.read(scrobbleStatusProvider);

    // **"开没开"读 preferences，不读 `status.enabled`。**
    //
    // `ScrobbleStatus` 里的 `preferences` 只在 `ScrobbleStatusNotifier.refresh()` 之后
    // 才被填上，而 `refresh()` 会去读凭据（平台 keystore）与协调器（数据库）。拿它当
    // 开关的真值来源会形成死锁：状态永远是"关闭" ⇒ 谁都不会去 refresh ⇒ 开关永远显示关。
    // `ScrobblePreferencesNotifier` 自己异步从 Hive 读，读到就重建 UI，不需要任何 refresh。
    //
    // 顺带的好处：默认关闭（绝大多数人、以及所有"pump 一下设置页"的 widget 测试）时
    // **凭据 provider 根本不会被构造** —— 它的 notifier 构造期 `unawaited(_load())`
    // 会碰平台 keystore，而关闭状态下没有任何理由碰它。
    final preferences = _ref.read(scrobblePreferencesProvider);
    if (!preferences.enabled) {
      return ScrobbleSettingsView(
        enabled: false,
        service: preferences.service,
        hasCredentials: status.hasCredentials,
        needsReauth: status.needsReauth,
        pendingCount: status.pendingCount,
        lastError: status.lastError,
      );
    }

    final secrets = _ref.read(scrobbleSecretsProvider);
    return ScrobbleSettingsView(
      enabled: true,
      service: preferences.service,
      // customBaseUrl 不在 ScrobbleStatus 里（那是"要不要补交"的快照），
      // 它属于偏好设置 —— 从 preferences 取，语义更准。
      customBaseUrl: preferences.customBaseUrl,
      hasCredentials: status.hasCredentials,
      needsReauth: status.needsReauth,
      pendingCount: status.pendingCount,
      // 只读 status：`status.lastError` 已由 `ScrobbleStatusNotifier.refresh()`
      // 从 coordinator 取好（它带的就是传输层的措辞）。
      // 这里**不再**去读 backend —— 那正是 `CircularDependencyError` 的成因：
      // `scrobbleBackendProvider` watch 了 preferences，而从 preferences notifier
      // 里反读 backend 就成环。只把调用推迟到闭包里并不能拆环（试过了）。
      lastError: status.lastError,
      apiKey: secrets.apiKey,
      apiSecret: secrets.apiSecret,
      sessionKey: secrets.sessionKey,
      token: secrets.token,
    );
  }


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
    // 从 status notifier 走，而不是 preferences notifier：后者的 `_ref` 就是
    // `scrobblePreferencesProvider`，反读 backend 会成环（见类注释与真机日志）。
    final ok = await _ref.read(scrobbleStatusProvider.notifier).testConnection();
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
  Uri? authorizeUrl(String apiKey) {
    final preferences = _ref.read(scrobblePreferencesProvider);
    return scrobbleAuthorizeUrl(
      service: preferences.service,
      apiKey: apiKey,
      preferences: preferences,
    );
  }

  @override
  void refresh() {
    // 不能用 invalidate：那会重建 notifier 并丢掉它的内存状态；
    // `refresh()` 才是 scrobble 侧提供的正确刷新方式 —— 它更新状态后，
    // widget 那侧的 `ref.watch(scrobbleStatusProvider)` 会重建 UI。
    unawaited(_ref.read(scrobbleStatusProvider.notifier).refresh());
  }
}

/// 设置页的注入点。测试用 `overrideWith((ref) => FakeController())` 替换它
/// （见 `test/scrobble_settings_test.dart`）。
///
/// **build 里不 watch 任何 scrobble provider** —— 刻意如此，见
/// [RiverpodScrobbleSettingsController] 的类注释（CircularDependencyError）。
/// 订阅由 `ScrobbleSettingsSection` 在 widget 层做。
final scrobbleSettingsControllerProvider = Provider<ScrobbleSettingsController>(
  (ref) => RiverpodScrobbleSettingsController(ref),
);