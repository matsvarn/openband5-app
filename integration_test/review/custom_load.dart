part of 'harness.dart';

Future<void> reviewCustomLoad(ReviewHarness h) async {
  final tester = h.tester;
  const curlId = 'custom-curl';
  const holdId = 'custom-hold';

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

  Finder hintedField(String hint) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.hintText == hint,
  );

  Finder plusOf(String id) => find.byKey(ValueKey('exercise-select-$id'));

  Finder saveTemplateAction() =>
      find.widgetWithText(OBAction, 'Vorlage speichern');

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

  Future<void> mountLive({
    required _CustomExerciseReviewRepo repository,
    required WorkoutTemplate template,
    Brightness brightness = Brightness.light,
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      reviewHost(
        brightness: brightness,
        scale: scale,
        home: OpenBandStrengthLive(repository: repository, template: template),
      ),
    );
    await pumpUntil(
      () =>
          find.byType(OpenBandStrengthLive).evaluate().isNotEmpty &&
          find.text(template.name).evaluate().isNotEmpty,
      'Live session did not start.',
    );
  }

  bool pickerCatalogueReady() {
    if (find.byType(OpenBandExercisePicker).evaluate().isEmpty) {
      return false;
    }
    return find.text('5 Übungen').evaluate().isNotEmpty ||
        find.text('6 Übungen').evaluate().isNotEmpty ||
        find.text('1 Übung').evaluate().isNotEmpty ||
        find.text('0 Übungen').evaluate().isNotEmpty ||
        find.text('Keine Übungen gefunden').evaluate().isNotEmpty;
  }

  Future<void> openPicker() async {
    final editor = find.byType(OpenBandTemplateEditor);
    final add = find.widgetWithText(OBAction, 'Übung hinzufügen');
    await ensureFullyInSafeViewport(editor, add);
    await tester.tap(add.hitTestable());
    await pumpSheet();
    await tester.tap(find.text('Bibliothek'));
    await pumpUntil(
      pickerCatalogueReady,
      'Exercise picker did not finish loading.',
    );
  }

  Future<CustomExerciseWriteResult> seedCurl(
    _CustomExerciseReviewRepo repository,
  ) {
    return repository.createCustomExercise(
      CustomExerciseDraft(
        id: curlId,
        label: 'Kurzhantel-Curl',
        mode: ExerciseCaptureMode.repetitions,
        equipment: ExerciseEquipmentCategory.dumbbell,
        loadBasis: ExerciseLoadBasis.perDevice,
        deviceCount: 2,
        repetitionBasis: ExerciseRepetitionBasis.perSide,
        primaryMuscles: const ['biceps'],
        secondaryMuscles: const ['forearms'],
      ),
    );
  }

  Future<void> addCurlFromLibrary() async {
    await openPicker();
    final picker = find.byType(OpenBandExercisePicker);
    final search = find.byKey(const ValueKey('exercise-search'));
    await ensureFullyInSafeViewport(picker, search);
    await enterFocused(search, 'Curl');
    await dismissKeyboard();
    await ensureFullyInSafeViewport(picker, plusOf(curlId));
    await tester.tap(plusOf(curlId).hitTestable());
    await pumpInk();
    final add = find.widgetWithText(OBAction, '1 Übung hinzufügen');
    await expectInSafeViewport(add);
    await tester.tap(add.hitTestable());
    await reviewPumpPageTransitions(tester);
    await tester.pump();
    expect(find.byType(OpenBandExercisePicker), findsNothing);
    expect(find.text('Kurzhantel-Curl'), findsWidgets);
    expect(find.text('kg je Hantel · Wdh. je Seite'), findsOneWidget);
  }

  Future<void> fillPlanFields() async {
    final editor = find.byType(OpenBandTemplateEditor);
    final name = hintedField('Name der Vorlage');
    await ensureFullyInSafeViewport(editor, name);
    await enterFocused(name, 'Kurztraining');
    await dismissKeyboard();
    final load = hintedField('kg');
    await ensureFullyInSafeViewport(editor, load);
    await enterFocused(load, '10');
    await dismissKeyboard();
    final reps = hintedField('Wdh.');
    await ensureFullyInSafeViewport(editor, reps);
    await enterFocused(reps, '8');
    await dismissKeyboard();
    expect(tester.widget<TextField>(load).controller!.text, '10');
    expect(tester.widget<TextField>(reps).controller!.text, '8');
    expect(find.text('Beide Seiten'), findsOneWidget);
  }

  Future<WorkoutTemplate> saveAndRead(
    _CustomExerciseReviewRepo repository,
  ) async {
    final save = saveTemplateAction();
    await expectInSafeViewport(save);
    expect(tester.widget<OBAction>(save).onPressed, isNotNull);
    final saves = repository.templateSaves;
    await tester.tap(save.hitTestable());
    await reviewPumpPageTransitions(tester);
    await tester.pump();
    expect(repository.templateSaves, saves + 1);
    return (await repository.readTemplates()).firstWhere(
      (t) => t.name == 'Kurztraining',
    );
  }

  void expectBothSidesCurl(PlannedSet set) {
    expect(set.reps, 8);
    expect(set.loadKg, 20);
    expect(set.load, isNotNull);
    expect(set.load!.value, 10);
    expect(set.load!.deviceCount, 2);
    expect(set.load!.side, ExerciseSetSide.both);
    expect(set.load!.basis, ExerciseLoadBasis.perDevice);
    expect(set.load!.unit, ExerciseLoadUnit.kg);
    expect(set.load!.repetitionBasis, ExerciseRepetitionBasis.perSide);
  }

  Finder liveField(String setId, List<String> suffixes) {
    for (final suffix in suffixes) {
      final found = find.byKey(ValueKey('field-$setId-$suffix'));
      if (found.evaluate().isNotEmpty) return found;
    }
    throw FlutterError(
      'Missing live field field-$setId-{${suffixes.join(',')}}',
    );
  }

  Finder liveLoadField(String setId) =>
      liveField(setId, const ['kg', '76', '76.0']);

  Finder liveRepsField(String setId) =>
      liveField(setId, const ['wdh', '64', '64.0']);

  Future<void> enterLiveSet(String setId) async {
    final live = find.byType(OpenBandStrengthLive);
    final load = liveLoadField(setId);
    await ensureFullyInSafeViewport(live, load);
    await enterFocused(load, '10');
    await dismissKeyboard();
    final reps = liveRepsField(setId);
    await ensureFullyInSafeViewport(live, reps);
    await enterFocused(reps, '8');
    await dismissKeyboard();
  }

  Future<ActiveStrengthSession> expectRecordedCurl({
    required _CustomExerciseReviewRepo repository,
    required String setId,
  }) async {
    final runtime = await repository.readActiveStrengthSession();
    expect(runtime, isA<ActiveStrengthSession>());
    final session = runtime as ActiveStrengthSession;
    expect(session.recorded, hasLength(1));
    final recorded = session.recorded.single;
    expect(recorded.plannedSetId, setId);
    expect(recorded.reps, 8);
    expect(recorded.loadKg, 20);
    expect(recorded.load, isNotNull);
    expect(recorded.load!.value, 10);
    expect(recorded.load!.deviceCount, 2);
    expect(recorded.load!.side, ExerciseSetSide.both);
    return session;
  }

  // Main plan: 10 kg × 2 devices, 8 per side, both sides.
  var repository = await loadRepo();
  expect((await seedCurl(repository)).saved, isTrue);
  await mountEditor(repository: repository);
  await addCurlFromLibrary();
  await fillPlanFields();
  await expectInSafeViewport(saveTemplateAction());
  await h.capture('custom-load-plan');

  final side = find.text('Beide Seiten').first;
  final editor = find.byType(OpenBandTemplateEditor);
  await ensureFullyInSafeViewport(editor, side);
  await tester.tap(side.hitTestable());
  await pumpSheet();
  expect(find.text('Seite'), findsOneWidget);
  expect(find.text('Links'), findsOneWidget);
  expect(find.text('Rechts'), findsOneWidget);
  await h.capture('custom-load-side');
  await tester.tap(find.text('Beide Seiten').last);
  await pumpSheet();
  expect(find.text('Seite'), findsNothing);

  var saved = await saveAndRead(repository);
  expectBothSidesCurl(saved.exercises.single.sets.single);
  await mountEditor(repository: repository, template: saved);
  expect(tester.widget<TextField>(hintedField('kg')).controller!.text, '10');
  expect(tester.widget<TextField>(hintedField('Wdh.')).controller!.text, '8');
  expect(find.text('Beide Seiten'), findsOneWidget);
  expectBothSidesCurl(
    (await repository.readTemplates())
        .firstWhere((t) => t.id == saved.id)
        .exercises
        .single
        .sets
        .single,
  );

  await mountEditor(
    repository: repository,
    template: saved,
    brightness: Brightness.dark,
  );
  expect(find.text('kg je Hantel · Wdh. je Seite'), findsOneWidget);
  await h.capture('custom-load-plan-dark');

  final setId = saved.exercises.single.sets.single.id;
  await mountLive(repository: repository, template: saved);
  await enterLiveSet(setId);
  expect(find.text('kg je Hantel · Wdh. je Seite'), findsOneWidget);
  expect(find.text('Beide Seiten'), findsOneWidget);
  await tester.tap(find.byTooltip('Übungsmenü'));
  await pumpSheet();
  expect(find.text('Einheit'), findsOneWidget);
  expect(find.text('kg'), findsWidgets);
  Navigator.of(tester.element(find.text('Einheit'))).pop();
  await pumpSheet();
  await h.capture('custom-load-live');

  repository.failStrengthWrites = true;
  final confirm = find.byKey(ValueKey('confirm-$setId'));
  await ensureFullyInSafeViewport(find.byType(OpenBandStrengthLive), confirm);
  await tester.tap(confirm.hitTestable());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
  expect(tester.widget<TextField>(liveLoadField(setId)).controller!.text, '10');
  expect(tester.widget<TextField>(liveRepsField(setId)).controller!.text, '8');
  expect(
    ((await repository.readActiveStrengthSession()) as ActiveStrengthSession)
        .recorded,
    isEmpty,
  );
  await h.capture('custom-load-record-error');

  repository.failStrengthWrites = false;
  await tester.tap(find.text('Erneut'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await expectRecordedCurl(repository: repository, setId: setId);
  expect(find.text('Speichern fehlgeschlagen'), findsNothing);

  // Dark live + error on a fresh write (one active session per repo).
  final darkRepo = await loadRepo();
  expect((await seedCurl(darkRepo)).saved, isTrue);
  await darkRepo.saveTemplate(saved);
  await mountLive(
    repository: darkRepo,
    template: saved,
    brightness: Brightness.dark,
  );
  await enterLiveSet(setId);
  await h.capture('custom-load-live-dark');
  darkRepo.failStrengthWrites = true;
  await tester.tap(find.byKey(ValueKey('confirm-$setId')).hitTestable());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
  expect(tester.widget<TextField>(liveLoadField(setId)).controller!.text, '10');
  await h.capture('custom-load-record-error-dark');
  darkRepo.failStrengthWrites = false;
  await tester.tap(find.text('Erneut'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await expectRecordedCurl(repository: darkRepo, setId: setId);

  // Left side uses one actual device.
  final leftRepo = await loadRepo();
  expect((await seedCurl(leftRepo)).saved, isTrue);
  await mountEditor(repository: leftRepo);
  await addCurlFromLibrary();
  await fillPlanFields();
  await ensureFullyInSafeViewport(
    find.byType(OpenBandTemplateEditor),
    find.text('Beide Seiten').first,
  );
  await tester.tap(find.text('Beide Seiten').first.hitTestable());
  await pumpSheet();
  await tester.tap(find.text('Links'));
  await pumpSheet();
  expect(find.text('Links'), findsOneWidget);
  final leftSaved = await saveAndRead(leftRepo);
  final leftSet = leftSaved.exercises.single.sets.single;
  expect(leftSet.reps, 8);
  expect(leftSet.loadKg, 10);
  expect(leftSet.load!.value, 10);
  expect(leftSet.load!.deviceCount, 1);
  expect(leftSet.load!.side, ExerciseSetSide.left);

  // Timed bodyweight: weight field absent, unit not offered.
  final timeRepo = await loadRepo();
  expect(
    (await timeRepo.createCustomExercise(
      CustomExerciseDraft(
        id: holdId,
        label: 'Wandsitz',
        mode: ExerciseCaptureMode.time,
        equipment: ExerciseEquipmentCategory.bodyweight,
        loadBasis: ExerciseLoadBasis.bodyweight,
        primaryMuscles: const ['legs'],
      ),
    )).saved,
    isTrue,
  );
  await mountEditor(repository: timeRepo);
  await openPicker();
  await ensureFullyInSafeViewport(
    find.byType(OpenBandExercisePicker),
    plusOf(holdId),
  );
  await tester.tap(plusOf(holdId).hitTestable());
  await pumpInk();
  await tester.tap(
    find.widgetWithText(OBAction, '1 Übung hinzufügen').hitTestable(),
  );
  await reviewPumpPageTransitions(tester);
  await tester.pump();
  expect(hintedField('kg'), findsNothing);
  expect(hintedField('lb'), findsNothing);
  expect(hintedField('Sek.'), findsOneWidget);
  expect(find.text('Beide Seiten'), findsNothing);
  expect(find.textContaining('je Hantel'), findsNothing);
  await h.capture('custom-load-bodyweight');

  // Unknown historic metadata is not recaptioned as je Hantel.
  final unknownRepo = await loadRepo();
  expect((await seedCurl(unknownRepo)).saved, isTrue);
  final unknownLoad = OriginalLoadInput.fromJson({
    'value': 17.25,
    'unit': 'stone',
    'basis': 'futureBasis',
    'repetitionBasis': 'futureReps',
    'side': 'futureSide',
    'future': {'v': 2},
  });
  final unknownTemplate = WorkoutTemplate(
    id: 'tpl-unknown-load',
    name: 'Altlast',
    version: 1,
    exercises: [
      PlannedExercise(
        id: 'ex-unknown',
        exerciseKey: curlId,
        name: 'Kurzhantel-Curl',
        definition: (await unknownRepo.readExerciseCatalogue())
            .byId(curlId)!
            .snapshot(),
        sets: [
          PlannedSet(id: 'set-unknown', reps: 8, loadKg: 20, load: unknownLoad),
        ],
      ),
    ],
    updatedAt: DateTime(2026, 9, 1),
  );
  await unknownRepo.saveTemplate(unknownTemplate);
  await mountEditor(repository: unknownRepo, template: unknownTemplate);
  expect(find.textContaining('je Hantel'), findsNothing);
  expect(find.byKey(const ValueKey('side-set-unknown')), findsNothing);
  await h.capture('custom-load-unknown');

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

  Future<void> capturePlanScaled({
    required String name,
    required bool scrolled,
  }) async {
    final scaled = await loadRepo();
    expect((await seedCurl(scaled)).saved, isTrue);
    await mountEditor(repository: scaled, scale: 2);
    await addCurlFromLibrary();
    await fillPlanFields();
    final save = saveTemplateAction();
    await expectInSafeViewport(find.text('Neue Vorlage'));
    await expectInSafeViewport(save);
    if (scrolled) {
      await ensureFullyInSafeViewport(
        find.byType(OpenBandTemplateEditor),
        find.text('Satz hinzufügen'),
      );
      await expectInSafeViewport(save);
      await h.capture(name);
      await tester.tap(save.hitTestable());
      await reviewPumpPageTransitions(tester);
      await tester.pump();
      expect(scaled.templateSaves, 1);
      expectBothSidesCurl(
        (await scaled.readTemplates())
            .firstWhere((t) => t.name == 'Kurztraining')
            .exercises
            .single
            .sets
            .single,
      );
    } else {
      final editor = find.byType(OpenBandTemplateEditor);
      await scrollListToMin(editor);
      final title = hintedField('Name der Vorlage');
      await ensureFullyInSafeViewport(editor, title);
      expect(tester.widget<TextField>(title).controller!.text, 'Kurztraining');
      await h.capture(name);
    }
  }

  await capturePlanScaled(name: 'custom-load-plan-2x', scrolled: false);
  await capturePlanScaled(name: 'custom-load-plan-2x-scrolled', scrolled: true);

  Future<void> captureLiveScaled({
    required String name,
    required bool scrolled,
  }) async {
    final scaled = await loadRepo();
    expect((await seedCurl(scaled)).saved, isTrue);
    await scaled.saveTemplate(saved);
    await mountLive(repository: scaled, template: saved, scale: 2);
    await enterLiveSet(setId);
    final confirm = find.byKey(ValueKey('confirm-$setId'));
    final live = find.byType(OpenBandStrengthLive);
    await expectInSafeViewport(find.text('Kurztraining'));
    if (scrolled) {
      await ensureFullyInSafeViewport(live, confirm);
      expect(rectInSafeViewport(tester.getRect(confirm)), isTrue);
      await h.capture(name);
      await tester.tap(confirm.hitTestable());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await expectRecordedCurl(repository: scaled, setId: setId);
    } else {
      await scrollListToMin(live);
      await expectInSafeViewport(find.text('Kurztraining'));
      expect(find.text('Kurzhantel-Curl'), findsWidgets);
      await h.capture(name);
    }
  }

  await captureLiveScaled(name: 'custom-load-live-2x', scrolled: false);
  await captureLiveScaled(name: 'custom-load-live-2x-scrolled', scrolled: true);

  Future<void> pickDefinitionChoice(Key sheetKey, Key choiceKey) async {
    expect(find.byKey(sheetKey), findsOneWidget);
    final choice = find.byKey(choiceKey);
    expect(choice, findsOneWidget);
    if (choice.hitTestable().evaluate().isEmpty) {
      await ensureFullyInSafeViewport(find.byKey(sheetKey), choice);
    }
    await tester.tap(choice.hitTestable());
    await pumpSheet();
  }

  Future<void> fillHiddenWandsitz() async {
    final editor = find.byType(OpenBandExerciseDefinitionEditor);
    expect(editor, findsOneWidget);
    final name = find.byKey(const ValueKey('custom-exercise-name'));
    await ensureFullyInSafeViewport(editor, name);
    await enterFocused(name, 'Wandsitz');
    await dismissKeyboard();
    await ensureFullyInSafeViewport(
      editor,
      find.byKey(const ValueKey('custom-exercise-equipment')),
    );
    await tester.tap(
      find.byKey(const ValueKey('custom-exercise-equipment')).hitTestable(),
    );
    await pumpSheet();
    await pickDefinitionChoice(
      const ValueKey('custom-exercise-equipment-sheet'),
      const ValueKey('custom-exercise-equipment-bodyweight'),
    );
    await ensureFullyInSafeViewport(
      editor,
      find.byKey(const ValueKey('custom-exercise-mode')),
    );
    await tester.tap(
      find.byKey(const ValueKey('custom-exercise-mode')).hitTestable(),
    );
    await pumpSheet();
    await pickDefinitionChoice(
      const ValueKey('custom-exercise-mode-sheet'),
      const ValueKey('custom-exercise-mode-time'),
    );
    await ensureFullyInSafeViewport(
      editor,
      find.byKey(const ValueKey('custom-exercise-load')),
    );
    await tester.tap(
      find.byKey(const ValueKey('custom-exercise-load')).hitTestable(),
    );
    await pumpSheet();
    await pickDefinitionChoice(
      const ValueKey('custom-exercise-load-sheet'),
      const ValueKey('custom-exercise-load-bodyweight'),
    );
    await ensureFullyInSafeViewport(
      editor,
      find.byKey(const ValueKey('custom-exercise-primary')),
    );
    await tester.tap(
      find.byKey(const ValueKey('custom-exercise-primary')).hitTestable(),
    );
    await reviewPumpPageTransitions(tester);
    await tester.pump();
    final legs = find.byKey(const ValueKey('custom-muscle-legs'));
    expect(legs, findsOneWidget);
    await tester.tap(legs.hitTestable());
    await pumpInk();
    await tester.tap(find.widgetWithText(OBAction, 'Übernehmen').hitTestable());
    await reviewPumpPageTransitions(tester);
    await tester.pump();
    final save = find.byKey(const ValueKey('custom-exercise-save'));
    await expectInSafeViewport(save);
    expect(tester.widget<OBAction>(save).onPressed, isNotNull);
    await tester.tap(save.hitTestable());
    await reviewPumpPageTransitions(tester);
    await tester.pump();
    await pumpUntil(
      () =>
          find.byType(OpenBandExerciseDefinitionEditor).evaluate().isEmpty &&
          pickerCatalogueReady(),
      'Hidden create did not return to the picker.',
    );
  }

  Future<void> expectHiddenNotice(String label) async {
    final notice = find.byKey(const ValueKey('custom-exercise-saved'));
    expect(notice, findsOneWidget);
    expect(
      find.descendant(of: notice, matching: find.text(label)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: notice, matching: find.text('Anzeigen')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(OpenBandExercisePicker),
        matching: find.text(label),
      ),
      findsOneWidget,
    );
  }

  Future<void> captureHidden({
    required String name,
    required double scale,
    required bool reveal,
  }) async {
    final hiddenRepo = await loadRepo();
    await mountEditor(repository: hiddenRepo, scale: scale);
    await openPicker();
    final picker = find.byType(OpenBandExercisePicker);
    final search = find.byKey(const ValueKey('exercise-search'));
    await ensureFullyInSafeViewport(picker, search);
    await enterFocused(search, 'Zebra');
    await dismissKeyboard();
    expect(find.text('Keine Übungen gefunden'), findsOneWidget);
    final create = find.byKey(const ValueKey('exercise-create-search'));
    await expectInSafeViewport(create);
    await tester.tap(create.hitTestable());
    await reviewPumpPageTransitions(tester);
    await tester.pump();
    await fillHiddenWandsitz();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('exercise-search')))
          .controller!
          .text,
      'Zebra',
    );
    expect(
      find.descendant(of: picker, matching: find.text('Wandsitz')),
      findsOneWidget,
    );
    await expectHiddenNotice('Wandsitz');
    final notice = find.byKey(const ValueKey('custom-exercise-saved'));
    final footer = find.ancestor(of: notice, matching: find.byType(ListView));
    final anzeigen = find.descendant(
      of: notice,
      matching: find.text('Anzeigen'),
    );
    final clear = find.widgetWithText(OBAction, 'Suche löschen');
    await ensureFullyInSafeViewport(footer, notice);
    await ensureFullyInSafeViewport(footer, anzeigen);
    await ensureFullyInSafeViewport(footer, create);
    await ensureFullyInSafeViewport(footer, clear);
    await h.capture(name);
    if (!reveal) return;
    await tester.tap(anzeigen.hitTestable());
    await tester.pump();
    expect(find.byKey(const ValueKey('custom-exercise-saved')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('exercise-search')))
          .controller!
          .text,
      'Wandsitz',
    );
    expect(
      find.descendant(of: picker, matching: find.text('Wandsitz')),
      findsWidgets,
    );
    expect(plusOf(hiddenRepo.lastCreate!.current!.id), findsOneWidget);
  }

  await captureHidden(name: 'custom-load-hidden', scale: 1, reveal: false);
  await captureHidden(name: 'custom-load-hidden-2x', scale: 2, reveal: true);
  OriginalLoadInput perDeviceOriginal({
    required double value,
    required ExerciseLoadUnit unit,
  }) => OriginalLoadInput(
    value: value,
    unit: unit,
    basis: ExerciseLoadBasis.perDevice,
    deviceCount: 2,
    repetitionBasis: ExerciseRepetitionBasis.perSide,
    side: ExerciseSetSide.both,
  );

  Future<WorkoutTemplate> writePlan(
    _CustomExerciseReviewRepo repository,
    WorkoutTemplate template,
  ) async {
    await repository.saveTemplate(template);
    return (await repository.readTemplates()).firstWhere(
      (t) => t.id == template.id,
    );
  }

  Future<ExerciseDefinitionSnapshot> curlSnapshot(
    _CustomExerciseReviewRepo repository,
  ) async {
    expect((await seedCurl(repository)).saved, isTrue);
    return (await repository.readExerciseCatalogue()).byId(curlId)!.snapshot();
  }

  PlannedSet planned({
    required String id,
    required int reps,
    OriginalLoadInput? load,
    double? loadKg,
  }) {
    final resolved = resolveStoredLoadKg(input: load, loadKg: loadKg);
    return PlannedSet(
      id: id,
      reps: reps,
      loadKg: resolved,
      mode: PlannedSetMode.repetitions,
      load: load,
    );
  }

  WorkoutTemplate curlPlan({
    required String id,
    required ExerciseDefinitionSnapshot definition,
    required List<PlannedSet> sets,
  }) => WorkoutTemplate(
    id: id,
    name: 'Kurztraining',
    version: 1,
    exercises: [
      PlannedExercise(
        id: 'ex-$id',
        exerciseKey: curlId,
        name: 'Kurzhantel-Curl',
        definition: definition,
        sets: sets,
      ),
    ],
    updatedAt: DateTime(2026, 9, 1),
  );

  Future<void> mountNamedLive({
    required _CustomExerciseReviewRepo repository,
    required WorkoutTemplate template,
    required String label,
    Brightness brightness = Brightness.light,
    double scale = 1,
  }) async {
    await mountLive(
      repository: repository,
      template: template,
      brightness: brightness,
      scale: scale,
    );
    await pumpUntil(
      () => find.text(label).evaluate().isNotEmpty,
      'Live session did not show $label.',
    );
  }

  final kg10 = perDeviceOriginal(value: 10, unit: ExerciseLoadUnit.kg);
  final lb22 = perDeviceOriginal(value: 22, unit: ExerciseLoadUnit.lb);
  expect(resolveStoredLoadKg(input: kg10), 20);
  expect(resolveStoredLoadKg(input: lb22), 22 * kKilogramsPerPound * 2);

  Future<WorkoutTemplate> mixedUnitsPlan(
    _CustomExerciseReviewRepo repository,
  ) async {
    final definition = await curlSnapshot(repository);
    final saved = await writePlan(
      repository,
      curlPlan(
        id: 'tpl-mixed-units',
        definition: definition,
        sets: [
          planned(id: 'set-mix-kg1', reps: 8, load: kg10),
          planned(id: 'set-mix-lb', reps: 8, load: lb22),
          planned(id: 'set-mix-kg2', reps: 8, load: kg10),
        ],
      ),
    );
    final sets = saved.exercises.single.sets;
    expect(sets, hasLength(3));
    expect(sets[0].loadKg, 20);
    expect(sets[0].load!.value, 10);
    expect(sets[0].load!.unit, ExerciseLoadUnit.kg);
    expect(sets[0].load!.deviceCount, 2);
    expect(sets[1].load!.value, 22);
    expect(sets[1].load!.unit, ExerciseLoadUnit.lb);
    expect(sets[1].loadKg, resolveStoredLoadKg(input: sets[1].load));
    expect(sets[2].loadKg, 20);
    expect(sets[2].load!.value, 10);
    return saved;
  }

  Future<void> confirmPerDeviceFirst(
    _CustomExerciseReviewRepo repository, {
    required String setId,
  }) async {
    final live = find.byType(OpenBandStrengthLive);
    final load = liveLoadField(setId);
    await ensureFullyInSafeViewport(live, load);
    await enterFocused(load, '10');
    await dismissKeyboard();
    final reps = liveRepsField(setId);
    await ensureFullyInSafeViewport(live, reps);
    await enterFocused(reps, '8');
    await dismissKeyboard();
    final confirm = find.byKey(ValueKey('confirm-$setId'));
    await ensureFullyInSafeViewport(live, confirm);
    await tester.tap(confirm.hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final runtime = await repository.readActiveStrengthSession();
    expect(runtime, isA<ActiveStrengthSession>());
    final recorded = (runtime as ActiveStrengthSession).recorded.single;
    expect(recorded.plannedSetId, setId);
    expect(recorded.reps, 8);
    expect(recorded.loadKg, 20);
    expect(recorded.load, isNotNull);
    expect(recorded.load!.value, 10);
    expect(recorded.load!.unit, ExerciseLoadUnit.kg);
    expect(recorded.load!.deviceCount, 2);
    expect(recorded.load!.basis, ExerciseLoadBasis.perDevice);
  }

  var mixedRepo = await loadRepo();
  var mixedSaved = await mixedUnitsPlan(mixedRepo);
  await mountNamedLive(
    repository: mixedRepo,
    template: mixedSaved,
    label: 'Kurzhantel-Curl',
  );
  await confirmPerDeviceFirst(mixedRepo, setId: 'set-mix-kg1');
  expect(find.text('LAST'), findsOneWidget);
  expect(find.text('je Hantel · Wdh. je Seite'), findsOneWidget);
  final lbLoad = liveLoadField('set-mix-lb');
  await ensureFullyInSafeViewport(find.byType(OpenBandStrengthLive), lbLoad);
  expect(tester.widget<TextField>(lbLoad).controller!.text, '22');
  expect(
    tester.widget<TextField>(liveRepsField('set-mix-lb')).controller!.text,
    '8',
  );
  await h.capture('custom-load-mixed-units');

  mixedRepo = await loadRepo();
  mixedSaved = await mixedUnitsPlan(mixedRepo);
  await mountNamedLive(
    repository: mixedRepo,
    template: mixedSaved,
    label: 'Kurzhantel-Curl',
    brightness: Brightness.dark,
  );
  await confirmPerDeviceFirst(mixedRepo, setId: 'set-mix-kg1');
  expect(find.text('LAST'), findsOneWidget);
  expect(find.text('je Hantel · Wdh. je Seite'), findsOneWidget);
  expect(
    tester.widget<TextField>(liveLoadField('set-mix-lb')).controller!.text,
    '22',
  );
  await h.capture('custom-load-mixed-units-dark');

  Future<WorkoutTemplate> mixedBasisPlan(
    _CustomExerciseReviewRepo repository,
  ) async {
    final definition = await curlSnapshot(repository);
    final saved = await writePlan(
      repository,
      curlPlan(
        id: 'tpl-mixed-basis',
        definition: definition,
        sets: [
          planned(id: 'set-basis-device', reps: 8, load: kg10),
          planned(id: 'set-basis-legacy', reps: 8, loadKg: 20),
          planned(id: 'set-basis-kg2', reps: 8, load: kg10),
        ],
      ),
    );
    final sets = saved.exercises.single.sets;
    expect(sets, hasLength(3));
    expect(sets[0].loadKg, 20);
    expect(sets[0].load!.basis, ExerciseLoadBasis.perDevice);
    expect(sets[0].load!.value, 10);
    expect(sets[0].load!.deviceCount, 2);
    expect(sets[1].load, isNull);
    expect(sets[1].loadKg, 20);
    expect(sets[2].loadKg, 20);
    expect(sets[2].load!.value, 10);
    expect(sets[2].load!.basis, ExerciseLoadBasis.perDevice);
    return saved;
  }

  var basisRepo = await loadRepo();
  var basisSaved = await mixedBasisPlan(basisRepo);
  await mountNamedLive(
    repository: basisRepo,
    template: basisSaved,
    label: 'Kurzhantel-Curl',
  );
  await confirmPerDeviceFirst(basisRepo, setId: 'set-basis-device');
  expect(find.text('kg je Hantel · Wdh. je Seite'), findsNothing);
  expect(find.text('je Hantel · Wdh. je Seite'), findsNWidgets(2));
  expect(find.text('Gesamtgewicht'), findsOneWidget);
  await h.capture('custom-load-mixed-basis');

  basisRepo = await loadRepo();
  basisSaved = await mixedBasisPlan(basisRepo);
  await mountNamedLive(
    repository: basisRepo,
    template: basisSaved,
    label: 'Kurzhantel-Curl',
    brightness: Brightness.dark,
  );
  await confirmPerDeviceFirst(basisRepo, setId: 'set-basis-device');
  expect(find.text('je Hantel · Wdh. je Seite'), findsNWidgets(2));
  expect(find.text('Gesamtgewicht'), findsOneWidget);
  await h.capture('custom-load-mixed-basis-dark');

  Future<void> captureMixedBasisScaled({
    required String name,
    required bool scrolled,
  }) async {
    final scaled = await loadRepo();
    final saved = await mixedBasisPlan(scaled);
    await mountNamedLive(
      repository: scaled,
      template: saved,
      label: 'Kurzhantel-Curl',
      scale: 2,
    );
    await confirmPerDeviceFirst(scaled, setId: 'set-basis-device');
    final live = find.byType(OpenBandStrengthLive);
    final last = find.byKey(const ValueKey('confirm-set-basis-kg2'));
    if (scrolled) {
      await ensureFullyInSafeViewport(live, last);
      expect(rectInSafeViewport(tester.getRect(last)), isTrue);
      expect(find.text('Gesamtgewicht'), findsOneWidget);
      await h.capture(name);
    } else {
      await scrollListToMin(live);
      await expectInSafeViewport(find.text('Kurztraining'));
      expect(find.text('je Hantel · Wdh. je Seite'), findsNWidgets(2));
      await h.capture(name);
    }
  }

  await captureMixedBasisScaled(
    name: 'custom-load-mixed-basis-2x',
    scrolled: false,
  );
  await captureMixedBasisScaled(
    name: 'custom-load-mixed-basis-2x-scrolled',
    scrolled: true,
  );

  Future<WorkoutTemplate> assistancePlan(
    _CustomExerciseReviewRepo repository,
  ) async {
    expect(
      (await repository.createCustomExercise(
        CustomExerciseDraft(
          id: 'custom-assist',
          label: 'Klimmzug unterstützt',
          mode: ExerciseCaptureMode.repetitions,
          equipment: ExerciseEquipmentCategory.machine,
          loadBasis: ExerciseLoadBasis.assistance,
          repetitionBasis: ExerciseRepetitionBasis.total,
          primaryMuscles: const ['back'],
        ),
      )).saved,
      isTrue,
    );
    final definition = (await repository.readExerciseCatalogue())
        .byId('custom-assist')!
        .snapshot();
    final assist = OriginalLoadInput(
      value: 20,
      unit: ExerciseLoadUnit.kg,
      basis: ExerciseLoadBasis.assistance,
      repetitionBasis: ExerciseRepetitionBasis.total,
    );
    expect(resolveStoredLoadKg(input: assist), isNull);
    final saved = await writePlan(
      repository,
      WorkoutTemplate(
        id: 'tpl-assist',
        name: 'Kurztraining',
        version: 1,
        exercises: [
          PlannedExercise(
            id: 'ex-assist',
            exerciseKey: 'custom-assist',
            name: 'Klimmzug unterstützt',
            definition: definition,
            sets: [
              planned(id: 'set-assist-1', reps: 8, load: assist),
              planned(id: 'set-assist-2', reps: 8, load: assist),
              planned(id: 'set-assist-3', reps: 8, load: assist),
            ],
          ),
        ],
        updatedAt: DateTime(2026, 9, 1),
      ),
    );
    final sets = saved.exercises.single.sets;
    expect(sets, hasLength(3));
    for (final set in sets) {
      expect(set.reps, 8);
      expect(set.loadKg, isNull);
      expect(set.load!.basis, ExerciseLoadBasis.assistance);
      expect(set.load!.value, 20);
      expect(resolveStoredLoadKg(input: set.load, loadKg: set.loadKg), isNull);
    }
    return saved;
  }

  Future<void> confirmAssistanceSet(
    _CustomExerciseReviewRepo repository,
    String setId,
  ) async {
    final live = find.byType(OpenBandStrengthLive);
    final load = liveLoadField(setId);
    await ensureFullyInSafeViewport(live, load);
    await enterFocused(load, '20');
    await dismissKeyboard();
    final reps = liveRepsField(setId);
    await ensureFullyInSafeViewport(live, reps);
    await enterFocused(reps, '8');
    await dismissKeyboard();
    expect(find.text('Beide Seiten'), findsNothing);
    final confirm = find.byKey(ValueKey('confirm-$setId'));
    await ensureFullyInSafeViewport(live, confirm);
    await tester.tap(confirm.hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final runtime = await repository.readActiveStrengthSession();
    expect(runtime, isA<ActiveStrengthSession>());
    final recorded = (runtime as ActiveStrengthSession).recorded.last;
    expect(recorded.plannedSetId, setId);
    expect(recorded.reps, 8);
    expect(recorded.loadKg, isNull);
    expect(recorded.load, isNotNull);
    expect(recorded.load!.basis, ExerciseLoadBasis.assistance);
    expect(recorded.load!.value, 20);
    expect(recorded.load!.unit, ExerciseLoadUnit.kg);
    expect(resolveStoredLoadKg(input: recorded.load), isNull);
  }

  Future<void> captureAssistance({
    required String name,
    required Brightness brightness,
  }) async {
    final repo = await loadRepo();
    final saved = await assistancePlan(repo);
    await mountNamedLive(
      repository: repo,
      template: saved,
      label: 'Klimmzug unterstützt',
      brightness: brightness,
    );
    expect(find.text('kg Unterstützung'), findsOneWidget);
    expect(find.text('Beide Seiten'), findsNothing);
    expect(find.text('LAST'), findsNothing);
    await confirmAssistanceSet(repo, 'set-assist-1');
    expect(
      ((await repo.readActiveStrengthSession()) as ActiveStrengthSession)
          .recorded,
      hasLength(1),
    );
    expect(find.byKey(const ValueKey('confirm-set-assist-2')), findsOneWidget);
    await h.capture(name);
  }

  await captureAssistance(
    name: 'custom-load-assistance',
    brightness: Brightness.light,
  );
  await captureAssistance(
    name: 'custom-load-assistance-dark',
    brightness: Brightness.dark,
  );
}
