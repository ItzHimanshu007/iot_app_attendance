import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../auth/controllers/auth_controller.dart';
import '../teacher/controllers/teacher_session_controller.dart';
import '../teacher/models/teacher_models.dart';
import '../../routes/app_router.dart';
import '../../shared/widgets/app_widgets.dart';

/// Teacher dashboard — home screen for teachers and admins.
class TeacherDashboard extends ConsumerWidget {
  const TeacherDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProvider);
    final firstName = profile?.fullName.split(' ').first ?? 'Teacher';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Good day,',
                style: AppTypography.labelMedium
                    .copyWith(color: AppColors.textSecondary)),
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
                backgroundColor: AppColors.secondarySurface,
                child: Text(
                  profile?.initials ?? '?',
                  style: AppTypography.labelMedium
                      .copyWith(color: AppColors.secondary),
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
            // ── Stats Card — live session count ──────────────────────────
            _TeacherStatsCard(),

            const SizedBox(height: 24),

            // ── Teacher Info Strip ──────────────────────────────────
            if (profile != null) ...[
              _TeacherInfoStrip(profile: profile),
              const SizedBox(height: 24),
            ],

            // ── Quick Actions ───────────────────────────────────────
            Text('Quick Actions', style: AppTypography.headlineSmall),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ActionCard(
                    icon: Icons.play_arrow_rounded,
                    label: 'Start Session',
                    subtitle: 'Begin attendance',
                    color: AppColors.success,
                    onTap: () => context.push(RoutePaths.sessionCreation),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionCard(
                    icon: Icons.history_edu,
                    label: 'My Sessions',
                    subtitle: 'Session history',
                    color: AppColors.info,
                    onTap: () => context.push(RoutePaths.timetable),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _ActionCard(
                    icon: Icons.analytics_outlined,
                    label: 'Reports',
                    subtitle: 'Attendance analytics',
                    color: AppColors.secondary,
                    onTap: () => context.push(RoutePaths.reports),
                  ),
                ),
                const SizedBox(width: 12),
                // ── Phase 2 Debug: BLE Scanner Test ─────────────────────────
                // TODO: Remove this action card after Phase 2 validation.
                Expanded(
                  child: _ActionCard(
                    icon: Icons.bluetooth_searching_rounded,
                    label: 'BLE Test',
                    subtitle: 'Debug scanner',
                    color: const Color(0xFFF59E0B), // amber — marks as debug
                    onTap: () => context.push(RoutePaths.bleScanner),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── Active Sessions ─────────────────────────────────────
            Text('Active Sessions', style: AppTypography.headlineSmall),
            const SizedBox(height: 12),
            _ActiveSessionSection(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (i) {
          if (i == 1) context.push(RoutePaths.profile);
          if (i == 2) context.push(RoutePaths.settings);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(RoutePaths.sessionCreation),
        heroTag: 'startSession',
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('Start Session'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
    );
  }
}

// ── Teacher Stats Card ────────────────────────────────────────────────────────

class _TeacherStatsCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timetableState = ref.watch(timetableControllerProvider);
    final sessionState = ref.watch(teacherSessionControllerProvider);

    final sessions = timetableState is TimetableLoaded
        ? timetableState.sessions
        : <AttendanceSession>[];
    final activeCount = sessions.where((s) => s.isActive).length;
    final totalStudents = sessions.fold<int>(
        0, (sum, s) => sum + s.totalPresent);
    final liveCount = sessionState is TeacherSessionActive
        ? sessionState.attendanceCount
        : 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Today\'s Overview',
                  style: AppTypography.titleMedium
                      .copyWith(color: Colors.white)),
              if (activeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                          color: Color(0xFF4ADE80),
                          shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 4),
                    Text('Live',
                        style: AppTypography.labelSmall
                            .copyWith(color: Colors.white)),
                  ]),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _StatCard(
                  value: activeCount.toString(), label: 'Active'),
              const SizedBox(width: 12),
              _StatCard(
                  value: liveCount > 0
                      ? liveCount.toString()
                      : totalStudents.toString(),
                  label: 'Present'),
              const SizedBox(width: 12),
              _StatCard(
                  value: sessions.isEmpty
                      ? '—'
                      : sessions.length.toString(),
                  label: 'Total'),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Active Session Section ────────────────────────────────────────────────────

class _ActiveSessionSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionState = ref.watch(teacherSessionControllerProvider);
    final timetableState = ref.watch(timetableControllerProvider);

    // If there's an active session in the controller, show live monitor card
    if (sessionState is TeacherSessionActive) {
      final session = sessionState.session;
      final remaining = session.remainingTime;
      final minutes = remaining != null ? remaining.inMinutes : 0;
      final seconds = remaining != null ? remaining.inSeconds % 60 : 0;

      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: AppColors.success.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        child: InkWell(
          onTap: () => context.push(RoutePaths.activeSession),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.successSurface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.wifi_tethering_rounded,
                          color: AppColors.success, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: AppColors.success,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text('LIVE',
                                style: AppTypography.labelSmall
                                    .copyWith(color: AppColors.success)),
                          ]),
                          Text('Session Active',
                              style: AppTypography.titleSmall),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 14),

                // ── Info grid ─────────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Present count
                    _SessionInfoChip(
                      icon: Icons.people_alt_outlined,
                      label: 'Present',
                      value: sessionState.attendanceCount.toString(),
                      color: AppColors.success,
                    ),

                    // Classroom ID
                    _SessionInfoChip(
                      icon: Icons.meeting_room_outlined,
                      label: 'Room',
                      value: session.classroomId,
                      color: AppColors.info,
                    ),

                    // Time remaining
                    _SessionInfoChip(
                      icon: Icons.timer_outlined,
                      label: 'Remaining',
                      value: remaining != null
                          ? '$minutes:${seconds.toString().padLeft(2, '0')}'
                          : '--:--',
                      color: minutes <= 5 ? AppColors.warning : AppColors.textSecondary,
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // ── Token chip ────────────────────────────────────────────
                // Students' mock token source will discover this token.
                // TODO: Remove or hide this chip after ESP32 integration.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.token_outlined,
                          size: 14, color: AppColors.textTertiary),
                      const SizedBox(width: 6),
                      Text(
                        'Token: ',
                        style: AppTypography.labelSmall
                            .copyWith(color: AppColors.textTertiary),
                      ),
                      Expanded(
                        child: Text(
                          session.notes != null
                              ? session.notes!
                              : '(token stored in backend)',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.textSecondary,
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Check timetable for any active sessions in history
    if (timetableState is TimetableLoaded &&
        timetableState.activeSessions.isNotEmpty) {
      return Column(
        children: timetableState.activeSessions
            .map((s) => _ActiveSessionBannerDash(session: s))
            .toList(),
      );
    }

    return const EmptyState(
      icon: Icons.event_available,
      title: 'No active sessions',
      subtitle: 'Tap "Start Session" to begin an attendance session.',
    );
  }
}

