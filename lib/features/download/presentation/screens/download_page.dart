import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../utils/file_opener.dart';
import '../../data/download_directory_service.dart';
import '../../data/download_scheduler.dart';
import '../providers/download_provider.dart';
import '../../domain/entities/download_task.dart';

/// Opens the system folder picker and returns the chosen path, or null.
///
/// A seam for tests: `file_picker`'s desktop implementation is FFI-backed and
/// would open a real dialog (and hang) inside `flutter test`.
typedef DirectoryPicker = Future<String?> Function(String? dialogTitle);

Future<String?> _pickDirectoryWithPlugin(String? dialogTitle) =>
    FilePicker.getDirectoryPath(dialogTitle: dialogTitle);

class DownloadPage extends ConsumerWidget {
  const DownloadPage({super.key, this.pickDirectory = _pickDirectoryWithPlugin});

  /// Overridable so the directory flow can be tested without the plugin.
  final DirectoryPicker pickDirectory;

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
    final options = await notifier.availableDownloadRoots();
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      // See `DownloadButton._showQualityPicker`: the shell's nested navigator fills
      // the screen now, so a sheet pushed on it would sit under the floating chrome.
      useRootNavigator: true,
      showDragHandle: true,
      builder: (sheetContext) {
        var displayedPath = currentPath;
        var currentOptions = options;
        var isSaving = false;

        /// Shown inside the sheet as well as in a snack bar: the sheet covers the
        /// bottom of the screen, so a snack bar alone can be hidden behind it —
        /// and the whole complaint about this flow was that failures were silent.
        String? errorMessage;
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Future<void> refreshPath() async {
              final path = await notifier.currentDownloadRootPath();
              final refreshed = await notifier.availableDownloadRoots();
              if (!sheetContext.mounted) return;
              setSheetState(() {
                displayedPath = path;
                currentOptions = refreshed;
              });
            }

            /// Applies [path] as the root, always resetting `isSaving` and always
            /// reporting the outcome.
            ///
            /// The old flow had no `try/finally`: when `Directory.create` threw,
            /// `isSaving` stayed true forever — spinner on, every control greyed
            /// out — and the exception vanished into `runZonedGuarded`.
            Future<void> applyRoot(
              Future<DownloadRootResult> Function() apply, {
              required String successMessage,
            }) async {
              setSheetState(() {
                isSaving = true;
                errorMessage = null;
              });

              DownloadRootResult result;
              try {
                result = await apply();
              } on Object catch (error) {
                // The service never throws; this is the belt to its braces, so a
                // future change cannot freeze the sheet again.
                result = DownloadRootResult.failure(
                  DownloadRootRejection.notWritable,
                  detail: error.toString(),
                );
              } finally {
                if (sheetContext.mounted) {
                  setSheetState(() {
                    isSaving = false;
                  });
                }
              }

              await refreshPath();
              if (!sheetContext.mounted) return;
              setSheetState(() {
                errorMessage = result.isOk ? null : result.message;
              });

              if (!context.mounted) return;
              if (result.isOk) {
                showSuccessSnackBar(context, successMessage);
              } else {
                showErrorSnackBar(context, result.message);
              }
            }

            Future<void> chooseCustomDirectory() async {
              String? path;
              try {
                path = await pickDirectory('选择下载目录');
              } on Object catch (error) {
                // A thrown platform error is a real failure, and is reported.
                debugPrint('directory picker failed: $error');
                if (!sheetContext.mounted) return;
                setSheetState(() {
                  errorMessage = '该位置无法作为下载目录，请换一个文件夹';
                });
                if (context.mounted) {
                  showErrorSnackBar(context, '该位置无法作为下载目录，请换一个文件夹');
                }
                return;
              }
              if (path == null || path.trim().isEmpty) {
                // `null` overwhelmingly means "the user cancelled the dialog",
                // and cancelling is a normal action — so this branch stays
                // silent (it only clears a message left over from before).
                //
                // KNOWN LIMITATION: `file_picker` also swallows
                // `PlatformException("unknown_path")` — a cloud-provider folder
                // it cannot map to a filesystem path — and returns null, so the
                // two cases are indistinguishable. When we cannot tell them
                // apart the cheaper default is silence: the occasional
                // unselectable cloud folder going quiet beats an error toast on
                // every cancel. The failure that actually matters (an
                // unwritable directory) is caught later by the write probe,
                // with an accurate message.
                if (!sheetContext.mounted) return;
                setSheetState(() {
                  errorMessage = null;
                });
                return;
              }
              await applyRoot(
                () => notifier.setCustomDownloadRoot(path!),
                successMessage: '下载目录已更新',
              );
            }

            Future<void> resetDirectory() async {
              setSheetState(() {
                isSaving = true;
                errorMessage = null;
              });
              try {
                await notifier.resetDownloadRoot();
              } on Object catch (error) {
                debugPrint('resetDownloadRoot failed: $error');
              } finally {
                if (sheetContext.mounted) {
                  setSheetState(() {
                    isSaving = false;
                  });
                }
              }
              await refreshPath();
              if (!sheetContext.mounted) return;
              setSheetState(() {
                errorMessage = null;
              });
              if (context.mounted) {
                showSuccessSnackBar(context, '已恢复默认下载目录');
              }
            }

            Future<void> openDownloadFolder() async {
              try {
                await FileOpener.openFolder(displayedPath);
              } catch (e) {
                if (!context.mounted) return;
                showErrorSnackBar(context, e.toString());
              }
            }

            return SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '下载目录',
                              style: Theme.of(
                                sheetContext,
                              ).textTheme.titleLarge,
                            ),
                          ),
                          if (isSaving)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '只能写入应用可访问的位置；下面两项都无需额外权限。',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(sheetContext).colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final option in currentOptions)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            option.isCurrent
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: option.isCurrent
                                ? Theme.of(sheetContext).colorScheme.primary
                                : null,
                          ),
                          title: Text(option.kind.label),
                          subtitle: Text(
                            '${option.path}\n${option.kind.description}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          enabled: !isSaving && !option.isCurrent,
                          onTap: () => applyRoot(
                            () => notifier.setCustomDownloadRoot(option.path),
                            successMessage: '下载目录已更新',
                          ),
                        ),
                      if (errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 4),
                          child: Text(
                            errorMessage!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(sheetContext).colorScheme.error,
                            ),
                          ),
                        ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.drive_folder_upload),
                        title: const Text('选择其他位置…'),
                        subtitle: const Text(
                          '系统文件夹选择器；不可写时会提示，不会改动设置',
                        ),
                        enabled: !isSaving,
                        onTap: chooseCustomDirectory,
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.folder_open),
                        title: const Text('打开下载文件夹'),
                        subtitle: Text(
                          displayedPath,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: openDownloadFolder,
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.restore),
                        label: const Text('恢复默认目录'),
                        onPressed: isSaving ? null : resetDirectory,
                      ),
                    ],
                  ),
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
    final queuePaused = ref.watch(
      downloadProvider.select((s) => s.queuePaused),
    );
    final queueBlockedReason = ref.watch(
      downloadProvider.select((s) => s.queueBlockedReason),
    );

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
            if (queuePaused)
              IconButton(
                icon: const Icon(Icons.play_circle_outline),
                tooltip: '继续队列',
                onPressed: () {
                  unawaited(notifier.resumeQueue());
                },
              ),
            if (activeTasks.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.pause_circle_outline),
                tooltip: '暂停全部',
                onPressed: () {
                  notifier.pauseQueue();
                },
              ),
          ],
        ),
        body: Column(
          children: [
            // Explains why nothing is starting (Wi-Fi gate / pause / 离线模式)
            // instead of leaving the queue silently stuck.
            if (queueBlockedReason != null)
              Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  queueBlockedReason,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  // Active downloads
                  _DownloadList(
                    tasks: activeTasks,
                    formatBytes: _formatBytes,
                    onPause: notifier.pauseDownload,
                    onCancel: notifier.cancelDownload,
                    onResume: notifier.resumeDownload,
                    onStart: notifier.startWaitingTask,
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
  final Future<DownloadEnqueueOutcome> Function(String)? onStart;

  const _DownloadList({
    required this.tasks,
    required this.formatBytes,
    this.onPause,
    this.onResume,
    this.onCancel,
    this.onRemove,
    this.onRetry,
    this.onStart,
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
            onStart: onStart,
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
  final Future<DownloadEnqueueOutcome> Function(String)? onStart;

  const _DownloadTile({
    required this.task,
    required this.formatBytes,
    this.onPause,
    this.onResume,
    this.onCancel,
    this.onRemove,
    this.onRetry,
    this.onStart,
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
        // A `waiting` row is a real queue entry now (offline-cache tasks are
        // created this way and the Wi-Fi gate can hold one back), so it needs
        // its own controls. It used to render no action at all.
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onStart != null)
              IconButton(
                icon: const Icon(Icons.play_arrow, size: 20),
                tooltip: '开始',
                onPressed: () => onStart!(task.id),
              ),
            if (onCancel != null)
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: '取消',
                onPressed: () => onCancel!(task.id),
              ),
          ],
        );
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
