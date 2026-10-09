// Auth models — data classes for auth layer.
//
// These mirror the Supabase Auth REST API response and the
// FastAPI UserProfile schema (backend/app/schemas/user.py).

class LoginRequest {
  const LoginRequest({required this.email, required this.password});

  final String email;
  final String password;

  Map<String, dynamic> toJson() => {
        'email': email,
        'password': password,
      };
}

/// Supabase Auth token response.
///
/// Matches: POST /auth/v1/token?grant_type=password
class AuthTokenResponse {
  const AuthTokenResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.tokenType,
    required this.userId,
    required this.email,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final String tokenType;
  final String userId;
  final String email;

  factory AuthTokenResponse.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? {};
    return AuthTokenResponse(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      expiresIn: json['expires_in'] as int? ?? 3600,
      tokenType: json['token_type'] as String? ?? 'bearer',
      userId: user['id'] as String? ?? json['user_id'] as String? ?? '',
      email: user['email'] as String? ?? '',
    );
  }
}

/// Supabase Auth token refresh response.
///
/// Matches: POST /auth/v1/token?grant_type=refresh_token
class RefreshTokenResponse {
  const RefreshTokenResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn;

  factory RefreshTokenResponse.fromJson(Map<String, dynamic> json) {
    return RefreshTokenResponse(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      expiresIn: json['expires_in'] as int? ?? 3600,
    );
  }
}

/// User profile from FastAPI backend.
///
/// Matches: GET /api/v1/users/me (backend/app/schemas/user.py → UserProfile)
class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.isActive,
    required this.createdAt,
    this.department,
    this.studentIdNumber,
    this.phone,
  });

  final String id;
  final String email;
  final String fullName;
  final String role;
  final bool isActive;
  final DateTime createdAt;
  final String? department;
  final String? studentIdNumber;
  final String? phone;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String,
      role: json['role'] as String,
      isActive: json['is_active'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      department: json['department'] as String?,
      studentIdNumber: json['student_id_number'] as String?,
      phone: json['phone'] as String?,
    );
  }

  /// Display-friendly role label.
  String get roleLabel {
    switch (role) {
      case 'teacher':
        return 'Teacher';
      case 'admin':
        return 'Administrator';
      case 'student':
      default:
        return 'Student';
    }
  }

  /// Initials for avatar display (up to 2 chars).
  String get initials {
    final parts = fullName.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }
}
