import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:openstrap_edge/openband/cycle_comparison_data.dart';
import 'package:openstrap_edge/openband/cycle_data.dart';
import 'package:openstrap_edge/openband/cycle_measurements_data.dart';
import 'package:openstrap_edge/openband/cycle_medians_data.dart';

typedef _SetenvNative = Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32);
typedef _SetenvDart = int Function(Pointer<Utf8>, Pointer<Utf8>, int);
typedef _UnsetenvNative = Int32 Function(Pointer<Utf8>);
typedef _UnsetenvDart = int Function(Pointer<Utf8>);
typedef _TzsetNative = Void Function();
typedef _TzsetDart = void Function();

void _setProcessTz(String? tz) {
  final lib = DynamicLibrary.process();
  final key = 'TZ'.toNativeUtf8();
  try {
    if (tz == null) {
      lib.lookupFunction<_UnsetenvNative, _UnsetenvDart>('unsetenv')(key);
    } else {
      final value = tz.toNativeUtf8();
      lib.lookupFunction<_SetenvNative, _SetenvDart>('setenv')(key, value, 1);
      calloc.free(value);
    }
    lib.lookupFunction<_TzsetNative, _TzsetDart>('tzset')();
  } finally {
    calloc.free(key);
  }
}

const _settings = CycleSettings(
  enabled: true,
  estimatesEnabled: true,
  lengthReviewEnabled: false,
);

const _paperStarts = [
  '2026-05-28',
  '2026-06-29',
  '2026-07-31',
  '2026-08-24',
];
const _anchor = '2026-09-15';
const _sameDayRhr = [50.0, 52.0, 54.0];
const _sameDayHrv = [45.0, 47.0, 49.0];

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

