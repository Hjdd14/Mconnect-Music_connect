import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../core/desktop/desktop_empty_state.dart';
import '../../../../core/desktop/desktop_page_scaffold.dart';
import '../../../../core/desktop/desktop_song_table.dart';
import '../../../../core/desktop/desktop_tokens.dart';
import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../models/song.dart';
import '../../../../utils/file_opener.dart';
import '../../domain/entities/download_task.dart';
import '../providers/download_provider.dart';

/// Desktop download manager.
///
/// Sectioned (active / completed / failed) instead of the phone's three tabs:
/// a desktop window has the vertical room to show all three at once, and a
/// section header with a count reads better than a tab that hides a number.
///
/// Every action is a call into [DownloadNotifier]; nothing here re-implements
/// queue semantics.
class DownloadsDesktopPage extends ConsumerStatefulWidget {
  const DownloadsDesktopPage({super.key});

  @override
  ConsumerState<DownloadsDesktopPage> createState() =>
      _DownloadsDesktopPageState();
}

class _DownloadsDesktopPageState extends ConsumerState<DownloadsDesktopPage> {
  static const int _maxCompletedShown = 200;

  String? _notice;
  bool _noticeIsError = false;

  void _showNotice(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _notice = message;
      _noticeIsError = isError;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(downloadProvider);
    final notifier = ref.read(downloadProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    final downloading = state.tasks
        .where((task) => task.status == DownloadStatus.downloading)
        .toList();
    final waiting = state.tasks
        .where((task) => task.status == DownloadStatus.waiting)
        .toList();
    final paused = state.tasks
        .where((task) => task.status == DownloadStatus.paused)
        .toList();
    final completed = state.completedTasks;
    final failed = state.failedTasks;
    final inProgressCount = downloading.length + waiting.length + paused.length;
    final totalCount = state.tasks.length;

    return DesktopPageScaffold(
      title: '下载',
      subtitle: totalCount == 0
          ? '还没有下载任务'
          : '进行中 $inProgressCount · 已完成 ${completed.length} · 失败 ${failed.length}',
      actions: [
        if (inProgressCount > 0)
          state.queuePaused
              ? TextButton.icon(
                  onPressed: () => unawaited(notifier.resumeQueue()),
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('继续队列'),
                )
              : TextButton.icon(
                  onPressed: notifier.pauseQueue,
                  icon: const Icon(Icons.pause, size: 16),
                  label: const Text('暂停全部'),
                ),
        IconButton(
          tooltip: '重新统计缓存占用',
          onPressed: () => unawaited(notifier.refreshCacheUsage()),
          icon: const Icon(Icons.refresh, size: 20),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: DesktopSpacing.sm,
            runSpacing: DesktopSpacing.xs,
            children: [
              DesktopInfoChip(
                icon: Icons.downloading,
                label: '进行中 $inProgressCount',
              ),
              DesktopInfoChip(
                icon: Icons.check_circle_outline,
                label: '已完成 ${completed.length}',
              ),
              DesktopInfoChip(
                icon: Icons.error_outline,
                label: '失败 ${failed.length}',
              ),
              DesktopInfoChip(
                icon: Icons.storage,
                label:
                    '离线缓存 ${formatDesktopBytes(state.estimatedOfflineCacheBytes)}',
              ),
            ],
          ),
          if (state.queueBlockedReason != null)
            Padding(
              padding: const EdgeInsets.only(top: DesktopSpacing.sm),
              child: _Banner(
                icon: Icons.pause_circle_outline,
                message: state.queueBlockedReason!,
                color: scheme.onSurfaceVariant,
              ),
            ),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.only(top: DesktopSpacing.sm),
              child: _Banner(
                icon: _noticeIsError ? Icons.error_outline : Icons.info_outline,
                message: _notice!,
                color: _noticeIsError ? scheme.error : scheme.onSurfaceVariant,
                onDismiss: () => setState(() => _notice = null),
              ),
            ),
          const SizedBox(height: DesktopSpacing.md),
          Expanded(
            child: totalCount == 0
                ? const DesktopEmptyState(
                    icon: Icons.download_outlined,
                    title: '还没有下载任务',
                    message: '在歌曲菜单或播放页点「下载」，任务会出现在这里',
                  )
                : AppScrollbar(
                    builder: (controller) => ListView(
                      controller: controller,
                      padding: const EdgeInsets.only(
                        bottom: DesktopSpacing.xxxl,
                        right: DesktopSpacing.xs,
                      ),
                      children: [
                        if (downloading.isNotEmpty ||
                            waiting.isNotEmpty ||
                            paused.isNotEmpty) ...[
                          DesktopSectionCard(
                            title: '进行中',
                            subtitle:
                                '下载中 ${downloading.length} · 等待中 ${waiting.length} · 已暂停 ${paused.length}',
                            child: Column(
                              children: [
                                for (final task in [
                                  ...downloading,
                                  ...waiting,
                                  ...paused,
                                ])
                                  _DownloadRow(
                                    key: ValueKey('download-active-${task.id}'),
                                    task: task,
                                    onPause:
                                        task.status ==
                                            DownloadStatus.downloading
                                        ? () => notifier.pauseDownload(task.id)
                                        : null,
                                    onStart:
                                        task.status == DownloadStatus.waiting ||
                                            task.status == DownloadStatus.paused
                                        ? () => unawaited(
                                            notifier.startWaitingTask(task.id),
                                          )
                                        : null,
                                    onCancel: () =>
                                        notifier.cancelDownload(task.id),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: DesktopSpacing.lg),
                        ],
                        if (completed.isNotEmpty) ...[
                          DesktopSectionCard(
                            title: '已完成',
                            subtitle: completed.length > _maxCompletedShown
                                ? '共 ${completed.length} 项，这里显示前 $_maxCompletedShown 项'
                                : '共 ${completed.length} 项',
                            child: Column(
                              children: [
                                for (final task in completed.take(
                                  _maxCompletedShown,
                                ))
                                  _DownloadRow(
                                    key: ValueKey('download-done-${task.id}'),
                                    task: task,
                                    onOpenFolder: task.filePath == null
                                        ? null
                                        : () => unawaited(_openFolder(task)),
                                    onDelete: () =>
                                        unawaited(_deleteCompleted(task)),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: DesktopSpacing.lg),
                        ],
                        if (failed.isNotEmpty) ...[
                          DesktopSectionCard(
                            title: '失败',
                            subtitle: '共 ${failed.length} 项 · 重试会从断点继续',
                            child: Column(
                              children: [
                                for (final task in failed)
                                  _DownloadRow(
                                    key: ValueKey('download-failed-${task.id}'),
                                    task: task,
                                    onRetry: () => unawaited(
                                      notifier.resumeDownload(task.id),
                                    ),
                                    onDelete: () =>
                                        unawaited(_removeRecord(task)),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _openFolder(DownloadTask task) async {
    final path = task.filePath?.trim();
    if (path == null || path.isEmpty) {
      _showNotice('这条记录没有本地文件路径', isError: true);
      return;
    }
    try {
      await FileOpener.openFolder(p.dirname(path));
    } on FileOpenerException catch (error) {
      _showNotice(error.message, isError: true);
    }
  }

  Future<void> _deleteCompleted(DownloadTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除下载文件'),
        content: Text('确定要删除「${task.song.name}」吗？这会同时删除本地文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    final removed = await ref
        .read(downloadProvider.notifier)
        .removeTask(task.id);
    if (!mounted) return;
    if (!removed) {
      _showNotice('删除下载文件失败', isError: true);
      return;
    }
    // A file shared with another completed row is deliberately kept: the app
    // never deletes a file another record still points at.
    final keptPath = ref.read(downloadProvider).keptSharedFilePath;
    if (keptPath != null) {
      ref.read(downloadProvider.notifier).acknowledgeKeptSharedFile();
      _showNotice('已删除这条记录，但文件仍被另一条记录使用，已保留');
    }
  }

  Future<void> _removeRecord(DownloadTask task) async {
    final removed = await ref
        .read(downloadProvider.notifier)
        .removeTask(task.id);
    if (!mounted) return;
    if (!removed) _showNotice('删除记录失败', isError: true);
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;
  final VoidCallback? onDismiss;

  const _Banner({
    required this.icon,
    required this.message,
    required this.color,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesktopSpacing.md,
        vertical: DesktopSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: DesktopRadii.smAll,
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: DesktopSpacing.sm),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DesktopText.caption.copyWith(color: color),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              tooltip: '关闭提示',
              onPressed: onDismiss,
              iconSize: 14,
              icon: const Icon(Icons.close),
            ),
        ],
      ),
    );
  }
}

class _DownloadRow extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback? onPause;
  final VoidCallback? onStart;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;
  final VoidCallback? onOpenFolder;

  const _DownloadRow({
    super.key,
    required this.task,
    this.onPause,
    this.onStart,
    this.onCancel,
    this.onRetry,
    this.onDelete,
    this.onOpenFolder,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Song song = task.song;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesktopSpacing.sm,
        vertical: DesktopSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.25),
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // On a narrow content plate the 220 px progress column is dropped
          // instead of squeezing the title to nothing; the same information is
          // then folded into a single line under the subtitle.
          final showProgress = constraints.maxWidth >= 620;
          return Row(
            children: [
              DesktopCoverArt(url: song.coverUrl, size: 42),
              const SizedBox(width: DesktopSpacing.md),
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            song.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DesktopText.bodyStrong.copyWith(
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: DesktopSpacing.sm),
                        _statusPill(scheme),
                        if (task.isOfflineCache) ...[
                          const SizedBox(width: DesktopSpacing.xs),
                          DesktopStatusPill(
                            label: '离线缓存',
                            color: scheme.tertiary,
                            icon: Icons.offline_pin_outlined,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${song.artistNames} · ${task.qualityLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopText.caption.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (!showProgress) ...[
                      const SizedBox(height: 2),
                      _compactDetail(scheme),
                    ],
                  ],
                ),
              ),
              if (showProgress) ...[
                const SizedBox(width: DesktopSpacing.md),
                SizedBox(width: 220, child: _progressArea(context, scheme)),
              ],
              const SizedBox(width: DesktopSpacing.md),
              SizedBox(
                width: 96,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: _actions(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The progress area's information squeezed onto one line for narrow rows.
  Widget _compactDetail(ColorScheme scheme) {
    final String text;
    switch (task.status) {
      case DownloadStatus.downloading:
        final percent = (task.progress * 100).clamp(0, 100).toStringAsFixed(0);
        text =
            '$percent% · ${formatDesktopBytes(task.downloadedBytes)} / '
            '${formatDesktopBytes(task.totalBytes ?? 0)}';
      case DownloadStatus.waiting:
        text = '等待队列开始';
      case DownloadStatus.paused:
        text = '已暂停 · ${formatDesktopBytes(task.downloadedBytes)}';
      case DownloadStatus.completed:
        text = task.filePath ?? '已保存到下载目录';
      case DownloadStatus.failed:
        text = task.error ?? '下载失败';
    }
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: DesktopText.caption.copyWith(
        color: task.status == DownloadStatus.failed
            ? scheme.error
            : scheme.onSurfaceVariant,
      ),
    );
  }

  DesktopStatusPill _statusPill(ColorScheme scheme) {
    return switch (task.status) {
      DownloadStatus.downloading => DesktopStatusPill(
        label: '下载中',
        color: scheme.primary,
        icon: Icons.downloading,
      ),
      DownloadStatus.waiting => DesktopStatusPill(
        label: '等待中',
        color: scheme.onSurfaceVariant,
        icon: Icons.schedule,
      ),
      DownloadStatus.paused => DesktopStatusPill(
        label: '已暂停',
        color: scheme.secondary,
        icon: Icons.pause,
      ),
      DownloadStatus.completed => DesktopStatusPill(
        label: '已完成',
        color: scheme.tertiary,
        icon: Icons.check,
      ),
      DownloadStatus.failed => DesktopStatusPill(
        label: '失败',
        color: scheme.error,
        icon: Icons.error_outline,
      ),
    };
  }

  Widget _progressArea(BuildContext context, ColorScheme scheme) {
    switch (task.status) {
      case DownloadStatus.downloading:
        final percent = (task.progress * 100).clamp(0, 100).toStringAsFixed(0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            LinearProgressIndicator(value: task.progress, minHeight: 3),
            const SizedBox(height: 3),
            Text(
              '$percent% · ${formatDesktopBytes(task.downloadedBytes)} / '
              '${formatDesktopBytes(task.totalBytes ?? 0)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DesktopText.caption.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      case DownloadStatus.waiting:
        return Text(
          '等待队列开始',
          style: DesktopText.caption.copyWith(color: scheme.onSurfaceVariant),
        );
      case DownloadStatus.paused:
        return Text(
          '已暂停 · ${formatDesktopBytes(task.downloadedBytes)}',
          style: DesktopText.caption.copyWith(color: scheme.onSurfaceVariant),
        );
      case DownloadStatus.completed:
        return Text(
          task.filePath ?? '已保存到下载目录',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
          style: DesktopText.caption.copyWith(color: scheme.onSurfaceVariant),
        );
      case DownloadStatus.failed:
        return Text(
          task.error ?? '下载失败',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: DesktopText.caption.copyWith(color: scheme.error),
        );
    }
  }

  List<Widget> _actions() {
    switch (task.status) {
      case DownloadStatus.downloading:
        return [
          if (onPause != null)
            IconButton(
              tooltip: '暂停下载',
              onPressed: onPause,
              iconSize: 17,
              icon: const Icon(Icons.pause),
            ),
          if (onCancel != null)
            IconButton(
              tooltip: '取消下载',
              onPressed: onCancel,
              iconSize: 17,
              icon: const Icon(Icons.close),
            ),
        ];
      case DownloadStatus.waiting:
      case DownloadStatus.paused:
        return [
          if (onStart != null)
            IconButton(
              tooltip: task.status == DownloadStatus.paused ? '继续下载' : '开始下载',
              onPressed: onStart,
              iconSize: 17,
              icon: const Icon(Icons.play_arrow),
            ),
          if (onCancel != null)
            IconButton(
              tooltip: '取消下载',
              onPressed: onCancel,
              iconSize: 17,
              icon: const Icon(Icons.close),
            ),
        ];
      case DownloadStatus.completed:
        return [
          if (onOpenFolder != null)
            IconButton(
              tooltip: '打开所在文件夹',
              onPressed: onOpenFolder,
              iconSize: 17,
              icon: const Icon(Icons.folder_open),
            ),
          if (onDelete != null)
            IconButton(
              tooltip: '删除记录和文件',
              onPressed: onDelete,
              iconSize: 17,
              icon: const Icon(Icons.delete_outline),
            ),
        ];
      case DownloadStatus.failed:
        return [
          if (onRetry != null)
            IconButton(
              tooltip: '重试',
              onPressed: onRetry,
              iconSize: 17,
              icon: const Icon(Icons.refresh),
            ),
          if (onDelete != null)
            IconButton(
              tooltip: '删除记录',
              onPressed: onDelete,
              iconSize: 17,
              icon: const Icon(Icons.delete_outline),
            ),
        ];
    }
  }
}
