part of 'harness.dart';

Future<void> reviewSleepLegend(ReviewHarness h) async {
  final tester = h.tester;
  Future<void> openSleep({
    SyntheticScenario scenario = SyntheticScenario.complete,
    Brightness brightness = Brightness.light,
    double? scale,
  }) async {
    await h.mount(scenario: scenario, brightness: brightness, scale: scale);
    await h.openSleep();
  }

  Finder sleepHeroText(String text) => find.descendant(
    of: find.byType(g3sleep.OBSleepLead),
    matching: find.text(text),
  );

  Finder stageLegendText(String text) => find.descendant(
    of: find.byType(g3day.OBStageLegend),
    matching: find.text(text),
  );

  Future<void> showLegend() async {
    final target = find.byType(g3day.OBStageLegend);
    await tester.scrollUntilVisible(
      target,
      160,
      scrollable: h.verticalScrollable().last,
    );
    await tester.pumpAndSettle();
    expect(target, findsOneWidget);
    expect(find.byType(g3day.OBStageLegend), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sleep-stage-swatch-Im Bett')),
      findsNothing,
    );
  }

  Future<void> closeSleep() async {
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.button == true &&
            widget.properties.label == 'Heute' &&
            widget.child is Pressable,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('g3-sleep')), findsNothing);
  }

  await openSleep();
  expect(sleepHeroText('7h18'), findsOneWidget);
  await h.capture('sleep-legend-light-hero');
  await showLegend();
  expect(stageLegendText('Tief'), findsOneWidget);
  expect(stageLegendText('Leicht'), findsOneWidget);
  expect(stageLegendText('REM'), findsOneWidget);
  expect(stageLegendText('Wach'), findsOneWidget);
  expect(find.text('7h44 im Bett'), findsOneWidget);
  expect(stageLegendText('1h08'), findsOneWidget);
  expect(stageLegendText('4h07'), findsOneWidget);
  expect(stageLegendText('2h03'), findsOneWidget);
  expect(stageLegendText('26 Min.'), findsOneWidget);
  expect(stageLegendText('Im Bett'), findsNothing);
  await h.capture('sleep-legend-light');
  await closeSleep();

  await openSleep(brightness: Brightness.dark);
  await showLegend();
  expect(stageLegendText('4h07'), findsOneWidget);
  await h.capture('sleep-legend-dark');
  await closeSleep();

  await openSleep(scenario: SyntheticScenario.partial);
  await showLegend();
  expect(
    find.descendant(
      of: find.byType(g3day.OBStageLegend),
      matching: find.text('—'),
    ),
    findsNothing,
  );
  await h.capture('sleep-legend-partial');
  await closeSleep();

  await openSleep(scenario: SyntheticScenario.missing);
  expect(sleepHeroText('Keine Nacht erkannt'), findsOneWidget);
  expect(find.byType(g3day.OBStageLegend), findsNothing);
  await h.capture('sleep-legend-missing');
  await closeSleep();

  await openSleep(scale: 2);
  expect(sleepHeroText('7h18'), findsOneWidget);
  await h.capture('sleep-legend-375-2x-hero');
  await showLegend();
  expect(stageLegendText('Leicht'), findsOneWidget);
  expect(stageLegendText('26 Min.'), findsOneWidget);
  await h.capture('sleep-legend-375-2x');
  await closeSleep();

  await openSleep(brightness: Brightness.dark, scale: 2);
  await showLegend();
  expect(stageLegendText('Leicht'), findsOneWidget);
  expect(stageLegendText('26 Min.'), findsOneWidget);
  await h.capture('sleep-legend-375-2x-dark');
  await closeSleep();
  expect(tester.takeException(), isNull);
}
