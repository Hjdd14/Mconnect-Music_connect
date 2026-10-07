import 'dart:async';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../models/audio_quality.dart';
import '../../../../models/song.dart';
import '../../../../models/user.dart';
import '../../../../platform/base/platform_registry.dart';
import '../../data/download_directory_service.dart';
import '../../data/download_scheduler.dart';
import '../../data/download_task_store.dart';
import '../../data/repositories/download_manager.dart';
import '../../data/saf_download_writer.dart' show isSafDocumentUri;
import '../../domain/entities/download_failure.dart';
import '../../domain/entities/download_task.dart';
import '../../../offline_cache/presentation/providers/offline_cache_provider.dart';

/// How many times the queue retries a retryable failure on its own.
const int kMaxAutoRetries = 2;

/// Delay before the first automatic retry (grows linearly per attempt).
const Duration kAutoRetryDelay = Duration(seconds: 3);

/// How often the offline cache remembers "this file was used".
const Duration kCacheAccessTouchInterval = Duration(minutes: 1);

/// The switches the queue obeys.
///
/// These are the same four switches the 离线缓存中心 page shows. They used to be
/// pure decoration — `wifiOnly` appeared only in the provider that stored it,
/// nothing read `autoRetry`/`autoCleanup`, and `offlineMode` only toggled a
/// switch's own value — so the queue now reads them through this one object.
@immutable
class DownloadQueuePolicy {
  final bool wifiOnly;
  final bool autoRetry;
  final bool autoCleanup;
  final bool offlineMode;
  final int sizeLimitMb;

  const DownloadQueuePolicy({
    this.wifiOnly = false,
    this.autoRetry = true,
    this.autoCleanup = true,
    this.offlineMode = false,
    this.sizeLimitMb = 1024,
  });

  /// Defaults for code that builds a notifier directly (tests, previews).
  ///
  /// Deliberately **not** the user's stored preference: the app wires the real
  /// one through `downloadProvider`. `wifiOnly: false` here keeps a bare
  /// notifier from reaching for the connectivity plugin.
  static const DownloadQueuePolicy defaults = DownloadQueuePolicy();

  DownloadQueuePolicy copyWith({
    bool? wifiOnly,
    bool? autoRetry,
    bool? autoCleanup,
    bool? offlineMode,
    int? sizeLimitMb,
  }) {
    return DownloadQueuePolicy(
      wifiOnly: wifiOnly ?? this.wifiOnly,
      autoRetry: autoRetry ?? this.autoRetry,
      autoCleanup: autoCleanup ?? this.autoCleanup,
      offlineMode: offlineMode ?? this.offlineMode,
      sizeLimitMb: sizeLimitMb ?? this.sizeLimitMb,
    );
  }
}

const Object _unset = Object();

/// State for the download system.
class DownloadState {
  final List<DownloadTask> tasks;
  final bool isCheckingVip;

  /// Cached-bytes measured by scanning the files (see
  /// [DownloadNotifier.refreshCacheUsage]). `null` until the first scan, in
  /// which case [estimatedOfflineCacheBytes] falls back to the task records.
  final int? offlineCacheBytes;

  /// True while the queue is paused by the user.
  final bool queuePaused;

  /// Why nothing is starting right now, for the UI to show. `null` = running
  /// normally.
  final String? queueBlockedReason;

  const DownloadState({
    this.tasks = const [],
    this.isCheckingVip = false,
    this.offlineCacheBytes,
    this.queuePaused = false,
    this.queueBlockedReason,
  });

  DownloadState copyWith({
    List<DownloadTask>? tasks,
    bool? isCheckingVip,
    Object? offlineCacheBytes = _unset,
    bool? queuePaused,
    Object? queueBlockedReason = _unset,
  }) {
    return DownloadState(
      tasks: tasks ?? this.tasks,
      isCheckingVip: isCheckingVip ?? this.isCheckingVip,
      offlineCacheBytes: identical(offlineCacheBytes, _unset)
          ? this.offlineCacheBytes
          : offlineCacheBytes as int?,
      queuePaused: queuePaused ?? this.queuePaused,
      queueBlockedReason: identical(queueBlockedReason, _unset)
          ? this.queueBlockedReason
          : queueBlockedReason as String?,
    );
  }

  List<DownloadTask> get activeTasks => tasks
      .where(
        (t) =>
            t.status == DownloadStatus.downloading ||
            t.status == DownloadStatus.waiting,
      )
      .toList();

