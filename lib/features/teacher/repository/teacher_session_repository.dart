import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/exceptions.dart';
import '../../../services/api_client.dart';
import '../models/teacher_models.dart';

// ── Interface ─────────────────────────────────────────────────────────────────

/// Interface for teacher session operations — enables mock injection.
abstract class TeacherSessionRepositoryInterface {
  Future<List<Subject>> getSubjects();
  Future<List<Classroom>> getClassrooms();
  Future<List<AttendanceSession>> getTimetable(); // sessions list as timetable
  Future<AttendanceSession> createSession(SessionCreateRequest request);
  Future<AttendanceSession> getSession(String sessionId);
  Future<SessionStatus> getSessionStatus(String sessionId);
  Future<TokenRotationResult> rotateToken(String sessionId);
  Future<SessionEndResult> closeSession(String sessionId);
}

// ── Real Implementation ───────────────────────────────────────────────────────

/// Teacher session repository — wraps FastAPI sessions + subjects + classrooms.
///
/// Endpoints used:
///   GET  /subjects/               → list subjects for dropdown
///   GET  /classrooms/             → list classrooms for dropdown
///   GET  /sessions/               → teacher's sessions (used as timetable)
///   POST /sessions/               → create attendance session
///   GET  /sessions/{id}           → single session
///   GET  /sessions/{id}/status    → live status + remaining time
///   POST /sessions/{id}/rotate-token → rotate BLE token
///   PATCH /sessions/{id}/end      → end session
class TeacherSessionRepository implements TeacherSessionRepositoryInterface {
  TeacherSessionRepository({required ApiClient apiClient})
      : _api = apiClient;

  final ApiClient _api;

  // ── Subjects ───────────────────────────────────────────────────────────────

