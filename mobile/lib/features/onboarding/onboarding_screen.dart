import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../core/config.dart';
import '../../core/theme/colors.dart';
import '../../shared/widgets.dart';
import '../auth/auth_service.dart';
import '../auth/models.dart';
import '../auth/session.dart';
import '../device/device_identity.dart';
import '../face/face_capture_screen.dart';
import '../face/liveness.dart';

/// First-run checklist: bind phone → enroll face → wait for admin approval.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, required this.me});

  final Me me;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() task) async {
    setState(() => _busy = true);
    try {
      await task();
      await ref.read(meProvider.notifier).reload();
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _registerDevice() => _run(() async {
    final identity = await ref.read(deviceIdentityProvider.future);
    if (!identity.isPhysicalDevice) {
      throw Exception('Emulators cannot be used for attendance.');
    }
    await ref.read(apiClientProvider).post('/devices/register', data: identity.toRegisterJson());
    if (mounted) showSnack(context, 'This phone is now bound to your account.');
  });

  Future<void> _enrollFace() async {
    final capture = await FaceCaptureScreen.open(
      context,
      mode: FaceCaptureMode.enroll,
      steps: [LivenessStep.blink.wire, LivenessStep.turnHead.wire],
      samples: AppConfig.enrollSamples,
      deadline: DateTime.now().add(const Duration(seconds: 90)),
    );
    if (capture == null || !mounted) return;
    await _run(() async {
      final identity = await ref.read(deviceIdentityProvider.future);
      await ref
          .read(apiClientProvider)
          .post(
            '/face/enroll',
            data: {
              'embeddings': capture.embeddings,
              'model_version': AppConfig.faceModelVersion,
              'device_fingerprint': identity.fingerprint,
              'liveness_steps': capture.completedSteps,
            },
          );
      if (mounted) showSnack(context, 'Face enrolled. Waiting for admin approval.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.me;
    final step = me.onboarding.nextStep;
    final faceRejected = me.onboarding.faceStatus == 'rejected';

    if (step == 'disabled') {
      return Scaffold(
        body: SafeArea(
          child: EmptyState(
            icon: Icons.block,
            color: AppColors.error,
            title: 'Your account is disabled',
            subtitle: 'Contact the office administrator.',
            action: OutlinedButton(
              onPressed: () => ref.read(authServiceProvider).signOut(),
              child: const Text('Sign out'),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up attendance'),
        actions: [
          if (me.profile.isAdmin)
            IconButton(
              tooltip: 'Admin',
              icon: const Icon(Icons.admin_panel_settings_outlined),
              onPressed: () => context.push('/admin'),
            ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authServiceProvider).signOut(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(meProvider.notifier).reload(),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Welcome, ${me.profile.firstName}!',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(
              'Three quick steps before you can mark attendance from your phone.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            _StepTile(
              number: 1,
              title: 'Bind this phone',
              body: 'Attendance can only be marked from one registered phone.',
              done: me.onboarding.deviceRegistered,
              active: step == 'register_device',
              action: step == 'register_device'
                  ? BusyButton(
                      label: 'Use this phone',
                      icon: Icons.phonelink_lock,
                      busy: _busy,
                      onPressed: _registerDevice,
                    )
                  : null,
            ),
            _StepTile(
              number: 2,
              title: faceRejected ? 'Enroll your face again' : 'Enroll your face',
              body: faceRejected
                  ? 'The admin asked you to re-enroll. Use good light and look straight at the camera.'
                  : 'Blink and turn your head, then hold still for 3 captures. '
                        'Only a face signature is stored — never your photo.',
              done: me.onboarding.faceEnrolled,
              active: step == 'enroll_face',
              action: step == 'enroll_face'
                  ? BusyButton(
                      label: 'Start face enrollment',
                      icon: Icons.face_retouching_natural,
                      busy: _busy,
                      onPressed: _enrollFace,
                    )
                  : null,
            ),
            _StepTile(
              number: 3,
              title: 'Admin approval',
              body: me.profile.isAdmin
                  ? 'You are an admin: open the admin panel (top right) and approve your own account.'
                  : 'Ask the office administrator to approve your account. Pull down to refresh.',
              done: me.onboarding.approved && me.onboarding.faceStatus == 'approved',
              active: step == 'await_approval',
              action: step == 'await_approval'
                  ? OutlinedButton.icon(
                      onPressed: _busy ? null : () => ref.read(meProvider.notifier).reload(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Check again'),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.number,
    required this.title,
    required this.body,
    required this.done,
    required this.active,
    this.action,
  });

  final int number;
  final String title;
  final String body;
  final bool done;
  final bool active;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final color = done
        ? AppColors.success
        : active
        ? AppColors.primary
        : AppColors.textTertiary;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: done
                      ? Icon(Icons.check, color: color, size: 18)
                      : Text(
                          '$number',
                          style: TextStyle(color: color, fontWeight: FontWeight.bold),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
              ],
            ),
            const SizedBox(height: 8),
            Text(body, style: Theme.of(context).textTheme.bodyMedium),
            if (action != null) ...[const SizedBox(height: 14), action!],
          ],
        ),
      ),
    );
  }
}
