import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'review/harness.dart';
export 'review/harness.dart';

const reviewFlows = <String, Future<void> Function(ReviewHarness)>{
  'all': reviewAll,
  'correction': reviewCorrection,
  'journal': reviewJournal,
  'journal-hub': reviewJournal,
  'nutrition-entry': reviewNutritionEntry,
  'nutrition-parent': reviewNutritionParent,
  'sleep-plan': reviewSleepPlan,
  'naps': reviewNaps,
  'exercise-picker': reviewExercisePicker,
  'custom-exercise': reviewCustomExercise,
  'exercise-copy': reviewExerciseCopy,
  'custom-load': reviewCustomLoad,
  'glucose': reviewGlucose,
  'medications': reviewMedications,
  'cycle': reviewCycle,
  'cycle-measurements': reviewCycleMeasurements,
  'cycle-observations': reviewCycleObservations,
  'cycle-gaps': reviewCycleGaps,
  'cycle-medians': reviewCycleMedians,
  'cycle-comparison': reviewCycleComparison,
  'night-scalar': reviewNightScalar,
  'night-cards': reviewNightCards,
  'sleep-legend': reviewSleepLegend,
  'respiration': reviewRespiration,
  'temperature': reviewTemperature,
  'weight': reviewWeight,
  'vo2': reviewVo2,
  'release': reviewRelease,
};

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final frames = <Map<String, Object?>>[];
  final captureFilter = reviewCaptureFilter(kOpenBandReviewCaptures);
  final capturedNames = <String>{};

  testWidgets('native first-flow visual review with isolated synthetic data', (
    tester,
  ) async {
    final flow = reviewFlows[kOpenBandReviewFlow];
    if (flow == null) {
      throw StateError(
        'Unknown OPENBAND_REVIEW_FLOW: $kOpenBandReviewFlow '
        '(expected all, correction, journal, journal-hub, nutrition-entry, nutrition-parent, sleep-plan, naps, exercise-picker, custom-exercise, exercise-copy, custom-load, glucose, medications, cycle, cycle-measurements, cycle-observations, cycle-gaps, cycle-medians, cycle-comparison, night-scalar, night-cards, sleep-legend, respiration, temperature, weight, vo2, or release)',
      );
    }
    await initializeDateFormatting('de_DE');
    final semantics = tester.ensureSemantics();
    final previousHitTestPolicy = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    var flowFailed = false;
    try {
      final h = ReviewHarness(
        tester: tester,
        binding: binding,
        captureFilter: captureFilter,
        capturedNames: capturedNames,
        frames: frames,
      );
      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['flow'] = kOpenBandReviewFlow;
      await flow(h);
    } catch (_) {
      flowFailed = true;
      rethrow;
    } finally {
      WidgetController.hitTestWarningShouldBeFatal = previousHitTestPolicy;
      semantics.dispose();
      if (!flowFailed) {
        reviewEnsureRequestedCaptures(captureFilter, capturedNames);
      }
    }
  });
}
