import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/openband/weight_data.dart';

Map<String, Object?> _loadFixture() =>
    jsonDecode(
          File(
            'docs/openband5/assets/fixtures/weight-history.json',
          ).readAsStringSync(),
        )
        as Map<String, Object?>;

void main() {
  test('windows are 7/30/90 civil days ending on endDay', () {
    expect(kWeightHistoryWindows, {7, 30, 90});
    expect(kWeightJournalField, 'weight_kg');
    expect(kJournalFieldsByKey[kWeightJournalField]!.max, 400);
    expect(() => requireWeightHistoryDays(14), throwsArgumentError);
    expect(() => requireWeightHistoryDay('2026-02-30'), throwsArgumentError);
    expect(() => requireWeightHistoryDay('2026-9-15'), throwsArgumentError);
    expect(() => weightDaysEnding('2026-09-15', 14), throwsArgumentError);

    final seven = weightDaysEnding('2026-09-15', 7);
    expect(seven, hasLength(7));
    expect(seven.first, '2026-09-09');
    expect(seven.last, '2026-09-15');
    expect(seven, openBandDaysEnding('2026-09-15', 7));
    expect(seven.toSet(), hasLength(7));

    final thirty = weightDaysEnding('2026-09-15', 30);
    expect(thirty.first, '2026-08-17');
    expect(thirty.last, '2026-09-15');
    expect(thirty, hasLength(30));

    final ninety = weightDaysEnding('2026-09-15', 90);
    expect(ninety.first, '2026-06-18');
    expect(ninety.last, '2026-09-15');
    expect(ninety, hasLength(90));
  });

  test('trailing windows are local calendar days, including DST', () {
    const spring = '2026-03-30';
    final thirty = weightDaysEnding(spring, 30);
    expect(thirty, hasLength(30));
    expect(thirty.last, spring);
    expect(thirty.first, '2026-03-01');
    expect(thirty, openBandDaysEnding(spring, 30));
    expect(thirty.toSet(), hasLength(30));

    final seven = weightDaysEnding(spring, 7);
    expect(seven, [
      '2026-03-24',
      '2026-03-25',
      '2026-03-26',
      '2026-03-27',
      '2026-03-28',
      '2026-03-29',
      '2026-03-30',
    ]);

    const fall = '2026-10-25';
    final fallSeven = weightDaysEnding(fall, 7);
    expect(fallSeven, hasLength(7));
    expect(fallSeven.first, '2026-10-19');
    expect(fallSeven.last, fall);
    expect(fallSeven.toSet(), hasLength(7));
  });

  test('EWMA keeps a one-civil-day gap across Berlin spring DST', () {
    final history = buildWeightHistory(
      endDay: '2026-03-30',
      days: 7,
      rows: const [
        WeightStoredRow(date: '2026-03-29', value: 80),
        WeightStoredRow(date: '2026-03-30', value: 70),
      ],
    );
    expect(history.trend[5], 80);
    expect(history.trend[6], closeTo(79.05723664263907, 1e-12));
  });

  test('paper fixture matches weightTrendEwma and dated entries', () {
    final fixture = _loadFixture();
    expect(fixture['variant'], 'additional-weight-history');
    expect((fixture['dates'] as List).cast<String>(), kWeightPaperDates);
    expect([
      for (final v in fixture['enteredKg'] as List) (v as num).toDouble(),
    ], kWeightPaperEnteredKg);
    expect(fixture['halfLifeDays'], kWeightTrendHalfLifeDays);

    final byDay = <String, double>{
      for (var i = 0; i < kWeightPaperDates.length; i++)
        kWeightPaperDates[i]: kWeightPaperEnteredKg[i],
    };
    final ewma = weightTrendEwma(byDay);
    final fixtureEwma = [
      for (final v in fixture['ewmaKg'] as List) (v as num).toDouble(),
    ];
    expect(fixtureEwma, kWeightPaperEwmaKg);
    for (var i = 0; i < kWeightPaperDates.length; i++) {
      expect(ewma[kWeightPaperDates[i]], closeTo(fixtureEwma[i], 1e-12));
    }

    final history = buildWeightHistory(
      endDay: kWeightPaperEndDay,
      days: 7,
      rows: [
        for (var i = 0; i < kWeightPaperDates.length; i++)
          WeightStoredRow(
            date: kWeightPaperDates[i],
            value: kWeightPaperEnteredKg[i],
            updatedAt: i + 1,
          ),
      ],
    );
    expect(history.latest?.day, '2026-09-15');
    expect(history.latest?.value, 75);
    expect(history.entries.map((e) => e.day), kWeightPaperDates.reversed);
    expect(history.entries.map((e) => e.value), kWeightPaperEnteredKg.reversed);
    expect(history.trend, hasLength(7));
    for (var i = 0; i < 7; i++) {
      expect(history.trend[i], closeTo(kWeightPaperEwmaKg[i], 1e-12));
    }
    expect(history.unreadableCount, 0);
  });

  test('gaps stay null in trend slots; entries omit missing days', () {
    final history = buildWeightHistory(
      endDay: '2026-09-15',
      days: 7,
      rows: const [
        WeightStoredRow(date: '2026-09-09', value: 80, updatedAt: 1),
        WeightStoredRow(date: '2026-09-15', value: 76, updatedAt: 2),
      ],
    );
    expect(history.entries.map((e) => e.day), ['2026-09-15', '2026-09-09']);
    expect(history.trend.first, 80);
    expect(history.trend.last, isNotNull);
    for (var i = 1; i < 6; i++) {
      expect(history.trend[i], isNull);
    }
    expect(history.unreadableCount, 0);
  });

  test('same-date trend is invariant across 7/30/90', () {
    final rows = [
      const WeightStoredRow(date: '2026-06-20', value: 80, updatedAt: 1),
      const WeightStoredRow(date: '2026-08-01', value: 78, updatedAt: 2),
      const WeightStoredRow(date: '2026-09-15', value: 76, updatedAt: 3),
    ];
    final seven = buildWeightHistory(endDay: '2026-09-15', days: 7, rows: rows);
    final thirty = buildWeightHistory(
      endDay: '2026-09-15',
      days: 30,
      rows: rows,
    );
    final ninety = buildWeightHistory(
      endDay: '2026-09-15',
      days: 90,
      rows: rows,
    );
    expect(seven.trend.last, ninety.trend.last);
    expect(thirty.trend.last, ninety.trend.last);
    expect(seven.latest?.day, '2026-09-15');
    expect(seven.entries.single.day, '2026-09-15');
    expect(ninety.entries.map((e) => e.day), [
      '2026-09-15',
      '2026-08-01',
      '2026-06-20',
    ]);
  });

  test('latest keeps its real date when it precedes the window', () {
    final history = buildWeightHistory(
      endDay: '2026-09-15',
      days: 7,
      rows: const [
        WeightStoredRow(date: '2026-08-01', value: 81.4, updatedAt: 4),
      ],
    );
    expect(history.latest?.day, '2026-08-01');
    expect(history.latest?.value, 81.4);
    expect(history.entries, isEmpty);
    expect(history.trend, everyElement(isNull));
  });

  test('valid future dates are excluded before decoding their value', () {
    final history = buildWeightHistory(
      endDay: '2026-09-15',
      days: 7,
      rows: const [
        WeightStoredRow(date: '2026-09-15', value: 75),
        WeightStoredRow(date: '2026-09-16', value: 'corrupt'),
        WeightStoredRow(date: '2026-09-17', value: double.nan),
      ],
    );
    expect(history.latest?.value, 75);
    expect(history.entries, hasLength(1));
    expect(history.unreadableCount, 0);
  });

  test('selected historical end excludes future entries', () {
    final history = buildWeightHistory(
      endDay: '2026-09-10',
      days: 7,
      rows: const [
        WeightStoredRow(date: '2026-09-09', value: 75.4, updatedAt: 1),
        WeightStoredRow(date: '2026-09-10', value: 75.2, updatedAt: 2),
        WeightStoredRow(date: '2026-09-15', value: 75, updatedAt: 3),
      ],
    );
    expect(history.latest?.day, '2026-09-10');
    expect(history.latest?.value, 75.2);
    expect(history.entries.map((e) => e.day), ['2026-09-10', '2026-09-09']);
    expect(history.entries.any((e) => e.day == '2026-09-15'), isFalse);
  });

  test(
    'finite out-of-range entries stay editable; nonfinite is unreadable',
    () {
      final history = buildWeightHistory(
        endDay: '2026-09-15',
        days: 7,
        rows: const [
          WeightStoredRow(date: '2026-09-09', value: 80, updatedAt: 1),
          WeightStoredRow(date: '2026-09-12', value: 0, updatedAt: 2),
          WeightStoredRow(date: '2026-09-13', value: -1, updatedAt: 3),
          WeightStoredRow(date: '2026-09-14', value: double.nan, updatedAt: 4),
          WeightStoredRow(date: '2026-09-15', value: 401, updatedAt: 5),
        ],
      );
      expect(history.entries, hasLength(4));
      expect(history.latest?.value, 401);
      expect(history.latest?.usableForTrend, isFalse);
      expect(
        history.entries.firstWhere((e) => e.day == '2026-09-12').usableForTrend,
        isFalse,
      );
      expect(
        history.entries.firstWhere((e) => e.day == '2026-09-13').usableForTrend,
        isFalse,
      );
      expect(history.entries.any((e) => e.day == '2026-09-14'), isFalse);
      expect(history.trend[0], 80);
      expect(history.trend[3], isNull);
      expect(history.trend[4], isNull);
      expect(history.trend[5], isNull);
      expect(history.trend[6], isNull);
      expect(history.unreadableCount, 1);
      expect(history.invalidCount, 3);
    },
  );

  test(
    'corrupt dates and non-numeric values count as unreadable, not missing',
    () {
      final history = buildWeightHistory(
        endDay: '2026-09-15',
        days: 7,
        rows: const [
          WeightStoredRow(date: '2026-09-15', value: 75, updatedAt: 1),
          WeightStoredRow(date: '2026-02-30', value: 70, updatedAt: 2),
          WeightStoredRow(date: 'not-a-day', value: 70, updatedAt: 3),
          WeightStoredRow(date: '2026-09-14', value: '75', updatedAt: 4),
          WeightStoredRow(date: '2026-09-13', value: null, updatedAt: 5),
          WeightStoredRow(date: '2026-09-12', value: double.infinity),
        ],
      );
      expect(history.unreadableCount, 5);
      expect(history.entries.single.value, 75);
      expect(history.latest?.day, '2026-09-15');
    },
  );

  test('missing or invalid stored metadata stays nullable unknown', () {
    final entry = interpretWeightRow(
      const WeightStoredRow(date: '2026-09-15', value: 75.0),
    );
    expect(entry?.updatedAt, isNull);
    expect(entry?.atMinuteOfDay, isNull);
    expect(
      interpretWeightRow(
        const WeightStoredRow(
          date: '2026-09-15',
          value: 75.0,
          updatedAt: 12,
          atMinuteOfDay: 435,
        ),
      )?.atMinuteOfDay,
      435,
    );

    for (final invalid in <Object?>[
      double.nan,
      double.infinity,
      1.5,
      -1,
      '12',
    ]) {
      final decoded = interpretWeightRow(
        WeightStoredRow(
          date: '2026-09-15',
          value: 75.0,
          updatedAt: invalid,
          atMinuteOfDay: invalid,
        ),
      );
      expect(decoded?.updatedAt, isNull, reason: '$invalid revision');
      expect(decoded?.atMinuteOfDay, isNull, reason: '$invalid minute');
    }
    final zeroMetadata = interpretWeightRow(
      const WeightStoredRow(
        date: '2026-09-15',
        value: 75.0,
        updatedAt: 0,
        atMinuteOfDay: 0,
      ),
    );
    expect(zeroMetadata?.updatedAt, isNull);
    expect(zeroMetadata?.atMinuteOfDay, 0);
    expect(
      interpretWeightRow(
        const WeightStoredRow(
          date: '2026-09-15',
          value: 75.0,
          atMinuteOfDay: 1440,
        ),
      )?.atMinuteOfDay,
      isNull,
    );
  });

  test('empty rows are an empty history, not an error', () {
    final history = buildWeightHistory(
      endDay: '2026-09-15',
      days: 7,
      rows: const [],
    );
    expect(history.entries, isEmpty);
    expect(history.latest, isNull);
    expect(history.trend, everyElement(isNull));
    expect(history.trend, hasLength(7));
    expect(history.unreadableCount, 0);
    expect(history.invalidCount, 0);
  });
}
