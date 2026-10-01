part of 'harness.dart';

Future<void> reviewWeight(ReviewHarness h) async {
  final tester = h.tester;
  const day = '2026-09-15';
  final now = DateTime(2026, 9, 15, 9, 41);

  Future<SyntheticOpenBandRepository> mountWeight({
    Brightness brightness = Brightness.light,
    double scale = 1,
    bool seeded = true,
    bool readError = false,
    SyntheticOpenBandRepository? repository,
  }) async {
    final mountedRepository = repository ?? await h.loadRepository();
    if (seeded) mountedRepository.seedWeightHistory();
    mountedRepository.failJournalRead = readError;
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: openBandTheme(brightness).copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: OpenBandWeight(
          repository: mountedRepository,
          endDay: day,
          now: () => now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return mountedRepository;
  }

  Future<void> openLatest() async {
    await tester.tap(find.byKey(const ValueKey('weight-latest-edit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('journal-value-sheet')), findsOneWidget);
  }

  final healthRepository = await h.loadRepository();
  healthRepository.seedWeightHistory();
  final healthController = OpenBandController(
    repository: healthRepository,
    initialDay: day,
    now: () => now,
  );
  await healthController.refresh();
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      debugShowCheckedModeBanner: false,
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: openBandTheme(
        Brightness.light,
      ).copyWith(platform: TargetPlatform.iOS),
      home: Scaffold(
        body: SafeArea(child: OpenBandHealth(controller: healthController)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final healthWeightRow = find.widgetWithText(OBSettingsValueRow, 'Gewicht');
  await tester.scrollUntilVisible(
    healthWeightRow,
    200,
    scrollable: h.verticalScrollable().last,
  );
  await tester.pumpAndSettle();
  await h.capture('weight-health-entry');
  await tester.tap(healthWeightRow);
  await tester.pumpAndSettle();
  expect(find.byType(OpenBandWeight), findsOneWidget);
  await h.capture('weight-health-detail');
  await openLatest();
  await tester.enterText(find.byKey(const ValueKey('journal-value')), '74,8');
  await tester.tap(find.text('Speichern'));
  await tester.pumpAndSettle();
  await reviewTapHeaderBack(tester);
  await tester.pumpAndSettle();
  expect(
    find.descendant(of: healthWeightRow, matching: find.text('74,8 kg')),
    findsOneWidget,
  );
  await h.capture('weight-health-refreshed');
  await tester.tap(healthWeightRow);
  await tester.pumpAndSettle();
  healthRepository.failJournalRead = true;
  await reviewTapHeaderBack(tester);
  await tester.pumpAndSettle();
  expect(
    find.descendant(
      of: healthWeightRow,
      matching: find.text('Journal · Laden fehlgeschlagen'),
    ),
    findsOneWidget,
  );
  expect(
    find.descendant(of: healthWeightRow, matching: find.text('74,8 kg')),
    findsNothing,
  );
  await h.capture('weight-health-refresh-error');
  healthRepository.failJournalRead = false;

  var repository = await mountWeight();
  healthController.dispose();
  expect(find.text('Journal · 15. Sept.'), findsOneWidget);
  expect(find.text('7 Einträge'), findsOneWidget);
  await h.capture('weight-light');
  await tester.tap(find.byTooltip('Über Gewicht'));
  await tester.pumpAndSettle();
  expect(find.text('Quelle: Journal · eingegebene Werte'), findsOneWidget);
  await h.capture('weight-info');

  repository = await mountWeight(brightness: Brightness.dark);
  await h.capture('weight-dark');
  await openLatest();
  expect(
    tester
        .widget<TextField>(find.byKey(const ValueKey('journal-value')))
        .controller!
        .text,
    '75',
  );
  await h.capture('weight-edit-dark');

  repository = await mountWeight(seeded: false);
  expect(find.text('Noch keine Einträge'), findsOneWidget);
  await h.capture('weight-missing');
  await tester.tap(find.text('Eintragen'));
  await tester.pumpAndSettle();
  expect(find.byType(OBCalendar), findsOneWidget);
  expect(find.byType(DatePickerDialog), findsNothing);
  expect(find.text('15. September übernehmen'), findsOneWidget);
  expect(find.text('Synthetische Daten'), findsNothing);
  await h.capture('weight-date-picker');
  await tester.tap(find.text('15. September übernehmen'));
  await tester.pumpAndSettle();
  expect(find.text('Wert entfernen'), findsNothing);
  await h.capture('weight-new');

  await mountWeight(seeded: false, brightness: Brightness.dark);
  await tester.tap(find.text('Eintragen'));
  await tester.pumpAndSettle();
  await h.capture('weight-date-picker-dark');

  await mountWeight(seeded: false, scale: 2);
  await tester.tap(find.text('Eintragen'));
  await tester.pumpAndSettle();
  final dateAction = find.text('15. September übernehmen');
  await tester.scrollUntilVisible(
    dateAction,
    200,
    scrollable: h.verticalScrollable().last,
  );
  await tester.pumpAndSettle();
  expect(
    tester.getRect(dateAction).bottom,
    lessThanOrEqualTo(
      tester.view.physicalSize.height / tester.view.devicePixelRatio,
    ),
  );
  await h.capture('weight-date-picker-2x');

  repository = await mountWeight(readError: true);
  expect(find.text('Einträge konnten nicht geladen werden.'), findsOneWidget);
  await h.capture('weight-read-error');

  repository = await mountWeight(scale: 2);
  expect(find.text('7 Einträge'), findsOneWidget);
  await h.capture('weight-2x');
  await openLatest();
  await h.capture('weight-edit-2x');
  await tester.tap(find.byTooltip('Schließen'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('weight-entry-2026-09-09')),
    250,
    scrollable: h.verticalScrollable().last,
  );
  await tester.pumpAndSettle();
  await h.capture('weight-2x-entries');

  repository = await mountWeight(brightness: Brightness.dark, scale: 2);
  expect(find.text('7 Einträge'), findsOneWidget);
  await h.capture('weight-375-2x-dark');
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('weight-entry-2026-09-09')),
    250,
    scrollable: h.verticalScrollable().last,
  );
  await tester.pumpAndSettle();
  await h.capture('weight-2x-entries-dark');

  final partialRepository = await h.loadRepository();
  partialRepository.seedWeightHistory(
    dates: const [day],
    enteredKg: const [401],
  );
  repository = await mountWeight(seeded: false, repository: partialRepository);
  expect(find.text('1 Wert ausgeschlossen'), findsOneWidget);
  await h.capture('weight-partial');

  final mixedPartialRepository = await h.loadRepository();
  mixedPartialRepository.seedWeightHistory();
  mixedPartialRepository.seedWeightHistory(
    dates: const ['2026-09-08'],
    enteredKg: const [double.nan],
  );
  repository = await mountWeight(
    seeded: false,
    repository: mixedPartialRepository,
  );
  expect(find.text('7 Einträge'), findsOneWidget);
  expect(find.text('1 Eintrag unlesbar'), findsOneWidget);
  expect(
    tester
        .widget<OBCalendarLine>(find.byType(OBCalendarLine))
        .values
        .whereType<double>(),
    hasLength(7),
  );
  await h.capture('weight-partial-history');

  final unreadableRepository = await h.loadRepository();
  unreadableRepository.seedWeightHistory(
    dates: const [day],
    enteredKg: const [double.nan],
  );
  repository = await mountWeight(
    seeded: false,
    brightness: Brightness.dark,
    repository: unreadableRepository,
  );
  expect(find.text('Einträge nicht lesbar'), findsOneWidget);
  expect(find.text('Eintragen'), findsOneWidget);
  await h.capture('weight-unreadable-dark');

  repository = await mountWeight();
  await openLatest();
  final field = find.byKey(const ValueKey('journal-value'));
  await tester.enterText(field, '74,5');
  final concurrent = await repository.readJournalDay(day);
  await repository.patchJournalDay(
    JournalDayPatch.fromBase(
      concurrent,
      metrics: const {'weight_kg': JournalMetricValue(76)},
    ),
  );
  await tester.tap(find.text('Speichern'));
  await tester.pumpAndSettle();
  expect(find.text('Eintrag wurde geändert'), findsOneWidget);
  expect(tester.widget<TextField>(field).controller!.text, '74,5');
  await h.capture('weight-conflict-retained');
  await tester.tap(find.text('Neu laden'));
  await tester.pumpAndSettle();
  expect(tester.widget<TextField>(field).controller!.text, '76');
  await tester.tap(find.byTooltip('Schließen'));
  await tester.pumpAndSettle();
  expect(find.text('76,0'), findsOneWidget);
  await h.capture('weight-conflict-closed-refreshed');

  repository = await mountWeight();
  await openLatest();
  await tester.enterText(field, '74,7');
  repository.failJournalPatch = true;
  await tester.tap(find.text('Speichern'));
  await tester.pumpAndSettle();
  expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
  expect(tester.widget<TextField>(field).controller!.text, '74,7');
  await h.capture('weight-save-error');

  repository = await mountWeight();
  await openLatest();
  await tester.enterText(field, '74,7');
  repository.failJournalRead = true;
  await tester.tap(find.text('Speichern'));
  await tester.pumpAndSettle();
  expect(
    find.text('Gespeichert. Verlauf konnte nicht aktualisiert werden.'),
    findsOneWidget,
  );
  await h.capture('weight-saved-refresh-error');

  repository.failJournalRead = false;
  await tester.tap(find.text('Erneut'));
  await tester.pumpAndSettle();
  expect(find.text('74,7'), findsOneWidget);
  await openLatest();
  await tester.tap(find.text('Wert entfernen'));
  await tester.pumpAndSettle();
  expect(find.text('Journal · 14. Sept.'), findsOneWidget);
  await h.capture('weight-removed');

  repository = await mountWeight();
  await openLatest();
  repository.failJournalRead = true;
  await tester.tap(find.text('Wert entfernen'));
  await tester.pumpAndSettle();
  expect(
    find.text('Gespeichert. Verlauf konnte nicht aktualisiert werden.'),
    findsOneWidget,
  );
  expect(find.text('Noch keine Einträge'), findsNothing);
  expect(find.text('Verlauf nicht verfügbar'), findsNothing);
  await h.capture('weight-remove-refresh-error');
}
