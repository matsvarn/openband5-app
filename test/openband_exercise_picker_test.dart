import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/exercise_definition_editor.dart';
import 'package:openstrap_edge/openband/exercise_picker.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/template_editor.dart';
import 'package:openstrap_edge/openband/theme.dart';

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

const _fiveIds = {
  'bench_press',
  'leg_press',
  'cable_fly',
  'pull_up',
  'plank',
};

Map _summary() =>
    jsonDecode(
          File(
            'docs/openband5/assets/fixtures/day-summary.json',
          ).readAsStringSync(),
        )
        as Map;

Map _detail() =>
    jsonDecode(
          File(
            'docs/openband5/assets/fixtures/sleep-detail.json',
          ).readAsStringSync(),
        )
        as Map;

ExerciseCatalogue fiveCatalogue({
  int unreadable = 0,
  List<ExerciseCatalogueEntry> extra = const [],
}) => ExerciseCatalogue(
  entries: [
    for (final e in kExercisePresets)
      if (_fiveIds.contains(e.id)) e.asEntry,
    ...extra,
  ],
  unreadableCount: unreadable,
);

ExerciseCatalogueEntry unknownRow() => ExerciseCatalogueEntry(
  id: 'imported_row',
  label: 'Rudern am Gerät',
  equipment: ExerciseEquipmentCategory.machine,
  source: ExerciseDefinitionSource.stored,
);

class _CatRepo extends SyntheticOpenBandRepository {
  _CatRepo({
    ExerciseCatalogue? catalogue,
    this.failCatalogue = false,
  }) : catalogue = catalogue ?? fiveCatalogue(),
       super.fromMaps(_summary(), _detail());

  ExerciseCatalogue catalogue;
  bool failCatalogue;

  @override
  Future<ExerciseCatalogue> readExerciseCatalogue() async {
    if (failCatalogue) throw StateError('fail');
    return catalogue;
  }

