import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/ble/ble_state.dart' show BleBlocker;
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/gestures/device_action.dart';
import 'package:openstrap_edge/l10n/app_localizations.dart';
import 'package:openstrap_edge/main_gallery.dart';
import 'package:openstrap_edge/notify/notification_prefs.dart';
import 'package:openstrap_edge/openband/appearance.dart';
import 'package:openstrap_edge/openband/calendar.dart';
import 'package:openstrap_edge/openband/calendar_line.dart';
import 'package:openstrap_edge/openband/units.dart';
import 'package:openstrap_edge/openband/notification_settings.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/exercise_definition_editor.dart';
import 'package:openstrap_edge/openband/exercise_picker.dart';
import 'package:openstrap_edge/openband/g3/chrome.dart' as g3chrome;
import 'package:openstrap_edge/openband/g3/journal_parts.dart';
import 'package:openstrap_edge/openband/g3/day.dart' as g3day;
import 'package:openstrap_edge/openband/g3/sleep_parts.dart' as g3sleep;
import 'package:openstrap_edge/openband/g3/screens/band.dart';
import 'package:openstrap_edge/openband/g3/screens/sleep.dart';
import 'package:openstrap_edge/openband/g3/screens/sleep_night.dart';
import 'package:openstrap_edge/openband/g3/screens/training_live.dart';
import 'package:openstrap_edge/openband/g3/screens/training_manual.dart';
import 'package:openstrap_edge/openband/g3/screens/training_screen.dart';
import 'package:openstrap_edge/openband/g3/screens/verlauf.dart';
import 'package:openstrap_edge/openband/health.dart';
import 'package:openstrap_edge/openband/night_scalar_detail.dart';
import 'package:openstrap_edge/openband/night_signals.dart';
import 'package:openstrap_edge/openband/screens.dart';
import 'package:openstrap_edge/openband/settings_controls.dart';
import 'package:openstrap_edge/openband/sleep_editor.dart';
import 'package:openstrap_edge/openband/sleep_goal.dart';
import 'package:openstrap_edge/openband/sleep_plan.dart';
import 'package:openstrap_edge/openband/strength_live.dart';
import 'package:openstrap_edge/openband/template_editor.dart';
import 'package:openstrap_edge/openband/vo2.dart';
import 'package:openstrap_edge/openband/weight.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/theme/theme_controller.dart';
import 'package:openstrap_edge/state/units_controller.dart';
import 'package:openstrap_edge/ui2/app_shell.dart';
import 'package:openstrap_edge/ui2/grammar.dart' show Pressable;
import 'package:openstrap_edge/openband/g3/metrics.dart' as g3metrics;
import 'package:openstrap_edge/ui2/onboarding/welcome.dart';
import 'package:openstrap_edge/ui2/onboarding/pairing.dart';
import 'package:openstrap_edge/ui2/onboarding/first_sync.dart';
import 'package:openstrap_edge/ui2/pairing/device_picker.dart';
import 'package:openstrap_edge/ui2/profile/alarm.dart';
import 'package:openstrap_edge/ui2/profile/gestures.dart';
import 'package:provider/provider.dart';

part 'fixtures.dart';
part 'all.dart';
part 'journal.dart';
part 'vo2.dart';
part 'weight.dart';
part 'naps.dart';
part 'sleep_plan.dart';
part 'exercise_picker.dart';
part 'custom_exercise.dart';
part 'exercise_copy.dart';
part 'custom_load.dart';
part 'night_scalar.dart';
part 'sleep_legend.dart';
part 'night_cards.dart';
part 'respiration.dart';
part 'temperature.dart';
part 'release.dart';
part 'correction.dart';
part 'sleep_goal.dart';
part 'training_templates.dart';
part 'strength_live.dart';
part 'gestures.dart';
part 'night.dart';
part 'alarm.dart';
part 'first_sync.dart';
part 'notifications.dart';
part 'appearance.dart';
part 'units.dart';

const kOpenBandReviewFlow = String.fromEnvironment(
  'OPENBAND_REVIEW_FLOW',
  defaultValue: 'all',
);

const kOpenBandReviewCaptures = String.fromEnvironment(
  'OPENBAND_REVIEW_CAPTURES',
);

Set<String>? reviewCaptureFilter(String raw) {
  if (raw.isEmpty) return null;
  final names = <String>{
    for (final part in raw.split(','))
      if (part.trim().isNotEmpty) part.trim(),
  };
  if (names.isEmpty) {
    throw StateError(
      'OPENBAND_REVIEW_CAPTURES is empty; refusing a false-success run.',
    );
  }
  return names;
}

void reviewEnsureRequestedCaptures(
  Set<String>? filter,
  Iterable<String> captured,
) {
  if (filter == null) return;
  final missing = filter.difference({...captured});
  if (missing.isNotEmpty) {
    throw StateError(
      'Requested captures were not taken: ${missing.join(', ')}',
    );
  }
}

class ReviewHarness {
  ReviewHarness({
    required this.tester,
    required this.binding,
    required this.flow,
    required Set<String>? captureFilter,
    required this.capturedNames,
    required this.frames,
  }) : _captureFilter = captureFilter;

  final WidgetTester tester;

  /// Null when the flow runs headless under `flutter test`, which captures
  /// nothing (its capture filter is empty).
  final IntegrationTestWidgetsFlutterBinding? binding;

  /// The OPENBAND_REVIEW_FLOW name this run was dispatched as.
  final String flow;
  final Set<String>? _captureFilter;
  final Set<String> capturedNames;
  final List<Map<String, Object?>> frames;

