// `lib/core/network/` -> two levels up is `lib/`, then `l10n/`.
// (`../l10n/` resolved to `lib/core/l10n/`, which does not exist, and because the
// import failed, every `zhAppLocalizations` reference below became "undefined
// name" - 18 errors from one path.)
import '../../l10n/l10n.dart';

/// Machine-readable reason for a failed request — the "错误码" half of
/// `docs/i18n-migration-plan.md` §3.3 「模式 A」.
///
/// An [ApiException] is thrown deep in the data/platform layer, where there is
/// no `BuildContext`, so it cannot translate itself. It carries this code
/// instead, and the UI maps it to the current locale with
/// `apiErrorText(context, error)` (`lib/core/network/api_error_l10n.dart`).
///
/// [ApiErrorCode.unknown] is the default: a raw `message` (e.g. one a platform
/// adapter built itself) is shown verbatim, which is exactly the behaviour
/// before the migration.
enum ApiErrorCode {
  loginExpired,
  songNotAvailable,
  qualityNotAvailable,
  lyricsNotFound,
  noVipMembership,
  storagePermissionDenied,
  network,
  notFound,
  unsupportedAction,
  storageFull,
  requestCancelled,
  requestTimeout,
  serverError,
  requestFailed,
  unknown,
}

class ApiException implements Exception {
  final int? statusCode;

  /// Chinese fallback text, **sourced from the ARB** (`lib/l10n/app_zh.arb`)
  /// rather than written here — that is what keeps `lib/core/network/**` free
  /// of hardcoded Chinese (`test/i18n_budget_test.dart`) while leaving the
  /// rendered Chinese byte-identical to the previous literals, so the page
  /// tests that assert it need no change.
  ///
  /// It is still the text shown when the UI has no translation for [code].
  final String message;

  /// Diagnostic detail (never a localized sentence the user must understand).
  final String? details;

  /// What the UI should display, in the current locale.
  final ApiErrorCode code;

  /// Placeholder value for codes that name a platform
  /// ([ApiErrorCode.songNotAvailable], [ApiErrorCode.unsupportedAction],
  /// [ApiErrorCode.noVipMembership], [ApiErrorCode.serverError],
  /// [ApiErrorCode.requestTimeout]).
  final String? platform;

  /// Placeholder value for [ApiErrorCode.qualityNotAvailable].
  final String? suggestedQuality;

  ApiException({
    this.statusCode,
    required this.message,
    this.details,
    this.code = ApiErrorCode.unknown,
    this.platform,
    this.suggestedQuality,
  });

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class LoginExpiredException extends ApiException {
  LoginExpiredException()
    : super(
        message: zhAppLocalizations.netLoginExpired,
        code: ApiErrorCode.loginExpired,
      );
}

class SongNotAvailableException extends ApiException {
  SongNotAvailableException({super.platform})
    : super(
        message: zhAppLocalizations.netSongNotAvailable(
          platform ?? zhAppLocalizations.netCurrentPlatform,
        ),
        code: ApiErrorCode.songNotAvailable,
      );
}

class QualityNotAvailableException extends ApiException {
  QualityNotAvailableException({super.suggestedQuality})
    : super(
        message: suggestedQuality == null
            ? zhAppLocalizations.netQualityNotAvailable
            : zhAppLocalizations.netQualityDowngraded(suggestedQuality),
        code: ApiErrorCode.qualityNotAvailable,
      );
}

class LyricsNotFoundException extends ApiException {
  LyricsNotFoundException()
    : super(
        message: zhAppLocalizations.netLyricsNotFound,
        code: ApiErrorCode.lyricsNotFound,
      );
}

class NoVipMembershipException extends ApiException {
  final String platformName;

  NoVipMembershipException(this.platformName)
    : super(
        message: zhAppLocalizations.netNoVip(platformName),
        code: ApiErrorCode.noVipMembership,
        platform: platformName,
      );
}

class StoragePermissionDeniedException extends ApiException {
  StoragePermissionDeniedException()
    : super(
        message: zhAppLocalizations.netStoragePermissionDenied,
        code: ApiErrorCode.storagePermissionDenied,
      );
}

/// The request never produced an HTTP response (timeout, DNS, socket, TLS).
///
/// Distinct from [ApiException] with a [ApiException.statusCode] because the
/// UI treats it differently: a status code means "the server answered", a
/// network failure means "retry may help / check connectivity".
class NetworkException extends ApiException {
  /// [code] defaults to [ApiErrorCode.network], but a caller that knows better
  /// (e.g. `translateDioException` on a connect/receive timeout, which sets
  /// [ApiErrorCode.requestTimeout]) can override it — the [message] fallback
  /// stays the same either way.
  NetworkException({
    super.details,
    super.code = ApiErrorCode.network,
    super.platform,
  }) : super(message: zhAppLocalizations.netConnectionFailed);
}

/// The requested resource does not exist on the platform (HTTP 404, or a
/// platform-specific "not found" code).
class NotFoundException extends ApiException {
  NotFoundException({super.details})
    : super(
        message: zhAppLocalizations.netNotFound,
        code: ApiErrorCode.notFound,
      );
}

/// The platform answered normally but does not implement this capability.
///
/// Used for the honest-degradation paths: 网易云/QQ 的艺人专辑列表、酷狗的
/// 官方每日推荐 etc. The UI is expected to surface the reason rather than
/// showing an empty list that looks like "no data".
class UnsupportedActionException extends ApiException {
  final String platformName;

  UnsupportedActionException(this.platformName, {super.details})
    : super(
        message: zhAppLocalizations.netUnsupported(platformName),
        code: ApiErrorCode.unsupportedAction,
        platform: platformName,
      );
}

class StorageFullException extends ApiException {
  StorageFullException()
    : super(
        message: zhAppLocalizations.netStorageFull,
        code: ApiErrorCode.storageFull,
      );
}

/// The caller cancelled the request (screen disposed, user navigated away, a
/// newer query superseded this one).
///
/// Deliberately NOT a [NetworkException]: the network was fine, so the UI must
/// not tell the user to retry the connection. Callers that cancel query
/// requests (see the `CancelToken` wiring in the platform adapters) are
/// expected to swallow this type silently.
class RequestCancelledException extends ApiException {
  RequestCancelledException()
    : super(
        message: zhAppLocalizations.netRequestCancelled,
        code: ApiErrorCode.requestCancelled,
      );
}
