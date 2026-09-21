// Typed latest-night cycle comparison. Repositories group civil dates here.
// Means, deltas, and z come from analytics; this file does not invent starts,
// substitute metrics, or claim phase, fertility, or sensor error.

import 'package:openstrap_analytics/onehz.dart' as ana;

import 'cycle_data.dart';
import 'cycle_measurements_data.dart';
import 'cycle_medians_data.dart';

const int kCycleComparisonPriorDays = 21;
const int kCycleComparisonPriorMinNights = 2;
const int kCycleComparisonSameDayMinPeriods = 3;

enum CycleComparisonReason { available, trackingDisabled }

enum CycleComparisonLatestReason { available, missing, unavailable, unreadable }

enum CycleComparisonPrior21Reason { available, noLatest, insufficientNights }

enum CycleComparisonSameDayReason {
  available,
  noLatest,
  unassignedLatest,
  unreadableStarts,
  emptyStarts,
  longLatestPeriod,
  insufficientPeriods,
}

class CycleComparisonAssignment {
  const CycleComparisonAssignment({
    required this.startDay,
    required this.cycleDay,
  });

  final String startDay;
  final int cycleDay;

  @override
  bool operator ==(Object other) =>
      other is CycleComparisonAssignment &&
      other.startDay == startDay &&
      other.cycleDay == cycleDay;

  @override
  int get hashCode => Object.hash(startDay, cycleDay);
}

class CycleComparisonNight {
  const CycleComparisonNight({
    required this.nightDay,
    this.assignment,
    required this.metric,
    this.sleepStart,
    this.sleepEnd,
    this.sleepSource,
    required this.algoVersion,
  });

  final String nightDay;
  /// Present only when a readable contributing start covers [nightDay].
  /// Unassigned and start-untrusted nights leave this null; never a fake date.
  final CycleComparisonAssignment? assignment;
  final CycleNightMetric metric;
  final DateTime? sleepStart;
  final DateTime? sleepEnd;
  final String? sleepSource;
  final int algoVersion;

  String? get startDay => assignment?.startDay;
  int? get cycleDay => assignment?.cycleDay;

  @override
  bool operator ==(Object other) =>
      other is CycleComparisonNight &&
      other.nightDay == nightDay &&
      other.assignment == assignment &&
      other.metric == metric &&
      other.sleepStart == sleepStart &&
      other.sleepEnd == sleepEnd &&
      other.sleepSource == sleepSource &&
      other.algoVersion == algoVersion;

  @override
  int get hashCode => Object.hash(
        nightDay,
        assignment,
        metric,
        sleepStart,
        sleepEnd,
        sleepSource,
        algoVersion,
      );
}

class CycleComparisonPrior21 {
  const CycleComparisonPrior21({
    required this.reason,
    this.startDay,
    this.endDay,
    this.count = 0,
    this.contributors = const [],
    this.mean,
    this.delta,
    this.z,
  });

  final CycleComparisonPrior21Reason reason;
  final String? startDay;
  final String? endDay;
  final int count;
  final List<CycleComparisonNight> contributors;
  final double? mean;
  final double? delta;
  final double? z;
}

class CycleComparisonSameDay {
  const CycleComparisonSameDay({
    required this.reason,
    this.cycleDay,
    this.count = 0,
    this.contributors = const [],
    this.mean,
    this.delta,
    this.z,
  });

  final CycleComparisonSameDayReason reason;
  final int? cycleDay;
  final int count;
  final List<CycleComparisonNight> contributors;
  final double? mean;
  final double? delta;
  final double? z;
}

class CycleMetricComparison {
  const CycleMetricComparison({
    required this.latestReason,
    this.latest,
    this.rejectedCount = 0,
    this.unreadableCount = 0,
    this.prior21 = const CycleComparisonPrior21(
      reason: CycleComparisonPrior21Reason.noLatest,
    ),
    this.sameDay = const CycleComparisonSameDay(
      reason: CycleComparisonSameDayReason.noLatest,
    ),
  });

