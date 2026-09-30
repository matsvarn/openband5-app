part of 'harness.dart';

Future<void> reviewCustomExercise(ReviewHarness h) async {
  final tester = h.tester;
  Future<_CustomExerciseReviewRepo> loadRepo() async {
    Future<Map> load(String name) async =>
        jsonDecode(
              await rootBundle.loadString(
                'docs/openband5/assets/fixtures/$name.json',
              ),
            )
            as Map;
    final repo = _CustomExerciseReviewRepo(
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
        if (searchUp && atMin) {
          searchUp = false;
        }
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
    while (!rectInSafeViewport(tester.getRect(target), contentOf: contentOf)) {
      if (extra >= 32) {
        throw FlutterError('Control is not fully within the safe viewport.');
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
    var waited = 0;
    while (!ready()) {
      if (++waited > 80) {
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

  Future<void> pumpInk() async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> mountEditor({
    required _CustomExerciseReviewRepo repository,
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

  Map<String, String> templateStamp(List<WorkoutTemplate> templates) => {
    for (final t in templates) t.id: jsonEncode(t.toJson()),
  };

  Finder inPicker(Finder matching) => find.descendant(
    of: find.byType(OpenBandExercisePicker),
    matching: matching,
  );

  Finder definitionEditor() => find.byType(OpenBandExerciseDefinitionEditor);

  Finder saveDefinition() => find.byKey(const ValueKey('custom-exercise-save'));

  Finder plusOf(String id) => find.byKey(ValueKey('exercise-select-$id'));

  bool pickerCatalogueReady() {
    if (find.byType(OpenBandExercisePicker).evaluate().isEmpty) {
      return false;
    }
    if (find.text('Bibliothek nicht geladen').evaluate().isNotEmpty) {
      return true;
    }
    if (find.text('Keine Übungen gefunden').evaluate().isNotEmpty) {
      return true;
    }
    return find.text('5 Übungen').evaluate().isNotEmpty ||
        find.text('6 Übungen').evaluate().isNotEmpty ||
        find.text('1 Übung').evaluate().isNotEmpty ||
        find.text('0 Übungen').evaluate().isNotEmpty;
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
    expect(find.text('Eigene Übung'), findsOneWidget);
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

  Future<void> openCreateFromPlus() async {
    final plus = find.byTooltip('Eigene Übung');
    await expectInSafeViewport(plus);
    await tester.tap(plus.hitTestable());
    await reviewPumpPageTransitions(tester);
    await tester.pump();
    expect(definitionEditor(), findsOneWidget);
  }

  Future<void> openCreateFromSearch() async {
    final create = find.byKey(const ValueKey('exercise-create-search'));
    await expectInSafeViewport(create);
    await tester.tap(create.hitTestable());
    await reviewPumpPageTransitions(tester);
    await tester.pump();
    expect(definitionEditor(), findsOneWidget);
  }

  Future<void> searchPicker(String query) async {
    final field = find.byKey(const ValueKey('exercise-search'));
    final picker = find.byType(OpenBandExercisePicker);
    await ensureFullyInSafeViewport(picker, field);
    await enterFocused(field, query);
    await dismissKeyboard();
  }

  Future<void> openDefinitionRow(Key key, {bool sheet = true}) async {
    final editor = definitionEditor();
    final row = find.byKey(key);
    await ensureFullyInSafeViewport(editor, row);
    await tester.tap(row.hitTestable());
    if (sheet) {
      await pumpSheet();
    } else {
      await reviewPumpPageTransitions(tester);
      await tester.pump();
    }
  }

  Future<void> pickSheetChoice(Key sheetKey, Key choiceKey) async {
    final sheet = find.byKey(sheetKey);
    expect(sheet, findsOneWidget);
    final choice = find.byKey(choiceKey);
    expect(choice, findsOneWidget);
    if (choice.hitTestable().evaluate().isEmpty ||
        !rectInSafeViewport(tester.getRect(choice))) {
      await ensureFullyInSafeViewport(sheet, choice);
    }
    await tester.tap(choice.hitTestable());
    await pumpSheet();
  }

  Future<void> enterCount(String value, {String? frame}) async {
    final field = find.byKey(const ValueKey('settings-count-field'));
    expect(field, findsOneWidget);
    await settleKeyboard(field);
    await tester.enterText(field, value);
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, value);
    if (frame != null) {
      await h.capture(frame);
    }
    await dismissKeyboard();
    final apply = find.descendant(
      of: find.byKey(const ValueKey('custom-exercise-count-sheet')),
      matching: find.widgetWithText(OBAction, 'Übernehmen'),
    );
    expect(tester.widget<OBAction>(apply).onPressed, isNotNull);
    await expectInSafeViewport(apply);
    await tester.tap(apply.hitTestable());
    await pumpSheet();
  }

  Future<void> tapMuscle(String id) async {
    final chip = find.byKey(ValueKey('custom-muscle-$id'));
    expect(chip, findsOneWidget);
    if (chip.hitTestable().evaluate().isEmpty) {
      final page = find.ancestor(of: chip, matching: find.byType(Scaffold));
      await ensureFullyInSafeViewport(page, chip);
    } else if (!rectInSafeViewport(tester.getRect(chip))) {
      final page = find.ancestor(of: chip, matching: find.byType(Scaffold));
      await ensureFullyInSafeViewport(page, chip);
    }
    await tester.tap(chip.hitTestable());
    await pumpInk();
  }

  Future<void> confirmMusclePage() async {
    final apply = find.widgetWithText(OBAction, 'Übernehmen');
    await expectInSafeViewport(apply);
    await tester.tap(apply.hitTestable());
    await reviewPumpPageTransitions(tester);
    await tester.pump();
  }

  Future<void> selectMuscles({
    required String primary,
    String? secondary,
    String? frame,
  }) async {
    await openDefinitionRow(
      const ValueKey('custom-exercise-primary'),
      sheet: false,
    );
    await tapMuscle(primary);
    if (frame != null) {
      await h.capture(frame);
    }
    await confirmMusclePage();
    if (secondary == null) return;
    await openDefinitionRow(
      const ValueKey('custom-exercise-secondary'),
      sheet: false,
    );
    await tapMuscle(secondary);
    await confirmMusclePage();
  }

  Future<void> expectEnteredName(String text) async {
    final editor = definitionEditor();
    final name = find.byKey(const ValueKey('custom-exercise-name'));
    await ensureFullyInSafeViewport(editor, name);
    expect(tester.widget<TextField>(name).controller!.text, text);
  }

  Future<void> expectRowValue(Key key, String value) async {
    final editor = definitionEditor();
    final row = find.byKey(key);
    await ensureFullyInSafeViewport(editor, row);
    expect(find.descendant(of: row, matching: find.text(value)), findsWidgets);
  }

  Future<void> fillKurzhantelCurl({
    String? equipmentFrame,
    String? modeFrame,
    String? loadFrame,
    String? countFrame,
    String? repsFrame,
    String? musclesFrame,
  }) async {
    final editor = definitionEditor();
    final name = find.byKey(const ValueKey('custom-exercise-name'));
    await ensureFullyInSafeViewport(editor, name);
    await enterFocused(name, 'Kurzhantel-Curl');
    await dismissKeyboard();
    expect(tester.widget<OBAction>(saveDefinition()).onPressed, isNull);

    await openDefinitionRow(const ValueKey('custom-exercise-equipment'));
    if (equipmentFrame != null) {
      await h.capture(equipmentFrame);
    }
    await pickSheetChoice(
      const ValueKey('custom-exercise-equipment-sheet'),
      const ValueKey('custom-exercise-equipment-dumbbell'),
    );

    await openDefinitionRow(const ValueKey('custom-exercise-mode'));
    if (modeFrame != null) {
      await h.capture(modeFrame);
    }
    await pickSheetChoice(
      const ValueKey('custom-exercise-mode-sheet'),
      const ValueKey('custom-exercise-mode-repetitions'),
    );

    await openDefinitionRow(const ValueKey('custom-exercise-load'));
    if (loadFrame != null) {
      await h.capture(loadFrame);
    }
    await pickSheetChoice(
      const ValueKey('custom-exercise-load-sheet'),
      const ValueKey('custom-exercise-load-perDevice'),
    );

    await openDefinitionRow(const ValueKey('custom-exercise-count'));
    await enterCount('2', frame: countFrame);

    await openDefinitionRow(const ValueKey('custom-exercise-reps'));
    if (repsFrame != null) {
      await h.capture(repsFrame);
    }
    await pickSheetChoice(
      const ValueKey('custom-exercise-reps-sheet'),
      const ValueKey('custom-exercise-reps-perSide'),
    );

    await selectMuscles(
      primary: 'biceps',
      secondary: 'forearms',
      frame: musclesFrame,
    );
    await expectEnteredName('Kurzhantel-Curl');
    await expectRowValue(
      const ValueKey('custom-exercise-equipment'),
      'Kurzhantel',
    );
    await expectRowValue(
      const ValueKey('custom-exercise-mode'),
      'Wiederholungen',
    );
    await expectRowValue(const ValueKey('custom-exercise-load'), 'Je Hantel');
    await expectRowValue(const ValueKey('custom-exercise-count'), '2');
    await expectRowValue(const ValueKey('custom-exercise-reps'), 'Je Seite');
    await expectRowValue(const ValueKey('custom-exercise-primary'), 'Bizeps');
    expect(tester.widget<OBAction>(saveDefinition()).onPressed, isNotNull);
  }

  Future<void> fillWandsitz() async {
    final editor = definitionEditor();
    final name = find.byKey(const ValueKey('custom-exercise-name'));
    await ensureFullyInSafeViewport(editor, name);
    await enterFocused(name, 'Wandsitz');
    await dismissKeyboard();
    await openDefinitionRow(const ValueKey('custom-exercise-equipment'));
    await pickSheetChoice(
      const ValueKey('custom-exercise-equipment-sheet'),
      const ValueKey('custom-exercise-equipment-bodyweight'),
    );
    await openDefinitionRow(const ValueKey('custom-exercise-mode'));
    await pickSheetChoice(
      const ValueKey('custom-exercise-mode-sheet'),
      const ValueKey('custom-exercise-mode-time'),
    );
    expect(find.byKey(const ValueKey('custom-exercise-count')), findsNothing);
    expect(find.byKey(const ValueKey('custom-exercise-reps')), findsNothing);
    await openDefinitionRow(const ValueKey('custom-exercise-load'));
    await pickSheetChoice(
      const ValueKey('custom-exercise-load-sheet'),
      const ValueKey('custom-exercise-load-bodyweight'),
    );
    expect(find.byKey(const ValueKey('custom-exercise-count')), findsNothing);
    expect(find.byKey(const ValueKey('custom-exercise-reps')), findsNothing);
    await selectMuscles(primary: 'legs');
    await expectEnteredName('Wandsitz');
    await expectRowValue(
      const ValueKey('custom-exercise-equipment'),
      'Eigengewicht',
    );
    await expectRowValue(const ValueKey('custom-exercise-mode'), 'Haltezeit');
    await expectRowValue(
      const ValueKey('custom-exercise-load'),
      'Eigengewicht',
    );
    await expectRowValue(const ValueKey('custom-exercise-primary'), 'Beine');
    expect(tester.widget<OBAction>(saveDefinition()).onPressed, isNotNull);
  }

  Future<void> expectEmptyDefinition() async {
    expect(definitionEditor(), findsOneWidget);
    expect(find.text('Eigene Übung'), findsWidgets);
    final nameField = tester.widget<TextField>(
      find.byKey(const ValueKey('custom-exercise-name')),
    );
    expect(nameField.controller!.text, isEmpty);
    expect(nameField.decoration?.hintText, 'Name der Übung');
    expect(find.byKey(const ValueKey('custom-exercise-load')), findsNothing);
    expect(find.byKey(const ValueKey('custom-exercise-count')), findsNothing);
    expect(find.byKey(const ValueKey('custom-exercise-reps')), findsNothing);
    expect(find.text('Auswählen'), findsWidgets);
    expect(find.text('—'), findsWidgets);
    expect(tester.widget<OBAction>(saveDefinition()).onPressed, isNull);
  }

  void expectSavedCurl(ExerciseCatalogueEntry entry) {
    expect(entry.label, 'Kurzhantel-Curl');
    expect(entry.equipment, ExerciseEquipmentCategory.dumbbell);
    expect(entry.mode, ExerciseCaptureMode.repetitions);
    expect(entry.loadBasis, ExerciseLoadBasis.perDevice);
    expect(entry.deviceCount, 2);
    expect(entry.repetitionBasis, ExerciseRepetitionBasis.perSide);
    expect(entry.primaryMuscles, contains('biceps'));
    expect(entry.secondaryMuscles, contains('forearms'));
    expect(entry.source, ExerciseDefinitionSource.stored);
  }

  Future<ExerciseCatalogueEntry> expectPersisted(
    _CustomExerciseReviewRepo repository,
    String id,
  ) async {
    final catalogue = await repository.readExerciseCatalogue();
    final entry = catalogue.byId(id);
    expect(entry, isNotNull);
    return entry!;
  }

  Future<void> expectUnselectedLibrary({
    required String id,
    required String label,
  }) async {
    expect(find.byType(OpenBandExercisePicker), findsOneWidget);
    expect(definitionEditor(), findsNothing);
    expect(inPicker(find.text(label)), findsOneWidget);
    expect(plusOf(id), findsOneWidget);
    expect(find.widgetWithText(OBAction, '1 Übung hinzufügen'), findsNothing);
    expect(
      tester
          .widget<OBAction>(
            find.widgetWithText(OBAction, '0 Übungen hinzufügen'),
          )
          .onPressed,
      isNull,
    );
  }

  Future<void> saveDefinitionAndWait({
    required _CustomExerciseReviewRepo repository,
  }) async {
    final save = saveDefinition();
    await expectInSafeViewport(save);
    expect(tester.widget<OBAction>(save).onPressed, isNotNull);
    await tester.tap(save.hitTestable());
    await reviewPumpPageTransitions(tester);
    await tester.pump();
    await pumpUntil(
      () => definitionEditor().evaluate().isEmpty && pickerCatalogueReady(),
      'Definition editor did not return to the picker after save.',
    );
    expect(repository.lastCreate, isNotNull);
    expect(repository.lastCreate!.saved, isTrue);
    expect(repository.lastCreate!.current, isNotNull);
  }

  // Empty definition via picker header plus.
  var repository = await loadRepo();
  await mountEditor(repository: repository);
  await openPicker();
  await openCreateFromPlus();
  await expectEmptyDefinition();
  await h.capture('custom-exercise-empty');
  await popRoute();
  expect(find.byType(OpenBandExercisePicker), findsOneWidget);

  repository = await loadRepo();
  await mountEditor(repository: repository, brightness: Brightness.dark);
  await openPicker();
  await openCreateFromPlus();
  await expectEmptyDefinition();
  await h.capture('custom-exercise-empty-dark');
  await popRoute();

  // Create-empty-search route, filled curl, genuine fail-once, retry.
  repository = await loadRepo();
  final originalTemplates = templateStamp(await repository.readTemplates());
  await mountEditor(repository: repository);
  await openPicker();
  await searchPicker('Curl');
  expect(find.text('Keine Übungen gefunden'), findsOneWidget);
  expect(find.text('0 Übungen'), findsOneWidget);
  expect(find.byKey(const ValueKey('exercise-create-search')), findsOneWidget);
  await h.capture('custom-exercise-create-search');
  await openCreateFromSearch();
  await expectEmptyDefinition();
  await fillKurzhantelCurl(
    equipmentFrame: 'custom-exercise-equipment',
    modeFrame: 'custom-exercise-mode',
    loadFrame: 'custom-exercise-load',
    countFrame: 'custom-exercise-count',
    repsFrame: 'custom-exercise-reps',
    musclesFrame: 'custom-exercise-muscles',
  );
  await expectInSafeViewport(saveDefinition());
  await h.capture('custom-exercise-filled');
  expect(repository.createCalls, 0);
  expect(repository.lastCreate, isNull);

  repository.failNextCreate = true;
  await tester.tap(saveDefinition().hitTestable());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(repository.createCalls, 1);
  expect(repository.failNextCreate, isFalse);
  expect(repository.lastCreate, isNull);
  expect(
    (await repository.readExerciseCatalogue()).entries.where(
      (entry) => entry.source == ExerciseDefinitionSource.stored,
    ),
    isEmpty,
  );
  expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
  expect(find.text('Erneut speichern'), findsOneWidget);
  await expectEnteredName('Kurzhantel-Curl');
  await expectRowValue(
    const ValueKey('custom-exercise-equipment'),
    'Kurzhantel',
  );
  await expectRowValue(const ValueKey('custom-exercise-reps'), 'Je Seite');
  await expectRowValue(const ValueKey('custom-exercise-primary'), 'Bizeps');
  await h.capture('custom-exercise-save-failure');

  await saveDefinitionAndWait(repository: repository);
  expect(repository.createCalls, 2);
  expect(repository.draftIds, hasLength(2));
  expect(repository.draftIds[0], repository.draftIds[1]);
  final curlId = repository.lastCreate!.current!.id;
  expect(repository.draftIds[0], curlId);
  expect(curlId, isNotEmpty);
  var savedCurl = await expectPersisted(repository, curlId);
  expectSavedCurl(savedCurl);
  expect(
    tester
        .widget<TextField>(find.byKey(const ValueKey('exercise-search')))
        .controller!
        .text,
    'Curl',
  );
  expect(inPicker(find.text('1 Übung')), findsOneWidget);
  expect(inPicker(find.textContaining('2 Hanteln')), findsOneWidget);
  expect(inPicker(find.textContaining('Wdh. je Seite')), findsOneWidget);
  await expectUnselectedLibrary(id: curlId, label: 'Kurzhantel-Curl');
  await h.capture('custom-exercise-library');

  await ensureFullyInSafeViewport(
    find.byType(OpenBandExercisePicker),
    plusOf(curlId),
  );
  await tester.tap(plusOf(curlId).hitTestable());
  await pumpInk();
  final addSelected = find.widgetWithText(OBAction, '1 Übung hinzufügen');
  expect(addSelected, findsOneWidget);
  await expectInSafeViewport(addSelected);
  await tester.tap(addSelected.hitTestable());
  await reviewPumpPageTransitions(tester);
  await tester.pump();
  expect(find.byType(OpenBandExercisePicker), findsNothing);
  expect(find.byType(OpenBandTemplateEditor), findsOneWidget);
  expect(find.text('Kurzhantel-Curl'), findsWidgets);
  final templateName = find.byType(TextField).first;
  await enterFocused(templateName, 'Kurztraining');
  await dismissKeyboard();
  expect(repository.templateSaves, 0);
  expect(templateStamp(await repository.readTemplates()), originalTemplates);
  savedCurl = await expectPersisted(repository, curlId);
  expectSavedCurl(savedCurl);
  await h.capture('custom-exercise-template');

  // Dark filled / count / failure / library on a separate write.
  final darkRepo = await loadRepo();
  await mountEditor(repository: darkRepo, brightness: Brightness.dark);
  await openPicker();
  await searchPicker('Curl');
  await openCreateFromSearch();
  await fillKurzhantelCurl(
    countFrame: 'custom-exercise-count-dark',
    musclesFrame: 'custom-exercise-muscles-dark',
  );
  await h.capture('custom-exercise-filled-dark');
  darkRepo.failNextCreate = true;
  await tester.tap(saveDefinition().hitTestable());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
  expect(find.text('Erneut speichern'), findsOneWidget);
  await expectEnteredName('Kurzhantel-Curl');
  await h.capture('custom-exercise-save-failure-dark');
  await saveDefinitionAndWait(repository: darkRepo);
  final darkId = darkRepo.lastCreate!.current!.id;
  expectSavedCurl(await expectPersisted(darkRepo, darkId));
  await expectUnselectedLibrary(id: darkId, label: 'Kurzhantel-Curl');
  await h.capture('custom-exercise-library-dark');

  // Timed bodyweight variant: count/reps not required, mode time.
  final timeRepo = await loadRepo();
  await mountEditor(repository: timeRepo);
  await openPicker();
  await openCreateFromPlus();
  await fillWandsitz();
  await h.capture('custom-exercise-time');
  await saveDefinitionAndWait(repository: timeRepo);
  final timeId = timeRepo.lastCreate!.current!.id;
  final timeEntry = await expectPersisted(timeRepo, timeId);
  expect(timeEntry.label, 'Wandsitz');
  expect(timeEntry.equipment, ExerciseEquipmentCategory.bodyweight);
  expect(timeEntry.mode, ExerciseCaptureMode.time);
  expect(timeEntry.loadBasis, ExerciseLoadBasis.bodyweight);
  expect(timeEntry.deviceCount, isNull);
  expect(timeEntry.repetitionBasis, isNull);
  expect(timeEntry.primaryMuscles, contains('legs'));
  await expectUnselectedLibrary(id: timeId, label: 'Wandsitz');

  final timeDark = await loadRepo();
  await mountEditor(repository: timeDark, brightness: Brightness.dark);
  await openPicker();
  await openCreateFromPlus();
  await fillWandsitz();
  await h.capture('custom-exercise-time-dark');
  await popRoute();

  Future<void> scrollListToMin(Finder ancestor) async {
    final scrollable = downScrollable(ancestor).first;
    var scrolls = 0;
    var pumps = 0;
    while (true) {
      final position = tester.state<ScrollableState>(scrollable).position;
      final min = position.minScrollExtent;
      final offset = position.pixels - min;
      final idle = !position.isScrollingNotifier.value;
      if (idle && offset.abs() <= 0.5) {
        expect(offset.abs(), lessThanOrEqualTo(0.5));
        expect(position.isScrollingNotifier.value, isFalse);
        return;
      }
      if (offset > 0.5) {
        if (++scrolls > 32) {
          throw FlutterError('ListView did not reach min scroll extent.');
        }
        await tester.drag(scrollable, const Offset(0, 64));
        await tester.pump();
        continue;
      }
      if (++pumps > 40) {
        throw FlutterError('ListView overscroll did not settle at min.');
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> captureScaled({
    required String name,
    required Brightness brightness,
    required bool scrolled,
  }) async {
    final scaled = await loadRepo();
    await mountEditor(repository: scaled, brightness: brightness, scale: 2);
    await openPicker();
    await openCreateFromPlus();
    await fillKurzhantelCurl();
    final editor = definitionEditor();
    final save = saveDefinition();
    await expectInSafeViewport(find.text('Eigene Übung'));
    await expectInSafeViewport(save);
    expect(tester.widget<OBAction>(save).onPressed, isNotNull);
    if (scrolled) {
      final secondary = find.byKey(const ValueKey('custom-exercise-secondary'));
      await ensureFullyInSafeViewport(editor, secondary);
      await expectInSafeViewport(save);
      expect(rectInSafeViewport(tester.getRect(save)), isTrue);
      expect(
        rectInSafeViewport(tester.getRect(secondary), contentOf: editor),
        isTrue,
      );
      await h.capture(name);
      await tester.tap(save.hitTestable());
      await reviewPumpPageTransitions(tester);
      await tester.pump();
      await pumpUntil(
        () => definitionEditor().evaluate().isEmpty && pickerCatalogueReady(),
        'Scaled save did not return to the picker.',
      );
      expect(scaled.lastCreate, isNotNull);
      expect(scaled.lastCreate!.saved, isTrue);
      final scaledId = scaled.lastCreate!.current!.id;
      expectSavedCurl(await expectPersisted(scaled, scaledId));
      await expectUnselectedLibrary(id: scaledId, label: 'Kurzhantel-Curl');
      expect(scaled.templateSaves, 0);
    } else {
      await scrollListToMin(editor);
      await expectEnteredName('Kurzhantel-Curl');
      await expectInSafeViewport(
        find.byKey(const ValueKey('custom-exercise-name')),
        contentOf: editor,
      );
      await h.capture(name);
    }
  }

  await captureScaled(
    name: 'custom-exercise-2x',
    brightness: Brightness.light,
    scrolled: false,
  );
  await captureScaled(
    name: 'custom-exercise-2x-scrolled',
    brightness: Brightness.light,
    scrolled: true,
  );
  await captureScaled(
    name: 'custom-exercise-2x-dark',
    brightness: Brightness.dark,
    scrolled: false,
  );
}
