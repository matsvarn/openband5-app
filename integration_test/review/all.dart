part of 'harness.dart';

Future<void> reviewAll(ReviewHarness h) async {
  await reviewOverviewCorrection(h);
  await reviewSleepGoal(h);
  await reviewTrainingTemplates(h);
  await reviewStrengthLive(h);
  await reviewJournal(h);
  await reviewGestures(h);
  await reviewNight(h);
  await reviewAlarm(h);
  await reviewNaps(h);
  await reviewFirstSync(h);
  await reviewNotifications(h);
  await reviewAppearance(h);
  await reviewUnits(h);
  await reviewWeight(h);
}
