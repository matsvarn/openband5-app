part of 'harness.dart';

Future<void> reviewNutritionParent(ReviewHarness h) async {
  final tester = h.tester;
  const day = '2026-09-15';
  final now = DateTime(2026, 9, 15, 9, 41);

  FoodEntry paperFood({
    required String id,
    required String date,
    required String meal,
    required String label,
    double? kcal,
    double? proteinG,
    double? carbsG,
    double? fatG,
    FoodSource source = FoodSource.manual,
    String? sourceCode,
    int createdAt = 1,
    int updatedAt = 1,
  }) => FoodEntry(
    id: id,
    date: date,
    meal: meal,
    label: label,
    kcal: kcal,
    proteinG: proteinG,
    carbsG: carbsG,
    fatG: fatG,
    source: source,
    sourceCode: sourceCode ?? source.name,
    confirmed: true,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  void seedPaperDay(
    _NutritionParentReviewRepo repository, {
    bool water = true,
    double? waterMl = 1250,
    bool weekVariants = true,
  }) {
    repository.seedFoodEntry(
      paperFood(
        id: 'm1',
        date: day,
        meal: 'breakfast',
        label: 'Haferflocken mit Milch',
        kcal: 380,
        proteinG: 18,
        carbsG: 56,
        fatG: 12,
        createdAt: 1,
        updatedAt: 1,
      ),
    );
    repository.seedFoodEntry(
      paperFood(
        id: 'm2',
        date: day,
        meal: 'breakfast',
        label: 'Kaffee',
        source: FoodSource.unknown,
        sourceCode: 'unknown',
        createdAt: 50,
        updatedAt: 50,
      ),
    );
    repository.seedFoodEntry(
      paperFood(
        id: 'm3',
        date: day,
        meal: 'lunch',
        label: 'Linsensalat',
        kcal: 240,
        proteinG: 8,
        carbsG: 32,
        fatG: 3,
        createdAt: 3,
        updatedAt: 3,
      ),
    );
    if (weekVariants) {
      repository.seedFoodEntry(
        paperFood(
          id: 'zero-kcal',
          date: '2026-09-12',
          meal: 'snack',
          label: 'Wasserzwieback',
          kcal: 0,
          createdAt: 12,
          updatedAt: 12,
        ),
      );
      repository.seedFoodEntry(
        paperFood(
          id: 'partial-kcal',
          date: '2026-09-13',
          meal: 'lunch',
          label: 'Kaffee',
          source: FoodSource.unknown,
          sourceCode: 'unknown',
          createdAt: 13,
          updatedAt: 13,
        ),
      );
      repository.seedFoodEntry(
        paperFood(
          id: 'hist-14',
          date: '2026-09-14',
          meal: 'lunch',
          label: 'Linsensalat',
          kcal: 240,
          proteinG: 8,
          carbsG: 32,
          fatG: 3,
          createdAt: 14,
          updatedAt: 14,
        ),
      );
    }
    if (water && waterMl != null) {
      repository.seedJournalEditor(
        day: day,
        metrics: {'water_ml': JournalMetricValue(waterMl)},
      );
    }
  }

  Finder parentScrollable() => find.descendant(
    of: find.byType(OpenBandNutrition),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    ),
  );

  Future<void> revealHittable(Finder target) async {
    final scrollable = parentScrollable().first;
    var scrolls = 0;
    while (target.hitTestable().evaluate().isEmpty) {
      if (scrolls >= 24) {
        throw FlutterError(
          'Control is not hit-testable after direction-aware scrolling.',
        );
      }
      if (target.evaluate().isEmpty) {
        await tester.drag(scrollable, const Offset(0, -64));
        await tester.pump();
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
  }

  void expectFooterHittable() {
    expect(
      find.byKey(const ValueKey('nutrition-search')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('nutrition-add')).hitTestable(),
      findsOneWidget,
    );
  }

  double parentScrollPixels() =>
      tester.state<ScrollableState>(parentScrollable().first).position.pixels;

  Future<void> restoreParentScroll(double offset) async {
    final position = tester
        .state<ScrollableState>(parentScrollable().first)
        .position;
    position.jumpTo(
      offset.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
    await tester.pump();
  }

  Future<void> expectPaperDayMeals(
    _NutritionParentReviewRepo repository,
  ) async {
    final oats = await repository.readFoodEntry('m1');
    expect(oats.current, isNotNull);
    expect(oats.current!.label, 'Haferflocken mit Milch');
    expect(oats.current!.source, FoodSource.manual);
    expect(oats.current!.kcal, 380);
    final coffee = await repository.readFoodEntry('m2');
    expect(coffee.current, isNotNull);
    expect(coffee.current!.label, 'Kaffee');
    expect(coffee.current!.source, FoodSource.unknown);
    expect(coffee.current!.sourceCode, 'unknown');
    expect(coffee.current!.kcal, isNull);
    final lentils = await repository.readFoodEntry('m3');
    expect(lentils.current, isNotNull);
    expect(lentils.current!.label, 'Linsensalat');
    expect(lentils.current!.source, FoodSource.manual);
    expect(lentils.current!.kcal, 240);

    final oatsRow = find.byKey(const ValueKey('food-row-m1'));
    final breakfastAdd = find.byTooltip('Frühstück ergänzen');
    await revealHittable(breakfastAdd);
    final breakfast = find.ancestor(
      of: breakfastAdd,
      matching: find.byType(OBMealSection),
    );
    expect(breakfast, findsOneWidget);
    expect(
      find.descendant(of: breakfast, matching: find.text('Frühstück')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: breakfast, matching: find.text('Teilweise')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: breakfast, matching: find.text('380 kcal')),
      findsNWidgets(2),
    );

    await revealHittable(oatsRow);
    expect(
      find.descendant(
        of: oatsRow,
        matching: find.text('Haferflocken mit Milch'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: oatsRow, matching: find.text('380 kcal')),
      findsOneWidget,
    );

    final coffeeRow = find.byKey(const ValueKey('food-row-m2'));
    await revealHittable(coffeeRow);
    expect(
      find.descendant(of: coffeeRow, matching: find.text('Kaffee')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: coffeeRow, matching: find.text('—')),
      findsOneWidget,
    );

    final lentilsRow = find.byKey(const ValueKey('food-row-m3'));
    await revealHittable(lentilsRow);
    expect(
      find.descendant(of: lentilsRow, matching: find.text('Linsensalat')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: lentilsRow, matching: find.text('240 kcal')),
      findsOneWidget,
    );
  }

  Finder waterCard() => find.byType(OpenBandWaterCard);

  Finder inWater(Finder matching) =>
      find.descendant(of: waterCard(), matching: matching);

  Finder waterSheet() => find.byKey(const ValueKey('journal-value-sheet'));

  Finder inWaterSheet(Finder matching) =>
      find.descendant(of: waterSheet(), matching: matching);

  Finder inPicker(Finder matching) => find.descendant(
    of: find.byType(OpenBandMealPickerSheet),
    matching: matching,
  );

  Finder inDraft(Finder matching) =>
      find.descendant(of: find.byType(OBMealDraftSheet), matching: matching);

  double keyboardInset() =>
      tester.view.viewInsets.bottom / tester.view.devicePixelRatio;

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

  Future<OpenBandController> mountParent({
    required _NutritionParentReviewRepo repository,
    Brightness brightness = Brightness.light,
    double scale = 1,
  }) async {
    final controller = OpenBandController(
      repository: repository,
      initialDay: day,
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
        home: OpenBandNutrition(controller: controller, revision: 0),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Future<void> mountGalleryNutrition({
    required _NutritionParentReviewRepo repository,
    Brightness brightness = Brightness.light,
    double? scale,
  }) async {
    repository.seedCaffeineSleepPattern('2026-09-15');
    await tester.pumpWidget(
      OpenBandGallery(
        key: UniqueKey(),
        repository: repository,
        showControls: false,
        initialBrightness: brightness,
        initialTextScale: scale,
      ),
    );
    await tester.pumpAndSettle();
    await h.press('Journal');
    await h.settleJournalHub(repository);
    await h.openHubNutrition();
    expect(find.byType(OpenBandNutrition), findsOneWidget);
  }

  void expectMinTapTarget(Finder target, {double size = 44}) {
    final box = tester.getRect(target.hitTestable());
    expect(box.width, greaterThanOrEqualTo(size));
    expect(box.height, greaterThanOrEqualTo(size));
  }

  Future<void> captureJournalCaffeine({
    required String name,
    Brightness brightness = Brightness.light,
    double? scale,
  }) async {
    final journalRepo = await h.mount(brightness: brightness, scale: scale);
    journalRepo.seedJournalEditor(
      metrics: {
        'caffeine_mg': const JournalMetricValue(200, atMinuteOfDay: 630),
      },
    );
    await h.press('Journal');
    await h.settleJournalHub(journalRepo);
    await h.openHubEditor();
    final caffeine = find.text('Koffein').last;
    await tester.ensureVisible(caffeine);
    await tester.tap(caffeine);
    await tester.pumpAndSettle();
    final sheet = find.byKey(const ValueKey('journal-value-sheet'));
    expect(sheet, findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.text('Koffein')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: sheet,
              matching: find.byKey(const ValueKey('journal-value')),
            ),
          )
          .controller!
          .text,
      '200',
    );
    expect(
      find.descendant(of: sheet, matching: find.text('10:30')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Menge')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Zuletzt')),
      findsOneWidget,
    );
    final amount = find.byKey(const ValueKey('journal-value-amount'));
    final time = find.byKey(const ValueKey('journal-value-time'));
    expect(amount, findsOneWidget);
    expect(time, findsOneWidget);
    final amountBox = tester.getRect(amount);
    final timeBox = tester.getRect(time);
    if ((scale ?? 1) <= 1) {
      expect((amountBox.center.dy - timeBox.center.dy).abs(), lessThan(8));
      expect(amountBox.right, lessThanOrEqualTo(timeBox.left + 1));
    } else {
      expect(timeBox.top + 0.5, greaterThanOrEqualTo(amountBox.bottom - 1));
    }
    expectMinTapTarget(
      find.descendant(of: sheet, matching: find.byTooltip('Schließen')),
    );
    expect(
      tester
          .getRect(
            find.descendant(
              of: sheet,
              matching: find.widgetWithText(FilledButton, 'Übernehmen'),
            ),
          )
          .height,
      greaterThanOrEqualTo(44),
    );
    await h.capture(name);
  }

  Future<void> tapTab(String label) async {
    final tab = find.descendant(
      of: find.byType(G2Segmented),
      matching: find.text(label),
    );
    expect(tab.hitTestable(), findsOneWidget);
    await tester.tap(tab.hitTestable());
    await tester.pumpAndSettle();
  }

  Future<_NutritionParentReviewRepo> freshRepo({
    bool water = true,
    double? waterMl = 1250,
    bool weekVariants = true,
    MealDraft? draft,
  }) async {
    final repository = await _loadNutritionParentReviewRepo();
    seedPaperDay(
      repository,
      water: water,
      waterMl: waterMl,
      weekVariants: weekVariants,
    );
    if (draft != null) {
      await repository.saveMealDraft(draft);
    }
    return repository;
  }

  Finder underlyingJournal() =>
      find.byType(OpenBandJournal, skipOffstage: false);

  Future<void> capturePendingDraftSaveError({
    required String name,
    Brightness brightness = Brightness.light,
    double scale = 1,
  }) async {
    final repository = await freshRepo();
    repository.failDraftWrite = true;
    final parent = await mountParent(
      repository: repository,
      brightness: brightness,
      scale: scale,
    );
    await tapTab('Lebensmittel');
    final coffee = find.byKey(const ValueKey('food-row-m2'));
    await revealHittable(coffee);
    await tester.tap(coffee.hitTestable());
    await tester.pumpAndSettle();
    expect(find.byType(OpenBandMealPickerSheet), findsOneWidget);
    await tester.tap(inPicker(find.text('Frühstück')).hitTestable());
    await tester.pumpAndSettle();
    expect(find.byType(OBMealDraftSheet), findsNothing);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('Speichern fehlgeschlagen'),
      ),
      findsOneWidget,
    );
    expect(
      find
          .descendant(of: find.byType(SnackBar), matching: find.text('Erneut'))
          .hitTestable(),
      findsOneWidget,
    );
    expect(await repository.readMealDraft(day, 'breakfast'), isNull);
    await h.capture(name);
    parent.dispose();
  }

  Future<void> openWaterSheet() async {
    await revealHittable(inWater(find.text('Wasser')));
    await tester.tap(inWater(find.text('Wasser')).hitTestable());
    await tester.pumpAndSettle();
    expect(waterSheet(), findsOneWidget);
    expect(inWaterSheet(find.text('Wasser')), findsOneWidget);
  }

  Future<void> captureDay({
    required String name,
    Brightness brightness = Brightness.light,
    double scale = 1,
    bool scrolled = false,
  }) async {
    final repository = await freshRepo();
    final controller = await mountParent(
      repository: repository,
      brightness: brightness,
      scale: scale,
    );
    expect(find.text('Ernährung'), findsOneWidget);
    expect(find.text('15. September'), findsOneWidget);
    expectFooterHittable();
    final origin = parentScrollPixels();
    await revealHittable(find.byType(OBMacroBars));
    expect(
      find.descendant(of: find.byType(OBMacroBars), matching: find.text('620')),
      findsOneWidget,
    );
    await revealHittable(inWater(find.text('1.250')));
    await expectPaperDayMeals(repository);
    if (scrolled) {
      final later = find.byTooltip('Zwischendurch ergänzen');
      await revealHittable(later);
      expect(find.text('Zwischendurch').hitTestable(), findsOneWidget);
      expectFooterHittable();
    } else {
      await restoreParentScroll(origin);
      expect(find.text('Ernährung'), findsOneWidget);
      expect(find.text('15. September'), findsOneWidget);
      expectFooterHittable();
    }
    await h.capture(name);
    controller.dispose();
  }

  await captureDay(name: 'nutrition-parent');
  await captureDay(name: 'nutrition-parent-dark', brightness: Brightness.dark);
  await captureDay(name: 'nutrition-parent-2x', scale: 2);
  await captureDay(
    name: 'nutrition-parent-2x-scrolled',
    scale: 2,
    scrolled: true,
  );
  await captureDay(
    name: 'nutrition-parent-2x-dark',
    brightness: Brightness.dark,
    scale: 2,
  );
  await captureDay(
    name: 'nutrition-parent-2x-scrolled-dark',
    brightness: Brightness.dark,
    scale: 2,
    scrolled: true,
  );

  var repository = await freshRepo(water: false);
  var controller = await mountParent(repository: repository);
  expect(inWater(find.text('—')), findsOneWidget);
  expect(inWater(find.text('1.250')), findsNothing);
  expect(inWater(find.text('0')), findsNothing);
  await h.capture('nutrition-parent-water-unknown');
  controller.dispose();

  repository = await freshRepo(waterMl: 0);
  controller = await mountParent(repository: repository);
  expect(inWater(find.text('0')), findsOneWidget);
  expect(inWater(find.text('—')), findsNothing);
  expect(inWater(find.text('1.250')), findsNothing);
  await h.capture('nutrition-parent-water-zero');
  controller.dispose();

  repository = await freshRepo();
  controller = await mountParent(repository: repository);
  await revealHittable(find.byKey(const ValueKey('water-plus')));
  await tester.tap(find.byKey(const ValueKey('water-plus')).hitTestable());
  await tester.pumpAndSettle();
  expect(inWater(find.text('1.500')), findsOneWidget);
  expect(repository.waterAdjusts, 1);
  expect(
    (await repository.readJournalDay(day)).metrics['water_ml']!.value,
    1500,
  );
  await h.capture('nutrition-parent-water-delta');
  controller.dispose();

  repository = await freshRepo();
  controller = await mountParent(repository: repository);
  repository.failJournalReadAfter = repository.journalReads;
  await revealHittable(find.byKey(const ValueKey('water-plus')));
  await tester.tap(find.byKey(const ValueKey('water-plus')).hitTestable());
  await tester.pumpAndSettle();
  expect(inWater(find.text('1.500')), findsOneWidget);
  expect(inWater(find.text('Laden fehlgeschlagen')), findsOneWidget);
  expect(inWater(find.text('Erneut versuchen')), findsOneWidget);
  expect(repository.waterAdjusts, 1);
  await h.capture('nutrition-parent-water-refresh-error');
  repository.failJournalReadAfter = null;
  await tester.tap(inWater(find.text('Erneut versuchen')).hitTestable());
  await tester.pumpAndSettle();
  expect(inWater(find.text('1.500')), findsOneWidget);
  expect(inWater(find.text('Laden fehlgeschlagen')), findsNothing);
  expect(repository.waterAdjusts, 1);
  await h.capture('nutrition-parent-water-refresh-retry');
  controller.dispose();

  repository = await freshRepo();
  controller = await mountParent(repository: repository);
  await openWaterSheet();
  expect(
    tester
        .widget<TextField>(
          inWaterSheet(find.byKey(const ValueKey('journal-value'))),
        )
        .controller!
        .text,
    '1250',
  );
  await h.capture('nutrition-parent-water-manual');
  await tester.tap(inWaterSheet(find.byTooltip('Schließen')).hitTestable());
  await tester.pumpAndSettle();
  expect(waterSheet(), findsNothing);
  controller.dispose();

  repository = await freshRepo();
  controller = await mountParent(
    repository: repository,
    brightness: Brightness.dark,
  );
  await openWaterSheet();
  await h.capture('nutrition-parent-water-manual-dark');
  await tester.tap(inWaterSheet(find.byTooltip('Schließen')).hitTestable());
  await tester.pumpAndSettle();
  expect(waterSheet(), findsNothing);
  controller.dispose();

  repository = await freshRepo();
  controller = await mountParent(repository: repository);
  await openWaterSheet();
  await tester.enterText(
    inWaterSheet(find.byKey(const ValueKey('journal-value'))),
    '1500',
  );
  await tester.pump();
  repository.failWaterWrite = true;
  await tester.tap(inWaterSheet(find.text('Speichern')).hitTestable());
  await tester.pumpAndSettle();
  expect(
    tester
        .widget<TextField>(
          inWaterSheet(find.byKey(const ValueKey('journal-value'))),
        )
        .controller!
        .text,
    '1500',
  );
  expect(inWaterSheet(find.text('Speichern fehlgeschlagen')), findsOneWidget);
  expect(inWaterSheet(find.text('Erneut versuchen')), findsOneWidget);
  expect(
    (await repository.readJournalDay(day)).metrics['water_ml']!.value,
    1250,
  );
  await h.capture('nutrition-parent-water-save-error');
  repository.failWaterWrite = false;
  await tester.tap(inWaterSheet(find.text('Erneut versuchen')).hitTestable());
  await tester.pumpAndSettle();
  expect(waterSheet(), findsNothing);
  expect(inWater(find.text('1.500')), findsOneWidget);
  expect(
    (await repository.readJournalDay(day)).metrics['water_ml']!.value,
    1500,
  );
  await h.capture('nutrition-parent-water-save-retry');
  controller.dispose();

  repository = await freshRepo();
  controller = await mountParent(repository: repository);
  await openWaterSheet();
  repository.conflictWaterWrite = true;
  await tester.tap(inWaterSheet(find.text('Speichern')).hitTestable());
  await tester.pumpAndSettle();
  expect(inWaterSheet(find.text('Eintrag wurde geändert')), findsOneWidget);
  expect(inWaterSheet(find.text('Neu laden')), findsOneWidget);
  expect(
    tester
        .widget<TextField>(
          inWaterSheet(find.byKey(const ValueKey('journal-value'))),
        )
        .controller!
        .text,
    '1250',
  );
  expect(
    (await repository.readJournalDay(day)).metrics['water_ml']!.value,
    1250,
  );
  await h.capture('nutrition-parent-water-conflict');
  repository.conflictWaterWrite = false;
  await tester.tap(inWaterSheet(find.byTooltip('Schließen')).hitTestable());
  await tester.pumpAndSettle();
  expect(waterSheet(), findsNothing);
  controller.dispose();

  repository = await freshRepo();
  controller = await mountParent(repository: repository, scale: 2);
  await openWaterSheet();
  await h.capture('nutrition-parent-water-2x');
  await settleKeyboard(
    inWaterSheet(find.byKey(const ValueKey('journal-value'))),
  );
  expect(
    tester
        .widget<TextField>(
          inWaterSheet(find.byKey(const ValueKey('journal-value'))),
        )
        .controller!
        .text,
    '1250',
  );
  await h.capture('nutrition-parent-water-2x-keyboard');
  controller.dispose();

  repository = await freshRepo();
  controller = await mountParent(repository: repository);
  await tapTab('Woche');
  expect(find.text('Erfasste Energie'), findsOneWidget);
  expect(
    find.descendant(
      of: find.byKey(const ValueKey('week-row-2026-09-11')),
      matching: find.text('Keine Einträge'),
    ),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: find.byKey(const ValueKey('week-row-2026-09-12')),
      matching: find.text('0'),
    ),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: find.byKey(const ValueKey('week-row-2026-09-13')),
      matching: find.text('1 Eintrag ohne kcal'),
    ),
    findsOneWidget,
  );
  await h.capture('nutrition-parent-week');
  controller.dispose();

  repository = await freshRepo();
  controller = await mountParent(
    repository: repository,
    brightness: Brightness.dark,
  );
  await tapTab('Woche');
  expect(find.text('Erfasste Energie'), findsOneWidget);
  await h.capture('nutrition-parent-week-dark');
  controller.dispose();

  repository = await freshRepo();
  repository.failWeekRead = true;
  controller = await mountParent(repository: repository);
  await tapTab('Woche');
  expect(find.text('Woche nicht geladen'), findsOneWidget);
  expect(find.text('Erneut'), findsOneWidget);
  await h.capture('nutrition-parent-week-error');
  repository.failWeekRead = false;
  await tester.tap(find.text('Erneut'));
  await tester.pumpAndSettle();
  expect(find.text('Erfasste Energie'), findsOneWidget);
  expect(find.text('Woche nicht geladen'), findsNothing);
  await h.capture('nutrition-parent-week-retry');
  controller.dispose();

  repository = await freshRepo();
  controller = await mountParent(repository: repository);
  await tapTab('Lebensmittel');
  expect(find.text('Zuletzt verwendet'), findsOneWidget);
  expect(find.byKey(const ValueKey('food-row-m1')), findsOneWidget);
  expect(find.byKey(const ValueKey('food-row-m2')), findsOneWidget);
  await h.capture('nutrition-parent-recents');
  controller.dispose();

  repository = await freshRepo();
  controller = await mountParent(
    repository: repository,
    brightness: Brightness.dark,
  );
  await tapTab('Lebensmittel');
  expect(find.text('Zuletzt verwendet'), findsOneWidget);
  await h.capture('nutrition-parent-recents-dark');
  controller.dispose();

  repository = await freshRepo();
  repository.failRecentRead = true;
  controller = await mountParent(repository: repository);
  await tapTab('Lebensmittel');
  expect(find.text('Einträge konnten nicht geladen werden.'), findsOneWidget);
  expect(find.text('Erneut'), findsOneWidget);
  await h.capture('nutrition-parent-recents-error');
  controller.dispose();

  repository = await freshRepo();
  controller = await mountParent(repository: repository);
  expectFooterHittable();
  await tester.tap(find.byKey(const ValueKey('nutrition-add')).hitTestable());
  await tester.pumpAndSettle();
  expect(find.byType(OpenBandMealPickerSheet), findsOneWidget);
  expect(inPicker(find.text('Mahlzeit wählen')), findsOneWidget);
  expect(inPicker(find.text('Frühstück')), findsOneWidget);
  await h.capture('nutrition-parent-picker');
  await tester.tap(inPicker(find.byTooltip('Schließen')).hitTestable());
  await tester.pumpAndSettle();
  expect(find.byType(OpenBandMealPickerSheet), findsNothing);
  controller.dispose();

  repository = await freshRepo();
  controller = await mountParent(
    repository: repository,
    brightness: Brightness.dark,
  );
  await tester.tap(find.byKey(const ValueKey('nutrition-add')).hitTestable());
  await tester.pumpAndSettle();
  expect(find.byType(OpenBandMealPickerSheet), findsOneWidget);
  expect(inPicker(find.text('Frühstück')), findsOneWidget);
  await h.capture('nutrition-parent-picker-dark');
  await tester.tap(inPicker(find.byTooltip('Schließen')).hitTestable());
  await tester.pumpAndSettle();
  expect(find.byType(OpenBandMealPickerSheet), findsNothing);
  controller.dispose();

  repository = await freshRepo(weekVariants: false);
  await repository.saveMealDraft(
    MealDraft(
      id: 'd-breakfast',
      day: day,
      meal: 'breakfast',
      entries: const [
        MealDraftEntry(
          id: 'e-oats',
          label: 'Haferflocken mit Milch',
          kcal: 380,
        ),
      ],
      updatedAt: DateTime(2026, 9, 15, 8),
    ),
  );
  controller = await mountParent(repository: repository);
  await tapTab('Lebensmittel');
  final coffee = find.byKey(const ValueKey('food-row-m2'));
  await revealHittable(coffee);
  await tester.tap(coffee.hitTestable());
  await tester.pumpAndSettle();
  expect(find.byType(OpenBandMealPickerSheet), findsOneWidget);
  await tester.tap(inPicker(find.text('Frühstück')).hitTestable());
  await tester.pumpAndSettle();
  expect(find.byType(OBMealDraftSheet), findsOneWidget);
  expect(inDraft(find.text('Haferflocken mit Milch')), findsOneWidget);
  expect(inDraft(find.text('Kaffee')), findsOneWidget);
  final retained = await repository.readMealDraft(day, 'breakfast');
  expect(retained, isNotNull);
  expect(retained!.id, 'd-breakfast');
  expect(retained.entries.map((e) => e.id), contains('e-oats'));
  final added = retained.entries.where((e) => e.id != 'e-oats').single;
  expect(added.id, isNot('m2'));
  expect(added.id, isNotEmpty);
  expect(added.label, 'Kaffee');
  expect(added.source, FoodSource.unknown);
  expect(added.sourceCode, 'unknown');
  expect(
    retained.entries.singleWhere((e) => e.id == 'e-oats').label,
    'Haferflocken mit Milch',
  );
  await h.capture('nutrition-parent-reuse-draft');
  await tester.tap(inDraft(find.text('Speichern')).hitTestable());
  await tester.pumpAndSettle();
  expect(find.byType(OBMealDraftSheet), findsNothing);
  await tapTab('Tag');
  expect(find.byKey(ValueKey('food-row-${added.id}')), findsOneWidget);
  final committed = await repository.readFoodEntry(added.id);
  expect(committed.saved, isTrue);
  expect(committed.current!.source, FoodSource.unknown);
  expect(committed.current!.id, added.id);
  await h.capture('nutrition-parent-reuse-committed');
  controller.dispose();

  await capturePendingDraftSaveError(name: 'nutrition-parent-draft-save-error');
  await capturePendingDraftSaveError(
    name: 'nutrition-parent-draft-save-error-dark',
    brightness: Brightness.dark,
  );
  await capturePendingDraftSaveError(
    name: 'nutrition-parent-draft-save-error-2x',
    scale: 2,
  );

  repository = await freshRepo();
  await mountGalleryNutrition(repository: repository);
  await tapTab('Woche');
  final historical = find.byKey(const ValueKey('week-row-2026-09-14'));
  await revealHittable(historical);
  await tester.tap(historical.hitTestable());
  await tester.pumpAndSettle();
  expect(
    tester.widget<OpenBandJournal>(underlyingJournal()).controller.selectedDay,
    '2026-09-14',
  );
  expect(
    find.descendant(
      of: find.byType(OpenBandNutrition),
      matching: find.text('14. September'),
    ),
    findsOneWidget,
  );
  final historicalOrigin = parentScrollPixels();
  final historicalLunch = find.byKey(const ValueKey('food-row-hist-14'));
  await revealHittable(historicalLunch);
  expect(
    find.descendant(of: historicalLunch, matching: find.text('Linsensalat')),
    findsOneWidget,
  );
  final historicalSaved = await repository.readFoodEntry('hist-14');
  expect(historicalSaved.current, isNotNull);
  expect(historicalSaved.current!.label, 'Linsensalat');
  expect(historicalSaved.current!.kcal, 240);
  await restoreParentScroll(historicalOrigin);
  final nutritionBack = find.descendant(
    of: find.byType(OpenBandNutrition),
    matching: find.byTooltip('Zurück'),
  );
  expectMinTapTarget(nutritionBack);
  await h.capture('nutrition-parent-historical');
  await tester.tap(nutritionBack.hitTestable());
  await tester.pumpAndSettle();
  expect(find.byType(OpenBandNutrition), findsNothing);
  expect(find.byType(OpenBandGallery), findsOneWidget);
  expect(find.byType(OpenBandJournal), findsOneWidget);
  expect(
    tester.widget<OpenBandJournal>(underlyingJournal()).controller.selectedDay,
    '2026-09-14',
  );
  final hub = find.byKey(const PageStorageKey('openband.journal'));
  final edit = find.descendant(
    of: hub,
    matching: find.byKey(const ValueKey('journal-edit')),
  );
  final hubScroll = find.descendant(of: hub, matching: find.byType(Scrollable));
  if (edit.hitTestable().evaluate().isEmpty) {
    if (edit.evaluate().isEmpty) {
      await tester.scrollUntilVisible(edit, -64, scrollable: hubScroll);
    } else {
      await Scrollable.ensureVisible(tester.element(edit), alignment: 0);
    }
    await tester.pumpAndSettle();
  }
  expect(edit.hitTestable(), findsOneWidget);
  expectMinTapTarget(edit);
  await h.capture('nutrition-parent-historical-return');

  await captureJournalCaffeine(name: 'nutrition-parent-journal-value');
  await captureJournalCaffeine(
    name: 'nutrition-parent-journal-value-dark',
    brightness: Brightness.dark,
  );
  await captureJournalCaffeine(
    name: 'nutrition-parent-journal-value-2x',
    scale: 2,
  );
  await captureJournalCaffeine(
    name: 'nutrition-parent-journal-value-2x-dark',
    brightness: Brightness.dark,
    scale: 2,
  );
}
