import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../motion/app_motion.dart';
import '../motion/app_page_transition.dart';
import '../theme/app_background.dart';
import '../theme/ui_style_provider.dart';
import '../widgets/app_bottom_nav_bar.dart';
import '../widgets/miuix_bottom_stack.dart';
import '../../features/album/presentation/pages/album_page.dart';
import '../../features/artist/presentation/pages/artist_page.dart';
import '../../features/backup/presentation/pages/backup_page.dart';
import '../../features/new_songs/presentation/pages/new_songs_page.dart';
import '../../features/toplist/presentation/pages/toplists_page.dart';
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
import '../../features/player/presentation/pages/queue_page.dart';
import '../../features/player/presentation/screens/player_screen.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/stats/presentation/pages/listening_stats_page.dart';
import '../../features/smart_playlists/presentation/pages/smart_playlist_editor_page.dart';
import '../../features/smart_playlists/presentation/pages/smart_playlists_page.dart';
import '../../models/platform_type.dart';

/// 根 Navigator 的 key：`/queue` 用 `parentNavigatorKey` 挂到它上面（见该路由
/// 的注释）。go_router 的顶层 Navigator 默认没有显式 key，挂根必须显式声明。
final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root-navigator',
);

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
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
    // 播放队列页（W1-D）。
    //
    // ⚠️ 历史与教训：W1-D 曾把本页放在 ShellRoute 内，真机（release/debug 均
    // 复现）点了入口后整页 touch-dead、音乐仍在播。设备日志抓到两次同一断言：
    //   navigator.dart:4096 '!keyReservation.contains(key)': is not true
    // （完整栈：NavigatorState._updatePages ← didUpdateWidget，即 pages 列表
    // 本身携带重复 key），随后 pop 时又炸 go_router builder.dart:424 的
    // `_pageToRouteMatchBase[page]!` null check。
    //
    // 成因：从 ShellRoute **外**的顶层路由（/player）push ShellRoute 内的路由
    // 时，go_router 14.8.1 会构造 ImperativeRouteMatch，其匹配链把 ShellRoute
    // 整体重建一遍；根 Navigator 与嵌套 Navigator 的 pages 在同一帧内分别用
    // `ValueKey(route.hashCode)`（ShellRouteMatch）与 `ValueKey(newMatchedPath)`
    // （RouteMatch）派生 key，两个 Navigator 的 page 集合在重建瞬间对不上，
    // /queue 的 key 在其中一个 Navigator 的 pages 里出现两次。防重入闸门挡不住
    // 它——断言在**一次** push 内部就发生了。
    //
    // 所以本页挂到**根 Navigator**（parentNavigatorKey 指向根），与 /player
    // 同构：入口只在 /player 里，返回即回到播放页，不需要 shell 的迷你播放器
    //（用户此刻就在全屏播放页上）。`test/app_router_routes_test.dart` 旧的
    //「必须在 ShellRoute 内」断言随之更新为「必须在根 Navigator」。
    GoRoute(
      path: '/queue',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => CustomTransitionPage<void>(
        key: state.pageKey,
        name: state.name ?? state.path,
        restorationId: state.pageKey.value,
        transitionDuration: AppMotion.routeForward,
        reverseTransitionDuration: AppMotion.routeReverse,
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            buildAppPageTransition(
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          reduceMotion: MediaQuery.disableAnimationsOf(context),
          child: AppBackgroundShell(
            drawImage: false,
            drawScrim: false,
            baseOpacity: secondaryBackingOpacity,
            child: SizedBox.expand(
              key: const Key('app-route-background-surface'),
              child: SecondaryGlassSurface(child: child),
            ),
          ),
        ),
        child: const QueuePage(),
      ),
    ),
    ShellRoute(
      pageBuilder: (context, state, child) => _appShellPage(
        state,
        AppRouteShell(path: state.uri.path, child: child),
      ),
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) =>
              _appLeafPage(state, const HomeScreen()),
        ),
        GoRoute(
          path: '/recommendations',
          pageBuilder: (context, state) =>
              _appLeafPage(state, const RecommendationsPage()),
        ),
        GoRoute(
          path: '/rankings',
          pageBuilder: (context, state) =>
              _appLeafPage(state, const RankingsPage()),
        ),
        GoRoute(
          path: '/likes',
          pageBuilder: (context, state) =>
              _appLeafPage(state, const LikesPage()),
        ),
        GoRoute(
          path: '/history',
          pageBuilder: (context, state) =>
              _appLeafPage(state, const HistoryPage()),
        ),
        GoRoute(
          path: '/import-playlist',
          pageBuilder: (context, state) =>
              _appLeafPage(state, const ImportPlaylistPage()),
        ),
        GoRoute(
          path: '/platform-playlists',
          pageBuilder: (context, state) =>
              _appLeafPage(state, const PlatformPlaylistsPage()),
        ),
        GoRoute(
          path: '/local-music',
          pageBuilder: (context, state) =>
              _appLeafPage(state, const LocalMusicPage()),
        ),
        GoRoute(
          path: '/offline-cache',
          pageBuilder: (context, state) =>
              _appLeafPage(state, const OfflineCachePage()),
        ),
        GoRoute(
          path: '/listening-stats',
          pageBuilder: (context, state) =>
              _appLeafPage(state, const ListeningStatsPage()),
        ),
        GoRoute(
          path: '/smart-playlists',
          pageBuilder: (context, state) =>
              _appLeafPage(state, const SmartPlaylistsPage()),
        ),
        GoRoute(
          path: '/smart-playlists/editor',
          pageBuilder: (context, state) => _appLeafPage(
            state,
            SmartPlaylistEditorPage(ruleId: state.uri.queryParameters['id']),
          ),
        ),
        GoRoute(
          path: '/playlist/:platform/:id',
          pageBuilder: (context, state) {
            final platform = PlatformType.parse(
              state.pathParameters['platform']!,
            );
            return _appLeafPage(
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
          path: '/toplists',
          pageBuilder: (context, state) =>
              _appLeafPage(state, const ToplistsPage()),
        ),
        GoRoute(
          path: '/toplist/:platform/:id',
          pageBuilder: (context, state) => _appLeafPage(
            state,
            ToplistDetailPage(
              platform: PlatformType.parse(state.pathParameters['platform']!),
              toplistId: state.pathParameters['id']!,
              toplistName: state.uri.queryParameters['name'],
            ),
          ),
        ),
        GoRoute(
          path: '/album/:platform/:id',
          pageBuilder: (context, state) => _appLeafPage(
            state,
            AlbumPage(
              platform: PlatformType.parse(state.pathParameters['platform']!),
              albumId: state.pathParameters['id']!,
              albumName: state.uri.queryParameters['name'],
            ),
          ),
        ),
        GoRoute(
          path: '/artist/:platform/:id',
          pageBuilder: (context, state) => _appLeafPage(
            state,
            ArtistPage(
              platform: PlatformType.parse(state.pathParameters['platform']!),
              artistId: state.pathParameters['id']!,
              artistName: state.uri.queryParameters['name'],
            ),
          ),
        ),
        GoRoute(
          path: '/new-songs',
          pageBuilder: (context, state) =>
              _appLeafPage(state, const NewSongsPage()),
        ),
        GoRoute(
          path: '/backup',
          pageBuilder: (context, state) =>
              _appLeafPage(state, const BackupPage()),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) =>
              _appLeafPage(state, const SettingsPage()),
        ),
        GoRoute(
          path: '/settings/accounts',
          pageBuilder: (context, state) =>
              _appLeafPage(state, const SettingsAccountsPage()),
        ),
        GoRoute(
          path: '/settings/appearance',
          pageBuilder: (context, state) =>
              _appLeafPage(state, const SettingsAppearancePage()),
        ),
        GoRoute(
          path: '/settings/floating-lyrics',
          pageBuilder: (context, state) =>
              _appLeafPage(state, const SettingsFloatingLyricsPage()),
        ),
        GoRoute(
          path: '/settings/audio',
          pageBuilder: (context, state) =>
              _appLeafPage(state, const SettingsAudioPage()),
        ),
        GoRoute(
          path: '/settings/diagnostics',
          pageBuilder: (context, state) =>
              _appLeafPage(state, const SettingsDiagnosticsPage()),
        ),
        GoRoute(
          path: '/login/:platform',
          pageBuilder: (context, state) {
            final platform = PlatformType.parse(
              state.pathParameters['platform']!,
            );
            return _appLeafPage(state, LoginPage(platform: platform));
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
///   frosted sheet in `app_background.dart`, whose own opaque floor is what masks
///   the page below — the picture stays visible because that floor *is* the
///   picture, blurred, not a flat colour.
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

/// Builds one of the app's transparent-backed pages.
///
/// ## Two kinds of page, and why they are no longer one function
///
/// This used to be a single `_transparentAppPage` that decided everything from
/// `state.uri.path == '/'` — including whether to wrap the page in the frosted
/// sheet. Because the same function also built the **shell** page (whose child is
/// `AppRouteShell`, i.e. the capsule layer plus the nested navigator), the shell
/// page got a sheet on every non-home location, and that sheet was the only thing
/// covering the bottom `contentInset` — the band the nested navigator cannot reach
/// (see `MiuixBottomStack.insetChild`).
///
/// `state.uri.path` flips to `/` the instant a `pop` starts, so that patch
/// vanished on the transition's first frame while the page sliding away kept its
/// own sheet for the rest of the animation: a sharp band under a frosted page.
///
/// The two roles are now separate ([appShellPage] / [appLeafPage]) and the bottom
/// clearance is applied to the *route's content* ([RouteBottomInset]) instead of
/// around the navigator, so no band needs patching at all.
CustomTransitionPage<void> _appPage(
  GoRouterState state,
  Widget child, {
  /// Wrap the page in the frosted sheet. False for the shell page, which paints
  /// the capsules and must stay transparent above the app background.
  required bool frost,

  /// Reserve the floating bottom stack's clearance inside the route.
  required bool insetContent,
}) {
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
      // The masking the opaque plate was doing is now done **structurally** by the
      // frosted sheet (`SecondaryGlassSurface`) on every secondary page. It has an
      // opaque floor and paints its own copy of the picture, so the page below
      // cannot composite through it — and because the floor *is* the (blurred)
      // picture, "opaque" no longer means "the background disappears".
      //
      // That sheet is also why no `BackdropFilter` appears in this file any more:
      // a backdrop filter samples the live scene, which during a transition still
      // contains the outgoing route, which is how the previous page's text ended up
      // smeared into a visible ghost inside the panel. **Reintroducing one brings
      // the ghost back.** See `SecondaryGlassSurface`'s doc comment.
      //
      // `drawImage: false` is still essential: this plate must never paint its own
      // copy of the background. The geometry scales the image to the viewport it is
      // handed, and a second copy here would double the background — the
      // "重复 / 缩小 / 黑边" that was reported earlier. (The frosted sheet *may*
      // paint a copy, but only because it is pinned to `AppBackgroundViewport` and
      // asserted pixel-equal by `test/secondary_plate_geometry_test.dart`.)
      final content = insetContent ? RouteBottomInset(child: child) : child;
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
            child: frost ? SecondaryGlassSurface(child: content) : content,
          ),
        ),
      );
    },
    child: child,
  );
}

