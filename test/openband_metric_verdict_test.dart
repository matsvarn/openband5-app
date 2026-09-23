import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/night_scalar_data.dart';

void main() {
  // Normal range = baseline ± 1.253 × spread; spread 4/1.253 gives 36–44.
  const spread = 4 / 1.253;

  test('inside the range is normal', () {
    expect(metricVerdict(MetricKey.hrv, 44, 40, spread), MetricVerdict.normal);
    expect(
      metricVerdict(MetricKey.restingHr, 38, 40, spread),
      MetricVerdict.normal,
    );
  });

  test('direction decides better or worse', () {
    expect(metricVerdict(MetricKey.hrv, 48, 40, spread), MetricVerdict.better);
    expect(metricVerdict(MetricKey.hrv, 30, 40, spread), MetricVerdict.worse);
    expect(
      metricVerdict(MetricKey.restingHr, 48, 40, spread),
      MetricVerdict.worse,
    );
    expect(
      metricVerdict(MetricKey.restingHr, 30, 40, spread),
      MetricVerdict.better,
    );
  });

  test('breathing rate has no good side', () {
    expect(
      metricVerdict(MetricKey.respiration, 48, 40, spread),
      MetricVerdict.worse,
    );
    expect(
      metricVerdict(MetricKey.respiration, 30, 40, spread),
      MetricVerdict.worse,
    );
  });

  test('no range, no verdict', () {
    expect(metricVerdict(MetricKey.hrv, 48, 40, null), isNull);
    expect(metricVerdict(MetricKey.hrv, 48, null, spread), isNull);
    expect(metricVerdict(MetricKey.hrv, null, 40, spread), isNull);
    expect(metricVerdict(MetricKey.recovery, 80, 60, spread), isNull);
  });

  test('card verdict needs a current trusted comparison', () {
    final current = dayMetricFromNightScalar(
      state: NightScalarState.current,
      value: 48,
      baseline: const StoredNightBaseline(
        value: 40,
        spread: spread,
        status: 'trusted',
      ),
    );
    expect(dayMetricVerdict(MetricKey.hrv, current), MetricVerdict.better);
    final provisional = dayMetricFromNightScalar(
      state: NightScalarState.current,
      value: 48,
      baseline: const StoredNightBaseline(
        value: 40,
        spread: spread,
        status: 'provisional',
      ),
    );
    expect(dayMetricVerdict(MetricKey.hrv, provisional), isNull);
  });
}
