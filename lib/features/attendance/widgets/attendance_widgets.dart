import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../models/attendance_models.dart';

// ── Attendance Ready Card ─────────────────────────────────────────────────────

/// Shown when a valid in-range beacon is found — ready to submit.
class AttendanceReadyCard extends StatelessWidget {
  const AttendanceReadyCard({
    super.key,
    required this.classroomId,
    required this.rssi,
    required this.onSubmit,
    this.isLoading = false,
  });

  final String classroomId;
  final int rssi;
  final VoidCallback onSubmit;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Session header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.wifi_tethering_rounded,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Session Found',
                          style: AppTypography.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        'Room: $classroomId',
                        style: AppTypography.bodyMedium
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                // RSSI badge
                _RssiBadge(rssi: rssi),
              ],
            ),

            const SizedBox(height: 20),

            // Steps preview
            _PipelineStepsPreview(),

            const SizedBox(height: 20),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isLoading ? null : onSubmit,
                icon: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.fingerprint, size: 22),
                label: Text(isLoading
                    ? 'Verifying…'
                    : 'Mark Attendance'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),

            const SizedBox(height: 8),
            Text(
              'Biometric verification required',
              style: AppTypography.labelSmall
                  .copyWith(color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Attendance Submitting Card ────────────────────────────────────────────────

/// Animated progress card shown during submission pipeline.
class AttendanceSubmittingCard extends StatefulWidget {
  const AttendanceSubmittingCard({
    super.key,
    required this.step,
    required this.classroomId,
  });

  final AttendancePipelineStep step;
  final String classroomId;

  @override
  State<AttendanceSubmittingCard> createState() =>
      _AttendanceSubmittingCardState();
}

class _AttendanceSubmittingCardState extends State<AttendanceSubmittingCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final steps = AttendancePipelineStep.values
        .where((s) =>
            s != AttendancePipelineStep.idle &&
            s != AttendancePipelineStep.complete &&
            s != AttendancePipelineStep.failed)
        .toList();
    final currentIndex = steps.indexOf(widget.step);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            ScaleTransition(
              scale: _scale,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 20,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(Icons.security_rounded,
                    color: Colors.white, size: 36),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.step.label,
              style: AppTypography.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Room ${widget.classroomId}',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),

            // Step progress dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(steps.length, (i) {
                final done = i < currentIndex;
                final active = i == currentIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: active ? 24 : 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: done
                        ? AppColors.success
                        : active
                            ? AppColors.primary
                            : AppColors.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),

            const SizedBox(height: 16),

            // Progress indicator
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: steps.isEmpty
                    ? 0
                    : (currentIndex + 1) / steps.length,
                backgroundColor: AppColors.primarySurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Attendance Success Card ───────────────────────────────────────────────────

/// Shown after successful attendance submission.
class AttendanceSuccessCard extends StatefulWidget {
  const AttendanceSuccessCard({
    super.key,
    required this.record,
    required this.classroomId,
    required this.onDone,
  });

  final AttendanceRecord record;
  final String classroomId;
  final VoidCallback onDone;

  @override
  State<AttendanceSuccessCard> createState() => _AttendanceSuccessCardState();
}

class _AttendanceSuccessCardState extends State<AttendanceSuccessCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _scale =
        CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final isLate = record.status == AppConstants.statusLate;

    return FadeTransition(
      opacity: _fade,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // Animated checkmark
              ScaleTransition(
                scale: _scale,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: isLate
                        ? const LinearGradient(colors: [
                            Color(0xFFD97706),
                            Color(0xFFF59E0B),
                          ])
                        : AppColors.successGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (isLate ? AppColors.warning : AppColors.success)
                            .withValues(alpha: 0.35),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Icon(
                    isLate ? Icons.access_time_rounded : Icons.check_rounded,
                    color: Colors.white,
                    size: 44,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              Text(
                isLate ? 'Marked Late' : 'Attendance Recorded!',
                style: AppTypography.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                isLate
                    ? 'You were marked late for this session.'
                    : 'You have been marked present.',
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),

              // Detail rows
              _DetailRow(
                icon: Icons.location_on_outlined,
                label: 'Classroom',
                value: widget.classroomId,
              ),
              const SizedBox(height: 10),
              _DetailRow(
                icon: Icons.schedule_outlined,
                label: 'Recorded At',
                value: _formatTime(record.markedAt),
              ),
              const SizedBox(height: 10),
              _DetailRow(
                icon: Icons.fingerprint,
                label: 'Verification',
                value: record.biometricVerified
                    ? 'Biometric + BLE'
                    : 'BLE Only',
              ),
              const SizedBox(height: 10),

              // Confirmation ID
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.receipt_outlined,
                        size: 14, color: AppColors.textTertiary),
                    const SizedBox(width: 8),
                    Text(
                      'ID: ${record.id.substring(0, 8).toUpperCase()}',
                      style: AppTypography.labelSmall.copyWith(
                        fontFamily: 'monospace',
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: record.id));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('ID copied to clipboard')),
                        );
                      },
                      child: const Icon(Icons.copy_outlined,
                          size: 14, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: widget.onDone,
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month}/${dt.year} $h:$m:$s';
  }
}

