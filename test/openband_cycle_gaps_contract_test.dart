import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/openband/cycle_data.dart';
import 'package:openstrap_edge/openband/cycle_gaps_data.dart';

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
  lengthReviewEnabled: true,
);

const _asOf = '2026-09-15';

const _paperStarts = [
  CycleStart(date: '2025-09-14', kind: kCycleStartKind),
  CycleStart(date: '2025-10-12', kind: kCycleStartKind),
  CycleStart(date: '2025-11-11', kind: kCycleStartKind),
  CycleStart(date: '2025-12-08', kind: kCycleStartKind),
  CycleStart(date: '2026-01-06', kind: kCycleStartKind),
  CycleStart(date: '2026-02-03', kind: kCycleStartKind),
  CycleStart(date: '2026-03-06', kind: kCycleStartKind),
  CycleStart(date: '2026-04-01', kind: kCycleStartKind),
  CycleStart(date: '2026-05-01', kind: kCycleStartKind),
  CycleStart(date: '2026-05-29', kind: kCycleStartKind),
  CycleStart(date: '2026-06-30', kind: kCycleStartKind),
  CycleStart(date: '2026-07-27', kind: kCycleStartKind),
  CycleStart(date: '2026-08-24', kind: kCycleStartKind),
];

const _paperGaps = <(String, String, int)>[
  ('2025-09-14', '2025-10-12', 28),
  ('2025-10-12', '2025-11-11', 30),
  ('2025-11-11', '2025-12-08', 27),
  ('2025-12-08', '2026-01-06', 29),
  ('2026-01-06', '2026-02-03', 28),
  ('2026-02-03', '2026-03-06', 31),
  ('2026-03-06', '2026-04-01', 26),
  ('2026-04-01', '2026-05-01', 30),
  ('2026-05-01', '2026-05-29', 28),
  ('2026-05-29', '2026-06-30', 32),
  ('2026-06-30', '2026-07-27', 27),
  ('2026-07-27', '2026-08-24', 28),
];

