import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/exceptions.dart';
import '../models/teacher_models.dart';
import '../repository/teacher_session_repository.dart';

// ── Session State ─────────────────────────────────────────────────────────────

sealed class TeacherSessionState {
  const TeacherSessionState();
}

/// No active session — ready to create one.
class TeacherSessionIdle extends TeacherSessionState {
  const TeacherSessionIdle();
}

/// Session creation in progress.
class TeacherSessionCreating extends TeacherSessionState {
  const TeacherSessionCreating();
}

/// Session is live — teacher is monitoring it.
class TeacherSessionActive extends TeacherSessionState {
  const TeacherSessionActive({
    required this.session,
    this.liveStatus,
    this.lastRotatedAt,
    this.lastRotationPreview,
  });

  final AttendanceSession session;
  final SessionStatus? liveStatus;
  final DateTime? lastRotatedAt;
  final String? lastRotationPreview;

  /// Live attendance count — prefer live status, fall back to session data.
  int get attendanceCount =>
      liveStatus?.totalPresent ?? session.totalPresent;

  TeacherSessionActive copyWith({
    AttendanceSession? session,
    SessionStatus? liveStatus,
    DateTime? lastRotatedAt,
    String? lastRotationPreview,
  }) {
    return TeacherSessionActive(
      session: session ?? this.session,
      liveStatus: liveStatus ?? this.liveStatus,
      lastRotatedAt: lastRotatedAt ?? this.lastRotatedAt,
      lastRotationPreview: lastRotationPreview ?? this.lastRotationPreview,
    );
  }
}

/// Token rotation in progress.
class TeacherSessionRotating extends TeacherSessionState {
  const TeacherSessionRotating({required this.session});
  final AttendanceSession session;
}

/// Session is being ended.
class TeacherSessionEnding extends TeacherSessionState {
  const TeacherSessionEnding({required this.session});
  final AttendanceSession session;
}

/// Session ended successfully.
class TeacherSessionEnded extends TeacherSessionState {
  const TeacherSessionEnded({required this.result});
  final SessionEndResult result;
}

/// Error state — holds last session context for retry UI.
class TeacherSessionError extends TeacherSessionState {
  const TeacherSessionError({
    required this.message,
    this.isRetryable = true,
    this.errorCode,
    this.session,
  });

  final String message;
  final bool isRetryable;
  final String? errorCode;
  final AttendanceSession? session;
}

/// Session expired server-side — shown on poll.
class TeacherSessionExpired extends TeacherSessionState {
  const TeacherSessionExpired({required this.session});
  final AttendanceSession session;
}

// ── Teacher Session Controller ────────────────────────────────────────────────

