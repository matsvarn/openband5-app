import '../data/day_label.dart';

/// Pinned `sleepNeed` clamp. Out-of-range stored numbers are corrupt, not clamped.
const double kSleepPlanNeedMinSec = 6 * 3600;
const double kSleepPlanNeedMaxSec = 11 * 3600;

/// Exclusive upper bound for a stored minute-of-day.
const double kSleepPlanMinuteOfDay = 1440;

const String kSleepPlanAbsentValue = '—';

/// Producer `recentDayResults` selection size (`DerivationEngine._crossDayWindow`).
const int kSleepPlanProducerFetchLimit = 90;

/// Below ~1973 in ms, so also any Unix-seconds timestamp. Not converted.
const int kSleepPlanMillisFloor = 100000000000;

enum SleepPlanStatus {
  available,
  partial,
  missing,
  unavailable,
  stale,
  inconsistent,
  corrupt,
}

enum SleepPlanIssue {
  historicalRequest,
  missingArtifact,
  missingNeed,
  wrongVersion,
  wrongDay,
  futureBuiltAt,
  inconsistentBuiltAt,
  unreadableJson,
  invalidNeed,
  invalidClock,
  invalidContribution,
  invalidConfidence,
  invalidEnvelope,
  staleInputs,
  unknownFreshness,
  invalidInputStamp,
  inconsistentInputStamp,
}

enum SleepPlanFreshness { fresh, staleInputs, unknown }

enum SleepPlanJobKind { sleepCorrection, napRecalc }

class SleepPlanInputJob {
  final String day;
  final SleepPlanJobKind kind;
  final String status;
  final int? resultComputedAtMs;
  const SleepPlanInputJob({
    required this.day,
    required this.kind,
    required this.status,
    this.resultComputedAtMs,
  });
}

class SleepPlanDayObservation {
  final String day;
  final int? computedAtMs;
  final bool skipped;
  final bool inFetchWindow;
  const SleepPlanDayObservation({
    required this.day,
    this.computedAtMs,
    this.skipped = false,
    this.inFetchWindow = false,
  });
}

class SleepPlanMetric {
  final bool present;
  final double? value;
  final String? note;
  final List<String> inputsUsed;
  final String? tier;
  final double? confidence;
  const SleepPlanMetric({
    this.present = false,
    this.value,
    this.note,
    this.inputsUsed = const [],
    this.tier,
    this.confidence,
  });

  static const absent = SleepPlanMetric();
}

class SleepPlanLimitations {
  final bool sourceTimezoneUnknown;
  final bool confidenceNotCalibrated;
  final bool notCycleAligned;
  const SleepPlanLimitations({
    this.sourceTimezoneUnknown = true,
    this.confidenceNotCalibrated = true,
    this.notCycleAligned = true,
  });
}

class SleepPlanDebt {
  final double? osdHours;
  final String? note;
  const SleepPlanDebt({this.osdHours, this.note});
}

class ComingNightSleepPlan {
  final String nightStartDay;
  final String wakeDay;
  final double needSeconds;
  final double? bedtimeMinuteOfDay;
  final double? wakeMinuteOfDay;
  final double? napCreditMin;
  final double? strainBonusMin;
  final int builtAtEpoch;
  final int algoVersion;
  final SleepPlanMetric need;
  final SleepPlanMetric bedtime;
  final SleepPlanMetric wake;
  final SleepPlanDebt? sleepDebt;
  final SleepPlanLimitations limitations;
  final SleepPlanFreshness freshness;
  final String? freshnessNote;
  final int? inputReadStartedAtMs;
  const ComingNightSleepPlan({
    required this.nightStartDay,
    required this.wakeDay,
    required this.needSeconds,
    this.bedtimeMinuteOfDay,
    this.wakeMinuteOfDay,
    this.napCreditMin,
    this.strainBonusMin,
    required this.builtAtEpoch,
    required this.algoVersion,
    required this.need,
    this.bedtime = SleepPlanMetric.absent,
    this.wake = SleepPlanMetric.absent,
    this.sleepDebt,
    this.limitations = const SleepPlanLimitations(),
    required this.freshness,
    this.freshnessNote,
    this.inputReadStartedAtMs,
  });
}

