part of 'harness.dart';

Future<void> reviewNight(ReviewHarness h) async {
  Future<void> openNight({
    Brightness brightness = Brightness.light,
    SyntheticScenario scenario = SyntheticScenario.complete,
    double? scale,
  }) async {
    await h.mount(brightness: brightness, scenario: scenario, scale: scale);
    await h.openSleep();
    await h.tap(
      find.byWidgetPredicate(
        (widget) => widget is g3metrics.G3LabelRow && widget.label == 'NACHT',
      ),
    );
    expect(find.byType(G3SleepNightSignals), findsOneWidget);
  }

  Future<void> showTrace(String lowest) async {
    await h.tap(find.text(lowest));
    expect(find.byType(g3sleep.OBNightTrace), findsOneWidget);
    expect(find.text(lowest), findsOneWidget);
  }

  for (final brightness in Brightness.values) {
    await openNight(brightness: brightness);
    await showTrace('tiefster 48 um 05:34');
    await h.capture('night-pulse-${brightness.name}');
    await h.tap(find.bySemanticsLabel('HRV'));
    await showTrace('tiefster 58 um 00:40');
    await h.capture('night-hrv-${brightness.name}');
    await h.tap(find.bySemanticsLabel('Atemfrequenz'));
    await showTrace('tiefster 13,6 um 02:49');
    await h.capture('night-respiration-${brightness.name}');
    await h.tap(find.bySemanticsLabel('Erklärung'));
    expect(
      find.text(
        'Gespeicherte Signale während der erkannten Nacht. Lücken bleiben leer; einzelne Werte werden nicht verbunden.',
      ),
      findsOneWidget,
    );
    await h.capture('night-info-${brightness.name}');
    await h.tap(find.bySemanticsLabel('Schließen'));
  }
  await openNight(scenario: SyntheticScenario.partial);
  await showTrace('tiefster 50 um 05:10');
  expect(
    find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label ==
              'Nachtverlauf mit 6 gespeicherten Messpunkten. Lücken bleiben leer.',
    ),
    findsOneWidget,
  );
  await h.capture('night-gap-trace');
  await openNight(scenario: SyntheticScenario.missingNightHrv);
  await h.tap(find.bySemanticsLabel('HRV'));
  await h.tap(find.text('Keine gespeicherten Werte'));
  expect(find.text('Keine gespeicherten Werte'), findsOneWidget);
  expect(find.byType(g3sleep.OBNightTrace), findsNothing);
  await h.capture('night-hrv-missing');
  await openNight(scale: 2);
  await h.tap(find.bySemanticsLabel('Atemfrequenz'));
  await showTrace('tiefster 13,6 um 02:49');
  await h.capture('night-large-text');
}
