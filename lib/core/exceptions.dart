/// Typed error hierarchy — every API and service error maps to one of these.
sealed class AppException implements Exception {
  const AppException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'AppException($code): $message';
}

// ── Auth ─────────────────────────────────────────────────────────────────────

class AuthException extends AppException {
  const AuthException(super.message, {super.code});
}

class SessionExpiredException extends AuthException {
  const SessionExpiredException()
      : super('Session expired. Please sign in again.', code: 'SESSION_EXPIRED');
}

class UnauthorizedException extends AuthException {
  const UnauthorizedException([String message = 'Unauthorized'])
      : super(message, code: 'UNAUTHORIZED');
}

class ForbiddenException extends AuthException {
  const ForbiddenException([String message = 'Access denied'])
      : super(message, code: 'FORBIDDEN');
}

// ── Network ──────────────────────────────────────────────────────────────────

class NetworkException extends AppException {
  const NetworkException([String message = 'No internet connection'])
      : super(message, code: 'NETWORK_ERROR');
}

class TimeoutException extends AppException {
  const TimeoutException([String message = 'Request timed out'])
      : super(message, code: 'TIMEOUT');
}

class ServerException extends AppException {
  const ServerException(super.message, {super.code, this.statusCode});
  final int? statusCode;
}

// ── Validation ───────────────────────────────────────────────────────────────

class ValidationException extends AppException {
  const ValidationException(super.message, {super.code, this.fieldErrors});
  final Map<String, String>? fieldErrors;
}

// ── Domain ───────────────────────────────────────────────────────────────────

class NotFoundException extends AppException {
  const NotFoundException([String message = 'Resource not found'])
      : super(message, code: 'NOT_FOUND');
}

class ConflictException extends AppException {
  const ConflictException(super.message, {super.code});
}

class DeviceException extends AppException {
  const DeviceException(super.message, {super.code});
}

// ── Generic ──────────────────────────────────────────────────────────────────

class UnexpectedException extends AppException {
  const UnexpectedException([String message = 'Something went wrong'])
      : super(message, code: 'UNEXPECTED');
}
