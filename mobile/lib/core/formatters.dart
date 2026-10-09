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

  static String statusLabel(String status) => switch (status) {
    'present' => 'Present',
    'late' => 'Late',
    'absent' => 'Absent',
    'on_leave' => 'On leave',
    'not_marked' => 'Not marked',
    _ => status,
  };
}
