import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/openband/cycle_data.dart';
import 'package:openstrap_edge/openband/cycle_observations_data.dart';

typedef _SetenvNative = Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32);
typedef _SetenvDart = int Function(Pointer<Utf8>, Pointer<Utf8>, int);
typedef _UnsetenvNative = Int32 Function(Pointer<Utf8>);
typedef _UnsetenvDart = int Function(Pointer<Utf8>);
typedef _TzsetNative = Void Function();
typedef _TzsetDart = void Function();

void _setProcessTz(String? tz) {
  final lib = DynamicLibrary.process();
  final key = 'TZ'.toNativeUtf8();
  try {
    if (tz == null) {
      lib.lookupFunction<_UnsetenvNative, _UnsetenvDart>('unsetenv')(key);
    } else {
      final value = tz.toNativeUtf8();
      lib.lookupFunction<_SetenvNative, _SetenvDart>('setenv')(key, value, 1);
      calloc.free(value);
    }
    lib.lookupFunction<_TzsetNative, _TzsetDart>('tzset')();
  } finally {
    calloc.free(key);
  }
}

const _settings = CycleSettings(
  enabled: true,
  estimatesEnabled: true,
  lengthReviewEnabled: false,
);

const _asOf = '2026-09-15';

const _paperStarts = [
  CycleStart(date: '2026-06-01', kind: kCycleStartKind),
  CycleStart(date: '2026-06-29', kind: kCycleStartKind),
  CycleStart(date: '2026-07-31', kind: kCycleStartKind),
  CycleStart(date: '2026-08-24', kind: kCycleStartKind),
];

const _week1Observations = [
  CycleObservation(date: '2026-06-01', tags: ['cramps', 'fatigue']),
  CycleObservation(date: '2026-06-03', tags: ['cramps']),
  CycleObservation(date: '2026-06-29', tags: ['cramps', 'headache']),
  CycleObservation(date: '2026-07-02', tags: ['fatigue']),
  CycleObservation(date: '2026-07-31', tags: ['cramps']),
  CycleObservation(date: '2026-08-02', tags: ['fatigue']),
  CycleObservation(date: '2026-08-24', tags: ['headache']),
  CycleObservation(date: '2026-08-25', tags: ['bloating']),
];

CycleSnapshot _snap({
  String day = _asOf,
  CycleSettings settings = _settings,
  List<CycleStart> starts = _paperStarts,
  List<CycleObservation> observations = _week1Observations,
  int unreadableCount = 0,
  bool unreadableStarts = false,
}) {
  return buildCycleSnapshot(
    day: day,
    settings: settings,
    starts: starts,
    observations: observations,
    unreadableCount: unreadableCount,
    unreadableStarts: unreadableStarts,
  );
}

