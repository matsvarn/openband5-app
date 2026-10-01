// Native review flows, headless, iPhone 13 mini: 375 x 812 pt, safe area
// 50 / 34 pt. See test/support/review_flows.dart.
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/review_flows.dart';

void main() => defineReviewFlowTests(
  '13 mini',
  const Size(1125, 2436),
  const FakeViewPadding(top: 150, bottom: 102),
);
