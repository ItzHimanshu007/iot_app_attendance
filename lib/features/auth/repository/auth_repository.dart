import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/exceptions.dart';
import '../../../services/api_client.dart';
import '../../../services/secure_storage_service.dart';
import '../models/auth_models.dart';
import '../services/supabase_auth_client.dart';

/// Result from [AuthRepository.register].
class RegisterResult {
  const RegisterResult({
    required this.needsEmailVerification,
    required this.userId,
  });

  /// True when Supabase email confirmation is enabled.
  /// In this case the user must verify their email before logging in.
  final bool needsEmailVerification;
  final String userId;
}

/// Auth repository — coordinates Supabase Auth + FastAPI profile fetch.
///
/// Responsibilities:
///   - Sign in via Supabase Auth REST
///   - Fetch user profile from FastAPI (/api/v1/users/me)
///   - Refresh tokens via Supabase Auth REST
///   - Sign out (remote + local)
///   - Validate stored session on app launch
///   - Register new students and teachers
///   - Send password-reset emails
class AuthRepository {
  AuthRepository({
    required SupabaseAuthClient supabaseClient,
    required ApiClient apiClient,
    required SecureStorageService storage,
  })  : _supabase = supabaseClient,
        _api = apiClient,
        _storage = storage;

  final SupabaseAuthClient _supabase;
  final ApiClient _api;
  final SecureStorageService _storage;

  // ── Login ─────────────────────────────────────────────────────────────────

  /// Complete login flow:
  ///   1. Sign in with Supabase Auth → get tokens
  ///   2. Fetch profile from FastAPI with the new access token
  ///   3. Return (tokens, profile) tuple
  Future<({AuthTokenResponse tokens, UserProfile profile})> login({
    required String email,
    required String password,
  }) async {
    // Step 1: Authenticate with Supabase
    dev.log('[LOGIN] calling Supabase signInWithPassword', name: 'AuthRepository');
    final raw = await _supabase.signInWithPassword(
      email: email,
      password: password,
    );

    final tokens = AuthTokenResponse.fromJson(raw);

    if (tokens.userId.isEmpty) {
      dev.log('[LOGIN] ERROR: Supabase returned empty userId', name: 'AuthRepository');
      throw const AuthException(
        'Authentication succeeded but user ID was missing',
        code: 'MISSING_USER_ID',
      );
    }

    dev.log('[LOGIN] Supabase OK — userId=${tokens.userId}', name: 'AuthRepository');

    // Step 2: Fetch FastAPI profile with the new token
    // We temporarily store the token so ApiClient interceptor picks it up
    await _storage.setAccessToken(tokens.accessToken);
    dev.log('[LOGIN] access token stored, fetching FastAPI profile…', name: 'AuthRepository');

    final profile = await _fetchProfile();
    dev.log('[LOGIN] FastAPI profile OK — role=${profile.role}', name: 'AuthRepository');

    return (tokens: tokens, profile: profile);
  }

  // ── Profile ───────────────────────────────────────────────────────────────

  /// Fetch user profile from FastAPI /api/v1/users/me
  Future<UserProfile> getProfile() async {
    return _fetchProfile();
  }

  Future<UserProfile> _fetchProfile() async {
    dev.log('[API] /users/me request', name: 'AuthRepository');
    try {
      final profile = await _api.get<UserProfile>(
        '/users/me',
        fromJson: (data) =>
            UserProfile.fromJson(data as Map<String, dynamic>),
      );
      dev.log('[API] /users/me success — role=${profile.role}', name: 'AuthRepository');
      return profile;
    } catch (e) {
      dev.log('[API] /users/me failure: $e', name: 'AuthRepository', error: e);
      rethrow;
    }
  }

  // ── Token Refresh ─────────────────────────────────────────────────────────

  /// Refresh the access token using the stored refresh token.
  ///
  /// Returns the new access token, or throws [SessionExpiredException]
  /// if the refresh token itself is expired or invalid.
  Future<RefreshTokenResponse> refreshSession() async {
    final storedRefresh = await _storage.getRefreshToken();
    if (storedRefresh == null || storedRefresh.isEmpty) {
      throw const SessionExpiredException();
    }

    final raw = await _supabase.refreshToken(storedRefresh);
    return RefreshTokenResponse.fromJson(raw);
  }

  // ── Registration ──────────────────────────────────────────────────────────

