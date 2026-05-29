import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../models/song.dart';
import '../../../../models/platform_type.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../providers/likes_provider.dart';

class LikesPage extends ConsumerWidget {
  const LikesPage({super.key});

  Color _platformColor(PlatformType platform) {
    switch (platform) {
      case PlatformType.local:
        return Colors.grey;
      case PlatformType.netease:
        return const Color(0xFFE60026);
      case PlatformType.qq:
        return const Color(0xFF31C27C);
      case PlatformType.kugou:
        return const Color(0xFF2CA2F9);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(likesProvider);
    final notifier = ref.read(likesProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text('我喜欢 (${state.filteredSongs.length})'),
        actions: [
          if (state.songs.isNotEmpty)
            PopupMenuButton<PlatformType?>(
              icon: const Icon(Icons.filter_list),
              tooltip: '平台筛选',
              onSelected: (platform) => notifier.setFilter(platform),
              itemBuilder: (context) => [
                const PopupMenuItem(value: null, child: Text('全部平台')),
                ...PlatformType.values.map(
                  (p) => PopupMenuItem(value: p, child: Text(p.displayName)),
                ),
              ],
            ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    state.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () =>
                        ref.read(likesProvider.notifier).loadLikes(),
                    child: const Text('重试'),
                  ),
                ],
              ),
            )
          : state.songs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.favorite_border,
                    size: 64,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '还没有喜欢的歌曲',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '在播放器中点击爱心添加',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
          : state.filteredSongs.isEmpty
          ? Center(
              child: Text(
                '该平台没有喜欢的歌曲',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.outline,
                  fontSize: 16,
                ),
              ),
            )
          : _buildSongList(context, ref, state, notifier),
    );
  }

  Widget _buildSongList(
    BuildContext context,
    WidgetRef ref,
    LikesState state,
    LikesNotifier notifier,
  ) {
    final songs = state.filteredSongs;
    return AppScrollbar(
      builder: (controller) => ListView.builder(
        controller: controller,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: songs.length,
        itemBuilder: (context, index) {
          final song = songs[index];
          return _SongTile(
            key: ValueKey('${song.platform.name}_${song.id}'),
            song: song,
            index: index + 1,
            platformColor: _platformColor(song.platform),
            onTap: () {
              ref
                  .read(playerProvider.notifier)
                  .playPlaylist(songs, startIndex: index);
            },
            onLike: () async {
              await notifier.toggleLike(song);
            },
          );
        },
      ),
    );
  }
}

class _SongTile extends StatelessWidget {
  final Song song;
  final int index;
  final Color platformColor;
  final VoidCallback onTap;
  final VoidCallback onLike;

  const _SongTile({
    super.key,
    required this.song,
    required this.index,
    required this.platformColor,
    required this.onTap,
    required this.onLike,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: SizedBox(
        width: 32,
        child: Center(
          child: Text(
            '$index',
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
              fontSize: 13,
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
      subtitle: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: platformColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              song.platform.displayName.substring(
                0,
                song.platform.displayName.length.clamp(0, 2),
              ),
              style: TextStyle(fontSize: 10, color: platformColor),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              song.artistNames,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
      trailing: IconButton(
        icon: Icon(
          Icons.favorite,
          color: Theme.of(context).colorScheme.error,
          size: 20,
        ),
        onPressed: onLike,
      ),
      onTap: onTap,
    );
  }
}
