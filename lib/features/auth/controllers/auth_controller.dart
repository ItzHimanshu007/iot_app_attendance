import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/exceptions.dart';
import '../../../services/secure_storage_service.dart';
import '../models/auth_models.dart';
import '../repository/auth_repository.dart';

/// Result returned from [AuthController.register].
class RegisterOutcome {
  const RegisterOutcome({this.error, this.needsEmailVerification = false});

  /// Non-null when registration failed.
  final String? error;

  /// True when Supabase requires email confirmation before sign-in.
  final bool needsEmailVerification;

  bool get isSuccess => error == null;
}

/// Full auth state including the user profile once loaded.
class AuthSessionState {
  const AuthSessionState({
    this.status = AuthStatus.loading,
    this.isInitializing = true,
    this.profile,
    this.errorMessage,
  });

  final AuthStatus status;

  /// True only during app startup session restore.
  /// False during login() so GoRouter does NOT redirect to splash mid-login.
  final bool isInitializing;

  final UserProfile? profile;
  final String? errorMessage;

  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get isLoading => status == AuthStatus.loading;
  bool get isUnauthenticated => status == AuthStatus.unauthenticated;
  bool get hasError => status == AuthStatus.error;

  String? get role => profile?.role;

  AuthSessionState copyWith({
    AuthStatus? status,
    bool? isInitializing,
    UserProfile? profile,
    String? errorMessage,
  }) {
    return AuthSessionState(
      status: status ?? this.status,
      isInitializing: isInitializing ?? this.isInitializing,
      profile: profile ?? this.profile,
      errorMessage: errorMessage,
    );
  }
}

enum AuthStatus { loading, authenticated, unauthenticated, error }

/// Auth controller — manages the full authentication lifecycle.
///
/// Exposed as a StateNotifier so GoRouter can listen reactively.
/// All business logic lives here, not in widgets.
class AuthController extends StateNotifier<AuthSessionState> {
  AuthController({
    required AuthRepository repository,
    required SecureStorageService storage,
  })  : _repo = repository,
        _storage = storage,
        super(const AuthSessionState()) {
    // Auto-initialize session on construction
    initializeSession();
  }

  final AuthRepository _repo;
  final SecureStorageService _storage;

  // ── Session Initialization ────────────────────────────────────────────────

  /// Called on app launch — restores session from secure storage.
  ///
  /// Flow:
  ///   1. Read stored access token
  ///   2. Call FastAPI /users/me to validate + get profile
  ///   3. If 401 → try refresh token → retry
  ///   4. If all fails → unauthenticated
  Future<void> initializeSession() async {
    dev.log('[AUTH] initializeSession: start', name: 'AuthController');
    // isInitializing=true → GoRouter redirects to splash while we load
    state = const AuthSessionState(status: AuthStatus.loading, isInitializing: true);
    try {
      final profile = await _repo.validateAndRestoreSession();
      // Persist role in case it changed on the server
      await _storage.setUserRole(profile.role);
      await _storage.setUserId(profile.id);
      dev.log('[AUTH] initializeSession: session valid — role=${profile.role} id=${profile.id}', name: 'AuthController');
      state = AuthSessionState(
        status: AuthStatus.authenticated,
        isInitializing: false,
        profile: profile,
      );
    } on SessionExpiredException {
      dev.log('[AUTH] initializeSession: session expired → unauthenticated', name: 'AuthController');
      state = const AuthSessionState(status: AuthStatus.unauthenticated, isInitializing: false);
    } on NetworkException catch (e) {
      // No network on startup — restore from local storage if possible
      dev.log('[AUTH] initializeSession: network error (${e.message}) → restoring from local storage', name: 'AuthController');
      await _restoreFromLocalStorage();
    } catch (e) {
      dev.log('[AUTH] initializeSession: unexpected error → unauthenticated: $e', name: 'AuthController');
      state = const AuthSessionState(status: AuthStatus.unauthenticated, isInitializing: false);
    }
  }

