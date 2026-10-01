// Runs every native review flow headless under `flutter test`, so a flow that
// no longer matches the UI fails in CI instead of rotting until someone opens
// a simulator. Nothing is captured; tool/ui_review.py still takes the
// screenshots. One test file per phone size, so CI shards run them in
// parallel.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../integration_test/openband_review_test.dart';

Future<void> _loadFonts() async {
  ByteData file(String path) =>
      ByteData.sublistView(File(path).readAsBytesSync());
  // Helvetica Neue is the iOS face and cannot be committed; Inter has close
  // metrics, so headless layout stays near the simulator's.
  for (final (family, path) in [
    ('Helvetica Neue', 'assets/fonts/Inter/Inter.ttf'),
    ('Inter', 'assets/fonts/Inter/Inter.ttf'),
    ('Inter Tight', 'assets/fonts/InterTight/InterTight[wght].ttf'),
  ]) {
    await (FontLoader(family)..addFont(Future.value(file(path)))).load();
  }
  await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
        rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
      ))
      .load();
}

/// Defines one test per review flow at the given phone size, in physical
/// pixels at 3x, with that phone's safe area. Without the safe area, lazy
/// lists build rows the phone does not.
void defineReviewFlowTests(
  String device,
  Size size,
  FakeViewPadding padding,
) {
  setUpAll(_loadFonts);

  for (final MapEntry(key: name, value: flow) in reviewFlows.entries) {
    testWidgets(
      'review flow $name ($device)',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 3;
        tester.view.padding = padding;
        tester.view.viewPadding = padding;
        addTearDown(tester.view.reset);
        await initializeDateFormatting('de_DE');
        void keyboardMetrics() {
          final editing = find
              .byType(EditableText)
              .evaluate()
              .any(
                (element) =>
                    (element.widget as EditableText).focusNode.hasFocus,
              );
          tester.view.viewInsets = FakeViewPadding(bottom: editing ? 1008 : 0);
        }

        FocusManager.instance.addListener(keyboardMetrics);
        addTearDown(
          () => FocusManager.instance.removeListener(keyboardMetrics),
        );
        final semantics = tester.ensureSemantics();
        final previous = WidgetController.hitTestWarningShouldBeFatal;
        WidgetController.hitTestWarningShouldBeFatal = true;
        final elapsed = Stopwatch()..start();
        try {
          await flow(
            ReviewHarness(
              tester: tester,
              binding: null,
              flow: name,
              captureFilter: const {},
              capturedNames: {},
              frames: [],
            ),
          );
        } finally {
          elapsed.stop();
          debugPrint(
            'REVIEW_DURATION $name ($device) ${elapsed.elapsedMilliseconds}ms',
          );
          WidgetController.hitTestWarningShouldBeFatal = previous;
          semantics.dispose();
          debugDefaultTargetPlatformOverride = null;
        }
      },
      // `all` walks every flow in sequence: about 80 s on a hosted runner.
      timeout: Timeout(Duration(minutes: name == 'all' ? 5 : 2)),
    );
  }
}
