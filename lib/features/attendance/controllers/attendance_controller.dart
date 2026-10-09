import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/exceptions.dart';
import '../../device/controllers/device_controller.dart';
import '../../device/models/device_models.dart';
import '../../device/services/biometric_service.dart';
import '../../device/services/device_fingerprint_service.dart';
import '../models/attendance_models.dart';
import '../models/ble_models.dart';
import '../repository/attendance_repository.dart';

// ── Attendance State ──────────────────────────────────────────────────────────

sealed class AttendanceState {
  const AttendanceState();
}

class AttendanceIdle extends AttendanceState {
  const AttendanceIdle();
}

/// Pipeline is running — carries current step for animated progress UI.
class AttendanceInProgress extends AttendanceState {
  const AttendanceInProgress({required this.step, this.advertisement});
  final AttendancePipelineStep step;
  final AttendanceSessionAdvertisement? advertisement;
}

/// Attendance submitted — record returned from backend.
class AttendanceSuccess extends AttendanceState {
  const AttendanceSuccess({required this.record, required this.advertisement});
  final AttendanceRecord record;
  final AttendanceSessionAdvertisement advertisement;
}

/// Submission rejected — typed reason.
class AttendanceFailure extends AttendanceState {
  const AttendanceFailure({
    required this.reason,
    required this.step,
    this.isRetryable = true,
    this.errorCode,
  });
  final String reason;
  final AttendancePipelineStep step;
  final bool isRetryable;
  final String? errorCode;
}

// ── History State ─────────────────────────────────────────────────────────────

sealed class AttendanceHistoryState {
  const AttendanceHistoryState();
}

class AttendanceHistoryInitial extends AttendanceHistoryState {
  const AttendanceHistoryInitial();
}

class AttendanceHistoryLoading extends AttendanceHistoryState {
  const AttendanceHistoryLoading();
}

class AttendanceHistoryLoaded extends AttendanceHistoryState {
  const AttendanceHistoryLoaded({
    required this.records,
    required this.analytics,
  });
  final List<AttendanceRecord> records;
  final AttendanceAnalytics analytics;
}

class AttendanceHistoryError extends AttendanceHistoryState {
  const AttendanceHistoryError(this.message);
  final String message;
}

// ── Attendance Controller ─────────────────────────────────────────────────────

/// Orchestrates the complete 8-step attendance submission pipeline.
///
/// Step 1: Session advertisement received (RSSI validated)
/// Step 2: Validate RSSI threshold
/// Step 3: Validate device registration
/// Step 4: Trigger biometric authentication
/// Step 5: Collect device fingerprint (SHA-256)
/// Step 6: Build AttendanceMarkRequest payload
/// Step 7: Submit to POST /attendance/
/// Step 8: Display result
class AttendanceController extends StateNotifier<AttendanceState> {
  AttendanceController({
    required AttendanceRepositoryInterface repository,
    required DeviceFingerprintInterface fingerprintService,
    required BiometricServiceInterface biometricService,
    required DeviceController deviceController,
  })  : _repo = repository,
        _fingerprint = fingerprintService,
        _biometric = biometricService,
        _deviceCtrl = deviceController,
        super(const AttendanceIdle());

  final AttendanceRepositoryInterface _repo;
  final DeviceFingerprintInterface _fingerprint;
  final BiometricServiceInterface _biometric;
  final DeviceController _deviceCtrl;

  // ── Main Pipeline ──────────────────────────────────────────────────────────

