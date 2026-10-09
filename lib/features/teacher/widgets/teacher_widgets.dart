import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../models/teacher_models.dart';

// ── Session Creation Card ─────────────────────────────────────────────────────

/// Session creation form card — subject text field + classroom + duration pickers.
class SessionCreationCard extends StatefulWidget {
  const SessionCreationCard({
    super.key,
    required this.classrooms,
    required this.onStart,
    this.isLoading = false,
  });

  final List<Classroom> classrooms;
  final void Function(SessionCreateRequest) onStart;
  final bool isLoading;

  @override
  State<SessionCreationCard> createState() => _SessionCreationCardState();
}

class _SessionCreationCardState extends State<SessionCreationCard> {
  final _subjectController = TextEditingController();
  Classroom? _classroom;
  int _durationMinutes = 5;
  final _notesController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  static const _durations = [3, 5, 10, 15, 20, 30, 45, 60];

  @override
  void dispose() {
    _subjectController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_classroom == null) return;

    widget.onStart(SessionCreateRequest(
      subjectName: _subjectController.text.trim(),
      classroomId: _classroom!.id,
      durationMinutes: _durationMinutes,
      notes: _notesController.text.isEmpty ? null : _notesController.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Start Attendance Session',
                      style: AppTypography.titleMedium,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Subject name text field
              Text('Subject Name', style: AppTypography.labelMedium),
              const SizedBox(height: 6),
              TextFormField(
                controller: _subjectController,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Enter subject name',
                  prefixIcon: Icon(Icons.book_outlined),
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) {
                    return 'Subject name cannot be empty';
                  }
                  if (trimmed.length < 3) {
                    return 'Subject name must be at least 3 characters';
                  }
                  if (trimmed.length > 100) {
                    return 'Subject name must not exceed 100 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Classroom dropdown
              Text('Classroom', style: AppTypography.labelMedium),
              const SizedBox(height: 6),
              // ignore: deprecated_member_use
              DropdownButtonFormField<Classroom>(
                value: _classroom,
                isExpanded: true,
                decoration: const InputDecoration(
                  hintText: 'Select classroom',
                  prefixIcon: Icon(Icons.meeting_room_outlined),
                ),
                items: widget.classrooms
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(
                            c.displayName,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _classroom = v),
                validator: (v) =>
                    v == null ? 'Please select a classroom' : null,
              ),
              const SizedBox(height: 14),

              // Duration selector
              Text('Duration', style: AppTypography.labelMedium),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _durations.map((d) {
                  final selected = d == _durationMinutes;
                  return GestureDetector(
                    onTap: () => setState(() => _durationMinutes = d),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primary
                            : AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected
                              ? AppColors.primary
                              : AppColors.border,
                        ),
                      ),
                      child: Text(
                        '${d}m',
                        style: AppTypography.labelMedium.copyWith(
                          color: selected ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),

              // Notes (optional)
              Text('Notes (optional)', style: AppTypography.labelMedium),
              const SizedBox(height: 6),
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'e.g. Mid-term practical test',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),

              const SizedBox(height: 20),

              // Confirm summary
              if (_subjectController.text.trim().isNotEmpty && _classroom != null)
                _SessionSummaryChip(
                  subjectName: _subjectController.text.trim(),
                  classroom: _classroom!,
                  duration: _durationMinutes,
                ),
              if (_subjectController.text.trim().isNotEmpty && _classroom != null)
                const SizedBox(height: 14),

              // Start button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed:
                      widget.isLoading ? null : _submit,
                  icon: widget.isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.wifi_tethering_rounded, size: 20),
                  label: Text(widget.isLoading
                      ? 'Starting session…'
                      : 'Start Session & Broadcast BLE'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  'This will activate the ESP32 BLE broadcaster',
                  style: AppTypography.labelSmall
                      .copyWith(color: AppColors.textTertiary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionSummaryChip extends StatelessWidget {
  const _SessionSummaryChip({
    required this.subjectName,
    required this.classroom,
    required this.duration,
  });

  final String subjectName;
  final Classroom classroom;
  final int duration;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Session Preview',
              style: AppTypography.labelSmall
                  .copyWith(color: AppColors.primary)),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.book_outlined,
                  size: 14, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(subjectName,
                    style: AppTypography.bodySmall),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.meeting_room_outlined,
                  size: 14, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  classroom.displayName,
                  style: AppTypography.bodySmall,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.timer_outlined,
                  size: 14, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$duration minutes',
                  style: AppTypography.bodySmall,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Active Session Card ───────────────────────────────────────────────────────

/// Main live session card — session details + remaining time + actions.
class ActiveSessionCard extends StatefulWidget {
  const ActiveSessionCard({
    super.key,
    required this.session,
    required this.liveStatus,
    required this.onRotateToken,
    required this.onEndSession,
    this.lastRotatedAt,
    this.lastRotationPreview,
    this.isRotating = false,
  });

  final AttendanceSession session;
  final SessionStatus? liveStatus;
  final VoidCallback onRotateToken;
  final VoidCallback onEndSession;
  final DateTime? lastRotatedAt;
  final String? lastRotationPreview;
  final bool isRotating;

  @override
  State<ActiveSessionCard> createState() => _ActiveSessionCardState();
}

class _ActiveSessionCardState extends State<ActiveSessionCard> {
  Timer? _clockTimer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _remaining = widget.session.remainingTime ?? Duration.zero;
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _remaining = widget.session.remainingTime ?? Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fraction = widget.session.elapsedFraction;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header — live indicator
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Live Session',
                  style: AppTypography.labelMedium
                      .copyWith(color: AppColors.success),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.successSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    widget.session.status.toUpperCase(),
                    style: AppTypography.labelSmall
                        .copyWith(color: AppColors.success),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Session ID
            _InfoRow(
              icon: Icons.tag_outlined,
              label: 'Session ID',
              value: widget.session.id.substring(0, 8).toUpperCase(),
              onTap: () {
                Clipboard.setData(
                    ClipboardData(text: widget.session.id));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Session ID copied')),
                );
              },
            ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.book_outlined,
              label: 'Subject',
              value: widget.session.displaySubjectName,
            ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.meeting_room_outlined,
              label: 'Classroom',
              value: widget.session.classroomId,
            ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.schedule_outlined,
              label: 'Started',
              value: _formatTime(widget.session.startedAt),
            ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // Remaining time countdown
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _CountdownDisplay(remaining: _remaining),
              ],
            ),

            const SizedBox(height: 12),

            // Session progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: fraction,
                backgroundColor: AppColors.primarySurface,
                valueColor: AlwaysStoppedAnimation<Color>(
                  fraction > 0.85 ? AppColors.warning : AppColors.primary,
                ),
                minHeight: 8,
              ),
            ),

            const SizedBox(height: 16),

            // Last rotation info
            if (widget.lastRotatedAt != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.refresh,
                        size: 14, color: AppColors.textTertiary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Token rotated ${_formatRelative(widget.lastRotatedAt!)}',
                        style: AppTypography.labelSmall
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                    if (widget.lastRotationPreview != null)
                      Text(
                        widget.lastRotationPreview!,
                        style: AppTypography.labelSmall.copyWith(
                          fontFamily: 'monospace',
                          color: AppColors.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.isRotating ? null : widget.onRotateToken,
                    icon: widget.isRotating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(widget.isRotating
                        ? 'Rotating…'
                        : 'Rotate Token'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: widget.onEndSession,
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    label: const Text('End Session'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatRelative(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}

// ── Attendance Counter Card ───────────────────────────────────────────────────

/// Live attendance counter with animated number.
class AttendanceCounterCard extends StatelessWidget {
  const AttendanceCounterCard({
    super.key,
    required this.count,
    required this.lastUpdated,
    this.onRefresh,
  });

  final int count;
  final DateTime lastUpdated;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Live Attendance', style: AppTypography.titleMedium),
                if (onRefresh != null)
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    onPressed: onRefresh,
                    tooltip: 'Refresh',
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: count.toDouble()),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              builder: (context, value, _) {
                return Text(
                  value.toInt().toString(),
                  style: AppTypography.displayLarge.copyWith(
                    color: AppColors.primary,
                    fontSize: 56,
                  ),
                );
              },
            ),
            Text(
              'students present',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Text(
              'Updated ${_formatRelative(lastUpdated)}',
              style: AppTypography.labelSmall
                  .copyWith(color: AppColors.textTertiary),
            ),
            const SizedBox(height: 4),
            Text(
              'Refreshes every 15 seconds',
              style: AppTypography.labelSmall
                  .copyWith(color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  String _formatRelative(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 5) return 'just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    return '${diff.inMinutes}m ago';
  }
}

// ── Session History Tile ──────────────────────────────────────────────────────

class SessionHistoryTile extends StatelessWidget {
  const SessionHistoryTile({
    super.key,
    required this.session,
    this.onTap,
  });

  final AttendanceSession session;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (color, bg, icon) = _statusStyle(session.status);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: bg,
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
                      session.displaySubjectName,
                      style: AppTypography.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatDate(session.startedAt)} · ${session.durationMinutes}m',
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                    ),
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
                      color: bg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      session.status.toUpperCase(),
                      style:
                          AppTypography.labelSmall.copyWith(color: color),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${session.totalPresent} present',
                    style: AppTypography.labelSmall
                        .copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  (Color, Color, IconData) _statusStyle(String status) {
    switch (status) {
      case 'active':
        return (AppColors.success, AppColors.successSurface,
            Icons.wifi_tethering_rounded);
      case 'completed':
        return (AppColors.primary, AppColors.primarySurface,
            Icons.check_circle_outline);
      case 'cancelled':
        return (AppColors.error, AppColors.errorSurface,
            Icons.cancel_outlined);
      default:
        return (AppColors.textSecondary, AppColors.surfaceVariant,
            Icons.event_outlined);
    }
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]}, $h:$m';
  }
}

// ── Session Expired Card ──────────────────────────────────────────────────────

class SessionExpiredCard extends StatelessWidget {
  const SessionExpiredCard({
    super.key,
    required this.session,
    required this.onDismiss,
    required this.onStartNew,
  });

  final AttendanceSession session;
  final VoidCallback onDismiss;
  final VoidCallback onStartNew;

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
                color: AppColors.warningSurface,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.hourglass_empty_rounded,
                  color: AppColors.warning, size: 42),
            ),
            const SizedBox(height: 16),
            Text('Session Expired',
                style: AppTypography.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'The session duration has ended. ${session.totalPresent} student(s) were marked present.',
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onDismiss,
                    child: const Text('Dismiss'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onStartNew,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('New Session'),
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

// ── Session Error Card ────────────────────────────────────────────────────────

class SessionErrorCard extends StatelessWidget {
  const SessionErrorCard({
    super.key,
    required this.message,
    required this.isRetryable,
    this.onRetry,
    this.onDismiss,
  });

  final String message;
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
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: AppColors.errorSurface,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline,
                  color: AppColors.error, size: 38),
            ),
            const SizedBox(height: 14),
            Text('Session Error',
                style: AppTypography.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              message,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
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
                      label: const Text('Retry'),
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

// ── Helper Sub-widgets ────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
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
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.copy_outlined,
                size: 12, color: AppColors.textTertiary),
          ],
        ],
      ),
    );
  }
}

class _CountdownDisplay extends StatelessWidget {
  const _CountdownDisplay({required this.remaining});
  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final h = remaining.inHours;
    final m = (remaining.inMinutes % 60).toString().padLeft(2, '0');
    final s = (remaining.inSeconds % 60).toString().padLeft(2, '0');

    final timeStr = h > 0 ? '$h:$m:$s' : '$m:$s';
    final isLow = remaining.inMinutes <= 5;

    return Column(
      children: [
        Text(
          timeStr,
          style: AppTypography.displaySmall.copyWith(
            color: isLow ? AppColors.error : AppColors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          'remaining',
          style: AppTypography.labelSmall
              .copyWith(color: AppColors.textTertiary),
        ),
      ],
    );
  }
}
