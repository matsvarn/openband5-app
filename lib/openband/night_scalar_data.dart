// Typed HRV / resting-pulse / respiration / skin-temperature night scalars.
// Repositories decode storage here. HRV/RHR use SQL `rmssd`/`rhr`; respiration
// uses payload `scalars.resp_rate`; skin temperature uses payload
// `scalars.skin_temp_z` only (no ADC / baselines.skin_temp / metric_series
// headline fallback). Not session envelopes or day curves. Civil-date windows;
// no interpolation, refold, or invented provenance.

import 'dart:convert';

import '../data/day_label.dart';

const Set<int> kNightScalarNights = {7, 30, 90};
const int kNightScalarPayloadBatchSize = 32;

const int kNightScalarMillisFloor = 1;

/// Paper fixture nights ending 2026-09-15: 14 stored priors plus selected 48.
const List<double> kNightScalarPaperHrv = [
  32, 42, 36, 44, 38, 46, 34, 42, 36, 44, 38, 46, 40, 40, 48,
];

/// Paper fixture nights ending 2026-09-15: 14 stored priors plus selected 54.
const List<double> kNightScalarPaperRhr = [
  53, 59, 54, 58, 55, 57, 56, 56, 57, 55, 56, 55, 57, 56, 54,
];

const double kNightScalarPaperHrvBaseline = 40;
const double kNightScalarPaperRhrBaseline = 56;

/// Paper normal ranges (baseline ± 1.253 × spread): HRV 36–44 ms, RHR 53–59.
const double kNightScalarPaperHrvSpread = 4 / 1.253;
const double kNightScalarPaperRhrSpread = 3 / 1.253;

double? nightScalarPaperSpread(NightScalarMetric metric) => switch (metric) {
  NightScalarMetric.hrv => kNightScalarPaperHrvSpread,
  NightScalarMetric.rhr => kNightScalarPaperRhrSpread,
  _ => null,
};
const double kNightScalarPaperRespRate = 16;

/// Paper fixture nights ending 2026-09-15: 14 stored priors plus selected 16.
const List<double> kNightScalarPaperResp = [
  14, 18, 14.5, 17.5, 15, 17, 15.5, 16.5, 14, 18, 15, 17, 15.5, 16.5, 16,
];

/// Paper skin-temperature SD, last 15 of 30 ending 2026-09-15. One real gap.
/// Selected +0.4 SD. Lead 01M2TRX5GZKAXKTSXK7D34E8AY: canonical signed 4YO1 /
/// dark 4YSR; SD main 4YPE / dark 4YTK; unknown 4YXJ / dark 4YZS; C 4Z21 /
/// dark 4Z4A.
const List<double?> kNightScalarPaperSkinTempSd = [
  -0.2, -0.1, 0, 0.1, null, 0.2, 0.1, 0.3, 0.2, -0.1, 0.1, 0.3, 0.2, 0.5, 0.4,
];

/// Same positions as [kNightScalarPaperSkinTempSd] as 32.8 + v °C. Selected 33.2.
const List<double?> kNightScalarPaperSkinTempC = [
  32.6, 32.7, 32.8, 32.9, null, 33.0, 32.9, 33.1, 33.0, 32.7, 32.9, 33.1, 33.0,
  33.3, 33.2,
];

const double kNightScalarPaperSkinTempSdSelected = 0.4;
const double kNightScalarPaperSkinTempCSelected = 33.2;
const double kNightScalarPaperSkinTempCOffset = 32.8;

const String kNightScalarPaperDay = '2026-09-15';

enum NightScalarMetric {
  hrv,
  rhr,
  respiration,
  skinTemperature;

  String get series => switch (this) {
    hrv => 'rmssd',
    rhr => 'rhr',
    respiration => 'resp_rate',
    skinTemperature => 'skin_temp_z',
  };

  String get baselinePath => switch (this) {
    hrv => 'hrv',
    rhr => 'resting_hr',
    respiration => 'resp',
    skinTemperature => 'skin_temp',
  };

  String? get sqlColumn => switch (this) {
    hrv => 'rmssd',
    rhr => 'rhr',
    respiration => null,
    skinTemperature => null,
  };

  String? get payloadScalar => switch (this) {
    respiration => 'resp_rate',
    skinTemperature => 'skin_temp_z',
    _ => null,
  };
}

/// Physical quantity of a published night scalar. Skin temperature is SD
/// (band relative deviation) or Celsius (WHOOP export). Other metrics leave
/// this unset. UI must switch on this enum — never on source strings.
enum NightScalarUnit {
  /// Relative deviation in standard deviations (`source = band`).
  sd,

  /// Absolute degrees Celsius (`whoop_export`, including null-column legacy).
  celsius,

  /// Quantity cannot be determined. Do not plot, mix, or call it missing.
  unknown;

  bool get isKnown => this == sd || this == celsius;
}

enum NightScalarState {
  current,
  older,
  partial,
  pending,
  failed,
  missing,
  unreadable,
  unknown,
  outdated,
}

