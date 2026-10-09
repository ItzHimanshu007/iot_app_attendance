import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/env.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../routes/app_router.dart';
import '../../services/connectivity_service.dart';
import '../auth/controllers/auth_controller.dart';
import 'diagnostics_screen.dart';

/// Settings screen — app preferences, connectivity, about, and diagnostics.
///
/// Long-press on the Settings app bar title → opens [DiagnosticsScreen].
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProvider);
    final connectivity = ref.watch(connectivityStreamProvider);

    void openDiagnostics() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const DiagnosticsScreen(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onLongPress: openDiagnostics,
          child: const Text('Settings'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Account ──────────────────────────────────────────────────────
          if (profile != null) ...[
            Text('Account', style: AppTypography.headlineSmall),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.primarySurface,
                  child: Text(
                    profile.fullName.isNotEmpty
                        ? profile.fullName[0].toUpperCase()
                        : '?',
                    style: AppTypography.titleMedium
                        .copyWith(color: AppColors.primary),
                  ),
                ),
                title: Text(profile.fullName),
                subtitle: Text(profile.email),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    profile.role.toUpperCase(),
                    style: AppTypography.labelSmall
                        .copyWith(color: AppColors.primary),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // ── Preferences ──────────────────────────────────────────────────
          Text('Preferences', style: AppTypography.headlineSmall),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Dark Mode'),
                  subtitle: const Text('Switch between light and dark themes'),
                  value: Theme.of(context).brightness == Brightness.dark,
                  onChanged: (_) {},
                  secondary: const Icon(Icons.dark_mode_outlined),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Notifications'),
                  subtitle: const Text('Receive attendance alerts'),
                  value: true,
                  onChanged: (_) {},
                  secondary: const Icon(Icons.notifications_outlined),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Connection ───────────────────────────────────────────────────
          Text('Connection', style: AppTypography.headlineSmall),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                // Network status
                connectivity.when(
                  data: (online) => ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: online
                            ? AppColors.successSurface
                            : AppColors.errorSurface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        online
                            ? Icons.wifi_rounded
                            : Icons.wifi_off_rounded,
                        color: online
                            ? AppColors.success
                            : AppColors.error,
                        size: 20,
                      ),
                    ),
                    title: Text(
                        online ? 'Connected' : 'No Internet Connection'),
                    subtitle: const Text('Network status'),
                    trailing: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: online
                            ? AppColors.success
                            : AppColors.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  loading: () => const ListTile(
                    title: Text('Checking network…'),
                    leading: SizedBox(
                      width: 36,
                      height: 36,
                      child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  ),
                  error: (_, __) => const ListTile(
                    title: Text('Network status unavailable'),
                    leading: Icon(Icons.error_outline),
                  ),
                ),

                const Divider(height: 1),

                // API Server
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Env.isApiConfigured
                          ? AppColors.successSurface
                          : AppColors.warningSurface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.cloud_outlined,
                        color: Env.isApiConfigured
                            ? AppColors.success
                            : AppColors.warning,
                        size: 20),
                  ),
                  title: const Text('API Server'),
                  subtitle: Text(AppConfig.apiBaseUrl,
                      style: AppTypography.bodySmall),
                ),

                const Divider(height: 1),

                // Supabase
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Env.isSupabaseConfigured
                          ? AppColors.successSurface
                          : AppColors.errorSurface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.storage_outlined,
                        color: Env.isSupabaseConfigured
                            ? AppColors.success
                            : AppColors.error,
                        size: 20),
                  ),
                  title: const Text('Supabase'),
                  subtitle: Text(
                    Env.isSupabaseConfigured
                        ? AppConfig.supabaseUrl
                        : 'Not configured — edit lib/core/env.dart',
                    style: AppTypography.bodySmall,
                  ),
                ),

                const Divider(height: 1),

                // BLE
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.infoSurface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.bluetooth,
                        color: AppColors.info, size: 20),
                  ),
                  title: const Text('BLE Scanner'),
                  subtitle: const Text('Attendance beacon discovery'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── About ────────────────────────────────────────────────────────
          Text('About', style: AppTypography.headlineSmall),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Version'),
                  subtitle: Text(
                      '${AppConfig.appVersion} (build ${AppConfig.buildNumber})'),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      AppConfig.env.toUpperCase(),
                      style: AppTypography.labelSmall
                          .copyWith(color: AppColors.primary),
                    ),
                  ),
                ),
                const Divider(height: 1),
                const ListTile(
                  title: Text('Architecture'),
                  subtitle: Text(
                      'Clean Architecture · Riverpod · GoRouter · Supabase'),
                ),
                const Divider(height: 1),
                ListTile(
                  title: Text(
                    AppConfig.isDebug
                        ? 'Developer: Long-press title for diagnostics'
                        : 'Smart Campus Attendance System',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textTertiary),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Danger Zone ──────────────────────────────────────────────────
          if (profile != null) ...[
            Text('Session', style: AppTypography.headlineSmall),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.errorSurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.logout,
                      color: AppColors.error, size: 20),
                ),
                title: const Text('Sign Out'),
                subtitle: const Text('Log out of your account'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _confirmLogout(context, ref),
              ),
            ),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out?'),
        content: const Text(
            'You will need to log in again to access the app.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(authControllerProvider.notifier).logout();
              context.go(RoutePaths.login);
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }
}
