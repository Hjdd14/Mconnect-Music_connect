import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/theme/ui_style_provider.dart';
import 'package:mconnect/core/widgets/app_bottom_nav_bar.dart';
import 'package:mconnect/core/widgets/floating_glass_nav_bar.dart';
import 'package:mconnect/core/widgets/miuix_bottom_layout.dart';
import 'package:mconnect/core/widgets/miuix_bottom_stack.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/features/player/presentation/widgets/mini_player_bar.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

const _song = Song(
  id: 'song-1',
  platform: PlatformType.netease,
  name: 'Song 1',
  artists: [Artist(id: 'a1', name: 'Artist 1')],
  duration: Duration(seconds: 200),
);

class _StubUiStyleNotifier extends UiStyleNotifier {
  _StubUiStyleNotifier(UiStyle style) : super(initialStyle: style);

  @override
  Future<void> setStyle(UiStyle style) async {
    state = state.copyWith(style: style);
  }
}

/// Seeds a current song so `MiniPlayerBar` actually paints its capsule.
class _SeededPlayerNotifier extends PlayerNotifier {
  _SeededPlayerNotifier({bool withSong = true})
    : super(
        audioController: _IdleAudioController(),
        audioControllerFactory: () => _IdleAudioController(),
      ) {
    if (withSong) {
      state = state.copyWith(
        currentSong: _song,
        playlist: const [_song],
        currentIndex: 0,
      );
    }
  }
}

class _IdleAudioController implements PlayerAudioController {
  @override
  bool get playing => false;
  @override
  Duration get position => Duration.zero;
  @override
  double get volume => 1.0;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Stream<AudioPlaybackState> get playerStateStream => const Stream.empty();
  @override
  Future<void> stop() async {}
  @override
  Future<void> setUrl(String url) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> applyEqualizer({
    required bool enabled,
    required List<double> bandGains,
  }) async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  Widget host({required Widget child, bool withSong = true}) {
    return ProviderScope(
      overrides: [
        uiStyleProvider.overrideWith(
          (ref) => _StubUiStyleNotifier(UiStyle.miuix),
        ),
        playerProvider.overrideWith(
          (ref) => _SeededPlayerNotifier(withSong: withSong),
        ),
      ],
      child: MaterialApp(
        // The stack fills the whole test surface, so widget rects coincide with
        // well-known screen coordinates and the geometry can be asserted
        // directly. `Center`/fixed-size wrappers would move the origin.
        home: Scaffold(body: child),
      ),
    );
  }

