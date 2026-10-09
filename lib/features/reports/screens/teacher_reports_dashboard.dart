import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../routes/app_router.dart';
import '../controllers/teacher_reports_controller.dart';
import '../widgets/analytics_widgets.dart';
import '../widgets/charts.dart';

/// Teacher Reports Dashboard — the top-level analytics entry point.
///
/// Tabs:
///   Overview   — KPI cards + trend chart + distribution donut
///   Subjects   — per-subject analytics list + bar chart
///   Students   — per-student list + low-attendance alerts
///   Sessions   — chronological session list
class TeacherReportsDashboard extends ConsumerStatefulWidget {
  const TeacherReportsDashboard({super.key});

  @override
  ConsumerState<TeacherReportsDashboard> createState() =>
      _TeacherReportsDashboardState();
}

class _TeacherReportsDashboardState
    extends ConsumerState<TeacherReportsDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(teacherReportsControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports & Analytics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () => ref
                .read(teacherReportsControllerProvider.notifier)
                .refresh(),
          ),
        ],
        bottom: switch (state) {
          ReportsLoaded() || ReportsEmpty() => TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'Subjects'),
                Tab(text: 'Students'),
                Tab(text: 'Sessions'),
              ],
            ),
          _ => null,
        },
      ),
      body: switch (state) {
        ReportsLoading() => const Center(child: CircularProgressIndicator()),

        ReportsEmpty() => ReportsEmptyState(
            onStartSession: () => context.push(RoutePaths.sessionCreation),
          ),

        ReportsError(message: final msg) => ReportsErrorState(
            message: msg,
            onRetry: () => ref
                .read(teacherReportsControllerProvider.notifier)
                .refresh(),
          ),

        ReportsLoaded(
          summary: final summary,
          subjects: final subjects,
          students: final students,
          sessions: final sessions,
          trend: final trend,
          lowAttendanceStudents: final lowStudents,
        ) =>
          RefreshIndicator(
            onRefresh: () => ref
                .read(teacherReportsControllerProvider.notifier)
                .refresh(),
            child: TabBarView(
              controller: _tabController,
              children: [
                // ── Overview Tab ─────────────────────────────────────────
                _OverviewTab(
                  summary: summary,
                  trend: trend,
                  students: students,
                  lowStudents: lowStudents,
                  onSeeAllStudents: () => _tabController.animateTo(2),
                ),

                // ── Subjects Tab ─────────────────────────────────────────
                _SubjectsTab(subjects: subjects),

                // ── Students Tab ─────────────────────────────────────────
                _StudentsTab(students: students),

                // ── Sessions Tab ─────────────────────────────────────────
                _SessionsTab(sessions: sessions),
              ],
            ),
          ),
      },
    );
  }
}

// ── Overview Tab ──────────────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.summary,
    required this.trend,
    required this.students,
    required this.lowStudents,
    required this.onSeeAllStudents,
  });

  final dynamic summary;
  final dynamic trend;
  final List students;
  final List lowStudents;
  final VoidCallback onSeeAllStudents;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // KPI cards
        AnalyticsSummaryRow(summary: summary),
        const SizedBox(height: 16),

        // Attendance trend line chart
        ChartCard(
          title: 'Attendance Trend',
          subtitle: 'Students present per session',
          chart: AttendanceTrendChart(trend: trend),
        ),
        const SizedBox(height: 12),

        // Distribution donut + legend
        ChartCard(
          title: 'Attendance Distribution',
          subtitle: 'Students by attendance level',
          chart: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AttendanceDistributionChart(
                students: students.cast(),
                size: 160,
              ),
              const SizedBox(width: 20),
              Expanded(
                child: DistributionLegend(students: students.cast()),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Low attendance alert
        Text('Attendance Alerts', style: AppTypography.headlineSmall),
        const SizedBox(height: 8),
        LowAttendanceAlertCard(
          students: lowStudents.cast(),
          onSeeAll: onSeeAllStudents,
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

// ── Subjects Tab ──────────────────────────────────────────────────────────────

class _SubjectsTab extends StatelessWidget {
  const _SubjectsTab({required this.subjects});

  final List subjects;

  @override
  Widget build(BuildContext context) {
    if (subjects.isEmpty) {
      return const Center(child: Text('No subject data available'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Subject comparison bar chart
        ChartCard(
          title: 'Subject Comparison',
          subtitle: 'Attendance rate by subject',
          chart: SubjectComparisonChart(subjects: subjects.cast()),
        ),
        const SizedBox(height: 12),

        Text('Subject Details', style: AppTypography.headlineSmall),
        const SizedBox(height: 8),

        ...subjects.map((s) => SubjectAnalyticsTile(analytics: s)),
        const SizedBox(height: 32),
      ],
    );
  }
}

// ── Students Tab ──────────────────────────────────────────────────────────────

class _StudentsTab extends ConsumerStatefulWidget {
  const _StudentsTab({required this.students});

  final List students;

  @override
  ConsumerState<_StudentsTab> createState() => _StudentsTabState();
}

class _StudentsTabState extends ConsumerState<_StudentsTab> {
  String _filter = 'all'; // all | low | critical

  @override
  Widget build(BuildContext context) {
    final filtered = switch (_filter) {
      'low' => widget.students
          .cast<dynamic>()
          .where((s) => s.isBelowThreshold75)
          .toList(),
      'critical' => widget.students
          .cast<dynamic>()
          .where((s) => s.isBelowThreshold50)
          .toList(),
      _ => widget.students,
    };

    return Column(
      children: [
        // Filter chips
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              _FilterChip(
                  label: 'All',
                  selected: _filter == 'all',
                  onTap: () => setState(() => _filter = 'all')),
              const SizedBox(width: 8),
              _FilterChip(
                  label: 'Below 75%',
                  selected: _filter == 'low',
                  onTap: () => setState(() => _filter = 'low'),
                  color: AppColors.warning),
              const SizedBox(width: 8),
              _FilterChip(
                  label: 'Critical',
                  selected: _filter == 'critical',
                  onTap: () => setState(() => _filter = 'critical'),
                  color: AppColors.error),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Student list
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'No students in this category',
                    style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) => StudentAnalyticsTile(
                    analytics: filtered[i],
                    rank: i + 1,
                  ),
                ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? activeColor.withValues(alpha: 0.12)
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? activeColor : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: selected ? activeColor : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ── Sessions Tab ──────────────────────────────────────────────────────────────

class _SessionsTab extends StatelessWidget {
  const _SessionsTab({required this.sessions});

  final List sessions;

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return const Center(child: Text('No session history'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sessions.length,
      itemBuilder: (ctx, i) =>
          SessionAnalyticsTile(analytics: sessions[i]),
    );
  }
}
