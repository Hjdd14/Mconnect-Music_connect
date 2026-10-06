import '../../../../core/network/api_exception.dart';
import '../../../../core/network/platform_http.dart';

/// Why a download stopped.
///
/// Before this existed every failure was a bare Chinese string
/// (`download_manager.dart` used to emit `'存储权限被拒绝'`, `'下载失败: HTTP $code'`,
/// `'下载错误: ${e.message}'`), so the queue could not tell "retry may help"
/// apart from "this will never work" — which is exactly what the 失败自动重试
/// switch needs to know.
enum DownloadFailureKind {
  /// No HTTP response at all: timeout, DNS, socket closed, TLS.
  network,

  /// The stored session is no longer usable (401/403) — retrying is pointless
  /// until the user signs in again.
  auth,

  /// The account tier does not allow the requested quality.
  vip,

  /// No usable space left, or the write itself reported ENOSPC.
  disk,

  /// The track/album/playlist does not exist on the platform any more.
  notFound,

  /// The platform answered normally but cannot serve this download.
  unsupported,

  /// The OS refused the path (Android storage permission, unwritable root).
  storagePermission,

  /// The user (or the queue) cancelled it — never shown as an error.
  cancelled,

  /// Anything we could not classify. Deliberately **not** retryable: retrying
  /// an unknown failure is how a broken URL becomes an infinite loop.
  unknown;

  static DownloadFailureKind? tryParse(String? name) {
    if (name == null) return null;
    for (final kind in DownloadFailureKind.values) {
      if (kind.name == name) return kind;
    }
    return null;
  }

  /// Whether the 失败自动重试 switch is allowed to try again on its own.
  bool get isRetryable =>
      this == DownloadFailureKind.network || this == DownloadFailureKind.disk;
}

/// A classified download failure: a machine-readable [kind] plus the message
/// the UI shows.
class DownloadFailure {
  final DownloadFailureKind kind;
  final String message;
  final String? detail;

  const DownloadFailure({
    required this.kind,
    required this.message,
    this.detail,
  });

  factory DownloadFailure.network([String? detail]) => DownloadFailure(
    kind: DownloadFailureKind.network,
    message: '网络连接失败，请检查网络后重试',
    detail: detail,
  );

  factory DownloadFailure.storageFull([String? detail]) => DownloadFailure(
    kind: DownloadFailureKind.disk,
    message: '存储空间不足，无法继续下载',
    detail: detail,
  );

  factory DownloadFailure.cancelled() => const DownloadFailure(
    kind: DownloadFailureKind.cancelled,
    message: '下载已取消',
  );

  /// Builds a failure from an HTTP status code, used when the server *did*
  /// answer but not with a body we can use.
  factory DownloadFailure.fromStatus(int? statusCode) {
    final kind = switch (statusCode) {
      401 || 403 => DownloadFailureKind.auth,
      404 || 410 => DownloadFailureKind.notFound,
      416 => DownloadFailureKind.network, // bad Range: the partial file is stale
      null => DownloadFailureKind.network,
      _ => DownloadFailureKind.unsupported,
    };
    return DownloadFailure(
      kind: kind,
      message: switch (kind) {
        DownloadFailureKind.auth => '登录已过期，请重新登录',
        DownloadFailureKind.notFound => '内容不存在或已被删除',
        DownloadFailureKind.network => '网络连接失败，请检查网络后重试',
        _ => '下载失败: HTTP $statusCode',
      },
      detail: statusCode == null ? null : 'HTTP $statusCode',
    );
  }

  /// Classifies anything a download can throw.
  ///
  /// Platform code throws the typed [ApiException] hierarchy (Wave 1), so the
  /// mapping is by type; raw strings only ever reach [DownloadFailureKind.unknown].
  factory DownloadFailure.from(Object error, {String? platformName}) {
    if (error is DownloadFailure) return error;

    final api = apiExceptionOf(error);
    final kind = switch (api) {
      NetworkException() => DownloadFailureKind.network,
      LoginExpiredException() => DownloadFailureKind.auth,
      NoVipMembershipException() => DownloadFailureKind.vip,
      StorageFullException() => DownloadFailureKind.disk,
      NotFoundException() => DownloadFailureKind.notFound,
      LyricsNotFoundException() => DownloadFailureKind.notFound,
      QualityNotAvailableException() => DownloadFailureKind.vip,
      SongNotAvailableException() => DownloadFailureKind.notFound,
      UnsupportedActionException() => DownloadFailureKind.unsupported,
      StoragePermissionDeniedException() =>
        DownloadFailureKind.storagePermission,
      RequestCancelledException() => DownloadFailureKind.cancelled,
      _ => _fromStatusCode(api.statusCode),
    };

    final message = switch (kind) {
      DownloadFailureKind.vip =>
        platformName == null || platformName.isEmpty
            ? '需要开通会员才能下载该音质'
            : '需要开通$platformName会员才能下载该音质',
      DownloadFailureKind.storagePermission => '存储权限被拒绝，请在系统设置中授权',
      DownloadFailureKind.cancelled => '下载已取消',
      _ => api.message.isEmpty ? '下载失败' : api.message,
    };

    return DownloadFailure(kind: kind, message: message, detail: api.details);
  }

  static DownloadFailureKind _fromStatusCode(int? code) => switch (code) {
    401 || 403 => DownloadFailureKind.auth,
    404 || 410 => DownloadFailureKind.notFound,
    _ => DownloadFailureKind.unknown,
  };

  bool get isRetryable => kind.isRetryable;

  DownloadFailureKind? get persistedKind => kind;

  @override
  String toString() => 'DownloadFailure(${kind.name}): $message';
}
