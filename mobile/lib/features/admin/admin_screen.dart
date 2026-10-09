import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/theme/colors.dart';
import '../../shared/widgets.dart';
import 'admin_api.dart';
import 'admin_beacons_tab.dart';
import 'admin_settings_tab.dart';
import 'admin_staff_tab.dart';

/// Admin panel: today's roster, approvals, proxy alerts, beacons, settings.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(icon: Icon(Icons.today), text: 'Today'),
              Tab(icon: Icon(Icons.people_alt_outlined), text: 'Staff'),
              Tab(icon: Icon(Icons.gpp_maybe_outlined), text: 'Alerts'),
              Tab(icon: Icon(Icons.bluetooth), text: 'Beacons'),
              Tab(icon: Icon(Icons.settings_outlined), text: 'Settings'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [RosterTab(), StaffTab(), AlertsTab(), BeaconsTab(), SettingsTab()],
        ),
      ),
    );
  }
}

// ── Today / roster ────────────────────────────────────────────────────────────

class RosterTab extends ConsumerStatefulWidget {
  const RosterTab({super.key});

  @override
  ConsumerState<RosterTab> createState() => _RosterTabState();
}

class _RosterTabState extends ConsumerState<RosterTab> {
  DateTime _day = DateTime.now();
  late Future<Json> _future = _load();

  Future<Json> _load() => ref.read(adminApiProvider).roster(_day);
  void _reload() => setState(() => _future = _load());

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      _day = picked;
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Json>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) return ErrorView(message: errorMessage(snap.error!), onRetry: _reload);
        final data = snap.data!;
        final summary = (data['summary'] as Map).cast<String, dynamic>();
        final rows = (data['rows'] as List).cast<Json>();
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Text(Fmt.date(_day), style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _pickDay,
                    icon: const Icon(Icons.edit_calendar),
                    label: const Text('Change'),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Count('Present', summary['present'], AppColors.present),
                  _Count('Late', summary['late'], AppColors.late_),
                  _Count('Not marked', summary['not_marked'], AppColors.textTertiary),
                  _Count('On leave', summary['on_leave'], AppColors.info),
                  _Count('Absent', summary['absent'], AppColors.absent),
                  _Count('Flagged', summary['flagged'], AppColors.warning),
                ],
              ),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                const EmptyState(icon: Icons.people_outline, title: 'No active staff yet'),
              for (final row in rows) _rosterTile(row),
            ],
          ),
        );
      },
    );
  }

  Widget _rosterTile(Json row) {
    final staff = (row['staff'] as Map).cast<String, dynamic>();
    final record = (row['attendance'] as Map?)?.cast<String, dynamic>();
    final flags = ((record?['flags'] as List?) ?? const []).cast<Object?>();
    final inAt = Fmt.parse(record?['check_in_at']);
    final outAt = Fmt.parse(record?['check_out_at']);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(staff['full_name'] as String? ?? ''),
        subtitle: Text(
          '${staff['employee_id'] ?? ''} · In ${Fmt.time(inAt)} · Out ${Fmt.time(outAt)}'
          '${flags.isNotEmpty ? '\n⚑ ${flags.join(', ')}' : ''}'
          '${record?['is_manual'] == true ? '\nManual: ${record?['manual_reason'] ?? ''}' : ''}',
        ),
        isThreeLine: flags.isNotEmpty || record?['is_manual'] == true,
        trailing: StatusBadge.attendance(row['status'] as String),
        onTap: () => _manualMark(staff),
      ),
    );
  }

  Future<void> _manualMark(Json staff) async {
    final reason = TextEditingController();
    var status = 'present';
    TimeOfDay? checkIn;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Mark ${staff['full_name']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'present', child: Text('Present')),
                  DropdownMenuItem(value: 'late', child: Text('Late')),
                  DropdownMenuItem(value: 'on_leave', child: Text('On leave')),
                  DropdownMenuItem(value: 'absent', child: Text('Absent')),
                ],
                onChanged: (v) => setLocal(() => status = v ?? status),
              ),
              const SizedBox(height: 12),
              if (status == 'present' || status == 'late')
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Check-in time'),
                  subtitle: Text(checkIn?.format(ctx) ?? 'Not set'),
                  trailing: const Icon(Icons.schedule),
                  onTap: () async {
                    final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.now());
                    if (t != null) setLocal(() => checkIn = t);
                  },
                ),
              TextField(
                controller: reason,
                decoration: const InputDecoration(labelText: 'Reason (required)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, reason.text.trim().length >= 3),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    try {
      await ref
          .read(adminApiProvider)
          .manualMark(
            staffId: staff['id'] as String,
            day: _day,
            status: status,
            reason: reason.text.trim(),
            checkIn: checkIn == null
                ? null
                : '${checkIn!.hour.toString().padLeft(2, '0')}:${checkIn!.minute.toString().padLeft(2, '0')}',
          );
      if (mounted) showSnack(context, 'Saved');
      _reload();
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    }
  }
}

class _Count extends StatelessWidget {
  const _Count(this.label, this.value, this.color);

  final String label;
  final Object? value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: CircleAvatar(
        backgroundColor: color,
        child: Text('${value ?? 0}', style: const TextStyle(color: Colors.white, fontSize: 11)),
      ),
      label: Text(label),
    );
  }
}

// ── Alerts (failed attempts) ──────────────────────────────────────────────────

class AlertsTab extends ConsumerStatefulWidget {
  const AlertsTab({super.key});

  @override
  ConsumerState<AlertsTab> createState() => _AlertsTabState();
}

class _AlertsTabState extends ConsumerState<AlertsTab> {
  late Future<List<Json>> _future = _load();

  Future<List<Json>> _load() => ref.read(adminApiProvider).attempts(DateTime.now());
  void _reload() => setState(() => _future = _load());

  static const _icons = {
    'FACE_MISMATCH': Icons.face_retouching_off,
    'DEVICE_MISMATCH': Icons.phonelink_erase,
    'DEVICE_IN_USE': Icons.phonelink_erase,
    'MOCK_LOCATION': Icons.wrong_location,
    'OUTSIDE_CAMPUS': Icons.wrong_location,
    'BEACON_TOKEN_INVALID': Icons.bluetooth_disabled,
    'BEACON_TOO_FAR': Icons.bluetooth_disabled,
    'LIVENESS_FAILED': Icons.visibility_off,
    'FACE_DUPLICATE': Icons.people,
    'EMULATOR_NOT_ALLOWED': Icons.computer,
  };

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Json>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) return ErrorView(message: errorMessage(snap.error!), onRetry: _reload);
        final rows = snap.data!;
        if (rows.isEmpty) {
          return EmptyState(
            icon: Icons.verified_user_outlined,
            color: AppColors.success,
            title: 'No failed attempts today',
            action: OutlinedButton(onPressed: _reload, child: const Text('Refresh')),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final r = rows[i];
              final code = r['reason_code'] as String? ?? 'UNKNOWN';
              final score = r['face_score'];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(_icons[code] ?? Icons.report_gmailerrorred, color: AppColors.error),
                  title: Text('${r['staff_name'] ?? 'Unknown'} — $code'),
                  subtitle: Text(
                    '${Fmt.time(Fmt.parse(r['created_at']))} · ${r['action']}'
                    '${score != null ? ' · face ${(score as num).toStringAsFixed(2)}' : ''}'
                    '\n${r['message'] ?? ''}',
                  ),
                  isThreeLine: true,
                ),
              );
            },
          ),
        );
      },
    );
  }
}
