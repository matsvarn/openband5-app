part of 'harness.dart';

Future<void> reviewCycleComparison(ReviewHarness h) async {
  final tester = h.tester;
  final now = DateTime(2026, 9, 15, 9, 41);
  const day = '2026-09-15';

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
    repo.seedCycleComparisonFixture();
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

  Finder cyclePage() => find.byKey(const ValueKey('cycle-overview'));
  Finder comparisonPage() => find.byKey(const ValueKey('cycle-comparison'));
  Finder comparisonWindow() =>
      find.byKey(const ValueKey('cycle-comparison-window'));
  Finder comparisonWindowLabel() =>
      find.descendant(of: comparisonWindow(), matching: find.byType(Text));

  void expectComparisonWindow(String start, String end) {
    expect(tester.widget<Text>(comparisonWindowLabel()).data, '$start–\n$end');
  }

  Finder inRoute(Finder ancestor, Finder matching) =>
      find.descendant(of: ancestor, matching: matching);
  Finder infoButton() =>
      inRoute(comparisonPage(), find.byTooltip('Information'));
  Finder infoBody() => find.byKey(const ValueKey('journal-info-body'));
  Finder infoClose() => find.widgetWithText(OBAction, 'Schließen');

  Future<void> expectInfoClosePinned() async {
    expect(infoClose().hitTestable(), findsOneWidget);
  }

  Future<_CycleReviewRepo> mountCycle({
    Brightness brightness = Brightness.light,
    double scale = 1,
    _CycleReviewRepo? repository,
  }) async {
    final repo = repository ?? await loadRepo();
    await tester.pumpWidget(
      reviewHost(
        brightness: brightness,
        scale: scale,
        home: OpenBandCycle(
          repository: repo,
          day: day,
          now: () => now,
          synthetic: true,
        ),
      ),
    );
    await pumpUntil(
      () => cyclePage().evaluate().isNotEmpty,
      'Cycle main did not load.',
    );
    return repo;
  }

  Future<_CycleReviewRepo> mountComparison({
    Brightness brightness = Brightness.light,
    double scale = 1,
    _CycleReviewRepo? repository,
  }) async {
    final repo = repository ?? await loadRepo();
    await tester.pumpWidget(
      reviewHost(
        brightness: brightness,
        scale: scale,
        home: OpenBandCycleComparison(
          repository: repo,
          day: day,
          now: () => now,
          synthetic: true,
        ),
      ),
    );
    await pumpUntil(
      () => comparisonPage().evaluate().isNotEmpty,
      'Cycle comparison did not load.',
    );
    return repo;
  }

  Finder downScrollable(Finder ancestor) => find.descendant(
    of: ancestor,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    ),
  );

  Future<void> resetComparisonScroll() async {
    final found = downScrollable(comparisonPage());
    if (found.evaluate().isEmpty) return;
    final position = tester.state<ScrollableState>(found.first).position;
    if ((position.pixels - position.minScrollExtent).abs() > 0.5) {
      position.jumpTo(position.minScrollExtent);
      await tester.pump();
    }
  }

  Future<void> captureMainEnds(String top, String bottom) async {
    final page = comparisonPage();
    final scrollable = downScrollable(page).first;
    tester
        .state<ScrollableState>(scrollable)
        .position
        .jumpTo(
          tester.state<ScrollableState>(scrollable).position.minScrollExtent,
        );
    await tester.pump();
    await h.capture(top);
    await tester.scrollUntilVisible(
      inRoute(page, find.text('Synthetische Daten')),
      80,
      scrollable: scrollable,
    );
    await h.capture(bottom);
    await resetComparisonScroll();
  }

  Future<void> captureSheetEnds(
    String top,
    String body, {
    required String lastContains,
    bool sourceActions = false,
  }) async {
    await expectInfoClosePinned();
    await h.capture(top);
    final infoScroll = find.descendant(
      of: infoBody(),
      matching: find.byType(Scrollable),
    );
    expect(infoScroll, findsOneWidget);
    await tester.pump();
    final position = tester.state<ScrollableState>(infoScroll.first).position;
    if (position.maxScrollExtent > 0.5) {
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
    }
    final last = find.textContaining(lastContains);
    expect(last, findsOneWidget);
    final lastBox = tester.getRect(last);
    final view = tester.getRect(infoScroll.first);
    expect(lastBox.top, greaterThanOrEqualTo(view.top - 1));
    expect(lastBox.bottom, lessThanOrEqualTo(view.bottom + 1));
    if (sourceActions) {
      expect(find.text('Ruhepuls · Quellen'), findsOneWidget);
      expect(find.text('HRV · Quellen'), findsOneWidget);
      expect(find.text('HRV · Quellen').hitTestable(), findsOneWidget);
    }
    await expectInfoClosePinned();
    await h.capture(body);
    if (sourceActions) {
      await tester.ensureVisible(find.text('HRV · Quellen'));
      await tester.pump();
      expect(find.text('HRV · Quellen').hitTestable(), findsOneWidget);
      await tester.ensureVisible(find.text('Ruhepuls · Quellen'));
      await tester.pump();
      expect(find.text('Ruhepuls · Quellen').hitTestable(), findsOneWidget);
      await expectInfoClosePinned();
    }
  }

  Future<void> openComparisonFromCycle() async {
    await tester.tap(
      inRoute(cyclePage(), find.text('Vergleich')).hitTestable(),
    );
    await pumpAfterTap();
    await pumpUntil(
      () => comparisonPage().evaluate().isNotEmpty,
      'Did not open comparison.',
    );
  }

  var repo = await loadRepo();
  await mountCycle(repository: repo);
  expect(
    tester.getTopLeft(inRoute(cyclePage(), find.text('Zyklustage'))).dy,
    lessThan(
      tester.getTopLeft(inRoute(cyclePage(), find.text('Vergleich'))).dy,
    ),
  );
  expect(
    tester.getTopLeft(inRoute(cyclePage(), find.text('Vergleich'))).dy,
    lessThan(
      tester.getTopLeft(inRoute(cyclePage(), find.text('Beobachtungen'))).dy,
    ),
  );
  await h.capture('cycle-comparison-root');
  await openComparisonFromCycle();
  expect(inRoute(comparisonPage(), find.text('56')), findsOneWidget);
  expect(
    inRoute(comparisonPage(), find.text('Nacht · Tag 23')),
    findsOneWidget,
  );
  expect(inRoute(comparisonPage(), find.text('51')), findsOneWidget);
  expect(
    inRoute(comparisonPage(), find.text('Nacht · Tag 22')),
    findsOneWidget,
  );
  await h.capture('cycle-comparison-main');
  await popRoute();
  await pumpUntil(
    () => cyclePage().evaluate().isNotEmpty,
    'Did not return to cycle.',
  );
  expect(comparisonPage(), findsNothing);
  await h.capture('cycle-comparison-root-back');

  repo = await loadRepo();
  await mountCycle(repository: repo);
  await openComparisonFromCycle();
  await tester.tap(find.byKey(const ValueKey('cycle-comparison-window')));
  await pumpAfterTap();
  expect(find.text('Enddatum'), findsOneWidget);
  await h.capture('cycle-comparison-date');
  await popRoute();
  await pumpUntil(
    () => comparisonPage().evaluate().isNotEmpty,
    'Date cancel did not return.',
  );
  expect(inRoute(comparisonPage(), find.text('56')), findsOneWidget);
  await h.capture('cycle-comparison-date-cancel');
  await tester.tap(find.byKey(const ValueKey('cycle-comparison-window')));
  await pumpAfterTap();
  await tester.tap(find.text('1').first);
  await pumpAfterTap();
  await tester.tap(find.text('Übernehmen'));
  await pumpAfterTap();
  expect(find.text('Enddatum'), findsNothing);
  expectComparisonWindow('2. Sept. 2025', '1. Sept. 2026');
  expect(
    inRoute(
      find.byKey(const ValueKey('cycle-comparison-rhr')),
      find.text('1. Sept. 2026'),
    ),
    findsOneWidget,
  );
  expect(
    inRoute(
      find.byKey(const ValueKey('cycle-comparison-hrv')),
      find.text('1. Sept. 2026'),
    ),
    findsOneWidget,
  );
  expect(inRoute(comparisonPage(), find.text('15. Sept. 2026')), findsNothing);
  await h.capture('cycle-comparison-date-confirm');
  await popRoute();
  await pumpUntil(
    () => cyclePage().evaluate().isNotEmpty,
    'Date confirm did not return to cycle.',
  );
  expect(inRoute(cyclePage(), find.text('Tag 23')), findsOneWidget);
  expect(
    inRoute(cyclePage(), find.textContaining('15. Sept.')),
    findsOneWidget,
  );
  await h.capture('cycle-comparison-date-confirm-root');

  repo = await loadRepo();
  await mountComparison(repository: repo, brightness: Brightness.dark);
  expect(inRoute(comparisonPage(), find.text('56')), findsOneWidget);
  await h.capture('cycle-comparison-main-dark');

  repo = await loadRepo();
  await mountComparison(repository: repo);
  await tester.tap(find.byKey(const ValueKey('cycle-comparison-earlier')));
  await pumpAfterTap();
  expectComparisonWindow('16. Sept. 2024', '15. Sept. 2025');
  expect(find.text('Keine Nacht'), findsNWidgets(2));
  expect(find.text('Kein Zyklusbeginn'), findsNothing);
  await h.capture('cycle-comparison-earlier');
  await tester.tap(find.byKey(const ValueKey('cycle-comparison-later')));
  await pumpAfterTap();
  expect(find.text('56'), findsOneWidget);
  await h.capture('cycle-comparison-earlier-return');

  repo = await loadRepo();
  repo.seedCycleComparisonFixture(includeHrv: false);
  await mountComparison(repository: repo);
  expect(find.text('56'), findsOneWidget);
  expect(find.text('Keine Nacht'), findsOneWidget);
  expect(find.text('51'), findsNothing);
  await h.capture('cycle-comparison-one-metric');

  repo = await loadRepo();
  repo.clearCycleNightSources();
  await mountComparison(repository: repo);
  expect(find.text('Keine Nacht'), findsNWidgets(2));
  expect(find.text('Gegenüber dem Mittelwert'), findsNothing);
  await h.capture('cycle-comparison-empty');
  await mountComparison(repository: repo, brightness: Brightness.dark);
  expect(find.text('Keine Nacht'), findsNWidgets(2));
  await h.capture('cycle-comparison-empty-dark');

  repo = await loadRepo();
  repo.clearCycleLogs();
  await mountComparison(repository: repo);
  expect(find.text('56'), findsOneWidget);
  expect(find.text('51'), findsOneWidget);
  expect(find.text('Kein Zyklusbeginn'), findsNWidgets(2));
  expect(find.text('Nacht · Tag 23'), findsNothing);
  await h.capture('cycle-comparison-no-start');

  repo = await loadRepo();
  repo.cycleSettings = const CycleSettings(
    enabled: false,
    estimatesEnabled: false,
    lengthReviewEnabled: false,
  );
  await mountComparison(repository: repo);
  expect(find.text('Zyklustracking aus'), findsOneWidget);
  await h.capture('cycle-comparison-disabled');
  await tester.tap(find.text('Einstellungen'));
  await pumpAfterTap();
  expect(find.text('Zyklus im Journal'), findsOneWidget);
  await h.capture('cycle-comparison-disabled-settings');
  await popRoute();
  await pumpUntil(
    () => comparisonPage().evaluate().isNotEmpty,
    'Settings did not return.',
  );
  await h.capture('cycle-comparison-disabled-return');

  repo = await loadRepo();
  repo.clearCycleLogs();
  repo.seedUnreadableCycleStart({'date': '2026-08-24', 'kind': 1});
  await mountComparison(repository: repo);
  expect(find.text('Beginn nicht lesbar'), findsNWidgets(2));
  expect(find.text('56'), findsOneWidget);
  expect(find.text('17 Nächte'), findsOneWidget);
  await h.capture('cycle-comparison-unreadable');

  repo = await loadRepo();
  repo.clearCycleLogs();
  repo.seedCycleStart(
    const CycleStart(date: '2025-01-01', kind: kCycleStartKind),
  );
  await mountComparison(repository: repo);
  expect(find.text('Abstand über 60 Tage'), findsNWidgets(2));
  expect(find.text('56'), findsOneWidget);
  expect(find.text('17 Nächte'), findsOneWidget);
  await h.capture('cycle-comparison-long');

  repo = await loadRepo();
  repo.seedCycleNightSource(
    CycleNightSourceRow(
      day: '2026-08-29',
      algoVersion: kAlgoVersion,
      payloadUnreadable: true,
    ),
  );
  await mountComparison(repository: repo);
  expect(find.text('Teilweise ausgewertet'), findsOneWidget);
  expect(find.text('56'), findsOneWidget);
  await h.capture('cycle-comparison-partial');
  await tester.tap(infoButton().hitTestable());
  await pumpAfterTap();
  expect(
    find.text(
      'Gewähltes Jahr und 21-Tage-Vergleiche: 1 Nacht mit nicht lesbaren Daten.',
    ),
    findsOneWidget,
  );
  expect(find.text('Ruhepuls · Quellen'), findsOneWidget);
  await captureSheetEnds(
    'cycle-comparison-partial-info',
    'cycle-comparison-partial-info-body',
    lastContains: 'nicht lesbaren Daten',
  );
  await tester.tap(infoClose().hitTestable());
  await pumpAfterTap();
  await mountComparison(repository: repo, brightness: Brightness.dark);
  expect(find.text('Teilweise ausgewertet'), findsOneWidget);
  await h.capture('cycle-comparison-partial-dark');
  await tester.tap(infoButton().hitTestable());
  await pumpAfterTap();
  await captureSheetEnds(
    'cycle-comparison-partial-info-dark',
    'cycle-comparison-partial-info-dark-body',
    lastContains: 'nicht lesbaren Daten',
  );
  await tester.tap(infoClose().hitTestable());
  await pumpAfterTap();

  repo = await loadRepo();
  repo.clearCycleNightSources();
  repo.seedCycleNightSource(
    CycleNightSourceRow(
      day: '2026-09-15',
      algoVersion: kAlgoVersion,
      payloadUnreadable: true,
    ),
  );
  await mountComparison(repository: repo);
  expect(find.text('Nicht auswertbar'), findsNWidgets(2));
  expect(find.text('Keine Nacht'), findsNothing);
  await h.capture('cycle-comparison-unavailable');
  await tester.tap(infoButton().hitTestable());
  await pumpAfterTap();
  expect(
    find.text(
      'Gewähltes Jahr und 21-Tage-Vergleiche: 1 Nacht mit nicht lesbaren Daten.',
    ),
    findsOneWidget,
  );
  expect(find.text('Ruhepuls · Quellen'), findsNothing);
  await captureSheetEnds(
    'cycle-comparison-unavailable-info',
    'cycle-comparison-unavailable-info-body',
    lastContains: 'nicht lesbaren Daten',
  );
  await tester.tap(infoClose().hitTestable());
  await pumpAfterTap();
  await mountComparison(repository: repo, brightness: Brightness.dark);
  expect(find.text('Nicht auswertbar'), findsNWidgets(2));
  await h.capture('cycle-comparison-unavailable-dark');
  await tester.tap(infoButton().hitTestable());
  await pumpAfterTap();
  expect(find.text('Ruhepuls · Quellen'), findsNothing);
  await captureSheetEnds(
    'cycle-comparison-unavailable-info-dark',
    'cycle-comparison-unavailable-info-dark-body',
    lastContains: 'nicht lesbaren Daten',
  );
  await tester.tap(infoClose().hitTestable());
  await pumpAfterTap();

  repo = await loadRepo();
  repo.failCycleComparisonRead = true;
  await mountComparison(repository: repo);
  expect(find.text('Daten nicht geladen'), findsOneWidget);
  await h.capture('cycle-comparison-error');
  await mountComparison(repository: repo, brightness: Brightness.dark);
  expect(find.text('Daten nicht geladen'), findsOneWidget);
  await h.capture('cycle-comparison-error-dark');
  repo.failCycleComparisonRead = false;
  await tester.tap(find.text('Erneut versuchen'));
  await pumpAfterTap();
  expect(find.text('56'), findsOneWidget);
  await h.capture('cycle-comparison-error-retry');

  repo = await loadRepo();
  await mountComparison(repository: repo);
  await resetComparisonScroll();
  await tester.tap(infoButton().hitTestable());
  await pumpAfterTap();
  expect(
    find.text(
      'Verglichen wird die letzte gespeicherte Nacht je Messwert. Die Differenz bezieht sich auf den Mittelwert der genannten Nächte.',
    ),
    findsOneWidget,
  );
  expect(find.text('Ruhepuls · Quellen'), findsOneWidget);
  expect(find.text('HRV · Quellen'), findsOneWidget);
  await captureSheetEnds(
    'cycle-comparison-info',
    'cycle-comparison-info-body',
    lastContains: 'HRV · Quellen',
    sourceActions: true,
  );
  await tester.tap(find.text('Ruhepuls · Quellen').hitTestable());
  await pumpAfterTap();
  expect(find.text('Ruhepuls · Quellen'), findsNothing);
  expect(find.text('Ruhepuls'), findsWidgets);
  await captureSheetEnds(
    'cycle-comparison-rhr-sources',
    'cycle-comparison-rhr-sources-body',
    lastContains: 'Keine Aussage über Ursache',
  );
  await tester.tap(infoClose().hitTestable());
  await pumpAfterTap();
  expect(comparisonPage(), findsOneWidget);

  repo = await loadRepo();
  await mountComparison(repository: repo);
  await tester.tap(infoButton().hitTestable());
  await pumpAfterTap();
  await tester.tap(find.text('HRV · Quellen').hitTestable());
  await pumpAfterTap();
  expect(find.text('HRV · Quellen'), findsNothing);
  await captureSheetEnds(
    'cycle-comparison-hrv-sources',
    'cycle-comparison-hrv-sources-body',
    lastContains: 'Keine Aussage über Ursache',
  );
  await tester.tap(infoClose().hitTestable());
  await pumpAfterTap();

  repo = await loadRepo();
  await mountComparison(repository: repo, brightness: Brightness.dark);
  await tester.tap(infoButton().hitTestable());
  await pumpAfterTap();
  await captureSheetEnds(
    'cycle-comparison-info-dark',
    'cycle-comparison-info-dark-body',
    lastContains: 'HRV · Quellen',
    sourceActions: true,
  );
  await tester.tap(infoClose().hitTestable());
  await pumpAfterTap();

  repo = await loadRepo();
  await mountComparison(repository: repo, scale: 2);
  expect(find.text('56'), findsOneWidget);
  await captureMainEnds(
    'cycle-comparison-main-2x-top',
    'cycle-comparison-main-2x',
  );
  await tester.tap(infoButton().hitTestable());
  await pumpAfterTap();
  await captureSheetEnds(
    'cycle-comparison-info-2x',
    'cycle-comparison-info-2x-body',
    lastContains: 'HRV · Quellen',
    sourceActions: true,
  );
  await tester.tap(find.text('Ruhepuls · Quellen').hitTestable());
  await pumpAfterTap();
  await captureSheetEnds(
    'cycle-comparison-rhr-sources-2x',
    'cycle-comparison-rhr-sources-2x-body',
    lastContains: 'Keine Aussage über Ursache',
  );
  await tester.tap(infoClose().hitTestable());
  await pumpAfterTap();
  await resetComparisonScroll();
  await tester.tap(
    find.byKey(const ValueKey('cycle-comparison-window')).hitTestable(),
  );
  await pumpAfterTap();
  expect(find.text('Enddatum'), findsOneWidget);
  await h.capture('cycle-comparison-date-2x');
  await popRoute();
  await pumpUntil(
    () => comparisonPage().evaluate().isNotEmpty,
    '2x date did not return.',
  );

  repo = await loadRepo();
  await mountComparison(
    repository: repo,
    brightness: Brightness.dark,
    scale: 2,
  );
  await captureMainEnds(
    'cycle-comparison-main-2x-dark-top',
    'cycle-comparison-main-2x-dark',
  );
  await tester.tap(infoButton().hitTestable());
  await pumpAfterTap();
  await captureSheetEnds(
    'cycle-comparison-info-2x-dark',
    'cycle-comparison-info-2x-dark-body',
    lastContains: 'HRV · Quellen',
    sourceActions: true,
  );
  await tester.tap(infoClose().hitTestable());
  await pumpAfterTap();
  await resetComparisonScroll();
  await tester.tap(
    find.byKey(const ValueKey('cycle-comparison-window')).hitTestable(),
  );
  await pumpAfterTap();
  expect(find.text('Enddatum'), findsOneWidget);
  await h.capture('cycle-comparison-date-2x-dark');
  expect(tester.takeException(), isNull);
}
