part of 'harness.dart';

Future<void> reviewCycle(ReviewHarness h) async {
  final tester = h.tester;
  final now = DateTime(2026, 9, 15, 9, 41);
  const day = SyntheticOpenBandRepository.cycleFixtureDay;
  const longNote =
      'Sehr lange Notiz über Krämpfe, Müdigkeit, Blähungen und den restlichen Tag, damit Tastatur und 2×-Layout wirklich scrollen müssen.';

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

  Future<void> dismissCycleNote(Finder page) async {
    final listRect = tester.getRect(downScrollable(page).first);
    final safe = reviewSafeViewport(contentOf: page);
    final keyboardTop =
        tester.view.physicalSize.height / tester.view.devicePixelRatio -
        keyboardInset();
    final left = listRect.left < safe.left ? safe.left : listRect.left;
    final top = listRect.top < safe.top ? safe.top : listRect.top;
    final right = listRect.right > safe.right ? safe.right : listRect.right;
    var bottom = listRect.bottom;
    if (bottom > safe.bottom) bottom = safe.bottom;
    if (bottom > keyboardTop) bottom = keyboardTop;
    final visible = Rect.fromLTRB(left, top, right, bottom);
    expect(visible.width, greaterThan(16));
    expect(visible.height, greaterThan(8));
    final point = Offset(listRect.left + 4, visible.center.dy);
    final field = tester.getRect(find.byKey(const ValueKey('cycle-note')));
    expect(point.dx, greaterThanOrEqualTo(listRect.left));
    expect(point.dx, lessThan(listRect.left + 16));
    expect(listRect.contains(point), isTrue);
    expect(visible.contains(point), isTrue);
    expect(field.contains(point), isFalse);
    expect(point.dy, lessThan(keyboardTop));
    await tester.tapAt(point);
    await tester.pump();
    await waitKeyboardInset(open: false);
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

  Finder undoNoticeAction(String label) => find.descendant(
    of: find.byType(SnackBar),
    matching: find.widgetWithText(TextButton, label),
  );

  Future<void> expectUndoNotice(String message, String action) async {
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.byType(SnackBarAction), findsNothing);
    expect(
      find.descendant(of: find.byType(SnackBar), matching: find.text(message)),
      findsOneWidget,
    );
    expect(undoNoticeAction(action), findsOneWidget);
  }

  Future<void> tapUndoNotice(String label) async {
    await tester.tap(undoNoticeAction(label).hitTestable());
    await pumpAfterTap();
  }

  Finder toggleSwitch(String label) => find.descendant(
    of: find.ancestor(
      of: find.text(label),
      matching: find.byType(OBSettingsToggleRow),
    ),
    matching: find.byType(CupertinoSwitch),
  );

  Future<_CycleReviewRepo> mountCycle({
    Brightness brightness = Brightness.light,
    double scale = 1,
    _CycleReviewRepo? repository,
    String? onDay,
    DateTime? clock,
    bool settingsOnly = false,
  }) async {
    final repo = repository ?? await loadRepo();
    await tester.pumpWidget(
      reviewHost(
        brightness: brightness,
        scale: scale,
        home: OpenBandCycle(
          repository: repo,
          day: onDay ?? day,
          now: () => clock ?? now,
          synthetic: true,
          settingsOnly: settingsOnly,
        ),
      ),
    );
    final key = settingsOnly ? 'cycle-settings' : 'cycle-overview';
    await pumpUntil(
      () =>
          find.byKey(ValueKey(key)).evaluate().isNotEmpty ||
          find.text('Daten nicht geladen').evaluate().isNotEmpty,
      'Cycle ${settingsOnly ? 'settings' : 'main'} did not load.',
    );
    return repo;
  }

  Future<OpenBandController> mountJournal({
    required _CycleReviewRepo repository,
    Brightness brightness = Brightness.light,
    double scale = 1,
    String? onDay,
  }) async {
    final journal = OpenBandController(
      repository: repository,
      initialDay: onDay ?? day,
      band: repository.band,
      now: () => now,
    );
    await journal.refresh();
    await tester.pumpWidget(
      reviewHost(
        brightness: brightness,
        scale: scale,
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
    return journal;
  }

  Future<void> expectMainFixture() async {
    final page = find.byKey(const ValueKey('cycle-overview'));
    expect(find.text('Zyklus'), findsWidgets);
    expect(find.text('Tag 23'), findsOneWidget);
    expect(find.text('Beginn · 24. August'), findsOneWidget);
    expect(find.text('Nächster Beginn · geschätzt'), findsOneWidget);
    expect(find.text('17.–25. Sept.'), findsOneWidget);
    expect(find.text('3 bisherige Abstände'), findsOneWidget);
    expect(find.text('Beginn eintragen'), findsOneWidget);
    await ensureFullyInSafeViewport(page, find.text('Messwerte'));
    await ensureFullyInSafeViewport(page, find.text('Verlauf'));
    await ensureFullyInSafeViewport(page, find.text('Einstellungen'));
    expect(
      tester
          .getTopLeft(
            find.descendant(of: page, matching: find.text('Messwerte')),
          )
          .dy,
      lessThan(
        tester
            .getTopLeft(
              find.descendant(of: page, matching: find.text('Verlauf')),
            )
            .dy,
      ),
    );
    await ensureFullyInSafeViewport(page, find.text('Synthetische Daten'));
  }

  Finder cycleChoiceSheet() =>
      find.byWidgetPredicate((widget) => widget is OBSettingsChoiceSheet);

  Future<void> expectSituationSelected(String label) async {
    expect(cycleChoiceSheet(), findsOneWidget);
    final rows = tester
        .widgetList<OBSettingsChoiceRow>(
          find.descendant(
            of: cycleChoiceSheet(),
            matching: find.byType(OBSettingsChoiceRow),
          ),
        )
        .toList();
    expect(rows, isNotEmpty);
    for (final row in rows) {
      if (row.label == label) {
        expect(row.selected, isTrue);
        expect(
          tester
              .getSemantics(find.text(row.label).last)
              .flagsCollection
              .isSelected
              .toBoolOrNull(),
          isTrue,
        );
      } else {
        expect(row.selected, isFalse);
      }
    }
  }

  // Journal enabled entry and selected-day navigation.
  var repo = await loadRepo();
  var journal = await mountJournal(repository: repo);
  final journalPage = find.byType(OpenBandJournal);
  final journalEntry = find.byKey(const ValueKey('cycle-journal'));
  await ensureFullyInSafeViewport(journalPage, journalEntry);
  expect(journalEntry.hitTestable(), findsOneWidget);
  expect(find.text('Zyklus'), findsWidgets);
  await h.capture('cycle-journal-entry');
  await tester.tap(journalEntry.hitTestable());
  await pumpAfterTap();
  await pumpUntil(
    () => find.byKey(const ValueKey('cycle-overview')).evaluate().isNotEmpty,
    'Cycle did not open from Journal.',
  );
  await expectMainFixture();
  expect(
    find.text(DateFormat('EEE, d. MMM', 'de_DE').format(DateTime.parse(day))),
    findsOneWidget,
  );
  await h.capture('cycle-journal');
  await popRoute();
  await pumpUntil(
    () => find.byType(OpenBandJournal).evaluate().isNotEmpty,
    'Journal route did not return.',
  );
  expect(find.byKey(const ValueKey('cycle-journal')), findsOneWidget);
  journal.dispose();

  repo = await loadRepo();
  journal = await mountJournal(repository: repo, brightness: Brightness.dark);
  await ensureFullyInSafeViewport(
    find.byType(OpenBandJournal),
    find.byKey(const ValueKey('cycle-journal')),
  );
  await h.capture('cycle-journal-entry-dark');
  await tester.tap(find.byKey(const ValueKey('cycle-journal')).hitTestable());
  await pumpAfterTap();
  await pumpUntil(
    () => find.byKey(const ValueKey('cycle-overview')).evaluate().isNotEmpty,
    'Cycle dark did not open from Journal.',
  );
  await h.capture('cycle-journal-dark');
  journal.dispose();

  repo = await loadRepo();
  repo.failCycleSettingsRead = true;
  journal = await mountJournal(repository: repo);
  final journalErrorRow = find.byKey(const ValueKey('cycle-journal'));
  await ensureFullyInSafeViewport(
    find.byType(OpenBandJournal),
    journalErrorRow,
  );
  expect(journalErrorRow, findsOneWidget);
  expect(journalErrorRow.hitTestable(), findsOneWidget);
  expect(
    find.descendant(of: journalErrorRow, matching: find.text('—')),
    findsOneWidget,
  );
  final settingsReadsBeforeRetry = repo.settingsReads;
  await h.capture('cycle-journal-error');
  await tester.tap(journalErrorRow.hitTestable());
  await pumpAfterTap();
  expect(find.byKey(const ValueKey('cycle-journal')), findsOneWidget);
  expect(
    find.descendant(
      of: find.byKey(const ValueKey('cycle-journal')),
      matching: find.text('—'),
    ),
    findsOneWidget,
  );
  expect(find.byKey(const ValueKey('cycle-overview')), findsNothing);
  expect(repo.settingsReads, greaterThan(settingsReadsBeforeRetry));
  repo.failCycleSettingsRead = false;
  repo.failCycleLogRead = true;
  await tester.tap(find.byKey(const ValueKey('cycle-journal')).hitTestable());
  await pumpAfterTap();
  await tester.tap(find.byKey(const ValueKey('cycle-journal')).hitTestable());
  await pumpAfterTap();
  await pumpUntil(
    () => find.text('Daten nicht geladen').evaluate().isNotEmpty,
    'Journal retry did not reach cycle read-error.',
  );
  expect(find.text('Erneut versuchen'), findsOneWidget);
  expect(find.byKey(const ValueKey('cycle-journal')), findsNothing);
  journal.dispose();

  repo = await loadRepo();
  repo.failCycleSettingsRead = true;
  journal = await mountJournal(repository: repo, brightness: Brightness.dark);
  await ensureFullyInSafeViewport(
    find.byType(OpenBandJournal),
    find.byKey(const ValueKey('cycle-journal')),
  );
  expect(find.byKey(const ValueKey('cycle-journal')), findsOneWidget);
  expect(
    find.descendant(
      of: find.byKey(const ValueKey('cycle-journal')),
      matching: find.text('—'),
    ),
    findsOneWidget,
  );
  await h.capture('cycle-journal-error-dark');
  journal.dispose();

  // Disabled setup, then enable/save reflected in Journal and main.
  repo = await loadRepo();
  repo.cycleSettings = const CycleSettings(
    enabled: false,
    estimatesEnabled: false,
    lengthReviewEnabled: false,
  );
  journal = await mountJournal(repository: repo);
  expect(find.byKey(const ValueKey('cycle-journal')), findsNothing);
  await h.capture('cycle-journal-disabled');
  journal.dispose();

  await mountCycle(repository: repo, settingsOnly: true);
  expect(find.byKey(const ValueKey('cycle-settings')), findsOneWidget);
  expect(
    tester.widget<CupertinoSwitch>(toggleSwitch('Zyklus im Journal')).value,
    isFalse,
  );
  await h.capture('cycle-setup');
  await tester.tap(toggleSwitch('Zyklus im Journal'));
  await pumpAfterTap();
  expect(
    tester.widget<CupertinoSwitch>(toggleSwitch('Zyklus im Journal')).value,
    isTrue,
  );
  expect(repo.cycleSettings.enabled, isTrue);
  expect(repo.settingsWrites, 1);
  await h.capture('cycle-setup-saved');

  journal = await mountJournal(repository: repo);
  await ensureFullyInSafeViewport(
    find.byType(OpenBandJournal),
    find.byKey(const ValueKey('cycle-journal')),
  );
  expect(find.byKey(const ValueKey('cycle-journal')), findsOneWidget);
  await h.capture('cycle-journal-after-enable');
  await tester.tap(find.byKey(const ValueKey('cycle-journal')).hitTestable());
  await pumpAfterTap();
  await pumpUntil(
    () => find.byKey(const ValueKey('cycle-overview')).evaluate().isNotEmpty,
    'Cycle did not open after enabling.',
  );
  expect(find.text('Tag 23'), findsOneWidget);
  await h.capture('cycle-main-after-enable');
  journal.dispose();

  repo = await loadRepo();
  repo.cycleSettings = const CycleSettings(
    enabled: false,
    estimatesEnabled: false,
    lengthReviewEnabled: false,
  );
  await mountCycle(
    repository: repo,
    settingsOnly: true,
    brightness: Brightness.dark,
  );
  expect(
    tester.widget<CupertinoSwitch>(toggleSwitch('Zyklus im Journal')).value,
    isFalse,
  );
  await h.capture('cycle-setup-dark');

  // Settings closed; situation picker runs last so a sheet-API
  // mismatch cannot drop the rest of the flow.
  repo = await loadRepo();
  await mountCycle(repository: repo, settingsOnly: true);
  expect(
    tester.widget<CupertinoSwitch>(toggleSwitch('Zyklus im Journal')).value,
    isTrue,
  );
  expect(
    tester.widget<CupertinoSwitch>(toggleSwitch('Zeitschätzung')).value,
    isTrue,
  );
  expect(find.text('Keine Angabe'), findsOneWidget);
  await h.capture('cycle-settings');
  await mountCycle(
    repository: repo,
    settingsOnly: true,
    brightness: Brightness.dark,
  );
  await h.capture('cycle-settings-dark');

  // Info.
  repo = await loadRepo();
  await mountCycle(repository: repo);
  await tester.tap(find.byTooltip('Information'));
  await pumpAfterTap();
  expect(find.text('Zyklus'), findsWidgets);
  expect(
    find.text(
      'Die Zeitschätzung nutzt den Median deiner eingetragenen Abstände. '
      'Die Spanne zeigt deren bisherige Streuung.',
    ),
    findsOneWidget,
  );
  expect(
    find.text(
      'Fehlende Einträge können die Schätzung verändern. '
      'Abstände über 60 Tage bleiben offen. Ein Eisprung wird nicht bestimmt.',
    ),
    findsOneWidget,
  );
  expect(
    find.text('Starts und Beobachtungen gelten für das gewählte Datum.'),
    findsNothing,
  );
  await h.capture('cycle-info');
  await tester.tap(find.text('Schließen'));
  await pumpAfterTap();
  await mountCycle(repository: repo, brightness: Brightness.dark);
  await tester.tap(find.byTooltip('Information'));
  await pumpAfterTap();
  await h.capture('cycle-info-dark');
  await tester.tap(find.text('Schließen'));
  await pumpAfterTap();

  // Main / empty / first start / withheld estimate / read error / partial.
  repo = await loadRepo();
  await mountCycle(repository: repo);
  await expectMainFixture();
  await scrollListToMin(find.byKey(const ValueKey('cycle-overview')));
  await h.capture('cycle-main');
  await tester.tap(find.byTooltip('Datum'));
  await pumpAfterTap();
  expect(find.text('Übernehmen'), findsOneWidget);
  await h.capture('cycle-day-picker');
  await tester.tap(find.bySemanticsLabel('Montag, 14. September 2026'));
  await pumpAfterTap();
  await tester.tap(find.widgetWithText(OBAction, 'Übernehmen'));
  await pumpAfterTap();
  expect(
    find.text(DateFormat('EEE, d. MMM', 'de_DE').format(DateTime(2026, 9, 14))),
    findsOneWidget,
  );
  expect(find.text('Tag 22'), findsOneWidget);
  await h.capture('cycle-day-picked');

  await mountCycle(repository: repo, brightness: Brightness.dark);
  await expectMainFixture();
  await h.capture('cycle-main-dark');
  await tester.tap(find.byTooltip('Datum'));
  await pumpAfterTap();
  expect(find.text('Übernehmen'), findsOneWidget);
  expect(find.text('Datum'), findsWidgets);
  await h.capture('cycle-day-picker-dark');
  await popRoute();

  repo = await loadRepo();
  repo.clearCycleLogs();
  await mountCycle(repository: repo);
  expect(find.text('—'), findsOneWidget);
  expect(find.text('Noch kein Beginn'), findsOneWidget);
  expect(find.text('Nächster Beginn · geschätzt'), findsNothing);
  await h.capture('cycle-empty');
  await mountCycle(repository: repo, brightness: Brightness.dark);
  expect(find.text('Noch kein Beginn'), findsOneWidget);
  await h.capture('cycle-empty-dark');

  repo = await loadRepo();
  repo.clearCycleLogs();
  repo.seedCycleStart(const CycleStart(date: day, kind: kCycleStartKind));
  await mountCycle(repository: repo);
  expect(find.text('Tag 1'), findsOneWidget);
  expect(find.text('Beginn · 15. September'), findsOneWidget);
  expect(find.text('Beginn bearbeiten'), findsOneWidget);
  expect(find.text('Nächster Beginn · geschätzt'), findsNothing);
  await h.capture('cycle-first-start');
  await mountCycle(repository: repo, brightness: Brightness.dark);
  expect(find.text('Tag 1'), findsOneWidget);
  await h.capture('cycle-first-start-dark');

  repo = await loadRepo();
  repo.clearCycleLogs();
  repo.seedCycleStart(
    const CycleStart(date: '2026-06-01', kind: kCycleStartKind),
  );
  repo.seedCycleStart(
    const CycleStart(date: '2026-08-24', kind: kCycleStartKind),
  );
  await mountCycle(repository: repo);
  expect(find.text('Tag 23'), findsOneWidget);
  expect(find.text('Schätzung offen'), findsOneWidget);
  expect(find.text('Abstand über 60 Tage'), findsOneWidget);
  await h.capture('cycle-estimate-open');
  await mountCycle(repository: repo, brightness: Brightness.dark);
  expect(find.text('Abstand über 60 Tage'), findsOneWidget);
  await h.capture('cycle-estimate-open-dark');

  repo = await loadRepo();
  repo.failCycleRead = true;
  await mountCycle(repository: repo);
  expect(find.text('Daten nicht geladen'), findsOneWidget);
  expect(find.text('Erneut versuchen'), findsOneWidget);
  await h.capture('cycle-read-error');
  repo.failCycleRead = false;
  await tester.tap(find.text('Erneut versuchen'));
  await pumpAfterTap();
  await expectMainFixture();
  await h.capture('cycle-read-error-retry');
  repo = await loadRepo();
  repo.failCycleRead = true;
  await mountCycle(repository: repo, brightness: Brightness.dark);
  expect(find.text('Daten nicht geladen'), findsOneWidget);
  await h.capture('cycle-read-error-dark');

  repo = await loadRepo();
  repo.clearCycleLogs();
  repo.seedUnreadableCycleStart({'date': '2026-08-24', 'kind': 1});
  await mountCycle(repository: repo);
  expect(find.text('—'), findsOneWidget);
  expect(find.text('Einträge teilweise lesbar'), findsOneWidget);
  expect(find.text('Tag 23'), findsNothing);
  expect(find.text('Starts nicht lesbar'), findsNothing);
  expect(find.text('Noch kein Beginn'), findsNothing);
  expect(find.text('Schätzung offen'), findsNothing);
  await h.capture('cycle-partial');
  await mountCycle(repository: repo, brightness: Brightness.dark);
  expect(find.text('—'), findsOneWidget);
  expect(find.text('Einträge teilweise lesbar'), findsOneWidget);
  await h.capture('cycle-partial-dark');

  repo = await loadRepo();
  repo.seedUnreadableCycleStart({'date': '2026-05-01', 'kind': 1});
  repo.cycleSettings = const CycleSettings(
    enabled: true,
    estimatesEnabled: false,
    lengthReviewEnabled: false,
  );
  await mountCycle(repository: repo);
  expect(find.text('—'), findsOneWidget);
  expect(find.text('Tag 23'), findsNothing);
  expect(find.textContaining('Tag '), findsNothing);

  // History: observation and start distinct.
  repo = await loadRepo();
  repo.seedCycleObservation(
    const CycleObservation(date: day, tags: ['cramps']),
  );
  await mountCycle(repository: repo);
  await tapVisible(
    find.text('Verlauf'),
    find.byKey(const ValueKey('cycle-overview')),
  );
  expect(find.byKey(const ValueKey('cycle-history')), findsOneWidget);
  expect(find.text('15. September'), findsOneWidget);
  expect(find.text('Krämpfe'), findsOneWidget);
  expect(find.text('24. August'), findsOneWidget);
  expect(find.text('31. Juli'), findsOneWidget);
  expect(find.text('29. Juni'), findsOneWidget);
  expect(find.text('1. Juni'), findsOneWidget);
  expect(find.text('Beginn'), findsNWidgets(4));
  await h.capture('cycle-history');
  await tester.tap(find.text('24. August'));
  await pumpAfterTap();
  expect(find.byKey(const ValueKey('cycle-start')), findsOneWidget);
  expect(find.text('Beginn'), findsWidgets);
  await popRoute();
  await tester.tap(find.text('15. September'));
  await pumpAfterTap();
  expect(find.byKey(const ValueKey('cycle-observation')), findsOneWidget);
  expect(find.text('Beobachtung'), findsOneWidget);
  await popRoute();
  await mountCycle(repository: repo, brightness: Brightness.dark);
  await tapVisible(
    find.text('Verlauf'),
    find.byKey(const ValueKey('cycle-overview')),
  );
  expect(find.text('Krämpfe'), findsOneWidget);
  expect(find.text('Beginn'), findsNWidgets(4));
  await h.capture('cycle-history-dark');

  // New start, keyboard, save failure retaining input, context-retry.
  repo = await loadRepo();
  await mountCycle(repository: repo);
  await tapVisible(
    find.text('Beginn eintragen'),
    find.byKey(const ValueKey('cycle-overview')),
  );
  expect(find.byKey(const ValueKey('cycle-start')), findsOneWidget);
  expect(find.text('15. Sept. 2026'), findsOneWidget);
  expect(find.text('Entfernen'), findsNothing);
  await h.capture('cycle-start');
  final note = find.byKey(const ValueKey('cycle-note'));
  await ensureFullyInSafeViewport(
    find.byKey(const ValueKey('cycle-start')),
    note,
  );
  await tester.tap(note);
  await tester.pump();
  await tester.showKeyboard(note);
  await tester.pump();
  await waitKeyboardInset(open: true);
  await tester.enterText(note, 'Heute begonnen');
  await tester.pump();
  expect(tester.widget<TextField>(note).controller!.text, 'Heute begonnen');
  await h.capture('cycle-start-keyboard');
  await dismissCycleNote(find.byKey(const ValueKey('cycle-start')));
  repo.failCycleWrite = true;
  final writesBeforeFail = repo.startWrites;
  await tester.tap(find.widgetWithText(OBAction, 'Speichern'));
  await pumpAfterTap();
  expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
  expect(tester.widget<TextField>(note).controller!.text, 'Heute begonnen');
  expect(find.byKey(const ValueKey('cycle-start')), findsOneWidget);
  await h.capture('cycle-save-error');
  repo.failCycleWrite = false;
  await tester.tap(find.widgetWithText(OBAction, 'Speichern'));
  await pumpAfterTap();
  await pumpUntil(
    () => find.byKey(const ValueKey('cycle-overview')).evaluate().isNotEmpty,
    'Start save retry did not return to main.',
  );
  expect(repo.startWrites, writesBeforeFail + 2);
  expect(find.text('Beginn bearbeiten'), findsOneWidget);
  expect(find.text('Tag 1'), findsOneWidget);
  await h.capture('cycle-start-saved');

  await mountCycle(repository: await loadRepo(), brightness: Brightness.dark);
  await tapVisible(
    find.text('Beginn eintragen'),
    find.byKey(const ValueKey('cycle-overview')),
  );
  await h.capture('cycle-start-dark');
  repo = await loadRepo();
  repo.failCycleWrite = true;
  await mountCycle(repository: repo, brightness: Brightness.dark);
  await tapVisible(
    find.text('Beginn eintragen'),
    find.byKey(const ValueKey('cycle-overview')),
  );
  await tester.enterText(
    find.byKey(const ValueKey('cycle-note')),
    'Heute begonnen',
  );
  await tester.pump();
  await tester.tap(find.widgetWithText(OBAction, 'Speichern'));
  await pumpAfterTap();
  expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
  expect(
    tester
        .widget<TextField>(find.byKey(const ValueKey('cycle-note')))
        .controller!
        .text,
    'Heute begonnen',
  );
  await h.capture('cycle-save-error-dark');

  repo = await loadRepo();
  repo.failCycleContextRefresh = true;
  await mountCycle(repository: repo);
  await tapVisible(
    find.text('Beginn eintragen'),
    find.byKey(const ValueKey('cycle-overview')),
  );
  await tester.enterText(
    find.byKey(const ValueKey('cycle-note')),
    'Refresh note',
  );
  await tester.pump();
  await tester.tap(find.widgetWithText(OBAction, 'Speichern'));
  await pumpAfterTap();
  final savedNote = find.byKey(const ValueKey('cycle-note'));
  expect(
    find.text('Gespeichert · Aktualisieren fehlgeschlagen'),
    findsOneWidget,
  );
  expect(find.widgetWithText(OBAction, 'Erneut versuchen'), findsOneWidget);
  expect(find.widgetWithText(OBAction, 'Speichern'), findsNothing);
  expect(find.text('Entfernen'), findsNothing);
  expect(tester.widget<TextField>(savedNote).enabled, isFalse);
  expect(tester.widget<TextField>(savedNote).controller!.text, 'Refresh note');
  expect(
    tester
        .widget<OBSettingsValueRow>(
          find.byWidgetPredicate(
            (w) => w is OBSettingsValueRow && w.label == 'Datum',
          ),
        )
        .onTap,
    isNull,
  );
  expect(find.byKey(const ValueKey('cycle-start')), findsOneWidget);
  expect(repo.startWrites, 1);
  final refreshesAfterFail = repo.contextRefreshes;
  await h.capture('cycle-context-error');
  repo.failCycleContextRefresh = false;
  await tester.tap(find.widgetWithText(OBAction, 'Erneut versuchen'));
  await pumpAfterTap();
  await pumpUntil(
    () => find.byKey(const ValueKey('cycle-overview')).evaluate().isNotEmpty,
    'Context retry did not return to main.',
  );
  expect(repo.startWrites, 1);
  expect(repo.contextRefreshes, greaterThan(refreshesAfterFail));
  expect(find.text('Beginn bearbeiten'), findsOneWidget);
  await h.capture('cycle-context-retry');

  repo = await loadRepo();
  repo.failCycleContextRefresh = true;
  await mountCycle(repository: repo, brightness: Brightness.dark);
  await tapVisible(
    find.text('Beginn eintragen'),
    find.byKey(const ValueKey('cycle-overview')),
  );
  await tester.enterText(
    find.byKey(const ValueKey('cycle-note')),
    'Refresh note',
  );
  await tester.pump();
  await tester.tap(find.widgetWithText(OBAction, 'Speichern'));
  await pumpAfterTap();
  expect(
    find.text('Gespeichert · Aktualisieren fehlgeschlagen'),
    findsOneWidget,
  );
  expect(
    tester.widget<TextField>(find.byKey(const ValueKey('cycle-note'))).enabled,
    isFalse,
  );
  await h.capture('cycle-context-error-dark');

  // Edit existing, removal confirmation, exact undo, conflict/reload.
  repo = await loadRepo();
  await mountCycle(repository: repo);
  await tapVisible(
    find.text('Verlauf'),
    find.byKey(const ValueKey('cycle-overview')),
  );
  await tester.tap(find.text('24. August'));
  await pumpAfterTap();
  expect(find.byKey(const ValueKey('cycle-start')), findsOneWidget);
  expect(find.text('24. Aug. 2026'), findsOneWidget);
  expect(find.text('Entfernen'), findsOneWidget);
  await h.capture('cycle-edit');
  repo.seedCycleStart(
    const CycleStart(
      date: '2026-08-24',
      kind: kCycleStartKind,
      note: 'geändert',
    ),
  );
  await tester.enterText(find.byKey(const ValueKey('cycle-note')), 'lokal');
  await tester.pump();
  await tester.tap(find.widgetWithText(OBAction, 'Speichern'));
  await pumpAfterTap();
  expect(find.text('Eintrag wurde geändert'), findsOneWidget);
  expect(find.text('Neu laden'), findsOneWidget);
  expect(
    tester
        .widget<TextField>(find.byKey(const ValueKey('cycle-note')))
        .controller!
        .text,
    'lokal',
  );
  await h.capture('cycle-conflict');
  await tester.tap(find.text('Neu laden'));
  await pumpAfterTap();
  expect(find.text('Eintrag wurde geändert'), findsNothing);
  expect(
    tester
        .widget<TextField>(find.byKey(const ValueKey('cycle-note')))
        .controller!
        .text,
    'geändert',
  );
  await h.capture('cycle-conflict-reload');

  repo = await loadRepo();
  await mountCycle(repository: repo, brightness: Brightness.dark);
  await tapVisible(
    find.text('Verlauf'),
    find.byKey(const ValueKey('cycle-overview')),
  );
  await tester.tap(find.text('24. August'));
  await pumpAfterTap();
  await h.capture('cycle-edit-dark');

  repo = await loadRepo();
  await mountCycle(repository: repo);
  await tapVisible(
    find.text('Verlauf'),
    find.byKey(const ValueKey('cycle-overview')),
  );
  await tester.tap(find.text('24. August'));
  await pumpAfterTap();
  await tester.tap(find.widgetWithText(OBAction, 'Entfernen'));
  await pumpAfterTap();
  expect(find.text('Beginn 24. August entfernen?'), findsOneWidget);
  await h.capture('cycle-remove');
  await tester.tap(find.text('Entfernen').last);
  await pumpAfterTap();
  await pumpUntil(
    () => find.byKey(const ValueKey('cycle-history')).evaluate().isNotEmpty,
    'Remove did not return to history.',
  );
  await expectUndoNotice('Beginn 24. Aug. entfernt', 'Rückgängig');
  expect(repo.startRemoves, 1);
  await h.capture('cycle-undo');
  final restored = const CycleStart(date: '2026-08-24', kind: kCycleStartKind);
  await tapUndoNotice('Rückgängig');
  expect(repo.startRestores, 1);
  await popRoute();
  await pumpUntil(
    () => find.byKey(const ValueKey('cycle-overview')).evaluate().isNotEmpty,
    'History did not return to main after undo.',
  );
  expect(find.text('Tag 23'), findsOneWidget);
  expect(find.text('Beginn · 24. August'), findsOneWidget);
  final snap = await repo.readCycle(day, now: now);
  expect(snap.starts, contains(restored));
  await h.capture('cycle-undo-restored');

  // Overview remove, History roundtrip, exact undo restore.
  repo = await loadRepo();
  const overviewStart = CycleStart(
    date: day,
    kind: kCycleStartKind,
    note: 'overview',
  );
  repo.seedCycleStart(overviewStart);
  await mountCycle(repository: repo);
  await tapVisible(
    find.text('Beginn bearbeiten'),
    find.byKey(const ValueKey('cycle-overview')),
  );
  expect(find.byKey(const ValueKey('cycle-start')), findsOneWidget);
  expect(find.text('Entfernen'), findsOneWidget);
  expect(
    tester
        .widget<TextField>(find.byKey(const ValueKey('cycle-note')))
        .controller!
        .text,
    'overview',
  );
  await tester.tap(find.widgetWithText(OBAction, 'Entfernen'));
  await pumpAfterTap();
  expect(find.text('Beginn 15. September entfernen?'), findsOneWidget);
  final overviewRemoves = repo.startRemoves;
  final overviewRestores = repo.startRestores;
  await tester.tap(find.text('Entfernen').last);
  await pumpAfterTap();
  await pumpUntil(
    () =>
        find.byKey(const ValueKey('cycle-overview')).evaluate().isNotEmpty &&
        find.byKey(const ValueKey('cycle-start')).evaluate().isEmpty,
    'Overview remove did not return to main.',
  );
  await expectUndoNotice('Beginn 15. Sept. entfernt', 'Rückgängig');
  expect(repo.startRemoves, overviewRemoves + 1);
  expect(repo.startRestores, overviewRestores);
  await pumpUntil(
    () => find.text('Beginn eintragen').evaluate().isNotEmpty,
    'Overview remove did not refresh main.',
  );
  await tapVisible(
    find.text('Verlauf'),
    find.byKey(const ValueKey('cycle-overview')),
  );
  expect(find.byKey(const ValueKey('cycle-history')), findsOneWidget);
  expect(find.text('24. August'), findsOneWidget);
  expect(find.text('15. September'), findsNothing);
  expect(repo.startRemoves, overviewRemoves + 1);
  expect(repo.startRestores, overviewRestores);
  await popRoute();
  await pumpUntil(
    () => find.byKey(const ValueKey('cycle-overview')).evaluate().isNotEmpty,
    'History did not return to main after overview remove.',
  );
  await expectUndoNotice('Beginn 15. Sept. entfernt', 'Rückgängig');
  expect(repo.startRemoves, overviewRemoves + 1);
  expect(repo.startRestores, overviewRestores);
  await h.capture('cycle-overview-undo');
  await tapUndoNotice('Rückgängig');
  await pumpUntil(
    () => find.text('Beginn bearbeiten').evaluate().isNotEmpty,
    'Overview undo did not restore start.',
  );
  expect(repo.startRemoves, overviewRemoves + 1);
  expect(repo.startRestores, overviewRestores + 1);
  final overviewSnap = await repo.readCycle(day, now: now);
  expect(overviewSnap.starts, contains(overviewStart));

  repo = await loadRepo();
  await mountCycle(repository: repo);
  await tapVisible(
    find.text('Verlauf'),
    find.byKey(const ValueKey('cycle-overview')),
  );
  await tester.tap(find.text('24. August'));
  await pumpAfterTap();
  await tester.tap(find.widgetWithText(OBAction, 'Entfernen'));
  await pumpAfterTap();
  await tester.tap(find.text('Entfernen').last);
  await pumpAfterTap();
  await pumpUntil(
    () => find.byKey(const ValueKey('cycle-history')).evaluate().isNotEmpty,
    'Restore-conflict remove did not return to history.',
  );
  await expectUndoNotice('Beginn 24. Aug. entfernt', 'Rückgängig');
  repo.seedCycleStart(
    const CycleStart(date: '2026-08-24', kind: kCycleStartKind, note: 'fremd'),
  );
  await tapUndoNotice('Rückgängig');
  await expectUndoNotice('Beginn wurde geändert', 'Neu laden');
  expect(repo.startRestores, 1);
  final conflicted = await repo.readCycle(day, now: now);
  expect(
    conflicted.starts,
    contains(
      const CycleStart(
        date: '2026-08-24',
        kind: kCycleStartKind,
        note: 'fremd',
      ),
    ),
  );
  await h.capture('cycle-undo-conflict');
  await tapUndoNotice('Neu laden');
  expect(repo.startRestores, 1);
  expect(find.byType(SnackBarAction), findsNothing);
  expect(undoNoticeAction('Neu laden'), findsNothing);

  repo = await loadRepo();
  await mountCycle(repository: repo, brightness: Brightness.dark);
  await tapVisible(
    find.text('Verlauf'),
    find.byKey(const ValueKey('cycle-overview')),
  );
  await tester.tap(find.text('24. August'));
  await pumpAfterTap();
  await tester.tap(find.widgetWithText(OBAction, 'Entfernen'));
  await pumpAfterTap();
  expect(find.text('Beginn 24. August entfernen?'), findsOneWidget);
  await h.capture('cycle-remove-dark');
  await tester.tap(find.text('Entfernen').last);
  await pumpAfterTap();
  await pumpUntil(
    () => find.byKey(const ValueKey('cycle-history')).evaluate().isNotEmpty,
    'Dark remove did not return to history.',
  );
  await expectUndoNotice('Beginn 24. Aug. entfernt', 'Rückgängig');
  await h.capture('cycle-undo-dark');

  repo = await loadRepo();
  repo.failCycleContextRefresh = true;
  await mountCycle(repository: repo);
  await tapVisible(
    find.text('Verlauf'),
    find.byKey(const ValueKey('cycle-overview')),
  );
  await tester.tap(find.text('24. August'));
  await pumpAfterTap();
  await tester.tap(find.widgetWithText(OBAction, 'Entfernen'));
  await pumpAfterTap();
  final removesBefore = repo.startRemoves;
  final restoresBefore = repo.startRestores;
  final refreshesBeforeRemove = repo.contextRefreshes;
  await tester.tap(find.text('Entfernen').last);
  await pumpAfterTap();
  await pumpUntil(
    () => find.byKey(const ValueKey('cycle-history')).evaluate().isNotEmpty,
    'Remove wake did not return to history.',
  );
  expect(repo.startRemoves, removesBefore + 1);
  expect(repo.contextRefreshes, greaterThan(refreshesBeforeRemove));
  await expectUndoNotice('Beginn 24. Aug. entfernt', 'Rückgängig');
  expect(find.text('Entfernt · Aktualisieren fehlgeschlagen'), findsOneWidget);
  expect(
    find.text('Wiederhergestellt · Aktualisieren fehlgeschlagen'),
    findsNothing,
  );
  await h.capture('cycle-remove-context-error');
  await tapUndoNotice('Rückgängig');
  expect(repo.startRestores, restoresBefore + 1);
  expect(repo.startRemoves, removesBefore + 1);
  expect(
    find.text('Wiederhergestellt · Aktualisieren fehlgeschlagen'),
    findsOneWidget,
  );
  expect(find.text('Entfernt · Aktualisieren fehlgeschlagen'), findsNothing);
  await h.capture('cycle-restore-context-error');

  // Observation tags/note, keyboard, save.
  repo = await loadRepo();
  await mountCycle(repository: repo);
  await tapVisible(
    find.text('Beobachtung festhalten'),
    find.byKey(const ValueKey('cycle-overview')),
  );
  expect(find.byKey(const ValueKey('cycle-observation')), findsOneWidget);
  await h.capture('cycle-observation');
  await tapVisible(
    find.text('Krämpfe'),
    find.byKey(const ValueKey('cycle-observation')),
  );
  await tapVisible(
    find.text('Müdigkeit'),
    find.byKey(const ValueKey('cycle-observation')),
  );
  final obsNote = find.byKey(const ValueKey('cycle-note'));
  await ensureFullyInSafeViewport(
    find.byKey(const ValueKey('cycle-observation')),
    obsNote,
  );
  await tester.tap(obsNote);
  await tester.pump();
  await tester.showKeyboard(obsNote);
  await tester.pump();
  await waitKeyboardInset(open: true);
  await tester.enterText(obsNote, 'Leichte Krämpfe');
  await tester.pump();
  await h.capture('cycle-observation-keyboard');
  await dismissCycleNote(find.byKey(const ValueKey('cycle-observation')));
  await ensureFullyInSafeViewport(
    find.byKey(const ValueKey('cycle-observation')),
    find.widgetWithText(OBAction, 'Speichern'),
  );
  await tester.tap(find.widgetWithText(OBAction, 'Speichern').hitTestable());
  await pumpAfterTap();
  await pumpUntil(
    () => find.byKey(const ValueKey('cycle-overview')).evaluate().isNotEmpty,
    'Observation save did not return to main.',
  );
  expect(repo.observationWrites, 1);
  await tapVisible(
    find.text('Verlauf'),
    find.byKey(const ValueKey('cycle-overview')),
  );
  expect(find.text('Krämpfe'), findsOneWidget);
  await h.capture('cycle-observation-saved');

  await mountCycle(repository: await loadRepo(), brightness: Brightness.dark);
  await tapVisible(
    find.text('Beobachtung festhalten'),
    find.byKey(const ValueKey('cycle-overview')),
  );
  await h.capture('cycle-observation-dark');

  // 2x main / settings / observation and long-text scrolling.
  repo = await loadRepo();
  await mountCycle(repository: repo, scale: 2);
  final main2x = find.byKey(const ValueKey('cycle-overview'));
  await ensureFullyInSafeViewport(main2x, find.text('Tag 23'));
  await scrollListToMin(main2x);
  await h.capture('cycle-main-2x');
  await tester.tap(find.byTooltip('Datum'));
  await pumpAfterTap();
  final pickerPage = find.ancestor(
    of: find.widgetWithText(OBAction, 'Übernehmen'),
    matching: find.byType(Scaffold),
  );
  await ensureFullyInSafeViewport(
    pickerPage,
    find.widgetWithText(OBAction, 'Übernehmen'),
  );
  await h.capture('cycle-day-picker-2x-scrolled');
  await popRoute();

  await mountCycle(repository: repo, scale: 2, brightness: Brightness.dark);
  await scrollListToMin(find.byKey(const ValueKey('cycle-overview')));
  await h.capture('cycle-main-2x-dark');

  repo = await loadRepo();
  await mountCycle(repository: repo, settingsOnly: true, scale: 2);
  await ensureFullyInSafeViewport(
    find.byKey(const ValueKey('cycle-settings')),
    find.text('Situation'),
  );
  await h.capture('cycle-settings-2x');
  await mountCycle(
    repository: repo,
    settingsOnly: true,
    scale: 2,
    brightness: Brightness.dark,
  );
  await ensureFullyInSafeViewport(
    find.byKey(const ValueKey('cycle-settings')),
    find.text('Situation'),
  );
  await h.capture('cycle-settings-2x-dark');

  repo = await loadRepo();
  await mountCycle(repository: repo, scale: 2);
  await tapVisible(
    find.text('Beobachtung festhalten'),
    find.byKey(const ValueKey('cycle-overview')),
  );
  final obs2x = find.byKey(const ValueKey('cycle-observation'));
  await ensureFullyInSafeViewport(obs2x, find.text('Krämpfe'));
  await h.capture('cycle-observation-2x');
  await tapVisible(find.text('Krämpfe'), obs2x);
  await tapVisible(find.text('Übelkeit'), obs2x);
  final obs2xNote = find.byKey(const ValueKey('cycle-note'));
  await ensureFullyInSafeViewport(obs2x, obs2xNote);
  await tester.tap(obs2xNote);
  await tester.pump();
  await tester.showKeyboard(obs2xNote);
  await tester.pump();
  await waitKeyboardInset(open: true);
  await tester.enterText(obs2xNote, longNote);
  await tester.pump();
  await dismissCycleNote(obs2x);
  await ensureFullyInSafeViewport(
    obs2x,
    find.widgetWithText(OBAction, 'Speichern'),
  );
  expect(
    tester
        .widget<TextField>(find.byKey(const ValueKey('cycle-note')))
        .controller!
        .text,
    longNote,
  );
  await h.capture('cycle-observation-2x-scrolled');
  await tester.tap(find.widgetWithText(OBAction, 'Speichern').hitTestable());
  await pumpAfterTap();
  await pumpUntil(
    () => find.byKey(const ValueKey('cycle-overview')).evaluate().isNotEmpty,
    '2x observation save did not return to main.',
  );

  await mountCycle(
    repository: await loadRepo(),
    scale: 2,
    brightness: Brightness.dark,
  );
  await tapVisible(
    find.text('Beobachtung festhalten'),
    find.byKey(const ValueKey('cycle-overview')),
  );
  await ensureFullyInSafeViewport(
    find.byKey(const ValueKey('cycle-observation')),
    find.text('Krämpfe'),
  );
  await h.capture('cycle-observation-2x-dark');

  repo = await loadRepo();
  await mountCycle(repository: repo, scale: 2);
  await tapVisible(
    find.text('Verlauf'),
    find.byKey(const ValueKey('cycle-overview')),
  );
  await tester.tap(find.text('24. August'));
  await pumpAfterTap();
  await tester.tap(find.widgetWithText(OBAction, 'Entfernen'));
  await pumpAfterTap();
  await tester.tap(find.text('Entfernen').last);
  await pumpAfterTap();
  await pumpUntil(
    () => find.byKey(const ValueKey('cycle-history')).evaluate().isNotEmpty,
    '2x remove did not return to history.',
  );
  await expectUndoNotice('Beginn 24. Aug. entfernt', 'Rückgängig');
  await h.capture('cycle-undo-2x');

  repo = await loadRepo();
  repo.failCycleContextRefresh = true;
  await mountCycle(repository: repo, scale: 2);
  await tapVisible(
    find.text('Beginn eintragen'),
    find.byKey(const ValueKey('cycle-overview')),
  );
  await tester.enterText(
    find.byKey(const ValueKey('cycle-note')),
    'Refresh note',
  );
  await tester.pump();
  await tester.tap(find.widgetWithText(OBAction, 'Speichern'));
  await pumpAfterTap();
  expect(
    find.text('Gespeichert · Aktualisieren fehlgeschlagen'),
    findsOneWidget,
  );
  expect(
    tester.widget<TextField>(find.byKey(const ValueKey('cycle-note'))).enabled,
    isFalse,
  );
  await h.capture('cycle-context-error-2x');

  // Situation picker: shared choice sheet with selected check, then save.
  repo = await loadRepo();
  await mountCycle(repository: repo, settingsOnly: true);
  await tapVisible(
    find.text('Situation'),
    find.byKey(const ValueKey('cycle-settings')),
  );
  await expectSituationSelected('Keine Angabe');
  await h.capture('cycle-situation');
  await tester.tap(find.text('Natürlicher Zyklus').last);
  await pumpAfterTap();
  expect(cycleChoiceSheet(), findsNothing);
  expect(find.text('Natürlicher Zyklus'), findsOneWidget);
  expect(repo.cycleSettings.situation, CycleSituation.cycling);
  await h.capture('cycle-situation-saved');
  await tapVisible(
    find.text('Situation'),
    find.byKey(const ValueKey('cycle-settings')),
  );
  await expectSituationSelected('Natürlicher Zyklus');
  await tester.tap(find.text('Natürlicher Zyklus').last);
  await pumpAfterTap();
  await mountCycle(
    repository: repo,
    settingsOnly: true,
    brightness: Brightness.dark,
  );
  await tapVisible(
    find.text('Situation'),
    find.byKey(const ValueKey('cycle-settings')),
  );
  await expectSituationSelected('Natürlicher Zyklus');
  await h.capture('cycle-situation-dark');
}
