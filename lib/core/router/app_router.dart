import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../motion/app_motion.dart';
import '../motion/app_page_transition.dart';
import '../theme/app_background.dart';
import '../theme/ui_style_provider.dart';
import '../widgets/app_bottom_nav_bar.dart';
import '../widgets/miuix_bottom_stack.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/discovery/presentation/pages/rankings_page.dart';
import '../../features/discovery/presentation/pages/recommendations_page.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/library/presentation/pages/history_page.dart';
import '../../features/library/presentation/pages/import_playlist_page.dart';
import '../../features/library/presentation/pages/likes_page.dart';
import '../../features/library/presentation/pages/platform_playlists_page.dart';
import '../../features/library/presentation/pages/playlist_detail_page.dart';
import '../../features/local_music/presentation/pages/local_music_page.dart';
import '../../features/offline_cache/presentation/pages/offline_cache_page.dart';
import '../../features/player/presentation/screens/player_screen.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/stats/presentation/pages/listening_stats_page.dart';
import '../../features/smart_playlists/presentation/pages/smart_playlist_editor_page.dart';
import '../../features/smart_playlists/presentation/pages/smart_playlists_page.dart';
import '../../models/platform_type.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/player',
      pageBuilder: (context, state) => CustomTransitionPage(
        child: const PlayerGlassRouteSurface(child: PlayerScreen()),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final tween = Tween(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).chain(CurveTween(curve: AppMotion.routeCurve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    ),
    ShellRoute(
      pageBuilder: (context, state, child) => _transparentAppPage(
        state,
        AppRouteShell(path: state.uri.path, child: child),
      ),
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) =>
              _transparentAppPage(state, const HomeScreen()),
        ),
        GoRoute(
          path: '/recommendations',
          pageBuilder: (context, state) =>
              _transparentAppPage(state, const RecommendationsPage()),
        ),
        GoRoute(
          path: '/rankings',
          pageBuilder: (context, state) =>
              _transparentAppPage(state, const RankingsPage()),
        ),
        GoRoute(
          path: '/likes',
          pageBuilder: (context, state) =>
              _transparentAppPage(state, const LikesPage()),
        ),
        GoRoute(
          path: '/history',
          pageBuilder: (context, state) =>
              _transparentAppPage(state, const HistoryPage()),
        ),
        GoRoute(
          path: '/import-playlist',
          pageBuilder: (context, state) =>
              _transparentAppPage(state, const ImportPlaylistPage()),
        ),
        GoRoute(
          path: '/platform-playlists',
          pageBuilder: (context, state) =>
              _transparentAppPage(state, const PlatformPlaylistsPage()),
        ),
        GoRoute(
          path: '/local-music',
          pageBuilder: (context, state) =>
              _transparentAppPage(state, const LocalMusicPage()),
        ),
        GoRoute(
          path: '/offline-cache',
          pageBuilder: (context, state) =>
              _transparentAppPage(state, const OfflineCachePage()),
        ),
        GoRoute(
          path: '/listening-stats',
          pageBuilder: (context, state) =>
              _transparentAppPage(state, const ListeningStatsPage()),
        ),
        GoRoute(
          path: '/smart-playlists',
          pageBuilder: (context, state) =>
              _transparentAppPage(state, const SmartPlaylistsPage()),
        ),
        GoRoute(
          path: '/smart-playlists/editor',
          pageBuilder: (context, state) => _transparentAppPage(
            state,
            SmartPlaylistEditorPage(ruleId: state.uri.queryParameters['id']),
          ),
        ),
        GoRoute(
          path: '/playlist/:platform/:id',
          pageBuilder: (context, state) {
            final platformStr = state.pathParameters['platform']!;
            final platform = PlatformType.values.firstWhere(
              (p) => p.name == platformStr,
              orElse: () => PlatformType.netease,
            );
            return _transparentAppPage(
              state,
              PlaylistDetailPage(
                platform: platform,
                playlistId: state.pathParameters['id']!,
                playlistName: state.uri.queryParameters['name'] ?? '歌单',
                coverUrl: state.uri.queryParameters['cover'],
              ),
            );
          },
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) =>
              _transparentAppPage(state, const SettingsPage()),
        ),
        GoRoute(
          path: '/settings/accounts',
          pageBuilder: (context, state) =>
              _transparentAppPage(state, const SettingsAccountsPage()),
        ),
        GoRoute(
          path: '/settings/appearance',
          pageBuilder: (context, state) =>
              _transparentAppPage(state, const SettingsAppearancePage()),
        ),
        GoRoute(
          path: '/settings/floating-lyrics',
          pageBuilder: (context, state) =>
              _transparentAppPage(state, const SettingsFloatingLyricsPage()),
        ),
        GoRoute(
          path: '/settings/audio',
          pageBuilder: (context, state) =>
              _transparentAppPage(state, const SettingsAudioPage()),
        ),
        GoRoute(
          path: '/settings/diagnostics',
          pageBuilder: (context, state) =>
              _transparentAppPage(state, const SettingsDiagnosticsPage()),
        ),
        GoRoute(
          path: '/login/:platform',
          pageBuilder: (context, state) {
            final platformStr = state.pathParameters['platform']!;
            final platform = PlatformType.values.firstWhere(
              (p) => p.name == platformStr,
              orElse: () => PlatformType.netease,
            );
            return _transparentAppPage(state, LoginPage(platform: platform));
          },
        ),
      ],
    ),
  ],
);

