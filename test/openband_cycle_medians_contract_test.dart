import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:openstrap_edge/openband/cycle_data.dart';
import 'package:openstrap_edge/openband/cycle_measurements_data.dart';
import 'package:openstrap_edge/openband/cycle_medians_data.dart';

const _settings = CycleSettings(
  enabled: true,
  estimatesEnabled: true,
  lengthReviewEnabled: false,
);

const _paperStarts = ['2026-06-29', '2026-07-31', '2026-08-24'];
const _anchor = '2026-09-15';

CycleLogParse _log(
  List<String> starts,
  String asOf, {
  List<Map<Object?, Object?>> extra = const [],
}) {
  return parseCycleLog(
    startRows: [
      for (final d in starts) {'date': d, 'kind': kCycleStartKind},
      ...extra,
    ],
    observationRows: const [],
    asOf: asOf,
  );
}

CycleNightSourceRow _night(
  String day, {
  double? rhr,
  double? hrv,
  int? algo,
  bool skipped = false,
  bool partial = false,
  bool imported = false,
  bool payloadUnreadable = false,
  double? rhrConfidence,
  double? hrvConfidence,
  String? rhrNote,
  String sleepSource = 'auto',
  int? computedAtMs,
  int? resultComputedAtMs,
  String? correctionAction,
}) {
  return CycleNightSourceRow(
    day: day,
    algoVersion: algo ?? kAlgoVersion,
    skipped: skipped,
    partial: partial,
    payloadUnreadable: payloadUnreadable,
    computedAtMs: computedAtMs,
    resultComputedAtMs: resultComputedAtMs,
    correctionAction: correctionAction,
    payload: payloadUnreadable
        ? null
        : cycleNightSourcePayload(
            rhr: rhr,
            hrv: hrv,
            onsetMs: cycleNightOnsetMs(day),
            offsetMs: cycleNightOffsetMs(day),
            imported: imported,
            rhrConfidence: rhrConfidence,
            hrvConfidence: hrvConfidence,
            rhrNote: rhrNote,
            sleepSource: sleepSource,
          ),
  );
}

List<CycleNightSourceRow> _paperNights(String start) {
  return [
    for (var i = 0; i < kCyclePaperRhr.length; i++)
      if (kCyclePaperRhr[i] != null || kCyclePaperHrv[i] != null)
        _night(
          cycleAddDays(start, i),
          rhr: kCyclePaperRhr[i],
          hrv: kCyclePaperHrv[i],
        ),
  ];
}

List<CycleNightSourceRow> _nightsOn(
  String start,
  List<double?> rhr,
  List<double?> hrv,
) {
  return [
    for (var i = 0; i < rhr.length; i++)
      if (rhr[i] != null || hrv[i] != null)
        _night(cycleAddDays(start, i), rhr: rhr[i], hrv: hrv[i]),
  ];
}

CycleMediansSnapshot _snap({
  CycleSettings settings = _settings,
  List<String> starts = _paperStarts,
  String anchorEnd = _anchor,
  int pageOffset = 0,
  List<CycleNightSourceRow> rows = const [],
  CycleLogParse? log,
  int? algoVersion,
}) {
  final window = cycleMedianWindow(
    anchorEnd: anchorEnd,
    pageOffset: pageOffset,
  );
  return buildCycleMediansSnapshot(
    settings: settings,
    log: log ?? _log(starts, window.endDay),
    algoVersion: algoVersion ?? kAlgoVersion,
    window: window,
    rows: rows,
  );
}