  List<DownloadTask> get waitingTasks =>
      tasks.where((t) => t.status == DownloadStatus.waiting).toList();

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

  List<DownloadTask> get waitingOfflineCacheTasks => offlineCacheTasks
      .where((t) => t.status == DownloadStatus.waiting)
      .toList();

  int get offlineCacheCount => offlineCacheTasks.length;

  /// Bytes on disk for the offline cache.
  ///
  /// Uses the scanned figure when available: summing the task records alone
  /// reported a total that never changed after a file was deleted outside the
  /// app.
  int get estimatedOfflineCacheBytes =>
      offlineCacheBytes ??
      completedOfflineCacheTasks.fold<int>(
        0,
        (sum, task) => sum + (task.totalBytes ?? task.downloadedBytes),
      );

  /// Sum of the records, for comparison in tests/diagnostics.
  int get recordedOfflineCacheBytes => completedOfflineCacheTasks.fold<int>(
    0,
    (sum, task) => sum + (task.totalBytes ?? task.downloadedBytes),
  );
}

/// What `cacheSongs` did with the rows it was given.
@immutable
class CacheEnqueueReport {
  final int started;
  final int queued;
  final int blockedNoConnection;
  final int blockedOfflineMode;
  final int blockedQueuePaused;
  final int skipped;

  const CacheEnqueueReport({
    this.started = 0,
    this.queued = 0,
    this.blockedNoConnection = 0,
    this.blockedOfflineMode = 0,
    this.blockedQueuePaused = 0,
    this.skipped = 0,
  });

  int get enqueued => started + queued;

  int get total =>
      started + queued + blockedNoConnection + blockedOfflineMode +
      blockedQueuePaused + skipped;
}

/// Notifier for managing downloads.
class DownloadNotifier extends StateNotifier<DownloadState> {
  final DownloadManager _manager;
  final DownloadTaskStore _taskStore;
  final FutureOr<bool> Function(String path) _fileExists;
  final Future<int> Function(DownloadTask task) _taskFileSize;
  final DownloadQueuePolicy Function() _policy;
  late final DownloadScheduler _scheduler;
  final Duration retryDelay;
  final int maxAutoRetries;
  final Stream<Object?>? connectivityStream;

  final Map<String, StreamSubscription> _subscriptions = {};
  final Map<String, Timer> _retryTimers = {};
  final Map<String, int> _retryAttempts = {};
  StreamSubscription<Object?>? _connectionSubscription;
  late final Future<void> ready;

  DownloadNotifier({
    DownloadManager? manager,
    DownloadState? initialState,
    DownloadTaskStore? taskStore,
    FutureOr<bool> Function(String path)? fileExists,
    Future<int> Function(DownloadTask task)? taskFileSize,
    DownloadQueuePolicy Function()? policy,
    DownloadScheduler? scheduler,
    ConnectionCheck? connectionCheck,
    this.connectivityStream,
    this.retryDelay = kAutoRetryDelay,
    this.maxAutoRetries = kMaxAutoRetries,
  }) : _manager = manager ?? DownloadManager(),
       _taskStore = taskStore ?? defaultDownloadTaskStore(),
       _fileExists = fileExists ?? ((path) => File(path).exists()),
       _taskFileSize = taskFileSize ?? _defaultTaskFileSize,
       _policy = policy ?? (() => DownloadQueuePolicy.defaults),
       super(initialState ?? const DownloadState()) {
    _scheduler =
        scheduler ??
        DownloadScheduler(
          onStart: (taskId) => unawaited(_startTaskById(taskId)),
          connectionCheck: connectionCheck,
        );
    ready = initialState == null
        ? _restoreStoredTasks()
        : Future<void>.value();
  }

  static Future<int> _defaultTaskFileSize(DownloadTask task) async {
    final path = task.filePath;
    if (path == null || path.trim().isEmpty) return 0;
    // A download published into the user's SAF folder is recorded as a
    // `content://` document URI, which `File` cannot measure. The recorded
    // total is the size the app itself wrote (and verified) before the copy, so
    // it is the right answer for cache accounting — and it costs no extra
    // platform round trip per task.
    if (isSafDocumentUri(path)) return task.totalBytes ?? task.downloadedBytes;
    try {
      final file = File(path);
      if (!await file.exists()) return 0;
      return await file.length();
    } catch (_) {
      return 0;
    }
  }

