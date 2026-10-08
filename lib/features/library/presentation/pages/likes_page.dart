import 'package:flutter/material.dart';
import '../../../../core/share/song_actions.dart';
import '../../../../core/theme/platform_accent.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../models/song.dart';
import '../../../../models/platform_type.dart';
import '../../../download/domain/entities/download_task.dart';
import '../../../download/presentation/providers/download_provider.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../providers/likes_provider.dart';

class LikesPage extends ConsumerWidget {
  const LikesPage({super.key});

  Color _platformColor(PlatformType platform) =>
      PlatformAccent.neutralColorOf(platform);

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
      // Three states, one widget — see `AsyncStateView`. The list is read on
      // every app open, so its loading state is the shimmer skeleton rather
      // than a spinner (no layout jump when the rows arrive).
      body: state.isLoading
          ? const AsyncStateView.loading(skeleton: true)
          : state.error != null
          ? AsyncStateView.error(
              title: '加载失败',
              message: state.error!,
              onRetry: () => ref.read(likesProvider.notifier).loadLikes(),
            )
          : state.songs.isEmpty
          ? const AsyncStateView.empty(
              title: '还没有喜欢的歌曲',
              message: '在播放器中点击爱心添加',
              icon: Icons.favorite_border,
            )
          : state.filteredSongs.isEmpty
          ? const AsyncStateView.empty(
              title: '该平台没有喜欢的歌曲',
              icon: Icons.filter_alt_off_outlined,
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
            // Long-press opens the shared song menu, so the gesture means the
            // same thing here as it does on the other song lists. `isLiked` is
            // true by definition (this page lists the liked songs); the download
            // flag is read once per long-press instead of watched, so a
            // downloading song does not rebuild the whole list.
            onLongPress: () => showSongActionsMenu(
              context,
              ref,
              song: song,
              isLiked: true,
              isDownloaded: _hasCompletedDownload(
                ref.read(downloadProvider),
                song,
              ),
              isLocal: false,
            ),
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
  final VoidCallback onLongPress;

  const _SongTile({
    super.key,
    required this.song,
    required this.index,
    required this.platformColor,
    required this.onTap,
    required this.onLike,
    required this.onLongPress,
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
      onLongPress: onLongPress,
    );
  }
}

/// Whether [song] has a finished download, at any quality.
///
/// Scans the queue state instead of `DownloadNotifier.isDownloaded`, which
/// needs an [AudioLevel] the row does not know: the menu only uses the flag to
/// stop offering 下载 for a song the user already has.
bool _hasCompletedDownload(DownloadState state, Song song) {
  return state.tasks.any(
    (task) =>
        task.song.id == song.id &&
        task.song.platform == song.platform &&
        task.status == DownloadStatus.completed,
  );
}
