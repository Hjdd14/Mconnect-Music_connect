import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import 'widget_actions.dart';
import 'widget_state.dart';

/// 错误上报口（与 `DiagnosticsService.recordError(String, Object, StackTrace)` 同形）。
typedef WidgetErrorSink = void Function(
  String message,
  Object error,
  StackTrace stack,
);

/// 小组件桥的唯一入口（facade）。
///
/// # 为什么必须有这一层
/// `home_widget` 的 `pubspec.yaml` 里 `flutter.plugin.platforms` **只声明 android 与
/// ios**。后果是两句话：
/// * **Windows 不会编译失败**（插件不参与 Windows 构建，没有任何原生代码被编译）；
/// * 但在 Windows 上调用任何 `HomeWidget.*` 会抛 `MissingPluginException`。
///
/// 所以"非 Android 上是安全 no-op"不是保险，而是**结构要求**：本类里每一处插件调用
/// 都在 `if (!isSupported) return ...;` 之后，`test/widget_bridge_test.dart` 用
/// [pluginCallCount] 把它钉住（在 Windows 上跑一遍，计数必须为 0）。
///
/// # 数据流
/// ```
/// 播放器状态变化 → WidgetSnapshot → saveWidgetData(SharedPreferences)
///                                   + updateWidget() 让桌面重绘
/// 桌面点击 → (LAUNCH action) → WidgetBridge.dispatch(Uri) → 动作派发
///           (媒体键广播)      → 由原生直接驱动 MediaSession，不经过这里
/// ```
/// **进程被杀**时小组件照常显示：原生 `onUpdate(..., widgetData)` 直接读那份
/// SharedPreferences，与 Flutter 进程无关。
class WidgetBridge {
  WidgetBridge._();

  /// 桌面端 widget receiver 的类名（`MconnectWidgetProvider` 的 Kotlin 类名）。
  static const String androidProviderName = 'MconnectWidgetProvider';

  /// 全限定类名。插件在 Android 上优先用 `qualifiedAndroidName`，两个都给是为了
  /// 兼容不同版本的解析顺序（`qualifiedAndroidName ?? androidName ?? name`）。
  static const String qualifiedAndroidProviderName =
      'com.mconnect.mconnect.MconnectWidgetProvider';

  /// 平台探测。测试用 `WidgetBridge.platformProbe = () => TargetPlatform.windows`
  /// 假装在桌面端，从而在不依赖插件的前提下验证 no-op 语义。
  @visibleForTesting
  static TargetPlatform Function() platformProbe = () => defaultTargetPlatform;

  /// 插件调用计数：**只在真的要碰插件之前**自增。
  /// Windows 用例断言它保持 0 —— 这是"安全 no-op"的结构性证据，而不是"看起来没报错"。
  @visibleForTesting
  static int pluginCallCount = 0;

  /// 错误上报（main.dart 注入 `diagnostics.recordError`）。为 null 时只 debugPrint。
  @visibleForTesting
  static WidgetErrorSink? errorSink;

  /// 传输类动作的执行钩子。由 `widget_playback_adapter.dart` 安装，
  /// 这样本文件**不需要 import `lib/features/player/**`**：那一层正在被 W2-A/W2-B 改动，
  /// 依赖面越小越好。
  static void Function(WidgetAction action, ProviderContainer container)?
  transportHandler;

  /// 导航类动作的执行钩子（默认用全局 router）。同样是可替换的注入点。
  static void Function(WidgetAction action)? navigationHandler;

  /// 是否支持（唯一决定"要不要碰插件"的开关）。
  static bool get isSupported =>
      !kIsWeb && platformProbe() == TargetPlatform.android;

  static bool _initialized = false;
  static Uri? _initialUri;
  static ProviderContainer? _container;
  static StreamSubscription<Uri?>? _clickSubscription;
  static WidgetSnapshot? _lastPublished;

  /// 最近一次写入是否成功（诊断用；也让"没桌面组件时跳过写盘"可观测）。
  static bool get isInitialized => _initialized;

  /// 冷启动时由小组件带来的那个 URI（读一次即清空，避免被消费两遍）。
  static Uri? takeInitialUri() {
    final uri = _initialUri;
    _initialUri = null;
    return uri;
  }

