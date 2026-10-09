import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../controllers/attendance_controller.dart';
import '../controllers/ble_controller.dart';
import '../models/ble_models.dart';
import '../widgets/attendance_widgets.dart';
import '../../device/controllers/device_controller.dart';
import '../../../routes/app_router.dart';

/// Attendance submission screen.
///
/// This is the primary student attendance screen. It:
///   1. Shows BLE scan results from [BleController]
///   2. Triggers the 8-step [AttendanceController] pipeline
///   3. Shows live progress during submission
///   4. Displays the result (success / failure)
///
/// Navigated to from: StudentDashboard → 'Scan for Session'.
class AttendanceSubmissionScreen extends ConsumerStatefulWidget {
  // Optionally pre-loaded from SessionDiscoveryScreen via GoRouter extra
  final AttendanceSessionAdvertisement? preloadedAdvertisement;

  const AttendanceSubmissionScreen({super.key, this.preloadedAdvertisement});

  @override
  ConsumerState<AttendanceSubmissionScreen> createState() =>
      _AttendanceSubmissionScreenState();
}

class _AttendanceSubmissionScreenState
    extends ConsumerState<AttendanceSubmissionScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
    _fadeAnim =
        CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final preloaded = widget.preloadedAdvertisement;
      if (preloaded != null) {
        // Navigated from SessionDiscoveryScreen with a known beacon —
        // auto-submit immediately without a new BLE scan.
        _startSubmission(preloaded);
      } else {
        // Navigated from StudentDashboard — auto-start BLE scan.
        ref.read(bleControllerProvider.notifier).startScan();
      }
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bleState = ref.watch(bleControllerProvider);
    final attendanceState = ref.watch(attendanceControllerProvider);
    final bestBeacon = ref.watch(bestBeaconProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mark Attendance'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            ref.read(attendanceControllerProvider.notifier).reset();
            ref.read(bleControllerProvider.notifier).stopScan();
            context.pop();
          },
        ),
        actions: [
          // History button
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Attendance History',
            onPressed: () => context.push(RoutePaths.attendanceHistory),
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: RefreshIndicator(
          onRefresh: () async {
            await ref.read(bleControllerProvider.notifier).rescan();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Attendance result overlay ─────────────────────────────
                _buildAttendanceStateView(
                    context, attendanceState, bestBeacon),

                const SizedBox(height: 16),

                // ── BLE scan section ─────────────────────────────────────
                if (attendanceState is AttendanceIdle ||
                    attendanceState is AttendanceFailure) ...[
                  Text('Nearby Sessions', style: AppTypography.headlineSmall),
                  const SizedBox(height: 12),
                  _BleSection(
                    bleState: bleState,
                    onBeaconSelected: (advert) => _startSubmission(advert),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),

    );
  }

  Widget _buildAttendanceStateView(
    BuildContext context,
    AttendanceState state,
    AttendanceSessionAdvertisement? beacon,
  ) {
    return switch (state) {
      AttendanceIdle() => const SizedBox.shrink(),

      AttendanceInProgress(step: final step, advertisement: final advert) =>
        AttendanceSubmittingCard(
          step: step,
          classroomId: advert?.classroomId ?? '—',
        ),

      AttendanceSuccess(
        record: final record,
        advertisement: final advert
      ) =>
        AttendanceSuccessCard(
          record: record,
          classroomId: advert.classroomId,
          onDone: () {
            ref.read(attendanceControllerProvider.notifier).reset();
            context.pop();
          },
        ),

      AttendanceFailure(
        reason: final reason,
        step: final step,
        isRetryable: final retryable
      ) =>
        AttendanceFailureCard(
          reason: reason,
          step: step,
          isRetryable: retryable,
          onRetry: retryable && beacon != null
              ? () => _startSubmission(beacon)
              : null,
          onDismiss: () =>
              ref.read(attendanceControllerProvider.notifier).reset(),
        ),
    };
  }

  Future<void> _startSubmission(
      AttendanceSessionAdvertisement advertisement) async {
    // Verify device is registered before starting pipeline
    final deviceState =
        ref.read(deviceControllerProvider);
    if (deviceState is! DeviceRegistered) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Register your device first.'),
          action: SnackBarAction(
            label: 'Register',
            onPressed: () => context.push(RoutePaths.deviceRegistration),
          ),
        ),
      );
      return;
    }

    await ref
        .read(attendanceControllerProvider.notifier)
        .submitAttendance(advertisement);
  }
}

