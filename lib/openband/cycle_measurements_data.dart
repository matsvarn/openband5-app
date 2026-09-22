// Typed cycle-night RHR / session HRV. Repositories decode storage here.
// Civil-date arithmetic only; no medians, MDC, z, or invented substitutes.

import 'cycle_data.dart';

const int kCycleMeasurementMaxNights = 120;
const int kCycleMeasurementMillisFloor = 1;

const List<double?> kCyclePaperRhr = [
  51, 52, 50, 54, 53, null, null, 55, 52, 53, 54, 56, 54, 55, null, 56, 57, 55,
  54, null, 56, 55, 54,
];

const List<double?> kCyclePaperHrv = [
  49, 46, 50, null, 47, null, null, 51, 46, 49, 45, 43, 47, 48, null, 44, 42, 46,
  null, null, 47, 48, null,
];

const String kCyclePaperStartDay = '2026-08-24';
const String kCyclePaperAsOfDay = '2026-09-15';

enum CycleMeasurementsReason {
  available,
  metricUnavailable,
  emptyStarts,
  trackingDisabled,
  unreadableStarts,
  selectedStartMissing,
}

enum CycleNightDisposition { missing, eligible, excluded, unreadable }

const Set<String> kCycleMeasurementSleepSources = {
  'auto',
  'auto_fallback',
  'manual',
  'confirmed',
};

const Set<String> kCycleMeasurementRefusedSleepSources = {
  'none',
  'rejected',
};

class CycleMeasurementPeriod {
  const CycleMeasurementPeriod({
    required this.startDay,
    required this.endDay,
    required this.open,
  });

  final String startDay;
  final String endDay;
  final bool open;

  int get lengthDays => cycleDiffDays(startDay, endDay) + 1;

  @override
  bool operator ==(Object other) =>
      other is CycleMeasurementPeriod &&
      other.startDay == startDay &&
      other.endDay == endDay &&
      other.open == open;

  @override
  int get hashCode => Object.hash(startDay, endDay, open);
}

class CycleNightMetric {
  const CycleNightMetric({
    required this.value,
    this.confidence,
    this.confidenceUnreadable = false,
    this.note,
    this.tier,
    this.inputsUsed = const [],
  });

  final double value;
  final double? confidence;
  /// Stored confidence was present but not finite 0..1. [confidence] stays null;
  /// the numeric value is kept. UI addition: treat as unknown, do not clamp.
  final bool confidenceUnreadable;
  final String? note;
  final String? tier;
  final List<String> inputsUsed;

  @override
  bool operator ==(Object other) =>
      other is CycleNightMetric &&
      other.value == value &&
      other.confidence == confidence &&
      other.confidenceUnreadable == confidenceUnreadable &&
      other.note == note &&
      other.tier == tier &&
      _sameStrings(other.inputsUsed, inputsUsed);

  @override
  int get hashCode => Object.hash(
        value,
        confidence,
        confidenceUnreadable,
        note,
        tier,
        Object.hashAll(inputsUsed),
      );
}

class CycleMetricLatest {
  const CycleMetricLatest({required this.day, required this.value});

  final String day;
  final double value;

  @override
  bool operator ==(Object other) =>
      other is CycleMetricLatest && other.day == day && other.value == value;

  @override
  int get hashCode => Object.hash(day, value);
}

class CycleNightMeasurement {
  const CycleNightMeasurement({
    required this.day,
    required this.cycleDay,
    this.windowStart,
    this.windowEnd,
    this.rhr,
    this.hrv,
    this.rhrUnreadable = false,
    this.hrvUnreadable = false,
    this.algoVersion,
    this.sleepSource,
  });

