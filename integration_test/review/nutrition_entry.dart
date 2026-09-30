part of 'harness.dart';

Future<void> reviewNutritionEntry(ReviewHarness h) async {
  final tester = h.tester;
  FoodEntryRouteResult? popped;
  final now = DateTime(2026, 9, 15, 9, 41);
  final knownAt = DateTime(2026, 9, 15, 8, 15, 42);
  final knownTs = knownAt.millisecondsSinceEpoch ~/ 1000;

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
  }) => FoodEntry(
    id: id,
    date: date,
    meal: meal,
    label: label,
    atTs: atTs,
    foodKey: 'oats',
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

  Finder foodScrollable() => h.verticalScrollable().last;

  Future<SyntheticOpenBandRepository> openFoodEntry({
    String id = 'oats',
    String day = '2026-09-15',
    Brightness brightness = Brightness.light,
    double? scale,
    FoodEntry? seed,
    bool failRead = false,
  }) async {
    final repository = await loadGalleryRepository();
    repository.seedFoodEntry(seed ?? oats());
    repository.failFoodRead = failRead;
    popped = null;
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: openBandTheme(brightness).copyWith(platform: TargetPlatform.iOS),
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale ?? 1)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              popped = await openOpenBandFoodEntry(
                context,
                repository: repository,
                id: id,
                day: day,
                synthetic: true,
                now: () => now,
              );
            },
            child: const Text('open-food-entry'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open-food-entry'));
    await tester.pumpAndSettle();
    return repository;
  }

  Future<void> openEditor() async {
    final edit = find.byTooltip('Bearbeiten');
    expect(edit, findsOneWidget);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(find.text('Eintrag bearbeiten'), findsOneWidget);
  }

  Future<void> openLabeledPane(String label) async {
    final target = find.text(label);
    final scrollable = foodScrollable();
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(target, 80, scrollable: scrollable);
    }
    var scrolls = 0;
    while (target.hitTestable().evaluate().isEmpty) {
      if (scrolls >= 24) {
        throw FlutterError(
          'Labeled control "$label" is not hit-testable in the food '
          'entry pane after scrolling.',
        );
      }
      if (target.evaluate().isEmpty) {
        await tester.scrollUntilVisible(target, 80, scrollable: scrollable);
      } else {
        final view = tester.getRect(scrollable);
        final box = tester.getRect(target);
        final delta = box.center.dy < view.center.dy ? 64.0 : -64.0;
        await tester.drag(scrollable, Offset(0, delta));
        await tester.pump();
      }
      scrolls++;
    }
    expect(target.hitTestable(), findsOneWidget);
    await tester.tap(target.hitTestable());
    await tester.pumpAndSettle();
  }

  Future<void> openTime() async {
    await openLabeledPane('Uhrzeit');
    expect(find.byKey(const ValueKey('food-time')), findsOneWidget);
    expect(find.byKey(const ValueKey('food-time-scroll')), findsOneWidget);
  }

  String timeFieldText() => tester
      .widget<TextField>(find.byKey(const ValueKey('food-time')))
      .controller!
      .text;

  double keyboardInset() =>
      tester.view.viewInsets.bottom / tester.view.devicePixelRatio;

  void expectPinned(Finder matching) {
    expect(matching.hitTestable(), findsOneWidget);
  }

  Finder enclosingPinnedControl(Finder matching) {
    if (matching.evaluate().single.widget is OBAction) return matching;
    final action = find.ancestor(of: matching, matching: find.byType(OBAction));
    if (action.evaluate().isNotEmpty) {
      expect(action, findsOneWidget);
      return action;
    }
    final nested = find.descendant(
      of: matching,
      matching: find.byType(OBAction),
    );
    if (nested.evaluate().isNotEmpty) {
      expect(nested, findsOneWidget);
      return nested;
    }
    final button = find.ancestor(
      of: matching,
      matching: find.byWidgetPredicate(
        (widget) => widget is ButtonStyleButton || widget is IconButton,
      ),
    );
    expect(
      button,
      findsOneWidget,
      reason: 'Pinned control has no enclosing OBAction or button.',
    );
    return button;
  }

  void expectPinnedAboveKeyboard(Finder matching) {
    expect(matching.hitTestable(), findsOneWidget);
    final box = tester.getRect(enclosingPinnedControl(matching));
    final view = tester.view;
    final logicalHeight = view.physicalSize.height / view.devicePixelRatio;
    final keyboardTop = logicalHeight - keyboardInset();
    expect(box.bottom, lessThanOrEqualTo(keyboardTop + 0.5));
    expect(box.top, lessThan(keyboardTop));
  }

  void expectSheetHeaderBelowStatusBar(String title) {
    final safeTop = tester.view.padding.top / tester.view.devicePixelRatio;
    final close = find.byTooltip('Schließen');
    expect(close.hitTestable(), findsOneWidget);
    final headerRow = find.ancestor(of: close, matching: find.byType(Row));
    expect(headerRow, findsOneWidget);
    final titleFinder = find.descendant(
      of: headerRow,
      matching: find.text(title),
    );
    expect(titleFinder, findsOneWidget);
    final titleBox = tester.getRect(titleFinder);
    expect(titleBox.top, greaterThanOrEqualTo(safeTop));
    expect(tester.getRect(close).top, greaterThanOrEqualTo(safeTop));
  }

  Future<void> waitKeyboardInset({required bool open}) async {
    var last = keyboardInset();
    var stable = 0;
    var pumped = 0;
    while (pumped < 60) {
      await tester.pump(const Duration(milliseconds: 16));
      if (tester.binding is LiveTestWidgetsFlutterBinding) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 16)),
        );
      }
      final inset = keyboardInset();
      final reached = open ? inset > 0 : inset == 0;
      if (reached && (inset - last).abs() < 0.5) {
        if (++stable >= 3) return;
      } else {
        stable = 0;
      }
      last = inset;
      pumped++;
    }
    throw FlutterError(
      open
          ? 'Keyboard inset did not become a stable positive value.'
          : 'Keyboard inset did not settle at zero.',
    );
  }

  Future<void> settleKeyboard(Finder field) async {
    await tester.tap(field);
    await tester.pump();
    await tester.showKeyboard(field);
    await tester.pump();
    await waitKeyboardInset(open: true);
  }

  Future<void> dismissKeyboard() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await waitKeyboardInset(open: false);
  }

  FoodEntry paperCoffee() => const FoodEntry(
    id: 'm2',
    date: '2026-09-15',
    meal: 'breakfast',
    label: 'Kaffee',
    source: FoodSource.unknown,
    sourceCode: 'unknown',
    confirmed: true,
    fibreG: 8.1,
    sodiumMg: 12,
    createdAt: 50,
    updatedAt: 50,
  );

  FoodEntry paperLentils() => oats(
    id: 'm3',
    meal: 'lunch',
    label: 'Linsensalat',
    kcal: 240,
    proteinG: 8,
    carbsG: 32,
    fatG: 3,
    createdAt: 3,
    updatedAt: 3,
  );

  void seedPaperFoods(_NutritionReviewRepo repository) {
    repository.seedFoodEntry(oats(id: 'm1', createdAt: 1, updatedAt: 1));
    repository.seedFoodEntry(paperCoffee());
    repository.seedFoodEntry(paperLentils());
  }

  MealDraft breakfastDraft() => MealDraft(
    id: 'd-breakfast',
    day: '2026-09-15',
    meal: 'breakfast',
    entries: const [
      MealDraftEntry(id: 'e-oats', label: 'Haferflocken mit Milch', kcal: 380),
      MealDraftEntry(
        id: 'e-coffee',
        label: 'Kaffee',
        source: FoodSource.unknown,
        sourceCode: 'unknown',
      ),
    ],
    updatedAt: DateTime(2026, 9, 15, 8),
  );

  Finder inFoodEntry(Finder matching) =>
      find.descendant(of: find.byType(OpenBandFoodEntry), matching: matching);

  Finder inDraft(Finder matching) =>
      find.descendant(of: find.byType(OBMealDraftSheet), matching: matching);

  Future<void> pumpShown() async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> tapSnackAction(String label) async {
    await tester.tap(find.widgetWithText(TextButton, label));
  }

  Future<OpenBandController> mountParent({
    required _NutritionReviewRepo repository,
    Brightness brightness = Brightness.light,
    double scale = 1,
    bool enableAdd = false,
    MealDraft? addDraft,
  }) async {
    final controller = OpenBandController(
      repository: repository,
      initialDay: '2026-09-15',
      band: repository.band,
      now: () => now,
    );
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: openBandTheme(brightness).copyWith(platform: TargetPlatform.iOS),
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => OpenBandNutrition(
            controller: controller,
            onAdd: enableAdd
                ? (meal) async {
                    final shown =
                        addDraft ??
                        await repository.readMealDraft('2026-09-15', meal);
                    if (shown == null || !context.mounted) return;
                    await showOpenBandMealDraft(context, repository, shown);
                  }
                : null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Future<void> removeRow(String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    final remove = find.byKey(const ValueKey('food-entry-remove'));
    await tester.scrollUntilVisible(remove, 80, scrollable: foodScrollable());
    expect(remove.hitTestable(), findsOneWidget);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ob-confirm-yes')));
    await pumpShown();
  }

  final detail = await openFoodEntry();
  expect(find.text('Eintrag'), findsOneWidget);
  expect(find.text('15. September'), findsOneWidget);
  expect(find.text('Frühstück'), findsOneWidget);
  expect(find.text('Haferflocken mit Milch'), findsOneWidget);
  expect(find.text('380'), findsOneWidget);
  expect(find.text('18 g'), findsOneWidget);
  expect(find.text('12 g'), findsOneWidget);
  expect(find.text('56 g'), findsOneWidget);
  expect(find.text('Menge'), findsOneWidget);
  expect(find.text('Uhrzeit'), findsOneWidget);
  expect(find.text('Quelle'), findsOneWidget);
  expect(find.text('Manuell'), findsOneWidget);
  expect(find.text('—'), findsNWidgets(2));
  expect(find.text('Eintrag entfernen'), findsOneWidget);
  expect(find.byKey(const ValueKey('food-entry-remove')), findsOneWidget);
  expect((await detail.readFoodEntry('oats')).current!.sourceCode, 'manual');
  await h.capture('nutrition-entry');

  await openFoodEntry(brightness: Brightness.dark);
  expect(find.text('Eintrag'), findsOneWidget);
  expect(find.text('Haferflocken mit Milch'), findsOneWidget);
  await h.capture('nutrition-entry-dark');

  await openFoodEntry(
    seed: oats(source: FoodSource.unknown, sourceCode: 'vendor-x', kcal: 10),
  );
  expect(find.text('Unbekannt'), findsOneWidget);
  expect(find.text('Manuell'), findsNothing);
  expect(find.bySemanticsLabel('Quelle Unbekannt vendor-x'), findsOneWidget);
  expect(find.text('10'), findsOneWidget);
  await h.capture('nutrition-entry-unknown');

  await openFoodEntry(
    seed: oats(kcal: 0, proteinG: 0, fibreG: 8.1, sugarG: 0, quantity: 0),
  );
  expect(find.text('0'), findsOneWidget);
  expect(find.text('0 g'), findsWidgets);
  expect(find.text('380'), findsNothing);
  await h.capture('nutrition-entry-zero');

  var photo = await openFoodEntry(
    seed: oats(
      source: FoodSource.photo,
      confirmed: false,
      kcal: 500,
      proteinG: 20,
      carbsG: 40,
      fatG: 10,
    ),
  );
  expect(find.text('Foto · unbestätigt'), findsOneWidget);
  expect(find.text('Foto'), findsNothing);
  expect(find.text('Manuell'), findsNothing);
  expect(find.text('Werte bestätigen'), findsNothing);
  expect(find.text('500'), findsNothing);
  expect(find.text('20 g'), findsNothing);
  expect(find.text('40 g'), findsNothing);
  expect(find.text('10 g'), findsNothing);
  expect(find.text('—'), findsWidgets);
  await h.capture('nutrition-entry-photo');

  await openEditor();
  await openLabeledPane('Nährwerte');
  expect(find.text('Foto · unbestätigt'), findsOneWidget);
  expect(find.text('Werte bestätigen'), findsOneWidget);
  expect(
    tester
        .widget<TextField>(find.byKey(const ValueKey('food-nutrient-kcal')))
        .controller!
        .text,
    '500',
  );
  await h.capture('nutrition-entry-photo-nutrients');
  await tester.tap(find.text('Werte bestätigen'));
  await tester.pumpAndSettle();
  expect(find.text('Eintrag bearbeiten'), findsOneWidget);
  expect(find.byKey(const ValueKey('food-entry-save')), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('food-entry-save')));
  await tester.pumpAndSettle();
  expect(find.text('Eintrag'), findsOneWidget);
  expect(find.text('500'), findsOneWidget);
  expect(find.text('20 g'), findsOneWidget);
  expect(find.text('Foto · unbestätigt'), findsNothing);
  expect(find.text('Foto'), findsOneWidget);
  final savedPhoto = (await photo.readFoodEntry('oats')).current!;
  expect(savedPhoto.confirmed, isTrue);
  expect(savedPhoto.kcal, 500);
  expect(savedPhoto.proteinG, 20);
  expect(savedPhoto.carbsG, 40);
  expect(savedPhoto.fatG, 10);
  expect(savedPhoto.source, FoodSource.photo);
  expect(savedPhoto.sourceCode, 'photo');
  await h.capture('nutrition-entry-photo-confirmed');

  await openFoodEntry(
    brightness: Brightness.dark,
    seed: oats(
      source: FoodSource.photo,
      confirmed: false,
      kcal: 500,
      proteinG: 20,
      carbsG: 40,
      fatG: 10,
    ),
  );
  await openEditor();
  await openLabeledPane('Nährwerte');
  expect(find.text('Foto · unbestätigt'), findsOneWidget);
  expect(find.text('Werte bestätigen'), findsOneWidget);
  expect(
    tester
        .widget<TextField>(find.byKey(const ValueKey('food-nutrient-kcal')))
        .controller!
        .text,
    '500',
  );
  await h.capture('nutrition-entry-photo-nutrients-dark');

  await openFoodEntry();
  await openEditor();
  expect(find.text('Lebensmittel'), findsOneWidget);
  expect(find.text('Mahlzeit'), findsOneWidget);
  expect(find.text('Menge'), findsOneWidget);
  expect(find.text('Uhrzeit'), findsOneWidget);
  expect(find.text('Nährwerte'), findsOneWidget);
  expect(find.text('Speichern'), findsOneWidget);
  expect(find.byKey(const ValueKey('food-entry-name')), findsOneWidget);
  expect(find.byKey(const ValueKey('food-entry-save')), findsOneWidget);
  await h.capture('nutrition-entry-editor');
  await openLabeledPane('Nährwerte');
  expect(find.text('Energie'), findsOneWidget);
  expect(find.text('Eiweiß'), findsOneWidget);
  expect(find.text('Kohlenhydrate'), findsOneWidget);
  expect(find.text('Fett'), findsOneWidget);
  expect(find.text('Ballaststoffe'), findsOneWidget);
  expect(find.text('Zucker'), findsOneWidget);
  expect(find.text('Gesättigte Fettsäuren'), findsOneWidget);
  expect(find.text('Natrium'), findsOneWidget);
  expect(find.text('Eisen'), findsOneWidget);
  expect(find.text('Calcium'), findsOneWidget);
  expect(find.byKey(const ValueKey('food-nutrient-kcal')), findsOneWidget);
  expect(find.byKey(const ValueKey('food-nutrient-proteinG')), findsOneWidget);
  expect(find.byKey(const ValueKey('food-nutrient-carbsG')), findsOneWidget);
  expect(find.byKey(const ValueKey('food-nutrient-fatG')), findsOneWidget);
  expect(find.byKey(const ValueKey('food-nutrient-fibreG')), findsOneWidget);
  expect(find.byKey(const ValueKey('food-nutrient-sugarG')), findsOneWidget);
  expect(find.byKey(const ValueKey('food-nutrient-satFatG')), findsOneWidget);
  expect(find.byKey(const ValueKey('food-nutrient-sodiumMg')), findsOneWidget);
  expect(find.byKey(const ValueKey('food-nutrient-ironMg')), findsOneWidget);
  expect(find.byKey(const ValueKey('food-nutrient-calciumMg')), findsOneWidget);
  expectPinned(find.text('Übernehmen'));
  await h.capture('nutrition-entry-nutrients');

  await openFoodEntry(brightness: Brightness.dark);
  await openEditor();
  await h.capture('nutrition-entry-editor-dark');
  await openLabeledPane('Nährwerte');
  expect(find.text('Energie'), findsOneWidget);
  expectPinned(find.text('Übernehmen'));
  await h.capture('nutrition-entry-nutrients-dark');

  await openFoodEntry(id: 'missing', seed: oats());
  expect(find.text('Eintrag nicht gefunden'), findsOneWidget);
  expect(find.text('Selbst eintragen'), findsNothing);
  await h.capture('nutrition-entry-missing');

  final readFail = await openFoodEntry(failRead: true);
  expect(find.text('Eintrag nicht geladen'), findsOneWidget);
  expect(find.text('Erneut versuchen'), findsOneWidget);
  await h.capture('nutrition-entry-read-error');
  readFail.failFoodRead = false;
  await tester.tap(find.text('Erneut versuchen'));
  await tester.pumpAndSettle();
  expect(find.text('Haferflocken mit Milch'), findsOneWidget);
  expect(find.text('Eintrag nicht geladen'), findsNothing);
  expect(
    (await readFail.readFoodEntry('oats')).current!.label,
    'Haferflocken mit Milch',
  );
  await h.capture('nutrition-entry-read-retry');

  final saveFail = await openFoodEntry();
  await openEditor();
  await tester.enterText(
    find.byKey(const ValueKey('food-entry-name')),
    'Haferflocken mit Hafermilch',
  );
  await tester.pump();
  saveFail.failFoodWrite = true;
  await tester.tap(find.byKey(const ValueKey('food-entry-save')));
  await tester.pumpAndSettle();
  expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
  expect(find.text('Erneut versuchen'), findsOneWidget);
  expect(
    tester
        .widget<TextField>(find.byKey(const ValueKey('food-entry-name')))
        .controller!
        .text,
    'Haferflocken mit Hafermilch',
  );
  expect(
    (await saveFail.readFoodEntry('oats')).current!.label,
    'Haferflocken mit Milch',
  );
  await h.capture('nutrition-entry-save-failure');
  saveFail.failFoodWrite = false;
  await tester.tap(find.text('Erneut versuchen'));
  await tester.pumpAndSettle();
  expect(find.text('Eintrag bearbeiten'), findsNothing);
  expect(find.text('Haferflocken mit Hafermilch'), findsOneWidget);
  final retried = (await saveFail.readFoodEntry('oats')).current!;
  expect(retried.label, 'Haferflocken mit Hafermilch');
  expect(retried.sourceCode, 'manual');
  expect(retried.kcal, 380);
  await h.capture('nutrition-entry-save-retry');

  final conflictRepo = await openFoodEntry();
  final original = (await conflictRepo.readFoodEntry('oats')).current!;
  await openEditor();
  await tester.enterText(
    find.byKey(const ValueKey('food-entry-name')),
    'Haferflocken mit Hafermilch',
  );
  await tester.pump();
  expect(
    (await conflictRepo.saveFoodEntry(
      original,
      oats(kcal: 390, updatedAt: original.updatedAt ?? 1000),
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
  await h.capture('nutrition-entry-conflict');
  await tester.tap(find.text('Neu laden'));
  await tester.pumpAndSettle();
  expect(find.text('Änderungen verwerfen?'), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('ob-confirm-yes')));
  await tester.pumpAndSettle();
  expect(find.text('Eintrag'), findsOneWidget);
  expect(find.text('390'), findsOneWidget);
  expect(find.text('Haferflocken mit Milch'), findsOneWidget);
  expect((await conflictRepo.readFoodEntry('oats')).current!.kcal, 390);
  await h.capture('nutrition-entry-conflict-reload');

  final quantityRepo = await openFoodEntry(seed: oats(quantity: 150));
  await openEditor();
  expect(find.text('150 g'), findsOneWidget);
  await openLabeledPane('Menge');
  expect(find.byKey(const ValueKey('food-qty-amount')), findsOneWidget);
  expect(find.byKey(const ValueKey('food-qty-unit')), findsOneWidget);
  expect(find.byKey(const ValueKey('food-qty-scale')), findsOneWidget);
  expect(find.text('Nährwerte anpassen'), findsOneWidget);
  expect(find.text('Menge entfernen'), findsOneWidget);
  expect(find.byTooltip('Schließen'), findsOneWidget);
  expect(find.text('Übernehmen'), findsOneWidget);
  await tester.enterText(find.byKey(const ValueKey('food-qty-amount')), '75');
  await tester.pump();
  await tester.tap(find.text('Nährwerte anpassen'));
  await tester.pump();
  await dismissKeyboard();
  expect(find.text('Menge entfernen').hitTestable(), findsOneWidget);
  expect(find.byTooltip('Schließen').hitTestable(), findsOneWidget);
  await h.capture('nutrition-entry-quantity');
  await tester.tap(find.text('Übernehmen'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('food-entry-save')));
  await tester.pumpAndSettle();
  final scaled = (await quantityRepo.readFoodEntry('oats')).current!;
  expect(scaled.quantity, 75);
  expect(scaled.unit, 'g');
  expect(scaled.kcal, 190);
  expect(scaled.proteinG, 9);
  expect(scaled.carbsG, 28);
  expect(scaled.fatG, 6);

  await openFoodEntry();
  await openEditor();
  await openLabeledPane('Menge');
  expect(
    tester
        .widget<TextField>(find.byKey(const ValueKey('food-qty-amount')))
        .controller!
        .text,
    '',
  );
  expect(find.byKey(const ValueKey('food-qty-scale')), findsNothing);
  expect(find.text('Nährwerte anpassen'), findsNothing);
  expect(find.text('Menge entfernen'), findsNothing);
  expect(find.byTooltip('Schließen'), findsOneWidget);
  await dismissKeyboard();
  await h.capture('nutrition-entry-quantity-unknown');

  await openFoodEntry(brightness: Brightness.dark, seed: oats(quantity: 150));
  await openEditor();
  await openLabeledPane('Menge');
  expect(find.byKey(const ValueKey('food-qty-amount')), findsOneWidget);
  expect(find.text('Nährwerte anpassen'), findsOneWidget);
  await tester.enterText(find.byKey(const ValueKey('food-qty-amount')), '75');
  await tester.pump();
  await tester.tap(find.text('Nährwerte anpassen'));
  await tester.pump();
  await dismissKeyboard();
  expect(find.text('Menge entfernen').hitTestable(), findsOneWidget);
  await h.capture('nutrition-entry-quantity-dark');

  final timeRepo = await openFoodEntry(seed: oats(atTs: knownTs));
  await openEditor();
  expect(find.text('08:15'), findsOneWidget);
  await openTime();
  expect(timeFieldText(), '08:15');
  expect(
    tester
        .widget<TextField>(find.byKey(const ValueKey('food-time')))
        .decoration!
        .hintText,
    'HH:mm',
  );
  expect(find.text('12:00'), findsNothing);
  expect(find.text('Uhrzeit entfernen'), findsOneWidget);
  expect(find.byTooltip('Schließen'), findsOneWidget);
  expect(find.text('Übernehmen'), findsOneWidget);
  expect(find.text('15. September'), findsWidgets);
  await dismissKeyboard();
  await h.capture('nutrition-entry-time');
  expect((await timeRepo.readFoodEntry('oats')).current!.atTs, knownTs);
  await tester.tap(find.text('Übernehmen'));
  await tester.pumpAndSettle();
  expect(find.text('Eintrag bearbeiten'), findsOneWidget);
  expect(find.text('08:15'), findsOneWidget);
  expect((await timeRepo.readFoodEntry('oats')).current!.atTs, knownTs);
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('food-entry-note')),
    80,
    scrollable: foodScrollable(),
  );
  await tester.enterText(
    find.byKey(const ValueKey('food-entry-note')),
    'zeit unverändert',
  );
  await tester.pump();
  await waitKeyboardInset(open: true);
  expectPinnedAboveKeyboard(find.byKey(const ValueKey('food-entry-save')));
  await tester.tap(find.byKey(const ValueKey('food-entry-save')));
  await tester.pumpAndSettle();
  final savedTime = (await timeRepo.readFoodEntry('oats')).current!;
  expect(savedTime.date, '2026-09-15');
  expect(savedTime.note, 'zeit unverändert');
  final persisted = DateTime.fromMillisecondsSinceEpoch(
    savedTime.atTs! * 1000,
  ).toLocal();
  expect(persisted.year, 2026);
  expect(persisted.month, 9);
  expect(persisted.day, 15);
  expect(persisted.hour, 8);
  expect(persisted.minute, 15);
  expect(persisted.second, 42);
  expect(savedTime.atTs, knownTs);

  await openEditor();
  await openTime();
  expect(timeFieldText(), '08:15');
  expect(find.text('Uhrzeit entfernen'), findsOneWidget);
  await tester.tap(find.text('Uhrzeit entfernen'));
  await tester.pumpAndSettle();
  expect((await timeRepo.readFoodEntry('oats')).current!.atTs, isNotNull);
  await tester.tap(find.byKey(const ValueKey('food-entry-save')));
  await tester.pumpAndSettle();
  final cleared = (await timeRepo.readFoodEntry('oats')).current!;
  expect(cleared.atTs, isNull);
  expect(cleared.date, '2026-09-15');

  await openFoodEntry();
  await openEditor();
  await openTime();
  expect(timeFieldText(), '');
  expect(
    tester
        .widget<TextField>(find.byKey(const ValueKey('food-time')))
        .decoration!
        .hintText,
    'HH:mm',
  );
  expect(find.text('12:00'), findsNothing);
  expect(find.text('Uhrzeit entfernen'), findsNothing);
  expect(
    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Übernehmen'))
        .onPressed,
    isNull,
  );
  await dismissKeyboard();
  await h.capture('nutrition-entry-time-unknown');

  await openFoodEntry(seed: oats(atTs: knownTs));
  await openEditor();
  await openTime();
  await tester.enterText(find.byKey(const ValueKey('food-time')), '25:30');
  await tester.pump();
  expect(timeFieldText(), '25:30');
  await waitKeyboardInset(open: true);
  expectPinnedAboveKeyboard(find.text('Übernehmen'));
  await tester.tap(find.text('Übernehmen'));
  await tester.pumpAndSettle();
  expect(find.text('Uhrzeit ungültig'), findsOneWidget);
  expect(timeFieldText(), '25:30');
  expect(find.byKey(const ValueKey('food-time')), findsOneWidget);
  await dismissKeyboard();
  await h.capture('nutrition-entry-time-error');

  await openFoodEntry(
    brightness: Brightness.dark,
    seed: oats(atTs: knownTs),
  );
  await openEditor();
  await openTime();
  expect(timeFieldText(), '08:15');
  expect(find.text('12:00'), findsNothing);
  expect(find.text('Uhrzeit entfernen'), findsOneWidget);
  await dismissKeyboard();
  await h.capture('nutrition-entry-time-dark');

  final removedRepo = await openFoodEntry();
  await tester.tap(find.byKey(const ValueKey('food-entry-remove')));
  await tester.pumpAndSettle();
  expect(find.text('Eintrag entfernen?'), findsOneWidget);
  await h.capture('nutrition-entry-remove-confirm');
  await tester.tap(find.text('Entfernen'));
  await tester.pumpAndSettle();
  expect(popped?.changed, isTrue);
  expect(popped?.removed?.id, 'oats');
  expect(popped?.removed?.label, 'Haferflocken mit Milch');
  expect(popped?.removed?.kcal, 380);
  expect(popped?.removed?.proteinG, 18);
  expect(popped?.removed?.sourceCode, 'manual');
  expect(popped?.removed?.confirmed, isTrue);
  expect((await removedRepo.readFoodEntry('oats')).missing, isTrue);

  await openFoodEntry(scale: 2);
  expect(tester.takeException(), isNull);
  expect(find.text('Eintrag'), findsOneWidget);
  await h.capture('nutrition-entry-large');
  await tester.scrollUntilVisible(
    find.text('Eintrag entfernen'),
    80,
    scrollable: foodScrollable(),
  );
  expect(
    find.byKey(const ValueKey('food-entry-remove')).hitTestable(),
    findsOneWidget,
  );
  await h.capture('nutrition-entry-large-scrolled');

  await openFoodEntry(scale: 2);
  await openEditor();
  expect(find.text('Eintrag bearbeiten'), findsOneWidget);
  expectPinned(find.text('Speichern'));
  await h.capture('nutrition-entry-editor-large');
  await settleKeyboard(find.byKey(const ValueKey('food-entry-name')));
  expect(keyboardInset(), greaterThan(0));
  expectPinnedAboveKeyboard(find.text('Speichern'));
  await h.capture('nutrition-entry-editor-keyboard');
  await dismissKeyboard();
  expect(keyboardInset(), 0);
  await tester.scrollUntilVisible(
    find.text('Notiz'),
    80,
    scrollable: foodScrollable(),
  );
  expectPinned(find.byKey(const ValueKey('food-entry-save')));
  await h.capture('nutrition-entry-editor-large-scrolled');

  await openFoodEntry(scale: 2);
  await openEditor();
  await openLabeledPane('Nährwerte');
  expect(find.text('Energie'), findsOneWidget);
  expectPinned(find.text('Übernehmen'));
  await h.capture('nutrition-entry-nutrients-large');
  await settleKeyboard(find.byKey(const ValueKey('food-nutrient-kcal')));
  expect(keyboardInset(), greaterThan(0));
  expectPinnedAboveKeyboard(find.text('Übernehmen'));
  await h.capture('nutrition-entry-nutrients-keyboard');
  await dismissKeyboard();
  expect(keyboardInset(), 0);
  await tester.scrollUntilVisible(
    find.text('Calcium'),
    80,
    scrollable: foodScrollable(),
  );
  expect(find.text('Calcium'), findsOneWidget);
  expectPinned(find.text('Übernehmen'));
  await h.capture('nutrition-entry-nutrients-large-scrolled');

  await openFoodEntry(scale: 2, seed: oats(quantity: 150));
  await openEditor();
  await openLabeledPane('Menge');
  expect(find.byKey(const ValueKey('food-qty-amount')), findsOneWidget);
  expect(find.text('Nährwerte anpassen'), findsOneWidget);
  expect(find.text('Menge entfernen'), findsOneWidget);
  expectPinned(find.text('Übernehmen'));
  await settleKeyboard(find.byKey(const ValueKey('food-qty-amount')));
  expect(keyboardInset(), greaterThan(0));
  expectPinnedAboveKeyboard(find.text('Übernehmen'));
  expectSheetHeaderBelowStatusBar('Menge');
  await h.capture('nutrition-entry-quantity-keyboard');
  await dismissKeyboard();
  expect(keyboardInset(), 0);

  await openFoodEntry(scale: 2, seed: oats(atTs: knownTs));
  await openEditor();
  await openTime();
  expect(timeFieldText(), '08:15');
  expectPinned(find.text('Übernehmen'));
  await settleKeyboard(find.byKey(const ValueKey('food-time')));
  expect(keyboardInset(), greaterThan(0));
  expectPinnedAboveKeyboard(find.text('Übernehmen'));
  expectSheetHeaderBelowStatusBar('Uhrzeit');
  await h.capture('nutrition-entry-time-keyboard');
  await dismissKeyboard();
  expect(keyboardInset(), 0);

  final parentRepo = await _loadNutritionReviewRepo();
  seedPaperFoods(parentRepo);
  var parent = await mountParent(repository: parentRepo);
  expect(find.byType(OpenBandNutrition), findsOneWidget);
  expect(find.text('Haferflocken mit Milch'), findsOneWidget);
  expect(find.text('Kaffee'), findsOneWidget);
  expect(find.text('Linsensalat'), findsOneWidget);
  expect(find.text('380'), findsOneWidget);
  expect(find.text('240'), findsOneWidget);
  expect((await parentRepo.readFoodEntry('m1')).current!.proteinG, 18);
  expect((await parentRepo.readFoodEntry('m1')).current!.fatG, 12);
  expect((await parentRepo.readFoodEntry('m1')).current!.carbsG, 56);
  expect((await parentRepo.readFoodEntry('m3')).current!.proteinG, 8);
  expect((await parentRepo.readFoodEntry('m3')).current!.fatG, 3);
  expect((await parentRepo.readFoodEntry('m3')).current!.carbsG, 32);
  expect(
    (await parentRepo.readFoodEntry('m2')).current!.source,
    FoodSource.unknown,
  );
  await h.capture('nutrition-entry-parent');

  await tester.tap(find.text('Kaffee'));
  await tester.pumpAndSettle();
  expect(inFoodEntry(find.text('Kaffee')), findsOneWidget);
  expect(inFoodEntry(find.text('Unbekannt')), findsOneWidget);
  expect(inFoodEntry(find.text('Manuell')), findsNothing);
  expect(inFoodEntry(find.text('380')), findsNothing);
  expect(inFoodEntry(find.text('18 g')), findsNothing);
  expect(inFoodEntry(find.text('08:15')), findsNothing);
  expect(inFoodEntry(find.text('—')), findsWidgets);
  expect(find.bySemanticsLabel('Quelle Unbekannt unknown'), findsOneWidget);
  expect((await parentRepo.readFoodEntry('m2')).current!.fibreG, 8.1);
  expect((await parentRepo.readFoodEntry('m2')).current!.kcal, isNull);
  expect((await parentRepo.readFoodEntry('m2')).current!.atTs, isNull);
  await h.capture('nutrition-entry-parent-coffee');
  await tester.tap(find.byTooltip('Zurück'));
  await tester.pumpAndSettle();
  expect(find.byType(OpenBandFoodEntry), findsNothing);
  expect(find.text('Kaffee'), findsOneWidget);

  await tester.tap(find.text('Haferflocken mit Milch'));
  await tester.pumpAndSettle();
  await openEditor();
  await tester.enterText(
    find.byKey(const ValueKey('food-entry-name')),
    'Hafer neu',
  );
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('food-entry-save')));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Zurück'));
  await tester.pumpAndSettle();
  expect(find.text('Hafer neu'), findsOneWidget);
  expect(find.text('Haferflocken mit Milch'), findsNothing);
  expect((await parentRepo.readFoodEntry('m1')).current!.label, 'Hafer neu');
  expect((await parentRepo.readFoodEntry('m1')).current!.proteinG, 18);
  await h.capture('nutrition-entry-parent-edited');
  parent.dispose();

  seedPaperFoods(parentRepo);
  parent = await mountParent(repository: parentRepo);
  await removeRow('Kaffee');
  expect(find.byType(OpenBandFoodEntry), findsNothing);
  expect(find.text('Kaffee'), findsNothing);
  expect(find.text('Eintrag entfernt'), findsOneWidget);
  expect(find.text('Rückgängig'), findsOneWidget);
  await h.capture('nutrition-entry-undo');
  await tapSnackAction('Rückgängig');
  await pumpShown();
  final restoredCoffee = (await parentRepo.readFoodEntry('m2')).current!;
  expect(restoredCoffee.label, 'Kaffee');
  expect(restoredCoffee.source, FoodSource.unknown);
  expect(restoredCoffee.sourceCode, 'unknown');
  expect(restoredCoffee.kcal, isNull);
  expect(restoredCoffee.fibreG, 8.1);
  expect(restoredCoffee.sodiumMg, 12);
  expect(restoredCoffee.atTs, isNull);
  expect(restoredCoffee.createdAt, 50);
  expect(restoredCoffee.updatedAt, 50);
  expect(find.text('Kaffee'), findsOneWidget);
  expect(parentRepo.restores, 1);
  parent.dispose();

  seedPaperFoods(parentRepo);
  parent = await mountParent(
    repository: parentRepo,
    brightness: Brightness.dark,
  );
  await removeRow('Kaffee');
  expect(find.text('Eintrag entfernt'), findsOneWidget);
  expect(find.text('Rückgängig'), findsOneWidget);
  await h.capture('nutrition-entry-undo-dark');
  await tapSnackAction('Rückgängig');
  await pumpShown();
  expect(find.text('Kaffee'), findsOneWidget);
  parent.dispose();

  seedPaperFoods(parentRepo);
  parent = await mountParent(repository: parentRepo, scale: 2);
  await removeRow('Haferflocken mit Milch');
  expect(find.text('Eintrag entfernt'), findsOneWidget);
  expect(find.text('Rückgängig'), findsOneWidget);
  final undoAction = tester.getRect(
    find.widgetWithText(TextButton, 'Rückgängig'),
  );
  expect(undoAction.height, greaterThanOrEqualTo(44));
  await h.capture('nutrition-entry-undo-2x');
  await tapSnackAction('Rückgängig');
  await pumpShown();
  expect(find.text('Haferflocken mit Milch'), findsOneWidget);
  expect((await parentRepo.readFoodEntry('m1')).current!.proteinG, 18);
  parent.dispose();

  seedPaperFoods(parentRepo);
  parentRepo.restores = 0;
  parent = await mountParent(repository: parentRepo);
  await removeRow('Kaffee');
  parentRepo.failFoodWrite = true;
  await tapSnackAction('Rückgängig');
  await pumpShown();
  expect(find.text('Wiederherstellen fehlgeschlagen'), findsOneWidget);
  expect((await parentRepo.readFoodEntry('m2')).missing, isTrue);
  expect(parentRepo.restores, 1);
  await h.capture('nutrition-entry-undo-error');
  parentRepo.failFoodWrite = false;
  await tapSnackAction('Erneut');
  await pumpShown();
  expect((await parentRepo.readFoodEntry('m2')).current!.fibreG, 8.1);
  expect(find.text('Kaffee'), findsOneWidget);
  expect(parentRepo.restores, 2);
  parent.dispose();

  seedPaperFoods(parentRepo);
  parentRepo.restores = 0;
  parent = await mountParent(repository: parentRepo);
  await removeRow('Kaffee');
  parentRepo.seedFoodEntry(
    const FoodEntry(
      id: 'm2',
      date: '2026-09-15',
      meal: 'breakfast',
      label: 'Other',
      kcal: 90,
      createdAt: 9,
      updatedAt: 9,
    ),
  );
  await tapSnackAction('Rückgängig');
  await pumpShown();
  final conflicted = (await parentRepo.readFoodEntry('m2')).current!;
  expect(conflicted.label, 'Other');
  expect(conflicted.kcal, 90);
  expect(conflicted.fibreG, isNull);
  expect(find.text('Eintrag wurde geändert'), findsOneWidget);
  expect(find.text('Neu laden'), findsOneWidget);
  expect(find.text('Wiederherstellen fehlgeschlagen'), findsNothing);
  expect(parentRepo.restores, 1);
  await h.capture('nutrition-entry-undo-conflict');
  await tapSnackAction('Neu laden');
  await pumpShown();
  expect(parentRepo.restores, 1);
  expect((await parentRepo.readFoodEntry('m2')).current!.label, 'Other');
  parent.dispose();

  seedPaperFoods(parentRepo);
  parentRepo.restores = 0;
  parent = await mountParent(repository: parentRepo);
  await removeRow('Kaffee');
  parentRepo.failDayRead = true;
  await tapSnackAction('Rückgängig');
  await pumpShown();
  expect(parent.loadError, isA<StateError>());
  expect((await parentRepo.readFoodEntry('m2')).current!.fibreG, 8.1);
  expect(parentRepo.restores, 1);
  expect(find.text('Einträge konnten nicht geladen werden.'), findsOneWidget);
  parentRepo.failDayRead = false;
  await tapSnackAction('Erneut');
  await pumpShown();
  expect(parent.loadError, isNull);
  expect(find.text('Kaffee'), findsOneWidget);
  expect(parentRepo.restores, 1);
  parent.dispose();

  final draftRepo = await _loadNutritionReviewRepo();
  seedPaperFoods(draftRepo);
  await draftRepo.saveMealDraft(breakfastDraft());
  parent = await mountParent(repository: draftRepo, enableAdd: true);
  await tester.tap(find.byTooltip('Frühstück ergänzen'));
  await tester.pumpAndSettle();
  expect(find.byType(OBMealDraftSheet), findsOneWidget);
  expect(inDraft(find.text('Haferflocken mit Milch')), findsOneWidget);
  expect(inDraft(find.text('Kaffee')), findsOneWidget);
  expect(inDraft(find.text('380 kcal')), findsOneWidget);
  expect(inDraft(find.text('—')), findsOneWidget);
  expect(find.byTooltip('Schließen'), findsOneWidget);
  expect(inDraft(find.text('Speichern')), findsOneWidget);
  await h.capture('nutrition-draft');
  parent.dispose();

  await draftRepo.saveMealDraft(breakfastDraft());
  parent = await mountParent(
    repository: draftRepo,
    brightness: Brightness.dark,
    enableAdd: true,
  );
  await tester.tap(find.byTooltip('Frühstück ergänzen'));
  await tester.pumpAndSettle();
  expect(find.byType(OBMealDraftSheet), findsOneWidget);
  expect(inDraft(find.text('380 kcal')), findsOneWidget);
  await h.capture('nutrition-draft-dark');
  parent.dispose();

  await draftRepo.saveMealDraft(breakfastDraft());
  draftRepo.failFoodWrite = true;
  parent = await mountParent(repository: draftRepo, enableAdd: true);
  await tester.tap(find.byTooltip('Frühstück ergänzen'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Speichern'));
  await tester.pumpAndSettle();
  expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
  expect(find.text('Erneut versuchen'), findsOneWidget);
  expect(find.text('Speichern'), findsNothing);
  expect(await draftRepo.readMealDraft('2026-09-15', 'breakfast'), isNotNull);
  expect((await draftRepo.readFoodEntry('e-oats')).missing, isTrue);
  await h.capture('nutrition-draft-save-failure');
  draftRepo.failFoodWrite = false;
  final commitsBeforeRetry = draftRepo.commits;
  await tester.tap(find.text('Erneut versuchen'));
  await tester.pumpAndSettle();
  expect(find.byType(OBMealDraftSheet), findsNothing);
  expect((await draftRepo.readFoodEntry('e-oats')).current!.kcal, 380);
  expect(draftRepo.commits, commitsBeforeRetry + 1);
  parent.dispose();

  final draftConflictRepo = await _loadNutritionReviewRepo();
  seedPaperFoods(draftConflictRepo);
  final staleBreakfast = breakfastDraft();
  await draftConflictRepo.saveMealDraft(staleBreakfast);
  await draftConflictRepo.discardMealDraft('d-breakfast');
  parent = await mountParent(
    repository: draftConflictRepo,
    enableAdd: true,
    addDraft: staleBreakfast,
  );
  await tester.tap(find.byTooltip('Frühstück ergänzen'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Speichern'));
  await tester.pumpAndSettle();
  expect(find.text('Entwurf nicht gespeichert'), findsOneWidget);
  expect(inDraft(find.text('Speichern')), findsNothing);
  expect(inDraft(find.text('380 kcal')), findsOneWidget);
  expect((await draftConflictRepo.readFoodEntry('e-oats')).missing, isTrue);
  await h.capture('nutrition-draft-conflict');
  await tester.tap(find.text('Neu laden'));
  await tester.pumpAndSettle();
  expect(find.text('Entwurf nicht gefunden'), findsOneWidget);
  expect(inDraft(find.text('380 kcal')), findsNothing);
  expect(find.text('Entwurf nicht gespeichert'), findsNothing);
  expect(find.text('Speichern'), findsNothing);
  expect(find.text('Haferflocken mit Milch'), findsOneWidget);
  expect(find.text('Kaffee'), findsOneWidget);
  await h.capture('nutrition-draft-missing');
  parent.dispose();

  final readRepo = await _loadNutritionReviewRepo();
  seedPaperFoods(readRepo);
  final staleRead = breakfastDraft();
  await readRepo.saveMealDraft(staleRead);
  await readRepo.discardMealDraft('d-breakfast');
  await readRepo.saveMealDraft(
    MealDraft(
      id: 'd-now',
      day: '2026-09-15',
      meal: 'breakfast',
      entries: staleRead.entries,
      updatedAt: DateTime(2026, 9, 15, 9),
    ),
  );
  parent = await mountParent(
    repository: readRepo,
    enableAdd: true,
    addDraft: staleRead,
  );
  await tester.tap(find.byTooltip('Frühstück ergänzen'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Speichern'));
  await tester.pumpAndSettle();
  readRepo.failDraftRead = true;
  final commitsBeforeRead = readRepo.commits;
  await tester.tap(find.text('Neu laden'));
  await tester.pumpAndSettle();
  expect(find.text('Entwurf nicht geladen'), findsOneWidget);
  expect(find.text('Entwurf nicht gespeichert'), findsNothing);
  expect(inDraft(find.text('380 kcal')), findsNothing);
  expect(inDraft(find.text('Speichern')), findsNothing);
  expect(readRepo.commits, commitsBeforeRead);
  await h.capture('nutrition-draft-read-error');
  readRepo.failDraftRead = false;
  await tester.tap(find.text('Neu laden'));
  await tester.pumpAndSettle();
  expect(inDraft(find.text('380 kcal')), findsOneWidget);
  expect(inDraft(find.text('Speichern')), findsOneWidget);
  expect(readRepo.commits, commitsBeforeRead);
  parent.dispose();

  final manyRepo = await _loadNutritionReviewRepo();
  seedPaperFoods(manyRepo);
  final many = MealDraft(
    id: 'd-many',
    day: '2026-09-15',
    meal: 'breakfast',
    entries: [
      for (var i = 1; i <= 8; i++)
        MealDraftEntry(
          id: 'e-$i',
          label: 'Sehr langes Lebensmittel $i mit extra Text',
          kcal: 100.0 * i,
        ),
    ],
    updatedAt: DateTime(2026, 9, 15, 8),
  );
  await manyRepo.saveMealDraft(many);
  parent = await mountParent(repository: manyRepo, scale: 2, enableAdd: true);
  await tester.tap(find.byTooltip('Frühstück ergänzen'));
  await tester.pumpAndSettle();
  expect(find.byType(OBMealDraftSheet), findsOneWidget);
  expectPinned(inDraft(find.text('Speichern')));
  expectSheetHeaderBelowStatusBar('Frühstück');
  await h.capture('nutrition-draft-large');
  await tester.scrollUntilVisible(
    find.text('Sehr langes Lebensmittel 8 mit extra Text'),
    80,
    scrollable: find.descendant(
      of: find.byType(OBMealDraftSheet),
      matching: find.byType(Scrollable),
    ),
  );
  expectPinned(inDraft(find.text('Speichern')));
  expectSheetHeaderBelowStatusBar('Frühstück');
  await h.capture('nutrition-draft-large-scrolled');
  parent.dispose();
}
