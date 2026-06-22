import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../utils/file_opener.dart';
import '../providers/download_provider.dart';
import '../../domain/entities/download_task.dart';

class DownloadPage extends ConsumerWidget {
  const DownloadPage({super.key});

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _showDownloadDirectorySheet(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final notifier = ref.read(downloadProvider.notifier);
    final currentPath = await notifier.currentDownloadRootPath();
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        var displayedPath = currentPath;
        var isSaving = false;

        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Future<void> refreshPath() async {
              final path = await notifier.currentDownloadRootPath();
              if (!sheetContext.mounted) return;
              setSheetState(() {
                displayedPath = path;
              });
            }

            Future<void> chooseDirectory() async {
              final path = await FilePicker.getDirectoryPath(
                dialogTitle: '选择下载目录',
              );
              if (path == null || path.trim().isEmpty) return;
              if (!sheetContext.mounted) return;
              setSheetState(() {
                isSaving = true;
              });

              final saved = await notifier.setCustomDownloadRoot(path);
              await refreshPath();
              if (!sheetContext.mounted) return;
              setSheetState(() {
                isSaving = false;
              });

              if (!context.mounted) return;
              if (saved) {
                showSuccessSnackBar(context, '下载目录已更新');
              } else {
                showErrorSnackBar(context, '该目录不可用，请选择其他文件夹');
              }
            }

            Future<void> resetDirectory() async {
              setSheetState(() {
                isSaving = true;
              });
              await notifier.resetDownloadRoot();
              await refreshPath();
              if (!sheetContext.mounted) return;
              setSheetState(() {
                isSaving = false;
              });
              if (context.mounted) {
                showSuccessSnackBar(context, '已恢复默认下载目录');
              }
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '下载目录',
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.folder_open),
                      title: const Text('当前目录'),
                      subtitle: Text(
                        displayedPath,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      icon: isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.drive_folder_upload),
                      label: const Text('选择目录'),
                      onPressed: isSaving ? null : chooseDirectory,
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.restore),
                      label: const Text('恢复默认目录'),
                      onPressed: isSaving ? null : resetDirectory,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeCount = ref.watch(
      downloadProvider.select((s) => s.activeCount),
    );
    final completedCount = ref.watch(
      downloadProvider.select((s) => s.completedTasks.length),
    );
    final failedCount = ref.watch(
      downloadProvider.select((s) => s.failedTasks.length),
    );
    final activeTasks = ref.watch(
      downloadProvider.select((s) => s.activeTasks),
    );
    final completedTasks = ref.watch(
      downloadProvider.select((s) => s.completedTasks),
    );
    final failedTasks = ref.watch(
      downloadProvider.select((s) => s.failedTasks),
    );
    final notifier = ref.read(downloadProvider.notifier);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('下载管理'),
          bottom: TabBar(
            tabs: [
              Tab(text: '下载中 ($activeCount)'),
              Tab(text: '已完成 ($completedCount)'),
              Tab(text: '失败 ($failedCount)'),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.folder_copy_outlined),
              tooltip: '下载目录',
              onPressed: () {
                unawaited(_showDownloadDirectorySheet(context, ref));
              },
            ),
            if (activeTasks.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.pause_circle_outline),
                tooltip: '暂停全部',
                onPressed: () {
                  for (final task in activeTasks) {
                    notifier.pauseDownload(task.id);
                  }
                },
              ),
          ],
        ),
        body: TabBarView(
          children: [
            // Active downloads
            _DownloadList(
              tasks: activeTasks,
              formatBytes: _formatBytes,
              onPause: notifier.pauseDownload,
              onCancel: notifier.cancelDownload,
              onResume: notifier.resumeDownload,
            ),
            // Completed downloads
            _DownloadList(
              tasks: completedTasks,
              formatBytes: _formatBytes,
              onRemove: notifier.removeTask,
            ),
            // Failed downloads
            _DownloadList(
              tasks: failedTasks,
              formatBytes: _formatBytes,
              onRetry: (task) => notifier.resumeDownload(task.id),
              onRemove: notifier.removeTask,
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadList extends StatelessWidget {
  final List<DownloadTask> tasks;
  final String Function(int) formatBytes;
  final void Function(String)? onPause;
  final void Function(String)? onResume;
  final void Function(String)? onCancel;
  final Future<bool> Function(String)? onRemove;
  final void Function(DownloadTask)? onRetry;

  const _DownloadList({
    required this.tasks,
    required this.formatBytes,
    this.onPause,
    this.onResume,
    this.onCancel,
    this.onRemove,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.download_done,
              size: 48,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text(
              '暂无内容',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      );
    }

    return AppScrollbar(
      builder: (controller) => ListView.builder(
        controller: controller,
        itemCount: tasks.length,
        itemBuilder: (context, index) {
          final task = tasks[index];
          return _DownloadTile(
            task: task,
            formatBytes: formatBytes,
            onPause: onPause,
            onResume: onResume,
            onCancel: onCancel,
            onRemove: onRemove,
            onRetry: onRetry,
          );
        },
      ),
    );
  }
}

class _DownloadTile extends StatelessWidget {
  final DownloadTask task;
  final String Function(int) formatBytes;
  final void Function(String)? onPause;
  final void Function(String)? onResume;
  final void Function(String)? onCancel;
  final Future<bool> Function(String)? onRemove;
  final void Function(DownloadTask)? onRetry;

  const _DownloadTile({
    required this.task,
    required this.formatBytes,
    this.onPause,
    this.onResume,
    this.onCancel,
    this.onRemove,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _buildLeading(context),
      title: Text(
        task.song.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${task.song.artistNames} · ${task.qualityLabel}',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.outline,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (task.status == DownloadStatus.downloading) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: task.progress,
                    minHeight: 2,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(task.progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
            Text(
              '${formatBytes(task.downloadedBytes)} / ${formatBytes(task.totalBytes ?? 0)}',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
          if (task.status == DownloadStatus.failed && task.error != null)
            Text(
              task.error!,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.error,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      trailing: _buildActions(context),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildLeading(BuildContext context) {
    switch (task.status) {
      case DownloadStatus.downloading:
        return SizedBox(
          width: 36,
          height: 36,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: task.progress,
                strokeWidth: 3,
                color: Theme.of(context).colorScheme.primary,
              ),
              Text(
                '${(task.progress * 100).toInt()}',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        );
      case DownloadStatus.completed:
        return Icon(
          Icons.check_circle,
          color: Theme.of(context).colorScheme.tertiary,
          size: 32,
        );
      case DownloadStatus.failed:
        return Icon(
          Icons.error_outline,
          color: Theme.of(context).colorScheme.error,
          size: 32,
        );
      case DownloadStatus.paused:
        return Icon(
          Icons.pause_circle_outline,
          color: Theme.of(context).colorScheme.secondary,
          size: 32,
        );
      case DownloadStatus.waiting:
        return Icon(
          Icons.hourglass_empty,
          color: Theme.of(context).colorScheme.outline,
          size: 32,
        );
    }
  }

  Widget? _buildActions(BuildContext context) {
    switch (task.status) {
      case DownloadStatus.downloading:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onPause != null)
              IconButton(
                icon: const Icon(Icons.pause, size: 20),
                onPressed: () => onPause!(task.id),
              ),
            if (onCancel != null)
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => onCancel!(task.id),
              ),
          ],
        );
      case DownloadStatus.paused:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onResume != null)
              IconButton(
                icon: const Icon(Icons.play_arrow, size: 20),
                onPressed: () => onResume!(task.id),
              ),
            if (onCancel != null)
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => onCancel!(task.id),
              ),
          ],
        );
      case DownloadStatus.failed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onRetry != null)
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () => onRetry!(task),
              ),
            if (onRemove != null)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () async {
                  final removed = await onRemove!(task.id);
                  if (!context.mounted) return;
                  if (!removed) {
                    showErrorSnackBar(context, '删除下载记录失败');
                  }
                },
              ),
          ],
        );
      case DownloadStatus.completed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (task.filePath != null)
              IconButton(
                icon: const Icon(Icons.folder_open, size: 20),
                tooltip: '打开文件夹',
                onPressed: () async {
                  final filePath = task.filePath;
                  if (filePath == null) return;
                  try {
                    await FileOpener.openFolder(p.dirname(filePath));
                  } catch (e) {
                    if (!context.mounted) return;
                    showErrorSnackBar(context, e.toString());
                  }
                },
              ),
            if (onRemove != null)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () async {
                  final confirmed = await _confirmDeleteDownloadedFile(
                    context,
                    task,
                  );
                  if (!context.mounted || !confirmed) return;
                  final removed = await onRemove!(task.id);
                  if (!context.mounted) return;
                  if (!removed) {
                    showErrorSnackBar(context, '删除下载文件失败');
                  }
                },
              ),
          ],
        );
      case DownloadStatus.waiting:
        return null;
    }
  }

  Future<bool> _confirmDeleteDownloadedFile(
    BuildContext context,
    DownloadTask task,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除下载文件'),
        content: Text('确定要删除“${task.song.name}”吗？这会删除本地文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return result == true;
  }
}
