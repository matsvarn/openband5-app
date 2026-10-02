part of 'harness.dart';

Future<void> reviewRespiration(ReviewHarness h) async {
  final tester = h.tester;
  final now = DateTime(2026, 9, 18, 9, 41);
  final onsetMs = DateTime(2026, 9, 14, 23, 10).millisecondsSinceEpoch;
  final wakeMs = DateTime(2026, 9, 15, 6, 54).millisecondsSinceEpoch;
  final computedAtMs = DateTime(2026, 9, 15, 7, 2).millisecondsSinceEpoch;

  Finder verticalScrollable() => find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable && widget.axisDirection == AxisDirection.down,
  );

  Future<SyntheticOpenBandRepository> loadRepo() async {
    Future<Map> load(String name) => h.fixture(name);
    return SyntheticOpenBandRepository.fromMaps(
      await load('day-summary'),
      await load('sleep-detail'),
      activity: await load('additional-flows'),
      run: await load('run-detail'),
    );
  }

  Map<String, NightScalarRow> paperResp({int? algo, bool partial = false}) {
    final days = nightScalarDaysEnding(kNightScalarPaperDay, 30);
    final start = days.length - kNightScalarPaperResp.length;
    return {
      for (var i = 0; i < kNightScalarPaperResp.length; i++)
        days[start + i]: NightScalarRow(
          day: days[start + i],
          algoVersion: algo ?? kAlgoVersion,
          value: kNightScalarPaperResp[i],
          partial: partial && days[start + i] == kNightScalarPaperDay,
        ),
    };
  }

  NightScalarRow selectedResp({
    bool partial = false,
    NightScalarEnvelope? envelope,
    String? sleepSource = 'auto',
    String? deviceFamily = 'gen5',
  }) => NightScalarRow(
    day: kNightScalarPaperDay,
    algoVersion: kAlgoVersion,
    partial: partial,
    value: kNightScalarPaperRespRate,
    computedAtMs: computedAtMs,
    sleepSource: sleepSource,
    deviceFamily: deviceFamily,
    envelope: envelope,
    windowStartMs: onsetMs,
    windowEndMs: wakeMs,
  );

  void seedPaper(
    SyntheticOpenBandRepository repository, {
    NightScalarRow? selected,
    Map<String, NightScalarRow>? matching,
    Map<String, NightScalarJob> sleepJobs = const {},
    Map<String, NightScalarJob> napJobs = const {},
  }) {
    repository.seedNightScalarDetail(
      key: MetricKey.respiration,
      selected: selected ?? selectedResp(),
      matching: matching ?? paperResp(),
      sleepJobs: sleepJobs,
      napJobs: napJobs,
      currentAlgo: kAlgoVersion,
    );
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

  bool nightScalarLoaded() =>
      find.byKey(const ValueKey('night-scalar-detail')).evaluate().isNotEmpty &&
      find
          .textContaining(
            RegExp(
              r'Basis|Nachtwert|Unvollständige Nacht|Auswertung|Ältere Berechnung|Erneut',
            ),
          )
          .evaluate()
          .isNotEmpty;

  Finder detailText(String text) => find.descendant(
    of: find.byKey(const ValueKey('night-scalar-detail')),
    matching: find.text(text),
  );

  Finder cardText(String text) => find.descendant(
    of: find.byKey(const ValueKey('atemfrequenz')),
    matching: find.text(text),
  );

  Future<OpenBandController> mountDetail({
    required SyntheticOpenBandRepository repository,
    Brightness brightness = Brightness.light,
    double scale = 1,
  }) async {
    final controller = OpenBandController(
      repository: repository,
      initialDay: kNightScalarPaperDay,
      band: repository.band,
      now: () => now,
    );
    await controller.refresh();
    await tester.pumpWidget(
      reviewHost(
        brightness: brightness,
        scale: scale,
        home: OpenBandNightScalarDetail(
          controller: controller,
          metricKey: MetricKey.respiration,
          label: 'Atmung',
          unit: '/min',
          icon: LucideIcons.wind,
          color: (p) => p.sleep,
          tint: (p) => p.sleepTint,
          digits: 1,
        ),
      ),
    );
    await pumpUntil(
      nightScalarLoaded,
      'Respiration detail did not finish loading.',
    );
    return controller;
  }

  var repo = await loadRepo();
  seedPaper(repo);
  await mountDetail(repository: repo);
  expect(find.bySemanticsLabel('Atmung'), findsOneWidget);
  expect(
    find.descendant(
      of: find.byKey(const ValueKey('night-scalar-hero')),
      matching: find.text('16,0'),
    ),
    findsOneWidget,
  );
  expect(detailText('15/30'), findsOneWidget);
  expect(detailText('Basis noch offen'), findsOneWidget);
  expect(detailText('HRV'), findsNothing);
  expect(detailText('Ruhepuls'), findsNothing);
  await h.capture('resp');
  await h.press('Nachtverlauf');
  await reviewPumpPageTransitions(tester);
  await pumpUntil(
    () =>
        find.byType(OpenBandNightSignals).evaluate().isNotEmpty &&
        find.byType(OBNightSignalChart).evaluate().isNotEmpty,
    'Night signals did not load.',
  );
  final nightTabs = tester.widget<G2Segmented>(
    find.byWidgetPredicate(
      (widget) =>
          widget is G2Segmented &&
          widget.labels.contains('Puls') &&
          widget.labels.contains('Atmung'),
    ),
  );
  expect(nightTabs.selected, NightSignalKind.respiration.index);
  await h.capture('resp-night-route');
  await reviewTapHeaderBack(tester);
  await pumpUntil(
    () =>
        find.byType(OpenBandNightSignals).evaluate().isEmpty &&
        nightScalarLoaded(),
    'Respiration detail did not return.',
  );
  await h.reveal(
    find.descendant(
      of: find.byKey(const ValueKey('night-scalar-hero')),
      matching: find.text('16,0'),
    ),
  );
  expect(
    find.descendant(
      of: find.byKey(const ValueKey('night-scalar-hero')),
      matching: find.text('16,0'),
    ),
    findsOneWidget,
  );
  await tester.tap(find.byTooltip('Information'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(
    find.textContaining('Atemfrequenz · gespeicherter Wert'),
    findsOneWidget,
  );
  expect(find.textContaining('Qualitätswert'), findsNothing);
  expect(find.textContaining('Normalbereich'), findsNothing);
  await h.capture('resp-info');
  await tester.tap(find.text('Schließen'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await h.press('7 Nächte');
  await tester.pumpAndSettle();
  expect(find.text('7/7'), findsOneWidget);
  await h.capture('resp-seven');
  await h.press('90 Nächte');
  await tester.pumpAndSettle();
  expect(find.text('15/90'), findsOneWidget);
  await h.capture('resp-ninety');

  repo = await loadRepo();
  seedPaper(repo);
  await mountDetail(repository: repo, brightness: Brightness.dark);
  expect(
    find.descendant(
      of: find.byKey(const ValueKey('night-scalar-hero')),
      matching: find.text('16,0'),
    ),
    findsOneWidget,
  );
  await h.capture('resp-dark');
  await h.press('7 Nächte');
  await tester.pumpAndSettle();
  await h.capture('resp-seven-dark');

  repo = await loadRepo();
  repo.seedNightScalarDetail(
    key: MetricKey.respiration,
    selected: null,
    matching: const {},
    currentAlgo: kAlgoVersion,
  );
  await mountDetail(repository: repo);
  expect(find.text('Noch kein Nachtwert'), findsOneWidget);
  expect(find.text('0/30'), findsOneWidget);
  await h.capture('resp-missing');
  repo = await loadRepo();
  repo.seedNightScalarDetail(
    key: MetricKey.respiration,
    selected: null,
    matching: const {},
    currentAlgo: kAlgoVersion,
  );
  await mountDetail(repository: repo, brightness: Brightness.dark);
  await h.capture('resp-missing-dark');

  repo = await loadRepo();
  seedPaper(
    repo,
    selected: selectedResp(partial: true),
    matching: paperResp(partial: true),
  );
  await mountDetail(repository: repo);
  expect(find.text('Unvollständige Nacht'), findsOneWidget);
  expect(
    find.descendant(
      of: find.byKey(const ValueKey('night-scalar-hero')),
      matching: find.text('16,0'),
    ),
    findsOneWidget,
  );
  expect(find.text('teils unvollständig'), findsOneWidget);
  await h.capture('resp-partial');
  repo = await loadRepo();
  seedPaper(
    repo,
    selected: selectedResp(partial: true),
    matching: paperResp(partial: true),
  );
  await mountDetail(repository: repo, brightness: Brightness.dark);
  await h.capture('resp-partial-dark');

  repo = await loadRepo();
  seedPaper(repo);
  repo.failNightScalarRead = true;
  await mountDetail(repository: repo);
  expect(find.text('Erneut'), findsOneWidget);
  await h.capture('resp-error');
  repo.failNightScalarRead = false;
  await tester.tap(find.text('Erneut'));
  await tester.pumpAndSettle();
  expect(
    find.descendant(
      of: find.byKey(const ValueKey('night-scalar-hero')),
      matching: find.text('16,0'),
    ),
    findsOneWidget,
  );
  await h.capture('resp-error-retry');
  repo = await loadRepo();
  seedPaper(repo);
  repo.failNightScalarRead = true;
  await mountDetail(repository: repo, brightness: Brightness.dark);
  await h.capture('resp-error-dark');

  repo = await loadRepo();
  seedPaper(
    repo,
    selected: selectedResp(
      envelope: const NightScalarEnvelope(
        tier: 'HIGH',
        confidence: 0.8,
        inputsUsed: ['rr'],
        note: 'rsa ok',
        brpm: 16.5,
        peakHz: 0.275,
        power: 1.25,
        source: 'rr_spectrum',
      ),
    ),
  );
  await mountDetail(repository: repo);
  await tester.tap(find.byTooltip('Information'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.textContaining('Stufe HIGH'), findsOneWidget);
  expect(find.textContaining('Qualitätswert 0,8 / 1'), findsOneWidget);
  expect(find.textContaining('RSA-Atemfrequenz 16,5 /min'), findsOneWidget);
  expect(find.textContaining('Spektralspitze 0,275 Hz'), findsOneWidget);
  expect(find.textContaining('Spektralleistung 1,25'), findsOneWidget);
  expect(find.textContaining('Methode rr_spectrum'), findsOneWidget);
  expect(find.textContaining('Unsicherheit'), findsNothing);
  await h.capture('resp-info-envelope');
  await tester.tap(find.text('Schließen'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));

  repo = await loadRepo();
  seedPaper(repo);
  await mountDetail(repository: repo, scale: 2);
  expect(
    find.descendant(
      of: find.byKey(const ValueKey('night-scalar-hero')),
      matching: find.text('16,0'),
    ),
    findsOneWidget,
  );
  await h.capture('resp-2x');
  await tester.drag(find.byType(ListView), const Offset(0, -520));
  await tester.pumpAndSettle();
  await h.capture('resp-2x-lower');

  repo = await loadRepo();
  seedPaper(repo);
  await mountDetail(repository: repo, brightness: Brightness.dark, scale: 2);
  expect(
    find.descendant(
      of: find.byKey(const ValueKey('night-scalar-hero')),
      matching: find.text('16,0'),
    ),
    findsOneWidget,
  );
  await h.capture('resp-2x-dark');
  await tester.drag(find.byType(ListView), const Offset(0, -520));
  await tester.pumpAndSettle();
  await h.capture('resp-2x-dark-lower');

  repo = await loadRepo();
  seedPaper(repo);
  final controller = OpenBandController(
    repository: repo,
    initialDay: kNightScalarPaperDay,
    band: repo.band,
    now: () => now,
  );
  await controller.refresh();
  await tester.pumpWidget(
    reviewHost(
      home: Scaffold(
        body: SafeArea(child: OpenBandHealth(controller: controller)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final respirationCard = find.byKey(const ValueKey('atemfrequenz'));
  await tester.scrollUntilVisible(
    respirationCard,
    200,
    scrollable: verticalScrollable().last,
  );
  await Scrollable.ensureVisible(
    tester.element(respirationCard),
    alignment: 0.25,
  );
  await tester.pumpAndSettle();
  expect(cardText('16,0'), findsOneWidget);
  await h.capture('resp-health-entry');
  await tester.tap(find.text('Atemfrequenz'));
  await reviewPumpPageTransitions(tester);
  await pumpUntil(nightScalarLoaded, 'Health did not open respiration detail.');
  expect(find.bySemanticsLabel('Atmung'), findsOneWidget);
  expect(
    find.descendant(
      of: find.byKey(const ValueKey('night-scalar-hero')),
      matching: find.text('16,0'),
    ),
    findsOneWidget,
  );
  await h.capture('resp-health-detail');
  await reviewTapHeaderBack(tester);
  await pumpUntil(
    () =>
        find.byKey(const ValueKey('night-scalar-detail')).evaluate().isEmpty &&
        find.text('Atemfrequenz').evaluate().isNotEmpty,
    'Health did not return from respiration.',
  );
  expect(find.text('Atemfrequenz'), findsOneWidget);
  expect(tester.takeException(), isNull);
}
