import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/error_text.dart';
import '../../core/formatters.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../shared/widgets.dart';
import 'admin_api.dart';
import 'admin_beacons_tab.dart';
import 'admin_settings_tab.dart';
import 'admin_staff_tab.dart';

/// Admin console: today's roster, approvals, proxy alerts, beacons, settings.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key, this.embedded = false, this.initialTab = 0});

  /// True when shown as a tab of the main shell (no back button).
  final bool embedded;
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !embedded,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Admin console'),
              Text(
                'Attendance management',
                style: TextStyle(
                  fontFamily: AppText.bodyFamily,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorSize: TabBarIndicatorSize.label,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Staff'),
              Tab(text: 'Alerts'),
              Tab(text: 'Beacons'),
              Tab(text: 'Settings'),
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

// ── Overview / roster ─────────────────────────────────────────────────────────

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

  bool get _isToday {
    final now = DateTime.now();
    return _day.year == now.year && _day.month == now.month && _day.day == now.day;
  }

  void _shift(int days) {
    final next = _day.add(Duration(days: days));
    if (next.isAfter(DateTime.now())) return;
    _day = next;
    _reload();
  }

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
        int n(String k) => (summary[k] as num?)?.toInt() ?? 0;
        final total = n('total');
        final marked = n('present') + n('late');
        final rate = total == 0 ? 0.0 : marked / total;

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => _shift(-1),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: _pickDay,
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            children: [
                              Text(_isToday ? 'Today' : Fmt.weekday(_day), style: AppText.overline),
                              Text(Fmt.date(_day), style: AppText.h3),
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _isToday ? null : () => _shift(1),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: AppColors.headerGradient,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${(rate * 100).round()}%',
                          style: AppText.display.copyWith(color: Colors.white),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Text(
                              'attendance · $marked of $total staff',
                              style: AppText.body.copyWith(color: Colors.white70),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: rate,
                        minHeight: 8,
                        color: AppColors.gold,
                        backgroundColor: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.86,
                children: [
                  StatTile(
                    label: 'On time',
                    value: '${n('present')}',
                    icon: Icons.check_circle_outline_rounded,
                    color: AppColors.success,
                  ),
                  StatTile(
                    label: 'Late',
                    value: '${n('late')}',
                    icon: Icons.timer_outlined,
                    color: AppColors.warning,
                  ),
                  StatTile(
                    label: 'Not marked',
                    value: '${n('not_marked')}',
                    icon: Icons.help_outline_rounded,
                    color: AppColors.notMarked,
                  ),
                  StatTile(
                    label: 'On leave',
                    value: '${n('on_leave')}',
                    icon: Icons.beach_access_outlined,
                    color: AppColors.info,
                  ),
                  StatTile(
                    label: 'Absent',
                    value: '${n('absent')}',
                    icon: Icons.cancel_outlined,
                    color: AppColors.error,
                  ),
                  StatTile(
                    label: 'Flagged',
                    value: '${n('flagged')}',
                    icon: Icons.flag_outlined,
                    color: AppColors.gold,
                  ),
                ],
              ),
              SectionHeader('Staff · ${rows.length}'),
              if (rows.isEmpty)
                const AppCard(
                  child: EmptyState(
                    icon: Icons.people_outline_rounded,
                    title: 'No active staff yet',
                  ),
                )
              else
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < rows.length; i++) ...[
                        if (i > 0) const Divider(indent: 70),
                        _rosterRow(rows[i]),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              const Text(
                'Tap a staff member to mark attendance manually.',
                style: AppText.caption,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _rosterRow(Json row) {
    final staff = (row['staff'] as Map).cast<String, dynamic>();
    final record = (row['attendance'] as Map?)?.cast<String, dynamic>();
    final flags = ((record?['flags'] as List?) ?? const []);
    final inAt = Fmt.parse(record?['check_in_at']);
    final outAt = Fmt.parse(record?['check_out_at']);
    final name = staff['full_name'] as String? ?? '';
    final initials = Fmt.initials(name);
    final detail = record == null
        ? (staff['department'] as String? ?? staff['employee_id'] as String? ?? '')
        : record['is_manual'] == true
        ? 'Manual · ${record['manual_reason'] ?? ''}'
        : 'In ${Fmt.time(inAt)} · Out ${Fmt.time(outAt)}';
    return InkWell(
      onTap: () => _manualMark(staff),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Avatar(initials, size: 42),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: AppText.bodyStrong, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: AppText.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (flags.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.flag_rounded, size: 18, color: AppColors.warning),
              ),
            StatusChip.attendance(row['status'] as String, dense: true),
          ],
        ),
      ),
    );
  }

  Future<void> _manualMark(Json staff) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ManualMarkSheet(staff: staff, day: _day),
    );
    if (saved == true) {
      if (mounted) showSnack(context, 'Attendance updated');
      _reload();
    }
  }
}

