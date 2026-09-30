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
        await tester.tap(find.bySemanticsLabel(RegExp(r'^Schlaf, ')).first);
        await tester.pumpAndSettle();
        await h.capture('sleep-${scenario.name}-${brightness.name}');
      }
    }
  }

  await h.mount();
  await tester.tap(find.text(obDayTitle('2026-09-15')));
  await tester.pumpAndSettle();
  await h.capture('date-selection');
  await tester.tap(find.byTooltip('Abbrechen'));
  await tester.pumpAndSettle();
  await h.edit(captureEntry: true);
  await h.capture('correction-edit');
  await h.press('Schlafzeiten speichern');
  expect(find.text('Schlaf aktualisiert'), findsWidgets);
  await h.capture('correction-complete');
  await h.press('Zur Übersicht');
  expect(find.bySemanticsLabel('Schlaf, 7h08 '), findsOneWidget);
  await h.capture('overview-corrected');

  final failing = await h.mount(scenario: SyntheticScenario.saveFailure);
  await h.edit(variant: '-save-failure');
  await h.press('Schlafzeiten speichern');
  expect(await failing.readDraft('2026-09-15'), isNotNull);
  await h.capture('save-failure');
  failing.scenario = SyntheticScenario.complete;
  await h.press('Erneut speichern');
  expect(find.text('Schlaf aktualisiert'), findsWidgets);
  await h.capture('save-retry-complete');

  final calculationFailure = await h.mount(
    scenario: SyntheticScenario.calculationFailure,
  );
  await h.edit(variant: '-calculation-failure');
  await h.press('Schlafzeiten speichern');
  expect(find.text('Auswertung erneut starten'), findsOneWidget);
  await h.capture('calculation-failure');
  calculationFailure.scenario = SyntheticScenario.complete;
  await h.press('Auswertung erneut starten');
  await h.capture('calculation-retry-complete');
  await h.press('Nacht ansehen');
  await tester.scrollUntilVisible(
    find.byTooltip('Schlafzeiten ändern'),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
  expect(find.byTooltip('Schlafzeiten ändern'), findsOneWidget);
  await h.capture('sleep-corrected');

  final pending = await h.mount(brightness: Brightness.dark);
  final calculation = Completer<void>();
  pending.calculationBarrier = calculation.future;
  await h.edit(variant: '-dark', captureEntry: true);
  await h.capture('correction-edit-dark');
  await h.press('Schlafzeiten speichern');
  expect(find.text('Zeiten gespeichert'), findsWidgets);
  await h.capture('correction-pending-dark');
  calculation.complete();
  await tester.pumpAndSettle();
  await h.capture('correction-complete-dark');
  await h.press('Automatische Zeiten wiederherstellen');
  await h.capture('restore-confirmation-dark');
  await h.press('Wiederherstellen');
  expect((await pending.readDay('2026-09-15')).sleep.duration.value, 438);
  expect(find.text('7h18'), findsNWidgets(2));

  await h.mount();
  await tester.tap(find.text(obDayTitle('2026-09-15')));
  await tester.pumpAndSettle();
  await h.press('14');
  await h.capture('date-selected-night');
  await h.press('14. September ansehen');
  expect(find.bySemanticsLabel('Schlaf, 7h02 '), findsOneWidget);
  await h.capture('overview-historical');

  final draftFailure = await h.mount(scenario: SyntheticScenario.draftFailure);
  await tester.tap(find.bySemanticsLabel('Schlaf, 7h18 '));
  await tester.pumpAndSettle();
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
  await tester.tap(find.bySemanticsLabel(RegExp(r'^Schlaf, ')).first);
  await tester.pumpAndSettle();
  await tester.tap(
    find.bySemanticsLabel(RegExp('02:10 bis 02:34: Keine Daten')).first,
  );
  await tester.pumpAndSettle();
  await h.capture('sleep-phases');
  await tester.tap(find.byTooltip('Schließen'));
  await tester.pumpAndSettle();

  final cancelled = await h.mount();
  await h.edit(variant: '-cancel');
  await h.press('Weiter bearbeiten');
  await tester.tap(find.byTooltip('Zurück').first);
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
  expect(find.text('7h18'), findsNWidgets(2));

  await h.mount(scale: 2);
  await h.capture('overview-large-text');
  await tester.tap(find.bySemanticsLabel('Schlaf, 7h18 '));
  await tester.pumpAndSettle();
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
  await h.press('Schlafzeiten speichern');
  await h.capture('correction-large-complete');
  await h.press('Zur Übersicht');
  await tester.tap(find.text(obDayTitle('2026-09-15')));
  await tester.pumpAndSettle();
  await h.capture('date-large-text');
  await h.press('14');
  await h.press('14. September ansehen');
  expect(find.bySemanticsLabel('Schlaf, 7h02 '), findsOneWidget);
}
