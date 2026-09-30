part of 'harness.dart';

Future<void> reviewMedications(ReviewHarness h) async {
  final tester = h.tester;
  final now = DateTime(2026, 9, 15, 9, 41);
  const day = SyntheticOpenBandRepository.medicationFixtureDay;

  Future<_MedicationReviewRepo> loadRepo() async {
    Future<Map> load(String name) async =>
        jsonDecode(
              await rootBundle.loadString(
                'docs/openband5/assets/fixtures/$name.json',
              ),
            )
            as Map;
    final repo = _MedicationReviewRepo(
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

  Future<void> enterFocused(Finder field, String text) async {
    await tester.tap(field);
    await tester.pump();
    await tester.showKeyboard(field);
    await tester.pump();
    await waitKeyboardInset(open: true);
    await tester.enterText(field, text);
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, text);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await waitKeyboardInset(open: false);
  }

  Future<void> pumpAfterTap() async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await reviewPumpPageTransitions(tester);
  }

  Future<_MedicationReviewRepo> mountMeds({
    Brightness brightness = Brightness.light,
    double scale = 1,
    _MedicationReviewRepo? repository,
    String? onDay,
    DateTime? clock,
  }) async {
    final repo = repository ?? await loadRepo();
    await tester.pumpWidget(
      reviewHost(
        brightness: brightness,
        scale: scale,
        home: OpenBandMedications(
          repository: repo,
          day: onDay ?? day,
          now: () => clock ?? now,
          synthetic: true,
        ),
      ),
    );
    await pumpUntil(
      () =>
          find.byKey(const ValueKey('medication-main')).evaluate().isNotEmpty ||
          find
              .text('Medikamente konnten nicht geladen werden.')
              .evaluate()
              .isNotEmpty,
      'Medications main did not load.',
    );
    return repo;
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

  // Journal entry.
  var repo = await loadRepo();
  final journal = OpenBandController(
    repository: repo,
    initialDay: day,
    band: repo.band,
    now: () => now,
  );
  await journal.refresh();
  await tester.pumpWidget(
    reviewHost(
      home: Scaffold(
        body: SafeArea(
          child: OpenBandJournal(
            controller: journal,
            onEdit: (_) async {},
            onNutrition: () async {},
          ),
        ),
      ),
    ),
  );
  await pumpUntil(
    () => find.text('Journal').evaluate().isNotEmpty,
    'Journal did not load.',
  );
  final journalPage = find.byType(OpenBandJournal);
  final journalEntry = find.byKey(const ValueKey('medication-journal'));
  await ensureFullyInSafeViewport(journalPage, journalEntry);
  expect(journalEntry.hitTestable(), findsOneWidget);
  expect(find.text('Medikamente'), findsWidgets);
  await h.capture('medications-journal-entry');
  await tester.tap(journalEntry.hitTestable());
  await pumpAfterTap();
  await pumpUntil(
    () => find.byKey(const ValueKey('medication-main')).evaluate().isNotEmpty,
    'Medications did not open from Journal.',
  );
  expect(find.text('Präparat A'), findsOneWidget);
  await h.capture('medications-journal');
  await popRoute();
  await pumpUntil(
    () => find.byType(OpenBandJournal).evaluate().isNotEmpty,
    'Journal route did not return.',
  );
  expect(find.byType(OpenBandJournal), findsOneWidget);
  expect(find.byKey(const ValueKey('medication-journal')), findsOneWidget);
  await scrollListToMin(find.byType(OpenBandJournal));
  expect(find.text('Journal'), findsOneWidget);
  journal.dispose();

  repo = await loadRepo();
  final journalDark = OpenBandController(
    repository: repo,
    initialDay: day,
    band: repo.band,
    now: () => now,
  );
  await journalDark.refresh();
  await tester.pumpWidget(
    reviewHost(
      brightness: Brightness.dark,
      home: Scaffold(
        body: SafeArea(
          child: OpenBandJournal(
            controller: journalDark,
            onEdit: (_) async {},
            onNutrition: () async {},
          ),
        ),
      ),
    ),
  );
  await pumpUntil(
    () => find.text('Journal').evaluate().isNotEmpty,
    'Journal dark did not load.',
  );
  final darkEntry = find.byKey(const ValueKey('medication-journal'));
  await ensureFullyInSafeViewport(find.byType(OpenBandJournal), darkEntry);
  expect(darkEntry.hitTestable(), findsOneWidget);
  await h.capture('medications-journal-entry-dark');
  await tester.tap(darkEntry.hitTestable());
  await pumpAfterTap();
  await pumpUntil(
    () => find.byKey(const ValueKey('medication-main')).evaluate().isNotEmpty,
    'Medications dark did not open from Journal.',
  );
  await h.capture('medications-journal-dark');
  journalDark.dispose();

  Future<void> expectMainLoaded() async {
    final page = find.byKey(const ValueKey('medication-main'));
    expect(find.text('Medikamente'), findsWidgets);
    await ensureFullyInSafeViewport(page, find.text('Präparat A'));
    expect(find.text('Präparat A'), findsOneWidget);
    expect(find.text('Präparat B'), findsOneWidget);
    expect(find.textContaining('Offen'), findsOneWidget);
    expect(find.textContaining('Später'), findsOneWidget);
    await ensureFullyInSafeViewport(page, find.text('Verlauf'));
    await ensureFullyInSafeViewport(page, find.text('Medikament hinzufügen'));
    await ensureFullyInSafeViewport(page, find.text('Synthetische Daten'));
  }

  repo = await mountMeds();
  await expectMainLoaded();
  await scrollListToMin(find.byKey(const ValueKey('medication-main')));
  await h.capture('medications-main');

  await mountMeds(brightness: Brightness.dark);
  await expectMainLoaded();
  await scrollListToMin(find.byKey(const ValueKey('medication-main')));
  await h.capture('medications-main-dark');

  // Record unanswered -> taken actual time -> save.
  repo = await mountMeds();
  await tapVisible(
    find.text('Präparat A'),
    find.byKey(const ValueKey('medication-main')),
  );
  expect(find.byKey(const ValueKey('medication-record')), findsOneWidget);
  expect(find.text('Einnahme'), findsOneWidget);
  expect(find.text('Genommen'), findsOneWidget);
  expect(find.text('Ausgelassen'), findsOneWidget);
  expect(find.text('Eintrag entfernen'), findsNothing);
  expect(
    tester
        .widget<OBAction>(find.widgetWithText(OBAction, 'Speichern'))
        .onPressed,
    isNull,
  );
  await h.capture('medications-unanswered');
  await tester.tap(find.text('Genommen'));
  await pumpAfterTap();
  expect(find.text('09:41'), findsOneWidget);
  await h.capture('medications-taken');
  await tester.tap(find.widgetWithText(OBAction, 'Speichern'));
  await pumpAfterTap();
  expect(find.text('Einnahme'), findsNothing);
  expect(find.textContaining('Genommen 09:41'), findsOneWidget);
  await h.capture('medications-saved');

  await tapVisible(
    find.text('Präparat A'),
    find.byKey(const ValueKey('medication-main')),
  );
  expect(find.text('Eintrag entfernen'), findsOneWidget);
  await tester.tap(find.text('Ausgelassen'));
  await pumpAfterTap();
  await tester.tap(find.widgetWithText(OBAction, 'Speichern'));
  await pumpAfterTap();
  expect(find.textContaining('Ausgelassen'), findsOneWidget);
  await h.capture('medications-skipped');

  await tapVisible(
    find.text('Präparat A'),
    find.byKey(const ValueKey('medication-main')),
  );
  await tester.tap(find.text('Eintrag entfernen'));
  await pumpAfterTap();
  expect(find.textContaining('Offen'), findsOneWidget);

  await mountMeds(brightness: Brightness.dark);
  await tapVisible(
    find.text('Präparat A'),
    find.byKey(const ValueKey('medication-main')),
  );
  await h.capture('medications-unanswered-dark');
  await tester.tap(find.text('Genommen'));
  await pumpAfterTap();
  expect(find.text('09:41'), findsOneWidget);
  await h.capture('medications-taken-dark');

  // History + older paging.
  repo = await mountMeds();
  await tapVisible(
    find.text('Verlauf'),
    find.byKey(const ValueKey('medication-main')),
  );
  expect(find.byKey(const ValueKey('medication-history')), findsOneWidget);
  expect(find.textContaining('Genommen'), findsWidgets);
  expect(find.textContaining('Kein Eintrag'), findsWidgets);
  expect(find.text('Ältere Einträge'), findsOneWidget);
  await h.capture('medications-history');
  repo.failHistoryAfterFirst = true;
  await tester.tap(find.text('Ältere Einträge'));
  await pumpAfterTap();
  expect(
    find.text('Medikamente konnten nicht geladen werden.'),
    findsOneWidget,
  );
  await h.capture('medications-history-older');
  repo.failHistoryAfterFirst = false;
  await tester.tap(find.text('Erneut versuchen'));
  await pumpAfterTap();
  expect(find.text('Präparat A'), findsWidgets);

  await mountMeds(brightness: Brightness.dark);
  await tapVisible(
    find.text('Verlauf'),
    find.byKey(const ValueKey('medication-main')),
  );
  await h.capture('medications-history-dark');

  repo = await loadRepo();
  repo.transformHistory = (hist) => MedicationHistory(
    fromDay: hist.fromDay,
    toDay: hist.toDay,
    entries: const [
      MedicationDayEntry(
        key: 'orphan-old',
        date: '2026-09-14',
        slotMin: 8 * 60,
        status: MedicationSlotStatus.taken,
        takenAt: null,
        snapshotLabel: null,
        snapshotDoseValue: null,
        snapshotDoseUnit: null,
        currentName: 'Präparat A',
        orphan: true,
      ),
    ],
  );
  await mountMeds(repository: repo);
  await tapVisible(
    find.text('Verlauf'),
    find.byKey(const ValueKey('medication-main')),
  );
  expect(find.textContaining('aktueller Name'), findsOneWidget);
  expect(find.text('1 Tablette'), findsNothing);
  await h.capture('medications-legacy');
  await mountMeds(repository: repo, brightness: Brightness.dark);
  await tapVisible(
    find.text('Verlauf'),
    find.byKey(const ValueKey('medication-main')),
  );
  expect(find.textContaining('aktueller Name'), findsOneWidget);
  await h.capture('medications-legacy-dark');

  repo = await loadRepo();
  repo.transformDay = (snap) => MedicationDay(
    day: snap.day,
    entries: [
      MedicationDayEntry(
        key: 'legacy',
        date: '2026-08-20',
        slotMin: 8 * 60,
        status: MedicationSlotStatus.taken,
        takenAt: DateTime.utc(2026, 8, 20, 7, 35),
        snapshotLabel: null,
        snapshotDoseValue: null,
        snapshotDoseUnit: null,
        orphan: true,
      ),
    ],
  );
  await mountMeds(repository: repo);
  await tapVisible(
    find.text('08:00'),
    find.byKey(const ValueKey('medication-main')),
  );
  expect(find.byKey(const ValueKey('medication-record')), findsOneWidget);
  expect(find.text('Name und Menge nicht gespeichert'), findsOneWidget);
  expect(find.text('Zeitzone nicht gespeichert'), findsOneWidget);
  expect(find.text('Eintrag entfernen'), findsOneWidget);
  expect(find.text('Unbekannt'), findsNothing);
  await h.capture('medications-legacy-record');
  await mountMeds(repository: repo, brightness: Brightness.dark);
  await tapVisible(
    find.text('08:00'),
    find.byKey(const ValueKey('medication-main')),
  );
  expect(find.text('Name und Menge nicht gespeichert'), findsOneWidget);
  expect(find.text('Zeitzone nicht gespeichert'), findsOneWidget);
  await h.capture('medications-legacy-record-dark');

  // Plans add / edit / end / restart / time weekdays.
  repo = await mountMeds();
  await tapVisible(
    find.text('Pläne verwalten'),
    find.byKey(const ValueKey('medication-main')),
  );
  expect(find.byKey(const ValueKey('medication-plans')), findsOneWidget);
  expect(find.text('Präparat A'), findsWidgets);
  await h.capture('medications-plans');
  await popRoute();
  await mountMeds(brightness: Brightness.dark);
  await tapVisible(
    find.text('Pläne verwalten'),
    find.byKey(const ValueKey('medication-main')),
  );
  expect(find.byKey(const ValueKey('medication-plans')), findsOneWidget);
  await h.capture('medications-plans-dark');
  await popRoute();
  await mountMeds();
  await tapVisible(
    find.text('Medikament hinzufügen'),
    find.byKey(const ValueKey('medication-main')),
  );
  expect(find.byKey(const ValueKey('medication-editor')), findsOneWidget);
  await h.capture('medications-editor');
  await popRoute();
  await mountMeds(brightness: Brightness.dark);
  await tapVisible(
    find.text('Medikament hinzufügen'),
    find.byKey(const ValueKey('medication-main')),
  );
  expect(find.byKey(const ValueKey('medication-editor')), findsOneWidget);
  await h.capture('medications-editor-dark');
  repo = await mountMeds();
  await tapVisible(
    find.text('Medikament hinzufügen'),
    find.byKey(const ValueKey('medication-main')),
  );
  final name = find.byKey(const ValueKey('medication-name'));
  await ensureFullyInSafeViewport(
    find.byKey(const ValueKey('medication-editor')),
    name,
  );
  await enterFocused(name, 'Zink');
  await tester.tap(find.widgetWithText(OBAction, 'Speichern'));
  await pumpAfterTap();
  await pumpUntil(
    () => find.byKey(const ValueKey('medication-main')).evaluate().isNotEmpty,
    'Create did not return to medications main.',
  );
  expect(
    find.descendant(
      of: find.byKey(const ValueKey('medication-main')),
      matching: find.text('Zink'),
    ),
    findsNothing,
  );
  final created = [
    for (final p in await repo.readMedicationPlans(activeOnly: true))
      if (p.name == 'Zink') p,
  ];
  expect(created, isNotEmpty);
  expect(created.single.schedule, isEmpty);
  await tapVisible(
    find.text('Pläne verwalten'),
    find.byKey(const ValueKey('medication-main')),
  );
  await tapVisible(
    find.text('Zink'),
    find.byKey(const ValueKey('medication-plans')),
  );
  expect(find.text('Plan bearbeiten'), findsOneWidget);
  expect(
    tester
        .widget<TextField>(find.byKey(const ValueKey('medication-name')))
        .controller!
        .text,
    'Zink',
  );
  await h.capture('medications-edit-plan');
  await popRoute();
  await tapVisible(
    find.text('Zink'),
    find.byKey(const ValueKey('medication-plans')),
  );
  await tester.tap(find.text('Plan beenden'));
  await pumpAfterTap();
  await tapVisible(
    find.text('Beendete Pläne'),
    find.byKey(const ValueKey('medication-plans')),
  );
  expect(find.byKey(const ValueKey('medication-ended')), findsOneWidget);
  expect(find.text('Zink'), findsOneWidget);
  await h.capture('medications-ended');
  await tester.tap(find.text('Zink'));
  await pumpAfterTap();
  expect(find.text('Plan fortsetzen'), findsWidgets);
  await h.capture('medications-restart');
  await tester.tap(find.widgetWithText(OBAction, 'Plan fortsetzen'));
  await pumpAfterTap();

  Future<MedicationPlan> planA() async {
    return (await repo.readMedicationPlans(
      activeOnly: true,
    )).firstWhere((p) => p.name == 'Präparat A');
  }

  Future<void> openPlanATime() async {
    await tapVisible(
      find.text('Pläne verwalten'),
      find.byKey(const ValueKey('medication-main')),
    );
    await tapVisible(
      find.text('Präparat A'),
      find.byKey(const ValueKey('medication-plans')),
    );
    await tester.tap(find.text('08:00'));
    await pumpAfterTap();
    expect(find.byKey(const ValueKey('medication-time')), findsOneWidget);
  }

  Finder mondaySwitch() => find.descendant(
    of: find.ancestor(
      of: find.text('Montag'),
      matching: find.byType(OBSettingsToggleRow),
    ),
    matching: find.byType(CupertinoSwitch),
  );

  repo = await mountMeds();
  final originalA = await planA();
  expect(originalA.schedule.single.minuteOfDay, 8 * 60);
  expect(originalA.schedule.single.weekdays, isEmpty);
  await openPlanATime();
  expect(find.text('Montag'), findsOneWidget);
  await h.capture('medications-time');
  final timePage = find.byKey(const ValueKey('medication-time'));
  await ensureFullyInSafeViewport(timePage, find.text('Montag'));
  expect(tester.widget<CupertinoSwitch>(mondaySwitch()).value, isTrue);
  await tester.tap(mondaySwitch().hitTestable());
  await pumpAfterTap();
  expect(tester.widget<CupertinoSwitch>(mondaySwitch()).value, isFalse);
  await popRoute();
  expect(find.byKey(const ValueKey('medication-editor')), findsOneWidget);
  expect(find.text('08:00'), findsOneWidget);
  expect((await planA()).schedule.single.weekdays, isEmpty);
  await tester.tap(find.text('08:00'));
  await pumpAfterTap();
  await ensureFullyInSafeViewport(
    find.byKey(const ValueKey('medication-time')),
    find.text('Montag'),
  );
  expect(tester.widget<CupertinoSwitch>(mondaySwitch()).value, isTrue);
  await tester.tap(mondaySwitch().hitTestable());
  await pumpAfterTap();
  await tester.tap(find.widgetWithText(OBAction, 'Speichern'));
  await pumpAfterTap();
  expect(find.byKey(const ValueKey('medication-editor')), findsOneWidget);
  expect((await planA()).schedule.single.weekdays, isEmpty);
  expect((await planA()).schedule.single.minuteOfDay, 8 * 60);

  await mountMeds(brightness: Brightness.dark);
  await openPlanATime();
  await h.capture('medications-time-dark');
  await tester.tap(find.widgetWithText(OBAction, 'Speichern'));
  await pumpAfterTap();
  expect(find.byKey(const ValueKey('medication-editor')), findsOneWidget);
  expect((await planA()).schedule.single.weekdays, isEmpty);

  // Empty / no-slot / read error.
  repo = await loadRepo();
  repo.transformPlans = (_) => const [];
  repo.transformDay = (snap) => MedicationDay(day: snap.day);
  await mountMeds(repository: repo);
  expect(find.text('Keine Medikamente'), findsOneWidget);
  expect(find.text('Keine Einnahme geplant'), findsNothing);
  await h.capture('medications-empty');
  await mountMeds(repository: repo, brightness: Brightness.dark);
  expect(find.text('Keine Medikamente'), findsOneWidget);
  await h.capture('medications-empty-dark');

  repo = await loadRepo();
  repo.transformDay = (snap) => MedicationDay(day: snap.day);
  await mountMeds(repository: repo);
  expect(find.text('Keine Einnahme geplant'), findsOneWidget);
  expect(find.text('Keine Medikamente'), findsNothing);
  await h.capture('medications-no-slot');

  repo = await loadRepo();
  repo.failMedicationRead = true;
  await mountMeds(repository: repo);
  expect(
    find.text('Medikamente konnten nicht geladen werden.'),
    findsOneWidget,
  );
  expect(find.text('Keine Medikamente'), findsNothing);
  await h.capture('medications-error');
  repo.failMedicationRead = false;
  await tester.tap(find.text('Erneut versuchen'));
  await pumpAfterTap();
  expect(find.text('Präparat A'), findsOneWidget);

  // Save failure keeps draft.
  repo = await loadRepo();
  repo.failMedicationWrite = true;
  await mountMeds(repository: repo);
  await tapVisible(
    find.text('Präparat A'),
    find.byKey(const ValueKey('medication-main')),
  );
  await tester.tap(find.text('Genommen'));
  await pumpAfterTap();
  final note = find.byKey(const ValueKey('medication-note'));
  await ensureFullyInSafeViewport(
    find.byKey(const ValueKey('medication-record')),
    note,
  );
  await enterFocused(note, 'Notiz');
  await tester.tap(find.widgetWithText(OBAction, 'Speichern'));
  await pumpAfterTap();
  expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
  expect(tester.widget<TextField>(note).controller!.text, 'Notiz');
  expect(find.text('Einnahme'), findsOneWidget);
  await h.capture('medications-save-error');
  await mountMeds(repository: repo, brightness: Brightness.dark);
  await tapVisible(
    find.text('Präparat A'),
    find.byKey(const ValueKey('medication-main')),
  );
  await tester.tap(find.text('Genommen'));
  await pumpAfterTap();
  await tester.tap(find.widgetWithText(OBAction, 'Speichern'));
  await pumpAfterTap();
  expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
  await h.capture('medications-save-error-dark');

  // Reminder failure retries refresh only.
  repo = await loadRepo();
  repo.failMedicationReminders = true;
  await mountMeds(repository: repo);
  await tapVisible(
    find.text('Präparat A'),
    find.byKey(const ValueKey('medication-main')),
  );
  await tester.tap(find.text('Genommen'));
  await pumpAfterTap();
  final savesBefore = repo.entrySaves;
  final refreshesBefore = repo.reminderRefreshes;
  await tester.tap(find.widgetWithText(OBAction, 'Speichern'));
  await pumpAfterTap();
  expect(repo.entrySaves, savesBefore + 1);
  expect(repo.reminderRefreshes, greaterThan(refreshesBefore));
  expect(
    find.text('Gespeichert · Erinnerungen nicht aktualisiert'),
    findsOneWidget,
  );
  await h.capture('medications-reminder-error');
  repo.failMedicationReminders = false;
  final refreshesAfterSave = repo.reminderRefreshes;
  await tester.tap(find.text('Erneut versuchen'));
  await pumpAfterTap();
  expect(repo.entrySaves, savesBefore + 1);
  expect(repo.reminderRefreshes, greaterThan(refreshesAfterSave));
  expect(
    find.text('Gespeichert · Erinnerungen nicht aktualisiert'),
    findsNothing,
  );

  repo = await loadRepo();
  repo.transformDay = (snap) =>
      MedicationDay(day: snap.day, entries: snap.entries, unreadableCount: 2);
  await mountMeds(repository: repo);
  expect(find.text('Nicht alle Einträge lesbar'), findsOneWidget);
  expect(find.text('Präparat A'), findsOneWidget);
  await h.capture('medications-partial');
  await mountMeds(repository: repo, brightness: Brightness.dark);
  expect(find.text('Nicht alle Einträge lesbar'), findsOneWidget);
  await h.capture('medications-partial-dark');

  repo = await loadRepo();
  await repo.saveMedicationPlan(
    MedicationPlanDraft(
      create: true,
      name: 'Präparat DST',
      doseValue: 1,
      doseUnit: 'Tablette',
      schedule: const [MedicationScheduleSlot(minuteOfDay: 2 * 60 + 30)],
    ),
    now: DateTime(2026, 10, 1, 8),
  );
  const dstDay = '2026-10-25';
  final dstNow = DateTime(2026, 10, 25, 9, 41);
  await mountMeds(repository: repo, onDay: dstDay, clock: dstNow);
  expect(find.text('02:30'), findsOneWidget);
  expect(find.text('Uhrzeit nicht eindeutig'), findsOneWidget);
  await h.capture('medications-dst');
  await mountMeds(
    repository: repo,
    brightness: Brightness.dark,
    onDay: dstDay,
    clock: dstNow,
  );
  expect(find.text('02:30'), findsOneWidget);
  expect(find.text('Uhrzeit nicht eindeutig'), findsOneWidget);
  await h.capture('medications-dst-dark');

  Future<void> captureScaled({
    required String name,
    required Future<void> Function() open,
    Brightness brightness = Brightness.light,
  }) async {
    await mountMeds(brightness: brightness, scale: 2);
    await open();
    await h.capture(name);
  }

  await captureScaled(
    name: 'medications-main-2x',
    open: () async {
      final page = find.byKey(const ValueKey('medication-main'));
      await ensureFullyInSafeViewport(page, find.text('Präparat A'));
      await ensureFullyInSafeViewport(page, find.text('Verlauf'));
      await scrollListToMin(page);
    },
  );
  Future<void> openTakenRecord() async {
    await tapVisible(
      find.text('Präparat A'),
      find.byKey(const ValueKey('medication-main')),
    );
    expect(find.text('Einnahme'), findsOneWidget);
    await tester.tap(find.text('Genommen'));
    await pumpAfterTap();
    final record = find.byKey(const ValueKey('medication-record'));
    await ensureFullyInSafeViewport(record, find.text('09:41'));
    expect(find.text('09:41'), findsOneWidget);
    expect(find.textContaining('2026'), findsWidgets);
  }

  await captureScaled(name: 'medications-record-2x', open: openTakenRecord);
  await ensureFullyInSafeViewport(
    find.byKey(const ValueKey('medication-record')),
    find.widgetWithText(OBAction, 'Speichern'),
  );
  await h.capture('medications-record-2x-save');
  await tester.tap(find.widgetWithText(OBAction, 'Speichern').hitTestable());
  await pumpAfterTap();
  expect(find.byKey(const ValueKey('medication-main')), findsOneWidget);
  expect(find.textContaining('Genommen 09:41'), findsOneWidget);

  await captureScaled(
    name: 'medications-record-2x-dark',
    brightness: Brightness.dark,
    open: openTakenRecord,
  );
  await ensureFullyInSafeViewport(
    find.byKey(const ValueKey('medication-record')),
    find.widgetWithText(OBAction, 'Speichern'),
  );
  await tester.tap(find.widgetWithText(OBAction, 'Speichern').hitTestable());
  await pumpAfterTap();
  expect(find.textContaining('Genommen 09:41'), findsOneWidget);
  await captureScaled(
    name: 'medications-main-2x-dark',
    brightness: Brightness.dark,
    open: () async {
      final page = find.byKey(const ValueKey('medication-main'));
      await ensureFullyInSafeViewport(page, find.text('Präparat A'));
      await scrollListToMin(page);
    },
  );
  await captureScaled(
    name: 'medications-editor-2x',
    open: () async {
      await tapVisible(
        find.text('Medikament hinzufügen'),
        find.byKey(const ValueKey('medication-main')),
      );
      expect(find.byKey(const ValueKey('medication-editor')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('medication-name')))
            .controller!
            .text,
        isEmpty,
      );
    },
  );
  await ensureFullyInSafeViewport(
    find.byKey(const ValueKey('medication-editor')),
    find.widgetWithText(OBAction, 'Speichern'),
  );
  await h.capture('medications-editor-2x-save');
  await tester.tap(find.widgetWithText(OBAction, 'Speichern').hitTestable());
  await pumpAfterTap();
  expect(find.byKey(const ValueKey('medication-editor')), findsOneWidget);
  expect(
    tester
        .widget<TextField>(find.byKey(const ValueKey('medication-name')))
        .controller!
        .text,
    isEmpty,
  );
  expect(find.byKey(const ValueKey('medication-main')), findsNothing);
  await captureScaled(
    name: 'medications-time-2x',
    open: () async {
      await tapVisible(
        find.text('Pläne verwalten'),
        find.byKey(const ValueKey('medication-main')),
      );
      await tapVisible(
        find.text('Präparat A'),
        find.byKey(const ValueKey('medication-plans')),
      );
      await tester.tap(find.text('08:00'));
      await pumpAfterTap();
      expect(find.byKey(const ValueKey('medication-time')), findsOneWidget);
      final time = find.byKey(const ValueKey('medication-time'));
      await ensureFullyInSafeViewport(time, find.text('Montag'));
      await ensureFullyInSafeViewport(
        time,
        find.widgetWithText(OBAction, 'Speichern'),
      );
      await scrollListToMin(time);
    },
  );
  await ensureFullyInSafeViewport(
    find.byKey(const ValueKey('medication-time')),
    find.widgetWithText(OBAction, 'Speichern'),
  );
  await tester.tap(find.widgetWithText(OBAction, 'Speichern').hitTestable());
  await pumpAfterTap();
  expect(find.byKey(const ValueKey('medication-editor')), findsOneWidget);
}
