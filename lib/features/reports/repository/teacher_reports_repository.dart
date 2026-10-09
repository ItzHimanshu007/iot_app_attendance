import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/exceptions.dart';
import '../../../services/api_client.dart';
import '../../teacher/models/teacher_models.dart';
import '../models/reports_models.dart';

// ── Interface ─────────────────────────────────────────────────────────────────

/// Interface for teacher analytics — all methods return computed aggregates.
abstract class TeacherReportsRepositoryInterface {
  /// Summary KPIs for the reports dashboard card row.
  Future<AttendanceSummary> getAttendanceSummary();

  /// Per-subject analytics — aggregated from sessions grouped by subject.
  Future<List<SubjectAnalytics>> getSubjectAnalytics();

  /// Per-student analytics — aggregated from attendance records.
  Future<List<StudentAnalytics>> getStudentAnalytics();

  /// Per-session analytics — enriched with subject + classroom labels.
  Future<List<SessionAnalytics>> getSessionAnalytics();

  /// Full trend dataset for line chart.
  Future<AttendanceTrendData> getAttendanceTrend();

  /// Export-ready DTO.
  Future<AttendanceExport> buildExport();
}

// ── Real Implementation ───────────────────────────────────────────────────────

/// Teacher reports repository.
///
/// Aggregates analytics client-side from:
///   GET /sessions/                       → teacher session list
///   GET /attendance/session/{session_id} → per-session attendance records
///   GET /subjects/                       → subject metadata
///
/// All computations (averages, rates, thresholds) happen here.
/// Controllers receive clean, typed analytics objects.
class TeacherReportsRepository implements TeacherReportsRepositoryInterface {
  TeacherReportsRepository({required ApiClient apiClient})
      : _api = apiClient;

  final ApiClient _api;

  // ── Internal fetch helpers ─────────────────────────────────────────────────

