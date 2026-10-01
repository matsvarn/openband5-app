part of 'harness.dart';

Future<void> reviewCycleGaps(ReviewHarness h) async {
  final tester = h.tester;
  final now = DateTime(2026, 9, 15, 9, 41);
  const day = '2026-09-15';
  const paperStarts = [
    '2025-09-14',
    '2025-10-12',
    '2025-11-11',
    '2025-12-08',
    '2026-01-06',
    '2026-02-03',
    '2026-03-06',
    '2026-04-01',
    '2026-05-01',
    '2026-05-29',
    '2026-06-30',
    '2026-07-27',
    '2026-08-24',
  ];

  void seedPaperGaps(
    _CycleReviewRepo target, {
    bool earlier = false,
    bool display = true,
    bool enabled = true,
  }) {
    target.clearCycleLogs();
    if (earlier) {
      target.seedCycleStart(
        const CycleStart(date: '2025-08-17', kind: kCycleStartKind),
      );
    }
    for (final date in paperStarts) {
      target.seedCycleStart(CycleStart(date: date, kind: kCycleStartKind));
    }
    target.cycleSettings = CycleSettings(
      enabled: enabled,
      estimatesEnabled: true,
      lengthReviewEnabled: display,
    );
  }

  Future<_CycleReviewRepo> loadRepo({
    bool earlier = false,
    bool display = true,
    bool enabled = true,
  }) async {
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
    seedPaperGaps(repo, earlier: earlier, display: display, enabled: enabled);
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
  Finder gapsPage() => find.byKey(const ValueKey('cycle-gaps'));
  Finder pickerRow() => find.byKey(const ValueKey('cycle-gaps-picker'));
  Finder plot() => find.byKey(const ValueKey('cycle-gaps-plot'));
  Finder inRoute(Finder ancestor, Finder matching) =>
      find.descendant(of: ancestor, matching: matching);
  Finder infoButton() => inRoute(gapsPage(), find.byTooltip('Information'));
  Finder gapsChoiceSheet() => find.byType(OBSettingsChoiceSheet<int>);
  Finder infoBody() => find.byKey(const ValueKey('journal-info-body'));
  Finder infoClose() => find.widgetWithText(OBAction, 'Schließen');
  Finder toggleSwitch(String label) => find.descendant(
    of: find.widgetWithText(OBSettingsToggleRow, label),
    matching: find.byType(CupertinoSwitch),
  );

  Future<void> expectInfoClosePinned() async {
    expect(infoClose().hitTestable(), findsOneWidget);
    expect(rectInSafeViewport(tester.getRect(infoClose())), isTrue);
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

  Future<_CycleReviewRepo> mountGaps({
    Brightness brightness = Brightness.light,
    double scale = 1,
    _CycleReviewRepo? repository,
  }) async {
    final repo = repository ?? await loadRepo();
    await tester.pumpWidget(
      reviewHost(
        brightness: brightness,
        scale: scale,
        home: OpenBandCycleGaps(
          repository: repo,
          day: day,
          now: () => now,
          synthetic: true,
        ),
      ),
    );
    await pumpUntil(
      () => gapsPage().evaluate().isNotEmpty,
      'Cycle gaps did not load.',
    );
    return repo;
  }

  Future<void> openGapsFromCycle() async {
    await tapVisible(inRoute(cyclePage(), find.text('Abstände')), cyclePage());
    await pumpUntil(
      () => gapsPage().evaluate().isNotEmpty,
      'Gaps did not open from cycle.',
    );
    expect(gapsPage(), findsOneWidget);
  }

  Future<void> expectPopulatedMain({bool subset = false}) async {
    final page = gapsPage();
    expect(inRoute(page, find.text('Abstände')), findsOneWidget);
    expect(inRoute(page, find.text('Zeitraum')), findsOneWidget);
    expect(inRoute(page, find.text('Sept. 2025–Aug. 2026')), findsOneWidget);
    expect(
      inRoute(page, find.text(subset ? '12 von 13 Abständen' : '12 Abstände')),
      findsOneWidget,
    );
    expect(inRoute(page, find.text('28')), findsWidgets);
    expect(inRoute(page, find.text('27. Juli–24. Aug.')), findsOneWidget);
    expect(inRoute(page, find.text('12. Okt. 2025')), findsOneWidget);
    expect(inRoute(page, find.text('24. Aug. 2026')), findsOneWidget);
    expect(inRoute(page, find.text('Synthetische Daten')), findsOneWidget);
  }

  Offset barSlot(Finder target, int slot, int count, {double scale = 1}) {
    final box = tester.getRect(target);
    final left = 28 + 16 * (scale - 1);
    final right = 4 + 4 * (scale - 1);
    final step = (box.width - left - right) / count;
    return Offset(box.left + left + (slot + 0.5) * step, box.center.dy);
  }

  Future<void> expectInfoParas() async {
    expect(
      find.text(
        'Abstände zählen die Kalendertage zwischen zwei eingetragenen Beginnen. Der laufende Zyklus ist noch nicht enthalten.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Die Ansicht ist optional und benötigt zwölf Abstände. Bei mehr als 60 Tagen oder einem nicht lesbaren Beginn bleibt sie offen. Ein fehlender Beginn lässt sich nicht von einem längeren Zyklus unterscheiden.',
      ),
      findsOneWidget,
    );
  }

  Finder infoLastParagraph() => find.text(
    'Die Ansicht ist optional und benötigt zwölf Abstände. Bei mehr als 60 Tagen oder einem nicht lesbaren Beginn bleibt sie offen. Ein fehlender Beginn lässt sich nicht von einem längeren Zyklus unterscheiden.',
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
  }

  var repo = await loadRepo();
  await mountCycle(repository: repo);
  await ensureFullyInSafeViewport(
    cyclePage(),
    inRoute(cyclePage(), find.text('Abstände')),
  );
  expect(
    tester.getTopLeft(inRoute(cyclePage(), find.text('Beobachtungen'))).dy,
    lessThan(tester.getTopLeft(inRoute(cyclePage(), find.text('Abstände'))).dy),
  );
  expect(
    tester.getTopLeft(inRoute(cyclePage(), find.text('Abstände'))).dy,
    lessThan(tester.getTopLeft(inRoute(cyclePage(), find.text('Verlauf'))).dy),
  );
  await h.capture('cycle-gaps-root');
  await openGapsFromCycle();
  await expectPopulatedMain();
  await h.capture('cycle-gaps-main');
  await popRoute();
  await pumpUntil(
    () => cyclePage().evaluate().isNotEmpty,
    'Did not return to cycle.',
  );
  expect(gapsPage(), findsNothing);
  await h.capture('cycle-gaps-root-back');

  repo = await loadRepo();
  await mountGaps(repository: repo, brightness: Brightness.dark);
  await expectPopulatedMain();
  await h.capture('cycle-gaps-main-dark');

  repo = await loadRepo();
  await mountGaps(repository: repo);
  await tester.tapAt(barSlot(plot(), 9, 12));
  await tester.pump();
  expect(inRoute(gapsPage(), find.text('32')), findsOneWidget);
  expect(inRoute(gapsPage(), find.text('29. Mai–30. Juni')), findsOneWidget);
  await h.capture('cycle-gaps-selected');

  repo = await loadRepo(earlier: true);
  await mountGaps(repository: repo);
  await expectPopulatedMain(subset: true);
  await tapVisible(pickerRow(), gapsPage());
  expect(gapsChoiceSheet(), findsOneWidget);
  expect(find.text('Sept. 2025–Aug. 2026'), findsWidgets);
  expect(find.text('Aug.–Sept. 2025'), findsOneWidget);
  await h.capture('cycle-gaps-picker');
  await tapVisible(
    inRoute(gapsChoiceSheet(), find.text('Aug.–Sept. 2025')),
    gapsChoiceSheet(),
  );
  expect(inRoute(gapsPage(), find.text('1 von 13 Abständen')), findsOneWidget);
  expect(inRoute(gapsPage(), find.text('17. Aug.–14. Sept.')), findsOneWidget);
  await h.capture('cycle-gaps-earlier');

  repo = await loadRepo(earlier: true);
  await mountGaps(repository: repo, brightness: Brightness.dark);
  await tapVisible(pickerRow(), gapsPage());
  await h.capture('cycle-gaps-picker-dark');

  repo = await loadRepo(display: false);
  await mountGaps(repository: repo);
  expect(
    inRoute(gapsPage(), find.text('Abstände ausgeblendet')),
    findsOneWidget,
  );
  await h.capture('cycle-gaps-off');

  repo = await loadRepo(enabled: false);
  await mountGaps(repository: repo);
  expect(inRoute(gapsPage(), find.text('Zyklus deaktiviert')), findsOneWidget);
  await h.capture('cycle-gaps-disabled');
  await tapVisible(inRoute(gapsPage(), find.text('Einstellungen')), gapsPage());
  await pumpUntil(
    () => find.byKey(const ValueKey('cycle-settings')).evaluate().isNotEmpty,
    'Disabled action did not open settings.',
  );
  expect(find.text('Abstände anzeigen'), findsOneWidget);
  await h.capture('cycle-gaps-disabled-settings');
  await popRoute();

  repo = await loadRepo();
  repo.clearCycleLogs();
  repo.seedCycleStart(
    const CycleStart(date: '2026-08-24', kind: kCycleStartKind),
  );
  await mountCycle(repository: repo);
  await openGapsFromCycle();
  expect(
    inRoute(gapsPage(), find.text('Mindestens 12 Abstände nötig')),
    findsOneWidget,
  );
  await h.capture('cycle-gaps-insufficient');
  await tapVisible(inRoute(gapsPage(), find.text('Zum Zyklus')), gapsPage());
  await pumpUntil(
    () => cyclePage().evaluate().isNotEmpty,
    'Insufficient did not return to cycle.',
  );

  repo = await loadRepo();
  repo.clearCycleLogs();
  repo.seedUnreadableCycleStart({'date': '2026-08-24', 'kind': 1});
  await mountCycle(repository: repo);
  await openGapsFromCycle();
  expect(
    inRoute(gapsPage(), find.text('Zyklusbeginn nicht lesbar')),
    findsOneWidget,
  );
  await h.capture('cycle-gaps-unreadable');
  await mountGaps(repository: repo, brightness: Brightness.dark);
  await h.capture('cycle-gaps-unreadable-dark');

  repo = await loadRepo();
  repo.clearCycleLogs();
  repo.seedCycleStart(
    const CycleStart(date: '2026-06-01', kind: kCycleStartKind),
  );
  repo.seedCycleStart(
    const CycleStart(date: '2026-08-24', kind: kCycleStartKind),
  );
  await mountGaps(repository: repo);
  expect(
    inRoute(gapsPage(), find.text('Abstand über 60 Tage')),
    findsOneWidget,
  );
  await h.capture('cycle-gaps-long-gap');

  repo = await loadRepo();
  repo.failCycleLogRead = true;
  await mountGaps(repository: repo);
  expect(find.text('Daten nicht geladen'), findsOneWidget);
  await h.capture('cycle-gaps-read-error');
  repo.failCycleLogRead = false;
  await tapVisible(find.text('Erneut versuchen'), gapsPage());
  await expectPopulatedMain();
  await h.capture('cycle-gaps-read-error-retry');
  repo.failCycleLogRead = true;
  await mountGaps(repository: repo, brightness: Brightness.dark);
  await h.capture('cycle-gaps-read-error-dark');

  repo = await loadRepo();
  await mountGaps(repository: repo);
  await tapVisible(infoButton(), gapsPage());
  await expectInfoParas();
  await expectInfoClosePinned();
  await h.capture('cycle-gaps-info');
  await tester.tap(infoClose().hitTestable());
  await pumpAfterTap();
  repo = await loadRepo();
  await mountGaps(repository: repo, brightness: Brightness.dark);
  await tapVisible(infoButton(), gapsPage());
  await h.capture('cycle-gaps-info-dark');
  await tester.tap(infoClose().hitTestable());
  await pumpAfterTap();

  repo = await loadRepo();
  await tester.pumpWidget(
    reviewHost(
      home: OpenBandCycleSettings(
        repository: repo,
        now: () => now,
        synthetic: true,
      ),
    ),
  );
  await pumpUntil(
    () => find.byKey(const ValueKey('cycle-settings')).evaluate().isNotEmpty,
    'Settings did not load.',
  );
  expect(
    tester.widget<CupertinoSwitch>(toggleSwitch('Abstände anzeigen')).value,
    isTrue,
  );
  await h.capture('cycle-gaps-settings');
  await tester.tap(toggleSwitch('Abstände anzeigen'));
  await pumpAfterTap();
  expect(repo.cycleSettings.lengthReviewEnabled, isFalse);
  await h.capture('cycle-gaps-settings-off');
  repo.failCycleContextRefresh = true;
  await tester.tap(toggleSwitch('Abstände anzeigen'));
  await pumpAfterTap();
  expect(repo.cycleSettings.lengthReviewEnabled, isTrue);
  expect(
    find.text('Gespeichert · Aktualisieren fehlgeschlagen'),
    findsOneWidget,
  );
  await h.capture('cycle-gaps-settings-refresh');

  repo = await loadRepo(earlier: true);
  await mountGaps(repository: repo, scale: 2);
  final page = gapsPage();
  await scrollListToMin(page);
  await h.capture('cycle-gaps-main-2x-top');
  await ensureFullyInSafeViewport(
    page,
    inRoute(page, find.text('Synthetische Daten')),
  );
  await h.capture('cycle-gaps-main-2x');
  await tapVisible(pickerRow(), page);
  await h.capture('cycle-gaps-picker-2x');
  await tapVisible(
    inRoute(gapsChoiceSheet(), find.text('Sept. 2025–Aug. 2026')).last,
    gapsChoiceSheet(),
  );
  await tapVisible(infoButton(), gapsPage());
  await expectInfoParas();
  await expectInfoClosePinned();
  await h.capture('cycle-gaps-info-2x');
  await scrollInfoBodyToEnd();
  await h.capture('cycle-gaps-info-2x-body');
  await tester.tap(infoClose().hitTestable());
  await pumpAfterTap();
  expect(find.text('Schließen'), findsNothing);
  expect(inRoute(gapsPage(), find.text('Synthetische Daten')), findsOneWidget);

  repo = await loadRepo();
  await mountGaps(repository: repo, brightness: Brightness.dark, scale: 2);
  await h.capture('cycle-gaps-main-2x-dark');
  await tapVisible(infoButton(), gapsPage());
  await expectInfoParas();
  await expectInfoClosePinned();
  await h.capture('cycle-gaps-info-2x-dark');
  await scrollInfoBodyToEnd();
  await h.capture('cycle-gaps-info-2x-dark-body');
  await tester.tap(infoClose().hitTestable());
  await pumpAfterTap();
  expect(find.text('Schließen'), findsNothing);
  expect(infoClose(), findsNothing);

  repo = await loadRepo(earlier: true);
  await mountGaps(repository: repo, brightness: Brightness.dark, scale: 2);
  await tapVisible(pickerRow(), gapsPage());
  expect(gapsChoiceSheet(), findsOneWidget);
  expect(find.text('Sept. 2025–Aug. 2026'), findsWidgets);
  expect(find.text('Aug.–Sept. 2025'), findsOneWidget);
  await h.capture('cycle-gaps-picker-2x-dark');
  expect(tester.takeException(), isNull);
}
