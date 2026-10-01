part of 'harness.dart';

Future<void> reviewNaps(ReviewHarness h) async {
  final tester = h.tester;
  Future<void> openNaps() async {
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Schlaf, ')).first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Nickerchen'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nickerchen'));
    await tester.pumpAndSettle();
  }

  await h.mount();
  await openNaps();
  expect(find.text('14:10–14:42'), findsOneWidget);
  expect(find.text('Erkannt'), findsOneWidget);
  await h.capture('naps-list');
  await h.press('Nickerchen ergänzen');
  expect(find.text('Selbst eingetragen'), findsNothing);
  await tester.enterText(find.byKey(const ValueKey('nap-start')), '16:00');
  await tester.enterText(find.byKey(const ValueKey('nap-end')), '16:40');
  await tester.pumpAndSettle();
  expect(find.text('40 Minuten'), findsOneWidget);
  await h.capture('naps-add');
  await h.press('Speichern');
  expect(find.text('16:00–16:40'), findsOneWidget);
  expect(find.text('Manuell'), findsOneWidget);
  await tester.tap(find.text('14:10–14:42'));
  await tester.pumpAndSettle();
  await h.capture('naps-edit');
  await h.press('Nickerchen entfernen');
  expect(find.text('14:10–14:42 entfernen?'), findsOneWidget);
  await tester.tap(find.text('Entfernen').last);
  await tester.pumpAndSettle();
  expect(find.text('Wiederherstellen'), findsOneWidget);
  await h.capture('naps-removed');
  await h.press('Wiederherstellen');
  expect(find.text('Erkannt'), findsOneWidget);

  final napFail = await h.mount(scenario: SyntheticScenario.calculationFailure);
  await openNaps();
  await h.press('Nickerchen ergänzen');
  await tester.enterText(find.byKey(const ValueKey('nap-start')), '16:00');
  await tester.enterText(find.byKey(const ValueKey('nap-end')), '16:40');
  await h.press('Speichern');
  expect(find.text('Gespeichert · Auswertung offen'), findsOneWidget);
  expect(find.text('Erneut auswerten'), findsOneWidget);
  expect(find.text('16:00–16:40'), findsOneWidget);
  expect(find.text('—'), findsWidgets);
  expect(find.text('72'), findsNothing);
  await h.capture('naps-recalc-failure');
  napFail.scenario = SyntheticScenario.complete;
  await h.press('Erneut auswerten');
  expect(find.text('16:00–16:40'), findsOneWidget);
  await h.capture('naps-recalc-retry');

  final empty = await h.mount();
  empty.seedNaps(const NapDay(day: '2026-09-15', judged: true, totalMin: 0));
  await openNaps();
  expect(find.text('Keine Nickerchen erkannt'), findsOneWidget);
  await h.capture('naps-empty');

  final unknown = await h.mount();
  unknown.seedNaps(const NapDay(day: '2026-09-15'));
  await openNaps();
  expect(find.text('Noch nicht bestimmbar'), findsOneWidget);
  expect(find.text('—'), findsWidgets);
  await h.capture('naps-unknown');

  await h.mount(brightness: Brightness.dark);
  await openNaps();
  await h.capture('naps-dark');
  await h.press('Nickerchen ergänzen');
  await h.capture('naps-add-dark');

  await h.mount(scale: 2);
  await openNaps();
  expect(tester.takeException(), isNull);
  await h.capture('naps-large-text');
  await h.press('Nickerchen ergänzen');
  expect(tester.takeException(), isNull);
  await h.capture('naps-add-large-text');
}
