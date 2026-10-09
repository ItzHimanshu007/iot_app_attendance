import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../models/reports_models.dart';

// ── Analytics Summary Cards ───────────────────────────────────────────────────

/// Top-level KPI card row for the reports dashboard.
class AnalyticsSummaryRow extends StatelessWidget {
  const AnalyticsSummaryRow({super.key, required this.summary});

  final AttendanceSummary summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _KpiCard(
                label: 'Total Sessions',
                value: summary.totalSessions.toString(),
                icon: Icons.event_note_rounded,
                iconColor: AppColors.primary,
                iconBg: AppColors.primarySurface,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _KpiCard(
                label: 'Students',
                value: summary.totalUniqueStudents.toString(),
                icon: Icons.people_outline_rounded,
                iconColor: AppColors.info,
                iconBg: AppColors.infoSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _KpiCard(
                label: 'Avg Attendance',
                value: summary.averageRatePercent,
                icon: Icons.bar_chart_rounded,
                iconColor: AppColors.success,
                iconBg: AppColors.successSurface,
                highlight: summary.averageAttendanceRate >= 0.75,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _KpiCard(
                label: 'Below 75%',
                value: summary.studentsBelow75.toString(),
                icon: Icons.warning_amber_rounded,
                iconColor: AppColors.warning,
                iconBg: AppColors.warningSurface,
                isAlert: summary.studentsBelow75 > 0,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    this.highlight = false,
    this.isAlert = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final bool highlight;
  final bool isAlert;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: AppTypography.labelSmall
                          .copyWith(color: AppColors.textTertiary)),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: AppTypography.titleMedium.copyWith(
                      color: isAlert
                          ? AppColors.warning
                          : highlight
                              ? AppColors.success
                              : AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
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

// ── Chart Section Card ────────────────────────────────────────────────────────

/// Generic chart card wrapper with title and optional subtitle.
class ChartCard extends StatelessWidget {
  const ChartCard({
    super.key,
    required this.title,
    required this.chart,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
  });

  final String title;
  final Widget chart;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTypography.titleMedium),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!,
                            style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textSecondary)),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 16),
            chart,
          ],
        ),
      ),
    );
  }
}

// ── Subject Analytics Tile ────────────────────────────────────────────────────

/// List tile for a subject's attendance summary.
class SubjectAnalyticsTile extends StatelessWidget {
  const SubjectAnalyticsTile({
    super.key,
    required this.analytics,
    this.onTap,
  });

  final SubjectAnalytics analytics;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final rate = analytics.attendanceRate;
    final color = rate >= 0.75
        ? AppColors.success
        : rate >= 0.50
            ? AppColors.warning
            : AppColors.error;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(analytics.subject.code,
                            style: AppTypography.titleSmall),
                        Text(analytics.subject.name,
                            style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      analytics.attendanceRatePercent,
                      style: AppTypography.labelMedium
                          .copyWith(color: color, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Attendance rate bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: rate,
                  backgroundColor:
                      AppColors.surfaceVariant,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 8),

              // Stats row
              Row(
                children: [
                  _StatChip(
                      label: 'Sessions',
                      value: analytics.totalSessions.toString()),
                  const SizedBox(width: 12),
                  _StatChip(
                      label: 'Avg',
                      value: analytics.averageAttendance
                          .toStringAsFixed(1)),
                  const SizedBox(width: 12),
                  _StatChip(
                      label: 'High',
                      value: analytics.highestAttendance.toString()),
                  const SizedBox(width: 12),
                  _StatChip(
                      label: 'Low',
                      value: analytics.lowestAttendance.toString()),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppTypography.labelSmall
                .copyWith(color: AppColors.textTertiary)),
        Text(value, style: AppTypography.titleSmall),
      ],
    );
  }
}

// ── Student Analytics Tile ────────────────────────────────────────────────────

/// Student attendance row — coloured by threshold.
class StudentAnalyticsTile extends StatelessWidget {
  const StudentAnalyticsTile({
    super.key,
    required this.analytics,
    required this.rank,
  });