/// Opacity of a page's backing plate, which sits over the app-level background.
///
/// This used to be one value for every route, which dimmed the user's background
/// everywhere — including the home screen, where it should read at nearly full
/// strength. It is now per route:
///
/// * the **home** screen keeps a whisper of dim so light-on-dark text stays legible
///   over a bright image;
/// * a **secondary** page paints no plate at all. Its readability comes from the
///   liquid-glass sheet in `app_background.dart`, which blurs the background
///   instead of flattening it — so the picture stays visible, which is the whole
///   point of setting a custom background.
///
/// A plate of `0` is only safe because the transition no longer depends on it: the
/// incoming page is opaque and covers the page below (`app_page_transition.dart`).
/// **If that ever changes back to a cross-fade, these values must go back up**, or
/// the two pages will composite.
const double homeBackingOpacity = 0.08;
const double secondaryBackingOpacity = 0;

/// Backing opacity for [location].
double routeBackingOpacityFor(String location) =>
    location == '/' ? homeBackingOpacity : secondaryBackingOpacity;

CustomTransitionPage<void> _transparentAppPage(
  GoRouterState state,
  Widget child,
) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    name: state.name ?? state.path,
    arguments: <String, String>{
      ...state.pathParameters,
      ...state.uri.queryParameters,
    },
    restorationId: state.pageKey.value,
    transitionDuration: AppMotion.routeForward,
    reverseTransitionDuration: AppMotion.routeReverse,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      // The plate carries ONE responsibility: per-route static readability (the home
      // screen lets the background read at nearly full strength, a secondary page
      // lets it through entirely).
      //
      // It deliberately does NOT go opaque during the transition. An earlier attempt
      // did — to stop the outgoing page showing through the strip the incoming page
      // had not covered yet — and that fixed the leftover while introducing a worse
      // artefact: the opaque plate is a *flat colour*, so it blanked the user's
      // background for the whole animation and then released it, which reads as a
      // solid-colour flash on entering a page.
      //
      // The masking that the opaque plate was doing is already provided by the
      // acrylic sheet (`SecondaryGlassSurface`) that sits above this plate on every
      // secondary page: it blurs and lightly fills whatever is behind it, for the
      // whole transition and after it. One mechanism, always on, instead of two that
      // fight. **Lowering the acrylic's fill or removing it will bring the leftover
      // back.**
      // `drawImage: false` is still essential: this plate must never paint its own
      // copy of the background. The geometry scales the image to the viewport it is
      // handed, and a second copy would double the background — the
      // "重复 / 缩小 / 黑边" that was reported earlier.
      final isHome = state.uri.path == '/';
      return buildAppPageTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        reduceMotion: MediaQuery.disableAnimationsOf(context),
        child: AppBackgroundShell(
          drawImage: false,
          drawScrim: false,
          baseOpacity: routeBackingOpacityFor(state.uri.path),
          child: SizedBox.expand(
            key: const Key('app-route-background-surface'),
            child: isHome ? child : SecondaryGlassSurface(child: child),
          ),
        ),
      );
    },
    child: child,
  );
}

