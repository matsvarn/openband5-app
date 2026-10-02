// R2 wiring regressions — the numbers the screens were reading wrong.
//
// Each group below pins one bug that shipped, so the fix cannot quietly come
// undone:
//
//  · the cross-day rollup was served VERBATIM, with no version and no date, so
//    every readiness driver, the sleep coach and the body clock could be weeks
//    old under an older algorithm with nothing on screen to say so;
//  · chart points lost their timestamps, so "Today" and "N days ago" were
//    counted off the ARRAY INDEX and a sync gap read as continuous;
//  · the sleep trend captioned itself "vs your need" while subtracting the
//    28-day average;
//  · "days with a derived record in the last month" counted every derived day
//    since install, so anyone past their first month read "30 of 30".

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/local_repository.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/ui2/screens/screens.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

int _noon(int back) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day - back, 12).millisecondsSinceEpoch ~/
      1000;
}

String _day(int back) {
  final n = DateTime.now();
  return dayLabelOf(DateTime(n.year, n.month, n.day - back));
}

class _FakeRepo extends LocalRepository {
  final Map<String, dynamic> insights = const {};
  final List<String> days = const [];
  final Map<String, dynamic> today;

  /// day id -> the `daytime_hrv` block `getDayHeart` serves for it.
  final Map<String, Map<String, dynamic>> daytimeHrv = const {};

  _FakeRepo({this.today = const {}});

  @override
  Future<Map<String, dynamic>> getDayHeart(String date) async => {
    'daytime_hrv': ?daytimeHrv[date],
  };
  @override
  Future<Map<String, dynamic>> getDaySleepV2(String date) async => const {};

  @override
  Future<Map<String, dynamic>> getToday() async => today;
  @override
  Future<Map<String, dynamic>> getInsights() async => insights;
  @override
  Future<Map<String, dynamic>> getProfile() async => const {};
  @override
  Future<List<String>> availableDays() async => days;
  @override
  Future<Map<String, dynamic>> getChart(
    String metric, {
    int? from,
    int? to,
    Set<String> signals = const {},
  }) async => const {'points': []};
  // Health reads the wear block for the night's off-wrist stretches and the
  // day's naps. Absent here on purpose: an empty map is "we never looked",
  // which is what a fake with no fixture is.
  @override
  Future<Map<String, dynamic>> getDayWear(String date) async => const {};
  @override
  Future<Map<String, dynamic>> getDayNaps(String date) async => const {};
}