  Finder verticalScrollable() => find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable && widget.axisDirection == AxisDirection.down,
  );

  Future<void> press(String text) => tap(find.text(text));

  Future<void> reveal(Finder target) async {
    if (target.evaluate().isEmpty) {
      final scrollable = verticalScrollable().last;
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(position.minScrollExtent);
      await tester.pumpAndSettle();
      for (var step = 0; step < 50 && target.evaluate().isEmpty; step++) {
        await tester.drag(scrollable, const Offset(0, -200));
        await tester.pump(const Duration(milliseconds: 50));
        // Lazy FutureBuilders can subscribe to cached Zone.root futures.
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }
    }
    await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
    await tester.pumpAndSettle();
  }

  Future<void> tap(Finder target) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await reveal(target);
    await tester.tap(target.hitTestable());
    await tester.pumpAndSettle();
  }

  Future<void> pressSleepEditor() =>
      tap(find.widgetWithText(g3chrome.OBLink, 'Zeiten ändern'));

  Future<SyntheticOpenBandRepository> mount({
    SyntheticScenario scenario = SyntheticScenario.complete,
    Brightness brightness = Brightness.light,
    double? scale,
    bool release = false,
    bool failRead = false,
    bool showControls = false,
  }) async {
    final repository = await loadRepository();
    repository.scenario = scenario;
    repository.failDayRead = failRead;
    await tester.pumpWidget(
      OpenBandGallery(
        key: UniqueKey(),
        repository: repository,
        showControls: showControls,
        initialBrightness: brightness,
        initialTextScale: scale,
        releaseReduced: release,
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  Future<Map> fixture(String name) async => (await tester.runAsync(
    () async =>
        jsonDecode(
              await rootBundle.loadString(
                'docs/openband5/assets/fixtures/$name.json',
              ),
            )
            as Map,
  ))!;

  Future<SyntheticOpenBandRepository> loadRepository() async =>
      (await tester.runAsync(loadGalleryRepository))!;

  Future<void> openSleep() async {
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.button == true &&
            (widget.child is Pressable ||
                widget.properties.label?.contains(', Tab,') == true) &&
            RegExp(
              r'^Schlaf(?:, Tab, 2 von 4)?$',
            ).hasMatch(widget.properties.label ?? ''),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('g3-sleep')), findsOneWidget);
  }

  Future<void> pop() async {
    final back = find.byType(BackButton);
    if (back.evaluate().isNotEmpty) {
      await tester.tap(back);
    } else {
      await tester
          .element(find.byType(Scaffold).first)
          .findAncestorStateOfType<NavigatorState>()
          ?.maybePop();
    }
    await tester.pumpAndSettle();
  }

  Future<void> capture(String name) async {
    final captureFilter = _captureFilter;
    expect(tester.takeException(), isNull);
    // Finish routes without pumpAndSettle (hangs on repeating indicators)
    // and without ModalRoute.of, which registers inherited dependents.
    await reviewPumpPageTransitions(tester);
    await reviewPumpPresentedFrame(tester);
    if (captureFilter != null && !captureFilter.contains(name)) {
      return;
    }
    final binding = this.binding!;
    const port = int.fromEnvironment('OPENBAND_REVIEW_PORT');
    if (port == 0) {
      await binding.takeScreenshot(name);
    } else {
      final client = HttpClient();
      try {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:$port/capture/$name'),
        );
        final response = await request.close();
        await response.drain<void>();
        if (response.statusCode != 200) {
          throw StateError('Native display capture failed: $name');
        }
      } finally {
        client.close(force: true);
      }
    }
    capturedNames.add(name);
    binding.reportData ??= <String, dynamic>{};
    final view = tester.view;
    frames.add({
      'name': name,
      'synthetic': true,
      'logicalWidth': view.physicalSize.width / view.devicePixelRatio,
      'logicalHeight': view.physicalSize.height / view.devicePixelRatio,
      'devicePixelRatio': view.devicePixelRatio,
      'keyboardInset': view.viewInsets.bottom / view.devicePixelRatio,
      'captureKind': port == 0 ? 'flutter-surface' : 'simulator-display',
      'semantics': binding.renderViews
          .map(
            (renderView) => renderView.owner?.semanticsOwner?.rootSemanticsNode
                ?.toStringDeep(),
          )
          .whereType<String>()
          .join('\n'),
    });
    binding.reportData!['frames'] = frames;
  }

  Future<void> settleJournalHub(SyntheticOpenBandRepository repository) async {
    await tester.pump();
    var pending = repository.caffeineSleepPatternPending;
    var frames = 0;
    while (pending == null && frames < 60) {
      await tester.pump();
      pending = repository.caffeineSleepPatternPending;
      frames++;
    }
    final inFlight = pending;
    if (inFlight != null) {
      await tester.runAsync(() async {
        try {
          await inFlight;
        } on StateError catch (error) {
          if (error.message != 'synthetic caffeine sleep pattern failure') {
            rethrow;
          }
        }
      });
    }
    await tester.pumpAndSettle();
  }

  Future<void> openHubEditor() =>
      tap(find.byKey(const ValueKey('journal-edit')));

  Future<void> edit({String variant = '', bool captureEntry = false}) async {
    await openSleep();
    await pressSleepEditor();
    await tester.pumpAndSettle();
    if (captureEntry) await capture('correction-entry$variant');
    await tester.enterText(find.byKey(const ValueKey('sleep-onset')), '23:25');
    await tester.pumpAndSettle();
    await capture('correction-keyboard$variant');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('sleep-onset')))
          .controller
          ?.text,
      '23:25',
    );
  }
}
