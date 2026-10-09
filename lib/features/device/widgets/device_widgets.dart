import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../models/device_models.dart';

// ── Device Status Card ────────────────────────────────────────────────────────

/// Compact card showing device registration status — used on dashboards.
class DeviceStatusCard extends StatelessWidget {
  const DeviceStatusCard({
    super.key,
    required this.status,
    this.deviceInfo,
    this.onTap,
  });

  final DeviceRegistrationStatus status;
  final DeviceInfo? deviceInfo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, color, title, subtitle) = _content();

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTypography.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                    ),
                    if (deviceInfo != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        deviceInfo!.deviceModel,
                        style: AppTypography.labelSmall
                            .copyWith(color: AppColors.textTertiary),
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.arrow_forward_ios,
                    size: 14, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  (IconData, Color, String, String) _content() {
    switch (status) {
      case DeviceRegistrationStatus.registered:
        return (
          Icons.verified_outlined,
          AppColors.success,
          'Device Registered',
          'This device is verified and active',
        );
      case DeviceRegistrationStatus.unregistered:
        return (
          Icons.phonelink_outlined,
          AppColors.warning,
          'Device Not Registered',
          'Register this device to take attendance',
        );
      case DeviceRegistrationStatus.inactive:
        return (
          Icons.phone_locked_outlined,
          AppColors.error,
          'Device Inactive',
          'Contact administrator to reactivate',
        );
      case DeviceRegistrationStatus.mismatch:
        return (
          Icons.device_unknown_outlined,
          AppColors.error,
          'Device Mismatch',
          'This account is linked to a different device',
        );
      case DeviceRegistrationStatus.unknown:
        return (
          Icons.help_outline,
          AppColors.textSecondary,
          'Status Unknown',
          'Unable to verify — check connection',
        );
    }
  }
}

// ── Biometric Type Icon ───────────────────────────────────────────────────────

class BiometricTypeIcon extends StatelessWidget {
  const BiometricTypeIcon({super.key, required this.type, this.size = 48});
  final AppBiometricType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = switch (type) {
      AppBiometricType.fingerprint => Icons.fingerprint,
      AppBiometricType.face => Icons.face_unlock_outlined,
      AppBiometricType.iris => Icons.remove_red_eye_outlined,
      AppBiometricType.none => Icons.security_outlined,
    };
    return Icon(icon, size: size, color: AppColors.primary);
  }
}

// ── Device Replacement Dialog ─────────────────────────────────────────────────

/// Shows a warning dialog before replacing the registered device.
Future<bool> showDeviceReplacementDialog(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.swap_horiz_rounded,
          color: AppColors.warning, size: 36),
      title: const Text('Replace Device?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Registering this device will deactivate your previously registered device.',
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warningSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    color: AppColors.warning, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'This action is logged and reviewed by administrators.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.warning,
            foregroundColor: Colors.white,
          ),
          child: const Text('Replace Device'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

// ── Loading Overlay ───────────────────────────────────────────────────────────

class SecurityLoadingOverlay extends StatelessWidget {
  const SecurityLoadingOverlay({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.4),
      child: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(message, style: AppTypography.bodyMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
