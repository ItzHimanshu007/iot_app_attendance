import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../controllers/attendance_controller.dart';
import '../models/attendance_models.dart';
import '../widgets/attendance_widgets.dart';

/// Student attendance history screen.
///
/// Shows all of the current student's attendance records from
/// GET /attendance/me, with pull-to-refresh and local analytics.
class AttendanceHistoryScreen extends ConsumerStatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  ConsumerState<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState
    extends ConsumerState<AttendanceHistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(attendanceHistoryProvider.notifier).loadHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final historyState = ref.watch(attendanceHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance History'),
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(attendanceHistoryProvider.notifier).refresh(),
        child: switch (historyState) {
          AttendanceHistoryInitial() || AttendanceHistoryLoading() =>
            const Center(child: CircularProgressIndicator()),

          AttendanceHistoryError(message: final msg) =>
            _buildErrorState(msg),

          AttendanceHistoryLoaded(
            records: final records,
            analytics: final analytics
          ) =>
            _buildLoaded(context, records, analytics),
        },
      ),
    );
  }

  Widget _buildLoaded(
    BuildContext context,
    List<AttendanceRecord> records,
    AttendanceAnalytics analytics,
  ) {
    return CustomScrollView(
      slivers: [
        // ── Analytics summary card ────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _AnalyticsSummaryCard(analytics: analytics),
          ),
        ),

        // ── Section header ────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('All Records', style: AppTypography.headlineSmall),
                Text(
                  '${records.length} total',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),

        // ── Records list ──────────────────────────────────────────────────
        if (records.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: const EmptyState(
                icon: Icons.event_note_outlined,
                title: 'No records yet',
                subtitle:
                    'Your attendance will appear here after you mark it.',
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => AttendanceHistoryTile(record: records[i]),
                childCount: records.length,
              ),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  Widget _buildErrorState(String message) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: 120),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 16),
              Text('Failed to load history',
                  style: AppTypography.titleMedium,
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(message,
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () =>
                    ref.read(attendanceHistoryProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Analytics Summary Card ────────────────────────────────────────────────────

class _AnalyticsSummaryCard extends StatelessWidget {
  const _AnalyticsSummaryCard({required this.analytics});
  final AttendanceAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final rate = analytics.successRate;
    final ratePercent = (rate * 100).toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Attendance',
            style: AppTypography.titleMedium
                .copyWith(color: Colors.white.withValues(alpha: 0.9)),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _StatChip(
                value: analytics.totalSubmissions.toString(),
                label: 'Total',
                color: Colors.white,
              ),
              const SizedBox(width: 20),
              _StatChip(
                value: analytics.successfulSubmissions.toString(),
                label: 'Present',
                color: Colors.white,
              ),
              const SizedBox(width: 20),
              _StatChip(
                value: '$ratePercent%',
                label: 'Rate',
                color: Colors.white,
              ),
            ],
          ),
          if (analytics.lastAttendanceTime != null) ...[
            const SizedBox(height: 12),
            Text(
              'Last recorded: ${_formatRelative(analytics.lastAttendanceTime!)}',
              style: AppTypography.labelSmall
                  .copyWith(color: Colors.white.withValues(alpha: 0.7)),
            ),
          ],
          if (analytics.lastClassroom != null) ...[
            const SizedBox(height: 4),
            Text(
              'Room: ${analytics.lastClassroom}',
              style: AppTypography.labelSmall
                  .copyWith(color: Colors.white.withValues(alpha: 0.7)),
            ),
          ],
          const SizedBox(height: 16),
          // Success rate progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: rate,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(
                rate >= 0.75
                    ? Colors.greenAccent
                    : rate >= 0.5
                        ? Colors.yellowAccent
                        : Colors.redAccent,
              ),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  String _formatRelative(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: AppTypography.displaySmall.copyWith(color: color),
        ),
        Text(
          label,
          style: AppTypography.labelSmall
              .copyWith(color: color.withValues(alpha: 0.7)),
        ),
      ],
    );
  }
}
