// G3 display formats. Pass local DateTimes; these functions do not convert
// time zones. Use g3DayLong for headings, g3DayShort for rows, g3NightOf for
// sleep labels, g3DateShort for a date without weekday, and g3Relative for a
// timestamp relative to a supplied clock. g3DataThrough supplies freshness
// copy. g3Clock returns HH:mm; g3Weekday returns a short weekday. g3Duration
// takes whole minutes; g3Signed adds a sign and optional
// unit. Null durations and signed values render as "—".
const _weekdays = [
  'Montag',
  'Dienstag',
  'Mittwoch',
  'Donnerstag',
  'Freitag',
  'Samstag',
  'Sonntag',
];
const _shortWeekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
const _months = [
  'Januar',
  'Februar',
  'März',
  'April',
  'Mai',
  'Juni',
  'Juli',
  'August',
  'September',
  'Oktober',
  'November',
  'Dezember',
];

String _two(int n) => n.toString().padLeft(2, '0');

String g3DayLong(DateTime day) =>
    '${_weekdays[day.weekday - 1]}, ${day.day}. ${_months[day.month - 1]}';

String g3DateShort(DateTime day) => '${_two(day.day)}.${_two(day.month)}';

String g3Clock(DateTime time) => '${_two(time.hour)}:${_two(time.minute)}';

String g3Weekday(DateTime day) => _shortWeekdays[day.weekday - 1];

String g3DayShort(DateTime day) =>
    '${_shortWeekdays[day.weekday - 1]} '
    '${g3DateShort(day)}';

String g3NightOf(DateTime day) => 'Nacht zu ${g3DayShort(day)}';

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String g3Relative(DateTime value, {required DateTime now}) {
  final clock = g3Clock(value);
  if (_sameDay(value, now)) return 'heute $clock';
  final yesterday = DateTime(now.year, now.month, now.day - 1);
  if (_sameDay(value, yesterday)) return 'gestern $clock';
  return '${g3DayShort(value)} $clock';
}

String g3DataThrough(DateTime? value, {required DateTime now}) {
  if (value == null) return 'Datenstand unbekannt';
  final clock = g3Clock(value);
  if (_sameDay(value, now)) return 'Daten bis $clock';
  final yesterday = DateTime(now.year, now.month, now.day - 1);
  if (_sameDay(value, yesterday)) return 'Daten bis gestern $clock';
  return 'Daten bis ${g3DayShort(value)} $clock';
}

String g3Duration(int? minutes) {
  if (minutes == null) return '—';
  final sign = minutes < 0 ? '−' : '';
  final absolute = minutes.abs();
  if (absolute < 60) return '$sign$absolute Min.';
  final hours = absolute ~/ 60;
  final remainder = absolute % 60;
  return '$sign${hours}h${remainder == 0 ? '' : _two(remainder)}';
}

String g3Signed(num? value, {int digits = 0, String? unit}) {
  if (value == null || !value.isFinite) return '—';
  final magnitude = value.abs().toStringAsFixed(digits).replaceAll('.', ',');
  final roundedZero = magnitude.replaceAll(RegExp('[0,]'), '').isEmpty;
  final sign = roundedZero ? '' : (value < 0 ? '−' : '+');
  return '$sign$magnitude${unit == null ? '' : ' $unit'}';
}
