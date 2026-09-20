import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/health/glucose_contract.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';

Map _load(String name) =>
    jsonDecode(File('docs/openband5/assets/fixtures/$name').readAsStringSync())
        as Map;

SyntheticOpenBandRepository repo() => SyntheticOpenBandRepository.fromMaps(
      _load('day-summary.json'),
      _load('sleep-detail.json'),
    );

void main() {
  test('fixture has 11 numbers, 2 gaps, and the three Paper clocks', () {
    final fixture = _load('glucose-source.json');
    expect(fixture['unit'], 'mmol/L');
    expect(fixture['latest'], '08:00');
    expect(fixture['imported_at'], '09:40');
    expect(fixture['last_query_at'], '09:41');
    final values = (fixture['values'] as List).cast<num?>();
    expect(values.whereType<num>(), hasLength(11));
    expect(values.where((v) => v == null), hasLength(2));
  });

  test('synthetic snapshot uses only fixture values and clocks', () async {
    final snap = await repo().readGlucose();
    expect(snap.history, hasLength(11));
    expect(snap.series, hasLength(11));
    expect(snap.unreadableCount, 0);
    expect(snap.truncated, isFalse);
    expect(
      snap.series.map((r) => r.value),
      [5.2, 5.4, 5.6, 5.9, 6.3, 5.8, 5.3, 5.1, 5.2, 5.1, 5.0],
    );
    expect(snap.series.every((r) => r.rawUnit == 'mmol/L'), isTrue);
    expect(
      snap.series.every((r) => r.unitKind == GlucoseUnitKind.millimolePerLiter),
      isTrue,
    );
    expect(snap.lastMeasuredAt, DateTime(2026, 9, 15, 8, 0));
    expect(snap.lastImportedAt, DateTime(2026, 9, 15, 9, 40));
    expect(snap.attempt.attemptedAt, DateTime(2026, 9, 15, 9, 41));
    expect(snap.attempt.status, HealthMeasurementImportStatus.stored);
    expect(
      snap.history.map((r) => r.measuredAt),
      isNot(contains(DateTime(2026, 9, 15, 7, 25))),
    );
    expect(
      snap.history.map((r) => r.measuredAt),
      isNot(contains(DateTime(2026, 9, 15, 7, 30))),
    );
  });

  test('Apple, Android and legacy source keys stay distinguishable', () {
    expect(
      importedSourceKey(isApple: true, sourceId: 'com.dexcom.G7', sourceName: 'Dexcom'),
      'apple:com.dexcom.G7',
    );
    expect(
      importedSourceKey(
        isApple: false,
        sourceId: '',
        sourceName: 'com.dexcom.g7',
      ),
      'android:com.dexcom.g7',
    );
    expect(legacyImportedSourceKey('Dexcom'), 'legacy:Dexcom');
    expect(
      importedSourceKey(isApple: true, sourceId: '', sourceName: ''),
      kAppleUnknownSourceKey,
    );
    expect(
      glucoseSourceFromStored(sourceName: 'Dexcom').legacy,
      isTrue,
    );
    expect(
      glucoseSourceFromStored(
        sourceKey: 'apple:com.dexcom.G7',
        sourceId: 'com.dexcom.G7',
        sourceName: 'Dexcom',
      ).legacy,
      isFalse,
    );
  });

  test('unknown unit is retained in history and not plotted', () async {
    final r = repo();
    r.retagGlucoseUnit('glucose-fixture-0800', 'stones');
    final snap = await r.readGlucose();
    expect(snap.history, hasLength(11));
    final unknown = snap.history.firstWhere((x) => x.uuid == 'glucose-fixture-0800');
    expect(unknown.unitKind, GlucoseUnitKind.unknown);
    expect(unknown.plottable, isFalse);
    expect(snap.series, isEmpty);
  });

  test('exclude hides series, restore shows retained fixture readings', () async {
    final r = repo();
    await r.setGlucoseSourceIncluded(
      SyntheticOpenBandRepository.glucoseFixtureSourceKey,
      included: false,
    );
    final hidden = await r.readGlucose();
    expect(hidden.selectedExcluded, isTrue);
    expect(hidden.series, isEmpty);
    expect(hidden.history, hasLength(11));
    expect(hidden.lastMeasuredAt, DateTime(2026, 9, 15, 8, 0));
    expect(hidden.sources.single.excluded, isTrue);

    await r.setGlucoseSourceIncluded(
      SyntheticOpenBandRepository.glucoseFixtureSourceKey,
      included: true,
    );
    final shown = await r.readGlucose();
    expect(shown.selectedExcluded, isFalse);
    expect(shown.series, hasLength(11));
  });

  test('exclusion write failure is not an optimistic success', () async {
    final r = repo()..failGlucoseExclusionWrite = true;
    await expectLater(
      r.setGlucoseSourceIncluded(
        SyntheticOpenBandRepository.glucoseFixtureSourceKey,
        included: false,
      ),
      throwsStateError,
    );
    final snap = await r.readGlucose();
    expect(snap.selectedExcluded, isFalse);
    expect(snap.series, hasLength(11));
  });

  test('empty import keeps stored readings', () async {
    final r = repo()..emptyGlucoseImport = true;
    final before = await r.readGlucose();
    final result = await r.importGlucose(now: DateTime(2026, 9, 15, 10, 0));
    expect(result.outcome.status, HealthMeasurementImportStatus.empty);
    expect(result.refreshFailed, isFalse);
    expect(result.snapshot!.history, hasLength(1));
    expect(result.snapshot!.history.single.uuid, before.history.first.uuid);
    expect(result.snapshot!.truncated, isTrue);
    expect(result.snapshot!.series, hasLength(11));
    expect(result.snapshot!.sources.single.readingCount, 11);
  });

  test('failed import keeps stored readings', () async {
    final r = repo()
      ..failGlucoseImport = true
      ..glucoseImportFailureStatus = HealthMeasurementImportStatus.readFailed;
    final result = await r.importGlucose(now: DateTime(2026, 9, 15, 10, 0));
    expect(result.outcome.status, HealthMeasurementImportStatus.readFailed);
    expect(result.refreshFailed, isFalse);
    expect(result.snapshot!.history, hasLength(1));
    expect(result.snapshot!.truncated, isTrue);
    expect(result.snapshot!.lastMeasuredAt, DateTime(2026, 9, 15, 8, 0));
    expect(result.snapshot!.series, hasLength(11));
  });

  test('store-read exception is not an empty snapshot', () async {
    final r = repo()..failGlucoseReads = true;
    await expectLater(r.readGlucose(), throwsStateError);
  });

  test('saved import keeps outcome when snapshot refresh fails', () async {
    final r = repo()..failGlucoseReads = true;
    final result = await r.importGlucose(now: DateTime(2026, 9, 15, 10, 0));
    expect(result.outcome.status, HealthMeasurementImportStatus.stored);
    expect(result.refreshFailed, isTrue);
    expect(result.snapshot, isNull);
  });

  test('series follows newest known unit; newest unknown withholds plot',
      () async {
    final r = repo()..clearGlucoseReadings();
    const source = GlucoseSourceIdentity(
      key: SyntheticOpenBandRepository.glucoseFixtureSourceKey,
      sourceName: 'Sensor-App (synthetisch) via Apple Health',
      provenance: GlucoseSourceProvenance.synthetic,
    );
    r.seedGlucoseReading(
      GlucoseReading(
        uuid: 'older-mg',
        measuredAt: DateTime(2026, 9, 15, 7, 0),
        value: 95,
        rawUnit: kGlucoseUnitMilligramPerDeciliter,
        unitKind: GlucoseUnitKind.milligramPerDeciliter,
        source: source,
      ),
    );
    r.seedGlucoseReading(
      GlucoseReading(
        uuid: 'newer-mmol',
        measuredAt: DateTime(2026, 9, 15, 8, 0),
        value: 5.2,
        rawUnit: kGlucoseUnitMillimolePerLiter,
        unitKind: GlucoseUnitKind.millimolePerLiter,
        source: source,
      ),
    );
    final mixed = await r.readGlucose();
    expect(mixed.series.map((x) => x.uuid), ['newer-mmol']);
    expect(
      mixed.series.single.unitKind,
      GlucoseUnitKind.millimolePerLiter,
    );

    r.retagGlucoseUnit('newer-mmol', 'stones');
    final unknownNewest = await r.readGlucose();
    expect(unknownNewest.history, hasLength(2));
    expect(
      unknownNewest.history.firstWhere((x) => x.uuid == 'newer-mmol').unitKind,
      GlucoseUnitKind.unknown,
    );
    expect(unknownNewest.series, isEmpty);
  });

  test('a most-recent window labels truncation instead of inventing oldest-N',
      () async {
    final snap = await repo().readGlucose(limit: 3);
    expect(snap.history, hasLength(3));
    expect(snap.truncated, isTrue);
    expect(snap.history.first.measuredAt, DateTime(2026, 9, 15, 8, 0));
    expect(snap.history.last.measuredAt, DateTime(2026, 9, 15, 7, 50));
    expect(snap.series, hasLength(11));
    expect(snap.sources.single.readingCount, 11);
  });

  test('corrupt sibling does not drop healthy fixture rows', () async {
    final r = repo();
    r.seedGlucoseReading(
      GlucoseReading(
        uuid: '',
        measuredAt: DateTime(2026, 9, 15, 6, 0),
        value: 5.2,
        rawUnit: 'mmol/L',
        unitKind: GlucoseUnitKind.millimolePerLiter,
        source: const GlucoseSourceIdentity(
          key: SyntheticOpenBandRepository.glucoseFixtureSourceKey,
          sourceName: 'Sensor-App (synthetisch) via Apple Health',
          provenance: GlucoseSourceProvenance.synthetic,
        ),
      ),
    );
    final snap = await r.readGlucose();
    expect(snap.history, hasLength(11));
    expect(snap.unreadableCount, 1);
  });

  test('limit 1 keeps the full latest local day series and all-time count',
      () async {
    final r = repo()..clearGlucoseReadings();
    const source = GlucoseSourceIdentity(
      key: SyntheticOpenBandRepository.glucoseFixtureSourceKey,
      sourceName: 'Sensor-App (synthetisch) via Apple Health',
      provenance: GlucoseSourceProvenance.synthetic,
    );
    for (var i = 0; i < 250; i++) {
      r.seedGlucoseReading(
        GlucoseReading(
          uuid: 'n$i',
          measuredAt: DateTime(2026, 9, 15, 12).subtract(Duration(minutes: i)),
          value: 5.2,
          rawUnit: kGlucoseUnitMillimolePerLiter,
          unitKind: GlucoseUnitKind.millimolePerLiter,
          source: source,
          importedAt: DateTime(2026, 9, 15, 9, 40),
        ),
      );
    }
    for (var i = 0; i < 20; i++) {
      r.seedGlucoseReading(
        GlucoseReading(
          uuid: 'prev$i',
          measuredAt: DateTime(2026, 9, 14, 12).subtract(Duration(minutes: i)),
          value: 5.0,
          rawUnit: kGlucoseUnitMillimolePerLiter,
          unitKind: GlucoseUnitKind.millimolePerLiter,
          source: source,
        ),
      );
    }
    final snap = await r.readGlucose(limit: 1);
    expect(snap.history, hasLength(1));
    expect(snap.history.single.uuid, 'n0');
    expect(snap.series, hasLength(250));
    expect(snap.truncated, isTrue);
    expect(snap.sources.single.readingCount, 270);
    expect(snap.lastMeasuredAt, DateTime(2026, 9, 15, 12));
  });

  test('growing history windows keep newest order and stable stored count',
      () async {
    final r = repo()..clearGlucoseReadings();
    const source = GlucoseSourceIdentity(
      key: SyntheticOpenBandRepository.glucoseFixtureSourceKey,
      sourceName: 'Sensor-App (synthetisch) via Apple Health',
      provenance: GlucoseSourceProvenance.synthetic,
    );
    for (var i = 0; i < 400; i++) {
      r.seedGlucoseReading(
        GlucoseReading(
          uuid: 'g$i',
          measuredAt: DateTime(2026, 9, 15, 16).subtract(Duration(minutes: i)),
          value: 5.2,
          rawUnit: kGlucoseUnitMillimolePerLiter,
          unitKind: GlucoseUnitKind.millimolePerLiter,
          source: source,
        ),
      );
    }
    final first = await r.readGlucose(limit: 200);
    expect(first.history, hasLength(200));
    expect(first.history.first.uuid, 'g0');
    expect(first.history.last.uuid, 'g199');
    expect(first.truncated, isTrue);
    expect(first.sources.single.readingCount, 400);
    expect(first.series, hasLength(400));

    final more = await r.readGlucose(limit: 400);
    expect(more.history, hasLength(400));
    expect(more.history.first.uuid, 'g0');
    expect(more.truncated, isFalse);
    expect(more.sources.single.readingCount, 400);
    expect(more.series, hasLength(400));
  });

  test('lastImportedAt is full-source max import, not newest measurement',
      () async {
    final r = repo()..clearGlucoseReadings();
    const source = GlucoseSourceIdentity(
      key: SyntheticOpenBandRepository.glucoseFixtureSourceKey,
      sourceName: 'Sensor-App (synthetisch) via Apple Health',
      provenance: GlucoseSourceProvenance.synthetic,
    );
    r.seedGlucoseReading(
      GlucoseReading(
        uuid: 'older-backfill',
        measuredAt: DateTime(2026, 9, 14, 8),
        value: 5.0,
        rawUnit: kGlucoseUnitMillimolePerLiter,
        unitKind: GlucoseUnitKind.millimolePerLiter,
        source: source,
        importedAt: DateTime(2026, 9, 15, 10),
      ),
    );
    r.seedGlucoseReading(
      GlucoseReading(
        uuid: 'newest-measure',
        measuredAt: DateTime(2026, 9, 15, 8),
        value: 5.2,
        rawUnit: kGlucoseUnitMillimolePerLiter,
        unitKind: GlucoseUnitKind.millimolePerLiter,
        source: source,
        importedAt: DateTime(2026, 9, 15, 9),
      ),
    );
    final snap = await r.readGlucose();
    expect(snap.lastMeasuredAt, DateTime(2026, 9, 15, 8));
    expect(snap.lastImportedAt, DateTime(2026, 9, 15, 10));
  });

  test('same-ts mixed units follow uuid desc; newest unknown withholds plot',
      () async {
    final r = repo()..clearGlucoseReadings();
    const source = GlucoseSourceIdentity(
      key: SyntheticOpenBandRepository.glucoseFixtureSourceKey,
      sourceName: 'Sensor-App (synthetisch) via Apple Health',
      provenance: GlucoseSourceProvenance.synthetic,
    );
    final at = DateTime(2026, 9, 15, 8);
    for (var i = 0; i < 40; i++) {
      final unknown = i == 39;
      r.seedGlucoseReading(
        GlucoseReading(
          uuid: 'u${i.toString().padLeft(2, '0')}',
          measuredAt: at,
          value: unknown ? 5.2 : (i.isEven ? 5.2 : 95),
          rawUnit: unknown
              ? 'stones'
              : (i.isEven
                  ? kGlucoseUnitMillimolePerLiter
                  : kGlucoseUnitMilligramPerDeciliter),
          unitKind: unknown
              ? GlucoseUnitKind.unknown
              : (i.isEven
                  ? GlucoseUnitKind.millimolePerLiter
                  : GlucoseUnitKind.milligramPerDeciliter),
          source: source,
        ),
      );
    }
    final snap = await r.readGlucose(limit: 1);
    expect(snap.history.single.uuid, 'u39');
    expect(snap.history.single.unitKind, GlucoseUnitKind.unknown);
    expect(snap.series, isEmpty);
    expect(snap.lastMeasuredAt, at);
    final ordered = [...snap.history]..sort(compareGlucoseNewestFirst);
    expect(ordered.first.uuid, 'u39');
  });

  test('DateTime max does not throw a local-day window or invent an end', () {
    final edge = DateTime.fromMillisecondsSinceEpoch(8640000000000000);
    expect(() => glucoseLocalDayWindow(edge), returnsNormally);
    expect(glucoseLocalDayWindow(edge), isNull);
    expect(glucoseLocalDayWindow(DateTime(2026, 9, 15, 8)), isNotNull);
  });

  test('present corrupt imported_at is partial; null stamp is not', () {
    Map<String, dynamic> row({
      required String uuid,
      required int ts,
      Object? importedAt,
    }) =>
        {
          'uuid': uuid,
          'ts': ts,
          'kind': 'glucose',
          'value': 5.2,
          'unit': kGlucoseUnitMillimolePerLiter,
          'source': 'Dexcom',
          'source_key': 'legacy:Dexcom',
          'imported_at': importedAt,
        };
    final snap = buildGlucoseSnapshot(
      rows: [
        row(uuid: 'legacy-null', ts: 20, importedAt: null),
        row(uuid: 'valid-older', ts: 10, importedAt: 50),
        row(
          uuid: 'corrupt-newer',
          ts: 30,
          importedAt: kGlucoseEpochSecMax + 1,
        ),
      ],
      settings: const [],
      receipt: null,
    );
    expect(snap.history.map((r) => r.uuid), [
      'corrupt-newer',
      'legacy-null',
      'valid-older',
    ]);
    expect(snap.unreadableCount, 1);
    expect(
      snap.lastImportedAt,
      DateTime.fromMillisecondsSinceEpoch(50 * 1000),
    );
    expect(glucoseImportedAtMalformed(null), isFalse);
    expect(glucoseImportedAtMalformed(kGlucoseEpochSecMax + 1), isTrue);
    expect(glucoseImportedAtMalformed(double.infinity), isTrue);
  });

  test('limit 200 with extra corrupt rows is not endlessly truncated', () async {
    final r = repo()..clearGlucoseReadings();
    const source = GlucoseSourceIdentity(
      key: SyntheticOpenBandRepository.glucoseFixtureSourceKey,
      sourceName: 'Sensor-App (synthetisch) via Apple Health',
      provenance: GlucoseSourceProvenance.synthetic,
    );
    r.seedGlucoseReading(
      GlucoseReading(
        uuid: 'v1',
        measuredAt: DateTime(2026, 9, 15, 8),
        value: 5.2,
        rawUnit: kGlucoseUnitMillimolePerLiter,
        unitKind: GlucoseUnitKind.millimolePerLiter,
        source: source,
      ),
    );
    r.seedGlucoseReading(
      GlucoseReading(
        uuid: 'v0',
        measuredAt: DateTime(2026, 9, 15, 7),
        value: 5.0,
        rawUnit: kGlucoseUnitMillimolePerLiter,
        unitKind: GlucoseUnitKind.millimolePerLiter,
        source: source,
      ),
    );
    for (var i = 0; i < 3; i++) {
      r.seedGlucoseReading(
        GlucoseReading(
          uuid: '',
          measuredAt: DateTime(2026, 9, 15, 9, i),
          value: 9.9,
          rawUnit: kGlucoseUnitMillimolePerLiter,
          unitKind: GlucoseUnitKind.millimolePerLiter,
          source: source,
        ),
      );
    }
    final snap = await r.readGlucose(limit: 200);
    expect(snap.history, hasLength(2));
    expect(snap.truncated, isFalse);
    expect(snap.sources.single.readingCount, 5);
    expect(snap.unreadableCount, 3);
    expect(snap.lastMeasuredAt, DateTime(2026, 9, 15, 8));
  });
}
