// Attendance submission models.
//
// AttendanceMarkRequest mirrors backend/app/schemas/attendance.py → AttendanceMark
// AttendanceRecord      mirrors backend/app/schemas/attendance.py → AttendanceResponse

import '../../../core/constants.dart';

// ── Request ───────────────────────────────────────────────────────────────────

/// Attendance submission payload — sent to POST /attendance/.
///
/// All anti-fraud fields included: token, fingerprint, biometric flag, RSSI.
class AttendanceMarkRequest {
  const AttendanceMarkRequest({
    required this.sessionId,
    required this.beaconToken,
    required this.deviceFingerprint,
    required this.biometricVerified,
    this.bleRssi,
  });

  final String sessionId;
  final String beaconToken;       // 16-char hex from BLE payload
  final String deviceFingerprint; // SHA-256 hash — never raw IDs
  final bool biometricVerified;
  final int? bleRssi;

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'beacon_token': beaconToken,
        'device_fingerprint': deviceFingerprint,
        'biometric_verified': biometricVerified,
        if (bleRssi != null) 'ble_rssi': bleRssi,
      };
}

// ── Response ──────────────────────────────────────────────────────────────────

/// Attendance record returned from backend.
///
/// Mirrors backend/app/schemas/attendance.py → AttendanceResponse.
class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.sessionId,
    required this.studentId,
    required this.status,
    required this.verificationMethod,
    required this.biometricVerified,
    required this.markedAt,
    required this.createdAt,
    this.bleRssi,
    this.verifiedAt,
    this.rejectionReason,
  });

  final String id;
  final String sessionId;
  final String studentId;
  final String status;             // 'present' | 'late' | 'absent' | 'revoked'
  final String verificationMethod; // 'ble_biometric' | etc.
  final bool biometricVerified;
  final DateTime markedAt;
  final DateTime createdAt;
  final int? bleRssi;
  final DateTime? verifiedAt;
  final String? rejectionReason;

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      studentId: json['student_id'] as String,
      status: json['status'] as String,
      verificationMethod: json['verification_method'] as String? ?? 'ble',
      biometricVerified: json['biometric_verified'] as bool? ?? false,
      markedAt: DateTime.parse(json['marked_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      bleRssi: json['ble_rssi'] as int?,
      verifiedAt: json['verified_at'] != null
          ? DateTime.parse(json['verified_at'] as String)
          : null,
      rejectionReason: json['rejection_reason'] as String?,
    );
  }

  /// User-facing status label.
  String get statusLabel {
    switch (status) {
      case AppConstants.statusPresent: return 'Present';
      case AppConstants.statusLate:    return 'Late';
      case AppConstants.statusAbsent:  return 'Absent';
      case AppConstants.statusRevoked: return 'Revoked';
      default:                         return status;
    }
  }

  /// Whether the attendance was successfully recorded (not rejected).
  bool get isSuccessful =>
      status == AppConstants.statusPresent || status == AppConstants.statusLate;
}

// ── Local Analytics ───────────────────────────────────────────────────────────

/// Locally-tracked attendance analytics — stored in SecureStorage.
class AttendanceAnalytics {
  const AttendanceAnalytics({
    required this.totalSubmissions,
    required this.successfulSubmissions,
    this.lastAttendanceTime,
    this.lastClassroom,
  });

  const AttendanceAnalytics.empty()
      : totalSubmissions = 0,
        successfulSubmissions = 0,
        lastAttendanceTime = null,
        lastClassroom = null;

  final int totalSubmissions;
  final int successfulSubmissions;
  final DateTime? lastAttendanceTime;
  final String? lastClassroom;

  double get successRate => totalSubmissions == 0
      ? 0.0
      : successfulSubmissions / totalSubmissions;

  AttendanceAnalytics copyWith({
    int? totalSubmissions,
    int? successfulSubmissions,
    DateTime? lastAttendanceTime,
    String? lastClassroom,
  }) {
    return AttendanceAnalytics(
      totalSubmissions: totalSubmissions ?? this.totalSubmissions,
      successfulSubmissions:
          successfulSubmissions ?? this.successfulSubmissions,
      lastAttendanceTime: lastAttendanceTime ?? this.lastAttendanceTime,
      lastClassroom: lastClassroom ?? this.lastClassroom,
    );
  }
}

// ── Submission Pipeline Result ────────────────────────────────────────────────

/// Typed result of the full attendance submission pipeline.
sealed class AttendanceSubmissionResult {}

class AttendanceSubmitted extends AttendanceSubmissionResult {
  AttendanceSubmitted(this.record);
  final AttendanceRecord record;
}

class AttendanceRejected extends AttendanceSubmissionResult {
  AttendanceRejected(this.reason, {this.errorCode});
  final String reason;
  final String? errorCode;
}

/// Step currently executing in the pipeline — for animated progress UI.
enum AttendancePipelineStep {
  idle,
  validatingSession,
  checkingDevice,
  authenticatingBiometric,
  collectingFingerprint,
  submitting,
  complete,
  failed,
}

extension AttendancePipelineStepX on AttendancePipelineStep {
  String get label {
    switch (this) {
      case AttendancePipelineStep.idle:
        return 'Ready';
      case AttendancePipelineStep.validatingSession:
        return 'Validating session…';
      case AttendancePipelineStep.checkingDevice:
        return 'Checking device…';
      case AttendancePipelineStep.authenticatingBiometric:
        return 'Verify your identity…';
      case AttendancePipelineStep.collectingFingerprint:
        return 'Collecting fingerprint…';
      case AttendancePipelineStep.submitting:
        return 'Submitting attendance…';
      case AttendancePipelineStep.complete:
        return 'Attendance recorded!';
      case AttendancePipelineStep.failed:
        return 'Submission failed';
    }
  }

  bool get isActive => this != AttendancePipelineStep.idle &&
      this != AttendancePipelineStep.complete &&
      this != AttendancePipelineStep.failed;
}
