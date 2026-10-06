class ApiException implements Exception {
  final int? statusCode;
  final String message;
  final String? details;

  ApiException({this.statusCode, required this.message, this.details});

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class LoginExpiredException extends ApiException {
  LoginExpiredException() : super(message: '登录已过期，请重新登录');
}

class SongNotAvailableException extends ApiException {
  SongNotAvailableException({String? platform})
      : super(message: '该歌曲在${platform ?? "当前平台"}不可用');
}

class QualityNotAvailableException extends ApiException {
  final String? suggestedQuality;
  QualityNotAvailableException({this.suggestedQuality})
      : super(message: '所选音质不可用${suggestedQuality != null ? "，已降级到$suggestedQuality" : ""}');
}

class LyricsNotFoundException extends ApiException {
  LyricsNotFoundException() : super(message: '暂无歌词');
}

class NoVipMembershipException extends ApiException {
  final String platformName;
  NoVipMembershipException(this.platformName)
      : super(message: '需要开通$platformName会员');
}

class StoragePermissionDeniedException extends ApiException {
  StoragePermissionDeniedException() : super(message: '存储权限被拒绝，请在设置中授权');
}

/// The request never produced an HTTP response (timeout, DNS, socket, TLS).
///
/// Distinct from [ApiException] with a [ApiException.statusCode] because the
/// UI treats it differently: a status code means "the server answered", a
/// network failure means "retry may help / check connectivity".
class NetworkException extends ApiException {
  NetworkException({super.details})
      : super(message: '网络连接失败，请检查网络后重试');
}

/// The requested resource does not exist on the platform (HTTP 404, or a
/// platform-specific "not found" code).
class NotFoundException extends ApiException {
  NotFoundException({super.details}) : super(message: '内容不存在或已被删除');
}

/// The platform answered normally but does not implement this capability.
///
/// Used for the honest-degradation paths: 网易云/QQ 的艺人专辑列表、酷狗的
/// 官方每日推荐 etc. The UI is expected to surface [ApiException.message]
/// rather than showing an empty list that looks like "no data".
class UnsupportedActionException extends ApiException {
  UnsupportedActionException(this.platformName, {super.details})
      : super(message: '$platformName暂不支持该功能');

  final String platformName;
}

class StorageFullException extends ApiException {
  StorageFullException() : super(message: '存储空间不足');
}

/// The caller cancelled the request (screen disposed, user navigated away, a
/// newer query superseded this one).
///
/// Deliberately NOT a [NetworkException]: the network was fine, so the UI must
/// not tell the user to "检查网络后重试". Callers that cancel query requests
/// (see the `CancelToken` wiring in the platform adapters) are expected to
/// swallow this type silently.
class RequestCancelledException extends ApiException {
  RequestCancelledException() : super(message: '请求已取消');
}
