import 'dart:math' show min, max;

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/openband/time.dart';
import 'package:openstrap_edge/openband/theme.dart';

void main() {
  test('a real sub-minute coverage gap never rounds down to zero', () {
    expect(obGapMinutes(0.2), '<1 Min.');
    expect(obGapMinutes(24), '24 Min.');
    expect(obGapMinutes(24.2), '25 Min.');
  });
  test('recorded timezone is retained when the phone uses another zone', () {
    final time = recordedTime(
      DateTime.utc(2026, 9, 14, 21, 25),
      'Europe/Berlin',
    );
    expect(time.hour, 23);
    expect(time.timeZoneOffset, const Duration(hours: 2));
    expect(
      parseRecordedTime(time, '23:40', zone: 'Europe/Berlin')?.toUtc(),
      DateTime.utc(2026, 9, 14, 21, 40),
    );
  });
  test('nonexistent spring clock time is refused', () {
    expect(
      parseRecordedTime(DateTime(2026, 3, 29), '02:30', zone: 'Europe/Berlin'),
      isNull,
    );
  });
  test(
    'ambiguous autumn time keeps an existing offset and otherwise refuses',
    () {
      final date = DateTime(2026, 10, 25);
      expect(parseRecordedTime(date, '02:30', zone: 'Europe/Berlin'), isNull);
      expect(
        parseRecordedTime(
          date,
          '02:30',
          zone: 'Europe/Berlin',
          previous: DateTime.utc(2026, 10, 25, 0, 20),
        )?.toUtc(),
        DateTime.utc(2026, 10, 25, 0, 30),
      );
      expect(
        parseRecordedTime(
          date,
          '02:30',
          zone: 'Europe/Berlin',
          previous: DateTime.utc(2026, 10, 25, 1, 20),
        )?.toUtc(),
        DateTime.utc(2026, 10, 25, 1, 30),
      );
    },
  );
  test('invalid clock inputs are refused', () {
    for (final input in ['24:00', '12:60', '', '1234']) {
      expect(parseRecordedTime(DateTime(2026, 9, 15), input), isNull);
    }
  });

  DateTime localWall(DateTime date, String text) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text)!;
    return DateTime(
      date.year,
      date.month,
      date.day,
      int.parse(match[1]!),
      int.parse(match[2]!),
    );
  }

  Set<int> localInstants(DateTime date, String text) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text)!;
    final hour = int.parse(match[1]!), minute = int.parse(match[2]!);
    final candidate = DateTime(date.year, date.month, date.day, hour, minute);
    bool matches(DateTime t) =>
        t.year == date.year &&
        t.month == date.month &&
        t.day == date.day &&
        t.hour == hour &&
        t.minute == minute;
    if (!matches(candidate)) return {};
    final out = {candidate.millisecondsSinceEpoch};
    for (final delta in [-120, -60, -30, 30, 60, 120]) {
      final other = candidate.add(Duration(minutes: delta));
      if (matches(other)) out.add(other.millisecondsSinceEpoch);
    }
    return out;
  }

  test('Europe/Berlin spring gap is refused with and without a zone name', () {
    final berlin = DateTime(2026, 3, 29);
    expect(
      parseRecordedTime(berlin, '02:30', zone: 'Europe/Berlin'),
      isNull,
    );
    final local = localWall(berlin, '02:30');
    if (local.hour != 2 || local.minute != 30) {
      expect(parseRecordedTime(berlin, '02:30'), isNull);
    }
  });

  test('zone-null autumn ambiguity keeps a matching offset or refuses', () {
    final date = DateTime(2026, 10, 25);
    final instants = localInstants(date, '02:30');
    if (instants.length < 2) {
      expect(
        parseRecordedTime(date, '02:30', zone: 'Europe/Berlin'),
        isNull,
      );
      return;
    }
    expect(parseRecordedTime(date, '02:30'), isNull);
    final earlier = DateTime.fromMillisecondsSinceEpoch(instants.reduce(min));
    final later = DateTime.fromMillisecondsSinceEpoch(instants.reduce(max));
    expect(
      parseRecordedTime(date, '02:30', previous: earlier)?.toUtc(),
      earlier.toUtc(),
    );
    expect(
      parseRecordedTime(date, '02:30', previous: later)?.toUtc(),
      later.toUtc(),
    );
  });
}
