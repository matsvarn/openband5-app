import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/nutrition.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';

class _ParentRepo extends SyntheticOpenBandRepository {
  _ParentRepo(super.summary, super.detail) : super.fromMaps();

  final mealReads = <String>[];
  final targetReads = <String>[];
  final weekReads = <String>[];
  final recentReads = <int>[];
  final mealGates = <String, Completer<void>>{};
  final weekGates = <String, Completer<void>>{};
  final casDrafts = <MealDraft>[];
  int draftReads = 0;
  bool failDraftRead = false;
  bool failCasWrite = false;
  bool conflictFirstCas = false;
  bool throwAfterCasOnce = false;
  int casCalls = 0;
  Completer<void>? casGate;
  final extraHits = <FoodHit>[];
  bool failSearch = false;

  Completer<void> gateMeals(String day) =>
      mealGates.putIfAbsent(day, Completer<void>.new);

  Completer<void> gateWeek(String day) =>
      weekGates.putIfAbsent(day, Completer<void>.new);

  @override
  Future<DayMeals> readMeals(String day) async {
    mealReads.add(day);
    final gate = mealGates[day];
    if (gate != null) await gate.future;
    return super.readMeals(day);
  }

  @override
  Future<NutritionTargetSnapshot> readNutritionTargets(String day) async {
    targetReads.add(day);
    return super.readNutritionTargets(day);
  }

  @override
  Future<NutritionWindow> readNutritionWindow(
    String endDay, {
    int days = 7,
  }) async {
    weekReads.add(endDay);
    final gate = weekGates[endDay];
    if (gate != null) await gate.future;
    return super.readNutritionWindow(endDay, days: days);
  }

  @override
  Future<List<FoodEntry>> readRecentFoods({int limit = 12}) async {
    recentReads.add(limit);
    return super.readRecentFoods(limit: limit);
  }

  @override
  Future<MealDraft?> readMealDraft(String day, String meal) async {
    draftReads++;
    if (failDraftRead) throw StateError('synthetic meal draft read failure');
    return super.readMealDraft(day, meal);
  }

  @override
  Future<MealDraftSaveResult> compareAndSaveMealDraft({
    required MealDraft? expected,
    required MealDraft draft,
  }) async {
    casCalls++;
    casDrafts.add(draft);
    final gate = casGate;
    if (gate != null) await gate.future;
    if (failCasWrite) throw StateError('synthetic cas write failure');
    if (conflictFirstCas && casCalls == 1) {
      return MealDraftSaveResult.conflict;
    }
    final result = await super.compareAndSaveMealDraft(
      expected: expected,
      draft: draft,
    );
    if (throwAfterCasOnce) {
      throwAfterCasOnce = false;
      throw StateError('synthetic response lost after durable CAS');
    }
    return result;
  }

  @override
  Future<List<FoodHit>> searchFoods(String query) async {
    if (failSearch) throw StateError('synthetic search failure');
    final hits = await super.searchFoods(query);
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return hits;
    return [
      ...hits,
      for (final hit in extraHits)
        if (hit.label.toLowerCase().contains(q)) hit,
    ];
  }
}

