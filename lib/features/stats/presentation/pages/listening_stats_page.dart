import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_scrollbar.dart';
import '../providers/listening_stats_provider.dart';

class ListeningStatsPage extends ConsumerWidget {
  const ListeningStatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(listeningStatsProvider);
    final notifier = ref.read(listeningStatsProvider.notifier);
    final report = ref.watch(listeningStatsReportProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('听歌统计'),
        actions: [
          IconButton(
            tooltip: '清空统计',
            icon: const Icon(Icons.delete_outline),
            onPressed: state.hasData
                ? () => _confirmClear(context, notifier)
                : null,
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.error != null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    state.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: notifier.load,
                    child: const Text('重试'),
                  ),
                ],
              ),
            );
          }
          final dimensions = report.valueOrNull;
          return AppScrollbar(
            builder: (controller) => ListView(
              controller: controller,
              padding: const EdgeInsets.all(16),
              children: [
                _SummaryRow(state: state),
                const SizedBox(height: 16),
                Text('常听歌曲', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (state.topSongs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: Text('还没有统计记录')),
                  )
                else ...[
                  if (state.allSongs.length > state.topSongs.length)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '仅展示前 ${state.topSongs.length} 首（共 ${state.allSongs.length} 首，'
                        '其余明细仍完整保留）',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  for (final entry in state.topSongs.take(50))
                    ListTile(
                      leading: CircleAvatar(
                        child: Text(entry.playCount.toString()),
                      ),
                      title: Text(entry.songName),
                      subtitle: Text(
                        '${entry.artistNames} · ${entry.platform.displayName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(_formatDuration(entry.listenDuration)),
                    ),
                ],
                if (dimensions != null && !dimensions.isEmpty) ...[
                  const SizedBox(height: 16),
                  _DimensionSection(
                    title: '常听歌手',
                    rows: dimensions.artists.take(10).toList(),
                  ),
                  _DimensionSection(
                    title: '平台分布',
                    rows: dimensions.platforms,
                  ),
                  _HourSection(hours: dimensions.hours),
                  if (dimensions.days.isNotEmpty) ...[
                    Text(
                      '最近活跃日',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    for (final day in dimensions.days.take(7))
                      ListTile(
                        dense: true,
                        title: Text(day.day),
                        subtitle: Text('${day.playCount} 次播放'),
                        trailing: Text(_formatDuration(day.listenDuration)),
                      ),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmClear(
    BuildContext context,
    ListeningStatsNotifier notifier,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空听歌统计'),
        content: const Text('将删除全部播放明细与每日汇总，且无法撤销。'),
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
      await notifier.clear();
    }
  }
}

class _DimensionSection extends StatelessWidget {
  final String title;
  final List<ListeningStatsDimension> rows;

  const _DimensionSection({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final row in rows)
          ListTile(
            dense: true,
            title: Text(row.label),
            subtitle: Text('${row.playCount} 次播放'),
            trailing: Text(_formatDuration(row.listenDuration)),
          ),
      ],
    );
  }
}

class _HourSection extends StatelessWidget {
  final List<ListeningStatsHourBucket> hours;

  const _HourSection({required this.hours});

  @override
  Widget build(BuildContext context) {
    final active = hours.where((hour) => hour.playCount > 0).toList()
      ..sort((a, b) => b.playCount.compareTo(a.playCount));
    if (active.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('常听时段', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final hour in active.take(5))
          ListTile(
            dense: true,
            title: Text('${hour.hour.toString().padLeft(2, '0')}:00 - '
                '${(hour.hour + 1).toString().padLeft(2, '0')}:00'),
            subtitle: Text('${hour.playCount} 次播放'),
            trailing: Text(_formatDuration(hour.listenDuration)),
          ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final ListeningStatsState state;

  const _SummaryRow({required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _SummaryTile(
                label: '播放次数',
                value: '${state.totalPlayCount}',
                icon: Icons.play_circle_outline,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryTile(
                label: '听歌时长',
                value: _formatTotal(state.totalListenDuration),
                icon: Icons.schedule,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _SummaryTile(
                label: '收录歌曲',
                value: '${state.totalSongCount}',
                icon: Icons.library_music_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryTile(
                label: '活跃天数',
                value: '${state.activeDayCount}',
                icon: Icons.calendar_today_outlined,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SummaryTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(value, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatTotal(Duration duration) {
  if (duration.inHours > 0) {
    return '${duration.inHours}小时${duration.inMinutes.remainder(60)}分';
  }
  return '${duration.inMinutes}分';
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours > 0) return '$hours小时$minutes分';
  return '${duration.inMinutes}分';
}
