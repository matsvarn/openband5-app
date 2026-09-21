// Typed HRV / resting-pulse night scalars. Repositories decode storage here.
// Published `scalars.rmssd` / `scalars.rhr` only — not session envelopes.
// Civil-date windows; no interpolation, refold, or invented provenance.

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
const String kNightScalarPaperDay = '2026-09-15';

enum NightScalarMetric { hrv, rhr }

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
const String kNightScalarTrustedBaseline = 'trusted';

const Set<String> kNightScalarOverrideSources = {'manual', 'confirmed'};

enum NightScalarGap {
  missing,
  skipped,
  version,
  unversioned,
  unreadable,
  withheld,
}

class StoredNightBaseline {
  const StoredNightBaseline({
    this.value,
    this.status,
    this.nValid,
    this.nightsSinceUpdate,
    this.note,
  });

  final double? value;
  final String? status;
  final int? nValid;
  final int? nightsSinceUpdate;
  final String? note;

  bool get isEmpty =>
      value == null &&
      status == null &&
      nValid == null &&
      nightsSinceUpdate == null &&
      note == null;

  @override
  bool operator ==(Object other) =>
      other is StoredNightBaseline &&
      other.value == value &&
      other.status == status &&
      other.nValid == nValid &&
      other.nightsSinceUpdate == nightsSinceUpdate &&
      other.note == note;

  @override
  int get hashCode =>
      Object.hash(value, status, nValid, nightsSinceUpdate, note);
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
    this.imported = false,
    this.gap,
  });

  final String day;
  final double? value;
  final bool partial;
  final String? source;
  final bool imported;
  final NightScalarGap? gap;

  @override
  bool operator ==(Object other) =>
      other is NightScalarHistoryNight &&
      other.day == day &&
      other.value == value &&
      other.partial == partial &&
      other.source == source &&
      other.imported == imported &&
      other.gap == gap;

  @override
  int get hashCode =>
      Object.hash(day, value, partial, source, imported, gap);
}

class NightScalarCounts {
  const NightScalarCounts({
    this.compared = 0,
    this.excludedVersion = 0,
    this.excludedSkipped = 0,
    this.excludedUnversioned = 0,
    this.unreadable = 0,
    this.imported = 0,
    this.sources = const {},
  });

  final int compared;
  final int excludedVersion;
  final int excludedSkipped;
  final int excludedUnversioned;
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
    this.sleepSource,
    this.deviceFamily,
    this.baseline,
    this.windowStartMs,
    this.windowEndMs,
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
  final String? sleepSource;
  final String? deviceFamily;
  final StoredNightBaseline? baseline;
  final int? windowStartMs;
  final int? windowEndMs;
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
    this.deviceFamily,
    this.recordingTimezone,
    this.history = const [],
    this.counts = const NightScalarCounts(),
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
  final String? deviceFamily;
  final String? recordingTimezone;
  final List<NightScalarHistoryNight> history;
  final NightScalarCounts counts;

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

  String get series =>
      key == NightScalarMetric.hrv ? 'rmssd' : 'rhr';

  String get baselinePath =>
      key == NightScalarMetric.hrv ? 'hrv' : 'resting_hr';

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
      other.deviceFamily == deviceFamily &&
      other.recordingTimezone == recordingTimezone &&
      _sameNights(other.history, history) &&
      other.counts == counts;

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
        ),
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
  Object? status,
  Object? nValid,
  Object? nightsSinceUpdate,
  Object? note,
}) {
  final parsed = StoredNightBaseline(
    value: nightScalarFinite(value),
    status: nightScalarStatus(status),
    nValid: nightScalarNonnegInt(nValid),
    nightsSinceUpdate: nightScalarNonnegInt(nightsSinceUpdate),
    note: nightScalarLabel(note),
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
Map<String, Object?>? projectNightScalarPayload(
  Object? json,
  String baselineRoot,
) {
  if (json is! String || json.isEmpty) return null;
  try {
    final decoded = jsonDecode(json);
    if (decoded is! Map) return null;
    final sleep = decoded['sleep'];
    final window = sleep is Map ? sleep['window'] : null;
    final value = window is Map ? window['value'] : null;
    final baselines = decoded['baselines'];
    final block = baselines is Map ? baselines[baselineRoot] : null;
    return {
      'imported': decoded['imported'],
      'source': decoded['source'],
      'sleep_source': decoded['sleep_source'],
      'device_family': decoded['device_family'],
      'onset_ms': value is Map ? value['onset_ms'] : null,
      'offset_ms': value is Map ? value['offset_ms'] : null,
      'baseline_value': block is Map ? block['baseline'] : null,
      'baseline_status': block is Map ? block['status'] : null,
      'baseline_n_valid': block is Map ? block['n_valid'] : null,
      'baseline_nights_since_update':
          block is Map ? block['nights_since_update'] : null,
      'baseline_note': block is Map ? block['note'] : null,
    };
  } catch (_) {
    return null;
  }
}

List<Map<String, Object?>?> projectNightScalarPayloads(
  List<Object?> raws,
  String baselineRoot,
) {
  return [for (final raw in raws) projectNightScalarPayload(raw, baselineRoot)];
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

  final window = payloadUnreadable
      ? null
      : nightScalarWindow(selected?.windowStartMs, selected?.windowEndMs);
  final baseline = payloadUnreadable ? null : selected?.baseline;
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
      final source = nightScalarLabel(row.source);
      compared++;
      if (row.imported) imported++;
      if (source != null) {
        sources[source] = (sources[source] ?? 0) + 1;
      }
      history.add(
        NightScalarHistoryNight(
          day: id,
          value: value,
          partial: row.partial,
          source: source,
          imported: row.imported,
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
    deviceFamily: deviceFamily,
    recordingTimezone: nightScalarLabel(recordingTimezone),
    history: List.unmodifiable(history),
    counts: NightScalarCounts(
      compared: compared,
      excludedVersion: excludedVersion,
      excludedSkipped: excludedSkipped,
      excludedUnversioned: excludedUnversioned,
      unreadable: unreadable,
      imported: imported,
      sources: Map.unmodifiable(sources),
    ),
  );
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
