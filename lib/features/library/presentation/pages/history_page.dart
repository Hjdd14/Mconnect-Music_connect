import 'package:flutter/material.dart';
import '../../../../core/share/song_actions.dart';
import '../../../../core/theme/platform_accent.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/l10n.dart';
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

  // 这两个 helper 没有自己的 context，所以把 l10n 实例当参数传进来
  // （比在方法里再取一次 context 更明确，也便于将来单测）。
  String _formatDuration(AppLocalizations l, Duration d) {
    if (d.inHours > 0) return l.commonHoursAgo(d.inHours);
    if (d.inMinutes > 0) return l.commonMinutesAgo(d.inMinutes);
    return l.commonNow;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(historyProvider);
    final notifier = ref.read(historyProvider.notifier);
    final l = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.libraryHistoryWithCount(state.entries.length)),
        actions: [
          if (state.entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: l.libraryHistoryClear,
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(l.libraryHistoryClearConfirm),
                    content: Text(l.libraryHistoryClearConfirmBody),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(l.actionCancel),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(l.commonConfirm),
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
      // Same three-state widget as every other list page. History is opened
      // frequently and its rows are a fixed height, so loading shows the shared
      // shimmer skeleton instead of a spinner.
      body: state.isLoading
          ? const AsyncStateView.loading(skeleton: true)
          : state.error != null
          ? AsyncStateView.error(
              title: l.commonLoadFailed,
              message: state.error!,
              onRetry: () => ref.read(historyProvider.notifier).loadHistory(),
            )
          : state.entries.isEmpty
          ? AsyncStateView.empty(
              title: l.libraryHistoryEmpty,
              icon: Icons.history,
            )
          : _buildList(context, ref, state),
    );
  }

  Widget _buildList(BuildContext context, WidgetRef ref, HistoryState state) {
    final now = DateTime.now();
    final l = context.l10n;
    final songs = state.entries.map((entry) => entry.song).toList();
    String? lastDateLabel;

    return AppScrollbar(
      builder: (controller) => ListView.builder(
        controller: controller,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: state.entries.length,
        itemBuilder: (context, index) {
          final entry = state.entries[index];
          final dateLabel = _getDateLabel(l, entry.listenedAt, now);

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
                timeAgo: _formatDuration(
                  context.l10n,
                  now.difference(entry.listenedAt),
                ),
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

  String _getDateLabel(AppLocalizations l, DateTime date, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(date.year, date.month, date.day);
    final diff = today.difference(dateOnly).inDays;

    if (diff == 0) return l.commonToday;
    if (diff == 1) return l.commonYesterday;
    if (diff < 7) return l.commonDaysAgo(diff);
    // 日期模式本身也是文案（zh 是 `MM月dd日`、en 是 `MMM d`），所以它同样来自
    // ARB：否则 en 用户会看到 `10月06日`。
    return DateFormat(l.commonMonthDayPattern).format(date);
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