  /// Create a new student or teacher account.
  ///
  /// Flow:
  ///   1. Call Supabase Auth `/auth/v1/signup`
  ///   2. If session returned (email confirmation disabled):
  ///        insert profile row via Supabase REST `/rest/v1/users`
  ///   3. If no session (email confirmation enabled):
  ///        show verification screen — profile is created via DB trigger or
  ///        upserted on first login
  Future<RegisterResult> register({
    required String email,
    required String password,
    required String fullName,
    required String role,   // 'student' | 'teacher'
    String? studentIdNumber, // enrollment number for students
    String? department,      // branch (students) or department (teachers)
  }) async {
    dev.log('[REGISTER] signUp email=$email role=$role', name: 'AuthRepository');
    final raw = await _supabase.signUp(
      email: email,
      password: password,
      role: role,
      fullName: fullName,
    );

    final user    = raw['user']    as Map<String, dynamic>?;
    final session = raw['session'] as Map<String, dynamic>?;

    if (user == null) {
      throw const AuthException(
        'Signup failed: no user data returned',
        code: 'SIGNUP_FAILED',
      );
    }

    final userId      = user['id'] as String;
    final accessToken = session?['access_token'] as String?;
    final needsVerification = accessToken == null;

    dev.log('[REGISTER] userId=$userId needsVerification=$needsVerification', name: 'AuthRepository');

    if (!needsVerification && accessToken != null) {
      // Email confirmation is disabled — insert profile immediately.
      await _storage.setAccessToken(accessToken);
      await _supabase.insertUserProfile(
        accessToken: accessToken,
        profile: {
          'id': userId,
          'email': email,
          'full_name': fullName,
          'role': role,
          'is_active': true,
          if (studentIdNumber != null && studentIdNumber.isNotEmpty)
            'student_id_number': studentIdNumber,
          if (department != null && department.isNotEmpty)
            'department': department,
        },
      );
      dev.log('[REGISTER] profile inserted', name: 'AuthRepository');
    } else {
      // Email confirmation is enabled.
      // Profile must be created via a Supabase DB trigger or on first login.
      dev.log('[REGISTER] email confirmation required — profile deferred', name: 'AuthRepository');
    }

    return RegisterResult(needsEmailVerification: needsVerification, userId: userId);
  }

  // ── Password Reset ────────────────────────────────────────────────────────

  /// Send a password-reset email via Supabase Auth.
  Future<void> forgotPassword(String email) async {
    dev.log('[AUTH] password reset requested for $email', name: 'AuthRepository');
    await _supabase.resetPasswordForEmail(email);
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  /// Sign out — calls Supabase to invalidate server-side, then clears storage.
  Future<void> logout() async {
    final token = await _storage.getAccessToken();
    if (token != null && token.isNotEmpty) {
      // Best-effort remote sign out (network may be unavailable)
      await _supabase.signOut(token);
    }
    await _storage.clearAll();
  }

  // ── Session Validation ────────────────────────────────────────────────────

  /// Validate the stored session on app launch.
  ///
  /// Returns the user profile if session is valid.
  /// Throws [SessionExpiredException] if token is absent or fetch fails with 401.
  /// Attempts a token refresh if the initial profile fetch returns 401.
  Future<UserProfile> validateAndRestoreSession() async {
    final hasToken = await _storage.hasToken();
    dev.log('[AUTH] validateAndRestoreSession: hasToken=$hasToken', name: 'AuthRepository');
    if (!hasToken) {
      throw const SessionExpiredException();
    }

    try {
      return await _fetchProfile();
    } on UnauthorizedException {
      dev.log('[AUTH] validateAndRestoreSession: 401 — attempting token refresh', name: 'AuthRepository');
      // Access token expired — attempt refresh
      return await _tryRefreshAndFetchProfile();
    } on SessionExpiredException {
      rethrow;
    }
  }

  Future<UserProfile> _tryRefreshAndFetchProfile() async {
    try {
      final refreshed = await refreshSession();
      await _storage.setAccessToken(refreshed.accessToken);
      await _storage.setRefreshToken(refreshed.refreshToken);
      return await _fetchProfile();
    } on AppException {
      // Refresh also failed — session fully expired
      await _storage.clearAll();
      throw const SessionExpiredException();
    }
  }
}

/// Provider for AuthRepository.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    supabaseClient: ref.watch(supabaseAuthClientProvider),
    apiClient: ref.watch(apiClientProvider),
    storage: ref.watch(secureStorageProvider),
  );
});
