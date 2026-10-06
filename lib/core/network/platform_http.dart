import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'retry_interceptor.dart';

/// Builds the [Dio] instance every platform adapter should use.
///
/// Before this existed, `ApiClient`/`RetryInterceptor`/`_ErrorInterceptor` were
/// **dead code**: all three platform adapters constructed their own bare `Dio`
/// (`netease_api.dart:13`, `qq_api.dart:14`, `kugou_api.dart:24`) with no
/// interceptors, so the app had no retry, no request cancellation and no
/// translated error messages despite the classes being present.
///
/// Differences from the old [ApiClient]:
/// * retries are **restricted to idempotent methods** (`GET`/`HEAD`), so a
///   failed `POST` (login, like, playlist write) is never replayed;
/// * timeouts are configurable per platform, including `sendTimeout`;
/// * errors are translated into typed [ApiException]s (see
///   [PlatformErrorInterceptor]).
///
/// Usage (Wave 1 wires the adapters to this):
/// ```dart
/// final dio = createPlatformDio(label: 'netease');
/// ```
Dio createPlatformDio({
  required String label,
  String? baseUrl,
  Map<String, String>? headers,
  Duration connectTimeout = const Duration(seconds: 15),
  Duration receiveTimeout = const Duration(seconds: 15),
  Duration sendTimeout = const Duration(seconds: 15),
  int maxRetries = 2,
  List<Interceptor> interceptors = const [],
}) {
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

  final retry = RetryInterceptor(maxRetries: maxRetries);
  dio.interceptors.addAll([
    IdempotentRetryGuard(retry),
    PlatformErrorInterceptor(label: label),
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
/// platform code can pick it up with [apiExceptionOf]; [translateApiException]
/// does the unwrapping for the common `catch` shape.
class PlatformErrorInterceptor extends Interceptor {
  PlatformErrorInterceptor({required this.label});

  /// Platform name used in messages, e.g. `网易云`.
  final String label;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final translated = translateDioException(err, label: label);
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
      return NetworkException(details: '$label请求超时');
    case DioExceptionType.connectionError:
    case DioExceptionType.badCertificate:
      return NetworkException(details: err.message);
    case DioExceptionType.cancel:
      return NetworkException(details: '请求已取消');
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
      return ApiException(statusCode: code, message: '$label服务器异常');
    default:
      return ApiException(
        statusCode: code,
        message: code == null ? '请求失败' : '请求失败 ($code)',
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
