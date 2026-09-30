part of 'harness.dart';

Future<void> reviewGlucose(ReviewHarness h) async {
  final tester = h.tester;
  final now = DateTime(2026, 9, 15, 9, 41);
  const sourceKey = SyntheticOpenBandRepository.glucoseFixtureSourceKey;

  Future<_GlucoseReviewRepo> loadRepo() async {
    Future<Map> load(String name) async =>
        jsonDecode(
              await rootBundle.loadString(
                'docs/openband5/assets/fixtures/$name.json',
              ),
            )
            as Map;
    final repo = _GlucoseReviewRepo(
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

  Future<void> pumpUntil(bool Function() ready, String message) async {
    await tester.pump();
    var waited = 0;
    while (!ready()) {
      if (++waited > 80) throw FlutterError(message);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await reviewPumpPageTransitions(tester);
  }

  Future<void> pumpSheet() async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<OpenBandController> mountHealth({
    required _GlucoseReviewRepo repository,
    Brightness brightness = Brightness.light,
    double scale = 1,
  }) async {
    final controller = OpenBandController(
      repository: repository,
      initialDay: '2026-09-15',
      band: repository.band,
      now: () => now,
    );
    await controller.refresh();
    await tester.pumpWidget(
      reviewHost(
        brightness: brightness,
        scale: scale,
        home: Scaffold(
          body: SafeArea(child: OpenBandHealth(controller: controller)),
        ),
      ),
    );
    await pumpUntil(
      () =>
          find.byType(OpenBandHealth).evaluate().isNotEmpty &&
          find.text('Gesundheit').evaluate().isNotEmpty &&
          !controller.loading,
      'Health did not finish loading.',
    );
    return controller;
  }

  Future<void> openGlucoseFromHealth() async {
    final entry = find.byKey(const ValueKey('glukose'));
    final health = find.byType(OpenBandHealth);
    await ensureFullyInSafeViewport(health, entry);
    expect(entry.hitTestable(), findsOneWidget);
    await tester.tap(entry.hitTestable());
    await reviewPumpPageTransitions(tester);
    await pumpUntil(
      () => find.byType(OpenBandGlucose).evaluate().isNotEmpty,
      'Glucose main did not open.',
    );
  }

  Future<void> popGlucose() async {
    await tester.tap(find.byTooltip('Zurück'));
    await reviewPumpPageTransitions(tester);
    await tester.pump();
  }

  Finder useSwitch() => find.descendant(
    of: find.byKey(const ValueKey('glucose-verwenden')),
    matching: find.byType(CupertinoSwitch),
  );

  Future<void> expectMainFixture({
    required bool excluded,
    bool restoreTop = true,
  }) async {
    final page = find.byType(OpenBandGlucose);
    expect(page, findsOneWidget);
    expect(find.text('Glukose'), findsWidgets);
    if (excluded) {
      expect(find.text('Sensor-App · Ausgeblendet'), findsOneWidget);
      expect(find.text('Sensor-App · Apple Health'), findsNothing);
      expect(find.text('—'), findsWidgets);
      expect(find.text('5,2'), findsNothing);
    } else {
      expect(find.text('5,2'), findsWidgets);
      expect(find.text('mmol/L'), findsWidgets);
      expect(find.text('15. September'), findsOneWidget);
      expect(find.text('08:00'), findsWidgets);
      expect(find.text('Sensor-App · Apple Health'), findsOneWidget);
    }
    await ensureFullyInSafeViewport(
      page,
      find.byKey(const ValueKey('glucose-quelle')),
    );
    await ensureFullyInSafeViewport(
      page,
      find.byKey(const ValueKey('glucose-messungen')),
    );
    expect(find.text('11'), findsOneWidget);
    await ensureFullyInSafeViewport(
      page,
      find.byKey(const ValueKey('glucose-synthetic')),
    );
    expect(find.text('Synthetische Daten'), findsOneWidget);
    if (restoreTop) await scrollListToMin(page);
  }

  Future<void> expectSourceClocks({
    required bool included,
    bool restoreTop = true,
  }) async {
    final page = find.byType(OpenBandGlucoseSource);
    expect(find.text('Quelle'), findsWidgets);
    expect(find.text('Sensor-App'), findsWidgets);
    expect(find.text('Apple Health'), findsWidgets);
    final measured = find.text('15. Sep., 08:00');
    final imported = find.text('15. Sep., 09:40');
    final queried = find.text('15. Sep., 09:41');
    await ensureFullyInSafeViewport(page, measured);
    expect(measured, findsOneWidget);
    await ensureFullyInSafeViewport(page, imported);
    expect(imported, findsOneWidget);
    await ensureFullyInSafeViewport(page, queried);
    expect(queried, findsOneWidget);
    final useLabel = find.text('Verwenden');
    await ensureFullyInSafeViewport(page, useLabel);
    expect(useLabel, findsOneWidget);
    final sw = useSwitch();
    await ensureFullyInSafeViewport(page, sw);
    expect(sw.hitTestable(), findsOneWidget);
    expect(
      tester.widget<CupertinoSwitch>(sw).value,
      included ? isTrue : isFalse,
    );
    await ensureFullyInSafeViewport(
      page,
      find.byKey(const ValueKey('glucose-lesen')),
    );
    expect(find.text('Jetzt lesen'), findsOneWidget);
    await ensureFullyInSafeViewport(
      page,
      find.byKey(const ValueKey('glucose-synthetic')),
    );
    expect(find.text('Synthetische Daten'), findsOneWidget);
    if (restoreTop) await scrollListToMin(page);
  }

  Future<void> expectHistoryFixture({bool restoreTop = true}) async {
    final page = find.byType(OpenBandGlucoseHistory);
    expect(find.text('Messungen'), findsWidgets);
    expect(find.text('07:25'), findsNothing);
    expect(find.text('07:30'), findsNothing);
    final eight = find.text('08:00');
    await ensureFullyInSafeViewport(page, eight);
    expect(eight, findsWidgets);
    final mmol = find.textContaining('mmol/L');
    await ensureFullyInSafeViewport(page, mmol.first);
    expect(mmol, findsWidgets);
    await ensureFullyInSafeViewport(
      page,
      find.byKey(const ValueKey('glucose-synthetic')),
    );
    expect(find.text('Synthetische Daten'), findsOneWidget);
    if (restoreTop) await scrollListToMin(page);
  }

  Future<void> openSource() async {
    final row = find.byKey(const ValueKey('glucose-quelle'));
    await ensureFullyInSafeViewport(find.byType(OpenBandGlucose), row);
    await tester.tap(row.hitTestable());
    await reviewPumpPageTransitions(tester);
    await pumpUntil(
      () => find.byType(OpenBandGlucoseSource).evaluate().isNotEmpty,
      'Glucose source did not open.',
    );
  }

  Future<void> openHistory() async {
    final row = find.byKey(const ValueKey('glucose-messungen'));
    await ensureFullyInSafeViewport(find.byType(OpenBandGlucose), row);
    await tester.tap(row.hitTestable());
    await reviewPumpPageTransitions(tester);
    await pumpUntil(
      () => find.byType(OpenBandGlucoseHistory).evaluate().isNotEmpty,
      'Glucose history did not open.',
    );
  }

  Future<void> toggleUse() async {
    final sw = useSwitch();
    expect(sw, findsOneWidget);
    await tester.tap(sw.hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  // Happy path from Health: main -> source -> exclude -> back ->
  // history -> back -> source -> restore.
  var repo = await loadRepo();
  var snap = await repo.readGlucose();
  expect(snap.history, hasLength(11));
  expect(snap.lastMeasuredAt, DateTime(2026, 9, 15, 8, 0));
  expect(snap.lastImportedAt, DateTime(2026, 9, 15, 9, 40));
  expect(snap.attempt.attemptedAt, DateTime(2026, 9, 15, 9, 41));
  expect(snap.selected?.key, sourceKey);
  var controller = await mountHealth(repository: repo);
  await openGlucoseFromHealth();
  await expectMainFixture(excluded: false);
  await h.capture('glucose-main');

  await openSource();
  await expectSourceClocks(included: true);
  await h.capture('glucose-source');
  await toggleUse();
  expect(tester.widget<CupertinoSwitch>(useSwitch()).value, isFalse);
  expect((await repo.readGlucose()).selectedExcluded, isTrue);
  await h.capture('glucose-source-excluded');
  await popGlucose();
  await expectMainFixture(excluded: true);
  expect((await repo.readGlucose()).history, hasLength(11));
  await h.capture('glucose-main-excluded');

  await openHistory();
  await expectHistoryFixture();
  await h.capture('glucose-history');
  await popGlucose();

  await openSource();
  expect(tester.widget<CupertinoSwitch>(useSwitch()).value, isFalse);
  await toggleUse();
  expect(tester.widget<CupertinoSwitch>(useSwitch()).value, isTrue);
  expect((await repo.readGlucose()).selectedExcluded, isFalse);
  await popGlucose();
  await expectMainFixture(excluded: false);

  controller.dispose();

  Future<void> captureMain({
    required String name,
    required Brightness brightness,
    double scale = 1,
    bool excluded = false,
    bool scrolled = false,
  }) async {
    final r = await loadRepo();
    if (excluded) {
      await r.setGlucoseSourceIncluded(sourceKey, included: false);
    }
    final c = await mountHealth(
      repository: r,
      brightness: brightness,
      scale: scale,
    );
    await openGlucoseFromHealth();
    await expectMainFixture(excluded: excluded, restoreTop: !scrolled);
    final page = find.byType(OpenBandGlucose);
    if (scrolled) {
      final row = find.byKey(const ValueKey('glucose-messungen'));
      await ensureFullyInSafeViewport(page, row);
      expect(row.hitTestable(), findsOneWidget);
      expect(find.text('11'), findsOneWidget);
      await h.capture(name);
    } else {
      await expectInSafeViewport(find.text('Glukose'));
      await h.capture(name);
    }
    c.dispose();
  }

  Future<void> captureSource({
    required String name,
    required Brightness brightness,
    double scale = 1,
    bool excluded = false,
    bool scrolled = false,
  }) async {
    final r = await loadRepo();
    if (excluded) {
      await r.setGlucoseSourceIncluded(sourceKey, included: false);
    }
    final c = await mountHealth(
      repository: r,
      brightness: brightness,
      scale: scale,
    );
    await openGlucoseFromHealth();
    await openSource();
    await expectSourceClocks(included: !excluded, restoreTop: !scrolled);
    final page = find.byType(OpenBandGlucoseSource);
    if (scrolled) {
      final read = find.byKey(const ValueKey('glucose-lesen'));
      await ensureFullyInSafeViewport(page, read);
      expect(read.hitTestable(), findsOneWidget);
      await h.capture(name);
    } else {
      await h.capture(name);
    }
    c.dispose();
  }

  Future<void> captureHistory({
    required String name,
    required Brightness brightness,
    double scale = 1,
    bool scrolled = false,
  }) async {
    final r = await loadRepo();
    final c = await mountHealth(
      repository: r,
      brightness: brightness,
      scale: scale,
    );
    await openGlucoseFromHealth();
    await openHistory();
    await expectHistoryFixture(restoreTop: !scrolled);
    final page = find.byType(OpenBandGlucoseHistory);
    if (scrolled) {
      final note = find.byKey(const ValueKey('glucose-synthetic'));
      await ensureFullyInSafeViewport(page, note);
      expect(note.hitTestable(), findsOneWidget);
      await h.capture(name);
    } else {
      await h.capture(name);
    }
    c.dispose();
  }

  await captureMain(name: 'glucose-main-dark', brightness: Brightness.dark);
  await captureSource(name: 'glucose-source-dark', brightness: Brightness.dark);
  await captureHistory(
    name: 'glucose-history-dark',
    brightness: Brightness.dark,
  );
  await captureMain(
    name: 'glucose-main-excluded-dark',
    brightness: Brightness.dark,
    excluded: true,
  );
  await captureSource(
    name: 'glucose-source-excluded-dark',
    brightness: Brightness.dark,
    excluded: true,
  );

  // Empty stored + empty query is not access denied.
  repo = await loadRepo();
  repo.clearGlucoseReadings();
  controller = await mountHealth(repository: repo);
  await openGlucoseFromHealth();
  expect(find.text('Keine Werte gespeichert'), findsOneWidget);
  expect(find.text('Jetzt lesen'), findsOneWidget);
  expect(find.text('Kein Zugriff'), findsNothing);
  await h.capture('glucose-empty');
  repo.emptyGlucoseImport = true;
  await tester.tap(find.byKey(const ValueKey('glucose-lesen')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.text('Keine Werte gelesen'), findsOneWidget);
  expect(find.text('Kein Zugriff'), findsNothing);
  await h.capture('glucose-empty-query');
  controller.dispose();

  repo = await loadRepo();
  repo.clearGlucoseReadings();
  controller = await mountHealth(repository: repo, brightness: Brightness.dark);
  await openGlucoseFromHealth();
  expect(find.text('Keine Werte gespeichert'), findsOneWidget);
  await h.capture('glucose-empty-dark');
  controller.dispose();

  // Explicit read failure retains stored hero.
  repo = await loadRepo();
  repo.failGlucoseImport = true;
  repo.glucoseImportFailureStatus = HealthMeasurementImportStatus.readFailed;
  controller = await mountHealth(repository: repo);
  await openGlucoseFromHealth();
  await openSource();
  await tester.tap(find.byKey(const ValueKey('glucose-lesen')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.text('Lesen fehlgeschlagen'), findsOneWidget);
  expect(find.text('15. Sep., 08:00'), findsOneWidget);
  await popGlucose();
  expect(find.text('Lesen fehlgeschlagen'), findsOneWidget);
  expect(find.text('5,2'), findsWidgets);
  await h.capture('glucose-failure');
  controller.dispose();

  repo = await loadRepo();
  repo.failGlucoseImport = true;
  repo.glucoseImportFailureStatus = HealthMeasurementImportStatus.readFailed;
  controller = await mountHealth(repository: repo, brightness: Brightness.dark);
  await openGlucoseFromHealth();
  await openSource();
  await tester.tap(find.byKey(const ValueKey('glucose-lesen')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await popGlucose();
  expect(find.text('Lesen fehlgeschlagen'), findsOneWidget);
  expect(find.text('5,2'), findsWidgets);
  await h.capture('glucose-failure-dark');
  controller.dispose();

  // Initial store-read error and retry.
  repo = await loadRepo();
  repo.failGlucoseReads = true;
  controller = await mountHealth(repository: repo);
  await openGlucoseFromHealth();
  expect(find.text('Lesen fehlgeschlagen'), findsOneWidget);
  expect(find.text('5,2'), findsNothing);
  await h.capture('glucose-store-error');
  repo.failGlucoseReads = false;
  await tester.tap(find.widgetWithText(OBAction, 'Erneut'));
  await pumpUntil(
    () => find.text('5,2').evaluate().isNotEmpty,
    'Store-read retry did not restore glucose.',
  );
  expect(find.text('Lesen fehlgeschlagen'), findsNothing);
  await h.capture('glucose-store-error-retry');
  controller.dispose();

  repo = await loadRepo();
  repo.failGlucoseReads = true;
  controller = await mountHealth(repository: repo, brightness: Brightness.dark);
  await openGlucoseFromHealth();
  expect(find.text('Lesen fehlgeschlagen'), findsOneWidget);
  expect(find.text('5,2'), findsNothing);
  await h.capture('glucose-store-error-dark');
  controller.dispose();

  // Import refreshFailed keeps stored snapshot (nullable result.snapshot).
  repo = await loadRepo();
  controller = await mountHealth(repository: repo);
  await openGlucoseFromHealth();
  await expectMainFixture(excluded: false);
  await openSource();
  repo.failGlucoseReads = true;
  await tester.tap(find.byKey(const ValueKey('glucose-lesen')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await popGlucose();
  expect(find.text('5,2'), findsWidgets);
  expect(find.text('Lesen fehlgeschlagen'), findsOneWidget);
  expect(find.text('Keine Werte gespeichert'), findsNothing);
  await h.capture('glucose-refresh-failed');
  controller.dispose();

  repo = await loadRepo();
  controller = await mountHealth(repository: repo, brightness: Brightness.dark);
  await openGlucoseFromHealth();
  await openSource();
  repo.failGlucoseReads = true;
  await tester.tap(find.byKey(const ValueKey('glucose-lesen')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await popGlucose();
  expect(find.text('5,2'), findsWidgets);
  expect(find.text('Lesen fehlgeschlagen'), findsOneWidget);
  await h.capture('glucose-refresh-failed-dark');
  controller.dispose();

  // Partial import copy.
  repo = await loadRepo()
    ..partialGlucose = true;
  controller = await mountHealth(repository: repo);
  await openGlucoseFromHealth();
  expect(find.text('Teilweise lesbar'), findsOneWidget);
  expect(find.text('5,2'), findsWidgets);
  await h.capture('glucose-partial');
  controller.dispose();
  repo = await loadRepo()
    ..partialGlucose = true;
  controller = await mountHealth(repository: repo, brightness: Brightness.dark);
  await openGlucoseFromHealth();
  expect(find.text('Teilweise lesbar'), findsOneWidget);
  await h.capture('glucose-partial-dark');
  controller.dispose();

  Future<void> captureInfo({
    required String name,
    required Brightness brightness,
    double scale = 1,
    bool scrolled = false,
  }) async {
    final r = await loadRepo();
    final c = await mountHealth(
      repository: r,
      brightness: brightness,
      scale: scale,
    );
    await openGlucoseFromHealth();
    await tester.tap(find.byTooltip('Glukosewerte'));
    await pumpSheet();
    expect(find.text('Glukosewerte'), findsWidgets);
    expect(
      find.text(
        'Messwerte aus Apple Health, getrennt nach Quelle. OpenBand misst Glukose nicht.',
      ),
      findsOneWidget,
    );
    if (scrolled) {
      final body = find.byKey(const ValueKey('journal-info-body'));
      await tester.drag(body, const Offset(0, -64));
      await tester.pump();
    }
    await h.capture(name);
    await tester.tap(find.byTooltip('Schließen'));
    await pumpSheet();
    expect(find.text('Glukosewerte'), findsNothing);
    c.dispose();
  }

  await captureInfo(name: 'glucose-info', brightness: Brightness.light);
  await captureInfo(name: 'glucose-info-dark', brightness: Brightness.dark);
  await captureInfo(
    name: 'glucose-info-2x',
    brightness: Brightness.light,
    scale: 2,
    scrolled: true,
  );

  // Toggle write failure retains switch state until retry.
  repo = await loadRepo();
  repo.failGlucoseExclusionWrite = true;
  controller = await mountHealth(repository: repo);
  await openGlucoseFromHealth();
  await openSource();
  await toggleUse();
  expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
  expect(tester.widget<CupertinoSwitch>(useSwitch()).value, isTrue);
  expect((await repo.readGlucose()).selectedExcluded, isFalse);
  await h.capture('glucose-toggle-error');
  repo.failGlucoseExclusionWrite = false;
  await tester.tap(find.widgetWithText(OBAction, 'Erneut'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(tester.widget<CupertinoSwitch>(useSwitch()).value, isFalse);
  controller.dispose();

  await captureMain(
    name: 'glucose-main-2x',
    brightness: Brightness.light,
    scale: 2,
  );
  await captureMain(
    name: 'glucose-main-2x-scrolled',
    brightness: Brightness.light,
    scale: 2,
    scrolled: true,
  );
  await captureMain(
    name: 'glucose-main-2x-dark',
    brightness: Brightness.dark,
    scale: 2,
  );
  await captureSource(
    name: 'glucose-source-2x',
    brightness: Brightness.light,
    scale: 2,
  );
  await captureSource(
    name: 'glucose-source-2x-scrolled',
    brightness: Brightness.light,
    scale: 2,
    scrolled: true,
  );
  await captureSource(
    name: 'glucose-source-2x-dark',
    brightness: Brightness.dark,
    scale: 2,
  );
  await captureHistory(
    name: 'glucose-history-2x',
    brightness: Brightness.light,
    scale: 2,
  );
  await captureHistory(
    name: 'glucose-history-2x-scrolled',
    brightness: Brightness.light,
    scale: 2,
    scrolled: true,
  );
}
