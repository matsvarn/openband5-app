import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/openband/confirm_sheet.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/meal_entry.dart';
import 'package:openstrap_edge/openband/settings_controls.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/openband/time.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

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

FoodEntry oats({
  String id = 'oats',
  String date = '2026-09-15',
  String meal = 'breakfast',
  String label = 'Haferflocken mit Milch',
  int? atTs,
  double? quantity,
  String unit = 'g',
  double? kcal = 380,
  double? proteinG = 18,
  double? carbsG = 56,
  double? fatG = 12,
  double? fibreG,
  double? sugarG,
  double? satFatG,
  double? sodiumMg,
  double? ironMg,
  double? calciumMg,
  FoodSource source = FoodSource.manual,
  String? sourceCode,
  bool confirmed = true,
  String note = '',
  int createdAt = 1000,
  int updatedAt = 1000,
  String? foodKey = 'oats',
}) => FoodEntry(
  id: id,
  date: date,
  meal: meal,
  label: label,
  atTs: atTs,
  foodKey: foodKey,
  quantity: quantity,
  unit: unit,
  kcal: kcal,
  proteinG: proteinG,
  carbsG: carbsG,
  fatG: fatG,
  fibreG: fibreG,
  sugarG: sugarG,
  satFatG: satFatG,
  sodiumMg: sodiumMg,
  ironMg: ironMg,
  calciumMg: calciumMg,
  source: source,
  sourceCode: sourceCode ?? source.name,
  confirmed: confirmed,
  note: note,
  createdAt: createdAt,
  updatedAt: updatedAt,
);

