import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/compute/manual_session.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/g3/screens/training_live.dart';
import 'package:openstrap_edge/openband/g3/screens/training_manual.dart';
import 'package:openstrap_edge/openband/g3/screens/training_screen.dart';
import 'package:openstrap_edge/openband/g3/charts.dart';
import 'package:openstrap_edge/openband/g3/chrome.dart'
    show OBActionPrimary, OBActionSecondary, OBListRow, OBSheet;
import 'package:openstrap_edge/openband/g3/chrome.dart'
    as g3chrome
    show OBPageHeader;
import 'package:openstrap_edge/openband/g3/training_parts.dart';
import 'package:openstrap_edge/openband/run_live.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';

Map<String, dynamic> _fixture(String name) => Map<String, dynamic>.from(
  jsonDecode(
        File('docs/openband5/assets/fixtures/$name.json').readAsStringSync(),
      )
      as Map,
);

class _CountingSuggestionRepo extends SyntheticOpenBandRepository {
  _CountingSuggestionRepo()
    : super.fromMaps(
        _fixture('day-summary'),
        _fixture('sleep-detail'),
        scenario: SyntheticScenario.g3Sample,
      );
  int confirms = 0, changes = 0;
  String? confirmedSport;
  Completer<void>? gate;

  @override
  Future<String> confirmSuggestion(String id, {String? sport}) async {
    confirms++;
    confirmedSport = sport;
    await gate?.future;
    return super.confirmSuggestion(id, sport: sport);
  }

  @override
  Future<void> changeSuggestionSport(String id, String sport) async {
    changes++;
    await super.changeSuggestionSport(id, sport);
  }
}

class _NoWeekRepo extends SyntheticOpenBandRepository {
  _NoWeekRepo()
    : super.fromMaps(
        _fixture('day-summary'),
        _fixture('sleep-detail'),
        scenario: SyntheticScenario.g3Sample,
      );

  @override
  Future<List<G3Activity>> readActivities(String day) async => const [];

  @override
  Future<G3WeeklyLoad> readWeeklyLoad(String endDay) async => G3WeeklyLoad([
    for (final day in g3DaysEnding(endDay, 7)) MetricPoint(day, null),
  ]);
}

SyntheticOpenBandRepository _repo(SyntheticScenario scenario) =>
    SyntheticOpenBandRepository.fromMaps(
      _fixture('day-summary'),
      _fixture('sleep-detail'),
      scenario: scenario,
    );