  DownloadManager get manager => _manager;

  DownloadScheduler get scheduler => _scheduler;

  /// Whether the queue will start an offline-cache task on its own right now.
  bool get canAutoStartOfflineCache {
    final policy = _policy();
    return !policy.offlineMode && !_scheduler.isPaused;
  }

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

  /// Start a download the user asked for.
  ///
  /// Only an existing **manual** task blocks this. It used to compare ids with
  /// the offline-cache queue, and those two shared one id — so a song that had
  /// ever been enqueued for caching could never be downloaded by hand again.
  Future<void> startDownload(Song song, AudioLevel quality) async {
    final id = DownloadTask.buildId(song, quality);
    final existing = state.tasks.where((t) => t.id == id).firstOrNull;
    if (existing != null && existing.status != DownloadStatus.failed) {
      return;
    }
    if (existing != null) {
      // Reuse the failed record so the list keeps its original position.
      await resumeDownload(id);
      return;
    }

    final task = DownloadTask(
      id: id,
      song: song,
      quality: quality,
      createdAt: DateTime.now(),
    );
    _setTasks([...state.tasks, task]);
    await _enqueueTask(
      task.id,
      auto: false,
      // The 仅 Wi-Fi 下载 switch says "移动网络下不自动执行缓存任务"; an explicit
      // tap is not automatic, so it is never vetoed by it.
      requiresConnection: false,
    );
  }

