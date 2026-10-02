import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/g3/screens/sleep.dart';
import 'package:openstrap_edge/openband/g3/screens/sleep_goal.dart';
import 'package:openstrap_edge/openband/g3/screens/sleep_night.dart';
import 'package:openstrap_edge/openband/g3/screens/sleep_naps.dart';
import 'package:openstrap_edge/openband/g3/screens/sleep_reminder.dart';
import 'package:openstrap_edge/openband/g3/chrome.dart'
    show
        G3DetailPage,
        OBInfoSheet,
        OBListRow,
        OBPanel,
        OBPageHeader,
        OBSectionHeader;
import 'package:openstrap_edge/openband/g3/day.dart'
    show OBHypnogram, OBStageLegend, OBWeekBars;
import 'package:openstrap_edge/openband/g3/g3_theme.dart';
import 'package:openstrap_edge/openband/g3/metrics.dart'
    show G3LabelRow, G3Scale, OBMissingValue;
import 'package:openstrap_edge/openband/g3/sleep_parts.dart';
import 'package:openstrap_edge/openband/naps.dart';
import 'package:openstrap_edge/openband/sleep_editor.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/tab_bar.dart';
import 'package:openstrap_edge/openband/theme.dart'
    show OBChevron, openBandTheme;
import 'package:openstrap_edge/ui2/app_shell.dart';

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

class _RespirationRangeRepo extends _PlanWithoutGoalRepo {
  @override
  Future<G3Baseline> readPersonalRange(G3Metric metric, String day) async =>
      metric == G3Metric.respRate
      ? const G3Baseline(
          BaselineStatus(BaselinePhase.trusted),
          range: PersonalRange(14.2, 16.6, 15.4),
        )
      : super.readPersonalRange(metric, day);
}

class _NoNapsRepo extends _RespirationRangeRepo {
  @override
  Future<NapDay> readNaps(String day) async =>
      NapDay(day: day, judged: true, totalMin: 0);
}

class _MissingNightMetricRepo extends _RespirationRangeRepo {
  @override
  Future<OpenBandDay> readDay(String day) async =>
      OpenBandDay(day: day, synthetic: true);
}

class _OneNightBasisRepo extends _PlanWithoutGoalRepo {
  @override
  Future<G3Baseline> readPersonalRange(G3Metric metric, String day) async =>
      const G3Baseline(
        BaselineStatus(BaselinePhase.building, nightsHave: 6, nightsNeeded: 7),
      );
}

