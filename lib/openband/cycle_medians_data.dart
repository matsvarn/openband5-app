// Typed twelve-month cycle-day medians of stored nights. Repositories group
// civil dates here. Medians, robust baseline, and MDC come from analytics;
// this file does not invent starts, substitute metrics, or compare z-scores.

import 'package:openstrap_analytics/onehz.dart' as ana;

import 'cycle_data.dart';
import 'cycle_measurements_data.dart';

const int kCycleMedianWindowMonths = 12;
const int kCycleMedianMinPointPeriods = 2;
const int kCycleMedianMinChartDays = 3;

enum CycleMediansReason {
  available,
  trackingDisabled,
  emptyStarts,
  unreadableStarts,
  longPeriods,
  insufficientDays,
}

enum CycleMedianPeriodExcludeReason { longClosed, longOpen }

class CycleMedianWindow {
  const CycleMedianWindow._({
    required this.startDay,
    required this.endDay,
    required this.page,
  });

  final String startDay;
  final String endDay;
  final int page;

  int get expectedNightCount => cycleDiffDays(startDay, endDay) + 1;

  List<String> get expectedNights =>
      cycleCivilDaysInclusive(startDay, endDay);
}

class CycleMedianContributor {
  const CycleMedianContributor({
    required this.nightDay,
    required this.startDay,
    required this.cycleDay,
    required this.metric,
    this.sleepStart,
    this.sleepEnd,
    this.sleepSource,
    required this.algoVersion,
  });

  final String nightDay;
  final String startDay;
  final int cycleDay;
  final CycleNightMetric metric;
  final DateTime? sleepStart;
  final DateTime? sleepEnd;
  final String? sleepSource;
  final int algoVersion;
}

class CycleMedianPoint {
  const CycleMedianPoint({
    required this.cycleDay,
    this.median,
    required this.contributingPeriodCount,
    this.contributors = const [],
  });

  final int cycleDay;
  final double? median;
  final int contributingPeriodCount;
  final List<CycleMedianContributor> contributors;
}

class CycleMedianNightSpread {
  const CycleMedianNightSpread({
    this.proxy,
    this.medianSpan,
    this.sampleCount = 0,
  });

  /// Statistical spread of eligible source nights (MDC of a robust baseline).
  /// Not measured sensor error, clinical significance, or physiological validity.
  final double? proxy;
  /// Descriptive max−min of plotted medians when at least two exist.
  final double? medianSpan;
  final int sampleCount;
}

class CycleMedianSeries {
  const CycleMedianSeries({
    required this.available,
    this.points = const [],
    this.latest,
    this.qualifyingDayCount = 0,
    this.eligibleNights = const [],
    this.spread = const CycleMedianNightSpread(),
  });

  final bool available;
  final List<CycleMedianPoint> points;
  final CycleMedianPoint? latest;
  final int qualifyingDayCount;
  final List<CycleMedianContributor> eligibleNights;
  final CycleMedianNightSpread spread;

  int get eligibleNightCount => eligibleNights.length;
}

class CycleMedianExcludedPeriod {
  const CycleMedianExcludedPeriod({
    required this.period,
    required this.reason,
  });

  final CycleMeasurementPeriod period;
  final CycleMedianPeriodExcludeReason reason;
}

class CycleMediansSnapshot {
  const CycleMediansSnapshot({
    required this.window,
    required this.settings,
    required this.algoVersion,
    required this.reason,
    this.periods = const [],
    this.excludedPeriods = const [],
    this.rhr = const CycleMedianSeries(available: false),
    this.hrv = const CycleMedianSeries(available: false),
    this.excludedNightCount = 0,
    this.unreadableNightCount = 0,
    this.partial = false,
  });

  final CycleMedianWindow window;
  final CycleSettings settings;
  final int algoVersion;
  final CycleMediansReason reason;
  final List<CycleMeasurementPeriod> periods;
  final List<CycleMedianExcludedPeriod> excludedPeriods;
  final CycleMedianSeries rhr;
  final CycleMedianSeries hrv;
  final int excludedNightCount;
  final int unreadableNightCount;
  final bool partial;

