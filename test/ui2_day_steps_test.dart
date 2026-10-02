// THE DAY STEPS SCREEN — the spans, and the one line about the sensors.
//
// Three things this screen may not get wrong, all of them honesty rather than
// layout:
//   * a stretch names the device that counted it, and never the wrong one;
//   * the accuracy line appears ONCE and says the right thing for the sensors
//     that actually counted — a day the phone carried alone must not be told
//     about wrists;
//   * a day whose count came off the strap's on-chip counter has no times
//     behind it, and must say THAT rather than "no steps" over a tile showing
//     thousands.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/day_steps.dart';

/// Local 09:00 on an arbitrary day, as epoch seconds.
final _nine = DateTime(2026, 8, 17, 9).millisecondsSinceEpoch ~/ 1000;

DayStepSpan _span(
  int fromMin,
  int toMin,
  int steps, {
  bool band = false,
  String? activity,
}) => DayStepSpan(
  startTs: _nine + fromMin * 60,
  endTs: _nine + toMin * 60,
  steps: steps,
  fromBand: band,
  activity: activity,
);

void main() {
  test('contiguous hours from one sensor read as one stretch — but never '
      'across a gap, and never across the other sensor', () {
    // whoop-4.db, 2026-08-13, exactly as the table holds it: hourly phone rows
    // with an 11:00 gap, and the strap's run spans landing inside 17:00–19:00.
    final rows = [
      _span(0, 60, 892), // 09:00–10:00  (the fixture's clock, not the day's)
      _span(60, 120, 9),
      _span(120, 180, 1012),
      _span(240, 300, 228), // one hour missing before this one
      _span(480, 540, 1649),
      _span(532, 534, 51, band: true),
      _span(534, 540, 737, band: true, activity: 'run'),
      _span(540, 600, 5753),
      _span(541, 544, 352, band: true, activity: 'run'),
      _span(600, 660, 214),
      _span(660, 720, 2074),
    ];
    final merged = mergeAdjacent(rows);
    expect(merged.map((s) => (s.startTs - _nine, s.endTs - _nine, s.steps)), [
      (0, 180 * 60, 1913), // three contiguous phone hours, joined
      (240 * 60, 300 * 60, 228), // the gap kept it separate
      (480 * 60, 540 * 60, 1649), // a band stretch starts inside the next
      (532 * 60, 534 * 60, 51),
      (534 * 60, 540 * 60, 737),
      (540 * 60, 600 * 60, 5753),
      (541 * 60, 544 * 60, 352),
      (600 * 60, 720 * 60, 2288),
    ]);
  });

  test('an hour gets one bar, in the colour of the sensor that counted most '
      'of it', () {
    // 09:00–10:00 phone (600), with a strap walk 09:10–09:40 (900) inside it.
    final (band, phone) = hourlySteps([
      _span(0, 60, 600),
      _span(10, 40, 900, band: true),
    ]);
    expect(
      band[9],
      closeTo(1500, .5),
      reason: 'the hour still shows every step counted in it',
    );
    expect(
      phone[9],
      isNull,
      reason: 'two bars would hide one behind the other',
    );
    expect(band[10], isNull, reason: 'an uncovered hour is a hole, not a zero');
  });
}
