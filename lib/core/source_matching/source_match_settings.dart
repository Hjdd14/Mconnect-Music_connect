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

/// 读/写「自动换源」开关的存储 seam。
///
/// # 为什么要有它（不是过度设计，是一次实测故障）
/// `setEnabled` 以前在**点击回调**里直接 `unawaited(box.put(...))`。
/// `testWidgets` 的 body 跑在 FakeAsync 里，这次真实文件 I/O 的 continuation
/// 排在假时钟队列上；body 结束后没人再排空它，于是文件级 `tearDown` 的
/// `await Hive.close()` 会一直等它。诊断探针
/// （`test/scrobble_settings_probe_test.dart`）实测：
/// ```
/// PROBE A: 不点任何开关       → hiveClose=closed-ok
/// PROBE B: 点「自动换源」      → hiveClose=closed-TIMEOUT(3s)   ← 复现
/// PROBE C: 点 + runAsync 收口 → hiveClose=closed-TIMEOUT(3s)   ← runAsync 救不回来
/// PROBE D: 点「淡入淡出」      → hiveClose=closed-TIMEOUT(3s)   ← 与具体开关无关
/// ```
/// 而每个探针都打印了 `addTearDown 到达 ⇒ body + widget teardown 已完成`，
/// 所以卡点被钉死在**文件级 tearDown 的 `Hive.close()`**。
///
/// 于是把存储抽成 seam：**生产仍然写 Hive**；widget 测试 override 成
/// [MemoryAutoSourceSwitchStore]（不产生真实 I/O，teardown 立刻干净），
/// 而"真的落到 Hive 了"由 `test/settings_persistence_test.dart` 里的持久化单测保证
/// —— 否则"点击只改内存"会变成新的假绿。
abstract class AutoSourceSwitchStore {
  /// `null` = 没存过 ⇒ 调用方用文档化默认值（true）。
  bool? read();

  Future<void> write(bool enabled);
}

/// 生产实现：读同步（box 已打开时零等待）、写异步。
///
/// 读写两侧都 try/catch 降级 —— 设置读不出来绝不能把异常抛进播放链路
/// （这是 W1-A 的教训，见 [AutoSourceSwitchNotifier.setEnabled] 的注释）。
class HiveAutoSourceSwitchStore implements AutoSourceSwitchStore {
  const HiveAutoSourceSwitchStore();

  @override
  bool? read() {
    try {
      final raw = Hive.box(_settingsBoxName).get(_autoSourceSwitchKey);
      return raw is bool ? raw : null;
    } catch (e, s) {
      debugPrint('AutoSourceSwitchStore read failed: $e');
      debugPrint('$s');
      return null;
    }
  }

  @override
  Future<void> write(bool enabled) async {
    try {
      await Hive.box(_settingsBoxName).put(_autoSourceSwitchKey, enabled);
    } catch (e, s) {
      debugPrint('AutoSourceSwitchStore write failed: $e');
      debugPrint('$s');
    }
  }
}

/// 测试实现：不碰 Hive；`writes` 记录每一次落盘请求，用来断言
/// "点击确实要求落盘了"，而不是"只改了内存"。
class MemoryAutoSourceSwitchStore implements AutoSourceSwitchStore {
  MemoryAutoSourceSwitchStore([this._value]);

  bool? _value;

  /// 当前"已存"的值（null = 从未写过）。
  bool? get value => _value;

  /// 依次收到的写入值。
  final List<bool> writes = <bool>[];

  @override
  bool? read() => _value;

  @override
  Future<void> write(bool enabled) async {
    _value = enabled;
    writes.add(enabled);
  }
}

/// 注入点：生产用 Hive；widget 测试 override 成内存实现。
final autoSourceSwitchStoreProvider = Provider<AutoSourceSwitchStore>(
  (ref) => const HiveAutoSourceSwitchStore(),
);

/// 「自动换源」开关。
///
/// 放在 `lib/core/source_matching/` 而不是 `lib/features/settings/` 的理由：
/// 换源是播放链路自己读的开关（`player_provider` 装配时注入给
/// `SourceMatchService`），设置页只是它的一个 UI 入口。
///
/// load/save 刻意镜像 `AudioEffectsSettingsNotifier`：同步 `read()`、异步 `write()`，
/// **两侧都降级**——设置读不出来绝不能把异常抛进播放链路。
class AutoSourceSwitchNotifier extends StateNotifier<AutoSourceSwitchState> {
  AutoSourceSwitchNotifier(this._store)
    : super(AutoSourceSwitchState(enabled: _initialEnabled(_store)));

  /// 静态 helper 而不是在 super(...) 里直接 `_store.read()`：前者不涉及任何
  /// "初始化列表里能不能用字段"的细节，读起来也没有歧义。
  static bool _initialEnabled(AutoSourceSwitchStore store) =>
      store.read() ?? true;

  final AutoSourceSwitchStore _store;

  /// 切换开关：**内存状态同步翻转**（UI 立刻有反馈），落盘 fire-and-forget。
  ///
  /// 刻意**不是** `async` + `await`：那条路径在"没有 Hive 初始化"的环境里会把
  /// HiveError 抛给调用方（或变成未处理的 zone 错误），一次开关点击就能把异常甩到
  /// UI/测试上（W1-A 实测就是这么红的）。这里：
  /// * 同步取**已打开**的 box —— 没打开就同步抛，被 store 的 catch 吃掉，不留 Future；
  /// * box 已打开时 `put` 是 fire-and-forget，失败只记诊断。
  /// * "这次 fire-and-forget 会不会卡住测试 teardown"由 [AutoSourceSwitchStore]
  ///   这个 seam 解决（见它的类注释）。
  void setEnabled(bool enabled) {
    state = AutoSourceSwitchState(enabled: enabled);
    unawaited(
      _store.write(enabled).catchError((Object error, StackTrace stack) {
        debugPrint('AutoSourceSwitchNotifier save failed: $error');
        debugPrint('$stack');
      }),
    );
  }
}

final autoSourceSwitchProvider =
    StateNotifierProvider<AutoSourceSwitchNotifier, AutoSourceSwitchState>((
      ref,
    ) {
      return AutoSourceSwitchNotifier(ref.read(autoSourceSwitchStoreProvider));
    });
