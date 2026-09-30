import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:openstrap_edge/health/glucose_contract.dart';
import 'package:openstrap_edge/health/health_measurement_import.dart';

HealthDataPoint _p(
  HealthDataType type,
  num value, {
  String uuid = 'u1',
  String source = 'Omron Connect',
  String sourceId = 'src',
  HealthDataUnit? unit,
}) {
  final resolved = unit ??
      switch (type) {
        HealthDataType.BLOOD_GLUCOSE => HealthDataUnit.MILLIGRAM_PER_DECILITER,
        HealthDataType.BODY_TEMPERATURE => HealthDataUnit.DEGREE_CELSIUS,
        _ => HealthDataUnit.MILLIMETER_OF_MERCURY,
      };
  return HealthDataPoint(
    uuid: uuid,
    value: NumericHealthValue(numericValue: value),
    type: type,
    unit: resolved,
    dateFrom: DateTime(2026, 8, 1, 9),
    dateTo: DateTime(2026, 8, 1, 9),
    sourceId: sourceId,
    sourcePlatform: HealthPlatformType.appleHealth,
    sourceDeviceId: 'dev',
    sourceName: source,
  );
}

void main() {
  test('a cuff reading keeps the cuff\'s name', () {
    final rows = rowsFrom([_p(HealthDataType.BLOOD_PRESSURE_SYSTOLIC, 128)]);
    expect(rows.single['kind'], kKindSystolic);
    expect(rows.single['value'], 128.0);
    expect(rows.single['source'], 'Omron Connect');
    expect(rows.single['source_id'], 'src');
    expect(rows.single['source_key'], 'apple:src');
    expect(rows.single['unit'], 'MILLIMETER_OF_MERCURY');
  });

  test('an out-of-range reading is DROPPED, never clamped', () {
    final rows = rowsFrom([
      _p(HealthDataType.BLOOD_PRESSURE_SYSTOLIC, 400, uuid: 'bad'),
      _p(HealthDataType.BLOOD_PRESSURE_SYSTOLIC, 118, uuid: 'good'),
    ]);
    expect(rows.map((r) => r['uuid']), ['good']);
  });

  test('a record with no uuid is skipped rather than given a synthetic key',
      () {
    final parsed = parseImportedPoints([
      _p(HealthDataType.BLOOD_GLUCOSE, 95, uuid: ''),
    ]);
    expect(parsed.rows, isEmpty);
    expect(parsed.invalidCount, 1);
  });

  test('the same uuid twice lands once', () {
    final parsed = parseImportedPoints([
      _p(HealthDataType.BLOOD_GLUCOSE, 95, uuid: 'g'),
      _p(HealthDataType.BLOOD_GLUCOSE, 95, uuid: 'g'),
    ]);
    expect(parsed.rows.length, 1);
    expect(parsed.ignoredCount, 1);
  });

  test('a type we do not import is ignored, not mis-filed', () {
    final parsed = parseImportedPoints([
      _p(HealthDataType.HEART_RATE, 60, uuid: 'h'),
    ]);
    expect(parsed.rows, isEmpty);
    expect(parsed.invalidCount, 0);
  });

  test('an unnamed source keeps raw identity, not Unknown app', () {
    final rows = rowsFrom([
      _p(
        HealthDataType.BODY_TEMPERATURE,
        36.8,
        uuid: 't',
        source: '  ',
        sourceId: '',
      ),
    ]);
    expect(rows.single['source'], '  ');
    expect(rows.single['source_id'], isNull);
    expect(rows.single['source_key'], kAppleUnknownSourceKey);
  });

  test('NaN and infinity are dropped, not stored', () {
    final parsed = parseImportedPoints([
      _p(HealthDataType.BLOOD_GLUCOSE, double.nan, uuid: 'nan'),
      _p(HealthDataType.BLOOD_GLUCOSE, double.infinity, uuid: 'inf'),
      _p(HealthDataType.BLOOD_GLUCOSE, double.negativeInfinity, uuid: 'ninf'),
      _p(HealthDataType.BLOOD_GLUCOSE, 95, uuid: 'ok'),
    ]);
    expect(parsed.rows.single['uuid'], 'ok');
    expect(parsed.invalidCount, 3);
  });

  test('glucose keeps 95 mg/dL and drops 5.2 in the plugin unit', () {
    final parsed = parseImportedPoints([
      _p(HealthDataType.BLOOD_GLUCOSE, 95, uuid: 'mg'),
      _p(HealthDataType.BLOOD_GLUCOSE, 5.2, uuid: 'mmol-shaped'),
    ]);
    expect(parsed.rows.single['uuid'], 'mg');
    expect(parsed.rows.single['unit'], kGlucoseUnitMilligramPerDeciliter);
    expect(parsed.invalidCount, 1);
  });

  test('glucose with a cuff unit is rejected, not converted', () {
    final parsed = parseImportedPoints([
      _p(
        HealthDataType.BLOOD_GLUCOSE,
        95,
        uuid: 'wrong',
        unit: HealthDataUnit.MILLIMETER_OF_MERCURY,
      ),
    ]);
    expect(parsed.rows, isEmpty);
    expect(parsed.invalidCount, 1);
  });

  test('body temperature still requires Celsius', () {
    final ok = rowsFrom([_p(HealthDataType.BODY_TEMPERATURE, 36.8, uuid: 'c')]);
    expect(ok, hasLength(1));
    final bad = parseImportedPoints([
      _p(
        HealthDataType.BODY_TEMPERATURE,
        36.8,
        uuid: 'f',
        unit: HealthDataUnit.MILLIMETER_OF_MERCURY,
      ),
    ]);
    expect(bad.rows, isEmpty);
    expect(bad.invalidCount, 1);
  });

  test('Android source key uses the package name, not an empty sourceId', () {
    final rows = rowsFrom([
      _p(
        HealthDataType.BLOOD_GLUCOSE,
        95,
        source: 'com.dexcom.g7',
        sourceId: '',
      ),
    ], isApple: false);
    expect(rows.single['source_key'], 'android:com.dexcom.g7');
    expect(rows.single['source_id'], isNull);
  });
}
