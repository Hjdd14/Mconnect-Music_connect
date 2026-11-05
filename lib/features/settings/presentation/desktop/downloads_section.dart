import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/snackbar_helper.dart';
import '../../../../utils/file_opener.dart';
import '../../../download/data/download_directory_service.dart';
import '../../../download/presentation/providers/download_provider.dart';
import '../../../offline_cache/presentation/providers/offline_cache_provider.dart';
import 'widgets/desktop_settings_card.dart';

/// 「下载与缓存」, inline instead of as a link to the download queue.
///
/// The section used to be a single card whose only action pushed /downloads --
/// a page about the *queue*, not about the settings this section is named
/// after. Everything that actually configures downloads (where files go, the
/// offline-cache switches) is here now, and the queue keeps its own entry on
/// the sidebar.
class DesktopDownloadsSection extends ConsumerStatefulWidget {
  const DesktopDownloadsSection({super.key});

  @override
  ConsumerState<DesktopDownloadsSection> createState() =>
      _DesktopDownloadsSectionState();
}

class _DesktopDownloadsSectionState
    extends ConsumerState<DesktopDownloadsSection> {
  final DownloadDirectoryService _service = DownloadDirectoryService();
  String? _path;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPath());
  }

  Future<void> _loadPath() async {
    try {
      final directory = await _service.currentRootDirectory(create: false);
      if (!mounted) return;
      setState(() => _path = directory.path);
    } on Object {
      if (!mounted) return;
      setState(() => _path = null);
    }
  }

  Future<void> _changeDirectory() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final picked = await FilePicker.getDirectoryPath(
        dialogTitle: '选择下载目录',
      );
      if (picked == null || picked.trim().isEmpty) return;
      final result = await ref
          .read(downloadProvider.notifier)
          .setCustomDownloadRoot(picked);
      await _loadPath();
      if (!mounted) return;
      if (result.isOk) {
        messenger?.showSnackBar(const SnackBar(content: Text('下载目录已更新')));
      } else {
        messenger?.showSnackBar(SnackBar(content: Text(result.message)));
      }
    } on Object catch (error) {
      if (!mounted) return;
      messenger?.showSnackBar(SnackBar(content: Text('无法使用该目录：$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetDirectory() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref.read(downloadProvider.notifier).resetDownloadRoot();
      await _loadPath();
      if (!mounted) return;
      messenger?.showSnackBar(const SnackBar(content: Text('已恢复默认下载目录')));
    } on Object catch (error) {
      if (!mounted) return;
      messenger?.showSnackBar(SnackBar(content: Text('恢复默认目录失败：$error')));
    }
  }

  Future<void> _openFolder() async {
    final path = _path;
    if (path == null) return;
    try {
      await FileOpener.openFolder(path);
    } on Object catch (error) {
      if (!mounted) return;
      showErrorSnackBar(context, '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(offlineCacheSettingsProvider);
    final notifier = ref.read(offlineCacheSettingsProvider.notifier);
    final cachedBytes = ref.watch(
      downloadProvider.select((s) => s.estimatedOfflineCacheBytes),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopSettingsCard(
          title: '下载目录',
          subtitle: '下载完成的文件按平台与音质分文件夹保存',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_outlined),
                title: const Text('当前目录'),
                subtitle: Text(
                  _path ?? '读取中…',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: OutlinedButton(
                  key: const ValueKey('desktop-downloads-change-dir'),
                  onPressed: _busy ? null : _changeDirectory,
                  child: const Text('更改…'),
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _busy ? null : _openFolder,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('打开文件夹'),
                  ),
                  TextButton.icon(
                    key: const ValueKey('desktop-downloads-reset-dir'),
                    onPressed: _busy ? null : _resetDirectory,
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text('恢复默认'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        DesktopSettingsCard(
          title: '离线缓存',
          subtitle: '缓存过的歌曲可以离线播放；当前占用 ${_formatBytes(cachedBytes)}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('离线模式'),
                subtitle: const Text('开启后不再自动开始缓存下载'),
                value: settings.offlineMode,
                onChanged: notifier.setOfflineMode,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('仅 Wi-Fi 下载'),
                subtitle: const Text('移动网络下不自动执行缓存任务'),
                value: settings.wifiOnly,
                onChanged: notifier.setWifiOnly,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('失败自动重试'),
                subtitle: const Text('缓存失败后允许队列稍后再次尝试'),
                value: settings.autoRetry,
                onChanged: notifier.setAutoRetry,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('自动清理'),
                subtitle: const Text('超过大小上限时删除最早完成的离线缓存'),
                value: settings.autoCleanup,
                onChanged: notifier.setAutoCleanup,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sd_storage_outlined),
                title: const Text('缓存大小上限'),
                subtitle: Slider(
                  value: settings.sizeLimitMb.toDouble(),
                  min: 128,
                  max: 8192,
                  divisions: 63,
                  label: '${settings.sizeLimitMb} MB',
                  onChanged: (value) => notifier.setSizeLimitMb(value.round()),
                ),
                trailing: SizedBox(
                  width: 84,
                  child: Text(
                    '${settings.sizeLimitMb} MB',
                    textAlign: TextAlign.end,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => context.push('/offline-cache'),
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('打开缓存中心'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '下载中的任务、失败重试与队列进度在侧栏「下载」里。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
