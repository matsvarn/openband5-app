part of 'harness.dart';

Future<void> reviewExerciseCopy(ReviewHarness h) async {
  final tester = h.tester;
  const curlId = 'custom-curl';
  const shortCurlId = 'custom-curl-short';

  Future<_CustomExerciseReviewRepo> loadRepo() async {
    Future<Map> load(String name) => h.fixture(name);
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

  Finder openOf(String id) => find.byKey(ValueKey('exercise-open-$id'));

  Finder copyAction() => find.byTooltip('Kopieren');

  bool pickerCatalogueReady() {
    if (find.byType(OpenBandExercisePicker).evaluate().isEmpty) {
      return false;
    }
    if (find.text('Bibliothek nicht geladen').evaluate().isNotEmpty) {
      return true;
    }
    final search = find.byKey(const ValueKey('exercise-search'));
    if (search.evaluate().isEmpty) return false;
    return tester.widget<TextField>(search).enabled == true;
  }

  Future<void> pumpPickerReady() async {
    await pumpUntil(
      pickerCatalogueReady,
      'Exercise picker did not finish loading.',
    );
  }

  Future<void> openPicker() async {
    final editor = find.byType(OpenBandTemplateEditor);
    final add = find.widgetWithText(OBAction, 'Übung hinzufügen');
    await ensureFullyInSafeViewport(editor, add);
    await tester.tap(add.hitTestable());
    await pumpSheet();
    expect(find.text('Bibliothek'), findsOneWidget);
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

  Future<void> expectRowValue(Key key, String value) async {
    expect(tester.widget<OBSettingsValueRow>(find.byKey(key)).value, value);
  }

  CustomExerciseDraft curlDraft({
    required String id,
    String label = 'Kurzhantel-Curl',
  }) => CustomExerciseDraft(
    id: id,
    label: label,
    mode: ExerciseCaptureMode.repetitions,
    equipment: ExerciseEquipmentCategory.dumbbell,
    loadBasis: ExerciseLoadBasis.perDevice,
    deviceCount: 2,
    repetitionBasis: ExerciseRepetitionBasis.perSide,
    primaryMuscles: const ['biceps'],
    secondaryMuscles: const ['forearms'],
  );

  Future<void> seedCurl(
    _CustomExerciseReviewRepo repository, {
    String id = curlId,
    String label = 'Kurzhantel-Curl',
  }) async {
    final result = await repository.createCustomExercise(
      curlDraft(id: id, label: label),
    );
    expect(result.saved, isTrue);
  }

  Future<void> openSource(String id) async {
    final picker = find.byType(OpenBandExercisePicker);
    final open = openOf(id);
    await ensureFullyInSafeViewport(picker, open);
    await tester.tap(open.hitTestable());
    await reviewPumpPageTransitions(tester);
    await tester.pump();
    expect(copyAction(), findsOneWidget);
  }

  Future<void> openCopy() async {
    await expectInSafeViewport(copyAction());
    await tester.tap(copyAction().hitTestable());
    await reviewPumpPageTransitions(tester);
    await tester.pump();
    expect(definitionEditor(), findsOneWidget);
    expect(find.bySemanticsLabel('Eigene Übung'), findsWidgets);
  }

  Future<void> fillPresetRemainder() async {
    await openDefinitionRow(const ValueKey('custom-exercise-load'));
    await pickSheetChoice(
      const ValueKey('custom-exercise-load-sheet'),
      const ValueKey('custom-exercise-load-total'),
    );
    await openDefinitionRow(const ValueKey('custom-exercise-reps'));
    await pickSheetChoice(
      const ValueKey('custom-exercise-reps-sheet'),
      const ValueKey('custom-exercise-reps-total'),
    );
  }

  Future<void> expectUnselectedAdd() async {
    expect(
      tester
          .widget<OBAction>(
            find.widgetWithText(OBAction, '0 Übungen hinzufügen'),
          )
          .onPressed,
      isNull,
    );
  }

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

  Future<void> saveAndReturn(_CustomExerciseReviewRepo repository) async {
    final save = saveDefinition();
    await expectInSafeViewport(save);
    expect(tester.widget<OBAction>(save).onPressed, isNotNull);
    await tester.tap(save.hitTestable());
    await reviewPumpPageTransitions(tester);
    await tester.pump();
    await pumpUntil(
      () =>
          definitionEditor().evaluate().isEmpty &&
          find.byType(OpenBandExercisePicker).evaluate().isNotEmpty &&
          pickerCatalogueReady(),
      'Copy did not unwind editor and detail to the picker.',
    );
    expect(repository.lastCreate, isNotNull);
    expect(repository.lastCreate!.saved, isTrue);
  }

  final bench = _pickerPreset('bench_press');

  var repository = await loadRepo();
  await seedCurl(repository);
  final originalTemplates = templateStamp(await repository.readTemplates());
  await mountEditor(repository: repository);
  await openPicker();
  await openSource(bench.id);
  expect(find.text(bench.labelDe), findsOneWidget);
  expect(find.text('OpenBand'), findsOneWidget);
  expect(copyAction(), findsOneWidget);
  await h.capture('exercise-copy-source');
  await openCopy();
  expect(find.text('Bankdrücken · Kopie'), findsOneWidget);
  expect(tester.widget<OBAction>(saveDefinition()).onPressed, isNull);
  await expectRowValue(
    const ValueKey('custom-exercise-equipment'),
    'Langhantel',
  );
  await expectRowValue(const ValueKey('custom-exercise-load'), 'Auswählen');
  await h.capture('exercise-copy-preset');
  await popRoute();
  expect(definitionEditor(), findsNothing);
  expect(find.text(bench.labelDe), findsOneWidget);
  expect(copyAction(), findsOneWidget);
  await h.capture('exercise-copy-cancel');
  await popRoute();
  expect(find.byType(OpenBandExercisePicker), findsOneWidget);
  expect(repository.createCalls, 1);
  expect(repository.lastCreate!.current!.id, curlId);
  expect(templateStamp(await repository.readTemplates()), originalTemplates);
  expect(repository.templateSaves, 0);

  repository = await loadRepo();
  await seedCurl(repository);
  await mountEditor(repository: repository, brightness: Brightness.dark);
  await openPicker();
  await openSource(bench.id);
  await h.capture('exercise-copy-source-dark');
  await openCopy();
  expect(find.text('Bankdrücken · Kopie'), findsOneWidget);
  await h.capture('exercise-copy-preset-dark');
  await popRoute();
  await popRoute();

  repository = await loadRepo();
  await seedCurl(repository);
  await mountEditor(repository: repository);
  await openPicker();
  await searchPicker('Curl');
  await openSource(curlId);
  expect(find.text('Kurzhantel-Curl'), findsOneWidget);
  await openCopy();
  expect(find.text('Kurzhantel-Curl · Kopie'), findsOneWidget);
  await expectRowValue(
    const ValueKey('custom-exercise-equipment'),
    'Kurzhantel',
  );
  await expectRowValue(const ValueKey('custom-exercise-load'), 'Je Hantel');
  await expectRowValue(const ValueKey('custom-exercise-count'), '2');
  await expectRowValue(const ValueKey('custom-exercise-reps'), 'Je Seite');
  await expectRowValue(const ValueKey('custom-exercise-primary'), 'Bizeps');
  await expectRowValue(const ValueKey('custom-exercise-secondary'), 'Unterarm');
  expect(tester.widget<OBAction>(saveDefinition()).onPressed, isNotNull);
  await h.capture('exercise-copy-custom');
  repository.failNextCreate = true;
  await tester.tap(saveDefinition().hitTestable());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
  expect(find.text('Erneut speichern'), findsOneWidget);
  expect(find.text('Kurzhantel-Curl · Kopie'), findsOneWidget);
  await h.capture('exercise-copy-retry');
  await saveAndReturn(repository);
  final copied = repository.lastCreate!.current!;
  expect(copied.id, isNot(curlId));
  expect(copied.id, isNot(bench.id));
  expect(copied.retained['copiedFrom'], curlId);
  expect(
    (await repository.readExerciseCatalogue()).byId(curlId)!.label,
    'Kurzhantel-Curl',
  );
  expect(inPicker(find.text('Kurzhantel-Curl')), findsOneWidget);
  expect(inPicker(find.text('Kurzhantel-Curl · Kopie')), findsOneWidget);
  expect(plusOf(curlId), findsOneWidget);
  expect(plusOf(copied.id), findsOneWidget);
  await expectUnselectedAdd();
  expect(repository.templateSaves, 0);
  await h.capture('exercise-copy-library');

  repository = await loadRepo();
  await seedCurl(repository);
  await mountEditor(repository: repository, brightness: Brightness.dark);
  await openPicker();
  await searchPicker('Curl');
  await openSource(curlId);
  await openCopy();
  await h.capture('exercise-copy-custom-dark');
  repository.failNextCreate = true;
  await tester.tap(saveDefinition().hitTestable());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
  await h.capture('exercise-copy-retry-dark');
  await saveAndReturn(repository);
  await h.capture('exercise-copy-library-dark');
  expect(repository.templateSaves, 0);

  repository = await loadRepo();
  await seedCurl(repository);
  await mountEditor(repository: repository);
  await openPicker();
  await searchPicker('Bank');
  await openSource(bench.id);
  await openCopy();
  await fillPresetRemainder();
  final name = find.byKey(const ValueKey('custom-exercise-name'));
  await enterFocused(name, 'Wandsitz');
  await dismissKeyboard();
  await saveAndReturn(repository);
  final hidden = repository.lastCreate!.current!;
  expect(hidden.label, 'Wandsitz');
  final notice = find.byKey(const ValueKey('custom-exercise-saved'));
  expect(notice, findsOneWidget);
  expect(
    find.descendant(of: notice, matching: find.text('Anzeigen')),
    findsOneWidget,
  );
  await h.capture('exercise-copy-hidden');
  await tester.tap(find.text('Anzeigen').hitTestable());
  await pumpInk();
  expect(find.byKey(const ValueKey('custom-exercise-saved')), findsNothing);
  expect(inPicker(find.text('Wandsitz')), findsWidgets);
  await h.capture('exercise-copy-hidden-reveal');
  expect(repository.templateSaves, 0);

  Future<void> captureScaled({
    required String name,
    required Brightness brightness,
    required bool scrolled,
  }) async {
    final scaled = await loadRepo();
    await seedCurl(scaled, id: shortCurlId, label: 'Curl');
    await mountEditor(repository: scaled, brightness: brightness, scale: 2);
    await openPicker();
    await searchPicker('Curl');
    await openSource(shortCurlId);
    await openCopy();
    expect(find.text('Curl · Kopie'), findsOneWidget);
    final editor = definitionEditor();
    final save = saveDefinition();
    await expectInSafeViewport(find.bySemanticsLabel('Eigene Übung'));
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
    } else {
      await scrollListToMin(editor);
      await expectInSafeViewport(
        find.byKey(const ValueKey('custom-exercise-name')),
        contentOf: editor,
      );
      await h.capture(name);
    }
  }

  await captureScaled(
    name: 'exercise-copy-2x',
    brightness: Brightness.light,
    scrolled: false,
  );
  await captureScaled(
    name: 'exercise-copy-2x-scrolled',
    brightness: Brightness.light,
    scrolled: true,
  );
  await captureScaled(
    name: 'exercise-copy-2x-dark',
    brightness: Brightness.dark,
    scrolled: false,
  );
  await captureScaled(
    name: 'exercise-copy-2x-scrolled-dark',
    brightness: Brightness.dark,
    scrolled: true,
  );
}