void main() {
  test('Paper week 1 is 8 tagged days across 4 cycles, 1 Jun–15 Sep', () {
    // Independent of the grouping function: 06-01→06-28 = 28d, 06-29→07-30 = 32d,
    // 07-31→08-23 = 24d, 08-24→09-15 open = 23d. Max 32d ⇒ 5 week windows.
    expect(cycleDiffDays('2026-06-01', '2026-06-28') + 1, 28);
    expect(cycleDiffDays('2026-06-29', '2026-07-30') + 1, 32);
    expect(cycleDiffDays('2026-07-31', '2026-08-23') + 1, 24);
    expect(cycleDiffDays('2026-08-24', '2026-09-15') + 1, 23);

    final summary = buildCycleObservationsSummary(_snap());
    expect(summary.availability, CycleObservationsAvailability.available);
    expect(summary.reason, CycleObservationsReason.available);
    expect(summary.asOfDay, '2026-09-15');
    expect(summary.firstStartDay, '2026-06-01');
    expect(summary.cycleCount, 4);
    expect(summary.unreadableCount, 0);
    expect(summary.partial, isFalse);
    expect(summary.weeks, hasLength(5));
    expect(
      [for (final w in summary.weeks) (w.fromCycleDay, w.toCycleDay)],
      [(1, 7), (8, 14), (15, 21), (22, 28), (29, 35)],
    );

    final week1 = summary.weeks.first;
    expect(week1.taggedDays, 8);
    expect(week1.counts, [
      const CycleObservationTagCount(tag: 'cramps', count: 4),
      const CycleObservationTagCount(tag: 'fatigue', count: 3),
      const CycleObservationTagCount(tag: 'headache', count: 2),
      const CycleObservationTagCount(tag: 'bloating', count: 1),
    ]);
    expect(
      [for (final w in summary.weeks.skip(1)) w.taggedDays],
      [0, 0, 0, 0],
    );
    expect(
      [for (final w in summary.weeks.skip(1)) w.counts],
      [isEmpty, isEmpty, isEmpty, isEmpty],
    );
  });

  test('day 30 nausea is week 5, not week 4; note-only 07-29 is excluded', () {
    expect(cycleDiffDays('2026-06-29', '2026-07-28') + 1, 30);
    expect(cycleDiffDays('2026-06-29', '2026-07-29') + 1, 31);
    final summary = buildCycleObservationsSummary(
      _snap(
        observations: [
          ..._week1Observations,
          const CycleObservation(date: '2026-07-28', tags: ['nausea']),
          const CycleObservation(
            date: '2026-07-29',
            tags: [],
            note: 'felt off',
          ),
        ],
      ),
    );
    expect(summary.weeks, hasLength(5));
    expect(summary.weeks[3].fromCycleDay, 22);
    expect(summary.weeks[3].toCycleDay, 28);
    expect(summary.weeks[3].taggedDays, 0);
    expect(summary.weeks[3].counts, isEmpty);
    expect(summary.weeks[4].fromCycleDay, 29);
    expect(summary.weeks[4].toCycleDay, 35);
    expect(summary.weeks[4].taggedDays, 1);
    expect(summary.weeks[4].counts, [
      const CycleObservationTagCount(tag: 'nausea', count: 1),
    ]);
    expect(summary.weeks.first.taggedDays, 8);
  });

  test('open vs closed bounds use the nearest preceding contributing start', () {
    final summary = buildCycleObservationsSummary(
      _snap(
        observations: const [
          CycleObservation(date: '2026-08-23', tags: ['closed-end']),
          CycleObservation(date: '2026-08-24', tags: ['open-start']),
          CycleObservation(date: '2026-09-07', tags: ['open-week3']),
          CycleObservation(date: '2026-09-15', tags: ['as-of']),
        ],
      ),
    );
    expect(cycleDiffDays('2026-07-31', '2026-08-23') + 1, 24);
    expect(cycleDiffDays('2026-08-24', '2026-08-24') + 1, 1);
    expect(cycleDiffDays('2026-08-24', '2026-09-07') + 1, 15);
    expect(cycleDiffDays('2026-08-24', '2026-09-15') + 1, 23);
    expect(summary.weeks.first.counts, [
      const CycleObservationTagCount(tag: 'open-start', count: 1),
    ]);
    expect(summary.weeks[2].counts, [
      const CycleObservationTagCount(tag: 'open-week3', count: 1),
    ]);
    expect(summary.weeks[3].fromCycleDay, 22);
    expect(summary.weeks[3].counts.map((c) => c.tag).toList()..sort(), [
      'as-of',
      'closed-end',
    ]);
    expect(summary.weeks[3].taggedDays, 2);
    expect(summary.cycleCount, 4);
  });

  test('future, before-first, and non-start rows do not contribute', () {
    final summary = buildCycleObservationsSummary(
      CycleSnapshot(
        day: _asOf,
        settings: _settings,
        starts: const [
          CycleStart(date: '2026-05-20', kind: 'spotting'),
          ..._paperStarts,
          CycleStart(date: '2026-09-20', kind: kCycleStartKind),
        ],
        observations: const [
          CycleObservation(date: '2026-05-20', tags: ['before']),
          CycleObservation(date: '2026-05-31', tags: ['before-first']),
          CycleObservation(date: '2026-09-16', tags: ['future']),
          CycleObservation(date: '2026-09-20', tags: ['future-start-day']),
          CycleObservation(date: '2026-06-01', tags: ['cramps']),
        ],
      ),
    );
    expect(summary.cycleCount, 4);
    expect(summary.firstStartDay, '2026-06-01');
    expect(summary.weeks.first.taggedDays, 1);
    expect(summary.weeks.first.counts, [
      const CycleObservationTagCount(tag: 'cramps', count: 1),
    ]);
    expect(
      [
        for (final w in summary.weeks)
          ...w.counts.map((c) => c.tag),
      ],
      ['cramps'],
    );
  });

  test('note-only, empty, and duplicate same-day tags; unknown tag kept', () {
    final summary = buildCycleObservationsSummary(
      _snap(
        observations: const [
          CycleObservation(date: '2026-06-01', tags: [], note: 'only a note'),
          CycleObservation(date: '2026-06-02', tags: []),
          CycleObservation(
            date: '2026-06-03',
            tags: ['cramps', 'cramps', 'fatigue'],
          ),
          CycleObservation(date: '2026-06-04', tags: ['mystery-spot']),
          CycleObservation(date: '2026-06-05', tags: ['fatigue', 'cramps']),
        ],
      ),
    );
    final week1 = summary.weeks.first;
    expect(week1.taggedDays, 3);
    expect(week1.counts, [
      const CycleObservationTagCount(tag: 'cramps', count: 2),
      const CycleObservationTagCount(tag: 'fatigue', count: 2),
      const CycleObservationTagCount(tag: 'mystery-spot', count: 1),
    ]);
  });

  test('overlapping same-date rows count each tag once', () {
    final summary = buildCycleObservationsSummary(
      _snap(
        observations: const [
          CycleObservation(date: '2026-06-01', tags: ['cramps', 'fatigue']),
          CycleObservation(date: '2026-06-01', tags: ['cramps', 'headache']),
        ],
      ),
    );
    final week1 = summary.weeks.first;
    expect(week1.taggedDays, 1);
    expect(week1.counts, [
      const CycleObservationTagCount(tag: 'cramps', count: 1),
      const CycleObservationTagCount(tag: 'fatigue', count: 1),
      const CycleObservationTagCount(tag: 'headache', count: 1),
    ]);
    expect(
      [for (final c in week1.counts) c.count],
      everyElement(lessThanOrEqualTo(week1.taggedDays)),
    );
  });

  test('tag ties sort by raw tag; never-seen tags are omitted', () {
    final summary = buildCycleObservationsSummary(
      _snap(
        observations: const [
          CycleObservation(date: '2026-06-01', tags: ['zzz', 'aaa']),
          CycleObservation(date: '2026-06-02', tags: ['aaa']),
        ],
      ),
    );
    expect(summary.weeks.first.counts, [
      const CycleObservationTagCount(tag: 'aaa', count: 2),
      const CycleObservationTagCount(tag: 'zzz', count: 1),
    ]);
    expect(
      [for (final c in summary.weeks.first.counts) c.tag],
      isNot(contains('cramps')),
    );
  });

  test('disabled, unreadable starts, and <3 starts stay distinct', () {
    final disabled = buildCycleObservationsSummary(
      _snap(
        settings: const CycleSettings(
          enabled: false,
          estimatesEnabled: true,
          lengthReviewEnabled: false,
        ),
      ),
    );
    expect(disabled.availability, CycleObservationsAvailability.withheld);
    expect(disabled.reason, CycleObservationsReason.trackingDisabled);
    expect(disabled.weeks, isEmpty);
    expect(disabled.cycleCount, 0);
    expect(disabled.firstStartDay, isNull);

    final unreadable = buildCycleObservationsSummary(
      _snap(unreadableStarts: true, unreadableCount: 1),
    );
    expect(unreadable.availability, CycleObservationsAvailability.withheld);
    expect(unreadable.reason, CycleObservationsReason.unreadableStarts);
    expect(unreadable.weeks, isEmpty);
    expect(unreadable.unreadableCount, 1);
    expect(unreadable.partial, isTrue);

    final two = buildCycleObservationsSummary(
      _snap(
        starts: const [
          CycleStart(date: '2026-08-24', kind: kCycleStartKind),
          CycleStart(date: '2026-07-31', kind: kCycleStartKind),
        ],
      ),
    );
    expect(two.availability, CycleObservationsAvailability.missing);
    expect(two.reason, CycleObservationsReason.insufficientStarts);
    expect(two.weeks, isEmpty);

    final none = buildCycleObservationsSummary(_snap(starts: const []));
    expect(none.reason, CycleObservationsReason.insufficientStarts);
    expect(none.weeks, isEmpty);

    final disabledWins = buildCycleObservationsSummary(
      _snap(
        settings: const CycleSettings(
          enabled: false,
          estimatesEnabled: false,
          lengthReviewEnabled: false,
        ),
        unreadableStarts: true,
        unreadableCount: 2,
        starts: const [
          CycleStart(date: '2026-08-24', kind: kCycleStartKind),
        ],
      ),
    );
    expect(disabledWins.reason, CycleObservationsReason.trackingDisabled);

    final estimatesOff = buildCycleObservationsSummary(
      _snap(
        settings: const CycleSettings(
          enabled: true,
          estimatesEnabled: false,
          situation: CycleSituation.none,
          lengthReviewEnabled: false,
        ),
      ),
    );
    expect(estimatesOff.reason, CycleObservationsReason.available);
    expect(estimatesOff.weeks, isNotEmpty);
  });

  test('readable sibling observations still count when others are unreadable',
      () {
    final summary = buildCycleObservationsSummary(
      _snap(unreadableCount: 2),
    );
    expect(summary.availability, CycleObservationsAvailability.available);
    expect(summary.partial, isTrue);
    expect(summary.unreadableCount, 2);
    expect(summary.weeks.first.taggedDays, 8);
    expect(summary.weeks.first.counts.first, const CycleObservationTagCount(
      tag: 'cramps',
      count: 4,
    ));
  });

  test('unsorted starts still group from the nearest predecessor', () {
    final summary = buildCycleObservationsSummary(
      _snap(
        starts: _paperStarts.reversed.toList(),
        observations: const [
          CycleObservation(date: '2026-07-02', tags: ['fatigue']),
        ],
      ),
    );
    expect(cycleDiffDays('2026-06-29', '2026-07-02') + 1, 4);
    expect(summary.cycleCount, 4);
    expect(summary.weeks.first.counts, [
      const CycleObservationTagCount(tag: 'fatigue', count: 1),
    ]);
    expect(summary.weeks.first.taggedDays, 1);
  });

  test('long gaps keep logged-start day counts and do not clamp into week 4',
      () {
    expect(cycleDiffDays('2026-01-01', '2026-02-20') + 1, 51);
    final summary = buildCycleObservationsSummary(
      _snap(
        day: '2026-06-15',
        starts: const [
          CycleStart(date: '2026-01-01', kind: kCycleStartKind),
          CycleStart(date: '2026-03-01', kind: kCycleStartKind),
          CycleStart(date: '2026-06-01', kind: kCycleStartKind),
        ],
        observations: const [
          CycleObservation(date: '2026-02-20', tags: ['gap']),
        ],
      ),
    );
    expect(summary.weeks.length, greaterThan(4));
    expect(summary.weeks[3].fromCycleDay, 22);
    expect(summary.weeks[3].toCycleDay, 28);
    expect(summary.weeks[3].counts, isEmpty);
    expect(summary.weeks[7].fromCycleDay, 50);
    expect(summary.weeks[7].toCycleDay, 56);
    expect(summary.weeks[7].counts, [
      const CycleObservationTagCount(tag: 'gap', count: 1),
    ]);
  });

  test(
    'civil spring and fall DST under America/Los_Angeles keep week bounds',
    () {
    final originalTz = Platform.environment['TZ'];
    _setProcessTz('America/Los_Angeles');
    addTearDown(() => _setProcessTz(originalTz));

    expect(
      DateTime(2026, 3, 8).timeZoneOffset,
      const Duration(hours: -8),
      reason: 'setenv(TZ)+tzset() did not re-home to America/Los_Angeles',
    );
    final fallLocal = DateTime(2026, 11, 1);
    expect(fallLocal.timeZoneOffset, const Duration(hours: -7));
    expect(
      fallLocal.add(const Duration(days: 1)).day,
      1,
      reason: 'local +24h on the 25h fall-back day stays on Nov 1; '
          'grouping must not use that arithmetic',
    );

    expect(cycleAddDays('2026-03-08', 1), '2026-03-09');
    expect(cycleAddDays('2026-11-01', 1), '2026-11-02');
    expect(cycleDiffDays('2026-03-02', '2026-03-08') + 1, 7);
    expect(cycleDiffDays('2026-03-02', '2026-03-09') + 1, 8);
    expect(cycleDiffDays('2026-10-26', '2026-11-01') + 1, 7);
    expect(cycleDiffDays('2026-10-26', '2026-11-02') + 1, 8);

    final summary = buildCycleObservationsSummary(
      _snap(
        day: '2026-11-08',
        starts: const [
          CycleStart(date: '2026-03-02', kind: kCycleStartKind),
          CycleStart(date: '2026-03-16', kind: kCycleStartKind),
          CycleStart(date: '2026-10-26', kind: kCycleStartKind),
        ],
        observations: const [
          CycleObservation(date: '2026-03-08', tags: ['spring-day7']),
          CycleObservation(date: '2026-03-09', tags: ['spring-day8']),
          CycleObservation(date: '2026-11-01', tags: ['fall-day7']),
          CycleObservation(date: '2026-11-02', tags: ['fall-day8']),
        ],
      ),
    );
    expect(summary.weeks.first.counts.map((c) => c.tag).toList()..sort(), [
      'fall-day7',
      'spring-day7',
    ]);
    expect(summary.weeks[1].counts.map((c) => c.tag).toList()..sort(), [
      'fall-day8',
      'spring-day8',
    ]);
  },
    skip: Platform.isWindows ? 'POSIX setenv/tzset only' : null,
  );
}