_ParentRepo _galleryRepo() => _ParentRepo(
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

FoodEntry _fullRecent() => const FoodEntry(
  id: 'recent-full',
  date: '2026-09-10',
  meal: 'lunch',
  label: 'Vollkornbrot',
  quantity: 80,
  unit: 'g',
  kcal: 210,
  proteinG: 7,
  carbsG: 38,
  fatG: 3.2,
  fibreG: 6,
  sugarG: 1.1,
  satFatG: 0.6,
  sodiumMg: 380,
  ironMg: 1.4,
  calciumMg: 22,
  foodKey: 'rye',
  source: FoodSource.verified,
  sourceCode: 'verified',
  confirmed: true,
  note: 'photo-ok',
  atTs: 999,
  createdAt: 40,
  updatedAt: 41,
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

  late _ParentRepo repo;
  late OpenBandController controller;

  setUp(() {
    repo = _galleryRepo();
    controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-15',
      band: repo.band,
      now: () => DateTime(2026, 9, 15, 9, 41),
    );
  });
  tearDown(() {
    for (final gate in [...repo.mealGates.values, ...repo.weekGates.values]) {
      if (!gate.isCompleted) gate.complete();
    }
    controller.dispose();
  });

  Future<void> mount(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double scale = 1,
    double width = 393,
    double height = 852,
    int revision = 0,
    OpenBandController? existing,
    EdgeInsets padding = const EdgeInsets.only(top: 59, bottom: 34),
    ValueChanged<StateSetter>? onHost,
  }) async {
    final used = existing ?? controller;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
            padding: padding,
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: onHost == null
            ? OpenBandNutrition(controller: used, revision: revision)
            : StatefulBuilder(
                builder: (context, setState) {
                  onHost(setState);
                  return OpenBandNutrition(
                    controller: used,
                    revision: revision,
                  );
                },
              ),
      ),
    );
  }

  Future<void> pumpShown(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('week shows raw days, zero, unknown, and a distinct error', (
    tester,
  ) async {
    repo.seedFoodEntry(
      const FoodEntry(
        id: 'zero-1',
        date: '2026-09-14',
        meal: 'lunch',
        label: 'Wasser',
        kcal: 0,
        confirmed: true,
      ),
    );
    repo.seedFoodEntry(
      const FoodEntry(
        id: 'unk-kcal',
        date: '2026-09-13',
        meal: 'dinner',
        label: 'Ohne Energie',
        confirmed: true,
      ),
    );
    await mount(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Woche'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('week-row-2026-09-09')), findsOneWidget);
    expect(find.byKey(const ValueKey('week-row-2026-09-15')), findsOneWidget);
    expect(find.text('Keine Einträge'), findsWidgets);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
    expect(find.text('1 Eintrag ohne kcal'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('week-row-2026-09-13')),
        matching: find.text('1 Eintrag ohne kcal'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('week-row-2026-09-14')),
        matching: find.text('0'),
      ),
      findsOneWidget,
    );
    expect(find.text('Woche nicht geladen'), findsNothing);

    await tester.tap(find.text('Tag'));
    await tester.pumpAndSettle();
    repo.failMealsRead = true;
    await tester.tap(find.text('Woche'));
    await tester.pumpAndSettle();
    expect(find.text('Woche nicht geladen'), findsOneWidget);
    expect(find.text('Keine Einträge'), findsNothing);
    repo.failMealsRead = false;
    await tester.tap(find.text('Erneut'));
    await tester.pumpAndSettle();
    expect(find.text('Woche nicht geladen'), findsNothing);
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('week window keeps seven local DST calendar days', (
    tester,
  ) async {
    controller.dispose();
    controller = OpenBandController(
      repository: repo,
      initialDay: '2026-03-31',
      band: repo.band,
      now: () => DateTime(2026, 3, 31, 9, 41),
    );
    await mount(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Woche'));
    await tester.pumpAndSettle();
    for (final day in [
      '2026-03-25',
      '2026-03-26',
      '2026-03-27',
      '2026-03-28',
      '2026-03-29',
      '2026-03-30',
      '2026-03-31',
    ]) {
      expect(find.byKey(ValueKey('week-row-$day')), findsOneWidget);
    }
  });

  testWidgets('late prior-day meals cannot replace the selected day', (
    tester,
  ) async {
    repo.gateMeals('2026-09-15');
    await mount(tester);
    await tester.pump();
    await tester.pump();
    expect(find.text('Haferflocken mit Milch'), findsNothing);

    await tester.runAsync(() => controller.selectDay('2026-09-14'));
    await tester.pump();
    await tester.pump();
    expect(controller.selectedDay, '2026-09-14');

    repo.gateMeals('2026-09-15').complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('Haferflocken mit Milch'), findsNothing);
    expect(controller.selectedDay, '2026-09-14');
  });

  testWidgets('late prior-week window cannot replace the selected day', (
    tester,
  ) async {
    await mount(tester);
    await tester.pumpAndSettle();
    repo.gateWeek('2026-09-15');
    await tester.tap(find.text('Woche'));
    await tester.pump();
    await tester.pump();
    await tester.runAsync(() => controller.selectDay('2026-09-14'));
    await tester.pump();
    await tester.pump();
    repo.gateWeek('2026-09-15').complete();
    await tester.pump();
    await tester.pump();
    expect(controller.selectedDay, '2026-09-14');
    expect(find.byKey(const ValueKey('week-row-2026-09-15')), findsNothing);
  });

  testWidgets('repository swap discards the prior repo continuation', (
    tester,
  ) async {
    final first = repo;
    first.gateMeals('2026-09-15');
    final second = _galleryRepo();
    second.seedFoodEntry(
      const FoodEntry(
        id: 'other-1',
        date: '2026-09-15',
        meal: 'snack',
        label: 'Anderes Repo',
        kcal: 90,
        confirmed: true,
      ),
    );
    final c2 = OpenBandController(
      repository: second,
      initialDay: '2026-09-15',
      band: second.band,
      now: () => DateTime(2026, 9, 15, 9, 41),
    );
    addTearDown(c2.dispose);
    await mount(tester);
    await tester.pump();
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        debugShowCheckedModeBanner: false,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(
          Brightness.light,
        ).copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: OpenBandNutrition(controller: c2),
      ),
    );
    await tester.pumpAndSettle();
    first.gateMeals('2026-09-15').complete();
    await tester.pump();
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Anderes Repo'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Anderes Repo'), findsOneWidget);
  });

  testWidgets(
    'same-day revision reloads meals without dropping pending or Undo',
    (tester) async {
      repo.seedFoodEntry(_fullRecent());
      repo.failCasWrite = true;
      var revision = 0;
      late StateSetter setHost;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 852);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          debugShowCheckedModeBanner: false,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('de')],
          theme: openBandTheme(
            Brightness.light,
          ).copyWith(platform: TargetPlatform.iOS),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.only(top: 59, bottom: 34),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: StatefulBuilder(
            builder: (context, setState) {
              setHost = setState;
              return OpenBandNutrition(
                controller: controller,
                revision: revision,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final mealsBefore = repo.mealReads.length;
      controller.updateBand(controller.band);
      await tester.pump();
      expect(repo.mealReads.length, mealsBefore);

      await tester.tap(find.text('Lebensmittel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vollkornbrot'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abend'));
      await pumpShown(tester);
      expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
      final kept = repo.casDrafts.single.entries.single.id;

      repo.seedFoodEntry(
        const FoodEntry(
          id: 'rev-1',
          date: '2026-09-15',
          meal: 'snack',
          label: 'Revision Apfel',
          kcal: 52,
          confirmed: true,
        ),
      );
      setHost(() => revision += 1);
      await tester.pumpAndSettle();
      expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
      await tester.tap(find.text('Tag'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Revision Apfel'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Revision Apfel'), findsOneWidget);
      expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);

      repo.failCasWrite = false;
      await tester.tap(find.widgetWithText(TextButton, 'Erneut'));
      await tester.pumpAndSettle();
      expect(repo.casDrafts.last.entries.single.id, kept);
      expect(find.byType(OBMealDraftSheet), findsOneWidget);
    },
  );

  testWidgets('recent reuse copies nutrients with a new id and null stamps', (
    tester,
  ) async {
    repo.seedFoodEntry(_fullRecent());
    await repo.saveMealDraft(
      MealDraft(
        id: 'draft-2026-09-15-dinner',
        day: '2026-09-15',
        meal: 'dinner',
        entries: const [MealDraftEntry(id: 'e-old', label: 'Reis', kcal: 300)],
        updatedAt: DateTime(2026, 9, 15, 18),
      ),
    );
    await mount(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lebensmittel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vollkornbrot'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abend'));
    await tester.pumpAndSettle();
    expect(repo.casDrafts, isNotEmpty);
    final draft = repo.casDrafts.last;
    expect(draft.entries.length, 2);
    expect(draft.entries.first.id, 'e-old');
    final added = draft.entries.last;
    expect(added.id, isNot(anyOf('recent-full', 'e-old')));
    expect(added.label, 'Vollkornbrot');
    expect(added.quantity, 80);
    expect(added.unit, 'g');
    expect(added.kcal, 210);
    expect(added.proteinG, 7);
    expect(added.carbsG, 38);
    expect(added.fatG, 3.2);
    expect(added.fibreG, 6);
    expect(added.sugarG, 1.1);
    expect(added.satFatG, 0.6);
    expect(added.sodiumMg, 380);
    expect(added.ironMg, 1.4);
    expect(added.calciumMg, 22);
    expect(added.foodKey, 'rye');
    expect(added.source, FoodSource.verified);
    expect(added.sourceCode, 'verified');
    expect(added.confirmed, isTrue);
    expect(added.note, 'photo-ok');
    expect(added.atTs, isNull);
    expect(added.createdAt, isNull);
    expect(added.updatedAt, isNull);
  });

  testWidgets('recent CAS conflict retries the same new entry id', (
    tester,
  ) async {
    repo.seedFoodEntry(_fullRecent());
    repo.conflictFirstCas = true;
    await mount(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lebensmittel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vollkornbrot'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abend'));
    await pumpShown(tester);
    expect(find.text('Konflikt'), findsOneWidget);
    expect(repo.casDrafts, hasLength(1));
    final kept = repo.casDrafts.single.entries.single.id;
    await tester.tap(find.widgetWithText(TextButton, 'Erneut'));
    await tester.pumpAndSettle();
    expect(repo.casDrafts, hasLength(2));
    expect(repo.casDrafts.last.entries.single.id, kept);
    expect(find.byType(OBMealDraftSheet), findsOneWidget);
  });

  testWidgets(
    'conflict retry keeps only the requested addition over the latest base',
    (tester) async {
      repo.seedFoodEntry(_fullRecent());
      await repo.saveMealDraft(
        MealDraft(
          id: 'draft-2026-09-15-dinner',
          day: '2026-09-15',
          meal: 'dinner',
          entries: const [
            MealDraftEntry(id: 'removed-old', label: 'Alt', kcal: 10),
            MealDraftEntry(id: 'kept-old', label: 'Vorher', kcal: 20),
          ],
          updatedAt: DateTime(2026, 9, 15, 18),
        ),
      );
      repo.conflictFirstCas = true;
      await mount(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lebensmittel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vollkornbrot'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abend').last);
      await pumpShown(tester);
      expect(find.text('Konflikt'), findsOneWidget);
      final requested = repo.casDrafts.single.entries.last;

      const edited = MealDraftEntry(
        id: 'kept-old',
        label: 'Extern bearbeitet',
        quantity: 0,
        kcal: 0,
        proteinG: 0,
        carbsG: 1.23456789,
        source: FoodSource.unknown,
        sourceCode: 'external-unknown',
      );
      const concurrent = MealDraftEntry(
        id: 'concurrent-new',
        label: 'Extern neu',
        fibreG: 3.1415926,
      );
      await repo.saveMealDraft(
        MealDraft(
          id: 'latest-dinner',
          day: '2026-09-15',
          meal: 'dinner',
          entries: const [edited, concurrent],
          updatedAt: DateTime(2026, 9, 15, 19),
        ),
      );
      await tester.tap(find.widgetWithText(TextButton, 'Erneut'));
      await tester.pumpAndSettle();

      final retried = repo.casDrafts.last;
      expect(retried.id, 'latest-dinner');
      expect(retried.entries.map((entry) => entry.id), [
        'kept-old',
        'concurrent-new',
        requested.id,
      ]);
      expect(
        retried.entries,
        isNot(
          contains(
            const MealDraftEntry(id: 'removed-old', label: 'Alt', kcal: 10),
          ),
        ),
      );
      expect(retried.entries[0], edited);
      expect(retried.entries[1], concurrent);
      expect(retried.entries[2], requested);
      expect(find.byType(OBMealDraftSheet), findsOneWidget);
    },
  );

  testWidgets('failed intent remains available and double retry is guarded', (
    tester,
  ) async {
    repo.seedFoodEntry(_fullRecent());
    repo.failCasWrite = true;
    await mount(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lebensmittel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vollkornbrot'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abend').last);
    await pumpShown(tester);
    final requested = repo.casDrafts.single.entries.single;

    await tester.pump(const Duration(seconds: 9));
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Erneut'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Schließen'), findsOneWidget);
    await tester.tap(find.text('Vollkornbrot'));
    await tester.pumpAndSettle();
    expect(find.text('Mahlzeit wählen'), findsNothing);
    expect(repo.casCalls, 1);

    repo.failCasWrite = false;
    final gate = Completer<void>();
    repo.casGate = gate;
    final retry = find.descendant(
      of: find.byType(SnackBar).last,
      matching: find.widgetWithText(TextButton, 'Erneut'),
    );
    await tester.tap(retry);
    await tester.pump();
    await tester.tap(retry);
    await tester.pump();
    expect(repo.casCalls, 2);
    gate.complete();
    await tester.pumpAndSettle();
    expect(repo.casCalls, 2);
    expect(repo.casDrafts.last.entries.single, requested);
    expect(find.text('Speichern fehlgeschlagen'), findsNothing);
    expect(find.byType(OBMealDraftSheet), findsOneWidget);
  });

  testWidgets('recent CAS write failure retries the same new entry id', (
    tester,
  ) async {
    repo.seedFoodEntry(_fullRecent());
    repo.failCasWrite = true;
    await mount(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lebensmittel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vollkornbrot'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abend'));
    await pumpShown(tester);
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    final kept = repo.casDrafts.single.entries.single.id;
    repo.failCasWrite = false;
    await tester.tap(find.widgetWithText(TextButton, 'Erneut'));
    await tester.pumpAndSettle();
    expect(repo.casDrafts.last.entries.single.id, kept);
    expect(repo.casDrafts, hasLength(2));
    expect(find.byType(OBMealDraftSheet), findsOneWidget);
  });

  testWidgets('unknown CAS success retries without duplicating the addition', (
    tester,
  ) async {
    repo.seedFoodEntry(_fullRecent());
    repo.throwAfterCasOnce = true;
    await mount(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lebensmittel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vollkornbrot'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abend').last);
    await pumpShown(tester);
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    final requested = repo.casDrafts.single.entries.single;

    await tester.tap(find.widgetWithText(TextButton, 'Erneut'));
    await tester.pumpAndSettle();
    expect(repo.casDrafts, hasLength(2));
    expect(
      repo.casDrafts.last.entries.where((entry) => entry.id == requested.id),
      hasLength(1),
    );
    expect(repo.casDrafts.last.entries.single, requested);
    expect(find.byType(OBMealDraftSheet), findsOneWidget);
  });

  testWidgets('recent draft read failure keeps the pending new entry id', (
    tester,
  ) async {
    repo.seedFoodEntry(_fullRecent());
    repo.failDraftRead = true;
    await mount(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lebensmittel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vollkornbrot'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abend'));
    await pumpShown(tester);
    expect(find.text('Entwurf nicht geladen'), findsOneWidget);
    expect(repo.casDrafts, isEmpty);
    repo.failDraftRead = false;
    await tester.tap(find.widgetWithText(TextButton, 'Erneut'));
    await tester.pumpAndSettle();
    expect(repo.casDrafts, hasLength(1));
    expect(repo.casDrafts.single.entries, hasLength(1));
    expect(find.byType(OBMealDraftSheet), findsOneWidget);
  });

  testWidgets('committed read failure retries read only', (tester) async {
    repo.seedFoodEntry(_fullRecent());
    await mount(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lebensmittel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vollkornbrot'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abend'));
    await tester.pumpAndSettle();
    expect(find.byType(OBMealDraftSheet), findsOneWidget);
    repo.failMealsRead = true;
    await tester.tap(find.text('Speichern'));
    await pumpShown(tester);
    expect(find.text('Einträge konnten nicht geladen werden.'), findsOneWidget);
    expect(await repo.readMealDraft('2026-09-15', 'dinner'), isNull);
    expect(
      (await repo.readFoodEntry(
        repo.casDrafts.single.entries.single.id,
      )).missing,
      isFalse,
    );
    repo.failMealsRead = false;
    final cas = repo.casCalls;
    await tester.tap(find.widgetWithText(TextButton, 'Erneut'));
    await pumpShown(tester);
    expect(repo.casCalls, cas);
    expect(find.text('Vollkornbrot'), findsWidgets);
    expect(find.text('Einträge konnten nicht geladen werden.'), findsNothing);
  });

  testWidgets('reuse captures day before the meal picker opens', (
    tester,
  ) async {
    repo.seedFoodEntry(_fullRecent());
    await mount(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lebensmittel'));
    await tester.pumpAndSettle();
    final reads = repo.draftReads;
    await tester.tap(find.text('Vollkornbrot'));
    await tester.pumpAndSettle();
    expect(find.text('Mahlzeit wählen'), findsOneWidget);

    await tester.runAsync(() => controller.selectDay('2026-09-14'));
    await tester.pump();
    await tester.tap(find.text('Abend').last);
    await tester.pumpAndSettle();

    expect(controller.selectedDay, '2026-09-14');
    expect(repo.draftReads, reads);
    expect(repo.casCalls, 0);
    expect(find.byType(OBMealDraftSheet), findsNothing);
  });

  testWidgets('search failure clears its latch and retries', (tester) async {
    repo.failSearch = true;
    await mount(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nutrition-search')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abend').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'reis');
    await tester.pumpAndSettle();
    expect(find.text('Suche fehlgeschlagen'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Erneut'), findsOneWidget);
    expect(tester.takeException(), isNull);

    repo.failSearch = false;
    await tester.tap(find.widgetWithText(TextButton, 'Erneut'));
    await tester.pumpAndSettle();
    expect(find.text('Suche fehlgeschlagen'), findsNothing);
  });

  testWidgets('unknown serving requires an explicit portion and keeps source', (
    tester,
  ) async {
    repo.extraHits.add(
      const FoodHit(
        key: 'loose-rice',
        label: 'Reis lose',
        kcal100: 130,
        proteinG100: 2.7,
        fibreG100: 0.4,
        source: FoodSource.verified,
        sourceCode: 'verified',
      ),
    );
    await mount(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nutrition-search')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abend').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'reis');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reis lose'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('food-portion-grams')), findsOneWidget);
    expect(find.text('100'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('food-portion-grams')),
      '80',
    );
    await tester.pump();
    await tester.tap(find.text('Übernehmen').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(repo.casDrafts, isNotEmpty);
    final added = repo.casDrafts.last.entries.single;
    expect(added.quantity, 80);
    expect(added.kcal, closeTo(104, .01));
    expect(added.proteinG, closeTo(2.16, .01));
    expect(added.fibreG, closeTo(0.32, .01));
    expect(added.carbsG, isNull);
    expect(added.source, FoodSource.verified);
    expect(added.sourceCode, 'verified');
    expect(added.foodKey, 'loose-rice');
  });

  testWidgets('375 2x footer stays hittable above the bottom inset', (
    tester,
  ) async {
    await mount(tester, scale: 2, width: 375, height: 812);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Suchen'), findsOneWidget);
    expect(find.text('Lebensmittel suchen'), findsNothing);
    final search = tester.getRect(
      find.byKey(const ValueKey('nutrition-search')),
    );
    final barcode = tester.getRect(
      find.byKey(const ValueKey('nutrition-barcode')),
    );
    final add = tester.getRect(find.byKey(const ValueKey('nutrition-add')));
    expect(search.height, greaterThanOrEqualTo(44));
    expect(barcode.height, greaterThanOrEqualTo(44));
    expect(add.height, greaterThanOrEqualTo(44));
    expect(search.bottom, lessThanOrEqualTo(812 - 34 + 0.5));
    expect(barcode.bottom, lessThanOrEqualTo(812 - 34 + 0.5));
    expect(add.bottom, lessThanOrEqualTo(812 - 34 + 0.5));
    final body = tester.getRect(find.byType(ListView));
    expect(body.bottom, lessThanOrEqualTo(search.top + 0.5));
    await tester.scrollUntilVisible(
      find.text('Zwischendurch'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const ValueKey('nutrition-search'))).bottom,
      lessThanOrEqualTo(812 - 34 + 0.5),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('large meal without partial leads second row with energy', (
    tester,
  ) async {
    await mount(tester, scale: 2, width: 375, height: 812);
    await tester.pumpAndSettle();
    final title = find.text('Abend');
    final card = find.ancestor(of: title, matching: find.byType(OBCard));
    await tester.scrollUntilVisible(
      card,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final energy = find.descendant(of: card, matching: find.text('—'));
    expect(energy, findsOneWidget);
    expect(
      tester.getTopLeft(energy).dx,
      closeTo(tester.getTopLeft(title).dx, .5),
    );
    expect(
      tester.getTopLeft(energy).dy,
      greaterThan(tester.getTopLeft(title).dy),
    );
  });

  Future<void> captureParent(
    WidgetTester tester,
    String name, {
    Brightness brightness = Brightness.light,
    double scale = 1,
    double width = 393,
    double height = 852,
    String day = '2026-09-15',
    bool failMeals = false,
    bool seedRecent = false,
    Future<void> Function()? beforeCapture,
  }) async {
    // Every frame is an independent production-widget scene. This prevents a
    // previous State/repository load from making an error frame look healthy.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    controller.dispose();
    repo = _galleryRepo();
    await repo.seedNutritionGoals(withFuture: false);
    await repo.adjustWater('2026-09-15', 1250);
    if (seedRecent) repo.seedFoodEntry(_fullRecent());
    repo.failMealsRead = failMeals;
    controller = OpenBandController(
      repository: repo,
      initialDay: day,
      band: repo.band,
      now: () => DateTime(2026, 9, 15, 9, 41),
    );
    await mount(
      tester,
      brightness: brightness,
      scale: scale,
      width: width,
      height: height,
    );
    await tester.pumpAndSettle();
    if (beforeCapture != null) await beforeCapture();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/$name.png'),
    );
  }

  testWidgets('nutrition parent goldens cover representative parent states', (
    tester,
  ) async {
    await captureParent(
      tester,
      'nutrition-parent-light',
      beforeCapture: () async {
        expect(find.text('620'), findsOneWidget);
        expect(find.text('Ziel 2.000'), findsOneWidget);
        expect(find.text('1.250'), findsOneWidget);
        expect(find.text('Kaffee'), findsOneWidget);
      },
    );
    await captureParent(
      tester,
      'nutrition-parent-dark',
      brightness: Brightness.dark,
      beforeCapture: () async {
        expect(find.text('620'), findsOneWidget);
        expect(find.text('Ziel 2.000'), findsOneWidget);
      },
    );
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final suffix = brightness == Brightness.light ? 'light' : 'dark';
      await captureParent(
        tester,
        'nutrition-parent-large-$suffix',
        brightness: brightness,
        scale: 2,
        width: 375,
        height: 812,
        beforeCapture: () async {
          expect(find.text('620'), findsOneWidget);
          expect(find.text('Ziel 2.000'), findsOneWidget);
        },
      );
      await captureParent(
        tester,
        'nutrition-parent-large-scrolled-$suffix',
        brightness: brightness,
        scale: 2,
        width: 375,
        height: 812,
        beforeCapture: () async {
          await tester.scrollUntilVisible(
            find.text('Linsensalat'),
            240,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('Linsensalat'), findsOneWidget);
          expect(find.text('Kaffee'), findsOneWidget);
        },
      );
    }
    await captureParent(
      tester,
      'nutrition-parent-week',
      beforeCapture: () async {
        await tester.tap(find.text('Woche'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('week-row-2026-09-15')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('nutrition-search')), findsNothing);
      },
    );
    await captureParent(
      tester,
      'nutrition-parent-library',
      seedRecent: true,
      beforeCapture: () async {
        await tester.tap(find.text('Lebensmittel'));
        await tester.pumpAndSettle();
        expect(find.text('Vollkornbrot'), findsOneWidget);
      },
    );
    await captureParent(
      tester,
      'nutrition-parent-missing',
      day: '2026-09-14',
      beforeCapture: () async {
        expect(find.text('620'), findsNothing);
        expect(find.text('—'), findsWidgets);
        expect(
          find.text('Einträge konnten nicht geladen werden.'),
          findsNothing,
        );
      },
    );
    await captureParent(
      tester,
      'nutrition-parent-error',
      failMeals: true,
      beforeCapture: () async {
        expect(
          find.text('Einträge konnten nicht geladen werden.'),
          findsOneWidget,
        );
        expect(find.text('Haferflocken mit Milch'), findsNothing);
      },
    );
  }, tags: const ['golden']);
}