  final String day;
  final int cycleDay;
  final DateTime? windowStart;
  final DateTime? windowEnd;
  final CycleNightMetric? rhr;
  final CycleNightMetric? hrv;
  /// Nested RHR envelope was present but malformed or mathematically invalid.
  /// [rhr] is then null; this is not known absence. UI addition.
  final bool rhrUnreadable;
  /// Nested session-HRV envelope was present but malformed or HRV < 0.
  /// [hrv] is then null; this is not known absence. UI addition.
  final bool hrvUnreadable;
  final int? algoVersion;
  final String? sleepSource;

  @override
  bool operator ==(Object other) =>
      other is CycleNightMeasurement &&
      other.day == day &&
      other.cycleDay == cycleDay &&
      other.windowStart == windowStart &&
      other.windowEnd == windowEnd &&
      other.rhr == rhr &&
      other.hrv == hrv &&
      other.rhrUnreadable == rhrUnreadable &&
      other.hrvUnreadable == hrvUnreadable &&
      other.algoVersion == algoVersion &&
      other.sleepSource == sleepSource;

  @override
  int get hashCode => Object.hash(
        day,
        cycleDay,
        windowStart,
        windowEnd,
        rhr,
        hrv,
        rhrUnreadable,
        hrvUnreadable,
        algoVersion,
        sleepSource,
      );
}

class CycleNightSourceRow {
  const CycleNightSourceRow({
    required this.day,
    required this.algoVersion,
    this.skipped = false,
    this.partial = false,
    this.payload,
    this.payloadUnreadable = false,
    this.jobBlocked = false,
    this.computedAtMs,
    this.resultComputedAtMs,
    this.correctionAction,
    this.correctionOnsetMs,
    this.correctionWakeMs,
  });

  final String day;
  final int algoVersion;
  final bool skipped;
  final bool partial;
  final Map<String, Object?>? payload;
  final bool payloadUnreadable;
  final bool jobBlocked;
  final int? computedAtMs;
  final int? resultComputedAtMs;
  final String? correctionAction;
  final int? correctionOnsetMs;
  final int? correctionWakeMs;
}

class CycleMeasurementsSnapshot {
  const CycleMeasurementsSnapshot({
    required this.asOfDay,
    required this.settings,
    required this.reason,
    this.selectedStartDay,
    this.selected,
    this.periods = const [],
    this.nights = const [],
    this.truncated = false,
    this.firstCycleDay = 1,
    this.latestRhr,
    this.latestHrv,
    this.excludedCount = 0,
    this.unreadableCount = 0,
    this.partial = false,
  });

  final String asOfDay;
  final CycleSettings settings;
  final CycleMeasurementsReason reason;
  final String? selectedStartDay;
  final CycleMeasurementPeriod? selected;
  final List<CycleMeasurementPeriod> periods;
  final List<CycleNightMeasurement> nights;
  final bool truncated;
  final int firstCycleDay;
  final CycleMetricLatest? latestRhr;
  final CycleMetricLatest? latestHrv;
  final int excludedCount;
  final int unreadableCount;
  final bool partial;

  int get visibleNights => nights.length;
  int get rhrAvailableCount => [for (final n in nights) if (n.rhr != null) n].length;
  int get hrvAvailableCount => [for (final n in nights) if (n.hrv != null) n].length;

  @override
  bool operator ==(Object other) =>
      other is CycleMeasurementsSnapshot &&
      other.asOfDay == asOfDay &&
      other.settings == settings &&
      other.reason == reason &&
      other.selectedStartDay == selectedStartDay &&
      other.selected == selected &&
      _samePeriods(other.periods, periods) &&
      _sameNights(other.nights, nights) &&
      other.truncated == truncated &&
      other.firstCycleDay == firstCycleDay &&
      other.latestRhr == latestRhr &&
      other.latestHrv == latestHrv &&
      other.excludedCount == excludedCount &&
      other.unreadableCount == unreadableCount &&
      other.partial == partial;

