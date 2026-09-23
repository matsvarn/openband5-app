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
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/journal.dart';
import 'package:openstrap_edge/openband/medication.dart';
import 'package:openstrap_edge/openband/notification_settings.dart';
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

class _MedRepo extends SyntheticOpenBandRepository {
  _MedRepo() : super.fromMaps(_daySummary(), _sleepDetail());

  int entrySaves = 0;
  int planSaves = 0;
  int restarts = 0;
  int reminderRefreshes = 0;
  Completer<void>? writeGate;
  MedicationEntryDraft? lastEntry;
  MedicationPlanDraft? lastPlan;
  MedicationDay Function(MedicationDay)? transformDay;
  MedicationHistory Function(MedicationHistory)? transformHistory;
  List<MedicationPlan> Function(List<MedicationPlan>)? transformPlans;
  bool failHistoryAfterFirst = false;
  int historyReads = 0;

  @override
  Future<MedicationDay> readMedicationDay(String day, {DateTime? now}) async {
    final snap = await super.readMedicationDay(day, now: now);
    return transformDay?.call(snap) ?? snap;
  }

  @override
  Future<List<MedicationPlan>> readMedicationPlans({
    bool activeOnly = true,
  }) async {
    final plans = await super.readMedicationPlans(activeOnly: activeOnly);
    return transformPlans?.call(plans) ?? plans;
  }

  @override
  Future<MedicationHistory> readMedicationHistory(
    String fromDay,
    String toDay, {
    DateTime? now,
  }) async {
    historyReads++;
    if (failHistoryAfterFirst && historyReads > 1) {
      throw StateError('synthetic medication history paging failure');
    }
    final hist = await super.readMedicationHistory(fromDay, toDay, now: now);
    return transformHistory?.call(hist) ?? hist;
  }

  @override
  Future<MedicationMutationResult> saveMedicationEntry(
    MedicationEntryDraft draft, {
    DateTime? now,
  }) async {
    entrySaves++;
    lastEntry = draft;
    final hold = writeGate;
    if (hold != null) await hold.future;
    return super.saveMedicationEntry(draft, now: now);
  }

  @override
  Future<MedicationMutationResult> saveMedicationPlan(
    MedicationPlanDraft draft, {
    DateTime? now,
  }) async {
    planSaves++;
    lastPlan = draft;
    final hold = writeGate;
    if (hold != null) await hold.future;
    return super.saveMedicationPlan(draft, now: now);
  }

  @override
  Future<MedicationMutationResult> restartMedicationPlan(
    String key, {
    DateTime? now,
  }) async {
    restarts++;
    return super.restartMedicationPlan(key, now: now);
  }

  @override
  Future<void> refreshMedicationReminders() async {
    reminderRefreshes++;
    return super.refreshMedicationReminders();
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

  late _MedRepo repo;

  setUp(() => repo = _MedRepo());

  Future<void> mount(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double scale = 1,
    double width = 393,
    double height = 852,
    String day = '2026-09-15',
    DateTime? now,
    bool synthetic = true,
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
            viewInsets: EdgeInsets.only(bottom: viewInsetBottom),
            disableAnimations: true,
          ),
          child: RepaintBoundary(
            key: const ValueKey('capture'),
            child: child,
          ),
        ),
        home:
            home ??
            OpenBandMedications(
              repository: repo,
              day: day,
              now: () => now ?? DateTime(2026, 9, 15, 9, 41),
              synthetic: synthetic,
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
    final controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-15',
      band: repo.band,
      now: () => DateTime(2026, 9, 15, 9, 41),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
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
          child: child!,
        ),
        home: Scaffold(
          body: OpenBandJournal(
            controller: controller,
            onEdit: (_) async {},
            onNutrition: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder weekdaySwitch(String day) => find.descendant(
    of: find.widgetWithText(OBSettingsToggleRow, day),
    matching: find.byType(CupertinoSwitch),
  );

  testWidgets('main light and dark goldens', (tester) async {
    await mount(tester);
    expect(find.text('Medikamente'), findsOneWidget);
    expect(find.text('Präparat A'), findsOneWidget);
    expect(find.text('Präparat B'), findsOneWidget);
    expect(find.textContaining('Offen'), findsOneWidget);
    expect(find.textContaining('Später'), findsOneWidget);
    expect(find.text('Keine Medikamente'), findsNothing);
    expect(find.text('Keine Einnahme geplant'), findsNothing);
    expect(find.text('Synthetische Daten'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/medication-light.png'),
    );
    await mount(tester, brightness: Brightness.dark);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/medication-dark.png'),
    );
  }, tags: const ['golden']);

  testWidgets('empty plans is not a missing slot', (tester) async {
    repo.transformPlans = (_) => const [];
    repo.transformDay = (day) => MedicationDay(day: day.day, entries: const []);
    await mount(tester);
    expect(find.text('Keine Medikamente'), findsOneWidget);
    expect(find.text('Keine Einnahme geplant'), findsNothing);
    expect(find.text('Medikamente konnten nicht geladen werden.'), findsNothing);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/medication-empty-light.png'),
    );
    await mount(tester, brightness: Brightness.dark);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/medication-empty-dark.png'),
    );
  }, tags: const ['golden']);

