import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/journal.dart';
import 'package:openstrap_edge/openband/journal_controls.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';

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

  late SyntheticOpenBandRepository repo;
  late OpenBandController controller;
  setUp(() {
    repo = SyntheticOpenBandRepository.fromMaps(
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
    controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-15',
      band: repo.band,
    );
  });
  tearDown(() => controller.dispose());

  Future<void> settleProducer(WidgetTester tester) async {
    final pending = repo.caffeineSleepPatternPending;
    if (pending != null) {
      await tester.runAsync(() async {
        try {
          await pending;
        } on Object {
          // Widget asserts producer failures.
        }
      });
    }
    await tester.pumpAndSettle();
  }

  Future<void> mount(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double scale = 1,
    double width = 393,
    double height = 852,
    bool seedPattern = true,
    bool seedGoals = true,
    SyntheticCaffeineSleepSeed patternSeed =
        SyntheticCaffeineSleepSeed.paperMeaningful,
    FutureOr<void> Function(String day)? onEdit,
    FutureOr<void> Function()? onNutrition,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (seedGoals) await repo.seedNutritionGoals();
    if (seedPattern) {
      repo.seedCaffeineSleepPattern('2026-09-15', seed: patternSeed);
    }
    await controller.refresh();
    await tester.runAsync(() async {
      try {
        await repo.readCaffeineSleepPattern(controller.selectedDay, 30);
      } on Object {
        // The mounted widget renders the producer failure.
      }
    });
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        debugShowCheckedModeBanner: false,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(brightness).copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            size: Size(width, height),
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('capture'),
          child: Scaffold(
            body: OpenBandJournal(
              controller: controller,
              onEdit: onEdit ?? (_) async {},
              onNutrition: onNutrition ?? () async {},
            ),
          ),
        ),
      ),
    );
    await settleProducer(tester);
  }

  Future<void> switchDay(WidgetTester tester, String day) async {
    await tester.runAsync(() => controller.selectDay(day));
  }

  testWidgets('journal hub meaningful pattern, mood CAS persist and clear', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('Journal'), findsOneWidget);
    expect(find.byKey(const ValueKey('journal-edit')), findsOneWidget);
    expect(find.byTooltip('Journal bearbeiten'), findsOneWidget);
    expect(find.text('Weitere Angaben'), findsNothing);
    expect(find.textContaining('erfasst'), findsNothing);
    expect(find.text('Wie fühlst du dich?'), findsOneWidget);
    expect(find.text('Koffein nach 14 Uhr'), findsOneWidget);
    expect(find.text('Alkohol'), findsOneWidget);
    expect(find.text('Abends gelesen'), findsOneWidget);
    expect(find.text('Einschlafen · Koffein nach 14 Uhr'), findsOneWidget);
    expect(find.text('+12 Min.'), findsOneWidget);
    expect(find.text('Ja gegenüber Nein'), findsOneWidget);
    expect(find.text('Ja · 7 Nächte'), findsOneWidget);
    expect(find.text('Nein · 11 Nächte'), findsOneWidget);
    expect(find.text('620'), findsOneWidget);
    expect(find.text('Ziel 2.000'), findsOneWidget);
    expect(find.textContaining('≥'), findsNothing);
    expect(find.textContaining('mind.'), findsNothing);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/journal-hub.png'),
    );
    await tester.tap(find.bySemanticsLabel('Stimmung Gut'));
    await tester.pumpAndSettle();
    expect((await repo.readJournalDay('2026-09-15')).metrics['mood']?.value, 4);
    await tester.tap(find.bySemanticsLabel('Stimmung Gut'));
    await tester.pumpAndSettle();
    expect(
      (await repo.readJournalDay('2026-09-15')).metrics.containsKey('mood'),
      isFalse,
    );
    await mount(tester, brightness: Brightness.dark);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/journal-hub-dark.png'),
    );
  });

  testWidgets(
    'yes/no answers persist as 1/0; absence stays open; clear works',
    (tester) async {
      await repo.writeJournal('2026-09-15', 'caffeine_mg', 180);
      await mount(tester);
      expect(find.byKey(const ValueKey('journal-edit')), findsOneWidget);
      expect(find.text('Weitere Angaben'), findsNothing);
      expect(find.text('1 erfasst'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Koffein nach 14 Uhr: Ja'));
      await settleProducer(tester);
      await tester.tap(find.bySemanticsLabel('Alkohol: Nein'));
      await tester.pumpAndSettle();
      final byKey = {
        for (final e in await repo.readJournal('2026-09-15')) e.key: e.value,
      };
      expect(byKey['caffeine_late'], 1);
      expect(byKey['alcohol_evening'], 0);
      expect(byKey.containsKey('read_before_bed'), isFalse);
      await tester.tap(find.bySemanticsLabel('Koffein nach 14 Uhr: Ja'));
      await settleProducer(tester);
      expect(
        (await repo.readJournalDay(
          '2026-09-15',
        )).metrics.containsKey('caffeine_late'),
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/journal-hub-answered.png'),
      );
    },
  );

  testWidgets('insufficient / unavailable / nonmeaningful / partial / error', (
    tester,
  ) async {
    await mount(tester, patternSeed: SyntheticCaffeineSleepSeed.insufficient);
    expect(find.text('Noch zu wenige Nächte'), findsOneWidget);
    expect(find.text('5 Nächte mit Eintrag'), findsOneWidget);
    expect(find.text('Teilweise auswertbar'), findsNothing);
    expect(find.textContaining('kein Beweis'), findsNothing);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/journal-hub-insufficient.png'),
    );

    await mount(tester, patternSeed: SyntheticCaffeineSleepSeed.unavailable);
    expect(find.text('Noch kein Vergleich'), findsOneWidget);
    expect(find.text('Keine auswertbaren Nächte mit Eintrag'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/journal-hub-unavailable.png'),
    );

    await mount(tester, patternSeed: SyntheticCaffeineSleepSeed.nonmeaningful);
    expect(find.text('Kein klares Muster'), findsOneWidget);
    expect(find.text('18 Nächte mit Eintrag'), findsOneWidget);
    expect(find.text('Teilweise auswertbar'), findsNothing);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/journal-hub-nonmeaningful.png'),
    );

    await mount(
      tester,
      patternSeed: SyntheticCaffeineSleepSeed.partialMeaningful,
    );
    expect(find.text('+12 Min.'), findsOneWidget);
    expect(find.text('Teilweise auswertbar'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/journal-hub-partial.png'),
    );

    repo.failCaffeineSleepPattern = true;
    await mount(tester, seedPattern: false);
    expect(find.text('Vergleich konnte nicht geladen werden.'), findsOneWidget);
    expect(find.text('Erneut'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/journal-hub-error.png'),
    );
    await mount(tester, seedPattern: false, brightness: Brightness.dark);
    expect(find.text('Vergleich konnte nicht geladen werden.'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/journal-hub-error-dark.png'),
    );
    repo.failCaffeineSleepPattern = false;
    repo.seedCaffeineSleepPattern('2026-09-15');
    await tester.tap(find.text('Erneut'));
    await tester.pump();
    await settleProducer(tester);
    expect(find.text('+12 Min.'), findsOneWidget);
  });

  testWidgets('partial label is shared across insufficient and nonmeaningful', (
    tester,
  ) async {
    Future<void> pumpKind(CaffeineSleepPatternKind kind) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          theme: openBandTheme(
            Brightness.light,
          ).copyWith(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: OBPatternCard(
              pattern: CaffeineSleepPattern(
                kind: kind,
                pairedN: kind == CaffeineSleepPatternKind.insufficient
                    ? 5
                    : 18,
                yesNights: kind == CaffeineSleepPatternKind.nonmeaningful
                    ? 9
                    : null,
                noNights: kind == CaffeineSleepPatternKind.nonmeaningful
                    ? 9
                    : null,
                endDay: '2026-09-15',
                startDay: '2026-08-17',
                nights: 30,
                algoVersion: 90,
                partial: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpKind(CaffeineSleepPatternKind.insufficient);
    expect(find.text('Noch zu wenige Nächte'), findsOneWidget);
    expect(find.text('Teilweise auswertbar'), findsOneWidget);
    expect(find.text('+12 Min.'), findsNothing);

    await pumpKind(CaffeineSleepPatternKind.nonmeaningful);
    expect(find.text('Kein klares Muster'), findsOneWidget);
    expect(find.text('Teilweise auswertbar'), findsOneWidget);
    expect(find.textContaining('≥'), findsNothing);
    expect(find.textContaining('mind.'), findsNothing);
  });

  testWidgets('meals error is distinct from missing nutrition data', (
    tester,
  ) async {
    repo.failMealsRead = true;
    await mount(tester);
    expect(find.text('Einträge konnten nicht geladen werden.'), findsOneWidget);
    expect(find.text('620'), findsNothing);
    expect(find.text('Erneut'), findsWidgets);
    repo.failMealsRead = false;
    await tester.tap(find.text('Erneut').first);
    await tester.pumpAndSettle();
    expect(find.text('620'), findsOneWidget);
  });

  testWidgets('hub target read error stays distinct from unset goals', (
    tester,
  ) async {
    repo.failNutritionTargetRead = true;
    await mount(tester);
    expect(find.text('Ziele konnten nicht geladen werden.'), findsOneWidget);
    expect(find.text('620'), findsOneWidget);
    expect(find.text('Ziel —'), findsOneWidget);
    expect(find.text('Kein Ziel'), findsNothing);
    expect(find.text('Ziel 2.000'), findsNothing);
    repo.failNutritionTargetRead = false;
    await tester.tap(find.text('Erneut').first);
    await tester.pumpAndSettle();
    expect(find.text('Ziel 2.000'), findsOneWidget);
  });

  testWidgets(
    'zero energy target is 0 with no ratio; absent targets hide track',
    (tester) async {
      await repo.seedNutritionGoals();
      final cleared = await repo.clearNutritionTargets(
        '2026-09-15',
        expectedRevision: 1,
      );
      expect(cleared.saved, isTrue);
      expect(cleared.row!.values.hasAny, isFalse);
      await mount(tester, seedGoals: false);
      expect(find.text('Kein Ziel'), findsOneWidget);
      expect(find.byKey(const ValueKey('macro-energy-track')), findsNothing);

      final saved = await repo.saveNutritionTargets(
        '2026-09-15',
        const NutritionTargetValues(proteinG: 0, fatG: 60),
        expectedRevision: cleared.row!.revision,
      );
      expect(saved.saved, isTrue);
      expect(saved.row!.values.energyKcal, isNull);
      expect(saved.row!.values.proteinG, 0);
      await mount(tester, seedGoals: false);
      expect(find.text('Kein Ziel'), findsOneWidget);
      expect(find.text('26 / 0 g'), findsOneWidget);
      expect(find.byKey(const ValueKey('macro-energy-track')), findsNothing);
      expect(
        tester.getSize(find.byKey(const ValueKey('macro-protein-fill'))).width,
        0,
      );
    },
  );

  testWidgets('inline write uses captured day; day switch does not clobber', (
    tester,
  ) async {
    await mount(tester);
    final writeGate = Completer<void>();
    repo.journalPatchBarrier = writeGate.future;
    await tester.tap(find.bySemanticsLabel('Stimmung Gut'));
    await tester.pump();
    await switchDay(tester, '2026-09-14');
    await tester.pump();
    writeGate.complete();
    repo.journalPatchBarrier = null;
    await settleProducer(tester);
    expect((await repo.readJournalDay('2026-09-15')).metrics['mood']?.value, 4);
    expect(
      (await repo.readJournalDay('2026-09-14')).metrics.containsKey('mood'),
      isFalse,
    );
  });

  testWidgets('save failure retains last saved snapshot', (tester) async {
    await mount(tester);
    repo.failJournalPatch = true;
    await tester.tap(find.bySemanticsLabel('Alkohol: Ja'));
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen.'), findsOneWidget);
    expect(
      (await repo.readJournalDay(
        '2026-09-15',
      )).metrics.containsKey('alcohol_evening'),
      isFalse,
    );
    expect(find.bySemanticsLabel('Alkohol: Ja'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/journal-hub-save-error.png'),
    );
    await mount(tester, brightness: Brightness.dark);
    repo.failJournalPatch = true;
    await tester.tap(find.bySemanticsLabel('Alkohol: Ja'));
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen.'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/journal-hub-save-error-dark.png'),
    );
  });

  testWidgets('info sheet uses methodology, 2x and 320 do not clip controls', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(find.text('Vergleich verstehen'), findsOneWidget);
    expect(find.textContaining('belegt keine Ursache'), findsOneWidget);
    expect(
      find.textContaining('17. August–15. September · 18 Nächte'),
      findsOneWidget,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/journal-hub-info.png'),
    );
    await tester.tap(find.text('Schließen').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await mount(
      tester,
      patternSeed: SyntheticCaffeineSleepSeed.unavailable,
    );
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('17. August–15. September · 0 Nächte'),
      findsOneWidget,
    );
    expect(find.textContaining('30 Nächte'), findsNothing);
    expect(find.textContaining('18 Nächte'), findsNothing);
    await tester.tap(find.text('Schließen').last);
    await tester.pumpAndSettle();

    await mount(tester, scale: 2, height: 1200);
    expect(find.text('Koffein nach 14 Uhr'), findsOneWidget);
    expect(find.text('+12 Min.'), findsOneWidget);
    expect(find.text('Ja gegenüber Nein'), findsOneWidget);
    expect(find.text('Ja · 7 Nächte'), findsOneWidget);
    expect(find.text('Nein · 11 Nächte'), findsOneWidget);
    expect(find.byKey(const ValueKey('journal-edit')), findsOneWidget);
    expect(find.text('Ja').hitTestable(), findsWidgets);
    final titleSel = TextSelection(
      baseOffset: 0,
      extentOffset: CaffeineSleepPattern.title.length,
    );
    expect(
      tester
          .renderObject<RenderParagraph>(find.text(CaffeineSleepPattern.title))
          .getBoxesForSelection(titleSel)
          .length,
      2,
    );
    expect(
      tester.getTopLeft(find.text('Ja gegenüber Nein')).dy,
      greaterThan(tester.getBottomLeft(find.text('+12 Min.')).dy - 2),
    );
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/journal-hub-2x.png'),
    );
    await tester.ensureVisible(find.text('Nein · 11 Nächte'));
    await tester.pumpAndSettle();
    expect(find.text('+12 Min.'), findsOneWidget);
    expect(find.text('Ja gegenüber Nein'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/journal-hub-2x-scrolled.png'),
    );

    await mount(
      tester,
      scale: 2,
      height: 1200,
      brightness: Brightness.dark,
    );
    await tester.ensureVisible(find.text('Nein · 11 Nächte'));
    await tester.pumpAndSettle();
    expect(
      tester
          .renderObject<RenderParagraph>(find.text(CaffeineSleepPattern.title))
          .getBoxesForSelection(titleSel)
          .length,
      2,
    );
    expect(
      tester.getTopLeft(find.text('Ja gegenüber Nein')).dy,
      greaterThan(tester.getBottomLeft(find.text('+12 Min.')).dy - 2),
    );
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/journal-hub-2x-scrolled-dark.png'),
    );

    await mount(tester, width: 320, height: 568);
    expect(find.text('Ja').hitTestable(), findsWidgets);
    await tester.scrollUntilVisible(find.text('Ja gegenüber Nein'), 200);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Ja gegenüber Nein')).dy,
      greaterThan(tester.getBottomLeft(find.text('+12 Min.')).dy - 2),
    );
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/journal-hub-320.png'),
    );
  });

  bool moodSelected(WidgetTester tester) =>
      tester
          .getSemantics(find.bySemanticsLabel('Stimmung Gut'))
          .flagsCollection
          .isSelected
          .toBoolOrNull() ??
      false;

  testWidgets(
    'day switch clears old answers immediately; pending save keeps CAS',
    (tester) async {
      await mount(tester);
      await tester.tap(find.bySemanticsLabel('Stimmung Gut'));
      await tester.pumpAndSettle();
      expect(moodSelected(tester), isTrue);

      final gate = Completer<void>();
      repo.journalReadBarrier = gate.future;
      await switchDay(tester, '2026-09-14');
      await tester.pump();
      expect(moodSelected(tester), isFalse);
      expect(find.bySemanticsLabel('Alkohol: Ja'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Alkohol: Ja'))
            .flagsCollection
            .isSelected
            .toBoolOrNull(),
        isFalse,
      );

      gate.complete();
      repo.journalReadBarrier = null;
      await settleProducer(tester);
      expect(moodSelected(tester), isFalse);
      expect(
        (await repo.readJournalDay('2026-09-15')).metrics['mood']?.value,
        4,
      );
      expect(
        (await repo.readJournalDay('2026-09-14')).metrics.containsKey('mood'),
        isFalse,
      );
    },
  );

  testWidgets('nutrition retry does not cancel an in-flight journal read', (
    tester,
  ) async {
    repo.failMealsRead = true;
    await mount(tester);
    expect(find.text('Einträge konnten nicht geladen werden.'), findsOneWidget);

    final gate = Completer<void>();
    repo.journalReadBarrier = gate.future;
    await switchDay(tester, '2026-09-14');
    await tester.pump();
    expect(find.text('Einträge konnten nicht geladen werden.'), findsOneWidget);

    repo.failMealsRead = false;
    await tester.tap(find.text('Erneut').first);
    await tester.pump();
    gate.complete();
    repo.journalReadBarrier = null;
    await settleProducer(tester);

    await tester.tap(find.bySemanticsLabel('Stimmung Gut'));
    await tester.pumpAndSettle();
    expect((await repo.readJournalDay('2026-09-14')).metrics['mood']?.value, 4);
    expect(find.text('620'), findsNothing);
  });

  testWidgets('conflict reloads retained newer revision before a new edit', (
    tester,
  ) async {
    await mount(tester);
    final loaded = await repo.readJournalDay('2026-09-15');

    await repo.writeJournal('2026-09-15', 'mood', 2);
    final concurrent = await repo.readJournalDay('2026-09-15');
    expect(
      concurrent.metricUpdatedAt['mood'] ?? 0,
      greaterThan(loaded.metricUpdatedAt['mood'] ?? 0),
    );

    await tester.tap(find.bySemanticsLabel('Stimmung Gut'));
    await tester.pumpAndSettle();
    expect(find.text('Antwort inzwischen geändert.'), findsOneWidget);
    expect(find.text('Neu laden'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/journal-hub-conflict.png'),
    );
    final retained = await repo.readJournalDay('2026-09-15');
    expect(retained.metrics['mood']?.value, 2);
    expect(
      retained.metricUpdatedAt['mood'],
      concurrent.metricUpdatedAt['mood'],
    );

    await tester.tap(find.text('Neu laden'));
    await tester.pumpAndSettle();
    expect(find.text('Antwort inzwischen geändert.'), findsNothing);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Stimmung Müde'))
          .flagsCollection
          .isSelected
          .toBoolOrNull(),
      isTrue,
    );

    await tester.tap(find.bySemanticsLabel('Stimmung Gut'));
    await tester.pumpAndSettle();
    final edited = await repo.readJournalDay('2026-09-15');
    expect(edited.metrics['mood']?.value, 4);
    expect(
      edited.metricUpdatedAt['mood'] ?? 0,
      greaterThan(concurrent.metricUpdatedAt['mood'] ?? 0),
    );

    await mount(tester, brightness: Brightness.dark);
    final darkLoaded = await repo.readJournalDay('2026-09-15');
    await repo.writeJournal('2026-09-15', 'mood', 2);
    await tester.tap(find.bySemanticsLabel('Stimmung Gut'));
    await tester.pumpAndSettle();
    expect(find.text('Antwort inzwischen geändert.'), findsOneWidget);
    expect(find.text('Neu laden'), findsOneWidget);
    expect(
      (await repo.readJournalDay('2026-09-15')).metricUpdatedAt['mood'],
      greaterThan(darkLoaded.metricUpdatedAt['mood'] ?? 0),
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/journal-hub-conflict-dark.png'),
    );
  });

  testWidgets('committed write with reload failure retries read only', (
    tester,
  ) async {
    await mount(tester);
    final before = await repo.readJournalDay('2026-09-15');
    repo.failJournalRead = true;
    await tester.tap(find.bySemanticsLabel('Stimmung Gut'));
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen.'), findsNothing);
    expect(find.text('Journal nicht geladen.'), findsOneWidget);
    expect(moodSelected(tester), isTrue);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/journal-hub-read-error.png'),
    );
    await tester.tap(
      find.bySemanticsLabel('Stimmung Okay'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(moodSelected(tester), isTrue);
    expect(find.text('Journal nicht geladen.'), findsOneWidget);

    repo.failJournalRead = false;
    final after = await repo.readJournalDay('2026-09-15');
    expect(after.metrics['mood']?.value, 4);
    expect(
      after.metricUpdatedAt['mood'] ?? 0,
      greaterThan(before.metricUpdatedAt['mood'] ?? 0),
    );
    final committedRev = after.metricUpdatedAt['mood'];

    await tester.tap(find.text('Erneut'));
    await settleProducer(tester);
    expect(find.text('Journal nicht geladen.'), findsNothing);
    expect(moodSelected(tester), isTrue);
    final reloaded = await repo.readJournalDay('2026-09-15');
    expect(reloaded.metrics['mood']?.value, 4);
    expect(reloaded.metricUpdatedAt['mood'], committedRev);

    await mount(tester, brightness: Brightness.dark);
    repo.failJournalRead = true;
    await tester.tap(find.bySemanticsLabel('Stimmung Okay'));
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen.'), findsNothing);
    expect(find.text('Journal nicht geladen.'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/journal-hub-read-error-dark.png'),
    );
    repo.failJournalRead = false;
  });

  testWidgets('header editor action invokes captured-day onEdit', (
    tester,
  ) async {
    final opened = <String>[];
    await mount(tester, onEdit: (day) async => opened.add(day));
    await tester.tap(find.byKey(const ValueKey('journal-edit')));
    await tester.pumpAndSettle();
    expect(opened, ['2026-09-15']);
    await switchDay(tester, '2026-09-14');
    await settleProducer(tester);
    await tester.tap(find.byKey(const ValueKey('journal-edit')));
    await tester.pumpAndSettle();
    expect(opened, ['2026-09-15', '2026-09-14']);
  });

  testWidgets(
    'header edit gated during inline write; latest answer kept',
    (tester) async {
      final opened = <String>[];
      await mount(tester, onEdit: (day) async => opened.add(day));
      final gate = Completer<void>();
      repo.journalPatchBarrier = gate.future;
      await tester.tap(find.bySemanticsLabel('Stimmung Gut'));
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('journal-edit')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(opened, isEmpty);
      expect(moodSelected(tester), isFalse);
      await switchDay(tester, '2026-09-14');
      await tester.pump();
      gate.complete();
      repo.journalPatchBarrier = null;
      await settleProducer(tester);
      expect(
        (await repo.readJournalDay('2026-09-15')).metrics['mood']?.value,
        4,
      );
      expect(
        (await repo.readJournalDay('2026-09-14')).metrics.containsKey('mood'),
        isFalse,
      );
      expect(moodSelected(tester), isFalse);
      await tester.tap(find.byKey(const ValueKey('journal-edit')));
      await tester.pumpAndSettle();
      expect(opened, ['2026-09-14']);

      await switchDay(tester, '2026-09-15');
      await settleProducer(tester);
      expect(moodSelected(tester), isTrue);
      final sameDay = Completer<void>();
      repo.journalPatchBarrier = sameDay.future;
      await tester.tap(find.bySemanticsLabel('Stimmung Gut'));
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('journal-edit')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(opened, ['2026-09-14']);
      sameDay.complete();
      repo.journalPatchBarrier = null;
      await settleProducer(tester);
      expect(
        (await repo.readJournalDay('2026-09-15')).metrics.containsKey('mood'),
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('journal-edit')));
      await tester.pumpAndSettle();
      expect(opened, ['2026-09-14', '2026-09-15']);
    },
  );

  testWidgets('same-day nutrition return reloads meals and targets only', (
    tester,
  ) async {
    final gate = Completer<void>();
    await mount(tester, onNutrition: () => gate.future);
    await tester.tap(find.bySemanticsLabel('Stimmung Gut'));
    await tester.pumpAndSettle();
    expect(moodSelected(tester), isTrue);
    expect(find.text('620'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Ernährung'));
    await tester.pump();
    final draft = MealDraft(
      id: 'd-return',
      day: '2026-09-15',
      meal: 'dinner',
      entries: const [
        MealDraftEntry(id: 'e-return', label: 'Reis', kcal: 300),
      ],
      updatedAt: DateTime(2026, 9, 15, 19),
    );
    await repo.saveMealDraft(draft);
    await repo.commitMealDraft(draft);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('920'), findsOneWidget);
    expect(find.text('620'), findsNothing);
    expect(moodSelected(tester), isTrue);
    expect((await repo.readJournalDay('2026-09-15')).metrics['mood']?.value, 4);
  });

  testWidgets(
    'info sheet pins title close and action while body scrolls',
    (tester) async {
      Finder action() => find.widgetWithText(FilledButton, 'Schließen');

      const infoBody =
          '17. August–15. September · 18 Nächte\n'
          '${CaffeineSleepPattern.infoComparison}\n'
          '${CaffeineSleepPattern.infoEligibility}\n'
          '${CaffeineSleepPattern.infoCausation}';

      Future<void> open({
        required double scale,
        required double width,
        required double height,
      }) async {
        await mount(
          tester,
          scale: scale,
          width: width,
          height: height,
        );
        showOpenBandJournalInfo(
          tester.element(find.byType(OpenBandJournal)),
          title: CaffeineSleepPattern.infoTitle,
          body: infoBody,
        );
        await tester.pumpAndSettle();
        expect(find.text('Vergleich verstehen').hitTestable(), findsOneWidget);
        expect(find.byTooltip('Schließen').hitTestable(), findsOneWidget);
        expect(action().hitTestable(), findsOneWidget);
      }

      Future<void> pinScrollAndDismiss({bool capture = false}) async {
        expect(find.text('Vergleich verstehen').hitTestable(), findsOneWidget);
        expect(find.byTooltip('Schließen').hitTestable(), findsOneWidget);
        expect(action().hitTestable(), findsOneWidget);
        final titleRect = tester.getRect(find.text('Vergleich verstehen'));
        final closeRect = tester.getRect(find.byTooltip('Schließen'));
        final actionRect = tester.getRect(action());
        final body = find.textContaining('Einschlafdauer nach');
        expect(body, findsOneWidget);
        final bodyTop = tester.getRect(body).top;
        await tester.drag(
          find.byKey(const ValueKey('journal-info-body')),
          const Offset(0, -180),
        );
        await tester.pumpAndSettle();
        expect(tester.getRect(body).top, isNot(bodyTop));
        expect(tester.getRect(find.text('Vergleich verstehen')), titleRect);
        expect(tester.getRect(find.byTooltip('Schließen')), closeRect);
        expect(tester.getRect(action()), actionRect);
        if (capture) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('openband_goldens/journal-hub-info-2x.png'),
          );
        }
        await tester.tap(find.byTooltip('Schließen'));
        await tester.pumpAndSettle();
        expect(find.text('Vergleich verstehen'), findsNothing);
        showOpenBandJournalInfo(
          tester.element(find.byType(OpenBandJournal)),
          title: CaffeineSleepPattern.infoTitle,
          body: infoBody,
        );
        await tester.pumpAndSettle();
        await tester.tap(action());
        await tester.pumpAndSettle();
        expect(find.text('Vergleich verstehen'), findsNothing);
      }

      await open(scale: 2, width: 320, height: 812);
      await pinScrollAndDismiss();

      await open(scale: 2, width: 375, height: 812);
      await pinScrollAndDismiss();

      await open(scale: 2, width: 393, height: 852);
      expect(
        tester
            .renderObject<RenderParagraph>(
              find.text(CaffeineSleepPattern.infoComparison),
            )
            .getBoxesForSelection(
              TextSelection(
                baseOffset: 0,
                extentOffset: CaffeineSleepPattern.infoComparison.length,
              ),
            )
            .length,
        4,
      );
      await pinScrollAndDismiss(capture: true);
    },
  );
}
