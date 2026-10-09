import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../controllers/session_monitor_controller.dart';
import '../controllers/teacher_session_controller.dart';
import '../models/teacher_models.dart';
import '../widgets/teacher_widgets.dart';

/// Full-screen active session monitor.
///
/// Shown when teacher has an ongoing session:
///   - Live attendance counter (10 s auto-refresh)
///   - Attendance list with student names, timestamps, RSSI
///   - Token rotation button
///   - End session button
///   - Manual refresh button
class ActiveSessionScreen extends ConsumerStatefulWidget {
  const ActiveSessionScreen({super.key});

  @override
  ConsumerState<ActiveSessionScreen> createState() =>
      _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends ConsumerState<ActiveSessionScreen> {
  DateTime _lastUpdated = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startMonitoring();
    });
  }

  void _startMonitoring() {
    final sessionState = ref.read(teacherSessionControllerProvider);
    if (sessionState is TeacherSessionActive) {
      final sessionId = sessionState.session.id;
      final monitor = ref.read(sessionMonitorControllerProvider.notifier);
      monitor.loadAttendance(sessionId);
      monitor.startPolling(sessionId);
    }
  }

  @override
  void dispose() {
    ref.read(sessionMonitorControllerProvider.notifier).stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessionState = ref.watch(teacherSessionControllerProvider);
    final monitorState = ref.watch(sessionMonitorControllerProvider);

    // Track last-updated timestamp when live status refreshes.
    ref.listen(teacherSessionControllerProvider, (prev, next) {
      if (next is TeacherSessionActive) {
        final prevStatus = prev is TeacherSessionActive ? prev.liveStatus : null;
        if (next.liveStatus != prevStatus) {
          setState(() => _lastUpdated = DateTime.now());
        }
      }
    });

    // Re-start monitoring if session becomes active after init
    ref.listen(teacherSessionControllerProvider, (prev, next) {
      if (next is TeacherSessionActive &&
          prev is! TeacherSessionActive) {
        final monitor = ref.read(sessionMonitorControllerProvider.notifier);
        monitor.loadAttendance(next.session.id);
        monitor.startPolling(next.session.id);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Session'),
        automaticallyImplyLeading: false,
        actions: [
          // Manual refresh — refreshes both status and attendance list
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () {
              ref
                  .read(teacherSessionControllerProvider.notifier)
                  .refreshStatus();
              ref.read(sessionMonitorControllerProvider.notifier).refresh();
            },
          ),
        ],
      ),
      body: switch (sessionState) {
        TeacherSessionActive(
          session: final session,
          liveStatus: final status,
          lastRotatedAt: final rotated,
          lastRotationPreview: final preview,
        ) =>
          RefreshIndicator(
            onRefresh: () async {
              ref
                  .read(teacherSessionControllerProvider.notifier)
                  .refreshStatus();
              await ref
                  .read(sessionMonitorControllerProvider.notifier)
                  .refresh();
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // ── Live attendance counter ─────────────────────────
                      AttendanceCounterCard(
                        count: _attendanceCount(status, session, monitorState),
                        lastUpdated: _lastUpdated,
                        onRefresh: () {
                          ref
                              .read(teacherSessionControllerProvider.notifier)
                              .refreshStatus();
                          ref
                              .read(sessionMonitorControllerProvider.notifier)
                              .refresh();
                        },
                      ),
                      const SizedBox(height: 12),

                      // ── Session details + controls ──────────────────────
                      ActiveSessionCard(
                        session: session,
                        liveStatus: status,
                        lastRotatedAt: rotated,
                        lastRotationPreview: preview,
                        onRotateToken: () => _onRotateToken(context),
                        onEndSession: () => _onEndSession(context),
                      ),
                      const SizedBox(height: 20),

                      // ── Attendance list ─────────────────────────────────
                      _AttendanceListSection(
                        monitorState: monitorState,
                        lastUpdated: _lastUpdated,
                      ),

                      const SizedBox(height: 32),
                    ]),
                  ),
                ),
              ],
            ),
          ),

        TeacherSessionRotating(session: final session) =>
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                AttendanceCounterCard(
                  count: session.totalPresent,
                  lastUpdated: _lastUpdated,
                ),
                const SizedBox(height: 12),
                ActiveSessionCard(
                  session: session,
                  liveStatus: null,
                  onRotateToken: () {},
                  onEndSession: () {},
                  isRotating: true,
                ),
              ],
            ),
          ),

        TeacherSessionEnding() =>
          const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Ending session…'),
              ],
            ),
          ),

        TeacherSessionEnded(result: final result) =>
          _SessionEndedView(result: result),

        TeacherSessionExpired(session: final session) =>
          Padding(
            padding: const EdgeInsets.all(16),
            child: SessionExpiredCard(
              session: session,
              onDismiss: () =>
                  ref.read(teacherSessionControllerProvider.notifier).reset(),
              onStartNew: () =>
                  ref.read(teacherSessionControllerProvider.notifier).reset(),
            ),
          ),

        TeacherSessionError(
          message: final msg,
          isRetryable: final retryable,
          session: final session,
        ) =>
          Padding(
            padding: const EdgeInsets.all(16),
            child: SessionErrorCard(
              message: msg,
              isRetryable: retryable,
              onDismiss: () =>
                  ref.read(teacherSessionControllerProvider.notifier).reset(),
              onRetry: retryable && session != null
                  ? () => ref
                      .read(teacherSessionControllerProvider.notifier)
                      .resumeSession(session.id)
                  : null,
            ),
          ),

        _ => const SizedBox.shrink(),
      },
    );
  }

  int _attendanceCount(
    SessionStatus? status,
    AttendanceSession session,
    SessionMonitorState monitorState,
  ) {
    if (monitorState is SessionMonitorLoaded) {
      return monitorState.presentCount;
    }
    return status?.totalPresent ?? session.totalPresent;
  }

  Future<void> _onRotateToken(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rotate Session Token?'),
        content: const Text(
          'This updates the token students must match. '
          'Students scanning at this moment may need to retry.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rotate'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(teacherSessionControllerProvider.notifier).rotateToken();
    }
  }

  Future<void> _onEndSession(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.stop_circle_outlined,
            color: AppColors.error, size: 36),
        title: const Text('End Session?'),
        content: const Text(
          'This will close attendance. '
          'Students will no longer be able to mark themselves present.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('End Session'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      ref.read(sessionMonitorControllerProvider.notifier).stopPolling();
      await ref
          .read(teacherSessionControllerProvider.notifier)
          .endSession();
    }
  }
}

