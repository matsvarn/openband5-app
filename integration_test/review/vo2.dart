part of 'harness.dart';

Future<void> reviewVo2(ReviewHarness h) async {
  final tester = h.tester;
  const day = '2026-09-15';
  final now = DateTime(2026, 9, 15, 9, 41);
  final measured = kSyntheticVo2PaperDay;
  String shortDate(String value) {
    final date = DateTime.parse(value);
    return DateFormat(
      date.year == now.year ? 'd. MMM' : 'd. MMM y',
      'de_DE',
    ).format(date);
  }

  const measuredShort = '14. Sept.';
  final paperValue = obNumber(kSyntheticVo2PaperValue, digits: 1);
  final paperLine = '$measuredShort · $kSyntheticVo2PaperMethod';
  final healthValue = '$paperValue $kVo2Unit';
  final healthWhen = 'Eingetragen · $measuredShort';

  Future<_Vo2ReviewRepo> mountVo2({
    Brightness brightness = Brightness.light,
    double scale = 1,
    _Vo2ReviewRepo? repository,
    bool seed = true,
    bool readError = false,
  }) async {
    final mounted = repository ?? await _loadVo2ReviewRepo(h);
    if (seed) mounted.seedVo2Paper();
    mounted.failVo2Read = readError;
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
        home: OpenBandVo2(repository: mounted, endDay: day, now: () => now),
      ),
    );
    await tester.pumpAndSettle();
    return mounted;
  }

  Finder pageScroll() => find.descendant(
    of: find.byKey(const ValueKey('vo2-scroll')),
    matching: find.byType(Scrollable),
  );

  Future<void> show(Finder target, {Finder? scrollable}) async {
    var scroll = scrollable ?? pageScroll();
    final matches = scroll.evaluate();
    if (matches.length > 1) {
      final outer = {
        for (final element in matches)
          if (element.findAncestorWidgetOfExactType<EditableText>() == null)
            element,
      };
      scroll = find.byElementPredicate(outer.contains);
    }
    if (scroll.evaluate().isNotEmpty) {
      await tester.scrollUntilVisible(target, 200, scrollable: scroll);
    }
    await tester.ensureVisible(target);
    await tester.pump();
  }

  String? heroText() => tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('vo2-hero-value')),
          matching: find.byType(Text),
          matchRoot: true,
        ),
      )
      .data;

  String fieldText(String key) =>
      tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

  Future<void> openEditor() async {
    final hero = find.byKey(const ValueKey('vo2-hero-edit'));
    await show(hero);
    await tester.tap(hero);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('vo2-editor')), findsOneWidget);
  }

  Future<void> saveEditor() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    final save = find.byKey(const ValueKey('vo2-save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
  }

  final healthRepository = await _loadVo2ReviewRepo(h);
  healthRepository.seedVo2Paper();
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
  final healthRow = find.byKey(const ValueKey('vo2-health-row'));
  await tester.scrollUntilVisible(
    healthRow,
    200,
    scrollable: h.verticalScrollable().last,
  );
  await tester.pumpAndSettle();
  expect(
    find.descendant(of: healthRow, matching: find.text('VO₂max')),
    findsOneWidget,
  );
  expect(
    find.descendant(of: healthRow, matching: find.text(healthWhen)),
    findsOneWidget,
  );
  expect(
    find.descendant(of: healthRow, matching: find.text(healthValue)),
    findsOneWidget,
  );
  expect(
    find.descendant(of: healthRow, matching: find.text('Eintrag nicht lesbar')),
    findsNothing,
  );
  expect(
    find.descendant(
      of: healthRow,
      matching: find.textContaining('Teilweise lesbar'),
    ),
    findsNothing,
  );
  await h.capture('vo2-health-entry');
  await tester.tap(healthRow);
  await tester.pumpAndSettle();
  expect(find.byType(OpenBandVo2), findsOneWidget);
  expect(heroText(), paperValue);
  expect(find.text(paperLine), findsOneWidget);
  await h.capture('vo2-health-detail');
  await openEditor();
  expect(fieldText('vo2-value-input'), '42');
  await tester.enterText(find.byKey(const ValueKey('vo2-value-input')), '42,5');
  await saveEditor();
  expect(find.byType(OpenBandVo2), findsOneWidget);
  await reviewTapHeaderBack(tester);
  await tester.pumpAndSettle();
  final refreshed = '${obNumber(42.5, digits: 1)} $kVo2Unit';
  expect(
    find.descendant(of: healthRow, matching: find.text(refreshed)),
    findsOneWidget,
  );
  expect(
    find.descendant(of: healthRow, matching: find.text(healthWhen)),
    findsOneWidget,
  );
  await h.capture('vo2-health-refreshed');
  await tester.tap(healthRow);
  await tester.pumpAndSettle();
  healthRepository.failVo2Read = true;
  await reviewTapHeaderBack(tester);
  await tester.pumpAndSettle();
  expect(
    find.descendant(of: healthRow, matching: find.text('Laden fehlgeschlagen')),
    findsOneWidget,
  );
  expect(
    find.descendant(of: healthRow, matching: find.text(refreshed)),
    findsNothing,
  );
  await h.capture('vo2-health-refresh-error');
  healthRepository.failVo2Read = false;

  final overview = await mountVo2();
  healthController.dispose();
  expect(heroText(), paperValue);
  expect(find.text(paperLine), findsOneWidget);
  expect(
    find.byKey(ValueKey('vo2-entry-$kSyntheticVo2PaperId')),
    findsOneWidget,
  );
  await h.capture('vo2-light');
  await tester.tap(find.byTooltip('Über VO₂max'));
  await tester.pumpAndSettle();
  expect(find.text('Über VO₂max'), findsOneWidget);
  expect(find.text('Quelle: Eigener Eintrag · ml/kg/min'), findsOneWidget);
  expect(find.text('Datum und Methode: laut Eingabe.'), findsOneWidget);
  expect(
    find.text('Einordnung: kein Referenzbereich hinterlegt.'),
    findsOneWidget,
  );
  await h.capture('vo2-info');
  await tester.tap(find.text('Schließen'));
  await tester.pumpAndSettle();

  await mountVo2(brightness: Brightness.dark);
  expect(find.text(paperLine), findsOneWidget);
  await h.capture('vo2-dark');

  await mountVo2(repository: overview, seed: false);
  await openEditor();
  expect(fieldText('vo2-value-input'), '42');
  expect(fieldText('vo2-method-input'), kSyntheticVo2PaperMethod);
  await h.capture('vo2-edit');
  await tester.tap(find.byTooltip('Schließen'));
  await tester.pumpAndSettle();

  final blank = await mountVo2(seed: false);
  expect(find.text('Noch keine Einträge'), findsOneWidget);
  expect(find.text('Einträge konnten nicht geladen werden.'), findsNothing);
  expect(find.byKey(const ValueKey('vo2-add-empty')), findsOneWidget);
  await h.capture('vo2-empty');
  await tester.tap(find.byKey(const ValueKey('vo2-add-empty')));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('vo2-editor')), findsOneWidget);
  expect(fieldText('vo2-value-input'), isEmpty);
  expect(fieldText('vo2-method-input'), isEmpty);
  expect(find.byKey(const ValueKey('vo2-remove')), findsNothing);
  await h.capture('vo2-new');
  await tester.enterText(find.byKey(const ValueKey('vo2-value-input')), '42');
  await tester.enterText(
    find.byKey(const ValueKey('vo2-method-input')),
    kSyntheticVo2PaperMethod,
  );
  await h.tap(find.byKey(const ValueKey('vo2-date-input')));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('vo2-calendar')), findsOneWidget);
  expect(find.byType(DatePickerDialog), findsNothing);
  final day14 = DateTime(2026, 9, 14);
  final dayLabel = DateFormat('EEEE, d. MMMM yyyy', 'de_DE').format(day14);
  final calendarScroll = find.descendant(
    of: find.byKey(const ValueKey('vo2-calendar')),
    matching: find.byType(Scrollable),
  );
  final dayTarget = find.bySemanticsLabel(dayLabel);
  await tester.scrollUntilVisible(dayTarget, 120, scrollable: calendarScroll);
  await tester.tap(dayTarget);
  await tester.pumpAndSettle();
  await show(
    find.byKey(const ValueKey('vo2-date-apply')),
    scrollable: calendarScroll,
  );
  await h.capture('vo2-date');
  await tester.tap(find.byKey(const ValueKey('vo2-date-apply')));
  await tester.pumpAndSettle();
  expect(
    find.text(DateFormat('d. MMMM y', 'de_DE').format(day14)),
    findsOneWidget,
  );
  await saveEditor();
  expect(heroText(), paperValue);
  expect(find.text(paperLine), findsOneWidget);
  final savedRow = find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith('vo2-entry-');
  });
  expect(savedRow, findsOneWidget);
  final savedId = (tester.widget(savedRow).key! as ValueKey<String>).value
      .substring('vo2-entry-'.length);
  final saved = await blank.readVo2Entry(savedId);
  expect(saved.head?.measuredOn, measured);
  expect(saved.head?.valueMlKgMin, kSyntheticVo2PaperValue);
  expect(saved.head?.declaredMethod, kSyntheticVo2PaperMethod);
  expect(saved.head?.id, savedId);
  await h.capture('vo2-saved');

  final history = await _vo2HistoryFixture(h);
  await mountVo2(repository: history, seed: false);
  await openEditor();
  final changes = find.byKey(const ValueKey('vo2-history'));
  await show(
    changes,
    scrollable: find.descendant(
      of: find.byKey(const ValueKey('vo2-editor')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.tap(changes);
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('vo2-history-page')), findsOneWidget);
  final at0940 = DateTime(2026, 9, 15, 9, 40);
  final at0941 = DateTime(2026, 9, 15, 9, 41);
  String stamp(DateTime time) =>
      '${shortDate(dayLabelOf(time))} · ${DateFormat('HH:mm', 'de_DE').format(time)}';
  expect(find.text(stamp(at0941)), findsOneWidget);
  expect(find.text(stamp(at0940)), findsOneWidget);
  expect(
    find.text('Wert vom ${shortDate(measured)} · $kSyntheticVo2PaperMethod'),
    findsOneWidget,
  );
  expect(
    find.text('Wert vom ${shortDate(measured)} · Methode \u2014'),
    findsOneWidget,
  );
  await h.capture('vo2-revisions');
  await reviewTapHeaderBack(tester);

  final removable = await mountVo2();
  await openEditor();
  final remove = find.byKey(const ValueKey('vo2-remove'));
  await tester.ensureVisible(remove);
  await tester.tap(remove);
  await tester.pumpAndSettle();
  expect(find.text('Entfernt'), findsOneWidget);
  expect(
    find.byKey(ValueKey('vo2-removed-$kSyntheticVo2PaperId')),
    findsOneWidget,
  );
  expect(find.byKey(ValueKey('vo2-entry-$kSyntheticVo2PaperId')), findsNothing);
  await h.capture('vo2-removed-section');
  await tester.tap(find.byKey(ValueKey('vo2-removed-$kSyntheticVo2PaperId')));
  await tester.pumpAndSettle();
  final removedPage = find.ancestor(
    of: find.byKey(const ValueKey('vo2-restore')),
    matching: find.byType(Scaffold),
  );
  Finder onRemoved(Finder match) =>
      find.descendant(of: removedPage, matching: match);
  expect(onRemoved(find.text('Entfernt')), findsOneWidget);
  expect(onRemoved(find.text(paperValue)), findsOneWidget);
  expect(onRemoved(find.text(paperLine)), findsOneWidget);
  expect(find.byKey(const ValueKey('vo2-restore')), findsOneWidget);
  await h.capture('vo2-removed');
  await tester.tap(find.byKey(const ValueKey('vo2-restore')));
  await tester.pumpAndSettle();
  expect(
    find.byKey(ValueKey('vo2-entry-$kSyntheticVo2PaperId')),
    findsOneWidget,
  );
  expect(
    find.byKey(ValueKey('vo2-removed-$kSyntheticVo2PaperId')),
    findsNothing,
  );
  final restored = await removable.readVo2Entry(kSyntheticVo2PaperId);
  expect(restored.head?.id, kSyntheticVo2PaperId);
  expect(restored.head?.deleted, isFalse);
  await h.capture('vo2-restored');

  final failingRead = await mountVo2(readError: true);
  expect(find.text('Einträge konnten nicht geladen werden.'), findsOneWidget);
  expect(find.text('Noch keine Einträge'), findsNothing);
  expect(find.text(paperValue), findsNothing);
  expect(find.byKey(const ValueKey('vo2-read-retry')), findsOneWidget);
  await h.capture('vo2-read-error');
  failingRead.failVo2Read = false;
  await tester.tap(find.byKey(const ValueKey('vo2-read-retry')));
  await tester.pumpAndSettle();
  expect(find.text('Einträge konnten nicht geladen werden.'), findsNothing);
  expect(heroText(), paperValue);
  await h.capture('vo2-read-retry');

  final partial = await _loadVo2ReviewRepo(h);
  final live = await partial.createVo2Entry(
    id: 'vo2-live',
    measuredOn: measured,
    valueMlKgMin: kSyntheticVo2PaperValue,
    declaredMethod: kSyntheticVo2PaperMethod,
  );
  if (live is! Vo2Committed || live.retry) {
    throw StateError('VO2 partial entry was not stored.');
  }
  partial.seedVo2Paper(corruptHead: true);
  await mountVo2(repository: partial, seed: false);
  expect(find.byKey(const ValueKey('vo2-entry-vo2-live')), findsOneWidget);
  expect(find.byKey(ValueKey('vo2-entry-$kSyntheticVo2PaperId')), findsNothing);
  expect(find.byKey(const ValueKey('vo2-unreadable-count')), findsOneWidget);
  expect(find.text('1 Eintrag nicht lesbar'), findsOneWidget);
  expect(find.text('99'), findsNothing);
  expect(find.text(paperValue), findsNWidgets(2));
  await h.capture('vo2-partial');

  final unreadable = await _loadVo2ReviewRepo(h);
  unreadable.seedVo2Paper(corruptHead: true);
  await mountVo2(repository: unreadable, seed: false);
  expect(heroText(), '\u2014');
  expect(find.text('Eintrag nicht lesbar'), findsOneWidget);
  expect(find.text(paperValue), findsNothing);
  expect(find.text('99'), findsNothing);
  expect(find.byKey(const ValueKey('vo2-add-empty')), findsOneWidget);
  await h.capture('vo2-unreadable');

  final saveFailure = await mountVo2();
  await openEditor();
  await tester.enterText(find.byKey(const ValueKey('vo2-value-input')), '42,7');
  saveFailure.failVo2Write = true;
  await saveEditor();
  expect(find.byKey(const ValueKey('vo2-editor')), findsOneWidget);
  expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
  expect(fieldText('vo2-value-input'), '42,7');
  expect(saveFailure.edits, 1);
  await h.capture('vo2-save-error');
  saveFailure.failVo2Write = false;
  await saveEditor();
  expect(find.byKey(const ValueKey('vo2-editor')), findsNothing);
  expect(saveFailure.edits, 2);
  expect(heroText(), obNumber(42.7, digits: 1));
  await h.capture('vo2-save-retry');

  final conflict = await mountVo2();
  await openEditor();
  await tester.enterText(find.byKey(const ValueKey('vo2-value-input')), '42,5');
  final raced = await conflict.editVo2Entry(
    id: kSyntheticVo2PaperId,
    expectedRevision: 1,
    measuredOn: measured,
    valueMlKgMin: 43,
    declaredMethod: kSyntheticVo2PaperMethod,
  );
  expect(raced, isA<Vo2Committed>());
  await saveEditor();
  expect(find.text('Eintrag wurde geändert'), findsOneWidget);
  expect(fieldText('vo2-value-input'), '42,5');
  expect(find.byKey(const ValueKey('vo2-editor')), findsOneWidget);
  await h.capture('vo2-conflict-retained');
  await saveEditor();
  expect(fieldText('vo2-value-input'), '43');
  expect(fieldText('vo2-method-input'), kSyntheticVo2PaperMethod);
  expect(find.text('Eintrag wurde geändert'), findsNothing);
  await h.capture('vo2-conflict-reload');
  await tester.tap(find.byTooltip('Schließen'));
  await tester.pumpAndSettle();
  expect(heroText(), obNumber(43, digits: 1));
  expect(find.text('42,5'), findsNothing);
  await h.capture('vo2-conflict-dismiss');

  final reload = await mountVo2();
  await openEditor();
  await tester.enterText(find.byKey(const ValueKey('vo2-value-input')), '44');
  final editsBefore = reload.edits;
  reload.failReadAfterCommit = true;
  await saveEditor();
  expect(
    find.text('Gespeichert. Einträge konnten nicht aktualisiert werden.'),
    findsOneWidget,
  );
  expect(find.text(obNumber(44, digits: 1)), findsNothing);
  expect(reload.edits, editsBefore + 1);
  await h.capture('vo2-saved-refresh-error');
  await tester.tap(find.byKey(const ValueKey('vo2-read-retry')));
  await tester.pumpAndSettle();
  expect(
    find.text('Gespeichert. Einträge konnten nicht aktualisiert werden.'),
    findsNothing,
  );
  expect(heroText(), obNumber(44, digits: 1));
  expect(reload.edits, editsBefore + 1);
  await h.capture('vo2-saved-refresh-retry');

  await mountVo2(scale: 2);
  expect(heroText(), paperValue);
  await h.capture('vo2-375-2x');
  await openEditor();
  final scaledSave = find.byKey(const ValueKey('vo2-save'));
  await tester.ensureVisible(scaledSave);
  expect(
    tester.getRect(scaledSave).bottom,
    lessThanOrEqualTo(
      tester.view.physicalSize.height / tester.view.devicePixelRatio,
    ),
  );
  await h.capture('vo2-375-editor');

  await mountVo2(brightness: Brightness.dark, scale: 2);
  expect(find.text(paperLine), findsOneWidget);
  await h.capture('vo2-375-2x-dark');
  await openEditor();
  final darkSave = find.byKey(const ValueKey('vo2-save'));
  await tester.ensureVisible(darkSave);
  expect(
    tester.getRect(darkSave).bottom,
    lessThanOrEqualTo(
      tester.view.physicalSize.height / tester.view.devicePixelRatio,
    ),
  );
  await h.capture('vo2-375-editor-dark');

  Future<OpenBandController> mountHealth(_Vo2ReviewRepo repository) async {
    final controller = OpenBandController(
      repository: repository,
      initialDay: day,
      now: () => now,
    );
    await controller.refresh();
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
          body: SafeArea(child: OpenBandHealth(controller: controller)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      healthRow,
      200,
      scrollable: h.verticalScrollable().last,
    );
    await tester.pumpAndSettle();
    return controller;
  }

  final unreadableHealth = await _loadVo2ReviewRepo(h);
  unreadableHealth.seedVo2Paper(corruptHead: true);
  final unreadableHealthController = await mountHealth(unreadableHealth);
  expect(
    find.descendant(of: healthRow, matching: find.text('Eintrag nicht lesbar')),
    findsOneWidget,
  );
  expect(
    find.descendant(of: healthRow, matching: find.text('\u2014')),
    findsOneWidget,
  );
  expect(
    find.descendant(of: healthRow, matching: find.text(healthWhen)),
    findsNothing,
  );
  expect(
    find.descendant(of: healthRow, matching: find.text(healthValue)),
    findsNothing,
  );
  expect(
    find.descendant(of: healthRow, matching: find.textContaining('99')),
    findsNothing,
  );
  expect(
    find.descendant(of: healthRow, matching: find.text('Laden fehlgeschlagen')),
    findsNothing,
  );
  await h.capture('vo2-health-unreadable');
  unreadableHealthController.dispose();

  final partialHealth = await _loadVo2ReviewRepo(h);
  final partialLive = await partialHealth.createVo2Entry(
    id: 'vo2-live',
    measuredOn: measured,
    valueMlKgMin: kSyntheticVo2PaperValue,
    declaredMethod: kSyntheticVo2PaperMethod,
  );
  if (partialLive is! Vo2Committed || partialLive.retry) {
    throw StateError('VO2 health partial entry was not stored.');
  }
  partialHealth.seedVo2Paper(corruptHead: true);
  final partialHealthController = await mountHealth(partialHealth);
  expect(
    find.descendant(of: healthRow, matching: find.text(healthValue)),
    findsOneWidget,
  );
  expect(
    find.descendant(of: healthRow, matching: find.textContaining(healthWhen)),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: healthRow,
      matching: find.textContaining('Teilweise lesbar'),
    ),
    findsOneWidget,
  );
  expect(
    find.descendant(of: healthRow, matching: find.text('Eintrag nicht lesbar')),
    findsNothing,
  );
  expect(
    find.descendant(of: healthRow, matching: find.textContaining('99')),
    findsNothing,
  );
  await h.capture('vo2-health-partial');
  partialHealthController.dispose();

  final lost = await mountVo2(seed: false);
  await tester.tap(find.byKey(const ValueKey('vo2-add-empty')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('vo2-value-input')), '41');
  await tester.enterText(
    find.byKey(const ValueKey('vo2-method-input')),
    kSyntheticVo2PaperMethod,
  );
  lost.loseNextCreateResponse = true;
  await saveEditor();
  expect(find.byKey(const ValueKey('vo2-editor')), findsOneWidget);
  expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
  expect(fieldText('vo2-value-input'), '41');
  expect(lost.lostCreateId, isNotNull);
  expect(lost.creates, 1);
  await tester.enterText(find.byKey(const ValueKey('vo2-value-input')), '42,5');
  await saveEditor();
  expect(find.text('Eintrag wurde geändert'), findsOneWidget);
  expect(find.text('Speichern fehlgeschlagen'), findsNothing);
  expect(fieldText('vo2-value-input'), '42,5');
  expect(fieldText('vo2-method-input'), kSyntheticVo2PaperMethod);
  expect(lost.creates, 2);
  await h.capture('vo2-create-conflict');
  await saveEditor();
  expect(find.byKey(const ValueKey('vo2-editor')), findsOneWidget);
  expect(find.text('Eintrag wurde geändert'), findsNothing);
  expect(find.text('Laden fehlgeschlagen'), findsNothing);
  expect(fieldText('vo2-value-input'), '41');
  expect(fieldText('vo2-method-input'), kSyntheticVo2PaperMethod);
  expect(lost.creates, 2);
  await h.capture('vo2-create-conflict-reloaded');
  await tester.tap(find.byTooltip('Schließen'));
  await tester.pumpAndSettle();
  final createdRows = find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith('vo2-entry-');
  });
  expect(createdRows, findsOneWidget);
  final createdId = (tester.widget(createdRows).key! as ValueKey<String>).value
      .substring('vo2-entry-'.length);
  expect(createdId, lost.lostCreateId);
  expect(heroText(), obNumber(41, digits: 1));
  expect(find.text('42,5'), findsNothing);
  final createdHead = await lost.readVo2Entry(createdId);
  expect(createdHead.head?.valueMlKgMin, 41);
  expect(createdHead.head?.declaredMethod, kSyntheticVo2PaperMethod);
  expect(createdHead.head?.deleted, isFalse);

  final removedConflict = await mountVo2();
  await openEditor();
  await tester.enterText(find.byKey(const ValueKey('vo2-value-input')), '42,5');
  final removedRemotely = await removedConflict.removeVo2Entry(
    id: kSyntheticVo2PaperId,
    expectedRevision: 1,
  );
  expect(removedRemotely, isA<Vo2Committed>());
  await saveEditor();
  expect(find.byKey(const ValueKey('vo2-editor')), findsOneWidget);
  expect(find.text('Eintrag wurde geändert'), findsOneWidget);
  expect(find.text('Laden fehlgeschlagen'), findsNothing);
  expect(fieldText('vo2-value-input'), '42,5');
  await saveEditor();
  expect(find.byKey(const ValueKey('vo2-editor')), findsNothing);
  expect(find.text('Laden fehlgeschlagen'), findsNothing);
  expect(find.text('Entfernt'), findsOneWidget);
  expect(
    find.byKey(ValueKey('vo2-removed-$kSyntheticVo2PaperId')),
    findsOneWidget,
  );
  expect(find.byKey(ValueKey('vo2-entry-$kSyntheticVo2PaperId')), findsNothing);
  expect(find.text('42,5'), findsNothing);
  expect(find.text(paperValue), findsOneWidget);
  await h.capture('vo2-removed-conflict');

  const receiptSource = 'OpenStrap backup';
  const partialReceipt = ImportOutcome(
    source: receiptSource,
    vo2TablePresent: true,
    vo2Revisions: 2,
    vo2ConflictIds: 1,
    vo2CorruptIds: 1,
  );
  const successReceipt = ImportOutcome(
    source: receiptSource,
    vo2TablePresent: true,
    vo2Revisions: 2,
  );
  const noopReceipt = ImportOutcome(
    source: receiptSource,
    vo2TablePresent: true,
  );
  const interruptedReceipt = ImportOutcome(
    source: receiptSource,
    vo2TablePresent: true,
    vo2Revisions: 1,
    readError: 'later table failed',
  );
  const interruptedEmptyReceipt = ImportOutcome(
    source: receiptSource,
    vo2TablePresent: true,
    readError: 'count failed',
  );

  void expectReceiptChrome({bool source = true}) {
    expect(find.byType(SafeArea), findsOneWidget);
    expect(find.bySemanticsLabel('Datenimport'), findsOneWidget);
    expect(find.byTooltip('Zurück'), findsOneWidget);
    expect(
      find.text('OpenBand-Sicherung'),
      source ? findsOneWidget : findsNothing,
    );
    expect(find.textContaining('OpenStrap'), findsNothing);
    expect(find.textContaining('0 Tag'), findsNothing);
    expect(find.textContaining('0 day'), findsNothing);
    expect(find.byIcon(LucideIcons.check), findsNothing);
  }

  void expectPartialReceipt() {
    expectReceiptChrome();
    expect(find.text('Teilweise importiert'), findsOneWidget);
    expect(find.text('2 VO₂max-Änderungen übernommen'), findsOneWidget);
    expect(find.text('Nicht übernommen'), findsOneWidget);
    expect(find.text('1 VO₂max-Konflikt'), findsOneWidget);
    expect(find.text('1 VO₂max-Eintrag nicht lesbar'), findsOneWidget);
    expect(find.text('Importiert'), findsNothing);
    expect(find.text('VO₂max unverändert'), findsNothing);
    expect(find.text('Nichts wurde importiert'), findsNothing);
    expect(find.text('Import unvollständig'), findsNothing);
  }

  Future<void> captureReceiptBottomIfCutOff(String name) async {
    final lower = find.text('1 VO₂max-Eintrag nicht lesbar');
    final viewport =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final hit = lower.hitTestable();
    final cutOff =
        hit.evaluate().isEmpty ||
        tester.getRect(hit).top < 0 ||
        tester.getRect(hit).bottom > viewport;
    if (!cutOff) return;
    final scroll = find.descendant(
      of: find.byKey(const ValueKey('import-receipt-scroll')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(lower, 160, scrollable: scroll);
    await tester.pump();
    expect(tester.getRect(lower).bottom, lessThanOrEqualTo(viewport));
    await h.capture(name);
  }

  await reviewMountImportReceipt(tester, partialReceipt);
  expectPartialReceipt();
  await h.capture('vo2-receipt-partial');
  await reviewMountImportReceipt(
    tester,
    partialReceipt,
    brightness: Brightness.dark,
  );
  expectPartialReceipt();
  await h.capture('vo2-receipt-partial-dark');
  await reviewMountImportReceipt(tester, partialReceipt, scale: 2);
  expectPartialReceipt();
  await h.capture('vo2-receipt-partial-375-2x');
  await captureReceiptBottomIfCutOff('vo2-receipt-partial-375-2x-bottom');
  await reviewMountImportReceipt(
    tester,
    partialReceipt,
    brightness: Brightness.dark,
    scale: 2,
  );
  expectPartialReceipt();
  await h.capture('vo2-receipt-partial-375-2x-dark');
  await captureReceiptBottomIfCutOff('vo2-receipt-partial-375-2x-dark-bottom');

  await reviewMountImportReceipt(tester, successReceipt);
  expectReceiptChrome();
  expect(find.text('Importiert'), findsOneWidget);
  expect(find.text('2 VO₂max-Änderungen übernommen'), findsOneWidget);
  expect(find.text('Nicht übernommen'), findsNothing);
  expect(find.text('Teilweise importiert'), findsNothing);
  expect(find.text('VO₂max unverändert'), findsNothing);
  await h.capture('vo2-receipt-success');

  await reviewMountImportReceipt(tester, noopReceipt);
  expectReceiptChrome();
  expect(find.text('VO₂max unverändert'), findsOneWidget);
  expect(find.text('Importiert'), findsNothing);
  expect(find.text('Teilweise importiert'), findsNothing);
  expect(find.text('Nichts wurde importiert'), findsNothing);
  expect(find.textContaining('Änderungen übernommen'), findsNothing);
  await h.capture('vo2-receipt-noop');

  await reviewMountImportReceipt(tester, interruptedReceipt);
  expectReceiptChrome();
  expect(find.text('Teilweise importiert'), findsOneWidget);
  expect(find.text('1 VO₂max-Änderung übernommen'), findsOneWidget);
  expect(find.text('Import unvollständig'), findsOneWidget);
  expect(find.textContaining('later table failed'), findsOneWidget);
  expect(find.text('Importiert'), findsNothing);
  expect(find.text('VO₂max unverändert'), findsNothing);
  expect(find.text('Nichts wurde importiert'), findsNothing);
  await h.capture('vo2-receipt-interrupted');

  await reviewMountImportReceipt(tester, interruptedEmptyReceipt);
  expectReceiptChrome(source: false);
  expect(find.text('Import unvollständig'), findsOneWidget);
  expect(find.textContaining('count failed'), findsOneWidget);
  expect(find.text('VO₂max unverändert'), findsNothing);
  expect(find.text('Nichts wurde importiert'), findsNothing);
  expect(find.text('Teilweise importiert'), findsNothing);
  expect(find.textContaining('übernommen'), findsNothing);
  await h.capture('vo2-receipt-interrupted-empty');
}