  /// Restore session identity from local storage when network is unavailable.
  Future<void> _restoreFromLocalStorage() async {
    final hasToken = await _storage.hasToken();
    final role = await _storage.getUserRole();
    final userId = await _storage.getUserId();

    if (hasToken && role != null && userId != null) {
      dev.log('[AUTH] restoreFromLocalStorage: restored cached session — role=$role id=$userId', name: 'AuthController');
      // Provide a minimal profile from cache — profile screen will retry
      state = AuthSessionState(
        status: AuthStatus.authenticated,
        isInitializing: false,
        profile: UserProfile(
          id: userId,
          email: '',
          fullName: 'Cached User',
          role: role,
          isActive: true,
          createdAt: DateTime.now(),
        ),
      );
    } else {
      dev.log('[AUTH] restoreFromLocalStorage: no cached session → unauthenticated', name: 'AuthController');
      state = const AuthSessionState(status: AuthStatus.unauthenticated, isInitializing: false);
    }
  }

  // ── Login ─────────────────────────────────────────────────────────────────

  /// Login with email and password.
  ///
  /// On success → authenticated state with full profile.
  /// On failure → returns the error message (does NOT throw).
  ///
  /// IMPORTANT: We do NOT set AuthStatus.loading here.
  /// Setting loading would cause GoRouter to redirect to /splash mid-login,
  /// producing a blink: /login → /splash → /login.
  /// The LoginScreen manages its own loading spinner independently.
  Future<String?> login({
    required String email,
    required String password,
  }) async {
    dev.log('[LOGIN] signIn start — email=$email', name: 'AuthController');

    try {
      final result = await _repo.login(email: email, password: password);
      final tokens = result.tokens;
      final profile = result.profile;

      dev.log('[LOGIN] signIn success — userId=${tokens.userId}', name: 'AuthController');
      dev.log('[LOGIN] session received — role=${profile.role}', name: 'AuthController');

      // Persist all session data
      await _storage.saveTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      await _storage.setUserId(profile.id);
      await _storage.setUserRole(profile.role);

      dev.log('[LOGIN] token persisted — storage write complete', name: 'AuthController');

      state = AuthSessionState(
        status: AuthStatus.authenticated,
        isInitializing: false,
        profile: profile,
      );

      dev.log('[AUTH] auth state → authenticated — role=${profile.role}', name: 'AuthController');
      return null; // No error

    } on AuthException catch (e) {
      dev.log('[LOGIN] signIn FAILED (AuthException): ${e.message}', name: 'AuthController');
      state = const AuthSessionState(status: AuthStatus.unauthenticated, isInitializing: false);
      return e.message;
    } on ValidationException catch (e) {
      dev.log('[LOGIN] signIn FAILED (ValidationException): ${e.message}', name: 'AuthController');
      state = const AuthSessionState(status: AuthStatus.unauthenticated, isInitializing: false);
      return e.message;
    } on NetworkException catch (e) {
      dev.log('[LOGIN] signIn FAILED (NetworkException): ${e.message} — check if FastAPI server is reachable from this device', name: 'AuthController');
      state = const AuthSessionState(status: AuthStatus.unauthenticated, isInitializing: false);
      return 'Cannot reach server. Is your phone on the same network as the server?';
    } on TimeoutException catch (e) {
      dev.log('[LOGIN] signIn FAILED (TimeoutException): ${e.message}', name: 'AuthController');
      state = const AuthSessionState(status: AuthStatus.unauthenticated, isInitializing: false);
      return 'Server did not respond. Please try again.';
    } on ServerException catch (e) {
      dev.log('[LOGIN] signIn FAILED (ServerException ${e.statusCode}): ${e.message}', name: 'AuthController');
      if (e.statusCode == 429) {
        state = const AuthSessionState(status: AuthStatus.unauthenticated, isInitializing: false);
        return 'Too many login attempts. Please wait and try again.';
      }
      state = const AuthSessionState(status: AuthStatus.unauthenticated, isInitializing: false);
      return 'Server error. Please try again later.';
    } catch (e) {
      dev.log('[LOGIN] signIn FAILED (unexpected): $e', name: 'AuthController', error: e);
      state = const AuthSessionState(status: AuthStatus.unauthenticated, isInitializing: false);
      return 'An unexpected error occurred: $e';
    }
  }

