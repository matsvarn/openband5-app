import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/screens.dart';
import 'package:openstrap_edge/openband/sleep_plan.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';

final _fixture =
    jsonDecode(
          File(
            'docs/openband5/assets/fixtures/sleep-plan.json',
          ).readAsStringSync(),
        )
        as Map;
final _outputs = Map<String, dynamic>.from(_fixture['outputs'] as Map);

double get _needSec => (_outputs['need_seconds'] as num).toDouble();
double get _bedtimeMin => (_outputs['bedtime_minute'] as num).toDouble();
double get _wakeMin => (_outputs['wake_minute'] as num).toDouble();

const _day = '2026-09-15';
final _builtAt = DateTime(2026, 9, 15, 7, 42);
final _now = DateTime(2026, 9, 15, 9, 41);

Map<String, dynamic> _daySummary() => Map<String, dynamic>.from(
  jsonDecode(
        File(
          'docs/openband5/assets/fixtures/day-summary.json',
        ).readAsStringSync(),
      )
      as Map,
);

Map<String, dynamic> _sleepDetail() => Map<String, dynamic>.from(
  jsonDecode(
        File(
          'docs/openband5/assets/fixtures/sleep-detail.json',
        ).readAsStringSync(),
      )
      as Map,
);

class _PlanRepo extends SyntheticOpenBandRepository {
  _PlanRepo() : super.fromMaps(_daySummary(), _sleepDetail());

  int reads = 0;
  final days = <String>[];
  final clocks = <DateTime?>[];
  Completer<void>? gate;

  @override
  Future<SleepPlanSnapshot> readSleepPlan(String day, {DateTime? now}) async {
    reads++;
    days.add(day);
    clocks.add(now);
    final hold = gate;
    if (hold != null) await hold.future;
    return super.readSleepPlan(day, now: now);
  }
}

Map<String, dynamic> _artifact({
  String day = _day,
  DateTime? builtAt,
  int? algoVersion,
  double? need,
  double? bedtime,
  double? wake,
  double? nap = 0,
  double? strain = 3,
  bool times = true,
  bool includeBedtime = true,
  bool includeWake = true,
  bool window = true,
  bool provenance = true,
}) {
  final built = builtAt ?? _builtAt;
  final showBed = times && includeBedtime;
  final showWake = times && includeWake;
  final coach = <String, dynamic>{
    'need': {
      'value': {'need_sec': need ?? _needSec},
    },
    'nap_credit_min': nap ?? '—',
    'strain_bonus_min': strain ?? '—',
    'bedtime': showBed
        ? {
            'value': {'bedtime_min_of_day': bedtime ?? _bedtimeMin},
          }
        : '—',
    'wake': showWake
        ? {
            'value': {'wake_min_of_day': wake ?? _wakeMin},
          }
        : '—',
  };
  final end = DateTime.parse(day);
  final dates = [
    for (var i = 13; i >= 0; i--)
      dayLabel(DateTime(end.year, end.month, end.day - i)),
  ];
  return {
    'algo_version': algoVersion ?? kAlgoVersion,
    'built_for_day': day,
    'built_at_epoch': built.millisecondsSinceEpoch ~/ 1000,
    if (provenance)
      'input_read_started_at_ms': built.millisecondsSinceEpoch - 4000,
    'sleep_coach': coach,
    if (window) ...{
      'n_days': dates.length,
      'recent': [
        for (final date in dates) {'date': date},
      ],
    },
  };
}

int _inputReadMs([DateTime? builtAt]) =>
    (builtAt ?? _builtAt).millisecondsSinceEpoch - 4000;

List<String> _windowDays({String day = _day}) {
  final end = DateTime.parse(day);
  return [
    for (var i = 13; i >= 0; i--)
      dayLabel(DateTime(end.year, end.month, end.day - i)),
  ];
}

List<SleepPlanDayObservation> _observations({
  String day = _day,
  DateTime? builtAt,
}) {
  final inputRead = _inputReadMs(builtAt);
  return [
    for (final date in _windowDays(day: day))
      SleepPlanDayObservation(
        day: date,
        computedAtMs: inputRead - 1000,
        skipped: false,
        inFetchWindow: true,
      ),
  ];
}