/// Manages the full teacher session lifecycle:
///   idle → creating → active → [rotating → active] → ending → ended
///
/// Polls session status every 15 seconds while active.
/// Architecture is WebSocket-ready: replace [_startPolling] with a
/// ws:// channel subscription when the backend supports it.
class TeacherSessionController
    extends StateNotifier<TeacherSessionState> {
  TeacherSessionController(this._repo) : super(const TeacherSessionIdle());

  final TeacherSessionRepositoryInterface _repo;

  Timer? _pollTimer;
  static const _pollInterval = Duration(seconds: 15);

  // ── Create Session ─────────────────────────────────────────────────────────

  Future<void> createSession(SessionCreateRequest request) async {
    state = const TeacherSessionCreating();
    try {
      final session = await _repo.createSession(request);
      state = TeacherSessionActive(session: session);
      _startPolling(session.id);
    } on ConflictException {
      state = const TeacherSessionError(
        message: 'A session is already active for this classroom or subject.',
        isRetryable: false,
        errorCode: 'SESSION_CONFLICT',
      );
    } on ForbiddenException {
      state = const TeacherSessionError(
        message: 'You are not authorised to create a session for this subject.',
        isRetryable: false,
        errorCode: 'FORBIDDEN',
      );
    } on NetworkException {
      state = const TeacherSessionError(
        message: 'No internet connection. Please try again.',
        errorCode: 'NETWORK_ERROR',
      );
    } on ServerException catch (e) {
      state = TeacherSessionError(
        message: e.message,
        isRetryable: false,
        errorCode: 'SERVER_ERROR',
      );
    } catch (e) {
      state = TeacherSessionError(
        message: 'Unexpected error: $e',
        isRetryable: true,
      );
    }
  }

  // ── Rotate Token ───────────────────────────────────────────────────────────

  Future<void> rotateToken() async {
    final current = state;
    if (current is! TeacherSessionActive) return;

    state = TeacherSessionRotating(session: current.session);
    try {
      final result = await _repo.rotateToken(current.session.id);
      state = current.copyWith(
        lastRotatedAt: result.rotatedAt,
        lastRotationPreview: result.newTokenPreview,
      );
    } on NetworkException {
      state = TeacherSessionError(
        message: 'Token rotation failed: no internet.',
        isRetryable: true,
        session: current.session,
      );
    } catch (e) {
      state = TeacherSessionError(
        message: 'Token rotation failed: $e',
        isRetryable: true,
        session: current.session,
      );
    }
  }

  // ── End Session ────────────────────────────────────────────────────────────

  Future<void> endSession() async {
    final current = state;
    if (current is! TeacherSessionActive) return;

    _stopPolling();
    state = TeacherSessionEnding(session: current.session);
    try {
      final result = await _repo.closeSession(current.session.id);
      state = TeacherSessionEnded(result: result);
    } on NetworkException {
      // Restore active state on network error
      state = TeacherSessionError(
        message: 'Could not end session: no internet.',
        isRetryable: true,
        session: current.session,
      );
    } catch (e) {
      state = TeacherSessionError(
        message: 'Could not end session: $e',
        isRetryable: true,
        session: current.session,
      );
    }
  }

  // ── Resume (reload existing active session) ────────────────────────────────

  Future<void> resumeSession(String sessionId) async {
    try {
      final session = await _repo.getSession(sessionId);
      if (session.isActive) {
        state = TeacherSessionActive(session: session);
        _startPolling(sessionId);
      }
    } catch (_) {
      // Silent — used on app resume
    }
  }

  // ── Force refresh ──────────────────────────────────────────────────────────

  Future<void> refreshStatus() async {
    final current = state;
    if (current is! TeacherSessionActive) return;
    await _pollOnce(current.session.id);
  }

  // ── Reset ──────────────────────────────────────────────────────────────────

  void reset() {
    _stopPolling();
    state = const TeacherSessionIdle();
  }

  // ── Polling ────────────────────────────────────────────────────────────────

  /// Start polling every 15 seconds.
  ///
  /// Architecture note: replace this block with a WebSocket channel
  /// subscription when the backend adds ws:// support.
  void _startPolling(String sessionId) {
    _stopPolling();
    _pollTimer = Timer.periodic(_pollInterval, (_) async {
      await _pollOnce(sessionId);
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _pollOnce(String sessionId) async {
    final current = state;
    if (current is! TeacherSessionActive) {
      _stopPolling();
      return;
    }
    try {
      final status = await _repo.getSessionStatus(sessionId);
      if (!status.isActive) {
        _stopPolling();
        state = TeacherSessionExpired(session: current.session);
        return;
      }
      state = current.copyWith(liveStatus: status);
    } catch (_) {
      // Silent poll failure — don't interrupt the teacher UI
    }
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }
}

// ── Reference Data Controllers ────────────────────────────────────────────────

sealed class SubjectsState {
  const SubjectsState();
}

class SubjectsLoading extends SubjectsState {
  const SubjectsLoading();
}

class SubjectsLoaded extends SubjectsState {
  const SubjectsLoaded(this.subjects);
  final List<Subject> subjects;
}

class SubjectsError extends SubjectsState {
  const SubjectsError(this.message);
  final String message;
}

class SubjectsController extends StateNotifier<SubjectsState> {
  SubjectsController(this._repo) : super(const SubjectsLoading()) {
    _load();
  }
  final TeacherSessionRepositoryInterface _repo;

  Future<void> _load() async {
    try {
      final subjects = await _repo.getSubjects();
      state = SubjectsLoaded(subjects);
    } catch (e) {
      state = SubjectsError('Failed to load subjects: $e');
    }
  }

  Future<void> refresh() async {
    state = const SubjectsLoading();
    await _load();
  }
}

sealed class ClassroomsState {
  const ClassroomsState();
}

class ClassroomsLoading extends ClassroomsState {
  const ClassroomsLoading();
}

class ClassroomsLoaded extends ClassroomsState {
  const ClassroomsLoaded(this.classrooms);
  final List<Classroom> classrooms;
}

class ClassroomsError extends ClassroomsState {
  const ClassroomsError(this.message);
  final String message;
}

class ClassroomsController extends StateNotifier<ClassroomsState> {
  ClassroomsController(this._repo) : super(const ClassroomsLoading()) {
    _load();
  }
  final TeacherSessionRepositoryInterface _repo;

  Future<void> _load() async {
    try {
      final classrooms = await _repo.getClassrooms();
      state = ClassroomsLoaded(classrooms);
    } catch (e) {
      state = ClassroomsError('Failed to load classrooms: $e');
    }
  }

  Future<void> refresh() async {
    state = const ClassroomsLoading();
    await _load();
  }
}

sealed class TimetableState {
  const TimetableState();
}

class TimetableLoading extends TimetableState {
  const TimetableLoading();
}

class TimetableLoaded extends TimetableState {
  const TimetableLoaded(this.sessions);
  final List<AttendanceSession> sessions;

  List<AttendanceSession> get activeSessions =>
      sessions.where((s) => s.isActive).toList();

  List<AttendanceSession> get recentSessions {
    final sorted = [...sessions]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return sorted.take(20).toList();
  }
}

class TimetableError extends TimetableState {
  const TimetableError(this.message);
  final String message;
}

class TimetableController extends StateNotifier<TimetableState> {
  TimetableController(this._repo) : super(const TimetableLoading()) {
    _load();
  }
  final TeacherSessionRepositoryInterface _repo;

  Future<void> _load() async {
    try {
      final sessions = await _repo.getTimetable();
      state = TimetableLoaded(sessions);
    } catch (e) {
      state = TimetableError('Failed to load sessions: $e');
    }
  }

  Future<void> refresh() async {
    state = const TimetableLoading();
    await _load();
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final teacherSessionControllerProvider =
    StateNotifierProvider<TeacherSessionController, TeacherSessionState>(
        (ref) {
  return TeacherSessionController(
    ref.watch(teacherSessionRepositoryProvider),
  );
});

final subjectsControllerProvider =
    StateNotifierProvider<SubjectsController, SubjectsState>((ref) {
  return SubjectsController(
    ref.watch(teacherSessionRepositoryProvider),
  );
});

final classroomsControllerProvider =
    StateNotifierProvider<ClassroomsController, ClassroomsState>((ref) {
  return ClassroomsController(
    ref.watch(teacherSessionRepositoryProvider),
  );
});

final timetableControllerProvider =
    StateNotifierProvider<TimetableController, TimetableState>((ref) {
  return TimetableController(
    ref.watch(teacherSessionRepositoryProvider),
  );
});

/// Convenience — is there currently an active session?
final hasActiveSessionProvider = Provider<bool>((ref) {
  return ref.watch(teacherSessionControllerProvider) is TeacherSessionActive;
});

/// Convenience — live attendance count.
final liveAttendanceCountProvider = Provider<int>((ref) {
  final state = ref.watch(teacherSessionControllerProvider);
  if (state is TeacherSessionActive) return state.attendanceCount;
  return 0;
});