class SleepPlanSnapshot {
  final String requestedDay;
  final String today;
  final SleepPlanStatus status;
  final SleepPlanIssue? issue;
  final ComingNightSleepPlan? plan;
  final SleepPlanMetric? need;
  final SleepPlanMetric? bedtime;
  final SleepPlanMetric? wake;
  const SleepPlanSnapshot({
    required this.requestedDay,
    required this.today,
    required this.status,
    this.issue,
    this.plan,
    this.need,
    this.bedtime,
    this.wake,
  });

  static SleepPlanSnapshot unavailable(String requestedDay, String today) =>
      SleepPlanSnapshot(
        requestedDay: requestedDay,
        today: today,
        status: SleepPlanStatus.unavailable,
        issue: SleepPlanIssue.historicalRequest,
      );
}

class _MetricParse {
  final SleepPlanMetric metric;
  final SleepPlanIssue? issue;
  const _MetricParse(this.metric, [this.issue]);
}

class _NumberParse {
  final double? value;
  final SleepPlanIssue? issue;
  const _NumberParse(this.value, [this.issue]);
}

/// Stored `recent[].date` values, or null when the list cannot be used.
///
/// `recent` is every input row, not a calendar span. A malformed or incomplete
/// list is unknown — never a subset and never `n_days` consecutive days.
List<String>? sleepPlanContributingDays(
  Map<String, dynamic>? artifact, {
  required String planDay,
}) {
  if (artifact == null) return null;
  final recent = artifact['recent'];
  if (recent is! List || recent.isEmpty) return null;
  final days = <String>[];
  final seen = <String>{};
  for (final row in recent) {
    if (row is! Map) return null;
    final date = row['date'];
    if (date is! String || _localDate(date) == null) return null;
    if (date.compareTo(planDay) > 0) return null;
    if (!seen.add(date)) return null;
    days.add(date);
  }
  final n = artifact['n_days'];
  if (n != null) {
    if (n is! num ||
        !n.isFinite ||
        n <= 0 ||
        n != n.roundToDouble() ||
        n.toInt() != days.length) {
      return null;
    }
  }
  days.sort();
  return days;
}

String sleepPlanWakeDay(String nightStartDay) {
  final start = _localDate(nightStartDay);
  if (start == null) {
    throw ArgumentError.value(nightStartDay, 'nightStartDay');
  }
  return dayLabelOf(DateTime(start.year, start.month, start.day + 1));
}

int? sleepPlanMillis(Object? raw) {
  if (raw is! num || !raw.isFinite || raw <= 0) return null;
  if (raw != raw.roundToDouble()) return null;
  final n = raw.toInt();
  if (n < kSleepPlanMillisFloor) return null;
  return n;
}

