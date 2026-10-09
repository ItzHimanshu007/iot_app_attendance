// Teacher reports & analytics models.
//
// Analytics are computed client-side from:
//   GET /sessions/        → List<AttendanceSession>
//   GET /attendance/session/{id} → List<AttendanceRecord>
//   GET /subjects/        → List<Subject>
//
// No dedicated analytics endpoint — all aggregation happens here.

import '../../teacher/models/teacher_models.dart';

// ── Raw Attendance Record (from backend) ──────────────────────────────────────

/// Single attendance record from GET /attendance/session/{id}.
/// Mirrors backend AttendanceResponse schema.
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
  final String status;
  final String verificationMethod;
  final bool biometricVerified;
  final DateTime markedAt;
  final DateTime createdAt;
  final int? bleRssi;
  final DateTime? verifiedAt;
  final String? rejectionReason;

  bool get isPresent => status == 'present' || status == 'late';

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
}

// ── Summary Analytics ─────────────────────────────────────────────────────────

/// Top-level summary for the reports dashboard.
class AttendanceSummary {
  const AttendanceSummary({
    required this.totalSessions,
    required this.totalUniqueStudents,
    required this.averageAttendanceRate,
    required this.studentsBelow75,
    required this.studentsBelow50,
    required this.totalPresentCount,
    required this.generatedAt,
  });

  final int totalSessions;
  final int totalUniqueStudents;
  final double averageAttendanceRate; // 0.0–1.0
  final int studentsBelow75;
  final int studentsBelow50;
  final int totalPresentCount;
  final DateTime generatedAt;

  String get averageRatePercent =>
      '${(averageAttendanceRate * 100).toStringAsFixed(1)}%';
}

// ── Subject Analytics ─────────────────────────────────────────────────────────

/// Per-subject aggregated attendance analytics.
class SubjectAnalytics {
  const SubjectAnalytics({
    required this.subject,
    required this.totalSessions,
    required this.averageAttendance,
    required this.highestAttendance,
    required this.lowestAttendance,
    required this.attendanceRate,
    required this.sessionHistory,
  });

  final Subject subject;
  final int totalSessions;
  final double averageAttendance;  // average student count per session
  final int highestAttendance;
  final int lowestAttendance;
  final double attendanceRate;     // 0.0–1.0 — fraction of max capacity
  final List<SessionDataPoint> sessionHistory;

  String get attendanceRatePercent =>
      '${(attendanceRate * 100).toStringAsFixed(1)}%';
}

/// A single {date, count} data point for trend charts.
class SessionDataPoint {
  const SessionDataPoint({
    required this.date,
    required this.count,
    required this.sessionId,
  });

  final DateTime date;
  final int count;
  final String sessionId;
}

// ── Student Analytics ─────────────────────────────────────────────────────────

/// Per-student attendance analytics across all sessions.
class StudentAnalytics {
  const StudentAnalytics({
    required this.studentId,
    required this.totalSessions,
    required this.sessionsAttended,
    required this.sessionsMissed,
    required this.attendanceRate,
    this.studentName,
  });

  final String studentId;
  final int totalSessions;
  final int sessionsAttended;
  final int sessionsMissed;
  final double attendanceRate; // 0.0–1.0

  /// Derived display name — falls back to truncated ID.
  final String? studentName;

  String get displayName =>
      studentName ?? studentId.substring(0, 8).toUpperCase();

  String get attendancePercent =>
      '${(attendanceRate * 100).toStringAsFixed(1)}%';

  bool get isBelowThreshold75 => attendanceRate < 0.75;
  bool get isBelowThreshold50 => attendanceRate < 0.50;

  AttendanceThreshold get threshold {
    if (isBelowThreshold50) return AttendanceThreshold.critical;
    if (isBelowThreshold75) return AttendanceThreshold.warning;
    return AttendanceThreshold.good;
  }
}

enum AttendanceThreshold { good, warning, critical }

// ── Session Analytics ─────────────────────────────────────────────────────────

/// Per-session analytics — date, subject, classroom, count.
class SessionAnalytics {
  const SessionAnalytics({
    required this.session,
    required this.attendanceCount,
    required this.attendanceRate,
    required this.subjectCode,
    required this.classroomName,
  });

  final AttendanceSession session;
  final int attendanceCount;
  final double attendanceRate;
  final String subjectCode;
  final String classroomName;

  String get dateLabel {
    final dt = session.startedAt;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]}, $h:$m';
  }
}

// ── Trend Data ────────────────────────────────────────────────────────────────

/// Full trend dataset — ordered by date for line charts.
class AttendanceTrendData {
  const AttendanceTrendData({
    required this.points,
    required this.maxCount,
    required this.minCount,
    required this.averageCount,
  });

  final List<SessionDataPoint> points;
  final int maxCount;
  final int minCount;
  final double averageCount;

  bool get hasData => points.isNotEmpty;
}

// ── Export DTOs ───────────────────────────────────────────────────────────────

/// Export-ready DTO — serialize to JSON/CSV for future PDF/Excel generation.
class AttendanceExport {
  const AttendanceExport({
    required this.exportedAt,
    required this.teacherId,
    required this.sessions,
    required this.students,
    required this.subjects,
  });

  final DateTime exportedAt;
  final String teacherId;
  final List<SessionAttendanceExport> sessions;
  final List<StudentAttendanceExport> students;
  final List<SubjectAttendanceExport> subjects;

  Map<String, dynamic> toJson() => {
        'exported_at': exportedAt.toIso8601String(),
        'teacher_id': teacherId,
        'sessions': sessions.map((s) => s.toJson()).toList(),
        'students': students.map((s) => s.toJson()).toList(),
        'subjects': subjects.map((s) => s.toJson()).toList(),
      };
}

class SessionAttendanceExport {
  const SessionAttendanceExport({
    required this.sessionId,
    required this.subjectCode,
    required this.classroomName,
    required this.date,
    required this.presentCount,
    required this.durationMinutes,
  });

  final String sessionId;
  final String subjectCode;
  final String classroomName;
  final DateTime date;
  final int presentCount;
  final int durationMinutes;

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'subject_code': subjectCode,
        'classroom_name': classroomName,
        'date': date.toIso8601String(),
        'present_count': presentCount,
        'duration_minutes': durationMinutes,
      };
}

class StudentAttendanceExport {
  const StudentAttendanceExport({
    required this.studentId,
    required this.sessionsAttended,
    required this.totalSessions,
    required this.attendancePercent,
  });

  final String studentId;
  final int sessionsAttended;
  final int totalSessions;
  final double attendancePercent;

  Map<String, dynamic> toJson() => {
        'student_id': studentId,
        'sessions_attended': sessionsAttended,
        'total_sessions': totalSessions,
        'attendance_percent': attendancePercent,
      };
}

class SubjectAttendanceExport {
  const SubjectAttendanceExport({
    required this.subjectId,
    required this.subjectCode,
    required this.totalSessions,
    required this.averageAttendance,
    required this.attendanceRate,
  });

  final String subjectId;
  final String subjectCode;
  final int totalSessions;
  final double averageAttendance;
  final double attendanceRate;

  Map<String, dynamic> toJson() => {
        'subject_id': subjectId,
        'subject_code': subjectCode,
        'total_sessions': totalSessions,
        'average_attendance': averageAttendance,
        'attendance_rate': attendanceRate,
      };
}
