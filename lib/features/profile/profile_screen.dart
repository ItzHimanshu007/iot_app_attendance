import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../auth/controllers/auth_controller.dart';
import '../../shared/widgets/app_widgets.dart';


/// Profile screen — displays user profile and account metadata.
///
/// Reads from [currentUserProvider]. Shows loading shimmer while
/// the auth controller fetches the profile from the backend.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final profile = authState.profile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Refresh Profile',
            onPressed: () =>
                ref.read(authControllerProvider.notifier).refreshProfile(),
          ),
        ],
      ),
      body: authState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : profile == null
              ? ErrorDisplay(
                  message: 'Could not load profile',
                  onRetry: () => ref
                      .read(authControllerProvider.notifier)
                      .refreshProfile(),
                )
              : _ProfileBody(profile: profile),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.profile});

  final dynamic profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 8),

          // ── Avatar Card ─────────────────────────────────────────────
          _AvatarCard(profile: profile),

          const SizedBox(height: 24),

          // ── Account Info ────────────────────────────────────────────
          _SectionHeader('Account Information'),
          const SizedBox(height: 12),
          _InfoCard(children: [
            _InfoTile(
              icon: Icons.person_outline,
              label: 'Full Name',
              value: profile.fullName,
            ),
            _InfoTile(
              icon: Icons.email_outlined,
              label: 'Email',
              value: profile.email.isNotEmpty ? profile.email : '—',
            ),
            _InfoTile(
              icon: Icons.badge_outlined,
              label: 'Role',
              value: profile.roleLabel,
              valueWidget: _RoleBadge(role: profile.role),
            ),
            if (profile.department != null)
              _InfoTile(
                icon: Icons.business_outlined,
                label: 'Department',
                value: profile.department!,
              ),
            if (profile.studentIdNumber != null)
              _InfoTile(
                icon: Icons.numbers_outlined,
                label: 'Student ID',
                value: profile.studentIdNumber!,
              ),
            if (profile.phone != null)
              _InfoTile(
                icon: Icons.phone_outlined,
                label: 'Phone',
                value: profile.phone!,
              ),
          ]),

          const SizedBox(height: 24),

          // ── Account Metadata ────────────────────────────────────────
          _SectionHeader('Account Details'),
          const SizedBox(height: 12),
          _InfoCard(children: [
            _InfoTile(
              icon: Icons.fingerprint_outlined,
              label: 'User ID',
              value: profile.id,
              isMonospace: true,
            ),
            _InfoTile(
              icon: Icons.check_circle_outline,
              label: 'Account Status',
              value: profile.isActive ? 'Active' : 'Inactive',
              valueColor:
                  profile.isActive ? AppColors.success : AppColors.error,
            ),
            _InfoTile(
              icon: Icons.calendar_today_outlined,
              label: 'Member Since',
              value: _formatDate(profile.createdAt),
            ),
          ]),

          const SizedBox(height: 32),

          // ── Sign Out ────────────────────────────────────────────────
          _SignOutButton(),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

class _AvatarCard extends StatelessWidget {
  const _AvatarCard({required this.profile});
  final dynamic profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          // Avatar circle
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.5), width: 2),
            ),
            child: Center(
              child: Text(
                profile.initials,
                style: AppTypography.headlineLarge
                    .copyWith(color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            profile.fullName,
            style: AppTypography.headlineMedium
                .copyWith(color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            profile.email,
            style: AppTypography.bodyMedium
                .copyWith(color: Colors.white.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 12),
          _RoleBadge(role: profile.role, dark: false),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role, this.dark = true});
  final String role;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final color = _colorForRole(role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: dark ? color.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: dark ? color.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        _labelForRole(role),
        style: AppTypography.labelSmall.copyWith(
          color: dark ? color : Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Color _colorForRole(String role) {
    switch (role) {
      case 'teacher':
        return AppColors.secondary;
      case 'admin':
        return AppColors.warning;
      default:
        return AppColors.primary;
    }
  }

  String _labelForRole(String role) {
    switch (role) {
      case 'teacher':
        return '📚 TEACHER';
      case 'admin':
        return '🛡️ ADMIN';
      default:
        return '🎓 STUDENT';
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(title, style: AppTypography.headlineSmall),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: children.indexed
            .expand((item) => [
                  item.$2,
                  if (item.$1 < children.length - 1)
                    const Divider(height: 1, indent: 56),
                ])
            .toList(),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.valueWidget,
    this.valueColor,
    this.isMonospace = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? valueWidget;
  final Color? valueColor;
  final bool isMonospace;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.primarySurface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
      title: Text(label, style: AppTypography.labelMedium),
      subtitle: valueWidget ??
          Text(
            value,
            style: isMonospace
                ? AppTypography.bodySmall.copyWith(
                    fontFamily: 'monospace',
                    color: valueColor,
                  )
                : AppTypography.bodyMedium.copyWith(color: valueColor),
          ),
    );
  }
}

class _SignOutButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoading = ref.watch(authControllerProvider).isLoading;

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: isLoading
            ? null
            : () => _confirmSignOut(context, ref),
        icon: Icon(
          Icons.logout_rounded,
          color: isLoading ? AppColors.textTertiary : AppColors.error,
        ),
        label: Text(
          'Sign Out',
          style: TextStyle(
            color: isLoading ? AppColors.textTertiary : AppColors.error,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: isLoading
                ? AppColors.border
                : AppColors.error.withValues(alpha: 0.5),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }
}