  @override
  Future<List<Subject>> getSubjects() async {
    return _api.get<List<Subject>>(
      '/subjects/',
      fromJson: (data) {
        final items = data as List<dynamic>;
        return items
            .map((e) => Subject.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );
  }

  // ── Classrooms ─────────────────────────────────────────────────────────────

  @override
  Future<List<Classroom>> getClassrooms() async {
    return _api.get<List<Classroom>>(
      '/classrooms/',
      fromJson: (data) {
        final items = data as List<dynamic>;
        return items
            .map((e) => Classroom.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );
  }

  // ── Sessions List (as timetable) ───────────────────────────────────────────

  @override
  Future<List<AttendanceSession>> getTimetable() async {
    return _api.get<List<AttendanceSession>>(
      '/sessions/',
      fromJson: (data) {
        final items = data as List<dynamic>;
        return items
            .map((e) => AttendanceSession.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );
  }

  // ── Create Session ─────────────────────────────────────────────────────────

  @override
  Future<AttendanceSession> createSession(
      SessionCreateRequest request) async {
    return _api.post<AttendanceSession>(
      '/sessions/',
      data: request.toJson(),
      fromJson: (data) =>
          AttendanceSession.fromJson(data as Map<String, dynamic>),
    );
  }

  // ── Get Session ────────────────────────────────────────────────────────────

  @override
  Future<AttendanceSession> getSession(String sessionId) async {
    return _api.get<AttendanceSession>(
      '/sessions/$sessionId',
      fromJson: (data) =>
          AttendanceSession.fromJson(data as Map<String, dynamic>),
    );
  }

  // ── Session Status (polling) ───────────────────────────────────────────────

  @override
  Future<SessionStatus> getSessionStatus(String sessionId) async {
    return _api.get<SessionStatus>(
      '/sessions/$sessionId/status',
      fromJson: (data) {
        final map = data as Map<String, dynamic>;
        // Normalise: backend may return id instead of session_id
        if (!map.containsKey('session_id') && map.containsKey('id')) {
          map['session_id'] = map['id'];
        }
        return SessionStatus.fromJson(map);
      },
    );
  }

  // ── Rotate Token ───────────────────────────────────────────────────────────

  @override
  Future<TokenRotationResult> rotateToken(String sessionId) async {
    return _api.post<TokenRotationResult>(
      '/sessions/$sessionId/rotate-token',
      fromJson: (data) {
        final map = data as Map<String, dynamic>;
        return TokenRotationResult.fromJson(map);
      },
    );
  }

  // ── End Session ────────────────────────────────────────────────────────────

  @override
  Future<SessionEndResult> closeSession(String sessionId) async {
    return _api.patch<SessionEndResult>(
      '/sessions/$sessionId/end',
      fromJson: (data) =>
          SessionEndResult.fromJson(data as Map<String, dynamic>),
    );
  }
}

// ── Mock Implementation ───────────────────────────────────────────────────────

/// Mock teacher repository — no network, no backend required.
class MockTeacherSessionRepository
    implements TeacherSessionRepositoryInterface {
  MockTeacherSessionRepository({
    this.simulatedDelay = const Duration(milliseconds: 600),
    this.shouldFail = false,
  });

  final Duration simulatedDelay;
  final bool shouldFail;

  static final _mockSubjects = [
    const Subject(
        id: 'sub-001',
        code: 'CS301',
        name: 'Data Structures',
        department: 'Computer Science',
        isActive: true),
    const Subject(
        id: 'sub-002',
        code: 'CS401',
        name: 'Operating Systems',
        department: 'Computer Science',
        isActive: true),
    const Subject(
        id: 'sub-003',
        code: 'CS501',
        name: 'Computer Networks',
        department: 'Computer Science',
        isActive: true),
  ];

  static final _mockClassrooms = [
    const Classroom(
        id: 'room-001',
        name: 'Lab 101',
        building: 'CS Block',
        floor: 1,
        capacity: 40,
        isActive: true),
    const Classroom(
        id: 'room-002',
        name: 'Hall A',
        building: 'Main Block',
        floor: 2,
        capacity: 120,
        isActive: true),
    const Classroom(
        id: 'room-003',
        name: 'Room 302',
        building: 'Science Block',
        floor: 3,
        capacity: 60,
        isActive: true),
  ];

  int _presentCount = 5;

  AttendanceSession _mockSession({String? id, String status = 'active'}) {
    final now = DateTime.now();
    return AttendanceSession(
      id: id ?? 'session-mock-001',
      teacherId: 'teacher-001',
      subjectName: 'Data Structures',   // free-text name (post-migration)
      subjectId: 'sub-001',             // kept for backward-compat reference
      classroomId: 'room-001',
      status: status,
      startedAt: now.subtract(const Duration(minutes: 10)),
      expiresAt: now.add(const Duration(minutes: 50)),
      durationMinutes: 60,
      totalPresent: _presentCount,
      createdAt: now.subtract(const Duration(minutes: 10)),
    );
  }

  @override
  Future<List<Subject>> getSubjects() async {
    await Future.delayed(simulatedDelay);
    if (shouldFail) throw const NetworkException();
    return _mockSubjects;
  }

  @override
  Future<List<Classroom>> getClassrooms() async {
    await Future.delayed(simulatedDelay);
    if (shouldFail) throw const NetworkException();
    return _mockClassrooms;
  }

  @override
  Future<List<AttendanceSession>> getTimetable() async {
    await Future.delayed(simulatedDelay);
    if (shouldFail) throw const NetworkException();
    return [_mockSession()];
  }

  @override
  Future<AttendanceSession> createSession(
      SessionCreateRequest request) async {
    await Future.delayed(simulatedDelay);
    if (shouldFail) throw const ConflictException('Session already active');
    return _mockSession();
  }

  @override
  Future<AttendanceSession> getSession(String sessionId) async {
    await Future.delayed(simulatedDelay);
    return _mockSession(id: sessionId);
  }

  @override
  Future<SessionStatus> getSessionStatus(String sessionId) async {
    await Future.delayed(simulatedDelay);
    _presentCount += 1;
    return SessionStatus(
      sessionId: sessionId,
      status: 'active',
      totalPresent: _presentCount,
      remainingSeconds: 2700,
    );
  }

  @override
  Future<TokenRotationResult> rotateToken(String sessionId) async {
    await Future.delayed(simulatedDelay);
    return TokenRotationResult(
      sessionId: sessionId,
      rotatedAt: DateTime.now(),
      newTokenPreview: 'a3f2b9••••••••••',
    );
  }

  @override
  Future<SessionEndResult> closeSession(String sessionId) async {
    await Future.delayed(simulatedDelay);
    return SessionEndResult(
      sessionId: sessionId,
      status: 'completed',
      totalPresent: _presentCount,
    );
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final teacherSessionRepositoryProvider =
    Provider<TeacherSessionRepositoryInterface>((ref) {
  return TeacherSessionRepository(
    apiClient: ref.watch(apiClientProvider),
  );
});
