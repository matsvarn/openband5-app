part of 'harness.dart';

Future<void> reviewNightCards(ReviewHarness h) async {
  final tester = h.tester;
  final onsetMs = DateTime(2026, 9, 14, 23, 10).millisecondsSinceEpoch;
  final wakeMs = DateTime(2026, 9, 15, 6, 54).millisecondsSinceEpoch;
  final computedAtMs = DateTime(2026, 9, 15, 7, 2).millisecondsSinceEpoch;

  NightScalarRow selectedHrv({bool partial = false}) => NightScalarRow(
    day: kNightScalarPaperDay,
    algoVersion: kAlgoVersion,
    partial: partial,
    value: 48,
    computedAtMs: computedAtMs,
    deviceFamily: 'gen5',
    sleepSource: 'auto',
    baseline: const StoredNightBaseline(
      value: kNightScalarPaperHrvBaseline,
      status: kNightScalarTrustedBaseline,
      nValid: 30,
    ),
    windowStartMs: onsetMs,
    windowEndMs: wakeMs,
  );

  NightScalarRow selectedRhr({bool partial = false}) => NightScalarRow(
    day: kNightScalarPaperDay,
    algoVersion: kAlgoVersion,
    partial: partial,
    value: 54,
    computedAtMs: computedAtMs,
    deviceFamily: 'gen5',
    sleepSource: 'auto',
    baseline: const StoredNightBaseline(
      value: kNightScalarPaperRhrBaseline,
      status: kNightScalarTrustedBaseline,
      nValid: 30,
    ),
    windowStartMs: onsetMs,
    windowEndMs: wakeMs,
  );

  Map<String, NightScalarRow> paperHrvMatching() {
    final days = nightScalarDaysEnding(kNightScalarPaperDay, 30);
    final start = days.length - kNightScalarPaperHrv.length;
    return {
      for (var i = 0; i < kNightScalarPaperHrv.length; i++)
        days[start + i]: NightScalarRow(
          day: days[start + i],
          algoVersion: kAlgoVersion,
          value: kNightScalarPaperHrv[i],
        ),
    };
  }

  Map<String, NightScalarRow> paperRhrMatching() {
    final days = nightScalarDaysEnding(kNightScalarPaperDay, 30);
    final start = days.length - kNightScalarPaperRhr.length;
    return {
      for (var i = 0; i < kNightScalarPaperRhr.length; i++)
        days[start + i]: NightScalarRow(
          day: days[start + i],
          algoVersion: kAlgoVersion,
          value: kNightScalarPaperRhr[i],
        ),
    };
  }

  Map<String, NightScalarJob> failedJobs() => {
    kNightScalarPaperDay: NightScalarJob(
      day: kNightScalarPaperDay,
      status: 'failed',
    ),
  };

  Map<String, NightScalarRow> historyMatching(
    Map<String, NightScalarRow> paper,
    NightScalarRow? selected,
  ) {
    if (selected == null) return paper;
    return {...paper, selected.day: selected};
  }

  void seedPair(
    SyntheticOpenBandRepository repo, {
    NightScalarRow? hrv,
    NightScalarRow? rhr,
    bool missing = false,
    Map<String, NightScalarJob> sleepJobs = const {},
    Map<String, NightScalarJob> napJobs = const {},
  }) {
    final selectedH = missing ? null : (hrv ?? selectedHrv());
    final selectedR = missing ? null : (rhr ?? selectedRhr());
    repo.seedNightScalarDetail(
      key: MetricKey.hrv,
      selected: selectedH,
      matching: missing
          ? const {}
          : historyMatching(paperHrvMatching(), selectedH),
      sleepJobs: sleepJobs,
      napJobs: napJobs,
      currentAlgo: kAlgoVersion,
    );
    repo.seedNightScalarDetail(
      key: MetricKey.restingHr,
      selected: selectedR,
      matching: missing
          ? const {}
          : historyMatching(paperRhrMatching(), selectedR),
      sleepJobs: sleepJobs,
      napJobs: napJobs,
      currentAlgo: kAlgoVersion,
    );
  }

  Future<void> openGallery({
    SyntheticScenario scenario = SyntheticScenario.complete,
    Brightness brightness = Brightness.light,
    double? scale,
    void Function(SyntheticOpenBandRepository)? seed,
  }) async {
    final repository = await loadGalleryRepository();
    repository.scenario = scenario;
    seed?.call(repository);
    await tester.pumpWidget(
      OpenBandGallery(
        key: UniqueKey(),
        repository: repository,
        showControls: false,
        initialBrightness: brightness,
        initialTextScale: scale,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapCard(int index) async {
    final cards = find.byType(G2MetricCard);
    await tester.ensureVisible(cards.at(index));
    await tester.pumpAndSettle();
    await tester.tap(cards.at(index));
    await tester.pumpAndSettle();
  }

  Future<void> openStrainDetail() async {
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Belastung, ')));
    await tester.pumpAndSettle();
    expect(find.text('Belastung'), findsWidgets);
    expect(find.text('Tag für Tag'), findsOneWidget);
    expect(find.textContaining('von 30 Tagen'), findsOneWidget);
    expect(find.text('Verlauf in der Nacht'), findsNothing);
    expect(find.text('So entsteht die Basis'), findsNothing);
  }

  Future<void> backFromStrain() async {
    await reviewTapHeaderBack(tester);
    expect(find.text('Tag für Tag'), findsNothing);
  }

  Future<void> expectDetailLoaded() async {
    await tester.pump();
    var waited = 0;
    while (find
            .byKey(const ValueKey('night-scalar-detail'))
            .evaluate()
            .isEmpty ||
        (find.textContaining('von ').evaluate().isEmpty &&
            find.text('Erneut').evaluate().isEmpty &&
            find.text('Noch kein Nachtwert').evaluate().isEmpty &&
            find.text(kNightScalarFailedLabel).evaluate().isEmpty)) {
      if (++waited > 80) {
        throw FlutterError('Night scalar detail did not finish loading.');
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
    await reviewPumpPageTransitions(tester);
  }

  Future<void> backFromDetail() async {
    await reviewTapHeaderBack(tester);
    expect(find.byKey(const ValueKey('night-scalar-detail')), findsNothing);
  }

  Future<void> backFromSleep() async {
    expect(find.byType(OpenBandSleep), findsOneWidget);
    await reviewTapHeaderBack(tester);
    expect(find.byType(OpenBandSleep), findsNothing);
  }

  void expectCardValues({
    required String hrv,
    required String rhr,
    required String hrvStatus,
    required String rhrStatus,
    required bool units,
  }) {
    final cards = find.byWidgetPredicate(
      (widget) =>
          widget is G2MetricCard &&
          (widget.label == 'HRV' || widget.label == 'Ruhepuls'),
    );
    expect(cards, findsNWidgets(2));
    expect(
      find.descendant(of: cards.at(0), matching: find.text(hrv)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cards.at(1), matching: find.text(rhr)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cards.at(0), matching: find.text(hrvStatus)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cards.at(1), matching: find.text(rhrStatus)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cards.at(0), matching: find.text('ms')),
      units ? findsOneWidget : findsNothing,
    );
    expect(
      find.descendant(of: cards.at(1), matching: find.text('/min')),
      units ? findsOneWidget : findsNothing,
    );
  }

  await openGallery(seed: seedPair);
  expectCardValues(
    hrv: '48',
    rhr: '54',
    hrvStatus: '+8 über Basis',
    rhrStatus: '−2 unter Basis',
    units: true,
  );
  await h.capture('night-cards-overview-light');
  await tapCard(0);
  await expectDetailLoaded();
  expect(find.text('48'), findsOneWidget);
  expect(find.text('+8 über Basis'), findsOneWidget);
  await h.capture('night-cards-overview-hrv-detail');
  await backFromDetail();
  await tapCard(1);
  await expectDetailLoaded();
  expect(find.text('54'), findsOneWidget);
  expect(find.text('−2 unter Basis'), findsOneWidget);
  await h.capture('night-cards-overview-rhr-detail');
  await backFromDetail();
  await openStrainDetail();
  await h.capture('night-cards-overview-strain-detail');
  await backFromStrain();

  await tester.tap(find.text('Gesundheit'));
  await tester.pumpAndSettle();
  expectCardValues(
    hrv: '48',
    rhr: '54',
    hrvStatus: '+8 über Basis',
    rhrStatus: '−2 unter Basis',
    units: true,
  );
  await h.capture('night-cards-health-light');
  await tapCard(0);
  await expectDetailLoaded();
  expect(find.text('48'), findsOneWidget);
  expect(find.text('+8 über Basis'), findsOneWidget);
  await h.capture('night-cards-health-hrv-detail');
  await backFromDetail();
  await tapCard(1);
  await expectDetailLoaded();
  expect(find.text('54'), findsOneWidget);
  expect(find.text('−2 unter Basis'), findsOneWidget);
  await backFromDetail();

  await tester.tap(find.text('Übersicht'));
  await tester.pumpAndSettle();
  final sleepRing = find.bySemanticsLabel(RegExp(r'^Schlaf, '));
  await tester.scrollUntilVisible(
    sleepRing,
    -300,
    scrollable: h.verticalScrollable().last,
  );
  await tester.pumpAndSettle();
  await tester.tap(sleepRing);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byWidgetPredicate(
      (widget) => widget is G2MetricCard && widget.label == 'HRV',
    ),
    200,
    scrollable: h.verticalScrollable().last,
  );
  await tester.pumpAndSettle();
  expectCardValues(
    hrv: '48',
    rhr: '54',
    hrvStatus: '+8 über Basis',
    rhrStatus: '−2 unter Basis',
    units: true,
  );
  await h.capture('night-cards-sleep-light');
  await tapCard(0);
  await expectDetailLoaded();
  expect(find.text('48'), findsOneWidget);
  expect(find.text('+8 über Basis'), findsOneWidget);
  await h.capture('night-cards-sleep-hrv-detail');
  await backFromDetail();
  await tapCard(1);
  await expectDetailLoaded();
  expect(find.text('54'), findsOneWidget);
  expect(find.text('−2 unter Basis'), findsOneWidget);
  await h.capture('night-cards-sleep-rhr-detail');
  await backFromDetail();
  await backFromSleep();

  await openGallery(brightness: Brightness.dark, seed: seedPair);
  expectCardValues(
    hrv: '48',
    rhr: '54',
    hrvStatus: '+8 über Basis',
    rhrStatus: '−2 unter Basis',
    units: true,
  );
  await h.capture('night-cards-overview-dark');
  await openStrainDetail();
  await h.capture('night-cards-overview-strain-detail-dark');
  await backFromStrain();
  await tester.tap(find.text('Gesundheit'));
  await tester.pumpAndSettle();
  await h.capture('night-cards-health-dark');

  await openGallery(
    scenario: SyntheticScenario.missing,
    seed: (repo) => seedPair(repo, missing: true),
  );
  expectCardValues(
    hrv: '—',
    rhr: '—',
    hrvStatus: 'Kein Nachtwert',
    rhrStatus: 'Kein Nachtwert',
    units: false,
  );
  expect(find.text('48'), findsNothing);
  expect(find.text('54'), findsNothing);
  await h.capture('night-cards-overview-missing');
  await tapCard(0);
  await expectDetailLoaded();
  expect(find.text('Noch kein Nachtwert'), findsOneWidget);
  expect(find.text('48'), findsNothing);
  expect(find.text(kNightScalarFailedLabel), findsNothing);
  await h.capture('night-cards-overview-missing-detail');
  await backFromDetail();
  await tapCard(1);
  await expectDetailLoaded();
  expect(find.text('Noch kein Nachtwert'), findsOneWidget);
  expect(find.text('54'), findsNothing);
  expect(find.text(kNightScalarFailedLabel), findsNothing);
  await backFromDetail();

  await openGallery(
    scenario: SyntheticScenario.partial,
    seed: (repo) => seedPair(
      repo,
      hrv: selectedHrv(partial: true),
      rhr: selectedRhr(partial: true),
    ),
  );
  expectCardValues(
    hrv: '48',
    rhr: '54',
    hrvStatus: 'Unvollständig',
    rhrStatus: 'Unvollständig',
    units: true,
  );
  expect(find.textContaining('Basis'), findsNothing);
  await h.capture('night-cards-overview-partial');
  await tapCard(0);
  await expectDetailLoaded();
  expect(find.text('48'), findsOneWidget);
  expect(find.text('Unvollständige Nacht'), findsOneWidget);
  expect(find.text('+8 über Basis'), findsNothing);
  await h.capture('night-cards-overview-partial-detail');
  await backFromDetail();
  await tapCard(1);
  await expectDetailLoaded();
  expect(find.text('54'), findsOneWidget);
  expect(find.text('Unvollständige Nacht'), findsOneWidget);
  expect(find.text('−2 unter Basis'), findsNothing);
  await backFromDetail();
  await tester.tap(find.text('Gesundheit'));
  await tester.pumpAndSettle();
  expect(find.text('7 von 7 Nächten · teilweise'), findsWidgets);
  expect(find.textContaining('Basis'), findsNothing);
  await h.capture('night-cards-health-partial');

  await openGallery(
    scenario: SyntheticScenario.partial,
    brightness: Brightness.dark,
    seed: (repo) => seedPair(
      repo,
      hrv: selectedHrv(partial: true),
      rhr: selectedRhr(partial: true),
    ),
  );
  await tester.tap(find.text('Gesundheit'));
  await tester.pumpAndSettle();
  expect(find.text('7 von 7 Nächten · teilweise'), findsWidgets);
  await h.capture('night-cards-health-partial-dark');

  await openGallery(
    seed: (repo) =>
        seedPair(repo, sleepJobs: failedJobs(), napJobs: failedJobs()),
  );
  expectCardValues(
    hrv: '—',
    rhr: '—',
    hrvStatus: kNightScalarFailedLabel,
    rhrStatus: kNightScalarFailedLabel,
    units: false,
  );
  expect(find.text('48'), findsNothing);
  expect(find.text('Kein Nachtwert'), findsNothing);
  await h.capture('night-cards-overview-error');
  await tapCard(0);
  await expectDetailLoaded();
  expect(find.text(kNightScalarFailedLabel), findsWidgets);
  expect(find.text('48'), findsNothing);
  expect(find.text('Noch kein Nachtwert'), findsNothing);
  await h.capture('night-cards-overview-error-detail');
  await backFromDetail();
  await tapCard(1);
  await expectDetailLoaded();
  expect(find.text(kNightScalarFailedLabel), findsWidgets);
  expect(find.text('54'), findsNothing);
  expect(find.text('Noch kein Nachtwert'), findsNothing);
  await backFromDetail();

  await openGallery(scale: 2, seed: seedPair);
  await tester.scrollUntilVisible(
    find.byWidgetPredicate(
      (widget) => widget is G2MetricCard && widget.label == 'HRV',
    ),
    200,
    scrollable: h.verticalScrollable().last,
  );
  await tester.pumpAndSettle();
  expect(find.byType(G2MetricCard), findsNWidgets(2));
  await h.capture('night-cards-overview-2x');
  await tester.tap(find.text('Gesundheit'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byWidgetPredicate(
      (widget) => widget is G2MetricCard && widget.label == 'HRV',
    ),
    200,
    scrollable: h.verticalScrollable().last,
  );
  await tester.pumpAndSettle();
  expect(
    find.byWidgetPredicate(
      (widget) =>
          widget is G2MetricCard &&
          (widget.label == 'HRV' || widget.label == 'Ruhepuls'),
    ),
    findsNWidgets(2),
  );
  await h.capture('night-cards-health-2x');
  await tester.tap(find.text('Übersicht'));
  await tester.pumpAndSettle();
  final largeSleepRing = find.bySemanticsLabel(RegExp(r'^Schlaf, '));
  await tester.scrollUntilVisible(
    largeSleepRing,
    -300,
    scrollable: h.verticalScrollable().last,
  );
  await tester.pumpAndSettle();
  await tester.tap(largeSleepRing);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byWidgetPredicate(
      (widget) => widget is G2MetricCard && widget.label == 'HRV',
    ),
    200,
    scrollable: h.verticalScrollable().last,
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byType(G2MetricCard).at(1));
  await tester.pumpAndSettle();
  expect(find.byType(G2MetricCard), findsNWidgets(2));
  expectCardValues(
    hrv: '48',
    rhr: '54',
    hrvStatus: '+8 über Basis',
    rhrStatus: '−2 unter Basis',
    units: true,
  );
  await h.capture('night-cards-sleep-2x');
  expect(tester.takeException(), isNull);
}