  final CycleComparisonLatestReason latestReason;
  final CycleComparisonNight? latest;
  /// Window-only refused sources for this metric (imported/partial/correction
  /// /rejected sleep). Not padding. Does not include known-absent values.
  final int rejectedCount;
  /// Window-only unreadable sources for this metric (duplicate, corrupt
  /// payload/envelope). Sibling-metric corruption is not counted here.
  final int unreadableCount;
  final CycleComparisonPrior21 prior21;
  final CycleComparisonSameDay sameDay;
}

class CycleComparisonSnapshot {
  const CycleComparisonSnapshot({
    required this.window,
    required this.settings,
    required this.algoVersion,
    required this.reason,
    this.rhr = const CycleMetricComparison(
      latestReason: CycleComparisonLatestReason.missing,
    ),
    this.hrv = const CycleMetricComparison(
      latestReason: CycleComparisonLatestReason.missing,
    ),
    this.excludedNightCount = 0,
    this.unreadableNightCount = 0,
    this.partial = false,
  });

  final CycleMedianWindow window;
  final CycleSettings settings;
  final int algoVersion;
  final CycleComparisonReason reason;
  final CycleMetricComparison rhr;
  final CycleMetricComparison hrv;
  final int excludedNightCount;
  final int unreadableNightCount;
  final bool partial;
}

/// Inclusive civil start for the SQLite night query: 21 days before
/// [window.startDay], clamped to year 1 so year-1 windows stay valid.
String cycleComparisonQueryStart(CycleMedianWindow window) {
  requireCycleCalendarDay(window.startDay, 'window.startDay');
  requireCycleCalendarDay(window.endDay, 'window.endDay');
  return _civilSubtractDays(window.startDay, kCycleComparisonPriorDays);
}