void main() {
  // ── the artifact behind four screens ──
  group('crossDayStaleReason', () {
    Map<String, dynamic> artifact({int? version, String? builtFor}) => {
      'algo_version': version ?? kAlgoVersion,
      'built_for_day': ?builtFor,
      'readiness_glassbox': const {'drivers': []},
    };

    test('an artifact stamped with today and this algo version is served', () {
      expect(
        LocalRepositoryImpl.crossDayStaleReason(
          artifact(builtFor: _day(0)),
          _day(0),
        ),
        isNull,
      );
    });

    test('yesterday is still fine — the families are multi-day by design', () {
      expect(
        LocalRepositoryImpl.crossDayStaleReason(
          artifact(builtFor: _day(1)),
          _day(0),
        ),
        isNull,
      );
    });

    test(
      'past the age ceiling it is withheld, with the day it was built for',
      () {
        final r = LocalRepositoryImpl.crossDayStaleReason(
          artifact(builtFor: _day(LocalRepositoryImpl.crossDayMaxAgeDays + 1)),
          _day(0),
        );
        expect(r?['kind'], 'stale');
        expect(
          r?['built_for_day'],
          _day(LocalRepositoryImpl.crossDayMaxAgeDays + 1),
        );
      },
    );

    test('an OLDER algo version is withheld however fresh the day', () {
      // The sharp case: a bump that changes the bundle SHAPE would otherwise be
      // served from the pre-bump artifact for the rest of the day, and the new
      // family silently sees nothing on the very pass the bump existed for.
      final r = LocalRepositoryImpl.crossDayStaleReason(
        artifact(version: kAlgoVersion - 1, builtFor: _day(0)),
        _day(0),
      );
      expect(r?['kind'], 'algo_version');
    });

    test('an UNSTAMPED artifact cannot be shown to be fresh, so it is not', () {
      expect(
        LocalRepositoryImpl.crossDayStaleReason(
          artifact(builtFor: null),
          _day(0),
        )?['kind'],
        'unstamped',
      );
      expect(
        LocalRepositoryImpl.crossDayStaleReason({
          'readiness_glassbox': const {},
        }, _day(0))?['kind'],
        'algo_version',
      );
    });

    test('a day in the FUTURE is a clock that moved, not freshness', () {
      final n = DateTime.now();
      final ahead = dayLabelOf(DateTime(n.year, n.month, n.day + 40));
      expect(
        LocalRepositoryImpl.crossDayStaleReason(
          artifact(builtFor: ahead),
          _day(0),
        )?['kind'],
        'stale',
      );
    });
  });

  // ── the seam that dropped `t` ──
  group('chart points keep their date', () {
    test('pointsOf carries t through; seriesOf is still values-only', () {
      final chart = {
        'points': [
          {'t': _noon(2), 'v': 51},
          {'t': _noon(0), 'v': 54.5},
        ],
      };
      expect(pointsOf(chart).map((e) => e.v).toList(), [51.0, 54.5]);
      expect(pointsOf(chart).last.t, _noon(0));
      expect(seriesOf(chart), [51.0, 54.5]);
    });

    test('a point with no timestamp is not a dated point', () {
      expect(
        pointsOf({
          'points': [
            {'v': 51},
          ],
        }),
        isEmpty,
      );
    });

    test('a gap is a HOLE, not a shorter line', () {
      // The bug in one assertion: three stored points spread over seven days
      // used to be drawn as three evenly spaced samples, and the line ran
      // straight through the four missing days as though they were measured.
      final dense = denseDays([
        (t: _noon(6), v: 50.0),
        (t: _noon(2), v: 54.0),
        (t: _noon(0), v: 52.0),
      ], 7);
      expect(dense, [50.0, null, null, null, 54.0, null, 52.0]);
      expect(dense.length, 7);
    });

    test('a point outside the window is dropped, not clamped into it', () {
      expect(denseDays([(t: _noon(40), v: 50.0)], 7), List.filled(7, null));
    });

    test('the label counts REAL days, not array positions', () {
      // Two stored points a fortnight apart. Labelling off the index called the
      // older one "1 day ago" and the newer one "Today" whatever their dates.
      expect(axisDay(_noon(0)), 'Today');
      expect(axisDay(_noon(0), todayWord: 'Last night'), 'Last night');
      expect(axisDay(_noon(14)), '14 days ago');
      expect(axisDay(_noon(14), unitWord: 'nights'), '14 nights ago');
      expect(axisDay(null), '');
      expect(daysBehind(_noon(3)), 3);
    });

    test('a day is a calendar day, DST boundary or not', () {
      // Spring forward, America/New_York: local midnight on the 8th to local
      // midnight on the 10th is 47 hours, and `inDays` truncated that to ONE.
      // `denseDays` then wrote the 8th and the 9th into the same slot and the
      // older of the two vanished.
      //
      // These assertions are exact in every zone; they only had teeth in a
      // DST one, which is where the bug was reproduced.
      expect(
        calendarDaysBetween(
          DateTime(2026, 3, 8, 23, 59),
          DateTime(2026, 3, 10, 0, 1),
        ),
        2,
      );
      expect(
        calendarDaysBetween(DateTime(2026, 3, 9), DateTime(2026, 3, 10)),
        1,
      );
      // Autumn back, the 25-hour day.
      expect(
        calendarDaysBetween(DateTime(2026, 11, 1), DateTime(2026, 11, 2)),
        1,
      );
      // Time of day never counts: one minute before midnight and one minute
      // after are a whole day apart, not zero.
      expect(
        calendarDaysBetween(
          DateTime(2026, 6, 1, 23, 59),
          DateTime(2026, 6, 2, 0, 1),
        ),
        1,
      );
    });
  });

  // ── an older night is not today's number ──
  //
  // This used to say the opposite: getToday holds the last scored night over
  // until today's settles, and Home printed it with one sentence naming the
  // night. On a phone the sentence loses — a figure in the today slot reads as
  // today's, so a morning the strap was never worn showed last week's sleep as
  // this morning's. The numbers stop at the loader now and the reason travels
  // in their place.
  group('held-over overnight', () {
    Map<String, dynamic> bundle(String state, {bool prior = true}) => {
      'status': {
        'today_day': '2026-05-20',
        'overnight_state': state,
        'overnight_day': '2026-05-16',
        'showing_prior_overnight': prior,
      },
      'daily': {
        'readiness': {'value': 82, 'confidence': .8, 'tier': 'HIGH'},
        'resting_hr': {'value': 51, 'confidence': .8, 'tier': 'HIGH'},
      },
      'sleep': {
        'duration_min': {'value': 430, 'confidence': .8, 'tier': 'HIGH'},
      },
    };

    test('the three overnight figures are refused', () async {
      final d = await HomeData.load(_FakeRepo(today: bundle('missing')));
      expect(d.readiness.value, isNull);
      expect(d.sleepMin.value, isNull);
      expect(d.rhr.value, isNull);
      // The night is still resolvable — it is just no longer a reading.
      expect(d.heldOverNight, '2026-05-16');
    });

    // A night still computing and a night that never happened are different
    // absences: one resolves itself, the other wants a sync.
    test('the absence says which of the two it is', () async {
      final building = await HomeData.load(
        _FakeRepo(today: bundle('building')),
      );
      expect(building.readiness.note, contains('still being worked out'));

      final missing = await HomeData.load(_FakeRepo(today: bundle('missing')));
      expect(missing.readiness.note, contains('reached the app'));
    });

    test("today's own night is served as itself", () async {
      final d = await HomeData.load(
        _FakeRepo(today: bundle('ready', prior: false)),
      );
      expect(d.readiness.value, 82);
      expect(d.rhr.value, 51);
      expect(d.heldOverNight, isNull);
    });
  });

  // ── a rebuild the user never hears about is data quietly vanishing ──
  group('dbRebuiltCard', () {
    test('says nothing when nothing was rebuilt', () {
      expect(dbRebuiltCard(null), isNull);
    });

    test('names the EMPTY tables, not just the recovered count', () {
      final card = dbRebuiltCard((
        cause: 'database disk image is malformed',
        quarantinePath: '/data/openstrap.corrupt.1755300000.db',
        salvaged: const {'day_result': 412, 'food_entry': 0, 'med_dose': 0},
      ))!;
      // The reassuring half.
      expect(card.why, contains('day_result 412'));
      // The half that actually tells someone their food log is gone. A summed
      // "412 rows recovered" would have read as good news.
      expect(card.why, contains('Empty:'));
      expect(card.why, contains('food_entry'));
      expect(card.why, contains('med_dose'));
      // And the original is still on disk — never imply a delete.
      expect(card.why, contains('/data/openstrap.corrupt.1755300000.db'));
      expect(card.why, contains('nothing was '));
    });

    test('does not pretend when nothing came back', () {
      final card = dbRebuiltCard((
        cause: 'file is not a database',
        quarantinePath: '/data/x.db',
        salvaged: const {'day_result': 0},
      ))!;
      expect(card.why, contains('Nothing could be read back'));
    });
  });

  group('Nerd stats naming', () {
    testWidgets('the detail door says Nerd stats', (t) async {
      t.view.physicalSize = const Size(390 * 3, 3000 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: Builder(builder: (c) => investigateRow(c, () {})),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Nerd stats'), findsOneWidget);
      expect(find.text('Investigate'), findsNothing);
    });
  });
}
