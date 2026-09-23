import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/openband/calendar.dart';
import 'package:openstrap_edge/openband/calendar_line.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/health.dart';
import 'package:openstrap_edge/openband/journal_value_editor.dart';
import 'package:openstrap_edge/openband/settings_controls.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/openband/weight.dart';

const _day = '2026-09-15';

IconButton _monthButton(WidgetTester tester, String tooltip) =>
    tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == tooltip,
      ),
    );

Finder _dayCell(String fragment) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics && _civilLabel(widget.properties.label, fragment),
);

bool _dayEnabled(WidgetTester tester, String fragment) =>
    tester.widget<Semantics>(_dayCell(fragment)).properties.enabled ?? false;

bool _todayRing(WidgetTester tester, String fragment) {
  final material = tester.widget<Material>(
    find.descendant(of: _dayCell(fragment), matching: find.byType(Material)),
  );
  return (material.shape! as RoundedRectangleBorder).side.width > 0;
}

bool _civilLabel(String? label, String fragment) {
  if (label == null) return false;
  final at = label.indexOf(fragment);
  if (at < 0) return false;
  if (at == 0) return true;
  final before = label.codeUnitAt(at - 1);
  return before < 0x30 || before > 0x39;
}

Map<String, dynamic> _fixture(String name) => Map<String, dynamic>.from(
  jsonDecode(File('docs/openband5/assets/fixtures/$name').readAsStringSync())
      as Map,
);

class _WeightUiRepository extends SyntheticOpenBandRepository {
  _WeightUiRepository()
    : super.fromMaps(
        _fixture('day-summary.json'),
        _fixture('sleep-detail.json'),
      );

  WeightHistory? forcedHistory;
  bool weightReadError = false;
  bool dayReadError = false;
  bool failHistoryAfterPatch = false;
  int patchCalls = 0;
  int weightReads = 0;
  final Map<int, Completer<WeightHistory>> pending = {};

  @override
  Future<WeightHistory> readWeightHistory(String endDay, int days) async {
    weightReads++;
    if (pending[days] case final wait?) return wait.future;
    if (weightReadError) throw StateError('weight read failed');
    if (forcedHistory case final history?) return history;
    return super.readWeightHistory(endDay, days);
  }

  @override
  Future<OpenBandDay> readDay(String day) {
    if (dayReadError) return Future.error(StateError('day read failed'));
    return super.readDay(day);
  }

