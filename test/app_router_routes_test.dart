import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mconnect/core/router/app_router.dart';

/// Guards the v1.4.0 route additions (榜单中心 / 榜单详情 / 专辑 / 艺人 / 新歌 / 备份).
///
/// These route targets did not exist before, so this is the red→green evidence
/// for the router change: every listed location resolves now, and the last case
/// proves the matcher is capable of returning null (i.e. the assertion can
/// actually fail) instead of passing vacuously.
///
/// W1-D appends `/queue` (播放队列页) and pins **where** it lives, not merely that
/// it resolves: a queue page outside the `ShellRoute` would lose the mini player
/// and the bottom capsule and would push onto the wrong navigator.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('v1.4.0 locations resolve to a route match', () {
    const locations = <String>[
      '/toplists',
      '/toplist/qq/26',
      '/album/netease/12345',
      '/artist/kugou/abcde',
      '/new-songs',
      '/backup',
      // The 发现 tab's 每日推荐 button is now its always-visible entry (the
      // full-width card was dropped), so its target is pinned here too.
      '/recommendations',
      // W1-D: 播放队列页。
      '/queue',
    ];

    for (final location in locations) {
      final match = appRouter.configuration.findMatch(Uri.parse(location));
      expect(
        match.matches,
        isNotEmpty,
        reason: '$location should resolve to a match',
      );
    }
  });

  test('/queue 挂在根 Navigator（与 /player 同构，绝不在 ShellRoute 内）', () {
    // 真机事故（2026-10-10）：本页最初在 ShellRoute 内，从 /player（ShellRoute 外）
    // push 它时，go_router 14.8.1 为 ImperativeRouteMatch 重建整条 ShellRoute 匹配
    // 链，根 Navigator 与嵌套 Navigator 的 pages 在同一帧各用一套 key 派生
    // （ShellRouteMatch=route.hashCode / RouteMatch=路径），/queue 的 key 在其中
    // 一个 Navigator 的 pages 里出现两次 → Navigator 断言
    // '!keyReservation.contains(key)' 炸掉 → push 静默失败、整页 touch-dead
    // （设备日志两次抓到，音乐不受影响）。挂到根 Navigator（parentNavigatorKey）
    // 后整条 ShellRoute 重建路径被绕开。
    final queue = appRouter.configuration.findMatch(Uri.parse('/queue'));

    final routeMatch = queue.matches.single as RouteMatch;
    expect(
      routeMatch.route.parentNavigatorKey,
      appRouter.routerDelegate.navigatorKey,
      reason: '/queue 必须显式挂根 Navigator，不再进 ShellRoute（见上方事故说明）',
    );

    // 反例：证明上面那条有区分力 —— /likes 仍是 shell 子路由（形状不同）。
    final likes = appRouter.configuration.findMatch(Uri.parse('/likes'));
    expect(likes.matches.single, isA<ShellRouteMatch>());
  });

  test('an unregistered location matches nothing', () {
    // NOTE: `findMatch` returns a RouteMatchList with an *empty* match list for
    // an unknown location — it does not return null. Asserting on `matches` is
    // therefore what gives this pair of tests discriminating power.
    final match = appRouter.configuration.findMatch(
      Uri.parse('/definitely-not-a-route'),
    );
    expect(match.matches, isEmpty);
  });
}
