import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../shared/widgets.dart';
import '../auth/auth_service.dart';
import '../auth/session.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider).value;
    if (me == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final p = me.profile;
    final device = me.device;

    Widget row(IconData icon, String label, String? value) => ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(value == null || value.isEmpty ? '—' : value),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: CircleAvatar(
              radius: 40,
              child: Text(p.initials, style: const TextStyle(fontSize: 26)),
            ),
          ),
          const SizedBox(height: 12),
          Center(child: Text(p.fullName, style: Theme.of(context).textTheme.titleLarge)),
          Center(child: Text(p.email, style: Theme.of(context).textTheme.bodyMedium)),
          const SizedBox(height: 8),
          Center(
            child: Wrap(
              spacing: 8,
              children: [
                StatusBadge(
                  label: p.isAdmin ? 'Admin' : 'Staff',
                  color: Theme.of(context).colorScheme.primary,
                ),
                StatusBadge(label: p.status, color: p.isActive ? Colors.green : Colors.orange),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                row(Icons.badge_outlined, 'Employee ID', p.employeeId),
                row(Icons.apartment_outlined, 'Department', p.department),
                row(Icons.work_outline, 'Designation', p.designation),
                row(Icons.phone_outlined, 'Phone', p.phone),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                row(
                  Icons.phone_android,
                  'Bound phone',
                  device == null
                      ? null
                      : '${device['device_model'] ?? ''} · ${device['os_version'] ?? ''}',
                ),
                row(
                  Icons.event_available,
                  'Bound since',
                  device == null
                      ? null
                      : Fmt.date(Fmt.parse(device['registered_at']) ?? DateTime.now()),
                ),
                row(Icons.face_retouching_natural, 'Face enrollment', me.onboarding.faceStatus),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Changed phones? Ask an admin to reset your device, then sign in on the new phone.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
            onPressed: () async {
              await ref.read(authServiceProvider).signOut();
              if (context.mounted) context.go('/');
            },
          ),
        ],
      ),
    );
  }
}
