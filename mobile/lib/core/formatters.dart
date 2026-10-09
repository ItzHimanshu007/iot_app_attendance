import 'package:intl/intl.dart';

/// Display helpers (local time of the phone — campus and phone share a timezone).
class Fmt {
  Fmt._();

  static final _time = DateFormat('hh:mm a');
  static final _date = DateFormat('EEE, d MMM yyyy');
  static final _shortDate = DateFormat('d MMM');
  static final _api = DateFormat('yyyy-MM-dd');

  static String time(DateTime? value) => value == null ? '—' : _time.format(value.toLocal());
  static String date(DateTime value) => _date.format(value);
  static String shortDate(DateTime value) => _shortDate.format(value);
  static String apiDate(DateTime value) => _api.format(value);

  static DateTime? parse(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

  static String hours(DateTime? start, DateTime? end) {
    if (start == null || end == null) return '—';
    final minutes = end.difference(start).inMinutes;
    return '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
  }

  static final _monthYear = DateFormat('MMMM yyyy');
  static final _weekday = DateFormat('EEE');
  static final _longDate = DateFormat('EEEE, d MMMM');

  static String monthYear(DateTime value) => _monthYear.format(value);
  static String weekday(DateTime value) => _weekday.format(value);
  static String longDate(DateTime value) => _longDate.format(value);

  static String greeting([DateTime? at]) {
    final hour = (at ?? DateTime.now()).hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  static const _honorifics = {'dr', 'prof', 'mr', 'mrs', 'ms', 'miss', 'er', 'shri', 'smt', 'sri'};

  static bool _isHonorific(String word) =>
      _honorifics.contains(word.toLowerCase().replaceAll('.', ''));

  /// "Dr. Asha Rao" → "AR".
  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final words = parts.where((p) => !_isHonorific(p)).toList();
    final use = words.isEmpty ? parts : words;
    if (use.isEmpty) return '?';
    if (use.length == 1) return use.first[0].toUpperCase();
    return '${use.first[0]}${use.last[0]}'.toUpperCase();
  }

  /// "Dr. Asha Rao" → "Dr. Asha", "Asha Rao" → "Asha".
  static String shortName(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    if (_isHonorific(parts.first) && parts.length > 1) return '${parts[0]} ${parts[1]}';
    return parts.first;
  }

  static String statusLabel(String status) => switch (status) {
    'present' => 'Present',
    'late' => 'Late',
    'absent' => 'Absent',
    'on_leave' => 'On leave',
    'not_marked' => 'Not marked',
    _ => status,
  };
}
