import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../shared/widgets.dart';
import '../location/location_service.dart';
import 'admin_api.dart';

/// Campus rules (location, office hours, thresholds) + Excel export.
class SettingsTab extends ConsumerStatefulWidget {
  const SettingsTab({super.key});

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab> {
  final _name = TextEditingController();
  final _timezone = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final _radius = TextEditingController();
  final _accuracy = TextEditingController();
  final _grace = TextEditingController();
  String _mode = 'flag';
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0);
  double _threshold = 0.6;

  bool _loading = true;
  bool _saving = false;
  bool _exporting = false;
  String? _error;
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _timezone, _lat, _lng, _radius, _accuracy, _grace]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = await ref.read(adminApiProvider).campus();
      _name.text = '${c['campus_name'] ?? ''}';
      _timezone.text = '${c['timezone'] ?? 'Asia/Kolkata'}';
      _lat.text = c['latitude']?.toString() ?? '';
      _lng.text = c['longitude']?.toString() ?? '';
      _radius.text = '${c['radius_m'] ?? 500}';
      _accuracy.text = '${c['max_location_accuracy_m'] ?? 150}';
      _grace.text = '${c['late_grace_minutes'] ?? 15}';
      _mode = '${c['geofence_mode'] ?? 'flag'}';
      _threshold = (c['face_match_threshold'] as num?)?.toDouble() ?? 0.6;
      final parts = '${c['work_start_time'] ?? '09:00'}'.split(':');
      _start = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (e) {
      _error = errorMessage(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _useMyLocation() async {
    final fix = await LocationService.currentFix();
    if (!mounted) return;
    if (fix == null) {
      showSnack(context, 'Could not get your location. Turn on GPS.', error: true);
      return;
    }
    setState(() {
      _lat.text = fix.latitude.toStringAsFixed(6);
      _lng.text = fix.longitude.toStringAsFixed(6);
    });
    showSnack(context, 'Accuracy ±${fix.accuracy.round()} m — save to apply');
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(adminApiProvider).saveCampus({
        'campus_name': _name.text.trim(),
        'timezone': _timezone.text.trim(),
        if (_lat.text.trim().isNotEmpty) 'latitude': double.parse(_lat.text.trim()),
        if (_lng.text.trim().isNotEmpty) 'longitude': double.parse(_lng.text.trim()),
        'radius_m': int.parse(_radius.text.trim()),
        'max_location_accuracy_m': int.parse(_accuracy.text.trim()),
        'late_grace_minutes': int.parse(_grace.text.trim()),
        'geofence_mode': _mode,
        'work_start_time':
            '${_start.hour.toString().padLeft(2, '0')}:${_start.minute.toString().padLeft(2, '0')}',
        'face_match_threshold': double.parse(_threshold.toStringAsFixed(2)),
      });
      if (mounted) showSnack(context, 'Settings saved');
    } on FormatException {
      if (mounted) showSnack(context, 'Check the numbers you entered', error: true);
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final bytes = await ref.read(adminApiProvider).exportReport(_from, _to);
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/staff-attendance_${Fmt.apiDate(_from)}_${Fmt.apiDate(_to)}.xlsx',
      );
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Staff attendance ${Fmt.apiDate(_from)} → ${Fmt.apiDate(_to)}',
        ),
      );
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Export', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _from,
                            firstDate: DateTime(2024),
                            lastDate: DateTime.now(),
                          );
                          if (d != null) setState(() => _from = d);
                        },
                        child: Text('From ${Fmt.shortDate(_from)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _to,
                            firstDate: DateTime(2024),
                            lastDate: DateTime.now(),
                          );
                          if (d != null) setState(() => _to = d);
                        },
                        child: Text('To ${Fmt.shortDate(_to)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                BusyButton(
                  label: 'Download Excel report',
                  icon: Icons.table_view,
                  busy: _exporting,
                  onPressed: _export,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('Campus rules', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Campus name'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _timezone,
          decoration: const InputDecoration(labelText: 'Timezone (e.g. Asia/Kolkata)'),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _lat,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(labelText: 'Latitude'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _lng,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(labelText: 'Longitude'),
              ),
            ),
          ],
        ),
        TextButton.icon(
          onPressed: _useMyLocation,
          icon: const Icon(Icons.my_location),
          label: const Text('Use my current location as campus centre'),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _radius,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Radius (m)'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _accuracy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Max GPS error (m)'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _mode,
          decoration: const InputDecoration(labelText: 'GPS geofence'),
          items: const [
            DropdownMenuItem(value: 'off', child: Text('Off — beacon only')),
            DropdownMenuItem(value: 'flag', child: Text('Flag — record & highlight outside')),
            DropdownMenuItem(value: 'enforce', child: Text('Enforce — reject outside campus')),
          ],
          onChanged: (v) => setState(() => _mode = v ?? _mode),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Office starts'),
                subtitle: Text(_start.format(context)),
                trailing: const Icon(Icons.schedule),
                onTap: () async {
                  final t = await showTimePicker(context: context, initialTime: _start);
                  if (t != null) setState(() => _start = t);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _grace,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Late after (min)'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text('Face match threshold: ${_threshold.toStringAsFixed(2)}'),
        Slider(
          value: _threshold,
          min: 0.4,
          max: 0.85,
          divisions: 45,
          onChanged: (v) => setState(() => _threshold = v),
        ),
        Text(
          'Higher = stricter. Check the face scores in Alerts / Today to tune it '
          '(same person is usually 0.65–0.9).',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        BusyButton(label: 'Save settings', icon: Icons.save, busy: _saving, onPressed: _save),
        const SizedBox(height: 24),
      ],
    );
  }
}