// ── Attendance List Section ────────────────────────────────────────────────────

class _AttendanceListSection extends StatelessWidget {
  const _AttendanceListSection({
    required this.monitorState,
    required this.lastUpdated,
  });

  final SessionMonitorState monitorState;
  final DateTime lastUpdated;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ─────────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Attendance List', style: AppTypography.headlineSmall),
            _LastRefreshedLabel(lastUpdated: lastUpdated),
          ],
        ),
        const SizedBox(height: 8),

        // ── Content ────────────────────────────────────────────────────────
        switch (monitorState) {
          SessionMonitorInitial() || SessionMonitorLoading() =>
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),

          SessionMonitorError(message: final msg) =>
            _MonitorErrorCard(message: msg),

          SessionMonitorLoaded(entries: final entries) =>
            entries.isEmpty
                ? _EmptyAttendanceCard()
                : _AttendanceEntryList(entries: entries),
        },
      ],
    );
  }
}

class _LastRefreshedLabel extends StatelessWidget {
  const _LastRefreshedLabel({required this.lastUpdated});
  final DateTime lastUpdated;

  String _format(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt).inSeconds;
    if (diff < 5) return 'just now';
    if (diff < 60) return '${diff}s ago';
    return '${diff ~/ 60}m ago';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.sync_rounded, size: 12, color: AppColors.textTertiary),
        const SizedBox(width: 4),
        Text(
          _format(lastUpdated),
          style: AppTypography.labelSmall
              .copyWith(color: AppColors.textTertiary),
        ),
      ],
    );
  }
}

class _EmptyAttendanceCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(Icons.people_outline_rounded,
              size: 40, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          Text('No students yet', style: AppTypography.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Students will appear here as they mark attendance.',
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _MonitorErrorCard extends StatelessWidget {
  const _MonitorErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.errorSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceEntryList extends StatelessWidget {
  const _AttendanceEntryList({required this.entries});
  final List<AttendanceEntry> entries;

  @override
  Widget build(BuildContext context) {
    // Most recent first
    final sorted = [...entries]
      ..sort((a, b) => b.markedAt.compareTo(a.markedAt));

    return Column(
      children: sorted.map((e) => _AttendanceEntryTile(entry: e)).toList(),
    );
  }
}

class _AttendanceEntryTile extends StatelessWidget {
  const _AttendanceEntryTile({required this.entry});
  final AttendanceEntry entry;

  Color get _statusColor => switch (entry.status) {
        'present' => AppColors.success,
        'late' => AppColors.warning,
        'revoked' => AppColors.error,
        _ => AppColors.textSecondary,
      };

  String get _statusLabel => switch (entry.status) {
        'present' => 'Present',
        'late' => 'Late',
        'revoked' => 'Revoked',
        _ => entry.status,
      };

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Status dot
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),

            // Student info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.studentName ?? 'Student ${entry.studentId.substring(0, 8)}',
                    style: AppTypography.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatTime(entry.markedAt.toLocal()),
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),

            // Badges
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _statusLabel,
                    style: AppTypography.labelSmall
                        .copyWith(color: _statusColor),
                  ),
                ),
                if (entry.bleRssi != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    '${entry.bleRssi} dBm',
                    style: AppTypography.labelSmall
                        .copyWith(color: AppColors.textTertiary),
                  ),
                ],
                if (entry.biometricVerified == true) ...[
                  const SizedBox(height: 3),
                  const Icon(Icons.fingerprint_rounded,
                      size: 14, color: AppColors.success),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Session Ended View ────────────────────────────────────────────────────────

class _SessionEndedView extends ConsumerWidget {
  const _SessionEndedView({required this.result});
  final SessionEndResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 48),
            ),
            const SizedBox(height: 24),
            Text(
              'Session Ended',
              style: AppTypography.headlineLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              '${result.totalPresent} student(s) marked present.',
              style: AppTypography.bodyLarge
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Attendance has been recorded.',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textTertiary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => ref
                    .read(teacherSessionControllerProvider.notifier)
                    .reset(),
                child: const Text('Back to Dashboard'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
