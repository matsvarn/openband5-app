part of 'harness.dart';

Future<void> reviewCycleMedians(ReviewHarness h) async {
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
    repo.seedCycleMedianFixture();
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
  Finder mediansPage() => find.byKey(const ValueKey('cycle-medians'));
  Finder rhrPlot() => find.byKey(const ValueKey('cycle-medians-rhr-plot'));
  Finder inRoute(Finder ancestor, Finder matching) =>
      find.descendant(of: ancestor, matching: matching);
  Finder infoButton() => inRoute(mediansPage(), find.byTooltip('Information'));
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

  Future<_CycleReviewRepo> mountMedians({
    Brightness brightness = Brightness.light,
    double scale = 1,
    _CycleReviewRepo? repository,
  }) async {
    final repo = repository ?? await loadRepo();
    await tester.pumpWidget(
      reviewHost(
        brightness: brightness,
        scale: scale,
        home: OpenBandCycleMedians(
          repository: repo,
          day: day,
          now: () => now,
          synthetic: true,
        ),
      ),
    );
    await pumpUntil(
      () => mediansPage().evaluate().isNotEmpty,
      'Cycle medians did not load.',
    );
    return repo;
  }

  Future<void> openMediansFromCycle() async {
    await tester.tap(inRoute(cyclePage(), find.text('Zyklustage')));
    await pumpAfterTap();
    await pumpUntil(
      () => mediansPage().evaluate().isNotEmpty,
      'Medians did not open from cycle.',
    );
  }

  Offset plotSlot(Finder target, int slot, int count) {
    final box = tester.getRect(target);
    const left = 26.0;
    const right = 4.0;
    final plotW = box.width - left - right;
    final x = count <= 1
        ? box.left + left + plotW / 2
        : box.left + left + slot * plotW / (count - 1);
    return Offset(x, box.center.dy);
  }

  Finder downScrollable(Finder ancestor) => find.descendant(
    of: ancestor,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    ),
  );

  Future<void> resetMediansScroll() async {
    final found = downScrollable(mediansPage());
    if (found.evaluate().isEmpty) return;
    final position = tester.state<ScrollableState>(found.first).position;
    if ((position.pixels - position.minScrollExtent).abs() > 0.5) {
      position.jumpTo(position.minScrollExtent);
      await tester.pump();
    }
  }

  Future<void> captureMainEnds(String top, String bottom) async {
    final page = mediansPage();
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
    await resetMediansScroll();
  }

  Future<void> captureInfoEnds(String top, String body) async {
    await resetMediansScroll();
    await tester.tap(infoButton().hitTestable());
    await pumpAfterTap();
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
    final last = find.textContaining('keine gemessene Sensorabweichung');
    expect(last, findsOneWidget);
    final lastBox = tester.getRect(last);
    final view = tester.getRect(infoScroll.first);
    expect(lastBox.top, greaterThanOrEqualTo(view.top - 1));
    expect(lastBox.bottom, lessThanOrEqualTo(view.bottom + 1));
    await expectInfoClosePinned();
    await h.capture(body);
    await tester.tap(infoClose().hitTestable());
    await pumpAfterTap();
  }

  var repo = await loadRepo();
  await mountCycle(repository: repo);
  expect(
    tester.getTopLeft(inRoute(cyclePage(), find.text('Messwerte'))).dy,
    lessThan(
      tester.getTopLeft(inRoute(cyclePage(), find.text('Zyklustage'))).dy,
    ),
  );
  expect(
    tester.getTopLeft(inRoute(cyclePage(), find.text('Zyklustage'))).dy,
    lessThan(
      tester.getTopLeft(inRoute(cyclePage(), find.text('Beobachtungen'))).dy,
    ),
  );
  await h.capture('cycle-medians-root');
  await openMediansFromCycle();
  expect(inRoute(mediansPage(), find.text('54')), findsOneWidget);
  expect(inRoute(mediansPage(), find.text('Median · Tag 23')), findsOneWidget);
  await h.capture('cycle-medians-main');
  await popRoute();
  await pumpUntil(
    () => cyclePage().evaluate().isNotEmpty,
    'Did not return to cycle.',
  );
  expect(mediansPage(), findsNothing);
  await h.capture('cycle-medians-root-back');

  repo = await loadRepo();
  await mountCycle(repository: repo);
  await openMediansFromCycle();
  await tester.tap(find.byKey(const ValueKey('cycle-medians-window')));
  await pumpAfterTap();
  expect(find.text('Enddatum'), findsOneWidget);
  await h.capture('cycle-medians-date');
  await popRoute();
  await pumpUntil(
    () => mediansPage().evaluate().isNotEmpty,
    'Date cancel did not return.',
  );
  expect(inRoute(mediansPage(), find.text('54')), findsOneWidget);
  await h.capture('cycle-medians-date-cancel');
  await tester.tap(find.byKey(const ValueKey('cycle-medians-window')));
  await pumpAfterTap();
  await tester.tap(find.text('1').first);
  await pumpAfterTap();
  await tester.tap(find.text('Übernehmen'));
  await pumpAfterTap();
  expect(find.text('Enddatum'), findsNothing);
  expect(find.textContaining('1. Sept. 2026'), findsOneWidget);
  expect(find.textContaining('15. Sept. 2026'), findsNothing);
  expect(inRoute(mediansPage(), find.text('2 Zyklen')), findsNWidgets(2));
  expect(inRoute(mediansPage(), find.text('3 Zyklen')), findsNothing);
  await h.capture('cycle-medians-date-confirm');
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
  await h.capture('cycle-medians-date-confirm-root');

  repo = await loadRepo();
  await mountMedians(repository: repo, brightness: Brightness.dark);
  expect(inRoute(mediansPage(), find.text('54')), findsOneWidget);
  await h.capture('cycle-medians-main-dark');

  repo = await loadRepo();
  await mountMedians(repository: repo);
  await tester.tapAt(plotSlot(rhrPlot(), 5, 23));
  await tester.pump();
  expect(find.text('Median · Tag 6'), findsOneWidget);
  expect(find.text('0 Zyklen'), findsOneWidget);
  expect(find.text('Median · Tag 22'), findsOneWidget);
  await h.capture('cycle-medians-gap');

  await tester.tap(find.byKey(const ValueKey('cycle-medians-earlier')));
  await pumpAfterTap();
  expect(find.text('Kein Zyklusbeginn'), findsOneWidget);
  expect(find.textContaining('16. Sept. 2024'), findsOneWidget);
  await h.capture('cycle-medians-earlier');
  await tester.tap(find.byKey(const ValueKey('cycle-medians-later')));
  await pumpAfterTap();
  expect(find.text('54'), findsOneWidget);
  await h.capture('cycle-medians-earlier-return');

  repo = await loadRepo();
  repo.seedCycleMedianFixture(includeHrv: false);
  await mountMedians(repository: repo);
  expect(find.text('Zu wenige Nächte'), findsOneWidget);
  expect(find.text('54'), findsOneWidget);
  await h.capture('cycle-medians-one-metric');

  repo = await loadRepo();
  repo.clearCycleNightSources();
  await mountMedians(repository: repo);
  expect(find.text('Zu wenige Nächte'), findsNWidgets(2));
  await h.capture('cycle-medians-empty');
  await mountMedians(repository: repo, brightness: Brightness.dark);
  expect(find.text('Zu wenige Nächte'), findsNWidgets(2));
  await h.capture('cycle-medians-empty-dark');

  repo = await loadRepo();
  repo.clearCycleLogs();
  await mountMedians(repository: repo);
  expect(find.text('Kein Zyklusbeginn'), findsOneWidget);
  await h.capture('cycle-medians-no-start');

  repo = await loadRepo();
  repo.cycleSettings = const CycleSettings(
    enabled: false,
    estimatesEnabled: false,
    lengthReviewEnabled: false,
  );
  await mountMedians(repository: repo);
  expect(find.text('Zyklustracking aus'), findsOneWidget);
  await h.capture('cycle-medians-disabled');
  await tester.tap(find.text('Einstellungen'));
  await pumpAfterTap();
  expect(find.text('Zyklus im Journal'), findsOneWidget);
  await h.capture('cycle-medians-disabled-settings');
  await popRoute();
  await pumpUntil(
    () => mediansPage().evaluate().isNotEmpty,
    'Settings did not return.',
  );
  await h.capture('cycle-medians-disabled-return');

  repo = await loadRepo();
  repo.clearCycleLogs();
  repo.seedUnreadableCycleStart({'date': '2026-08-24', 'kind': 1});
  await mountMedians(repository: repo);
  expect(find.text('Beginn nicht lesbar'), findsOneWidget);
  await h.capture('cycle-medians-unreadable');
  await tester.tap(find.text('Zum Verlauf'));
  await pumpAfterTap();
  expect(find.byKey(const ValueKey('cycle-history')), findsOneWidget);
  await h.capture('cycle-medians-unreadable-history');
  await popRoute();
  await pumpUntil(
    () => mediansPage().evaluate().isNotEmpty,
    'History did not return.',
  );
  await h.capture('cycle-medians-unreadable-return');

  repo = await loadRepo();
  repo.seedCycleStart(
    const CycleStart(date: '2026-04-01', kind: kCycleStartKind),
  );
  await mountMedians(repository: repo);
  expect(find.text('Teilweise ausgewertet'), findsOneWidget);
  await h.capture('cycle-medians-partial');
  await mountMedians(repository: repo, brightness: Brightness.dark);
  expect(find.text('Teilweise ausgewertet'), findsOneWidget);
  await h.capture('cycle-medians-partial-dark');

  repo = await loadRepo();
  repo.clearCycleLogs();
  repo.seedCycleStart(
    const CycleStart(date: '2025-01-01', kind: kCycleStartKind),
  );
  repo.seedCycleStart(
    const CycleStart(date: '2025-06-01', kind: kCycleStartKind),
  );
  await mountMedians(repository: repo);
  expect(find.text('Abstände über 60 Tage'), findsOneWidget);
  await h.capture('cycle-medians-long');

  repo = await loadRepo();
  repo.failCycleMediansRead = true;
  await mountMedians(repository: repo);
  expect(find.text('Daten nicht geladen'), findsOneWidget);
  await h.capture('cycle-medians-error');
  await mountMedians(repository: repo, brightness: Brightness.dark);
  expect(find.text('Daten nicht geladen'), findsOneWidget);
  await h.capture('cycle-medians-error-dark');
  repo.failCycleMediansRead = false;
  await tester.tap(find.text('Erneut versuchen'));
  await pumpAfterTap();
  expect(find.text('54'), findsOneWidget);
  await h.capture('cycle-medians-error-retry');

  repo = await loadRepo();
  repo.clearCycleNightSources();
  repo.seedCycleNightSource(
    CycleNightSourceRow(
      day: '2026-08-29',
      algoVersion: kAlgoVersion,
      payloadUnreadable: true,
    ),
  );
  await mountMedians(repository: repo);
  expect(find.text('Teilweise ausgewertet'), findsOneWidget);
  expect(find.text('Zu wenige Nächte'), findsNWidgets(2));
  await h.capture('cycle-medians-partial-thin');

  repo = await loadRepo();
  repo.seedCycleStart(
    const CycleStart(date: '2026-08-24', kind: kCycleStartKind, note: 'keep'),
  );
  repo.seedUnreadableCycleStart({'date': '2026-05-01', 'kind': 1});
  repo.failCycleContextRefresh = true;
  await mountMedians(repository: repo);
  await tester.tap(find.text('Zum Verlauf'));
  await pumpAfterTap();
  await tester.tap(find.text('24. August'));
  await pumpAfterTap();
  await tester.tap(find.text('Entfernen'));
  await pumpAfterTap();
  await tester.tap(find.text('Entfernen').last);
  await pumpAfterTap();
  await popRoute();
  await pumpUntil(
    () => mediansPage().evaluate().isNotEmpty,
    'History remove did not return.',
  );
  expect(find.text('Entfernt · Aktualisieren fehlgeschlagen'), findsOneWidget);
  await h.capture('cycle-medians-removed-refresh');
  await tester.tap(find.text('Rückgängig'));
  await pumpAfterTap();
  expect(repo.startRestores, 1);
  expect(
    find.text('Wiederhergestellt · Aktualisieren fehlgeschlagen'),
    findsOneWidget,
  );
  await h.capture('cycle-medians-restored-refresh');
  repo.failCycleContextRefresh = false;
  await tester.tap(find.text('Erneut versuchen'));
  await pumpAfterTap();
  expect(find.text('Aktualisieren fehlgeschlagen'), findsNothing);
  expect(repo.startRestores, 1);

  repo = await loadRepo();
  repo.seedCycleStart(
    const CycleStart(date: '2026-08-24', kind: kCycleStartKind, note: 'keep'),
  );
  repo.seedUnreadableCycleStart({'date': '2026-05-01', 'kind': 1});
  repo.failCycleContextRefresh = true;
  await mountMedians(repository: repo, brightness: Brightness.dark);
  await tester.tap(find.text('Zum Verlauf'));
  await pumpAfterTap();
  await tester.tap(find.text('24. August'));
  await pumpAfterTap();
  await tester.tap(find.text('Entfernen'));
  await pumpAfterTap();
  await tester.tap(find.text('Entfernen').last);
  await pumpAfterTap();
  await popRoute();
  await pumpUntil(
    () => mediansPage().evaluate().isNotEmpty,
    'Dark history remove did not return.',
  );
  expect(find.text('Entfernt · Aktualisieren fehlgeschlagen'), findsOneWidget);
  await h.capture('cycle-medians-removed-refresh-dark');
  await tester.tap(find.text('Rückgängig'));
  await pumpAfterTap();
  expect(repo.startRestores, 1);
  expect(
    find.text('Wiederhergestellt · Aktualisieren fehlgeschlagen'),
    findsOneWidget,
  );
  await h.capture('cycle-medians-restored-refresh-dark');
  repo.failCycleContextRefresh = false;
  await tester.tap(find.text('Erneut versuchen'));
  await pumpAfterTap();
  expect(find.text('Aktualisieren fehlgeschlagen'), findsNothing);
  expect(repo.startRestores, 1);

  repo = await loadRepo();
  await mountMedians(repository: repo);
  await captureInfoEnds('cycle-medians-info', 'cycle-medians-info-body');

  repo = await loadRepo();
  await mountMedians(repository: repo, brightness: Brightness.dark);
  await captureInfoEnds(
    'cycle-medians-info-dark',
    'cycle-medians-info-dark-body',
  );

  repo = await loadRepo();
  await mountMedians(repository: repo, scale: 2);
  expect(find.text('54'), findsOneWidget);
  await captureMainEnds('cycle-medians-main-2x-top', 'cycle-medians-main-2x');
  await captureInfoEnds('cycle-medians-info-2x', 'cycle-medians-info-2x-body');
  await resetMediansScroll();
  await tester.tap(
    find.byKey(const ValueKey('cycle-medians-window')).hitTestable(),
  );
  await pumpAfterTap();
  expect(find.text('Enddatum'), findsOneWidget);
  await h.capture('cycle-medians-date-2x');
  await popRoute();
  await pumpUntil(
    () => mediansPage().evaluate().isNotEmpty,
    '2x date did not return.',
  );

  repo = await loadRepo();
  await mountMedians(repository: repo, brightness: Brightness.dark, scale: 2);
  await captureMainEnds(
    'cycle-medians-main-2x-dark-top',
    'cycle-medians-main-2x-dark',
  );
  await captureInfoEnds(
    'cycle-medians-info-2x-dark',
    'cycle-medians-info-2x-dark-body',
  );
  await resetMediansScroll();
  await tester.tap(
    find.byKey(const ValueKey('cycle-medians-window')).hitTestable(),
  );
  await pumpAfterTap();
  expect(find.text('Enddatum'), findsOneWidget);
  await h.capture('cycle-medians-date-2x-dark');
  expect(tester.takeException(), isNull);
}
