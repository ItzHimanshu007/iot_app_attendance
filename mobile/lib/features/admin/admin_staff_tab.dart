import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/theme/colors.dart';
import '../../shared/widgets.dart';
import '../auth/session.dart';
import 'admin_api.dart';

/// Staff list with approve / reset / disable actions.
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

  static const _stepLabels = {
    'register_device': 'Needs to bind phone',
    'enroll_face': 'Needs to enroll face',
    'await_approval': 'Waiting for approval',
    'ready': 'Ready',
    'disabled': 'Disabled',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search name, email or employee ID',
              prefixIcon: Icon(Icons.search),
            ),
            onSubmitted: (v) {
              _query = v.trim();
              _reload();
            },
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              for (final entry in const {
                'pending': 'Pending',
                'active': 'Active',
                'disabled': 'Disabled',
                null: 'All',
              }.entries)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: ChoiceChip(
                    label: Text(entry.value),
                    selected: _status == entry.key,
                    onSelected: (_) {
                      _status = entry.key;
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
                return const EmptyState(icon: Icons.people_outline, title: 'Nobody here');
              }
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  itemBuilder: (_, i) => _tile(rows[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _tile(Json s) {
    final device = (s['device'] as Map?)?.cast<String, dynamic>();
    final face = (s['face'] as Map?)?.cast<String, dynamic>();
    final step = s['next_step'] as String? ?? '';
    final ready = step == 'ready';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text('${s['full_name']}${s['role'] == 'admin' ? '  (admin)' : ''}'),
        subtitle: Text(
          '${s['employee_id'] ?? '—'} · ${s['department'] ?? ''}\n'
          'Phone: ${device?['device_model'] ?? 'not bound'} · Face: ${face?['status'] ?? 'none'}',
        ),
        isThreeLine: true,
        trailing: StatusBadge(
          label: _stepLabels[step] ?? step,
          color: ready
              ? AppColors.success
              : step == 'await_approval'
              ? AppColors.warning
              : AppColors.textTertiary,
        ),
        onTap: () => _actions(s),
      ),
    );
  }

  Future<void> _actions(Json s) async {
    final id = s['id'] as String;
    final myId = ref.read(meProvider).value?.profile.id;
    final face = (s['face'] as Map?)?.cast<String, dynamic>();
    final active = s['status'] == 'active';
    final isAdmin = s['role'] == 'admin';
    final api = ref.read(adminApiProvider);

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(s['full_name'] as String? ?? ''),
              subtitle: Text(s['email'] as String? ?? ''),
            ),
            if (!active || face?['status'] == 'pending')
              _sheetItem(
                ctx,
                'approve',
                Icons.verified,
                'Approve account & face',
                AppColors.success,
              ),
            if (face != null && face['status'] != 'rejected')
              _sheetItem(ctx, 'reject', Icons.face_retouching_off, 'Ask to re-enroll face'),
            if (face != null)
              _sheetItem(ctx, 'reset_face', Icons.delete_outline, 'Delete face data'),
            if (s['device'] != null)
              _sheetItem(ctx, 'reset_device', Icons.phonelink_erase, 'Reset bound phone'),
            if (id != myId) ...[
              _sheetItem(
                ctx,
                active ? 'disable' : 'enable',
                active ? Icons.block : Icons.check,
                active ? 'Disable account' : 'Enable account',
                active ? AppColors.error : null,
              ),
              _sheetItem(
                ctx,
                isAdmin ? 'demote' : 'promote',
                Icons.admin_panel_settings,
                isAdmin ? 'Remove admin role' : 'Make admin',
              ),
            ],
          ],
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
      if (mounted) showSnack(context, 'Done');
      if (id == myId) ref.read(meProvider.notifier).reload();
      _reload();
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  Widget _sheetItem(BuildContext ctx, String value, IconData icon, String label, [Color? color]) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color)),
      onTap: () => Navigator.pop(ctx, value),
    );
  }
}