  @override
  int get hashCode => Object.hash(
        asOfDay,
        settings,
        reason,
        selectedStartDay,
        selected,
        Object.hashAll(periods),
        Object.hashAll(nights),
        truncated,
        firstCycleDay,
        latestRhr,
        latestHrv,
        excludedCount,
        unreadableCount,
        partial,
      );
}

List<String> cycleCivilDaysInclusive(String from, String to) {
  requireCycleCalendarDay(from, 'from');
  requireCycleCalendarDay(to, 'to');
  final n = cycleDiffDays(from, to);
  if (n < 0) {
    throw ArgumentError.value(to, 'to', 'Expected a day on or after from.');
  }
  return [for (var i = 0; i <= n; i++) cycleAddDays(from, i)];
}

/// Stored-equivalent v90 payload. Session RMSSD is [hrv]; RHR is nocturnal
/// `low30_mean_bpm`. A missing metric stays absent — never a scalar fallback.
Map<String, Object?> cycleNightSourcePayload({
  double? rhr,
  double? hrv,
  required int onsetMs,
  required int offsetMs,
  String sleepSource = 'auto',
  bool imported = false,
  double? rmssdScalar,
  String? rhrNote,
  String? hrvNote,
  double? rhrConfidence,
  double? hrvConfidence,
}) {
  Object rhrValue;
  if (rhr == null) {
    rhrValue = '—';
  } else {
    rhrValue = <String, Object?>{'low30_mean_bpm': rhr};
  }
  return {
    'sleep_source': sleepSource,
    if (imported) 'imported': true,
    'sleep': {
      'window': {
        'value': {
          'onset_ms': onsetMs,
          'offset_ms': offsetMs,
        },
      },
    },
    'clinical': {
      'resting_hr': {
        'value': rhrValue,
        'confidence': ?rhrConfidence,
        'note': ?rhrNote,
        'tier': 'HIGH',
        'inputs_used': const ['hr_1hz', 'sleep_window'],
      },
      'rmssd_sleep_session': {
        'value': hrv ?? '—',
        'confidence': ?hrvConfidence,
        'note': ?hrvNote,
        'tier': 'HIGH',
        'inputs_used': const ['rr_sleep_window'],
      },
    },
    if (rmssdScalar != null) 'scalars': {'rmssd': rmssdScalar},
  };
}

int cycleNightOnsetMs(String day) {
  requireCycleCalendarDay(day);
  return cycleUtcDate(day)
      .subtract(const Duration(hours: 8))
      .millisecondsSinceEpoch;
}

int cycleNightOffsetMs(String day) {
  requireCycleCalendarDay(day);
  return cycleUtcDate(day).add(const Duration(hours: 6)).millisecondsSinceEpoch;
}

class CycleMeasurementSelection {
  const CycleMeasurementSelection({
    required this.reason,
    this.selectedStart,
    this.selected,
    this.periods = const [],
    this.visibleStart,
    this.truncated = false,
    this.firstCycleDay = 1,
  });

  final CycleMeasurementsReason? reason;
  final String? selectedStart;
  final CycleMeasurementPeriod? selected;
  final List<CycleMeasurementPeriod> periods;
  final String? visibleStart;
  final bool truncated;
  final int firstCycleDay;
}

