import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/cycle.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/journal.dart';
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

class _CycleRepo extends SyntheticOpenBandRepository {
  _CycleRepo() : super.fromMaps(_daySummary(), _sleepDetail());

  int startSaves = 0;
  int startRemoves = 0;
  int startRestores = 0;
  int observationSaves = 0;
  int settingsSaves = 0;
  int refreshes = 0;
  int cycleReads = 0;
  Completer<void>? writeGate;
  Completer<void>? readGate;
  Completer<void>? settingsReadGate;
  Completer<void>? refreshGate;
  Completer<void>? restoreGate;
  bool failSettingsRead = false;

  @override
  Future<CycleSettings> readCycleSettings() async {
    final gate = settingsReadGate;
    if (gate != null) await gate.future;
    if (failSettingsRead) throw StateError('settings unavailable');
    return super.readCycleSettings();
  }

  @override
  Future<CycleSnapshot> readCycle(String day, {DateTime? now}) async {
    cycleReads++;
    final gate = readGate;
    final result = await super.readCycle(day, now: now);
    if (gate != null) await gate.future;
    return result;
  }

  @override
  Future<CycleWriteResult> saveCycleStart(
    CycleStart desired, {
    CycleStart? expected,
    DateTime? now,
  }) async {
    startSaves++;
    final hold = writeGate;
    if (hold != null) await hold.future;
    return super.saveCycleStart(desired, expected: expected, now: now);
  }

  @override
  Future<CycleWriteResult> saveCycleObservation(
    CycleObservation desired, {
    CycleObservation? expected,
    DateTime? now,
  }) async {
    observationSaves++;
    final hold = writeGate;
    if (hold != null) await hold.future;
    return super.saveCycleObservation(desired, expected: expected, now: now);
  }

  @override
  Future<CycleWriteResult> saveCycleSettings(CycleSettings settings) async {
    settingsSaves++;
    final hold = writeGate;
    if (hold != null) await hold.future;
    return super.saveCycleSettings(settings);
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
    final gate = restoreGate;
    if (gate != null) await gate.future;
    return super.restoreCycleStart(removed, now: now);
  }

