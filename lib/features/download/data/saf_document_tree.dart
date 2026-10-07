import 'package:flutter/services.dart';

import 'saf_tree_store.dart';

/// Result of copying one file into a SAF tree.
class SafCopyResult {
  /// Bytes actually present in the destination.
  final int bytes;

  /// The destination document URI.
  final String uri;

  /// The name the provider actually gave the document.
  ///
  /// Providers may adjust the display name, so the caller must persist *this*
  /// name rather than the one it asked for.
  final String displayName;

  const SafCopyResult({
    required this.bytes,
    required this.uri,
    required this.displayName,
  });

  @override
  String toString() => 'SafCopyResult($displayName, $bytes bytes)';
}

/// The platform error codes `SafDocumentTreeController.kt` reports.
///
/// Kept as constants (not raw strings) so a typo cannot silently downgrade a
/// "the user must re-pick the folder" case into a generic failure.
class SafErrorCodes {
  static const persistFailed = 'PERSIST_FAILED';
  static const pickerBusy = 'PICKER_BUSY';
  static const pickerFailed = 'PICKER_FAILED';
  static const permissionLost = 'PERMISSION_LOST';
  static const treeUnavailable = 'TREE_UNAVAILABLE';
  static const invalidArgs = 'INVALID_ARGS';
  static const sourceMissing = 'SOURCE_MISSING';
  static const nameConflict = 'NAME_CONFLICT';
  static const createDirFailed = 'CREATE_DIR_FAILED';
  static const createFailed = 'CREATE_FAILED';
  static const deleteFailed = 'DELETE_FAILED';
  static const openFailed = 'OPEN_FAILED';
  static const writeFailed = 'WRITE_FAILED';
  static const sizeMismatch = 'SIZE_MISMATCH';
  static const copyFailed = 'COPY_FAILED';

  /// Codes that mean "the saved grant is gone: the user has to pick the folder
  /// again". They must never be swallowed into a silent fallback.
  static const Set<String> permissionCodes = {
    persistFailed,
    permissionLost,
    treeUnavailable,
  };
}

/// A raw failure from the SAF channel, keeping the stable [code].
class SafDocumentTreeException implements Exception {
  final String code;
  final String message;

  const SafDocumentTreeException(this.code, this.message);

  /// True when the user must re-pick the folder.
  bool get isPermissionProblem => SafErrorCodes.permissionCodes.contains(code);

  @override
  String toString() => 'SafDocumentTreeException($code): $message';
}

/// SAF tree operations, as a seam so the writer can be tested with a fake.
abstract class SafDocumentTree {
  /// Opens `ACTION_OPEN_DOCUMENT_TREE` and takes a persistable grant.
  /// Returns null when the user cancelled.
  Future<SafTreeSelection?> pickDirectory();

  /// Whether the persisted grant for [treeUri] is still writable.
  Future<bool> isGranted(String treeUri);

  /// Drops the persisted grant.
  Future<bool> release(String treeUri);

  /// Streams `sourcePath` into `<treeUri>/<relativePath>/<fileName>`,
  /// overwriting an existing file, and returns what the provider wrote.
  Future<SafCopyResult> copyToTree({
    required String treeUri,
    required String relativePath,
    required String fileName,
    required String sourcePath,
  });

  /// Deletes a document previously created by [copyToTree].
  ///
  /// Needed because a SAF download is identified by a `content://` URI, which
  /// `File(...).delete()` cannot touch — without this, "删除下载文件" would
  /// silently report success and leave the file in the user's folder.
  Future<bool> deleteDocument(String documentUri);

  /// Opens the folder in a file manager. `FileOpener.openFolder` cannot do this
  /// for a `content://` tree.
  Future<bool> openTree(String treeUri);
}

/// [SafDocumentTree] over the `com.mconnect.mconnect/saf_tree` method channel.
class MethodChannelSafDocumentTree implements SafDocumentTree {
  MethodChannelSafDocumentTree({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'com.mconnect.mconnect/saf_tree';

  final MethodChannel _channel;

  @override
  Future<SafTreeSelection?> pickDirectory() async {
    final result = await _invoke<Map<Object?, Object?>>('pickDirectory');
    if (result == null) return null;
    final uri = result['uri']?.toString();
    if (uri == null || uri.isEmpty) return null;
    return SafTreeSelection(
      uri: uri,
      name: result['name']?.toString() ?? uri,
      grantedAt: DateTime.now(),
    );
  }

  @override
  Future<bool> isGranted(String treeUri) async =>
      await _invoke<bool>('isGranted', {'uri': treeUri}) ?? false;

  @override
  Future<bool> release(String treeUri) async =>
      await _invoke<bool>('release', {'uri': treeUri}) ?? false;

  @override
  Future<SafCopyResult> copyToTree({
    required String treeUri,
    required String relativePath,
    required String fileName,
    required String sourcePath,
  }) async {
    final result = await _invoke<Map<Object?, Object?>>('copyToTree', {
      'uri': treeUri,
      'relativePath': relativePath,
      'fileName': fileName,
      'sourcePath': sourcePath,
    });
    if (result == null) {
      throw const SafDocumentTreeException(
        SafErrorCodes.copyFailed,
        '写入自定义目录失败：平台没有返回结果',
      );
    }
    final bytes = result['bytes'];
    return SafCopyResult(
      bytes: bytes is int ? bytes : int.tryParse('$bytes') ?? 0,
      uri: result['uri']?.toString() ?? '',
      displayName: result['displayName']?.toString() ?? fileName,
    );
  }

  @override
  Future<bool> deleteDocument(String documentUri) async =>
      await _invoke<bool>('deleteDocument', {'uri': documentUri}) ?? false;

  @override
  Future<bool> openTree(String treeUri) async =>
      await _invoke<bool>('openTree', {'uri': treeUri}) ?? false;

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (error) {
      throw SafDocumentTreeException(
        error.code,
        error.message ?? 'SAF 操作失败（${error.code}）',
      );
    } on MissingPluginException {
      // Desktop / unit tests: the channel does not exist, which is not a crash
      // but "this platform has no SAF".
      throw const SafDocumentTreeException(
        SafErrorCodes.treeUnavailable,
        '当前平台不支持自定义目录（SAF）',
      );
    }
  }
}
