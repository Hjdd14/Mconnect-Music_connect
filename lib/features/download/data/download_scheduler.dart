import 'dart:async';
import 'dart:collection';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// How many downloads may run at the same time.
///
/// Declared here, next to the scheduler that enforces it (and read by
/// [DownloadManager], which enforces the same cap inside a single download), so
/// the number is a real tunable instead of an unused constant in
/// `AppConstants` — `maxConcurrentDownloads` used to live there and was read by
/// nobody.
const int kMaxConcurrentDownloads = 3;

/// Reports whether the current connection is one offline-cache traffic is
/// allowed on (Wi-Fi / Ethernet), used by the 仅 Wi-Fi 下载 switch.
///
/// Returns `true` only when we are **sure** the connection is unmetered.
typedef ConnectionCheck = Future<bool> Function();

/// The default [ConnectionCheck], backed by `connectivity_plus`.
///
/// Fails **open**: if the plugin cannot answer (not registered on this
/// platform, platform channel error), the queue is allowed to run. A download
/// that quietly never starts is a worse failure than one that runs on mobile
/// data, and the switch is still honoured whenever the plugin does answer.
Future<bool> defaultConnectionCheck() async {
  try {
    final results = await Connectivity().checkConnectivity();
    return results.any(
      (result) =>
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.ethernet ||
          result == ConnectivityResult.vpn,
    );
  } catch (error) {
    debugPrint('DownloadScheduler connectivity check failed: $error');
    return true;
  }
}

/// What happened to an enqueue request.
enum DownloadEnqueueOutcome {
  /// A slot was free; the task was handed to the starter.
  started,

  /// Queued behind the running downloads (FIFO).
  queued,

  /// Held back because the connection is not one the 仅 Wi-Fi 下载 switch
  /// allows. The task stays visible as `waiting` and is retried by
  /// [DownloadScheduler.recheckHeld].
  blockedNoConnection,

  /// The queue is paused; the task waits for [DownloadScheduler.resume].
  blockedQueuePaused,

  /// Held back because 离线模式 is on: the queue must not start network traffic
  /// on its own. Produced by the notifier (which owns the switches), not by the
  /// scheduler.
  blockedOfflineMode,

  /// The task was already queued or running.
  duplicate,
}

/// A real FIFO download queue with a concurrency cap and a pause switch.
///
/// This is the piece that did not exist before: `cacheSongs` created `waiting`
/// tasks and never called [DownloadManager.download], so offline-cache rows sat
/// in the list forever ("离线缓存死队列").
///
/// The scheduler owns *when* a task starts; the notifier owns *what* starting
/// means and all task state. It never touches the network itself, which keeps
/// it trivially testable.
class DownloadScheduler {
  DownloadScheduler({
    required this.onStart,
    this.maxConcurrent = kMaxConcurrentDownloads,
    ConnectionCheck? connectionCheck,
  }) : _connectionCheck = connectionCheck ?? defaultConnectionCheck;

  /// Called when a task may start downloading.
  final void Function(String taskId) onStart;

  /// Upper bound on simultaneously running downloads.
  final int maxConcurrent;

  final ConnectionCheck _connectionCheck;
  final Queue<String> _pending = Queue<String>();
  final Set<String> _active = <String>{};
  final Set<String> _held = <String>{};
  bool _paused = false;
  bool _pumping = false;

  bool get isPaused => _paused;

  int get activeCount => _active.length;

  /// Queued and waiting for a free slot, in FIFO order.
  List<String> get pendingIds => List<String>.unmodifiable(_pending);

  /// Waiting for an allowed connection (仅 Wi-Fi 下载).
  List<String> get heldIds => List<String>.unmodifiable(_held);

  bool isActive(String taskId) => _active.contains(taskId);

  bool isQueued(String taskId) =>
      _pending.contains(taskId) || _held.contains(taskId);

  /// Adds [taskId] to the queue.
  ///
  /// [requiresConnection] is true for tasks the *app* decided to run on its own
  /// (offline-cache queue) while 仅 Wi-Fi 下载 is on. A download the user pressed
  /// "下载" on passes `false`: the switch is labelled "移动网络下不自动执行缓存
  /// 任务", so it must not veto an explicit tap.
  Future<DownloadEnqueueOutcome> enqueue(
    String taskId, {
    bool requiresConnection = false,
  }) async {
    if (_active.contains(taskId) || _pending.contains(taskId)) {
      return DownloadEnqueueOutcome.duplicate;
    }
    if (_held.contains(taskId)) {
      if (requiresConnection) return DownloadEnqueueOutcome.blockedNoConnection;
      _held.remove(taskId);
    }

    if (requiresConnection && !await _connectionCheck()) {
      _held.add(taskId);
      return DownloadEnqueueOutcome.blockedNoConnection;
    }

    _pending.add(taskId);
    if (_paused) return DownloadEnqueueOutcome.blockedQueuePaused;

    await _pump();
    return _active.contains(taskId)
        ? DownloadEnqueueOutcome.started
        : DownloadEnqueueOutcome.queued;
  }

  /// Re-checks everything held by the connection gate; call this when
  /// connectivity changes (e.g. mobile → Wi-Fi).
  Future<int> recheckHeld() async {
    if (_held.isEmpty) return 0;
    if (!await _connectionCheck()) return 0;
    final waiting = List<String>.from(_held);
    _held.clear();
    for (final taskId in waiting) {
      _pending.add(taskId);
    }
    await _pump();
    return waiting.length;
  }

  /// Marks [taskId] as finished (completed, failed or paused) and frees its
  /// slot.
  void complete(String taskId) {
    _active.remove(taskId);
    _pending.remove(taskId);
    unawaited(_pump());
  }

  /// Removes [taskId] from every stage without starting anything.
  void remove(String taskId) {
    _active.remove(taskId);
    _pending.remove(taskId);
    _held.remove(taskId);
  }

  /// Stops the queue from starting anything new. Running downloads are not
  /// interrupted — the caller pauses those explicitly.
  void pause() {
    _paused = true;
  }

  /// Restarts the queue and pumps it.
  Future<void> resume() async {
    _paused = false;
    await _pump();
  }

  void dispose() {
    _pending.clear();
    _held.clear();
    _active.clear();
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (!_paused && _active.length < maxConcurrent && _pending.isNotEmpty) {
        final taskId = _pending.removeFirst();
        _active.add(taskId);
        onStart(taskId);
      }
    } finally {
      _pumping = false;
    }
  }
}
