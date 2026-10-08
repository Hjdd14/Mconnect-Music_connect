import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// 与主题 / 音频效果 / 悬浮歌词共用同一个设置 box（仓库既有约定，不要另造一个）。
const _settingsBoxName = 'settings';
const _autoSourceSwitchKey = 'auto_source_switch';

/// 「自动换源」开关的状态（Wave 1-A / 计划 D-2：**默认开**）。
@immutable
class AutoSourceSwitchState {
  const AutoSourceSwitchState({this.enabled = true});

  final bool enabled;

  AutoSourceSwitchState copyWith({bool? enabled}) {
    return AutoSourceSwitchState(enabled: enabled ?? this.enabled);
  }
}

/// 「自动换源」开关。
///
/// 放在 `lib/core/source_matching/` 而不是 `lib/features/settings/` 的理由：
/// 换源是播放链路自己读的开关（`player_provider` 装配时注入给
/// `SourceMatchService`），设置页只是它的一个 UI 入口；本波 fix-playback 的写作用域
/// 也只覆盖 `settings_page.dart` 这一个 settings 文件。
///
/// load/save 刻意镜像 [AudioEffectsSettingsNotifier]：同步 `Hive.box(...)` 读、
/// 异步 `Hive.openBox(...)` 写，**两侧都 try/catch 降级**——设置读不出来
/// 绝不能把异常抛进播放链路。
class AutoSourceSwitchNotifier extends StateNotifier<AutoSourceSwitchState> {
  AutoSourceSwitchNotifier() : super(const AutoSourceSwitchState()) {
    _load();
  }

  void _load() {
    // 读失败（box 还没打开 / 存储损坏 / 平台不可用）时必须保持**文档化的默认值**
    // —— 计划 D-2 的默认是「开」。把默认值写成显式的 `stored ?? true`，而不是
    // "catch 里什么都不做、赌初始 state 是对的"，这样这条路径有单一事实来源。
    bool? stored;
    try {
      final raw = Hive.box(_settingsBoxName).get(_autoSourceSwitchKey);
      if (raw is bool) stored = raw;
    } catch (e, s) {
      debugPrint('AutoSourceSwitchNotifier load failed: $e');
      debugPrint('$s');
    }
    if (!mounted) return;
    state = AutoSourceSwitchState(enabled: stored ?? true);
  }

  /// 切换开关：**内存状态同步翻转**（UI 立刻有反馈），落盘 fire-and-forget。
  ///
  /// 刻意**不是** `async` + `await Hive.openBox(...)`：那条路径在"没有 Hive 初始化"
  /// 的环境里会把 HiveError 抛给调用方（或变成未处理的 zone 错误），一次开关点击
  /// 就能把异常甩到 UI/测试上（W1-A 实测就是这么红的）。这里改成：
  /// * 同步取**已打开**的 box —— 没打开就同步抛，被下面的 catch 吃掉，不留 Future；
  /// * box 已打开时 `put` 是 fire-and-forget，失败走 `catchError` 只记诊断。
  ///
  /// 与 [_load] 的容错**对称**：读失败、写失败都只降级，绝不上抛。
  void setEnabled(bool enabled) {
    state = AutoSourceSwitchState(enabled: enabled);
    try {
      final box = Hive.box(_settingsBoxName);
      unawaited(
        box
            .put(_autoSourceSwitchKey, enabled)
            .catchError((Object error, StackTrace stack) {
              debugPrint('AutoSourceSwitchNotifier save failed: $error');
              debugPrint('$stack');
            }),
      );
    } catch (e, s) {
      debugPrint('AutoSourceSwitchNotifier save failed: $e');
      debugPrint('$s');
    }
  }
}

final autoSourceSwitchProvider =
    StateNotifierProvider<AutoSourceSwitchNotifier, AutoSourceSwitchState>((
      ref,
    ) {
      return AutoSourceSwitchNotifier();
    });