SleepPlanSnapshot sleepPlanFromStoredCrossday({
  required String requestedDay,
  required DateTime now,
  required int algoVersion,
  Map<String, dynamic>? artifact,
  bool unreadable = false,
  List<SleepPlanInputJob> jobs = const [],
  List<String>? contributingDays,
  List<SleepPlanDayObservation> observations = const [],
}) {
  final today = todayLabel(now);
  if (requestedDay != today) {
    return SleepPlanSnapshot.unavailable(requestedDay, today);
  }
  if (unreadable) {
    return SleepPlanSnapshot(
      requestedDay: requestedDay,
      today: today,
      status: SleepPlanStatus.corrupt,
      issue: SleepPlanIssue.unreadableJson,
    );
  }
  if (artifact == null) {
    return SleepPlanSnapshot(
      requestedDay: requestedDay,
      today: today,
      status: SleepPlanStatus.missing,
      issue: SleepPlanIssue.missingArtifact,
    );
  }

  final version = _positiveWhole(artifact['algo_version']);
  if (version == null || version != algoVersion) {
    return SleepPlanSnapshot(
      requestedDay: requestedDay,
      today: today,
      status: SleepPlanStatus.stale,
      issue: SleepPlanIssue.wrongVersion,
    );
  }
  final builtFor = artifact['built_for_day'];
  if (builtFor is! String ||
      builtFor.isEmpty ||
      _localDate(builtFor) == null ||
      builtFor != requestedDay) {
    return SleepPlanSnapshot(
      requestedDay: requestedDay,
      today: today,
      status: SleepPlanStatus.stale,
      issue: SleepPlanIssue.wrongDay,
    );
  }
  final builtAt = _positiveWhole(artifact['built_at_epoch']);
  if (builtAt == null) {
    return SleepPlanSnapshot(
      requestedDay: requestedDay,
      today: today,
      status: SleepPlanStatus.inconsistent,
      issue: SleepPlanIssue.inconsistentBuiltAt,
    );
  }
  final nowSec = now.millisecondsSinceEpoch ~/ 1000;
  if (builtAt > nowSec) {
    return SleepPlanSnapshot(
      requestedDay: requestedDay,
      today: today,
      status: SleepPlanStatus.inconsistent,
      issue: SleepPlanIssue.futureBuiltAt,
    );
  }
  final builtAtLocal = DateTime.fromMillisecondsSinceEpoch(builtAt * 1000);
  if (dayLabelOf(builtAtLocal) != builtFor) {
    return SleepPlanSnapshot(
      requestedDay: requestedDay,
      today: today,
      status: SleepPlanStatus.inconsistent,
      issue: SleepPlanIssue.inconsistentBuiltAt,
    );
  }

  final stampParse = _inputReadStamp(
    artifact['input_read_started_at_ms'],
    builtAtEpoch: builtAt,
    builtForDay: builtFor,
    nowMs: now.millisecondsSinceEpoch,
  );
  if (stampParse.issue != null) {
    return SleepPlanSnapshot(
      requestedDay: requestedDay,
      today: today,
      status: stampParse.status,
      issue: stampParse.issue,
    );
  }
  final inputReadStartedAtMs = stampParse.ms;

  final coach = artifact['sleep_coach'];
  if (coach == null) {
    return SleepPlanSnapshot(
      requestedDay: requestedDay,
      today: today,
      status: SleepPlanStatus.missing,
      issue: SleepPlanIssue.missingNeed,
    );
  }
  if (coach is! Map) {
    return SleepPlanSnapshot(
      requestedDay: requestedDay,
      today: today,
      status: SleepPlanStatus.corrupt,
      issue: SleepPlanIssue.invalidEnvelope,
    );
  }
  final coachMap = _asStringMap(coach);
  if (coachMap == null) {
    return SleepPlanSnapshot(
      requestedDay: requestedDay,
      today: today,
      status: SleepPlanStatus.corrupt,
      issue: SleepPlanIssue.invalidEnvelope,
    );
  }

  final needParse = _objectMetric(
    coachMap['need'],
    field: 'need_sec',
    min: kSleepPlanNeedMinSec,
    max: kSleepPlanNeedMaxSec,
    invalidValue: SleepPlanIssue.invalidNeed,
  );
  if (needParse.issue != null) {
    return SleepPlanSnapshot(
      requestedDay: requestedDay,
      today: today,
      status: SleepPlanStatus.corrupt,
      issue: needParse.issue,
      need: needParse.metric,
    );
  }
  if (!needParse.metric.present || needParse.metric.value == null) {
    return SleepPlanSnapshot(
      requestedDay: requestedDay,
      today: today,
      status: SleepPlanStatus.missing,
      issue: SleepPlanIssue.missingNeed,
      need: needParse.metric,
    );
  }

  final bedtimeParse = _objectMetric(
    coachMap['bedtime'],
    field: 'bedtime_min_of_day',
    min: 0,
    maxExclusive: kSleepPlanMinuteOfDay,
    invalidValue: SleepPlanIssue.invalidClock,
  );
  if (bedtimeParse.issue != null) {
    return SleepPlanSnapshot(
      requestedDay: requestedDay,
      today: today,
      status: SleepPlanStatus.corrupt,
      issue: bedtimeParse.issue,
      need: needParse.metric,
      bedtime: bedtimeParse.metric,
    );
  }
  final wakeParse = _objectMetric(
    coachMap['wake'],
    field: 'wake_min_of_day',
    min: 0,
    maxExclusive: kSleepPlanMinuteOfDay,
    invalidValue: SleepPlanIssue.invalidClock,
  );
  if (wakeParse.issue != null) {
    return SleepPlanSnapshot(
      requestedDay: requestedDay,
      today: today,
      status: SleepPlanStatus.corrupt,
      issue: wakeParse.issue,
      need: needParse.metric,
      bedtime: bedtimeParse.metric,
      wake: wakeParse.metric,
    );
  }

  final nap = _plainMinutes(coachMap['nap_credit_min']);
  if (nap.issue != null) {
    return SleepPlanSnapshot(
      requestedDay: requestedDay,
      today: today,
      status: SleepPlanStatus.corrupt,
      issue: nap.issue,
      need: needParse.metric,
    );
  }
  final strain = _plainMinutes(coachMap['strain_bonus_min']);
  if (strain.issue != null) {
    return SleepPlanSnapshot(
      requestedDay: requestedDay,
      today: today,
      status: SleepPlanStatus.corrupt,
      issue: strain.issue,
      need: needParse.metric,
    );
  }

  final window =
      contributingDays ??
      sleepPlanContributingDays(artifact, planDay: requestedDay);
  final freshness = _freshness(
    jobs: jobs,
    window: window,
    observations: observations,
    inputReadStartedAtMs: inputReadStartedAtMs,
    planDay: requestedDay,
  );
  final clocksPresent =
      bedtimeParse.metric.present && wakeParse.metric.present;
  final contributionsPresent = nap.value != null && strain.value != null;
  final status = _interpretedStatus(
    clocksPresent: clocksPresent,
    contributionsPresent: contributionsPresent,
    freshness: freshness.kind,
  );

  return SleepPlanSnapshot(
    requestedDay: requestedDay,
    today: today,
    status: status,
    issue: status == SleepPlanStatus.stale
        ? SleepPlanIssue.staleInputs
        : freshness.kind == SleepPlanFreshness.unknown
        ? SleepPlanIssue.unknownFreshness
        : null,
    need: needParse.metric,
    bedtime: bedtimeParse.metric,
    wake: wakeParse.metric,
    plan: ComingNightSleepPlan(
      nightStartDay: requestedDay,
      wakeDay: sleepPlanWakeDay(requestedDay),
      needSeconds: needParse.metric.value!,
      bedtimeMinuteOfDay: bedtimeParse.metric.value,
      wakeMinuteOfDay: wakeParse.metric.value,
      napCreditMin: nap.value,
      strainBonusMin: strain.value,
      builtAtEpoch: builtAt,
      algoVersion: version,
      need: needParse.metric,
      bedtime: bedtimeParse.metric,
      wake: wakeParse.metric,
      sleepDebt: _debt(artifact['sleep_debt']),
      freshness: freshness.kind,
      freshnessNote: freshness.note,
      inputReadStartedAtMs: inputReadStartedAtMs,
    ),
  );
}

