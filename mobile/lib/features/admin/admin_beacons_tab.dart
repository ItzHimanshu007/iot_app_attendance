import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/theme/colors.dart';
import '../../shared/widgets.dart';
import 'admin_api.dart';

/// Manage ESP32 beacons and get the firmware config for each one.
class BeaconsTab extends ConsumerStatefulWidget {
  const BeaconsTab({super.key});

  @override
  ConsumerState<BeaconsTab> createState() => _BeaconsTabState();
}

class _BeaconsTabState extends ConsumerState<BeaconsTab> {
  late Future<List<Json>> _future = _load();

  Future<List<Json>> _load() => ref.read(adminApiProvider).beacons();
  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('Add beacon'),
      ),
      body: FutureBuilder<List<Json>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return ErrorView(message: errorMessage(snap.error!), onRetry: _reload);
          final rows = snap.data!;
          if (rows.isEmpty) {
            return const EmptyState(
              icon: Icons.bluetooth,
              title: 'No beacons yet',
              subtitle: 'Add one, then flash an ESP32 with its firmware config.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final b = rows[i];
              final active = b['is_active'] == true;
              final lastUsed = Fmt.parse(b['last_used_at']);
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(
                    Icons.bluetooth,
                    color: active ? AppColors.primary : AppColors.textTertiary,
                  ),
                  title: Text(b['name'] as String? ?? ''),
                  subtitle: Text(
                    '${b['location'] ?? 'No location'} · RSSI ≥ ${b['rssi_threshold']} dBm\n'
                    'Last used: ${lastUsed == null ? 'never' : '${Fmt.shortDate(lastUsed)} ${Fmt.time(lastUsed)}'}',
                  ),
                  isThreeLine: true,
                  trailing: active ? null : const StatusBadge(label: 'Off', color: AppColors.error),
                  onTap: () => _actions(b),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _create() async {
    final name = TextEditingController();
    final location = TextEditingController();
    var rssi = -85.0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add beacon'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name (e.g. Staff Room A)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: location,
                decoration: const InputDecoration(labelText: 'Where is it placed?'),
              ),
              const SizedBox(height: 10),
              Text('Minimum signal: ${rssi.round()} dBm'),
              Slider(
                value: rssi,
                min: -100,
                max: -55,
                divisions: 45,
                onChanged: (v) => setLocal(() => rssi = v),
              ),
              const Text('-85 ≈ 10–20 m indoors · -70 ≈ same room', style: TextStyle(fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, name.text.trim().length >= 2),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      final created = await ref
          .read(adminApiProvider)
          .createBeacon(name.text.trim(), location.text.trim(), rssi.round());
      _reload();
      if (mounted) await _showFirmware(created);
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  Future<void> _actions(Json b) async {
    final id = b['id'] as String;
    final active = b['is_active'] == true;
    final api = ref.read(adminApiProvider);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(b['name'] as String? ?? ''), subtitle: Text(id)),
            ListTile(
              leading: const Icon(Icons.memory),
              title: const Text('Firmware config (secret)'),
              onTap: () => Navigator.pop(ctx, 'firmware'),
            ),
            ListTile(
              leading: Icon(active ? Icons.toggle_off : Icons.toggle_on),
              title: Text(active ? 'Deactivate' : 'Activate'),
              onTap: () => Navigator.pop(ctx, 'toggle'),
            ),
            ListTile(
              leading: const Icon(Icons.key),
              title: const Text('Rotate secret (re-flash needed)'),
              onTap: () => Navigator.pop(ctx, 'rotate'),
            ),
          ],
        ),
      ),
    );
    if (action == null) return;
    try {
      switch (action) {
        case 'firmware':
          final secret = await api.beaconSecret(id);
          if (mounted) await _showFirmware(secret);
        case 'toggle':
          await api.updateBeacon(id, {'is_active': !active});
          _reload();
        case 'rotate':
          final rotated = await api.rotateBeaconSecret(id);
          if (mounted) await _showFirmware(rotated);
      }
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  Future<void> _showFirmware(Json beacon) {
    final config = beacon['firmware_config'] as String? ?? '';
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Firmware config'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Paste into firmware/staff_beacon/secrets.h, set your Wi-Fi, '
                'then flash the ESP32. Keep the secret private.',
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                color: const Color(0xFF111827),
                child: SelectableText(
                  config,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Colors.greenAccent,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: config));
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) showSnack(context, 'Copied');
            },
            child: const Text('Copy'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }
}
