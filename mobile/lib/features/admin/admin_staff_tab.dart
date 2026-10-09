import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../shared/widgets.dart';
import '../auth/session.dart';
import 'admin_api.dart';

/// Staff directory with approval / reset / disable actions.
class StaffTab extends ConsumerStatefulWidget {
  const StaffTab({super.key});

  @override
  ConsumerState<StaffTab> createState() => _StaffTabState();
}

class _StaffTabState extends ConsumerState<StaffTab> {
  String? _status = 'pending';
  String _query = '';
  late Future<List<Json>> _future = _load();

  Future<List<Json>> _load() => ref.read(adminApiProvider).staff(status: _status, query: _query);
  void _reload() => setState(() => _future = _load());

  static const _filters = {
    'pending': 'Pending',
    'active': 'Active',
    'disabled': 'Disabled',
    null: 'All',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: TextField(
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: 'Search by name, email or employee ID',
              prefixIcon: Icon(Icons.search_rounded),
              contentPadding: EdgeInsets.symmetric(vertical: 12),
            ),
            onSubmitted: (v) {
              _query = v.trim();
              _reload();
            },
          ),
        ),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final e in _filters.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: ChoiceChip(
                    label: Text(e.value),
                    selected: _status == e.key,
                    onSelected: (_) {
                      _status = e.key;
                      _reload();
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Json>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return ErrorView(message: errorMessage(snap.error!), onRetry: _reload);
              }
              final rows = snap.data!;
              if (rows.isEmpty) {
                return EmptyState(
                  icon: Icons.groups_outlined,
                  title: _status == 'pending' ? 'No pending approvals' : 'No staff found',
                  subtitle: _status == 'pending'
                      ? 'New sign-ups appear here once they register their phone and face.'
                      : null,
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _StaffCard(staff: rows[i], onTap: () => _actions(rows[i])),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _actions(Json s) async {
    final id = s['id'] as String;
    final myId = ref.read(meProvider).value?.profile.id;
    final face = (s['face'] as Map?)?.cast<String, dynamic>();
    final active = s['status'] == 'active';
    final isAdmin = s['role'] == 'admin';
    final api = ref.read(adminApiProvider);

    Widget item(
      BuildContext ctx,
      String value,
      IconData icon,
      String label,
      String hint, [
      Color color = AppColors.primary,
    ]) => ListTile(
      leading: IconBadge(icon, color: color, size: 40),
      title: Text(
        label,
        style: AppText.bodyStrong.copyWith(color: color == AppColors.error ? color : null),
      ),
      subtitle: Text(hint),
      onTap: () => Navigator.pop(ctx, value),
    );

    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Avatar(_initials(s['full_name'] as String? ?? '')),
                title: Text(s['full_name'] as String? ?? '', style: AppText.h3),
                subtitle: Text('${s['email'] ?? ''}'),
              ),
              const Divider(),
              if (!active || face?['status'] == 'pending')
                item(
                  ctx,
                  'approve',
                  Icons.verified_rounded,
                  'Approve account',
                  'Activate the account and approve the enrolled face',
                  AppColors.success,
                ),
              if (face != null && face['status'] != 'rejected')
                item(
                  ctx,
                  'reject',
                  Icons.face_retouching_off,
                  'Ask to re-enroll face',
                  'Use when the enrollment photo conditions were poor',
                  AppColors.warning,
                ),
              if (s['device'] != null)
                item(
                  ctx,
                  'reset_device',
                  Icons.phonelink_erase_rounded,
                  'Reset registered phone',
                  'Lets the staff member register a new phone',
                ),
              if (face != null)
                item(
                  ctx,
                  'reset_face',
                  Icons.delete_outline_rounded,
                  'Delete face data',
                  'The staff member must enroll again',
                  AppColors.warning,
                ),
              if (id != myId) ...[
                item(
                  ctx,
                  isAdmin ? 'demote' : 'promote',
                  Icons.admin_panel_settings_outlined,
                  isAdmin ? 'Remove admin role' : 'Make administrator',
                  isAdmin ? 'Back to a regular staff account' : 'Full access to this console',
                ),
                item(
                  ctx,
                  active ? 'disable' : 'enable',
                  active ? Icons.block_rounded : Icons.check_circle_outline,
                  active ? 'Disable account' : 'Enable account',
                  active ? 'Blocks sign-in and attendance' : 'Restore access',
                  active ? AppColors.error : AppColors.success,
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;

    try {
      switch (action) {
        case 'approve':
          await api.approve(id);
        case 'reject':
          await api.rejectFace(id, null);
        case 'reset_face':
          await api.resetFace(id);
        case 'reset_device':
          await api.resetDevice(id);
        case 'disable':
          await api.setStatus(id, 'disabled');
        case 'enable':
          await api.setStatus(id, 'active');
        case 'promote':
          await api.setRole(id, 'admin');
        case 'demote':
          await api.setRole(id, 'staff');
      }
      if (mounted) showSnack(context, 'Updated');
      if (id == myId) ref.read(meProvider.notifier).reload();
      _reload();
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    }
  }
}

String _initials(String name) => Fmt.initials(name);

class _StaffCard extends StatelessWidget {
  const _StaffCard({required this.staff, required this.onTap});

  final Json staff;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = staff;
    final device = (s['device'] as Map?)?.cast<String, dynamic>();
    final face = (s['face'] as Map?)?.cast<String, dynamic>();
    final step = s['next_step'] as String? ?? '';
    final (label, color) = switch (step) {
      'ready' => ('Active', AppColors.success),
      'await_approval' => ('Needs approval', AppColors.warning),
      'enroll_face' => ('Setting up', AppColors.notMarked),
      'register_device' => ('Setting up', AppColors.notMarked),
      'disabled' => ('Disabled', AppColors.error),
      _ => (step, AppColors.notMarked),
    };
    final faceStatus = face?['status'] as String?;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Avatar(_initials(s['full_name'] as String? ?? ''), size: 46),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        s['full_name'] as String? ?? '',
                        style: AppText.h3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (s['role'] == 'admin') ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.shield_rounded, size: 15, color: AppColors.gold),
                    ],
                  ],
                ),
                Text(
                  [s['employee_id'], s['department']].whereType<String>().join(' · '),
                  style: AppText.caption,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    StatusChip.tone(label, color, dense: true),
                    StatusChip.tone(
                      device == null ? 'No phone yet' : '${device['device_model'] ?? 'Phone'}',
                      device == null ? AppColors.notMarked : AppColors.primary,
                      icon: Icons.smartphone_rounded,
                      dense: true,
                    ),
                    StatusChip.tone(
                      faceStatus == null ? 'No face yet' : 'Face $faceStatus',
                      faceStatus == 'approved'
                          ? AppColors.success
                          : faceStatus == null
                          ? AppColors.notMarked
                          : AppColors.warning,
                      icon: Icons.face_rounded,
                      dense: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
        ],
      ),
    );
  }
}
