part of 'harness.dart';

Future<void> reviewExercisePicker(ReviewHarness h) async {
  final tester = h.tester;
  final bench = _pickerPreset('bench_press');
  final plank = _pickerPreset('plank');
  final labels = _pickerLabelsAlphabetical();
  expect(kExercisePresets, hasLength(18));
  expect(labels, [
    'Bankdrücken',
    'Beinpresse',
    'Kabelzug-Flys',
    'Klimmzug',
    'Unterarmstütz',
  ]);

  Future<_ExercisePickerReviewRepo> loadRepo() async {
    Future<Map> load(String name) => h.fixture(name);
    final repo = _ExercisePickerReviewRepo(
      await load('day-summary'),
      await load('sleep-detail'),
      activity: await load('additional-flows'),
      run: await load('run-detail'),
    );
    await repo.seedNutritionGoals();
    return repo;
  }

  Widget reviewHost({
    required Widget home,
    Brightness brightness = Brightness.light,
    double scale = 1,
  }) => MaterialApp(
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
    home: home,
  );

  Finder downScrollable(Finder ancestor) => find.descendant(
    of: ancestor,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    ),
  );

  Rect reviewSafeViewport({Finder? contentOf}) {
    final view = tester.view;
    final dpr = view.devicePixelRatio;
    final size = view.physicalSize / dpr;
    final pad = view.viewPadding;
    final screen = Rect.fromLTRB(
      pad.left / dpr,
      pad.top / dpr,
      size.width - pad.right / dpr,
      size.height - pad.bottom / dpr,
    );
    if (contentOf == null) return screen;
    final box = tester.getRect(downScrollable(contentOf).first);
    return Rect.fromLTRB(
      box.left < screen.left ? screen.left : box.left,
      box.top < screen.top ? screen.top : box.top,
      box.right > screen.right ? screen.right : box.right,
      box.bottom > screen.bottom ? screen.bottom : box.bottom,
    );
  }

  bool rectInSafeViewport(Rect box, {Finder? contentOf, double slop = 0.5}) {
    final safe = reviewSafeViewport(contentOf: contentOf);
    return box.top >= safe.top - slop &&
        box.bottom <= safe.bottom + slop &&
        box.left >= safe.left - slop &&
        box.right <= safe.right + slop;
  }

  Future<void> expectInSafeViewport(Finder target, {Finder? contentOf}) async {
    expect(target, findsWidgets);
    expect(
      rectInSafeViewport(tester.getRect(target), contentOf: contentOf),
      isTrue,
    );
  }

  Future<void> restoreScroll(Finder ancestor, double offset) async {
    final position = tester
        .state<ScrollableState>(downScrollable(ancestor).first)
        .position;
    position.jumpTo(
      offset.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
    await tester.pump();
  }

  Future<void> revealIn(Finder ancestor, Finder target) async {
    final scrollable = downScrollable(ancestor).first;
    var scrolls = 0;
    var searchUp = true;
    while (target.evaluate().isEmpty ||
        target.hitTestable().evaluate().isEmpty) {
      if (scrolls >= 32) {
        throw FlutterError(
          'Control is not hit-testable after production scrolling.',
        );
      }
      if (target.evaluate().isEmpty) {
        final position = tester.state<ScrollableState>(scrollable).position;
        final atMin = position.pixels <= position.minScrollExtent + 0.5;
        final atMax = position.pixels >= position.maxScrollExtent - 0.5;
        if (searchUp && atMin) searchUp = false;
        final dy = searchUp ? (atMin ? 0.0 : 64.0) : (atMax ? 0.0 : -64.0);
        if (dy == 0) {
          throw FlutterError(
            'Control is not hit-testable after production scrolling.',
          );
        }
        await tester.drag(scrollable, Offset(0, dy));
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

  Future<void> ensureFullyInSafeViewport(
    Finder ancestor,
    Finder target, {
    bool content = true,
  }) async {
    await revealIn(ancestor, target);
    final scrollable = downScrollable(ancestor).first;
    final contentOf = content ? ancestor : null;
    var extra = 0;

    String diagnostics() {
      final box = tester.getRect(target);
      final safe = reviewSafeViewport(contentOf: contentOf);
      final position = tester.state<ScrollableState>(scrollable).position;
      return 'target=$box safe=$safe '
          'overflowTop=${safe.top - box.top} '
          'overflowBottom=${box.bottom - safe.bottom} '
          'overflowLeft=${safe.left - box.left} '
          'overflowRight=${box.right - safe.right} '
          'scroll=${position.pixels} '
          'extent=${position.minScrollExtent}..${position.maxScrollExtent} '
          'viewport=${position.viewportDimension} extra=$extra';
    }

    while (!rectInSafeViewport(tester.getRect(target), contentOf: contentOf)) {
      if (extra >= 32) {
        throw FlutterError(
          'Control is not fully within the safe viewport.\n${diagnostics()}',
        );
      }
      final box = tester.getRect(target);
      final safe = reviewSafeViewport(contentOf: contentOf);
      final overflowBottom = box.bottom - safe.bottom;
      final overflowTop = safe.top - box.top;
      if (extra == 0) {
        await Scrollable.ensureVisible(
          tester.element(target),
          alignment: overflowBottom >= overflowTop ? 1.0 : 0.0,
        );
        await tester.pump();
      } else {
        const minGesture = 64.0;
        final needed = overflowBottom > 0
            ? -(overflowBottom + 8)
            : overflowTop + 8;
        final dy = needed < 0
            ? (needed > -minGesture ? -minGesture : needed)
            : (needed < minGesture ? minGesture : needed);
        await tester.drag(scrollable, Offset(0, dy));
        await tester.pump();
      }
      extra++;
    }
    expect(
      rectInSafeViewport(tester.getRect(target), contentOf: contentOf),
      isTrue,
    );
    expect(target.hitTestable(), findsOneWidget);
  }

  Future<void> pumpUntil(bool Function() ready, String message) async {
    await tester.pump();
    var frames = 0;
    while (!ready()) {
      if (++frames > 80) {
        throw FlutterError(message);
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
    await reviewPumpPageTransitions(tester);
  }

  Future<void> pumpSheet() async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> mountEditor({
    required _ExercisePickerReviewRepo repository,
    WorkoutTemplate? template,
    Brightness brightness = Brightness.light,
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      reviewHost(
        brightness: brightness,
        scale: scale,
        home: OpenBandTemplateEditor(
          repository: repository,
          template: template,
        ),
      ),
    );
    await pumpUntil(
      () => find.byType(OpenBandTemplateEditor).evaluate().isNotEmpty,
      'Template editor did not finish loading.',
    );
  }

  Future<WorkoutTemplate> fixtureA(_ExercisePickerReviewRepo repository) async {
    final templates = await repository.readTemplates();
    return templates.firstWhere((t) => t.id == 'tpl-ganzkoerper-a');
  }

  List<String> sessionStamp(List<TrainingSession> sessions) => [
    for (final s in sessions)
      '${s.id}|${s.durationMin}|${s.start.millisecondsSinceEpoch}',
  ];

  Map<String, String> templateStamp(List<WorkoutTemplate> templates) => {
    for (final t in templates) t.id: jsonEncode(t.toJson()),
  };

  Future<void> expectFixturesUnchanged(
    _ExercisePickerReviewRepo repository, {
    required Map<String, String> templates,
    required List<String> sessions,
  }) async {
    expect(repository.templateSaves, 0);
    final a = await fixtureA(repository);
    expect(a.exercises, hasLength(4));
    expect(a.workSets, 12);
    expect(templateStamp(await repository.readTemplates()), templates);
    expect(
      sessionStamp(await repository.readSessions('2026-09-15', 14)),
      sessions,
    );
  }

  Finder plusOf(String id) => find.byKey(ValueKey('exercise-select-$id'));

  Finder openOf(String id) => find.byKey(ValueKey('exercise-open-$id'));

  Finder inPicker(Finder matching) => find.descendant(
    of: find.byType(OpenBandExercisePicker),
    matching: matching,
  );

  bool pickerCatalogueReady() {
    if (find.byType(OpenBandExercisePicker).evaluate().isEmpty) {
      return false;
    }
    if (find.text('Bibliothek nicht geladen').evaluate().isNotEmpty) {
      return true;
    }
    if (find.text('Keine Übungen').evaluate().isNotEmpty) {
      return true;
    }
    return find.text('5 Übungen').evaluate().isNotEmpty ||
        find.text('6 Übungen').evaluate().isNotEmpty ||
        find.text('0 Übungen').evaluate().isNotEmpty ||
        find.textContaining('nicht lesbar').evaluate().isNotEmpty;
  }

  Future<void> pumpPickerReady() async {
    await pumpUntil(
      pickerCatalogueReady,
      'Exercise picker did not finish loading.',
    );
  }

  Future<void> openAddSheet() async {
    final editor = find.byType(OpenBandTemplateEditor);
    final add = find.widgetWithText(OBAction, 'Übung hinzufügen');
    await ensureFullyInSafeViewport(editor, add);
    await tester.tap(add.hitTestable());
    await pumpSheet();
    expect(find.text('Bibliothek'), findsOneWidget);
    expect(find.bySemanticsLabel('Eigene Übung'), findsOneWidget);
    expect(find.text('Eigene Zeitübung'), findsOneWidget);
  }

  Future<void> openPicker() async {
    await openAddSheet();
    await tester.tap(find.text('Bibliothek'));
    await pumpPickerReady();
  }

  Future<void> popRoute() async {
    await tester.tap(find.byTooltip('Zurück'));
    await reviewPumpPageTransitions(tester);
    await tester.pump();
  }

  Finder addSelectedAction() =>
      find.widgetWithText(OBAction, '2 Übungen hinzufügen');

  Finder saveAction() => find.widgetWithText(OBAction, 'Vorlage speichern');

  Future<void> pumpInk() async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> selectBenchAndPlank() async {
    final picker = find.byType(OpenBandExercisePicker);
    final benchSelect = plusOf(bench.id);
    final plankSelect = plusOf(plank.id);
    await ensureFullyInSafeViewport(picker, benchSelect);
    await tester.tap(benchSelect.hitTestable());
    await tester.pump();
    await ensureFullyInSafeViewport(picker, plankSelect);
    await tester.tap(plankSelect.hitTestable());
    await pumpInk();
    expect(addSelectedAction(), findsOneWidget);
    await restoreScroll(picker, 0);
  }

  Future<void> tapFilterChip(Key key) async {
    final chip = find.byKey(key);
    final page = find.ancestor(
      of: find.bySemanticsLabel('Filter'),
      matching: find.byType(Scaffold),
    );
    await ensureFullyInSafeViewport(page, chip);
    await tester.tap(chip.hitTestable());
    await pumpInk();
  }

  Future<void> openFilterPage() async {
    final picker = find.byType(OpenBandExercisePicker);
    final trigger = find.byKey(const ValueKey('exercise-filter-muscles'));
    await ensureFullyInSafeViewport(picker, trigger);
    await tester.tap(trigger.hitTestable());
    await reviewPumpPageTransitions(tester);
    await tester.pump();
    expect(find.bySemanticsLabel('Filter'), findsOneWidget);
  }

  Future<void> selectChestAndBarbell() async {
    await tapFilterChip(const ValueKey('filter-muscle-chest'));
    await tapFilterChip(const ValueKey('filter-equipment-barbell'));
  }

  Future<void> applyFilter() async {
    final apply = find.widgetWithText(OBAction, 'Filter anwenden');
    await expectInSafeViewport(apply);
    await tester.tap(apply.hitTestable());
    await reviewPumpPageTransitions(tester);
    await tester.pump();
  }

  void expectBankOnlyWithHiddenSelection() {
    expect(plusOf(bench.id), findsOneWidget);
    expect(plusOf(plank.id), findsNothing);
    expect(plusOf('cable_fly'), findsNothing);
    expect(plusOf('leg_press'), findsNothing);
    expect(plusOf('pull_up'), findsNothing);
    expect(inPicker(find.text(bench.labelDe)), findsOneWidget);
    expect(inPicker(find.text(plank.labelDe)), findsNothing);
    expect(inPicker(find.text('Kabelzug-Flys')), findsNothing);
    expect(
      inPicker(find.text('1 Übung · 1 Auswahl außerhalb')),
      findsOneWidget,
    );
    expect(addSelectedAction(), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('exercise-filter-muscles')),
        matching: find.text('Brust'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('exercise-filter-equipment')),
        matching: find.text('Langhantel'),
      ),
      findsOneWidget,
    );
  }

  double keyboardInset() =>
      tester.view.viewInsets.bottom / tester.view.devicePixelRatio;

  Future<void> waitKeyboardInset({required bool open}) async {
    var last = keyboardInset();
    var stable = 0;
    var pumped = 0;
    while (pumped < 60) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 16)),
      );
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
    expect(keyboardInset(), 0);
  }

  Future<void> enterFocused(Finder field, String text) async {
    await settleKeyboard(field);
    await tester.enterText(field, text);
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, text);
  }

  Future<void> nameDraft(String name) async {
    await tester.enterText(find.byType(TextField).first, name);
    await tester.pump();
    await dismissKeyboard();
  }

  Future<void> expectUnknownDetail() async {
    expect(find.text(_kUnknownImportedExerciseLabel), findsWidgets);
    expect(find.text('Nicht festgelegt'), findsOneWidget);
    expect(find.text('Importiert'), findsNothing);
    expect(find.text('Gespeichert'), findsNothing);
    expect(find.text('Maschine'), findsOneWidget);
    expect(find.text('Erfassung'), findsOneWidget);
    expect(
      tester
          .widget<OBAction>(find.widgetWithText(OBAction, 'Auswählen'))
          .onPressed,
      isNull,
    );
  }

  void expectVisibleLabels(Iterable<String> expected) {
    for (final label in expected) {
      expect(inPicker(find.text(label)), findsOneWidget);
    }
  }

  void expectAlphabeticalVisible() {
    expectVisibleLabels(labels);
    final tops = [
      for (final label in labels)
        tester.getRect(inPicker(find.text(label))).top,
    ];
    for (var i = 1; i < tops.length; i++) {
      expect(tops[i], greaterThan(tops[i - 1]));
    }
  }

  Finder exerciseCard(String label) => find
      .ancestor(
        of: find.byWidgetPredicate(
          (widget) => widget is TextField && widget.controller?.text == label,
        ),
        matching: find.byType(OBCard),
      )
      .first;

  void expectEmptyDraft(String label, {required bool timed}) {
    final card = exerciseCard(label);
    final fields = find.descendant(of: card, matching: find.byType(TextField));
    final texts = [
      for (final element in fields.evaluate())
        (element.widget as TextField).controller!.text,
    ];
    expect(texts.first, label);
    expect(texts, hasLength(timed ? 2 : 3));
    expect(texts.skip(1), everyElement(isEmpty));
    expect(
      find.descendant(of: card, matching: find.text('Sek.')),
      timed ? findsWidgets : findsNothing,
    );
    expect(
      find.descendant(of: card, matching: find.text('Wdh.')),
      timed ? findsNothing : findsWidgets,
    );
  }

  Future<void> confirmSelectedIntoDraft() async {
    final add = addSelectedAction();
    await expectInSafeViewport(add);
    await tester.tap(add.hitTestable());
    await reviewPumpPageTransitions(tester);
    await tester.pump();
    expect(find.byType(OpenBandExercisePicker), findsNothing);
    expect(find.byType(OpenBandTemplateEditor), findsOneWidget);
    expectEmptyDraft(bench.labelDe, timed: false);
    expectEmptyDraft(plank.labelDe, timed: true);
  }

  Future<void> addBenchAndPlankToDraft({
    required _ExercisePickerReviewRepo repository,
    Brightness brightness = Brightness.light,
    double scale = 1,
    String name = '',
  }) async {
    await mountEditor(
      repository: repository,
      brightness: brightness,
      scale: scale,
    );
    await openPicker();
    await selectBenchAndPlank();
    await confirmSelectedIntoDraft();
    if (name.isNotEmpty) {
      await nameDraft(name);
    }
  }

  final repository = await loadRepo();
  final originalTemplates = templateStamp(await repository.readTemplates());
  final originalSessions = sessionStamp(
    await repository.readSessions('2026-09-15', 14),
  );
  final originalA = await fixtureA(repository);
  expect(originalA.exercises, hasLength(4));
  expect(originalA.workSets, 12);
  expect(assembleExerciseCatalogue(const []).entries, hasLength(18));

  await mountEditor(repository: repository);
  await openAddSheet();
  await h.capture('exercise-picker-add-sheet');
  await tester.tap(find.text('Bibliothek'));
  await pumpPickerReady();
  expect(inPicker(find.text('5 Übungen')), findsOneWidget);
  expectAlphabeticalVisible();
  await selectBenchAndPlank();
  expect(inPicker(find.text(bench.labelDe)), findsOneWidget);
  expect(inPicker(find.text(plank.labelDe)), findsOneWidget);
  await h.capture('exercise-picker');

  await openFilterPage();
  await selectChestAndBarbell();
  expect(find.bySemanticsLabel('Filter'), findsOneWidget);
  await h.capture('exercise-picker-filter');
  await applyFilter();
  expectBankOnlyWithHiddenSelection();
  await h.capture('exercise-picker-filtered');

  await openFilterPage();
  await tapFilterChip(const ValueKey('filter-muscle-legs'));
  await popRoute();
  expectBankOnlyWithHiddenSelection();

  await tester.tap(openOf(bench.id));
  await reviewPumpPageTransitions(tester);
  await tester.pump();
  expect(find.bySemanticsLabel('Übung'), findsOneWidget);
  expect(find.text(bench.labelDe), findsWidgets);
  expect(find.text('Gerät'), findsOneWidget);
  expect(
    find.descendant(
      of: find.ancestor(
        of: find.text('Gerät'),
        matching: find.byType(Scaffold),
      ),
      matching: find.text('Langhantel'),
    ),
    findsOneWidget,
  );
  expect(find.text('Wiederholungen'), findsOneWidget);
  expect(find.text('OpenBand'), findsOneWidget);
  await h.capture('exercise-picker-detail');
  await popRoute();
  expect(find.byType(OpenBandExercisePicker), findsOneWidget);
  expect(inPicker(find.text(bench.labelDe)), findsOneWidget);
  expect(find.text('2 Übungen hinzufügen'), findsOneWidget);

  await openFilterPage();
  await tester.tap(find.text('Zurücksetzen'));
  await tester.pump();
  await applyFilter();
  expectAlphabeticalVisible();
  expect(addSelectedAction(), findsOneWidget);
  await confirmSelectedIntoDraft();
  await expectFixturesUnchanged(
    repository,
    templates: originalTemplates,
    sessions: originalSessions,
  );
  await nameDraft('Kurztraining');
  expect(tester.widget<OBAction>(saveAction()).onPressed, isNotNull);
  await h.capture('exercise-picker-draft');

  await tester.tap(saveAction());
  await reviewPumpPageTransitions(tester);
  await tester.pump();
  expect(repository.templateSaves, 1);
  final saved = (await repository.readTemplates()).firstWhere(
    (t) => t.name == 'Kurztraining',
  );
  expect(saved.exercises, hasLength(2));
  final savedPlank = saved.exercises.firstWhere(
    (e) => e.exerciseKey == plank.id,
  );
  expect(savedPlank.sets, hasLength(1));
  expect(savedPlank.sets.single.mode, PlannedSetMode.time);
  expect(savedPlank.sets.single.seconds, isNull);
  expect(savedPlank.sets.single.reps, isNull);
  expect(savedPlank.sets.single.loadKg, isNull);
  expect((await fixtureA(repository)).exercises, hasLength(4));
  expect(
    sessionStamp(await repository.readSessions('2026-09-15', 14)),
    originalSessions,
  );
  await mountEditor(repository: repository, template: saved);
  expectEmptyDraft(plank.labelDe, timed: true);
  await h.capture('exercise-picker-reopen');

  final inPlanRepo = await loadRepo();
  await mountEditor(
    repository: inPlanRepo,
    template: await fixtureA(inPlanRepo),
  );
  await openPicker();
  expect(inPicker(find.textContaining('Im Plan')), findsWidgets);
  await tester.tap(plusOf(bench.id));
  await pumpSheet();
  expect(find.text('Übung erneut hinzufügen?'), findsOneWidget);
  expect(find.byKey(const ValueKey('ob-confirm-no')), findsOneWidget);
  expect(find.byKey(const ValueKey('ob-confirm-yes')), findsOneWidget);
  await h.capture('exercise-picker-in-plan');
  await tester.tap(find.byKey(const ValueKey('ob-confirm-no')));
  await pumpSheet();
  expect(find.text('Übung erneut hinzufügen?'), findsNothing);
  expect(find.text('2 Übungen hinzufügen'), findsNothing);
  await tester.tap(plusOf(bench.id));
  await pumpSheet();
  await tester.tap(find.byKey(const ValueKey('ob-confirm-yes')));
  await pumpSheet();
  expect(find.text('1 Übung hinzufügen'), findsOneWidget);

  final unknownRepo = await loadRepo();
  unknownRepo.includeUnknownMode = true;
  await mountEditor(repository: unknownRepo);
  await openPicker();
  expect(inPicker(find.text(_kUnknownImportedExerciseLabel)), findsOneWidget);
  expect(
    tester.widget<IconButton>(plusOf(_kUnknownImportedExerciseId)).onPressed,
    isNull,
  );
  await tester.tap(openOf(_kUnknownImportedExerciseId));
  await reviewPumpPageTransitions(tester);
  await tester.pump();
  await expectUnknownDetail();
  await h.capture('exercise-picker-unknown');

  final unknownDarkRepo = await loadRepo();
  unknownDarkRepo.includeUnknownMode = true;
  await mountEditor(repository: unknownDarkRepo, brightness: Brightness.dark);
  await openPicker();
  expect(inPicker(find.text(_kUnknownImportedExerciseLabel)), findsOneWidget);
  expect(
    tester.widget<IconButton>(plusOf(_kUnknownImportedExerciseId)).onPressed,
    isNull,
  );
  await tester.tap(openOf(_kUnknownImportedExerciseId));
  await reviewPumpPageTransitions(tester);
  await tester.pump();
  await expectUnknownDetail();
  await h.capture('exercise-picker-unknown-dark');

  final emptyRepo = await loadRepo();
  await mountEditor(repository: emptyRepo);
  await openPicker();
  await tester.enterText(
    find.byKey(const ValueKey('exercise-search')),
    'Ausfallschritte',
  );
  await tester.pump();
  await dismissKeyboard();
  expect(find.text('Keine Übungen gefunden'), findsOneWidget);
  expect(find.text('0 Übungen'), findsOneWidget);
  await h.capture('exercise-picker-empty');
  await tester.tap(find.widgetWithText(OBAction, 'Suche löschen'));
  await tester.pump();
  expectAlphabeticalVisible();
  expect(find.text('Keine Übungen gefunden'), findsNothing);

  final errorRepo = await loadRepo();
  errorRepo.failCatalogueRead = true;
  await mountEditor(repository: errorRepo);
  await openPicker();
  expect(find.text('Bibliothek nicht geladen'), findsOneWidget);
  expect(find.text('Keine Übungen gefunden'), findsNothing);
  await h.capture('exercise-picker-error');
  errorRepo.failCatalogueRead = false;
  await tester.tap(find.widgetWithText(OBAction, 'Erneut laden'));
  await pumpPickerReady();
  expect(find.text('Bibliothek nicht geladen'), findsNothing);
  expectAlphabeticalVisible();
  await h.capture('exercise-picker-error-retry');

  final errorDarkRepo = await loadRepo();
  errorDarkRepo.failCatalogueRead = true;
  await mountEditor(repository: errorDarkRepo, brightness: Brightness.dark);
  await openPicker();
  expect(find.text('Bibliothek nicht geladen'), findsOneWidget);
  await h.capture('exercise-picker-error-dark');

  final partialRepo = await loadRepo();
  partialRepo.unreadableCount = 2;
  await mountEditor(repository: partialRepo);
  await openPicker();
  expect(find.text('5 Übungen · 2 nicht lesbar'), findsOneWidget);
  expectAlphabeticalVisible();
  await h.capture('exercise-picker-partial');

  final darkRepo = await loadRepo();
  await mountEditor(repository: darkRepo, brightness: Brightness.dark);
  await openPicker();
  await selectBenchAndPlank();
  await h.capture('exercise-picker-dark');
  await tester.tap(openOf(bench.id));
  await reviewPumpPageTransitions(tester);
  await tester.pump();
  await h.capture('exercise-picker-detail-dark');
  await popRoute();
  await openFilterPage();
  await selectChestAndBarbell();
  await h.capture('exercise-picker-filter-dark');

  Future<void> captureScaled({
    required String name,
    required Brightness brightness,
    required bool scrolled,
  }) async {
    final scaled = await loadRepo();
    await mountEditor(repository: scaled, brightness: brightness, scale: 2);
    await openPicker();
    await selectBenchAndPlank();
    final picker = find.byType(OpenBandExercisePicker);
    await expectInSafeViewport(inPicker(find.bySemanticsLabel('Übungen')));
    await expectInSafeViewport(
      find.byKey(const ValueKey('exercise-search')),
      contentOf: picker,
    );
    await expectInSafeViewport(
      find.byKey(const ValueKey('exercise-filter-muscles')),
      contentOf: picker,
    );
    await expectInSafeViewport(
      inPicker(find.text(bench.labelDe)),
      contentOf: picker,
    );
    if (scrolled) {
      final footer = find.widgetWithText(OBAction, '2 Übungen hinzufügen');
      final last = openOf(plank.id);
      await ensureFullyInSafeViewport(picker, last);
      await expectInSafeViewport(footer);
      expect(rectInSafeViewport(tester.getRect(footer)), isTrue);
      expect(
        rectInSafeViewport(tester.getRect(last), contentOf: picker),
        isTrue,
      );
      await h.capture(name);
      await tester.tap(footer.hitTestable());
      await reviewPumpPageTransitions(tester);
      await tester.pump();
      expect(find.byType(OpenBandExercisePicker), findsNothing);
      expectEmptyDraft(bench.labelDe, timed: false);
      expectEmptyDraft(plank.labelDe, timed: true);
    } else {
      await h.capture(name);
    }
  }

  await captureScaled(
    name: 'exercise-picker-2x',
    brightness: Brightness.light,
    scrolled: false,
  );
  await captureScaled(
    name: 'exercise-picker-2x-scrolled',
    brightness: Brightness.light,
    scrolled: true,
  );
  await captureScaled(
    name: 'exercise-picker-2x-dark',
    brightness: Brightness.dark,
    scrolled: false,
  );

  Future<void> captureParentScaled({
    required String name,
    required Brightness brightness,
    required bool scrolled,
  }) async {
    final scaled = await loadRepo();
    await addBenchAndPlankToDraft(
      repository: scaled,
      brightness: brightness,
      scale: 2,
      name: 'Kurztraining',
    );
    final editor = find.byType(OpenBandTemplateEditor);
    final save = saveAction();
    expect(tester.widget<OBAction>(save).onPressed, isNotNull);
    await expectInSafeViewport(find.bySemanticsLabel('Neue Vorlage'));
    await expectInSafeViewport(save);
    if (scrolled) {
      final add = find.widgetWithText(OBAction, 'Übung hinzufügen');
      await ensureFullyInSafeViewport(editor, add);
      await expectInSafeViewport(save);
      expect(rectInSafeViewport(tester.getRect(save)), isTrue);
      expect(
        rectInSafeViewport(tester.getRect(add), contentOf: editor),
        isTrue,
      );
      await tester.tap(add.hitTestable());
      await pumpSheet();
      expect(find.text('Bibliothek'), findsOneWidget);
      expect(find.bySemanticsLabel('Eigene Übung'), findsOneWidget);
      expect(find.text('Eigene Zeitübung'), findsOneWidget);
      Navigator.of(tester.element(find.text('Bibliothek'))).pop();
      await pumpSheet();
      expect(find.text('Bibliothek'), findsNothing);
      expect(find.bySemanticsLabel('Eigene Übung'), findsNothing);
      expect(find.text('Eigene Zeitübung'), findsNothing);
      await ensureFullyInSafeViewport(editor, add);
      await expectInSafeViewport(save);
      expect(rectInSafeViewport(tester.getRect(save)), isTrue);
      expect(
        rectInSafeViewport(tester.getRect(add), contentOf: editor),
        isTrue,
      );
      await h.capture(name);
      await tester.tap(save.hitTestable());
      await reviewPumpPageTransitions(tester);
      await tester.pump();
      expect(scaled.templateSaves, 1);
      final savedAtScale = (await scaled.readTemplates()).firstWhere(
        (t) => t.name == 'Kurztraining',
      );
      expect(savedAtScale.exercises, hasLength(2));
      expect(
        savedAtScale.exercises
            .firstWhere((e) => e.exerciseKey == plank.id)
            .sets
            .single
            .mode,
        PlannedSetMode.time,
      );
    } else {
      await h.capture(name);
    }
  }

  final draftDark = await loadRepo();
  await addBenchAndPlankToDraft(
    repository: draftDark,
    brightness: Brightness.dark,
    name: 'Kurztraining',
  );
  expect(find.bySemanticsLabel('Neue Vorlage'), findsOneWidget);
  expect(tester.widget<OBAction>(saveAction()).onPressed, isNotNull);
  await h.capture('exercise-picker-draft-dark');

  await captureParentScaled(
    name: 'exercise-picker-draft-2x',
    brightness: Brightness.light,
    scrolled: false,
  );
  await captureParentScaled(
    name: 'exercise-picker-draft-2x-scrolled',
    brightness: Brightness.light,
    scrolled: true,
  );

  Finder hintedField(String hint) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.hintText == hint,
  );

  WorkoutTemplate legacyHoldTemplate() => WorkoutTemplate(
    id: 'legacy-hold',
    name: 'Altbestand',
    version: 1,
    exercises: [
      PlannedExercise(
        id: 'ex-legacy-hold',
        exerciseKey: 'legacy-hold',
        name: 'Halten',
        sets: const [
          PlannedSet(
            id: 'set-legacy-hold',
            reps: 8,
            seconds: 40,
            loadKg: 62.55,
          ),
        ],
      ),
    ],
    updatedAt: DateTime(2026, 9, 1),
  );

  void expectLegacyHoldUnchanged(WorkoutTemplate template) {
    expect(template.id, 'legacy-hold');
    expect(template.name, 'Altbestand');
    expect(template.exercises, hasLength(1));
    final exercise = template.exercises.single;
    expect(exercise.exerciseKey, 'legacy-hold');
    expect(exercise.name, 'Halten');
    expect(exercise.sets, hasLength(1));
    final set = exercise.sets.single;
    expect(set.reps, 8);
    expect(set.seconds, 40);
    expect(set.loadKg, 62.55);
    expect(set.mode, isNull);
  }

  Future<void> captureLegacyHold({
    required String name,
    required Brightness brightness,
    required bool refillAndSave,
  }) async {
    final repo = await loadRepo();
    final original = await repo.saveTemplate(legacyHoldTemplate());
    expectLegacyHoldUnchanged(original);
    final stamp = jsonEncode(original.toJson());
    final savesAfterSeed = repo.templateSaves;
    await mountEditor(
      repository: repo,
      template: original,
      brightness: brightness,
    );
    expect(find.bySemanticsLabel('Vorlage bearbeiten'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Altbestand'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Halten'), findsOneWidget);
    final sek = hintedField('Sek.');
    expect(sek, findsOneWidget);
    expect(tester.widget<TextField>(sek).controller!.text, '40');
    await enterFocused(sek, '');
    await dismissKeyboard();
    expect(find.text('Dauer fehlt.'), findsOneWidget);
    expect(tester.widget<OBAction>(saveAction()).onPressed, isNull);
    expect(repo.templateSaves, savesAfterSeed);
    final held = (await repo.readTemplates()).firstWhere(
      (t) => t.id == 'legacy-hold',
    );
    expect(jsonEncode(held.toJson()), stamp);
    expectLegacyHoldUnchanged(held);
    await h.capture(name);
    if (!refillAndSave) return;
    await enterFocused(sek, '40');
    await dismissKeyboard();
    expect(find.text('Dauer fehlt.'), findsNothing);
    expect(tester.widget<OBAction>(saveAction()).onPressed, isNotNull);
    await tester.tap(saveAction().hitTestable());
    await reviewPumpPageTransitions(tester);
    await tester.pump();
    expect(repo.templateSaves, savesAfterSeed + 1);
    final saved = (await repo.readTemplates()).firstWhere(
      (t) => t.id == 'legacy-hold',
    );
    expectLegacyHoldUnchanged(saved);
    await mountEditor(repository: repo, template: saved);
    expect(
      tester.widget<TextField>(hintedField('Sek.')).controller!.text,
      '40',
    );
    expect(hintedField('Wdh.'), findsNothing);
    expectLegacyHoldUnchanged(
      (await repo.readTemplates()).firstWhere((t) => t.id == 'legacy-hold'),
    );
  }

  await captureLegacyHold(
    name: 'exercise-picker-legacy-hold',
    brightness: Brightness.light,
    refillAndSave: true,
  );
  await captureLegacyHold(
    name: 'exercise-picker-legacy-hold-dark',
    brightness: Brightness.dark,
    refillAndSave: false,
  );
}
