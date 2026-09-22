import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';

Map _load(String name) =>
    jsonDecode(File('docs/openband5/assets/fixtures/$name').readAsStringSync())
        as Map;

SyntheticOpenBandRepository repo() => SyntheticOpenBandRepository.fromMaps(
      _load('day-summary.json'),
      _load('sleep-detail.json'),
    );

const _settings = CycleSettings(
  enabled: true,
  estimatesEnabled: true,
  lengthReviewEnabled: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('kAlgoVersion remains the cycle-night pin', () {
    expect(kAlgoVersion, 94);
  });

  test('Paper cycle is 23 dense nights, RHR 54 on 15 Sep, HRV 48 on 14 Sep',
      () async {
    final snap = await repo().readCycleMeasurements(
      SyntheticOpenBandRepository.cycleFixtureDay,
    );
    expect(snap.reason, CycleMeasurementsReason.available);
    expect(snap.selected?.startDay, '2026-08-24');
    expect(snap.selected?.endDay, '2026-09-15');
    expect(snap.selected?.open, isTrue);
    expect(snap.nights, hasLength(23));
    expect(snap.nights.first.day, '2026-08-24');
    expect(snap.nights.first.cycleDay, 1);
    expect(snap.nights.last.day, '2026-09-15');
    expect(snap.nights.last.cycleDay, 23);
    expect(snap.rhrAvailableCount, 19);
    expect(snap.hrvAvailableCount, 16);
    expect(snap.latestRhr, const CycleMetricLatest(day: '2026-09-15', value: 54));
    expect(snap.latestHrv, const CycleMetricLatest(day: '2026-09-14', value: 48));
    expect(snap.nights.last.rhr?.value, 54);
    expect(snap.nights.last.hrv, isNull);
    expect(snap.nights[21].day, '2026-09-14');
    expect(snap.nights[21].hrv?.value, 48);
    expect(
      [for (final n in snap.nights) n.rhr?.value],
      kCyclePaperRhr,
    );
    expect(
      [for (final n in snap.nights) n.hrv?.value],
      kCyclePaperHrv,
    );
    expect(snap.partial, isFalse);
    expect(snap.excludedCount, 0);
    expect(snap.unreadableCount, 0);
    expect(snap.truncated, isFalse);
    expect(snap.periods.map((p) => p.startDay), [
      '2026-06-01',
      '2026-06-29',
      '2026-07-31',
      '2026-08-24',
    ]);
    expect(snap.periods.last.open, isTrue);
    expect(snap.periods.first.open, isFalse);
    expect(snap.periods[2].endDay, '2026-08-23');
  });

  test('missing nights stay dense gaps, not zero', () async {
    final snap = await repo().readCycleMeasurements('2026-09-15');
    final gap = snap.nights[5];
    expect(gap.day, '2026-08-29');
    expect(gap.rhr, isNull);
    expect(gap.hrv, isNull);
    expect(gap.cycleDay, 6);
    expect(snap.nights[4].rhr?.value, 53);
    expect(snap.nights[7].rhr?.value, 55);
  });

  test('previous logged cycle keeps exact bounds and does not borrow later nights',
      () async {
    final snap = await repo().readCycleMeasurements(
      '2026-09-15',
      cycleStartDay: '2026-07-31',
    );
    expect(snap.selected?.startDay, '2026-07-31');
    expect(snap.selected?.endDay, '2026-08-23');
    expect(snap.selected?.open, isFalse);
    expect(snap.nights.first.day, '2026-07-31');
    expect(snap.nights.last.day, '2026-08-23');
    expect(snap.nights.every((n) => n.rhr == null && n.hrv == null), isTrue);
    expect(snap.reason, CycleMeasurementsReason.metricUnavailable);
    expect(snap.latestRhr, isNull);
    expect(snap.latestHrv, isNull);
  });

  test('removed selected start is typed missing, never another cycle', () async {
    final r = repo();
    await r.removeCycleStart(
      const CycleStart(date: '2026-08-24', kind: kCycleStartKind),
    );
    final missing = await r.readCycleMeasurements(
      '2026-09-15',
      cycleStartDay: '2026-08-24',
    );
    expect(missing.reason, CycleMeasurementsReason.selectedStartMissing);
    expect(missing.selected, isNull);
    expect(missing.selectedStartDay, '2026-08-24');
    expect(missing.nights, isEmpty);
    expect(missing.latestRhr, isNull);
    expect(missing.latestHrv, isNull);
    expect(missing.periods.map((p) => p.startDay), [
      '2026-06-01',
      '2026-06-29',
      '2026-07-31',
    ]);
    expect(missing.periods.last.endDay, '2026-09-15');
    expect(missing.periods.last.open, isTrue);
    expect(missing.periods[1].endDay, '2026-07-30');
    final fallback = await r.readCycleMeasurements('2026-09-15');
    expect(fallback.selected?.startDay, '2026-07-31');
    expect(fallback.selected?.endDay, '2026-09-15');
  });

  test('empty starts, disabled tracking and unreadable starts stay distinct',
      () async {
    final r = repo();
    r.clearCycleLogs();
    expect(
      (await r.readCycleMeasurements('2026-09-15')).reason,
      CycleMeasurementsReason.emptyStarts,
    );
    r.cycleSettings = const CycleSettings(
      enabled: false,
      estimatesEnabled: false,
      lengthReviewEnabled: false,
    );
    r.seedCycleStart(
      const CycleStart(date: '2026-08-24', kind: kCycleStartKind),
    );
    expect(
      (await r.readCycleMeasurements('2026-09-15')).reason,
      CycleMeasurementsReason.trackingDisabled,
    );
    r.cycleSettings = _settings;
    r.seedUnreadableCycleStart({'date': '2026-08-10', 'kind': ''});
    final unreadable = await r.readCycleMeasurements('2026-09-15');
    expect(unreadable.reason, CycleMeasurementsReason.unreadableStarts);
    expect(unreadable.periods, isEmpty);
    expect(unreadable.nights, isEmpty);
  });

  test('duplicate contributing starts make association uncertain', () {
    final snap = buildCycleMeasurementsSnapshot(
      asOfDay: '2026-09-15',
      settings: _settings,
      log: parseCycleLog(
        startRows: const [
          {'date': '2026-08-24', 'kind': 'start'},
          {'date': '2026-08-24', 'kind': 'start'},
        ],
        observationRows: const [],
        asOf: '2026-09-15',
      ),
      algoVersion: kAlgoVersion,
    );
    expect(snap.reason, CycleMeasurementsReason.unreadableStarts);
    expect(snap.nights, isEmpty);
  });

  test('later corrupt starts do not contaminate an as-of read', () async {
    final r = repo();
    r.seedUnreadableCycleStart({'date': '2026-09-20', 'kind': ''});
    final snap = await r.readCycleMeasurements('2026-09-15');
    expect(snap.reason, CycleMeasurementsReason.available);
    expect(snap.selected?.startDay, '2026-08-24');
    expect(snap.unreadableCount, 0);
  });

  test('read failure is not an empty success', () async {
    final r = repo();
    r.failCycleMeasurementsRead = true;
    await expectLater(
      r.readCycleMeasurements('2026-09-15'),
      throwsStateError,
    );
  });

  test('invalid as-of throws instead of an unavailable snapshot', () async {
    await expectLater(
      repo().readCycleMeasurements('15-09-2026'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('empty injection is metric-unavailable with dense gaps', () async {
    final r = repo();
    r.clearCycleNightSources();
    final snap = await r.readCycleMeasurements('2026-09-15');
    expect(snap.reason, CycleMeasurementsReason.metricUnavailable);
    expect(snap.nights, hasLength(23));
    expect(snap.latestRhr, isNull);
    expect(snap.partial, isFalse);
  });

  test('partial injection counts excluded nights without filling gaps as zero',
      () async {
    final r = repo();
    r.seedCycleNightSource(
      CycleNightSourceRow(
        day: '2026-09-15',
        algoVersion: kAlgoVersion,
        skipped: true,
        payload: cycleNightSourcePayload(
          rhr: 54,
          hrv: 48,
          onsetMs: cycleNightOnsetMs('2026-09-15'),
          offsetMs: cycleNightOffsetMs('2026-09-15'),
        ),
      ),
    );
    final snap = await r.readCycleMeasurements('2026-09-15');
    expect(snap.partial, isTrue);
    expect(snap.excludedCount, 1);
    expect(snap.nights.last.rhr, isNull);
    expect(snap.latestRhr?.day, isNot('2026-09-15'));
  });

  test('civil arithmetic keeps both DST transitions and west-zone labels', () {
    expect(isCycleCalendarDay('2026-03-08'), isTrue);
    expect(isCycleCalendarDay('2026-11-01'), isTrue);
    expect(cycleAddDays('2026-03-08', 1), '2026-03-09');
    expect(cycleAddDays('2026-11-01', 1), '2026-11-02');
    final days = cycleCivilDaysInclusive('2026-03-07', '2026-03-10');
    expect(days, ['2026-03-07', '2026-03-08', '2026-03-09', '2026-03-10']);
    final fall = cycleCivilDaysInclusive('2026-10-31', '2026-11-02');
    expect(fall, ['2026-10-31', '2026-11-01', '2026-11-02']);
    expect(cycleDiffDays('2026-03-08', '2026-03-29'), 21);
  });

  test('120-day cap keeps the true cycle-day offset', () {
    const start = '2026-04-19';
    const asOf = '2026-09-15';
    expect(cycleDiffDays(start, asOf) + 1, 150);
    final visible = cycleAddDays(asOf, -(kCycleMeasurementMaxNights - 1));
    final snap = buildCycleMeasurementsSnapshot(
      asOfDay: asOf,
      settings: _settings,
      log: parseCycleLog(
        startRows: const [
          {'date': start, 'kind': 'start'},
        ],
        observationRows: const [],
        asOf: asOf,
      ),
      algoVersion: kAlgoVersion,
      rows: [
        CycleNightSourceRow(
          day: start,
          algoVersion: kAlgoVersion,
          payload: cycleNightSourcePayload(
            rhr: 40,
            onsetMs: cycleNightOnsetMs(start),
            offsetMs: cycleNightOffsetMs(start),
          ),
        ),
        CycleNightSourceRow(
          day: visible,
          algoVersion: kAlgoVersion,
          payload: cycleNightSourcePayload(
            rhr: 41,
            onsetMs: cycleNightOnsetMs(visible),
            offsetMs: cycleNightOffsetMs(visible),
          ),
        ),
      ],
    );
    expect(snap.truncated, isTrue);
    expect(snap.nights, hasLength(120));
    expect(snap.nights.first.day, visible);
    expect(snap.nights.first.cycleDay, 31);
    expect(snap.firstCycleDay, 31);
    expect(snap.nights.first.rhr?.value, 41);
    expect(snap.nights.any((n) => n.day == start), isFalse);
  });

  test('session envelope absence stays unavailable when a scalar is present', () {
    const day = '2026-09-15';
    final payload = cycleNightSourcePayload(
      rhr: 54,
      hrv: null,
      rmssdScalar: 48,
      onsetMs: cycleNightOnsetMs(day),
      offsetMs: cycleNightOffsetMs(day),
    );
    final parsed = parseCycleNightSource(
      CycleNightSourceRow(
        day: day,
        algoVersion: kAlgoVersion,
        payload: payload,
      ),
      algoVersion: kAlgoVersion,
    );
    expect(parsed.disposition, CycleNightDisposition.eligible);
    expect(parsed.rhr?.value, 54);
    expect(parsed.hrv, isNull);
  });

  test('RHR <= 0 is corrupt; HRV 0 is valid; HRV < 0 is corrupt', () {
    const day = '2026-09-15';
    CycleNightParse parse(double? rhr, double? hrv) => parseCycleNightSource(
          CycleNightSourceRow(
            day: day,
            algoVersion: kAlgoVersion,
            payload: cycleNightSourcePayload(
              rhr: rhr,
              hrv: hrv,
              onsetMs: cycleNightOnsetMs(day),
              offsetMs: cycleNightOffsetMs(day),
            ),
          ),
          algoVersion: kAlgoVersion,
        );
    final rhrZero = parse(0, 48);
    expect(rhrZero.disposition, CycleNightDisposition.eligible);
    expect(rhrZero.rhr, isNull);
    expect(rhrZero.rhrUnreadable, isTrue);
    expect(rhrZero.hrv?.value, 48);
    expect(rhrZero.hrvUnreadable, isFalse);
    final hrvZero = parse(54, 0);
    expect(hrvZero.hrv?.value, 0);
    expect(hrvZero.hrvUnreadable, isFalse);
    expect(hrvZero.rhr?.value, 54);
    final hrvNeg = parse(54, -1);
    expect(hrvNeg.hrv, isNull);
    expect(hrvNeg.hrvUnreadable, isTrue);
    expect(hrvNeg.rhr?.value, 54);
  });
}
