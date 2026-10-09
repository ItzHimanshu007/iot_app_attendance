import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/error_text.dart';
import '../../core/formatters.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../shared/widgets.dart';
import '../beacon/beacon_controller.dart';
import '../device/device_identity.dart';
import '../face/face_capture_screen.dart';
import '../location/location_service.dart';
import 'attendance_api.dart';

/// Check-in / check-out flow:
///   beacon → server challenge → camera (liveness + face signature) → GPS → verify.
Future<void> markAttendance(BuildContext context, WidgetRef ref, String action) async {
  final beacon = ref.read(beaconControllerProvider).nearest;
  if (beacon == null) {
    await showVerificationError(
      context,
      const ApiException(
        'No campus beacon in range. Move closer to a beacon and try again.',
        code: 'BEACON_TOO_FAR',
      ),
    );
    return;
  }

  final api = ref.read(attendanceApiProvider);
  final progress = ValueNotifier<int>(0);
  final close = _showProgress(context, progress);

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
    close();
    if (context.mounted && await showVerificationError(context, e, allowRetry: true)) {
      if (context.mounted) return markAttendance(context, ref, action);
    }
    return;
  }
  close();
  if (!context.mounted) return;

  final locationFuture = LocationService.currentFix();
  final capture = await FaceCaptureScreen.open(
    context,
    mode: FaceCaptureMode.verify,
    steps: challenge.steps,
    deadline: challenge.expiresAt,
  );
  if (capture == null || capture.embeddings.isEmpty || !context.mounted) {
    if (context.mounted) showSnack(context, 'Verification cancelled', error: true);
    return;
  }

  progress.value = 2;
  final close2 = _showProgress(context, progress);
  try {
    final fresh = ref.read(beaconControllerProvider).byId(challenge.beaconId) ?? beacon;
    final location = await locationFuture.timeout(
      const Duration(seconds: 12),
      onTimeout: () => null,
    );
    progress.value = 3;
    final result = await api.submit(
      challenge: challenge,
      beacon: fresh,
      embedding: capture.embeddings.first,
      completedSteps: capture.completedSteps,
      fingerprint: identity.fingerprint,
      isPhysicalDevice: identity.isPhysicalDevice,
      location: location,
    );
    close2();
    ref.invalidate(todayProvider);
    ref.invalidate(historyProvider);
    if (context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => AttendanceResultScreen(result: result),
        ),
      );
    }
  } catch (e) {
    close2();
    if (context.mounted && await showVerificationError(context, e, allowRetry: true)) {
      // A fresh challenge with new liveness steps; the old one is used up.
      if (context.mounted) return markAttendance(context, ref, action);
    }
  }
}

// ── Progress dialog ──────────────────────────────────────────────────────────

const _steps = [
  (Icons.bluetooth_rounded, 'Campus beacon'),
  (Icons.face_rounded, 'Face & liveness'),
  (Icons.location_on_outlined, 'Location'),
  (Icons.cloud_upload_outlined, 'Recording attendance'),
];

/// Shows the step list; returns a function that closes it.
VoidCallback _showProgress(BuildContext context, ValueNotifier<int> current) {
  final navigator = Navigator.of(context, rootNavigator: true);
  var open = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(canPop: false, child: VerificationProgressDialog(current: current)),
  ).then((_) => open = false);
  return () {
    if (open) {
      open = false;
      navigator.pop();
    }
  };
}

class VerificationProgressDialog extends StatelessWidget {
  const VerificationProgressDialog({super.key, required this.current});

