import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../models/song.dart';
import '../../../../models/platform_type.dart';
import '../../../download/presentation/widgets/download_button.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../providers/rankings_provider.dart';

class RankingsPage extends ConsumerStatefulWidget {
  const RankingsPage({super.key});

  @override
  ConsumerState<RankingsPage> createState() => _RankingsPageState();
}

class _RankingsPageState extends ConsumerState<RankingsPage>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  int _lastTabCount = 0;

  @override
  void initState() {
    super.initState();
    final state = ref.read(rankingsProvider);
    if (state.songsByPlatform.isEmpty && !state.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(rankingsProvider.notifier).loadRankings();
      });
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  void _syncTabController(int length) {
    if (length <= 0) {
      _tabController?.dispose();
      _tabController = null;
      _lastTabCount = 0;
      return;
    }
    if (_lastTabCount != length) {
      final previousIndex = _tabController?.index ?? 0;
      _tabController?.dispose();
      _tabController = TabController(length: length, vsync: this);
      if (previousIndex < length) {
        _tabController!.index = previousIndex;
      }
      _lastTabCount = length;
    }
  }

  Color _platformColor(PlatformType platform) {
    switch (platform) {
      case PlatformType.local:
        return Theme.of(context).colorScheme.primary;
      case PlatformType.netease:
        return const Color(0xFFE60026);
      case PlatformType.qq:
        return const Color(0xFF31C27C);
      case PlatformType.kugou:
        return const Color(0xFF2CA2F9);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rankingsProvider);
    final platforms = state.songsByPlatform.keys.toList();
    _syncTabController(platforms.length);

    return Scaffold(
      appBar: AppBar(
        title: const Text('排行榜'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(rankingsProvider.notifier).loadRankings(),
          ),
        ],
        bottom: _tabController != null
            ? TabBar(
                controller: _tabController!,
                tabs: platforms.map((p) => Tab(text: p.displayName)).toList(),
              )
            : null,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : platforms.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.leaderboard,
                    size: 64,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    state.error ?? '暂无排行榜数据',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () =>
                        ref.read(rankingsProvider.notifier).loadRankings(),
                    child: const Text('重试'),
                  ),
                ],
              ),
            )
          : TabBarView(
              controller: _tabController!,
              children: platforms.map((platform) {
                final songs = state.songsForPlatform(platform);
                return _SongList(
                  songs: songs,
                  platformColor: _platformColor(platform),
                );
              }).toList(),
            ),
    );
  }
}

class _SongList extends ConsumerWidget {
  final List<Song> songs;
  final Color platformColor;

  const _SongList({required this.songs, required this.platformColor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppScrollbar(
      builder: (controller) => ListView.builder(
        controller: controller,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: songs.length,
        itemBuilder: (context, index) {
          final song = songs[index];
          return ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: platformColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: platformColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            title: Text(
              song.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15),
            ),
            subtitle: Text(
              song.artistNames,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 13,
              ),
            ),
            trailing: DownloadButton(song: song, size: 22),
            onTap: () {
              ref
                  .read(playerProvider.notifier)
                  .playPlaylist(songs, startIndex: index);
            },
          );
        },
      ),
    );
  }
}