SleepPlanStatus _interpretedStatus({
  required bool clocksPresent,
  required bool contributionsPresent,
  required SleepPlanFreshness freshness,
}) {
  if (freshness == SleepPlanFreshness.staleInputs) {
    return SleepPlanStatus.stale;
  }
  if (freshness == SleepPlanFreshness.unknown ||
      !clocksPresent ||
      !contributionsPresent) {
    return SleepPlanStatus.partial;
  }
  return SleepPlanStatus.available;
}

({int? ms, SleepPlanIssue? issue, SleepPlanStatus status}) _inputReadStamp(
  Object? raw, {
  required int builtAtEpoch,
  required String builtForDay,
  required int nowMs,
}) {
  if (raw == null) {
    return (ms: null, issue: null, status: SleepPlanStatus.inconsistent);
  }
  if (raw is! num || !raw.isFinite) {
    return (
      ms: null,
      issue: SleepPlanIssue.invalidInputStamp,
      status: SleepPlanStatus.corrupt,
    );
  }
  if (raw != raw.roundToDouble()) {
    return (
      ms: null,
      issue: SleepPlanIssue.invalidInputStamp,
      status: SleepPlanStatus.corrupt,
    );
  }
  final ms = raw.toInt();
  if (ms <= 0 ||
      ms < kSleepPlanMillisFloor ||
      ms > nowMs ||
      ms > builtAtEpoch * 1000 + 999) {
    return (
      ms: null,
      issue: SleepPlanIssue.inconsistentInputStamp,
      status: SleepPlanStatus.inconsistent,
    );
  }
  if (dayLabelOf(DateTime.fromMillisecondsSinceEpoch(ms)) != builtForDay) {
    return (
      ms: null,
      issue: SleepPlanIssue.inconsistentInputStamp,
      status: SleepPlanStatus.inconsistent,
    );
  }
  return (ms: ms, issue: null, status: SleepPlanStatus.inconsistent);
}

