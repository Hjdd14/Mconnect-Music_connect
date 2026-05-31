import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:mconnect/core/router/app_router.dart';
import 'package:mconnect/features/home/presentation/screens/home_screen.dart';
import 'package:mconnect/features/library/presentation/screens/library_screen.dart';
import 'package:mconnect/features/player/presentation/screens/player_screen.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/features/player/presentation/widgets/mini_player_bar.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

void main() {
  testWidgets(
    'home screen renders without eagerly creating a native audio player',
    (tester) async {
      var createdAudioControllers = 0;
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerProvider.overrideWith(
              (ref) => PlayerNotifier(
                audioControllerFactory: () {
                  createdAudioControllers++;
                  return _IdleAudioController();
                },
              ),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pump();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(createdAudioControllers, 0);
    },
  );

  testWidgets(
    'switching tabs updates the router location so player back returns to the active tab',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/?tab=3',
        routes: [
          GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerProvider.overrideWith(
              (ref) => PlayerNotifier(
                audioControllerFactory: () => _IdleAudioController(),
              ),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pump();
      expect(router.routeInformationProvider.value.uri.toString(), '/?tab=3');

      await tester.tap(find.byIcon(Icons.search).last);
      await tester.pump(const Duration(milliseconds: 150));

      expect(router.routeInformationProvider.value.uri.toString(), '/');
    },
  );

  testWidgets('home screen supports horizontal swiping between adjacent tabs', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerProvider.overrideWith(
            (ref) => PlayerNotifier(
              audioControllerFactory: () => _IdleAudioController(),
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pump();
    expect(router.routeInformationProvider.value.uri.toString(), '/');

    await tester.drag(find.byType(HomeScreen), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.toString(), '/?tab=1');

    await tester.drag(find.byType(HomeScreen), const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.toString(), '/');
  });

  testWidgets('home screen reuses cached tab pages across tab changes', (
    tester,
  ) async {
    var searchFactoryCalls = 0;
    var discoveryFactoryCalls = 0;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => HomeScreen(
            screenFactories: {
              0: () {
                searchFactoryCalls++;
                return const SizedBox();
              },
              1: () {
                discoveryFactoryCalls++;
                return const SizedBox();
              },
              2: () => const SizedBox(),
              3: () => const SizedBox(),
            },
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerProvider.overrideWith(
            (ref) => PlayerNotifier(
              audioControllerFactory: () => _IdleAudioController(),
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pump();
    expect(searchFactoryCalls, 1);

    await tester.tap(find.byIcon(Icons.explore).last);
    await tester.pumpAndSettle();
    expect(discoveryFactoryCalls, 1);

    await tester.tap(find.byIcon(Icons.search).last);
    await tester.pumpAndSettle();

    expect(searchFactoryCalls, 1);
    expect(discoveryFactoryCalls, 1);
  });

  testWidgets(
    'mini player passes the current location to the player back button',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/?tab=2',
        routes: [
          ShellRoute(
            builder: (context, state, child) => AppRouteShell(child: child),
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          GoRoute(
            path: '/player',
            builder: (context, state) => const PlayerScreen(),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerProvider.overrideWith((ref) => _SeededPlayerNotifier()),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pump();
      expect(find.byType(MiniPlayerBar), findsOneWidget);
      await tester.tap(find.text('Song 1'));
      await tester.pumpAndSettle();

      final backButton = find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.keyboard_arrow_down),
      );
      expect(backButton, findsOneWidget);

      await tester.tap(backButton);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.library_music), findsOneWidget);
      expect(find.text('Song 1'), findsOneWidget);
    },
  );

  testWidgets('route shell keeps mini player visible outside home tabs', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/likes',
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppRouteShell(child: child),
          routes: [
            GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
            GoRoute(
              path: '/likes',
              builder: (context, state) =>
                  const Scaffold(body: Center(child: Text('Likes Page'))),
            ),
          ],
        ),
        GoRoute(
          path: '/player',
          builder: (context, state) => const PlayerScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerProvider.overrideWith((ref) => _SeededPlayerNotifier()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pump();

    expect(find.text('Likes Page'), findsOneWidget);
    expect(find.byType(MiniPlayerBar), findsOneWidget);

    await tester.tap(find.text('Song 1'));
    await tester.pumpAndSettle();

    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(find.byType(MiniPlayerBar), findsNothing);
  });

  testWidgets('route shell gives mini player normal material text style', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/likes',
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppRouteShell(child: child),
          routes: [
            GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
            GoRoute(
              path: '/likes',
              builder: (context, state) =>
                  const Scaffold(body: Center(child: Text('Likes Page'))),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerProvider.overrideWith((ref) => _SeededPlayerNotifier()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pump();

    final songTextContext = tester.element(
      find.descendant(
        of: find.byType(MiniPlayerBar),
        matching: find.text('Song 1'),
      ),
    );
    final artistTextContext = tester.element(
      find.descendant(
        of: find.byType(MiniPlayerBar),
        matching: find.text('Artist 1'),
      ),
    );

    final songDefaultStyle = DefaultTextStyle.of(songTextContext).style;
    final artistDefaultStyle = DefaultTextStyle.of(artistTextContext).style;

    expect(songDefaultStyle.decorationStyle, isNot(TextDecorationStyle.double));
    expect(
      artistDefaultStyle.decorationStyle,
      isNot(TextDecorationStyle.double),
    );
    expect(songDefaultStyle.color, isNot(const Color(0xD0FF0000)));
    expect(artistDefaultStyle.color, isNot(const Color(0xD0FF0000)));
  });

  testWidgets(
    'library tab scrolls to settings on compact screens above the mini player',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 520);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const HomeScreen(
              screenFactories: {
                0: _EmptyTab.new,
                1: _EmptyTab.new,
                2: LibraryScreen.new,
                3: _EmptyTab.new,
              },
            ),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) =>
                const Scaffold(body: Center(child: Text('Settings Page'))),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerProvider.overrideWith((ref) => _SeededPlayerNotifier()),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pump();
      await tester.tap(find.byIcon(Icons.library_music).last);
      await tester.pumpAndSettle();

      expect(find.byType(MiniPlayerBar), findsOneWidget);
      expect(find.byType(LibraryScreen), findsOneWidget);

      final libraryScrollable = find.descendant(
        of: find.byType(LibraryScreen),
        matching: find.byType(Scrollable),
      );
      expect(libraryScrollable, findsOneWidget);
      expect(find.text('设置').hitTestable(), findsNothing);

      await tester.scrollUntilVisible(
        find.text('设置'),
        120,
        scrollable: libraryScrollable,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('设置').hitTestable());
      await tester.pumpAndSettle();

      expect(find.text('Settings Page'), findsOneWidget);
    },
  );

  testWidgets(
    'mini player progress updates when only playback progress changes',
    (tester) async {
      final notifier = _SeededPlayerNotifier()
        ..setProgress(
          position: const Duration(seconds: 30),
          duration: const Duration(minutes: 2),
        );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [playerProvider.overrideWith((ref) => notifier)],
          child: const MaterialApp(home: Scaffold(body: MiniPlayerBar())),
        ),
      );

      await tester.pump();

      LinearProgressIndicator progress() {
        return tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
      }

      expect(progress().value, 0.25);

      notifier.setProgress(
        position: const Duration(seconds: 60),
        duration: const Duration(minutes: 2),
      );
      await tester.pump();

      expect(progress().value, 0.5);
    },
  );

  for (final route in const [
    (path: '/likes', label: 'Likes Page'),
    (path: '/history', label: 'History Page'),
  ]) {
    testWidgets('player return keeps ${route.path} on the navigation stack', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          ShellRoute(
            builder: (context, state, child) => AppRouteShell(child: child),
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const HomeScreen(
                  screenFactories: {
                    0: _EmptyTab.new,
                    1: _EmptyTab.new,
                    2: _EmptyTab.new,
                    3: _EmptyTab.new,
                  },
                ),
              ),
              GoRoute(
                path: route.path,
                builder: (context, state) => Scaffold(
                  appBar: AppBar(title: Text(route.label)),
                  body: Center(child: Text(route.label)),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/player',
            builder: (context, state) => const PlayerScreen(),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerProvider.overrideWith((ref) => _SeededPlayerNotifier()),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pump();
      router.push(route.path);
      await tester.pumpAndSettle();
      expect(find.text(route.label), findsWidgets);

      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Song 1'));
        await tester.pumpAndSettle();
        expect(find.byType(PlayerScreen), findsOneWidget);

        await tester.tap(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.byIcon(Icons.keyboard_arrow_down),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(route.label), findsWidgets);
      }

      router.pop();
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.toString(), '/');
    });
  }

  testWidgets('player screen can be dismissed by swiping down', (tester) async {
    final router = GoRouter(
      initialLocation: '/player?from=%2F%3Ftab%3D2',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
        GoRoute(
          path: '/player',
          builder: (context, state) => const PlayerScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerProvider.overrideWith((ref) => _SeededPlayerNotifier()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(PlayerScreen), findsOneWidget);

    await tester.drag(find.byType(PlayerScreen), const Offset(0, 360));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.toString(), '/?tab=2');
  });

  testWidgets('player screen shows existing progress on first frame', (
    tester,
  ) async {
    final notifier = _SeededPlayerNotifier()
      ..setProgress(
        position: const Duration(minutes: 1, seconds: 23),
        duration: const Duration(minutes: 4, seconds: 5),
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [playerProvider.overrideWith((ref) => notifier)],
        child: const MaterialApp(home: PlayerScreen()),
      ),
    );

    await tester.pump();

    expect(find.text('01:23'), findsOneWidget);
    expect(find.text('04:05'), findsOneWidget);
  });

  testWidgets('player middle artwork toggles lyrics display', (tester) async {
    final router = GoRouter(
      initialLocation: '/player?from=%2F',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
        GoRoute(
          path: '/player',
          builder: (context, state) => const PlayerScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerProvider.overrideWith((ref) => _SeededPlayerNotifier()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.lyrics_outlined),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('player_middle_toggle')));
    await tester.pump(const Duration(milliseconds: 350));

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.album),
      ),
      findsOneWidget,
    );
  });
}