CycleMeasurementSelection selectCycleMeasurementRange({
  required String asOfDay,
  required CycleSettings settings,
  required CycleLogParse log,
  String? cycleStartDay,
}) {
  requireCycleCalendarDay(asOfDay, 'asOfDay');
  if (cycleStartDay != null) {
    requireCycleCalendarDay(cycleStartDay, 'cycleStartDay');
  }
  if (!settings.enabled) {
    return const CycleMeasurementSelection(
      reason: CycleMeasurementsReason.trackingDisabled,
    );
  }

  final contributing = <String>[];
  var duplicate = false;
  for (final start in log.starts) {
    if (!start.contributes) continue;
    if (start.date.compareTo(asOfDay) > 0) continue;
    if (contributing.isNotEmpty &&
        start.date.compareTo(contributing.last) <= 0) {
      duplicate = true;
    }
    contributing.add(start.date);
  }

  if (log.unreadableStarts || duplicate) {
    return const CycleMeasurementSelection(
      reason: CycleMeasurementsReason.unreadableStarts,
    );
  }
  if (contributing.isEmpty) {
    return const CycleMeasurementSelection(
      reason: CycleMeasurementsReason.emptyStarts,
    );
  }

  final periods = <CycleMeasurementPeriod>[];
  for (var i = 0; i < contributing.length; i++) {
    final start = contributing[i];
    final next = i + 1 < contributing.length ? contributing[i + 1] : null;
    final rawEnd = next == null ? asOfDay : cycleAddDays(next, -1);
    final end = rawEnd.compareTo(asOfDay) <= 0 ? rawEnd : asOfDay;
    periods.add(
      CycleMeasurementPeriod(
        startDay: start,
        endDay: end,
        open: next == null,
      ),
    );
  }

  final selectedStart = cycleStartDay ?? contributing.last;
  if (!contributing.contains(selectedStart) ||
      selectedStart.compareTo(asOfDay) > 0) {
    return CycleMeasurementSelection(
      reason: CycleMeasurementsReason.selectedStartMissing,
      selectedStart: selectedStart,
      periods: List.unmodifiable(periods),
    );
  }

  CycleMeasurementPeriod? selected;
  for (final period in periods) {
    if (period.startDay == selectedStart) selected = period;
  }
  if (selected == null) {
    return CycleMeasurementSelection(
      reason: CycleMeasurementsReason.selectedStartMissing,
      selectedStart: selectedStart,
      periods: List.unmodifiable(periods),
    );
  }

  final truncated = selected.lengthDays > kCycleMeasurementMaxNights;
  final visibleStart = truncated
      ? cycleAddDays(selected.endDay, -(kCycleMeasurementMaxNights - 1))
      : selected.startDay;
  return CycleMeasurementSelection(
    reason: null,
    selectedStart: selectedStart,
    selected: selected,
    periods: List.unmodifiable(periods),
    visibleStart: visibleStart,
    truncated: truncated,
    firstCycleDay: cycleDiffDays(selected.startDay, visibleStart) + 1,
  );
}

