import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/config.dart';
import '../../core/formatters.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../shared/widgets.dart';
import '../auth/models.dart';
import '../beacon/beacon_controller.dart';
import 'attendance_api.dart';
import 'mark_attendance.dart';

/// Staff dashboard: today's status, campus beacon presence and the mark button.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, required this.me, this.onOpenHistory});

  final Me me;
  final VoidCallback? onOpenHistory;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(beaconControllerProvider.notifier).start();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final beacons = ref.read(beaconControllerProvider.notifier);
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(todayProvider);
      beacons.start();
    } else if (state == AppLifecycleState.paused) {
      beacons.stop();
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(todayProvider);
    ref.invalidate(historyProvider);
    await ref.read(beaconControllerProvider.notifier).restart();
    await ref.read(todayProvider.future).catchError((_) => TodayInfo(date: DateTime.now()));
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.me.profile;
    final today = ref.watch(todayProvider);
    final beacons = ref.watch(beaconControllerProvider);
    final campusName = today.value?.campusName ?? AppConfig.collegeName;
    final role = [
      profile.designation,
      profile.department,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        edgeOffset: 120,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            GradientHeader(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 64),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const BrandLogo(size: 34),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              campusName.toUpperCase(),
                              style: AppText.overline.copyWith(color: Colors.white70),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              AppConfig.appName,
                              style: AppText.h3.copyWith(color: Colors.white, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                      Avatar(profile.initials, size: 40, onDark: true),
                    ],
                  ),
                  const SizedBox(height: 26),
                  Text(
                    '${Fmt.greeting()},',
                    style: AppText.body.copyWith(color: Colors.white.withValues(alpha: 0.75)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    profile.fullName,
                    style: AppText.h1.copyWith(color: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (role.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      role,
                      style: AppText.caption.copyWith(color: Colors.white.withValues(alpha: 0.75)),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today_rounded, size: 14, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          Fmt.longDate(DateTime.now()),
                          style: AppText.caption.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    today.when(
                      data: (info) => _TodayCard(info: info),
                      loading: () => const AppCard(child: LoadingBlock(height: 150)),
                      error: (e, _) => AppCard(
                        child: ErrorView(
                          message: errorMessage(e),
                          onRetry: () => ref.invalidate(todayProvider),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _PresenceCard(state: beacons),
                    const SizedBox(height: 14),
                    _ActionArea(today: today.value, beacons: beacons),
                    const SectionHeader('This month'),
                    _MonthStats(onOpenHistory: widget.onOpenHistory),
                    const SizedBox(height: 18),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_outline_rounded, size: 14, color: AppColors.textTertiary),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Your photo is never stored or uploaded.',
                            style: AppText.caption,
                          ),
                        ),
                      ],
                    ),
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

// ── Today ─────────────────────────────────────────────────────────────────────

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.info});

  final TodayInfo info;

  @override
  Widget build(BuildContext context) {
    final record = info.record;
    final status = record?.status ?? 'not_marked';
    final inAt = record?.checkInAt;
    final outAt = record?.checkOutAt;
    final worked = inAt == null ? null : Fmt.hours(inAt, outAt ?? DateTime.now());

    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text("Today's attendance", style: AppText.h3)),
              StatusChip.attendance(status),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _TimePoint(
                label: 'Check in',
                time: inAt,
                icon: Icons.login_rounded,
                color: AppColors.success,
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      worked ?? 'Not started',
                      style: AppText.caption.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2),
                              gradient: LinearGradient(
                                colors: [
                                  inAt != null ? AppColors.success : AppColors.border,
                                  outAt != null ? AppColors.primary : AppColors.border,
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text('worked', style: AppText.caption),
                  ],
                ),
              ),
              _TimePoint(
                label: 'Check out',
                time: outAt,
                icon: Icons.logout_rounded,
                color: AppColors.primary,
                alignEnd: true,
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.schedule_rounded, size: 16, color: AppColors.textTertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  record?.isManual == true
                      ? 'Marked by admin: ${record?.manualReason ?? ''}'
                      : info.workStart == null
                      ? 'Office hours'
                      : 'Office starts ${info.workStart!.substring(0, 5)}'
                            '${info.lateGraceMinutes != null ? ' · ${info.lateGraceMinutes} min grace' : ''}',
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

class _TimePoint extends StatelessWidget {
  const _TimePoint({
    required this.label,
    required this.time,
    required this.icon,
    required this.color,
    this.alignEnd = false,
  });

  final String label;
  final DateTime? time;
  final IconData icon;
  final Color color;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final done = time != null;
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: done ? color : AppColors.textTertiary),
            const SizedBox(width: 6),
            Text(label, style: AppText.caption),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          done ? Fmt.time(time) : '--:--',
          style: AppText.number.copyWith(
            fontSize: 20,
            color: done ? AppColors.text : AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

// ── Campus presence (BLE beacon) ──────────────────────────────────────────────

class _PresenceCard extends ConsumerWidget {
  const _PresenceCard({required this.state});

  final BeaconState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(beaconControllerProvider.notifier);
    final nearest = state.nearest;

    Widget card({
      required IconData icon,
      required Color color,
      required String title,
      required String subtitle,
      Widget? trailing,
    }) => AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          IconBadge(icon, color: color, size: 46),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.h3),
                const SizedBox(height: 2),
                Text(subtitle, style: AppText.caption),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );

    if (nearest != null) {
      return card(
        icon: Icons.bluetooth_connected_rounded,
        color: AppColors.success,
        title: 'You are on campus',
        subtitle: '${nearest.name} · ${nearest.signalLabel} signal',
        trailing: SignalBars(rssi: nearest.rssi),
      );
    }
    return switch (state.status) {
      BeaconStatus.bluetoothOff => card(
        icon: Icons.bluetooth_disabled_rounded,
        color: AppColors.warning,
        title: 'Bluetooth is off',
        subtitle: 'Turn it on to detect the campus beacon.',
        trailing: TextButton(onPressed: controller.turnOnBluetooth, child: const Text('Turn on')),
      ),
      BeaconStatus.permissionDenied || BeaconStatus.locationOff || BeaconStatus.error => card(
        icon: Icons.warning_amber_rounded,
        color: AppColors.warning,
        title: 'Beacon scan unavailable',
        subtitle: state.message ?? 'Check Bluetooth and Location permissions.',
        trailing: TextButton(onPressed: controller.restart, child: const Text('Retry')),
      ),
      BeaconStatus.unsupported => card(
        icon: Icons.block_rounded,
        color: AppColors.error,
        title: 'Bluetooth LE not supported',
        subtitle: state.message ?? 'This phone cannot detect campus beacons.',
      ),
      _ => card(
        icon: Icons.bluetooth_searching_rounded,
        color: AppColors.primary,
        title: 'Looking for a campus beacon',
        subtitle: 'Walk to the staff room or your department office.',
        trailing: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      ),
    };
  }
}

