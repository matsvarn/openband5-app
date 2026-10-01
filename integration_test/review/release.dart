part of 'harness.dart';

Future<void> reviewRelease(ReviewHarness h) async {
  final tester = h.tester;
  Future<void> chooseG3Scenario(String label) async {
    await tester.tap(find.text('Synthetische Galerie'));
    await tester.pumpAndSettle();
    final choice = find.text(label);
    final sheetScroll = find
        .descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        )
        .last;
    await tester.scrollUntilVisible(choice, 240, scrollable: sheetScroll);
    await Scrollable.ensureVisible(tester.element(choice), alignment: .2);
    await tester.pumpAndSettle();
    await tester.tap(choice);
    await tester.pumpAndSettle();
    final gallery = tester.widget<OpenBandGallery>(
      find.byType(OpenBandGallery),
    );
    await tester.pumpWidget(
      OpenBandGallery(
        key: gallery.key,
        repository: gallery.repository,
        initialBrightness: gallery.initialBrightness,
        initialTextScale: gallery.initialTextScale,
        releaseReduced: gallery.releaseReduced,
        showControls: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('29. September'), findsWidgets);
  }

  Future<void> backFromG3() async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  Future<void> revealG3(
    Finder target, {
    double delta = 240,
    Finder? scrollable,
  }) async {
    await tester.scrollUntilVisible(
      target,
      delta,
      scrollable: scrollable ?? h.verticalScrollable().hitTestable().last,
    );
    await Scrollable.ensureVisible(tester.element(target), alignment: .2);
    await tester.pumpAndSettle();
  }

  Future<void> reviewG3(Brightness brightness) async {
    final suffix = brightness.name;
    await h.mount(
      release: true,
      scenario: SyntheticScenario.g3Sample,
      brightness: brightness,
      showControls: true,
    );
    await chooseG3Scenario('G3 · Tagesblatt');
    for (final domain in ['home', 'sleep', 'workout', 'wellness']) {
      expect(find.byKey(ValueKey('ob-tab-$domain')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('ob-tab-health')), findsNothing);
    await h.capture('g3-heute-$suffix');

    await revealG3(find.text('KÖRPER'));
    await h.capture('g3-heute-scrolled-$suffix');
    await tester.tap(find.text('HRV').last);
    await tester.pumpAndSettle();
    expect(find.byType(G3MetricDetail), findsOneWidget);
    await h.capture('g3-verlauf-hrv-$suffix');
    await backFromG3();

    tester
        .state<ScrollableState>(h.verticalScrollable().hitTestable().last)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(g3chrome.OBPageHeader).first,
        matching: find.text('Heute'),
      ),
    );
    await tester.pumpAndSettle();
    await h.capture('g3-date-picker-$suffix');
    await backFromG3();

    await tester.tap(find.bySemanticsLabel('Profil'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-screen')), findsOneWidget);
    await h.capture('g3-profile-$suffix');
    await tester.tap(find.byKey(const ValueKey('profile-band')));
    await tester.pumpAndSettle();
    expect(find.byType(G3BandScreen), findsOneWidget);
    await h.capture('g3-band-$suffix');
    await backFromG3();
    await backFromG3();

    await tester.tap(find.byKey(const ValueKey('ob-tab-sleep')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('g3-sleep')), findsOneWidget);
    await h.capture('g3-schlaf-$suffix');
    // The plan for tonight is reached through the sleep goal sheet.
    await tester.tap(find.text('SCHLAF').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Heute Nacht'));
    await tester.pumpAndSettle();
    expect(find.byType(G3SleepTonight), findsOneWidget);
    await h.capture('g3-heute-nacht-$suffix');
    await backFromG3();
    await revealG3(find.text('Zeiten ändern'));
    await tester.tap(find.text('Zeiten ändern'));
    await tester.pumpAndSettle();
    expect(find.byType(SleepEditor), findsOneWidget);
    await h.capture('g3-schlaf-correction-$suffix');
    await backFromG3();

    await tester.tap(find.byKey(const ValueKey('ob-tab-workout')));
    await tester.pumpAndSettle();
    expect(find.byType(G3TrainingScreen), findsOneWidget);
    await h.capture('g3-training-$suffix');
    final trainingScroll = find
        .descendant(
          of: find.byType(G3TrainingScreen),
          matching: h.verticalScrollable(),
        )
        .hitTestable()
        .last;
    await revealG3(find.text('Stimmt'), scrollable: trainingScroll);
    await tester.tap(find.text('Stimmt'));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byType(G3TrainingScreen),
            matching: find.text('Lauf'),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.byType(G3ActivityScreen), findsOneWidget);
    await h.capture('g3-training-result-$suffix');
    await revealG3(
      find.text('ZEIT IN ZONEN'),
      scrollable: find
          .descendant(
            of: find.byType(G3ActivityScreen),
            matching: h.verticalScrollable(),
          )
          .hitTestable()
          .last,
    );
    await h.capture('g3-training-result-zones-$suffix');
    await backFromG3();
    tester.state<ScrollableState>(trainingScroll).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nachtragen'));
    await tester.pumpAndSettle();
    expect(find.byType(G3ManualFlow), findsOneWidget);
    await h.capture('g3-training-manual-$suffix');
    await backFromG3();

    await tester.tap(find.text('Training starten'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await h.capture('g3-training-sport-picker-$suffix');
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Lauf'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Starten'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(G3LiveRun), findsOneWidget);
    await h.capture('g3-training-live-$suffix');
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();
    await h.capture('g3-training-live-paused-$suffix');
    await tester.tap(find.text('Beenden'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verwerfen'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Verwerfen'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(G3LiveRun), findsNothing);

    await tester.tap(find.byKey(const ValueKey('ob-tab-wellness')));
    await tester.pumpAndSettle();
    await h.capture('g3-journal-$suffix');
    expect(find.byType(OBCheckIn), findsOneWidget);
    await tester.tap(find.text('Nein'));
    await tester.pumpAndSettle();
    await h.capture('g3-journal-checkin-$suffix');
  }

  for (final brightness in [Brightness.light, Brightness.dark]) {
    await reviewG3(brightness);
  }
  await h.mount(
    release: true,
    scenario: SyntheticScenario.g3Building,
    showControls: true,
  );
  await chooseG3Scenario('G3 · Basis im Aufbau');
  await h.capture('g3-heute-baseline-building');
  await revealG3(find.text('KÖRPER'));
  expect(find.textContaining('Basis: noch 3 Nächte'), findsWidgets);
  await h.capture('g3-heute-baseline-building-scrolled');

  await h.mount(scenario: SyntheticScenario.g3Sample, showControls: true);
  await chooseG3Scenario('G3 · Tagesblatt');
  expect(find.bySemanticsLabel('Gesundheit'), findsOneWidget);
  await h.capture('g3-development-shell');
  await tester.tap(find.bySemanticsLabel('Gesundheit'));
  await tester.pumpAndSettle();
  await h.capture('g3-development-health');

  Future<void> mountBandView(
    Widget child, {
    Brightness brightness = Brightness.light,
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: openBandTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: child,
      ),
    );
    await tester.pumpAndSettle();
  }

  var pairingActions = 0;
  Widget pairingFixture({PairPhase initial = PairPhase.idle}) {
    var phase = initial;
    return StatefulBuilder(
      builder: (context, setState) => PairingView(
        phase: phase,
        blocker: phase == PairPhase.bluetoothBlocked
            ? BleBlocker.permissionDenied
            : null,
        onPair: () {
          pairingActions++;
          setState(() => phase = PairPhase.bluetoothBlocked);
        },
        onBack: () => pairingActions++,
        onSkip: () => pairingActions++,
      ),
    );
  }

  for (final brightness in [Brightness.light, Brightness.dark]) {
    final suffix = brightness == Brightness.light ? 'light' : 'dark';
    await mountBandView(pairingFixture(), brightness: brightness);
    expect(
      find.text('Noch nicht verbunden. Band nah ans iPhone halten.'),
      findsOneWidget,
    );
    await h.capture('release-pairing-$suffix');
    final pairAction = find.byType(g3chrome.OBActionPrimary).first;
    await tester.tap(pairAction);
    await tester.pumpAndSettle();
    expect(pairingActions, greaterThan(0));
    expect(
      find.text('Noch nicht verbunden. Band nah ans iPhone halten.'),
      findsNothing,
    );
    await h.capture('release-pairing-permission-$suffix');
  }
  await mountBandView(pairingFixture(), scale: 2);
  await h.capture('release-pairing-large');
  await tester.scrollUntilVisible(
    find.text('WHOOP-App schließen'),
    200,
    scrollable: h.verticalScrollable().last,
  );
  await h.capture('release-pairing-large-bottom');

  var resumeCalls = 0;
  var doneCalls = 0;
  FirstSyncScreen syncFixture() {
    var band = BandSnapshot(
      connection: BandConnection.connected,
      transfer: TransferState.interrupted,
      latestStoredAt: DateTime(2026, 9, 15, 2, 10),
    );
    return FirstSyncScreen(
      synthetic: true,
      now: () => DateTime(2026, 9, 15, 9, 41),
      onDone: () => doneCalls++,
      readBand: () async => band,
      readSetupEvaluation: (day) async => SetupEvaluation(
        day: day,
        currentAlgo: kAlgoVersion,
        state: SetupEvalState.missing,
      ),
      onResume: () async {
        resumeCalls++;
        band = BandSnapshot(
          connection: resumeCalls == 1
              ? BandConnection.disconnected
              : BandConnection.connected,
          transfer: TransferState.idle,
          latestStoredAt: DateTime(2026, 9, 15, 2, 10),
        );
      },
    );
  }

  for (final brightness in [Brightness.light, Brightness.dark]) {
    final suffix = brightness == Brightness.light ? 'light' : 'dark';
    resumeCalls = 0;
    await mountBandView(syncFixture(), brightness: brightness);
    expect(find.text('bis 02:10'), findsWidgets);
    await h.capture('release-sync-interrupted-$suffix');
    await tester.tap(find.text('Fortsetzen'));
    await tester.pumpAndSettle();
    expect(resumeCalls, 1);
    expect(find.text('Verbunden'), findsNothing);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    await h.capture('release-sync-failed-$suffix');
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(resumeCalls, 2);
    expect(find.text('Verbunden'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsNothing);
    expect(find.text('bis 02:10'), findsWidgets);
    await h.capture('release-sync-retry-$suffix');
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
  }
  expect(doneCalls, 2);
  resumeCalls = 0;
  await mountBandView(syncFixture(), scale: 2);
  await h.capture('release-sync-large');
  await tester.scrollUntilVisible(
    find.text('Fortsetzen'),
    240,
    scrollable: h.verticalScrollable().last,
  );
  await h.capture('release-sync-large-bottom');
  await tester.tap(find.text('Weiter'));
  await tester.pumpAndSettle();
  expect(doneCalls, 3);

  for (final brightness in [Brightness.light, Brightness.dark]) {
    final suffix = brightness == Brightness.light ? 'light' : 'dark';
    await mountBandView(
      FirstSyncView(
        synthetic: true,
        now: DateTime(2026, 9, 15, 9, 41),
        onDone: () {},
        band: BandSnapshot(
          connection: BandConnection.connected,
          transfer: TransferState.receiving,
          latestStoredAt: DateTime(2026, 9, 15, 6, 54),
        ),
      ),
      brightness: brightness,
    );
    expect(find.text('bis 06:54'), findsWidgets);
    await h.capture('release-sync-receiving-$suffix');
  }
  await mountBandView(
    FirstSyncView(
      synthetic: true,
      now: DateTime(2026, 9, 15, 9, 41),
      onDone: () {},
      band: BandSnapshot(
        connection: BandConnection.connected,
        transfer: TransferState.receiving,
        latestStoredAt: DateTime(2026, 9, 15, 6, 54),
      ),
    ),
    scale: 2,
  );
  await h.capture('release-sync-receiving-large');
  await tester.scrollUntilVisible(
    find.textContaining('Erst gespeichert'),
    200,
    scrollable: h.verticalScrollable().last,
  );
  await h.capture('release-sync-receiving-large-bottom');

  Future<OpenBandController> mountFreshStatus({
    Brightness brightness = Brightness.light,
    double scale = 1,
  }) async {
    final repository = await h.loadRepository();
    final controller = OpenBandController(
      repository: repository,
      initialDay: '2026-09-15',
      band: repository.band,
      now: () => DateTime(2026, 9, 15, 9, 41),
    );
    await controller.refresh();
    await mountBandView(
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: OBAction(
              'Datenstand öffnen',
              onPressed: () => showBandStatus(context, controller, () {}),
            ),
          ),
        ),
      ),
      brightness: brightness,
      scale: scale,
    );
    await tester.tap(find.text('Datenstand öffnen'));
    await tester.pumpAndSettle();
    return controller;
  }

  for (final brightness in [Brightness.light, Brightness.dark]) {
    final suffix = brightness == Brightness.light ? 'light' : 'dark';
    final controller = await mountFreshStatus(brightness: brightness);
    await h.capture('release-data-status-fresh-$suffix');
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    controller.dispose();
  }
  final largeStatus = await mountFreshStatus(scale: 2);
  await h.capture('release-data-status-fresh-large');
  await tester.scrollUntilVisible(
    find.text('Auswertung'),
    200,
    scrollable: h.verticalScrollable().last,
  );
  await h.capture('release-data-status-fresh-large-bottom');
  await tester.ensureVisible(find.text('Schließen'));
  await tester.tap(find.text('Schließen'));
  await tester.pumpAndSettle();
  largeStatus.dispose();

  final sensorQuery = TextEditingController();
  var scanCalls = 0;
  BleBlocker? scanBlocker = BleBlocker.permissionDenied;
  await mountBandView(
    StatefulBuilder(
      builder: (context, setState) => DevicePickerView(
        query: sensorQuery,
        title: 'Sensor verbinden',
        subtitle: 'Synthetische Daten',
        scanBlocker: scanBlocker,
        onScan: () => setState(() {
          scanCalls++;
          scanBlocker = null;
        }),
      ),
    ),
  );
  await h.capture('release-sensor-permission');
  final retry = find.text(
    AppLocalizations.of(
      tester.element(find.byType(DevicePickerView)),
    )!.pairingTryAgain,
  );
  await tester.tap(retry);
  await tester.pumpAndSettle();
  expect(scanCalls, 1);
  await h.capture('release-sensor-empty');
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  sensorQuery.dispose();
  return;
}