({SleepPlanFreshness kind, String? note}) _freshness({
  required List<SleepPlanInputJob> jobs,
  required List<String>? window,
  required List<SleepPlanDayObservation> observations,
  required int? inputReadStartedAtMs,
  required String planDay,
}) {
  final contributing = window?.toSet();
  final fetchDays = {
    for (final row in observations)
      if (row.inFetchWindow) row.day,
  };
  var unknownTime = false;
  for (final job in jobs) {
    if (!_jobRelevant(
      job,
      planDay: planDay,
      contributing: contributing,
      fetchDays: fetchDays,
    )) {
      continue;
    }
    if (job.status != 'complete') {
      return (
        kind: SleepPlanFreshness.staleInputs,
        note: 'unresolved ${job.kind.name} on ${job.day}',
      );
    }
    final at = sleepPlanMillis(job.resultComputedAtMs);
    if (at == null) {
      unknownTime = true;
      continue;
    }
    if (inputReadStartedAtMs != null && at >= inputReadStartedAtMs) {
      return (
        kind: SleepPlanFreshness.staleInputs,
        note: 'newer ${job.kind.name} on ${job.day}',
      );
    }
  }
  if (window == null) {
    return (
      kind: SleepPlanFreshness.unknown,
      note: 'forecast history window is not stored',
    );
  }
  if (unknownTime) {
    return (
      kind: SleepPlanFreshness.unknown,
      note: 'a contributing job has no usable result time',
    );
  }
  if (inputReadStartedAtMs == null) {
    return (
      kind: SleepPlanFreshness.unknown,
      note: 'input read stamp is not stored',
    );
  }
  if (observations.isEmpty) {
    return (
      kind: SleepPlanFreshness.unknown,
      note: 'served day metadata was not observed',
    );
  }
  final byDay = <String, SleepPlanDayObservation>{
    for (final row in observations) row.day: row,
  };
  for (final day in window) {
    final row = byDay[day];
    if (row == null) {
      return (
        kind: SleepPlanFreshness.unknown,
        note: 'served metadata missing for $day',
      );
    }
    if (row.skipped || !row.inFetchWindow) {
      return (
        kind: SleepPlanFreshness.staleInputs,
        note: 'contributing day $day would leave the next rebuild',
      );
    }
    final computedAt = sleepPlanMillis(row.computedAtMs);
    if (computedAt == null) {
      return (
        kind: SleepPlanFreshness.unknown,
        note: 'served computed_at missing for $day',
      );
    }
    if (computedAt >= inputReadStartedAtMs) {
      return (
        kind: SleepPlanFreshness.staleInputs,
        note: 'day $day changed at or after the input read',
      );
    }
  }
  for (final row in observations) {
    if (!row.inFetchWindow || row.skipped) continue;
    if (contributing!.contains(row.day)) continue;
    return (
      kind: SleepPlanFreshness.staleInputs,
      note: 'day ${row.day} would enter the next rebuild',
    );
  }
  return (kind: SleepPlanFreshness.fresh, note: null);
}

bool _jobRelevant(
  SleepPlanInputJob job, {
  required String planDay,
  required Set<String>? contributing,
  required Set<String> fetchDays,
}) {
  if (job.kind == SleepPlanJobKind.napRecalc) return job.day == planDay;
  if (contributing != null && contributing.contains(job.day)) return true;
  return fetchDays.contains(job.day);
}

SleepPlanDebt? _debt(Object? raw) {
  if (raw == null || raw == kSleepPlanAbsentValue) return null;
  if (raw is! Map) return null;
  final map = _asStringMap(raw);
  if (map == null) return null;
  final value = map['value'];
  double? osd;
  if (value is Map) {
    final hours = value['osd_hours'];
    if (hours is num && hours.isFinite && hours > 0) osd = hours.toDouble();
  }
  final noteRaw = map['note'];
  final note = noteRaw is String && noteRaw.isNotEmpty ? noteRaw : null;
  if (osd == null && note == null) return null;
  return SleepPlanDebt(osdHours: osd, note: note);
}

