import 'dart:developer' as dev;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api_exception.dart';
import 'config.dart';

/// HTTP client for the FastAPI backend.
///
/// * Adds the Supabase access token (refreshing it first if it expired).
/// * Retries once after a 401 with a freshly refreshed token.
/// * Maps every failure to an [ApiException] with the backend's error code.
class ApiClient {
  ApiClient(this._auth) {
    _dio = Dio(
      BaseOptions(
        baseUrl: '${AppConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), '')}/api/v1',
        connectTimeout: AppConfig.connectTimeout,
        receiveTimeout: AppConfig.receiveTimeout,
        sendTimeout: AppConfig.connectTimeout,
        headers: {'Accept': 'application/json'},
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _accessToken();
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
          handler.next(options);
        },
        onError: (error, handler) async {
          final retried = error.requestOptions.extra['retried'] == true;
          if (error.response?.statusCode == 401 && !retried) {
            try {
              final refreshed = await _auth.refreshSession();
              final token = refreshed.session?.accessToken;
              if (token != null) {
                final options = error.requestOptions
                  ..headers['Authorization'] = 'Bearer $token'
                  ..extra['retried'] = true;
                return handler.resolve(await _dio.fetch(options));
              }
            } catch (_) {
              // fall through to the original error
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  final GoTrueClient _auth;
  late final Dio _dio;

  Future<String?> _accessToken() async {
    final session = _auth.currentSession;
    if (session == null) return null;
    if (session.isExpired) {
      try {
        final refreshed = await _auth.refreshSession();
        return refreshed.session?.accessToken;
      } catch (_) {
        return session.accessToken;
      }
    }
    return session.accessToken;
  }

  /// Wakes a sleeping Render instance. Fire-and-forget.
  Future<void> warmUp() async {
    try {
      await Dio(BaseOptions(receiveTimeout: AppConfig.receiveTimeout))
          .get('${AppConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), '')}/health');
    } catch (_) {}
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.get(path, queryParameters: query));

  Future<dynamic> post(String path, {Object? data}) => _send(() => _dio.post(path, data: data));

  Future<dynamic> put(String path, {Object? data}) => _send(() => _dio.put(path, data: data));

  Future<dynamic> patch(String path, {Object? data}) => _send(() => _dio.patch(path, data: data));

  Future<List<int>> getBytes(String path, {Map<String, dynamic>? query}) async {
    final response = await _send(
      () => _dio.get<List<int>>(
        path,
        queryParameters: query,
        options: Options(responseType: ResponseType.bytes),
      ),
    );
    return response as List<int>;
  }

  Future<dynamic> _send(Future<Response<dynamic>> Function() call) async {
    try {
      final response = await call();
      return response.data;
    } on DioException catch (e) {
      final mapped = _map(e);
      dev.log(
        'API ${e.requestOptions.method} ${e.requestOptions.path} → ${mapped.code}',
        name: 'ApiClient',
      );
      throw mapped;
    }
  }

  ApiException _map(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const ApiException(
          'The server is taking too long. If it was asleep, try again in a few seconds.',
          code: 'TIMEOUT',
        );
      case DioExceptionType.connectionError:
        return const ApiException(
          'Cannot reach the server. Check your internet connection.',
          code: 'NETWORK_ERROR',
        );
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode;
        final body = e.response?.data;
        if (body is Map && body['error'] is Map) {
          final err = body['error'] as Map;
          return ApiException(
            (err['message'] ?? 'Request failed').toString(),
            code: (err['code'] ?? 'HTTP_$status').toString(),
            statusCode: status,
          );
        }
        return ApiException('Server error ($status)', code: 'HTTP_$status', statusCode: status);
      default:
        return ApiException(e.message ?? 'Unexpected error', code: 'UNKNOWN');
    }
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(Supabase.instance.client.auth);
});
