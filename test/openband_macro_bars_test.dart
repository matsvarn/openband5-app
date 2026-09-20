import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/nutrition.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';

SyntheticOpenBandRepository galleryRepo() =>
    SyntheticOpenBandRepository.fromMaps(
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

const fixtureTargets = NutritionTargetValues(
  energyKcal: 2000,
  proteinG: 125,
  carbohydrateG: 240,
  fatG: 60,
);

DayMeals mealsOf(List<MealEntry> entries, {String day = '2026-09-15'}) {
  NutrientSum sum(double? Function(MealEntry) pick) {
    var known = 0, unknown = 0;
    var total = 0.0;
    for (final e in entries) {
      final v = pick(e);
      if (v == null) {
        unknown++;
      } else {
        known++;
        total += v;
      }
    }
    return NutrientSum(known == 0 ? null : total, known, unknown);
  }

  return DayMeals(
    day: day,
    entries: entries,
    kcal: sum((e) => e.kcal),
    proteinG: sum((e) => e.proteinG),
    carbsG: sum((e) => e.carbsG),
    fatG: sum((e) => e.fatG),
  );
}

double fillRatio(WidgetTester tester, String name) {
  final track = tester.getSize(find.byKey(ValueKey('macro-$name-track')));
  final fill = tester.getSize(find.byKey(ValueKey('macro-$name-fill')));
  expect(track.width, greaterThan(0));
  return fill.width / track.width;
}

void expectCardWidth(WidgetTester tester, double width) {
  expect(tester.getSize(find.byType(OBCard)).width, closeTo(width, 0.5));
}

void expectInlineValue(WidgetTester tester, String text) {
  final rect = tester.getRect(find.text(text));
  expect(rect.height, lessThan(22), reason: '"$text" must stay on one line');
}

void expectReadablePairGap(WidgetTester tester, String label, String value) {
  final labelBox = tester.getRect(find.text(label));
  final valueBox = tester.getRect(find.text(value));
  final paragraph = tester.renderObject<RenderParagraph>(find.text(value));
  final intrinsic = paragraph.getMaxIntrinsicWidth(double.infinity);
  final valueGlyphLeft = valueBox.right - intrinsic;
  expect(
    valueGlyphLeft - labelBox.right,
    greaterThanOrEqualTo(4),
    reason: '"$label" / "$value" pair gap',
  );
}

void expectStackedMacros(WidgetTester tester, {String carbs = 'KH'}) {
  expect(
    tester.getTopLeft(find.text('Eiweiß')).dy,
    lessThan(tester.getTopLeft(find.text('Fett')).dy),
  );
  expect(
    tester.getTopLeft(find.text('Fett')).dy,
    lessThan(tester.getTopLeft(find.text(carbs)).dy),
  );
}

void expectThreeMacroColumns(WidgetTester tester, {required bool hasTracks}) {
  final protein = tester.getTopLeft(find.text('Eiweiß'));
  final fat = tester.getTopLeft(find.text('Fett'));
  final carbs = tester.getTopLeft(find.text('KH'));
  expect(protein.dx, lessThan(fat.dx));
  expect(fat.dx, lessThan(carbs.dx));
  expect((protein.dy - fat.dy).abs(), lessThan(2));
  expect((fat.dy - carbs.dy).abs(), lessThan(2));
  if (!hasTracks) return;
  expect(
    tester.getTopLeft(find.byKey(const ValueKey('macro-protein-track'))).dy,
    closeTo(
      tester.getTopLeft(find.byKey(const ValueKey('macro-fat-track'))).dy,
      0.5,
    ),
  );
  expect(
    tester.getTopLeft(find.byKey(const ValueKey('macro-fat-track'))).dy,
    closeTo(
      tester.getTopLeft(find.byKey(const ValueKey('macro-carbs-track'))).dy,
      0.5,
    ),
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
  });

  late SyntheticOpenBandRepository repo;

  setUp(() => repo = galleryRepo());

  Future<void> mount(
    WidgetTester tester,
    DayMeals meals, {
    NutritionTargetValues? targets = fixtureTargets,
    bool targetsUnavailable = false,
    bool omitUnavailableFlag = false,
    Brightness brightness = Brightness.light,
    double scale = 1,
    double width = 393,
    double height = 852,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bars = omitUnavailableFlag
        ? OBMacroBars(meals: meals, targets: targets)
        : OBMacroBars(
            meals: meals,
            targets: targets,
            targetsUnavailable: targetsUnavailable,
          );
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
        home: Scaffold(
          backgroundColor: openBandTheme(brightness).scaffoldBackgroundColor,
          body: Center(
            child: SizedBox(
              width: width,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: RepaintBoundary(
                  key: const ValueKey('capture'),
                  child: bars,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('fixture ratios use stored values, not rounded labels', (
    tester,
  ) async {
    final meals = await repo.readMeals('2026-09-15');
    await mount(tester, meals);
    expect(meals.kcal.value, 620);
    expect(meals.proteinG.value, 26);
    expect(meals.fatG.value, 15);
    expect(meals.carbsG.value, 88);
    expect(find.text('620'), findsOneWidget);
    expect(find.text('kcal'), findsOneWidget);
    expect(find.text('Ziel 2.000'), findsOneWidget);
    expect(find.text('26 / 125 g'), findsOneWidget);
    expect(find.text('15 / 60 g'), findsOneWidget);
    expect(find.text('88 / 240 g'), findsOneWidget);
    expect(find.text('Eiweiß'), findsOneWidget);
    expect(find.text('Fett'), findsOneWidget);
    expect(find.text('KH'), findsOneWidget);
    expect(find.text('Kohlenhydrate'), findsNothing);
    expect(find.textContaining('mind.'), findsNothing);
    expect(find.textContaining('≥'), findsNothing);
    expect(fillRatio(tester, 'energy'), closeTo(620 / 2000, 0.002));
    expect(fillRatio(tester, 'protein'), closeTo(26 / 125, 0.002));
    expect(fillRatio(tester, 'fat'), closeTo(15 / 60, 0.002));
    expect(fillRatio(tester, 'carbs'), closeTo(88 / 240, 0.002));
    expect(tester.getSize(find.byKey(const ValueKey('macro-energy-track'))).height, 8);
    expect(tester.getSize(find.byKey(const ValueKey('macro-protein-track'))).height, 6);
    expectThreeMacroColumns(tester, hasTracks: true);
    expectCardWidth(tester, 361);
    expectInlineValue(tester, '26 / 125 g');
    expectInlineValue(tester, '15 / 60 g');
    expectInlineValue(tester, '88 / 240 g');
    expectReadablePairGap(tester, 'Eiweiß', '26 / 125 g');
    expectReadablePairGap(tester, 'Fett', '15 / 60 g');
    expectReadablePairGap(tester, 'KH', '88 / 240 g');
    expect(
      tester.getTopLeft(find.text('Ziel 2.000')).dx,
      greaterThan(tester.getTopLeft(find.text('kcal')).dx),
    );
    expect(
      tester.getTopLeft(find.text('Ziel 2.000')).dy,
      lessThan(tester.getTopLeft(find.text('Eiweiß')).dy),
    );
    expect(
      tester.getSemantics(find.byType(OBMacroBars)).label,
      contains('Kohlenhydrate 88 / 240 g'),
    );
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/macro-light.png'),
    );

    await mount(tester, meals, width: 375);
    expectCardWidth(tester, 343);
    expectStackedMacros(tester);
    expectInlineValue(tester, '26 / 125 g');
    expectInlineValue(tester, '15 / 60 g');
    expectInlineValue(tester, '88 / 240 g');
    expectReadablePairGap(tester, 'Eiweiß', '26 / 125 g');
    expect(find.byType(FittedBox), findsNothing);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/macro-375.png'),
    );
  });

  testWidgets('unrounded actual drives the fill, not the painted label', (
    tester,
  ) async {
    final meals = mealsOf(const [
      MealEntry(
        id: 'a',
        meal: 'lunch',
        label: 'Reis',
        kcal: 620.4,
        proteinG: 26.4,
        carbsG: 88,
        fatG: 15,
      ),
    ]);
    await mount(tester, meals);
    expect(find.text('620,4'), findsOneWidget);
    expect(find.text('26,4 / 125 g'), findsOneWidget);
    expect(fillRatio(tester, 'energy'), closeTo(620.4 / 2000, 0.002));
    expect(fillRatio(tester, 'protein'), closeTo(26.4 / 125, 0.002));
    expect(fillRatio(tester, 'energy'), isNot(closeTo(620 / 2000, 0.0001)));
  });

  testWidgets('no goal hides energy and macro tracks', (tester) async {
    final meals = await repo.readMeals('2026-09-15');
    await mount(tester, meals, targets: null);
    expect(find.text('Kein Ziel'), findsOneWidget);
    expect(find.text('Ziel 2.000'), findsNothing);
    expect(find.text('Ziel —'), findsNothing);
    expect(find.text('26 g'), findsOneWidget);
    expect(find.text('15 g'), findsOneWidget);
    expect(find.text('88 g'), findsOneWidget);
    expect(find.text('26 / 125 g'), findsNothing);
    expectInlineValue(tester, '26 g');
    expect(find.byKey(const ValueKey('macro-energy-track')), findsNothing);
    expect(find.byKey(const ValueKey('macro-protein-track')), findsNothing);
    expect(find.byKey(const ValueKey('macro-fat-track')), findsNothing);
    expect(find.byKey(const ValueKey('macro-carbs-track')), findsNothing);
    expectThreeMacroColumns(tester, hasTracks: false);
    expect(
      tester.getSemantics(find.byType(OBMacroBars)).label,
      contains('Kein Ziel'),
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/macro-unset.png'),
    );

    await mount(tester, meals, targets: const NutritionTargetValues());
    expect(find.text('Kein Ziel'), findsOneWidget);
    expect(find.byKey(const ValueKey('macro-energy-track')), findsNothing);
  });

  testWidgets('macro-specific target hides only that track', (tester) async {
    final meals = await repo.readMeals('2026-09-15');
    await mount(
      tester,
      meals,
      targets: const NutritionTargetValues(energyKcal: 2000, proteinG: 125),
    );
    expect(find.text('Ziel 2.000'), findsOneWidget);
    expect(find.text('26 / 125 g'), findsOneWidget);
    expect(find.text('15 g'), findsOneWidget);
    expect(find.text('88 g'), findsOneWidget);
    expect(find.byKey(const ValueKey('macro-energy-track')), findsOneWidget);
    expect(find.byKey(const ValueKey('macro-protein-track')), findsOneWidget);
    expect(find.byKey(const ValueKey('macro-fat-track')), findsNothing);
    expect(find.byKey(const ValueKey('macro-carbs-track')), findsNothing);
  });

  testWidgets('null measured sums stay dashes with zero fill pixels', (
    tester,
  ) async {
    final meals = mealsOf(const [
      MealEntry(id: 'm2', meal: 'breakfast', label: 'Kaffee'),
    ]);
    expect(meals.kcal.value, isNull);
    expect(meals.kcal.unknown, 1);
    await mount(tester, meals);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('— / 125 g'), findsOneWidget);
    expect(find.text('— / 60 g'), findsOneWidget);
    expect(find.text('— / 240 g'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(find.text('0 / 125 g'), findsNothing);
    expect(tester.getSize(find.byKey(const ValueKey('macro-energy-fill'))).width, 0);
    expect(tester.getSize(find.byKey(const ValueKey('macro-protein-fill'))).width, 0);
    expect(tester.getSize(find.byKey(const ValueKey('macro-fat-fill'))).width, 0);
    expect(tester.getSize(find.byKey(const ValueKey('macro-carbs-fill'))).width, 0);
    expect(find.byKey(const ValueKey('macro-energy-track')), findsOneWidget);
    expect(find.text('1 Eintrag unvollständig'), findsOneWidget);
    expect(find.textContaining('ohne Nährwerte'), findsNothing);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/macro-missing.png'),
    );
  });

  testWidgets('actual zero is 0, distinct from null', (tester) async {
    final zero = mealsOf(const [
      MealEntry(
        id: 'z',
        meal: 'snack',
        label: 'Wasser',
        kcal: 0,
        proteinG: 0,
        carbsG: 0,
        fatG: 0,
      ),
    ]);
    await mount(tester, zero);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('0 / 125 g'), findsOneWidget);
    expect(find.text('0 / 60 g'), findsOneWidget);
    expect(find.text('0 / 240 g'), findsOneWidget);
    expect(find.text('—'), findsNothing);
    expect(tester.getSize(find.byKey(const ValueKey('macro-energy-fill'))).width, 0);
    expect(tester.getSize(find.byKey(const ValueKey('macro-protein-fill'))).width, 0);
    expect(find.textContaining('ohne Nährwerte'), findsNothing);
    expect(find.textContaining('unvollständig'), findsNothing);

    final empty = mealsOf(const []);
    await mount(tester, empty);
    expect(empty.kcal.value, isNull);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(find.textContaining('ohne Nährwerte'), findsNothing);
    expect(find.textContaining('unvollständig'), findsNothing);
  });

  testWidgets('explicit 0 g target shows denominator and does not fill', (
    tester,
  ) async {
    final meals = await repo.readMeals('2026-09-15');
    await mount(
      tester,
      meals,
      targets: const NutritionTargetValues(proteinG: 0, fatG: 60),
    );
    expect(find.text('Kein Ziel'), findsOneWidget);
    expect(find.text('26 / 0 g'), findsOneWidget);
    expect(find.text('15 / 60 g'), findsOneWidget);
    expect(find.byKey(const ValueKey('macro-energy-track')), findsNothing);
    expect(find.byKey(const ValueKey('macro-protein-track')), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('macro-protein-fill'))).width, 0);
    expect(fillRatio(tester, 'fat'), closeTo(15 / 60, 0.002));
  });

  testWidgets('overage clamps fill and keeps true labels', (tester) async {
    final meals = await repo.readMeals('2026-09-15');
    await mount(
      tester,
      meals,
      targets: const NutritionTargetValues(
        energyKcal: 500,
        proteinG: 20,
        carbohydrateG: 50,
        fatG: 10,
      ),
    );
    expect(find.text('Ziel 500'), findsOneWidget);
    expect(find.text('26 / 20 g'), findsOneWidget);
    expect(find.text('15 / 10 g'), findsOneWidget);
    expect(find.text('88 / 50 g'), findsOneWidget);
    expect(fillRatio(tester, 'energy'), closeTo(1, 0.002));
    expect(fillRatio(tester, 'protein'), closeTo(1, 0.002));
    expect(fillRatio(tester, 'fat'), closeTo(1, 0.002));
    expect(fillRatio(tester, 'carbs'), closeTo(1, 0.002));
    expect(tester.getSize(find.byKey(const ValueKey('macro-energy-fill'))).width, lessThanOrEqualTo(tester.getSize(find.byKey(const ValueKey('macro-energy-track'))).width));
  });

  testWidgets('missing count uses any shown nutrient, not kcal unknown', (
    tester,
  ) async {
    final meals = mealsOf(const [
      MealEntry(
        id: '1',
        meal: 'lunch',
        label: 'Reis',
        kcal: 200,
        proteinG: null,
        carbsG: 45,
        fatG: 2,
      ),
      MealEntry(
        id: '2',
        meal: 'lunch',
        label: 'Huhn',
        kcal: 180,
        proteinG: 30,
        carbsG: 0,
        fatG: 4,
      ),
    ]);
    expect(meals.kcal.unknown, 0);
    expect(meals.proteinG.unknown, 1);
    expect(meals.proteinG.value, 30);
    expect(meals.carbsG.value, 45);
    expect(meals.carbsG.known, 2);
    expect(meals.carbsG.unknown, 0);
    await mount(tester, meals);
    expect(find.text('380'), findsOneWidget);
    expect(find.text('30 / 125 g'), findsOneWidget);
    expect(find.text('45 / 240 g'), findsOneWidget);
    expect(find.text('1 Eintrag unvollständig'), findsOneWidget);
    expect(find.textContaining('ohne Nährwerte'), findsNothing);
    expect(find.textContaining('mind.'), findsNothing);
    expect(find.textContaining('≥'), findsNothing);
    expect(fillRatio(tester, 'protein'), closeTo(30 / 125, 0.002));
    expect(fillRatio(tester, 'carbs'), closeTo(45 / 240, 0.002));

    final carbsMissing = mealsOf(const [
      MealEntry(
        id: 'c',
        meal: 'lunch',
        label: 'Huhn',
        kcal: 180,
        proteinG: 30,
        carbsG: null,
        fatG: 4,
      ),
    ]);
    expect(carbsMissing.kcal.value, 180);
    expect(carbsMissing.proteinG.value, 30);
    expect(carbsMissing.carbsG.value, isNull);
    await mount(tester, carbsMissing);
    expect(find.text('180'), findsOneWidget);
    expect(find.text('30 / 125 g'), findsOneWidget);
    expect(find.text('— / 240 g'), findsOneWidget);
    expect(find.text('1 Eintrag unvollständig'), findsOneWidget);
    expect(find.textContaining('ohne Nährwerte'), findsNothing);

    final twoPartial = mealsOf(const [
      MealEntry(
        id: 'a',
        meal: 'lunch',
        label: 'Reis',
        kcal: 200,
        proteinG: 4,
        carbsG: null,
        fatG: 2,
      ),
      MealEntry(
        id: 'b',
        meal: 'lunch',
        label: 'Huhn',
        kcal: 180,
        proteinG: 30,
        carbsG: null,
        fatG: 4,
      ),
    ]);
    await mount(tester, twoPartial);
    expect(find.text('2 Einträge unvollständig'), findsOneWidget);
    expect(find.text('1 Eintrag unvollständig'), findsNothing);
    expect(find.textContaining('ohne Nährwerte'), findsNothing);
  });

  testWidgets('dark fixture', (tester) async {
    final meals = await repo.readMeals('2026-09-15');
    await mount(tester, meals, brightness: Brightness.dark);
    expect(tester.takeException(), isNull);
    final p = OB(true);
    final proteinFill = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byKey(const ValueKey('macro-protein-fill')),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(proteinFill.color, p.pulse);
    final fatFill = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byKey(const ValueKey('macro-fat-fill')),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(fatFill.color, p.food);
    final carbsFill = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byKey(const ValueKey('macro-carbs-fill')),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(carbsFill.color, p.strain);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/macro-dark.png'),
    );
  });

  testWidgets('2x stacks full Kohlenhydrate rows', (tester) async {
    final meals = await repo.readMeals('2026-09-15');
    await mount(tester, meals, scale: 2, height: 1200);
    expect(find.text('Kohlenhydrate'), findsOneWidget);
    expect(find.text('KH'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Eiweiß')).dy,
      lessThan(tester.getTopLeft(find.text('Fett')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Fett')).dy,
      lessThan(tester.getTopLeft(find.text('Kohlenhydrate')).dy),
    );
    expect(tester.getSize(find.byKey(const ValueKey('macro-energy-track'))).height, 8);
    expect(tester.getSize(find.byKey(const ValueKey('macro-protein-track'))).height, 6);
    expect(tester.getSize(find.text('26 / 125 g')).height, lessThan(40));
    expect(
      tester.getRect(find.text('Ziel 2.000')).top,
      greaterThan(tester.getRect(find.text('620')).bottom - 4),
    );
    expect(
      tester.getRect(find.text('Ziel 2.000')).top -
          tester.getRect(find.text('620')).bottom,
      closeTo(8, 1.5),
    );
    expect(
      tester.getTopLeft(find.text('Ziel 2.000')).dx,
      closeTo(tester.getTopLeft(find.text('620')).dx, 1),
    );
    expect(
      tester.getTopLeft(find.text('Ziel 2.000')).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('macro-energy-track'))).dy),
    );
    expect(find.byType(FittedBox), findsNothing);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/macro-2x.png'),
    );
  });

  testWidgets('320 and long values wrap without clipping or shrinking', (
    tester,
  ) async {
    final meals = await repo.readMeals('2026-09-15');
    await mount(tester, meals, width: 320, height: 568);
    expect(tester.takeException(), isNull);
    expect(find.text('KH'), findsOneWidget);
    expect(find.text('Kohlenhydrate'), findsNothing);
    expectCardWidth(tester, 288);
    expect(
      tester.getTopLeft(find.text('Eiweiß')).dy,
      lessThan(tester.getTopLeft(find.text('Fett')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Fett')).dy,
      lessThan(tester.getTopLeft(find.text('KH')).dy),
    );
    expect(
      (tester.getTopLeft(find.text('Eiweiß')).dy -
              tester.getTopLeft(find.text('26 / 125 g')).dy)
          .abs(),
      lessThan(2),
    );
    expect(
      (tester.getTopLeft(find.text('Fett')).dy -
              tester.getTopLeft(find.text('15 / 60 g')).dy)
          .abs(),
      lessThan(2),
    );
    expectInlineValue(tester, '26 / 125 g');
    expectInlineValue(tester, '15 / 60 g');
    expectInlineValue(tester, '88 / 240 g');
    expect(find.byType(FittedBox), findsNothing);
    expect(
      tester
          .widget<Text>(find.text('26 / 125 g'))
          .style!
          .fontSize,
      13,
    );
    expect(
      tester.widget<Text>(find.text('620')).style!.fontSize,
      34,
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/macro-320.png'),
    );

    final long = mealsOf(const [
      MealEntry(
        id: 'l',
        meal: 'dinner',
        label: 'Buffet',
        kcal: 1234567,
        proteinG: 1234.56,
        carbsG: 9876.54,
        fatG: 4321.09,
      ),
    ]);
    await mount(
      tester,
      long,
      width: 320,
      height: 568,
      targets: const NutritionTargetValues(
        energyKcal: 9876543,
        proteinG: 9876.54,
        carbohydrateG: 1234.56,
        fatG: 8765.43,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(FittedBox), findsNothing);
    expect(find.text('1.234,56 / 9.876,54 g'), findsOneWidget);
    expect(find.text('4.321,09 / 8.765,43 g'), findsOneWidget);
    expect(find.text('9.876,54 / 1.234,56 g'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('1.234,56 / 9.876,54 g')).style!.fontSize,
      13,
    );
    expectInlineValue(tester, '1.234,56 / 9.876,54 g');
    expectInlineValue(tester, '4.321,09 / 8.765,43 g');
    expectInlineValue(tester, '9.876,54 / 1.234,56 g');
    expect(
      tester.getTopLeft(find.text('Eiweiß')).dy,
      lessThan(tester.getTopLeft(find.text('Fett')).dy),
    );
    final card = tester.getRect(find.byType(OBCard));
    final protein = tester.getRect(find.text('1.234,56 / 9.876,54 g'));
    expect(protein.right, lessThanOrEqualTo(card.right - 13.5));
    expect(protein.left, greaterThanOrEqualTo(card.left + 13.5));
    final overflows = tester.binding.takeException();
    expect(overflows, isNull);
  });

  testWidgets('375 2x and decimal targets stay unclipped', (tester) async {
    final meals = await repo.readMeals('2026-09-15');
    await mount(tester, meals, width: 375, scale: 2, height: 1400);
    expectCardWidth(tester, 343);
    expectStackedMacros(tester, carbs: 'Kohlenhydrate');
    expect(find.text('Kohlenhydrate'), findsOneWidget);
    expect(
      tester.getRect(find.text('Ziel 2.000')).top,
      greaterThan(tester.getRect(find.text('620')).bottom - 4),
    );
    expect(
      tester.getRect(find.text('Ziel 2.000')).top -
          tester.getRect(find.text('620')).bottom,
      closeTo(8, 1.5),
    );
    expect(
      tester.getTopLeft(find.text('Ziel 2.000')).dx,
      closeTo(tester.getTopLeft(find.text('620')).dx, 1),
    );
    expect(find.text('26 / 125 g'), findsOneWidget);
    expect(find.byType(FittedBox), findsNothing);
    expect(tester.widget<Text>(find.text('26 / 125 g')).style!.fontSize, 13);
    expect(tester.widget<Text>(find.text('620')).style!.fontSize, 34);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/macro-375-2x.png'),
    );

    final decimal = mealsOf(const [
      MealEntry(
        id: 'd',
        meal: 'lunch',
        label: 'Reis',
        kcal: 620.4,
        proteinG: 26.4,
        carbsG: 88.25,
        fatG: 15.5,
      ),
    ]);
    await mount(
      tester,
      decimal,
      width: 375,
      scale: 2,
      height: 1400,
      targets: const NutritionTargetValues(
        energyKcal: 2000.5,
        proteinG: 125.25,
        carbohydrateG: 240.5,
        fatG: 60.75,
      ),
    );
    expect(find.text('620,4'), findsOneWidget);
    expect(find.text('Ziel 2.000,5'), findsOneWidget);
    expect(find.text('26,4 / 125,25 g'), findsOneWidget);
    expect(find.text('15,5 / 60,75 g'), findsOneWidget);
    expect(find.text('88,25 / 240,5 g'), findsOneWidget);
    expect(
      tester.getRect(find.text('Ziel 2.000,5')).top,
      greaterThan(tester.getRect(find.text('620,4')).bottom - 4),
    );
    expect(
      tester.getTopLeft(find.text('Ziel 2.000,5')).dx,
      closeTo(tester.getTopLeft(find.text('620,4')).dx, 1),
    );
    expect(fillRatio(tester, 'protein'), closeTo(26.4 / 125.25, 0.002));
    expect(find.byType(FittedBox), findsNothing);
    expect(tester.takeException(), isNull);

    await mount(
      tester,
      decimal,
      width: 375,
      height: 852,
      targets: const NutritionTargetValues(
        energyKcal: 9876543,
        proteinG: 9876.54,
        carbohydrateG: 1234.56,
        fatG: 8765.43,
      ),
    );
    expect(find.text('Ziel 9.876.543'), findsOneWidget);
    expect(find.text('26,4 / 9.876,54 g'), findsOneWidget);
    expectStackedMacros(tester);
    final card = tester.getRect(find.byType(OBCard));
    final protein = tester.getRect(find.text('26,4 / 9.876,54 g'));
    expect(protein.right, lessThanOrEqualTo(card.right - 13.5));
    expect(protein.left, greaterThanOrEqualTo(card.left + 13.5));
    expect(find.byType(FittedBox), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy null targets stay unset, unavailable is distinct', (
    tester,
  ) async {
    final meals = await repo.readMeals('2026-09-15');
    await mount(tester, meals, targets: null, omitUnavailableFlag: true);
    expect(find.text('Kein Ziel'), findsOneWidget);
    expect(find.text('Ziel —'), findsNothing);
    expect(find.text('26 g'), findsOneWidget);
    expect(find.byKey(const ValueKey('macro-energy-track')), findsNothing);
    expect(find.byKey(const ValueKey('macro-protein-track')), findsNothing);

    await mount(tester, meals, targets: null, targetsUnavailable: false);
    expect(find.text('Kein Ziel'), findsOneWidget);
    expect(find.text('Ziel —'), findsNothing);

    await mount(tester, meals, targets: null, targetsUnavailable: true);
    expect(find.text('Ziel —'), findsOneWidget);
    expect(find.text('Kein Ziel'), findsNothing);
    expect(find.text('26 g'), findsOneWidget);
    expect(find.text('15 g'), findsOneWidget);
    expect(find.text('88 g'), findsOneWidget);
    expect(find.text('26 / 125 g'), findsNothing);
    expect(find.byKey(const ValueKey('macro-energy-track')), findsNothing);
    expect(find.byKey(const ValueKey('macro-protein-track')), findsNothing);
    expect(find.byKey(const ValueKey('macro-fat-track')), findsNothing);
    expect(find.byKey(const ValueKey('macro-carbs-track')), findsNothing);
    expectInlineValue(tester, '26 g');
    expectThreeMacroColumns(tester, hasTracks: false);
    expect(
      tester.getSemantics(find.byType(OBMacroBars)).label,
      contains('Ziel —'),
    );
    expect(
      tester.getSemantics(find.byType(OBMacroBars)).label,
      isNot(contains('Kein Ziel')),
    );
    expect(
      tester.getSemantics(find.byType(OBMacroBars)).label,
      contains('Eiweiß 26 g'),
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/macro-unavailable.png'),
    );

    await mount(
      tester,
      meals,
      targets: fixtureTargets,
      targetsUnavailable: true,
    );
    expect(find.text('Ziel —'), findsOneWidget);
    expect(find.text('Kein Ziel'), findsNothing);
    expect(find.text('26 g'), findsOneWidget);
    expect(find.text('26 / 125 g'), findsNothing);
    expect(find.text('Ziel 2.000'), findsNothing);
    expect(find.byKey(const ValueKey('macro-energy-track')), findsNothing);
    expect(find.byKey(const ValueKey('macro-protein-track')), findsNothing);
    expect(find.byKey(const ValueKey('macro-fat-fill')), findsNothing);
    expect(find.byKey(const ValueKey('macro-protein-fill')), findsNothing);
  });
}
