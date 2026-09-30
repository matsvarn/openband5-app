import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/openband/alp_tokens.dart';
import 'package:openstrap_edge/openband/cycle.dart';
import 'package:openstrap_edge/openband/cycle_gaps.dart';
import 'package:openstrap_edge/openband/cycle_gaps_data.dart';
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

final _paperNow = DateTime(2026, 9, 15, 9, 41);

const _paperStarts = [
  '2025-09-14',
  '2025-10-12',
  '2025-11-11',
  '2025-12-08',
  '2026-01-06',
  '2026-02-03',
  '2026-03-06',
  '2026-04-01',
  '2026-05-01',
  '2026-05-29',
  '2026-06-30',
  '2026-07-27',
  '2026-08-24',
];

const _extraStarts = [
  '2024-09-17',
  '2024-10-15',
  '2024-11-12',
  '2024-12-10',
  '2025-01-07',
  '2025-02-04',
  '2025-03-04',
  '2025-04-01',
  '2025-04-29',
  '2025-05-27',
  '2025-06-24',
  '2025-07-22',
  '2025-08-19',
];

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
  Widget build(BuildContext context) => OpenBandCycleGaps(
    repository: repo,
    day: day,
    now: () => _paperNow,
    synthetic: true,
  );
}

void _seedPaperGaps(
  SyntheticOpenBandRepository repo, {
  bool earlier = false,
  bool extra25 = false,
  bool display = true,
}) {
  repo.clearCycleLogs();
  if (extra25) {
    for (final date in _extraStarts) {
      repo.seedCycleStart(CycleStart(date: date, kind: kCycleStartKind));
    }
  } else if (earlier) {
    repo.seedCycleStart(
      const CycleStart(date: '2025-08-17', kind: kCycleStartKind),
    );
  }
  for (final date in _paperStarts) {
    repo.seedCycleStart(CycleStart(date: date, kind: kCycleStartKind));
  }
  repo.cycleSettings = CycleSettings(
    enabled: true,
    estimatesEnabled: true,
    lengthReviewEnabled: display,
  );
}

