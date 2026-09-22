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
import 'package:openstrap_edge/openband/alp_tokens.dart';
import 'package:openstrap_edge/openband/cycle.dart';
import 'package:openstrap_edge/openband/cycle_comparison.dart';
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
  int comparisonReads = 0;
  String? lastAnchor;
  int? lastPage;

  @override
  Future<CycleComparisonSnapshot> readCycleComparison(
    String anchorEnd, {
    int pageOffset = 0,
    DateTime? now,
  }) async {
    comparisonReads++;
    lastAnchor = anchorEnd;
    lastPage = pageOffset;
    final snap = await super.readCycleComparison(
      anchorEnd,
      pageOffset: pageOffset,
      now: now,
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
  Widget build(BuildContext context) => Column(
    children: [
      Text('host-day $day', key: const ValueKey('host-day')),
      Expanded(
        child: OpenBandCycleComparison(
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
  String sleepSource = 'auto',
  String? rhrNote,
  String? hrvNote,
  int? onsetMs,
  int? offsetMs,
  bool imported = false,
  bool omitSleepWindow = false,
}) {
  if (unreadable) {
    return CycleNightSourceRow(
      day: day,
      algoVersion: kAlgoVersion,
      payloadUnreadable: true,
    );
  }
  final payload = Map<String, Object?>.from(
    cycleNightSourcePayload(
      rhr: rhr,
      hrv: hrv,
      rhrNote: rhrNote,
      hrvNote: hrvNote,
      sleepSource: sleepSource,
      imported: imported,
      onsetMs: onsetMs ?? cycleNightOnsetMs(day),
      offsetMs: offsetMs ?? cycleNightOffsetMs(day),
    ),
  );
  if (omitSleepWindow) payload.remove('sleep');
  return CycleNightSourceRow(
    day: day,
    algoVersion: kAlgoVersion,
    payload: payload,
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
    repo.seedCycleComparisonFixture();
  });

  Finder capture() => find.byKey(const ValueKey('capture'));

  Future<void> expectGolden(WidgetTester tester, String name) async {
    await expectLater(capture(), matchesGoldenFile('openband_goldens/$name'));
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
            OpenBandCycleComparison(
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

  testWidgets('root Vergleich sits after Zyklustage before Beobachtungen', (
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
      tester.getTopLeft(find.text('Zyklustage')).dy,
      lessThan(tester.getTopLeft(find.text('Vergleich')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Vergleich')).dy,
      lessThan(tester.getTopLeft(find.text('Beobachtungen')).dy),
    );
    await tester.tap(find.text('Vergleich'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cycle-comparison')), findsOneWidget);
    expect(find.text('56'), findsOneWidget);
    expect(find.text('Nacht · Tag 23'), findsOneWidget);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cycle-overview')), findsOneWidget);
    expect(find.text('Tag 23'), findsOneWidget);
  });

  testWidgets('fixture latest values, independent dates and counts', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('Vergleich'), findsWidgets);
    expect(find.textContaining('16. Sept. 2025'), findsOneWidget);
    expect(find.textContaining('15. Sept. 2026'), findsWidgets);
    expect(find.text('Ruhepuls'), findsOneWidget);
    expect(find.text('56'), findsOneWidget);
    expect(find.text('Nacht · Tag 23'), findsOneWidget);
    expect(find.text('17 Nächte'), findsOneWidget);
    expect(find.text('−0,2 bpm'), findsOneWidget);
    expect(find.text('+4,0 bpm'), findsOneWidget);
    expect(find.text('HRV'), findsOneWidget);
    expect(find.text('51'), findsOneWidget);
    expect(find.text('Nacht · Tag 22'), findsOneWidget);
    expect(find.textContaining('14. Sept. 2026'), findsOneWidget);
    expect(find.text('15 Nächte'), findsOneWidget);
    expect(find.text('+1,3 ms'), findsOneWidget);
    expect(find.text('+4,0 ms'), findsOneWidget);
    expect(find.text('3 frühere Zyklen'), findsNWidgets(2));
    expect(find.text('Gegenüber dem Mittelwert'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await expectGolden(tester, 'cycle-comparison.png');
    await mount(tester, brightness: Brightness.dark);
    await expectGolden(tester, 'cycle-comparison-dark.png');
  });

  testWidgets('missing latest omits the reference block', (tester) async {
    repo.clearCycleNightSources();
    await mount(tester);
    expect(find.text('Keine Nacht'), findsNWidgets(2));
    expect(find.text('—'), findsNWidgets(2));
    expect(find.text('Gegenüber dem Mittelwert'), findsNothing);
    expect(find.text('21 Tage davor'), findsNothing);
    expect(tester.takeException(), isNull);
    await expectGolden(tester, 'cycle-comparison-empty.png');
    await mount(tester, brightness: Brightness.dark);
    await expectGolden(tester, 'cycle-comparison-empty-dark.png');
  });

  testWidgets('unavailable stored metric is not presented as no readings', (
    tester,
  ) async {
    final snap = await repo.readCycleComparison(
      '2026-09-15',
      now: DateTime(2026, 9, 15, 9, 41),
    );
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(Brightness.light),
        home: Scaffold(
          body: ListView(
            children: [
              OBNightComparisonCard(
                label: 'Ruhepuls',
                unit: 'bpm',
                iconColor: AlpColor.pulse,
                metric: const CycleMetricComparison(
                  latestReason: CycleComparisonLatestReason.unavailable,
                ),
              ),
              OBNightComparisonCard(
                label: 'HRV',
                unit: 'ms',
                iconColor: AlpColor.recovery,
                metric: snap.hrv,
              ),
              const Text('Teilweise ausgewertet'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Nicht auswertbar'), findsOneWidget);
    expect(find.text('Keine Nacht'), findsNothing);
    expect(find.text('51'), findsOneWidget);
    expect(find.text('Gegenüber dem Mittelwert'), findsOneWidget);
    expect(find.text('Teilweise ausgewertet'), findsOneWidget);
  });

  testWidgets('thin references keep counts and dash deltas', (tester) async {
    repo.clearCycleNightSources();
    repo.seedCycleNightSource(_night('2026-09-15', rhr: 56, hrv: null));
    repo.seedCycleNightSource(_night('2026-09-14', rhr: null, hrv: 51));
    repo.seedCycleNightSource(_night('2026-09-10', rhr: 54, hrv: 48));
    repo.seedCycleNightSource(_night('2026-07-21', rhr: 52, hrv: null));
    repo.seedCycleNightSource(_night('2026-06-19', rhr: 50, hrv: null));
    repo.seedCycleNightSource(_night('2026-07-20', rhr: null, hrv: 47));
    repo.seedCycleNightSource(_night('2026-06-18', rhr: null, hrv: 45));
    await mount(tester);
    expect(find.text('56'), findsOneWidget);
    expect(find.text('51'), findsOneWidget);
    expect(find.text('1 Nacht'), findsNWidgets(2));
    expect(find.text('2 frühere Zyklen'), findsNWidgets(2));
    expect(find.text('—'), findsNWidgets(4));
    expect(find.text('Gegenüber dem Mittelwert'), findsNWidgets(2));
    await expectGolden(tester, 'cycle-comparison-thin.png');
  });

  testWidgets('no starts keep latest and prior-21', (tester) async {
    repo.clearCycleLogs();
    await mount(tester);
    expect(find.text('56'), findsOneWidget);
    expect(find.text('51'), findsOneWidget);
    expect(find.text('17 Nächte'), findsOneWidget);
    expect(find.text('15 Nächte'), findsOneWidget);
    expect(find.text('−0,2 bpm'), findsOneWidget);
    expect(find.text('+1,3 ms'), findsOneWidget);
    expect(find.text('Kein Zyklusbeginn'), findsNWidgets(2));
    expect(find.text('Nacht · Tag 23'), findsNothing);
    expect(find.text('Nacht · Tag 22'), findsNothing);
    expect(find.text('Nacht'), findsNWidgets(2));
    await expectGolden(tester, 'cycle-comparison-no-start.png');
  });

  testWidgets('unreadable starts keep latest and prior-21', (tester) async {
    repo.clearCycleLogs();
    repo.seedUnreadableCycleStart({'date': '2026-08-24', 'kind': 1});
    await mount(tester);
    expect(find.text('56'), findsOneWidget);
    expect(find.text('17 Nächte'), findsOneWidget);
    expect(find.text('Beginn nicht lesbar'), findsNWidgets(2));
    expect(find.text('Nacht · Tag 23'), findsNothing);
    await expectGolden(tester, 'cycle-comparison-unreadable.png');
  });

  testWidgets('long period keeps latest and prior-21', (tester) async {
    repo.clearCycleLogs();
    repo.seedCycleStart(
      const CycleStart(date: '2025-01-01', kind: kCycleStartKind),
    );
    await mount(tester);
    expect(find.text('56'), findsOneWidget);
    expect(find.text('17 Nächte'), findsOneWidget);
    expect(find.text('Abstand über 60 Tage'), findsNWidgets(2));
    expect(find.text('Nacht'), findsNWidgets(2));
    expect(find.textContaining('Nacht · Tag'), findsNothing);
    await expectGolden(tester, 'cycle-comparison-long.png');
  });

  testWidgets('one missing metric keeps the other', (tester) async {
    repo.seedCycleComparisonFixture(includeHrv: false);
    await mount(tester);
    expect(find.text('56'), findsOneWidget);
    expect(find.text('Nacht · Tag 23'), findsOneWidget);
    expect(find.text('Keine Nacht'), findsOneWidget);
    expect(find.text('51'), findsNothing);
    expect(find.text('Gegenüber dem Mittelwert'), findsOneWidget);
    await expectGolden(tester, 'cycle-comparison-one-metric.png');
  });

  testWidgets('partial notice keeps cards', (tester) async {
    repo.seedCycleNightSource(_night('2026-08-29', unreadable: true));
    await mount(tester);
    expect(find.text('Teilweise ausgewertet'), findsOneWidget);
    expect(find.text('56'), findsOneWidget);
    expect(find.text('Nacht · Tag 23'), findsOneWidget);
    await expectGolden(tester, 'cycle-comparison-partial.png');
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Gewähltes Jahr und 21-Tage-Vergleiche: 1 Nacht mit nicht lesbaren Daten.',
      ),
      findsOneWidget,
    );
    expect(find.text('Ruhepuls · Quellen'), findsOneWidget);
    await expectGolden(tester, 'cycle-comparison-partial-info.png');
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    await mount(tester, brightness: Brightness.dark);
    await expectGolden(tester, 'cycle-comparison-partial-dark.png');
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Gewähltes Jahr und 21-Tage-Vergleiche: 1 Nacht mit nicht lesbaren Daten.',
      ),
      findsOneWidget,
    );
    await expectGolden(tester, 'cycle-comparison-partial-info-dark.png');
  });

  testWidgets('unreadable-only night is not presented as no readings', (
    tester,
  ) async {
    repo.clearCycleNightSources();
    repo.seedCycleNightSource(_night('2026-09-15', unreadable: true));
    await mount(tester);
    expect(find.text('Teilweise ausgewertet'), findsOneWidget);
    expect(find.text('Nicht auswertbar'), findsNWidgets(2));
    expect(find.text('Keine Nacht'), findsNothing);
    expect(find.text('Gegenüber dem Mittelwert'), findsNothing);
    expect(find.text('56'), findsNothing);
    await expectGolden(tester, 'cycle-comparison-unavailable.png');
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Gewähltes Jahr und 21-Tage-Vergleiche: 1 Nacht mit nicht lesbaren Daten.',
      ),
      findsOneWidget,
    );
    expect(find.text('Ruhepuls · Quellen'), findsNothing);
    expect(find.text('HRV · Quellen'), findsNothing);
    await expectGolden(tester, 'cycle-comparison-unavailable-info.png');
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    await mount(tester, brightness: Brightness.dark);
    await expectGolden(tester, 'cycle-comparison-unavailable-dark.png');
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(find.text('Ruhepuls · Quellen'), findsNothing);
    await expectGolden(tester, 'cycle-comparison-unavailable-info-dark.png');
  });

  testWidgets('read exception keeps window and retries', (tester) async {
    repo.failCycleComparisonRead = true;
    await mount(tester);
    expect(find.textContaining('16. Sept. 2025'), findsOneWidget);
    expect(find.textContaining('15. Sept. 2026'), findsOneWidget);
    expect(find.text('Daten nicht geladen'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(find.text('Ruhepuls'), findsNothing);
    expect(find.text('56'), findsNothing);
    await expectGolden(tester, 'cycle-comparison-error.png');
    repo.failCycleComparisonRead = false;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(find.text('56'), findsOneWidget);
    expect(find.text('Daten nicht geladen'), findsNothing);
  });

  testWidgets('disabled opens settings and rereads on return', (tester) async {
    repo.cycleSettings = const CycleSettings(
      enabled: false,
      estimatesEnabled: false,
      lengthReviewEnabled: false,
    );
    await mount(tester);
    expect(find.text('Zyklustracking aus'), findsOneWidget);
    expect(find.text('Einstellungen'), findsOneWidget);
    await expectGolden(tester, 'cycle-comparison-disabled.png');
    await tester.tap(find.text('Einstellungen'));
    await tester.pumpAndSettle();
    expect(find.text('Zyklus im Journal'), findsOneWidget);
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
    expect(find.text('56'), findsOneWidget);
  });

  testWidgets('end date picker cancel and confirm keep the root day', (
    tester,
  ) async {
    final hostKey = GlobalKey<_HostState>();
    await mount(
      tester,
      home: _Host(key: hostKey, initialRepo: repo, initialDay: '2026-09-15'),
    );
    expect(find.text('host-day 2026-09-15'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cycle-comparison-window')));
    await tester.pumpAndSettle();
    expect(find.text('Enddatum'), findsOneWidget);
    expect(find.text('Datum'), findsNothing);
    await expectGolden(tester, 'cycle-comparison-date.png');
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('56'), findsOneWidget);
    expect(repo.lastAnchor, '2026-09-15');
    expect(find.text('host-day 2026-09-15'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cycle-comparison-window')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(repo.lastPage, 0);
    expect(repo.lastAnchor, '2026-09-01');
    expect(find.text('host-day 2026-09-15'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('cycle-comparison-window')),
              matching: find.byType(Text),
            ),
          )
          .data,
      '2. Sept. 2025–\n1. Sept. 2026',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('cycle-comparison-rhr')),
        matching: find.text('1. Sept. 2026'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('cycle-comparison-hrv')),
        matching: find.text('1. Sept. 2026'),
      ),
      findsOneWidget,
    );
    expect(find.text('15. Sept. 2026'), findsNothing);
  });

  testWidgets('earlier empty years are missing nights not missing starts', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('cycle-comparison-earlier')));
    await tester.pumpAndSettle();
    expect(repo.lastPage, 1);
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('cycle-comparison-window')),
              matching: find.byType(Text),
            ),
          )
          .data,
      '16. Sept. 2024–\n15. Sept. 2025',
    );
    expect(find.text('Keine Nacht'), findsNWidgets(2));
    expect(find.text('Kein Zyklusbeginn'), findsNothing);
    expect(find.text('56'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('cycle-comparison-later')));
    await tester.pumpAndSettle();
    expect(repo.lastPage, 0);
    expect(find.text('56'), findsOneWidget);
  });

  testWidgets('paging does not keep previous metrics under new dates', (
    tester,
  ) async {
    final hold = Completer<void>();
    await mount(tester);
    expect(find.text('56'), findsOneWidget);
    repo.gate = hold;
    await tester.tap(find.byKey(const ValueKey('cycle-comparison-earlier')));
    await tester.pump();
    expect(find.text('56'), findsNothing);
    expect(find.textContaining('16. Sept. 2024'), findsOneWidget);
    hold.complete();
    await tester.pumpAndSettle();
    expect(find.text('Keine Nacht'), findsNWidgets(2));
  });

  testWidgets('stale reads and identity changes do not paint old cards', (
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
    expect(find.text('56'), findsNothing);

    final second = _GateRepo()..seedCycleComparisonFixture(includeHrv: false);
    final secondGate = Completer<void>();
    second.gate = secondGate;
    hostKey.currentState!.update(repository: second);
    await tester.pump();
    expect(find.text('56'), findsNothing);

    first.complete();
    await tester.pump();
    expect(find.text('56'), findsNothing);
    expect(find.text('Keine Nacht'), findsNothing);

    secondGate.complete();
    await tester.pumpAndSettle();
    expect(find.text('56'), findsOneWidget);
    expect(find.text('Keine Nacht'), findsOneWidget);
    expect(find.text('Nacht · Tag 22'), findsNothing);
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

  testWidgets('method info has Paper copy and source actions', (tester) async {
    await mount(tester);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Verglichen wird die letzte gespeicherte Nacht je Messwert. Die Differenz bezieht sich auf den Mittelwert der genannten Nächte.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        '21 Tage davor: mindestens zwei Nächte. Gleicher Zyklustag: mindestens drei frühere Zyklen im gewählten Zeitraum. Abstände über 60 Tage werden nicht zugeordnet.',
      ),
      findsOneWidget,
    );
    expect(find.text('Ruhepuls · Quellen'), findsOneWidget);
    expect(find.text('HRV · Quellen'), findsOneWidget);
    await expectGolden(tester, 'cycle-comparison-info.png');
  });

  testWidgets('source actions close method then open metric sheet', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ruhepuls · Quellen'));
    await tester.pumpAndSettle();
    expect(find.text('Ruhepuls · Quellen'), findsNothing);
    expect(find.text('HRV · Quellen'), findsNothing);
    expect(
      find.textContaining('15. Sept. 2026 · 56 bpm · Tag 23'),
      findsOneWidget,
    );
    expect(find.textContaining('Mittelwert 56,2 bpm'), findsOneWidget);
    expect(find.textContaining('z −0,10'), findsOneWidget);
    expect(
      find.textContaining('19. Juni: 50 bpm · Beginn 28. Mai'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Alle genannten Nächte: Vortag 16:00 bis zum genannten Datum 06:00 UTC',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Algorithmus $kAlgoVersion'), findsOneWidget);
    expect(find.textContaining('Schlaf automatisch'), findsOneWidget);
    expect(find.textContaining('Stufe HIGH'), findsOneWidget);
    expect(
      find.textContaining('Eingaben Puls (1 Hz), Schlaffenster'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Keine Aussage über Ursache oder Zyklusphase'),
      findsOneWidget,
    );
    expect(find.text('Eisprung'), findsNothing);
    await expectGolden(tester, 'cycle-comparison-rhr-sources.png');
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cycle-comparison')), findsOneWidget);

    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HRV · Quellen'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('14. Sept. 2026 · 51 ms · Tag 22'),
      findsOneWidget,
    );
    expect(find.textContaining('Mittelwert 49,7 ms'), findsOneWidget);
    expect(
      find.textContaining('Eingaben RR-Intervalle im Schlaffenster'),
      findsOneWidget,
    );
    await expectGolden(tester, 'cycle-comparison-hrv-sources.png');
  });

  testWidgets('long-period latest omits Tag in source', (tester) async {
    repo.clearCycleLogs();
    repo.seedCycleStart(
      const CycleStart(date: '2025-01-01', kind: kCycleStartKind),
    );
    await mount(tester);
    expect(find.textContaining('Nacht · Tag'), findsNothing);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ruhepuls · Quellen'));
    await tester.pumpAndSettle();
    expect(find.textContaining(' · Tag '), findsNothing);
    expect(find.textContaining('Abstand über 60 Tage'), findsWidgets);
    expect(find.textContaining('Algorithmus $kAlgoVersion'), findsWidgets);
  });

  testWidgets('absent sleep bounds are not invented or grouped', (
    tester,
  ) async {
    const latest = CycleComparisonNight(
      nightDay: '2026-09-15',
      assignment: CycleComparisonAssignment(
        startDay: '2026-08-24',
        cycleDay: 23,
      ),
      metric: CycleNightMetric(value: 56),
      algoVersion: kAlgoVersion,
    );
    const prior = CycleComparisonNight(
      nightDay: '2026-09-14',
      metric: CycleNightMetric(value: 54),
      algoVersion: kAlgoVersion,
    );
    const earlier = CycleComparisonNight(
      nightDay: '2026-09-13',
      metric: CycleNightMetric(value: 56),
      algoVersion: kAlgoVersion,
    );
    final body = comparisonSourceBody(
      const CycleMetricComparison(
        latestReason: CycleComparisonLatestReason.available,
        latest: latest,
        prior21: CycleComparisonPrior21(
          reason: CycleComparisonPrior21Reason.available,
          startDay: '2026-08-25',
          endDay: '2026-09-14',
          count: 2,
          contributors: [earlier, prior],
          mean: 55,
          delta: 1,
        ),
      ),
      'bpm',
      '2026-09-15',
    );
    expect(body.contains('Nacht:'), isFalse);
    expect(body.contains('Alle genannten Nächte'), isFalse);
    expect(body.contains('Vortag'), isFalse);
    expect(body.contains('16:00'), isFalse);
    expect(body.contains('06:00'), isFalse);
    expect(body.contains('15. Sept. 2026 · 56 bpm'), isTrue);

    repo.seedCycleNightSource(
      _night('2026-09-15', rhr: 56, hrv: null, omitSleepWindow: true),
    );
    await mount(tester);
    expect(find.text('15. Sept. 2026'), findsNothing);
    expect(find.text('Teilweise ausgewertet'), findsOneWidget);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Gewähltes Jahr und 21-Tage-Vergleiche: 1 Nacht mit nicht auswertbarem Ergebnis.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('unassigned latest is Nicht zugeordnet without Tag', (
    tester,
  ) async {
    repo.clearCycleNightSources();
    repo.seedCycleNightSource(_night('2026-05-20', rhr: 56, hrv: 51));
    repo.seedCycleNightSource(_night('2026-05-19', rhr: 54, hrv: 48));
    repo.seedCycleNightSource(_night('2026-05-18', rhr: 55, hrv: 49));
    await mount(tester);
    expect(find.text('Nicht zugeordnet'), findsNWidgets(2));
    expect(find.textContaining('Nacht · Tag'), findsNothing);
    expect(find.text('Nacht'), findsNWidgets(2));
    expect(find.text('56'), findsOneWidget);
    expect(find.text('51'), findsOneWidget);
    expect(find.text('Gegenüber dem Mittelwert'), findsNWidgets(2));
  });

  testWidgets('excluded night is disclosed in method info', (tester) async {
    repo.seedCycleNightSource(
      _night('2026-08-20', rhr: 50, hrv: 40, imported: true),
    );
    await mount(tester);
    expect(find.text('Teilweise ausgewertet'), findsOneWidget);
    expect(find.text('56'), findsOneWidget);
    expect(find.text('Nacht · Tag 23'), findsOneWidget);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Gewähltes Jahr und 21-Tage-Vergleiche: 1 Nacht mit nicht auswertbarem Ergebnis.',
      ),
      findsOneWidget,
    );
    expect(find.text('Ruhepuls · Quellen'), findsOneWidget);
    expect(find.text('HRV · Quellen'), findsOneWidget);
  });

  testWidgets('differing latest metadata is not dropped', (tester) async {
    repo.seedCycleNightSource(
      _night(
        '2026-09-15',
        rhr: 56,
        hrv: null,
        sleepSource: 'manual',
        rhrNote: 'korrektur',
        onsetMs: _utcMs('2026-09-15', 1),
        offsetMs: _utcMs('2026-09-15', 7),
      ),
    );
    await mount(tester);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ruhepuls · Quellen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Alle genannten Nächte'), findsNothing);
    expect(
      find.textContaining('15. Sept. 2026 · 56 bpm · Tag 23'),
      findsOneWidget,
    );
    expect(find.textContaining('Schlaf manuell'), findsOneWidget);
    expect(find.textContaining('Hinweis: korrektur'), findsOneWidget);
    expect(find.textContaining('1:00'), findsOneWidget);
    expect(find.textContaining('7:00'), findsOneWidget);
    expect(find.textContaining('Algorithmus $kAlgoVersion'), findsWidgets);
  });

  testWidgets('same-day source windows stay explicit', (tester) async {
    for (final day in [
      '2026-09-15',
      '2026-09-14',
      '2026-09-10',
      '2026-08-22',
      '2026-07-21',
      '2026-06-19',
    ]) {
      repo.seedCycleNightSource(
        _night(day, onsetMs: _utcMs(day, 2), offsetMs: _utcMs(day, 6)),
      );
    }
    await mount(tester);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ruhepuls · Quellen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Vortag'), findsNothing);
    expect(find.textContaining('Alle genannten Nächte'), findsNothing);
    expect(find.textContaining('2:00'), findsWidgets);
    expect(find.textContaining('6:00'), findsWidgets);
    expect(find.textContaining('Algorithmus $kAlgoVersion'), findsWidgets);
  });

  testWidgets('mixed metadata prints its own source facts', (tester) async {
    repo.seedCycleNightSource(
      _night(
        '2026-09-10',
        rhr: 57,
        hrv: 50,
        sleepSource: 'manual',
        rhrNote: 'korrektur',
        onsetMs: _utcMs('2026-09-10', 2),
        offsetMs: _utcMs('2026-09-10', 6),
      ),
    );
    await mount(tester);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ruhepuls · Quellen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Alle genannten Nächte'), findsNothing);
    expect(find.textContaining('Schlaf manuell'), findsOneWidget);
    expect(find.textContaining('Hinweis: korrektur'), findsOneWidget);
    expect(find.textContaining('2:00'), findsOneWidget);
    expect(find.textContaining('Schlaf automatisch'), findsWidgets);
  });

  testWidgets('zero-sd mean stays and z is unknown', (tester) async {
    repo.clearCycleNightSources();
    repo.seedCycleNightSource(_night('2026-09-15', rhr: 56, hrv: null));
    repo.seedCycleNightSource(_night('2026-09-14', rhr: 56, hrv: null));
    repo.seedCycleNightSource(_night('2026-09-13', rhr: 56, hrv: null));
    await mount(tester);
    expect(find.text('56'), findsOneWidget);
    expect(find.text('0,0 bpm'), findsOneWidget);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ruhepuls · Quellen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mittelwert 56,0 bpm'), findsOneWidget);
    expect(find.textContaining('z —'), findsOneWidget);
  });

  testWidgets('method info omits source actions when no source exists', (
    tester,
  ) async {
    repo.clearCycleNightSources();
    await mount(tester);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(find.text('Ruhepuls · Quellen'), findsNothing);
    expect(find.text('HRV · Quellen'), findsNothing);
    expect(find.text('Schließen'), findsOneWidget);
  });

  testWidgets('2x stacks header date, caption and delta', (tester) async {
    await mount(tester, scale: 2, width: 375, height: 812);
    expect(find.text('56'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final list = find.descendant(
      of: find.byKey(const ValueKey('cycle-comparison')),
      matching: find.byType(Scrollable),
    );
    await tester.drag(list.first, const Offset(0, 400));
    await tester.pumpAndSettle();
    await expectGolden(tester, 'cycle-comparison-large-top.png');
    await tester.scrollUntilVisible(
      find.text('Synthetische Daten'),
      80,
      scrollable: list.first,
    );
    await expectGolden(tester, 'cycle-comparison-large-bottom.png');
  });

  testWidgets('year-1 end does not crash the window', (tester) async {
    await mount(tester, day: '0001-01-15');
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('cycle-comparison')), findsOneWidget);
    expect(find.byType(OBWindowPager), findsNothing);
    expect(find.text('Daten nicht geladen'), findsOneWidget);
  });

  testWidgets('error after page change does not restore old metrics', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('56'), findsOneWidget);
    repo.failCycleComparisonRead = true;
    await tester.tap(find.byKey(const ValueKey('cycle-comparison-earlier')));
    await tester.pumpAndSettle();
    expect(find.textContaining('16. Sept. 2024'), findsOneWidget);
    expect(find.text('Daten nicht geladen'), findsOneWidget);
    expect(find.text('56'), findsNothing);
    expect(find.text('Nacht · Tag 23'), findsNothing);
  });
}
