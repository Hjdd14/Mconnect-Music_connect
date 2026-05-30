import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_scrollbar.dart';
import '../../../download/domain/entities/download_task.dart';
import '../../../download/presentation/providers/download_provider.dart';
import '../providers/offline_cache_provider.dart';

class OfflineCachePage extends ConsumerWidget {
  const OfflineCachePage({super.key});

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(offlineCacheSettingsProvider);
    final settingsNotifier = ref.read(offlineCacheSettingsProvider.notifier);
    final downloadState = ref.watch(downloadProvider);
    final downloadNotifier = ref.read(downloadProvider.notifier);
    final cacheBytes = downloadState.estimatedOfflineCacheBytes;

    return Scaffold(
      appBar: AppBar(title: const Text('离线缓存中心')),
      body: AppScrollbar(
        builder: (controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            _SummaryCard(
              cachedCount: downloadState.completedOfflineCacheTasks.length,
              waitingCount: downloadState.offlineCacheTasks
                  .where((task) => task.status == DownloadStatus.waiting)
                  .length,
              failedCount: downloadState.failedOfflineCacheTasks.length,
              usedText: _formatBytes(cacheBytes),
              limitText: '${settings.sizeLimitMb} MB',
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              secondary: const Icon(Icons.offline_pin_outlined),
              title: const Text('离线模式'),
              subtitle: const Text('开启后优先显示和播放已缓存内容'),
              value: settings.offlineMode,
              onChanged: settingsNotifier.setOfflineMode,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.wifi),
              title: const Text('仅 Wi-Fi 下载'),
              subtitle: const Text('移动网络下不自动执行缓存任务'),
              value: settings.wifiOnly,
              onChanged: settingsNotifier.setWifiOnly,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.replay_outlined),
              title: const Text('失败自动重试'),
              subtitle: const Text('缓存失败后允许队列稍后再次尝试'),
              value: settings.autoRetry,
              onChanged: settingsNotifier.setAutoRetry,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.cleaning_services_outlined),
              title: const Text('自动清理'),
              subtitle: const Text('超过大小上限时删除最早完成的离线缓存'),
              value: settings.autoCleanup,
              onChanged: settingsNotifier.setAutoCleanup,
            ),
            ListTile(
              leading: const Icon(Icons.sd_storage_outlined),
              title: const Text('缓存大小上限'),
              subtitle: Slider(
                value: settings.sizeLimitMb.toDouble(),
                min: 128,
                max: 8192,
                divisions: 63,
                label: '${settings.sizeLimitMb} MB',
                onChanged: (value) =>
                    settingsNotifier.setSizeLimitMb(value.round()),
              ),
              trailing: SizedBox(
                width: 72,
                child: Text(
                  '${settings.sizeLimitMb} MB',
                  textAlign: TextAlign.end,
                ),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('立即清理缓存'),
              subtitle: const Text('按当前大小上限清理最早完成的离线缓存任务'),
              onTap: settings.autoCleanup
                  ? () => downloadNotifier.cleanupOfflineCache(
                      sizeLimitMb: settings.sizeLimitMb,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final int cachedCount;
  final int waitingCount;
  final int failedCount;
  final String usedText;
  final String limitText;

  const _SummaryCard({
    required this.cachedCount,
    required this.waitingCount,
    required this.failedCount,
    required this.usedText,
    required this.limitText,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('缓存概览', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MetricChip(label: '已缓存', value: '$cachedCount'),
                _MetricChip(label: '等待中', value: '$waitingCount'),
                _MetricChip(label: '失败', value: '$failedCount'),
                _MetricChip(label: '空间', value: '$usedText / $limitText'),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '缓存中心复用下载队列，批量缓存整张歌单或专辑时会在这里统一管理。',
              style: TextStyle(color: cs.outline, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$label $value'),
    );
  }
}