  int get excludedPeriodCount => excludedPeriods.length;
}

/// Twelve-calendar-month window from a fixed [anchorEnd] and nonnegative
/// whole-year [pageOffset]. Boundaries are [anchorEnd]+1 day shifted by
/// −12×offset calendar months with day clamping. Inclusive end is the
/// boundary minus one civil day. Anchor future limit is the caller's.
CycleMedianWindow cycleMedianWindow({
  required String anchorEnd,
  required int pageOffset,
}) {
  requireCycleCalendarDay(anchorEnd, 'anchorEnd');
  if (pageOffset < 0) {
    throw ArgumentError.value(
      pageOffset,
      'pageOffset',
      'Expected a nonnegative whole-year page offset.',
    );
  }
  _requireBoundaryYear(anchorEnd, 'anchorEnd');
  final origin = _civilAddDays(anchorEnd, 1, 'anchorEnd');
  final close = _addCalendarMonths(origin, -kCycleMedianWindowMonths * pageOffset);
  final open = _addCalendarMonths(
    origin,
    -kCycleMedianWindowMonths * (pageOffset + 1),
  );
  final endDay = _civilAddDays(close, -1, 'anchorEnd');
  if (open.compareTo(endDay) > 0) {
    throw ArgumentError.value(
      anchorEnd,
      'anchorEnd',
      'Cycle median window start must not follow end.',
    );
  }
  return CycleMedianWindow._(startDay: open, endDay: endDay, page: pageOffset);
}

