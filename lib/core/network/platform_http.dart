import 'package:dio/dio.dart';

import '../../l10n/l10n.dart';
import '../../models/platform_type.dart';
import 'api_exception.dart';
import 'retry_interceptor.dart';

/// Called when a platform reports that the stored session is no longer valid
/// (HTTP 401/403).
///
/// The point of this seam is that session expiry is reported **once, centrally**,
/// instead of every caller remembering to handle it. Before it existed exactly
/// one production call site
/// (`platform_playlists_provider.dart`) reacted to [LoginExpiredException],
/// so a dead cookie on any other path (daily recommendations, charts, charts
/// hub, downloads, stream-URL resolution) left the app showing the user as
/// logged in while every request failed — and in the worst case degraded
/// silently to guest data.
typedef SessionExpiredHandler = void Function(PlatformType platform);

/// Process-wide sink for [SessionExpiredHandler].
///
/// A global is acceptable here because there is exactly one app instance and
/// the handler is installed once at start-up (`lib/app.dart`). Tests should pass
/// `onSessionExpired:` to [createPlatformDio] instead of mutating this, so they
/// never depend on ordering between each other.
class SessionExpiryReporter {
  SessionExpiryReporter._();

  static SessionExpiredHandler? handler;

  /// Forgets the installed handler (tests, and a clean shutdown).
  static void reset() => handler = null;

  static void report(PlatformType platform) => handler?.call(platform);
}

/// Builds the [Dio] instance every platform adapter should use.
///
/// Before this existed, the old `ApiClient` / `_ErrorInterceptor` pair was
/// **dead code**: all three platform adapters constructed their own bare `Dio`
/// (`netease_api.dart:13`, `qq_api.dart:14`, `kugou_api.dart:24`) with no
/// interceptors, so the app had no retry, no request cancellation and no
/// translated error messages despite the classes being present. (That dead pair
/// was removed in W3-D; `api_client.dart` is a tombstone.)
///
/// Differences from that old client:
/// * retries are **restricted to idempotent methods** (`GET`/`HEAD`), so a
///   failed `POST` (login, like, playlist write) is never replayed;
/// * timeouts are configurable per platform, including `sendTimeout`;
/// * retry backoff is configurable ([retryBaseDelay]/[retryMaxDelay]) so per
///   platform tuning and fast tests do not need the production 1s/2s backoff;
/// * errors are translated into typed [ApiException]s (see
///   [PlatformErrorInterceptor]);
/// * a session expiry is reported through [onSessionExpired] /
///   [SessionExpiryReporter] rather than being left to each caller.
///
/// Usage:
/// ```dart
/// final dio = createPlatformDio(platform: PlatformType.netease);
/// ```
///
/// KNOWN LIMIT: only HTTP 401/403 counts as an expiry. These APIs very often
/// answer 200 with a business error code instead (NetEase `code`, QQ `code`,
/// Kugou token errors), and those are **not** recognised here — such a failure
/// surfaces as a normal error, or as silently degraded guest data. Widening it
/// requires per-platform body-code semantics, which is deliberately out of
/// scope (see docs/mconnect-improvement-plan.md).
///
/// [platform] is optional on purpose: it is what enables the expiry report, but
/// existing callers and tests that only pass a [label] must keep working (a
/// required parameter here would have forced several concurrently edited test
/// files to change at once). Production adapters pass it; tests may omit it.
Dio createPlatformDio({
  String? label,
  PlatformType? platform,
  SessionExpiredHandler? onSessionExpired,
  String? baseUrl,
  Map<String, String>? headers,
  Duration connectTimeout = const Duration(seconds: 15),
  Duration receiveTimeout = const Duration(seconds: 15),
  Duration sendTimeout = const Duration(seconds: 15),
  int maxRetries = 2,
  Duration retryBaseDelay = const Duration(seconds: 1),
  Duration retryMaxDelay = const Duration(seconds: 30),
  List<Interceptor> interceptors = const [],
}) {
  final effectiveLabel =
      label ?? platform?.displayName ?? zhAppLocalizations.netUnknownPlatform;
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl ?? '',
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      sendTimeout: sendTimeout,
      headers: headers == null ? null : Map<String, String>.from(headers),
      // Platform payloads are decoded by hand (several platforms return a JSON
      // document wrapped in a JSON string), so Dio must not try to be clever.
      responseType: ResponseType.json,
    ),
  );

  final retry = RetryInterceptor(
    maxRetries: maxRetries,
    baseDelay: retryBaseDelay,
    maxDelay: retryMaxDelay,
  );
  dio.interceptors.addAll([
    IdempotentRetryGuard(retry),
    PlatformErrorInterceptor(
      label: effectiveLabel,
      platform: platform,
      onSessionExpired: onSessionExpired,
    ),
    ...interceptors,
  ]);
  // RetryInterceptor re-issues the request through this instance, so it needs
  // the reference after the interceptors are installed.
  retry.dio = dio;

  return dio;
}

