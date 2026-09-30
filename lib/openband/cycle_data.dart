// Typed cycle log + honest calendar estimate. Repositories decode storage here.
// No phase, fertility, pregnancy, or fabricated confidence. Median/MAD come
// from analytics; this file only does civil-date arithmetic and availability.

import 'dart:convert';

import 'package:openstrap_analytics/onehz.dart' as ana;

import '../data/day_label.dart';

const String kCycleStartKind = 'start';
const int kCycleMaxObservedGapDays = 60;
const int kCyclePreferencesVersion = 1;

enum CycleSituation { cycling, contraception, none }

enum CycleEstimateAvailability { available, missing, withheld, stale }

enum CycleEstimateReason {
  availableRange,
  availablePoint,
  missingStarts,
  trackingDisabled,
  estimatesDisabled,
  situationNone,
  gapExceedsSixtyDays,
  unreadableStarts,
  staleOpen,
}

enum CycleWriteStatus { saved, savedContextRefreshFailed, conflict }

/// Civil `YYYY-MM-DD` that exists on the Gregorian calendar.
bool isCycleCalendarDay(String day) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) return false;
  final p = day.split('-').map(int.parse).toList();
  final d = DateTime.utc(p[0], p[1], p[2]);
  return d.year == p[0] && d.month == p[1] && d.day == p[2];
}

void requireCycleCalendarDay(String day, [String name = 'day']) {
  if (!isCycleCalendarDay(day)) {
    throw ArgumentError.value(day, name, 'Expected a Gregorian YYYY-MM-DD.');
  }
}

DateTime cycleUtcDate(String day) {
  requireCycleCalendarDay(day);
  final p = day.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2]);
}

int cycleDiffDays(String from, String to) =>
    cycleUtcDate(to).difference(cycleUtcDate(from)).inDays;

String cycleAddDays(String day, int days) {
  final d = cycleUtcDate(day).add(Duration(days: days));
  String two(int x) => x.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
}

String cycleTodayLabel(DateTime now) => todayLabel(now);

bool cycleDateIsAfterToday(String day, DateTime now) =>
    day.compareTo(cycleTodayLabel(now)) > 0;

void requireCycleWriteDay(String day, DateTime now, [String name = 'date']) {
  requireCycleCalendarDay(day, name);
  if (cycleDateIsAfterToday(day, now)) {
    throw ArgumentError.value(
      day,
      name,
      'Cycle writes cannot be after local today.',
    );
  }
}

class CycleSettings {
  const CycleSettings({
    required this.enabled,
    required this.estimatesEnabled,
    this.situation,
    required this.lengthReviewEnabled,
  });

  final bool enabled;
  final bool estimatesEnabled;
  final CycleSituation? situation;
  final bool lengthReviewEnabled;

  /// Canonical profile fields once runtime persists version 1.
  Map<String, Object?> toProfileFields() => {
        'cycle_preferences_version': kCyclePreferencesVersion,
        'track_cycle': enabled,
        'cycle_estimates': estimatesEnabled,
        'repro_state': situation?.name,
        'cycle_length_review': lengthReviewEnabled,
      };