const String kNightScalarPendingLabel = 'Auswertung läuft';
const String kNightScalarOpenLabel = 'Auswertung offen';
const String kNightScalarFailedLabel = 'Auswertung fehlgeschlagen';
const String kNightScalarUnknownUnitLabel = 'Einheit unbekannt';
const String kNightScalarTrustedBaseline = 'trusted';

const Set<String> kNightScalarOverrideSources = {'manual', 'confirmed'};

enum NightScalarGap {
  missing,
  skipped,
  version,
  unversioned,
  unreadable,
  withheld,

  /// Finite stored scalar whose quantity is unknown or not the selected unit.
  unit,
}

class StoredNightBaseline {
  const StoredNightBaseline({
    this.value,
    this.spread,
    this.status,
    this.nValid,
    this.nightsSinceUpdate,
    this.note,
  });

  final double? value;

  /// Robust spread of the baseline (analytics `BaselineState.spread`).
  final double? spread;
  final String? status;
  final int? nValid;
  final int? nightsSinceUpdate;
  final String? note;

  bool get isEmpty =>
      value == null &&
      spread == null &&
      status == null &&
      nValid == null &&
      nightsSinceUpdate == null &&
      note == null;

  @override
  bool operator ==(Object other) =>
      other is StoredNightBaseline &&
      other.value == value &&
      other.spread == spread &&
      other.status == status &&
      other.nValid == nValid &&
      other.nightsSinceUpdate == nightsSinceUpdate &&
      other.note == note;

  @override
  int get hashCode =>
      Object.hash(value, spread, status, nValid, nightsSinceUpdate, note);
}

/// Genuine `respiration.rsa` envelope. Spectral [peakHz]/[power]/[source] and
/// [brpm] come from present `value` (power is not an error bound). Missing
/// confidence stays null and is never defaulted to 0.5.
class NightScalarEnvelope {
  const NightScalarEnvelope({
    this.tier,
    this.confidence,
    this.inputsUsed,
    this.note,
    this.brpm,
    this.peakHz,
    this.power,
    this.source,
  });

  final String? tier;
  final double? confidence;
  final List<String>? inputsUsed;
  final String? note;
  final double? brpm;
  final double? peakHz;
  final double? power;
  final String? source;

  bool get isEmpty =>
      tier == null &&
      confidence == null &&
      (inputsUsed == null || inputsUsed!.isEmpty) &&
      note == null &&
      brpm == null &&
      peakHz == null &&
      power == null &&
      source == null;

  @override
  bool operator ==(Object other) =>
      other is NightScalarEnvelope &&
      other.tier == tier &&
      other.confidence == confidence &&
      _sameStringList(other.inputsUsed, inputsUsed) &&
      other.note == note &&
      other.brpm == brpm &&
      other.peakHz == peakHz &&
      other.power == power &&
      other.source == source;

  @override
  int get hashCode => Object.hash(
    tier,
    confidence,
    inputsUsed == null ? null : Object.hashAll(inputsUsed!),
    note,
    brpm,
    peakHz,
    power,
    source,
  );
}

class NightScalarJob {
  const NightScalarJob({
    required this.day,
    this.status,
    this.identityMatched = true,
    this.resultAlgo,
    this.resultComputedAt,
    this.action,
    this.onsetMs,
    this.wakeMs,
  });

  final String day;
  final String? status;
  final bool identityMatched;
  final int? resultAlgo;
  final int? resultComputedAt;
  final String? action;
  final int? onsetMs;
  final int? wakeMs;
}

class NightScalarHistoryNight {
  const NightScalarHistoryNight({
    required this.day,
    this.value,
    this.partial = false,
    this.source,
    this.resultSource,
    this.payloadSource,
    this.imported = false,
    this.gap,
    this.unit,
  });

  final String day;
  final double? value;
  final bool partial;
  /// Payload `source` for HRV/RHR/respiration. Null stays null.
  final String? source;
  /// Exact-row `day_result.source`. Null stays null — never backfilled.
  final String? resultSource;
  /// Payload `source`. Null stays null — never backfilled from [resultSource].
  final String? payloadSource;
  final bool imported;
  final NightScalarGap? gap;
  final NightScalarUnit? unit;

  @override
  bool operator ==(Object other) =>
      other is NightScalarHistoryNight &&
      other.day == day &&
      other.value == value &&
      other.partial == partial &&
      other.source == source &&
      other.resultSource == resultSource &&
      other.payloadSource == payloadSource &&
      other.imported == imported &&
      other.gap == gap &&
      other.unit == unit;

  @override
  int get hashCode => Object.hash(
    day,
    value,
    partial,
    source,
    resultSource,
    payloadSource,
    imported,
    gap,
    unit,
  );
}

class NightScalarCounts {
  const NightScalarCounts({
    this.compared = 0,
    this.excludedVersion = 0,
    this.excludedSkipped = 0,
    this.excludedUnversioned = 0,
    this.excludedUnit = 0,
    this.unreadable = 0,
    this.imported = 0,
    this.sources = const {},
  });

