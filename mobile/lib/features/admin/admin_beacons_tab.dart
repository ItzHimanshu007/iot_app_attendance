import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../shared/widgets.dart';
import 'admin_api.dart';

/// ESP32 beacons and their firmware configuration.
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
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add beacon', style: AppText.button),
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
              icon: Icons.settings_input_antenna_rounded,
              title: 'No beacons yet',
              subtitle:
                  'Add a beacon, then flash an ESP32 with its firmware config. '
                  'Place it in the staff room or a department office.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _beaconCard(rows[i]),
          );
        },
      ),
    );
  }

  Widget _beaconCard(Json b) {
    final active = b['is_active'] == true;
    final lastUsed = Fmt.parse(b['last_used_at']);
    return AppCard(
      onTap: () => _actions(b),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          IconBadge(
            Icons.settings_input_antenna_rounded,
            color: active ? AppColors.primary : AppColors.textTertiary,
            size: 46,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(b['name'] as String? ?? '', style: AppText.h3),
                Text(b['location'] as String? ?? 'Location not set', style: AppText.caption),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    StatusChip.tone(
                      active ? 'Active' : 'Disabled',
                      active ? AppColors.success : AppColors.error,
                      dense: true,
                    ),
                    StatusChip.tone(
                      '≥ ${b['rssi_threshold']} dBm',
                      AppColors.primary,
                      icon: Icons.network_cell_rounded,
                      dense: true,
                    ),
                    StatusChip.tone(
                      lastUsed == null ? 'Never used' : 'Used ${Fmt.shortDate(lastUsed)}',
                      AppColors.notMarked,
                      icon: Icons.history_rounded,
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

  Future<void> _create() async {
    final created = await showModalBottomSheet<Json>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CreateBeaconSheet(),
    );
    if (created == null) return;
    _reload();
    if (mounted) await _showFirmware(created);
  }

  Future<void> _actions(Json b) async {
    final id = b['id'] as String;
    final active = b['is_active'] == true;
    final api = ref.read(adminApiProvider);
    Widget item(BuildContext ctx, String v, IconData icon, String title, String hint) => ListTile(
      leading: IconBadge(icon, size: 40),
      title: Text(title),
      subtitle: Text(hint),
      onTap: () => Navigator.pop(ctx, v),
    );
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(b['name'] as String? ?? '', style: AppText.h3),
              subtitle: Text(id, style: AppText.caption.copyWith(fontFamily: 'monospace')),
            ),
            const Divider(),
            item(
              ctx,
              'firmware',
              Icons.memory_rounded,
              'Firmware config',
              'Beacon ID and secret for secrets.h',
            ),
            item(
              ctx,
              'toggle',
              active ? Icons.toggle_off_outlined : Icons.toggle_on_outlined,
              active ? 'Disable beacon' : 'Enable beacon',
              active ? 'Stops accepting this beacon' : 'Accept this beacon again',
            ),
            item(ctx, 'rotate', Icons.key_rounded, 'Rotate secret', 'You must re-flash the ESP32'),
            const SizedBox(height: 8),
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
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Firmware config', style: AppText.h2),
              const SizedBox(height: 6),
              const Text(
                'Paste into firmware/staff_beacon/secrets.h, set your Wi-Fi name and password, '
                'then flash the ESP32. Keep the secret private.',
                style: AppText.body,
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SelectableText(
                  config,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    height: 1.5,
                    color: Color(0xFF86EFAC),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Copy to clipboard',
                icon: Icons.copy_rounded,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: config));
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) showSnack(context, 'Copied');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateBeaconSheet extends ConsumerStatefulWidget {
  const _CreateBeaconSheet();

  @override
  ConsumerState<_CreateBeaconSheet> createState() => _CreateBeaconSheetState();
}

class _CreateBeaconSheetState extends ConsumerState<_CreateBeaconSheet> {
  final _name = TextEditingController();
  final _location = TextEditingController();
  double _rssi = -85;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_name.text.trim().length < 2) {
      showSnack(context, 'Enter a beacon name', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final created = await ref
          .read(adminApiProvider)
          .createBeacon(_name.text.trim(), _location.text.trim(), _rssi.round());
      if (mounted) Navigator.pop(context, created);
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final range = _rssi >= -70
        ? 'same room'
        : _rssi >= -85
        ? '≈ 10–20 m indoors'
        : 'large area';
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Add beacon', style: AppText.h2),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Staff Room – Block A',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _location,
            decoration: const InputDecoration(labelText: 'Where is it placed?'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(child: Text('Minimum signal', style: AppText.bodyStrong)),
              Text('${_rssi.round()} dBm · $range', style: AppText.caption),
            ],
          ),
          Slider(
            value: _rssi,
            min: -100,
            max: -55,
            divisions: 45,
            onChanged: (v) => setState(() => _rssi = v),
          ),
          const SizedBox(height: 8),
          PrimaryButton(
            label: 'Create beacon',
            icon: Icons.add_rounded,
            busy: _busy,
            onPressed: _create,
          ),
        ],
      ),
    );
  }
}
