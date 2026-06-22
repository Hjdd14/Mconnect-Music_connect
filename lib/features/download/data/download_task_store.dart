import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../domain/entities/download_task.dart';

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

class HiveDownloadTaskStore implements DownloadTaskStore {
  static const _boxName = 'download_tasks';
  static const _tasksKey = 'tasks';

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
    final raw = box?.get(_tasksKey);
    if (raw is! List) return const [];
    return raw.map(DownloadTask.fromJson).whereType<DownloadTask>().toList();
  }

  @override
  Future<void> save(List<DownloadTask> tasks) async {
    final box = await _boxOrNull('save');
    await box?.put(_tasksKey, tasks.map((task) => task.toJson()).toList());
  }
}
