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
import 'package:openstrap_edge/openband/cycle.dart';
import 'package:openstrap_edge/openband/cycle_comparison.dart';
import 'package:openstrap_edge/openband/cycle_gaps.dart';
import 'package:openstrap_edge/openband/cycle_measurements.dart';
import 'package:openstrap_edge/openband/cycle_medians.dart';
import 'package:openstrap_edge/openband/cycle_observations.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/exercise_definition_editor.dart';
import 'package:openstrap_edge/openband/exercise_picker.dart';
import 'package:openstrap_edge/openband/glucose.dart';
import 'package:openstrap_edge/openband/health.dart';
import 'package:openstrap_edge/openband/journal.dart';
import 'package:openstrap_edge/openband/night_scalar_detail.dart';
import 'package:openstrap_edge/openband/night_signals.dart';
import 'package:openstrap_edge/openband/medication.dart';
import 'package:openstrap_edge/openband/meal_entry.dart';
import 'package:openstrap_edge/openband/nutrition.dart';
import 'package:openstrap_edge/openband/nutrition_browser.dart';
import 'package:openstrap_edge/openband/screens.dart';
import 'package:openstrap_edge/openband/settings_controls.dart';
import 'package:openstrap_edge/openband/sleep_editor.dart';
import 'package:openstrap_edge/openband/sleep_goal.dart';
import 'package:openstrap_edge/openband/sleep_plan.dart';
import 'package:openstrap_edge/openband/strength_live.dart';
import 'package:openstrap_edge/openband/template_editor.dart';
import 'package:openstrap_edge/openband/water.dart';
import 'package:openstrap_edge/openband/vo2.dart';
import 'package:openstrap_edge/openband/weight.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/theme/theme_controller.dart';
import 'package:openstrap_edge/state/units_controller.dart';
import 'package:openstrap_edge/ui2/app_shell.dart';
import 'package:openstrap_edge/ui2/onboarding/welcome.dart';
import 'package:openstrap_edge/ui2/onboarding/pairing.dart';
import 'package:openstrap_edge/ui2/onboarding/first_sync.dart';
import 'package:openstrap_edge/ui2/pairing/device_picker.dart';
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

/// Header back on the current route. Sleep keeps that control in the
/// scrollable, so the finder is scrolled on-screen before the tap.
Future<void> reviewTapHeaderBack(WidgetTester tester) async {
  await reviewPumpPageTransitions(tester);
  final back = find.byTooltip('Zurück');
  if (back.evaluate().isEmpty) {
    final scrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable &&
          axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
    );
    await tester.scrollUntilVisible(back, -300, scrollable: scrollable.last);
  }
  await tester.ensureVisible(back.last);
  await tester.pump();
  await tester.tap(back.last);
  await reviewPumpPageTransitions(tester);
}

Future<void> reviewMountImportReceipt(
  WidgetTester tester,
  ImportOutcome outcome, {
  Brightness brightness = Brightness.light,
  double scale = 1,
}) async {
  final canvas = OB(brightness == Brightness.dark).canvas;
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
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        backgroundColor: canvas,
        body: SafeArea(
          child: ListView(
            key: const ValueKey('import-receipt-scroll'),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              OBPageHeader(
                title: 'Datenimport',
                subtitle: '',
                onBack: () {},
              ),
              ImportReport(outcome),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
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

  _NutritionReviewRepo(super.summary, super.detail, {super.activity, super.run})
    : super.fromMaps();

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

/// One-shot read failure after a committed VO2 write, and one-shot loss of a
/// create response after that create is already stored. A retry commit does
/// not arm another failure and does not append a revision.
class _Vo2ReviewRepo extends SyntheticOpenBandRepository {
  int creates = 0;
  int edits = 0;
  int removes = 0;
  int restores = 0;
  bool failReadAfterCommit = false;
  bool loseNextCreateResponse = false;
  String? lostCreateId;
  bool _failNextRead = false;
  DateTime clock = DateTime(2026, 9, 15, 9, 41);

  _Vo2ReviewRepo(super.summary, super.detail, {super.activity, super.run})
    : super.fromMaps() {
    vo2Now = () => clock;
  }

  void _noteCommit(Vo2WriteResult result) {
    if (failReadAfterCommit && result is Vo2Committed && !result.retry) {
      _failNextRead = true;
    }
  }

  Future<T> _readOrFail<T>(Future<T> Function() read) {
    if (_failNextRead) {
      _failNextRead = false;
      return Future<T>.error(StateError('synthetic vo2 read failure'));
    }
    return read();
  }

  @override
  Future<Vo2List> readVo2Entries() => _readOrFail(() => super.readVo2Entries());

  @override
  Future<Vo2Detail> readVo2Entry(String id) =>
      _readOrFail(() => super.readVo2Entry(id));

  @override
  Future<Vo2WriteResult> createVo2Entry({
    required String id,
    required String measuredOn,
    required double valueMlKgMin,
    String? declaredMethod,
  }) async {
    creates++;
    final result = await super.createVo2Entry(
      id: id,
      measuredOn: measuredOn,
      valueMlKgMin: valueMlKgMin,
      declaredMethod: declaredMethod,
    );
    if (loseNextCreateResponse) {
      loseNextCreateResponse = false;
      if (result is Vo2Committed && !result.retry) {
        lostCreateId = result.revision.id;
        throw StateError('synthetic vo2 create response lost');
      }
    }
    _noteCommit(result);
    return result;
  }

  @override
  Future<Vo2WriteResult> editVo2Entry({
    required String id,
    required int expectedRevision,
    required String measuredOn,
    required double valueMlKgMin,
    String? declaredMethod,
  }) async {
    edits++;
    final result = await super.editVo2Entry(
      id: id,
      expectedRevision: expectedRevision,
      measuredOn: measuredOn,
      valueMlKgMin: valueMlKgMin,
      declaredMethod: declaredMethod,
    );
    _noteCommit(result);
    return result;
  }

  @override
  Future<Vo2WriteResult> removeVo2Entry({
    required String id,
    required int expectedRevision,
  }) async {
    removes++;
    final result = await super.removeVo2Entry(
      id: id,
      expectedRevision: expectedRevision,
    );
    _noteCommit(result);
    return result;
  }

  @override
  Future<Vo2WriteResult> restoreVo2Entry({
    required String id,
    required int expectedRevision,
  }) async {
    restores++;
    final result = await super.restoreVo2Entry(
      id: id,
      expectedRevision: expectedRevision,
    );
    _noteCommit(result);
    return result;
  }
}

Future<_Vo2ReviewRepo> _loadVo2ReviewRepo() async {
  Future<Map> load(String name) async =>
      jsonDecode(
            await rootBundle.loadString(
              'docs/openband5/assets/fixtures/$name.json',
            ),
          )
          as Map;
  final repo = _Vo2ReviewRepo(
    await load('day-summary'),
    await load('sleep-detail'),
    activity: await load('additional-flows'),
    run: await load('run-detail'),
  );
  await repo.seedNutritionGoals();
  repo.seedCaffeineSleepPattern('2026-09-15');
  return repo;
}

/// Paper history: 42.0 on 14 Sept, created at 09:40 with no method, then the
/// same id edited at 09:41 to Spiroergometrie.
Future<_Vo2ReviewRepo> _vo2HistoryFixture() async {
  final repo = await _loadVo2ReviewRepo();
  repo.clock = DateTime(2026, 9, 15, 9, 40);
  final created = await repo.createVo2Entry(
    id: kSyntheticVo2PaperId,
    measuredOn: kSyntheticVo2PaperDay,
    valueMlKgMin: kSyntheticVo2PaperValue,
  );
  if (created is! Vo2Committed ||
      created.retry ||
      created.revision.revision != 1 ||
      created.revision.declaredMethod != null) {
    throw StateError('VO2 history create did not store revision 1.');
  }
  repo.clock = DateTime(2026, 9, 15, 9, 41);
  final edited = await repo.editVo2Entry(
    id: kSyntheticVo2PaperId,
    expectedRevision: 1,
    measuredOn: kSyntheticVo2PaperDay,
    valueMlKgMin: kSyntheticVo2PaperValue,
    declaredMethod: kSyntheticVo2PaperMethod,
  );
  if (edited is! Vo2Committed ||
      edited.retry ||
      edited.revision.revision != 2 ||
      edited.revision.id != kSyntheticVo2PaperId ||
      edited.revision.declaredMethod != kSyntheticVo2PaperMethod) {
    throw StateError('VO2 history edit did not store revision 2.');
  }
  return repo;
}

class _NutritionParentReviewRepo extends _NutritionReviewRepo {
  bool failWeekRead = false;
  bool failRecentRead = false;
  bool failWaterWrite = false;
  bool conflictWaterWrite = false;
  bool failDraftWrite = false;
  int? failJournalReadAfter;
  int waterAdjusts = 0;
  int journalReads = 0;
  int weekReads = 0;
  int recentReads = 0;

  _NutritionParentReviewRepo(
    super.summary,
    super.detail, {
    super.activity,
    super.run,
  });

  @override
  Future<JournalDaySnapshot> readJournalDay(String day) async {
    journalReads++;
    if (failJournalReadAfter != null && journalReads > failJournalReadAfter!) {
      throw StateError('synthetic journal refresh failure');
    }
    return super.readJournalDay(day);
  }

  @override
  Future<double?> adjustWater(String day, double deltaMl) async {
    waterAdjusts++;
    if (failWaterWrite) {
      throw StateError('synthetic water adjust failure');
    }
    return super.adjustWater(day, deltaMl);
  }

  @override
  Future<void> patchJournalDay(JournalDayPatch patch) async {
    if (conflictWaterWrite) {
      throw JournalConflict(patch.day, fields: const ['water_ml']);
    }
    if (failWaterWrite) {
      throw StateError('synthetic water patch failure');
    }
    return super.patchJournalDay(patch);
  }

  @override
  Future<NutritionWindow> readNutritionWindow(
    String endDay, {
    int days = 7,
  }) async {
    weekReads++;
    if (failWeekRead) {
      throw StateError('synthetic week read failure');
    }
    return super.readNutritionWindow(endDay, days: days);
  }

  @override
  Future<List<FoodEntry>> readRecentFoods({int limit = 12}) async {
    recentReads++;
    if (failRecentRead) {
      throw StateError('synthetic recent read failure');
    }
    return super.readRecentFoods(limit: limit);
  }

  @override
  Future<MealDraftSaveResult> compareAndSaveMealDraft({
    required MealDraft? expected,
    required MealDraft draft,
  }) async {
    if (failDraftWrite) {
      throw StateError('synthetic meal draft write failure');
    }
    return super.compareAndSaveMealDraft(expected: expected, draft: draft);
  }
}

Future<_NutritionParentReviewRepo> _loadNutritionParentReviewRepo() async {
  Future<Map> load(String name) async =>
      jsonDecode(
            await rootBundle.loadString(
              'docs/openband5/assets/fixtures/$name.json',
            ),
          )
          as Map;
  final repo = _NutritionParentReviewRepo(
    await load('day-summary'),
    await load('sleep-detail'),
    activity: await load('additional-flows'),
    run: await load('run-detail'),
  );
  await repo.seedNutritionGoals();
  return repo;
}

class _SleepPlanReviewRepo extends SyntheticOpenBandRepository {
  _SleepPlanReviewRepo(super.summary, super.detail, {super.activity, super.run})
    : super.fromMaps();

  final requestedDays = <String>[];
  final clocks = <DateTime?>[];

  @override
  Future<SleepPlanSnapshot> readSleepPlan(String day, {DateTime? now}) async {
    requestedDays.add(day);
    clocks.add(now);
    return super.readSleepPlan(day, now: now);
  }
}

const _kExercisePickerPresetIds = <String>[
  'bench_press',
  'leg_press',
  'cable_fly',
  'pull_up',
  'plank',
];

const _kUnknownImportedExerciseId = 'imported-unknown';
const _kUnknownImportedExerciseLabel = 'Rudern am Gerät';

ExercisePreset _pickerPreset(String id) {
  final preset = exercisePresetById(id);
  if (preset == null) {
    throw StateError('Missing exercise preset $id');
  }
  return preset;
}

List<ExercisePreset> _pickerPresets() => [
  for (final id in _kExercisePickerPresetIds) _pickerPreset(id),
];

List<String> _pickerLabelsAlphabetical() {
  final labels = [for (final preset in _pickerPresets()) preset.labelDe];
  labels.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return labels;
}

class _ExercisePickerReviewRepo extends SyntheticOpenBandRepository {
  _ExercisePickerReviewRepo(
    super.summary,
    super.detail, {
    super.activity,
    super.run,
  }) : super.fromMaps();

  bool failCatalogueRead = false;
  int unreadableCount = 0;
  bool includeUnknownMode = false;
  int catalogueReads = 0;
  int templateSaves = 0;

  @override
  Future<ExerciseCatalogue> readExerciseCatalogue() async {
    catalogueReads++;
    if (failCatalogueRead) {
      throw StateError('synthetic exercise catalogue read failure');
    }
    final entries = <ExerciseCatalogueEntry>[
      for (final preset in _pickerPresets()) preset.asEntry,
      if (includeUnknownMode)
        ExerciseCatalogueEntry(
          id: _kUnknownImportedExerciseId,
          label: _kUnknownImportedExerciseLabel,
          source: ExerciseDefinitionSource.stored,
          equipment: ExerciseEquipmentCategory.machine,
        ),
    ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return ExerciseCatalogue(
      entries: entries,
      unreadableCount: unreadableCount,
    );
  }

  @override
  Future<WorkoutTemplate> saveTemplate(WorkoutTemplate template) async {
    templateSaves++;
    return super.saveTemplate(template);
  }
}

class _CustomExerciseReviewRepo extends SyntheticOpenBandRepository {
  _CustomExerciseReviewRepo(
    super.summary,
    super.detail, {
    super.activity,
    super.run,
  }) : super.fromMaps();

  bool failNextCreate = false;
  int createCalls = 0;
  int templateSaves = 0;
  final draftIds = <String?>[];
  CustomExerciseWriteResult? lastCreate;

  @override
  Future<ExerciseCatalogue> readExerciseCatalogue() async {
    final stored = await super.readExerciseCatalogue();
    final byId = <String, ExerciseCatalogueEntry>{
      for (final preset in _pickerPresets()) preset.id: preset.asEntry,
    };
    for (final entry in stored.entries) {
      if (entry.source == ExerciseDefinitionSource.stored) {
        byId[entry.id] = entry;
      }
    }
    final entries = byId.values.toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return ExerciseCatalogue(entries: entries);
  }

  @override
  Future<CustomExerciseWriteResult> createCustomExercise(
    CustomExerciseDraft draft,
  ) async {
    createCalls++;
    draftIds.add(draft.id);
    if (failNextCreate) {
      failNextCreate = false;
      throw StateError('synthetic custom exercise create failure');
    }
    final result = await super.createCustomExercise(draft);
    lastCreate = result;
    return result;
  }

  @override
  Future<WorkoutTemplate> saveTemplate(WorkoutTemplate template) async {
    templateSaves++;
    return super.saveTemplate(template);
  }
}

class _GlucoseReviewRepo extends SyntheticOpenBandRepository {
  _GlucoseReviewRepo(super.summary, super.detail, {super.activity, super.run})
    : super.fromMaps();

  bool partialGlucose = false;

  @override
  Future<GlucoseSnapshot> readGlucose({String? sourceKey, int? limit}) async {
    final snap = await super.readGlucose(sourceKey: sourceKey, limit: limit);
    if (!partialGlucose) return snap;
    return GlucoseSnapshot(
      selected: snap.selected,
      selectedExcluded: snap.selectedExcluded,
      sources: snap.sources,
      history: snap.history,
      series: snap.series,
      attempt: GlucoseAttempt(
        status: HealthMeasurementImportStatus.partial,
        attemptedAt: snap.attempt.attemptedAt,
        storedCount: snap.attempt.storedCount,
        writtenCount: snap.attempt.writtenCount,
        invalidCount: 2,
        ignoredCount: 1,
      ),
      lastMeasuredAt: snap.lastMeasuredAt,
      lastImportedAt: snap.lastImportedAt,
      truncated: snap.truncated,
      unreadableCount: snap.unreadableCount,
    );
  }
}

class _MedicationReviewRepo extends SyntheticOpenBandRepository {
  _MedicationReviewRepo(
    super.summary,
    super.detail, {
    super.activity,
    super.run,
  }) : super.fromMaps();

  MedicationDay Function(MedicationDay)? transformDay;
  MedicationHistory Function(MedicationHistory)? transformHistory;
  List<MedicationPlan> Function(List<MedicationPlan>)? transformPlans;
  bool failHistoryAfterFirst = false;
  int historyReads = 0;
  int entrySaves = 0;
  int reminderRefreshes = 0;

  @override
  Future<MedicationDay> readMedicationDay(String day, {DateTime? now}) async {
    final snap = await super.readMedicationDay(day, now: now);
    return transformDay?.call(snap) ?? snap;
  }

  @override
  Future<List<MedicationPlan>> readMedicationPlans({
    bool activeOnly = true,
  }) async {
    final plans = await super.readMedicationPlans(activeOnly: activeOnly);
    return transformPlans?.call(plans) ?? plans;
  }

  @override
  Future<MedicationHistory> readMedicationHistory(
    String fromDay,
    String toDay, {
    DateTime? now,
  }) async {
    historyReads++;
    if (failHistoryAfterFirst && historyReads > 1) {
      throw StateError('synthetic medication history paging failure');
    }
    final hist = await super.readMedicationHistory(fromDay, toDay, now: now);
    return transformHistory?.call(hist) ?? hist;
  }

  @override
  Future<MedicationMutationResult> saveMedicationEntry(
    MedicationEntryDraft draft, {
    DateTime? now,
  }) async {
    entrySaves++;
    return super.saveMedicationEntry(draft, now: now);
  }

  @override
  Future<void> refreshMedicationReminders() async {
    reminderRefreshes++;
    return super.refreshMedicationReminders();
  }
}

class _CycleReviewRepo extends SyntheticOpenBandRepository {
  _CycleReviewRepo(super.summary, super.detail, {super.activity, super.run})
    : super.fromMaps();

  int startWrites = 0;
  int observationWrites = 0;
  int settingsWrites = 0;
  int settingsReads = 0;
  int startRemoves = 0;
  int startRestores = 0;
  int contextRefreshes = 0;
  int measurementsReads = 0;
  bool failCycleSettingsRead = false;
  bool failCycleLogRead = false;

  @override
  Future<CycleSettings> readCycleSettings() async {
    settingsReads++;
    if (failCycleSettingsRead) {
      throw StateError('synthetic cycle settings read failure');
    }
    return super.readCycleSettings();
  }

  @override
  Future<CycleSnapshot> readCycle(String day, {DateTime? now}) async {
    if (failCycleLogRead) {
      throw StateError('synthetic cycle log read failure');
    }
    return super.readCycle(day, now: now);
  }

  @override
  Future<CycleMeasurementsSnapshot> readCycleMeasurements(
    String asOfDay, {
    String? cycleStartDay,
  }) async {
    measurementsReads++;
    return super.readCycleMeasurements(asOfDay, cycleStartDay: cycleStartDay);
  }

  @override
  Future<CycleWriteResult> saveCycleSettings(CycleSettings settings) async {
    settingsWrites++;
    return super.saveCycleSettings(settings);
  }

  @override
  Future<CycleWriteResult> saveCycleStart(
    CycleStart desired, {
    CycleStart? expected,
    DateTime? now,
  }) async {
    startWrites++;
    return super.saveCycleStart(desired, expected: expected, now: now);
  }

  @override
  Future<CycleWriteResult> removeCycleStart(CycleStart expected) async {
    startRemoves++;
    return super.removeCycleStart(expected);
  }

  @override
  Future<CycleWriteResult> restoreCycleStart(
    CycleStart removed, {
    DateTime? now,
  }) async {
    startRestores++;
    return super.restoreCycleStart(removed, now: now);
  }

  @override
  Future<CycleWriteResult> saveCycleObservation(
    CycleObservation desired, {
    CycleObservation? expected,
    DateTime? now,
  }) async {
    observationWrites++;
    return super.saveCycleObservation(desired, expected: expected, now: now);
  }

  @override
  Future<void> refreshCycleContext() async {
    contextRefreshes++;
    return super.refreshCycleContext();
  }
}

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

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final frames = <Map<String, Object?>>[];
  final captureFilter = reviewCaptureFilter(kOpenBandReviewCaptures);
  final capturedNames = <String>{};

  testWidgets('native first-flow visual review with isolated synthetic data', (
    tester,
  ) async {
    if (kOpenBandReviewFlow != 'all' &&
        kOpenBandReviewFlow != 'correction' &&
        kOpenBandReviewFlow != 'journal' &&
        kOpenBandReviewFlow != 'journal-hub' &&
        kOpenBandReviewFlow != 'nutrition-entry' &&
        kOpenBandReviewFlow != 'nutrition-parent' &&
        kOpenBandReviewFlow != 'sleep-plan' &&
        kOpenBandReviewFlow != 'exercise-picker' &&
        kOpenBandReviewFlow != 'custom-exercise' &&
        kOpenBandReviewFlow != 'exercise-copy' &&
        kOpenBandReviewFlow != 'custom-load' &&
        kOpenBandReviewFlow != 'glucose' &&
        kOpenBandReviewFlow != 'medications' &&
        kOpenBandReviewFlow != 'cycle' &&
        kOpenBandReviewFlow != 'cycle-measurements' &&
        kOpenBandReviewFlow != 'cycle-observations' &&
        kOpenBandReviewFlow != 'cycle-gaps' &&
        kOpenBandReviewFlow != 'cycle-medians' &&
        kOpenBandReviewFlow != 'cycle-comparison' &&
        kOpenBandReviewFlow != 'night-scalar' &&
        kOpenBandReviewFlow != 'night-cards' &&
        kOpenBandReviewFlow != 'sleep-legend' &&
        kOpenBandReviewFlow != 'respiration' &&
        kOpenBandReviewFlow != 'temperature' &&
        kOpenBandReviewFlow != 'weight' &&
        kOpenBandReviewFlow != 'vo2' &&
        kOpenBandReviewFlow != 'release') {
      throw StateError(
        'Unknown OPENBAND_REVIEW_FLOW: $kOpenBandReviewFlow '
        '(expected all, correction, journal, journal-hub, nutrition-entry, nutrition-parent, sleep-plan, exercise-picker, custom-exercise, exercise-copy, custom-load, glucose, medications, cycle, cycle-measurements, cycle-observations, cycle-gaps, cycle-medians, cycle-comparison, night-scalar, night-cards, sleep-legend, respiration, temperature, weight, vo2, or release)',
      );
    }
    await initializeDateFormatting('de_DE');
    final semantics = tester.ensureSemantics();
    final previousHitTestPolicy = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    var flowFailed = false;
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
        bool release = false,
        bool failRead = false,
      }) async {
        final repository = await loadGalleryRepository();
        repository.scenario = scenario;
        repository.failDayRead = failRead;
        await tester.pumpWidget(
          OpenBandGallery(
            key: UniqueKey(),
            repository: repository,
            showControls: false,
            initialBrightness: brightness,
            initialTextScale: scale,
            releaseReduced: release,
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
        if (captureFilter != null && !captureFilter.contains(name)) {
          return;
        }
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
              if (error.message != 'synthetic caffeine sleep pattern failure') {
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

      Future<void> reviewJournal() async {
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

      Future<void> reviewVo2() async {
        const day = '2026-09-15';
        final now = DateTime(2026, 9, 15, 9, 41);
        final measured = kSyntheticVo2PaperDay;
        String shortDate(String value) {
          final date = DateTime.parse(value);
          return DateFormat(
            date.year == now.year ? 'd. MMM' : 'd. MMM y',
            'de_DE',
          ).format(date);
        }

        const measuredShort = '14. Sept.';
        final paperValue = obNumber(kSyntheticVo2PaperValue, digits: 1);
        final paperLine = '$measuredShort · $kSyntheticVo2PaperMethod';
        final healthValue = '$paperValue $kVo2Unit';
        final healthWhen = 'Eingetragen · $measuredShort';

        Future<_Vo2ReviewRepo> mountVo2({
          Brightness brightness = Brightness.light,
          double scale = 1,
          _Vo2ReviewRepo? repository,
          bool seed = true,
          bool readError = false,
        }) async {
          final mounted = repository ?? await _loadVo2ReviewRepo();
          if (seed) mounted.seedVo2Paper();
          mounted.failVo2Read = readError;
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
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: OpenBandVo2(
                repository: mounted,
                endDay: day,
                now: () => now,
              ),
            ),
          );
          await tester.pumpAndSettle();
          return mounted;
        }

        Finder pageScroll() => find.descendant(
          of: find.byKey(const ValueKey('vo2-scroll')),
          matching: find.byType(Scrollable),
        );

        Future<void> show(Finder target, {Finder? scrollable}) async {
          var scroll = scrollable ?? pageScroll();
          final matches = scroll.evaluate();
          if (matches.length > 1) {
            final outer = {
              for (final element in matches)
                if (element.findAncestorWidgetOfExactType<EditableText>() ==
                    null)
                  element,
            };
            scroll = find.byElementPredicate(outer.contains);
          }
          if (scroll.evaluate().isNotEmpty) {
            await tester.scrollUntilVisible(target, 200, scrollable: scroll);
          }
          await tester.ensureVisible(target);
          await tester.pump();
        }

        String? heroText() => tester.widget<Text>(
          find.descendant(
            of: find.byKey(const ValueKey('vo2-hero-value')),
            matching: find.byType(Text),
            matchRoot: true,
          ),
        ).data;

        String fieldText(String key) => tester
            .widget<TextField>(find.byKey(ValueKey(key)))
            .controller!
            .text;

        Future<void> openEditor() async {
          final hero = find.byKey(const ValueKey('vo2-hero-edit'));
          await show(hero);
          await tester.tap(hero);
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('vo2-editor')), findsOneWidget);
        }

        Future<void> saveEditor() async {
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();
          final save = find.byKey(const ValueKey('vo2-save'));
          await tester.ensureVisible(save);
          await tester.tap(save);
          await tester.pumpAndSettle();
        }

        final healthRepository = await _loadVo2ReviewRepo();
        healthRepository.seedVo2Paper();
        final healthController = OpenBandController(
          repository: healthRepository,
          initialDay: day,
          now: () => now,
        );
        await healthController.refresh();
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            debugShowCheckedModeBanner: false,
            locale: const Locale('de'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            theme: openBandTheme(
              Brightness.light,
            ).copyWith(platform: TargetPlatform.iOS),
            home: Scaffold(
              body: SafeArea(
                child: OpenBandHealth(controller: healthController),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final healthRow = find.byKey(const ValueKey('vo2-health-row'));
        await tester.scrollUntilVisible(
          healthRow,
          200,
          scrollable: verticalScrollable().last,
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: healthRow, matching: find.text('VO₂max')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: healthRow, matching: find.text(healthWhen)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: healthRow, matching: find.text(healthValue)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: healthRow,
            matching: find.text('Eintrag nicht lesbar'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: healthRow,
            matching: find.textContaining('Teilweise lesbar'),
          ),
          findsNothing,
        );
        await capture('vo2-health-entry');
        await tester.tap(healthRow);
        await tester.pumpAndSettle();
        expect(find.byType(OpenBandVo2), findsOneWidget);
        expect(
          heroText(),
          paperValue,
        );
        expect(find.text(paperLine), findsOneWidget);
        await capture('vo2-health-detail');
        await openEditor();
        expect(fieldText('vo2-value-input'), '42');
        await tester.enterText(
          find.byKey(const ValueKey('vo2-value-input')),
          '42,5',
        );
        await saveEditor();
        expect(find.byType(OpenBandVo2), findsOneWidget);
        await reviewTapHeaderBack(tester);
        await tester.pumpAndSettle();
        final refreshed = '${obNumber(42.5, digits: 1)} $kVo2Unit';
        expect(
          find.descendant(of: healthRow, matching: find.text(refreshed)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: healthRow, matching: find.text(healthWhen)),
          findsOneWidget,
        );
        await capture('vo2-health-refreshed');
        await tester.tap(healthRow);
        await tester.pumpAndSettle();
        healthRepository.failVo2Read = true;
        await reviewTapHeaderBack(tester);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: healthRow,
            matching: find.text('Laden fehlgeschlagen'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: healthRow, matching: find.text(refreshed)),
          findsNothing,
        );
        await capture('vo2-health-refresh-error');
        healthRepository.failVo2Read = false;

        final overview = await mountVo2();
        healthController.dispose();
        expect(
          heroText(),
          paperValue,
        );
        expect(find.text(paperLine), findsOneWidget);
        expect(
          find.byKey(ValueKey('vo2-entry-$kSyntheticVo2PaperId')),
          findsOneWidget,
        );
        await capture('vo2-light');
        await tester.tap(find.byTooltip('Über VO₂max'));
        await tester.pumpAndSettle();
        expect(find.text('Über VO₂max'), findsOneWidget);
        expect(
          find.text('Quelle: Eigener Eintrag · ml/kg/min'),
          findsOneWidget,
        );
        expect(find.text('Datum und Methode: laut Eingabe.'), findsOneWidget);
        expect(
          find.text('Einordnung: kein Referenzbereich hinterlegt.'),
          findsOneWidget,
        );
        await capture('vo2-info');
        await tester.tap(find.text('Schließen'));
        await tester.pumpAndSettle();

        await mountVo2(brightness: Brightness.dark);
        expect(find.text(paperLine), findsOneWidget);
        await capture('vo2-dark');

        await mountVo2(repository: overview, seed: false);
        await openEditor();
        expect(fieldText('vo2-value-input'), '42');
        expect(fieldText('vo2-method-input'), kSyntheticVo2PaperMethod);
        await capture('vo2-edit');
        await tester.tap(find.byTooltip('Schließen'));
        await tester.pumpAndSettle();

        final blank = await mountVo2(seed: false);
        expect(find.text('Noch keine Einträge'), findsOneWidget);
        expect(find.text('Einträge konnten nicht geladen werden.'), findsNothing);
        expect(find.byKey(const ValueKey('vo2-add-empty')), findsOneWidget);
        await capture('vo2-empty');
        await tester.tap(find.byKey(const ValueKey('vo2-add-empty')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('vo2-editor')), findsOneWidget);
        expect(fieldText('vo2-value-input'), isEmpty);
        expect(fieldText('vo2-method-input'), isEmpty);
        expect(find.byKey(const ValueKey('vo2-remove')), findsNothing);
        await capture('vo2-new');
        await tester.enterText(
          find.byKey(const ValueKey('vo2-value-input')),
          '42',
        );
        await tester.enterText(
          find.byKey(const ValueKey('vo2-method-input')),
          kSyntheticVo2PaperMethod,
        );
        await tester.tap(find.byKey(const ValueKey('vo2-date-input')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('vo2-calendar')), findsOneWidget);
        expect(find.byType(DatePickerDialog), findsNothing);
        final day14 = DateTime(2026, 9, 14);
        final dayLabel = DateFormat(
          'EEEE, d. MMMM yyyy',
          'de_DE',
        ).format(day14);
        final calendarScroll = find.descendant(
          of: find.byKey(const ValueKey('vo2-calendar')),
          matching: find.byType(Scrollable),
        );
        final dayTarget = find.bySemanticsLabel(dayLabel);
        await tester.scrollUntilVisible(
          dayTarget,
          120,
          scrollable: calendarScroll,
        );
        await tester.tap(dayTarget);
        await tester.pumpAndSettle();
        await show(
          find.byKey(const ValueKey('vo2-date-apply')),
          scrollable: calendarScroll,
        );
        await capture('vo2-date');
        await tester.tap(find.byKey(const ValueKey('vo2-date-apply')));
        await tester.pumpAndSettle();
        expect(
          find.text(DateFormat('d. MMMM y', 'de_DE').format(day14)),
          findsOneWidget,
        );
        await saveEditor();
        expect(
          heroText(),
          paperValue,
        );
        expect(find.text(paperLine), findsOneWidget);
        final savedRow = find.byWidgetPredicate((widget) {
          final key = widget.key;
          return key is ValueKey<String> && key.value.startsWith('vo2-entry-');
        });
        expect(savedRow, findsOneWidget);
        final savedId =
            (tester.widget(savedRow).key! as ValueKey<String>).value.substring(
              'vo2-entry-'.length,
            );
        final saved = await blank.readVo2Entry(savedId);
        expect(saved.head?.measuredOn, measured);
        expect(saved.head?.valueMlKgMin, kSyntheticVo2PaperValue);
        expect(saved.head?.declaredMethod, kSyntheticVo2PaperMethod);
        expect(saved.head?.id, savedId);
        await capture('vo2-saved');

        final history = await _vo2HistoryFixture();
        await mountVo2(repository: history, seed: false);
        await openEditor();
        final changes = find.byKey(const ValueKey('vo2-history'));
        await show(
          changes,
          scrollable: find.descendant(
            of: find.byKey(const ValueKey('vo2-editor')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.tap(changes);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('vo2-history-page')), findsOneWidget);
        final at0940 = DateTime(2026, 9, 15, 9, 40);
        final at0941 = DateTime(2026, 9, 15, 9, 41);
        String stamp(DateTime time) =>
            '${shortDate(dayLabelOf(time))} · ${DateFormat('HH:mm', 'de_DE').format(time)}';
        expect(find.text(stamp(at0941)), findsOneWidget);
        expect(find.text(stamp(at0940)), findsOneWidget);
        expect(
          find.text('Wert vom ${shortDate(measured)} · $kSyntheticVo2PaperMethod'),
          findsOneWidget,
        );
        expect(
          find.text('Wert vom ${shortDate(measured)} · Methode \u2014'),
          findsOneWidget,
        );
        await capture('vo2-revisions');
        await reviewTapHeaderBack(tester);

        final removable = await mountVo2();
        await openEditor();
        final remove = find.byKey(const ValueKey('vo2-remove'));
        await tester.ensureVisible(remove);
        await tester.tap(remove);
        await tester.pumpAndSettle();
        expect(find.text('Entfernt'), findsOneWidget);
        expect(
          find.byKey(ValueKey('vo2-removed-$kSyntheticVo2PaperId')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('vo2-entry-$kSyntheticVo2PaperId')),
          findsNothing,
        );
        await capture('vo2-removed-section');
        await tester.tap(
          find.byKey(ValueKey('vo2-removed-$kSyntheticVo2PaperId')),
        );
        await tester.pumpAndSettle();
        final removedPage = find.ancestor(
          of: find.byKey(const ValueKey('vo2-restore')),
          matching: find.byType(Scaffold),
        );
        Finder onRemoved(Finder match) =>
            find.descendant(of: removedPage, matching: match);
        expect(onRemoved(find.text('Entfernt')), findsOneWidget);
        expect(onRemoved(find.text(paperValue)), findsOneWidget);
        expect(onRemoved(find.text(paperLine)), findsOneWidget);
        expect(find.byKey(const ValueKey('vo2-restore')), findsOneWidget);
        await capture('vo2-removed');
        await tester.tap(find.byKey(const ValueKey('vo2-restore')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('vo2-entry-$kSyntheticVo2PaperId')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('vo2-removed-$kSyntheticVo2PaperId')),
          findsNothing,
        );
        final restored = await removable.readVo2Entry(kSyntheticVo2PaperId);
        expect(restored.head?.id, kSyntheticVo2PaperId);
        expect(restored.head?.deleted, isFalse);
        await capture('vo2-restored');

        final failingRead = await mountVo2(readError: true);
        expect(
          find.text('Einträge konnten nicht geladen werden.'),
          findsOneWidget,
        );
        expect(find.text('Noch keine Einträge'), findsNothing);
        expect(find.text(paperValue), findsNothing);
        expect(find.byKey(const ValueKey('vo2-read-retry')), findsOneWidget);
        await capture('vo2-read-error');
        failingRead.failVo2Read = false;
        await tester.tap(find.byKey(const ValueKey('vo2-read-retry')));
        await tester.pumpAndSettle();
        expect(
          find.text('Einträge konnten nicht geladen werden.'),
          findsNothing,
        );
        expect(
          heroText(),
          paperValue,
        );
        await capture('vo2-read-retry');

        final partial = await _loadVo2ReviewRepo();
        final live = await partial.createVo2Entry(
          id: 'vo2-live',
          measuredOn: measured,
          valueMlKgMin: kSyntheticVo2PaperValue,
          declaredMethod: kSyntheticVo2PaperMethod,
        );
        if (live is! Vo2Committed || live.retry) {
          throw StateError('VO2 partial entry was not stored.');
        }
        partial.seedVo2Paper(corruptHead: true);
        await mountVo2(repository: partial, seed: false);
        expect(find.byKey(const ValueKey('vo2-entry-vo2-live')), findsOneWidget);
        expect(
          find.byKey(ValueKey('vo2-entry-$kSyntheticVo2PaperId')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('vo2-unreadable-count')),
          findsOneWidget,
        );
        expect(find.text('1 Eintrag nicht lesbar'), findsOneWidget);
        expect(find.text('99'), findsNothing);
        expect(find.text(paperValue), findsNWidgets(2));
        await capture('vo2-partial');

        final unreadable = await _loadVo2ReviewRepo();
        unreadable.seedVo2Paper(corruptHead: true);
        await mountVo2(repository: unreadable, seed: false);
        expect(
          heroText(),
          '\u2014',
        );
        expect(find.text('Eintrag nicht lesbar'), findsOneWidget);
        expect(find.text(paperValue), findsNothing);
        expect(find.text('99'), findsNothing);
        expect(find.byKey(const ValueKey('vo2-add-empty')), findsOneWidget);
        await capture('vo2-unreadable');

        final saveFailure = await mountVo2();
        await openEditor();
        await tester.enterText(
          find.byKey(const ValueKey('vo2-value-input')),
          '42,7',
        );
        saveFailure.failVo2Write = true;
        await saveEditor();
        expect(find.byKey(const ValueKey('vo2-editor')), findsOneWidget);
        expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
        expect(fieldText('vo2-value-input'), '42,7');
        expect(saveFailure.edits, 1);
        await capture('vo2-save-error');
        saveFailure.failVo2Write = false;
        await saveEditor();
        expect(find.byKey(const ValueKey('vo2-editor')), findsNothing);
        expect(saveFailure.edits, 2);
        expect(
          heroText(),
          obNumber(42.7, digits: 1),
        );
        await capture('vo2-save-retry');

        final conflict = await mountVo2();
        await openEditor();
        await tester.enterText(
          find.byKey(const ValueKey('vo2-value-input')),
          '42,5',
        );
        final raced = await conflict.editVo2Entry(
          id: kSyntheticVo2PaperId,
          expectedRevision: 1,
          measuredOn: measured,
          valueMlKgMin: 43,
          declaredMethod: kSyntheticVo2PaperMethod,
        );
        expect(raced, isA<Vo2Committed>());
        await saveEditor();
        expect(find.text('Eintrag wurde geändert'), findsOneWidget);
        expect(fieldText('vo2-value-input'), '42,5');
        expect(find.byKey(const ValueKey('vo2-editor')), findsOneWidget);
        await capture('vo2-conflict-retained');
        await saveEditor();
        expect(fieldText('vo2-value-input'), '43');
        expect(fieldText('vo2-method-input'), kSyntheticVo2PaperMethod);
        expect(find.text('Eintrag wurde geändert'), findsNothing);
        await capture('vo2-conflict-reload');
        await tester.tap(find.byTooltip('Schließen'));
        await tester.pumpAndSettle();
        expect(
          heroText(),
          obNumber(43, digits: 1),
        );
        expect(find.text('42,5'), findsNothing);
        await capture('vo2-conflict-dismiss');

        final reload = await mountVo2();
        await openEditor();
        await tester.enterText(
          find.byKey(const ValueKey('vo2-value-input')),
          '44',
        );
        final editsBefore = reload.edits;
        reload.failReadAfterCommit = true;
        await saveEditor();
        expect(
          find.text('Gespeichert. Einträge konnten nicht aktualisiert werden.'),
          findsOneWidget,
        );
        expect(find.text(obNumber(44, digits: 1)), findsNothing);
        expect(reload.edits, editsBefore + 1);
        await capture('vo2-saved-refresh-error');
        await tester.tap(find.byKey(const ValueKey('vo2-read-retry')));
        await tester.pumpAndSettle();
        expect(
          find.text('Gespeichert. Einträge konnten nicht aktualisiert werden.'),
          findsNothing,
        );
        expect(
          heroText(),
          obNumber(44, digits: 1),
        );
        expect(reload.edits, editsBefore + 1);
        await capture('vo2-saved-refresh-retry');

        await mountVo2(scale: 2);
        expect(
          heroText(),
          paperValue,
        );
        await capture('vo2-375-2x');
        await openEditor();
        final scaledSave = find.byKey(const ValueKey('vo2-save'));
        await tester.ensureVisible(scaledSave);
        expect(
          tester.getRect(scaledSave).bottom,
          lessThanOrEqualTo(
            tester.view.physicalSize.height / tester.view.devicePixelRatio,
          ),
        );
        await capture('vo2-375-editor');

        await mountVo2(brightness: Brightness.dark, scale: 2);
        expect(find.text(paperLine), findsOneWidget);
        await capture('vo2-375-2x-dark');
        await openEditor();
        final darkSave = find.byKey(const ValueKey('vo2-save'));
        await tester.ensureVisible(darkSave);
        expect(
          tester.getRect(darkSave).bottom,
          lessThanOrEqualTo(
            tester.view.physicalSize.height / tester.view.devicePixelRatio,
          ),
        );
        await capture('vo2-375-editor-dark');

        Future<OpenBandController> mountHealth(
          _Vo2ReviewRepo repository,
        ) async {
          final controller = OpenBandController(
            repository: repository,
            initialDay: day,
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
                Brightness.light,
              ).copyWith(platform: TargetPlatform.iOS),
              home: Scaffold(
                body: SafeArea(
                  child: OpenBandHealth(controller: controller),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            healthRow,
            200,
            scrollable: verticalScrollable().last,
          );
          await tester.pumpAndSettle();
          return controller;
        }

        final unreadableHealth = await _loadVo2ReviewRepo();
        unreadableHealth.seedVo2Paper(corruptHead: true);
        final unreadableHealthController = await mountHealth(unreadableHealth);
        expect(
          find.descendant(
            of: healthRow,
            matching: find.text('Eintrag nicht lesbar'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: healthRow, matching: find.text('\u2014')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: healthRow, matching: find.text(healthWhen)),
          findsNothing,
        );
        expect(
          find.descendant(of: healthRow, matching: find.text(healthValue)),
          findsNothing,
        );
        expect(
          find.descendant(of: healthRow, matching: find.textContaining('99')),
          findsNothing,
        );
        expect(
          find.descendant(
            of: healthRow,
            matching: find.text('Laden fehlgeschlagen'),
          ),
          findsNothing,
        );
        await capture('vo2-health-unreadable');
        unreadableHealthController.dispose();

        final partialHealth = await _loadVo2ReviewRepo();
        final partialLive = await partialHealth.createVo2Entry(
          id: 'vo2-live',
          measuredOn: measured,
          valueMlKgMin: kSyntheticVo2PaperValue,
          declaredMethod: kSyntheticVo2PaperMethod,
        );
        if (partialLive is! Vo2Committed || partialLive.retry) {
          throw StateError('VO2 health partial entry was not stored.');
        }
        partialHealth.seedVo2Paper(corruptHead: true);
        final partialHealthController = await mountHealth(partialHealth);
        expect(
          find.descendant(of: healthRow, matching: find.text(healthValue)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: healthRow,
            matching: find.textContaining(healthWhen),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: healthRow,
            matching: find.textContaining('Teilweise lesbar'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: healthRow,
            matching: find.text('Eintrag nicht lesbar'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(of: healthRow, matching: find.textContaining('99')),
          findsNothing,
        );
        await capture('vo2-health-partial');
        partialHealthController.dispose();

        final lost = await mountVo2(seed: false);
        await tester.tap(find.byKey(const ValueKey('vo2-add-empty')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('vo2-value-input')),
          '41',
        );
        await tester.enterText(
          find.byKey(const ValueKey('vo2-method-input')),
          kSyntheticVo2PaperMethod,
        );
        lost.loseNextCreateResponse = true;
        await saveEditor();
        expect(find.byKey(const ValueKey('vo2-editor')), findsOneWidget);
        expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
        expect(fieldText('vo2-value-input'), '41');
        expect(lost.lostCreateId, isNotNull);
        expect(lost.creates, 1);
        await tester.enterText(
          find.byKey(const ValueKey('vo2-value-input')),
          '42,5',
        );
        await saveEditor();
        expect(find.text('Eintrag wurde geändert'), findsOneWidget);
        expect(find.text('Speichern fehlgeschlagen'), findsNothing);
        expect(fieldText('vo2-value-input'), '42,5');
        expect(fieldText('vo2-method-input'), kSyntheticVo2PaperMethod);
        expect(lost.creates, 2);
        await capture('vo2-create-conflict');
        await saveEditor();
        expect(find.byKey(const ValueKey('vo2-editor')), findsOneWidget);
        expect(find.text('Eintrag wurde geändert'), findsNothing);
        expect(find.text('Laden fehlgeschlagen'), findsNothing);
        expect(fieldText('vo2-value-input'), '41');
        expect(fieldText('vo2-method-input'), kSyntheticVo2PaperMethod);
        expect(lost.creates, 2);
        await capture('vo2-create-conflict-reloaded');
        await tester.tap(find.byTooltip('Schließen'));
        await tester.pumpAndSettle();
        final createdRows = find.byWidgetPredicate((widget) {
          final key = widget.key;
          return key is ValueKey<String> && key.value.startsWith('vo2-entry-');
        });
        expect(createdRows, findsOneWidget);
        final createdId =
            (tester.widget(createdRows).key! as ValueKey<String>).value
                .substring('vo2-entry-'.length);
        expect(createdId, lost.lostCreateId);
        expect(
          heroText(),
          obNumber(41, digits: 1),
        );
        expect(find.text('42,5'), findsNothing);
        final createdHead = await lost.readVo2Entry(createdId);
        expect(createdHead.head?.valueMlKgMin, 41);
        expect(createdHead.head?.declaredMethod, kSyntheticVo2PaperMethod);
        expect(createdHead.head?.deleted, isFalse);

        final removedConflict = await mountVo2();
        await openEditor();
        await tester.enterText(
          find.byKey(const ValueKey('vo2-value-input')),
          '42,5',
        );
        final removedRemotely = await removedConflict.removeVo2Entry(
          id: kSyntheticVo2PaperId,
          expectedRevision: 1,
        );
        expect(removedRemotely, isA<Vo2Committed>());
        await saveEditor();
        expect(find.byKey(const ValueKey('vo2-editor')), findsOneWidget);
        expect(find.text('Eintrag wurde geändert'), findsOneWidget);
        expect(find.text('Laden fehlgeschlagen'), findsNothing);
        expect(fieldText('vo2-value-input'), '42,5');
        await saveEditor();
        expect(find.byKey(const ValueKey('vo2-editor')), findsNothing);
        expect(find.text('Laden fehlgeschlagen'), findsNothing);
        expect(find.text('Entfernt'), findsOneWidget);
        expect(
          find.byKey(ValueKey('vo2-removed-$kSyntheticVo2PaperId')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('vo2-entry-$kSyntheticVo2PaperId')),
          findsNothing,
        );
        expect(find.text('42,5'), findsNothing);
        expect(find.text(paperValue), findsOneWidget);
        await capture('vo2-removed-conflict');

        const receiptSource = 'OpenStrap backup';
        const partialReceipt = ImportOutcome(
          source: receiptSource,
          vo2TablePresent: true,
          vo2Revisions: 2,
          vo2ConflictIds: 1,
          vo2CorruptIds: 1,
        );
        const successReceipt = ImportOutcome(
          source: receiptSource,
          vo2TablePresent: true,
          vo2Revisions: 2,
        );
        const noopReceipt = ImportOutcome(
          source: receiptSource,
          vo2TablePresent: true,
        );
        const interruptedReceipt = ImportOutcome(
          source: receiptSource,
          vo2TablePresent: true,
          vo2Revisions: 1,
          readError: 'later table failed',
        );
        const interruptedEmptyReceipt = ImportOutcome(
          source: receiptSource,
          vo2TablePresent: true,
          readError: 'count failed',
        );


        void expectReceiptChrome({bool source = true}) {
          expect(find.byType(SafeArea), findsOneWidget);
          expect(find.text('Datenimport'), findsOneWidget);
          expect(find.byTooltip('Zurück'), findsOneWidget);
          expect(
            find.text('OpenBand-Sicherung'),
            source ? findsOneWidget : findsNothing,
          );
          expect(find.textContaining('OpenStrap'), findsNothing);
          expect(find.textContaining('0 Tag'), findsNothing);
          expect(find.textContaining('0 day'), findsNothing);
          expect(find.byIcon(LucideIcons.check), findsNothing);
        }

        void expectPartialReceipt() {
          expectReceiptChrome();
          expect(find.text('Teilweise importiert'), findsOneWidget);
          expect(find.text('2 VO₂max-Änderungen übernommen'), findsOneWidget);
          expect(find.text('Nicht übernommen'), findsOneWidget);
          expect(find.text('1 VO₂max-Konflikt'), findsOneWidget);
          expect(find.text('1 VO₂max-Eintrag nicht lesbar'), findsOneWidget);
          expect(find.text('Importiert'), findsNothing);
          expect(find.text('VO₂max unverändert'), findsNothing);
          expect(find.text('Nichts wurde importiert'), findsNothing);
          expect(find.text('Import unvollständig'), findsNothing);
        }

        Future<void> captureReceiptBottomIfCutOff(String name) async {
          final lower = find.text('1 VO₂max-Eintrag nicht lesbar');
          final viewport =
              tester.view.physicalSize.height / tester.view.devicePixelRatio;
          final hit = lower.hitTestable();
          final cutOff =
              hit.evaluate().isEmpty ||
              tester.getRect(hit).top < 0 ||
              tester.getRect(hit).bottom > viewport;
          if (!cutOff) return;
          final scroll = find.descendant(
            of: find.byKey(const ValueKey('import-receipt-scroll')),
            matching: find.byType(Scrollable),
          );
          await tester.scrollUntilVisible(lower, 160, scrollable: scroll);
          await tester.pump();
          expect(tester.getRect(lower).bottom, lessThanOrEqualTo(viewport));
          await capture(name);
        }

        await reviewMountImportReceipt(tester, partialReceipt);
        expectPartialReceipt();
        await capture('vo2-receipt-partial');
        await reviewMountImportReceipt(tester, partialReceipt, brightness: Brightness.dark);
        expectPartialReceipt();
        await capture('vo2-receipt-partial-dark');
        await reviewMountImportReceipt(tester, partialReceipt, scale: 2);
        expectPartialReceipt();
        await capture('vo2-receipt-partial-375-2x');
        await captureReceiptBottomIfCutOff('vo2-receipt-partial-375-2x-bottom');
        await reviewMountImportReceipt(tester, partialReceipt, brightness: Brightness.dark, scale: 2);
        expectPartialReceipt();
        await capture('vo2-receipt-partial-375-2x-dark');
        await captureReceiptBottomIfCutOff(
          'vo2-receipt-partial-375-2x-dark-bottom',
        );

        await reviewMountImportReceipt(tester, successReceipt);
        expectReceiptChrome();
        expect(find.text('Importiert'), findsOneWidget);
        expect(find.text('2 VO₂max-Änderungen übernommen'), findsOneWidget);
        expect(find.text('Nicht übernommen'), findsNothing);
        expect(find.text('Teilweise importiert'), findsNothing);
        expect(find.text('VO₂max unverändert'), findsNothing);
        await capture('vo2-receipt-success');

        await reviewMountImportReceipt(tester, noopReceipt);
        expectReceiptChrome();
        expect(find.text('VO₂max unverändert'), findsOneWidget);
        expect(find.text('Importiert'), findsNothing);
        expect(find.text('Teilweise importiert'), findsNothing);
        expect(find.text('Nichts wurde importiert'), findsNothing);
        expect(find.textContaining('Änderungen übernommen'), findsNothing);
        await capture('vo2-receipt-noop');

        await reviewMountImportReceipt(tester, interruptedReceipt);
        expectReceiptChrome();
        expect(find.text('Teilweise importiert'), findsOneWidget);
        expect(find.text('1 VO₂max-Änderung übernommen'), findsOneWidget);
        expect(find.text('Import unvollständig'), findsOneWidget);
        expect(find.textContaining('later table failed'), findsOneWidget);
        expect(find.text('Importiert'), findsNothing);
        expect(find.text('VO₂max unverändert'), findsNothing);
        expect(find.text('Nichts wurde importiert'), findsNothing);
        await capture('vo2-receipt-interrupted');

        await reviewMountImportReceipt(tester, interruptedEmptyReceipt);
        expectReceiptChrome(source: false);
        expect(find.text('Import unvollständig'), findsOneWidget);
        expect(find.textContaining('count failed'), findsOneWidget);
        expect(find.text('VO₂max unverändert'), findsNothing);
        expect(find.text('Nichts wurde importiert'), findsNothing);
        expect(find.text('Teilweise importiert'), findsNothing);
        expect(find.textContaining('übernommen'), findsNothing);
        await capture('vo2-receipt-interrupted-empty');
      }

      Future<void> reviewWeight() async {
        const day = '2026-09-15';
        final now = DateTime(2026, 9, 15, 9, 41);

        Future<SyntheticOpenBandRepository> mountWeight({
          Brightness brightness = Brightness.light,
          double scale = 1,
          bool seeded = true,
          bool readError = false,
          SyntheticOpenBandRepository? repository,
        }) async {
          final mountedRepository = repository ?? await loadGalleryRepository();
          if (seeded) mountedRepository.seedWeightHistory();
          mountedRepository.failJournalRead = readError;
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
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: OpenBandWeight(
                repository: mountedRepository,
                endDay: day,
                now: () => now,
              ),
            ),
          );
          await tester.pumpAndSettle();
          return mountedRepository;
        }

        Future<void> openLatest() async {
          await tester.tap(find.byKey(const ValueKey('weight-latest-edit')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('journal-value-sheet')),
            findsOneWidget,
          );
        }

        final healthRepository = await loadGalleryRepository();
        healthRepository.seedWeightHistory();
        final healthController = OpenBandController(
          repository: healthRepository,
          initialDay: day,
          now: () => now,
        );
        await healthController.refresh();
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            debugShowCheckedModeBanner: false,
            locale: const Locale('de'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            theme: openBandTheme(
              Brightness.light,
            ).copyWith(platform: TargetPlatform.iOS),
            home: Scaffold(
              body: SafeArea(
                child: OpenBandHealth(controller: healthController),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final healthWeightRow = find.widgetWithText(
          OBSettingsValueRow,
          'Gewicht',
        );
        await tester.scrollUntilVisible(
          healthWeightRow,
          200,
          scrollable: verticalScrollable().last,
        );
        await tester.pumpAndSettle();
        await capture('weight-health-entry');
        await tester.tap(healthWeightRow);
        await tester.pumpAndSettle();
        expect(find.byType(OpenBandWeight), findsOneWidget);
        await capture('weight-health-detail');
        await openLatest();
        await tester.enterText(
          find.byKey(const ValueKey('journal-value')),
          '74,8',
        );
        await tester.tap(find.text('Speichern'));
        await tester.pumpAndSettle();
        await reviewTapHeaderBack(tester);
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: healthWeightRow, matching: find.text('74,8 kg')),
          findsOneWidget,
        );
        await capture('weight-health-refreshed');
        await tester.tap(healthWeightRow);
        await tester.pumpAndSettle();
        healthRepository.failJournalRead = true;
        await reviewTapHeaderBack(tester);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: healthWeightRow,
            matching: find.text('Journal · Laden fehlgeschlagen'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: healthWeightRow, matching: find.text('74,8 kg')),
          findsNothing,
        );
        await capture('weight-health-refresh-error');
        healthRepository.failJournalRead = false;

        var repository = await mountWeight();
        healthController.dispose();
        expect(find.text('Journal · 15. Sept.'), findsOneWidget);
        expect(find.text('7 Einträge'), findsOneWidget);
        await capture('weight-light');
        await tester.tap(find.byTooltip('Über Gewicht'));
        await tester.pumpAndSettle();
        expect(
          find.text('Quelle: Journal · eingegebene Werte'),
          findsOneWidget,
        );
        await capture('weight-info');

        repository = await mountWeight(brightness: Brightness.dark);
        await capture('weight-dark');
        await openLatest();
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('journal-value')))
              .controller!
              .text,
          '75',
        );
        await capture('weight-edit-dark');

        repository = await mountWeight(seeded: false);
        expect(find.text('Noch keine Einträge'), findsOneWidget);
        await capture('weight-missing');
        await tester.tap(find.text('Eintragen'));
        await tester.pumpAndSettle();
        expect(find.byType(OBCalendar), findsOneWidget);
        expect(find.byType(DatePickerDialog), findsNothing);
        expect(find.text('15. September übernehmen'), findsOneWidget);
        expect(find.text('Synthetische Daten'), findsNothing);
        await capture('weight-date-picker');
        await tester.tap(find.text('15. September übernehmen'));
        await tester.pumpAndSettle();
        expect(find.text('Wert entfernen'), findsNothing);
        await capture('weight-new');

        await mountWeight(seeded: false, brightness: Brightness.dark);
        await tester.tap(find.text('Eintragen'));
        await tester.pumpAndSettle();
        await capture('weight-date-picker-dark');

        await mountWeight(seeded: false, scale: 2);
        await tester.tap(find.text('Eintragen'));
        await tester.pumpAndSettle();
        final dateAction = find.text('15. September übernehmen');
        await tester.scrollUntilVisible(
          dateAction,
          200,
          scrollable: verticalScrollable().last,
        );
        await tester.pumpAndSettle();
        expect(
          tester.getRect(dateAction).bottom,
          lessThanOrEqualTo(
            tester.view.physicalSize.height / tester.view.devicePixelRatio,
          ),
        );
        await capture('weight-date-picker-2x');

        repository = await mountWeight(readError: true);
        expect(
          find.text('Einträge konnten nicht geladen werden.'),
          findsOneWidget,
        );
        await capture('weight-read-error');

        repository = await mountWeight(scale: 2);
        expect(find.text('7 Einträge'), findsOneWidget);
        await capture('weight-2x');
        await openLatest();
        await capture('weight-edit-2x');
        await tester.tap(find.byTooltip('Schließen'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('weight-entry-2026-09-09')),
          250,
          scrollable: verticalScrollable().last,
        );
        await tester.pumpAndSettle();
        await capture('weight-2x-entries');

        repository = await mountWeight(brightness: Brightness.dark, scale: 2);
        expect(find.text('7 Einträge'), findsOneWidget);
        await capture('weight-375-2x-dark');
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('weight-entry-2026-09-09')),
          250,
          scrollable: verticalScrollable().last,
        );
        await tester.pumpAndSettle();
        await capture('weight-2x-entries-dark');

        final partialRepository = await loadGalleryRepository();
        partialRepository.seedWeightHistory(
          dates: const [day],
          enteredKg: const [401],
        );
        repository = await mountWeight(
          seeded: false,
          repository: partialRepository,
        );
        expect(find.text('1 Wert ausgeschlossen'), findsOneWidget);
        await capture('weight-partial');

        final mixedPartialRepository = await loadGalleryRepository();
        mixedPartialRepository.seedWeightHistory();
        mixedPartialRepository.seedWeightHistory(
          dates: const ['2026-09-08'],
          enteredKg: const [double.nan],
        );
        repository = await mountWeight(
          seeded: false,
          repository: mixedPartialRepository,
        );
        expect(find.text('7 Einträge'), findsOneWidget);
        expect(find.text('1 Eintrag unlesbar'), findsOneWidget);
        expect(
          tester
              .widget<OBCalendarLine>(find.byType(OBCalendarLine))
              .values
              .whereType<double>(),
          hasLength(7),
        );
        await capture('weight-partial-history');

        final unreadableRepository = await loadGalleryRepository();
        unreadableRepository.seedWeightHistory(
          dates: const [day],
          enteredKg: const [double.nan],
        );
        repository = await mountWeight(
          seeded: false,
          brightness: Brightness.dark,
          repository: unreadableRepository,
        );
        expect(find.text('Einträge nicht lesbar'), findsOneWidget);
        expect(find.text('Eintragen'), findsOneWidget);
        await capture('weight-unreadable-dark');

        repository = await mountWeight();
        await openLatest();
        final field = find.byKey(const ValueKey('journal-value'));
        await tester.enterText(field, '74,5');
        final concurrent = await repository.readJournalDay(day);
        await repository.patchJournalDay(
          JournalDayPatch.fromBase(
            concurrent,
            metrics: const {'weight_kg': JournalMetricValue(76)},
          ),
        );
        await tester.tap(find.text('Speichern'));
        await tester.pumpAndSettle();
        expect(find.text('Eintrag wurde geändert'), findsOneWidget);
        expect(tester.widget<TextField>(field).controller!.text, '74,5');
        await capture('weight-conflict-retained');
        await tester.tap(find.text('Neu laden'));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(field).controller!.text, '76');
        await tester.tap(find.byTooltip('Schließen'));
        await tester.pumpAndSettle();
        expect(find.text('76,0'), findsOneWidget);
        await capture('weight-conflict-closed-refreshed');

        repository = await mountWeight();
        await openLatest();
        await tester.enterText(field, '74,7');
        repository.failJournalPatch = true;
        await tester.tap(find.text('Speichern'));
        await tester.pumpAndSettle();
        expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
        expect(tester.widget<TextField>(field).controller!.text, '74,7');
        await capture('weight-save-error');

        repository = await mountWeight();
        await openLatest();
        await tester.enterText(field, '74,7');
        repository.failJournalRead = true;
        await tester.tap(find.text('Speichern'));
        await tester.pumpAndSettle();
        expect(
          find.text('Gespeichert. Verlauf konnte nicht aktualisiert werden.'),
          findsOneWidget,
        );
        await capture('weight-saved-refresh-error');

        repository.failJournalRead = false;
        await tester.tap(find.text('Erneut'));
        await tester.pumpAndSettle();
        expect(find.text('74,7'), findsOneWidget);
        await openLatest();
        await tester.tap(find.text('Wert entfernen'));
        await tester.pumpAndSettle();
        expect(find.text('Journal · 14. Sept.'), findsOneWidget);
        await capture('weight-removed');

        repository = await mountWeight();
        await openLatest();
        repository.failJournalRead = true;
        await tester.tap(find.text('Wert entfernen'));
        await tester.pumpAndSettle();
        expect(
          find.text('Gespeichert. Verlauf konnte nicht aktualisiert werden.'),
          findsOneWidget,
        );
        expect(find.text('Noch keine Einträge'), findsNothing);
        expect(find.text('Verlauf nicht verfügbar'), findsNothing);
        await capture('weight-remove-refresh-error');
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
            await tester.scrollUntilVisible(target, 80, scrollable: scrollable);
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
          expect(
            find.byKey(const ValueKey('food-time-scroll')),
            findsOneWidget,
          );
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
          expect(tester.getRect(close).top, greaterThanOrEqualTo(safeTop));
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
        expect(
          (await detail.readFoodEntry('oats')).current!.sourceCode,
          'manual',
        );
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
        expect(
          find.bySemanticsLabel('Quelle Unbekannt vendor-x'),
          findsOneWidget,
        );
        expect(find.text('10'), findsOneWidget);
        await capture('nutrition-entry-unknown');

        await openFoodEntry(
          seed: oats(kcal: 0, proteinG: 0, fibreG: 8.1, sugarG: 0, quantity: 0),
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
              .widget<TextField>(
                find.byKey(const ValueKey('food-nutrient-kcal')),
              )
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
        expect(
          find.byKey(const ValueKey('food-nutrient-kcal')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('food-nutrient-proteinG')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('food-nutrient-carbsG')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('food-nutrient-fatG')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('food-nutrient-fibreG')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('food-nutrient-sugarG')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('food-nutrient-satFatG')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('food-nutrient-sodiumMg')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('food-nutrient-ironMg')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('food-nutrient-calciumMg')),
          findsOneWidget,
        );
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
        expect(
          (await readFail.readFoodEntry('oats')).current!.label,
          'Haferflocken mit Milch',
        );
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
        expect((await conflictRepo.readFoodEntry('oats')).current!.kcal, 390);
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
        expectPinnedAboveKeyboard(
          find.byKey(const ValueKey('food-entry-save')),
        );
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
        expect((await parentRepo.readFoodEntry('m1')).current!.proteinG, 18);
        expect((await parentRepo.readFoodEntry('m1')).current!.fatG, 12);
        expect((await parentRepo.readFoodEntry('m1')).current!.carbsG, 56);
        expect((await parentRepo.readFoodEntry('m3')).current!.proteinG, 8);
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
        expect((await parentRepo.readFoodEntry('m2')).current!.fibreG, 8.1);
        expect((await parentRepo.readFoodEntry('m2')).current!.kcal, isNull);
        expect((await parentRepo.readFoodEntry('m2')).current!.atTs, isNull);
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
        expect(
          await draftRepo.readMealDraft('2026-09-15', 'breakfast'),
          isNotNull,
        );
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
        expect(
          (await draftConflictRepo.readFoodEntry('e-oats')).missing,
          isTrue,
        );
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

      Future<void> reviewNutritionParent() async {
        const day = '2026-09-15';
        final now = DateTime(2026, 9, 15, 9, 41);

        FoodEntry paperFood({
          required String id,
          required String date,
          required String meal,
          required String label,
          double? kcal,
          double? proteinG,
          double? carbsG,
          double? fatG,
          FoodSource source = FoodSource.manual,
          String? sourceCode,
          int createdAt = 1,
          int updatedAt = 1,
        }) => FoodEntry(
          id: id,
          date: date,
          meal: meal,
          label: label,
          kcal: kcal,
          proteinG: proteinG,
          carbsG: carbsG,
          fatG: fatG,
          source: source,
          sourceCode: sourceCode ?? source.name,
          confirmed: true,
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        void seedPaperDay(
          _NutritionParentReviewRepo repository, {
          bool water = true,
          double? waterMl = 1250,
          bool weekVariants = true,
        }) {
          repository.seedFoodEntry(
            paperFood(
              id: 'm1',
              date: day,
              meal: 'breakfast',
              label: 'Haferflocken mit Milch',
              kcal: 380,
              proteinG: 18,
              carbsG: 56,
              fatG: 12,
              createdAt: 1,
              updatedAt: 1,
            ),
          );
          repository.seedFoodEntry(
            paperFood(
              id: 'm2',
              date: day,
              meal: 'breakfast',
              label: 'Kaffee',
              source: FoodSource.unknown,
              sourceCode: 'unknown',
              createdAt: 50,
              updatedAt: 50,
            ),
          );
          repository.seedFoodEntry(
            paperFood(
              id: 'm3',
              date: day,
              meal: 'lunch',
              label: 'Linsensalat',
              kcal: 240,
              proteinG: 8,
              carbsG: 32,
              fatG: 3,
              createdAt: 3,
              updatedAt: 3,
            ),
          );
          if (weekVariants) {
            repository.seedFoodEntry(
              paperFood(
                id: 'zero-kcal',
                date: '2026-09-12',
                meal: 'snack',
                label: 'Wasserzwieback',
                kcal: 0,
                createdAt: 12,
                updatedAt: 12,
              ),
            );
            repository.seedFoodEntry(
              paperFood(
                id: 'partial-kcal',
                date: '2026-09-13',
                meal: 'lunch',
                label: 'Kaffee',
                source: FoodSource.unknown,
                sourceCode: 'unknown',
                createdAt: 13,
                updatedAt: 13,
              ),
            );
            repository.seedFoodEntry(
              paperFood(
                id: 'hist-14',
                date: '2026-09-14',
                meal: 'lunch',
                label: 'Linsensalat',
                kcal: 240,
                proteinG: 8,
                carbsG: 32,
                fatG: 3,
                createdAt: 14,
                updatedAt: 14,
              ),
            );
          }
          if (water && waterMl != null) {
            repository.seedJournalEditor(
              day: day,
              metrics: {'water_ml': JournalMetricValue(waterMl)},
            );
          }
        }

        Finder parentScrollable() => find.descendant(
          of: find.byType(OpenBandNutrition),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        );

        Future<void> revealHittable(Finder target) async {
          final scrollable = parentScrollable().first;
          var scrolls = 0;
          while (target.hitTestable().evaluate().isEmpty) {
            if (scrolls >= 24) {
              throw FlutterError(
                'Control is not hit-testable after direction-aware scrolling.',
              );
            }
            if (target.evaluate().isEmpty) {
              await tester.drag(scrollable, const Offset(0, -64));
              await tester.pump();
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
        }

        void expectFooterHittable() {
          expect(
            find.byKey(const ValueKey('nutrition-search')).hitTestable(),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('nutrition-add')).hitTestable(),
            findsOneWidget,
          );
        }

        double parentScrollPixels() => tester
            .state<ScrollableState>(parentScrollable().first)
            .position
            .pixels;

        Future<void> restoreParentScroll(double offset) async {
          final position = tester
              .state<ScrollableState>(parentScrollable().first)
              .position;
          position.jumpTo(
            offset.clamp(position.minScrollExtent, position.maxScrollExtent),
          );
          await tester.pump();
        }

        Future<void> expectPaperDayMeals(
          _NutritionParentReviewRepo repository,
        ) async {
          final oats = await repository.readFoodEntry('m1');
          expect(oats.current, isNotNull);
          expect(oats.current!.label, 'Haferflocken mit Milch');
          expect(oats.current!.source, FoodSource.manual);
          expect(oats.current!.kcal, 380);
          final coffee = await repository.readFoodEntry('m2');
          expect(coffee.current, isNotNull);
          expect(coffee.current!.label, 'Kaffee');
          expect(coffee.current!.source, FoodSource.unknown);
          expect(coffee.current!.sourceCode, 'unknown');
          expect(coffee.current!.kcal, isNull);
          final lentils = await repository.readFoodEntry('m3');
          expect(lentils.current, isNotNull);
          expect(lentils.current!.label, 'Linsensalat');
          expect(lentils.current!.source, FoodSource.manual);
          expect(lentils.current!.kcal, 240);

          final oatsRow = find.byKey(const ValueKey('food-row-m1'));
          final breakfastAdd = find.byTooltip('Frühstück ergänzen');
          await revealHittable(breakfastAdd);
          final breakfast = find.ancestor(
            of: breakfastAdd,
            matching: find.byType(OBMealSection),
          );
          expect(breakfast, findsOneWidget);
          expect(
            find.descendant(of: breakfast, matching: find.text('Frühstück')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: breakfast, matching: find.text('Teilweise')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: breakfast, matching: find.text('380 kcal')),
            findsNWidgets(2),
          );

          await revealHittable(oatsRow);
          expect(
            find.descendant(
              of: oatsRow,
              matching: find.text('Haferflocken mit Milch'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(of: oatsRow, matching: find.text('380 kcal')),
            findsOneWidget,
          );

          final coffeeRow = find.byKey(const ValueKey('food-row-m2'));
          await revealHittable(coffeeRow);
          expect(
            find.descendant(of: coffeeRow, matching: find.text('Kaffee')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: coffeeRow, matching: find.text('—')),
            findsOneWidget,
          );

          final lentilsRow = find.byKey(const ValueKey('food-row-m3'));
          await revealHittable(lentilsRow);
          expect(
            find.descendant(of: lentilsRow, matching: find.text('Linsensalat')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: lentilsRow, matching: find.text('240 kcal')),
            findsOneWidget,
          );
        }

        Finder waterCard() => find.byType(OpenBandWaterCard);

        Finder inWater(Finder matching) =>
            find.descendant(of: waterCard(), matching: matching);

        Finder waterSheet() =>
            find.byKey(const ValueKey('journal-value-sheet'));

        Finder inWaterSheet(Finder matching) =>
            find.descendant(of: waterSheet(), matching: matching);

        Finder inPicker(Finder matching) => find.descendant(
          of: find.byType(OpenBandMealPickerSheet),
          matching: matching,
        );

        Finder inDraft(Finder matching) => find.descendant(
          of: find.byType(OBMealDraftSheet),
          matching: matching,
        );

        double keyboardInset() =>
            tester.view.viewInsets.bottom / tester.view.devicePixelRatio;

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

        Future<OpenBandController> mountParent({
          required _NutritionParentReviewRepo repository,
          Brightness brightness = Brightness.light,
          double scale = 1,
        }) async {
          final controller = OpenBandController(
            repository: repository,
            initialDay: day,
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
              home: OpenBandNutrition(controller: controller, revision: 0),
            ),
          );
          await tester.pumpAndSettle();
          return controller;
        }

        Future<void> mountGalleryNutrition({
          required _NutritionParentReviewRepo repository,
          Brightness brightness = Brightness.light,
          double? scale,
        }) async {
          repository.seedCaffeineSleepPattern('2026-09-15');
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
          await press('Journal');
          await settleJournalHub(repository);
          await openHubNutrition();
          expect(find.byType(OpenBandNutrition), findsOneWidget);
        }

        void expectMinTapTarget(Finder target, {double size = 44}) {
          final box = tester.getRect(target.hitTestable());
          expect(box.width, greaterThanOrEqualTo(size));
          expect(box.height, greaterThanOrEqualTo(size));
        }

        Future<void> captureJournalCaffeine({
          required String name,
          Brightness brightness = Brightness.light,
          double? scale,
        }) async {
          final journalRepo = await mount(brightness: brightness, scale: scale);
          journalRepo.seedJournalEditor(
            metrics: {
              'caffeine_mg': const JournalMetricValue(200, atMinuteOfDay: 630),
            },
          );
          await press('Journal');
          await settleJournalHub(journalRepo);
          await openHubEditor();
          final caffeine = find.text('Koffein').last;
          await tester.ensureVisible(caffeine);
          await tester.tap(caffeine);
          await tester.pumpAndSettle();
          final sheet = find.byKey(const ValueKey('journal-value-sheet'));
          expect(sheet, findsOneWidget);
          expect(
            find.descendant(of: sheet, matching: find.text('Koffein')),
            findsOneWidget,
          );
          expect(
            tester
                .widget<TextField>(
                  find.descendant(
                    of: sheet,
                    matching: find.byKey(const ValueKey('journal-value')),
                  ),
                )
                .controller!
                .text,
            '200',
          );
          expect(
            find.descendant(of: sheet, matching: find.text('10:30')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: sheet, matching: find.text('Menge')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: sheet, matching: find.text('Zuletzt')),
            findsOneWidget,
          );
          final amount = find.byKey(const ValueKey('journal-value-amount'));
          final time = find.byKey(const ValueKey('journal-value-time'));
          expect(amount, findsOneWidget);
          expect(time, findsOneWidget);
          final amountBox = tester.getRect(amount);
          final timeBox = tester.getRect(time);
          if ((scale ?? 1) <= 1) {
            expect(
              (amountBox.center.dy - timeBox.center.dy).abs(),
              lessThan(8),
            );
            expect(amountBox.right, lessThanOrEqualTo(timeBox.left + 1));
          } else {
            expect(
              timeBox.top + 0.5,
              greaterThanOrEqualTo(amountBox.bottom - 1),
            );
          }
          expectMinTapTarget(
            find.descendant(of: sheet, matching: find.byTooltip('Schließen')),
          );
          expect(
            tester
                .getRect(
                  find.descendant(
                    of: sheet,
                    matching: find.widgetWithText(FilledButton, 'Übernehmen'),
                  ),
                )
                .height,
            greaterThanOrEqualTo(44),
          );
          await capture(name);
        }

        Future<void> tapTab(String label) async {
          final tab = find.descendant(
            of: find.byType(OBSegmented),
            matching: find.text(label),
          );
          expect(tab.hitTestable(), findsOneWidget);
          await tester.tap(tab.hitTestable());
          await tester.pumpAndSettle();
        }

        Future<_NutritionParentReviewRepo> freshRepo({
          bool water = true,
          double? waterMl = 1250,
          bool weekVariants = true,
          MealDraft? draft,
        }) async {
          final repository = await _loadNutritionParentReviewRepo();
          seedPaperDay(
            repository,
            water: water,
            waterMl: waterMl,
            weekVariants: weekVariants,
          );
          if (draft != null) {
            await repository.saveMealDraft(draft);
          }
          return repository;
        }

        Finder underlyingJournal() =>
            find.byType(OpenBandJournal, skipOffstage: false);

        Future<void> capturePendingDraftSaveError({
          required String name,
          Brightness brightness = Brightness.light,
          double scale = 1,
        }) async {
          final repository = await freshRepo();
          repository.failDraftWrite = true;
          final parent = await mountParent(
            repository: repository,
            brightness: brightness,
            scale: scale,
          );
          await tapTab('Lebensmittel');
          final coffee = find.byKey(const ValueKey('food-row-m2'));
          await revealHittable(coffee);
          await tester.tap(coffee.hitTestable());
          await tester.pumpAndSettle();
          expect(find.byType(OpenBandMealPickerSheet), findsOneWidget);
          await tester.tap(inPicker(find.text('Frühstück')).hitTestable());
          await tester.pumpAndSettle();
          expect(find.byType(OBMealDraftSheet), findsNothing);
          expect(
            find.descendant(
              of: find.byType(SnackBar),
              matching: find.text('Speichern fehlgeschlagen'),
            ),
            findsOneWidget,
          );
          expect(
            find
                .descendant(
                  of: find.byType(SnackBar),
                  matching: find.text('Erneut'),
                )
                .hitTestable(),
            findsOneWidget,
          );
          expect(await repository.readMealDraft(day, 'breakfast'), isNull);
          await capture(name);
          parent.dispose();
        }

        Future<void> openWaterSheet() async {
          await revealHittable(inWater(find.text('Wasser')));
          await tester.tap(inWater(find.text('Wasser')).hitTestable());
          await tester.pumpAndSettle();
          expect(waterSheet(), findsOneWidget);
          expect(inWaterSheet(find.text('Wasser')), findsOneWidget);
        }

        Future<void> captureDay({
          required String name,
          Brightness brightness = Brightness.light,
          double scale = 1,
          bool scrolled = false,
        }) async {
          final repository = await freshRepo();
          final controller = await mountParent(
            repository: repository,
            brightness: brightness,
            scale: scale,
          );
          expect(find.text('Ernährung'), findsOneWidget);
          expect(find.text('15. September'), findsOneWidget);
          expectFooterHittable();
          final origin = parentScrollPixels();
          await revealHittable(find.byType(OBMacroBars));
          expect(
            find.descendant(
              of: find.byType(OBMacroBars),
              matching: find.text('620'),
            ),
            findsOneWidget,
          );
          await revealHittable(inWater(find.text('1.250')));
          await expectPaperDayMeals(repository);
          if (scrolled) {
            final later = find.byTooltip('Zwischendurch ergänzen');
            await revealHittable(later);
            expect(find.text('Zwischendurch').hitTestable(), findsOneWidget);
            expectFooterHittable();
          } else {
            await restoreParentScroll(origin);
            expect(find.text('Ernährung'), findsOneWidget);
            expect(find.text('15. September'), findsOneWidget);
            expectFooterHittable();
          }
          await capture(name);
          controller.dispose();
        }

        await captureDay(name: 'nutrition-parent');
        await captureDay(
          name: 'nutrition-parent-dark',
          brightness: Brightness.dark,
        );
        await captureDay(name: 'nutrition-parent-2x', scale: 2);
        await captureDay(
          name: 'nutrition-parent-2x-scrolled',
          scale: 2,
          scrolled: true,
        );
        await captureDay(
          name: 'nutrition-parent-2x-dark',
          brightness: Brightness.dark,
          scale: 2,
        );
        await captureDay(
          name: 'nutrition-parent-2x-scrolled-dark',
          brightness: Brightness.dark,
          scale: 2,
          scrolled: true,
        );

        var repository = await freshRepo(water: false);
        var controller = await mountParent(repository: repository);
        expect(inWater(find.text('—')), findsOneWidget);
        expect(inWater(find.text('1.250')), findsNothing);
        expect(inWater(find.text('0')), findsNothing);
        await capture('nutrition-parent-water-unknown');
        controller.dispose();

        repository = await freshRepo(waterMl: 0);
        controller = await mountParent(repository: repository);
        expect(inWater(find.text('0')), findsOneWidget);
        expect(inWater(find.text('—')), findsNothing);
        expect(inWater(find.text('1.250')), findsNothing);
        await capture('nutrition-parent-water-zero');
        controller.dispose();

        repository = await freshRepo();
        controller = await mountParent(repository: repository);
        await revealHittable(find.byKey(const ValueKey('water-plus')));
        await tester.tap(
          find.byKey(const ValueKey('water-plus')).hitTestable(),
        );
        await tester.pumpAndSettle();
        expect(inWater(find.text('1.500')), findsOneWidget);
        expect(repository.waterAdjusts, 1);
        expect(
          (await repository.readJournalDay(day)).metrics['water_ml']!.value,
          1500,
        );
        await capture('nutrition-parent-water-delta');
        controller.dispose();

        repository = await freshRepo();
        controller = await mountParent(repository: repository);
        repository.failJournalReadAfter = repository.journalReads;
        await revealHittable(find.byKey(const ValueKey('water-plus')));
        await tester.tap(
          find.byKey(const ValueKey('water-plus')).hitTestable(),
        );
        await tester.pumpAndSettle();
        expect(inWater(find.text('1.500')), findsOneWidget);
        expect(inWater(find.text('Laden fehlgeschlagen')), findsOneWidget);
        expect(inWater(find.text('Erneut versuchen')), findsOneWidget);
        expect(repository.waterAdjusts, 1);
        await capture('nutrition-parent-water-refresh-error');
        repository.failJournalReadAfter = null;
        await tester.tap(inWater(find.text('Erneut versuchen')).hitTestable());
        await tester.pumpAndSettle();
        expect(inWater(find.text('1.500')), findsOneWidget);
        expect(inWater(find.text('Laden fehlgeschlagen')), findsNothing);
        expect(repository.waterAdjusts, 1);
        await capture('nutrition-parent-water-refresh-retry');
        controller.dispose();

        repository = await freshRepo();
        controller = await mountParent(repository: repository);
        await openWaterSheet();
        expect(
          tester
              .widget<TextField>(
                inWaterSheet(find.byKey(const ValueKey('journal-value'))),
              )
              .controller!
              .text,
          '1250',
        );
        await capture('nutrition-parent-water-manual');
        await tester.tap(
          inWaterSheet(find.byTooltip('Schließen')).hitTestable(),
        );
        await tester.pumpAndSettle();
        expect(waterSheet(), findsNothing);
        controller.dispose();

        repository = await freshRepo();
        controller = await mountParent(
          repository: repository,
          brightness: Brightness.dark,
        );
        await openWaterSheet();
        await capture('nutrition-parent-water-manual-dark');
        await tester.tap(
          inWaterSheet(find.byTooltip('Schließen')).hitTestable(),
        );
        await tester.pumpAndSettle();
        expect(waterSheet(), findsNothing);
        controller.dispose();

        repository = await freshRepo();
        controller = await mountParent(repository: repository);
        await openWaterSheet();
        await tester.enterText(
          inWaterSheet(find.byKey(const ValueKey('journal-value'))),
          '1500',
        );
        await tester.pump();
        repository.failWaterWrite = true;
        await tester.tap(inWaterSheet(find.text('Speichern')).hitTestable());
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(
                inWaterSheet(find.byKey(const ValueKey('journal-value'))),
              )
              .controller!
              .text,
          '1500',
        );
        expect(
          inWaterSheet(find.text('Speichern fehlgeschlagen')),
          findsOneWidget,
        );
        expect(inWaterSheet(find.text('Erneut versuchen')), findsOneWidget);
        expect(
          (await repository.readJournalDay(day)).metrics['water_ml']!.value,
          1250,
        );
        await capture('nutrition-parent-water-save-error');
        repository.failWaterWrite = false;
        await tester.tap(
          inWaterSheet(find.text('Erneut versuchen')).hitTestable(),
        );
        await tester.pumpAndSettle();
        expect(waterSheet(), findsNothing);
        expect(inWater(find.text('1.500')), findsOneWidget);
        expect(
          (await repository.readJournalDay(day)).metrics['water_ml']!.value,
          1500,
        );
        await capture('nutrition-parent-water-save-retry');
        controller.dispose();

        repository = await freshRepo();
        controller = await mountParent(repository: repository);
        await openWaterSheet();
        repository.conflictWaterWrite = true;
        await tester.tap(inWaterSheet(find.text('Speichern')).hitTestable());
        await tester.pumpAndSettle();
        expect(
          inWaterSheet(find.text('Eintrag wurde geändert')),
          findsOneWidget,
        );
        expect(inWaterSheet(find.text('Neu laden')), findsOneWidget);
        expect(
          tester
              .widget<TextField>(
                inWaterSheet(find.byKey(const ValueKey('journal-value'))),
              )
              .controller!
              .text,
          '1250',
        );
        expect(
          (await repository.readJournalDay(day)).metrics['water_ml']!.value,
          1250,
        );
        await capture('nutrition-parent-water-conflict');
        repository.conflictWaterWrite = false;
        await tester.tap(
          inWaterSheet(find.byTooltip('Schließen')).hitTestable(),
        );
        await tester.pumpAndSettle();
        expect(waterSheet(), findsNothing);
        controller.dispose();

        repository = await freshRepo();
        controller = await mountParent(repository: repository, scale: 2);
        await openWaterSheet();
        await capture('nutrition-parent-water-2x');
        await settleKeyboard(
          inWaterSheet(find.byKey(const ValueKey('journal-value'))),
        );
        expect(
          tester
              .widget<TextField>(
                inWaterSheet(find.byKey(const ValueKey('journal-value'))),
              )
              .controller!
              .text,
          '1250',
        );
        await capture('nutrition-parent-water-2x-keyboard');
        controller.dispose();

        repository = await freshRepo();
        controller = await mountParent(repository: repository);
        await tapTab('Woche');
        expect(find.text('Erfasste Energie'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('week-row-2026-09-11')),
            matching: find.text('Keine Einträge'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('week-row-2026-09-12')),
            matching: find.text('0'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('week-row-2026-09-13')),
            matching: find.text('1 Eintrag ohne kcal'),
          ),
          findsOneWidget,
        );
        await capture('nutrition-parent-week');
        controller.dispose();

        repository = await freshRepo();
        controller = await mountParent(
          repository: repository,
          brightness: Brightness.dark,
        );
        await tapTab('Woche');
        expect(find.text('Erfasste Energie'), findsOneWidget);
        await capture('nutrition-parent-week-dark');
        controller.dispose();

        repository = await freshRepo();
        repository.failWeekRead = true;
        controller = await mountParent(repository: repository);
        await tapTab('Woche');
        expect(find.text('Woche nicht geladen'), findsOneWidget);
        expect(find.text('Erneut'), findsOneWidget);
        await capture('nutrition-parent-week-error');
        repository.failWeekRead = false;
        await tester.tap(find.text('Erneut'));
        await tester.pumpAndSettle();
        expect(find.text('Erfasste Energie'), findsOneWidget);
        expect(find.text('Woche nicht geladen'), findsNothing);
        await capture('nutrition-parent-week-retry');
        controller.dispose();

        repository = await freshRepo();
        controller = await mountParent(repository: repository);
        await tapTab('Lebensmittel');
        expect(find.text('Zuletzt verwendet'), findsOneWidget);
        expect(find.byKey(const ValueKey('food-row-m1')), findsOneWidget);
        expect(find.byKey(const ValueKey('food-row-m2')), findsOneWidget);
        await capture('nutrition-parent-recents');
        controller.dispose();

        repository = await freshRepo();
        controller = await mountParent(
          repository: repository,
          brightness: Brightness.dark,
        );
        await tapTab('Lebensmittel');
        expect(find.text('Zuletzt verwendet'), findsOneWidget);
        await capture('nutrition-parent-recents-dark');
        controller.dispose();

        repository = await freshRepo();
        repository.failRecentRead = true;
        controller = await mountParent(repository: repository);
        await tapTab('Lebensmittel');
        expect(
          find.text('Einträge konnten nicht geladen werden.'),
          findsOneWidget,
        );
        expect(find.text('Erneut'), findsOneWidget);
        await capture('nutrition-parent-recents-error');
        controller.dispose();

        repository = await freshRepo();
        controller = await mountParent(repository: repository);
        expectFooterHittable();
        await tester.tap(
          find.byKey(const ValueKey('nutrition-add')).hitTestable(),
        );
        await tester.pumpAndSettle();
        expect(find.byType(OpenBandMealPickerSheet), findsOneWidget);
        expect(inPicker(find.text('Mahlzeit wählen')), findsOneWidget);
        expect(inPicker(find.text('Frühstück')), findsOneWidget);
        await capture('nutrition-parent-picker');
        await tester.tap(inPicker(find.byTooltip('Schließen')).hitTestable());
        await tester.pumpAndSettle();
        expect(find.byType(OpenBandMealPickerSheet), findsNothing);
        controller.dispose();

        repository = await freshRepo();
        controller = await mountParent(
          repository: repository,
          brightness: Brightness.dark,
        );
        await tester.tap(
          find.byKey(const ValueKey('nutrition-add')).hitTestable(),
        );
        await tester.pumpAndSettle();
        expect(find.byType(OpenBandMealPickerSheet), findsOneWidget);
        expect(inPicker(find.text('Frühstück')), findsOneWidget);
        await capture('nutrition-parent-picker-dark');
        await tester.tap(inPicker(find.byTooltip('Schließen')).hitTestable());
        await tester.pumpAndSettle();
        expect(find.byType(OpenBandMealPickerSheet), findsNothing);
        controller.dispose();

        repository = await freshRepo(weekVariants: false);
        await repository.saveMealDraft(
          MealDraft(
            id: 'd-breakfast',
            day: day,
            meal: 'breakfast',
            entries: const [
              MealDraftEntry(
                id: 'e-oats',
                label: 'Haferflocken mit Milch',
                kcal: 380,
              ),
            ],
            updatedAt: DateTime(2026, 9, 15, 8),
          ),
        );
        controller = await mountParent(repository: repository);
        await tapTab('Lebensmittel');
        final coffee = find.byKey(const ValueKey('food-row-m2'));
        await revealHittable(coffee);
        await tester.tap(coffee.hitTestable());
        await tester.pumpAndSettle();
        expect(find.byType(OpenBandMealPickerSheet), findsOneWidget);
        await tester.tap(inPicker(find.text('Frühstück')).hitTestable());
        await tester.pumpAndSettle();
        expect(find.byType(OBMealDraftSheet), findsOneWidget);
        expect(inDraft(find.text('Haferflocken mit Milch')), findsOneWidget);
        expect(inDraft(find.text('Kaffee')), findsOneWidget);
        final retained = await repository.readMealDraft(day, 'breakfast');
        expect(retained, isNotNull);
        expect(retained!.id, 'd-breakfast');
        expect(retained.entries.map((e) => e.id), contains('e-oats'));
        final added = retained.entries.where((e) => e.id != 'e-oats').single;
        expect(added.id, isNot('m2'));
        expect(added.id, isNotEmpty);
        expect(added.label, 'Kaffee');
        expect(added.source, FoodSource.unknown);
        expect(added.sourceCode, 'unknown');
        expect(
          retained.entries.singleWhere((e) => e.id == 'e-oats').label,
          'Haferflocken mit Milch',
        );
        await capture('nutrition-parent-reuse-draft');
        await tester.tap(inDraft(find.text('Speichern')).hitTestable());
        await tester.pumpAndSettle();
        expect(find.byType(OBMealDraftSheet), findsNothing);
        await tapTab('Tag');
        expect(find.byKey(ValueKey('food-row-${added.id}')), findsOneWidget);
        final committed = await repository.readFoodEntry(added.id);
        expect(committed.saved, isTrue);
        expect(committed.current!.source, FoodSource.unknown);
        expect(committed.current!.id, added.id);
        await capture('nutrition-parent-reuse-committed');
        controller.dispose();

        await capturePendingDraftSaveError(
          name: 'nutrition-parent-draft-save-error',
        );
        await capturePendingDraftSaveError(
          name: 'nutrition-parent-draft-save-error-dark',
          brightness: Brightness.dark,
        );
        await capturePendingDraftSaveError(
          name: 'nutrition-parent-draft-save-error-2x',
          scale: 2,
        );

        repository = await freshRepo();
        await mountGalleryNutrition(repository: repository);
        await tapTab('Woche');
        final historical = find.byKey(const ValueKey('week-row-2026-09-14'));
        await revealHittable(historical);
        await tester.tap(historical.hitTestable());
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<OpenBandJournal>(underlyingJournal())
              .controller
              .selectedDay,
          '2026-09-14',
        );
        expect(
          find.descendant(
            of: find.byType(OpenBandNutrition),
            matching: find.text('14. September'),
          ),
          findsOneWidget,
        );
        final historicalOrigin = parentScrollPixels();
        final historicalLunch = find.byKey(const ValueKey('food-row-hist-14'));
        await revealHittable(historicalLunch);
        expect(
          find.descendant(
            of: historicalLunch,
            matching: find.text('Linsensalat'),
          ),
          findsOneWidget,
        );
        final historicalSaved = await repository.readFoodEntry('hist-14');
        expect(historicalSaved.current, isNotNull);
        expect(historicalSaved.current!.label, 'Linsensalat');
        expect(historicalSaved.current!.kcal, 240);
        await restoreParentScroll(historicalOrigin);
        final nutritionBack = find.descendant(
          of: find.byType(OpenBandNutrition),
          matching: find.byTooltip('Zurück'),
        );
        expectMinTapTarget(nutritionBack);
        await capture('nutrition-parent-historical');
        await tester.tap(nutritionBack.hitTestable());
        await tester.pumpAndSettle();
        expect(find.byType(OpenBandNutrition), findsNothing);
        expect(find.byType(OpenBandGallery), findsOneWidget);
        expect(find.byType(OpenBandJournal), findsOneWidget);
        expect(
          tester
              .widget<OpenBandJournal>(underlyingJournal())
              .controller
              .selectedDay,
          '2026-09-14',
        );
        final hub = find.byKey(const PageStorageKey('openband.journal'));
        final edit = find.descendant(
          of: hub,
          matching: find.byKey(const ValueKey('journal-edit')),
        );
        final hubScroll = find.descendant(
          of: hub,
          matching: find.byType(Scrollable),
        );
        if (edit.hitTestable().evaluate().isEmpty) {
          if (edit.evaluate().isEmpty) {
            await tester.scrollUntilVisible(edit, -64, scrollable: hubScroll);
          } else {
            await Scrollable.ensureVisible(tester.element(edit), alignment: 0);
          }
          await tester.pumpAndSettle();
        }
        expect(edit.hitTestable(), findsOneWidget);
        expectMinTapTarget(edit);
        await capture('nutrition-parent-historical-return');

        await captureJournalCaffeine(name: 'nutrition-parent-journal-value');
        await captureJournalCaffeine(
          name: 'nutrition-parent-journal-value-dark',
          brightness: Brightness.dark,
        );
        await captureJournalCaffeine(
          name: 'nutrition-parent-journal-value-2x',
          scale: 2,
        );
        await captureJournalCaffeine(
          name: 'nutrition-parent-journal-value-2x-dark',
          brightness: Brightness.dark,
          scale: 2,
        );
      }

      Future<void> reviewSleepPlan() async {
        const day = '2026-09-15';
        const wakeDay = '2026-09-16';
        const pastDay = '2026-09-14';
        final now = DateTime(2026, 9, 15, 9, 41);
        final builtAt = DateTime(2026, 9, 15, 7, 42);
        final builtEpoch = builtAt.millisecondsSinceEpoch ~/ 1000;
        final inputReadStartedAtMs = builtAt.millisecondsSinceEpoch - 4000;
        final observationComputedAtMs = inputReadStartedAtMs - 1500;
        const needSeconds = 30805.714285714286;
        const bedtimeMinute = 1319.548872180451;
        const wakeMinute = 420.0;
        const baselineNeedSec = 28800.0;
        const sleepDebtSec = 1800.0;
        final strainBonusMin =
            (needSeconds - baselineNeedSec - sleepDebtSec) / 60;

        Map<String, dynamic> fixtureArtifact({
          int? algoVersion,
          bool times = true,
          bool window = true,
          bool provenance = true,
          double? need,
          double? nap = 0,
          required double? strain,
          double? bedtime,
          double? wake,
        }) {
          final dates = openBandDaysEnding(day, 14);
          return {
            'algo_version': algoVersion ?? kAlgoVersion,
            'built_for_day': day,
            'built_at_epoch': builtEpoch,
            if (provenance) 'input_read_started_at_ms': inputReadStartedAtMs,
            'sleep_coach': {
              'need': {
                'value': {'need_sec': need ?? needSeconds},
              },
              'nap_credit_min': nap ?? '—',
              'strain_bonus_min': strain ?? '—',
              'bedtime': times
                  ? {
                      'value': {'bedtime_min_of_day': bedtime ?? bedtimeMinute},
                    }
                  : '—',
              'wake': times
                  ? {
                      'value': {'wake_min_of_day': wake ?? wakeMinute},
                    }
                  : '—',
            },
            if (window) ...{
              'n_days': dates.length,
              'recent': [
                for (final date in dates) {'date': date},
              ],
            },
          };
        }

        List<SleepPlanDayObservation> fixtureObservations({
          Map<String, dynamic>? artifact,
          int? computedAtMs,
          bool skipped = false,
          bool inFetchWindow = true,
        }) {
          final recent = artifact?['recent'];
          if (recent is! List) return const [];
          final at = computedAtMs ?? observationComputedAtMs;
          return [
            for (final row in recent)
              if (row is Map && row['date'] is String)
                SleepPlanDayObservation(
                  day: row['date'] as String,
                  computedAtMs: at,
                  skipped: skipped,
                  inFetchWindow: inFetchWindow,
                ),
          ];
        }

        Future<_SleepPlanReviewRepo> loadRepo() async {
          Future<Map> load(String name) async =>
              jsonDecode(
                    await rootBundle.loadString(
                      'docs/openband5/assets/fixtures/$name.json',
                    ),
                  )
                  as Map;
          final repo = _SleepPlanReviewRepo(
            await load('day-summary'),
            await load('sleep-detail'),
            activity: await load('additional-flows'),
            run: await load('run-detail'),
          );
          await repo.seedNutritionGoals();
          repo.seedCaffeineSleepPattern(day);
          repo.sleepPlanNow = () => now;
          repo.sleepPlanArtifact = fixtureArtifact(strain: strainBonusMin);
          repo.sleepPlanJobs = const [];
          repo.sleepPlanObservations = fixtureObservations(
            artifact: repo.sleepPlanArtifact,
          );
          return repo;
        }

        void resetPlan(
          _SleepPlanReviewRepo repository, {
          Map<String, dynamic>? artifact,
          bool missingArtifact = false,
          List<SleepPlanDayObservation>? observations,
        }) {
          repository.failSleepPlanRead = false;
          repository.sleepPlanJobs = const [];
          repository.sleepPlanArtifact = missingArtifact
              ? null
              : artifact ?? fixtureArtifact(strain: strainBonusMin);
          repository.sleepPlanObservations =
              observations ??
              fixtureObservations(artifact: repository.sleepPlanArtifact);
          repository.requestedDays.clear();
          repository.clocks.clear();
        }

        Finder downScrollable(Finder ancestor) => find.descendant(
          of: ancestor,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        );

        Future<void> revealIn(Finder ancestor, Finder target) async {
          final scrollable = downScrollable(ancestor).first;
          var scrolls = 0;
          while (target.evaluate().isEmpty ||
              target.hitTestable().evaluate().isEmpty) {
            if (scrolls >= 32) {
              throw FlutterError(
                'Control is not hit-testable after production scrolling.',
              );
            }
            if (target.evaluate().isEmpty) {
              final position = tester
                  .state<ScrollableState>(scrollable)
                  .position;
              final atMin = position.pixels <= position.minScrollExtent + 0.5;
              final atMax = position.pixels >= position.maxScrollExtent - 0.5;
              final dy = !atMin
                  ? 64.0
                  : !atMax
                  ? -64.0
                  : 0.0;
              if (dy == 0) {
                throw FlutterError(
                  'Control is not hit-testable after production scrolling.',
                );
              }
              await tester.drag(scrollable, Offset(0, dy));
              await tester.pump();
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
        }

        double scrollPixels(Finder ancestor) => tester
            .state<ScrollableState>(downScrollable(ancestor).first)
            .position
            .pixels;

        Future<void> restoreScroll(Finder ancestor, double offset) async {
          final position = tester
              .state<ScrollableState>(downScrollable(ancestor).first)
              .position;
          position.jumpTo(
            offset.clamp(position.minScrollExtent, position.maxScrollExtent),
          );
          await tester.pump();
        }

        Rect reviewSafeViewport() {
          final view = tester.view;
          final dpr = view.devicePixelRatio;
          final size = view.physicalSize / dpr;
          final pad = view.viewPadding;
          return Rect.fromLTRB(
            pad.left / dpr,
            pad.top / dpr,
            size.width - pad.right / dpr,
            size.height - pad.bottom / dpr,
          );
        }

        bool rectInSafeViewport(Rect box) {
          final safe = reviewSafeViewport();
          return box.top >= safe.top &&
              box.bottom <= safe.bottom &&
              box.left >= safe.left &&
              box.right <= safe.right;
        }

        Future<void> pumpUntilPlanReady() async {
          await tester.pump();
          var frames = 0;
          while (find.byType(OpenBandSleepPlan).evaluate().isEmpty ||
              find.text('Geschätzter Schlafbedarf').evaluate().isEmpty) {
            if (++frames > 80) {
              throw FlutterError('Sleep plan did not finish loading.');
            }
            await tester.pump(const Duration(milliseconds: 16));
          }
          await reviewPumpPageTransitions(tester);
        }

        Future<void> pumpHostReady(Finder home) async {
          await tester.pump();
          var frames = 0;
          while (home.evaluate().isEmpty) {
            if (++frames > 80) {
              throw FlutterError('Sleep host did not finish loading.');
            }
            await tester.pump(const Duration(milliseconds: 16));
          }
          await reviewPumpPageTransitions(tester);
        }

        Widget reviewHost({
          required Widget home,
          Brightness brightness = Brightness.light,
          double scale = 1,
        }) => MaterialApp(
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
          home: home,
        );

        Future<OpenBandController> mountSleep({
          required _SleepPlanReviewRepo repository,
          Brightness brightness = Brightness.light,
          double scale = 1,
          String selectedDay = day,
          DateTime? clock,
        }) async {
          final wall = clock ?? now;
          final controller = OpenBandController(
            repository: repository,
            initialDay: selectedDay,
            band: repository.band,
            now: () => wall,
          );
          await controller.refresh();
          await tester.pumpWidget(
            reviewHost(
              brightness: brightness,
              scale: scale,
              home: OpenBandSleep(controller: controller),
            ),
          );
          await pumpHostReady(find.byType(OpenBandSleep));
          return controller;
        }

        Future<void> mountPlan({
          required _SleepPlanReviewRepo repository,
          Brightness brightness = Brightness.light,
          double scale = 1,
          String planDay = day,
        }) async {
          await tester.pumpWidget(
            reviewHost(
              brightness: brightness,
              scale: scale,
              home: OpenBandSleepPlan(
                repository: repository,
                day: planDay,
                now: () => now,
                synthetic: true,
              ),
            ),
          );
          await pumpUntilPlanReady();
        }

        Future<void> openTonight() async {
          final tonight = find.text('Heute Nacht');
          await revealIn(find.byType(OpenBandSleep), tonight);
          expect(tonight.hitTestable(), findsOneWidget);
          await tester.tap(tonight.hitTestable());
          await pumpUntilPlanReady();
        }

        Future<void> popPlan() async {
          final back = find.byTooltip('Zurück');
          expect(back, findsWidgets);
          await tester.tap(back.last);
          await reviewPumpPageTransitions(tester);
          await tester.pump();
        }

        void expectFixtureNumbers(ComingNightSleepPlan plan) {
          expect(plan.needSeconds, closeTo(needSeconds, 0.0001));
          expect(plan.needSeconds, closeTo(30805.7142857, 0.0001));
          expect(plan.bedtimeMinuteOfDay, closeTo(bedtimeMinute, 0.0001));
          expect(plan.bedtimeMinuteOfDay, closeTo(1319.548872, 0.0001));
          expect(plan.wakeMinuteOfDay, closeTo(wakeMinute, 0.0001));
          expect(plan.wakeMinuteOfDay, closeTo(420, 0.0001));
          expect(plan.napCreditMin, 0);
          expect(plan.napCreditMin, isNotNull);
          expect(plan.strainBonusMin, closeTo(strainBonusMin, 0.0001));
          expect(plan.strainBonusMin, closeTo(3.42857, 0.0001));
          expect(plan.algoVersion, kAlgoVersion);
          expect(plan.algoVersion, 90);
          expect(plan.nightStartDay, day);
          expect(plan.wakeDay, wakeDay);
        }

        void expectFullPlanCopy() {
          expect(find.text('Heute Nacht'), findsOneWidget);
          expect(find.text('15./16. September'), findsOneWidget);
          expect(find.text('Geschätzter Schlafbedarf'), findsOneWidget);
          expect(find.text('8 h 33'), findsOneWidget);
          expect(find.text('Stand 07:42'), findsOneWidget);
          expect(find.text('22:00'), findsOneWidget);
          expect(find.text('07:00'), findsOneWidget);
          expect(find.text('Noch keine Schätzung'), findsNothing);
          expect(find.text('Laden fehlgeschlagen'), findsNothing);
          expect(find.text('Belastung fehlt'), findsNothing);
          expect(find.text('Nickerchen unvollständig'), findsNothing);
          expect(find.text('Aktualität unbekannt'), findsNothing);
          expect(find.text('Zeitplanung unvollständig'), findsNothing);
          expect(find.text('Aufwachzeiten fehlen'), findsNothing);
        }

        final repository = await loadRepo();
        expect(kAlgoVersion, 90);
        expect(strainBonusMin, closeTo(3.42857, 0.0001));
        final artifact = repository.sleepPlanArtifact!;
        expect(artifact['algo_version'], 90);
        expect(artifact['built_for_day'], day);
        expect(artifact['built_at_epoch'], builtEpoch);
        expect(artifact['input_read_started_at_ms'], inputReadStartedAtMs);
        expect(artifact['n_days'], 14);
        final recent = artifact['recent'] as List;
        expect(recent, isNotEmpty);
        final recentDates = [
          for (final row in recent) (row as Map)['date'] as String,
        ];
        expect(recentDates.toSet().length, recentDates.length);
        expect(recentDates.every((date) => date.compareTo(day) <= 0), isTrue);
        expect(recentDates.last, day);
        expect(artifact['n_days'], recentDates.length);
        expect(repository.sleepPlanObservations, isNotEmpty);
        expect(
          repository.sleepPlanObservations.map((row) => row.day).toList(),
          recentDates,
        );
        expect(
          repository.sleepPlanObservations.every(
            (row) =>
                row.inFetchWindow &&
                !row.skipped &&
                row.computedAtMs != null &&
                row.computedAtMs! < inputReadStartedAtMs,
          ),
          isTrue,
        );

        final mapped = sleepPlanFromStoredCrossday(
          requestedDay: day,
          now: now,
          algoVersion: kAlgoVersion,
          artifact: artifact,
          jobs: repository.sleepPlanJobs,
          observations: repository.sleepPlanObservations,
        );
        expect(mapped.status, SleepPlanStatus.available);
        expect(mapped.plan, isNotNull);
        expect(mapped.plan!.freshness, SleepPlanFreshness.fresh);
        expectFixtureNumbers(mapped.plan!);
        expect(mapped.plan!.napCreditMin, 0);
        expect(mapped.plan!.napCreditMin, isNotNull);

        var controller = await mountSleep(repository: repository);
        expect(controller.selectedDay, day);
        expect(find.text('Schlafziel'), findsOneWidget);
        await revealIn(find.byType(OpenBandSleep), find.text('Heute Nacht'));
        expect(find.text('Heute Nacht').hitTestable(), findsOneWidget);
        await capture('sleep-plan-parent');
        await openTonight();
        expect(
          tester.widget<OpenBandSleepPlan>(find.byType(OpenBandSleepPlan)).day,
          day,
        );
        expect(repository.requestedDays, contains(day));
        expect(repository.clocks, isNotEmpty);
        expect(repository.clocks.every((clock) => clock != null), isTrue);
        expect(controller.selectedDay, day);
        expectFullPlanCopy();
        final source = await repository.readSleepPlan(day, now: now);
        expect(source.plan, isNotNull);
        expectFixtureNumbers(source.plan!);
        await capture('sleep-plan');

        await tester.tap(find.byTooltip('Zur Schätzung'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Zur Schätzung'), findsWidgets);
        expect(
          find.text(
            'Aus gespeicherten Nächten, Belastung und Nickerchen. Kein gemessener persönlicher Schlafbedarf.',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'Die Abendplanung nutzt typische Aufwachzeiten und Schlafeffizienz. Sie stellt keinen Wecker.',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'Berücksichtigt: Belastung +3 Min · Nickerchen 0 Min. Stand 15. September, 07:42 · Modell $kAlgoVersion.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Die Zeitzone der Berechnung wurde nicht gespeichert.'),
          findsOneWidget,
        );
        expect(find.textContaining('Nickerchen 0 Min'), findsWidgets);
        expect(find.textContaining('Nickerchen unvollständig'), findsNothing);
        await capture('sleep-plan-info');
        await tester.tap(find.byTooltip('Schließen'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('8 h 33'), findsOneWidget);

        await revealIn(
          find.byType(OpenBandSleepPlan),
          find.text('Eigenes Schlafziel'),
        );
        await tester.tap(find.text('Eigenes Schlafziel').hitTestable());
        await tester.pump();
        var goalFrames = 0;
        while (find.byType(OpenBandSleepGoal).evaluate().isEmpty ||
            find.text('Ab 16. September').evaluate().isEmpty) {
          if (++goalFrames > 80) {
            throw FlutterError('Sleep goal did not finish loading.');
          }
          await tester.pump(const Duration(milliseconds: 16));
        }
        await reviewPumpPageTransitions(tester);
        expect(
          tester.widget<OpenBandSleepGoal>(find.byType(OpenBandSleepGoal)).day,
          wakeDay,
        );
        expect(controller.selectedDay, day);
        await capture('sleep-plan-goal');
        await popPlan();
        expect(find.byType(OpenBandSleepPlan), findsOneWidget);
        expect(
          tester.widget<OpenBandSleepPlan>(find.byType(OpenBandSleepPlan)).day,
          day,
        );
        expect(controller.selectedDay, day);
        await popPlan();
        expect(find.byType(OpenBandSleepPlan), findsNothing);
        expect(find.byType(OpenBandSleep), findsOneWidget);
        expect(controller.selectedDay, day);
        await revealIn(find.byType(OpenBandSleep), find.text('Heute Nacht'));
        expect(find.text('Heute Nacht').hitTestable(), findsOneWidget);
        await capture('sleep-plan-parent-return');
        controller.dispose();

        resetPlan(repository);
        controller = await mountSleep(
          repository: repository,
          brightness: Brightness.dark,
        );
        await openTonight();
        expectFullPlanCopy();
        await capture('sleep-plan-dark');
        await tester.tap(find.byTooltip('Zur Schätzung'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          find.text(
            'Berücksichtigt: Belastung +3 Min · Nickerchen 0 Min. Stand 15. September, 07:42 · Modell $kAlgoVersion.',
          ),
          findsOneWidget,
        );
        await capture('sleep-plan-info-dark');
        await tester.tap(find.byTooltip('Schließen'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        controller.dispose();

        resetPlan(repository, missingArtifact: true);
        await mountPlan(repository: repository);
        expect(find.text('8 h 33'), findsNothing);
        expect(find.text('—'), findsWidgets);
        expect(find.text('Noch keine Schätzung'), findsOneWidget);
        expect(find.text('Laden fehlgeschlagen'), findsNothing);
        await capture('sleep-plan-empty');
        await mountPlan(repository: repository, brightness: Brightness.dark);
        expect(find.text('Noch keine Schätzung'), findsOneWidget);
        await capture('sleep-plan-empty-dark');

        resetPlan(
          repository,
          artifact: fixtureArtifact(times: false, strain: strainBonusMin),
        );
        await mountPlan(repository: repository);
        expect(find.text('8 h 33'), findsOneWidget);
        expect(find.text('Stand 07:42'), findsOneWidget);
        expect(find.text('22:00'), findsNothing);
        expect(find.text('07:00'), findsNothing);
        expect(find.text('Zeitplanung unvollständig'), findsOneWidget);
        expect(find.text('Aufwachzeiten fehlen'), findsNothing);
        await capture('sleep-plan-partial');
        await mountPlan(repository: repository, brightness: Brightness.dark);
        expect(find.text('Zeitplanung unvollständig'), findsOneWidget);
        expect(find.text('Aufwachzeiten fehlen'), findsNothing);
        await capture('sleep-plan-partial-dark');

        resetPlan(repository);
        repository.failSleepPlanRead = true;
        await mountPlan(repository: repository);
        expect(find.text('Laden fehlgeschlagen'), findsOneWidget);
        expect(find.text('Erneut versuchen').hitTestable(), findsOneWidget);
        expect(find.text('8 h 33'), findsNothing);
        expect(find.text('Noch keine Schätzung'), findsNothing);
        await capture('sleep-plan-error');
        repository.failSleepPlanRead = false;
        await tester.tap(find.text('Erneut versuchen').hitTestable());
        await tester.pump();
        var retryFrames = 0;
        while (find.text('8 h 33').evaluate().isEmpty) {
          if (++retryFrames > 80) {
            throw FlutterError('Sleep plan retry did not restore the fixture.');
          }
          await tester.pump(const Duration(milliseconds: 16));
        }
        await reviewPumpPageTransitions(tester);
        expect(find.text('8 h 33'), findsOneWidget);
        expect(find.text('Laden fehlgeschlagen'), findsNothing);
        await capture('sleep-plan-error-retry');
        repository.failSleepPlanRead = true;
        await mountPlan(repository: repository, brightness: Brightness.dark);
        expect(find.text('Laden fehlgeschlagen'), findsOneWidget);
        await capture('sleep-plan-error-dark');

        resetPlan(
          repository,
          observations: fixtureObservations(
            artifact: fixtureArtifact(strain: strainBonusMin),
            computedAtMs: inputReadStartedAtMs,
          ),
        );
        await mountPlan(repository: repository);
        expect(find.text('8 h 33'), findsNothing);
        expect(find.text('22:00'), findsNothing);
        expect(find.text('Schätzung nicht aktuell'), findsOneWidget);
        expect(find.text('Noch keine Schätzung'), findsNothing);
        await capture('sleep-plan-stale');

        resetPlan(
          repository,
          artifact: fixtureArtifact(need: 100, strain: strainBonusMin),
        );
        await mountPlan(repository: repository);
        expect(find.text('8 h 33'), findsNothing);
        expect(find.text('Schätzung nicht lesbar'), findsOneWidget);
        expect(find.text('Noch keine Schätzung'), findsNothing);
        await capture('sleep-plan-corrupt');

        resetPlan(
          repository,
          artifact: fixtureArtifact(
            window: false,
            provenance: false,
            strain: strainBonusMin,
          ),
        );
        await mountPlan(repository: repository);
        expect(find.text('8 h 33'), findsOneWidget);
        expect(find.text('Aktualität unbekannt'), findsOneWidget);
        expect(find.text('Stand 07:42'), findsNothing);
        await capture('sleep-plan-unknown');

        resetPlan(repository, artifact: fixtureArtifact(strain: null, nap: 0));
        await mountPlan(repository: repository);
        final missing = await repository.readSleepPlan(day, now: now);
        expect(missing.plan, isNotNull);
        expect(missing.plan!.napCreditMin, 0);
        expect(missing.plan!.napCreditMin, isNotNull);
        expect(missing.plan!.strainBonusMin, isNull);
        expect(find.text('8 h 33'), findsOneWidget);
        expect(find.text('Belastung fehlt'), findsOneWidget);
        expect(find.text('Nickerchen unvollständig'), findsNothing);
        await tester.tap(find.byTooltip('Zur Schätzung'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.textContaining('Belastung fehlt'), findsWidgets);
        expect(find.textContaining('Nickerchen 0 Min'), findsOneWidget);
        await tester.tap(find.byTooltip('Schließen'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await capture('sleep-plan-missing-contribution');

        resetPlan(
          repository,
          artifact: fixtureArtifact(strain: strainBonusMin, nap: null),
        );
        await mountPlan(repository: repository);
        final nullNap = await repository.readSleepPlan(day, now: now);
        expect(nullNap.plan, isNotNull);
        expect(nullNap.plan!.napCreditMin, isNull);
        expect(nullNap.plan!.strainBonusMin, isNotNull);
        expect(find.text('Nickerchen unvollständig'), findsOneWidget);
        expect(find.text('Belastung fehlt'), findsNothing);

        Future<void> captureScaled({
          required String name,
          required Brightness brightness,
          required bool scrolled,
        }) async {
          resetPlan(repository);
          await mountPlan(
            repository: repository,
            brightness: brightness,
            scale: 2,
          );
          expect(find.text('8 h 33'), findsOneWidget);
          final bed = tester.getRect(find.text('Ins Bett · geschätzt'));
          final rise = tester.getRect(find.text('Aufstehen · typisch'));
          expect(rise.top, greaterThan(bed.bottom + 8));
          final plan = find.byType(OpenBandSleepPlan);
          final origin = scrollPixels(plan);
          final goal = find.text('Eigenes Schlafziel');
          if (scrolled) {
            await revealIn(plan, goal);
            expect(goal.evaluate(), isNotEmpty);
            final card = find
                .ancestor(of: goal, matching: find.byType(OBCard))
                .first;
            final row = find
                .ancestor(of: goal, matching: find.byType(OBSettingsValueRow))
                .first;
            await Scrollable.ensureVisible(
              tester.element(card),
              alignment: 1.0,
            );
            await tester.pump();
            final scrollable = downScrollable(plan).first;
            var extra = 0;
            while (!rectInSafeViewport(tester.getRect(card)) ||
                !rectInSafeViewport(tester.getRect(row))) {
              if (extra >= 32) {
                throw FlutterError(
                  'Goal card is not fully within the safe viewport.',
                );
              }
              final box = tester.getRect(card);
              final safe = reviewSafeViewport();
              final overflowBottom = box.bottom - safe.bottom;
              final overflowTop = safe.top - box.top;
              final dy = overflowBottom > 0
                  ? -(overflowBottom + 8)
                  : overflowTop + 8;
              await tester.drag(scrollable, Offset(0, dy.clamp(-96.0, 96.0)));
              await tester.pump();
              extra++;
            }
            await tester.pump();
            final safe = reviewSafeViewport();
            final cardBox = tester.getRect(card);
            final rowBox = tester.getRect(row);
            expect(cardBox.top, greaterThanOrEqualTo(safe.top));
            expect(cardBox.bottom, lessThanOrEqualTo(safe.bottom));
            expect(cardBox.left, greaterThanOrEqualTo(safe.left));
            expect(cardBox.right, lessThanOrEqualTo(safe.right));
            expect(rowBox.top, greaterThanOrEqualTo(safe.top));
            expect(rowBox.bottom, lessThanOrEqualTo(safe.bottom));
            expect(rowBox.left, greaterThanOrEqualTo(safe.left));
            expect(rowBox.right, lessThanOrEqualTo(safe.right));
            expect(goal.hitTestable(), findsOneWidget);
            expect(card.hitTestable(), findsOneWidget);
            await capture(name);
            await tester.tap(card.hitTestable());
            await tester.pump();
            var goalFrames = 0;
            while (find.byType(OpenBandSleepGoal).evaluate().isEmpty ||
                find.text('Ab 16. September').evaluate().isEmpty) {
              if (++goalFrames > 80) {
                throw FlutterError('Sleep goal did not finish loading at 2x.');
              }
              await tester.pump(const Duration(milliseconds: 16));
            }
            await reviewPumpPageTransitions(tester);
            expect(
              tester
                  .widget<OpenBandSleepGoal>(find.byType(OpenBandSleepGoal))
                  .day,
              wakeDay,
            );
            await popPlan();
            expect(find.byType(OpenBandSleepPlan), findsOneWidget);
            expect(
              tester
                  .widget<OpenBandSleepPlan>(find.byType(OpenBandSleepPlan))
                  .day,
              day,
            );
          } else {
            await restoreScroll(plan, origin);
            expect(find.text('Heute Nacht'), findsOneWidget);
            expect(find.text('8 h 33'), findsOneWidget);
            await capture(name);
          }
        }

        await captureScaled(
          name: 'sleep-plan-2x',
          brightness: Brightness.light,
          scrolled: false,
        );
        await captureScaled(
          name: 'sleep-plan-2x-scrolled',
          brightness: Brightness.light,
          scrolled: true,
        );
        await captureScaled(
          name: 'sleep-plan-2x-dark',
          brightness: Brightness.dark,
          scrolled: false,
        );
        await captureScaled(
          name: 'sleep-plan-2x-scrolled-dark',
          brightness: Brightness.dark,
          scrolled: true,
        );

        resetPlan(repository);
        controller = await mountSleep(
          repository: repository,
          selectedDay: pastDay,
        );
        expect(controller.selectedDay, pastDay);
        await revealIn(find.byType(OpenBandSleep), find.text('Schlafziel'));
        expect(find.text('Heute Nacht'), findsNothing);
        expect(find.text('Schlafziel').hitTestable(), findsOneWidget);
        expect(repository.requestedDays, isEmpty);
        await capture('sleep-plan-parent-past');
        controller.dispose();
      }

      Future<void> reviewExercisePicker() async {
        final bench = _pickerPreset('bench_press');
        final plank = _pickerPreset('plank');
        final labels = _pickerLabelsAlphabetical();
        expect(kExercisePresets, hasLength(18));
        expect(labels, [
          'Bankdrücken',
          'Beinpresse',
          'Kabelzug-Flys',
          'Klimmzug',
          'Unterarmstütz',
        ]);

        Future<_ExercisePickerReviewRepo> loadRepo() async {
          Future<Map> load(String name) async =>
              jsonDecode(
                    await rootBundle.loadString(
                      'docs/openband5/assets/fixtures/$name.json',
                    ),
                  )
                  as Map;
          final repo = _ExercisePickerReviewRepo(
            await load('day-summary'),
            await load('sleep-detail'),
            activity: await load('additional-flows'),
            run: await load('run-detail'),
          );
          await repo.seedNutritionGoals();
          return repo;
        }

        Widget reviewHost({
          required Widget home,
          Brightness brightness = Brightness.light,
          double scale = 1,
        }) => MaterialApp(
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
          home: home,
        );

        Finder downScrollable(Finder ancestor) => find.descendant(
          of: ancestor,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        );

        Rect reviewSafeViewport({Finder? contentOf}) {
          final view = tester.view;
          final dpr = view.devicePixelRatio;
          final size = view.physicalSize / dpr;
          final pad = view.viewPadding;
          final screen = Rect.fromLTRB(
            pad.left / dpr,
            pad.top / dpr,
            size.width - pad.right / dpr,
            size.height - pad.bottom / dpr,
          );
          if (contentOf == null) return screen;
          final box = tester.getRect(downScrollable(contentOf).first);
          return Rect.fromLTRB(
            box.left < screen.left ? screen.left : box.left,
            box.top < screen.top ? screen.top : box.top,
            box.right > screen.right ? screen.right : box.right,
            box.bottom > screen.bottom ? screen.bottom : box.bottom,
          );
        }

        bool rectInSafeViewport(
          Rect box, {
          Finder? contentOf,
          double slop = 0.5,
        }) {
          final safe = reviewSafeViewport(contentOf: contentOf);
          return box.top >= safe.top - slop &&
              box.bottom <= safe.bottom + slop &&
              box.left >= safe.left - slop &&
              box.right <= safe.right + slop;
        }

        Future<void> expectInSafeViewport(
          Finder target, {
          Finder? contentOf,
        }) async {
          expect(target, findsWidgets);
          expect(
            rectInSafeViewport(tester.getRect(target), contentOf: contentOf),
            isTrue,
          );
        }

        Future<void> restoreScroll(Finder ancestor, double offset) async {
          final position = tester
              .state<ScrollableState>(downScrollable(ancestor).first)
              .position;
          position.jumpTo(
            offset.clamp(position.minScrollExtent, position.maxScrollExtent),
          );
          await tester.pump();
        }

        Future<void> revealIn(Finder ancestor, Finder target) async {
          final scrollable = downScrollable(ancestor).first;
          var scrolls = 0;
          while (target.evaluate().isEmpty ||
              target.hitTestable().evaluate().isEmpty) {
            if (scrolls >= 32) {
              throw FlutterError(
                'Control is not hit-testable after production scrolling.',
              );
            }
            if (target.evaluate().isEmpty) {
              final position = tester
                  .state<ScrollableState>(scrollable)
                  .position;
              final atMin = position.pixels <= position.minScrollExtent + 0.5;
              final atMax = position.pixels >= position.maxScrollExtent - 0.5;
              final dy = !atMin
                  ? 64.0
                  : !atMax
                  ? -64.0
                  : 0.0;
              if (dy == 0) {
                throw FlutterError(
                  'Control is not hit-testable after production scrolling.',
                );
              }
              await tester.drag(scrollable, Offset(0, dy));
              await tester.pump();
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
        }

        Future<void> ensureFullyInSafeViewport(
          Finder ancestor,
          Finder target, {
          bool content = true,
        }) async {
          await revealIn(ancestor, target);
          final scrollable = downScrollable(ancestor).first;
          final contentOf = content ? ancestor : null;
          var extra = 0;

          String diagnostics() {
            final box = tester.getRect(target);
            final safe = reviewSafeViewport(contentOf: contentOf);
            final position = tester.state<ScrollableState>(scrollable).position;
            return 'target=$box safe=$safe '
                'overflowTop=${safe.top - box.top} '
                'overflowBottom=${box.bottom - safe.bottom} '
                'overflowLeft=${safe.left - box.left} '
                'overflowRight=${box.right - safe.right} '
                'scroll=${position.pixels} '
                'extent=${position.minScrollExtent}..${position.maxScrollExtent} '
                'viewport=${position.viewportDimension} extra=$extra';
          }

          while (!rectInSafeViewport(
            tester.getRect(target),
            contentOf: contentOf,
          )) {
            if (extra >= 32) {
              throw FlutterError(
                'Control is not fully within the safe viewport.\n${diagnostics()}',
              );
            }
            final box = tester.getRect(target);
            final safe = reviewSafeViewport(contentOf: contentOf);
            final overflowBottom = box.bottom - safe.bottom;
            final overflowTop = safe.top - box.top;
            if (extra == 0) {
              await Scrollable.ensureVisible(
                tester.element(target),
                alignment: overflowBottom >= overflowTop ? 1.0 : 0.0,
              );
              await tester.pump();
            } else {
              const minGesture = 64.0;
              final needed = overflowBottom > 0
                  ? -(overflowBottom + 8)
                  : overflowTop + 8;
              final dy = needed < 0
                  ? (needed > -minGesture ? -minGesture : needed)
                  : (needed < minGesture ? minGesture : needed);
              await tester.drag(scrollable, Offset(0, dy));
              await tester.pump();
            }
            extra++;
          }
          expect(
            rectInSafeViewport(tester.getRect(target), contentOf: contentOf),
            isTrue,
          );
          expect(target.hitTestable(), findsOneWidget);
        }

        Future<void> pumpUntil(bool Function() ready, String message) async {
          await tester.pump();
          var frames = 0;
          while (!ready()) {
            if (++frames > 80) {
              throw FlutterError(message);
            }
            await tester.pump(const Duration(milliseconds: 16));
          }
          await reviewPumpPageTransitions(tester);
        }

        Future<void> pumpSheet() async {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
        }

        Future<void> mountEditor({
          required _ExercisePickerReviewRepo repository,
          WorkoutTemplate? template,
          Brightness brightness = Brightness.light,
          double scale = 1,
        }) async {
          await tester.pumpWidget(
            reviewHost(
              brightness: brightness,
              scale: scale,
              home: OpenBandTemplateEditor(
                repository: repository,
                template: template,
              ),
            ),
          );
          await pumpUntil(
            () => find.byType(OpenBandTemplateEditor).evaluate().isNotEmpty,
            'Template editor did not finish loading.',
          );
        }

        Future<WorkoutTemplate> fixtureA(
          _ExercisePickerReviewRepo repository,
        ) async {
          final templates = await repository.readTemplates();
          return templates.firstWhere((t) => t.id == 'tpl-ganzkoerper-a');
        }

        List<String> sessionStamp(List<TrainingSession> sessions) => [
          for (final s in sessions)
            '${s.id}|${s.durationMin}|${s.start.millisecondsSinceEpoch}',
        ];

        Map<String, String> templateStamp(List<WorkoutTemplate> templates) => {
          for (final t in templates) t.id: jsonEncode(t.toJson()),
        };

        Future<void> expectFixturesUnchanged(
          _ExercisePickerReviewRepo repository, {
          required Map<String, String> templates,
          required List<String> sessions,
        }) async {
          expect(repository.templateSaves, 0);
          final a = await fixtureA(repository);
          expect(a.exercises, hasLength(4));
          expect(a.workSets, 12);
          expect(templateStamp(await repository.readTemplates()), templates);
          expect(
            sessionStamp(await repository.readSessions('2026-09-15', 14)),
            sessions,
          );
        }

        Finder plusOf(String id) => find.byKey(ValueKey('exercise-select-$id'));

        Finder openOf(String id) => find.byKey(ValueKey('exercise-open-$id'));

        Finder inPicker(Finder matching) => find.descendant(
          of: find.byType(OpenBandExercisePicker),
          matching: matching,
        );

        bool pickerCatalogueReady() {
          if (find.byType(OpenBandExercisePicker).evaluate().isEmpty) {
            return false;
          }
          if (find.text('Bibliothek nicht geladen').evaluate().isNotEmpty) {
            return true;
          }
          if (find.text('Keine Übungen').evaluate().isNotEmpty) {
            return true;
          }
          return find.text('5 Übungen').evaluate().isNotEmpty ||
              find.text('6 Übungen').evaluate().isNotEmpty ||
              find.text('0 Übungen').evaluate().isNotEmpty ||
              find.textContaining('nicht lesbar').evaluate().isNotEmpty;
        }

        Future<void> pumpPickerReady() async {
          await pumpUntil(
            pickerCatalogueReady,
            'Exercise picker did not finish loading.',
          );
        }

        Future<void> openAddSheet() async {
          final editor = find.byType(OpenBandTemplateEditor);
          final add = find.widgetWithText(OBAction, 'Übung hinzufügen');
          await ensureFullyInSafeViewport(editor, add);
          await tester.tap(add.hitTestable());
          await pumpSheet();
          expect(find.text('Bibliothek'), findsOneWidget);
          expect(find.text('Eigene Übung'), findsOneWidget);
          expect(find.text('Eigene Zeitübung'), findsOneWidget);
        }

        Future<void> openPicker() async {
          await openAddSheet();
          await tester.tap(find.text('Bibliothek'));
          await pumpPickerReady();
        }

        Future<void> popRoute() async {
          await tester.tap(find.byTooltip('Zurück'));
          await reviewPumpPageTransitions(tester);
          await tester.pump();
        }

        Finder addSelectedAction() =>
            find.widgetWithText(OBAction, '2 Übungen hinzufügen');

        Finder saveAction() =>
            find.widgetWithText(OBAction, 'Vorlage speichern');

        Future<void> pumpInk() async {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        }

        Future<void> selectBenchAndPlank() async {
          final picker = find.byType(OpenBandExercisePicker);
          final benchSelect = plusOf(bench.id);
          final plankSelect = plusOf(plank.id);
          await ensureFullyInSafeViewport(picker, benchSelect);
          await tester.tap(benchSelect.hitTestable());
          await tester.pump();
          await ensureFullyInSafeViewport(picker, plankSelect);
          await tester.tap(plankSelect.hitTestable());
          await pumpInk();
          expect(addSelectedAction(), findsOneWidget);
          await restoreScroll(picker, 0);
        }

        Future<void> tapFilterChip(Key key) async {
          final chip = find.byKey(key);
          final page = find.ancestor(
            of: find.text('Filter'),
            matching: find.byType(Scaffold),
          );
          await ensureFullyInSafeViewport(page, chip);
          await tester.tap(chip.hitTestable());
          await pumpInk();
        }

        Future<void> openFilterPage() async {
          final picker = find.byType(OpenBandExercisePicker);
          final trigger = find.byKey(const ValueKey('exercise-filter-muscles'));
          await ensureFullyInSafeViewport(picker, trigger);
          await tester.tap(trigger.hitTestable());
          await reviewPumpPageTransitions(tester);
          await tester.pump();
          expect(find.text('Filter'), findsOneWidget);
        }

        Future<void> selectChestAndBarbell() async {
          await tapFilterChip(const ValueKey('filter-muscle-chest'));
          await tapFilterChip(const ValueKey('filter-equipment-barbell'));
        }

        Future<void> applyFilter() async {
          final apply = find.widgetWithText(OBAction, 'Filter anwenden');
          await expectInSafeViewport(apply);
          await tester.tap(apply.hitTestable());
          await reviewPumpPageTransitions(tester);
          await tester.pump();
        }

        void expectBankOnlyWithHiddenSelection() {
          expect(plusOf(bench.id), findsOneWidget);
          expect(plusOf(plank.id), findsNothing);
          expect(plusOf('cable_fly'), findsNothing);
          expect(plusOf('leg_press'), findsNothing);
          expect(plusOf('pull_up'), findsNothing);
          expect(inPicker(find.text(bench.labelDe)), findsOneWidget);
          expect(inPicker(find.text(plank.labelDe)), findsNothing);
          expect(inPicker(find.text('Kabelzug-Flys')), findsNothing);
          expect(
            inPicker(find.text('1 Übung · 1 Auswahl außerhalb')),
            findsOneWidget,
          );
          expect(addSelectedAction(), findsOneWidget);
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('exercise-filter-muscles')),
              matching: find.text('Brust'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('exercise-filter-equipment')),
              matching: find.text('Langhantel'),
            ),
            findsOneWidget,
          );
        }

        double keyboardInset() =>
            tester.view.viewInsets.bottom / tester.view.devicePixelRatio;

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
          expect(keyboardInset(), 0);
        }

        Future<void> enterFocused(Finder field, String text) async {
          await settleKeyboard(field);
          await tester.enterText(field, text);
          await tester.pump();
          expect(tester.widget<TextField>(field).controller!.text, text);
        }

        Future<void> nameDraft(String name) async {
          await tester.enterText(find.byType(TextField).first, name);
          await tester.pump();
          await dismissKeyboard();
        }

        Future<void> expectUnknownDetail() async {
          expect(find.text(_kUnknownImportedExerciseLabel), findsWidgets);
          expect(find.text('Nicht festgelegt'), findsOneWidget);
          expect(find.text('Importiert'), findsNothing);
          expect(find.text('Gespeichert'), findsNothing);
          expect(find.text('Maschine'), findsOneWidget);
          expect(find.text('Erfassung'), findsOneWidget);
          expect(
            tester
                .widget<OBAction>(find.widgetWithText(OBAction, 'Auswählen'))
                .onPressed,
            isNull,
          );
        }

        void expectVisibleLabels(Iterable<String> expected) {
          for (final label in expected) {
            expect(inPicker(find.text(label)), findsOneWidget);
          }
        }

        void expectAlphabeticalVisible() {
          expectVisibleLabels(labels);
          final tops = [
            for (final label in labels)
              tester.getRect(inPicker(find.text(label))).top,
          ];
          for (var i = 1; i < tops.length; i++) {
            expect(tops[i], greaterThan(tops[i - 1]));
          }
        }

        Finder exerciseCard(String label) => find
            .ancestor(
              of: find.byWidgetPredicate(
                (widget) =>
                    widget is TextField && widget.controller?.text == label,
              ),
              matching: find.byType(OBCard),
            )
            .first;

        void expectEmptyDraft(String label, {required bool timed}) {
          final card = exerciseCard(label);
          final fields = find.descendant(
            of: card,
            matching: find.byType(TextField),
          );
          final texts = [
            for (final element in fields.evaluate())
              (element.widget as TextField).controller!.text,
          ];
          expect(texts.first, label);
          expect(texts, hasLength(timed ? 2 : 3));
          expect(texts.skip(1), everyElement(isEmpty));
          expect(
            find.descendant(of: card, matching: find.text('Sek.')),
            timed ? findsWidgets : findsNothing,
          );
          expect(
            find.descendant(of: card, matching: find.text('Wdh.')),
            timed ? findsNothing : findsWidgets,
          );
        }

        Future<void> confirmSelectedIntoDraft() async {
          final add = addSelectedAction();
          await expectInSafeViewport(add);
          await tester.tap(add.hitTestable());
          await reviewPumpPageTransitions(tester);
          await tester.pump();
          expect(find.byType(OpenBandExercisePicker), findsNothing);
          expect(find.byType(OpenBandTemplateEditor), findsOneWidget);
          expectEmptyDraft(bench.labelDe, timed: false);
          expectEmptyDraft(plank.labelDe, timed: true);
        }

        Future<void> addBenchAndPlankToDraft({
          required _ExercisePickerReviewRepo repository,
          Brightness brightness = Brightness.light,
          double scale = 1,
          String name = '',
        }) async {
          await mountEditor(
            repository: repository,
            brightness: brightness,
            scale: scale,
          );
          await openPicker();
          await selectBenchAndPlank();
          await confirmSelectedIntoDraft();
          if (name.isNotEmpty) {
            await nameDraft(name);
          }
        }

        final repository = await loadRepo();
        final originalTemplates = templateStamp(
          await repository.readTemplates(),
        );
        final originalSessions = sessionStamp(
          await repository.readSessions('2026-09-15', 14),
        );
        final originalA = await fixtureA(repository);
        expect(originalA.exercises, hasLength(4));
        expect(originalA.workSets, 12);
        expect(assembleExerciseCatalogue(const []).entries, hasLength(18));

        await mountEditor(repository: repository);
        await openAddSheet();
        await capture('exercise-picker-add-sheet');
        await tester.tap(find.text('Bibliothek'));
        await pumpPickerReady();
        expect(inPicker(find.text('5 Übungen')), findsOneWidget);
        expectAlphabeticalVisible();
        await selectBenchAndPlank();
        expect(inPicker(find.text(bench.labelDe)), findsOneWidget);
        expect(inPicker(find.text(plank.labelDe)), findsOneWidget);
        await capture('exercise-picker');

        await openFilterPage();
        await selectChestAndBarbell();
        expect(find.text('Filter'), findsOneWidget);
        await capture('exercise-picker-filter');
        await applyFilter();
        expectBankOnlyWithHiddenSelection();
        await capture('exercise-picker-filtered');

        await openFilterPage();
        await tapFilterChip(const ValueKey('filter-muscle-legs'));
        await popRoute();
        expectBankOnlyWithHiddenSelection();

        await tester.tap(openOf(bench.id));
        await reviewPumpPageTransitions(tester);
        await tester.pump();
        expect(find.text('Übung'), findsOneWidget);
        expect(find.text(bench.labelDe), findsWidgets);
        expect(find.text('Gerät'), findsOneWidget);
        expect(
          find.descendant(
            of: find.ancestor(
              of: find.text('Gerät'),
              matching: find.byType(Scaffold),
            ),
            matching: find.text('Langhantel'),
          ),
          findsOneWidget,
        );
        expect(find.text('Wiederholungen'), findsOneWidget);
        expect(find.text('OpenBand'), findsOneWidget);
        await capture('exercise-picker-detail');
        await popRoute();
        expect(find.byType(OpenBandExercisePicker), findsOneWidget);
        expect(inPicker(find.text(bench.labelDe)), findsOneWidget);
        expect(find.text('2 Übungen hinzufügen'), findsOneWidget);

        await openFilterPage();
        await tester.tap(find.text('Zurücksetzen'));
        await tester.pump();
        await applyFilter();
        expectAlphabeticalVisible();
        expect(addSelectedAction(), findsOneWidget);
        await confirmSelectedIntoDraft();
        await expectFixturesUnchanged(
          repository,
          templates: originalTemplates,
          sessions: originalSessions,
        );
        await nameDraft('Kurztraining');
        expect(tester.widget<OBAction>(saveAction()).onPressed, isNotNull);
        await capture('exercise-picker-draft');

        await tester.tap(saveAction());
        await reviewPumpPageTransitions(tester);
        await tester.pump();
        expect(repository.templateSaves, 1);
        final saved = (await repository.readTemplates()).firstWhere(
          (t) => t.name == 'Kurztraining',
        );
        expect(saved.exercises, hasLength(2));
        final savedPlank = saved.exercises.firstWhere(
          (e) => e.exerciseKey == plank.id,
        );
        expect(savedPlank.sets, hasLength(1));
        expect(savedPlank.sets.single.mode, PlannedSetMode.time);
        expect(savedPlank.sets.single.seconds, isNull);
        expect(savedPlank.sets.single.reps, isNull);
        expect(savedPlank.sets.single.loadKg, isNull);
        expect((await fixtureA(repository)).exercises, hasLength(4));
        expect(
          sessionStamp(await repository.readSessions('2026-09-15', 14)),
          originalSessions,
        );
        await mountEditor(repository: repository, template: saved);
        expectEmptyDraft(plank.labelDe, timed: true);
        await capture('exercise-picker-reopen');

        final inPlanRepo = await loadRepo();
        await mountEditor(
          repository: inPlanRepo,
          template: await fixtureA(inPlanRepo),
        );
        await openPicker();
        expect(inPicker(find.textContaining('Im Plan')), findsWidgets);
        await tester.tap(plusOf(bench.id));
        await pumpSheet();
        expect(find.text('Übung erneut hinzufügen?'), findsOneWidget);
        expect(find.byKey(const ValueKey('ob-confirm-no')), findsOneWidget);
        expect(find.byKey(const ValueKey('ob-confirm-yes')), findsOneWidget);
        await capture('exercise-picker-in-plan');
        await tester.tap(find.byKey(const ValueKey('ob-confirm-no')));
        await pumpSheet();
        expect(find.text('Übung erneut hinzufügen?'), findsNothing);
        expect(find.text('2 Übungen hinzufügen'), findsNothing);
        await tester.tap(plusOf(bench.id));
        await pumpSheet();
        await tester.tap(find.byKey(const ValueKey('ob-confirm-yes')));
        await pumpSheet();
        expect(find.text('1 Übung hinzufügen'), findsOneWidget);

        final unknownRepo = await loadRepo();
        unknownRepo.includeUnknownMode = true;
        await mountEditor(repository: unknownRepo);
        await openPicker();
        expect(
          inPicker(find.text(_kUnknownImportedExerciseLabel)),
          findsOneWidget,
        );
        expect(
          tester
              .widget<IconButton>(plusOf(_kUnknownImportedExerciseId))
              .onPressed,
          isNull,
        );
        await tester.tap(openOf(_kUnknownImportedExerciseId));
        await reviewPumpPageTransitions(tester);
        await tester.pump();
        await expectUnknownDetail();
        await capture('exercise-picker-unknown');

        final unknownDarkRepo = await loadRepo();
        unknownDarkRepo.includeUnknownMode = true;
        await mountEditor(
          repository: unknownDarkRepo,
          brightness: Brightness.dark,
        );
        await openPicker();
        expect(
          inPicker(find.text(_kUnknownImportedExerciseLabel)),
          findsOneWidget,
        );
        expect(
          tester
              .widget<IconButton>(plusOf(_kUnknownImportedExerciseId))
              .onPressed,
          isNull,
        );
        await tester.tap(openOf(_kUnknownImportedExerciseId));
        await reviewPumpPageTransitions(tester);
        await tester.pump();
        await expectUnknownDetail();
        await capture('exercise-picker-unknown-dark');

        final emptyRepo = await loadRepo();
        await mountEditor(repository: emptyRepo);
        await openPicker();
        await tester.enterText(
          find.byKey(const ValueKey('exercise-search')),
          'Ausfallschritte',
        );
        await tester.pump();
        await dismissKeyboard();
        expect(find.text('Keine Übungen gefunden'), findsOneWidget);
        expect(find.text('0 Übungen'), findsOneWidget);
        await capture('exercise-picker-empty');
        await tester.tap(find.widgetWithText(OBAction, 'Suche löschen'));
        await tester.pump();
        expectAlphabeticalVisible();
        expect(find.text('Keine Übungen gefunden'), findsNothing);

        final errorRepo = await loadRepo();
        errorRepo.failCatalogueRead = true;
        await mountEditor(repository: errorRepo);
        await openPicker();
        expect(find.text('Bibliothek nicht geladen'), findsOneWidget);
        expect(find.text('Keine Übungen gefunden'), findsNothing);
        await capture('exercise-picker-error');
        errorRepo.failCatalogueRead = false;
        await tester.tap(find.widgetWithText(OBAction, 'Erneut laden'));
        await pumpPickerReady();
        expect(find.text('Bibliothek nicht geladen'), findsNothing);
        expectAlphabeticalVisible();
        await capture('exercise-picker-error-retry');

        final errorDarkRepo = await loadRepo();
        errorDarkRepo.failCatalogueRead = true;
        await mountEditor(
          repository: errorDarkRepo,
          brightness: Brightness.dark,
        );
        await openPicker();
        expect(find.text('Bibliothek nicht geladen'), findsOneWidget);
        await capture('exercise-picker-error-dark');

        final partialRepo = await loadRepo();
        partialRepo.unreadableCount = 2;
        await mountEditor(repository: partialRepo);
        await openPicker();
        expect(find.text('5 Übungen · 2 nicht lesbar'), findsOneWidget);
        expectAlphabeticalVisible();
        await capture('exercise-picker-partial');

        final darkRepo = await loadRepo();
        await mountEditor(repository: darkRepo, brightness: Brightness.dark);
        await openPicker();
        await selectBenchAndPlank();
        await capture('exercise-picker-dark');
        await tester.tap(openOf(bench.id));
        await reviewPumpPageTransitions(tester);
        await tester.pump();
        await capture('exercise-picker-detail-dark');
        await popRoute();
        await openFilterPage();
        await selectChestAndBarbell();
        await capture('exercise-picker-filter-dark');

        Future<void> captureScaled({
          required String name,
          required Brightness brightness,
          required bool scrolled,
        }) async {
          final scaled = await loadRepo();
          await mountEditor(
            repository: scaled,
            brightness: brightness,
            scale: 2,
          );
          await openPicker();
          await selectBenchAndPlank();
          final picker = find.byType(OpenBandExercisePicker);
          await expectInSafeViewport(inPicker(find.text('Übungen')));
          await expectInSafeViewport(
            find.byKey(const ValueKey('exercise-search')),
            contentOf: picker,
          );
          await expectInSafeViewport(
            find.byKey(const ValueKey('exercise-filter-muscles')),
            contentOf: picker,
          );
          await expectInSafeViewport(
            inPicker(find.text(bench.labelDe)),
            contentOf: picker,
          );
          if (scrolled) {
            final footer = find.widgetWithText(
              OBAction,
              '2 Übungen hinzufügen',
            );
            final last = openOf(plank.id);
            await ensureFullyInSafeViewport(picker, last);
            await expectInSafeViewport(footer);
            expect(rectInSafeViewport(tester.getRect(footer)), isTrue);
            expect(
              rectInSafeViewport(tester.getRect(last), contentOf: picker),
              isTrue,
            );
            await capture(name);
            await tester.tap(footer.hitTestable());
            await reviewPumpPageTransitions(tester);
            await tester.pump();
            expect(find.byType(OpenBandExercisePicker), findsNothing);
            expectEmptyDraft(bench.labelDe, timed: false);
            expectEmptyDraft(plank.labelDe, timed: true);
          } else {
            await capture(name);
          }
        }

        await captureScaled(
          name: 'exercise-picker-2x',
          brightness: Brightness.light,
          scrolled: false,
        );
        await captureScaled(
          name: 'exercise-picker-2x-scrolled',
          brightness: Brightness.light,
          scrolled: true,
        );
        await captureScaled(
          name: 'exercise-picker-2x-dark',
          brightness: Brightness.dark,
          scrolled: false,
        );

        Future<void> captureParentScaled({
          required String name,
          required Brightness brightness,
          required bool scrolled,
        }) async {
          final scaled = await loadRepo();
          await addBenchAndPlankToDraft(
            repository: scaled,
            brightness: brightness,
            scale: 2,
            name: 'Kurztraining',
          );
          final editor = find.byType(OpenBandTemplateEditor);
          final save = saveAction();
          expect(tester.widget<OBAction>(save).onPressed, isNotNull);
          await expectInSafeViewport(find.text('Neue Vorlage'));
          await expectInSafeViewport(save);
          if (scrolled) {
            final add = find.widgetWithText(OBAction, 'Übung hinzufügen');
            await ensureFullyInSafeViewport(editor, add);
            await expectInSafeViewport(save);
            expect(rectInSafeViewport(tester.getRect(save)), isTrue);
            expect(
              rectInSafeViewport(tester.getRect(add), contentOf: editor),
              isTrue,
            );
            await tester.tap(add.hitTestable());
            await pumpSheet();
            expect(find.text('Bibliothek'), findsOneWidget);
            expect(find.text('Eigene Übung'), findsOneWidget);
            expect(find.text('Eigene Zeitübung'), findsOneWidget);
            Navigator.of(tester.element(find.text('Bibliothek'))).pop();
            await pumpSheet();
            expect(find.text('Bibliothek'), findsNothing);
            expect(find.text('Eigene Übung'), findsNothing);
            expect(find.text('Eigene Zeitübung'), findsNothing);
            await ensureFullyInSafeViewport(editor, add);
            await expectInSafeViewport(save);
            expect(rectInSafeViewport(tester.getRect(save)), isTrue);
            expect(
              rectInSafeViewport(tester.getRect(add), contentOf: editor),
              isTrue,
            );
            await capture(name);
            await tester.tap(save.hitTestable());
            await reviewPumpPageTransitions(tester);
            await tester.pump();
            expect(scaled.templateSaves, 1);
            final savedAtScale = (await scaled.readTemplates()).firstWhere(
              (t) => t.name == 'Kurztraining',
            );
            expect(savedAtScale.exercises, hasLength(2));
            expect(
              savedAtScale.exercises
                  .firstWhere((e) => e.exerciseKey == plank.id)
                  .sets
                  .single
                  .mode,
              PlannedSetMode.time,
            );
          } else {
            await capture(name);
          }
        }

        final draftDark = await loadRepo();
        await addBenchAndPlankToDraft(
          repository: draftDark,
          brightness: Brightness.dark,
          name: 'Kurztraining',
        );
        expect(find.text('Neue Vorlage'), findsOneWidget);
        expect(tester.widget<OBAction>(saveAction()).onPressed, isNotNull);
        await capture('exercise-picker-draft-dark');

        await captureParentScaled(
          name: 'exercise-picker-draft-2x',
          brightness: Brightness.light,
          scrolled: false,
        );
        await captureParentScaled(
          name: 'exercise-picker-draft-2x-scrolled',
          brightness: Brightness.light,
          scrolled: true,
        );

        Finder hintedField(String hint) => find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.hintText == hint,
        );

        WorkoutTemplate legacyHoldTemplate() => WorkoutTemplate(
          id: 'legacy-hold',
          name: 'Altbestand',
          version: 1,
          exercises: [
            PlannedExercise(
              id: 'ex-legacy-hold',
              exerciseKey: 'legacy-hold',
              name: 'Halten',
              sets: const [
                PlannedSet(
                  id: 'set-legacy-hold',
                  reps: 8,
                  seconds: 40,
                  loadKg: 62.55,
                ),
              ],
            ),
          ],
          updatedAt: DateTime(2026, 9, 1),
        );

        void expectLegacyHoldUnchanged(WorkoutTemplate template) {
          expect(template.id, 'legacy-hold');
          expect(template.name, 'Altbestand');
          expect(template.exercises, hasLength(1));
          final exercise = template.exercises.single;
          expect(exercise.exerciseKey, 'legacy-hold');
          expect(exercise.name, 'Halten');
          expect(exercise.sets, hasLength(1));
          final set = exercise.sets.single;
          expect(set.reps, 8);
          expect(set.seconds, 40);
          expect(set.loadKg, 62.55);
          expect(set.mode, isNull);
        }

        Future<void> captureLegacyHold({
          required String name,
          required Brightness brightness,
          required bool refillAndSave,
        }) async {
          final repo = await loadRepo();
          final original = await repo.saveTemplate(legacyHoldTemplate());
          expectLegacyHoldUnchanged(original);
          final stamp = jsonEncode(original.toJson());
          final savesAfterSeed = repo.templateSaves;
          await mountEditor(
            repository: repo,
            template: original,
            brightness: brightness,
          );
          expect(find.text('Vorlage bearbeiten'), findsOneWidget);
          expect(find.widgetWithText(TextField, 'Altbestand'), findsOneWidget);
          expect(find.widgetWithText(TextField, 'Halten'), findsOneWidget);
          final sek = hintedField('Sek.');
          expect(sek, findsOneWidget);
          expect(tester.widget<TextField>(sek).controller!.text, '40');
          await enterFocused(sek, '');
          await dismissKeyboard();
          expect(find.text('Dauer fehlt.'), findsOneWidget);
          expect(tester.widget<OBAction>(saveAction()).onPressed, isNull);
          expect(repo.templateSaves, savesAfterSeed);
          final held = (await repo.readTemplates()).firstWhere(
            (t) => t.id == 'legacy-hold',
          );
          expect(jsonEncode(held.toJson()), stamp);
          expectLegacyHoldUnchanged(held);
          await capture(name);
          if (!refillAndSave) return;
          await enterFocused(sek, '40');
          await dismissKeyboard();
          expect(find.text('Dauer fehlt.'), findsNothing);
          expect(tester.widget<OBAction>(saveAction()).onPressed, isNotNull);
          await tester.tap(saveAction().hitTestable());
          await reviewPumpPageTransitions(tester);
          await tester.pump();
          expect(repo.templateSaves, savesAfterSeed + 1);
          final saved = (await repo.readTemplates()).firstWhere(
            (t) => t.id == 'legacy-hold',
          );
          expectLegacyHoldUnchanged(saved);
          await mountEditor(repository: repo, template: saved);
          expect(
            tester.widget<TextField>(hintedField('Sek.')).controller!.text,
            '40',
          );
          expect(hintedField('Wdh.'), findsNothing);
          expectLegacyHoldUnchanged(
            (await repo.readTemplates()).firstWhere(
              (t) => t.id == 'legacy-hold',
            ),
          );
        }

        await captureLegacyHold(
          name: 'exercise-picker-legacy-hold',
          brightness: Brightness.light,
          refillAndSave: true,
        );
        await captureLegacyHold(
          name: 'exercise-picker-legacy-hold-dark',
          brightness: Brightness.dark,
          refillAndSave: false,
        );
      }

      Future<void> reviewCustomExercise() async {
        Future<_CustomExerciseReviewRepo> loadRepo() async {
          Future<Map> load(String name) async =>
              jsonDecode(
                    await rootBundle.loadString(
                      'docs/openband5/assets/fixtures/$name.json',
                    ),
                  )
                  as Map;
          final repo = _CustomExerciseReviewRepo(
            await load('day-summary'),
            await load('sleep-detail'),
            activity: await load('additional-flows'),
            run: await load('run-detail'),
          );
          await repo.seedNutritionGoals();
          return repo;
        }

        Widget reviewHost({
          required Widget home,
          Brightness brightness = Brightness.light,
          double scale = 1,
        }) => MaterialApp(
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
          home: home,
        );

        Finder downScrollable(Finder ancestor) => find.descendant(
          of: ancestor,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        );

        Rect reviewSafeViewport({Finder? contentOf}) {
          final view = tester.view;
          final dpr = view.devicePixelRatio;
          final size = view.physicalSize / dpr;
          final pad = view.viewPadding;
          final screen = Rect.fromLTRB(
            pad.left / dpr,
            pad.top / dpr,
            size.width - pad.right / dpr,
            size.height - pad.bottom / dpr,
          );
          if (contentOf == null) return screen;
          final box = tester.getRect(downScrollable(contentOf).first);
          return Rect.fromLTRB(
            box.left < screen.left ? screen.left : box.left,
            box.top < screen.top ? screen.top : box.top,
            box.right > screen.right ? screen.right : box.right,
            box.bottom > screen.bottom ? screen.bottom : box.bottom,
          );
        }

        bool rectInSafeViewport(
          Rect box, {
          Finder? contentOf,
          double slop = 0.5,
        }) {
          final safe = reviewSafeViewport(contentOf: contentOf);
          return box.top >= safe.top - slop &&
              box.bottom <= safe.bottom + slop &&
              box.left >= safe.left - slop &&
              box.right <= safe.right + slop;
        }

        Future<void> expectInSafeViewport(
          Finder target, {
          Finder? contentOf,
        }) async {
          expect(target, findsWidgets);
          expect(
            rectInSafeViewport(tester.getRect(target), contentOf: contentOf),
            isTrue,
          );
        }

        Future<void> revealIn(Finder ancestor, Finder target) async {
          final scrollable = downScrollable(ancestor).first;
          var scrolls = 0;
          var searchUp = true;
          while (target.evaluate().isEmpty ||
              target.hitTestable().evaluate().isEmpty) {
            if (scrolls >= 32) {
              throw FlutterError(
                'Control is not hit-testable after production scrolling.',
              );
            }
            if (target.evaluate().isEmpty) {
              final position = tester
                  .state<ScrollableState>(scrollable)
                  .position;
              final atMin = position.pixels <= position.minScrollExtent + 0.5;
              final atMax = position.pixels >= position.maxScrollExtent - 0.5;
              if (searchUp && atMin) {
                searchUp = false;
              }
              final dy = searchUp
                  ? (atMin ? 0.0 : 64.0)
                  : (atMax ? 0.0 : -64.0);
              if (dy == 0) {
                throw FlutterError(
                  'Control is not hit-testable after production scrolling.',
                );
              }
              await tester.drag(scrollable, Offset(0, dy));
              await tester.pump();
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
        }

        Future<void> ensureFullyInSafeViewport(
          Finder ancestor,
          Finder target, {
          bool content = true,
        }) async {
          await revealIn(ancestor, target);
          final scrollable = downScrollable(ancestor).first;
          final contentOf = content ? ancestor : null;
          var extra = 0;
          while (!rectInSafeViewport(
            tester.getRect(target),
            contentOf: contentOf,
          )) {
            if (extra >= 32) {
              throw FlutterError(
                'Control is not fully within the safe viewport.',
              );
            }
            final box = tester.getRect(target);
            final safe = reviewSafeViewport(contentOf: contentOf);
            final overflowBottom = box.bottom - safe.bottom;
            final overflowTop = safe.top - box.top;
            if (extra == 0) {
              await Scrollable.ensureVisible(
                tester.element(target),
                alignment: overflowBottom >= overflowTop ? 1.0 : 0.0,
              );
              await tester.pump();
            } else {
              const minGesture = 64.0;
              final needed = overflowBottom > 0
                  ? -(overflowBottom + 8)
                  : overflowTop + 8;
              final dy = needed < 0
                  ? (needed > -minGesture ? -minGesture : needed)
                  : (needed < minGesture ? minGesture : needed);
              await tester.drag(scrollable, Offset(0, dy));
              await tester.pump();
            }
            extra++;
          }
          expect(
            rectInSafeViewport(tester.getRect(target), contentOf: contentOf),
            isTrue,
          );
          expect(target.hitTestable(), findsOneWidget);
        }

        Future<void> pumpUntil(bool Function() ready, String message) async {
          await tester.pump();
          var waited = 0;
          while (!ready()) {
            if (++waited > 80) {
              throw FlutterError(message);
            }
            await tester.pump(const Duration(milliseconds: 16));
          }
          await reviewPumpPageTransitions(tester);
        }

        Future<void> pumpSheet() async {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
        }

        Future<void> pumpInk() async {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        }

        Future<void> mountEditor({
          required _CustomExerciseReviewRepo repository,
          WorkoutTemplate? template,
          Brightness brightness = Brightness.light,
          double scale = 1,
        }) async {
          await tester.pumpWidget(
            reviewHost(
              brightness: brightness,
              scale: scale,
              home: OpenBandTemplateEditor(
                repository: repository,
                template: template,
              ),
            ),
          );
          await pumpUntil(
            () => find.byType(OpenBandTemplateEditor).evaluate().isNotEmpty,
            'Template editor did not finish loading.',
          );
        }

        Map<String, String> templateStamp(List<WorkoutTemplate> templates) => {
          for (final t in templates) t.id: jsonEncode(t.toJson()),
        };

        Finder inPicker(Finder matching) => find.descendant(
          of: find.byType(OpenBandExercisePicker),
          matching: matching,
        );

        Finder definitionEditor() =>
            find.byType(OpenBandExerciseDefinitionEditor);

        Finder saveDefinition() =>
            find.byKey(const ValueKey('custom-exercise-save'));

        Finder plusOf(String id) => find.byKey(ValueKey('exercise-select-$id'));

        bool pickerCatalogueReady() {
          if (find.byType(OpenBandExercisePicker).evaluate().isEmpty) {
            return false;
          }
          if (find.text('Bibliothek nicht geladen').evaluate().isNotEmpty) {
            return true;
          }
          if (find.text('Keine Übungen gefunden').evaluate().isNotEmpty) {
            return true;
          }
          return find.text('5 Übungen').evaluate().isNotEmpty ||
              find.text('6 Übungen').evaluate().isNotEmpty ||
              find.text('1 Übung').evaluate().isNotEmpty ||
              find.text('0 Übungen').evaluate().isNotEmpty;
        }

        Future<void> pumpPickerReady() async {
          await pumpUntil(
            pickerCatalogueReady,
            'Exercise picker did not finish loading.',
          );
        }

        Future<void> openAddSheet() async {
          final editor = find.byType(OpenBandTemplateEditor);
          final add = find.widgetWithText(OBAction, 'Übung hinzufügen');
          await ensureFullyInSafeViewport(editor, add);
          await tester.tap(add.hitTestable());
          await pumpSheet();
          expect(find.text('Bibliothek'), findsOneWidget);
          expect(find.text('Eigene Übung'), findsOneWidget);
          expect(find.text('Eigene Zeitübung'), findsOneWidget);
        }

        Future<void> openPicker() async {
          await openAddSheet();
          await tester.tap(find.text('Bibliothek'));
          await pumpPickerReady();
        }

        Future<void> popRoute() async {
          await tester.tap(find.byTooltip('Zurück'));
          await reviewPumpPageTransitions(tester);
          await tester.pump();
        }

        double keyboardInset() =>
            tester.view.viewInsets.bottom / tester.view.devicePixelRatio;

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
          expect(keyboardInset(), 0);
        }

        Future<void> enterFocused(Finder field, String text) async {
          await settleKeyboard(field);
          await tester.enterText(field, text);
          await tester.pump();
          expect(tester.widget<TextField>(field).controller!.text, text);
        }

        Future<void> openCreateFromPlus() async {
          final plus = find.byTooltip('Eigene Übung');
          await expectInSafeViewport(plus);
          await tester.tap(plus.hitTestable());
          await reviewPumpPageTransitions(tester);
          await tester.pump();
          expect(definitionEditor(), findsOneWidget);
        }

        Future<void> openCreateFromSearch() async {
          final create = find.byKey(const ValueKey('exercise-create-search'));
          await expectInSafeViewport(create);
          await tester.tap(create.hitTestable());
          await reviewPumpPageTransitions(tester);
          await tester.pump();
          expect(definitionEditor(), findsOneWidget);
        }

        Future<void> searchPicker(String query) async {
          final field = find.byKey(const ValueKey('exercise-search'));
          final picker = find.byType(OpenBandExercisePicker);
          await ensureFullyInSafeViewport(picker, field);
          await enterFocused(field, query);
          await dismissKeyboard();
        }

        Future<void> openDefinitionRow(Key key, {bool sheet = true}) async {
          final editor = definitionEditor();
          final row = find.byKey(key);
          await ensureFullyInSafeViewport(editor, row);
          await tester.tap(row.hitTestable());
          if (sheet) {
            await pumpSheet();
          } else {
            await reviewPumpPageTransitions(tester);
            await tester.pump();
          }
        }

        Future<void> pickSheetChoice(Key sheetKey, Key choiceKey) async {
          final sheet = find.byKey(sheetKey);
          expect(sheet, findsOneWidget);
          final choice = find.byKey(choiceKey);
          expect(choice, findsOneWidget);
          if (choice.hitTestable().evaluate().isEmpty ||
              !rectInSafeViewport(tester.getRect(choice))) {
            await ensureFullyInSafeViewport(sheet, choice);
          }
          await tester.tap(choice.hitTestable());
          await pumpSheet();
        }

        Future<void> enterCount(String value, {String? frame}) async {
          final field = find.byKey(const ValueKey('settings-count-field'));
          expect(field, findsOneWidget);
          await settleKeyboard(field);
          await tester.enterText(field, value);
          await tester.pump();
          expect(tester.widget<TextField>(field).controller!.text, value);
          if (frame != null) {
            await capture(frame);
          }
          await dismissKeyboard();
          final apply = find.descendant(
            of: find.byKey(const ValueKey('custom-exercise-count-sheet')),
            matching: find.widgetWithText(OBAction, 'Übernehmen'),
          );
          expect(tester.widget<OBAction>(apply).onPressed, isNotNull);
          await expectInSafeViewport(apply);
          await tester.tap(apply.hitTestable());
          await pumpSheet();
        }

        Future<void> tapMuscle(String id) async {
          final chip = find.byKey(ValueKey('custom-muscle-$id'));
          expect(chip, findsOneWidget);
          if (chip.hitTestable().evaluate().isEmpty) {
            final page = find.ancestor(
              of: chip,
              matching: find.byType(Scaffold),
            );
            await ensureFullyInSafeViewport(page, chip);
          } else if (!rectInSafeViewport(tester.getRect(chip))) {
            final page = find.ancestor(
              of: chip,
              matching: find.byType(Scaffold),
            );
            await ensureFullyInSafeViewport(page, chip);
          }
          await tester.tap(chip.hitTestable());
          await pumpInk();
        }

        Future<void> confirmMusclePage() async {
          final apply = find.widgetWithText(OBAction, 'Übernehmen');
          await expectInSafeViewport(apply);
          await tester.tap(apply.hitTestable());
          await reviewPumpPageTransitions(tester);
          await tester.pump();
        }

        Future<void> selectMuscles({
          required String primary,
          String? secondary,
          String? frame,
        }) async {
          await openDefinitionRow(
            const ValueKey('custom-exercise-primary'),
            sheet: false,
          );
          await tapMuscle(primary);
          if (frame != null) {
            await capture(frame);
          }
          await confirmMusclePage();
          if (secondary == null) return;
          await openDefinitionRow(
            const ValueKey('custom-exercise-secondary'),
            sheet: false,
          );
          await tapMuscle(secondary);
          await confirmMusclePage();
        }

        Future<void> expectEnteredName(String text) async {
          final editor = definitionEditor();
          final name = find.byKey(const ValueKey('custom-exercise-name'));
          await ensureFullyInSafeViewport(editor, name);
          expect(tester.widget<TextField>(name).controller!.text, text);
        }

        Future<void> expectRowValue(Key key, String value) async {
          final editor = definitionEditor();
          final row = find.byKey(key);
          await ensureFullyInSafeViewport(editor, row);
          expect(
            find.descendant(of: row, matching: find.text(value)),
            findsWidgets,
          );
        }

        Future<void> fillKurzhantelCurl({
          String? equipmentFrame,
          String? modeFrame,
          String? loadFrame,
          String? countFrame,
          String? repsFrame,
          String? musclesFrame,
        }) async {
          final editor = definitionEditor();
          final name = find.byKey(const ValueKey('custom-exercise-name'));
          await ensureFullyInSafeViewport(editor, name);
          await enterFocused(name, 'Kurzhantel-Curl');
          await dismissKeyboard();
          expect(tester.widget<OBAction>(saveDefinition()).onPressed, isNull);

          await openDefinitionRow(const ValueKey('custom-exercise-equipment'));
          if (equipmentFrame != null) {
            await capture(equipmentFrame);
          }
          await pickSheetChoice(
            const ValueKey('custom-exercise-equipment-sheet'),
            const ValueKey('custom-exercise-equipment-dumbbell'),
          );

          await openDefinitionRow(const ValueKey('custom-exercise-mode'));
          if (modeFrame != null) {
            await capture(modeFrame);
          }
          await pickSheetChoice(
            const ValueKey('custom-exercise-mode-sheet'),
            const ValueKey('custom-exercise-mode-repetitions'),
          );

          await openDefinitionRow(const ValueKey('custom-exercise-load'));
          if (loadFrame != null) {
            await capture(loadFrame);
          }
          await pickSheetChoice(
            const ValueKey('custom-exercise-load-sheet'),
            const ValueKey('custom-exercise-load-perDevice'),
          );

          await openDefinitionRow(const ValueKey('custom-exercise-count'));
          await enterCount('2', frame: countFrame);

          await openDefinitionRow(const ValueKey('custom-exercise-reps'));
          if (repsFrame != null) {
            await capture(repsFrame);
          }
          await pickSheetChoice(
            const ValueKey('custom-exercise-reps-sheet'),
            const ValueKey('custom-exercise-reps-perSide'),
          );

          await selectMuscles(
            primary: 'biceps',
            secondary: 'forearms',
            frame: musclesFrame,
          );
          await expectEnteredName('Kurzhantel-Curl');
          await expectRowValue(
            const ValueKey('custom-exercise-equipment'),
            'Kurzhantel',
          );
          await expectRowValue(
            const ValueKey('custom-exercise-mode'),
            'Wiederholungen',
          );
          await expectRowValue(
            const ValueKey('custom-exercise-load'),
            'Je Hantel',
          );
          await expectRowValue(const ValueKey('custom-exercise-count'), '2');
          await expectRowValue(
            const ValueKey('custom-exercise-reps'),
            'Je Seite',
          );
          await expectRowValue(
            const ValueKey('custom-exercise-primary'),
            'Bizeps',
          );
          expect(
            tester.widget<OBAction>(saveDefinition()).onPressed,
            isNotNull,
          );
        }

        Future<void> fillWandsitz() async {
          final editor = definitionEditor();
          final name = find.byKey(const ValueKey('custom-exercise-name'));
          await ensureFullyInSafeViewport(editor, name);
          await enterFocused(name, 'Wandsitz');
          await dismissKeyboard();
          await openDefinitionRow(const ValueKey('custom-exercise-equipment'));
          await pickSheetChoice(
            const ValueKey('custom-exercise-equipment-sheet'),
            const ValueKey('custom-exercise-equipment-bodyweight'),
          );
          await openDefinitionRow(const ValueKey('custom-exercise-mode'));
          await pickSheetChoice(
            const ValueKey('custom-exercise-mode-sheet'),
            const ValueKey('custom-exercise-mode-time'),
          );
          expect(
            find.byKey(const ValueKey('custom-exercise-count')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('custom-exercise-reps')),
            findsNothing,
          );
          await openDefinitionRow(const ValueKey('custom-exercise-load'));
          await pickSheetChoice(
            const ValueKey('custom-exercise-load-sheet'),
            const ValueKey('custom-exercise-load-bodyweight'),
          );
          expect(
            find.byKey(const ValueKey('custom-exercise-count')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('custom-exercise-reps')),
            findsNothing,
          );
          await selectMuscles(primary: 'legs');
          await expectEnteredName('Wandsitz');
          await expectRowValue(
            const ValueKey('custom-exercise-equipment'),
            'Eigengewicht',
          );
          await expectRowValue(
            const ValueKey('custom-exercise-mode'),
            'Haltezeit',
          );
          await expectRowValue(
            const ValueKey('custom-exercise-load'),
            'Eigengewicht',
          );
          await expectRowValue(
            const ValueKey('custom-exercise-primary'),
            'Beine',
          );
          expect(
            tester.widget<OBAction>(saveDefinition()).onPressed,
            isNotNull,
          );
        }

        Future<void> expectEmptyDefinition() async {
          expect(definitionEditor(), findsOneWidget);
          expect(find.text('Eigene Übung'), findsWidgets);
          final nameField = tester.widget<TextField>(
            find.byKey(const ValueKey('custom-exercise-name')),
          );
          expect(nameField.controller!.text, isEmpty);
          expect(nameField.decoration?.hintText, 'Name der Übung');
          expect(
            find.byKey(const ValueKey('custom-exercise-load')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('custom-exercise-count')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('custom-exercise-reps')),
            findsNothing,
          );
          expect(find.text('Auswählen'), findsWidgets);
          expect(find.text('—'), findsWidgets);
          expect(tester.widget<OBAction>(saveDefinition()).onPressed, isNull);
        }

        void expectSavedCurl(ExerciseCatalogueEntry entry) {
          expect(entry.label, 'Kurzhantel-Curl');
          expect(entry.equipment, ExerciseEquipmentCategory.dumbbell);
          expect(entry.mode, ExerciseCaptureMode.repetitions);
          expect(entry.loadBasis, ExerciseLoadBasis.perDevice);
          expect(entry.deviceCount, 2);
          expect(entry.repetitionBasis, ExerciseRepetitionBasis.perSide);
          expect(entry.primaryMuscles, contains('biceps'));
          expect(entry.secondaryMuscles, contains('forearms'));
          expect(entry.source, ExerciseDefinitionSource.stored);
        }

        Future<ExerciseCatalogueEntry> expectPersisted(
          _CustomExerciseReviewRepo repository,
          String id,
        ) async {
          final catalogue = await repository.readExerciseCatalogue();
          final entry = catalogue.byId(id);
          expect(entry, isNotNull);
          return entry!;
        }

        Future<void> expectUnselectedLibrary({
          required String id,
          required String label,
        }) async {
          expect(find.byType(OpenBandExercisePicker), findsOneWidget);
          expect(definitionEditor(), findsNothing);
          expect(inPicker(find.text(label)), findsOneWidget);
          expect(plusOf(id), findsOneWidget);
          expect(
            find.widgetWithText(OBAction, '1 Übung hinzufügen'),
            findsNothing,
          );
          expect(
            tester
                .widget<OBAction>(
                  find.widgetWithText(OBAction, '0 Übungen hinzufügen'),
                )
                .onPressed,
            isNull,
          );
        }

        Future<void> saveDefinitionAndWait({
          required _CustomExerciseReviewRepo repository,
        }) async {
          final save = saveDefinition();
          await expectInSafeViewport(save);
          expect(tester.widget<OBAction>(save).onPressed, isNotNull);
          await tester.tap(save.hitTestable());
          await reviewPumpPageTransitions(tester);
          await tester.pump();
          await pumpUntil(
            () =>
                definitionEditor().evaluate().isEmpty && pickerCatalogueReady(),
            'Definition editor did not return to the picker after save.',
          );
          expect(repository.lastCreate, isNotNull);
          expect(repository.lastCreate!.saved, isTrue);
          expect(repository.lastCreate!.current, isNotNull);
        }

        // Empty definition via picker header plus.
        var repository = await loadRepo();
        await mountEditor(repository: repository);
        await openPicker();
        await openCreateFromPlus();
        await expectEmptyDefinition();
        await capture('custom-exercise-empty');
        await popRoute();
        expect(find.byType(OpenBandExercisePicker), findsOneWidget);

        repository = await loadRepo();
        await mountEditor(repository: repository, brightness: Brightness.dark);
        await openPicker();
        await openCreateFromPlus();
        await expectEmptyDefinition();
        await capture('custom-exercise-empty-dark');
        await popRoute();

        // Create-empty-search route, filled curl, genuine fail-once, retry.
        repository = await loadRepo();
        final originalTemplates = templateStamp(
          await repository.readTemplates(),
        );
        await mountEditor(repository: repository);
        await openPicker();
        await searchPicker('Curl');
        expect(find.text('Keine Übungen gefunden'), findsOneWidget);
        expect(find.text('0 Übungen'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('exercise-create-search')),
          findsOneWidget,
        );
        await capture('custom-exercise-create-search');
        await openCreateFromSearch();
        await expectEmptyDefinition();
        await fillKurzhantelCurl(
          equipmentFrame: 'custom-exercise-equipment',
          modeFrame: 'custom-exercise-mode',
          loadFrame: 'custom-exercise-load',
          countFrame: 'custom-exercise-count',
          repsFrame: 'custom-exercise-reps',
          musclesFrame: 'custom-exercise-muscles',
        );
        await expectInSafeViewport(saveDefinition());
        await capture('custom-exercise-filled');
        expect(repository.createCalls, 0);
        expect(repository.lastCreate, isNull);

        repository.failNextCreate = true;
        await tester.tap(saveDefinition().hitTestable());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(repository.createCalls, 1);
        expect(repository.failNextCreate, isFalse);
        expect(repository.lastCreate, isNull);
        expect(
          (await repository.readExerciseCatalogue()).entries.where(
            (entry) => entry.source == ExerciseDefinitionSource.stored,
          ),
          isEmpty,
        );
        expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
        expect(find.text('Erneut speichern'), findsOneWidget);
        await expectEnteredName('Kurzhantel-Curl');
        await expectRowValue(
          const ValueKey('custom-exercise-equipment'),
          'Kurzhantel',
        );
        await expectRowValue(
          const ValueKey('custom-exercise-reps'),
          'Je Seite',
        );
        await expectRowValue(
          const ValueKey('custom-exercise-primary'),
          'Bizeps',
        );
        await capture('custom-exercise-save-failure');

        await saveDefinitionAndWait(repository: repository);
        expect(repository.createCalls, 2);
        expect(repository.draftIds, hasLength(2));
        expect(repository.draftIds[0], repository.draftIds[1]);
        final curlId = repository.lastCreate!.current!.id;
        expect(repository.draftIds[0], curlId);
        expect(curlId, isNotEmpty);
        var savedCurl = await expectPersisted(repository, curlId);
        expectSavedCurl(savedCurl);
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('exercise-search')))
              .controller!
              .text,
          'Curl',
        );
        expect(inPicker(find.text('1 Übung')), findsOneWidget);
        expect(inPicker(find.textContaining('2 Hanteln')), findsOneWidget);
        expect(inPicker(find.textContaining('Wdh. je Seite')), findsOneWidget);
        await expectUnselectedLibrary(id: curlId, label: 'Kurzhantel-Curl');
        await capture('custom-exercise-library');

        await ensureFullyInSafeViewport(
          find.byType(OpenBandExercisePicker),
          plusOf(curlId),
        );
        await tester.tap(plusOf(curlId).hitTestable());
        await pumpInk();
        final addSelected = find.widgetWithText(OBAction, '1 Übung hinzufügen');
        expect(addSelected, findsOneWidget);
        await expectInSafeViewport(addSelected);
        await tester.tap(addSelected.hitTestable());
        await reviewPumpPageTransitions(tester);
        await tester.pump();
        expect(find.byType(OpenBandExercisePicker), findsNothing);
        expect(find.byType(OpenBandTemplateEditor), findsOneWidget);
        expect(find.text('Kurzhantel-Curl'), findsWidgets);
        final templateName = find.byType(TextField).first;
        await enterFocused(templateName, 'Kurztraining');
        await dismissKeyboard();
        expect(repository.templateSaves, 0);
        expect(
          templateStamp(await repository.readTemplates()),
          originalTemplates,
        );
        savedCurl = await expectPersisted(repository, curlId);
        expectSavedCurl(savedCurl);
        await capture('custom-exercise-template');

        // Dark filled / count / failure / library on a separate write.
        final darkRepo = await loadRepo();
        await mountEditor(repository: darkRepo, brightness: Brightness.dark);
        await openPicker();
        await searchPicker('Curl');
        await openCreateFromSearch();
        await fillKurzhantelCurl(
          countFrame: 'custom-exercise-count-dark',
          musclesFrame: 'custom-exercise-muscles-dark',
        );
        await capture('custom-exercise-filled-dark');
        darkRepo.failNextCreate = true;
        await tester.tap(saveDefinition().hitTestable());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
        expect(find.text('Erneut speichern'), findsOneWidget);
        await expectEnteredName('Kurzhantel-Curl');
        await capture('custom-exercise-save-failure-dark');
        await saveDefinitionAndWait(repository: darkRepo);
        final darkId = darkRepo.lastCreate!.current!.id;
        expectSavedCurl(await expectPersisted(darkRepo, darkId));
        await expectUnselectedLibrary(id: darkId, label: 'Kurzhantel-Curl');
        await capture('custom-exercise-library-dark');

        // Timed bodyweight variant: count/reps not required, mode time.
        final timeRepo = await loadRepo();
        await mountEditor(repository: timeRepo);
        await openPicker();
        await openCreateFromPlus();
        await fillWandsitz();
        await capture('custom-exercise-time');
        await saveDefinitionAndWait(repository: timeRepo);
        final timeId = timeRepo.lastCreate!.current!.id;
        final timeEntry = await expectPersisted(timeRepo, timeId);
        expect(timeEntry.label, 'Wandsitz');
        expect(timeEntry.equipment, ExerciseEquipmentCategory.bodyweight);
        expect(timeEntry.mode, ExerciseCaptureMode.time);
        expect(timeEntry.loadBasis, ExerciseLoadBasis.bodyweight);
        expect(timeEntry.deviceCount, isNull);
        expect(timeEntry.repetitionBasis, isNull);
        expect(timeEntry.primaryMuscles, contains('legs'));
        await expectUnselectedLibrary(id: timeId, label: 'Wandsitz');

        final timeDark = await loadRepo();
        await mountEditor(repository: timeDark, brightness: Brightness.dark);
        await openPicker();
        await openCreateFromPlus();
        await fillWandsitz();
        await capture('custom-exercise-time-dark');
        await popRoute();

        Future<void> scrollListToMin(Finder ancestor) async {
          final scrollable = downScrollable(ancestor).first;
          var scrolls = 0;
          var pumps = 0;
          while (true) {
            final position = tester.state<ScrollableState>(scrollable).position;
            final min = position.minScrollExtent;
            final offset = position.pixels - min;
            final idle = !position.isScrollingNotifier.value;
            if (idle && offset.abs() <= 0.5) {
              expect(offset.abs(), lessThanOrEqualTo(0.5));
              expect(position.isScrollingNotifier.value, isFalse);
              return;
            }
            if (offset > 0.5) {
              if (++scrolls > 32) {
                throw FlutterError('ListView did not reach min scroll extent.');
              }
              await tester.drag(scrollable, const Offset(0, 64));
              await tester.pump();
              continue;
            }
            if (++pumps > 40) {
              throw FlutterError('ListView overscroll did not settle at min.');
            }
            await tester.pump(const Duration(milliseconds: 16));
          }
        }

        Future<void> captureScaled({
          required String name,
          required Brightness brightness,
          required bool scrolled,
        }) async {
          final scaled = await loadRepo();
          await mountEditor(
            repository: scaled,
            brightness: brightness,
            scale: 2,
          );
          await openPicker();
          await openCreateFromPlus();
          await fillKurzhantelCurl();
          final editor = definitionEditor();
          final save = saveDefinition();
          await expectInSafeViewport(find.text('Eigene Übung'));
          await expectInSafeViewport(save);
          expect(tester.widget<OBAction>(save).onPressed, isNotNull);
          if (scrolled) {
            final secondary = find.byKey(
              const ValueKey('custom-exercise-secondary'),
            );
            await ensureFullyInSafeViewport(editor, secondary);
            await expectInSafeViewport(save);
            expect(rectInSafeViewport(tester.getRect(save)), isTrue);
            expect(
              rectInSafeViewport(tester.getRect(secondary), contentOf: editor),
              isTrue,
            );
            await capture(name);
            await tester.tap(save.hitTestable());
            await reviewPumpPageTransitions(tester);
            await tester.pump();
            await pumpUntil(
              () =>
                  definitionEditor().evaluate().isEmpty &&
                  pickerCatalogueReady(),
              'Scaled save did not return to the picker.',
            );
            expect(scaled.lastCreate, isNotNull);
            expect(scaled.lastCreate!.saved, isTrue);
            final scaledId = scaled.lastCreate!.current!.id;
            expectSavedCurl(await expectPersisted(scaled, scaledId));
            await expectUnselectedLibrary(
              id: scaledId,
              label: 'Kurzhantel-Curl',
            );
            expect(scaled.templateSaves, 0);
          } else {
            await scrollListToMin(editor);
            await expectEnteredName('Kurzhantel-Curl');
            await expectInSafeViewport(
              find.byKey(const ValueKey('custom-exercise-name')),
              contentOf: editor,
            );
            await capture(name);
          }
        }

        await captureScaled(
          name: 'custom-exercise-2x',
          brightness: Brightness.light,
          scrolled: false,
        );
        await captureScaled(
          name: 'custom-exercise-2x-scrolled',
          brightness: Brightness.light,
          scrolled: true,
        );
        await captureScaled(
          name: 'custom-exercise-2x-dark',
          brightness: Brightness.dark,
          scrolled: false,
        );
      }

      Future<void> reviewExerciseCopy() async {
        const curlId = 'custom-curl';
        const shortCurlId = 'custom-curl-short';

        Future<_CustomExerciseReviewRepo> loadRepo() async {
          Future<Map> load(String name) async =>
              jsonDecode(
                    await rootBundle.loadString(
                      'docs/openband5/assets/fixtures/$name.json',
                    ),
                  )
                  as Map;
          final repo = _CustomExerciseReviewRepo(
            await load('day-summary'),
            await load('sleep-detail'),
            activity: await load('additional-flows'),
            run: await load('run-detail'),
          );
          await repo.seedNutritionGoals();
          return repo;
        }

        Widget reviewHost({
          required Widget home,
          Brightness brightness = Brightness.light,
          double scale = 1,
        }) => MaterialApp(
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
          home: home,
        );

        Finder downScrollable(Finder ancestor) => find.descendant(
          of: ancestor,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        );

        Rect reviewSafeViewport({Finder? contentOf}) {
          final view = tester.view;
          final dpr = view.devicePixelRatio;
          final size = view.physicalSize / dpr;
          final pad = view.viewPadding;
          final screen = Rect.fromLTRB(
            pad.left / dpr,
            pad.top / dpr,
            size.width - pad.right / dpr,
            size.height - pad.bottom / dpr,
          );
          if (contentOf == null) return screen;
          final box = tester.getRect(downScrollable(contentOf).first);
          return Rect.fromLTRB(
            box.left < screen.left ? screen.left : box.left,
            box.top < screen.top ? screen.top : box.top,
            box.right > screen.right ? screen.right : box.right,
            box.bottom > screen.bottom ? screen.bottom : box.bottom,
          );
        }

        bool rectInSafeViewport(
          Rect box, {
          Finder? contentOf,
          double slop = 0.5,
        }) {
          final safe = reviewSafeViewport(contentOf: contentOf);
          return box.top >= safe.top - slop &&
              box.bottom <= safe.bottom + slop &&
              box.left >= safe.left - slop &&
              box.right <= safe.right + slop;
        }

        Future<void> expectInSafeViewport(
          Finder target, {
          Finder? contentOf,
        }) async {
          expect(target, findsWidgets);
          expect(
            rectInSafeViewport(tester.getRect(target), contentOf: contentOf),
            isTrue,
          );
        }

        Future<void> revealIn(Finder ancestor, Finder target) async {
          final scrollable = downScrollable(ancestor).first;
          var scrolls = 0;
          var searchUp = true;
          while (target.evaluate().isEmpty ||
              target.hitTestable().evaluate().isEmpty) {
            if (scrolls >= 32) {
              throw FlutterError(
                'Control is not hit-testable after production scrolling.',
              );
            }
            if (target.evaluate().isEmpty) {
              final position = tester
                  .state<ScrollableState>(scrollable)
                  .position;
              final atMin = position.pixels <= position.minScrollExtent + 0.5;
              final atMax = position.pixels >= position.maxScrollExtent - 0.5;
              if (searchUp && atMin) {
                searchUp = false;
              }
              final dy = searchUp
                  ? (atMin ? 0.0 : 64.0)
                  : (atMax ? 0.0 : -64.0);
              if (dy == 0) {
                throw FlutterError(
                  'Control is not hit-testable after production scrolling.',
                );
              }
              await tester.drag(scrollable, Offset(0, dy));
              await tester.pump();
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
        }

        Future<void> ensureFullyInSafeViewport(
          Finder ancestor,
          Finder target, {
          bool content = true,
        }) async {
          await revealIn(ancestor, target);
          final scrollable = downScrollable(ancestor).first;
          final contentOf = content ? ancestor : null;
          var extra = 0;
          while (!rectInSafeViewport(
            tester.getRect(target),
            contentOf: contentOf,
          )) {
            if (extra >= 32) {
              throw FlutterError(
                'Control is not fully within the safe viewport.',
              );
            }
            final box = tester.getRect(target);
            final safe = reviewSafeViewport(contentOf: contentOf);
            final overflowBottom = box.bottom - safe.bottom;
            final overflowTop = safe.top - box.top;
            if (extra == 0) {
              await Scrollable.ensureVisible(
                tester.element(target),
                alignment: overflowBottom >= overflowTop ? 1.0 : 0.0,
              );
              await tester.pump();
            } else {
              const minGesture = 64.0;
              final needed = overflowBottom > 0
                  ? -(overflowBottom + 8)
                  : overflowTop + 8;
              final dy = needed < 0
                  ? (needed > -minGesture ? -minGesture : needed)
                  : (needed < minGesture ? minGesture : needed);
              await tester.drag(scrollable, Offset(0, dy));
              await tester.pump();
            }
            extra++;
          }
          expect(
            rectInSafeViewport(tester.getRect(target), contentOf: contentOf),
            isTrue,
          );
          expect(target.hitTestable(), findsOneWidget);
        }

        Future<void> pumpUntil(bool Function() ready, String message) async {
          await tester.pump();
          var waited = 0;
          while (!ready()) {
            if (++waited > 80) {
              throw FlutterError(message);
            }
            await tester.pump(const Duration(milliseconds: 16));
          }
          await reviewPumpPageTransitions(tester);
        }

        Future<void> pumpSheet() async {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
        }

        Future<void> pumpInk() async {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        }

        Future<void> mountEditor({
          required _CustomExerciseReviewRepo repository,
          WorkoutTemplate? template,
          Brightness brightness = Brightness.light,
          double scale = 1,
        }) async {
          await tester.pumpWidget(
            reviewHost(
              brightness: brightness,
              scale: scale,
              home: OpenBandTemplateEditor(
                repository: repository,
                template: template,
              ),
            ),
          );
          await pumpUntil(
            () => find.byType(OpenBandTemplateEditor).evaluate().isNotEmpty,
            'Template editor did not finish loading.',
          );
        }

        Map<String, String> templateStamp(List<WorkoutTemplate> templates) => {
          for (final t in templates) t.id: jsonEncode(t.toJson()),
        };

        Finder inPicker(Finder matching) => find.descendant(
          of: find.byType(OpenBandExercisePicker),
          matching: matching,
        );

        Finder definitionEditor() =>
            find.byType(OpenBandExerciseDefinitionEditor);

        Finder saveDefinition() =>
            find.byKey(const ValueKey('custom-exercise-save'));

        Finder plusOf(String id) => find.byKey(ValueKey('exercise-select-$id'));

        Finder openOf(String id) => find.byKey(ValueKey('exercise-open-$id'));

        Finder copyAction() => find.byTooltip('Kopieren');

        bool pickerCatalogueReady() {
          if (find.byType(OpenBandExercisePicker).evaluate().isEmpty) {
            return false;
          }
          if (find.text('Bibliothek nicht geladen').evaluate().isNotEmpty) {
            return true;
          }
          final search = find.byKey(const ValueKey('exercise-search'));
          if (search.evaluate().isEmpty) return false;
          return tester.widget<TextField>(search).enabled == true;
        }

        Future<void> pumpPickerReady() async {
          await pumpUntil(
            pickerCatalogueReady,
            'Exercise picker did not finish loading.',
          );
        }

        Future<void> openPicker() async {
          final editor = find.byType(OpenBandTemplateEditor);
          final add = find.widgetWithText(OBAction, 'Übung hinzufügen');
          await ensureFullyInSafeViewport(editor, add);
          await tester.tap(add.hitTestable());
          await pumpSheet();
          expect(find.text('Bibliothek'), findsOneWidget);
          await tester.tap(find.text('Bibliothek'));
          await pumpPickerReady();
        }

        Future<void> popRoute() async {
          await tester.tap(find.byTooltip('Zurück'));
          await reviewPumpPageTransitions(tester);
          await tester.pump();
        }

        double keyboardInset() =>
            tester.view.viewInsets.bottom / tester.view.devicePixelRatio;

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
          expect(keyboardInset(), 0);
        }

        Future<void> enterFocused(Finder field, String text) async {
          await settleKeyboard(field);
          await tester.enterText(field, text);
          await tester.pump();
          expect(tester.widget<TextField>(field).controller!.text, text);
        }

        Future<void> searchPicker(String query) async {
          final field = find.byKey(const ValueKey('exercise-search'));
          final picker = find.byType(OpenBandExercisePicker);
          await ensureFullyInSafeViewport(picker, field);
          await enterFocused(field, query);
          await dismissKeyboard();
        }

        Future<void> openDefinitionRow(Key key, {bool sheet = true}) async {
          final editor = definitionEditor();
          final row = find.byKey(key);
          await ensureFullyInSafeViewport(editor, row);
          await tester.tap(row.hitTestable());
          if (sheet) {
            await pumpSheet();
          } else {
            await reviewPumpPageTransitions(tester);
            await tester.pump();
          }
        }

        Future<void> pickSheetChoice(Key sheetKey, Key choiceKey) async {
          final sheet = find.byKey(sheetKey);
          expect(sheet, findsOneWidget);
          final choice = find.byKey(choiceKey);
          expect(choice, findsOneWidget);
          if (choice.hitTestable().evaluate().isEmpty ||
              !rectInSafeViewport(tester.getRect(choice))) {
            await ensureFullyInSafeViewport(sheet, choice);
          }
          await tester.tap(choice.hitTestable());
          await pumpSheet();
        }

        Future<void> expectRowValue(Key key, String value) async {
          expect(
            tester.widget<OBSettingsValueRow>(find.byKey(key)).value,
            value,
          );
        }

        CustomExerciseDraft curlDraft({
          required String id,
          String label = 'Kurzhantel-Curl',
        }) => CustomExerciseDraft(
          id: id,
          label: label,
          mode: ExerciseCaptureMode.repetitions,
          equipment: ExerciseEquipmentCategory.dumbbell,
          loadBasis: ExerciseLoadBasis.perDevice,
          deviceCount: 2,
          repetitionBasis: ExerciseRepetitionBasis.perSide,
          primaryMuscles: const ['biceps'],
          secondaryMuscles: const ['forearms'],
        );

        Future<void> seedCurl(
          _CustomExerciseReviewRepo repository, {
          String id = curlId,
          String label = 'Kurzhantel-Curl',
        }) async {
          final result = await repository.createCustomExercise(
            curlDraft(id: id, label: label),
          );
          expect(result.saved, isTrue);
        }

        Future<void> openSource(String id) async {
          final picker = find.byType(OpenBandExercisePicker);
          final open = openOf(id);
          await ensureFullyInSafeViewport(picker, open);
          await tester.tap(open.hitTestable());
          await reviewPumpPageTransitions(tester);
          await tester.pump();
          expect(copyAction(), findsOneWidget);
        }

        Future<void> openCopy() async {
          await expectInSafeViewport(copyAction());
          await tester.tap(copyAction().hitTestable());
          await reviewPumpPageTransitions(tester);
          await tester.pump();
          expect(definitionEditor(), findsOneWidget);
          expect(find.text('Eigene Übung'), findsWidgets);
        }

        Future<void> fillPresetRemainder() async {
          await openDefinitionRow(const ValueKey('custom-exercise-load'));
          await pickSheetChoice(
            const ValueKey('custom-exercise-load-sheet'),
            const ValueKey('custom-exercise-load-total'),
          );
          await openDefinitionRow(const ValueKey('custom-exercise-reps'));
          await pickSheetChoice(
            const ValueKey('custom-exercise-reps-sheet'),
            const ValueKey('custom-exercise-reps-total'),
          );
        }

        Future<void> expectUnselectedAdd() async {
          expect(
            tester
                .widget<OBAction>(
                  find.widgetWithText(OBAction, '0 Übungen hinzufügen'),
                )
                .onPressed,
            isNull,
          );
        }

        Future<void> scrollListToMin(Finder ancestor) async {
          final scrollable = downScrollable(ancestor).first;
          var scrolls = 0;
          var pumps = 0;
          while (true) {
            final position = tester.state<ScrollableState>(scrollable).position;
            final min = position.minScrollExtent;
            final offset = position.pixels - min;
            final idle = !position.isScrollingNotifier.value;
            if (idle && offset.abs() <= 0.5) {
              expect(offset.abs(), lessThanOrEqualTo(0.5));
              expect(position.isScrollingNotifier.value, isFalse);
              return;
            }
            if (offset > 0.5) {
              if (++scrolls > 32) {
                throw FlutterError('ListView did not reach min scroll extent.');
              }
              await tester.drag(scrollable, const Offset(0, 64));
              await tester.pump();
              continue;
            }
            if (++pumps > 40) {
              throw FlutterError('ListView overscroll did not settle at min.');
            }
            await tester.pump(const Duration(milliseconds: 16));
          }
        }

        Future<void> saveAndReturn(_CustomExerciseReviewRepo repository) async {
          final save = saveDefinition();
          await expectInSafeViewport(save);
          expect(tester.widget<OBAction>(save).onPressed, isNotNull);
          await tester.tap(save.hitTestable());
          await reviewPumpPageTransitions(tester);
          await tester.pump();
          await pumpUntil(
            () =>
                definitionEditor().evaluate().isEmpty &&
                find.byType(OpenBandExercisePicker).evaluate().isNotEmpty &&
                pickerCatalogueReady(),
            'Copy did not unwind editor and detail to the picker.',
          );
          expect(repository.lastCreate, isNotNull);
          expect(repository.lastCreate!.saved, isTrue);
        }

        final bench = _pickerPreset('bench_press');

        var repository = await loadRepo();
        await seedCurl(repository);
        final originalTemplates = templateStamp(
          await repository.readTemplates(),
        );
        await mountEditor(repository: repository);
        await openPicker();
        await openSource(bench.id);
        expect(find.text(bench.labelDe), findsOneWidget);
        expect(find.text('OpenBand'), findsOneWidget);
        expect(copyAction(), findsOneWidget);
        await capture('exercise-copy-source');
        await openCopy();
        expect(find.text('Bankdrücken · Kopie'), findsOneWidget);
        expect(tester.widget<OBAction>(saveDefinition()).onPressed, isNull);
        await expectRowValue(
          const ValueKey('custom-exercise-equipment'),
          'Langhantel',
        );
        await expectRowValue(
          const ValueKey('custom-exercise-load'),
          'Auswählen',
        );
        await capture('exercise-copy-preset');
        await popRoute();
        expect(definitionEditor(), findsNothing);
        expect(find.text(bench.labelDe), findsOneWidget);
        expect(copyAction(), findsOneWidget);
        await capture('exercise-copy-cancel');
        await popRoute();
        expect(find.byType(OpenBandExercisePicker), findsOneWidget);
        expect(repository.createCalls, 1);
        expect(repository.lastCreate!.current!.id, curlId);
        expect(
          templateStamp(await repository.readTemplates()),
          originalTemplates,
        );
        expect(repository.templateSaves, 0);

        repository = await loadRepo();
        await seedCurl(repository);
        await mountEditor(repository: repository, brightness: Brightness.dark);
        await openPicker();
        await openSource(bench.id);
        await capture('exercise-copy-source-dark');
        await openCopy();
        expect(find.text('Bankdrücken · Kopie'), findsOneWidget);
        await capture('exercise-copy-preset-dark');
        await popRoute();
        await popRoute();

        repository = await loadRepo();
        await seedCurl(repository);
        await mountEditor(repository: repository);
        await openPicker();
        await searchPicker('Curl');
        await openSource(curlId);
        expect(find.text('Kurzhantel-Curl'), findsOneWidget);
        await openCopy();
        expect(find.text('Kurzhantel-Curl · Kopie'), findsOneWidget);
        await expectRowValue(
          const ValueKey('custom-exercise-equipment'),
          'Kurzhantel',
        );
        await expectRowValue(
          const ValueKey('custom-exercise-load'),
          'Je Hantel',
        );
        await expectRowValue(const ValueKey('custom-exercise-count'), '2');
        await expectRowValue(
          const ValueKey('custom-exercise-reps'),
          'Je Seite',
        );
        await expectRowValue(
          const ValueKey('custom-exercise-primary'),
          'Bizeps',
        );
        await expectRowValue(
          const ValueKey('custom-exercise-secondary'),
          'Unterarm',
        );
        expect(tester.widget<OBAction>(saveDefinition()).onPressed, isNotNull);
        await capture('exercise-copy-custom');
        repository.failNextCreate = true;
        await tester.tap(saveDefinition().hitTestable());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
        expect(find.text('Erneut speichern'), findsOneWidget);
        expect(find.text('Kurzhantel-Curl · Kopie'), findsOneWidget);
        await capture('exercise-copy-retry');
        await saveAndReturn(repository);
        final copied = repository.lastCreate!.current!;
        expect(copied.id, isNot(curlId));
        expect(copied.id, isNot(bench.id));
        expect(copied.retained['copiedFrom'], curlId);
        expect(
          (await repository.readExerciseCatalogue()).byId(curlId)!.label,
          'Kurzhantel-Curl',
        );
        expect(inPicker(find.text('Kurzhantel-Curl')), findsOneWidget);
        expect(inPicker(find.text('Kurzhantel-Curl · Kopie')), findsOneWidget);
        expect(plusOf(curlId), findsOneWidget);
        expect(plusOf(copied.id), findsOneWidget);
        await expectUnselectedAdd();
        expect(repository.templateSaves, 0);
        await capture('exercise-copy-library');

        repository = await loadRepo();
        await seedCurl(repository);
        await mountEditor(repository: repository, brightness: Brightness.dark);
        await openPicker();
        await searchPicker('Curl');
        await openSource(curlId);
        await openCopy();
        await capture('exercise-copy-custom-dark');
        repository.failNextCreate = true;
        await tester.tap(saveDefinition().hitTestable());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
        await capture('exercise-copy-retry-dark');
        await saveAndReturn(repository);
        await capture('exercise-copy-library-dark');
        expect(repository.templateSaves, 0);

        repository = await loadRepo();
        await seedCurl(repository);
        await mountEditor(repository: repository);
        await openPicker();
        await searchPicker('Bank');
        await openSource(bench.id);
        await openCopy();
        await fillPresetRemainder();
        final name = find.byKey(const ValueKey('custom-exercise-name'));
        await enterFocused(name, 'Wandsitz');
        await dismissKeyboard();
        await saveAndReturn(repository);
        final hidden = repository.lastCreate!.current!;
        expect(hidden.label, 'Wandsitz');
        final notice = find.byKey(const ValueKey('custom-exercise-saved'));
        expect(notice, findsOneWidget);
        expect(
          find.descendant(of: notice, matching: find.text('Anzeigen')),
          findsOneWidget,
        );
        await capture('exercise-copy-hidden');
        await tester.tap(find.text('Anzeigen').hitTestable());
        await pumpInk();
        expect(
          find.byKey(const ValueKey('custom-exercise-saved')),
          findsNothing,
        );
        expect(inPicker(find.text('Wandsitz')), findsWidgets);
        await capture('exercise-copy-hidden-reveal');
        expect(repository.templateSaves, 0);

        Future<void> captureScaled({
          required String name,
          required Brightness brightness,
          required bool scrolled,
        }) async {
          final scaled = await loadRepo();
          await seedCurl(scaled, id: shortCurlId, label: 'Curl');
          await mountEditor(
            repository: scaled,
            brightness: brightness,
            scale: 2,
          );
          await openPicker();
          await searchPicker('Curl');
          await openSource(shortCurlId);
          await openCopy();
          expect(find.text('Curl · Kopie'), findsOneWidget);
          final editor = definitionEditor();
          final save = saveDefinition();
          await expectInSafeViewport(find.text('Eigene Übung'));
          await expectInSafeViewport(save);
          expect(tester.widget<OBAction>(save).onPressed, isNotNull);
          if (scrolled) {
            final secondary = find.byKey(
              const ValueKey('custom-exercise-secondary'),
            );
            await ensureFullyInSafeViewport(editor, secondary);
            await expectInSafeViewport(save);
            expect(rectInSafeViewport(tester.getRect(save)), isTrue);
            expect(
              rectInSafeViewport(tester.getRect(secondary), contentOf: editor),
              isTrue,
            );
            await capture(name);
          } else {
            await scrollListToMin(editor);
            await expectInSafeViewport(
              find.byKey(const ValueKey('custom-exercise-name')),
              contentOf: editor,
            );
            await capture(name);
          }
        }

        await captureScaled(
          name: 'exercise-copy-2x',
          brightness: Brightness.light,
          scrolled: false,
        );
        await captureScaled(
          name: 'exercise-copy-2x-scrolled',
          brightness: Brightness.light,
          scrolled: true,
        );
        await captureScaled(
          name: 'exercise-copy-2x-dark',
          brightness: Brightness.dark,
          scrolled: false,
        );
        await captureScaled(
          name: 'exercise-copy-2x-scrolled-dark',
          brightness: Brightness.dark,
          scrolled: true,
        );
      }

      Future<void> reviewCustomLoad() async {
        const curlId = 'custom-curl';
        const holdId = 'custom-hold';

        Future<_CustomExerciseReviewRepo> loadRepo() async {
          Future<Map> load(String name) async =>
              jsonDecode(
                    await rootBundle.loadString(
                      'docs/openband5/assets/fixtures/$name.json',
                    ),
                  )
                  as Map;
          final repo = _CustomExerciseReviewRepo(
            await load('day-summary'),
            await load('sleep-detail'),
            activity: await load('additional-flows'),
            run: await load('run-detail'),
          );
          await repo.seedNutritionGoals();
          return repo;
        }

        Widget reviewHost({
          required Widget home,
          Brightness brightness = Brightness.light,
          double scale = 1,
        }) => MaterialApp(
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
          home: home,
        );

        Finder downScrollable(Finder ancestor) => find.descendant(
          of: ancestor,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        );

        Rect reviewSafeViewport({Finder? contentOf}) {
          final view = tester.view;
          final dpr = view.devicePixelRatio;
          final size = view.physicalSize / dpr;
          final pad = view.viewPadding;
          final screen = Rect.fromLTRB(
            pad.left / dpr,
            pad.top / dpr,
            size.width - pad.right / dpr,
            size.height - pad.bottom / dpr,
          );
          if (contentOf == null) return screen;
          final box = tester.getRect(downScrollable(contentOf).first);
          return Rect.fromLTRB(
            box.left < screen.left ? screen.left : box.left,
            box.top < screen.top ? screen.top : box.top,
            box.right > screen.right ? screen.right : box.right,
            box.bottom > screen.bottom ? screen.bottom : box.bottom,
          );
        }

        bool rectInSafeViewport(
          Rect box, {
          Finder? contentOf,
          double slop = 0.5,
        }) {
          final safe = reviewSafeViewport(contentOf: contentOf);
          return box.top >= safe.top - slop &&
              box.bottom <= safe.bottom + slop &&
              box.left >= safe.left - slop &&
              box.right <= safe.right + slop;
        }

        Future<void> expectInSafeViewport(
          Finder target, {
          Finder? contentOf,
        }) async {
          expect(target, findsWidgets);
          expect(
            rectInSafeViewport(tester.getRect(target), contentOf: contentOf),
            isTrue,
          );
        }

        Future<void> revealIn(Finder ancestor, Finder target) async {
          final scrollable = downScrollable(ancestor).first;
          var scrolls = 0;
          var searchUp = true;
          while (target.evaluate().isEmpty ||
              target.hitTestable().evaluate().isEmpty) {
            if (scrolls >= 32) {
              throw FlutterError(
                'Control is not hit-testable after production scrolling.',
              );
            }
            if (target.evaluate().isEmpty) {
              final position = tester
                  .state<ScrollableState>(scrollable)
                  .position;
              final atMin = position.pixels <= position.minScrollExtent + 0.5;
              final atMax = position.pixels >= position.maxScrollExtent - 0.5;
              if (searchUp && atMin) {
                searchUp = false;
              }
              final dy = searchUp
                  ? (atMin ? 0.0 : 64.0)
                  : (atMax ? 0.0 : -64.0);
              if (dy == 0) {
                throw FlutterError(
                  'Control is not hit-testable after production scrolling.',
                );
              }
              await tester.drag(scrollable, Offset(0, dy));
              await tester.pump();
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
        }

        Future<void> ensureFullyInSafeViewport(
          Finder ancestor,
          Finder target, {
          bool content = true,
        }) async {
          await revealIn(ancestor, target);
          final scrollable = downScrollable(ancestor).first;
          final contentOf = content ? ancestor : null;
          var extra = 0;
          while (!rectInSafeViewport(
            tester.getRect(target),
            contentOf: contentOf,
          )) {
            if (extra >= 32) {
              throw FlutterError(
                'Control is not fully within the safe viewport.',
              );
            }
            final box = tester.getRect(target);
            final safe = reviewSafeViewport(contentOf: contentOf);
            final overflowBottom = box.bottom - safe.bottom;
            final overflowTop = safe.top - box.top;
            if (extra == 0) {
              await Scrollable.ensureVisible(
                tester.element(target),
                alignment: overflowBottom >= overflowTop ? 1.0 : 0.0,
              );
              await tester.pump();
            } else {
              const minGesture = 64.0;
              final needed = overflowBottom > 0
                  ? -(overflowBottom + 8)
                  : overflowTop + 8;
              final dy = needed < 0
                  ? (needed > -minGesture ? -minGesture : needed)
                  : (needed < minGesture ? minGesture : needed);
              await tester.drag(scrollable, Offset(0, dy));
              await tester.pump();
            }
            extra++;
          }
          expect(
            rectInSafeViewport(tester.getRect(target), contentOf: contentOf),
            isTrue,
          );
          expect(target.hitTestable(), findsOneWidget);
        }

        Future<void> pumpUntil(bool Function() ready, String message) async {
          await tester.pump();
          var waited = 0;
          while (!ready()) {
            if (++waited > 80) {
              throw FlutterError(message);
            }
            await tester.pump(const Duration(milliseconds: 16));
          }
          await reviewPumpPageTransitions(tester);
        }

        Future<void> pumpSheet() async {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
        }

        Future<void> pumpInk() async {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        }

        double keyboardInset() =>
            tester.view.viewInsets.bottom / tester.view.devicePixelRatio;

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
          expect(keyboardInset(), 0);
        }

        Future<void> enterFocused(Finder field, String text) async {
          await settleKeyboard(field);
          await tester.enterText(field, text);
          await tester.pump();
          expect(tester.widget<TextField>(field).controller!.text, text);
        }

        Finder hintedField(String hint) => find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.hintText == hint,
        );

        Finder plusOf(String id) => find.byKey(ValueKey('exercise-select-$id'));

        Finder saveTemplateAction() =>
            find.widgetWithText(OBAction, 'Vorlage speichern');

        Future<void> mountEditor({
          required _CustomExerciseReviewRepo repository,
          WorkoutTemplate? template,
          Brightness brightness = Brightness.light,
          double scale = 1,
        }) async {
          await tester.pumpWidget(
            reviewHost(
              brightness: brightness,
              scale: scale,
              home: OpenBandTemplateEditor(
                repository: repository,
                template: template,
              ),
            ),
          );
          await pumpUntil(
            () => find.byType(OpenBandTemplateEditor).evaluate().isNotEmpty,
            'Template editor did not finish loading.',
          );
        }

        Future<void> mountLive({
          required _CustomExerciseReviewRepo repository,
          required WorkoutTemplate template,
          Brightness brightness = Brightness.light,
          double scale = 1,
        }) async {
          await tester.pumpWidget(
            reviewHost(
              brightness: brightness,
              scale: scale,
              home: OpenBandStrengthLive(
                repository: repository,
                template: template,
              ),
            ),
          );
          await pumpUntil(
            () =>
                find.byType(OpenBandStrengthLive).evaluate().isNotEmpty &&
                find.text(template.name).evaluate().isNotEmpty,
            'Live session did not start.',
          );
        }

        bool pickerCatalogueReady() {
          if (find.byType(OpenBandExercisePicker).evaluate().isEmpty) {
            return false;
          }
          return find.text('5 Übungen').evaluate().isNotEmpty ||
              find.text('6 Übungen').evaluate().isNotEmpty ||
              find.text('1 Übung').evaluate().isNotEmpty ||
              find.text('0 Übungen').evaluate().isNotEmpty ||
              find.text('Keine Übungen gefunden').evaluate().isNotEmpty;
        }

        Future<void> openPicker() async {
          final editor = find.byType(OpenBandTemplateEditor);
          final add = find.widgetWithText(OBAction, 'Übung hinzufügen');
          await ensureFullyInSafeViewport(editor, add);
          await tester.tap(add.hitTestable());
          await pumpSheet();
          await tester.tap(find.text('Bibliothek'));
          await pumpUntil(
            pickerCatalogueReady,
            'Exercise picker did not finish loading.',
          );
        }

        Future<CustomExerciseWriteResult> seedCurl(
          _CustomExerciseReviewRepo repository,
        ) {
          return repository.createCustomExercise(
            CustomExerciseDraft(
              id: curlId,
              label: 'Kurzhantel-Curl',
              mode: ExerciseCaptureMode.repetitions,
              equipment: ExerciseEquipmentCategory.dumbbell,
              loadBasis: ExerciseLoadBasis.perDevice,
              deviceCount: 2,
              repetitionBasis: ExerciseRepetitionBasis.perSide,
              primaryMuscles: const ['biceps'],
              secondaryMuscles: const ['forearms'],
            ),
          );
        }

        Future<void> addCurlFromLibrary() async {
          await openPicker();
          final picker = find.byType(OpenBandExercisePicker);
          final search = find.byKey(const ValueKey('exercise-search'));
          await ensureFullyInSafeViewport(picker, search);
          await enterFocused(search, 'Curl');
          await dismissKeyboard();
          await ensureFullyInSafeViewport(picker, plusOf(curlId));
          await tester.tap(plusOf(curlId).hitTestable());
          await pumpInk();
          final add = find.widgetWithText(OBAction, '1 Übung hinzufügen');
          await expectInSafeViewport(add);
          await tester.tap(add.hitTestable());
          await reviewPumpPageTransitions(tester);
          await tester.pump();
          expect(find.byType(OpenBandExercisePicker), findsNothing);
          expect(find.text('Kurzhantel-Curl'), findsWidgets);
          expect(find.text('kg je Hantel · Wdh. je Seite'), findsOneWidget);
        }

        Future<void> fillPlanFields() async {
          final editor = find.byType(OpenBandTemplateEditor);
          final name = hintedField('Name der Vorlage');
          await ensureFullyInSafeViewport(editor, name);
          await enterFocused(name, 'Kurztraining');
          await dismissKeyboard();
          final load = hintedField('kg');
          await ensureFullyInSafeViewport(editor, load);
          await enterFocused(load, '10');
          await dismissKeyboard();
          final reps = hintedField('Wdh.');
          await ensureFullyInSafeViewport(editor, reps);
          await enterFocused(reps, '8');
          await dismissKeyboard();
          expect(tester.widget<TextField>(load).controller!.text, '10');
          expect(tester.widget<TextField>(reps).controller!.text, '8');
          expect(find.text('Beide Seiten'), findsOneWidget);
        }

        Future<WorkoutTemplate> saveAndRead(
          _CustomExerciseReviewRepo repository,
        ) async {
          final save = saveTemplateAction();
          await expectInSafeViewport(save);
          expect(tester.widget<OBAction>(save).onPressed, isNotNull);
          final saves = repository.templateSaves;
          await tester.tap(save.hitTestable());
          await reviewPumpPageTransitions(tester);
          await tester.pump();
          expect(repository.templateSaves, saves + 1);
          return (await repository.readTemplates()).firstWhere(
            (t) => t.name == 'Kurztraining',
          );
        }

        void expectBothSidesCurl(PlannedSet set) {
          expect(set.reps, 8);
          expect(set.loadKg, 20);
          expect(set.load, isNotNull);
          expect(set.load!.value, 10);
          expect(set.load!.deviceCount, 2);
          expect(set.load!.side, ExerciseSetSide.both);
          expect(set.load!.basis, ExerciseLoadBasis.perDevice);
          expect(set.load!.unit, ExerciseLoadUnit.kg);
          expect(set.load!.repetitionBasis, ExerciseRepetitionBasis.perSide);
        }

        Finder liveField(String setId, List<String> suffixes) {
          for (final suffix in suffixes) {
            final found = find.byKey(ValueKey('field-$setId-$suffix'));
            if (found.evaluate().isNotEmpty) return found;
          }
          throw FlutterError(
            'Missing live field field-$setId-{${suffixes.join(',')}}',
          );
        }

        Finder liveLoadField(String setId) =>
            liveField(setId, const ['kg', '76', '76.0']);

        Finder liveRepsField(String setId) =>
            liveField(setId, const ['wdh', '64', '64.0']);

        Future<void> enterLiveSet(String setId) async {
          final live = find.byType(OpenBandStrengthLive);
          final load = liveLoadField(setId);
          await ensureFullyInSafeViewport(live, load);
          await enterFocused(load, '10');
          await dismissKeyboard();
          final reps = liveRepsField(setId);
          await ensureFullyInSafeViewport(live, reps);
          await enterFocused(reps, '8');
          await dismissKeyboard();
        }

        Future<ActiveStrengthSession> expectRecordedCurl({
          required _CustomExerciseReviewRepo repository,
          required String setId,
        }) async {
          final runtime = await repository.readActiveStrengthSession();
          expect(runtime, isA<ActiveStrengthSession>());
          final session = runtime as ActiveStrengthSession;
          expect(session.recorded, hasLength(1));
          final recorded = session.recorded.single;
          expect(recorded.plannedSetId, setId);
          expect(recorded.reps, 8);
          expect(recorded.loadKg, 20);
          expect(recorded.load, isNotNull);
          expect(recorded.load!.value, 10);
          expect(recorded.load!.deviceCount, 2);
          expect(recorded.load!.side, ExerciseSetSide.both);
          return session;
        }

        // Main plan: 10 kg × 2 devices, 8 per side, both sides.
        var repository = await loadRepo();
        expect((await seedCurl(repository)).saved, isTrue);
        await mountEditor(repository: repository);
        await addCurlFromLibrary();
        await fillPlanFields();
        await expectInSafeViewport(saveTemplateAction());
        await capture('custom-load-plan');

        final side = find.text('Beide Seiten').first;
        final editor = find.byType(OpenBandTemplateEditor);
        await ensureFullyInSafeViewport(editor, side);
        await tester.tap(side.hitTestable());
        await pumpSheet();
        expect(find.text('Seite'), findsOneWidget);
        expect(find.text('Links'), findsOneWidget);
        expect(find.text('Rechts'), findsOneWidget);
        await capture('custom-load-side');
        await tester.tap(find.text('Beide Seiten').last);
        await pumpSheet();
        expect(find.text('Seite'), findsNothing);

        var saved = await saveAndRead(repository);
        expectBothSidesCurl(saved.exercises.single.sets.single);
        await mountEditor(repository: repository, template: saved);
        expect(
          tester.widget<TextField>(hintedField('kg')).controller!.text,
          '10',
        );
        expect(
          tester.widget<TextField>(hintedField('Wdh.')).controller!.text,
          '8',
        );
        expect(find.text('Beide Seiten'), findsOneWidget);
        expectBothSidesCurl(
          (await repository.readTemplates())
              .firstWhere((t) => t.id == saved.id)
              .exercises
              .single
              .sets
              .single,
        );

        await mountEditor(
          repository: repository,
          template: saved,
          brightness: Brightness.dark,
        );
        expect(find.text('kg je Hantel · Wdh. je Seite'), findsOneWidget);
        await capture('custom-load-plan-dark');

        final setId = saved.exercises.single.sets.single.id;
        await mountLive(repository: repository, template: saved);
        await enterLiveSet(setId);
        expect(find.text('kg je Hantel · Wdh. je Seite'), findsOneWidget);
        expect(find.text('Beide Seiten'), findsOneWidget);
        await tester.tap(find.byTooltip('Übungsmenü'));
        await pumpSheet();
        expect(find.text('Einheit'), findsOneWidget);
        expect(find.text('kg'), findsWidgets);
        Navigator.of(tester.element(find.text('Einheit'))).pop();
        await pumpSheet();
        await capture('custom-load-live');

        repository.failStrengthWrites = true;
        final confirm = find.byKey(ValueKey('confirm-$setId'));
        await ensureFullyInSafeViewport(
          find.byType(OpenBandStrengthLive),
          confirm,
        );
        await tester.tap(confirm.hitTestable());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
        expect(
          tester.widget<TextField>(liveLoadField(setId)).controller!.text,
          '10',
        );
        expect(
          tester.widget<TextField>(liveRepsField(setId)).controller!.text,
          '8',
        );
        expect(
          ((await repository.readActiveStrengthSession())
                  as ActiveStrengthSession)
              .recorded,
          isEmpty,
        );
        await capture('custom-load-record-error');

        repository.failStrengthWrites = false;
        await tester.tap(find.text('Erneut'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await expectRecordedCurl(repository: repository, setId: setId);
        expect(find.text('Speichern fehlgeschlagen'), findsNothing);

        // Dark live + error on a fresh write (one active session per repo).
        final darkRepo = await loadRepo();
        expect((await seedCurl(darkRepo)).saved, isTrue);
        await darkRepo.saveTemplate(saved);
        await mountLive(
          repository: darkRepo,
          template: saved,
          brightness: Brightness.dark,
        );
        await enterLiveSet(setId);
        await capture('custom-load-live-dark');
        darkRepo.failStrengthWrites = true;
        await tester.tap(find.byKey(ValueKey('confirm-$setId')).hitTestable());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
        expect(
          tester.widget<TextField>(liveLoadField(setId)).controller!.text,
          '10',
        );
        await capture('custom-load-record-error-dark');
        darkRepo.failStrengthWrites = false;
        await tester.tap(find.text('Erneut'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await expectRecordedCurl(repository: darkRepo, setId: setId);

        // Left side uses one actual device.
        final leftRepo = await loadRepo();
        expect((await seedCurl(leftRepo)).saved, isTrue);
        await mountEditor(repository: leftRepo);
        await addCurlFromLibrary();
        await fillPlanFields();
        await ensureFullyInSafeViewport(
          find.byType(OpenBandTemplateEditor),
          find.text('Beide Seiten').first,
        );
        await tester.tap(find.text('Beide Seiten').first.hitTestable());
        await pumpSheet();
        await tester.tap(find.text('Links'));
        await pumpSheet();
        expect(find.text('Links'), findsOneWidget);
        final leftSaved = await saveAndRead(leftRepo);
        final leftSet = leftSaved.exercises.single.sets.single;
        expect(leftSet.reps, 8);
        expect(leftSet.loadKg, 10);
        expect(leftSet.load!.value, 10);
        expect(leftSet.load!.deviceCount, 1);
        expect(leftSet.load!.side, ExerciseSetSide.left);

        // Timed bodyweight: weight field absent, unit not offered.
        final timeRepo = await loadRepo();
        expect(
          (await timeRepo.createCustomExercise(
            CustomExerciseDraft(
              id: holdId,
              label: 'Wandsitz',
              mode: ExerciseCaptureMode.time,
              equipment: ExerciseEquipmentCategory.bodyweight,
              loadBasis: ExerciseLoadBasis.bodyweight,
              primaryMuscles: const ['legs'],
            ),
          )).saved,
          isTrue,
        );
        await mountEditor(repository: timeRepo);
        await openPicker();
        await ensureFullyInSafeViewport(
          find.byType(OpenBandExercisePicker),
          plusOf(holdId),
        );
        await tester.tap(plusOf(holdId).hitTestable());
        await pumpInk();
        await tester.tap(
          find.widgetWithText(OBAction, '1 Übung hinzufügen').hitTestable(),
        );
        await reviewPumpPageTransitions(tester);
        await tester.pump();
        expect(hintedField('kg'), findsNothing);
        expect(hintedField('lb'), findsNothing);
        expect(hintedField('Sek.'), findsOneWidget);
        expect(find.text('Beide Seiten'), findsNothing);
        expect(find.textContaining('je Hantel'), findsNothing);
        await capture('custom-load-bodyweight');

        // Unknown historic metadata is not recaptioned as je Hantel.
        final unknownRepo = await loadRepo();
        expect((await seedCurl(unknownRepo)).saved, isTrue);
        final unknownLoad = OriginalLoadInput.fromJson({
          'value': 17.25,
          'unit': 'stone',
          'basis': 'futureBasis',
          'repetitionBasis': 'futureReps',
          'side': 'futureSide',
          'future': {'v': 2},
        });
        final unknownTemplate = WorkoutTemplate(
          id: 'tpl-unknown-load',
          name: 'Altlast',
          version: 1,
          exercises: [
            PlannedExercise(
              id: 'ex-unknown',
              exerciseKey: curlId,
              name: 'Kurzhantel-Curl',
              definition: (await unknownRepo.readExerciseCatalogue())
                  .byId(curlId)!
                  .snapshot(),
              sets: [
                PlannedSet(
                  id: 'set-unknown',
                  reps: 8,
                  loadKg: 20,
                  load: unknownLoad,
                ),
              ],
            ),
          ],
          updatedAt: DateTime(2026, 9, 1),
        );
        await unknownRepo.saveTemplate(unknownTemplate);
        await mountEditor(repository: unknownRepo, template: unknownTemplate);
        expect(find.textContaining('je Hantel'), findsNothing);
        expect(find.byKey(const ValueKey('side-set-unknown')), findsNothing);
        await capture('custom-load-unknown');

        Future<void> scrollListToMin(Finder ancestor) async {
          final scrollable = downScrollable(ancestor).first;
          var scrolls = 0;
          var pumps = 0;
          while (true) {
            final position = tester.state<ScrollableState>(scrollable).position;
            final min = position.minScrollExtent;
            final offset = position.pixels - min;
            final idle = !position.isScrollingNotifier.value;
            if (idle && offset.abs() <= 0.5) {
              expect(offset.abs(), lessThanOrEqualTo(0.5));
              expect(position.isScrollingNotifier.value, isFalse);
              return;
            }
            if (offset > 0.5) {
              if (++scrolls > 32) {
                throw FlutterError('ListView did not reach min scroll extent.');
              }
              await tester.drag(scrollable, const Offset(0, 64));
              await tester.pump();
              continue;
            }
            if (++pumps > 40) {
              throw FlutterError('ListView overscroll did not settle at min.');
            }
            await tester.pump(const Duration(milliseconds: 16));
          }
        }

        Future<void> capturePlanScaled({
          required String name,
          required bool scrolled,
        }) async {
          final scaled = await loadRepo();
          expect((await seedCurl(scaled)).saved, isTrue);
          await mountEditor(repository: scaled, scale: 2);
          await addCurlFromLibrary();
          await fillPlanFields();
          final save = saveTemplateAction();
          await expectInSafeViewport(find.text('Neue Vorlage'));
          await expectInSafeViewport(save);
          if (scrolled) {
            await ensureFullyInSafeViewport(
              find.byType(OpenBandTemplateEditor),
              find.text('Satz hinzufügen'),
            );
            await expectInSafeViewport(save);
            await capture(name);
            await tester.tap(save.hitTestable());
            await reviewPumpPageTransitions(tester);
            await tester.pump();
            expect(scaled.templateSaves, 1);
            expectBothSidesCurl(
              (await scaled.readTemplates())
                  .firstWhere((t) => t.name == 'Kurztraining')
                  .exercises
                  .single
                  .sets
                  .single,
            );
          } else {
            final editor = find.byType(OpenBandTemplateEditor);
            await scrollListToMin(editor);
            final title = hintedField('Name der Vorlage');
            await ensureFullyInSafeViewport(editor, title);
            expect(
              tester.widget<TextField>(title).controller!.text,
              'Kurztraining',
            );
            await capture(name);
          }
        }

        await capturePlanScaled(name: 'custom-load-plan-2x', scrolled: false);
        await capturePlanScaled(
          name: 'custom-load-plan-2x-scrolled',
          scrolled: true,
        );

        Future<void> captureLiveScaled({
          required String name,
          required bool scrolled,
        }) async {
          final scaled = await loadRepo();
          expect((await seedCurl(scaled)).saved, isTrue);
          await scaled.saveTemplate(saved);
          await mountLive(repository: scaled, template: saved, scale: 2);
          await enterLiveSet(setId);
          final confirm = find.byKey(ValueKey('confirm-$setId'));
          final live = find.byType(OpenBandStrengthLive);
          await expectInSafeViewport(find.text('Kurztraining'));
          if (scrolled) {
            await ensureFullyInSafeViewport(live, confirm);
            expect(rectInSafeViewport(tester.getRect(confirm)), isTrue);
            await capture(name);
            await tester.tap(confirm.hitTestable());
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
            await expectRecordedCurl(repository: scaled, setId: setId);
          } else {
            await scrollListToMin(live);
            await expectInSafeViewport(find.text('Kurztraining'));
            expect(find.text('Kurzhantel-Curl'), findsWidgets);
            await capture(name);
          }
        }

        await captureLiveScaled(name: 'custom-load-live-2x', scrolled: false);
        await captureLiveScaled(
          name: 'custom-load-live-2x-scrolled',
          scrolled: true,
        );

        Future<void> pickDefinitionChoice(Key sheetKey, Key choiceKey) async {
          expect(find.byKey(sheetKey), findsOneWidget);
          final choice = find.byKey(choiceKey);
          expect(choice, findsOneWidget);
          if (choice.hitTestable().evaluate().isEmpty) {
            await ensureFullyInSafeViewport(find.byKey(sheetKey), choice);
          }
          await tester.tap(choice.hitTestable());
          await pumpSheet();
        }

        Future<void> fillHiddenWandsitz() async {
          final editor = find.byType(OpenBandExerciseDefinitionEditor);
          expect(editor, findsOneWidget);
          final name = find.byKey(const ValueKey('custom-exercise-name'));
          await ensureFullyInSafeViewport(editor, name);
          await enterFocused(name, 'Wandsitz');
          await dismissKeyboard();
          await ensureFullyInSafeViewport(
            editor,
            find.byKey(const ValueKey('custom-exercise-equipment')),
          );
          await tester.tap(
            find
                .byKey(const ValueKey('custom-exercise-equipment'))
                .hitTestable(),
          );
          await pumpSheet();
          await pickDefinitionChoice(
            const ValueKey('custom-exercise-equipment-sheet'),
            const ValueKey('custom-exercise-equipment-bodyweight'),
          );
          await ensureFullyInSafeViewport(
            editor,
            find.byKey(const ValueKey('custom-exercise-mode')),
          );
          await tester.tap(
            find.byKey(const ValueKey('custom-exercise-mode')).hitTestable(),
          );
          await pumpSheet();
          await pickDefinitionChoice(
            const ValueKey('custom-exercise-mode-sheet'),
            const ValueKey('custom-exercise-mode-time'),
          );
          await ensureFullyInSafeViewport(
            editor,
            find.byKey(const ValueKey('custom-exercise-load')),
          );
          await tester.tap(
            find.byKey(const ValueKey('custom-exercise-load')).hitTestable(),
          );
          await pumpSheet();
          await pickDefinitionChoice(
            const ValueKey('custom-exercise-load-sheet'),
            const ValueKey('custom-exercise-load-bodyweight'),
          );
          await ensureFullyInSafeViewport(
            editor,
            find.byKey(const ValueKey('custom-exercise-primary')),
          );
          await tester.tap(
            find.byKey(const ValueKey('custom-exercise-primary')).hitTestable(),
          );
          await reviewPumpPageTransitions(tester);
          await tester.pump();
          final legs = find.byKey(const ValueKey('custom-muscle-legs'));
          expect(legs, findsOneWidget);
          await tester.tap(legs.hitTestable());
          await pumpInk();
          await tester.tap(
            find.widgetWithText(OBAction, 'Übernehmen').hitTestable(),
          );
          await reviewPumpPageTransitions(tester);
          await tester.pump();
          final save = find.byKey(const ValueKey('custom-exercise-save'));
          await expectInSafeViewport(save);
          expect(tester.widget<OBAction>(save).onPressed, isNotNull);
          await tester.tap(save.hitTestable());
          await reviewPumpPageTransitions(tester);
          await tester.pump();
          await pumpUntil(
            () =>
                find
                    .byType(OpenBandExerciseDefinitionEditor)
                    .evaluate()
                    .isEmpty &&
                pickerCatalogueReady(),
            'Hidden create did not return to the picker.',
          );
        }

        Future<void> expectHiddenNotice(String label) async {
          final notice = find.byKey(const ValueKey('custom-exercise-saved'));
          expect(notice, findsOneWidget);
          expect(
            find.descendant(of: notice, matching: find.text(label)),
            findsOneWidget,
          );
          expect(
            find.descendant(of: notice, matching: find.text('Anzeigen')),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byType(OpenBandExercisePicker),
              matching: find.text(label),
            ),
            findsOneWidget,
          );
        }

        Future<void> captureHidden({
          required String name,
          required double scale,
          required bool reveal,
        }) async {
          final hiddenRepo = await loadRepo();
          await mountEditor(repository: hiddenRepo, scale: scale);
          await openPicker();
          final picker = find.byType(OpenBandExercisePicker);
          final search = find.byKey(const ValueKey('exercise-search'));
          await ensureFullyInSafeViewport(picker, search);
          await enterFocused(search, 'Zebra');
          await dismissKeyboard();
          expect(find.text('Keine Übungen gefunden'), findsOneWidget);
          final create = find.byKey(const ValueKey('exercise-create-search'));
          await expectInSafeViewport(create);
          await tester.tap(create.hitTestable());
          await reviewPumpPageTransitions(tester);
          await tester.pump();
          await fillHiddenWandsitz();
          expect(
            tester
                .widget<TextField>(
                  find.byKey(const ValueKey('exercise-search')),
                )
                .controller!
                .text,
            'Zebra',
          );
          expect(
            find.descendant(of: picker, matching: find.text('Wandsitz')),
            findsOneWidget,
          );
          await expectHiddenNotice('Wandsitz');
          final notice = find.byKey(const ValueKey('custom-exercise-saved'));
          final footer = find.ancestor(
            of: notice,
            matching: find.byType(ListView),
          );
          final anzeigen = find.descendant(
            of: notice,
            matching: find.text('Anzeigen'),
          );
          final clear = find.widgetWithText(OBAction, 'Suche löschen');
          await ensureFullyInSafeViewport(footer, notice);
          await ensureFullyInSafeViewport(footer, anzeigen);
          await ensureFullyInSafeViewport(footer, create);
          await ensureFullyInSafeViewport(footer, clear);
          await capture(name);
          if (!reveal) return;
          await tester.tap(anzeigen.hitTestable());
          await tester.pump();
          expect(
            find.byKey(const ValueKey('custom-exercise-saved')),
            findsNothing,
          );
          expect(
            tester
                .widget<TextField>(
                  find.byKey(const ValueKey('exercise-search')),
                )
                .controller!
                .text,
            'Wandsitz',
          );
          expect(
            find.descendant(of: picker, matching: find.text('Wandsitz')),
            findsWidgets,
          );
          expect(plusOf(hiddenRepo.lastCreate!.current!.id), findsOneWidget);
        }

        await captureHidden(
          name: 'custom-load-hidden',
          scale: 1,
          reveal: false,
        );
        await captureHidden(
          name: 'custom-load-hidden-2x',
          scale: 2,
          reveal: true,
        );
        OriginalLoadInput perDeviceOriginal({
          required double value,
          required ExerciseLoadUnit unit,
        }) => OriginalLoadInput(
          value: value,
          unit: unit,
          basis: ExerciseLoadBasis.perDevice,
          deviceCount: 2,
          repetitionBasis: ExerciseRepetitionBasis.perSide,
          side: ExerciseSetSide.both,
        );

        Future<WorkoutTemplate> writePlan(
          _CustomExerciseReviewRepo repository,
          WorkoutTemplate template,
        ) async {
          await repository.saveTemplate(template);
          return (await repository.readTemplates()).firstWhere(
            (t) => t.id == template.id,
          );
        }

        Future<ExerciseDefinitionSnapshot> curlSnapshot(
          _CustomExerciseReviewRepo repository,
        ) async {
          expect((await seedCurl(repository)).saved, isTrue);
          return (await repository.readExerciseCatalogue())
              .byId(curlId)!
              .snapshot();
        }

        PlannedSet planned({
          required String id,
          required int reps,
          OriginalLoadInput? load,
          double? loadKg,
        }) {
          final resolved = resolveStoredLoadKg(input: load, loadKg: loadKg);
          return PlannedSet(
            id: id,
            reps: reps,
            loadKg: resolved,
            mode: PlannedSetMode.repetitions,
            load: load,
          );
        }

        WorkoutTemplate curlPlan({
          required String id,
          required ExerciseDefinitionSnapshot definition,
          required List<PlannedSet> sets,
        }) => WorkoutTemplate(
          id: id,
          name: 'Kurztraining',
          version: 1,
          exercises: [
            PlannedExercise(
              id: 'ex-$id',
              exerciseKey: curlId,
              name: 'Kurzhantel-Curl',
              definition: definition,
              sets: sets,
            ),
          ],
          updatedAt: DateTime(2026, 9, 1),
        );

        Future<void> mountNamedLive({
          required _CustomExerciseReviewRepo repository,
          required WorkoutTemplate template,
          required String label,
          Brightness brightness = Brightness.light,
          double scale = 1,
        }) async {
          await mountLive(
            repository: repository,
            template: template,
            brightness: brightness,
            scale: scale,
          );
          await pumpUntil(
            () => find.text(label).evaluate().isNotEmpty,
            'Live session did not show $label.',
          );
        }

        final kg10 = perDeviceOriginal(value: 10, unit: ExerciseLoadUnit.kg);
        final lb22 = perDeviceOriginal(value: 22, unit: ExerciseLoadUnit.lb);
        expect(resolveStoredLoadKg(input: kg10), 20);
        expect(resolveStoredLoadKg(input: lb22), 22 * kKilogramsPerPound * 2);

        Future<WorkoutTemplate> mixedUnitsPlan(
          _CustomExerciseReviewRepo repository,
        ) async {
          final definition = await curlSnapshot(repository);
          final saved = await writePlan(
            repository,
            curlPlan(
              id: 'tpl-mixed-units',
              definition: definition,
              sets: [
                planned(id: 'set-mix-kg1', reps: 8, load: kg10),
                planned(id: 'set-mix-lb', reps: 8, load: lb22),
                planned(id: 'set-mix-kg2', reps: 8, load: kg10),
              ],
            ),
          );
          final sets = saved.exercises.single.sets;
          expect(sets, hasLength(3));
          expect(sets[0].loadKg, 20);
          expect(sets[0].load!.value, 10);
          expect(sets[0].load!.unit, ExerciseLoadUnit.kg);
          expect(sets[0].load!.deviceCount, 2);
          expect(sets[1].load!.value, 22);
          expect(sets[1].load!.unit, ExerciseLoadUnit.lb);
          expect(sets[1].loadKg, resolveStoredLoadKg(input: sets[1].load));
          expect(sets[2].loadKg, 20);
          expect(sets[2].load!.value, 10);
          return saved;
        }

        Future<void> confirmPerDeviceFirst(
          _CustomExerciseReviewRepo repository, {
          required String setId,
        }) async {
          final live = find.byType(OpenBandStrengthLive);
          final load = liveLoadField(setId);
          await ensureFullyInSafeViewport(live, load);
          await enterFocused(load, '10');
          await dismissKeyboard();
          final reps = liveRepsField(setId);
          await ensureFullyInSafeViewport(live, reps);
          await enterFocused(reps, '8');
          await dismissKeyboard();
          final confirm = find.byKey(ValueKey('confirm-$setId'));
          await ensureFullyInSafeViewport(live, confirm);
          await tester.tap(confirm.hitTestable());
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          final runtime = await repository.readActiveStrengthSession();
          expect(runtime, isA<ActiveStrengthSession>());
          final recorded = (runtime as ActiveStrengthSession).recorded.single;
          expect(recorded.plannedSetId, setId);
          expect(recorded.reps, 8);
          expect(recorded.loadKg, 20);
          expect(recorded.load, isNotNull);
          expect(recorded.load!.value, 10);
          expect(recorded.load!.unit, ExerciseLoadUnit.kg);
          expect(recorded.load!.deviceCount, 2);
          expect(recorded.load!.basis, ExerciseLoadBasis.perDevice);
        }

        var mixedRepo = await loadRepo();
        var mixedSaved = await mixedUnitsPlan(mixedRepo);
        await mountNamedLive(
          repository: mixedRepo,
          template: mixedSaved,
          label: 'Kurzhantel-Curl',
        );
        await confirmPerDeviceFirst(mixedRepo, setId: 'set-mix-kg1');
        expect(find.text('LAST'), findsOneWidget);
        expect(find.text('je Hantel · Wdh. je Seite'), findsOneWidget);
        final lbLoad = liveLoadField('set-mix-lb');
        await ensureFullyInSafeViewport(
          find.byType(OpenBandStrengthLive),
          lbLoad,
        );
        expect(tester.widget<TextField>(lbLoad).controller!.text, '22');
        expect(
          tester
              .widget<TextField>(liveRepsField('set-mix-lb'))
              .controller!
              .text,
          '8',
        );
        await capture('custom-load-mixed-units');

        mixedRepo = await loadRepo();
        mixedSaved = await mixedUnitsPlan(mixedRepo);
        await mountNamedLive(
          repository: mixedRepo,
          template: mixedSaved,
          label: 'Kurzhantel-Curl',
          brightness: Brightness.dark,
        );
        await confirmPerDeviceFirst(mixedRepo, setId: 'set-mix-kg1');
        expect(find.text('LAST'), findsOneWidget);
        expect(find.text('je Hantel · Wdh. je Seite'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(liveLoadField('set-mix-lb'))
              .controller!
              .text,
          '22',
        );
        await capture('custom-load-mixed-units-dark');

        Future<WorkoutTemplate> mixedBasisPlan(
          _CustomExerciseReviewRepo repository,
        ) async {
          final definition = await curlSnapshot(repository);
          final saved = await writePlan(
            repository,
            curlPlan(
              id: 'tpl-mixed-basis',
              definition: definition,
              sets: [
                planned(id: 'set-basis-device', reps: 8, load: kg10),
                planned(id: 'set-basis-legacy', reps: 8, loadKg: 20),
                planned(id: 'set-basis-kg2', reps: 8, load: kg10),
              ],
            ),
          );
          final sets = saved.exercises.single.sets;
          expect(sets, hasLength(3));
          expect(sets[0].loadKg, 20);
          expect(sets[0].load!.basis, ExerciseLoadBasis.perDevice);
          expect(sets[0].load!.value, 10);
          expect(sets[0].load!.deviceCount, 2);
          expect(sets[1].load, isNull);
          expect(sets[1].loadKg, 20);
          expect(sets[2].loadKg, 20);
          expect(sets[2].load!.value, 10);
          expect(sets[2].load!.basis, ExerciseLoadBasis.perDevice);
          return saved;
        }

        var basisRepo = await loadRepo();
        var basisSaved = await mixedBasisPlan(basisRepo);
        await mountNamedLive(
          repository: basisRepo,
          template: basisSaved,
          label: 'Kurzhantel-Curl',
        );
        await confirmPerDeviceFirst(basisRepo, setId: 'set-basis-device');
        expect(find.text('kg je Hantel · Wdh. je Seite'), findsNothing);
        expect(find.text('je Hantel · Wdh. je Seite'), findsNWidgets(2));
        expect(find.text('Gesamtgewicht'), findsOneWidget);
        await capture('custom-load-mixed-basis');

        basisRepo = await loadRepo();
        basisSaved = await mixedBasisPlan(basisRepo);
        await mountNamedLive(
          repository: basisRepo,
          template: basisSaved,
          label: 'Kurzhantel-Curl',
          brightness: Brightness.dark,
        );
        await confirmPerDeviceFirst(basisRepo, setId: 'set-basis-device');
        expect(find.text('je Hantel · Wdh. je Seite'), findsNWidgets(2));
        expect(find.text('Gesamtgewicht'), findsOneWidget);
        await capture('custom-load-mixed-basis-dark');

        Future<void> captureMixedBasisScaled({
          required String name,
          required bool scrolled,
        }) async {
          final scaled = await loadRepo();
          final saved = await mixedBasisPlan(scaled);
          await mountNamedLive(
            repository: scaled,
            template: saved,
            label: 'Kurzhantel-Curl',
            scale: 2,
          );
          await confirmPerDeviceFirst(scaled, setId: 'set-basis-device');
          final live = find.byType(OpenBandStrengthLive);
          final last = find.byKey(const ValueKey('confirm-set-basis-kg2'));
          if (scrolled) {
            await ensureFullyInSafeViewport(live, last);
            expect(rectInSafeViewport(tester.getRect(last)), isTrue);
            expect(find.text('Gesamtgewicht'), findsOneWidget);
            await capture(name);
          } else {
            await scrollListToMin(live);
            await expectInSafeViewport(find.text('Kurztraining'));
            expect(find.text('je Hantel · Wdh. je Seite'), findsNWidgets(2));
            await capture(name);
          }
        }

        await captureMixedBasisScaled(
          name: 'custom-load-mixed-basis-2x',
          scrolled: false,
        );
        await captureMixedBasisScaled(
          name: 'custom-load-mixed-basis-2x-scrolled',
          scrolled: true,
        );

        Future<WorkoutTemplate> assistancePlan(
          _CustomExerciseReviewRepo repository,
        ) async {
          expect(
            (await repository.createCustomExercise(
              CustomExerciseDraft(
                id: 'custom-assist',
                label: 'Klimmzug unterstützt',
                mode: ExerciseCaptureMode.repetitions,
                equipment: ExerciseEquipmentCategory.machine,
                loadBasis: ExerciseLoadBasis.assistance,
                repetitionBasis: ExerciseRepetitionBasis.total,
                primaryMuscles: const ['back'],
              ),
            )).saved,
            isTrue,
          );
          final definition = (await repository.readExerciseCatalogue())
              .byId('custom-assist')!
              .snapshot();
          final assist = OriginalLoadInput(
            value: 20,
            unit: ExerciseLoadUnit.kg,
            basis: ExerciseLoadBasis.assistance,
            repetitionBasis: ExerciseRepetitionBasis.total,
          );
          expect(resolveStoredLoadKg(input: assist), isNull);
          final saved = await writePlan(
            repository,
            WorkoutTemplate(
              id: 'tpl-assist',
              name: 'Kurztraining',
              version: 1,
              exercises: [
                PlannedExercise(
                  id: 'ex-assist',
                  exerciseKey: 'custom-assist',
                  name: 'Klimmzug unterstützt',
                  definition: definition,
                  sets: [
                    planned(id: 'set-assist-1', reps: 8, load: assist),
                    planned(id: 'set-assist-2', reps: 8, load: assist),
                    planned(id: 'set-assist-3', reps: 8, load: assist),
                  ],
                ),
              ],
              updatedAt: DateTime(2026, 9, 1),
            ),
          );
          final sets = saved.exercises.single.sets;
          expect(sets, hasLength(3));
          for (final set in sets) {
            expect(set.reps, 8);
            expect(set.loadKg, isNull);
            expect(set.load!.basis, ExerciseLoadBasis.assistance);
            expect(set.load!.value, 20);
            expect(
              resolveStoredLoadKg(input: set.load, loadKg: set.loadKg),
              isNull,
            );
          }
          return saved;
        }

        Future<void> confirmAssistanceSet(
          _CustomExerciseReviewRepo repository,
          String setId,
        ) async {
          final live = find.byType(OpenBandStrengthLive);
          final load = liveLoadField(setId);
          await ensureFullyInSafeViewport(live, load);
          await enterFocused(load, '20');
          await dismissKeyboard();
          final reps = liveRepsField(setId);
          await ensureFullyInSafeViewport(live, reps);
          await enterFocused(reps, '8');
          await dismissKeyboard();
          expect(find.text('Beide Seiten'), findsNothing);
          final confirm = find.byKey(ValueKey('confirm-$setId'));
          await ensureFullyInSafeViewport(live, confirm);
          await tester.tap(confirm.hitTestable());
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          final runtime = await repository.readActiveStrengthSession();
          expect(runtime, isA<ActiveStrengthSession>());
          final recorded = (runtime as ActiveStrengthSession).recorded.last;
          expect(recorded.plannedSetId, setId);
          expect(recorded.reps, 8);
          expect(recorded.loadKg, isNull);
          expect(recorded.load, isNotNull);
          expect(recorded.load!.basis, ExerciseLoadBasis.assistance);
          expect(recorded.load!.value, 20);
          expect(recorded.load!.unit, ExerciseLoadUnit.kg);
          expect(resolveStoredLoadKg(input: recorded.load), isNull);
        }

        Future<void> captureAssistance({
          required String name,
          required Brightness brightness,
        }) async {
          final repo = await loadRepo();
          final saved = await assistancePlan(repo);
          await mountNamedLive(
            repository: repo,
            template: saved,
            label: 'Klimmzug unterstützt',
            brightness: brightness,
          );
          expect(find.text('kg Unterstützung'), findsOneWidget);
          expect(find.text('Beide Seiten'), findsNothing);
          expect(find.text('LAST'), findsNothing);
          await confirmAssistanceSet(repo, 'set-assist-1');
          expect(
            ((await repo.readActiveStrengthSession()) as ActiveStrengthSession)
                .recorded,
            hasLength(1),
          );
          expect(
            find.byKey(const ValueKey('confirm-set-assist-2')),
            findsOneWidget,
          );
          await capture(name);
        }

        await captureAssistance(
          name: 'custom-load-assistance',
          brightness: Brightness.light,
        );
        await captureAssistance(
          name: 'custom-load-assistance-dark',
          brightness: Brightness.dark,
        );
      }

      Future<void> reviewGlucose() async {
        final now = DateTime(2026, 9, 15, 9, 41);
        const sourceKey = SyntheticOpenBandRepository.glucoseFixtureSourceKey;

        Future<_GlucoseReviewRepo> loadRepo() async {
          Future<Map> load(String name) async =>
              jsonDecode(
                    await rootBundle.loadString(
                      'docs/openband5/assets/fixtures/$name.json',
                    ),
                  )
                  as Map;
          final repo = _GlucoseReviewRepo(
            await load('day-summary'),
            await load('sleep-detail'),
            activity: await load('additional-flows'),
            run: await load('run-detail'),
          );
          await repo.seedNutritionGoals();
          return repo;
        }

        Widget reviewHost({
          required Widget home,
          Brightness brightness = Brightness.light,
          double scale = 1,
        }) => MaterialApp(
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
          home: home,
        );

        Finder downScrollable(Finder ancestor) => find.descendant(
          of: ancestor,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        );

        Rect reviewSafeViewport({Finder? contentOf}) {
          final view = tester.view;
          final dpr = view.devicePixelRatio;
          final size = view.physicalSize / dpr;
          final pad = view.viewPadding;
          final screen = Rect.fromLTRB(
            pad.left / dpr,
            pad.top / dpr,
            size.width - pad.right / dpr,
            size.height - pad.bottom / dpr,
          );
          if (contentOf == null) return screen;
          final box = tester.getRect(downScrollable(contentOf).first);
          return Rect.fromLTRB(
            box.left < screen.left ? screen.left : box.left,
            box.top < screen.top ? screen.top : box.top,
            box.right > screen.right ? screen.right : box.right,
            box.bottom > screen.bottom ? screen.bottom : box.bottom,
          );
        }

        bool rectInSafeViewport(
          Rect box, {
          Finder? contentOf,
          double slop = 0.5,
        }) {
          final safe = reviewSafeViewport(contentOf: contentOf);
          return box.top >= safe.top - slop &&
              box.bottom <= safe.bottom + slop &&
              box.left >= safe.left - slop &&
              box.right <= safe.right + slop;
        }

        Future<void> expectInSafeViewport(
          Finder target, {
          Finder? contentOf,
        }) async {
          expect(target, findsWidgets);
          expect(
            rectInSafeViewport(tester.getRect(target), contentOf: contentOf),
            isTrue,
          );
        }

        Future<void> revealIn(Finder ancestor, Finder target) async {
          final scrollable = downScrollable(ancestor).first;
          var scrolls = 0;
          var searchUp = true;
          while (target.evaluate().isEmpty ||
              target.hitTestable().evaluate().isEmpty) {
            if (scrolls >= 32) {
              throw FlutterError(
                'Control is not hit-testable after production scrolling.',
              );
            }
            if (target.evaluate().isEmpty) {
              final position = tester
                  .state<ScrollableState>(scrollable)
                  .position;
              final atMin = position.pixels <= position.minScrollExtent + 0.5;
              final atMax = position.pixels >= position.maxScrollExtent - 0.5;
              if (searchUp && atMin) searchUp = false;
              final dy = searchUp
                  ? (atMin ? 0.0 : 64.0)
                  : (atMax ? 0.0 : -64.0);
              if (dy == 0) {
                throw FlutterError(
                  'Control is not hit-testable after production scrolling.',
                );
              }
              await tester.drag(scrollable, Offset(0, dy));
              await tester.pump();
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
        }

        Future<void> ensureFullyInSafeViewport(
          Finder ancestor,
          Finder target, {
          bool content = true,
        }) async {
          await revealIn(ancestor, target);
          final scrollable = downScrollable(ancestor).first;
          final contentOf = content ? ancestor : null;
          var extra = 0;
          while (!rectInSafeViewport(
            tester.getRect(target),
            contentOf: contentOf,
          )) {
            if (extra >= 32) {
              throw FlutterError(
                'Control is not fully within the safe viewport.',
              );
            }
            final box = tester.getRect(target);
            final safe = reviewSafeViewport(contentOf: contentOf);
            final overflowBottom = box.bottom - safe.bottom;
            final overflowTop = safe.top - box.top;
            if (extra == 0) {
              await Scrollable.ensureVisible(
                tester.element(target),
                alignment: overflowBottom >= overflowTop ? 1.0 : 0.0,
              );
              await tester.pump();
            } else {
              const minGesture = 64.0;
              final needed = overflowBottom > 0
                  ? -(overflowBottom + 8)
                  : overflowTop + 8;
              final dy = needed < 0
                  ? (needed > -minGesture ? -minGesture : needed)
                  : (needed < minGesture ? minGesture : needed);
              await tester.drag(scrollable, Offset(0, dy));
              await tester.pump();
            }
            extra++;
          }
          expect(
            rectInSafeViewport(tester.getRect(target), contentOf: contentOf),
            isTrue,
          );
          expect(target.hitTestable(), findsOneWidget);
        }

        Future<void> scrollListToMin(Finder ancestor) async {
          final scrollable = downScrollable(ancestor).first;
          var scrolls = 0;
          var pumps = 0;
          while (true) {
            final position = tester.state<ScrollableState>(scrollable).position;
            final min = position.minScrollExtent;
            final offset = position.pixels - min;
            final idle = !position.isScrollingNotifier.value;
            if (idle && offset.abs() <= 0.5) {
              expect(offset.abs(), lessThanOrEqualTo(0.5));
              expect(position.isScrollingNotifier.value, isFalse);
              return;
            }
            if (offset > 0.5) {
              if (++scrolls > 32) {
                throw FlutterError('ListView did not reach min scroll extent.');
              }
              await tester.drag(scrollable, const Offset(0, 64));
              await tester.pump();
              continue;
            }
            if (++pumps > 40) {
              throw FlutterError('ListView overscroll did not settle at min.');
            }
            await tester.pump(const Duration(milliseconds: 16));
          }
        }

        Future<void> pumpUntil(bool Function() ready, String message) async {
          await tester.pump();
          var waited = 0;
          while (!ready()) {
            if (++waited > 80) throw FlutterError(message);
            await tester.pump(const Duration(milliseconds: 16));
          }
          await reviewPumpPageTransitions(tester);
        }

        Future<void> pumpSheet() async {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
        }

        Future<OpenBandController> mountHealth({
          required _GlucoseReviewRepo repository,
          Brightness brightness = Brightness.light,
          double scale = 1,
        }) async {
          final controller = OpenBandController(
            repository: repository,
            initialDay: '2026-09-15',
            band: repository.band,
            now: () => now,
          );
          await controller.refresh();
          await tester.pumpWidget(
            reviewHost(
              brightness: brightness,
              scale: scale,
              home: Scaffold(
                body: SafeArea(child: OpenBandHealth(controller: controller)),
              ),
            ),
          );
          await pumpUntil(
            () =>
                find.byType(OpenBandHealth).evaluate().isNotEmpty &&
                find.text('Gesundheit').evaluate().isNotEmpty &&
                !controller.loading,
            'Health did not finish loading.',
          );
          return controller;
        }

        Future<void> openGlucoseFromHealth() async {
          final entry = find.byKey(const ValueKey('glukose'));
          final health = find.byType(OpenBandHealth);
          await ensureFullyInSafeViewport(health, entry);
          expect(entry.hitTestable(), findsOneWidget);
          await tester.tap(entry.hitTestable());
          await reviewPumpPageTransitions(tester);
          await pumpUntil(
            () => find.byType(OpenBandGlucose).evaluate().isNotEmpty,
            'Glucose main did not open.',
          );
        }

        Future<void> popGlucose() async {
          await tester.tap(find.byTooltip('Zurück'));
          await reviewPumpPageTransitions(tester);
          await tester.pump();
        }

        Finder useSwitch() => find.descendant(
          of: find.byKey(const ValueKey('glucose-verwenden')),
          matching: find.byType(CupertinoSwitch),
        );

        Future<void> expectMainFixture({
          required bool excluded,
          bool restoreTop = true,
        }) async {
          final page = find.byType(OpenBandGlucose);
          expect(page, findsOneWidget);
          expect(find.text('Glukose'), findsWidgets);
          if (excluded) {
            expect(find.text('Sensor-App · Ausgeblendet'), findsOneWidget);
            expect(find.text('Sensor-App · Apple Health'), findsNothing);
            expect(find.text('—'), findsWidgets);
            expect(find.text('5,2'), findsNothing);
          } else {
            expect(find.text('5,2'), findsWidgets);
            expect(find.text('mmol/L'), findsWidgets);
            expect(find.text('15. September'), findsOneWidget);
            expect(find.text('08:00'), findsWidgets);
            expect(find.text('Sensor-App · Apple Health'), findsOneWidget);
          }
          await ensureFullyInSafeViewport(
            page,
            find.byKey(const ValueKey('glucose-quelle')),
          );
          await ensureFullyInSafeViewport(
            page,
            find.byKey(const ValueKey('glucose-messungen')),
          );
          expect(find.text('11'), findsOneWidget);
          await ensureFullyInSafeViewport(
            page,
            find.byKey(const ValueKey('glucose-synthetic')),
          );
          expect(find.text('Synthetische Daten'), findsOneWidget);
          if (restoreTop) await scrollListToMin(page);
        }

        Future<void> expectSourceClocks({
          required bool included,
          bool restoreTop = true,
        }) async {
          final page = find.byType(OpenBandGlucoseSource);
          expect(find.text('Quelle'), findsWidgets);
          expect(find.text('Sensor-App'), findsWidgets);
          expect(find.text('Apple Health'), findsWidgets);
          final measured = find.text('15. Sep., 08:00');
          final imported = find.text('15. Sep., 09:40');
          final queried = find.text('15. Sep., 09:41');
          await ensureFullyInSafeViewport(page, measured);
          expect(measured, findsOneWidget);
          await ensureFullyInSafeViewport(page, imported);
          expect(imported, findsOneWidget);
          await ensureFullyInSafeViewport(page, queried);
          expect(queried, findsOneWidget);
          final useLabel = find.text('Verwenden');
          await ensureFullyInSafeViewport(page, useLabel);
          expect(useLabel, findsOneWidget);
          final sw = useSwitch();
          await ensureFullyInSafeViewport(page, sw);
          expect(sw.hitTestable(), findsOneWidget);
          expect(
            tester.widget<CupertinoSwitch>(sw).value,
            included ? isTrue : isFalse,
          );
          await ensureFullyInSafeViewport(
            page,
            find.byKey(const ValueKey('glucose-lesen')),
          );
          expect(find.text('Jetzt lesen'), findsOneWidget);
          await ensureFullyInSafeViewport(
            page,
            find.byKey(const ValueKey('glucose-synthetic')),
          );
          expect(find.text('Synthetische Daten'), findsOneWidget);
          if (restoreTop) await scrollListToMin(page);
        }

        Future<void> expectHistoryFixture({bool restoreTop = true}) async {
          final page = find.byType(OpenBandGlucoseHistory);
          expect(find.text('Messungen'), findsWidgets);
          expect(find.text('07:25'), findsNothing);
          expect(find.text('07:30'), findsNothing);
          final eight = find.text('08:00');
          await ensureFullyInSafeViewport(page, eight);
          expect(eight, findsWidgets);
          final mmol = find.textContaining('mmol/L');
          await ensureFullyInSafeViewport(page, mmol.first);
          expect(mmol, findsWidgets);
          await ensureFullyInSafeViewport(
            page,
            find.byKey(const ValueKey('glucose-synthetic')),
          );
          expect(find.text('Synthetische Daten'), findsOneWidget);
          if (restoreTop) await scrollListToMin(page);
        }

        Future<void> openSource() async {
          final row = find.byKey(const ValueKey('glucose-quelle'));
          await ensureFullyInSafeViewport(find.byType(OpenBandGlucose), row);
          await tester.tap(row.hitTestable());
          await reviewPumpPageTransitions(tester);
          await pumpUntil(
            () => find.byType(OpenBandGlucoseSource).evaluate().isNotEmpty,
            'Glucose source did not open.',
          );
        }

        Future<void> openHistory() async {
          final row = find.byKey(const ValueKey('glucose-messungen'));
          await ensureFullyInSafeViewport(find.byType(OpenBandGlucose), row);
          await tester.tap(row.hitTestable());
          await reviewPumpPageTransitions(tester);
          await pumpUntil(
            () => find.byType(OpenBandGlucoseHistory).evaluate().isNotEmpty,
            'Glucose history did not open.',
          );
        }

        Future<void> toggleUse() async {
          final sw = useSwitch();
          expect(sw, findsOneWidget);
          await tester.tap(sw.hitTestable());
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
        }

        // Happy path from Health: main -> source -> exclude -> back ->
        // history -> back -> source -> restore.
        var repo = await loadRepo();
        var snap = await repo.readGlucose();
        expect(snap.history, hasLength(11));
        expect(snap.lastMeasuredAt, DateTime(2026, 9, 15, 8, 0));
        expect(snap.lastImportedAt, DateTime(2026, 9, 15, 9, 40));
        expect(snap.attempt.attemptedAt, DateTime(2026, 9, 15, 9, 41));
        expect(snap.selected?.key, sourceKey);
        var controller = await mountHealth(repository: repo);
        await openGlucoseFromHealth();
        await expectMainFixture(excluded: false);
        await capture('glucose-main');

        await openSource();
        await expectSourceClocks(included: true);
        await capture('glucose-source');
        await toggleUse();
        expect(tester.widget<CupertinoSwitch>(useSwitch()).value, isFalse);
        expect((await repo.readGlucose()).selectedExcluded, isTrue);
        await capture('glucose-source-excluded');
        await popGlucose();
        await expectMainFixture(excluded: true);
        expect((await repo.readGlucose()).history, hasLength(11));
        await capture('glucose-main-excluded');

        await openHistory();
        await expectHistoryFixture();
        await capture('glucose-history');
        await popGlucose();

        await openSource();
        expect(tester.widget<CupertinoSwitch>(useSwitch()).value, isFalse);
        await toggleUse();
        expect(tester.widget<CupertinoSwitch>(useSwitch()).value, isTrue);
        expect((await repo.readGlucose()).selectedExcluded, isFalse);
        await popGlucose();
        await expectMainFixture(excluded: false);

        controller.dispose();

        Future<void> captureMain({
          required String name,
          required Brightness brightness,
          double scale = 1,
          bool excluded = false,
          bool scrolled = false,
        }) async {
          final r = await loadRepo();
          if (excluded) {
            await r.setGlucoseSourceIncluded(sourceKey, included: false);
          }
          final c = await mountHealth(
            repository: r,
            brightness: brightness,
            scale: scale,
          );
          await openGlucoseFromHealth();
          await expectMainFixture(excluded: excluded, restoreTop: !scrolled);
          final page = find.byType(OpenBandGlucose);
          if (scrolled) {
            final row = find.byKey(const ValueKey('glucose-messungen'));
            await ensureFullyInSafeViewport(page, row);
            expect(row.hitTestable(), findsOneWidget);
            expect(find.text('11'), findsOneWidget);
            await capture(name);
          } else {
            await expectInSafeViewport(find.text('Glukose'));
            await capture(name);
          }
          c.dispose();
        }

        Future<void> captureSource({
          required String name,
          required Brightness brightness,
          double scale = 1,
          bool excluded = false,
          bool scrolled = false,
        }) async {
          final r = await loadRepo();
          if (excluded) {
            await r.setGlucoseSourceIncluded(sourceKey, included: false);
          }
          final c = await mountHealth(
            repository: r,
            brightness: brightness,
            scale: scale,
          );
          await openGlucoseFromHealth();
          await openSource();
          await expectSourceClocks(included: !excluded, restoreTop: !scrolled);
          final page = find.byType(OpenBandGlucoseSource);
          if (scrolled) {
            final read = find.byKey(const ValueKey('glucose-lesen'));
            await ensureFullyInSafeViewport(page, read);
            expect(read.hitTestable(), findsOneWidget);
            await capture(name);
          } else {
            await capture(name);
          }
          c.dispose();
        }

        Future<void> captureHistory({
          required String name,
          required Brightness brightness,
          double scale = 1,
          bool scrolled = false,
        }) async {
          final r = await loadRepo();
          final c = await mountHealth(
            repository: r,
            brightness: brightness,
            scale: scale,
          );
          await openGlucoseFromHealth();
          await openHistory();
          await expectHistoryFixture(restoreTop: !scrolled);
          final page = find.byType(OpenBandGlucoseHistory);
          if (scrolled) {
            final note = find.byKey(const ValueKey('glucose-synthetic'));
            await ensureFullyInSafeViewport(page, note);
            expect(note.hitTestable(), findsOneWidget);
            await capture(name);
          } else {
            await capture(name);
          }
          c.dispose();
        }

        await captureMain(
          name: 'glucose-main-dark',
          brightness: Brightness.dark,
        );
        await captureSource(
          name: 'glucose-source-dark',
          brightness: Brightness.dark,
        );
        await captureHistory(
          name: 'glucose-history-dark',
          brightness: Brightness.dark,
        );
        await captureMain(
          name: 'glucose-main-excluded-dark',
          brightness: Brightness.dark,
          excluded: true,
        );
        await captureSource(
          name: 'glucose-source-excluded-dark',
          brightness: Brightness.dark,
          excluded: true,
        );

        // Empty stored + empty query is not access denied.
        repo = await loadRepo();
        repo.clearGlucoseReadings();
        controller = await mountHealth(repository: repo);
        await openGlucoseFromHealth();
        expect(find.text('Keine Werte gespeichert'), findsOneWidget);
        expect(find.text('Jetzt lesen'), findsOneWidget);
        expect(find.text('Kein Zugriff'), findsNothing);
        await capture('glucose-empty');
        repo.emptyGlucoseImport = true;
        await tester.tap(find.byKey(const ValueKey('glucose-lesen')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Keine Werte gelesen'), findsOneWidget);
        expect(find.text('Kein Zugriff'), findsNothing);
        await capture('glucose-empty-query');
        controller.dispose();

        repo = await loadRepo();
        repo.clearGlucoseReadings();
        controller = await mountHealth(
          repository: repo,
          brightness: Brightness.dark,
        );
        await openGlucoseFromHealth();
        expect(find.text('Keine Werte gespeichert'), findsOneWidget);
        await capture('glucose-empty-dark');
        controller.dispose();

        // Explicit read failure retains stored hero.
        repo = await loadRepo();
        repo.failGlucoseImport = true;
        repo.glucoseImportFailureStatus =
            HealthMeasurementImportStatus.readFailed;
        controller = await mountHealth(repository: repo);
        await openGlucoseFromHealth();
        await openSource();
        await tester.tap(find.byKey(const ValueKey('glucose-lesen')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Lesen fehlgeschlagen'), findsOneWidget);
        expect(find.text('15. Sep., 08:00'), findsOneWidget);
        await popGlucose();
        expect(find.text('Lesen fehlgeschlagen'), findsOneWidget);
        expect(find.text('5,2'), findsWidgets);
        await capture('glucose-failure');
        controller.dispose();

        repo = await loadRepo();
        repo.failGlucoseImport = true;
        repo.glucoseImportFailureStatus =
            HealthMeasurementImportStatus.readFailed;
        controller = await mountHealth(
          repository: repo,
          brightness: Brightness.dark,
        );
        await openGlucoseFromHealth();
        await openSource();
        await tester.tap(find.byKey(const ValueKey('glucose-lesen')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await popGlucose();
        expect(find.text('Lesen fehlgeschlagen'), findsOneWidget);
        expect(find.text('5,2'), findsWidgets);
        await capture('glucose-failure-dark');
        controller.dispose();

        // Initial store-read error and retry.
        repo = await loadRepo();
        repo.failGlucoseReads = true;
        controller = await mountHealth(repository: repo);
        await openGlucoseFromHealth();
        expect(find.text('Lesen fehlgeschlagen'), findsOneWidget);
        expect(find.text('5,2'), findsNothing);
        await capture('glucose-store-error');
        repo.failGlucoseReads = false;
        await tester.tap(find.widgetWithText(OBAction, 'Erneut'));
        await pumpUntil(
          () => find.text('5,2').evaluate().isNotEmpty,
          'Store-read retry did not restore glucose.',
        );
        expect(find.text('Lesen fehlgeschlagen'), findsNothing);
        await capture('glucose-store-error-retry');
        controller.dispose();

        repo = await loadRepo();
        repo.failGlucoseReads = true;
        controller = await mountHealth(
          repository: repo,
          brightness: Brightness.dark,
        );
        await openGlucoseFromHealth();
        expect(find.text('Lesen fehlgeschlagen'), findsOneWidget);
        expect(find.text('5,2'), findsNothing);
        await capture('glucose-store-error-dark');
        controller.dispose();

        // Import refreshFailed keeps stored snapshot (nullable result.snapshot).
        repo = await loadRepo();
        controller = await mountHealth(repository: repo);
        await openGlucoseFromHealth();
        await expectMainFixture(excluded: false);
        await openSource();
        repo.failGlucoseReads = true;
        await tester.tap(find.byKey(const ValueKey('glucose-lesen')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await popGlucose();
        expect(find.text('5,2'), findsWidgets);
        expect(find.text('Lesen fehlgeschlagen'), findsOneWidget);
        expect(find.text('Keine Werte gespeichert'), findsNothing);
        await capture('glucose-refresh-failed');
        controller.dispose();

        repo = await loadRepo();
        controller = await mountHealth(
          repository: repo,
          brightness: Brightness.dark,
        );
        await openGlucoseFromHealth();
        await openSource();
        repo.failGlucoseReads = true;
        await tester.tap(find.byKey(const ValueKey('glucose-lesen')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await popGlucose();
        expect(find.text('5,2'), findsWidgets);
        expect(find.text('Lesen fehlgeschlagen'), findsOneWidget);
        await capture('glucose-refresh-failed-dark');
        controller.dispose();

        // Partial import copy.
        repo = await loadRepo()
          ..partialGlucose = true;
        controller = await mountHealth(repository: repo);
        await openGlucoseFromHealth();
        expect(find.text('Teilweise lesbar'), findsOneWidget);
        expect(find.text('5,2'), findsWidgets);
        await capture('glucose-partial');
        controller.dispose();
        repo = await loadRepo()
          ..partialGlucose = true;
        controller = await mountHealth(
          repository: repo,
          brightness: Brightness.dark,
        );
        await openGlucoseFromHealth();
        expect(find.text('Teilweise lesbar'), findsOneWidget);
        await capture('glucose-partial-dark');
        controller.dispose();

        Future<void> captureInfo({
          required String name,
          required Brightness brightness,
          double scale = 1,
          bool scrolled = false,
        }) async {
          final r = await loadRepo();
          final c = await mountHealth(
            repository: r,
            brightness: brightness,
            scale: scale,
          );
          await openGlucoseFromHealth();
          await tester.tap(find.byTooltip('Glukosewerte'));
          await pumpSheet();
          expect(find.text('Glukosewerte'), findsWidgets);
          expect(
            find.text(
              'Messwerte aus Apple Health, getrennt nach Quelle. OpenBand misst Glukose nicht.',
            ),
            findsOneWidget,
          );
          if (scrolled) {
            final body = find.byKey(const ValueKey('journal-info-body'));
            await tester.drag(body, const Offset(0, -64));
            await tester.pump();
          }
          await capture(name);
          await tester.tap(find.byTooltip('Schließen'));
          await pumpSheet();
          expect(find.text('Glukosewerte'), findsNothing);
          c.dispose();
        }

        await captureInfo(name: 'glucose-info', brightness: Brightness.light);
        await captureInfo(
          name: 'glucose-info-dark',
          brightness: Brightness.dark,
        );
        await captureInfo(
          name: 'glucose-info-2x',
          brightness: Brightness.light,
          scale: 2,
          scrolled: true,
        );

        // Toggle write failure retains switch state until retry.
        repo = await loadRepo();
        repo.failGlucoseExclusionWrite = true;
        controller = await mountHealth(repository: repo);
        await openGlucoseFromHealth();
        await openSource();
        await toggleUse();
        expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
        expect(tester.widget<CupertinoSwitch>(useSwitch()).value, isTrue);
        expect((await repo.readGlucose()).selectedExcluded, isFalse);
        await capture('glucose-toggle-error');
        repo.failGlucoseExclusionWrite = false;
        await tester.tap(find.widgetWithText(OBAction, 'Erneut'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.widget<CupertinoSwitch>(useSwitch()).value, isFalse);
        controller.dispose();

        await captureMain(
          name: 'glucose-main-2x',
          brightness: Brightness.light,
          scale: 2,
        );
        await captureMain(
          name: 'glucose-main-2x-scrolled',
          brightness: Brightness.light,
          scale: 2,
          scrolled: true,
        );
        await captureMain(
          name: 'glucose-main-2x-dark',
          brightness: Brightness.dark,
          scale: 2,
        );
        await captureSource(
          name: 'glucose-source-2x',
          brightness: Brightness.light,
          scale: 2,
        );
        await captureSource(
          name: 'glucose-source-2x-scrolled',
          brightness: Brightness.light,
          scale: 2,
          scrolled: true,
        );
        await captureSource(
          name: 'glucose-source-2x-dark',
          brightness: Brightness.dark,
          scale: 2,
        );
        await captureHistory(
          name: 'glucose-history-2x',
          brightness: Brightness.light,
          scale: 2,
        );
        await captureHistory(
          name: 'glucose-history-2x-scrolled',
          brightness: Brightness.light,
          scale: 2,
          scrolled: true,
        );
      }

      Future<void> reviewMedications() async {
        final now = DateTime(2026, 9, 15, 9, 41);
        const day = SyntheticOpenBandRepository.medicationFixtureDay;

        Future<_MedicationReviewRepo> loadRepo() async {
          Future<Map> load(String name) async =>
              jsonDecode(
                    await rootBundle.loadString(
                      'docs/openband5/assets/fixtures/$name.json',
                    ),
                  )
                  as Map;
          final repo = _MedicationReviewRepo(
            await load('day-summary'),
            await load('sleep-detail'),
            activity: await load('additional-flows'),
            run: await load('run-detail'),
          );
          await repo.seedNutritionGoals();
          return repo;
        }

        Widget reviewHost({
          required Widget home,
          Brightness brightness = Brightness.light,
          double scale = 1,
        }) => MaterialApp(
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
          home: home,
        );

        Finder downScrollable(Finder ancestor) => find.descendant(
          of: ancestor,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        );

        Rect reviewSafeViewport({Finder? contentOf}) {
          final view = tester.view;
          final dpr = view.devicePixelRatio;
          final size = view.physicalSize / dpr;
          final pad = view.viewPadding;
          final screen = Rect.fromLTRB(
            pad.left / dpr,
            pad.top / dpr,
            size.width - pad.right / dpr,
            size.height - pad.bottom / dpr,
          );
          if (contentOf == null) return screen;
          final box = tester.getRect(downScrollable(contentOf).first);
          return Rect.fromLTRB(
            box.left < screen.left ? screen.left : box.left,
            box.top < screen.top ? screen.top : box.top,
            box.right > screen.right ? screen.right : box.right,
            box.bottom > screen.bottom ? screen.bottom : box.bottom,
          );
        }

        bool rectInSafeViewport(
          Rect box, {
          Finder? contentOf,
          double slop = 0.5,
        }) {
          final safe = reviewSafeViewport(contentOf: contentOf);
          return box.top >= safe.top - slop &&
              box.bottom <= safe.bottom + slop &&
              box.left >= safe.left - slop &&
              box.right <= safe.right + slop;
        }

        Future<void> revealIn(Finder ancestor, Finder target) async {
          final scrollable = downScrollable(ancestor).first;
          var scrolls = 0;
          var searchUp = true;
          while (target.evaluate().isEmpty ||
              target.hitTestable().evaluate().isEmpty) {
            if (scrolls >= 32) {
              throw FlutterError(
                'Control is not hit-testable after production scrolling.',
              );
            }
            if (target.evaluate().isEmpty) {
              final position = tester
                  .state<ScrollableState>(scrollable)
                  .position;
              final atMin = position.pixels <= position.minScrollExtent + 0.5;
              final atMax = position.pixels >= position.maxScrollExtent - 0.5;
              if (searchUp && atMin) searchUp = false;
              final dy = searchUp
                  ? (atMin ? 0.0 : 64.0)
                  : (atMax ? 0.0 : -64.0);
              if (dy == 0) {
                throw FlutterError(
                  'Control is not hit-testable after production scrolling.',
                );
              }
              await tester.drag(scrollable, Offset(0, dy));
              await tester.pump();
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
        }

        Future<void> ensureFullyInSafeViewport(
          Finder ancestor,
          Finder target,
        ) async {
          await revealIn(ancestor, target);
          final scrollable = downScrollable(ancestor).first;
          var extra = 0;
          while (!rectInSafeViewport(
            tester.getRect(target),
            contentOf: ancestor,
          )) {
            if (extra >= 32) {
              throw FlutterError(
                'Control is not fully within the safe viewport.',
              );
            }
            final box = tester.getRect(target);
            final safe = reviewSafeViewport(contentOf: ancestor);
            final overflowBottom = box.bottom - safe.bottom;
            final overflowTop = safe.top - box.top;
            if (extra == 0) {
              await Scrollable.ensureVisible(
                tester.element(target),
                alignment: overflowBottom >= overflowTop ? 1.0 : 0.0,
              );
              await tester.pump();
            } else {
              const minGesture = 64.0;
              final needed = overflowBottom > 0
                  ? -(overflowBottom + 8)
                  : overflowTop + 8;
              final dy = needed < 0
                  ? (needed > -minGesture ? -minGesture : needed)
                  : (needed < minGesture ? minGesture : needed);
              await tester.drag(scrollable, Offset(0, dy));
              await tester.pump();
            }
            extra++;
          }
          expect(target.hitTestable(), findsOneWidget);
        }

        Future<void> scrollListToMin(Finder ancestor) async {
          final scrollable = downScrollable(ancestor).first;
          var scrolls = 0;
          var pumps = 0;
          while (true) {
            final position = tester.state<ScrollableState>(scrollable).position;
            final min = position.minScrollExtent;
            final offset = position.pixels - min;
            final idle = !position.isScrollingNotifier.value;
            if (idle && offset.abs() <= 0.5) {
              expect(offset.abs(), lessThanOrEqualTo(0.5));
              return;
            }
            if (offset > 0.5) {
              if (++scrolls > 32) {
                throw FlutterError('ListView did not reach min scroll extent.');
              }
              await tester.drag(scrollable, const Offset(0, 64));
              await tester.pump();
              continue;
            }
            if (++pumps > 40) {
              throw FlutterError('ListView overscroll did not settle at min.');
            }
            await tester.pump(const Duration(milliseconds: 16));
          }
        }

        Future<void> pumpUntil(bool Function() ready, String message) async {
          await tester.pump();
          var waited = 0;
          while (!ready()) {
            if (++waited > 80) throw FlutterError(message);
            await tester.pump(const Duration(milliseconds: 16));
          }
          await reviewPumpPageTransitions(tester);
        }

        double keyboardInset() =>
            tester.view.viewInsets.bottom / tester.view.devicePixelRatio;

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

        Future<void> enterFocused(Finder field, String text) async {
          await tester.tap(field);
          await tester.pump();
          await tester.showKeyboard(field);
          await tester.pump();
          await waitKeyboardInset(open: true);
          await tester.enterText(field, text);
          await tester.pump();
          expect(tester.widget<TextField>(field).controller!.text, text);
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();
          await waitKeyboardInset(open: false);
        }

        Future<void> pumpAfterTap() async {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await reviewPumpPageTransitions(tester);
        }

        Future<_MedicationReviewRepo> mountMeds({
          Brightness brightness = Brightness.light,
          double scale = 1,
          _MedicationReviewRepo? repository,
          String? onDay,
          DateTime? clock,
        }) async {
          final repo = repository ?? await loadRepo();
          await tester.pumpWidget(
            reviewHost(
              brightness: brightness,
              scale: scale,
              home: OpenBandMedications(
                repository: repo,
                day: onDay ?? day,
                now: () => clock ?? now,
                synthetic: true,
              ),
            ),
          );
          await pumpUntil(
            () =>
                find
                    .byKey(const ValueKey('medication-main'))
                    .evaluate()
                    .isNotEmpty ||
                find
                    .text('Medikamente konnten nicht geladen werden.')
                    .evaluate()
                    .isNotEmpty,
            'Medications main did not load.',
          );
          return repo;
        }

        Future<void> popRoute() async {
          await tester.tap(find.byTooltip('Zurück'));
          await reviewPumpPageTransitions(tester);
          await tester.pump();
        }

        Future<void> tapVisible(Finder target, Finder ancestor) async {
          await ensureFullyInSafeViewport(ancestor, target);
          await tester.tap(target.hitTestable());
          await pumpAfterTap();
        }

        // Journal entry.
        var repo = await loadRepo();
        final journal = OpenBandController(
          repository: repo,
          initialDay: day,
          band: repo.band,
          now: () => now,
        );
        await journal.refresh();
        await tester.pumpWidget(
          reviewHost(
            home: Scaffold(
              body: SafeArea(
                child: OpenBandJournal(
                  controller: journal,
                  onEdit: (_) async {},
                  onNutrition: () async {},
                ),
              ),
            ),
          ),
        );
        await pumpUntil(
          () => find.text('Journal').evaluate().isNotEmpty,
          'Journal did not load.',
        );
        final journalPage = find.byType(OpenBandJournal);
        final journalEntry = find.byKey(const ValueKey('medication-journal'));
        await ensureFullyInSafeViewport(journalPage, journalEntry);
        expect(journalEntry.hitTestable(), findsOneWidget);
        expect(find.text('Medikamente'), findsWidgets);
        await capture('medications-journal-entry');
        await tester.tap(journalEntry.hitTestable());
        await pumpAfterTap();
        await pumpUntil(
          () => find
              .byKey(const ValueKey('medication-main'))
              .evaluate()
              .isNotEmpty,
          'Medications did not open from Journal.',
        );
        expect(find.text('Präparat A'), findsOneWidget);
        await capture('medications-journal');
        await popRoute();
        await pumpUntil(
          () => find.byType(OpenBandJournal).evaluate().isNotEmpty,
          'Journal route did not return.',
        );
        expect(find.byType(OpenBandJournal), findsOneWidget);
        expect(
          find.byKey(const ValueKey('medication-journal')),
          findsOneWidget,
        );
        await scrollListToMin(find.byType(OpenBandJournal));
        expect(find.text('Journal'), findsOneWidget);
        journal.dispose();

        repo = await loadRepo();
        final journalDark = OpenBandController(
          repository: repo,
          initialDay: day,
          band: repo.band,
          now: () => now,
        );
        await journalDark.refresh();
        await tester.pumpWidget(
          reviewHost(
            brightness: Brightness.dark,
            home: Scaffold(
              body: SafeArea(
                child: OpenBandJournal(
                  controller: journalDark,
                  onEdit: (_) async {},
                  onNutrition: () async {},
                ),
              ),
            ),
          ),
        );
        await pumpUntil(
          () => find.text('Journal').evaluate().isNotEmpty,
          'Journal dark did not load.',
        );
        final darkEntry = find.byKey(const ValueKey('medication-journal'));
        await ensureFullyInSafeViewport(
          find.byType(OpenBandJournal),
          darkEntry,
        );
        expect(darkEntry.hitTestable(), findsOneWidget);
        await capture('medications-journal-entry-dark');
        await tester.tap(darkEntry.hitTestable());
        await pumpAfterTap();
        await pumpUntil(
          () => find
              .byKey(const ValueKey('medication-main'))
              .evaluate()
              .isNotEmpty,
          'Medications dark did not open from Journal.',
        );
        await capture('medications-journal-dark');
        journalDark.dispose();

        Future<void> expectMainLoaded() async {
          final page = find.byKey(const ValueKey('medication-main'));
          expect(find.text('Medikamente'), findsWidgets);
          await ensureFullyInSafeViewport(page, find.text('Präparat A'));
          expect(find.text('Präparat A'), findsOneWidget);
          expect(find.text('Präparat B'), findsOneWidget);
          expect(find.textContaining('Offen'), findsOneWidget);
          expect(find.textContaining('Später'), findsOneWidget);
          await ensureFullyInSafeViewport(page, find.text('Verlauf'));
          await ensureFullyInSafeViewport(
            page,
            find.text('Medikament hinzufügen'),
          );
          await ensureFullyInSafeViewport(
            page,
            find.text('Synthetische Daten'),
          );
        }

        repo = await mountMeds();
        await expectMainLoaded();
        await scrollListToMin(find.byKey(const ValueKey('medication-main')));
        await capture('medications-main');

        await mountMeds(brightness: Brightness.dark);
        await expectMainLoaded();
        await scrollListToMin(find.byKey(const ValueKey('medication-main')));
        await capture('medications-main-dark');

        // Record unanswered -> taken actual time -> save.
        repo = await mountMeds();
        await tapVisible(
          find.text('Präparat A'),
          find.byKey(const ValueKey('medication-main')),
        );
        expect(find.byKey(const ValueKey('medication-record')), findsOneWidget);
        expect(find.text('Einnahme'), findsOneWidget);
        expect(find.text('Genommen'), findsOneWidget);
        expect(find.text('Ausgelassen'), findsOneWidget);
        expect(find.text('Eintrag entfernen'), findsNothing);
        expect(
          tester
              .widget<OBAction>(find.widgetWithText(OBAction, 'Speichern'))
              .onPressed,
          isNull,
        );
        await capture('medications-unanswered');
        await tester.tap(find.text('Genommen'));
        await pumpAfterTap();
        expect(find.text('09:41'), findsOneWidget);
        await capture('medications-taken');
        await tester.tap(find.widgetWithText(OBAction, 'Speichern'));
        await pumpAfterTap();
        expect(find.text('Einnahme'), findsNothing);
        expect(find.textContaining('Genommen 09:41'), findsOneWidget);
        await capture('medications-saved');

        await tapVisible(
          find.text('Präparat A'),
          find.byKey(const ValueKey('medication-main')),
        );
        expect(find.text('Eintrag entfernen'), findsOneWidget);
        await tester.tap(find.text('Ausgelassen'));
        await pumpAfterTap();
        await tester.tap(find.widgetWithText(OBAction, 'Speichern'));
        await pumpAfterTap();
        expect(find.textContaining('Ausgelassen'), findsOneWidget);
        await capture('medications-skipped');

        await tapVisible(
          find.text('Präparat A'),
          find.byKey(const ValueKey('medication-main')),
        );
        await tester.tap(find.text('Eintrag entfernen'));
        await pumpAfterTap();
        expect(find.textContaining('Offen'), findsOneWidget);

        await mountMeds(brightness: Brightness.dark);
        await tapVisible(
          find.text('Präparat A'),
          find.byKey(const ValueKey('medication-main')),
        );
        await capture('medications-unanswered-dark');
        await tester.tap(find.text('Genommen'));
        await pumpAfterTap();
        expect(find.text('09:41'), findsOneWidget);
        await capture('medications-taken-dark');

        // History + older paging.
        repo = await mountMeds();
        await tapVisible(
          find.text('Verlauf'),
          find.byKey(const ValueKey('medication-main')),
        );
        expect(
          find.byKey(const ValueKey('medication-history')),
          findsOneWidget,
        );
        expect(find.textContaining('Genommen'), findsWidgets);
        expect(find.textContaining('Kein Eintrag'), findsWidgets);
        expect(find.text('Ältere Einträge'), findsOneWidget);
        await capture('medications-history');
        repo.failHistoryAfterFirst = true;
        await tester.tap(find.text('Ältere Einträge'));
        await pumpAfterTap();
        expect(
          find.text('Medikamente konnten nicht geladen werden.'),
          findsOneWidget,
        );
        await capture('medications-history-older');
        repo.failHistoryAfterFirst = false;
        await tester.tap(find.text('Erneut versuchen'));
        await pumpAfterTap();
        expect(find.text('Präparat A'), findsWidgets);

        await mountMeds(brightness: Brightness.dark);
        await tapVisible(
          find.text('Verlauf'),
          find.byKey(const ValueKey('medication-main')),
        );
        await capture('medications-history-dark');

        repo = await loadRepo();
        repo.transformHistory = (hist) => MedicationHistory(
          fromDay: hist.fromDay,
          toDay: hist.toDay,
          entries: const [
            MedicationDayEntry(
              key: 'orphan-old',
              date: '2026-09-14',
              slotMin: 8 * 60,
              status: MedicationSlotStatus.taken,
              takenAt: null,
              snapshotLabel: null,
              snapshotDoseValue: null,
              snapshotDoseUnit: null,
              currentName: 'Präparat A',
              orphan: true,
            ),
          ],
        );
        await mountMeds(repository: repo);
        await tapVisible(
          find.text('Verlauf'),
          find.byKey(const ValueKey('medication-main')),
        );
        expect(find.textContaining('aktueller Name'), findsOneWidget);
        expect(find.text('1 Tablette'), findsNothing);
        await capture('medications-legacy');
        await mountMeds(repository: repo, brightness: Brightness.dark);
        await tapVisible(
          find.text('Verlauf'),
          find.byKey(const ValueKey('medication-main')),
        );
        expect(find.textContaining('aktueller Name'), findsOneWidget);
        await capture('medications-legacy-dark');

        repo = await loadRepo();
        repo.transformDay = (snap) => MedicationDay(
          day: snap.day,
          entries: [
            MedicationDayEntry(
              key: 'legacy',
              date: '2026-08-20',
              slotMin: 8 * 60,
              status: MedicationSlotStatus.taken,
              takenAt: DateTime.utc(2026, 8, 20, 7, 35),
              snapshotLabel: null,
              snapshotDoseValue: null,
              snapshotDoseUnit: null,
              orphan: true,
            ),
          ],
        );
        await mountMeds(repository: repo);
        await tapVisible(
          find.text('08:00'),
          find.byKey(const ValueKey('medication-main')),
        );
        expect(find.byKey(const ValueKey('medication-record')), findsOneWidget);
        expect(find.text('Name und Menge nicht gespeichert'), findsOneWidget);
        expect(find.text('Zeitzone nicht gespeichert'), findsOneWidget);
        expect(find.text('Eintrag entfernen'), findsOneWidget);
        expect(find.text('Unbekannt'), findsNothing);
        await capture('medications-legacy-record');
        await mountMeds(repository: repo, brightness: Brightness.dark);
        await tapVisible(
          find.text('08:00'),
          find.byKey(const ValueKey('medication-main')),
        );
        expect(find.text('Name und Menge nicht gespeichert'), findsOneWidget);
        expect(find.text('Zeitzone nicht gespeichert'), findsOneWidget);
        await capture('medications-legacy-record-dark');

        // Plans add / edit / end / restart / time weekdays.
        repo = await mountMeds();
        await tapVisible(
          find.text('Pläne verwalten'),
          find.byKey(const ValueKey('medication-main')),
        );
        expect(find.byKey(const ValueKey('medication-plans')), findsOneWidget);
        expect(find.text('Präparat A'), findsWidgets);
        await capture('medications-plans');
        await popRoute();
        await mountMeds(brightness: Brightness.dark);
        await tapVisible(
          find.text('Pläne verwalten'),
          find.byKey(const ValueKey('medication-main')),
        );
        expect(find.byKey(const ValueKey('medication-plans')), findsOneWidget);
        await capture('medications-plans-dark');
        await popRoute();
        await mountMeds();
        await tapVisible(
          find.text('Medikament hinzufügen'),
          find.byKey(const ValueKey('medication-main')),
        );
        expect(find.byKey(const ValueKey('medication-editor')), findsOneWidget);
        await capture('medications-editor');
        await popRoute();
        await mountMeds(brightness: Brightness.dark);
        await tapVisible(
          find.text('Medikament hinzufügen'),
          find.byKey(const ValueKey('medication-main')),
        );
        expect(find.byKey(const ValueKey('medication-editor')), findsOneWidget);
        await capture('medications-editor-dark');
        repo = await mountMeds();
        await tapVisible(
          find.text('Medikament hinzufügen'),
          find.byKey(const ValueKey('medication-main')),
        );
        final name = find.byKey(const ValueKey('medication-name'));
        await ensureFullyInSafeViewport(
          find.byKey(const ValueKey('medication-editor')),
          name,
        );
        await enterFocused(name, 'Zink');
        await tester.tap(find.widgetWithText(OBAction, 'Speichern'));
        await pumpAfterTap();
        await pumpUntil(
          () => find
              .byKey(const ValueKey('medication-main'))
              .evaluate()
              .isNotEmpty,
          'Create did not return to medications main.',
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('medication-main')),
            matching: find.text('Zink'),
          ),
          findsNothing,
        );
        final created = [
          for (final p in await repo.readMedicationPlans(activeOnly: true))
            if (p.name == 'Zink') p,
        ];
        expect(created, isNotEmpty);
        expect(created.single.schedule, isEmpty);
        await tapVisible(
          find.text('Pläne verwalten'),
          find.byKey(const ValueKey('medication-main')),
        );
        await tapVisible(
          find.text('Zink'),
          find.byKey(const ValueKey('medication-plans')),
        );
        expect(find.text('Plan bearbeiten'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('medication-name')))
              .controller!
              .text,
          'Zink',
        );
        await capture('medications-edit-plan');
        await popRoute();
        await tapVisible(
          find.text('Zink'),
          find.byKey(const ValueKey('medication-plans')),
        );
        await tester.tap(find.text('Plan beenden'));
        await pumpAfterTap();
        await tapVisible(
          find.text('Beendete Pläne'),
          find.byKey(const ValueKey('medication-plans')),
        );
        expect(find.byKey(const ValueKey('medication-ended')), findsOneWidget);
        expect(find.text('Zink'), findsOneWidget);
        await capture('medications-ended');
        await tester.tap(find.text('Zink'));
        await pumpAfterTap();
        expect(find.text('Plan fortsetzen'), findsWidgets);
        await capture('medications-restart');
        await tester.tap(find.widgetWithText(OBAction, 'Plan fortsetzen'));
        await pumpAfterTap();

        Future<MedicationPlan> planA() async {
          return (await repo.readMedicationPlans(
            activeOnly: true,
          )).firstWhere((p) => p.name == 'Präparat A');
        }

        Future<void> openPlanATime() async {
          await tapVisible(
            find.text('Pläne verwalten'),
            find.byKey(const ValueKey('medication-main')),
          );
          await tapVisible(
            find.text('Präparat A'),
            find.byKey(const ValueKey('medication-plans')),
          );
          await tester.tap(find.text('08:00'));
          await pumpAfterTap();
          expect(find.byKey(const ValueKey('medication-time')), findsOneWidget);
        }

        Finder mondaySwitch() => find.descendant(
          of: find.ancestor(
            of: find.text('Montag'),
            matching: find.byType(OBSettingsToggleRow),
          ),
          matching: find.byType(CupertinoSwitch),
        );

        repo = await mountMeds();
        final originalA = await planA();
        expect(originalA.schedule.single.minuteOfDay, 8 * 60);
        expect(originalA.schedule.single.weekdays, isEmpty);
        await openPlanATime();
        expect(find.text('Montag'), findsOneWidget);
        await capture('medications-time');
        final timePage = find.byKey(const ValueKey('medication-time'));
        await ensureFullyInSafeViewport(timePage, find.text('Montag'));
        expect(tester.widget<CupertinoSwitch>(mondaySwitch()).value, isTrue);
        await tester.tap(mondaySwitch().hitTestable());
        await pumpAfterTap();
        expect(tester.widget<CupertinoSwitch>(mondaySwitch()).value, isFalse);
        await popRoute();
        expect(find.byKey(const ValueKey('medication-editor')), findsOneWidget);
        expect(find.text('08:00'), findsOneWidget);
        expect((await planA()).schedule.single.weekdays, isEmpty);
        await tester.tap(find.text('08:00'));
        await pumpAfterTap();
        await ensureFullyInSafeViewport(
          find.byKey(const ValueKey('medication-time')),
          find.text('Montag'),
        );
        expect(tester.widget<CupertinoSwitch>(mondaySwitch()).value, isTrue);
        await tester.tap(mondaySwitch().hitTestable());
        await pumpAfterTap();
        await tester.tap(find.widgetWithText(OBAction, 'Speichern'));
        await pumpAfterTap();
        expect(find.byKey(const ValueKey('medication-editor')), findsOneWidget);
        expect((await planA()).schedule.single.weekdays, isEmpty);
        expect((await planA()).schedule.single.minuteOfDay, 8 * 60);

        await mountMeds(brightness: Brightness.dark);
        await openPlanATime();
        await capture('medications-time-dark');
        await tester.tap(find.widgetWithText(OBAction, 'Speichern'));
        await pumpAfterTap();
        expect(find.byKey(const ValueKey('medication-editor')), findsOneWidget);
        expect((await planA()).schedule.single.weekdays, isEmpty);

        // Empty / no-slot / read error.
        repo = await loadRepo();
        repo.transformPlans = (_) => const [];
        repo.transformDay = (snap) => MedicationDay(day: snap.day);
        await mountMeds(repository: repo);
        expect(find.text('Keine Medikamente'), findsOneWidget);
        expect(find.text('Keine Einnahme geplant'), findsNothing);
        await capture('medications-empty');
        await mountMeds(repository: repo, brightness: Brightness.dark);
        expect(find.text('Keine Medikamente'), findsOneWidget);
        await capture('medications-empty-dark');

        repo = await loadRepo();
        repo.transformDay = (snap) => MedicationDay(day: snap.day);
        await mountMeds(repository: repo);
        expect(find.text('Keine Einnahme geplant'), findsOneWidget);
        expect(find.text('Keine Medikamente'), findsNothing);
        await capture('medications-no-slot');

        repo = await loadRepo();
        repo.failMedicationRead = true;
        await mountMeds(repository: repo);
        expect(
          find.text('Medikamente konnten nicht geladen werden.'),
          findsOneWidget,
        );
        expect(find.text('Keine Medikamente'), findsNothing);
        await capture('medications-error');
        repo.failMedicationRead = false;
        await tester.tap(find.text('Erneut versuchen'));
        await pumpAfterTap();
        expect(find.text('Präparat A'), findsOneWidget);

        // Save failure keeps draft.
        repo = await loadRepo();
        repo.failMedicationWrite = true;
        await mountMeds(repository: repo);
        await tapVisible(
          find.text('Präparat A'),
          find.byKey(const ValueKey('medication-main')),
        );
        await tester.tap(find.text('Genommen'));
        await pumpAfterTap();
        final note = find.byKey(const ValueKey('medication-note'));
        await ensureFullyInSafeViewport(
          find.byKey(const ValueKey('medication-record')),
          note,
        );
        await enterFocused(note, 'Notiz');
        await tester.tap(find.widgetWithText(OBAction, 'Speichern'));
        await pumpAfterTap();
        expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
        expect(tester.widget<TextField>(note).controller!.text, 'Notiz');
        expect(find.text('Einnahme'), findsOneWidget);
        await capture('medications-save-error');
        await mountMeds(repository: repo, brightness: Brightness.dark);
        await tapVisible(
          find.text('Präparat A'),
          find.byKey(const ValueKey('medication-main')),
        );
        await tester.tap(find.text('Genommen'));
        await pumpAfterTap();
        await tester.tap(find.widgetWithText(OBAction, 'Speichern'));
        await pumpAfterTap();
        expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
        await capture('medications-save-error-dark');

        // Reminder failure retries refresh only.
        repo = await loadRepo();
        repo.failMedicationReminders = true;
        await mountMeds(repository: repo);
        await tapVisible(
          find.text('Präparat A'),
          find.byKey(const ValueKey('medication-main')),
        );
        await tester.tap(find.text('Genommen'));
        await pumpAfterTap();
        final savesBefore = repo.entrySaves;
        final refreshesBefore = repo.reminderRefreshes;
        await tester.tap(find.widgetWithText(OBAction, 'Speichern'));
        await pumpAfterTap();
        expect(repo.entrySaves, savesBefore + 1);
        expect(repo.reminderRefreshes, greaterThan(refreshesBefore));
        expect(
          find.text('Gespeichert · Erinnerungen nicht aktualisiert'),
          findsOneWidget,
        );
        await capture('medications-reminder-error');
        repo.failMedicationReminders = false;
        final refreshesAfterSave = repo.reminderRefreshes;
        await tester.tap(find.text('Erneut versuchen'));
        await pumpAfterTap();
        expect(repo.entrySaves, savesBefore + 1);
        expect(repo.reminderRefreshes, greaterThan(refreshesAfterSave));
        expect(
          find.text('Gespeichert · Erinnerungen nicht aktualisiert'),
          findsNothing,
        );

        repo = await loadRepo();
        repo.transformDay = (snap) => MedicationDay(
          day: snap.day,
          entries: snap.entries,
          unreadableCount: 2,
        );
        await mountMeds(repository: repo);
        expect(find.text('Nicht alle Einträge lesbar'), findsOneWidget);
        expect(find.text('Präparat A'), findsOneWidget);
        await capture('medications-partial');
        await mountMeds(repository: repo, brightness: Brightness.dark);
        expect(find.text('Nicht alle Einträge lesbar'), findsOneWidget);
        await capture('medications-partial-dark');

        repo = await loadRepo();
        await repo.saveMedicationPlan(
          MedicationPlanDraft(
            create: true,
            name: 'Präparat DST',
            doseValue: 1,
            doseUnit: 'Tablette',
            schedule: const [MedicationScheduleSlot(minuteOfDay: 2 * 60 + 30)],
          ),
          now: DateTime(2026, 10, 1, 8),
        );
        const dstDay = '2026-10-25';
        final dstNow = DateTime(2026, 10, 25, 9, 41);
        await mountMeds(repository: repo, onDay: dstDay, clock: dstNow);
        expect(find.text('02:30'), findsOneWidget);
        expect(find.text('Uhrzeit nicht eindeutig'), findsOneWidget);
        await capture('medications-dst');
        await mountMeds(
          repository: repo,
          brightness: Brightness.dark,
          onDay: dstDay,
          clock: dstNow,
        );
        expect(find.text('02:30'), findsOneWidget);
        expect(find.text('Uhrzeit nicht eindeutig'), findsOneWidget);
        await capture('medications-dst-dark');

        Future<void> captureScaled({
          required String name,
          required Future<void> Function() open,
          Brightness brightness = Brightness.light,
        }) async {
          await mountMeds(brightness: brightness, scale: 2);
          await open();
          await capture(name);
        }

        await captureScaled(
          name: 'medications-main-2x',
          open: () async {
            final page = find.byKey(const ValueKey('medication-main'));
            await ensureFullyInSafeViewport(page, find.text('Präparat A'));
            await ensureFullyInSafeViewport(page, find.text('Verlauf'));
            await scrollListToMin(page);
          },
        );
        Future<void> openTakenRecord() async {
          await tapVisible(
            find.text('Präparat A'),
            find.byKey(const ValueKey('medication-main')),
          );
          expect(find.text('Einnahme'), findsOneWidget);
          await tester.tap(find.text('Genommen'));
          await pumpAfterTap();
          final record = find.byKey(const ValueKey('medication-record'));
          await ensureFullyInSafeViewport(record, find.text('09:41'));
          expect(find.text('09:41'), findsOneWidget);
          expect(find.textContaining('2026'), findsWidgets);
        }

        await captureScaled(
          name: 'medications-record-2x',
          open: openTakenRecord,
        );
        await ensureFullyInSafeViewport(
          find.byKey(const ValueKey('medication-record')),
          find.widgetWithText(OBAction, 'Speichern'),
        );
        await capture('medications-record-2x-save');
        await tester.tap(
          find.widgetWithText(OBAction, 'Speichern').hitTestable(),
        );
        await pumpAfterTap();
        expect(find.byKey(const ValueKey('medication-main')), findsOneWidget);
        expect(find.textContaining('Genommen 09:41'), findsOneWidget);

        await captureScaled(
          name: 'medications-record-2x-dark',
          brightness: Brightness.dark,
          open: openTakenRecord,
        );
        await ensureFullyInSafeViewport(
          find.byKey(const ValueKey('medication-record')),
          find.widgetWithText(OBAction, 'Speichern'),
        );
        await tester.tap(
          find.widgetWithText(OBAction, 'Speichern').hitTestable(),
        );
        await pumpAfterTap();
        expect(find.textContaining('Genommen 09:41'), findsOneWidget);
        await captureScaled(
          name: 'medications-main-2x-dark',
          brightness: Brightness.dark,
          open: () async {
            final page = find.byKey(const ValueKey('medication-main'));
            await ensureFullyInSafeViewport(page, find.text('Präparat A'));
            await scrollListToMin(page);
          },
        );
        await captureScaled(
          name: 'medications-editor-2x',
          open: () async {
            await tapVisible(
              find.text('Medikament hinzufügen'),
              find.byKey(const ValueKey('medication-main')),
            );
            expect(
              find.byKey(const ValueKey('medication-editor')),
              findsOneWidget,
            );
            expect(
              tester
                  .widget<TextField>(
                    find.byKey(const ValueKey('medication-name')),
                  )
                  .controller!
                  .text,
              isEmpty,
            );
          },
        );
        await ensureFullyInSafeViewport(
          find.byKey(const ValueKey('medication-editor')),
          find.widgetWithText(OBAction, 'Speichern'),
        );
        await capture('medications-editor-2x-save');
        await tester.tap(
          find.widgetWithText(OBAction, 'Speichern').hitTestable(),
        );
        await pumpAfterTap();
        expect(find.byKey(const ValueKey('medication-editor')), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('medication-name')))
              .controller!
              .text,
          isEmpty,
        );
        expect(find.byKey(const ValueKey('medication-main')), findsNothing);
        await captureScaled(
          name: 'medications-time-2x',
          open: () async {
            await tapVisible(
              find.text('Pläne verwalten'),
              find.byKey(const ValueKey('medication-main')),
            );
            await tapVisible(
              find.text('Präparat A'),
              find.byKey(const ValueKey('medication-plans')),
            );
            await tester.tap(find.text('08:00'));
            await pumpAfterTap();
            expect(
              find.byKey(const ValueKey('medication-time')),
              findsOneWidget,
            );
            final time = find.byKey(const ValueKey('medication-time'));
            await ensureFullyInSafeViewport(time, find.text('Montag'));
            await ensureFullyInSafeViewport(
              time,
              find.widgetWithText(OBAction, 'Speichern'),
            );
            await scrollListToMin(time);
          },
        );
        await ensureFullyInSafeViewport(
          find.byKey(const ValueKey('medication-time')),
          find.widgetWithText(OBAction, 'Speichern'),
        );
        await tester.tap(
          find.widgetWithText(OBAction, 'Speichern').hitTestable(),
        );
        await pumpAfterTap();
        expect(find.byKey(const ValueKey('medication-editor')), findsOneWidget);
      }

      Future<void> reviewCycle() async {
        final now = DateTime(2026, 9, 15, 9, 41);
        const day = SyntheticOpenBandRepository.cycleFixtureDay;
        const longNote =
            'Sehr lange Notiz über Krämpfe, Müdigkeit, Blähungen und den restlichen Tag, damit Tastatur und 2×-Layout wirklich scrollen müssen.';

        Future<_CycleReviewRepo> loadRepo() async {
          Future<Map> load(String name) async =>
              jsonDecode(
                    await rootBundle.loadString(
                      'docs/openband5/assets/fixtures/$name.json',
                    ),
                  )
                  as Map;
          final repo = _CycleReviewRepo(
            await load('day-summary'),
            await load('sleep-detail'),
            activity: await load('additional-flows'),
            run: await load('run-detail'),
          );
          await repo.seedNutritionGoals();
          return repo;
        }

        Widget reviewHost({
          required Widget home,
          Brightness brightness = Brightness.light,
          double scale = 1,
        }) => MaterialApp(
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
          home: home,
        );

        Finder downScrollable(Finder ancestor) => find.descendant(
          of: ancestor,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        );

        Rect reviewSafeViewport({Finder? contentOf}) {
          final view = tester.view;
          final dpr = view.devicePixelRatio;
          final size = view.physicalSize / dpr;
          final pad = view.viewPadding;
          final screen = Rect.fromLTRB(
            pad.left / dpr,
            pad.top / dpr,
            size.width - pad.right / dpr,
            size.height - pad.bottom / dpr,
          );
          if (contentOf == null) return screen;
          final box = tester.getRect(downScrollable(contentOf).first);
          return Rect.fromLTRB(
            box.left < screen.left ? screen.left : box.left,
            box.top < screen.top ? screen.top : box.top,
            box.right > screen.right ? screen.right : box.right,
            box.bottom > screen.bottom ? screen.bottom : box.bottom,
          );
        }

        bool rectInSafeViewport(
          Rect box, {
          Finder? contentOf,
          double slop = 0.5,
        }) {
          final safe = reviewSafeViewport(contentOf: contentOf);
          return box.top >= safe.top - slop &&
              box.bottom <= safe.bottom + slop &&
              box.left >= safe.left - slop &&
              box.right <= safe.right + slop;
        }

        Future<void> revealIn(Finder ancestor, Finder target) async {
          final scrollable = downScrollable(ancestor).first;
          var scrolls = 0;
          var searchUp = true;
          while (target.evaluate().isEmpty ||
              target.hitTestable().evaluate().isEmpty) {
            if (scrolls >= 32) {
              throw FlutterError(
                'Control is not hit-testable after production scrolling.',
              );
            }
            if (target.evaluate().isEmpty) {
              final position = tester
                  .state<ScrollableState>(scrollable)
                  .position;
              final atMin = position.pixels <= position.minScrollExtent + 0.5;
              final atMax = position.pixels >= position.maxScrollExtent - 0.5;
              if (searchUp && atMin) searchUp = false;
              final dy = searchUp
                  ? (atMin ? 0.0 : 64.0)
                  : (atMax ? 0.0 : -64.0);
              if (dy == 0) {
                throw FlutterError(
                  'Control is not hit-testable after production scrolling.',
                );
              }
              await tester.drag(scrollable, Offset(0, dy));
              await tester.pump();
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
        }

        Future<void> ensureFullyInSafeViewport(
          Finder ancestor,
          Finder target,
        ) async {
          await revealIn(ancestor, target);
          final scrollable = downScrollable(ancestor).first;
          var extra = 0;
          while (!rectInSafeViewport(
            tester.getRect(target),
            contentOf: ancestor,
          )) {
            if (extra >= 32) {
              throw FlutterError(
                'Control is not fully within the safe viewport.',
              );
            }
            final box = tester.getRect(target);
            final safe = reviewSafeViewport(contentOf: ancestor);
            final overflowBottom = box.bottom - safe.bottom;
            final overflowTop = safe.top - box.top;
            if (extra == 0) {
              await Scrollable.ensureVisible(
                tester.element(target),
                alignment: overflowBottom >= overflowTop ? 1.0 : 0.0,
              );
              await tester.pump();
            } else {
              const minGesture = 64.0;
              final needed = overflowBottom > 0
                  ? -(overflowBottom + 8)
                  : overflowTop + 8;
              final dy = needed < 0
                  ? (needed > -minGesture ? -minGesture : needed)
                  : (needed < minGesture ? minGesture : needed);
              await tester.drag(scrollable, Offset(0, dy));
              await tester.pump();
            }
            extra++;
          }
          expect(target.hitTestable(), findsOneWidget);
        }

        Future<void> scrollListToMin(Finder ancestor) async {
          final scrollable = downScrollable(ancestor).first;
          var scrolls = 0;
          var pumps = 0;
          while (true) {
            final position = tester.state<ScrollableState>(scrollable).position;
            final min = position.minScrollExtent;
            final offset = position.pixels - min;
            final idle = !position.isScrollingNotifier.value;
            if (idle && offset.abs() <= 0.5) {
              expect(offset.abs(), lessThanOrEqualTo(0.5));
              return;
            }
            if (offset > 0.5) {
              if (++scrolls > 32) {
                throw FlutterError('ListView did not reach min scroll extent.');
              }
              await tester.drag(scrollable, const Offset(0, 64));
              await tester.pump();
              continue;
            }
            if (++pumps > 40) {
              throw FlutterError('ListView overscroll did not settle at min.');
            }
            await tester.pump(const Duration(milliseconds: 16));
          }
        }

        Future<void> pumpUntil(bool Function() ready, String message) async {
          await tester.pump();
          var waited = 0;
          while (!ready()) {
            if (++waited > 80) throw FlutterError(message);
            await tester.pump(const Duration(milliseconds: 16));
          }
          await reviewPumpPageTransitions(tester);
        }

        double keyboardInset() =>
            tester.view.viewInsets.bottom / tester.view.devicePixelRatio;

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

        Future<void> dismissCycleNote(Finder page) async {
          final listRect = tester.getRect(downScrollable(page).first);
          final safe = reviewSafeViewport(contentOf: page);
          final keyboardTop =
              tester.view.physicalSize.height / tester.view.devicePixelRatio -
              keyboardInset();
          final left = listRect.left < safe.left ? safe.left : listRect.left;
          final top = listRect.top < safe.top ? safe.top : listRect.top;
          final right = listRect.right > safe.right
              ? safe.right
              : listRect.right;
          var bottom = listRect.bottom;
          if (bottom > safe.bottom) bottom = safe.bottom;
          if (bottom > keyboardTop) bottom = keyboardTop;
          final visible = Rect.fromLTRB(left, top, right, bottom);
          expect(visible.width, greaterThan(16));
          expect(visible.height, greaterThan(8));
          final point = Offset(listRect.left + 4, visible.center.dy);
          final field = tester.getRect(
            find.byKey(const ValueKey('cycle-note')),
          );
          expect(point.dx, greaterThanOrEqualTo(listRect.left));
          expect(point.dx, lessThan(listRect.left + 16));
          expect(listRect.contains(point), isTrue);
          expect(visible.contains(point), isTrue);
          expect(field.contains(point), isFalse);
          expect(point.dy, lessThan(keyboardTop));
          await tester.tapAt(point);
          await tester.pump();
          await waitKeyboardInset(open: false);
        }

        Future<void> pumpAfterTap() async {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await reviewPumpPageTransitions(tester);
        }

        Future<void> popRoute() async {
          await tester.tap(find.byTooltip('Zurück'));
          await reviewPumpPageTransitions(tester);
          await tester.pump();
        }

        Future<void> tapVisible(Finder target, Finder ancestor) async {
          await ensureFullyInSafeViewport(ancestor, target);
          await tester.tap(target.hitTestable());
          await pumpAfterTap();
        }

        Finder undoNoticeAction(String label) => find.descendant(
          of: find.byType(SnackBar),
          matching: find.widgetWithText(TextButton, label),
        );

        Future<void> expectUndoNotice(String message, String action) async {
          expect(find.byType(SnackBar), findsOneWidget);
          expect(find.byType(SnackBarAction), findsNothing);
          expect(
            find.descendant(
              of: find.byType(SnackBar),
              matching: find.text(message),
            ),
            findsOneWidget,
          );
          expect(undoNoticeAction(action), findsOneWidget);
        }

        Future<void> tapUndoNotice(String label) async {
          await tester.tap(undoNoticeAction(label).hitTestable());
          await pumpAfterTap();
        }

        Finder toggleSwitch(String label) => find.descendant(
          of: find.ancestor(
            of: find.text(label),
            matching: find.byType(OBSettingsToggleRow),
          ),
          matching: find.byType(CupertinoSwitch),
        );

        Future<_CycleReviewRepo> mountCycle({
          Brightness brightness = Brightness.light,
          double scale = 1,
          _CycleReviewRepo? repository,
          String? onDay,
          DateTime? clock,
          bool settingsOnly = false,
        }) async {
          final repo = repository ?? await loadRepo();
          await tester.pumpWidget(
            reviewHost(
              brightness: brightness,
              scale: scale,
              home: OpenBandCycle(
                repository: repo,
                day: onDay ?? day,
                now: () => clock ?? now,
                synthetic: true,
                settingsOnly: settingsOnly,
              ),
            ),
          );
          final key = settingsOnly ? 'cycle-settings' : 'cycle-overview';
          await pumpUntil(
            () =>
                find.byKey(ValueKey(key)).evaluate().isNotEmpty ||
                find.text('Daten nicht geladen').evaluate().isNotEmpty,
            'Cycle ${settingsOnly ? 'settings' : 'main'} did not load.',
          );
          return repo;
        }

        Future<OpenBandController> mountJournal({
          required _CycleReviewRepo repository,
          Brightness brightness = Brightness.light,
          double scale = 1,
          String? onDay,
        }) async {
          final journal = OpenBandController(
            repository: repository,
            initialDay: onDay ?? day,
            band: repository.band,
            now: () => now,
          );
          await journal.refresh();
          await tester.pumpWidget(
            reviewHost(
              brightness: brightness,
              scale: scale,
              home: Scaffold(
                body: SafeArea(
                  child: OpenBandJournal(
                    controller: journal,
                    onEdit: (_) async {},
                    onNutrition: () async {},
                  ),
                ),
              ),
            ),
          );
          await pumpUntil(
            () => find.text('Journal').evaluate().isNotEmpty,
            'Journal did not load.',
          );
          return journal;
        }

        Future<void> expectMainFixture() async {
          final page = find.byKey(const ValueKey('cycle-overview'));
          expect(find.text('Zyklus'), findsWidgets);
          expect(find.text('Tag 23'), findsOneWidget);
          expect(find.text('Beginn · 24. August'), findsOneWidget);
          expect(find.text('Nächster Beginn · geschätzt'), findsOneWidget);
          expect(find.text('17.–25. Sept.'), findsOneWidget);
          expect(find.text('3 bisherige Abstände'), findsOneWidget);
          expect(find.text('Beginn eintragen'), findsOneWidget);
          await ensureFullyInSafeViewport(page, find.text('Messwerte'));
          await ensureFullyInSafeViewport(page, find.text('Verlauf'));
          await ensureFullyInSafeViewport(page, find.text('Einstellungen'));
          expect(
            tester
                .getTopLeft(
                  find.descendant(of: page, matching: find.text('Messwerte')),
                )
                .dy,
            lessThan(
              tester
                  .getTopLeft(
                    find.descendant(of: page, matching: find.text('Verlauf')),
                  )
                  .dy,
            ),
          );
          await ensureFullyInSafeViewport(
            page,
            find.text('Synthetische Daten'),
          );
        }

        Finder cycleChoiceSheet() =>
            find.byWidgetPredicate((widget) => widget is OBSettingsChoiceSheet);

        Future<void> expectSituationSelected(String label) async {
          expect(cycleChoiceSheet(), findsOneWidget);
          final rows = tester
              .widgetList<OBSettingsChoiceRow>(
                find.descendant(
                  of: cycleChoiceSheet(),
                  matching: find.byType(OBSettingsChoiceRow),
                ),
              )
              .toList();
          expect(rows, isNotEmpty);
          for (final row in rows) {
            if (row.label == label) {
              expect(row.selected, isTrue);
              expect(
                tester
                    .getSemantics(find.text(row.label).last)
                    .flagsCollection
                    .isSelected
                    .toBoolOrNull(),
                isTrue,
              );
            } else {
              expect(row.selected, isFalse);
            }
          }
        }

        // Journal enabled entry and selected-day navigation.
        var repo = await loadRepo();
        var journal = await mountJournal(repository: repo);
        final journalPage = find.byType(OpenBandJournal);
        final journalEntry = find.byKey(const ValueKey('cycle-journal'));
        await ensureFullyInSafeViewport(journalPage, journalEntry);
        expect(journalEntry.hitTestable(), findsOneWidget);
        expect(find.text('Zyklus'), findsWidgets);
        await capture('cycle-journal-entry');
        await tester.tap(journalEntry.hitTestable());
        await pumpAfterTap();
        await pumpUntil(
          () => find
              .byKey(const ValueKey('cycle-overview'))
              .evaluate()
              .isNotEmpty,
          'Cycle did not open from Journal.',
        );
        await expectMainFixture();
        expect(
          find.text(
            DateFormat('EEE, d. MMM', 'de_DE').format(DateTime.parse(day)),
          ),
          findsOneWidget,
        );
        await capture('cycle-journal');
        await popRoute();
        await pumpUntil(
          () => find.byType(OpenBandJournal).evaluate().isNotEmpty,
          'Journal route did not return.',
        );
        expect(find.byKey(const ValueKey('cycle-journal')), findsOneWidget);
        journal.dispose();

        repo = await loadRepo();
        journal = await mountJournal(
          repository: repo,
          brightness: Brightness.dark,
        );
        await ensureFullyInSafeViewport(
          find.byType(OpenBandJournal),
          find.byKey(const ValueKey('cycle-journal')),
        );
        await capture('cycle-journal-entry-dark');
        await tester.tap(
          find.byKey(const ValueKey('cycle-journal')).hitTestable(),
        );
        await pumpAfterTap();
        await pumpUntil(
          () => find
              .byKey(const ValueKey('cycle-overview'))
              .evaluate()
              .isNotEmpty,
          'Cycle dark did not open from Journal.',
        );
        await capture('cycle-journal-dark');
        journal.dispose();

        repo = await loadRepo();
        repo.failCycleSettingsRead = true;
        journal = await mountJournal(repository: repo);
        final journalErrorRow = find.byKey(const ValueKey('cycle-journal'));
        await ensureFullyInSafeViewport(
          find.byType(OpenBandJournal),
          journalErrorRow,
        );
        expect(journalErrorRow, findsOneWidget);
        expect(journalErrorRow.hitTestable(), findsOneWidget);
        expect(
          find.descendant(of: journalErrorRow, matching: find.text('—')),
          findsOneWidget,
        );
        final settingsReadsBeforeRetry = repo.settingsReads;
        await capture('cycle-journal-error');
        await tester.tap(journalErrorRow.hitTestable());
        await pumpAfterTap();
        expect(find.byKey(const ValueKey('cycle-journal')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('cycle-journal')),
            matching: find.text('—'),
          ),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('cycle-overview')), findsNothing);
        expect(repo.settingsReads, greaterThan(settingsReadsBeforeRetry));
        repo.failCycleSettingsRead = false;
        repo.failCycleLogRead = true;
        await tester.tap(
          find.byKey(const ValueKey('cycle-journal')).hitTestable(),
        );
        await pumpAfterTap();
        await tester.tap(
          find.byKey(const ValueKey('cycle-journal')).hitTestable(),
        );
        await pumpAfterTap();
        await pumpUntil(
          () => find.text('Daten nicht geladen').evaluate().isNotEmpty,
          'Journal retry did not reach cycle read-error.',
        );
        expect(find.text('Erneut versuchen'), findsOneWidget);
        expect(find.byKey(const ValueKey('cycle-journal')), findsNothing);
        journal.dispose();

        repo = await loadRepo();
        repo.failCycleSettingsRead = true;
        journal = await mountJournal(
          repository: repo,
          brightness: Brightness.dark,
        );
        await ensureFullyInSafeViewport(
          find.byType(OpenBandJournal),
          find.byKey(const ValueKey('cycle-journal')),
        );
        expect(find.byKey(const ValueKey('cycle-journal')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('cycle-journal')),
            matching: find.text('—'),
          ),
          findsOneWidget,
        );
        await capture('cycle-journal-error-dark');
        journal.dispose();

        // Disabled setup, then enable/save reflected in Journal and main.
        repo = await loadRepo();
        repo.cycleSettings = const CycleSettings(
          enabled: false,
          estimatesEnabled: false,
          lengthReviewEnabled: false,
        );
        journal = await mountJournal(repository: repo);
        expect(find.byKey(const ValueKey('cycle-journal')), findsNothing);
        await capture('cycle-journal-disabled');
        journal.dispose();

        await mountCycle(repository: repo, settingsOnly: true);
        expect(find.byKey(const ValueKey('cycle-settings')), findsOneWidget);
        expect(
          tester
              .widget<CupertinoSwitch>(toggleSwitch('Zyklus im Journal'))
              .value,
          isFalse,
        );
        await capture('cycle-setup');
        await tester.tap(toggleSwitch('Zyklus im Journal'));
        await pumpAfterTap();
        expect(
          tester
              .widget<CupertinoSwitch>(toggleSwitch('Zyklus im Journal'))
              .value,
          isTrue,
        );
        expect(repo.cycleSettings.enabled, isTrue);
        expect(repo.settingsWrites, 1);
        await capture('cycle-setup-saved');

        journal = await mountJournal(repository: repo);
        await ensureFullyInSafeViewport(
          find.byType(OpenBandJournal),
          find.byKey(const ValueKey('cycle-journal')),
        );
        expect(find.byKey(const ValueKey('cycle-journal')), findsOneWidget);
        await capture('cycle-journal-after-enable');
        await tester.tap(
          find.byKey(const ValueKey('cycle-journal')).hitTestable(),
        );
        await pumpAfterTap();
        await pumpUntil(
          () => find
              .byKey(const ValueKey('cycle-overview'))
              .evaluate()
              .isNotEmpty,
          'Cycle did not open after enabling.',
        );
        expect(find.text('Tag 23'), findsOneWidget);
        await capture('cycle-main-after-enable');
        journal.dispose();

        repo = await loadRepo();
        repo.cycleSettings = const CycleSettings(
          enabled: false,
          estimatesEnabled: false,
          lengthReviewEnabled: false,
        );
        await mountCycle(
          repository: repo,
          settingsOnly: true,
          brightness: Brightness.dark,
        );
        expect(
          tester
              .widget<CupertinoSwitch>(toggleSwitch('Zyklus im Journal'))
              .value,
          isFalse,
        );
        await capture('cycle-setup-dark');

        // Settings closed; situation picker runs last so a sheet-API
        // mismatch cannot drop the rest of the flow.
        repo = await loadRepo();
        await mountCycle(repository: repo, settingsOnly: true);
        expect(
          tester
              .widget<CupertinoSwitch>(toggleSwitch('Zyklus im Journal'))
              .value,
          isTrue,
        );
        expect(
          tester.widget<CupertinoSwitch>(toggleSwitch('Zeitschätzung')).value,
          isTrue,
        );
        expect(find.text('Keine Angabe'), findsOneWidget);
        await capture('cycle-settings');
        await mountCycle(
          repository: repo,
          settingsOnly: true,
          brightness: Brightness.dark,
        );
        await capture('cycle-settings-dark');

        // Info.
        repo = await loadRepo();
        await mountCycle(repository: repo);
        await tester.tap(find.byTooltip('Information'));
        await pumpAfterTap();
        expect(find.text('Zyklus'), findsWidgets);
        expect(
          find.text(
            'Die Zeitschätzung nutzt den Median deiner eingetragenen Abstände. '
            'Die Spanne zeigt deren bisherige Streuung.',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'Fehlende Einträge können die Schätzung verändern. '
            'Abstände über 60 Tage bleiben offen. Ein Eisprung wird nicht bestimmt.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Starts und Beobachtungen gelten für das gewählte Datum.'),
          findsNothing,
        );
        await capture('cycle-info');
        await tester.tap(find.text('Schließen'));
        await pumpAfterTap();
        await mountCycle(repository: repo, brightness: Brightness.dark);
        await tester.tap(find.byTooltip('Information'));
        await pumpAfterTap();
        await capture('cycle-info-dark');
        await tester.tap(find.text('Schließen'));
        await pumpAfterTap();

        // Main / empty / first start / withheld estimate / read error / partial.
        repo = await loadRepo();
        await mountCycle(repository: repo);
        await expectMainFixture();
        await scrollListToMin(find.byKey(const ValueKey('cycle-overview')));
        await capture('cycle-main');
        await tester.tap(find.byTooltip('Datum'));
        await pumpAfterTap();
        expect(find.text('Übernehmen'), findsOneWidget);
        await capture('cycle-day-picker');
        await tester.tap(find.bySemanticsLabel('Montag, 14. September 2026'));
        await pumpAfterTap();
        await tester.tap(find.widgetWithText(OBAction, 'Übernehmen'));
        await pumpAfterTap();
        expect(
          find.text(
            DateFormat('EEE, d. MMM', 'de_DE').format(DateTime(2026, 9, 14)),
          ),
          findsOneWidget,
        );
        expect(find.text('Tag 22'), findsOneWidget);
        await capture('cycle-day-picked');

        await mountCycle(repository: repo, brightness: Brightness.dark);
        await expectMainFixture();
        await capture('cycle-main-dark');
        await tester.tap(find.byTooltip('Datum'));
        await pumpAfterTap();
        expect(find.text('Übernehmen'), findsOneWidget);
        expect(find.text('Datum'), findsWidgets);
        await capture('cycle-day-picker-dark');
        await popRoute();

        repo = await loadRepo();
        repo.clearCycleLogs();
        await mountCycle(repository: repo);
        expect(find.text('—'), findsOneWidget);
        expect(find.text('Noch kein Beginn'), findsOneWidget);
        expect(find.text('Nächster Beginn · geschätzt'), findsNothing);
        await capture('cycle-empty');
        await mountCycle(repository: repo, brightness: Brightness.dark);
        expect(find.text('Noch kein Beginn'), findsOneWidget);
        await capture('cycle-empty-dark');

        repo = await loadRepo();
        repo.clearCycleLogs();
        repo.seedCycleStart(const CycleStart(date: day, kind: kCycleStartKind));
        await mountCycle(repository: repo);
        expect(find.text('Tag 1'), findsOneWidget);
        expect(find.text('Beginn · 15. September'), findsOneWidget);
        expect(find.text('Beginn bearbeiten'), findsOneWidget);
        expect(find.text('Nächster Beginn · geschätzt'), findsNothing);
        await capture('cycle-first-start');
        await mountCycle(repository: repo, brightness: Brightness.dark);
        expect(find.text('Tag 1'), findsOneWidget);
        await capture('cycle-first-start-dark');

        repo = await loadRepo();
        repo.clearCycleLogs();
        repo.seedCycleStart(
          const CycleStart(date: '2026-06-01', kind: kCycleStartKind),
        );
        repo.seedCycleStart(
          const CycleStart(date: '2026-08-24', kind: kCycleStartKind),
        );
        await mountCycle(repository: repo);
        expect(find.text('Tag 23'), findsOneWidget);
        expect(find.text('Schätzung offen'), findsOneWidget);
        expect(find.text('Abstand über 60 Tage'), findsOneWidget);
        await capture('cycle-estimate-open');
        await mountCycle(repository: repo, brightness: Brightness.dark);
        expect(find.text('Abstand über 60 Tage'), findsOneWidget);
        await capture('cycle-estimate-open-dark');

        repo = await loadRepo();
        repo.failCycleRead = true;
        await mountCycle(repository: repo);
        expect(find.text('Daten nicht geladen'), findsOneWidget);
        expect(find.text('Erneut versuchen'), findsOneWidget);
        await capture('cycle-read-error');
        repo.failCycleRead = false;
        await tester.tap(find.text('Erneut versuchen'));
        await pumpAfterTap();
        await expectMainFixture();
        await capture('cycle-read-error-retry');
        repo = await loadRepo();
        repo.failCycleRead = true;
        await mountCycle(repository: repo, brightness: Brightness.dark);
        expect(find.text('Daten nicht geladen'), findsOneWidget);
        await capture('cycle-read-error-dark');

        repo = await loadRepo();
        repo.clearCycleLogs();
        repo.seedUnreadableCycleStart({'date': '2026-08-24', 'kind': 1});
        await mountCycle(repository: repo);
        expect(find.text('—'), findsOneWidget);
        expect(find.text('Einträge teilweise lesbar'), findsOneWidget);
        expect(find.text('Tag 23'), findsNothing);
        expect(find.text('Starts nicht lesbar'), findsNothing);
        expect(find.text('Noch kein Beginn'), findsNothing);
        expect(find.text('Schätzung offen'), findsNothing);
        await capture('cycle-partial');
        await mountCycle(repository: repo, brightness: Brightness.dark);
        expect(find.text('—'), findsOneWidget);
        expect(find.text('Einträge teilweise lesbar'), findsOneWidget);
        await capture('cycle-partial-dark');

        repo = await loadRepo();
        repo.seedUnreadableCycleStart({'date': '2026-05-01', 'kind': 1});
        repo.cycleSettings = const CycleSettings(
          enabled: true,
          estimatesEnabled: false,
          lengthReviewEnabled: false,
        );
        await mountCycle(repository: repo);
        expect(find.text('—'), findsOneWidget);
        expect(find.text('Tag 23'), findsNothing);
        expect(find.textContaining('Tag '), findsNothing);

        // History: observation and start distinct.
        repo = await loadRepo();
        repo.seedCycleObservation(
          const CycleObservation(date: day, tags: ['cramps']),
        );
        await mountCycle(repository: repo);
        await tapVisible(
          find.text('Verlauf'),
          find.byKey(const ValueKey('cycle-overview')),
        );
        expect(find.byKey(const ValueKey('cycle-history')), findsOneWidget);
        expect(find.text('15. September'), findsOneWidget);
        expect(find.text('Krämpfe'), findsOneWidget);
        expect(find.text('24. August'), findsOneWidget);
        expect(find.text('31. Juli'), findsOneWidget);
        expect(find.text('29. Juni'), findsOneWidget);
        expect(find.text('1. Juni'), findsOneWidget);
        expect(find.text('Beginn'), findsNWidgets(4));
        await capture('cycle-history');
        await tester.tap(find.text('24. August'));
        await pumpAfterTap();
        expect(find.byKey(const ValueKey('cycle-start')), findsOneWidget);
        expect(find.text('Beginn'), findsWidgets);
        await popRoute();
        await tester.tap(find.text('15. September'));
        await pumpAfterTap();
        expect(find.byKey(const ValueKey('cycle-observation')), findsOneWidget);
        expect(find.text('Beobachtung'), findsOneWidget);
        await popRoute();
        await mountCycle(repository: repo, brightness: Brightness.dark);
        await tapVisible(
          find.text('Verlauf'),
          find.byKey(const ValueKey('cycle-overview')),
        );
        expect(find.text('Krämpfe'), findsOneWidget);
        expect(find.text('Beginn'), findsNWidgets(4));
        await capture('cycle-history-dark');

        // New start, keyboard, save failure retaining input, context-retry.
        repo = await loadRepo();
        await mountCycle(repository: repo);
        await tapVisible(
          find.text('Beginn eintragen'),
          find.byKey(const ValueKey('cycle-overview')),
        );
        expect(find.byKey(const ValueKey('cycle-start')), findsOneWidget);
        expect(find.text('15. Sept. 2026'), findsOneWidget);
        expect(find.text('Entfernen'), findsNothing);
        await capture('cycle-start');
        final note = find.byKey(const ValueKey('cycle-note'));
        await ensureFullyInSafeViewport(
          find.byKey(const ValueKey('cycle-start')),
          note,
        );
        await tester.tap(note);
        await tester.pump();
        await tester.showKeyboard(note);
        await tester.pump();
        await waitKeyboardInset(open: true);
        await tester.enterText(note, 'Heute begonnen');
        await tester.pump();
        expect(
          tester.widget<TextField>(note).controller!.text,
          'Heute begonnen',
        );
        await capture('cycle-start-keyboard');
        await dismissCycleNote(find.byKey(const ValueKey('cycle-start')));
        repo.failCycleWrite = true;
        final writesBeforeFail = repo.startWrites;
        await tester.tap(find.widgetWithText(OBAction, 'Speichern'));
        await pumpAfterTap();
        expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
        expect(
          tester.widget<TextField>(note).controller!.text,
          'Heute begonnen',
        );
        expect(find.byKey(const ValueKey('cycle-start')), findsOneWidget);
        await capture('cycle-save-error');
        repo.failCycleWrite = false;
        await tester.tap(find.widgetWithText(OBAction, 'Speichern'));
        await pumpAfterTap();
        await pumpUntil(
          () => find
              .byKey(const ValueKey('cycle-overview'))
              .evaluate()
              .isNotEmpty,
          'Start save retry did not return to main.',
        );
        expect(repo.startWrites, writesBeforeFail + 2);
        expect(find.text('Beginn bearbeiten'), findsOneWidget);
        expect(find.text('Tag 1'), findsOneWidget);
        await capture('cycle-start-saved');

        await mountCycle(
          repository: await loadRepo(),
          brightness: Brightness.dark,
        );
        await tapVisible(
          find.text('Beginn eintragen'),
          find.byKey(const ValueKey('cycle-overview')),
        );
        await capture('cycle-start-dark');
        repo = await loadRepo();
        repo.failCycleWrite = true;
        await mountCycle(repository: repo, brightness: Brightness.dark);
        await tapVisible(
          find.text('Beginn eintragen'),
          find.byKey(const ValueKey('cycle-overview')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('cycle-note')),
          'Heute begonnen',
        );
        await tester.pump();
        await tester.tap(find.widgetWithText(OBAction, 'Speichern'));
        await pumpAfterTap();
        expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('cycle-note')))
              .controller!
              .text,
          'Heute begonnen',
        );
        await capture('cycle-save-error-dark');

        repo = await loadRepo();
        repo.failCycleContextRefresh = true;
        await mountCycle(repository: repo);
        await tapVisible(
          find.text('Beginn eintragen'),
          find.byKey(const ValueKey('cycle-overview')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('cycle-note')),
          'Refresh note',
        );
        await tester.pump();
        await tester.tap(find.widgetWithText(OBAction, 'Speichern'));
        await pumpAfterTap();
        final savedNote = find.byKey(const ValueKey('cycle-note'));
        expect(
          find.text('Gespeichert · Aktualisieren fehlgeschlagen'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(OBAction, 'Erneut versuchen'),
          findsOneWidget,
        );
        expect(find.widgetWithText(OBAction, 'Speichern'), findsNothing);
        expect(find.text('Entfernen'), findsNothing);
        expect(tester.widget<TextField>(savedNote).enabled, isFalse);
        expect(
          tester.widget<TextField>(savedNote).controller!.text,
          'Refresh note',
        );
        expect(
          tester
              .widget<OBSettingsValueRow>(
                find.byWidgetPredicate(
                  (w) => w is OBSettingsValueRow && w.label == 'Datum',
                ),
              )
              .onTap,
          isNull,
        );
        expect(find.byKey(const ValueKey('cycle-start')), findsOneWidget);
        expect(repo.startWrites, 1);
        final refreshesAfterFail = repo.contextRefreshes;
        await capture('cycle-context-error');
        repo.failCycleContextRefresh = false;
        await tester.tap(find.widgetWithText(OBAction, 'Erneut versuchen'));
        await pumpAfterTap();
        await pumpUntil(
          () => find
              .byKey(const ValueKey('cycle-overview'))
              .evaluate()
              .isNotEmpty,
          'Context retry did not return to main.',
        );
        expect(repo.startWrites, 1);
        expect(repo.contextRefreshes, greaterThan(refreshesAfterFail));
        expect(find.text('Beginn bearbeiten'), findsOneWidget);
        await capture('cycle-context-retry');

        repo = await loadRepo();
        repo.failCycleContextRefresh = true;
        await mountCycle(repository: repo, brightness: Brightness.dark);
        await tapVisible(
          find.text('Beginn eintragen'),
          find.byKey(const ValueKey('cycle-overview')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('cycle-note')),
          'Refresh note',
        );
        await tester.pump();
        await tester.tap(find.widgetWithText(OBAction, 'Speichern'));
        await pumpAfterTap();
        expect(
          find.text('Gespeichert · Aktualisieren fehlgeschlagen'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('cycle-note')))
              .enabled,
          isFalse,
        );
        await capture('cycle-context-error-dark');

        // Edit existing, removal confirmation, exact undo, conflict/reload.
        repo = await loadRepo();
        await mountCycle(repository: repo);
        await tapVisible(
          find.text('Verlauf'),
          find.byKey(const ValueKey('cycle-overview')),
        );
        await tester.tap(find.text('24. August'));
        await pumpAfterTap();
        expect(find.byKey(const ValueKey('cycle-start')), findsOneWidget);
        expect(find.text('24. Aug. 2026'), findsOneWidget);
        expect(find.text('Entfernen'), findsOneWidget);
        await capture('cycle-edit');
        repo.seedCycleStart(
          const CycleStart(
            date: '2026-08-24',
            kind: kCycleStartKind,
            note: 'geändert',
          ),
        );
        await tester.enterText(
          find.byKey(const ValueKey('cycle-note')),
          'lokal',
        );
        await tester.pump();
        await tester.tap(find.widgetWithText(OBAction, 'Speichern'));
        await pumpAfterTap();
        expect(find.text('Eintrag wurde geändert'), findsOneWidget);
        expect(find.text('Neu laden'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('cycle-note')))
              .controller!
              .text,
          'lokal',
        );
        await capture('cycle-conflict');
        await tester.tap(find.text('Neu laden'));
        await pumpAfterTap();
        expect(find.text('Eintrag wurde geändert'), findsNothing);
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('cycle-note')))
              .controller!
              .text,
          'geändert',
        );
        await capture('cycle-conflict-reload');

        repo = await loadRepo();
        await mountCycle(repository: repo, brightness: Brightness.dark);
        await tapVisible(
          find.text('Verlauf'),
          find.byKey(const ValueKey('cycle-overview')),
        );
        await tester.tap(find.text('24. August'));
        await pumpAfterTap();
        await capture('cycle-edit-dark');

        repo = await loadRepo();
        await mountCycle(repository: repo);
        await tapVisible(
          find.text('Verlauf'),
          find.byKey(const ValueKey('cycle-overview')),
        );
        await tester.tap(find.text('24. August'));
        await pumpAfterTap();
        await tester.tap(find.widgetWithText(OBAction, 'Entfernen'));
        await pumpAfterTap();
        expect(find.text('Beginn 24. August entfernen?'), findsOneWidget);
        await capture('cycle-remove');
        await tester.tap(find.text('Entfernen').last);
        await pumpAfterTap();
        await pumpUntil(
          () =>
              find.byKey(const ValueKey('cycle-history')).evaluate().isNotEmpty,
          'Remove did not return to history.',
        );
        await expectUndoNotice('Beginn 24. Aug. entfernt', 'Rückgängig');
        expect(repo.startRemoves, 1);
        await capture('cycle-undo');
        final restored = const CycleStart(
          date: '2026-08-24',
          kind: kCycleStartKind,
        );
        await tapUndoNotice('Rückgängig');
        expect(repo.startRestores, 1);
        await popRoute();
        await pumpUntil(
          () => find
              .byKey(const ValueKey('cycle-overview'))
              .evaluate()
              .isNotEmpty,
          'History did not return to main after undo.',
        );
        expect(find.text('Tag 23'), findsOneWidget);
        expect(find.text('Beginn · 24. August'), findsOneWidget);
        final snap = await repo.readCycle(day, now: now);
        expect(snap.starts, contains(restored));
        await capture('cycle-undo-restored');

        // Overview remove, History roundtrip, exact undo restore.
        repo = await loadRepo();
        const overviewStart = CycleStart(
          date: day,
          kind: kCycleStartKind,
          note: 'overview',
        );
        repo.seedCycleStart(overviewStart);
        await mountCycle(repository: repo);
        await tapVisible(
          find.text('Beginn bearbeiten'),
          find.byKey(const ValueKey('cycle-overview')),
        );
        expect(find.byKey(const ValueKey('cycle-start')), findsOneWidget);
        expect(find.text('Entfernen'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('cycle-note')))
              .controller!
              .text,
          'overview',
        );
        await tester.tap(find.widgetWithText(OBAction, 'Entfernen'));
        await pumpAfterTap();
        expect(find.text('Beginn 15. September entfernen?'), findsOneWidget);
        final overviewRemoves = repo.startRemoves;
        final overviewRestores = repo.startRestores;
        await tester.tap(find.text('Entfernen').last);
        await pumpAfterTap();
        await pumpUntil(
          () =>
              find
                  .byKey(const ValueKey('cycle-overview'))
                  .evaluate()
                  .isNotEmpty &&
              find.byKey(const ValueKey('cycle-start')).evaluate().isEmpty,
          'Overview remove did not return to main.',
        );
        await expectUndoNotice('Beginn 15. Sept. entfernt', 'Rückgängig');
        expect(repo.startRemoves, overviewRemoves + 1);
        expect(repo.startRestores, overviewRestores);
        await pumpUntil(
          () => find.text('Beginn eintragen').evaluate().isNotEmpty,
          'Overview remove did not refresh main.',
        );
        await tapVisible(
          find.text('Verlauf'),
          find.byKey(const ValueKey('cycle-overview')),
        );
        expect(find.byKey(const ValueKey('cycle-history')), findsOneWidget);
        expect(find.text('24. August'), findsOneWidget);
        expect(find.text('15. September'), findsNothing);
        expect(repo.startRemoves, overviewRemoves + 1);
        expect(repo.startRestores, overviewRestores);
        await popRoute();
        await pumpUntil(
          () => find
              .byKey(const ValueKey('cycle-overview'))
              .evaluate()
              .isNotEmpty,
          'History did not return to main after overview remove.',
        );
        await expectUndoNotice('Beginn 15. Sept. entfernt', 'Rückgängig');
        expect(repo.startRemoves, overviewRemoves + 1);
        expect(repo.startRestores, overviewRestores);
        await capture('cycle-overview-undo');
        await tapUndoNotice('Rückgängig');
        await pumpUntil(
          () => find.text('Beginn bearbeiten').evaluate().isNotEmpty,
          'Overview undo did not restore start.',
        );
        expect(repo.startRemoves, overviewRemoves + 1);
        expect(repo.startRestores, overviewRestores + 1);
        final overviewSnap = await repo.readCycle(day, now: now);
        expect(overviewSnap.starts, contains(overviewStart));

        repo = await loadRepo();
        await mountCycle(repository: repo);
        await tapVisible(
          find.text('Verlauf'),
          find.byKey(const ValueKey('cycle-overview')),
        );
        await tester.tap(find.text('24. August'));
        await pumpAfterTap();
        await tester.tap(find.widgetWithText(OBAction, 'Entfernen'));
        await pumpAfterTap();
        await tester.tap(find.text('Entfernen').last);
        await pumpAfterTap();
        await pumpUntil(
          () =>
              find.byKey(const ValueKey('cycle-history')).evaluate().isNotEmpty,
          'Restore-conflict remove did not return to history.',
        );
        await expectUndoNotice('Beginn 24. Aug. entfernt', 'Rückgängig');
        repo.seedCycleStart(
          const CycleStart(
            date: '2026-08-24',
            kind: kCycleStartKind,
            note: 'fremd',
          ),
        );
        await tapUndoNotice('Rückgängig');
        await expectUndoNotice('Beginn wurde geändert', 'Neu laden');
        expect(repo.startRestores, 1);
        final conflicted = await repo.readCycle(day, now: now);
        expect(
          conflicted.starts,
          contains(
            const CycleStart(
              date: '2026-08-24',
              kind: kCycleStartKind,
              note: 'fremd',
            ),
          ),
        );
        await capture('cycle-undo-conflict');
        await tapUndoNotice('Neu laden');
        expect(repo.startRestores, 1);
        expect(find.byType(SnackBarAction), findsNothing);
        expect(undoNoticeAction('Neu laden'), findsNothing);

        repo = await loadRepo();
        await mountCycle(repository: repo, brightness: Brightness.dark);
        await tapVisible(
          find.text('Verlauf'),
          find.byKey(const ValueKey('cycle-overview')),
        );
        await tester.tap(find.text('24. August'));
        await pumpAfterTap();
        await tester.tap(find.widgetWithText(OBAction, 'Entfernen'));
        await pumpAfterTap();
        expect(find.text('Beginn 24. August entfernen?'), findsOneWidget);
        await capture('cycle-remove-dark');
        await tester.tap(find.text('Entfernen').last);
        await pumpAfterTap();
        await pumpUntil(
          () =>
              find.byKey(const ValueKey('cycle-history')).evaluate().isNotEmpty,
          'Dark remove did not return to history.',
        );
        await expectUndoNotice('Beginn 24. Aug. entfernt', 'Rückgängig');
        await capture('cycle-undo-dark');

        repo = await loadRepo();
        repo.failCycleContextRefresh = true;
        await mountCycle(repository: repo);
        await tapVisible(
          find.text('Verlauf'),
          find.byKey(const ValueKey('cycle-overview')),
        );
        await tester.tap(find.text('24. August'));
        await pumpAfterTap();
        await tester.tap(find.widgetWithText(OBAction, 'Entfernen'));
        await pumpAfterTap();
        final removesBefore = repo.startRemoves;
        final restoresBefore = repo.startRestores;
        final refreshesBeforeRemove = repo.contextRefreshes;
        await tester.tap(find.text('Entfernen').last);
        await pumpAfterTap();
        await pumpUntil(
          () =>
              find.byKey(const ValueKey('cycle-history')).evaluate().isNotEmpty,
          'Remove wake did not return to history.',
        );
        expect(repo.startRemoves, removesBefore + 1);
        expect(repo.contextRefreshes, greaterThan(refreshesBeforeRemove));
        await expectUndoNotice('Beginn 24. Aug. entfernt', 'Rückgängig');
        expect(
          find.text('Entfernt · Aktualisieren fehlgeschlagen'),
          findsOneWidget,
        );
        expect(
          find.text('Wiederhergestellt · Aktualisieren fehlgeschlagen'),
          findsNothing,
        );
        await capture('cycle-remove-context-error');
        await tapUndoNotice('Rückgängig');
        expect(repo.startRestores, restoresBefore + 1);
        expect(repo.startRemoves, removesBefore + 1);
        expect(
          find.text('Wiederhergestellt · Aktualisieren fehlgeschlagen'),
          findsOneWidget,
        );
        expect(
          find.text('Entfernt · Aktualisieren fehlgeschlagen'),
          findsNothing,
        );
        await capture('cycle-restore-context-error');

        // Observation tags/note, keyboard, save.
        repo = await loadRepo();
        await mountCycle(repository: repo);
        await tapVisible(
          find.text('Beobachtung festhalten'),
          find.byKey(const ValueKey('cycle-overview')),
        );
        expect(find.byKey(const ValueKey('cycle-observation')), findsOneWidget);
        await capture('cycle-observation');
        await tapVisible(
          find.text('Krämpfe'),
          find.byKey(const ValueKey('cycle-observation')),
        );
        await tapVisible(
          find.text('Müdigkeit'),
          find.byKey(const ValueKey('cycle-observation')),
        );
        final obsNote = find.byKey(const ValueKey('cycle-note'));
        await ensureFullyInSafeViewport(
          find.byKey(const ValueKey('cycle-observation')),
          obsNote,
        );
        await tester.tap(obsNote);
        await tester.pump();
        await tester.showKeyboard(obsNote);
        await tester.pump();
        await waitKeyboardInset(open: true);
        await tester.enterText(obsNote, 'Leichte Krämpfe');
        await tester.pump();
        await capture('cycle-observation-keyboard');
        await dismissCycleNote(find.byKey(const ValueKey('cycle-observation')));
        await ensureFullyInSafeViewport(
          find.byKey(const ValueKey('cycle-observation')),
          find.widgetWithText(OBAction, 'Speichern'),
        );
        await tester.tap(
          find.widgetWithText(OBAction, 'Speichern').hitTestable(),
        );
        await pumpAfterTap();
        await pumpUntil(
          () => find
              .byKey(const ValueKey('cycle-overview'))
              .evaluate()
              .isNotEmpty,
          'Observation save did not return to main.',
        );
        expect(repo.observationWrites, 1);
        await tapVisible(
          find.text('Verlauf'),
          find.byKey(const ValueKey('cycle-overview')),
        );
        expect(find.text('Krämpfe'), findsOneWidget);
        await capture('cycle-observation-saved');

        await mountCycle(
          repository: await loadRepo(),
          brightness: Brightness.dark,
        );
        await tapVisible(
          find.text('Beobachtung festhalten'),
          find.byKey(const ValueKey('cycle-overview')),
        );
        await capture('cycle-observation-dark');

        // 2x main / settings / observation and long-text scrolling.
        repo = await loadRepo();
        await mountCycle(repository: repo, scale: 2);
        final main2x = find.byKey(const ValueKey('cycle-overview'));
        await ensureFullyInSafeViewport(main2x, find.text('Tag 23'));
        await scrollListToMin(main2x);
        await capture('cycle-main-2x');
        await tester.tap(find.byTooltip('Datum'));
        await pumpAfterTap();
        final pickerPage = find.ancestor(
          of: find.widgetWithText(OBAction, 'Übernehmen'),
          matching: find.byType(Scaffold),
        );
        await ensureFullyInSafeViewport(
          pickerPage,
          find.widgetWithText(OBAction, 'Übernehmen'),
        );
        await capture('cycle-day-picker-2x-scrolled');
        await popRoute();

        await mountCycle(
          repository: repo,
          scale: 2,
          brightness: Brightness.dark,
        );
        await scrollListToMin(find.byKey(const ValueKey('cycle-overview')));
        await capture('cycle-main-2x-dark');

        repo = await loadRepo();
        await mountCycle(repository: repo, settingsOnly: true, scale: 2);
        await ensureFullyInSafeViewport(
          find.byKey(const ValueKey('cycle-settings')),
          find.text('Situation'),
        );
        await capture('cycle-settings-2x');
        await mountCycle(
          repository: repo,
          settingsOnly: true,
          scale: 2,
          brightness: Brightness.dark,
        );
        await ensureFullyInSafeViewport(
          find.byKey(const ValueKey('cycle-settings')),
          find.text('Situation'),
        );
        await capture('cycle-settings-2x-dark');

        repo = await loadRepo();
        await mountCycle(repository: repo, scale: 2);
        await tapVisible(
          find.text('Beobachtung festhalten'),
          find.byKey(const ValueKey('cycle-overview')),
        );
        final obs2x = find.byKey(const ValueKey('cycle-observation'));
        await ensureFullyInSafeViewport(obs2x, find.text('Krämpfe'));
        await capture('cycle-observation-2x');
        await tapVisible(find.text('Krämpfe'), obs2x);
        await tapVisible(find.text('Übelkeit'), obs2x);
        final obs2xNote = find.byKey(const ValueKey('cycle-note'));
        await ensureFullyInSafeViewport(obs2x, obs2xNote);
        await tester.tap(obs2xNote);
        await tester.pump();
        await tester.showKeyboard(obs2xNote);
        await tester.pump();
        await waitKeyboardInset(open: true);
        await tester.enterText(obs2xNote, longNote);
        await tester.pump();
        await dismissCycleNote(obs2x);
        await ensureFullyInSafeViewport(
          obs2x,
          find.widgetWithText(OBAction, 'Speichern'),
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('cycle-note')))
              .controller!
              .text,
          longNote,
        );
        await capture('cycle-observation-2x-scrolled');
        await tester.tap(
          find.widgetWithText(OBAction, 'Speichern').hitTestable(),
        );
        await pumpAfterTap();
        await pumpUntil(
          () => find
              .byKey(const ValueKey('cycle-overview'))
              .evaluate()
              .isNotEmpty,
          '2x observation save did not return to main.',
        );

        await mountCycle(
          repository: await loadRepo(),
          scale: 2,
          brightness: Brightness.dark,
        );
        await tapVisible(
          find.text('Beobachtung festhalten'),
          find.byKey(const ValueKey('cycle-overview')),
        );
        await ensureFullyInSafeViewport(
          find.byKey(const ValueKey('cycle-observation')),
          find.text('Krämpfe'),
        );
        await capture('cycle-observation-2x-dark');

        repo = await loadRepo();
        await mountCycle(repository: repo, scale: 2);
        await tapVisible(
          find.text('Verlauf'),
          find.byKey(const ValueKey('cycle-overview')),
        );
        await tester.tap(find.text('24. August'));
        await pumpAfterTap();
        await tester.tap(find.widgetWithText(OBAction, 'Entfernen'));
        await pumpAfterTap();
        await tester.tap(find.text('Entfernen').last);
        await pumpAfterTap();
        await pumpUntil(
          () =>
              find.byKey(const ValueKey('cycle-history')).evaluate().isNotEmpty,
          '2x remove did not return to history.',
        );
        await expectUndoNotice('Beginn 24. Aug. entfernt', 'Rückgängig');
        await capture('cycle-undo-2x');

        repo = await loadRepo();
        repo.failCycleContextRefresh = true;
        await mountCycle(repository: repo, scale: 2);
        await tapVisible(
          find.text('Beginn eintragen'),
          find.byKey(const ValueKey('cycle-overview')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('cycle-note')),
          'Refresh note',
        );
        await tester.pump();
        await tester.tap(find.widgetWithText(OBAction, 'Speichern'));
        await pumpAfterTap();
        expect(
          find.text('Gespeichert · Aktualisieren fehlgeschlagen'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('cycle-note')))
              .enabled,
          isFalse,
        );
        await capture('cycle-context-error-2x');

        // Situation picker: shared choice sheet with selected check, then save.
        repo = await loadRepo();
        await mountCycle(repository: repo, settingsOnly: true);
        await tapVisible(
          find.text('Situation'),
          find.byKey(const ValueKey('cycle-settings')),
        );
        await expectSituationSelected('Keine Angabe');
        await capture('cycle-situation');
        await tester.tap(find.text('Natürlicher Zyklus').last);
        await pumpAfterTap();
        expect(cycleChoiceSheet(), findsNothing);
        expect(find.text('Natürlicher Zyklus'), findsOneWidget);
        expect(repo.cycleSettings.situation, CycleSituation.cycling);
        await capture('cycle-situation-saved');
        await tapVisible(
          find.text('Situation'),
          find.byKey(const ValueKey('cycle-settings')),
        );
        await expectSituationSelected('Natürlicher Zyklus');
        await tester.tap(find.text('Natürlicher Zyklus').last);
        await pumpAfterTap();
        await mountCycle(
          repository: repo,
          settingsOnly: true,
          brightness: Brightness.dark,
        );
        await tapVisible(
          find.text('Situation'),
          find.byKey(const ValueKey('cycle-settings')),
        );
        await expectSituationSelected('Natürlicher Zyklus');
        await capture('cycle-situation-dark');
      }

      Future<void> reviewCycleMeasurements() async {
        final now = DateTime(2026, 9, 15, 9, 41);
        const day = SyntheticOpenBandRepository.cycleFixtureDay;

        Future<_CycleReviewRepo> loadRepo() async {
          Future<Map> load(String name) async =>
              jsonDecode(
                    await rootBundle.loadString(
                      'docs/openband5/assets/fixtures/$name.json',
                    ),
                  )
                  as Map;
          final repo = _CycleReviewRepo(
            await load('day-summary'),
            await load('sleep-detail'),
            activity: await load('additional-flows'),
            run: await load('run-detail'),
          );
          await repo.seedNutritionGoals();
          return repo;
        }

        Widget reviewHost({
          required Widget home,
          Brightness brightness = Brightness.light,
          double scale = 1,
        }) => MaterialApp(
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
          home: home,
        );

        Finder downScrollable(Finder ancestor) => find.descendant(
          of: ancestor,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        );

        Rect reviewSafeViewport({Finder? contentOf}) {
          final view = tester.view;
          final dpr = view.devicePixelRatio;
          final size = view.physicalSize / dpr;
          final pad = view.viewPadding;
          final screen = Rect.fromLTRB(
            pad.left / dpr,
            pad.top / dpr,
            size.width - pad.right / dpr,
            size.height - pad.bottom / dpr,
          );
          if (contentOf == null) return screen;
          final box = tester.getRect(downScrollable(contentOf).first);
          return Rect.fromLTRB(
            box.left < screen.left ? screen.left : box.left,
            box.top < screen.top ? screen.top : box.top,
            box.right > screen.right ? screen.right : box.right,
            box.bottom > screen.bottom ? screen.bottom : box.bottom,
          );
        }

        bool rectInSafeViewport(
          Rect box, {
          Finder? contentOf,
          double slop = 0.5,
        }) {
          final safe = reviewSafeViewport(contentOf: contentOf);
          return box.top >= safe.top - slop &&
              box.bottom <= safe.bottom + slop &&
              box.left >= safe.left - slop &&
              box.right <= safe.right + slop;
        }

        Future<void> revealIn(Finder ancestor, Finder target) async {
          final scrollable = downScrollable(ancestor).first;
          var scrolls = 0;
          var searchUp = true;
          while (target.evaluate().isEmpty ||
              target.hitTestable().evaluate().isEmpty) {
            if (scrolls >= 32) {
              throw FlutterError(
                'Control is not hit-testable after production scrolling.',
              );
            }
            if (target.evaluate().isEmpty) {
              final position = tester
                  .state<ScrollableState>(scrollable)
                  .position;
              final atMin = position.pixels <= position.minScrollExtent + 0.5;
              final atMax = position.pixels >= position.maxScrollExtent - 0.5;
              if (searchUp && atMin) searchUp = false;
              final dy = searchUp
                  ? (atMin ? 0.0 : 64.0)
                  : (atMax ? 0.0 : -64.0);
              if (dy == 0) {
                throw FlutterError(
                  'Control is not hit-testable after production scrolling.',
                );
              }
              await tester.drag(scrollable, Offset(0, dy));
              await tester.pump();
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
        }

        Future<void> ensureFullyInSafeViewport(
          Finder ancestor,
          Finder target,
        ) async {
          await revealIn(ancestor, target);
          final scrollable = downScrollable(ancestor).first;
          var extra = 0;
          while (!rectInSafeViewport(
            tester.getRect(target),
            contentOf: ancestor,
          )) {
            if (extra >= 32) {
              throw FlutterError(
                'Control is not fully within the safe viewport.',
              );
            }
            final box = tester.getRect(target);
            final safe = reviewSafeViewport(contentOf: ancestor);
            final overflowBottom = box.bottom - safe.bottom;
            final overflowTop = safe.top - box.top;
            if (extra == 0) {
              await Scrollable.ensureVisible(
                tester.element(target),
                alignment: overflowBottom >= overflowTop ? 1.0 : 0.0,
              );
              await tester.pump();
            } else {
              const minGesture = 64.0;
              final needed = overflowBottom > 0
                  ? -(overflowBottom + 8)
                  : overflowTop + 8;
              final dy = needed < 0
                  ? (needed > -minGesture ? -minGesture : needed)
                  : (needed < minGesture ? minGesture : needed);
              await tester.drag(scrollable, Offset(0, dy));
              await tester.pump();
            }
            extra++;
          }
          expect(target.hitTestable(), findsOneWidget);
        }

        Future<void> scrollListToMin(Finder ancestor) async {
          final scrollable = downScrollable(ancestor).first;
          var scrolls = 0;
          var pumps = 0;
          while (true) {
            final position = tester.state<ScrollableState>(scrollable).position;
            final min = position.minScrollExtent;
            final offset = position.pixels - min;
            final idle = !position.isScrollingNotifier.value;
            if (idle && offset.abs() <= 0.5) {
              expect(offset.abs(), lessThanOrEqualTo(0.5));
              return;
            }
            if (offset > 0.5) {
              if (++scrolls > 32) {
                throw FlutterError('ListView did not reach min scroll extent.');
              }
              await tester.drag(scrollable, const Offset(0, 64));
              await tester.pump();
              continue;
            }
            if (++pumps > 40) {
              throw FlutterError('ListView overscroll did not settle at min.');
            }
            await tester.pump(const Duration(milliseconds: 16));
          }
        }

        Future<void> pumpUntil(bool Function() ready, String message) async {
          await tester.pump();
          var waited = 0;
          while (!ready()) {
            if (++waited > 80) throw FlutterError(message);
            await tester.pump(const Duration(milliseconds: 16));
          }
          await reviewPumpPageTransitions(tester);
        }

        Future<void> pumpAfterTap() async {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await reviewPumpPageTransitions(tester);
        }

        Future<void> popRoute() async {
          await tester.tap(find.byTooltip('Zurück'));
          await reviewPumpPageTransitions(tester);
          await tester.pump();
        }

        Future<void> tapVisible(Finder target, Finder ancestor) async {
          await ensureFullyInSafeViewport(ancestor, target);
          await tester.tap(target.hitTestable());
          await pumpAfterTap();
        }

        Finder cyclePage() => find.byKey(const ValueKey('cycle-overview'));
        Finder measurementsPage() =>
            find.byKey(const ValueKey('cycle-measurements'));
        Finder rhrPlot() =>
            find.byKey(const ValueKey('cycle-measurements-rhr-plot'));
        Finder hrvPlot() =>
            find.byKey(const ValueKey('cycle-measurements-hrv-plot'));
        Finder pickerRow() =>
            find.byKey(const ValueKey('cycle-measurements-picker'));

        Finder inRoute(Finder ancestor, Finder matching) =>
            find.descendant(of: ancestor, matching: matching);

        Finder infoButton() =>
            inRoute(measurementsPage(), find.byTooltip('Information'));

        Finder metricCard(Finder plot) =>
            find.ancestor(of: plot, matching: find.byType(OBCard)).first;

        Finder measurementsChoiceSheet() {
          final byStart = find.byType(OBSettingsChoiceSheet<String>);
          if (byStart.evaluate().isNotEmpty) return byStart;
          return find.byType(OBSettingsChoiceSheet<CycleMeasurementPeriod>);
        }

        CycleNightSourceRow nightSource({
          required String onDay,
          double? rhr,
          double? hrv,
          double? rhrConfidence,
          double? hrvConfidence,
          bool unreadable = false,
        }) => CycleNightSourceRow(
          day: onDay,
          algoVersion: kAlgoVersion,
          payloadUnreadable: unreadable,
          payload: unreadable
              ? null
              : cycleNightSourcePayload(
                  rhr: rhr,
                  hrv: hrv,
                  rhrConfidence: rhrConfidence,
                  hrvConfidence: hrvConfidence,
                  onsetMs: cycleNightOnsetMs(onDay),
                  offsetMs: cycleNightOffsetMs(onDay),
                ),
        );

        Finder infoBody() => find.byKey(const ValueKey('journal-info-body'));
        Finder infoClose() => find.widgetWithText(OBAction, 'Schließen');
        Finder inInfo(String text) => find.descendant(
          of: infoBody(),
          matching: find.textContaining(text),
        );

        Future<void> expectInfoClosePinned() async {
          expect(infoClose().hitTestable(), findsOneWidget);
          expect(rectInSafeViewport(tester.getRect(infoClose())), isTrue);
        }

        Future<void> revealInfoText(Finder target) async {
          final body = infoBody();
          expect(body, findsOneWidget);
          var drags = 0;
          while (target.evaluate().isEmpty ||
              target.hitTestable().evaluate().isEmpty) {
            if (++drags > 24) {
              throw FlutterError(
                'Info source text is not hit-testable after production scrolling.',
              );
            }
            await tester.drag(body, const Offset(0, -64));
            await tester.pump();
            await expectInfoClosePinned();
          }
          expect(target.hitTestable(), findsOneWidget);
          await expectInfoClosePinned();
        }

        Future<void> expectGenericInfoParas() async {
          expect(
            find.text(
              'Ruhepuls und HRV stammen aus gespeicherten Nächten. Das Datum gehört zur jeweiligen Nacht.',
            ),
            findsOneWidget,
          );
          expect(
            find.text(
              'Die HRV zeigt die RMSSD der Schlafsitzung. Fehlende oder neu zu berechnende Werte bleiben als Lücke sichtbar.',
            ),
            findsOneWidget,
          );
          expect(
            find.text(
              'Die Werte bestimmen weder eine Zyklusphase noch einen Eisprung.',
            ),
            findsOneWidget,
          );
          expect(inInfo('%'), findsNothing);
          expect(inInfo('Genauigkeit'), findsNothing);
        }

        Future<void> expectDefaultSourceDisclosure() async {
          await expectGenericInfoParas();
          await revealInfoText(inInfo('Ruhepuls · 15. Sept.'));
          expect(inInfo('Ruhepuls · 15. Sept.'), findsOneWidget);
          expect(
            inInfo('14. Sept., 16:00–15. Sept., 06:00 UTC'),
            findsOneWidget,
          );
          await revealInfoText(inInfo('HRV · 14. Sept.'));
          expect(inInfo('HRV · 14. Sept.'), findsOneWidget);
          expect(
            inInfo('13. Sept., 16:00–14. Sept., 06:00 UTC'),
            findsOneWidget,
          );
          expect(inInfo('Qualitätswert —'), findsWidgets);
          expect(
            inInfo(
              'Qualitätswerte sind gespeicherte Scores, keine Fehlerspannen.',
            ),
            findsOneWidget,
          );
          expect(inInfo('Qualitätswert 0,90 / 1'), findsNothing);
          await expectInfoClosePinned();
        }

        Future<_CycleReviewRepo> mountCycle({
          Brightness brightness = Brightness.light,
          double scale = 1,
          _CycleReviewRepo? repository,
          String? onDay,
        }) async {
          final repo = repository ?? await loadRepo();
          await tester.pumpWidget(
            reviewHost(
              brightness: brightness,
              scale: scale,
              home: OpenBandCycle(
                repository: repo,
                day: onDay ?? day,
                now: () => now,
                synthetic: true,
              ),
            ),
          );
          await pumpUntil(
            () =>
                cyclePage().evaluate().isNotEmpty ||
                find.text('Daten nicht geladen').evaluate().isNotEmpty,
            'Cycle main did not load.',
          );
          return repo;
        }

        Future<_CycleReviewRepo> mountMeasurements({
          Brightness brightness = Brightness.light,
          double scale = 1,
          _CycleReviewRepo? repository,
          String? onDay,
        }) async {
          final repo = repository ?? await loadRepo();
          await tester.pumpWidget(
            reviewHost(
              brightness: brightness,
              scale: scale,
              home: OpenBandCycleMeasurements(
                repository: repo,
                day: onDay ?? day,
                now: () => now,
                synthetic: true,
              ),
            ),
          );
          await pumpUntil(
            () => measurementsPage().evaluate().isNotEmpty,
            'Cycle measurements did not load.',
          );
          return repo;
        }

        Future<void> openMeasurementsFromCycle() async {
          await tapVisible(
            inRoute(cyclePage(), find.text('Messwerte')),
            cyclePage(),
          );
          await pumpUntil(
            () => measurementsPage().evaluate().isNotEmpty,
            'Measurements did not open from cycle.',
          );
          expect(measurementsPage(), findsOneWidget);
        }

        Future<void> expectPopulatedMain() async {
          final page = measurementsPage();
          expect(inRoute(page, find.text('Messwerte')), findsOneWidget);
          expect(inRoute(page, find.text('Zyklus')), findsOneWidget);
          expect(
            inRoute(page, find.text('24. Aug.–15. Sept.')),
            findsOneWidget,
          );
          expect(inRoute(page, find.text('Ruhepuls')), findsOneWidget);
          expect(inRoute(page, find.text('HRV')), findsOneWidget);
          expect(inRoute(page, find.text('19 von 23 Nächten')), findsOneWidget);
          expect(inRoute(page, find.text('16 von 23 Nächten')), findsOneWidget);
          expect(rhrPlot(), findsOneWidget);
          expect(hrvPlot(), findsOneWidget);
          expect(
            inRoute(metricCard(rhrPlot()), find.text('54')),
            findsOneWidget,
          );
          expect(
            inRoute(metricCard(rhrPlot()), find.text('bpm')),
            findsOneWidget,
          );
          expect(
            inRoute(metricCard(rhrPlot()), find.text('15. Sept.')),
            findsOneWidget,
          );
          expect(
            inRoute(metricCard(hrvPlot()), find.text('48')),
            findsOneWidget,
          );
          expect(
            inRoute(metricCard(hrvPlot()), find.text('ms')),
            findsOneWidget,
          );
          expect(
            inRoute(metricCard(hrvPlot()), find.text('14. Sept.')),
            findsOneWidget,
          );
          expect(inRoute(page, find.text('Tag 1')), findsWidgets);
          expect(inRoute(page, find.text('Tag 23')), findsWidgets);
          expect(
            inRoute(page, find.text('Synthetische Daten')),
            findsOneWidget,
          );
        }

        Future<void> expectPeriodSelected(String label) async {
          final sheet = measurementsChoiceSheet();
          expect(sheet, findsOneWidget);
          final rows = tester
              .widgetList<OBSettingsChoiceRow>(
                find.descendant(
                  of: sheet,
                  matching: find.byType(OBSettingsChoiceRow),
                ),
              )
              .toList();
          expect(rows, isNotEmpty);
          for (final row in rows) {
            if (row.label == label) {
              expect(row.selected, isTrue);
            } else {
              expect(row.selected, isFalse);
            }
          }
        }

        double plotLeftInset(Finder plot) {
          final scaler = MediaQuery.textScalerOf(tester.element(plot));
          return scaler.scale(14) > 20 ? 44.0 : 26.0;
        }

        Offset plotSlotOffset(Finder plot, int slot, int count) {
          final box = tester.getRect(plot);
          final left = plotLeftInset(plot);
          const right = 4.0;
          final usable = box.width - left - right;
          expect(usable, greaterThan(8.0));
          final x = count <= 1
              ? box.left + left + usable / 2
              : box.left + left + slot * usable / (count - 1);
          final point = Offset(x, box.center.dy);
          expect(box.contains(point), isTrue);
          return point;
        }

        Future<void> tapPlotSlot(Finder plot, int slot, int count) async {
          await ensureFullyInSafeViewport(measurementsPage(), plot);
          await tester.tapAt(plotSlotOffset(plot, slot, count));
          await tester.pump();
        }

        Future<void> dragPlotSlot(
          Finder plot,
          int fromSlot,
          int toSlot,
          int count,
        ) async {
          await ensureFullyInSafeViewport(measurementsPage(), plot);
          final from = plotSlotOffset(plot, fromSlot, count);
          final to = plotSlotOffset(plot, toSlot, count);
          await tester.timedDragFrom(
            from,
            to - from,
            const Duration(milliseconds: 280),
          );
          await tester.pump();
        }

        Future<void> expectSelectedGap(Finder plot) async {
          final card = metricCard(plot);
          expect(inRoute(card, find.text('29. Aug.')), findsOneWidget);
          expect(inRoute(card, find.text('—')), findsOneWidget);
          expect(inRoute(card, find.text('15. Sept.')), findsNothing);
          expect(inRoute(card, find.text('14. Sept.')), findsNothing);
        }

        // Root navigation to measurements and back.
        var repo = await loadRepo();
        await mountCycle(repository: repo);
        await ensureFullyInSafeViewport(
          cyclePage(),
          inRoute(cyclePage(), find.text('Messwerte')),
        );
        expect(
          tester.getTopLeft(inRoute(cyclePage(), find.text('Messwerte'))).dy,
          lessThan(
            tester.getTopLeft(inRoute(cyclePage(), find.text('Verlauf'))).dy,
          ),
        );
        await capture('cycle-measurements-root');
        await openMeasurementsFromCycle();
        await expectPopulatedMain();
        await scrollListToMin(measurementsPage());
        await capture('cycle-measurements-main');
        await popRoute();
        await pumpUntil(
          () => cyclePage().evaluate().isNotEmpty,
          'Cycle did not return from measurements.',
        );
        expect(measurementsPage(), findsNothing);
        expect(inRoute(cyclePage(), find.text('Messwerte')), findsOneWidget);
        expect(inRoute(cyclePage(), find.text('Verlauf')), findsOneWidget);
        await capture('cycle-measurements-root-back');

        repo = await loadRepo();
        await mountMeasurements(repository: repo, brightness: Brightness.dark);
        await expectPopulatedMain();
        await capture('cycle-measurements-main-dark');

        // Picker + actual prior-cycle selection (empty is correct).
        repo = await loadRepo();
        await mountMeasurements(repository: repo);
        await tapVisible(pickerRow(), measurementsPage());
        expect(measurementsChoiceSheet(), findsOneWidget);
        await expectPeriodSelected('24. Aug.–15. Sept.');
        expect(find.text('31. Juli–23. Aug.'), findsOneWidget);
        expect(find.text('29. Juni–30. Juli'), findsOneWidget);
        expect(find.text('1.–28. Juni'), findsOneWidget);
        await capture('cycle-measurements-picker');
        await tester.tap(find.text('31. Juli–23. Aug.'));
        await pumpAfterTap();
        expect(measurementsChoiceSheet(), findsNothing);
        expect(
          inRoute(measurementsPage(), find.text('31. Juli–23. Aug.')),
          findsOneWidget,
        );
        expect(
          inRoute(measurementsPage(), find.text('0 von 24 Nächten')),
          findsWidgets,
        );
        expect(inRoute(measurementsPage(), find.text('—')), findsWidgets);
        expect(rhrPlot(), findsNothing);
        expect(hrvPlot(), findsNothing);
        await capture('cycle-measurements-prior');

        repo = await loadRepo();
        await mountMeasurements(repository: repo, brightness: Brightness.dark);
        await tapVisible(pickerRow(), measurementsPage());
        await expectPeriodSelected('24. Aug.–15. Sept.');
        expect(find.text('31. Juli–23. Aug.').hitTestable(), findsOneWidget);
        await capture('cycle-measurements-picker-dark');
        await tester.tap(find.text('24. Aug.–15. Sept.').last);
        await pumpAfterTap();

        // Info open/close with independent selected-night source windows.
        repo = await loadRepo();
        await mountMeasurements(repository: repo);
        await tapVisible(infoButton(), measurementsPage());
        expect(find.text('Messwerte'), findsWidgets);
        await expectDefaultSourceDisclosure();
        await capture('cycle-measurements-info');
        await tester.tap(infoClose().hitTestable());
        await pumpAfterTap();
        expect(infoClose(), findsNothing);
        await expectPopulatedMain();

        await mountMeasurements(repository: repo, brightness: Brightness.dark);
        await tapVisible(infoButton(), measurementsPage());
        await expectDefaultSourceDisclosure();
        await capture('cycle-measurements-info-dark');
        await tester.tap(infoClose().hitTestable());
        await pumpAfterTap();

        repo = await loadRepo();
        repo.seedCycleNightSource(
          nightSource(
            onDay: '2026-09-15',
            rhr: kCyclePaperRhr[22],
            rhrConfidence: 0.9,
          ),
        );
        repo.seedCycleNightSource(
          nightSource(
            onDay: '2026-09-14',
            rhr: kCyclePaperRhr[21],
            hrv: kCyclePaperHrv[21],
            hrvConfidence: 0.9,
          ),
        );
        await mountMeasurements(repository: repo);
        await tapVisible(infoButton(), measurementsPage());
        await expectGenericInfoParas();
        await revealInfoText(inInfo('Ruhepuls · 15. Sept.'));
        expect(inInfo('Ruhepuls · 15. Sept.'), findsOneWidget);
        expect(inInfo('14. Sept., 16:00–15. Sept., 06:00 UTC'), findsOneWidget);
        await revealInfoText(inInfo('HRV · 14. Sept.'));
        expect(inInfo('HRV · 14. Sept.'), findsOneWidget);
        expect(inInfo('13. Sept., 16:00–14. Sept., 06:00 UTC'), findsOneWidget);
        expect(inInfo('Qualitätswert 0,90 / 1'), findsWidgets);
        expect(inInfo('Qualitätswert —'), findsNothing);
        expect(
          inInfo(
            'Qualitätswerte sind gespeicherte Scores, keine Fehlerspannen.',
          ),
          findsOneWidget,
        );
        await expectInfoClosePinned();
        await capture('cycle-measurements-info-quality');
        await tester.tap(infoClose().hitTestable());
        await pumpAfterTap();

        // Tap and drag each plot onto the missing 29 Aug slot.
        repo = await loadRepo();
        await mountMeasurements(repository: repo);
        await tapPlotSlot(rhrPlot(), 5, 23);
        await expectSelectedGap(rhrPlot());
        expect(inRoute(metricCard(hrvPlot()), find.text('48')), findsOneWidget);
        await dragPlotSlot(rhrPlot(), 22, 5, 23);
        await expectSelectedGap(rhrPlot());
        await capture('cycle-measurements-gap-rhr');
        await tapPlotSlot(hrvPlot(), 5, 23);
        await expectSelectedGap(hrvPlot());
        await expectSelectedGap(rhrPlot());
        await dragPlotSlot(hrvPlot(), 0, 5, 23);
        await expectSelectedGap(hrvPlot());
        await capture('cycle-measurements-gap-hrv');
        await tapVisible(infoButton(), measurementsPage());
        await expectGenericInfoParas();
        expect(inInfo('Ruhepuls · 29. Aug.'), findsNothing);
        expect(inInfo('HRV · 29. Aug.'), findsNothing);
        await tester.tap(infoClose().hitTestable());
        await pumpAfterTap();

        repo = await loadRepo();
        await mountMeasurements(repository: repo, brightness: Brightness.dark);
        await tapPlotSlot(rhrPlot(), 5, 23);
        await expectSelectedGap(rhrPlot());
        await tapPlotSlot(hrvPlot(), 5, 23);
        await expectSelectedGap(hrvPlot());
        await capture('cycle-measurements-gap-dark');

        // Metric empty.
        repo = await loadRepo();
        repo.clearCycleNightSources();
        await mountMeasurements(repository: repo);
        expect(
          inRoute(measurementsPage(), find.text('0 von 23 Nächten')),
          findsNWidgets(2),
        );
        expect(inRoute(measurementsPage(), find.text('—')), findsWidgets);
        expect(rhrPlot(), findsNothing);
        expect(hrvPlot(), findsNothing);
        await capture('cycle-measurements-empty');
        await mountMeasurements(repository: repo, brightness: Brightness.dark);
        expect(
          inRoute(measurementsPage(), find.text('0 von 23 Nächten')),
          findsNWidgets(2),
        );
        await capture('cycle-measurements-empty-dark');

        // One-point RHR, HRV absent.
        repo = await loadRepo();
        repo.clearCycleNightSources();
        repo.seedCycleNightSource(nightSource(onDay: '2026-09-15', rhr: 54));
        await mountMeasurements(repository: repo);
        expect(
          inRoute(measurementsPage(), find.text('1 von 23 Nächten')),
          findsOneWidget,
        );
        expect(
          inRoute(measurementsPage(), find.text('0 von 23 Nächten')),
          findsOneWidget,
        );
        expect(rhrPlot(), findsOneWidget);
        expect(inRoute(metricCard(rhrPlot()), find.text('54')), findsOneWidget);
        expect(
          inRoute(metricCard(rhrPlot()), find.text('15. Sept.')),
          findsOneWidget,
        );
        expect(hrvPlot(), findsNothing);
        expect(inRoute(measurementsPage(), find.text('—')), findsOneWidget);
        await capture('cycle-measurements-single');
        await mountMeasurements(repository: repo, brightness: Brightness.dark);
        expect(rhrPlot(), findsOneWidget);
        expect(hrvPlot(), findsNothing);
        await capture('cycle-measurements-single-dark');

        // Corrupt-row partial banner. Unreadable on a fixture gap night
        // keeps the 19/16 sample counts.
        repo = await loadRepo();
        repo.seedCycleNightSource(
          nightSource(onDay: '2026-08-29', unreadable: true),
        );
        await mountMeasurements(repository: repo);
        expect(
          inRoute(measurementsPage(), find.text('Daten teilweise lesbar')),
          findsOneWidget,
        );
        await expectPopulatedMain();
        await capture('cycle-measurements-partial');
        await mountMeasurements(repository: repo, brightness: Brightness.dark);
        expect(
          inRoute(measurementsPage(), find.text('Daten teilweise lesbar')),
          findsOneWidget,
        );
        await capture('cycle-measurements-partial-dark');

        // Read error + retry after clearing the flag.
        repo = await loadRepo();
        repo.failCycleMeasurementsRead = true;
        await mountMeasurements(repository: repo);
        expect(
          inRoute(measurementsPage(), find.text('Daten nicht geladen')),
          findsOneWidget,
        );
        expect(
          inRoute(measurementsPage(), find.text('Erneut versuchen')),
          findsOneWidget,
        );
        expect(rhrPlot(), findsNothing);
        await capture('cycle-measurements-read-error');
        final readsBeforeRetry = repo.measurementsReads;
        repo.failCycleMeasurementsRead = false;
        await tester.tap(
          inRoute(measurementsPage(), find.text('Erneut versuchen')),
        );
        await pumpAfterTap();
        await expectPopulatedMain();
        expect(repo.measurementsReads, greaterThan(readsBeforeRetry));
        await capture('cycle-measurements-read-error-retry');
        repo = await loadRepo();
        repo.failCycleMeasurementsRead = true;
        await mountMeasurements(repository: repo, brightness: Brightness.dark);
        expect(
          inRoute(measurementsPage(), find.text('Daten nicht geladen')),
          findsOneWidget,
        );
        await capture('cycle-measurements-read-error-dark');

        // Missing start.
        repo = await loadRepo();
        repo.clearCycleLogs();
        await mountCycle(repository: repo);
        await openMeasurementsFromCycle();
        expect(
          inRoute(measurementsPage(), find.text('Kein Zyklusbeginn')),
          findsOneWidget,
        );
        expect(
          inRoute(measurementsPage(), find.text('Zum Zyklus')),
          findsOneWidget,
        );
        await capture('cycle-measurements-no-start');
        await tester.tap(
          inRoute(measurementsPage(), find.text('Zum Zyklus')).hitTestable(),
        );
        await pumpAfterTap();
        await pumpUntil(
          () => cyclePage().evaluate().isNotEmpty,
          'No-start did not return to cycle.',
        );
        expect(measurementsPage(), findsNothing);
        await mountMeasurements(repository: repo, brightness: Brightness.dark);
        expect(
          inRoute(measurementsPage(), find.text('Kein Zyklusbeginn')),
          findsOneWidget,
        );
        await capture('cycle-measurements-no-start-dark');

        // Disabled action opens settings.
        repo = await loadRepo();
        repo.cycleSettings = const CycleSettings(
          enabled: false,
          estimatesEnabled: false,
          lengthReviewEnabled: false,
        );
        await mountMeasurements(repository: repo);
        expect(
          inRoute(measurementsPage(), find.text('Zyklus deaktiviert')),
          findsOneWidget,
        );
        expect(
          inRoute(measurementsPage(), find.text('Einstellungen')),
          findsOneWidget,
        );
        await capture('cycle-measurements-disabled');
        await tester.tap(
          inRoute(measurementsPage(), find.text('Einstellungen')).hitTestable(),
        );
        await pumpAfterTap();
        await pumpUntil(
          () => find
              .byKey(const ValueKey('cycle-settings'))
              .evaluate()
              .isNotEmpty,
          'Disabled action did not open settings.',
        );
        expect(find.byKey(const ValueKey('cycle-settings')), findsOneWidget);
        await capture('cycle-measurements-disabled-settings');
        await popRoute();
        await pumpUntil(
          () => measurementsPage().evaluate().isNotEmpty,
          'Settings did not return to measurements.',
        );
        repo = await loadRepo();
        repo.cycleSettings = const CycleSettings(
          enabled: false,
          estimatesEnabled: false,
          lengthReviewEnabled: false,
        );
        await mountMeasurements(repository: repo, brightness: Brightness.dark);
        expect(
          inRoute(measurementsPage(), find.text('Zyklus deaktiviert')),
          findsOneWidget,
        );
        await capture('cycle-measurements-disabled-dark');

        // Unreadable starts.
        repo = await loadRepo();
        repo.clearCycleLogs();
        repo.seedUnreadableCycleStart({'date': '2026-08-24', 'kind': 1});
        await mountCycle(repository: repo);
        await openMeasurementsFromCycle();
        expect(
          inRoute(measurementsPage(), find.text('Zyklusbeginn nicht lesbar')),
          findsOneWidget,
        );
        expect(
          inRoute(measurementsPage(), find.text('Zum Zyklus')),
          findsOneWidget,
        );
        await capture('cycle-measurements-unreadable');
        await tester.tap(
          inRoute(measurementsPage(), find.text('Zum Zyklus')).hitTestable(),
        );
        await pumpAfterTap();
        await pumpUntil(
          () => cyclePage().evaluate().isNotEmpty,
          'Unreadable-start did not return to cycle.',
        );
        expect(measurementsPage(), findsNothing);
        await mountMeasurements(repository: repo, brightness: Brightness.dark);
        expect(
          inRoute(measurementsPage(), find.text('Zyklusbeginn nicht lesbar')),
          findsOneWidget,
        );
        await capture('cycle-measurements-unreadable-dark');

        // Removed selected start: pick a start after it is gone so _load
        // keeps that identity and does not silently switch to the current cycle.
        repo = await loadRepo();
        await mountMeasurements(repository: repo);
        await repo.removeCycleStart(
          const CycleStart(date: '2026-07-31', kind: kCycleStartKind),
        );
        await tapVisible(pickerRow(), measurementsPage());
        expect(find.text('31. Juli–23. Aug.'), findsOneWidget);
        await tester.tap(find.text('31. Juli–23. Aug.'));
        await pumpAfterTap();
        await pumpUntil(
          () => find.text('Zyklus nicht mehr vorhanden').evaluate().isNotEmpty,
          'Removed start did not reload a typed reason.',
        );
        expect(
          inRoute(measurementsPage(), find.text('19 von 23 Nächten')),
          findsNothing,
        );
        expect(inRoute(measurementsPage(), find.text('54')), findsNothing);
        expect(find.text('Zyklus nicht mehr vorhanden'), findsOneWidget);
        expect(find.text('Zyklus wählen'), findsOneWidget);
        await capture('cycle-measurements-removed');
        await tester.tap(find.text('Zyklus wählen'));
        await pumpAfterTap();
        expect(measurementsChoiceSheet(), findsOneWidget);
        expect(find.text('24. Aug.–15. Sept.'), findsWidgets);
        expect(find.text('31. Juli–23. Aug.'), findsNothing);
        final removedRows = tester
            .widgetList<OBSettingsChoiceRow>(
              find.descendant(
                of: measurementsChoiceSheet(),
                matching: find.byType(OBSettingsChoiceRow),
              ),
            )
            .toList();
        expect(removedRows, isNotEmpty);
        for (final row in removedRows) {
          expect(row.selected, isFalse);
        }
        expect(find.text('24. Aug.–15. Sept.').hitTestable(), findsWidgets);
        await capture('cycle-measurements-removed-picker');
        repo = await loadRepo();
        await mountMeasurements(repository: repo, brightness: Brightness.dark);
        await repo.removeCycleStart(
          const CycleStart(date: '2026-07-31', kind: kCycleStartKind),
        );
        await tapVisible(pickerRow(), measurementsPage());
        await tester.tap(find.text('31. Juli–23. Aug.'));
        await pumpAfterTap();
        await pumpUntil(
          () => find.text('Zyklus nicht mehr vorhanden').evaluate().isNotEmpty,
          'Dark removed start did not show typed reason.',
        );
        await capture('cycle-measurements-removed-dark');

        // 120-night cap: May 1–Sept 15, Tag 19..138, one sample each.
        repo = await loadRepo();
        repo.clearCycleLogs();
        repo.clearCycleNightSources();
        repo.seedCycleStart(
          const CycleStart(date: '2026-05-01', kind: kCycleStartKind),
        );
        repo.seedCycleNightSource(nightSource(onDay: '2026-09-15', rhr: 54));
        repo.seedCycleNightSource(nightSource(onDay: '2026-09-14', hrv: 48));
        await mountMeasurements(repository: repo);
        expect(
          inRoute(measurementsPage(), find.text('1. Mai–15. Sept.')),
          findsOneWidget,
        );
        expect(
          inRoute(measurementsPage(), find.text('Letzte 120 Nächte')),
          findsOneWidget,
        );
        expect(
          inRoute(measurementsPage(), find.text('1 von 120 Nächten')),
          findsNWidgets(2),
        );
        expect(inRoute(measurementsPage(), find.text('Tag 19')), findsWidgets);
        expect(inRoute(measurementsPage(), find.text('Tag 138')), findsWidgets);
        expect(rhrPlot(), findsOneWidget);
        expect(hrvPlot(), findsOneWidget);
        expect(inRoute(metricCard(rhrPlot()), find.text('54')), findsOneWidget);
        expect(inRoute(metricCard(hrvPlot()), find.text('48')), findsOneWidget);
        await capture('cycle-measurements-truncated');
        await mountMeasurements(repository: repo, brightness: Brightness.dark);
        expect(
          inRoute(measurementsPage(), find.text('Letzte 120 Nächte')),
          findsOneWidget,
        );
        expect(inRoute(measurementsPage(), find.text('Tag 19')), findsWidgets);
        expect(inRoute(measurementsPage(), find.text('Tag 138')), findsWidgets);
        await capture('cycle-measurements-truncated-dark');

        // 375/2x light/dark main, lower HRV, picker/info safe area.
        repo = await loadRepo();
        await mountMeasurements(repository: repo, scale: 2);
        final main2x = measurementsPage();
        await ensureFullyInSafeViewport(
          main2x,
          inRoute(main2x, find.text('Ruhepuls')),
        );
        await scrollListToMin(main2x);
        await capture('cycle-measurements-main-2x');
        await ensureFullyInSafeViewport(main2x, hrvPlot());
        await capture('cycle-measurements-main-2x-hrv');
        await tapVisible(pickerRow(), main2x);
        final sheet2x = measurementsChoiceSheet();
        expect(sheet2x, findsOneWidget);
        await ensureFullyInSafeViewport(sheet2x, find.text('1.–28. Juni'));
        expect(
          rectInSafeViewport(
            tester.getRect(find.text('1.–28. Juni')),
            contentOf: sheet2x,
          ),
          isTrue,
        );
        await capture('cycle-measurements-picker-2x');
        await tapVisible(
          inRoute(sheet2x, find.text('24. Aug.–15. Sept.')),
          sheet2x,
        );
        await tapVisible(infoButton(), measurementsPage());
        await expectGenericInfoParas();
        await expectInfoClosePinned();
        await capture('cycle-measurements-info-2x');
        await revealInfoText(inInfo('Ruhepuls · 15. Sept.'));
        await revealInfoText(inInfo('HRV · 14. Sept.'));
        await revealInfoText(
          inInfo(
            'Qualitätswerte sind gespeicherte Scores, keine Fehlerspannen.',
          ),
        );
        expect(inInfo('14. Sept., 16:00–15. Sept., 06:00 UTC'), findsOneWidget);
        expect(inInfo('13. Sept., 16:00–14. Sept., 06:00 UTC'), findsOneWidget);
        expect(inInfo('Qualitätswert —'), findsWidgets);
        await expectInfoClosePinned();
        await capture('cycle-measurements-info-2x-source');
        await tester.tap(infoClose().hitTestable());
        await pumpAfterTap();
        expect(infoClose(), findsNothing);
        expect(tester.takeException(), isNull);

        await mountMeasurements(
          repository: repo,
          scale: 2,
          brightness: Brightness.dark,
        );
        await scrollListToMin(measurementsPage());
        await capture('cycle-measurements-main-2x-dark');
        await ensureFullyInSafeViewport(measurementsPage(), hrvPlot());
        await capture('cycle-measurements-main-2x-dark-hrv');
        await tapVisible(infoButton(), measurementsPage());
        await expectGenericInfoParas();
        await revealInfoText(inInfo('Ruhepuls · 15. Sept.'));
        await revealInfoText(inInfo('HRV · 14. Sept.'));
        expect(inInfo('14. Sept., 16:00–15. Sept., 06:00 UTC'), findsOneWidget);
        expect(inInfo('Qualitätswert —'), findsWidgets);
        await expectInfoClosePinned();
        await capture('cycle-measurements-info-2x-source-dark');
        await tester.tap(infoClose().hitTestable());
        await pumpAfterTap();
      }

      Future<void> reviewCycleObservations() async {
        final now = DateTime(2026, 9, 15, 9, 41);
        const day = SyntheticOpenBandRepository.cycleFixtureDay;

        void seedPaperObservations(
          _CycleReviewRepo target, {
          bool week5 = false,
        }) {
          const rows = <(String, List<String>)>[
            ('2026-06-01', ['cramps', 'fatigue']),
            ('2026-06-03', ['cramps']),
            ('2026-06-29', ['cramps', 'headache']),
            ('2026-07-02', ['fatigue']),
            ('2026-07-31', ['cramps']),
            ('2026-08-02', ['fatigue']),
            ('2026-08-24', ['headache']),
            ('2026-08-25', ['bloating']),
          ];
          for (final row in rows) {
            target.seedCycleObservation(
              CycleObservation(date: row.$1, tags: row.$2),
            );
          }
          if (week5) {
            target.seedCycleObservation(
              const CycleObservation(date: '2026-07-28', tags: ['nausea']),
            );
            target.seedCycleObservation(
              const CycleObservation(
                date: '2026-07-29',
                tags: [],
                note: 'felt off',
              ),
            );
          }
        }

        Future<_CycleReviewRepo> loadRepo({bool week5 = false}) async {
          Future<Map> load(String name) async =>
              jsonDecode(
                    await rootBundle.loadString(
                      'docs/openband5/assets/fixtures/$name.json',
                    ),
                  )
                  as Map;
          final repo = _CycleReviewRepo(
            await load('day-summary'),
            await load('sleep-detail'),
            activity: await load('additional-flows'),
            run: await load('run-detail'),
          );
          await repo.seedNutritionGoals();
          seedPaperObservations(repo, week5: week5);
          return repo;
        }

        Widget reviewHost({
          required Widget home,
          Brightness brightness = Brightness.light,
          double scale = 1,
        }) => MaterialApp(
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
          home: home,
        );

        Finder downScrollable(Finder ancestor) => find.descendant(
          of: ancestor,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        );

        Rect reviewSafeViewport({Finder? contentOf}) {
          final view = tester.view;
          final dpr = view.devicePixelRatio;
          final size = view.physicalSize / dpr;
          final pad = view.viewPadding;
          final screen = Rect.fromLTRB(
            pad.left / dpr,
            pad.top / dpr,
            size.width - pad.right / dpr,
            size.height - pad.bottom / dpr,
          );
          if (contentOf == null) return screen;
          final box = tester.getRect(downScrollable(contentOf).first);
          return Rect.fromLTRB(
            box.left < screen.left ? screen.left : box.left,
            box.top < screen.top ? screen.top : box.top,
            box.right > screen.right ? screen.right : box.right,
            box.bottom > screen.bottom ? screen.bottom : box.bottom,
          );
        }

        bool rectInSafeViewport(
          Rect box, {
          Finder? contentOf,
          double slop = 0.5,
        }) {
          final safe = reviewSafeViewport(contentOf: contentOf);
          return box.top >= safe.top - slop &&
              box.bottom <= safe.bottom + slop &&
              box.left >= safe.left - slop &&
              box.right <= safe.right + slop;
        }

        Future<void> revealIn(Finder ancestor, Finder target) async {
          final scrollable = downScrollable(ancestor).first;
          var scrolls = 0;
          var searchUp = true;
          while (target.evaluate().isEmpty ||
              target.hitTestable().evaluate().isEmpty) {
            if (scrolls >= 32) {
              throw FlutterError(
                'Control is not hit-testable after production scrolling.',
              );
            }
            if (target.evaluate().isEmpty) {
              final position = tester
                  .state<ScrollableState>(scrollable)
                  .position;
              final atMin = position.pixels <= position.minScrollExtent + 0.5;
              final atMax = position.pixels >= position.maxScrollExtent - 0.5;
              if (searchUp && atMin) searchUp = false;
              final dy = searchUp
                  ? (atMin ? 0.0 : 64.0)
                  : (atMax ? 0.0 : -64.0);
              if (dy == 0) {
                throw FlutterError(
                  'Control is not hit-testable after production scrolling.',
                );
              }
              await tester.drag(scrollable, Offset(0, dy));
              await tester.pump();
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
        }

        Future<void> ensureFullyInSafeViewport(
          Finder ancestor,
          Finder target,
        ) async {
          await revealIn(ancestor, target);
          final scrollable = downScrollable(ancestor).first;
          var extra = 0;
          while (!rectInSafeViewport(
            tester.getRect(target),
            contentOf: ancestor,
          )) {
            if (extra >= 32) {
              throw FlutterError(
                'Control is not fully within the safe viewport.',
              );
            }
            final box = tester.getRect(target);
            final safe = reviewSafeViewport(contentOf: ancestor);
            final overflowBottom = box.bottom - safe.bottom;
            final overflowTop = safe.top - box.top;
            if (extra == 0) {
              await Scrollable.ensureVisible(
                tester.element(target),
                alignment: overflowBottom >= overflowTop ? 1.0 : 0.0,
              );
              await tester.pump();
            } else {
              const minGesture = 64.0;
              final needed = overflowBottom > 0
                  ? -(overflowBottom + 8)
                  : overflowTop + 8;
              final dy = needed < 0
                  ? (needed > -minGesture ? -minGesture : needed)
                  : (needed < minGesture ? minGesture : needed);
              await tester.drag(scrollable, Offset(0, dy));
              await tester.pump();
            }
            extra++;
          }
          expect(target.hitTestable(), findsOneWidget);
        }

        Future<void> scrollListToMin(Finder ancestor) async {
          final scrollable = downScrollable(ancestor).first;
          var scrolls = 0;
          var pumps = 0;
          while (true) {
            final position = tester.state<ScrollableState>(scrollable).position;
            final min = position.minScrollExtent;
            final offset = position.pixels - min;
            final idle = !position.isScrollingNotifier.value;
            if (idle && offset.abs() <= 0.5) {
              expect(offset.abs(), lessThanOrEqualTo(0.5));
              return;
            }
            if (offset > 0.5) {
              if (++scrolls > 32) {
                throw FlutterError('ListView did not reach min scroll extent.');
              }
              await tester.drag(scrollable, const Offset(0, 64));
              await tester.pump();
              continue;
            }
            if (++pumps > 40) {
              throw FlutterError('ListView overscroll did not settle at min.');
            }
            await tester.pump(const Duration(milliseconds: 16));
          }
        }

        Future<void> pumpUntil(bool Function() ready, String message) async {
          await tester.pump();
          var waited = 0;
          while (!ready()) {
            if (++waited > 80) throw FlutterError(message);
            await tester.pump(const Duration(milliseconds: 16));
          }
          await reviewPumpPageTransitions(tester);
        }

        Future<void> pumpAfterTap() async {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await reviewPumpPageTransitions(tester);
        }

        Future<void> popRoute() async {
          await tester.tap(find.byTooltip('Zurück'));
          await reviewPumpPageTransitions(tester);
          await tester.pump();
        }

        Future<void> tapVisible(Finder target, Finder ancestor) async {
          await ensureFullyInSafeViewport(ancestor, target);
          await tester.tap(target.hitTestable());
          await pumpAfterTap();
        }

        Finder cyclePage() => find.byKey(const ValueKey('cycle-overview'));
        Finder observationsPage() =>
            find.byKey(const ValueKey('cycle-observations'));
        Finder pickerRow() =>
            find.byKey(const ValueKey('cycle-observations-picker'));
        Finder inRoute(Finder ancestor, Finder matching) =>
            find.descendant(of: ancestor, matching: matching);
        Finder infoButton() =>
            inRoute(observationsPage(), find.byTooltip('Information'));
        Finder observationsChoiceSheet() =>
            find.byType(OBSettingsChoiceSheet<int>);
        Finder infoBody() => find.byKey(const ValueKey('journal-info-body'));
        Finder infoClose() => find.widgetWithText(OBAction, 'Schließen');
        Finder inInfo(String text) => find.descendant(
          of: infoBody(),
          matching: find.textContaining(text),
        );

        Future<void> expectInfoClosePinned() async {
          expect(infoClose().hitTestable(), findsOneWidget);
          expect(rectInSafeViewport(tester.getRect(infoClose())), isTrue);
        }

        Future<_CycleReviewRepo> mountCycle({
          Brightness brightness = Brightness.light,
          double scale = 1,
          _CycleReviewRepo? repository,
          String? onDay,
        }) async {
          final repo = repository ?? await loadRepo();
          await tester.pumpWidget(
            reviewHost(
              brightness: brightness,
              scale: scale,
              home: OpenBandCycle(
                repository: repo,
                day: onDay ?? day,
                now: () => now,
                synthetic: true,
              ),
            ),
          );
          await pumpUntil(
            () =>
                cyclePage().evaluate().isNotEmpty ||
                find.text('Daten nicht geladen').evaluate().isNotEmpty,
            'Cycle main did not load.',
          );
          return repo;
        }

        Future<_CycleReviewRepo> mountObservations({
          Brightness brightness = Brightness.light,
          double scale = 1,
          _CycleReviewRepo? repository,
          String? onDay,
        }) async {
          final repo = repository ?? await loadRepo();
          await tester.pumpWidget(
            reviewHost(
              brightness: brightness,
              scale: scale,
              home: OpenBandCycleObservations(
                repository: repo,
                day: onDay ?? day,
                now: () => now,
                synthetic: true,
              ),
            ),
          );
          await pumpUntil(
            () => observationsPage().evaluate().isNotEmpty,
            'Cycle observations did not load.',
          );
          return repo;
        }

        Future<void> openObservationsFromCycle() async {
          await tapVisible(
            inRoute(cyclePage(), find.text('Beobachtungen')),
            cyclePage(),
          );
          await pumpUntil(
            () => observationsPage().evaluate().isNotEmpty,
            'Observations did not open from cycle.',
          );
          expect(observationsPage(), findsOneWidget);
        }

        Future<void> expectPopulatedMain() async {
          final page = observationsPage();
          expect(inRoute(page, find.text('Beobachtungen')), findsOneWidget);
          expect(inRoute(page, find.text('Zyklustage')), findsOneWidget);
          expect(inRoute(page, find.text('Tag 1–7')), findsOneWidget);
          expect(
            inRoute(page, find.text('8 Tage mit Beobachtungen')),
            findsOneWidget,
          );
          expect(
            inRoute(page, find.text('1. Juni–15. Sept. · 4 Zyklen')),
            findsOneWidget,
          );
          expect(inRoute(page, find.text('Krämpfe')), findsOneWidget);
          expect(inRoute(page, find.text('4 von 8')), findsOneWidget);
          expect(inRoute(page, find.text('Müdigkeit')), findsOneWidget);
          expect(inRoute(page, find.text('3 von 8')), findsOneWidget);
          expect(inRoute(page, find.text('Kopfschmerzen')), findsOneWidget);
          expect(inRoute(page, find.text('2 von 8')), findsOneWidget);
          expect(inRoute(page, find.text('Blähungen')), findsOneWidget);
          expect(inRoute(page, find.text('1 von 8')), findsOneWidget);
          expect(
            inRoute(page, find.text('Synthetische Daten')),
            findsOneWidget,
          );
        }

        Future<void> expectWeekSelected(String label) async {
          final sheet = observationsChoiceSheet();
          expect(sheet, findsOneWidget);
          final rows = tester
              .widgetList<OBSettingsChoiceRow>(
                find.descendant(
                  of: sheet,
                  matching: find.byType(OBSettingsChoiceRow),
                ),
              )
              .toList();
          expect(rows, isNotEmpty);
          for (final row in rows) {
            if (row.label == label) {
              expect(row.selected, isTrue);
            } else {
              expect(row.selected, isFalse);
            }
          }
        }

        Future<void> expectInfoParas() async {
          expect(
            find.text(
              'Gezählt werden nur Tage mit mindestens einer gespeicherten Beobachtung. Notizen allein und fehlende Einträge zählen nicht als symptomfreie Tage.',
            ),
            findsOneWidget,
          );
          expect(
            find.text(
              'Die Übersicht beginnt mit drei eingetragenen Zyklusbeginnen. Zyklustage zählen ab dem jeweils letzten eingetragenen Beginn. Der laufende Zyklus ist enthalten.',
            ),
            findsOneWidget,
          );
        }

        Finder infoLastParagraph() => find.text(
          'Die Übersicht beginnt mit drei eingetragenen Zyklusbeginnen. Zyklustage zählen ab dem jeweils letzten eingetragenen Beginn. Der laufende Zyklus ist enthalten.',
        );

        Future<void> scrollInfoBodyToEnd() async {
          final body = infoBody();
          expect(body, findsOneWidget);
          final scrollable = downScrollable(body).first;
          final position = tester.state<ScrollableState>(scrollable).position;
          final start = position.pixels;
          expect(position.maxScrollExtent, greaterThan(0.5));
          var drags = 0;
          while (position.pixels < position.maxScrollExtent - 0.5) {
            if (++drags > 32) {
              throw FlutterError(
                'Info body did not reach end after production scrolling.',
              );
            }
            await tester.drag(scrollable, const Offset(0, -64));
            await tester.pump();
            await expectInfoClosePinned();
          }
          expect(position.pixels, greaterThan(start));
          final last = infoLastParagraph();
          expect(last.hitTestable(), findsOneWidget);
          expect(inInfo('enthalten.'), findsOneWidget);
          final lastBox = tester.getRect(last);
          final bodyView = reviewSafeViewport(contentOf: body);
          expect(lastBox.bottom, lessThanOrEqualTo(bodyView.bottom + 8));
          await expectInfoClosePinned();
        }

        Future<void> openPickerSheet({double scale = 1}) async {
          await tapVisible(pickerRow(), observationsPage());
          final sheet = observationsChoiceSheet();
          expect(sheet, findsOneWidget);
          expect(find.text('Tag 1–7'), findsWidgets);
          expect(find.text('Tag 8–14'), findsOneWidget);
          expect(find.text('Tag 15–21'), findsOneWidget);
          expect(find.text('Tag 22–28'), findsOneWidget);
          expect(find.text('Tag 29–35'), findsOneWidget);
          await expectWeekSelected('Tag 1–7');
          if (scale > 1) {
            await ensureFullyInSafeViewport(sheet, find.text('Tag 29–35'));
            expect(
              rectInSafeViewport(
                tester.getRect(find.text('Tag 29–35')),
                contentOf: sheet,
              ),
              isTrue,
            );
          }
        }

        Future<void> capturePickerVariant({
          required String name,
          Brightness brightness = Brightness.light,
          double scale = 1,
        }) async {
          final repo = await loadRepo(week5: true);
          await mountObservations(
            repository: repo,
            brightness: brightness,
            scale: scale,
          );
          await openPickerSheet(scale: scale);
          await capture(name);
        }

        Future<void> captureInfoVariant({
          required String name,
          Brightness brightness = Brightness.light,
          double scale = 1,
          String? bodyName,
        }) async {
          final repo = await loadRepo();
          await mountObservations(
            repository: repo,
            brightness: brightness,
            scale: scale,
          );
          await tapVisible(infoButton(), observationsPage());
          await expectInfoParas();
          await expectInfoClosePinned();
          await capture(name);
          if (bodyName != null) {
            await scrollInfoBodyToEnd();
            await capture(bodyName);
          }
          await tester.tap(infoClose().hitTestable());
          await pumpAfterTap();
          expect(infoClose(), findsNothing);
        }

        Future<void> captureScaledMain({
          required Brightness brightness,
          required String topName,
          required String bottomName,
          required String pickerName,
          required String infoName,
          String? infoBodyName,
        }) async {
          final repo = await loadRepo(week5: true);
          await mountObservations(
            repository: repo,
            brightness: brightness,
            scale: 2,
          );
          final page = observationsPage();
          await scrollListToMin(page);
          await ensureFullyInSafeViewport(
            page,
            inRoute(page, find.text('Beobachtungen')),
          );
          expect(
            inRoute(page, find.text('Beobachtungen')).hitTestable(),
            findsOneWidget,
          );
          await capture(topName);
          await ensureFullyInSafeViewport(
            page,
            inRoute(page, find.text('Synthetische Daten')),
          );
          await capture(bottomName);
          await openPickerSheet(scale: 2);
          await capture(pickerName);
          await tapVisible(
            inRoute(observationsChoiceSheet(), find.text('Tag 1–7')),
            observationsChoiceSheet(),
          );
          await tapVisible(infoButton(), observationsPage());
          await expectInfoParas();
          await expectInfoClosePinned();
          await capture(infoName);
          if (infoBodyName != null) {
            await scrollInfoBodyToEnd();
            await capture(infoBodyName);
          }
          await tester.tap(infoClose().hitTestable());
          await pumpAfterTap();
          expect(infoClose(), findsNothing);
        }

        var repo = await loadRepo();
        await mountCycle(repository: repo);
        await ensureFullyInSafeViewport(
          cyclePage(),
          inRoute(cyclePage(), find.text('Beobachtungen')),
        );
        expect(
          tester.getTopLeft(inRoute(cyclePage(), find.text('Messwerte'))).dy,
          lessThan(
            tester
                .getTopLeft(inRoute(cyclePage(), find.text('Beobachtungen')))
                .dy,
          ),
        );
        expect(
          tester
              .getTopLeft(inRoute(cyclePage(), find.text('Beobachtungen')))
              .dy,
          lessThan(
            tester.getTopLeft(inRoute(cyclePage(), find.text('Verlauf'))).dy,
          ),
        );
        await capture('cycle-observations-root');
        await openObservationsFromCycle();
        await expectPopulatedMain();
        await scrollListToMin(observationsPage());
        await capture('cycle-observations-main');
        await popRoute();
        await pumpUntil(
          () => cyclePage().evaluate().isNotEmpty,
          'Cycle did not return from observations.',
        );
        expect(observationsPage(), findsNothing);
        expect(
          inRoute(cyclePage(), find.text('Beobachtungen')),
          findsOneWidget,
        );
        expect(inRoute(cyclePage(), find.text('Verlauf')), findsOneWidget);
        await capture('cycle-observations-root-back');

        repo = await loadRepo();
        await mountObservations(repository: repo, brightness: Brightness.dark);
        await expectPopulatedMain();
        await capture('cycle-observations-main-dark');

        repo = await loadRepo(week5: true);
        await mountObservations(repository: repo);
        await tapVisible(pickerRow(), observationsPage());
        expect(observationsChoiceSheet(), findsOneWidget);
        expect(find.text('Tag 1–7'), findsWidgets);
        expect(find.text('Tag 8–14'), findsOneWidget);
        expect(find.text('Tag 15–21'), findsOneWidget);
        expect(find.text('Tag 22–28'), findsOneWidget);
        expect(find.text('Tag 29–35'), findsOneWidget);
        await expectWeekSelected('Tag 1–7');
        await capture('cycle-observations-picker');
        await tester.tap(find.text('Tag 29–35'));
        await pumpAfterTap();
        expect(
          inRoute(observationsPage(), find.text('Tag 29–35')),
          findsOneWidget,
        );
        expect(
          inRoute(observationsPage(), find.text('1 Tag mit Beobachtungen')),
          findsOneWidget,
        );
        expect(
          inRoute(observationsPage(), find.text('Übelkeit')),
          findsOneWidget,
        );
        expect(
          inRoute(observationsPage(), find.text('1 von 1')),
          findsOneWidget,
        );
        expect(inRoute(observationsPage(), find.text('Krämpfe')), findsNothing);
        await capture('cycle-observations-week5');
        await tapVisible(pickerRow(), observationsPage());
        await tester.tap(find.text('Tag 8–14'));
        await pumpAfterTap();
        expect(
          inRoute(
            observationsPage(),
            find.text('Keine Einträge für diese Zyklustage'),
          ),
          findsOneWidget,
        );
        expect(
          inRoute(observationsPage(), find.text('Übelkeit')),
          findsNothing,
        );
        expect(inRoute(observationsPage(), find.text('Krämpfe')), findsNothing);
        await capture('cycle-observations-empty');

        repo = await loadRepo();
        repo.seedUnreadableCycleObservation({
          'date': '2026-09-10',
          'symptoms_json': '{',
        });
        await mountObservations(repository: repo);
        expect(
          inRoute(observationsPage(), find.text('Einträge teilweise lesbar')),
          findsOneWidget,
        );
        expect(
          inRoute(observationsPage(), find.text('8 Tage mit Beobachtungen')),
          findsOneWidget,
        );
        expect(
          inRoute(observationsPage(), find.text('4 von 8')),
          findsOneWidget,
        );
        await capture('cycle-observations-partial');
        await mountObservations(repository: repo, brightness: Brightness.dark);
        expect(
          inRoute(observationsPage(), find.text('Einträge teilweise lesbar')),
          findsOneWidget,
        );
        expect(
          inRoute(observationsPage(), find.text('8 Tage mit Beobachtungen')),
          findsOneWidget,
        );
        await capture('cycle-observations-partial-dark');

        repo = await loadRepo();
        repo.failCycleRead = true;
        await mountObservations(repository: repo);
        expect(
          inRoute(observationsPage(), find.text('Daten nicht geladen')),
          findsOneWidget,
        );
        expect(
          inRoute(observationsPage(), find.text('Erneut versuchen')),
          findsOneWidget,
        );
        await capture('cycle-observations-read-error');
        await mountObservations(repository: repo, brightness: Brightness.dark);
        expect(
          inRoute(observationsPage(), find.text('Daten nicht geladen')),
          findsOneWidget,
        );
        expect(
          inRoute(observationsPage(), find.text('Erneut versuchen')),
          findsOneWidget,
        );
        await capture('cycle-observations-read-error-dark');
        repo.failCycleRead = false;
        await tester.tap(
          inRoute(
            observationsPage(),
            find.text('Erneut versuchen'),
          ).hitTestable(),
        );
        await pumpAfterTap();
        await pumpUntil(
          () => find.text('8 Tage mit Beobachtungen').evaluate().isNotEmpty,
          'Retry did not reload observations.',
        );
        await expectPopulatedMain();
        await capture('cycle-observations-read-error-retry');

        repo = await loadRepo();
        repo.clearCycleLogs();
        repo.seedCycleStart(
          const CycleStart(date: '2026-08-24', kind: kCycleStartKind),
        );
        repo.seedCycleStart(
          const CycleStart(date: '2026-07-31', kind: kCycleStartKind),
        );
        await mountCycle(repository: repo);
        await openObservationsFromCycle();
        expect(
          inRoute(
            observationsPage(),
            find.text('Mindestens 3 Zyklusbeginne nötig'),
          ),
          findsOneWidget,
        );
        expect(
          inRoute(observationsPage(), find.text('Zum Zyklus')),
          findsOneWidget,
        );
        await capture('cycle-observations-insufficient');
        await tester.tap(
          inRoute(observationsPage(), find.text('Zum Zyklus')).hitTestable(),
        );
        await pumpAfterTap();
        await pumpUntil(
          () => cyclePage().evaluate().isNotEmpty,
          'Insufficient did not return to cycle.',
        );
        expect(observationsPage(), findsNothing);

        repo = await loadRepo();
        repo.cycleSettings = const CycleSettings(
          enabled: false,
          estimatesEnabled: false,
          lengthReviewEnabled: false,
        );
        await mountObservations(repository: repo);
        expect(
          inRoute(observationsPage(), find.text('Zyklus deaktiviert')),
          findsOneWidget,
        );
        expect(
          inRoute(observationsPage(), find.text('Einstellungen')),
          findsOneWidget,
        );
        await capture('cycle-observations-disabled');
        await tester.tap(
          inRoute(observationsPage(), find.text('Einstellungen')).hitTestable(),
        );
        await pumpAfterTap();
        await pumpUntil(
          () => find
              .byKey(const ValueKey('cycle-settings'))
              .evaluate()
              .isNotEmpty,
          'Disabled action did not open settings.',
        );
        expect(find.byKey(const ValueKey('cycle-settings')), findsOneWidget);
        await capture('cycle-observations-disabled-settings');
        await popRoute();
        await pumpUntil(
          () => observationsPage().evaluate().isNotEmpty,
          'Settings did not return to observations.',
        );

        repo = await loadRepo();
        repo.clearCycleLogs();
        repo.seedUnreadableCycleStart({'date': '2026-08-24', 'kind': 1});
        await mountCycle(repository: repo);
        await openObservationsFromCycle();
        expect(
          inRoute(observationsPage(), find.text('Zyklusbeginn nicht lesbar')),
          findsOneWidget,
        );
        expect(
          inRoute(observationsPage(), find.text('Zum Zyklus')),
          findsOneWidget,
        );
        await capture('cycle-observations-unreadable');
        await tester.tap(
          inRoute(observationsPage(), find.text('Zum Zyklus')).hitTestable(),
        );
        await pumpAfterTap();
        await pumpUntil(
          () => cyclePage().evaluate().isNotEmpty,
          'Unreadable-start did not return to cycle.',
        );
        expect(observationsPage(), findsNothing);
        await mountObservations(repository: repo, brightness: Brightness.dark);
        expect(
          inRoute(observationsPage(), find.text('Zyklusbeginn nicht lesbar')),
          findsOneWidget,
        );
        await capture('cycle-observations-unreadable-dark');

        repo = await loadRepo();
        await mountObservations(repository: repo);
        await tapVisible(infoButton(), observationsPage());
        await expectInfoParas();
        await expectInfoClosePinned();
        await capture('cycle-observations-info');
        await tester.tap(infoClose().hitTestable());
        await pumpAfterTap();
        expect(infoClose(), findsNothing);
        await captureInfoVariant(
          name: 'cycle-observations-info-dark',
          brightness: Brightness.dark,
        );
        await capturePickerVariant(
          name: 'cycle-observations-picker-dark',
          brightness: Brightness.dark,
        );

        await captureScaledMain(
          brightness: Brightness.light,
          topName: 'cycle-observations-main-2x-top',
          bottomName: 'cycle-observations-main-2x',
          pickerName: 'cycle-observations-picker-2x',
          infoName: 'cycle-observations-info-2x',
          infoBodyName: 'cycle-observations-info-2x-body',
        );
        await captureScaledMain(
          brightness: Brightness.dark,
          topName: 'cycle-observations-main-2x-dark-top',
          bottomName: 'cycle-observations-main-2x-dark',
          pickerName: 'cycle-observations-picker-2x-dark',
          infoName: 'cycle-observations-info-2x-dark',
        );
        expect(tester.takeException(), isNull);
      }

      Future<void> reviewCycleGaps() async {
        final now = DateTime(2026, 9, 15, 9, 41);
        const day = '2026-09-15';
        const paperStarts = [
          '2025-09-14',
          '2025-10-12',
          '2025-11-11',
          '2025-12-08',
          '2026-01-06',
          '2026-02-03',
          '2026-03-06',
          '2026-04-01',
          '2026-05-01',
          '2026-05-29',
          '2026-06-30',
          '2026-07-27',
          '2026-08-24',
        ];

        void seedPaperGaps(
          _CycleReviewRepo target, {
          bool earlier = false,
          bool display = true,
          bool enabled = true,
        }) {
          target.clearCycleLogs();
          if (earlier) {
            target.seedCycleStart(
              const CycleStart(date: '2025-08-17', kind: kCycleStartKind),
            );
          }
          for (final date in paperStarts) {
            target.seedCycleStart(
              CycleStart(date: date, kind: kCycleStartKind),
            );
          }
          target.cycleSettings = CycleSettings(
            enabled: enabled,
            estimatesEnabled: true,
            lengthReviewEnabled: display,
          );
        }

        Future<_CycleReviewRepo> loadRepo({
          bool earlier = false,
          bool display = true,
          bool enabled = true,
        }) async {
          Future<Map> load(String name) async =>
              jsonDecode(
                    await rootBundle.loadString(
                      'docs/openband5/assets/fixtures/$name.json',
                    ),
                  )
                  as Map;
          final repo = _CycleReviewRepo(
            await load('day-summary'),
            await load('sleep-detail'),
            activity: await load('additional-flows'),
            run: await load('run-detail'),
          );
          await repo.seedNutritionGoals();
          seedPaperGaps(
            repo,
            earlier: earlier,
            display: display,
            enabled: enabled,
          );
          return repo;
        }

        Widget reviewHost({
          required Widget home,
          Brightness brightness = Brightness.light,
          double scale = 1,
        }) => MaterialApp(
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
          home: home,
        );

        Finder downScrollable(Finder ancestor) => find.descendant(
          of: ancestor,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        );

        Rect reviewSafeViewport({Finder? contentOf}) {
          final view = tester.view;
          final dpr = view.devicePixelRatio;
          final size = view.physicalSize / dpr;
          final pad = view.viewPadding;
          final screen = Rect.fromLTRB(
            pad.left / dpr,
            pad.top / dpr,
            size.width - pad.right / dpr,
            size.height - pad.bottom / dpr,
          );
          if (contentOf == null) return screen;
          final box = tester.getRect(downScrollable(contentOf).first);
          return Rect.fromLTRB(
            box.left < screen.left ? screen.left : box.left,
            box.top < screen.top ? screen.top : box.top,
            box.right > screen.right ? screen.right : box.right,
            box.bottom > screen.bottom ? screen.bottom : box.bottom,
          );
        }

        bool rectInSafeViewport(
          Rect box, {
          Finder? contentOf,
          double slop = 0.5,
        }) {
          final safe = reviewSafeViewport(contentOf: contentOf);
          return box.top >= safe.top - slop &&
              box.bottom <= safe.bottom + slop &&
              box.left >= safe.left - slop &&
              box.right <= safe.right + slop;
        }

        Future<void> revealIn(Finder ancestor, Finder target) async {
          final scrollable = downScrollable(ancestor).first;
          var scrolls = 0;
          var searchUp = true;
          while (target.evaluate().isEmpty ||
              target.hitTestable().evaluate().isEmpty) {
            if (scrolls >= 32) {
              throw FlutterError(
                'Control is not hit-testable after production scrolling.',
              );
            }
            if (target.evaluate().isEmpty) {
              final position = tester
                  .state<ScrollableState>(scrollable)
                  .position;
              final atMin = position.pixels <= position.minScrollExtent + 0.5;
              final atMax = position.pixels >= position.maxScrollExtent - 0.5;
              if (searchUp && atMin) searchUp = false;
              final dy = searchUp
                  ? (atMin ? 0.0 : 64.0)
                  : (atMax ? 0.0 : -64.0);
              if (dy == 0) {
                throw FlutterError(
                  'Control is not hit-testable after production scrolling.',
                );
              }
              await tester.drag(scrollable, Offset(0, dy));
              await tester.pump();
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
        }

        Future<void> ensureFullyInSafeViewport(
          Finder ancestor,
          Finder target,
        ) async {
          await revealIn(ancestor, target);
          final scrollable = downScrollable(ancestor).first;
          var extra = 0;
          while (!rectInSafeViewport(
            tester.getRect(target),
            contentOf: ancestor,
          )) {
            if (extra >= 32) {
              throw FlutterError(
                'Control is not fully within the safe viewport.',
              );
            }
            final box = tester.getRect(target);
            final safe = reviewSafeViewport(contentOf: ancestor);
            final overflowBottom = box.bottom - safe.bottom;
            final overflowTop = safe.top - box.top;
            if (extra == 0) {
              await Scrollable.ensureVisible(
                tester.element(target),
                alignment: overflowBottom >= overflowTop ? 1.0 : 0.0,
              );
              await tester.pump();
            } else {
              const minGesture = 64.0;
              final needed = overflowBottom > 0
                  ? -(overflowBottom + 8)
                  : overflowTop + 8;
              final dy = needed < 0
                  ? (needed > -minGesture ? -minGesture : needed)
                  : (needed < minGesture ? minGesture : needed);
              await tester.drag(scrollable, Offset(0, dy));
              await tester.pump();
            }
            extra++;
          }
          expect(target.hitTestable(), findsOneWidget);
        }

        Future<void> scrollListToMin(Finder ancestor) async {
          final scrollable = downScrollable(ancestor).first;
          var scrolls = 0;
          var pumps = 0;
          while (true) {
            final position = tester.state<ScrollableState>(scrollable).position;
            final min = position.minScrollExtent;
            final offset = position.pixels - min;
            final idle = !position.isScrollingNotifier.value;
            if (idle && offset.abs() <= 0.5) {
              expect(offset.abs(), lessThanOrEqualTo(0.5));
              return;
            }
            if (offset > 0.5) {
              if (++scrolls > 32) {
                throw FlutterError('ListView did not reach min scroll extent.');
              }
              await tester.drag(scrollable, const Offset(0, 64));
              await tester.pump();
              continue;
            }
            if (++pumps > 40) {
              throw FlutterError('ListView overscroll did not settle at min.');
            }
            await tester.pump(const Duration(milliseconds: 16));
          }
        }

        Future<void> pumpUntil(bool Function() ready, String message) async {
          await tester.pump();
          var waited = 0;
          while (!ready()) {
            if (++waited > 80) throw FlutterError(message);
            await tester.pump(const Duration(milliseconds: 16));
          }
          await reviewPumpPageTransitions(tester);
        }

        Future<void> pumpAfterTap() async {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await reviewPumpPageTransitions(tester);
        }

        Future<void> popRoute() async {
          await tester.tap(find.byTooltip('Zurück'));
          await reviewPumpPageTransitions(tester);
          await tester.pump();
        }

        Future<void> tapVisible(Finder target, Finder ancestor) async {
          await ensureFullyInSafeViewport(ancestor, target);
          await tester.tap(target.hitTestable());
          await pumpAfterTap();
        }

        Finder cyclePage() => find.byKey(const ValueKey('cycle-overview'));
        Finder gapsPage() => find.byKey(const ValueKey('cycle-gaps'));
        Finder pickerRow() => find.byKey(const ValueKey('cycle-gaps-picker'));
        Finder plot() => find.byKey(const ValueKey('cycle-gaps-plot'));
        Finder inRoute(Finder ancestor, Finder matching) =>
            find.descendant(of: ancestor, matching: matching);
        Finder infoButton() =>
            inRoute(gapsPage(), find.byTooltip('Information'));
        Finder gapsChoiceSheet() => find.byType(OBSettingsChoiceSheet<int>);
        Finder infoBody() => find.byKey(const ValueKey('journal-info-body'));
        Finder infoClose() => find.widgetWithText(OBAction, 'Schließen');
        Finder toggleSwitch(String label) => find.descendant(
          of: find.widgetWithText(OBSettingsToggleRow, label),
          matching: find.byType(CupertinoSwitch),
        );

        Future<void> expectInfoClosePinned() async {
          expect(infoClose().hitTestable(), findsOneWidget);
          expect(rectInSafeViewport(tester.getRect(infoClose())), isTrue);
        }

        Future<_CycleReviewRepo> mountCycle({
          Brightness brightness = Brightness.light,
          double scale = 1,
          _CycleReviewRepo? repository,
        }) async {
          final repo = repository ?? await loadRepo();
          await tester.pumpWidget(
            reviewHost(
              brightness: brightness,
              scale: scale,
              home: OpenBandCycle(
                repository: repo,
                day: day,
                now: () => now,
                synthetic: true,
              ),
            ),
          );
          await pumpUntil(
            () => cyclePage().evaluate().isNotEmpty,
            'Cycle main did not load.',
          );
          return repo;
        }

        Future<_CycleReviewRepo> mountGaps({
          Brightness brightness = Brightness.light,
          double scale = 1,
          _CycleReviewRepo? repository,
        }) async {
          final repo = repository ?? await loadRepo();
          await tester.pumpWidget(
            reviewHost(
              brightness: brightness,
              scale: scale,
              home: OpenBandCycleGaps(
                repository: repo,
                day: day,
                now: () => now,
                synthetic: true,
              ),
            ),
          );
          await pumpUntil(
            () => gapsPage().evaluate().isNotEmpty,
            'Cycle gaps did not load.',
          );
          return repo;
        }

        Future<void> openGapsFromCycle() async {
          await tapVisible(
            inRoute(cyclePage(), find.text('Abstände')),
            cyclePage(),
          );
          await pumpUntil(
            () => gapsPage().evaluate().isNotEmpty,
            'Gaps did not open from cycle.',
          );
          expect(gapsPage(), findsOneWidget);
        }

        Future<void> expectPopulatedMain({bool subset = false}) async {
          final page = gapsPage();
          expect(inRoute(page, find.text('Abstände')), findsOneWidget);
          expect(inRoute(page, find.text('Zeitraum')), findsOneWidget);
          expect(
            inRoute(page, find.text('Sept. 2025–Aug. 2026')),
            findsOneWidget,
          );
          expect(
            inRoute(
              page,
              find.text(subset ? '12 von 13 Abständen' : '12 Abstände'),
            ),
            findsOneWidget,
          );
          expect(inRoute(page, find.text('28')), findsWidgets);
          expect(inRoute(page, find.text('27. Juli–24. Aug.')), findsOneWidget);
          expect(inRoute(page, find.text('12. Okt. 2025')), findsOneWidget);
          expect(inRoute(page, find.text('24. Aug. 2026')), findsOneWidget);
          expect(
            inRoute(page, find.text('Synthetische Daten')),
            findsOneWidget,
          );
        }

        Offset barSlot(Finder target, int slot, int count, {double scale = 1}) {
          final box = tester.getRect(target);
          final left = 28 + 16 * (scale - 1);
          final right = 4 + 4 * (scale - 1);
          final step = (box.width - left - right) / count;
          return Offset(box.left + left + (slot + 0.5) * step, box.center.dy);
        }

        Future<void> expectInfoParas() async {
          expect(
            find.text(
              'Abstände zählen die Kalendertage zwischen zwei eingetragenen Beginnen. Der laufende Zyklus ist noch nicht enthalten.',
            ),
            findsOneWidget,
          );
          expect(
            find.text(
              'Die Ansicht ist optional und benötigt zwölf Abstände. Bei mehr als 60 Tagen oder einem nicht lesbaren Beginn bleibt sie offen. Ein fehlender Beginn lässt sich nicht von einem längeren Zyklus unterscheiden.',
            ),
            findsOneWidget,
          );
        }

        Finder infoLastParagraph() => find.text(
          'Die Ansicht ist optional und benötigt zwölf Abstände. Bei mehr als 60 Tagen oder einem nicht lesbaren Beginn bleibt sie offen. Ein fehlender Beginn lässt sich nicht von einem längeren Zyklus unterscheiden.',
        );

        Future<void> scrollInfoBodyToEnd() async {
          final body = infoBody();
          expect(body, findsOneWidget);
          final scrollable = downScrollable(body).first;
          final position = tester.state<ScrollableState>(scrollable).position;
          final start = position.pixels;
          expect(position.maxScrollExtent, greaterThan(0.5));
          var drags = 0;
          while (position.pixels < position.maxScrollExtent - 0.5) {
            if (++drags > 32) {
              throw FlutterError(
                'Info body did not reach end after production scrolling.',
              );
            }
            await tester.drag(scrollable, const Offset(0, -64));
            await tester.pump();
            await expectInfoClosePinned();
          }
          expect(position.pixels, greaterThan(start));
          final last = infoLastParagraph();
          expect(last.hitTestable(), findsOneWidget);
        }

        var repo = await loadRepo();
        await mountCycle(repository: repo);
        await ensureFullyInSafeViewport(
          cyclePage(),
          inRoute(cyclePage(), find.text('Abstände')),
        );
        expect(
          tester
              .getTopLeft(inRoute(cyclePage(), find.text('Beobachtungen')))
              .dy,
          lessThan(
            tester.getTopLeft(inRoute(cyclePage(), find.text('Abstände'))).dy,
          ),
        );
        expect(
          tester.getTopLeft(inRoute(cyclePage(), find.text('Abstände'))).dy,
          lessThan(
            tester.getTopLeft(inRoute(cyclePage(), find.text('Verlauf'))).dy,
          ),
        );
        await capture('cycle-gaps-root');
        await openGapsFromCycle();
        await expectPopulatedMain();
        await capture('cycle-gaps-main');
        await popRoute();
        await pumpUntil(
          () => cyclePage().evaluate().isNotEmpty,
          'Did not return to cycle.',
        );
        expect(gapsPage(), findsNothing);
        await capture('cycle-gaps-root-back');

        repo = await loadRepo();
        await mountGaps(repository: repo, brightness: Brightness.dark);
        await expectPopulatedMain();
        await capture('cycle-gaps-main-dark');

        repo = await loadRepo();
        await mountGaps(repository: repo);
        await tester.tapAt(barSlot(plot(), 9, 12));
        await tester.pump();
        expect(inRoute(gapsPage(), find.text('32')), findsOneWidget);
        expect(
          inRoute(gapsPage(), find.text('29. Mai–30. Juni')),
          findsOneWidget,
        );
        await capture('cycle-gaps-selected');

        repo = await loadRepo(earlier: true);
        await mountGaps(repository: repo);
        await expectPopulatedMain(subset: true);
        await tapVisible(pickerRow(), gapsPage());
        expect(gapsChoiceSheet(), findsOneWidget);
        expect(find.text('Sept. 2025–Aug. 2026'), findsWidgets);
        expect(find.text('Aug.–Sept. 2025'), findsOneWidget);
        await capture('cycle-gaps-picker');
        await tapVisible(
          inRoute(gapsChoiceSheet(), find.text('Aug.–Sept. 2025')),
          gapsChoiceSheet(),
        );
        expect(
          inRoute(gapsPage(), find.text('1 von 13 Abständen')),
          findsOneWidget,
        );
        expect(
          inRoute(gapsPage(), find.text('17. Aug.–14. Sept.')),
          findsOneWidget,
        );
        await capture('cycle-gaps-earlier');

        repo = await loadRepo(earlier: true);
        await mountGaps(repository: repo, brightness: Brightness.dark);
        await tapVisible(pickerRow(), gapsPage());
        await capture('cycle-gaps-picker-dark');

        repo = await loadRepo(display: false);
        await mountGaps(repository: repo);
        expect(
          inRoute(gapsPage(), find.text('Abstände ausgeblendet')),
          findsOneWidget,
        );
        await capture('cycle-gaps-off');

        repo = await loadRepo(enabled: false);
        await mountGaps(repository: repo);
        expect(
          inRoute(gapsPage(), find.text('Zyklus deaktiviert')),
          findsOneWidget,
        );
        await capture('cycle-gaps-disabled');
        await tapVisible(
          inRoute(gapsPage(), find.text('Einstellungen')),
          gapsPage(),
        );
        await pumpUntil(
          () => find
              .byKey(const ValueKey('cycle-settings'))
              .evaluate()
              .isNotEmpty,
          'Disabled action did not open settings.',
        );
        expect(find.text('Abstände anzeigen'), findsOneWidget);
        await capture('cycle-gaps-disabled-settings');
        await popRoute();

        repo = await loadRepo();
        repo.clearCycleLogs();
        repo.seedCycleStart(
          const CycleStart(date: '2026-08-24', kind: kCycleStartKind),
        );
        await mountCycle(repository: repo);
        await openGapsFromCycle();
        expect(
          inRoute(gapsPage(), find.text('Mindestens 12 Abstände nötig')),
          findsOneWidget,
        );
        await capture('cycle-gaps-insufficient');
        await tapVisible(
          inRoute(gapsPage(), find.text('Zum Zyklus')),
          gapsPage(),
        );
        await pumpUntil(
          () => cyclePage().evaluate().isNotEmpty,
          'Insufficient did not return to cycle.',
        );

        repo = await loadRepo();
        repo.clearCycleLogs();
        repo.seedUnreadableCycleStart({'date': '2026-08-24', 'kind': 1});
        await mountCycle(repository: repo);
        await openGapsFromCycle();
        expect(
          inRoute(gapsPage(), find.text('Zyklusbeginn nicht lesbar')),
          findsOneWidget,
        );
        await capture('cycle-gaps-unreadable');
        await mountGaps(repository: repo, brightness: Brightness.dark);
        await capture('cycle-gaps-unreadable-dark');

        repo = await loadRepo();
        repo.clearCycleLogs();
        repo.seedCycleStart(
          const CycleStart(date: '2026-06-01', kind: kCycleStartKind),
        );
        repo.seedCycleStart(
          const CycleStart(date: '2026-08-24', kind: kCycleStartKind),
        );
        await mountGaps(repository: repo);
        expect(
          inRoute(gapsPage(), find.text('Abstand über 60 Tage')),
          findsOneWidget,
        );
        await capture('cycle-gaps-long-gap');

        repo = await loadRepo();
        repo.failCycleLogRead = true;
        await mountGaps(repository: repo);
        expect(find.text('Daten nicht geladen'), findsOneWidget);
        await capture('cycle-gaps-read-error');
        repo.failCycleLogRead = false;
        await tapVisible(find.text('Erneut versuchen'), gapsPage());
        await expectPopulatedMain();
        await capture('cycle-gaps-read-error-retry');
        repo.failCycleLogRead = true;
        await mountGaps(repository: repo, brightness: Brightness.dark);
        await capture('cycle-gaps-read-error-dark');

        repo = await loadRepo();
        await mountGaps(repository: repo);
        await tapVisible(infoButton(), gapsPage());
        await expectInfoParas();
        await expectInfoClosePinned();
        await capture('cycle-gaps-info');
        await tester.tap(infoClose().hitTestable());
        await pumpAfterTap();
        repo = await loadRepo();
        await mountGaps(repository: repo, brightness: Brightness.dark);
        await tapVisible(infoButton(), gapsPage());
        await capture('cycle-gaps-info-dark');
        await tester.tap(infoClose().hitTestable());
        await pumpAfterTap();

        repo = await loadRepo();
        await tester.pumpWidget(
          reviewHost(
            home: OpenBandCycleSettings(
              repository: repo,
              now: () => now,
              synthetic: true,
            ),
          ),
        );
        await pumpUntil(
          () => find
              .byKey(const ValueKey('cycle-settings'))
              .evaluate()
              .isNotEmpty,
          'Settings did not load.',
        );
        expect(
          tester
              .widget<CupertinoSwitch>(toggleSwitch('Abstände anzeigen'))
              .value,
          isTrue,
        );
        await capture('cycle-gaps-settings');
        await tester.tap(toggleSwitch('Abstände anzeigen'));
        await pumpAfterTap();
        expect(repo.cycleSettings.lengthReviewEnabled, isFalse);
        await capture('cycle-gaps-settings-off');
        repo.failCycleContextRefresh = true;
        await tester.tap(toggleSwitch('Abstände anzeigen'));
        await pumpAfterTap();
        expect(repo.cycleSettings.lengthReviewEnabled, isTrue);
        expect(
          find.text('Gespeichert · Aktualisieren fehlgeschlagen'),
          findsOneWidget,
        );
        await capture('cycle-gaps-settings-refresh');

        repo = await loadRepo(earlier: true);
        await mountGaps(repository: repo, scale: 2);
        final page = gapsPage();
        await scrollListToMin(page);
        await capture('cycle-gaps-main-2x-top');
        await ensureFullyInSafeViewport(
          page,
          inRoute(page, find.text('Synthetische Daten')),
        );
        await capture('cycle-gaps-main-2x');
        await tapVisible(pickerRow(), page);
        await capture('cycle-gaps-picker-2x');
        await tapVisible(
          inRoute(gapsChoiceSheet(), find.text('Sept. 2025–Aug. 2026')).last,
          gapsChoiceSheet(),
        );
        await tapVisible(infoButton(), gapsPage());
        await expectInfoParas();
        await expectInfoClosePinned();
        await capture('cycle-gaps-info-2x');
        await scrollInfoBodyToEnd();
        await capture('cycle-gaps-info-2x-body');
        await tester.tap(infoClose().hitTestable());
        await pumpAfterTap();
        expect(find.text('Schließen'), findsNothing);
        expect(
          inRoute(gapsPage(), find.text('Synthetische Daten')),
          findsOneWidget,
        );

        repo = await loadRepo();
        await mountGaps(
          repository: repo,
          brightness: Brightness.dark,
          scale: 2,
        );
        await capture('cycle-gaps-main-2x-dark');
        await tapVisible(infoButton(), gapsPage());
        await expectInfoParas();
        await expectInfoClosePinned();
        await capture('cycle-gaps-info-2x-dark');
        await scrollInfoBodyToEnd();
        await capture('cycle-gaps-info-2x-dark-body');
        await tester.tap(infoClose().hitTestable());
        await pumpAfterTap();
        expect(find.text('Schließen'), findsNothing);
        expect(infoClose(), findsNothing);

        repo = await loadRepo(earlier: true);
        await mountGaps(
          repository: repo,
          brightness: Brightness.dark,
          scale: 2,
        );
        await tapVisible(pickerRow(), gapsPage());
        expect(gapsChoiceSheet(), findsOneWidget);
        expect(find.text('Sept. 2025–Aug. 2026'), findsWidgets);
        expect(find.text('Aug.–Sept. 2025'), findsOneWidget);
        await capture('cycle-gaps-picker-2x-dark');
        expect(tester.takeException(), isNull);
      }

      Future<void> reviewCycleMedians() async {
        final now = DateTime(2026, 9, 15, 9, 41);
        const day = '2026-09-15';

        Future<_CycleReviewRepo> loadRepo() async {
          Future<Map> load(String name) async =>
              jsonDecode(
                    await rootBundle.loadString(
                      'docs/openband5/assets/fixtures/$name.json',
                    ),
                  )
                  as Map;
          final repo = _CycleReviewRepo(
            await load('day-summary'),
            await load('sleep-detail'),
            activity: await load('additional-flows'),
            run: await load('run-detail'),
          );
          await repo.seedNutritionGoals();
          repo.seedCycleMedianFixture();
          return repo;
        }

        Widget reviewHost({
          required Widget home,
          Brightness brightness = Brightness.light,
          double scale = 1,
        }) => MaterialApp(
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
          home: home,
        );

        Future<void> pumpUntil(bool Function() ready, String message) async {
          await tester.pump();
          var waited = 0;
          while (!ready()) {
            if (++waited > 80) throw FlutterError(message);
            await tester.pump(const Duration(milliseconds: 16));
          }
          await reviewPumpPageTransitions(tester);
        }

        Future<void> pumpAfterTap() async {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await reviewPumpPageTransitions(tester);
        }

        Future<void> popRoute() async {
          await tester.tap(find.byTooltip('Zurück'));
          await reviewPumpPageTransitions(tester);
          await tester.pump();
        }

        Finder cyclePage() => find.byKey(const ValueKey('cycle-overview'));
        Finder mediansPage() => find.byKey(const ValueKey('cycle-medians'));
        Finder rhrPlot() =>
            find.byKey(const ValueKey('cycle-medians-rhr-plot'));
        Finder inRoute(Finder ancestor, Finder matching) =>
            find.descendant(of: ancestor, matching: matching);
        Finder infoButton() =>
            inRoute(mediansPage(), find.byTooltip('Information'));
        Finder infoBody() => find.byKey(const ValueKey('journal-info-body'));
        Finder infoClose() => find.widgetWithText(OBAction, 'Schließen');

        Future<void> expectInfoClosePinned() async {
          expect(infoClose().hitTestable(), findsOneWidget);
        }

        Future<_CycleReviewRepo> mountCycle({
          Brightness brightness = Brightness.light,
          double scale = 1,
          _CycleReviewRepo? repository,
        }) async {
          final repo = repository ?? await loadRepo();
          await tester.pumpWidget(
            reviewHost(
              brightness: brightness,
              scale: scale,
              home: OpenBandCycle(
                repository: repo,
                day: day,
                now: () => now,
                synthetic: true,
              ),
            ),
          );
          await pumpUntil(
            () => cyclePage().evaluate().isNotEmpty,
            'Cycle main did not load.',
          );
          return repo;
        }

        Future<_CycleReviewRepo> mountMedians({
          Brightness brightness = Brightness.light,
          double scale = 1,
          _CycleReviewRepo? repository,
        }) async {
          final repo = repository ?? await loadRepo();
          await tester.pumpWidget(
            reviewHost(
              brightness: brightness,
              scale: scale,
              home: OpenBandCycleMedians(
                repository: repo,
                day: day,
                now: () => now,
                synthetic: true,
              ),
            ),
          );
          await pumpUntil(
            () => mediansPage().evaluate().isNotEmpty,
            'Cycle medians did not load.',
          );
          return repo;
        }

        Future<void> openMediansFromCycle() async {
          await tester.tap(inRoute(cyclePage(), find.text('Zyklustage')));
          await pumpAfterTap();
          await pumpUntil(
            () => mediansPage().evaluate().isNotEmpty,
            'Medians did not open from cycle.',
          );
        }

        Offset plotSlot(Finder target, int slot, int count) {
          final box = tester.getRect(target);
          const left = 26.0;
          const right = 4.0;
          final plotW = box.width - left - right;
          final x = count <= 1
              ? box.left + left + plotW / 2
              : box.left + left + slot * plotW / (count - 1);
          return Offset(x, box.center.dy);
        }

        Finder downScrollable(Finder ancestor) => find.descendant(
          of: ancestor,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        );

        Future<void> resetMediansScroll() async {
          final found = downScrollable(mediansPage());
          if (found.evaluate().isEmpty) return;
          final position = tester.state<ScrollableState>(found.first).position;
          if ((position.pixels - position.minScrollExtent).abs() > 0.5) {
            position.jumpTo(position.minScrollExtent);
            await tester.pump();
          }
        }

        Future<void> captureMainEnds(String top, String bottom) async {
          final page = mediansPage();
          final scrollable = downScrollable(page).first;
          tester
              .state<ScrollableState>(scrollable)
              .position
              .jumpTo(
                tester
                    .state<ScrollableState>(scrollable)
                    .position
                    .minScrollExtent,
              );
          await tester.pump();
          await capture(top);
          await tester.scrollUntilVisible(
            inRoute(page, find.text('Synthetische Daten')),
            80,
            scrollable: scrollable,
          );
          await capture(bottom);
          await resetMediansScroll();
        }

        Future<void> captureInfoEnds(String top, String body) async {
          await resetMediansScroll();
          await tester.tap(infoButton().hitTestable());
          await pumpAfterTap();
          await expectInfoClosePinned();
          await capture(top);
          final infoScroll = find.descendant(
            of: infoBody(),
            matching: find.byType(Scrollable),
          );
          expect(infoScroll, findsOneWidget);
          await tester.pump();
          final position = tester
              .state<ScrollableState>(infoScroll.first)
              .position;
          if (position.maxScrollExtent > 0.5) {
            position.jumpTo(position.maxScrollExtent);
            await tester.pump();
          }
          final last = find.textContaining('keine gemessene Sensorabweichung');
          expect(last, findsOneWidget);
          final lastBox = tester.getRect(last);
          final view = tester.getRect(infoScroll.first);
          expect(lastBox.top, greaterThanOrEqualTo(view.top - 1));
          expect(lastBox.bottom, lessThanOrEqualTo(view.bottom + 1));
          await expectInfoClosePinned();
          await capture(body);
          await tester.tap(infoClose().hitTestable());
          await pumpAfterTap();
        }

        var repo = await loadRepo();
        await mountCycle(repository: repo);
        expect(
          tester.getTopLeft(inRoute(cyclePage(), find.text('Messwerte'))).dy,
          lessThan(
            tester.getTopLeft(inRoute(cyclePage(), find.text('Zyklustage'))).dy,
          ),
        );
        expect(
          tester.getTopLeft(inRoute(cyclePage(), find.text('Zyklustage'))).dy,
          lessThan(
            tester
                .getTopLeft(inRoute(cyclePage(), find.text('Beobachtungen')))
                .dy,
          ),
        );
        await capture('cycle-medians-root');
        await openMediansFromCycle();
        expect(inRoute(mediansPage(), find.text('54')), findsOneWidget);
        expect(
          inRoute(mediansPage(), find.text('Median · Tag 23')),
          findsOneWidget,
        );
        await capture('cycle-medians-main');
        await popRoute();
        await pumpUntil(
          () => cyclePage().evaluate().isNotEmpty,
          'Did not return to cycle.',
        );
        expect(mediansPage(), findsNothing);
        await capture('cycle-medians-root-back');

        repo = await loadRepo();
        await mountCycle(repository: repo);
        await openMediansFromCycle();
        await tester.tap(find.byKey(const ValueKey('cycle-medians-window')));
        await pumpAfterTap();
        expect(find.text('Enddatum'), findsOneWidget);
        await capture('cycle-medians-date');
        await popRoute();
        await pumpUntil(
          () => mediansPage().evaluate().isNotEmpty,
          'Date cancel did not return.',
        );
        expect(inRoute(mediansPage(), find.text('54')), findsOneWidget);
        await capture('cycle-medians-date-cancel');
        await tester.tap(find.byKey(const ValueKey('cycle-medians-window')));
        await pumpAfterTap();
        await tester.tap(find.text('1').first);
        await pumpAfterTap();
        await tester.tap(find.text('Übernehmen'));
        await pumpAfterTap();
        expect(find.text('Enddatum'), findsNothing);
        expect(find.textContaining('1. Sept. 2026'), findsOneWidget);
        expect(find.textContaining('15. Sept. 2026'), findsNothing);
        expect(inRoute(mediansPage(), find.text('2 Zyklen')), findsNWidgets(2));
        expect(inRoute(mediansPage(), find.text('3 Zyklen')), findsNothing);
        await capture('cycle-medians-date-confirm');
        await popRoute();
        await pumpUntil(
          () => cyclePage().evaluate().isNotEmpty,
          'Date confirm did not return to cycle.',
        );
        expect(inRoute(cyclePage(), find.text('Tag 23')), findsOneWidget);
        expect(
          inRoute(cyclePage(), find.textContaining('15. Sept.')),
          findsOneWidget,
        );
        await capture('cycle-medians-date-confirm-root');

        repo = await loadRepo();
        await mountMedians(repository: repo, brightness: Brightness.dark);
        expect(inRoute(mediansPage(), find.text('54')), findsOneWidget);
        await capture('cycle-medians-main-dark');

        repo = await loadRepo();
        await mountMedians(repository: repo);
        await tester.tapAt(plotSlot(rhrPlot(), 5, 23));
        await tester.pump();
        expect(find.text('Median · Tag 6'), findsOneWidget);
        expect(find.text('0 Zyklen'), findsOneWidget);
        expect(find.text('Median · Tag 22'), findsOneWidget);
        await capture('cycle-medians-gap');

        await tester.tap(find.byKey(const ValueKey('cycle-medians-earlier')));
        await pumpAfterTap();
        expect(find.text('Kein Zyklusbeginn'), findsOneWidget);
        expect(find.textContaining('16. Sept. 2024'), findsOneWidget);
        await capture('cycle-medians-earlier');
        await tester.tap(find.byKey(const ValueKey('cycle-medians-later')));
        await pumpAfterTap();
        expect(find.text('54'), findsOneWidget);
        await capture('cycle-medians-earlier-return');

        repo = await loadRepo();
        repo.seedCycleMedianFixture(includeHrv: false);
        await mountMedians(repository: repo);
        expect(find.text('Zu wenige Nächte'), findsOneWidget);
        expect(find.text('54'), findsOneWidget);
        await capture('cycle-medians-one-metric');

        repo = await loadRepo();
        repo.clearCycleNightSources();
        await mountMedians(repository: repo);
        expect(find.text('Zu wenige Nächte'), findsNWidgets(2));
        await capture('cycle-medians-empty');
        await mountMedians(repository: repo, brightness: Brightness.dark);
        expect(find.text('Zu wenige Nächte'), findsNWidgets(2));
        await capture('cycle-medians-empty-dark');

        repo = await loadRepo();
        repo.clearCycleLogs();
        await mountMedians(repository: repo);
        expect(find.text('Kein Zyklusbeginn'), findsOneWidget);
        await capture('cycle-medians-no-start');

        repo = await loadRepo();
        repo.cycleSettings = const CycleSettings(
          enabled: false,
          estimatesEnabled: false,
          lengthReviewEnabled: false,
        );
        await mountMedians(repository: repo);
        expect(find.text('Zyklustracking aus'), findsOneWidget);
        await capture('cycle-medians-disabled');
        await tester.tap(find.text('Einstellungen'));
        await pumpAfterTap();
        expect(find.text('Zyklus im Journal'), findsOneWidget);
        await capture('cycle-medians-disabled-settings');
        await popRoute();
        await pumpUntil(
          () => mediansPage().evaluate().isNotEmpty,
          'Settings did not return.',
        );
        await capture('cycle-medians-disabled-return');

        repo = await loadRepo();
        repo.clearCycleLogs();
        repo.seedUnreadableCycleStart({'date': '2026-08-24', 'kind': 1});
        await mountMedians(repository: repo);
        expect(find.text('Beginn nicht lesbar'), findsOneWidget);
        await capture('cycle-medians-unreadable');
        await tester.tap(find.text('Zum Verlauf'));
        await pumpAfterTap();
        expect(find.byKey(const ValueKey('cycle-history')), findsOneWidget);
        await capture('cycle-medians-unreadable-history');
        await popRoute();
        await pumpUntil(
          () => mediansPage().evaluate().isNotEmpty,
          'History did not return.',
        );
        await capture('cycle-medians-unreadable-return');

        repo = await loadRepo();
        repo.seedCycleStart(
          const CycleStart(date: '2026-04-01', kind: kCycleStartKind),
        );
        await mountMedians(repository: repo);
        expect(find.text('Teilweise ausgewertet'), findsOneWidget);
        await capture('cycle-medians-partial');
        await mountMedians(repository: repo, brightness: Brightness.dark);
        expect(find.text('Teilweise ausgewertet'), findsOneWidget);
        await capture('cycle-medians-partial-dark');

        repo = await loadRepo();
        repo.clearCycleLogs();
        repo.seedCycleStart(
          const CycleStart(date: '2025-01-01', kind: kCycleStartKind),
        );
        repo.seedCycleStart(
          const CycleStart(date: '2025-06-01', kind: kCycleStartKind),
        );
        await mountMedians(repository: repo);
        expect(find.text('Abstände über 60 Tage'), findsOneWidget);
        await capture('cycle-medians-long');

        repo = await loadRepo();
        repo.failCycleMediansRead = true;
        await mountMedians(repository: repo);
        expect(find.text('Daten nicht geladen'), findsOneWidget);
        await capture('cycle-medians-error');
        await mountMedians(repository: repo, brightness: Brightness.dark);
        expect(find.text('Daten nicht geladen'), findsOneWidget);
        await capture('cycle-medians-error-dark');
        repo.failCycleMediansRead = false;
        await tester.tap(find.text('Erneut versuchen'));
        await pumpAfterTap();
        expect(find.text('54'), findsOneWidget);
        await capture('cycle-medians-error-retry');

        repo = await loadRepo();
        repo.clearCycleNightSources();
        repo.seedCycleNightSource(
          CycleNightSourceRow(
            day: '2026-08-29',
            algoVersion: kAlgoVersion,
            payloadUnreadable: true,
          ),
        );
        await mountMedians(repository: repo);
        expect(find.text('Teilweise ausgewertet'), findsOneWidget);
        expect(find.text('Zu wenige Nächte'), findsNWidgets(2));
        await capture('cycle-medians-partial-thin');

        repo = await loadRepo();
        repo.seedCycleStart(
          const CycleStart(
            date: '2026-08-24',
            kind: kCycleStartKind,
            note: 'keep',
          ),
        );
        repo.seedUnreadableCycleStart({'date': '2026-05-01', 'kind': 1});
        repo.failCycleContextRefresh = true;
        await mountMedians(repository: repo);
        await tester.tap(find.text('Zum Verlauf'));
        await pumpAfterTap();
        await tester.tap(find.text('24. August'));
        await pumpAfterTap();
        await tester.tap(find.text('Entfernen'));
        await pumpAfterTap();
        await tester.tap(find.text('Entfernen').last);
        await pumpAfterTap();
        await popRoute();
        await pumpUntil(
          () => mediansPage().evaluate().isNotEmpty,
          'History remove did not return.',
        );
        expect(
          find.text('Entfernt · Aktualisieren fehlgeschlagen'),
          findsOneWidget,
        );
        await capture('cycle-medians-removed-refresh');
        await tester.tap(find.text('Rückgängig'));
        await pumpAfterTap();
        expect(repo.startRestores, 1);
        expect(
          find.text('Wiederhergestellt · Aktualisieren fehlgeschlagen'),
          findsOneWidget,
        );
        await capture('cycle-medians-restored-refresh');
        repo.failCycleContextRefresh = false;
        await tester.tap(find.text('Erneut versuchen'));
        await pumpAfterTap();
        expect(find.text('Aktualisieren fehlgeschlagen'), findsNothing);
        expect(repo.startRestores, 1);

        repo = await loadRepo();
        repo.seedCycleStart(
          const CycleStart(
            date: '2026-08-24',
            kind: kCycleStartKind,
            note: 'keep',
          ),
        );
        repo.seedUnreadableCycleStart({'date': '2026-05-01', 'kind': 1});
        repo.failCycleContextRefresh = true;
        await mountMedians(repository: repo, brightness: Brightness.dark);
        await tester.tap(find.text('Zum Verlauf'));
        await pumpAfterTap();
        await tester.tap(find.text('24. August'));
        await pumpAfterTap();
        await tester.tap(find.text('Entfernen'));
        await pumpAfterTap();
        await tester.tap(find.text('Entfernen').last);
        await pumpAfterTap();
        await popRoute();
        await pumpUntil(
          () => mediansPage().evaluate().isNotEmpty,
          'Dark history remove did not return.',
        );
        expect(
          find.text('Entfernt · Aktualisieren fehlgeschlagen'),
          findsOneWidget,
        );
        await capture('cycle-medians-removed-refresh-dark');
        await tester.tap(find.text('Rückgängig'));
        await pumpAfterTap();
        expect(repo.startRestores, 1);
        expect(
          find.text('Wiederhergestellt · Aktualisieren fehlgeschlagen'),
          findsOneWidget,
        );
        await capture('cycle-medians-restored-refresh-dark');
        repo.failCycleContextRefresh = false;
        await tester.tap(find.text('Erneut versuchen'));
        await pumpAfterTap();
        expect(find.text('Aktualisieren fehlgeschlagen'), findsNothing);
        expect(repo.startRestores, 1);

        repo = await loadRepo();
        await mountMedians(repository: repo);
        await captureInfoEnds('cycle-medians-info', 'cycle-medians-info-body');

        repo = await loadRepo();
        await mountMedians(repository: repo, brightness: Brightness.dark);
        await captureInfoEnds(
          'cycle-medians-info-dark',
          'cycle-medians-info-dark-body',
        );

        repo = await loadRepo();
        await mountMedians(repository: repo, scale: 2);
        expect(find.text('54'), findsOneWidget);
        await captureMainEnds(
          'cycle-medians-main-2x-top',
          'cycle-medians-main-2x',
        );
        await captureInfoEnds(
          'cycle-medians-info-2x',
          'cycle-medians-info-2x-body',
        );
        await resetMediansScroll();
        await tester.tap(
          find.byKey(const ValueKey('cycle-medians-window')).hitTestable(),
        );
        await pumpAfterTap();
        expect(find.text('Enddatum'), findsOneWidget);
        await capture('cycle-medians-date-2x');
        await popRoute();
        await pumpUntil(
          () => mediansPage().evaluate().isNotEmpty,
          '2x date did not return.',
        );

        repo = await loadRepo();
        await mountMedians(
          repository: repo,
          brightness: Brightness.dark,
          scale: 2,
        );
        await captureMainEnds(
          'cycle-medians-main-2x-dark-top',
          'cycle-medians-main-2x-dark',
        );
        await captureInfoEnds(
          'cycle-medians-info-2x-dark',
          'cycle-medians-info-2x-dark-body',
        );
        await resetMediansScroll();
        await tester.tap(
          find.byKey(const ValueKey('cycle-medians-window')).hitTestable(),
        );
        await pumpAfterTap();
        expect(find.text('Enddatum'), findsOneWidget);
        await capture('cycle-medians-date-2x-dark');
        expect(tester.takeException(), isNull);
      }

      Future<void> reviewCycleComparison() async {
        final now = DateTime(2026, 9, 15, 9, 41);
        const day = '2026-09-15';

        Future<_CycleReviewRepo> loadRepo() async {
          Future<Map> load(String name) async =>
              jsonDecode(
                    await rootBundle.loadString(
                      'docs/openband5/assets/fixtures/$name.json',
                    ),
                  )
                  as Map;
          final repo = _CycleReviewRepo(
            await load('day-summary'),
            await load('sleep-detail'),
            activity: await load('additional-flows'),
            run: await load('run-detail'),
          );
          await repo.seedNutritionGoals();
          repo.seedCycleComparisonFixture();
          return repo;
        }

        Widget reviewHost({
          required Widget home,
          Brightness brightness = Brightness.light,
          double scale = 1,
        }) => MaterialApp(
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
          home: home,
        );

        Future<void> pumpUntil(bool Function() ready, String message) async {
          await tester.pump();
          var waited = 0;
          while (!ready()) {
            if (++waited > 80) throw FlutterError(message);
            await tester.pump(const Duration(milliseconds: 16));
          }
          await reviewPumpPageTransitions(tester);
        }

        Future<void> pumpAfterTap() async {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await reviewPumpPageTransitions(tester);
        }

        Future<void> popRoute() async {
          await tester.tap(find.byTooltip('Zurück'));
          await reviewPumpPageTransitions(tester);
          await tester.pump();
        }

        Finder cyclePage() => find.byKey(const ValueKey('cycle-overview'));
        Finder comparisonPage() =>
            find.byKey(const ValueKey('cycle-comparison'));
        Finder comparisonWindow() =>
            find.byKey(const ValueKey('cycle-comparison-window'));
        Finder comparisonWindowLabel() => find.descendant(
          of: comparisonWindow(),
          matching: find.byType(Text),
        );

        void expectComparisonWindow(String start, String end) {
          expect(
            tester.widget<Text>(comparisonWindowLabel()).data,
            '$start–\n$end',
          );
        }

        Finder inRoute(Finder ancestor, Finder matching) =>
            find.descendant(of: ancestor, matching: matching);
        Finder infoButton() =>
            inRoute(comparisonPage(), find.byTooltip('Information'));
        Finder infoBody() => find.byKey(const ValueKey('journal-info-body'));
        Finder infoClose() => find.widgetWithText(OBAction, 'Schließen');

        Future<void> expectInfoClosePinned() async {
          expect(infoClose().hitTestable(), findsOneWidget);
        }

        Future<_CycleReviewRepo> mountCycle({
          Brightness brightness = Brightness.light,
          double scale = 1,
          _CycleReviewRepo? repository,
        }) async {
          final repo = repository ?? await loadRepo();
          await tester.pumpWidget(
            reviewHost(
              brightness: brightness,
              scale: scale,
              home: OpenBandCycle(
                repository: repo,
                day: day,
                now: () => now,
                synthetic: true,
              ),
            ),
          );
          await pumpUntil(
            () => cyclePage().evaluate().isNotEmpty,
            'Cycle main did not load.',
          );
          return repo;
        }

        Future<_CycleReviewRepo> mountComparison({
          Brightness brightness = Brightness.light,
          double scale = 1,
          _CycleReviewRepo? repository,
        }) async {
          final repo = repository ?? await loadRepo();
          await tester.pumpWidget(
            reviewHost(
              brightness: brightness,
              scale: scale,
              home: OpenBandCycleComparison(
                repository: repo,
                day: day,
                now: () => now,
                synthetic: true,
              ),
            ),
          );
          await pumpUntil(
            () => comparisonPage().evaluate().isNotEmpty,
            'Cycle comparison did not load.',
          );
          return repo;
        }

        Finder downScrollable(Finder ancestor) => find.descendant(
          of: ancestor,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        );

        Future<void> resetComparisonScroll() async {
          final found = downScrollable(comparisonPage());
          if (found.evaluate().isEmpty) return;
          final position = tester.state<ScrollableState>(found.first).position;
          if ((position.pixels - position.minScrollExtent).abs() > 0.5) {
            position.jumpTo(position.minScrollExtent);
            await tester.pump();
          }
        }

        Future<void> captureMainEnds(String top, String bottom) async {
          final page = comparisonPage();
          final scrollable = downScrollable(page).first;
          tester
              .state<ScrollableState>(scrollable)
              .position
              .jumpTo(
                tester
                    .state<ScrollableState>(scrollable)
                    .position
                    .minScrollExtent,
              );
          await tester.pump();
          await capture(top);
          await tester.scrollUntilVisible(
            inRoute(page, find.text('Synthetische Daten')),
            80,
            scrollable: scrollable,
          );
          await capture(bottom);
          await resetComparisonScroll();
        }

        Future<void> captureSheetEnds(
          String top,
          String body, {
          required String lastContains,
          bool sourceActions = false,
        }) async {
          await expectInfoClosePinned();
          await capture(top);
          final infoScroll = find.descendant(
            of: infoBody(),
            matching: find.byType(Scrollable),
          );
          expect(infoScroll, findsOneWidget);
          await tester.pump();
          final position = tester
              .state<ScrollableState>(infoScroll.first)
              .position;
          if (position.maxScrollExtent > 0.5) {
            position.jumpTo(position.maxScrollExtent);
            await tester.pump();
          }
          final last = find.textContaining(lastContains);
          expect(last, findsOneWidget);
          final lastBox = tester.getRect(last);
          final view = tester.getRect(infoScroll.first);
          expect(lastBox.top, greaterThanOrEqualTo(view.top - 1));
          expect(lastBox.bottom, lessThanOrEqualTo(view.bottom + 1));
          if (sourceActions) {
            expect(find.text('Ruhepuls · Quellen'), findsOneWidget);
            expect(find.text('HRV · Quellen'), findsOneWidget);
            expect(find.text('HRV · Quellen').hitTestable(), findsOneWidget);
          }
          await expectInfoClosePinned();
          await capture(body);
          if (sourceActions) {
            await tester.ensureVisible(find.text('HRV · Quellen'));
            await tester.pump();
            expect(find.text('HRV · Quellen').hitTestable(), findsOneWidget);
            await tester.ensureVisible(find.text('Ruhepuls · Quellen'));
            await tester.pump();
            expect(
              find.text('Ruhepuls · Quellen').hitTestable(),
              findsOneWidget,
            );
            await expectInfoClosePinned();
          }
        }

        Future<void> openComparisonFromCycle() async {
          await tester.tap(
            inRoute(cyclePage(), find.text('Vergleich')).hitTestable(),
          );
          await pumpAfterTap();
          await pumpUntil(
            () => comparisonPage().evaluate().isNotEmpty,
            'Did not open comparison.',
          );
        }

        var repo = await loadRepo();
        await mountCycle(repository: repo);
        expect(
          tester.getTopLeft(inRoute(cyclePage(), find.text('Zyklustage'))).dy,
          lessThan(
            tester.getTopLeft(inRoute(cyclePage(), find.text('Vergleich'))).dy,
          ),
        );
        expect(
          tester.getTopLeft(inRoute(cyclePage(), find.text('Vergleich'))).dy,
          lessThan(
            tester
                .getTopLeft(inRoute(cyclePage(), find.text('Beobachtungen')))
                .dy,
          ),
        );
        await capture('cycle-comparison-root');
        await openComparisonFromCycle();
        expect(inRoute(comparisonPage(), find.text('56')), findsOneWidget);
        expect(
          inRoute(comparisonPage(), find.text('Nacht · Tag 23')),
          findsOneWidget,
        );
        expect(inRoute(comparisonPage(), find.text('51')), findsOneWidget);
        expect(
          inRoute(comparisonPage(), find.text('Nacht · Tag 22')),
          findsOneWidget,
        );
        await capture('cycle-comparison-main');
        await popRoute();
        await pumpUntil(
          () => cyclePage().evaluate().isNotEmpty,
          'Did not return to cycle.',
        );
        expect(comparisonPage(), findsNothing);
        await capture('cycle-comparison-root-back');

        repo = await loadRepo();
        await mountCycle(repository: repo);
        await openComparisonFromCycle();
        await tester.tap(find.byKey(const ValueKey('cycle-comparison-window')));
        await pumpAfterTap();
        expect(find.text('Enddatum'), findsOneWidget);
        await capture('cycle-comparison-date');
        await popRoute();
        await pumpUntil(
          () => comparisonPage().evaluate().isNotEmpty,
          'Date cancel did not return.',
        );
        expect(inRoute(comparisonPage(), find.text('56')), findsOneWidget);
        await capture('cycle-comparison-date-cancel');
        await tester.tap(find.byKey(const ValueKey('cycle-comparison-window')));
        await pumpAfterTap();
        await tester.tap(find.text('1').first);
        await pumpAfterTap();
        await tester.tap(find.text('Übernehmen'));
        await pumpAfterTap();
        expect(find.text('Enddatum'), findsNothing);
        expectComparisonWindow('2. Sept. 2025', '1. Sept. 2026');
        expect(
          inRoute(
            find.byKey(const ValueKey('cycle-comparison-rhr')),
            find.text('1. Sept. 2026'),
          ),
          findsOneWidget,
        );
        expect(
          inRoute(
            find.byKey(const ValueKey('cycle-comparison-hrv')),
            find.text('1. Sept. 2026'),
          ),
          findsOneWidget,
        );
        expect(
          inRoute(comparisonPage(), find.text('15. Sept. 2026')),
          findsNothing,
        );
        await capture('cycle-comparison-date-confirm');
        await popRoute();
        await pumpUntil(
          () => cyclePage().evaluate().isNotEmpty,
          'Date confirm did not return to cycle.',
        );
        expect(inRoute(cyclePage(), find.text('Tag 23')), findsOneWidget);
        expect(
          inRoute(cyclePage(), find.textContaining('15. Sept.')),
          findsOneWidget,
        );
        await capture('cycle-comparison-date-confirm-root');

        repo = await loadRepo();
        await mountComparison(repository: repo, brightness: Brightness.dark);
        expect(inRoute(comparisonPage(), find.text('56')), findsOneWidget);
        await capture('cycle-comparison-main-dark');

        repo = await loadRepo();
        await mountComparison(repository: repo);
        await tester.tap(
          find.byKey(const ValueKey('cycle-comparison-earlier')),
        );
        await pumpAfterTap();
        expectComparisonWindow('16. Sept. 2024', '15. Sept. 2025');
        expect(find.text('Keine Nacht'), findsNWidgets(2));
        expect(find.text('Kein Zyklusbeginn'), findsNothing);
        await capture('cycle-comparison-earlier');
        await tester.tap(find.byKey(const ValueKey('cycle-comparison-later')));
        await pumpAfterTap();
        expect(find.text('56'), findsOneWidget);
        await capture('cycle-comparison-earlier-return');

        repo = await loadRepo();
        repo.seedCycleComparisonFixture(includeHrv: false);
        await mountComparison(repository: repo);
        expect(find.text('56'), findsOneWidget);
        expect(find.text('Keine Nacht'), findsOneWidget);
        expect(find.text('51'), findsNothing);
        await capture('cycle-comparison-one-metric');

        repo = await loadRepo();
        repo.clearCycleNightSources();
        await mountComparison(repository: repo);
        expect(find.text('Keine Nacht'), findsNWidgets(2));
        expect(find.text('Gegenüber dem Mittelwert'), findsNothing);
        await capture('cycle-comparison-empty');
        await mountComparison(repository: repo, brightness: Brightness.dark);
        expect(find.text('Keine Nacht'), findsNWidgets(2));
        await capture('cycle-comparison-empty-dark');

        repo = await loadRepo();
        repo.clearCycleLogs();
        await mountComparison(repository: repo);
        expect(find.text('56'), findsOneWidget);
        expect(find.text('51'), findsOneWidget);
        expect(find.text('Kein Zyklusbeginn'), findsNWidgets(2));
        expect(find.text('Nacht · Tag 23'), findsNothing);
        await capture('cycle-comparison-no-start');

        repo = await loadRepo();
        repo.cycleSettings = const CycleSettings(
          enabled: false,
          estimatesEnabled: false,
          lengthReviewEnabled: false,
        );
        await mountComparison(repository: repo);
        expect(find.text('Zyklustracking aus'), findsOneWidget);
        await capture('cycle-comparison-disabled');
        await tester.tap(find.text('Einstellungen'));
        await pumpAfterTap();
        expect(find.text('Zyklus im Journal'), findsOneWidget);
        await capture('cycle-comparison-disabled-settings');
        await popRoute();
        await pumpUntil(
          () => comparisonPage().evaluate().isNotEmpty,
          'Settings did not return.',
        );
        await capture('cycle-comparison-disabled-return');

        repo = await loadRepo();
        repo.clearCycleLogs();
        repo.seedUnreadableCycleStart({'date': '2026-08-24', 'kind': 1});
        await mountComparison(repository: repo);
        expect(find.text('Beginn nicht lesbar'), findsNWidgets(2));
        expect(find.text('56'), findsOneWidget);
        expect(find.text('17 Nächte'), findsOneWidget);
        await capture('cycle-comparison-unreadable');

        repo = await loadRepo();
        repo.clearCycleLogs();
        repo.seedCycleStart(
          const CycleStart(date: '2025-01-01', kind: kCycleStartKind),
        );
        await mountComparison(repository: repo);
        expect(find.text('Abstand über 60 Tage'), findsNWidgets(2));
        expect(find.text('56'), findsOneWidget);
        expect(find.text('17 Nächte'), findsOneWidget);
        await capture('cycle-comparison-long');

        repo = await loadRepo();
        repo.seedCycleNightSource(
          CycleNightSourceRow(
            day: '2026-08-29',
            algoVersion: kAlgoVersion,
            payloadUnreadable: true,
          ),
        );
        await mountComparison(repository: repo);
        expect(find.text('Teilweise ausgewertet'), findsOneWidget);
        expect(find.text('56'), findsOneWidget);
        await capture('cycle-comparison-partial');
        await tester.tap(infoButton().hitTestable());
        await pumpAfterTap();
        expect(
          find.text(
            'Gewähltes Jahr und 21-Tage-Vergleiche: 1 Nacht mit nicht lesbaren Daten.',
          ),
          findsOneWidget,
        );
        expect(find.text('Ruhepuls · Quellen'), findsOneWidget);
        await captureSheetEnds(
          'cycle-comparison-partial-info',
          'cycle-comparison-partial-info-body',
          lastContains: 'nicht lesbaren Daten',
        );
        await tester.tap(infoClose().hitTestable());
        await pumpAfterTap();
        await mountComparison(repository: repo, brightness: Brightness.dark);
        expect(find.text('Teilweise ausgewertet'), findsOneWidget);
        await capture('cycle-comparison-partial-dark');
        await tester.tap(infoButton().hitTestable());
        await pumpAfterTap();
        await captureSheetEnds(
          'cycle-comparison-partial-info-dark',
          'cycle-comparison-partial-info-dark-body',
          lastContains: 'nicht lesbaren Daten',
        );
        await tester.tap(infoClose().hitTestable());
        await pumpAfterTap();

        repo = await loadRepo();
        repo.clearCycleNightSources();
        repo.seedCycleNightSource(
          CycleNightSourceRow(
            day: '2026-09-15',
            algoVersion: kAlgoVersion,
            payloadUnreadable: true,
          ),
        );
        await mountComparison(repository: repo);
        expect(find.text('Nicht auswertbar'), findsNWidgets(2));
        expect(find.text('Keine Nacht'), findsNothing);
        await capture('cycle-comparison-unavailable');
        await tester.tap(infoButton().hitTestable());
        await pumpAfterTap();
        expect(
          find.text(
            'Gewähltes Jahr und 21-Tage-Vergleiche: 1 Nacht mit nicht lesbaren Daten.',
          ),
          findsOneWidget,
        );
        expect(find.text('Ruhepuls · Quellen'), findsNothing);
        await captureSheetEnds(
          'cycle-comparison-unavailable-info',
          'cycle-comparison-unavailable-info-body',
          lastContains: 'nicht lesbaren Daten',
        );
        await tester.tap(infoClose().hitTestable());
        await pumpAfterTap();
        await mountComparison(repository: repo, brightness: Brightness.dark);
        expect(find.text('Nicht auswertbar'), findsNWidgets(2));
        await capture('cycle-comparison-unavailable-dark');
        await tester.tap(infoButton().hitTestable());
        await pumpAfterTap();
        expect(find.text('Ruhepuls · Quellen'), findsNothing);
        await captureSheetEnds(
          'cycle-comparison-unavailable-info-dark',
          'cycle-comparison-unavailable-info-dark-body',
          lastContains: 'nicht lesbaren Daten',
        );
        await tester.tap(infoClose().hitTestable());
        await pumpAfterTap();

        repo = await loadRepo();
        repo.failCycleComparisonRead = true;
        await mountComparison(repository: repo);
        expect(find.text('Daten nicht geladen'), findsOneWidget);
        await capture('cycle-comparison-error');
        await mountComparison(repository: repo, brightness: Brightness.dark);
        expect(find.text('Daten nicht geladen'), findsOneWidget);
        await capture('cycle-comparison-error-dark');
        repo.failCycleComparisonRead = false;
        await tester.tap(find.text('Erneut versuchen'));
        await pumpAfterTap();
        expect(find.text('56'), findsOneWidget);
        await capture('cycle-comparison-error-retry');

        repo = await loadRepo();
        await mountComparison(repository: repo);
        await resetComparisonScroll();
        await tester.tap(infoButton().hitTestable());
        await pumpAfterTap();
        expect(
          find.text(
            'Verglichen wird die letzte gespeicherte Nacht je Messwert. Die Differenz bezieht sich auf den Mittelwert der genannten Nächte.',
          ),
          findsOneWidget,
        );
        expect(find.text('Ruhepuls · Quellen'), findsOneWidget);
        expect(find.text('HRV · Quellen'), findsOneWidget);
        await captureSheetEnds(
          'cycle-comparison-info',
          'cycle-comparison-info-body',
          lastContains: 'HRV · Quellen',
          sourceActions: true,
        );
        await tester.tap(find.text('Ruhepuls · Quellen').hitTestable());
        await pumpAfterTap();
        expect(find.text('Ruhepuls · Quellen'), findsNothing);
        expect(find.text('Ruhepuls'), findsWidgets);
        await captureSheetEnds(
          'cycle-comparison-rhr-sources',
          'cycle-comparison-rhr-sources-body',
          lastContains: 'Keine Aussage über Ursache',
        );
        await tester.tap(infoClose().hitTestable());
        await pumpAfterTap();
        expect(comparisonPage(), findsOneWidget);

        repo = await loadRepo();
        await mountComparison(repository: repo);
        await tester.tap(infoButton().hitTestable());
        await pumpAfterTap();
        await tester.tap(find.text('HRV · Quellen').hitTestable());
        await pumpAfterTap();
        expect(find.text('HRV · Quellen'), findsNothing);
        await captureSheetEnds(
          'cycle-comparison-hrv-sources',
          'cycle-comparison-hrv-sources-body',
          lastContains: 'Keine Aussage über Ursache',
        );
        await tester.tap(infoClose().hitTestable());
        await pumpAfterTap();

        repo = await loadRepo();
        await mountComparison(repository: repo, brightness: Brightness.dark);
        await tester.tap(infoButton().hitTestable());
        await pumpAfterTap();
        await captureSheetEnds(
          'cycle-comparison-info-dark',
          'cycle-comparison-info-dark-body',
          lastContains: 'HRV · Quellen',
          sourceActions: true,
        );
        await tester.tap(infoClose().hitTestable());
        await pumpAfterTap();

        repo = await loadRepo();
        await mountComparison(repository: repo, scale: 2);
        expect(find.text('56'), findsOneWidget);
        await captureMainEnds(
          'cycle-comparison-main-2x-top',
          'cycle-comparison-main-2x',
        );
        await tester.tap(infoButton().hitTestable());
        await pumpAfterTap();
        await captureSheetEnds(
          'cycle-comparison-info-2x',
          'cycle-comparison-info-2x-body',
          lastContains: 'HRV · Quellen',
          sourceActions: true,
        );
        await tester.tap(find.text('Ruhepuls · Quellen').hitTestable());
        await pumpAfterTap();
        await captureSheetEnds(
          'cycle-comparison-rhr-sources-2x',
          'cycle-comparison-rhr-sources-2x-body',
          lastContains: 'Keine Aussage über Ursache',
        );
        await tester.tap(infoClose().hitTestable());
        await pumpAfterTap();
        await resetComparisonScroll();
        await tester.tap(
          find.byKey(const ValueKey('cycle-comparison-window')).hitTestable(),
        );
        await pumpAfterTap();
        expect(find.text('Enddatum'), findsOneWidget);
        await capture('cycle-comparison-date-2x');
        await popRoute();
        await pumpUntil(
          () => comparisonPage().evaluate().isNotEmpty,
          '2x date did not return.',
        );

        repo = await loadRepo();
        await mountComparison(
          repository: repo,
          brightness: Brightness.dark,
          scale: 2,
        );
        await captureMainEnds(
          'cycle-comparison-main-2x-dark-top',
          'cycle-comparison-main-2x-dark',
        );
        await tester.tap(infoButton().hitTestable());
        await pumpAfterTap();
        await captureSheetEnds(
          'cycle-comparison-info-2x-dark',
          'cycle-comparison-info-2x-dark-body',
          lastContains: 'HRV · Quellen',
          sourceActions: true,
        );
        await tester.tap(infoClose().hitTestable());
        await pumpAfterTap();
        await resetComparisonScroll();
        await tester.tap(
          find.byKey(const ValueKey('cycle-comparison-window')).hitTestable(),
        );
        await pumpAfterTap();
        expect(find.text('Enddatum'), findsOneWidget);
        await capture('cycle-comparison-date-2x-dark');
        expect(tester.takeException(), isNull);
      }

      Future<void> reviewNightScalar() async {
        final now = DateTime(2026, 9, 15, 9, 41);
        final onsetMs = DateTime(2026, 9, 14, 23, 10).millisecondsSinceEpoch;
        final wakeMs = DateTime(2026, 9, 15, 6, 54).millisecondsSinceEpoch;

        Future<SyntheticOpenBandRepository> loadRepo() async {
          Future<Map> load(String name) async =>
              jsonDecode(
                    await rootBundle.loadString(
                      'docs/openband5/assets/fixtures/$name.json',
                    ),
                  )
                  as Map;
          return SyntheticOpenBandRepository.fromMaps(
            await load('day-summary'),
            await load('sleep-detail'),
            activity: await load('additional-flows'),
            run: await load('run-detail'),
          );
        }

        Map<String, NightScalarRow> paperHrv({int? algo}) {
          final days = nightScalarDaysEnding(kNightScalarPaperDay, 30);
          final start = days.length - kNightScalarPaperHrv.length;
          return {
            for (var i = 0; i < kNightScalarPaperHrv.length; i++)
              days[start + i]: NightScalarRow(
                day: days[start + i],
                algoVersion: algo ?? kAlgoVersion,
                value: kNightScalarPaperHrv[i],
              ),
          };
        }

        NightScalarRow selectedHrv({
          StoredNightBaseline? baseline,
          int? algo,
          bool partial = false,
          int? computedAtMs,
          String? deviceFamily,
          String? sleepSource,
        }) => NightScalarRow(
          day: kNightScalarPaperDay,
          algoVersion: algo ?? kAlgoVersion,
          partial: partial,
          value: 48,
          computedAtMs:
              computedAtMs ??
              DateTime(2026, 9, 15, 7, 2).millisecondsSinceEpoch,
          deviceFamily: deviceFamily,
          sleepSource: sleepSource,
          baseline:
              baseline ??
              const StoredNightBaseline(
                value: kNightScalarPaperHrvBaseline,
                status: 'trusted',
                nValid: 30,
              ),
          windowStartMs: onsetMs,
          windowEndMs: wakeMs,
        );

        void seedTrusted(SyntheticOpenBandRepository repo, {bool hrv = true}) {
          if (hrv) {
            repo.seedNightScalarDetail(
              selected: selectedHrv(deviceFamily: 'gen5', sleepSource: 'auto'),
              matching: paperHrv(),
              currentAlgo: kAlgoVersion,
            );
            return;
          }
          final days = nightScalarDaysEnding(kNightScalarPaperDay, 30);
          final start = days.length - kNightScalarPaperRhr.length;
          repo.seedNightScalarDetail(
            key: MetricKey.restingHr,
            selected: NightScalarRow(
              day: kNightScalarPaperDay,
              algoVersion: kAlgoVersion,
              value: 54,
              computedAtMs: DateTime(2026, 9, 15, 7, 2).millisecondsSinceEpoch,
              baseline: const StoredNightBaseline(
                value: kNightScalarPaperRhrBaseline,
                status: 'trusted',
              ),
              windowStartMs: onsetMs,
              windowEndMs: wakeMs,
            ),
            matching: {
              for (var i = 0; i < kNightScalarPaperRhr.length; i++)
                days[start + i]: NightScalarRow(
                  day: days[start + i],
                  algoVersion: kAlgoVersion,
                  value: kNightScalarPaperRhr[i],
                ),
            },
            currentAlgo: kAlgoVersion,
          );
        }

        Map<String, NightScalarJob> failedJobs() => {
          kNightScalarPaperDay: NightScalarJob(
            day: kNightScalarPaperDay,
            status: 'failed',
          ),
        };

        void seedSelectedPartial(SyntheticOpenBandRepository repo) {
          final matching = paperHrv();
          matching[kNightScalarPaperDay] = NightScalarRow(
            day: kNightScalarPaperDay,
            algoVersion: kAlgoVersion,
            value: kNightScalarPaperHrv.last,
            partial: true,
          );
          repo.seedNightScalarDetail(
            selected: selectedHrv(
              partial: true,
              deviceFamily: 'gen5',
              sleepSource: 'auto',
            ),
            matching: matching,
            currentAlgo: kAlgoVersion,
          );
        }

        void seedFailedReceipt(SyntheticOpenBandRepository repo) {
          repo.seedNightScalarDetail(
            selected: selectedHrv(deviceFamily: 'gen5', sleepSource: 'auto'),
            matching: paperHrv(),
            sleepJobs: failedJobs(),
            napJobs: failedJobs(),
            currentAlgo: kAlgoVersion,
          );
        }

        Widget reviewHost({
          required Widget home,
          Brightness brightness = Brightness.light,
          double scale = 1,
        }) => MaterialApp(
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
          home: home,
        );

        Future<void> pumpUntil(bool Function() ready, String message) async {
          await tester.pump();
          var waited = 0;
          while (!ready()) {
            if (++waited > 80) throw FlutterError(message);
            await tester.pump(const Duration(milliseconds: 16));
          }
          await reviewPumpPageTransitions(tester);
        }

        bool nightScalarLoaded() =>
            find
                .byKey(const ValueKey('night-scalar-detail'))
                .evaluate()
                .isNotEmpty &&
            (find.textContaining('von ').evaluate().isNotEmpty ||
                find.text('Erneut').evaluate().isNotEmpty);

        Future<OpenBandController> mountDetail({
          required SyntheticOpenBandRepository repository,
          MetricKey key = MetricKey.hrv,
          Brightness brightness = Brightness.light,
          double scale = 1,
        }) async {
          final controller = OpenBandController(
            repository: repository,
            initialDay: kNightScalarPaperDay,
            band: repository.band,
            now: () => now,
          );
          await controller.refresh();
          await tester.pumpWidget(
            reviewHost(
              brightness: brightness,
              scale: scale,
              home: OpenBandNightScalarDetail(
                controller: controller,
                metricKey: key,
                label: key == MetricKey.hrv ? 'HRV' : 'Ruhepuls',
                unit: key == MetricKey.hrv ? 'ms' : '/min',
                icon: key == MetricKey.hrv
                    ? LucideIcons.activity
                    : LucideIcons.heart,
                color: key == MetricKey.hrv
                    ? (p) => p.recovery
                    : (p) => p.pulse,
                tint: key == MetricKey.hrv
                    ? (p) => p.recoveryTint
                    : (p) => p.pulseTint,
              ),
            ),
          );
          await pumpUntil(
            nightScalarLoaded,
            'Night scalar detail did not finish loading.',
          );
          return controller;
        }

        var repo = await loadRepo();
        seedTrusted(repo);
        await mountDetail(repository: repo);
        expect(find.text('48'), findsOneWidget);
        expect(find.text('15 von 30 Nächten'), findsOneWidget);
        await capture('night-scalar-hrv');
        await tester.tap(find.text('Nachtverlauf'));
        await reviewPumpPageTransitions(tester);
        await pumpUntil(
          () =>
              find.byType(OpenBandNightSignals).evaluate().isNotEmpty &&
              find.byType(OBNightSignalChart).evaluate().isNotEmpty,
          'Night signals did not load.',
        );
        final nightTabs = tester.widget<OBSegmented>(
          find.byWidgetPredicate(
            (widget) =>
                widget is OBSegmented &&
                widget.labels.contains('Puls') &&
                widget.labels.contains('HRV'),
          ),
        );
        expect(nightTabs.selected, 1);
        await capture('night-scalar-night-route');
        await tester.tap(find.byTooltip('Zurück'));
        await reviewPumpPageTransitions(tester);
        await pumpUntil(
          () =>
              find.byType(OpenBandNightSignals).evaluate().isEmpty &&
              find.text('48').evaluate().isNotEmpty &&
              nightScalarLoaded(),
          'Night scalar detail did not return.',
        );
        expect(find.text('48'), findsOneWidget);
        await tester.tap(find.byTooltip('Information'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await capture('night-scalar-info');
        await tester.tap(find.text('Schließen'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Persönliche Basis'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await capture('night-scalar-baseline');
        await tester.tap(find.text('Schließen'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('7 Nächte'));
        await tester.pumpAndSettle();
        await capture('night-scalar-seven');
        await tester.tap(find.text('90 Nächte'));
        await tester.pumpAndSettle();
        await capture('night-scalar-ninety');

        repo = await loadRepo();
        seedTrusted(repo);
        await mountDetail(repository: repo, brightness: Brightness.dark);
        await capture('night-scalar-hrv-dark');
        await tester.tap(find.text('7 Nächte'));
        await tester.pumpAndSettle();
        await capture('night-scalar-seven-dark');

        repo = await loadRepo();
        seedTrusted(repo, hrv: false);
        await mountDetail(repository: repo, key: MetricKey.restingHr);
        expect(find.text('54'), findsOneWidget);
        await capture('night-scalar-rhr');
        repo = await loadRepo();
        seedTrusted(repo, hrv: false);
        await mountDetail(
          repository: repo,
          key: MetricKey.restingHr,
          brightness: Brightness.dark,
        );
        await capture('night-scalar-rhr-dark');

        repo = await loadRepo();
        repo.scenario = SyntheticScenario.missing;
        await mountDetail(repository: repo);
        expect(find.text('Noch kein Nachtwert'), findsOneWidget);
        expect(find.text('14 von 30 Nächten'), findsOneWidget);
        await capture('night-scalar-selected-missing');

        repo = await loadRepo();
        repo.seedNightScalarDetail(
          selected: null,
          matching: const {},
          currentAlgo: kAlgoVersion,
        );
        await mountDetail(repository: repo);
        expect(find.text('Noch kein Nachtwert'), findsOneWidget);
        expect(find.text('0 von 30 Nächten'), findsOneWidget);
        expect(find.text('14 von 30 Nächten'), findsNothing);
        await capture('night-scalar-full-missing');

        repo = await loadRepo();
        seedSelectedPartial(repo);
        await mountDetail(repository: repo);
        expect(find.text('Unvollständige Nacht'), findsOneWidget);
        expect(find.text('48'), findsOneWidget);
        expect(find.text('15 von 30 · teils unvollständig'), findsOneWidget);
        expect(find.textContaining('Basis 40'), findsOneWidget);
        expect(find.text('+8 über Basis'), findsNothing);
        await capture('night-scalar-partial');

        repo = await loadRepo();
        repo.scenario = SyntheticScenario.processing;
        await mountDetail(repository: repo);
        expect(find.text('Auswertung läuft'), findsOneWidget);
        await capture('night-scalar-pending');

        repo = await loadRepo();
        seedFailedReceipt(repo);
        await mountDetail(repository: repo);
        expect(find.text('Auswertung fehlgeschlagen'), findsOneWidget);
        expect(find.text('48'), findsNothing);
        expect(find.text('14 von 30 Nächten'), findsOneWidget);
        await capture('night-scalar-failed');
        await tester.tap(find.byTooltip('Information'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          find.textContaining('Zuletzt gespeichert: 48 ms'),
          findsOneWidget,
        );
        expect(
          find.textContaining('14.–15. September · 23:10–06:54'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Schlaf automatisch · WHOOP 5.0'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Berechnet am 15. September, 07:02'),
          findsOneWidget,
        );
        expect(find.textContaining('Vorherige Basis 40 ms'), findsOneWidget);
        expect(find.textContaining('30 gültige Nächte'), findsOneWidget);
        expect(
          find.textContaining('Vorheriger Status: Verlässlich'),
          findsOneWidget,
        );
        expect(find.textContaining('Algorithmus 90'), findsOneWidget);
        await capture('night-scalar-failed-info');
        await tester.tap(find.text('Schlaf ansehen'));
        await reviewPumpPageTransitions(tester);
        await pumpUntil(
          () =>
              find.byType(SleepEditor).evaluate().isNotEmpty &&
              find.text('Schlafzeiten ändern').evaluate().isNotEmpty,
          'Sleep editor did not open from failed info.',
        );
        await capture('night-scalar-correction-route');

        repo = await loadRepo();
        repo.seedNightScalarDetail(
          selected: selectedHrv(),
          matching: paperHrv(),
          sleepJobs: {
            kNightScalarPaperDay: NightScalarJob(
              day: kNightScalarPaperDay,
              status: 'queued',
            ),
          },
          currentAlgo: kAlgoVersion,
        );
        await mountDetail(repository: repo);
        await capture('night-scalar-unknown');

        repo = await loadRepo();
        repo.seedNightScalarDetail(
          selected: selectedHrv(algo: 80),
          matching: paperHrv(algo: 80),
          currentAlgo: kAlgoVersion,
        );
        await mountDetail(repository: repo);
        await capture('night-scalar-old');

        repo = await loadRepo();
        repo.seedNightScalarDetail(
          selected: selectedHrv(
            baseline: const StoredNightBaseline(
              value: 40,
              status: 'provisional',
            ),
          ),
          matching: paperHrv(),
          currentAlgo: kAlgoVersion,
        );
        await mountDetail(repository: repo);
        await capture('night-scalar-provisional');

        repo = await loadRepo();
        repo.seedNightScalarDetail(
          selected: selectedHrv(
            baseline: const StoredNightBaseline(value: 40, status: 'stale'),
          ),
          matching: paperHrv(),
          currentAlgo: kAlgoVersion,
        );
        await mountDetail(repository: repo);
        await capture('night-scalar-stale');

        repo = await loadRepo();
        final unreadableHistory = paperHrv()..remove(kNightScalarPaperDay);
        repo.seedNightScalarDetail(
          selected: NightScalarRow(
            day: kNightScalarPaperDay,
            algoVersion: kAlgoVersion,
            payloadUnreadable: true,
            value: 48,
          ),
          matching: unreadableHistory,
          currentAlgo: kAlgoVersion,
        );
        await mountDetail(repository: repo);
        expect(find.text('Nachtwert nicht lesbar'), findsOneWidget);
        expect(find.text('14 von 30 Nächten'), findsOneWidget);
        expect(find.text('15 von 30 Nächten'), findsNothing);
        await capture('night-scalar-unreadable');

        repo = await loadRepo();
        final sparseDays = nightScalarDaysEnding(kNightScalarPaperDay, 30);
        repo.seedNightScalarDetail(
          selected: selectedHrv(),
          matching: {
            sparseDays[15]: NightScalarRow(
              day: sparseDays[15],
              algoVersion: kAlgoVersion,
              value: 32,
            ),
            sparseDays[26]: NightScalarRow(
              day: sparseDays[26],
              algoVersion: kAlgoVersion,
              value: 46,
            ),
            sparseDays[29]: selectedHrv(),
          },
          currentAlgo: kAlgoVersion,
        );
        await mountDetail(repository: repo);
        expect(find.text('48'), findsOneWidget);
        expect(find.text('3 von 30 Nächten'), findsOneWidget);
        expect(find.text('+8 über Basis'), findsOneWidget);
        await capture('night-scalar-sparse');

        repo = await loadRepo();
        repo.failNightScalarRead = true;
        await mountDetail(repository: repo);
        expect(find.text('Erneut'), findsOneWidget);
        await capture('night-scalar-error');
        repo.failNightScalarRead = false;
        await tester.tap(find.text('Erneut'));
        await tester.pumpAndSettle();
        await capture('night-scalar-error-retry');

        // Paper acceptance includes the non-default states in both themes.
        repo = await loadRepo();
        repo.scenario = SyntheticScenario.missing;
        await mountDetail(repository: repo, brightness: Brightness.dark);
        expect(find.text('14 von 30 Nächten'), findsOneWidget);
        await capture('night-scalar-selected-missing-dark');

        repo = await loadRepo();
        repo.seedNightScalarDetail(
          selected: null,
          matching: const {},
          currentAlgo: kAlgoVersion,
        );
        await mountDetail(repository: repo, brightness: Brightness.dark);
        expect(find.text('0 von 30 Nächten'), findsOneWidget);
        await capture('night-scalar-full-missing-dark');

        repo = await loadRepo();
        seedSelectedPartial(repo);
        await mountDetail(repository: repo, brightness: Brightness.dark);
        expect(find.text('Unvollständige Nacht'), findsOneWidget);
        expect(find.text('15 von 30 · teils unvollständig'), findsOneWidget);
        expect(find.textContaining('Basis 40'), findsOneWidget);
        await capture('night-scalar-partial-dark');

        repo = await loadRepo();
        repo.failNightScalarRead = true;
        await mountDetail(repository: repo, brightness: Brightness.dark);
        await capture('night-scalar-error-dark');

        repo = await loadRepo();
        seedTrusted(repo);
        await mountDetail(repository: repo, brightness: Brightness.dark);
        await tester.tap(find.byTooltip('Information'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await capture('night-scalar-info-dark');

        repo = await loadRepo();
        repo.seedNightScalarDetail(
          selected: selectedHrv(
            baseline: const StoredNightBaseline(
              value: 40,
              status: 'provisional',
            ),
          ),
          matching: paperHrv(),
          currentAlgo: kAlgoVersion,
        );
        await mountDetail(repository: repo, brightness: Brightness.dark);
        await capture('night-scalar-provisional-dark');

        repo = await loadRepo();
        repo.seedNightScalarDetail(
          selected: selectedHrv(
            baseline: const StoredNightBaseline(value: 40, status: 'stale'),
          ),
          matching: paperHrv(),
          currentAlgo: kAlgoVersion,
        );
        await mountDetail(repository: repo, brightness: Brightness.dark);
        await capture('night-scalar-stale-dark');

        repo = await loadRepo();
        seedTrusted(repo);
        await mountDetail(repository: repo, scale: 2);
        await capture('night-scalar-2x');
        await tester.drag(find.byType(ListView), const Offset(0, -520));
        await tester.pumpAndSettle();
        await capture('night-scalar-2x-lower');
        repo = await loadRepo();
        seedTrusted(repo);
        await mountDetail(
          repository: repo,
          scale: 2,
          brightness: Brightness.dark,
        );
        await capture('night-scalar-2x-dark');
        await tester.drag(find.byType(ListView), const Offset(0, -520));
        await tester.pumpAndSettle();
        await capture('night-scalar-2x-dark-lower');
        expect(tester.takeException(), isNull);
      }

      Future<void> reviewSleepLegend() async {
        Future<void> openSleep({
          SyntheticScenario scenario = SyntheticScenario.complete,
          Brightness brightness = Brightness.light,
          double? scale,
        }) async {
          await mount(scenario: scenario, brightness: brightness, scale: scale);
          final sleep = find.bySemanticsLabel(RegExp(r'^Schlaf, ')).first;
          await tester.tap(sleep);
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('openband-sleep')), findsOneWidget);
        }

        Finder sleepHeroText(String text) {
          final sleepCards = find.descendant(
            of: find.byKey(const ValueKey('openband-sleep')),
            matching: find.byType(OBCard),
          );
          return find.descendant(
            of: sleepCards.first,
            matching: find.text(text),
          );
        }

        Finder stageLegendText(String text) => find.descendant(
          of: find.byKey(const ValueKey('sleep-stage-legend')),
          matching: find.text(text),
        );

        Future<void> showLegend() async {
          final target = find.byKey(const ValueKey('sleep-stage-legend'));
          await tester.scrollUntilVisible(
            target,
            160,
            scrollable: verticalScrollable().last,
          );
          await tester.pumpAndSettle();
          expect(target, findsOneWidget);
          expect(find.byType(OBStageLegend), findsOneWidget);
          expect(
            find.byKey(const ValueKey('sleep-stage-swatch-Im Bett')),
            findsNothing,
          );
        }

        Future<void> closeSleep() async {
          final back = find.byTooltip('Zurück');
          await tester.scrollUntilVisible(
            back,
            -160,
            scrollable: verticalScrollable().last,
          );
          await tester.pumpAndSettle();
          await tester.tap(back);
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('openband-sleep')), findsNothing);
        }

        await openSleep();
        expect(sleepHeroText('7h18'), findsOneWidget);
        await capture('sleep-legend-light-hero');
        await showLegend();
        expect(stageLegendText('Tief'), findsOneWidget);
        expect(stageLegendText('Leicht'), findsOneWidget);
        expect(stageLegendText('REM'), findsOneWidget);
        expect(stageLegendText('Wach'), findsOneWidget);
        expect(stageLegendText('Im Bett'), findsOneWidget);
        expect(stageLegendText('1h08'), findsOneWidget);
        expect(stageLegendText('4h07'), findsOneWidget);
        expect(stageLegendText('2h03'), findsOneWidget);
        expect(stageLegendText('26 Min.'), findsOneWidget);
        expect(stageLegendText('7h44'), findsOneWidget);
        await capture('sleep-legend-light');
        await closeSleep();

        await openSleep(brightness: Brightness.dark);
        await showLegend();
        expect(stageLegendText('4h07'), findsOneWidget);
        await capture('sleep-legend-dark');
        await closeSleep();

        await openSleep(scenario: SyntheticScenario.partial);
        await showLegend();
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('sleep-stage-legend')),
            matching: find.text('—'),
          ),
          findsNothing,
        );
        await capture('sleep-legend-partial');
        await closeSleep();

        await openSleep(scenario: SyntheticScenario.missing);
        expect(
          find.text('Für diese Nacht liegt noch kein Schlafwert vor.'),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('sleep-stage-legend')), findsNothing);
        await capture('sleep-legend-missing');
        await closeSleep();

        await openSleep(scale: 2);
        expect(sleepHeroText('7h18'), findsOneWidget);
        await capture('sleep-legend-375-2x-hero');
        await showLegend();
        expect(stageLegendText('Leicht'), findsOneWidget);
        expect(stageLegendText('26 Min.'), findsOneWidget);
        await capture('sleep-legend-375-2x');
        await closeSleep();

        await openSleep(brightness: Brightness.dark, scale: 2);
        await showLegend();
        expect(stageLegendText('Leicht'), findsOneWidget);
        expect(stageLegendText('26 Min.'), findsOneWidget);
        await capture('sleep-legend-375-2x-dark');
        await closeSleep();
        expect(tester.takeException(), isNull);
      }

      Future<void> reviewNightCards() async {
        final onsetMs = DateTime(2026, 9, 14, 23, 10).millisecondsSinceEpoch;
        final wakeMs = DateTime(2026, 9, 15, 6, 54).millisecondsSinceEpoch;
        final computedAtMs = DateTime(2026, 9, 15, 7, 2).millisecondsSinceEpoch;

        NightScalarRow selectedHrv({bool partial = false}) => NightScalarRow(
          day: kNightScalarPaperDay,
          algoVersion: kAlgoVersion,
          partial: partial,
          value: 48,
          computedAtMs: computedAtMs,
          deviceFamily: 'gen5',
          sleepSource: 'auto',
          baseline: const StoredNightBaseline(
            value: kNightScalarPaperHrvBaseline,
            status: kNightScalarTrustedBaseline,
            nValid: 30,
          ),
          windowStartMs: onsetMs,
          windowEndMs: wakeMs,
        );

        NightScalarRow selectedRhr({bool partial = false}) => NightScalarRow(
          day: kNightScalarPaperDay,
          algoVersion: kAlgoVersion,
          partial: partial,
          value: 54,
          computedAtMs: computedAtMs,
          deviceFamily: 'gen5',
          sleepSource: 'auto',
          baseline: const StoredNightBaseline(
            value: kNightScalarPaperRhrBaseline,
            status: kNightScalarTrustedBaseline,
            nValid: 30,
          ),
          windowStartMs: onsetMs,
          windowEndMs: wakeMs,
        );

        Map<String, NightScalarRow> paperHrvMatching() {
          final days = nightScalarDaysEnding(kNightScalarPaperDay, 30);
          final start = days.length - kNightScalarPaperHrv.length;
          return {
            for (var i = 0; i < kNightScalarPaperHrv.length; i++)
              days[start + i]: NightScalarRow(
                day: days[start + i],
                algoVersion: kAlgoVersion,
                value: kNightScalarPaperHrv[i],
              ),
          };
        }

        Map<String, NightScalarRow> paperRhrMatching() {
          final days = nightScalarDaysEnding(kNightScalarPaperDay, 30);
          final start = days.length - kNightScalarPaperRhr.length;
          return {
            for (var i = 0; i < kNightScalarPaperRhr.length; i++)
              days[start + i]: NightScalarRow(
                day: days[start + i],
                algoVersion: kAlgoVersion,
                value: kNightScalarPaperRhr[i],
              ),
          };
        }

        Map<String, NightScalarJob> failedJobs() => {
          kNightScalarPaperDay: NightScalarJob(
            day: kNightScalarPaperDay,
            status: 'failed',
          ),
        };

        Map<String, NightScalarRow> historyMatching(
          Map<String, NightScalarRow> paper,
          NightScalarRow? selected,
        ) {
          if (selected == null) return paper;
          return {...paper, selected.day: selected};
        }

        void seedPair(
          SyntheticOpenBandRepository repo, {
          NightScalarRow? hrv,
          NightScalarRow? rhr,
          bool missing = false,
          Map<String, NightScalarJob> sleepJobs = const {},
          Map<String, NightScalarJob> napJobs = const {},
        }) {
          final selectedH = missing ? null : (hrv ?? selectedHrv());
          final selectedR = missing ? null : (rhr ?? selectedRhr());
          repo.seedNightScalarDetail(
            key: MetricKey.hrv,
            selected: selectedH,
            matching: missing
                ? const {}
                : historyMatching(paperHrvMatching(), selectedH),
            sleepJobs: sleepJobs,
            napJobs: napJobs,
            currentAlgo: kAlgoVersion,
          );
          repo.seedNightScalarDetail(
            key: MetricKey.restingHr,
            selected: selectedR,
            matching: missing
                ? const {}
                : historyMatching(paperRhrMatching(), selectedR),
            sleepJobs: sleepJobs,
            napJobs: napJobs,
            currentAlgo: kAlgoVersion,
          );
        }

        Future<void> openGallery({
          SyntheticScenario scenario = SyntheticScenario.complete,
          Brightness brightness = Brightness.light,
          double? scale,
          void Function(SyntheticOpenBandRepository)? seed,
        }) async {
          final repository = await loadGalleryRepository();
          repository.scenario = scenario;
          seed?.call(repository);
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
        }

        Future<void> tapCard(int index) async {
          final cards = find.byType(OBMetricCard);
          await tester.ensureVisible(cards.at(index));
          await tester.pumpAndSettle();
          await tester.tap(cards.at(index));
          await tester.pumpAndSettle();
        }

        Future<void> openStrainDetail() async {
          await tester.tap(find.bySemanticsLabel(RegExp(r'^Belastung, ')));
          await tester.pumpAndSettle();
          expect(find.text('Belastung'), findsWidgets);
          expect(find.text('Tag für Tag'), findsOneWidget);
          expect(find.textContaining('von 30 Tagen'), findsOneWidget);
          expect(find.text('Verlauf in der Nacht'), findsNothing);
          expect(find.text('So entsteht die Basis'), findsNothing);
        }

        Future<void> backFromStrain() async {
          await reviewTapHeaderBack(tester);
          expect(find.text('Tag für Tag'), findsNothing);
        }

        Future<void> expectDetailLoaded() async {
          await tester.pump();
          var waited = 0;
          while (find
                  .byKey(const ValueKey('night-scalar-detail'))
                  .evaluate()
                  .isEmpty ||
              (find.textContaining('von ').evaluate().isEmpty &&
                  find.text('Erneut').evaluate().isEmpty &&
                  find.text('Noch kein Nachtwert').evaluate().isEmpty &&
                  find.text(kNightScalarFailedLabel).evaluate().isEmpty)) {
            if (++waited > 80) {
              throw FlutterError('Night scalar detail did not finish loading.');
            }
            await tester.pump(const Duration(milliseconds: 16));
          }
          await reviewPumpPageTransitions(tester);
        }

        Future<void> backFromDetail() async {
          await reviewTapHeaderBack(tester);
          expect(
            find.byKey(const ValueKey('night-scalar-detail')),
            findsNothing,
          );
        }

        Future<void> backFromSleep() async {
          expect(find.byType(OpenBandSleep), findsOneWidget);
          await reviewTapHeaderBack(tester);
          expect(find.byType(OpenBandSleep), findsNothing);
        }

        void expectCardValues({
          required String hrv,
          required String rhr,
          required String hrvStatus,
          required String rhrStatus,
          required bool units,
        }) {
          final cards = find.byWidgetPredicate(
            (widget) =>
                widget is OBMetricCard &&
                (widget.label == 'HRV' || widget.label == 'Ruhepuls'),
          );
          expect(cards, findsNWidgets(2));
          expect(
            find.descendant(of: cards.at(0), matching: find.text(hrv)),
            findsOneWidget,
          );
          expect(
            find.descendant(of: cards.at(1), matching: find.text(rhr)),
            findsOneWidget,
          );
          expect(
            find.descendant(of: cards.at(0), matching: find.text(hrvStatus)),
            findsOneWidget,
          );
          expect(
            find.descendant(of: cards.at(1), matching: find.text(rhrStatus)),
            findsOneWidget,
          );
          expect(
            find.descendant(of: cards.at(0), matching: find.text('ms')),
            units ? findsOneWidget : findsNothing,
          );
          expect(
            find.descendant(of: cards.at(1), matching: find.text('/min')),
            units ? findsOneWidget : findsNothing,
          );
        }

        await openGallery(seed: seedPair);
        expectCardValues(
          hrv: '48',
          rhr: '54',
          hrvStatus: '+8 über Basis',
          rhrStatus: '−2 unter Basis',
          units: true,
        );
        await capture('night-cards-overview-light');
        await tapCard(0);
        await expectDetailLoaded();
        expect(find.text('48'), findsOneWidget);
        expect(find.text('+8 über Basis'), findsOneWidget);
        await capture('night-cards-overview-hrv-detail');
        await backFromDetail();
        await tapCard(1);
        await expectDetailLoaded();
        expect(find.text('54'), findsOneWidget);
        expect(find.text('−2 unter Basis'), findsOneWidget);
        await capture('night-cards-overview-rhr-detail');
        await backFromDetail();
        await openStrainDetail();
        await capture('night-cards-overview-strain-detail');
        await backFromStrain();

        await tester.tap(find.text('Gesundheit'));
        await tester.pumpAndSettle();
        expectCardValues(
          hrv: '48',
          rhr: '54',
          hrvStatus: '+8 über Basis',
          rhrStatus: '−2 unter Basis',
          units: true,
        );
        await capture('night-cards-health-light');
        await tapCard(0);
        await expectDetailLoaded();
        expect(find.text('48'), findsOneWidget);
        expect(find.text('+8 über Basis'), findsOneWidget);
        await capture('night-cards-health-hrv-detail');
        await backFromDetail();
        await tapCard(1);
        await expectDetailLoaded();
        expect(find.text('54'), findsOneWidget);
        expect(find.text('−2 unter Basis'), findsOneWidget);
        await backFromDetail();

        await tester.tap(find.text('Übersicht'));
        await tester.pumpAndSettle();
        final sleepRing = find.bySemanticsLabel(RegExp(r'^Schlaf, '));
        await tester.scrollUntilVisible(
          sleepRing,
          -300,
          scrollable: verticalScrollable().last,
        );
        await tester.pumpAndSettle();
        await tester.tap(sleepRing);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byWidgetPredicate(
            (widget) => widget is OBMetricCard && widget.label == 'HRV',
          ),
          200,
          scrollable: verticalScrollable().last,
        );
        await tester.pumpAndSettle();
        expectCardValues(
          hrv: '48',
          rhr: '54',
          hrvStatus: '+8 über Basis',
          rhrStatus: '−2 unter Basis',
          units: true,
        );
        await capture('night-cards-sleep-light');
        await tapCard(0);
        await expectDetailLoaded();
        expect(find.text('48'), findsOneWidget);
        expect(find.text('+8 über Basis'), findsOneWidget);
        await capture('night-cards-sleep-hrv-detail');
        await backFromDetail();
        await tapCard(1);
        await expectDetailLoaded();
        expect(find.text('54'), findsOneWidget);
        expect(find.text('−2 unter Basis'), findsOneWidget);
        await capture('night-cards-sleep-rhr-detail');
        await backFromDetail();
        await backFromSleep();

        await openGallery(brightness: Brightness.dark, seed: seedPair);
        expectCardValues(
          hrv: '48',
          rhr: '54',
          hrvStatus: '+8 über Basis',
          rhrStatus: '−2 unter Basis',
          units: true,
        );
        await capture('night-cards-overview-dark');
        await openStrainDetail();
        await capture('night-cards-overview-strain-detail-dark');
        await backFromStrain();
        await tester.tap(find.text('Gesundheit'));
        await tester.pumpAndSettle();
        await capture('night-cards-health-dark');

        await openGallery(
          scenario: SyntheticScenario.missing,
          seed: (repo) => seedPair(repo, missing: true),
        );
        expectCardValues(
          hrv: '—',
          rhr: '—',
          hrvStatus: 'Kein Nachtwert',
          rhrStatus: 'Kein Nachtwert',
          units: false,
        );
        expect(find.text('48'), findsNothing);
        expect(find.text('54'), findsNothing);
        await capture('night-cards-overview-missing');
        await tapCard(0);
        await expectDetailLoaded();
        expect(find.text('Noch kein Nachtwert'), findsOneWidget);
        expect(find.text('48'), findsNothing);
        expect(find.text(kNightScalarFailedLabel), findsNothing);
        await capture('night-cards-overview-missing-detail');
        await backFromDetail();
        await tapCard(1);
        await expectDetailLoaded();
        expect(find.text('Noch kein Nachtwert'), findsOneWidget);
        expect(find.text('54'), findsNothing);
        expect(find.text(kNightScalarFailedLabel), findsNothing);
        await backFromDetail();

        await openGallery(
          scenario: SyntheticScenario.partial,
          seed: (repo) => seedPair(
            repo,
            hrv: selectedHrv(partial: true),
            rhr: selectedRhr(partial: true),
          ),
        );
        expectCardValues(
          hrv: '48',
          rhr: '54',
          hrvStatus: 'Unvollständig',
          rhrStatus: 'Unvollständig',
          units: true,
        );
        expect(find.textContaining('Basis'), findsNothing);
        await capture('night-cards-overview-partial');
        await tapCard(0);
        await expectDetailLoaded();
        expect(find.text('48'), findsOneWidget);
        expect(find.text('Unvollständige Nacht'), findsOneWidget);
        expect(find.text('+8 über Basis'), findsNothing);
        await capture('night-cards-overview-partial-detail');
        await backFromDetail();
        await tapCard(1);
        await expectDetailLoaded();
        expect(find.text('54'), findsOneWidget);
        expect(find.text('Unvollständige Nacht'), findsOneWidget);
        expect(find.text('−2 unter Basis'), findsNothing);
        await backFromDetail();
        await tester.tap(find.text('Gesundheit'));
        await tester.pumpAndSettle();
        expect(find.text('7 von 7 Nächten · teilweise'), findsWidgets);
        expect(find.textContaining('Basis'), findsNothing);
        await capture('night-cards-health-partial');

        await openGallery(
          scenario: SyntheticScenario.partial,
          brightness: Brightness.dark,
          seed: (repo) => seedPair(
            repo,
            hrv: selectedHrv(partial: true),
            rhr: selectedRhr(partial: true),
          ),
        );
        await tester.tap(find.text('Gesundheit'));
        await tester.pumpAndSettle();
        expect(find.text('7 von 7 Nächten · teilweise'), findsWidgets);
        await capture('night-cards-health-partial-dark');

        await openGallery(
          seed: (repo) =>
              seedPair(repo, sleepJobs: failedJobs(), napJobs: failedJobs()),
        );
        expectCardValues(
          hrv: '—',
          rhr: '—',
          hrvStatus: kNightScalarFailedLabel,
          rhrStatus: kNightScalarFailedLabel,
          units: false,
        );
        expect(find.text('48'), findsNothing);
        expect(find.text('Kein Nachtwert'), findsNothing);
        await capture('night-cards-overview-error');
        await tapCard(0);
        await expectDetailLoaded();
        expect(find.text(kNightScalarFailedLabel), findsWidgets);
        expect(find.text('48'), findsNothing);
        expect(find.text('Noch kein Nachtwert'), findsNothing);
        await capture('night-cards-overview-error-detail');
        await backFromDetail();
        await tapCard(1);
        await expectDetailLoaded();
        expect(find.text(kNightScalarFailedLabel), findsWidgets);
        expect(find.text('54'), findsNothing);
        expect(find.text('Noch kein Nachtwert'), findsNothing);
        await backFromDetail();

        await openGallery(scale: 2, seed: seedPair);
        await tester.scrollUntilVisible(
          find.byWidgetPredicate(
            (widget) => widget is OBMetricCard && widget.label == 'HRV',
          ),
          200,
          scrollable: verticalScrollable().last,
        );
        await tester.pumpAndSettle();
        expect(find.byType(OBMetricCard), findsNWidgets(2));
        await capture('night-cards-overview-2x');
        await tester.tap(find.text('Gesundheit'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byWidgetPredicate(
            (widget) => widget is OBMetricCard && widget.label == 'HRV',
          ),
          200,
          scrollable: verticalScrollable().last,
        );
        await tester.pumpAndSettle();
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is OBMetricCard &&
                (widget.label == 'HRV' || widget.label == 'Ruhepuls'),
          ),
          findsNWidgets(2),
        );
        await capture('night-cards-health-2x');
        await tester.tap(find.text('Übersicht'));
        await tester.pumpAndSettle();
        final largeSleepRing = find.bySemanticsLabel(RegExp(r'^Schlaf, '));
        await tester.scrollUntilVisible(
          largeSleepRing,
          -300,
          scrollable: verticalScrollable().last,
        );
        await tester.pumpAndSettle();
        await tester.tap(largeSleepRing);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byWidgetPredicate(
            (widget) => widget is OBMetricCard && widget.label == 'HRV',
          ),
          200,
          scrollable: verticalScrollable().last,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(OBMetricCard).at(1));
        await tester.pumpAndSettle();
        expect(find.byType(OBMetricCard), findsNWidgets(2));
        expectCardValues(
          hrv: '48',
          rhr: '54',
          hrvStatus: '+8 über Basis',
          rhrStatus: '−2 unter Basis',
          units: true,
        );
        await capture('night-cards-sleep-2x');
        expect(tester.takeException(), isNull);
      }

      Future<void> reviewRespiration() async {
        final now = DateTime(2026, 9, 18, 9, 41);
        final onsetMs = DateTime(2026, 9, 14, 23, 10).millisecondsSinceEpoch;
        final wakeMs = DateTime(2026, 9, 15, 6, 54).millisecondsSinceEpoch;
        final computedAtMs = DateTime(2026, 9, 15, 7, 2).millisecondsSinceEpoch;

        Finder verticalScrollable() => find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        );

        Future<SyntheticOpenBandRepository> loadRepo() async {
          Future<Map> load(String name) async =>
              jsonDecode(
                    await rootBundle.loadString(
                      'docs/openband5/assets/fixtures/$name.json',
                    ),
                  )
                  as Map;
          return SyntheticOpenBandRepository.fromMaps(
            await load('day-summary'),
            await load('sleep-detail'),
            activity: await load('additional-flows'),
            run: await load('run-detail'),
          );
        }

        Map<String, NightScalarRow> paperResp({
          int? algo,
          bool partial = false,
        }) {
          final days = nightScalarDaysEnding(kNightScalarPaperDay, 30);
          final start = days.length - kNightScalarPaperResp.length;
          return {
            for (var i = 0; i < kNightScalarPaperResp.length; i++)
              days[start + i]: NightScalarRow(
                day: days[start + i],
                algoVersion: algo ?? kAlgoVersion,
                value: kNightScalarPaperResp[i],
                partial: partial && days[start + i] == kNightScalarPaperDay,
              ),
          };
        }

        NightScalarRow selectedResp({
          bool partial = false,
          NightScalarEnvelope? envelope,
          String? sleepSource = 'auto',
          String? deviceFamily = 'gen5',
        }) => NightScalarRow(
          day: kNightScalarPaperDay,
          algoVersion: kAlgoVersion,
          partial: partial,
          value: kNightScalarPaperRespRate,
          computedAtMs: computedAtMs,
          sleepSource: sleepSource,
          deviceFamily: deviceFamily,
          envelope: envelope,
          windowStartMs: onsetMs,
          windowEndMs: wakeMs,
        );

        void seedPaper(
          SyntheticOpenBandRepository repository, {
          NightScalarRow? selected,
          Map<String, NightScalarRow>? matching,
          Map<String, NightScalarJob> sleepJobs = const {},
          Map<String, NightScalarJob> napJobs = const {},
        }) {
          repository.seedNightScalarDetail(
            key: MetricKey.respiration,
            selected: selected ?? selectedResp(),
            matching: matching ?? paperResp(),
            sleepJobs: sleepJobs,
            napJobs: napJobs,
            currentAlgo: kAlgoVersion,
          );
        }

        Widget reviewHost({
          required Widget home,
          Brightness brightness = Brightness.light,
          double scale = 1,
        }) => MaterialApp(
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
          home: home,
        );

        Future<void> pumpUntil(bool Function() ready, String message) async {
          await tester.pump();
          var waited = 0;
          while (!ready()) {
            if (++waited > 80) throw FlutterError(message);
            await tester.pump(const Duration(milliseconds: 16));
          }
          await reviewPumpPageTransitions(tester);
        }

        bool nightScalarLoaded() =>
            find
                .byKey(const ValueKey('night-scalar-detail'))
                .evaluate()
                .isNotEmpty &&
            (find.textContaining('von ').evaluate().isNotEmpty ||
                find.text('Erneut').evaluate().isNotEmpty ||
                find.text('Noch kein Nachtwert').evaluate().isNotEmpty);

        Finder detailText(String text) => find.descendant(
          of: find.byKey(const ValueKey('night-scalar-detail')),
          matching: find.text(text),
        );

        Finder cardText(String text) => find.descendant(
          of: find.byKey(const ValueKey('atemfrequenz')),
          matching: find.text(text),
        );

        Future<OpenBandController> mountDetail({
          required SyntheticOpenBandRepository repository,
          Brightness brightness = Brightness.light,
          double scale = 1,
        }) async {
          final controller = OpenBandController(
            repository: repository,
            initialDay: kNightScalarPaperDay,
            band: repository.band,
            now: () => now,
          );
          await controller.refresh();
          await tester.pumpWidget(
            reviewHost(
              brightness: brightness,
              scale: scale,
              home: OpenBandNightScalarDetail(
                controller: controller,
                metricKey: MetricKey.respiration,
                label: 'Atmung',
                unit: '/min',
                icon: LucideIcons.wind,
                color: (p) => p.sleep,
                tint: (p) => p.sleepTint,
                digits: 1,
              ),
            ),
          );
          await pumpUntil(
            nightScalarLoaded,
            'Respiration detail did not finish loading.',
          );
          return controller;
        }

        var repo = await loadRepo();
        seedPaper(repo);
        await mountDetail(repository: repo);
        expect(detailText('Atmung'), findsOneWidget);
        expect(detailText('16,0'), findsOneWidget);
        expect(detailText('15 von 30 Nächten'), findsOneWidget);
        expect(detailText('Basis noch offen'), findsOneWidget);
        expect(detailText('HRV'), findsNothing);
        expect(detailText('Ruhepuls'), findsNothing);
        await capture('resp');
        await tester.tap(find.text('Nachtverlauf'));
        await reviewPumpPageTransitions(tester);
        await pumpUntil(
          () =>
              find.byType(OpenBandNightSignals).evaluate().isNotEmpty &&
              find.byType(OBNightSignalChart).evaluate().isNotEmpty,
          'Night signals did not load.',
        );
        final nightTabs = tester.widget<OBSegmented>(
          find.byWidgetPredicate(
            (widget) =>
                widget is OBSegmented &&
                widget.labels.contains('Puls') &&
                widget.labels.contains('Atmung'),
          ),
        );
        expect(nightTabs.selected, NightSignalKind.respiration.index);
        await capture('resp-night-route');
        await reviewTapHeaderBack(tester);
        await pumpUntil(
          () =>
              find.byType(OpenBandNightSignals).evaluate().isEmpty &&
              detailText('16,0').evaluate().isNotEmpty &&
              nightScalarLoaded(),
          'Respiration detail did not return.',
        );
        expect(detailText('16,0'), findsOneWidget);
        await tester.tap(find.byTooltip('Information'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          find.textContaining('Atemfrequenz · gespeicherter Wert'),
          findsOneWidget,
        );
        expect(find.textContaining('Qualitätswert'), findsNothing);
        expect(find.textContaining('Normalbereich'), findsNothing);
        await capture('resp-info');
        await tester.tap(find.text('Schließen'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('7 Nächte'));
        await tester.pumpAndSettle();
        expect(find.textContaining('von 7 Nächten'), findsOneWidget);
        await capture('resp-seven');
        await tester.tap(find.text('90 Nächte'));
        await tester.pumpAndSettle();
        expect(find.text('15 von 90 Nächten'), findsOneWidget);
        await capture('resp-ninety');

        repo = await loadRepo();
        seedPaper(repo);
        await mountDetail(repository: repo, brightness: Brightness.dark);
        expect(detailText('16,0'), findsOneWidget);
        await capture('resp-dark');
        await tester.tap(find.text('7 Nächte'));
        await tester.pumpAndSettle();
        await capture('resp-seven-dark');

        repo = await loadRepo();
        repo.seedNightScalarDetail(
          key: MetricKey.respiration,
          selected: null,
          matching: const {},
          currentAlgo: kAlgoVersion,
        );
        await mountDetail(repository: repo);
        expect(find.text('Noch kein Nachtwert'), findsOneWidget);
        expect(find.text('0 von 30 Nächten'), findsOneWidget);
        await capture('resp-missing');
        repo = await loadRepo();
        repo.seedNightScalarDetail(
          key: MetricKey.respiration,
          selected: null,
          matching: const {},
          currentAlgo: kAlgoVersion,
        );
        await mountDetail(repository: repo, brightness: Brightness.dark);
        await capture('resp-missing-dark');

        repo = await loadRepo();
        seedPaper(
          repo,
          selected: selectedResp(partial: true),
          matching: paperResp(partial: true),
        );
        await mountDetail(repository: repo);
        expect(find.text('Unvollständige Nacht'), findsOneWidget);
        expect(detailText('16,0'), findsOneWidget);
        expect(find.textContaining('teils unvollständig'), findsOneWidget);
        await capture('resp-partial');
        repo = await loadRepo();
        seedPaper(
          repo,
          selected: selectedResp(partial: true),
          matching: paperResp(partial: true),
        );
        await mountDetail(repository: repo, brightness: Brightness.dark);
        await capture('resp-partial-dark');

        repo = await loadRepo();
        seedPaper(repo);
        repo.failNightScalarRead = true;
        await mountDetail(repository: repo);
        expect(find.text('Erneut'), findsOneWidget);
        await capture('resp-error');
        repo.failNightScalarRead = false;
        await tester.tap(find.text('Erneut'));
        await tester.pumpAndSettle();
        expect(detailText('16,0'), findsOneWidget);
        await capture('resp-error-retry');
        repo = await loadRepo();
        seedPaper(repo);
        repo.failNightScalarRead = true;
        await mountDetail(repository: repo, brightness: Brightness.dark);
        await capture('resp-error-dark');

        repo = await loadRepo();
        seedPaper(
          repo,
          selected: selectedResp(
            envelope: const NightScalarEnvelope(
              tier: 'HIGH',
              confidence: 0.8,
              inputsUsed: ['rr'],
              note: 'rsa ok',
              brpm: 16.5,
              peakHz: 0.275,
              power: 1.25,
              source: 'rr_spectrum',
            ),
          ),
        );
        await mountDetail(repository: repo);
        await tester.tap(find.byTooltip('Information'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.textContaining('Stufe HIGH'), findsOneWidget);
        expect(find.textContaining('Qualitätswert 0,8 / 1'), findsOneWidget);
        expect(
          find.textContaining('RSA-Atemfrequenz 16,5 /min'),
          findsOneWidget,
        );
        expect(find.textContaining('Spektralspitze 0,275 Hz'), findsOneWidget);
        expect(find.textContaining('Spektralleistung 1,25'), findsOneWidget);
        expect(find.textContaining('Methode rr_spectrum'), findsOneWidget);
        expect(find.textContaining('Unsicherheit'), findsNothing);
        await capture('resp-info-envelope');
        await tester.tap(find.text('Schließen'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        repo = await loadRepo();
        seedPaper(repo);
        await mountDetail(repository: repo, scale: 2);
        expect(detailText('16,0'), findsOneWidget);
        await capture('resp-2x');
        await tester.drag(find.byType(ListView), const Offset(0, -520));
        await tester.pumpAndSettle();
        await capture('resp-2x-lower');

        repo = await loadRepo();
        seedPaper(repo);
        await mountDetail(
          repository: repo,
          brightness: Brightness.dark,
          scale: 2,
        );
        expect(detailText('16,0'), findsOneWidget);
        await capture('resp-2x-dark');
        await tester.drag(find.byType(ListView), const Offset(0, -520));
        await tester.pumpAndSettle();
        await capture('resp-2x-dark-lower');

        repo = await loadRepo();
        seedPaper(repo);
        final controller = OpenBandController(
          repository: repo,
          initialDay: kNightScalarPaperDay,
          band: repo.band,
          now: () => now,
        );
        await controller.refresh();
        await tester.pumpWidget(
          reviewHost(
            home: Scaffold(
              body: SafeArea(child: OpenBandHealth(controller: controller)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final respirationCard = find.byKey(const ValueKey('atemfrequenz'));
        await tester.scrollUntilVisible(
          respirationCard,
          200,
          scrollable: verticalScrollable().last,
        );
        await Scrollable.ensureVisible(
          tester.element(respirationCard),
          alignment: 0.25,
        );
        await tester.pumpAndSettle();
        expect(cardText('16,0'), findsOneWidget);
        await capture('resp-health-entry');
        await tester.tap(find.text('Atemfrequenz'));
        await reviewPumpPageTransitions(tester);
        await pumpUntil(
          nightScalarLoaded,
          'Health did not open respiration detail.',
        );
        expect(detailText('Atmung'), findsOneWidget);
        expect(detailText('16,0'), findsOneWidget);
        await capture('resp-health-detail');
        await reviewTapHeaderBack(tester);
        await pumpUntil(
          () =>
              find
                  .byKey(const ValueKey('night-scalar-detail'))
                  .evaluate()
                  .isEmpty &&
              find.text('Atemfrequenz').evaluate().isNotEmpty,
          'Health did not return from respiration.',
        );
        expect(find.text('Atemfrequenz'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      Future<void> reviewTemperature() async {
        final now = DateTime(2026, 9, 18, 9, 41);

        Future<SyntheticOpenBandRepository> loadRepo() async {
          Future<Map> load(String name) async =>
              jsonDecode(
                    await rootBundle.loadString(
                      'docs/openband5/assets/fixtures/$name.json',
                    ),
                  )
                  as Map;
          return SyntheticOpenBandRepository.fromMaps(
            await load('day-summary'),
            await load('sleep-detail'),
            activity: await load('additional-flows'),
            run: await load('run-detail'),
          );
        }

        void seed(
          SyntheticOpenBandRepository repository,
          NightScalarUnit unit, {
          bool partial = false,
          String? rowSource,
          String? payloadSource,
        }) {
          final days = nightScalarDaysEnding(kNightScalarPaperDay, 30);
          final values = unit == NightScalarUnit.celsius
              ? kNightScalarPaperSkinTempC
              : kNightScalarPaperSkinTempSd;
          final start = days.length - values.length;
          final source = switch (unit) {
            NightScalarUnit.sd => 'band',
            NightScalarUnit.celsius => 'whoop_export',
            NightScalarUnit.unknown => 'cloud_v2',
          };
          NightScalarRow row(String day, double value) => NightScalarRow(
            day: day,
            algoVersion: kAlgoVersion,
            value: value,
            partial: partial && day == kNightScalarPaperDay,
            imported: unit == NightScalarUnit.celsius,
            rowSource: rowSource ?? source,
            source: payloadSource ?? source,
          );
          repository.seedNightScalarDetail(
            key: MetricKey.skinTemperature,
            selected: NightScalarRow(
              day: kNightScalarPaperDay,
              algoVersion: kAlgoVersion,
              value: unit == NightScalarUnit.celsius ? 33.2 : 0.4,
              partial: partial,
              imported: unit == NightScalarUnit.celsius,
              rowSource: rowSource ?? source,
              source: payloadSource ?? source,
              deviceFamily: 'gen5',
              computedAtMs: DateTime(2026, 9, 15, 7, 2).millisecondsSinceEpoch,
            ),
            matching: {
              for (var i = 0; i < values.length; i++)
                if (values[i] != null)
                  days[start + i]: row(days[start + i], values[i]!),
            },
            currentAlgo: kAlgoVersion,
          );
        }

        Widget host(
          Widget home, {
          Brightness brightness = Brightness.light,
          double scale = 1,
        }) => MaterialApp(
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
          home: home,
        );

        Future<OpenBandController> mount(
          SyntheticOpenBandRepository repository, {
          Brightness brightness = Brightness.light,
          double scale = 1,
          bool expectError = false,
          bool expectSourceVisible = true,
        }) async {
          final controller = OpenBandController(
            repository: repository,
            initialDay: kNightScalarPaperDay,
            band: repository.band,
            now: () => now,
          );
          await controller.refresh();
          await tester.pumpWidget(
            host(
              OpenBandNightScalarDetail(
                controller: controller,
                metricKey: MetricKey.skinTemperature,
                label: 'Hauttemperatur',
                unit: '',
                icon: LucideIcons.thermometer,
                color: (p) => p.ink,
                tint: (p) => p.well,
                digits: 1,
              ),
              brightness: brightness,
              scale: scale,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('night-scalar-detail')),
            findsOneWidget,
          );
          if (expectError) {
            expect(
              find.text('Nachtwerte konnten nicht geladen werden.'),
              findsOneWidget,
            );
            expect(find.text('Erneut'), findsOneWidget);
            expect(find.text('Quelle'), findsNothing);
          } else {
            expect(find.text('Erneut'), findsNothing);
            if (expectSourceVisible) {
              expect(find.text('Quelle'), findsOneWidget);
            } else {
              expect(find.byType(OBSegmented), findsOneWidget);
              expect(find.text('30 Nächte'), findsOneWidget);
            }
          }
          return controller;
        }

        var repository = await loadRepo();
        seed(repository, NightScalarUnit.sd);
        await mount(repository);
        await capture('temperature-sd');
        await tester.tap(find.byTooltip('Information'));
        await tester.pumpAndSettle();
        await capture('temperature-info-sd');
        await tester.tap(find.text('Schließen'));
        await tester.pumpAndSettle();
        for (final period in ['7 Nächte', '90 Nächte']) {
          await tester.tap(find.text(period));
          await tester.pumpAndSettle();
          await capture(
            'temperature-${period.startsWith('7') ? 'seven' : 'ninety'}',
          );
        }

        repository = await loadRepo();
        seed(repository, NightScalarUnit.sd);
        await mount(repository, brightness: Brightness.dark);
        await capture('temperature-sd-dark');

        for (final unit in [NightScalarUnit.celsius, NightScalarUnit.unknown]) {
          for (final brightness in [Brightness.light, Brightness.dark]) {
            repository = await loadRepo();
            seed(repository, unit);
            await mount(repository, brightness: brightness);
            await capture('temperature-${unit.name}-${brightness.name}');
          }
        }

        repository = await loadRepo();
        seed(
          repository,
          NightScalarUnit.unknown,
          rowSource: 'band',
          payloadSource: 'whoop_export',
        );
        await mount(repository);
        expect(find.text('Uneindeutig'), findsOneWidget);
        await capture('temperature-conflict');
        await tester.tap(find.byTooltip('Information'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Quellen: Band / WHOOP-Export'),
          findsOneWidget,
        );
        await capture('temperature-info-conflict');

        repository = await loadRepo();
        seed(repository, NightScalarUnit.sd, partial: true);
        await mount(repository);
        await capture('temperature-partial');

        repository = await loadRepo();
        repository.seedNightScalarDetail(
          key: MetricKey.skinTemperature,
          selected: null,
          matching: const {},
          currentAlgo: kAlgoVersion,
        );
        await mount(repository);
        await capture('temperature-missing');

        repository = await loadRepo();
        seed(repository, NightScalarUnit.sd);
        repository.failNightScalarRead = true;
        await mount(repository, expectError: true);
        await capture('temperature-error');
        repository.failNightScalarRead = false;
        await tester.tap(find.text('Erneut'));
        await tester.pumpAndSettle();
        expect(find.text('+0,4'), findsOneWidget);
        expect(find.text('Quelle'), findsOneWidget);
        expect(find.text('Erneut'), findsNothing);
        await capture('temperature-error-retry');

        for (final brightness in [Brightness.light, Brightness.dark]) {
          repository = await loadRepo();
          seed(repository, NightScalarUnit.sd);
          await mount(
            repository,
            brightness: brightness,
            scale: 2,
            expectSourceVisible: false,
          );
          expect(find.text('+0,4'), findsOneWidget);
          expect(find.text('14 von 30 Nächten'), findsOneWidget);
          await capture('temperature-2x-${brightness.name}');
          await tester.scrollUntilVisible(
            find.text('Quelle'),
            250,
            scrollable: verticalScrollable().last,
          );
          await tester.pumpAndSettle();
          expect(find.text('Quelle'), findsOneWidget);
          await capture('temperature-2x-lower-${brightness.name}');
        }

        repository = await loadRepo();
        seed(repository, NightScalarUnit.sd);
        final controller = OpenBandController(
          repository: repository,
          initialDay: kNightScalarPaperDay,
          band: repository.band,
          now: () => now,
        );
        await controller.refresh();
        await tester.pumpWidget(
          host(
            Scaffold(
              body: SafeArea(child: OpenBandHealth(controller: controller)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final card = find.byKey(const ValueKey('hauttemperatur'));
        await tester.scrollUntilVisible(
          card,
          200,
          scrollable: verticalScrollable().last,
        );
        await Scrollable.ensureVisible(tester.element(card), alignment: .25);
        await tester.pumpAndSettle();
        await capture('temperature-health-entry');
        await tester.tap(card);
        await tester.pumpAndSettle();
        await capture('temperature-health-detail');
        await reviewTapHeaderBack(tester);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('hauttemperatur')), findsOneWidget);
        expect(find.byType(OpenBandNightSignals), findsNothing);
        expect(tester.takeException(), isNull);
      }

      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['flow'] = kOpenBandReviewFlow;
      if (kOpenBandReviewFlow == 'release') {
        Future<void> openMesswerte(String name) async {
          final row = find.byKey(const ValueKey('alle-messwerte'));
          final scrollable = verticalScrollable().last;
          tester.state<ScrollableState>(scrollable).position.jumpTo(0);
          await tester.pump();
          await tester.scrollUntilVisible(row, 200, scrollable: scrollable);
          await tester.ensureVisible(row);
          await tester.pumpAndSettle();
          await tester.tap(row);
          await tester.pumpAndSettle();
          expect(find.text('MESSWERTE'), findsOneWidget);
          expect(find.text('7 Nächte'), findsNothing);
          expect(find.text('Laborwerte'), findsNothing);
          expect(find.text('Glukose'), findsNothing);
          expect(find.byKey(const ValueKey('atemfrequenz')), findsOneWidget);
          expect(find.byKey(const ValueKey('hauttemperatur')), findsOneWidget);
          final back = tester.getRect(find.byTooltip('Zurück').last);
          final inset = tester.view.padding.top / tester.view.devicePixelRatio;
          expect(
            back.top,
            greaterThanOrEqualTo(inset),
            reason: 'Messwerte header must clear the status-bar inset',
          );
          await capture(name);
          await reviewTapHeaderBack(tester);
        }

        await mount(release: true);
        expect(find.text('Training'), findsNothing);
        expect(find.text('Journal'), findsNothing);
        expect(find.text('Wasser'), findsNothing);
        expect(find.text('Energie'), findsNothing);
        expect(find.text('Alle Messwerte'), findsOneWidget);
        expect(find.text('Dein Journal'), findsNothing);
        await capture('release-happy-light');
        await tester.scrollUntilVisible(
          find.text('SCHRITTE'),
          300,
          scrollable: verticalScrollable().last,
        );
        await capture('release-happy-light-bottom');
        await openMesswerte('release-messwerte-light');

        await mount(release: true, brightness: Brightness.dark);
        await capture('release-happy-dark');
        await tester.scrollUntilVisible(
          find.text('SCHRITTE'),
          300,
          scrollable: verticalScrollable().last,
        );
        await capture('release-happy-dark-bottom');
        await openMesswerte('release-messwerte-dark');

        await mount(release: true, scenario: SyntheticScenario.missing);
        expect(find.text('Tief'), findsNothing);
        expect(find.text('Wasser'), findsNothing);
        await capture('release-missing');
        await openMesswerte('release-messwerte-missing');

        await mount(release: true, failRead: true);
        expect(find.text('Daten konnten nicht geladen werden.'), findsOneWidget);
        expect(find.text('Alle Messwerte'), findsNothing);
        await capture('release-error');

        await mount(release: true, scale: 2);
        expect(find.text('Training'), findsNothing);
        await capture('release-large');
        await tester.scrollUntilVisible(
          find.text('SCHRITTE'),
          300,
          scrollable: verticalScrollable().last,
        );
        await capture('release-large-bottom');

        Future<void> openReleaseProfile() async {
          await tester.tap(find.byTooltip('Profil'));
          await tester.pumpAndSettle();
          if (find.text('Daten & Sicherung').evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              find.byKey(const ValueKey('profile-data')),
              250,
              scrollable: verticalScrollable().last,
            );
            await tester.pumpAndSettle();
          }
          expect(find.text('Daten & Sicherung'), findsOneWidget);
          expect(find.text('Community'), findsNothing);
        }

        Future<void> openReleaseData() async {
          final data = find.text('Daten & Sicherung');
          await tester.ensureVisible(data);
          await tester.tap(data);
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('data-export-database')),
              findsOneWidget);
          expect(find.text('Glukose'), findsNothing);
        }

        for (final brightness in [Brightness.light, Brightness.dark]) {
          final suffix = brightness == Brightness.light ? 'light' : 'dark';
          await mount(release: true, brightness: brightness);
          await openReleaseProfile();
          await capture('release-profile-$suffix');
          await openReleaseData();
          await capture('release-data-$suffix');
        }

        await mount(release: true, scale: 2);
        await openReleaseProfile();
        await capture('release-profile-large');
        await openReleaseData();
        await capture('release-data-large');
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('data-reanalyze')),
          220,
          scrollable: verticalScrollable().last,
        );
        await capture('release-data-large-bottom');

        await mount(release: true);
        await openReleaseProfile();
        await openReleaseData();
        final exportDatabase = find.byKey(const ValueKey('data-export-database'));
        await tester.tap(exportDatabase);
        await tester.pumpAndSettle();
        final exportFailure = find.textContaining('synthetischer Schreibfehler');
        await tester.ensureVisible(exportFailure);
        expect(exportFailure, findsOneWidget);
        await capture('release-data-export-error');
        await tester.ensureVisible(exportDatabase);
        await tester.tap(exportDatabase);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Export erstellt'));
        expect(exportFailure, findsNothing);
        await capture('release-data-export-retry');
        final cadence = find.byKey(const ValueKey('data-backup-cadence'));
        await tester.ensureVisible(cadence);
        await tester.tap(cadence);
        await tester.pumpAndSettle();
        expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

        const restoreReceipt = ImportOutcome(
          source: 'OpenStrap backup',
          restoredRows: 12,
          unchangedRows: 3,
          restoreConflicts: 1,
          unreadableRows: 1,
          pendingRecalculations: 2,
        );
        await reviewMountImportReceipt(tester, restoreReceipt);
        expect(find.text('Teilweise importiert'), findsOneWidget);
        expect(find.text('12 Einträge gespeichert'), findsOneWidget);
        expect(find.text('1 Konflikt · lokal beibehalten'), findsOneWidget);
        await capture('release-restore-partial');
        await reviewMountImportReceipt(
          tester, restoreReceipt, brightness: Brightness.dark,
        );
        await capture('release-restore-partial-dark');
        await reviewMountImportReceipt(tester, restoreReceipt, scale: 2);
        await tester.ensureVisible(find.text('2 Neuberechnungen ausstehend'));
        await capture('release-restore-partial-large');

        Future<void> mountBandView(
          Widget child, {
          Brightness brightness = Brightness.light,
          double scale = 1,
        }) async {
          await tester.pumpWidget(MaterialApp(
            key: UniqueKey(),
            debugShowCheckedModeBanner: false,
            locale: const Locale('de'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            theme: openBandTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
              ),
              child: child!,
            ),
            home: child,
          ));
          await tester.pumpAndSettle();
        }

        var pairingActions = 0;
        Widget pairingFixture({PairPhase initial = PairPhase.idle}) {
          var phase = initial;
          return StatefulBuilder(builder: (context, setState) => PairingView(
            phase: phase,
            blocker: phase == PairPhase.bluetoothBlocked
                ? BleBlocker.permissionDenied : null,
            onPair: () {
              pairingActions++;
              setState(() => phase = PairPhase.bluetoothBlocked);
            },
            onBack: () => pairingActions++,
            onSkip: () => pairingActions++,
          ));
        }

        for (final brightness in [Brightness.light, Brightness.dark]) {
          final suffix = brightness == Brightness.light ? 'light' : 'dark';
          await mountBandView(pairingFixture(), brightness: brightness);
          expect(find.text('WHOOP 5.0'), findsOneWidget);
          await capture('release-pairing-$suffix');
          final pairAction = find.byType(OBAction).first;
          await tester.tap(pairAction);
          await tester.pumpAndSettle();
          expect(pairingActions, greaterThan(0));
          expect(find.text('WHOOP 5.0'), findsNothing);
          await capture('release-pairing-permission-$suffix');
        }
        await mountBandView(pairingFixture(), scale: 2);
        await capture('release-pairing-large');
        await tester.scrollUntilVisible(
          find.text('WHOOP-App schließen'), 200,
          scrollable: verticalScrollable().last,
        );
        await capture('release-pairing-large-bottom');

        var resumeCalls = 0;
        var doneCalls = 0;
        FirstSyncScreen syncFixture() {
          var band = BandSnapshot(
            connection: BandConnection.connected,
            transfer: TransferState.interrupted,
            latestStoredAt: DateTime(2026, 9, 15, 2, 10),
          );
          return FirstSyncScreen(
            synthetic: true,
            now: () => DateTime(2026, 9, 15, 9, 41),
            onDone: () => doneCalls++,
            readBand: () async => band,
            readSetupEvaluation: (day) async => SetupEvaluation(
              day: day, currentAlgo: kAlgoVersion,
              state: SetupEvalState.missing,
            ),
            onResume: () async {
              resumeCalls++;
              band = BandSnapshot(
                connection: resumeCalls == 1
                    ? BandConnection.disconnected : BandConnection.connected,
                transfer: TransferState.idle,
                latestStoredAt: DateTime(2026, 9, 15, 2, 10),
              );
            },
          );
        }
        for (final brightness in [Brightness.light, Brightness.dark]) {
          final suffix = brightness == Brightness.light ? 'light' : 'dark';
          resumeCalls = 0;
          await mountBandView(syncFixture(), brightness: brightness);
          expect(find.text('bis 02:10'), findsOneWidget);
          await capture('release-sync-interrupted-$suffix');
          await tester.tap(find.text('Fortsetzen'));
          await tester.pumpAndSettle();
          expect(resumeCalls, 1);
          expect(find.text('Verbunden'), findsNothing);
          expect(find.text('Erneut'), findsOneWidget);
          await capture('release-sync-failed-$suffix');
          await tester.tap(find.text('Erneut'));
          await tester.pumpAndSettle();
          expect(resumeCalls, 2);
          expect(find.text('Verbunden'), findsOneWidget);
          expect(find.text('Erneut'), findsNothing);
          expect(find.text('bis 02:10'), findsOneWidget);
          await capture('release-sync-retry-$suffix');
          await tester.tap(find.text('Weiter zum Profil'));
          await tester.pumpAndSettle();
        }
        expect(doneCalls, 2);
        resumeCalls = 0;
        await mountBandView(syncFixture(), scale: 2);
        await capture('release-sync-large');
        await tester.ensureVisible(find.text('Fortsetzen'));
        await capture('release-sync-large-bottom');
        await tester.tap(find.text('Weiter zum Profil'));
        await tester.pumpAndSettle();
        expect(doneCalls, 3);

        final sensorQuery = TextEditingController();
        var scanCalls = 0;
        BleBlocker? scanBlocker = BleBlocker.permissionDenied;
        await mountBandView(StatefulBuilder(
          builder: (context, setState) => DevicePickerView(
            query: sensorQuery,
            title: 'Sensor verbinden',
            subtitle: 'Synthetische Daten',
            scanBlocker: scanBlocker,
            onScan: () => setState(() {
              scanCalls++;
              scanBlocker = null;
            }),
          ),
        ));
        await capture('release-sensor-permission');
        final retry = find.text(AppLocalizations.of(
          tester.element(find.byType(DevicePickerView)),
        )!.pairingTryAgain);
        await tester.tap(retry);
        await tester.pumpAndSettle();
        expect(scanCalls, 1);
        await capture('release-sensor-empty');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        sensorQuery.dispose();
        return;
      }
      if (kOpenBandReviewFlow == 'journal' ||
          kOpenBandReviewFlow == 'journal-hub') {
        await reviewJournal();
        return;
      }
      if (kOpenBandReviewFlow == 'nutrition-entry') {
        await reviewNutritionEntry();
        return;
      }
      if (kOpenBandReviewFlow == 'nutrition-parent') {
        await reviewNutritionParent();
        return;
      }
      if (kOpenBandReviewFlow == 'sleep-plan') {
        await reviewSleepPlan();
        return;
      }
      if (kOpenBandReviewFlow == 'exercise-picker') {
        await reviewExercisePicker();
        return;
      }
      if (kOpenBandReviewFlow == 'custom-exercise') {
        await reviewCustomExercise();
        return;
      }
      if (kOpenBandReviewFlow == 'exercise-copy') {
        await reviewExerciseCopy();
        return;
      }
      if (kOpenBandReviewFlow == 'custom-load') {
        await reviewCustomLoad();
        return;
      }
      if (kOpenBandReviewFlow == 'glucose') {
        await reviewGlucose();
        return;
      }
      if (kOpenBandReviewFlow == 'medications') {
        await reviewMedications();
        return;
      }
      if (kOpenBandReviewFlow == 'cycle') {
        await reviewCycle();
        return;
      }
      if (kOpenBandReviewFlow == 'cycle-measurements') {
        await reviewCycleMeasurements();
        return;
      }
      if (kOpenBandReviewFlow == 'cycle-observations') {
        await reviewCycleObservations();
        return;
      }
      if (kOpenBandReviewFlow == 'cycle-gaps') {
        await reviewCycleGaps();
        return;
      }
      if (kOpenBandReviewFlow == 'cycle-medians') {
        await reviewCycleMedians();
        return;
      }
      if (kOpenBandReviewFlow == 'cycle-comparison') {
        await reviewCycleComparison();
        return;
      }
      if (kOpenBandReviewFlow == 'night-scalar') {
        await reviewNightScalar();
        return;
      }
      if (kOpenBandReviewFlow == 'night-cards') {
        await reviewNightCards();
        return;
      }
      if (kOpenBandReviewFlow == 'sleep-legend') {
        await reviewSleepLegend();
        return;
      }
      if (kOpenBandReviewFlow == 'respiration') {
        await reviewRespiration();
        return;
      }
      if (kOpenBandReviewFlow == 'temperature') {
        await reviewTemperature();
        return;
      }
      if (kOpenBandReviewFlow == 'weight') {
        await reviewWeight();
        return;
      }
      if (kOpenBandReviewFlow == 'vo2') {
        await reviewVo2();
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

      if (kOpenBandReviewFlow == 'correction') {
        await mount();
        await edit();
        await capture('correction-edit');
        await mount(brightness: Brightness.dark);
        await edit(variant: '-dark');
        await capture('correction-edit-dark');
        await mount(scale: 2);
        await edit(variant: '-large');
        await tester.ensureVisible(find.byKey(const ValueKey('sleep-wake')));
        await tester.enterText(
          find.byKey(const ValueKey('sleep-wake')),
          '06:54',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await capture('correction-large-edit');
        return;
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
      await capture('correction-edit');
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
      await capture('correction-edit-dark');
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
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await capture('correction-large-edit');
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

      await reviewWeight();
      await reviewNutritionEntry();
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
