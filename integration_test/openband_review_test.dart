import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/gestures/device_action.dart';
import 'package:openstrap_edge/l10n/app_localizations.dart';
import 'package:openstrap_edge/main_gallery.dart';
import 'package:openstrap_edge/notify/notification_prefs.dart';
import 'package:openstrap_edge/openband/appearance.dart';
import 'package:openstrap_edge/openband/units.dart';
import 'package:openstrap_edge/openband/notification_settings.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/meal_entry.dart';
import 'package:openstrap_edge/openband/nutrition.dart';
import 'package:openstrap_edge/openband/strength_live.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/theme/theme_controller.dart';
import 'package:openstrap_edge/state/units_controller.dart';
import 'package:openstrap_edge/ui2/app_shell.dart';
import 'package:openstrap_edge/ui2/profile/alarm.dart';
import 'package:openstrap_edge/ui2/profile/gestures.dart';
import 'package:provider/provider.dart';

bool reviewRouteAnimating(Animation<double>? animation) =>
    animation != null && animation.isAnimating;

bool reviewTransitionUnsettled(
  Animation<double> primary,
  Animation<double> secondary,
) {
  if (reviewRouteAnimating(primary) || reviewRouteAnimating(secondary)) {
    return true;
  }
  // dismissed + value 0 is not isAnimating, but Cupertino still paints
  // _kRightMiddleTween at Offset(1,0) — a fully shifted-off page.
  // Secondary 1 is a settled covered route (parallax parked at -1/3).
  if (primary.value < 1.0) return true;
  return secondary.value > 0.0 && secondary.value < 1.0;
}

bool reviewPageTransitionRunning(WidgetTester tester) {
  for (final element in find.byType(CupertinoPageTransition).evaluate()) {
    final widget = element.widget as CupertinoPageTransition;
    if (reviewTransitionUnsettled(
      widget.primaryRouteAnimation,
      widget.secondaryRouteAnimation,
    )) {
      return true;
    }
  }
  for (final element
      in find.byType(CupertinoFullscreenDialogTransition).evaluate()) {
    final widget = element.widget as CupertinoFullscreenDialogTransition;
    if (reviewTransitionUnsettled(
      widget.primaryRouteAnimation,
      widget.secondaryRouteAnimation,
    )) {
      return true;
    }
  }
  return false;
}

Future<void> reviewPumpPageTransitions(WidgetTester tester) async {
  await tester.pump();
  var pumped = 0;
  while (reviewPageTransitionRunning(tester)) {
    await tester.pump(const Duration(milliseconds: 16));
    if (++pumped > 60) {
      throw FlutterError(
        'Page transition did not complete after $pumped pumped frames.',
      );
    }
  }
}

bool reviewTimingContainsFrame(
  List<FrameTiming> timings,
  int? targetFrameNumber,
) {
  if (targetFrameNumber == null) return false;
  for (final timing in timings) {
    if (timing.frameNumber == targetFrameNumber) return true;
  }
  return false;
}

Future<void> reviewPumpPresentedFrame(WidgetTester tester) async {
  if (tester.binding is! LiveTestWidgetsFlutterBinding) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    return;
  }

  int? targetFrameNumber;
  final rastered = Completer<void>();
  late final TimingsCallback listener;
  listener = (List<FrameTiming> timings) {
    if (reviewTimingContainsFrame(timings, targetFrameNumber) &&
        !rastered.isCompleted) {
      rastered.complete();
    }
  };

  tester.binding.addTimingsCallback(listener);
  tester.binding.addPostFrameCallback((_) {
    // hooks.dart updates frameData after begin-frame callbacks.
    targetFrameNumber = tester.binding.platformDispatcher.frameData.frameNumber;
  });
  try {
    await tester.pump();
    if (targetFrameNumber == null) {
      throw FlutterError(
        'Post-frame callback did not record a target frame number.',
      );
    }
    await rastered.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw FlutterError(
        'Timed out waiting for FrameTiming of frame $targetFrameNumber.',
      ),
    );
  } finally {
    tester.binding.removeTimingsCallback(listener);
  }
}

class _NutritionReviewRepo extends SyntheticOpenBandRepository {
  int commits = 0;
  int draftReads = 0;
  int restores = 0;
  bool failDraftRead = false;
  bool failDayRead = false;

  _NutritionReviewRepo(
    super.summary,
    super.detail, {
    super.activity,
    super.run,
  }) : super.fromMaps();

  @override
  Future<OpenBandDay> readDay(String day) {
    if (failDayRead) {
      return Future.error(StateError('synthetic day read failure'));
    }
    return super.readDay(day);
  }

  @override
  Future<MealDraft?> readMealDraft(String day, String meal) async {
    draftReads++;
    if (failDraftRead) {
      throw StateError('synthetic meal draft read failure');
    }
    return super.readMealDraft(day, meal);
  }

  @override
  Future<MealDraftCommitResult> commitMealDraft(MealDraft draft) async {
    commits++;
    return super.commitMealDraft(draft);
  }

  @override
  Future<FoodSnapshotResult> restoreFoodEntry(FoodEntry snapshot) async {
    restores++;
    return super.restoreFoodEntry(snapshot);
  }
}

Future<_NutritionReviewRepo> _loadNutritionReviewRepo() async {
  Future<Map> load(String name) async =>
      jsonDecode(
            await rootBundle.loadString(
              'docs/openband5/assets/fixtures/$name.json',
            ),
          )
          as Map;
  final repo = _NutritionReviewRepo(
    await load('day-summary'),
    await load('sleep-detail'),
    activity: await load('additional-flows'),
    run: await load('run-detail'),
  );
  await repo.seedNutritionGoals();
  return repo;
}

