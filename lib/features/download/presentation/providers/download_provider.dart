import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../models/audio_quality.dart';
import '../../../../models/song.dart';
import '../../../../models/user.dart';
import '../../../../platform/base/platform_registry.dart';
import '../../data/download_task_store.dart';
import '../../data/repositories/download_manager.dart';
import '../../domain/entities/download_task.dart';

/// State for the download system.
class DownloadState {
  final List<DownloadTask> tasks;
  final bool isCheckingVip;

  const DownloadState({this.tasks = const [], this.isCheckingVip = false});

  DownloadState copyWith({List<DownloadTask>? tasks, bool? isCheckingVip}) {
    return DownloadState(
      tasks: tasks ?? this.tasks,
      isCheckingVip: isCheckingVip ?? this.isCheckingVip,
    );
  }

  List<DownloadTask> get activeTasks => tasks
      .where(
        (t) =>
            t.status == DownloadStatus.downloading ||
            t.status == DownloadStatus.waiting,
      )
      .toList();

  List<DownloadTask> get completedTasks =>
      tasks.where((t) => t.status == DownloadStatus.completed).toList();

  List<DownloadTask> get failedTasks =>
      tasks.where((t) => t.status == DownloadStatus.failed).toList();

  int get activeCount => activeTasks.length;

  List<DownloadTask> get offlineCacheTasks =>
      tasks.where((t) => t.isOfflineCache).toList();

  List<DownloadTask> get completedOfflineCacheTasks => offlineCacheTasks
      .where((t) => t.status == DownloadStatus.completed)
      .toList();

  List<DownloadTask> get failedOfflineCacheTasks => offlineCacheTasks
      .where((t) => t.status == DownloadStatus.failed)
      .toList();

  int get offlineCacheCount => offlineCacheTasks.length;

  int get estimatedOfflineCacheBytes => completedOfflineCacheTasks.fold<int>(
    0,
    (sum, task) => sum + (task.totalBytes ?? task.downloadedBytes),
  );
}

/// Notifier for managing downloads.
class DownloadNotifier extends StateNotifier<DownloadState> {
  final DownloadManager _manager;
  final DownloadTaskStore _taskStore;
  final FutureOr<bool> Function(String path) _fileExists;
  final Map<String, StreamSubscription> _subscriptions = {};
  late final Future<void> ready;

  DownloadNotifier({
    DownloadManager? manager,
    DownloadState? initialState,
    DownloadTaskStore? taskStore,
    FutureOr<bool> Function(String path)? fileExists,
  })
    : _manager = manager ?? DownloadManager(),
      _taskStore = taskStore ?? defaultDownloadTaskStore(),
      _fileExists = fileExists ?? ((path) => File(path).exists()),
      super(initialState ?? const DownloadState()) {
    ready = initialState == null ? _restoreStoredTasks() : Future<void>.value();
  }

  DownloadManager get manager => _manager;

  /// Check VIP status for a platform and quality combination.
  /// Returns true if download is allowed.
  Future<bool> checkVipForDownload(Song song, AudioLevel quality) async {
    try {
      final platform = PlatformRegistry.get(song.platform);
      final vipLevel = await platform.getVipStatus();

      // Free users can only download standard quality
      if (vipLevel == VipLevel.free && quality != AudioLevel.low) {
        return false;
      }

      // VIP users can download up to high quality.
      if (vipLevel == VipLevel.vip && quality.isSvipOnly) {
        return false;
      }

      // SVIP can download all qualities
      return true;
    } catch (e) {
      debugPrint('VIP check error: $e');
      return false;
    }
  }

  /// Get required VIP level for a quality.
  VipLevel requiredVipLevel(AudioLevel quality) {
    if (quality.isSvipOnly) {
      return VipLevel.svip;
    }
    if (quality.isVipOnly) {
      return VipLevel.vip;
    }
    return VipLevel.free;
  }

  /// Start downloading a song.
  Future<void> startDownload(Song song, AudioLevel quality) async {
    // Check if already downloading
    final existing = state.tasks.where(
      (t) =>
          t.song.id == song.id &&
          t.song.platform == song.platform &&
          t.quality == quality &&
          t.status != DownloadStatus.failed,
    );
    if (existing.isNotEmpty) return;

    final task = DownloadTask(
      id: '${song.platform.name}_${song.id}_${quality.name}',
      song: song,
      quality: quality,
      createdAt: DateTime.now(),
    );

    _setTasks([...state.tasks, task]);

    // Start the download
    final stream = _manager.download(task);
    _subscriptions[task.id] = stream.listen(
      (progress) {
        _updateTaskProgress(task.id, progress);
      },
      onDone: () {
        _subscriptions.remove(task.id);
      },
    );
  }

  /// Enqueue songs for offline cache without starting network downloads.
  Future<void> cacheSongs(
    List<Song> songs, {
    required AudioLevel quality,
  }) async {
    if (songs.isEmpty) return;

    final existingIds = state.tasks.map((task) => task.id).toSet();
    final newTasks = <DownloadTask>[];
    final now = DateTime.now();

    for (final song in songs) {
      final id = '${song.platform.name}_${song.id}_${quality.name}';
      if (existingIds.contains(id)) continue;
      existingIds.add(id);
      newTasks.add(
        DownloadTask(
          id: id,
          song: song,
          quality: quality,
          createdAt: now,
          isOfflineCache: true,
        ),
      );
    }

    if (newTasks.isEmpty) return;
    _setTasks([...state.tasks, ...newTasks]);
  }