  @override
  Future<void> patchJournalDay(JournalDayPatch patch) async {
    patchCalls++;
    await super.patchJournalDay(patch);
    if (failHistoryAfterPatch) weightReadError = true;
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

  late _WeightUiRepository repo;

  setUp(() => repo = _WeightUiRepository());

  Widget app({
    Brightness brightness = Brightness.light,
    double scale = 1,
    Size size = const Size(393, 852),
    Widget? home,
  }) => MaterialApp(
    locale: const Locale('de'),
    supportedLocales: const [Locale('de')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: openBandTheme(brightness).copyWith(platform: TargetPlatform.iOS),
    home: RepaintBoundary(
      key: const ValueKey('capture'),
      child: MediaQuery(
        data: MediaQueryData(
          size: size,
          devicePixelRatio: 1,
          padding: const EdgeInsets.only(top: 59, bottom: 34),
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child:
            home ??
            OpenBandWeight(
              key: UniqueKey(),
              repository: repo,
              endDay: _day,
              now: () => DateTime(2026, 9, 15, 9, 41),
            ),
      ),
    ),
  );

  Future<void> mount(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double scale = 1,
    Size size = const Size(393, 852),
    Widget? home,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(brightness: brightness, scale: scale, size: size, home: home),
    );
    await tester.pumpAndSettle();
  }

  Future<OpenBandController> mountHealth(WidgetTester tester) async {
    final controller = OpenBandController(
      repository: repo,
      initialDay: _day,
      now: () => DateTime(2026, 9, 15, 9, 41),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    await mount(
      tester,
      home: Scaffold(
        body: SafeArea(child: OpenBandHealth(controller: controller)),
      ),
    );
    await tester.scrollUntilVisible(find.text('Gewicht'), 200);
    return controller;
  }

  Future<void> openLatest(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('weight-latest-edit')));
    await tester.pumpAndSettle();
    expect(find.byType(OBJournalValueSheet), findsOneWidget);
  }

  group('dated weight behavior', () {
    testWidgets('renders actual dated fixture, gaps and shared controls', (
      tester,
    ) async {
      repo.seedWeightHistory();
      await mount(tester);
      expect(find.text('75,0'), findsOneWidget);
      expect(find.text('Journal · 15. Sept.'), findsOneWidget);
      expect(find.byType(OBSegmented), findsOneWidget);
      expect(find.byType(OBCalendarLine), findsOneWidget);
      final line = tester.widget<OBCalendarLine>(find.byType(OBCalendarLine));
      expect(line.values, hasLength(7));
      expect(line.values.whereType<double>(), hasLength(7));
      expect(find.byKey(const ValueKey('weight-add')), findsOneWidget);
      expect(find.text('15. September'), findsOneWidget);
      await tester.tap(find.byTooltip('Über Gewicht'));
      await tester.pumpAndSettle();
      expect(find.text('Quelle: Journal · eingegebene Werte'), findsOneWidget);
      expect(find.textContaining('7 Tagen Halbwertszeit'), findsOneWidget);
    });

    testWidgets('Health shows the dated Journal row before Labor', (
      tester,
    ) async {
      repo.seedWeightHistory();
      await mountHealth(tester);
      expect(find.text('Gewicht'), findsOneWidget);
      expect(find.text('Journal · 15. Sept.'), findsOneWidget);
      expect(find.text('75,0 kg'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Laborwerte'), 100);
      expect(
        tester.getTopLeft(find.text('Gewicht')).dy,
        lessThan(tester.getTopLeft(find.text('Laborwerte')).dy),
      );
    });

    testWidgets('Health route edit refreshes the row after returning', (
      tester,
    ) async {
      repo.seedWeightHistory();
      await mountHealth(tester);
      await tester.tap(find.widgetWithText(OBSettingsValueRow, 'Gewicht'));
      await tester.pumpAndSettle();
      expect(find.byType(OpenBandWeight), findsOneWidget);
      await openLatest(tester);
      await tester.enterText(
        find.byKey(const ValueKey('journal-value')),
        '74,8',
      );
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Zurück'));
      await tester.pumpAndSettle();
      final row = find.widgetWithText(OBSettingsValueRow, 'Gewicht');
      expect(
        find.descendant(of: row, matching: find.text('74,8 kg')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('Journal · 15. Sept.')),
        findsOneWidget,
      );
    });

    testWidgets('Health return clears stale data while pending', (
      tester,
    ) async {
      repo.seedWeightHistory();
      await mountHealth(tester);
      final row = find.widgetWithText(OBSettingsValueRow, 'Gewicht');

      await tester.tap(row);
      await tester.pumpAndSettle();
      final pending = Completer<WeightHistory>();
      repo.pending[7] = pending;
      await tester.tap(find.byTooltip('Zurück'));
      await tester.pump();
      expect(
        find.descendant(of: row, matching: find.text('75,0 kg')),
        findsNothing,
      );
      expect(
        find.descendant(of: row, matching: find.text('—')),
        findsOneWidget,
      );
      pending.complete(await _superHistory(repo, 7));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: row, matching: find.text('75,0 kg')),
        findsOneWidget,
      );
    });

    testWidgets(
      'Health observes an immediate return-read failure before its next frame',
      (tester) async {
        repo.seedWeightHistory();
        await mountHealth(tester);
        final row = find.widgetWithText(OBSettingsValueRow, 'Gewicht');
        await tester.tap(row);
        await tester.pumpAndSettle();
        repo.weightReadError = true;
        await tester.tap(find.byTooltip('Zurück'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.descendant(of: row, matching: find.text('75,0 kg')),
          findsNothing,
        );
        expect(
          find.descendant(
            of: row,
            matching: find.text('Journal · Laden fehlgeschlagen'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: row, matching: find.text('—')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Health refresh token reloads weight and withholds stale data when day refresh fails',
      (tester) async {
        repo.seedWeightHistory();
        final controller = await mountHealth(tester);
        final row = find.widgetWithText(OBSettingsValueRow, 'Gewicht');
        expect(
          find.descendant(of: row, matching: find.text('75,0 kg')),
          findsOneWidget,
        );
        final readsBeforeBandUpdate = repo.weightReads;
        controller.updateBand(controller.band);
        await tester.pump();
        expect(repo.weightReads, readsBeforeBandUpdate);

        final base = await repo.readJournalDay(_day);
        await repo.patchJournalDay(
          JournalDayPatch.fromBase(
            base,
            metrics: {kWeightJournalField: const JournalMetricValue(74.4)},
          ),
        );
        final pending = Completer<WeightHistory>();
        repo.pending[7] = pending;
        repo.dayReadError = true;

        final refresh = controller.refresh();
        await tester.pump();
        expect(
          find.descendant(of: row, matching: find.text('75,0 kg')),
          findsNothing,
        );
        expect(
          find.descendant(of: row, matching: find.text('—')),
          findsOneWidget,
        );

        pending.complete(await _superHistory(repo, 7));
        await refresh;
        await tester.pumpAndSettle();
        expect(controller.loadError, isNotNull);
        expect(
          find.descendant(of: row, matching: find.text('74,4 kg')),
          findsOneWidget,
        );
      },
    );

    testWidgets('empty and read error are distinct and retryable', (
      tester,
    ) async {
      await mount(tester);
      expect(find.text('Noch keine Einträge'), findsOneWidget);
      expect(find.text('Eintragen'), findsOneWidget);
      expect(find.byType(OBSegmented), findsNothing);

      repo.weightReadError = true;
      await mount(tester);
      expect(
        find.text('Einträge konnten nicht geladen werden.'),
        findsOneWidget,
      );
      expect(find.text('Noch keine Einträge'), findsNothing);
      repo.weightReadError = false;
      await tester.tap(find.text('Erneut'));
      await tester.pumpAndSettle();
      expect(find.text('Noch keine Einträge'), findsOneWidget);
    });

    testWidgets(
      'corrupt-only stays honest and offers entry without history UI',
      (tester) async {
        repo.forcedHistory = const WeightHistory(
          endDay: _day,
          days: 7,
          entries: [],
          trend: [null, null, null, null, null, null, null],
          unreadableCount: 2,
        );
        await mount(tester);
        expect(find.text('—'), findsOneWidget);
        expect(find.text('Einträge nicht lesbar'), findsOneWidget);
        expect(find.text('Eintragen'), findsOneWidget);
        expect(find.byType(OBSegmented), findsNothing);
        expect(find.byType(OBCalendarLine), findsNothing);
        expect(find.text('Einträge'), findsNothing);
      },
    );

    testWidgets('partial status is compact and details use shared info sheet', (
      tester,
    ) async {
      repo.forcedHistory = const WeightHistory(
        endDay: _day,
        days: 7,
        entries: [WeightEntry(day: _day, value: 401)],
        latest: WeightEntry(day: _day, value: 401),
        trend: [null, null, null, null, null, null, null],
        unreadableCount: 1,
        invalidCount: 1,
      );
      await mount(tester);
      expect(
        find.text('1 Wert ausgeschlossen · 1 Eintrag unlesbar'),
        findsOneWidget,
      );
      expect(find.text('Vom Trend ausgeschlossen'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('weight-partial-info')));
      await tester.pumpAndSettle();
      expect(find.text('Hinweise zu den Einträgen'), findsOneWidget);
      expect(find.textContaining('gültigen Bereichs'), findsOneWidget);
    });

    testWidgets(
      'latest outside window remains editable and add stays exposed',
      (tester) async {
        repo.seedWeightHistory(
          dates: const ['2026-08-01'],
          enteredKg: const [77],
        );
        await mount(tester);
        expect(find.text('Journal · 1. Aug.'), findsOneWidget);
        expect(find.byKey(const ValueKey('weight-add')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('weight-entry-2026-08-01')),
          findsNothing,
        );
        await openLatest(tester);
        expect(
          find.descendant(
            of: find.byType(OBJournalValueSheet),
            matching: find.text('1. August'),
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('journal-value')))
              .controller!
              .text,
          '77',
        );
      },
    );

    testWidgets('edit and remove use fixed date, raw text and one CAS write', (
      tester,
    ) async {
      repo.seedWeightHistory();
      await mount(tester);
      await openLatest(tester);
      final field = find.byKey(const ValueKey('journal-value'));
      expect(tester.widget<TextField>(field).controller!.text, '75');
      expect(
        find.descendant(
          of: find.byType(OBJournalValueSheet),
          matching: find.text('15. September'),
        ),
        findsOneWidget,
      );
      await tester.enterText(field, '74,8');
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(repo.patchCalls, 1);
      expect((await repo.readWeightHistory(_day, 7)).latest?.value, 74.8);

      await openLatest(tester);
      await tester.tap(find.text('Wert entfernen'));
      await tester.pumpAndSettle();
      expect(repo.patchCalls, 2);
      expect((await repo.readWeightHistory(_day, 7)).latest?.day, '2026-09-14');
    });

    testWidgets('weight edit preserves note, tags and unrelated metrics', (
      tester,
    ) async {
      final empty = await repo.readJournalDay(_day);
      await repo.patchJournalDay(
        JournalDayPatch.fromBase(
          empty,
          metrics: const {
            'weight_kg': JournalMetricValue(75),
            'mood': JournalMetricValue(4),
          },
          note: 'Abend',
          tags: const ['Spaziergang'],
        ),
      );
      repo.patchCalls = 0;
      await mount(tester);
      await openLatest(tester);
      await tester.enterText(
        find.byKey(const ValueKey('journal-value')),
        '74,9',
      );
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      final saved = await repo.readJournalDay(_day);
      expect(saved.note, 'Abend');
      expect(saved.tags, ['Spaziergang']);
      expect(saved.metrics['mood']?.value, 4);
      expect(saved.metrics['weight_kg']?.value, 74.9);
      expect(repo.patchCalls, 1);
    });

    testWidgets('new entry starts blank and hides remove action', (
      tester,
    ) async {
      await mount(tester);
      await tester.tap(find.text('Eintragen'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsNothing);
      expect(find.byType(OBCalendar), findsOneWidget);
      expect(find.text('DATUM'), findsOneWidget);
      expect(find.text('Synthetische Daten'), findsNothing);
      final calendar = tester.widget<OBCalendar>(find.byType(OBCalendar));
      expect(calendar.allowFuture, isFalse);
      expect(calendar.now, DateTime(2026, 9, 15, 9, 41));
      expect(calendar.lastDate, DateTime(2026, 9, 15));
      expect(calendar.selected, DateTime(2026, 9, 15));
      expect(
        tester.widget<OBCard>(find.byType(OBCard)).padding,
        const EdgeInsets.fromLTRB(10, 14, 10, 10),
      );
      expect(find.text('15. September übernehmen'), findsOneWidget);
      await tester.tap(find.text('15. September übernehmen'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('journal-value'));
      expect(tester.widget<TextField>(field).controller!.text, '');
      expect(find.text('Wert entfernen'), findsNothing);
    });

    testWidgets('future and end day stay closed on the canonical calendar', (
      tester,
    ) async {
      await mount(tester);
      await tester.tap(find.text('Eintragen'));
      await tester.pumpAndSettle();
      expect(_dayEnabled(tester, '16. September 2026'), isFalse);
      expect(_monthButton(tester, 'Nächster Monat').onPressed, isNull);
      await tester.tap(find.byTooltip('Vorheriger Monat'));
      await tester.pumpAndSettle();
      expect(find.text('August 2026'), findsOneWidget);
      expect(_monthButton(tester, 'Nächster Monat').onPressed, isNotNull);
      await tester.tap(find.byTooltip('Nächster Monat'));
      await tester.pumpAndSettle();
      expect(find.text('September 2026'), findsOneWidget);
      expect(_monthButton(tester, 'Nächster Monat').onPressed, isNull);
    });

    testWidgets('historical end day is a cap and is not labeled today', (
      tester,
    ) async {
      await mount(
        tester,
        home: OpenBandWeight(
          repository: repo,
          endDay: '2025-09-15',
          now: () => DateTime(2026, 9, 15, 9, 41),
        ),
      );
      await tester.tap(find.text('Eintragen'));
      await tester.pumpAndSettle();
      final calendar = tester.widget<OBCalendar>(find.byType(OBCalendar));
      expect(calendar.now, DateTime(2026, 9, 15, 9, 41));
      expect(calendar.lastDate, DateTime(2025, 9, 15));
      expect(calendar.month, DateTime(2025, 9));
      expect(find.text('Heute'), findsNothing);
      await tester.tap(find.text('10'));
      await tester.pumpAndSettle();
      expect(_todayRing(tester, '15. September 2025'), isFalse);
      expect(_dayEnabled(tester, '16. September 2025'), isFalse);
      expect(_monthButton(tester, 'Nächster Monat').onPressed, isNull);
      expect(find.text('10. September übernehmen'), findsOneWidget);
    });

    testWidgets('a month more than 20 years ago stays reachable', (
      tester,
    ) async {
      await mount(
        tester,
        home: OpenBandWeight(
          repository: repo,
          endDay: '2000-06-15',
          now: () => DateTime(2026, 9, 15, 9, 41),
        ),
      );
      await tester.tap(find.text('Eintragen'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<OBCalendar>(find.byType(OBCalendar)).month,
        DateTime(2000, 6),
      );
      expect(_monthButton(tester, 'Vorheriger Monat').onPressed, isNotNull);
    });

    testWidgets('previous month stops at January of year 1', (tester) async {
      await mount(
        tester,
        home: OpenBandWeight(
          repository: repo,
          endDay: '0001-02-15',
          now: () => DateTime(2026, 9, 15, 9, 41),
        ),
      );
      await tester.tap(find.text('Eintragen'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<OBCalendar>(find.byType(OBCalendar)).month,
        DateTime(1, 2),
      );
      expect(_monthButton(tester, 'Vorheriger Monat').onPressed, isNotNull);
      await tester.tap(find.byTooltip('Vorheriger Monat'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<OBCalendar>(find.byType(OBCalendar)).month,
        DateTime(1, 1),
      );
      expect(_monthButton(tester, 'Vorheriger Monat').onPressed, isNull);
      expect(_monthButton(tester, 'Nächster Monat').onPressed, isNotNull);
    });

    testWidgets('cancelling the date page writes nothing', (tester) async {
      await mount(tester);
      await tester.tap(find.text('Eintragen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Zurück'));
      await tester.pumpAndSettle();
      expect(find.byType(OBJournalValueSheet), findsNothing);
      expect(find.byType(OpenBandWeight), findsOneWidget);
      expect(repo.patchCalls, 0);
      expect((await repo.readJournalDay(_day)).metrics['weight_kg'], isNull);
      expect(
        (await repo.readJournalDay('2026-09-10')).metrics['weight_kg'],
        isNull,
      );
    });

    testWidgets('confirming a past day opens that fixed day editor', (
      tester,
    ) async {
      await mount(tester);
      await tester.tap(find.text('Eintragen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10. September übernehmen'));
      await tester.pumpAndSettle();
      expect(find.byType(OBJournalValueSheet), findsOneWidget);
      expect(find.text('10. September'), findsOneWidget);
      expect(find.text('Wert entfernen'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('journal-value')),
        '70,5',
      );
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(
        (await repo.readJournalDay('2026-09-10')).metrics['weight_kg']?.value,
        70.5,
      );
      expect((await repo.readJournalDay(_day)).metrics['weight_kg'], isNull);
      expect(repo.patchCalls, 1);
    });

    testWidgets('375px at 2x can reach the date confirmation', (tester) async {
      await mount(tester, scale: 2, size: const Size(375, 812));
      await tester.tap(find.text('Eintragen'));
      await tester.pumpAndSettle();
      final action = find.text('15. September übernehmen');
      await tester.scrollUntilVisible(action, 200);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final rect = tester.getRect(action);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(812));
    });

    testWidgets('closing a conflict reloads the winning external value', (
      tester,
    ) async {
      repo.seedWeightHistory();
      await mount(tester);
      await openLatest(tester);
      final field = find.byKey(const ValueKey('journal-value'));
      await tester.enterText(field, '74,5');
      final concurrent = await repo.readJournalDay(_day);
      await repo.patchJournalDay(
        JournalDayPatch.fromBase(
          concurrent,
          metrics: const {'weight_kg': JournalMetricValue(76)},
        ),
      );
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(find.text('Eintrag wurde geändert'), findsOneWidget);
      expect(tester.widget<TextField>(field).controller!.text, '74,5');
      final writesAtConflict = repo.patchCalls;

      await tester.tap(find.byTooltip('Schließen'));
      await tester.pumpAndSettle();
      expect(find.byType(OBJournalValueSheet), findsNothing);
      expect(find.text('76,0'), findsOneWidget);
      expect(find.text('75,0'), findsNothing);
      expect(repo.patchCalls, writesAtConflict);
    });

    testWidgets(
      'conflict retains draft and close after reload refreshes page',
      (tester) async {
        repo.seedWeightHistory();
        await mount(tester);
        await openLatest(tester);
        final field = find.byKey(const ValueKey('journal-value'));
        await tester.enterText(field, '74,5');
        final concurrent = await repo.readJournalDay(_day);
        await repo.patchJournalDay(
          JournalDayPatch.fromBase(
            concurrent,
            metrics: const {'weight_kg': JournalMetricValue(76)},
          ),
        );
        await tester.tap(find.text('Speichern'));
        await tester.pumpAndSettle();
        expect(find.text('Eintrag wurde geändert'), findsOneWidget);
        expect(tester.widget<TextField>(field).controller!.text, '74,5');
        await tester.tap(find.text('Neu laden'));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(field).controller!.text, '76');
        final writesAtConflict = repo.patchCalls;
        await tester.tap(find.byTooltip('Schließen'));
        await tester.pumpAndSettle();
        expect(find.text('76,0'), findsOneWidget);
        expect(find.text('75,0'), findsNothing);
        expect(repo.patchCalls, writesAtConflict);
      },
    );

    testWidgets('failed reload after closing conflict withholds stale page', (
      tester,
    ) async {
      repo.seedWeightHistory();
      await mount(tester);
      await openLatest(tester);
      final field = find.byKey(const ValueKey('journal-value'));
      await tester.enterText(field, '74,5');
      final concurrent = await repo.readJournalDay(_day);
      await repo.patchJournalDay(
        JournalDayPatch.fromBase(
          concurrent,
          metrics: const {'weight_kg': JournalMetricValue(76)},
        ),
      );
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      final writesAtConflict = repo.patchCalls;
      repo.weightReadError = true;

      await tester.tap(find.byTooltip('Schließen'));
      await tester.pumpAndSettle();
      expect(
        find.text('Einträge konnten nicht geladen werden.'),
        findsOneWidget,
      );
      expect(find.text('75,0'), findsNothing);
      expect(find.text('76,0'), findsNothing);
      expect(find.byType(OBCalendarLine), findsNothing);
      expect(repo.patchCalls, writesAtConflict);

      repo.weightReadError = false;
      await tester.tap(find.text('Erneut'));
      await tester.pumpAndSettle();
      expect(find.text('76,0'), findsOneWidget);
      expect(repo.patchCalls, writesAtConflict);
    });

    testWidgets('save failure retains draft and offers a real retry', (
      tester,
    ) async {
      repo.seedWeightHistory();
      await mount(tester);
      await openLatest(tester);
      final field = find.byKey(const ValueKey('journal-value'));
      await tester.enterText(field, '74,6');
      repo.failJournalPatch = true;
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
      expect(find.text('Erneut versuchen'), findsOneWidget);
      expect(tester.widget<TextField>(field).controller!.text, '74,6');
      repo.failJournalPatch = false;
      await tester.tap(find.text('Erneut versuchen'));
      await tester.pumpAndSettle();
      expect((await repo.readWeightHistory(_day, 7)).latest?.value, 74.6);
    });

    testWidgets('durable save and refresh failure do not duplicate the write', (
      tester,
    ) async {
      repo.seedWeightHistory();
      repo.failHistoryAfterPatch = true;
      await mount(tester);
      await openLatest(tester);
      await tester.enterText(
        find.byKey(const ValueKey('journal-value')),
        '74,7',
      );
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(
        find.text('Gespeichert. Verlauf konnte nicht aktualisiert werden.'),
        findsOneWidget,
      );
      expect(find.byType(OBCalendarLine), findsNothing);
      expect(find.text('Verlauf nicht verfügbar'), findsNothing);
      expect(find.text('Noch keine Einträge'), findsNothing);
      expect(find.text('74,7'), findsNothing);
      expect(find.text('75,0'), findsNothing);
      expect(find.text('—'), findsOneWidget);
      expect(repo.patchCalls, 1);
      await tester.tap(find.text('Erneut'));
      await tester.pumpAndSettle();
      expect(
        find.text('Gespeichert. Verlauf konnte nicht aktualisiert werden.'),
        findsOneWidget,
      );
      expect(repo.patchCalls, 1);
      repo.weightReadError = false;
      repo.failHistoryAfterPatch = false;
      await tester.tap(find.text('Erneut'));
      await tester.pumpAndSettle();
      expect(repo.patchCalls, 1);
      expect(find.text('74,7'), findsOneWidget);
    });

    testWidgets('remove plus refresh failure keeps prior history unknown', (
      tester,
    ) async {
      repo.seedWeightHistory();
      await mount(tester);
      await openLatest(tester);
      repo.failHistoryAfterPatch = true;
      await tester.tap(find.text('Wert entfernen'));
      await tester.pumpAndSettle();
      expect(find.text('Verlauf nicht verfügbar'), findsNothing);
      expect(find.text('Noch keine Einträge'), findsNothing);
      expect(find.text('75,0'), findsNothing);
      expect(find.text('—'), findsOneWidget);
      expect(
        find.text('Gespeichert. Verlauf konnte nicht aktualisiert werden.'),
        findsOneWidget,
      );
      expect(repo.patchCalls, 1);
    });

    testWidgets('period changes withhold old curve and ignore stale result', (
      tester,
    ) async {
      repo.seedWeightHistory();
      await mount(tester);
      final thirty = Completer<WeightHistory>();
      final ninety = Completer<WeightHistory>();
      repo.pending[30] = thirty;
      repo.pending[90] = ninety;
      await tester.tap(find.text('30 Tage'));
      await tester.pump();
      expect(find.byType(OBCalendarLine), findsNothing);
      await tester.tap(find.text('90 Tage'));
      await tester.pump();
      expect(find.byType(OBCalendarLine), findsNothing);
      ninety.complete(await _superHistory(repo, 90));
      await tester.pumpAndSettle();
      expect(
        tester.widget<OBCalendarLine>(find.byType(OBCalendarLine)).days,
        90,
      );
      thirty.complete(await _superHistory(repo, 30));
      await tester.pumpAndSettle();
      expect(
        tester.widget<OBCalendarLine>(find.byType(OBCalendarLine)).days,
        90,
      );
    });

    testWidgets('375px at 2x stacks chart heading and entry content', (
      tester,
    ) async {
      repo.seedWeightHistory();
      await mount(tester, scale: 2, size: const Size(375, 1200));
      expect(tester.takeException(), isNull);
      final trend = tester.getRect(find.text('Trend'));
      final count = tester.getRect(find.text('7 Einträge').first);
      expect(count.top, greaterThanOrEqualTo(trend.bottom));
      final date = tester.getRect(find.text('15. September'));
      final value = tester.getRect(find.text('75,0 kg').first);
      expect(value.top, greaterThanOrEqualTo(date.bottom));
    });

    testWidgets('375px at 2x wraps prior-year chart dates', (tester) async {
      repo.seedWeightHistory(
        dates: const [
          '2025-09-09',
          '2025-09-10',
          '2025-09-11',
          '2025-09-12',
          '2025-09-13',
          '2025-09-14',
          '2025-09-15',
        ],
        enteredKg: const [76.2, 76.0, 75.8, 75.7, 75.5, 75.3, 75.1],
      );
      await mount(
        tester,
        scale: 2,
        size: const Size(375, 1200),
        home: OpenBandWeight(
          repository: repo,
          endDay: '2025-09-15',
          now: () => DateTime(2026, 9, 15, 9, 41),
        ),
      );
      expect(find.text('9. Sept. 2025'), findsOneWidget);
      expect(find.text('15. Sept. 2025'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('375px at 2x wraps a broad finite stored weight', (
      tester,
    ) async {
      repo.seedWeightHistory(
        dates: const [_day],
        enteredKg: const [1234567890.1],
      );
      await mount(tester, scale: 2, size: const Size(375, 1200));
      expect(find.text('1.234.567.890,1'), findsOneWidget);
      expect(find.text('Vom Trend ausgeschlossen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('320px normal text has no overflow', (tester) async {
      repo.seedWeightHistory();
      await mount(tester, size: const Size(320, 900));
      expect(tester.takeException(), isNull);
      expect(find.byType(OBCalendarLine), findsOneWidget);
    });

    testWidgets('Paper weight variants match goldens', (tester) async {
      Future<void> capture(String name) => expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/$name.png'),
      );

      repo.seedWeightHistory();
      await mount(tester);
      await capture('weight-light');

      await mount(tester, brightness: Brightness.dark);
      await capture('weight-dark');

      repo = _WeightUiRepository();
      await mount(tester);
      await capture('weight-empty');

      repo = _WeightUiRepository();
      repo.seedWeightHistory(
        dates: const [_day],
        enteredKg: const [double.nan],
      );
      await mount(tester, brightness: Brightness.dark);
      await capture('weight-unreadable-dark');

      repo = _WeightUiRepository()..seedWeightHistory();
      await mount(tester, scale: 2, size: const Size(375, 1200));
      await capture('weight-375-2x-top');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('weight-entry-2026-09-09')),
        250,
      );
      await tester.pumpAndSettle();
      await capture('weight-375-2x-entries');
    });
  });

  testWidgets('dark theme keeps the Paper card and canvas roles', (
    tester,
  ) async {
    repo.seedWeightHistory();
    await mount(tester, brightness: Brightness.dark);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, const OB(true).canvas);
    expect(find.text('Journal · 15. Sept.'), findsOneWidget);
    expect(find.byType(OBCalendarLine), findsOneWidget);
  });
}

Future<WeightHistory> _superHistory(_WeightUiRepository repo, int days) async {
  repo.pending.remove(days);
  return repo.readWeightHistory(_day, days);
}