Map<String, Object?> _corruptMetricPayload(
  String day, {
  double? rhr,
  double? hrv,
  bool corruptRhr = false,
  bool corruptHrv = false,
}) {
  final payload = cycleNightSourcePayload(
    rhr: rhr,
    hrv: hrv,
    onsetMs: cycleNightOnsetMs(day),
    offsetMs: cycleNightOffsetMs(day),
  );
  final clinical = Map<String, Object?>.from(payload['clinical']! as Map);
  if (corruptRhr) clinical['resting_hr'] = 'bad';
  if (corruptHrv) clinical['rmssd_sleep_session'] = 'bad';
  payload['clinical'] = clinical;
  return payload;
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
  Map<String, Object?>? payload,
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
        : payload ??
            cycleNightSourcePayload(
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

List<CycleNightSourceRow> _paperNights(
  String start, {
  num rhrAdd = 0,
  num hrvAdd = 0,
}) {
  return [
    for (var i = 0; i < kCyclePaperRhr.length; i++)
      if ((kCyclePaperRhr[i] != null) || (kCyclePaperHrv[i] != null))
        _night(
          cycleAddDays(start, i),
          rhr: kCyclePaperRhr[i] == null ? null : kCyclePaperRhr[i]! + rhrAdd,
          hrv: kCyclePaperHrv[i] == null ? null : kCyclePaperHrv[i]! + hrvAdd,
        ),
  ];
}

List<CycleNightSourceRow> _paperComparisonRows() {
  final rows = <CycleNightSourceRow>[
    for (var i = 0; i < _paperStarts.length; i++)
      ..._paperNights(
        _paperStarts[i],
        rhrAdd: i == _paperStarts.length - 1 ? 2 : 0,
        hrvAdd: i == _paperStarts.length - 1 ? 3 : 0,
      ),
  ];
  final byDay = <String, CycleNightSourceRow>{
    for (final row in rows) row.day: row,
  };
  for (var i = 0; i < 3; i++) {
    final start = _paperStarts[i];
    final rhrDay = cycleAddDays(start, 22);
    final hrvDay = cycleAddDays(start, 21);
    final rhrPrev = parseCycleNightSource(
      byDay[rhrDay]!,
      algoVersion: kAlgoVersion,
    );
    byDay[rhrDay] = _night(
      rhrDay,
      rhr: _sameDayRhr[i],
      hrv: rhrPrev.hrv?.value,
    );
    final hrvPrev = parseCycleNightSource(
      byDay[hrvDay]!,
      algoVersion: kAlgoVersion,
    );
    byDay[hrvDay] = _night(
      hrvDay,
      rhr: hrvPrev.rhr?.value,
      hrv: _sameDayHrv[i],
    );
  }
  return byDay.values.toList();
}

List<double> _paperPrior21Rhr() => [
      for (var i = 1; i <= 21; i++)
        if (kCyclePaperRhr[i] != null) kCyclePaperRhr[i]! + 2,
    ];

List<double> _paperPrior21Hrv() => [
      for (var i = 0; i <= 20; i++)
        if (kCyclePaperHrv[i] != null) kCyclePaperHrv[i]! + 3,
    ];

CycleComparisonSnapshot _snap({
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
  return buildCycleComparisonSnapshot(
    settings: settings,
    log: log ?? _log(starts, window.endDay),
    algoVersion: algoVersion ?? kAlgoVersion,
    window: window,
    rows: rows,
  );
}

void main() {
  test('kAlgoVersion remains the cycle-night pin', () {
    expect(kAlgoVersion, 96);
  });

  test('reuses the fixed-anchor twelve-month window and year-1 query pad', () {
    final page0 = cycleMedianWindow(anchorEnd: _anchor, pageOffset: 0);
    expect(page0.startDay, '2025-09-16');
    expect(page0.endDay, '2026-09-15');
    expect(cycleComparisonQueryStart(page0), '2025-08-26');
    expect(cycleDiffDays(cycleComparisonQueryStart(page0), page0.startDay), 21);

    final page1 = cycleMedianWindow(anchorEnd: _anchor, pageOffset: 1);
    expect(page1.startDay, '2024-09-16');
    expect(page1.endDay, '2025-09-15');
    expect(cycleAddDays(page1.endDay, 1), page0.startDay);

    final year1 = cycleMedianWindow(anchorEnd: '0001-12-31', pageOffset: 0);
    expect(year1.startDay, '0001-01-01');
    expect(cycleComparisonQueryStart(year1), '0001-01-01');

    expect(
      () => cycleMedianWindow(anchorEnd: '0001-01-31', pageOffset: 0),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => cycleMedianWindow(anchorEnd: '9999-12-31', pageOffset: 0),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => cycleMedianWindow(anchorEnd: _anchor, pageOffset: -1),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('Paper fixture latest nights, prior-21, and same-day use ana.mean/z', () {
    final snap = _snap(rows: _paperComparisonRows());
    expect(snap.reason, CycleComparisonReason.available);
    expect(snap.window.startDay, '2025-09-16');
    expect(snap.window.endDay, '2026-09-15');
    expect(snap.partial, isFalse);

    expect(snap.rhr.latestReason, CycleComparisonLatestReason.available);
    expect(snap.rhr.latest?.nightDay, '2026-09-15');
    expect(snap.rhr.latest?.metric.value, 56);
    expect(snap.rhr.latest?.cycleDay, 23);
    expect(snap.rhr.latest?.startDay, '2026-08-24');
    expect(snap.rhr.latest?.sleepSource, 'auto');
    expect(snap.rhr.latest?.algoVersion, kAlgoVersion);

    expect(snap.hrv.latestReason, CycleComparisonLatestReason.available);
    expect(snap.hrv.latest?.nightDay, '2026-09-14');
    expect(snap.hrv.latest?.metric.value, 51);
    expect(snap.hrv.latest?.cycleDay, 22);
    expect(snap.hrv.latest?.nightDay, isNot(snap.rhr.latest?.nightDay));
    expect(snap.hrv.latest?.cycleDay, isNot(snap.rhr.latest?.cycleDay));

    final rhrPrior = _paperPrior21Rhr();
    expect(snap.rhr.prior21.reason, CycleComparisonPrior21Reason.available);
    expect(snap.rhr.prior21.startDay, '2026-08-25');
    expect(snap.rhr.prior21.endDay, '2026-09-14');
    expect(snap.rhr.prior21.count, 17);
    expect(snap.rhr.prior21.count, rhrPrior.length);
    expect(snap.rhr.prior21.mean, ana.mean(rhrPrior));
    expect(snap.rhr.prior21.delta, 56 - ana.mean(rhrPrior)!);
    expect(snap.rhr.prior21.z, ana.z(56, rhrPrior));

    final hrvPrior = _paperPrior21Hrv();
    expect(snap.hrv.prior21.reason, CycleComparisonPrior21Reason.available);
    expect(snap.hrv.prior21.startDay, '2026-08-24');
    expect(snap.hrv.prior21.endDay, '2026-09-13');
    expect(snap.hrv.prior21.count, 15);
    expect(snap.hrv.prior21.mean, ana.mean(hrvPrior));
    expect(snap.hrv.prior21.delta, 51 - ana.mean(hrvPrior)!);
    expect(snap.hrv.prior21.z, ana.z(51, hrvPrior));

    expect(snap.rhr.sameDay.reason, CycleComparisonSameDayReason.available);
    expect(snap.rhr.sameDay.cycleDay, 23);
    expect(snap.rhr.sameDay.count, 3);
    expect(snap.rhr.sameDay.mean, ana.mean(_sameDayRhr));
    expect(snap.rhr.sameDay.delta, 56 - ana.mean(_sameDayRhr)!);
    expect(snap.rhr.sameDay.z, ana.z(56, _sameDayRhr));
    expect(snap.rhr.sameDay.z, 2);
    expect(
      snap.rhr.sameDay.contributors.map((c) => c.metric.value),
      _sameDayRhr,
    );

    expect(snap.hrv.sameDay.reason, CycleComparisonSameDayReason.available);
    expect(snap.hrv.sameDay.cycleDay, 22);
    expect(snap.hrv.sameDay.count, 3);
    expect(snap.hrv.sameDay.mean, ana.mean(_sameDayHrv));
    expect(snap.hrv.sameDay.delta, 51 - ana.mean(_sameDayHrv)!);
    expect(snap.hrv.sameDay.z, ana.z(51, _sameDayHrv));
    expect(
      snap.hrv.sameDay.contributors.map((c) => c.metric.value),
      _sameDayHrv,
    );
  });

  test('latest is the newest accepted night in the window, not median day', () {
    final snap = _snap(
      starts: const ['2026-06-29', '2026-07-31', '2026-08-24'],
      rows: [
        for (final start in ['2026-06-29', '2026-07-31', '2026-08-24'])
          ..._paperNights(start),
      ],
    );
    expect(snap.rhr.latest?.nightDay, '2026-09-15');
    expect(snap.rhr.latest?.metric.value, 54);
    expect(snap.rhr.latest?.cycleDay, 23);
    expect(snap.hrv.latest?.nightDay, '2026-09-14');
    expect(snap.hrv.latest?.metric.value, 48);
    expect(snap.hrv.latest?.cycleDay, 22);

    final compared = _snap(rows: _paperComparisonRows());
    final medians = buildCycleMediansSnapshot(
      settings: _settings,
      log: _log(_paperStarts, '2026-09-15'),
      algoVersion: kAlgoVersion,
      window: cycleMedianWindow(anchorEnd: _anchor, pageOffset: 0),
      rows: _paperComparisonRows(),
    );
    expect(compared.rhr.latest?.metric.value, 56);
    expect(medians.rhr.latest?.cycleDay, 23);
    expect(compared.rhr.latest?.metric.value, isNot(medians.rhr.latest?.median));
  });

  test('prior-21 may extend before the window and keeps unassigned nights', () {
    const latest = '2025-09-16';
    const pad = '2025-08-26';
    const inside = '2025-09-10';
    const tooOld = '2025-08-25';
    final snap = _snap(
      starts: const [],
      rows: [
        _night(tooOld, rhr: 40, hrv: 10),
        _night(pad, rhr: 50, hrv: 20),
        _night(inside, rhr: 52, hrv: 22),
        _night(latest, rhr: 54, hrv: 24),
      ],
    );
    expect(snap.rhr.latest?.nightDay, latest);
    expect(snap.rhr.latest?.assignment, isNull);
    expect(snap.rhr.prior21.startDay, pad);
    expect(snap.rhr.prior21.endDay, '2025-09-15');
    expect(snap.rhr.prior21.count, 2);
    expect(
      snap.rhr.prior21.contributors.map((c) => c.nightDay),
      [pad, inside],
    );
    expect(
      snap.rhr.prior21.contributors.map((c) => c.assignment),
      [null, null],
    );
    expect(snap.rhr.sameDay.reason, CycleComparisonSameDayReason.emptyStarts);
    expect(snap.hrv.latest?.nightDay, latest);
    expect(snap.hrv.prior21.count, 2);
  });

  test('leap and DST civil labels stay consecutive under Los Angeles', () {
    final originalTz = Platform.environment['TZ'];
    _setProcessTz('America/Los_Angeles');
    addTearDown(() => _setProcessTz(originalTz));
    expect(
      DateTime(2026, 3, 8).timeZoneOffset,
      const Duration(hours: -8),
    );
    expect(
      DateTime(2026, 11, 1).timeZoneOffset,
      const Duration(hours: -7),
    );
    final leap = cycleMedianWindow(anchorEnd: '2024-09-15', pageOffset: 0);
    expect(leap.expectedNights, contains('2024-02-29'));
    expect(leap.expectedNightCount, 366);
    expect(
      cycleCivilDaysInclusive('2026-03-07', '2026-03-10'),
      ['2026-03-07', '2026-03-08', '2026-03-09', '2026-03-10'],
    );
    expect(cycleDiffDays('2026-03-08', '2026-03-09'), 1);
    final snap = _snap(
      anchorEnd: '2026-03-10',
      starts: const ['2026-03-07'],
      rows: [
        _night('2026-03-07', rhr: 50),
        _night('2026-03-08', rhr: 51),
        _night('2026-03-09', rhr: 52),
        _night('2026-03-10', rhr: 53),
      ],
    );
    expect(snap.window.endDay, '2026-03-10');
    expect(snap.rhr.latest?.nightDay, '2026-03-10');
    expect(snap.rhr.prior21.count, 3);
    expect(
      snap.rhr.prior21.contributors.map((c) => c.nightDay),
      ['2026-03-07', '2026-03-08', '2026-03-09'],
    );
  });

  test('window and prior-21 bounds are inclusive except the latest night', () {
    final snap = _snap(
      starts: const ['2026-08-01'],
      rows: [
        _night('2026-08-25', rhr: 40),
        _night('2026-09-14', rhr: 50),
        _night('2026-09-15', rhr: 56),
        _night('2026-09-16', rhr: 99),
      ],
    );
    expect(snap.rhr.latest?.nightDay, '2026-09-15');
    expect(snap.rhr.prior21.startDay, '2026-08-25');
    expect(snap.rhr.prior21.endDay, '2026-09-14');
    expect(
      snap.rhr.prior21.contributors.map((c) => c.nightDay),
      ['2026-08-25', '2026-09-14'],
    );
    expect(
      snap.rhr.prior21.contributors.any((c) => c.nightDay == '2026-09-15'),
      isFalse,
    );
    expect(
      snap.rhr.prior21.contributors.any((c) => c.nightDay == '2026-09-16'),
      isFalse,
    );
  });

  test('starts after window.endDay do not close the open period', () {
    final window = cycleMedianWindow(anchorEnd: _anchor, pageOffset: 0);
    final snap = buildCycleComparisonSnapshot(
      settings: _settings,
      log: parseCycleLog(
        startRows: const [
          {'date': '2026-05-28', 'kind': 'start'},
          {'date': '2026-06-29', 'kind': 'start'},
          {'date': '2026-07-31', 'kind': 'start'},
          {'date': '2026-08-24', 'kind': 'start'},
          {'date': '2026-10-01', 'kind': 'start'},
        ],
        observationRows: const [],
        asOf: window.endDay,
      ),
      algoVersion: kAlgoVersion,
      window: window,
      rows: _paperComparisonRows(),
    );
    expect(snap.rhr.latest?.startDay, '2026-08-24');
    expect(snap.rhr.sameDay.reason, CycleComparisonSameDayReason.available);
    expect(snap.rhr.sameDay.count, 3);
    expect(
      snap.rhr.latest?.nightDay.compareTo(window.endDay) ?? 1,
      lessThanOrEqualTo(0),
    );
  });

  test('duplicate and unreadable starts withhold only the cycle-day reference',
      () {
    final rows = [
      _night('2026-09-14', rhr: 54, hrv: 48),
      _night('2026-09-15', rhr: 56, hrv: 50),
    ];
    final duplicate = _snap(
      log: _log(const ['2026-08-24', '2026-08-24'], _anchor),
      rows: rows,
    );
    expect(duplicate.rhr.latest?.metric.value, 56);
    expect(duplicate.rhr.prior21.count, 1);
    expect(
      duplicate.rhr.sameDay.reason,
      CycleComparisonSameDayReason.unreadableStarts,
    );
    expect(duplicate.rhr.latest?.assignment, isNull);

    final corrupt = _snap(
      log: parseCycleLog(
        startRows: const [
          {'date': '2026-08-24', 'kind': 'start'},
          {'date': '2026-08-10', 'kind': ''},
        ],
        observationRows: const [],
        asOf: _anchor,
      ),
      rows: rows,
    );
    expect(corrupt.rhr.latest?.nightDay, '2026-09-15');
    expect(
      corrupt.rhr.sameDay.reason,
      CycleComparisonSameDayReason.unreadableStarts,
    );
  });

  test('duplicate night rows are unreadable and do not pick either value', () {
    final snap = _snap(
      starts: const ['2026-08-24'],
      rows: [
        _night('2026-09-14', rhr: 50, hrv: 40),
        _night('2026-09-15', rhr: 56, hrv: 51),
        _night('2026-09-15', rhr: 99, hrv: 99),
      ],
    );
    expect(snap.unreadableNightCount, 1);
    expect(snap.partial, isTrue);
    expect(snap.rhr.latest?.nightDay, '2026-09-14');
    expect(snap.rhr.latest?.metric.value, 50);
    expect(snap.hrv.latest?.metric.value, 40);
  });

  test('long-period and unassigned nights stay as latest and prior-21', () {
    final long = _snap(
      starts: const ['2025-10-01'],
      rows: [
        _night('2026-09-01', rhr: 50, hrv: 40),
        _night('2026-09-14', rhr: 54, hrv: 48),
        _night('2026-09-15', rhr: 56, hrv: 51),
      ],
    );
    expect(long.rhr.latest?.nightDay, '2026-09-15');
    expect(long.rhr.latest?.startDay, '2025-10-01');
    expect(long.rhr.prior21.reason, CycleComparisonPrior21Reason.available);
    expect(long.rhr.prior21.count, 2);
    expect(
      long.rhr.sameDay.reason,
      CycleComparisonSameDayReason.longLatestPeriod,
    );

    final unassigned = _snap(
      starts: const ['2026-09-12'],
      rows: [
        _night('2026-08-25', rhr: 50, hrv: 40),
        _night('2026-09-01', rhr: 52, hrv: 42),
        _night('2026-09-10', rhr: 56, hrv: 51),
      ],
    );
    expect(unassigned.rhr.latest?.nightDay, '2026-09-10');
    expect(unassigned.rhr.latest?.assignment, isNull);
    expect(unassigned.hrv.latest?.nightDay, '2026-09-10');
    expect(unassigned.hrv.latest?.assignment, isNull);
    expect(unassigned.rhr.prior21.reason, CycleComparisonPrior21Reason.available);
    expect(unassigned.rhr.prior21.count, 2);
    expect(unassigned.hrv.prior21.reason, CycleComparisonPrior21Reason.available);
    expect(unassigned.hrv.prior21.count, 2);
    expect(
      unassigned.rhr.sameDay.reason,
      CycleComparisonSameDayReason.unassignedLatest,
    );
    expect(
      unassigned.hrv.sameDay.reason,
      CycleComparisonSameDayReason.unassignedLatest,
    );
  });

  test('earlier long periods are dropped individually from same-day', () {
    final snap = _snap(
      starts: const [
        '2025-10-01',
        '2026-05-28',
        '2026-06-29',
        '2026-07-31',
        '2026-08-24',
      ],
      rows: [
        _night('2025-10-23', rhr: 10, hrv: 10),
        ..._paperComparisonRows(),
      ],
    );
    expect(snap.partial, isTrue);
    expect(snap.rhr.sameDay.count, 3);
    expect(
      snap.rhr.sameDay.contributors.any((c) => c.startDay == '2025-10-01'),
      isFalse,
    );
    expect(snap.rhr.latest?.metric.value, 56);
  });

  test('closed gap 60 and open age 60 stay eligible; 61 withholds same-day', () {
    const start = '2026-07-17';
    const next = '2026-09-15';
    expect(cycleDiffDays(start, next), 60);
    final closed = _snap(
      starts: const [start, next],
      rows: [
        _night(cycleAddDays(start, 0), rhr: 50),
        _night(next, rhr: 56),
      ],
    );
    expect(closed.rhr.latest?.cycleDay, 1);
    expect(
      closed.rhr.sameDay.reason,
      isNot(CycleComparisonSameDayReason.longLatestPeriod),
    );

    const longOpen = '2026-07-17';
    expect(cycleDiffDays(longOpen, _anchor) + 1, 61);
    final tooOpen = _snap(
      starts: const [longOpen],
      rows: [
        _night('2026-09-14', rhr: 54),
        _night('2026-09-15', rhr: 56),
      ],
    );
    expect(
      tooOpen.rhr.sameDay.reason,
      CycleComparisonSameDayReason.longLatestPeriod,
    );
    expect(tooOpen.rhr.latest?.metric.value, 56);
    expect(tooOpen.rhr.prior21.count, 1);
  });

  test('exact algo, skipped, imported, and stale correction keep parse refusals',
      () {
    final snap = _snap(
      starts: const ['2026-08-24'],
      rows: [
        _night('2026-09-10', rhr: 50, hrv: 40),
        _night('2026-09-11', rhr: 51, hrv: 41, skipped: true),
        _night('2026-09-12', rhr: 52, hrv: 42, imported: true),
        _night('2026-09-13', rhr: 53, hrv: 43, payloadUnreadable: true),
        _night(
          '2026-09-14',
          rhr: 54,
          hrv: 44,
          computedAtMs: 10,
          resultComputedAtMs: 20,
        ),
        _night('2026-09-15', rhr: 56, hrv: 51, algo: kAlgoVersion - 1),
        _night('2026-09-15', rhr: 99, hrv: 99, algo: kAlgoVersion + 1),
      ],
    );
    expect(snap.rhr.latest?.nightDay, '2026-09-10');
    expect(snap.rhr.latest?.metric.value, 50);
    expect(snap.excludedNightCount, 3);
    expect(snap.unreadableNightCount, 1);
    expect(snap.partial, isTrue);
  });

  test('malformed sibling metric does not drop the other', () {
    final badHrv = cycleNightSourcePayload(
      rhr: 56,
      hrv: 51,
      onsetMs: cycleNightOnsetMs('2026-09-15'),
      offsetMs: cycleNightOffsetMs('2026-09-15'),
    );
    final clinical = Map<String, Object?>.from(badHrv['clinical']! as Map);
    clinical['rmssd_sleep_session'] = 'bad';
    badHrv['clinical'] = clinical;
    final snap = _snap(
      starts: const ['2026-08-24'],
      rows: [
        _night('2026-09-14', rhr: 54, hrv: 48),
        _night('2026-09-15', payload: badHrv),
      ],
    );
    expect(snap.rhr.latest?.nightDay, '2026-09-15');
    expect(snap.rhr.latest?.metric.value, 56);
    expect(snap.hrv.latest?.nightDay, '2026-09-14');
    expect(snap.hrv.latest?.metric.value, 48);
    expect(snap.unreadableNightCount, 1);
    expect(snap.partial, isTrue);
    expect(snap.hrv.unreadableCount, 1);
    expect(snap.rhr.unreadableCount, 0);
  });

  test('prior-21 needs two unique nights; same-day needs three earlier periods',
      () {
    final one = _snap(
      starts: const ['2026-08-24'],
      rows: [
        _night('2026-09-15', rhr: 56, hrv: 51),
      ],
    );
    expect(one.rhr.prior21.reason, CycleComparisonPrior21Reason.insufficientNights);
    expect(one.rhr.prior21.count, 0);
    expect(one.rhr.prior21.mean, isNull);
    expect(one.rhr.sameDay.reason, CycleComparisonSameDayReason.insufficientPeriods);
    expect(one.rhr.sameDay.count, 0);

    final twoPrior = _snap(
      starts: const ['2026-08-24'],
      rows: [
        _night('2026-09-01', rhr: 50),
        _night('2026-09-10', rhr: 52),
        _night('2026-09-15', rhr: 56),
      ],
    );
    expect(twoPrior.rhr.prior21.reason, CycleComparisonPrior21Reason.available);
    expect(twoPrior.rhr.prior21.count, 2);
    expect(twoPrior.rhr.prior21.mean, ana.mean(const [50.0, 52.0]));
    expect(twoPrior.rhr.sameDay.count, 0);

    final twoCycles = _snap(
      starts: const ['2026-06-29', '2026-07-31', '2026-08-24'],
      rows: [
        _night('2026-07-21', rhr: 50),
        _night('2026-08-22', rhr: 52),
        _night('2026-09-15', rhr: 56),
      ],
    );
    expect(
      twoCycles.rhr.sameDay.reason,
      CycleComparisonSameDayReason.insufficientPeriods,
    );
    expect(twoCycles.rhr.sameDay.count, 2);
    expect(twoCycles.rhr.sameDay.mean, isNull);
  });

  test('zero sample SD still has mean and delta; z stays null', () {
    final snap = _snap(
      starts: const ['2026-05-28', '2026-06-29', '2026-07-31', '2026-08-24'],
      rows: [
        _night('2026-06-19', rhr: 54, hrv: 48),
        _night('2026-07-21', rhr: 54, hrv: 48),
        _night('2026-08-22', rhr: 54, hrv: 48),
        _night('2026-09-10', rhr: 54, hrv: 48),
        _night('2026-09-11', rhr: 54, hrv: 48),
        _night('2026-09-15', rhr: 56, hrv: 51),
      ],
    );
    expect(snap.rhr.prior21.mean, 54);
    expect(snap.rhr.prior21.delta, 2);
    expect(snap.rhr.prior21.z, isNull);
    expect(ana.z(56, const [54.0, 54.0]), isNull);
    expect(snap.rhr.sameDay.mean, 54);
    expect(snap.rhr.sameDay.delta, 2);
    expect(snap.rhr.sameDay.z, ana.z(56, const [54.0, 54.0, 54.0]));
    expect(snap.rhr.sameDay.z, isNull);
  });

  test('tracking off withholds without reading nights; estimates do not gate',
      () {
    final off = _snap(
      settings: const CycleSettings(
        enabled: false,
        estimatesEnabled: true,
        lengthReviewEnabled: false,
      ),
      rows: _paperComparisonRows(),
    );
    expect(off.reason, CycleComparisonReason.trackingDisabled);
    expect(off.rhr.latest, isNull);
    expect(off.hrv.latest, isNull);

    final gated = _snap(
      settings: const CycleSettings(
        enabled: true,
        estimatesEnabled: false,
        lengthReviewEnabled: true,
        situation: CycleSituation.none,
      ),
      rows: _paperComparisonRows(),
    );
    expect(gated.reason, CycleComparisonReason.available);
    expect(gated.rhr.latest?.metric.value, 56);
    expect(gated.hrv.latest?.metric.value, 51);
  });

  test('starts before the window keep true cycle-day numbering', () {
    const early = '2025-09-01';
    final snap = _snap(
      starts: const [early],
      rows: [
        _night('2025-09-10', rhr: 50),
        _night('2025-09-16', rhr: 54),
      ],
    );
    expect(snap.rhr.latest?.nightDay, '2025-09-16');
    expect(snap.rhr.latest?.startDay, early);
    expect(snap.rhr.latest?.cycleDay, 16);
    expect(
      snap.rhr.prior21.contributors
          .firstWhere((c) => c.nightDay == '2025-09-10')
          .cycleDay,
      10,
    );
    expect(
      snap.rhr.prior21.contributors
          .firstWhere((c) => c.nightDay == '2025-09-10')
          .startDay,
      early,
    );
  });

  test('source envelope matches parseCycleNightSource', () {
    const day = '2026-09-15';
    final row = _night(
      day,
      rhr: 56,
      hrv: 51,
      rhrConfidence: 0.81,
      hrvConfidence: 0.44,
      rhrNote: 'low30',
    );
    final parsed = parseCycleNightSource(row, algoVersion: kAlgoVersion);
    final snap = _snap(
      starts: const ['2026-08-24'],
      rows: [row, _night('2026-09-14', rhr: 54, hrv: 48)],
    );
    expect(snap.rhr.latest?.metric.value, parsed.rhr?.value);
    expect(snap.rhr.latest?.metric.confidence, parsed.rhr?.confidence);
    expect(snap.rhr.latest?.metric.note, parsed.rhr?.note);
    expect(snap.rhr.latest?.sleepSource, parsed.sleepSource);
    expect(snap.rhr.latest?.sleepStart, parsed.windowStart);
    expect(snap.rhr.latest?.sleepEnd, parsed.windowEnd);
    expect(snap.hrv.latest?.metric.confidence, parsed.hrv?.confidence);
  });

  test('latest reason distinguishes missing, unavailable and unreadable', () {
    final absent = _snap(starts: const ['2026-08-24'], rows: const []);
    expect(absent.rhr.latestReason, CycleComparisonLatestReason.missing);
    expect(absent.hrv.latestReason, CycleComparisonLatestReason.missing);
    expect(absent.rhr.rejectedCount, 0);
    expect(absent.rhr.unreadableCount, 0);

    final knownAbsent = _snap(
      starts: const ['2026-08-24'],
      rows: [_night('2026-09-15', hrv: 51)],
    );
    expect(knownAbsent.rhr.latestReason, CycleComparisonLatestReason.missing);
    expect(knownAbsent.hrv.latestReason, CycleComparisonLatestReason.available);
    expect(knownAbsent.hrv.latest?.metric.value, 51);

    final refused = _snap(
      starts: const ['2026-08-24'],
      rows: [
        _night('2026-09-14', rhr: 54, hrv: 48, imported: true),
        _night('2026-09-15', rhr: 56, hrv: 51, skipped: true),
      ],
    );
    expect(refused.rhr.latestReason, CycleComparisonLatestReason.unavailable);
    expect(refused.hrv.latestReason, CycleComparisonLatestReason.unavailable);
    expect(refused.rhr.rejectedCount, 2);
    expect(refused.hrv.rejectedCount, 2);
    expect(refused.rhr.unreadableCount, 0);
    expect(refused.rhr.latest, isNull);
    expect(refused.excludedNightCount, 2);

    final duplicate = _snap(
      starts: const ['2026-08-24'],
      rows: [
        _night('2026-09-15', rhr: 56, hrv: 51),
        _night('2026-09-15', rhr: 99, hrv: 99),
      ],
    );
    expect(duplicate.rhr.latestReason, CycleComparisonLatestReason.unreadable);
    expect(duplicate.hrv.latestReason, CycleComparisonLatestReason.unreadable);
    expect(duplicate.rhr.unreadableCount, 1);
    expect(duplicate.hrv.unreadableCount, 1);

    final corruptRhr = _snap(
      starts: const ['2026-08-24'],
      rows: [
        _night(
          '2026-09-15',
          payload: _corruptMetricPayload('2026-09-15', hrv: 51, corruptRhr: true),
        ),
      ],
    );
    expect(corruptRhr.rhr.latestReason, CycleComparisonLatestReason.unreadable);
    expect(corruptRhr.rhr.unreadableCount, 1);
    expect(corruptRhr.hrv.latestReason, CycleComparisonLatestReason.available);
    expect(corruptRhr.hrv.latest?.metric.value, 51);
    expect(corruptRhr.hrv.unreadableCount, 0);

    final corruptRhrAbsentHrv = _snap(
      starts: const ['2026-08-24'],
      rows: [
        _night(
          '2026-09-15',
          payload: _corruptMetricPayload('2026-09-15', corruptRhr: true),
        ),
      ],
    );
    expect(
      corruptRhrAbsentHrv.rhr.latestReason,
      CycleComparisonLatestReason.unreadable,
    );
    expect(
      corruptRhrAbsentHrv.hrv.latestReason,
      CycleComparisonLatestReason.missing,
    );
    expect(corruptRhrAbsentHrv.hrv.unreadableCount, 0);
    expect(corruptRhrAbsentHrv.hrv.rejectedCount, 0);
  });

  test('unused padding anomalies are ignored; relevant prior-21 padding counts',
      () {
    final baseRows = [
      _night('2026-09-01', rhr: 50, hrv: 40),
      _night('2026-09-10', rhr: 52, hrv: 42),
      _night('2026-09-15', rhr: 56, hrv: 51),
    ];
    final clean = _snap(starts: const ['2026-08-24'], rows: baseRows);
    expect(clean.unreadableNightCount, 0);
    expect(clean.excludedNightCount, 0);
    expect(clean.partial, isFalse);
    expect(clean.rhr.prior21.startDay, '2026-08-25');

    final unused = _snap(
      starts: const ['2026-08-24'],
      rows: [
        ...baseRows,
        _night('2025-08-26', rhr: 99, payloadUnreadable: true),
        _night('2025-08-26', rhr: 88),
      ],
    );
    expect(unused.unreadableNightCount, clean.unreadableNightCount);
    expect(unused.excludedNightCount, clean.excludedNightCount);
    expect(unused.partial, clean.partial);
    expect(unused.rhr.latestReason, CycleComparisonLatestReason.available);
    expect(unused.rhr.unreadableCount, 0);

    final padOnly = _snap(
      starts: const [],
      rows: [_night('2025-08-26', payloadUnreadable: true)],
    );
    expect(padOnly.rhr.latestReason, CycleComparisonLatestReason.missing);
    expect(padOnly.hrv.latestReason, CycleComparisonLatestReason.missing);
    expect(padOnly.unreadableNightCount, 0);
    expect(padOnly.partial, isFalse);

    final relevant = _snap(
      starts: const [],
      rows: [
        _night('2025-08-26', payloadUnreadable: true),
        _night('2025-09-16', rhr: 54, hrv: 44),
      ],
    );
    expect(relevant.rhr.latest?.nightDay, '2025-09-16');
    expect(relevant.rhr.prior21.startDay, '2025-08-26');
    expect(relevant.unreadableNightCount, 1);
    expect(relevant.partial, isTrue);
    expect(relevant.rhr.unreadableCount, 0);
  });

  test('accepted padding nights never become latest for an empty displayed year',
      () {
    final snap = _snap(
      starts: const ['2026-08-24'],
      rows: [
        _night('2025-08-26', rhr: 50, hrv: 20),
        _night('2025-09-10', rhr: 52, hrv: 22),
        _night('2025-09-15', rhr: 54, hrv: 24),
      ],
    );
    expect(snap.window.startDay, '2025-09-16');
    expect(snap.rhr.latestReason, CycleComparisonLatestReason.missing);
    expect(snap.rhr.latest, isNull);
    expect(snap.hrv.latestReason, CycleComparisonLatestReason.missing);
    expect(snap.hrv.latest, isNull);
    expect(snap.rhr.prior21.reason, CycleComparisonPrior21Reason.noLatest);
    expect(snap.hrv.prior21.reason, CycleComparisonPrior21Reason.noLatest);
    expect(snap.rhr.sameDay.reason, CycleComparisonSameDayReason.noLatest);
    expect(snap.hrv.sameDay.reason, CycleComparisonSameDayReason.noLatest);
  });
}
