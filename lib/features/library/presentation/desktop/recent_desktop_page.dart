import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/desktop/desktop_empty_state.dart';
import '../../../../core/desktop/desktop_page_scaffold.dart';
import '../../../../core/desktop/desktop_song_table.dart';
import '../../../../core/desktop/desktop_tokens.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../providers/history_provider.dart';

/// 最近播放桌面页。
///
/// Same data as the phone history page ([historyProvider]), a desktop
/// presentation: the shared song row, day headers between the days, and the two
/// row actions a desktop client is expected to have (play next, add to queue).
class RecentDesktopPage extends ConsumerWidget {
  const RecentDesktopPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(historyProvider);
    final notifier = ref.read(historyProvider.notifier);
    final count = state.entries.length;

    return DesktopPageScaffold(
      title: '最近播放',
      subtitle: count == 0 ? '按天分组的播放历史' : '共 $count 条 · 按天分组',
      actions: [
        IconButton(
          tooltip: '刷新记录',
          onPressed: () => unawaited(notifier.loadHistory()),
          icon: const Icon(Icons.refresh, size: 20),
        ),
        if (count > 0)
          OutlinedButton.icon(
            onPressed: () => _confirmClear(context, notifier),
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            label: const Text('清空历史'),
          ),
      ],
      child: _buildBody(context, ref, state),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, HistoryState state) {
    if (state.isLoading && state.entries.isEmpty) {
      return const DesktopInlineLoading(label: '正在读取播放历史');
    }
    if (state.error != null && state.entries.isEmpty) {
      return DesktopInlineError(
        message: state.error!,
        onRetry: () =>
            unawaited(ref.read(historyProvider.notifier).loadHistory()),
      );
    }
    if (state.entries.isEmpty) {
      return const DesktopEmptyState(
        icon: Icons.history,
        title: '还没有播放记录',
        message: '播放过的歌曲会按天出现在这里，方便回听',
      );
    }

    // The list is pre-flattened into day headers plus rows instead of deciding
    // "is this a new day?" inside the row builder: a builder that derives that
    // from its own mutable state cannot survive a rebuild.
    final rows = _groupHistoryByDay(state.entries, DateTime.now());

    return LayoutBuilder(
      builder: (context, constraints) {
        final showAlbum =
            constraints.maxWidth >= DesktopSongTableMetrics.albumBreakpoint;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopSongTableHeader(showAlbum: showAlbum, actionsLabel: '操作'),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  vertical: DesktopSpacing.xs,
                ),
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  return switch (row) {
                    _DayHeaderRow(:final label, :final count) => _DayHeader(
                      label: label,
                      count: count,
                    ),
                    _EntryRow(:final entry, :final position) => DesktopSongRow(
                      key: ValueKey(
                        'history-${entry.song.platform.name}-'
                        '${entry.song.id}-$position',
                      ),
                      song: entry.song,
                      index: position,
                      showAlbum: showAlbum,
                      // The 专辑 column carries the play time followed by the
                      // album: with day headers above, this is the timeline that
                      // makes the page readable at a glance.
                      albumLabel: _albumWithTime(entry),
                      onTap: () => unawaited(
                        ref.read(playerProvider.notifier).playPlaylist([
                          for (final item in state.entries) item.song,
                        ], startIndex: position),
                      ),
                      trailing: [
                        IconButton(
                          tooltip: '下一首播放',
                          onPressed: () => ref
                              .read(playerProvider.notifier)
                              .playNext(entry.song),
                          icon: const Icon(Icons.skip_next, size: 17),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 32,
                            height: 32,
                          ),
                        ),
                        IconButton(
                          tooltip: '加入播放队列',
                          onPressed: () => ref
                              .read(playerProvider.notifier)
                              .addToQueue(entry.song),
                          icon: const Icon(Icons.playlist_add, size: 17),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 32,
                            height: 32,
                          ),
                        ),
                      ],
                    ),
                  };
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmClear(
    BuildContext context,
    HistoryNotifier notifier,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空最近播放'),
        content: const Text('将删除全部播放历史记录，且无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await notifier.clearHistory();
    }
  }

  String _albumWithTime(HistoryEntry entry) {
    final album = entry.song.album?.name;
    final time = _clockLabel(entry.listenedAt);
    if (album == null || album.trim().isEmpty) return time;
    return '$time · $album';
  }
}

/// One row of the flattened list: either a day header or a history entry.
sealed class _RecentRow {
  const _RecentRow();
}

class _DayHeaderRow extends _RecentRow {
  const _DayHeaderRow(this.label, this.count);

  final String label;
  final int count;
}

class _EntryRow extends _RecentRow {
  const _EntryRow({required this.entry, required this.position});

  final HistoryEntry entry;

  /// Index into the full (unflattened) history list, so playback continues in
  /// the same order the page shows.
  final int position;
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesktopSpacing.md,
        DesktopSpacing.lg,
        DesktopSpacing.md,
        DesktopSpacing.xs,
      ),
      child: Row(
        children: [
          Text(
            label,
            style: DesktopText.bodyStrong.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(width: DesktopSpacing.sm),
          Text(
            '$count 首',
            style: DesktopText.caption.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Flattens the history into day headers plus entry rows.
///
/// The buckets come from [_dayLabelFor], which is also what the header displays,
/// so a header can never disagree with the rows below it.
List<_RecentRow> _groupHistoryByDay(List<HistoryEntry> entries, DateTime now) {
  final rows = <_RecentRow>[];
  var index = 0;
  while (index < entries.length) {
    final label = _dayLabelFor(entries[index].listenedAt, now);
    var end = index;
    while (end < entries.length &&
        _dayLabelFor(entries[end].listenedAt, now) == label) {
      end++;
    }
    rows.add(_DayHeaderRow(label, end - index));
    for (var position = index; position < end; position++) {
      rows.add(_EntryRow(entry: entries[position], position: position));
    }
    index = end;
  }
  return rows;
}

/// Day bucket label: 今天 / 昨天 / N 天前 (within a week) / M月d日.
String _dayLabelFor(DateTime date, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final thatDay = DateTime(date.year, date.month, date.day);
  final diff = today.difference(thatDay).inDays;
  if (diff == 0) return '今天';
  if (diff == 1) return '昨天';
  if (diff > 1 && diff < 7) return '$diff 天前';
  return '${date.month}月${date.day}日';
}

/// HH:mm in local time.
String _clockLabel(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
