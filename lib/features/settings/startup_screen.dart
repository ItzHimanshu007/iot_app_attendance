import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/startup_validator.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../routes/app_router.dart';

/// Startup screen — shown while validating configuration + connectivity.
///
/// On success → navigates to login (GoRouter handles auth state).
/// On critical failure → shows actionable error with retry.
class StartupScreen extends ConsumerStatefulWidget {
  const StartupScreen({super.key});

  @override
  ConsumerState<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends ConsumerState<StartupScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation =
        Tween<double>(begin: 0.85, end: 1.0).animate(_pulseController);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final validationAsync = ref.watch(startupValidationProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: validationAsync.when(
          loading: () => _buildLoadingBody(),
          data: (validation) {
            if (!validation.canProceed) {
              return _buildCriticalError(validation);
            }
            // Passed — navigate, GoRouter will take over from auth state
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) context.go(RoutePaths.login);
            });
            return _buildLoadingBody();
          },
          error: (e, _) => _buildCriticalError(null, fallbackError: '$e'),
        ),
      ),
    );
  }

  Widget _buildLoadingBody() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Logo pulse
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(Icons.wifi_tethering_rounded,
                  color: Colors.white, size: 44),
            ),
          ),
          const SizedBox(height: 28),
          Text('Smart Campus', style: AppTypography.headlineLarge),
          const SizedBox(height: 8),
          Text('Attendance System',
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 48),
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Checking configuration…',
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildCriticalError(StartupValidation? validation,
      {String? fallbackError}) {
    final message = validation?.criticalError ?? fallbackError ?? 'Unknown error';
    final checks = validation?.checks ?? [];

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.errorSurface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.error_outline,
                  color: AppColors.error, size: 40),
            ),
            const SizedBox(height: 20),
            Text('Cannot Start App',
                style: AppTypography.headlineMedium
                    .copyWith(color: AppColors.error),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              message,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),

            if (checks.isNotEmpty) ...[
              const SizedBox(height: 20),
              ...checks.map((c) => _CheckRow(check: c)),
            ],

            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () => ref.invalidate(startupValidationProvider),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),

            const SizedBox(height: 12),
            Text(
              'Edit lib/core/env.dart to configure your Supabase project.',
              style: AppTypography.labelSmall
                  .copyWith(color: AppColors.textTertiary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check});
  final StartupCheckResult check;

  @override
  Widget build(BuildContext context) {
    final color = check.passed
        ? AppColors.success
        : check.isCritical
            ? AppColors.error
            : AppColors.warning;
    final icon = check.passed
        ? Icons.check_circle_outline
        : check.isCritical
            ? Icons.cancel_outlined
            : Icons.warning_amber_outlined;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(check.name,
              style:
                  AppTypography.bodySmall.copyWith(color: color)),
        ],
      ),
    );
  }
}
