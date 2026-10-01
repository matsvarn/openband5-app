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
    bool health = false,
  }) async {
    final repository = await h.loadRepository();
    repository.scenario = scenario;
    seed?.call(repository);
    if (health) {
      final controller = OpenBandController(
        repository: repository,
        initialDay: kNightScalarPaperDay,
        band: repository.band,
        now: () => DateTime(2026, 9, 18, 9, 41),
      );
      await controller.refresh();
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          theme: openBandTheme(brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale ?? 1)),
            child: child!,
          ),
          home: OpenBandHealth(controller: controller, bandMetricsOnly: true),
        ),
      );
    } else {
      await tester.pumpWidget(
        OpenBandGallery(
          key: UniqueKey(),
          repository: repository,
          showControls: false,
          releaseReduced: true,
          initialBrightness: brightness,
          initialTextScale: scale,
        ),
      );
    }
    await tester.pumpAndSettle();
  }

  Finder bodyRow(String name) => find.byWidgetPredicate(
    (widget) => widget is g3metrics.OBBodyRow && widget.name == name,
  );
  Future<void> reveal(Finder target) async {
    await tester.scrollUntilVisible(
      target,
      180,
      scrollable: h.verticalScrollable().last,
    );
    await tester.pumpAndSettle();
  }

  Future<void> expectToday(String hrv, String rhr) async {
    await reveal(bodyRow('HRV'));
    for (final (name, value, unit) in [
      ('HRV', hrv, 'ms'),
      ('Ruhepuls', rhr, '/min'),
    ]) {
      final row = bodyRow(name);
      expect(
        find.descendant(
          of: row,
          matching: find.text(
            value == '—' ? value : '$value $unit',
            findRichText: true,
          ),
        ),
        findsOneWidget,
      );
    }
  }

  Future<void> expectHealth(String hrv, String rhr) => expectToday(hrv, rhr);

  Future<void> openHealthDetail(
    String name,
    G3Metric metric, {
    String? capture,
  }) async {
    await reveal(bodyRow(name));
    await tester.tap(bodyRow(name));
    await tester.pumpAndSettle();
    expect(
      tester.widget<G3MetricDetail>(find.byType(G3MetricDetail)).metric,
      metric,
    );
    expect(
      find.descendant(
        of: find.byType(g3chrome.OBPageHeader),
        matching: find.text(name.toUpperCase()),
      ),
      findsOneWidget,
    );
    if (capture != null) await h.capture(capture);
    await reviewTapHeaderBack(tester);
  }

  await openGallery(seed: seedPair);
  await expectToday('48', '54');
  await h.capture('night-cards-overview-light');
  for (final (name, metric, capture) in [
    ('HRV', G3Metric.hrv, 'night-cards-heute-hrv-verlauf'),
    ('Ruhepuls', G3Metric.rhr, 'night-cards-heute-rhr-verlauf'),
  ]) {
    await reveal(bodyRow(name));
    await tester.tap(bodyRow(name));
    await tester.pumpAndSettle();
    expect(
      tester.widget<G3MetricDetail>(find.byType(G3MetricDetail)).metric,
      metric,
    );
    await h.capture(capture);
    await reviewTapHeaderBack(tester);
  }
  final strain = find.byWidgetPredicate(
    (widget) =>
        widget is g3metrics.OBSecondaryMetric && widget.label == 'BELASTUNG',
  );
  await tester.scrollUntilVisible(
    strain,
    -200,
    scrollable: h.verticalScrollable().last,
  );
  await h.tap(strain);
  expect(find.byType(G3LoadScreen), findsOneWidget);
  await h.capture('night-cards-overview-strain-detail');
  await reviewTapHeaderBack(tester);
  await h.openSleep();
  await h.press('IN DER NACHT');
  expect(find.text('HRV · ms'), findsOneWidget);
  expect(find.text('RUHEPULS'), findsOneWidget);
  expect(find.text('48', findRichText: true), findsOneWidget);
  expect(find.text('54 /min', findRichText: true), findsOneWidget);
  await h.capture('night-cards-sleep-light');

  for (final brightness in Brightness.values) {
    await openGallery(seed: seedPair, health: true, brightness: brightness);
    await expectHealth('48', '54');
    await h.capture('night-cards-messwerte-${brightness.name}');
    await openHealthDetail(
      'HRV',
      G3Metric.hrv,
      capture: brightness == Brightness.light
          ? 'night-cards-messwerte-hrv-verlauf'
          : null,
    );
    await openHealthDetail('Ruhepuls', G3Metric.rhr);
  }
  await openGallery(seed: seedPair, brightness: Brightness.dark);
  await expectToday('48', '54');
  await h.capture('night-cards-overview-dark');
  await tester.scrollUntilVisible(
    strain,
    -200,
    scrollable: h.verticalScrollable().last,
  );
  await h.tap(strain);
  expect(find.byType(G3LoadScreen), findsOneWidget);
  await h.capture('night-cards-overview-strain-detail-dark');
  await reviewTapHeaderBack(tester);

  for (final (scenario, seed, hrv, rhr, suffix) in [
    (
      SyntheticScenario.missing,
      (SyntheticOpenBandRepository repo) => seedPair(repo, missing: true),
      '—',
      '—',
      'missing',
    ),
    (
      SyntheticScenario.partial,
      (SyntheticOpenBandRepository repo) => seedPair(
        repo,
        hrv: selectedHrv(partial: true),
        rhr: selectedRhr(partial: true),
      ),
      '48',
      '54',
      'partial',
    ),
    (
      SyntheticScenario.complete,
      (SyntheticOpenBandRepository repo) =>
          seedPair(repo, sleepJobs: failedJobs(), napJobs: failedJobs()),
      '—',
      '—',
      'error',
    ),
  ]) {
    await openGallery(scenario: scenario, seed: seed);
    await expectToday(hrv, rhr);
    await h.capture('night-cards-overview-$suffix');
    await openGallery(scenario: scenario, seed: seed, health: true);
    await expectHealth('—', '—');
    await h.capture('night-cards-messwerte-$suffix');
    await openHealthDetail(
      'HRV',
      G3Metric.hrv,
      capture: 'night-cards-messwerte-$suffix-verlauf',
    );
    await openHealthDetail('Ruhepuls', G3Metric.rhr);
  }
  await openGallery(
    scenario: SyntheticScenario.partial,
    health: true,
    brightness: Brightness.dark,
    seed: (repo) => seedPair(
      repo,
      hrv: selectedHrv(partial: true),
      rhr: selectedRhr(partial: true),
    ),
  );
  await expectHealth('—', '—');
  await h.capture('night-cards-messwerte-partial-dark');

  await openGallery(scale: 2, seed: seedPair);
  await expectToday('48', '54');
  await h.capture('night-cards-overview-2x');
  await h.openSleep();
  await h.press('IN DER NACHT');
  expect(find.text('48', findRichText: true), findsOneWidget);
  expect(find.text('54 /min', findRichText: true), findsOneWidget);
  await h.capture('night-cards-sleep-2x');
  await openGallery(scale: 2, seed: seedPair, health: true);
  await expectHealth('48', '54');
  await h.capture('night-cards-messwerte-2x');
  expect(tester.takeException(), isNull);
}
