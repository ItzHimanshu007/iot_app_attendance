import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/env.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../services/connectivity_service.dart';
import '../../services/secure_storage_service.dart';
import '../auth/controllers/auth_controller.dart';

/// Hidden developer diagnostics screen.
///
/// Access: Long-press on the Settings screen title.
/// Displays current configuration, auth state, BLE state, and network status.
class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  bool _isRefreshing = false;
  Map<String, String> _storageSnapshot = {};
  bool? _networkStatus;
  BluetoothAdapterState _bleState = BluetoothAdapterState.unknown;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);

    final storage = ref.read(secureStorageProvider);
    final connectivity = ref.read(connectivityServiceProvider);

    final results = await Future.wait([
      _readStorageSnapshot(storage),
      connectivity.isConnected,
      FlutterBluePlus.adapterState.first,
    ]);

    if (mounted) {
      setState(() {
        _storageSnapshot = results[0] as Map<String, String>;
        _networkStatus = results[1] as bool;
        _bleState = results[2] as BluetoothAdapterState;
        _isRefreshing = false;
      });
    }
  }

  Future<Map<String, String>> _readStorageSnapshot(
      SecureStorageService storage) async {
    final accessToken = await storage.getAccessToken();
    final userId = await storage.getUserId();
    final role = await storage.getUserRole();
    final deviceRegistered = await storage.isDeviceRegistered();
    final fingerprint = await storage.getDeviceFingerprint();

    return {
      'Access Token': accessToken != null
          ? '${accessToken.substring(0, 12)}… (${accessToken.length} chars)'
          : 'None',
      'User ID': userId ?? 'None',
      'Role': role ?? 'None',
      'Device Registered': deviceRegistered.toString(),
      'Device Fingerprint': fingerprint != null
          ? '${fingerprint.substring(0, 12)}…'
          : 'None',
    };
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final profile = authState.profile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        backgroundColor: AppColors.darkBackground,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isRefreshing ? null : _refresh,
          ),
        ],
      ),
      backgroundColor: AppColors.darkBackground,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Warning banner ──────────────────────────────────────────────
          _DiagnosticsBanner(),
          const SizedBox(height: 16),

          // ── Configuration ───────────────────────────────────────────────
          _DiagnosticsSection(
            title: 'Configuration',
            icon: Icons.settings_outlined,
            rows: [
              _DiagRow('Environment', AppConfig.env.toUpperCase()),
              _DiagRow('App Version',
                  '${AppConfig.appVersion} (${AppConfig.buildNumber})'),
              _DiagRow('Build Mode',
                  AppConfig.isDebug ? 'DEBUG' : 'RELEASE',
                  highlight: AppConfig.isDebug ? AppColors.warning : AppColors.success),
              _DiagRow('API URL', AppConfig.apiBaseUrl),
              _DiagRow('Supabase URL', AppConfig.supabaseUrl),
              _DiagRow(
                'Anon Key',
                AppConfig.supabaseAnonKey.isEmpty
                    ? 'NOT SET ⚠'
                    : '${AppConfig.supabaseAnonKey.substring(0, 12)}… (${AppConfig.supabaseAnonKey.length} chars)',
                highlight: AppConfig.supabaseAnonKey.isEmpty
                    ? AppColors.error
                    : AppColors.success,
              ),
              _DiagRow(
                'Config Status',
                Env.isFullyConfigured ? 'OK ✓' : 'INCOMPLETE ⚠',
                highlight: Env.isFullyConfigured
                    ? AppColors.success
                    : AppColors.error,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Auth State ──────────────────────────────────────────────────
          _DiagnosticsSection(
            title: 'Auth State',
            icon: Icons.lock_outline,
            rows: [
              _DiagRow('Status', authState.status.name.toUpperCase(),
                  highlight: authState.isAuthenticated
                      ? AppColors.success
                      : AppColors.warning),
              _DiagRow('User ID', profile?.id ?? 'None'),
              _DiagRow('Email', profile?.email ?? 'None'),
              _DiagRow('Role', profile?.role ?? 'None',
                  highlight: profile?.role != null
                      ? AppColors.info
                      : null),
              _DiagRow('Full Name', profile?.fullName ?? 'None'),
            ],
          ),
          const SizedBox(height: 12),

          // ── Token Storage ───────────────────────────────────────────────
          _DiagnosticsSection(
            title: 'Secure Storage',
            icon: Icons.storage_outlined,
            rows: _storageSnapshot.entries
                .map((e) => _DiagRow(e.key, e.value))
                .toList(),
          ),
          const SizedBox(height: 12),

          // ── Connectivity ────────────────────────────────────────────────
          _DiagnosticsSection(
            title: 'Connectivity',
            icon: Icons.wifi_outlined,
            rows: [
              _DiagRow(
                'Network',
                _networkStatus == null
                    ? 'Checking…'
                    : _networkStatus!
                        ? 'Online ✓'
                        : 'Offline ✗',
                highlight: _networkStatus == null
                    ? null
                    : _networkStatus!
                        ? AppColors.success
                        : AppColors.error,
              ),
              _DiagRow(
                'BLE Adapter',
                _bleState.name.toUpperCase(),
                highlight: _bleState == BluetoothAdapterState.on
                    ? AppColors.success
                    : AppColors.warning,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Actions ─────────────────────────────────────────────────────
          _DiagnosticsSection(
            title: 'Actions',
            icon: Icons.build_outlined,
            rows: [],
            child: Column(
              children: [
                _ActionButton(
                  label: 'Copy Config to Clipboard',
                  icon: Icons.copy_outlined,
                  onTap: () => _copyConfig(context),
                ),
                const SizedBox(height: 8),
                _ActionButton(
                  label: 'Clear All Secure Storage',
                  icon: Icons.delete_outline,
                  color: AppColors.error,
                  onTap: () => _clearStorage(context),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  void _copyConfig(BuildContext context) {
    final config = '''
=== Smart Campus Diagnostics ===
Environment : ${AppConfig.env.toUpperCase()}
App Version : ${AppConfig.appVersion}
API URL     : ${AppConfig.apiBaseUrl}
Supabase URL: ${AppConfig.supabaseUrl}
Anon Key    : ${AppConfig.supabaseAnonKey.isEmpty ? 'NOT SET' : 'SET (${AppConfig.supabaseAnonKey.length} chars)'}

=== Auth ===
Status  : ${ref.read(authControllerProvider).status}
User ID : ${ref.read(authControllerProvider).profile?.id ?? 'None'}
Role    : ${ref.read(authControllerProvider).profile?.role ?? 'None'}

=== Storage ===
${_storageSnapshot.entries.map((e) => '${e.key}: ${e.value}').join('\n')}

=== Network ===
Online: $_networkStatus
BLE   : $_bleState
''';

    Clipboard.setData(ClipboardData(text: config));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnostics copied to clipboard')),
    );
  }

  Future<void> _clearStorage(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Storage?'),
        content: const Text(
            'This will delete all stored tokens and device data. You will be logged out.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(secureStorageProvider).clearAll();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Storage cleared. Restarting…')),
        );
      }
      await ref.read(authControllerProvider.notifier).logout();
    }
  }
}

// ── Sub-Widgets ───────────────────────────────────────────────────────────────

class _DiagnosticsBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.warning, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Developer mode — do not share this screen in production.',
              style: AppTypography.labelSmall
                  .copyWith(color: AppColors.warning),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticsSection extends StatelessWidget {
  const _DiagnosticsSection({
    required this.title,
    required this.icon,
    required this.rows,
    this.child,
  });

  final String title;
  final IconData icon;
  final List<_DiagRow> rows;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: AppColors.textTertiary),
            const SizedBox(width: 6),
            Text(title,
                style: AppTypography.labelSmall
                    .copyWith(color: AppColors.textTertiary,
                        letterSpacing: 0.8)),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.darkSurface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              ...rows.asMap().entries.map((entry) {
                return Column(
                  children: [
                    _DiagRowWidget(entry.value),
                    if (entry.key < rows.length - 1 || child != null)
                      Divider(
                          height: 1,
                          color:
                              AppColors.darkBorder.withValues(alpha: 0.4)),
                  ],
                );
              }),
              if (child != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: child,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DiagRow {
  const _DiagRow(this.label, this.value, {this.highlight});
  final String label;
  final String value;
  final Color? highlight;
}

class _DiagRowWidget extends StatelessWidget {
  const _DiagRowWidget(this.row);
  final _DiagRow row;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              row.label,
              style: AppTypography.labelSmall
                  .copyWith(color: AppColors.darkTextSecondary),
            ),
          ),
          Expanded(
            child: Text(
              row.value,
              style: AppTypography.labelSmall.copyWith(
                color: row.highlight ?? AppColors.darkTextPrimary,
                fontFamily: 'monospace',
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.color,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primaryLight;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: c),
        label: Text(label, style: TextStyle(color: c)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: c.withValues(alpha: 0.4)),
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }
}