  /// 初始化。**必须在 `runApp` 之前调用一次**（`lib/main.dart` 里那一处）。
  ///
  /// 语义：
  /// * 幂等 —— 重复调用直接返回；
  /// * 非 Android 上立即返回，**不触碰任何插件 API**；
  /// * 任何异常都被吞掉并上报：小组件是锦上添花，绝不允许它拖垮启动。
  static Future<void> initialize({WidgetErrorSink? onError}) async {
    if (onError != null) errorSink = onError;
    if (_initialized) return;
    // 先置位：即使下面抛异常，也不会被反复重试（重试只会重复失败）。
    _initialized = true;

    if (!isSupported) {
      // Windows / 桌面：home_widget 没有实现，走到这里就结束。
      debugPrint(
        'WidgetBridge: 当前平台不支持桌面小组件（home_widget 只注册 android+ios），'
        '已按 no-op 处理。',
      );
      return;
    }

    try {
      pluginCallCount++;
      _initialUri = await HomeWidget.initiallyLaunchedFromHomeWidget();

      pluginCallCount++;
      _clickSubscription = HomeWidget.widgetClicked.listen(
        _deliver,
        onError: (Object error, StackTrace stack) =>
            _report('小组件点击流异常', error, stack),
      );
    } catch (error, stack) {
      _report('WidgetBridge.initialize 失败（已忽略）', error, stack);
    }
  }

  /// 把 [ProviderContainer] 接进来（由 `WidgetBridgeObserver` 在第一个 provider
  /// 建立时调用）。它同时是"读取播放器状态"和"派发控制动作"的凭据。
  static void attach(ProviderContainer container) {
    _container ??= container;
  }

  /// 处理冷启动时带的那个 URI。必须等首帧之后再做，否则 `GoRouter` 还没挂到
  /// widget 树上，`go()` 会抛 `GoError: There is nothing to pop` 之类的错。
  static Future<void> deliverInitial() async {
    final uri = takeInitialUri();
    if (uri == null) return;
    final binding = WidgetsBinding.instance;
    // addPostFrameCallback 要求已经有一帧在排队；main() 里已 ensureInitialized，
    // 但保险起见先 scheduleFrame，避免"首帧永远不来 → 冷启动点击被吞"。
    binding.scheduleFrame();
    binding.addPostFrameCallback((_) {
      _deliver(uri);
    });
  }

  /// 推一份快照到共享存储 + 让桌面重绘。
  ///
  /// * 非 Android：直接返回；
  /// * 与上次完全相同：直接返回（挡住播放进度 tick）；
  /// * 封面走 `saveImage`（网络图先解码成 PNG 落到共享目录，再把**绝对路径**写进
  ///   `coverPath`）；失败就当没有封面，绝不让它影响文字与按钮。
  static Future<void> publish(WidgetSnapshot snapshot) async {
    if (!isSupported) return;
    if (_lastPublished == snapshot) return;
    _lastPublished = snapshot;

    try {
      // 只有桌面上真的摆了组件才值得写盘 + IPC 重绘。
      if (!await _hasPinnedWidget()) return;

      pluginCallCount++;
      await HomeWidget.saveWidgetData<String>(
        WidgetDataKeys.title,
        snapshot.songName ?? '',
      );
      pluginCallCount++;
      await HomeWidget.saveWidgetData<String>(
        WidgetDataKeys.artist,
        snapshot.artistNames ?? '',
      );
      pluginCallCount++;
      await HomeWidget.saveWidgetData<bool>(
        WidgetDataKeys.isPlaying,
        snapshot.isPlaying,
      );
      pluginCallCount++;
      await HomeWidget.saveWidgetData<bool>(
        WidgetDataKeys.hasSong,
        snapshot.hasSong,
      );

      // 封面：先落盘（saveImage 会把路径写进同一个 key），再触发重绘。
      final coverUrl = snapshot.coverPath;
      if (coverUrl != null && coverUrl.isNotEmpty && !_coverIsLocalFile(coverUrl)) {
        try {
          pluginCallCount++;
          await HomeWidget.saveImage(
            WidgetDataKeys.coverPath,
            NetworkImage(coverUrl),
          );
        } catch (error, stack) {
          // 网络/解码失败 → 明确的"没有封面"，不要让上一次的封面残留
          _report('小组件封面落盘失败（已按无封面处理）', error, stack);
          pluginCallCount++;
          await HomeWidget.saveWidgetData<String>(WidgetDataKeys.coverPath, null);
        }
      } else {
        pluginCallCount++;
        await HomeWidget.saveWidgetData<String>(
          WidgetDataKeys.coverPath,
          coverUrl,
        );
      }

      pluginCallCount++;
      await HomeWidget.updateWidget(
        androidName: androidProviderName,
        qualifiedAndroidName: qualifiedAndroidProviderName,
      );
    } catch (error, stack) {
      _report('WidgetBridge.publish 失败（已忽略）', error, stack);
    }
  }

  /// 派发一个动作（点击流与冷启动 URI 共用）。
  ///
  /// 认不出来的 URI 一律丢弃：`WidgetActions.parse` 只认 `mconnect://widget/...`，
  /// 所以 `mconnect://song?...` 这类分享深链不会被这里误吞。
  static void dispatch(Uri? uri) {
    final action = WidgetActions.parse(uri);
    if (action == null) return;
    _execute(action);
  }

  /// 便捷入口（测试/调试用）。
  static void dispatchRaw(String? raw) {
    final action = WidgetActions.parseRaw(raw);
    if (action == null) return;
    _execute(action);
  }

