// Native review flows, headless, iPhone 15 Pro: 393 x 852 pt, safe area
// 59 / 34 pt. See test/support/review_flows.dart.
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/review_flows.dart';

void main() => defineReviewFlowTests(
  '15 Pro',
  const Size(1179, 2556),
  const FakeViewPadding(top: 177, bottom: 102),
);