CycleComparisonSnapshot buildCycleComparisonSnapshot({
  required CycleSettings settings,
  required CycleLogParse log,
  required int algoVersion,
  required CycleMedianWindow window,
  List<CycleNightSourceRow> rows = const [],
}) {
  requireCycleCalendarDay(window.startDay, 'window.startDay');
  requireCycleCalendarDay(window.endDay, 'window.endDay');
  if (window.page < 0) {
    throw ArgumentError.value(
      window.page,
      'window.page',
      'Expected a nonnegative whole-year page offset.',
    );
  }
  if (window.startDay.compareTo(window.endDay) > 0) {
    throw ArgumentError.value(
      window.endDay,
      'window.endDay',
      'Expected a day on or after window.startDay.',
    );
  }

  if (!settings.enabled) {
    return CycleComparisonSnapshot(
      window: window,
      settings: settings,
      algoVersion: algoVersion,
      reason: CycleComparisonReason.trackingDisabled,
    );
  }

  final queryStart = cycleComparisonQueryStart(window);
  final grouping = buildCycleMediansSnapshot(
    settings: settings,
    log: log,
    algoVersion: algoVersion,
    window: window,
  );

  final contributing = <String>[];
  var duplicate = false;
  for (final start in log.starts) {
    if (!start.contributes) continue;
    if (start.date.compareTo(window.endDay) > 0) continue;
    contributing.add(start.date);
  }
  contributing.sort();
  for (var i = 1; i < contributing.length; i++) {
    if (contributing[i] == contributing[i - 1]) duplicate = true;
  }
  final startsTrusted = !log.unreadableStarts && !duplicate;
  final labelStarts = <String>[];
  if (startsTrusted) {
    for (final s in contributing) {
      if (labelStarts.isEmpty || labelStarts.last != s) labelStarts.add(s);
    }
  }

  final byDay = <String, List<CycleNightSourceRow>>{};
  for (final row in rows) {
    if (row.algoVersion != algoVersion) continue;
    if (!isCycleCalendarDay(row.day)) continue;
    if (row.day.compareTo(queryStart) < 0 ||
        row.day.compareTo(window.endDay) > 0) {
      continue;
    }
    (byDay[row.day] ??= <CycleNightSourceRow>[]).add(row);
  }

  final rhrByDay = <String, CycleComparisonNight>{};
  final hrvByDay = <String, CycleComparisonNight>{};
  final status = <String, _NightStatus>{};
  var rhrRejected = 0;
  var rhrUnreadable = 0;
  var hrvRejected = 0;
  var hrvUnreadable = 0;

  final days = byDay.keys.toList()..sort();
  for (final day in days) {
    final matches = byDay[day]!;
    final inWindow = _inInclusive(day, window.startDay, window.endDay);
    if (matches.length > 1) {
      status[day] = const _NightStatus(unreadable: true);
      if (inWindow) {
        rhrUnreadable++;
        hrvUnreadable++;
      }
      continue;
    }
    final parsed = parseCycleNightSource(
      matches.single,
      algoVersion: algoVersion,
    );
    switch (parsed.disposition) {
      case CycleNightDisposition.unreadable:
        status[day] = const _NightStatus(unreadable: true);
        if (inWindow) {
          rhrUnreadable++;
          hrvUnreadable++;
        }
      case CycleNightDisposition.excluded:
        status[day] = const _NightStatus(excluded: true);
        if (inWindow) {
          rhrRejected++;
          hrvRejected++;
        }
      case CycleNightDisposition.missing:
        break;
      case CycleNightDisposition.eligible:
        status[day] = _NightStatus(
          unreadable: parsed.rhrUnreadable ||
              parsed.hrvUnreadable ||
              parsed.metadataUnreadable,
        );
        if (inWindow) {
          if (parsed.rhrUnreadable) rhrUnreadable++;
          if (parsed.hrvUnreadable) hrvUnreadable++;
        }
        final assignment = _assignment(day, labelStarts);
        if (parsed.rhr != null) {
          rhrByDay[day] = CycleComparisonNight(
            nightDay: day,
            assignment: assignment,
            metric: parsed.rhr!,
            sleepStart: parsed.windowStart,
            sleepEnd: parsed.windowEnd,
            sleepSource: parsed.sleepSource,
            algoVersion: algoVersion,
          );
        }
        if (parsed.hrv != null) {
          hrvByDay[day] = CycleComparisonNight(
            nightDay: day,
            assignment: assignment,
            metric: parsed.hrv!,
            sleepStart: parsed.windowStart,
            sleepEnd: parsed.windowEnd,
            sleepSource: parsed.sleepSource,
            algoVersion: algoVersion,
          );
        }
    }
  }

  final rhr = _metric(
    byDay: rhrByDay,
    window: window,
    grouping: grouping,
    startsTrusted: startsTrusted,
    rejectedCount: rhrRejected,
    unreadableCount: rhrUnreadable,
  );
  final hrv = _metric(
    byDay: hrvByDay,
    window: window,
    grouping: grouping,
    startsTrusted: startsTrusted,
    rejectedCount: hrvRejected,
    unreadableCount: hrvUnreadable,
  );

  var excludedNightCount = 0;
  var unreadableNightCount = 0;
  for (final day in status.keys) {
    if (!_coverageDay(day, window, rhr.prior21, hrv.prior21)) continue;
    final s = status[day]!;
    if (s.unreadable) {
      unreadableNightCount++;
    } else if (s.excluded) {
      excludedNightCount++;
    }
  }

  return CycleComparisonSnapshot(
    window: window,
    settings: settings,
    algoVersion: algoVersion,
    reason: CycleComparisonReason.available,
    rhr: rhr,
    hrv: hrv,
    excludedNightCount: excludedNightCount,
    unreadableNightCount: unreadableNightCount,
    partial: grouping.excludedPeriods.isNotEmpty ||
        excludedNightCount > 0 ||
        unreadableNightCount > 0,
  );
}

class _NightStatus {
  const _NightStatus({
    this.excluded = false,
    this.unreadable = false,
  });

  final bool excluded;
  final bool unreadable;
}

