import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mconnect/core/utils/snackbar_helper.dart';
import 'package:mconnect/features/scrobble/data/scrobble_config.dart';
import 'package:mconnect/features/scrobble/presentation/providers/scrobble_provider.dart';
import 'package:mconnect/features/settings/presentation/providers/scrobble_settings_controller.dart';
import 'package:url_launcher/url_launcher.dart';

/// 设置页的「听歌记录同步」区块（Wave 2-D scrobble 的 UI 部分）。
///
/// # 三条硬约束（都用 `test/scrobble_settings_test.dart` 钉住）
/// 1. **默认关闭**：关闭时**不显示**凭据输入；"不构造后端、不发请求"由 scrobble 侧
///    结构保证（`scrobbleBackendProvider` 在 enabled=false 时返回 null，
///    coordinator 也不 start），本 widget 只把请求挂在显式点击上。
/// 2. **切服务不丢凭据**：切换服务只调 `setService` + 机密重新载入（`loadFor`），
///    **绝不**用空串去写凭据 —— 空串在 `ScrobbleCredentials._writeOrDelete` 里
///    意味着"删除该键"。
/// 3. **非法 base URL 就地报错且不保存**：先用 `isValidScrobbleBaseUrl` 本地校验，
///    不通过就只更新 `errorText`，既不落盘也不发请求。
///
/// # 文案为什么是硬编码中文
/// `lib/l10n/**` 是 W3-D 的禁区；这一波统一入 ARB，本文件先写死中文。
///
/// # 可测性
/// 数据面全部经 [ScrobbleSettingsController]（窄接口，见 providers 目录），
/// 测试用 `overrideWith((ref) => FakeController())` 注入。
/// 「打开授权页」另有 [launcher] 注入点，避免测试真的去拉系统浏览器。
class ScrobbleSettingsSection extends ConsumerStatefulWidget {
  const ScrobbleSettingsSection({super.key, this.launcher});

  /// 打开 URL 的方式。null → `url_launcher` 的 `launchUrl`。
  /// 测试注入一个返回 false 的实现来验证 Clipboard 回退分支。
  final Future<bool> Function(Uri uri)? launcher;

  @override
  ConsumerState<ScrobbleSettingsSection> createState() =>
      _ScrobbleSettingsSectionState();
}

