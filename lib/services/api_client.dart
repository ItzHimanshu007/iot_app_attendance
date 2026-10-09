import 'dart:developer' as dev;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import '../core/exceptions.dart';
import 'secure_storage_service.dart';

/// Dio API client — configured with JWT interceptor, retry, and error mapping.
class ApiClient {
  ApiClient({required this.storage}) {
    _dio = Dio(BaseOptions(
      baseUrl: '${AppConfig.apiBaseUrl}/api/v1',
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      sendTimeout: AppConfig.sendTimeout,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    _dio.interceptors.addAll([
      _AuthInterceptor(storage),
      _RetryInterceptor(_dio),
      _LogInterceptor(), // always enabled — uses dart:developer (works in release)
    ]);
  }

  final SecureStorageService storage;
  late final Dio _dio;

  // ── HTTP methods ───────────────────────────────────────────────────────────

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? fromJson,
  }) async {
    final response = await _request(() => _dio.get(
          path,
          queryParameters: queryParameters,
        ));
    return fromJson != null ? fromJson(response.data) : response.data as T;
  }

  Future<T> post<T>(
    String path, {
    dynamic data,
    T Function(dynamic)? fromJson,
  }) async {
    final response = await _request(() => _dio.post(path, data: data));
    return fromJson != null ? fromJson(response.data) : response.data as T;
  }

  Future<T> patch<T>(
    String path, {
    dynamic data,
    T Function(dynamic)? fromJson,
  }) async {
    final response = await _request(() => _dio.patch(path, data: data));
    return fromJson != null ? fromJson(response.data) : response.data as T;
  }

  Future<T> put<T>(
    String path, {
    dynamic data,
    T Function(dynamic)? fromJson,
  }) async {
    final response = await _request(() => _dio.put(path, data: data));
    return fromJson != null ? fromJson(response.data) : response.data as T;
  }

  Future<void> delete(String path) async {
    await _request(() => _dio.delete(path));
  }

  // ── Error mapping ──────────────────────────────────────────────────────────

  Future<Response> _request(Future<Response> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  AppException _mapDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const TimeoutException();

      case DioExceptionType.connectionError:
        return const NetworkException();

      case DioExceptionType.badResponse:
        return _mapStatusCode(e.response);

      case DioExceptionType.cancel:
        return const UnexpectedException('Request cancelled');

      default:
        return UnexpectedException(e.message ?? 'Unknown error');
    }
  }

  AppException _mapStatusCode(Response? response) {
    final status = response?.statusCode ?? 500;
    final body = response?.data;

    // Extract backend error message
    String message = 'Server error';
    String? code;
    if (body is Map<String, dynamic>) {
      final error = body['error'];
      if (error is Map<String, dynamic>) {
        message = error['message'] as String? ?? message;
        code = error['code'] as String?;
      }
    }

    switch (status) {
      case 401:
        if (code == 'SESSION_EXPIRED') {
          return const SessionExpiredException();
        }
        return UnauthorizedException(message);
      case 403:
        return ForbiddenException(message);
      case 404:
        return NotFoundException(message);
      case 409:
        return ConflictException(message, code: code);
      case 422:
        return ValidationException(message, code: code);
      case >= 500:
        return ServerException(message, code: code, statusCode: status);
      default:
        return ServerException(message, code: code, statusCode: status);
    }
  }
}

// ── JWT Auth Interceptor ─────────────────────────────────────────────────────

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._storage);
  final SecureStorageService _storage;

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _storage.getAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      // Token expired — clear and let the auth state handle redirect
      dev.log('[API] 401 received — clearing tokens', name: 'ApiClient');
      await _storage.clearTokens();
    }
    handler.next(err);
  }
}

// ── Retry Interceptor ────────────────────────────────────────────────────────

class _RetryInterceptor extends Interceptor {
  _RetryInterceptor(this._dio);
  final Dio _dio;

  static const _maxRetries = AppConfig.maxRetries;
  static const _retryableStatuses = {408, 429, 500, 502, 503, 504};

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final status = err.response?.statusCode;
    final retryCount = err.requestOptions.extra['retryCount'] as int? ?? 0;

    if (retryCount < _maxRetries &&
        status != null &&
        _retryableStatuses.contains(status)) {
      final delay = Duration(milliseconds: 500 * (retryCount + 1));
      await Future.delayed(delay);

      final options = err.requestOptions;
      options.extra['retryCount'] = retryCount + 1;

      try {
        final response = await _dio.fetch(options);
        handler.resolve(response);
        return;
      } on DioException catch (retryErr) {
        handler.next(retryErr);
        return;
      }
    }
    handler.next(err);
  }
}

// ── Debug Log Interceptor ─────────────────────────────────────────

/// Uses dart:developer log() which is visible in adb logcat even in release.
class _LogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    dev.log('[API] → ${options.method} ${options.baseUrl}${options.path}', name: 'ApiClient');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    dev.log('[API] ← ${response.statusCode} ${response.requestOptions.path}', name: 'ApiClient');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final status = err.response?.statusCode ?? err.type.name;
    final url = err.requestOptions.baseUrl + err.requestOptions.path;
    dev.log('[API] ✗ $status $url — ${err.message}', name: 'ApiClient', error: err);
    handler.next(err);
  }
}

/// Global API client provider.
final apiClientProvider = Provider<ApiClient>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return ApiClient(storage: storage);
});
