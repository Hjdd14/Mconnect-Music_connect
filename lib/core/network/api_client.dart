import 'package:dio/dio.dart';
import 'api_exception.dart';
import 'retry_interceptor.dart';

class ApiClient {
  final Dio _dio;

  ApiClient({BaseOptions? options})
      : _dio = Dio(options ?? BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 15),
            sendTimeout: const Duration(seconds: 15),
          )) {
    final retryInterceptor = RetryInterceptor();
    _dio.interceptors.addAll([
      retryInterceptor,
      _ErrorInterceptor(),
    ]);
    retryInterceptor.dio = _dio;
  }

  Dio get dio => _dio;

  void setCookies(String domain, Map<String, String> cookies) {
    final cookie = cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
    _dio.options.headers['cookie'] = cookie;
  }

  void setHeaders(Map<String, String> headers) {
    _dio.options.headers.addAll(headers);
  }
}

class _ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    String message;
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        message = '网络连接超时';
        break;
      case DioExceptionType.badResponse:
        message = _statusCodeMessage(err.response?.statusCode);
        break;
      case DioExceptionType.connectionError:
        message = '无网络连接';
        break;
      default:
        message = '请求失败';
    }
    handler.next(DioException(
      requestOptions: err.requestOptions,
      response: err.response,
      type: err.type,
      error: ApiException(
        statusCode: err.response?.statusCode,
        message: message,
        details: err.message,
      ),
      message: message,
    ));
  }

  String _statusCodeMessage(int? code) {
    switch (code) {
      case 401:
        return '登录已过期';
      case 403:
        return '请求被拒绝';
      case 404:
        return '资源不存在';
      case 500:
      case 502:
      case 503:
        return '服务器异常';
      default:
        return '请求失败 ($code)';
    }
  }
}
