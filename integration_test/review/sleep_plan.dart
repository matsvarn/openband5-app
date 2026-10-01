part of 'harness.dart';

Future<void> reviewSleepPlan(ReviewHarness h) async {
  final tester = h.tester;
  const day = '2026-09-15';
  const wakeDay = '2026-09-16';
  const pastDay = '2026-09-14';
  final now = DateTime(2026, 9, 15, 9, 41);
  final builtAt = DateTime(2026, 9, 15, 7, 42);
  final builtEpoch = builtAt.millisecondsSinceEpoch ~/ 1000;
  final inputReadStartedAtMs = builtAt.millisecondsSinceEpoch - 4000;
  final observationComputedAtMs = inputReadStartedAtMs - 1500;
  const needSeconds = 30805.714285714286;
  const bedtimeMinute = 1319.548872180451;
  const wakeMinute = 420.0;
  const baselineNeedSec = 28800.0;
  const sleepDebtSec = 1800.0;
  final strainBonusMin = (needSeconds - baselineNeedSec - sleepDebtSec) / 60;

  Map<String, dynamic> fixtureArtifact({
    int? algoVersion,
    bool times = true,
    bool window = true,
    bool provenance = true,
    double? need,
    double? nap = 0,
    required double? strain,
    double? bedtime,
    double? wake,
  }) {
    final dates = openBandDaysEnding(day, 14);
    return {
      'algo_version': algoVersion ?? kAlgoVersion,
      'built_for_day': day,
      'built_at_epoch': builtEpoch,
      if (provenance) 'input_read_started_at_ms': inputReadStartedAtMs,
      'sleep_coach': {
        'need': {
          'value': {'need_sec': need ?? needSeconds},
        },
        'nap_credit_min': nap ?? '—',
        'strain_bonus_min': strain ?? '—',
        'bedtime': times
            ? {
                'value': {'bedtime_min_of_day': bedtime ?? bedtimeMinute},
              }
            : '—',
        'wake': times
            ? {
                'value': {'wake_min_of_day': wake ?? wakeMinute},
              }
            : '—',
      },
      if (window) ...{
        'n_days': dates.length,
        'recent': [
          for (final date in dates) {'date': date},
        ],
      },
    };
  }

  List<SleepPlanDayObservation> fixtureObservations({
    Map<String, dynamic>? artifact,
    int? computedAtMs,
    bool skipped = false,
    bool inFetchWindow = true,
  }) {
    final recent = artifact?['recent'];
    if (recent is! List) return const [];
    final at = computedAtMs ?? observationComputedAtMs;
    return [
      for (final row in recent)
        if (row is Map && row['date'] is String)
          SleepPlanDayObservation(
            day: row['date'] as String,
            computedAtMs: at,
            skipped: skipped,
            inFetchWindow: inFetchWindow,
          ),
    ];
  }

  Future<_SleepPlanReviewRepo> loadRepo() async {
    Future<Map> load(String name) => h.fixture(name);
    final repo = _SleepPlanReviewRepo(
      await load('day-summary'),
      await load('sleep-detail'),
      activity: await load('additional-flows'),
      run: await load('run-detail'),
    );
    await repo.seedNutritionGoals();
    repo.seedCaffeineSleepPattern(day);
    repo.sleepPlanNow = () => now;
    repo.sleepPlanArtifact = fixtureArtifact(strain: strainBonusMin);
    repo.sleepPlanJobs = const [];
    repo.sleepPlanObservations = fixtureObservations(
      artifact: repo.sleepPlanArtifact,
    );
    return repo;
  }

  void resetPlan(
    _SleepPlanReviewRepo repository, {
    Map<String, dynamic>? artifact,
    bool missingArtifact = false,
    List<SleepPlanDayObservation>? observations,
  }) {
    repository.failSleepPlanRead = false;
    repository.sleepPlanJobs = const [];
    repository.sleepPlanArtifact = missingArtifact
        ? null
        : artifact ?? fixtureArtifact(strain: strainBonusMin);
    repository.sleepPlanObservations =
        observations ??
        fixtureObservations(artifact: repository.sleepPlanArtifact);
    repository.requestedDays.clear();
    repository.clocks.clear();
  }

  Finder downScrollable(Finder ancestor) => find.descendant(
    of: ancestor,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    ),
  );

  Future<void> revealIn(Finder ancestor, Finder target) async {
    final scrollable = downScrollable(ancestor).first;
    var scrolls = 0;
    while (target.evaluate().isEmpty ||
        target.hitTestable().evaluate().isEmpty) {
      if (scrolls >= 32) {
        throw FlutterError(
          'Control is not hit-testable after production scrolling.',
        );
      }
      if (target.evaluate().isEmpty) {
        final position = tester.state<ScrollableState>(scrollable).position;
        final atMax = position.pixels >= position.maxScrollExtent - 0.5;
        if (atMax) {
          throw FlutterError(
            'Control is not hit-testable after production scrolling.',
          );
        }
        await tester.drag(scrollable, const Offset(0, -64));
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

  double scrollPixels(Finder ancestor) => tester
      .state<ScrollableState>(downScrollable(ancestor).first)
      .position
      .pixels;

  Future<void> restoreScroll(Finder ancestor, double offset) async {
    final position = tester
        .state<ScrollableState>(downScrollable(ancestor).first)
        .position;
    position.jumpTo(
      offset.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
    await tester.pump();
  }

  Rect reviewSafeViewport() {
    final view = tester.view;
    final dpr = view.devicePixelRatio;
    final size = view.physicalSize / dpr;
    final pad = view.viewPadding;
    return Rect.fromLTRB(
      pad.left / dpr,
      pad.top / dpr,
      size.width - pad.right / dpr,
      size.height - pad.bottom / dpr,
    );
  }

  bool rectInSafeViewport(Rect box) {
    final safe = reviewSafeViewport();
    return box.top >= safe.top &&
        box.bottom <= safe.bottom &&
        box.left >= safe.left &&
        box.right <= safe.right;
  }

  Future<void> pumpUntilPlanReady() async {
    await tester.pump();
    var frames = 0;
    while (find.byType(OpenBandSleepPlan).evaluate().isEmpty ||
        find.text('GESCHÄTZTER SCHLAFBEDARF').evaluate().isEmpty) {
      if (++frames > 80) {
        throw FlutterError('Sleep plan did not finish loading.');
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
    await reviewPumpPageTransitions(tester);
  }

  Future<void> pumpHostReady(Finder home) async {
    await tester.pump();
    var frames = 0;
    while (home.evaluate().isEmpty) {
      if (++frames > 80) {
        throw FlutterError('Sleep host did not finish loading.');
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
    await reviewPumpPageTransitions(tester);
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

  Future<OpenBandController> mountSleep({
    required _SleepPlanReviewRepo repository,
    Brightness brightness = Brightness.light,
    double scale = 1,
    String selectedDay = day,
    DateTime? clock,
  }) async {
    final wall = clock ?? now;
    final controller = OpenBandController(
      repository: repository,
      initialDay: selectedDay,
      band: repository.band,
      now: () => wall,
    );
    await controller.refresh();
    await tester.pumpWidget(
      reviewHost(
        brightness: brightness,
        scale: scale,
        home: OpenBandSleep(controller: controller),
      ),
    );
    await pumpHostReady(find.byType(OpenBandSleep));
    return controller;
  }

  Future<void> mountPlan({
    required _SleepPlanReviewRepo repository,
    Brightness brightness = Brightness.light,
    double scale = 1,
    String planDay = day,
  }) async {
    await tester.pumpWidget(
      reviewHost(
        brightness: brightness,
        scale: scale,
        home: OpenBandSleepPlan(
          repository: repository,
          day: planDay,
          now: () => now,
          synthetic: true,
        ),
      ),
    );
    await pumpUntilPlanReady();
  }

  Future<void> openTonight() async {
    final tonight = find.text('Heute Nacht');
    await revealIn(find.byType(OpenBandSleep), tonight);
    expect(tonight.hitTestable(), findsOneWidget);
    await tester.tap(tonight.hitTestable());
    await pumpUntilPlanReady();
  }

  Finder goalLink() => find.descendant(
    of: find.byType(OBSettingsValueRow),
    matching: find.text('Eigenes Schlafziel'),
  );

  Future<void> popPlan() async {
    final back = find.byTooltip('Zurück');
    expect(back, findsWidgets);
    await tester.tap(back.last);
    await reviewPumpPageTransitions(tester);
    await tester.pump();
  }

  void expectFixtureNumbers(ComingNightSleepPlan plan) {
    expect(plan.needSeconds, closeTo(needSeconds, 0.0001));
    expect(plan.needSeconds, closeTo(30805.7142857, 0.0001));
    expect(plan.bedtimeMinuteOfDay, closeTo(bedtimeMinute, 0.0001));
    expect(plan.bedtimeMinuteOfDay, closeTo(1319.548872, 0.0001));
    expect(plan.wakeMinuteOfDay, closeTo(wakeMinute, 0.0001));
    expect(plan.wakeMinuteOfDay, closeTo(420, 0.0001));
    expect(plan.napCreditMin, 0);
    expect(plan.napCreditMin, isNotNull);
    expect(plan.strainBonusMin, closeTo(strainBonusMin, 0.0001));
    expect(plan.strainBonusMin, closeTo(3.42857, 0.0001));
    expect(plan.algoVersion, kAlgoVersion);
    expect(plan.nightStartDay, day);
    expect(plan.wakeDay, wakeDay);
  }

  void expectFullPlanCopy() {
    expect(find.text('HEUTE NACHT'), findsOneWidget);
    expect(find.text('15./16. September'), findsOneWidget);
    expect(find.text('GESCHÄTZTER SCHLAFBEDARF'), findsOneWidget);
    expect(find.text('8h33'), findsOneWidget);
    expect(find.text('Stand 07:42'), findsOneWidget);
    expect(find.text('22:00'), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);
    expect(find.text('Noch keine Schätzung'), findsNothing);
    expect(find.text('Laden fehlgeschlagen'), findsNothing);
    expect(find.text('Belastung fehlt'), findsNothing);
    expect(find.text('Nickerchen unvollständig'), findsNothing);
    expect(find.text('Aktualität unbekannt'), findsNothing);
    expect(find.text('Zeitplanung unvollständig'), findsNothing);
    expect(find.text('Aufwachzeiten fehlen'), findsNothing);
  }

  final repository = await loadRepo();
  expect(strainBonusMin, closeTo(3.42857, 0.0001));
  final artifact = repository.sleepPlanArtifact!;
  expect(artifact['algo_version'], kAlgoVersion);
  expect(artifact['built_for_day'], day);
  expect(artifact['built_at_epoch'], builtEpoch);
  expect(artifact['input_read_started_at_ms'], inputReadStartedAtMs);
  expect(artifact['n_days'], 14);
  final recent = artifact['recent'] as List;
  expect(recent, isNotEmpty);
  final recentDates = [
    for (final row in recent) (row as Map)['date'] as String,
  ];
  expect(recentDates.toSet().length, recentDates.length);
  expect(recentDates.every((date) => date.compareTo(day) <= 0), isTrue);
  expect(recentDates.last, day);
  expect(artifact['n_days'], recentDates.length);
  expect(repository.sleepPlanObservations, isNotEmpty);
  expect(
    repository.sleepPlanObservations.map((row) => row.day).toList(),
    recentDates,
  );
  expect(
    repository.sleepPlanObservations.every(
      (row) =>
          row.inFetchWindow &&
          !row.skipped &&
          row.computedAtMs != null &&
          row.computedAtMs! < inputReadStartedAtMs,
    ),
    isTrue,
  );

  final mapped = sleepPlanFromStoredCrossday(
    requestedDay: day,
    now: now,
    algoVersion: kAlgoVersion,
    artifact: artifact,
    jobs: repository.sleepPlanJobs,
    observations: repository.sleepPlanObservations,
  );
  expect(mapped.status, SleepPlanStatus.available);
  expect(mapped.plan, isNotNull);
  expect(mapped.plan!.freshness, SleepPlanFreshness.fresh);
  expectFixtureNumbers(mapped.plan!);
  expect(mapped.plan!.napCreditMin, 0);
  expect(mapped.plan!.napCreditMin, isNotNull);

  var controller = await mountSleep(repository: repository);
  expect(controller.selectedDay, day);
  await revealIn(find.byType(OpenBandSleep), find.text('Schlafziel'));
  expect(find.text('Schlafziel'), findsOneWidget);
  await revealIn(find.byType(OpenBandSleep), find.text('Heute Nacht'));
  expect(find.text('Heute Nacht').hitTestable(), findsOneWidget);
  await h.capture('sleep-plan-parent');
  await openTonight();
  expect(
    tester.widget<OpenBandSleepPlan>(find.byType(OpenBandSleepPlan)).day,
    day,
  );
  expect(repository.requestedDays, contains(day));
  expect(repository.clocks, isNotEmpty);
  expect(repository.clocks.every((clock) => clock != null), isTrue);
  expect(controller.selectedDay, day);
  expectFullPlanCopy();
  final source = await repository.readSleepPlan(day, now: now);
  expect(source.plan, isNotNull);
  expectFixtureNumbers(source.plan!);
  await h.capture('sleep-plan');

  await tester.tap(find.byTooltip('Zur Schätzung'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.text('Zur Schätzung'), findsWidgets);
  expect(
    find.text(
      'Aus gespeicherten Nächten, Belastung und Nickerchen. Kein gemessener persönlicher Schlafbedarf.',
    ),
    findsOneWidget,
  );
  expect(
    find.text(
      'Die Abendplanung nutzt typische Aufwachzeiten und Schlafeffizienz. Sie stellt keinen Wecker.',
    ),
    findsOneWidget,
  );
  expect(
    find.text(
      'Berücksichtigt: Belastung +3 Min. · Nickerchen 0 Min. Stand 15. September, 07:42 · Modell $kAlgoVersion.',
    ),
    findsOneWidget,
  );
  expect(
    find.text('Die Zeitzone der Berechnung wurde nicht gespeichert.'),
    findsOneWidget,
  );
  expect(find.textContaining('Nickerchen 0 Min'), findsWidgets);
  expect(find.textContaining('Nickerchen unvollständig'), findsNothing);
  await h.capture('sleep-plan-info');
  await tester.tap(find.byTooltip('Schließen'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.text('8h33'), findsOneWidget);

  await revealIn(find.byType(OpenBandSleepPlan), goalLink());
  await tester.tap(goalLink().hitTestable());
  await tester.pump();
  var goalFrames = 0;
  while (find.byType(OpenBandSleepGoal).evaluate().isEmpty ||
      find.text('Ab 16. September').evaluate().isEmpty) {
    if (++goalFrames > 80) {
      throw FlutterError('Sleep goal did not finish loading.');
    }
    await tester.pump(const Duration(milliseconds: 16));
  }
  await reviewPumpPageTransitions(tester);
  expect(
    tester.widget<OpenBandSleepGoal>(find.byType(OpenBandSleepGoal)).day,
    wakeDay,
  );
  expect(controller.selectedDay, day);
  await h.capture('sleep-plan-goal');
  await popPlan();
  expect(find.byType(OpenBandSleepPlan), findsOneWidget);
  expect(
    tester.widget<OpenBandSleepPlan>(find.byType(OpenBandSleepPlan)).day,
    day,
  );
  expect(controller.selectedDay, day);
  await popPlan();
  expect(find.byType(OpenBandSleepPlan), findsNothing);
  expect(find.byType(OpenBandSleep), findsOneWidget);
  expect(controller.selectedDay, day);
  await revealIn(find.byType(OpenBandSleep), find.text('Heute Nacht'));
  expect(find.text('Heute Nacht').hitTestable(), findsOneWidget);
  await h.capture('sleep-plan-parent-return');
  controller.dispose();

  resetPlan(repository);
  controller = await mountSleep(
    repository: repository,
    brightness: Brightness.dark,
  );
  await openTonight();
  expectFullPlanCopy();
  await h.capture('sleep-plan-dark');
  await tester.tap(find.byTooltip('Zur Schätzung'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(
    find.text(
      'Berücksichtigt: Belastung +3 Min. · Nickerchen 0 Min. Stand 15. September, 07:42 · Modell $kAlgoVersion.',
    ),
    findsOneWidget,
  );
  await h.capture('sleep-plan-info-dark');
  await tester.tap(find.byTooltip('Schließen'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  controller.dispose();

  resetPlan(repository, missingArtifact: true);
  await mountPlan(repository: repository);
  expect(find.text('8h33'), findsNothing);
  expect(find.text('—'), findsWidgets);
  expect(find.text('Noch keine Schätzung'), findsOneWidget);
  expect(find.text('Laden fehlgeschlagen'), findsNothing);
  await h.capture('sleep-plan-empty');
  await mountPlan(repository: repository, brightness: Brightness.dark);
  expect(find.text('Noch keine Schätzung'), findsOneWidget);
  await h.capture('sleep-plan-empty-dark');

  resetPlan(
    repository,
    artifact: fixtureArtifact(times: false, strain: strainBonusMin),
  );
  await mountPlan(repository: repository);
  expect(find.text('8h33'), findsOneWidget);
  expect(find.text('Stand 07:42'), findsOneWidget);
  expect(find.text('22:00'), findsNothing);
  expect(find.text('07:00'), findsNothing);
  expect(find.text('Zeitplanung unvollständig'), findsOneWidget);
  expect(find.text('Aufwachzeiten fehlen'), findsNothing);
  await h.capture('sleep-plan-partial');
  await mountPlan(repository: repository, brightness: Brightness.dark);
  expect(find.text('Zeitplanung unvollständig'), findsOneWidget);
  expect(find.text('Aufwachzeiten fehlen'), findsNothing);
  await h.capture('sleep-plan-partial-dark');

  resetPlan(repository);
  repository.failSleepPlanRead = true;
  await mountPlan(repository: repository);
  expect(find.text('Laden fehlgeschlagen'), findsOneWidget);
  expect(find.text('Erneut versuchen').hitTestable(), findsOneWidget);
  expect(find.text('8h33'), findsNothing);
  expect(find.text('Noch keine Schätzung'), findsNothing);
  await h.capture('sleep-plan-error');
  repository.failSleepPlanRead = false;
  await tester.tap(find.text('Erneut versuchen').hitTestable());
  await tester.pump();
  var retryFrames = 0;
  while (find.text('8h33').evaluate().isEmpty) {
    if (++retryFrames > 80) {
      throw FlutterError('Sleep plan retry did not restore the fixture.');
    }
    await tester.pump(const Duration(milliseconds: 16));
  }
  await reviewPumpPageTransitions(tester);
  expect(find.text('8h33'), findsOneWidget);
  expect(find.text('Laden fehlgeschlagen'), findsNothing);
  await h.capture('sleep-plan-error-retry');
  repository.failSleepPlanRead = true;
  await mountPlan(repository: repository, brightness: Brightness.dark);
  expect(find.text('Laden fehlgeschlagen'), findsOneWidget);
  await h.capture('sleep-plan-error-dark');

  resetPlan(
    repository,
    observations: fixtureObservations(
      artifact: fixtureArtifact(strain: strainBonusMin),
      computedAtMs: inputReadStartedAtMs,
    ),
  );
  await mountPlan(repository: repository);
  expect(find.text('8h33'), findsNothing);
  expect(find.text('22:00'), findsNothing);
  expect(find.text('Schätzung nicht aktuell'), findsOneWidget);
  expect(find.text('Noch keine Schätzung'), findsNothing);
  await h.capture('sleep-plan-stale');

  resetPlan(
    repository,
    artifact: fixtureArtifact(need: 100, strain: strainBonusMin),
  );
  await mountPlan(repository: repository);
  expect(find.text('8h33'), findsNothing);
  expect(find.text('Schätzung nicht lesbar'), findsOneWidget);
  expect(find.text('Noch keine Schätzung'), findsNothing);
  await h.capture('sleep-plan-corrupt');

  resetPlan(
    repository,
    artifact: fixtureArtifact(
      window: false,
      provenance: false,
      strain: strainBonusMin,
    ),
  );
  await mountPlan(repository: repository);
  expect(find.text('8h33'), findsOneWidget);
  expect(find.text('Aktualität unbekannt'), findsOneWidget);
  expect(find.text('Stand 07:42'), findsNothing);
  await h.capture('sleep-plan-unknown');

  resetPlan(repository, artifact: fixtureArtifact(strain: null, nap: 0));
  await mountPlan(repository: repository);
  final missing = await repository.readSleepPlan(day, now: now);
  expect(missing.plan, isNotNull);
  expect(missing.plan!.napCreditMin, 0);
  expect(missing.plan!.napCreditMin, isNotNull);
  expect(missing.plan!.strainBonusMin, isNull);
  expect(find.text('8h33'), findsOneWidget);
  expect(find.text('Belastung fehlt'), findsOneWidget);
  expect(find.text('Nickerchen unvollständig'), findsNothing);
  await tester.tap(find.byTooltip('Zur Schätzung'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.textContaining('Belastung fehlt'), findsWidgets);
  expect(find.textContaining('Nickerchen 0 Min'), findsOneWidget);
  await tester.tap(find.byTooltip('Schließen'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await h.capture('sleep-plan-missing-contribution');

  resetPlan(
    repository,
    artifact: fixtureArtifact(strain: strainBonusMin, nap: null),
  );
  await mountPlan(repository: repository);
  final nullNap = await repository.readSleepPlan(day, now: now);
  expect(nullNap.plan, isNotNull);
  expect(nullNap.plan!.napCreditMin, isNull);
  expect(nullNap.plan!.strainBonusMin, isNotNull);
  expect(find.text('Nickerchen unvollständig'), findsOneWidget);
  expect(find.text('Belastung fehlt'), findsNothing);

  Future<void> captureScaled({
    required String name,
    required Brightness brightness,
    required bool scrolled,
  }) async {
    resetPlan(repository);
    await mountPlan(repository: repository, brightness: brightness, scale: 2);
    expect(find.text('8h33'), findsOneWidget);
    final plan = find.byType(OpenBandSleepPlan);
    final origin = scrollPixels(plan);
    final bedLabel = find.text('INS BETT · GESCHÄTZT');
    await revealIn(plan, bedLabel);
    final bedBottom = tester.getRect(bedLabel).bottom + scrollPixels(plan);
    final riseLabel = find.text('AUFSTEHEN · TYPISCH');
    await revealIn(plan, riseLabel);
    final riseTop = tester.getRect(riseLabel).top + scrollPixels(plan);
    expect(riseTop, greaterThan(bedBottom + 8));
    final goal = goalLink();
    if (scrolled) {
      await revealIn(plan, goal);
      expect(goal.evaluate(), isNotEmpty);
      final card = find.ancestor(of: goal, matching: find.byType(OBCard)).first;
      final row = find
          .ancestor(of: goal, matching: find.byType(OBSettingsValueRow))
          .first;
      await Scrollable.ensureVisible(tester.element(card), alignment: 1.0);
      await tester.pump();
      final scrollable = downScrollable(plan).first;
      var extra = 0;
      while (!rectInSafeViewport(tester.getRect(card)) ||
          !rectInSafeViewport(tester.getRect(row))) {
        if (extra >= 32) {
          throw FlutterError(
            'Goal card is not fully within the safe viewport: '
            'card=${tester.getRect(card)}, row=${tester.getRect(row)}, '
            'safe=${reviewSafeViewport()}, scroll=${scrollPixels(plan)}.',
          );
        }
        final box = tester.getRect(card);
        final safe = reviewSafeViewport();
        final overflowBottom = box.bottom - safe.bottom;
        final overflowTop = safe.top - box.top;
        final dy = overflowBottom > 0 ? -(overflowBottom + 8) : overflowTop + 8;
        await tester.drag(scrollable, Offset(0, dy.clamp(-96.0, 96.0)));
        await tester.pump();
        extra++;
      }
      await tester.pump();
      final safe = reviewSafeViewport();
      final cardBox = tester.getRect(card);
      final rowBox = tester.getRect(row);
      expect(cardBox.top, greaterThanOrEqualTo(safe.top));
      expect(cardBox.bottom, lessThanOrEqualTo(safe.bottom));
      expect(cardBox.left, greaterThanOrEqualTo(safe.left));
      expect(cardBox.right, lessThanOrEqualTo(safe.right));
      expect(rowBox.top, greaterThanOrEqualTo(safe.top));
      expect(rowBox.bottom, lessThanOrEqualTo(safe.bottom));
      expect(rowBox.left, greaterThanOrEqualTo(safe.left));
      expect(rowBox.right, lessThanOrEqualTo(safe.right));
      expect(goal.hitTestable(), findsOneWidget);
      expect(card.hitTestable(), findsOneWidget);
      await h.capture(name);
      await tester.tap(card.hitTestable());
      await tester.pump();
      var goalFrames = 0;
      while (find.byType(OpenBandSleepGoal).evaluate().isEmpty ||
          find.text('Ab 16. September').evaluate().isEmpty) {
        if (++goalFrames > 80) {
          throw FlutterError('Sleep goal did not finish loading at 2x.');
        }
        await tester.pump(const Duration(milliseconds: 16));
      }
      await reviewPumpPageTransitions(tester);
      expect(
        tester.widget<OpenBandSleepGoal>(find.byType(OpenBandSleepGoal)).day,
        wakeDay,
      );
      await popPlan();
      expect(find.byType(OpenBandSleepPlan), findsOneWidget);
      expect(
        tester.widget<OpenBandSleepPlan>(find.byType(OpenBandSleepPlan)).day,
        day,
      );
    } else {
      await restoreScroll(plan, origin);
      expect(find.text('HEUTE NACHT'), findsOneWidget);
      expect(find.text('8h33'), findsOneWidget);
      await h.capture(name);
    }
  }

  await captureScaled(
    name: 'sleep-plan-2x',
    brightness: Brightness.light,
    scrolled: false,
  );
  await captureScaled(
    name: 'sleep-plan-2x-scrolled',
    brightness: Brightness.light,
    scrolled: true,
  );
  await captureScaled(
    name: 'sleep-plan-2x-dark',
    brightness: Brightness.dark,
    scrolled: false,
  );
  await captureScaled(
    name: 'sleep-plan-2x-scrolled-dark',
    brightness: Brightness.dark,
    scrolled: true,
  );

  resetPlan(repository);
  controller = await mountSleep(repository: repository, selectedDay: pastDay);
  expect(controller.selectedDay, pastDay);
  await revealIn(find.byType(OpenBandSleep), find.text('Schlafziel'));
  expect(find.text('Heute Nacht'), findsNothing);
  expect(find.text('Schlafziel').hitTestable(), findsOneWidget);
  expect(repository.requestedDays, isEmpty);
  await h.capture('sleep-plan-parent-past');
  controller.dispose();
}