  final ValueListenable<int> current;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 36),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 14),
        child: ValueListenableBuilder<int>(
          valueListenable: current,
          builder: (context, active, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Verifying attendance', style: AppText.h2),
              const SizedBox(height: 4),
              const Text('Please keep the app open.', style: AppText.caption),
              const SizedBox(height: 16),
              for (var i = 0; i < _steps.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: i < active
                            ? const CircleAvatar(
                                backgroundColor: AppColors.successSoft,
                                child: Icon(
                                  Icons.check_rounded,
                                  size: 16,
                                  color: AppColors.success,
                                ),
                              )
                            : i == active
                            ? const Padding(
                                padding: EdgeInsets.all(4),
                                child: CircularProgressIndicator(strokeWidth: 2.4),
                              )
                            : CircleAvatar(
                                backgroundColor: AppColors.surfaceMuted,
                                child: Icon(_steps[i].$1, size: 15, color: AppColors.textTertiary),
                              ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        _steps[i].$2,
                        style: i == active
                            ? AppText.bodyStrong
                            : AppText.body.copyWith(
                                color: i < active ? AppColors.text : AppColors.textTertiary,
                              ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Error sheet ───────────────────────────────────────────────────────────────

/// Explains why verification failed. With [allowRetry], errors the staff member
/// can fix by trying again get a "Try again" button; returns true if pressed.
Future<bool> showVerificationError(
  BuildContext context,
  Object error, {
  bool allowRetry = false,
}) async {
  final text = ErrorText.of(error);
  final retry = allowRetry && ErrorText.canRetry(error);
  final again = await showModalBottomSheet<bool>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(color: AppColors.errorSoft, shape: BoxShape.circle),
              child: Icon(text.icon, color: AppColors.error, size: 36),
            ),
            const SizedBox(height: 16),
            Text(text.title, style: AppText.h2, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(errorMessage(error), style: AppText.body, textAlign: TextAlign.center),
            if (text.tip != null) ...[
              const SizedBox(height: 16),
              MessageBanner(message: text.tip!, icon: Icons.lightbulb_outline_rounded),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: retry
                  ? FilledButton.icon(
                      onPressed: () => Navigator.pop(ctx, true),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try again'),
                    )
                  : FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ),
            if (retry)
              SizedBox(
                width: double.infinity,
                child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
              ),
          ],
        ),
      ),
    ),
  );
  return again ?? false;
}

// ── Success screen ────────────────────────────────────────────────────────────

class AttendanceResultScreen extends StatelessWidget {
  const AttendanceResultScreen({super.key, required this.result});

  final SubmitResult result;

  @override
  Widget build(BuildContext context) {
    final checkIn = result.action == 'check_in';
    final time = checkIn ? result.record.checkInAt : result.record.checkOutAt;
    final late = checkIn && result.record.status == 'late';
    final accent = late ? AppColors.warning : AppColors.success;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const Spacer(),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.6, end: 1),
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOutBack,
                builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
                child: Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.12),
                  ),
                  child: Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
                      child: const Icon(Icons.check_rounded, color: Colors.white, size: 46),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(checkIn ? 'Checked in' : 'Checked out', style: AppText.display),
              const SizedBox(height: 6),
              Text(
                '${Fmt.longDate(time ?? DateTime.now())} · ${Fmt.time(time)}',
                style: AppText.body,
              ),
              const SizedBox(height: 12),
              if (checkIn)
                late
                    ? StatusChip.tone('Late arrival', AppColors.warning)
                    : StatusChip.tone('On time', AppColors.success),
              const SizedBox(height: 28),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Column(
                  children: [
                    InfoRow(
                      icon: Icons.bluetooth_connected_rounded,
                      label: 'Campus beacon',
                      value: result.beaconName ?? 'Verified',
                      trailing: const Icon(
                        Icons.verified_rounded,
                        color: AppColors.success,
                        size: 20,
                      ),
                    ),
                    const Divider(),
                    InfoRow(
                      icon: Icons.face_rounded,
                      label: 'Face match',
                      value: '${(result.faceScore * 100).toStringAsFixed(0)}% similarity',
                      trailing: const Icon(
                        Icons.verified_rounded,
                        color: AppColors.success,
                        size: 20,
                      ),
                    ),
                    if (result.distanceM != null) ...[
                      const Divider(),
                      InfoRow(
                        icon: Icons.location_on_outlined,
                        label: 'Distance from campus centre',
                        value: '${result.distanceM!.toStringAsFixed(0)} m',
                      ),
                    ],
                  ],
                ),
              ),
              if (result.flags.isNotEmpty) ...[
                const SizedBox(height: 14),
                MessageBanner(
                  tone: BannerTone.warning,
                  title: 'Recorded with a note for the admin',
                  message: result.flags.map((f) => f.replaceAll('_', ' ')).join(', '),
                ),
              ],
              const Spacer(flex: 2),
              FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
            ],
          ),
        ),
      ),
    );
  }
}