  /// [legacyEnabled] is prefs `cycle_tracking_enabled`. Version 1 uses
  /// `track_cycle` alone. Older rows need both flags on. Absent cycle flag
  /// keys are unchosen/off. A present non-bool (including JSON null) throws.
  /// A null profile is unavailable, not an empty new-user map. Absent or
  /// JSON-null `repro_state` is valid unchosen.
  static CycleSettings fromProfile(
    Map<String, Object?>? profile,
    bool legacyEnabled,
  ) {
    if (profile == null) {
      throw const FormatException('Cycle settings are unreadable.');
    }
    final version = _strictOptionalInt(profile, 'cycle_preferences_version');
    final track = _strictOptionalBool(profile, 'track_cycle', missing: false);
    final bool enabled;
    if (version == kCyclePreferencesVersion) {
      enabled = track;
    } else if (version == null) {
      enabled = legacyEnabled && track;
    } else {
      throw FormatException('Unknown cycle_preferences_version: $version');
    }
    return CycleSettings(
      enabled: enabled,
      estimatesEnabled: _strictOptionalBool(
        profile,
        'cycle_estimates',
        missing: false,
      ),
      situation: _strictSituation(profile['repro_state']),
      lengthReviewEnabled: _strictOptionalBool(
        profile,
        'cycle_length_review',
        missing: false,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CycleSettings &&
      other.enabled == enabled &&
      other.estimatesEnabled == estimatesEnabled &&
      other.situation == situation &&
      other.lengthReviewEnabled == lengthReviewEnabled;

  @override
  int get hashCode =>
      Object.hash(enabled, estimatesEnabled, situation, lengthReviewEnabled);
}

class CycleStart {
  const CycleStart({required this.date, required this.kind, this.note});

  final String date;
  final String kind;
  final String? note;

  bool get contributes => kind == kCycleStartKind;

  @override
  bool operator ==(Object other) =>
      other is CycleStart &&
      other.date == date &&
      other.kind == kind &&
      other.note == note;

  @override
  int get hashCode => Object.hash(date, kind, note);
}

class CycleObservation {
  const CycleObservation({
    required this.date,
    required this.tags,
    this.note,
    this.updatedAt,
  });

  final String date;
  final List<String> tags;
  final String? note;
  final int? updatedAt;

  bool get isClear => tags.isEmpty && (note == null || note!.isEmpty);

  @override
  bool operator ==(Object other) =>
      other is CycleObservation &&
      other.date == date &&
      _sameStrings(other.tags, tags) &&
      other.note == note &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(date, Object.hashAll(tags), note, updatedAt);
}

bool cycleObservationsContentEqual(CycleObservation? a, CycleObservation? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return a.date == b.date && _sameStrings(a.tags, b.tags) && a.note == b.note;
}

class CycleEstimate {
  const CycleEstimate({
    required this.availability,
    required this.reason,
    this.gapCount = 0,
    this.medianDays,
    this.madDays,
    this.from,
    this.to,
    this.point,
  });

  final CycleEstimateAvailability availability;
  final CycleEstimateReason reason;
  final int gapCount;
  final double? medianDays;
  final double? madDays;
  final String? from;
  final String? to;
  final String? point;

  static const missing = CycleEstimate(
    availability: CycleEstimateAvailability.missing,
    reason: CycleEstimateReason.missingStarts,
  );
}

class CycleSnapshot {
  const CycleSnapshot({
    required this.day,
    required this.settings,
    this.starts = const [],
    this.observations = const [],
    this.unreadableCount = 0,
    this.unreadableStarts = false,
    this.latestStart,
    this.cycleDay,
    this.estimate = CycleEstimate.missing,
  });

  final String day;
  final CycleSettings settings;
  final List<CycleStart> starts;
  final List<CycleObservation> observations;
  final int unreadableCount;
  /// Independent of estimate settings. True when an as-of start row cannot
  /// be trusted, so [cycleDay] must not be shown as known.
  final bool unreadableStarts;
  final CycleStart? latestStart;
  final int? cycleDay;
  final CycleEstimate estimate;
}

class CycleWriteResult {
  const CycleWriteResult.saved({
    this.start,
    this.observation,
    this.settings,
  })  : status = CycleWriteStatus.saved,
        currentStart = null,
        currentObservation = null;

  const CycleWriteResult.savedContextRefreshFailed({
    this.start,
    this.observation,
    this.settings,
  })  : status = CycleWriteStatus.savedContextRefreshFailed,
        currentStart = null,
        currentObservation = null;

  const CycleWriteResult.conflict({
    this.start,
    this.observation,
    this.settings,
    this.currentStart,
    this.currentObservation,
  }) : status = CycleWriteStatus.conflict;

  final CycleWriteStatus status;
  final CycleStart? start;
  final CycleObservation? observation;
  final CycleSettings? settings;
  final CycleStart? currentStart;
  final CycleObservation? currentObservation;

  bool get committed =>
      status == CycleWriteStatus.saved ||
      status == CycleWriteStatus.savedContextRefreshFailed;
  bool get contextRefreshFailed =>
      status == CycleWriteStatus.savedContextRefreshFailed;
  bool get conflict => status == CycleWriteStatus.conflict;
}

class CycleStartParse {
  const CycleStartParse.ok(this.start) : unreadable = false;
  const CycleStartParse.unreadable()
      : start = null,
        unreadable = true;

  final CycleStart? start;
  final bool unreadable;
}

class CycleObservationParse {
  const CycleObservationParse.ok(this.observation) : unreadable = false;
  const CycleObservationParse.unreadable()
      : observation = null,
        unreadable = true;

  final CycleObservation? observation;
  final bool unreadable;
}

class CycleLogParse {
  const CycleLogParse({
    required this.starts,
    required this.observations,
    required this.unreadableCount,
    required this.unreadableStarts,
  });

  final List<CycleStart> starts;
  final List<CycleObservation> observations;
  final int unreadableCount;
  final bool unreadableStarts;
}

CycleStartParse parseCycleStartRow(Map<Object?, Object?> row) {
  final date = row['date'];
  final kind = row['kind'];
  if (date is! String || !isCycleCalendarDay(date)) {
    return const CycleStartParse.unreadable();
  }
  if (kind is! String || kind.isEmpty) {
    return const CycleStartParse.unreadable();
  }
  final note = row['note'];
  if (note != null && note is! String) {
    return const CycleStartParse.unreadable();
  }
  return CycleStartParse.ok(
    CycleStart(date: date, kind: kind, note: note as String?),
  );
}

CycleObservationParse parseCycleObservationRow(Map<Object?, Object?> row) {
  final date = row['date'];
  if (date is! String || !isCycleCalendarDay(date)) {
    return const CycleObservationParse.unreadable();
  }
  final rawTags = row['symptoms_json'];
  if (rawTags is! String) return const CycleObservationParse.unreadable();
  Object? decoded;
  try {
    decoded = jsonDecode(rawTags);
  } on FormatException {
    return const CycleObservationParse.unreadable();
  }
  if (decoded is! List) return const CycleObservationParse.unreadable();
  final tags = <String>[];
  for (final e in decoded) {
    if (e is! String) return const CycleObservationParse.unreadable();
    tags.add(e);
  }
  final note = row['note'];
  if (note != null && note is! String) {
    return const CycleObservationParse.unreadable();
  }
  if (row.containsKey('updated_at') &&
      row['updated_at'] != null &&
      _strictOptionalEpoch(row['updated_at']) == null) {
    return const CycleObservationParse.unreadable();
  }
  return CycleObservationParse.ok(
    CycleObservation(
      date: date,
      tags: List.unmodifiable(tags),
      note: note as String?,
      updatedAt: _strictOptionalEpoch(row['updated_at']),
    ),
  );
}

CycleLogParse parseCycleLog({
  required List<Map<Object?, Object?>> startRows,
  required List<Map<Object?, Object?>> observationRows,
  String? asOf,
}) {
  if (asOf != null) requireCycleCalendarDay(asOf);
  final starts = <CycleStart>[];
  var unreadable = 0;
  var unreadableStarts = false;
  for (final row in startRows) {
    if (_cycleRowAfterAsOf(row, asOf)) continue;
    final parsed = parseCycleStartRow(row);
    if (parsed.unreadable || parsed.start == null) {
      unreadable++;
      unreadableStarts = true;
      continue;
    }
    starts.add(parsed.start!);
  }
  starts.sort((a, b) => a.date.compareTo(b.date));
  final observations = <CycleObservation>[];
  for (final row in observationRows) {
    if (_cycleRowAfterAsOf(row, asOf)) continue;
    final parsed = parseCycleObservationRow(row);
    if (parsed.unreadable || parsed.observation == null) {
      unreadable++;
      continue;
    }
    observations.add(parsed.observation!);
  }
  observations.sort((a, b) => a.date.compareTo(b.date));
  return CycleLogParse(
    starts: List.unmodifiable(starts),
    observations: List.unmodifiable(observations),
    unreadableCount: unreadable,
    unreadableStarts: unreadableStarts,
  );
}

CycleSnapshot buildCycleSnapshot({
  required String day,
  required CycleSettings settings,
  required List<CycleStart> starts,
  required List<CycleObservation> observations,
  required int unreadableCount,
  required bool unreadableStarts,
}) {
  requireCycleCalendarDay(day);
  final asOfStarts = [
    for (final s in starts)
      if (s.date.compareTo(day) <= 0) s,
  ];
  final asOfObservations = [
    for (final o in observations)
      if (o.date.compareTo(day) <= 0) o,
  ];
  CycleStart? latest;
  for (final s in asOfStarts) {
    if (s.contributes) latest = s;
  }
  return CycleSnapshot(
    day: day,
    settings: settings,
    starts: List.unmodifiable(asOfStarts),
    observations: List.unmodifiable(asOfObservations),
    unreadableCount: unreadableCount,
    unreadableStarts: unreadableStarts,
    latestStart: latest,
    cycleDay: unreadableStarts || latest == null
        ? null
        : cycleDiffDays(latest.date, day) + 1,
    estimate: estimateCycle(
      day: day,
      settings: settings,
      startsAsOfDay: asOfStarts,
      unreadableStarts: unreadableStarts,
    ),
  );
}

CycleEstimate estimateCycle({
  required String day,
  required CycleSettings settings,
  required List<CycleStart> startsAsOfDay,
  required bool unreadableStarts,
}) {
  final contributing = [
    for (final s in startsAsOfDay)
      if (s.contributes) s.date,
  ]..sort();
  final gaps = <double>[];
  var longGap = false;
  for (var i = 1; i < contributing.length; i++) {
    final gap = cycleDiffDays(contributing[i - 1], contributing[i]);
    if (gap > kCycleMaxObservedGapDays) longGap = true;
    gaps.add(gap.toDouble());
  }
  final gapCount = gaps.length;
  final medianDays = gaps.isEmpty ? null : ana.median(gaps);
  final madDays = gaps.length >= 2 ? ana.mad(gaps, scaled: false) : null;

  CycleEstimate withheld(CycleEstimateReason reason) => CycleEstimate(
        availability: CycleEstimateAvailability.withheld,
        reason: reason,
        gapCount: gapCount,
        medianDays: medianDays,
        madDays: madDays,
      );

  if (!settings.enabled) {
    return withheld(CycleEstimateReason.trackingDisabled);
  }
  if (!settings.estimatesEnabled) {
    return withheld(CycleEstimateReason.estimatesDisabled);
  }
  if (settings.situation == CycleSituation.none) {
    return withheld(CycleEstimateReason.situationNone);
  }
  if (unreadableStarts) {
    return withheld(CycleEstimateReason.unreadableStarts);
  }
  if (longGap) return withheld(CycleEstimateReason.gapExceedsSixtyDays);
  if (contributing.length < 2 || medianDays == null) {
    return CycleEstimate(
      availability: CycleEstimateAvailability.missing,
      reason: CycleEstimateReason.missingStarts,
      gapCount: gapCount,
    );
  }

  final offset = medianDays.round();
  final point = cycleAddDays(contributing.last, offset);
  String? from;
  String? to;
  var reason = CycleEstimateReason.availablePoint;
  if (madDays != null) {
    final w = madDays.round();
    from = cycleAddDays(point, -w);
    to = cycleAddDays(point, w);
    reason = CycleEstimateReason.availableRange;
  }
  if ((to ?? point).compareTo(day) < 0) {
    return CycleEstimate(
      availability: CycleEstimateAvailability.stale,
      reason: CycleEstimateReason.staleOpen,
      gapCount: gapCount,
      medianDays: medianDays,
      madDays: madDays,
      from: from,
      to: to,
      point: point,
    );
  }
  return CycleEstimate(
    availability: CycleEstimateAvailability.available,
    reason: reason,
    gapCount: gapCount,
    medianDays: medianDays,
    madDays: madDays,
    from: from,
    to: to,
    point: point,
  );
}

bool _cycleRowAfterAsOf(Map<Object?, Object?> row, String? asOf) {
  if (asOf == null) return false;
  final date = row['date'];
  return date is String &&
      isCycleCalendarDay(date) &&
      date.compareTo(asOf) > 0;
}

bool _sameStrings(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _strictOptionalBool(
  Map<String, Object?> profile,
  String key, {
  required bool missing,
}) {
  if (!profile.containsKey(key)) return missing;
  return _strictBool(profile[key], key);
}

bool _strictBool(Object? raw, String key) {
  if (raw is bool) return raw;
  throw FormatException('Unreadable $key in cycle settings.');
}

int? _strictOptionalInt(Map<String, Object?> profile, String key) {
  if (!profile.containsKey(key) || profile[key] == null) return null;
  final raw = profile[key];
  if (raw is int) return raw;
  throw FormatException('Unreadable $key in cycle settings.');
}

CycleSituation? _strictSituation(Object? raw) {
  if (raw == null) return null;
  if (raw is! String) {
    throw const FormatException('Unreadable repro_state in cycle settings.');
  }
  return switch (raw) {
    'cycling' => CycleSituation.cycling,
    'contraception' => CycleSituation.contraception,
    'none' => CycleSituation.none,
    _ => throw FormatException(
        'Unreadable repro_state in cycle settings: $raw',
      ),
  };
}

int? _strictOptionalEpoch(Object? raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  return null;
}
