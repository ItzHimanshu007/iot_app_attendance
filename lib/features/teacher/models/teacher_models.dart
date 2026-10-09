// Teacher session management models.
//
// All DTOs mirror the backend schema exactly:
//   backend/app/schemas/session.py
//   backend/app/schemas/course.py

import '../../../core/constants.dart';

// ── Subject ───────────────────────────────────────────────────────────────────

/// Subject — mirrors backend SubjectResponse.
class Subject {
  const Subject({
    required this.id,
    required this.code,
    required this.name,
    required this.department,
    required this.isActive,
    this.semester,
    this.credits,
  });

  final String id;
  final String code;
  final String name;
  final String department;
  final bool isActive;
  final String? semester;
  final int? credits;

  String get displayName => '$code — $name';

  factory Subject.fromJson(Map<String, dynamic> json) {
    return Subject(
      id: json['id'] as String,
      code: json['code'] as String,
      name: json['name'] as String,
      department: json['department'] as String,
      isActive: json['is_active'] as bool? ?? true,
      semester: json['semester'] as String?,
      credits: json['credits'] as int?,
    );
  }
}

// ── Classroom ─────────────────────────────────────────────────────────────────

/// Classroom — mirrors backend classroom record.
class Classroom {
  const Classroom({
    required this.id,
    required this.name,
    required this.building,
    required this.floor,
    required this.capacity,
    required this.isActive,
  });

  final String id;
  final String name;
  final String building;
  final int floor;
  final int capacity;
  final bool isActive;

  String get displayName => '$building — $name';
  String get shortName => name;