  /// Gives the tests a deterministic 400x800 logical surface.
  void useTallSurface(WidgetTester tester) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('MiuixBottomLayout arithmetic', () {
    testWidgets('Material and Miuix give the player different insets', (
      tester,
    ) async {
      late double material;
      late double miuix;

      await tester.pumpWidget(
        host(
          child: Builder(
            builder: (context) {
              material = MiuixBottomLayout.playerBottomInsetFor(
                context,
                UiStyle.material,
              );
              miuix = MiuixBottomLayout.playerBottomInsetFor(
                context,
                UiStyle.miuix,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(material, 88.0);
      expect(miuix, 96.0);
      expect(
        material,
        lessThan(miuix),
        reason: 'the Material bar is flush, so the player sits lower',
      );
      // Pin the constant against the arithmetic that produced it, so a bad edit
      // to either number fails here.
      expect(
        material,
        MiuixBottomLayout.materialNavBarHeight + MiuixBottomLayout.playerGap,
      );
    });

    testWidgets('the player inset is the nav capsule plus the gap', (
      tester,
    ) async {
      late double playerInset;
      late double contentInset;
      late double navHeight;

      await tester.pumpWidget(
        host(
          child: Builder(
            builder: (context) {
              playerInset = MiuixBottomLayout.playerBottomInset(context);
              contentInset = MiuixBottomLayout.contentInset(context);
              navHeight = MiuixBottomLayout.navCapsuleHeight(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(
        playerInset,
        FloatingGlassNavBar.bottomMargin +
            navHeight +
            MiuixBottomLayout.playerGap,
      );
      expect(
        contentInset,
        playerInset + MiuixBottomLayout.playerHeight,
        reason: 'content must clear the player capsule completely',
      );

      // The regression behind the flashing mini player: these values must be a
      // pure function of the shared geometry, never of whether the nav capsule
      // happens to be mounted. Both shells therefore agree.
      expect(playerInset, 36.0 + 52.0 + 8.0);
      expect(contentInset, 36.0 + 52.0 + 8.0 + 48.0);
    });

    test('the player capsule is shorter and wider than the nav capsule', () {
      expect(
        MiuixBottomLayout.playerHeight,
        lessThan(FloatingGlassNavBar.minBarHeight),
        reason: 'the player capsule is meant to read as shorter',
      );
      expect(
        MiuixBottomLayout.playerSideMargin,
        lessThan(FloatingGlassNavBar.sideMargin),
        reason: 'a smaller side margin makes the player capsule wider/longer',
      );
    });
  });

  group('MiuixBottomStack geometry', () {
    testWidgets('the player capsule and the nav capsule never overlap', (
      tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        host(
          child: const MiuixBottomStack(
            navBar: AppBottomNavBar(
              selectedIndex: 0,
              onDestinationSelected: _noop,
            ),
            child: SizedBox.expand(),
          ),
        ),
      );
      await tester.pump();

      final navRect = tester.getRect(find.byKey(AppBottomNavBar.miuixKey));
      final playerRect = tester.getRect(find.byType(MiniPlayerBar));

      // Overlap is exactly the defect that was reported: the nav capsule covered
      // the player's content. Require a real gap, not merely "not identical".
      expect(
        playerRect.bottom,
        lessThanOrEqualTo(navRect.top - MiuixBottomLayout.playerGap + 0.5),
        reason: 'player $playerRect must sit above nav $navRect',
      );
      expect(playerRect.height, MiuixBottomLayout.playerHeight);
      expect(
        playerRect.width,
        lessThan(navRect.width),
        reason: 'the player capsule must be narrower than the nav capsule',
      );
      expect(playerRect.left, MiuixBottomLayout.playerSideMargin);
    });

    testWidgets(
      'the Material player clears the real NavigationBar (no overlap)',
      (tester) async {
        useTallSurface(tester);

        // Build the real `NavigationBar` in the same position the app puts it, so
        // the assertion is against Flutter's actual height rather than a number
        // we copied from it.
        await tester.pumpWidget(
          host(
            child: MiuixBottomStack(
              style: UiStyle.material,
              navBar: NavigationBar(
                selectedIndex: 0,
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.search), label: '搜索'),
                  NavigationDestination(
                    icon: Icon(Icons.library_music),
                    label: '音乐库',
                  ),
                ],
              ),
              child: const SizedBox.expand(),
            ),
          ),
        );
        await tester.pump();

        final navRect = tester.getRect(find.byType(NavigationBar));
        final playerRect = tester.getRect(find.byType(MiniPlayerBar));

        // The reported defect: under Material the player sat 16 dp inside an
        // opaque 80 dp bar, so its lower part was painted over. Require a gap.
        expect(
          playerRect.bottom,
          lessThanOrEqualTo(navRect.top),
          reason: 'player $playerRect must sit entirely above nav $navRect',
        );
        expect(playerRect.height, MiuixBottomLayout.playerHeight);

        // And pin our constant to what Flutter actually renders, so a future
        // Flutter change fails here instead of silently re-introducing overlap.
        expect(
          navRect.height,
          MiuixBottomLayout.materialNavBarHeight,
          reason: 'materialNavBarHeight is stale versus the real NavigationBar',
        );
      },
    );

    testWidgets('the Miuix player clears the real glass capsule', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        host(
          child: const MiuixBottomStack(
            navBar: AppBottomNavBar(
              selectedIndex: 0,
              onDestinationSelected: _noop,
            ),
            child: SizedBox.expand(),
          ),
        ),
      );
      await tester.pump();

      final navRect = tester.getRect(find.byKey(AppBottomNavBar.miuixKey));
      final playerRect = tester.getRect(find.byType(MiniPlayerBar));
      expect(
        navRect.top - playerRect.bottom,
        closeTo(MiuixBottomLayout.playerGap, 1.0),
        reason: 'the gap is a deliberate 8 dp under Miuix too',
      );
    });

    testWidgets('the player is painted after the nav bar', (tester) async {
      // Paint order, not geometry, is what makes occlusion impossible: whatever
      // comes last in a `Stack` wins. The nav bar used to be added last, so an
      // opaque bar covered the player, and once transparent its indicator pill and
      // label would still draw over it.
      useTallSurface(tester);
      await tester.pumpWidget(
        host(
          child: MiuixBottomStack(
            style: UiStyle.material,
            navBar: AppBottomNavBar(
              selectedIndex: 0,
              onDestinationSelected: _noop,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pump();

      final stack = tester.widget<Stack>(
        find.descendant(
          of: find.byType(MiuixBottomStack),
          matching: find.byType(Stack),
        ),
      );
      final playerIndex = stack.children.indexWhere(
        (child) => child is Positioned &&
            child.child is MiniPlayerBar,
      );
      final navIndex = stack.children.indexWhere(
        (child) => child is Positioned && child.child is AppBottomNavBar,
      );

      expect(playerIndex, isNonNegative);
      expect(navIndex, isNonNegative);
      expect(
        playerIndex,
        greaterThan(navIndex),
        reason: 'the player must be the last child so nothing draws over it',
      );
    });

    testWidgets('the player capsule sits the shared inset above the bottom', (
      tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        host(child: const MiuixBottomStack(child: SizedBox.expand())),
      );
      await tester.pump();

      final playerRect = tester.getRect(find.byType(MiniPlayerBar));
      // 800-tall surface; the capsule's bottom edge must be the shared inset.
      expect(playerRect.bottom, closeTo(800 - (36 + 52 + 8), 0.5));
    });

    testWidgets('an idle player collapses but keeps the layout slot', (
      tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        host(
          withSong: false,
          child: const MiuixBottomStack(child: SizedBox.expand()),
        ),
      );
      await tester.pump();

      // No song -> nothing painted, and the content inset drops to the nav
      // capsule only, so an idle page does not carry a 48 dp hole.
      final playerRect = tester.getRect(find.byType(MiniPlayerBar));
      expect(playerRect.height, 0);
    });

    testWidgets('insetChild decides whether the child reserves the clearance', (
      tester,
    ) async {
      // `AppRouteShell` passes `false`, because its child is go_router's nested
      // Navigator: a `Padding` around a Navigator is a band no route inside it can
      // paint into, and the routed frosted sheet then cannot reach the bottom edge —
      // the sharp strip the user saw while a page was leaving.
      //
      // The clearance has not disappeared; it moved inside each route
      // (`RouteBottomInset`). So this pins both directions of the flag, measured on
      // the child's own box.
      useTallSurface(tester);
      final childKey = GlobalKey();

      await tester.pumpWidget(
        host(
          child: MiuixBottomStack(
            child: SizedBox.expand(key: childKey),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.getSize(find.byKey(childKey)).height,
        800 - MiuixBottomLayout.contentInset(hostContext(tester)),
        reason: 'the default must keep reserving the clearance for direct content',
      );

      await tester.pumpWidget(
        host(
          child: MiuixBottomStack(
            insetChild: false,
            child: SizedBox.expand(key: childKey),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.getSize(find.byKey(childKey)).height,
        800,
        reason:
            'a nested Navigator must be allowed to paint to the bottom edge, or a '
            'frosted page cannot cover the capsule area',
      );
    });
  });
}

/// The element under test, for resolving the style-dependent inset in an assertion.
BuildContext hostContext(WidgetTester tester) =>
    tester.element(find.byType(MiuixBottomStack));

void _noop(int _) {}
