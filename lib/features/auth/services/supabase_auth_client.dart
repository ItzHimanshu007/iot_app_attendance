import 'dart:developer' as dev;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config.dart';
import '../../../core/exceptions.dart';

/// Low-level Supabase Auth REST client.
///
/// Handles token exchange with Supabase Auth service directly,
/// separate from the FastAPI ApiClient which uses the JWT.
///
/// Supabase Auth REST endpoints:
///   POST /auth/v1/token?grant_type=password   → sign in
///   POST /auth/v1/token?grant_type=refresh_token → refresh
///   POST /auth/v1/logout                       → sign out
class SupabaseAuthClient {
  SupabaseAuthClient() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.supabaseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'apikey': AppConfig.supabaseAnonKey,
      },
    ));

    // Always add — uses dart:developer (visible in adb logcat on release builds)
    _dio.interceptors.add(_SupabaseLogInterceptor());
  }

  late final Dio _dio;

  /// Sign in with email and password.
  ///
  /// Returns raw JSON from Supabase Auth including access_token,
  /// refresh_token, and user object.
  Future<Map<String, dynamic>> signInWithPassword({
    required String email,
    required String password,
  }) async {
    return _call(() => _dio.post(
          '/auth/v1/token',
          queryParameters: {'grant_type': 'password'},
          data: {'email': email, 'password': password},
        ));
  }

  /// Create a new Supabase auth user.
  ///
  /// Returns raw Supabase response which includes:
  ///   - `user`    — always present on success
  ///   - `session` — present only when email confirmation is DISABLED;
  ///                 null when confirmation email is sent
  ///
  /// [role] and [fullName] are written into `raw_user_meta_data` so that
  /// a Postgres DB trigger can read them even when email confirmation is ON
  /// and no session is returned immediately.
  Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
    required String role,
    required String fullName,
  }) async {
    return _call(() => _dio.post(
          '/auth/v1/signup',
          data: {
            'email': email,
            'password': password,
            // 'data' key → Supabase stores this as raw_user_meta_data
            // Available to DB triggers regardless of email confirmation state
            'data': {
              'role': role,
              'full_name': fullName,
            },
          },
        ));
  }

  /// Insert a user profile row into `public.users` via Supabase Postgres REST.
  ///
  /// Requires a valid JWT ([accessToken]) that satisfies the RLS INSERT policy:
  ///   `WITH CHECK (auth.uid() = id)`
  Future<void> insertUserProfile({
    required String accessToken,
    required Map<String, dynamic> profile,
  }) async {
    try {
      await _dio.post(
        '/rest/v1/users',
        data: profile,
        options: Options(
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Prefer': 'return=minimal',
          },
        ),
      );
      dev.log('[Supabase] profile row inserted — id=${profile["id"]}', name: 'SupabaseAuthClient');
    } on DioException catch (e) {
      dev.log('[Supabase] profile insert failed: ${e.response?.statusCode} ${e.message}', name: 'SupabaseAuthClient');
      throw _mapError(e);
    }
  }

  /// Send a password-reset email via Supabase Auth.
  ///
  /// Supabase sends a magic link to the provided [email].
  /// Does NOT throw if the email is not found (Supabase returns 200 regardless
  /// for security — prevents email enumeration).
  Future<void> resetPasswordForEmail(String email) async {
    await _call(() => _dio.post(
          '/auth/v1/recover',
          data: {'email': email},
        ));
  }

  /// Refresh an expired access token using the refresh token.
  Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    return _call(() => _dio.post(
          '/auth/v1/token',
          queryParameters: {'grant_type': 'refresh_token'},
          data: {'refresh_token': refreshToken},
        ));
  }

  /// Sign out — invalidates the token server-side.
  Future<void> signOut(String accessToken) async {
    try {
      await _dio.post(
        '/auth/v1/logout',
        options: Options(
          headers: {'Authorization': 'Bearer $accessToken'},
        ),
      );
    } on DioException {
      // Best-effort sign out — even if it fails, local state is cleared
    }
  }

  // ── Internal ────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _call(
    Future<Response> Function() request,
  ) async {
    try {
      final response = await request();
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  AppException _mapError(DioException e) {
    final status = e.response?.statusCode;
    final body = e.response?.data;

    String message = 'Authentication failed';
    if (body is Map<String, dynamic>) {
      // Supabase error format: {"error": "...", "error_description": "..."}
      message = body['error_description'] as String? ??
          body['error'] as String? ??
          body['msg'] as String? ??
          message;
    }

    switch (status) {
      case 400:
        // Invalid credentials or bad request
        if (message.toLowerCase().contains('invalid') ||
            message.toLowerCase().contains('wrong') ||
            message.toLowerCase().contains('credentials')) {
          return AuthException(
            'Invalid email or password',
            code: 'INVALID_CREDENTIALS',
          );
        }
        return ValidationException(message);
      case 401:
        return const SessionExpiredException();
      case 422:
        return ValidationException(message);
      case 429:
        return const ServerException(
          'Too many login attempts. Please wait a moment.',
          code: 'RATE_LIMITED',
          statusCode: 429,
        );
      default:
        if (e.type == DioExceptionType.connectionError) {
          return const NetworkException();
        }
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          return const TimeoutException();
        }
        return ServerException(message, statusCode: status);
    }
  }
}

class _SupabaseLogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    dev.log('[Supabase] → ${options.method} ${options.path}', name: 'SupabaseAuthClient');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    dev.log('[Supabase] ← ${response.statusCode}', name: 'SupabaseAuthClient');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    dev.log('[Supabase] ✗ ${err.response?.statusCode} — ${err.message}', name: 'SupabaseAuthClient', error: err);
    handler.next(err);
  }
}

/// Provider for the Supabase Auth REST client.
final supabaseAuthClientProvider = Provider<SupabaseAuthClient>((ref) {
  return SupabaseAuthClient();
});
