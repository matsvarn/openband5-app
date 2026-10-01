part of 'harness.dart';

Future<void> reviewNaps(ReviewHarness h) async {
  final tester = h.tester;
  Future<void> openNaps() async {
    await h.openSleep();
    final row = find.byWidgetPredicate(
      (widget) =>
          widget is g3chrome.OBListRow &&
          (widget.title == 'Nickerchen' ||
              widget.title == 'Noch keins erkannt'),
    );
    await h.tap(row);
  }

  Finder todayNap() =>
      find.widgetWithText(g3chrome.OBListRow, 'Di 15.09 · 14:10–14:42');
  Finder todayNapText(String text) =>
      find.descendant(of: todayNap(), matching: find.text(text));

  await h.mount();
  await openNaps();
  expect(find.text('Di 15.09 · 14:10–14:42'), findsOneWidget);
  expect(todayNapText('auto-erkannt · 32 Min. gelegen'), findsOneWidget);
  await h.capture('naps-list');
  await h.press('Nickerchen eintragen');
  expect(find.text('Selbst eingetragen'), findsNothing);
  await tester.enterText(
    find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.semanticCounterText == 'Beginn',
    ),
    '16:00',
  );
  await tester.enterText(
    find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.semanticCounterText == 'Ende',
    ),
    '16:40',
  );
  await tester.pumpAndSettle();
  expect(find.text('40 Minuten gelegen'), findsOneWidget);
  await h.capture('naps-add');
  await h.press('Speichern');
  expect(find.text('Di 15.09 · 16:00–16:40'), findsOneWidget);
  expect(find.text('eingetragen'), findsOneWidget);
  await tester.tap(find.text('Di 15.09 · 14:10–14:42'));
  await tester.pumpAndSettle();
  await h.capture('naps-edit');
  await h.press('Nickerchen entfernen');
  expect(find.text('14:10–14:42 entfernen?'), findsOneWidget);
  await tester.tap(find.text('Entfernen').last);
  await tester.pumpAndSettle();
  expect(find.text('14:10–14:42 wiederherstellen'), findsOneWidget);
  await h.capture('naps-removed');
  await h.press('14:10–14:42 wiederherstellen');
  expect(todayNapText('auto-erkannt'), findsOneWidget);
  expect(todayNapText('—'), findsOneWidget);

  final napFail = await h.mount(scenario: SyntheticScenario.calculationFailure);
  await openNaps();
  await h.press('Nickerchen eintragen');
  await tester.enterText(
    find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.semanticCounterText == 'Beginn',
    ),
    '16:00',
  );
  await tester.enterText(
    find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.semanticCounterText == 'Ende',
    ),
    '16:40',
  );
  await h.press('Speichern');
  expect(find.text('Gespeichert · Auswertung offen'), findsOneWidget);
  expect(find.text('Erneut auswerten'), findsOneWidget);
  expect(find.text('Di 15.09 · 16:00–16:40'), findsOneWidget);
  expect(find.text('—'), findsWidgets);
  expect(find.text('72'), findsNothing);
  await h.capture('naps-recalc-failure');
  napFail.scenario = SyntheticScenario.complete;
  await h.press('Erneut auswerten');
  expect(find.text('Di 15.09 · 16:00–16:40'), findsOneWidget);
  await h.capture('naps-recalc-retry');

  final empty = await h.mount();
  for (final day in openBandDaysEnding('2026-09-15', 7)) {
    empty.seedNaps(NapDay(day: day, judged: true, totalMin: 0));
  }
  await openNaps();
  expect(find.text('Keine Nickerchen'), findsOneWidget);
  await h.capture('naps-empty');

  final unknown = await h.mount();
  for (final day in openBandDaysEnding('2026-09-15', 7)) {
    unknown.seedNaps(NapDay(day: day));
  }
  await openNaps();
  expect(find.text('Noch nicht beurteilbar'), findsOneWidget);
  expect(find.text('—'), findsWidgets);
  await h.capture('naps-unknown');

  await h.mount(brightness: Brightness.dark);
  await openNaps();
  await h.capture('naps-dark');
  await h.press('Nickerchen eintragen');
  await h.capture('naps-add-dark');

  await h.mount(scale: 2);
  await openNaps();
  expect(tester.takeException(), isNull);
  await h.capture('naps-large-text');
  await h.press('Nickerchen eintragen');
  expect(tester.takeException(), isNull);
  await h.capture('naps-add-large-text');
}
