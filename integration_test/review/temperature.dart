part of 'harness.dart';

Future<void> reviewTemperature(ReviewHarness h) async {
  final tester = h.tester;
  final now = DateTime(2026, 9, 18, 9, 41);

  Future<SyntheticOpenBandRepository> loadRepo() async {
    Future<Map> load(String name) => h.fixture(name);
    return SyntheticOpenBandRepository.fromMaps(
      await load('day-summary'),
      await load('sleep-detail'),
      activity: await load('additional-flows'),
      run: await load('run-detail'),
    );
  }

  void seed(
    SyntheticOpenBandRepository repository,
    NightScalarUnit unit, {
    bool partial = false,
    String? rowSource,
    String? payloadSource,
  }) {
    final days = nightScalarDaysEnding(kNightScalarPaperDay, 30);
    final values = unit == NightScalarUnit.celsius
        ? kNightScalarPaperSkinTempC
        : kNightScalarPaperSkinTempSd;
    final start = days.length - values.length;
    final source = switch (unit) {
      NightScalarUnit.sd => 'band',
      NightScalarUnit.celsius => 'whoop_export',
      NightScalarUnit.unknown => 'cloud_v2',
    };
    NightScalarRow row(String day, double value) => NightScalarRow(
      day: day,
      algoVersion: kAlgoVersion,
      value: value,
      partial: partial && day == kNightScalarPaperDay,
      imported: unit == NightScalarUnit.celsius,
      rowSource: rowSource ?? source,
      source: payloadSource ?? source,
    );
    repository.seedNightScalarDetail(
      key: MetricKey.skinTemperature,
      selected: NightScalarRow(
        day: kNightScalarPaperDay,
        algoVersion: kAlgoVersion,
        value: unit == NightScalarUnit.celsius ? 33.2 : 0.4,
        partial: partial,
        imported: unit == NightScalarUnit.celsius,
        rowSource: rowSource ?? source,
        source: payloadSource ?? source,
        deviceFamily: 'gen5',
        computedAtMs: DateTime(2026, 9, 15, 7, 2).millisecondsSinceEpoch,
      ),
      matching: {
        for (var i = 0; i < values.length; i++)
          if (values[i] != null)
            days[start + i]: row(days[start + i], values[i]!),
      },
      currentAlgo: kAlgoVersion,
    );
  }

  Widget host(
    Widget home, {
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

  Future<OpenBandController> mount(
    SyntheticOpenBandRepository repository, {
    Brightness brightness = Brightness.light,
    double scale = 1,
    bool expectError = false,
    bool expectSourceVisible = true,
  }) async {
    final controller = OpenBandController(
      repository: repository,
      initialDay: kNightScalarPaperDay,
      band: repository.band,
      now: () => now,
    );
    await controller.refresh();
    await tester.pumpWidget(
      host(
        OpenBandNightScalarDetail(
          controller: controller,
          metricKey: MetricKey.skinTemperature,
          label: 'Hauttemperatur',
          unit: '',
          icon: LucideIcons.thermometer,
          color: (p) => p.ink,
          tint: (p) => p.well,
          digits: 1,
        ),
        brightness: brightness,
        scale: scale,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('night-scalar-detail')), findsOneWidget);
    if (expectError) {
      expect(
        find.text('Nachtwerte konnten nicht geladen werden.'),
        findsOneWidget,
      );
      expect(find.text('Erneut'), findsOneWidget);
      expect(find.text('Quelle'), findsNothing);
    } else {
      expect(find.text('Erneut'), findsNothing);
      if (expectSourceVisible) {
        expect(find.text('Quelle'), findsOneWidget);
      } else {
        expect(find.byType(G2Segmented), findsOneWidget);
        expect(find.text('30 Nächte'), findsOneWidget);
      }
    }
    return controller;
  }

  var repository = await loadRepo();
  seed(repository, NightScalarUnit.sd);
  await mount(repository);
  await h.capture('temperature-sd');
  await tester.tap(find.byTooltip('Information'));
  await tester.pumpAndSettle();
  await h.capture('temperature-info-sd');
  await tester.tap(find.text('Schließen'));
  await tester.pumpAndSettle();
  for (final period in ['7 Nächte', '90 Nächte']) {
    await tester.tap(find.text(period));
    await tester.pumpAndSettle();
    await h.capture(
      'temperature-${period.startsWith('7') ? 'seven' : 'ninety'}',
    );
  }

  repository = await loadRepo();
  seed(repository, NightScalarUnit.sd);
  await mount(repository, brightness: Brightness.dark);
  await h.capture('temperature-sd-dark');

  for (final unit in [NightScalarUnit.celsius, NightScalarUnit.unknown]) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      repository = await loadRepo();
      seed(repository, unit);
      await mount(repository, brightness: brightness);
      await h.capture('temperature-${unit.name}-${brightness.name}');
    }
  }

  repository = await loadRepo();
  seed(
    repository,
    NightScalarUnit.unknown,
    rowSource: 'band',
    payloadSource: 'whoop_export',
  );
  await mount(repository);
  expect(find.text('Uneindeutig'), findsOneWidget);
  await h.capture('temperature-conflict');
  await tester.tap(find.byTooltip('Information'));
  await tester.pumpAndSettle();
  expect(find.textContaining('Quellen: Band / WHOOP-Export'), findsOneWidget);
  await h.capture('temperature-info-conflict');

  repository = await loadRepo();
  seed(repository, NightScalarUnit.sd, partial: true);
  await mount(repository);
  await h.capture('temperature-partial');

  repository = await loadRepo();
  repository.seedNightScalarDetail(
    key: MetricKey.skinTemperature,
    selected: null,
    matching: const {},
    currentAlgo: kAlgoVersion,
  );
  await mount(repository);
  await h.capture('temperature-missing');

  repository = await loadRepo();
  seed(repository, NightScalarUnit.sd);
  repository.failNightScalarRead = true;
  await mount(repository, expectError: true);
  await h.capture('temperature-error');
  repository.failNightScalarRead = false;
  await tester.tap(find.text('Erneut'));
  await tester.pumpAndSettle();
  expect(find.text('+0,4'), findsOneWidget);
  expect(find.text('Quelle'), findsOneWidget);
  expect(find.text('Erneut'), findsNothing);
  await h.capture('temperature-error-retry');

  for (final brightness in [Brightness.light, Brightness.dark]) {
    repository = await loadRepo();
    seed(repository, NightScalarUnit.sd);
    await mount(
      repository,
      brightness: brightness,
      scale: 2,
      expectSourceVisible: false,
    );
    expect(find.text('+0,4'), findsOneWidget);
    expect(find.text('14 von 30 Nächten'), findsOneWidget);
    await h.capture('temperature-2x-${brightness.name}');
    await tester.scrollUntilVisible(
      find.text('Quelle'),
      250,
      scrollable: h.verticalScrollable().last,
    );
    await tester.pumpAndSettle();
    expect(find.text('Quelle'), findsOneWidget);
    await h.capture('temperature-2x-lower-${brightness.name}');
  }

  repository = await loadRepo();
  seed(repository, NightScalarUnit.sd);
  final controller = OpenBandController(
    repository: repository,
    initialDay: kNightScalarPaperDay,
    band: repository.band,
    now: () => now,
  );
  await controller.refresh();
  await tester.pumpWidget(
    host(
      Scaffold(
        body: SafeArea(child: OpenBandHealth(controller: controller)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final card = find.byKey(const ValueKey('hauttemperatur'));
  await tester.scrollUntilVisible(
    card,
    200,
    scrollable: h.verticalScrollable().last,
  );
  await Scrollable.ensureVisible(tester.element(card), alignment: .25);
  await tester.pumpAndSettle();
  await h.capture('temperature-health-entry');
  await tester.tap(card);
  await tester.pumpAndSettle();
  await h.capture('temperature-health-detail');
  await reviewTapHeaderBack(tester);
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('hauttemperatur')), findsOneWidget);
  expect(find.byType(OpenBandNightSignals), findsNothing);
  expect(tester.takeException(), isNull);
}
