import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/openband/alp_tokens.dart';
import 'package:openstrap_edge/openband/cycle.dart';
import 'package:openstrap_edge/openband/cycle_observations.dart';
import 'package:openstrap_edge/openband/cycle_observations_data.dart';
import 'package:openstrap_edge/openband/domain.dart';
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

final _paperNow = DateTime(2026, 9, 15, 9, 41);

class _GateRepo extends SyntheticOpenBandRepository {
  _GateRepo() : super.fromMaps(_daySummary(), _sleepDetail());

  Completer<void>? gate;
  int cycleReads = 0;

  @override
  Future<CycleSnapshot> readCycle(String day, {DateTime? now}) async {
    cycleReads++;
    final snap = await super.readCycle(day, now: now);
    final hold = gate;
    if (hold != null) await hold.future;
    return snap;
  }
}

class _Host extends StatefulWidget {
  const _Host({
    super.key,
    required this.initialRepo,
    required this.initialDay,
  });
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
  Widget build(BuildContext context) => OpenBandCycleObservations(
    repository: repo,
    day: day,
    now: () => _paperNow,
    synthetic: true,
  );
}

void _seedPaperObservations(
  SyntheticOpenBandRepository repo, {
  bool week5 = false,
}) {
  const rows = <(String, List<String>)>[
    ('2026-06-01', ['cramps', 'fatigue']),
    ('2026-06-03', ['cramps']),
    ('2026-06-29', ['cramps', 'headache']),
    ('2026-07-02', ['fatigue']),
    ('2026-07-31', ['cramps']),
    ('2026-08-02', ['fatigue']),
    ('2026-08-24', ['headache']),
    ('2026-08-25', ['bloating']),
  ];
  for (final row in rows) {
    repo.seedCycleObservation(CycleObservation(date: row.$1, tags: row.$2));
  }
  if (week5) {
    repo.seedCycleObservation(
      const CycleObservation(date: '2026-07-28', tags: ['nausea']),
    );
    repo.seedCycleObservation(
      const CycleObservation(date: '2026-07-29', tags: [], note: 'felt off'),
    );
  }
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
    _seedPaperObservations(repo);
  });

  Finder capture() => find.byKey(const ValueKey('capture'));

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
            OpenBandCycleObservations(
              repository: repository ?? repo,
              day: day,
              now: () => _paperNow,
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

  testWidgets('root Beobachtungen sits after Messwerte and before Verlauf', (
    tester,
  ) async {
    await mount(
      tester,
      home: OpenBandCycle(
        repository: repo,
        day: '2026-09-15',
        now: () => _paperNow,
        synthetic: true,
      ),
    );
    expect(find.text('Messwerte'), findsOneWidget);
    expect(find.text('Beobachtungen'), findsOneWidget);
    expect(find.text('Verlauf'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Messwerte')).dy,
      lessThan(tester.getTopLeft(find.text('Beobachtungen')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Beobachtungen')).dy,
      lessThan(tester.getTopLeft(find.text('Verlauf')).dy),
    );
    await tester.tap(find.text('Beobachtungen'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cycle-observations')), findsOneWidget);
    expect(find.text('8 Tage mit Beobachtungen'), findsOneWidget);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cycle-overview')), findsOneWidget);
    expect(find.text('Beobachtung festhalten'), findsOneWidget);
  });

  testWidgets('Beobachtungen stays reachable without a start', (tester) async {
    repo.clearCycleLogs();
    await mount(
      tester,
      home: OpenBandCycle(
        repository: repo,
        day: '2026-09-15',
        now: () => _paperNow,
        synthetic: true,
      ),
    );
    expect(find.text('Beobachtungen'), findsOneWidget);
    await tester.tap(find.text('Beobachtungen'));
    await tester.pumpAndSettle();
    expect(find.text('Mindestens 3 Zyklusbeginne nötig'), findsOneWidget);
    expect(find.text('Zum Zyklus'), findsOneWidget);
  });

  testWidgets('paper week 1 counts and dates', (tester) async {
    await mount(tester);
    expect(find.text('Tag 1–7'), findsOneWidget);
    expect(find.text('8 Tage mit Beobachtungen'), findsOneWidget);
    expect(find.text('1. Juni–15. Sept. · 4 Zyklen'), findsOneWidget);
    expect(find.text('Krämpfe'), findsOneWidget);
    expect(find.text('4 von 8'), findsOneWidget);
    expect(find.text('Müdigkeit'), findsOneWidget);
    expect(find.text('3 von 8'), findsOneWidget);
    expect(find.text('Kopfschmerzen'), findsOneWidget);
    expect(find.text('2 von 8'), findsOneWidget);
    expect(find.text('Blähungen'), findsOneWidget);
    expect(find.text('1 von 8'), findsOneWidget);
    expect(find.text('Akne'), findsNothing);
    expect(find.text('Synthetische Daten'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle-observations.png'),
    );
    await mount(tester, brightness: Brightness.dark);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle-observations-dark.png'),
    );
  });

  testWidgets('picker lists 7-day groups and week 5 is separate', (
    tester,
  ) async {
    _seedPaperObservations(repo, week5: true);
    await mount(tester);
    final summary = buildCycleObservationsSummary(
      await repo.readCycle('2026-09-15', now: _paperNow),
    );
    expect(summary.weeks, hasLength(5));
    expect(summary.weeks[4].fromCycleDay, 29);
    expect(summary.weeks[4].toCycleDay, 35);
    expect(summary.weeks[4].taggedDays, 1);
    await tester.tap(find.byKey(const ValueKey('cycle-observations-picker')));
    await tester.pumpAndSettle();
    expect(find.text('Tag 1–7'), findsWidgets);
    expect(find.text('Tag 8–14'), findsOneWidget);
    expect(find.text('Tag 15–21'), findsOneWidget);
    expect(find.text('Tag 22–28'), findsOneWidget);
    expect(find.text('Tag 29–35'), findsOneWidget);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle-observations-picker.png'),
    );
    await tester.tap(find.text('Tag 29–35'));
    await tester.pumpAndSettle();
    expect(find.text('Tag 29–35'), findsOneWidget);
    expect(find.text('1 Tag mit Beobachtungen'), findsOneWidget);
    expect(find.text('Übelkeit'), findsOneWidget);
    expect(find.text('1 von 1'), findsOneWidget);
    expect(find.text('Krämpfe'), findsNothing);
    expect(find.text('Keine Einträge für diese Zyklustage'), findsNothing);
  });

  testWidgets('empty week is selectable and is not no-symptoms', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('cycle-observations-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tag 8–14'));
    await tester.pumpAndSettle();
    expect(find.text('Tag 8–14'), findsOneWidget);
    expect(find.text('Keine Einträge für diese Zyklustage'), findsOneWidget);
    expect(find.text('keine Symptome'), findsNothing);
    expect(find.text('Krämpfe'), findsNothing);
    expect(find.text('8 Tage mit Beobachtungen'), findsNothing);
    expect(tester.takeException(), isNull);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle-observations-empty.png'),
    );
    await mount(tester, brightness: Brightness.dark);
    await tester.tap(find.byKey(const ValueKey('cycle-observations-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tag 8–14'));
    await tester.pumpAndSettle();
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle-observations-empty-dark.png'),
    );
  });

  testWidgets('unknown tag stays visible and long labels wrap', (tester) async {
    repo.seedCycleObservation(
      const CycleObservation(
        date: '2026-06-04',
        tags: ['mystery-spot'],
      ),
    );
    await mount(tester);
    expect(find.text('mystery-spot'), findsOneWidget);
    expect(find.text('9 Tage mit Beobachtungen'), findsOneWidget);

    repo.seedCycleObservation(
      const CycleObservation(
        date: '2026-06-05',
        tags: [
          'sehr-langes-unbekanntes-symptom-das-in-der-zeile-bricht',
        ],
      ),
    );
    await mount(tester, scale: 2, width: 375, height: 812);
    expect(
      find.text('sehr-langes-unbekanntes-symptom-das-in-der-zeile-bricht'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(find.text('Synthetische Daten'), 240);
    expect(tester.takeException(), isNull);
  });

  testWidgets('partial notice keeps known counts', (tester) async {
    repo.seedUnreadableCycleObservation({
      'date': '2026-09-10',
      'symptoms_json': '{',
    });
    await mount(tester);
    expect(find.text('Einträge teilweise lesbar'), findsOneWidget);
    expect(find.text('8 Tage mit Beobachtungen'), findsOneWidget);
    expect(find.text('4 von 8'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle-observations-partial.png'),
    );
    await mount(tester, brightness: Brightness.dark);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle-observations-partial-dark.png'),
    );
  });

  testWidgets('read exception is retryable', (tester) async {
    repo.failCycleRead = true;
    await mount(tester);
    expect(find.text('Daten nicht geladen'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(find.text('Krämpfe'), findsNothing);
    expect(find.text('Mindestens 3 Zyklusbeginne nötig'), findsNothing);
    final color = tester.widget<Text>(find.text('Daten nicht geladen')).style?.color;
    expect(color, AlpColor.danger);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle-observations-error.png'),
    );
    repo.failCycleRead = false;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(find.text('8 Tage mit Beobachtungen'), findsOneWidget);
    expect(find.text('Daten nicht geladen'), findsNothing);
  });

  testWidgets('insufficient, disabled settings return, and unreadable', (
    tester,
  ) async {
    repo.clearCycleLogs();
    repo.seedCycleStart(
      const CycleStart(date: '2026-08-24', kind: kCycleStartKind),
    );
    repo.seedCycleStart(
      const CycleStart(date: '2026-07-31', kind: kCycleStartKind),
    );
    await mount(tester);
    expect(find.text('Mindestens 3 Zyklusbeginne nötig'), findsOneWidget);
    expect(find.text('Zum Zyklus'), findsOneWidget);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle-observations-insufficient.png'),
    );

    repo = _GateRepo();
    _seedPaperObservations(repo);
    repo.cycleSettings = const CycleSettings(
      enabled: false,
      estimatesEnabled: false,
      lengthReviewEnabled: false,
    );
    await mount(tester);
    expect(find.text('Zyklus deaktiviert'), findsOneWidget);
    expect(find.text('Einstellungen'), findsOneWidget);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle-observations-disabled.png'),
    );
    await tester.tap(find.text('Einstellungen'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cycle-settings')), findsOneWidget);
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
    expect(find.text('8 Tage mit Beobachtungen'), findsOneWidget);

    repo.clearCycleLogs();
    repo.seedUnreadableCycleStart({'date': '2026-08-24', 'kind': 1});
    await mount(tester);
    expect(find.text('Zyklusbeginn nicht lesbar'), findsOneWidget);
    final unreadColor = tester
        .widget<Text>(find.text('Zyklusbeginn nicht lesbar'))
        .style
        ?.color;
    expect(unreadColor, AlpColor.danger);
    expect(find.text('Zum Zyklus'), findsOneWidget);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle-observations-unreadable.png'),
    );
  });

  testWidgets('stale loads do not paint old counts', (tester) async {
    final first = Completer<void>();
    repo.gate = first;
    final hostKey = GlobalKey<_HostState>();
    await mount(
      tester,
      settle: false,
      home: _Host(
        key: hostKey,
        initialRepo: repo,
        initialDay: '2026-09-15',
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('4 von 8'), findsNothing);

    final second = _GateRepo();
    second.clearCycleLogs();
    second.seedCycleStart(
      const CycleStart(date: '2026-06-01', kind: kCycleStartKind),
    );
    second.seedCycleStart(
      const CycleStart(date: '2026-06-29', kind: kCycleStartKind),
    );
    second.seedCycleStart(
      const CycleStart(date: '2026-07-31', kind: kCycleStartKind),
    );
    second.seedCycleObservation(
      const CycleObservation(date: '2026-06-01', tags: ['acne']),
    );
    final secondGate = Completer<void>();
    second.gate = secondGate;
    hostKey.currentState!.update(repository: second);
    await tester.pump();
    expect(find.text('4 von 8'), findsNothing);
    expect(find.text('Akne'), findsNothing);

    first.complete();
    await tester.pump();
    expect(find.text('4 von 8'), findsNothing);
    expect(find.text('Akne'), findsNothing);

    secondGate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Akne'), findsOneWidget);
    expect(find.text('1 von 1'), findsOneWidget);
    expect(find.text('4 von 8'), findsNothing);
    expect(find.text('Krämpfe'), findsNothing);
  });

  testWidgets('picker identity is dropped after repository change', (
    tester,
  ) async {
    _seedPaperObservations(repo, week5: true);
    final hostKey = GlobalKey<_HostState>();
    await mount(
      tester,
      home: _Host(
        key: hostKey,
        initialRepo: repo,
        initialDay: '2026-09-15',
      ),
    );
    await tester.tap(find.byKey(const ValueKey('cycle-observations-picker')));
    await tester.pumpAndSettle();
    expect(find.text('Tag 29–35'), findsOneWidget);

    final other = _GateRepo();
    other.clearCycleLogs();
    other.seedCycleStart(
      const CycleStart(date: '2026-06-01', kind: kCycleStartKind),
    );
    other.seedCycleStart(
      const CycleStart(date: '2026-06-08', kind: kCycleStartKind),
    );
    other.seedCycleStart(
      const CycleStart(date: '2026-06-15', kind: kCycleStartKind),
    );
    other.seedCycleObservation(
      const CycleObservation(date: '2026-06-01', tags: ['fatigue']),
    );
    hostKey.currentState!.update(repository: other);
    await tester.pump();
    await tester.tap(find.text('Tag 29–35'));
    await tester.pumpAndSettle();
    expect(find.text('Übelkeit'), findsNothing);
    expect(find.text('Müdigkeit'), findsOneWidget);
    expect(find.text('Tag 1–7'), findsOneWidget);
    expect(find.text('Tag 29–35'), findsNothing);
  });

  testWidgets('reload that shortens weeks selects the first group', (
    tester,
  ) async {
    _seedPaperObservations(repo, week5: true);
    final hostKey = GlobalKey<_HostState>();
    await mount(
      tester,
      home: _Host(
        key: hostKey,
        initialRepo: repo,
        initialDay: '2026-09-15',
      ),
    );
    await tester.tap(find.byKey(const ValueKey('cycle-observations-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tag 29–35'));
    await tester.pumpAndSettle();
    expect(find.text('Übelkeit'), findsOneWidget);

    final short = _GateRepo();
    short.clearCycleLogs();
    short.seedCycleStart(
      const CycleStart(date: '2026-06-01', kind: kCycleStartKind),
    );
    short.seedCycleStart(
      const CycleStart(date: '2026-06-08', kind: kCycleStartKind),
    );
    short.seedCycleStart(
      const CycleStart(date: '2026-06-15', kind: kCycleStartKind),
    );
    short.seedCycleObservation(
      const CycleObservation(date: '2026-06-01', tags: ['cramps']),
    );
    hostKey.currentState!.update(repository: short);
    await tester.pumpAndSettle();
    expect(find.text('Übelkeit'), findsNothing);
    expect(find.text('Tag 29–35'), findsNothing);
    expect(find.text('Tag 1–7'), findsOneWidget);
    expect(find.text('Krämpfe'), findsOneWidget);
    expect(find.text('1 Tag mit Beobachtungen'), findsOneWidget);
  });

  testWidgets('as-of year and singular title', (tester) async {
    repo.clearCycleLogs();
    repo.seedCycleStart(
      const CycleStart(date: '2025-12-01', kind: kCycleStartKind),
    );
    repo.seedCycleStart(
      const CycleStart(date: '2026-01-05', kind: kCycleStartKind),
    );
    repo.seedCycleStart(
      const CycleStart(date: '2026-02-02', kind: kCycleStartKind),
    );
    repo.seedCycleObservation(
      const CycleObservation(date: '2025-12-02', tags: ['cramps']),
    );
    await mount(tester, day: '2026-02-10');
    expect(find.text('1 Tag mit Beobachtungen'), findsOneWidget);
    expect(find.textContaining('2025'), findsOneWidget);
    expect(find.textContaining('2026'), findsOneWidget);
    expect(find.text('1 von 1'), findsOneWidget);
  });

  testWidgets('historical 2025 range shows year when now is 2026', (
    tester,
  ) async {
    repo.clearCycleLogs();
    repo.seedCycleStart(
      const CycleStart(date: '2025-06-01', kind: kCycleStartKind),
    );
    repo.seedCycleStart(
      const CycleStart(date: '2025-06-29', kind: kCycleStartKind),
    );
    repo.seedCycleStart(
      const CycleStart(date: '2025-07-31', kind: kCycleStartKind),
    );
    repo.seedCycleObservation(
      const CycleObservation(date: '2025-06-01', tags: ['cramps']),
    );
    await mount(tester, day: '2025-09-15');
    expect(find.text('1 Tag mit Beobachtungen'), findsOneWidget);
    expect(find.text('1. Juni 2025–15. Sept. 2025 · 3 Zyklen'), findsOneWidget);
    expect(find.text('1. Juni–15. Sept. · 3 Zyklen'), findsNothing);
  });

  testWidgets('info uses the shared sheet', (tester) async {
    await mount(tester);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Gezählt werden nur Tage mit mindestens einer gespeicherten Beobachtung. Notizen allein und fehlende Einträge zählen nicht als symptomfreie Tage.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Die Übersicht beginnt mit drei eingetragenen Zyklusbeginnen. Zyklustage zählen ab dem jeweils letzten eingetragenen Beginn. Der laufende Zyklus ist enthalten.',
      ),
      findsOneWidget,
    );
    expect(find.text('Schließen'), findsOneWidget);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle-observations-info.png'),
    );
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('journal-info-body')), findsNothing);
  });

  testWidgets('375 2x and 320w scroll without overflow', (tester) async {
    await mount(tester, scale: 2, width: 375, height: 812);
    expect(find.text('8 Tage mit Beobachtungen'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle-observations-large.png'),
    );
    await tester.tap(find.byKey(const ValueKey('cycle-observations-picker')));
    await tester.pumpAndSettle();
    final week5 = find.text('Tag 29–35');
    if (week5.hitTestable().evaluate().isEmpty) {
      await tester.scrollUntilVisible(week5, 80);
    }
    expect(week5, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Tag 1–7').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(find.text('Schließen').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Synthetische Daten'), 240);
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
      matchesGoldenFile('openband_goldens/cycle-observations-large-dark.png'),
    );

    await mount(tester, width: 320, height: 568);
    expect(find.text('8 Tage mit Beobachtungen'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Synthetische Daten'), 200);
    expect(tester.takeException(), isNull);
  });

  testWidgets('count rows are not buttons', (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await mount(tester);
      expect(
        find.bySemanticsLabel('Krämpfe, 4 Tage von 8 Tagen'),
        findsOneWidget,
      );
      expect(find.text('Krämpfe'), findsOneWidget);
      expect(find.text('4 von 8'), findsOneWidget);
      expect(
        tester.getSemantics(find.text('Krämpfe')).getSemanticsData().hasAction(
          SemanticsAction.tap,
        ),
        isFalse,
      );
    } finally {
      handle.dispose();
    }
  });
}