  final int compared;
  final int excludedVersion;
  final int excludedSkipped;
  final int excludedUnversioned;
  final int excludedUnit;
  final int unreadable;
  final int imported;
  final Map<String, int> sources;

  @override
  bool operator ==(Object other) =>
      other is NightScalarCounts &&
      other.compared == compared &&
      other.excludedVersion == excludedVersion &&
      other.excludedSkipped == excludedSkipped &&
      other.excludedUnversioned == excludedUnversioned &&
      other.excludedUnit == excludedUnit &&
      other.unreadable == unreadable &&
      other.imported == imported &&
      _sameCounts(other.sources, sources);

  @override
  int get hashCode {
    final keys = sources.keys.toList()..sort();
    return Object.hash(
      compared,
      excludedVersion,
      excludedSkipped,
      excludedUnversioned,
      excludedUnit,
      unreadable,
      imported,
      Object.hashAll([for (final k in keys) Object.hash(k, sources[k])]),
    );
  }
}

class NightScalarRow {
  const NightScalarRow({
    required this.day,
    this.algoVersion,
    this.skipped = false,
    this.partial = false,
    this.payloadUnreadable = false,
    this.value,
    this.computedAtMs,
    this.imported = false,
    this.source,
    this.rowSource,
    this.sleepSource,
    this.deviceFamily,
    this.baseline,
    this.windowStartMs,
    this.windowEndMs,
    this.envelope,
  });

  final String day;
  final int? algoVersion;
  final bool skipped;
  final bool partial;
  final bool payloadUnreadable;
  final double? value;
  final int? computedAtMs;
  final bool imported;
  final String? source;
  /// Exact-row `day_result.source`. Never inferred from payload or series.
  final String? rowSource;
  final String? sleepSource;
  final String? deviceFamily;
  final StoredNightBaseline? baseline;
  final int? windowStartMs;
  final int? windowEndMs;
  final NightScalarEnvelope? envelope;
}

class NightScalarDetail {
  const NightScalarDetail({
    required this.day,
    required this.key,
    required this.nights,
    required this.currentAlgo,
    required this.state,
    this.olderCalculation = false,
    this.partial = false,
    this.value,
    this.storedForInfo,
    this.baseline,
    this.window,
    this.computedAt,
    this.algoVersion,
    this.historyAnchor,
    this.sleepSource,
    this.vendorSource,
    this.resultSource,
    this.payloadSource,
    this.deviceFamily,
    this.recordingTimezone,
    this.unit,
    this.history = const [],
    this.counts = const NightScalarCounts(),
    this.envelope,
  });

  final String day;
  final NightScalarMetric key;
  final int nights;
  final int currentAlgo;
  final NightScalarState state;
  final bool olderCalculation;
  final bool partial;
  final double? value;
  final double? storedForInfo;
  final StoredNightBaseline? baseline;
  final ({DateTime start, DateTime end})? window;
  final DateTime? computedAt;
  final int? algoVersion;
  final int? historyAnchor;
  final String? sleepSource;
  final String? vendorSource;
  /// Exact-row `day_result.source`. Null stays null — never backfilled.
  final String? resultSource;
  /// Payload `source`. Null stays null — never backfilled from [resultSource].
  final String? payloadSource;
  final String? deviceFamily;
  final String? recordingTimezone;
  /// Skin-temperature quantity. Null on HRV / RHR / respiration.
  final NightScalarUnit? unit;
  final List<NightScalarHistoryNight> history;
  final NightScalarCounts counts;
  final NightScalarEnvelope? envelope;

  /// Known SD or Celsius. Unknown selected has no comparable chart.
  bool get hasComparableQuantity => unit?.isKnown == true;

  bool get withheld =>
      state == NightScalarState.pending ||
      state == NightScalarState.failed ||
      state == NightScalarState.unknown ||
      state == NightScalarState.outdated;

  String? get evaluationLabel => switch (state) {
    NightScalarState.pending => kNightScalarPendingLabel,
    NightScalarState.failed => kNightScalarFailedLabel,
    NightScalarState.unknown ||
    NightScalarState.outdated => kNightScalarOpenLabel,
    _ => null,
  };

  String get series => key.series;
  String get baselinePath => key.baselinePath;

  @override
  bool operator ==(Object other) =>
      other is NightScalarDetail &&
      other.day == day &&
      other.key == key &&
      other.nights == nights &&
      other.currentAlgo == currentAlgo &&
      other.state == state &&
      other.olderCalculation == olderCalculation &&
      other.partial == partial &&
      other.value == value &&
      other.storedForInfo == storedForInfo &&
      other.baseline == baseline &&
      other.window?.start == window?.start &&
      other.window?.end == window?.end &&
      other.computedAt == computedAt &&
      other.algoVersion == algoVersion &&
      other.historyAnchor == historyAnchor &&
      other.sleepSource == sleepSource &&
      other.vendorSource == vendorSource &&
      other.resultSource == resultSource &&
      other.payloadSource == payloadSource &&
      other.deviceFamily == deviceFamily &&
      other.recordingTimezone == recordingTimezone &&
      other.unit == unit &&
      _sameNights(other.history, history) &&
      other.counts == counts &&
      other.envelope == envelope;

