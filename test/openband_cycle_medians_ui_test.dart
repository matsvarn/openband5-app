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
import 'package:openstrap_edge/openband/cycle.dart';
import 'package:openstrap_edge/openband/cycle_medians.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/settings_controls.dart';
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
  Completer<void>? restoreGate;
  int medianReads = 0;
  int startRemoves = 0;
  int startRestores = 0;
  String? lastAnchor;
  int? lastPage;

  @override
  Future<CycleMediansSnapshot> readCycleMedians(
    String anchorEnd, {
    int pageOffset = 0,
    DateTime? now,
  }) async {
    medianReads++;
    lastAnchor = anchorEnd;
    lastPage = pageOffset;
    final snap = await super.readCycleMedians(
      anchorEnd,
      pageOffset: pageOffset,
      now: now,
    );
    final hold = gate;
    if (hold != null) await hold.future;
    return snap;
  }

  @override
  Future<CycleWriteResult> removeCycleStart(CycleStart expected) async {
    startRemoves++;
    return super.removeCycleStart(expected);
  }

  @override
  Future<CycleWriteResult> restoreCycleStart(
    CycleStart removed, {
    DateTime? now,
  }) async {
    startRestores++;
    final hold = restoreGate;
    if (hold != null) await hold.future;
    return super.restoreCycleStart(removed, now: now);
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
  Widget build(BuildContext context) => Column(
    children: [
      Text('host-day $day', key: const ValueKey('host-day')),
      Expanded(
        child: OpenBandCycleMedians(
          repository: repo,
          day: day,
          now: () => DateTime(2026, 9, 15, 9, 41),
          synthetic: true,
        ),
      ),
    ],
  );
}

DateTime _utcDay(String day) {
  final p = day.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2]);
}

int _utcMs(String day, int hour) =>
    _utcDay(day).add(Duration(hours: hour)).millisecondsSinceEpoch;

