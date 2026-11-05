import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/desktop/desktop_empty_state.dart';
import '../../../../core/desktop/desktop_page_scaffold.dart';
import '../../../../core/desktop/desktop_song_table.dart';
import '../../../../core/desktop/desktop_tokens.dart';
import '../../../../core/widgets/app_scrollbar.dart';
import '../providers/player_provider.dart';

/// Desktop play queue (`/queue`).
///
/// Reordering/removal/clear are the existing [PlayerNotifier] queue API — this
/// page owns no queue semantics, only the desktop presentation of them.
class QueueDesktopPage extends ConsumerWidget {
  const QueueDesktopPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final queue = ref.watch(playerProvider.select((s) => s.playlist));
    final currentIndex = ref.watch(
      playerProvider.select((s) => s.currentIndex),
    );
    final notifier = ref.read(playerProvider.notifier);

    var total = Duration.zero;
    for (final song in queue) {
      total += song.duration;
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.surface, scheme.surfaceContainerLow],
          ),
        ),
        child: DesktopPageScaffold(
          title: '播放队列',
          subtitle: queue.isEmpty
              ? '队列是空的'
              : '共 ${queue.length} 首 · 总时长 ${formatDesktopTotalDuration(total)}',
          leading: IconButton(
            tooltip: '返回',
            onPressed: () => _close(context),
            icon: const Icon(Icons.arrow_back, size: 20),
          ),
          actions: [
            if (queue.isNotEmpty)
              TextButton.icon(
                onPressed: () => unawaited(_confirmClear(context, ref)),
                icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                label: const Text('清空队列'),
              ),
          ],
          child: queue.isEmpty
              ? DesktopEmptyState(
                  icon: Icons.queue_music,
                  title: '队列是空的',
                  message: '播放歌曲，或在歌曲菜单里选「加入播放队列」',
                  action: FilledButton(
                    onPressed: () => context.go('/'),
                    child: const Text('去发现音乐'),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final showAlbum =
                        constraints.maxWidth >=
                        DesktopSongTableMetrics.albumBreakpoint;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DesktopSongTableHeader(
                          showAlbum: showAlbum,
                          actionsLabel: '操作',
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: AppScrollbar(
                            builder: (controller) => ReorderableListView.builder(
                              scrollController: controller,
                              buildDefaultDragHandles: false,
                              padding: const EdgeInsets.only(
                                top: DesktopSpacing.xs,
                                bottom: DesktopSpacing.xxxl,
                              ),
                              itemCount: queue.length,
                              // `onReorderItem` already fixes the classic
                              // off-by-one for downward moves, so the index is
                              // passed straight to moveInQueue.
                              onReorderItem: (oldIndex, newIndex) =>
                                  notifier.moveInQueue(oldIndex, newIndex),
                              proxyDecorator: (child, index, animation) =>
                                  Material(
                                    elevation: 6,
                                    color: scheme.surfaceContainerHigh,
                                    borderRadius: DesktopRadii.mdAll,
                                    child: child,
                                  ),
                              itemBuilder: (context, index) {
                                final song = queue[index];
                                return DesktopSongRow(
                                  // A queue can hold the same song twice, so
                                  // the key must include the index.
                                  key: ValueKey(
                                    'desktop-queue-${song.dedupeKey}-$index',
                                  ),
                                  song: song,
                                  index: index,
                                  isCurrent: index == currentIndex,
                                  showAlbum: showAlbum,
                                  onTap: () =>
                                      unawaited(notifier.playAtIndex(index)),
                                  trailing: [
                                    IconButton(
                                      tooltip: '从队列移除 ${song.name}',
                                      onPressed: () => unawaited(
                                        notifier.removeFromQueue(
                                          song.dedupeKey,
                                        ),
                                      ),
                                      iconSize: 16,
                                      icon: const Icon(Icons.close),
                                    ),
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: DesktopSpacing.xs,
                                        ),
                                        child: Icon(
                                          Icons.drag_handle,
                                          size: 16,
                                          color: scheme.onSurfaceVariant,
                                          semanticLabel: '拖动排序',
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }

  void _close(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  /// Clearing stops playback and cannot be undone, so it is confirmed.
  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空播放队列'),
        content: const Text('将停止播放并移除队列里的全部歌曲。'),
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
    if (confirmed != true) return;
    await ref.read(playerProvider.notifier).clearQueue();
  }
}
