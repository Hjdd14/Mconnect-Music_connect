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
      : super(message: '需要开通${platformName}会员');
}

class StoragePermissionDeniedException extends ApiException {
  StoragePermissionDeniedException() : super(message: '存储权限被拒绝，请在设置中授权');
}

class StorageFullException extends ApiException {
  StorageFullException() : super(message: '存储空间不足');
}
