part of 'harness.dart';

Future<void> reviewCycleMeasurements(ReviewHarness h) async {
  final tester = h.tester;
  final now = DateTime(2026, 9, 15, 9, 41);
  const day = SyntheticOpenBandRepository.cycleFixtureDay;

  Future<_CycleReviewRepo> loadRepo() async {
    Future<Map> load(String name) async =>
        jsonDecode(
              await rootBundle.loadString(
                'docs/openband5/assets/fixtures/$name.json',
              ),
            )
            as Map;
    final repo = _CycleReviewRepo(
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

  Future<void> ensureFullyInSafeViewport(Finder ancestor, Finder target) async {
    await revealIn(ancestor, target);
    final scrollable = downScrollable(ancestor).first;
    var extra = 0;
    while (!rectInSafeViewport(tester.getRect(target), contentOf: ancestor)) {
      if (extra >= 32) {
        throw FlutterError('Control is not fully within the safe viewport.');
      }
      final box = tester.getRect(target);
      final safe = reviewSafeViewport(contentOf: ancestor);
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

  Future<void> pumpAfterTap() async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await reviewPumpPageTransitions(tester);
  }

  Future<void> popRoute() async {
    await tester.tap(find.byTooltip('Zurück'));
    await reviewPumpPageTransitions(tester);
    await tester.pump();
  }

  Future<void> tapVisible(Finder target, Finder ancestor) async {
    await ensureFullyInSafeViewport(ancestor, target);
    await tester.tap(target.hitTestable());
    await pumpAfterTap();
  }

  Finder cyclePage() => find.byKey(const ValueKey('cycle-overview'));
  Finder measurementsPage() => find.byKey(const ValueKey('cycle-measurements'));
  Finder rhrPlot() => find.byKey(const ValueKey('cycle-measurements-rhr-plot'));
  Finder hrvPlot() => find.byKey(const ValueKey('cycle-measurements-hrv-plot'));
  Finder pickerRow() => find.byKey(const ValueKey('cycle-measurements-picker'));

  Finder inRoute(Finder ancestor, Finder matching) =>
      find.descendant(of: ancestor, matching: matching);

  Finder infoButton() =>
      inRoute(measurementsPage(), find.byTooltip('Information'));

  Finder metricCard(Finder plot) =>
      find.ancestor(of: plot, matching: find.byType(OBCard)).first;

  Finder measurementsChoiceSheet() {
    final byStart = find.byType(OBSettingsChoiceSheet<String>);
    if (byStart.evaluate().isNotEmpty) return byStart;
    return find.byType(OBSettingsChoiceSheet<CycleMeasurementPeriod>);
  }

  CycleNightSourceRow nightSource({
    required String onDay,
    double? rhr,
    double? hrv,
    double? rhrConfidence,
    double? hrvConfidence,
    bool unreadable = false,
  }) => CycleNightSourceRow(
    day: onDay,
    algoVersion: kAlgoVersion,
    payloadUnreadable: unreadable,
    payload: unreadable
        ? null
        : cycleNightSourcePayload(
            rhr: rhr,
            hrv: hrv,
            rhrConfidence: rhrConfidence,
            hrvConfidence: hrvConfidence,
            onsetMs: cycleNightOnsetMs(onDay),
            offsetMs: cycleNightOffsetMs(onDay),
          ),
  );

  Finder infoBody() => find.byKey(const ValueKey('journal-info-body'));
  Finder infoClose() => find.widgetWithText(OBAction, 'Schließen');
  Finder inInfo(String text) =>
      find.descendant(of: infoBody(), matching: find.textContaining(text));

  Future<void> expectInfoClosePinned() async {
    expect(infoClose().hitTestable(), findsOneWidget);
    expect(rectInSafeViewport(tester.getRect(infoClose())), isTrue);
  }

  Future<void> revealInfoText(Finder target) async {
    final body = infoBody();
    expect(body, findsOneWidget);
    var drags = 0;
    while (target.evaluate().isEmpty ||
        target.hitTestable().evaluate().isEmpty) {
      if (++drags > 24) {
        throw FlutterError(
          'Info source text is not hit-testable after production scrolling.',
        );
      }
      await tester.drag(body, const Offset(0, -64));
      await tester.pump();
      await expectInfoClosePinned();
    }
    expect(target.hitTestable(), findsOneWidget);
    await expectInfoClosePinned();
  }

  Future<void> expectGenericInfoParas() async {
    expect(
      find.text(
        'Ruhepuls und HRV stammen aus gespeicherten Nächten. Das Datum gehört zur jeweiligen Nacht.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Die HRV zeigt die RMSSD der Schlafsitzung. Fehlende oder neu zu berechnende Werte bleiben als Lücke sichtbar.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Die Werte bestimmen weder eine Zyklusphase noch einen Eisprung.',
      ),
      findsOneWidget,
    );
    expect(inInfo('%'), findsNothing);
    expect(inInfo('Genauigkeit'), findsNothing);
  }

  Future<void> expectDefaultSourceDisclosure() async {
    await expectGenericInfoParas();
    await revealInfoText(inInfo('Ruhepuls · 15. Sept.'));
    expect(inInfo('Ruhepuls · 15. Sept.'), findsOneWidget);
    expect(inInfo('14. Sept., 16:00–15. Sept., 06:00 UTC'), findsOneWidget);
    await revealInfoText(inInfo('HRV · 14. Sept.'));
    expect(inInfo('HRV · 14. Sept.'), findsOneWidget);
    expect(inInfo('13. Sept., 16:00–14. Sept., 06:00 UTC'), findsOneWidget);
    expect(inInfo('Qualitätswert —'), findsWidgets);
    expect(
      inInfo('Qualitätswerte sind gespeicherte Scores, keine Fehlerspannen.'),
      findsOneWidget,
    );
    expect(inInfo('Qualitätswert 0,90 / 1'), findsNothing);
    await expectInfoClosePinned();
  }

  Future<_CycleReviewRepo> mountCycle({
    Brightness brightness = Brightness.light,
    double scale = 1,
    _CycleReviewRepo? repository,
    String? onDay,
  }) async {
    final repo = repository ?? await loadRepo();
    await tester.pumpWidget(
      reviewHost(
        brightness: brightness,
        scale: scale,
        home: OpenBandCycle(
          repository: repo,
          day: onDay ?? day,
          now: () => now,
          synthetic: true,
        ),
      ),
    );
    await pumpUntil(
      () =>
          cyclePage().evaluate().isNotEmpty ||
          find.text('Daten nicht geladen').evaluate().isNotEmpty,
      'Cycle main did not load.',
    );
    return repo;
  }

  Future<_CycleReviewRepo> mountMeasurements({
    Brightness brightness = Brightness.light,
    double scale = 1,
    _CycleReviewRepo? repository,
    String? onDay,
  }) async {
    final repo = repository ?? await loadRepo();
    await tester.pumpWidget(
      reviewHost(
        brightness: brightness,
        scale: scale,
        home: OpenBandCycleMeasurements(
          repository: repo,
          day: onDay ?? day,
          now: () => now,
          synthetic: true,
        ),
      ),
    );
    await pumpUntil(
      () => measurementsPage().evaluate().isNotEmpty,
      'Cycle measurements did not load.',
    );
    return repo;
  }

  Future<void> openMeasurementsFromCycle() async {
    await tapVisible(inRoute(cyclePage(), find.text('Messwerte')), cyclePage());
    await pumpUntil(
      () => measurementsPage().evaluate().isNotEmpty,
      'Measurements did not open from cycle.',
    );
    expect(measurementsPage(), findsOneWidget);
  }

  Future<void> expectPopulatedMain() async {
    final page = measurementsPage();
    expect(inRoute(page, find.text('Messwerte')), findsOneWidget);
    expect(inRoute(page, find.text('Zyklus')), findsOneWidget);
    expect(inRoute(page, find.text('24. Aug.–15. Sept.')), findsOneWidget);
    expect(inRoute(page, find.text('Ruhepuls')), findsOneWidget);
    expect(inRoute(page, find.text('HRV')), findsOneWidget);
    expect(inRoute(page, find.text('19 von 23 Nächten')), findsOneWidget);
    expect(inRoute(page, find.text('16 von 23 Nächten')), findsOneWidget);
    expect(rhrPlot(), findsOneWidget);
    expect(hrvPlot(), findsOneWidget);
    expect(inRoute(metricCard(rhrPlot()), find.text('54')), findsOneWidget);
    expect(inRoute(metricCard(rhrPlot()), find.text('bpm')), findsOneWidget);
    expect(
      inRoute(metricCard(rhrPlot()), find.text('15. Sept.')),
      findsOneWidget,
    );
    expect(inRoute(metricCard(hrvPlot()), find.text('48')), findsOneWidget);
    expect(inRoute(metricCard(hrvPlot()), find.text('ms')), findsOneWidget);
    expect(
      inRoute(metricCard(hrvPlot()), find.text('14. Sept.')),
      findsOneWidget,
    );
    expect(inRoute(page, find.text('Tag 1')), findsWidgets);
    expect(inRoute(page, find.text('Tag 23')), findsWidgets);
    expect(inRoute(page, find.text('Synthetische Daten')), findsOneWidget);
  }

  Future<void> expectPeriodSelected(String label) async {
    final sheet = measurementsChoiceSheet();
    expect(sheet, findsOneWidget);
    final rows = tester
        .widgetList<OBSettingsChoiceRow>(
          find.descendant(
            of: sheet,
            matching: find.byType(OBSettingsChoiceRow),
          ),
        )
        .toList();
    expect(rows, isNotEmpty);
    for (final row in rows) {
      if (row.label == label) {
        expect(row.selected, isTrue);
      } else {
        expect(row.selected, isFalse);
      }
    }
  }

  double plotLeftInset(Finder plot) {
    final scaler = MediaQuery.textScalerOf(tester.element(plot));
    return scaler.scale(14) > 20 ? 44.0 : 26.0;
  }

  Offset plotSlotOffset(Finder plot, int slot, int count) {
    final box = tester.getRect(plot);
    final left = plotLeftInset(plot);
    const right = 4.0;
    final usable = box.width - left - right;
    expect(usable, greaterThan(8.0));
    final x = count <= 1
        ? box.left + left + usable / 2
        : box.left + left + slot * usable / (count - 1);
    final point = Offset(x, box.center.dy);
    expect(box.contains(point), isTrue);
    return point;
  }

  Future<void> tapPlotSlot(Finder plot, int slot, int count) async {
    await ensureFullyInSafeViewport(measurementsPage(), plot);
    await tester.tapAt(plotSlotOffset(plot, slot, count));
    await tester.pump();
  }

  Future<void> dragPlotSlot(
    Finder plot,
    int fromSlot,
    int toSlot,
    int count,
  ) async {
    await ensureFullyInSafeViewport(measurementsPage(), plot);
    final from = plotSlotOffset(plot, fromSlot, count);
    final to = plotSlotOffset(plot, toSlot, count);
    await tester.timedDragFrom(
      from,
      to - from,
      const Duration(milliseconds: 280),
    );
    await tester.pump();
  }

  Future<void> expectSelectedGap(Finder plot) async {
    final card = metricCard(plot);
    expect(inRoute(card, find.text('29. Aug.')), findsOneWidget);
    expect(inRoute(card, find.text('—')), findsOneWidget);
    expect(inRoute(card, find.text('15. Sept.')), findsNothing);
    expect(inRoute(card, find.text('14. Sept.')), findsNothing);
  }

  // Root navigation to measurements and back.
  var repo = await loadRepo();
  await mountCycle(repository: repo);
  await ensureFullyInSafeViewport(
    cyclePage(),
    inRoute(cyclePage(), find.text('Messwerte')),
  );
  expect(
    tester.getTopLeft(inRoute(cyclePage(), find.text('Messwerte'))).dy,
    lessThan(tester.getTopLeft(inRoute(cyclePage(), find.text('Verlauf'))).dy),
  );
  await h.capture('cycle-measurements-root');
  await openMeasurementsFromCycle();
  await expectPopulatedMain();
  await scrollListToMin(measurementsPage());
  await h.capture('cycle-measurements-main');
  await popRoute();
  await pumpUntil(
    () => cyclePage().evaluate().isNotEmpty,
    'Cycle did not return from measurements.',
  );
  expect(measurementsPage(), findsNothing);
  expect(inRoute(cyclePage(), find.text('Messwerte')), findsOneWidget);
  expect(inRoute(cyclePage(), find.text('Verlauf')), findsOneWidget);
  await h.capture('cycle-measurements-root-back');

  repo = await loadRepo();
  await mountMeasurements(repository: repo, brightness: Brightness.dark);
  await expectPopulatedMain();
  await h.capture('cycle-measurements-main-dark');

  // Picker + actual prior-cycle selection (empty is correct).
  repo = await loadRepo();
  await mountMeasurements(repository: repo);
  await tapVisible(pickerRow(), measurementsPage());
  expect(measurementsChoiceSheet(), findsOneWidget);
  await expectPeriodSelected('24. Aug.–15. Sept.');
  expect(find.text('31. Juli–23. Aug.'), findsOneWidget);
  expect(find.text('29. Juni–30. Juli'), findsOneWidget);
  expect(find.text('1.–28. Juni'), findsOneWidget);
  await h.capture('cycle-measurements-picker');
  await tester.tap(find.text('31. Juli–23. Aug.'));
  await pumpAfterTap();
  expect(measurementsChoiceSheet(), findsNothing);
  expect(
    inRoute(measurementsPage(), find.text('31. Juli–23. Aug.')),
    findsOneWidget,
  );
  expect(
    inRoute(measurementsPage(), find.text('0 von 24 Nächten')),
    findsWidgets,
  );
  expect(inRoute(measurementsPage(), find.text('—')), findsWidgets);
  expect(rhrPlot(), findsNothing);
  expect(hrvPlot(), findsNothing);
  await h.capture('cycle-measurements-prior');

  repo = await loadRepo();
  await mountMeasurements(repository: repo, brightness: Brightness.dark);
  await tapVisible(pickerRow(), measurementsPage());
  await expectPeriodSelected('24. Aug.–15. Sept.');
  expect(find.text('31. Juli–23. Aug.').hitTestable(), findsOneWidget);
  await h.capture('cycle-measurements-picker-dark');
  await tester.tap(find.text('24. Aug.–15. Sept.').last);
  await pumpAfterTap();

  // Info open/close with independent selected-night source windows.
  repo = await loadRepo();
  await mountMeasurements(repository: repo);
  await tapVisible(infoButton(), measurementsPage());
  expect(find.text('Messwerte'), findsWidgets);
  await expectDefaultSourceDisclosure();
  await h.capture('cycle-measurements-info');
  await tester.tap(infoClose().hitTestable());
  await pumpAfterTap();
  expect(infoClose(), findsNothing);
  await expectPopulatedMain();

  await mountMeasurements(repository: repo, brightness: Brightness.dark);
  await tapVisible(infoButton(), measurementsPage());
  await expectDefaultSourceDisclosure();
  await h.capture('cycle-measurements-info-dark');
  await tester.tap(infoClose().hitTestable());
  await pumpAfterTap();

  repo = await loadRepo();
  repo.seedCycleNightSource(
    nightSource(
      onDay: '2026-09-15',
      rhr: kCyclePaperRhr[22],
      rhrConfidence: 0.9,
    ),
  );
  repo.seedCycleNightSource(
    nightSource(
      onDay: '2026-09-14',
      rhr: kCyclePaperRhr[21],
      hrv: kCyclePaperHrv[21],
      hrvConfidence: 0.9,
    ),
  );
  await mountMeasurements(repository: repo);
  await tapVisible(infoButton(), measurementsPage());
  await expectGenericInfoParas();
  await revealInfoText(inInfo('Ruhepuls · 15. Sept.'));
  expect(inInfo('Ruhepuls · 15. Sept.'), findsOneWidget);
  expect(inInfo('14. Sept., 16:00–15. Sept., 06:00 UTC'), findsOneWidget);
  await revealInfoText(inInfo('HRV · 14. Sept.'));
  expect(inInfo('HRV · 14. Sept.'), findsOneWidget);
  expect(inInfo('13. Sept., 16:00–14. Sept., 06:00 UTC'), findsOneWidget);
  expect(inInfo('Qualitätswert 0,90 / 1'), findsWidgets);
  expect(inInfo('Qualitätswert —'), findsNothing);
  expect(
    inInfo('Qualitätswerte sind gespeicherte Scores, keine Fehlerspannen.'),
    findsOneWidget,
  );
  await expectInfoClosePinned();
  await h.capture('cycle-measurements-info-quality');
  await tester.tap(infoClose().hitTestable());
  await pumpAfterTap();

  // Tap and drag each plot onto the missing 29 Aug slot.
  repo = await loadRepo();
  await mountMeasurements(repository: repo);
  await tapPlotSlot(rhrPlot(), 5, 23);
  await expectSelectedGap(rhrPlot());
  expect(inRoute(metricCard(hrvPlot()), find.text('48')), findsOneWidget);
  await dragPlotSlot(rhrPlot(), 22, 5, 23);
  await expectSelectedGap(rhrPlot());
  await h.capture('cycle-measurements-gap-rhr');
  await tapPlotSlot(hrvPlot(), 5, 23);
  await expectSelectedGap(hrvPlot());
  await expectSelectedGap(rhrPlot());
  await dragPlotSlot(hrvPlot(), 0, 5, 23);
  await expectSelectedGap(hrvPlot());
  await h.capture('cycle-measurements-gap-hrv');
  await tapVisible(infoButton(), measurementsPage());
  await expectGenericInfoParas();
  expect(inInfo('Ruhepuls · 29. Aug.'), findsNothing);
  expect(inInfo('HRV · 29. Aug.'), findsNothing);
  await tester.tap(infoClose().hitTestable());
  await pumpAfterTap();

  repo = await loadRepo();
  await mountMeasurements(repository: repo, brightness: Brightness.dark);
  await tapPlotSlot(rhrPlot(), 5, 23);
  await expectSelectedGap(rhrPlot());
  await tapPlotSlot(hrvPlot(), 5, 23);
  await expectSelectedGap(hrvPlot());
  await h.capture('cycle-measurements-gap-dark');

  // Metric empty.
  repo = await loadRepo();
  repo.clearCycleNightSources();
  await mountMeasurements(repository: repo);
  expect(
    inRoute(measurementsPage(), find.text('0 von 23 Nächten')),
    findsNWidgets(2),
  );
  expect(inRoute(measurementsPage(), find.text('—')), findsWidgets);
  expect(rhrPlot(), findsNothing);
  expect(hrvPlot(), findsNothing);
  await h.capture('cycle-measurements-empty');
  await mountMeasurements(repository: repo, brightness: Brightness.dark);
  expect(
    inRoute(measurementsPage(), find.text('0 von 23 Nächten')),
    findsNWidgets(2),
  );
  await h.capture('cycle-measurements-empty-dark');

  // One-point RHR, HRV absent.
  repo = await loadRepo();
  repo.clearCycleNightSources();
  repo.seedCycleNightSource(nightSource(onDay: '2026-09-15', rhr: 54));
  await mountMeasurements(repository: repo);
  expect(
    inRoute(measurementsPage(), find.text('1 von 23 Nächten')),
    findsOneWidget,
  );
  expect(
    inRoute(measurementsPage(), find.text('0 von 23 Nächten')),
    findsOneWidget,
  );
  expect(rhrPlot(), findsOneWidget);
  expect(inRoute(metricCard(rhrPlot()), find.text('54')), findsOneWidget);
  expect(
    inRoute(metricCard(rhrPlot()), find.text('15. Sept.')),
    findsOneWidget,
  );
  expect(hrvPlot(), findsNothing);
  expect(inRoute(measurementsPage(), find.text('—')), findsOneWidget);
  await h.capture('cycle-measurements-single');
  await mountMeasurements(repository: repo, brightness: Brightness.dark);
  expect(rhrPlot(), findsOneWidget);
  expect(hrvPlot(), findsNothing);
  await h.capture('cycle-measurements-single-dark');

  // Corrupt-row partial banner. Unreadable on a fixture gap night
  // keeps the 19/16 sample counts.
  repo = await loadRepo();
  repo.seedCycleNightSource(nightSource(onDay: '2026-08-29', unreadable: true));
  await mountMeasurements(repository: repo);
  expect(
    inRoute(measurementsPage(), find.text('Daten teilweise lesbar')),
    findsOneWidget,
  );
  await expectPopulatedMain();
  await h.capture('cycle-measurements-partial');
  await mountMeasurements(repository: repo, brightness: Brightness.dark);
  expect(
    inRoute(measurementsPage(), find.text('Daten teilweise lesbar')),
    findsOneWidget,
  );
  await h.capture('cycle-measurements-partial-dark');

  // Read error + retry after clearing the flag.
  repo = await loadRepo();
  repo.failCycleMeasurementsRead = true;
  await mountMeasurements(repository: repo);
  expect(
    inRoute(measurementsPage(), find.text('Daten nicht geladen')),
    findsOneWidget,
  );
  expect(
    inRoute(measurementsPage(), find.text('Erneut versuchen')),
    findsOneWidget,
  );
  expect(rhrPlot(), findsNothing);
  await h.capture('cycle-measurements-read-error');
  final readsBeforeRetry = repo.measurementsReads;
  repo.failCycleMeasurementsRead = false;
  await tester.tap(inRoute(measurementsPage(), find.text('Erneut versuchen')));
  await pumpAfterTap();
  await expectPopulatedMain();
  expect(repo.measurementsReads, greaterThan(readsBeforeRetry));
  await h.capture('cycle-measurements-read-error-retry');
  repo = await loadRepo();
  repo.failCycleMeasurementsRead = true;
  await mountMeasurements(repository: repo, brightness: Brightness.dark);
  expect(
    inRoute(measurementsPage(), find.text('Daten nicht geladen')),
    findsOneWidget,
  );
  await h.capture('cycle-measurements-read-error-dark');

  // Missing start.
  repo = await loadRepo();
  repo.clearCycleLogs();
  await mountCycle(repository: repo);
  await openMeasurementsFromCycle();
  expect(
    inRoute(measurementsPage(), find.text('Kein Zyklusbeginn')),
    findsOneWidget,
  );
  expect(inRoute(measurementsPage(), find.text('Zum Zyklus')), findsOneWidget);
  await h.capture('cycle-measurements-no-start');
  await tester.tap(
    inRoute(measurementsPage(), find.text('Zum Zyklus')).hitTestable(),
  );
  await pumpAfterTap();
  await pumpUntil(
    () => cyclePage().evaluate().isNotEmpty,
    'No-start did not return to cycle.',
  );
  expect(measurementsPage(), findsNothing);
  await mountMeasurements(repository: repo, brightness: Brightness.dark);
  expect(
    inRoute(measurementsPage(), find.text('Kein Zyklusbeginn')),
    findsOneWidget,
  );
  await h.capture('cycle-measurements-no-start-dark');

  // Disabled action opens settings.
  repo = await loadRepo();
  repo.cycleSettings = const CycleSettings(
    enabled: false,
    estimatesEnabled: false,
    lengthReviewEnabled: false,
  );
  await mountMeasurements(repository: repo);
  expect(
    inRoute(measurementsPage(), find.text('Zyklus deaktiviert')),
    findsOneWidget,
  );
  expect(
    inRoute(measurementsPage(), find.text('Einstellungen')),
    findsOneWidget,
  );
  await h.capture('cycle-measurements-disabled');
  await tester.tap(
    inRoute(measurementsPage(), find.text('Einstellungen')).hitTestable(),
  );
  await pumpAfterTap();
  await pumpUntil(
    () => find.byKey(const ValueKey('cycle-settings')).evaluate().isNotEmpty,
    'Disabled action did not open settings.',
  );
  expect(find.byKey(const ValueKey('cycle-settings')), findsOneWidget);
  await h.capture('cycle-measurements-disabled-settings');
  await popRoute();
  await pumpUntil(
    () => measurementsPage().evaluate().isNotEmpty,
    'Settings did not return to measurements.',
  );
  repo = await loadRepo();
  repo.cycleSettings = const CycleSettings(
    enabled: false,
    estimatesEnabled: false,
    lengthReviewEnabled: false,
  );
  await mountMeasurements(repository: repo, brightness: Brightness.dark);
  expect(
    inRoute(measurementsPage(), find.text('Zyklus deaktiviert')),
    findsOneWidget,
  );
  await h.capture('cycle-measurements-disabled-dark');

  // Unreadable starts.
  repo = await loadRepo();
  repo.clearCycleLogs();
  repo.seedUnreadableCycleStart({'date': '2026-08-24', 'kind': 1});
  await mountCycle(repository: repo);
  await openMeasurementsFromCycle();
  expect(
    inRoute(measurementsPage(), find.text('Zyklusbeginn nicht lesbar')),
    findsOneWidget,
  );
  expect(inRoute(measurementsPage(), find.text('Zum Zyklus')), findsOneWidget);
  await h.capture('cycle-measurements-unreadable');
  await tester.tap(
    inRoute(measurementsPage(), find.text('Zum Zyklus')).hitTestable(),
  );
  await pumpAfterTap();
  await pumpUntil(
    () => cyclePage().evaluate().isNotEmpty,
    'Unreadable-start did not return to cycle.',
  );
  expect(measurementsPage(), findsNothing);
  await mountMeasurements(repository: repo, brightness: Brightness.dark);
  expect(
    inRoute(measurementsPage(), find.text('Zyklusbeginn nicht lesbar')),
    findsOneWidget,
  );
  await h.capture('cycle-measurements-unreadable-dark');

  // Removed selected start: pick a start after it is gone so _load
  // keeps that identity and does not silently switch to the current cycle.
  repo = await loadRepo();
  await mountMeasurements(repository: repo);
  await repo.removeCycleStart(
    const CycleStart(date: '2026-07-31', kind: kCycleStartKind),
  );
  await tapVisible(pickerRow(), measurementsPage());
  expect(find.text('31. Juli–23. Aug.'), findsOneWidget);
  await tester.tap(find.text('31. Juli–23. Aug.'));
  await pumpAfterTap();
  await pumpUntil(
    () => find.text('Zyklus nicht mehr vorhanden').evaluate().isNotEmpty,
    'Removed start did not reload a typed reason.',
  );
  expect(
    inRoute(measurementsPage(), find.text('19 von 23 Nächten')),
    findsNothing,
  );
  expect(inRoute(measurementsPage(), find.text('54')), findsNothing);
  expect(find.text('Zyklus nicht mehr vorhanden'), findsOneWidget);
  expect(find.text('Zyklus wählen'), findsOneWidget);
  await h.capture('cycle-measurements-removed');
  await tester.tap(find.text('Zyklus wählen'));
  await pumpAfterTap();
  expect(measurementsChoiceSheet(), findsOneWidget);
  expect(find.text('24. Aug.–15. Sept.'), findsWidgets);
  expect(find.text('31. Juli–23. Aug.'), findsNothing);
  final removedRows = tester
      .widgetList<OBSettingsChoiceRow>(
        find.descendant(
          of: measurementsChoiceSheet(),
          matching: find.byType(OBSettingsChoiceRow),
        ),
      )
      .toList();
  expect(removedRows, isNotEmpty);
  for (final row in removedRows) {
    expect(row.selected, isFalse);
  }
  expect(find.text('24. Aug.–15. Sept.').hitTestable(), findsWidgets);
  await h.capture('cycle-measurements-removed-picker');
  repo = await loadRepo();
  await mountMeasurements(repository: repo, brightness: Brightness.dark);
  await repo.removeCycleStart(
    const CycleStart(date: '2026-07-31', kind: kCycleStartKind),
  );
  await tapVisible(pickerRow(), measurementsPage());
  await tester.tap(find.text('31. Juli–23. Aug.'));
  await pumpAfterTap();
  await pumpUntil(
    () => find.text('Zyklus nicht mehr vorhanden').evaluate().isNotEmpty,
    'Dark removed start did not show typed reason.',
  );
  await h.capture('cycle-measurements-removed-dark');

  // 120-night cap: May 1–Sept 15, Tag 19..138, one sample each.
  repo = await loadRepo();
  repo.clearCycleLogs();
  repo.clearCycleNightSources();
  repo.seedCycleStart(
    const CycleStart(date: '2026-05-01', kind: kCycleStartKind),
  );
  repo.seedCycleNightSource(nightSource(onDay: '2026-09-15', rhr: 54));
  repo.seedCycleNightSource(nightSource(onDay: '2026-09-14', hrv: 48));
  await mountMeasurements(repository: repo);
  expect(
    inRoute(measurementsPage(), find.text('1. Mai–15. Sept.')),
    findsOneWidget,
  );
  expect(
    inRoute(measurementsPage(), find.text('Letzte 120 Nächte')),
    findsOneWidget,
  );
  expect(
    inRoute(measurementsPage(), find.text('1 von 120 Nächten')),
    findsNWidgets(2),
  );
  expect(inRoute(measurementsPage(), find.text('Tag 19')), findsWidgets);
  expect(inRoute(measurementsPage(), find.text('Tag 138')), findsWidgets);
  expect(rhrPlot(), findsOneWidget);
  expect(hrvPlot(), findsOneWidget);
  expect(inRoute(metricCard(rhrPlot()), find.text('54')), findsOneWidget);
  expect(inRoute(metricCard(hrvPlot()), find.text('48')), findsOneWidget);
  await h.capture('cycle-measurements-truncated');
  await mountMeasurements(repository: repo, brightness: Brightness.dark);
  expect(
    inRoute(measurementsPage(), find.text('Letzte 120 Nächte')),
    findsOneWidget,
  );
  expect(inRoute(measurementsPage(), find.text('Tag 19')), findsWidgets);
  expect(inRoute(measurementsPage(), find.text('Tag 138')), findsWidgets);
  await h.capture('cycle-measurements-truncated-dark');

  // 375/2x light/dark main, lower HRV, picker/info safe area.
  repo = await loadRepo();
  await mountMeasurements(repository: repo, scale: 2);
  final main2x = measurementsPage();
  await ensureFullyInSafeViewport(
    main2x,
    inRoute(main2x, find.text('Ruhepuls')),
  );
  await scrollListToMin(main2x);
  await h.capture('cycle-measurements-main-2x');
  await ensureFullyInSafeViewport(main2x, hrvPlot());
  await h.capture('cycle-measurements-main-2x-hrv');
  await tapVisible(pickerRow(), main2x);
  final sheet2x = measurementsChoiceSheet();
  expect(sheet2x, findsOneWidget);
  await ensureFullyInSafeViewport(sheet2x, find.text('1.–28. Juni'));
  expect(
    rectInSafeViewport(
      tester.getRect(find.text('1.–28. Juni')),
      contentOf: sheet2x,
    ),
    isTrue,
  );
  await h.capture('cycle-measurements-picker-2x');
  await tapVisible(inRoute(sheet2x, find.text('24. Aug.–15. Sept.')), sheet2x);
  await tapVisible(infoButton(), measurementsPage());
  await expectGenericInfoParas();
  await expectInfoClosePinned();
  await h.capture('cycle-measurements-info-2x');
  await revealInfoText(inInfo('Ruhepuls · 15. Sept.'));
  await revealInfoText(inInfo('HRV · 14. Sept.'));
  await revealInfoText(
    inInfo('Qualitätswerte sind gespeicherte Scores, keine Fehlerspannen.'),
  );
  expect(inInfo('14. Sept., 16:00–15. Sept., 06:00 UTC'), findsOneWidget);
  expect(inInfo('13. Sept., 16:00–14. Sept., 06:00 UTC'), findsOneWidget);
  expect(inInfo('Qualitätswert —'), findsWidgets);
  await expectInfoClosePinned();
  await h.capture('cycle-measurements-info-2x-source');
  await tester.tap(infoClose().hitTestable());
  await pumpAfterTap();
  expect(infoClose(), findsNothing);
  expect(tester.takeException(), isNull);

  await mountMeasurements(
    repository: repo,
    scale: 2,
    brightness: Brightness.dark,
  );
  await scrollListToMin(measurementsPage());
  await h.capture('cycle-measurements-main-2x-dark');
  await ensureFullyInSafeViewport(measurementsPage(), hrvPlot());
  await h.capture('cycle-measurements-main-2x-dark-hrv');
  await tapVisible(infoButton(), measurementsPage());
  await expectGenericInfoParas();
  await revealInfoText(inInfo('Ruhepuls · 15. Sept.'));
  await revealInfoText(inInfo('HRV · 14. Sept.'));
  expect(inInfo('14. Sept., 16:00–15. Sept., 06:00 UTC'), findsOneWidget);
  expect(inInfo('Qualitätswert —'), findsWidgets);
  await expectInfoClosePinned();
  await h.capture('cycle-measurements-info-2x-source-dark');
  await tester.tap(infoClose().hitTestable());
  await pumpAfterTap();
}
