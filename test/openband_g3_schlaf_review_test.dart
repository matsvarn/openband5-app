import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/g3/screens/sleep.dart';
import 'package:openstrap_edge/openband/g3/screens/sleep_goal.dart';
import 'package:openstrap_edge/openband/g3/screens/sleep_night.dart';
import 'package:openstrap_edge/openband/g3/screens/sleep_reminder.dart';
import 'package:openstrap_edge/openband/g3/sleep_parts.dart';
import 'package:openstrap_edge/openband/naps.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart' show openBandTheme;

Map _fixture(String name) =>
    jsonDecode(
          File('docs/openband5/assets/fixtures/$name.json').readAsStringSync(),
        )
        as Map;

SyntheticOpenBandRepository _repo({SyntheticScenario? scenario}) =>
    SyntheticOpenBandRepository.fromMaps(
      _fixture('day-summary'),
      _fixture('sleep-detail'),
      scenario: scenario ?? SyntheticScenario.complete,
    );

Future<void> _card(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: openBandTheme(Brightness.light),
      home: Scaffold(
        body: SingleChildScrollView(child: SizedBox(width: 393, child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

class _DelayedReminder extends MemorySleepBedtimeReminder {
  final response = Completer<SleepArmedReminder?>();
  @override
  Future<SleepArmedReminder?> armed() => response.future;
}

class _ClosedNightRepo extends SyntheticOpenBandRepository {
  _ClosedNightRepo(this.night)
    : super.fromMaps(_fixture('day-summary'), _fixture('sleep-detail'));
  final SleepNight night;
  @override
  Future<OpenBandDay> readDay(String day) async => OpenBandDay(
    day: day,
    synthetic: true,
    calculatedAt: DateTime(2026, 9, 29, 9),
    sleep: night,
  );
}

class _MeasuredNoGoalRepo extends SyntheticOpenBandRepository {
  _MeasuredNoGoalRepo()
    : super.fromMaps(_fixture('day-summary'), _fixture('sleep-detail'));
  @override
  Future<List<MetricPoint>> readMetricHistory(
    MetricKey key,
    String day,
    int nights,
  ) async => [
    for (var i = 0; i < 7; i++)
      MetricPoint('2026-09-${(22 + i).toString().padLeft(2, '0')}', 430),
  ];
}

class _PlanWithoutGoalRepo extends SyntheticOpenBandRepository {
  _PlanWithoutGoalRepo()
    : super.fromMaps(
        _fixture('day-summary'),
        _fixture('sleep-detail'),
        scenario: SyntheticScenario.g3Sample,
      );
  @override
  Future<SleepGoalSnapshot> readSleepGoal(String day) async =>
      const SleepGoalSnapshot();
}

class _NoFreeNightRepo extends _PlanWithoutGoalRepo {
  @override
  Future<G3SleepPlus> readSleepPlus(String day, {DateTime? now}) async =>
      const G3SleepPlus(
        regularity: G3AvailableValue(null),
        socialJetlag: G3AvailableValue(null),
        sleepDebt: G3SleepDebt(hasFreeNight: false),
        bedtime: null,
        wake: null,
      );
}

Future<void> _root(WidgetTester tester, SleepNight night) async {
  final repo = _ClosedNightRepo(night);
  final controller = OpenBandController(
    repository: repo,
    initialDay: '2026-09-29',
    now: () => DateTime(2026, 9, 29, 10),
  );
  await controller.refresh();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: openBandTheme(Brightness.light),
      home: G3SleepScreen(
        controller: controller,
        reminder: MemorySleepBedtimeReminder(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  testWidgets('plan shows source rows without claiming the goal is need', (
    tester,
  ) async {
    await _card(
      tester,
      OBPlanBreakdown(
        bonus: 20,
        napCredit: 15,
        need: 485,
        efficiency: .94,
        wake: DateTime(2026, 9, 30, 6, 54),
        bedtime: DateTime(2026, 9, 29, 22, 18),
      ),
    );
    expect(find.text('Freie Nächte · p75'), findsOneWidget);
    expect(find.text('Schlafschuld, positiv'), findsOneWidget);
    expect(find.text('Eigenes Schlafziel'), findsNothing);
    expect(find.text('—'), findsNWidgets(2));
    expect(find.text('22:20'), findsOneWidget);
  });

  testWidgets('first goal starts from measured nights without storing it', (
    tester,
  ) async {
    final repo = _MeasuredNoGoalRepo();
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  G3SleepGoalSheet.show(context, repo, '2026-09-29'),
              child: const Text('Öffnen'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
    expect(find.text('7h10'), findsOneWidget);
    expect(find.text('Start: dein Ø der letzten 7 Nächte'), findsOneWidget);
    expect((await repo.readSleepGoal('2026-09-29')).targetMinutes, isNull);
  });

  testWidgets('tonight offers the stored bedtime without a sleep goal', (
    tester,
  ) async {
    final repo = _PlanWithoutGoalRepo();
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: G3SleepTonight(
          repository: repo,
          day: '2026-09-29',
          now: () => DateTime(2026, 9, 29, 10),
          reminder: MemorySleepBedtimeReminder(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('22:20'), findsWidgets);
    expect(find.textContaining('erinnern'), findsOneWidget);
    expect(find.text('Eigenes Schlafziel'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no free night refuses need and bedtime without a reminder', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: G3SleepTonight(
          repository: _NoFreeNightRepo(),
          day: '2026-09-29',
          now: () => DateTime(2026, 9, 29, 10),
          reminder: MemorySleepBedtimeReminder(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Noch keine freie Nacht'), findsOneWidget);
    expect(find.text('Woher der Bedarf kommt'), findsOneWidget);
    expect(find.textContaining('erinnern'), findsNothing);
  });

  testWidgets('building rhythm states its actual refusal', (tester) async {
    await _card(
      tester,
      const OBSriLead(gate: 'Regelmäßigkeit braucht 7 ausgewertete Nächte.'),
    );
    expect(find.text('—'), findsOneWidget);
    expect(
      find.text('Regelmäßigkeit braucht 7 ausgewertete Nächte.'),
      findsOneWidget,
    );
    expect(find.text('aus 7 Nächten'), findsNothing);
  });

  testWidgets('debt refusal stays distinct from another-day artifact', (
    tester,
  ) async {
    await _card(
      tester,
      const OBSleepDebt(gate: 'Braucht längere freie Nächte.'),
    );
    expect(find.text('Braucht längere freie Nächte.'), findsOneWidget);
    expect(
      find.text('Für diesen Tag keine Auswertung gespeichert.'),
      findsNothing,
    );
  });

  testWidgets(
    'signed social jetlag gives the direction without a negative duration',
    (tester) async {
      await _card(tester, const OBSocialJetlag(minutes: -100));
      expect(find.text('1h40'), findsOneWidget);
      expect(find.text('früher an freien Tagen'), findsOneWidget);
      await _card(tester, const OBSocialJetlag(minutes: 100));
      expect(find.text('später an freien Tagen'), findsOneWidget);
    },
  );

  testWidgets('sleep debt formats positive, negative and zero', (tester) async {
    await _card(tester, const OBSleepDebtLead(minutes: -47));
    expect(find.text('47 Min.'), findsOneWidget);
    expect(find.text('mehr als in freien Nächten'), findsOneWidget);
    await _card(tester, const OBSleepDebt(minutes: 0));
    expect(find.text('0 Min.'), findsOneWidget);
    expect(find.text('gleich lang wie in freien Nächten'), findsOneWidget);
    await _card(tester, const OBSleepDebt(minutes: 47));
    expect(find.text('weniger als in freien Nächten'), findsOneWidget);
  });

  testWidgets('bedtime comparison wraps across midnight', (tester) async {
    await _card(
      tester,
      OBBedtimeLead(
        bedtime: DateTime(2026, 9, 29, 22, 20),
        wake: DateTime(2026, 9, 30, 7),
        lastOnset: DateTime(2026, 9, 29, 0, 40),
      ),
    );
    expect(find.textContaining('140 Min. früher'), findsOneWidget);
  });

  testWidgets('clock axis labels follow the bar time mapping', (tester) async {
    await _card(tester, const OBSleepClockAxis(startHour: 21, endHour: 9));
    final start = tester.getTopLeft(find.byType(OBSleepClockAxis)).dx;
    final width = tester.getSize(find.byType(OBSleepClockAxis)).width;
    for (final (label, fraction) in [
      ('22:00', 1 / 12),
      ('02:00', 5 / 12),
      ('06:00', 9 / 12),
    ]) {
      expect(
        tester.getCenter(find.text(label)).dx,
        closeTo(start + width * fraction, 2),
      );
    }
  });

  testWidgets('strain running caption is limited to the open day', (
    tester,
  ) async {
    await _card(tester, const OBPlanBreakdown(bonus: 20, strainOpen: false));
    expect(find.text('Belastung heute, läuft'), findsNothing);
    await _card(tester, const OBPlanBreakdown(bonus: 20, strainOpen: true));
    expect(find.text('Belastung heute, läuft'), findsOneWidget);
  });

  testWidgets('another day with null value and gate is not called building', (
    tester,
  ) async {
    await _card(tester, const OBSleepWindows(windows: [], regularity: null));
    expect(
      find.text('Für diesen Tag keine Auswertung gespeichert.'),
      findsOneWidget,
    );
    expect(find.text('Basis im Aufbau'), findsNothing);
    await _card(tester, const OBSleepDebt());
    expect(
      find.text('Für diesen Tag keine Auswertung gespeichert.'),
      findsOneWidget,
    );
  });

  test(
    'signal partial is caused by uncovered intervals, not a stored flag',
    () {
      final start = DateTime(2026, 9, 29, 0);
      final window = (start: start, end: start.add(const Duration(minutes: 3)));
      NightSignalSeries series(List<NightSignalReading> values) =>
          NightSignalSeries(
            readings: values,
            partial: true,
            maxConnectingGap: const Duration(minutes: 1),
          );
      expect(
        nightSignalHasUncoveredInterval(
          series([
            for (var i = 0; i <= 3; i++)
              NightSignalReading(start.add(Duration(minutes: i)), 55),
          ]),
          window,
        ),
        isFalse,
      );
      expect(
        nightSignalHasUncoveredInterval(
          series([
            NightSignalReading(start, 55),
            NightSignalReading(start.add(const Duration(minutes: 1)), null),
            NightSignalReading(start.add(const Duration(minutes: 3)), 54),
          ]),
          window,
        ),
        isTrue,
      );
    },
  );

  testWidgets('SRI uses the defined negative to positive scale', (
    tester,
  ) async {
    await _card(tester, const OBSriLead(value: -25));
    expect(find.text('−100'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
  });

  testWidgets('debt values beyond the fixed axis are named, not pinned', (
    tester,
  ) async {
    await _card(
      tester,
      const OBSleepDebt(minutes: 90, freeMinutes: 600, usualMinutes: 350),
    );
    expect(find.text('Wert außerhalb der Skala 6–9 h.'), findsOneWidget);
  });

  testWidgets(
    'closed missing night omits estimated phases and offers correction',
    (tester) async {
      await _root(tester, const SleepNight());
      expect(find.text('Keine Nacht erkannt'), findsWidgets);
      expect(find.textContaining('Phasen aus Puls'), findsNothing);
      expect(find.text('Doch geschlafen?'), findsOneWidget);
      expect(find.text('Schlafzeiten eintragen'), findsOneWidget);
    },
  );

  testWidgets('a gap night labels the uncovered span and uses staged totals', (
    tester,
  ) async {
    final start = DateTime(2026, 9, 28, 23);
    final night = SleepNight(
      onset: start,
      wake: start.add(const Duration(hours: 4)),
      duration: const DayMetric(180),
      bedMinutes: 240,
      unobservedMinutes: 60,
      deepMinutes: 120,
      segments: [
        NightSegment(
          start,
          start.add(const Duration(hours: 1)),
          NightStage.deep,
        ),
        NightSegment(
          start.add(const Duration(hours: 1)),
          start.add(const Duration(hours: 2)),
          null,
        ),
        NightSegment(
          start.add(const Duration(hours: 2)),
          start.add(const Duration(hours: 4)),
          NightStage.light,
        ),
      ],
    );
    await _root(tester, night);
    expect(find.textContaining('00:00–01:00 ohne Daten'), findsOneWidget);
    expect(find.text('1h00'), findsOneWidget);
    expect(find.text('2h00'), findsOneWidget);
  });

  test('stale reminder reconcile cannot cancel a newly armed slot', () async {
    final reminder = _DelayedReminder();
    reminder.current = (at: DateTime(2026, 9, 29, 22), day: '2026-09-29');
    var generation = 1;
    final pending = reminder.reconcile(
      today: '2026-09-30',
      planLoaded: false,
      active: () => generation == 1,
    );
    generation++;
    reminder.response.complete(reminder.current);
    expect(await pending, isFalse);
    expect(reminder.cancellations, 0);
  });

  test(
    'correction save, recalculation and restore preserve their distinct states',
    () async {
      final repo = _repo();
      const day = '2026-09-15';
      final draft = SleepDraft(
        id: 'review-correction',
        day: day,
        onset: DateTime(2026, 9, 14, 22, 40),
        wake: DateTime(2026, 9, 15, 6, 54),
      );
      final saved = await repo.saveCorrection(draft);
      expect(saved.state, CorrectionState.pending);
      expect((await repo.readDraft(day))?.onset, draft.onset);
      await repo.recalculate(saved);
      expect(
        (await repo.readDay(day)).correction?.state,
        CorrectionState.complete,
      );
      await repo.restoreAutomatic(day);
      expect((await repo.readDay(day)).correction, isNull);
    },
  );

  testWidgets('corrected night Rückgängig restores automatic evaluation', (
    tester,
  ) async {
    final repo = _repo();
    const day = '2026-09-15';
    final saved = await repo.saveCorrection(
      SleepDraft(
        id: 'undo-correction',
        day: day,
        onset: DateTime(2026, 9, 14, 22, 40),
        wake: DateTime(2026, 9, 15, 6, 54),
      ),
    );
    await repo.recalculate(saved);
    final controller = OpenBandController(
      repository: repo,
      initialDay: day,
      now: () => DateTime(2026, 9, 29, 10),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: G3SleepScreen(
          controller: controller,
          reminder: MemorySleepBedtimeReminder(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Von dir korrigiert'), findsOneWidget);
    await tester.tap(find.text('Rückgängig'));
    await tester.pumpAndSettle();
    expect(find.text('Automatische Zeiten wiederherstellen?'), findsOneWidget);
    await tester.tap(find.text('Wiederherstellen'));
    await tester.pumpAndSettle();
    expect((await repo.readDay(day)).correction, isNull);
    expect(find.text('Von dir korrigiert'), findsNothing);
  });

  test('nap calculation failure keeps the committed revision', () async {
    final repo = _repo(scenario: SyntheticScenario.calculationFailure);
    const day = '2026-09-29';
    final revision = await repo.addNap(
      day: day,
      start: DateTime(2026, 9, 29, 14),
      end: DateTime(2026, 9, 29, 14, 30),
    );
    await expectLater(
      repo.recalculateNaps(day: day, revision: revision),
      throwsStateError,
    );
    final naps = await repo.readNaps(day);
    expect(naps.job?.revision, revision);
    expect(naps.job?.state, CorrectionState.failed);
    expect(naps.sessions.any((nap) => nap.source == NapSource.manual), isTrue);
  });

  testWidgets('nap editor names the selected day before writing', (
    tester,
  ) async {
    final controller = OpenBandController(
      repository: _repo(),
      initialDay: '2026-09-28',
      now: () => DateTime(2026, 9, 29, 10),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: Scaffold(
          body: OpenBandNapEditor(controller: controller, g3Sheet: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Tag: Mo 28.09'), findsOneWidget);
  });
}