  Future<void> cleanupOfflineCache({required int sizeLimitMb}) async {
    final limitBytes = sizeLimitMb * 1024 * 1024;
    if (limitBytes <= 0) return;

    var completed = state.completedOfflineCacheTasks.toList()
      ..sort(
        (left, right) => (left.completedAt ?? left.createdAt).compareTo(
          right.completedAt ?? right.createdAt,
        ),
      );
    var totalBytes = completed.fold<int>(
      0,
      (sum, task) => sum + (task.totalBytes ?? task.downloadedBytes),
    );

    for (final task in completed) {
      if (totalBytes <= limitBytes) break;
      final taskBytes = task.totalBytes ?? task.downloadedBytes;
      final removed = await removeTask(task.id);
      if (removed) {
        totalBytes -= taskBytes;
      }
    }
  }

  void _updateTaskProgress(String taskId, DownloadProgress progress) {
    final tasks = List<DownloadTask>.from(state.tasks);
    final index = tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    final task = tasks[index];

    if (progress.completed) {
      tasks[index] = task.copyWith(
        status: DownloadStatus.completed,
        progress: 1.0,
        downloadedBytes: progress.downloadedBytes,
        totalBytes: () => progress.totalBytes,
        filePath: () => progress.filePath,
        completedAt: () => DateTime.now(),
      );
    } else if (progress.error != null) {
      tasks[index] = task.copyWith(
        status: DownloadStatus.failed,
        error: () => progress.error,
      );
    } else if (progress.paused) {
      tasks[index] = task.copyWith(status: DownloadStatus.paused);
    } else {
      tasks[index] = task.copyWith(
        status: DownloadStatus.downloading,
        progress: progress.progress,
        downloadedBytes: progress.downloadedBytes,
        totalBytes: () => progress.totalBytes,
      );
    }

    _setTasks(tasks);
  }

  /// Pause a download.
  void pauseDownload(String taskId) {
    _manager.pause(taskId);
  }

  /// Resume or retry a download.
  void resumeDownload(String taskId) {
    final index = state.tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;
    final task = state.tasks[index];

    if (task.status == DownloadStatus.paused ||
        task.status == DownloadStatus.failed) {
      final tasks = List<DownloadTask>.from(state.tasks);
      tasks[index] = task.copyWith(
        status: DownloadStatus.waiting,
        error: () => null,
      );
      _setTasks(tasks);

      final stream = _manager.download(tasks[index]);
      _subscriptions[taskId] = stream.listen(
        (progress) => _updateTaskProgress(taskId, progress),
        onDone: () => _subscriptions.remove(taskId),
      );
    }
  }

  /// Cancel a download.
  void cancelDownload(String taskId) {
    _manager.cancel(taskId);
    final tasks = List<DownloadTask>.from(state.tasks);
    tasks.removeWhere((t) => t.id == taskId);
    _setTasks(tasks);
  }

  Future<String> currentDownloadRootPath() async {
    final directory = await _manager.currentRootDirectory();
    return directory.path;
  }

  Future<bool> setCustomDownloadRoot(String path) {
    return _manager.setCustomRootDirectory(path);
  }

  Future<void> resetDownloadRoot() {
    return _manager.resetCustomRootDirectory();
  }

  /// Remove a task from the list. Completed tasks also delete the local file.
  Future<bool> removeTask(String taskId) async {
    await _subscriptions.remove(taskId)?.cancel();
    final index = state.tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return true;

    final task = state.tasks[index];
    if (task.status == DownloadStatus.completed) {
      final deleted = await _manager.deleteDownloadedFile(task);
      if (!deleted) return false;
    }

    final tasks = List<DownloadTask>.from(state.tasks);
    tasks.removeAt(index);
    _setTasks(tasks);
    return true;
  }

  /// Check if a song is already downloaded.
  bool isDownloaded(String songId, AudioLevel quality, {String? platform}) {
    return state.tasks.any(
      (t) =>
          t.song.id == songId &&
          t.quality == quality &&
          (platform == null || t.song.platform.name == platform) &&
          t.status == DownloadStatus.completed,
    );
  }

  @override
  void dispose() {
    for (final sub in _subscriptions.values) {
      sub.cancel();
    }
    _manager.dispose();
    super.dispose();
  }

  Future<void> _restoreStoredTasks() async {
    final stored = await _taskStore.load();
    if (!mounted) return;
    if (stored.isEmpty) return;

    final restored = <DownloadTask>[];
    for (final task in stored) {
      final normalized = await _normalizeRestoredTask(task);
      if (normalized != null) restored.add(normalized);
    }

    state = state.copyWith(tasks: restored);
    await _persistTasks(restored);
  }

  Future<DownloadTask?> _normalizeRestoredTask(DownloadTask task) async {
    switch (task.status) {
      case DownloadStatus.completed:
        final path = task.filePath;
        if (path == null || path.trim().isEmpty) return null;
        return await _fileExists(path) ? task : null;
      case DownloadStatus.failed:
        return task;
      case DownloadStatus.waiting:
      case DownloadStatus.downloading:
      case DownloadStatus.paused:
        return task.copyWith(status: DownloadStatus.paused);
    }
  }

  void _setTasks(List<DownloadTask> tasks) {
    if (!mounted) return;
    state = state.copyWith(tasks: tasks);
    unawaited(_persistTasks(tasks));
  }

  Future<void> _persistTasks(List<DownloadTask> tasks) {
    return _taskStore.save(List<DownloadTask>.unmodifiable(tasks));
  }
}

final downloadProvider = StateNotifierProvider<DownloadNotifier, DownloadState>(
  (ref) {
    return DownloadNotifier();
  },
);
