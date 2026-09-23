import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:openstrap_edge/openband/alp_tokens.dart';
import 'package:openstrap_edge/openband/cycle.dart';
import 'package:openstrap_edge/openband/cycle_measurements.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/openband/health.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';

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

class _GateRepo extends SyntheticOpenBandRepository {
  _GateRepo() : super.fromMaps(_daySummary(), _sleepDetail());

  Completer<void>? gate;
  int measurementReads = 0;
  String? lastStart;

  @override
  Future<CycleMeasurementsSnapshot> readCycleMeasurements(
    String asOfDay, {
    String? cycleStartDay,
  }) async {
    measurementReads++;
    lastStart = cycleStartDay;
    final snap = await super.readCycleMeasurements(
      asOfDay,
      cycleStartDay: cycleStartDay,
    );
    final hold = gate;
    if (hold != null) await hold.future;
    return snap;
  }
}

class _Host extends StatefulWidget {
  const _Host({super.key, required this.initialRepo, required this.initialDay});
  final OpenBandRepository initialRepo;
  final String initialDay;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late OpenBandRepository repo = widget.initialRepo;
  late String day = widget.initialDay;

  void update({OpenBandRepository? repository, String? asOf}) {
    setState(() {
      if (repository != null) repo = repository;
      if (asOf != null) day = asOf;
    });
  }

  @override
  Widget build(BuildContext context) => OpenBandCycleMeasurements(
    repository: repo,
    day: day,
    now: () => DateTime(2026, 9, 15, 9, 41),
    synthetic: true,
  );
}