  @override
  int get hashCode => Object.hash(
        Object.hash(
          day,
          key,
          nights,
          currentAlgo,
          state,
          olderCalculation,
          partial,
          value,
          storedForInfo,
          baseline,
        ),
        Object.hash(
          window?.start,
          window?.end,
          computedAt,
          algoVersion,
          historyAnchor,
          sleepSource,
          vendorSource,
          deviceFamily,
          recordingTimezone,
          Object.hashAll(history),
          counts,
          envelope,
        ),
        Object.hash(resultSource, payloadSource, unit),
      );
}

bool isNightScalarDay(String day) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) return false;
  final p = day.split('-').map(int.parse).toList();
  final d = DateTime(p[0], p[1], p[2]);
  return d.year == p[0] && d.month == p[1] && d.day == p[2];
}

void requireNightScalarDay(String day, [String name = 'day']) {
  if (!isNightScalarDay(day)) {
    throw ArgumentError.value(day, name, 'Expected a Gregorian YYYY-MM-DD.');
  }
}

void requireNightScalarNights(int nights) {
  if (!kNightScalarNights.contains(nights)) {
    throw ArgumentError.value(nights, 'nights', 'Expected 7, 30, or 90.');
  }
}

List<String> nightScalarDaysEnding(String endDay, int nights) {
  requireNightScalarDay(endDay, 'endDay');
  requireNightScalarNights(nights);
  final end = DateTime.parse(endDay);
  return [
    for (var i = nights - 1; i >= 0; i--)
      dayLabelOf(DateTime(end.year, end.month, end.day - i)),
  ];
}

double? nightScalarFinite(Object? raw) {
  if (raw is! num || !raw.isFinite) return null;
  return raw.toDouble();
}

/// Stored unit-interval confidence. Out-of-range and nonfinite stay null.
double? nightScalarUnitInterval(Object? raw) {
  final n = nightScalarFinite(raw);
  if (n == null || n < 0 || n > 1) return null;
  return n;
}

