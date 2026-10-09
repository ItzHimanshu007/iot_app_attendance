import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../models/reports_models.dart';

// ── Attendance Trend Line Chart ───────────────────────────────────────────────

/// Line chart — attendance count over time (one point per session).
class AttendanceTrendChart extends StatefulWidget {
  const AttendanceTrendChart({
    super.key,
    required this.trend,
    this.height = 220,
  });

  final AttendanceTrendData trend;
  final double height;

  @override
  State<AttendanceTrendChart> createState() => _AttendanceTrendChartState();
}

class _AttendanceTrendChartState extends State<AttendanceTrendChart> {
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    if (!widget.trend.hasData) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: Text('No trend data yet'),
        ),
      );
    }

    final points = widget.trend.points;
    final spots = List.generate(points.length, (i) {
      return FlSpot(i.toDouble(), points[i].count.toDouble());
    });

    final maxY =
        (widget.trend.maxCount * 1.2).ceilToDouble().clamp(5.0, double.infinity);

    return SizedBox(
      height: widget.height,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (spots.length - 1).toDouble(),
          minY: 0,
          maxY: maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (maxY / 4).roundToDouble(),
            getDrawingHorizontalLine: (v) => FlLine(
              color: AppColors.border.withValues(alpha: 0.5),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                interval: (maxY / 4).roundToDouble(),
                getTitlesWidget: (v, meta) => Text(
                  v.toInt().toString(),
                  style: AppTypography.labelSmall
                      .copyWith(color: AppColors.textTertiary),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: (spots.length / 4).ceilToDouble().clamp(1, double.infinity),
                getTitlesWidget: (v, meta) {
                  final idx = v.toInt();
                  if (idx >= points.length) return const SizedBox.shrink();
                  final dt = points[idx].date;
                  return Text(
                    '${dt.day}/${dt.month}',
                    style: AppTypography.labelSmall
                        .copyWith(color: AppColors.textTertiary),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppColors.surface,
              getTooltipItems: (spots) {
                return spots.map((spot) {
                  final idx = spot.x.toInt();
                  final dt = points[idx].date;
                  return LineTooltipItem(
                    '${spot.y.toInt()} present\n${dt.day}/${dt.month}/${dt.year}',
                    AppTypography.labelSmall.copyWith(
                      color: AppColors.primary,
                    ),
                  );
                }).toList();
              },
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.35,
              color: AppColors.primary,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) =>
                    FlDotCirclePainter(
                  radius: _touchedIndex == index ? 6 : 4,
                  color: AppColors.primary,
                  strokeWidth: 2,
                  strokeColor: Colors.white,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.25),
                    AppColors.primary.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Subject Comparison Bar Chart ──────────────────────────────────────────────

/// Horizontal bar chart — attendance rate per subject.
class SubjectComparisonChart extends StatelessWidget {
  const SubjectComparisonChart({
    super.key,
    required this.subjects,
    this.height = 220,
  });

  final List<SubjectAnalytics> subjects;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (subjects.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: Text('No subject data yet')),
      );
    }

    final data = subjects.take(6).toList();

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: 1.0,
          minY: 0,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => AppColors.surface,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final sub = data[group.x.toInt()];
                return BarTooltipItem(
                  '${sub.subject.code}\n${(rod.toY * 100).toStringAsFixed(1)}%',
                  AppTypography.labelSmall.copyWith(
                    color: AppColors.primary,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                interval: 0.25,
                getTitlesWidget: (v, meta) => Text(
                  '${(v * 100).toInt()}%',
                  style: AppTypography.labelSmall
                      .copyWith(color: AppColors.textTertiary),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, meta) {
                  final idx = v.toInt();
                  if (idx >= data.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      data[idx].subject.code,
                      style: AppTypography.labelSmall
                          .copyWith(color: AppColors.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 0.25,
            getDrawingHorizontalLine: (v) => FlLine(
              color: AppColors.border.withValues(alpha: 0.5),
              strokeWidth: 1,
            ),
          ),
          barGroups: List.generate(data.length, (i) {
            final rate = data[i].attendanceRate;
            final barColor = rate >= 0.75
                ? AppColors.success
                : rate >= 0.50
                    ? AppColors.warning
                    : AppColors.error;
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: rate,
                  color: barColor,
                  width: 28,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(6)),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: 1.0,
                    color:
                        AppColors.surfaceVariant.withValues(alpha: 0.5),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

// ── Attendance Distribution Pie Chart ─────────────────────────────────────────

/// Donut chart — student threshold distribution (good / warning / critical).
class AttendanceDistributionChart extends StatefulWidget {
  const AttendanceDistributionChart({
    super.key,
    required this.students,
    this.size = 180,
  });

  final List<StudentAnalytics> students;
  final double size;

  @override
  State<AttendanceDistributionChart> createState() =>
      _AttendanceDistributionChartState();
}

class _AttendanceDistributionChartState
    extends State<AttendanceDistributionChart> {
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.students.isEmpty) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: const Center(child: Text('No data')),
      );
    }

    final good = widget.students
        .where((s) => s.threshold == AttendanceThreshold.good)
        .length;
    final warning = widget.students
        .where((s) => s.threshold == AttendanceThreshold.warning)
        .length;
    final critical = widget.students
        .where((s) => s.threshold == AttendanceThreshold.critical)
        .length;

    final sections = <PieChartSectionData>[
      if (good > 0)
        _section(good, AppColors.success, '≥75%', 0),
      if (warning > 0)
        _section(warning, AppColors.warning, '50–75%', 1),
      if (critical > 0)
        _section(critical, AppColors.error, '<50%', 2),
    ];

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: PieChart(
        PieChartData(
          sections: sections,
          centerSpaceRadius: widget.size * 0.28,
          sectionsSpace: 2,
          pieTouchData: PieTouchData(
            touchCallback: (event, response) {
              setState(() {
                if (!event.isInterestedForInteractions ||
                    response == null ||
                    response.touchedSection == null) {
                  _touchedIndex = null;
                } else {
                  _touchedIndex =
                      response.touchedSection!.touchedSectionIndex;
                }
              });
            },
          ),
        ),
      ),
    );
  }

  PieChartSectionData _section(
      int count, Color color, String label, int index) {
    final touched = _touchedIndex == index;
    return PieChartSectionData(
      color: color,
      value: count.toDouble(),
      radius: touched ? widget.size * 0.32 : widget.size * 0.28,
      title: touched ? '$count' : '',
      titleStyle: AppTypography.labelSmall.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}