  Future<List<AttendanceSession>> _fetchSessions() async {
    return _api.get<List<AttendanceSession>>(
      '/sessions/',
      fromJson: (data) => (data as List<dynamic>)
          .map((e) => AttendanceSession.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<List<AttendanceRecord>> _fetchSessionAttendance(
      String sessionId) async {
    return _api.get<List<AttendanceRecord>>(
      '/attendance/session/$sessionId',
      fromJson: (data) => (data as List<dynamic>)
          .map((e) =>
              AttendanceRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<List<Subject>> _fetchSubjects() async {
    return _api.get<List<Subject>>(
      '/subjects/',
      fromJson: (data) => (data as List<dynamic>)
          .map((e) => Subject.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  // ── Aggregation core ───────────────────────────────────────────────────────

  /// Fetch sessions + all attendance records in parallel.
  /// Returns (sessions, Map<sessionId, records>).
  Future<
      (
        List<AttendanceSession>,
        Map<String, List<AttendanceRecord>>,
        List<Subject>
      )> _fetchAll() async {
    final sessions = await _fetchSessions();
    final subjects = await _fetchSubjects();

    // Fetch attendance for each session concurrently
    final futures = sessions.map((s) async {
      try {
        final records = await _fetchSessionAttendance(s.id);
        return MapEntry(s.id, records);
      } catch (_) {
        // If a session's records fail, return empty list — don't fail all
        return MapEntry(s.id, <AttendanceRecord>[]);
      }
    });

    final entries = await Future.wait(futures);
    final attendanceMap = Map.fromEntries(entries);

    return (sessions, attendanceMap, subjects);
  }

  // ── Public methods ─────────────────────────────────────────────────────────

  @override
  Future<AttendanceSummary> getAttendanceSummary() async {
    final (sessions, attendanceMap, _) = await _fetchAll();

    final allRecords = attendanceMap.values.expand((r) => r).toList();
    final uniqueStudents =
        allRecords.map((r) => r.studentId).toSet().length;

    final totalPresent =
        sessions.fold<int>(0, (sum, s) => sum + s.totalPresent);

    // Average rate: mean of (present / max_possible) per session
    // We approximate capacity from max attendance seen
    final maxCapacity = sessions.isEmpty
        ? 1
        : sessions.map((s) => s.totalPresent).reduce((a, b) => a > b ? a : b);

    final averageRate = sessions.isEmpty || maxCapacity == 0
        ? 0.0
        : sessions.fold<double>(
              0,
              (sum, s) => sum + (s.totalPresent / maxCapacity),
            ) /
            sessions.length;

    // Student threshold counts
    final studentAttendance =
        _computeStudentRates(sessions, attendanceMap);
    final below75 =
        studentAttendance.values.where((r) => r < 0.75).length;
    final below50 =
        studentAttendance.values.where((r) => r < 0.50).length;

    return AttendanceSummary(
      totalSessions: sessions.length,
      totalUniqueStudents: uniqueStudents,
      averageAttendanceRate: averageRate.clamp(0.0, 1.0),
      studentsBelow75: below75,
      studentsBelow50: below50,
      totalPresentCount: totalPresent,
      generatedAt: DateTime.now(),
    );
  }

  @override
  Future<List<SubjectAnalytics>> getSubjectAnalytics() async {
    final (sessions, attendanceMap, subjects) = await _fetchAll();

    // Group sessions by displaySubjectName — works for both new sessions
    // (subjectName set) and historical sessions (backend resolves the name).
    final grouped = <String, List<AttendanceSession>>{};
    for (final s in sessions) {
      grouped.putIfAbsent(s.displaySubjectName, () => []).add(s);
    }

    final result = <SubjectAnalytics>[];
    for (final entry in grouped.entries) {
      final nameKey = entry.key;
      final subjectSessions = entry.value
        ..sort((a, b) => a.startedAt.compareTo(b.startedAt));

      // Build a synthetic Subject for display — uses the free-text name.
      // For historical sessions the backend already resolved the name into
      // subjectName via the migration's backward-compat logic.
      final subject = subjects.firstWhere(
        (s) => s.name == nameKey,
        orElse: () => Subject(
          id: nameKey,
          code: nameKey.length >= 3
              ? nameKey.substring(0, 3).toUpperCase()
              : nameKey.toUpperCase(),
          name: nameKey,
          department: '',
          isActive: true,
        ),
      );

      final counts = subjectSessions.map((s) => s.totalPresent).toList();
      final totalPresent = counts.fold<int>(0, (a, b) => a + b);
      final avgAttendance =
          counts.isEmpty ? 0.0 : totalPresent / counts.length;
      final maxSeen = counts.isEmpty
          ? 0
          : counts.reduce((a, b) => a > b ? a : b);
      final rate = maxSeen == 0 ? 0.0 : avgAttendance / maxSeen;

      final history = subjectSessions.map((s) {
        return SessionDataPoint(
          date: s.startedAt,
          count: s.totalPresent,
          sessionId: s.id,
        );
      }).toList();

      result.add(SubjectAnalytics(
        subject: subject,
        totalSessions: subjectSessions.length,
        averageAttendance: avgAttendance,
        highestAttendance: counts.isEmpty
            ? 0
            : counts.reduce((a, b) => a > b ? a : b),
        lowestAttendance: counts.isEmpty
            ? 0
            : counts.reduce((a, b) => a < b ? a : b),
        attendanceRate: rate.clamp(0.0, 1.0),
        sessionHistory: history,
      ));
    }

    result.sort(
        (a, b) => b.attendanceRate.compareTo(a.attendanceRate));
    return result;
  }

  @override
  Future<List<StudentAnalytics>> getStudentAnalytics() async {
    final (sessions, attendanceMap, _) = await _fetchAll();

    final studentRates = _computeStudentRates(sessions, attendanceMap);
    final totalSessions = sessions.length;

    final result = studentRates.entries.map((entry) {
      final rate = entry.value;
      final attended = (rate * totalSessions).round();
      return StudentAnalytics(
        studentId: entry.key,
        totalSessions: totalSessions,
        sessionsAttended: attended,
        sessionsMissed: totalSessions - attended,
        attendanceRate: rate,
      );
    }).toList();

    result.sort((a, b) => a.attendanceRate.compareTo(b.attendanceRate));
    return result;
  }

  @override
  Future<List<SessionAnalytics>> getSessionAnalytics() async {
    final (sessions, attendanceMap, _) = await _fetchAll();

    final sorted = [...sessions]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

    return sorted.map((s) {
      final records = attendanceMap[s.id] ?? [];
      final presentCount =
          records.where((r) => r.isPresent).length;
      final rate = records.isEmpty
          ? 0.0
          : presentCount / records.length;

      return SessionAnalytics(
        session: s,
        attendanceCount: s.totalPresent,
        attendanceRate: rate.clamp(0.0, 1.0),
        // Use the human-readable subject name — never a UUID.
        subjectCode: s.displaySubjectName,
        classroomName: s.classroomId,
      );
    }).toList();
  }

  @override
  Future<AttendanceTrendData> getAttendanceTrend() async {
    final sessions = await _fetchSessions();
    final sorted = [...sessions]
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));

    final points = sorted.map((s) {
      return SessionDataPoint(
        date: s.startedAt,
        count: s.totalPresent,
        sessionId: s.id,
      );
    }).toList();

    if (points.isEmpty) {
      return const AttendanceTrendData(
        points: [],
        maxCount: 0,
        minCount: 0,
        averageCount: 0,
      );
    }

    final counts = points.map((p) => p.count).toList();
    return AttendanceTrendData(
      points: points,
      maxCount: counts.reduce((a, b) => a > b ? a : b),
      minCount: counts.reduce((a, b) => a < b ? a : b),
      averageCount: counts.fold<int>(0, (a, b) => a + b) / counts.length,
    );
  }

  @override
  Future<AttendanceExport> buildExport() async {
    final (sessions, attendanceMap, _) = await _fetchAll();
    final studentRates = _computeStudentRates(sessions, attendanceMap);

    final sessionExports = sessions.map((s) {
      return SessionAttendanceExport(
        sessionId: s.id,
        // Use the human-readable subject name — never a UUID.
        subjectCode: s.displaySubjectName,
        classroomName: s.classroomId,
        date: s.startedAt,
        presentCount: s.totalPresent,
        durationMinutes: s.durationMinutes,
      );
    }).toList();

    final studentExports = studentRates.entries.map((e) {
      final attended = (e.value * sessions.length).round();
      return StudentAttendanceExport(
        studentId: e.key,
        sessionsAttended: attended,
        totalSessions: sessions.length,
        attendancePercent: e.value * 100,
      );
    }).toList();

    // Group by displaySubjectName (works for both new and historical sessions).
    final subjectGroups = <String, List<AttendanceSession>>{};
    for (final s in sessions) {
      subjectGroups.putIfAbsent(s.displaySubjectName, () => []).add(s);
    }
    final subjectExports = subjectGroups.entries.map((e) {
      final avg = e.value.fold<int>(0, (sum, s) => sum + s.totalPresent) /
          e.value.length;
      final max = e.value.map((s) => s.totalPresent).reduce((a, b) => a > b ? a : b);
      final rate = max == 0 ? 0.0 : avg / max;
      return SubjectAttendanceExport(
        subjectId: e.key,          // using name as the key (no UUID available)
        subjectCode: e.key,
        totalSessions: e.value.length,
        averageAttendance: avg,
        attendanceRate: rate,
      );
    }).toList();

    return AttendanceExport(
      exportedAt: DateTime.now(),
      teacherId: '',
      sessions: sessionExports,
      students: studentExports,
      subjects: subjectExports,
    );
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Compute per-student attendance rates across all sessions.
  /// Returns Map<studentId, rate 0.0–1.0>.
  Map<String, double> _computeStudentRates(
    List<AttendanceSession> sessions,
    Map<String, List<AttendanceRecord>> attendanceMap,
  ) {
    if (sessions.isEmpty) return {};

    // Collect all unique students
    final allRecords =
        attendanceMap.values.expand((r) => r).toList();
    final uniqueStudents =
        allRecords.map((r) => r.studentId).toSet();

    final result = <String, double>{};
    for (final studentId in uniqueStudents) {
      int attended = 0;
      for (final session in sessions) {
        final records = attendanceMap[session.id] ?? [];
        final found = records.any((r) =>
            r.studentId == studentId && r.isPresent);
        if (found) attended++;
      }
      result[studentId] = sessions.isEmpty
          ? 0.0
          : (attended / sessions.length).clamp(0.0, 1.0);
    }
    return result;
  }
}

// ── Mock Implementation ───────────────────────────────────────────────────────

/// Mock repository — deterministic data for tests, no network required.
class MockTeacherReportsRepository
    implements TeacherReportsRepositoryInterface {
  MockTeacherReportsRepository({
    this.simulatedDelay = const Duration(milliseconds: 700),
    this.isEmpty = false,
    this.shouldFail = false,
  });

  final Duration simulatedDelay;
  final bool isEmpty;
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

  static final _mockSessions = List.generate(12, (i) {
    final now = DateTime.now();
    final mockSubject = _mockSubjects[i % 3];
    final count = 18 + (i % 7) * 3;
    return AttendanceSession(
      id: 'session-$i',
      teacherId: 'teacher-001',
      subjectName: mockSubject.name,      // free-text name (post-migration)
      subjectId: mockSubject.id,          // legacy reference kept for compat
      classroomId: 'room-00${(i % 3) + 1}',
      status: i == 0 ? 'active' : 'completed',
      startedAt:
          now.subtract(Duration(days: i * 3, hours: 2)),
      expiresAt:
          now.subtract(Duration(days: i * 3)).add(const Duration(hours: 1)),
      durationMinutes: 60,
      totalPresent: count,
      createdAt: now.subtract(Duration(days: i * 3, hours: 2)),
    );
  });

  static final _mockStudentIds = List.generate(
      25, (i) => 'student-${i.toString().padLeft(3, '0')}');

  @override
  Future<AttendanceSummary> getAttendanceSummary() async {
    await Future.delayed(simulatedDelay);
    if (shouldFail) throw const NetworkException();
    if (isEmpty) {
      return AttendanceSummary(
        totalSessions: 0,
        totalUniqueStudents: 0,
        averageAttendanceRate: 0,
        studentsBelow75: 0,
        studentsBelow50: 0,
        totalPresentCount: 0,
        generatedAt: DateTime.now(),
      );
    }
    return AttendanceSummary(
      totalSessions: 12,
      totalUniqueStudents: 25,
      averageAttendanceRate: 0.78,
      studentsBelow75: 4,
      studentsBelow50: 1,
      totalPresentCount: 234,
      generatedAt: DateTime.now(),
    );
  }

  @override
  Future<List<SubjectAnalytics>> getSubjectAnalytics() async {
    await Future.delayed(simulatedDelay);
    if (shouldFail) throw const NetworkException();
    if (isEmpty) return [];

    return _mockSubjects.asMap().entries.map((entry) {
      final i = entry.key;
      final sub = entry.value;
      final rates = [0.82, 0.74, 0.91];
      final avgs = [20.3, 18.1, 22.5];
      final history = List.generate(4, (j) {
        return SessionDataPoint(
          date: DateTime.now().subtract(Duration(days: j * 7)),
          count: 16 + (j * 2) + (i * 3),
          sessionId: 'session-${i * 4 + j}',
        );
      });
      return SubjectAnalytics(
        subject: sub,
        totalSessions: 4,
        averageAttendance: avgs[i],
        highestAttendance: 25,
        lowestAttendance: 14,
        attendanceRate: rates[i],
        sessionHistory: history,
      );
    }).toList();
  }

  @override
  Future<List<StudentAnalytics>> getStudentAnalytics() async {
    await Future.delayed(simulatedDelay);
    if (shouldFail) throw const NetworkException();
    if (isEmpty) return [];

    final rates = [
      0.92, 0.87, 0.83, 0.79, 0.75, 0.72, 0.68, 0.65, 0.60,
      0.58, 0.55, 0.50, 0.48, 0.42, 0.38,
    ];

    return List.generate(15, (i) {
      final rate = i < rates.length ? rates[i] : 0.80;
      final attended = (rate * 12).round();
      return StudentAnalytics(
        studentId: _mockStudentIds[i],
        totalSessions: 12,
        sessionsAttended: attended,
        sessionsMissed: 12 - attended,
        attendanceRate: rate,
      );
    });
  }

  @override
  Future<List<SessionAnalytics>> getSessionAnalytics() async {
    await Future.delayed(simulatedDelay);
    if (shouldFail) throw const NetworkException();
    if (isEmpty) return [];

    return _mockSessions.take(10).map((s) {
      final subject = _mockSubjects.firstWhere(
          (sub) => sub.id == s.subjectId,
          orElse: () => _mockSubjects[0]);
      return SessionAnalytics(
        session: s,
        attendanceCount: s.totalPresent,
        attendanceRate: s.totalPresent / 28.0,
        subjectCode: subject.code,
        classroomName: 'Lab ${s.classroomId}',
      );
    }).toList();
  }

  @override
  Future<AttendanceTrendData> getAttendanceTrend() async {
    await Future.delayed(simulatedDelay);
    if (shouldFail) throw const NetworkException();
    if (isEmpty) {
      return const AttendanceTrendData(
        points: [], maxCount: 0, minCount: 0, averageCount: 0);
    }

    final points = List.generate(12, (i) {
      return SessionDataPoint(
        date: DateTime.now().subtract(Duration(days: i * 3)),
        count: 14 + (i % 5) * 3 + (i ~/ 4) * 2,
        sessionId: 'session-$i',
      );
    }).reversed.toList();

    final counts = points.map((p) => p.count).toList();
    return AttendanceTrendData(
      points: points,
      maxCount: counts.reduce((a, b) => a > b ? a : b),
      minCount: counts.reduce((a, b) => a < b ? a : b),
      averageCount: counts.fold<int>(0, (a, b) => a + b) / counts.length,
    );
  }

  @override
  Future<AttendanceExport> buildExport() async {
    await Future.delayed(simulatedDelay);
    final sessions = await getSessionAnalytics();
    return AttendanceExport(
      exportedAt: DateTime.now(),
      teacherId: 'teacher-001',
      sessions: sessions
          .map((s) => SessionAttendanceExport(
                sessionId: s.session.id,
                subjectCode: s.subjectCode,
                classroomName: s.classroomName,
                date: s.session.startedAt,
                presentCount: s.attendanceCount,
                durationMinutes: s.session.durationMinutes,
              ))
          .toList(),
      students: [],
      subjects: [],
    );
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final teacherReportsRepositoryProvider =
    Provider<TeacherReportsRepositoryInterface>((ref) {
  return TeacherReportsRepository(
    apiClient: ref.watch(apiClientProvider),
  );
});
