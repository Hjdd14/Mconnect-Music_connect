import 'dart:async';
import 'package:dio/dio.dart';

/// Retries failed requests with exponential backoff.
/// Only retries on connection timeouts and 5xx server errors.
///
/// IMPORTANT: Set [dio] to the parent Dio instance after adding this
/// interceptor, so retries use the same interceptor chain and timeout config.
class RetryInterceptor extends Interceptor {
  final int maxRetries;
  final Duration baseDelay;
  final Duration maxDelay;

  /// Reference to the parent Dio. Must be set after adding this interceptor.
  Dio? dio;

  RetryInterceptor({
    this.maxRetries = 3,
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
  });

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final retryCount = err.requestOptions._retryCount;

    if (retryCount >= maxRetries || !_shouldRetry(err)) {
      return handler.next(err);
    }

    final delay = Duration(
      milliseconds: (baseDelay.inMilliseconds * (1 << retryCount))
          .clamp(0, maxDelay.inMilliseconds),
    );
    await Future.delayed(delay);

    err.requestOptions._retryCount = retryCount + 1;

    final dioRef = dio;
    if (dioRef == null) {
      return handler.next(err);
    }

    try {
      final response = await dioRef.fetch(err.requestOptions);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  bool _shouldRetry(DioException err) {
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        final code = err.response?.statusCode;
        return code != null && code >= 500;
      default:
        return false;
    }
  }
}

/// Extension to track retry count on request options.
const _retryKey = 'retry_count';

extension _RetryX on RequestOptions {
  int get _retryCount => (extra[_retryKey] as int?) ?? 0;
  set _retryCount(int value) => extra[_retryKey] = value;
}
