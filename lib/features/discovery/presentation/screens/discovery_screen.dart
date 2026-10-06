import 'package:flutter/material.dart';
import '../../../../core/theme/platform_accent.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/widgets/app_scrollbar.dart';
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '发现',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                  child: Icon(
                    Icons.wb_sunny,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                title: const Text('每日推荐'),
                subtitle: const Text('根据你的口味生成'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/recommendations'),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.tertiaryContainer,
                  child: Icon(
                    Icons.trending_up,
                    color: Theme.of(context).colorScheme.onTertiaryContainer,
                  ),
                ),
                title: const Text('榜单中心'),
                subtitle: const Text('各平台榜单 · QQ 热歌榜 300 首'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/toplists'),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
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
                const SizedBox(width: 8),
                Expanded(
                  child: _DiscoveryEntry(
                    icon: Icons.person_search_outlined,
                    label: '艺人 / 专辑',
                    // Artists and albums are addressed by platform id, which only
                    // a search can produce, so this entry hands over to the
                    // search tab instead of inventing an id-less route.
                    onTap: () => context.go('/?tab=0'),
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
            Expanded(
              child: recState.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : recState.hasData
                  ? _RecommendationGrid(
                      recState: recState,
                      platformColor: _platformColor,
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.music_note,
                            size: 48,
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            recState.error ?? '登录后查看更多',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.outline,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact entry tile for the 榜单中心 / 新歌速递 / 艺人·专辑 row.
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
