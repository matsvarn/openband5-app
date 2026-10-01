part of 'harness.dart';

Future<void> reviewNightScalar(ReviewHarness h) async {
  final tester = h.tester;
  final now = DateTime(2026, 9, 15, 9, 41);
  final onsetMs = DateTime(2026, 9, 14, 23, 10).millisecondsSinceEpoch;
  final wakeMs = DateTime(2026, 9, 15, 6, 54).millisecondsSinceEpoch;

  Future<SyntheticOpenBandRepository> loadRepo() async {
    Future<Map> load(String name) => h.fixture(name);
    return SyntheticOpenBandRepository.fromMaps(
      await load('day-summary'),
      await load('sleep-detail'),
      activity: await load('additional-flows'),
      run: await load('run-detail'),
    );
  }

  Map<String, NightScalarRow> paperHrv({int? algo}) {
    final days = nightScalarDaysEnding(kNightScalarPaperDay, 30);
    final start = days.length - kNightScalarPaperHrv.length;
    return {
      for (var i = 0; i < kNightScalarPaperHrv.length; i++)
        days[start + i]: NightScalarRow(
          day: days[start + i],
          algoVersion: algo ?? kAlgoVersion,
          value: kNightScalarPaperHrv[i],
        ),
    };
  }

  NightScalarRow selectedHrv({
    StoredNightBaseline? baseline,
    int? algo,
    bool partial = false,
    int? computedAtMs,
    String? deviceFamily,
    String? sleepSource,
  }) => NightScalarRow(
    day: kNightScalarPaperDay,
    algoVersion: algo ?? kAlgoVersion,
    partial: partial,
    value: 48,
    computedAtMs:
        computedAtMs ?? DateTime(2026, 9, 15, 7, 2).millisecondsSinceEpoch,
    deviceFamily: deviceFamily,
    sleepSource: sleepSource,
    baseline:
        baseline ??
        const StoredNightBaseline(
          value: kNightScalarPaperHrvBaseline,
          status: 'trusted',
          nValid: 30,
        ),
    windowStartMs: onsetMs,
    windowEndMs: wakeMs,
  );

  void seedTrusted(SyntheticOpenBandRepository repo, {bool hrv = true}) {
    if (hrv) {
      repo.seedNightScalarDetail(
        selected: selectedHrv(deviceFamily: 'gen5', sleepSource: 'auto'),
        matching: paperHrv(),
        currentAlgo: kAlgoVersion,
      );
      return;
    }
    final days = nightScalarDaysEnding(kNightScalarPaperDay, 30);
    final start = days.length - kNightScalarPaperRhr.length;
    repo.seedNightScalarDetail(
      key: MetricKey.restingHr,
      selected: NightScalarRow(
        day: kNightScalarPaperDay,
        algoVersion: kAlgoVersion,
        value: 54,
        computedAtMs: DateTime(2026, 9, 15, 7, 2).millisecondsSinceEpoch,
        baseline: const StoredNightBaseline(
          value: kNightScalarPaperRhrBaseline,
          status: 'trusted',
        ),
        windowStartMs: onsetMs,
        windowEndMs: wakeMs,
      ),
      matching: {
        for (var i = 0; i < kNightScalarPaperRhr.length; i++)
          days[start + i]: NightScalarRow(
            day: days[start + i],
            algoVersion: kAlgoVersion,
            value: kNightScalarPaperRhr[i],
          ),
      },
      currentAlgo: kAlgoVersion,
    );
  }

  Map<String, NightScalarJob> failedJobs() => {
    kNightScalarPaperDay: NightScalarJob(
      day: kNightScalarPaperDay,
      status: 'failed',
    ),
  };

  void seedSelectedPartial(SyntheticOpenBandRepository repo) {
    final matching = paperHrv();
    matching[kNightScalarPaperDay] = NightScalarRow(
      day: kNightScalarPaperDay,
      algoVersion: kAlgoVersion,
      value: kNightScalarPaperHrv.last,
      partial: true,
    );
    repo.seedNightScalarDetail(
      selected: selectedHrv(
        partial: true,
        deviceFamily: 'gen5',
        sleepSource: 'auto',
      ),
      matching: matching,
      currentAlgo: kAlgoVersion,
    );
  }

  void seedFailedReceipt(SyntheticOpenBandRepository repo) {
    repo.seedNightScalarDetail(
      selected: selectedHrv(deviceFamily: 'gen5', sleepSource: 'auto'),
      matching: paperHrv(),
      sleepJobs: failedJobs(),
      napJobs: failedJobs(),
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

  Future<OpenBandController> mountDetail({
    required SyntheticOpenBandRepository repository,
    MetricKey key = MetricKey.hrv,
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
          metricKey: key,
          label: key == MetricKey.hrv ? 'HRV' : 'Ruhepuls',
          unit: key == MetricKey.hrv ? 'ms' : '/min',
          icon: key == MetricKey.hrv ? LucideIcons.activity : LucideIcons.heart,
          color: key == MetricKey.hrv ? (p) => p.recovery : (p) => p.pulse,
          tint: key == MetricKey.hrv
              ? (p) => p.recoveryTint
              : (p) => p.pulseTint,
        ),
      ),
    );
    await pumpUntil(
      nightScalarLoaded,
      'Night scalar detail did not finish loading.',
    );
    return controller;
  }

  Finder heroText(String text) => find.descendant(
    of: find.byKey(const ValueKey('night-scalar-hero')),
    matching: find.text(text),
  );

  var repo = await loadRepo();
  seedTrusted(repo);
  await mountDetail(repository: repo);
  expect(heroText('48'), findsOneWidget);
  expect(find.text('15/30'), findsOneWidget);
  await h.capture('night-scalar-hrv');
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
          widget.labels.contains('HRV'),
    ),
  );
  expect(nightTabs.selected, 1);
  await h.capture('night-scalar-night-route');
  await tester.tap(find.byTooltip('Zurück'));
  await reviewPumpPageTransitions(tester);
  await pumpUntil(
    () =>
        find.byType(OpenBandNightSignals).evaluate().isEmpty &&
        nightScalarLoaded(),
    'Night scalar detail did not return.',
  );
  await h.reveal(heroText('48'));
  expect(heroText('48'), findsOneWidget);
  await tester.tap(find.byTooltip('Information'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await h.capture('night-scalar-info');
  await tester.tap(find.text('Schließen'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await h.press('Persönliche Basis');
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await h.capture('night-scalar-baseline');
  await tester.tap(find.text('Schließen'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await h.press('7 Nächte');
  await tester.pumpAndSettle();
  await h.capture('night-scalar-seven');
  await h.press('90 Nächte');
  await tester.pumpAndSettle();
  await h.capture('night-scalar-ninety');

  repo = await loadRepo();
  seedTrusted(repo);
  await mountDetail(repository: repo, brightness: Brightness.dark);
  await h.capture('night-scalar-hrv-dark');
  await h.press('7 Nächte');
  await tester.pumpAndSettle();
  await h.capture('night-scalar-seven-dark');

  repo = await loadRepo();
  seedTrusted(repo, hrv: false);
  await mountDetail(repository: repo, key: MetricKey.restingHr);
  expect(heroText('54'), findsOneWidget);
  await h.capture('night-scalar-rhr');
  repo = await loadRepo();
  seedTrusted(repo, hrv: false);
  await mountDetail(
    repository: repo,
    key: MetricKey.restingHr,
    brightness: Brightness.dark,
  );
  await h.capture('night-scalar-rhr-dark');

  repo = await loadRepo();
  repo.scenario = SyntheticScenario.missing;
  await mountDetail(repository: repo);
  expect(find.text('Noch kein Nachtwert'), findsOneWidget);
  expect(find.text('14/30'), findsOneWidget);
  await h.capture('night-scalar-selected-missing');

  repo = await loadRepo();
  repo.seedNightScalarDetail(
    selected: null,
    matching: const {},
    currentAlgo: kAlgoVersion,
  );
  await mountDetail(repository: repo);
  expect(find.text('Noch kein Nachtwert'), findsOneWidget);
  expect(find.text('0/30'), findsOneWidget);
  expect(find.text('14/30'), findsNothing);
  await h.capture('night-scalar-full-missing');

  repo = await loadRepo();
  seedSelectedPartial(repo);
  await mountDetail(repository: repo);
  expect(find.text('Unvollständige Nacht'), findsOneWidget);
  expect(heroText('48'), findsOneWidget);
  expect(find.text('teils unvollständig'), findsOneWidget);
  expect(find.textContaining('Basis 40'), findsOneWidget);
  expect(find.text('+8 über deiner Basis (40 ms)'), findsNothing);
  await h.capture('night-scalar-partial');

  repo = await loadRepo();
  repo.scenario = SyntheticScenario.processing;
  await mountDetail(repository: repo);
  expect(find.text('Auswertung läuft'), findsOneWidget);
  await h.capture('night-scalar-pending');

  repo = await loadRepo();
  seedFailedReceipt(repo);
  await mountDetail(repository: repo);
  expect(find.text('Auswertung fehlgeschlagen'), findsOneWidget);
  expect(heroText('48'), findsNothing);
  expect(find.text('14/30'), findsOneWidget);
  await h.capture('night-scalar-failed');
  await tester.tap(find.byTooltip('Information'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.textContaining('Zuletzt gespeichert: 48 ms'), findsOneWidget);
  expect(
    find.textContaining('14.–15. September · 23:10–06:54'),
    findsOneWidget,
  );
  expect(find.textContaining('Schlaf automatisch · WHOOP 5.0'), findsOneWidget);
  expect(
    find.textContaining('Berechnet am 15. September, 07:02'),
    findsOneWidget,
  );
  expect(find.textContaining('Vorherige Basis 40 ms'), findsOneWidget);
  expect(find.textContaining('30 gültige Nächte'), findsOneWidget);
  expect(find.textContaining('Vorheriger Status: Verlässlich'), findsOneWidget);
  expect(find.textContaining('Algorithmus $kAlgoVersion'), findsOneWidget);
  await h.capture('night-scalar-failed-info');
  await tester.tap(find.text('Schlaf ansehen'));
  await reviewPumpPageTransitions(tester);
  await pumpUntil(
    () =>
        find.byType(SleepEditor).evaluate().isNotEmpty &&
        find.byKey(const ValueKey('sleep-onset')).evaluate().isNotEmpty,
    'Sleep editor did not open from failed info.',
  );
  await h.capture('night-scalar-correction-route');

  repo = await loadRepo();
  repo.seedNightScalarDetail(
    selected: selectedHrv(),
    matching: paperHrv(),
    sleepJobs: {
      kNightScalarPaperDay: NightScalarJob(
        day: kNightScalarPaperDay,
        status: 'queued',
      ),
    },
    currentAlgo: kAlgoVersion,
  );
  await mountDetail(repository: repo);
  await h.capture('night-scalar-unknown');

  repo = await loadRepo();
  repo.seedNightScalarDetail(
    selected: selectedHrv(algo: 80),
    matching: paperHrv(algo: 80),
    currentAlgo: kAlgoVersion,
  );
  await mountDetail(repository: repo);
  await h.capture('night-scalar-old');

  repo = await loadRepo();
  repo.seedNightScalarDetail(
    selected: selectedHrv(
      baseline: const StoredNightBaseline(value: 40, status: 'provisional'),
    ),
    matching: paperHrv(),
    currentAlgo: kAlgoVersion,
  );
  await mountDetail(repository: repo);
  await h.capture('night-scalar-provisional');

  repo = await loadRepo();
  repo.seedNightScalarDetail(
    selected: selectedHrv(
      baseline: const StoredNightBaseline(value: 40, status: 'stale'),
    ),
    matching: paperHrv(),
    currentAlgo: kAlgoVersion,
  );
  await mountDetail(repository: repo);
  await h.capture('night-scalar-stale');

  repo = await loadRepo();
  final unreadableHistory = paperHrv()..remove(kNightScalarPaperDay);
  repo.seedNightScalarDetail(
    selected: NightScalarRow(
      day: kNightScalarPaperDay,
      algoVersion: kAlgoVersion,
      payloadUnreadable: true,
      value: 48,
    ),
    matching: unreadableHistory,
    currentAlgo: kAlgoVersion,
  );
  await mountDetail(repository: repo);
  expect(find.text('Nachtwert nicht lesbar'), findsOneWidget);
  expect(find.text('14/30'), findsOneWidget);
  expect(find.text('15/30'), findsNothing);
  await h.capture('night-scalar-unreadable');

  repo = await loadRepo();
  final sparseDays = nightScalarDaysEnding(kNightScalarPaperDay, 30);
  repo.seedNightScalarDetail(
    selected: selectedHrv(),
    matching: {
      sparseDays[15]: NightScalarRow(
        day: sparseDays[15],
        algoVersion: kAlgoVersion,
        value: 32,
      ),
      sparseDays[26]: NightScalarRow(
        day: sparseDays[26],
        algoVersion: kAlgoVersion,
        value: 46,
      ),
      sparseDays[29]: selectedHrv(),
    },
    currentAlgo: kAlgoVersion,
  );
  await mountDetail(repository: repo);
  expect(heroText('48'), findsOneWidget);
  expect(find.text('3/30'), findsOneWidget);
  expect(find.text('+8 über deiner Basis (40 ms)'), findsOneWidget);
  await h.capture('night-scalar-sparse');

  repo = await loadRepo();
  repo.failNightScalarRead = true;
  await mountDetail(repository: repo);
  expect(find.text('Erneut'), findsOneWidget);
  await h.capture('night-scalar-error');
  repo.failNightScalarRead = false;
  await tester.tap(find.text('Erneut'));
  await tester.pumpAndSettle();
  await h.capture('night-scalar-error-retry');

  // Paper acceptance includes the non-default states in both themes.
  repo = await loadRepo();
  repo.scenario = SyntheticScenario.missing;
  await mountDetail(repository: repo, brightness: Brightness.dark);
  expect(find.text('14/30'), findsOneWidget);
  await h.capture('night-scalar-selected-missing-dark');

  repo = await loadRepo();
  repo.seedNightScalarDetail(
    selected: null,
    matching: const {},
    currentAlgo: kAlgoVersion,
  );
  await mountDetail(repository: repo, brightness: Brightness.dark);
  expect(find.text('0/30'), findsOneWidget);
  await h.capture('night-scalar-full-missing-dark');

  repo = await loadRepo();
  seedSelectedPartial(repo);
  await mountDetail(repository: repo, brightness: Brightness.dark);
  expect(find.text('Unvollständige Nacht'), findsOneWidget);
  expect(find.text('teils unvollständig'), findsOneWidget);
  expect(find.textContaining('Basis 40'), findsOneWidget);
  await h.capture('night-scalar-partial-dark');

  repo = await loadRepo();
  repo.failNightScalarRead = true;
  await mountDetail(repository: repo, brightness: Brightness.dark);
  await h.capture('night-scalar-error-dark');

  repo = await loadRepo();
  seedTrusted(repo);
  await mountDetail(repository: repo, brightness: Brightness.dark);
  await tester.tap(find.byTooltip('Information'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await h.capture('night-scalar-info-dark');

  repo = await loadRepo();
  repo.seedNightScalarDetail(
    selected: selectedHrv(
      baseline: const StoredNightBaseline(value: 40, status: 'provisional'),
    ),
    matching: paperHrv(),
    currentAlgo: kAlgoVersion,
  );
  await mountDetail(repository: repo, brightness: Brightness.dark);
  await h.capture('night-scalar-provisional-dark');

  repo = await loadRepo();
  repo.seedNightScalarDetail(
    selected: selectedHrv(
      baseline: const StoredNightBaseline(value: 40, status: 'stale'),
    ),
    matching: paperHrv(),
    currentAlgo: kAlgoVersion,
  );
  await mountDetail(repository: repo, brightness: Brightness.dark);
  await h.capture('night-scalar-stale-dark');

  repo = await loadRepo();
  seedTrusted(repo);
  await mountDetail(repository: repo, scale: 2);
  await h.capture('night-scalar-2x');
  await tester.drag(find.byType(ListView), const Offset(0, -520));
  await tester.pumpAndSettle();
  await h.capture('night-scalar-2x-lower');
  repo = await loadRepo();
  seedTrusted(repo);
  await mountDetail(repository: repo, scale: 2, brightness: Brightness.dark);
  await h.capture('night-scalar-2x-dark');
  await tester.drag(find.byType(ListView), const Offset(0, -520));
  await tester.pumpAndSettle();
  await h.capture('night-scalar-2x-dark-lower');
  expect(tester.takeException(), isNull);
}
