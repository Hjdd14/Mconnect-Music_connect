import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../platform/base/platform_registry.dart';
import '../download_directory_service.dart';
import '../../domain/entities/download_task.dart';

class DownloadManager {
  final Dio _dio;
  final DownloadDirectoryService _directoryService;
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, DateTime> _lastProgressUpdates = {};
  final int maxConcurrent;
  int _activeDownloads = 0;

  DownloadManager({
    Dio? dio,
    DownloadDirectoryService? directoryService,
    this.maxConcurrent = 3,
  }) : _directoryService = directoryService ?? DownloadDirectoryService(),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 30),
               receiveTimeout: const Duration(minutes: 10),
             ),
           );

  DownloadDirectoryService get directoryService => _directoryService;

  Future<Directory> currentRootDirectory() =>
      _directoryService.currentRootDirectory();

  Future<bool> setCustomRootDirectory(String path) =>
      _directoryService.setCustomRootDirectory(path);

  Future<void> resetCustomRootDirectory() =>
      _directoryService.resetCustomRootDirectory();

  Future<bool> deleteDownloadedFile(DownloadTask task) async {
    final filePath = task.filePath;
    if (filePath == null || filePath.trim().isEmpty) return true;
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Download a song. Returns a stream of progress updates.
  Stream<DownloadProgress> download(DownloadTask task) async* {
    final controller = StreamController<DownloadProgress>();

    _startDownload(task, controller);

    yield* controller.stream;
  }

  Future<void> _startDownload(
    DownloadTask task,
    StreamController<DownloadProgress> controller,
  ) async {
    // Wait for a slot if at max concurrent
    while (_activeDownloads >= maxConcurrent) {
      if (controller.isClosed) return;
      await Future.delayed(const Duration(milliseconds: 200));
    }

    _activeDownloads++;
    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;

    try {
      // Check storage permission
      if (Platform.isAndroid) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          _emitError(controller, task, '存储权限被拒绝');
          return;
        }
      }

      // Get download URL
      final platform = PlatformRegistry.get(task.song.platform);
      final url = await platform.getSongUrl(
        task.song.id,
        quality: task.quality,
      );

      // Get download directory
      final dir = await _directoryService.targetDirectory(
        task.song.platform,
        task.quality,
      );
      final filePath = '${dir.path}/${task.fileName}';

      // Always download from scratch (Dio.download overwrites, doesn't append)
      final file = File(filePath);

      final response = await _dio.download(
        url,
        filePath,
        cancelToken: cancelToken,
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            // Throttle progress updates to max 1 per second
            final now = DateTime.now();
            final last = _lastProgressUpdates[task.id];
            if (last != null && now.difference(last).inMilliseconds < 1000) {
              return;
            }
            _lastProgressUpdates[task.id] = now;
            final progress = received / total;
            controller.add(
              DownloadProgress(
                taskId: task.id,
                downloadedBytes: received,
                totalBytes: total,
                progress: progress,
              ),
            );
          }
        },
      );

      if (response.statusCode == 200) {
        controller.add(
          DownloadProgress(
            taskId: task.id,
            downloadedBytes: await file.length(),
            totalBytes: await file.length(),
            progress: 1.0,
            completed: true,
            filePath: filePath,
          ),
        );
      } else {
        _emitError(controller, task, '下载失败: HTTP ${response.statusCode}');
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        controller.add(
          DownloadProgress(
            taskId: task.id,
            downloadedBytes: 0,
            totalBytes: 0,
            progress: 0,
            paused: true,
          ),
        );
      } else {
        _emitError(controller, task, '下载错误: ${e.message}');
      }
    } catch (e) {
      _emitError(controller, task, '下载错误: ${e.toString()}');
    } finally {
      _activeDownloads--;
      _cancelTokens.remove(task.id);
      _lastProgressUpdates.remove(task.id);
      await controller.close();
    }
  }

  void _emitError(
    StreamController<DownloadProgress> controller,
    DownloadTask task,
    String error,
  ) {
    controller.add(
      DownloadProgress(
        taskId: task.id,
        downloadedBytes: 0,
        totalBytes: 0,
        progress: 0,
        error: error,
      ),
    );
  }

  void pause(String taskId) {
    _cancelTokens[taskId]?.cancel('paused');
  }

  void cancel(String taskId) {
    _cancelTokens[taskId]?.cancel('cancelled');
  }

  void dispose() {
    for (final token in _cancelTokens.values) {
      token.cancel('disposed');
    }
    _cancelTokens.clear();
  }
}

class DownloadProgress {
  final String taskId;
  final int downloadedBytes;
  final int totalBytes;
  final double progress;
  final bool completed;
  final bool paused;
  final String? filePath;
  final String? error;

  const DownloadProgress({
    required this.taskId,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.progress,
    this.completed = false,
    this.paused = false,
    this.filePath,
    this.error,
  });
}