/// The page that hosts `AppRouteShell`: the bottom capsules plus go_router's
/// nested `Navigator`.
///
/// It gets no frosted sheet and no content inset. The sheet belongs to the routed
/// pages (which the nested navigator holds) and the inset belongs inside them —
/// both for the reason spelled out on [_appPage].
CustomTransitionPage<void> _appShellPage(GoRouterState state, Widget child) =>
    _appPage(state, child, frost: false, insetContent: false);

/// A routed page inside the shell, or a top-level page outside it.
///
/// Frosted unless it is the home tab host, and always carrying its own bottom
/// clearance.
CustomTransitionPage<void> _appLeafPage(GoRouterState state, Widget child) =>
    _appPage(
      state,
      child,
      frost: state.uri.path != '/',
      insetContent: true,
    );

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

  /// Throttles the capsule's taps (see [TabSwitchThrottle]).
  final _tabSwitch = TabSwitchThrottle();

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
    // This is the *production* tab path. With a `ShellRoute` above it,
    // `HomeScreen` reports `ownsBottomLayer = false` and never runs its own
    // debounce, so the guard has to live here — the previous protection sat on a
    // path that is never taken while the shell exists.
    if (!_tabSwitch.shouldAccept(index, _tabIndex)) return;

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
          // The nested navigator must fill the screen: a `Padding` around it is a
          // band no route inside it can paint into, which is what made the bottom of
          // the screen stay sharp while a frosted page slid away. Each routed page
          // reserves the clearance itself (`RouteBottomInset`).
          insetChild: false,
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