class _SignedJetlagRepo extends _PlanWithoutGoalRepo {
  @override
  Future<G3SleepPlus> readSleepPlus(String day, {DateTime? now}) async =>
      const G3SleepPlus(
        regularity: G3AvailableValue(78),
        socialJetlag: G3AvailableValue(1.5),
        socialJetlagDetail: G3SocialJetlagDetail(signedHours: -1.5),
        sleepDebt: G3SleepDebt(),
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
  setUpAll(() async {
    await initializeDateFormatting('de_DE');
    for (final (family, path) in [
      ('Inter', 'assets/fonts/Inter/Inter.ttf'),
      ('Inter Tight', 'assets/fonts/InterTight/InterTight[wght].ttf'),
    ]) {
      await (FontLoader(family)..addFont(
            Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
          ))
          .load();
    }
  });

  testWidgets(
    'sleep overview cards open from their bodies and detail labels are inert',
    (tester) async {
      var opened = 0;
      await _card(
        tester,
        Column(
          children: [
            OBSleepWindows(
              windows: const [],
              regularity: 72,
              onTap: () => opened++,
            ),
            OBSocialJetlag(minutes: 30, onTap: () => opened++),
            OBSleepDebt(minutes: 20, onTap: () => opened++),
          ],
        ),
      );
      for (final label in [
        'REGELMÄSSIGKEIT',
        'SOZIALE ZEITVERSCHIEBUNG',
        'SCHLAFSCHULD',
      ]) {
        final panel = find
            .ancestor(of: find.text(label), matching: find.byType(OBPanel))
            .first;
        await tester.tapAt(tester.getBottomLeft(panel) + const Offset(30, -24));
      }
      expect(opened, 3);
      expect(find.text('Ansehen'), findsNothing);
      expect(find.text('Methode'), findsNothing);

      await _card(
        tester,
        const OBSleepWindows(windows: [], regularity: 72, detail: true),
      );
      await tester.tap(find.text('IM BETT JE NACHT'));
      expect(opened, 3);
    },
  );

  testWidgets(
    'sleep header routes profile and band when callbacks are supplied',
    (tester) async {
      final controller = OpenBandController(
        repository: _repo(),
        initialDay: '2026-09-29',
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      var profile = 0;
      var band = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: openBandTheme(Brightness.light),
          home: G3SleepScreen(
            controller: controller,
            onProfile: () => profile++,
            onBand: () => band++,
            reminder: MemorySleepBedtimeReminder(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Profil'));
      await tester.tap(find.bySemanticsLabel('Band getrennt'));
      expect(profile, 1);
      expect(band, 1);
    },
  );

  testWidgets('sleep lead opens goal setup from the card body', (tester) async {
    var opened = 0;
    await _card(
      tester,
      OBSleepLead(minutes: 438, goalMinutes: 465, onGoal: () => opened++),
    );
    final panel = find
        .ancestor(of: find.text('SCHLAF'), matching: find.byType(OBPanel))
        .first;
    await tester.tapAt(tester.getBottomRight(panel) - const Offset(24, 24));
    expect(opened, 1);
    expect(find.text('Ziel 7h45'), findsOneWidget);
  });

  testWidgets('sleep detail info keys show their method explanation', (
    tester,
  ) async {
    final repo = _repo();
    final pages = <Widget>[
      G3SleepRegularity(repository: repo, day: '2026-09-29'),
      G3SleepDebtDetail(repository: repo, day: '2026-09-29'),
      G3SleepTonight(
        repository: repo,
        day: '2026-09-29',
        now: () => DateTime(2026, 9, 29, 10),
        reminder: MemorySleepBedtimeReminder(),
      ),
    ];
    for (final page in pages) {
      await tester.pumpWidget(
        MaterialApp(theme: openBandTheme(Brightness.light), home: page),
      );
      await tester.pumpAndSettle();
      expect(find.byType(G3DetailPage), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Erklärung'));
      await tester.pumpAndSettle();
      expect(find.byType(OBInfoSheet), findsOneWidget);
      expect(find.bySemanticsLabel('Schließen'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Schließen'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('sleep overview uses the shared night date and missing value', (
    tester,
  ) async {
    await _root(tester, const SleepNight());
    expect(find.text('Nacht zu Di 29.09'), findsOneWidget);
    expect(find.byType(OBMissingValue), findsWidgets);
  });

  testWidgets('sleep labels and marks use violet while values stay ink', (
    tester,
  ) async {
    await _card(tester, const OBSleepLead(minutes: 438, goalMinutes: null));
    final label = find.text('SCHLAF');
    final g = G3.of(tester.element(label));
    expect(
      tester.widget<Text>(label).style!.color,
      g.domainHue(G3Domain.sleep),
    );
    expect(tester.widget<Text>(find.text('7h18')).style!.color, g.ink);
    expect(find.byIcon(LucideIcons.moon), findsOneWidget);

    await _card(tester, const OBPlanBreakdown(baseline: 420, need: 420));
    expect(
      tester.widget<Text>(find.text('RECHNUNG')).style!.color,
      G3.of(tester.element(find.text('RECHNUNG'))).domainHue(G3Domain.sleep),
    );
  });

  testWidgets('sleep tonight uses the shared note with its own heading', (
    tester,
  ) async {
    final controller = OpenBandController(
      repository: _PlanWithoutGoalRepo(),
      initialDay: '2026-09-29',
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
    await tester.scrollUntilVisible(
      find.text('SCHLAF'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('SCHLAF'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Heute Nacht'));
    await tester.pumpAndSettle();
    expect(find.byType(G3SleepTonight), findsOneWidget);
    expect(find.text('HEUTE NACHT'), findsOneWidget);
    expect(find.text('FÜR HEUTE'), findsNothing);
  });

  testWidgets('free nights use a full-width shared section heading', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: G3SleepDebtDetail(repository: _repo(), day: '2026-09-29'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('FREIE NÄCHTE · SA UND SO'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.ancestor(
        of: find.text('FREIE NÄCHTE · SA UND SO'),
        matching: find.byType(OBSectionHeader),
      ),
      findsOneWidget,
    );
    expect(tester.getTopLeft(find.text('FREIE NÄCHTE · SA UND SO')).dx, 24);
  });

  testWidgets(
    'night phase method lives in the sheet and the overview uses shared week bars',
    (tester) async {
      final start = DateTime(2026, 9, 28, 23, 10);
      await _root(
        tester,
        SleepNight(
          onset: start,
          wake: start.add(const Duration(hours: 7, minutes: 44)),
          duration: const DayMetric(438),
          bedMinutes: 464,
          segments: [
            NightSegment(
              start,
              start.add(const Duration(hours: 7, minutes: 44)),
              NightStage.light,
            ),
          ],
        ),
      );
      expect(
        tester.widget<OBHypnogram>(find.byType(OBHypnogram)).domain,
        G3Domain.sleep,
      );
      final g = G3.of(tester.element(find.byType(OBStageLegend)));
      final swatches = tester.widget<OBStageLegend>(find.byType(OBStageLegend));
      expect(
        [for (final item in swatches.items) item.$3],
        [
          g.stageFor(G3Domain.sleep, 3),
          g.stageFor(G3Domain.sleep, 2),
          g.stageFor(G3Domain.sleep, 1),
          g.stageFor(G3Domain.sleep, 0),
        ],
      );
      expect(find.textContaining('Phasen aus Puls'), findsNothing);
      expect(find.text('lückenlos'), findsNothing);
      await Scrollable.ensureVisible(
        tester.element(find.text('Methode')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Methode'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Tief ist am unsichersten'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Schließen'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('LETZTE 7 NÄCHTE'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.byType(OBWeekBars), findsOneWidget);
      expect(
        tester.widget<OBWeekBars>(find.byType(OBWeekBars)).domain,
        G3Domain.sleep,
      );
      expect(find.text('Eintragen'), findsOneWidget);
      expect(find.text('+ Eintragen'), findsNothing);
      final napsHeader = find.ancestor(
        of: find.text('NICKERCHEN'),
        matching: find.byType(OBSectionHeader),
      );
      expect(
        find.descendant(
          of: napsHeader,
          matching: find.byIcon(LucideIcons.plus),
        ),
        findsOneWidget,
      );
    },
  );

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

  testWidgets('Rechnung signs nonzero terms and leaves zero unsigned', (
    tester,
  ) async {
    await _card(
      tester,
      const OBPlanBreakdown(debt: 10, bonus: 20, napCredit: 0),
    );
    expect(find.text('+10 Min.'), findsOneWidget);
    expect(find.text('+20 Min.'), findsOneWidget);
    expect(find.text('0 Min.'), findsOneWidget);
    expect(find.text('−0 Min.'), findsNothing);

    await _card(
      tester,
      const OBPlanBreakdown(debt: 0, bonus: 0, napCredit: 15),
    );
    expect(find.text('0 Min.'), findsNWidgets(2));
    expect(find.text('−15 Min.'), findsOneWidget);
    expect(find.text('+0 Min.'), findsNothing);
    expect(find.text('−0 Min.'), findsNothing);
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
    expect(find.text('7h35'), findsOneWidget);
    expect(find.text('+10 Min.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tonight leaves efficiency absent without a stored divisor', (
    tester,
  ) async {
    await _card(
      tester,
      const OBPlanBreakdown(baseline: 451, debt: 13, need: 484),
    );
    expect(find.text('7h31'), findsOneWidget);
    expect(find.text('+13 Min.'), findsOneWidget);
    expect(find.text('÷ übliche Schlafeffizienz'), findsOneWidget);
    expect(find.text('8h35 im Bett'), findsNothing);
  });

  testWidgets('a need limit is named without inferred clamp minutes', (
    tester,
  ) async {
    await _card(
      tester,
      const OBPlanBreakdown(
        baseline: 420,
        debt: 10,
        bonus: 0,
        napCredit: 115,
        needClamp: G3SleepNeedClamp(360),
        need: 360,
      ),
    );
    expect(find.text('Belastung, angerechnet'), findsOneWidget);
    expect(find.text('Nickerchen, angerechnet'), findsOneWidget);
    final floor = find.ancestor(
      of: find.text('Untergrenze 6h angewendet'),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: floor, matching: find.text('—')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: floor, matching: find.textContaining('Min.')),
      findsNothing,
    );
    await _card(
      tester,
      const OBPlanBreakdown(
        baseline: 570,
        debt: 165,
        bonus: 0,
        napCredit: 0,
        needClamp: G3SleepNeedClamp(660),
        need: 660,
      ),
    );
    final ceiling = find.ancestor(
      of: find.text('Obergrenze 11h angewendet'),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: ceiling, matching: find.text('—')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: ceiling, matching: find.textContaining('Min.')),
      findsNothing,
    );
  });

  testWidgets('tonight subtitle uses the next civil day at DST end', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: G3SleepTonight(
          repository: _NoFreeNightRepo(),
          day: '2026-10-25',
          now: () => DateTime(2026, 10, 25, 10),
          reminder: MemorySleepBedtimeReminder(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('So → Mo 26.10'), findsOneWidget);
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

  testWidgets(
    'root omits baseline explanations and night detail keeps singular copy',
    (tester) async {
      final repo = _OneNightBasisRepo();
      final controller = OpenBandController(
        repository: repo,
        initialDay: '2026-09-29',
        now: () => DateTime(2026, 9, 29, 10),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      await tester.pumpWidget(
        MaterialApp(
          theme: openBandTheme(Brightness.light),
          home: G3SleepScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('HRV · ms'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('noch 1 Nacht'), findsNothing);
      expect(find.text('noch 1 Nächte'), findsNothing);
      final emptyScales = find.byWidgetPredicate(
        (widget) => widget is G3Dashed && widget.height == 7,
      );
      expect(emptyScales, findsNWidgets(3));
      for (var index = 0; index < 3; index++) {
        expect(tester.getSize(emptyScales.at(index)).width, greaterThan(60));
      }

      await tester.pumpWidget(
        MaterialApp(
          theme: openBandTheme(Brightness.light),
          home: G3SleepNightSignals(repository: repo, day: '2026-09-29'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('noch 1 Nacht'), findsWidgets);
      expect(find.text('noch 1 Nächte'), findsNothing);
    },
  );

  testWidgets('trusted range with a missing night metric stays missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: G3SleepNightSignals(
          repository: _MissingNightMetricRepo(),
          day: '2026-09-29',
          initialKind: NightSignalKind.respiration,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('—'), findsWidgets);
    expect(find.textContaining('deinem Median'), findsNothing);
  });

  testWidgets('one window and one measured point use singular', (tester) async {
    final at = DateTime(2026, 9, 29, 0);
    await _card(
      tester,
      OBSleepWindows(
        windows: [
          (
            day: 'Mo',
            start: at,
            end: at.add(const Duration(hours: 7)),
            minutes: 420,
          ),
        ],
        regularity: 75,
        detail: true,
      ),
    );
    expect(find.text('1 Nacht'), findsOneWidget);
    expect(find.text('1 Nächte'), findsNothing);

    await _card(
      tester,
      OBNightTrace(
        domain: G3Domain.recovery,
        series: NightSignalSeries(readings: [NightSignalReading(at, 60)]),
        start: at,
        end: at.add(const Duration(minutes: 1)),
      ),
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label ==
                'Nachtverlauf mit 1 gespeichertem Messpunkt. Lücken bleiben leer.',
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<OBNightTrace>(find.byType(OBNightTrace)).domain,
      G3Domain.recovery,
    );
  });

  testWidgets('Körper metrics stay blue on Schlaf and Nachtverlauf', (
    tester,
  ) async {
    await _root(tester, const SleepNight());
    await tester.scrollUntilVisible(
      find.text('HRV · ms'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    final g = G3.of(tester.element(find.text('HRV · ms')));
    for (final label in ['HRV · ms', 'RUHEPULS', 'ATEMFREQUENZ']) {
      expect(
        tester.widget<Text>(find.text(label)).style!.color,
        g.domainHue(G3Domain.recovery),
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: G3SleepNightSignals(
          repository: _RespirationRangeRepo(),
          day: '2026-09-29',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<OBPageHeader>(find.byType(OBPageHeader)).domain,
      G3Domain.sleep,
    );
    expect(
      tester
          .widget<G3LabelRow>(
            find.byWidgetPredicate(
              (widget) => widget is G3LabelRow && widget.label == 'RUHEPULS',
            ),
          )
          .domain,
      G3Domain.recovery,
    );
    await tester.tap(find.text('Atemfrequenz'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<G3LabelRow>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is G3LabelRow && widget.label == 'ATEMFREQUENZ',
            ),
          )
          .domain,
      G3Domain.recovery,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is G3Scale &&
            widget.domain == G3Domain.recovery &&
            widget.band != null,
      ),
      findsWidgets,
    );
  });

  testWidgets('ungated missing SRI says this day has no evaluation', (
    tester,
  ) async {
    await _card(tester, const OBSriLead());
    expect(
      find.text('Für diesen Tag keine Auswertung gespeichert.'),
      findsOneWidget,
    );
    expect(find.text('im Aufbau'), findsNothing);
    expect(find.text('von 100'), findsNothing);
  });

  testWidgets('regularity detail preserves the ungated missing state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: G3SleepRegularity(
          repository: _NoFreeNightRepo(),
          day: '2026-09-29',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Für diesen Tag keine Auswertung gespeichert.'),
      findsWidgets,
    );
    expect(find.text('im Aufbau'), findsNothing);
  });

  testWidgets('regularity detail uses stored jetlag sign, not absolute hours', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: G3SleepRegularity(
          repository: _SignedJetlagRepo(),
          day: '2026-09-29',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('früher an freien Tagen'));
    expect(find.text('früher an freien Tagen'), findsOneWidget);
    expect(find.text('später an freien Tagen'), findsNothing);
  });

  testWidgets('debt refusal stays distinct from another-day artifact', (
    tester,
  ) async {
    await _card(
      tester,
      const OBSleepDebt(gate: 'Braucht längere freie Nächte.', detail: true),
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
      await _card(tester, const OBSocialJetlag(minutes: 0));
      expect(find.text('gleich an freien Tagen'), findsOneWidget);
      expect(find.text('später an freien Tagen'), findsNothing);
    },
  );

  testWidgets('missing window summaries omit their period captions', (
    tester,
  ) async {
    await _card(tester, const OBSocialJetlag());
    expect(find.text('7 Nächte'), findsNothing);
    await _card(tester, const OBSleepDebtLead());
    expect(find.text('3 Wochen'), findsNothing);
  });

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
    expect(find.textContaining('2h20 früher'), findsOneWidget);
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
    expect(find.text('Belastung, angerechnet · läuft'), findsNothing);
    await _card(tester, const OBPlanBreakdown(bonus: 20, strainOpen: true));
    expect(find.text('Belastung, angerechnet · läuft'), findsOneWidget);
  });

  testWidgets('another day with null value and gate is not called building', (
    tester,
  ) async {
    await _card(
      tester,
      const OBSleepWindows(windows: [], regularity: null, detail: true),
    );
    expect(
      find.text('Für diesen Tag keine Auswertung gespeichert.'),
      findsOneWidget,
    );
    expect(find.text('Basis im Aufbau'), findsNothing);
    await _card(tester, const OBSleepDebt(detail: true));
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
    expect(find.text('von 100'), findsNothing);
  });

  testWidgets('respiration range ticks keep one decimal', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: G3SleepNightSignals(
          repository: _RespirationRangeRepo(),
          day: '2026-09-29',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Atemfrequenz'));
    await tester.pumpAndSettle();
    expect(find.text('14,2'), findsOneWidget);
    expect(find.text('16,6'), findsOneWidget);
  });

  testWidgets('debt values beyond the fixed axis are named, not pinned', (
    tester,
  ) async {
    await _card(
      tester,
      const OBSleepDebt(
        minutes: 90,
        freeMinutes: 600,
        usualMinutes: 350,
        detail: true,
      ),
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
    expect(find.text('1h'), findsOneWidget);
    expect(find.text('2h'), findsOneWidget);
  });

  testWidgets('multiple night gaps name every uncovered clock range', (
    tester,
  ) async {
    final start = DateTime(2026, 9, 28, 23);
    final night = SleepNight(
      onset: start,
      wake: start.add(const Duration(hours: 4)),
      duration: const DayMetric(120),
      bedMinutes: 240,
      unobservedMinutes: 120,
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
          start.add(const Duration(hours: 3)),
          NightStage.light,
        ),
        NightSegment(
          start.add(const Duration(hours: 3)),
          start.add(const Duration(hours: 4)),
          null,
        ),
      ],
    );
    await _root(tester, night);
    expect(find.textContaining('00:00–01:00 ohne Daten'), findsOneWidget);
    expect(find.textContaining('02:00–03:00 ohne Daten'), findsOneWidget);
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

  testWidgets(
    'sleep correction covers the floating tab bar and names its recorded span',
    (tester) async {
      final start = DateTime(2026, 9, 28, 23, 10);
      final end = DateTime(2026, 9, 29, 6, 54);
      final repo = _ClosedNightRepo(
        SleepNight(
          onset: start,
          wake: end,
          duration: const DayMetric(438),
          bedMinutes: 464,
          segments: [NightSegment(start, end, NightStage.light)],
        ),
      );
      final controller = OpenBandController(
        repository: repo,
        initialDay: '2026-09-29',
        now: () => DateTime(2026, 9, 29, 10),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      await tester.pumpWidget(
        MaterialApp(
          theme: openBandTheme(Brightness.light),
          home: AppShell(
            initial: ShellDomain.sleep,
            releaseStyle: true,
            domains: const [ShellDomain.home, ShellDomain.sleep],
            builder: (context, domain) => domain == ShellDomain.sleep
                ? G3SleepScreen(controller: controller, asTab: true)
                : const Scaffold(body: Text('Heute')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(OBTabBar), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Zeiten ändern'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('Zeiten ändern')),
        alignment: .3,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zeiten ändern'));
      await tester.pumpAndSettle();
      expect(find.byType(SleepEditor), findsOneWidget);
      expect(find.byType(OBTabBar), findsNothing);
      expect(find.text('Nacht zu Di 29.09'), findsOneWidget);
      expect(find.text('7h44'), findsOneWidget);
      expect(find.text('Band hat aufgezeichnet 23:10–06:54'), findsOneWidget);
      expect(find.textContaining('vorher'), findsNothing);
      final header = find.byType(OBPageHeader).last;
      final firstPanel = find.byType(OBPanel).first;
      expect(tester.getTopLeft(header).dx, 0);
      expect(tester.getTopLeft(firstPanel).dx, 16);
      expect(
        tester.getTopLeft(firstPanel).dy - tester.getBottomLeft(header).dy,
        closeTo(12, 1),
      );
      final bar = find.byKey(const ValueKey('sleep-window-bar'));
      final left = tester.getTopLeft(bar).dx;
      final width = tester.getSize(bar).width;
      for (final (hour, label, fraction) in [
        (20, '20:00', 0.0),
        (0, '00:00', 4 / 14),
        (4, '04:00', 8 / 14),
        (8, '08:00', 12 / 14),
        (10, '10:00', 1.0),
      ]) {
        final x = left + width * fraction;
        expect(
          tester.getCenter(find.byKey(ValueKey('sleep-window-tick-$hour'))).dx,
          closeTo(x, 1.5),
        );
        if (hour != 8) {
          expect(
            tester.getCenter(find.text(label)).dx,
            closeTo((x - 17).clamp(left, left + width - 34) + 17, 1.5),
          );
        }
      }
      await tester.tap(find.text('+5 Min.').first);
      await tester.pumpAndSettle();
      expect(find.text('7h39 · vorher 7h44'), findsOneWidget);
      expect(
        find.text('Band hat aufgezeichnet 23:10–06:54 · vorher 23:10–06:54'),
        findsOneWidget,
      );
      await tester.tap(find.text('−5 Min.').first);
      await tester.pumpAndSettle();
      expect(find.text('7h44'), findsOneWidget);
      expect(find.textContaining('vorher'), findsNothing);
    },
  );

  testWidgets('correction uses a dash when recorded span is unknown', (
    tester,
  ) async {
    final controller = OpenBandController(
      repository: _ClosedNightRepo(
        SleepNight(
          onset: DateTime(2026, 9, 28, 23, 10),
          wake: DateTime(2026, 9, 29, 6, 54),
        ),
      ),
      initialDay: '2026-09-29',
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: SleepEditor(controller: controller, g3: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Band hat aufgezeichnet —'), findsOneWidget);
    expect(find.textContaining('vorher'), findsNothing);
  });

  for (final scale in [2.0, 3.1]) {
    testWidgets('correction axis and times fit 375 pt at ${scale}x text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = OpenBandController(
        repository: _ClosedNightRepo(
          SleepNight(
            onset: DateTime(2026, 9, 28, 23, 25),
            wake: DateTime(2026, 9, 29, 6, 54),
          ),
        ),
        initialDay: '2026-09-29',
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      await tester.pumpWidget(
        MaterialApp(
          theme: openBandTheme(Brightness.light),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(375, 812),
              textScaler: TextScaler.linear(scale),
            ),
            child: SleepEditor(controller: controller, g3: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final recorded = tester.getRect(find.text('Band hat aufgezeichnet —'));
      final labels = [
        for (final label in ['20:00', '00:00', '04:00', '10:00'])
          tester.getRect(find.text(label)),
      ];
      for (var i = 0; i < labels.length; i++) {
        // One line, above the recorded span, clear of its neighbour.
        expect(labels[i].height, lessThan(20 * 1.3));
        expect(labels[i].bottom, lessThanOrEqualTo(recorded.top));
        if (i > 0) {
          expect(labels[i].left, greaterThanOrEqualTo(labels[i - 1].right));
        }
      }
      for (final key in ['sleep-onset', 'sleep-wake']) {
        final field = find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(EditableText),
        );
        final editable = tester.widget<EditableText>(field);
        final painter = TextPainter(
          text: TextSpan(text: editable.controller.text, style: editable.style),
          textScaler:
              editable.textScaler ??
              MediaQuery.textScalerOf(tester.element(field)),
          textDirection: TextDirection.ltr,
        )..layout();
        addTearDown(painter.dispose);
        expect(painter.width, lessThanOrEqualTo(tester.getSize(field).width));
      }
      for (final label in ['BEGINN · MO', 'ENDE · DI']) {
        expect(
          tester.getRect(find.text(label)).bottom,
          lessThanOrEqualTo(
            tester
                .getTopLeft(
                  find.byKey(
                    ValueKey(
                      label.startsWith('B') ? 'sleep-onset' : 'sleep-wake',
                    ),
                  ),
                )
                .dy,
          ),
        );
      }
    });
  }

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
  test('night trace labels only stored missing runs with known cadence', () {
    final start = DateTime(2026, 9, 29, 4, 10);
    final end = start.add(const Duration(minutes: 10));
    final readings = [
      NightSignalReading(start, 54),
      for (var i = 2; i < 8; i++)
        NightSignalReading(start.add(Duration(minutes: i)), null),
      NightSignalReading(start.add(const Duration(minutes: 8)), 55),
    ];
    final gaps = nightTraceGaps(
      NightSignalSeries(
        readings: readings,
        maxConnectingGap: const Duration(minutes: 2),
      ),
      start,
      end,
    );
    expect(gaps, hasLength(1));
    expect(gaps.single.start, DateTime(2026, 9, 29, 4, 12));
    expect(gaps.single.end, DateTime(2026, 9, 29, 4, 18));
    expect(
      nightTraceGaps(NightSignalSeries(readings: readings), start, end),
      isEmpty,
    );
    expect(
      nightTraceGaps(
        NightSignalSeries(
          readings: [
            NightSignalReading(start, 54),
            NightSignalReading(end, 55),
          ],
          maxConnectingGap: const Duration(minutes: 10),
        ),
        start,
        end,
      ),
      isEmpty,
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets('sleep target labels do not overlap at 375 pt $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      for (final scale in [1.0, 1.3]) {
        for (final goal in [300, 465, 600, 720]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: openBandTheme(brightness),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: OBSleepLead(minutes: 438, goalMinutes: goal),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final label = tester.getRect(
            find.text('Ziel ${obSleepDuration(goal)}'),
          );
          expect(
            label.left,
            greaterThan(tester.getRect(find.text('0 h')).right),
          );
          expect(label.right, lessThan(tester.getRect(find.text('10 h')).left));
          expect(tester.takeException(), isNull);
        }
      }
    });

    testWidgets(
      'sleep navigation and all night segments fit 375×812 $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final repo = _NoNapsRepo();
        final controller = OpenBandController(
          repository: repo,
          initialDay: '2026-09-29',
          now: () => DateTime(2026, 9, 29, 10),
        );
        addTearDown(controller.dispose);
        await controller.refresh();
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        Future<void> frame(Widget child) async {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(
            MaterialApp(theme: openBandTheme(brightness), home: child),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }

        await frame(
          G3SleepScreen(
            controller: controller,
            scrollController: scroll,
            reminder: MemorySleepBedtimeReminder(),
          ),
        );
        await tester.tap(find.text('NACHT'));
        await tester.pumpAndSettle();
        expect(find.byType(G3SleepNightSignals), findsOneWidget);
        expect(tester.takeException(), isNull);
        for (final segment in ['HRV', 'Atemfrequenz', 'Puls']) {
          await tester.tap(find.text(segment).first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.textContaining('tiefster'), findsOneWidget);
          expect(find.textContaining('Ø Schlaf'), findsNothing);
          expect(find.text('Optisches Signal verwertbar'), findsNothing);
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -350),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, 700),
          );
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Schlaf'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Zeiten ändern'));
        await tester.pumpAndSettle();
        expect(find.byType(SleepEditor), findsOneWidget);
        expect(tester.takeException(), isNull);
        await frame(
          G3SleepScreen(
            controller: controller,
            scrollController: scroll,
            reminder: MemorySleepBedtimeReminder(),
          ),
        );
        await tester.scrollUntilVisible(
          find.text('Noch keins erkannt'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final emptyNap = find.ancestor(
          of: find.text('Noch keins erkannt'),
          matching: find.byType(OBListRow),
        );
        expect(
          find.descendant(of: emptyNap, matching: find.byType(OBChevron)),
          findsOneWidget,
        );
        await tester.tap(find.text('Noch keins erkannt'));
        await tester.pumpAndSettle();
        expect(find.byType(G3SleepNaps), findsOneWidget);
        expect(tester.takeException(), isNull);
        for (final detail in <Widget>[
          G3SleepRegularity(repository: repo, day: '2026-09-29'),
          G3SleepDebtDetail(repository: repo, day: '2026-09-29'),
        ]) {
          await frame(detail);
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -500),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
}
