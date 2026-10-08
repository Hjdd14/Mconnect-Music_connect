import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/async_state_view.dart';
import '../../../../models/song.dart';
import '../providers/player_provider.dart';

/// 播放队列页（`/queue`）。
///
/// 为什么需要这一页：`PlayerNotifier.addToQueue` 只往队列里塞，之前没有任何界面
/// 展示它（播放页只弹一句「已添加到播放队列」），所以用户既看不到也改不了正在
/// 排队的歌。队列编辑能力由 Wave 0-A 提供
/// （`player_provider.dart` 的 `moveInQueue` / `removeFromQueue` / `clearQueue` /
/// `playAtIndex`），**这一页只调用，不重新实现任何队列语义**。
///
/// **三态**：只有 `empty` 一种。队列是 [PlayerState] 的同步数据，没有取数过程，
/// 所以既没有 loading 也没有 error 态 —— 硬加一个不可达的
/// `AsyncStateView.loading` 只会是死代码（Wave 1 评审已确认）。
///
/// 入口（「打开队列页」的按钮）由 W1-A 在 `player_screen.dart` 里加
/// （`context.push('/queue')`）；本页只保证路由与内容就绪。
class QueuePage extends ConsumerWidget {
  const QueuePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerProvider);
    final notifier = ref.read(playerProvider.notifier);
    final queue = state.playlist;

    return Scaffold(
      appBar: AppBar(
        title: const Text('播放队列'),
        actions: [
          // 空队列没有可清空的东西：按钮不出现，而不是出现后必然失败。
          if (queue.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: '清空队列',
              onPressed: () => unawaited(_confirmClear(context, ref)),
            ),
        ],
      ),
      body: queue.isEmpty
          ? const AsyncStateView.empty(
              title: '队列是空的',
              message: '播放歌曲，或在歌曲菜单里选「加入播放队列」',
              icon: Icons.queue_music,
            )
          : Column(
              children: [
                _QueueSummary(
                  count: queue.length,
                  totalDuration: _totalDuration(queue),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    // 显式拖拽把手（和播放列表详情页一致）：整行默认的长按拖拽
                    // 会和「点击跳播」抢同一个手势，用户也看不出哪一行能拖。
                    buildDefaultDragHandles: false,
                    itemCount: queue.length,
                    // `onReorderItem`（不是已弃用的 `onReorder`）已经替调用方
                    // 修正过 `newIndex`，所以这里直接交给 `moveInQueue`，
                    // **不能再做经典的 -1 修正**。
                    onReorderItem: (oldIndex, newIndex) =>
                        notifier.moveInQueue(oldIndex, newIndex),
                    itemBuilder: (context, index) {
                      final song = queue[index];
                      return _QueueRow(
                        // 同一首歌可以入队两次，所以 key 必须带上下标。
                        key: ValueKey('queue-${song.dedupeKey}-$index'),
                        index: index,
                        song: song,
                        isCurrent: index == state.currentIndex,
                        onTap: () => unawaited(notifier.playAtIndex(index)),
                        onRemove: () =>
                            unawaited(notifier.removeFromQueue(song.dedupeKey)),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  /// 清空是破坏性且不可撤销的（会停止播放），所以必须二次确认。
  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空播放队列'),
        content: const Text('将停止播放并移除队列里的全部歌曲。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(playerProvider.notifier).clearQueue();
  }

  static Duration _totalDuration(List<Song> queue) {
    var total = Duration.zero;
    for (final song in queue) {
      total += song.duration;
    }
    return total;
  }
}

/// 「共 N 首 · 总时长 …」。
///
/// 单独一行而不是塞进 AppBar：队列长度会变（重排/删除/清空），标题栏里闪动的
/// 数字既难读也会让标题宽度跳。
class _QueueSummary extends StatelessWidget {
  const _QueueSummary({required this.count, required this.totalDuration});

  final int count;
  final Duration totalDuration;

  @override
  Widget build(BuildContext context) {
    // `onSurfaceVariant`：正文色，不用 `outline`（那是边框色）。
    final style = TextStyle(
      fontSize: 13,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Text('共 $count 首', style: style),
          const SizedBox(width: 12),
          Text('总时长 ${formatQueueDuration(totalDuration)}', style: style),
        ],
      ),
    );
  }
}

/// `9 分` / `1 小时 5 分`。不足 1 分钟按 `0 分` 显示（队列里不会有这么多超短曲
/// 目，为它加一套「秒」文案只会多一处没人看的措辞）。
String formatQueueDuration(Duration total) {
  final hours = total.inHours;
  final minutes = total.inMinutes.remainder(60);
  if (hours > 0) return '$hours 小时 $minutes 分';
  return '$minutes 分';
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    super.key,
    required this.index,
    required this.song,
    required this.isCurrent,
    required this.onTap,
    required this.onRemove,
  });

  final int index;
  final Song song;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      // 当前曲目：整行高亮 + 播放标记。标记只在当前行出现，所以「哪一首在播」
      // 不依赖颜色（色盲/高对比度主题下也读得出来）。
      selected: isCurrent,
      selectedTileColor: cs.primaryContainer.withValues(alpha: 0.4),
      leading: SizedBox(
        width: 32,
        child: Center(
          child: isCurrent
              ? Icon(Icons.graphic_eq, size: 20, color: cs.primary)
              : Text(
                  '${index + 1}',
                  style: TextStyle(fontSize: 13, color: cs.outline),
                ),
        ),
      ),
      title: Text(song.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        song.artistNames,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, color: cs.outline),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            // tooltip 带歌名：一行一个，测试与读屏都能精确定位到某一首。
            tooltip: '从队列移除 ${song.name}',
            onPressed: onRemove,
          ),
          ReorderableDragStartListener(
            index: index,
            child: Icon(
              Icons.drag_handle,
              size: 20,
              color: cs.outline,
              semanticLabel: '拖动排序',
            ),
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}
