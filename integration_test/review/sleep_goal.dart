part of 'harness.dart';

Future<void> reviewSleepGoal(ReviewHarness h) async {
  Future<SyntheticOpenBandRepository> openGoal({
    Brightness brightness = Brightness.light,
    double? scale,
    int? target,
  }) async {
    final repository = await h.mount(brightness: brightness, scale: scale);
    if (target != null) await repository.saveSleepGoal('2026-09-15', target);
    await h.openSleep();
    await h.tap(find.byType(g3sleep.OBSleepLead));
    expect(
      find.text(target == null ? 'Schlafziel festlegen' : 'Schlafziel'),
      findsOneWidget,
    );
    return repository;
  }

  Finder goalValue(String value) => find.descendant(
    of: find.byKey(const ValueKey('g3-sleep-goal-value')),
    matching: find.text(value),
    matchRoot: true,
  );
  final unset = await openGoal();
  expect((await unset.readSleepGoal('2026-09-15')).targetMinutes, isNull);
  expect(goalValue('6h41'), findsOneWidget);
  expect(find.text('Start: dein Ø der letzten 7 Nächte'), findsOneWidget);
  await h.capture('sleep-goal-unset');
  await h.press('+15 Min.');
  expect(goalValue('6h56'), findsOneWidget);
  await h.capture('sleep-goal-editor');
  await h.press('Ziel speichern');
  expect((await unset.readSleepGoal('2026-09-15')).targetMinutes, 416);
  expect(find.text('Ziel 6h56'), findsOneWidget);
  await h.capture('sleep-goal-saved');
  await h.tap(find.byType(g3sleep.OBSleepLead));
  await h.press('Verlauf');
  expect(find.text('Letzte 7 Nächte'), findsOneWidget);
  await h.capture('sleep-goal-history');

  for (final (brightness, scale, suffix) in [
    (Brightness.light, 1.0, 'target'),
    (Brightness.dark, 1.0, 'dark'),
    (Brightness.light, 2.0, '2x'),
  ]) {
    await openGoal(brightness: brightness, scale: scale, target: 465);
    expect(goalValue('7h45'), findsOneWidget);
    await h.capture('sleep-goal-editor-$suffix');
    await h.press('Abbrechen');
    expect(find.text('Ziel 7h45'), findsOneWidget);
    await h.capture('sleep-goal-$suffix');
  }
  final failure = await openGoal(target: 465);
  failure.failSleepGoalWrite = true;
  await h.press('+15 Min.');
  expect(goalValue('8h'), findsOneWidget);
  await h.press('Speichern');
  expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
  expect((await failure.readSleepGoal('2026-09-15')).targetMinutes, 465);
  await h.capture('sleep-goal-error');
  failure.failSleepGoalWrite = false;
  await h.press('Erneut speichern');
  expect((await failure.readSleepGoal('2026-09-15')).targetMinutes, 480);
  expect(find.text('Ziel 8h'), findsOneWidget);
}
