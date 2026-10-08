import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../platform/base/platform_registry.dart';
import '../download_directory_service.dart';
import '../saf_download_writer.dart';
import '../../domain/entities/download_failure.dart';
import '../../domain/entities/download_task.dart';
import '../download_scheduler.dart' show kMaxConcurrentDownloads;

/// Best-effort free-space probe: bytes available on the volume holding [path],
/// or `null` when this build cannot measure it.
typedef FreeSpaceProbe = Future<int?> Function(String path);

/// Extra headroom required before a download starts, so a file that exactly
/// fills the volume does not leave the app unable to write its own state.
const int kDownloadFreeSpaceReserveBytes = 32 * 1024 * 1024;

/// The default [FreeSpaceProbe].
///
/// `dart:io` exposes no free-space API and this project has no dependency that
/// does (adding one would touch `pubspec.yaml`), so the probe shells out to the
/// POSIX `df` that ships with Android/Linux/macOS and reads its POSIX (`-P`)
/// output. On Windows it returns `null` — a Windows desktop download is not
/// pre-flight gated, but a full disk is still reported as
/// [DownloadFailureKind.disk] when the write itself fails.
Future<int?> defaultFreeSpaceProbe(String path) async {
  if (Platform.isWindows) return null;
  try {
    final result = await Process.run('df', ['-P', '-k', path]);
    if (result.exitCode != 0) return null;
    final lines = (result.stdout as String)
        .trim()
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.length < 2) return null;
    final columns = lines.last.trim().split(RegExp(r'\s+'));
    if (columns.length < 4) return null;
    final availableKb = int.tryParse(columns[3]);
    if (availableKb == null || availableKb < 0) return null;
    return availableKb * 1024;
  } catch (_) {
    return null;
  }
}

class DownloadManager {
  final Dio _dio;
  final DownloadDirectoryService _directoryService;
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, DateTime> _lastProgressUpdates = {};
  final int maxConcurrent;
  final FreeSpaceProbe _freeSpaceProbe;
  final _DownloadSemaphore _slots;
  int _activeDownloads = 0;

