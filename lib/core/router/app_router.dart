import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
import '../../features/player/presentation/screens/player_screen.dart';
import '../../features/player/presentation/widgets/mini_player_bar.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/stats/presentation/pages/listening_stats_page.dart';
import '../../models/platform_type.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/player',
      pageBuilder: (context, state) => CustomTransitionPage(
        child: const PlayerScreen(),
        transitionsBuilder: (_, animation, __, child) {
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
      builder: (context, state, child) => AppRouteShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
        GoRoute(
          path: '/recommendations',
          builder: (context, state) => const RecommendationsPage(),
        ),
        GoRoute(
          path: '/rankings',
          builder: (context, state) => const RankingsPage(),
        ),
        GoRoute(path: '/likes', builder: (context, state) => const LikesPage()),
        GoRoute(
          path: '/history',
          builder: (context, state) => const HistoryPage(),
        ),
        GoRoute(
          path: '/import-playlist',
          builder: (context, state) => const ImportPlaylistPage(),
        ),
        GoRoute(
          path: '/platform-playlists',
          builder: (context, state) => const PlatformPlaylistsPage(),
        ),
        GoRoute(
          path: '/local-music',
          builder: (context, state) => const LocalMusicPage(),
        ),
        GoRoute(
          path: '/listening-stats',
          builder: (context, state) => const ListeningStatsPage(),
        ),
        GoRoute(
          path: '/playlist/:platform/:id',
          builder: (context, state) {
            final platformStr = state.pathParameters['platform']!;
            final platform = PlatformType.values.firstWhere(
              (p) => p.name == platformStr,
              orElse: () => PlatformType.netease,
            );
            return PlaylistDetailPage(
              platform: platform,
              playlistId: state.pathParameters['id']!,
              playlistName: state.uri.queryParameters['name'] ?? '歌单',
              coverUrl: state.uri.queryParameters['cover'],
            );
          },
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsPage(),
        ),
        GoRoute(
          path: '/login/:platform',
          builder: (context, state) {
            final platformStr = state.pathParameters['platform']!;
            final platform = PlatformType.values.firstWhere(
              (p) => p.name == platformStr,
              orElse: () => PlatformType.netease,
            );
            return LoginPage(platform: platform);
          },
        ),
      ],
    ),
  ],
);

class AppRouteShell extends StatelessWidget {
  final Widget child;

  const AppRouteShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final showMiniPlayer = path != '/';

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
