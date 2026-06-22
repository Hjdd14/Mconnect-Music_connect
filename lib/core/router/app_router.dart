import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_background.dart';
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
import '../../features/player/presentation/widgets/mini_player_bar.dart';
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
          ).chain(CurveTween(curve: Curves.easeOutCubic));
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
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = animation.drive(CurveTween(curve: Curves.easeOutCubic));
      final scale = Tween<double>(begin: 0.975, end: 1).animate(curved);

      return AppBackgroundShell(
        child: SizedBox.expand(
          key: const Key('app-route-background-surface'),
          child: FadeTransition(
            opacity: curved,
            child: ScaleTransition(scale: scale, child: child),
          ),
        ),
      );
    },
    child: child,
  );
}

class AppRouteShell extends StatelessWidget {
  final Widget child;
  final String? path;

  const AppRouteShell({super.key, required this.child, this.path});

  @override
  Widget build(BuildContext context) {
    final currentPath = path ?? GoRouterState.of(context).uri.path;
    final showMiniPlayer = currentPath != '/';

    if (!showMiniPlayer) {
      return child;
    }

    return Material(
      color: Colors.transparent,
      child: DefaultTextStyle(
        style: Theme.of(context).textTheme.bodyMedium ?? const TextStyle(),
        child: Column(
          children: [
            Expanded(child: child),
            const MiniPlayerBar(),
          ],
        ),
      ),
    );
  }
}
