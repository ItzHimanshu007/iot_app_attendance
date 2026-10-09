import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../models/ble_models.dart';

// ── Bluetooth Disabled Card ──────────────────────────────────────────────────

/// Shown when Bluetooth hardware is off.
class BluetoothDisabledCard extends StatelessWidget {
  const BluetoothDisabledCard({super.key, this.onEnable});

  final VoidCallback? onEnable;

  @override
  Widget build(BuildContext context) {
    return _StateCard(
      icon: Icons.bluetooth_disabled,
      iconColor: AppColors.textSecondary,
      iconBgColor: AppColors.surfaceVariant,
      title: 'Bluetooth is Off',
      subtitle:
          'Enable Bluetooth to scan for nearby attendance sessions.',
      action: onEnable != null
          ? ElevatedButton.icon(
              onPressed: onEnable,
              icon: const Icon(Icons.bluetooth, size: 18),
              label: const Text('Enable Bluetooth'),
            )
          : null,
    );
  }
}

// ── Permission Denied Card ───────────────────────────────────────────────────

/// Shown when BLE permissions were denied.
class BlePermissionDeniedCard extends StatelessWidget {
  const BlePermissionDeniedCard({
    super.key,
    required this.onRequestPermission,
    this.isPermanent = false,
  });

  final VoidCallback onRequestPermission;
  final bool isPermanent;

  @override
  Widget build(BuildContext context) {
    return _StateCard(
      icon: Icons.lock_open_outlined,
      iconColor: AppColors.warning,
      iconBgColor: AppColors.warningSurface,
      title: 'Bluetooth Permission Required',
      subtitle: isPermanent
          ? 'Permission was permanently denied. Please enable Bluetooth access in Settings.'
          : 'Bluetooth scan permission is needed to detect nearby attendance sessions.',
      action: ElevatedButton.icon(
        onPressed: onRequestPermission,
        icon: Icon(
          isPermanent ? Icons.settings_outlined : Icons.security_outlined,
          size: 18,
        ),
        label: Text(isPermanent ? 'Open Settings' : 'Grant Permission'),
      ),
    );
  }
}

// ── BLE Scanning Card ────────────────────────────────────────────────────────

/// Animated scanning indicator.
class BleScanningScard extends StatefulWidget {
  const BleScanningScard({super.key, this.foundCount = 0});

  final int foundCount;

  @override
  State<BleScanningScard> createState() => _BleScanningScardState();
}

class _BleScanningScardState extends State<BleScanningScard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.08),
            AppColors.secondary.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) => Opacity(
              opacity: _pulse.value,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      blurRadius: 12 * _pulse.value,
                      spreadRadius: 2 * _pulse.value,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.bluetooth_searching,
                  color: AppColors.primary,
                  size: 26,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Scanning for Sessions…',
                    style: AppTypography.titleSmall),
                const SizedBox(height: 4),
                Text(
                  widget.foundCount > 0
                      ? 'Found ${widget.foundCount} beacon${widget.foundCount != 1 ? 's' : ''}'
                      : 'Looking for nearby ESP32 beacons',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      ),
    );
  }
}

// ── No Session Found Card ────────────────────────────────────────────────────

class NoSessionFoundCard extends StatelessWidget {
  const NoSessionFoundCard({super.key, required this.onRescan});

  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) {
    return _StateCard(
      icon: Icons.wifi_tethering_off,
      iconColor: AppColors.textTertiary,
      iconBgColor: AppColors.surfaceVariant,
      title: 'No Session Nearby',
      subtitle:
          'No active ESP32 beacon was detected. Make sure you are in the classroom and the session is active.',
      action: OutlinedButton.icon(
        onPressed: onRescan,
        icon: const Icon(Icons.refresh, size: 18),
        label: const Text('Scan Again'),
      ),
    );
  }
}

// ── Session Found Card ───────────────────────────────────────────────────────

/// Displays a detected SCA beacon.
class SessionFoundCard extends StatelessWidget {
  const SessionFoundCard({
    super.key,
    required this.advertisement,
    this.onTap,
  });

  final AttendanceSessionAdvertisement advertisement;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final signal = advertisement.signalStrength;
    final isInRange = advertisement.isInRange;
    final signalColor = _signalColor(signal);

    return Card(
      child: InkWell(
        onTap: isInRange ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // ── Header row ─────────────────────────────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isInRange
                          ? AppColors.successSurface
                          : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isInRange
                          ? Icons.wifi_tethering_rounded
                          : Icons.signal_wifi_bad_outlined,
                      color: isInRange
                          ? AppColors.success
                          : AppColors.textSecondary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Room ${advertisement.classroomId}',
                          style: AppTypography.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isInRange ? 'In range — tap to attend' : 'Too far away',
                          style: AppTypography.bodySmall.copyWith(
                            color: isInRange
                                ? AppColors.success
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // RSSI badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: signalColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: signalColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      '${advertisement.rssi} dBm',
                      style: AppTypography.labelSmall
                          .copyWith(color: signalColor),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // ── Signal strength bar ────────────────────────────────
              Row(
                children: [
                  _SignalBars(bars: signal.bars, color: signalColor),
                  const SizedBox(width: 8),
                  Text(
                    signal.label,
                    style: AppTypography.labelSmall
                        .copyWith(color: signalColor),
                  ),
                  const Spacer(),
                  // Device name chip
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      advertisement.deviceName,
                      style: AppTypography.labelSmall
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),

              // ── Token preview ──────────────────────────────────────
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.token_outlined,
                        size: 14, color: AppColors.textTertiary),
                    const SizedBox(width: 6),
                    Text(
                      'Token: ${advertisement.token.substring(0, 8)}••••••••',
                      style: AppTypography.labelSmall.copyWith(
                        fontFamily: 'monospace',
                        color: AppColors.textSecondary,
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

  Color _signalColor(SignalStrength signal) {
    switch (signal) {
      case SignalStrength.excellent:
      case SignalStrength.good:
        return AppColors.success;
      case SignalStrength.fair:
        return AppColors.warning;
      case SignalStrength.weak:
        return AppColors.error;
    }
  }
}

// ── Signal Bars Widget ───────────────────────────────────────────────────────

class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.bars, required this.color});

  final int bars;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(4, (i) {
        final active = i < bars;
        final height = 6.0 + (i * 4.0);
        return Padding(
          padding: const EdgeInsets.only(right: 2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 5,
            height: height,
            decoration: BoxDecoration(
              color: active
                  ? color
                  : AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}

// ── BLE Error Card ───────────────────────────────────────────────────────────

class BleErrorCard extends StatelessWidget {
  const BleErrorCard({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _StateCard(
      icon: Icons.error_outline,
      iconColor: AppColors.error,
      iconBgColor: AppColors.errorSurface,
      title: 'Scan Failed',
      subtitle: message,
      action: OutlinedButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh, size: 18),
        label: const Text('Try Again'),
      ),
    );
  }
}

// ── Generic State Card ───────────────────────────────────────────────────────

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: iconBgColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 32),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: AppTypography.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
