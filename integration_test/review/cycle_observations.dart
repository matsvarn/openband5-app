part of 'harness.dart';

Future<void> reviewCycleObservations(ReviewHarness h) async {
  final tester = h.tester;
  final now = DateTime(2026, 9, 15, 9, 41);
  const day = SyntheticOpenBandRepository.cycleFixtureDay;

  void seedPaperObservations(_CycleReviewRepo target, {bool week5 = false}) {
    const rows = <(String, List<String>)>[
      ('2026-06-01', ['cramps', 'fatigue']),
      ('2026-06-03', ['cramps']),
      ('2026-06-29', ['cramps', 'headache']),
      ('2026-07-02', ['fatigue']),
      ('2026-07-31', ['cramps']),
      ('2026-08-02', ['fatigue']),
      ('2026-08-24', ['headache']),
      ('2026-08-25', ['bloating']),
    ];
    for (final row in rows) {
      target.seedCycleObservation(CycleObservation(date: row.$1, tags: row.$2));
    }
    if (week5) {
      target.seedCycleObservation(
        const CycleObservation(date: '2026-07-28', tags: ['nausea']),
      );
      target.seedCycleObservation(
        const CycleObservation(date: '2026-07-29', tags: [], note: 'felt off'),
      );
    }
  }

  Future<_CycleReviewRepo> loadRepo({bool week5 = false}) async {
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
    seedPaperObservations(repo, week5: week5);
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
  Finder observationsPage() => find.byKey(const ValueKey('cycle-observations'));
  Finder pickerRow() => find.byKey(const ValueKey('cycle-observations-picker'));
  Finder inRoute(Finder ancestor, Finder matching) =>
      find.descendant(of: ancestor, matching: matching);
  Finder infoButton() =>
      inRoute(observationsPage(), find.byTooltip('Information'));
  Finder observationsChoiceSheet() => find.byType(OBSettingsChoiceSheet<int>);
  Finder infoBody() => find.byKey(const ValueKey('journal-info-body'));
  Finder infoClose() => find.widgetWithText(OBAction, 'Schließen');
  Finder inInfo(String text) =>
      find.descendant(of: infoBody(), matching: find.textContaining(text));

  Future<void> expectInfoClosePinned() async {
    expect(infoClose().hitTestable(), findsOneWidget);
    expect(rectInSafeViewport(tester.getRect(infoClose())), isTrue);
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

  Future<_CycleReviewRepo> mountObservations({
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
        home: OpenBandCycleObservations(
          repository: repo,
          day: onDay ?? day,
          now: () => now,
          synthetic: true,
        ),
      ),
    );
    await pumpUntil(
      () => observationsPage().evaluate().isNotEmpty,
      'Cycle observations did not load.',
    );
    return repo;
  }

  Future<void> openObservationsFromCycle() async {
    await tapVisible(
      inRoute(cyclePage(), find.text('Beobachtungen')),
      cyclePage(),
    );
    await pumpUntil(
      () => observationsPage().evaluate().isNotEmpty,
      'Observations did not open from cycle.',
    );
    expect(observationsPage(), findsOneWidget);
  }

  Future<void> expectPopulatedMain() async {
    final page = observationsPage();
    expect(inRoute(page, find.text('Beobachtungen')), findsOneWidget);
    expect(inRoute(page, find.text('Zyklustage')), findsOneWidget);
    expect(inRoute(page, find.text('Tag 1–7')), findsOneWidget);
    expect(
      inRoute(page, find.text('8 Tage mit Beobachtungen')),
      findsOneWidget,
    );
    expect(
      inRoute(page, find.text('1. Juni–15. Sept. · 4 Zyklen')),
      findsOneWidget,
    );
    expect(inRoute(page, find.text('Krämpfe')), findsOneWidget);
    expect(inRoute(page, find.text('4 von 8')), findsOneWidget);
    expect(inRoute(page, find.text('Müdigkeit')), findsOneWidget);
    expect(inRoute(page, find.text('3 von 8')), findsOneWidget);
    expect(inRoute(page, find.text('Kopfschmerzen')), findsOneWidget);
    expect(inRoute(page, find.text('2 von 8')), findsOneWidget);
    expect(inRoute(page, find.text('Blähungen')), findsOneWidget);
    expect(inRoute(page, find.text('1 von 8')), findsOneWidget);
    expect(inRoute(page, find.text('Synthetische Daten')), findsOneWidget);
  }

  Future<void> expectWeekSelected(String label) async {
    final sheet = observationsChoiceSheet();
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

  Future<void> expectInfoParas() async {
    expect(
      find.text(
        'Gezählt werden nur Tage mit mindestens einer gespeicherten Beobachtung. Notizen allein und fehlende Einträge zählen nicht als symptomfreie Tage.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Die Übersicht beginnt mit drei eingetragenen Zyklusbeginnen. Zyklustage zählen ab dem jeweils letzten eingetragenen Beginn. Der laufende Zyklus ist enthalten.',
      ),
      findsOneWidget,
    );
  }

  Finder infoLastParagraph() => find.text(
    'Die Übersicht beginnt mit drei eingetragenen Zyklusbeginnen. Zyklustage zählen ab dem jeweils letzten eingetragenen Beginn. Der laufende Zyklus ist enthalten.',
  );

  Future<void> scrollInfoBodyToEnd() async {
    final body = infoBody();
    expect(body, findsOneWidget);
    final scrollable = downScrollable(body).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    final start = position.pixels;
    expect(position.maxScrollExtent, greaterThan(0.5));
    var drags = 0;
    while (position.pixels < position.maxScrollExtent - 0.5) {
      if (++drags > 32) {
        throw FlutterError(
          'Info body did not reach end after production scrolling.',
        );
      }
      await tester.drag(scrollable, const Offset(0, -64));
      await tester.pump();
      await expectInfoClosePinned();
    }
    expect(position.pixels, greaterThan(start));
    final last = infoLastParagraph();
    expect(last.hitTestable(), findsOneWidget);
    expect(inInfo('enthalten.'), findsOneWidget);
    final lastBox = tester.getRect(last);
    final bodyView = reviewSafeViewport(contentOf: body);
    expect(lastBox.bottom, lessThanOrEqualTo(bodyView.bottom + 8));
    await expectInfoClosePinned();
  }

  Future<void> openPickerSheet({double scale = 1}) async {
    await tapVisible(pickerRow(), observationsPage());
    final sheet = observationsChoiceSheet();
    expect(sheet, findsOneWidget);
    expect(find.text('Tag 1–7'), findsWidgets);
    expect(find.text('Tag 8–14'), findsOneWidget);
    expect(find.text('Tag 15–21'), findsOneWidget);
    expect(find.text('Tag 22–28'), findsOneWidget);
    expect(find.text('Tag 29–35'), findsOneWidget);
    await expectWeekSelected('Tag 1–7');
    if (scale > 1) {
      await ensureFullyInSafeViewport(sheet, find.text('Tag 29–35'));
      expect(
        rectInSafeViewport(
          tester.getRect(find.text('Tag 29–35')),
          contentOf: sheet,
        ),
        isTrue,
      );
    }
  }

  Future<void> capturePickerVariant({
    required String name,
    Brightness brightness = Brightness.light,
    double scale = 1,
  }) async {
    final repo = await loadRepo(week5: true);
    await mountObservations(
      repository: repo,
      brightness: brightness,
      scale: scale,
    );
    await openPickerSheet(scale: scale);
    await h.capture(name);
  }

  Future<void> captureInfoVariant({
    required String name,
    Brightness brightness = Brightness.light,
    double scale = 1,
    String? bodyName,
  }) async {
    final repo = await loadRepo();
    await mountObservations(
      repository: repo,
      brightness: brightness,
      scale: scale,
    );
    await tapVisible(infoButton(), observationsPage());
    await expectInfoParas();
    await expectInfoClosePinned();
    await h.capture(name);
    if (bodyName != null) {
      await scrollInfoBodyToEnd();
      await h.capture(bodyName);
    }
    await tester.tap(infoClose().hitTestable());
    await pumpAfterTap();
    expect(infoClose(), findsNothing);
  }

  Future<void> captureScaledMain({
    required Brightness brightness,
    required String topName,
    required String bottomName,
    required String pickerName,
    required String infoName,
    String? infoBodyName,
  }) async {
    final repo = await loadRepo(week5: true);
    await mountObservations(repository: repo, brightness: brightness, scale: 2);
    final page = observationsPage();
    await scrollListToMin(page);
    await ensureFullyInSafeViewport(
      page,
      inRoute(page, find.text('Beobachtungen')),
    );
    expect(
      inRoute(page, find.text('Beobachtungen')).hitTestable(),
      findsOneWidget,
    );
    await h.capture(topName);
    await ensureFullyInSafeViewport(
      page,
      inRoute(page, find.text('Synthetische Daten')),
    );
    await h.capture(bottomName);
    await openPickerSheet(scale: 2);
    await h.capture(pickerName);
    await tapVisible(
      inRoute(observationsChoiceSheet(), find.text('Tag 1–7')),
      observationsChoiceSheet(),
    );
    await tapVisible(infoButton(), observationsPage());
    await expectInfoParas();
    await expectInfoClosePinned();
    await h.capture(infoName);
    if (infoBodyName != null) {
      await scrollInfoBodyToEnd();
      await h.capture(infoBodyName);
    }
    await tester.tap(infoClose().hitTestable());
    await pumpAfterTap();
    expect(infoClose(), findsNothing);
  }

  var repo = await loadRepo();
  await mountCycle(repository: repo);
  await ensureFullyInSafeViewport(
    cyclePage(),
    inRoute(cyclePage(), find.text('Beobachtungen')),
  );
  expect(
    tester.getTopLeft(inRoute(cyclePage(), find.text('Messwerte'))).dy,
    lessThan(
      tester.getTopLeft(inRoute(cyclePage(), find.text('Beobachtungen'))).dy,
    ),
  );
  expect(
    tester.getTopLeft(inRoute(cyclePage(), find.text('Beobachtungen'))).dy,
    lessThan(tester.getTopLeft(inRoute(cyclePage(), find.text('Verlauf'))).dy),
  );
  await h.capture('cycle-observations-root');
  await openObservationsFromCycle();
  await expectPopulatedMain();
  await scrollListToMin(observationsPage());
  await h.capture('cycle-observations-main');
  await popRoute();
  await pumpUntil(
    () => cyclePage().evaluate().isNotEmpty,
    'Cycle did not return from observations.',
  );
  expect(observationsPage(), findsNothing);
  expect(inRoute(cyclePage(), find.text('Beobachtungen')), findsOneWidget);
  expect(inRoute(cyclePage(), find.text('Verlauf')), findsOneWidget);
  await h.capture('cycle-observations-root-back');

  repo = await loadRepo();
  await mountObservations(repository: repo, brightness: Brightness.dark);
  await expectPopulatedMain();
  await h.capture('cycle-observations-main-dark');

  repo = await loadRepo(week5: true);
  await mountObservations(repository: repo);
  await tapVisible(pickerRow(), observationsPage());
  expect(observationsChoiceSheet(), findsOneWidget);
  expect(find.text('Tag 1–7'), findsWidgets);
  expect(find.text('Tag 8–14'), findsOneWidget);
  expect(find.text('Tag 15–21'), findsOneWidget);
  expect(find.text('Tag 22–28'), findsOneWidget);
  expect(find.text('Tag 29–35'), findsOneWidget);
  await expectWeekSelected('Tag 1–7');
  await h.capture('cycle-observations-picker');
  await tester.tap(find.text('Tag 29–35'));
  await pumpAfterTap();
  expect(inRoute(observationsPage(), find.text('Tag 29–35')), findsOneWidget);
  expect(
    inRoute(observationsPage(), find.text('1 Tag mit Beobachtungen')),
    findsOneWidget,
  );
  expect(inRoute(observationsPage(), find.text('Übelkeit')), findsOneWidget);
  expect(inRoute(observationsPage(), find.text('1 von 1')), findsOneWidget);
  expect(inRoute(observationsPage(), find.text('Krämpfe')), findsNothing);
  await h.capture('cycle-observations-week5');
  await tapVisible(pickerRow(), observationsPage());
  await tester.tap(find.text('Tag 8–14'));
  await pumpAfterTap();
  expect(
    inRoute(
      observationsPage(),
      find.text('Keine Einträge für diese Zyklustage'),
    ),
    findsOneWidget,
  );
  expect(inRoute(observationsPage(), find.text('Übelkeit')), findsNothing);
  expect(inRoute(observationsPage(), find.text('Krämpfe')), findsNothing);
  await h.capture('cycle-observations-empty');

  repo = await loadRepo();
  repo.seedUnreadableCycleObservation({
    'date': '2026-09-10',
    'symptoms_json': '{',
  });
  await mountObservations(repository: repo);
  expect(
    inRoute(observationsPage(), find.text('Einträge teilweise lesbar')),
    findsOneWidget,
  );
  expect(
    inRoute(observationsPage(), find.text('8 Tage mit Beobachtungen')),
    findsOneWidget,
  );
  expect(inRoute(observationsPage(), find.text('4 von 8')), findsOneWidget);
  await h.capture('cycle-observations-partial');
  await mountObservations(repository: repo, brightness: Brightness.dark);
  expect(
    inRoute(observationsPage(), find.text('Einträge teilweise lesbar')),
    findsOneWidget,
  );
  expect(
    inRoute(observationsPage(), find.text('8 Tage mit Beobachtungen')),
    findsOneWidget,
  );
  await h.capture('cycle-observations-partial-dark');

  repo = await loadRepo();
  repo.failCycleRead = true;
  await mountObservations(repository: repo);
  expect(
    inRoute(observationsPage(), find.text('Daten nicht geladen')),
    findsOneWidget,
  );
  expect(
    inRoute(observationsPage(), find.text('Erneut versuchen')),
    findsOneWidget,
  );
  await h.capture('cycle-observations-read-error');
  await mountObservations(repository: repo, brightness: Brightness.dark);
  expect(
    inRoute(observationsPage(), find.text('Daten nicht geladen')),
    findsOneWidget,
  );
  expect(
    inRoute(observationsPage(), find.text('Erneut versuchen')),
    findsOneWidget,
  );
  await h.capture('cycle-observations-read-error-dark');
  repo.failCycleRead = false;
  await tester.tap(
    inRoute(observationsPage(), find.text('Erneut versuchen')).hitTestable(),
  );
  await pumpAfterTap();
  await pumpUntil(
    () => find.text('8 Tage mit Beobachtungen').evaluate().isNotEmpty,
    'Retry did not reload observations.',
  );
  await expectPopulatedMain();
  await h.capture('cycle-observations-read-error-retry');

  repo = await loadRepo();
  repo.clearCycleLogs();
  repo.seedCycleStart(
    const CycleStart(date: '2026-08-24', kind: kCycleStartKind),
  );
  repo.seedCycleStart(
    const CycleStart(date: '2026-07-31', kind: kCycleStartKind),
  );
  await mountCycle(repository: repo);
  await openObservationsFromCycle();
  expect(
    inRoute(observationsPage(), find.text('Mindestens 3 Zyklusbeginne nötig')),
    findsOneWidget,
  );
  expect(inRoute(observationsPage(), find.text('Zum Zyklus')), findsOneWidget);
  await h.capture('cycle-observations-insufficient');
  await tester.tap(
    inRoute(observationsPage(), find.text('Zum Zyklus')).hitTestable(),
  );
  await pumpAfterTap();
  await pumpUntil(
    () => cyclePage().evaluate().isNotEmpty,
    'Insufficient did not return to cycle.',
  );
  expect(observationsPage(), findsNothing);

  repo = await loadRepo();
  repo.cycleSettings = const CycleSettings(
    enabled: false,
    estimatesEnabled: false,
    lengthReviewEnabled: false,
  );
  await mountObservations(repository: repo);
  expect(
    inRoute(observationsPage(), find.text('Zyklus deaktiviert')),
    findsOneWidget,
  );
  expect(
    inRoute(observationsPage(), find.text('Einstellungen')),
    findsOneWidget,
  );
  await h.capture('cycle-observations-disabled');
  await tester.tap(
    inRoute(observationsPage(), find.text('Einstellungen')).hitTestable(),
  );
  await pumpAfterTap();
  await pumpUntil(
    () => find.byKey(const ValueKey('cycle-settings')).evaluate().isNotEmpty,
    'Disabled action did not open settings.',
  );
  expect(find.byKey(const ValueKey('cycle-settings')), findsOneWidget);
  await h.capture('cycle-observations-disabled-settings');
  await popRoute();
  await pumpUntil(
    () => observationsPage().evaluate().isNotEmpty,
    'Settings did not return to observations.',
  );

  repo = await loadRepo();
  repo.clearCycleLogs();
  repo.seedUnreadableCycleStart({'date': '2026-08-24', 'kind': 1});
  await mountCycle(repository: repo);
  await openObservationsFromCycle();
  expect(
    inRoute(observationsPage(), find.text('Zyklusbeginn nicht lesbar')),
    findsOneWidget,
  );
  expect(inRoute(observationsPage(), find.text('Zum Zyklus')), findsOneWidget);
  await h.capture('cycle-observations-unreadable');
  await tester.tap(
    inRoute(observationsPage(), find.text('Zum Zyklus')).hitTestable(),
  );
  await pumpAfterTap();
  await pumpUntil(
    () => cyclePage().evaluate().isNotEmpty,
    'Unreadable-start did not return to cycle.',
  );
  expect(observationsPage(), findsNothing);
  await mountObservations(repository: repo, brightness: Brightness.dark);
  expect(
    inRoute(observationsPage(), find.text('Zyklusbeginn nicht lesbar')),
    findsOneWidget,
  );
  await h.capture('cycle-observations-unreadable-dark');

  repo = await loadRepo();
  await mountObservations(repository: repo);
  await tapVisible(infoButton(), observationsPage());
  await expectInfoParas();
  await expectInfoClosePinned();
  await h.capture('cycle-observations-info');
  await tester.tap(infoClose().hitTestable());
  await pumpAfterTap();
  expect(infoClose(), findsNothing);
  await captureInfoVariant(
    name: 'cycle-observations-info-dark',
    brightness: Brightness.dark,
  );
  await capturePickerVariant(
    name: 'cycle-observations-picker-dark',
    brightness: Brightness.dark,
  );

  await captureScaledMain(
    brightness: Brightness.light,
    topName: 'cycle-observations-main-2x-top',
    bottomName: 'cycle-observations-main-2x',
    pickerName: 'cycle-observations-picker-2x',
    infoName: 'cycle-observations-info-2x',
    infoBodyName: 'cycle-observations-info-2x-body',
  );
  await captureScaledMain(
    brightness: Brightness.dark,
    topName: 'cycle-observations-main-2x-dark-top',
    bottomName: 'cycle-observations-main-2x-dark',
    pickerName: 'cycle-observations-picker-2x-dark',
    infoName: 'cycle-observations-info-2x-dark',
  );
  expect(tester.takeException(), isNull);
}