CycleSnapshot _snap({
  String day = _asOf,
  CycleSettings settings = _settings,
  List<CycleStart> starts = _paperStarts,
  List<CycleObservation> observations = const [],
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
  test('display minimum matches the legacy 12-gap review floor', () {
    expect(kCycleGapsDisplayMinimum, 12);
    expect(kCycleMaxObservedGapDays, 60);
  });

  test('Paper fixture is 12 closed gaps; latest 28 is 27 Jul–24 Aug', () {
    expect(cycleDiffDays('2026-08-24', '2026-09-15'), 22);
    expect([for (final g in _paperGaps) g.$3], [
      28, 30, 27, 29, 28, 31, 26, 30, 28, 32, 27, 28,
    ]);

    final summary = buildCycleGapsSummary(_snap());
    expect(summary.reason, CycleGapsReason.available);
    expect(summary.asOfDay, '2026-09-15');
    expect(summary.gaps, hasLength(12));
    expect(
      [for (final g in summary.gaps) (g.previousStart, g.nextStart, g.days)],
      _paperGaps,
    );
    expect(summary.gaps.last, const CycleObservedGap(
      previousStart: '2026-07-27',
      nextStart: '2026-08-24',
    ));
    expect(summary.gaps.last.days, 28);
    expect(
      [for (final g in summary.gaps) g.days],
      isNot(contains(22)),
    );
    expect(summary.gaps.any((g) => g.nextStart == '2026-09-15'), isFalse);
  });

  test('11 closed gaps stay insufficient; 12 become available', () {
    final eleven = buildCycleGapsSummary(
      _snap(starts: _paperStarts.sublist(0, 12)),
    );
    expect(eleven.reason, CycleGapsReason.insufficientGaps);
    expect(eleven.gaps, isEmpty);

    final twelve = buildCycleGapsSummary(_snap());
    expect(twelve.reason, CycleGapsReason.available);
    expect(twelve.gaps, hasLength(kCycleGapsDisplayMinimum));
  });

  test('tracking off and length-review off withhold independently', () {
    final tracking = buildCycleGapsSummary(
      _snap(
        settings: const CycleSettings(
          enabled: false,
          estimatesEnabled: true,
          lengthReviewEnabled: true,
        ),
      ),
    );
    expect(tracking.reason, CycleGapsReason.trackingDisabled);
    expect(tracking.gaps, isEmpty);

    final display = buildCycleGapsSummary(
      _snap(
        settings: const CycleSettings(
          enabled: true,
          estimatesEnabled: true,
          lengthReviewEnabled: false,
        ),
      ),
    );
    expect(display.reason, CycleGapsReason.displayDisabled);
    expect(display.gaps, isEmpty);

    final both = buildCycleGapsSummary(
      _snap(
        settings: const CycleSettings(
          enabled: false,
          estimatesEnabled: true,
          lengthReviewEnabled: false,
        ),
      ),
    );
    expect(both.reason, CycleGapsReason.trackingDisabled);
    expect(both.gaps, isEmpty);
  });

  test('estimates and situation do not gate historical gaps', () {
    for (final settings in const [
      CycleSettings(
        enabled: true,
        estimatesEnabled: false,
        situation: CycleSituation.none,
        lengthReviewEnabled: true,
      ),
      CycleSettings(
        enabled: true,
        estimatesEnabled: false,
        situation: CycleSituation.contraception,
        lengthReviewEnabled: true,
      ),
    ]) {
      final summary = buildCycleGapsSummary(_snap(settings: settings));
      expect(summary.reason, CycleGapsReason.available);
      expect(summary.gaps, hasLength(12));
    }
  });

  test('no starts and one start are insufficient, not a zero-day bar', () {
    final none = buildCycleGapsSummary(_snap(starts: const []));
    expect(none.reason, CycleGapsReason.insufficientGaps);
    expect(none.gaps, isEmpty);

    final one = buildCycleGapsSummary(
      _snap(
        starts: const [
          CycleStart(date: '2026-08-24', kind: kCycleStartKind),
        ],
      ),
    );
    expect(one.reason, CycleGapsReason.insufficientGaps);
    expect(one.gaps, isEmpty);
    expect(one.gaps.any((g) => g.days == 0), isFalse);
  });

  test('as-of drops a later start and does not close the last interval', () {
    final later = [
      ..._paperStarts,
      const CycleStart(date: '2026-09-20', kind: kCycleStartKind),
    ];
    final asOf = buildCycleGapsSummary(_snap(starts: later));
    expect(asOf.reason, CycleGapsReason.available);
    expect(asOf.gaps, hasLength(12));
    expect(asOf.gaps.last.nextStart, '2026-08-24');
    expect(asOf.gaps.any((g) => g.nextStart == '2026-09-20'), isFalse);
    expect(asOf.gaps.any((g) => g.nextStart == '2026-09-15'), isFalse);

    final beforeLast = buildCycleGapsSummary(
      _snap(day: '2026-08-01', starts: later),
    );
    expect(beforeLast.reason, CycleGapsReason.insufficientGaps);
    expect(beforeLast.gaps, isEmpty);
    expect(cycleDiffDays('2026-07-27', '2026-08-01'), 5);
  });

  test('a 60-day gap is kept; 61 withholds the whole chart', () {
    const prefix = [
      CycleStart(date: '2025-08-04', kind: kCycleStartKind),
      CycleStart(date: '2025-09-01', kind: kCycleStartKind),
      CycleStart(date: '2025-09-29', kind: kCycleStartKind),
      CycleStart(date: '2025-10-27', kind: kCycleStartKind),
      CycleStart(date: '2025-11-24', kind: kCycleStartKind),
      CycleStart(date: '2025-12-22', kind: kCycleStartKind),
      CycleStart(date: '2026-01-19', kind: kCycleStartKind),
      CycleStart(date: '2026-02-16', kind: kCycleStartKind),
      CycleStart(date: '2026-03-16', kind: kCycleStartKind),
      CycleStart(date: '2026-04-13', kind: kCycleStartKind),
      CycleStart(date: '2026-05-11', kind: kCycleStartKind),
    ];
    expect(cycleDiffDays('2026-06-01', '2026-07-31'), 60);
    final sixty = buildCycleGapsSummary(
      _snap(
        starts: [
          ...prefix,
          const CycleStart(date: '2026-06-01', kind: kCycleStartKind),
          const CycleStart(date: '2026-07-31', kind: kCycleStartKind),
        ],
      ),
    );
    expect(sixty.reason, CycleGapsReason.available);
    expect(sixty.gaps, hasLength(12));
    expect(sixty.gaps.last.days, 60);
    expect(sixty.gaps.last.previousStart, '2026-06-01');
    expect(sixty.gaps.last.nextStart, '2026-07-31');

    expect(cycleDiffDays('2026-06-01', '2026-08-01'), 61);
    final sixtyOne = buildCycleGapsSummary(
      _snap(
        starts: [
          ...prefix,
          const CycleStart(date: '2026-06-01', kind: kCycleStartKind),
          const CycleStart(date: '2026-08-01', kind: kCycleStartKind),
        ],
      ),
    );
    expect(sixtyOne.reason, CycleGapsReason.longGap);
    expect(sixtyOne.gaps, isEmpty);
  });

  test('unsorted input and non-start kinds still use contributing as-of starts',
      () {
    final mixed = [
      const CycleStart(date: '2026-09-20', kind: kCycleStartKind),
      const CycleStart(date: '2025-08-01', kind: 'spotting'),
      ..._paperStarts.reversed,
      const CycleStart(date: '2026-07-27', kind: 'note'),
    ];
    final summary = buildCycleGapsSummary(_snap(starts: mixed));
    expect(summary.reason, CycleGapsReason.available);
    expect(
      [for (final g in summary.gaps) (g.previousStart, g.nextStart, g.days)],
      _paperGaps,
    );
  });

  test('duplicate contributing dates withhold as unreadable, not a 0-day bar',
      () {
    final summary = buildCycleGapsSummary(
      _snap(
        starts: [
          ..._paperStarts,
          const CycleStart(
            date: '2026-08-24',
            kind: kCycleStartKind,
            note: 'other origin',
          ),
        ],
      ),
    );
    expect(summary.reason, CycleGapsReason.unreadableStarts);
    expect(summary.gaps, isEmpty);
    expect(summary.gaps.any((g) => g.days == 0), isFalse);
  });

  test('unreadable starts withhold; observation-only partial still projects',
      () {
    final unreadable = buildCycleGapsSummary(
      _snap(unreadableStarts: true, unreadableCount: 1),
    );
    expect(unreadable.reason, CycleGapsReason.unreadableStarts);
    expect(unreadable.gaps, isEmpty);

    final observationsOnly = buildCycleGapsSummary(
      _snap(unreadableCount: 2),
    );
    expect(observationsOnly.reason, CycleGapsReason.available);
    expect(observationsOnly.gaps, hasLength(12));
    expect(observationsOnly.gaps.last.days, 28);
  });

  test('all gaps are returned; there is no history cap', () {
    final extra = [
      ..._paperStarts,
      const CycleStart(date: '2026-09-15', kind: kCycleStartKind),
    ];
    expect(cycleDiffDays('2026-08-24', '2026-09-15'), 22);
    final summary = buildCycleGapsSummary(_snap(starts: extra));
    expect(summary.reason, CycleGapsReason.available);
    expect(summary.gaps, hasLength(13));
    expect(summary.gaps.first.previousStart, '2025-09-14');
    expect(summary.gaps.last, const CycleObservedGap(
      previousStart: '2026-08-24',
      nextStart: '2026-09-15',
    ));
    expect(summary.gaps.last.days, 22);
  });

  test(
    'civil spring and fall DST under America/Los_Angeles and Europe',
    () {
      final originalTz = Platform.environment['TZ'];
      addTearDown(() => _setProcessTz(originalTz));

      _setProcessTz('America/Los_Angeles');
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
            'gaps must not use that arithmetic',
      );
      expect(cycleDiffDays('2026-03-08', '2026-03-09'), 1);
      expect(cycleDiffDays('2026-11-01', '2026-11-02'), 1);

      _setProcessTz('Europe/Berlin');
      expect(DateTime(2026, 3, 29).timeZoneOffset, const Duration(hours: 1));
      expect(DateTime(2026, 3, 30).timeZoneOffset, const Duration(hours: 2));
      expect(DateTime(2026, 10, 25).timeZoneOffset, const Duration(hours: 2));
      expect(DateTime(2026, 10, 26).timeZoneOffset, const Duration(hours: 1));
      expect(cycleDiffDays('2026-03-29', '2026-03-30'), 1);
      expect(cycleDiffDays('2026-10-25', '2026-10-26'), 1);
      expect(cycleDiffDays('2026-03-28', '2026-03-30'), 2);

      expect(cycleDiffDays('2026-03-01', '2026-03-29'), 28);
      expect(cycleDiffDays('2026-10-11', '2026-11-08'), 28);
      final summary = buildCycleGapsSummary(
        _snap(
          day: '2026-12-20',
          starts: const [
            CycleStart(date: '2026-01-04', kind: kCycleStartKind),
            CycleStart(date: '2026-02-01', kind: kCycleStartKind),
            CycleStart(date: '2026-03-01', kind: kCycleStartKind),
            CycleStart(date: '2026-03-29', kind: kCycleStartKind),
            CycleStart(date: '2026-04-26', kind: kCycleStartKind),
            CycleStart(date: '2026-05-24', kind: kCycleStartKind),
            CycleStart(date: '2026-06-21', kind: kCycleStartKind),
            CycleStart(date: '2026-07-19', kind: kCycleStartKind),
            CycleStart(date: '2026-08-16', kind: kCycleStartKind),
            CycleStart(date: '2026-09-13', kind: kCycleStartKind),
            CycleStart(date: '2026-10-11', kind: kCycleStartKind),
            CycleStart(date: '2026-11-08', kind: kCycleStartKind),
            CycleStart(date: '2026-12-06', kind: kCycleStartKind),
          ],
        ),
      );
      expect(summary.reason, CycleGapsReason.available);
      expect(summary.gaps, hasLength(12));
      expect([for (final g in summary.gaps) g.days], everyElement(28));
      expect(summary.gaps[2], const CycleObservedGap(
        previousStart: '2026-03-01',
        nextStart: '2026-03-29',
      ));
      expect(summary.gaps[10], const CycleObservedGap(
        previousStart: '2026-10-11',
        nextStart: '2026-11-08',
      ));
    },
    skip: Platform.isWindows ? 'POSIX setenv/tzset only' : null,
  );

  test('output gaps are immutable and input starts are not sorted in place', () {
    final starts = [..._paperStarts.reversed];
    final snapshot = CycleSnapshot(
      day: _asOf,
      settings: _settings,
      starts: starts,
    );
    final summary = buildCycleGapsSummary(snapshot);
    expect(summary.reason, CycleGapsReason.available);
    expect(summary.gaps, hasLength(12));
    expect(starts.first.date, '2026-08-24');
    expect(starts.last.date, '2025-09-14');
    expect(identical(summary.gaps, starts), isFalse);
    expect(
      () => summary.gaps.add(
        const CycleObservedGap(
          previousStart: '2026-08-24',
          nextStart: '2026-09-15',
        ),
      ),
      throwsUnsupportedError,
    );
  });
}
