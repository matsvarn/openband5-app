// Import measurements from devices that are CLEARED to take them.
//
// A blood-pressure cuff measures blood pressure. A CGM measures glucose. A
// thermometer measures core temperature. None of those is a thing this app can
// derive from a wrist, and the honest way for those numbers to sit next to your
// sleep is for the device that is allowed to measure them to measure them, and
// for us to show the reading with that device's name on it.
//
// ⚠️ READ-ONLY INPUTS TO DISPLAY. NEVER TRAINING TARGETS. ⚠️
// Read the guard on `_createImportedMeasurement` in db.dart. It is repeated
// there and here deliberately: the moment a cuff series and a wrist PPG series
// live in one database, the obvious next idea is to fit one to the other, and
// that idea is a cuffless-blood-pressure claim from an uncleared device. These
// rows may be shown beside ours. They may never be regressed against ours, and
// nothing derived may take one as an input.
//
// NEVER BLENDED. There is no combined series, no "your blood pressure" without
// the cuff's name on it, and no averaging of an imported reading with anything
// of ours. The source name is a NOT NULL column for that reason.
//
// This is the ONLY honest route to blood pressure or glucose in this app. Both
// are permanently refused as things OpenStrap computes.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import '../data/db.dart';
import 'glucose_contract.dart';

/// Stable `imported_measurement.kind` keys. Written to the database, so they
/// are contract: rename one and every stored row orphans.
const String kKindSystolic = 'bp_systolic';
const String kKindDiastolic = 'bp_diastolic';
const String kKindGlucose = 'glucose';
const String kKindBodyTemp = 'body_temp';

const Map<HealthDataType, String> kImportedKinds = {
  HealthDataType.BLOOD_PRESSURE_SYSTOLIC: kKindSystolic,
  HealthDataType.BLOOD_PRESSURE_DIASTOLIC: kKindDiastolic,
  HealthDataType.BLOOD_GLUCOSE: kKindGlucose,
  HealthDataType.BODY_TEMPERATURE: kKindBodyTemp,
};

/// Plausibility bounds per kind, in the plugin's canonical unit (mmHg, mg/dL,
/// °C). A reading outside these is a bad record — a cuff error code, a stuck
/// sensor, a unit mix-up — and it is DROPPED rather than clamped: a clamped
/// reading is a fabricated one, and this is a table of other people's
/// measurements where we have no standing to invent anything.
const Map<String, (double, double)> kImportedBounds = {
  kKindSystolic: (50, 300),
  kKindDiastolic: (20, 200),
  kKindGlucose: (10, 1000),
  kKindBodyTemp: (25, 45),
};

bool importedUnitCorrect(String kind, HealthDataUnit unit) {
  switch (kind) {
    case kKindSystolic:
    case kKindDiastolic:
      return unit == HealthDataUnit.MILLIMETER_OF_MERCURY;
    case kKindGlucose:
      return unit == HealthDataUnit.MILLIGRAM_PER_DECILITER;
    case kKindBodyTemp:
      return unit == HealthDataUnit.DEGREE_CELSIUS;
    default:
      return false;
  }
}

class ImportedPointParse {
  final List<Map<String, Object?>> rows;
  final int invalidCount;
  final int ignoredCount;
  final Map<String, int> invalidByKind;
  final Map<String, int> ignoredByKind;
  const ImportedPointParse({
    required this.rows,
    this.invalidCount = 0,
    this.ignoredCount = 0,
    this.invalidByKind = const {},
    this.ignoredByKind = const {},
  });
}

/// Turn raw health-store points into `imported_measurement` rows, dropping
/// anything unusable. Pure, so the filtering is testable without a store.
@visibleForTesting
List<Map<String, Object?>> rowsFrom(
  List<HealthDataPoint> points, {
  bool isApple = true,
}) =>
    parseImportedPoints(points, isApple: isApple).rows;

