import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/theme/colors.dart';
import '../../shared/widgets.dart';
import '../auth/models.dart';
import '../beacon/beacon_controller.dart';
import 'attendance_api.dart';
import 'mark_attendance.dart';

/// Staff home: today's status, live beacon detection and the mark button.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, required this.me});

  final Me me;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
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
      _startScan();
    } else if (state == AppLifecycleState.paused) {
      beacons.stop();
    }
  }

  void _startScan() {
    if (!mounted) return;
    ref.read(beaconControllerProvider.notifier).start();
  }

  Future<void> _refresh() async {
    ref.invalidate(todayProvider);
    await ref.read(beaconControllerProvider.notifier).restart();
    await ref.read(todayProvider.future).catchError((_) => TodayInfo(date: DateTime.now()));
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.me.profile;
    final today = ref.watch(todayProvider);
    final beacons = ref.watch(beaconControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hi, ${profile.firstName}'),
            Text(Fmt.date(DateTime.now()), style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'History',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => context.push('/history'),
          ),
          if (profile.isAdmin)
            IconButton(
              tooltip: 'Admin',
              icon: const Icon(Icons.admin_panel_settings_outlined),
              onPressed: () => context.push('/admin'),
            ),
          IconButton(
            tooltip: 'Profile',
            icon: CircleAvatar(
              radius: 15,
              child: Text(profile.initials, style: const TextStyle(fontSize: 12)),
            ),
            onPressed: () => context.push('/profile'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            today.when(
              data: (info) => _TodayCard(info: info),
              loading: () => const Card(
                child: SizedBox(height: 140, child: Center(child: CircularProgressIndicator())),
              ),
              error: (e, _) => Card(
                child: ErrorView(
                  message: errorMessage(e),
                  onRetry: () => ref.invalidate(todayProvider),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _BeaconCard(state: beacons),
            const SizedBox(height: 24),
            _ActionButton(today: today.value, beacons: beacons),
            const SizedBox(height: 16),
            Text(
              'Your phone must be near a campus beacon. You will then blink/smile/turn '
              'as asked so the app can verify it is really you.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.info});

  final TodayInfo info;

  @override
  Widget build(BuildContext context) {
    final record = info.record;
    final theme = Theme.of(context);
    final status = record?.status ?? 'not_marked';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Today', style: theme.textTheme.titleLarge),
                const Spacer(),
                StatusBadge.attendance(status),
              ],
            ),
            if (info.workStart != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Office starts ${info.workStart!.substring(0, 5)}'
                  '${info.lateGraceMinutes != null ? ' · ${info.lateGraceMinutes} min grace' : ''}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                _TimeTile(label: 'Check-in', value: Fmt.time(record?.checkInAt), icon: Icons.login),
                _TimeTile(
                  label: 'Check-out',
                  value: Fmt.time(record?.checkOutAt),
                  icon: Icons.logout,
                ),
                _TimeTile(
                  label: 'Hours',
                  value: Fmt.hours(record?.checkInAt, record?.checkOutAt),
                  icon: Icons.timelapse,
                ),
              ],
            ),
            if (record?.isManual == true && record?.manualReason != null) ...[
              const SizedBox(height: 12),
              Text('Marked by admin: ${record!.manualReason}', style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(height: 6),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _BeaconCard extends ConsumerWidget {
  const _BeaconCard({required this.state});

  final BeaconState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(beaconControllerProvider.notifier);
    final nearest = state.nearest;

    if (nearest != null) {
      return InfoCard(
        icon: Icons.bluetooth_connected,
        color: AppColors.success,
        title: 'On campus — ${nearest.name}',
        subtitle: 'Signal ${nearest.signalLabel} (${nearest.rssi} dBm)',
        trailing: const Icon(Icons.check_circle, color: AppColors.success),
      );
    }

    return switch (state.status) {
      BeaconStatus.bluetoothOff => InfoCard(
        icon: Icons.bluetooth_disabled,
        color: AppColors.warning,
        title: 'Bluetooth is off',
        subtitle: state.message,
        trailing: TextButton(onPressed: controller.turnOnBluetooth, child: const Text('Turn on')),
      ),
      BeaconStatus.permissionDenied || BeaconStatus.locationOff || BeaconStatus.error => InfoCard(
        icon: Icons.warning_amber,
        color: AppColors.warning,
        title: 'Beacon scan unavailable',
        subtitle: state.message,
        trailing: TextButton(onPressed: controller.restart, child: const Text('Retry')),
      ),
      BeaconStatus.unsupported => InfoCard(
        icon: Icons.block,
        color: AppColors.error,
        title: 'Bluetooth LE not supported',
        subtitle: state.message,
      ),
      _ => const InfoCard(
        icon: Icons.bluetooth_searching,
        title: 'Looking for a campus beacon…',
        subtitle: 'Walk to the staff room or your department office.',
        trailing: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    };
  }
}

class _ActionButton extends ConsumerWidget {
  const _ActionButton({required this.today, required this.beacons});

  final TodayInfo? today;
  final BeaconState beacons;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = today;
    if (info == null) return const SizedBox.shrink();
    final action = info.nextAction;
    if (action == null) {
      return InfoCard(
        icon: Icons.task_alt,
        color: AppColors.success,
        title: info.record?.isLockedByAdmin == true
            ? 'Marked ${Fmt.statusLabel(info.record!.status).toLowerCase()} by admin'
            : 'All done for today',
        subtitle: 'See you tomorrow!',
      );
    }
    final inRange = beacons.nearest != null;
    final label = action == 'check_in' ? 'Check in' : 'Check out';
    return BusyButton(
      label: inRange ? label : '$label (get near a beacon)',
      icon: action == 'check_in' ? Icons.face_retouching_natural : Icons.logout,
      onPressed: inRange ? () => markAttendance(context, ref, action) : null,
    );
  }
}