class _ManualMarkSheet extends ConsumerStatefulWidget {
  const _ManualMarkSheet({required this.staff, required this.day});

  final Json staff;
  final DateTime day;

  @override
  ConsumerState<_ManualMarkSheet> createState() => _ManualMarkSheetState();
}

class _ManualMarkSheetState extends ConsumerState<_ManualMarkSheet> {
  final _reason = TextEditingController();
  String _status = 'present';
  TimeOfDay? _checkIn;
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_reason.text.trim().length < 3) {
      showSnack(context, 'Please enter a reason', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final t = _checkIn;
      await ref
          .read(adminApiProvider)
          .manualMark(
            staffId: widget.staff['id'] as String,
            day: widget.day,
            status: _status,
            reason: _reason.text.trim(),
            checkIn: t == null
                ? null
                : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const options = {
      'present': 'Present',
      'late': 'Late',
      'on_leave': 'On leave',
      'absent': 'Absent',
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Manual attendance', style: AppText.h2),
          const SizedBox(height: 4),
          Text('${widget.staff['full_name']} · ${Fmt.date(widget.day)}', style: AppText.body),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in options.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _status == e.key,
                  onSelected: (_) => setState(() => _status = e.key),
                ),
            ],
          ),
          if (_status == 'present' || _status == 'late') ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.schedule_rounded),
              label: Text(
                _checkIn == null
                    ? 'Set check-in time (optional)'
                    : 'Check-in ${_checkIn!.format(context)}',
              ),
              onPressed: () async {
                final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                if (t != null) setState(() => _checkIn = t);
              },
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(
              labelText: 'Reason (required)',
              hintText: 'e.g. Phone not working, on official duty',
            ),
          ),
          const SizedBox(height: 18),
          PrimaryButton(label: 'Save', icon: Icons.save_outlined, busy: _busy, onPressed: _save),
        ],
      ),
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
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              MessageBanner(
                tone: rows.isEmpty ? BannerTone.success : BannerTone.warning,
                title: rows.isEmpty
                    ? 'No failed attempts today'
                    : '${rows.length} failed attempt${rows.length == 1 ? '' : 's'} today',
                message:
                    'Every rejected check-in is logged here — wrong face, wrong phone, '
                    'fake location, expired beacon code and more.',
              ),
              if (rows.isNotEmpty) ...[
                const SectionHeader('Latest first'),
                for (final r in rows) _alertCard(r),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _alertCard(Json r) {
    final code = r['reason_code'] as String?;
    final text = ErrorText.forCode(code);
    final score = r['face_score'] as num?;
    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(text.icon, color: AppColors.error, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(text.title, style: AppText.h3)),
                    Text(Fmt.time(Fmt.parse(r['created_at'])), style: AppText.caption),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${r['staff_name'] ?? 'Unknown'}${r['employee_id'] != null ? ' · ${r['employee_id']}' : ''}',
                  style: AppText.bodyStrong.copyWith(fontSize: 13.5),
                ),
                if (r['message'] != null) ...[
                  const SizedBox(height: 4),
                  Text('${r['message']}', style: AppText.caption),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    StatusChip.tone(
                      _actionLabel(r['action'] as String?),
                      AppColors.notMarked,
                      icon: Icons.touch_app_outlined,
                      dense: true,
                    ),
                    if (score != null)
                      StatusChip.tone(
                        'face ${(score * 100).round()}%',
                        AppColors.error,
                        dense: true,
                      ),
                    if (code != null)
                      StatusChip.tone(
                        code,
                        AppColors.textTertiary,
                        icon: Icons.code_rounded,
                        dense: true,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _actionLabel(String? action) => switch (action) {
  'challenge_check_in' || 'submit_check_in' => 'Check-in',
  'challenge_check_out' || 'submit_check_out' => 'Check-out',
  'device_register' => 'Phone registration',
  'face_enroll' => 'Face enrollment',
  _ => action ?? 'Unknown',
};