@visibleForTesting
ImportedPointParse parseImportedPoints(
  List<HealthDataPoint> points, {
  bool isApple = true,
}) {
  final out = <Map<String, Object?>>[];
  final seen = <String>{};
  var invalid = 0;
  var ignored = 0;
  final invalidByKind = <String, int>{};
  final ignoredByKind = <String, int>{};
  void bumpInvalid(String kind) {
    invalid++;
    invalidByKind[kind] = (invalidByKind[kind] ?? 0) + 1;
  }

  void bumpIgnored(String kind) {
    ignored++;
    ignoredByKind[kind] = (ignoredByKind[kind] ?? 0) + 1;
  }

  for (final p in points) {
    final kind = kImportedKinds[p.type];
    if (kind == null) continue;
    final v = p.value;
    if (v is! NumericHealthValue) {
      bumpInvalid(kind);
      continue;
    }
    final value = v.numericValue.toDouble();
    if (!value.isFinite) {
      bumpInvalid(kind);
      continue;
    }
    if (!importedUnitCorrect(kind, p.unit)) {
      bumpInvalid(kind);
      continue;
    }
    final bounds = kImportedBounds[kind];
    if (bounds != null && (value < bounds.$1 || value > bounds.$2)) {
      bumpInvalid(kind);
      continue;
    }
    if (p.uuid.isEmpty) {
      bumpInvalid(kind);
      continue;
    }
    if (!seen.add(p.uuid)) {
      bumpIgnored(kind);
      continue;
    }
    final sourceName = p.sourceName;
    final sourceId = p.sourceId;
    out.add({
      'uuid': p.uuid,
      'ts': p.dateTo.millisecondsSinceEpoch ~/ 1000,
      'kind': kind,
      'value': value,
      'unit': p.unit.name,
      'source': sourceName,
      'source_id': sourceId.trim().isEmpty ? null : sourceId.trim(),
      'source_key': importedSourceKey(
        isApple: isApple,
        sourceId: sourceId,
        sourceName: sourceName,
      ),
    });
  }
  return ImportedPointParse(
    rows: out,
    invalidCount: invalid,
    ignoredCount: ignored,
    invalidByKind: invalidByKind,
    ignoredByKind: ignoredByKind,
  );
}

class ImportedMeasurementImporter {
  ImportedMeasurementImporter({
    Health? health,
    bool? isApple,
    Future<ImportedMeasurementCommitResult> Function(
      ImportedMeasurementCommitInput input,
    )? commit,
    DateTime Function()? clock,
  })  : _health = health ?? Health(),
        _isApple = isApple ?? (Platform.isIOS || Platform.isMacOS),
        _commit = commit ?? LocalDb.commitImportedMeasurements,
        _clock = clock;

  final Health _health;
  final bool _isApple;
  final Future<ImportedMeasurementCommitResult> Function(
    ImportedMeasurementCommitInput input,
  ) _commit;
  final DateTime Function()? _clock;

  DateTime _wallNow() => _clock?.call() ?? DateTime.now();

  static const List<HealthDataType> types = [
    HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
    HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
    HealthDataType.BLOOD_GLUCOSE,
    HealthDataType.BODY_TEMPERATURE,
  ];

  static const List<HealthDataType> glucoseOnly = [
    HealthDataType.BLOOD_GLUCOSE,
  ];

  Future<HealthMeasurementImportOutcome> sync({
    List<HealthDataType>? types,
    DateTime? now,
  }) {
    final requested = types ?? ImportedMeasurementImporter.types;
    // One process-wide queue for Health I/O and the matching commit. Per-instance
    // in-flight flags cannot order two Phone Import / Jetzt-lesen objects.
    return LocalDb.runImportedMeasurementOp(
      () => _sync(requested: requested, now: now),
    );
  }

