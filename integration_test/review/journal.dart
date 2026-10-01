part of 'harness.dart';

Future<void> reviewJournal(ReviewHarness h) async {
  final tester = h.tester;
  Finder journalHub() => find.byKey(const PageStorageKey('openband.journal'));

  Finder inJournalHub(Finder matching) =>
      find.descendant(of: journalHub(), matching: matching);

  Finder journalHubScrollable() =>
      find.descendant(of: journalHub(), matching: find.byType(Scrollable));

  Future<void> expectHubText(String text) async {
    final target = inJournalHub(find.text(text));
    if (target.evaluate().isEmpty) await h.reveal(target);
    expect(target, findsOneWidget);
  }

  Future<void> tapJournalHubRetry() => h.tap(inJournalHub(find.text('Erneut')));

  bool isFullyVisibleInJournalHub(Finder matching) {
    final target = inJournalHub(matching);
    if (target.evaluate().length != 1) return false;
    if (target.hitTestable().evaluate().isEmpty) return false;
    final box = tester.getRect(target);
    final view = tester.getRect(journalHub());
    const slop = 0.5;
    return box.top >= view.top - slop &&
        box.bottom <= view.bottom + slop &&
        box.left >= view.left - slop &&
        box.right <= view.right + slop;
  }

  Future<void> revealJournalHubPatternCard(Finder lastLine) async {
    final heading = find.text('Einschlafen · Koffein nach 14 Uhr');
    final end = inJournalHub(lastLine);
    if (end.evaluate().isEmpty) await h.reveal(end);
    var drags = 0;
    while (drags < 50 &&
        !(isFullyVisibleInJournalHub(heading) &&
            isFullyVisibleInJournalHub(lastLine))) {
      final view = tester.getRect(journalHub());
      if (end.evaluate().isEmpty) {
        await tester.drag(journalHubScrollable(), const Offset(0, -200));
      } else {
        final endBox = tester.getRect(end);
        final headingBox = inJournalHub(heading).evaluate().isEmpty
            ? null
            : tester.getRect(inJournalHub(heading));
        final Offset delta;
        if (endBox.bottom > view.bottom + 0.5) {
          delta = const Offset(0, -80);
        } else if (headingBox != null && headingBox.top < view.top - 0.5) {
          delta = const Offset(0, 80);
        } else if (endBox.top < view.top - 0.5) {
          delta = const Offset(0, 80);
        } else if (!isFullyVisibleInJournalHub(lastLine)) {
          delta = const Offset(0, -80);
        } else if (!isFullyVisibleInJournalHub(heading)) {
          delta = const Offset(0, 80);
        } else {
          break;
        }
        await tester.drag(journalHubScrollable(), delta);
      }
      await tester.pumpAndSettle();
      drags++;
    }
    expect(isFullyVisibleInJournalHub(heading), isTrue);
    expect(isFullyVisibleInJournalHub(lastLine), isTrue);
  }

  Future<void> revealJournalHubPattern() async {
    await revealJournalHubPatternCard(find.text('Nein · 11 Nächte'));
  }

  Future<void> revealJournalHubHeader() async {
    final edit = inJournalHub(find.byKey(const ValueKey('journal-edit')));
    if (edit.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        edit,
        -200,
        scrollable: journalHubScrollable(),
      );
    }
    await Scrollable.ensureVisible(tester.element(edit), alignment: 0);
    await tester.pumpAndSettle();
  }

  Future<void> openJournalHubInfo() =>
      h.tap(inJournalHub(find.byTooltip('Information')));

  Future<SyntheticOpenBandRepository> openJournalHub({
    Brightness brightness = Brightness.light,
    double? scale,
    SyntheticCaffeineSleepSeed patternSeed =
        SyntheticCaffeineSleepSeed.paperMeaningful,
    bool failPattern = false,
    bool failJournalRead = false,
    bool failMeals = false,
    bool failTargets = false,
    bool filledAnswers = false,
  }) async {
    final repository = await h.mount(brightness: brightness, scale: scale);
    repository.seedCaffeineSleepPattern('2026-09-15', seed: patternSeed);
    if (filledAnswers) {
      await repository.writeJournal('2026-09-15', 'mood', 4);
      await repository.writeJournal('2026-09-15', 'caffeine_late', 1);
      await repository.writeJournal('2026-09-15', 'alcohol_evening', 0);
      await repository.writeJournal('2026-09-15', 'read_before_bed', 1);
    }
    repository.failCaffeineSleepPattern = failPattern;
    repository.failJournalRead = failJournalRead;
    repository.failMealsRead = failMeals;
    repository.failNutritionTargetRead = failTargets;
    await h.press('Journal');
    await h.settleJournalHub(repository);
    return repository;
  }

  Future<void> reviewJournalHubInfo2x({
    Brightness brightness = Brightness.light,
    String suffix = '',
  }) async {
    await openJournalHub(brightness: brightness, scale: 2);
    await openJournalHubInfo();
    final title = find.text('Vergleich verstehen');
    final close = find.byTooltip('Schließen');
    final footer = find.text('Schließen');
    expect(title, findsOneWidget);
    expect(title.hitTestable(), findsOneWidget);
    expect(close.hitTestable(), findsOneWidget);
    expect(footer.hitTestable(), findsOneWidget);
    await h.capture('journal-hub-info-2x$suffix');
    final titleRect = tester.getRect(title);
    final closeRect = tester.getRect(close);
    final causality = find.textContaining('belegt keine Ursache');
    final footerButton = find.widgetWithText(FilledButton, 'Schließen');
    bool causalityFullyInBody() {
      if (causality.evaluate().length != 1) return false;
      if (footerButton.evaluate().length != 1) return false;
      final box = tester.getRect(causality);
      final footerBox = tester.getRect(footerButton);
      final headerBottom =
          tester.getRect(title).bottom > tester.getRect(close).bottom
          ? tester.getRect(title).bottom
          : tester.getRect(close).bottom;
      const slop = 0.5;
      return box.top >= headerBottom - slop &&
          box.bottom <= footerBox.top + slop;
    }

    if (causality.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        causality,
        80,
        scrollable: h.verticalScrollable().last,
      );
    }
    var drags = 0;
    while (!causalityFullyInBody() && drags < 50) {
      await tester.drag(h.verticalScrollable().last, const Offset(0, -80));
      await tester.pumpAndSettle();
      drags++;
    }
    expect(causalityFullyInBody(), isTrue);
    expect(causality.hitTestable(), findsOneWidget);
    expect(title.hitTestable(), findsOneWidget);
    expect(tester.getRect(title), titleRect);
    expect(close.hitTestable(), findsOneWidget);
    expect(tester.getRect(close), closeRect);
    expect(footer.hitTestable(), findsOneWidget);
    expect(footerButton.hitTestable(), findsOneWidget);
    await h.capture('journal-hub-info-2x-scrolled$suffix');
    await tester.tap(find.text('Schließen').last);
    await tester.pumpAndSettle();
  }

  Future<void> expectMeaningfulPattern() async {
    for (final text in ['+12 Min.', 'Ja · 7 Nächte', 'Nein · 11 Nächte']) {
      final target = inJournalHub(find.text(text));
      if (target.evaluate().isEmpty) await h.reveal(target);
      expect(target, findsOneWidget);
    }
    expect(inJournalHub(find.textContaining('≥')), findsNothing);
    expect(inJournalHub(find.textContaining('mind.')), findsNothing);
  }

  Future<void> expectMeaningfulPatternVisible() async {
    await expectMeaningfulPattern();
    expect(
      isFullyVisibleInJournalHub(
        find.text('Einschlafen · Koffein nach 14 Uhr'),
      ),
      isTrue,
    );
    expect(isFullyVisibleInJournalHub(find.text('+12 Min.')), isTrue);
    expect(isFullyVisibleInJournalHub(find.text('Ja · 7 Nächte')), isTrue);
    expect(isFullyVisibleInJournalHub(find.text('Nein · 11 Nächte')), isTrue);
  }

  bool hubSelected(String label) =>
      tester
          .getSemantics(find.bySemanticsLabel(label))
          .flagsCollection
          .isSelected
          .toBoolOrNull() ==
      true;

  final hub = await openJournalHub();
  await h.reveal(inJournalHub(find.text('Einschlafen · Koffein nach 14 Uhr')));
  await expectHubText('Einschlafen · Koffein nach 14 Uhr');
  await expectMeaningfulPattern();
  await h.reveal(inJournalHub(find.text('620')));
  await expectHubText('620');
  await revealJournalHubHeader();
  expect(hubSelected('Stimmung Gut'), isFalse);
  expect(hubSelected('Koffein nach 14 Uhr: Nein'), isFalse);
  expect(hubSelected('Alkohol: Nein'), isFalse);
  expect(hubSelected('Abends gelesen: Nein'), isFalse);
  await h.capture('journal-hub');
  await revealJournalHubPattern();
  await expectMeaningfulPatternVisible();
  await h.capture('journal-hub-scrolled');
  await openJournalHubInfo();
  expect(find.text('Vergleich verstehen'), findsOneWidget);
  expect(find.textContaining('belegt keine Ursache'), findsOneWidget);
  expect(
    find.textContaining('17. August–15. September · 18 Nächte'),
    findsOneWidget,
  );
  await h.capture('journal-hub-info');
  await tester.tap(find.text('Schließen').last);
  await tester.pumpAndSettle();
  await revealJournalHubHeader();
  await tester.tap(find.bySemanticsLabel('Stimmung Gut'));
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsLabel('Koffein nach 14 Uhr: Ja'));
  await h.settleJournalHub(hub);
  await tester.tap(find.bySemanticsLabel('Alkohol: Nein'));
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsLabel('Abends gelesen: Ja'));
  await tester.pumpAndSettle();
  expect(hubSelected('Stimmung Gut'), isTrue);
  expect(hubSelected('Koffein nach 14 Uhr: Ja'), isTrue);
  expect(hubSelected('Alkohol: Nein'), isTrue);
  expect(hubSelected('Abends gelesen: Ja'), isTrue);
  await expectMeaningfulPattern();
  await h.capture('journal-answered');
  if (h.flow != 'journal-hub') {
    await h.openHubEditor();
    await h.capture('journal-editor');
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    await h.capture('journal-info');
    await tester.tap(find.text('Schließen').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Eigene Felder'));
    await tester.tap(find.text('Eigene Felder'));
    await tester.pumpAndSettle();
    await h.capture('journal-fields');
    await tester.tap(find.text('Feld hinzufügen'));
    await tester.pumpAndSettle();
    await h.capture('journal-field-create');
    await h.pop();
    await h.pop();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    await openJournalHub(failJournalRead: true);
    await h.openHubEditor();
    expect(find.text('Journal nicht geladen'), findsOneWidget);
    await h.capture('journal-editor-load-error');

    await openJournalHub(brightness: Brightness.dark);
    await h.openHubEditor();
    await h.capture('journal-editor-dark');
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    await h.capture('journal-info-dark');
    await tester.tap(find.text('Schließen').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Eigene Felder'));
    await tester.tap(find.text('Eigene Felder'));
    await tester.pumpAndSettle();
    await h.capture('journal-fields-dark');

    await openJournalHub(scale: 2);
    await h.openHubEditor();
    expect(find.text('Ausgeblendet'), findsNothing);
    await h.capture('journal-editor-large');
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    await h.capture('journal-info-large');
    await tester.tap(find.text('Schließen').last);
    await tester.pumpAndSettle();

    Future<SyntheticOpenBandRepository> openJournalEditor({
      bool filled = false,
      bool withCustom = false,
      Brightness brightness = Brightness.light,
      double? scale,
    }) async {
      final repository = await h.mount(brightness: brightness, scale: scale);
      if (filled || withCustom) {
        repository.seedJournalEditor(filled: filled, withCustom: withCustom);
      }
      await h.press('Journal');
      await h.settleJournalHub(repository);
      await h.openHubEditor();
      return repository;
    }

    await openJournalEditor();
    await h.capture('journal-editor-empty');

    final filledJournal = await openJournalEditor(
      filled: true,
      withCustom: true,
    );
    await tester.tap(find.text('Schlafqualität'));
    await tester.pumpAndSettle();
    await h.capture('journal-editor-rating');
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Koffein').last);
    await tester.tap(find.text('Koffein').last);
    await tester.pumpAndSettle();
    await h.capture('journal-editor-value');
    await tester.enterText(find.byKey(const ValueKey('journal-value')), '180');
    await tester.tap(find.text('10:30'));
    await tester.pumpAndSettle();
    await h.capture('journal-editor-time');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Tags'));
    await tester.tap(find.text('Tags'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('journal-tags-sheet')),
        matching: find.text('Koffein'),
      ),
    );
    await tester.pump();
    await h.capture('journal-editor-tags');
    await tester.tap(find.byKey(const ValueKey('journal-tag-custom')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('journal-tag-custom')),
    );
    await h.capture('journal-editor-tags-keyboard');
    await tester.enterText(
      find.byKey(const ValueKey('journal-tag-custom')),
      'Yoga',
    );
    await tester.ensureVisible(find.byTooltip('Tag hinzufügen'));
    await tester.tap(find.byTooltip('Tag hinzufügen'));
    await tester.pump();
    await h.capture('journal-editor-tags-custom');
    expect(
      find
          .descendant(
            of: find.byKey(const ValueKey('journal-tags-sheet')),
            matching: find.text('Tags'),
          )
          .hitTestable(),
      findsOneWidget,
    );
    expect(
      find
          .descendant(
            of: find.byKey(const ValueKey('journal-tags-sheet')),
            matching: find.byTooltip('Schließen'),
          )
          .hitTestable(),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Übernehmen').hitTestable(),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Übernehmen'));
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.bySemanticsLabel('Stimmung Sehr gut'));
    await tester.tap(find.bySemanticsLabel('Stimmung Sehr gut'));
    await tester.pump();
    await tester.ensureVisible(find.text('Eigene Felder'));
    await tester.tap(find.text('Eigene Felder'));
    await tester.pumpAndSettle();
    await h.capture('journal-fields-from-draft');
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    await h.capture('journal-editor-after-fields');
    filledJournal.failJournalPatch = true;
    await tester.tap(find.byKey(const ValueKey('journal-save')));
    await tester.pumpAndSettle();
    await h.capture('journal-editor-save-error');
    filledJournal.failJournalPatch = false;
    await tester.tap(find.byKey(const ValueKey('journal-save')));
    await tester.pumpAndSettle();
    await h.openHubEditor();
    await h.capture('journal-editor-reopened');
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();

    final conflictJournal = await openJournalEditor(filled: true);
    await tester.tap(find.bySemanticsLabel('Stimmung Sehr gut'));
    await tester.pump();
    final conflictBase = await conflictJournal.readJournalDay('2026-09-15');
    await conflictJournal.patchJournalDay(
      JournalDayPatch.fromBase(
        conflictBase,
        metrics: const {'mood': JournalMetricValue(2)},
      ),
    );
    await tester.tap(find.byKey(const ValueKey('journal-save')));
    await tester.pumpAndSettle();
    await h.capture('journal-editor-conflict');
    await tester.tap(find.text('Neu laden'));
    await tester.pumpAndSettle();
    await h.capture('journal-discard');
    await tester.tap(find.text('Verwerfen und neu laden'));
    await tester.pumpAndSettle();
    await h.capture('journal-editor-reloaded');
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();

    await openJournalEditor(withCustom: true);
    await tester.ensureVisible(find.text('Eigene Felder'));
    await tester.tap(find.text('Eigene Felder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Feld hinzufügen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Menge'));
    await tester.pumpAndSettle();
    await h.capture('journal-field-type');
    await tester.tap(find.text('Dauer'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('journal-field-name')),
      'Dehnung',
    );
    await tester.tap(find.text('Speichern').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Magnesium').first);
    await tester.pumpAndSettle();
    await h.capture('journal-field-detail');
    await tester.tap(find.text('Ausblenden'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ausgeblendet'));
    await tester.pumpAndSettle();
    await h.capture('journal-fields-hidden');
    await tester.tap(find.text('Magnesium'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Einblenden'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();

    final fieldsFail = await openJournalEditor();
    fieldsFail.failJournalFieldsList = true;
    await tester.ensureVisible(find.text('Eigene Felder'));
    await tester.tap(find.text('Eigene Felder'));
    await tester.pumpAndSettle();
    await h.capture('journal-fields-load-error');
    fieldsFail.failJournalFieldsList = false;
    await tester.tap(find.text('Erneut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Feld hinzufügen'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('journal-field-name')),
      'Omega',
    );
    fieldsFail.failJournalFieldsList = true;
    await tester.tap(find.text('Speichern').first);
    await tester.pumpAndSettle();
    await h.capture('journal-field-create-retry');
    fieldsFail.failJournalFieldsList = false;
    await tester.tap(find.text('Erneut'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();

    await openJournalEditor(filled: true, scale: 2);
    await tester.ensureVisible(find.byKey(const ValueKey('journal-note')));
    await tester.tap(find.byKey(const ValueKey('journal-note')));
    await tester.pumpAndSettle();
    await h.capture('journal-editor-keyboard');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Tags'));
    await tester.pumpAndSettle();
    await h.capture('journal-editor-scrolled');
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    if (find.text('Änderungen verwerfen?').evaluate().isNotEmpty) {
      await tester.tap(find.text('Weiter bearbeiten'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Zurück'));
      await tester.pumpAndSettle();
      if (find.text('Änderungen verwerfen?').evaluate().isNotEmpty) {
        await tester.tap(find.text('Verwerfen'));
        await tester.pumpAndSettle();
      }
    }

    await openJournalEditor(
      filled: true,
      scale: 2,
      brightness: Brightness.dark,
    );
    await tester.ensureVisible(find.text('Tags'));
    await tester.pumpAndSettle();
    await h.capture('journal-editor-scrolled-dark');
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
  }

  await openJournalHub(brightness: Brightness.dark);
  await expectMeaningfulPattern();
  await h.reveal(inJournalHub(find.text('620')));
  await expectHubText('620');
  await revealJournalHubHeader();
  expect(hubSelected('Alkohol: Nein'), isFalse);
  await h.capture('journal-hub-dark');
  await revealJournalHubPattern();
  await expectMeaningfulPatternVisible();
  await h.capture('journal-hub-scrolled-dark');

  await openJournalHub(scale: 2);
  await expectHubText('Journal');
  await h.reveal(inJournalHub(find.text('620')));
  await expectHubText('620');
  await revealJournalHubHeader();
  await h.capture('journal-hub-2x');
  await revealJournalHubPattern();
  await expectMeaningfulPatternVisible();
  await h.capture('journal-hub-2x-scrolled');

  await openJournalHub(brightness: Brightness.dark, scale: 2);
  await expectHubText('Journal');
  await h.reveal(inJournalHub(find.text('620')));
  await expectHubText('620');
  await revealJournalHubHeader();
  await h.capture('journal-hub-2x-dark');
  await revealJournalHubPattern();
  await expectMeaningfulPatternVisible();
  await h.capture('journal-hub-2x-scrolled-dark');

  await reviewJournalHubInfo2x();
  await reviewJournalHubInfo2x(brightness: Brightness.dark, suffix: '-dark');

  await openJournalHub(patternSeed: SyntheticCaffeineSleepSeed.insufficient);
  await revealJournalHubPatternCard(find.text('5 Nächte mit Eintrag'));
  await expectHubText('Noch zu wenige Nächte');
  await expectHubText('5 Nächte mit Eintrag');
  expect(inJournalHub(find.text('+12 Min.')), findsNothing);
  expect(inJournalHub(find.textContaining('≥')), findsNothing);
  expect(
    isFullyVisibleInJournalHub(find.text('Noch zu wenige Nächte')),
    isTrue,
  );
  expect(isFullyVisibleInJournalHub(find.text('5 Nächte mit Eintrag')), isTrue);
  await h.capture('journal-hub-insufficient');

  await openJournalHub(
    brightness: Brightness.dark,
    patternSeed: SyntheticCaffeineSleepSeed.insufficient,
  );
  await revealJournalHubPatternCard(find.text('5 Nächte mit Eintrag'));
  await expectHubText('Noch zu wenige Nächte');
  await expectHubText('5 Nächte mit Eintrag');
  expect(inJournalHub(find.text('+12 Min.')), findsNothing);
  expect(inJournalHub(find.textContaining('≥')), findsNothing);
  expect(
    isFullyVisibleInJournalHub(find.text('Noch zu wenige Nächte')),
    isTrue,
  );
  expect(isFullyVisibleInJournalHub(find.text('5 Nächte mit Eintrag')), isTrue);
  await h.capture('journal-hub-insufficient-dark');

  await openJournalHub(patternSeed: SyntheticCaffeineSleepSeed.unavailable);
  await revealJournalHubPatternCard(
    find.text('Keine auswertbaren Nächte mit Eintrag'),
  );
  await expectHubText('Noch kein Vergleich');
  await expectHubText('Keine auswertbaren Nächte mit Eintrag');
  expect(inJournalHub(find.text('Nein · 11 Nächte')), findsNothing);
  expect(isFullyVisibleInJournalHub(find.text('Noch kein Vergleich')), isTrue);
  expect(
    isFullyVisibleInJournalHub(
      find.text('Keine auswertbaren Nächte mit Eintrag'),
    ),
    isTrue,
  );
  await h.capture('journal-hub-unavailable');

  await openJournalHub(
    brightness: Brightness.dark,
    patternSeed: SyntheticCaffeineSleepSeed.unavailable,
  );
  await revealJournalHubPatternCard(
    find.text('Keine auswertbaren Nächte mit Eintrag'),
  );
  await expectHubText('Noch kein Vergleich');
  await expectHubText('Keine auswertbaren Nächte mit Eintrag');
  expect(inJournalHub(find.text('Nein · 11 Nächte')), findsNothing);
  expect(isFullyVisibleInJournalHub(find.text('Noch kein Vergleich')), isTrue);
  expect(
    isFullyVisibleInJournalHub(
      find.text('Keine auswertbaren Nächte mit Eintrag'),
    ),
    isTrue,
  );
  await h.capture('journal-hub-unavailable-dark');

  await openJournalHub(patternSeed: SyntheticCaffeineSleepSeed.nonmeaningful);
  await revealJournalHubPatternCard(find.text('18 Nächte mit Eintrag'));
  await expectHubText('Kein klares Muster');
  await expectHubText('18 Nächte mit Eintrag');
  expect(inJournalHub(find.text('+12 Min.')), findsNothing);
  expect(isFullyVisibleInJournalHub(find.text('Kein klares Muster')), isTrue);
  expect(
    isFullyVisibleInJournalHub(find.text('18 Nächte mit Eintrag')),
    isTrue,
  );
  await h.capture('journal-hub-nonmeaningful');

  await openJournalHub(
    brightness: Brightness.dark,
    patternSeed: SyntheticCaffeineSleepSeed.nonmeaningful,
  );
  await revealJournalHubPatternCard(find.text('18 Nächte mit Eintrag'));
  await expectHubText('Kein klares Muster');
  await expectHubText('18 Nächte mit Eintrag');
  expect(inJournalHub(find.text('+12 Min.')), findsNothing);
  expect(isFullyVisibleInJournalHub(find.text('Kein klares Muster')), isTrue);
  expect(
    isFullyVisibleInJournalHub(find.text('18 Nächte mit Eintrag')),
    isTrue,
  );
  await h.capture('journal-hub-nonmeaningful-dark');

  await openJournalHub(
    patternSeed: SyntheticCaffeineSleepSeed.partialMeaningful,
  );
  await expectMeaningfulPattern();
  await expectHubText('Teilweise auswertbar');
  await revealJournalHubPatternCard(find.text('Teilweise auswertbar'));
  await expectMeaningfulPatternVisible();
  expect(isFullyVisibleInJournalHub(find.text('Teilweise auswertbar')), isTrue);
  await h.capture('journal-hub-partial');

  await openJournalHub(
    brightness: Brightness.dark,
    patternSeed: SyntheticCaffeineSleepSeed.partialMeaningful,
  );
  await expectMeaningfulPattern();
  await expectHubText('Teilweise auswertbar');
  await revealJournalHubPatternCard(find.text('Teilweise auswertbar'));
  await expectMeaningfulPatternVisible();
  expect(isFullyVisibleInJournalHub(find.text('Teilweise auswertbar')), isTrue);
  await h.capture('journal-hub-partial-dark');

  final patternFail = await openJournalHub(failPattern: true);
  await expectHubText('Vergleich konnte nicht geladen werden.');
  await expectHubText('Erneut');
  await revealJournalHubPatternCard(find.text('Erneut'));
  expect(
    isFullyVisibleInJournalHub(
      find.text('Vergleich konnte nicht geladen werden.'),
    ),
    isTrue,
  );
  expect(isFullyVisibleInJournalHub(find.text('Erneut')), isTrue);
  await h.capture('journal-hub-pattern-error');
  patternFail.failCaffeineSleepPattern = false;
  await tapJournalHubRetry();
  await tester.pump();
  await h.settleJournalHub(patternFail);
  await revealJournalHubPattern();
  await expectMeaningfulPatternVisible();
  await h.capture('journal-hub-pattern-retry');

  final patternFailDark = await openJournalHub(
    brightness: Brightness.dark,
    failPattern: true,
  );
  await expectHubText('Vergleich konnte nicht geladen werden.');
  await expectHubText('Erneut');
  await revealJournalHubPatternCard(find.text('Erneut'));
  expect(
    isFullyVisibleInJournalHub(
      find.text('Vergleich konnte nicht geladen werden.'),
    ),
    isTrue,
  );
  expect(isFullyVisibleInJournalHub(find.text('Erneut')), isTrue);
  await h.capture('journal-hub-pattern-error-dark');
  patternFailDark.failCaffeineSleepPattern = false;
  await tapJournalHubRetry();
  await tester.pump();
  await h.settleJournalHub(patternFailDark);
  await revealJournalHubPattern();
  await expectMeaningfulPatternVisible();
  await h.capture('journal-hub-pattern-retry-dark');

  final writeFail = await openJournalHub(filledAnswers: true);
  expect(hubSelected('Stimmung Gut'), isTrue);
  expect(hubSelected('Alkohol: Nein'), isTrue);
  writeFail.failJournalPatch = true;
  await tester.tap(find.bySemanticsLabel('Alkohol: Ja'));
  await tester.pumpAndSettle();
  await expectHubText('Speichern fehlgeschlagen.');
  expect(hubSelected('Alkohol: Nein'), isTrue);
  expect(hubSelected('Alkohol: Ja'), isFalse);
  await h.capture('journal-hub-write-error');
  writeFail.failJournalPatch = false;
  await tester.tap(find.bySemanticsLabel('Alkohol: Ja'));
  await tester.pumpAndSettle();
  expect(inJournalHub(find.text('Speichern fehlgeschlagen.')), findsNothing);
  expect(hubSelected('Alkohol: Ja'), isTrue);
  await h.capture('journal-hub-write-retry');

  final writeFailDark = await openJournalHub(
    brightness: Brightness.dark,
    filledAnswers: true,
  );
  expect(hubSelected('Stimmung Gut'), isTrue);
  expect(hubSelected('Alkohol: Nein'), isTrue);
  writeFailDark.failJournalPatch = true;
  await tester.tap(find.bySemanticsLabel('Alkohol: Ja'));
  await tester.pumpAndSettle();
  await expectHubText('Speichern fehlgeschlagen.');
  expect(hubSelected('Alkohol: Nein'), isTrue);
  expect(hubSelected('Alkohol: Ja'), isFalse);
  await h.capture('journal-hub-write-error-dark');
  writeFailDark.failJournalPatch = false;
  await tester.tap(find.bySemanticsLabel('Alkohol: Ja'));
  await tester.pumpAndSettle();
  expect(inJournalHub(find.text('Speichern fehlgeschlagen.')), findsNothing);
  expect(hubSelected('Alkohol: Ja'), isTrue);
  await h.capture('journal-hub-write-retry-dark');

  final conflictHub = await openJournalHub(filledAnswers: true);
  await conflictHub.writeJournal('2026-09-15', 'mood', 2);
  await tester.tap(find.bySemanticsLabel('Stimmung Okay'));
  await tester.pumpAndSettle();
  await expectHubText('Antwort inzwischen geändert.');
  await expectHubText('Neu laden');
  expect(hubSelected('Stimmung Gut'), isTrue);
  await h.capture('journal-hub-conflict');
  await tester.tap(inJournalHub(find.text('Neu laden')));
  await h.settleJournalHub(conflictHub);
  expect(inJournalHub(find.text('Antwort inzwischen geändert.')), findsNothing);
  expect(hubSelected('Stimmung Müde'), isTrue);
  await h.capture('journal-hub-conflict-reloaded');

  final conflictHubDark = await openJournalHub(
    brightness: Brightness.dark,
    filledAnswers: true,
  );
  await conflictHubDark.writeJournal('2026-09-15', 'mood', 2);
  await tester.tap(find.bySemanticsLabel('Stimmung Okay'));
  await tester.pumpAndSettle();
  await expectHubText('Antwort inzwischen geändert.');
  await expectHubText('Neu laden');
  expect(hubSelected('Stimmung Gut'), isTrue);
  await h.capture('journal-hub-conflict-dark');
  await tester.tap(inJournalHub(find.text('Neu laden')));
  await h.settleJournalHub(conflictHubDark);
  expect(inJournalHub(find.text('Antwort inzwischen geändert.')), findsNothing);
  expect(hubSelected('Stimmung Müde'), isTrue);
  await h.capture('journal-hub-conflict-reloaded-dark');

  final readFail = await openJournalHub(filledAnswers: true);
  readFail.failJournalRead = true;
  await tester.tap(find.bySemanticsLabel('Stimmung Okay'));
  await tester.pumpAndSettle();
  expect(inJournalHub(find.text('Speichern fehlgeschlagen.')), findsNothing);
  await expectHubText('Journal nicht geladen.');
  expect(hubSelected('Stimmung Okay'), isTrue);
  final disabledMood = find.bySemanticsLabel('Stimmung Gut');
  expect(disabledMood.hitTestable(), findsNothing);
  expect(
    find.ancestor(
      of: disabledMood,
      matching: find.byWidgetPredicate(
        (widget) => widget is IgnorePointer && widget.ignoring,
      ),
    ),
    findsOneWidget,
  );
  readFail.failJournalRead = false;
  final storedBefore = await readFail.readJournalDay('2026-09-15');
  readFail.failJournalRead = true;
  await tester.tapAt(tester.getCenter(disabledMood));
  await tester.pumpAndSettle();
  expect(hubSelected('Stimmung Okay'), isTrue);
  readFail.failJournalRead = false;
  final storedAfter = await readFail.readJournalDay('2026-09-15');
  readFail.failJournalRead = true;
  expect(
    storedAfter.metrics['mood']?.value,
    storedBefore.metrics['mood']?.value,
  );
  expect(
    storedAfter.metricUpdatedAt['mood'],
    storedBefore.metricUpdatedAt['mood'],
  );
  await h.capture('journal-hub-read-error');
  readFail.failJournalRead = false;
  await tapJournalHubRetry();
  await h.settleJournalHub(readFail);
  expect(inJournalHub(find.text('Journal nicht geladen.')), findsNothing);
  expect(hubSelected('Stimmung Okay'), isTrue);
  await h.capture('journal-hub-read-retry');

  final readFailDark = await openJournalHub(
    brightness: Brightness.dark,
    filledAnswers: true,
  );
  readFailDark.failJournalRead = true;
  await tester.tap(find.bySemanticsLabel('Stimmung Okay'));
  await tester.pumpAndSettle();
  await expectHubText('Journal nicht geladen.');
  expect(hubSelected('Stimmung Okay'), isTrue);
  await h.capture('journal-hub-read-error-dark');
  readFailDark.failJournalRead = false;
  await tapJournalHubRetry();
  await h.settleJournalHub(readFailDark);
  expect(inJournalHub(find.text('Journal nicht geladen.')), findsNothing);
  expect(hubSelected('Stimmung Okay'), isTrue);
  await h.capture('journal-hub-read-retry-dark');

  final mealsFail = await openJournalHub(failMeals: true);
  await expectHubText('Einträge konnten nicht geladen werden.');
  await expectHubText('Erneut');
  expect(inJournalHub(find.text('620')), findsNothing);
  expect(inJournalHub(find.text('kcal')), findsNothing);
  expect(inJournalHub(find.text('Ziel 2.000')), findsNothing);
  expect(inJournalHub(find.text('Kein Ziel')), findsNothing);
  await h.capture('journal-hub-meals-error');
  mealsFail.failMealsRead = false;
  await tapJournalHubRetry();
  await tester.pump();
  await h.settleJournalHub(mealsFail);
  expect(
    inJournalHub(find.text('Einträge konnten nicht geladen werden.')),
    findsNothing,
  );
  await h.reveal(inJournalHub(find.text('620')));
  await expectHubText('620');
  await revealJournalHubHeader();
  await expectHubText('Ziel 2.000');
  await h.capture('journal-hub-meals-retry');

  final mealsFailDark = await openJournalHub(
    brightness: Brightness.dark,
    failMeals: true,
  );
  await expectHubText('Einträge konnten nicht geladen werden.');
  await expectHubText('Erneut');
  expect(inJournalHub(find.text('620')), findsNothing);
  expect(inJournalHub(find.text('kcal')), findsNothing);
  expect(inJournalHub(find.text('Ziel 2.000')), findsNothing);
  expect(inJournalHub(find.text('Kein Ziel')), findsNothing);
  await h.capture('journal-hub-meals-error-dark');
  mealsFailDark.failMealsRead = false;
  await tapJournalHubRetry();
  await tester.pump();
  await h.settleJournalHub(mealsFailDark);
  expect(
    inJournalHub(find.text('Einträge konnten nicht geladen werden.')),
    findsNothing,
  );
  await h.reveal(inJournalHub(find.text('620')));
  await expectHubText('620');
  await revealJournalHubHeader();
  await expectHubText('Ziel 2.000');
  await h.capture('journal-hub-meals-retry-dark');

  final targetsFail = await openJournalHub(failTargets: true);
  await expectHubText('Ziele konnten nicht geladen werden.');
  await expectHubText('Erneut');
  await h.reveal(inJournalHub(find.text('620')));
  await expectHubText('620');
  await revealJournalHubHeader();
  await expectHubText('Ziel —');
  expect(inJournalHub(find.text('Kein Ziel')), findsNothing);
  expect(inJournalHub(find.text('Ziel 2.000')), findsNothing);
  await h.capture('journal-hub-targets-error');
  targetsFail.failNutritionTargetRead = false;
  await tapJournalHubRetry();
  await tester.pump();
  await h.settleJournalHub(targetsFail);
  expect(
    inJournalHub(find.text('Ziele konnten nicht geladen werden.')),
    findsNothing,
  );
  await h.reveal(inJournalHub(find.text('620')));
  await expectHubText('620');
  await revealJournalHubHeader();
  await expectHubText('Ziel 2.000');
  expect(inJournalHub(find.text('Ziel —')), findsNothing);
  expect(inJournalHub(find.text('Kein Ziel')), findsNothing);
  await h.capture('journal-hub-targets-retry');

  final targetsFailDark = await openJournalHub(
    brightness: Brightness.dark,
    failTargets: true,
  );
  await expectHubText('Ziele konnten nicht geladen werden.');
  await expectHubText('Erneut');
  await h.reveal(inJournalHub(find.text('620')));
  await expectHubText('620');
  await revealJournalHubHeader();
  await expectHubText('Ziel —');
  expect(inJournalHub(find.text('Kein Ziel')), findsNothing);
  expect(inJournalHub(find.text('Ziel 2.000')), findsNothing);
  await h.capture('journal-hub-targets-error-dark');
  targetsFailDark.failNutritionTargetRead = false;
  await tapJournalHubRetry();
  await tester.pump();
  await h.settleJournalHub(targetsFailDark);
  expect(
    inJournalHub(find.text('Ziele konnten nicht geladen werden.')),
    findsNothing,
  );
  await h.reveal(inJournalHub(find.text('620')));
  await expectHubText('620');
  await revealJournalHubHeader();
  await expectHubText('Ziel 2.000');
  expect(inJournalHub(find.text('Ziel —')), findsNothing);
  expect(inJournalHub(find.text('Kein Ziel')), findsNothing);
  await h.capture('journal-hub-targets-retry-dark');
}