void main() {
  test('kAlgoVersion remains the cycle-night pin', () {
    expect(kAlgoVersion, 90);
  });

  test('window is twelve civil months from a fixed anchor, not 365 or UTC', () {
    final page0 = cycleMedianWindow(anchorEnd: _anchor, pageOffset: 0);
    expect(page0.startDay, '2025-09-16');
    expect(page0.endDay, '2026-09-15');
    expect(page0.page, 0);
    expect(page0.expectedNightCount, 365);
    expect(page0.expectedNights.first, page0.startDay);
    expect(page0.expectedNights.last, page0.endDay);
    expect(page0.expectedNights, hasLength(365));

    final page1 = cycleMedianWindow(anchorEnd: _anchor, pageOffset: 1);
    expect(page1.startDay, '2024-09-16');
    expect(page1.endDay, '2025-09-15');
    expect(cycleAddDays(page1.endDay, 1), page0.startDay);
    expect(cycleAddDays(page0.endDay, 1), '2026-09-16');

    final page2 = cycleMedianWindow(anchorEnd: _anchor, pageOffset: 2);
    expect(page2.expectedNightCount, 366);
    expect(cycleAddDays(page2.endDay, 1), page1.startDay);

    expect(
      cycleMedianWindow(anchorEnd: _anchor, pageOffset: 0).startDay,
      page0.startDay,
    );
  });

  test('leap clamp and end-of-month stay on the fixed anchor', () {
    final leap = cycleMedianWindow(anchorEnd: '2024-02-28', pageOffset: 0);
    expect(leap.startDay, '2023-02-28');
    expect(leap.endDay, '2024-02-28');
    expect(leap.expectedNightCount, 366);
    final leapBack = cycleMedianWindow(anchorEnd: '2024-02-28', pageOffset: 1);
    expect(leapBack.startDay, '2022-02-28');
    expect(leapBack.endDay, '2023-02-27');
    expect(cycleAddDays(leapBack.endDay, 1), leap.startDay);

    final jan = cycleMedianWindow(anchorEnd: '2025-01-31', pageOffset: 0);
    expect(jan.startDay, '2024-02-01');
    expect(jan.endDay, '2025-01-31');
    final janBack = cycleMedianWindow(anchorEnd: '2025-01-31', pageOffset: 1);
    expect(janBack.endDay, '2024-01-31');
    expect(cycleAddDays(janBack.endDay, 1), jan.startDay);
  });

  test('DST civil nights stay consecutive labels, not duration math', () {
    final window = cycleMedianWindow(anchorEnd: _anchor, pageOffset: 0);
    expect(
      cycleCivilDaysInclusive('2026-03-07', '2026-03-10'),
      ['2026-03-07', '2026-03-08', '2026-03-09', '2026-03-10'],
    );
    expect(
      cycleCivilDaysInclusive('2026-10-31', '2026-11-02'),
      ['2026-10-31', '2026-11-01', '2026-11-02'],
    );
    expect(window.expectedNights.contains('2026-03-08'), isTrue);
    expect(window.expectedNights.contains('2025-11-01'), isTrue);
    expect(cycleDiffDays('2026-03-08', '2026-03-09'), 1);
  });

  test('malformed, impossible, negative, and year-range windows throw', () {
    expect(
      () => cycleMedianWindow(anchorEnd: '15-09-2026', pageOffset: 0),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => cycleMedianWindow(anchorEnd: '2026-02-29', pageOffset: 0),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => cycleMedianWindow(anchorEnd: _anchor, pageOffset: -1),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => cycleMedianWindow(anchorEnd: '0001-01-31', pageOffset: 0),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => cycleMedianWindow(anchorEnd: '9999-12-31', pageOffset: 0),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('paper medians reuse sparse nights across three recorded starts', () {
    final rows = [
      for (final start in _paperStarts) ..._paperNights(start),
    ];
    final snap = _snap(rows: rows);
    expect(snap.reason, CycleMediansReason.available);
    expect(snap.window.startDay, '2025-09-16');
    expect(snap.window.endDay, '2026-09-15');
    expect(snap.periods.map((p) => p.startDay), _paperStarts);
    expect(snap.periods.last.open, isTrue);
    expect(snap.periods.first.open, isFalse);
    expect(snap.partial, isFalse);

    expect(snap.rhr.available, isTrue);
    expect(snap.rhr.points, hasLength(23));
    expect(snap.rhr.qualifyingDayCount, 19);
    expect(snap.rhr.latest?.cycleDay, 23);
    expect(snap.rhr.latest?.median, 54);
    expect(snap.rhr.latest?.contributingPeriodCount, 3);
    expect(
      [for (final p in snap.rhr.points) p.median],
      [
        for (final v in kCyclePaperRhr) v,
      ],
    );
    expect(snap.rhr.points[5].cycleDay, 6);
    expect(snap.rhr.points[5].median, isNull);
    expect(snap.rhr.points[5].contributingPeriodCount, 0);
    expect(snap.rhr.points[6].median, isNull);
    expect(snap.rhr.eligibleNightCount, 19 * 3);

    expect(snap.hrv.available, isTrue);
    expect(snap.hrv.points, hasLength(22));
    expect(snap.hrv.qualifyingDayCount, 16);
    expect(snap.hrv.latest?.cycleDay, 22);
    expect(snap.hrv.latest?.median, 48);
    expect(snap.hrv.latest?.contributingPeriodCount, 3);
    expect(
      [for (final p in snap.hrv.points) p.median],
      kCyclePaperHrv.sublist(0, 22),
    );
    expect(snap.hrv.latest?.cycleDay, isNot(snap.rhr.latest?.cycleDay));
  });

  test('independent known medians use pinned ana.median and period counts', () {
    const starts = ['2026-07-01', '2026-08-01', '2026-09-01'];
    final rows = [
      ..._nightsOn('2026-07-01', [10, 20, 40], [1, 2, 3]),
      ..._nightsOn('2026-08-01', [30, 20, 10], [9, 8, 7]),
      ..._nightsOn('2026-09-01', [20, 20, 20], [5, 5, 5]),
    ];
    final snap = _snap(starts: starts, rows: rows);
    expect(snap.rhr.points.map((p) => p.median), [20, 20, 20]);
    expect(snap.rhr.points.map((p) => p.median), [
      ana.median([10, 30, 20]),
      ana.median([20, 20, 20]),
      ana.median([40, 10, 20]),
    ]);
    expect(snap.rhr.points.every((p) => p.contributingPeriodCount == 3), isTrue);
    expect(snap.hrv.points.map((p) => p.median), [5, 5, 5]);
    expect(snap.hrv.points.map((p) => p.median), [
      ana.median([1, 9, 5]),
      ana.median([2, 8, 5]),
      ana.median([3, 7, 5]),
    ]);
    expect(snap.rhr.points.first.contributors.map((c) => c.nightDay), [
      '2026-07-01',
      '2026-08-01',
      '2026-09-01',
    ]);
    expect(snap.rhr.points.first.contributors.map((c) => c.startDay), starts);
  });

  test('start before window keeps original cycleDay and drops earlier nights', () {
    const early = '2025-09-10';
    const close = '2025-10-01';
    const late = '2026-08-20';
    final window = cycleMedianWindow(anchorEnd: _anchor, pageOffset: 0);
    expect(early.compareTo(window.startDay) < 0, isTrue);
    expect(cycleDiffDays(early, '2025-09-16') + 1, 7);
    final snap = _snap(
      starts: const [early, close, late],
      rows: [
        _night(early, rhr: 88, hrv: 88),
        _night('2025-09-15', rhr: 99, hrv: 99),
        _night('2025-09-16', rhr: 10, hrv: 1),
        _night('2025-09-17', rhr: 20, hrv: 2),
        _night('2025-09-18', rhr: 30, hrv: 3),
        _night('2026-08-26', rhr: 40, hrv: 7),
        _night('2026-08-27', rhr: 50, hrv: 8),
        _night('2026-08-28', rhr: 60, hrv: 9),
      ],
    );
    expect(snap.reason, CycleMediansReason.available);
    expect(snap.rhr.points.map((p) => p.cycleDay), [1, 2, 3, 4, 5, 6, 7, 8, 9]);
    expect(snap.rhr.points.map((p) => p.median), [null, null, null, null, null, null, 25, 35, 45]);
    expect(snap.rhr.points.map((p) => p.contributingPeriodCount), [0, 0, 0, 0, 0, 0, 2, 2, 2]);
    expect(snap.rhr.points[6].contributors.map((c) => c.startDay), [early, late]);
    expect(snap.rhr.points[6].contributors.map((c) => c.nightDay), [
      '2025-09-16',
      '2026-08-26',
    ]);
    expect(snap.rhr.points[6].contributors.map((c) => c.cycleDay), [7, 7]);
    expect(
      snap.rhr.eligibleNights.any((c) => c.nightDay.compareTo(window.startDay) < 0),
      isFalse,
    );
    expect(snap.rhr.eligibleNights.map((c) => c.metric.value), isNot(contains(88)));
    expect(snap.rhr.eligibleNights.map((c) => c.metric.value), isNot(contains(99)));
    expect(snap.hrv.points.map((p) => p.cycleDay), [1, 2, 3, 4, 5, 6, 7, 8, 9]);
    expect(snap.hrv.points.map((p) => p.median), [null, null, null, null, null, null, 4, 5, 6]);
    expect(snap.hrv.points.map((p) => p.contributingPeriodCount), [0, 0, 0, 0, 0, 0, 2, 2, 2]);
  });

  test('a point needs two distinct periods; the chart needs three cycle days', () {
    final one = _snap(
      starts: const ['2026-08-24'],
      rows: _nightsOn('2026-08-24', [51, 52, 53, 54, 55], [40, 41, 42, 43, 44]),
    );
    expect(one.reason, CycleMediansReason.insufficientDays);
    expect(one.rhr.available, isFalse);
    expect(one.rhr.points, isEmpty);
    expect(one.rhr.latest, isNull);
    expect(one.rhr.qualifyingDayCount, 0);
    expect(one.rhr.eligibleNightCount, 5);

    final twoDays = _snap(
      starts: const ['2026-08-01', '2026-09-01'],
      rows: [
        ..._nightsOn('2026-08-01', [10, 11], [1, 2]),
        ..._nightsOn('2026-09-01', [20, 21], [8, 9]),
      ],
    );
    expect(twoDays.reason, CycleMediansReason.insufficientDays);
    expect(twoDays.rhr.qualifyingDayCount, 2);
    expect(twoDays.rhr.points, isEmpty);
    expect(twoDays.rhr.eligibleNightCount, 4);

    final threeDays = _snap(
      starts: const ['2026-08-01', '2026-09-01'],
      rows: [
        ..._nightsOn('2026-08-01', [10, 11, 12], [1, 2, 3]),
        ..._nightsOn('2026-09-01', [20, 21, 22], [8, 9, 10]),
      ],
    );
    expect(threeDays.reason, CycleMediansReason.available);
    expect(threeDays.rhr.points, hasLength(3));
    expect(threeDays.rhr.points.map((p) => p.median), [
      ana.median([10, 20]),
      ana.median([11, 21]),
      ana.median([12, 22]),
    ]);
    expect(threeDays.rhr.points.first.contributingPeriodCount, 2);
  });

  test('dense slots keep holes; trailing unobserved days are not appended', () {
    final snap = _snap(
      starts: const ['2026-07-01', '2026-08-01'],
      rows: [
        ..._nightsOn('2026-07-01', [10, 11, null, 13, 99], [1, 2, 3, 4, 5]),
        ..._nightsOn('2026-08-01', [20, 21, null, 23], [8, 9, 10, 11]),
      ],
    );
    expect(snap.rhr.available, isTrue);
    expect(snap.rhr.points.map((p) => p.cycleDay), [1, 2, 3, 4]);
    expect(snap.rhr.points.map((p) => p.median), [
      ana.median([10, 20]),
      ana.median([11, 21]),
      null,
      ana.median([13, 23]),
    ]);
    expect(snap.rhr.points[2].contributingPeriodCount, 0);
    expect(snap.rhr.latest?.cycleDay, 4);
    expect(snap.rhr.points.any((p) => p.cycleDay == 5), isFalse);
    expect(
      snap.rhr.eligibleNights.any((c) => c.cycleDay == 5 && c.metric.value == 99),
      isTrue,
    );
    expect(snap.hrv.points, hasLength(4));
  });

  test('HRV and RHR stay independent with no cross-metric fallback', () {
    final snap = _snap(
      starts: const ['2026-08-01', '2026-09-01'],
      rows: [
        ..._nightsOn('2026-08-01', [10, 11, 12], [1, null, null]),
        ..._nightsOn('2026-09-01', [20, 21, 22], [8, null, null]),
      ],
    );
    expect(snap.reason, CycleMediansReason.available);
    expect(snap.rhr.available, isTrue);
    expect(snap.rhr.latest?.cycleDay, 3);
    expect(snap.hrv.available, isFalse);
    expect(snap.hrv.latest, isNull);
    expect(snap.hrv.points, isEmpty);
    expect(snap.hrv.qualifyingDayCount, 1);
    expect(snap.hrv.eligibleNightCount, 2);
  });

  test('source envelope and confidence match parseCycleNightSource', () {
    const day = '2026-08-24';
    const start = '2026-08-01';
    final row = _night(
      day,
      rhr: 54,
      hrv: 48,
      rhrConfidence: 0.81,
      hrvConfidence: 0.44,
      rhrNote: 'low30',
    );
    final parsed = parseCycleNightSource(row, algoVersion: kAlgoVersion);
    final snap = _snap(
      starts: const [start, '2026-09-01'],
      rows: [
        row,
        _night(cycleAddDays(start, 1), rhr: 50, hrv: 40, rhrConfidence: 0.81),
        _night(cycleAddDays(start, 2), rhr: 51, hrv: 41),
        _night('2026-09-01', rhr: 52, hrv: 42, rhrConfidence: 0.81),
        _night('2026-09-02', rhr: 53, hrv: 43),
        _night('2026-09-03', rhr: 55, hrv: 45),
      ],
    );
    final contributor = snap.rhr.eligibleNights.singleWhere(
      (c) => c.nightDay == day,
    );
    expect(contributor.nightDay, day);
    expect(contributor.startDay, start);
    expect(contributor.metric.value, parsed.rhr?.value);
    expect(contributor.metric.confidence, parsed.rhr?.confidence);
    expect(contributor.metric.note, parsed.rhr?.note);
    expect(contributor.sleepSource, parsed.sleepSource);
    expect(contributor.sleepStart, parsed.windowStart);
    expect(contributor.sleepEnd, parsed.windowEnd);
    expect(contributor.algoVersion, kAlgoVersion);
  });

  test('malformed sibling metric does not drop the other', () {
    const startA = '2026-08-01';
    const startB = '2026-09-01';
    final snap = _snap(
      starts: const [startA, startB],
      rows: [
        _night(startA, rhr: 0, hrv: 40),
        _night(cycleAddDays(startA, 1), rhr: 51, hrv: -1),
        _night(cycleAddDays(startA, 2), rhr: 52, hrv: 42),
        _night(cycleAddDays(startA, 3), rhr: 53, hrv: 43),
        _night(startB, rhr: 60, hrv: 50),
        _night(cycleAddDays(startB, 1), rhr: 61, hrv: 51),
        _night(cycleAddDays(startB, 2), rhr: 62, hrv: 52),
        _night(cycleAddDays(startB, 3), rhr: 63, hrv: 53),
      ],
    );
    expect(snap.rhr.points[0].median, isNull);
    expect(snap.rhr.points[0].contributingPeriodCount, 1);
    expect(snap.rhr.points[1].median, ana.median([51, 61]));
    expect(snap.hrv.points[0].median, ana.median([40, 50]));
    expect(snap.hrv.points[1].median, isNull);
    expect(snap.unreadableNightCount, greaterThan(0));
    expect(snap.partial, isTrue);
  });

  test('tracking disabled, empty starts, and estimate flags stay distinct', () {
    expect(
      _snap(settings: const CycleSettings(
        enabled: false,
        estimatesEnabled: true,
        lengthReviewEnabled: true,
      )).reason,
      CycleMediansReason.trackingDisabled,
    );
    expect(_snap(starts: const []).reason, CycleMediansReason.emptyStarts);
    expect(
      _snap(
        log: _log(const [], _anchor, extra: [
          {'date': '2026-08-24', 'kind': 'removed'},
        ]),
      ).reason,
      CycleMediansReason.emptyStarts,
    );
    final still = _snap(
      settings: const CycleSettings(
        enabled: true,
        estimatesEnabled: false,
        situation: CycleSituation.none,
        lengthReviewEnabled: false,
      ),
      starts: const ['2026-08-01', '2026-09-01'],
      rows: [
        ..._nightsOn('2026-08-01', [10, 11, 12], [1, 2, 3]),
        ..._nightsOn('2026-09-01', [20, 21, 22], [8, 9, 10]),
      ],
    );
    expect(still.reason, CycleMediansReason.available);
  });

  test('future, corrupt, and duplicate starts follow existing as-of rules', () {
    final futureCorrupt = _snap(
      log: parseCycleLog(
        startRows: const [
          {'date': '2026-08-01', 'kind': 'start'},
          {'date': '2026-09-01', 'kind': 'start'},
          {'date': '2026-09-20', 'kind': ''},
        ],
        observationRows: const [],
        asOf: '2026-09-15',
      ),
      rows: [
        ..._nightsOn('2026-08-01', [10, 11, 12], [1, 2, 3]),
        ..._nightsOn('2026-09-01', [20, 21, 22], [8, 9, 10]),
      ],
    );
    expect(futureCorrupt.reason, CycleMediansReason.available);

    final duplicate = _snap(
      log: _log(const ['2026-08-24', '2026-08-24'], _anchor),
    );
    expect(duplicate.reason, CycleMediansReason.unreadableStarts);
    expect(duplicate.rhr.points, isEmpty);

    final asOfCorrupt = _snap(
      log: parseCycleLog(
        startRows: const [
          {'date': '2026-08-01', 'kind': 'start'},
          {'date': '2026-08-10', 'kind': ''},
        ],
        observationRows: const [],
        asOf: '2026-09-15',
      ),
    );
    expect(asOfCorrupt.reason, CycleMediansReason.unreadableStarts);
  });

  test('later starts do not close an open window period', () {
    final window = cycleMedianWindow(anchorEnd: _anchor, pageOffset: 0);
    final snap = buildCycleMediansSnapshot(
      settings: _settings,
      log: parseCycleLog(
        startRows: const [
          {'date': '2026-06-15', 'kind': 'start'},
          {'date': '2026-08-01', 'kind': 'start'},
          {'date': '2026-10-15', 'kind': 'start'},
        ],
        observationRows: const [],
      ),
      algoVersion: kAlgoVersion,
      window: window,
      rows: [
        ..._nightsOn('2026-06-15', [10, 11, 12], [1, 2, 3]),
        ..._nightsOn('2026-08-01', [20, 21, 22], [8, 9, 10]),
        _night('2026-09-20', rhr: 99, hrv: 99),
      ],
    );
    expect(snap.periods.map((p) => p.startDay), ['2026-06-15', '2026-08-01']);
    expect(snap.periods.last.open, isTrue);
    expect(snap.periods.last.endDay, window.endDay);
    expect(snap.reason, CycleMediansReason.available);
    expect(
      snap.rhr.eligibleNights.any((c) => c.nightDay == '2026-09-20'),
      isFalse,
    );
  });

  test('long closed and open periods are excluded without contaminating valid ones',
      () {
    final mixed = _snap(
      starts: const ['2026-01-01', '2026-04-15', '2026-08-01', '2026-08-25'],
      rows: [
        ..._nightsOn('2026-01-01', [99, 98, 97], [9, 8, 7]),
        ..._nightsOn('2026-08-01', [10, 11, 12], [1, 2, 3]),
        ..._nightsOn('2026-08-25', [20, 21, 22], [8, 9, 10]),
      ],
    );
    expect(mixed.reason, CycleMediansReason.available);
    expect(mixed.partial, isTrue);
    expect(mixed.excludedPeriodCount, 2);
    expect(
      mixed.excludedPeriods.map((e) => e.reason),
      [
        CycleMedianPeriodExcludeReason.longClosed,
        CycleMedianPeriodExcludeReason.longClosed,
      ],
    );
    expect(mixed.periods.map((p) => p.startDay), ['2026-08-01', '2026-08-25']);
    expect(mixed.rhr.latest?.median, ana.median([12, 22]));
    expect(
      mixed.rhr.eligibleNights.any((c) => c.startDay == '2026-01-01'),
      isFalse,
    );

    final allLong = _snap(starts: const ['2026-01-01', '2026-06-01']);
    expect(allLong.reason, CycleMediansReason.longPeriods);
    expect(allLong.rhr.points, isEmpty);
    expect(allLong.rhr.latest, isNull);
    expect(allLong.rhr.eligibleNightCount, 0);
    expect(allLong.partial, isTrue);
    expect(allLong.excludedPeriodCount, 2);
  });

  test('closed gap 60 and open age 60 stay valid; 61 is long', () {
    const start = '2026-07-17';
    const next = '2026-09-15';
    expect(cycleDiffDays(start, next), 60);
    final closed = _snap(
      starts: const [start, next],
      rows: [
        ..._nightsOn(start, [10, 11, 12], [1, 2, 3]),
        ..._nightsOn(next, [20, 21, 22], [8, 9, 10]),
      ],
    );
    expect(closed.excludedPeriodCount, 0);
    expect(closed.periods, hasLength(2));
    expect(closed.periods.first.open, isFalse);
    expect(closed.periods.last.startDay, next);

    const longNext = '2026-09-16';
    expect(cycleDiffDays(start, longNext), 61);
    final longClosed = _snap(
      anchorEnd: '2026-09-16',
      starts: const [start, longNext],
    );
    expect(
      longClosed.excludedPeriods.any(
        (e) => e.reason == CycleMedianPeriodExcludeReason.longClosed,
      ),
      isTrue,
    );

    const openStart = '2026-07-18';
    expect(cycleDiffDays(openStart, _anchor) + 1, 60);
    final open = _snap(
      starts: const ['2026-06-01', openStart],
      rows: [
        ..._nightsOn('2026-06-01', [10, 11, 12], [1, 2, 3]),
        ..._nightsOn(openStart, [20, 21, 22], [8, 9, 10]),
      ],
    );
    expect(open.periods.last.open, isTrue);
    expect(open.reason, CycleMediansReason.available);

    const longOpen = '2026-07-17';
    expect(cycleDiffDays(longOpen, _anchor) + 1, 61);
    final tooOpen = _snap(starts: const [longOpen]);
    expect(tooOpen.reason, CycleMediansReason.longPeriods);
    expect(tooOpen.excludedPeriods.single.reason,
        CycleMedianPeriodExcludeReason.longOpen);
  });

  test('exact algo, skipped, imported, and stale correction keep parse refusals',
      () {
    const a = '2026-08-01';
    const b = '2026-09-01';
    final snap = _snap(
      starts: const [a, b],
      rows: [
        _night(a, rhr: 10, hrv: 1),
        _night(cycleAddDays(a, 1), rhr: 11, hrv: 2),
        _night(cycleAddDays(a, 2), rhr: 12, hrv: 3),
        _night(b, rhr: 20, hrv: 8),
        _night(cycleAddDays(b, 1), rhr: 21, hrv: 9),
        _night(cycleAddDays(b, 2), rhr: 22, hrv: 10),
        _night(a, rhr: 99, hrv: 99, algo: kAlgoVersion - 1),
        _night('2026-08-10', rhr: 33, hrv: 33, skipped: true),
        _night('2026-08-11', rhr: 33, hrv: 33, imported: true),
        _night('2026-08-12', rhr: 33, hrv: 33, payloadUnreadable: true),
        _night(
          '2026-08-13',
          rhr: 33,
          hrv: 33,
          computedAtMs: 10,
          resultComputedAtMs: 20,
        ),
      ],
    );
    expect(snap.reason, CycleMediansReason.available);
    expect(snap.rhr.eligibleNights.map((c) => c.metric.value), isNot(contains(99)));
    expect(snap.rhr.eligibleNights.map((c) => c.metric.value), isNot(contains(33)));
    expect(snap.excludedNightCount, 3);
    expect(snap.unreadableNightCount, 1);
    expect(snap.partial, isTrue);
  });

  test('duplicate eligible rows on one date are unreadable, not a silent pick',
      () {
    const a = '2026-08-01';
    const b = '2026-09-01';
    final snap = _snap(
      starts: const [a, b],
      rows: [
        _night(a, rhr: 10, hrv: 1),
        _night(a, rhr: 99, hrv: 1),
        _night(cycleAddDays(a, 1), rhr: 11, hrv: 2),
        _night(cycleAddDays(a, 2), rhr: 12, hrv: 3),
        _night(cycleAddDays(a, 3), rhr: 13, hrv: 4),
        _night(b, rhr: 20, hrv: 8),
        _night(cycleAddDays(b, 1), rhr: 21, hrv: 9),
        _night(cycleAddDays(b, 2), rhr: 22, hrv: 10),
        _night(cycleAddDays(b, 3), rhr: 23, hrv: 11),
      ],
    );
    expect(snap.unreadableNightCount, 1);
    expect(snap.rhr.points.first.contributingPeriodCount, 1);
    expect(snap.rhr.points.first.median, isNull);
    expect(
      snap.rhr.eligibleNights.any((c) => c.nightDay == a),
      isFalse,
    );
  });

  test('zero MAD leaves proxy null; raw-night proxy is not the median span', () {
    final zero = _snap(
      starts: const ['2026-08-01', '2026-09-01'],
      rows: [
        ..._nightsOn('2026-08-01', [54, 54, 54], [40, 40, 40]),
        ..._nightsOn('2026-09-01', [54, 54, 54], [40, 40, 40]),
      ],
    );
    expect(zero.rhr.spread.proxy, isNull);
    expect(zero.rhr.spread.medianSpan, 0);
    expect(zero.rhr.spread.sampleCount, 6);

    final raw = _snap(
      starts: const ['2026-08-01', '2026-09-01'],
      rows: [
        ..._nightsOn('2026-08-01', [50, 50, 50], [10, 10, 10]),
        ..._nightsOn('2026-09-01', [60, 60, 60], [30, 30, 30]),
      ],
    );
    final rhrNights = [50.0, 50.0, 50.0, 60.0, 60.0, 60.0];
    final expected = ana.mdc(ana.robustBaseline(rhrNights, minValid: 3));
    expect(raw.rhr.spread.proxy, expected);
    expect(raw.rhr.spread.medianSpan, 0);
    expect(raw.rhr.spread.proxy, isNotNull);
    expect(raw.hrv.spread.proxy, isNot(raw.rhr.spread.proxy));
  });

  test('spread uses eligible nights even when the chart gate fails', () {
    final snap = _snap(
      starts: const ['2026-08-24'],
      rows: _nightsOn('2026-08-24', [50, 51, 60], [10, 11, 12]),
    );
    expect(snap.rhr.available, isFalse);
    expect(snap.rhr.spread.medianSpan, isNull);
    expect(snap.rhr.spread.sampleCount, 3);
    expect(
      snap.rhr.spread.proxy,
      ana.mdc(ana.robustBaseline([50, 51, 60], minValid: 3)),
    );
  });
}
