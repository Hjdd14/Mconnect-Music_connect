import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/entities/download_failure.dart';
import 'saf_document_tree.dart';
import 'saf_tree_store.dart';

typedef SafStagingDirectoryProvider = Future<Directory> Function();

/// The staging directory downloads are written to before they are copied into
/// the user's SAF folder.
///
/// The existing download pipeline (Dio stream + `Range` + resumable
/// `openWrite`) is untouched: it keeps writing to a real filesystem path, just
/// inside the app's own cache, where scoped storage cannot refuse it. The copy
/// into the tree happens afterwards, from a complete and size-checked file.
Future<Directory> defaultSafStagingDirectory() async {
  final temp = await getTemporaryDirectory();
  return Directory(p.join(temp.path, 'download_staging'));
}

/// A SAF write that failed, carrying the classification the download queue
/// already understands.
class SafDownloadException implements Exception {
  final DownloadFailure failure;

  const SafDownloadException(this.failure);

  DownloadFailureKind get kind => failure.kind;
  bool get needsFolderRepick => failure.kind == DownloadFailureKind.storagePermission;

  @override
  String toString() => 'SafDownloadException(${failure.kind.name}): ${failure.message}';
}

/// What a successful commit produced.
class SafWriteResult {
  /// Where the file ended up (the SAF document URI).
  final String documentUri;

  /// The name the provider actually used for the document.
  final String displayName;

  final int bytes;

  /// True when the staging file was removed after the copy.
  final bool stagingRemoved;

  const SafWriteResult({
    required this.documentUri,
    required this.displayName,
    required this.bytes,
    required this.stagingRemoved,
  });

  @override
  String toString() =>
      'SafWriteResult($displayName, $bytes bytes, stagingRemoved=$stagingRemoved)';
}

/// What the caller should do with a SAF-configured download folder.
///
/// Three states, not a bool, because "the user never chose a SAF folder" and
/// "the user chose one and its grant died" must be handled differently: the
/// first is normal (use the default directory), the second **must be told to
/// the user** — silently falling back is how a download ends up in a folder
/// nobody looks at.
enum SafTargetState {
  /// No SAF folder was ever chosen.
  notConfigured,

  /// A SAF folder is configured and still writable.
  ready,

  /// A SAF folder is configured but the persisted grant is gone.
  permissionLost,
}

/// Copies a finished download into the user's SAF folder.
///
/// Responsibilities kept here, and deliberately **not** spread into the
/// download queue:
/// * the grant is checked *before* copying, so a revoked folder is reported
///   instead of producing a half-written file;
/// * the copy is size-verified — a provider that stops accepting bytes (quota,
///   revoked grant) must not leave a truncated song in the library;
/// * a failed copy **keeps** the staging file, so a retry can re-copy without
///   downloading the track again;
/// * a successful copy deletes it.
class SafDownloadWriter {
  SafDownloadWriter({
    SafDocumentTree? tree,
    SafTreeStore? store,
    SafStagingDirectoryProvider? stagingDirectoryProvider,
  }) : tree = tree ?? MethodChannelSafDocumentTree(),
       store = store ?? HiveSafTreeStore(),
       _stagingDirectoryProvider =
           stagingDirectoryProvider ?? defaultSafStagingDirectory;

  final SafDocumentTree tree;
  final SafTreeStore store;
  final SafStagingDirectoryProvider _stagingDirectoryProvider;

