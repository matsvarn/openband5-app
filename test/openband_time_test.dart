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
}
