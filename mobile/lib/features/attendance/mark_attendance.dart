import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/theme/colors.dart';
import '../beacon/beacon_controller.dart';
import '../device/device_identity.dart';
import '../face/face_capture_screen.dart';
import '../location/location_service.dart';
import 'attendance_api.dart';

/// The whole check-in / check-out flow:
///
///   beacon in range → server challenge (validates the rotating token)
///   → camera: random liveness steps + face signature (on the phone)
///   → GPS fix → server verification → result.
Future<void> markAttendance(BuildContext context, WidgetRef ref, String action) async {
  final beacon = ref.read(beaconControllerProvider).nearest;
  if (beacon == null) {
    _showError(context, 'No campus beacon in range. Move closer to a beacon and try again.');
    return;
  }

  final api = ref.read(attendanceApiProvider);
  final navigator = Navigator.of(context);
  _showProgress(context, 'Checking the campus beacon…');

  DeviceIdentity identity;
  Challenge challenge;
  try {
    identity = await ref.read(deviceIdentityProvider.future);
    challenge = await api.challenge(
      action: action,
      beacon: beacon,
      fingerprint: identity.fingerprint,
      isPhysicalDevice: identity.isPhysicalDevice,
    );
  } catch (e) {
    navigator.pop();
    if (context.mounted) _showError(context, errorMessage(e));
    return;
  }
  navigator.pop();
  if (!context.mounted) return;

  // Get GPS while the user is busy with the camera.
  final locationFuture = LocationService.currentFix();

  final capture = await FaceCaptureScreen.open(
    context,
    mode: FaceCaptureMode.verify,
    steps: challenge.steps,
    deadline: challenge.expiresAt,
  );
  if (capture == null || capture.embeddings.isEmpty) {
    if (context.mounted) _showError(context, 'Face verification was cancelled.');
    return;
  }
  if (!context.mounted) return;

  _showProgress(context, 'Verifying…');
  try {
    // Prefer a fresh reading of the same beacon (token may have rotated).
    final fresh = ref.read(beaconControllerProvider).byId(challenge.beaconId) ?? beacon;
    final location = await locationFuture.timeout(
      const Duration(seconds: 12),
      onTimeout: () => null,
    );
    final result = await api.submit(
      challenge: challenge,
      beacon: fresh,
      embedding: capture.embeddings.first,
      completedSteps: capture.completedSteps,
      fingerprint: identity.fingerprint,
      isPhysicalDevice: identity.isPhysicalDevice,
      location: location,
    );
    navigator.pop();
    ref.invalidate(todayProvider);
    ref.invalidate(historyProvider);
    if (context.mounted) await _showSuccess(context, result);
  } catch (e) {
    navigator.pop();
    if (context.mounted) _showError(context, errorMessage(e));
  }
}

void _showProgress(BuildContext context, String text) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(width: 20),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    ),
  );
}

void _showError(BuildContext context, String message) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.gpp_bad_outlined, color: AppColors.error, size: 40),
      title: const Text('Not marked'),
      content: Text(message),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ),
  );
}

Future<void> _showSuccess(BuildContext context, SubmitResult result) {
  final checkIn = result.action == 'check_in';
  final time = checkIn ? result.record.checkInAt : result.record.checkOutAt;
  final late = checkIn && result.record.status == 'late';
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.verified, color: late ? AppColors.warning : AppColors.success, size: 48),
      title: Text(checkIn ? (late ? 'Checked in (late)' : 'Checked in') : 'Checked out'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Time: ${Fmt.time(time)}'),
          if (result.beaconName != null) Text('Beacon: ${result.beaconName}'),
          Text('Face match: ${(result.faceScore * 100).toStringAsFixed(0)}%'),
          if (result.distanceM != null)
            Text('Distance from campus centre: ${result.distanceM!.toStringAsFixed(0)} m'),
          if (result.flags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Flagged for review: ${result.flags.join(', ')}',
              style: const TextStyle(color: AppColors.warning),
            ),
          ],
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))],
    ),
  );
}