  final StudentAnalytics analytics;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final threshold = analytics.threshold;
    final (color, bg, icon) = switch (threshold) {
      AttendanceThreshold.good => (AppColors.success, AppColors.successSurface,
          Icons.check_circle_outline),
      AttendanceThreshold.warning =>
        (AppColors.warning, AppColors.warningSurface, Icons.warning_outlined),
      AttendanceThreshold.critical =>
        (AppColors.error, AppColors.errorSurface, Icons.error_outline),
    };

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Rank
            SizedBox(
              width: 28,
              child: Text(
                '#$rank',
                style: AppTypography.labelSmall
                    .copyWith(color: AppColors.textTertiary),
              ),
            ),
            // Threshold icon
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 10),
            // Student info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(analytics.displayName, style: AppTypography.bodyMedium),
                  Text(
                    '${analytics.sessionsAttended}/${analytics.totalSessions} sessions',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            // Rate badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  analytics.attendancePercent,
                  style: AppTypography.titleSmall.copyWith(color: color),
                ),
                if (threshold != AttendanceThreshold.good)
                  Text(
                    threshold == AttendanceThreshold.critical
                        ? 'CRITICAL'
                        : 'LOW',
                    style: AppTypography.labelSmall.copyWith(
                      color: color,
                      letterSpacing: 0.5,
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

// ── Session Analytics Tile ────────────────────────────────────────────────────

class SessionAnalyticsTile extends StatelessWidget {
  const SessionAnalyticsTile({
    super.key,
    required this.analytics,
  });

  final SessionAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Date block
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Text(
                    analytics.session.startedAt.day.toString(),
                    style: AppTypography.titleMedium
                        .copyWith(color: AppColors.primary),
                  ),
                  Text(
                    _monthAbbr(analytics.session.startedAt.month),
                    style: AppTypography.labelSmall
                        .copyWith(color: AppColors.primary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${analytics.subjectCode} — ${analytics.classroomName}',
                    style: AppTypography.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    analytics.dateLabel,
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  analytics.attendanceCount.toString(),
                  style: AppTypography.titleMedium,
                ),
                Text(
                  'present',
                  style: AppTypography.labelSmall
                      .copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _monthAbbr(int m) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[m - 1];
  }
}

// ── Low Attendance Alert List ─────────────────────────────────────────────────

/// Prominent alert card for students below threshold.
class LowAttendanceAlertCard extends StatelessWidget {
  const LowAttendanceAlertCard({
    super.key,
    required this.students,
    this.threshold = 0.75,
    this.onSeeAll,
  });

  final List<StudentAnalytics> students;
  final double threshold;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    if (students.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.successSurface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.check_circle_rounded,
                    color: AppColors.success, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('All students on track',
                        style: AppTypography.titleSmall),
                    Text(
                      'No students below ${(threshold * 100).toInt()}% attendance',
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Column(
        children: [
          // Alert header
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.warningSurface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppColors.warning, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${students.length} student${students.length == 1 ? '' : 's'} below ${(threshold * 100).toInt()}%',
                    style: AppTypography.labelMedium
                        .copyWith(color: AppColors.warning),
                  ),
                ),
                if (onSeeAll != null)
                  GestureDetector(
                    onTap: onSeeAll,
                    child: Text(
                      'See all',
                      style: AppTypography.labelSmall
                          .copyWith(color: AppColors.warning),
                    ),
                  ),
              ],
            ),
          ),

          // First 3 students
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: students
                  .take(3)
                  .toList()
                  .asMap()
                  .entries
                  .map((e) => StudentAnalyticsTile(
                        analytics: e.value,
                        rank: e.key + 1,
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Distribution Legend ───────────────────────────────────────────────────────

/// Legend row for the donut chart.
class DistributionLegend extends StatelessWidget {
  const DistributionLegend({super.key, required this.students});

  final List<StudentAnalytics> students;

  @override
  Widget build(BuildContext context) {
    final good = students
        .where((s) => s.threshold == AttendanceThreshold.good)
        .length;
    final warning = students
        .where((s) => s.threshold == AttendanceThreshold.warning)
        .length;
    final critical = students
        .where((s) => s.threshold == AttendanceThreshold.critical)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LegendRow(
            color: AppColors.success, label: '≥75% (Good)', count: good),
        const SizedBox(height: 6),
        _LegendRow(
            color: AppColors.warning,
            label: '50–75% (Low)',
            count: warning),
        const SizedBox(height: 6),
        _LegendRow(
            color: AppColors.error,
            label: '<50% (Critical)',
            count: critical),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow(
      {required this.color, required this.label, required this.count});

  final Color color;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, style: AppTypography.bodySmall),
        ),
        Text(
          count.toString(),
          style: AppTypography.titleSmall,
        ),
      ],
    );
  }
}

// ── Reports Empty State ───────────────────────────────────────────────────────

class ReportsEmptyState extends StatelessWidget {
  const ReportsEmptyState({super.key, required this.onStartSession});

  final VoidCallback onStartSession;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.analytics_outlined,
                  size: 48, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            Text('No Reports Yet',
                style: AppTypography.headlineSmall,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Reports will appear after you conduct your first attendance session.',
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onStartSession,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Start First Session'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Reports Error State ───────────────────────────────────────────────────────

class ReportsErrorState extends StatelessWidget {
  const ReportsErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text('Failed to Load Reports',
                style: AppTypography.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              message,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
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