CycleMediansSnapshot buildCycleMediansSnapshot({
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
  _requireBoundaryYear(window.startDay, 'window.startDay');
  _requireBoundaryYear(window.endDay, 'window.endDay');

  CycleMediansSnapshot withheld(CycleMediansReason reason) =>
      CycleMediansSnapshot(
        window: window,
        settings: settings,
        algoVersion: algoVersion,
        reason: reason,
      );

  if (!settings.enabled) {
    return withheld(CycleMediansReason.trackingDisabled);
  }

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
  if (log.unreadableStarts || duplicate) {
    return withheld(CycleMediansReason.unreadableStarts);
  }
  if (contributing.isEmpty) {
    return withheld(CycleMediansReason.emptyStarts);
  }

  final periods = <CycleMeasurementPeriod>[];
  final excluded = <CycleMedianExcludedPeriod>[];
  for (var i = 0; i < contributing.length; i++) {
    final start = contributing[i];
    final next = i + 1 < contributing.length ? contributing[i + 1] : null;
    final open = next == null;
    final end = open ? window.endDay : cycleAddDays(next, -1);
    if (end.compareTo(start) < 0) continue;
    final period = CycleMeasurementPeriod(
      startDay: start,
      endDay: end,
      open: open,
    );
    if (end.compareTo(window.startDay) < 0 ||
        start.compareTo(window.endDay) > 0) {
      continue;
    }
    if (open) {
      final age = cycleDiffDays(start, window.endDay) + 1;
      if (age > kCycleMaxObservedGapDays) {
        excluded.add(
          CycleMedianExcludedPeriod(
            period: period,
            reason: CycleMedianPeriodExcludeReason.longOpen,
          ),
        );
        continue;
      }
    } else {
      final gap = cycleDiffDays(start, next);
      if (gap > kCycleMaxObservedGapDays) {
        excluded.add(
          CycleMedianExcludedPeriod(
            period: period,
            reason: CycleMedianPeriodExcludeReason.longClosed,
          ),
        );
        continue;
      }
    }
    periods.add(period);
  }

  if (periods.isEmpty) {
    if (excluded.isNotEmpty) {
      return CycleMediansSnapshot(
        window: window,
        settings: settings,
        algoVersion: algoVersion,
        reason: CycleMediansReason.longPeriods,
        excludedPeriods: List.unmodifiable(excluded),
        partial: true,
      );
    }
    return withheld(CycleMediansReason.emptyStarts);
  }

  final byDay = <String, List<CycleNightSourceRow>>{};
  for (final row in rows) {
    if (row.algoVersion != algoVersion) continue;
    if (!isCycleCalendarDay(row.day)) continue;
    if (row.day.compareTo(window.startDay) < 0 ||
        row.day.compareTo(window.endDay) > 0) {
      continue;
    }
    (byDay[row.day] ??= <CycleNightSourceRow>[]).add(row);
  }

  final rhrByDay = <int, List<CycleMedianContributor>>{};
  final hrvByDay = <int, List<CycleMedianContributor>>{};
  final rhrEligible = <CycleMedianContributor>[];
  final hrvEligible = <CycleMedianContributor>[];
  var excludedNightCount = 0;
  var unreadableNightCount = 0;

  for (final period in periods) {
    final clipStart = period.startDay.compareTo(window.startDay) < 0
        ? window.startDay
        : period.startDay;
    final clipEnd = period.endDay.compareTo(window.endDay) > 0
        ? window.endDay
        : period.endDay;
    if (clipEnd.compareTo(clipStart) < 0) continue;
    for (final day in cycleCivilDaysInclusive(clipStart, clipEnd)) {
      final cycleDay = cycleDiffDays(period.startDay, day) + 1;
      if (cycleDay < 1 || cycleDay > kCycleMaxObservedGapDays) continue;
      final matches = byDay[day];
      if (matches == null || matches.isEmpty) continue;
      if (matches.length > 1) {
        unreadableNightCount++;
        continue;
      }
      final parsed = parseCycleNightSource(
        matches.single,
        algoVersion: algoVersion,
      );
      switch (parsed.disposition) {
        case CycleNightDisposition.unreadable:
          unreadableNightCount++;
        case CycleNightDisposition.excluded:
          excludedNightCount++;
        case CycleNightDisposition.missing:
          break;
        case CycleNightDisposition.eligible:
          if (parsed.rhrUnreadable ||
              parsed.hrvUnreadable ||
              parsed.metadataUnreadable) {
            unreadableNightCount++;
          }
          if (parsed.rhr != null) {
            final c = CycleMedianContributor(
              nightDay: day,
              startDay: period.startDay,
              cycleDay: cycleDay,
              metric: parsed.rhr!,
              sleepStart: parsed.windowStart,
              sleepEnd: parsed.windowEnd,
              sleepSource: parsed.sleepSource,
              algoVersion: algoVersion,
            );
            rhrEligible.add(c);
            (rhrByDay[cycleDay] ??= <CycleMedianContributor>[]).add(c);
          }
          if (parsed.hrv != null) {
            final c = CycleMedianContributor(
              nightDay: day,
              startDay: period.startDay,
              cycleDay: cycleDay,
              metric: parsed.hrv!,
              sleepStart: parsed.windowStart,
              sleepEnd: parsed.windowEnd,
              sleepSource: parsed.sleepSource,
              algoVersion: algoVersion,
            );
            hrvEligible.add(c);
            (hrvByDay[cycleDay] ??= <CycleMedianContributor>[]).add(c);
          }
      }
    }
  }

  final rhr = _series(rhrByDay, rhrEligible);
  final hrv = _series(hrvByDay, hrvEligible);
  final reason = rhr.available || hrv.available
      ? CycleMediansReason.available
      : CycleMediansReason.insufficientDays;
  return CycleMediansSnapshot(
    window: window,
    settings: settings,
    algoVersion: algoVersion,
    reason: reason,
    periods: List.unmodifiable(periods),
    excludedPeriods: List.unmodifiable(excluded),
    rhr: rhr,
    hrv: hrv,
    excludedNightCount: excludedNightCount,
    unreadableNightCount: unreadableNightCount,
    partial: excluded.isNotEmpty ||
        excludedNightCount > 0 ||
        unreadableNightCount > 0,
  );
}

CycleMedianSeries _series(
  Map<int, List<CycleMedianContributor>> byDay,
  List<CycleMedianContributor> eligible,
) {
  var lastQualifying = 0;
  var qualifyingCount = 0;
  for (final cycleDay in byDay.keys.toList()..sort()) {
    final point = _point(cycleDay, byDay[cycleDay]!);
    if (point.median != null) {
      lastQualifying = cycleDay;
      qualifyingCount++;
    }
  }
  final available = qualifyingCount >= kCycleMedianMinChartDays;
  final dense = available
      ? [
          for (var day = 1; day <= lastQualifying; day++)
            _point(day, byDay[day] ?? const []),
        ]
      : const <CycleMedianPoint>[];
  final plotted = [
    for (final p in dense)
      if (p.median != null) p.median!,
  ];
  return CycleMedianSeries(
    available: available,
    points: List.unmodifiable(dense),
    latest: available ? dense.last : null,
    qualifyingDayCount: qualifyingCount,
    eligibleNights: List.unmodifiable(eligible),
    spread: _nightSpread(eligible, plotted),
  );
}

CycleMedianPoint _point(int cycleDay, List<CycleMedianContributor> raw) {
  final byStart = <String, CycleMedianContributor>{};
  for (final c in raw) {
    byStart.putIfAbsent(c.startDay, () => c);
  }
  final contributors = byStart.values.toList()
    ..sort((a, b) => a.startDay.compareTo(b.startDay));
  final values = [for (final c in contributors) c.metric.value];
  final median = values.length >= kCycleMedianMinPointPeriods
      ? ana.median(values)
      : null;
  return CycleMedianPoint(
    cycleDay: cycleDay,
    median: median,
    contributingPeriodCount: contributors.length,
    contributors: List.unmodifiable(contributors),
  );
}

CycleMedianNightSpread _nightSpread(
  List<CycleMedianContributor> eligible,
  List<double> plottedMedians,
) {
  final values = [for (final c in eligible) c.metric.value];
  final base = ana.robustBaseline(values, minValid: kCycleMedianMinChartDays);
  final proxy = !base.sufficient || base.scale == null || base.scale! <= 0
      ? null
      : ana.mdc(base);
  double? span;
  if (plottedMedians.length >= 2) {
    var lo = plottedMedians.first;
    var hi = plottedMedians.first;
    for (final v in plottedMedians) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    span = hi - lo;
  }
  return CycleMedianNightSpread(
    proxy: proxy,
    medianSpan: span,
    sampleCount: values.length,
  );
}

String _addCalendarMonths(String day, int months) {
  requireCycleCalendarDay(day);
  final p = day.split('-').map(int.parse).toList();
  final total = p[0] * 12 + (p[1] - 1) + months;
  final year = total ~/ 12;
  final month = total % 12 + 1;
  if (year < 1 || year > 9999) {
    throw ArgumentError.value(
      day,
      'anchorEnd',
      'Cycle median window boundaries must be year 1..9999.',
    );
  }
  final dim = _daysInMonth(year, month);
  final clamped = p[2] > dim ? dim : p[2];
  return _civilYmd(year, month, clamped);
}

String _civilAddDays(String day, int days, String name) {
  requireCycleCalendarDay(day, name);
  final p = day.split('-').map(int.parse).toList();
  var year = p[0];
  var month = p[1];
  var d = p[2] + days;
  if (days >= 0) {
    while (true) {
      final dim = _daysInMonth(year, month);
      if (d <= dim) break;
      d -= dim;
      month++;
      if (month > 12) {
        month = 1;
        year++;
      }
    }
  } else {
    while (d < 1) {
      month--;
      if (month < 1) {
        month = 12;
        year--;
      }
      d += _daysInMonth(year, month);
    }
  }
  if (year < 1 || year > 9999) {
    throw ArgumentError.value(
      day,
      name,
      'Cycle median window boundaries must be year 1..9999.',
    );
  }
  return _civilYmd(year, month, d);
}

void _requireBoundaryYear(String day, String name) {
  final year = int.parse(day.substring(0, 4));
  if (year < 1 || year > 9999) {
    throw ArgumentError.value(
      day,
      name,
      'Cycle median window boundaries must be year 1..9999.',
    );
  }
}

int _daysInMonth(int year, int month) {
  const table = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (month == 2 && _gregorianLeap(year)) return 29;
  return table[month - 1];
}

bool _gregorianLeap(int year) =>
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);

String _civilYmd(int year, int month, int day) {
  String two(int x) => x.toString().padLeft(2, '0');
  return '${year.toString().padLeft(4, '0')}-${two(month)}-${two(day)}';
}
