import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/config.dart';
import '../../core/formatters.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../shared/widgets.dart';
import '../auth/auth_service.dart';
import '../auth/session.dart';

final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version} (${info.buildNumber})';
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need your email and password to sign in again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              minimumSize: const Size(100, 44),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(authServiceProvider).signOut();
    if (context.mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider).value;
    if (me == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final p = me.profile;
    final device = me.device;
    final faceStatus = me.onboarding.faceStatus;
    final version = ref.watch(appVersionProvider).value ?? '—';

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          GradientHeader(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              children: [
                Avatar(p.initials, size: 80, onDark: true),
                const SizedBox(height: 14),
                Text(
                  p.fullName,
                  style: AppText.h1.copyWith(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                if (p.designation != null && p.designation!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    p.designation!,
                    style: AppText.body.copyWith(color: Colors.white.withValues(alpha: 0.78)),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    _HeaderChip(icon: Icons.badge_outlined, label: p.employeeId ?? 'No ID'),
                    _HeaderChip(
                      icon: p.isAdmin ? Icons.admin_panel_settings_outlined : Icons.person_outline,
                      label: p.isAdmin ? 'Administrator' : 'Staff',
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader('Work details'),
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Column(
                    children: [
                      InfoRow(
                        icon: Icons.apartment_outlined,
                        label: 'Department',
                        value: p.department,
                      ),
                      const Divider(),
                      InfoRow(
                        icon: Icons.mail_outline_rounded,
                        label: 'Official email',
                        value: p.email,
                      ),
                      const Divider(),
                      InfoRow(icon: Icons.phone_outlined, label: 'Mobile', value: p.phone),
                    ],
                  ),
                ),
                const SectionHeader('Security'),
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Column(
                    children: [
                      InfoRow(
                        icon: Icons.smartphone_rounded,
                        label: 'Registered phone',
                        value: device == null
                            ? 'Not registered'
                            : '${device['device_model'] ?? 'Phone'} · since '
                                  '${Fmt.shortDate(Fmt.parse(device['registered_at']) ?? DateTime.now())}',
                      ),
                      const Divider(),
                      InfoRow(
                        icon: Icons.face_retouching_natural,
                        label: 'Face enrollment',
                        value: faceStatus == null ? 'Not enrolled' : 'Signature only (no photo)',
                        trailing: faceStatus == null
                            ? null
                            : StatusChip.tone(
                                faceStatus == 'approved' ? 'Approved' : faceStatus,
                                faceStatus == 'approved' ? AppColors.success : AppColors.warning,
                                dense: true,
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const MessageBanner(
                  icon: Icons.phonelink_setup_rounded,
                  message:
                      'Changed your phone? Ask the administrator to reset your registered '
                      'phone, then sign in on the new one.',
                ),
                const SectionHeader('About'),
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Column(
                    children: [
                      InfoRow(
                        icon: Icons.school_outlined,
                        label: 'Institution',
                        value: AppConfig.collegeName,
                      ),
                      const Divider(),
                      InfoRow(
                        icon: Icons.info_outline_rounded,
                        label: 'App version',
                        value: version,
                      ),
                      const Divider(),
                      const InfoRow(
                        icon: Icons.privacy_tip_outlined,
                        label: 'Privacy',
                        value: 'Photos never leave your phone',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.errorSoft, width: 1.5),
                  ),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out'),
                  onPressed: () => _signOut(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppText.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
