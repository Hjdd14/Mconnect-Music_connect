import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/router/app_router.dart';

/// Guards the v1.4.0 route additions (榜单中心 / 榜单详情 / 专辑 / 艺人 / 新歌 / 备份).
///
/// These route targets did not exist before, so this is the red→green evidence
/// for the router change: every listed location resolves now, and the last case
/// proves the matcher is capable of returning null (i.e. the assertion can
/// actually fail) instead of passing vacuously.
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