  testWidgets('active plans with no day rows is no slot', (tester) async {
    repo.transformDay = (day) => MedicationDay(day: day.day, entries: const []);
    await mount(tester);
    expect(find.text('Keine Einnahme geplant'), findsOneWidget);
    expect(find.text('Keine Medikamente'), findsNothing);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/medication-noslot-light.png'),
    );
  }, tags: const ['golden']);

  testWidgets('read error is not empty and retries', (tester) async {
    repo.failMedicationRead = true;
    await mount(tester);
    expect(find.text('Medikamente konnten nicht geladen werden.'), findsOneWidget);
    expect(find.text('Keine Medikamente'), findsNothing);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/medication-error-light.png'),
    );
    repo.failMedicationRead = false;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(find.text('Präparat A'), findsOneWidget);
  }, tags: const ['golden']);

  testWidgets('partial corrupt reads keep visible rows', (tester) async {
    repo.transformDay = (day) => MedicationDay(
      day: day.day,
      entries: day.entries,
      unreadableCount: 2,
    );
    await mount(tester);
    expect(find.text('Nicht alle Einträge lesbar'), findsOneWidget);
    expect(find.text('Präparat A'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/medication-partial-light.png'),
    );
  }, tags: const ['golden']);

  testWidgets('DST unavailable stays on its own line', (tester) async {
    repo.transformDay = (day) => MedicationDay(
      day: day.day,
      entries: [
        MedicationDayEntry(
          key: SyntheticOpenBandRepository.medicationFixturePlanAKey,
          date: day.day,
          slotMin: 2 * 60 + 30,
          status: MedicationSlotStatus.unavailable,
          snapshotLabel: 'Präparat A',
          snapshotDoseValue: 1,
          snapshotDoseUnit: 'Tablette',
        ),
        ...day.entries.where(
          (e) => e.key == SyntheticOpenBandRepository.medicationFixturePlanBKey,
        ),
      ],
    );
    await mount(tester);
    expect(find.text('Uhrzeit nicht eindeutig'), findsOneWidget);
    expect(find.text('02:30'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/medication-dst-light.png'),
    );
  }, tags: const ['golden']);

  testWidgets('history groups original snapshots and pages older days', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('Verlauf'));
    await tester.pumpAndSettle();
    expect(find.text('Verlauf'), findsOneWidget);
    expect(find.text('Präparat A'), findsWidgets);
    expect(find.textContaining('Genommen'), findsWidgets);
    expect(find.textContaining('Kein Eintrag'), findsWidgets);
    expect(find.textContaining('4 von'), findsNothing);
    expect(find.text('Ältere Einträge'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/medication-history-light.png'),
    );
    final firstReads = repo.historyReads;
    repo.failHistoryAfterFirst = true;
    await tester.tap(find.text('Ältere Einträge'));
    await tester.pumpAndSettle();
    expect(find.text('Präparat A'), findsWidgets);
    expect(find.text('Medikamente konnten nicht geladen werden.'), findsOneWidget);
    repo.failHistoryAfterFirst = false;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(repo.historyReads, greaterThan(firstReads));
    expect(find.text('Präparat A'), findsWidgets);
    await mount(tester, brightness: Brightness.dark);
    await tester.tap(find.text('Verlauf'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/medication-history-dark.png'),
    );
  }, tags: const ['golden']);

  testWidgets('unknown original metadata is not replaced by current plan', (
    tester,
  ) async {
    repo.transformHistory = (hist) => MedicationHistory(
      fromDay: hist.fromDay,
      toDay: hist.toDay,
      entries: [
        const MedicationDayEntry(
          key: 'orphan-old',
          date: '2026-09-14',
          slotMin: 8 * 60,
          status: MedicationSlotStatus.taken,
          takenAt: null,
          snapshotLabel: null,
          snapshotDoseValue: null,
          snapshotDoseUnit: null,
          currentName: 'Präparat A',
          orphan: true,
        ),
        const MedicationDayEntry(
          key: 'orphan-gone',
          date: '2025-09-14',
          slotMin: 9 * 60,
          status: MedicationSlotStatus.unknown,
          orphan: true,
        ),
      ],
    );
    await mount(tester);
    await tester.tap(find.text('Verlauf'));
    await tester.pumpAndSettle();
    expect(find.textContaining('aktueller Name'), findsOneWidget);
    expect(find.text('Präparat A'), findsOneWidget);
    expect(find.text('Medikament'), findsOneWidget);
    expect(find.textContaining('Name und Menge nicht gespeichert'), findsOneWidget);
    expect(find.text('Älterer Eintrag'), findsNothing);
    expect(find.text('Unbekannt'), findsNothing);
    expect(find.text('14. Sept. 2025'), findsOneWidget);
    expect(find.text('1 Tablette'), findsNothing);
  });

  testWidgets('new entry starts unanswered and save stays disabled', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('Präparat A'));
    await tester.pumpAndSettle();
    expect(find.text('Einnahme'), findsOneWidget);
    expect(find.text('Genommen'), findsOneWidget);
    expect(find.text('Ausgelassen'), findsOneWidget);
    expect(find.text('Eintrag entfernen'), findsNothing);
    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Speichern'),
    );
    expect(save.onPressed, isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/medication-unanswered-light.png'),
    );
  }, tags: const ['golden']);

  testWidgets('explicit taken, skipped, and clear persist actual status', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('Präparat A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Genommen'));
    await tester.pumpAndSettle();
    expect(find.text('09:41'), findsOneWidget);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Einnahme'), findsNothing);
    expect(find.textContaining('Genommen 09:41'), findsOneWidget);
    expect(find.text('Gespeichert'), findsNothing);

    await tester.tap(find.text('Präparat A'));
    await tester.pumpAndSettle();
    expect(find.text('Eintrag entfernen'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/medication-record-existing-light.png'),
    );
    await tester.tap(find.text('Ausgelassen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ausgelassen'), findsOneWidget);

    await tester.tap(find.text('Präparat A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eintrag entfernen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Offen'), findsOneWidget);
  }, tags: const ['golden']);

  testWidgets('save error keeps draft and blocks double submit', (tester) async {
    repo.failMedicationWrite = true;
    repo.writeGate = Completer<void>();
    await mount(tester);
    await tester.tap(find.text('Präparat A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Genommen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('medication-note')), 'Notiz');
    await tester.tap(find.text('Speichern'));
    await tester.pump();
    await tester.tap(find.text('Speichern'));
    await tester.pump();
    expect(repo.entrySaves, 1);
    repo.writeGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(find.text('Notiz'), findsOneWidget);
    expect(find.text('Einnahme'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/medication-save-error-light.png'),
    );
    repo.failMedicationWrite = false;
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Genommen'), findsOneWidget);
  }, tags: const ['golden']);

  testWidgets('reminder aftermath retries only refresh', (tester) async {
    repo.failMedicationReminders = true;
    await mount(tester);
    await tester.tap(find.text('Präparat A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Genommen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Gespeichert · Erinnerungen nicht aktualisiert'), findsOneWidget);
    final saves = repo.entrySaves;
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/medication-reminders-failed-light.png'),
    );
    repo.failMedicationReminders = false;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(repo.entrySaves, saves);
    expect(repo.reminderRefreshes, greaterThan(0));
    expect(find.text('Gespeichert · Erinnerungen nicht aktualisiert'), findsNothing);
  }, tags: const ['golden']);

  testWidgets('create edit end restart keep identity', (tester) async {
    await mount(tester);
    await tester.tap(find.text('Medikament hinzufügen'));
    await tester.pumpAndSettle();
    expect(find.text('Medikament hinzufügen'), findsWidgets);
    await tester.enterText(find.byKey(const ValueKey('medication-name')), 'Zink');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    final created = (await repo.readMedicationPlans(
      activeOnly: true,
    )).firstWhere((p) => p.name == 'Zink');
    expect(created.key, isNotEmpty);
    expect(created.active, isTrue);

    await tester.tap(find.text('Pläne verwalten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zink'));
    await tester.pumpAndSettle();
    expect(find.text('Plan bearbeiten'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('medication-name')), 'Zink plus');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    final edited = (await repo.readMedicationPlans(
      activeOnly: false,
    )).firstWhere((p) => p.key == created.key);
    expect(edited.name, 'Zink plus');
    expect(edited.key, created.key);

    await tester.tap(find.text('Zink plus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan beenden'));
    await tester.pumpAndSettle();
    final ended = (await repo.readMedicationPlans(
      activeOnly: false,
    )).firstWhere((p) => p.key == created.key);
    expect(ended.active, isFalse);

    await tester.tap(find.text('Beendete Pläne'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zink plus'));
    await tester.pumpAndSettle();
    expect(find.text('Plan fortsetzen'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, 'Plan fortsetzen'));
    await tester.pumpAndSettle();
    final restarted = (await repo.readMedicationPlans(
      activeOnly: true,
    )).firstWhere((p) => p.key == created.key);
    expect(restarted.active, isTrue);
    expect(restarted.key, created.key);
  });

  testWidgets('plans reminder row uses synthetic notification settings', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('Pläne verwalten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Erinnerungen'));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationSettings), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('journal card pushes medications and back keeps the day', (
    tester,
  ) async {
    await mountJournal(tester);
    expect(find.text('Medikamente'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('medication-journal')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('medication-main')), findsOneWidget);
    expect(find.text('Präparat A'), findsOneWidget);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('Journal'), findsOneWidget);
    expect(find.byKey(const ValueKey('medication-journal')), findsOneWidget);
  });

  testWidgets('375 2x long name stacks the canonical row', (tester) async {
    repo.transformDay = (day) => MedicationDay(
      day: day.day,
      entries: [
        MedicationDayEntry(
          key: SyntheticOpenBandRepository.medicationFixturePlanAKey,
          date: day.day,
          slotMin: 8 * 60,
          status: MedicationSlotStatus.unknown,
          snapshotLabel:
              'Sehr langes Kombinationspräparat mit Mineralstoffen',
          snapshotDoseValue: 12.5,
          snapshotDoseUnit: 'Filmtabletten',
        ),
        ...day.entries.where(
          (e) => e.key == SyntheticOpenBandRepository.medicationFixturePlanBKey,
        ),
      ],
    );
    await mount(tester, width: 375, scale: 2, height: 1600);
    expect(find.text('Medikamente'), findsOneWidget);
    expect(
      find.text('Sehr langes Kombinationspräparat mit Mineralstoffen'),
      findsOneWidget,
    );
    expect(find.textContaining('12,5'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/medication-375-2x.png'),
    );
  }, tags: const ['golden']);

  testWidgets('keyboard inset keeps the editor usable', (tester) async {
    await mount(tester);
    await tester.tap(find.text('Medikament hinzufügen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('medication-name')));
    tester.view.viewInsets = const FakeViewPadding(bottom: 308);
    await tester.pumpAndSettle();
    expect(find.text('Medikament hinzufügen'), findsWidgets);
    expect(find.byKey(const ValueKey('medication-name')), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/medication-keyboard.png'),
    );
    tester.view.resetViewInsets();
  }, tags: const ['golden']);

  testWidgets('record large stacks the taken clock', (tester) async {
    await mount(tester, width: 375, scale: 2, height: 1800);
    await tester.tap(find.text('Präparat A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Genommen'));
    await tester.pumpAndSettle();
    expect(find.text('15. Sept. 2026'), findsOneWidget);
    expect(find.text('09:41'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/medication-record-large.png'),
    );
  }, tags: const ['golden']);

  testWidgets('editor large stacks quantity and unit', (tester) async {
    await mount(tester, width: 375, scale: 2, height: 1800);
    await tester.tap(find.text('Pläne verwalten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Präparat A'));
    await tester.pumpAndSettle();
    expect(find.text('Plan bearbeiten'), findsOneWidget);
    expect(find.text('Tablette'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/medication-editor-large.png'),
    );
  }, tags: const ['golden']);

  testWidgets('time editor keeps weekday rows', (tester) async {
    await mount(tester);
    await tester.tap(find.text('Pläne verwalten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Präparat A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('08:00'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('medication-time')), findsOneWidget);
    expect(find.text('Montag'), findsOneWidget);
    expect(find.text('Sonntag'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Speichern'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/medication-time.png'),
    );
    await mount(tester, brightness: Brightness.dark);
    await tester.tap(find.text('Pläne verwalten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Präparat A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('08:00'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('medication-time')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Speichern'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/medication-time-dark.png'),
    );
  }, tags: const ['golden']);

  testWidgets('time editor back discards unconfirmed weekday draft', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('Pläne verwalten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Präparat A'));
    await tester.pumpAndSettle();
    expect(find.text('Täglich'), findsOneWidget);
    await tester.tap(find.text('08:00'));
    await tester.pumpAndSettle();
    await tester.tap(weekdaySwitch('Sonntag'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('medication-time')), findsNothing);
    expect(find.text('Plan bearbeiten'), findsOneWidget);
    expect(find.text('Täglich'), findsOneWidget);
    expect(find.textContaining('Mo, Di'), findsNothing);
    expect(repo.planSaves, 0);
  });

  testWidgets('time editor Speichern updates parent draft only', (tester) async {
    await mount(tester);
    await tester.tap(find.text('Pläne verwalten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Präparat A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('08:00'));
    await tester.pumpAndSettle();
    await tester.tap(weekdaySwitch('Sonntag'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Speichern'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('medication-time')), findsNothing);
    expect(find.text('Plan bearbeiten'), findsOneWidget);
    expect(find.text('Täglich'), findsNothing);
    expect(find.text('Mo, Di, Mi, Do, Fr, Sa'), findsOneWidget);
    expect(repo.planSaves, 0);
  });

  testWidgets('time editor zero weekdays stays on screen', (tester) async {
    await mount(tester);
    await tester.tap(find.text('Pläne verwalten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Präparat A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('08:00'));
    await tester.pumpAndSettle();
    for (final day in [
      'Montag',
      'Dienstag',
      'Mittwoch',
      'Donnerstag',
      'Freitag',
      'Samstag',
      'Sonntag',
    ]) {
      await tester.ensureVisible(find.text(day));
      await tester.tap(weekdaySwitch(day));
      await tester.pump();
    }
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Speichern'));
    await tester.tap(find.widgetWithText(FilledButton, 'Speichern'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('medication-time')), findsOneWidget);
    expect(find.text('Mindestens ein Wochentag.'), findsOneWidget);
    expect(repo.planSaves, 0);
  });

  testWidgets('legacy unknown snapshot uses Paper copy', (tester) async {
    repo.transformDay = (day) => MedicationDay(
      day: day.day,
      entries: [
        MedicationDayEntry(
          key: 'legacy',
          date: '2026-08-20',
          slotMin: 8 * 60,
          status: MedicationSlotStatus.taken,
          takenAt: DateTime.utc(2026, 8, 20, 7, 35),
          snapshotLabel: null,
          snapshotDoseValue: null,
          snapshotDoseUnit: null,
          orphan: true,
        ),
      ],
    );
    await mount(tester);
    await tester.tap(find.text('Medikament'));
    await tester.pumpAndSettle();
    expect(find.text('Name und Menge nicht gespeichert'), findsOneWidget);
    expect(find.text('07:35 UTC'), findsOneWidget);
    expect(find.text('07:35'), findsNothing);
    expect(find.text('Zeitzone nicht gespeichert'), findsOneWidget);
    expect(find.text('Eintrag entfernen'), findsOneWidget);
    expect(find.text('Unbekannt'), findsNothing);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/medication-legacy-light.png'),
    );
  }, tags: const ['golden']);

  testWidgets('0.125 dose is not rounded by an unrelated edit', (tester) async {
    await mount(tester);
    await tester.tap(find.text('Medikament hinzufügen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('medication-name')), 'Zink');
    await tester.enterText(
      find.byKey(const ValueKey('medication-dose')),
      '0,125',
    );
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pläne verwalten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zink'));
    await tester.pumpAndSettle();
    final dose = tester.widget<TextField>(
      find.byKey(const ValueKey('medication-dose')),
    );
    expect(dose.controller!.text, '0,125');
    await tester.enterText(
      find.byKey(const ValueKey('medication-name')),
      'Zink plus',
    );
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    final stored = (await repo.readMedicationPlans(
      activeOnly: true,
    )).firstWhere((p) => p.name == 'Zink plus');
    expect(stored.doseValue, 0.125);
  });

  testWidgets('unchanged dose edit retains stored precision', (tester) async {
    const tiny = 1e-13;
    repo.transformPlans = (plans) => [
      for (final p in plans)
        if (p.name == 'Präparat A')
          MedicationPlan(
            key: p.key,
            name: p.name,
            doseValue: tiny,
            doseUnit: p.doseUnit,
            kind: p.kind,
            note: p.note,
            schedule: p.schedule,
            active: p.active,
            createdAtMs: p.createdAtMs,
            revisionId: p.revisionId,
            effectiveTs: p.effectiveTs,
            effectiveDate: p.effectiveDate,
            effectiveMin: p.effectiveMin,
            origin: p.origin,
            scheduleUnreadableCount: p.scheduleUnreadableCount,
          )
        else
          p,
    ];
    await mount(tester);
    await tester.tap(find.text('Pläne verwalten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Präparat A'));
    await tester.pumpAndSettle();
    final dose = tester.widget<TextField>(
      find.byKey(const ValueKey('medication-dose')),
    );
    expect(dose.controller!.text, isNot('0'));
    expect(dose.controller!.text.contains('e-'), isTrue);
    await tester.enterText(
      find.byKey(const ValueKey('medication-name')),
      'Präparat A2',
    );
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(repo.lastPlan!.doseValue, tiny);
    final stored = (await repo.readMedicationPlans(
      activeOnly: true,
    )).firstWhere((p) => p.key == SyntheticOpenBandRepository.medicationFixturePlanAKey);
    expect(stored.doseValue, tiny);
  });

  testWidgets('invalid nonempty dose is rejected before write', (tester) async {
    await mount(tester);
    await tester.tap(find.text('Medikament hinzufügen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('medication-name')), 'Zink');
    await tester.enterText(find.byKey(const ValueKey('medication-dose')), 'abc');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Menge ungültig'), findsOneWidget);
    expect(find.text('Medikament hinzufügen'), findsWidgets);
    expect(repo.planSaves, 0);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('medication-dose')),
    );
    expect(field.controller!.text, 'abc');
  });

  testWidgets('restart dirty is one save and failure keeps stored plan', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('Medikament hinzufügen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('medication-name')), 'Zink');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    final created = (await repo.readMedicationPlans(
      activeOnly: true,
    )).firstWhere((p) => p.name == 'Zink');
    await tester.tap(find.text('Pläne verwalten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zink'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('medication-name')),
      'Zink plus',
    );
    await tester.tap(find.text('Plan beenden'));
    await tester.pumpAndSettle();
    final endedEarly = (await repo.readMedicationPlans(
      activeOnly: false,
    )).firstWhere((p) => p.key == created.key);
    expect(endedEarly.active, isFalse);
    expect(endedEarly.name, 'Zink');
    await tester.tap(find.text('Beendete Pläne'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zink'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('medication-name')),
      'Zink plus',
    );
    final savesBefore = repo.planSaves;
    repo.failMedicationWrite = true;
    await tester.tap(find.widgetWithText(FilledButton, 'Plan fortsetzen'));
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(find.text('Plan fortsetzen'), findsWidgets);
    expect(repo.planSaves, savesBefore + 1);
    expect(repo.restarts, 0);
    final ended = (await repo.readMedicationPlans(
      activeOnly: false,
    )).firstWhere((p) => p.key == created.key);
    expect(ended.active, isFalse);
    expect(ended.name, 'Zink');
    final name = tester.widget<TextField>(
      find.byKey(const ValueKey('medication-name')),
    );
    expect(name.controller!.text, 'Zink plus');
    repo.failMedicationWrite = false;
    await tester.tap(find.widgetWithText(FilledButton, 'Plan fortsetzen'));
    await tester.pumpAndSettle();
    expect(repo.planSaves, savesBefore + 2);
    expect(repo.restarts, 0);
    final restarted = (await repo.readMedicationPlans(
      activeOnly: true,
    )).firstWhere((p) => p.key == created.key);
    expect(restarted.active, isTrue);
    expect(restarted.name, 'Zink plus');
  });

  testWidgets('empty note submits a string and clears the stored note', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('Präparat A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Genommen'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('medication-note')),
      'Mit Essen',
    );
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(repo.lastEntry!.note, 'Mit Essen');
    await tester.tap(find.text('Präparat A'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('medication-note')), '');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(repo.lastEntry!.note, '');
    await tester.tap(find.text('Präparat A'));
    await tester.pumpAndSettle();
    final note = tester.widget<TextField>(
      find.byKey(const ValueKey('medication-note')),
    );
    expect(note.controller!.text, '');
  });

  testWidgets('known offset shows original local clock', (tester) async {
    final instant = DateTime.utc(2026, 9, 15, 7, 35);
    repo.transformDay = (day) => MedicationDay(
      day: day.day,
      entries: [
        MedicationDayEntry(
          key: SyntheticOpenBandRepository.medicationFixturePlanAKey,
          date: day.day,
          slotMin: 8 * 60,
          status: MedicationSlotStatus.taken,
          takenAt: instant,
          takenUtcOffsetMinutes: 120,
          snapshotLabel: 'Präparat A',
          snapshotDoseValue: 1,
          snapshotDoseUnit: 'Tablette',
        ),
      ],
    );
    await mount(tester);
    expect(find.textContaining('Genommen 09:35'), findsOneWidget);
    expect(find.textContaining('UTC'), findsNothing);
    await tester.tap(find.text('Präparat A'));
    await tester.pumpAndSettle();
    expect(find.text('09:35'), findsOneWidget);
    expect(find.textContaining('UTC'), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('medication-taken-date'))).height,
      greaterThanOrEqualTo(44),
    );
  });

  test('DST gap 02:30 is refused from civil day plus HH:mm', () {
    expect(
      resolveMedicationTakenAt(
        year: 2026,
        month: 3,
        day: 29,
        hour: 2,
        minute: 30,
        zone: 'Europe/Berlin',
      ),
      isNull,
    );
    expect(
      resolveMedicationTakenAt(
        year: 2026,
        month: 3,
        day: 29,
        hour: 3,
        minute: 30,
        zone: 'Europe/Berlin',
      ),
      isNotNull,
    );
  });

  test('known offset reconstructs the original local clock', () {
    final shown = medicationTakenDisplay(
      MedicationDayEntry(
        key: 'k',
        date: '2026-08-20',
        slotMin: 8 * 60,
        status: MedicationSlotStatus.taken,
        takenAt: DateTime.utc(2026, 8, 20, 7, 35),
        takenUtcOffsetMinutes: 120,
      ),
    )!;
    expect(shown.hour, 9);
    expect(shown.minute, 35);
    expect(shown.day, 20);
    expect(shown.offsetUnknown, isFalse);
  });

  test('unknown offset does not treat current timezone as recorded truth', () {
    final shown = medicationTakenDisplay(
      MedicationDayEntry(
        key: 'k',
        date: '2026-08-20',
        slotMin: 8 * 60,
        status: MedicationSlotStatus.taken,
        takenAt: DateTime.utc(2026, 8, 20, 7, 35),
      ),
    )!;
    expect(shown.offsetUnknown, isTrue);
    expect(shown.hour, 7);
    expect(shown.minute, 35);
  });

  testWidgets('unknown offset clock is labelled UTC and save keeps instant', (
    tester,
  ) async {
    final instant = DateTime.utc(2026, 9, 15, 7, 35);
    repo.transformDay = (day) => MedicationDay(
      day: day.day,
      entries: [
        MedicationDayEntry(
          key: SyntheticOpenBandRepository.medicationFixturePlanAKey,
          date: day.day,
          slotMin: 8 * 60,
          status: MedicationSlotStatus.taken,
          takenAt: instant,
          snapshotLabel: 'Präparat A',
          snapshotDoseValue: 1,
          snapshotDoseUnit: 'Tablette',
        ),
      ],
    );
    await mount(tester);
    expect(find.textContaining('Genommen 07:35 UTC'), findsOneWidget);
    await tester.tap(find.text('Präparat A'));
    await tester.pumpAndSettle();
    expect(find.text('07:35 UTC'), findsOneWidget);
    expect(find.text('Zeitzone nicht gespeichert'), findsOneWidget);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(repo.lastEntry!.takenAt!.toUtc(), instant);
  });
}
