// Typed observation counts over CycleSnapshot. Civil-date grouping only;
// no percentages, phases, or fabricated absence.

import 'cycle_data.dart';

enum CycleObservationsAvailability { available, missing, withheld }

enum CycleObservationsReason {
  available,
  trackingDisabled,
  unreadableStarts,
  insufficientStarts,
}

class CycleObservationTagCount {
  const CycleObservationTagCount({required this.tag, required this.count});

  final String tag;
  final int count;

  @override
  bool operator ==(Object other) =>
      other is CycleObservationTagCount &&
      other.tag == tag &&
      other.count == count;

  @override
  int get hashCode => Object.hash(tag, count);
}

class CycleObservationsWeek {
  const CycleObservationsWeek({
    required this.fromCycleDay,
    required this.toCycleDay,
    required this.taggedDays,
    this.counts = const [],
  });

  final int fromCycleDay;
  final int toCycleDay;
  /// Days in this week window with nonempty tags, across contributing cycles.
  /// Note-only and missing rows are not a "no symptoms" count.
  final int taggedDays;
  final List<CycleObservationTagCount> counts;

  @override
  bool operator ==(Object other) =>
      other is CycleObservationsWeek &&
      other.fromCycleDay == fromCycleDay &&
      other.toCycleDay == toCycleDay &&
      other.taggedDays == taggedDays &&
      _sameCounts(other.counts, counts);

  @override
  int get hashCode => Object.hash(
        fromCycleDay,
        toCycleDay,
        taggedDays,
        Object.hashAll(counts),
      );
}

class CycleObservationsSummary {
  const CycleObservationsSummary({
    required this.availability,
    required this.reason,
    required this.asOfDay,
    this.firstStartDay,
    this.cycleCount = 0,
    this.unreadableCount = 0,
    this.partial = false,
    this.weeks = const [],
  });

  final CycleObservationsAvailability availability;
  final CycleObservationsReason reason;
  final String asOfDay;
  /// Earliest contributing as-of start. Null when grouping is not available.
  final String? firstStartDay;
  /// Contributing as-of starts, including the current open cycle.
  final int cycleCount;
  final int unreadableCount;
  final bool partial;
  final List<CycleObservationsWeek> weeks;

  @override
  bool operator ==(Object other) =>
      other is CycleObservationsSummary &&
      other.availability == availability &&
      other.reason == reason &&
      other.asOfDay == asOfDay &&
      other.firstStartDay == firstStartDay &&
      other.cycleCount == cycleCount &&
      other.unreadableCount == unreadableCount &&
      other.partial == partial &&
      _sameWeeks(other.weeks, weeks);

  @override
  int get hashCode => Object.hash(
        availability,
        reason,
        asOfDay,
        firstStartDay,
        cycleCount,
        unreadableCount,
        partial,
        Object.hashAll(weeks),
      );
}

CycleObservationsSummary buildCycleObservationsSummary(CycleSnapshot snapshot) {
  final asOf = snapshot.day;
  final unreadableCount = snapshot.unreadableCount;
  final partial = unreadableCount > 0;

  CycleObservationsSummary withheld(CycleObservationsReason reason) =>
      CycleObservationsSummary(
        availability: CycleObservationsAvailability.withheld,
        reason: reason,
        asOfDay: asOf,
        unreadableCount: unreadableCount,
        partial: partial,
      );

  if (!snapshot.settings.enabled) {
    return withheld(CycleObservationsReason.trackingDisabled);
  }
  if (snapshot.unreadableStarts) {
    return withheld(CycleObservationsReason.unreadableStarts);
  }

  final starts = [
    for (final start in snapshot.starts)
      if (start.contributes && start.date.compareTo(asOf) <= 0) start.date,
  ]..sort();
  final uniqueStarts = <String>[];
  for (final date in starts) {
    if (uniqueStarts.isEmpty || uniqueStarts.last != date) {
      uniqueStarts.add(date);
    }
  }

  if (uniqueStarts.length < 3) {
    return CycleObservationsSummary(
      availability: CycleObservationsAvailability.missing,
      reason: CycleObservationsReason.insufficientStarts,
      asOfDay: asOf,
      unreadableCount: unreadableCount,
      partial: partial,
    );
  }

  var maxLength = 0;
  for (var i = 0; i < uniqueStarts.length; i++) {
    final start = uniqueStarts[i];
    final end = i + 1 < uniqueStarts.length
        ? cycleAddDays(uniqueStarts[i + 1], -1)
        : asOf;
    if (end.compareTo(start) < 0) continue;
    final length = cycleDiffDays(start, end) + 1;
    if (length > maxLength) maxLength = length;
  }

  final weekCount = maxLength == 0 ? 0 : (maxLength + 6) ~/ 7;
  final taggedDates = <int, Set<String>>{
    for (var i = 0; i < weekCount; i++) i: <String>{},
  };
  final tagCounts = <int, Map<String, int>>{
    for (var i = 0; i < weekCount; i++) i: <String, int>{},
  };

  final observations = [...snapshot.observations]
    ..sort((a, b) => a.date.compareTo(b.date));
  final firstStart = uniqueStarts.first;
  final tagsByDay = <String, Set<String>>{};
  for (final observation in observations) {
    if (observation.date.compareTo(asOf) > 0) continue;
    if (observation.date.compareTo(firstStart) < 0) continue;
    (tagsByDay[observation.date] ??= <String>{}).addAll(observation.tags);
  }
  for (final entry in tagsByDay.entries) {
    final tags = entry.value;
    if (tags.isEmpty) continue;
    final start = _nearestStart(uniqueStarts, entry.key);
    if (start == null) continue;
    final cycleDay = cycleDiffDays(start, entry.key) + 1;
    final weekIndex = (cycleDay - 1) ~/ 7;
    if (weekIndex < 0 || weekIndex >= weekCount) continue;
    taggedDates[weekIndex]!.add(entry.key);
    final counts = tagCounts[weekIndex]!;
    for (final tag in tags) {
      counts[tag] = (counts[tag] ?? 0) + 1;
    }
  }

  final weeks = <CycleObservationsWeek>[
    for (var i = 0; i < weekCount; i++)
      CycleObservationsWeek(
        fromCycleDay: i * 7 + 1,
        toCycleDay: (i + 1) * 7,
        taggedDays: taggedDates[i]!.length,
        counts: List.unmodifiable(_sortedCounts(tagCounts[i]!)),
      ),
  ];

  return CycleObservationsSummary(
    availability: CycleObservationsAvailability.available,
    reason: CycleObservationsReason.available,
    asOfDay: asOf,
    firstStartDay: firstStart,
    cycleCount: uniqueStarts.length,
    unreadableCount: unreadableCount,
    partial: partial,
    weeks: List.unmodifiable(weeks),
  );
}

String? _nearestStart(List<String> starts, String day) {
  String? found;
  for (final start in starts) {
    if (start.compareTo(day) <= 0) {
      found = start;
    } else {
      break;
    }
  }
  return found;
}

List<CycleObservationTagCount> _sortedCounts(Map<String, int> counts) {
  final rows = [
    for (final e in counts.entries)
      CycleObservationTagCount(tag: e.key, count: e.value),
  ];
  rows.sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    if (byCount != 0) return byCount;
    return a.tag.compareTo(b.tag);
  });
  return rows;
}

bool _sameCounts(
  List<CycleObservationTagCount> a,
  List<CycleObservationTagCount> b,
) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameWeeks(List<CycleObservationsWeek> a, List<CycleObservationsWeek> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
