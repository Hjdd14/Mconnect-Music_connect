import 'package:flutter/material.dart';
import '../../../../core/theme/platform_accent.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../models/platform_type.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../providers/playlist_recommendations_provider.dart';

class DiscoveryScreen extends ConsumerStatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  ConsumerState<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends ConsumerState<DiscoveryScreen> {
  @override
  void initState() {
    super.initState();
    ref.listenManual(authProvider.select((s) => s.loggedUsers), (
      previous,
      next,
    ) {
      if (!mounted || previous == next) return;
      ref.read(playlistRecommendationsProvider.notifier).loadRecommendations();
    });
    final state = ref.read(playlistRecommendationsProvider);
    if (!state.hasData && !state.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(playlistRecommendationsProvider.notifier)
            .loadRecommendations();
      });
    }
  }

  Color _platformColor(PlatformType platform) =>
      PlatformAccent.colorOf(context, platform);

  @override
  Widget build(BuildContext context) {
    final recState = ref.watch(playlistRecommendationsProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        // Scrollable, not a bare Column.
        //
        // Device log 2026-10-09 while the phone was in LANDSCAPE (the screenshot
        // shows the yellow "BOTTOM OVERFLOWED BY 35 PIXELS" bar):
        //   23:02:10  13 pixels   23:02:11  35 pixels   23:02:30  87 pixels
        // A fixed Column (title + three entry cards + a section header + an
        // Expanded area) cannot fit when the available height drops from ~640 to
        // ~360 logical pixels, and the `Expanded` child cannot absorb the
        // shortfall. Making the page scrollable removes the whole class instead of
        // tuning one height: whatever the shortfall is, the user can reach it.
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '发现',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              // Three side-by-side entries, all the same compact weight.
              //
              // The 每日推荐 and 榜单中心 cards that used to sit above this row are
              // gone: 榜单中心 was listed twice (card + tile), the cards' subtitles
              // did not fit a compact layout, and the 艺人 / 专辑 tile only handed
              // over to the search tab, which is already one tap away in the bottom
              // bar. Each button keeps the destination it always had.
              Row(
                children: [
                  Expanded(
                    child: _DiscoveryEntry(
                      icon: Icons.wb_sunny,
                      label: '每日推荐',
                      onTap: () => context.push('/recommendations'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DiscoveryEntry(
                      icon: Icons.leaderboard_outlined,
                      label: '榜单中心',
                      onTap: () => context.push('/toplists'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DiscoveryEntry(
                      icon: Icons.fiber_new_outlined,
                      label: '新歌速递',
                      onTap: () => context.push('/new-songs'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '歌单推荐',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  if (recState.hasData)
                    TextButton(
                      onPressed: () => context.push('/recommendations'),
                      child: const Text('查看全部'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // The grid gets a bounded viewport instead of `Expanded`: inside a
              // scroll view there is no incoming height constraint to expand into,
              // so the recommendation area is given a sensible fixed height and
              // becomes one more thing the page scrolls past.
              SizedBox(
                height: _recommendationsViewportHeight(context),
                child: _recommendationsArea(recState),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Height for the recommendation grid inside the scroll view.
  ///
  /// Two rows of cards plus the gap, measured against the grid's own item extent;
  /// proportionally smaller on a short (landscape) viewport so the page does not
  /// become mostly one oversized grid.
  static double _recommendationsViewportHeight(BuildContext context) {
    final available = MediaQuery.sizeOf(context).height;
    if (available < 420) return 220;
    if (available < 700) return 300;
    return 360;
  }

  /// The 歌单推荐 area below the three compact entries.
  ///
  /// A *failure* and *nothing to show* are deliberately different states here.
  /// The page used to render `recState.error ?? '登录后查看更多'` in a single
  /// branch, which meant a platform that had actually thrown was presented as
  /// "not signed in" — with no way to try again. Now a real per-platform failure
  /// gets `AsyncStateView.error` (retry mandatory, per the shared contract) and
  /// everything else stays an `empty` state whose copy is unchanged.
  Widget _recommendationsArea(PlaylistRecommendationsState recState) {
    if (recState.isLoading) return const AsyncStateView.loading();
    if (recState.hasData) {
      return _RecommendationGrid(
        recState: recState,
        platformColor: _platformColor,
      );
    }

    // `errorsByPlatform` is non-empty only when a platform call actually threw —
    // the provider also reports "请先登录平台账号" / "暂无推荐内容" through
    // `error`, but with no per-platform failure recorded. Classifying on that
    // (rather than on the message text) keeps the two apart.
    final message = recState.error;
    if (recState.errorsByPlatform.isNotEmpty && message != null) {
      return AsyncStateView.error(
        title: message,
        onRetry: () => ref
            .read(playlistRecommendationsProvider.notifier)
            .loadRecommendations(),
      );
    }

    return AsyncStateView.empty(
      title: message ?? '登录后查看更多',
      icon: Icons.music_note,
    );
  }
}

/// One of the three compact entries at the top of the 发现 tab
/// (每日推荐 / 榜单中心 / 新歌速递): icon above a single-line label, side by side.
///
/// Deliberately has no subtitle - the row of three is the compact form of these
/// destinations, and the descriptions the removed cards carried did not fit.
class _DiscoveryEntry extends StatelessWidget {
  const _DiscoveryEntry({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: cs.primary),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecommendationGrid extends ConsumerWidget {
  final PlaylistRecommendationsState recState;
  final Color Function(PlatformType) platformColor;

  const _RecommendationGrid({
    required this.recState,
    required this.platformColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Flatten all songs from all platforms into a grid
    final allSongs = recState.songsByPlatform.entries
        .expand((e) => e.value.take(6).map((s) => (song: s, platform: e.key)))
        .toList();
    final songs = allSongs.map((entry) => entry.song).toList();

    return AppScrollbar(
      builder: (controller) => GridView.builder(
        controller: controller,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.75,
        ),
        itemCount: allSongs.length.clamp(0, 9),
        itemBuilder: (context, index) {
          final entry = allSongs[index];
          final song = entry.song;
          final color = platformColor(entry.platform);

          return GestureDetector(
            onTap: () => ref
                .read(playerProvider.notifier)
                .playPlaylist(songs, startIndex: index),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: song.coverUrl != null
                        ? CachedNetworkImage(
                            imageUrl: song.coverUrl!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            memCacheWidth: 600,
                            placeholder: (_, _) => Container(
                              color: color.withValues(alpha: 0.1),
                              child: Icon(Icons.music_note, color: color),
                            ),
                            errorWidget: (_, _, _) => Container(
                              color: color.withValues(alpha: 0.1),
                              child: Icon(Icons.music_note, color: color),
                            ),
                          )
                        : Container(
                            color: color.withValues(alpha: 0.1),
                            child: Icon(Icons.music_note, color: color),
                          ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  song.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  song.artistNames,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
