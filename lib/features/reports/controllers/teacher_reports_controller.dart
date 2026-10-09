import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/reports_models.dart';
import '../repository/teacher_reports_repository.dart';

// ── Reports State ─────────────────────────────────────────────────────────────

sealed class ReportsState {
  const ReportsState();
}

class ReportsLoading extends ReportsState {
  const ReportsLoading();
}

class ReportsLoaded extends ReportsState {
  const ReportsLoaded({
    required this.summary,
    required this.subjects,
    required this.students,
    required this.sessions,
    required this.trend,
  });

  final AttendanceSummary summary;
  final List<SubjectAnalytics> subjects;
  final List<StudentAnalytics> students;
  final List<SessionAnalytics> sessions;
  final AttendanceTrendData trend;

  /// Students below 75% attendance — sorted worst-first.
  List<StudentAnalytics> get lowAttendanceStudents =>
      students.where((s) => s.isBelowThreshold75).toList();

  /// Students below 50% — critical alert list.
  List<StudentAnalytics> get criticalStudents =>
      students.where((s) => s.isBelowThreshold50).toList();

  ReportsLoaded copyWith({
    AttendanceSummary? summary,
    List<SubjectAnalytics>? subjects,
    List<StudentAnalytics>? students,
    List<SessionAnalytics>? sessions,
    AttendanceTrendData? trend,
  }) {
    return ReportsLoaded(
      summary: summary ?? this.summary,
      subjects: subjects ?? this.subjects,
      students: students ?? this.students,
      sessions: sessions ?? this.sessions,
      trend: trend ?? this.trend,
    );
  }
}

class ReportsEmpty extends ReportsState {
  const ReportsEmpty();
}

class ReportsError extends ReportsState {
  const ReportsError({required this.message, this.isRetryable = true});
  final String message;
  final bool isRetryable;
}

// ── Controller ────────────────────────────────────────────────────────────────

/// Teacher reports controller — loads all analytics in parallel.
///
/// Loads: summary, subjects, students, sessions, trend
/// All requests fire concurrently via [Future.wait].
class TeacherReportsController extends StateNotifier<ReportsState> {
  TeacherReportsController(this._repo) : super(const ReportsLoading()) {
    _load();
  }

  final TeacherReportsRepositoryInterface _repo;

  Future<void> _load() async {
    state = const ReportsLoading();
    try {
      // Parallel fetch — all analytics in one round trip
      final results = await Future.wait([
        _repo.getAttendanceSummary(),
        _repo.getSubjectAnalytics(),
        _repo.getStudentAnalytics(),
        _repo.getSessionAnalytics(),
        _repo.getAttendanceTrend(),
      ]);

      final summary = results[0] as AttendanceSummary;
      final subjects = results[1] as List<SubjectAnalytics>;
      final students = results[2] as List<StudentAnalytics>;
      final sessions = results[3] as List<SessionAnalytics>;
      final trend = results[4] as AttendanceTrendData;

      if (summary.totalSessions == 0 && subjects.isEmpty) {
        state = const ReportsEmpty();
        return;
      }

      state = ReportsLoaded(
        summary: summary,
        subjects: subjects,
        students: students,
        sessions: sessions,
        trend: trend,
      );
    } on Exception catch (e) {
      state = ReportsError(
        message: _friendlyError(e),
        isRetryable: true,
      );
    }
  }

  Future<void> refresh() => _load();

  Future<AttendanceExport?> buildExport() async {
    try {
      return await _repo.buildExport();
    } catch (_) {
      return null;
    }
  }

  String _friendlyError(Exception e) {
    final msg = e.toString();
    if (msg.contains('NetworkException')) {
      return 'No internet connection. Pull down to retry.';
    }
    if (msg.contains('Unauthorized') || msg.contains('403')) {
      return 'You are not authorised to view this data.';
    }
    return 'Failed to load reports. Please try again.';
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final teacherReportsControllerProvider =
    StateNotifierProvider<TeacherReportsController, ReportsState>((ref) {
  return TeacherReportsController(
    ref.watch(teacherReportsRepositoryProvider),
  );
});

/// Convenience — low attendance students (below 75%).
final lowAttendanceStudentsProvider = Provider<List<StudentAnalytics>>((ref) {
  final state = ref.watch(teacherReportsControllerProvider);
  if (state is ReportsLoaded) return state.lowAttendanceStudents;
  return [];
});

/// Convenience — summary data.
final attendanceSummaryProvider = Provider<AttendanceSummary?>((ref) {
  final state = ref.watch(teacherReportsControllerProvider);
  if (state is ReportsLoaded) return state.summary;
  return null;
});

/// Convenience — trend data for chart.
final attendanceTrendProvider = Provider<AttendanceTrendData?>((ref) {
  final state = ref.watch(teacherReportsControllerProvider);
  if (state is ReportsLoaded) return state.trend;
  return null;
});
