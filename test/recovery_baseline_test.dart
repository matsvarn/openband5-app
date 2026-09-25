// The Erholung baseline (algo 97): `baselines.recovery` folds the headline
// readiness of PRIOR days only, so a re-derive of the same day with the same
// history yields the same block, and a missing history never invents one.
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/onehz_pipeline.dart';

void main() {
  const dayStart = 1767225600;
  const n = 600;

  Map<String, dynamic> recoveryBlock(List<double> history) {
    final ts = [for (var i = 0; i < n; i++) dayStart + i];
    final hr = [for (var i = 0; i < n; i++) 60];
    final bundle = deriveDayBundle(
      DayBundleInput(
        date: '2026-01-01',
        dayTsSec: ts,
        dayHr: hr,
        sleepTsSec: const [],
        sleepHr: const [],
        sleepRrTsMs: const [],
        sleepRrMs: const [],
        sleepSkinTemp: const [],
        sleepJson: const {},
        hypnoStages: const [],
        sleepOnsetSec: 0,
        sleepOffsetSec: 0,
        profile: const {},
        dayConfidence: 0.5,
        dayFlags: const [],
        deviceFamily: 'gen5',
        readinessHistory: history,
      ).toJson(),
    );
    return ((bundle['baselines'] as Map)['recovery'] as Map)
        .cast<String, dynamic>();
  }

  final history = [
    for (var i = 0; i < 20; i++) 60.0 + (i % 5) * 2, // 60–68, centre ~64
  ];

  test('20 prior days make a trusted baseline near their centre', () {
    final b = recoveryBlock(history);
    expect(b['status'], 'trusted');
    expect(b['n_valid'], 20);
    expect(b['baseline'] as num, closeTo(64, 3));
    expect(b['spread'] as num, greaterThanOrEqualTo(3),
        reason: 'the 3-point floor keeps the range from collapsing');
  });

  test('a re-derive with the same history gives the same block', () {
    expect(recoveryBlock(history), recoveryBlock(history));
  });

  test('few prior days stay below trusted', () {
    final b = recoveryBlock(history.sublist(0, 5));
    expect(b['status'], isNot('trusted'));
  });

  test('no history, no baseline', () {
    final b = recoveryBlock(const []);
    expect(b['baseline'], isNull);
    expect(b['spread'], isNull);
    expect(b['status'], 'calibrating');
  });
}
