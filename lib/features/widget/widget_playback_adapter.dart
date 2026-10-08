import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_router.dart';
import '../player/presentation/providers/player_provider.dart';
import 'widget_actions.dart';
import 'widget_bridge.dart';
import 'widget_state.dart';

/// 小组件与**播放器**之间的唯一适配层。
///
/// # 为什么单独一个文件
/// `lib/features/player/**` 由 W2-A/W2-B 持有并在活跃改动。把"读 `PlayerState`、
/// 调 `PlayerNotifier`"这两件与玩家耦合的事**全部**收在这一个文件里，其余
/// `lib/features/widget/**` 不需要 import 播放器；将来播放器 API 一变，只需要改这里。
///
/// # 只使用公开且稳定的表面
/// * `playerProvider`（`StateNotifierProvider<PlayerNotifier, PlayerState>`）
/// * `PlayerState.currentSong` / `.isPlaying`
/// * `Song.name` / `.artistNames` / `.coverUrl`
/// * `PlayerNotifier.togglePlay()` / `.skipToNext()` / `.skipToPrevious()`
/// 都是既有调用点（播放页、通知栏、悬浮歌词）在用的表面，不涉及私有成员。
class WidgetPlaybackAdapter {
  const WidgetPlaybackAdapter._();

  /// 安装钩子。由 [WidgetBridgeObserver] 的构造函数调用一次。
  static void install() {
    WidgetBridge.transportHandler = _transport;
    WidgetBridge.navigationHandler = _navigate;
  }

  /// 这个 provider 的更新是否与小组件有关（只有播放器状态才需要推给桌面）。
  static bool handles(ProviderBase<Object?> provider) =>
      identical(provider, playerProvider);

  /// `PlayerState` → 小组件快照。返回 null 表示这次更新推不出有效快照（忽略）。
  static WidgetSnapshot? snapshotFrom(Object? value) {
    if (value is! PlayerState) return null;
    final song = value.currentSong;
    if (song == null) {
      // 没有当前曲目 → 明确推"空"，让桌面回到兜底文案（而不是留着上一首的名字）。
      return const WidgetSnapshot.empty();
    }
    return WidgetSnapshot(
      songName: song.name,
      // `Song.name` 是曲名；歌手用现成的 artistNames（多歌手已用 ', ' 连接）。
      artistNames: song.artistNames,
      isPlaying: value.isPlaying,
      // 这里给的是**网络地址**（`Song.coverUrl`）。桥接层用 `HomeWidget.saveImage`
      // 把它解码落盘后，写进共享存储的是**绝对路径**；落盘失败就退化成"无封面"。
      // 注意：v1 不提供本地音乐的内嵌封面路径（`Song` 只暴露 coverUrl），
      // 本地曲目的封面同样走这条网络/缓存路径，失败则隐藏图片。
      coverPath: song.coverUrl,
    );
  }

  // ── 动作执行 ────────────────────────────────────────────────────────────

  static void _transport(WidgetAction action, ProviderContainer container) {
    final PlayerNotifier notifier;
    try {
      notifier = container.read(playerProvider.notifier);
    } catch (error, stack) {
      WidgetBridge.reportNotifierMissing(action, error, stack);
      return;
    }

    final Future<void>? pending = switch (action.kind) {
      WidgetActionKind.togglePlayPause => notifier.togglePlay(),
      WidgetActionKind.next => notifier.skipToNext(),
      WidgetActionKind.previous => notifier.skipToPrevious(),
      // 导航类动作不会走到这里（`WidgetAction.isTransport` 已经把开关分好）
      WidgetActionKind.openPlayer || WidgetActionKind.openQueue => null,
    };

    if (pending != null) {
      // 桌面点了按钮却失败（例如没有可播的下一首）时，异常必须被吞掉并上报，
      // 否则会变成未捕获的异步错误、被崩溃上报当成崩溃。
      unawaited(
        pending.catchError((Object error, StackTrace stack) {
          debugPrint('WidgetPlaybackAdapter: ${action.kind} 执行失败 :: $error');
        }),
      );
    }
  }

  static void _navigate(WidgetAction action) {
    // 路径与 lib/core/router/app_router.dart 的 GoRoute 声明一致（'/player'、'/queue'）。
    switch (action.kind) {
      case WidgetActionKind.openPlayer:
        appRouter.go('/player');
      case WidgetActionKind.openQueue:
        appRouter.go('/queue');
      case WidgetActionKind.togglePlayPause:
      case WidgetActionKind.next:
      case WidgetActionKind.previous:
        break;
    }
  }
}
