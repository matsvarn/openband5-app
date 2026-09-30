part of 'harness.dart';

Future<void> reviewNight(ReviewHarness h) async {
  final tester = h.tester;
  for (final brightness in [Brightness.light, Brightness.dark]) {
    await h.mount(brightness: brightness);
    await tester.tap(find.bySemanticsLabel('Schlaf, 7h18 '));
    await tester.pumpAndSettle();
    await h.press('Nachtverlauf');
    await h.capture('night-pulse-${brightness.name}');
    await h.press('HRV');
    expect(find.text('60'), findsOneWidget);
    await h.capture('night-hrv-${brightness.name}');
    await h.press('Atmung');
    expect(find.text('14,2'), findsOneWidget);
    await h.capture('night-respiration-${brightness.name}');
    await tester.tap(find.byTooltip('Nachtverlauf: Quelle und Darstellung'));
    await tester.pumpAndSettle();
    await h.capture('night-info-${brightness.name}');
    await h.press('Schließen');
  }
  for (final scenario in [
    SyntheticScenario.partial,
    SyntheticScenario.missingNightHrv,
  ]) {
    await h.mount(scenario: scenario);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Schlaf, ')));
    await tester.pumpAndSettle();
    await h.press('Nachtverlauf');
    if (scenario == SyntheticScenario.partial) {
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byTooltip('Nächster Messpunkt'));
        await tester.pumpAndSettle();
      }
      expect(find.text('02:10'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      await h.capture('night-gap-selected');
    } else {
      await h.press('HRV');
      expect(find.text('Keine HRV-Werte'), findsOneWidget);
      await h.capture('night-hrv-missing');
    }
  }
  await h.mount(scale: 2);
  await tester.tap(find.bySemanticsLabel('Schlaf, 7h18 '));
  await tester.pumpAndSettle();
  await h.press('Nachtverlauf');
  await h.press('Atmung');
  await h.capture('night-large-text');
}
