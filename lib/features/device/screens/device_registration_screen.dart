import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../controllers/biometric_controller.dart';
import '../controllers/device_controller.dart';
import '../models/device_models.dart';
import '../widgets/device_widgets.dart';

/// Device Registration Screen — guides the student through:
///   1. Device fingerprint collection
///   2. Biometric authentication (proves consent)
///   3. Backend device registration
///
/// This screen is shown when [DeviceUnregistered] or [DeviceMismatch].
class DeviceRegistrationScreen extends ConsumerStatefulWidget {
  const DeviceRegistrationScreen({super.key});

  @override
  ConsumerState<DeviceRegistrationScreen> createState() =>
      _DeviceRegistrationScreenState();
}

class _DeviceRegistrationScreenState
    extends ConsumerState<DeviceRegistrationScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fadeAnim =
        CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deviceState = ref.watch(deviceControllerProvider);
    final bioState = ref.watch(biometricControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Register Device'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Stack(
        children: [
          FadeTransition(
            opacity: _fadeAnim,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  _buildHeader(),
                  const SizedBox(height: 32),
                  _buildStepIndicator(deviceState, bioState),
                  const SizedBox(height: 32),
                  _buildContent(context, deviceState, bioState),
                ],
              ),
            ),
          ),
          // Overlay during registration
          if (deviceState is DeviceRegistering)
            const SecurityLoadingOverlay(
                message: 'Registering device…'),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.phonelink_lock, color: Colors.white, size: 40),
        ),
        const SizedBox(height: 20),
        Text('Secure Device Registration',
            style: AppTypography.headlineMedium,
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          'Link this device to your account for attendance verification.',
          style: AppTypography.bodyMedium
              .copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildStepIndicator(DeviceState deviceState, BiometricState bioState) {
    final step1Done = true; // Device fingerprint always collected
    final step2Done = bioState is BiometricAuthenticated;
    final step3Done = deviceState is DeviceRegistered;

    return Row(
      children: [
        _StepDot(number: 1, label: 'Fingerprint', done: step1Done, active: !step2Done),
        _StepLine(done: step2Done),
        _StepDot(number: 2, label: 'Biometrics', done: step2Done, active: step1Done && !step3Done),
        _StepLine(done: step3Done),
        _StepDot(number: 3, label: 'Register', done: step3Done, active: step2Done),
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    DeviceState deviceState,
    BiometricState bioState,
  ) {
    // Step 3: Registered
    if (deviceState is DeviceRegistered) {
      return _RegistrationSuccess(device: deviceState.device);
    }

    // Error states
    if (deviceState is DeviceError) {
      return _ErrorCard(
        message: deviceState.message,
        onRetry: () =>
            ref.read(deviceControllerProvider.notifier).checkDeviceStatus(),
      );
    }

    if (deviceState is DeviceMismatch) {
      return _MismatchCard(
        onReplace: () => _handleDeviceReplacement(context),
      );
    }

    // Step 2: Biometric — fingerprint ready, need biometric auth
    if (bioState is BiometricAuthenticated) {
      return _ReadyToRegisterCard(
        onRegister: () =>
            ref.read(deviceControllerProvider.notifier).registerDevice(),
      );
    }

    // Biometric error states
    if (bioState is BiometricAuthFailed) {
      return _BiometricErrorCard(
        reason: bioState.reason,
        onRetry: () => _requestBiometric(),
      );
    }

    if (bioState is BiometricUnavailableState) {
      return _BiometricUnavailableCard(
        availability: bioState.availability,
      );
    }

    // Step 1 / default: Show device info and request biometric
    final metadata = deviceState is DeviceUnregistered
        ? deviceState.metadata
        : null;

    return Column(
      children: [
        if (metadata != null) _DeviceInfoCard(metadata: metadata),
        const SizedBox(height: 16),
        _BiometricConsentCard(
          isLoading: bioState is BiometricAuthenticating ||
              bioState is BiometricCheckingAvailability,
          onAuthenticate: () => _requestBiometric(),
        ),
      ],
    );
  }

  Future<void> _requestBiometric() async {
    ref.read(biometricControllerProvider.notifier).reset();
    await ref.read(biometricControllerProvider.notifier).authenticate(
          reason:
              'Verify your identity to register this device for attendance',
        );
  }

  Future<void> _handleDeviceReplacement(BuildContext context) async {
    final confirmed = await showDeviceReplacementDialog(context);
    if (confirmed && mounted) {
      await ref.read(deviceControllerProvider.notifier).registerDevice();
    }
  }
}

// ── Step indicator widgets ─────────────────────────────────────────────────────

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.number,
    required this.label,
    required this.done,
    required this.active,
  });

  final int number;
  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = done
        ? AppColors.success
        : active
            ? AppColors.primary
            : AppColors.border;
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: done || active ? color : AppColors.surfaceVariant,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Center(
            child: done
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : Text(
                    '$number',
                    style: AppTypography.labelMedium.copyWith(
                      color: active ? Colors.white : AppColors.textTertiary,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: AppTypography.labelSmall.copyWith(
                color: done || active
                    ? AppColors.textPrimary
                    : AppColors.textTertiary)),
      ],
    );
  }
}