CycleNightSourceRow _night(
  String day, {
  bool unreadable = false,
  double? rhr = 54,
  double? hrv = 48,
  double? rhrConfidence,
  String sleepSource = 'auto',
  String? rhrNote,
  int? onsetMs,
  int? offsetMs,
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
      rhrNote: rhrNote,
      sleepSource: sleepSource,
      onsetMs: onsetMs ?? cycleNightOnsetMs(day),
      offsetMs: offsetMs ?? cycleNightOffsetMs(day),
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

  setUp(() {
    repo = _GateRepo();
    repo.seedCycleMedianFixture();
  });

  Finder capture() => find.byKey(const ValueKey('capture'));

  Future<void> expectGolden(WidgetTester tester, String name) async {
    await expectLater(capture(), matchesGoldenFile('openband_goldens/$name'));
  }

  Finder cardOf(Key plot) =>
      find.ancestor(of: find.byKey(plot), matching: find.byType(OBCard));

  late WidgetTester testerRectOwner;
  Rect testerRect(Finder plot) => testerRectOwner.getRect(plot);

  Offset slotAt(Finder plot, int i, int n) {
    final box = testerRect(plot);
    const left = 26.0;
    const right = 4.0;
    final plotW = box.width - left - right;
    final x = n <= 1
        ? box.left + left + plotW / 2
        : box.left + left + i * plotW / (n - 1);
    return Offset(x, box.center.dy);
  }

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
    testerRectOwner = tester;
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
            OpenBandCycleMedians(
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

  testWidgets('root Zyklustage sits after Messwerte before Beobachtungen', (
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
    expect(
      tester.getTopLeft(find.text('Messwerte')).dy,
      lessThan(tester.getTopLeft(find.text('Zyklustage')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Zyklustage')).dy,
      lessThan(tester.getTopLeft(find.text('Beobachtungen')).dy),
    );
    await tester.tap(find.text('Zyklustage'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cycle-medians')), findsOneWidget);
    expect(find.text('54'), findsOneWidget);
    expect(find.text('Median · Tag 23'), findsOneWidget);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cycle-overview')), findsOneWidget);
    expect(find.text('Tag 23'), findsOneWidget);
  });

  testWidgets('fixture latest values, counts, and axes', (tester) async {
    await mount(tester);
    expect(find.text('Zyklustage'), findsWidgets);
    expect(find.textContaining('16. Sept. 2025'), findsOneWidget);
    expect(find.textContaining('15. Sept. 2026'), findsOneWidget);
    expect(find.text('Ruhepuls'), findsOneWidget);
    expect(find.text('3 Zyklen'), findsNWidgets(2));
    expect(find.text('54'), findsOneWidget);
    expect(find.text('Median · Tag 23'), findsOneWidget);
    expect(find.text('Tag 1'), findsNWidgets(2));
    expect(find.text('Tag 23'), findsOneWidget);
    expect(find.text('HRV'), findsOneWidget);
    expect(find.text('48'), findsWidgets);
    expect(find.text('Median · Tag 22'), findsOneWidget);
    expect(find.text('Tag 22'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('cycle-medians-rhr-plot')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('cycle-medians-hrv-plot')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await expectGolden(tester, 'cycle-medians.png');
    await mount(tester, brightness: Brightness.dark);
    await expectGolden(tester, 'cycle-medians-dark.png');
  });

  testWidgets('RHR gap keeps HRV selection and omits a null marker', (
    tester,
  ) async {
    await mount(tester);
    const rhrPlot = ValueKey('cycle-medians-rhr-plot');
    const hrvPlot = ValueKey('cycle-medians-hrv-plot');
    await tester.tapAt(slotAt(find.byKey(rhrPlot), 5, 23));
    await tester.pump();
    expect(
      find.descendant(of: cardOf(rhrPlot), matching: find.text('—')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: cardOf(rhrPlot),
        matching: find.text('Median · Tag 6'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cardOf(rhrPlot), matching: find.text('0 Zyklen')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cardOf(hrvPlot), matching: find.text('48')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: cardOf(hrvPlot),
        matching: find.text('Median · Tag 22'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cardOf(hrvPlot), matching: find.text('3 Zyklen')),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    await expectGolden(tester, 'cycle-medians-gap.png');
  });

  testWidgets('unavailable metric hides plot and coverage', (tester) async {
    repo.seedCycleMedianFixture(includeHrv: false);
    await mount(tester);
    expect(find.text('54'), findsOneWidget);
    expect(find.text('Median · Tag 23'), findsOneWidget);
    expect(find.text('Zu wenige Nächte'), findsOneWidget);
    expect(find.byKey(const ValueKey('cycle-medians-hrv-plot')), findsNothing);
    expect(find.text('3 Zyklen'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectGolden(tester, 'cycle-medians-one-metric.png');
  });

  testWidgets('thin nights keep dash caption and omit plots', (tester) async {
    repo.clearCycleNightSources();
    await mount(tester);
    expect(find.text('Zu wenige Nächte'), findsNWidgets(2));
    expect(find.text('—'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('cycle-medians-rhr-plot')), findsNothing);
    expect(find.text('3 Zyklen'), findsNothing);
    expect(find.text('Tag 1'), findsNothing);
    await expectGolden(tester, 'cycle-medians-empty.png');
    await mount(tester, brightness: Brightness.dark);
    await expectGolden(tester, 'cycle-medians-empty-dark.png');
  });

  testWidgets('partial notice keeps charts', (tester) async {
    repo.seedCycleStart(
      const CycleStart(date: '2026-04-01', kind: kCycleStartKind),
    );
    repo.seedCycleNightSource(_night('2026-08-29', unreadable: true));
    await mount(tester);
    expect(find.text('Teilweise ausgewertet'), findsOneWidget);
    expect(find.text('54'), findsOneWidget);
    expect(find.text('Median · Tag 23'), findsOneWidget);
    await expectGolden(tester, 'cycle-medians-partial.png');
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 Zyklus ausgelassen'), findsOneWidget);
    expect(find.textContaining('Nacht nicht lesbar'), findsOneWidget);
    await expectGolden(tester, 'cycle-medians-partial-info.png');
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    await mount(tester, brightness: Brightness.dark);
    await expectGolden(tester, 'cycle-medians-partial-dark.png');
  });

  testWidgets('all-long periods are not assigned', (tester) async {
    repo.clearCycleLogs();
    repo.seedCycleStart(
      const CycleStart(date: '2025-01-01', kind: kCycleStartKind),
    );
    repo.seedCycleStart(
      const CycleStart(date: '2025-06-01', kind: kCycleStartKind),
    );
    await mount(tester);
    expect(find.text('Abstände über 60 Tage'), findsOneWidget);
    expect(find.text('Nicht zugeordnet'), findsNWidgets(2));
    expect(find.text('—'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('cycle-medians-rhr-plot')), findsNothing);
    expect(find.text('Zu wenige Nächte'), findsNothing);
    await expectGolden(tester, 'cycle-medians-long.png');
  });

  testWidgets('read exception keeps window and retries', (tester) async {
    repo.failCycleMediansRead = true;
    await mount(tester);
    expect(find.textContaining('16. Sept. 2025'), findsOneWidget);
    expect(find.textContaining('15. Sept. 2026'), findsOneWidget);
    expect(find.text('Daten nicht geladen'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(find.text('Ruhepuls'), findsNothing);
    expect(find.text('54'), findsNothing);
    await expectGolden(tester, 'cycle-medians-error.png');
    repo.failCycleMediansRead = false;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(find.text('54'), findsOneWidget);
    expect(find.text('Daten nicht geladen'), findsNothing);
  });

  testWidgets('unavailable states keep their actions', (tester) async {
    repo.clearCycleLogs();
    await mount(tester);
    expect(find.text('Kein Zyklusbeginn'), findsOneWidget);
    expect(find.text('Zum Zyklus'), findsOneWidget);
    await expectGolden(tester, 'cycle-medians-no-start.png');

    repo.cycleSettings = const CycleSettings(
      enabled: false,
      estimatesEnabled: false,
      lengthReviewEnabled: false,
    );
    repo.seedCycleMedianFixture();
    await mount(tester);
    expect(find.text('Zyklustracking aus'), findsOneWidget);
    expect(find.text('Einstellungen'), findsOneWidget);
    await expectGolden(tester, 'cycle-medians-disabled.png');
    await tester.tap(find.text('Einstellungen'));
    await tester.pumpAndSettle();
    expect(find.text('Zyklus im Journal'), findsOneWidget);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cycle-medians')), findsOneWidget);

    repo.cycleSettings = const CycleSettings(
      enabled: true,
      estimatesEnabled: true,
      lengthReviewEnabled: false,
    );
    repo.clearCycleLogs();
    repo.seedUnreadableCycleStart({'date': '2026-08-24', 'kind': 1});
    await mount(tester);
    expect(find.text('Beginn nicht lesbar'), findsOneWidget);
    expect(find.text('Zum Verlauf'), findsOneWidget);
    await expectGolden(tester, 'cycle-medians-unreadable.png');
    await tester.tap(find.text('Zum Verlauf'));
    await tester.pumpAndSettle();
    expect(find.text('Verlauf'), findsWidgets);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cycle-medians')), findsOneWidget);
  });

  testWidgets('settings return rereads and withholds prior state', (
    tester,
  ) async {
    repo.cycleSettings = const CycleSettings(
      enabled: false,
      estimatesEnabled: false,
      lengthReviewEnabled: false,
    );
    await mount(tester);
    expect(find.text('Zyklustracking aus'), findsOneWidget);
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
    expect(find.text('Zyklustracking aus'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    hold.complete();
    await tester.pumpAndSettle();
    expect(find.text('Zyklustracking aus'), findsNothing);
    expect(find.text('Ruhepuls'), findsOneWidget);
  });

  testWidgets('earlier empty starts keep the requested window', (tester) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('cycle-medians-earlier')));
    await tester.pumpAndSettle();
    expect(repo.lastPage, 1);
    expect(find.textContaining('16. Sept. 2024'), findsOneWidget);
    expect(find.textContaining('15. Sept. 2025'), findsOneWidget);
    expect(find.text('Kein Zyklusbeginn'), findsOneWidget);
    expect(find.text('Zum Zyklus'), findsOneWidget);
    expect(find.text('54'), findsNothing);
    expect(find.text('Zu wenige Nächte'), findsNothing);
    await expectGolden(tester, 'cycle-medians-earlier.png');
    await tester.tap(find.byKey(const ValueKey('cycle-medians-later')));
    await tester.pumpAndSettle();
    expect(repo.lastPage, 0);
    expect(find.text('54'), findsOneWidget);
  });

  testWidgets('end date picker cancel and confirm are independent of day', (
    tester,
  ) async {
    final hostKey = GlobalKey<_HostState>();
    await mount(
      tester,
      home: _Host(key: hostKey, initialRepo: repo, initialDay: '2026-09-15'),
    );
    expect(find.text('host-day 2026-09-15'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cycle-medians-window')));
    await tester.pumpAndSettle();
    expect(find.text('Enddatum'), findsOneWidget);
    expect(find.text('Datum'), findsNothing);
    await expectGolden(tester, 'cycle-medians-date.png');
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('54'), findsOneWidget);
    expect(repo.lastAnchor, '2026-09-15');
    expect(find.text('host-day 2026-09-15'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cycle-medians-earlier')));
    await tester.pumpAndSettle();
    expect(repo.lastPage, 1);
    await tester.tap(find.byKey(const ValueKey('cycle-medians-window')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(repo.lastPage, 0);
    expect(repo.lastAnchor, '2026-09-15');
    expect(find.text('host-day 2026-09-15'), findsOneWidget);
    expect(find.text('54'), findsOneWidget);
  });

  testWidgets('future selected day clamps the anchor only', (tester) async {
    await mount(tester, day: '2026-09-20');
    expect(repo.lastAnchor, '2026-09-15');
    expect(find.textContaining('15. Sept. 2026'), findsOneWidget);
    expect(find.text('54'), findsOneWidget);
  });

  testWidgets('paging does not keep previous metrics under new dates', (
    tester,
  ) async {
    final hold = Completer<void>();
    await mount(tester);
    expect(find.text('54'), findsOneWidget);
    repo.gate = hold;
    await tester.tap(find.byKey(const ValueKey('cycle-medians-earlier')));
    await tester.pump();
    expect(find.text('54'), findsNothing);
    expect(find.textContaining('16. Sept. 2024'), findsOneWidget);
    hold.complete();
    await tester.pumpAndSettle();
    expect(find.text('Kein Zyklusbeginn'), findsOneWidget);
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

    final second = _GateRepo()..seedCycleMedianFixture(includeHrv: false);
    final secondGate = Completer<void>();
    second.gate = secondGate;
    hostKey.currentState!.update(repository: second);
    await tester.pump();
    expect(find.text('54'), findsNothing);

    first.complete();
    await tester.pump();
    expect(find.text('54'), findsNothing);
    expect(find.text('Zu wenige Nächte'), findsNothing);

    secondGate.complete();
    await tester.pumpAndSettle();
    expect(find.text('54'), findsOneWidget);
    expect(find.text('Zu wenige Nächte'), findsOneWidget);
    expect(find.text('Median · Tag 22'), findsNothing);
  });

  testWidgets('unmount ignores in-flight reads', (tester) async {
    final hold = Completer<void>();
    repo.gate = hold;
    await mount(tester, settle: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    hold.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('source info uses contributors, MDC, and scrollable last para', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Mediane vergleichen denselben Tag ab einem eingetragenen Beginn. Jeder Punkt braucht Nächte aus zwei Zyklen; die Kurve mindestens drei solche Tage.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Abstände und laufende Zyklen über 60 Tage werden ausgelassen. Die Zuordnung beschreibt keine Zyklusphase.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Ruhepuls · Tag 23 · 54 bpm'), findsOneWidget);
    expect(find.textContaining('21. Juli · Beginn 29. Juni'), findsOneWidget);
    expect(find.textContaining('22. Aug. · Beginn 31. Juli'), findsOneWidget);
    expect(find.textContaining('15. Sept. · Beginn 24. Aug.'), findsOneWidget);
    expect(
      find.textContaining('Jeweils 54 bpm · Qualitätswert —'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Schlaf: automatisch · Stufe: HIGH · Eingaben: Puls (1 Hz), Schlaffenster',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('HRV · Tag 22 · 48 ms'), findsOneWidget);
    expect(find.textContaining('20. Juli · Beginn 29. Juni'), findsOneWidget);
    expect(
      find.textContaining('Jeweils 48 ms · Qualitätswert —'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Schlaf: automatisch · Stufe: HIGH · Eingaben: RR-Intervalle im Schlaffenster',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('100 %'), findsNothing);
    expect(find.textContaining('Eisprung'), findsNothing);
    expect(
      find.textContaining('Vortag, 16:00 bis zum genannten Datum, 06:00 UTC'),
      findsOneWidget,
    );
    expect(find.textContaining('Algorithmus $kAlgoVersion'), findsOneWidget);
    expect(
      find.textContaining(
        'Robustes Streuungsmaß (MDC): Ruhepuls 4,1 bpm aus 57 Nächten; HRV 6,2 ms aus 48 Nächten.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('keine gemessene Sensorabweichung'),
      findsOneWidget,
    );
    await expectGolden(tester, 'cycle-medians-info.png');
    final last = find.textContaining('keine gemessene Sensorabweichung');
    final infoScroll = find.byKey(const ValueKey('journal-info-body'));
    await tester.scrollUntilVisible(
      last,
      80,
      scrollable: find.descendant(
        of: infoScroll,
        matching: find.byType(Scrollable),
      ),
    );
    expect(last, findsOneWidget);
    expect(find.text('Schließen'), findsWidgets);
  });

  testWidgets('info keeps per-source bounds when RHR and HRV windows differ', (
    tester,
  ) async {
    for (final day in ['2026-07-20', '2026-08-21', '2026-09-14']) {
      repo.seedCycleNightSource(
        _night(
          day,
          rhr: 54,
          hrv: 48,
          onsetMs: _utcMs(day, 2),
          offsetMs: _utcMs(day, 6),
        ),
      );
    }
    await mount(tester);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Vortag, 16:00 bis zum genannten Datum, 06:00 UTC'),
      findsOneWidget,
    );
    expect(find.textContaining('2:00'), findsWidgets);
    expect(find.textContaining('6:00'), findsWidgets);
    expect(find.textContaining('Algorithmus $kAlgoVersion'), findsWidgets);
    final body = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .join('\n');
    final hrvIdx = body.indexOf('HRV · Tag 22');
    expect(hrvIdx, greaterThan(0));
    expect(body.substring(hrvIdx).contains('16:00'), isFalse);
  });

  testWidgets('info same-day windows keep bounds and algo', (tester) async {
    for (final day in [
      '2026-07-20',
      '2026-07-21',
      '2026-08-21',
      '2026-08-22',
      '2026-09-14',
      '2026-09-15',
    ]) {
      repo.seedCycleNightSource(
        _night(day, onsetMs: _utcMs(day, 2), offsetMs: _utcMs(day, 6)),
      );
    }
    await mount(tester);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Vortag, 16:00'), findsNothing);
    expect(find.textContaining('02:00'), findsWidgets);
    expect(find.textContaining('06:00 UTC'), findsWidgets);
    expect(find.textContaining('Algorithmus $kAlgoVersion'), findsWidgets);
    expect(
      find.text(
        'Qualitätswerte sind gespeicherte Scores, keine Fehlerspannen.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('info gap selection does not drop the other metric bounds', (
    tester,
  ) async {
    await mount(tester);
    await tester.tapAt(
      slotAt(find.byKey(const ValueKey('cycle-medians-rhr-plot')), 5, 23),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ruhepuls · Tag 6 · —'), findsOneWidget);
    expect(find.textContaining('HRV · Tag 22 · 48 ms'), findsOneWidget);
    expect(
      find.textContaining('Vortag, 16:00 bis zum genannten Datum, 06:00 UTC'),
      findsOneWidget,
    );
    expect(find.textContaining('20. Juli · Beginn 29. Juni'), findsOneWidget);
  });

  testWidgets('info equal values still show distinct qualities', (
    tester,
  ) async {
    repo.seedCycleNightSource(
      _night('2026-07-21', hrv: null, rhrConfidence: 0.9),
    );
    repo.seedCycleNightSource(
      _night('2026-08-22', hrv: null, rhrConfidence: 0.4),
    );
    repo.seedCycleNightSource(_night('2026-09-15', hrv: null));
    await mount(tester);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Jeweils 54 bpm'), findsNothing);
    expect(find.textContaining('Qualitätswert 0,90 / 1'), findsOneWidget);
    expect(find.textContaining('Qualitätswert 0,40 / 1'), findsOneWidget);
    expect(find.textContaining('54 bpm'), findsWidgets);
  });

  testWidgets('info mixed provenance keeps source note and tier', (
    tester,
  ) async {
    repo.seedCycleNightSource(
      _night(
        '2026-07-21',
        hrv: null,
        sleepSource: 'manual',
        rhrNote: 'korrigiert',
      ),
    );
    repo.seedCycleNightSource(
      _night('2026-08-22', hrv: null, sleepSource: 'confirmed'),
    );
    repo.seedCycleNightSource(_night('2026-09-15', hrv: null));
    await mount(tester);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Schlaf: manuell'), findsOneWidget);
    expect(find.textContaining('Hinweis: korrigiert'), findsOneWidget);
    expect(find.textContaining('Schlaf: bestätigt'), findsOneWidget);
    expect(find.textContaining('Stufe: HIGH'), findsWidgets);
    expect(
      find.textContaining('Eingaben: Puls (1 Hz), Schlaffenster'),
      findsWidgets,
    );
  });

  testWidgets('header chevrons stay 44 and grow at 2x', (tester) async {
    await mount(tester);
    final earlier = tester.getRect(
      find.byKey(const ValueKey('cycle-medians-earlier')),
    );
    final later = tester.getRect(
      find.byKey(const ValueKey('cycle-medians-later')),
    );
    expect(earlier.width, 44);
    expect(earlier.height, 44);
    expect(later.width, 44);
    expect(later.height, 44);
    expect(tester.getRect(find.byType(OBWindowPager)).height, 64);
    final laterButton = tester.widget<IconButton>(
      find.byKey(const ValueKey('cycle-medians-later')),
    );
    expect(laterButton.onPressed, isNull);

    await mount(tester, scale: 2, width: 375, height: 812);
    expect(find.text('54'), findsOneWidget);
    expect(find.text('Median · Tag 23'), findsOneWidget);
    final pager = tester.getRect(find.byType(OBWindowPager));
    expect(pager.height, greaterThan(64));
    final range = tester.widget<Text>(find.textContaining('16. Sept. 2025'));
    expect(range.style?.fontSize, 15);
    expect(range.style?.height, 20 / 15);
    expect(range.style?.fontWeight, FontWeight.w600);
    expect(tester.takeException(), isNull);
    await expectGolden(tester, 'cycle-medians-large-top.png');
    await tester.scrollUntilVisible(find.text('Synthetische Daten'), 200);
    await expectGolden(tester, 'cycle-medians-large-bottom.png');
    await expectGolden(tester, 'cycle-medians-large.png');
    await mount(
      tester,
      scale: 2,
      width: 375,
      height: 812,
      brightness: Brightness.dark,
    );
    await expectGolden(tester, 'cycle-medians-large-dark.png');
    await tester.scrollUntilVisible(find.text('Synthetische Daten'), 200);
    await expectGolden(tester, 'cycle-medians-large-dark-bottom.png');
  });

  testWidgets('semantics walk every slot including gaps', (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await mount(tester);
      final plot = find.byKey(const ValueKey('cycle-medians-rhr-plot'));
      var node = tester.getSemantics(plot);
      expect(node.value, contains('Tag 23'));
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.decrease),
        isTrue,
      );
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.increase),
        isFalse,
      );
      await tester.tapAt(slotAt(plot, 5, 23));
      await tester.pump();
      node = tester.getSemantics(plot);
      expect(node.value, contains('Tag 6'));
      expect(node.value, contains('kein Wert'));
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.increase),
        isTrue,
      );
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.decrease),
        isTrue,
      );
    } finally {
      handle.dispose();
    }
  });

  testWidgets('insufficientDays still discloses partialness', (tester) async {
    repo.clearCycleNightSources();
    repo.seedCycleNightSource(_night('2026-08-29', unreadable: true));
    await mount(tester);
    expect(find.text('Teilweise ausgewertet'), findsOneWidget);
    expect(find.text('Zu wenige Nächte'), findsNWidgets(2));
    expect(find.text('Abstände über 60 Tage'), findsNothing);
    await expectGolden(tester, 'cycle-medians-partial-thin.png');
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nacht nicht lesbar'), findsOneWidget);
  });

  testWidgets('history remove receipt survives return and restores edits', (
    tester,
  ) async {
    const original = CycleStart(
      date: '2026-08-24',
      kind: kCycleStartKind,
      note: '  exact\nsource  ',
    );
    repo.seedCycleStart(original);
    repo.seedUnreadableCycleStart({'date': '2026-05-01', 'kind': 1});
    repo.failCycleContextRefresh = true;
    await mount(tester);
    expect(find.text('Beginn nicht lesbar'), findsOneWidget);
    await tester.tap(find.text('Zum Verlauf'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cycle-history')), findsOneWidget);
    await tester.tap(find.text('24. August'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen').last);
    await tester.pumpAndSettle();
    expect(repo.startRemoves, 1);
    expect(
      find.text('Entfernt · Aktualisieren fehlgeschlagen'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cycle-medians')), findsOneWidget);
    expect(
      find.text('Entfernt · Aktualisieren fehlgeschlagen'),
      findsOneWidget,
    );
    expect(find.text('Rückgängig').hitTestable(), findsOneWidget);
    expect(find.text('54'), findsNothing);
    repo.failCycleContextRefresh = false;
    await tester.tap(find.text('Rückgängig'));
    await tester.pumpAndSettle();
    expect(repo.startRemoves, 1);
    expect(repo.startRestores, 1);
    final snap = await repo.readCycle('2026-09-15');
    expect(
      snap.starts.where((s) => s.date == original.date).single.note,
      original.note,
    );
    expect(find.text('Aktualisieren fehlgeschlagen'), findsNothing);
    expect(find.text('Beginn nicht lesbar'), findsOneWidget);
  });

  testWidgets('in-flight restore ignores pager and back', (tester) async {
    const original = CycleStart(
      date: '2026-08-24',
      kind: kCycleStartKind,
      note: '  exact\nsource  ',
    );
    repo.seedCycleStart(original);
    repo.seedUnreadableCycleStart({'date': '2026-05-01', 'kind': 1});
    await mount(tester);
    await tester.tap(find.text('Zum Verlauf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('24. August'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('Rückgängig'), findsOneWidget);
    final hold = Completer<void>();
    repo.restoreGate = hold;
    await tester.tap(find.text('Rückgängig'));
    await tester.pump();
    expect(repo.startRestores, 1);
    expect(find.byKey(const ValueKey('cycle-medians')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cycle-medians-earlier')));
    await tester.pump();
    expect(repo.lastPage, 0);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pump();
    expect(find.byKey(const ValueKey('cycle-medians')), findsOneWidget);
    hold.complete();
    repo.restoreGate = null;
    await tester.pumpAndSettle();
    expect(repo.startRestores, 1);
    final snap = await repo.readCycle('2026-09-15');
    expect(
      snap.starts.where((s) => s.date == original.date).single.note,
      original.note,
    );
    await tester.tap(find.byKey(const ValueKey('cycle-medians-earlier')));
    await tester.pumpAndSettle();
    expect(repo.lastPage, 1);
  });

  testWidgets('refresh retry does not repeat a committed restore', (
    tester,
  ) async {
    const original = CycleStart(
      date: '2026-08-24',
      kind: kCycleStartKind,
      note: 'keep',
    );
    repo.seedCycleStart(original);
    repo.seedUnreadableCycleStart({'date': '2026-05-01', 'kind': 1});
    repo.failCycleContextRefresh = true;
    await mount(tester);
    await tester.tap(find.text('Zum Verlauf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('24. August'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(
      find.text('Entfernt · Aktualisieren fehlgeschlagen'),
      findsOneWidget,
    );
    await expectGolden(tester, 'cycle-medians-removed-refresh.png');
    await tester.tap(find.text('Rückgängig'));
    await tester.pumpAndSettle();
    expect(repo.startRestores, 1);
    expect(
      find.text('Wiederhergestellt · Aktualisieren fehlgeschlagen'),
      findsOneWidget,
    );
    await expectGolden(tester, 'cycle-medians-restored-refresh.png');
    repo.failCycleContextRefresh = false;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(repo.startRestores, 1);
    expect(repo.startRemoves, 1);
    expect(find.text('Aktualisieren fehlgeschlagen'), findsNothing);
    final snap = await repo.readCycle('2026-09-15');
    expect(
      snap.starts.where((s) => s.date == original.date).single.note,
      original.note,
    );
  });

  testWidgets('restore write failure keeps retry identity', (tester) async {
    const original = CycleStart(
      date: '2026-08-24',
      kind: kCycleStartKind,
      note: 'keep',
    );
    repo.seedCycleStart(original);
    repo.seedUnreadableCycleStart({'date': '2026-05-01', 'kind': 1});
    await mount(tester);
    await tester.tap(find.text('Zum Verlauf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('24. August'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('Rückgängig'), findsOneWidget);
    repo.failCycleWrite = true;
    await tester.tap(find.text('Rückgängig'));
    await tester.pumpAndSettle();
    expect(repo.startRestores, 1);
    expect(find.text('Wiederherstellen fehlgeschlagen'), findsOneWidget);
    expect(find.text('Erneut'), findsOneWidget);
    expect(find.text('Beginn 24. Aug. entfernt'), findsNothing);
    repo.failCycleWrite = false;
    await tester.tap(find.text('Erneut'));
    await tester.pumpAndSettle();
    expect(repo.startRestores, 2);
    expect(repo.startRemoves, 1);
    final snap = await repo.readCycle('2026-09-15');
    expect(
      snap.starts.where((s) => s.date == original.date).single.note,
      original.note,
    );
  });

  testWidgets('busy restore blocks settings history and refresh retry', (
    tester,
  ) async {
    const original = CycleStart(
      date: '2026-08-24',
      kind: kCycleStartKind,
      note: 'keep',
    );
    repo.seedCycleStart(original);
    repo.seedUnreadableCycleStart({'date': '2026-05-01', 'kind': 1});
    repo.failCycleContextRefresh = true;
    await mount(tester);
    await tester.tap(find.text('Zum Verlauf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('24. August'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    final hold = Completer<void>();
    repo.restoreGate = hold;
    await tester.tap(find.text('Rückgängig'));
    await tester.pump();
    expect(repo.startRestores, 1);
    await tester.tap(find.text('Zum Verlauf'));
    await tester.pump();
    expect(find.byKey(const ValueKey('cycle-history')), findsNothing);
    expect(find.text('Einstellungen'), findsNothing);
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pump();
    hold.complete();
    repo.restoreGate = null;
    await tester.pumpAndSettle();
    expect(repo.startRestores, 1);
    expect(find.byKey(const ValueKey('cycle-medians')), findsOneWidget);
  });

  testWidgets('year-1 end does not crash the window', (tester) async {
    await mount(tester, day: '0001-01-15');
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('cycle-medians')), findsOneWidget);
    expect(find.byType(OBWindowPager), findsNothing);
    expect(find.text('Daten nicht geladen'), findsOneWidget);
  });

  testWidgets('history receipt survives pop to cycle root', (tester) async {
    const original = CycleStart(
      date: '2026-08-24',
      kind: kCycleStartKind,
      note: '  exact\nsource  ',
    );
    repo.seedCycleStart(original);
    repo.seedUnreadableCycleStart({'date': '2026-05-01', 'kind': 1});
    repo.failCycleContextRefresh = true;
    await mount(
      tester,
      home: OpenBandCycle(
        repository: repo,
        day: '2026-09-15',
        now: () => DateTime(2026, 9, 15, 9, 41),
        synthetic: true,
      ),
    );
    await tester.tap(find.text('Zyklustage'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cycle-medians')), findsOneWidget);
    await tester.tap(find.text('Zum Verlauf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('24. August'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cycle-medians')), findsOneWidget);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cycle-overview')), findsOneWidget);
    expect(
      find.text('Entfernt · Aktualisieren fehlgeschlagen'),
      findsOneWidget,
    );
    expect(find.text('Rückgängig').hitTestable(), findsOneWidget);
    repo.failCycleContextRefresh = false;
    await tester.tap(find.text('Rückgängig'));
    await tester.pumpAndSettle();
    expect(repo.startRemoves, 1);
    expect(repo.startRestores, 1);
    final snap = await repo.readCycle('2026-09-15');
    expect(
      snap.starts.where((s) => s.date == original.date).single.note,
      original.note,
    );
  });

  testWidgets('error after page change does not restore old metrics', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('54'), findsOneWidget);
    repo.failCycleMediansRead = true;
    await tester.tap(find.byKey(const ValueKey('cycle-medians-earlier')));
    await tester.pumpAndSettle();
    expect(find.textContaining('16. Sept. 2024'), findsOneWidget);
    expect(find.text('Daten nicht geladen'), findsOneWidget);
    expect(find.text('54'), findsNothing);
    expect(find.text('Median · Tag 23'), findsNothing);
  });
}
