import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../auth/controllers/auth_controller.dart';
import '../device/controllers/device_controller.dart';
import '../device/models/device_models.dart';
import '../device/widgets/device_widgets.dart';
import '../../routes/app_router.dart';
import '../../shared/widgets/app_widgets.dart';

/// Student dashboard — home screen for students.
class StudentDashboard extends ConsumerWidget {
  const StudentDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProvider);
    final firstName = profile?.fullName.split(' ').first ?? 'Student';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Good day,',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            Text(firstName, style: AppTypography.titleMedium),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
          GestureDetector(
            onTap: () => context.push(RoutePaths.profile),
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primarySurface,
                child: Text(
                  profile?.initials ?? '?',
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Quick Stats Card ─────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppColors.cardGradient,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Today\'s Attendance',
                    style: AppTypography.titleMedium.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _StatItem(
                        value: '—',
                        label: 'Classes',
                        color: Colors.white,
                      ),
                      const SizedBox(width: 24),
                      _StatItem(
                        value: '—',
                        label: 'Present',
                        color: Colors.white,
                      ),
                      const SizedBox(width: 24),
                      _StatItem(
                        value: '—%',
                        label: 'Rate',
                        color: Colors.white,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── User Info Strip ─────────────────────────────────────
            if (profile != null) ...[
              _UserInfoStrip(profile: profile),
              const SizedBox(height: 16),
            ],

            // ── Device Status ────────────────────────────────────────
            _DeviceStatusSection(),
            const SizedBox(height: 24),

            // ── Active Sessions ─────────────────────────────────────
            Text('Active Sessions', style: AppTypography.headlineSmall),
            const SizedBox(height: 12),

            // Scan for session CTA
            Card(
              child: InkWell(
                onTap: () => context.push(RoutePaths.sessionDiscovery),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primarySurface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.radar,
                          color: AppColors.primary,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Scan for Session',
                              style: AppTypography.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Find nearby ESP32 attendance beacons',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: AppColors.textTertiary,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Recent Attendance ────────────────────────────────────
            Text('Recent Attendance', style: AppTypography.headlineSmall),
            const SizedBox(height: 12),
            const EmptyState(
              icon: Icons.history,
              title: 'No records yet',
              subtitle: 'Your attendance history will appear here.',
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (i) {
          if (i == 1) context.push(RoutePaths.attendanceHistory);
          if (i == 2) context.push(RoutePaths.profile);
          if (i == 3) context.push(RoutePaths.settings);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _UserInfoStrip extends StatelessWidget {
  const _UserInfoStrip({required this.profile});
  final dynamic profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            child: Text(
              profile.initials,
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(profile.fullName, style: AppTypography.titleSmall),
                if (profile.studentIdNumber != null)
                  Text(
                    'ID: ${profile.studentIdNumber}',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                if (profile.department != null)
                  Text(
                    profile.department!,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '🎓 Student',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.success,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: AppTypography.displaySmall.copyWith(color: color)),
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: color.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

/// Inline device status section — checks and shows device registration state.
class _DeviceStatusSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceState = ref.watch(deviceControllerProvider);

    // Auto-check on first build
    if (deviceState is DeviceInitial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(deviceControllerProvider.notifier).checkDeviceStatus();
      });
      return const SizedBox.shrink();
    }

    if (deviceState is DeviceChecking) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }

    final status = switch (deviceState) {
      DeviceRegistered() => DeviceRegistrationStatus.registered,
      DeviceUnregistered() => DeviceRegistrationStatus.unregistered,
      DeviceInactive() => DeviceRegistrationStatus.inactive,
      DeviceMismatch() => DeviceRegistrationStatus.mismatch,
      _ => DeviceRegistrationStatus.unknown,
    };

    final deviceInfo = deviceState is DeviceRegistered
        ? (deviceState).device
        : null;

    return DeviceStatusCard(
      status: status,
      deviceInfo: deviceInfo,
      onTap: status != DeviceRegistrationStatus.registered
          ? () => context.push(RoutePaths.deviceRegistration)
          : null,
    );
  }
}
