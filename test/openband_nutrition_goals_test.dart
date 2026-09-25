import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/health.dart';
import 'package:openstrap_edge/openband/nutrition.dart';
import 'package:openstrap_edge/openband/nutrition_goals.dart';
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
  final now = DateTime(2026, 9, 15, 9, 41);

  setUp(() => repo = galleryRepo());

  Future<void> mount(
    WidgetTester tester,
    Widget home, {
    Brightness brightness = Brightness.light,
    double scale = 1,
    double width = 393,
    double height = 852,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: RepaintBoundary(key: const ValueKey('capture'), child: child!),
        ),
        home: SizedBox(width: width, height: height, child: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  OpenBandNutritionGoals overview() => OpenBandNutritionGoals(
    repository: repo,
    day: '2026-09-15',
    now: () => now,
    synthetic: true,
  );

  OpenBandNutritionGoalsEditor editor({NutritionTargetValues? draft}) =>
      OpenBandNutritionGoalsEditor(
        repository: repo,
        day: '2026-09-15',
        now: () => now,
        synthetic: true,
        draft: draft,
      );

  group('conversion', () {
    test('fixture percents and future grams', () {
      const v = NutritionTargetValues(
        energyKcal: 2000,
        proteinG: 125,
        carbohydrateG: 240,
        fatG: 60,
      );
      expect(
        nutritionPercentOf(v.proteinG, v.energyKcal, kNutritionProteinKcal),
        25,
      );
      expect(
        nutritionPercentOf(v.carbohydrateG, v.energyKcal, kNutritionCarbKcal),
        48,
      );
      expect(nutritionPercentOf(v.fatG, v.energyKcal, kNutritionFatKcal), 27);
      expect(
        nutritionMacroKcal(
          proteinG: v.proteinG,
          carbohydrateG: v.carbohydrateG,
          fatG: v.fatG,
        ),
        2000,
      );
      expect(nutritionGramsOf(25, 2100, kNutritionProteinKcal), 131.25);
      expect(nutritionGramsOf(48, 2100, kNutritionCarbKcal), 252);
      expect(nutritionGramsOf(27, 2100, kNutritionFatKcal), 63);
      expect(nutritionPercentSumOk(25, 48, 27), isTrue);
      expect(nutritionPercentSumOk(25, 48, 22), isFalse);
    });

    test('comma and dot parse; both marks are invalid', () {
      expect(parseNutritionGoalNumber('22,5').value, 22.5);
      expect(parseNutritionGoalNumber('22.5').value, 22.5);
      expect(parseNutritionGoalNumber('22.5').value, isNot(225));
      expect(parseNutritionGoalNumber('1.234,5').bad, isTrue);
      expect(parseNutritionGoalNumber('').blank, isTrue);
      expect(parseNutritionGoalNumber('NaN').bad, isTrue);
      expect(parseNutritionGoalNumber('-1').value, -1);
      expect(parseNutritionGoalNumber('1e2').bad, isTrue);
      expect(parseNutritionGoalNumber('1e2').value, isNull);
      expect(parseNutritionGoalNumber('Infinity').bad, isTrue);
      expect(parseNutritionGoalNumber('1 2').bad, isTrue);
      expect(parseNutritionGoalNumber('1 2').value, isNull);
      expect(parseNutritionGoalNumber('1\u00a02').bad, isTrue);
      expect(parseNutritionGoalNumber('1\u00a02').value, isNull);
      expect(parseNutritionGoalNumber('  22,5  ').value, 22.5);
      expect(parseNutritionGoalNumber('\u00a0125\u00a0').value, 125);
      expect(formatNutritionGoalNumber(131.25), '131,25');
      expect(formatNutritionGoalNumber(125), '125');
      expect(formatNutritionGoalNumber(0), '0');
    });
  });

  group('compact segmented', () {
    testWidgets('g/% 44pt edge taps at 1x and 2x; disabled stays inert', (
      tester,
    ) async {
      var selected = 0;
      final taps = <int>[];
      final semantics = tester.ensureSemantics();
      try {
        Future<void> show({double scale = 1, List<bool>? enabled}) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(393, 852);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: openBandTheme(
                Brightness.light,
              ).copyWith(platform: TargetPlatform.iOS),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: Center(
                  child: StatefulBuilder(
                    builder: (context, setState) => OBSegmented(
                      compact: true,
                      labels: const ['g', '%'],
                      selected: selected,
                      enabled: enabled,
                      onChanged: (i) {
                        taps.add(i);
                        setState(() => selected = i);
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        Finder well(String label) =>
            find.ancestor(of: find.text(label), matching: find.byType(InkWell));

        Future<void> tapEdge(String label, {required bool top}) async {
          final box = tester.getRect(well(label));
          expect(box.height, greaterThanOrEqualTo(44));
          await tester.tapAt(
            Offset(box.center.dx, top ? box.top + 1 : box.bottom - 1),
          );
          await tester.pump();
        }

        await show();
        expect(tester.getSize(well('g')).height, greaterThanOrEqualTo(44));
        expect(tester.getSize(well('%')).height, greaterThanOrEqualTo(44));
        expect(
          tester.getSemantics(well('g')).rect.height,
          greaterThanOrEqualTo(44),
        );
        expect(
          tester.getSemantics(well('%')).rect.height,
          greaterThanOrEqualTo(44),
        );
        expect(tester.getSemantics(well('g')).label, 'g');
        expect(tester.getSemantics(well('%')).label, '%');
        await tapEdge('%', top: true);
        expect(selected, 1);
        expect(taps, [1]);
        await tapEdge('g', top: false);
        expect(selected, 0);
        expect(taps, [1, 0]);

        taps.clear();
        await show(enabled: const [true, false]);
        await tester.tapAt(tester.getRect(well('%')).center);
        await tester.pump();
        expect(taps, isEmpty);
        expect(selected, 0);

        taps.clear();
        await show(scale: 2);
        expect(tester.getSize(well('g')).height, greaterThanOrEqualTo(44));
        expect(tester.getSize(well('%')).height, greaterThanOrEqualTo(44));
        await tapEdge('%', top: true);
        expect(selected, 1);
        await tapEdge('g', top: false);
        expect(selected, 0);
      } finally {
        semantics.dispose();
      }
    });
  });

  group('editor', () {
    testWidgets('unset start disables save; empty is dash', (tester) async {
      await mount(tester, editor());
      expect(find.text('—'), findsWidgets);
      expect(
        tester
            .widget<FilledButton>(
              find.descendant(
                of: find.byKey(const ValueKey('nutrition-goal-save')),
                matching: find.byType(FilledButton),
              ),
            )
            .onPressed,
        isNull,
      );
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/nutrition-goal-unset.png'),
      );
    }, tags: const ['golden']);

    testWidgets('grams fixture, toggle retains bits, percent energy recasts', (
      tester,
    ) async {
      await repo.seedNutritionGoals();
      await mount(tester, editor());
      expect(find.text('2000'), findsOneWidget);
      expect(find.text('125'), findsOneWidget);
      expect(find.text('240'), findsOneWidget);
      expect(find.text('60'), findsOneWidget);
      expect(find.text('2.000 kcal'), findsOneWidget);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/nutrition-goal-editor.png'),
      );

      await tester.tap(find.text('%'));
      await tester.pump();
      expect(find.text('25'), findsOneWidget);
      expect(find.text('48'), findsOneWidget);
      expect(find.text('27'), findsOneWidget);
      expect(find.text('100 %'), findsOneWidget);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/nutrition-goal-percent.png'),
      );

      await tester.tap(find.text('g'));
      await tester.pump();
      expect(find.text('125'), findsOneWidget);
      await tester.tap(find.text('Gültig ab'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('16'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('übernehmen'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nutrition-goal-save')));
      await tester.pumpAndSettle();
      final applied = await repo.readNutritionTargets('2026-09-16');
      expect(applied.effectiveDay, '2026-09-16');
      expect(applied.revision, 1);
      expect(applied.values.proteinG, 125);
      expect(applied.values.carbohydrateG, 240);
      expect(applied.values.fatG, 60);
      expect(applied.values.energyKcal, 2000);

      await mount(tester, editor());
      await tester.enterText(
        find.byKey(const ValueKey('nutrition-goal-energy')),
        '2100',
      );
      await tester.pump();
      expect(find.text('125'), findsOneWidget);
      expect(find.text('240'), findsOneWidget);
      expect(find.text('60'), findsOneWidget);
      expect(find.text('131,25'), findsNothing);

      await mount(tester, editor());
      await tester.tap(find.text('%'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('nutrition-goal-energy')),
        '2100',
      );
      await tester.pump();
      await tester.tap(find.text('g'));
      await tester.pump();
      expect(find.text('131,25'), findsOneWidget);
      expect(find.text('252'), findsOneWidget);
      expect(find.text('63'), findsOneWidget);
    }, tags: const ['golden']);

    testWidgets('invalid 0, NaN, sum 95 and missing refuse save', (
      tester,
    ) async {
      await repo.seedNutritionGoals();
      await mount(tester, editor());
      Future<NutritionTargetValues> stored() async =>
          (await repo.readNutritionTargets('2026-09-15')).values;

      await tester.enterText(
        find.byKey(const ValueKey('nutrition-goal-energy')),
        '0',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('nutrition-goal-save')));
      await tester.pump();
      expect(find.byType(OpenBandNutritionGoalsEditor), findsOneWidget);
      expect((await stored()).energyKcal, 2000);

      await tester.enterText(
        find.byKey(const ValueKey('nutrition-goal-energy')),
        '-1',
      );
      await tester.pump();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('nutrition-goal-energy')),
            )
            .controller!
            .text,
        '-1',
      );
      await tester.tap(find.byKey(const ValueKey('nutrition-goal-save')));
      await tester.pump();
      expect((await stored()).energyKcal, 2000);

      await tester.enterText(
        find.byKey(const ValueKey('nutrition-goal-energy')),
        'NaN',
      );
      await tester.pump();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('nutrition-goal-energy')),
            )
            .controller!
            .text,
        'NaN',
      );
      await tester.tap(find.byKey(const ValueKey('nutrition-goal-save')));
      await tester.pump();
      expect((await stored()).energyKcal, 2000);

      await tester.enterText(
        find.byKey(const ValueKey('nutrition-goal-energy')),
        '1e2',
      );
      await tester.pump();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('nutrition-goal-energy')),
            )
            .controller!
            .text,
        '1e2',
      );
      await tester.tap(find.byKey(const ValueKey('nutrition-goal-save')));
      await tester.pump();
      expect((await stored()).energyKcal, 2000);
      expect((await stored()).energyKcal, isNot(12));
      expect((await stored()).energyKcal, isNot(100));

      await tester.enterText(
        find.byKey(const ValueKey('nutrition-goal-energy')),
        '1 2',
      );
      await tester.pump();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('nutrition-goal-energy')),
            )
            .controller!
            .text,
        '1 2',
      );
      await tester.tap(find.byKey(const ValueKey('nutrition-goal-save')));
      await tester.pump();
      expect((await stored()).energyKcal, 2000);
      expect((await stored()).energyKcal, isNot(12));

      await tester.enterText(
        find.byKey(const ValueKey('nutrition-goal-energy')),
        '1\u00a02',
      );
      await tester.pump();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('nutrition-goal-energy')),
            )
            .controller!
            .text,
        '1\u00a02',
      );
      await tester.tap(find.byKey(const ValueKey('nutrition-goal-save')));
      await tester.pump();
      expect((await stored()).energyKcal, 2000);
      expect((await stored()).energyKcal, isNot(12));

      await tester.enterText(
        find.byKey(const ValueKey('nutrition-goal-energy')),
        '2000',
      );
      await tester.pump();
      await tester.tap(find.text('%'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('nutrition-goal-fat')),
        '22',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('nutrition-goal-save')));
      await tester.pump();
      expect(find.text('Die Summe muss 100 % ergeben.'), findsOneWidget);
      expect((await stored()).fatG, 60);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/nutrition-goal-invalid.png'),
      );

      await tester.enterText(
        find.byKey(const ValueKey('nutrition-goal-fat')),
        '',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('nutrition-goal-save')));
      await tester.pump();
      expect(find.byType(OpenBandNutritionGoalsEditor), findsOneWidget);
    }, tags: const ['golden']);

    testWidgets('comma parse saves 22.5 not 225', (tester) async {
      await repo.saveNutritionTargets(
        '2026-09-15',
        const NutritionTargetValues(energyKcal: 2000, proteinG: 20),
      );
      await mount(tester, editor());
      await tester.enterText(
        find.byKey(const ValueKey('nutrition-goal-protein')),
        '22,5',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('nutrition-goal-save')));
      await tester.pumpAndSettle();
      expect(
        (await repo.readNutritionTargets('2026-09-15')).values.proteinG,
        22.5,
      );
    });

    testWidgets('saved then read-fail does not write again', (tester) async {
      await repo.seedNutritionGoals(withFuture: false);
      await mount(tester, editor());
      await tester.enterText(
        find.byKey(const ValueKey('nutrition-goal-energy')),
        '1800',
      );
      await tester.pump();
      repo.failNutritionTargetRead = true;
      await tester.tap(find.byKey(const ValueKey('nutrition-goal-save')));
      await tester.pumpAndSettle();
      expect(find.text('Ziele nicht geladen'), findsOneWidget);
      expect(find.text('Speichern fehlgeschlagen'), findsNothing);
      repo.failNutritionTargetRead = false;
      expect((await repo.listNutritionTargetChanges()), hasLength(1));
      expect(
        (await repo.readNutritionTargets('2026-09-15')).values.energyKcal,
        1800,
      );
      await tester.tap(find.text('Erneut'));
      await tester.pumpAndSettle();
      expect(find.byType(OpenBandNutritionGoalsEditor), findsNothing);
      expect((await repo.listNutritionTargetChanges()), hasLength(1));
    });

    testWidgets('CAS conflict keeps draft; reload is behind confirm', (
      tester,
    ) async {
      await repo.seedNutritionGoals(withFuture: false);
      await mount(tester, editor());
      await tester.enterText(
        find.byKey(const ValueKey('nutrition-goal-energy')),
        '1600',
      );
      await tester.pump();
      await repo.saveNutritionTargets(
        '2026-09-15',
        const NutritionTargetValues(energyKcal: 1700),
        expectedRevision: 1,
      );
      await tester.tap(find.byKey(const ValueKey('nutrition-goal-save')));
      await tester.pumpAndSettle();
      expect(find.text('Ziele wurden inzwischen geändert.'), findsOneWidget);
      expect(find.text('1600'), findsOneWidget);
      await tester.tap(find.text('Neu laden'));
      await tester.pumpAndSettle();
      expect(find.text('Änderungen verwerfen?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ob-confirm-no')));
      await tester.pumpAndSettle();
      expect(find.text('1600'), findsOneWidget);
    });

    testWidgets('unsaved back asks confirm; saving disables back', (
      tester,
    ) async {
      await repo.seedNutritionGoals(withFuture: false);
      final barrier = Completer<void>();
      repo.nutritionTargetWriteBarrier = barrier.future;
      await mount(tester, editor());
      await tester.enterText(
        find.byKey(const ValueKey('nutrition-goal-energy')),
        '1900',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('nutrition-goal-save')));
      await tester.pump();
      await tester.tap(find.byTooltip('Zurück'));
      await tester.pump();
      expect(find.byType(OpenBandNutritionGoalsEditor), findsOneWidget);
      barrier.complete();
      await tester.pumpAndSettle();
      expect(
        (await repo.readNutritionTargets('2026-09-15')).values.energyKcal,
        1900,
      );

      await mount(tester, editor());
      await tester.enterText(
        find.byKey(const ValueKey('nutrition-goal-energy')),
        '1500',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Zurück'));
      await tester.pumpAndSettle();
      expect(find.text('Änderungen verwerfen?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ob-confirm-no')));
      await tester.pumpAndSettle();
      expect(find.byType(OpenBandNutritionGoalsEditor), findsOneWidget);
    });

    testWidgets('write failure keeps draft and retries once', (tester) async {
      await repo.seedNutritionGoals(withFuture: false);
      await mount(tester, editor());
      await tester.enterText(
        find.byKey(const ValueKey('nutrition-goal-energy')),
        '1550',
      );
      await tester.pump();
      repo.failNutritionTargetWrite = true;
      await tester.tap(find.byKey(const ValueKey('nutrition-goal-save')));
      await tester.pumpAndSettle();
      expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
      expect(find.text('1550'), findsOneWidget);
      expect(
        (await repo.readNutritionTargets('2026-09-15')).values.energyKcal,
        2000,
      );
      repo.failNutritionTargetWrite = false;
      await tester.tap(find.text('Erneut speichern'));
      await tester.pumpAndSettle();
      expect(
        (await repo.readNutritionTargets('2026-09-15')).values.energyKcal,
        1550,
      );
    });

    testWidgets('double save is one write', (tester) async {
      await repo.seedNutritionGoals(withFuture: false);
      final barrier = Completer<void>();
      repo.nutritionTargetWriteBarrier = barrier.future;
      await mount(tester, editor());
      await tester.enterText(
        find.byKey(const ValueKey('nutrition-goal-energy')),
        '1650',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('nutrition-goal-save')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('nutrition-goal-save')));
      await tester.pump();
      barrier.complete();
      await tester.pumpAndSettle();
      expect((await repo.listNutritionTargetChanges()).single.revision, 2);
    });

    testWidgets('2x and 320 do not overflow', (tester) async {
      await repo.seedNutritionGoals();
      await mount(tester, editor(), scale: 2);
      expect(tester.takeException(), isNull);
      expect(find.text('ERNÄHRUNGS-\nZIELE'), findsOneWidget);
      expect(find.byIcon(LucideIcons.chevronRight), findsWidgets);
      expect(find.text('Ernährungsziele'), findsNothing);
      final energy = tester.widget<TextField>(
        find.byKey(const ValueKey('nutrition-goal-energy')),
      );
      expect(energy.style!.fontSize, 28);
      final value = tester.getSize(find.text('2000').first);
      expect(value.height, lessThan(80));
      expect(value.width, greaterThan(40));
      final makro = tester.getSize(find.text('Makronährstoffe'));
      expect(makro.height, lessThan(50));
      expect(tester.getSize(find.text('g').first).width, greaterThan(8));
      expect(tester.getSize(find.text('%').first).width, greaterThan(8));
      expect(tester.getSize(find.byType(OBSegmented)).width, 146);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('nutrition-goal-energy')))
            .width,
        greaterThan(200),
      );
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/nutrition-goal-editor-2x.png'),
      );

      await mount(tester, editor(), width: 320, height: 568);
      expect(tester.takeException(), isNull);
      expect(find.text('ERNÄHRUNGSZIELE'), findsOneWidget);
      expect(find.text('ERNÄHRUNGS-\nZIELE'), findsNothing);
      final narrowEnergy = tester.widget<TextField>(
        find.byKey(const ValueKey('nutrition-goal-energy')),
      );
      expect(narrowEnergy.style!.fontSize, 28);
      expect(tester.getSize(find.text('2000').first).height, lessThan(50));
      expect(tester.getSize(find.byType(OBSegmented)).width, 102);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/nutrition-goal-editor-320.png'),
      );

      await mount(tester, editor(), width: 375, height: 667);
      expect(tester.takeException(), isNull);
    }, tags: const ['golden']);

    testWidgets('dark grams editor', (tester) async {
      await repo.seedNutritionGoals();
      await mount(tester, editor(), brightness: Brightness.dark);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/nutrition-goal-editor-dark.png'),
      );
      await mount(tester, editor(), brightness: Brightness.dark, scale: 2);
      expect(find.text('ERNÄHRUNGS-\nZIELE'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('nutrition-goal-energy')),
            )
            .style!
            .fontSize,
        28,
      );
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/nutrition-goal-editor-2x-dark.png'),
      );
    }, tags: const ['golden']);
  });

  group('overview history clear legacy', () {
    testWidgets('overview and history with planned future', (tester) async {
      await repo.seedNutritionGoals();
      await mount(tester, overview());
      expect(find.text('Ab 15. September'), findsOneWidget);
      expect(find.text('2.000'), findsOneWidget);
      expect(find.byIcon(LucideIcons.history), findsOneWidget);
      final andern = tester.getRect(
        find.widgetWithText(FilledButton, 'Ändern'),
      );
      expect(andern.left, greaterThan(24));
      final remove = tester.getRect(find.text('Ziele entfernen'));
      expect((remove.center.dx - 196.5).abs(), lessThan(24));
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/nutrition-goal-overview.png'),
      );
      await tester.tap(find.text('Verlauf'));
      await tester.pumpAndSettle();
      expect(find.text('Geplant'), findsOneWidget);
      expect(find.text('131,25 g'), findsOneWidget);
      expect(find.text('20. September'), findsOneWidget);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/nutrition-goal-history.png'),
      );
    }, tags: const ['golden']);

    testWidgets('overview dark and 2x do not overflow the macro row', (
      tester,
    ) async {
      await repo.seedNutritionGoals();
      await mount(tester, overview(), brightness: Brightness.dark);
      expect(tester.takeException(), isNull);
      expect(find.text('Ändern'), findsOneWidget);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/nutrition-goal-overview-dark.png'),
      );
      await mount(tester, overview(), scale: 2);
      expect(tester.takeException(), isNull);
      expect(find.text('Kohlenhydrate'), findsOneWidget);
      expect(find.byIcon(LucideIcons.history), findsOneWidget);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/nutrition-goal-overview-2x.png'),
      );
    }, tags: const ['golden']);

    testWidgets('no-goal overview is empty not a default', (tester) async {
      await mount(tester, overview());
      expect(find.text('Keine Ziele'), findsOneWidget);
      expect(find.text('Ziele festlegen'), findsOneWidget);
      expect(find.text('2.000'), findsNothing);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/nutrition-goal-empty.png'),
      );
    }, tags: const ['golden']);

    testWidgets('clear writes empty boundary and keeps earlier row', (
      tester,
    ) async {
      await repo.seedNutritionGoals();
      await mount(tester, overview());
      await tester.tap(find.text('Ziele entfernen'));
      await tester.pumpAndSettle();
      expect(find.text('Ziele entfernen?'), findsOneWidget);
      expect(find.text('Ab 15. September'), findsWidgets);
      await tester.tap(find.text('Entfernen'));
      await tester.pumpAndSettle();
      expect(find.text('Keine Ziele'), findsOneWidget);
      expect(
        (await repo.readNutritionTargets('2026-09-15')).values.hasAny,
        isFalse,
      );
      expect((await repo.readNutritionTargets('2026-09-14')).origin, isNull);
      expect(
        (await repo.listNutritionTargetChanges()).map((c) => c.validFromDay),
        ['2026-09-15', '2026-09-20'],
      );
    });

    testWidgets('stale-revision clear keeps concurrent target', (tester) async {
      await repo.seedNutritionGoals();
      await mount(tester, overview());
      await repo.saveNutritionTargets(
        '2026-09-15',
        const NutritionTargetValues(energyKcal: 1700, proteinG: 110),
        expectedRevision: 1,
      );
      await tester.tap(find.text('Ziele entfernen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entfernen'));
      await tester.pumpAndSettle();
      expect(find.text('Ziele inzwischen geändert.'), findsOneWidget);
      expect(find.text('2.000'), findsOneWidget);
      expect(find.byType(OpenBandNutritionGoalsEditor), findsNothing);
      expect(
        (await repo.readNutritionTargets('2026-09-15')).values.energyKcal,
        1700,
      );
      expect(
        (await repo.readNutritionTargets('2026-09-15')).values.proteinG,
        110,
      );
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/nutrition-goal-clear-conflict.png'),
      );
      await tester.tap(find.text('Neu laden'));
      await tester.pumpAndSettle();
      expect(find.text('Ziele inzwischen geändert.'), findsNothing);
      expect(find.text('1.700'), findsOneWidget);
      expect(find.text('110'), findsOneWidget);
      expect(
        (await repo.readNutritionTargets('2026-09-15')).values.energyKcal,
        1700,
      );
    }, tags: const ['golden']);

    testWidgets('stale-revision clear conflict dark', (tester) async {
      await repo.seedNutritionGoals();
      await mount(tester, overview(), brightness: Brightness.dark);
      await repo.saveNutritionTargets(
        '2026-09-15',
        const NutritionTargetValues(energyKcal: 1700, proteinG: 110),
        expectedRevision: 1,
      );
      await tester.tap(find.text('Ziele entfernen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entfernen'));
      await tester.pumpAndSettle();
      expect(find.text('Ziele inzwischen geändert.'), findsOneWidget);
      expect(find.text('2.000'), findsOneWidget);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile(
          'openband_goldens/nutrition-goal-clear-conflict-dark.png',
        ),
      );
    }, tags: const ['golden']);

    testWidgets('clear write-fail keeps target and reopens confirm', (
      tester,
    ) async {
      await repo.seedNutritionGoals();
      await mount(tester, overview());
      repo.failNutritionTargetWrite = true;
      await tester.tap(find.text('Ziele entfernen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entfernen'));
      await tester.pumpAndSettle();
      expect(find.text('Entfernen fehlgeschlagen.'), findsOneWidget);
      expect(find.text('2.000'), findsOneWidget);
      expect(find.byType(OpenBandNutritionGoalsEditor), findsNothing);
      expect(
        (await repo.readNutritionTargets('2026-09-15')).values.energyKcal,
        2000,
      );
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/nutrition-goal-clear-error.png'),
      );
      repo.failNutritionTargetWrite = false;
      await tester.tap(find.text('Erneut'));
      await tester.pumpAndSettle();
      expect(find.text('Ziele entfernen?'), findsOneWidget);
      await tester.tap(find.text('Entfernen'));
      await tester.pumpAndSettle();
      expect(find.text('Keine Ziele'), findsOneWidget);
      expect(
        (await repo.readNutritionTargets('2026-09-15')).values.hasAny,
        isFalse,
      );
    }, tags: const ['golden']);

    testWidgets('clear write-fail dark', (tester) async {
      await repo.seedNutritionGoals();
      await mount(tester, overview(), brightness: Brightness.dark);
      repo.failNutritionTargetWrite = true;
      await tester.tap(find.text('Ziele entfernen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entfernen'));
      await tester.pumpAndSettle();
      expect(find.text('Entfernen fehlgeschlagen.'), findsOneWidget);
      expect(find.text('2.000'), findsOneWidget);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile(
          'openband_goldens/nutrition-goal-clear-error-dark.png',
        ),
      );
    }, tags: const ['golden']);

    testWidgets('clear then read-fail uses read recovery not another clear', (
      tester,
    ) async {
      await repo.seedNutritionGoals();
      await mount(tester, overview());
      final before = await repo.listNutritionTargetChanges();
      repo.failNutritionTargetRead = true;
      await tester.tap(find.text('Ziele entfernen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entfernen'));
      await tester.pumpAndSettle();
      expect(find.text('Ziele nicht geladen'), findsOneWidget);
      expect(find.text('Entfernen fehlgeschlagen.'), findsNothing);
      expect(find.byType(OpenBandNutritionGoalsEditor), findsNothing);
      repo.failNutritionTargetRead = false;
      expect(
        (await repo.readNutritionTargets('2026-09-15')).values.hasAny,
        isFalse,
      );
      expect(await repo.listNutritionTargetChanges(), hasLength(before.length));
      await tester.tap(find.text('Erneut'));
      await tester.pumpAndSettle();
      expect(find.text('Keine Ziele'), findsOneWidget);
      expect(await repo.listNutritionTargetChanges(), hasLength(before.length));
    });

    testWidgets('legacy undated has no invented date', (tester) async {
      repo.nutritionToday = () => '2026-09-15';
      repo.legacyUndatedProfile = {'kcal_target': 2000, 'protein_target': 125};
      await mount(tester, overview());
      expect(find.text('Ohne Startdatum'), findsOneWidget);
      expect(find.text('2.000'), findsOneWidget);
      expect(find.text('—'), findsWidgets);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/nutrition-goal-legacy.png'),
      );
    }, tags: const ['golden']);

    testWidgets('failed read is retry not no-goal', (tester) async {
      repo.failNutritionTargetRead = true;
      await mount(tester, overview());
      expect(find.text('Ziele nicht geladen'), findsOneWidget);
      expect(find.text('Keine Ziele'), findsNothing);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/nutrition-goal-read-error.png'),
      );
      repo.failNutritionTargetRead = false;
      await repo.seedNutritionGoals();
      await tester.tap(find.text('Erneut'));
      await tester.pumpAndSettle();
      expect(find.text('Ändern'), findsOneWidget);
    }, tags: const ['golden']);

    testWidgets('history empty boundary is visible', (tester) async {
      await repo.saveNutritionTargets(
        '2026-09-10',
        const NutritionTargetValues(energyKcal: 1800, proteinG: 90),
      );
      await repo.clearNutritionTargets('2026-09-15');
      await mount(tester, overview());
      await tester.tap(find.text('Verlauf'));
      await tester.pumpAndSettle();
      expect(find.text('Keine Ziele'), findsOneWidget);
      expect(find.text('15. September'), findsOneWidget);
      expect(find.text('10. September'), findsOneWidget);
    });
  });

  testWidgets('nutrition day exposes goals entry', (tester) async {
    await repo.seedNutritionGoals();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-15',
      now: () => now,
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(Brightness.light),
        home: OpenBandNutrition(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ernährungsziele'));
    await tester.pumpAndSettle();
    expect(find.text('Ändern'), findsOneWidget);
  });
}