  DownloadManager({
    Dio? dio,
    DownloadDirectoryService? directoryService,
    this.safWriter,
    int maxConcurrent = kMaxConcurrentDownloads,
    FreeSpaceProbe? freeSpaceProbe,
  }) : maxConcurrent = maxConcurrent,
       _slots = _DownloadSemaphore(maxConcurrent),
       _freeSpaceProbe = freeSpaceProbe ?? defaultFreeSpaceProbe,
       _directoryService = directoryService ?? DownloadDirectoryService(),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 30),
               receiveTimeout: const Duration(minutes: 10),
             ),
           );

  /// Overrides the SAF writer. By default the directory service's own writer is
  /// used, so injecting a service built on a fake tree is enough.
  final SafDownloadWriter? safWriter;

  SafDownloadWriter get _safWriter => safWriter ?? _directoryService.safWriter;

  DownloadDirectoryService get directoryService => _directoryService;

  /// Number of downloads this manager is currently running. Used by tests and
  /// diagnostics; the scheduler keeps the queue itself.
  int get activeDownloads => _activeDownloads;

  Future<Directory> currentRootDirectory() =>
      _directoryService.currentRootDirectory();

  Future<bool> setCustomRootDirectory(String path) =>
      _directoryService.setCustomRootDirectory(path);

  Future<void> resetCustomRootDirectory() =>
      _directoryService.resetCustomRootDirectory();

  Future<bool> deleteDownloadedFile(DownloadTask task) async {
    final filePath = task.filePath;
    if (filePath == null || filePath.trim().isEmpty) return true;
    // A file that lives in the user's SAF folder is identified by a
    // `content://` URI. `File(uri).exists()` is false, so the plain path below
    // would report "deleted" while leaving the song in their folder.
    if (isDocumentUri(filePath)) {
      return _safWriter.deleteDocument(filePath);
    }
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

  /// True for a `content://` (or `file://`) document URI, i.e. a file that was
  /// published into a SAF folder rather than written to a plain path.
  static bool isDocumentUri(String path) => isSafDocumentUri(path);

  /// Size of a task's file on disk, or 0 when it is missing.
  Future<int> partialBytesOf(DownloadTask task) async {
    final path = await _resolveFilePath(task);
    if (path == null) return 0;
    return _lengthOrZero(File(path));
  }

  /// Deletes a half-written file.
  ///
  /// Partial files are deliberately kept after a failure or a pause (that is
  /// what makes the next attempt a resume), but a download the user *cancelled*
  /// must not leave an orphan behind — and a later re-download of the same song
  /// would otherwise silently resume from it.
  Future<void> discardPartialFile(DownloadTask task) async {
    try {
      final path = await _resolveFilePath(task);
      if (path == null) return;
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (error) {
      debugPrint('discardPartialFile failed: $error');
    }
  }

  /// Where [task] is (or would be) written: the recorded path, else the path
  /// derived from the download directory layout.
  ///
  /// A SAF task's *partial* bytes live in the staging directory even though its
  /// published file is a document URI, so resolution goes through the same
  /// destination switch the transfer uses — otherwise a paused SAF download
  /// would report its progress from a path nothing ever wrote to.
  Future<String?> _resolveFilePath(DownloadTask task) async {
    final recorded = task.filePath;
    if (recorded != null &&
        recorded.trim().isNotEmpty &&
        !isDocumentUri(recorded)) {
      return recorded;
    }
    try {
      final destination = await _directoryService.resolveDownloadDestination(
        task.song.platform,
        task.quality,
        create: false,
      );
      return switch (destination) {
        FileSystemDownloadDestination(:final directory) =>
          '${directory.path}/${task.fileName}',
        SafDownloadDestination(:final stagingDirectory) =>
          '${stagingDirectory.path}/${task.fileName}',
        UnusableDownloadDestination() => null,
      };
    } catch (_) {
      return null;
    }
  }

  /// Download a song. Returns a stream of progress updates.
  Stream<DownloadProgress> download(DownloadTask task) async* {
    final controller = StreamController<DownloadProgress>();

    // Fire-and-forget on purpose: the body feeds `controller`, and the caller
    // consumes it through the returned stream. `await`ing it here would deadlock
    // (nothing drains the controller until this method returns).
    unawaited(_startDownload(task, controller));

    yield* controller.stream;
  }

  Future<void> _startDownload(
    DownloadTask task,
    StreamController<DownloadProgress> controller,
  ) async {
    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;

    // A real semaphore instead of the old
    // `while (_activeDownloads >= maxConcurrent) await Future.delayed(200ms)`:
    // that spun one timer per waiting download, wasted up to 200 ms of latency
    // on every slot hand-off, and could not be cancelled while it waited.
    await _slots.acquire();

    String? filePath;
    // Set only while a download targets the user's SAF folder: the transfer
    // writes into staging exactly as before, and the file is moved into the
    // tree once it is complete and size-checked.
    SafDownloadDestination? safTarget;
    try {
      if (controller.isClosed || cancelToken.isCancelled) return;

      _activeDownloads++;

      // Where the bytes go is resolved BEFORE the network is touched. A SAF
      // folder whose grant has been revoked has to fail here, with a reason the
      // user can act on — falling back to the app sandbox would put the file
      // somewhere they will never look.
      final destination = await _directoryService.resolveDownloadDestination(
        task.song.platform,
        task.quality,
      );
      final Directory dir;
      switch (destination) {
        case UnusableDownloadDestination(:final failure):
          _emitFailure(controller, task, failure);
          return;
        case SafDownloadDestination():
          dir = destination.stagingDirectory;
          safTarget = destination;
        case FileSystemDownloadDestination():
          dir = destination.directory;
      }
      filePath =
          await _recordedPathOrNull(task) ?? '${dir.path}/${task.fileName}';

      // Get download URL (throws typed ApiExceptions since Wave 1).
      final platform = PlatformRegistry.get(task.song.platform);
      final url = await platform.getSongUrl(
        task.song.id,
        quality: task.quality,
      );

      // Android storage permission: only when the target really is outside the
      // app sandbox. The old code asked unconditionally, and `Permission.storage`
      // has been a no-op (immediately denied) on API 33+ — so on a modern phone
      // every single download failed with "存储权限被拒绝" even though the default
      // target directory needs no permission at all.
      //
      // Skipped entirely for a SAF target: staging lives in the app's own cache,
      // which needs no permission — the user's folder is reached through the
      // persisted tree grant instead.
      if (safTarget == null &&
          Platform.isAndroid &&
          await _directoryService.needsLegacyStoragePermission(dir)) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          _emitFailure(
            controller,
            task,
            const DownloadFailure(
              kind: DownloadFailureKind.storagePermission,
              message: '存储权限被拒绝，请在系统设置中授权',
            ),
          );
          return;
        }
      }

      final file = File(filePath);
      final resumeFrom = await _resumeOffset(file, task);

      final response = await _dio.get<ResponseBody>(
        url,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          headers: resumeFrom > 0
              ? {'Range': 'bytes=$resumeFrom-'}
              : null,
        ),
      );

      final statusCode = response.statusCode ?? 0;
      if (statusCode != 200 && statusCode != 206) {
        _emitFailure(controller, task, DownloadFailure.fromStatus(statusCode));
        return;
      }

      final body = response.data;
      if (body == null) {
        _emitFailure(
          controller,
          task,
          const DownloadFailure(
            kind: DownloadFailureKind.network,
            message: '下载失败：服务器没有返回内容',
          ),
        );
        return;
      }

      // 206 means the server honoured our Range request; 200 means it ignored it
      // and the whole body is coming, so the partial file must be replaced.
      final resuming = statusCode == 206 && resumeFrom > 0;
      final startOffset = resuming ? resumeFrom : 0;
      final declaredLength = _declaredLength(response.headers);
      final expectedTotal = declaredLength == null
          ? null
          : declaredLength + startOffset;

      // Pre-flight disk check. `null` from the probe means "unknown" — never
      // treated as "plenty of room", it just skips the gate.
      //
      // Deliberate limitation (approved for v1.4.1): the probe measures the
      // volume holding `dir.path`, which for a SAF target is the app's staging
      // area — not the user's folder, which may be another volume. Filling the
      // target volume is therefore reported later, by the copy itself:
      // `SafDownloadWriter` classifies it as `disk` (retryable) and keeps the
      // staging file, so the retry does not have to download again.
      final expectedBytes = expectedTotal ?? task.totalBytes;
      if (expectedBytes != null && expectedBytes > 0) {
        final free = await _freeSpaceProbe(dir.path);
        if (free != null &&
            free < expectedBytes + kDownloadFreeSpaceReserveBytes) {
          _emitFailure(
            controller,
            task,
            DownloadFailure.storageFull(
              '可用 ${free ~/ (1024 * 1024)} MB，需要 '
              '${(expectedBytes + kDownloadFreeSpaceReserveBytes) ~/ (1024 * 1024)} MB',
            ),
          );
          return;
        }
      }

      // Partial files are KEPT on failure/cancel: that is what makes the next
      // attempt a resume instead of a restart from byte 0.
      final sink = file.openWrite(
        mode: resuming ? FileMode.append : FileMode.write,
      );
      var received = startOffset;
      try {
        await for (final chunk in body.stream) {
          if (cancelToken.isCancelled) {
            throw DioException(
              requestOptions: response.requestOptions,
              type: DioExceptionType.cancel,
            );
          }
          sink.add(chunk);
          received += chunk.length;
          _reportProgress(
            controller,
            task,
            received: received,
            total: expectedTotal ?? task.totalBytes ?? -1,
          );
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      final onDisk = await file.length();
      if (onDisk == 0) {
        _emitFailure(
          controller,
          task,
          const DownloadFailure(
            kind: DownloadFailureKind.network,
            message: '下载失败：没有收到任何数据',
          ),
        );
        return;
      }
      // Size validation: a truncated transfer used to be reported as a success
      // (it only trusted `statusCode == 200`), leaving a half-written file the
      // player could not open.
      if (expectedTotal != null && onDisk != expectedTotal) {
        _emitFailure(
          controller,
          task,
          DownloadFailure(
            kind: DownloadFailureKind.network,
            message: '下载不完整（$onDisk / $expectedTotal 字节），可重试续传',
            detail: 'size mismatch',
          ),
          filePath: filePath,
          downloadedBytes: onDisk,
        );
        return;
      }

      // The bytes are complete and verified, so now — and only now — move them
      // into the user's folder. Until this point the download is a normal
      // resumable file in staging; if the copy fails, the staging file is kept
      // (see SafDownloadWriter.commit) so a retry does not re-download.
      var completedPath = filePath;
      var completedBytes = onDisk;
      if (safTarget != null) {
        try {
          final outcome = await _safWriter.commit(
            stagingFile: file,
            relativePath: safTarget.relativePath,
            fileName: task.fileName,
          );
          // The provider may have renamed the document; the URI it returned is
          // the only identity that is correct for "delete"/"open folder" later,
          // so that is what the task must record.
          completedPath = outcome.documentUri;
          completedBytes = outcome.bytes;
        } on SafDownloadException catch (error) {
          _emitFailure(
            controller,
            task,
            error.failure,
            filePath: filePath,
            downloadedBytes: onDisk,
          );
          return;
        }
      }

      controller.add(
        DownloadProgress(
          taskId: task.id,
          downloadedBytes: completedBytes,
          totalBytes: completedBytes,
          progress: 1.0,
          completed: true,
          filePath: completedPath,
        ),
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel || cancelToken.isCancelled) {
        final onDisk = filePath == null
            ? 0
            : await _lengthOrZero(File(filePath));
        controller.add(
          DownloadProgress(
            taskId: task.id,
            downloadedBytes: onDisk,
            totalBytes: task.totalBytes ?? onDisk,
            progress: task.totalBytes == null || task.totalBytes == 0
                ? 0
                : (onDisk / task.totalBytes!).clamp(0, 1).toDouble(),
            paused: true,
            filePath: filePath,
          ),
        );
      } else {
        _emitFailure(
          controller,
          task,
          DownloadFailure.from(e, platformName: task.song.platform.displayName),
          filePath: filePath,
          downloadedBytes: filePath == null
              ? 0
              : await _lengthOrZero(File(filePath)),
        );
      }
    } on Object catch (e) {
      _emitFailure(
        controller,
        task,
        _classifyIoFailure(e, platformName: task.song.platform.displayName),
        filePath: filePath,
        downloadedBytes: filePath == null
            ? 0
            : await _lengthOrZero(File(filePath)),
      );
    } finally {
      _activeDownloads--;
      _slots.release();
      _cancelTokens.remove(task.id);
      _lastProgressUpdates.remove(task.id);
      if (!controller.isClosed) await controller.close();
    }
  }

  /// How many bytes of [file] can be reused: its length when this task can
  /// account for exactly those bytes, otherwise 0 (start over).
  ///
  /// [DownloadTask.downloadedBytes] is the app's own record of what it wrote. The
  /// file has to be *exactly* that long; anything else means the bytes are not
  /// provably this task's — a file another task left behind (the pre-W0-C name
  /// collided across qualities), a file something else truncated or replaced, or
  /// a length no progress update ever saw. Appending onto those bytes produces a
  /// file that still passes the size check and plays as noise, so a mismatch
  /// restarts from byte 0 instead of resuming.
  ///
  /// Deliberate trade-off: a process killed without a pause/failure event can
  /// leave the file longer than the last recorded progress, and that attempt will
  /// restart. Correctness over re-downloaded bytes — the pause, failure, cancel
  /// and completion paths all persist the exact byte count, so a graceful stop
  /// still resumes.
  Future<int> _resumeOffset(File file, DownloadTask task) async {
    try {
      if (!await file.exists()) return 0;
      final existing = await file.length();
      if (existing <= 0) return 0;
      final expected = task.totalBytes;
      if (expected != null && existing >= expected) return 0;
      final recorded = task.downloadedBytes;
      if (recorded <= 0 || existing != recorded) return 0;
      return existing;
    } catch (_) {
      return 0;
    }
  }

  /// [DownloadTask.filePath] when it is a plain filesystem path whose file is
  /// still there, else null.
  ///
  /// Used to keep a task on the path it already recorded. Rows written before
  /// the file name carried the quality hold e.g. `歌手 - 歌名.mp3`; re-deriving
  /// the name would abandon a valid partial file, and for a completed row it
  /// would point away from the file the user actually has. A file the user
  /// deleted is not reused — the download falls back to the derived name.
  Future<String?> _recordedPathOrNull(DownloadTask task) async {
    final recorded = task.filePath;
    if (recorded == null ||
        recorded.trim().isEmpty ||
        isDocumentUri(recorded)) {
      return null;
    }
    try {
      return await File(recorded).exists() ? recorded : null;
    } catch (_) {
      return null;
    }
  }

  int? _declaredLength(Headers headers) {
    final raw = headers.value(Headers.contentLengthHeader);
    if (raw == null) return null;
    final value = int.tryParse(raw);
    if (value == null || value <= 0) return null;
    return value;
  }

  void _reportProgress(
    StreamController<DownloadProgress> controller,
    DownloadTask task, {
    required int received,
    required int total,
  }) {
    final now = DateTime.now();
    final last = _lastProgressUpdates[task.id];
    if (last != null && now.difference(last).inMilliseconds < 1000) return;
    _lastProgressUpdates[task.id] = now;
    controller.add(
      DownloadProgress(
        taskId: task.id,
        downloadedBytes: received,
        totalBytes: total < 0 ? 0 : total,
        progress: total <= 0 ? 0 : (received / total).clamp(0, 1).toDouble(),
      ),
    );
  }

  Future<int> _lengthOrZero(File file) async {
    try {
      return await file.exists() ? await file.length() : 0;
    } catch (_) {
      return 0;
    }
  }

  /// Turns a raw I/O error into a classified failure, so "disk full" and
  /// "permission denied" stop looking like network trouble.
  DownloadFailure _classifyIoFailure(Object error, {String? platformName}) {
    if (error is FileSystemException) {
      final code = error.osError?.errorCode;
      switch (code) {
        case 28: // ENOSPC
        case 112: // ERROR_DISK_FULL (Windows)
          return DownloadFailure.storageFull(error.message);
        case 13: // EACCES
        case 1: // EPERM
        case 5: // ERROR_ACCESS_DENIED (Windows)
          return const DownloadFailure(
            kind: DownloadFailureKind.storagePermission,
            message: '没有写入权限，请更换下载目录',
          );
      }
    }
    // A socket that died mid-body surfaces as a raw HttpException /
    // SocketException from the response stream, not as a DioException — without
    // this it landed in `unknown` and the retry switch refused to help.
    if (error is HttpException || error is SocketException) {
      return DownloadFailure.network(error.toString());
    }
    return DownloadFailure.from(error, platformName: platformName);
  }

  void _emitFailure(
    StreamController<DownloadProgress> controller,
    DownloadTask task,
    DownloadFailure failure, {
    String? filePath,
    int downloadedBytes = 0,
  }) {
    controller.add(
      DownloadProgress(
        taskId: task.id,
        downloadedBytes: downloadedBytes,
        totalBytes: task.totalBytes ?? 0,
        progress: task.totalBytes == null || task.totalBytes == 0
            ? 0
            : (downloadedBytes / task.totalBytes!).clamp(0, 1).toDouble(),
        failure: failure,
        error: failure.message,
        filePath: filePath,
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

/// A counting semaphore with a FIFO of waiters.
///
/// Replaces the busy-wait loop the manager used to use; waiters are woken in
/// arrival order and never spin.
class _DownloadSemaphore {
  _DownloadSemaphore(this.permits);

  final int permits;
  int _inUse = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  Future<void> acquire() {
    if (_inUse < permits) {
      _inUse++;
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      // Hand the permit straight to the next waiter instead of dropping the
      // count and racing every waiter for it.
      _waiters.removeFirst().complete();
      return;
    }
    if (_inUse > 0) _inUse--;
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

  /// Classified failure (Wave 2). When null and [error] is set, the failure
  /// could not be typed — treated as [DownloadFailureKind.unknown].
  final DownloadFailure? failure;

  const DownloadProgress({
    required this.taskId,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.progress,
    this.completed = false,
    this.paused = false,
    this.filePath,
    this.error,
    this.failure,
  });
}