/// Hands the shell's live tab index to the home screen.
///
/// The shell owns the tab index because the nav capsule is rendered by the
/// shell; the home screen owns the `PageView` because the pages are its content.
/// This scope is how they agree.
///
/// Its **absence** is load-bearing: `HomeScreen` uses it to detect that no
/// `ShellRoute` is above it (several routers mount the home screen directly) and
/// then renders its own bottom layer instead.
class TabHostScope extends InheritedWidget {
  final int index;
  final ValueChanged<int> onTabSelected;

  const TabHostScope({
    super.key,
    required this.index,
    required this.onTabSelected,
    required super.child,
  });

  static TabHostScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TabHostScope>();

  @override
  bool updateShouldNotify(TabHostScope oldWidget) =>
      oldWidget.index != index || oldWidget.onTabSelected != onTabSelected;
}

class AppRouteShell extends ConsumerStatefulWidget {
  final Widget child;
  final String? path;

  const AppRouteShell({super.key, required this.child, this.path});

  @override
  ConsumerState<AppRouteShell> createState() => _AppRouteShellState();
}

class _AppRouteShellState extends ConsumerState<AppRouteShell> {
  int _tabIndex = 0;

  /// Only the home tabs carry a nav capsule; secondary pages show the player
  /// alone.
  bool get _isHomeTabs {
    final currentPath = widget.path ?? GoRouterState.of(context).uri.path;
    return currentPath == '/';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The route param is the single source of truth for the active tab. Mirroring
    // it here (rather than keeping an independent copy) is what keeps the nav
    // capsule correct after a pop, a deep link, or any navigation that did not go
    // through the capsule. `_onTabSelected` writes the same param, so the two can
    // only ever agree; the brief lag of one frame is not observable.
    if (!_isHomeTabs) return;
    final raw = GoRouterState.of(context).uri.queryParameters['tab'];
    final tab = int.tryParse(raw ?? '') ?? 0;
    if (tab != _tabIndex) {
      _tabIndex = tab;
    }
  }

  void _onTabSelected(int index) {
    setState(() => _tabIndex = index);
    // The location must follow the tab, both so the route stays the source of
    // truth and so the player's "back" target is the tab the user is actually on.
    // `HomeScreen` does the same when its PageView settles.
    context.go(index == 0 ? '/' : '/?tab=$index');
  }

  @override
  Widget build(BuildContext context) {
    // The mini player is rendered HERE, once, for every route in this shell — and
    // never by a route page. When each page built its own copy, a push had both
    // the outgoing and the incoming page painting a capsule at the same position
    // with different animation opacities, so the two visibly stacked (the
    // flashing the user reported).
    //
    // The nav capsule is rendered here too, but its index is mirrored down to
    // `HomeScreen` through [TabHostScope] so the tab indicator stays tied to the
    // `PageView` animation the home screen drives.
    final navBar = _isHomeTabs
        ? AppBottomNavBar(
            selectedIndex: _tabIndex,
            onDestinationSelected: _onTabSelected,
          )
        : null;

    final style = ref.watch(uiStyleProvider).style;

    return Material(
      color: Colors.transparent,
      child: DefaultTextStyle(
        style: Theme.of(context).textTheme.bodyMedium ?? const TextStyle(),
        child: MiuixBottomStack(
          style: style,
          navBar: navBar,
          // The player is drawn AFTER the nav bar inside the stack, so the bar can
          // never paint over it. That ordering, plus the per-style inset, is what
          // keeps the player fully visible.
          child: TabHostScope(
            index: _tabIndex,
            onTabSelected: _onTabSelected,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
