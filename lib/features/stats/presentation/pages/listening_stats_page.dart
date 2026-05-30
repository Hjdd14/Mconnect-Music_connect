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

    return Scaffold(
      appBar: AppBar(
        title: const Text('听歌统计'),
        actions: [
          IconButton(
            tooltip: '清空统计',
            icon: const Icon(Icons.delete_outline),
            onPressed: state.totalPlayCount == 0 && state.topSongs.isEmpty
                ? null
                : () => notifier.clear(),
          ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : AppScrollbar(
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
                  else
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
              ),
            ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) return '$hours小时$minutes分';
    return '${duration.inMinutes}分';
  }
}

class _SummaryRow extends StatelessWidget {
  final ListeningStatsState state;

  const _SummaryRow({required this.state});

  @override
  Widget build(BuildContext context) {
    return Row(
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
    );
  }

  String _formatTotal(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours}小时${duration.inMinutes.remainder(60)}分';
    }
    return '${duration.inMinutes}分';
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
