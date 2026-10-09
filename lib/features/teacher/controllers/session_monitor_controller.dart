/// Session monitor controller — polls attendance records for a live session.
///
/// Responsibilities:
///   - [loadAttendance]  → fetch attendance list for a session once
///   - [startPolling]    → auto-refresh every 10 s while screen is open
///   - [stopPolling]     → cancel timer on dispose
///   - Manual refresh    → call [loadAttendance] on demand
///
/// Attendance records are fetched from:
///   GET /attendance/session/{session_id}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/api_client.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

/// A single attendance record as seen by the teacher monitor.
class AttendanceEntry {
  const AttendanceEntry({
    required this.id,
    required this.studentId,
    required this.status,
    required this.markedAt,
    this.studentName,
    this.bleRssi,
    this.biometricVerified,
  });

  final String id;
  final String studentId;
  final String status;           // 'present' | 'late' | 'revoked'
  final DateTime markedAt;
  final String? studentName;
  final int? bleRssi;
  final bool? biometricVerified;

  bool get isPresent => status == 'present';

  factory AttendanceEntry.fromJson(Map<String, dynamic> json) {
    return AttendanceEntry(
      id: json['id'] as String,
      studentId: json['student_id'] as String,
      status: json['status'] as String? ?? 'present',
      markedAt: DateTime.parse(json['marked_at'] as String),
      studentName: json['student_name'] as String?,
      bleRssi: json['ble_rssi'] as int?,
      biometricVerified: json['biometric_verified'] as bool?,
    );
  }
}

// ── State ─────────────────────────────────────────────────────────────────────

sealed class SessionMonitorState {
  const SessionMonitorState();
}

class SessionMonitorInitial extends SessionMonitorState {
  const SessionMonitorInitial();
}

class SessionMonitorLoading extends SessionMonitorState {
  const SessionMonitorLoading();
}

class SessionMonitorLoaded extends SessionMonitorState {
  const SessionMonitorLoaded({
    required this.sessionId,
    required this.entries,
    required this.lastRefreshed,
  });

  final String sessionId;
  final List<AttendanceEntry> entries;
  final DateTime lastRefreshed;

  int get presentCount =>
      entries.where((e) => e.isPresent).length;
}

class SessionMonitorError extends SessionMonitorState {
  const SessionMonitorError(this.message);
  final String message;
}

// ── Controller ────────────────────────────────────────────────────────────────

class SessionMonitorController
    extends StateNotifier<SessionMonitorState> {
  SessionMonitorController(this._api) : super(const SessionMonitorInitial());

  final ApiClient _api;
  Timer? _pollTimer;
  String? _currentSessionId;

  static const _pollInterval = Duration(seconds: 10);

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<void> loadAttendance(String sessionId) async {
    _currentSessionId = sessionId;
    state = const SessionMonitorLoading();
    await _fetchOnce(sessionId);
  }

  void startPolling(String sessionId) {
    _currentSessionId = sessionId;
    _stopPolling();
    _pollTimer = Timer.periodic(_pollInterval, (_) async {
      if (_currentSessionId != null) {
        await _fetchOnce(_currentSessionId!);
      }
    });
  }

  void stopPolling() => _stopPolling();

  Future<void> refresh() async {
    if (_currentSessionId != null) {
      await _fetchOnce(_currentSessionId!);
    }
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  Future<void> _fetchOnce(String sessionId) async {
    try {
      final entries = await _api.get<List<AttendanceEntry>>(
        '/attendance/session/$sessionId',
        fromJson: (data) {
          final items = data as List<dynamic>;
          return items
              .map((e) => AttendanceEntry.fromJson(e as Map<String, dynamic>))
              .toList();
        },
      );
      if (!mounted) return;
      state = SessionMonitorLoaded(
        sessionId: sessionId,
        entries: entries,
        lastRefreshed: DateTime.now(),
      );
    } catch (e) {
      if (!mounted) return;
      // Don't wipe existing data on poll failure — keep stale data visible.
      final current = state;
      if (current is! SessionMonitorLoaded) {
        state = SessionMonitorError('Failed to load attendance: $e');
      }
    }
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final sessionMonitorControllerProvider = StateNotifierProvider<
    SessionMonitorController, SessionMonitorState>((ref) {
  return SessionMonitorController(ref.watch(apiClientProvider));
});
