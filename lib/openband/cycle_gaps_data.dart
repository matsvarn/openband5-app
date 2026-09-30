// Closed start-to-start gaps over CycleSnapshot. Civil-date differences only;
// no estimates, published bounds, or open as-of elapsed time.

import 'cycle_data.dart';

const int kCycleGapsDisplayMinimum = 12;

enum CycleGapsReason {
  available,
  trackingDisabled,
  displayDisabled,
  unreadableStarts,
  insufficientGaps,
  longGap,
}

class CycleObservedGap {
  const CycleObservedGap({
    required this.previousStart,
    required this.nextStart,
  });

  final String previousStart;
  final String nextStart;

  int get days => cycleDiffDays(previousStart, nextStart);

  @override
  bool operator ==(Object other) =>
      other is CycleObservedGap &&
      other.previousStart == previousStart &&
      other.nextStart == nextStart;

  @override
  int get hashCode => Object.hash(previousStart, nextStart);
}

class CycleGapsSummary {
  const CycleGapsSummary({
    required this.reason,
    required this.asOfDay,
    this.gaps = const [],
  });

  final CycleGapsReason reason;
  final String asOfDay;
  final List<CycleObservedGap> gaps;

  @override
  bool operator ==(Object other) =>
      other is CycleGapsSummary &&
      other.reason == reason &&
      other.asOfDay == asOfDay &&
      _sameGaps(other.gaps, gaps);

  @override
  int get hashCode => Object.hash(reason, asOfDay, Object.hashAll(gaps));
}

CycleGapsSummary buildCycleGapsSummary(CycleSnapshot snapshot) {
  final asOf = snapshot.day;

  CycleGapsSummary withheld(CycleGapsReason reason) => CycleGapsSummary(
        reason: reason,
        asOfDay: asOf,
      );

  if (!snapshot.settings.enabled) {
    return withheld(CycleGapsReason.trackingDisabled);
  }
  if (!snapshot.settings.lengthReviewEnabled) {
    return withheld(CycleGapsReason.displayDisabled);
  }
  if (snapshot.unreadableStarts) {
    return withheld(CycleGapsReason.unreadableStarts);
  }

  final dates = [
    for (final start in snapshot.starts)
      if (start.contributes && start.date.compareTo(asOf) <= 0) start.date,
  ]..sort();
  for (var i = 1; i < dates.length; i++) {
    if (dates[i] == dates[i - 1]) {
      return withheld(CycleGapsReason.unreadableStarts);
    }
  }

  final gaps = <CycleObservedGap>[
    for (var i = 1; i < dates.length; i++)
      CycleObservedGap(previousStart: dates[i - 1], nextStart: dates[i]),
  ];
  for (final gap in gaps) {
    if (gap.days > kCycleMaxObservedGapDays) {
      return withheld(CycleGapsReason.longGap);
    }
  }
  if (gaps.length < kCycleGapsDisplayMinimum) {
    return withheld(CycleGapsReason.insufficientGaps);
  }

  return CycleGapsSummary(
    reason: CycleGapsReason.available,
    asOfDay: asOf,
    gaps: List.unmodifiable(gaps),
  );
}

bool _sameGaps(List<CycleObservedGap> a, List<CycleObservedGap> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
