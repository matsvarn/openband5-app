part of 'harness.dart';

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
      theme: openBandTheme(brightness).copyWith(platform: TargetPlatform.iOS),
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
              G2PageHeader(title: 'Datenimport', subtitle: '', onBack: () {}),
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
