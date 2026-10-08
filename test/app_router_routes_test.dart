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

  test('/queue 挂在 ShellRoute 内（与 /likes 同构，而不是 /player 那种顶层页）', () {
    final queue = appRouter.configuration.findMatch(Uri.parse('/queue'));
    final likes = appRouter.configuration.findMatch(Uri.parse('/likes'));

    // 形状与一个已知合格的 shell 子路由一致 —— 比"matches 非空"强得多。
    expect(queue.matches, hasLength(likes.matches.length));
    expect(
      queue.matches.single,
      isA<ShellRouteMatch>(),
      reason: '队列页必须在 shell 里：否则迷你播放器与底栏会消失，返回栈也会错',
    );
    expect(
      (queue.matches.single as ShellRouteMatch).matches.map(
        (routeMatch) => routeMatch.matchedLocation,
      ),
      contains('/queue'),
      reason: 'shell 里的叶子路由必须真的是 /queue',
    );

    // 反例：证明上面那条 `isA<ShellRouteMatch>` 有区分力 —— `/player` 是
    // ShellRoute 之外的顶层路由，形状不同。
    final player = appRouter.configuration.findMatch(Uri.parse('/player'));
    expect(player.matches.single, isNot(isA<ShellRouteMatch>()));
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