class _StepLine extends StatelessWidget {
  const _StepLine({required this.done});
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 20, left: 4, right: 4),
        decoration: BoxDecoration(
          color: done ? AppColors.success : AppColors.border,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}

// ── Content cards ─────────────────────────────────────────────────────────────

class _DeviceInfoCard extends StatelessWidget {
  const _DeviceInfoCard({required this.metadata});
  final DeviceMetadata metadata;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.smartphone_outlined,
                    color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text('Device Information',
                    style: AppTypography.titleSmall),
              ],
            ),
            const Divider(height: 20),
            _InfoRow('Model', metadata.deviceModel),
            _InfoRow('Manufacturer', metadata.manufacturer),
            _InfoRow('Android', metadata.osVersion),
            _InfoRow('SDK', metadata.sdkVersion.toString()),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: AppTypography.labelMedium
                    .copyWith(color: AppColors.textSecondary)),
          ),
          Expanded(
              child: Text(value, style: AppTypography.bodySmall)),
        ],
      ),
    );
  }
}

class _BiometricConsentCard extends StatelessWidget {
  const _BiometricConsentCard({
    required this.onAuthenticate,
    required this.isLoading,
  });
  final VoidCallback onAuthenticate;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.fingerprint,
                  color: AppColors.primary, size: 48),
            ),
            const SizedBox(height: 16),
            Text('Biometric Consent Required',
                style: AppTypography.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Authenticate with your fingerprint or face to confirm you consent to registering this device.',
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isLoading ? null : onAuthenticate,
                icon: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.fingerprint, size: 20),
                label: Text(isLoading
                    ? 'Verifying…'
                    : 'Verify with Biometrics'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadyToRegisterCard extends StatelessWidget {
  const _ReadyToRegisterCard({required this.onRegister});
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.successSurface,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle,
                  color: AppColors.success, size: 48),
            ),
            const SizedBox(height: 16),
            Text('Identity Verified',
                style: AppTypography.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Biometric authentication successful. Ready to register this device.',
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onRegister,
                icon: const Icon(Icons.phonelink_lock, size: 20),
                label: const Text('Register This Device'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RegistrationSuccess extends StatelessWidget {
  const _RegistrationSuccess({required this.device});
  final DeviceInfo device;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppColors.successGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.success.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(Icons.verified, color: Colors.white, size: 48),
            ),
            const SizedBox(height: 20),
            Text('Device Registered!',
                style: AppTypography.headlineMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'This device is now linked to your account. You can take attendance.',
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // Device fingerprint preview
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.successSurface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.security, color: AppColors.success, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${device.deviceFingerprint.substring(0, 16)}…',
                      style: AppTypography.labelSmall.copyWith(
                        fontFamily: 'monospace',
                        color: AppColors.success,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.home_rounded),
                label: const Text('Back to Dashboard'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BiometricErrorCard extends StatelessWidget {
  const _BiometricErrorCard({required this.reason, required this.onRetry});
  final BiometricFailureReason reason;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.errorSurface,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.fingerprint,
                  color: AppColors.error, size: 48),
            ),
            const SizedBox(height: 16),
            Text('Verification Failed',
                style: AppTypography.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              reason.userMessage,
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (reason != BiometricFailureReason.notAvailable &&
                reason != BiometricFailureReason.notEnrolled &&
                reason != BiometricFailureReason.notSecured)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 20),
                  label: const Text('Try Again'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BiometricUnavailableCard extends StatelessWidget {
  const _BiometricUnavailableCard({required this.availability});
  final BiometricAvailability availability;

  @override
  Widget build(BuildContext context) {
    final (title, body) = switch (availability) {
      BiometricAvailability.notEnrolled => (
          'No Biometrics Enrolled',
          'Please set up a fingerprint or face unlock in your device Settings, then return to register.',
        ),
      BiometricAvailability.notSecured => (
          'Device Not Secured',
          'A PIN, pattern, or password lock screen is required to use biometric authentication.',
        ),
      _ => (
          'Biometrics Unavailable',
          'Biometric hardware is not available on this device.',
        ),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.no_encryption_outlined,
                color: AppColors.warning, size: 48),
            const SizedBox(height: 16),
            Text(title,
                style: AppTypography.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(body,
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _MismatchCard extends StatelessWidget {
  const _MismatchCard({required this.onReplace});
  final VoidCallback onReplace;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.errorSurface,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.device_unknown,
                  color: AppColors.error, size: 48),
            ),
            const SizedBox(height: 16),
            Text('Different Device Registered',
                style: AppTypography.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Your account is linked to a different device. You can replace it, but this will be logged.',
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onReplace,
                icon: const Icon(Icons.swap_horiz_rounded,
                    color: AppColors.warning),
                label: const Text('Replace Device',
                    style: TextStyle(color: AppColors.warning)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.warning),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 48),
            const SizedBox(height: 16),
            Text('Something went wrong',
                style: AppTypography.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message,
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
