part of 'harness.dart';

Future<void> reviewCorrection(ReviewHarness h) async {
  final tester = h.tester;
  await h.mount();
  await h.edit();
  await h.capture('correction-edit');
  await h.mount(brightness: Brightness.dark);
  await h.edit(variant: '-dark');
  await h.capture('correction-edit-dark');
  await h.mount(scale: 2);
  await h.edit(variant: '-large');
  await tester.ensureVisible(find.byKey(const ValueKey('sleep-wake')));
  await tester.enterText(find.byKey(const ValueKey('sleep-wake')), '06:54');
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await h.capture('correction-large-edit');
  return;
}

Future<void> reviewOverviewCorrection(ReviewHarness h) async {
  final tester = h.tester;
  for (final scenario in [
    SyntheticScenario.complete,
    SyntheticScenario.dense,
    SyntheticScenario.partial,
    SyntheticScenario.missing,
    SyntheticScenario.processing,
    SyntheticScenario.disconnected,
    SyntheticScenario.interrupted,
  ]) {
    for (final brightness in Brightness.values) {
      await h.mount(scenario: scenario, brightness: brightness);
      await h.capture('overview-${scenario.name}-${brightness.name}');
      if ([
        SyntheticScenario.complete,
        SyntheticScenario.dense,
        SyntheticScenario.partial,
        SyntheticScenario.missing,
        SyntheticScenario.processing,
      ].contains(scenario)) {
        await h.openSleep();
        await h.capture('sleep-${scenario.name}-${brightness.name}');
      }
    }
  }

  await h.mount();
  await tester.tap(find.bySemanticsLabel('Kalender'));
  await tester.pumpAndSettle();
  await h.capture('date-selection');
  await h.tap(find.bySemanticsLabel('Schließen'));
  await tester.pumpAndSettle();
  await h.edit(captureEntry: true);
  await h.capture('correction-edit');
  await h.press('Speichern');
  expect(find.text('Zeiten korrigiert'), findsWidgets);
  await h.capture('correction-complete');
  await h.press('Zur Übersicht');
  await h.openSleep();
  expect(
    find.descendant(
      of: find.byType(g3sleep.OBSleepLead),
      matching: find.text('7h08'),
    ),
    findsOneWidget,
  );
  await h.press('Heute');
  await h.capture('overview-corrected');

  final failing = await h.mount(scenario: SyntheticScenario.saveFailure);
  await h.edit(variant: '-save-failure');
  await h.press('Speichern');
  expect(await failing.readDraft('2026-09-15'), isNotNull);
  await h.capture('save-failure');
  failing.scenario = SyntheticScenario.complete;
  await h.press('Erneut speichern');
  expect(find.text('Zeiten korrigiert'), findsWidgets);
  await h.capture('save-retry-complete');

  final calculationFailure = await h.mount(
    scenario: SyntheticScenario.calculationFailure,
  );
  await h.edit(variant: '-calculation-failure');
  await h.press('Speichern');
  expect(find.text('Auswertung erneut starten'), findsOneWidget);
  await h.capture('calculation-failure');
  calculationFailure.scenario = SyntheticScenario.complete;
  await h.press('Auswertung erneut starten');
  await h.capture('calculation-retry-complete');
  await h.press('Nacht ansehen');
  await tester.scrollUntilVisible(
    find.widgetWithText(g3chrome.OBLink, 'Zeiten ändern'),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
  expect(find.widgetWithText(g3chrome.OBLink, 'Zeiten ändern'), findsOneWidget);
  await h.capture('sleep-corrected');

  final pending = await h.mount(brightness: Brightness.dark);
  final calculation = Completer<void>();
  pending.calculationBarrier = calculation.future;
  await h.edit(variant: '-dark', captureEntry: true);
  await h.capture('correction-edit-dark');
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(
    find.widgetWithText(g3chrome.OBActionPrimary, 'Speichern'),
  );
  await tester.tap(find.widgetWithText(g3chrome.OBActionPrimary, 'Speichern'));
  await reviewPumpPageTransitions(tester);
  expect(find.text('Zeiten gespeichert'), findsWidgets);
  await h.capture('correction-pending-dark');
  calculation.complete();
  await tester.pumpAndSettle();
  await h.capture('correction-complete-dark');
  await h.press('Automatische Zeiten wiederherstellen');
  await h.capture('restore-confirmation-dark');
  await h.press('Wiederherstellen');
  expect((await pending.readDay('2026-09-15')).sleep.duration.value, 438);
  expect(
    find.descendant(
      of: find.byType(g3sleep.OBSleepLead),
      matching: find.text('7h18'),
    ),
    findsOneWidget,
  );

  await h.mount();
  await tester.tap(find.bySemanticsLabel('Kalender'));
  await tester.pumpAndSettle();
  await h.tap(
    find.descendant(of: find.byType(BottomSheet), matching: find.text('14')),
  );
  await h.capture('date-selected-night');
  await h.press('Ansehen');
  await h.openSleep();
  expect(
    find.descendant(
      of: find.byType(g3sleep.OBSleepLead),
      matching: find.text('7h02'),
    ),
    findsOneWidget,
  );
  await h.press('Heute');
  await h.capture('overview-historical');

  final draftFailure = await h.mount(scenario: SyntheticScenario.draftFailure);
  await h.openSleep();
  await h.pressSleepEditor();
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('sleep-onset')), '23:25');
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Entwurf erneut sichern'));
  await h.capture('draft-save-failure');
  draftFailure.scenario = SyntheticScenario.complete;
  await h.press('Entwurf erneut sichern');
  expect((await draftFailure.readDraft('2026-09-15'))?.onset.minute, 25);

  await h.mount(scenario: SyntheticScenario.partial);
  await h.openSleep();
  await tester.scrollUntilVisible(
    find.text('02:10–02:34 ohne Daten · nicht aufgefüllt'),
    200,
    scrollable: h.verticalScrollable().last,
  );
  await tester.pumpAndSettle();
  expect(
    find.text('02:10–02:34 ohne Daten · nicht aufgefüllt'),
    findsOneWidget,
  );
  await h.capture('sleep-phases-gap');

  final cancelled = await h.mount();
  await h.edit(variant: '-cancel');
  await reviewTapHeaderBack(tester);
  await tester.pumpAndSettle();
  await h.capture('draft-leave-confirmation');
  await h.press('Entwurf behalten');
  await h.pressSleepEditor();
  await tester.pumpAndSettle();
  expect(
    tester
        .widget<TextField>(find.byKey(const ValueKey('sleep-onset')))
        .controller
        ?.text,
    '23:25',
  );
  await h.press('Änderung verwerfen');
  expect(await cancelled.readDraft('2026-09-15'), isNull);
  expect((await cancelled.readDay('2026-09-15')).sleep.duration.value, 438);
  expect(
    find.descendant(
      of: find.byType(g3sleep.OBSleepLead),
      matching: find.text('7h18'),
    ),
    findsOneWidget,
  );

  await h.mount(scale: 2);
  await h.capture('overview-large-text');
  await h.openSleep();
  await h.capture('sleep-large-text');
  await h.pressSleepEditor();
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('sleep-onset')), '23:25');
  await tester.pumpAndSettle();
  await h.capture('correction-large-keyboard');
  await tester.ensureVisible(find.byKey(const ValueKey('sleep-wake')));
  await tester.enterText(find.byKey(const ValueKey('sleep-wake')), '06:54');
  await tester.pumpAndSettle();
  await h.capture('correction-large-wake-keyboard');
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await h.capture('correction-large-edit');
  await h.press('Speichern');
  await h.capture('correction-large-complete');
  await h.press('Zur Übersicht');
  await h.press('Heute');
  await tester.tap(find.bySemanticsLabel('Kalender'));
  await tester.pumpAndSettle();
  await h.capture('date-large-text');
  await h.tap(
    find.descendant(of: find.byType(BottomSheet), matching: find.text('14')),
  );
  await h.press('Ansehen');
  await h.openSleep();
  expect(
    find.descendant(
      of: find.byType(g3sleep.OBSleepLead),
      matching: find.text('7h02'),
    ),
    findsOneWidget,
  );
  await h.press('Heute');
}