class _ScrobbleSettingsSectionState
    extends ConsumerState<ScrobbleSettingsSection> {
  /// 用户改过的字段值。**null 一律表示"没动过"** —— 没动过的字段在保存时会被跳过，
  /// 这样不会把已存的密钥覆盖成空串；用户主动清空则是一个空串（按约定 = 删除该键）。
  String? _apiKeyTyped;
  String? _apiSecretTyped;
  String? _sessionKeyTyped;
  String? _tokenTyped;

  /// 用户在本次会话里输入过的自定义 base URL；null = 没动过输入框。
  String? _baseUrlTyped;

  String? _baseUrlError;
  bool _busy = false;

  void _setBusy(bool value) {
    if (mounted) setState(() => _busy = value);
  }

  @override
  Widget build(BuildContext context) {
    // 显式订阅（widget 级）：状态一变就重建 UI，但**不把这条边加进
    // `scrobbleSettingsControllerProvider` 的 provider 图**。
    //
    // 早期版本由 controller 自己 `ref.watch` 这些 provider，于是 provider 图里出现
    // controller → status → coordinator → backend → preferences/secrets → controller
    // 的环；把区块挂进 `SettingsPage` 时 `PROBE S` 量到 `CircularDependencyError`，
    // 该页在区块之后的条目全部不再渲染。widget 订阅不参与 provider 图，所以
    // 订阅放在这里既能让 UI 跟着变，又不可能成环。
    ref.watch(scrobbleStatusProvider);

    // **"开没开"读 preferences，不读 `status.enabled`。**
    // `ScrobbleStatus` 里的 preferences 只有 `refresh()` 之后才会被填上，而
    // `refresh()` 会去读凭据（平台 keystore）与协调器（数据库）—— 拿它当开关的真值
    // 会变成"关闭时永远刷新不到开启"的死锁，而且默认关闭时本就不该碰那两个存储。
    // `scrobblePreferencesProvider` 自己是异步从 Hive 读的（Hive 打开着的环境里
    // 零真实 I/O），读到之后会重建这里，开关自然就对了。
    final preferences = ref.watch(scrobblePreferencesProvider);

    // 凭据只在**开启时**订阅：默认关闭时连 `scrobbleSecretsProvider` 都不要被构造
    // （它的 notifier 构造期 `unawaited(_load())` 会碰平台 keystore）。
    if (preferences.enabled) {
      ref.watch(scrobbleSecretsProvider);
    }

    // 「待补交 N 条」是 status 里非 reactive 的部分，开启后要主动问一次。
    // 用 `ref.listen(fireImmediately: true)` 而不是 initState：preferences 是**异步**
    // 载入的，initState 那一帧它多半还是"关闭"，只会在关→开时漏刷；listen 覆盖
    // "载入后本来就是开启"的情况。回调里只排帧后动作 —— refresh() 会读 provider，
    // 不能在 build 期跑。
    // No `fireImmediately`: `WidgetRef.listen` has no such parameter (only
    // `listenManual` does). It is not needed either: the preferences notifier
    // loads from Hive asynchronously, so the "stored value is enabled" case
    // arrives as a false -> true transition, which this listener does see.
    ref.listen<bool>(
      scrobblePreferencesProvider.select((prefs) => prefs.enabled),
      (previous, next) {
        if (!next) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref.read(scrobbleSettingsControllerProvider).refresh();
        });
      },
    );

    final controller = ref.watch(scrobbleSettingsControllerProvider);
    final view = controller.view;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            key: const Key('scrobble-enabled-switch'),
            secondary: const Icon(Icons.cloud_upload_outlined),
            title: const Text('听歌记录同步'),
            subtitle: const Text('把你听过的歌提交到 Last.fm / Libre.fm / ListenBrainz'),
            // 关闭时下方整块不渲染：不显示凭据输入，也就没有任何输入会触发请求。
            value: view.enabled,
            onChanged: _busy
                ? null
                : (enabled) async {
                    _setBusy(true);
                    try {
                      await controller.setEnabled(enabled);
                    } catch (error) {
                      // 吞掉并提示：这是个 fire-and-forget 的回调，
                      // 让它抛出去会变成"未捕获的异步错误"（会被崩溃上报当成崩溃）。
                      // 这里 guard 的必须是**这个 BuildContext 自己**的 mounted：
                      // `context` 是 build 的参数，不是 State.context，用 State 的
                      // `mounted` 会被 analyzer 判定为"不相关的守卫"。
                      if (context.mounted) showErrorSnackBar(context, '切换失败：$error');
                    } finally {
                      _setBusy(false);
                    }
                  },
          ),
          if (view.enabled) ..._enabledBody(controller, view),
        ],
      ),
    );
  }

  List<Widget> _enabledBody(
    ScrobbleSettingsController controller,
    ScrobbleSettingsView view,
  ) {
    /// 凭据输入框的 identity：`(字段, 服务, 已存值)` 三者任一变化就重建。
    ///
    /// 为什么不能只用固定的 `Key`：`TextFormField` 的 `initialValue` 只在它的
    /// State 首次创建时生效，而 listenbrainz→maloja 这类切换会用同一个 key 复用到
    /// 同一个 element，于是 maloja 下面会显示 listenbrainz 的 token。
    /// 注意 key 里放的是 `Object.hash(...)`（不是密文本身），避免密钥出现在调试输出里。
    Key secretFieldKey(String field, String value) =>
        ValueKey<Object>(Object.hash(field, view.service.id, value));

    return <Widget>[
      ListTile(
        leading: const Icon(Icons.dns_outlined),
        title: const Text('服务'),
        subtitle: view.hasCredentials ? null : const Text('尚未配置凭据'),
        trailing: DropdownButton<ScrobbleService>(
          key: const Key('scrobble-service-dropdown'),
          value: view.service,
          onChanged: _busy
              ? null
              : (service) async {
                  if (service == null || service == view.service) return;
                  _setBusy(true);
                  try {
                    // 只切服务 + 把该服务的已存机密读回来（内部不含任何写入）。
                    await controller.setService(service);
                    if (!mounted) return;
                    // 切换后把"用户改过"的痕迹清掉：输入框要显示的是新服务的已存值。
                    setState(() {
                      _apiKeyTyped = null;
                      _apiSecretTyped = null;
                      _sessionKeyTyped = null;
                      _tokenTyped = null;
                      _baseUrlTyped = null;
                      _baseUrlError = null;
                    });
                  } catch (error) {
                    // 同上：fire-and-forget 回调不能让异常逃逸。
                    if (mounted) showErrorSnackBar(context, '切换服务失败：$error');
                  } finally {
                    _setBusy(false);
                  }
                },
          items: [
            for (final service in ScrobbleService.values)
              DropdownMenuItem<ScrobbleService>(
                value: service,
                child: Text(service.label),
              ),
          ],
        ),
      ),
      if (view.service.usesApiKey) ...<Widget>[
        _textField(
          identityKey: secretFieldKey('api-key', view.apiKey),
          fieldKey: const Key('scrobble-api-key-field'),
          label: 'API Key',
          helper: '${view.service.label} 应用级 API Key',
          initialValue: view.apiKey,
          onChanged: (value) => _apiKeyTyped = value,
        ),
        _textField(
          identityKey: secretFieldKey('api-secret', view.apiSecret),
          fieldKey: const Key('scrobble-api-secret-field'),
          label: 'API Secret',
          helper: '与 API Key 配对，用于请求签名',
          initialValue: view.apiSecret,
          onChanged: (value) => _apiSecretTyped = value,
        ),
        _textField(
          identityKey: secretFieldKey('session-key', view.sessionKey),
          fieldKey: const Key('scrobble-session-key-field'),
          label: 'Session Key（sk）',
          helper: '授权后获得；只保存在本机安全存储',
          initialValue: view.sessionKey,
          onChanged: (value) => _sessionKeyTyped = value,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('scrobble-open-auth'),
              onPressed: _busy
                  ? null
                  : () => _openAuthorizationPage(controller, view),
              icon: const Icon(Icons.open_in_new),
              label: const Text('打开授权页'),
            ),
          ),
        ),
      ],
      if (view.service.usesToken)
        _textField(
          identityKey: secretFieldKey('token', view.token),
          fieldKey: const Key('scrobble-token-field'),
          label: 'User Token',
          helper: '在服务站点的设置页复制',
          initialValue: view.token,
          onChanged: (value) => _tokenTyped = value,
        ),
      if (view.service.usesCustomBaseUrl) _baseUrlField(view),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          children: <Widget>[
            FilledButton.tonal(
              key: const Key('scrobble-save-credentials'),
              onPressed: _busy ? null : () => _save(controller, view),
              child: const Text('保存'),
            ),
            FilledButton(
              key: const Key('scrobble-test-connection'),
              onPressed: _busy ? null : () => _testConnection(controller),
              child: const Text('测试连接'),
            ),
          ],
        ),
      ),
      ListTile(
        key: const Key('scrobble-pending-count'),
        leading: const Icon(Icons.sync_outlined),
        title: Text('待补交 ${view.pendingCount} 条'),
        subtitle: view.needsReauth
            ? const Text(
                '需要重新登录后才能继续提交',
                key: Key('scrobble-reauth-notice'),
              )
            : null,
        trailing: FilledButton(
          key: const Key('scrobble-drain-now'),
          // needsReauth 时**禁用**（连点击都不给，自然不会发请求）；
          // 没有待补交时同样不可用。
          onPressed: (view.pendingCount > 0 && !view.needsReauth && !_busy)
              ? () => _drainNow(controller)
              : null,
          child: const Text('立即补交'),
        ),
      ),
      if (view.lastError != null && view.lastError!.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            '上次错误：${view.lastError}',
            key: const Key('scrobble-last-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        )
      else
        const SizedBox(height: 8),
    ];
  }

  /// 一个凭据输入框。
  ///
  /// `initialValue` 来自已存机密：让用户看得见"已经配过"（内容被 obscureText 遮住）。
  /// `identityKey` 挂在包一层的 `Padding` 上，用来在"换了服务 / 已存值变了"时
  /// 重建 FormField 的内部 State；`fieldKey` 是测试用的稳定 Key（不能被 identity 影响）。
  Widget _textField({
    required Key identityKey,
    required Key fieldKey,
    required String label,
    required String helper,
    required String initialValue,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      key: identityKey,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: TextFormField(
        key: fieldKey,
        initialValue: initialValue,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(labelText: label, helperText: helper),
        onChanged: onChanged,
      ),
    );
  }

  /// 自定义 base URL（只有 `usesCustomBaseUrl` 的服务会渲染它，目前是 Maloja）。
  Widget _baseUrlField(ScrobbleSettingsView view) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: TextFormField(
        key: const Key('scrobble-base-url-field'),
        initialValue: view.customBaseUrl ?? '',
        decoration: InputDecoration(
          labelText: '自定义 Base URL',
          helperText: '例如 https://maloja.example.com',
          errorText: _baseUrlError,
        ),
        onChanged: _onBaseUrlChanged,
      ),
    );
  }

  void _onBaseUrlChanged(String value) {
    _baseUrlTyped = value;
    final trimmed = value.trim();
    String? error;
    if (trimmed.isEmpty) {
      error = '请填写实例地址（例如 https://maloja.example.com）';
    } else if (!isValidScrobbleBaseUrl(trimmed)) {
      error = '地址必须以 http:// 或 https:// 开头';
    }
    if (error != _baseUrlError) {
      setState(() => _baseUrlError = error);
    }
  }

  Future<void> _save(
    ScrobbleSettingsController controller,
    ScrobbleSettingsView view,
  ) async {
    // 需求 3：非法地址**就地报错且不保存**。onChanged 已经报过错，
    // 这里再挡一次是因为用户可能没改输入框直接点了保存。
    if (view.service.usesCustomBaseUrl) {
      final candidate = _baseUrlTyped ?? view.customBaseUrl;
      if (candidate == null || candidate.trim().isEmpty) {
        setState(() {
          _baseUrlError = '请填写实例地址（例如 https://maloja.example.com）';
        });
        return;
      }
      if (!isValidScrobbleBaseUrl(candidate)) {
        setState(() => _baseUrlError = '地址必须以 http:// 或 https:// 开头');
        return;
      }
    }

    _setBusy(true);
    try {
      if (view.service.usesCustomBaseUrl && _baseUrlTyped != null) {
        final error = await controller.setCustomBaseUrl(_baseUrlTyped);
        if (!mounted) return;
        if (error != null) {
          setState(() => _baseUrlError = error);
          showErrorSnackBar(context, error);
          return;
        }
      }

      // 只提交"用户改过"的字段（null = 跳过）。这一点很关键：把没动过的字段
      // 当空串写下去，会把已存的密钥抹掉。
      await controller.saveCredentials(
        apiKey: _apiKeyTyped,
        apiSecret: _apiSecretTyped,
        sessionKey: _sessionKeyTyped,
        token: _tokenTyped,
      );
      if (!mounted) return;
      showSuccessSnackBar(context, '已保存');
    } catch (error) {
      if (!mounted) return;
      showErrorSnackBar(context, '保存失败：$error');
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _testConnection(ScrobbleSettingsController controller) async {
    _setBusy(true);
    try {
      final ok = await controller.testConnection();
      if (!mounted) return;
      // 用**新实例**读文案：refresh() 之后旧实例里的快照可能已经过期。
      final fresh = ref.read(scrobbleSettingsControllerProvider).view;
      if (ok) {
        showSuccessSnackBar(context, '连接成功');
      } else {
        showErrorSnackBar(context, '连接失败：${fresh.lastError ?? '未知错误'}');
      }
    } catch (error) {
      if (!mounted) return;
      showErrorSnackBar(context, '连接失败：$error');
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _drainNow(ScrobbleSettingsController controller) async {
    _setBusy(true);
    try {
      final ok = await controller.drainNow();
      if (!mounted) return;
      final fresh = ref.read(scrobbleSettingsControllerProvider).view;
      if (ok) {
        showSuccessSnackBar(context, '补交完成，待补交 ${fresh.pendingCount} 条');
      } else {
        showErrorSnackBar(context, '补交失败：${fresh.lastError ?? '未知错误'}');
      }
    } catch (error) {
      if (!mounted) return;
      showErrorSnackBar(context, '补交失败：$error');
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _openAuthorizationPage(
    ScrobbleSettingsController controller,
    ScrobbleSettingsView view,
  ) async {
    // URL 由 scrobble 侧构造（`scrobbleAuthorizeUrl`），设置页不自己拼字符串；
    // apiKey 优先用用户刚输入的，其次用已保存的。
    final uri = controller.authorizeUrl(_apiKeyTyped ?? view.apiKey);
    if (uri == null) return;

    bool opened = false;
    try {
      final launcher = widget.launcher;
      opened = launcher != null
          ? await launcher(uri)
          : await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!mounted) return;
    if (opened) return;

    // 没有浏览器可用（Windows 上常见，或 Android 上被拦截）时回退为复制链接，
    // 用户至少能把它贴到别处打开 —— 与设置页「导出诊断日志」的回退同构。
    await Clipboard.setData(ClipboardData(text: uri.toString()));
    if (!mounted) return;
    showInfoSnackBar(context, '授权链接已复制');
  }
}
