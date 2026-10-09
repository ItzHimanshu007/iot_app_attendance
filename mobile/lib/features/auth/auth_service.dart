import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin wrapper over Supabase Auth with friendly error messages.
class AuthService {
  GoTrueClient get _auth => Supabase.instance.client.auth;

  Future<void> signIn(String email, String password) async {
    try {
      await _auth.signInWithPassword(email: email.trim(), password: password);
    } on AuthException catch (e) {
      throw Exception(_friendly(e.message));
    }
  }

  /// Returns true when the project requires email confirmation first.
  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
    required String employeeId,
    String? department,
    String? designation,
    String? phone,
  }) async {
    try {
      final response = await _auth.signUp(
        email: email.trim(),
        password: password,
        // Read by the `handle_new_user` trigger to create the staff profile.
        data: {
          'full_name': fullName.trim(),
          'employee_id': employeeId.trim(),
          if (department != null && department.trim().isNotEmpty) 'department': department.trim(),
          if (designation != null && designation.trim().isNotEmpty)
            'designation': designation.trim(),
          if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        },
      );
      return response.session == null;
    } on AuthException catch (e) {
      throw Exception(_friendly(e.message));
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      await _auth.resetPasswordForEmail(email.trim());
    } on AuthException catch (e) {
      throw Exception(_friendly(e.message));
    }
  }

  Future<void> signOut() => _auth.signOut();

  String _friendly(String message) {
    final m = message.toLowerCase();
    if (m.contains('invalid login credentials')) return 'Wrong email or password.';
    if (m.contains('email not confirmed')) {
      return 'Please confirm your email first — check your inbox.';
    }
    if (m.contains('already registered') || m.contains('already been registered')) {
      return 'An account with this email already exists.';
    }
    if (m.contains('database error saving new user')) {
      return 'Could not create the account. This employee ID may already be registered.';
    }
    if (m.contains('password should be')) return message;
    if (m.contains('rate limit') || m.contains('too many')) {
      return 'Too many attempts. Please wait a minute and try again.';
    }
    return message;
  }
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService());
