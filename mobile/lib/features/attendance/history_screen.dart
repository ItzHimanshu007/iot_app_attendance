import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../shared/widgets.dart';
import 'attendance_api.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('My attendance')),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            ErrorView(message: errorMessage(e), onRetry: () => ref.invalidate(historyProvider)),
        data: (records) => RefreshIndicator(
          onRefresh: () => ref.refresh(historyProvider.future),
          child: records.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 80),
                    EmptyState(
                      icon: Icons.event_note_rounded,
                      title: 'No attendance yet',
                      subtitle: 'Your check-ins from the last 60 days will appear here.',
                    ),
                  ],
                )
              : _HistoryList(records: records),
        ),
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.records});

  final List<AttendanceRecord> records;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<AttendanceRecord>>{};
    for (final r in records) {
      groups.putIfAbsent(Fmt.monthYear(r.date), () => []).add(r);
    }
    final attended = records.where((r) => r.status == 'present' || r.status == 'late').length;
    final late = records.where((r) => r.status == 'late').length;
    final onTime = attended == 0 ? 0.0 : (attended - late) / attended;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: AppColors.headerGradient,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('LAST 60 DAYS', style: AppText.overline.copyWith(color: Colors.white60)),
              const SizedBox(height: 12),
              Row(
                children: [
                  _HeroNumber(value: '$attended', label: 'Days present'),
                  _HeroNumber(value: '$late', label: 'Late'),
                  _HeroNumber(value: '${(onTime * 100).round()}%', label: 'On time'),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: onTime,
                  minHeight: 7,
                  color: AppColors.gold,
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                ),
              ),
            ],
          ),
        ),
        for (final entry in groups.entries) ...[
          SectionHeader(entry.key),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < entry.value.length; i++) ...[
                  if (i > 0) const Divider(indent: 76),
                  _DayRow(record: entry.value[i]),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _HeroNumber extends StatelessWidget {
  const _HeroNumber({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: AppText.number.copyWith(color: Colors.white)),
        const SizedBox(height: 2),
        Text(label, style: AppText.caption.copyWith(color: Colors.white70)),
      ],
    ),
  );
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.record});

  final AttendanceRecord record;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final color = statusColor(r.status);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Container(
            width: 48,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: statusSoftColor(r.status),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text('${r.date.day}', style: AppText.h2.copyWith(color: color, height: 1.1)),
                Text(
                  Fmt.weekday(r.date).toUpperCase(),
                  style: AppText.overline.copyWith(color: color, fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.checkedIn
                      ? '${Fmt.time(r.checkInAt)}  –  ${r.checkedOut ? Fmt.time(r.checkOutAt) : '…'}'
                      : Fmt.statusLabel(r.status),
                  style: AppText.bodyStrong,
                ),
                const SizedBox(height: 2),
                Text(
                  r.isManual
                      ? 'Marked by admin${r.manualReason != null ? ' · ${r.manualReason}' : ''}'
                      : r.checkedOut
                      ? 'Worked ${Fmt.hours(r.checkInAt, r.checkOutAt)}'
                      : r.checkedIn
                      ? 'No check-out recorded'
                      : '',
                  style: AppText.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (r.flags.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Tooltip(
                message: 'Flagged for review',
                child: Icon(Icons.flag_rounded, size: 18, color: AppColors.warning),
              ),
            ),
          StatusChip.attendance(r.status, dense: true),
        ],
      ),
    );
  }
}
