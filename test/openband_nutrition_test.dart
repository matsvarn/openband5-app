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
import 'package:openstrap_edge/openband/nutrition_browser.dart' hide obMeals;
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

  Future<void> mount(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(brightness).copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('capture'),
          child: Scaffold(
            body: OpenBandNutrition(controller: controller, onAdd: (_) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder mealSection(String label) => find.ancestor(
    of: find.text(label),
    matching: find.byType(OBMealSection),
  );

  Future<void> restoreTop(WidgetTester tester) async {
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
  }

  Future<void> expectEmptyMeal(WidgetTester tester, String label) async {
    final title = find.text(label);
    await tester.scrollUntilVisible(
      title,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final section = mealSection(label);
    expect(
      find.descendant(of: section, matching: find.text('—')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: section, matching: find.text('Teilweise')),
      findsNothing,
    );
    expect(
      find.descendant(of: section, matching: find.byType(OpenBandFoodEnergyRow)),
      findsNothing,
    );
  }

  testWidgets('day meals: partial totals, unknown entries, and empty meals', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('620'), findsOneWidget);
    expect(find.text('1 Eintrag unvollständig'), findsOneWidget);
    expect(find.textContaining('mind.'), findsNothing);
    expect(find.text('380 kcal'), findsNWidgets(2));
    expect(find.text('240 kcal'), findsNWidgets(2));
    expect(find.text('Noch nichts erfasst'), findsNothing);

    final breakfast = mealSection('Frühstück');
    expect(
      find.descendant(of: breakfast, matching: find.text('Teilweise')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: breakfast, matching: find.text('380 kcal')),
      findsNWidgets(2),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('food-row-m2')),
        matching: find.text('—'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: mealSection('Mittag'), matching: find.text('240 kcal')),
      findsNWidgets(2),
    );
    expect(find.text('Teilweise'), findsOneWidget);

    await expectEmptyMeal(tester, 'Abend');
    await expectEmptyMeal(tester, 'Zwischendurch');
    await restoreTop(tester);

    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/nutrition-light.png'),
    );
    await mount(tester, brightness: Brightness.dark);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/nutrition-dark.png'),
    );
  });

  testWidgets('food search stages a serving-sized portion', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    MealDraft? result;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () async {
                  result = await showModalBottomSheet<MealDraft>(
                    context: ctx,
                    builder: (_) => OBFoodSearchSheet(
                      repository: repo,
                      draft: MealDraft(
                        id: 'd',
                        day: '2026-09-15',
                        meal: 'dinner',
                        entries: const [],
                        updatedAt: DateTime(2026),
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'hafer');
    await tester.pumpAndSettle();
    expect(find.text('372 kcal / 100 g'), findsOneWidget);
    await tester.tap(find.text('Haferflocken'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    final e = result!.entries.single;
    expect(e.quantity, 60);
    expect(e.kcal, closeTo(223.2, .01));
    expect(e.foodKey, 'oats');
  });

  test('meal draft commits atomically and never on failure', () async {
    final draft = MealDraft(
      id: 'd1',
      day: '2026-09-15',
      meal: 'dinner',
      entries: const [
        MealDraftEntry(id: 'e1', label: 'Reis', kcal: 300, carbsG: 65),
        MealDraftEntry(id: 'e2', label: 'Tofu', kcal: 180, proteinG: 18),
      ],
      updatedAt: DateTime(2026, 9, 15, 19),
    );
    await repo.saveMealDraft(draft);
    expect((await repo.readMealDraft('2026-09-15', 'dinner'))?.id, 'd1');
    expect((await repo.readMeals('2026-09-15')).kcal.value, 620);
    repo.scenario = SyntheticScenario.saveFailure;
    await expectLater(repo.commitMealDraft(draft), throwsStateError);
    expect((await repo.readMeals('2026-09-15')).kcal.value, 620);
    expect(await repo.readMealDraft('2026-09-15', 'dinner'), isNotNull);
    repo.scenario = SyntheticScenario.complete;
    await repo.commitMealDraft(draft);
    final meals = await repo.readMeals('2026-09-15');
    expect(meals.kcal.value, 1100);
    expect(meals.entries.where((e) => e.meal == 'dinner').length, 2);
    expect(await repo.readMealDraft('2026-09-15', 'dinner'), isNull);
    await expectLater(
      repo.commitMealDraft(
        MealDraft(
          id: 'empty',
          day: '2026-09-15',
          meal: 'snack',
          entries: const [],
          updatedAt: DateTime(2026),
        ),
      ),
      throwsArgumentError,
    );
  });
}