CycleMetricComparison _metric({
  required Map<String, CycleComparisonNight> byDay,
  required CycleMedianWindow window,
  required CycleMediansSnapshot grouping,
  required bool startsTrusted,
  required int rejectedCount,
  required int unreadableCount,
}) {
  CycleComparisonNight? latest;
  for (final day in byDay.keys) {
    if (!_inInclusive(day, window.startDay, window.endDay)) continue;
    final night = byDay[day]!;
    if (latest == null || night.nightDay.compareTo(latest.nightDay) > 0) {
      latest = night;
    }
  }
  final latestReason = latest != null
      ? CycleComparisonLatestReason.available
      : unreadableCount > 0
          ? CycleComparisonLatestReason.unreadable
          : rejectedCount > 0
              ? CycleComparisonLatestReason.unavailable
              : CycleComparisonLatestReason.missing;
  if (latest == null) {
    return CycleMetricComparison(
      latestReason: latestReason,
      rejectedCount: rejectedCount,
      unreadableCount: unreadableCount,
    );
  }
  return CycleMetricComparison(
    latestReason: latestReason,
    latest: latest,
    rejectedCount: rejectedCount,
    unreadableCount: unreadableCount,
    prior21: _prior21(latest, byDay),
    sameDay: _sameDay(
      latest: latest,
      byDay: byDay,
      window: window,
      grouping: grouping,
      startsTrusted: startsTrusted,
    ),
  );
}

bool _inInclusive(String day, String start, String end) =>
    day.compareTo(start) >= 0 && day.compareTo(end) <= 0;

bool _coverageDay(
  String day,
  CycleMedianWindow window,
  CycleComparisonPrior21 rhr,
  CycleComparisonPrior21 hrv,
) {
  if (_inInclusive(day, window.startDay, window.endDay)) return true;
  final rhrStart = rhr.startDay;
  final rhrEnd = rhr.endDay;
  if (rhrStart != null &&
      rhrEnd != null &&
      _inInclusive(day, rhrStart, rhrEnd)) {
    return true;
  }
  final hrvStart = hrv.startDay;
  final hrvEnd = hrv.endDay;
  if (hrvStart != null &&
      hrvEnd != null &&
      _inInclusive(day, hrvStart, hrvEnd)) {
    return true;
  }
  return false;
}

CycleComparisonPrior21 _prior21(
  CycleComparisonNight latest,
  Map<String, CycleComparisonNight> byDay,
) {
  if (cycleDiffDays('0001-01-01', latest.nightDay) < 1) {
    return const CycleComparisonPrior21(
      reason: CycleComparisonPrior21Reason.insufficientNights,
    );
  }
  final endDay = cycleAddDays(latest.nightDay, -1);
  final startDay = _civilSubtractDays(
    latest.nightDay,
    kCycleComparisonPriorDays,
  );
  final contributors = [
    for (final day in byDay.keys)
      if (day.compareTo(startDay) >= 0 && day.compareTo(endDay) <= 0)
        byDay[day]!,
  ];
  final values = [for (final c in contributors) c.metric.value];
  if (values.length < kCycleComparisonPriorMinNights) {
    return CycleComparisonPrior21(
      reason: CycleComparisonPrior21Reason.insufficientNights,
      startDay: startDay,
      endDay: endDay,
      count: values.length,
      contributors: List.unmodifiable(contributors),
    );
  }
  final mean = ana.mean(values)!;
  return CycleComparisonPrior21(
    reason: CycleComparisonPrior21Reason.available,
    startDay: startDay,
    endDay: endDay,
    count: values.length,
    contributors: List.unmodifiable(contributors),
    mean: mean,
    delta: latest.metric.value - mean,
    z: ana.z(latest.metric.value, values),
  );
}