const _song = Song(
  id: 'song-1',
  platform: PlatformType.netease,
  name: 'Song 1',
  artists: [Artist(id: 'artist-1', name: 'Artist 1')],
);

class _SeededPlayerNotifier extends PlayerNotifier {
  _SeededPlayerNotifier()
    : super(
        audioController: _IdleAudioController(),
        audioControllerFactory: () => _IdleAudioController(),
      ) {
    state = state.copyWith(
      currentSong: _song,
      playlist: const [_song],
      currentIndex: 0,
    );
  }

  void setProgress({required Duration position, required Duration duration}) {
    state = state.copyWith(position: position, duration: duration);
  }
}

class _EmptyTab extends StatelessWidget {
  const _EmptyTab();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _IdleAudioController implements PlayerAudioController {
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _playerStateController =
      StreamController<AudioPlaybackState>.broadcast();

  @override
  bool get playing => false;

  @override
  Duration get position => Duration.zero;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<AudioPlaybackState> get playerStateStream =>
      _playerStateController.stream;

  @override
  Future<void> stop() async {}

  @override
  Future<void> setUrl(String url, {Song? song}) async {}

  @override
  Future<void> play() async {
    _playerStateController.add(
      const AudioPlaybackState(
        playing: true,
        processingState: just_audio.ProcessingState.ready,
      ),
    );
  }

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
  Future<void> dispose() async {
    await _positionController.close();
    await _durationController.close();
    await _playerStateController.close();
  }
}
