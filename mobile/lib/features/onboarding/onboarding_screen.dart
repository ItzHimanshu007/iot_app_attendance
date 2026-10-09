import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../core/config.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../shared/widgets.dart';
import '../auth/auth_service.dart';
import '../auth/models.dart';
import '../auth/session.dart';
import '../device/device_identity.dart';
import '../face/face_capture_screen.dart';
import '../face/liveness.dart';

/// First-run checklist: bind phone → enroll face → admin approval.
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
    if (mounted) showSnack(context, 'This phone is now registered to your account.');
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
    final onboarding = me.onboarding;
    final step = onboarding.nextStep;

    if (step == 'disabled') {
      return Scaffold(
        body: SafeArea(
          child: EmptyState(
            icon: Icons.block_rounded,
            color: AppColors.error,
            title: 'Account disabled',
            subtitle: 'Your account has been disabled. Please contact ${AppConfig.supportContact}.',
            action: SizedBox(
              width: 180,
              child: OutlinedButton(
                onPressed: () => ref.read(authServiceProvider).signOut(),
                child: const Text('Sign out'),
              ),
            ),
          ),
        ),
      );
    }

    final faceRejected = onboarding.faceStatus == 'rejected';
    final approved = onboarding.approved && onboarding.faceStatus == 'approved';
    final done = [
      onboarding.deviceRegistered,
      onboarding.faceEnrolled,
      approved,
    ].where((d) => d).length;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.read(meProvider.notifier).reload(),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            GradientHeader(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const BrandLogo(size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          AppConfig.collegeName,
                          style: AppText.h3.copyWith(color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (me.profile.isAdmin)
                        IconButton(
                          tooltip: 'Admin console',
                          color: Colors.white,
                          icon: const Icon(Icons.admin_panel_settings_outlined),
                          onPressed: () => context.push('/admin'),
                        ),
                      IconButton(
                        tooltip: 'Sign out',
                        color: Colors.white,
                        icon: const Icon(Icons.logout_rounded),
                        onPressed: () => ref.read(authServiceProvider).signOut(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Welcome, ${me.profile.firstName}',
                    style: AppText.h1.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Finish these steps to start marking attendance from your phone.',
                    style: AppText.body.copyWith(color: Colors.white.withValues(alpha: 0.78)),
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: done / 3,
                            minHeight: 8,
                            color: AppColors.gold,
                            backgroundColor: Colors.white.withValues(alpha: 0.18),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$done of 3 completed',
                          style: AppText.caption.copyWith(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              child: Column(
                children: [
                  _StepCard(
                    number: 1,
                    icon: Icons.phonelink_lock_rounded,
                    title: 'Register this phone',
                    body:
                        'Attendance can only be marked from one registered phone. '
                        'Changing phones later needs admin approval.',
                    state: onboarding.deviceRegistered
                        ? _StepState.done
                        : step == 'register_device'
                        ? _StepState.current
                        : _StepState.locked,
                    doneNote: me.device?['device_model'] == null
                        ? null
                        : 'Registered: ${me.device!['device_model']}',
                    action: PrimaryButton(
                      label: 'Register this phone',
                      icon: Icons.verified_user_outlined,
                      busy: _busy,
                      onPressed: _registerDevice,
                    ),
                  ),
                  _StepCard(
                    number: 2,
                    icon: Icons.face_retouching_natural,
                    title: faceRejected ? 'Enroll your face again' : 'Enroll your face',
                    body: faceRejected
                        ? 'The administrator asked you to re-enroll. Use good light and look '
                              'straight at the camera.'
                        : 'Blink and turn your head when asked, then hold still for three quick '
                              'captures. Only a face signature is stored — never your photo.',
                    state: onboarding.faceEnrolled
                        ? _StepState.done
                        : step == 'enroll_face'
                        ? _StepState.current
                        : _StepState.locked,
                    warning: faceRejected,
                    action: PrimaryButton(
                      label: 'Start face enrollment',
                      icon: Icons.camera_front_outlined,
                      busy: _busy,
                      onPressed: _enrollFace,
                    ),
                  ),
                  _StepCard(
                    number: 3,
                    icon: Icons.verified_rounded,
                    title: 'Administrator approval',
                    body: me.profile.isAdmin
                        ? 'You are an administrator: open the admin console (top right) and '
                              'approve your own account.'
                        : 'The administrator verifies your details and approves your account. '
                              'Pull down to refresh.',
                    state: approved
                        ? _StepState.done
                        : step == 'await_approval'
                        ? _StepState.current
                        : _StepState.locked,
                    action: OutlinedButton.icon(
                      onPressed: _busy ? null : () => ref.read(meProvider.notifier).reload(),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Check approval status'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  MessageBanner(
                    icon: Icons.support_agent_rounded,
                    message: 'Need help? Contact ${AppConfig.supportContact}.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _StepState { done, current, locked }

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.icon,
    required this.title,
    required this.body,
    required this.state,
    required this.action,
    this.doneNote,
    this.warning = false,
  });

  final int number;
  final IconData icon;
  final String title;
  final String body;
  final _StepState state;
  final Widget action;
  final String? doneNote;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final (color, chip) = switch (state) {
      _StepState.done => (
        AppColors.success,
        StatusChip.tone('Done', AppColors.success, icon: Icons.check_rounded, dense: true),
      ),
      _StepState.current => (
        warning ? AppColors.warning : AppColors.primary,
        StatusChip.tone(
          warning ? 'Action needed' : 'Next step',
          warning ? AppColors.warning : AppColors.primary,
          dense: true,
        ),
      ),
      _StepState.locked => (
        AppColors.textTertiary,
        StatusChip.tone(
          'Pending',
          AppColors.textTertiary,
          icon: Icons.lock_outline_rounded,
          dense: true,
        ),
      ),
    };
    final current = state == _StepState.current;
    return AppCard(
      margin: const EdgeInsets.only(bottom: 14),
      borderColor: current ? color.withValues(alpha: 0.6) : null,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: state == _StepState.done
                    ? Icon(Icons.check_rounded, color: color)
                    : Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('STEP $number', style: AppText.overline),
                    const SizedBox(height: 2),
                    Text(title, style: AppText.h3),
                  ],
                ),
              ),
              chip,
            ],
          ),
          if (state != _StepState.done || doneNote == null) ...[
            const SizedBox(height: 12),
            Text(body, style: AppText.body),
          ] else ...[
            const SizedBox(height: 10),
            Text(doneNote!, style: AppText.caption),
          ],
          if (current) ...[
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: action),
          ],
        ],
      ),
    );
  }
}