  // ── Registration ───────────────────────────────────────────────────────────

  /// Create a new student or teacher account.
  ///
  /// On success → [RegisterOutcome] with `isSuccess = true`.
  /// On failure → [RegisterOutcome] with `error` set (does NOT throw).
  Future<RegisterOutcome> register({
    required String email,
    required String password,
    required String fullName,
    required String role,
    String? studentIdNumber,
    String? department,
  }) async {
    dev.log('[REGISTER] start — email=$email role=$role', name: 'AuthController');
    try {
      final result = await _repo.register(
        email: email,
        password: password,
        fullName: fullName,
        role: role,
        studentIdNumber: studentIdNumber,
        department: department,
      );
      dev.log('[REGISTER] success — needsVerification=${result.needsEmailVerification}', name: 'AuthController');
      return RegisterOutcome(needsEmailVerification: result.needsEmailVerification);
    } on AuthException catch (e) {
      dev.log('[REGISTER] AuthException: ${e.message}', name: 'AuthController');
      return RegisterOutcome(error: e.message);
    } on ValidationException catch (e) {
      dev.log('[REGISTER] ValidationException: ${e.message}', name: 'AuthController');
      return RegisterOutcome(error: e.message);
    } on NetworkException {
      dev.log('[REGISTER] NetworkException', name: 'AuthController');
      return RegisterOutcome(error: 'Cannot reach server. Check your internet connection.');
    } on ServerException catch (e) {
      dev.log('[REGISTER] ServerException ${e.statusCode}', name: 'AuthController');
      if (e.statusCode == 422 || e.statusCode == 400) {
        return RegisterOutcome(error: 'An account with this email already exists.');
      }
      return RegisterOutcome(error: 'Server error. Please try again later.');
    } catch (e) {
      dev.log('[REGISTER] unexpected: $e', name: 'AuthController', error: e);
      return RegisterOutcome(error: 'Registration failed: ${e.toString()}');
    }
  }

  // ── Password Reset ──────────────────────────────────────────────────────────

  /// Send a password-reset email.
  ///
  /// Returns null on success, or an error message string.
  Future<String?> forgotPassword(String email) async {
    dev.log('[AUTH] forgotPassword: $email', name: 'AuthController');
    try {
      await _repo.forgotPassword(email);
      return null;
    } on NetworkException {
      return 'Cannot reach server. Check your internet connection.';
    } catch (e) {
      return 'Failed to send reset email. Please try again.';
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  /// Sign out — clears all local state and invalidates server session.
  Future<void> logout() async {
    dev.log('[AUTH] logout: start', name: 'AuthController');
    state = const AuthSessionState(status: AuthStatus.loading, isInitializing: false);
    await _repo.logout();
    dev.log('[AUTH] logout: complete → unauthenticated', name: 'AuthController');
    state = const AuthSessionState(status: AuthStatus.unauthenticated, isInitializing: false);
  }

  // ── Profile Refresh ───────────────────────────────────────────────────────

  /// Re-fetch the user profile from the server.
  Future<void> refreshProfile() async {
    try {
      final profile = await _repo.getProfile();
      state = state.copyWith(profile: profile);
    } catch (_) {
      // Silently ignore — profile refresh is non-critical
    }
  }
}

/// Primary auth controller provider — single source of truth for auth state.
final authControllerProvider =
    StateNotifierProvider<AuthController, AuthSessionState>((ref) {
  return AuthController(
    repository: ref.watch(authRepositoryProvider),
    storage: ref.watch(secureStorageProvider),
  );
});

/// Convenience provider — current user profile (null if not authenticated).
final currentUserProvider = Provider<UserProfile?>((ref) {
  return ref.watch(authControllerProvider).profile;
});

/// Convenience provider — current user role (null if not authenticated).
final currentRoleProvider = Provider<String?>((ref) {
  return ref.watch(authControllerProvider).profile?.role;
});