CycleMeasurementsSnapshot buildCycleMeasurementsSnapshot({
  required String asOfDay,
  required CycleSettings settings,
  required CycleLogParse log,
  String? cycleStartDay,
  required int algoVersion,
  List<CycleNightSourceRow> rows = const [],
}) {
  final selection = selectCycleMeasurementRange(
    asOfDay: asOfDay,
    settings: settings,
    log: log,
    cycleStartDay: cycleStartDay,
  );

  CycleMeasurementsSnapshot withheld(CycleMeasurementsReason reason) =>
      CycleMeasurementsSnapshot(
        asOfDay: asOfDay,
        settings: settings,
        reason: reason,
        selectedStartDay: selection.selectedStart ?? cycleStartDay,
        periods: selection.periods,
      );

  if (selection.reason != null) return withheld(selection.reason!);
  final selected = selection.selected!;
  final visibleStart = selection.visibleStart!;
  final firstCycleDay = selection.firstCycleDay;
  final days = cycleCivilDaysInclusive(visibleStart, selected.endDay);

  final byDay = <String, CycleNightSourceRow>{};
  for (final row in rows) {
    if (row.algoVersion != algoVersion) continue;
    if (row.day.compareTo(visibleStart) < 0 ||
        row.day.compareTo(selected.endDay) > 0) {
      continue;
    }
    byDay[row.day] = row;
  }

  final nights = <CycleNightMeasurement>[];
  var excludedCount = 0;
  var unreadableCount = 0;
  CycleMetricLatest? latestRhr;
  CycleMetricLatest? latestHrv;

  for (var i = 0; i < days.length; i++) {
    final day = days[i];
    final cycleDay = firstCycleDay + i;
    final row = byDay[day];
    if (row == null) {
      nights.add(CycleNightMeasurement(day: day, cycleDay: cycleDay));
      continue;
    }
    final parsed = parseCycleNightSource(row, algoVersion: algoVersion);
    switch (parsed.disposition) {
      case CycleNightDisposition.unreadable:
        unreadableCount++;
        nights.add(CycleNightMeasurement(day: day, cycleDay: cycleDay));
      case CycleNightDisposition.excluded:
      case CycleNightDisposition.missing:
        if (parsed.disposition == CycleNightDisposition.excluded) {
          excludedCount++;
        }
        nights.add(CycleNightMeasurement(day: day, cycleDay: cycleDay));
      case CycleNightDisposition.eligible:
        nights.add(
          CycleNightMeasurement(
            day: day,
            cycleDay: cycleDay,
            windowStart: parsed.windowStart,
            windowEnd: parsed.windowEnd,
            rhr: parsed.rhr,
            hrv: parsed.hrv,
            rhrUnreadable: parsed.rhrUnreadable,
            hrvUnreadable: parsed.hrvUnreadable,
            algoVersion: algoVersion,
            sleepSource: parsed.sleepSource,
          ),
        );
        if (parsed.rhrUnreadable ||
            parsed.hrvUnreadable ||
            parsed.metadataUnreadable) {
          unreadableCount++;
        }
        if (parsed.rhr != null) {
          latestRhr = CycleMetricLatest(day: day, value: parsed.rhr!.value);
        }
        if (parsed.hrv != null) {
          latestHrv = CycleMetricLatest(day: day, value: parsed.hrv!.value);
        }
    }
  }

  final hasMetric = latestRhr != null || latestHrv != null;
  return CycleMeasurementsSnapshot(
    asOfDay: asOfDay,
    settings: settings,
    reason: hasMetric
        ? CycleMeasurementsReason.available
        : CycleMeasurementsReason.metricUnavailable,
    selectedStartDay: selection.selectedStart,
    selected: selected,
    periods: selection.periods,
    nights: List.unmodifiable(nights),
    truncated: selection.truncated,
    firstCycleDay: firstCycleDay,
    latestRhr: latestRhr,
    latestHrv: latestHrv,
    excludedCount: excludedCount,
    unreadableCount: unreadableCount,
    partial: excludedCount > 0 || unreadableCount > 0,
  );
}

class CycleNightParse {
  const CycleNightParse({
    required this.disposition,
    this.windowStart,
    this.windowEnd,
    this.rhr,
    this.hrv,
    this.rhrUnreadable = false,
    this.hrvUnreadable = false,
    this.metadataUnreadable = false,
    this.sleepSource,
  });

  final CycleNightDisposition disposition;
  final DateTime? windowStart;
  final DateTime? windowEnd;
  final CycleNightMetric? rhr;
  final CycleNightMetric? hrv;
  final bool rhrUnreadable;
  final bool hrvUnreadable;
  final bool metadataUnreadable;
  final String? sleepSource;
}

