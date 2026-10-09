import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../services/secure_storage_service.dart';

/// Represents the current authentication state of the app.
class AuthState {
  const AuthState({
    this.isAuthenticated = false,
    this.isLoading = true,
    this.userId,
    this.role,
    this.errorMessage,
  });

  final bool isAuthenticated;
  final bool isLoading;
  final String? userId;
  final String? role;
  final String? errorMessage;

  bool get isStudent => role == AppConstants.roleStudent;
  bool get isTeacher => role == AppConstants.roleTeacher;
  bool get isAdmin => role == AppConstants.roleAdmin;

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    String? userId,
    String? role,
    String? errorMessage,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      userId: userId ?? this.userId,
      role: role ?? this.role,
      errorMessage: errorMessage,
    );
  }
}

/// Auth state notifier — manages authentication lifecycle.
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._storage) : super(const AuthState()) {
    _init();
  }

  final SecureStorageService _storage;

  Future<void> _init() async {
    try {
      final hasToken = await _storage.hasToken();
      if (hasToken) {
        final role = await _storage.getUserRole();
        final userId = await _storage.getUserId();
        state = AuthState(
          isAuthenticated: true,
          isLoading: false,
          role: role,
          userId: userId,
        );
      } else {
        state = const AuthState(isAuthenticated: false, isLoading: false);
      }
    } catch (_) {
      state = const AuthState(isAuthenticated: false, isLoading: false);
    }
  }

  /// Sign in — store tokens and update state.
  Future<void> signIn({
    required String accessToken,
    required String refreshToken,
    required String userId,
    required String role,
  }) async {
    state = state.copyWith(isLoading: true);
    await _storage.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    await _storage.setUserId(userId);
    await _storage.setUserRole(role);
    state = AuthState(
      isAuthenticated: true,
      isLoading: false,
      userId: userId,
      role: role,
    );
  }

  /// Sign out — clear all stored data and reset state.
  Future<void> signOut() async {
    state = state.copyWith(isLoading: true);
    await _storage.clearAll();
    state = const AuthState(isAuthenticated: false, isLoading: false);
  }

  /// Update the stored access token (e.g., after refresh).
  Future<void> updateAccessToken(String token) async {
    await _storage.setAccessToken(token);
  }
}

/// Global auth state provider.
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return AuthNotifier(storage);
});