const kOpenBandReviewFlow = String.fromEnvironment(
  'OPENBAND_REVIEW_FLOW',
  defaultValue: 'all',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final frames = <Map<String, Object?>>[];

  testWidgets('native first-flow visual review with isolated synthetic data', (
    tester,
  ) async {
    if (kOpenBandReviewFlow != 'all' &&
        kOpenBandReviewFlow != 'journal' &&
        kOpenBandReviewFlow != 'journal-hub' &&
        kOpenBandReviewFlow != 'nutrition-entry') {
      throw StateError(
        'Unknown OPENBAND_REVIEW_FLOW: $kOpenBandReviewFlow '
        '(expected all, journal, journal-hub, or nutrition-entry)',
      );
    }
    await initializeDateFormatting('de_DE');
    final semantics = tester.ensureSemantics();
    final previousHitTestPolicy = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    try {
      Finder verticalScrollable() => find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      );

      Future<void> press(String text) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        final target = find.text(text);
        if (target.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            target,
            200,
            scrollable: verticalScrollable().last,
          );
        } else {
          await tester.ensureVisible(target);
        }
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      Future<void> pressSleepEditor() async {
        final target = find.byTooltip('Schlafzeiten ändern');
        await tester.scrollUntilVisible(
          target,
          200,
          scrollable: verticalScrollable().last,
        );
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      Future<SyntheticOpenBandRepository> mount({
        SyntheticScenario scenario = SyntheticScenario.complete,
        Brightness brightness = Brightness.light,
        double? scale,
      }) async {
        final repository = await loadGalleryRepository();
        repository.scenario = scenario;
        await tester.pumpWidget(
          OpenBandGallery(
            key: UniqueKey(),
            repository: repository,
            showControls: false,
            initialBrightness: brightness,
            initialTextScale: scale,
          ),
        );
        await tester.pumpAndSettle();
        return repository;
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
        expect(tester.takeException(), isNull);
        // Finish routes without pumpAndSettle (hangs on repeating indicators)
        // and without ModalRoute.of, which registers inherited dependents.
        await reviewPumpPageTransitions(tester);
        await reviewPumpPresentedFrame(tester);
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
                (renderView) => renderView
                    .owner
                    ?.semanticsOwner
                    ?.rootSemanticsNode
                    ?.toStringDeep(),
              )
              .whereType<String>()
              .join('\n'),
        });
        binding.reportData!['frames'] = frames;
      }

      Future<void> reviewJournal() async {
        Future<void> settleJournalHub(
          SyntheticOpenBandRepository repository,
        ) async {
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
                if (error.message !=
                    'synthetic caffeine sleep pattern failure') {
                  rethrow;
                }
              }
            });
          }
          await tester.pumpAndSettle();
        }

        Future<void> openHubEditor() async {
          final edit = find.byKey(const ValueKey('journal-edit'));
          await tester.ensureVisible(edit);
          await tester.pumpAndSettle();
          await tester.tap(edit);
          await tester.pumpAndSettle();
        }

        Future<void> openHubNutrition() async {
          final journal = find.byKey(const PageStorageKey('openband.journal'));
          final nutrition = find.descendant(
            of: journal,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  widget.properties.button == true &&
                  widget.properties.label == 'Ernährung',
            ),
          );
          final journalScroll = find.descendant(
            of: journal,
            matching: find.byType(Scrollable),
          );
          if (nutrition.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              nutrition,
              200,
              scrollable: journalScroll,
            );
          }
          await Scrollable.ensureVisible(
            tester.element(nutrition),
            alignment: 0.5,
          );
          await tester.pumpAndSettle();
          await tester.tap(nutrition);
          await tester.pumpAndSettle();
        }

        Finder journalHub() =>
            find.byKey(const PageStorageKey('openband.journal'));

        Finder inJournalHub(Finder matching) =>
            find.descendant(of: journalHub(), matching: matching);

        Finder journalHubScrollable() => find.descendant(
          of: journalHub(),
          matching: find.byType(Scrollable),
        );

        Future<void> tapJournalHubRetry() async {
          final retry = inJournalHub(find.text('Erneut'));
          if (retry.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              retry,
              200,
              scrollable: journalHubScrollable(),
            );
          }
          await Scrollable.ensureVisible(tester.element(retry), alignment: 0.5);
          await tester.pumpAndSettle();
          await tester.tap(retry);
        }

        bool isFullyVisibleInJournalHub(Finder matching) {
          final target = inJournalHub(matching);
          if (target.evaluate().length != 1) return false;
          if (target.hitTestable().evaluate().isEmpty) return false;
          final box = tester.getRect(target);
          final view = tester.getRect(journalHub());
          const slop = 0.5;
          return box.top >= view.top - slop &&
              box.bottom <= view.bottom + slop &&
              box.left >= view.left - slop &&
              box.right <= view.right + slop;
        }

        Future<void> revealJournalHubPatternCard(Finder lastLine) async {
          final heading = find.text('Einschlafen · Koffein nach 14 Uhr');
          final end = inJournalHub(lastLine);
          if (end.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              end,
              200,
              scrollable: journalHubScrollable(),
            );
          }
          var drags = 0;
          while (drags < 50 &&
              !(isFullyVisibleInJournalHub(heading) &&
                  isFullyVisibleInJournalHub(lastLine))) {
            final view = tester.getRect(journalHub());
            if (end.evaluate().isEmpty) {
              await tester.drag(journalHubScrollable(), const Offset(0, -200));
            } else {
              final endBox = tester.getRect(end);
              final headingBox = inJournalHub(heading).evaluate().isEmpty
                  ? null
                  : tester.getRect(inJournalHub(heading));
              final Offset delta;
              if (endBox.bottom > view.bottom + 0.5) {
                delta = const Offset(0, -80);
              } else if (headingBox != null &&
                  headingBox.top < view.top - 0.5) {
                delta = const Offset(0, 80);
              } else if (endBox.top < view.top - 0.5) {
                delta = const Offset(0, 80);
              } else if (!isFullyVisibleInJournalHub(lastLine)) {
                delta = const Offset(0, -80);
              } else if (!isFullyVisibleInJournalHub(heading)) {
                delta = const Offset(0, 80);
              } else {
                break;
              }
              await tester.drag(journalHubScrollable(), delta);
            }
            await tester.pumpAndSettle();
            drags++;
          }
          expect(isFullyVisibleInJournalHub(heading), isTrue);
          expect(isFullyVisibleInJournalHub(lastLine), isTrue);
        }

        Future<void> revealJournalHubPattern() async {
          await revealJournalHubPatternCard(find.text('Nein · 11 Nächte'));
        }

        Future<void> revealJournalHubHeader() async {
          final edit = inJournalHub(find.byKey(const ValueKey('journal-edit')));
          if (edit.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              edit,
              -200,
              scrollable: journalHubScrollable(),
            );
          }
          await Scrollable.ensureVisible(tester.element(edit), alignment: 0);
          await tester.pumpAndSettle();
        }

        Future<void> openJournalHubInfo() async {
          final info = inJournalHub(find.byTooltip('Information'));
          if (info.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              info,
              200,
              scrollable: journalHubScrollable(),
            );
          }
          await Scrollable.ensureVisible(tester.element(info), alignment: 0.5);
          await tester.pumpAndSettle();
          await tester.tap(info);
          await tester.pumpAndSettle();
        }

        Future<SyntheticOpenBandRepository> openJournalHub({
          Brightness brightness = Brightness.light,
          double? scale,
          SyntheticCaffeineSleepSeed patternSeed =
              SyntheticCaffeineSleepSeed.paperMeaningful,
          bool failPattern = false,
          bool failJournalRead = false,
          bool failMeals = false,
          bool failTargets = false,
          bool filledAnswers = false,
        }) async {
          final repository = await mount(brightness: brightness, scale: scale);
          repository.seedCaffeineSleepPattern('2026-09-15', seed: patternSeed);
          if (filledAnswers) {
            await repository.writeJournal('2026-09-15', 'mood', 4);
            await repository.writeJournal('2026-09-15', 'caffeine_late', 1);
            await repository.writeJournal('2026-09-15', 'alcohol_evening', 0);
            await repository.writeJournal('2026-09-15', 'read_before_bed', 1);
          }
          repository.failCaffeineSleepPattern = failPattern;
          repository.failJournalRead = failJournalRead;
          repository.failMealsRead = failMeals;
          repository.failNutritionTargetRead = failTargets;
          await press('Journal');
          await settleJournalHub(repository);
          return repository;
        }

        Future<void> reviewJournalHubInfo2x({
          Brightness brightness = Brightness.light,
          String suffix = '',
        }) async {
          await openJournalHub(brightness: brightness, scale: 2);
          await openJournalHubInfo();
          final title = find.text('Vergleich verstehen');
          final close = find.byTooltip('Schließen');
          final footer = find.text('Schließen');
          expect(title, findsOneWidget);
          expect(title.hitTestable(), findsOneWidget);
          expect(close.hitTestable(), findsOneWidget);
          expect(footer.hitTestable(), findsOneWidget);
          await capture('journal-hub-info-2x$suffix');
          final titleRect = tester.getRect(title);
          final closeRect = tester.getRect(close);
          final causality = find.textContaining('belegt keine Ursache');
          final footerButton = find.widgetWithText(FilledButton, 'Schließen');
          bool causalityFullyInBody() {
            if (causality.evaluate().length != 1) return false;
            if (footerButton.evaluate().length != 1) return false;
            final box = tester.getRect(causality);
            final footerBox = tester.getRect(footerButton);
            final headerBottom =
                tester.getRect(title).bottom > tester.getRect(close).bottom
                ? tester.getRect(title).bottom
                : tester.getRect(close).bottom;
            const slop = 0.5;
            return box.top >= headerBottom - slop &&
                box.bottom <= footerBox.top + slop;
          }

          if (causality.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              causality,
              80,
              scrollable: verticalScrollable().last,
            );
          }
          var drags = 0;
          while (!causalityFullyInBody() && drags < 50) {
            await tester.drag(verticalScrollable().last, const Offset(0, -80));
            await tester.pumpAndSettle();
            drags++;
          }
          expect(causalityFullyInBody(), isTrue);
          expect(causality.hitTestable(), findsOneWidget);
          expect(title.hitTestable(), findsOneWidget);
          expect(tester.getRect(title), titleRect);
          expect(close.hitTestable(), findsOneWidget);
          expect(tester.getRect(close), closeRect);
          expect(footer.hitTestable(), findsOneWidget);
          expect(footerButton.hitTestable(), findsOneWidget);
          await capture('journal-hub-info-2x-scrolled$suffix');
          await tester.tap(find.text('Schließen').last);
          await tester.pumpAndSettle();
        }

        void expectMeaningfulPattern() {
          expect(inJournalHub(find.text('+12 Min.')), findsOneWidget);
          expect(inJournalHub(find.text('Ja · 7 Nächte')), findsOneWidget);
          expect(inJournalHub(find.text('Nein · 11 Nächte')), findsOneWidget);
          expect(inJournalHub(find.textContaining('≥')), findsNothing);
          expect(inJournalHub(find.textContaining('mind.')), findsNothing);
        }

        void expectMeaningfulPatternVisible() {
          expectMeaningfulPattern();
          expect(
            isFullyVisibleInJournalHub(
              find.text('Einschlafen · Koffein nach 14 Uhr'),
            ),
            isTrue,
          );
          expect(isFullyVisibleInJournalHub(find.text('+12 Min.')), isTrue);
          expect(
            isFullyVisibleInJournalHub(find.text('Ja · 7 Nächte')),
            isTrue,
          );
          expect(
            isFullyVisibleInJournalHub(find.text('Nein · 11 Nächte')),
            isTrue,
          );
        }

        bool hubSelected(String label) =>
            tester
                .getSemantics(find.bySemanticsLabel(label))
                .flagsCollection
                .isSelected
                .toBoolOrNull() ==
            true;

        final hub = await openJournalHub();
        expect(
          inJournalHub(find.text('Einschlafen · Koffein nach 14 Uhr')),
          findsOneWidget,
        );
        expectMeaningfulPattern();
        expect(inJournalHub(find.text('620')), findsOneWidget);
        expect(hubSelected('Stimmung Gut'), isFalse);
        expect(hubSelected('Koffein nach 14 Uhr: Nein'), isFalse);
        expect(hubSelected('Alkohol: Nein'), isFalse);
        expect(hubSelected('Abends gelesen: Nein'), isFalse);
        await capture('journal-hub');
        await revealJournalHubPattern();
        expectMeaningfulPatternVisible();
        await capture('journal-hub-scrolled');
        await openJournalHubInfo();
        expect(find.text('Vergleich verstehen'), findsOneWidget);
        expect(find.textContaining('belegt keine Ursache'), findsOneWidget);
        expect(
          find.textContaining('17. August–15. September · 18 Nächte'),
          findsOneWidget,
        );
        await capture('journal-hub-info');
        await tester.tap(find.text('Schließen').last);
        await tester.pumpAndSettle();
        await revealJournalHubHeader();
        await tester.tap(find.bySemanticsLabel('Stimmung Gut'));
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel('Koffein nach 14 Uhr: Ja'));
        await settleJournalHub(hub);
        await tester.tap(find.bySemanticsLabel('Alkohol: Nein'));
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel('Abends gelesen: Ja'));
        await tester.pumpAndSettle();
        expect(hubSelected('Stimmung Gut'), isTrue);
        expect(hubSelected('Koffein nach 14 Uhr: Ja'), isTrue);
        expect(hubSelected('Alkohol: Nein'), isTrue);
        expect(hubSelected('Abends gelesen: Ja'), isTrue);
        expectMeaningfulPattern();
        await capture('journal-answered');
        if (kOpenBandReviewFlow != 'journal-hub') {
          await openHubEditor();
          await capture('journal-editor');
          await tester.tap(find.byTooltip('Information'));
          await tester.pumpAndSettle();
          await capture('journal-info');
          await tester.tap(find.text('Schließen').last);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Eigene Felder'));
          await tester.tap(find.text('Eigene Felder'));
          await tester.pumpAndSettle();
          await capture('journal-fields');
          await tester.tap(find.text('Feld hinzufügen'));
          await tester.pumpAndSettle();
          await capture('journal-field-create');
          await pop();
          await pop();
          await tester.tap(find.byTooltip('Zurück'));
          await tester.pumpAndSettle();
          await openHubNutrition();
          await capture('nutrition-day');
          await tester.tap(find.byTooltip('Frühstück ergänzen'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField).first, 'hafer');
          await tester.pumpAndSettle();
          await capture('food-search');
          await tester.tap(find.text('Haferflocken'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Übernehmen'));
          await tester.pumpAndSettle();
          await capture('meal-draft-preview');
          await tester.tap(find.text('Entwurf behalten'));
          await tester.pumpAndSettle();

          Future<SyntheticOpenBandRepository> openGoals({
            Brightness brightness = Brightness.light,
            double? scale,
          }) async {
            final repository = await mount(
              brightness: brightness,
              scale: scale,
            );
            await press('Journal');
            await settleJournalHub(repository);
            await openHubNutrition();
            await tester.tap(find.byTooltip('Ernährungsziele').hitTestable());
            await tester.pumpAndSettle();
            return repository;
          }

          Future<void> openGoalInfo() async {
            await tester.tap(find.byTooltip('Ernährungsziele').hitTestable());
            await tester.pumpAndSettle();
          }

          Future<void> closeGoalInfo() async {
            await tester.tap(find.text('Schließen').last);
            await tester.pumpAndSettle();
          }

          Future<void> settleGoalKeyboard() async {
            FocusManager.instance.primaryFocus?.unfocus();
            await tester.pumpAndSettle();
          }

          await tester.tap(find.byTooltip('Ernährungsziele').hitTestable());
          await tester.pumpAndSettle();
          await capture('nutrition-goals-overview');
          await openGoalInfo();
          await capture('nutrition-goals-info');
          await closeGoalInfo();
          await tester.tap(find.text('Ändern'));
          await tester.pumpAndSettle();
          expect(find.text('2000'), findsWidgets);
          await capture('nutrition-goals-editor');
          await tester.tap(find.text('%'));
          await tester.pumpAndSettle();
          expect(find.text('25'), findsOneWidget);
          await capture('nutrition-goals-percent');
          await tester.tap(find.text('g'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Gültig ab'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('20'));
          await tester.pumpAndSettle();
          await capture('nutrition-goals-date');
          await tester.ensureVisible(find.textContaining('übernehmen'));
          await tester.tap(find.textContaining('übernehmen'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(const ValueKey('nutrition-goal-save')),
          );
          await tester.tap(find.byKey(const ValueKey('nutrition-goal-save')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Verlauf'));
          await tester.pumpAndSettle();
          expect(find.text('Geplant'), findsOneWidget);
          await capture('nutrition-goals-history');
          await pop();
          await tester.tap(find.text('Ziele entfernen'));
          await tester.pumpAndSettle();
          await capture('nutrition-goals-clear');
          await tester.tap(find.text('Entfernen'));
          await tester.pumpAndSettle();
          expect(find.text('Keine Ziele'), findsOneWidget);
          await capture('nutrition-goals-cleared');
          await tester.tap(find.text('Verlauf'));
          await tester.pumpAndSettle();
          expect(find.text('Geplant'), findsOneWidget);
          await capture('nutrition-goals-history-retained');
          await pop();
          await pop();

          final goalFail = await mount();
          goalFail.failNutritionTargetRead = true;
          await press('Journal');
          await settleJournalHub(goalFail);
          await openHubNutrition();
          await tester.tap(find.byTooltip('Ernährungsziele').hitTestable());
          await tester.pumpAndSettle();
          expect(find.text('Ziele nicht geladen'), findsOneWidget);
          await capture('nutrition-goals-read-error');
          goalFail.failNutritionTargetRead = false;
          await tester.tap(find.text('Erneut'));
          await tester.pumpAndSettle();
          expect(find.text('Ziele nicht geladen'), findsNothing);
          await capture('nutrition-goals-read-retry');

          final goalWrite = await openGoals();
          await tester.tap(find.text('Ändern'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('nutrition-goal-energy')),
            '1550',
          );
          await tester.pumpAndSettle();
          await settleGoalKeyboard();
          await tester.ensureVisible(
            find.byKey(const ValueKey('nutrition-goal-save')),
          );
          goalWrite.failNutritionTargetWrite = true;
          await tester.tap(find.byKey(const ValueKey('nutrition-goal-save')));
          await tester.pumpAndSettle();
          expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
          await capture('nutrition-goals-write-error');
          goalWrite.failNutritionTargetWrite = false;
          await tester.ensureVisible(find.text('Erneut speichern'));
          await tester.tap(find.text('Erneut speichern'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Ändern'));
          await tester.pumpAndSettle();
          expect(find.text('1550'), findsWidgets);
          await capture('nutrition-goals-write-retry');

          final goalConflict = await openGoals();
          await tester.tap(find.text('Ändern'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('nutrition-goal-energy')),
            '1600',
          );
          await tester.pumpAndSettle();
          await settleGoalKeyboard();
          await tester.ensureVisible(
            find.byKey(const ValueKey('nutrition-goal-save')),
          );
          await goalConflict.saveNutritionTargets(
            '2026-09-15',
            const NutritionTargetValues(energyKcal: 1700),
            expectedRevision: 1,
          );
          await tester.tap(find.byKey(const ValueKey('nutrition-goal-save')));
          await tester.pumpAndSettle();
          expect(
            find.text('Ziele wurden inzwischen geändert.'),
            findsOneWidget,
          );
          await capture('nutrition-goals-conflict');

          final goalClearConflict = await openGoals();
          await goalClearConflict.saveNutritionTargets(
            '2026-09-15',
            const NutritionTargetValues(energyKcal: 1700),
            expectedRevision: 1,
          );
          await tester.tap(find.text('Ziele entfernen'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Entfernen'));
          await tester.pumpAndSettle();
          expect(find.text('Ziele inzwischen geändert.'), findsOneWidget);
          expect(find.text('2.000'), findsOneWidget);
          expect(find.text('Gültig ab'), findsNothing);
          await capture('nutrition-goals-clear-conflict');
          await tester.tap(find.text('Neu laden'));
          await tester.pumpAndSettle();
          expect(find.text('Ziele inzwischen geändert.'), findsNothing);
          expect(find.text('1.700'), findsOneWidget);

          final goalClearConflictDark = await openGoals(
            brightness: Brightness.dark,
          );
          await goalClearConflictDark.saveNutritionTargets(
            '2026-09-15',
            const NutritionTargetValues(energyKcal: 1700),
            expectedRevision: 1,
          );
          await tester.tap(find.text('Ziele entfernen'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Entfernen'));
          await tester.pumpAndSettle();
          expect(find.text('Ziele inzwischen geändert.'), findsOneWidget);
          await capture('nutrition-goals-clear-conflict-dark');

          final goalClearFail = await openGoals();
          goalClearFail.failNutritionTargetWrite = true;
          await tester.tap(find.text('Ziele entfernen'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Entfernen'));
          await tester.pumpAndSettle();
          expect(find.text('Entfernen fehlgeschlagen.'), findsOneWidget);
          expect(find.text('2.000'), findsOneWidget);
          expect(find.text('Gültig ab'), findsNothing);
          await capture('nutrition-goals-clear-error');
          goalClearFail.failNutritionTargetWrite = false;
          await tester.tap(find.text('Erneut'));
          await tester.pumpAndSettle();
          expect(find.text('Ziele entfernen?'), findsOneWidget);
          await capture('nutrition-goals-clear-retry');
          await tester.tap(find.text('Entfernen'));
          await tester.pumpAndSettle();
          expect(find.text('Keine Ziele'), findsOneWidget);

          final goalClearFailDark = await openGoals(
            brightness: Brightness.dark,
          );
          goalClearFailDark.failNutritionTargetWrite = true;
          await tester.tap(find.text('Ziele entfernen'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Entfernen'));
          await tester.pumpAndSettle();
          expect(find.text('Entfernen fehlgeschlagen.'), findsOneWidget);
          await capture('nutrition-goals-clear-error-dark');

          final missingGoals = await mount();
          await missingGoals.clearNutritionTargets(
            '2026-09-15',
            expectedRevision: 1,
          );
          await missingGoals.clearNutritionTargets(
            '2026-09-20',
            expectedRevision: 1,
          );
          await press('Journal');
          await settleJournalHub(missingGoals);
          await openHubNutrition();
          await tester.tap(find.byTooltip('Ernährungsziele').hitTestable());
          await tester.pumpAndSettle();
          expect(find.text('Keine Ziele'), findsOneWidget);
          await capture('nutrition-goals-empty');

          await openGoals(brightness: Brightness.dark);
          await capture('nutrition-goals-overview-dark');
          await openGoalInfo();
          await capture('nutrition-goals-info-dark');
          await closeGoalInfo();
          await tester.tap(find.text('Ändern'));
          await tester.pumpAndSettle();
          await capture('nutrition-goals-editor-dark');
          await tester.tap(find.text('%'));
          await tester.pumpAndSettle();
          expect(find.text('25'), findsOneWidget);
          await capture('nutrition-goals-percent-dark');

          await openGoals(scale: 2);
          await openGoalInfo();
          expect(find.text('Ernährungs-\nziele'), findsWidgets);
          await capture('nutrition-goals-info-large');
          await closeGoalInfo();
          await tester.ensureVisible(find.text('Ändern'));
          await tester.tap(find.text('Ändern'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await capture('nutrition-goals-editor-large');
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('nutrition-goal-fat')),
            200,
            scrollable: verticalScrollable().last,
          );
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('nutrition-goal-save')),
            200,
            scrollable: verticalScrollable().last,
          );
          expect(
            find.byKey(const ValueKey('nutrition-goal-save')).hitTestable(),
            findsOneWidget,
          );
          await capture('nutrition-goals-editor-large-scrolled');

          await openJournalHub(failJournalRead: true);
          await openHubEditor();
          await capture('journal-editor-load-error');

          await openJournalHub(brightness: Brightness.dark);
          await openHubEditor();
          await capture('journal-editor-dark');
          await tester.tap(find.byTooltip('Information'));
          await tester.pumpAndSettle();
          await capture('journal-info-dark');
          await tester.tap(find.text('Schließen').last);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Eigene Felder'));
          await tester.tap(find.text('Eigene Felder'));
          await tester.pumpAndSettle();
          await capture('journal-fields-dark');

          await openJournalHub(scale: 2);
          await openHubEditor();
          expect(find.text('Ausgeblendet'), findsNothing);
          await capture('journal-editor-large');
          await tester.tap(find.byTooltip('Information'));
          await tester.pumpAndSettle();
          await capture('journal-info-large');
          await tester.tap(find.text('Schließen').last);
          await tester.pumpAndSettle();

          Future<SyntheticOpenBandRepository> openJournalEditor({
            bool filled = false,
            bool withCustom = false,
            Brightness brightness = Brightness.light,
            double? scale,
          }) async {
            final repository = await mount(
              brightness: brightness,
              scale: scale,
            );
            if (filled || withCustom) {
              repository.seedJournalEditor(
                filled: filled,
                withCustom: withCustom,
              );
            }
            await press('Journal');
            await settleJournalHub(repository);
            await openHubEditor();
            return repository;
          }

          await openJournalEditor();
          await capture('journal-editor-empty');

          final filledJournal = await openJournalEditor(
            filled: true,
            withCustom: true,
          );
          await tester.tap(find.text('Schlafqualität'));
          await tester.pumpAndSettle();
          await capture('journal-editor-rating');
          await tester.tap(find.text('Übernehmen'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Koffein').last);
          await tester.tap(find.text('Koffein').last);
          await tester.pumpAndSettle();
          await capture('journal-editor-value');
          await tester.enterText(
            find.byKey(const ValueKey('journal-value')),
            '180',
          );
          await tester.tap(find.text('10:30'));
          await tester.pumpAndSettle();
          await capture('journal-editor-time');
          await tester.tap(find.text('OK'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Übernehmen'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Tags'));
          await tester.tap(find.text('Tags'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.descendant(
              of: find.byKey(const ValueKey('journal-tags-sheet')),
              matching: find.text('Koffein'),
            ),
          );
          await tester.pump();
          await capture('journal-editor-tags');
          await tester.tap(find.byKey(const ValueKey('journal-tag-custom')));
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(const ValueKey('journal-tag-custom')),
          );
          await capture('journal-editor-tags-keyboard');
          await tester.enterText(
            find.byKey(const ValueKey('journal-tag-custom')),
            'Yoga',
          );
          await tester.ensureVisible(find.byTooltip('Tag hinzufügen'));
          await tester.tap(find.byTooltip('Tag hinzufügen'));
          await tester.pump();
          await capture('journal-editor-tags-custom');
          expect(
            find
                .descendant(
                  of: find.byKey(const ValueKey('journal-tags-sheet')),
                  matching: find.text('Tags'),
                )
                .hitTestable(),
            findsOneWidget,
          );
          expect(
            find
                .descendant(
                  of: find.byKey(const ValueKey('journal-tags-sheet')),
                  matching: find.byTooltip('Schließen'),
                )
                .hitTestable(),
            findsOneWidget,
          );
          expect(
            find.widgetWithText(FilledButton, 'Übernehmen').hitTestable(),
            findsOneWidget,
          );
          await tester.ensureVisible(find.text('Übernehmen'));
          await tester.tap(find.text('Übernehmen'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.bySemanticsLabel('Stimmung Sehr gut'),
          );
          await tester.tap(find.bySemanticsLabel('Stimmung Sehr gut'));
          await tester.pump();
          await tester.ensureVisible(find.text('Eigene Felder'));
          await tester.tap(find.text('Eigene Felder'));
          await tester.pumpAndSettle();
          await capture('journal-fields-from-draft');
          await tester.tap(find.byTooltip('Zurück'));
          await tester.pumpAndSettle();
          await capture('journal-editor-after-fields');
          filledJournal.failJournalPatch = true;
          await tester.tap(find.byKey(const ValueKey('journal-save')));
          await tester.pumpAndSettle();
          await capture('journal-editor-save-error');
          filledJournal.failJournalPatch = false;
          await tester.tap(find.byKey(const ValueKey('journal-save')));
          await tester.pumpAndSettle();
          await openHubEditor();
          await capture('journal-editor-reopened');
          await tester.tap(find.byTooltip('Zurück'));
          await tester.pumpAndSettle();

          final conflictJournal = await openJournalEditor(filled: true);
          await tester.tap(find.bySemanticsLabel('Stimmung Sehr gut'));
          await tester.pump();
          final conflictBase = await conflictJournal.readJournalDay(
            '2026-09-15',
          );
          await conflictJournal.patchJournalDay(
            JournalDayPatch.fromBase(
              conflictBase,
              metrics: const {'mood': JournalMetricValue(2)},
            ),
          );
          await tester.tap(find.byKey(const ValueKey('journal-save')));
          await tester.pumpAndSettle();
          await capture('journal-editor-conflict');
          await tester.tap(find.text('Neu laden'));
          await tester.pumpAndSettle();
          await capture('journal-discard');
          await tester.tap(find.text('Verwerfen und neu laden'));
          await tester.pumpAndSettle();
          await capture('journal-editor-reloaded');
          await tester.tap(find.byTooltip('Zurück'));
          await tester.pumpAndSettle();

          await openJournalEditor(withCustom: true);
          await tester.ensureVisible(find.text('Eigene Felder'));
          await tester.tap(find.text('Eigene Felder'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Feld hinzufügen'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Menge'));
          await tester.pumpAndSettle();
          await capture('journal-field-type');
          await tester.tap(find.text('Dauer'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('journal-field-name')),
            'Dehnung',
          );
          await tester.tap(find.text('Speichern').first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Magnesium').first);
          await tester.pumpAndSettle();
          await capture('journal-field-detail');
          await tester.tap(find.text('Ausblenden'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Ausgeblendet'));
          await tester.pumpAndSettle();
          await capture('journal-fields-hidden');
          await tester.tap(find.text('Magnesium'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Einblenden'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Zurück'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Zurück'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Zurück'));
          await tester.pumpAndSettle();

          final fieldsFail = await openJournalEditor();
          fieldsFail.failJournalFieldsList = true;
          await tester.ensureVisible(find.text('Eigene Felder'));
          await tester.tap(find.text('Eigene Felder'));
          await tester.pumpAndSettle();
          await capture('journal-fields-load-error');
          fieldsFail.failJournalFieldsList = false;
          await tester.tap(find.text('Erneut'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Feld hinzufügen'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('journal-field-name')),
            'Omega',
          );
          fieldsFail.failJournalFieldsList = true;
          await tester.tap(find.text('Speichern').first);
          await tester.pumpAndSettle();
          await capture('journal-field-create-retry');
          fieldsFail.failJournalFieldsList = false;
          await tester.tap(find.text('Erneut'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Zurück'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Zurück'));
          await tester.pumpAndSettle();

          await openJournalEditor(filled: true, scale: 2);
          await tester.ensureVisible(
            find.byKey(const ValueKey('journal-note')),
          );
          await tester.tap(find.byKey(const ValueKey('journal-note')));
          await tester.pumpAndSettle();
          await capture('journal-editor-keyboard');
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Tags'));
          await tester.pumpAndSettle();
          await capture('journal-editor-scrolled');
          await tester.tap(find.byTooltip('Zurück'));
          await tester.pumpAndSettle();
          if (find.text('Änderungen verwerfen?').evaluate().isNotEmpty) {
            await tester.tap(find.text('Weiter bearbeiten'));
            await tester.pumpAndSettle();
            await tester.tap(find.byTooltip('Zurück'));
            await tester.pumpAndSettle();
            if (find.text('Änderungen verwerfen?').evaluate().isNotEmpty) {
              await tester.tap(find.text('Verwerfen'));
              await tester.pumpAndSettle();
            }
          }

          await openJournalEditor(
            filled: true,
            scale: 2,
            brightness: Brightness.dark,
          );
          await tester.ensureVisible(find.text('Tags'));
          await tester.pumpAndSettle();
          await capture('journal-editor-scrolled-dark');
          await tester.tap(find.byTooltip('Zurück'));
          await tester.pumpAndSettle();
        }

        await openJournalHub(brightness: Brightness.dark);
        expectMeaningfulPattern();
        expect(inJournalHub(find.text('620')), findsOneWidget);
        expect(hubSelected('Alkohol: Nein'), isFalse);
        await capture('journal-hub-dark');
        await revealJournalHubPattern();
        expectMeaningfulPatternVisible();
        await capture('journal-hub-scrolled-dark');

        await openJournalHub(scale: 2);
        expect(inJournalHub(find.text('Journal')), findsOneWidget);
        expect(inJournalHub(find.text('620')), findsOneWidget);
        await capture('journal-hub-2x');
        await revealJournalHubPattern();
        expectMeaningfulPatternVisible();
        await capture('journal-hub-2x-scrolled');

        await openJournalHub(brightness: Brightness.dark, scale: 2);
        expect(inJournalHub(find.text('Journal')), findsOneWidget);
        expect(inJournalHub(find.text('620')), findsOneWidget);
        await capture('journal-hub-2x-dark');
        await revealJournalHubPattern();
        expectMeaningfulPatternVisible();
        await capture('journal-hub-2x-scrolled-dark');

        await reviewJournalHubInfo2x();
        await reviewJournalHubInfo2x(
          brightness: Brightness.dark,
          suffix: '-dark',
        );

        await openJournalHub(
          patternSeed: SyntheticCaffeineSleepSeed.insufficient,
        );
        expect(
          inJournalHub(find.text('Noch zu wenige Nächte')),
          findsOneWidget,
        );
        expect(inJournalHub(find.text('5 Nächte mit Eintrag')), findsOneWidget);
        expect(inJournalHub(find.text('+12 Min.')), findsNothing);
        expect(inJournalHub(find.textContaining('≥')), findsNothing);
        await revealJournalHubPatternCard(find.text('5 Nächte mit Eintrag'));
        expect(
          isFullyVisibleInJournalHub(find.text('Noch zu wenige Nächte')),
          isTrue,
        );
        expect(
          isFullyVisibleInJournalHub(find.text('5 Nächte mit Eintrag')),
          isTrue,
        );
        await capture('journal-hub-insufficient');

        await openJournalHub(
          brightness: Brightness.dark,
          patternSeed: SyntheticCaffeineSleepSeed.insufficient,
        );
        expect(
          inJournalHub(find.text('Noch zu wenige Nächte')),
          findsOneWidget,
        );
        expect(inJournalHub(find.text('5 Nächte mit Eintrag')), findsOneWidget);
        expect(inJournalHub(find.text('+12 Min.')), findsNothing);
        expect(inJournalHub(find.textContaining('≥')), findsNothing);
        await revealJournalHubPatternCard(find.text('5 Nächte mit Eintrag'));
        expect(
          isFullyVisibleInJournalHub(find.text('Noch zu wenige Nächte')),
          isTrue,
        );
        expect(
          isFullyVisibleInJournalHub(find.text('5 Nächte mit Eintrag')),
          isTrue,
        );
        await capture('journal-hub-insufficient-dark');

        await openJournalHub(
          patternSeed: SyntheticCaffeineSleepSeed.unavailable,
        );
        expect(inJournalHub(find.text('Noch kein Vergleich')), findsOneWidget);
        expect(
          inJournalHub(find.text('Keine auswertbaren Nächte mit Eintrag')),
          findsOneWidget,
        );
        expect(inJournalHub(find.text('Nein · 11 Nächte')), findsNothing);
        await revealJournalHubPatternCard(
          find.text('Keine auswertbaren Nächte mit Eintrag'),
        );
        expect(
          isFullyVisibleInJournalHub(find.text('Noch kein Vergleich')),
          isTrue,
        );
        expect(
          isFullyVisibleInJournalHub(
            find.text('Keine auswertbaren Nächte mit Eintrag'),
          ),
          isTrue,
        );
        await capture('journal-hub-unavailable');

        await openJournalHub(
          brightness: Brightness.dark,
          patternSeed: SyntheticCaffeineSleepSeed.unavailable,
        );
        expect(inJournalHub(find.text('Noch kein Vergleich')), findsOneWidget);
        expect(
          inJournalHub(find.text('Keine auswertbaren Nächte mit Eintrag')),
          findsOneWidget,
        );
        expect(inJournalHub(find.text('Nein · 11 Nächte')), findsNothing);
        await revealJournalHubPatternCard(
          find.text('Keine auswertbaren Nächte mit Eintrag'),
        );
        expect(
          isFullyVisibleInJournalHub(find.text('Noch kein Vergleich')),
          isTrue,
        );
        expect(
          isFullyVisibleInJournalHub(
            find.text('Keine auswertbaren Nächte mit Eintrag'),
          ),
          isTrue,
        );
        await capture('journal-hub-unavailable-dark');

        await openJournalHub(
          patternSeed: SyntheticCaffeineSleepSeed.nonmeaningful,
        );
        expect(inJournalHub(find.text('Kein klares Muster')), findsOneWidget);
        expect(
          inJournalHub(find.text('18 Nächte mit Eintrag')),
          findsOneWidget,
        );
        expect(inJournalHub(find.text('+12 Min.')), findsNothing);
        await revealJournalHubPatternCard(find.text('18 Nächte mit Eintrag'));
        expect(
          isFullyVisibleInJournalHub(find.text('Kein klares Muster')),
          isTrue,
        );
        expect(
          isFullyVisibleInJournalHub(find.text('18 Nächte mit Eintrag')),
          isTrue,
        );
        await capture('journal-hub-nonmeaningful');

        await openJournalHub(
          brightness: Brightness.dark,
          patternSeed: SyntheticCaffeineSleepSeed.nonmeaningful,
        );
        expect(inJournalHub(find.text('Kein klares Muster')), findsOneWidget);
        expect(
          inJournalHub(find.text('18 Nächte mit Eintrag')),
          findsOneWidget,
        );
        expect(inJournalHub(find.text('+12 Min.')), findsNothing);
        await revealJournalHubPatternCard(find.text('18 Nächte mit Eintrag'));
        expect(
          isFullyVisibleInJournalHub(find.text('Kein klares Muster')),
          isTrue,
        );
        expect(
          isFullyVisibleInJournalHub(find.text('18 Nächte mit Eintrag')),
          isTrue,
        );
        await capture('journal-hub-nonmeaningful-dark');

        await openJournalHub(
          patternSeed: SyntheticCaffeineSleepSeed.partialMeaningful,
        );
        expectMeaningfulPattern();
        expect(inJournalHub(find.text('Teilweise auswertbar')), findsOneWidget);
        await revealJournalHubPatternCard(find.text('Teilweise auswertbar'));
        expectMeaningfulPatternVisible();
        expect(
          isFullyVisibleInJournalHub(find.text('Teilweise auswertbar')),
          isTrue,
        );
        await capture('journal-hub-partial');

        await openJournalHub(
          brightness: Brightness.dark,
          patternSeed: SyntheticCaffeineSleepSeed.partialMeaningful,
        );
        expectMeaningfulPattern();
        expect(inJournalHub(find.text('Teilweise auswertbar')), findsOneWidget);
        await revealJournalHubPatternCard(find.text('Teilweise auswertbar'));
        expectMeaningfulPatternVisible();
        expect(
          isFullyVisibleInJournalHub(find.text('Teilweise auswertbar')),
          isTrue,
        );
        await capture('journal-hub-partial-dark');

        final patternFail = await openJournalHub(failPattern: true);
        expect(
          inJournalHub(find.text('Vergleich konnte nicht geladen werden.')),
          findsOneWidget,
        );
        expect(inJournalHub(find.text('Erneut')), findsOneWidget);
        await revealJournalHubPatternCard(find.text('Erneut'));
        expect(
          isFullyVisibleInJournalHub(
            find.text('Vergleich konnte nicht geladen werden.'),
          ),
          isTrue,
        );
        expect(isFullyVisibleInJournalHub(find.text('Erneut')), isTrue);
        await capture('journal-hub-pattern-error');
        patternFail.failCaffeineSleepPattern = false;
        await tapJournalHubRetry();
        await tester.pump();
        await settleJournalHub(patternFail);
        await revealJournalHubPattern();
        expectMeaningfulPatternVisible();
        await capture('journal-hub-pattern-retry');

        final patternFailDark = await openJournalHub(
          brightness: Brightness.dark,
          failPattern: true,
        );
        expect(
          inJournalHub(find.text('Vergleich konnte nicht geladen werden.')),
          findsOneWidget,
        );
        expect(inJournalHub(find.text('Erneut')), findsOneWidget);
        await revealJournalHubPatternCard(find.text('Erneut'));
        expect(
          isFullyVisibleInJournalHub(
            find.text('Vergleich konnte nicht geladen werden.'),
          ),
          isTrue,
        );
        expect(isFullyVisibleInJournalHub(find.text('Erneut')), isTrue);
        await capture('journal-hub-pattern-error-dark');
        patternFailDark.failCaffeineSleepPattern = false;
        await tapJournalHubRetry();
        await tester.pump();
        await settleJournalHub(patternFailDark);
        await revealJournalHubPattern();
        expectMeaningfulPatternVisible();
        await capture('journal-hub-pattern-retry-dark');

        final writeFail = await openJournalHub(filledAnswers: true);
        expect(hubSelected('Stimmung Gut'), isTrue);
        expect(hubSelected('Alkohol: Nein'), isTrue);
        writeFail.failJournalPatch = true;
        await tester.tap(find.bySemanticsLabel('Alkohol: Ja'));
        await tester.pumpAndSettle();
        expect(
          inJournalHub(find.text('Speichern fehlgeschlagen.')),
          findsOneWidget,
        );
        expect(hubSelected('Alkohol: Nein'), isTrue);
        expect(hubSelected('Alkohol: Ja'), isFalse);
        await capture('journal-hub-write-error');
        writeFail.failJournalPatch = false;
        await tester.tap(find.bySemanticsLabel('Alkohol: Ja'));
        await tester.pumpAndSettle();
        expect(
          inJournalHub(find.text('Speichern fehlgeschlagen.')),
          findsNothing,
        );
        expect(hubSelected('Alkohol: Ja'), isTrue);
        await capture('journal-hub-write-retry');

        final writeFailDark = await openJournalHub(
          brightness: Brightness.dark,
          filledAnswers: true,
        );
        expect(hubSelected('Stimmung Gut'), isTrue);
        expect(hubSelected('Alkohol: Nein'), isTrue);
        writeFailDark.failJournalPatch = true;
        await tester.tap(find.bySemanticsLabel('Alkohol: Ja'));
        await tester.pumpAndSettle();
        expect(
          inJournalHub(find.text('Speichern fehlgeschlagen.')),
          findsOneWidget,
        );
        expect(hubSelected('Alkohol: Nein'), isTrue);
        expect(hubSelected('Alkohol: Ja'), isFalse);
        await capture('journal-hub-write-error-dark');
        writeFailDark.failJournalPatch = false;
        await tester.tap(find.bySemanticsLabel('Alkohol: Ja'));
        await tester.pumpAndSettle();
        expect(
          inJournalHub(find.text('Speichern fehlgeschlagen.')),
          findsNothing,
        );
        expect(hubSelected('Alkohol: Ja'), isTrue);
        await capture('journal-hub-write-retry-dark');

        final conflictHub = await openJournalHub(filledAnswers: true);
        await conflictHub.writeJournal('2026-09-15', 'mood', 2);
        await tester.tap(find.bySemanticsLabel('Stimmung Okay'));
        await tester.pumpAndSettle();
        expect(
          inJournalHub(find.text('Antwort inzwischen geändert.')),
          findsOneWidget,
        );
        expect(inJournalHub(find.text('Neu laden')), findsOneWidget);
        expect(hubSelected('Stimmung Gut'), isTrue);
        await capture('journal-hub-conflict');
        await tester.tap(inJournalHub(find.text('Neu laden')));
        await settleJournalHub(conflictHub);
        expect(
          inJournalHub(find.text('Antwort inzwischen geändert.')),
          findsNothing,
        );
        expect(hubSelected('Stimmung Müde'), isTrue);
        await capture('journal-hub-conflict-reloaded');

        final conflictHubDark = await openJournalHub(
          brightness: Brightness.dark,
          filledAnswers: true,
        );
        await conflictHubDark.writeJournal('2026-09-15', 'mood', 2);
        await tester.tap(find.bySemanticsLabel('Stimmung Okay'));
        await tester.pumpAndSettle();
        expect(
          inJournalHub(find.text('Antwort inzwischen geändert.')),
          findsOneWidget,
        );
        expect(inJournalHub(find.text('Neu laden')), findsOneWidget);
        expect(hubSelected('Stimmung Gut'), isTrue);
        await capture('journal-hub-conflict-dark');
        await tester.tap(inJournalHub(find.text('Neu laden')));
        await settleJournalHub(conflictHubDark);
        expect(
          inJournalHub(find.text('Antwort inzwischen geändert.')),
          findsNothing,
        );
        expect(hubSelected('Stimmung Müde'), isTrue);
        await capture('journal-hub-conflict-reloaded-dark');

        final readFail = await openJournalHub(filledAnswers: true);
        readFail.failJournalRead = true;
        await tester.tap(find.bySemanticsLabel('Stimmung Okay'));
        await tester.pumpAndSettle();
        expect(
          inJournalHub(find.text('Speichern fehlgeschlagen.')),
          findsNothing,
        );
        expect(
          inJournalHub(find.text('Journal nicht geladen.')),
          findsOneWidget,
        );
        expect(hubSelected('Stimmung Okay'), isTrue);
        final disabledMood = find.bySemanticsLabel('Stimmung Gut');
        expect(disabledMood.hitTestable(), findsNothing);
        expect(
          find.ancestor(
            of: disabledMood,
            matching: find.byWidgetPredicate(
              (widget) => widget is IgnorePointer && widget.ignoring,
            ),
          ),
          findsOneWidget,
        );
        readFail.failJournalRead = false;
        final storedBefore = await readFail.readJournalDay('2026-09-15');
        readFail.failJournalRead = true;
        await tester.tapAt(tester.getCenter(disabledMood));
        await tester.pumpAndSettle();
        expect(hubSelected('Stimmung Okay'), isTrue);
        readFail.failJournalRead = false;
        final storedAfter = await readFail.readJournalDay('2026-09-15');
        readFail.failJournalRead = true;
        expect(
          storedAfter.metrics['mood']?.value,
          storedBefore.metrics['mood']?.value,
        );
        expect(
          storedAfter.metricUpdatedAt['mood'],
          storedBefore.metricUpdatedAt['mood'],
        );
        await capture('journal-hub-read-error');
        readFail.failJournalRead = false;
        await tapJournalHubRetry();
        await settleJournalHub(readFail);
        expect(inJournalHub(find.text('Journal nicht geladen.')), findsNothing);
        expect(hubSelected('Stimmung Okay'), isTrue);
        await capture('journal-hub-read-retry');

        final readFailDark = await openJournalHub(
          brightness: Brightness.dark,
          filledAnswers: true,
        );
        readFailDark.failJournalRead = true;
        await tester.tap(find.bySemanticsLabel('Stimmung Okay'));
        await tester.pumpAndSettle();
        expect(
          inJournalHub(find.text('Journal nicht geladen.')),
          findsOneWidget,
        );
        expect(hubSelected('Stimmung Okay'), isTrue);
        await capture('journal-hub-read-error-dark');
        readFailDark.failJournalRead = false;
        await tapJournalHubRetry();
        await settleJournalHub(readFailDark);
        expect(inJournalHub(find.text('Journal nicht geladen.')), findsNothing);
        expect(hubSelected('Stimmung Okay'), isTrue);
        await capture('journal-hub-read-retry-dark');

        final mealsFail = await openJournalHub(failMeals: true);
        expect(
          inJournalHub(find.text('Einträge konnten nicht geladen werden.')),
          findsOneWidget,
        );
        expect(inJournalHub(find.text('Erneut')), findsOneWidget);
        expect(inJournalHub(find.text('620')), findsNothing);
        expect(inJournalHub(find.text('kcal')), findsNothing);
        expect(inJournalHub(find.text('Ziel 2.000')), findsNothing);
        expect(inJournalHub(find.text('Kein Ziel')), findsNothing);
        await capture('journal-hub-meals-error');
        mealsFail.failMealsRead = false;
        await tapJournalHubRetry();
        await tester.pump();
        await settleJournalHub(mealsFail);
        expect(
          inJournalHub(find.text('Einträge konnten nicht geladen werden.')),
          findsNothing,
        );
        expect(inJournalHub(find.text('620')), findsOneWidget);
        expect(inJournalHub(find.text('Ziel 2.000')), findsOneWidget);
        await capture('journal-hub-meals-retry');

        final mealsFailDark = await openJournalHub(
          brightness: Brightness.dark,
          failMeals: true,
        );
        expect(
          inJournalHub(find.text('Einträge konnten nicht geladen werden.')),
          findsOneWidget,
        );
        expect(inJournalHub(find.text('Erneut')), findsOneWidget);
        expect(inJournalHub(find.text('620')), findsNothing);
        expect(inJournalHub(find.text('kcal')), findsNothing);
        expect(inJournalHub(find.text('Ziel 2.000')), findsNothing);
        expect(inJournalHub(find.text('Kein Ziel')), findsNothing);
        await capture('journal-hub-meals-error-dark');
        mealsFailDark.failMealsRead = false;
        await tapJournalHubRetry();
        await tester.pump();
        await settleJournalHub(mealsFailDark);
        expect(
          inJournalHub(find.text('Einträge konnten nicht geladen werden.')),
          findsNothing,
        );
        expect(inJournalHub(find.text('620')), findsOneWidget);
        expect(inJournalHub(find.text('Ziel 2.000')), findsOneWidget);
        await capture('journal-hub-meals-retry-dark');

        final targetsFail = await openJournalHub(failTargets: true);
        expect(
          inJournalHub(find.text('Ziele konnten nicht geladen werden.')),
          findsOneWidget,
        );
        expect(inJournalHub(find.text('Erneut')), findsOneWidget);
        expect(inJournalHub(find.text('620')), findsOneWidget);
        expect(inJournalHub(find.text('Ziel —')), findsOneWidget);
        expect(inJournalHub(find.text('Kein Ziel')), findsNothing);
        expect(inJournalHub(find.text('Ziel 2.000')), findsNothing);
        await capture('journal-hub-targets-error');
        targetsFail.failNutritionTargetRead = false;
        await tapJournalHubRetry();
        await tester.pump();
        await settleJournalHub(targetsFail);
        expect(
          inJournalHub(find.text('Ziele konnten nicht geladen werden.')),
          findsNothing,
        );
        expect(inJournalHub(find.text('620')), findsOneWidget);
        expect(inJournalHub(find.text('Ziel 2.000')), findsOneWidget);
        expect(inJournalHub(find.text('Ziel —')), findsNothing);
        expect(inJournalHub(find.text('Kein Ziel')), findsNothing);
        await capture('journal-hub-targets-retry');

        final targetsFailDark = await openJournalHub(
          brightness: Brightness.dark,
          failTargets: true,
        );
        expect(
          inJournalHub(find.text('Ziele konnten nicht geladen werden.')),
          findsOneWidget,
        );
        expect(inJournalHub(find.text('Erneut')), findsOneWidget);
        expect(inJournalHub(find.text('620')), findsOneWidget);
        expect(inJournalHub(find.text('Ziel —')), findsOneWidget);
        expect(inJournalHub(find.text('Kein Ziel')), findsNothing);
        expect(inJournalHub(find.text('Ziel 2.000')), findsNothing);
        await capture('journal-hub-targets-error-dark');
        targetsFailDark.failNutritionTargetRead = false;
        await tapJournalHubRetry();
        await tester.pump();
        await settleJournalHub(targetsFailDark);
        expect(
          inJournalHub(find.text('Ziele konnten nicht geladen werden.')),
          findsNothing,
        );
        expect(inJournalHub(find.text('620')), findsOneWidget);
        expect(inJournalHub(find.text('Ziel 2.000')), findsOneWidget);
        expect(inJournalHub(find.text('Ziel —')), findsNothing);
        expect(inJournalHub(find.text('Kein Ziel')), findsNothing);
        await capture('journal-hub-targets-retry-dark');
      }

      Future<void> reviewNutritionEntry() async {
        FoodEntryRouteResult? popped;
        final now = DateTime(2026, 9, 15, 9, 41);
        final knownAt = DateTime(2026, 9, 15, 8, 15, 42);
        final knownTs = knownAt.millisecondsSinceEpoch ~/ 1000;

        FoodEntry oats({
          String id = 'oats',
          String date = '2026-09-15',
          String meal = 'breakfast',
          String label = 'Haferflocken mit Milch',
          int? atTs,
          double? quantity,
          String unit = 'g',
          double? kcal = 380,
          double? proteinG = 18,
          double? carbsG = 56,
          double? fatG = 12,
          double? fibreG,
          double? sugarG,
          double? satFatG,
          double? sodiumMg,
          double? ironMg,
          double? calciumMg,
          FoodSource source = FoodSource.manual,
          String? sourceCode,
          bool confirmed = true,
          String note = '',
          int createdAt = 1000,
          int updatedAt = 1000,
        }) => FoodEntry(
          id: id,
          date: date,
          meal: meal,
          label: label,
          atTs: atTs,
          foodKey: 'oats',
          quantity: quantity,
          unit: unit,
          kcal: kcal,
          proteinG: proteinG,
          carbsG: carbsG,
          fatG: fatG,
          fibreG: fibreG,
          sugarG: sugarG,
          satFatG: satFatG,
          sodiumMg: sodiumMg,
          ironMg: ironMg,
          calciumMg: calciumMg,
          source: source,
          sourceCode: sourceCode ?? source.name,
          confirmed: confirmed,
          note: note,
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        Finder foodScrollable() => verticalScrollable().last;

        Future<SyntheticOpenBandRepository> openFoodEntry({
          String id = 'oats',
          String day = '2026-09-15',
          Brightness brightness = Brightness.light,
          double? scale,
          FoodEntry? seed,
          bool failRead = false,
        }) async {
          final repository = await loadGalleryRepository();
          repository.seedFoodEntry(seed ?? oats());
          repository.failFoodRead = failRead;
          popped = null;
          await tester.pumpWidget(
            MaterialApp(
              key: UniqueKey(),
              debugShowCheckedModeBanner: false,
              locale: const Locale('de'),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              theme: openBandTheme(
                brightness,
              ).copyWith(platform: TargetPlatform.iOS),
              themeAnimationDuration: Duration.zero,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale ?? 1)),
                child: child!,
              ),
              home: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    popped = await openOpenBandFoodEntry(
                      context,
                      repository: repository,
                      id: id,
                      day: day,
                      synthetic: true,
                      now: () => now,
                    );
                  },
                  child: const Text('open-food-entry'),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('open-food-entry'));
          await tester.pumpAndSettle();
          return repository;
        }

        Future<void> openEditor() async {
          final edit = find.byTooltip('Bearbeiten');
          expect(edit, findsOneWidget);
          await tester.tap(edit);
          await tester.pumpAndSettle();
          expect(find.text('Eintrag bearbeiten'), findsOneWidget);
        }

        Future<void> openLabeledPane(String label) async {
          final target = find.text(label);
          final scrollable = foodScrollable();
          if (target.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              target,
              80,
              scrollable: scrollable,
            );
          }
          var scrolls = 0;
          while (target.hitTestable().evaluate().isEmpty) {
            if (scrolls >= 24) {
              throw FlutterError(
                'Labeled control "$label" is not hit-testable in the food '
                'entry pane after scrolling.',
              );
            }
            if (target.evaluate().isEmpty) {
              await tester.scrollUntilVisible(
                target,
                80,
                scrollable: scrollable,
              );
            } else {
              final view = tester.getRect(scrollable);
              final box = tester.getRect(target);
              final delta = box.center.dy < view.center.dy ? 64.0 : -64.0;
              await tester.drag(scrollable, Offset(0, delta));
              await tester.pump();
            }
            scrolls++;
          }
          expect(target.hitTestable(), findsOneWidget);
          await tester.tap(target.hitTestable());
          await tester.pumpAndSettle();
        }

        Future<void> openTime() async {
          await openLabeledPane('Uhrzeit');
          expect(find.byKey(const ValueKey('food-time')), findsOneWidget);
          expect(find.byKey(const ValueKey('food-time-scroll')), findsOneWidget);
        }

        String timeFieldText() => tester
            .widget<TextField>(find.byKey(const ValueKey('food-time')))
            .controller!
            .text;

        double keyboardInset() =>
            tester.view.viewInsets.bottom / tester.view.devicePixelRatio;

        void expectPinned(Finder matching) {
          expect(matching.hitTestable(), findsOneWidget);
        }

        Finder enclosingPinnedControl(Finder matching) {
          if (matching.evaluate().single.widget is OBAction) return matching;
          final action = find.ancestor(
            of: matching,
            matching: find.byType(OBAction),
          );
          if (action.evaluate().isNotEmpty) {
            expect(action, findsOneWidget);
            return action;
          }
          final nested = find.descendant(
            of: matching,
            matching: find.byType(OBAction),
          );
          if (nested.evaluate().isNotEmpty) {
            expect(nested, findsOneWidget);
            return nested;
          }
          final button = find.ancestor(
            of: matching,
            matching: find.byWidgetPredicate(
              (widget) => widget is ButtonStyleButton || widget is IconButton,
            ),
          );
          expect(
            button,
            findsOneWidget,
            reason: 'Pinned control has no enclosing OBAction or button.',
          );
          return button;
        }

        void expectPinnedAboveKeyboard(Finder matching) {
          expect(matching.hitTestable(), findsOneWidget);
          final box = tester.getRect(enclosingPinnedControl(matching));
          final view = tester.view;
          final logicalHeight =
              view.physicalSize.height / view.devicePixelRatio;
          final keyboardTop = logicalHeight - keyboardInset();
          expect(box.bottom, lessThanOrEqualTo(keyboardTop + 0.5));
          expect(box.top, lessThan(keyboardTop));
        }

        void expectSheetHeaderBelowStatusBar(String title) {
          final safeTop =
              tester.view.padding.top / tester.view.devicePixelRatio;
          final close = find.byTooltip('Schließen');
          expect(close.hitTestable(), findsOneWidget);
          final headerRow = find.ancestor(
            of: close,
            matching: find.byType(Row),
          );
          expect(headerRow, findsOneWidget);
          final titleFinder = find.descendant(
            of: headerRow,
            matching: find.text(title),
          );
          expect(titleFinder, findsOneWidget);
          final titleBox = tester.getRect(titleFinder);
          expect(titleBox.top, greaterThanOrEqualTo(safeTop));
          expect(
            tester.getRect(close).top,
            greaterThanOrEqualTo(safeTop),
          );
        }

        Future<void> waitKeyboardInset({required bool open}) async {
          var last = keyboardInset();
          var stable = 0;
          var pumped = 0;
          while (pumped < 60) {
            await tester.pump(const Duration(milliseconds: 16));
            if (tester.binding is LiveTestWidgetsFlutterBinding) {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 16)),
              );
            }
            final inset = keyboardInset();
            final reached = open ? inset > 0 : inset == 0;
            if (reached && (inset - last).abs() < 0.5) {
              if (++stable >= 3) return;
            } else {
              stable = 0;
            }
            last = inset;
            pumped++;
          }
          throw FlutterError(
            open
                ? 'Keyboard inset did not become a stable positive value.'
                : 'Keyboard inset did not settle at zero.',
          );
        }

        Future<void> settleKeyboard(Finder field) async {
          await tester.tap(field);
          await tester.pump();
          await tester.showKeyboard(field);
          await tester.pump();
          await waitKeyboardInset(open: true);
        }

        Future<void> dismissKeyboard() async {
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();
          await waitKeyboardInset(open: false);
        }

        FoodEntry paperCoffee() => const FoodEntry(
          id: 'm2',
          date: '2026-09-15',
          meal: 'breakfast',
          label: 'Kaffee',
          source: FoodSource.unknown,
          sourceCode: 'unknown',
          confirmed: true,
          fibreG: 8.1,
          sodiumMg: 12,
          createdAt: 50,
          updatedAt: 50,
        );

        FoodEntry paperLentils() => oats(
          id: 'm3',
          meal: 'lunch',
          label: 'Linsensalat',
          kcal: 240,
          proteinG: 8,
          carbsG: 32,
          fatG: 3,
          createdAt: 3,
          updatedAt: 3,
        );

        void seedPaperFoods(_NutritionReviewRepo repository) {
          repository.seedFoodEntry(oats(id: 'm1', createdAt: 1, updatedAt: 1));
          repository.seedFoodEntry(paperCoffee());
          repository.seedFoodEntry(paperLentils());
        }

        MealDraft breakfastDraft() => MealDraft(
          id: 'd-breakfast',
          day: '2026-09-15',
          meal: 'breakfast',
          entries: const [
            MealDraftEntry(
              id: 'e-oats',
              label: 'Haferflocken mit Milch',
              kcal: 380,
            ),
            MealDraftEntry(
              id: 'e-coffee',
              label: 'Kaffee',
              source: FoodSource.unknown,
              sourceCode: 'unknown',
            ),
          ],
          updatedAt: DateTime(2026, 9, 15, 8),
        );

        Finder inFoodEntry(Finder matching) => find.descendant(
          of: find.byType(OpenBandFoodEntry),
          matching: matching,
        );

        Finder inDraft(Finder matching) => find.descendant(
          of: find.byType(OBMealDraftSheet),
          matching: matching,
        );

        Future<void> pumpShown() async {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
        }

        Future<void> tapSnackAction(String label) async {
          await tester.tap(find.widgetWithText(TextButton, label));
        }

        Future<OpenBandController> mountParent({
          required _NutritionReviewRepo repository,
          Brightness brightness = Brightness.light,
          double scale = 1,
          bool enableAdd = false,
          MealDraft? addDraft,
        }) async {
          final controller = OpenBandController(
            repository: repository,
            initialDay: '2026-09-15',
            band: repository.band,
            now: () => now,
          );
          await controller.refresh();
          await tester.pumpWidget(
            MaterialApp(
              key: UniqueKey(),
              debugShowCheckedModeBanner: false,
              locale: const Locale('de'),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              theme: openBandTheme(
                brightness,
              ).copyWith(platform: TargetPlatform.iOS),
              themeAnimationDuration: Duration.zero,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Builder(
                builder: (context) => OpenBandNutrition(
                  controller: controller,
                  onAdd: enableAdd
                      ? (meal) async {
                          final shown =
                              addDraft ??
                              await repository.readMealDraft(
                                '2026-09-15',
                                meal,
                              );
                          if (shown == null || !context.mounted) return;
                          await showOpenBandMealDraft(
                            context,
                            repository,
                            shown,
                          );
                        }
                      : null,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          return controller;
        }

        Future<void> removeRow(String label) async {
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          final remove = find.byKey(const ValueKey('food-entry-remove'));
          await tester.scrollUntilVisible(
            remove,
            80,
            scrollable: foodScrollable(),
          );
          expect(remove.hitTestable(), findsOneWidget);
          await tester.tap(remove);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('ob-confirm-yes')));
          await pumpShown();
        }

        final detail = await openFoodEntry();
        expect(find.text('Eintrag'), findsOneWidget);
        expect(find.text('15. September'), findsOneWidget);
        expect(find.text('Frühstück'), findsOneWidget);
        expect(find.text('Haferflocken mit Milch'), findsOneWidget);
        expect(find.text('380'), findsOneWidget);
        expect(find.text('18 g'), findsOneWidget);
        expect(find.text('12 g'), findsOneWidget);
        expect(find.text('56 g'), findsOneWidget);
        expect(find.text('Menge'), findsOneWidget);
        expect(find.text('Uhrzeit'), findsOneWidget);
        expect(find.text('Quelle'), findsOneWidget);
        expect(find.text('Manuell'), findsOneWidget);
        expect(find.text('—'), findsNWidgets(2));
        expect(find.text('Eintrag entfernen'), findsOneWidget);
        expect(find.byKey(const ValueKey('food-entry-remove')), findsOneWidget);
        expect((await detail.readFoodEntry('oats')).current!.sourceCode, 'manual');
        await capture('nutrition-entry');

        await openFoodEntry(brightness: Brightness.dark);
        expect(find.text('Eintrag'), findsOneWidget);
        expect(find.text('Haferflocken mit Milch'), findsOneWidget);
        await capture('nutrition-entry-dark');

        await openFoodEntry(
          seed: oats(
            source: FoodSource.unknown,
            sourceCode: 'vendor-x',
            kcal: 10,
          ),
        );
        expect(find.text('Unbekannt'), findsOneWidget);
        expect(find.text('Manuell'), findsNothing);
        expect(find.bySemanticsLabel('Quelle Unbekannt vendor-x'), findsOneWidget);
        expect(find.text('10'), findsOneWidget);
        await capture('nutrition-entry-unknown');

        await openFoodEntry(
          seed: oats(
            kcal: 0,
            proteinG: 0,
            fibreG: 8.1,
            sugarG: 0,
            quantity: 0,
          ),
        );
        expect(find.text('0'), findsOneWidget);
        expect(find.text('0 g'), findsWidgets);
        expect(find.text('380'), findsNothing);
        await capture('nutrition-entry-zero');

        var photo = await openFoodEntry(
          seed: oats(
            source: FoodSource.photo,
            confirmed: false,
            kcal: 500,
            proteinG: 20,
            carbsG: 40,
            fatG: 10,
          ),
        );
        expect(find.text('Foto · unbestätigt'), findsOneWidget);
        expect(find.text('Foto'), findsNothing);
        expect(find.text('Manuell'), findsNothing);
        expect(find.text('Werte bestätigen'), findsNothing);
        expect(find.text('500'), findsNothing);
        expect(find.text('20 g'), findsNothing);
        expect(find.text('40 g'), findsNothing);
        expect(find.text('10 g'), findsNothing);
        expect(find.text('—'), findsWidgets);
        await capture('nutrition-entry-photo');

        await openEditor();
        await openLabeledPane('Nährwerte');
        expect(find.text('Foto · unbestätigt'), findsOneWidget);
        expect(find.text('Werte bestätigen'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('food-nutrient-kcal')))
              .controller!
              .text,
          '500',
        );
        await capture('nutrition-entry-photo-nutrients');
        await tester.tap(find.text('Werte bestätigen'));
        await tester.pumpAndSettle();
        expect(find.text('Eintrag bearbeiten'), findsOneWidget);
        expect(find.byKey(const ValueKey('food-entry-save')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('food-entry-save')));
        await tester.pumpAndSettle();
        expect(find.text('Eintrag'), findsOneWidget);
        expect(find.text('500'), findsOneWidget);
        expect(find.text('20 g'), findsOneWidget);
        expect(find.text('Foto · unbestätigt'), findsNothing);
        expect(find.text('Foto'), findsOneWidget);
        final savedPhoto = (await photo.readFoodEntry('oats')).current!;
        expect(savedPhoto.confirmed, isTrue);
        expect(savedPhoto.kcal, 500);
        expect(savedPhoto.proteinG, 20);
        expect(savedPhoto.carbsG, 40);
        expect(savedPhoto.fatG, 10);
        expect(savedPhoto.source, FoodSource.photo);
        expect(savedPhoto.sourceCode, 'photo');
        await capture('nutrition-entry-photo-confirmed');

        await openFoodEntry(
          brightness: Brightness.dark,
          seed: oats(
            source: FoodSource.photo,
            confirmed: false,
            kcal: 500,
            proteinG: 20,
            carbsG: 40,
            fatG: 10,
          ),
        );
        await openEditor();
        await openLabeledPane('Nährwerte');
        expect(find.text('Foto · unbestätigt'), findsOneWidget);
        expect(find.text('Werte bestätigen'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(
                find.byKey(const ValueKey('food-nutrient-kcal')),
              )
              .controller!
              .text,
          '500',
        );
        await capture('nutrition-entry-photo-nutrients-dark');

        await openFoodEntry();
        await openEditor();
        expect(find.text('Lebensmittel'), findsOneWidget);
        expect(find.text('Mahlzeit'), findsOneWidget);
        expect(find.text('Menge'), findsOneWidget);
        expect(find.text('Uhrzeit'), findsOneWidget);
        expect(find.text('Nährwerte'), findsOneWidget);
        expect(find.text('Speichern'), findsOneWidget);
        expect(find.byKey(const ValueKey('food-entry-name')), findsOneWidget);
        expect(find.byKey(const ValueKey('food-entry-save')), findsOneWidget);
        await capture('nutrition-entry-editor');
        await openLabeledPane('Nährwerte');
        expect(find.text('Energie'), findsOneWidget);
        expect(find.text('Eiweiß'), findsOneWidget);
        expect(find.text('Kohlenhydrate'), findsOneWidget);
        expect(find.text('Fett'), findsOneWidget);
        expect(find.text('Ballaststoffe'), findsOneWidget);
        expect(find.text('Zucker'), findsOneWidget);
        expect(find.text('Gesättigte Fettsäuren'), findsOneWidget);
        expect(find.text('Natrium'), findsOneWidget);
        expect(find.text('Eisen'), findsOneWidget);
        expect(find.text('Calcium'), findsOneWidget);
        expect(find.byKey(const ValueKey('food-nutrient-kcal')), findsOneWidget);
        expect(find.byKey(const ValueKey('food-nutrient-proteinG')), findsOneWidget);
        expect(find.byKey(const ValueKey('food-nutrient-carbsG')), findsOneWidget);
        expect(find.byKey(const ValueKey('food-nutrient-fatG')), findsOneWidget);
        expect(find.byKey(const ValueKey('food-nutrient-fibreG')), findsOneWidget);
        expect(find.byKey(const ValueKey('food-nutrient-sugarG')), findsOneWidget);
        expect(find.byKey(const ValueKey('food-nutrient-satFatG')), findsOneWidget);
        expect(find.byKey(const ValueKey('food-nutrient-sodiumMg')), findsOneWidget);
        expect(find.byKey(const ValueKey('food-nutrient-ironMg')), findsOneWidget);
        expect(find.byKey(const ValueKey('food-nutrient-calciumMg')), findsOneWidget);
        expectPinned(find.text('Übernehmen'));
        await capture('nutrition-entry-nutrients');

        await openFoodEntry(brightness: Brightness.dark);
        await openEditor();
        await capture('nutrition-entry-editor-dark');
        await openLabeledPane('Nährwerte');
        expect(find.text('Energie'), findsOneWidget);
        expectPinned(find.text('Übernehmen'));
        await capture('nutrition-entry-nutrients-dark');

        await openFoodEntry(id: 'missing', seed: oats());
        expect(find.text('Eintrag nicht gefunden'), findsOneWidget);
        expect(find.text('Selbst eintragen'), findsNothing);
        await capture('nutrition-entry-missing');

        final readFail = await openFoodEntry(failRead: true);
        expect(find.text('Eintrag nicht geladen'), findsOneWidget);
        expect(find.text('Erneut versuchen'), findsOneWidget);
        await capture('nutrition-entry-read-error');
        readFail.failFoodRead = false;
        await tester.tap(find.text('Erneut versuchen'));
        await tester.pumpAndSettle();
        expect(find.text('Haferflocken mit Milch'), findsOneWidget);
        expect(find.text('Eintrag nicht geladen'), findsNothing);
        expect((await readFail.readFoodEntry('oats')).current!.label, 'Haferflocken mit Milch');
        await capture('nutrition-entry-read-retry');

        final saveFail = await openFoodEntry();
        await openEditor();
        await tester.enterText(
          find.byKey(const ValueKey('food-entry-name')),
          'Haferflocken mit Hafermilch',
        );
        await tester.pump();
        saveFail.failFoodWrite = true;
        await tester.tap(find.byKey(const ValueKey('food-entry-save')));
        await tester.pumpAndSettle();
        expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
        expect(find.text('Erneut versuchen'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('food-entry-name')))
              .controller!
              .text,
          'Haferflocken mit Hafermilch',
        );
        expect(
          (await saveFail.readFoodEntry('oats')).current!.label,
          'Haferflocken mit Milch',
        );
        await capture('nutrition-entry-save-failure');
        saveFail.failFoodWrite = false;
        await tester.tap(find.text('Erneut versuchen'));
        await tester.pumpAndSettle();
        expect(find.text('Eintrag bearbeiten'), findsNothing);
        expect(find.text('Haferflocken mit Hafermilch'), findsOneWidget);
        final retried = (await saveFail.readFoodEntry('oats')).current!;
        expect(retried.label, 'Haferflocken mit Hafermilch');
        expect(retried.sourceCode, 'manual');
        expect(retried.kcal, 380);
        await capture('nutrition-entry-save-retry');

        final conflictRepo = await openFoodEntry();
        final original = (await conflictRepo.readFoodEntry('oats')).current!;
        await openEditor();
        await tester.enterText(
          find.byKey(const ValueKey('food-entry-name')),
          'Haferflocken mit Hafermilch',
        );
        await tester.pump();
        expect(
          (await conflictRepo.saveFoodEntry(
            original,
            oats(kcal: 390, updatedAt: original.updatedAt ?? 1000),
          )).saved,
          isTrue,
        );
        await tester.tap(find.byKey(const ValueKey('food-entry-save')));
        await tester.pumpAndSettle();
        expect(find.text('Eintrag wurde geändert'), findsOneWidget);
        expect(find.text('Neu laden'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('food-entry-name')))
              .controller!
              .text,
          'Haferflocken mit Hafermilch',
        );
        await capture('nutrition-entry-conflict');
        await tester.tap(find.text('Neu laden'));
        await tester.pumpAndSettle();
        expect(find.text('Änderungen verwerfen?'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('ob-confirm-yes')));
        await tester.pumpAndSettle();
        expect(find.text('Eintrag'), findsOneWidget);
        expect(find.text('390'), findsOneWidget);
        expect(find.text('Haferflocken mit Milch'), findsOneWidget);
        expect(
          (await conflictRepo.readFoodEntry('oats')).current!.kcal,
          390,
        );
        await capture('nutrition-entry-conflict-reload');

        final quantityRepo = await openFoodEntry(seed: oats(quantity: 150));
        await openEditor();
        expect(find.text('150 g'), findsOneWidget);
        await openLabeledPane('Menge');
        expect(find.byKey(const ValueKey('food-qty-amount')), findsOneWidget);
        expect(find.byKey(const ValueKey('food-qty-unit')), findsOneWidget);
        expect(find.byKey(const ValueKey('food-qty-scale')), findsOneWidget);
        expect(find.text('Nährwerte anpassen'), findsOneWidget);
        expect(find.text('Menge entfernen'), findsOneWidget);
        expect(find.byTooltip('Schließen'), findsOneWidget);
        expect(find.text('Übernehmen'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('food-qty-amount')),
          '75',
        );
        await tester.pump();
        await tester.tap(find.text('Nährwerte anpassen'));
        await tester.pump();
        await dismissKeyboard();
        expect(find.text('Menge entfernen').hitTestable(), findsOneWidget);
        expect(find.byTooltip('Schließen').hitTestable(), findsOneWidget);
        await capture('nutrition-entry-quantity');
        await tester.tap(find.text('Übernehmen'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('food-entry-save')));
        await tester.pumpAndSettle();
        final scaled = (await quantityRepo.readFoodEntry('oats')).current!;
        expect(scaled.quantity, 75);
        expect(scaled.unit, 'g');
        expect(scaled.kcal, 190);
        expect(scaled.proteinG, 9);
        expect(scaled.carbsG, 28);
        expect(scaled.fatG, 6);

        await openFoodEntry();
        await openEditor();
        await openLabeledPane('Menge');
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('food-qty-amount')))
              .controller!
              .text,
          '',
        );
        expect(find.byKey(const ValueKey('food-qty-scale')), findsNothing);
        expect(find.text('Nährwerte anpassen'), findsNothing);
        expect(find.text('Menge entfernen'), findsNothing);
        expect(find.byTooltip('Schließen'), findsOneWidget);
        await dismissKeyboard();
        await capture('nutrition-entry-quantity-unknown');

        await openFoodEntry(
          brightness: Brightness.dark,
          seed: oats(quantity: 150),
        );
        await openEditor();
        await openLabeledPane('Menge');
        expect(find.byKey(const ValueKey('food-qty-amount')), findsOneWidget);
        expect(find.text('Nährwerte anpassen'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('food-qty-amount')),
          '75',
        );
        await tester.pump();
        await tester.tap(find.text('Nährwerte anpassen'));
        await tester.pump();
        await dismissKeyboard();
        expect(find.text('Menge entfernen').hitTestable(), findsOneWidget);
        await capture('nutrition-entry-quantity-dark');

        final timeRepo = await openFoodEntry(seed: oats(atTs: knownTs));
        await openEditor();
        expect(find.text('08:15'), findsOneWidget);
        await openTime();
        expect(timeFieldText(), '08:15');
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('food-time')))
              .decoration!
              .hintText,
          'HH:mm',
        );
        expect(find.text('12:00'), findsNothing);
        expect(find.text('Uhrzeit entfernen'), findsOneWidget);
        expect(find.byTooltip('Schließen'), findsOneWidget);
        expect(find.text('Übernehmen'), findsOneWidget);
        expect(find.text('15. September'), findsWidgets);
        await dismissKeyboard();
        await capture('nutrition-entry-time');
        expect((await timeRepo.readFoodEntry('oats')).current!.atTs, knownTs);
        await tester.tap(find.text('Übernehmen'));
        await tester.pumpAndSettle();
        expect(find.text('Eintrag bearbeiten'), findsOneWidget);
        expect(find.text('08:15'), findsOneWidget);
        expect((await timeRepo.readFoodEntry('oats')).current!.atTs, knownTs);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('food-entry-note')),
          80,
          scrollable: foodScrollable(),
        );
        await tester.enterText(
          find.byKey(const ValueKey('food-entry-note')),
          'zeit unverändert',
        );
        await tester.pump();
        await waitKeyboardInset(open: true);
        expectPinnedAboveKeyboard(find.byKey(const ValueKey('food-entry-save')));
        await tester.tap(find.byKey(const ValueKey('food-entry-save')));
        await tester.pumpAndSettle();
        final savedTime = (await timeRepo.readFoodEntry('oats')).current!;
        expect(savedTime.date, '2026-09-15');
        expect(savedTime.note, 'zeit unverändert');
        final persisted = DateTime.fromMillisecondsSinceEpoch(
          savedTime.atTs! * 1000,
        ).toLocal();
        expect(persisted.year, 2026);
        expect(persisted.month, 9);
        expect(persisted.day, 15);
        expect(persisted.hour, 8);
        expect(persisted.minute, 15);
        expect(persisted.second, 42);
        expect(savedTime.atTs, knownTs);

        await openEditor();
        await openTime();
        expect(timeFieldText(), '08:15');
        expect(find.text('Uhrzeit entfernen'), findsOneWidget);
        await tester.tap(find.text('Uhrzeit entfernen'));
        await tester.pumpAndSettle();
        expect((await timeRepo.readFoodEntry('oats')).current!.atTs, isNotNull);
        await tester.tap(find.byKey(const ValueKey('food-entry-save')));
        await tester.pumpAndSettle();
        final cleared = (await timeRepo.readFoodEntry('oats')).current!;
        expect(cleared.atTs, isNull);
        expect(cleared.date, '2026-09-15');

        await openFoodEntry();
        await openEditor();
        await openTime();
        expect(timeFieldText(), '');
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('food-time')))
              .decoration!
              .hintText,
          'HH:mm',
        );
        expect(find.text('12:00'), findsNothing);
        expect(find.text('Uhrzeit entfernen'), findsNothing);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Übernehmen'),
              )
              .onPressed,
          isNull,
        );
        await dismissKeyboard();
        await capture('nutrition-entry-time-unknown');

        await openFoodEntry(seed: oats(atTs: knownTs));
        await openEditor();
        await openTime();
        await tester.enterText(
          find.byKey(const ValueKey('food-time')),
          '25:30',
        );
        await tester.pump();
        expect(timeFieldText(), '25:30');
        await waitKeyboardInset(open: true);
        expectPinnedAboveKeyboard(find.text('Übernehmen'));
        await tester.tap(find.text('Übernehmen'));
        await tester.pumpAndSettle();
        expect(find.text('Uhrzeit ungültig'), findsOneWidget);
        expect(timeFieldText(), '25:30');
        expect(find.byKey(const ValueKey('food-time')), findsOneWidget);
        await dismissKeyboard();
        await capture('nutrition-entry-time-error');

        await openFoodEntry(
          brightness: Brightness.dark,
          seed: oats(atTs: knownTs),
        );
        await openEditor();
        await openTime();
        expect(timeFieldText(), '08:15');
        expect(find.text('12:00'), findsNothing);
        expect(find.text('Uhrzeit entfernen'), findsOneWidget);
        await dismissKeyboard();
        await capture('nutrition-entry-time-dark');

        final removedRepo = await openFoodEntry();
        await tester.tap(find.byKey(const ValueKey('food-entry-remove')));
        await tester.pumpAndSettle();
        expect(find.text('Eintrag entfernen?'), findsOneWidget);
        await capture('nutrition-entry-remove-confirm');
        await tester.tap(find.text('Entfernen'));
        await tester.pumpAndSettle();
        expect(popped?.changed, isTrue);
        expect(popped?.removed?.id, 'oats');
        expect(popped?.removed?.label, 'Haferflocken mit Milch');
        expect(popped?.removed?.kcal, 380);
        expect(popped?.removed?.proteinG, 18);
        expect(popped?.removed?.sourceCode, 'manual');
        expect(popped?.removed?.confirmed, isTrue);
        expect((await removedRepo.readFoodEntry('oats')).missing, isTrue);

        await openFoodEntry(scale: 2);
        expect(tester.takeException(), isNull);
        expect(find.text('Eintrag'), findsOneWidget);
        await capture('nutrition-entry-large');
        await tester.scrollUntilVisible(
          find.text('Eintrag entfernen'),
          80,
          scrollable: foodScrollable(),
        );
        expect(
          find.byKey(const ValueKey('food-entry-remove')).hitTestable(),
          findsOneWidget,
        );
        await capture('nutrition-entry-large-scrolled');

        await openFoodEntry(scale: 2);
        await openEditor();
        expect(find.text('Eintrag bearbeiten'), findsOneWidget);
        expectPinned(find.text('Speichern'));
        await capture('nutrition-entry-editor-large');
        await settleKeyboard(find.byKey(const ValueKey('food-entry-name')));
        expect(keyboardInset(), greaterThan(0));
        expectPinnedAboveKeyboard(find.text('Speichern'));
        await capture('nutrition-entry-editor-keyboard');
        await dismissKeyboard();
        expect(keyboardInset(), 0);
        await tester.scrollUntilVisible(
          find.text('Notiz'),
          80,
          scrollable: foodScrollable(),
        );
        expectPinned(find.byKey(const ValueKey('food-entry-save')));
        await capture('nutrition-entry-editor-large-scrolled');

        await openFoodEntry(scale: 2);
        await openEditor();
        await openLabeledPane('Nährwerte');
        expect(find.text('Energie'), findsOneWidget);
        expectPinned(find.text('Übernehmen'));
        await capture('nutrition-entry-nutrients-large');
        await settleKeyboard(find.byKey(const ValueKey('food-nutrient-kcal')));
        expect(keyboardInset(), greaterThan(0));
        expectPinnedAboveKeyboard(find.text('Übernehmen'));
        await capture('nutrition-entry-nutrients-keyboard');
        await dismissKeyboard();
        expect(keyboardInset(), 0);
        await tester.scrollUntilVisible(
          find.text('Calcium'),
          80,
          scrollable: foodScrollable(),
        );
        expect(find.text('Calcium'), findsOneWidget);
        expectPinned(find.text('Übernehmen'));
        await capture('nutrition-entry-nutrients-large-scrolled');

        await openFoodEntry(scale: 2, seed: oats(quantity: 150));
        await openEditor();
        await openLabeledPane('Menge');
        expect(find.byKey(const ValueKey('food-qty-amount')), findsOneWidget);
        expect(find.text('Nährwerte anpassen'), findsOneWidget);
        expect(find.text('Menge entfernen'), findsOneWidget);
        expectPinned(find.text('Übernehmen'));
        await settleKeyboard(find.byKey(const ValueKey('food-qty-amount')));
        expect(keyboardInset(), greaterThan(0));
        expectPinnedAboveKeyboard(find.text('Übernehmen'));
        expectSheetHeaderBelowStatusBar('Menge');
        await capture('nutrition-entry-quantity-keyboard');
        await dismissKeyboard();
        expect(keyboardInset(), 0);

        await openFoodEntry(scale: 2, seed: oats(atTs: knownTs));
        await openEditor();
        await openTime();
        expect(timeFieldText(), '08:15');
        expectPinned(find.text('Übernehmen'));
        await settleKeyboard(find.byKey(const ValueKey('food-time')));
        expect(keyboardInset(), greaterThan(0));
        expectPinnedAboveKeyboard(find.text('Übernehmen'));
        expectSheetHeaderBelowStatusBar('Uhrzeit');
        await capture('nutrition-entry-time-keyboard');
        await dismissKeyboard();
        expect(keyboardInset(), 0);

        final parentRepo = await _loadNutritionReviewRepo();
        seedPaperFoods(parentRepo);
        var parent = await mountParent(repository: parentRepo);
        expect(find.byType(OpenBandNutrition), findsOneWidget);
        expect(find.text('Haferflocken mit Milch'), findsOneWidget);
        expect(find.text('Kaffee'), findsOneWidget);
        expect(find.text('Linsensalat'), findsOneWidget);
        expect(find.text('380'), findsOneWidget);
        expect(find.text('240'), findsOneWidget);
        expect(
          (await parentRepo.readFoodEntry('m1')).current!.proteinG,
          18,
        );
        expect((await parentRepo.readFoodEntry('m1')).current!.fatG, 12);
        expect((await parentRepo.readFoodEntry('m1')).current!.carbsG, 56);
        expect(
          (await parentRepo.readFoodEntry('m3')).current!.proteinG,
          8,
        );
        expect((await parentRepo.readFoodEntry('m3')).current!.fatG, 3);
        expect((await parentRepo.readFoodEntry('m3')).current!.carbsG, 32);
        expect(
          (await parentRepo.readFoodEntry('m2')).current!.source,
          FoodSource.unknown,
        );
        await capture('nutrition-entry-parent');

        await tester.tap(find.text('Kaffee'));
        await tester.pumpAndSettle();
        expect(inFoodEntry(find.text('Kaffee')), findsOneWidget);
        expect(inFoodEntry(find.text('Unbekannt')), findsOneWidget);
        expect(inFoodEntry(find.text('Manuell')), findsNothing);
        expect(inFoodEntry(find.text('380')), findsNothing);
        expect(inFoodEntry(find.text('18 g')), findsNothing);
        expect(inFoodEntry(find.text('08:15')), findsNothing);
        expect(inFoodEntry(find.text('—')), findsWidgets);
        expect(
          find.bySemanticsLabel('Quelle Unbekannt unknown'),
          findsOneWidget,
        );
        expect(
          (await parentRepo.readFoodEntry('m2')).current!.fibreG,
          8.1,
        );
        expect(
          (await parentRepo.readFoodEntry('m2')).current!.kcal,
          isNull,
        );
        expect(
          (await parentRepo.readFoodEntry('m2')).current!.atTs,
          isNull,
        );
        await capture('nutrition-entry-parent-coffee');
        await tester.tap(find.byTooltip('Zurück'));
        await tester.pumpAndSettle();
        expect(find.byType(OpenBandFoodEntry), findsNothing);
        expect(find.text('Kaffee'), findsOneWidget);

        await tester.tap(find.text('Haferflocken mit Milch'));
        await tester.pumpAndSettle();
        await openEditor();
        await tester.enterText(
          find.byKey(const ValueKey('food-entry-name')),
          'Hafer neu',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('food-entry-save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Zurück'));
        await tester.pumpAndSettle();
        expect(find.text('Hafer neu'), findsOneWidget);
        expect(find.text('Haferflocken mit Milch'), findsNothing);
        expect(
          (await parentRepo.readFoodEntry('m1')).current!.label,
          'Hafer neu',
        );
        expect((await parentRepo.readFoodEntry('m1')).current!.proteinG, 18);
        await capture('nutrition-entry-parent-edited');
        parent.dispose();

        seedPaperFoods(parentRepo);
        parent = await mountParent(repository: parentRepo);
        await removeRow('Kaffee');
        expect(find.byType(OpenBandFoodEntry), findsNothing);
        expect(find.text('Kaffee'), findsNothing);
        expect(find.text('Eintrag entfernt'), findsOneWidget);
        expect(find.text('Rückgängig'), findsOneWidget);
        await capture('nutrition-entry-undo');
        await tapSnackAction('Rückgängig');
        await pumpShown();
        final restoredCoffee = (await parentRepo.readFoodEntry('m2')).current!;
        expect(restoredCoffee.label, 'Kaffee');
        expect(restoredCoffee.source, FoodSource.unknown);
        expect(restoredCoffee.sourceCode, 'unknown');
        expect(restoredCoffee.kcal, isNull);
        expect(restoredCoffee.fibreG, 8.1);
        expect(restoredCoffee.sodiumMg, 12);
        expect(restoredCoffee.atTs, isNull);
        expect(restoredCoffee.createdAt, 50);
        expect(restoredCoffee.updatedAt, 50);
        expect(find.text('Kaffee'), findsOneWidget);
        expect(parentRepo.restores, 1);
        parent.dispose();

        seedPaperFoods(parentRepo);
        parent = await mountParent(
          repository: parentRepo,
          brightness: Brightness.dark,
        );
        await removeRow('Kaffee');
        expect(find.text('Eintrag entfernt'), findsOneWidget);
        expect(find.text('Rückgängig'), findsOneWidget);
        await capture('nutrition-entry-undo-dark');
        await tapSnackAction('Rückgängig');
        await pumpShown();
        expect(find.text('Kaffee'), findsOneWidget);
        parent.dispose();

        seedPaperFoods(parentRepo);
        parent = await mountParent(repository: parentRepo, scale: 2);
        await removeRow('Haferflocken mit Milch');
        expect(find.text('Eintrag entfernt'), findsOneWidget);
        expect(find.text('Rückgängig'), findsOneWidget);
        final undoAction = tester.getRect(
          find.widgetWithText(TextButton, 'Rückgängig'),
        );
        expect(undoAction.height, greaterThanOrEqualTo(44));
        await capture('nutrition-entry-undo-2x');
        await tapSnackAction('Rückgängig');
        await pumpShown();
        expect(find.text('Haferflocken mit Milch'), findsOneWidget);
        expect((await parentRepo.readFoodEntry('m1')).current!.proteinG, 18);
        parent.dispose();

        seedPaperFoods(parentRepo);
        parentRepo.restores = 0;
        parent = await mountParent(repository: parentRepo);
        await removeRow('Kaffee');
        parentRepo.failFoodWrite = true;
        await tapSnackAction('Rückgängig');
        await pumpShown();
        expect(find.text('Wiederherstellen fehlgeschlagen'), findsOneWidget);
        expect((await parentRepo.readFoodEntry('m2')).missing, isTrue);
        expect(parentRepo.restores, 1);
        await capture('nutrition-entry-undo-error');
        parentRepo.failFoodWrite = false;
        await tapSnackAction('Erneut');
        await pumpShown();
        expect((await parentRepo.readFoodEntry('m2')).current!.fibreG, 8.1);
        expect(find.text('Kaffee'), findsOneWidget);
        expect(parentRepo.restores, 2);
        parent.dispose();

        seedPaperFoods(parentRepo);
        parentRepo.restores = 0;
        parent = await mountParent(repository: parentRepo);
        await removeRow('Kaffee');
        parentRepo.seedFoodEntry(
          const FoodEntry(
            id: 'm2',
            date: '2026-09-15',
            meal: 'breakfast',
            label: 'Other',
            kcal: 90,
            createdAt: 9,
            updatedAt: 9,
          ),
        );
        await tapSnackAction('Rückgängig');
        await pumpShown();
        final conflicted = (await parentRepo.readFoodEntry('m2')).current!;
        expect(conflicted.label, 'Other');
        expect(conflicted.kcal, 90);
        expect(conflicted.fibreG, isNull);
        expect(find.text('Eintrag wurde geändert'), findsOneWidget);
        expect(find.text('Neu laden'), findsOneWidget);
        expect(find.text('Wiederherstellen fehlgeschlagen'), findsNothing);
        expect(parentRepo.restores, 1);
        await capture('nutrition-entry-undo-conflict');
        await tapSnackAction('Neu laden');
        await pumpShown();
        expect(parentRepo.restores, 1);
        expect((await parentRepo.readFoodEntry('m2')).current!.label, 'Other');
        parent.dispose();

        seedPaperFoods(parentRepo);
        parentRepo.restores = 0;
        parent = await mountParent(repository: parentRepo);
        await removeRow('Kaffee');
        parentRepo.failDayRead = true;
        await tapSnackAction('Rückgängig');
        await pumpShown();
        expect(parent.loadError, isA<StateError>());
        expect((await parentRepo.readFoodEntry('m2')).current!.fibreG, 8.1);
        expect(parentRepo.restores, 1);
        expect(
          find.text('Einträge konnten nicht geladen werden.'),
          findsOneWidget,
        );
        parentRepo.failDayRead = false;
        await tapSnackAction('Erneut');
        await pumpShown();
        expect(parent.loadError, isNull);
        expect(find.text('Kaffee'), findsOneWidget);
        expect(parentRepo.restores, 1);
        parent.dispose();

        final draftRepo = await _loadNutritionReviewRepo();
        seedPaperFoods(draftRepo);
        await draftRepo.saveMealDraft(breakfastDraft());
        parent = await mountParent(repository: draftRepo, enableAdd: true);
        await tester.tap(find.byTooltip('Frühstück ergänzen'));
        await tester.pumpAndSettle();
        expect(find.byType(OBMealDraftSheet), findsOneWidget);
        expect(inDraft(find.text('Haferflocken mit Milch')), findsOneWidget);
        expect(inDraft(find.text('Kaffee')), findsOneWidget);
        expect(inDraft(find.text('380 kcal')), findsOneWidget);
        expect(inDraft(find.text('—')), findsOneWidget);
        expect(find.byTooltip('Schließen'), findsOneWidget);
        expect(inDraft(find.text('Speichern')), findsOneWidget);
        await capture('nutrition-draft');
        parent.dispose();

        await draftRepo.saveMealDraft(breakfastDraft());
        parent = await mountParent(
          repository: draftRepo,
          brightness: Brightness.dark,
          enableAdd: true,
        );
        await tester.tap(find.byTooltip('Frühstück ergänzen'));
        await tester.pumpAndSettle();
        expect(find.byType(OBMealDraftSheet), findsOneWidget);
        expect(inDraft(find.text('380 kcal')), findsOneWidget);
        await capture('nutrition-draft-dark');
        parent.dispose();

        await draftRepo.saveMealDraft(breakfastDraft());
        draftRepo.failFoodWrite = true;
        parent = await mountParent(repository: draftRepo, enableAdd: true);
        await tester.tap(find.byTooltip('Frühstück ergänzen'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Speichern'));
        await tester.pumpAndSettle();
        expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
        expect(find.text('Erneut versuchen'), findsOneWidget);
        expect(find.text('Speichern'), findsNothing);
        expect(await draftRepo.readMealDraft('2026-09-15', 'breakfast'), isNotNull);
        expect((await draftRepo.readFoodEntry('e-oats')).missing, isTrue);
        await capture('nutrition-draft-save-failure');
        draftRepo.failFoodWrite = false;
        final commitsBeforeRetry = draftRepo.commits;
        await tester.tap(find.text('Erneut versuchen'));
        await tester.pumpAndSettle();
        expect(find.byType(OBMealDraftSheet), findsNothing);
        expect((await draftRepo.readFoodEntry('e-oats')).current!.kcal, 380);
        expect(draftRepo.commits, commitsBeforeRetry + 1);
        parent.dispose();

        final draftConflictRepo = await _loadNutritionReviewRepo();
        seedPaperFoods(draftConflictRepo);
        final staleBreakfast = breakfastDraft();
        await draftConflictRepo.saveMealDraft(staleBreakfast);
        await draftConflictRepo.discardMealDraft('d-breakfast');
        parent = await mountParent(
          repository: draftConflictRepo,
          enableAdd: true,
          addDraft: staleBreakfast,
        );
        await tester.tap(find.byTooltip('Frühstück ergänzen'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Speichern'));
        await tester.pumpAndSettle();
        expect(find.text('Entwurf nicht gespeichert'), findsOneWidget);
        expect(inDraft(find.text('Speichern')), findsNothing);
        expect(inDraft(find.text('380 kcal')), findsOneWidget);
        expect((await draftConflictRepo.readFoodEntry('e-oats')).missing, isTrue);
        await capture('nutrition-draft-conflict');
        await tester.tap(find.text('Neu laden'));
        await tester.pumpAndSettle();
        expect(find.text('Entwurf nicht gefunden'), findsOneWidget);
        expect(inDraft(find.text('380 kcal')), findsNothing);
        expect(find.text('Entwurf nicht gespeichert'), findsNothing);
        expect(find.text('Speichern'), findsNothing);
        expect(find.text('Haferflocken mit Milch'), findsOneWidget);
        expect(find.text('Kaffee'), findsOneWidget);
        await capture('nutrition-draft-missing');
        parent.dispose();

        final readRepo = await _loadNutritionReviewRepo();
        seedPaperFoods(readRepo);
        final staleRead = breakfastDraft();
        await readRepo.saveMealDraft(staleRead);
        await readRepo.discardMealDraft('d-breakfast');
        await readRepo.saveMealDraft(
          MealDraft(
            id: 'd-now',
            day: '2026-09-15',
            meal: 'breakfast',
            entries: staleRead.entries,
            updatedAt: DateTime(2026, 9, 15, 9),
          ),
        );
        parent = await mountParent(
          repository: readRepo,
          enableAdd: true,
          addDraft: staleRead,
        );
        await tester.tap(find.byTooltip('Frühstück ergänzen'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Speichern'));
        await tester.pumpAndSettle();
        readRepo.failDraftRead = true;
        final commitsBeforeRead = readRepo.commits;
        await tester.tap(find.text('Neu laden'));
        await tester.pumpAndSettle();
        expect(find.text('Entwurf nicht geladen'), findsOneWidget);
        expect(find.text('Entwurf nicht gespeichert'), findsNothing);
        expect(inDraft(find.text('380 kcal')), findsNothing);
        expect(inDraft(find.text('Speichern')), findsNothing);
        expect(readRepo.commits, commitsBeforeRead);
        await capture('nutrition-draft-read-error');
        readRepo.failDraftRead = false;
        await tester.tap(find.text('Neu laden'));
        await tester.pumpAndSettle();
        expect(inDraft(find.text('380 kcal')), findsOneWidget);
        expect(inDraft(find.text('Speichern')), findsOneWidget);
        expect(readRepo.commits, commitsBeforeRead);
        parent.dispose();

        final manyRepo = await _loadNutritionReviewRepo();
        seedPaperFoods(manyRepo);
        final many = MealDraft(
          id: 'd-many',
          day: '2026-09-15',
          meal: 'breakfast',
          entries: [
            for (var i = 1; i <= 8; i++)
              MealDraftEntry(
                id: 'e-$i',
                label: 'Sehr langes Lebensmittel $i mit extra Text',
                kcal: 100.0 * i,
              ),
          ],
          updatedAt: DateTime(2026, 9, 15, 8),
        );
        await manyRepo.saveMealDraft(many);
        parent = await mountParent(
          repository: manyRepo,
          scale: 2,
          enableAdd: true,
        );
        await tester.tap(find.byTooltip('Frühstück ergänzen'));
        await tester.pumpAndSettle();
        expect(find.byType(OBMealDraftSheet), findsOneWidget);
        expectPinned(inDraft(find.text('Speichern')));
        expectSheetHeaderBelowStatusBar('Frühstück');
        await capture('nutrition-draft-large');
        await tester.scrollUntilVisible(
          find.text('Sehr langes Lebensmittel 8 mit extra Text'),
          80,
          scrollable: find.descendant(
            of: find.byType(OBMealDraftSheet),
            matching: find.byType(Scrollable),
          ),
        );
        expectPinned(inDraft(find.text('Speichern')));
        expectSheetHeaderBelowStatusBar('Frühstück');
        await capture('nutrition-draft-large-scrolled');
        parent.dispose();
      }

      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['flow'] = kOpenBandReviewFlow;
      if (kOpenBandReviewFlow == 'journal' ||
          kOpenBandReviewFlow == 'journal-hub') {
        await reviewJournal();
        return;
      }
      if (kOpenBandReviewFlow == 'nutrition-entry') {
        await reviewNutritionEntry();
        return;
      }

      Future<void> edit({
        String variant = '',
        bool captureEntry = false,
      }) async {
        await tester.tap(find.bySemanticsLabel('Schlaf, 7h18 '));
        await tester.pumpAndSettle();
        await pressSleepEditor();
        await tester.pumpAndSettle();
        if (captureEntry) await capture('correction-entry$variant');
        await tester.enterText(
          find.byKey(const ValueKey('sleep-onset')),
          '23:25',
        );
        await tester.pumpAndSettle();
        await capture('correction-keyboard$variant');
        await tester.ensureVisible(find.text('Änderung ansehen'));
        await tester.tap(find.text('Änderung ansehen'));
        await tester.pumpAndSettle();
        expect(find.text('7h29'), findsOneWidget);
      }

      for (final scenario in [
        SyntheticScenario.complete,
        SyntheticScenario.dense,
        SyntheticScenario.partial,
        SyntheticScenario.missing,
        SyntheticScenario.processing,
        SyntheticScenario.disconnected,
        SyntheticScenario.interrupted,
      ]) {
        for (final brightness in Brightness.values) {
          await mount(scenario: scenario, brightness: brightness);
          await capture('overview-${scenario.name}-${brightness.name}');
          if ([
            SyntheticScenario.complete,
            SyntheticScenario.dense,
            SyntheticScenario.partial,
            SyntheticScenario.missing,
            SyntheticScenario.processing,
          ].contains(scenario)) {
            await tester.tap(find.bySemanticsLabel(RegExp(r'^Schlaf, ')).first);
            await tester.pumpAndSettle();
            await capture('sleep-${scenario.name}-${brightness.name}');
          }
        }
      }

      await mount();
      await tester.tap(find.text(obDayTitle('2026-09-15')));
      await tester.pumpAndSettle();
      await capture('date-selection');
      await tester.tap(find.byTooltip('Abbrechen'));
      await tester.pumpAndSettle();
      await edit(captureEntry: true);
      await capture('correction-preview');
      await press('Schlafzeiten speichern');
      expect(find.text('Schlaf aktualisiert'), findsWidgets);
      await capture('correction-complete');
      await press('Zur Übersicht');
      expect(find.bySemanticsLabel('Schlaf, 7h08 '), findsOneWidget);
      await capture('overview-corrected');

      final failing = await mount(scenario: SyntheticScenario.saveFailure);
      await edit(variant: '-save-failure');
      await press('Schlafzeiten speichern');
      expect(await failing.readDraft('2026-09-15'), isNotNull);
      await capture('save-failure');
      failing.scenario = SyntheticScenario.complete;
      await press('Erneut speichern');
      expect(find.text('Schlaf aktualisiert'), findsWidgets);
      await capture('save-retry-complete');

      final calculationFailure = await mount(
        scenario: SyntheticScenario.calculationFailure,
      );
      await edit(variant: '-calculation-failure');
      await press('Schlafzeiten speichern');
      expect(find.text('Auswertung erneut starten'), findsOneWidget);
      await capture('calculation-failure');
      calculationFailure.scenario = SyntheticScenario.complete;
      await press('Auswertung erneut starten');
      await capture('calculation-retry-complete');
      await press('Nacht ansehen');
      await tester.scrollUntilVisible(
        find.byTooltip('Schlafzeiten ändern'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Schlafzeiten ändern'), findsOneWidget);
      await capture('sleep-corrected');

      final pending = await mount(brightness: Brightness.dark);
      final calculation = Completer<void>();
      pending.calculationBarrier = calculation.future;
      await edit(variant: '-dark', captureEntry: true);
      await capture('correction-preview-dark');
      await press('Schlafzeiten speichern');
      expect(find.text('Zeiten gespeichert'), findsWidgets);
      await capture('correction-pending-dark');
      calculation.complete();
      await tester.pumpAndSettle();
      await capture('correction-complete-dark');
      await press('Automatische Zeiten wiederherstellen');
      await capture('restore-confirmation-dark');
      await press('Wiederherstellen');
      expect((await pending.readDay('2026-09-15')).sleep.duration.value, 438);
      expect(find.text('7h18'), findsNWidgets(2));

      await mount();
      await tester.tap(find.text(obDayTitle('2026-09-15')));
      await tester.pumpAndSettle();
      await press('14');
      await capture('date-selected-night');
      await press('14. September ansehen');
      expect(find.bySemanticsLabel('Schlaf, 7h02 '), findsOneWidget);
      await capture('overview-historical');

      final draftFailure = await mount(
        scenario: SyntheticScenario.draftFailure,
      );
      await tester.tap(find.bySemanticsLabel('Schlaf, 7h18 '));
      await tester.pumpAndSettle();
      await pressSleepEditor();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('sleep-onset')),
        '23:25',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Entwurf erneut sichern'));
      await capture('draft-save-failure');
      draftFailure.scenario = SyntheticScenario.complete;
      await press('Entwurf erneut sichern');
      expect((await draftFailure.readDraft('2026-09-15'))?.onset.minute, 25);

      await mount(scenario: SyntheticScenario.partial);
      await tester.tap(find.bySemanticsLabel(RegExp(r'^Schlaf, ')).first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsLabel(RegExp('02:10 bis 02:34: Keine Daten')).first,
      );
      await tester.pumpAndSettle();
      await capture('sleep-phases');
      await tester.tap(find.byTooltip('Schließen'));
      await tester.pumpAndSettle();

      final cancelled = await mount();
      await edit(variant: '-cancel');
      await press('Weiter bearbeiten');
      await tester.tap(find.byTooltip('Zurück').first);
      await tester.pumpAndSettle();
      await capture('draft-leave-confirmation');
      await press('Entwurf behalten');
      await pressSleepEditor();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('sleep-onset')))
            .controller
            ?.text,
        '23:25',
      );
      await press('Änderung ansehen');
      await press('Änderung verwerfen');
      expect(await cancelled.readDraft('2026-09-15'), isNull);
      expect((await cancelled.readDay('2026-09-15')).sleep.duration.value, 438);
      expect(find.text('7h18'), findsNWidgets(2));

      await mount(scale: 2);
      await capture('overview-large-text');
      await tester.tap(find.bySemanticsLabel('Schlaf, 7h18 '));
      await tester.pumpAndSettle();
      await capture('sleep-large-text');
      await pressSleepEditor();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('sleep-onset')),
        '23:25',
      );
      await tester.pumpAndSettle();
      await capture('correction-large-keyboard');
      await tester.ensureVisible(find.byKey(const ValueKey('sleep-wake')));
      await tester.enterText(find.byKey(const ValueKey('sleep-wake')), '06:54');
      await tester.pumpAndSettle();
      await capture('correction-large-wake-keyboard');
      await press('Änderung ansehen');
      await capture('correction-large-preview');
      await press('Schlafzeiten speichern');
      await capture('correction-large-complete');
      await press('Zur Übersicht');
      await tester.tap(find.text(obDayTitle('2026-09-15')));
      await tester.pumpAndSettle();
      await capture('date-large-text');
      await press('14');
      await press('14. September ansehen');
      expect(find.bySemanticsLabel('Schlaf, 7h02 '), findsOneWidget);

      Future<SyntheticOpenBandRepository> openSleepGoal({
        SyntheticScenario scenario = SyntheticScenario.complete,
        Brightness brightness = Brightness.light,
        double? scale,
        int? targetMinutes,
        bool estimate = true,
      }) async {
        final repository = await mount(
          scenario: scenario,
          brightness: brightness,
          scale: scale,
        );
        if (!estimate) repository.weekendEstimate = null;
        if (targetMinutes != null) {
          await repository.saveSleepGoal('2026-09-15', targetMinutes);
        }
        await tester.tap(find.bySemanticsLabel('Schlaf, 7h18 '));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Schlafziel'),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Schlafziel'));
        await tester.pumpAndSettle();
        return repository;
      }

      await openSleepGoal();
      expect(find.text('Ziel festlegen'), findsOneWidget);
      expect(find.text('7 h 45'), findsNothing);
      await capture('sleep-goal-unset');
      await press('Ziel festlegen');
      await capture('sleep-goal-editor');
      await tester.enterText(
        find.byKey(const ValueKey('sleep-goal-hours')),
        '7',
      );
      await tester.enterText(
        find.byKey(const ValueKey('sleep-goal-minutes')),
        '45',
      );
      await tester.pumpAndSettle();
      await press('Speichern');
      expect(find.text('7 h 45'), findsOneWidget);
      expect(find.text('8 h 12 · Stand 15. September'), findsOneWidget);
      await capture('sleep-goal-estimate');
      await tester.tap(find.bySemanticsLabel('Wochenend-Schätzung'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          '75. Perzentil der Wochenendnächte. Keine Messung des Schlafbedarfs.',
        ),
        findsOneWidget,
      );
      await capture('sleep-goal-estimate-info');
      await press('Schließen');
      await openSleepGoal(targetMinutes: 465);
      await press('Ändern');
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('sleep-goal-hours')))
            .controller
            ?.text,
        '7',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('sleep-goal-minutes')))
            .controller
            ?.text,
        '45',
      );
      await capture('sleep-goal-editor-target');
      await openSleepGoal(
        brightness: Brightness.dark,
        targetMinutes: 465,
        estimate: false,
      );
      expect(find.text('7 h 45'), findsOneWidget);
      expect(find.text('Ändern'), findsOneWidget);
      expect(find.text('8 h 12 · Stand 15. September'), findsNothing);
      await capture('sleep-goal-dark');
      await press('Ändern');
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('sleep-goal-hours')))
            .controller
            ?.text,
        '7',
      );
      await capture('sleep-goal-editor-dark');
      await openSleepGoal(scale: 2, targetMinutes: 465);
      expect(find.text('7 h 45'), findsOneWidget);
      expect(find.text('8 h 12 · Stand 15. September'), findsOneWidget);
      await capture('sleep-goal-2x');
      await press('Ändern');
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('sleep-goal-hours')))
            .controller
            ?.text,
        '7',
      );
      await capture('sleep-goal-editor-2x');
      final failingGoal = await openSleepGoal();
      failingGoal.failSleepGoalWrite = true;
      await press('Ziel festlegen');
      await tester.enterText(
        find.byKey(const ValueKey('sleep-goal-hours')),
        '7',
      );
      await tester.enterText(
        find.byKey(const ValueKey('sleep-goal-minutes')),
        '45',
      );
      await tester.pumpAndSettle();
      await press('Speichern');
      expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
      await capture('sleep-goal-error');

      // ── Hub- und Flow-Captures der neuen Oberflächen ──
      await mount();
      await press('Gesundheit');
      await capture('health-hub');
      await press('30 Nächte');
      await capture('health-30');

      await press('Laborwerte');
      await capture('labs-list');
      await press('Ferritin');
      await capture('labs-detail');
      await tester.tap(find.byKey(const ValueKey('lab-hist-2026-09-15')));
      await tester.pumpAndSettle();
      await capture('labs-editor');
      await tester.enterText(find.byKey(const ValueKey('lab-value')), '53');
      await tester.pumpAndSettle();
      await capture('labs-editor-keyboard');
      await tester.tap(find.byTooltip('Zurück'));
      await tester.pumpAndSettle();
      await press('Verwerfen');
      await tester.tap(find.byTooltip('Zurück'));
      await tester.pumpAndSettle();
      await press('Wert hinzufügen');
      await capture('labs-chooser');
      await press('Ferritin');
      await capture('labs-add');
      await tester.enterText(find.byKey(const ValueKey('lab-value')), '40');
      await tester.pumpAndSettle();
      await press('Speichern');
      await capture('labs-add-success');
      await press('Ferritin');
      await tester.tap(find.byKey(const ValueKey('lab-hist-2026-09-15')));
      await tester.pumpAndSettle();
      await press('Wert entfernen');
      await capture('labs-delete-confirm');
      await tester.tap(find.text('Wert entfernen').last);
      await tester.pumpAndSettle();
      await capture('labs-delete-success');
      await tester.tap(find.byTooltip('Zurück'));
      await tester.pumpAndSettle();

      final failingDelete = await mount();
      failingDelete.failLabWrites = true;
      await press('Gesundheit');
      await press('Laborwerte');
      await press('Ferritin');
      await tester.tap(find.byKey(const ValueKey('lab-hist-2026-09-15')));
      await tester.pumpAndSettle();
      await press('Wert entfernen');
      await tester.tap(find.text('Wert entfernen').last);
      await tester.pumpAndSettle();
      expect(find.text('Nicht entfernt.'), findsOneWidget);
      await capture('labs-delete-failure');

      await mount(brightness: Brightness.dark);
      await press('Gesundheit');
      await press('Laborwerte');
      await capture('labs-list-dark');
      await press('Ferritin');
      await capture('labs-detail-dark');
      await tester.tap(find.byKey(const ValueKey('lab-hist-2026-09-15')));
      await tester.pumpAndSettle();
      await capture('labs-editor-dark');
      await tester.tap(find.byTooltip('Zurück'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Zurück'));
      await tester.pumpAndSettle();

      final emptyLabs = await mount();
      await emptyLabs.deleteLabDraw('ferritin', '2026-09-15');
      await emptyLabs.deleteLabDraw('ferritin', '2026-06-12');
      await emptyLabs.deleteLabDraw('ferritin', '2026-03-04');
      await emptyLabs.deleteLabDraw('vitamin_b12', '2026-09-15');
      await emptyLabs.deleteLabDraw('vitamin_d', '2026-09-15');
      await press('Gesundheit');
      await press('Laborwerte');
      await capture('labs-empty');

      final failingLabs = await mount();
      failingLabs.failLabWrites = true;
      await press('Gesundheit');
      await press('Laborwerte');
      await press('Ferritin');
      await tester.tap(find.byKey(const ValueKey('lab-hist-2026-09-15')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('lab-value')), '53');
      await tester.pumpAndSettle();
      await press('Speichern');
      expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
      await capture('labs-save-failure');

      await mount();
      await press('Gesundheit');
      await press('Laborwerte');
      await press('Vitamin D (25-OH)');
      expect(find.text('Befundbereich unbekannt'), findsNothing);
      expect(find.text('Befundbereich'), findsWidgets);
      expect(find.text('—'), findsWidgets);
      await capture('labs-bounds-missing');
      await tester.tap(find.byTooltip('Zurück'));
      await tester.pumpAndSettle();
      await press('Eigene Marker');
      await press('Marker anlegen');
      await tester.enterText(
        find.byKey(const ValueKey('lab-def-name')),
        'Kupfer',
      );
      await tester.enterText(
        find.byKey(const ValueKey('lab-def-unit')),
        'µg/dL',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await capture('labs-custom-marker');

      await mount(brightness: Brightness.dark);
      await press('Gesundheit');
      await press('Laborwerte');
      await press('Eigene Marker');
      await press('Marker anlegen');
      await tester.enterText(
        find.byKey(const ValueKey('lab-def-name')),
        'Kupfer',
      );
      await tester.enterText(
        find.byKey(const ValueKey('lab-def-unit')),
        'µg/dL',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await capture('labs-custom-dark');

      await mount(scale: 2);
      await press('Gesundheit');
      await capture('health-large-text');
      await press('Laborwerte');
      await capture('labs-list-large');
      await press('Ferritin');
      await capture('labs-detail-large');
      await press('Wert hinzufügen');
      await capture('labs-editor-large');

      await mount();
      await press('Training');
      await capture('training-hub');
      await tester.tap(find.text('Starten'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await capture('strength-live');
      await tester.tap(find.byTooltip('Einklappen'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // 'Laufen' trifft Quick-Start-Tile und Zuletzt-Zeile; die Zeile ist letztere.
      await tester.ensureVisible(find.text('Laufen').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Laufen').last);
      await tester.pumpAndSettle();
      await capture('session-run');
      await pop();
      // Das Quick-Start-Tile liegt über der Liste; erst ganz nach oben
      // flingen (die Liste lädt Zeilen lazy — 'Laufen' allein trifft
      // sonst wieder die Zuletzt-Zeile).
      for (var i = 0; i < 5; i++) {
        await tester.fling(
          find.byType(Scrollable).last,
          const Offset(0, 500),
          3000,
        );
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Laufen').first);
      await tester.pumpAndSettle();
      await capture('run-live');
      await tester.tap(find.byTooltip('Einklappen'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Vorlagen'));
      await tester.pumpAndSettle();
      await capture('templates-list');
      await tester.tap(find.byTooltip('Aktionen').first);
      await tester.pumpAndSettle();
      await capture('templates-menu');
      await tester.tap(find.text('Anheften'));
      await tester.pumpAndSettle();
      await capture('templates-pinned');
      await tester.tap(find.byTooltip('Aktionen').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bearbeiten'));
      await tester.pumpAndSettle();
      await capture('template-editor');
      await pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Neue Vorlage'));
      await tester.pumpAndSettle();
      await capture('template-editor-create');
      await pop();
      await tester.pumpAndSettle();
      await pop();
      await tester.pumpAndSettle();
      await capture('templates-hub');

      await mount(brightness: Brightness.dark);
      await press('Training');
      await tester.tap(find.byTooltip('Vorlagen'));
      await tester.pumpAndSettle();
      await capture('templates-dark');
      await tester.tap(find.byTooltip('Aktionen').first);
      await tester.pumpAndSettle();
      await capture('templates-menu-dark');
      await pop();
      await tester.pumpAndSettle();

      final emptyTemplates = await mount();
      emptyTemplates.clearTemplates();
      await press('Training');
      await tester.tap(find.byTooltip('Vorlagen'));
      await tester.pumpAndSettle();
      expect(find.text('Keine Vorlagen'), findsOneWidget);
      await capture('templates-empty');

      final templateReadFail = await mount();
      templateReadFail.failTemplateRead = true;
      await press('Training');
      await tester.tap(find.byTooltip('Vorlagen'));
      await tester.pumpAndSettle();
      expect(
        find.text('Vorlagen konnten nicht geladen werden.'),
        findsOneWidget,
      );
      expect(find.text('Keine Vorlagen'), findsNothing);
      await capture('templates-error');

      await mount(scale: 2);
      await press('Training');
      await tester.tap(find.byTooltip('Vorlagen'));
      await tester.pumpAndSettle();
      await capture('templates-2x');

      Future<SyntheticOpenBandRepository> openPaperLive({
        Brightness brightness = Brightness.light,
        double? scale,
        bool failWrites = false,
      }) async {
        final repository = await mount(brightness: brightness, scale: scale);
        final now = DateTime(2026, 9, 15, 18, 32, 14);
        await repository.seedPaperLiveStrength(
          startedAt: DateTime(2026, 9, 15, 18),
          now: now,
        );
        repository.failStrengthWrites = failWrites;
        final nav = tester
            .element(find.byType(AppShell).first)
            .findAncestorStateOfType<NavigatorState>();
        unawaited(
          nav!.push(
            MaterialPageRoute<void>(
              builder: (_) => OpenBandStrengthLive.resume(
                repository: repository,
                now: () => now,
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        return repository;
      }

      Finder inBank(Finder matching) => find.descendant(
        of: find.ancestor(
          of: find.text('Bankdrücken'),
          matching: find.byType(OBExerciseBlock),
        ),
        matching: matching,
      );

      // InkRipple._kFadeOutDuration=375ms; InkSparkle=617ms. 200ms theme
      // duration ends while confirmed ripple is still opaque (fade starts
      // 225/375). Cap stays under the 1s rest tick.
      Future<void> settleLiveTransition() async {
        await tester.pumpAndSettle(
          const Duration(milliseconds: 16),
          EnginePhase.sendSemanticsUpdate,
          const Duration(milliseconds: 800),
        );
      }

      await openPaperLive();
      expect(find.text('1:24'), findsOneWidget);
      expect(
        Theme.of(tester.element(find.byType(OpenBandStrengthLive))).brightness,
        Brightness.light,
      );
      await capture('strength-live-light');

      await openPaperLive();
      await tester.tap(inBank(find.byTooltip('Übungsmenü')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Satz 3 überspringen'), findsOneWidget);
      await capture('strength-menu');

      await openPaperLive();
      await tester.tap(inBank(find.byTooltip('Übungsmenü')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Satz 3 überspringen'));
      await settleLiveTransition();
      expect(find.text('Satz 3 überspringen'), findsNothing);
      expect(inBank(find.text('Übersprungen')), findsOneWidget);
      await capture('strength-skipped');

      await openPaperLive();
      await tester.tap(inBank(find.byTooltip('Satz hinzufügen')));
      await settleLiveTransition();
      expect(inBank(find.text('5')), findsOneWidget);
      await capture('strength-add');

      final failingLive = await openPaperLive(failWrites: true);
      final failNow = DateTime(2026, 9, 15, 18, 32, 14);
      expect(inBank(find.byTooltip('Satz 3 bestätigen')), findsOneWidget);
      await tester.tap(inBank(find.byTooltip('Satz 3 bestätigen')));
      await settleLiveTransition();
      expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
      await capture('strength-save-failure');
      failingLive.failStrengthWrites = false;
      await tester.tap(find.text('Erneut'));
      await settleLiveTransition();
      expect(find.text('Speichern fehlgeschlagen'), findsNothing);
      await capture('strength-save-retry');
      await tester.tap(find.byTooltip('Einklappen'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      unawaited(
        tester
            .element(find.byType(AppShell).first)
            .findAncestorStateOfType<NavigatorState>()!
            .push(
              MaterialPageRoute<void>(
                builder: (_) => OpenBandStrengthLive.resume(
                  repository: failingLive,
                  now: () => failNow,
                ),
              ),
            ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('62,5'), findsWidgets);
      await capture('strength-resume');

      await openPaperLive(brightness: Brightness.dark);
      expect(
        Theme.of(tester.element(find.byType(OpenBandStrengthLive))).brightness,
        Brightness.dark,
      );
      expect(find.text('Übersprungen'), findsNothing);
      await capture('strength-live-dark');
      await openPaperLive(scale: 2);
      expect(find.text('+30 s').hitTestable(), findsOneWidget);
      await capture('strength-live-large');
      await tester.tap(find.byTooltip('Einklappen'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await reviewJournal();

      for (final brightness in Brightness.values) {
        for (final phoneActions in [true, false]) {
          var chosen = DeviceAction.none;
          await tester.pumpWidget(
            MaterialApp(
              key: UniqueKey(),
              debugShowCheckedModeBanner: false,
              locale: const Locale('de'),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              theme: openBandTheme(brightness),
              home: StatefulBuilder(
                builder: (context, setState) => BandGesturesView(
                  chosen: chosen,
                  supported: {
                    DeviceAction.none,
                    ...DeviceAction.values.where((a) => a.isInApp),
                    if (phoneActions) ...{
                      DeviceAction.ringPhone,
                      DeviceAction.torch,
                    },
                  },
                  onPick: (value) => setState(() => chosen = value),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final state = phoneActions ? 'available' : 'unavailable';
          await capture('gestures-$state-${brightness.name}');
          if (phoneActions) {
            await press('Wasser protokollieren');
            expect(chosen, DeviceAction.logWater);
            await capture('gestures-selected-${brightness.name}');
          }
        }
      }

      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          debugShowCheckedModeBanner: false,
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: openBandTheme(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: BandGesturesView(
            chosen: DeviceAction.none,
            supported: {
              DeviceAction.none,
              ...DeviceAction.values.where((a) => a.isInApp),
              DeviceAction.ringPhone,
              DeviceAction.torch,
            },
            onPick: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await capture('gestures-large-text');
      await press('Taschenlampe');
      await capture('gestures-large-text-scrolled');

      for (final brightness in [Brightness.light, Brightness.dark]) {
        await mount(brightness: brightness);
        await tester.tap(find.bySemanticsLabel('Schlaf, 7h18 '));
        await tester.pumpAndSettle();
        await press('Nachtverlauf');
        await capture('night-pulse-${brightness.name}');
        await press('HRV');
        expect(find.text('60'), findsOneWidget);
        await capture('night-hrv-${brightness.name}');
        await press('Atmung');
        expect(find.text('14,2'), findsOneWidget);
        await capture('night-respiration-${brightness.name}');
        await tester.tap(
          find.byTooltip('Nachtverlauf: Quelle und Darstellung'),
        );
        await tester.pumpAndSettle();
        await capture('night-info-${brightness.name}');
        await press('Schließen');
      }
      for (final scenario in [
        SyntheticScenario.partial,
        SyntheticScenario.missingNightHrv,
      ]) {
        await mount(scenario: scenario);
        await tester.tap(find.bySemanticsLabel(RegExp(r'^Schlaf, ')));
        await tester.pumpAndSettle();
        await press('Nachtverlauf');
        if (scenario == SyntheticScenario.partial) {
          for (var i = 0; i < 2; i++) {
            await tester.tap(find.byTooltip('Nächster Messpunkt'));
            await tester.pumpAndSettle();
          }
          expect(find.text('02:10'), findsOneWidget);
          expect(find.text('—'), findsOneWidget);
          await capture('night-gap-selected');
        } else {
          await press('HRV');
          expect(find.text('Keine HRV-Werte'), findsOneWidget);
          await capture('night-hrv-missing');
        }
      }
      await mount(scale: 2);
      await tester.tap(find.bySemanticsLabel('Schlaf, 7h18 '));
      await tester.pumpAndSettle();
      await press('Nachtverlauf');
      await press('Atmung');
      await capture('night-large-text');

      Future<void> mountAlarm({
        DateTime? at,
        AlarmArmState state = AlarmArmState.none,
        bool connected = true,
        bool scheduleEnabled = true,
        bool failing = false,
        Brightness brightness = Brightness.light,
        double scale = 1,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            debugShowCheckedModeBanner: false,
            locale: const Locale('de'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            theme: openBandTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: AlarmGallerySession(
              armedAt: at,
              now: galleryAlarmNow,
              state: state,
              connected: connected,
              scheduleEnabled: scheduleEnabled,
              failing: failing,
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Finder wednesdayTime() => find.descendant(
        of: find.byKey(const ValueKey('alarm-day-2')),
        matching: find.text('07:00'),
      );

      await mountAlarm(at: galleryAlarmAt, state: AlarmArmState.storedSeconds);
      await capture('alarm-ready');
      await tester.tap(find.byType(CupertinoSwitch).at(2));
      await tester.pumpAndSettle();
      expect(wednesdayTime(), findsNothing);
      await tester.tap(find.byType(CupertinoSwitch).at(2));
      await tester.pumpAndSettle();
      expect(wednesdayTime(), findsOneWidget);
      await mountAlarm(
        at: galleryAlarmAt,
        state: AlarmArmState.storedSeconds,
        brightness: Brightness.dark,
      );
      await capture('alarm-ready-dark');
      await mountAlarm(at: galleryAlarmAt, state: AlarmArmState.unknown);
      await capture('alarm-light');
      await mountAlarm(
        at: galleryAlarmAt,
        state: AlarmArmState.unknown,
        brightness: Brightness.dark,
      );
      await capture('alarm-dark');
      await mountAlarm(at: galleryAlarmAt, state: AlarmArmState.pending);
      await capture('alarm-pending');
      await mountAlarm(scheduleEnabled: false);
      await capture('alarm-none');
      await mountAlarm(
        at: galleryAlarmAt,
        state: AlarmArmState.allSlotsInactive,
        scheduleEnabled: false,
      );
      await capture('alarm-slots-inactive');
      await mountAlarm(
        at: galleryAlarmAt,
        state: AlarmArmState.allSlotsInactive,
        scheduleEnabled: false,
        brightness: Brightness.dark,
      );
      await capture('alarm-slots-inactive-dark');
      await mountAlarm(
        at: galleryAlarmAt,
        state: AlarmArmState.unknown,
        connected: false,
      );
      await capture('alarm-offline');
      await mountAlarm(
        at: galleryAlarmAt,
        state: AlarmArmState.pending,
        failing: true,
      );
      await tester.tap(find.text('Ausschalten'));
      await tester.pumpAndSettle();
      await capture('alarm-error');
      await mountAlarm(at: galleryAlarmAt, state: AlarmArmState.unknown);
      await tester.tap(find.bySemanticsLabel(RegExp(r'Uhrzeit Mittwoch')));
      await tester.pumpAndSettle();
      await capture('alarm-timepicker');
      await tester.tap(find.text('Abbrechen').first);
      await tester.pumpAndSettle();
      await mountAlarm(
        at: galleryAlarmAt,
        state: AlarmArmState.unknown,
        brightness: Brightness.dark,
      );
      await tester.tap(find.bySemanticsLabel(RegExp(r'Uhrzeit Mittwoch')));
      await tester.pumpAndSettle();
      await capture('alarm-timepicker-dark');
      await tester.tap(find.text('Abbrechen').first);
      await tester.pumpAndSettle();
      await mountAlarm(at: galleryAlarmAt, state: AlarmArmState.storedSeconds);
      await tester.tap(find.bySemanticsLabel(RegExp(r'Uhrzeit Mittwoch')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '88');
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await capture('alarm-timepicker-input');
      await tester.tap(find.text('Abbrechen').first);
      await tester.pumpAndSettle();
      await mountAlarm(
        at: galleryAlarmAt,
        state: AlarmArmState.storedSeconds,
        scale: 2,
      );
      await capture('alarm-large-text');
      await tester.tap(find.bySemanticsLabel(RegExp(r'Uhrzeit Mittwoch')));
      await tester.pumpAndSettle();
      await capture('alarm-timepicker-large');
      await tester.tap(find.text('Abbrechen').first);
      await tester.pumpAndSettle();
      await mountAlarm(
        at: galleryAlarmAt,
        state: AlarmArmState.offPending,
        scheduleEnabled: false,
      );
      await capture('alarm-off-pending');
      await tester.tap(find.text('Erneut ausschalten'));
      await tester.pumpAndSettle();
      await mountAlarm(
        at: galleryAlarmAt,
        state: AlarmArmState.offPending,
        scheduleEnabled: false,
        brightness: Brightness.dark,
      );
      await capture('alarm-off-pending-dark');
      await mountAlarm(
        at: galleryAlarmAt,
        state: AlarmArmState.offPending,
        scheduleEnabled: false,
        connected: false,
      );
      await capture('alarm-off-offline');
      await mountAlarm(
        at: galleryAlarmAt,
        state: AlarmArmState.offPending,
        scheduleEnabled: false,
        failing: true,
      );
      await tester.tap(find.text('Erneut ausschalten'));
      await tester.pumpAndSettle();
      await capture('alarm-off-retry-error');
      Future<void> openNaps() async {
        await tester.tap(find.bySemanticsLabel(RegExp(r'^Schlaf, ')).first);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Nickerchen'),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Nickerchen'));
        await tester.pumpAndSettle();
      }

      await mount();
      await openNaps();
      expect(find.text('14:10–14:42'), findsOneWidget);
      expect(find.text('Erkannt'), findsOneWidget);
      await capture('naps-list');
      await press('Nickerchen ergänzen');
      expect(find.text('Selbst eingetragen'), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('nap-start')), '16:00');
      await tester.enterText(find.byKey(const ValueKey('nap-end')), '16:40');
      await tester.pumpAndSettle();
      expect(find.text('40 Minuten'), findsOneWidget);
      await capture('naps-add');
      await press('Speichern');
      expect(find.text('16:00–16:40'), findsOneWidget);
      expect(find.text('Manuell'), findsOneWidget);
      await tester.tap(find.text('14:10–14:42'));
      await tester.pumpAndSettle();
      await capture('naps-edit');
      await press('Nickerchen entfernen');
      expect(find.text('14:10–14:42 entfernen?'), findsOneWidget);
      await tester.tap(find.text('Entfernen').last);
      await tester.pumpAndSettle();
      expect(find.text('Wiederherstellen'), findsOneWidget);
      await capture('naps-removed');
      await press('Wiederherstellen');
      expect(find.text('Erkannt'), findsOneWidget);

      final napFail = await mount(
        scenario: SyntheticScenario.calculationFailure,
      );
      await openNaps();
      await press('Nickerchen ergänzen');
      await tester.enterText(find.byKey(const ValueKey('nap-start')), '16:00');
      await tester.enterText(find.byKey(const ValueKey('nap-end')), '16:40');
      await press('Speichern');
      expect(find.text('Gespeichert · Auswertung offen'), findsOneWidget);
      expect(find.text('Erneut auswerten'), findsOneWidget);
      expect(find.text('16:00–16:40'), findsOneWidget);
      expect(find.text('—'), findsWidgets);
      expect(find.text('72'), findsNothing);
      await capture('naps-recalc-failure');
      napFail.scenario = SyntheticScenario.complete;
      await press('Erneut auswerten');
      expect(find.text('16:00–16:40'), findsOneWidget);
      await capture('naps-recalc-retry');

      final empty = await mount();
      empty.seedNaps(
        const NapDay(day: '2026-09-15', judged: true, totalMin: 0),
      );
      await openNaps();
      expect(find.text('Keine Nickerchen erkannt'), findsOneWidget);
      await capture('naps-empty');

      final unknown = await mount();
      unknown.seedNaps(const NapDay(day: '2026-09-15'));
      await openNaps();
      expect(find.text('Noch nicht bestimmbar'), findsOneWidget);
      expect(find.text('—'), findsWidgets);
      await capture('naps-unknown');

      await mount(brightness: Brightness.dark);
      await openNaps();
      await capture('naps-dark');
      await press('Nickerchen ergänzen');
      await capture('naps-add-dark');

      await mount(scale: 2);
      await openNaps();
      expect(tester.takeException(), isNull);
      await capture('naps-large-text');
      await press('Nickerchen ergänzen');
      expect(tester.takeException(), isNull);
      await capture('naps-add-large-text');

      Future<void> mountFirstSync({
        Brightness brightness = Brightness.light,
        bool receiving = true,
        SetupEvalState evalState = SetupEvalState.missing,
        bool evalError = false,
        double scale = 1,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            debugShowCheckedModeBanner: false,
            locale: const Locale('de'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            theme: openBandTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: firstSyncGalleryFrame(
              brightness: brightness,
              receiving: receiving,
              evalState: evalState,
              evalError: evalError,
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await mountFirstSync();
      expect(find.text('Auswertung heute'), findsOneWidget);
      expect(find.text('bis 06:54'), findsOneWidget);
      await capture('first-sync-light');
      await tester.tap(find.byTooltip('Information'));
      await tester.pumpAndSettle();
      await capture('first-sync-info');
      await tester.tap(find.text('Schließen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weiter zum Profil'));
      await tester.pumpAndSettle();
      await mountFirstSync(brightness: Brightness.dark);
      await capture('first-sync-dark');
      await mountFirstSync(
        receiving: false,
        evalState: SetupEvalState.complete,
      );
      expect(find.text('07:12'), findsOneWidget);
      await capture('first-sync-complete');
      await mountFirstSync(
        brightness: Brightness.dark,
        evalState: SetupEvalState.partial,
      );
      expect(find.text('Teilweise'), findsOneWidget);
      await capture('first-sync-partial-dark');
      await mountFirstSync(evalError: true);
      expect(find.text('Auswertung nicht geladen'), findsOneWidget);
      await capture('first-sync-read-error');
      await tester.tap(find.text('Erneut'));
      await tester.pumpAndSettle();
      expect(find.text('Auswertung nicht geladen'), findsOneWidget);
      await capture('first-sync-read-error-retry');
      await mountFirstSync(scale: 2);
      expect(find.text('Auswertung heute'), findsOneWidget);
      await capture('first-sync-2x');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      Future<void> revealNotification(Finder target) async {
        final scrollable = find.byType(Scrollable).last;
        if (target.evaluate().isEmpty) {
          tester.state<ScrollableState>(scrollable).position.jumpTo(0);
          await tester.pumpAndSettle();
        }
        await tester.scrollUntilVisible(target, 200, scrollable: scrollable);
        await tester.pumpAndSettle();
      }

      Future<void> mountNotifications({
        required Brightness brightness,
        bool loaded = true,
        bool? granted = true,
        String? saveError,
        String? applyError,
        String? permissionError,
        NotificationPrefs prefs = openBandPaperNotificationPrefs,
        double? scale,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            debugShowCheckedModeBanner: false,
            locale: const Locale('de'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            theme: openBandTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale ?? 1)),
              child: child!,
            ),
            home: NotificationSettingsView(
              synthetic: true,
              loaded: loaded,
              granted: granted,
              prefs: prefs,
              saveError: saveError,
              applyError: applyError,
              permissionError: permissionError,
              onChanged: (_) async {},
              onRequestPermission: () {},
              onRetrySave: saveError == null ? null : () {},
              onRetryApply: applyError == null ? null : () {},
              onRetryPermission: permissionError == null ? null : () {},
            ),
          ),
        );
        if (loaded) {
          await tester.pumpAndSettle();
        } else {
          await tester.pump(const Duration(milliseconds: 350));
        }
      }

      for (final brightness in Brightness.values) {
        await mountNotifications(brightness: brightness);
        await capture('notifications-${brightness.name}');
      }
      await mountNotifications(
        brightness: Brightness.light,
        loaded: false,
        granted: null,
      );
      await capture('notifications-loading');
      await mountNotifications(brightness: Brightness.light, granted: false);
      await capture('notifications-denied');
      await mountNotifications(
        brightness: Brightness.light,
        saveError: 'Speichern fehlgeschlagen',
      );
      await capture('notifications-error');
      await mountNotifications(
        brightness: Brightness.light,
        applyError: 'Gespeichert. Anwenden fehlgeschlagen',
      );
      await capture('notifications-apply-error');
      await mountNotifications(
        brightness: Brightness.dark,
        applyError: 'Gespeichert. Anwenden fehlgeschlagen',
      );
      await capture('notifications-apply-error-dark');
      await mountNotifications(
        brightness: Brightness.light,
        permissionError: 'internal',
      );
      await capture('notifications-permission-unknown');
      await mountNotifications(brightness: Brightness.light);
      await revealNotification(find.byKey(const ValueKey('quiet-start')));
      await tester.tap(find.byKey(const ValueKey('quiet-start')));
      await tester.pumpAndSettle();
      await capture('notifications-quiet-time');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mountNotifications(brightness: Brightness.dark);
      await revealNotification(find.byKey(const ValueKey('quiet-start')));
      await tester.tap(find.byKey(const ValueKey('quiet-start')));
      await tester.pumpAndSettle();
      await capture('notifications-quiet-time-dark');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mountNotifications(brightness: Brightness.light);
      await revealNotification(find.byKey(const ValueKey('quiet-start')));
      await tester.tap(find.byKey(const ValueKey('quiet-start')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '88');
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await capture('notifications-quiet-time-input');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mountNotifications(brightness: Brightness.light, scale: 2);
      await revealNotification(find.byKey(const ValueKey('quiet-start')));
      await tester.tap(find.byKey(const ValueKey('quiet-start')));
      await tester.pumpAndSettle();
      await capture('notifications-quiet-time-large');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mountNotifications(brightness: Brightness.light);
      await revealNotification(find.byKey(const ValueKey('notif-battery')));
      await tester.tap(find.byKey(const ValueKey('notif-battery')));
      await tester.pumpAndSettle();
      await capture('notifications-choice');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mountNotifications(brightness: Brightness.dark);
      await revealNotification(find.byKey(const ValueKey('notif-battery')));
      await tester.tap(find.byKey(const ValueKey('notif-battery')));
      await tester.pumpAndSettle();
      await capture('notifications-choice-dark');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mountNotifications(brightness: Brightness.light, scale: 2);
      await revealNotification(find.byKey(const ValueKey('notif-battery')));
      await tester.tap(find.byKey(const ValueKey('notif-battery')));
      await tester.pumpAndSettle();
      await capture('notifications-choice-large');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      var live = openBandPaperNotificationPrefs;
      final applied = <NotificationPrefs>[];
      var reminders = 0;
      var failSave = false;

      Future<void> mountLive({
        Brightness brightness = Brightness.light,
        double scale = 1,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            debugShowCheckedModeBanner: false,
            locale: const Locale('de'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            theme: openBandTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                alwaysUse24HourFormat: true,
              ),
              child: child!,
            ),
            home: NotificationSettings(
              synthetic: true,
              loadPrefs: () async => live,
              persistPrefs: (prefs) async {
                if (failSave) throw Exception('disk full');
                live = prefs;
              },
              readPermission: () async => true,
              onRefreshReminders: () async => reminders++,
              onArmWater: (prefs) async => applied.add(prefs),
              onRefreshBattery: (prefs) async => applied.add(prefs),
              relaySupported: false,
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      CupertinoSwitch notifSwitch(Key key) {
        return tester.widget<CupertinoSwitch>(
          find.descendant(
            of: find.byKey(key),
            matching: find.byType(CupertinoSwitch),
          ),
        );
      }

      Future<void> tapLiveSwitch(Key key) async {
        final sw = find.descendant(
          of: find.byKey(key),
          matching: find.byType(CupertinoSwitch),
        );
        await revealNotification(sw);
        await tester.pumpAndSettle();
        await tester.tap(sw);
        await tester.pumpAndSettle();
      }

      await mountLive();
      expect(notifSwitch(const ValueKey('notif-health')).value, isTrue);
      final remindersBeforeToggle = reminders;
      await tapLiveSwitch(const ValueKey('notif-health'));
      expect(live.healthEnabled, isFalse);
      expect(notifSwitch(const ValueKey('notif-health')).value, isFalse);
      expect(reminders, greaterThan(remindersBeforeToggle));
      expect(applied, isNotEmpty);
      expect(applied.last.healthEnabled, isFalse);

      await revealNotification(find.byKey(const ValueKey('notif-battery')));
      await tester.tap(find.byKey(const ValueKey('notif-battery')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('notification-choice')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('notification-choice-25')));
      await tester.pumpAndSettle();
      expect(live.batteryAlertPct, 25);
      expect(find.text('25 %'), findsOneWidget);
      expect(applied.last.batteryAlertPct, 25);

      await tester.tap(find.byKey(const ValueKey('notif-battery')));
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('notification-choice-25')))
            .flagsCollection
            .isSelected
            .toBoolOrNull(),
        isTrue,
      );
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('notification-choice-20')))
            .flagsCollection
            .isSelected
            .toBoolOrNull(),
        isNot(true),
      );
      await tester.tapAt(const Offset(20, 150));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('notification-choice')), findsNothing);
      expect(live.batteryAlertPct, 25);

      await revealNotification(
        find.byKey(const ValueKey('notif-water-interval')),
      );
      await tester.tap(find.byKey(const ValueKey('notif-water-interval')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('notification-choice-180')));
      await tester.pumpAndSettle();
      expect(live.waterIntervalMin, 180);
      expect(find.text('3h'), findsOneWidget);
      expect(applied.last.waterIntervalMin, 180);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('quiet-start')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const ValueKey('quiet-start')));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_outlined), findsNothing);
      await tester.enterText(find.byType(TextFormField).first, '21');
      await tester.enterText(find.byType(TextFormField).last, '30');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(live.quietStartMin, 21 * 60 + 30);
      expect(find.text('21:30'), findsOneWidget);
      expect(applied.last.quietStartMin, 21 * 60 + 30);

      await capture('notifications-live');

      failSave = true;
      final remindersBeforeFail = reminders;
      await tapLiveSwitch(const ValueKey('notif-health'));
      expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
      expect(notifSwitch(const ValueKey('notif-health')).value, isFalse);
      expect(live.healthEnabled, isFalse);
      expect(live.batteryAlertPct, 25);
      expect(reminders, remindersBeforeFail);
      await capture('notifications-live-save-failure');
      failSave = false;
      await tester.tap(find.text('Erneut'));
      await tester.pumpAndSettle();
      expect(find.text('Speichern fehlgeschlagen'), findsNothing);
      expect(live.healthEnabled, isTrue);
      expect(notifSwitch(const ValueKey('notif-health')).value, isTrue);
      expect(applied.last.healthEnabled, isTrue);
      expect(reminders, greaterThan(remindersBeforeFail));
      await capture('notifications-live-save-retry');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mountLive(scale: 2);
      expect(find.text('25 %'), findsOneWidget);
      await capture('notifications-live-large');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('quiet-start')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('21:30'), findsOneWidget);
      await capture('notifications-live-large-quiet');

      Future<void> mountAppearance({
        required Brightness brightness,
        AppThemeChoice selected = AppThemeChoice.system,
        String? saveError,
        double? scale,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            debugShowCheckedModeBanner: false,
            locale: const Locale('de'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            theme: openBandTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale ?? 1)),
              child: child!,
            ),
            home: AppearanceSettingsView(
              selected: selected,
              synthetic: true,
              saveError: saveError,
              onSelect: (_) {},
              onRetry: saveError == null ? null : () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await mountAppearance(brightness: Brightness.light);
      expect(find.text('Darstellung'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      await capture('appearance-light');
      await mountAppearance(
        brightness: Brightness.dark,
        selected: AppThemeChoice.dark,
      );
      await capture('appearance-dark');
      await mountAppearance(
        brightness: Brightness.light,
        saveError: 'Speichern fehlgeschlagen',
      );
      expect(find.text('Erneut'), findsOneWidget);
      await capture('appearance-error');
      await mountAppearance(
        brightness: Brightness.dark,
        selected: AppThemeChoice.dark,
        saveError: 'Speichern fehlgeschlagen',
      );
      expect(find.text('Erneut'), findsOneWidget);
      await capture('appearance-error-dark');
      await mountAppearance(brightness: Brightness.light, scale: 2);
      await capture('appearance-large');

      var failAppearance = true;
      var liveTheme = ThemeController.seed(
        AppThemeChoice.system,
        Brightness.light,
        persist: (_) async {
          if (failAppearance) throw Exception('disk full');
          return true;
        },
      );
      try {
        Future<void> mountLiveAppearance() async {
          await tester.pumpWidget(
            ChangeNotifierProvider<ThemeController>.value(
              value: liveTheme,
              child: ListenableBuilder(
                listenable: liveTheme,
                builder: (context, _) => MaterialApp(
                  debugShowCheckedModeBanner: false,
                  locale: const Locale('de'),
                  supportedLocales: AppLocalizations.supportedLocales,
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  theme: openBandTheme(Brightness.light),
                  darkTheme: openBandTheme(Brightness.dark),
                  themeMode: liveTheme.materialThemeMode,
                  themeAnimationDuration: Duration.zero,
                  home: AppearanceSettings(
                    synthetic: true,
                    controller: liveTheme,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        Brightness appearanceThemeBrightness() => Theme.of(
          tester.element(find.byType(AppearanceSettings)),
        ).brightness;

        await mountLiveAppearance();
        await tester.tap(find.byKey(const ValueKey('appearance-choice-dark')));
        await tester.pumpAndSettle();
        expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
        expect(liveTheme.choice, AppThemeChoice.system);
        expect(appearanceThemeBrightness(), Brightness.light);
        await capture('appearance-live-save-failure');
        failAppearance = false;
        await tester.tap(find.text('Erneut'));
        await tester.pumpAndSettle();
        expect(find.text('Speichern fehlgeschlagen'), findsNothing);
        expect(liveTheme.choice, AppThemeChoice.dark);
        expect(liveTheme.effective, Brightness.dark);
        expect(appearanceThemeBrightness(), Brightness.dark);
        await capture('appearance-live-save-retry');

        await tester.tap(
          find.byKey(const ValueKey('appearance-choice-system')),
        );
        await tester.pumpAndSettle();
        expect(liveTheme.choice, AppThemeChoice.system);
        expect(liveTheme.effective, Brightness.light);
        expect(appearanceThemeBrightness(), Brightness.light);
        await capture('appearance-live-system');

        liveTheme.updatePlatformBrightness(Brightness.dark);
        await tester.pumpAndSettle();
        expect(liveTheme.choice, AppThemeChoice.system);
        expect(liveTheme.effective, Brightness.dark);
        expect(appearanceThemeBrightness(), Brightness.dark);
        await capture('appearance-live-system-os-dark');

        final reopenedChoice = liveTheme.choice;
        final previous = liveTheme;
        liveTheme = ThemeController.seed(
          reopenedChoice,
          Brightness.dark,
          persist: (_) async => true,
        );
        previous.dispose();
        await mountLiveAppearance();
        expect(liveTheme.choice, AppThemeChoice.system);
        expect(liveTheme.effective, Brightness.dark);
        expect(appearanceThemeBrightness(), Brightness.dark);
        await capture('appearance-live-reopen');
      } finally {
        liveTheme.dispose();
      }

      Future<void> mountUnits({
        required Brightness brightness,
        UnitSystem selected = UnitSystem.metric,
        String? saveError,
        double? scale,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            debugShowCheckedModeBanner: false,
            locale: const Locale('de'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            theme: openBandTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale ?? 1)),
              child: child!,
            ),
            home: UnitsSettingsView(
              selected: selected,
              synthetic: true,
              saveError: saveError,
              onSelect: (_) {},
              onRetry: saveError == null ? null : () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await mountUnits(brightness: Brightness.light);
      expect(find.text('Einheiten'), findsOneWidget);
      expect(find.text('Metrisch'), findsOneWidget);
      expect(find.text('5,00 km'), findsOneWidget);
      await capture('units-light');
      await mountUnits(
        brightness: Brightness.light,
        selected: UnitSystem.imperial,
      );
      expect(find.text('3,11 mi'), findsOneWidget);
      await capture('units-imperial');
      await mountUnits(
        brightness: Brightness.dark,
        selected: UnitSystem.metric,
      );
      await capture('units-dark');
      await mountUnits(
        brightness: Brightness.dark,
        selected: UnitSystem.imperial,
      );
      await capture('units-imperial-dark');
      await mountUnits(
        brightness: Brightness.light,
        saveError: 'Speichern fehlgeschlagen',
      );
      expect(find.text('Erneut'), findsOneWidget);
      await capture('units-error');
      await mountUnits(
        brightness: Brightness.dark,
        selected: UnitSystem.metric,
        saveError: 'Speichern fehlgeschlagen',
      );
      expect(find.text('Erneut'), findsOneWidget);
      await capture('units-error-dark');
      await mountUnits(brightness: Brightness.light, scale: 2);
      expect(find.text('Entfernung'), findsOneWidget);
      expect(find.text('5,00 km'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('units-preview-stacked')),
        findsOneWidget,
      );
      await capture('units-large');
      await mountUnits(
        brightness: Brightness.dark,
        selected: UnitSystem.metric,
        scale: 2,
      );
      expect(find.text('Entfernung'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('units-preview-stacked')),
        findsOneWidget,
      );
      await capture('units-large-dark');
      await mountUnits(
        brightness: Brightness.light,
        selected: UnitSystem.imperial,
        scale: 2,
      );
      expect(find.text('3,11 mi'), findsOneWidget);
      expect(find.text('8:03 /mi'), findsOneWidget);
      expect(find.text('5′11″'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('units-preview-stacked')),
        findsOneWidget,
      );
      await capture('units-large-imperial');

      var failUnits = true;
      var liveUnits = UnitsController.seed(
        UnitSystem.metric,
        persist: (_) async {
          if (failUnits) throw Exception('disk full');
          return true;
        },
      );
      try {
        Future<void> mountLiveUnits() async {
          await tester.pumpWidget(
            ChangeNotifierProvider<UnitsController>.value(
              key: UniqueKey(),
              value: liveUnits,
              child: ListenableBuilder(
                listenable: liveUnits,
                builder: (context, _) => MaterialApp(
                  debugShowCheckedModeBanner: false,
                  locale: const Locale('de'),
                  supportedLocales: AppLocalizations.supportedLocales,
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  theme: openBandTheme(Brightness.light),
                  darkTheme: openBandTheme(Brightness.dark),
                  themeMode: ThemeMode.light,
                  themeAnimationDuration: Duration.zero,
                  home: UnitsSettings(synthetic: true, controller: liveUnits),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await mountLiveUnits();
        await tester.tap(find.byKey(const ValueKey('units-choice-imperial')));
        await tester.pumpAndSettle();
        expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
        expect(liveUnits.system, UnitSystem.metric);
        expect(find.text('5,00 km'), findsOneWidget);
        await capture('units-live-save-failure');
        failUnits = false;
        await tester.tap(find.text('Erneut'));
        await tester.pumpAndSettle();
        expect(find.text('Speichern fehlgeschlagen'), findsNothing);
        expect(liveUnits.system, UnitSystem.imperial);
        expect(find.text('3,11 mi'), findsOneWidget);
        await capture('units-live-save-retry');

        final reopenedSystem = liveUnits.system;
        final previousUnits = liveUnits;
        liveUnits = UnitsController.seed(
          reopenedSystem,
          persist: (_) async => true,
        );
        previousUnits.dispose();
        await mountLiveUnits();
        expect(liveUnits.system, UnitSystem.imperial);
        expect(find.text('3,11 mi'), findsOneWidget);
        await capture('units-live-reopen');
      } finally {
        liveUnits.dispose();
      }

      await reviewNutritionEntry();
    } finally {
      WidgetController.hitTestWarningShouldBeFatal = previousHitTestPolicy;
      semantics.dispose();
    }
  });
}