  /// Enqueue songs for offline cache and actually run them.
  ///
  /// This is the fix for the dead queue: it used to create `waiting` rows and
  /// never call [DownloadManager.download], and nothing else in the app ever
  /// started them.
  Future<CacheEnqueueReport> cacheSongs(
    List<Song> songs, {
    required AudioLevel quality,
  }) async {
    if (songs.isEmpty) return const CacheEnqueueReport();

    final existingIds = state.tasks.map((task) => task.id).toSet();
    final newTasks = <DownloadTask>[];
    var skipped = 0;
    final now = DateTime.now();

    for (final song in songs) {
      final id = DownloadTask.buildCacheId(song, quality);
      final alreadyThere = state.tasks.any(
        (task) => task.id == id && task.status != DownloadStatus.failed,
      );
      // A song the user already downloaded by hand needs no cache copy.
      final alreadyDownloaded = state.tasks.any(
        (task) =>
            task.id == DownloadTask.buildId(song, quality) &&
            task.status == DownloadStatus.completed,
      );
      if (existingIds.contains(id) || alreadyThere || alreadyDownloaded) {
        skipped++;
        continue;
      }
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

    if (newTasks.isNotEmpty) {
      _setTasks([...state.tasks, ...newTasks]);
    }

    var started = 0;
    var queued = 0;
    var blockedNoConnection = 0;
    var blockedOfflineMode = 0;
    var blockedQueuePaused = 0;

    for (final task in newTasks) {
      final outcome = await _enqueueTask(
        task.id,
        auto: true,
        requiresConnection: _policy().wifiOnly,
      );
      switch (outcome) {
        case DownloadEnqueueOutcome.started:
          started++;
        case DownloadEnqueueOutcome.queued:
          queued++;
        case DownloadEnqueueOutcome.blockedNoConnection:
          blockedNoConnection++;
        case DownloadEnqueueOutcome.blockedOfflineMode:
          blockedOfflineMode++;
        case DownloadEnqueueOutcome.blockedQueuePaused:
          blockedQueuePaused++;
        case DownloadEnqueueOutcome.duplicate:
          skipped++;
      }
    }

    return CacheEnqueueReport(
      started: started,
      queued: queued,
      blockedNoConnection: blockedNoConnection,
      blockedOfflineMode: blockedOfflineMode,
      blockedQueuePaused: blockedQueuePaused,
      skipped: skipped,
    );
  }

  /// Evicts offline-cache files until the cache fits [sizeLimitMb].
  ///
  /// LRU, not FIFO: the least recently **used** entry goes first, so the album
  /// someone keeps playing is not deleted just because it finished early.
  Future<int> cleanupOfflineCache({int? sizeLimitMb}) async {
    final limitBytes = (sizeLimitMb ?? _policy().sizeLimitMb) * 1024 * 1024;
    if (limitBytes <= 0) return 0;

    await refreshCacheUsage();
    // Every await below can land after `dispose` (a completion callback racing a
    // disposed provider); touching `state` then throws "after dispose was
    // called" as an unhandled zone error.
    if (!mounted) return 0;
    var totalBytes = state.estimatedOfflineCacheBytes;
    if (totalBytes <= limitBytes) return 0;

    final candidates = state.completedOfflineCacheTasks.toList()
      ..sort((left, right) => left.cacheRecency.compareTo(right.cacheRecency));

    var removed = 0;
    for (final task in candidates) {
      if (totalBytes <= limitBytes) break;
      final taskBytes = await _taskFileSize(task).then(
        (size) => size > 0 ? size : (task.totalBytes ?? task.downloadedBytes),
      );
      if (!mounted) break;
      final didRemove = await removeTask(task.id);
      if (didRemove) {
        totalBytes -= taskBytes;
        removed++;
      }
    }
    await refreshCacheUsage();
    return removed;
  }

  /// Measures the offline cache by scanning the files on disk.
  ///
  /// A file deleted outside the app stops being counted; a record whose file is
  /// gone contributes 0.
  Future<int> refreshCacheUsage() async {
    var total = 0;
    for (final task in state.completedOfflineCacheTasks) {
      total += await _taskFileSize(task);
    }
    if (!mounted) return total;
    state = state.copyWith(offlineCacheBytes: total);
    return total;
  }

  /// The local file backing [song], if it has been downloaded or cached.
  ///
  /// This is the hook the offline-playback priority needs: with 离线模式 on, the
  /// player should prefer this path over a network stream. Reading it also
  /// stamps the task's access time, which is what LRU eviction orders by.
  Future<String?> localFilePathFor(Song song, {AudioLevel? quality}) async {
    final candidates = state.tasks
        .where(
          (task) =>
              task.song.id == song.id &&
              task.song.platform == song.platform &&
              task.status == DownloadStatus.completed &&
              (task.filePath?.trim().isNotEmpty ?? false) &&
              (quality == null || task.quality == quality),
        )
        .toList();
    if (candidates.isEmpty) return null;

    // Prefer a manual download over a cache entry, then the highest quality.
    candidates.sort((left, right) {
      if (left.isOfflineCache != right.isOfflineCache) {
        return left.isOfflineCache ? 1 : -1;
      }
      return right.quality.index.compareTo(left.quality.index);
    });

    for (final task in candidates) {
      final path = task.filePath!;
      // A song published into the user's SAF folder is a `content://` document,
      // not a playback path: handing it to the player as a file path fails, and
      // `File(path).exists()` is false anyway. Skip it so offline playback
      // falls back to the stream instead of "discovering" a file it cannot use.
      if (isSafDocumentUri(path)) continue;
      if (await _fileExists(path)) {
        await _touchAccess(task);
        return path;
      }
    }
    return null;
  }

  /// Puts a `waiting` task (offline cache rows created by [cacheSongs] or held
  /// back by the connection gate) into the queue — the "开始" action the
  /// download list did not offer for `waiting` rows.
  Future<DownloadEnqueueOutcome> startWaitingTask(String taskId) async {
    final task = _taskById(taskId);
    if (task == null) return DownloadEnqueueOutcome.duplicate;
    if (task.status != DownloadStatus.waiting &&
        task.status != DownloadStatus.paused &&
        task.status != DownloadStatus.failed) {
      return DownloadEnqueueOutcome.duplicate;
    }
    _retryTimers.remove(taskId)?.cancel();
    _retryAttempts.remove(taskId);
    _replaceTask(
      task.copyWith(
        status: DownloadStatus.waiting,
        error: () => null,
        failureKind: () => null,
      ),
    );
    return _enqueueTask(
      taskId,
      auto: false,
      requiresConnection: task.isOfflineCache && _policy().wifiOnly,
    );
  }

  /// Stops the queue from starting anything new and pauses what is running.
  void pauseQueue() {
    _scheduler.pause();
    for (final task in state.tasks) {
      if (task.status == DownloadStatus.downloading) {
        _manager.pause(task.id);
      }
    }
    _syncQueueState();
  }

  /// Restarts the queue (used after 仅 Wi-Fi 下载 blocked it, or after a pause).
  ///
  /// Re-queues anything the queue itself paused: `pauseQueue` stops the running
  /// downloads too, so a "继续队列" that only un-paused the gate would leave
  /// those rows sitting at `paused` with nothing to restart them.
  Future<void> resumeQueue() async {
    await _scheduler.recheckHeld();
    await _scheduler.resume();
    final paused = state.tasks
        .where((task) => task.status == DownloadStatus.paused)
        .toList();
    for (final task in paused) {
      await _enqueueTask(
        task.id,
        auto: false,
        requiresConnection: task.isOfflineCache && _policy().wifiOnly,
      );
    }
    _syncQueueState();
  }

  void _updateTaskProgress(String taskId, DownloadProgress progress) {
    if (!mounted) return;
    final index = state.tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    final task = state.tasks[index];
    final tasks = List<DownloadTask>.from(state.tasks);

    if (progress.completed) {
      tasks[index] = task.copyWith(
        status: DownloadStatus.completed,
        progress: 1.0,
        downloadedBytes: progress.downloadedBytes,
        totalBytes: () => progress.totalBytes,
        filePath: () => progress.filePath,
        error: () => null,
        failureKind: () => null,
        completedAt: () => DateTime.now(),
        lastAccessedAt: () => DateTime.now(),
      );
      _retryAttempts.remove(taskId);
      _retryTimers.remove(taskId)?.cancel();
      _setTasks(tasks);
      _scheduler.complete(taskId);
      unawaited(_onTaskCompleted(tasks[index]));
      _syncQueueState();
      return;
    }

    if (progress.failure != null || progress.error != null) {
      final failure =
          progress.failure ??
          DownloadFailure(
            kind: DownloadFailureKind.unknown,
            message: progress.error!,
          );
      tasks[index] = task.copyWith(
        status: DownloadStatus.failed,
        error: () => failure.message,
        failureKind: () => failure.kind,
        downloadedBytes: progress.downloadedBytes > 0
            ? progress.downloadedBytes
            : task.downloadedBytes,
        filePath: progress.filePath != null
            ? () => progress.filePath
            : null,
      );
      _setTasks(tasks);
      _scheduler.complete(taskId);
      _scheduleAutoRetry(taskId, failure);
      _syncQueueState();
      return;
    }

    if (progress.paused) {
      tasks[index] = task.copyWith(
        status: DownloadStatus.paused,
        downloadedBytes: progress.downloadedBytes,
        totalBytes: progress.totalBytes > 0
            ? () => progress.totalBytes
            : null,
        progress: progress.progress,
        filePath: progress.filePath != null
            ? () => progress.filePath
            : null,
      );
      _setTasks(tasks);
      _scheduler.complete(taskId);
      _syncQueueState();
      return;
    }

    tasks[index] = task.copyWith(
      status: DownloadStatus.downloading,
      progress: progress.progress,
      downloadedBytes: progress.downloadedBytes,
      totalBytes: () => progress.totalBytes,
    );
    _setTasks(tasks);
  }

  /// Starts a task the scheduler handed a slot to.
  Future<void> _startTaskById(String taskId) async {
    if (!mounted) return;
    final task = _taskById(taskId);
    if (task == null) {
      _scheduler.remove(taskId);
      return;
    }
    _replaceTask(
      task.copyWith(
        status: DownloadStatus.downloading,
        error: () => null,
        failureKind: () => null,
      ),
    );

    final stream = _manager.download(task);
    _subscriptions[taskId] = stream.listen(
      (progress) => _updateTaskProgress(taskId, progress),
      onError: (Object error) {
        _updateTaskProgress(
          taskId,
          DownloadProgress(
            taskId: taskId,
            downloadedBytes: task.downloadedBytes,
            totalBytes: task.totalBytes ?? 0,
            progress: task.progress,
            error: error.toString(),
            failure: DownloadFailure.from(
              error,
              platformName: task.song.platform.displayName,
            ),
          ),
        );
      },
      onDone: () {
        _subscriptions.remove(taskId);
      },
    );
    _syncQueueState();
  }

  Future<void> _onTaskCompleted(DownloadTask task) async {
    await refreshCacheUsage();
    if (!mounted) return;
    final policy = _policy();
    if (task.isOfflineCache && policy.autoCleanup) {
      await cleanupOfflineCache(sizeLimitMb: policy.sizeLimitMb);
    }
  }

  /// Bounded automatic retry for transient failures, gated by 失败自动重试.
  void _scheduleAutoRetry(String taskId, DownloadFailure failure) {
    final policy = _policy();
    if (!policy.autoRetry || !failure.isRetryable) return;
    final attempts = _retryAttempts[taskId] ?? 0;
    if (attempts >= maxAutoRetries) return;

    _retryAttempts[taskId] = attempts + 1;
    _retryTimers.remove(taskId)?.cancel();
    _retryTimers[taskId] = Timer(retryDelay * (attempts + 1), () {
      _retryTimers.remove(taskId);
      if (!mounted) return;
      final task = _taskById(taskId);
      if (task == null || task.status != DownloadStatus.failed) return;
      unawaited(
        _enqueueTask(
          taskId,
          auto: true,
          requiresConnection: task.isOfflineCache && _policy().wifiOnly,
        ),
      );
    });
  }

  Future<DownloadEnqueueOutcome> _enqueueTask(
    String taskId, {
    required bool auto,
    required bool requiresConnection,
  }) async {
    if (auto && _policy().offlineMode) {
      _syncQueueState();
      return DownloadEnqueueOutcome.blockedOfflineMode;
    }
    final outcome = await _scheduler.enqueue(
      taskId,
      requiresConnection: requiresConnection,
    );
    if (outcome == DownloadEnqueueOutcome.blockedNoConnection) {
      _ensureConnectionListener();
    }
    _syncQueueState();
    return outcome;
  }

  /// Subscribes to connectivity changes while something is held back by
  /// 仅 Wi-Fi 下载, so the cache resumes by itself when Wi-Fi comes back.
  void _ensureConnectionListener() {
    if (_connectionSubscription != null) return;
    try {
      final stream = connectivityStream ?? Connectivity().onConnectivityChanged;
      _connectionSubscription = stream.listen(
        (_) => unawaited(_recheckHeld()),
        onError: (Object error) {
          debugPrint('connectivity stream error: $error');
        },
      );
    } catch (error) {
      debugPrint('connectivity stream unavailable: $error');
    }
  }

  Future<void> _recheckHeld() async {
    final resumed = await _scheduler.recheckHeld();
    if (resumed > 0) {
      debugPrint(
        'Download queue resumed $resumed task(s) after a network change',
      );
    }
    _syncQueueState();
  }

  /// Pause a download.
  void pauseDownload(String taskId) {
    _manager.pause(taskId);
  }

  /// Resume or retry a download the user asked for.
  Future<void> resumeDownload(String taskId) async {
    final task = _taskById(taskId);
    if (task == null) return;
    if (task.status != DownloadStatus.paused &&
        task.status != DownloadStatus.failed) {
      return;
    }
    _retryTimers.remove(taskId)?.cancel();
    _retryAttempts.remove(taskId);
    _replaceTask(
      task.copyWith(
        status: DownloadStatus.waiting,
        error: () => null,
        failureKind: () => null,
      ),
    );
    await _enqueueTask(
      taskId,
      auto: false,
      requiresConnection: task.isOfflineCache && _policy().wifiOnly,
    );
  }

  /// Cancel a download.
  void cancelDownload(String taskId) {
    _retryTimers.remove(taskId)?.cancel();
    _retryAttempts.remove(taskId);
    final task = _taskById(taskId);
    _manager.cancel(taskId);
    if (task != null) {
      // Resume keeps partial files; an explicit cancel must not.
      unawaited(_manager.discardPartialFile(task));
    }
    _scheduler.complete(taskId);
    _scheduler.remove(taskId);
    final tasks = List<DownloadTask>.from(state.tasks);
    tasks.removeWhere((t) => t.id == taskId);
    _setTasks(tasks);
    _syncQueueState();
  }

  Future<String> currentDownloadRootPath() async {
    final directory = await _manager.currentRootDirectory();
    return directory.path;
  }

  /// The stable, app-writable roots the settings sheet offers.
  ///
  /// Both options are inside the app's own sandbox (documents + app-specific
  /// external), so neither needs a runtime permission and neither can be
  /// unwritable.
  Future<List<DownloadRootOption>> availableDownloadRoots() =>
      _manager.directoryService.availableRootOptions();

  /// Applies a new download root.
  ///
  /// **Never throws** and reports *why* it failed (see [DownloadRootResult]):
  /// the old `bool` path let a `PathAccessException` escape as an uncaught
  /// async error, which left the settings sheet spinning on "保存中" forever
  /// with no message at all.
  Future<DownloadRootResult> setCustomDownloadRoot(String path) =>
      _manager.directoryService.applyCustomRootDirectory(path);

  Future<void> resetDownloadRoot() {
    return _manager.resetCustomRootDirectory();
  }

  /// Remove a task from the list. Completed tasks also delete the local file.
  Future<bool> removeTask(String taskId) async {
    _retryTimers.remove(taskId)?.cancel();
    _retryAttempts.remove(taskId);
    await _subscriptions.remove(taskId)?.cancel();
    _scheduler.remove(taskId);
    if (!mounted) return true;
    final index = state.tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return true;

    final task = state.tasks[index];
    if (task.status == DownloadStatus.completed) {
      final deleted = await _manager.deleteDownloadedFile(task);
      if (!deleted) return false;
      if (!mounted) return true;
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
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    _connectionSubscription?.cancel();
    _scheduler.dispose();
    _manager.dispose();
    super.dispose();
  }

  Future<void> _restoreStoredTasks() async {
    final stored = await _taskStore.load();
    if (!mounted) return;
    if (stored.isEmpty) return;

    final restored = <DownloadTask>[];
    final seenIds = <String>{};
    for (final task in stored) {
      final normalized = await _normalizeRestoredTask(task);
      if (normalized == null) continue;
      // Builds before this change gave cache rows and manual rows the same id;
      // keep the first so a restored list cannot contain a duplicate id.
      if (!seenIds.add(normalized.id)) continue;
      restored.add(normalized);
    }

    state = state.copyWith(tasks: restored);
    await _persistTasks(restored);
    await refreshCacheUsage();
    await _autoResumeRestored(restored);
  }

  Future<DownloadTask?> _normalizeRestoredTask(DownloadTask task) async {
    switch (task.status) {
      case DownloadStatus.completed:
        final path = task.filePath;
        if (path == null || path.trim().isEmpty) return null;
        // A SAF download's file lives in the user's own folder and is identified
        // by a `content://` URI, which `File(path).exists()` always answers
        // "false" for. Dropping it here (and then persisting the shortened list
        // above) made every song downloaded into a custom folder vanish from the
        // list after a restart, even though the file was still there. Existence
        // for those is the SAF side's business — the grant is checked before the
        // next download, and a refused delete is reported.
        if (isSafDocumentUri(path)) return task;
        return await _fileExists(path) ? task : null;
      case DownloadStatus.failed:
        return task;
      case DownloadStatus.waiting:
      case DownloadStatus.downloading:
      case DownloadStatus.paused:
        return task.copyWith(status: DownloadStatus.paused);
    }
  }

  /// A task that was mid-flight when the app stopped comes back `paused` and is
  /// put back in the queue — but only when 失败自动重试 is on. Before this, an
  /// interrupted download silently stayed paused after every restart.
  Future<void> _autoResumeRestored(List<DownloadTask> tasks) async {
    if (!_policy().autoRetry) {
      _syncQueueState();
      return;
    }
    for (final task in tasks.where((t) => t.status == DownloadStatus.paused)) {
      await _enqueueTask(
        task.id,
        auto: true,
        requiresConnection: task.isOfflineCache && _policy().wifiOnly,
      );
    }
    _syncQueueState();
  }

  Future<void> _touchAccess(DownloadTask task) async {
    final last = task.lastAccessedAt;
    if (last != null &&
        DateTime.now().difference(last) < kCacheAccessTouchInterval) {
      return;
    }
    _replaceTask(task.copyWith(lastAccessedAt: () => DateTime.now()));
  }

  DownloadTask? _taskById(String taskId) =>
      state.tasks.where((t) => t.id == taskId).firstOrNull;

  void _replaceTask(DownloadTask task) {
    final tasks = List<DownloadTask>.from(state.tasks);
    final index = tasks.indexWhere((t) => t.id == task.id);
    if (index == -1) return;
    tasks[index] = task;
    _setTasks(tasks);
  }

  void _syncQueueState() {
    if (!mounted) return;
    final policy = _policy();
    String? reason;
    if (policy.offlineMode && state.waitingOfflineCacheTasks.isNotEmpty) {
      reason = '离线模式已开启，缓存任务不会自动开始';
    } else if (_scheduler.isPaused) {
      reason = '下载队列已暂停';
    } else if (_scheduler.heldIds.isNotEmpty) {
      reason = '已开启「仅 Wi-Fi 下载」，等待 Wi-Fi 连接';
    }
    state = state.copyWith(
      queuePaused: _scheduler.isPaused,
      queueBlockedReason: reason,
    );
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
    return DownloadNotifier(
      policy: () => ref.read(offlineCacheSettingsProvider).toQueuePolicy(),
    );
  },
);
