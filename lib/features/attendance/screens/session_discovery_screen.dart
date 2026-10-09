import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../routes/app_router.dart';
import '../models/ble_models.dart';
import '../services/ble_token_source.dart';

// ── Discovery State ────────────────────────────────────────────────────────────

sealed class _DiscoveryState {}

class _DiscoveryIdle extends _DiscoveryState {}

class _DiscoveryLoading extends _DiscoveryState {}

class _DiscoveryFound extends _DiscoveryState {
  _DiscoveryFound(this.advertisement);
  final AttendanceSessionAdvertisement advertisement;
}

class _DiscoveryEmpty extends _DiscoveryState {}

class _DiscoveryError extends _DiscoveryState {
  _DiscoveryError(this.message);
  final String message;
}

// ── Screen ─────────────────────────────────────────────────────────────────────

/// Session Discovery Screen — finds nearby attendance sessions.
///
/// Uses [BleAttendanceTokenSource] via [tokenSourceProvider] to scan for
/// the nearest ESP32 BLE beacon and retrieve the attendance token.
///
/// Navigation to [AttendanceSubmissionScreen] passes [preloadedAdvertisement],
/// bypassing any additional BLE scan inside that screen.
class SessionDiscoveryScreen extends ConsumerStatefulWidget {
  const SessionDiscoveryScreen({super.key});

  @override
  ConsumerState<SessionDiscoveryScreen> createState() =>
      _SessionDiscoveryScreenState();
}

class _SessionDiscoveryScreenState
    extends ConsumerState<SessionDiscoveryScreen> {
  _DiscoveryState _state = _DiscoveryIdle();

  @override
  void initState() {
    super.initState();
    // Auto-start discovery when screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) => _discover());
  }

  // ── Discovery ──────────────────────────────────────────────────────────────

  Future<void> _discover() async {
    if (!mounted) return;
    setState(() => _state = _DiscoveryLoading());

    try {
      final source = ref.read(tokenSourceProvider);
      final advertisement = await source.discoverSession();
      if (!mounted) return;

      if (advertisement == null) {
        setState(() => _state = _DiscoveryEmpty());
      } else {
        setState(() => _state = _DiscoveryFound(advertisement));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _state = _DiscoveryError(e.toString()));
    }
  }

  void _navigateToSubmission(AttendanceSessionAdvertisement ad) {
    context.push(RoutePaths.attendanceSubmission, extra: ad);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find Session'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (_state is _DiscoveryLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Scan Again',
              onPressed: _discover,
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _discover,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final state = _state;

    return switch (state) {
      _DiscoveryIdle() => _buildIdle(),
      _DiscoveryLoading() => _buildLoading(),
      _DiscoveryFound(advertisement: final ad) => _buildFound(ad),
      _DiscoveryEmpty() => _buildEmpty(),
      _DiscoveryError(message: final msg) => _buildError(msg),
    };
  }

  // ── State Widgets ──────────────────────────────────────────────────────────

  Widget _buildIdle() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            Icon(
              Icons.wifi_tethering_outlined,
              size: 64,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text('Ready', style: AppTypography.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Tap refresh to search for an active session.',
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _discover,
              icon: const Icon(Icons.search_rounded),
              label: const Text('Find Session'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            const SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 24),
            Text('Searching for sessions…', style: AppTypography.titleSmall),
            const SizedBox(height: 8),
            Text(
              'Scanning for nearby BLE beacons…',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFound(AttendanceSessionAdvertisement ad) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle_outline,
                size: 18, color: AppColors.success),
            const SizedBox(width: 6),
            Text(
              'Session Found',
              style: AppTypography.labelMedium
                  .copyWith(color: AppColors.success),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Session card
        _SessionDiscoveredCard(
          advertisement: ad,
          onTap: () => _navigateToSubmission(ad),
        ),

        const SizedBox(height: 24),

        Center(
          child: OutlinedButton.icon(
            onPressed: _discover,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Search Again'),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.textTertiary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.search_off_rounded,
                size: 48,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 20),
            Text('No Session Found', style: AppTypography.titleMedium),
            const SizedBox(height: 8),
            Text(
              'There are no active attendance sessions right now.\n'
              'Ask your teacher to start a session.',
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _discover,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.errorSurface,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 20),
            Text('Discovery Failed', style: AppTypography.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _discover,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Session Discovered Card ────────────────────────────────────────────────────

class _SessionDiscoveredCard extends StatelessWidget {
  const _SessionDiscoveredCard({
    required this.advertisement,
    required this.onTap,
  });

  final AttendanceSessionAdvertisement advertisement;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final signal = advertisement.signalStrength;

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
        onTap: onTap,
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
                        Text(
                          'Classroom ${advertisement.classroomId}',
                          style: AppTypography.titleMedium,
                        ),
                        Text(
                          advertisement.deviceName,
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  _SignalBadge(signal: signal, rssi: advertisement.rssi),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _InfoChip(
                    icon: Icons.token_outlined,
                    label: 'Token',
                    value: advertisement.token.length >= 6
                        ? '${advertisement.token.substring(0, 6)}…'
                        : advertisement.token,
                  ),
                  _InfoChip(
                    icon: Icons.signal_wifi_4_bar_rounded,
                    label: 'Signal',
                    value: '${advertisement.rssi} dBm',
                  ),
                  _InfoChip(
                    icon: Icons.access_time_rounded,
                    label: 'Age',
                    value: 'Now',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onTap,
                  icon: const Icon(Icons.how_to_reg_rounded),
                  label: const Text('Mark Attendance'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignalBadge extends StatelessWidget {
  const _SignalBadge({required this.signal, required this.rssi});
  final SignalStrength signal;
  final int rssi;

  Color get _color => switch (signal) {
        SignalStrength.excellent => AppColors.success,
        SignalStrength.good => AppColors.info,
        SignalStrength.fair => AppColors.warning,
        SignalStrength.weak => AppColors.error,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      child: Text(
        signal.label,
        style: AppTypography.labelSmall.copyWith(color: _color),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(height: 2),
        Text(label,
            style:
                AppTypography.labelSmall.copyWith(color: AppColors.textTertiary)),
        Text(value,
            style: AppTypography.labelMedium
                .copyWith(color: AppColors.textPrimary)),
      ],
    );
  }
}
