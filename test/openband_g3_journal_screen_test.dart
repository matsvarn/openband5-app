import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/g3/screens/journal_screen.dart';
import 'package:openstrap_edge/openband/g3/journal_parts.dart'
    show OBCheckIn, OBPatternCard, OBPatternDotPlot, OBSwitch;
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';

SyntheticOpenBandRepository _repo() => SyntheticOpenBandRepository.fromMaps(
  jsonDecode(
        File(
          'docs/openband5/assets/fixtures/day-summary.json',
        ).readAsStringSync(),
      )
      as Map,
  jsonDecode(
        File(
          'docs/openband5/assets/fixtures/sleep-detail.json',
        ).readAsStringSync(),
      )
      as Map,
)..failCaffeineSleepPattern = true;

class _ReadFailsAfterWrite extends SyntheticOpenBandRepository {
  _ReadFailsAfterWrite()
    : super.fromMaps(
        jsonDecode(
              File(
                'docs/openband5/assets/fixtures/day-summary.json',
              ).readAsStringSync(),
            )
            as Map,
        jsonDecode(
              File(
                'docs/openband5/assets/fixtures/sleep-detail.json',
              ).readAsStringSync(),
            )
            as Map,
      );

  @override
  Future<void> patchJournalDay(JournalDayPatch patch) async {
    await super.patchJournalDay(patch);
    failJournalRead = true;
  }
}

class _PatternRepository extends SyntheticOpenBandRepository {
  _PatternRepository()
    : super.fromMaps(
        jsonDecode(
              File(
                'docs/openband5/assets/fixtures/day-summary.json',
              ).readAsStringSync(),
            )
            as Map,
        jsonDecode(
              File(
                'docs/openband5/assets/fixtures/sleep-detail.json',
              ).readAsStringSync(),
            )
            as Map,
      );

  Completer<G3JournalPattern>? pending;
  bool failPattern = false;
  bool partialPattern = false;