Widget _app(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: openBandTheme(brightness),
      home: Scaffold(body: child),
    );

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
    await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
          rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
        ))
        .load();
  });

  testWidgets('stored zone minutes render without a trace', (tester) async {
    final repo = _repo(SyntheticScenario.g3Sample);
    final start = DateTime(2026, 9, 29, 8);
    final activity = G3Activity(
      id: 'stored-no-trace',
      sport: 'running',
      source: G3ActivitySource.manual,
      confirmed: true,
      start: start,
      end: start.add(const Duration(minutes: 30)),
      zoneMinutes: const [2, 4, 6, 8, 10],
      zoneBasis: const G3ZoneBasis(G3ZoneBasisKind.hfmaxEstimated, 186),
    );
    await tester.pumpWidget(
      _app(G3ActivityScreen(repository: repo, activity: activity)),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.textContaining('HFmax 186'));
    expect(find.textContaining('HFmax 186'), findsOneWidget);
    expect(find.text('10 Min.'), findsOneWidget);
  });

  test('synthetic run trace follows the reported 42-minute session', () async {
    final activity = (await _repo(
      SyntheticScenario.g3Sample,
    ).readActivities('2026-09-29')).single;
    final trace = activity.hrTrace;
    expect(trace, hasLength(84));
    expect(trace.first.at, activity.start);
    expect(trace.last.at, activity.end!.subtract(const Duration(seconds: 30)));
    for (var i = 1; i < trace.length; i++) {
      expect(
        trace[i].at.difference(trace[i - 1].at),
        const Duration(seconds: 30),
      );
    }

    final gap = activity.signalGaps.single;
    final absent = [
      for (final point in trace)
        if (point.meanBpm == null) point.at,
    ];
    expect(absent, [gap.start, gap.start.add(const Duration(seconds: 30))]);
    expect(absent.last.isBefore(gap.end), isTrue);

    final bpm = [for (final point in trace) point.meanBpm];
    final valid = bpm.whereType<double>().toList();
    expect(
      valid.reduce((a, b) => a + b) / valid.length,
      closeTo(activity.avgHr!, .25),
    );
    expect(valid.reduce((a, b) => a > b ? a : b), activity.maxHr);
    expect(bpm.first!, lessThan(130));
    expect(bpm[11]!, greaterThan(bpm.first!));
    final steady = bpm.skip(12).take(56).whereType<double>().toList();
    expect(steady.reduce((a, b) => a < b ? a : b), lessThanOrEqualTo(145));
    expect(steady.reduce((a, b) => a > b ? a : b), greaterThanOrEqualTo(153));
    expect(bpm.indexOf(176), inInclusiveRange(68, 78));
  });

  testWidgets('result lead separates minutes and names the session strain', (
    tester,
  ) async {
    final repo = _repo(SyntheticScenario.g3Sample);
    final activity = (await repo.readActivities('2026-09-29')).single;
    await tester.pumpWidget(
      _app(G3ActivityScreen(repository: repo, activity: activity)),
    );
    await tester.pumpAndSettle();
    expect(find.text(' Min.'), findsOneWidget);
    expect(find.text('diese Einheit'), findsOneWidget);
  });

  testWidgets('Karvonen zones identify pulsreserve', (tester) async {
    final repo = _repo(SyntheticScenario.g3Sample);
    final start = DateTime(2026, 9, 29, 8);
    final activity = G3Activity(
      id: 'reserve',
      sport: 'cycling',
      source: G3ActivitySource.manual,
      confirmed: true,
      start: start,
      end: start.add(const Duration(minutes: 30)),
      zoneMinutes: const [1, 2, 3, 4, 5],
      zoneBasis: const G3ZoneBasis(G3ZoneBasisKind.heartRateReserve, 191),
    );
    await tester.pumpWidget(
      _app(G3ActivityScreen(repository: repo, activity: activity)),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('% Pulsreserve'));
    expect(find.text('% Pulsreserve'), findsOneWidget);
    expect(
      find.text('Pulsreserve (Karvonen) · aus deinen Zonen'),
      findsOneWidget,
    );
    expect(find.textContaining('HFmax 191'), findsNothing);
    expect(find.textContaining('70–80 %'), findsNothing);
  });

  testWidgets('observed HFmax names the measured stored ceiling', (
    tester,
  ) async {
    final repo = _repo(SyntheticScenario.g3Sample);
    final start = DateTime(2026, 9, 29, 8);
    final activity = G3Activity(
      id: 'observed-basis',
      sport: 'cycling',
      source: G3ActivitySource.manual,
      confirmed: true,
      start: start,
      end: start.add(const Duration(minutes: 30)),
      zoneMinutes: const [1, 2, 3, 4, 5],
      zoneBasis: const G3ZoneBasis(G3ZoneBasisKind.hfmaxObserved, 191),
    );
    await tester.pumpWidget(
      _app(G3ActivityScreen(repository: repo, activity: activity)),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.textContaining('HFmax 191'));
    expect(find.text('% HFmax'), findsOneWidget);
    expect(find.text('HFmax 191 · gemessen'), findsOneWidget);
  });

  testWidgets('Kraft quick start uses the sets catalogue sport key', (
    tester,
  ) async {
    final repo = _repo(SyntheticScenario.g3Sample);
    final controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-29',
      band: repo.band,
      now: () => DateTime(2026, 9, 29, 9, 41),
    );
    addTearDown(controller.dispose);
    String? started;
    await tester.pumpWidget(
      _app(
        G3TrainingScreen(controller: controller, onStart: (s) => started = s),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Training starten'));
    await tester.pumpAndSettle();
    expect(find.byType(OBSheet), findsOneWidget);
    expect(find.text('Weitere …'), findsOneWidget);
    await tester.tap(find.text('Kraft'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Starten'));
    await tester.pumpAndSettle();
    expect(started, 'weight_training');
  });

  testWidgets('unknown basis keeps minutes and suppresses percentages', (
    tester,
  ) async {
    final repo = _repo(SyntheticScenario.g3Sample);
    final start = DateTime(2026, 9, 29, 8);
    final activity = G3Activity(
      id: 'unknown-basis',
      sport: 'cycling',
      source: G3ActivitySource.manual,
      confirmed: true,
      start: start,
      end: start.add(const Duration(minutes: 30)),
      zoneMinutes: const [1, 2, 3, 4, 5],
    );
    await tester.pumpWidget(
      _app(G3ActivityScreen(repository: repo, activity: activity)),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Grundlage unbekannt'));
    expect(find.text('Grundlage unbekannt'), findsOneWidget);
    expect(find.text('5 Min.'), findsOneWidget);
    expect(find.textContaining('% HFmax'), findsNothing);
    expect(find.textContaining('% Pulsreserve'), findsNothing);
    expect(find.textContaining('70–80 %'), findsNothing);
  });

  testWidgets('manual session without band pulse names the missing source', (
    tester,
  ) async {
    final repo = _repo(SyntheticScenario.g3Sample);
    final start = DateTime(2026, 9, 29, 8);
    await tester.pumpWidget(
      _app(
        G3ActivityScreen(
          repository: repo,
          activity: G3Activity(
            id: 'manual-no-hr',
            sport: 'swimming',
            source: G3ActivitySource.manual,
            confirmed: true,
            start: start,
            end: start.add(const Duration(minutes: 45)),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Kein Bandpuls in diesem Zeitraum.'));
    expect(find.text('Kein Bandpuls in diesem Zeitraum.'), findsOneWidget);
    expect(find.textContaining('ruhiges Ende'), findsNothing);
  });

  test('a trace stroke breaks at a gap with no sample inside', () {
    expect(hrTraceStrokeRuns([(0, 120), (5, 140), (10, 150)], [(6, 8)]), [
      [(0.0, 120.0), (5.0, 140.0)],
      [(10.0, 150.0)],
    ]);
  });

  test('trace peak never comes from a gap', () {
    expect(hrTraceVisiblePeak([(1, 140), (2.5, 190), (4, 150)], [(2, 3)]), (
      4.0,
      150.0,
    ));
  });

  test('signal strip uses the stored gap intervals', () {
    expect(signalSegmentsFromGaps(10, [(2, 3), (7, 7.5)]), [
      (120, false),
      (60, true),
      (240, false),
      (30, true),
      (150, false),
    ]);
    expect(signalSegmentsFromGaps(5, [(1, 2), (1.5, 3)]), [
      (60, false),
      (120, true),
      (120, false),
    ]);
  });

  testWidgets('mini bar labels a paused engine interval honestly', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        OBSessionMiniBar(
          sport: 'cycling',
          elapsed: '12:30',
          heartRate: 141,
          zone: 3,
          paused: true,
          onTap: () {},
        ),
      ),
    );
    expect(find.text('Rad pausiert · 12:30'), findsOneWidget);
    expect(find.text('Puls zählt nicht mit'), findsOneWidget);
    expect(find.textContaining('Zone 3'), findsNothing);
  });

  testWidgets('live stats show measured mean and max separately', (
    tester,
  ) async {
    final run = ValueNotifier(
      const LiveRun(
        elapsedSec: 120,
        heartRate: 136,
        averageHr: 128,
        maxHrSeen: 158,
      ),
    );
    addTearDown(run.dispose);
    await tester.pumpWidget(
      _app(
        G3LiveRun(
          run: run,
          sport: 'cycling',
          onPause: () {},
          onResume: () {},
          onFinish: () async {},
        ),
      ),
    );
    expect(find.text('Ø PULS'), findsOneWidget);
    expect(find.text('128'), findsOneWidget);
    expect(find.text('max 158'), findsOneWidget);
  });

  testWidgets('live header uses the engine start time', (tester) async {
    final run = ValueNotifier(
      LiveRun(elapsedSec: 120, startedAt: DateTime(2026, 9, 29, 17, 40)),
    );
    addTearDown(run.dispose);
    await tester.pumpWidget(
      _app(
        G3LiveRun(
          run: run,
          sport: 'cycling',
          onPause: () {},
          onResume: () {},
          onFinish: () async {},
        ),
      ),
    );
    expect(find.text('seit 17:40'), findsOneWidget);
  });

  testWidgets('pause copy remains true when band pulse disappears', (
    tester,
  ) async {
    final run = ValueNotifier(const LiveRun(elapsedSec: 120, paused: true));
    addTearDown(run.dispose);
    await tester.pumpWidget(
      _app(
        G3LiveRun(
          run: run,
          sport: 'cycling',
          onPause: () {},
          onResume: () {},
          onFinish: () async {},
        ),
      ),
    );
    expect(find.text('Puls zählt nicht mit'), findsOneWidget);
    expect(find.textContaining('Band fester anlegen'), findsNothing);
  });

  testWidgets(
    'unconfirmed detection withholds zones, then confirmation reveals stored zones',
    (tester) async {
      final repo = _repo(SyntheticScenario.g3Sample);
      final activity = (await repo.readActivities('2026-09-29')).single;
      await tester.pumpWidget(
        _app(G3ActivityScreen(repository: repo, activity: activity)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Zonen nach Bestätigung'), findsWidgets);
      expect(find.textContaining('HFmax 186'), findsNothing);
      await tester.tap(find.text('Stimmt'));
      await tester.pumpAndSettle();
      expect(find.textContaining('HFmax 186'), findsOneWidget);
    },
  );

  testWidgets('unknown detected sport remains generic and can be changed', (
    tester,
  ) async {
    final repo = _repo(SyntheticScenario.g3Sample);
    final base = (await repo.readActivities('2026-09-29')).single;
    final unknown = G3Activity(
      id: base.id,
      sport: 'unmapped_sensor_code',
      source: G3ActivitySource.auto,
      confirmed: false,
      start: base.start,
      end: base.end,
    );
    await tester.pumpWidget(
      _app(G3ActivityScreen(repository: repo, activity: unknown)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Aktivität'), findsWidgets);
    expect(find.text('unmapped_sensor_code'), findsNothing);
    expect(find.text('BELASTUNG'), findsOneWidget);
    expect(find.text('Zonen nach Bestätigung'), findsWidgets);
    await tester.tap(find.text('Ändern'));
    await tester.pumpAndSettle();
    final dismiss = find.ancestor(
      of: find.text('Kein Training'),
      matching: find.byType(OBActionSecondary),
    );
    expect(dismiss, findsOneWidget);
    expect(
      find.descendant(
        of: dismiss,
        matching: find.byIcon(LucideIcons.chevronRight),
      ),
      findsNothing,
    );
    expect(find.text('Rad'), findsWidgets);
    await tester.tap(find.text('Rad'));
    await tester.pump();
    await tester.ensureVisible(find.text('Als Rad speichern'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Als Rad speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Rad'), findsWidgets);
    expect(find.textContaining('HFmax 186'), findsOneWidget);
  });

  testWidgets('changing sport confirms once with the selected sport', (
    tester,
  ) async {
    final repo = _CountingSuggestionRepo();
    final activity = (await repo.readActivities('2026-09-29')).single;
    await tester.pumpWidget(
      _app(G3ActivityScreen(repository: repo, activity: activity)),
    );
    await tester.tap(find.text('Ändern'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rad').first);
    await tester.pump();
    await tester.ensureVisible(find.text('Als Rad speichern'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Als Rad speichern'));
    await tester.pumpAndSettle();
    expect(repo.confirms, 1);
    expect(repo.confirmedSport, 'cycling');
    expect(repo.changes, 0);
  });

  testWidgets('confirmation tap is latched while the write is pending', (
    tester,
  ) async {
    final repo = _CountingSuggestionRepo()..gate = Completer<void>();
    final activity = (await repo.readActivities('2026-09-29')).single;
    await tester.pumpWidget(
      _app(G3ActivityScreen(repository: repo, activity: activity)),
    );
    await tester.tap(find.text('Stimmt'));
    await tester.pump();
    expect(
      tester
          .widget<OBActionPrimary>(find.byType(OBActionPrimary).first)
          .onPressed,
      isNull,
    );
    expect(repo.confirms, 1);
    repo.gate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('Heute can open a result route with a stored activity', (
    tester,
  ) async {
    final repo = _repo(SyntheticScenario.g3Sample);
    final activity = (await repo.readActivities('2026-09-29')).single;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(
              context,
            ).push(g3ActivityResultRoute(repository: repo, activity: activity)),
            child: const Text('Öffnen'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
    expect(find.text('Zonen nach Bestätigung'), findsWidgets);
  });

  testWidgets('Kein Training removes the suggestion but preserves the day', (
    tester,
  ) async {
    final repo = _repo(SyntheticScenario.g3Sample);
    final activity = (await repo.readActivities('2026-09-29')).single;
    final dayBefore = await repo.readDay('2026-09-29');
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(
              context,
            ).push(g3ActivityResultRoute(repository: repo, activity: activity)),
            child: const Text('Öffnen'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ändern'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Kein Training'));
    await tester.tap(find.text('Kein Training'));
    await tester.pumpAndSettle();
    expect(find.text('Kein Training?'), findsOneWidget);
    await tester.tap(find.text('Kein Training').last);
    await tester.pumpAndSettle();
    expect(await repo.readActivities('2026-09-29'), isEmpty);
    expect(
      (await repo.readDay('2026-09-29')).strain.value,
      dayBefore.strain.value,
    );
  });

  testWidgets('sport picker remains scrollable at large text', (tester) async {
    tester.view.physicalSize = const Size(786, 1702);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final repo = _repo(SyntheticScenario.g3Sample);
    final activity = (await repo.readActivities('2026-09-29')).single;
    await tester.pumpWidget(
      _app(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: G3ActivityScreen(repository: repo, activity: activity),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ändern'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Als Lauf speichern'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing training load renders refusal and no synthetic number', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Center(
          child: SizedBox(
            width: 350,
            child: OBTrainingLoad(load: G3WeeklyLoad([])),
          ),
        ),
      ),
    );
    expect(find.text('Trainingslast noch nicht berechnet'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2));
    expect(find.text('64'), findsNothing);
    expect(find.textContaining('14 Tage'), findsNothing);
  });

  testWidgets('stored load refusal shows the remaining days', (tester) async {
    await tester.pumpWidget(
      _app(
        const Center(
          child: SizedBox(
            width: 350,
            child: OBTrainingLoad(
              load: G3WeeklyLoad(
                [],
                refusalNote: 'need_baseline:have=11,need=14',
                daysHave: 11,
                daysNeed: 14,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Noch keine Trainingslast'), findsOneWidget);
    expect(find.text('11 von 14 Tagen · noch 3 Tage'), findsOneWidget);
  });

  testWidgets('stored load refusal uses Tag when one day is needed', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Center(
          child: SizedBox(
            width: 350,
            child: OBTrainingLoad(
              load: G3WeeklyLoad(
                [],
                refusalNote: 'need_baseline:have=0,need=1',
                daysHave: 0,
                daysNeed: 1,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('0 von 1 Tag · noch 1 Tag'), findsOneWidget);
  });

  testWidgets('ready training load has no invented comparison bars', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Center(
          child: SizedBox(
            width: 350,
            child: OBTrainingLoad(load: G3WeeklyLoad([], atl: 64, ctl: 51)),
          ),
        ),
      ),
    );
    expect(find.text('64'), findsOneWidget);
    expect(find.text('51'), findsOneWidget);
    expect(find.text('Letzte Woche mehr als gewohnt.'), findsOneWidget);
    expect(find.byType(FractionallySizedBox), findsNothing);
  });

  testWidgets(
    'weak live signal keeps pulse and zone absent while finish remains reachable',
    (tester) async {
      final run = ValueNotifier(const LiveRun(elapsedSec: 60));
      addTearDown(run.dispose);
      await tester.pumpWidget(
        _app(
          G3LiveRun(
            run: run,
            sport: 'running',
            onPause: () {},
            onResume: () {},
            onFinish: () async {},
          ),
        ),
      );
      expect(find.text('Kein verlässlicher Bandpuls'), findsOneWidget);
      expect(find.text('Zone — · HFmax-Grundlage fehlt'), findsNothing);
      expect(find.text('Beenden'), findsOneWidget);
      await tester.tap(find.text('Beenden'));
      await tester.pump();
      expect(find.text('Speichern'), findsOneWidget);
    },
  );

  testWidgets('live zones follow reserve bands and show below zone one', (
    tester,
  ) async {
    final set = ana.HeartRateZoneSet(
      source: 'karvonen',
      maxHr: 191,
      zones: [
        for (var i = 0; i < 5; i++)
          ana.HeartRateZone(
            number: i + 1,
            lower: 110 + i * 20,
            upper: 130 + i * 20,
            lowerPct: .5 + i * .1,
            upperPct: .6 + i * .1,
          ),
      ],
    );
    final run = ValueNotifier(
      LiveRun(elapsedSec: 60, heartRate: 141, zone: 2, zoneSet: set),
    );
    addTearDown(run.dispose);
    await tester.pumpWidget(
      _app(
        G3LiveRun(
          run: run,
          sport: 'cycling',
          onPause: () {},
          onResume: () {},
          onFinish: () async {},
        ),
      ),
    );
    expect(find.textContaining('130–150 /min'), findsOneWidget);
    expect(find.textContaining('% Pulsreserve'), findsOneWidget);
    run.value = LiveRun(elapsedSec: 61, heartRate: 104, zone: 0, zoneSet: set);
    await tester.pump();
    expect(find.text('unter Zone 1'), findsOneWidget);
    expect(find.text('Zonen: Grundlage unbekannt'), findsNothing);
  });

  testWidgets('unknown live zone basis leaves every meter slot neutral', (
    tester,
  ) async {
    final run = ValueNotifier(
      const LiveRun(elapsedSec: 60, heartRate: 154, zone: 3),
    );
    addTearDown(run.dispose);
    await tester.pumpWidget(
      _app(
        G3LiveRun(
          run: run,
          sport: 'running',
          onPause: () {},
          onResume: () {},
          onFinish: () async {},
        ),
      ),
    );
    expect(find.text('Zonen: Grundlage unbekannt'), findsOneWidget);
    for (var i = 1; i <= 5; i++) {
      expect(
        tester.widget<Text>(find.text('Z$i')).style?.fontWeight,
        FontWeight.w400,
      );
    }
    final slots = tester
        .widgetList<Container>(find.byType(Container))
        .where(
          (widget) =>
              widget.constraints?.maxHeight == 10 &&
              widget.decoration is BoxDecoration,
        );
    expect(slots, hasLength(5));
    expect(
      slots.map((slot) => (slot.decoration! as BoxDecoration).color).toSet(),
      hasLength(1),
    );
  });

  testWidgets('live average pulse appears only when the engine provides it', (
    tester,
  ) async {
    final run = ValueNotifier(const LiveRun(elapsedSec: 962, heartRate: 154));
    addTearDown(run.dispose);
    await tester.pumpWidget(
      _app(
        G3LiveRun(
          run: run,
          sport: 'running',
          onPause: () {},
          onResume: () {},
          onFinish: () async => throw StateError('disk'),
        ),
      ),
    );
    expect(find.text('Ø PULS'), findsNothing);

    run.value = const LiveRun(elapsedSec: 963, heartRate: 154, averageHr: 141);
    await tester.pump();
    expect(find.text('Ø PULS'), findsOneWidget);
    expect(find.text('141'), findsOneWidget);

    run.value = const LiveRun(elapsedSec: 964, heartRate: 154);
    await tester.pump();
    await tester.tap(find.text('Beenden'));
    await tester.pump();
    expect(find.text('Ø PULS'), findsNothing);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Ø PULS'), findsNothing);
  });

  testWidgets('discard asks before invoking session teardown', (tester) async {
    final run = ValueNotifier(const LiveRun(elapsedSec: 60));
    addTearDown(run.dispose);
    var discarded = false;
    await tester.pumpWidget(
      _app(
        G3LiveRun(
          run: run,
          sport: 'cycling',
          onPause: () {},
          onResume: () {},
          onFinish: () async {},
          onDiscard: () async {
            discarded = true;
          },
        ),
      ),
    );
    await tester.tap(find.text('Beenden'));
    await tester.pump();
    await tester.tap(find.text('Verwerfen'));
    await tester.pumpAndSettle();
    expect(find.text('Einheit verwerfen?'), findsOneWidget);
    expect(discarded, isFalse);
    await tester.tap(find.text('Verwerfen').last);
    await tester.pumpAndSettle();
    expect(discarded, isTrue);
  });

  testWidgets('failed live save remains available for retry', (tester) async {
    final run = ValueNotifier(
      LiveRun(
        elapsedSec: 60,
        heartRate: 135,
        zone: 3,
        zoneSet: ana.HeartRateZones.zonesFromMaxHr(186, source: 'tanaka'),
      ),
    );
    addTearDown(run.dispose);
    await tester.pumpWidget(
      _app(
        G3LiveRun(
          run: run,
          sport: 'cycling',
          onPause: () {},
          onResume: () {},
          onFinish: () async {
            throw StateError('disk');
          },
        ),
      ),
    );
    await tester.tap(find.text('Beenden'));
    await tester.pump();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.textContaining('bleibt auf diesem iPhone'), findsOneWidget);
    expect(find.text('Erneut speichern'), findsOneWidget);
  });

  testWidgets('manual flow reaches review with no invented strain', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(G3ManualFlow(now: () => DateTime(2026, 9, 29, 9, 41))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weiter mit Yoga'));
    await tester.pump();
    expect(find.text('Schritt 2 von 3'), findsOneWidget);
    await tester.tap(find.text('Weiter'));
    await tester.pump();
    expect(find.text('Schritt 3 von 3'), findsOneWidget);
    expect(find.textContaining('Belastung —'), findsOneWidget);
  });

  testWidgets('Nachtragen title stays on one line at 375 pt and 2× text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: G3ManualFlow(now: () => DateTime(2026, 9, 29, 9, 41)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final title = tester.renderObject<RenderParagraph>(find.text('NACHTRAGEN'));
    expect(
      title.size.height,
      lessThanOrEqualTo(title.preferredLineHeight * 1.2),
    );
    expect(title.didExceedMaxLines, isFalse);
    expect(find.byTooltip('Abbrechen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Nachtragen omits Zuletzt without recent activity evidence', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        G3ManualFlow(
          now: () => DateTime(2026, 9, 29, 9, 41),
          initialSpans: const [],
        ),
      ),
    );
    expect(find.text('ZULETZT'), findsNothing);
    expect(find.text('Lauf'), findsOneWidget);
  });

  testWidgets(
    'Nachtragen takes recent sports from activities without duplicates',
    (tester) async {
      await tester.pumpWidget(
        _app(
          G3ManualFlow(
            now: () => DateTime(2026, 9, 29, 9, 41),
            recentRepository: _repo(SyntheticScenario.g3Sample),
            initialSpans: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ZULETZT'), findsOneWidget);
      expect(find.text('Lauf'), findsOneWidget);
      expect(find.text('Rad'), findsOneWidget);
      expect(find.text('ALLE SPORTARTEN'), findsOneWidget);
      final grids = find.byType(GridView);
      expect(grids, findsNWidgets(2));
      expect(
        find.descendant(of: grids.first, matching: find.text('Lauf')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: grids.first, matching: find.text('Rad')),
        findsNothing,
      );
      expect(
        find.descendant(of: grids.last, matching: find.text('Rad')),
        findsOneWidget,
      );
    },
  );

  testWidgets('Yoga uses a Lucide flower rather than the sport silhouette', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(trainingSportIcon('yoga', color: Colors.black)),
    );
    expect(tester.widget<Icon>(find.byType(Icon)).icon, LucideIcons.flower2);
  });

  testWidgets('live Training header stays on one line at 375 pt and 2× text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final run = ValueNotifier(const LiveRun(elapsedSec: 60));
    addTearDown(run.dispose);
    await tester.pumpWidget(
      _app(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: G3LiveRun(
            run: run,
            sport: 'martial_arts',
            onPause: () {},
            onResume: () {},
            onFinish: () async {},
          ),
        ),
      ),
    );
    final title = tester.renderObject<RenderParagraph>(
      find.text('KAMPFSPORT · LÄUFT'),
    );
    expect(
      title.size.height,
      lessThanOrEqualTo(title.preferredLineHeight * 1.2),
    );
    expect(title.didExceedMaxLines, isFalse);
  });

  testWidgets('load detail title stays on one line at 375 pt and 2× text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: g3chrome.OBPageHeader.detail(
            title: 'BELASTUNG',
            backLabel: 'Training',
            onBack: () {},
          ),
        ),
      ),
    );
    final title = tester.renderObject<RenderParagraph>(find.text('BELASTUNG'));
    expect(
      title.size.height,
      lessThanOrEqualTo(title.preferredLineHeight * 1.2),
    );
    expect(title.didExceedMaxLines, isFalse);
  });

  testWidgets('overlap review cannot offer a second save', (tester) async {
    final existingStart = DateTime(2026, 9, 29, 7, 58);
    final existingEnd = DateTime(2026, 9, 29, 8, 40);
    await tester.pumpWidget(
      _app(
        G3ManualFlow(
          now: () => DateTime(2026, 9, 29, 9, 41),
          initialStep: 2,
          initialStart: DateTime(2026, 9, 29, 7, 50),
          initialEnd: DateTime(2026, 9, 29, 8, 35),
          initialSpans: [
            SessionSpan(
              'run',
              existingStart.millisecondsSinceEpoch ~/ 1000,
              existingEnd.millisecondsSinceEpoch ~/ 1000,
            ),
          ],
        ),
      ),
    );
    expect(find.text('Zeitraum schon erfasst'), findsOneWidget);
    expect(find.text('Speichern'), findsNothing);
    await tester.tap(find.text('Zeit ändern'));
    await tester.pump();
    expect(find.text('Schritt 2 von 3'), findsOneWidget);
  });

  testWidgets('manual date picker does not update a removed flow', (
    tester,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        theme: openBandTheme(Brightness.light),
        home: const Scaffold(body: Text('root')),
      ),
    );
    final route = MaterialPageRoute<void>(
      builder: (_) =>
          G3ManualFlow(now: () => DateTime(2026, 9, 29, 9, 41), initialStep: 1),
    );
    nav.currentState!.push(route);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tag'));
    await tester.pumpAndSettle();
    nav.currentState!.removeRoute(route);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual time picker does not update a removed flow', (
    tester,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        theme: openBandTheme(Brightness.light),
        home: const Scaffold(body: Text('root')),
      ),
    );
    final route = MaterialPageRoute<void>(
      builder: (_) =>
          G3ManualFlow(now: () => DateTime(2026, 9, 29, 9, 41), initialStep: 1),
    );
    nav.currentState!.push(route);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beginn'));
    await tester.pumpAndSettle();
    nav.currentState!.removeRoute(route);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('root opens the stored suggestion result', (tester) async {
    final repo = _repo(SyntheticScenario.g3Sample);
    final controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-29',
      band: repo.band,
      now: () => DateTime(2026, 9, 29, 9, 41),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(G3TrainingScreen(controller: controller)));
    await tester.pumpAndSettle();
    expect(find.text('9,4'), findsWidgets);
    expect(find.text('Sportart richtig?'), findsOneWidget);
    expect(find.text('Belastung im Verlauf'), findsNothing);
    await tester.tap(find.text('Lauf').first);
    await tester.pumpAndSettle();
    expect(find.text('PULSERHOLUNG'), findsOneWidget);
  });

  testWidgets('quick start exposes the finishable other sport path', (
    tester,
  ) async {
    final repo = _repo(SyntheticScenario.g3Sample);
    final controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-29',
      band: repo.band,
      now: () => DateTime(2026, 9, 29, 9, 41),
    );
    addTearDown(controller.dispose);
    String? started;
    await tester.pumpWidget(
      _app(
        G3TrainingScreen(
          controller: controller,
          onStart: (sport) => started = sport,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Training starten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weitere …'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sonstiges'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sonstiges'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Starten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Starten'));
    await tester.pumpAndSettle();
    expect(started, 'other');
  });

  testWidgets('scrolled Training keeps a compact header above the list', (
    tester,
  ) async {
    final repo = _repo(SyntheticScenario.g3Sample);
    final controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-29',
      band: repo.band,
      now: () => DateTime(2026, 9, 29, 9, 41),
    );
    final scroll = ScrollController(initialScrollOffset: 505);
    addTearDown(controller.dispose);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _app(G3TrainingScreen(controller: controller, scrollController: scroll)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Synthetische Daten'), findsOneWidget);
    expect(find.text('Di 29.09 · Synthetische Daten'), findsOneWidget);
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.textContaining('Synthetische Daten'), findsNothing);
  });

  testWidgets('Training lead and load keep method copy off the overview', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      _app(
        ListView(
          children: [
            OBLoadLead(
              value: 9.4,
              countTime: '09:38',
              onTap: () => opened = true,
            ),
            OBTrainingLoad(
              load: const G3WeeklyLoad([], atl: 64, ctl: 51),
              onMethod: () => opened = true,
            ),
          ],
        ),
      ),
    );
    expect(find.text('Tagessumme 0–21'), findsNothing);
    expect(find.textContaining('gezählt bis'), findsNothing);
    expect(find.text('Tag läuft'), findsOneWidget);
    expect(find.text('TRIMP'), findsNothing);
    expect(find.text('Tägliches TRIMP · eigene Einheit'), findsNothing);
    expect(find.text('AKUT · 7 TAGE'), findsOneWidget);
    expect(find.text('GEWOHNT · 6 WOCHEN'), findsOneWidget);
    await tester.tap(find.text('Methode ›'));
    expect(opened, isTrue);
  });

  testWidgets('load period labels fit at large text on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: const Center(
            child: OBTrainingLoad(load: G3WeeklyLoad([], atl: 64, ctl: 51)),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('AKUT · 7 TAGE'), findsOneWidget);
    expect(find.text('GEWOHNT · 6 WOCHEN'), findsOneWidget);
  });

  testWidgets('load detail explains scale and has no dead lead chevron', (
    tester,
  ) async {
    final repo = _repo(SyntheticScenario.g3Sample);
    final controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-29',
      band: repo.band,
      now: () => DateTime(2026, 9, 29, 9, 41),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        G3LoadScreen(
          controller: controller,
          activity: null,
          weekly: const G3WeeklyLoad([]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(OBLoadLead),
        matching: find.byType(OBChevron),
      ),
      findsNothing,
    );
    await tester.tap(find.bySemanticsLabel('Erklärung'));
    await tester.pumpAndSettle();
    expect(find.textContaining('keinen persönlichen Bereich'), findsOneWidget);
    expect(find.textContaining('Wenig Tragezeit'), findsOneWidget);
  });

  testWidgets('result info works and synthetic activity is labelled', (
    tester,
  ) async {
    final repo = _repo(SyntheticScenario.g3Sample);
    final activity = (await repo.readActivities('2026-09-29')).single;
    await tester.pumpWidget(
      _app(G3ActivityScreen(repository: repo, activity: activity)),
    );
    await tester.pumpAndSettle();
    expect(find.text('EINHEIT'), findsOneWidget);
    expect(find.byIcon(LucideIcons.ellipsis), findsNothing);
    expect(find.text('SYNTHETISCHE DATEN'), findsOneWidget);
    expect(
      find.text('Wie stark der Puls in der ersten Minute nach dem Ende fällt.'),
      findsNothing,
    );
    await tester.tap(find.bySemanticsLabel('Erklärung'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pulserholung ist'), findsOneWidget);
  });

  testWidgets('detected sport uses a generic activity label and icon', (
    tester,
  ) async {
    expect(trainingSport('detected'), 'Aktivität');
    expect(trainingSport('unknown'), 'Aktivität');
    await tester.pumpWidget(
      _app(trainingSportIcon('detected', color: Colors.black)),
    );
    expect(find.byIcon(LucideIcons.activity), findsOneWidget);
  });

  testWidgets('Training clock follows the latest stored band value', (
    tester,
  ) async {
    final repo = _repo(SyntheticScenario.g3Sample);
    final controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-29',
      band: BandSnapshot(latestStoredAt: DateTime(2026, 9, 29, 9, 12)),
      now: () => DateTime(2026, 9, 29, 9, 41),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(G3TrainingScreen(controller: controller)));
    await tester.pumpAndSettle();
    expect(find.text('Daten bis 09:12'), findsOneWidget);
    expect(find.textContaining('Daten bis 09:38'), findsNothing);
  });

  testWidgets('live copy states pause once and keeps active time explicit', (
    tester,
  ) async {
    final run = ValueNotifier(const LiveRun(elapsedSec: 120, paused: true));
    addTearDown(run.dispose);
    await tester.pumpWidget(
      _app(
        G3LiveRun(
          run: run,
          sport: 'cycling',
          onPause: () {},
          onResume: () {},
          onFinish: () async {},
        ),
      ),
    );
    expect(find.text('RAD · PAUSIERT'), findsOneWidget);
    expect(find.text('Puls zählt nicht mit'), findsOneWidget);
    expect(find.text('aktive Zeit'), findsOneWidget);
    expect(find.text('angehalten'), findsNothing);
    run.value = const LiveRun(elapsedSec: 120);
    await tester.pump();
    expect(find.text('RAD · LÄUFT'), findsOneWidget);
    expect(find.text('auf dem iPhone'), findsOneWidget);
    expect(find.text('Einheit läuft auf dem iPhone'), findsNothing);
  });

  testWidgets('manual time fields use the shared tappable row', (tester) async {
    await tester.pumpWidget(
      _app(
        G3ManualFlow(now: () => DateTime(2026, 9, 29, 9, 41), initialStep: 1),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OBListRow), findsNWidgets(3));
    expect(find.text('Beginn'), findsOneWidget);
    expect(find.text('Ende'), findsOneWidget);
  });

  testWidgets('canonical light root golden', (tester) async {
    tester.view.physicalSize = const Size(786, 1702);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final repo = _repo(SyntheticScenario.g3Sample);
    final controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-29',
      band: repo.band,
      now: () => DateTime(2026, 9, 29, 9, 41),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(G3TrainingScreen(controller: controller)));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(G3TrainingScreen),
      matchesGoldenFile('openband_goldens/g3-training-root-light.png'),
    );
  }, tags: const ['golden']);

  testWidgets('missing week has no strain bars golden', (tester) async {
    tester.view.physicalSize = const Size(786, 1702);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final repo = _NoWeekRepo();
    final controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-29',
      band: repo.band,
      now: () => DateTime(2026, 9, 29, 9, 41),
    );
    final scroll = ScrollController(initialScrollOffset: 570);
    addTearDown(controller.dispose);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _app(G3TrainingScreen(controller: controller, scrollController: scroll)),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(G3TrainingScreen),
      matchesGoldenFile('openband_goldens/g3-training-missing-week.png'),
    );
  }, tags: const ['golden']);

  testWidgets('sport picker light golden', (tester) async {
    tester.view.physicalSize = const Size(786, 1702);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final repo = _repo(SyntheticScenario.g3Sample);
    final activity = (await repo.readActivities('2026-09-29')).single;
    await tester.pumpWidget(
      _app(G3ActivityScreen(repository: repo, activity: activity)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Ändern'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/g3-training-sport-picker-light.png'),
    );
  }, tags: const ['golden']);
}
