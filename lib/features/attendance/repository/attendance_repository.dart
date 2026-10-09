import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/exceptions.dart';
import '../../../services/api_client.dart';
import '../../../services/secure_storage_service.dart';
import '../models/attendance_models.dart';

// ── Interface ─────────────────────────────────────────────────────────────────

/// Interface for attendance operations — enables mock injection in tests.
abstract class AttendanceRepositoryInterface {
  /// Resolve a classroom ID to the currently active session ID.
  /// Returns null if no active session exists for that classroom.
  Future<String?> getActiveSessionForClassroom(String classroomId);

  Future<AttendanceRecord> submitAttendance(AttendanceMarkRequest request);
  Future<AttendanceRecord> submitAttendanceWithContext({
    required AttendanceMarkRequest request,
    required String classroomId,
  });
  Future<List<AttendanceRecord>> getAttendanceHistory();
  Future<AttendanceRecord?> getAttendanceStatus(String recordId);
  Future<AttendanceAnalytics> getLocalAnalytics();
}

// ── Real Implementation ───────────────────────────────────────────────────────

/// Attendance repository — wraps FastAPI attendance endpoints.
///
/// Endpoints:
///   POST /attendance/         → submit attendance record
///   GET  /attendance/me       → student's own history
///   GET  /attendance/{id}     → single record
class AttendanceRepository implements AttendanceRepositoryInterface {
  AttendanceRepository({
    required ApiClient apiClient,
    required SecureStorageService storage,
  })  : _api = apiClient,
        _storage = storage;

  final ApiClient _api;
  final SecureStorageService _storage;

  // ── Session Lookup ──────────────────────────────────────────────────────────

  /// Resolve a classroom ID to the active session ID.
  /// Calls GET /sessions/active?classroom_id={id}.
  /// Returns null if no active session exists for that classroom.
  @override
  Future<String?> getActiveSessionForClassroom(String classroomId) async {
    // Guard: classroomId must be a UUID.
    // The name-only fallback path in BlePayloadParser can produce the
    // device-name suffix (e.g. "LAB101") when manufacturerData is empty.
    // Passing that to Postgres causes: invalid input syntax for type uuid.
    // Reject non-UUID strings here so the backend is never called with them.
    final uuidPattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    );
    if (!uuidPattern.hasMatch(classroomId)) {
      print('[ATTENDANCE REPO] getActiveSessionForClassroom: '
          'classroomId "$classroomId" is not a UUID — '
          'blocked to prevent Postgres type error (protocolVersion=0 path?)');
      return null;
    }
    try {
      final session = await _api.get<Map<String, dynamic>?>(
        '/sessions/active',
        queryParameters: {'classroom_id': classroomId},
        fromJson: (data) =>
            data == null ? null : data as Map<String, dynamic>,
      );
      return session?['id'] as String?;
    } catch (_) {
      return null;
    }
  }

  // ── Submission ─────────────────────────────────────────────────────────────

  /// Submit attendance — main pipeline endpoint.
  ///
  /// On success: persists analytics locally.
  /// Propagates [ConflictException] for duplicate attendance.
  @override
  Future<AttendanceRecord> submitAttendance(
      AttendanceMarkRequest request) async {
    final record = await _api.post<AttendanceRecord>(
      '/attendance/',
      data: request.toJson(),
      fromJson: (data) =>
          AttendanceRecord.fromJson(data as Map<String, dynamic>),
    );

    // Persist local analytics on success
    await _updateLocalAnalytics(
      classroom: null, // classroom not in response — stored from BLE
      success: record.isSuccessful,
    );

    return record;
  }

  /// Submit attendance with classroom context for analytics.
  @override
  Future<AttendanceRecord> submitAttendanceWithContext({
    required AttendanceMarkRequest request,
    required String classroomId,
  }) async {
    final record = await _api.post<AttendanceRecord>(
      '/attendance/',
      data: request.toJson(),
      fromJson: (data) =>
          AttendanceRecord.fromJson(data as Map<String, dynamic>),
    );

    await _updateLocalAnalytics(
      classroom: classroomId,
      success: record.isSuccessful,
    );

    return record;
  }

  // ── Query ──────────────────────────────────────────────────────────────────

  @override
  Future<List<AttendanceRecord>> getAttendanceHistory() async {
    final list = await _api.get<List<AttendanceRecord>>(
      '/attendance/me',
      fromJson: (data) {
        final items = data as List<dynamic>;
        return items
            .map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );
    return list;
  }

  @override
  Future<AttendanceRecord?> getAttendanceStatus(String recordId) async {
    try {
      return await _api.get<AttendanceRecord>(
        '/attendance/$recordId',
        fromJson: (data) =>
            AttendanceRecord.fromJson(data as Map<String, dynamic>),
      );
    } on NotFoundException {
      return null;
    }
  }

  // ── Local Analytics ────────────────────────────────────────────────────────

  @override
  Future<AttendanceAnalytics> getLocalAnalytics() async {
    final totalStr =
        await _storage.rawRead(AppConstants.keyTotalSubmissions);
    final successStr =
        await _storage.rawRead(AppConstants.keySuccessfulSubmissions);
    final lastTime =
        await _storage.rawRead(AppConstants.keyLastAttendanceTime);
    final lastRoom = await _storage.rawRead(AppConstants.keyLastClassroom);

    return AttendanceAnalytics(
      totalSubmissions: int.tryParse(totalStr ?? '0') ?? 0,
      successfulSubmissions: int.tryParse(successStr ?? '0') ?? 0,
      lastAttendanceTime:
          lastTime != null ? DateTime.tryParse(lastTime) : null,
      lastClassroom: lastRoom,
    );
  }

  Future<void> _updateLocalAnalytics({
    required String? classroom,
    required bool success,
  }) async {
    final analytics = await getLocalAnalytics();
    final updated = analytics.copyWith(
      totalSubmissions: analytics.totalSubmissions + 1,
      successfulSubmissions: success
          ? analytics.successfulSubmissions + 1
          : analytics.successfulSubmissions,
      lastAttendanceTime: DateTime.now(),
      lastClassroom: classroom ?? analytics.lastClassroom,
    );

    await _storage.rawWrite(
      AppConstants.keyTotalSubmissions,
      updated.totalSubmissions.toString(),
    );
    await _storage.rawWrite(
      AppConstants.keySuccessfulSubmissions,
      updated.successfulSubmissions.toString(),
    );
    await _storage.rawWrite(
      AppConstants.keyLastAttendanceTime,
      updated.lastAttendanceTime?.toIso8601String() ?? '',
    );
    if (classroom != null) {
      await _storage.rawWrite(AppConstants.keyLastClassroom, classroom);
    }
  }
}

