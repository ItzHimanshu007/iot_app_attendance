/// App-wide constants — no magic strings/numbers in feature code.
class AppConstants {
  AppConstants._();

  // ── Roles ──────────────────────────────────────────────────────────────────
  static const String roleStudent = 'student';
  static const String roleTeacher = 'teacher';
  static const String roleAdmin = 'admin';

  // ── Attendance statuses ────────────────────────────────────────────────────
  static const String statusPresent = 'present';
  static const String statusLate = 'late';
  static const String statusAbsent = 'absent';
  static const String statusRevoked = 'revoked';

  // ── Session statuses ───────────────────────────────────────────────────────
  static const String sessionActive = 'active';
  static const String sessionCompleted = 'completed';
  static const String sessionCancelled = 'cancelled';

  // ── Storage keys ───────────────────────────────────────────────────────────
  static const String keyAccessToken = 'access_token';
  static const String keyRefreshToken = 'refresh_token';
  static const String keyUserRole = 'user_role';
  static const String keyUserId = 'user_id';
  static const String keyDeviceFingerprint = 'device_fingerprint';
  static const String keyDeviceId = 'device_id';
  static const String keyDeviceRegistered = 'device_registered';
  static const String keyDeviceAndroidId = 'device_android_id';
  static const String keyOnboardingComplete = 'onboarding_complete';

  static const String keyLastAttendanceTime = 'last_attendance_time';
  static const String keyLastClassroom = 'last_classroom';
  static const String keyTotalSubmissions = 'total_submissions';
  static const String keySuccessfulSubmissions = 'successful_submissions';

  // ── Durations ──────────────────────────────────────────────────────────────
  static const Duration snackBarDuration = Duration(seconds: 3);
  static const Duration animationDuration = Duration(milliseconds: 300);
  static const Duration splashDuration = Duration(seconds: 2);

  // ── Pagination ─────────────────────────────────────────────────────────────
  static const int defaultPageSize = 20;
}