/// Restricts [RetryInterceptor] to idempotent requests.
///
/// A retry re-sends the request; replaying a `POST` that already reached the
/// server can double-apply a side effect (double "like", duplicated playlist
/// entry). Non-idempotent failures are deliberately passed straight through.
class IdempotentRetryGuard extends Interceptor {
  IdempotentRetryGuard(this._inner);

  final RetryInterceptor _inner;

  static const Set<String> _idempotentMethods = {'GET', 'HEAD', 'OPTIONS'};

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final method = err.requestOptions.method.toUpperCase();
    if (_idempotentMethods.contains(method)) {
      _inner.onError(err, handler);
      return;
    }
    handler.next(err);
  }
}

/// Translates transport failures into typed [ApiException]s.
///
/// The translated exception is attached to `DioException.error`, which is where
/// platform code can pick it up with [apiExceptionOf]; [translateDioException]
/// does the unwrapping for the common `catch` shape.
class PlatformErrorInterceptor extends Interceptor {
  PlatformErrorInterceptor({
    required this.label,
    this.platform,
    this.onSessionExpired,
  });

  /// Platform name used in messages, e.g. `网易云音乐`.
  final String label;

  /// Which platform this client belongs to. When null, expiry reporting is
  /// disabled for this client (callers that only pass a label).
  final PlatformType? platform;

  /// Overrides [SessionExpiryReporter.handler] for this client; tests inject it
  /// so they never depend on a global.
  final SessionExpiredHandler? onSessionExpired;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final translated = translateDioException(err, label: label);
    final owner = platform;
    if (owner != null && translated is LoginExpiredException) {
      // Reported centrally instead of making every caller remember: one dead
      // cookie used to be noticed by exactly one provider.
      (onSessionExpired ?? SessionExpiryReporter.report)(owner);
    }
    handler.next(
      DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        type: err.type,
        error: translated,
        message: translated.message,
        stackTrace: err.stackTrace,
      ),
    );
  }
}

/// Maps a [DioException] onto the app's typed exception hierarchy.
ApiException translateDioException(DioException err, {String label = ''}) {
  switch (err.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      // A timeout is a connectivity problem, but the UI can say something more
      // precise than "couldn't connect": it knows which platform timed out.
      return NetworkException(
        details: zhAppLocalizations.netRequestTimeout(label),
        code: ApiErrorCode.requestTimeout,
        platform: label,
      );
    case DioExceptionType.connectionError:
    case DioExceptionType.badCertificate:
      return NetworkException(details: err.message);
    case DioExceptionType.cancel:
      // A deliberate cancel (screen disposed, a newer query superseded this
      // one, `CancelToken` fired) is not a connectivity problem. Adapters wire
      // per-query `CancelToken`s, so callers must be able to tell the two
      // apart — otherwise leaving a page shows "网络连接失败，请检查网络".
      return RequestCancelledException();
    case DioExceptionType.badResponse:
      return _fromStatusCode(err.response?.statusCode, label);
    case DioExceptionType.unknown:
      return NetworkException(details: err.message);
  }
}

ApiException _fromStatusCode(int? code, String label) {
  switch (code) {
    case 401:
    case 403:
      // Both mean "the stored session is no longer usable" for these APIs.
      return LoginExpiredException();
    case 404:
      return NotFoundException(details: label.isEmpty ? null : label);
    case 500:
    case 502:
    case 503:
    case 504:
      return ApiException(
        statusCode: code,
        message: zhAppLocalizations.netServerError(label),
        code: ApiErrorCode.serverError,
        platform: label,
      );
    default:
      return ApiException(
        statusCode: code,
        message: code == null
            ? zhAppLocalizations.netRequestFailed
            : zhAppLocalizations.netRequestFailedWithCode(code),
        code: ApiErrorCode.requestFailed,
      );
  }
}

/// Unwraps the typed exception a [PlatformErrorInterceptor] attached, if any.
///
/// Lets platform code write the pattern the UI needs:
/// ```dart
/// } on Object catch (e) {
///   throw apiExceptionOf(e);   // never leak a raw Exception to the UI
/// }
/// ```
ApiException apiExceptionOf(Object error) {
  if (error is ApiException) return error;
  if (error is DioException) {
    final inner = error.error;
    if (inner is ApiException) return inner;
    return translateDioException(error);
  }
  return ApiException(message: error.toString());
}