_MetricParse _objectMetric(
  Object? raw, {
  required String field,
  required double min,
  double? max,
  double? maxExclusive,
  required SleepPlanIssue invalidValue,
}) {
  if (raw == null || raw == kSleepPlanAbsentValue) {
    return const _MetricParse(SleepPlanMetric.absent);
  }
  if (raw is! Map) {
    return _MetricParse(SleepPlanMetric.absent, SleepPlanIssue.invalidEnvelope);
  }
  final map = _asStringMap(raw);
  if (map == null) {
    return _MetricParse(SleepPlanMetric.absent, SleepPlanIssue.invalidEnvelope);
  }
  final provenance = _provenance(map);
  if (provenance.issue != null) {
    return _MetricParse(provenance.metric, provenance.issue);
  }
  final valueRaw = map['value'];
  if (_isAbsent(valueRaw)) {
    return _MetricParse(provenance.metric);
  }
  if (valueRaw is! Map) {
    return _MetricParse(provenance.metric, SleepPlanIssue.invalidEnvelope);
  }
  final inner = _asStringMap(valueRaw);
  if (inner == null) {
    return _MetricParse(provenance.metric, SleepPlanIssue.invalidEnvelope);
  }
  final number = inner[field];
  if (_isAbsent(number)) {
    return _MetricParse(provenance.metric);
  }
  if (number is! num || !number.isFinite) {
    return _MetricParse(provenance.metric, invalidValue);
  }
  final value = number.toDouble();
  if (value < min) return _MetricParse(provenance.metric, invalidValue);
  if (max != null && value > max) {
    return _MetricParse(provenance.metric, invalidValue);
  }
  if (maxExclusive != null && value >= maxExclusive) {
    return _MetricParse(provenance.metric, invalidValue);
  }
  return _MetricParse(
    SleepPlanMetric(
      present: true,
      value: value,
      note: provenance.metric.note,
      inputsUsed: provenance.metric.inputsUsed,
      tier: provenance.metric.tier,
      confidence: provenance.metric.confidence,
    ),
  );
}

_MetricParse _provenance(Map<String, dynamic> map) {
  final confRaw = map['confidence'];
  double? confidence;
  if (confRaw != null && !_isAbsent(confRaw)) {
    if (confRaw is! num ||
        !confRaw.isFinite ||
        confRaw < 0 ||
        confRaw > 1) {
      return const _MetricParse(
        SleepPlanMetric.absent,
        SleepPlanIssue.invalidConfidence,
      );
    }
    confidence = confRaw.toDouble();
  }
  final noteRaw = map['note'];
  if (noteRaw != null && noteRaw is! String) {
    return const _MetricParse(
      SleepPlanMetric.absent,
      SleepPlanIssue.invalidEnvelope,
    );
  }
  final note = noteRaw is String && noteRaw.isNotEmpty ? noteRaw : null;
  final tierRaw = map['tier'];
  final tier = tierRaw is String && tierRaw.isNotEmpty ? tierRaw : null;
  final inputs = _inputs(map['inputs_used']);
  return _MetricParse(
    SleepPlanMetric(
      note: note,
      inputsUsed: inputs,
      tier: tier,
      confidence: confidence,
    ),
  );
}

_NumberParse _plainMinutes(Object? raw) {
  if (_isAbsent(raw)) return const _NumberParse(null);
  if (raw is num) {
    if (!raw.isFinite) {
      return const _NumberParse(null, SleepPlanIssue.invalidContribution);
    }
    return _NumberParse(raw.toDouble());
  }
  return const _NumberParse(null, SleepPlanIssue.invalidContribution);
}

List<String> _inputs(Object? raw) {
  if (raw == null) return const [];
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is String && item.isNotEmpty) item,
  ];
}

bool _isAbsent(Object? raw) =>
    raw == null || raw == kSleepPlanAbsentValue;

int? _positiveWhole(Object? value) {
  if (value is! num || !value.isFinite || value <= 0) return null;
  if (value != value.roundToDouble()) return null;
  return value.toInt();
}

Map<String, dynamic>? _asStringMap(Map raw) {
  if (raw.keys.any((k) => k is! String)) return null;
  return raw.cast<String, dynamic>();
}

DateTime? _localDate(String day) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) return null;
  final p = day.split('-').map(int.parse).toList();
  final d = DateTime(p[0], p[1], p[2]);
  if (d.year != p[0] || d.month != p[1] || d.day != p[2]) return null;
  return d;
}
