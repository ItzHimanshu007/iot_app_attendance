import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/theme/colors.dart';
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
        data: (records) {
          if (records.isEmpty) {
            return const EmptyState(
              icon: Icons.event_busy,
              title: 'No attendance yet',
              subtitle: 'Your check-ins from the last 60 days will appear here.',
            );
          }
          final present = records.where((r) => r.status == 'present').length;
          final late = records.where((r) => r.status == 'late').length;
          return RefreshIndicator(
            onRefresh: () => ref.refresh(historyProvider.future),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    _Stat(label: 'Present', value: present, color: AppColors.present),
                    _Stat(label: 'Late', value: late, color: AppColors.late_),
                    _Stat(label: 'Days', value: records.length, color: AppColors.primary),
                  ],
                ),
                const SizedBox(height: 12),
                for (final r in records)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      title: Text(Fmt.date(r.date)),
                      subtitle: Text(
                        'In ${Fmt.time(r.checkInAt)} · Out ${Fmt.time(r.checkOutAt)}'
                        ' · ${Fmt.hours(r.checkInAt, r.checkOutAt)}'
                        '${r.isManual ? '\nMarked by admin: ${r.manualReason ?? ''}' : ''}',
                      ),
                      isThreeLine: r.isManual,
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          StatusBadge.attendance(r.status),
                          if (r.flags.isNotEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Icon(Icons.flag, size: 16, color: AppColors.warning),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Text(
                '$value',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: color),
              ),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