  /// Execute the full attendance submission pipeline.
  ///
  /// [advertisement] — BLE beacon discovered in Phase 4.3.
  /// The advertisement carries classroomId + token + rssi.
  Future<void> submitAttendance(
      AttendanceSessionAdvertisement advertisement) async {
    // Guard: don't re-run if already in progress
    if (state is AttendanceInProgress) return;

    // ── Step 0: Resolve active session ID from classroom ─────────────────────
    // The BLE advertisement only carries classroomId (from device name SCA-X).
    // We must look up the actual session UUID before proceeding.
    _setStep(AttendancePipelineStep.validatingSession, advertisement);

    final sessionId = await _repo.getActiveSessionForClassroom(
      advertisement.classroomId,
    );

    if (sessionId == null) {
      _fail(
        step: AttendancePipelineStep.validatingSession,
        reason:
            'No active session found for classroom ${advertisement.classroomId}. '
            'The session may have ended.',
        isRetryable: true,
      );
      return;
    }

    // ── Step 1: Validate RSSI threshold ─────────────────────────────────────
    // Note: advertisement age is NOT checked here.
    // Session validity was already confirmed by getActiveSessionForClassroom
    // above (Step 0). A beacon is valid as long as the backend has an active
    // session — the user may take any amount of time to press the button.
    _setStep(AttendancePipelineStep.validatingSession, advertisement);

    if (!advertisement.isInRange) {
      _fail(
        step: AttendancePipelineStep.validatingSession,
        reason:
            'Signal too weak (${advertisement.rssi} dBm). Move closer to the classroom.',
        isRetryable: true,
      );
      return;
    }

    // ── Step 2: Validate device registration ─────────────────────────────────
    _setStep(AttendancePipelineStep.checkingDevice, advertisement);

    final deviceState = _deviceCtrl.state;
    if (deviceState is! DeviceRegistered) {
      _fail(
        step: AttendancePipelineStep.checkingDevice,
        reason: 'Device not registered. Register your device first.',
        isRetryable: false,
        errorCode: 'DEVICE_NOT_REGISTERED',
      );
      return;
    }

    if (!deviceState.device.isActive) {
      _fail(
        step: AttendancePipelineStep.checkingDevice,
        reason: 'Your device has been deactivated. Contact your administrator.',
        isRetryable: false,
        errorCode: 'DEVICE_INACTIVE',
      );
      return;
    }

    // ── Step 3: Biometric authentication ─────────────────────────────────────
    _setStep(AttendancePipelineStep.authenticatingBiometric, advertisement);

    final bioResult = await _biometric.authenticate(
      reason:
          'Verify your identity to record attendance in ${advertisement.classroomId}',
    );

    // Handle biometric result — abort on cancel, fail on error
    bool biometricPassed = false;
    switch (bioResult) {
      case BiometricSuccess():
        biometricPassed = true;
      case BiometricCancelled():
        // Silent cancel — return user to idle
        state = const AttendanceIdle();
        return;
      case BiometricFailure(reason: final r):
        _fail(
          step: AttendancePipelineStep.authenticatingBiometric,
          reason: r.userMessage,
          isRetryable: r != BiometricFailureReason.notAvailable &&
              r != BiometricFailureReason.notEnrolled,
          errorCode: 'BIOMETRIC_FAILED',
        );
        return;
    }

    // ── Step 4: Collect device fingerprint ───────────────────────────────────
    _setStep(AttendancePipelineStep.collectingFingerprint, advertisement);

    late final String fingerprint;
    try {
      fingerprint = await _fingerprint.getFingerprint();
    } catch (e) {
      _fail(
        step: AttendancePipelineStep.collectingFingerprint,
        reason: 'Failed to generate device fingerprint: $e',
        isRetryable: true,
      );
      return;
    }

    // ── Step 5: Build payload ─────────────────────────────────────────────────
    final request = AttendanceMarkRequest(
      sessionId: sessionId,   // ← real session UUID resolved in Step 0
      beaconToken: advertisement.token,
      deviceFingerprint: fingerprint,
      biometricVerified: biometricPassed,
      bleRssi: advertisement.rssi,
    );

    // ── Step 6: Submit to backend ─────────────────────────────────────────────
    _setStep(AttendancePipelineStep.submitting, advertisement);

    try {
      final record = await _repo.submitAttendanceWithContext(
        request: request,
        classroomId: advertisement.classroomId,
      );

      // ── Step 7: Success ────────────────────────────────────────────────────
      state = AttendanceSuccess(
        record: record,
        advertisement: advertisement,
      );
    } on ConflictException catch (e) {
      _fail(
        step: AttendancePipelineStep.submitting,
        reason: 'Attendance already recorded for this session.',
        isRetryable: false,
        errorCode: e.code ?? 'DUPLICATE_ATTENDANCE',
      );
    } on ForbiddenException {
      _fail(
        step: AttendancePipelineStep.submitting,
        reason: 'You are not enrolled in this session.',
        isRetryable: false,
        errorCode: 'NOT_ENROLLED',
      );
    } on UnauthorizedException {
      _fail(
        step: AttendancePipelineStep.submitting,
        reason: 'Session expired. Please sign in again.',
        isRetryable: false,
        errorCode: 'UNAUTHORIZED',
      );
    } on ValidationException catch (e) {
      _fail(
        step: AttendancePipelineStep.submitting,
        reason: e.message,
        isRetryable: false,
        errorCode: 'VALIDATION_ERROR',
      );
    } on NetworkException {
      _fail(
        step: AttendancePipelineStep.submitting,
        reason: 'No internet connection. Please try again.',
        isRetryable: true,
        errorCode: 'NETWORK_ERROR',
      );
    } on ServerException catch (e) {
      _fail(
        step: AttendancePipelineStep.submitting,
        reason: e.message,
        isRetryable: e.statusCode != null && e.statusCode! < 500,
        errorCode: 'SERVER_ERROR',
      );
    } catch (e) {
      _fail(
        step: AttendancePipelineStep.submitting,
        reason: 'An unexpected error occurred: $e',
        isRetryable: true,
      );
    }
  }

