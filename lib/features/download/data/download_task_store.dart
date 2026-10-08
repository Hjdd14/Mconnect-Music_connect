import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../domain/entities/download_task.dart';

/// Storage for the download list.
///
/// **Keep this interface at two methods.** Every test double in the suite
/// declares `implements DownloadTaskStore`, so one extra member stops all of
/// them from compiling at once. That constraint is why "write only the rows that
/// changed" lives *inside* [HiveDownloadTaskStore.save] as a diff rather than as
/// a `saveChanged` method added here. If a second implementation ever genuinely
/// needs a new capability, put it behind its own separate interface and probe
/// for it with `is` at the call site — do not grow this one.
abstract class DownloadTaskStore {
  Future<List<DownloadTask>> load();
  Future<void> save(List<DownloadTask> tasks);
}

DownloadTaskStore defaultDownloadTaskStore() {
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return const NoopDownloadTaskStore();
  }
  return HiveDownloadTaskStore();
}

class NoopDownloadTaskStore implements DownloadTaskStore {
  const NoopDownloadTaskStore();

  @override
  Future<List<DownloadTask>> load() async => const [];

  @override
  Future<void> save(List<DownloadTask> tasks) async {}
}

/// Hive-backed task storage that writes only the rows that changed.
///
/// Two properties, both needed by the download queue:
///
/// * Rows live under one key each (`task/<id>`), so a progress update writes one
///   small value instead of re-serializing the whole library into a single
///   `tasks` key — that was O(N²) JSON encoding per second with N concurrent
///   downloads.
/// * [save] compares each row against what it last wrote and skips the unchanged
///   ones, so even a caller that hands over the whole list (which is what
///   `DownloadTaskStore` allows) only touches the rows that moved.
///
/// The legacy `tasks` list is still maintained — an older build reads it after a
/// downgrade — but it is only rewritten when the *set or order* of rows changes.
/// A progress tick therefore never re-serializes the library into it.
class HiveDownloadTaskStore implements DownloadTaskStore {
  static const _boxName = 'download_tasks';

  /// Legacy key holding the whole list in one value.
  static const legacyTasksKey = 'tasks';

  /// Per-row key prefix. Public so a test can inspect the box directly.
  static const taskKeyPrefix = 'task/';

  static String taskKey(String id) => '$taskKeyPrefix$id';

  /// Signature of what was last written per row, so an unchanged row can be
  /// skipped. Seeded by [load] for rows that already had their own key.
  final Map<String, String> _lastWritten = {};

  /// The row order [legacyTasksKey] currently holds, or null when unknown —
  /// a fresh process, or a library that only exists in the legacy list.
  List<String>? _legacyOrder;

  Future<Box?> _boxOrNull(String operation) {
    try {
      return Hive.openBox(_boxName)
          .then<Box?>((box) => box)
          .catchError((Object error) {
        debugPrint('DownloadTaskStore $operation failed: $error');
        return null;
      });
    } catch (error) {
      debugPrint('DownloadTaskStore $operation failed: $error');
      return Future<Box?>.value();
    }
  }

  @override
  Future<List<DownloadTask>> load() async {
    final box = await _boxOrNull('load');
    if (box == null) return const [];

    // Insertion order is what the list is rendered in: the legacy list first
    // (that is the order the user saw before the upgrade), then any row that
    // only exists under its own key.
    final order = <String>[];
    final byId = <String, DownloadTask>{};

    final legacy = box.get(legacyTasksKey);
    if (legacy is List) {
      for (final value in legacy) {
        final task = DownloadTask.fromJson(value);
        if (task == null || byId.containsKey(task.id)) continue;
        byId[task.id] = task;
        order.add(task.id);
      }
    }

    for (final key in box.keys) {
      if (key is! String || !key.startsWith(taskKeyPrefix)) continue;
      final task = DownloadTask.fromJson(box.get(key));
      if (task == null) continue;
      if (!byId.containsKey(task.id)) order.add(task.id);
      byId[task.id] = task;
      // Already stored under its own key, so the next save can skip it unless
      // something about it really changed.
      _lastWritten[task.id] = _signatureOf(task);
    }

    _legacyOrder = order;

    final ordered = <DownloadTask>[];
    for (final id in order) {
      final task = byId[id];
      if (task != null) ordered.add(task);
    }
    return ordered;
  }

  @override
  Future<void> save(List<DownloadTask> tasks) async {
    final box = await _boxOrNull('save');
    if (box == null) return;

    final ids = <String>[];
    for (final task in tasks) {
      ids.add(task.id);
      final signature = _signatureOf(task);
      if (_lastWritten[task.id] == signature) continue;
      await box.put(taskKey(task.id), task.toJson());
      _lastWritten[task.id] = signature;
    }

    // A row that was removed must not survive under its own key.
    final keep = ids.map(taskKey).toSet();
    for (final key in box.keys.toList()) {
      if (key is! String || !key.startsWith(taskKeyPrefix)) continue;
      if (keep.contains(key)) continue;
      await box.delete(key);
      _lastWritten.remove(key.substring(taskKeyPrefix.length));
    }

    // Only a change to the rows or their order has to reach the legacy list; a
    // progress update must not re-serialize the library into it.
    if (!_sameOrder(_legacyOrder, ids)) {
      await box.put(
        legacyTasksKey,
        tasks.map((task) => task.toJson()).toList(),
      );
      _legacyOrder = ids;
    }
  }

  /// A cheap signature of every field [DownloadTask.toJson] persists.
  ///
  /// Deliberately not `jsonEncode(task.toJson())`: encoding the nested `Song`
  /// (artists, album, available qualities) for every row is exactly the cost
  /// this change exists to remove. The `Song` contributes only its identity —
  /// it is fixed when the row is enqueued and `DownloadTask.copyWith` cannot
  /// change it, so nothing else about it can move.
  static String _signatureOf(DownloadTask task) {
    const field = '\u0001';
    final song = task.song;
    return [
      song.id,
      song.platform.name,
      song.name,
      song.artistNames,
      song.coverUrl,
      song.duration.inMilliseconds,
      song.album?.id,
      song.album?.name,
      song.album?.coverUrl,
      song.availableQualities.length,
      task.quality.name,
      task.status.name,
      task.progress,
      task.downloadedBytes,
      task.totalBytes,
      task.filePath,
      task.error,
      task.createdAt.toIso8601String(),
      task.completedAt?.toIso8601String(),
      task.isOfflineCache,
      task.failureKind?.name,
      task.lastAccessedAt?.toIso8601String(),
    ].join(field);
  }

  static bool _sameOrder(List<String>? before, List<String> after) {
    if (before == null || before.length != after.length) return false;
    for (var index = 0; index < after.length; index++) {
      if (before[index] != after[index]) return false;
    }
    return true;
  }
}