// ── Mock Implementation ───────────────────────────────────────────────────────

/// Mock attendance repository — for unit tests without network or hardware.
class MockAttendanceRepository implements AttendanceRepositoryInterface {
  MockAttendanceRepository({
    this.shouldSucceed = true,
    this.simulatedDelay = const Duration(milliseconds: 800),
    this.errorToThrow,
    List<AttendanceRecord>? history,
  }) : _history = history ?? [];

  final bool shouldSucceed;
  final Duration simulatedDelay;
  final Exception? errorToThrow;
  final List<AttendanceRecord> _history;

  static AttendanceRecord mockRecord({String? id, String? status}) =>
      AttendanceRecord(
        id: id ?? 'mock-record-001',
        sessionId: 'mock-session-abc',
        studentId: 'mock-student-001',
        status: status ?? AppConstants.statusPresent,
        verificationMethod: 'ble_biometric',
        biometricVerified: true,
        markedAt: DateTime.now(),
        createdAt: DateTime.now(),
        bleRssi: -62,
      );

  @override
  Future<String?> getActiveSessionForClassroom(String classroomId) async {
    await Future.delayed(simulatedDelay);
    // Return a deterministic mock session ID for tests
    return 'mock-session-abc';
  }

  @override
  Future<AttendanceRecord> submitAttendance(
      AttendanceMarkRequest request) async {
    await Future.delayed(simulatedDelay);
    if (errorToThrow != null) throw errorToThrow!;
    if (!shouldSucceed) {
      throw const ConflictException('Attendance already recorded',
          code: 'DUPLICATE_ATTENDANCE');
    }
    return mockRecord();
  }

  @override
  Future<AttendanceRecord> submitAttendanceWithContext({
    required AttendanceMarkRequest request,
    required String classroomId,
  }) =>
      submitAttendance(request);

  @override
  Future<List<AttendanceRecord>> getAttendanceHistory() async {
    await Future.delayed(simulatedDelay);
    return _history;
  }

  @override
  Future<AttendanceRecord?> getAttendanceStatus(String recordId) async {
    await Future.delayed(simulatedDelay);
    return _history.where((r) => r.id == recordId).firstOrNull;
  }

  @override
  Future<AttendanceAnalytics> getLocalAnalytics() async {
    return AttendanceAnalytics(
      totalSubmissions: _history.length,
      successfulSubmissions: _history.where((r) => r.isSuccessful).length,
      lastAttendanceTime:
          _history.isNotEmpty ? _history.last.markedAt : null,
      lastClassroom: null,
    );
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final attendanceRepositoryProvider =
    Provider<AttendanceRepositoryInterface>((ref) {
  return AttendanceRepository(
    apiClient: ref.watch(apiClientProvider),
    storage: ref.watch(secureStorageProvider),
  );
});