  // ── History ────────────────────────────────────────────────────────────────

  /// Reset to idle — used after viewing result or when cancelling.
  void reset() => state = const AttendanceIdle();

  // ── Internal helpers ───────────────────────────────────────────────────────

  void _setStep(
    AttendancePipelineStep step,
    AttendanceSessionAdvertisement advertisement,
  ) {
    state = AttendanceInProgress(step: step, advertisement: advertisement);
  }

  void _fail({
    required AttendancePipelineStep step,
    required String reason,
    required bool isRetryable,
    String? errorCode,
  }) {
    state = AttendanceFailure(
      reason: reason,
      step: step,
      isRetryable: isRetryable,
      errorCode: errorCode,
    );
  }
}

// ── History Controller ────────────────────────────────────────────────────────

class AttendanceHistoryController
    extends StateNotifier<AttendanceHistoryState> {
  AttendanceHistoryController(this._repo)
      : super(const AttendanceHistoryInitial());

  final AttendanceRepositoryInterface _repo;

  Future<void> loadHistory() async {
    state = const AttendanceHistoryLoading();
    try {
      final records = await _repo.getAttendanceHistory();
      final analytics = await _repo.getLocalAnalytics();
      state = AttendanceHistoryLoaded(records: records, analytics: analytics);
    } catch (e) {
      state = AttendanceHistoryError('Failed to load attendance history: $e');
    }
  }

  Future<void> refresh() => loadHistory();
}

// ── Providers ─────────────────────────────────────────────────────────────────

/// Primary attendance submission controller.
final attendanceControllerProvider =
    StateNotifierProvider<AttendanceController, AttendanceState>((ref) {
  return AttendanceController(
    repository: ref.watch(attendanceRepositoryProvider),
    fingerprintService: ref.watch(deviceFingerprintProvider),
    biometricService: ref.watch(biometricServiceProvider),
    deviceController:
        ref.read(deviceControllerProvider.notifier),
  );
});

/// Attendance history controller.
final attendanceHistoryProvider =
    StateNotifierProvider<AttendanceHistoryController, AttendanceHistoryState>(
        (ref) {
  return AttendanceHistoryController(
    ref.watch(attendanceRepositoryProvider),
  );
});

/// Convenience — last successful record (from current session).
final lastAttendanceRecordProvider = Provider<AttendanceRecord?>((ref) {
  final state = ref.watch(attendanceControllerProvider);
  if (state is AttendanceSuccess) return state.record;
  return null;
});