  static void _deliver(Uri? uri) {
    try {
      dispatch(uri);
    } catch (error, stack) {
      _report('小组件动作派发失败（已忽略）', error, stack);
    }
  }

  static void _execute(WidgetAction action) {
    if (action.isTransport) {
      final container = _container;
      final handler = transportHandler;
      if (container == null || handler == null) {
        // 播放器还没起来（例如冷启动点击发生在首帧之前）——不猜、不乱播。
        debugPrint('WidgetBridge: 播放器尚未就绪，忽略 ${action.kind}');
        return;
      }
      try {
        handler(action, container);
      } catch (error, stack) {
        _report('小组件控制动作失败（已忽略）', error, stack);
      }
      return;
    }

    final navigate = navigationHandler ?? _defaultNavigate;
    try {
      navigate(action);
    } catch (error, stack) {
      _report('小组件导航失败（已忽略）', error, stack);
    }
  }

  static void _defaultNavigate(WidgetAction action) {
    // appRouter 是全局 GoRouter（lib/core/router/app_router.dart）。
    // 这里用字符串路径而不是 import 路由常量：本文件刻意不依赖 core/**，
    // 路径与 app_router 的 GoRoute 声明一致（'/player'、'/queue'）。
    //
    // 真正的导航实现由 `widget_playback_adapter.dart` 覆盖
    // （`WidgetBridge.navigationHandler`），因为它已经 import 了 router。
    debugPrint('WidgetBridge: 未安装导航处理器，忽略 ${action.kind}');
  }

  // ── 封面 / 组件存在性 ────────────────────────────────────────────────────

  /// 缓存"桌面上有没有组件"，避免每次切歌都查一遍 PackageManager。
  static bool? _hasPinnedWidgetCache;
  static DateTime? _hasPinnedWidgetCheckedAt;
  static const Duration _pinnedWidgetCacheTtl = Duration(minutes: 5);

  static Future<bool> _hasPinnedWidget() async {
    final cached = _hasPinnedWidgetCache;
    final checkedAt = _hasPinnedWidgetCheckedAt;
    if (cached != null &&
        checkedAt != null &&
        DateTime.now().difference(checkedAt) < _pinnedWidgetCacheTtl) {
      return cached;
    }
    try {
      pluginCallCount++;
      final widgets = await HomeWidget.getInstalledWidgets();
      final has = widgets.isNotEmpty;
      _hasPinnedWidgetCache = has;
      _hasPinnedWidgetCheckedAt = DateTime.now();
      return has;
    } catch (error, stack) {
      // 查不到就当作"有"（宁可多写一次，也不要因为查询失败而让小组件停在旧内容）。
      _report('查询已安装小组件失败（按"存在"继续）', error, stack);
      _hasPinnedWidgetCache = true;
      _hasPinnedWidgetCheckedAt = DateTime.now();
      return true;
    }
  }

  /// 已经落盘的封面路径（绝对路径）不需要再解码一次。
  static bool _coverIsLocalFile(String value) =>
      value.startsWith('/') || value.startsWith('file:');

  /// 读不到 `playerProvider.notifier` 时的上报口。
  ///
  /// 单独一个具名方法（而不是让动作适配器直接调 [_report]）是因为两者不在
  /// 同一个库：私有成员跨文件不可见，而"notifier 读不到"是这条路径上唯一
  /// 可预期、值得在诊断里**具名**的失败——小组件点了播放却什么都没发生，
  /// 没有这条记录就只能猜。
  ///
  /// 注意：`container.read(playerProvider.notifier)` 抛异常通常意味着容器被
  /// dispose（进程回收/热重启），此时**不能**再去 read 别的东西，直接返回。
  static void reportNotifierMissing(
    WidgetAction action,
    Object error,
    StackTrace stack,
  ) {
    _report('notifier unavailable for ${action.kind.name}', error, stack);
  }

  static void _report(String message, Object error, StackTrace stack) {
    debugPrint('WidgetBridge: $message :: $error');
    final sink = errorSink;
    if (sink != null) {
      try {
        sink(message, error, stack);
      } catch (_) {
        // 上报本身失败时不再上报（避免递归）。
      }
    }
  }

  // ── 测试支撑 ─────────────────────────────────────────────────────────────

  /// 每个用例开头调用，把静态状态复位（静态单例是这里唯一的状态）。
  @visibleForTesting
  static Future<void> resetForTest() async {
    await _clickSubscription?.cancel();
    _clickSubscription = null;
    _initialized = false;
    _initialUri = null;
    _container = null;
    _lastPublished = null;
    _hasPinnedWidgetCache = null;
    _hasPinnedWidgetCheckedAt = null;
    pluginCallCount = 0;
    errorSink = null;
    transportHandler = null;
    navigationHandler = null;
    platformProbe = () => defaultTargetPlatform;
  }
}