// ── Main action ───────────────────────────────────────────────────────────────

class _ActionArea extends ConsumerWidget {
  const _ActionArea({required this.today, required this.beacons});

  final TodayInfo? today;
  final BeaconState beacons;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = today;
    if (info == null) return const SizedBox.shrink();
    final action = info.nextAction;
    if (action == null) {
      final locked = info.record?.isLockedByAdmin == true;
      return MessageBanner(
        tone: locked ? BannerTone.info : BannerTone.success,
        title: locked
            ? 'Marked ${Fmt.statusLabel(info.record!.status).toLowerCase()} by admin'
            : 'All done for today',
        message: locked
            ? 'Attendance for today has been recorded by the administrator.'
            : 'Your check-in and check-out are recorded. See you tomorrow!',
      );
    }

    final inRange = beacons.nearest != null;
    final checkIn = action == 'check_in';
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Step(icon: Icons.bluetooth_rounded, label: 'Beacon', done: inRange),
              const _StepLine(),
              const _Step(icon: Icons.face_rounded, label: 'Face'),
              const _StepLine(),
              const _Step(icon: Icons.location_on_outlined, label: 'Location'),
            ],
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: inRange
                ? (checkIn ? 'Check in now' : 'Check out now')
                : 'Move near a campus beacon',
            icon: inRange
                ? (checkIn ? Icons.face_retouching_natural : Icons.logout_rounded)
                : Icons.bluetooth_searching_rounded,
            color: checkIn ? AppColors.primary : AppColors.navy,
            onPressed: inRange ? () => markAttendance(context, ref, action) : null,
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.label, this.done = false});

  final IconData icon;
  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final color = done ? AppColors.success : AppColors.textSecondary;
    return Column(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: done ? AppColors.successSoft : AppColors.surfaceMuted,
            shape: BoxShape.circle,
          ),
          child: Icon(done ? Icons.check_rounded : icon, size: 18, color: color),
        ),
        const SizedBox(height: 6),
        Text(label, style: AppText.caption.copyWith(fontSize: 11.5, color: color)),
      ],
    );
  }
}

class _StepLine extends StatelessWidget {
  const _StepLine();

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      height: 2,
      margin: const EdgeInsets.only(bottom: 20, left: 6, right: 6),
      color: AppColors.border,
    ),
  );
}

// ── Month summary ─────────────────────────────────────────────────────────────

class _MonthStats extends ConsumerWidget {
  const _MonthStats({this.onOpenHistory});

  final VoidCallback? onOpenHistory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(historyProvider).value ?? const <AttendanceRecord>[];
    final now = DateTime.now();
    final month = records
        .where((r) => r.date.year == now.year && r.date.month == now.month)
        .toList();
    final present = month.where((r) => r.status == 'present' || r.status == 'late').length;
    final late = month.where((r) => r.status == 'late').length;
    final ins = month.map((r) => r.checkInAt).whereType<DateTime>().toList();
    String avg = '—';
    if (ins.isNotEmpty) {
      final minutes = ins.map((t) => t.hour * 60 + t.minute).reduce((a, b) => a + b) ~/ ins.length;
      avg = Fmt.time(DateTime(now.year, now.month, now.day, minutes ~/ 60, minutes % 60));
    }
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'Days present',
                value: '$present',
                icon: Icons.event_available_rounded,
                color: AppColors.success,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                label: 'Late arrivals',
                value: '$late',
                icon: Icons.timer_outlined,
                color: AppColors.warning,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                label: 'Avg. check-in',
                value: avg,
                icon: Icons.schedule_rounded,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        if (onOpenHistory != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onOpenHistory,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('View full history'),
            ),
          ),
      ],
    );
  }
}