  @override
  Future<CustomExerciseWriteResult> createCustomExercise(
    CustomExerciseDraft draft,
  ) async {
    final result = await super.createCustomExercise(draft);
    if (result.saved && result.current != null) {
      catalogue = ExerciseCatalogue(
        entries: [
          for (final e in catalogue.entries)
            if (e.id != result.current!.id) e,
          result.current!,
        ],
        unreadableCount: catalogue.unreadableCount,
      );
    }
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('de_DE');
    for (final (family, path) in [
      ('Inter', 'assets/fonts/Inter/Inter.ttf'),
      ('Inter Tight', 'assets/fonts/InterTight/InterTight[wght].ttf'),
    ]) {
      final loader = FontLoader(family)
        ..addFont(
          Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
        );
      await loader.load();
    }
    final icons = FontLoader('packages/lucide_icons_flutter/Lucide')
      ..addFont(
        rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
      );
    await icons.load();
  });

  Future<void> pumpPicker(
    WidgetTester tester, {
    _CatRepo? repo,
    Set<String> existing = const {},
    Brightness brightness = Brightness.light,
    double scale = 1,
    double width = 393,
    double height = 852,
    double dpr = 1,
    bool createOnOpen = false,
    ExerciseCaptureMode? initialCreateMode,
  }) async {
    repo ??= _CatRepo();
    tester.view.devicePixelRatio = dpr;
    tester.view.physicalSize = Size(width * dpr, height * dpr);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(brightness).copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: OpenBandExercisePicker(
          repository: repo,
          existingExerciseIds: existing,
          createOnOpen: createOnOpen,
          initialCreateMode: initialCreateMode,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<List<ExerciseCatalogueEntry>?> openAndPick(
    WidgetTester tester, {
    required _CatRepo repo,
    Set<String> existing = const {},
    required Future<void> Function() interact,
  }) async {
    List<ExerciseCatalogueEntry>? picked;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  picked = await Navigator.of(ctx).push(
                    MaterialPageRoute(
                      builder: (_) => OpenBandExercisePicker(
                        repository: repo,
                        existingExerciseIds: existing,
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await interact();
    return picked;
  }

  Future<void> selectBenchAndPlank(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('exercise-select-bench_press')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('exercise-select-plank')));
    await tester.pumpAndSettle();
  }

  test('empty timed planned set is timed for live slots without invented duration', () {
    final slots = strengthPlanSlots(
      WorkoutTemplate(
        id: 't',
        name: 't',
        version: 1,
        exercises: [
          PlannedExercise(
            id: 'e',
            exerciseKey: 'plank',
            name: 'Plank',
            sets: const [PlannedSet(id: 's', mode: PlannedSetMode.time)],
          ),
        ],
        updatedAt: DateTime(2026, 9, 1),
      ),
      const [],
    );
    expect(slots.single.timed, isTrue);
    expect(slots.single.plannedSetId, 's');
  });

  testWidgets('selection persists across search, filter and detail', (
    tester,
  ) async {
    final repo = _CatRepo();
    final picked = await openAndPick(
      tester,
      repo: repo,
      interact: () async {
        await selectBenchAndPlank(tester);
        await tester.enterText(
          find.byKey(const ValueKey('exercise-search')),
          'Bank',
        );
        await tester.pumpAndSettle();
        expect(find.text('Bankdrücken'), findsOneWidget);
        expect(find.text('Unterarmstütz'), findsNothing);
        expect(find.text('1 Übung · 1 Auswahl außerhalb'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('exercise-search')),
          '',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Muskelgruppen'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Brust'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Langhantel'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Zurück').last);
        await tester.pumpAndSettle();
        expect(find.text('5 Übungen'), findsOneWidget);
        await tester.tap(find.text('Muskelgruppen'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Brust'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Langhantel'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Filter anwenden'));
        await tester.pumpAndSettle();
        expect(find.text('1 Übung · 1 Auswahl außerhalb'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('exercise-open-bench_press')));
        await tester.pumpAndSettle();
        expect(find.text('Auswahl entfernen'), findsOneWidget);
        await tester.tap(find.byTooltip('Zurück').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('2 Übungen hinzufügen'));
        await tester.tap(find.text('2 Übungen hinzufügen'));
        await tester.pumpAndSettle();
      },
    );
    expect(picked, isNotNull);
    expect(picked!.map((e) => e.id), ['bench_press', 'plank']);
  });

  testWidgets('filter cancel leaves picker filters unchanged', (tester) async {
    await pumpPicker(tester);
    await tester.tap(find.text('Muskelgruppen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brust'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zurück').last);
    await tester.pumpAndSettle();
    expect(find.text('Bankdrücken'), findsOneWidget);
    expect(find.text('Unterarmstütz'), findsOneWidget);
    expect(find.text('Muskelgruppen'), findsOneWidget);
  });

  testWidgets('hidden selection count stays visible while filtered', (
    tester,
  ) async {
    await pumpPicker(tester);
    await selectBenchAndPlank(tester);
    await tester.tap(find.text('Muskelgruppen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brust'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Langhantel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filter anwenden'));
    await tester.pumpAndSettle();
    expect(find.text('Brust'), findsWidgets);
    expect(find.text('Langhantel'), findsWidgets);
    expect(find.text('1 Übung · 1 Auswahl außerhalb'), findsOneWidget);
    expect(find.text('Bankdrücken'), findsOneWidget);
    expect(find.text('Unterarmstütz'), findsNothing);
  });

  testWidgets('empty catalogue is distinct from no search match', (
    tester,
  ) async {
    await pumpPicker(
      tester,
      repo: _CatRepo(catalogue: const ExerciseCatalogue(entries: [])),
    );
    expect(find.text('Keine Übungen'), findsOneWidget);
    expect(find.text('Keine Übungen gefunden'), findsNothing);
    expect(find.text('Suche löschen'), findsNothing);
    expect(find.text('0 Übungen'), findsOneWidget);

    await pumpPicker(tester);
    await tester.enterText(
      find.byKey(const ValueKey('exercise-search')),
      'Ausfallschritte',
    );
    await tester.pumpAndSettle();
    expect(find.text('Keine Übungen gefunden'), findsOneWidget);
    expect(find.text('Keine Übungen'), findsNothing);
    expect(find.text('Suche löschen'), findsOneWidget);
    expect(find.text('0 Übungen'), findsOneWidget);
    await tester.tap(find.text('Suche löschen'));
    await tester.pumpAndSettle();
    expect(find.text('Bankdrücken'), findsOneWidget);
  });

  testWidgets('read error is retryable and not a false empty', (tester) async {
    final repo = _CatRepo(failCatalogue: true);
    await pumpPicker(tester, repo: repo);
    expect(find.text('Bibliothek nicht geladen'), findsOneWidget);
    expect(find.text('Keine Übungen'), findsNothing);
    expect(find.text('— Übungen'), findsNothing);
    expect(find.text('Übung suchen'), findsNothing);
    expect(find.text('Muskelgruppen'), findsNothing);
    repo.failCatalogue = false;
    await tester.tap(find.text('Erneut laden'));
    await tester.pumpAndSettle();
    expect(find.text('Bankdrücken'), findsOneWidget);
    expect(find.text('5 Übungen'), findsOneWidget);
  });

  testWidgets('partial unreadable count is concise', (tester) async {
    await pumpPicker(
      tester,
      repo: _CatRepo(catalogue: fiveCatalogue(unreadable: 2)),
    );
    expect(find.text('5 Übungen · 2 nicht lesbar'), findsOneWidget);
  });

  testWidgets('unknown mode is visible, marked and not selectable', (
    tester,
  ) async {
    await pumpPicker(
      tester,
      repo: _CatRepo(
        catalogue: fiveCatalogue(extra: [unknownRow()]),
      ),
    );
    expect(find.text('Rudern am Gerät'), findsOneWidget);
    expect(find.textContaining('Erfassungsart offen'), findsOneWidget);
    final plus = tester.widget<IconButton>(
      find.byKey(const ValueKey('exercise-select-imported_row')),
    );
    expect(plus.onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('exercise-open-imported_row')));
    await tester.pumpAndSettle();
    expect(find.text('Gespeichert'), findsNothing);
    expect(find.text('Importiert'), findsNothing);
    expect(find.text('OpenBand'), findsNothing);
    expect(find.text('Nicht festgelegt'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
    expect(find.text('Auswählen'), findsOneWidget);
    final action = tester.widget<OBAction>(find.widgetWithText(OBAction, 'Auswählen'));
    expect(action.onPressed, isNull);
  });

  testWidgets('same-name distinct keys stay independent', (tester) async {
    final twin = ExerciseCatalogueEntry(
      id: 'bench_press_custom',
      label: 'Bankdrücken',
      mode: ExerciseCaptureMode.repetitions,
      equipment: ExerciseEquipmentCategory.dumbbell,
      source: ExerciseDefinitionSource.stored,
      retained: {'custom': 1},
    );
    final picked = await openAndPick(
      tester,
      repo: _CatRepo(catalogue: fiveCatalogue(extra: [twin])),
      interact: () async {
        await tester.tap(
          find.byKey(const ValueKey('exercise-select-bench_press')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('exercise-select-bench_press_custom')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('2 Übungen hinzufügen'));
        await tester.pumpAndSettle();
      },
    );
    expect(picked!.map((e) => e.id), ['bench_press', 'bench_press_custom']);
  });

  testWidgets('in-plan repeat confirms; cancel and rapid taps stay single', (
    tester,
  ) async {
    final repo = _CatRepo();
    final picked = await openAndPick(
      tester,
      repo: repo,
      existing: const {'bench_press'},
      interact: () async {
        final plus = find.byKey(const ValueKey('exercise-select-bench_press'));
        await tester.tap(plus);
        await tester.pump();
        await tester.tap(plus, warnIfMissed: false);
        await tester.pump();
        await tester.tap(plus, warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.text('Übung erneut hinzufügen?'), findsOneWidget);
        await tester.tap(find.text('Abbrechen'));
        await tester.pumpAndSettle();
        expect(find.text('0 Übungen hinzufügen'), findsOneWidget);
        await tester.tap(plus);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Hinzufügen'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('1 Übung hinzufügen'));
        await tester.tap(find.text('1 Übung hinzufügen'));
        await tester.pumpAndSettle();
      },
    );
    expect(picked, hasLength(1));
    expect(picked!.single.id, 'bench_press');
  });

  testWidgets('search matches German and English aliases', (tester) async {
    await pumpPicker(tester);
    await tester.enterText(
      find.byKey(const ValueKey('exercise-search')),
      'Plank',
    );
    await tester.pumpAndSettle();
    expect(find.text('Unterarmstütz'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('exercise-search')),
      'Bench press',
    );
    await tester.pumpAndSettle();
    expect(find.text('Bankdrücken'), findsOneWidget);
    expect(find.text('Unterarmstütz'), findsNothing);
  });

  testWidgets('Ohne Zuordnung matches null equipment via shared filter', (
    tester,
  ) async {
    final free = ExerciseCatalogueEntry(
      id: 'hip_thrust',
      label: 'Hüftstoßen',
      mode: ExerciseCaptureMode.repetitions,
      source: ExerciseDefinitionSource.preset,
    );
    await pumpPicker(
      tester,
      repo: _CatRepo(catalogue: fiveCatalogue(extra: [free])),
    );
    await tester.tap(find.text('Geräte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ohne Zuordnung'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filter anwenden'));
    await tester.pumpAndSettle();
    expect(find.text('Hüftstoßen'), findsOneWidget);
    expect(find.text('Bankdrücken'), findsNothing);
  });

  testWidgets('confirm adds one empty set each; cancel leaves draft', (
    tester,
  ) async {
    final repo = _CatRepo();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: OpenBandTemplateEditor(repository: repo),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Kurztraining');
    await tester.tap(find.text('Übung hinzufügen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bibliothek'));
    await tester.pumpAndSettle();
    await selectBenchAndPlank(tester);
    await tester.tap(find.byTooltip('Zurück').last);
    await tester.pumpAndSettle();
    expect(find.text('Bankdrücken'), findsNothing);
    expect(find.byType(OpenBandTemplateEditor), findsOneWidget);

    await tester.tap(find.text('Übung hinzufügen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bibliothek'));
    await tester.pumpAndSettle();
    await selectBenchAndPlank(tester);
    await tester.ensureVisible(find.text('2 Übungen hinzufügen'));
    await tester.tap(find.text('2 Übungen hinzufügen'));
    await tester.pumpAndSettle();
    expect(find.text('Bankdrücken'), findsOneWidget);
    expect(find.text('Unterarmstütz'), findsOneWidget);
    await tester.tap(find.text('Vorlage speichern'));
    await tester.pumpAndSettle();

    final saved = (await repo.readTemplates()).firstWhere(
      (t) => t.name == 'Kurztraining',
    );
    expect(saved.exercises, hasLength(2));
    expect(saved.exercises.map((e) => e.exerciseKey), [
      'bench_press',
      'plank',
    ]);
    expect(saved.exercises.map((e) => e.id).every(_uuid.hasMatch), isTrue);
    expect(saved.exercises.first.id, isNot(saved.exercises.first.exerciseKey));
    expect(saved.exercises.first.sets, hasLength(1));
    expect(saved.exercises.first.sets.single.mode, PlannedSetMode.repetitions);
    expect(saved.exercises.first.sets.single.reps, isNull);
    expect(saved.exercises.first.sets.single.seconds, isNull);
    expect(saved.exercises.first.sets.single.loadKg, isNull);
    expect(saved.exercises.first.sets.single.restSec, isNull);
    expect(saved.exercises.last.sets.single.mode, PlannedSetMode.time);
    expect(saved.exercises.last.sets.single.seconds, isNull);
    expect(saved.exercises.last.sets.single.reps, isNull);
    expect(saved.exercises.first.definition?.id, 'bench_press');
  });

  testWidgets('saving failure retains library draft', (tester) async {
    final repo = _CatRepo();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: OpenBandTemplateEditor(repository: repo),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Halt');
    await tester.tap(find.text('Übung hinzufügen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bibliothek'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('exercise-select-plank')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('1 Übung hinzufügen'));
    await tester.tap(find.text('1 Übung hinzufügen'));
    await tester.pumpAndSettle();
    repo.failTemplateWrite = true;
    await tester.tap(find.text('Vorlage speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen.'), findsOneWidget);
    expect(find.text('Unterarmstütz'), findsOneWidget);
    expect(find.byType(OpenBandTemplateEditor), findsOneWidget);
    expect(
      (await repo.readTemplates()).where((t) => t.name == 'Halt'),
      isEmpty,
    );
  });

  testWidgets('goldens: picker selected light/dark/375-2x', (tester) async {
    await pumpPicker(tester);
    await selectBenchAndPlank(tester);
    await expectLater(
      find.byType(OpenBandExercisePicker),
      matchesGoldenFile('openband_goldens/exercise-picker.png'),
    );
    await pumpPicker(tester, brightness: Brightness.dark);
    await selectBenchAndPlank(tester);
    await expectLater(
      find.byType(OpenBandExercisePicker),
      matchesGoldenFile('openband_goldens/exercise-picker-dark.png'),
    );
    await pumpPicker(tester, scale: 2, width: 375, height: 1600);
    await selectBenchAndPlank(tester);
    await expectLater(
      find.byType(OpenBandExercisePicker),
      matchesGoldenFile('openband_goldens/exercise-375-2x.png'),
    );
  });

  testWidgets('goldens: filter, filtered, detail, empty, error, partial', (
    tester,
  ) async {
    await pumpPicker(tester);
    await tester.tap(find.text('Muskelgruppen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brust'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Langhantel'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/exercise-filter.png'),
    );

    await pumpPicker(tester, brightness: Brightness.dark);
    await tester.tap(find.text('Muskelgruppen'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/exercise-filter-dark.png'),
    );

    await pumpPicker(tester);
    await selectBenchAndPlank(tester);
    await tester.tap(find.text('Muskelgruppen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brust'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Langhantel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filter anwenden'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(OpenBandExercisePicker),
      matchesGoldenFile('openband_goldens/exercise-filtered.png'),
    );

    await pumpPicker(tester);
    await tester.tap(find.byKey(const ValueKey('exercise-open-bench_press')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/exercise-detail.png'),
    );
    await pumpPicker(tester, brightness: Brightness.dark);
    await tester.tap(find.byKey(const ValueKey('exercise-open-bench_press')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/exercise-detail-dark.png'),
    );

    await pumpPicker(tester);
    await tester.enterText(
      find.byKey(const ValueKey('exercise-search')),
      'Ausfallschritte',
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(OpenBandExercisePicker),
      matchesGoldenFile('openband_goldens/exercise-empty.png'),
    );
    await pumpPicker(tester, brightness: Brightness.dark);
    await tester.enterText(
      find.byKey(const ValueKey('exercise-search')),
      'Ausfallschritte',
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(OpenBandExercisePicker),
      matchesGoldenFile('openband_goldens/exercise-empty-dark.png'),
    );

    await pumpPicker(tester, repo: _CatRepo(failCatalogue: true));
    await expectLater(
      find.byType(OpenBandExercisePicker),
      matchesGoldenFile('openband_goldens/exercise-error.png'),
    );
    await pumpPicker(
      tester,
      repo: _CatRepo(failCatalogue: true),
      brightness: Brightness.dark,
    );
    await expectLater(
      find.byType(OpenBandExercisePicker),
      matchesGoldenFile('openband_goldens/exercise-error-dark.png'),
    );

    await pumpPicker(
      tester,
      repo: _CatRepo(catalogue: fiveCatalogue(unreadable: 2)),
    );
    await selectBenchAndPlank(tester);
    await expectLater(
      find.byType(OpenBandExercisePicker),
      matchesGoldenFile('openband_goldens/exercise-partial.png'),
    );
    await pumpPicker(
      tester,
      repo: _CatRepo(catalogue: fiveCatalogue(unreadable: 2)),
      brightness: Brightness.dark,
    );
    await selectBenchAndPlank(tester);
    await expectLater(
      find.byType(OpenBandExercisePicker),
      matchesGoldenFile('openband_goldens/exercise-partial-dark.png'),
    );

    await pumpPicker(
      tester,
      repo: _CatRepo(catalogue: fiveCatalogue(extra: [unknownRow()])),
    );
    await tester.tap(find.byKey(const ValueKey('exercise-open-imported_row')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/exercise-unknown.png'),
    );
  });

  testWidgets('goldens: add sheet and parent editor', (tester) async {
    final repo = _CatRepo();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(Brightness.light).copyWith(
          platform: TargetPlatform.iOS,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: OpenBandTemplateEditor(repository: repo),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übung hinzufügen'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/exercise-add-sheet.png'),
    );
    await tester.tap(find.text('Bibliothek'));
    await tester.pumpAndSettle();
    await selectBenchAndPlank(tester);
    await tester.tap(find.text('2 Übungen hinzufügen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Kurztraining');
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(OpenBandTemplateEditor),
      matchesGoldenFile('openband_goldens/exercise-parent.png'),
    );
  });

  testWidgets('goldens: mixed legacy blank duration light/dark', (tester) async {
    Finder hinted(String hint) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == hint,
    );
    Future<void> mount(Brightness brightness) async {
      final repo = _CatRepo();
      await repo.saveTemplate(
        WorkoutTemplate(
          id: 'tpl-legacy-err',
          name: 'Altbestand',
          version: 1,
          exercises: [
            PlannedExercise(
              id: 'ex-hold',
              exerciseKey: 'plank',
              name: 'Halten',
              sets: [
                PlannedSet(
                  id: 'set-both',
                  reps: 8,
                  seconds: 40,
                  loadKg: 62.55,
                  restSec: 90,
                ),
              ],
            ),
          ],
          updatedAt: DateTime(2026, 9, 1),
        ),
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 852);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          debugShowCheckedModeBanner: false,
          locale: const Locale('de'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('de')],
          theme: openBandTheme(brightness).copyWith(
            platform: TargetPlatform.iOS,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.only(top: 59, bottom: 34),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: OpenBandTemplateEditor(
            repository: repo,
            template: (await repo.readTemplates()).firstWhere(
              (t) => t.id == 'tpl-legacy-err',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(hinted('Sek.'), '');
      await tester.pumpAndSettle();
    }

    await mount(Brightness.light);
    expect(find.text('Dauer fehlt.'), findsOneWidget);
    await expectLater(
      find.byType(OpenBandTemplateEditor),
      matchesGoldenFile('openband_goldens/exercise-legacy-error.png'),
    );
    await mount(Brightness.dark);
    await expectLater(
      find.byType(OpenBandTemplateEditor),
      matchesGoldenFile('openband_goldens/exercise-legacy-error-dark.png'),
    );
  });

  testWidgets('header plus and empty search open the editor', (tester) async {
    await pumpPicker(tester);
    await tester.tap(find.byTooltip('Eigene Übung'));
    await tester.pumpAndSettle();
    expect(find.byType(OpenBandExerciseDefinitionEditor), findsOneWidget);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('exercise-search')),
      'Ausfallschritte',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('exercise-create-search')));
    await tester.pumpAndSettle();
    expect(find.byType(OpenBandExerciseDefinitionEditor), findsOneWidget);
  });

  testWidgets('createOnOpen pushes typed editor once then returns unselected', (
    tester,
  ) async {
    await pumpPicker(
      tester,
      createOnOpen: true,
      initialCreateMode: ExerciseCaptureMode.time,
    );
    expect(find.byType(OpenBandExerciseDefinitionEditor), findsOneWidget);
    expect(find.text('Haltezeit'), findsOneWidget);
    expect(find.byKey(const ValueKey('custom-exercise-reps')), findsNothing);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.byType(OpenBandExercisePicker), findsOneWidget);
    expect(find.byType(OpenBandExerciseDefinitionEditor), findsNothing);
    expect(find.text('0 Übungen hinzufügen'), findsOneWidget);
    await tester.tap(find.byTooltip('Eigene Übung'));
    await tester.pumpAndSettle();
    expect(find.byType(OpenBandExerciseDefinitionEditor), findsOneWidget);
    expect(find.text('Haltezeit'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('custom-exercise-mode')),
        matching: find.text('Auswählen'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('generic picker does not auto-open the editor', (tester) async {
    await pumpPicker(tester);
    expect(find.byType(OpenBandExerciseDefinitionEditor), findsNothing);
    expect(find.byType(OpenBandExercisePicker), findsOneWidget);
  });

  testWidgets('unknown row still omits invented load lines', (tester) async {
    await pumpPicker(
      tester,
      repo: _CatRepo(catalogue: fiveCatalogue(extra: [unknownRow()])),
    );
    expect(find.textContaining('je Hantel'), findsNothing);
    expect(find.textContaining('Wdh.'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('exercise-open-imported_row')));
    await tester.pumpAndSettle();
    expect(find.text('Gewichtsangabe'), findsNothing);
    expect(find.text('Nicht festgelegt'), findsOneWidget);
  });

  testWidgets('unknown unselectable row is still copyable', (tester) async {
    await pumpPicker(
      tester,
      repo: _CatRepo(catalogue: fiveCatalogue(extra: [unknownRow()])),
    );
    await tester.tap(find.byKey(const ValueKey('exercise-open-imported_row')));
    await tester.pumpAndSettle();
    final select = tester.widget<OBAction>(
      find.widgetWithText(OBAction, 'Auswählen'),
    );
    expect(select.onPressed, isNull);
    expect(find.byTooltip('Kopieren'), findsOneWidget);
    await tester.tap(find.byTooltip('Kopieren'));
    await tester.pumpAndSettle();
    expect(find.byType(OpenBandExerciseDefinitionEditor), findsOneWidget);
    expect(find.text('Rudern am Gerät · Kopie'), findsOneWidget);
    expect(
      tester
          .widget<OBAction>(find.byKey(const ValueKey('custom-exercise-save')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('Zurück').last);
    await tester.pumpAndSettle();
    expect(find.text('Auswählen'), findsOneWidget);
    expect(
      tester.widget<OBAction>(find.widgetWithText(OBAction, 'Auswählen')).onPressed,
      isNull,
    );
  });

  testWidgets('copy does not select source; query stays put', (tester) async {
    final repo = _CatRepo();
    await pumpPicker(tester, repo: repo);
    await tester.enterText(
      find.byKey(const ValueKey('exercise-search')),
      'Bank',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('exercise-open-bench_press')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Kopieren'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('custom-exercise-load')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('custom-exercise-load-total')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('custom-exercise-reps')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('custom-exercise-reps-total')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('custom-exercise-save')));
    await tester.pumpAndSettle();
    expect(find.byType(OpenBandExercisePicker), findsOneWidget);
    expect(find.text('Bankdrücken'), findsOneWidget);
    expect(find.text('Bankdrücken · Kopie'), findsOneWidget);
    expect(find.text('0 Übungen hinzufügen'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('exercise-search'))).controller!.text,
      'Bank',
    );

    await tester.tap(find.byKey(const ValueKey('exercise-filter-muscles')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filter-muscle-chest')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filter anwenden'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('exercise-open-bench_press')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Kopieren'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zurück').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zurück').last);
    await tester.pumpAndSettle();
    expect(find.text('Bankdrücken'), findsWidgets);
    expect(find.text('Bankdrücken · Kopie'), findsOneWidget);
    expect(find.text('0 Übungen hinzufügen'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('exercise-filter-muscles')),
        matching: find.text('Brust'),
      ),
      findsOneWidget,
    );
  });
}