String dayLabel(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year.toString().padLeft(4, '0')}-${two(dt.month)}-${two(dt.day)}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('de_DE');
    for (final font in [
      ('Inter', 'assets/fonts/Inter/Inter.ttf'),
      ('Inter Tight', 'assets/fonts/InterTight/InterTight[wght].ttf'),
      (
        'packages/lucide_icons_flutter/Lucide',
        'packages/lucide_icons_flutter/assets/lucide.ttf',
      ),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });

  late _PlanRepo repo;
  late DateTime clock;

  setUp(() {
    repo = _PlanRepo();
    clock = _now;
    repo.sleepPlanNow = () => clock;
    repo.sleepPlanArtifact = _artifact();
    repo.sleepPlanObservations = _observations();
    repo.sleepPlanJobs = const [];
  });

  Future<void> mount(
    WidgetTester tester, {
    String day = _day,
    Brightness brightness = Brightness.light,
    double width = 393,
    double height = 852,
    double scale = 1,
    bool planRoute = true,
    OpenBandController? controller,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final home = planRoute
        ? OpenBandSleepPlan(
            key: UniqueKey(),
            repository: repo,
            day: day,
            now: () => clock,
          )
        : OpenBandSleep(controller: controller!);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('de'),
        supportedLocales: const [Locale('de')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: openBandTheme(brightness).copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            viewPadding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('capture'),
          child: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('fixture need, times and stand render in light and dark', (
    tester,
  ) async {
    expect(_needSec, closeTo(30805.7142857, 0.0001));
    expect(_bedtimeMin, closeTo(1319.548872, 0.0001));
    expect(_wakeMin, closeTo(420, 0.0001));
    await mount(tester);
    expect(find.text('Heute Nacht'), findsOneWidget);
    expect(find.text('15./16. September'), findsOneWidget);
    expect(find.text('Geschätzter Schlafbedarf'), findsOneWidget);
    expect(find.text('8 h 33'), findsOneWidget);
    expect(find.text('Stand 07:42'), findsOneWidget);
    expect(find.text('22:00'), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);
    expect(find.text('8 h'), findsNothing);
    expect(find.text('Belastung fehlt'), findsNothing);
    expect(find.text('Nickerchen unvollständig'), findsNothing);
    expect(find.text('Noch keine Schätzung'), findsNothing);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/sleep-plan.png'),
    );
    await mount(tester, brightness: Brightness.dark);
    expect(find.text('8 h 33'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/sleep-plan-dark.png'),
    );
  }, tags: const ['golden']);

  testWidgets('missing artifact is emdash, not a loading or error state', (
    tester,
  ) async {
    repo.sleepPlanArtifact = null;
    await mount(tester);
    expect(find.text('8 h 33'), findsNothing);
    expect(find.text('—'), findsWidgets);
    expect(find.text('Noch keine Schätzung'), findsOneWidget);
    expect(find.text('Laden fehlgeschlagen'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/sleep-plan-empty.png'),
    );
    await mount(tester, brightness: Brightness.dark);
    expect(find.text('Noch keine Schätzung'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/sleep-plan-empty-dark.png'),
    );
  }, tags: const ['golden']);

  testWidgets('need without times keeps the hero and names the missing clocks', (
    tester,
  ) async {
    repo.sleepPlanArtifact = _artifact(times: false);
    await mount(tester);
    expect(find.text('8 h 33'), findsOneWidget);
    expect(find.text('Stand 07:42'), findsOneWidget);
    expect(find.text('22:00'), findsNothing);
    expect(find.text('Zeitplanung unvollständig'), findsOneWidget);
    expect(find.text('Aufwachzeiten fehlen'), findsNothing);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/sleep-plan-partial.png'),
    );
    await mount(tester, brightness: Brightness.dark);
    expect(find.text('Zeitplanung unvollständig'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/sleep-plan-partial-dark.png'),
    );
  }, tags: const ['golden']);

  testWidgets('storage error retries and restores the fixture', (tester) async {
    repo.failSleepPlanRead = true;
    await mount(tester);
    expect(find.text('Laden fehlgeschlagen'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(find.text('8 h 33'), findsNothing);
    expect(find.text('Noch keine Schätzung'), findsNothing);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/sleep-plan-error.png'),
    );
    await mount(tester, brightness: Brightness.dark);
    expect(find.text('Laden fehlgeschlagen'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/sleep-plan-error-dark.png'),
    );
    repo.failSleepPlanRead = false;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(find.text('8 h 33'), findsOneWidget);
    expect(find.text('Laden fehlgeschlagen'), findsNothing);
  }, tags: const ['golden']);

  testWidgets('2x stacks times and scrolls instead of shrinking', (
    tester,
  ) async {
    await mount(tester, width: 375, height: 1200, scale: 2);
    expect(find.text('8 h 33'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final bed = tester.getRect(find.text('Ins Bett · geschätzt'));
    final rise = tester.getRect(find.text('Aufstehen · typisch'));
    expect(rise.top, greaterThan(bed.bottom + 8));
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/sleep-plan-2x.png'),
    );
    await mount(
      tester,
      width: 375,
      height: 1200,
      scale: 2,
      brightness: Brightness.dark,
    );
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/sleep-plan-2x-dark.png'),
    );
  }, tags: const ['golden']);

  testWidgets('375x812 2x viewport scrolls to Eigenes Schlafziel', (
    tester,
  ) async {
    await mount(tester, width: 375, height: 812, scale: 2);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Eigenes Schlafziel'),
      80,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(find.text('Eigenes Schlafziel'), findsOneWidget);
    final goal = tester.getRect(find.text('Eigenes Schlafziel'));
    expect(goal.top, lessThan(812));
    expect(goal.bottom, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('info uses Paper copy, contributions and timezone', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byTooltip('Zur Schätzung'));
    await tester.pumpAndSettle();
    expect(find.text('Zur Schätzung'), findsWidgets);
    expect(
      find.text(
        'Aus gespeicherten Nächten, Belastung und Nickerchen. Kein gemessener persönlicher Schlafbedarf.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Die Abendplanung nutzt typische Aufwachzeiten und Schlafeffizienz. Sie stellt keinen Wecker.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Berücksichtigt: Belastung +3 Min · Nickerchen 0 Min. Stand 15. September, 07:42 · Modell $kAlgoVersion.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Die Zeitzone der Berechnung wurde nicht gespeichert.'),
      findsOneWidget,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/sleep-plan-info.png'),
    );
    await tester.tap(find.text('Schließen').last);
    await tester.pumpAndSettle();
    expect(find.text('Schließen'), findsNothing);
    await mount(tester, brightness: Brightness.dark);
    await tester.tap(find.byTooltip('Zur Schätzung'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/sleep-plan-info-dark.png'),
    );
    await tester.tap(find.byTooltip('Schließen'));
    await tester.pumpAndSettle();
    expect(find.text('8 h 33'), findsOneWidget);
  }, tags: const ['golden']);

  testWidgets('null strain or nap is partial; true zero is not absence', (
    tester,
  ) async {
    repo.sleepPlanArtifact = _artifact(strain: null, nap: 0);
    await mount(tester);
    expect(find.text('8 h 33'), findsOneWidget);
    expect(find.text('Belastung fehlt'), findsOneWidget);
    expect(find.text('Nickerchen unvollständig'), findsNothing);
    await tester.tap(find.byTooltip('Zur Schätzung'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Belastung fehlt'), findsWidgets);
    expect(find.textContaining('Nickerchen 0 Min'), findsOneWidget);
    await tester.tap(find.text('Schließen').last);
    await tester.pumpAndSettle();

    repo.sleepPlanArtifact = _artifact(strain: 3, nap: null);
    await mount(tester);
    expect(find.text('Nickerchen unvollständig'), findsOneWidget);
    expect(find.text('Belastung fehlt'), findsNothing);
  });

  testWidgets('applied nap credit is subtracted, never shown as a plus', (
    tester,
  ) async {
    repo.sleepPlanArtifact = _artifact(nap: 12, strain: 3);
    await mount(tester);
    expect(find.text('8 h 33'), findsOneWidget);
    expect(find.text('Nickerchen unvollständig'), findsNothing);
    await tester.tap(find.byTooltip('Zur Schätzung'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Berücksichtigt: Belastung +3 Min · Nickerchen -12 Min. Stand 15. September, 07:42 · Modell $kAlgoVersion.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Nickerchen +12'), findsNothing);
    expect(find.textContaining('Nickerchen 12 Min'), findsNothing);
  });

  testWidgets('incomplete clocks stay generic even if one time is present', (
    tester,
  ) async {
    repo.sleepPlanArtifact = _artifact(includeWake: false);
    await mount(tester);
    expect(find.text('8 h 33'), findsOneWidget);
    expect(find.text('22:00'), findsOneWidget);
    expect(find.text('07:00'), findsNothing);
    expect(find.text('Zeitplanung unvollständig'), findsOneWidget);
    expect(find.text('Aufwachzeiten fehlen'), findsNothing);
  });

  testWidgets('stale inputs withhold values even when status is available', (
    tester,
  ) async {
    repo.sleepPlanArtifact = _artifact();
    repo.sleepPlanObservations = _observations();
    repo.sleepPlanJobs = [
      SleepPlanInputJob(
        day: _day,
        kind: SleepPlanJobKind.napRecalc,
        status: 'complete',
        resultComputedAtMs: _inputReadMs(),
      ),
    ];
    await mount(tester);
    expect(find.text('8 h 33'), findsNothing);
    expect(find.text('22:00'), findsNothing);
    expect(find.text('Schätzung nicht aktuell'), findsOneWidget);
    expect(find.text('Noch keine Schätzung'), findsNothing);
  });

  testWidgets('unknown freshness keeps values and labels them', (tester) async {
    repo.sleepPlanArtifact = _artifact(window: false, provenance: false);
    repo.sleepPlanObservations = const [];
    repo.sleepPlanJobs = const [];
    await mount(tester);
    expect(find.text('8 h 33'), findsOneWidget);
    expect(find.text('Aktualität unbekannt'), findsOneWidget);
    expect(find.text('Stand 07:42'), findsNothing);
  });

  testWidgets('corrupt and stale artifacts are not empty states', (
    tester,
  ) async {
    repo.sleepPlanArtifact = _artifact(need: 100);
    await mount(tester);
    expect(find.text('8 h 33'), findsNothing);
    expect(find.text('Schätzung nicht lesbar'), findsOneWidget);
    expect(find.text('Noch keine Schätzung'), findsNothing);

    repo.sleepPlanArtifact = _artifact(algoVersion: 1);
    await mount(tester);
    expect(find.text('Schätzung nicht aktuell'), findsOneWidget);
    expect(find.text('Noch keine Schätzung'), findsNothing);
  });

  testWidgets('historical day does not borrow tonight and drops Heute Nacht', (
    tester,
  ) async {
    await mount(tester, day: '2026-09-14');
    expect(repo.days, ['2026-09-14']);
    expect(find.text('Heute Nacht'), findsNothing);
    expect(find.text('Nacht'), findsOneWidget);
    expect(find.text('14./15. September'), findsOneWidget);
    expect(find.text('8 h 33'), findsNothing);
    expect(find.text('Stand 07:42'), findsNothing);
    expect(find.text('Keine gespeicherte Schätzung'), findsOneWidget);
    expect(find.text('Noch keine Schätzung'), findsNothing);
  });

  testWidgets('midnight deadline stops showing the prior night as tonight', (
    tester,
  ) async {
    clock = DateTime(2026, 9, 15, 23, 59, 50);
    await mount(tester);
    expect(find.text('Heute Nacht'), findsOneWidget);
    expect(find.text('8 h 33'), findsOneWidget);
    clock = DateTime(2026, 9, 16, 0, 0, 10);
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(find.text('8 h 33'), findsNothing);
    expect(find.text('Heute Nacht'), findsNothing);
    expect(find.text('Nacht'), findsOneWidget);
    expect(find.text('Keine gespeicherte Schätzung'), findsOneWidget);
    expect(find.text('Noch keine Schätzung'), findsNothing);
  });

  testWidgets('parent captures today, goal uses tomorrow, selected day stays', (
    tester,
  ) async {
    final controller = OpenBandController(
      repository: repo,
      initialDay: _day,
      band: repo.band,
      now: () => clock,
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    await mount(tester, planRoute: false, controller: controller);
    await tester.scrollUntilVisible(
      find.text('Heute Nacht'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Heute Nacht'), findsOneWidget);
    expect(find.text('Schlafziel'), findsOneWidget);
    await tester.tap(find.text('Heute Nacht'));
    await tester.pumpAndSettle();
    expect(repo.days, [_day]);
    expect(clocksAreCaptured(repo.clocks), isTrue);
    expect(find.text('8 h 33'), findsOneWidget);
    expect(controller.selectedDay, _day);
    await tester.tap(find.text('Eigenes Schlafziel'));
    await tester.pumpAndSettle();
    expect(find.text('Ab 16. September'), findsOneWidget);
    expect(controller.selectedDay, _day);
    await tester.tap(find.byTooltip('Zurück').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zurück').last);
    await tester.pumpAndSettle();
    expect(controller.selectedDay, _day);
    await tester.tap(find.text('Schlafziel'));
    await tester.pumpAndSettle();
    expect(find.text('Ab 15. September'), findsOneWidget);
  });

  testWidgets('Heute Nacht is hidden on a past selected day', (tester) async {
    clock = DateTime(2026, 9, 18, 9, 41);
    final controller = OpenBandController(
      repository: repo,
      initialDay: _day,
      band: repo.band,
      now: () => clock,
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    await mount(tester, planRoute: false, controller: controller);
    await tester.scrollUntilVisible(
      find.text('Schlafziel'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Heute Nacht'), findsNothing);
    expect(repo.reads, 0);
  });

  testWidgets('standalone parent header respects remaining status inset', (
    tester,
  ) async {
    Future<void> pumpParent(double top) async {
      final controller = OpenBandController(
        repository: repo,
        initialDay: _day,
        band: repo.band,
        now: () => clock,
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 852);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('de'),
          supportedLocales: const [Locale('de')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: openBandTheme(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: EdgeInsets.only(top: top),
              viewPadding: EdgeInsets.only(top: top),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: OpenBandSleep(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpParent(58);
    final belowInset = tester.getRect(find.byTooltip('Zurück'));
    expect(belowInset.top, greaterThanOrEqualTo(58));
    expect(find.text('Schlaf'), findsOneWidget);

    await pumpParent(0);
    final consumed = tester.getRect(find.byTooltip('Zurück'));
    expect(consumed.top, lessThan(16));
  });

  testWidgets('stale completion and dispose do not paint the old forecast', (
    tester,
  ) async {
    repo.gate = Completer<void>();
    clock = _now;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget host(String day) => MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('de'),
      supportedLocales: const [Locale('de')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: openBandTheme(Brightness.light),
      home: OpenBandSleepPlan(
        repository: repo,
        day: day,
        now: () => clock,
      ),
    );
    await tester.pumpWidget(host(_day));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Noch keine Schätzung'), findsNothing);
    final first = repo.gate!;
    repo.gate = Completer<void>();
    await tester.pumpWidget(host('2026-09-14'));
    await tester.pump();
    first.complete();
    await tester.pump();
    expect(find.text('8 h 33'), findsNothing);
    repo.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('8 h 33'), findsNothing);
    expect(find.text('Heute Nacht'), findsNothing);

    repo.gate = Completer<void>();
    await tester.pumpWidget(const SizedBox.shrink());
    repo.gate!.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('rebuilds do not reread on every tick', (tester) async {
    await mount(tester);
    expect(repo.reads, 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(repo.reads, 1);
  });

  test('night range crosses months, years and DST calendar days', () {
    expect(sleepPlanNightRangeLabel('2026-09-15'), '15./16. September');
    expect(
      sleepPlanNightRangeLabel('2026-09-30'),
      '30. September/1. Oktober',
    );
    expect(
      sleepPlanNightRangeLabel('2026-12-31'),
      '31. Dezember 2026/1. Januar 2027',
    );
    expect(sleepPlanNightRangeLabel('2026-03-28'), '28./29. März');
    expect(sleepPlanNeedLabel(_needSec), '8 h 33');
    expect(sleepPlanClockLabel(_bedtimeMin), '22:00');
    expect(sleepPlanClockLabel(_wakeMin), '07:00');
    expect(sleepPlanWakeDay(_day), '2026-09-16');
  });
}

bool clocksAreCaptured(List<DateTime?> clocks) =>
    clocks.isNotEmpty && clocks.every((value) => value != null);
