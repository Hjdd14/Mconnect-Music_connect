import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/player/presentation/pages/queue_page.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

import 'support/content_page_fakes.dart';

/// 播放队列页（`/queue`）。
///
/// 审计结论：27 条路由里没有 `/queue`，而 `PlayerNotifier.addToQueue` 只往队列
/// 里塞、UI 从不展示（播放页只弹一句「已添加到播放队列」），所以用户看不到也改
/// 不了正在排队的歌。这一页是那件事的唯一出口。
///
/// 队列编辑能力在 `player_provider.dart:2817+`（Wave 0-A），**这一页只调用，
/// 不重新实现**：`moveInQueue` / `removeFromQueue` / `clearQueue` / `playAtIndex`。
void main() {
  late PlayerNotifier player;

  /// 三首各 3 分钟的歌：总时长 9 分，所以头部的断言是精确值而不是 `textContaining`。
  List<Song> threeSongs() => [
    song('n1', PlatformType.netease, name: 'A', seconds: 180),
    song('n2', PlatformType.netease, name: 'B', seconds: 180),
    song('n3', PlatformType.netease, name: 'C', seconds: 180),
  ];

  setUp(() {
    final platform = registerFake(
      FakeContentPlatform(type: PlatformType.netease),
    );
    player = PlayerNotifier(
      audioController: IdleAudioController(),
      platformResolver: (_) => platform,
    );
    // A tall surface so all three rows are laid out and the reorder drag has
    // deterministic geometry (same trick as the playlist-detail test).
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1200, 2400);
    view.devicePixelRatio = 3;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  Future<void> pumpQueue(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [playerProvider.overrideWith((ref) => player)],
        child: const MaterialApp(home: QueuePage()),
      ),
    );
    await tester.pump();
  }

  /// Lets `PlayerNotifier._schedulePlaybackMemorySave`'s 5 s Timer fire.
  ///
  /// 每一次队列改动都会排一个 5 秒 Timer（`_playbackMemorySaveInterval`），
  /// 测试结束时 Timer 仍 pending 会触发 `flutter_test` 的 `!timersPending`
  /// 不变式 —— 与 likes/history 长按测试结尾 `pump(5s)` 同一个理由。
  Future<void> drainScheduledTimers(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 6));

  List<String> namesOf(PlayerNotifier notifier) =>
      notifier.state.playlist.map((s) => s.name).toList();

  group('播放队列页', () {
    testWidgets('空队列 → 共享空态，且不显示清空入口', (tester) async {
      await pumpQueue(tester);

      expect(find.text('队列是空的'), findsOneWidget);
      expect(find.text('播放歌曲，或在歌曲菜单里选「加入播放队列」'), findsOneWidget);
      // 没有队列就没有可清空的东西，入口不该出现（否则是个必然失败的按钮）。
      expect(find.byTooltip('清空队列'), findsNothing);
      expect(find.byType(ReorderableListView), findsNothing);

      // 这一条不改队列，但仍走一遍收尾：`PlayerNotifier` 构造时会起一个卡死
      // 看门狗的周期 Timer（`playback_health_monitor.dart:134`，**不按平台门控**），
      // 本仓库既有用例也都在结尾排一次时钟。
      await drainScheduledTimers(tester);
    });

    testWidgets('显示曲数与总时长，并高亮当前播放曲', (tester) async {
      await player.playPlaylist(threeSongs(), startIndex: 1); // 当前 = B
      await pumpQueue(tester);

      expect(find.text('共 3 首'), findsOneWidget);
      expect(find.text('总时长 9 分'), findsOneWidget);

      final current = tester.widget<ListTile>(
        find.ancestor(of: find.text('B'), matching: find.byType(ListTile)).first,
      );
      final other = tester.widget<ListTile>(
        find.ancestor(of: find.text('A'), matching: find.byType(ListTile)).first,
      );
      expect(current.selected, isTrue, reason: '当前播放的那一首必须高亮');
      expect(other.selected, isFalse);
      // 「正在播放」的图形标记只在当前行出现，所以它同时是唯一性证明。
      expect(find.byIcon(Icons.graphic_eq), findsOneWidget);

      await drainScheduledTimers(tester);
    });

    testWidgets('拖动重排 → 落到 moveInQueue，且顺序由 provider 持久持有', (tester) async {
      await player.playPlaylist(threeSongs()); // A B C，当前 = A
      await pumpQueue(tester);

      // 自校准拖动距离：按真实行高算，而不是写死像素。
      final handles = find.byIcon(Icons.drag_handle);
      final rowHeight =
          tester.getCenter(handles.at(1)).dy - tester.getCenter(handles.first).dy;

      // 手势只发**一个** move 事件，位移取 0.75 行。这不是随手取的数，
      // 是 `_dragUpdateItems` 的换位窗口 + "空隙下标比目标位置多 1" 两条规则决定的
      // （`reorderable_list.dart`，reverse = false / 向下拖）：
      //
      // * `_handleReorderItem` 最后会做 `newIndex > oldIndex → newIndex -= 1`
      //   （`:1022-1025`），所以"向下挪一格"要的是**空隙下标 2**，不是 1；
      // * 单事件下，落点位移 d（自**按下点**起算，`_DragInfo.dragOffset` 见 `:1517`）
      //   落在 [0.5h, 1h) 时走 `itemMiddle <= proxyItemEnd <= itemEnd` 分支
      //   → 空隙下标 = item.index + 1 = 2（`:1096-1101`）→ 减 1 后恰好挪一格；
      // * 落在 [1h, 1.5h] 时反而走上一分支 → 空隙下标 = 1 → 减 1 后是 0，**不换位**；
      // * 多个 move 事件会把 `_insertIndex` 累积推高：改用本方案前是"40px + 1.25h"
      //   两个事件，空隙下标被推到 3 → 减 1 后挪两格，Actual `['B','C','A']`
      //   就是这么来的（不再是"顺序没变"，证明 `pumpAndSettle` 那步已经修对）。
      //
      // 所以：**一个事件、0.75h**（窗口 [0.5h, 1h) 的正中，两侧各留 0.25h 余量），
      // 而 0.75h 也大于 kTouchSlop(18)，保证拖动真的开始。
      final gesture = await tester.startGesture(tester.getCenter(handles.first));
      await gesture.moveBy(Offset(0, rowHeight * 0.75));
      await tester.pump();
      await gesture.up();

      // **必须是 pumpAndSettle，不能只 pump 一帧。**
      // `ReorderableListView` 的放手路径分两段：`onEnd: _dragEnd` 只计算落点
      // （`reorderable_list.dart:942-976`），真正调 `onReorderItem` 的是
      // `_dropCompleted`（`:978-982`），而它要等**落位动画跑完**才被调用
      // （`:1563`）。只 pump 一帧时动画没走完，回调根本没发生 —— provider 顺序
      // 会原封不动，这正是这条用例第一次跑时的失败形态（Actual 仍是 A B C）。
      //
      // 这里 `pumpAndSettle` 是安全的：队列页只有 empty 一种三态，
      // `AsyncStateView` 的 shimmer 只存在于 loading 态，本页没有任何无限动画。
      await tester.pumpAndSettle();

      // 持久性：新版顺序必须落在 provider 里（页面重建后也只能渲染它）。
      expect(
        namesOf(player),
        ['B', 'A', 'C'],
        reason: '拖动必须落到 moveInQueue，而不是只改本地 widget 顺序',
      );
      // 当前曲跟着走了：A 从 0 挪到 1，播放本身没有被打断。
      expect(player.state.currentSong?.name, 'A');
      expect(player.state.currentIndex, 1);

      // 「再进页面仍是新顺序」等价于「页面只渲染 provider 的顺序」：队列页是
      // 无状态的（`build` 直接读 `state.playlist`），没有本地顺序可缓存，所以
      // 直接改 provider 再 pump 就能证明这一点。
      //
      // 这里**不**再 pumpWidget 一次来模拟"重进"：Riverpod 2.6 的
      // `ProviderScope.didUpdateWidget` 会走 `container.updateOverrides`
      // （`flutter_riverpod-2.6.1/lib/src/framework.dart:253`），有把注入的
      // notifier 换掉/释放的副作用，为一条断言引入这种风险不值得。
      player.moveInQueue(1, 0); // A 挪回队首
      await tester.pump();
      expect(
        tester.getTopLeft(find.text('A')).dy,
        lessThan(tester.getTopLeft(find.text('B')).dy),
        reason: '页面必须跟着 provider 的队列顺序重排（provider 是唯一真相）',
      );

      await drainScheduledTimers(tester);
    });

    testWidgets('点击某曲 → playAtIndex 跳到它', (tester) async {
      await player.playPlaylist(threeSongs()); // 当前 = A
      await pumpQueue(tester);

      await tester.tap(find.text('C'));
      await tester.pump();
      await tester.pump();

      expect(player.state.currentSong?.name, 'C');
      expect(player.state.currentIndex, 2);

      await drainScheduledTimers(tester);
    });

    testWidgets('删除非当前曲 → 队列少一首，当前播放不受影响', (tester) async {
      await player.playPlaylist(threeSongs(), startIndex: 1); // 当前 = B
      await pumpQueue(tester);

      await tester.tap(find.byTooltip('从队列移除 A'));
      await tester.pump();
      await tester.pump();

      expect(namesOf(player), ['B', 'C']);
      expect(
        player.state.currentSong?.name,
        'B',
        reason: '删掉别的歌不能打断正在播的那一首',
      );
      expect(player.state.currentIndex, 0, reason: 'currentIndex 跟着当前曲走');

      await drainScheduledTimers(tester);
    });

    testWidgets('删除当前播放曲 → 由接手的那一首继续，播放器状态自洽', (tester) async {
      await player.playPlaylist(threeSongs(), startIndex: 1); // 当前 = B
      await pumpQueue(tester);

      await tester.tap(find.byTooltip('从队列移除 B'));
      await tester.pump();
      await tester.pump();

      expect(namesOf(player), ['A', 'C']);
      // provider 的契约（`removeFromQueue` 文档）：由"原下标位置上剩下的那一首"
      // 接手 —— B 在 index 1，删掉后 index 1 是 C。
      expect(player.state.currentSong?.name, 'C');
      expect(player.state.currentIndex, 1);
      expect(find.text('C'), findsOneWidget, reason: '删除后页面不能崩，仍要正常渲染');

      await drainScheduledTimers(tester);
    });

    testWidgets('清空队列需要二次确认：取消不动，确认后清空并显示空态', (tester) async {
      await player.playPlaylist(threeSongs(), startIndex: 1);
      await pumpQueue(tester);

      // 取消：队列必须原封不动（否则就是个"点了就删"的陷阱按钮）。
      await tester.tap(find.byTooltip('清空队列'));
      await tester.pumpAndSettle();
      expect(find.text('清空播放队列'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(player.state.playlist, hasLength(3), reason: '取消不能动队列');
      expect(find.text('共 3 首'), findsOneWidget);

      // 确认：队列清空、停止播放、页面落到空态。
      await tester.tap(find.byTooltip('清空队列'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '清空'));
      await tester.pumpAndSettle();

      expect(player.state.playlist, isEmpty);
      expect(player.state.currentSong, isNull);
      expect(find.text('队列是空的'), findsOneWidget);
      expect(find.byTooltip('清空队列'), findsNothing);

      await drainScheduledTimers(tester);
    });
  });
}