  /// The folder downloads are staged in (created on demand).
  Future<Directory> stagingDirectory() async {
    final directory = await _stagingDirectoryProvider();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  /// Decides what a download that targets the SAF folder should do.
  ///
  /// Call this **before** starting the transfer: it is the difference between
  /// "write into the user's folder" and "fall back to the default folder and
  /// say so".
  Future<SafTargetState> targetState() async {
    final selection = await store.read();
    if (selection == null) return SafTargetState.notConfigured;
    try {
      final granted = await tree.isGranted(selection.uri);
      return granted ? SafTargetState.ready : SafTargetState.permissionLost;
    } on SafDocumentTreeException {
      // A platform that cannot answer (no SAF at all) is indistinguishable from
      // a lost grant for the caller's purposes: it must fall back and explain.
      return SafTargetState.permissionLost;
    }
  }

  /// Convenience for callers that only need "can I write into the tree?".
  ///
  /// Prefer [targetState] when the UI has to explain the fallback.
  Future<bool> isReady() async =>
      await targetState() == SafTargetState.ready;

  /// Opens the folder picker and persists the grant. Returns null when the user
  /// cancelled.
  Future<SafTreeSelection?> pickDirectory() async {
    try {
      final selection = await tree.pickDirectory();
      if (selection == null) return null;
      await store.save(selection);
      return selection;
    } on SafDocumentTreeException catch (error) {
      throw SafDownloadException(_failureFor(error));
    }
  }

  /// Forgets the SAF folder (e.g. the user switched back to the default one).
  Future<void> clear() async {
    final selection = await store.read();
    if (selection != null) {
      await tree.release(selection.uri);
    }
    await store.clear();
  }

  /// Copies [stagingFile] to `<tree>/<relativePath>/<fileName>`.
  ///
  /// Throws [SafDownloadException] with a classified [DownloadFailure] when the
  /// copy cannot be completed; the staging file is left in place.
  Future<SafWriteResult> commit({
    required File stagingFile,
    required String relativePath,
    required String fileName,
  }) async {
    final selection = await store.read();
    if (selection == null) {
      throw SafDownloadException(
        const DownloadFailure(
          kind: DownloadFailureKind.storagePermission,
          message: '尚未选择自定义下载目录',
        ),
      );
    }

    if (!await stagingFile.exists()) {
      throw SafDownloadException(
        DownloadFailure(
          kind: DownloadFailureKind.unknown,
          message: '下载的临时文件不存在，请重新下载',
          detail: stagingFile.path,
        ),
      );
    }

    // Checked before copying: a revoked grant is the one case the user must act
    // on, so it becomes its own message instead of a generic write error.
    if (!await tree.isGranted(selection.uri)) {
      throw SafDownloadException(
        const DownloadFailure(
          kind: DownloadFailureKind.storagePermission,
          message: '自定义目录的访问权限已失效，请在下载设置中重新选择目录',
        ),
      );
    }

    final SafCopyResult copied;
    try {
      copied = await tree.copyToTree(
        treeUri: selection.uri,
        relativePath: relativePath,
        fileName: fileName,
        sourcePath: stagingFile.path,
      );
    } on SafDocumentTreeException catch (error) {
      throw SafDownloadException(_failureFor(error));
    }

    final expected = await stagingFile.length();
    if (copied.bytes != expected) {
      // The platform deletes a mismatched document itself; the staging file
      // stays so a retry does not have to re-download.
      throw SafDownloadException(
        DownloadFailure(
          kind: DownloadFailureKind.disk,
          message: '写入自定义目录时字节数不符，请重试',
          detail: 'expected=$expected actual=${copied.bytes}',
        ),
      );
    }

    var stagingRemoved = false;
    try {
      await stagingFile.delete();
      stagingRemoved = true;
    } catch (_) {
      // A leftover staging file is not a download failure: the song is in the
      // user's folder. It is reported through `stagingRemoved` instead.
    }

    return SafWriteResult(
      documentUri: copied.uri,
      displayName: copied.displayName,
      bytes: copied.bytes,
      stagingRemoved: stagingRemoved,
    );
  }

  /// Opens the chosen folder in a file manager, if the platform can.
  Future<bool> openDirectory() async {
    final selection = await store.read();
    if (selection == null) return false;
    try {
      return await tree.openTree(selection.uri);
    } on SafDocumentTreeException {
      return false;
    }
  }

  static DownloadFailure _failureFor(SafDocumentTreeException error) {
    final kind = switch (error.code) {
      SafErrorCodes.treeUnavailable ||
      SafErrorCodes.permissionLost ||
      SafErrorCodes.persistFailed => DownloadFailureKind.storagePermission,
      // A provider that ran out of room mid-copy reports it through the write
      // path; the copy is retryable and the staging file is still intact.
      SafErrorCodes.sizeMismatch ||
      SafErrorCodes.writeFailed ||
      SafErrorCodes.copyFailed => DownloadFailureKind.disk,
      _ => DownloadFailureKind.unknown,
    };
    return DownloadFailure(
      kind: kind,
      message: switch (kind) {
        DownloadFailureKind.storagePermission =>
          error.code == SafErrorCodes.persistFailed
              ? '无法长期保留该目录的访问权限，请换一个目录'
              : '自定义目录的访问权限已失效，请在下载设置中重新选择目录',
        DownloadFailureKind.disk => '写入自定义目录失败，请重试',
        _ => '写入自定义目录失败：${error.message}',
      },
      detail: '${error.code}: ${error.message}',
    );
  }
}
