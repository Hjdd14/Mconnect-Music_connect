import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/features/player/presentation/widgets/mini_player_bar.dart';
import 'package:mconnect/models/platform_type.dart';

import 'support/content_page_fakes.dart';

/// Opening the player from the mini capsule: a tap burst must not stack players.
///
/// On a real device, tapping the capsule quickly stacked N full-screen players —
/// each with its own full-screen blur and its own 1 s / 250 ms timers — which is
/// the "the phone froze and had to be restarted" report. The second test pins the
/// other half of the same fix: the capsule's backdrop must not be re-sampled by
/// the per-frame progress ring.
void main() {
  Future<PlayerNotifier> playerWithCurrentTrack() async {
    final platform = registerFake(
      FakeContentPlatform(type: PlatformType.qq),
    );
    final player = PlayerNotifier(
      audioController: IdleAudioController(),
      platformResolver: (_) => platform,
    );
    await player.playSong(song('current', PlatformType.qq, name: '正在播放'));
    return player;
  }

  Future<GoRouter> pumpCapsule(
    WidgetTester tester,
    PlayerNotifier player, {
    bool floating = false,
  }) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              Scaffold(body: MiniPlayerBar(floating: floating)),
        ),
        GoRoute(
          path: playerRoutePath,
          builder: (context, state) =>
              const Scaffold(body: SizedBox(key: Key('player-page'))),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [playerProvider.overrideWith((ref) => player)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    return router;
  }

  testWidgets('连点迷你播放器 10 次只压入 1 个 /player 路由', (tester) async {
    final player = await playerWithCurrentTrack();
    await pumpCapsule(tester, player);

    // Ten taps with no frame in between: exactly the burst that used to stack ten
    // players. `context.push` only moves the router on the next frame, so the
    // guard has to be a cooldown, not a route-stack check.
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.text('正在播放'));
    }
    await tester.pumpAndSettle();

    // Counted through the widget tree rather than `currentConfiguration`: after an
    // imperative `push` the delegate's configuration still reports the shell's
    // route, while each stacked route does add its own page to the tree.
    expect(
      find.byKey(const Key('player-page'), skipOffstage: false),
      findsOneWidget,
      reason: '10 次连点必须只留下 1 层播放页，否则每层都会自带全屏模糊与定时器',
    );
  });

  testWidgets('关掉播放器后立刻再点仍能打开（守卫不是时间冷却）', (tester) async {
    final player = await playerWithCurrentTrack();
    final router = await pumpCapsule(tester, player);

    // The app's own shell tests open → close → open the player twice in a row
    // within milliseconds, so the guard must be "this push is still in flight",
    // never "not again for N milliseconds".
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('正在播放'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('player-page'), skipOffstage: false),
        findsOneWidget,
      );

      router.pop();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('player-page'), skipOffstage: false),
        findsNothing,
      );
    }
  });

  testWidgets('浮层胶囊：BackdropFilter 的直接子节点是 RepaintBoundary', (tester) async {
    final player = await playerWithCurrentTrack();
    await pumpCapsule(tester, player, floating: true);

    final backdrop = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(
      backdrop.child,
      isA<RepaintBoundary>(),
      reason: '进度环每帧重绘；没有这层边界，backdrop 会被每帧重新采样（播放时持续烧 GPU）',
    );

    // The ring itself is still inside the boundary, i.e. it now repaints in its
    // own layer instead of re-compositing the filtered layer above it.
    expect(
      find.ancestor(
        of: find.byKey(capsuleProgressRingKey),
        matching: find.byType(RepaintBoundary),
      ),
      findsWidgets,
    );
  });
}