class _ActiveSessionBannerDash extends StatelessWidget {
  const _ActiveSessionBannerDash({required this.session});
  final AttendanceSession session;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Room ${session.classroomId} · ${session.totalPresent} present',
                style: AppTypography.bodyMedium,
              ),
            ),
            Text(
              'LIVE',
              style: AppTypography.labelSmall
                  .copyWith(color: AppColors.success),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeacherInfoStrip extends StatelessWidget {
  const _TeacherInfoStrip({required this.profile});
  final dynamic profile;

  @override
  Widget build(BuildContext context) {
    final isAdmin = profile.role == 'admin';
    final color = isAdmin ? AppColors.warning : AppColors.secondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Text(
              profile.initials,
              style: AppTypography.labelMedium.copyWith(color: color),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(profile.fullName, style: AppTypography.titleSmall),
                if (profile.department != null)
                  Text(
                    profile.department!,
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isAdmin ? '🛡️ Admin' : '📚 Teacher',
              style: AppTypography.labelSmall.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value,
                style: AppTypography.headlineMedium
                    .copyWith(color: Colors.white)),
            const SizedBox(height: 2),
            Text(label,
                style: AppTypography.labelSmall
                    .copyWith(color: Colors.white.withValues(alpha: 0.7))),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(height: 12),
              Text(label, style: AppTypography.titleSmall),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Session Info Chip ─────────────────────────────────────────────────────────

/// Small info chip used in the active session card on the dashboard.
class _SessionInfoChip extends StatelessWidget {
  const _SessionInfoChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 3),
        Text(
          label,
          style: AppTypography.labelSmall
              .copyWith(color: AppColors.textTertiary),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: AppTypography.titleSmall.copyWith(color: color),
        ),
      ],
    );
  }
}