  @override
  Future<G3JournalPattern> readJournalPattern(String endDay, int nights) async {
    if (pending case final wait?) return wait.future;
    if (failPattern) throw StateError('pattern read failed');
    return G3JournalPattern(
      CaffeineSleepPattern(
        kind: CaffeineSleepPatternKind.meaningful,
        pairedN: 12,
        yesNights: 5,
        noNights: 7,
        delta: 4,
        endDay: endDay,
        startDay: '2026-08-17',
        nights: nights,
        algoVersion: 1,
        partial: partialPattern,
      ),
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
  late SyntheticOpenBandRepository repo;
  late OpenBandController controller;
  setUp(() {
    repo = _repo();
    controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-15',
      now: () => DateTime(2026, 9, 15),
    );
  });
  tearDown(() => controller.dispose());

  Future<void> mount(WidgetTester tester, {bool settle = true}) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(
          Brightness.light,
        ).copyWith(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: G3JournalScreen(controller: controller, onEdit: (_) {}),
        ),
      ),
    );
    await tester.pump();
    if (!settle) return;
    await tester.pumpAndSettle();
    final pending = repo.caffeineSleepPatternPending;
    if (pending != null) {
      await tester.runAsync(() async {
        try {
          await pending;
        } on Object {
          // The screen renders the repository failure.
        }
      });
    }
    await tester.pumpAndSettle();
  }

  testWidgets('Journal remains usable at 320 pt with larger text', (
    tester,
  ) async {
    await mount(tester);
    tester.view.physicalSize = const Size(320, 852);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Gestern Abend Alkohol?'), findsOneWidget);
  });

  testWidgets(
    'missing answers stay open and a saved answer advances the check-in',
    (tester) async {
      await mount(tester);
      expect(find.text('Gestern Abend Alkohol?'), findsOneWidget);
      expect(
        find.text('Noch nichts beantwortet. Auslassen kostet nichts.'),
        findsOneWidget,
      );
      expect(
        (await repo.readJournalDay('2026-09-14')).metrics['alcohol_evening'],
        isNull,
      );
      await tester.tap(find.text('Ja').first);
      await tester.pumpAndSettle();
      expect(
        (await repo.readJournalDay(
          '2026-09-14',
        )).metrics['alcohol_evening']?.value,
        1,
      );
      expect(find.text('Gestern nach 14 Uhr Koffein?'), findsOneWidget);
      expect(find.text('2 von 4'), findsOneWidget);
    },
  );

  testWidgets('Journal uses typed open order and answered-count progress', (
    tester,
  ) async {
    repo.seedJournalEditor(
      day: '2026-09-15',
      metrics: {'mood': const JournalMetricValue(4)},
    );
    await mount(tester);
    expect(find.text('Gestern Abend Alkohol?'), findsOneWidget);
    expect(find.text('2 von 4'), findsOneWidget);
    await tester.tap(find.text('Später'));
    await tester.pumpAndSettle();
    expect(find.text('Gestern nach 14 Uhr Koffein?'), findsOneWidget);
    expect(find.text('2 von 4'), findsOneWidget);
    await tester.tap(find.text('Ja').first);
    await tester.pumpAndSettle();
    expect(find.text('Noch etwas zu gestern?'), findsOneWidget);
    expect(find.text('3 von 4'), findsOneWidget);
  });

  testWidgets('dark check-in separates done, current, and future segments', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.dark),
        home: Scaffold(
          body: OBCheckIn(
            title: 'Frage',
            index: 2,
            total: 4,
            answer: const SizedBox.shrink(),
            onLater: () {},
          ),
        ),
      ),
    );
    final segments = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(OBCheckIn),
            matching: find.byType(Container),
          ),
        )
        .where((widget) => widget.constraints?.minHeight == 4)
        .toList();
    expect(segments, hasLength(4));
    final colors = [
      for (final segment in segments)
        (segment.decoration! as BoxDecoration).color!,
    ];
    expect(
      colors[0].computeLuminance(),
      greaterThan(colors[1].computeLuminance()),
    );
    expect(colors[1].a, 1);
    expect(
      colors[1].computeLuminance(),
      greaterThan(colors[2].computeLuminance() + .2),
    );
    expect(colors[2], colors[3]);
  });

  testWidgets('today caffeine answer belongs to yesterday', (tester) async {
    repo.seedJournalEditor(
      day: '2026-09-14',
      metrics: {'alcohol_evening': const JournalMetricValue(0)},
    );
    await mount(tester);
    expect(find.text('Gestern nach 14 Uhr Koffein?'), findsOneWidget);
    await tester.tap(find.text('Ja').first);
    await tester.pumpAndSettle();
    expect(
      (await repo.readJournalDay('2026-09-14')).metrics['caffeine_late']?.value,
      1,
    );
    expect(
      (await repo.readJournalDay('2026-09-15')).metrics['caffeine_late'],
      isNull,
    );
  });

  testWidgets('a past check-in shows and writes each question target day', (
    tester,
  ) async {
    controller.dispose();
    controller = OpenBandController(
      repository: repo,
      initialDay: '2026-03-01',
      now: () => DateTime(2026, 3, 2),
    );
    await mount(tester);
    expect(find.text('SO 01.03'), findsOneWidget);
    expect(find.text('Alkohol am Sa 28.02?'), findsOneWidget);
    await tester.tap(find.text('Ja').first);
    await tester.pumpAndSettle();
    expect(
      (await repo.readJournalDay(
        '2026-02-28',
      )).metrics['alcohol_evening']?.value,
      1,
    );
    expect(
      (await repo.readJournalDay('2026-03-01')).metrics['alcohol_evening'],
      isNull,
    );
    await tester.tap(find.text('Später'));
    await tester.pumpAndSettle();
    expect(find.text('Wie war deine Stimmung am So 01.03?'), findsOneWidget);
    await tester.tap(find.text('4').first);
    await tester.pumpAndSettle();
    expect((await repo.readJournalDay('2026-03-01')).metrics['mood']?.value, 4);
    expect((await repo.readJournalDay('2026-02-28')).metrics['mood'], isNull);
    expect(find.text('Notiz zu Sa 28.02?'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Vorheriger Abend');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect((await repo.readJournalDay('2026-02-28')).note, 'Vorheriger Abend');
    expect((await repo.readJournalDay('2026-03-01')).note, isEmpty);
  });

  testWidgets('failed save retains the chosen answer and can retry', (
    tester,
  ) async {
    repo.failJournalPatch = true;
    await mount(tester);
    await tester.tap(find.text('Nein').first);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Deine Auswahl bleibt erhalten'),
      findsOneWidget,
    );
    expect(
      (await repo.readJournalDay('2026-09-14')).metrics['alcohol_evening'],
      isNull,
    );
    repo.failJournalPatch = false;
    await tester.tap(find.text('Erneut speichern'));
    await tester.pumpAndSettle();
    expect(
      (await repo.readJournalDay(
        '2026-09-14',
      )).metrics['alcohol_evening']?.value,
      0,
    );
  });

  testWidgets('changing day during a save leaves the new day writable', (
    tester,
  ) async {
    final barrier = Completer<void>();
    repo.journalPatchBarrier = barrier.future;
    await mount(tester);
    await tester.tap(find.text('Nein').first);
    await tester.pump();
    unawaited(controller.selectDay('2026-09-14'));
    await tester.pump();
    barrier.complete();
    repo.journalPatchBarrier = null;
    await tester.pumpAndSettle();
    expect(find.text('Alkohol am So 13.09?'), findsOneWidget);
    await tester.tap(find.text('Ja').first);
    await tester.pumpAndSettle();
    expect(
      (await repo.readJournalDay(
        '2026-09-13',
      )).metrics['alcohol_evening']?.value,
      1,
    );
  });

  testWidgets(
    'a conflict reloads the latest answer instead of retrying a stale patch',
    (tester) async {
      await mount(tester);
      final barrier = Completer<void>();
      repo.journalPatchBarrier = barrier.future;
      await tester.tap(find.text('Nein').first);
      await tester.pump();
      repo.seedJournalEditor(
        day: '2026-09-14',
        metrics: {'alcohol_evening': const JournalMetricValue(1)},
      );
      repo.journalPatchBarrier = null;
      barrier.complete();
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Antwort inzwischen geändert'),
        findsOneWidget,
      );
      expect(find.text('Neu laden'), findsOneWidget);
      expect(find.text('Erneut speichern'), findsNothing);
      await tester.tap(find.text('Neu laden'));
      await tester.pumpAndSettle();
      expect(find.text('Gestern nach 14 Uhr Koffein?'), findsOneWidget);
      expect(
        (await repo.readJournalDay(
          '2026-09-14',
        )).metrics['alcohol_evening']?.value,
        1,
      );
    },
  );

  testWidgets(
    'successful write with failed refresh offers reload, not another save',
    (tester) async {
      repo = _ReadFailsAfterWrite()..failCaffeineSleepPattern = true;
      controller.dispose();
      controller = OpenBandController(
        repository: repo,
        initialDay: '2026-09-15',
        now: () => DateTime(2026, 9, 15),
      );
      await mount(tester);
      await tester.tap(find.text('Nein').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Antwort gespeichert.'), findsOneWidget);
      expect(find.text('Neu laden'), findsOneWidget);
      expect(find.text('Erneut speichern'), findsNothing);
      repo.failJournalRead = false;
      await tester.tap(find.text('Neu laden'));
      await tester.pumpAndSettle();
      expect(
        (await repo.readJournalDay(
          '2026-09-14',
        )).metrics['alcohol_evening']?.value,
        0,
      );
    },
  );

  testWidgets(
    'a saved custom question joins the check-in and keeps its own field',
    (tester) async {
      await repo.createJournalField(
        const JournalFieldSpec(
          key: 'custom_evening_walk',
          label: 'Abends draußen?',
          kind: JournalFieldKind.yesNo,
          unit: '',
          max: 1,
          step: 1,
          custom: true,
        ),
      );
      await mount(tester);
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('Später'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Abends draußen?'), findsOneWidget);
      await tester.tap(find.text('Ja').first);
      await tester.pumpAndSettle();
      expect(
        (await repo.readJournalDay(
          '2026-09-15',
        )).metrics['custom_evening_walk']?.value,
        1,
      );
    },
  );

  testWidgets('hiding and restoring a custom question retains its answer', (
    tester,
  ) async {
    await repo.createJournalField(
      const JournalFieldSpec(
        key: 'custom_evening_walk',
        label: 'Abends draußen?',
        kind: JournalFieldKind.yesNo,
        unit: '',
        max: 1,
        step: 1,
        custom: true,
      ),
    );
    repo.seedJournalEditor(
      day: '2026-09-15',
      metrics: {'custom_evening_walk': const JournalMetricValue(1)},
    );
    await mount(tester);
    await tester.tap(find.text('Anpassen ›'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(OBSwitch).first);
    await tester.pumpAndSettle();
    expect(
      (await repo.listJournalFields(
        includeHidden: true,
      )).firstWhere((f) => f.key == 'custom_evening_walk').hidden,
      isTrue,
    );
    await tester.tap(find.byType(OBSwitch).first);
    await tester.pumpAndSettle();
    expect(
      (await repo.listJournalFields(
        includeHidden: true,
      )).firstWhere((f) => f.key == 'custom_evening_walk').hidden,
      isFalse,
    );
    expect(
      (await repo.readJournalDay(
        '2026-09-15',
      )).metrics['custom_evening_walk']?.value,
      1,
    );
  });

  testWidgets(
    'editing a saved answer keeps the sheet draft after a failed save',
    (tester) async {
      repo.seedJournalEditor(
        day: '2026-09-14',
        metrics: {'alcohol_evening': const JournalMetricValue(0)},
      );
      await mount(tester);
      await tester.tap(find.byTooltip('Alkohol ändern'));
      await tester.pumpAndSettle();
      expect(find.text('vorher: Nein'), findsOneWidget);
      await tester.tap(find.text('Ja').last);
      await tester.pump();
      repo.failJournalPatch = true;
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Deine Auswahl bleibt erhalten'),
        findsOneWidget,
      );
      expect(
        (await repo.readJournalDay(
          '2026-09-14',
        )).metrics['alcohol_evening']?.value,
        0,
      );
      repo.failJournalPatch = false;
      await tester.tap(find.text('Erneut speichern').last);
      await tester.pumpAndSettle();
      expect(
        (await repo.readJournalDay(
          '2026-09-14',
        )).metrics['alcohol_evening']?.value,
        1,
      );
      expect(find.text('vorher: Nein'), findsNothing);
    },
  );

  testWidgets('editing an earlier answer keeps the first open question', (
    tester,
  ) async {
    repo.seedJournalEditor(
      day: '2026-09-14',
      metrics: {'alcohol_evening': const JournalMetricValue(0)},
    );
    await mount(tester);
    expect(find.text('Gestern nach 14 Uhr Koffein?'), findsOneWidget);
    await tester.tap(find.byTooltip('Alkohol ändern'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ja').last);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Gestern nach 14 Uhr Koffein?'), findsOneWidget);
  });

  testWidgets('dismissing a failed edit cannot retry onto the open question', (
    tester,
  ) async {
    repo.seedJournalEditor(
      day: '2026-09-14',
      metrics: {'alcohol_evening': const JournalMetricValue(0)},
    );
    await mount(tester);
    expect(find.text('Gestern nach 14 Uhr Koffein?'), findsOneWidget);
    await tester.tap(find.byTooltip('Alkohol ändern'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ja').last);
    repo.failJournalPatch = true;
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Erneut speichern'), findsOneWidget);
    await tester.tap(find.byTooltip('Schließen'));
    await tester.pumpAndSettle();
    repo.failJournalPatch = false;
    final retry = find.text('Erneut speichern');
    if (retry.evaluate().isNotEmpty) {
      await tester.tap(retry);
      await tester.pumpAndSettle();
    }
    expect(retry, findsNothing);
    expect(
      (await repo.readJournalDay('2026-09-14')).metrics['caffeine_late'],
      isNull,
    );
    expect(
      (await repo.readJournalDay(
        '2026-09-14',
      )).metrics['alcohol_evening']?.value,
      0,
    );
  });

  testWidgets('closing another edit keeps the open caffeine retry', (
    tester,
  ) async {
    repo.seedJournalEditor(
      day: '2026-09-14',
      metrics: {'alcohol_evening': const JournalMetricValue(0)},
    );
    repo.failJournalPatch = true;
    await mount(tester);
    await tester.tap(find.text('Ja').first);
    await tester.pumpAndSettle();
    expect(find.text('Erneut speichern'), findsOneWidget);
    await tester.tap(find.byTooltip('Alkohol ändern'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Schließen'));
    await tester.pumpAndSettle();
    expect(find.text('Erneut speichern'), findsOneWidget);
    expect(
      find.textContaining('Deine Auswahl bleibt erhalten'),
      findsOneWidget,
    );
    repo.failJournalPatch = false;
    await tester.tap(find.text('Erneut speichern'));
    await tester.pumpAndSettle();
    expect(
      (await repo.readJournalDay('2026-09-14')).metrics['caffeine_late']?.value,
      1,
    );
    expect(
      (await repo.readJournalDay(
        '2026-09-14',
      )).metrics['alcohol_evening']?.value,
      0,
    );
  });

  testWidgets('a saved edit keeps its refresh failure after the sheet closes', (
    tester,
  ) async {
    final failingRepo = _ReadFailsAfterWrite()..failCaffeineSleepPattern = true;
    failingRepo.seedJournalEditor(
      day: '2026-09-14',
      metrics: {'alcohol_evening': const JournalMetricValue(0)},
    );
    repo = failingRepo;
    controller.dispose();
    controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-15',
      now: () => DateTime(2026, 9, 15),
    );
    await mount(tester);
    await tester.tap(find.byTooltip('Alkohol ändern'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ja').last);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.byType(G3JournalAnswerSheet), findsNothing);
    expect(
      find.text(
        'Antwort gespeichert. Ansicht konnte nicht aktualisiert werden.',
      ),
      findsOneWidget,
    );
    expect(find.text('Neu laden'), findsOneWidget);
    failingRepo.failJournalRead = false;
    await tester.tap(find.text('Neu laden'));
    await tester.pumpAndSettle();
    expect(
      (await repo.readJournalDay(
        '2026-09-14',
      )).metrics['alcohol_evening']?.value,
      1,
    );
    expect(
      (await repo.readJournalDay('2026-09-14')).metrics['caffeine_late'],
      isNull,
    );
  });

  testWidgets('a failed delete retries null and leaves the question open', (
    tester,
  ) async {
    repo.seedJournalEditor(
      day: '2026-09-14',
      metrics: {'alcohol_evening': const JournalMetricValue(1)},
    );
    await mount(tester);
    await tester.tap(find.byTooltip('Alkohol ändern'));
    await tester.pumpAndSettle();
    repo.failJournalPatch = true;
    await tester.tap(find.text('Antwort löschen'));
    await tester.pumpAndSettle();
    repo.failJournalPatch = false;
    await tester.tap(find.text('Erneut speichern').last);
    await tester.pumpAndSettle();
    expect(
      (await repo.readJournalDay('2026-09-14')).metrics['alcohol_evening'],
      isNull,
    );
    expect(find.text('Gestern Abend Alkohol?'), findsOneWidget);
  });

  testWidgets('a sheet conflict offers reload and drops its stale draft', (
    tester,
  ) async {
    repo.seedJournalEditor(
      day: '2026-09-14',
      metrics: {'alcohol_evening': const JournalMetricValue(0)},
    );
    await mount(tester);
    await tester.tap(find.byTooltip('Alkohol ändern'));
    await tester.pumpAndSettle();
    final barrier = Completer<void>();
    repo.journalPatchBarrier = barrier.future;
    await tester.tap(find.text('Speichern'));
    await tester.pump();
    repo.seedJournalEditor(
      day: '2026-09-14',
      metrics: {'alcohol_evening': const JournalMetricValue(1)},
    );
    repo.journalPatchBarrier = null;
    barrier.complete();
    await tester.pumpAndSettle();
    expect(find.text('Neu laden'), findsOneWidget);
    expect(find.text('Erneut speichern'), findsNothing);
    await tester.tap(find.text('Neu laden'));
    await tester.pumpAndSettle();
    expect(find.byType(G3JournalAnswerSheet), findsNothing);
    expect(
      (await repo.readJournalDay(
        '2026-09-14',
      )).metrics['alcohol_evening']?.value,
      1,
    );
  });

  testWidgets('zero is Keins and Später does not create a metric', (
    tester,
  ) async {
    await repo.createJournalField(
      const JournalFieldSpec(
        key: 'custom_count',
        label: 'Wie viele?',
        kind: JournalFieldKind.dose,
        unit: 'Anzahl',
        max: 20,
        step: 1,
        custom: true,
      ),
    );
    await mount(tester);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Später'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Wie viele?'), findsOneWidget);
    await tester.tap(find.text('Später'));
    await tester.pumpAndSettle();
    expect(
      (await repo.readJournalDay('2026-09-15')).metrics['custom_count'],
      isNull,
    );
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Später'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Keins'));
    await tester.pumpAndSettle();
    expect(
      (await repo.readJournalDay('2026-09-15')).metrics['custom_count']?.value,
      0,
    );
    expect(find.text('Keins'), findsWidgets);
    expect(find.text('0 Anzahl'), findsNothing);
  });

  testWidgets('pattern refusal shows the repository minimum and paired count', (
    tester,
  ) async {
    repo.failCaffeineSleepPattern = false;
    repo.seedCaffeineSleepPattern(
      '2026-09-15',
      seed: SyntheticCaffeineSleepSeed.insufficient,
    );
    await mount(tester);
    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('noch kein Vergleich'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('noch kein Vergleich'));
    await tester.pumpAndSettle();
    expect(find.text('5 von 8 Paaren · noch 3'), findsOneWidget);
    expect(
      find.text('Für den Vergleich fehlen Tag-Nacht-Paare: 5 von 8 vorhanden.'),
      findsOneWidget,
    );
    expect(find.textContaining('von 3'), findsWidgets);
    expect(find.textContaining('ms'), findsNothing);
  });

  testWidgets('pattern counts use singular nouns for one pair and one night', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: Scaffold(
          body: Column(
            children: const [
              OBPatternCard(
                title: 'Noch zu wenige Nächte',
                detail: 'Koffein nach 14 Uhr · folgende Nacht',
                have: 0,
                need: 1,
              ),
              OBPatternDotPlot(
                withAnswer: [0.5],
                withoutAnswer: [],
                min: 0,
                max: 1,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('von 1 Tag-Nacht-Paar'), findsOneWidget);
    expect(find.text('0 von 1 Paar · noch 1'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        '1 beobachtete Nacht mit Ja und 0 beobachtete Nächte mit Nein',
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets(
    'pattern card separates loading, failure, retry, and partial data',
    (tester) async {
      final patternRepo = _PatternRepository();
      final pending = patternRepo.pending = Completer<G3JournalPattern>();
      repo = patternRepo;
      controller.dispose();
      controller = OpenBandController(
        repository: repo,
        initialDay: '2026-09-15',
        now: () => DateTime(2026, 9, 15),
      );
      await mount(tester, settle: false);
      await tester.pump();
      expect(find.text('Vergleich wird geladen.'), findsOneWidget);
      patternRepo.pending = null;
      patternRepo.failPattern = true;
      pending.completeError(StateError('pattern read failed'));
      await tester.pumpAndSettle();
      expect(
        find.text('Vergleich konnte nicht geladen werden.'),
        findsOneWidget,
      );
      expect(find.text('Erneut'), findsOneWidget);
      patternRepo.failPattern = false;
      patternRepo.partialPattern = true;
      await tester.ensureVisible(find.text('Erneut'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Erneut'));
      await tester.pumpAndSettle();
      expect(find.text('Teilweise auswertbar'), findsOneWidget);
      expect(find.text('Vergleich konnte nicht geladen werden.'), findsNothing);
    },
  );

  testWidgets(
    'paired refusal shows known side counts without calling it a side refusal',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const model = CaffeineSleepPattern(
        kind: CaffeineSleepPatternKind.insufficient,
        pairedN: 5,
        yesNights: 1,
        noNights: 4,
        endDay: '2026-09-15',
        startDay: '2026-08-17',
        nights: 30,
        algoVersion: 1,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: openBandTheme(Brightness.light),
          home: const G3JournalPatternScreen(pattern: G3JournalPattern(model)),
        ),
      );
      expect(find.text('5 von 8 Paaren · noch 3'), findsOneWidget);
      expect(find.text('1 von 3'), findsOneWidget);
      expect(find.text('4 · genug'), findsOneWidget);
      expect(
        find.text(
          'Für den Vergleich fehlen Tag-Nacht-Paare: 5 von 8 vorhanden.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'known per-side refusal counts use the supplied producer threshold',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const model = CaffeineSleepPattern(
        kind: CaffeineSleepPatternKind.insufficient,
        pairedN: 8,
        yesNights: 1,
        noNights: 7,
        endDay: '2026-09-15',
        startDay: '2026-08-17',
        nights: 30,
        algoVersion: 1,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: openBandTheme(Brightness.light),
          home: const G3JournalPatternScreen(pattern: G3JournalPattern(model)),
        ),
      );
      expect(
        find.text('8 Paare · Ja 1 von 3 nötig · Nein 7 vorhanden'),
        findsOneWidget,
      );
      expect(
        find.text('Für den Vergleich braucht es je 3 Nächte mit Ja und Nein.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('partial pattern keeps its label beside a minute result', (
    tester,
  ) async {
    const model = CaffeineSleepPattern(
      kind: CaffeineSleepPatternKind.meaningful,
      pairedN: 12,
      yesNights: 5,
      noNights: 7,
      delta: 4,
      endDay: '2026-09-15',
      startDay: '2026-08-17',
      nights: 30,
      algoVersion: 1,
      partial: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: const G3JournalPatternScreen(pattern: G3JournalPattern(model)),
      ),
    );
    expect(find.text('+4'), findsOneWidget);
    expect(find.text('Teilweise auswertbar'), findsOneWidget);
  });

  testWidgets(
    'history refusal names the producer count and unknown stays generic',
    (tester) async {
      const history = CaffeineSleepPattern(
        kind: CaffeineSleepPatternKind.insufficient,
        pairedN: 8,
        yesNights: 4,
        noNights: 4,
        note: 'need_history:have=8,need=18',
        endDay: '2026-09-15',
        startDay: '2026-08-17',
        nights: 30,
        algoVersion: 1,
      );
      Widget screen(CaffeineSleepPattern pattern) => MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: G3JournalPatternScreen(pattern: G3JournalPattern(pattern)),
      );
      await tester.pumpWidget(screen(history));
      expect(
        find.text(
          'Für den statistischen Vergleich fehlen Tag-Nacht-Paare: 8 von 18 nötig.',
        ),
        findsOneWidget,
      );
      expect(find.text('8 von 18 Paaren für den Test'), findsOneWidget);
      await tester.pumpWidget(
        screen(
          const CaffeineSleepPattern(
            kind: CaffeineSleepPatternKind.insufficient,
            pairedN: 8,
            yesNights: 4,
            noNights: 4,
            note: 'other',
            endDay: '2026-09-15',
            startDay: '2026-08-17',
            nights: 30,
            algoVersion: 1,
          ),
        ),
      );
      expect(
        find.text('Ein Vergleich ist noch nicht möglich.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('Journal tab light', (tester) async {
    repo.seedJournalEditor(
      day: '2026-09-14',
      metrics: {
        'alcohol_evening': const JournalMetricValue(0),
        'caffeine_late': const JournalMetricValue(1),
      },
    );
    await mount(tester);
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('openband_goldens/g3-journal-tab-light.png'),
    );
  }, tags: const ['golden']);

  testWidgets('Journal section labels align with their trailing text', (
    tester,
  ) async {
    repo.seedJournalEditor(
      day: '2026-09-15',
      metrics: {'mood': const JournalMetricValue(4)},
    );
    await mount(tester);

    double baseline(String text) {
      final box = tester.renderObject<RenderBox>(find.text(text));
      final offset = box.getDryBaseline(
        box.constraints,
        TextBaseline.alphabetic,
      )!;
      return box.localToGlobal(Offset(0, offset)).dy;
    }

    expect((baseline('HEUTE') - baseline('Anpassen ›')).abs(), lessThan(1));
    expect(
      (baseline('HEUTE BEANTWORTET') - baseline('1 beantwortet')).abs(),
      lessThan(1),
    );
    final action = find.ancestor(
      of: find.text('Anpassen ›'),
      matching: find.byType(TextButton),
    );
    expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
  });
}