// ── Attendance Failure Card ───────────────────────────────────────────────────

class AttendanceFailureCard extends StatelessWidget {
  const AttendanceFailureCard({
    super.key,
    required this.reason,
    required this.step,
    required this.isRetryable,
    this.onRetry,
    this.onDismiss,
  });

  final String reason;
  final AttendancePipelineStep step;
  final bool isRetryable;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

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
              child:
                  const Icon(Icons.cancel_outlined, color: AppColors.error, size: 42),
            ),
            const SizedBox(height: 16),
            Text('Attendance Failed',
                style: AppTypography.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              reason,
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            // Failed step indicator
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.errorSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Text(
                'Failed at: ${step.label}',
                style: AppTypography.labelSmall
                    .copyWith(color: AppColors.error),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (onDismiss != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onDismiss,
                      child: const Text('Dismiss'),
                    ),
                  ),
                if (onDismiss != null && isRetryable)
                  const SizedBox(width: 12),
                if (isRetryable && onRetry != null)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Try Again'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Attendance History Tile ───────────────────────────────────────────────────

class AttendanceHistoryTile extends StatelessWidget {
  const AttendanceHistoryTile({super.key, required this.record});
  final AttendanceRecord record;

  @override
  Widget build(BuildContext context) {
    final (color, bgColor, icon) = _statusStyle(record.status);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Session ${record.sessionId.substring(0, 8).toUpperCase()}',
                    style: AppTypography.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatDate(record.markedAt),
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  if (record.rejectionReason != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      record.rejectionReason!,
                      style: AppTypography.labelSmall
                          .copyWith(color: AppColors.error),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    record.statusLabel,
                    style: AppTypography.labelSmall.copyWith(color: color),
                  ),
                ),
                if (record.biometricVerified) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.fingerprint,
                          size: 12, color: AppColors.textTertiary),
                      const SizedBox(width: 2),
                      Text(
                        'Biometric',
                        style: AppTypography.labelSmall
                            .copyWith(color: AppColors.textTertiary),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  (Color, Color, IconData) _statusStyle(String status) {
    switch (status) {
      case AppConstants.statusPresent:
        return (AppColors.success, AppColors.successSurface,
            Icons.check_circle_outline);
      case AppConstants.statusLate:
        return (AppColors.warning, AppColors.warningSurface,
            Icons.access_time_outlined);
      case AppConstants.statusRevoked:
        return (AppColors.error, AppColors.errorSurface,
            Icons.cancel_outlined);
      default:
        return (AppColors.textSecondary, AppColors.surfaceVariant,
            Icons.radio_button_unchecked_outlined);
    }
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, $h:$m';
  }
}

// ── Helper sub-widgets ────────────────────────────────────────────────────────

class _RssiBadge extends StatelessWidget {
  const _RssiBadge({required this.rssi});
  final int rssi;

  @override
  Widget build(BuildContext context) {
    final color = rssi >= -60 ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$rssi dBm',
        style: AppTypography.labelSmall.copyWith(color: color),
      ),
    );
  }
}

class _PipelineStepsPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const steps = [
      (Icons.wifi_tethering_rounded, 'Session'),
      (Icons.phone_android_outlined, 'Device'),
      (Icons.fingerprint, 'Biometric'),
      (Icons.cloud_upload_outlined, 'Submit'),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: steps.map((s) {
        return Expanded(
          child: Column(
            children: [
              Icon(s.$1, size: 20, color: AppColors.primary),
              const SizedBox(height: 4),
              Text(
                s.$2,
                style: AppTypography.labelSmall
                    .copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textTertiary),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: AppTypography.bodySmall
              .copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: AppTypography.bodySmall,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
