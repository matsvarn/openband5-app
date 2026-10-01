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
  await reviewCorrection(h);
  await reviewRelease(h);
  await reviewSleepPlan(h);
  await reviewExercisePicker(h);
  await reviewCustomExercise(h);
  await reviewExerciseCopy(h);
  await reviewCustomLoad(h);
  await reviewNightScalar(h);
  await reviewNightCards(h);
  await reviewSleepLegend(h);
  await reviewRespiration(h);
  await reviewTemperature(h);
  await reviewVo2(h);
}
