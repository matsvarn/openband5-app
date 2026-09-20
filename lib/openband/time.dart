import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

bool _zonesLoaded = false;
tz.Location? _location(String? name) {
  if (name == null || name.isEmpty) return null;
  if (!_zonesLoaded) {
    tzdata.initializeTimeZones();
    _zonesLoaded = true;
  }
  try {
    return tz.getLocation(name);
  } catch (_) {
    return null;
  }
}

DateTime recordedTime(DateTime instant, String? zone) {
  final location = _location(zone);
  return location == null
      ? instant.toLocal()
      : tz.TZDateTime.from(instant, location);
}

/// Refuses nonexistent spring-forward times. For an ambiguous autumn time,
/// retains the previous endpoint's offset only if that offset identifies it.
DateTime? parseRecordedTime(
  DateTime date,
  String text, {
  String? zone,
  DateTime? previous,
}) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text.trim());
  if (match == null) return null;
  final hour = int.parse(match[1]!), minute = int.parse(match[2]!);
  if (hour > 23 || minute > 59) return null;
  final location = _location(zone);
  final candidate = location == null
      ? DateTime(date.year, date.month, date.day, hour, minute)
      : tz.TZDateTime(location, date.year, date.month, date.day, hour, minute);
  bool matches(DateTime t) =>
      t.year == date.year &&
      t.month == date.month &&
      t.day == date.day &&
      t.hour == hour &&
      t.minute == minute;
  if (!matches(candidate)) return null;
  final alternatives = <DateTime>[candidate];
  for (final delta in [-120, -60, -30, 30, 60, 120]) {
    final shifted = candidate.add(Duration(minutes: delta));
    final other = location == null
        ? shifted
        : tz.TZDateTime.from(shifted, location);
    if (!matches(other)) continue;
    if (alternatives.any(
      (value) => value.millisecondsSinceEpoch == other.millisecondsSinceEpoch,
    )) {
      continue;
    }
    alternatives.add(other);
  }
  if (alternatives.length == 1) return candidate;
  if (previous == null) return null;
  final offset = recordedTime(previous, zone).timeZoneOffset;
  for (final value in alternatives) {
    if (value.timeZoneOffset == offset) return value;
  }
  return null;
}