tz.TZDateTime berlinAt(
  int year,
  int month,
  int day,
  int hour,
  int minute, [
  int second = 0,
]) {
  tzdata.initializeTimeZones();
  return tz.TZDateTime(
    tz.getLocation('Europe/Berlin'),
    year,
    month,
    day,
    hour,
    minute,
    second,
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
    final icons = FontLoader('packages/lucide_icons_flutter/Lucide')
      ..addFont(
        rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
      );
    await icons.load();
  });

  late SyntheticOpenBandRepository repo;
  final now = DateTime(2026, 9, 15, 9, 41);

  setUp(() {
    repo = galleryRepo();
    repo.seedFoodEntry(oats());
  });

  Future<void> mount(
    WidgetTester tester, {
    String id = 'oats',
    String day = '2026-09-15',
    Brightness brightness = Brightness.light,
    double scale = 1,
    double width = 393,
    double height = 852,
    bool synthetic = false,
    double viewInsetBottom = 0,
    String? zone,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    tester.view.viewInsets = FakeViewPadding(bottom: viewInsetBottom);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
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
          child: RepaintBoundary(
            key: const ValueKey('capture'),
            child: child!,
          ),
        ),
        home: SizedBox(
          width: width,
          height: height,
          child: OpenBandFoodEntry(
            repository: repo,
            id: id,
            day: day,
            synthetic: synthetic,
            now: () => now,
            zone: zone,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<FoodEntryRouteResult?> mountPushed(
    WidgetTester tester, {
    String id = 'oats',
    String day = '2026-09-15',
  }) async {
    FoodEntryRouteResult? result;
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
        theme: openBandTheme(Brightness.light).copyWith(
          platform: TargetPlatform.iOS,
        ),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await openOpenBandFoodEntry(
                context,
                repository: repo,
                id: id,
                day: day,
                now: () => now,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('detail shows stored day, dashes, macros and pencil header', (
    tester,
  ) async {
    await mount(tester, day: '2026-09-14');
    expect(find.text('Eintrag'), findsOneWidget);
    expect(find.text('15. September'), findsOneWidget);
    expect(find.text('14. September'), findsNothing);
    expect(find.text('Frühstück'), findsOneWidget);
    expect(find.text('Haferflocken mit Milch'), findsOneWidget);
    expect(find.text('380'), findsOneWidget);
    expect(find.text('18 g'), findsOneWidget);
    expect(find.text('12 g'), findsOneWidget);
    expect(find.text('56 g'), findsOneWidget);
    final energy = tester.getRect(find.text('380'));
    final protein = tester.getRect(find.text('Eiweiß'));
    expect(protein.top - energy.bottom, closeTo(16, 1));
    expect(
      (tester.getRect(find.text('Fett')).top - protein.top).abs(),
      lessThan(1),
    );
    expect(find.text('Menge'), findsOneWidget);
    expect(find.text('Uhrzeit'), findsOneWidget);
    expect(find.text('Quelle'), findsOneWidget);
    expect(find.text('Manuell'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2));
    expect(find.text('P'), findsNothing);
    expect(find.text('K'), findsNothing);
    expect(find.text('F'), findsNothing);
    expect(find.byIcon(LucideIcons.pencil), findsOneWidget);
    expect(find.byType(OBPageHeader), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/meal-entry-detail.png'),
    );
    await tester.tap(find.text('Weitere Nährwerte'));
    await tester.pumpAndSettle();
    expect(find.text('Ballaststoffe'), findsOneWidget);
    expect(find.text('Zucker'), findsOneWidget);
    expect(find.text('Gesättigte Fettsäuren'), findsOneWidget);
    expect(find.text('Natrium'), findsOneWidget);
    expect(find.text('Eisen'), findsOneWidget);
    expect(find.text('Calcium'), findsOneWidget);
  });

  testWidgets('detail dark uses card token', (tester) async {
    await mount(tester, brightness: Brightness.dark);
    expect(find.text('Eintrag'), findsOneWidget);
    final box = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(OBCard).first,
            matching: find.byType(Container),
          )
          .first,
    );
    expect((box.decoration as BoxDecoration).color, OB(true).card);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/meal-entry-detail-dark.png'),
    );
  });

  testWidgets('unknown source is not called manual; photo stays unmeasured', (
    tester,
  ) async {
    repo.seedFoodEntry(
      oats(
        id: 'wire',
        source: FoodSource.unknown,
        sourceCode: 'vendor-x',
        kcal: 10,
      ),
    );
    await mount(tester, id: 'wire');
    expect(find.text('Unbekannt'), findsOneWidget);
    expect(find.text('Manuell'), findsNothing);
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Quelle Unbekannt vendor-x'), findsOneWidget);
    semantics.dispose();

    repo.seedFoodEntry(
      oats(
        id: 'photo',
        source: FoodSource.photo,
        confirmed: false,
        kcal: 500,
        proteinG: 20,
        carbsG: 40,
        fatG: 10,
      ),
    );
    await mount(tester, id: 'photo');
    expect(find.text('Foto · unbestätigt'), findsOneWidget);
    expect(find.text('Foto'), findsNothing);
    expect(find.text('Manuell'), findsNothing);
    expect(find.text('500'), findsNothing);
    expect(find.text('20 g'), findsNothing);
    expect(find.text('—'), findsWidgets);
  });

  testWidgets('zero is distinct from empty and precision is kept', (
    tester,
  ) async {
    repo.seedFoodEntry(
      oats(
        kcal: 0,
        proteinG: 0,
        fibreG: 8.1,
        sugarG: 0,
        quantity: 0,
      ),
    );
    await mount(tester);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('0 g'), findsWidgets);
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nährwerte'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('food-nutrient-kcal')))
          .controller!
          .text,
      '0',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('food-nutrient-fibreG')),
          )
          .controller!
          .text,
      '8,1',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('food-nutrient-sugarG')),
          )
          .controller!
          .text,
      '0',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('food-nutrient-sodiumMg')),
          )
          .controller!
          .text,
      '',
    );
    await tester.enterText(
      find.byKey(const ValueKey('food-nutrient-ironMg')),
      '1,25',
    );
    await tester.enterText(
      find.byKey(const ValueKey('food-nutrient-calciumMg')),
      '-1',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.descendant(
              of: find.byType(OBAction),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const ValueKey('food-nutrient-calciumMg')),
      '2.5',
    );
    await tester.pump();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('food-entry-save')));
    await tester.pumpAndSettle();
    final saved = (await repo.readFoodEntry('oats')).current!;
    expect(saved.kcal, 0);
    expect(saved.proteinG, 0);
    expect(saved.fibreG, 8.1);
    expect(saved.sugarG, 0);
    expect(saved.ironMg, 1.25);
    expect(saved.calciumMg, 2.5);
    expect(saved.sodiumMg, isNull);
    expect(saved.quantity, 0);
    expect(saved.unit, 'g');
    expect(saved.carbsG, 56);
    expect(saved.sourceCode, 'manual');
  });

  testWidgets('editor apply cancel and name edit keep nutrients', (
    tester,
  ) async {
    repo.seedFoodEntry(oats(fibreG: 8.1, note: 'pack', quantity: 80));
    await mount(tester);
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    expect(find.text('Eintrag bearbeiten'), findsOneWidget);
    expect(find.text('80 g'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/meal-entry-editor.png'),
    );
    await tester.tap(find.text('Nährwerte'));
    await tester.pumpAndSettle();
    expect(find.text('Energie'), findsOneWidget);
    expect(find.text('Ballaststoffe'), findsOneWidget);
    expect(find.byTooltip('Zurück'), findsOneWidget);
    expect(find.byIcon(LucideIcons.chevronLeft), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/meal-entry-nutrients.png'),
    );
    await tester.enterText(
      find.byKey(const ValueKey('food-nutrient-kcal')),
      '999',
    );
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('380'), findsOneWidget);
    expect(find.text('999'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('food-entry-name')),
      'Haferflocken mit Hafermilch',
    );
    await tester.enterText(find.byKey(const ValueKey('food-entry-note')), 'neu');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('food-entry-save')));
    await tester.pumpAndSettle();
    final saved = (await repo.readFoodEntry('oats')).current!;
    expect(saved.label, 'Haferflocken mit Hafermilch');
    expect(saved.note, 'neu');
    expect(saved.kcal, 380);
    expect(saved.proteinG, 18);
    expect(saved.fibreG, 8.1);
    expect(saved.quantity, 80);
    expect(saved.atTs, isNull);
    expect(saved.sourceCode, 'manual');
    expect(find.text('Haferflocken mit Hafermilch'), findsOneWidget);
  });

  testWidgets('quantity scale is explicit and unit change does not scale', (
    tester,
  ) async {
    repo.seedFoodEntry(
      oats(quantity: 80, fibreG: 8, sugarG: null, kcal: 400, proteinG: 20),
    );
    await mount(tester);
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Menge'));
    await tester.pumpAndSettle();
    expect(find.text('Nährwerte anpassen'), findsOneWidget);
    expect(
      tester
          .widget<OBSettingsChoiceRow>(find.byType(OBSettingsChoiceRow))
          .selected,
      isFalse,
    );
    await tester.enterText(
      find.byKey(const ValueKey('food-qty-amount')),
      '160',
    );
    await tester.pump();
    await tester.tap(find.text('Nährwerte anpassen'));
    await tester.pump();
    expect(
      tester
          .widget<OBSettingsChoiceRow>(find.byType(OBSettingsChoiceRow))
          .selected,
      isTrue,
    );
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('food-entry-save')));
    await tester.pumpAndSettle();
    var saved = (await repo.readFoodEntry('oats')).current!;
    expect(saved.quantity, 160);
    expect(saved.kcal, 800);
    expect(saved.proteinG, 40);
    expect(saved.fibreG, 16);
    expect(saved.sugarG, isNull);

    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Menge'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('food-qty-unit')), 'ml');
    await tester.enterText(
      find.byKey(const ValueKey('food-qty-amount')),
      '80',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('food-qty-scale')), findsNothing);
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('food-entry-save')));
    await tester.pumpAndSettle();
    saved = (await repo.readFoodEntry('oats')).current!;
    expect(saved.quantity, 80);
    expect(saved.unit, 'ml');
    expect(saved.kcal, 800);
    expect(saved.sugarG, isNull);
  });

  testWidgets('missing original quantity never scales', (tester) async {
    await mount(tester);
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Menge'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('food-qty-scale')), findsNothing);
    expect(find.text('Menge entfernen'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Übernehmen'))
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const ValueKey('food-qty-amount')),
      '100',
    );
    await tester.pump();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('food-entry-save')));
    await tester.pumpAndSettle();
    final saved = (await repo.readFoodEntry('oats')).current!;
    expect(saved.quantity, 100);
    expect(saved.kcal, 380);
    expect(saved.proteinG, 18);
  });

  testWidgets('save failure keeps draft; retry writes once after success', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('food-entry-name')),
      'Haferflocken mit Hafermilch',
    );
    await tester.pump();
    repo.failFoodWrite = true;
    await tester.tap(find.byKey(const ValueKey('food-entry-save')));
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(find.byTooltip('Zurück'), findsOneWidget);
    expect(find.byIcon(LucideIcons.chevronLeft), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('food-entry-name')))
          .controller!
          .text,
      'Haferflocken mit Hafermilch',
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/meal-entry-save-failure.png'),
    );
    repo.failFoodWrite = false;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(find.text('Eintrag bearbeiten'), findsNothing);
    expect(find.text('Haferflocken mit Hafermilch'), findsOneWidget);
    final first = (await repo.readFoodEntry('oats')).current!;
    expect(first.label, 'Haferflocken mit Hafermilch');
    final updatedAt = first.updatedAt;
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.descendant(
              of: find.byKey(const ValueKey('food-entry-save')),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );
    expect((await repo.readFoodEntry('oats')).current!.updatedAt, updatedAt);
  });

  testWidgets('retry button follows save validation', (tester) async {
    const zone = 'Europe/Berlin';
    final at = berlinAt(2026, 3, 28, 2, 30, 42);
    repo.seedFoodEntry(
      oats(
        date: '2026-03-28',
        atTs: at.millisecondsSinceEpoch ~/ 1000,
        quantity: 80,
      ),
    );
    await mount(tester, zone: zone, day: '2026-03-28');
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('food-entry-name')),
      'Haferflocken extra',
    );
    await tester.pump();
    repo.failFoodWrite = true;
    await tester.tap(find.byKey(const ValueKey('food-entry-save')));
    await tester.pumpAndSettle();
    FilledButton retry() => tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(const ValueKey('food-entry-save')),
        matching: find.byType(FilledButton),
      ),
    );
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(retry().onPressed, isNotNull);
    await tester.enterText(
      find.byKey(const ValueKey('food-entry-name')),
      '   ',
    );
    await tester.pump();
    expect(retry().onPressed, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('food-entry-name')),
      'Haferflocken extra',
    );
    await tester.pump();
    expect(retry().onPressed, isNotNull);
    await tester.tap(find.text('Datum'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('29'));
    await tester.pump();
    await tester.tap(find.text('29. März übernehmen'));
    await tester.pumpAndSettle();
    expect(find.text('29. März'), findsWidgets);
    expect(find.text('Uhrzeit ungültig'), findsOneWidget);
    expect(retry().onPressed, isNull);
  });

  testWidgets('conflict keeps draft and reload needs discard confirm', (
    tester,
  ) async {
    final original = (await repo.readFoodEntry('oats')).current!;
    await mount(tester);
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('food-entry-name')),
      'Haferflocken mit Hafermilch',
    );
    await tester.pump();
    expect(
      (await repo.saveFoodEntry(
        original,
        FoodEntry(
          id: original.id,
          date: original.date,
          meal: original.meal,
          label: original.label,
          kcal: 390,
          proteinG: original.proteinG,
          carbsG: original.carbsG,
          fatG: original.fatG,
          source: original.source,
          sourceCode: original.sourceCode,
          confirmed: original.confirmed,
          createdAt: original.createdAt,
          updatedAt: original.updatedAt,
        ),
      )).saved,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('food-entry-save')));
    await tester.pumpAndSettle();
    expect(find.text('Eintrag wurde geändert'), findsOneWidget);
    expect(find.text('Neu laden'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('food-entry-name')))
          .controller!
          .text,
      'Haferflocken mit Hafermilch',
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/meal-entry-conflict.png'),
    );
    await tester.tap(find.text('Neu laden'));
    await tester.pumpAndSettle();
    expect(find.text('Änderungen verwerfen?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ob-confirm-no')));
    await tester.pumpAndSettle();
    expect(find.text('Haferflocken mit Hafermilch'), findsOneWidget);
    await tester.tap(find.text('Neu laden'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ob-confirm-yes')));
    await tester.pumpAndSettle();
    expect(find.text('Eintrag'), findsOneWidget);
    expect(find.text('390'), findsOneWidget);
    expect(find.text('Haferflocken mit Milch'), findsOneWidget);
  });

  testWidgets('busy write ignores a second save tap', (tester) async {
    await mount(tester);
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('food-entry-name')),
      'Haferflocken mit Hafermilch',
    );
    await tester.pump();
    final barrier = Completer<void>();
    repo.foodWriteBarrier = barrier.future;
    await tester.tap(find.byKey(const ValueKey('food-entry-save')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('food-entry-save')));
    await tester.tap(find.byTooltip('Zurück'));
    barrier.complete();
    await tester.pumpAndSettle();
    expect(find.text('Haferflocken mit Hafermilch'), findsOneWidget);
    expect((await repo.readFoodEntry('oats')).current!.label, 'Haferflocken mit Hafermilch');
  });

  testWidgets('removal pops exact receipt; stale delete keeps the page', (
    tester,
  ) async {
    var result = await mountPushed(tester);
    expect(result, isNull);
    await tester.tap(find.byKey(const ValueKey('food-entry-remove')));
    await tester.pumpAndSettle();
    expect(find.text('Eintrag entfernen?'), findsOneWidget);
    expect(find.byType(OpenBandConfirmSheet), findsOneWidget);
    await tester.tap(find.text('Entfernen'));
    await tester.pumpAndSettle();
    result = tester.takeException() == null ? result : result;
    // Re-open capture of push result by reading the stored completer via a
    // second mount: the first push already popped. Rebuild a push.
    FoodEntryRouteResult? popped;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(Brightness.light),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              popped = await openOpenBandFoodEntry(
                context,
                repository: repo,
                id: 'oats',
                day: '2026-09-15',
                now: () => now,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    repo.seedFoodEntry(oats());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('food-entry-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen'));
    await tester.pumpAndSettle();
    expect(popped?.changed, isTrue);
    expect(popped?.removed?.id, 'oats');
    expect(popped?.removed?.label, 'Haferflocken mit Milch');
    expect(popped?.removed?.kcal, 380);
    expect((await repo.readFoodEntry('oats')).missing, isTrue);

    repo.seedFoodEntry(oats());
    final original = (await repo.readFoodEntry('oats')).current!;
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      (await repo.saveFoodEntry(
        original,
        FoodEntry(
          id: original.id,
          date: original.date,
          meal: original.meal,
          label: original.label,
          kcal: 410,
          proteinG: original.proteinG,
          carbsG: original.carbsG,
          fatG: original.fatG,
          source: original.source,
          sourceCode: original.sourceCode,
          confirmed: original.confirmed,
          createdAt: original.createdAt,
          updatedAt: original.updatedAt,
        ),
      )).saved,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('food-entry-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen'));
    await tester.pumpAndSettle();
    expect(find.text('Eintrag'), findsOneWidget);
    expect(find.text('Eintrag wurde geändert'), findsOneWidget);
    expect((await repo.readFoodEntry('oats')).current!.kcal, 410);
  });

  testWidgets('missing and read error stay honest', (tester) async {
    await mount(tester, id: 'missing');
    expect(find.text('Eintrag nicht gefunden'), findsOneWidget);
    expect(find.text('Selbst eintragen'), findsNothing);
    expect(find.text('Dein Eintrag bleibt erhalten'), findsNothing);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/meal-entry-missing.png'),
    );

    repo.failFoodRead = true;
    await mount(tester);
    expect(find.text('Eintrag nicht geladen'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/meal-entry-error.png'),
    );
    repo.failFoodRead = false;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(find.text('Haferflocken mit Milch'), findsOneWidget);
  });

  testWidgets('read error dark and 2x stacked wells stay on screen', (
    tester,
  ) async {
    repo.failFoodRead = true;
    await mount(tester, brightness: Brightness.dark);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/meal-entry-error-dark.png'),
    );
    repo.failFoodRead = false;

    await mount(tester, scale: 2, width: 375);
    expect(find.text('Haferflocken mit Milch'), findsOneWidget);
    final protein = tester.getRect(find.text('Eiweiß'));
    final proteinG = tester.getRect(find.text('18 g'));
    expect(proteinG.left - protein.right, closeTo(12, 1));
    expect((protein.center.dy - proteinG.center.dy).abs(), lessThan(2));
    final fat = tester.getRect(find.text('Fett'));
    expect(fat.top, greaterThan(protein.bottom));
    expect(fat.top, greaterThan(proteinG.bottom));
    expect(tester.getRect(find.text('Kohlenhydrate')).height, lessThan(40));
    expect(find.byIcon(LucideIcons.pencil).hitTestable(), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/meal-entry-detail-2x.png'),
    );
    await tester.scrollUntilVisible(
      find.text('Weitere Nährwerte'),
      80,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Weitere Nährwerte'));
    await tester.pumpAndSettle();
    expect(find.text('Weitere Nährwerte').hitTestable(), findsOneWidget);
    expect(find.byIcon(LucideIcons.pencil).hitTestable(), findsOneWidget);
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    expect(find.text('Eintrag bearbeiten'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/meal-entry-editor-2x.png'),
    );
    await tester.scrollUntilVisible(
      find.text('Nährwerte'),
      80,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Nährwerte'));
    await tester.pumpAndSettle();
    expect(find.text('Energie').hitTestable(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('food-nutrient-kcal')).hitTestable(),
      findsOneWidget,
    );
    final field = tester.getRect(
      find.byKey(const ValueKey('food-nutrient-kcal')),
    );
    final well = tester.getRect(
      find
          .ancestor(
            of: find.byKey(const ValueKey('food-nutrient-kcal')),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(field.left, lessThan(50));
    expect(well.width, greaterThan(300));
    expect(find.text('Übernehmen').hitTestable(), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Calcium'),
      80,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Übernehmen').hitTestable(), findsOneWidget);
    await tester.showKeyboard(find.byKey(const ValueKey('food-nutrient-kcal')));
    await tester.pump();
    expect(find.text('Übernehmen').hitTestable(), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/meal-entry-nutrients-2x.png'),
    );
  });

  testWidgets(
    'scrolled editor opens nutrients at top; entry identity resets scroll',
    (tester) async {
      repo.seedFoodEntry(
        oats(id: 'other', label: 'Anderes Essen', quantity: 80, kcal: 10),
      );
      var currentId = 'oats';
      final tick = ValueNotifier(0);
      addTearDown(tick.dispose);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 852);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          debugShowCheckedModeBanner: false,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('de')],
          theme: openBandTheme(Brightness.light).copyWith(
            platform: TargetPlatform.iOS,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              padding: const EdgeInsets.only(top: 59, bottom: 34),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: SizedBox(
            width: 375,
            height: 852,
            child: ValueListenableBuilder<int>(
              valueListenable: tick,
              builder: (context, value, child) => OpenBandFoodEntry(
                repository: repo,
                id: currentId,
                day: '2026-09-15',
                now: () => now,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(LucideIcons.pencil));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Nährwerte'),
        80,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Nährwerte'));
      await tester.pumpAndSettle();
      expect(find.text('Energie').hitTestable(), findsOneWidget);
      expect(
        find.byKey(const ValueKey('food-nutrient-kcal')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Zurück'));
      await tester.pumpAndSettle();
      expect(find.text('Eintrag bearbeiten'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('food-entry-name')).hitTestable(),
        findsOneWidget,
      );
      currentId = 'other';
      tick.value++;
      await tester.pumpAndSettle();
      expect(find.text('Anderes Essen').hitTestable(), findsOneWidget);
      expect(find.text('Energie'), findsNothing);
    },
  );

  testWidgets('320 width keeps editor save and nutrient apply fixed', (
    tester,
  ) async {
    await mount(tester, width: 320);
    expect(
      tester.getRect(find.text('Fett')).top,
      greaterThan(tester.getRect(find.text('Eiweiß')).bottom),
    );
    expect(
      tester.getRect(find.text('18 g')).left -
          tester.getRect(find.text('Eiweiß')).right,
      closeTo(12, 1),
    );
    await tester.scrollUntilVisible(
      find.text('Weitere Nährwerte'),
      40,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Weitere Nährwerte').hitTestable(), findsOneWidget);
    expect(find.byIcon(LucideIcons.pencil).hitTestable(), findsOneWidget);
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    expect(find.text('Speichern').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Nährwerte'));
    await tester.pumpAndSettle();
    expect(find.text('Übernehmen').hitTestable(), findsOneWidget);
    final well = tester.getRect(
      find.byKey(const ValueKey('food-nutrient-kcal')),
    );
    expect(well.width, greaterThan(200));
  });

  testWidgets('editor dark and nutrients dark', (tester) async {
    await mount(tester, brightness: Brightness.dark);
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/meal-entry-editor-dark.png'),
    );
    await tester.tap(find.text('Nährwerte'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/meal-entry-nutrients-dark.png'),
    );
  });

  testWidgets('detail back reports changed after a successful save', (
    tester,
  ) async {
    FoodEntryRouteResult? popped;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(Brightness.light),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              popped = await openOpenBandFoodEntry(
                context,
                repository: repo,
                id: 'oats',
                day: '2026-09-15',
                now: () => now,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Bearbeiten'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('food-entry-name')),
      'Haferflocken mit Hafermilch',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('food-entry-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(popped?.changed, isTrue);
    expect(popped?.removed, isNull);
  });

  testWidgets('quantity modal matches Paper known, unknown, and dark', (
    tester,
  ) async {
    repo.seedFoodEntry(oats(quantity: 150));
    await mount(tester);
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Menge'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('food-qty-amount')), '75');
    await tester.pump();
    await tester.tap(find.text('Nährwerte anpassen'));
    await tester.pump();
    expect(find.byType(ModalBarrier), findsWidgets);
    expect(find.text('Menge entfernen'), findsOneWidget);
    expect(find.text('Übernehmen'), findsOneWidget);
    expect(find.text('75'), findsOneWidget);
    final amountWell = tester.getRect(
      find
          .ancestor(
            of: find.byKey(const ValueKey('food-qty-amount')),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(amountWell.height, closeTo(56, 1));
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/meal-entry-quantity.png'),
    );
    await tester.tap(find.byTooltip('Schließen'));
    await tester.pumpAndSettle();

    repo.seedFoodEntry(oats());
    await mount(tester);
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Menge'));
    await tester.pumpAndSettle();
    expect(find.text('Nährwerte anpassen'), findsNothing);
    expect(find.text('Menge entfernen'), findsNothing);
    expect(find.byType(ModalBarrier), findsWidgets);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/meal-entry-quantity-unknown.png'),
    );
    await tester.tap(find.byTooltip('Schließen'));
    await tester.pumpAndSettle();

    repo.seedFoodEntry(oats(quantity: 150));
    await mount(tester, brightness: Brightness.dark);
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Menge'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('food-qty-amount')), '75');
    await tester.pump();
    await tester.tap(find.text('Nährwerte anpassen'));
    await tester.pump();
    expect(find.byType(ModalBarrier), findsWidgets);
    expect(find.text('Menge entfernen'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/meal-entry-quantity-dark.png'),
    );
  });

  testWidgets('unconfirmed photo confirms only via Werte bestätigen', (
    tester,
  ) async {
    repo.seedFoodEntry(
      oats(source: FoodSource.photo, confirmed: false, quantity: 80),
    );
    await mount(tester);
    expect(find.text('Foto · unbestätigt'), findsOneWidget);
    expect(find.text('380'), findsNothing);
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('food-entry-name')),
      'Haferflocken Foto',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('food-entry-save')));
    await tester.pumpAndSettle();
    var saved = (await repo.readFoodEntry('oats')).current!;
    expect(saved.confirmed, isFalse);
    expect(saved.source, FoodSource.photo);
    expect(saved.sourceCode, 'photo');

    repo.seedFoodEntry(
      oats(source: FoodSource.photo, confirmed: false, quantity: 80),
    );
    await mount(tester);
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nährwerte'));
    await tester.pumpAndSettle();
    expect(find.text('Foto · unbestätigt'), findsOneWidget);
    expect(find.text('Werte bestätigen'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/meal-entry-photo-nutrients.png'),
    );
    await tester.tap(find.text('Werte bestätigen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('food-entry-save')));
    await tester.pumpAndSettle();
    saved = (await repo.readFoodEntry('oats')).current!;
    expect(saved.confirmed, isTrue);
    expect(saved.kcal, 380);
    expect(saved.source, FoodSource.photo);
    expect(saved.sourceCode, 'photo');
    expect(find.text('380'), findsOneWidget);
    expect(find.text('Foto · unbestätigt'), findsNothing);
  });

  testWidgets('unconfirmed photo dark keeps Werte bestätigen', (tester) async {
    repo.seedFoodEntry(
      oats(source: FoodSource.photo, confirmed: false, quantity: 80),
    );
    await mount(tester, brightness: Brightness.dark);
    expect(find.text('Foto · unbestätigt'), findsOneWidget);
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nährwerte'));
    await tester.pumpAndSettle();
    expect(find.text('Foto · unbestätigt'), findsOneWidget);
    expect(find.text('Werte bestätigen'), findsOneWidget);
    expect(find.byTooltip('Zurück'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/meal-entry-photo-nutrients-dark.png'),
    );
  });

  testWidgets('stale delayed read is discarded after id and repo change', (
    tester,
  ) async {
    final delayed = _GatedFoodRepo(
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
    delayed.seedFoodEntry(oats(id: 'old', label: 'Altes Essen'));
    delayed.seedFoodEntry(oats(id: 'fresh', label: 'Neues Essen', kcal: 120));
    final other = galleryRepo()
      ..seedFoodEntry(oats(id: 'fresh', label: 'Anderes Repo', kcal: 50));
    final oldGate = Completer<void>();
    delayed.gateFor = (id) => id == 'old' ? oldGate : null;

    OpenBandRepository currentRepo = delayed;
    var currentId = 'old';
    final tick = ValueNotifier(0);

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ValueListenableBuilder<int>(
        valueListenable: tick,
        builder: (context, value, child) => MaterialApp(
          locale: const Locale('de'),
          debugShowCheckedModeBanner: false,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('de')],
          theme: openBandTheme(Brightness.light).copyWith(
            platform: TargetPlatform.iOS,
          ),
          home: OpenBandFoodEntry(
            repository: currentRepo,
            id: currentId,
            day: '2026-09-15',
            now: () => now,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Altes Essen'), findsNothing);

    currentId = 'fresh';
    currentRepo = other;
    tick.value++;
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Anderes Repo'), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
    expect(find.text('Altes Essen'), findsNothing);

    oldGate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Anderes Repo'), findsOneWidget);
    expect(find.text('Altes Essen'), findsNothing);
    expect(find.text('Neues Essen'), findsNothing);
  });

  testWidgets('conflict stays blocking after a cancelled child pane', (
    tester,
  ) async {
    final original = (await repo.readFoodEntry('oats')).current!;
    await mount(tester);
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('food-entry-name')),
      'Haferflocken mit Hafermilch',
    );
    await tester.pump();
    expect(
      (await repo.saveFoodEntry(
        original,
        FoodEntry(
          id: original.id,
          date: original.date,
          meal: original.meal,
          label: original.label,
          kcal: 390,
          proteinG: original.proteinG,
          carbsG: original.carbsG,
          fatG: original.fatG,
          source: original.source,
          sourceCode: original.sourceCode,
          confirmed: original.confirmed,
          createdAt: original.createdAt,
          updatedAt: original.updatedAt,
        ),
      )).saved,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('food-entry-save')));
    await tester.pumpAndSettle();
    expect(find.text('Eintrag wurde geändert'), findsOneWidget);
    expect(find.text('Neu laden'), findsOneWidget);

    await tester.tap(find.text('Nährwerte'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('Eintrag wurde geändert'), findsOneWidget);
    expect(find.text('Neu laden'), findsOneWidget);
    expect(find.byKey(const ValueKey('food-entry-save')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('food-entry-name')))
          .controller!
          .text,
      'Haferflocken mit Hafermilch',
    );

    await tester.tap(find.text('Menge'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Schließen'));
    await tester.pumpAndSettle();
    expect(find.text('Neu laden'), findsOneWidget);
    expect(find.byKey(const ValueKey('food-entry-save')), findsNothing);
    expect((await repo.readFoodEntry('oats')).current!.kcal, 390);
    expect((await repo.readFoodEntry('oats')).current!.label, 'Haferflocken mit Milch');
  });

  testWidgets('date move keeps seconds and time can be cleared', (tester) async {
    final local = DateTime(2026, 9, 15, 8, 15, 42);
    repo.seedFoodEntry(
      oats(atTs: local.millisecondsSinceEpoch ~/ 1000, quantity: 80),
    );
    await mount(tester);
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Datum'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('16'));
    await tester.pump();
    await tester.tap(find.text('16. September übernehmen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('food-entry-save')));
    await tester.pumpAndSettle();
    var saved = (await repo.readFoodEntry('oats')).current!;
    expect(saved.date, '2026-09-16');
    final moved = DateTime.fromMillisecondsSinceEpoch(saved.atTs! * 1000);
    expect(moved.toLocal().second, 42);
    expect(moved.toLocal().hour, 8);
    expect(moved.toLocal().minute, 15);

    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uhrzeit').first);
    await tester.pumpAndSettle();
    expect(find.text('Uhrzeit entfernen'), findsOneWidget);
    await tester.tap(find.text('Uhrzeit entfernen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('food-entry-save')));
    await tester.pumpAndSettle();
    saved = (await repo.readFoodEntry('oats')).current!;
    expect(saved.atTs, isNull);
    expect(saved.date, '2026-09-16');
  });

  testWidgets('quantity 2x keeps apply fixed above the keyboard', (
    tester,
  ) async {
    const inset = 420.0;
    repo.seedFoodEntry(oats(quantity: 150));
    await mount(tester, scale: 2, width: 375);
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Menge'),
      80,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Menge'));
    await tester.pumpAndSettle();
    expect(find.byType(ModalBarrier), findsWidgets);
    final unitWell = tester.getRect(
      find
          .ancestor(
            of: find.byKey(const ValueKey('food-qty-unit')),
            matching: find.byType(Container),
          )
          .first,
    );
    final unitGlyph = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('food-qty-unit')),
        matching: find.byType(EditableText),
      ),
    );
    expect(unitWell.height, closeTo(84, 1));
    expect(unitGlyph.bottom, lessThanOrEqualTo(unitWell.bottom + 0.5));
    expect(unitGlyph.top, greaterThanOrEqualTo(unitWell.top - 0.5));
    final choice = tester.getRect(find.byType(OBSettingsChoiceRow));
    expect(choice.height, greaterThanOrEqualTo(64 - 0.5));
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/meal-entry-quantity-2x.png'),
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: inset);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Übernehmen').hitTestable(), findsOneWidget);
    final apply = tester.getRect(find.text('Übernehmen'));
    expect(apply.bottom, lessThanOrEqualTo(852 - inset + 1));
    final applyTop = apply.top;
    final qtyScroll = find
        .descendant(
          of: find.byKey(const ValueKey('food-qty-scroll')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Nährwerte anpassen'),
      40,
      scrollable: qtyScroll,
    );
    await tester.pump();
    expect(find.text('Übernehmen').hitTestable(), findsOneWidget);
    expect(tester.getRect(find.text('Übernehmen')).top, applyTop);
    expect(find.text('Nährwerte anpassen').hitTestable(), findsOneWidget);
  });

  testWidgets(
    'public route 2x quantity sheet stays in the safe area above the keyboard',
    (tester) async {
      const inset = 308.0;
      repo.seedFoodEntry(oats(quantity: 150));
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 812);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          debugShowCheckedModeBanner: false,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('de')],
          theme: openBandTheme(Brightness.light).copyWith(
            platform: TargetPlatform.iOS,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              padding: const EdgeInsets.only(top: 59, bottom: 34),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                openOpenBandFoodEntry(
                  context,
                  repository: repo,
                  id: 'oats',
                  day: '2026-09-15',
                  now: () => now,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(LucideIcons.pencil));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Menge'),
        80,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Menge'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: inset);
      await tester.pump();
      await tester.pumpAndSettle();
      final close = tester.getRect(find.byTooltip('Schließen'));
      expect(close.top, greaterThanOrEqualTo(59));
      expect(find.text('Menge').hitTestable(), findsWidgets);
      expect(find.text('Übernehmen').hitTestable(), findsOneWidget);
      expect(find.text('Menge entfernen').hitTestable(), findsOneWidget);
      expect(
        tester.getRect(find.text('Übernehmen')).bottom,
        lessThanOrEqualTo(812 - inset + 1),
      );
      expect(
        tester.getRect(find.text('Menge entfernen')).bottom,
        lessThanOrEqualTo(812 - inset + 1),
      );
      final qtyScroll = find
          .descendant(
            of: find.byKey(const ValueKey('food-qty-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('food-qty-amount')),
        40,
        scrollable: qtyScroll,
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('food-qty-amount')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.getRect(find.byTooltip('Schließen')).top, greaterThanOrEqualTo(59));
      expect(find.text('Übernehmen').hitTestable(), findsOneWidget);
      expect(find.text('Menge entfernen').hitTestable(), findsOneWidget);
    },
  );

  testWidgets('time sheet matches Paper known, unknown, dark, and error', (
    tester,
  ) async {
    final at = DateTime(2026, 9, 15, 8, 15);
    repo.seedFoodEntry(
      oats(atTs: at.millisecondsSinceEpoch ~/ 1000, quantity: 150),
    );
    await mount(tester);
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uhrzeit').first);
    await tester.pumpAndSettle();
    expect(find.byType(ModalBarrier), findsWidgets);
    expect(find.text('15. September'), findsWidgets);
    expect(find.text('08:15'), findsWidgets);
    expect(find.text('12:00'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('food-time')))
          .controller!
          .text,
      '08:15',
    );
    expect(find.text('Uhrzeit entfernen'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Übernehmen'))
          .onPressed,
      isNotNull,
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/meal-entry-time.png'),
    );
    await tester.enterText(find.byKey(const ValueKey('food-time')), '25:30');
    await tester.pump();
    await tester.tap(find.text('Übernehmen'));
    await tester.pump();
    expect(find.text('Uhrzeit ungültig'), findsOneWidget);
    expect(find.text('25:30'), findsOneWidget);
    expect(find.byType(ModalBarrier), findsWidgets);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Übernehmen'))
          .onPressed,
      isNotNull,
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/meal-entry-time-error.png'),
    );
    await tester.tap(find.byTooltip('Schließen'));
    await tester.pumpAndSettle();

    repo.seedFoodEntry(oats(quantity: 150));
    await mount(tester);
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uhrzeit').first);
    await tester.pumpAndSettle();
    expect(find.text('HH:mm'), findsOneWidget);
    expect(find.text('12:00'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('food-time')))
          .controller!
          .text,
      '',
    );
    expect(find.text('Uhrzeit entfernen'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Übernehmen'))
          .onPressed,
      isNull,
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/meal-entry-time-unknown.png'),
    );
    await tester.tap(find.byTooltip('Schließen'));
    await tester.pumpAndSettle();

    repo.seedFoodEntry(
      oats(atTs: at.millisecondsSinceEpoch ~/ 1000, quantity: 150),
    );
    await mount(tester, brightness: Brightness.dark);
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uhrzeit').first);
    await tester.pumpAndSettle();
    expect(find.text('08:15'), findsWidgets);
    expect(find.text('Uhrzeit entfernen'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/meal-entry-time-dark.png'),
    );
  });

  testWidgets('time sheet cancel keeps unknown; clear and apply stage only', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uhrzeit').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('food-time')), '09:00');
    await tester.pump();
    await tester.tap(find.byTooltip('Schließen'));
    await tester.pumpAndSettle();
    expect(find.text('09:00'), findsNothing);
    expect(find.text('—'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('food-entry-save')));
    await tester.pumpAndSettle();
    expect((await repo.readFoodEntry('oats')).current!.atTs, isNull);

    final at = DateTime(2026, 9, 15, 8, 15);
    repo.seedFoodEntry(oats(atTs: at.millisecondsSinceEpoch ~/ 1000));
    await mount(tester);
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uhrzeit').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uhrzeit entfernen'));
    await tester.pumpAndSettle();
    expect(find.text('Uhrzeit entfernen'), findsNothing);
    expect((await repo.readFoodEntry('oats')).current!.atTs, isNotNull);
    await tester.tap(find.byKey(const ValueKey('food-entry-save')));
    await tester.pumpAndSettle();
    expect((await repo.readFoodEntry('oats')).current!.atTs, isNull);
  });

  testWidgets('time sheet keeps 25:30 and DST gap until a valid apply', (
    tester,
  ) async {
    final at = DateTime(2026, 9, 15, 8, 15);
    repo.seedFoodEntry(oats(atTs: at.millisecondsSinceEpoch ~/ 1000));
    await mount(tester);
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uhrzeit').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('food-time')), '25:30');
    await tester.pump();
    await tester.tap(find.text('Übernehmen'));
    await tester.pump();
    expect(find.text('Uhrzeit ungültig'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('food-time')))
          .controller!
          .text,
      '25:30',
    );
    await tester.enterText(find.byKey(const ValueKey('food-time')), '08:16');
    await tester.pump();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(find.text('Uhrzeit ungültig'), findsNothing);
    expect(find.text('08:16'), findsOneWidget);
    expect((await repo.readFoodEntry('oats')).current!.atTs, at.millisecondsSinceEpoch ~/ 1000);
    await tester.tap(find.byKey(const ValueKey('food-entry-save')));
    await tester.pumpAndSettle();
    final saved = (await repo.readFoodEntry('oats')).current!;
    final local = DateTime.fromMillisecondsSinceEpoch(saved.atTs! * 1000).toLocal();
    expect(local.hour, 8);
    expect(local.minute, 16);

    repo.seedFoodEntry(oats(date: '2026-03-29', quantity: 80));
    await mount(tester, zone: 'Europe/Berlin');
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uhrzeit').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('food-time')), '02:30');
    await tester.pump();
    await tester.tap(find.text('Übernehmen'));
    await tester.pump();
    expect(parseRecordedTime(DateTime(2026, 3, 29), '02:30', zone: 'Europe/Berlin'), isNull);
    expect(find.text('Uhrzeit ungültig'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('food-time')))
          .controller!
          .text,
      '02:30',
    );
    expect(find.byType(ModalBarrier), findsWidgets);
  });

  testWidgets(
    'unchanged time apply keeps seconds; changed time uses minute precision',
    (tester) async {
      const zone = 'Europe/Berlin';
      final at = berlinAt(2026, 9, 15, 8, 15, 42);
      repo.seedFoodEntry(
        oats(atTs: at.millisecondsSinceEpoch ~/ 1000, quantity: 80),
      );
      await mount(tester, zone: zone);
      await tester.tap(find.byIcon(LucideIcons.pencil));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Uhrzeit').first);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('food-time')))
            .controller!
            .text,
        '08:15',
      );
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('food-entry-name')),
        'Haferflocken extra',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('food-entry-save')));
      await tester.pumpAndSettle();
      var saved = (await repo.readFoodEntry('oats')).current!;
      expect(saved.atTs, at.millisecondsSinceEpoch ~/ 1000);
      expect(saved.label, 'Haferflocken extra');

      await tester.tap(find.byIcon(LucideIcons.pencil));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Uhrzeit').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('food-time')), '15:20');
      await tester.pump();
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('food-entry-save')));
      await tester.pumpAndSettle();
      saved = (await repo.readFoodEntry('oats')).current!;
      final wall = recordedTime(
        DateTime.fromMillisecondsSinceEpoch(saved.atTs! * 1000),
        zone,
      );
      expect(wall.hour, 15);
      expect(wall.minute, 20);
      expect(wall.second, 0);

      repo.seedFoodEntry(oats(quantity: 80));
      await mount(tester, zone: zone);
      await tester.tap(find.byIcon(LucideIcons.pencil));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Uhrzeit').first);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Übernehmen'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Schließen'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('food-entry-name')),
        'Noch ohne Zeit',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('food-entry-save')));
      await tester.pumpAndSettle();
      expect((await repo.readFoodEntry('oats')).current!.atTs, isNull);
    },
  );

  testWidgets('time 2x keeps apply fixed above the keyboard', (tester) async {
    const inset = 420.0;
    final at = DateTime(2026, 9, 15, 8, 15);
    repo.seedFoodEntry(oats(atTs: at.millisecondsSinceEpoch ~/ 1000));
    await mount(tester, scale: 2, width: 375);
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Uhrzeit').first,
      80,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Uhrzeit').first);
    await tester.pumpAndSettle();
    expect(find.byType(ModalBarrier), findsWidgets);
    tester.view.viewInsets = const FakeViewPadding(bottom: inset);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Übernehmen').hitTestable(), findsOneWidget);
    final apply = tester.getRect(find.text('Übernehmen'));
    expect(apply.bottom, lessThanOrEqualTo(852 - inset + 1));
    final applyTop = apply.top;
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('food-time')),
      40,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('food-time-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pump();
    expect(find.text('Übernehmen').hitTestable(), findsOneWidget);
    expect(tester.getRect(find.text('Übernehmen')).top, applyTop);
  });

  testWidgets('stale modal completion does not mutate a replaced row', (
    tester,
  ) async {
    repo.seedFoodEntry(oats(quantity: 150));
    repo.seedFoodEntry(
      oats(id: 'other', label: 'Anderes Essen', quantity: 80, kcal: 10),
    );
    var currentId = 'oats';
    final tick = ValueNotifier(0);
    addTearDown(tick.dispose);
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
        theme: openBandTheme(Brightness.light).copyWith(
          platform: TargetPlatform.iOS,
        ),
        home: ValueListenableBuilder<int>(
          valueListenable: tick,
          builder: (context, value, child) => OpenBandFoodEntry(
            repository: repo,
            id: currentId,
            day: '2026-09-15',
            now: () => now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('food-entry-remove')));
    await tester.pumpAndSettle();
    expect(find.text('Eintrag entfernen?'), findsOneWidget);
    currentId = 'other';
    tick.value++;
    await tester.pumpAndSettle();
    expect(find.text('Anderes Essen'), findsOneWidget);
    await tester.tap(find.text('Entfernen'));
    await tester.pumpAndSettle();
    expect((await repo.readFoodEntry('oats')).missing, isFalse);
    expect((await repo.readFoodEntry('other')).current!.label, 'Anderes Essen');
    expect(find.text('Anderes Essen'), findsOneWidget);

    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Menge'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('food-qty-amount')),
      '999',
    );
    await tester.pump();
    currentId = 'oats';
    tick.value++;
    await tester.pumpAndSettle();
    expect(find.text('Haferflocken mit Milch'), findsWidgets);
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect((await repo.readFoodEntry('oats')).current!.quantity, 150);
    expect((await repo.readFoodEntry('other')).current!.quantity, 80);
    expect(find.text('150 g'), findsOneWidget);
    expect(find.text('999'), findsNothing);
  });

  testWidgets('invalid date attempt blocks save until cancelled or time applies', (
    tester,
  ) async {
    const zone = 'Europe/Berlin';
    final gap = berlinAt(2026, 3, 28, 2, 30, 42);
    repo.seedFoodEntry(
      oats(
        date: '2026-03-28',
        atTs: gap.millisecondsSinceEpoch ~/ 1000,
        quantity: 80,
      ),
    );
    await mount(tester, zone: zone, day: '2026-03-28');
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Datum'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('29'));
    await tester.pump();
    await tester.tap(find.text('29. März übernehmen'));
    await tester.pumpAndSettle();
    expect(find.text('29. März'), findsWidgets);
    expect(find.text('Uhrzeit ungültig'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('food-entry-name')),
      'Haferflocken Lücke',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Speichern'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Datum'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('28'));
    await tester.pump();
    await tester.tap(find.text('28. März übernehmen'));
    await tester.pumpAndSettle();
    expect(find.text('Uhrzeit ungültig'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Speichern'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const ValueKey('food-entry-save')));
    await tester.pumpAndSettle();
    var saved = (await repo.readFoodEntry('oats')).current!;
    expect(saved.date, '2026-03-28');
    expect(saved.label, 'Haferflocken Lücke');
    expect(saved.atTs, gap.millisecondsSinceEpoch ~/ 1000);

    repo.seedFoodEntry(
      oats(
        date: '2026-03-28',
        atTs: gap.millisecondsSinceEpoch ~/ 1000,
        quantity: 80,
      ),
    );
    await mount(tester, zone: zone, day: '2026-03-28');
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Datum'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('29'));
    await tester.pump();
    await tester.tap(find.text('29. März übernehmen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uhrzeit').first);
    await tester.pumpAndSettle();
    expect(find.text('29. März'), findsWidgets);
    await tester.enterText(find.byKey(const ValueKey('food-time')), '08:15');
    await tester.pump();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(find.text('Uhrzeit ungültig'), findsNothing);
    expect(find.text('08:15'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('food-entry-save')));
    await tester.pumpAndSettle();
    saved = (await repo.readFoodEntry('oats')).current!;
    expect(saved.date, '2026-03-29');
    expect(
      saved.atTs,
      berlinAt(2026, 3, 29, 8, 15).millisecondsSinceEpoch ~/ 1000,
    );

    final fold = berlinAt(2026, 10, 24, 2, 30, 42);
    repo.seedFoodEntry(
      oats(
        date: '2026-10-24',
        atTs: fold.millisecondsSinceEpoch ~/ 1000,
        quantity: 80,
      ),
    );
    await mount(tester, zone: zone, day: '2026-10-24');
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Datum'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('25'));
    await tester.pump();
    await tester.tap(find.text('25. Oktober übernehmen'));
    await tester.pumpAndSettle();
    expect(find.text('Uhrzeit ungültig'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('food-entry-save')));
    await tester.pumpAndSettle();
    saved = (await repo.readFoodEntry('oats')).current!;
    expect(saved.date, '2026-10-25');
    final kept = tz.TZDateTime.from(
      DateTime.fromMillisecondsSinceEpoch(saved.atTs! * 1000),
      tz.getLocation('Europe/Berlin'),
    );
    expect(kept.hour, 2);
    expect(kept.minute, 30);
    expect(kept.second, 42);
    expect(kept.timeZoneOffset, const Duration(hours: 2));
  });
}

class _GatedFoodRepo extends SyntheticOpenBandRepository {
  Completer<void>? Function(String id)? gateFor;
  _GatedFoodRepo(super.summary, super.detail) : super.fromMaps();

  @override
  Future<FoodSnapshotResult> readFoodEntry(String id) async {
    final gate = gateFor?.call(id);
    if (gate != null) await gate.future;
    return super.readFoodEntry(id);
  }
}