CycleNightParse parseCycleNightSource(
  CycleNightSourceRow row, {
  required int algoVersion,
}) {
  if (row.algoVersion != algoVersion) {
    return const CycleNightParse(disposition: CycleNightDisposition.missing);
  }
  if (row.skipped || row.partial || row.jobBlocked) {
    return const CycleNightParse(disposition: CycleNightDisposition.excluded);
  }
  if (cycleNightPredatesReceipt(row.computedAtMs, row.resultComputedAtMs)) {
    return const CycleNightParse(disposition: CycleNightDisposition.excluded);
  }
  if (row.payloadUnreadable || row.payload == null) {
    return const CycleNightParse(disposition: CycleNightDisposition.unreadable);
  }
  final payload = row.payload!;
  if (payload['imported'] == true) {
    return const CycleNightParse(disposition: CycleNightDisposition.excluded);
  }
  final source = payload['sleep_source'];
  if (source is! String ||
      kCycleMeasurementRefusedSleepSources.contains(source) ||
      !kCycleMeasurementSleepSources.contains(source)) {
    return CycleNightParse(
      disposition: CycleNightDisposition.excluded,
      sleepSource: source is String ? source : null,
    );
  }
  final window = _sleepWindow(payload);
  if (window == null) {
    return CycleNightParse(
      disposition: CycleNightDisposition.excluded,
      sleepSource: source,
    );
  }
  if (row.correctionAction != null &&
      row.correctionAction != 'override' &&
      row.correctionAction != 'automatic') {
    return CycleNightParse(
      disposition: CycleNightDisposition.unreadable,
      sleepSource: source,
    );
  }
  if (!cycleNightOverrideMatches(
        action: row.correctionAction,
        requestedOnsetMs: row.correctionOnsetMs,
        requestedWakeMs: row.correctionWakeMs,
        sleepSource: source,
        windowStart: window.$1,
        windowEnd: window.$2,
      )) {
    return CycleNightParse(
      disposition: CycleNightDisposition.excluded,
      sleepSource: source,
    );
  }
  final rhr = _readRestingHr(payload);
  final hrv = _readSessionHrv(payload);
  return CycleNightParse(
    disposition: CycleNightDisposition.eligible,
    windowStart: window.$1,
    windowEnd: window.$2,
    rhr: rhr.metric,
    hrv: hrv.metric,
    rhrUnreadable: rhr.unreadable,
    hrvUnreadable: hrv.unreadable,
    metadataUnreadable: rhr.metadataUnreadable || hrv.metadataUnreadable,
    sleepSource: source,
  );
}

/// True when the stored row is older than a completed correction receipt.
bool cycleNightPredatesReceipt(int? computedAtMs, int? resultComputedAtMs) {
  if (resultComputedAtMs == null || resultComputedAtMs <= 0) return false;
  return computedAtMs == null || computedAtMs < resultComputedAtMs;
}

/// Override publication: requested bounds at second precision, source manual
/// or confirmed. Automatic receipts keep prior bounds and are not compared.
/// Null action is no correction. Unknown actions are not treated as automatic.
bool cycleNightOverrideMatches({
  required String? action,
  required int? requestedOnsetMs,
  required int? requestedWakeMs,
  required String sleepSource,
  required DateTime windowStart,
  required DateTime windowEnd,
}) {
  if (action == null || action == 'automatic') return true;
  if (action != 'override') return false;
  if (sleepSource != 'manual' && sleepSource != 'confirmed') return false;
  if (requestedOnsetMs == null || requestedWakeMs == null) return false;
  return _publishedSleepSeconds(requestedOnsetMs, truncate: true) ==
          _publishedSleepSeconds(
            windowStart.millisecondsSinceEpoch,
            truncate: false,
          ) &&
      _publishedSleepSeconds(requestedWakeMs, truncate: true) ==
          _publishedSleepSeconds(
            windowEnd.millisecondsSinceEpoch,
            truncate: false,
          );
}

int _publishedSleepSeconds(int ms, {required bool truncate}) =>
    truncate ? ms ~/ 1000 : (ms / 1000).round();

(DateTime, DateTime)? _sleepWindow(Map<String, Object?> payload) {
  final onset = _epochMs(_at(payload, 'sleep.window.value.onset_ms'));
  final offset = _epochMs(_at(payload, 'sleep.window.value.offset_ms'));
  if (onset == null || offset == null || !offset.isAfter(onset)) return null;
  return (onset, offset);
}

class _NightMetricParse {
  const _NightMetricParse({
    this.metric,
    this.unreadable = false,
    this.metadataUnreadable = false,
  });

  final CycleNightMetric? metric;
  final bool unreadable;
  final bool metadataUnreadable;
}