  Future<HealthMeasurementImportOutcome> _sync({
    required List<HealthDataType> requested,
    DateTime? now,
  }) async {
    final attemptedAt = now ?? _wallNow();
    final kinds = [
      for (final t in requested)
        if (kImportedKinds[t] != null) kImportedKinds[t]!,
    ];
    try {
      await _health.configure();
    } catch (e) {
      debugPrint('[imported_measurement] configure: $e');
      return _fail(
        HealthMeasurementImportStatus.authorizationRequestFailed,
        attemptedAt,
        kinds,
      );
    }

    final perms = [for (final _ in requested) HealthDataAccess.READ];
    bool? already;
    try {
      already = await _health.hasPermissions(requested, permissions: perms);
    } catch (e) {
      debugPrint('[imported_measurement] permission: $e');
      return _fail(
        HealthMeasurementImportStatus.authorizationRequestFailed,
        attemptedAt,
        kinds,
      );
    }

    if (already != true) {
      try {
        await _health.requestAuthorization(requested, permissions: perms);
      } catch (e) {
        debugPrint('[imported_measurement] permission: $e');
        return _fail(
          HealthMeasurementImportStatus.authorizationRequestFailed,
          attemptedAt,
          kinds,
        );
      }
    }
    if (!_isApple) {
      try {
        final proven = await _health.hasPermissions(
          requested,
          permissions: perms,
        );
        if (proven == false) {
          return _fail(
            HealthMeasurementImportStatus.authorizationDenied,
            attemptedAt,
            kinds,
          );
        }
      } catch (e) {
        debugPrint('[imported_measurement] permission: $e');
        return _fail(
          HealthMeasurementImportStatus.authorizationRequestFailed,
          attemptedAt,
          kinds,
        );
      }
    }

    final end = attemptedAt;
    // Health Connect caps third-party reads at 30 days without
    // READ_HEALTH_DATA_HISTORY. Pinned health 12.2.1 can request that
    // permission; this app does not declare or ask for it — so Android still
    // gets the 30-day window. A year on Apple is enough for occasional meters.
    final start = _isApple
        ? DateTime(end.year - 1, end.month, end.day)
        : end.subtract(const Duration(days: 30));

    List<HealthDataPoint> points;
    try {
      points = await _health.getHealthDataFromTypes(
        types: requested,
        startTime: start,
        endTime: end,
      );
    } catch (e) {
      debugPrint('[imported_measurement] read: $e');
      return _fail(
        HealthMeasurementImportStatus.readFailed,
        attemptedAt,
        kinds,
      );
    }

    final parsed = parseImportedPoints(points, isApple: _isApple);
    final storedAt = _wallNow();
    try {
      final committed = await _commit(
        ImportedMeasurementCommitInput(
          rows: parsed.rows,
          kinds: kinds,
          attemptedAt: attemptedAt,
          storedAt: storedAt,
          invalidByKind: parsed.invalidByKind,
          ignoredByKind: parsed.ignoredByKind,
        ),
      );
      final status = parsed.invalidCount > 0
          ? HealthMeasurementImportStatus.partial
          : committed.storedCount > 0
              ? HealthMeasurementImportStatus.stored
              : HealthMeasurementImportStatus.empty;
      return HealthMeasurementImportOutcome(
        status: status,
        attemptedAt: attemptedAt,
        storedCount: committed.storedCount,
        writtenCount: committed.writtenCount,
        invalidCount: parsed.invalidCount,
        ignoredCount: parsed.ignoredCount + committed.skippedExcluded,
      );
    } catch (e) {
      debugPrint('[imported_measurement] persist: $e');
      await _fail(
        HealthMeasurementImportStatus.persistenceFailed,
        attemptedAt,
        kinds,
        invalidByKind: parsed.invalidByKind,
        ignoredByKind: parsed.ignoredByKind,
      );
      return HealthMeasurementImportOutcome(
        status: HealthMeasurementImportStatus.persistenceFailed,
        attemptedAt: attemptedAt,
        invalidCount: parsed.invalidCount,
        ignoredCount: parsed.ignoredCount,
      );
    }
  }

  Future<HealthMeasurementImportOutcome> _fail(
    HealthMeasurementImportStatus status,
    DateTime attemptedAt,
    List<String> kinds, {
    Map<String, int> invalidByKind = const {},
    Map<String, int> ignoredByKind = const {},
  }) async {
    final invalidCount =
        invalidByKind.values.fold<int>(0, (sum, n) => sum + n);
    final ignoredCount =
        ignoredByKind.values.fold<int>(0, (sum, n) => sum + n);
    try {
      await _commit(
        ImportedMeasurementCommitInput(
          rows: const [],
          kinds: kinds,
          attemptedAt: attemptedAt,
          forcedOutcome: status.name,
          invalidByKind: invalidByKind,
          ignoredByKind: ignoredByKind,
          persistRows: false,
        ),
      );
    } catch (e) {
      debugPrint('[imported_measurement] receipt: $e');
    }
    return HealthMeasurementImportOutcome(
      status: status,
      attemptedAt: attemptedAt,
      invalidCount: invalidCount,
      ignoredCount: ignoredCount,
    );
  }
}