CycleNightSourceRow _night(
  String day, {
  double? rhr,
  double? hrv,
  double? rhrConfidence,
  double? hrvConfidence,
  bool unreadable = false,
}) {
  if (unreadable) {
    return CycleNightSourceRow(
      day: day,
      algoVersion: kAlgoVersion,
      payloadUnreadable: true,
    );
  }
  return CycleNightSourceRow(
    day: day,
    algoVersion: kAlgoVersion,
    payload: cycleNightSourcePayload(
      rhr: rhr,
      hrv: hrv,
      rhrConfidence: rhrConfidence,
      hrvConfidence: hrvConfidence,
      onsetMs: cycleNightOnsetMs(day),
      offsetMs: cycleNightOffsetMs(day),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('de_DE');
    for (final (family, path) in [
      ('Inter', 'assets/fonts/Inter/Inter.ttf'),
      ('Inter Tight', 'assets/fonts/InterTight/InterTight[wght].ttf'),
    ]) {
      final loader = FontLoader(family)
        ..addFont(
          Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
        );
      await loader.load();
    }
    final icons = FontLoader('packages/lucide_icons_flutter/Lucide')
      ..addFont(
        rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
      );
    await icons.load();
  });

  late _GateRepo repo;

  setUp(() => repo = _GateRepo());

  Finder capture() => find.byKey(const ValueKey('capture'));

  Finder cardOf(Key plot) =>
      find.ancestor(of: find.byKey(plot), matching: find.byType(OBCard));

  Future<void> mount(
    WidgetTester tester, {
    OpenBandRepository? repository,
    String day = '2026-09-15',
    Brightness brightness = Brightness.light,
    double scale = 1,
    double width = 393,
    double height = 852,
    bool synthetic = true,
    bool settle = true,
    Widget? home,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            viewPadding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: RepaintBoundary(
            key: const ValueKey('capture'),
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        home:
            home ??
            OpenBandCycleMeasurements(
              repository: repository ?? repo,
              day: day,
              now: () => DateTime(2026, 9, 15, 9, 41),
              synthetic: synthetic,
            ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets('root Messwerte opens measurements before Verlauf', (
    tester,
  ) async {
    await mount(
      tester,
      home: OpenBandCycle(
        repository: repo,
        day: '2026-09-15',
        now: () => DateTime(2026, 9, 15, 9, 41),
        synthetic: true,
      ),
    );
    expect(find.text('Messwerte'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Messwerte')).dy,
      lessThan(tester.getTopLeft(find.text('Verlauf')).dy),
    );
    await tester.tap(find.text('Messwerte'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cycle-measurements')), findsOneWidget);
    expect(find.text('Ruhepuls'), findsOneWidget);
    expect(find.text('54'), findsOneWidget);
    expect(find.text('48'), findsWidgets);
  });

  testWidgets('Messwerte stays reachable without a start', (tester) async {
    repo.clearCycleLogs();
    await mount(
      tester,
      home: OpenBandCycle(
        repository: repo,
        day: '2026-09-15',
        now: () => DateTime(2026, 9, 15, 9, 41),
        synthetic: true,
      ),
    );
    expect(find.text('Messwerte'), findsOneWidget);
    await tester.tap(find.text('Messwerte'));
    await tester.pumpAndSettle();
    expect(find.text('Kein Zyklusbeginn'), findsOneWidget);
    expect(find.text('Zum Zyklus'), findsOneWidget);
  });

  testWidgets('fixture latest values stay independent', (tester) async {
    await mount(tester);
    expect(find.text('19 von 23 Nächten'), findsOneWidget);
    expect(find.text('16 von 23 Nächten'), findsOneWidget);
    expect(find.text('54'), findsOneWidget);
    expect(find.text('15. Sept.'), findsOneWidget);
    expect(find.text('48'), findsWidgets);
    expect(find.text('14. Sept.'), findsOneWidget);
    expect(find.text('Tag 1'), findsWidgets);
    expect(find.text('Tag 23'), findsWidgets);
    expect(tester.takeException(), isNull);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle-measurements.png'),
    );
    await mount(tester, brightness: Brightness.dark);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle-measurements-dark.png'),
    );
  }, tags: const ['golden']);

  testWidgets('picker lists dated periods newest first and reloads', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('cycle-measurements-picker')));
    await tester.pumpAndSettle();
    expect(find.text('24. Aug.–15. Sept.'), findsWidgets);
    expect(find.text('31. Juli–23. Aug.'), findsOneWidget);
    expect(find.text('29. Juni–30. Juli'), findsOneWidget);
    expect(find.text('1.–28. Juni'), findsOneWidget);
    final labels = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    expect(
      labels.indexOf('24. Aug.–15. Sept.'),
      lessThan(labels.indexOf('31. Juli–23. Aug.')),
    );
    expect(
      labels.indexOf('31. Juli–23. Aug.'),
      lessThan(labels.indexOf('1.–28. Juni')),
    );
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle-measurements-picker.png'),
    );
    await tester.tap(find.text('1.–28. Juni'));
    await tester.pumpAndSettle();
    expect(repo.lastStart, '2026-06-01');
    expect(find.text('1.–28. Juni'), findsOneWidget);
    expect(find.text('24. Aug.–15. Sept.'), findsNothing);
  }, tags: const ['golden']);

  testWidgets('empty nights keep dash coverage and omit plots', (tester) async {
    repo.clearCycleNightSources();
    await mount(tester);
    expect(find.text('0 von 23 Nächten'), findsNWidgets(2));
    expect(find.text('—'), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey('cycle-measurements-rhr-plot')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('cycle-measurements-hrv-plot')),
      findsNothing,
    );
    expect(find.text('Tag 1'), findsNothing);
    expect(tester.takeException(), isNull);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle-measurements-empty.png'),
    );
    await mount(tester, brightness: Brightness.dark);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle-measurements-empty-dark.png'),
    );
  }, tags: const ['golden']);

  testWidgets('unreadable rows show partial notice above cards', (
    tester,
  ) async {
    repo.seedCycleNightSource(_night('2026-08-29', unreadable: true));
    await mount(tester);
    expect(find.text('Daten teilweise lesbar'), findsOneWidget);
    expect(find.text('19 von 23 Nächten'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle-measurements-partial.png'),
    );
    await mount(tester, brightness: Brightness.dark);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle-measurements-partial-dark.png'),
    );
  }, tags: const ['golden']);

  testWidgets('read exception is retryable and not empty', (tester) async {
    repo.failCycleMeasurementsRead = true;
    await mount(tester);
    expect(find.text('Daten nicht geladen'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(find.text('Ruhepuls'), findsNothing);
    expect(find.text('Kein Zyklusbeginn'), findsNothing);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle-measurements-error.png'),
    );
    repo.failCycleMeasurementsRead = false;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(find.text('54'), findsOneWidget);
    expect(find.text('Daten nicht geladen'), findsNothing);
  }, tags: const ['golden']);

  testWidgets('unavailable states keep their actions', (tester) async {
    repo.clearCycleLogs();
    await mount(tester);
    expect(find.text('Kein Zyklusbeginn'), findsOneWidget);
    expect(find.text('Zum Zyklus'), findsOneWidget);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle-measurements-no-start.png'),
    );

    repo.cycleSettings = const CycleSettings(
      enabled: false,
      estimatesEnabled: false,
      lengthReviewEnabled: false,
    );
    await mount(tester);
    expect(find.text('Zyklus deaktiviert'), findsOneWidget);
    expect(find.text('Einstellungen'), findsOneWidget);
    await tester.tap(find.text('Einstellungen'));
    await tester.pumpAndSettle();
    expect(find.text('Zyklus im Journal'), findsOneWidget);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cycle-measurements')), findsOneWidget);

    repo.cycleSettings = const CycleSettings(
      enabled: true,
      estimatesEnabled: true,
      lengthReviewEnabled: false,
    );
    repo.clearCycleLogs();
    repo.seedUnreadableCycleStart({'date': '2026-08-24', 'kind': 1});
    await mount(tester);
    expect(find.text('Zyklusbeginn nicht lesbar'), findsOneWidget);
    final color = tester
        .widget<Text>(find.text('Zyklusbeginn nicht lesbar'))
        .style
        ?.color;
    expect(color, AlpColor.danger);
    expect(find.text('Zum Zyklus'), findsOneWidget);
  }, tags: const ['golden']);

  testWidgets('settings return withholds prior unavailable state', (
    tester,
  ) async {
    repo.cycleSettings = const CycleSettings(
      enabled: false,
      estimatesEnabled: false,
      lengthReviewEnabled: false,
    );
    await mount(tester);
    expect(find.text('Zyklus deaktiviert'), findsOneWidget);
    await tester.tap(find.text('Einstellungen'));
    await tester.pumpAndSettle();
    repo.cycleSettings = const CycleSettings(
      enabled: true,
      estimatesEnabled: true,
      lengthReviewEnabled: false,
    );
    final hold = Completer<void>();
    repo.gate = hold;
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pump();
    expect(find.text('Zyklus deaktiviert'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    hold.complete();
    await tester.pumpAndSettle();
    expect(find.text('Zyklus deaktiviert'), findsNothing);
    expect(find.text('Ruhepuls'), findsOneWidget);
  });

  testWidgets('removed selected cycle offers remaining periods', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('cycle-measurements-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.–28. Juni'));
    await tester.pumpAndSettle();
    repo.failCycleMeasurementsRead = true;
    await tester.tap(find.byKey(const ValueKey('cycle-measurements-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('31. Juli–23. Aug.'));
    await tester.pumpAndSettle();
    expect(find.text('Daten nicht geladen'), findsOneWidget);
    repo.failCycleMeasurementsRead = false;
    repo.clearCycleLogs();
    repo.seedCycleStart(
      const CycleStart(date: '2026-06-29', kind: kCycleStartKind),
    );
    repo.seedCycleStart(
      const CycleStart(date: '2026-08-24', kind: kCycleStartKind),
    );
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(find.text('Zyklus nicht mehr vorhanden'), findsOneWidget);
    expect(find.text('Zyklus wählen'), findsOneWidget);
    expect(find.text('Ruhepuls'), findsNothing);
    await tester.tap(find.text('Zyklus wählen'));
    await tester.pumpAndSettle();
    expect(find.text('24. Aug.–15. Sept.'), findsOneWidget);
    await tester.tap(find.text('24. Aug.–15. Sept.'));
    await tester.pumpAndSettle();
    expect(find.text('54'), findsOneWidget);
  });

  testWidgets('gap slot shows dash and its civil date', (tester) async {
    await mount(tester);
    const rhrPlot = ValueKey('cycle-measurements-rhr-plot');
    const hrvPlot = ValueKey('cycle-measurements-hrv-plot');
    final plot = tester.getRect(find.byKey(rhrPlot));
    await tester.tapAt(Offset(plot.left + 94.86, plot.center.dy));
    await tester.pump();
    final rhr = cardOf(rhrPlot);
    final hrv = cardOf(hrvPlot);
    expect(find.descendant(of: rhr, matching: find.text('—')), findsOneWidget);
    expect(
      find.descendant(of: rhr, matching: find.text('29. Aug.')),
      findsOneWidget,
    );
    expect(find.descendant(of: rhr, matching: find.text('54')), findsNothing);
    expect(find.descendant(of: hrv, matching: find.text('48')), findsOneWidget);
    expect(
      find.descendant(of: hrv, matching: find.text('14. Sept.')),
      findsOneWidget,
    );
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle-measurements-gap.png'),
    );
  }, tags: const ['golden']);

  testWidgets('single finite point has no empty-metric plot', (tester) async {
    repo.clearCycleNightSources();
    repo.seedCycleNightSource(_night('2026-09-15', rhr: 54));
    await mount(tester);
    expect(find.text('1 von 23 Nächten'), findsOneWidget);
    expect(find.text('0 von 23 Nächten'), findsOneWidget);
    expect(find.text('54'), findsOneWidget);
    expect(find.text('15. Sept.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('cycle-measurements-rhr-plot')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('cycle-measurements-hrv-plot')),
      findsNothing,
    );
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle-measurements-single.png'),
    );
  }, tags: const ['golden']);

  testWidgets('clipped window labels actual cycle days', (tester) async {
    repo.clearCycleLogs();
    repo.clearCycleNightSources();
    repo.seedCycleStart(
      const CycleStart(date: '2026-05-01', kind: kCycleStartKind),
    );
    repo.seedCycleNightSource(_night('2026-09-15', rhr: 54));
    repo.seedCycleNightSource(_night('2026-09-14', hrv: 48));
    await mount(tester);
    expect(find.text('Letzte 120 Nächte'), findsOneWidget);
    expect(find.text('1 von 120 Nächten'), findsNWidgets(2));
    expect(find.text('Tag 19'), findsWidgets);
    expect(find.text('Tag 138'), findsWidgets);
    expect(find.text('Tag 1'), findsNothing);
    expect(find.text('1. Mai–15. Sept.'), findsOneWidget);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle-measurements-truncated.png'),
    );
  }, tags: const ['golden']);

  testWidgets('info body matches Paper', (tester) async {
    await mount(tester);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Ruhepuls und HRV stammen aus gespeicherten Nächten. Das Datum gehört zur jeweiligen Nacht.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Die HRV zeigt die RMSSD der Schlafsitzung. Fehlende oder neu zu berechnende Werte bleiben als Lücke sichtbar.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Die Werte bestimmen weder eine Zyklusphase noch einen Eisprung.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Ruhepuls · 15. Sept.'), findsOneWidget);
    expect(
      find.textContaining('14. Sept., 16:00–15. Sept., 06:00 UTC'),
      findsOneWidget,
    );
    expect(find.textContaining('HRV · 14. Sept.'), findsOneWidget);
    expect(
      find.textContaining('13. Sept., 16:00–14. Sept., 06:00 UTC'),
      findsOneWidget,
    );
    expect(find.textContaining('Qualitätswert —'), findsNWidgets(2));
    expect(
      find.text(
        'Qualitätswerte sind gespeicherte Scores, keine Fehlerspannen.',
      ),
      findsOneWidget,
    );
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle-measurements-info.png'),
    );
  }, tags: const ['golden']);

  testWidgets('375 2x canonical fixture fits and selects independently', (
    tester,
  ) async {
    await mount(tester, scale: 2, width: 375, height: 812);
    expect(find.text('19 von 23 Nächten'), findsOneWidget);
    expect(find.text('16 von 23 Nächten'), findsOneWidget);
    expect(find.text('54'), findsOneWidget);
    expect(find.text('15. Sept.'), findsOneWidget);
    expect(find.text('48'), findsWidgets);
    expect(find.text('14. Sept.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle-measurements-large.png'),
    );
    const rhrPlot = ValueKey('cycle-measurements-rhr-plot');
    const hrvPlot = ValueKey('cycle-measurements-hrv-plot');
    final plot = tester.getRect(find.byKey(rhrPlot));
    await tester.tapAt(Offset(plot.left + plot.width * 0.12, plot.center.dy));
    await tester.pump();
    expect(
      find.descendant(of: cardOf(rhrPlot), matching: find.text('54')),
      findsNothing,
    );
    expect(
      find.descendant(of: cardOf(hrvPlot), matching: find.text('48')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cardOf(hrvPlot), matching: find.text('14. Sept.')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(find.text('Synthetische Daten'), 200);
    expect(tester.takeException(), isNull);
    await mount(
      tester,
      scale: 2,
      width: 375,
      height: 812,
      brightness: Brightness.dark,
    );
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle-measurements-large-dark.png'),
    );
    await tester.tap(find.byKey(const ValueKey('cycle-measurements-picker')));
    await tester.pumpAndSettle();
    expect(find.text('1.–28. Juni'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('24. Aug.–15. Sept.').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    final infoScroll = find.byKey(const ValueKey('journal-info-body'));
    await tester.scrollUntilVisible(
      find.text(
        'Qualitätswerte sind gespeicherte Scores, keine Fehlerspannen.',
      ),
      80,
      scrollable: find.descendant(
        of: infoScroll,
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.textContaining('Ruhepuls ·'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, tags: const ['golden']);

  testWidgets('375 2x three-digit value wraps date without overflow', (
    tester,
  ) async {
    repo.clearCycleNightSources();
    repo.seedCycleNightSource(_night('2026-09-15', rhr: 104, hrv: 48));
    await mount(tester, scale: 2, width: 375, height: 812);
    expect(find.text('104'), findsOneWidget);
    expect(find.text('15. Sept.'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Synthetische Daten'), 200);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale reads and identity changes do not paint old plots', (
    tester,
  ) async {
    final first = Completer<void>();
    repo.gate = first;
    final hostKey = GlobalKey<_HostState>();
    await mount(
      tester,
      settle: false,
      home: _Host(key: hostKey, initialRepo: repo, initialDay: '2026-09-15'),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('54'), findsNothing);

    final second = _GateRepo();
    second.clearCycleNightSources();
    second.seedCycleNightSource(_night('2026-09-15', rhr: 61));
    final secondGate = Completer<void>();
    second.gate = secondGate;
    hostKey.currentState!.update(repository: second);
    await tester.pump();
    expect(find.text('54'), findsNothing);
    expect(find.text('61'), findsNothing);

    first.complete();
    await tester.pump();
    expect(find.text('54'), findsNothing);
    expect(find.text('61'), findsNothing);

    secondGate.complete();
    await tester.pumpAndSettle();
    expect(find.text('61'), findsOneWidget);
    expect(find.text('54'), findsNothing);
    expect(find.text('19 von 23 Nächten'), findsNothing);

    final delayed = Completer<void>();
    second.gate = delayed;
    hostKey.currentState!.update(asOf: '2026-09-14');
    await tester.pump();
    expect(find.text('61'), findsNothing);
    delayed.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cycle-measurements')), findsOneWidget);
  });

  testWidgets('picker choice is ignored after repository identity change', (
    tester,
  ) async {
    final hostKey = GlobalKey<_HostState>();
    await mount(
      tester,
      home: _Host(key: hostKey, initialRepo: repo, initialDay: '2026-09-15'),
    );
    await tester.tap(find.byKey(const ValueKey('cycle-measurements-picker')));
    await tester.pumpAndSettle();
    expect(find.text('1.–28. Juni'), findsOneWidget);

    final other = _GateRepo();
    other.clearCycleLogs();
    other.seedCycleStart(
      const CycleStart(date: '2026-08-24', kind: kCycleStartKind),
    );
    hostKey.currentState!.update(repository: other);
    await tester.pump();
    await tester.tap(find.text('1.–28. Juni'));
    await tester.pumpAndSettle();
    expect(find.text('Zyklus nicht mehr vorhanden'), findsNothing);
    expect(other.lastStart, isNull);
    expect(find.text('24. Aug.–15. Sept.'), findsOneWidget);
  });

  testWidgets('semantics walk every slot including gaps', (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await mount(tester);
      final plot = find.byKey(const ValueKey('cycle-measurements-rhr-plot'));
      var node = tester.getSemantics(plot);
      expect(node.value, contains('15. September'));
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.decrease),
        isTrue,
      );
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.increase),
        isFalse,
      );
      final box = tester.getRect(plot);
      await tester.tapAt(Offset(box.left + 8, box.center.dy));
      await tester.pump();
      node = tester.getSemantics(plot);
      expect(node.value, contains('24. August'));
      await tester.tapAt(Offset(box.left + 94.86, box.center.dy));
      await tester.pump();
      node = tester.getSemantics(plot);
      expect(node.value, contains('kein Wert'));
    } finally {
      handle.dispose();
    }
  });

  testWidgets('nonfinite values do not plot or crash', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(Brightness.light),
        home: Scaffold(
          body: OBTrendCard.sourced(
            label: 'Ruhepuls',
            unit: 'bpm',
            icon: Icons.show_chart,
            color: AlpColor.pulse,
            tint: AlpColor.pulseTint,
            coverage: '0 von 3 Nächten',
            points: const [
              OBSourcedSample(value: double.nan, caption: '13. Sept.'),
              OBSourcedSample(value: double.infinity, caption: '14. Sept.'),
              OBSourcedSample(
                value: double.negativeInfinity,
                caption: '15. Sept.',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('—'), findsOneWidget);
    expect(find.byType(GestureDetector), findsNothing);
  });

  testWidgets('isolated first and last sourced points stay selectable', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('de')],
          theme: openBandTheme(Brightness.light),
          home: Builder(
            builder: (context) {
              final p = OB.of(context);
              return Scaffold(body: _IsolatedSelectCard(palette: p));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('52'), findsOneWidget);
      final plot = find.byKey(const ValueKey('isolated-plot'));
      var node = tester.getSemantics(plot);
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.decrease),
        isTrue,
      );
      final box = tester.getRect(plot);
      await tester.tapAt(Offset(box.center.dx, box.center.dy));
      await tester.pump();
      node = tester.getSemantics(plot);
      expect(node.value, contains('kein Wert'));
      await tester.tapAt(Offset(box.left + 8, box.center.dy));
      await tester.pump();
      node = tester.getSemantics(plot);
      expect(node.value, contains('50'));
    } finally {
      handle.dispose();
    }
  });

  testWidgets('isolated first point and gap do not join', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const samples = [
      OBSourcedSample(
        value: 50,
        caption: '13. Sept.',
        semantics: '13. September',
      ),
      OBSourcedSample(caption: '14. Sept.', semantics: '14. September'),
      OBSourcedSample(
        value: 52,
        caption: '15. Sept.',
        semantics: '15. September',
      ),
    ];
    const points = [
      MetricPoint('2026-09-13', 50),
      MetricPoint('2026-09-14', null),
      MetricPoint('2026-09-15', 52),
    ];
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(Brightness.light),
        home: Builder(
          builder: (context) {
            final p = OB.of(context);
            return Scaffold(
              backgroundColor: p.canvas,
              body: Align(
                alignment: Alignment.topCenter,
                child: RepaintBoundary(
                  key: const ValueKey('capture'),
                  child: ColoredBox(
                    color: p.canvas,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OBTrendCard.sourced(
                            label: 'Ruhepuls',
                            unit: 'bpm',
                            icon: LucideIcons.activity,
                            color: p.pulse,
                            tint: p.pulseTint,
                            coverage: '2 von 3 Nächten',
                            axisStart: 'Tag 1',
                            axisEnd: 'Tag 3',
                            selectedIndex: 2,
                            points: samples,
                          ),
                          const SizedBox(height: 12),
                          OBTrendCard(
                            label: 'HRV',
                            unit: 'ms',
                            icon: LucideIcons.activity,
                            color: p.recovery,
                            tint: p.recoveryTint,
                            nights: 3,
                            points: points,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('52'), findsWidgets);
    expect(find.text('50'), findsNothing);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile(
        'openband_goldens/cycle-measurements-isolated-first.png',
      ),
    );
  }, tags: const ['golden']);

  testWidgets('legacy headline ignores nonfinite last sample', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(Brightness.light),
        home: Builder(
          builder: (context) {
            final p = OB.of(context);
            return Scaffold(
              body: OBTrendCard(
                label: 'HRV',
                unit: 'ms',
                icon: Icons.show_chart,
                color: p.recovery,
                tint: p.recoveryTint,
                nights: 3,
                points: const [
                  MetricPoint('2026-09-13', 40),
                  MetricPoint('2026-09-14', 42),
                  MetricPoint('2026-09-15', double.nan),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('NaN'), findsNothing);
  });

  testWidgets('info reports stored confidence and omits gap sources', (
    tester,
  ) async {
    repo.clearCycleNightSources();
    repo.seedCycleNightSource(
      _night('2026-09-15', rhr: 54, rhrConfidence: 0.9),
    );
    repo.seedCycleNightSource(_night('2026-09-14', hrv: 48, hrvConfidence: 1));
    await mount(tester);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Qualitätswert 0,90 / 1'), findsOneWidget);
    expect(find.textContaining('Qualitätswert 1 / 1'), findsOneWidget);
    expect(
      find.text(
        'Qualitätswerte sind gespeicherte Scores, keine Fehlerspannen.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();

    final plot = tester.getRect(
      find.byKey(const ValueKey('cycle-measurements-rhr-plot')),
    );
    await tester.tapAt(Offset(plot.left + 26, plot.center.dy));
    await tester.pump();
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ruhepuls ·'), findsNothing);
    expect(find.textContaining('HRV · 14. Sept.'), findsOneWidget);
  });

  testWidgets('corrupt confidence is dash and malformed metric is partial', (
    tester,
  ) async {
    repo.clearCycleNightSources();
    repo.seedCycleNightSource(
      _night('2026-09-15', rhr: 54, rhrConfidence: 1.4),
    );
    repo.seedCycleNightSource(_night('2026-09-14', rhr: 0, hrv: 48));
    await mount(tester);
    expect(find.text('Daten teilweise lesbar'), findsOneWidget);
    expect(find.text('54'), findsOneWidget);
    expect(find.text('48'), findsWidgets);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Qualitätswert —'), findsWidgets);
    expect(find.textContaining('Qualitätswert 0,90 / 1'), findsNothing);
    expect(find.textContaining('auto'), findsNothing);
  });
}

class _IsolatedSelectCard extends StatefulWidget {
  const _IsolatedSelectCard({required this.palette});
  final OB palette;
  @override
  State<_IsolatedSelectCard> createState() => _IsolatedSelectCardState();
}

class _IsolatedSelectCardState extends State<_IsolatedSelectCard> {
  int _slot = 2;
  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return OBTrendCard.sourced(
      label: 'Ruhepuls',
      unit: 'bpm',
      icon: Icons.show_chart,
      color: p.pulse,
      tint: p.pulseTint,
      coverage: '2 von 3 Nächten',
      selectedIndex: _slot,
      plotKey: const ValueKey('isolated-plot'),
      onSelect: (i) => setState(() => _slot = i),
      points: const [
        OBSourcedSample(
          value: 50,
          caption: '13. Sept.',
          semantics: '13. September',
        ),
        OBSourcedSample(caption: '14. Sept.', semantics: '14. September'),
        OBSourcedSample(
          value: 52,
          caption: '15. Sept.',
          semantics: '15. September',
        ),
      ],
    );
  }
}
