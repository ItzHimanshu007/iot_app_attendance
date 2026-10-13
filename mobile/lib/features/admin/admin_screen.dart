import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/config.dart';
import '../../core/error_text.dart';
import '../../core/formatters.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../shared/widgets.dart';
import 'admin_api.dart';
import 'admin_beacons_tab.dart';
import 'admin_settings_tab.dart';
import 'admin_staff_tab.dart';

/// Admin console: today's overview, approvals, proxy alerts, beacons, settings.
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
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            _AdminHeader(embedded: embedded),
            const Expanded(
              child: TabBarView(
                children: [RosterTab(), StaffTab(), AlertsTab(), BeaconsTab(), SettingsTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Navy header with the console title and all five sections visible at once.
class _AdminHeader extends StatelessWidget {
  const _AdminHeader({required this.embedded});

  final bool embedded;

  static const _tabs = [
    (Icons.dashboard_outlined, 'Overview'),
    (Icons.badge_outlined, 'Staff'),
    (Icons.gpp_maybe_outlined, 'Alerts'),
    (Icons.settings_input_antenna_rounded, 'Beacons'),
    (Icons.tune_rounded, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Container(
        decoration: const BoxDecoration(gradient: AppColors.headerGradient),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(embedded ? 20 : 4, 14, 20, 10),
                child: Row(
                  children: [
                    if (!embedded) const BackButton(color: Colors.white),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ADMIN CONSOLE',
                            style: AppText.overline.copyWith(color: AppColors.gold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            AppConfig.collegeName,
                            style: AppText.h2.copyWith(color: Colors.white),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.admin_panel_settings_outlined, color: Colors.white),
                    ),
                  ],
                ),
              ),
              TabBar(
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white.withValues(alpha: 0.62),
                indicatorColor: AppColors.gold,
                indicatorWeight: 3,
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorPadding: const EdgeInsets.symmetric(horizontal: 14),
                dividerColor: Colors.transparent,
                labelPadding: EdgeInsets.zero,
                overlayColor: WidgetStateProperty.all(Colors.white.withValues(alpha: 0.06)),
                tabs: [
                  for (final (icon, label) in _tabs)
                    Tab(
                      height: 60,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 21),
                          const SizedBox(height: 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              label,
                              style: const TextStyle(
                                fontFamily: AppText.heading,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Overview ─────────────────────────────────────────────────────────────────

class _Overview {
  const _Overview(this.roster, this.failedAttempts, this.staff);

  final Json roster;
  final List<Json> failedAttempts;
  final List<Json> staff;
}

/// Roster statuses in display order, with the label used on this screen.
const _statusOrder = [
  ('present', 'On time'),
  ('late', 'Late'),
  ('on_leave', 'On leave'),
  ('absent', 'Absent'),
  ('not_marked', 'Not marked'),
];

class RosterTab extends ConsumerStatefulWidget {
  const RosterTab({super.key});

  @override
  ConsumerState<RosterTab> createState() => _RosterTabState();
}

class _RosterTabState extends ConsumerState<RosterTab> {
  DateTime _day = DateTime.now();
  String _filter = 'all';
  String _query = '';
  late Future<_Overview> _future = _load();

  Future<_Overview> _load() async {
    final api = ref.read(adminApiProvider);
    final roster = api.roster(_day);
    // The extras only feed "Needs attention"; the overview still works without them.
    final attempts = api.attempts(_day).catchError((Object _) => <Json>[]);
    final staff = api.staff().catchError((Object _) => <Json>[]);
    return _Overview(await roster, await attempts, await staff);
  }

  void _reload() => setState(() => _future = _load());

  bool get _isToday => DateUtils.isSameDay(_day, DateTime.now());

  void _shift(int days) {
    final next = _day.add(Duration(days: days));
    if (next.isAfter(DateTime.now())) return;
    _day = next;
    _filter = 'all';
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
      _filter = 'all';
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Overview>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) return ErrorView(message: errorMessage(snap.error!), onRetry: _reload);
        final data = snap.data!;
        final summary = (data.roster['summary'] as Map).cast<String, dynamic>();
        final rows = (data.roster['rows'] as List).cast<Json>();
        int n(String k) => (summary[k] as num?)?.toInt() ?? 0;
        final approvals = data.staff.where((s) => s['next_step'] == 'await_approval').length;

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _dayBar(),
              const SizedBox(height: 14),
              _SummaryCard(
                counts: {for (final (key, _) in _statusOrder) key: n(key)},
                total: n('total'),
                checkedOut: n('checked_out'),
                title: _isToday ? "Today's attendance" : 'Attendance on ${Fmt.date(_day)}',
              ),
              const SectionHeader('Needs attention'),
              _attention(
                approvals: approvals,
                failed: _isToday ? data.failedAttempts.length : 0,
                flagged: n('flagged'),
              ),
              SectionHeader('Staff · ${rows.length}'),
              ..._roster(rows),
            ],
          ),
        );
      },
    );
  }

  Widget _dayBar() {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous day',
            onPressed: () => _shift(-1),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: InkWell(
              onTap: _pickDay,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 17, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _isToday ? 'Today · ${Fmt.date(_day)}' : Fmt.date(_day),
                        style: AppText.bodyStrong,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Next day',
            onPressed: _isToday ? null : () => _shift(1),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  Widget _attention({required int approvals, required int failed, required int flagged}) {
    final tabs = DefaultTabController.of(context);
    final items = [
      if (approvals > 0)
        _AttentionItem(
          icon: Icons.how_to_reg_outlined,
          color: AppColors.warning,
          title: '$approvals staff waiting for approval',
          subtitle: 'Check their phone and face enrollment',
          onTap: () => tabs.animateTo(1),
        ),
      if (failed > 0)
        _AttentionItem(
          icon: Icons.gpp_bad_outlined,
          color: AppColors.error,
          title: '$failed failed check-in attempt${failed == 1 ? '' : 's'}',
          subtitle: 'Possible proxy: wrong face, phone or location',
          onTap: () => tabs.animateTo(2),
        ),
      if (flagged > 0)
        _AttentionItem(
          icon: Icons.flag_outlined,
          color: AppColors.gold,
          title: '$flagged check-in${flagged == 1 ? '' : 's'} flagged',
          subtitle: 'Accepted with a note, e.g. weak face match',
          onTap: () => setState(() => _filter = 'flagged'),
        ),
    ];
    if (items.isEmpty) {
      return const AppCard(
        padding: EdgeInsets.all(14),
        child: Row(
          children: [
            IconBadge(Icons.verified_outlined, color: AppColors.success, size: 40),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('All clear', style: AppText.bodyStrong),
                  SizedBox(height: 2),
                  Text('No approvals or proxy alerts waiting', style: AppText.caption),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 66),
            items[i],
          ],
        ],
      ),
    );
  }

  List<Widget> _roster(List<Json> rows) {
    if (rows.isEmpty) {
      return const [
        AppCard(
          child: EmptyState(
            icon: Icons.people_outline_rounded,
            title: 'No active staff yet',
            subtitle: 'Approve staff in the Staff tab to see them here.',
          ),
        ),
      ];
    }
    bool flagged(Json r) => (((r['attendance'] as Map?)?['flags'] as List?) ?? const []).isNotEmpty;
    final counts = <String, int>{
      'all': rows.length,
      for (final (key, _) in _statusOrder) key: rows.where((r) => r['status'] == key).length,
      'flagged': rows.where(flagged).length,
    };
    final labels = {'all': 'All', for (final (k, v) in _statusOrder) k: v, 'flagged': 'Flagged'};
    final q = _query.trim().toLowerCase();
    final visible = rows.where((r) {
      final match = switch (_filter) {
        'all' => true,
        'flagged' => flagged(r),
        _ => r['status'] == _filter,
      };
      if (!match) return false;
      if (q.isEmpty) return true;
      final staff = (r['staff'] as Map).cast<String, dynamic>();
      return '${staff['full_name']} ${staff['employee_id']} ${staff['department']}'
          .toLowerCase()
          .contains(q);
    }).toList();

    return [
      if (rows.length > 8) ...[
        TextField(
          onChanged: (v) => setState(() => _query = v),
          decoration: const InputDecoration(
            hintText: 'Search staff',
            prefixIcon: Icon(Icons.search_rounded),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
      ],
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final key in labels.keys)
              if (key == 'all' || (counts[key] ?? 0) > 0 || key == _filter)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('${labels[key]} ${counts[key] ?? 0}'),
                    selected: _filter == key,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _filter = key),
                  ),
                ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      if (visible.isEmpty)
        const AppCard(
          child: EmptyState(icon: Icons.filter_list_off_rounded, title: 'Nobody in this list'),
        )
      else
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < visible.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 68),
                _rosterRow(visible[i]),
              ],
            ],
          ),
        ),
      const SizedBox(height: 12),
      const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.touch_app_outlined, size: 15, color: AppColors.textTertiary),
          SizedBox(width: 6),
          Flexible(
            child: Text(
              'Tap a staff member to mark attendance manually',
              style: AppText.caption,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    ];
  }

  Widget _rosterRow(Json row) {
    final staff = (row['staff'] as Map).cast<String, dynamic>();
    final record = (row['attendance'] as Map?)?.cast<String, dynamic>();
    final status = row['status'] as String;
    final flags = ((record?['flags'] as List?) ?? const []);
    final inAt = Fmt.parse(record?['check_in_at']);
    final outAt = Fmt.parse(record?['check_out_at']);
    final name = staff['full_name'] as String? ?? '';
    final meta = [
      staff['department'],
      staff['employee_id'],
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    final manual = record?['is_manual'] == true;

    return InkWell(
      onTap: () => _manualMark(staff),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusAvatar(initials: Fmt.initials(name), color: statusColor(status)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: AppText.bodyStrong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      meta,
                      style: AppText.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StatusChip.attendance(status, dense: true),
                      if (inAt != null) _TimeTag(Icons.login_rounded, Fmt.time(inAt)),
                      if (outAt != null) _TimeTag(Icons.logout_rounded, Fmt.time(outAt)),
                      if (manual)
                        _TimeTag(
                          Icons.edit_note_rounded,
                          'Manual${record?['manual_reason'] != null ? ': ${record!['manual_reason']}' : ''}',
                        ),
                      if (flags.isNotEmpty)
                        StatusChip.tone(
                          'Flagged',
                          AppColors.warning,
                          icon: Icons.flag_rounded,
                          dense: true,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
            ),
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

/// Ring chart of the day's statuses with a legend of counts.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.counts,
    required this.total,
    required this.checkedOut,
    required this.title,
  });

  final Map<String, int> counts;
  final int total;
  final int checkedOut;
  final String title;

  @override
  Widget build(BuildContext context) {
    final checkedIn = (counts['present'] ?? 0) + (counts['late'] ?? 0);
    final rate = total == 0 ? 0 : (checkedIn * 100 / total).round();
    final ring = SizedBox.square(
      dimension: 118,
      child: CustomPaint(
        painter: _RingPainter([
          for (final (key, _) in _statusOrder) (counts[key] ?? 0, statusColor(key)),
        ]),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$rate%', style: AppText.h1.copyWith(height: 1.1)),
              const Text('present', style: AppText.caption),
            ],
          ),
        ),
      ),
    );
    final legend = Column(
      children: [
        for (final (key, label) in _statusOrder)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3.5),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: statusColor(key), shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: AppText.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text('${counts[key] ?? 0}', style: AppText.bodyStrong),
              ],
            ),
          ),
      ],
    );

    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppText.h3),
          const SizedBox(height: 2),
          Text('$checkedIn of $total staff checked in', style: AppText.caption),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, c) => c.maxWidth < 300
                ? Column(children: [ring, const SizedBox(height: 14), legend])
                : Row(
                    children: [
                      ring,
                      const SizedBox(width: 22),
                      Expanded(child: legend),
                    ],
                  ),
          ),
          const Divider(height: 26),
          Row(
            children: [
              const Icon(Icons.groups_2_outlined, size: 17, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text('$total staff', style: AppText.caption),
              const SizedBox(width: 18),
              const Icon(Icons.logout_rounded, size: 17, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '$checkedOut checked out',
                  style: AppText.caption,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.segments);

  final List<(int, Color)> segments;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 13.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = AppColors.surfaceMuted);
    final total = segments.fold<int>(0, (sum, s) => sum + s.$1);
    if (total == 0) return;
    final parts = segments.where((s) => s.$1 > 0).length;
    final gap = parts > 1 ? 0.05 : 0.0;
    var start = -math.pi / 2;
    for (final (value, color) in segments) {
      if (value == 0) continue;
      final sweep = 2 * math.pi * value / total;
      canvas.drawArc(
        rect,
        start + gap / 2,
        math.max(sweep - gap, 0.01),
        false,
        paint..color = color,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.segments.toString() != segments.toString();
}

class _AttentionItem extends StatelessWidget {
  const _AttentionItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            IconBadge(icon, color: color, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.bodyStrong),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppText.caption),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// Initials avatar with a small status dot.
class _StatusAvatar extends StatelessWidget {
  const _StatusAvatar({required this.initials, required this.color});

  final String initials;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Avatar(initials, size: 44),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeTag extends StatelessWidget {
  const _TimeTag(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: AppText.caption.copyWith(color: AppColors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
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
