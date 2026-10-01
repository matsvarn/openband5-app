part of 'harness.dart';

Future<void> reviewSleepGoal(ReviewHarness h) async {
  final tester = h.tester;
  Future<SyntheticOpenBandRepository> openSleepGoal({
    SyntheticScenario scenario = SyntheticScenario.complete,
    Brightness brightness = Brightness.light,
    double? scale,
    int? targetMinutes,
    bool estimate = true,
  }) async {
    final repository = await h.mount(
      scenario: scenario,
      brightness: brightness,
      scale: scale,
    );
    if (!estimate) repository.weekendEstimate = null;
    if (targetMinutes != null) {
      await repository.saveSleepGoal('2026-09-15', targetMinutes);
    }
    await tester.tap(find.bySemanticsLabel('Schlaf, 7h18 '));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Schlafziel'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schlafziel'));
    await tester.pumpAndSettle();
    return repository;
  }

  await openSleepGoal();
  expect(find.text('Ziel festlegen'), findsOneWidget);
  expect(find.text('7 h 45'), findsNothing);
  await h.capture('sleep-goal-unset');
  await h.press('Ziel festlegen');
  await h.capture('sleep-goal-editor');
  await tester.enterText(find.byKey(const ValueKey('sleep-goal-hours')), '7');
  await tester.enterText(
    find.byKey(const ValueKey('sleep-goal-minutes')),
    '45',
  );
  await tester.pumpAndSettle();
  await h.press('Speichern');
  expect(find.text('7 h 45'), findsOneWidget);
  expect(find.text('8 h 12 · Stand 15. September'), findsOneWidget);
  await h.capture('sleep-goal-estimate');
  await tester.tap(find.bySemanticsLabel('Wochenend-Schätzung'));
  await tester.pumpAndSettle();
  expect(
    find.text(
      '75. Perzentil der Wochenendnächte. Keine Messung des Schlafbedarfs.',
    ),
    findsOneWidget,
  );
  await h.capture('sleep-goal-estimate-info');
  await h.press('Schließen');
  await openSleepGoal(targetMinutes: 465);
  await h.press('Ändern');
  expect(
    tester
        .widget<TextField>(find.byKey(const ValueKey('sleep-goal-hours')))
        .controller
        ?.text,
    '7',
  );
  expect(
    tester
        .widget<TextField>(find.byKey(const ValueKey('sleep-goal-minutes')))
        .controller
        ?.text,
    '45',
  );
  await h.capture('sleep-goal-editor-target');
  await openSleepGoal(
    brightness: Brightness.dark,
    targetMinutes: 465,
    estimate: false,
  );
  expect(find.text('7 h 45'), findsOneWidget);
  expect(find.text('Ändern'), findsOneWidget);
  expect(find.text('8 h 12 · Stand 15. September'), findsNothing);
  await h.capture('sleep-goal-dark');
  await h.press('Ändern');
  expect(
    tester
        .widget<TextField>(find.byKey(const ValueKey('sleep-goal-hours')))
        .controller
        ?.text,
    '7',
  );
  await h.capture('sleep-goal-editor-dark');
  await openSleepGoal(scale: 2, targetMinutes: 465);
  expect(find.text('7 h 45'), findsOneWidget);
  expect(find.text('8 h 12 · Stand 15. September'), findsOneWidget);
  await h.capture('sleep-goal-2x');
  await h.press('Ändern');
  expect(
    tester
        .widget<TextField>(find.byKey(const ValueKey('sleep-goal-hours')))
        .controller
        ?.text,
    '7',
  );
  await h.capture('sleep-goal-editor-2x');
  final failingGoal = await openSleepGoal();
  failingGoal.failSleepGoalWrite = true;
  await h.press('Ziel festlegen');
  await tester.enterText(find.byKey(const ValueKey('sleep-goal-hours')), '7');
  await tester.enterText(
    find.byKey(const ValueKey('sleep-goal-minutes')),
    '45',
  );
  await tester.pumpAndSettle();
  await h.press('Speichern');
  expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
  await h.capture('sleep-goal-error');
}