  @override
  Future<void> refreshCycleContext() async {
    refreshes++;
    final gate = refreshGate;
    if (gate != null) await gate.future;
    return super.refreshCycleContext();
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

  late _CycleRepo repo;
  late OpenBandController journalController;

  setUp(() => repo = _CycleRepo());

  Future<void> mount(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double scale = 1,
    double width = 393,
    double height = 852,
    String day = '2026-09-15',
    DateTime? now,
    bool synthetic = true,
    bool settingsOnly = false,
    Widget? home,
    double viewInsetBottom = 0,
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
            viewInsets: viewInsetBottom > 0
                ? EdgeInsets.only(bottom: viewInsetBottom)
                : MediaQuery.of(context).viewInsets,
            disableAnimations: true,
          ),
          child: RepaintBoundary(
            key: const ValueKey('capture'),
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        home:
            home ??
            OpenBandCycle(
              repository: repo,
              day: day,
              now: () => now ?? DateTime(2026, 9, 15, 9, 41),
              synthetic: synthetic,
              settingsOnly: settingsOnly,
            ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> mountJournal(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    journalController = OpenBandController(
      repository: repo,
      initialDay: '2026-09-15',
      band: repo.band,
      now: () => DateTime(2026, 9, 15, 9, 41),
    );
    addTearDown(journalController.dispose);
    await journalController.refresh();
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(1),
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            viewPadding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: child ?? const SizedBox.shrink(),
        ),
        home: Scaffold(body: OpenBandJournal(controller: journalController)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder capture() => find.byKey(const ValueKey('capture'));

  Future<void> expectGolden(WidgetTester tester, String name) async {
    await expectLater(capture(), matchesGoldenFile('openband_goldens/$name'));
  }

  /// Header back sits in the page list. After scrolling to Verlauf/Einstellungen
  /// it is offstage; bring it on-screen before tapping.
  Future<void> tapCycleBack(WidgetTester tester) async {
    Finder hit() => find.byTooltip('Zurück').hitTestable();
    if (hit().evaluate().isEmpty) {
      final hidden = find.byTooltip('Zurück', skipOffstage: false);
      expect(
        hidden,
        findsWidgets,
        reason: 'Expected a Zurück control on the current route.',
      );
      await tester.ensureVisible(hidden.first);
      await tester.pumpAndSettle();
    }
    expect(hit(), findsWidgets);
    await tester.tap(hit().first);
  }

  Finder noteEditable() => find.descendant(
    of: find.byKey(const ValueKey('cycle-note')),
    matching: find.byType(EditableText),
  );

  bool noteHasFocus(WidgetTester tester) =>
      tester.state<EditableTextState>(noteEditable()).widget.focusNode.hasFocus;

  testWidgets('main summary matches stored fixture', (tester) async {
    await mount(tester);
    expect(find.text('Tag 23'), findsOneWidget);
    expect(find.text('Beginn · 24. August'), findsOneWidget);
    expect(
      find.text('17.–25. Sept.'),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .join(' | '),
    );
    expect(find.text('3 bisherige Abstände'), findsOneWidget);
    expect(find.text('Beginn eintragen'), findsOneWidget);
    expect(find.text('Selbst eintragen'), findsNothing);
    expect(find.text('Vergleich'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Zyklustage')).dy,
      lessThan(tester.getTopLeft(find.text('Vergleich')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Vergleich')).dy,
      lessThan(tester.getTopLeft(find.text('Beobachtungen')).dy),
    );
    await expectGolden(tester, 'cycle-main.png');
    await mount(tester, brightness: Brightness.dark);
    await expectGolden(tester, 'cycle-main-dark.png');
  });

  testWidgets('equal estimate bounds collapse to one date', (tester) async {
    repo.seedCycleComparisonFixture();
    await mount(tester);
    expect(find.text('Nächster Beginn · geschätzt'), findsOneWidget);
    expect(find.text('25. Sept.'), findsOneWidget);
    expect(find.text('25.–25. Sept.'), findsNothing);
    expect(find.text('17.–25. Sept.'), findsNothing);
    expect(find.text('3 bisherige Abstände'), findsOneWidget);
    expect(find.text('Tag 23'), findsOneWidget);
  });

  testWidgets('empty is not a read failure', (tester) async {
    repo.clearCycleLogs();
    await mount(tester);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('Noch kein Beginn'), findsOneWidget);
    expect(find.text('Daten nicht geladen'), findsNothing);
    expect(find.text('Nächster Beginn · geschätzt'), findsNothing);
    await expectGolden(tester, 'cycle-empty.png');
    await mount(tester, brightness: Brightness.dark);
    await expectGolden(tester, 'cycle-empty-dark.png');
  });

  testWidgets('first start on selected day opens edit', (tester) async {
    repo.clearCycleLogs();
    repo.seedCycleStart(
      const CycleStart(date: '2026-09-15', kind: kCycleStartKind),
    );
    await mount(tester);
    expect(find.text('Tag 1'), findsOneWidget);
    expect(find.text('Beginn · 15. September'), findsOneWidget);
    expect(find.text('Beginn bearbeiten'), findsOneWidget);
    expect(find.text('Nächster Beginn · geschätzt'), findsNothing);
    await expectGolden(tester, 'cycle-first-start.png');
  });

  testWidgets('missing estimate with a long gap shows the reason', (
    tester,
  ) async {
    repo.clearCycleLogs();
    repo.seedCycleStart(
      const CycleStart(date: '2026-06-01', kind: kCycleStartKind),
    );
    repo.seedCycleStart(
      const CycleStart(date: '2026-08-24', kind: kCycleStartKind),
    );
    await mount(tester);
    expect(find.text('Tag 23'), findsOneWidget);
    expect(find.text('Schätzung offen'), findsOneWidget);
    expect(find.text('Abstand über 60 Tage'), findsOneWidget);
    await expectGolden(tester, 'cycle-estimate-open.png');
  });

  testWidgets('disabled estimate is omitted', (tester) async {
    repo.cycleSettings = const CycleSettings(
      enabled: true,
      estimatesEnabled: false,
      lengthReviewEnabled: false,
    );
    await mount(tester);
    expect(find.text('Tag 23'), findsOneWidget);
    expect(find.text('Nächster Beginn · geschätzt'), findsNothing);
    expect(find.text('Schätzung offen'), findsNothing);
  });

  testWidgets('declared none suppresses estimate', (tester) async {
    repo.cycleSettings = const CycleSettings(
      enabled: true,
      estimatesEnabled: true,
      situation: CycleSituation.none,
      lengthReviewEnabled: false,
    );
    await mount(tester);
    expect(find.text('Nächster Beginn · geschätzt'), findsNothing);
    expect(find.text('Schätzung offen'), findsNothing);
  });

  testWidgets('read error is not empty', (tester) async {
    repo.failCycleRead = true;
    await mount(tester);
    expect(find.text('Daten nicht geladen'), findsOneWidget);
    expect(find.text('Noch kein Beginn'), findsNothing);
    expect(find.text('Beginn eintragen'), findsNothing);
    await expectGolden(tester, 'cycle-read-error.png');
    repo.failCycleRead = false;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(find.text('Tag 23'), findsOneWidget);
  });

  testWidgets('settings and setup goldens', (tester) async {
    await mount(tester, settingsOnly: true);
    expect(find.text('Zyklus im Journal'), findsOneWidget);
    expect(find.text('Zeitschätzung'), findsOneWidget);
    expect(find.text('Abstände anzeigen'), findsOneWidget);
    expect(find.text('Keine Angabe'), findsOneWidget);
    await expectGolden(tester, 'cycle-settings.png');
    await mount(tester, settingsOnly: true, brightness: Brightness.dark);
    await expectGolden(tester, 'cycle-settings-dark.png');
    repo.cycleSettings = const CycleSettings(
      enabled: false,
      estimatesEnabled: false,
      lengthReviewEnabled: false,
    );
    await mount(tester, settingsOnly: true);
    await expectGolden(tester, 'cycle-setup.png');
  });

  testWidgets('start and observation goldens', (tester) async {
    await mount(tester);
    await tester.tap(find.text('Beginn eintragen'));
    await tester.pumpAndSettle();
    expect(find.text('Datum'), findsOneWidget);
    expect(find.text('Notiz'), findsOneWidget);
    expect(find.text('Speichern'), findsOneWidget);
    await expectGolden(tester, 'cycle-start.png');
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    await mount(tester, brightness: Brightness.dark);
    await tester.tap(find.text('Beginn eintragen'));
    await tester.pumpAndSettle();
    await expectGolden(tester, 'cycle-start-dark.png');
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    repo.seedCycleObservation(
      const CycleObservation(date: '2026-09-15', tags: ['cramps']),
    );
    await mount(tester);
    await tester.tap(find.text('Beobachtung festhalten'));
    await tester.pumpAndSettle();
    expect(find.text('Krämpfe'), findsOneWidget);
    expect(find.text('Kopfschmerzen'), findsOneWidget);
    expect(find.text('Stimmungstief'), findsOneWidget);
    expect(find.text('Niedergeschlagenheit'), findsNothing);
    await expectGolden(tester, 'cycle-observation.png');
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    await mount(tester, brightness: Brightness.dark);
    await tester.tap(find.text('Beobachtung festhalten'));
    await tester.pumpAndSettle();
    await expectGolden(tester, 'cycle-observation-dark.png');
  });

  testWidgets('history is as-of selected day and tappable', (tester) async {
    repo.seedCycleObservation(
      const CycleObservation(date: '2026-09-15', tags: ['cramps']),
    );
    await mount(tester);
    await tester.drag(
      find.byKey(const ValueKey('cycle-overview')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verlauf'));
    await tester.pumpAndSettle();
    expect(find.text('15. September'), findsOneWidget);
    expect(find.text('Krämpfe'), findsOneWidget);
    expect(find.text('24. August'), findsOneWidget);
    expect(find.text('1. Juni'), findsOneWidget);
    await expectGolden(tester, 'cycle-history.png');
    await tester.tap(find.text('Krämpfe'));
    await tester.pumpAndSettle();
    expect(find.text('BEOBACHTUNG'), findsOneWidget);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('24. August'));
    await tester.pumpAndSettle();
    expect(find.text('BEGINN'), findsOneWidget);
  });

  testWidgets('history hides later rows when an earlier day is selected', (
    tester,
  ) async {
    repo.seedCycleObservation(
      const CycleObservation(date: '2026-09-15', tags: ['cramps']),
    );
    await mount(tester, day: '2026-08-24');
    await tester.drag(
      find.byKey(const ValueKey('cycle-overview')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verlauf'));
    await tester.pumpAndSettle();
    expect(find.text('15. September'), findsNothing);
    expect(find.text('24. August'), findsOneWidget);
    expect(find.text('1. Juni'), findsOneWidget);
  });

  testWidgets('save error keeps the draft', (tester) async {
    repo.failCycleWrite = true;
    await mount(tester);
    await tester.tap(find.text('Beginn eintragen'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('cycle-note')),
      'Heute begonnen',
    );
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(find.text('Heute begonnen'), findsOneWidget);
    expect(repo.startSaves, 1);
    await expectGolden(tester, 'cycle-save-error.png');
    repo.failCycleWrite = false;
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(repo.startSaves, 2);
    expect(find.text('Tag 1'), findsOneWidget);
  });

  testWidgets('context refresh retry does not write again', (tester) async {
    repo.failCycleContextRefresh = true;
    await mount(tester);
    await tester.tap(find.text('Beginn eintragen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(
      find.text('Gespeichert · Aktualisieren fehlgeschlagen'),
      findsOneWidget,
    );
    expect(find.text('Speichern'), findsNothing);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('cycle-note')))
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<OBSettingsValueRow>(
            find.widgetWithText(OBSettingsValueRow, 'Datum'),
          )
          .chevron,
      isFalse,
    );
    expect(repo.startSaves, 1);
    await expectGolden(tester, 'cycle-saved-refresh.png');
    repo.failCycleContextRefresh = false;
    final reads = repo.cycleReads;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(repo.startSaves, 1);
    expect(repo.cycleReads, greaterThan(reads));
    expect(find.text('Tag 1'), findsOneWidget);
  });

  testWidgets('read retry after save does not write again', (tester) async {
    await mount(tester);
    await tester.tap(find.text('Beginn eintragen'));
    await tester.pumpAndSettle();
    repo.failCycleRead = true;
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Gespeichert · Daten nicht geladen'), findsOneWidget);
    expect(find.text('Speichern'), findsNothing);
    expect(repo.startSaves, 1);
    repo.failCycleRead = false;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(repo.startSaves, 1);
    expect(find.text('Tag 1'), findsOneWidget);
  });

  testWidgets('busy save disables a second write', (tester) async {
    repo.writeGate = Completer<void>();
    await mount(tester);
    await tester.tap(find.text('Beginn eintragen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pump();
    await tester.tap(find.text('Speichern'));
    await tester.pump();
    expect(repo.startSaves, 1);
    repo.writeGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Tag 1'), findsOneWidget);
  });

  testWidgets('back does not write', (tester) async {
    await mount(tester);
    await tester.tap(find.text('Beginn eintragen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('cycle-note')), 'Entwurf');
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(repo.startSaves, 0);
    expect(find.text('Tag 23'), findsOneWidget);
  });

  testWidgets('existing selected start opens edit not overwrite', (
    tester,
  ) async {
    repo.clearCycleLogs();
    repo.seedCycleStart(
      const CycleStart(
        date: '2026-09-15',
        kind: kCycleStartKind,
        note: 'Original',
      ),
    );
    await mount(tester);
    await tester.tap(find.text('Beginn bearbeiten'));
    await tester.pumpAndSettle();
    expect(find.text('Original'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('cycle-note')),
      'Geändert',
    );
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(repo.startSaves, 1);
    await tester.tap(find.text('Beginn bearbeiten'));
    await tester.pumpAndSettle();
    expect(find.text('Geändert'), findsOneWidget);
  });

  testWidgets('start conflict retains the draft until reload is accepted', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('Beginn eintragen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('cycle-note')), 'Entwurf');
    repo.seedCycleStart(
      const CycleStart(
        date: '2026-09-15',
        kind: kCycleStartKind,
        note: 'Fremd',
      ),
    );
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Eintrag wurde geändert'), findsOneWidget);
    expect(find.text('Entwurf'), findsOneWidget);
    expect(repo.startSaves, 1);
    await tester.tap(find.text('Neu laden'));
    await tester.pumpAndSettle();
    expect(find.text('Entwurf'), findsNothing);
    expect(find.text('Fremd'), findsOneWidget);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(repo.startSaves, 2);
    await tester.tap(find.text('Beginn bearbeiten'));
    await tester.pumpAndSettle();
    expect(find.text('Fremd'), findsOneWidget);
  });

  testWidgets('remove start confirms and undo restores exact row', (
    tester,
  ) async {
    repo.clearCycleLogs();
    const original = CycleStart(
      date: '2026-09-15',
      kind: kCycleStartKind,
      note: 'Original',
    );
    repo.seedCycleStart(original);
    await mount(tester);
    await tester.tap(find.text('Beginn bearbeiten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('15. September'), findsWidgets);
    await tester.tap(find.text('Entfernen').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Noch kein Beginn'), findsOneWidget);
    expect(find.text('Beginn 15. Sept. entfernt'), findsOneWidget);
    expect(find.text('Rückgängig'), findsOneWidget);
    await tester.tap(find.text('Rückgängig'));
    await tester.pumpAndSettle();
    expect(find.text('Tag 1'), findsOneWidget);
    await tester.tap(find.text('Beginn bearbeiten'));
    await tester.pumpAndSettle();
    expect(find.text('Original'), findsOneWidget);
  });

  testWidgets('observation toggles unknown tags and note-only', (tester) async {
    repo.seedCycleObservation(
      const CycleObservation(
        date: '2026-09-15',
        tags: ['cramps', 'legacy-spotting'],
        note: 'behalten',
        updatedAt: 1,
      ),
    );
    await mount(tester);
    await tester.tap(find.text('Beobachtung festhalten'));
    await tester.pumpAndSettle();
    expect(find.text('legacy-spotting'), findsOneWidget);
    await tester.tap(find.text('Krämpfe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(repo.observationSaves, 1);
    final kept = await repo.readCycle('2026-09-15', now: DateTime(2026, 9, 15));
    expect(kept.observations.single.tags, ['legacy-spotting']);
    expect(kept.observations.single.note, 'behalten');
    await tester.tap(find.text('Beobachtung festhalten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('legacy-spotting'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('cycle-note')),
      'nur Notiz',
    );
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    final noteOnly = await repo.readCycle(
      '2026-09-15',
      now: DateTime(2026, 9, 15),
    );
    expect(noteOnly.observations.single.tags, isEmpty);
    expect(noteOnly.observations.single.note, 'nur Notiz');
  });

  testWidgets(
    'start and observation on the same day stay separately editable',
    (tester) async {
      repo.clearCycleLogs();
      repo.seedCycleStart(
        const CycleStart(date: '2026-09-15', kind: kCycleStartKind),
      );
      repo.seedCycleObservation(
        const CycleObservation(date: '2026-09-15', tags: ['nausea']),
      );
      await mount(tester);
      await tester.drag(
      find.byKey(const ValueKey('cycle-overview')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verlauf'));
      await tester.pumpAndSettle();
      expect(find.text('Übelkeit'), findsOneWidget);
      expect(find.text('Beginn'), findsOneWidget);
      await tester.tap(find.text('Übelkeit'));
      await tester.pumpAndSettle();
      expect(find.text('BEOBACHTUNG'), findsOneWidget);
      await tester.tap(find.byTooltip('Zurück'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beginn'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cycle-start')), findsOneWidget);
    },
  );

  testWidgets('shell selected day is preserved after a historical edit', (
    tester,
  ) async {
    await mountJournal(tester);
    expect(find.text('Zyklus'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('cycle-journal')));
    await tester.tap(find.byKey(const ValueKey('cycle-journal')));
    await tester.pumpAndSettle();
    expect(find.text('Di., 15. Sept.'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('cycle-overview')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verlauf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('24. August'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('cycle-note')),
      'historisch',
    );
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    await tapCycleBack(tester);
    await tester.pumpAndSettle();
    await tapCycleBack(tester);
    await tester.pumpAndSettle();
    expect(journalController.selectedDay, '2026-09-15');
  });

  testWidgets('journal row hides when off and returns when re-enabled', (
    tester,
  ) async {
    await mountJournal(tester);
    expect(find.byKey(const ValueKey('cycle-journal')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('cycle-journal')));
    await tester.tap(find.byKey(const ValueKey('cycle-journal')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('cycle-overview')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Einstellungen'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(OBSettingsToggleRow, 'Zyklus im Journal'),
        matching: find.byType(CupertinoSwitch),
      ),
    );
    await tester.pumpAndSettle();
    expect(repo.cycleSettings.enabled, isFalse);
    expect((await repo.readCycle('2026-09-15')).starts, isNotEmpty);
    await tapCycleBack(tester);
    await tester.pumpAndSettle();
    await tapCycleBack(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cycle-journal')), findsNothing);
    await mount(tester, settingsOnly: true);
    expect(find.text('Zyklus im Journal'), findsOneWidget);
    expect(find.textContaining('Wellness'), findsNothing);
    repo.cycleSettings = const CycleSettings(
      enabled: true,
      estimatesEnabled: true,
      lengthReviewEnabled: false,
    );
    await mountJournal(tester);
    expect(find.byKey(const ValueKey('cycle-journal')), findsOneWidget);
  });

  testWidgets('settings persist after acknowledgement not optimistically', (
    tester,
  ) async {
    repo.writeGate = Completer<void>();
    await mount(tester, settingsOnly: true);
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(OBSettingsToggleRow, 'Zeitschätzung'),
        matching: find.byType(CupertinoSwitch),
      ),
    );
    await tester.pump();
    expect(repo.cycleSettings.estimatesEnabled, isTrue);
    repo.writeGate!.complete();
    await tester.pumpAndSettle();
    expect(repo.cycleSettings.estimatesEnabled, isFalse);
    expect(repo.settingsSaves, 1);
  });

  testWidgets('2x and narrow widths keep save reachable with keyboard', (
    tester,
  ) async {
    await mount(tester, scale: 2, width: 375, height: 812);
    expect(find.text('Tag 23'), findsOneWidget);
    await expectGolden(tester, 'cycle-2x.png');
    await mount(tester, width: 320, height: 568);
    expect(find.text('ZYKLUS'), findsWidgets);
    expect(find.text('Tag 23').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Zurück').hitTestable(), findsOneWidget);
    await tester.pumpAndSettle();
    await expectGolden(tester, 'cycle-320.png');
    await tester.scrollUntilVisible(
      find.text('Einstellungen'),
      80,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('cycle-overview')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Einstellungen').hitTestable(), findsOneWidget);
    await expectGolden(tester, 'cycle-320-bottom.png');
    await mount(tester, width: 375, height: 812);
    await tester.tap(find.text('Beginn eintragen'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Speichern'),
      100,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('cycle-start')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Speichern').hitTestable(), findsOneWidget);
    await expectLater(
      capture(),
      matchesGoldenFile('openband_goldens/cycle-keyboard.png'),
    );
  });

  testWidgets('partial unreadable starts show unknown hero', (tester) async {
    repo.seedUnreadableCycleStart({'date': '2026-05-01', 'kind': 1});
    await mount(tester);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('Einträge teilweise lesbar'), findsOneWidget);
    expect(find.text('Tag 23'), findsNothing);
    expect(find.text('Starts nicht lesbar'), findsNothing);
    expect(find.text('Nächster Beginn · geschätzt'), findsNothing);
    await expectGolden(tester, 'cycle-partial.png');
    await mount(tester, brightness: Brightness.dark);
    await expectGolden(tester, 'cycle-partial-dark.png');
  });

  testWidgets('info body matches Paper', (tester) async {
    await mount(tester);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Median deiner eingetragenen Abstände'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Ein Eisprung wird nicht bestimmt'),
      findsOneWidget,
    );
  });

  testWidgets('situation uses shared choice sheet with selected check', (
    tester,
  ) async {
    await mount(tester, settingsOnly: true);
    await tester.tap(find.text('Situation'));
    await tester.pumpAndSettle();
    expect(find.byType(OBSettingsChoiceSheet<int>), findsOneWidget);
    expect(find.text('Keine Angabe'), findsWidgets);
    expect(find.text('Natürlicher Zyklus'), findsOneWidget);
    await tester.tap(find.text('Natürlicher Zyklus'));
    await tester.pumpAndSettle();
    expect(repo.cycleSettings.situation, CycleSituation.cycling);
    expect(find.text('Natürlicher Zyklus'), findsOneWidget);
  });

  testWidgets('existing observation date is fixed', (tester) async {
    repo.seedCycleObservation(
      const CycleObservation(date: '2026-09-15', tags: ['cramps']),
    );
    await mount(tester);
    await tester.tap(find.text('Beobachtung festhalten'));
    await tester.pumpAndSettle();
    final row = tester.widget<OBSettingsValueRow>(
      find.widgetWithText(OBSettingsValueRow, 'Datum'),
    );
    expect(row.chevron, isFalse);
    expect(row.onTap, isNull);
  });

  testWidgets('new observation date pick loads existing CAS', (tester) async {
    repo.seedCycleObservation(
      const CycleObservation(
        date: '2026-09-14',
        tags: ['cramps'],
        note: 'alt',
        updatedAt: 1,
      ),
    );
    await mount(tester);
    await tester.tap(find.text('Beobachtung festhalten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Datum'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('14'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(find.text('alt'), findsOneWidget);
    final row = tester.widget<OBSettingsValueRow>(
      find.widgetWithText(OBSettingsValueRow, 'Datum'),
    );
    expect(row.chevron, isFalse);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(repo.observationSaves, 1);
    final kept = await repo.readCycle('2026-09-14', now: DateTime(2026, 9, 15));
    expect(kept.observations.single.note, 'alt');
  });

  testWidgets('future calendar day is not committed', (tester) async {
    await mount(tester);
    await tester.tap(find.text('Beginn eintragen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Datum'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('16'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(find.text('15. Sept. 2026'), findsOneWidget);
  });

  testWidgets('history empty and partial are labelled', (tester) async {
    repo.clearCycleLogs();
    await mount(tester);
    await tester.drag(
      find.byKey(const ValueKey('cycle-overview')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verlauf'));
    await tester.pumpAndSettle();
    expect(find.text('Keine Einträge'), findsOneWidget);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    repo.seedCycleStart(
      const CycleStart(date: '2026-08-24', kind: kCycleStartKind),
    );
    repo.seedUnreadableCycleStart({'date': '2026-05-01', 'kind': 1});
    await mount(tester);
    await tester.drag(
      find.byKey(const ValueKey('cycle-overview')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verlauf'));
    await tester.pumpAndSettle();
    expect(find.text('Einträge teilweise lesbar'), findsOneWidget);
    expect(find.text('24. August'), findsOneWidget);
  });

  testWidgets('remove wake failure keeps undo and does not remove again', (
    tester,
  ) async {
    repo.clearCycleLogs();
    repo.seedCycleStart(
      const CycleStart(
        date: '2026-09-15',
        kind: kCycleStartKind,
        note: 'Original',
      ),
    );
    repo.failCycleContextRefresh = true;
    await mount(tester);
    await tester.tap(find.text('Beginn bearbeiten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(repo.startRemoves, 1);
    expect(
      find.text('Entfernt · Aktualisieren fehlgeschlagen'),
      findsOneWidget,
    );
    expect(find.text('Rückgängig'), findsOneWidget);
    expect(find.text('Noch kein Beginn'), findsOneWidget);
    repo.failCycleContextRefresh = false;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(repo.startRemoves, 1);
    expect(find.text('Aktualisieren fehlgeschlagen'), findsNothing);
  });

  testWidgets('restore wake failure reloads source and retries refresh only', (
    tester,
  ) async {
    repo.clearCycleLogs();
    repo.seedCycleStart(
      const CycleStart(
        date: '2026-09-15',
        kind: kCycleStartKind,
        note: 'Original',
      ),
    );
    await mount(tester);
    await tester.tap(find.text('Beginn bearbeiten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    repo.failCycleContextRefresh = true;
    await tester.tap(find.text('Rückgängig'));
    await tester.pumpAndSettle();
    expect(repo.startRestores, 1);
    expect(find.text('Tag 1'), findsOneWidget);
    expect(
      find.text('Wiederhergestellt · Aktualisieren fehlgeschlagen'),
      findsOneWidget,
    );
    repo.failCycleContextRefresh = false;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(repo.startRestores, 1);
    expect(find.text('Aktualisieren fehlgeschlagen'), findsNothing);
    await tester.tap(find.text('Beginn bearbeiten'));
    await tester.pumpAndSettle();
    expect(find.text('Original'), findsOneWidget);
  });

  testWidgets('history restore conflict reloads read-only', (tester) async {
    repo.clearCycleLogs();
    repo.seedCycleStart(
      const CycleStart(
        date: '2026-08-24',
        kind: kCycleStartKind,
        note: 'Original',
      ),
    );
    await mount(tester);
    await tester.drag(
      find.byKey(const ValueKey('cycle-overview')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verlauf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('24. August'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Beginn 24. Aug. entfernt'), findsOneWidget);
    repo.seedCycleStart(
      const CycleStart(
        date: '2026-08-24',
        kind: kCycleStartKind,
        note: 'Fremd',
      ),
    );
    await tester.tap(find.text('Rückgängig'));
    await tester.pumpAndSettle();
    expect(find.text('Beginn wurde geändert'), findsOneWidget);
    expect(find.text('Neu laden'), findsOneWidget);
    expect(repo.startRestores, 1);
    await tester.tap(find.text('Neu laden'));
    await tester.pumpAndSettle();
    expect(repo.startRestores, 1);
    expect(find.text('Beginn wurde geändert'), findsNothing);
    await tester.tap(find.text('24. August'));
    await tester.pumpAndSettle();
    expect(find.text('Fremd'), findsOneWidget);
  });

  testWidgets('journal enable refreshes on same day without date change', (
    tester,
  ) async {
    await mountJournal(tester);
    expect(find.byKey(const ValueKey('cycle-journal')), findsOneWidget);
    repo.cycleSettings = const CycleSettings(
      enabled: false,
      estimatesEnabled: true,
      lengthReviewEnabled: false,
    );
    await journalController.refresh();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cycle-journal')), findsNothing);
    // Re-enable on the SAME mounted Journal, as the shell source refresh does.
    await repo.saveCycleSettings(
      const CycleSettings(
        enabled: true,
        estimatesEnabled: false,
        lengthReviewEnabled: false,
      ),
    );
    await journalController.refresh();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cycle-journal')), findsOneWidget);
    expect(journalController.selectedDay, '2026-09-15');
  });

  testWidgets('Journal unknown read is retryable, not disabled', (
    tester,
  ) async {
    repo.failSettingsRead = true;
    await mountJournal(tester);
    final row = find.byKey(const ValueKey('cycle-journal'));
    await tester.scrollUntilVisible(row, 200);
    expect(find.text('Daten nicht geladen'), findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('—')), findsOneWidget);
    repo.failSettingsRead = false;
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('Daten nicht geladen'), findsNothing);
    expect(row, findsOneWidget);
    repo.failSettingsRead = true;
    await journalController.refresh();
    await tester.pumpAndSettle();
    expect(row, findsOneWidget);
    expect(find.text('Daten nicht geladen'), findsOneWidget);
    repo.failSettingsRead = false;
    await repo.saveCycleSettings(
      const CycleSettings(
        enabled: false,
        estimatesEnabled: false,
        lengthReviewEnabled: false,
      ),
    );
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(row, findsNothing);
  });

  testWidgets('main day and repository replacement reject stale reads', (
    tester,
  ) async {
    final source = ValueNotifier<(OpenBandRepository, String)>((
      repo,
      '2026-09-15',
    ));
    addTearDown(source.dispose);
    await mount(
      tester,
      home: ValueListenableBuilder<(OpenBandRepository, String)>(
        valueListenable: source,
        builder: (_, value, _) => OpenBandCycle(
          repository: value.$1,
          day: value.$2,
          now: () => DateTime(2026, 9, 15),
        ),
      ),
    );
    expect(find.text('Tag 23'), findsOneWidget);
    final gate = repo.readGate = Completer<void>();
    source.value = (repo, '2026-08-24');
    await tester.pump();
    expect(find.text('Tag 23'), findsNothing);
    expect(find.text('Beginn eintragen'), findsNothing);
    final replacement = _CycleRepo()..clearCycleLogs();
    source.value = (replacement, '2026-09-15');
    await tester.pumpAndSettle();
    expect(find.text('Noch kein Beginn'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Tag 1'), findsNothing);
    expect(find.text('Noch kein Beginn'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history clears old rows while selected date loads', (
    tester,
  ) async {
    await mount(tester);
    await tester.drag(
      find.byKey(const ValueKey('cycle-overview')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verlauf'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Datum'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('14'));
    final gate = repo.readGate = Completer<void>();
    await tester.tap(find.text('Übernehmen'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('24. August'), findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('24. August'), findsOneWidget);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('Mo., 14. Sept.'), findsOneWidget);
  });

  for (final situation in [null, CycleSituation.none]) {
    testWidgets('unreadable starts independent of estimate policy $situation', (
      tester,
    ) async {
      repo.cycleSettings = CycleSettings(
        enabled: true,
        estimatesEnabled: false,
        lengthReviewEnabled: false,
        situation: situation,
      );
      repo.seedUnreadableCycleStart({'date': '2026-05-01', 'kind': 1});
      await mount(tester);
      expect(find.text('Tag 23'), findsNothing);
      expect(find.text('—'), findsOneWidget);
      expect(find.text('Einträge teilweise lesbar'), findsOneWidget);
    });
  }

  Future<void> removeFromHistory(WidgetTester tester) async {
    await tester.drag(
      find.byKey(const ValueKey('cycle-overview')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verlauf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('24. August'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen').last);
    await tester.pumpAndSettle();
  }

  testWidgets('overview undo survives a no-op History roundtrip', (
    tester,
  ) async {
    repo.clearCycleLogs();
    const original = CycleStart(
      date: '2026-09-15',
      kind: kCycleStartKind,
      note: '  exact\nsource  ',
    );
    repo.seedCycleStart(original);
    await mount(tester);
    await tester.tap(find.text('Beginn bearbeiten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Rückgängig'), findsOneWidget);
    expect(repo.startRemoves, 1);
    await tester.drag(
      find.byKey(const ValueKey('cycle-overview')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verlauf'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('Rückgängig').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Rückgängig'));
    await tester.pumpAndSettle();
    final snap = await repo.readCycle('2026-09-15');
    expect(
      snap.starts.where((s) => s.date == original.date).single.note,
      original.note,
    );
    expect(repo.startRemoves, 1);
    expect(repo.startRestores, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history back transfers exact Undo and failed refresh receipt', (
    tester,
  ) async {
    const original = CycleStart(
      date: '2026-08-24',
      kind: kCycleStartKind,
      note: '  exact\nsource  ',
    );
    repo.seedCycleStart(original);
    repo.failCycleContextRefresh = true;
    await mount(tester);
    await removeFromHistory(tester);
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(
      find.text('Entfernt · Aktualisieren fehlgeschlagen'),
      findsOneWidget,
    );
    expect(repo.startRemoves, 1);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(
      find.text('Entfernt · Aktualisieren fehlgeschlagen'),
      findsOneWidget,
    );
    expect(find.text('Rückgängig').hitTestable(), findsOneWidget);
    repo.failCycleContextRefresh = false;
    await tester.tap(find.text('Rückgängig'));
    await tester.pumpAndSettle();
    final snap = await repo.readCycle('2026-09-15');
    expect(
      snap.starts.where((s) => s.date == original.date).single.note,
      original.note,
    );
    expect(repo.startRemoves, 1);
    expect(repo.startRestores, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Undo cannot outlive the overview route', (tester) async {
    await mount(
      tester,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => OpenBandCycle.push(
              context,
              repository: repo,
              day: '2026-09-15',
              now: () => DateTime(2026, 9, 15),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await removeFromHistory(tester);
    await tapCycleBack(tester);
    await tester.pumpAndSettle();
    expect(find.text('Rückgängig'), findsOneWidget);
    await tapCycleBack(tester);
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Rückgängig'), findsNothing);
    expect(repo.startRestores, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposed editor completion cannot pop parent or write twice', (
    tester,
  ) async {
    repo.writeGate = Completer<void>();
    await mount(tester);
    await tester.tap(find.text('Beginn eintragen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pump();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    repo.writeGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cycle-overview')), findsOneWidget);
    expect(repo.startSaves, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'observation committed refresh failure locks inputs and never replays',
    (tester) async {
      repo.failCycleContextRefresh = true;
      await mount(tester);
      await tester.tap(find.text('Beobachtung festhalten'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Krämpfe'));
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Erneut versuchen'),
        100,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('cycle-observation')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Speichern'), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('cycle-note')))
            .enabled,
        isFalse,
      );
      await tester.tap(find.text('Erneut versuchen'));
      await tester.pumpAndSettle();
      expect(repo.observationSaves, 1);
      repo.failCycleContextRefresh = false;
      await tester.tap(find.text('Erneut versuchen'));
      await tester.pumpAndSettle();
      expect(repo.observationSaves, 1);
      expect(find.byKey(const ValueKey('cycle-overview')), findsOneWidget);
    },
  );

  testWidgets(
    'observation conflict reload adopts actual note and unknown tags',
    (tester) async {
      repo.seedCycleObservation(
        const CycleObservation(
          date: '2026-09-15',
          tags: ['cramps'],
          note: 'original',
          updatedAt: 1,
        ),
      );
      await mount(tester);
      await tester.tap(find.text('Beobachtung festhalten'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('cycle-note')), 'lokal');
      repo.seedCycleObservation(
        const CycleObservation(
          date: '2026-09-15',
          tags: ['nausea', 'legacy'],
          note: 'geändert',
          updatedAt: 2,
        ),
      );
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(find.text('lokal'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Neu laden'),
        100,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('cycle-observation')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Neu laden'));
      await tester.pumpAndSettle();
      expect(find.text('lokal'), findsNothing);
      expect(find.text('geändert'), findsOneWidget);
      expect(find.text('legacy'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Speichern'),
        100,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('cycle-observation')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      final saved = (await repo.readCycle('2026-09-15')).observations.single;
      expect(saved.tags, ['nausea', 'legacy']);
      expect(saved.note, 'geändert');
    },
  );

  testWidgets('move collision reloads original source, never destination CAS', (
    tester,
  ) async {
    repo.seedCycleStart(
      const CycleStart(
        date: '2026-09-15',
        kind: kCycleStartKind,
        note: 'source',
      ),
    );
    repo.seedCycleStart(
      const CycleStart(
        date: '2026-09-14',
        kind: kCycleStartKind,
        note: 'destination',
      ),
    );
    await mount(tester);
    await tester.tap(find.text('Beginn bearbeiten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Datum'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('14'));
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('cycle-note')), 'lokal');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Eintrag wurde geändert'), findsOneWidget);
    expect(find.text('lokal'), findsOneWidget);
    repo.seedCycleStart(
      const CycleStart(
        date: '2026-09-15',
        kind: kCycleStartKind,
        note: 'geändert',
      ),
    );
    await tester.tap(find.text('Neu laden'));
    await tester.pumpAndSettle();
    expect(find.text('15. Sept. 2026'), findsOneWidget);
    expect(find.text('geändert'), findsOneWidget);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    final rows = (await repo.readCycle('2026-09-15')).starts;
    expect(rows.firstWhere((s) => s.date == '2026-09-14').note, 'destination');
    expect(rows.firstWhere((s) => s.date == '2026-09-15').note, 'geändert');
  });

  testWidgets('start move to vacant date retains source note', (tester) async {
    repo.seedCycleStart(
      const CycleStart(
        date: '2026-09-15',
        kind: kCycleStartKind,
        note: ' exact ',
      ),
    );
    await mount(tester);
    await tester.tap(find.text('Beginn bearbeiten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Datum'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('14'));
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    final rows = (await repo.readCycle('2026-09-15')).starts;
    expect(rows.where((s) => s.date == '2026-09-15'), isEmpty);
    expect(rows.firstWhere((s) => s.date == '2026-09-14').note, ' exact ');
    expect(repo.startSaves, 1);
  });

  testWidgets(
    'settings committed read failure retries without another refresh',
    (tester) async {
      await mount(tester, settingsOnly: true);
      repo.failSettingsRead = true;
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(OBSettingsToggleRow, 'Zyklus im Journal'),
          matching: find.byType(CupertinoSwitch),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Gespeichert · Daten nicht geladen'), findsOneWidget);
      expect(find.textContaining('Aktualisieren fehlgeschlagen'), findsNothing);
      expect(repo.settingsSaves, 1);
      expect(repo.refreshes, 1);
      expect(
        tester
            .widget<OBSettingsToggleRow>(
              find.widgetWithText(OBSettingsToggleRow, 'Zyklus im Journal'),
            )
            .interactive,
        isFalse,
      );
      repo.failSettingsRead = false;
      await tester.tap(find.text('Erneut versuchen'));
      await tester.pumpAndSettle();
      expect(find.text('Gespeichert · Daten nicht geladen'), findsNothing);
      expect(repo.settingsSaves, 1);
      expect(repo.refreshes, 1);
      expect(repo.cycleSettings.enabled, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('settings old failure cannot change replacement repository', (
    tester,
  ) async {
    final source = ValueNotifier<OpenBandRepository>(repo);
    addTearDown(source.dispose);
    await mount(
      tester,
      home: ValueListenableBuilder<OpenBandRepository>(
        valueListenable: source,
        builder: (_, value, _) => OpenBandCycle(
          repository: value,
          day: '2026-09-15',
          settingsOnly: true,
        ),
      ),
    );
    final gate = repo.writeGate = Completer<void>();
    repo.failCycleWrite = true;
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(OBSettingsToggleRow, 'Zyklus im Journal'),
        matching: find.byType(CupertinoSwitch),
      ),
    );
    await tester.pump();
    final replacement = _CycleRepo()
      ..cycleSettings = const CycleSettings(
        enabled: false,
        estimatesEnabled: false,
        lengthReviewEnabled: false,
      );
    source.value = replacement;
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen'), findsNothing);
    expect(
      tester
          .widget<OBSettingsToggleRow>(
            find.widgetWithText(OBSettingsToggleRow, 'Zyklus im Journal'),
          )
          .value,
      isFalse,
    );
    expect(replacement.settingsSaves, 0);
  });

  testWidgets('settings late read failure cannot lock replacement repository', (
    tester,
  ) async {
    final source = ValueNotifier<OpenBandRepository>(repo);
    addTearDown(source.dispose);
    await mount(
      tester,
      home: ValueListenableBuilder<OpenBandRepository>(
        valueListenable: source,
        builder: (_, value, _) => OpenBandCycle(
          repository: value,
          day: '2026-09-15',
          settingsOnly: true,
        ),
      ),
    );
    final gate = repo.settingsReadGate = Completer<void>();
    repo.failSettingsRead = true;
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(OBSettingsToggleRow, 'Zyklus im Journal'),
        matching: find.byType(CupertinoSwitch),
      ),
    );
    await tester.pump();
    final replacement = _CycleRepo()
      ..cycleSettings = const CycleSettings(
        enabled: false,
        estimatesEnabled: false,
        lengthReviewEnabled: false,
      );
    source.value = replacement;
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('Daten nicht geladen'), findsNothing);
    expect(find.textContaining('Aktualisieren fehlgeschlagen'), findsNothing);
    expect(find.text('Speichern fehlgeschlagen'), findsNothing);
    expect(
      tester
          .widget<OBSettingsToggleRow>(
            find.widgetWithText(OBSettingsToggleRow, 'Zyklus im Journal'),
          )
          .interactive,
      isTrue,
    );
    expect(
      tester
          .widget<OBSettingsToggleRow>(
            find.widgetWithText(OBSettingsToggleRow, 'Zyklus im Journal'),
          )
          .value,
      isFalse,
    );
    expect(replacement.settingsSaves, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('2x observation at 320 with keyboard can scroll and save', (
    tester,
  ) async {
    await mount(tester, width: 320, height: 568, scale: 2);
    await tester.scrollUntilVisible(
      find.text('Beobachtung festhalten').hitTestable(),
      180,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beobachtung festhalten'));
    await tester.pumpAndSettle();
    final scroll = find
        .descendant(
          of: find.byKey(const ValueKey('cycle-observation')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Stimmungstief').hitTestable(),
      180,
      scrollable: scroll,
    );
    expect(find.text('Stimmungstief'), findsOneWidget);
    expect(find.text('Niedergeschlagenheit'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Übelkeit').hitTestable(),
      180,
      scrollable: scroll,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übelkeit'));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('cycle-note')).hitTestable(),
      180,
      scrollable: scroll,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('cycle-note')), 'Notiz');
    tester.view.viewInsets = const FakeViewPadding(bottom: 220);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Speichern').hitTestable(),
      180,
      scrollable: scroll,
    );
    await tester.pumpAndSettle();
    expect(find.text('Speichern').hitTestable(), findsOneWidget);
    await expectGolden(tester, 'cycle-observation-320-2x-keyboard.png');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(repo.observationSaves, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tap outside shared note at 2x ends focus and reaches Save', (
    tester,
  ) async {
    const longNote =
        'Langer Eintrag mit mehreren Zeilen\n'
        'damit das Feld den Caret über der Tastatur hält\n'
        'und Speichern nicht mehr sichtbar bleibt\n'
        'ohne die Tastatur zu schließen.';

    Future<void> dismissNoteAndReachSave(
      String editorKey,
      String openLabel,
    ) async {
      await tester.scrollUntilVisible(find.text(openLabel).hitTestable(), 180);
      await tester.tap(find.text(openLabel));
      await tester.pumpAndSettle();
      final scroll = find
          .descendant(
            of: find.byKey(ValueKey(editorKey)),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('cycle-note')).hitTestable(),
        180,
        scrollable: scroll,
      );
      await tester.enterText(
        find.byKey(const ValueKey('cycle-note')),
        longNote,
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      await tester.pumpAndSettle();
      expect(noteHasFocus(tester), isTrue);
      final noteBox = tester.getRect(find.byKey(const ValueKey('cycle-note')));
      await tester.tapAt(Offset(noteBox.right + 8, noteBox.center.dy));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey(editorKey)), findsOneWidget);
      expect(noteHasFocus(tester), isFalse);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      final outerScroll = find
          .ancestor(
            of: find.byKey(const ValueKey('cycle-note')),
            matching: find.byType(Scrollable),
          )
          .last;
      await tester.scrollUntilVisible(
        find.text('Speichern'),
        180,
        scrollable: outerScroll,
      );
      expect(find.text('Speichern').hitTestable(), findsOneWidget);
    }

    await mount(tester, width: 320, height: 568, scale: 2);
    addTearDown(tester.view.resetViewInsets);
    await dismissNoteAndReachSave('cycle-start', 'Beginn eintragen');
    await mount(tester, width: 320, height: 568, scale: 2);
    await dismissNoteAndReachSave(
      'cycle-observation',
      'Beobachtung festhalten',
    );
    expect(tester.takeException(), isNull);
  });
}
