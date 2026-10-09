import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../shared/widgets.dart';
import '../location/location_service.dart';
import 'admin_api.dart';

/// Campus rules (location, office hours, thresholds) + Excel reports.
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
    showSnack(context, 'Location set (±${fix.accuracy.round()} m). Save to apply.');
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
      if (mounted) showSnack(context, 'Please check the numbers you entered', error: true);
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
          text: 'Staff attendance ${Fmt.apiDate(_from)} to ${Fmt.apiDate(_to)}',
        ),
      );
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<DateTime?> _pickDate(DateTime initial) => showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2024),
    lastDate: DateTime.now(),
  );

  Widget _numberField(TextEditingController c, String label, {String? suffix}) => TextField(
    controller: c,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label, suffixText: suffix),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    const gap = SizedBox(height: 12);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        const SectionHeader('Reports'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  IconBadge(Icons.table_view_rounded, color: AppColors.success, size: 40),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Excel attendance report', style: AppText.h3),
                        Text('Daily log + per-staff summary', style: AppText.caption),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event_rounded, size: 18),
                      label: Text(Fmt.shortDate(_from)),
                      onPressed: () async {
                        final d = await _pickDate(_from);
                        if (d != null) setState(() => _from = d);
                      },
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event_rounded, size: 18),
                      label: Text(Fmt.shortDate(_to)),
                      onPressed: () async {
                        final d = await _pickDate(_to);
                        if (d != null) setState(() => _to = d);
                      },
                    ),
                  ),
                ],
              ),
              gap,
              PrimaryButton(
                label: 'Download & share',
                icon: Icons.download_rounded,
                busy: _exporting,
                onPressed: _export,
                color: AppColors.success,
              ),
            ],
          ),
        ),
        const SectionHeader('Institution'),
        AppCard(
          child: Column(
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Campus name'),
              ),
              gap,
              TextField(
                controller: _timezone,
                decoration: const InputDecoration(
                  labelText: 'Timezone',
                  helperText: 'e.g. Asia/Kolkata',
                ),
              ),
            ],
          ),
        ),
        const SectionHeader('Office hours'),
        AppCard(
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () async {
                    final t = await showTimePicker(context: context, initialTime: _start);
                    if (t != null) setState(() => _start = t);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Office starts',
                      suffixIcon: Icon(Icons.schedule_rounded),
                    ),
                    child: Text(_start.format(context), style: AppText.bodyStrong),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _numberField(_grace, 'Late after', suffix: 'min')),
            ],
          ),
        ),
        const SectionHeader('Campus location'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _lat,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Latitude'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _lng,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Longitude'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _useMyLocation,
                  icon: const Icon(Icons.my_location_rounded, size: 18),
                  label: const Text('Use my current location'),
                ),
              ),
              Row(
                children: [
                  Expanded(child: _numberField(_radius, 'Radius', suffix: 'm')),
                  const SizedBox(width: 12),
                  Expanded(child: _numberField(_accuracy, 'Max GPS error', suffix: 'm')),
                ],
              ),
              const SizedBox(height: 16),
              const Text('GPS check', style: AppText.bodyStrong),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'off', label: Text('Off')),
                  ButtonSegment(value: 'flag', label: Text('Flag')),
                  ButtonSegment(value: 'enforce', label: Text('Enforce')),
                ],
                selected: {_mode},
                onSelectionChanged: (v) => setState(() => _mode = v.first),
                showSelectedIcon: false,
              ),
              const SizedBox(height: 8),
              Text(switch (_mode) {
                'off' => 'Only the campus beacon is checked.',
                'enforce' => 'Check-ins outside the radius are rejected.',
                _ => 'Check-ins outside the radius are recorded and flagged for review.',
              }, style: AppText.caption),
            ],
          ),
        ),
        const SectionHeader('Face verification'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('Match threshold', style: AppText.bodyStrong)),
                  StatusChip.tone(_threshold.toStringAsFixed(2), AppColors.primary),
                ],
              ),
              Slider(
                value: _threshold,
                min: 0.4,
                max: 0.85,
                divisions: 45,
                onChanged: (v) => setState(() => _threshold = v),
              ),
              const Text(
                'Higher is stricter. The same person usually scores 0.65–0.90 — check the '
                'scores in Alerts before changing this.',
                style: AppText.caption,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: 'Save settings',
          icon: Icons.save_outlined,
          busy: _saving,
          onPressed: _save,
        ),
      ],
    );
  }
}