Finder _toggle(String label) => find.descendant(
  of: find.widgetWithText(OBSettingsToggleRow, label),
  matching: find.byType(CupertinoSwitch),
);

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
    _seedPaperGaps(repo);
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
            OpenBandCycleGaps(
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

  testWidgets('root Abstände sits after Beobachtungen and before Verlauf', (
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
    expect(find.text('Beobachtungen'), findsOneWidget);
    expect(find.text('Abstände'), findsOneWidget);
    expect(find.text('Verlauf'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Beobachtungen')).dy,
      lessThan(tester.getTopLeft(find.text('Abstände')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Abstände')).dy,
      lessThan(tester.getTopLeft(find.text('Verlauf')).dy),
    );
    await tester.tap(find.text('Abstände'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cycle-gaps')), findsOneWidget);
    expect(find.text('12 Abstände'), findsOneWidget);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cycle-overview')), findsOneWidget);
    expect(find.text('Beobachtung festhalten'), findsOneWidget);
  });

  testWidgets('paper latest 12 gaps and no open bar', (tester) async {
    await mount(tester);
    final summary = buildCycleGapsSummary(
      await repo.readCycle('2026-09-15', now: _paperNow),
    );
    expect(summary.reason, CycleGapsReason.available);
    expect(summary.gaps.map((g) => g.days), [
      28,
      30,
      27,
      29,
      28,
      31,
      26,
      30,
      28,
      32,
      27,
      28,
    ]);
    expect(find.text('Sept. 2025–Aug. 2026'), findsOneWidget);
    expect(find.text('12 Abstände'), findsOneWidget);
    expect(find.text('28'), findsWidgets);
    expect(find.text('27. Juli–24. Aug.'), findsOneWidget);
    expect(find.text('12. Okt. 2025'), findsOneWidget);
    expect(find.text('24. Aug. 2026'), findsOneWidget);
    expect(find.text('Zwischen Beginnen'), findsOneWidget);
    expect(find.textContaining('15. Sept.'), findsNothing);
    expect(find.text('Synthetische Daten'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle_gaps.png'),
    );
    await mount(tester, brightness: Brightness.dark);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle_gaps-dark.png'),
    );
  });

  testWidgets('selected actual gap via tap, drag, and semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      await mount(tester);
      final plot = find.byKey(const ValueKey('cycle-gaps-plot'));
      expect(plot, findsOneWidget);
      var node = tester.getSemantics(plot);
      expect(node.value, contains('27. Juli–24. Aug.'));
      expect(node.value, contains('28'));
      expect(node.getSemanticsData().hasAction(SemanticsAction.decrease), isTrue);
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.increase),
        isFalse,
      );

      final box = tester.getRect(plot);
      final plotW = box.width - 28 - 4;
      final step = plotW / 12;
      await tester.tapAt(Offset(box.left + 28 + 9.5 * step, box.center.dy));
      await tester.pump();
      expect(find.text('32'), findsOneWidget);
      expect(find.text('29. Mai–30. Juni'), findsOneWidget);
      expect(find.text('27. Juli–24. Aug.'), findsNothing);
      node = tester.getSemantics(plot);
      expect(node.value, contains('29. Mai–30. Juni'));
      expect(node.value, contains('32'));
      await expectLater(
        capture(),
        matchesGoldenFile('openband_goldens/cycle_gaps-selected.png'),
      );

      await tester.dragFrom(
        Offset(box.left + 28 + 9.5 * step, box.center.dy),
        Offset(step, 0),
      );
      await tester.pump();
      expect(find.text('27'), findsOneWidget);
      expect(find.text('30. Juni–27. Juli'), findsOneWidget);

      await tester.tapAt(Offset(box.left + 28 + 11.5 * step, box.center.dy));
      await tester.pump();
      expect(find.text('27. Juli–24. Aug.'), findsOneWidget);
      final owner = tester.getSemantics(plot).owner!;
      owner.performAction(
        tester.getSemantics(plot).id,
        SemanticsAction.decrease,
      );
      await tester.pump();
      expect(find.text('30. Juni–27. Juli'), findsOneWidget);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('picker older partial groups from the end', (tester) async {
    _seedPaperGaps(repo, earlier: true);
    await mount(tester);
    final summary = buildCycleGapsSummary(
      await repo.readCycle('2026-09-15', now: _paperNow),
    );
    expect(summary.gaps, hasLength(13));
    expect(summary.gaps.first.days, 28);
    expect(summary.gaps.first.previousStart, '2025-08-17');
    expect(summary.gaps.first.nextStart, '2025-09-14');
    final groups = partitionCycleGaps(summary.gaps);
    expect(groups, hasLength(2));
    expect(groups.first, hasLength(12));
    expect(groups.last, hasLength(1));
    expect(find.text('12 von 13 Abständen'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cycle-gaps-picker')));
    await tester.pumpAndSettle();
    expect(find.text('Sept. 2025–Aug. 2026'), findsWidgets);
    expect(find.text('Aug.–Sept. 2025'), findsOneWidget);
    final rows = tester
        .widgetList<OBSettingsChoiceRow>(find.byType(OBSettingsChoiceRow))
        .toList();
    expect(rows, hasLength(2));
    expect(rows.first.label, 'Sept. 2025–Aug. 2026');
    expect(rows.first.selected, isTrue);
    expect(rows.last.label, 'Aug.–Sept. 2025');
    expect(rows.last.selected, isFalse);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle_gaps-picker.png'),
    );
    await tester.tap(find.text('Aug.–Sept. 2025'));
    await tester.pumpAndSettle();
    expect(find.text('Aug.–Sept. 2025'), findsOneWidget);
    expect(find.text('1 von 13 Abständen'), findsOneWidget);
    expect(find.text('17. Aug.–14. Sept.'), findsOneWidget);
    expect(find.text('14. Sept. 2025'), findsOneWidget);
    expect(find.text('12. Okt. 2025'), findsNothing);
    expect(find.text('24. Aug. 2026'), findsNothing);
    expect(tester.takeException(), isNull);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle_gaps-earlier.png'),
    );
    await mount(tester, brightness: Brightness.dark);
    await tester.tap(find.byKey(const ValueKey('cycle-gaps-picker')));
    await tester.pumpAndSettle();
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle_gaps-picker-dark.png'),
    );
    await tester.tap(find.text('Aug.–Sept. 2025'));
    await tester.pumpAndSettle();
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle_gaps-earlier-dark.png'),
    );
  });

  testWidgets('25-gap partition is newest 12, preceding 12, first 1', (
    tester,
  ) async {
    _seedPaperGaps(repo, extra25: true);
    final summary = buildCycleGapsSummary(
      await repo.readCycle('2026-09-15', now: _paperNow),
    );
    expect(summary.gaps, hasLength(25));
    final groups = partitionCycleGaps(summary.gaps);
    expect(groups.map((g) => g.length), [12, 12, 1]);
    expect(groups[0].first.previousStart, '2025-09-14');
    expect(groups[0].last.nextStart, '2026-08-24');
    expect(groups[1].last.nextStart, '2025-09-14');
    expect(groups[2].single.previousStart, '2024-09-17');
    expect(groups[2].single.nextStart, '2024-10-15');
    await mount(tester);
    expect(find.text('12 von 25 Abständen'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cycle-gaps-picker')));
    await tester.pumpAndSettle();
    expect(find.text('Sept. 2025–Aug. 2026'), findsWidgets);
    expect(find.text('Okt. 2024–Sept. 2025'), findsOneWidget);
    expect(find.text('Sept.–Okt. 2024'), findsOneWidget);
  });

  testWidgets('same-month 25 one-day gaps keep unique picker labels and Tag',
      (tester) async {
    repo.clearCycleLogs();
    repo.cycleSettings = const CycleSettings(
      enabled: true,
      estimatesEnabled: true,
      lengthReviewEnabled: true,
    );
    for (var day = 1; day <= 26; day++) {
      final date =
          '2026-09-${day.toString().padLeft(2, '0')}';
      repo.seedCycleStart(CycleStart(date: date, kind: kCycleStartKind));
    }
    final summary = buildCycleGapsSummary(
      await repo.readCycle('2026-09-26', now: DateTime(2026, 9, 26, 9, 41)),
    );
    expect(summary.gaps, hasLength(25));
    expect(summary.gaps.every((gap) => gap.days == 1), isTrue);
    final groups = partitionCycleGaps(summary.gaps);
    expect(groups.map((g) => g.length), [12, 12, 1]);
    expect(cycleGapsGroupLabel(groups[0]), '14.–26. Sept. 2026');
    expect(cycleGapsGroupLabel(groups[1]), '2.–14. Sept. 2026');
    expect(cycleGapsGroupLabel(groups[2]), '1.–2. Sept. 2026');
    expect(
      {for (final group in groups) cycleGapsGroupLabel(group)},
      hasLength(3),
    );
    await mount(tester, day: '2026-09-26');
    expect(find.text('12 von 25 Abständen'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    expect(find.text('Tag'), findsOneWidget);
    expect(find.text('Tage'), findsNothing);
    expect(find.text('25. Sept.–26. Sept.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cycle-gaps-picker')));
    await tester.pumpAndSettle();
    expect(find.text('14.–26. Sept. 2026'), findsWidgets);
    expect(find.text('2.–14. Sept. 2026'), findsOneWidget);
    expect(find.text('1.–2. Sept. 2026'), findsOneWidget);
    await tester.tap(find.text('1.–2. Sept. 2026'));
    await tester.pumpAndSettle();
    expect(find.text('1 von 25 Abständen'), findsOneWidget);
    expect(find.text('1.–2. Sept. 2026'), findsOneWidget);
    expect(find.text('Tag'), findsOneWidget);
    expect(find.text('Tage'), findsNothing);
    expect(find.text('1. Sept.–2. Sept.'), findsOneWidget);
  });

  testWidgets('display off, tracking disabled, settings return', (
    tester,
  ) async {
    _seedPaperGaps(repo, display: false);
    await mount(tester);
    expect(find.text('Abstände ausgeblendet'), findsOneWidget);
    expect(find.text('Einstellungen'), findsOneWidget);
    expect(find.text('12 Abstände'), findsNothing);
    expect(find.text('0 Abstände'), findsNothing);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle_gaps-off.png'),
    );

    repo.cycleSettings = const CycleSettings(
      enabled: false,
      estimatesEnabled: true,
      lengthReviewEnabled: true,
    );
    await mount(tester);
    expect(find.text('Zyklus deaktiviert'), findsOneWidget);
    expect(find.text('Einstellungen'), findsOneWidget);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle_gaps-disabled.png'),
    );
    await tester.tap(find.text('Einstellungen'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cycle-settings')), findsOneWidget);
    expect(find.text('Abstände anzeigen'), findsOneWidget);
    repo.cycleSettings = const CycleSettings(
      enabled: true,
      estimatesEnabled: true,
      lengthReviewEnabled: true,
    );
    final hold = Completer<void>();
    repo.gate = hold;
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pump();
    expect(find.text('Zyklus deaktiviert'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    hold.complete();
    await tester.pumpAndSettle();
    expect(find.text('12 Abstände'), findsOneWidget);
  });

  testWidgets('on/off toggle and committed refresh failure preserve retry', (
    tester,
  ) async {
    await mount(
      tester,
      home: OpenBandCycleSettings(
        repository: repo,
        now: () => _paperNow,
        synthetic: true,
      ),
    );
    expect(
      tester.widget<CupertinoSwitch>(_toggle('Abstände anzeigen')).value,
      isTrue,
    );
    await tester.tap(_toggle('Abstände anzeigen'));
    await tester.pumpAndSettle();
    expect(repo.cycleSettings.lengthReviewEnabled, isFalse);
    expect(
      tester.widget<CupertinoSwitch>(_toggle('Abstände anzeigen')).value,
      isFalse,
    );
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle_gaps-settings-off.png'),
    );

    repo.failCycleContextRefresh = true;
    await tester.tap(_toggle('Abstände anzeigen'));
    await tester.pumpAndSettle();
    expect(repo.cycleSettings.lengthReviewEnabled, isTrue);
    expect(
      tester.widget<CupertinoSwitch>(_toggle('Abstände anzeigen')).value,
      isTrue,
    );
    expect(find.text('Gespeichert · Aktualisieren fehlgeschlagen'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(
      tester
          .widget<OBSettingsToggleRow>(
            find.widgetWithText(OBSettingsToggleRow, 'Abstände anzeigen'),
          )
          .interactive,
      isFalse,
    );
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle_gaps-settings-refresh.png'),
    );
    final writes = repo.cycleContextRefreshCalls;
    repo.failCycleContextRefresh = false;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(find.text('Gespeichert · Aktualisieren fehlgeschlagen'), findsNothing);
    expect(repo.cycleSettings.lengthReviewEnabled, isTrue);
    expect(repo.cycleContextRefreshCalls, greaterThan(writes));

    repo.cycleSettings = const CycleSettings(
      enabled: true,
      estimatesEnabled: true,
      lengthReviewEnabled: false,
    );
    await mount(
      tester,
      brightness: Brightness.dark,
      home: OpenBandCycleSettings(
        repository: repo,
        now: () => _paperNow,
        synthetic: true,
      ),
    );
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle_gaps-settings-off-dark.png'),
    );
    repo.failCycleContextRefresh = true;
    await tester.tap(_toggle('Abstände anzeigen'));
    await tester.pumpAndSettle();
    expect(find.text('Gespeichert · Aktualisieren fehlgeschlagen'), findsOneWidget);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle_gaps-settings-refresh-dark.png'),
    );
  });

  testWidgets('insufficient, duplicate, unreadable, long gap, error retry', (
    tester,
  ) async {
    repo.clearCycleLogs();
    repo.cycleSettings = const CycleSettings(
      enabled: true,
      estimatesEnabled: true,
      lengthReviewEnabled: true,
    );
    repo.seedCycleStart(
      const CycleStart(date: '2026-07-27', kind: kCycleStartKind),
    );
    repo.seedCycleStart(
      const CycleStart(date: '2026-08-24', kind: kCycleStartKind),
    );
    await mount(tester);
    expect(find.text('Mindestens 12 Abstände nötig'), findsOneWidget);
    expect(find.text('Zum Zyklus'), findsOneWidget);
    expect(find.textContaining('1 Abstand'), findsNothing);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle_gaps-insufficient.png'),
    );

    repo.clearCycleLogs();
    repo.seedCycleStart(
      const CycleStart(date: '2026-06-01', kind: kCycleStartKind),
    );
    repo.seedCycleStart(
      const CycleStart(date: '2026-08-24', kind: kCycleStartKind),
    );
    await mount(tester);
    expect(find.text('Abstand über 60 Tage'), findsOneWidget);
    expect(find.text('Zum Zyklus'), findsOneWidget);
    final longColor = tester
        .widget<Text>(find.text('Abstand über 60 Tage'))
        .style
        ?.color;
    expect(longColor, AlpColor.muted);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle_gaps-long-gap.png'),
    );

    repo.clearCycleLogs();
    repo.seedUnreadableCycleStart({'date': '2026-08-24', 'kind': 1});
    await mount(tester);
    expect(find.text('Zyklusbeginn nicht lesbar'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Zyklusbeginn nicht lesbar')).style?.color,
      AlpColor.danger,
    );
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle_gaps-unreadable.png'),
    );

    _seedPaperGaps(repo);
    repo.seedUnreadableCycleStart({
      'date': '2025-09-14',
      'kind': kCycleStartKind,
    });
    await mount(tester);
    expect(find.text('Zyklusbeginn nicht lesbar'), findsOneWidget);
    expect(find.text('12 Abstände'), findsNothing);

    repo = _GateRepo();
    _seedPaperGaps(repo);
    repo.failCycleRead = true;
    await mount(tester);
    expect(find.text('Daten nicht geladen'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(find.text('12 Abstände'), findsNothing);
    expect(
      tester.widget<Text>(find.text('Daten nicht geladen')).style?.color,
      AlpColor.danger,
    );
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle_gaps-error.png'),
    );
    repo.failCycleRead = false;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(find.text('12 Abstände'), findsOneWidget);
  });

  testWidgets('observation-only partial does not warn', (tester) async {
    repo.seedUnreadableCycleObservation({
      'date': '2026-09-10',
      'symptoms_json': '{',
    });
    await mount(tester);
    expect(find.text('12 Abstände'), findsOneWidget);
    expect(find.textContaining('teilweise'), findsNothing);
    expect(find.text('Zyklusbeginn nicht lesbar'), findsNothing);
  });

  testWidgets('stale loads and picker do not keep old gaps', (tester) async {
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
    expect(find.text('12 Abstände'), findsNothing);

    final second = _GateRepo();
    _seedPaperGaps(second, earlier: true);
    final secondGate = Completer<void>();
    second.gate = secondGate;
    hostKey.currentState!.update(repository: second);
    await tester.pump();
    expect(find.text('12 Abstände'), findsNothing);

    first.complete();
    await tester.pump();
    expect(find.text('12 Abstände'), findsNothing);

    secondGate.complete();
    await tester.pumpAndSettle();
    expect(find.text('12 von 13 Abständen'), findsOneWidget);
    expect(find.text('12 Abstände'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('cycle-gaps-picker')));
    await tester.pumpAndSettle();
    expect(find.text('Aug.–Sept. 2025'), findsOneWidget);

    final third = _GateRepo();
    _seedPaperGaps(third);
    hostKey.currentState!.update(repository: third);
    await tester.pump();
    await tester.tap(find.text('Aug.–Sept. 2025'));
    await tester.pumpAndSettle();
    expect(find.text('1 von 13 Abständen'), findsNothing);
    expect(find.text('12 Abstände'), findsOneWidget);
    expect(find.text('Aug.–Sept. 2025'), findsNothing);
  });

  testWidgets('as-of year on axis and singular coverage', (tester) async {
    _seedPaperGaps(repo, earlier: true);
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('cycle-gaps-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aug.–Sept. 2025'));
    await tester.pumpAndSettle();
    expect(find.text('1 von 13 Abständen'), findsOneWidget);
    expect(find.text('14. Sept. 2025'), findsOneWidget);
    expect(find.text('14. Sept.'), findsNothing);
  });

  testWidgets('info uses the shared sheet', (tester) async {
    await mount(tester);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Abstände zählen die Kalendertage zwischen zwei eingetragenen Beginnen. Der laufende Zyklus ist noch nicht enthalten.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Die Ansicht ist optional und benötigt zwölf Abstände. Bei mehr als 60 Tagen oder einem nicht lesbaren Beginn bleibt sie offen. Ein fehlender Beginn lässt sich nicht von einem längeren Zyklus unterscheiden.',
      ),
      findsOneWidget,
    );
    expect(find.text('Schließen'), findsOneWidget);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle_gaps-info.png'),
    );
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('journal-info-body')), findsNothing);
  });

  testWidgets('375 2x and 320w scroll without overflow', (tester) async {
    await mount(tester, scale: 2, width: 375, height: 812);
    expect(find.text('12 Abstände'), findsOneWidget);
    expect(find.text('27. Juli–24. Aug.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle_gaps-large.png'),
    );
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(find.text('Schließen').hitTestable(), findsOneWidget);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle_gaps-info-large.png'),
    );
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    _seedPaperGaps(repo, earlier: true);
    await mount(tester, scale: 2, width: 375, height: 812);
    await tester.tap(find.byKey(const ValueKey('cycle-gaps-picker')));
    await tester.pumpAndSettle();
    expect(find.text('Sept. 2025–Aug. 2026'), findsWidgets);
    expect(find.text('Aug.–Sept. 2025'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle_gaps-picker-large.png'),
    );
    await tester.tap(find.text('Sept. 2025–Aug. 2026').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Synthetische Daten'), 240);
    expect(tester.takeException(), isNull);

    _seedPaperGaps(repo);
    await mount(
      tester,
      scale: 2,
      width: 375,
      height: 812,
      brightness: Brightness.dark,
    );
    expect(find.text('12 Abstände'), findsOneWidget);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle_gaps-large-dark.png'),
    );

    await mount(tester, width: 320, height: 568);
    expect(find.text('12 Abstände'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Synthetische Daten'), 200);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark remaining states', (tester) async {
    await mount(tester, brightness: Brightness.dark);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle_gaps-info-dark.png'),
    );

    _seedPaperGaps(repo, display: false);
    await mount(tester, brightness: Brightness.dark);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle_gaps-off-dark.png'),
    );

    repo.cycleSettings = const CycleSettings(
      enabled: false,
      estimatesEnabled: true,
      lengthReviewEnabled: true,
    );
    await mount(tester, brightness: Brightness.dark);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle_gaps-disabled-dark.png'),
    );

    repo.clearCycleLogs();
    repo.cycleSettings = const CycleSettings(
      enabled: true,
      estimatesEnabled: true,
      lengthReviewEnabled: true,
    );
    repo.seedCycleStart(
      const CycleStart(date: '2026-08-24', kind: kCycleStartKind),
    );
    await mount(tester, brightness: Brightness.dark);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle_gaps-insufficient-dark.png'),
    );

    repo.clearCycleLogs();
    repo.seedCycleStart(
      const CycleStart(date: '2026-06-01', kind: kCycleStartKind),
    );
    repo.seedCycleStart(
      const CycleStart(date: '2026-08-24', kind: kCycleStartKind),
    );
    await mount(tester, brightness: Brightness.dark);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle_gaps-long-gap-dark.png'),
    );

    repo.clearCycleLogs();
    repo.seedUnreadableCycleStart({'date': '2026-08-24', 'kind': 1});
    await mount(tester, brightness: Brightness.dark);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle_gaps-unreadable-dark.png'),
    );

    repo = _GateRepo();
    _seedPaperGaps(repo);
    repo.failCycleRead = true;
    await mount(tester, brightness: Brightness.dark);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle_gaps-error-dark.png'),
    );

    repo = _GateRepo();
    _seedPaperGaps(repo);
    await mount(tester, brightness: Brightness.dark);
    final plot = find.byKey(const ValueKey('cycle-gaps-plot'));
    final box = tester.getRect(plot);
    final plotW = box.width - 28 - 4;
    final step = plotW / 12;
    await tester.tapAt(Offset(box.left + 28 + 9.5 * step, box.center.dy));
    await tester.pump();
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle_gaps-selected-dark.png'),
    );
  });
}