CycleComparisonSameDay _sameDay({
  required CycleComparisonNight latest,
  required Map<String, CycleComparisonNight> byDay,
  required CycleMedianWindow window,
  required CycleMediansSnapshot grouping,
  required bool startsTrusted,
}) {
  if (!startsTrusted ||
      grouping.reason == CycleMediansReason.unreadableStarts) {
    return const CycleComparisonSameDay(
      reason: CycleComparisonSameDayReason.unreadableStarts,
    );
  }
  if (grouping.reason == CycleMediansReason.emptyStarts) {
    return const CycleComparisonSameDay(
      reason: CycleComparisonSameDayReason.emptyStarts,
    );
  }
  final cycleDay = latest.cycleDay;
  final startDay = latest.startDay;
  if (cycleDay == null || startDay == null) {
    final inLong = grouping.excludedPeriods.any(
      (e) =>
          latest.nightDay.compareTo(e.period.startDay) >= 0 &&
          latest.nightDay.compareTo(e.period.endDay) <= 0,
    );
    return CycleComparisonSameDay(
      reason: inLong
          ? CycleComparisonSameDayReason.longLatestPeriod
          : CycleComparisonSameDayReason.unassignedLatest,
    );
  }

  CycleMeasurementPeriod? current;
  for (final period in grouping.periods) {
    if (latest.nightDay.compareTo(period.startDay) >= 0 &&
        latest.nightDay.compareTo(period.endDay) <= 0) {
      current = period;
    }
  }
  if (current == null) {
    final inLong = grouping.excludedPeriods.any(
      (e) =>
          latest.nightDay.compareTo(e.period.startDay) >= 0 &&
          latest.nightDay.compareTo(e.period.endDay) <= 0,
    );
    return CycleComparisonSameDay(
      reason: inLong
          ? CycleComparisonSameDayReason.longLatestPeriod
          : CycleComparisonSameDayReason.unassignedLatest,
      cycleDay: cycleDay,
    );
  }
  if (cycleDay < 1 || cycleDay > kCycleMaxObservedGapDays) {
    return CycleComparisonSameDay(
      reason: CycleComparisonSameDayReason.unassignedLatest,
      cycleDay: cycleDay,
    );
  }

  final contributors = <CycleComparisonNight>[];
  for (final period in grouping.periods) {
    if (period.startDay.compareTo(current.startDay) >= 0) continue;
    final nightDay = cycleAddDays(period.startDay, cycleDay - 1);
    if (nightDay.compareTo(period.startDay) < 0 ||
        nightDay.compareTo(period.endDay) > 0) {
      continue;
    }
    if (nightDay.compareTo(window.startDay) < 0 ||
        nightDay.compareTo(window.endDay) > 0) {
      continue;
    }
    final night = byDay[nightDay];
    if (night == null) continue;
    contributors.add(night);
  }

  if (contributors.length < kCycleComparisonSameDayMinPeriods) {
    return CycleComparisonSameDay(
      reason: CycleComparisonSameDayReason.insufficientPeriods,
      cycleDay: cycleDay,
      count: contributors.length,
      contributors: List.unmodifiable(contributors),
    );
  }
  final values = [for (final c in contributors) c.metric.value];
  final mean = ana.mean(values)!;
  return CycleComparisonSameDay(
    reason: CycleComparisonSameDayReason.available,
    cycleDay: cycleDay,
    count: contributors.length,
    contributors: List.unmodifiable(contributors),
    mean: mean,
    delta: latest.metric.value - mean,
    z: ana.z(latest.metric.value, values),
  );
}

CycleComparisonAssignment? _assignment(String day, List<String> starts) {
  String? start;
  for (final s in starts) {
    if (s.compareTo(day) <= 0) {
      start = s;
    } else {
      break;
    }
  }
  if (start == null) return null;
  return CycleComparisonAssignment(
    startDay: start,
    cycleDay: cycleDiffDays(start, day) + 1,
  );
}

String _civilSubtractDays(String day, int days) {
  requireCycleCalendarDay(day);
  if (days <= 0) return day;
  if (cycleDiffDays('0001-01-01', day) < days) return '0001-01-01';
  return cycleAddDays(day, -days);
}