/// Debounce window for tab switches made through the bottom capsule.
const Duration tabSwitchDebounce = Duration(milliseconds: 80);

/// Leading-edge throttle for tab switches.
///
/// The capsule sits under a fast thumb, and every accepted switch rebuilds the
/// tab host and starts a page transition, so a burst of taps used to queue one
/// transition per tap. The *first* tap is applied immediately (leading edge), so
/// the bar never feels laggy; only taps inside [window] of an accepted one are
/// dropped.
///
/// Extracted from the shell (and given an injectable clock) so this behaviour —
/// which only shows up as a dropped frame on a real device — can be asserted
/// directly instead of racing wall-clock time in a widget test.
@visibleForTesting
class TabSwitchThrottle {
  TabSwitchThrottle({
    this.window = tabSwitchDebounce,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration window;
  final DateTime Function() _clock;

  DateTime? _lastAcceptedAt;

  /// Taps dropped by the throttle (same tab, or inside [window]).
  int skipped = 0;

  /// Whether a tap on [index] may switch away from [currentIndex].
  bool shouldAccept(int index, int currentIndex) {
    // Tapping the tab you are already on must not re-issue `go()` (it still
    // rebuilds the host and re-enters the transition).
    if (index == currentIndex) {
      skipped++;
      return false;
    }

    final now = _clock();
    final last = _lastAcceptedAt;
    if (last != null && now.difference(last) < window) {
      skipped++;
      return false;
    }

    _lastAcceptedAt = now;
    return true;
  }
}