bool _knownAbsent(Object? value) => value == null || value == '—';

_NightMetricParse _readClinicalEnvelope(
  Map<String, Object?> payload,
  String key,
  _NightMetricParse Function(Map<Object?, Object?> env) read,
) {
  if (!payload.containsKey('clinical')) return const _NightMetricParse();
  final clinical = payload['clinical'];
  if (clinical == null) return const _NightMetricParse();
  if (clinical is! Map) return const _NightMetricParse(unreadable: true);
  if (!clinical.containsKey(key)) return const _NightMetricParse();
  final raw = clinical[key];
  if (raw == null) return const _NightMetricParse();
  if (raw is! Map) return const _NightMetricParse(unreadable: true);
  if (!raw.containsKey('value')) {
    return const _NightMetricParse(unreadable: true);
  }
  if (_knownAbsent(raw['value'])) return const _NightMetricParse();
  return read(Map<Object?, Object?>.from(raw));
}

_NightMetricParse _readRestingHr(Map<String, Object?> payload) {
  return _readClinicalEnvelope(payload, 'resting_hr', (env) {
    final value = env['value'];
    if (value is! Map || !value.containsKey('low30_mean_bpm')) {
      return const _NightMetricParse(unreadable: true);
    }
    final bpm = _finiteNum(value['low30_mean_bpm']);
    if (bpm == null || bpm <= 0) {
      return const _NightMetricParse(unreadable: true);
    }
    return _metricFromEnvelope(env, bpm);
  });
}

_NightMetricParse _readSessionHrv(Map<String, Object?> payload) {
  return _readClinicalEnvelope(payload, 'rmssd_sleep_session', (env) {
    final value = _finiteNum(env['value']);
    if (value == null || value < 0) {
      return const _NightMetricParse(unreadable: true);
    }
    return _metricFromEnvelope(env, value);
  });
}

_NightMetricParse _metricFromEnvelope(Map<Object?, Object?> env, double value) {
  final confidence = _storedConfidence(env['confidence']);
  return _NightMetricParse(
    metric: CycleNightMetric(
      value: value,
      confidence: confidence.value,
      confidenceUnreadable: confidence.unreadable,
      note: _optionalNote(env['note']),
      tier: _optionalString(env['tier']),
      inputsUsed: _inputs(env['inputs_used']),
    ),
    metadataUnreadable: confidence.unreadable,
  );
}

({double? value, bool unreadable}) _storedConfidence(Object? raw) {
  if (raw == null) return (value: null, unreadable: false);
  final n = _finiteNum(raw);
  if (n == null || n < 0 || n > 1) {
    return (value: null, unreadable: true);
  }
  return (value: n, unreadable: false);
}

Object? _at(Map<String, Object?> map, String path) {
  Object? current = map;
  for (final part in path.split('.')) {
    if (current is! Map) return null;
    current = current[part];
  }
  return current;
}

double? _finiteNum(Object? raw) {
  if (raw is! num || !raw.isFinite) return null;
  return raw.toDouble();
}

DateTime? _epochMs(Object? raw) {
  final value = _finiteNum(raw);
  if (value == null || value < kCycleMeasurementMillisFloor) return null;
  if (value.abs() > 8640000000000000) return null;
  return DateTime.fromMillisecondsSinceEpoch(value.round(), isUtc: true);
}

String? _optionalNote(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return raw;
}

String? _optionalString(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return raw;
}

List<String> _inputs(Object? raw) {
  if (raw is! List) return const [];
  final out = <String>[];
  for (final item in raw) {
    if (item is! String) return const [];
    out.add(item);
  }
  return List.unmodifiable(out);
}

bool _sameStrings(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _samePeriods(
  List<CycleMeasurementPeriod> a,
  List<CycleMeasurementPeriod> b,
) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameNights(
  List<CycleNightMeasurement> a,
  List<CycleNightMeasurement> b,
) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