  factory Classroom.fromJson(Map<String, dynamic> json) {
    return Classroom(
      id: json['id'] as String,
      name: json['name'] as String,
      building: json['building'] as String? ?? '',
      floor: json['floor'] as int? ?? 0,
      capacity: json['capacity'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

// ── Session Create Request ─────────────────────────────────────────────────────

/// Session creation payload — mirrors the updated backend SessionCreate schema.
///
/// [subjectName] is the free-text subject name typed by the teacher.
/// The backend now accepts `subject_name` directly; `subject_id` is no longer
/// required or sent.
class SessionCreateRequest {
  const SessionCreateRequest({
    required this.subjectName,
    required this.classroomId,
    required this.durationMinutes,
    this.timetableId,
    this.notes,
  });

  /// Free-text subject name entered by the teacher (trimmed, 3–100 chars).
  final String subjectName;
  final String classroomId;
  final int durationMinutes;   // 1–480 minutes
  final String? timetableId;
  final String? notes;

  Map<String, dynamic> toJson() => {
        'subject_name': subjectName,
        'classroom_id': classroomId,
        'duration_minutes': durationMinutes,
        if (timetableId != null) 'timetable_id': timetableId,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
      };
}

// ── Session Response ──────────────────────────────────────────────────────────

/// Active / completed session — mirrors backend SessionResponse.
///
/// [subjectName] is the free-text subject name (present for sessions created
/// after the backend migration).
///
/// [subjectId] is kept nullable for backward-compatibility with historical
/// sessions that were created before the migration.  New sessions will have
/// [subjectName] populated and [subjectId] null.
///
/// Always use [displaySubjectName] when showing the subject to the user —
/// it provides the correct fallback chain without ever exposing a UUID.
class AttendanceSession {
  const AttendanceSession({
    required this.id,
    required this.teacherId,
    required this.classroomId,
    required this.status,
    required this.startedAt,
    required this.expiresAt,
    required this.durationMinutes,
    required this.totalPresent,
    required this.createdAt,
    this.subjectName,
    this.subjectId,
    this.timetableId,
    this.endedAt,
    this.notes,
  });

  final String id;
  final String teacherId;

  /// Free-text subject name (new sessions). Null for historical sessions.
  final String? subjectName;

  /// Legacy UUID subject reference (historical sessions only). Nullable.
  final String? subjectId;

  final String classroomId;
  final String status;         // 'active' | 'completed' | 'cancelled'
  final DateTime startedAt;
  final DateTime expiresAt;
  final int durationMinutes;
  final int totalPresent;
  final DateTime createdAt;
  final String? timetableId;
  final DateTime? endedAt;
  final String? notes;

  /// The subject label to display in the UI.
  ///
  /// Priority:
  ///   1. [subjectName] — populated by new sessions.
  ///   2. 'Unknown Subject' — shown for historical sessions whose subject
  ///      record was not resolved (backend returns resolved name or this
  ///      sentinel for orphaned records).
  String get displaySubjectName => subjectName ?? 'Unknown Subject';

  bool get isActive => status == AppConstants.sessionActive;
  bool get isCompleted => status == AppConstants.sessionCompleted;

  /// Remaining time — null if session is not active.
  Duration? get remainingTime {
    if (!isActive) return null;
    final remaining = expiresAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Progress fraction [0.0, 1.0] — how much of the session has elapsed.
  double get elapsedFraction {
    final total = expiresAt.difference(startedAt).inSeconds;
    if (total <= 0) return 1.0;
    final elapsed = DateTime.now().difference(startedAt).inSeconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  bool get isExpired =>
      isActive && DateTime.now().isAfter(expiresAt);

  factory AttendanceSession.fromJson(Map<String, dynamic> json) {
    return AttendanceSession(
      id: json['id'] as String,
      teacherId: json['teacher_id'] as String,
      // New field — populated by the backend for sessions after the migration.
      subjectName: json['subject_name'] as String?,
      // Legacy field — may be absent or null for post-migration sessions.
      subjectId: json['subject_id'] as String?,
      classroomId: json['classroom_id'] as String,
      status: json['status'] as String,
      startedAt: DateTime.parse(json['started_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
      durationMinutes: json['duration_minutes'] as int,
      totalPresent: json['total_present'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      timetableId: json['timetable_id'] as String?,
      endedAt: json['ended_at'] != null
          ? DateTime.parse(json['ended_at'] as String)
          : null,
      notes: json['notes'] as String?,
    );
  }
}

// ── Session Status ────────────────────────────────────────────────────────────

/// Session status from GET /sessions/{id}/status — includes live remaining time.
class SessionStatus {
  const SessionStatus({
    required this.sessionId,
    required this.status,
    required this.totalPresent,
    this.remainingSeconds,
  });

  final String sessionId;
  final String status;
  final int totalPresent;
  final int? remainingSeconds;

  bool get isActive => status == AppConstants.sessionActive;

  Duration get remainingDuration =>
      Duration(seconds: remainingSeconds ?? 0);

  factory SessionStatus.fromJson(Map<String, dynamic> json) {
    return SessionStatus(
      sessionId: json['session_id'] as String? ?? json['id'] as String,
      status: json['status'] as String,
      totalPresent: json['total_present'] as int? ?? 0,
      remainingSeconds: json['remaining_seconds'] as int?,
    );
  }
}

// ── Token Rotation Result ─────────────────────────────────────────────────────

/// Result from POST /sessions/{id}/rotate-token.
class TokenRotationResult {
  const TokenRotationResult({
    required this.sessionId,
    required this.rotatedAt,
    this.newTokenPreview,
  });

  final String sessionId;
  final DateTime rotatedAt;
  final String? newTokenPreview; // first 6 chars of new token, masked rest

  factory TokenRotationResult.fromJson(Map<String, dynamic> json) {
    final token = json['new_token'] as String?;
    return TokenRotationResult(
      sessionId: json['session_id'] as String? ??
          json['id'] as String? ?? '',
      rotatedAt: json['rotated_at'] != null
          ? DateTime.parse(json['rotated_at'] as String)
          : DateTime.now(),
      newTokenPreview: token != null && token.length >= 6
          ? '${token.substring(0, 6)}••••••••••'
          : token,
    );
  }
}

// ── Session End Result ────────────────────────────────────────────────────────

/// Result from PATCH /sessions/{id}/end — mirrors SessionEnd schema.
class SessionEndResult {
  const SessionEndResult({
    required this.sessionId,
    required this.status,
    required this.totalPresent,
  });

  final String sessionId;
  final String status;
  final int totalPresent;

  factory SessionEndResult.fromJson(Map<String, dynamic> json) {
    return SessionEndResult(
      sessionId: json['session_id'] as String,
      status: json['status'] as String,
      totalPresent: json['total_present'] as int? ?? 0,
    );
  }
}

// ── Timetable Entry (client-side aggregation) ─────────────────────────────────

/// A timetable slot — built client-side from subjects + classrooms.
/// The backend does not expose a dedicated timetable list endpoint;
/// teachers use sessions history as their "timetable".
class TimetableEntry {
  const TimetableEntry({
    required this.subject,
    required this.classroom,
    required this.dayOfWeek,
    required this.startHour,
    required this.startMinute,
    required this.durationMinutes,
    this.timetableId,
  });

  final Subject subject;
  final Classroom classroom;
  final int dayOfWeek;       // 1=Mon … 7=Sun
  final int startHour;
  final int startMinute;
  final int durationMinutes;
  final String? timetableId;

  String get dayName {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[(dayOfWeek - 1).clamp(0, 6)];
  }

  String get timeLabel {
    final h = startHour.toString().padLeft(2, '0');
    final m = startMinute.toString().padLeft(2, '0');
    final endMin = startMinute + durationMinutes;
    final endH = (startHour + endMin ~/ 60).toString().padLeft(2, '0');
    final endM = (endMin % 60).toString().padLeft(2, '0');
    return '$h:$m – $endH:$endM';
  }

  bool get isNow {
    final now = DateTime.now();
    if (now.weekday != dayOfWeek) return false;
    final startTotal = startHour * 60 + startMinute;
    final endTotal = startTotal + durationMinutes;
    final nowTotal = now.hour * 60 + now.minute;
    return nowTotal >= startTotal && nowTotal < endTotal;
  }
}
