import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'widget_bridge.dart';
import 'widget_playback_adapter.dart';

/// 把小组件桥接进 Riverpod 生命周期。
///
/// 为什么要一个 `ProviderObserver`：
/// 小组件需要两样东西 —— ① **读**播放器状态（推给桌面）② 一个 `ProviderContainer`
/// （点桌面按钮时调 `PlayerNotifier`）。这两样都只在 provider 容器存在之后才有。
/// `ProviderObserver` 的每个回调都会收到当前 `ProviderContainer`，于是在**不修改
/// `app.dart` / `lib/core/share/**`**（分别是 ux-parity 与其它成员的写作用域）的前提下，
/// 拿到了同一个容器。
///
/// 用法（`lib/main.dart`，唯一一处接线）：
/// ```dart
/// runZonedGuarded(
///   () => runApp(ProviderScope(
///     observers: [WidgetBridgeObserver()],
///     child: const MconnectApp(),
///   )),
///   onZoneError,
/// );
/// ```
///
/// 行为边界：
/// * 它**不**创建任何 provider，也不读任何业务数据；只在播放器状态更新时推一份快照；
/// * 非 Android 上 `WidgetBridge.publish` 是硬 no-op，所以这类回调在 Windows 上几乎零成本；
/// * 所有异常都被 `WidgetBridge` 吞掉并上报 —— 观察者抛异常会污染整个容器。
class WidgetBridgeObserver extends ProviderObserver {
  WidgetBridgeObserver() {
    // 安装播放器适配层（读状态 + 执行控制动作）。放在构造函数里是为了让"接线"这件事
    // 只发生在 `main.dart` 那一行 `WidgetBridgeObserver()` 上。
    WidgetPlaybackAdapter.install();
  }

  bool _initialDelivered = false;

  @override
  void didAddProvider(
    ProviderBase<Object?> provider,
    Object? value,
    ProviderContainer container,
  ) {
    // 第一个被建立的 provider 就够我们把容器接进来（此后不再重复 attach）。
    WidgetBridge.attach(container);
    if (_initialDelivered) return;
    _initialDelivered = true;
    // 冷启动若来自小组件点击，`takeInitialUri()` 里有值；必须在首帧之后再导航。
    unawaited(WidgetBridge.deliverInitial());
  }

  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    if (!WidgetPlaybackAdapter.handles(provider)) return;
    final snapshot = WidgetPlaybackAdapter.snapshotFrom(newValue);
    if (snapshot == null) return;
    unawaited(WidgetBridge.publish(snapshot));
  }
}