/// Keep only nonempty trimmed strings. Never [Object.toString] coerce.
List<String>? nightScalarStringList(Object? raw) {
  if (raw is! List) return null;
  final out = <String>[
    for (final item in raw)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
  return out.isEmpty ? null : List<String>.unmodifiable(out);
}

int? nightScalarInt(Object? raw) {
  final n = nightScalarFinite(raw);
  if (n == null || n != n.roundToDouble()) return null;
  return n.round();
}

int? nightScalarNonnegInt(Object? raw) {
  final n = nightScalarInt(raw);
  if (n == null || n < 0) return null;
  return n;
}

bool nightScalarJsonTrue(Object? raw) {
  if (raw == true) return true;
  if (raw is int && raw == 1) return true;
  return false;
}

String? nightScalarLabel(Object? raw) {
  if (raw is! String) return null;
  final value = raw.trim();
  return value.isEmpty ? null : value;
}

bool nightScalarKnownUnit(NightScalarUnit? unit) => unit?.isKnown == true;

/// Classify skin-temperature quantity from exact-row `day_result.source` plus
/// payload `source` / `imported`. Never reads `metric_series_version`. Source
/// strings are provenance for Info — UI unit comes only from this enum.
///
/// `band` supports SD unless a nonempty payload source conflicts.
/// `whoop_export` supports Celsius unless a nonempty payload source conflicts.
/// `cloud_v2` and any other nonempty row source are unknown.
/// A null column may use unambiguous payload `imported: true` +
/// `source: whoop_export` for legacy Celsius. Null column with `band` or
/// `imported` alone cannot infer SD or Celsius. Any two nonempty differing
/// sources are unknown. Invalid / non-string sources do not classify.
NightScalarUnit nightScalarSkinTemperatureUnit({
  Object? resultSource,
  Object? payloadSource,
  Object? imported,
}) {
  final row = nightScalarLabel(resultSource);
  final payload = nightScalarLabel(payloadSource);
  final isImported = nightScalarJsonTrue(imported);
  if (row != null && payload != null && row != payload) {
    return NightScalarUnit.unknown;
  }
  if (row == 'band') return NightScalarUnit.sd;
  if (row == 'whoop_export') return NightScalarUnit.celsius;
  if (row != null) return NightScalarUnit.unknown;
  if (isImported && payload == 'whoop_export') {
    return NightScalarUnit.celsius;
  }
  return NightScalarUnit.unknown;
}

String? nightScalarStatus(Object? raw) {
  final label = nightScalarLabel(raw);
  return label?.toLowerCase();
}

int? nightScalarMillis(Object? raw) {
  final n = nightScalarFinite(raw);
  if (n == null || n < kNightScalarMillisFloor) return null;
  if (n.abs() > 8640000000000000) return null;
  return n.round();
}

DateTime? nightScalarEpochMs(Object? raw) {
  final ms = nightScalarMillis(raw);
  if (ms == null) return null;
  return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
}

({DateTime start, DateTime end})? nightScalarWindow(
  Object? onsetRaw,
  Object? offsetRaw,
) {
  final start = nightScalarEpochMs(onsetRaw);
  final end = nightScalarEpochMs(offsetRaw);
  if (start == null || end == null || !end.isAfter(start)) return null;
  return (start: start, end: end);
}

StoredNightBaseline? nightScalarBaseline({
  Object? value,
  Object? spread,
  Object? status,
  Object? nValid,
  Object? nightsSinceUpdate,
  Object? note,
}) {
  final parsed = StoredNightBaseline(
    value: nightScalarFinite(value),
    spread: nightScalarFinite(spread),
    status: nightScalarStatus(status),
    nValid: nightScalarNonnegInt(nValid),
    nightsSinceUpdate: nightScalarNonnegInt(nightsSinceUpdate),
    note: nightScalarLabel(note),
  );
  return parsed.isEmpty ? null : parsed;
}

/// Copy stored `respiration.rsa` fields that are actually present. Spectral
/// provenance lives on present `value`. Never default confidence. Published
/// rate stays `scalars.resp_rate`, not [NightScalarEnvelope.brpm].
NightScalarEnvelope? nightScalarEnvelope(Object? rsa) {
  if (rsa is! Map) return null;
  double? confidence;
  if (rsa.containsKey('confidence')) {
    confidence = nightScalarUnitInterval(rsa['confidence']);
  }
  final value = rsa['value'];
  final spectral = value is Map ? value : const <Object?, Object?>{};
  final parsed = NightScalarEnvelope(
    tier: nightScalarLabel(rsa['tier']),
    confidence: confidence,
    inputsUsed: nightScalarStringList(rsa['inputs_used']),
    note: nightScalarLabel(rsa['note']),
    brpm: nightScalarFinite(spectral['brpm']),
    peakHz: nightScalarFinite(spectral['peak_hz']),
    power: nightScalarFinite(spectral['power']),
    source: nightScalarLabel(spectral['source']),
  );
  return parsed.isEmpty ? null : parsed;
}

NightScalarJob nightScalarSleepJobFromRow(Map<String, Object?> row) {
  final correctionId = row['correction_id']?.toString();
  final jobId = row['job_correction_id']?.toString();
  final corrRev = (row['revision'] as num?)?.toInt();
  final jobRev = (row['job_revision'] as num?)?.toInt();
  final identity =
      correctionId != null &&
      jobId != null &&
      correctionId == jobId &&
      corrRev != null &&
      jobRev != null &&
      corrRev == jobRev;
  return NightScalarJob(
    day: row['day_id'] as String,
    status: row['status']?.toString(),
    identityMatched: identity,
    resultAlgo: (row['result_algo_version'] as num?)?.toInt(),
    resultComputedAt: (row['result_computed_at'] as num?)?.toInt(),
    action: nightScalarLabel(row['action']),
    onsetMs: nightScalarMillis(row['onset_ms']),
    wakeMs: nightScalarMillis(row['wake_ms']),
  );
}

NightScalarJob nightScalarNapJobFromRow(Map<String, Object?> row) {
  return NightScalarJob(
    day: row['day_id'] as String,
    status: row['status']?.toString(),
    identityMatched: row['day_id'] is String,
    resultAlgo: (row['result_algo_version'] as num?)?.toInt(),
    resultComputedAt: (row['result_computed_at'] as num?)?.toInt(),
  );
}

/// Complete only with matching identity and a receipt that covers this stored
/// result (`storedComputedAt >= receipt`, same stored algo). Status `complete`
/// alone is unknown, not a queued pending job. An older stored algo stays
/// readable when the receipt names that algo.
NightScalarState? nightScalarReceiptState(
  NightScalarJob? job, {
  int? storedAlgo,
  int? storedComputedAt,
}) {
  if (job == null) return null;
  if (!job.identityMatched) return NightScalarState.unknown;
  if (job.status == 'failed') return NightScalarState.failed;
  if (job.status == 'pending' || job.status == 'calculating') {
    return NightScalarState.pending;
  }
  if (job.status != 'complete') return NightScalarState.unknown;
  final receiptAt = nightScalarEpochMs(job.resultComputedAt);
  if (job.resultAlgo == null || receiptAt == null) {
    return NightScalarState.unknown;
  }
  if (storedAlgo == null || storedComputedAt == null) {
    return NightScalarState.unknown;
  }
  final storedAt = nightScalarEpochMs(storedComputedAt);
  if (storedAt == null) return NightScalarState.unknown;
  if (job.resultAlgo != storedAlgo) return NightScalarState.unknown;
  if (storedAt.isBefore(receiptAt)) return NightScalarState.outdated;
  return null;
}

/// Override publication uses known actions and the stored window/source.
/// Only explicit `automatic` skips bounds. Null or unknown action is unproven.
bool? nightScalarOverrideProof({
  required NightScalarJob job,
  NightScalarRow? row,
}) {
  final action = job.action;
  if (action == 'automatic') return true;
  if (action != 'override') return null;
  if (row == null || row.payloadUnreadable) return null;
  final source = nightScalarLabel(row.sleepSource);
  if (source == null || !kNightScalarOverrideSources.contains(source)) {
    return null;
  }
  if (job.onsetMs == null || job.wakeMs == null) return null;
  final window = nightScalarWindow(row.windowStartMs, row.windowEndMs);
  if (window == null) return null;
  final requestedOnset = nightScalarMillis(job.onsetMs);
  final requestedWake = nightScalarMillis(job.wakeMs);
  if (requestedOnset == null || requestedWake == null) return null;
  final startMs = window.start.millisecondsSinceEpoch;
  final endMs = window.end.millisecondsSinceEpoch;
  return _publishedSleepSeconds(requestedOnset, truncate: true) ==
          _publishedSleepSeconds(startMs, truncate: false) &&
      _publishedSleepSeconds(requestedWake, truncate: true) ==
          _publishedSleepSeconds(endMs, truncate: false);
}

int _publishedSleepSeconds(int ms, {required bool truncate}) =>
    truncate ? ms ~/ 1000 : (ms / 1000).round();

NightScalarState? nightScalarJobsOverlay({
  NightScalarJob? sleep,
  NightScalarJob? nap,
  NightScalarRow? row,
  int? storedAlgo,
  int? storedComputedAt,
}) {
  var sleepState = nightScalarReceiptState(
    sleep,
    storedAlgo: storedAlgo,
    storedComputedAt: storedComputedAt,
  );
  if (sleepState == null &&
      sleep != null &&
      sleep.status == 'complete' &&
      sleep.identityMatched) {
    if (row?.imported == true ||
        nightScalarOverrideProof(job: sleep, row: row) != true) {
      sleepState = NightScalarState.unknown;
    }
  }
  var napState = nightScalarReceiptState(
    nap,
    storedAlgo: storedAlgo,
    storedComputedAt: storedComputedAt,
  );
  if (napState == null && nap != null && row?.imported == true) {
    napState = NightScalarState.unknown;
  }
  if (sleepState == NightScalarState.failed ||
      napState == NightScalarState.failed) {
    return NightScalarState.failed;
  }
  if (sleepState == NightScalarState.pending ||
      napState == NightScalarState.pending) {
    return NightScalarState.pending;
  }
  if (sleepState == NightScalarState.outdated ||
      napState == NightScalarState.outdated) {
    return NightScalarState.outdated;
  }
  if (sleepState == NightScalarState.unknown ||
      napState == NightScalarState.unknown) {
    return NightScalarState.unknown;
  }
  return null;
}

/// Same selected-night state as [buildNightScalarDetail], without history.
NightScalarState nightScalarPublishedState({
  NightScalarState? overlay,
  NightScalarRow? selected,
  required int currentAlgo,
  double? value,
}) {
  if (overlay != null) return overlay;
  if (selected?.payloadUnreadable == true) return NightScalarState.unreadable;
  final finite = nightScalarFinite(value);
  if (selected == null || selected.skipped || finite == null) {
    return NightScalarState.missing;
  }
  if (selected.partial) return NightScalarState.partial;
  if (selected.algoVersion != null && selected.algoVersion != currentAlgo) {
    return NightScalarState.older;
  }
  return NightScalarState.current;
}

double? nightScalarCardBaseline({
  required NightScalarState state,
  StoredNightBaseline? baseline,
}) {
  if (state != NightScalarState.current) return null;
  if (nightScalarStatus(baseline?.status) != kNightScalarTrustedBaseline) {
    return null;
  }
  return nightScalarFinite(baseline?.value);
}

/// dart:convert last-wins nested fields only. sqlite json_extract is first-wins.
/// Sleep series, clinical envelopes, and curves stay out of the projection.
/// [scalarKey] is payload `scalars.*` for metrics without a SQL column.
Map<String, Object?>? projectNightScalarPayload(
  Object? json,
  String baselineRoot, [
  String? scalarKey,
]) {
  if (json is! String || json.isEmpty) return null;
  try {
    final decoded = jsonDecode(json);
    if (decoded is! Map) return null;
    final sleep = decoded['sleep'];
    final window = sleep is Map ? sleep['window'] : null;
    final value = window is Map ? window['value'] : null;
    final baselines = decoded['baselines'];
    final block = baselines is Map ? baselines[baselineRoot] : null;
    final scalars = decoded['scalars'];
    final respiration = decoded['respiration'];
    final rsa = respiration is Map ? respiration['rsa'] : null;
    final envelope = <String, Object?>{};
    if (rsa is Map) {
      rsa.forEach((k, v) {
        if (k is String) envelope[k] = v;
      });
    }
    return {
      'imported': decoded['imported'],
      'source': decoded['source'],
      'sleep_source': decoded['sleep_source'],
      'device_family': decoded['device_family'],
      'onset_ms': value is Map ? value['onset_ms'] : null,
      'offset_ms': value is Map ? value['offset_ms'] : null,
      'baseline_value': block is Map ? block['baseline'] : null,
      'baseline_spread': block is Map ? block['spread'] : null,
      'baseline_status': block is Map ? block['status'] : null,
      'baseline_n_valid': block is Map ? block['n_valid'] : null,
      'baseline_nights_since_update':
          block is Map ? block['nights_since_update'] : null,
      'baseline_note': block is Map ? block['note'] : null,
      if (scalarKey != null)
        'scalar': scalars is Map ? scalars[scalarKey] : null,
      if (envelope.isNotEmpty) 'envelope': envelope,
    };
  } catch (_) {
    return null;
  }
}

List<Map<String, Object?>?> projectNightScalarPayloads(
  List<Object?> raws,
  String baselineRoot, [
  String? scalarKey,
]) {
  return [
    for (final raw in raws)
      projectNightScalarPayload(raw, baselineRoot, scalarKey),
  ];
}

NightScalarDetail buildNightScalarDetail({
  required String day,
  required NightScalarMetric key,
  required int nights,
  required int currentAlgo,
  required List<String> days,
  NightScalarRow? selected,
  Map<String, NightScalarRow> matching = const {},
  Set<String> otherVersionDays = const {},
  Set<String> seriesOnlyDays = const {},
  Map<String, NightScalarJob> sleepJobs = const {},
  Map<String, NightScalarJob> napJobs = const {},
  String? recordingTimezone,
}) {
  requireNightScalarDay(day);
  requireNightScalarNights(nights);
  if (days.length != nights || days.last != day) {
    throw ArgumentError.value(
      days,
      'days',
      'Expected $nights local calendar days ending on $day.',
    );
  }

  final selectedAlgo = selected?.algoVersion;
  final payloadUnreadable = selected?.payloadUnreadable == true;
  final historyAnchor = selectedAlgo ?? currentAlgo;
  final olderCalculation =
      !payloadUnreadable && selectedAlgo != null && selectedAlgo != currentAlgo;
  final selectedPartial = selected?.partial == true && !payloadUnreadable;
  final selectedFinite =
      payloadUnreadable ? null : nightScalarFinite(selected?.value);
  final skipped = selected?.skipped == true;
  final overlay = nightScalarJobsOverlay(
    sleep: sleepJobs[day],
    nap: napJobs[day],
    row: selected,
    storedAlgo: selectedAlgo,
    storedComputedAt: selected?.computedAtMs,
  );
  final selectedUnit = key == NightScalarMetric.skinTemperature &&
          selected != null
      ? nightScalarSkinTemperatureUnit(
          resultSource: selected.rowSource,
          payloadSource: payloadUnreadable ? null : selected.source,
          imported: payloadUnreadable ? false : selected.imported,
        )
      : null;

  NightScalarState state;
  double? hero;
  double? storedForInfo;
  if (overlay != null) {
    state = overlay;
    storedForInfo = selectedFinite;
  } else if (payloadUnreadable) {
    state = NightScalarState.unreadable;
  } else if (selected == null || skipped || selectedFinite == null) {
    state = NightScalarState.missing;
  } else if (selectedPartial) {
    state = NightScalarState.partial;
    hero = selectedFinite;
  } else if (olderCalculation) {
    state = NightScalarState.older;
    hero = selectedFinite;
  } else {
    state = NightScalarState.current;
    hero = selectedFinite;
  }
  if (overlay == null &&
      hero != null &&
      key == NightScalarMetric.skinTemperature &&
      !nightScalarKnownUnit(selectedUnit)) {
    storedForInfo = hero;
    hero = null;
  }

  final window = payloadUnreadable
      ? null
      : nightScalarWindow(selected?.windowStartMs, selected?.windowEndMs);
  final baseline = payloadUnreadable || key == NightScalarMetric.skinTemperature
      ? null
      : selected?.baseline;
  final sleepSource =
      payloadUnreadable ? null : nightScalarLabel(selected?.sleepSource);
  final deviceFamily =
      payloadUnreadable ? null : nightScalarLabel(selected?.deviceFamily);
  final vendorSource = !payloadUnreadable && selected?.imported == true
      ? nightScalarLabel(selected?.source)
      : null;
  final computedAt = nightScalarEpochMs(selected?.computedAtMs);

  var compared = 0;
  var excludedVersion = 0;
  var excludedSkipped = 0;
  var excludedUnversioned = 0;
  var excludedUnit = 0;
  var unreadable = 0;
  var imported = 0;
  final sources = <String, int>{};
  final history = <NightScalarHistoryNight>[];

  for (final id in days) {
    final row = matching[id];
    final nightOverlay = nightScalarJobsOverlay(
      sleep: sleepJobs[id],
      nap: napJobs[id],
      row: row,
      storedAlgo: row?.algoVersion ?? historyAnchor,
      storedComputedAt: row?.computedAtMs,
    );
    if (row != null) {
      if (row.payloadUnreadable) {
        unreadable++;
        history.add(
          NightScalarHistoryNight(day: id, gap: NightScalarGap.unreadable),
        );
        continue;
      }
      if (nightOverlay != null) {
        history.add(
          NightScalarHistoryNight(day: id, gap: NightScalarGap.withheld),
        );
        continue;
      }
      if (row.skipped) {
        excludedSkipped++;
        history.add(
          NightScalarHistoryNight(
            day: id,
            partial: row.partial,
            gap: NightScalarGap.skipped,
          ),
        );
        continue;
      }
      final value = nightScalarFinite(row.value);
      if (value == null) {
        history.add(
          NightScalarHistoryNight(
            day: id,
            partial: row.partial,
            gap: NightScalarGap.missing,
          ),
        );
        continue;
      }
      final payloadSource = nightScalarLabel(row.source);
      final resultSource = nightScalarLabel(row.rowSource);
      final nightUnit = key == NightScalarMetric.skinTemperature
          ? nightScalarSkinTemperatureUnit(
              resultSource: row.rowSource,
              payloadSource: row.source,
              imported: row.imported,
            )
          : null;
      if (key == NightScalarMetric.skinTemperature &&
          !(nightScalarKnownUnit(selectedUnit) && nightUnit == selectedUnit)) {
        excludedUnit++;
        history.add(
          NightScalarHistoryNight(
            day: id,
            partial: row.partial,
            source: payloadSource,
            resultSource: resultSource,
            payloadSource: payloadSource,
            imported: row.imported,
            gap: NightScalarGap.unit,
            unit: nightUnit,
          ),
        );
        continue;
      }
      compared++;
      if (row.imported) imported++;
      _countNightScalarSource(
        sources,
        key: key,
        resultSource: resultSource,
        payloadSource: payloadSource,
      );
      history.add(
        NightScalarHistoryNight(
          day: id,
          value: value,
          partial: row.partial,
          source: payloadSource,
          resultSource: resultSource,
          payloadSource: payloadSource,
          imported: row.imported,
          unit: nightUnit,
        ),
      );
      continue;
    }
    if (otherVersionDays.contains(id)) {
      excludedVersion++;
      history.add(
        NightScalarHistoryNight(day: id, gap: NightScalarGap.version),
      );
      continue;
    }
    if (seriesOnlyDays.contains(id)) {
      excludedUnversioned++;
      history.add(
        NightScalarHistoryNight(day: id, gap: NightScalarGap.unversioned),
      );
      continue;
    }
    history.add(
      NightScalarHistoryNight(day: id, gap: NightScalarGap.missing),
    );
  }

  return NightScalarDetail(
    day: day,
    key: key,
    nights: nights,
    currentAlgo: currentAlgo,
    state: state,
    olderCalculation: olderCalculation,
    partial: selectedPartial && !skipped,
    value: hero,
    storedForInfo: storedForInfo,
    baseline: baseline,
    window: window,
    computedAt: computedAt,
    algoVersion: selectedAlgo,
    historyAnchor: historyAnchor,
    sleepSource: sleepSource,
    vendorSource: vendorSource,
    resultSource: nightScalarLabel(selected?.rowSource),
    payloadSource: payloadUnreadable ? null : nightScalarLabel(selected?.source),
    deviceFamily: deviceFamily,
    recordingTimezone: nightScalarLabel(recordingTimezone),
    unit: selectedUnit,
    envelope: payloadUnreadable || key != NightScalarMetric.respiration
        ? null
        : selected?.envelope,
    history: List.unmodifiable(history),
    counts: NightScalarCounts(
      compared: compared,
      excludedVersion: excludedVersion,
      excludedSkipped: excludedSkipped,
      excludedUnversioned: excludedUnversioned,
      excludedUnit: excludedUnit,
      unreadable: unreadable,
      imported: imported,
      sources: Map.unmodifiable(sources),
    ),
  );
}

bool _sameStringList(List<String>? a, List<String>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameNights(
  List<NightScalarHistoryNight> a,
  List<NightScalarHistoryNight> b,
) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameCounts(Map<String, int> a, Map<String, int> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}

/// Compared-night provenance. Skin temperature counts one channel when the
/// other is empty, never merges two nonempty differing sources into one key.
void _countNightScalarSource(
  Map<String, int> sources, {
  required NightScalarMetric key,
  required String? resultSource,
  required String? payloadSource,
}) {
  if (key == NightScalarMetric.skinTemperature) {
    if (resultSource != null &&
        payloadSource != null &&
        resultSource != payloadSource) {
      return;
    }
    final label = payloadSource ?? resultSource;
    if (label != null) sources[label] = (sources[label] ?? 0) + 1;
    return;
  }
  if (payloadSource != null) {
    sources[payloadSource] = (sources[payloadSource] ?? 0) + 1;
  }
}
