import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/openband/alp_tokens.dart';
import 'package:openstrap_edge/openband/nutrition_browser.dart';
import 'package:openstrap_edge/openband/settings_controls.dart';
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

  testWidgets('picker: four meal values, no default check, header gap only', (
    tester,
  ) async {
    await _pump(
      tester,
      const Align(
        alignment: Alignment.bottomCenter,
        child: OpenBandMealPickerSheet(),
      ),
    );

    expect(find.text('Mahlzeit wählen'), findsOneWidget);
    expect(find.text('Frühstück'), findsOneWidget);
    expect(find.text('Mittag'), findsOneWidget);
    expect(find.text('Abend'), findsOneWidget);
    expect(find.text('Zwischendurch'), findsOneWidget);
    expect(find.byType(OBSettingsChoiceRow), findsNWidgets(4));
    expect(find.byIcon(LucideIcons.check), findsNothing);

    final close = tester.getRect(find.byTooltip('Schließen'));
    expect(close.width, 44);
    expect(close.height, 44);

    final choiceRects = find
        .byType(OBSettingsChoiceRow)
        .evaluate()
        .map((e) => tester.getRect(find.byWidget(e.widget)))
        .toList();
    expect(choiceRects.first.top - close.bottom, 16);
    for (var i = 1; i < choiceRects.length; i++) {
      expect(choiceRects[i].top, choiceRects[i - 1].bottom);
      expect(choiceRects[i].height, greaterThanOrEqualTo(48));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('picker returns the four meal keys', (tester) async {
    String? picked;
    await _pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            picked = await showOpenBandMealPicker(context);
          },
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mittag'));
    await tester.pumpAndSettle();
    expect(picked, 'lunch');

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Frühstück'));
    await tester.pumpAndSettle();
    expect(picked, 'breakfast');
  });

  testWidgets('picker at 375 2x keeps four choices and close reachable', (
    tester,
  ) async {
    await _pump(
      tester,
      const Align(
        alignment: Alignment.bottomCenter,
        child: OpenBandMealPickerSheet(),
      ),
      size: const Size(375, 812),
      scale: 2,
    );
    for (final label in ['Frühstück', 'Mittag', 'Abend', 'Zwischendurch']) {
      await tester.ensureVisible(find.text(label));
      expect(find.text(label), findsOneWidget);
    }
    await tester.ensureVisible(find.byTooltip('Schließen'));
    expect(tester.getSize(find.byTooltip('Schließen')), const Size(44, 44));
    expect(tester.takeException(), isNull);
  });

  testWidgets('food row large stacks label then energy without clipping', (
    tester,
  ) async {
    await _pump(
      tester,
      ColoredBox(
        color: AlpColor.canvas,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            OpenBandFoodEnergyRow(
              id: 'h',
              label: 'Hähnchenbrust',
              kcal: 297,
              onTap: () {},
            ),
            const OpenBandFoodEnergyRow(id: 'k', label: 'Kaffee'),
          ],
        ),
      ),
      size: const Size(375, 812),
      scale: 2,
    );

    final chicken = tester.getRect(find.byKey(const ValueKey('food-row-h')));
    final name = tester.getRect(find.text('Hähnchenbrust'));
    final energy = tester.getRect(find.text('297 kcal'));
    expect(chicken.height, greaterThanOrEqualTo(96));
    expect(name.bottom, lessThanOrEqualTo(energy.top));
    expect(name.left, energy.left);
    expect(name.right - name.left, greaterThan(64));
    expect(chicken.contains(name.center), isTrue);
    expect(chicken.contains(energy.center), isTrue);
    expect(energy.width, greaterThan(64));
    expect(tester.widget<Text>(find.text('—')).style!.color, AlpColor.muted);
    expect(tester.takeException(), isNull);
  });

  testWidgets('food row normal keeps name flex and 64 energy lane', (
    tester,
  ) async {
    await _pump(
      tester,
      Align(
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ColoredBox(
              color: AlpColor.canvas,
              child: OpenBandFoodEnergyRow(
                id: 'h',
                label: 'Haferflocken mit Milch',
                kcal: 380,
                onTap: () {},
              ),
            ),
          ],
        ),
      ),
    );
    final row = tester.getRect(find.byKey(const ValueKey('food-row-h')));
    expect(row.height, 48);
    final name = tester.getRect(find.text('Haferflocken mit Milch'));
    final energy = tester.getRect(find.text('380 kcal'));
    expect(energy.width, 64);
    expect(name.center.dy, closeTo(energy.center.dy, 1));
    expect(name.right, lessThanOrEqualTo(energy.left));
  });

  testWidgets('footer tap targets are 44 and scanner is scanLine', (
    tester,
  ) async {
    var search = 0, barcode = 0, add = 0;
    await _pump(
      tester,
      Align(
        alignment: Alignment.bottomCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            OpenBandNutritionFooter(
              onSearch: () => search++,
              onBarcode: () => barcode++,
              onAdd: () => add++,
            ),
          ],
        ),
      ),
    );

    final searchHit = tester.getSize(
      find.byKey(const ValueKey('nutrition-search')),
    );
    expect(searchHit.height, greaterThanOrEqualTo(44));
    final barcodeHit = tester.getRect(
      find.byKey(const ValueKey('nutrition-barcode')),
    );
    expect(barcodeHit.size, const Size(44, 44));
    final addHit = tester.getRect(find.byKey(const ValueKey('nutrition-add')));
    expect(addHit.size, const Size(44, 44));
    expect(find.byIcon(LucideIcons.scanLine), findsOneWidget);
    expect(find.byIcon(LucideIcons.scanBarcode), findsNothing);

    await tester.tap(find.byKey(const ValueKey('nutrition-barcode')));
    await tester.tap(find.byKey(const ValueKey('nutrition-add')));
    await tester.tap(find.byKey(const ValueKey('nutrition-search')));
    expect(barcode, 1);
    expect(add, 1);
    expect(search, 1);

    final bar = tester.getSize(
      find
          .descendant(
            of: find.byType(OpenBandNutritionFooter),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(bar.height, 52);
    expect(find.text('Lebensmittel suchen'), findsOneWidget);
  });

  testWidgets('footer large uses Suchen and grows to 60', (tester) async {
    await _pump(
      tester,
      const Align(
        alignment: Alignment.bottomCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [OpenBandNutritionFooter()],
        ),
      ),
      size: const Size(375, 812),
      scale: 2,
    );
    expect(find.text('Suchen'), findsOneWidget);
    expect(find.text('Lebensmittel suchen'), findsNothing);
    final bar = tester.getSize(
      find
          .descendant(
            of: find.byType(OpenBandNutritionFooter),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(bar.height, greaterThanOrEqualTo(60));
    expect(
      tester.getSize(find.byKey(const ValueKey('nutrition-barcode'))),
      const Size(44, 44),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('footer honors padding and viewPadding bottom insets', (
    tester,
  ) async {
    Future<double> lowestHitTarget({
      required EdgeInsets padding,
      required EdgeInsets viewPadding,
    }) async {
      await _pump(
        tester,
        const SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(child: SizedBox()),
              OpenBandNutritionFooter(),
            ],
          ),
        ),
        size: const Size(375, 812),
        scale: 2,
        padding: padding,
        viewPadding: viewPadding,
      );
      final bottoms = [
        for (final key in const [
          'nutrition-search',
          'nutrition-barcode',
          'nutrition-add',
        ])
          tester.getRect(find.byKey(ValueKey(key))).bottom,
      ];
      return bottoms.reduce((a, b) => a > b ? a : b);
    }

    expect(
      await lowestHitTarget(
        padding: const EdgeInsets.only(bottom: 34),
        viewPadding: EdgeInsets.zero,
      ),
      lessThanOrEqualTo(778.5),
    );
    expect(
      await lowestHitTarget(
        padding: EdgeInsets.zero,
        viewPadding: const EdgeInsets.only(bottom: 34),
      ),
      lessThanOrEqualTo(778.5),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('week unknown, zero, empty and partial stay distinct', (
    tester,
  ) async {
    await _pump(
      tester,
      OpenBandNutritionWeek(
        days: [
          _day('2026-09-09', [_food('a', 'Hafer', kcal: 420)]),
          _day('2026-09-10', [
            _food('b', 'Salat', kcal: 780),
            _food('c', 'Kaffee'),
          ]),
          _day('2026-09-11'),
          _day('2026-09-12', [_food('z', 'Wasser', kcal: 0)]),
          _day('2026-09-13', [_food('u', 'Espresso')]),
        ],
      ),
    );

    expect(find.text('Erfasste Energie'), findsOneWidget);
    expect(find.text('kcal'), findsOneWidget);
    expect(find.text('Keine Einträge'), findsOneWidget);
    expect(find.text('1 Eintrag ohne kcal'), findsNWidgets(2));
    expect(find.text('420'), findsOneWidget);
    expect(find.text('780'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2));

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('week-row-2026-09-09')),
        matching: find.byType(ClipRRect),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('week-row-2026-09-11')),
        matching: find.byType(ClipRRect),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('week-row-2026-09-12')),
        matching: find.byType(ClipRRect),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('week-row-2026-09-13')),
        matching: find.byType(ClipRRect),
      ),
      findsNothing,
    );
    final positiveBar = tester.getSize(
      find.byKey(const ValueKey('week-bar-2026-09-09')),
    );
    expect(positiveBar.width, greaterThan(0));
    expect(positiveBar.height, 8);
    expect(find.byKey(const ValueKey('week-bar-2026-09-11')), findsNothing);
    expect(find.byKey(const ValueKey('week-bar-2026-09-12')), findsNothing);
    expect(find.byKey(const ValueKey('week-bar-2026-09-13')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('library card uses Paper labels and food rows', (tester) async {
    await _pump(
      tester,
      OpenBandRecentFoods(
        foods: [
          _food('1', 'Haferflocken mit Milch', kcal: 380),
          _food('2', 'Linsensalat', kcal: 240),
          _food('3', 'Kaffee'),
        ],
        onReuse: (_) {},
      ),
    );
    expect(find.text('Zuletzt verwendet'), findsOneWidget);
    expect(find.text('Haferflocken mit Milch'), findsOneWidget);
    expect(find.text('380 kcal'), findsOneWidget);
    expect(find.text('240 kcal'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.textContaining('g'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picker 2x screenshot', (tester) async {
    await _pump(
      tester,
      const ColoredBox(
        color: AlpColor.well,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: RepaintBoundary(
            key: ValueKey('capture'),
            child: OpenBandMealPickerSheet(),
          ),
        ),
      ),
      size: const Size(375, 812),
      scale: 2,
    );
    expect(find.text('Zwischendurch'), findsOneWidget);
    await _capture(tester, find.byKey(const ValueKey('capture')), 'picker-2x');
  }, tags: const ['golden']);

  testWidgets('light picker screenshot', (tester) async {
    await _pump(
      tester,
      const ColoredBox(
        color: AlpColor.well,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: RepaintBoundary(
            key: ValueKey('capture'),
            child: OpenBandMealPickerSheet(),
          ),
        ),
      ),
    );
    await _capture(tester, find.byKey(const ValueKey('capture')), 'picker');
  }, tags: const ['golden']);

  testWidgets('food rows large screenshot', (tester) async {
    await _pump(
      tester,
      ColoredBox(
        color: AlpColor.well,
        child: Center(
          child: RepaintBoundary(
            key: const ValueKey('capture'),
            child: SizedBox(
              width: 343,
              child: OBCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    OpenBandFoodEnergyRow(
                      id: 'h',
                      label: 'Hähnchenbrust',
                      kcal: 297,
                    ),
                    OpenBandFoodEnergyRow(
                      id: 'r',
                      label: 'Reis, gekocht',
                      kcal: 323,
                    ),
                    OpenBandFoodEnergyRow(id: 'k', label: 'Kaffee'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      size: const Size(375, 812),
      scale: 2,
    );
    expect(find.text('Hähnchenbrust'), findsOneWidget);
    expect(find.text('297 kcal'), findsOneWidget);
    await _capture(tester, find.byKey(const ValueKey('capture')), 'food-large');
  }, tags: const ['golden']);

  testWidgets('footer light dark and large screenshots', (tester) async {
    Future<void> shot(Brightness brightness, double scale, String name) async {
      await _pump(
        tester,
        ColoredBox(
          color: brightness == Brightness.dark
              ? AlpColor.darkCanvas
              : AlpColor.well,
          child: const Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RepaintBoundary(
                  key: ValueKey('capture'),
                  child: OpenBandNutritionFooter(),
                ),
              ],
            ),
          ),
        ),
        brightness: brightness,
        size: scale == 2 ? const Size(375, 812) : const Size(393, 852),
        scale: scale,
      );
      expect(
        find.text(scale == 2 ? 'Suchen' : 'Lebensmittel suchen'),
        findsOneWidget,
      );
      await _capture(tester, find.byKey(const ValueKey('capture')), name);
    }

    await shot(Brightness.light, 1, 'footer');
    await shot(Brightness.dark, 1, 'footer-dark');
    await shot(Brightness.light, 2, 'footer-large');
  }, tags: const ['golden']);

  testWidgets('week screenshot', (tester) async {
    await _pump(
      tester,
      ColoredBox(
        color: AlpColor.well,
        child: RepaintBoundary(
          key: const ValueKey('capture'),
          child: OpenBandNutritionWeek(
            days: [
              _day('2026-09-09', [_food('a', 'Hafer', kcal: 420)]),
              _day('2026-09-10', [
                _food('b', 'Salat', kcal: 780),
                _food('c', 'Kaffee'),
              ]),
              _day('2026-09-11'),
              _day('2026-09-12', [_food('d', 'Abend', kcal: 1180)]),
              _day('2026-09-13', [_food('e', 'So', kcal: 1060)]),
              _day('2026-09-14', [_food('f', 'Mo', kcal: 920)]),
              _day('2026-09-15', [
                _food('g', 'Mittag', kcal: 620),
                _food('h', 'Kaffee'),
              ]),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Erfasste Energie'), findsOneWidget);
    expect(find.text('Keine Einträge'), findsOneWidget);
    await _capture(tester, find.byKey(const ValueKey('capture')), 'week');
  }, tags: const ['golden']);

  testWidgets('library screenshot', (tester) async {
    await _pump(
      tester,
      ColoredBox(
        color: AlpColor.well,
        child: RepaintBoundary(
          key: const ValueKey('capture'),
          child: OpenBandRecentFoods(
            foods: [
              _food('1', 'Haferflocken mit Milch', kcal: 380),
              _food('2', 'Linsensalat', kcal: 240),
              _food('3', 'Kaffee'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Zuletzt verwendet'), findsOneWidget);
    await _capture(tester, find.byKey(const ValueKey('capture')), 'library');
  }, tags: const ['golden']);
}

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  Brightness brightness = Brightness.light,
  Size size = const Size(393, 852),
  double scale = 1,
  EdgeInsets padding = const EdgeInsets.only(top: 59, bottom: 34),
  EdgeInsets viewPadding = const EdgeInsets.only(top: 59, bottom: 34),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      locale: const Locale('de'),
      debugShowCheckedModeBanner: false,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('de')],
      theme: openBandTheme(brightness).copyWith(platform: TargetPlatform.iOS),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          padding: padding,
          viewPadding: viewPadding,
          viewInsets: EdgeInsets.zero,
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: Scaffold(backgroundColor: Colors.transparent, body: home),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, Finder finder, String name) async {
  expect(finder, findsOneWidget);
  expect(tester.takeException(), isNull);
  await tester.pump();
  await expectLater(
    finder,
    matchesGoldenFile('openband_goldens/nutrition-browser-$name.png'),
  );
}

NutritionDay _day(String date, [List<FoodEntry> entries = const []]) =>
    rollupDay(date, entries, today: '2026-09-20');

FoodEntry _food(String id, String label, {double? kcal}) => FoodEntry(
  id: id,
  date: '2026-09-15',
  meal: 'lunch',
  label: label,
  kcal: kcal,
);
