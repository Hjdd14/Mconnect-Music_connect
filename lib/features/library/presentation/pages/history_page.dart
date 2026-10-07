import 'package:flutter/material.dart';
import '../../../../core/share/song_actions.dart';
import '../../../../core/theme/platform_accent.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../models/song.dart';
import '../../../../models/platform_type.dart';
import '../../../download/domain/entities/download_task.dart';
import '../../../download/presentation/providers/download_provider.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../providers/history_provider.dart';
import '../providers/likes_provider.dart';

class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  Color _platformColor(PlatformType platform) =>
      PlatformAccent.neutralColorOf(platform);

  String _formatDuration(Duration d) {
    if (d.inHours > 0) return '${d.inHours}小时前';
    if (d.inMinutes > 0) return '${d.inMinutes}分钟前';
    return '刚刚';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(historyProvider);
    final notifier = ref.read(historyProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text('听歌历史 (${state.entries.length})'),
        actions: [
          if (state.entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: '清空历史',
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('清空听歌历史'),
                    content: const Text('确定要清空所有听歌历史吗？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('确定'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await notifier.clearHistory();
                }
              },
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
                        ref.read(historyProvider.notifier).loadHistory(),
                    child: const Text('重试'),
                  ),
                ],
              ),
            )
          : state.entries.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history,
                    size: 64,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '还没有听歌记录',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            )
          : _buildList(context, ref, state),
    );
  }

  Widget _buildList(BuildContext context, WidgetRef ref, HistoryState state) {
    final now = DateTime.now();
    final songs = state.entries.map((entry) => entry.song).toList();
    String? lastDateLabel;

    return AppScrollbar(
      builder: (controller) => ListView.builder(
        controller: controller,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: state.entries.length,
        itemBuilder: (context, index) {
          final entry = state.entries[index];
          final dateLabel = _getDateLabel(entry.listenedAt, now);

          Widget? dateHeader;
          if (dateLabel != lastDateLabel) {
            lastDateLabel = dateLabel;
            dateHeader = Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                dateLabel,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.outline,
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ?dateHeader,
              _HistoryTile(
                song: entry.song,
                time: entry.listenedAt,
                platformColor: _platformColor(entry.song.platform),
                timeAgo: _formatDuration(now.difference(entry.listenedAt)),
                onTap: () {
                  ref
                      .read(playerProvider.notifier)
                      .playPlaylist(songs, startIndex: index);
                },
                // Same long-press menu as every other song list. The like state
                // is read at press time (not watched): history has up to 200
                // rows and nothing else on this page depends on it.
                onLongPress: () => showSongActionsMenu(
                  context,
                  ref,
                  song: entry.song,
                  isLiked: _isLiked(ref.read(likesProvider), entry.song),
                  isDownloaded: _hasCompletedDownload(
                    ref.read(downloadProvider),
                    entry.song,
                  ),
                  isLocal: false,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _getDateLabel(DateTime date, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(date.year, date.month, date.day);
    final diff = today.difference(dateOnly).inDays;

    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    if (diff < 7) return '$diff天前';
    return DateFormat('MM月dd日').format(date);
  }
}

class _HistoryTile extends StatelessWidget {
  final Song song;
  final DateTime time;
  final Color platformColor;
  final String timeAgo;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _HistoryTile({
    required this.song,
    required this.time,
    required this.platformColor,
    required this.timeAgo,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
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
            song.platform.displayName.substring(0, 1),
            style: TextStyle(
              color: platformColor,
              fontWeight: FontWeight.bold,
              fontSize: 16,
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
        song.artistNames.isEmpty ? timeAgo : '${song.artistNames} · $timeAgo',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Theme.of(context).colorScheme.outline,
          fontSize: 13,
        ),
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

/// Whether [song] is currently in 我喜欢 — the menu's 喜欢/取消喜欢 label depends
/// on it.
bool _isLiked(LikesState state, Song song) {
  return state.songs.any(
    (liked) => liked.id == song.id && liked.platform == song.platform,
  );
}

/// Whether [song] has a finished download, at any quality (see the same helper
/// on the likes page: the menu only needs "don't offer 下载 again").
bool _hasCompletedDownload(DownloadState state, Song song) {
  return state.tasks.any(
    (task) =>
        task.song.id == song.id &&
        task.song.platform == song.platform &&
        task.status == DownloadStatus.completed,
  );
}