// ── BLE Section ───────────────────────────────────────────────────────────────

class _BleSection extends StatelessWidget {
  const _BleSection({
    required this.bleState,
    required this.onBeaconSelected,
  });

  final BleState bleState;
  final void Function(AttendanceSessionAdvertisement) onBeaconSelected;

  @override
  Widget build(BuildContext context) {
    return switch (bleState) {
      BleIdle() || BleCheckingPrerequisites() => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
        ),

      BleDisabled() => _BleDisabledCard(),
      BlePermissionDenied() => _BlePermissionCard(),

      BleScanning(advertisements: final ads) => ads.isEmpty
          ? _ScanningEmptyCard()
          : _BeaconList(
              advertisements: ads,
              onTap: onBeaconSelected,
              isScanning: true,
            ),

      BleScanComplete(advertisements: final ads) => ads.isEmpty
          ? _NoBeaconsCard()
          : _BeaconList(
              advertisements: ads,
              onTap: onBeaconSelected,
              isScanning: false,
            ),

      BleError(message: final msg) => _BleErrorCard(message: msg),
    };
  }
}

class _BleDisabledCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.bluetooth_disabled, size: 48,
                color: AppColors.textTertiary),
            const SizedBox(height: 12),
            Text('Bluetooth is Off', style: AppTypography.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Enable Bluetooth to scan for attendance sessions.',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _BlePermissionCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.bluetooth_searching, size: 48,
                color: AppColors.warning),
            const SizedBox(height: 12),
            Text('Bluetooth Permission Required',
                style: AppTypography.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Allow Bluetooth access in Settings to find sessions.',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanningEmptyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Scanning for sessions…',
                style: AppTypography.bodyMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              'Make sure you are near the classroom.',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoBeaconsCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.search_off_rounded, size: 48,
                color: AppColors.textTertiary),
            const SizedBox(height: 12),
            Text('No Sessions Found', style: AppTypography.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'No active attendance sessions nearby. Are you in the right classroom?',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () =>
                  ref.read(bleControllerProvider.notifier).rescan(),
              icon: const Icon(Icons.refresh),
              label: const Text('Scan Again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BleErrorCard extends ConsumerWidget {
  const _BleErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text('Scan Error', style: AppTypography.titleMedium),
            const SizedBox(height: 8),
            Text(message,
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () =>
                  ref.read(bleControllerProvider.notifier).rescan(),
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BeaconList extends StatelessWidget {
  const _BeaconList({
    required this.advertisements,
    required this.onTap,
    required this.isScanning,
  });

  final List<AttendanceSessionAdvertisement> advertisements;
  final void Function(AttendanceSessionAdvertisement) onTap;
  final bool isScanning;

  @override
  Widget build(BuildContext context) {
    final inRange = advertisements.where((a) => a.isInRange).toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    final outOfRange = advertisements.where((a) => !a.isInRange).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isScanning)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(),
          ),
        ...inRange.map((advert) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AttendanceReadyCard(
                classroomId: advert.classroomId,
                rssi: advert.rssi,
                onSubmit: () => onTap(advert),
              ),
            )),
        if (outOfRange.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Out of range (${outOfRange.length})',
            style: AppTypography.labelMedium
                .copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: 6),
          ...outOfRange.map((advert) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.wifi_off_outlined,
                            size: 20, color: AppColors.textTertiary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Room ${advert.classroomId}',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        Text(
                          '${advert.rssi} dBm',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.error.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )),
        ],
      ],
    );
  }
}

