import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/app.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/strength_live.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/ui2/activity/live.dart';
import 'package:openstrap_edge/ui2/theme.dart';
import 'package:provider/provider.dart';

SyntheticOpenBandRepository _repo() => SyntheticOpenBandRepository.fromMaps(
  jsonDecode(
        File(
          'docs/openband5/assets/fixtures/day-summary.json',
        ).readAsStringSync(),
      )
      as Map,
  jsonDecode(
        File(
          'docs/openband5/assets/fixtures/sleep-detail.json',
        ).readAsStringSync(),
      )
      as Map,
);

ExerciseDefinitionSnapshot _customDefinition({
  ExerciseLoadBasis basis = ExerciseLoadBasis.perDevice,
  ExerciseEquipmentCategory equipment = ExerciseEquipmentCategory.dumbbell,
  int? deviceCount = 2,
  ExerciseRepetitionBasis? repetitionBasis = ExerciseRepetitionBasis.perSide,
}) => ExerciseDefinitionSnapshot(
  id: 'custom-curl',
  label: 'Kurzhantel-Curl',
  source: ExerciseDefinitionSource.stored,
  version: 1,
  mode: ExerciseCaptureMode.repetitions,
  equipment: equipment,
  loadBasis: basis,
  deviceCount: deviceCount,
  repetitionBasis: repetitionBasis,
);

WorkoutTemplate _template({
  String name = 'Einheit',
  List<PlannedExercise>? exercises,
}) => WorkoutTemplate(
  id: 'tpl-test',
  name: name,
  version: 1,
  exercises:
      exercises ??
      const [
        PlannedExercise(
          id: 'ex-a',
          exerciseKey: 'bench_press',
          name: 'Bankdrücken',
          sets: [
            PlannedSet(id: 'a-1', reps: 8, loadKg: 40, restSec: 90),
            PlannedSet(id: 'a-2', reps: 8, loadKg: 40, restSec: 90),
          ],
        ),
      ],
  updatedAt: DateTime(2026, 9, 15),
);

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

  late SyntheticOpenBandRepository repo;
  late DateTime now;
  setUp(() {
    repo = _repo();
    now = DateTime(2026, 9, 15, 18, 32, 14);
    repo.strengthNow = () => now;
  });

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  Future<void> mount(
    WidgetTester tester, {
    Widget? child,
    Brightness brightness = Brightness.light,
    double width = 375,
    double dpr = 2,
    double scale = 1,
    bool resume = false,
    WorkoutTemplate? template,
  }) async {
    await unmount(tester);
    tester.view.devicePixelRatio = dpr;
    tester.view.physicalSize = Size(width * dpr, 812 * dpr);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        locale: const Locale('de'),
        debugShowCheckedModeBanner: false,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(
          Brightness.light,
        ).copyWith(platform: TargetPlatform.iOS),
        darkTheme: openBandTheme(
          Brightness.dark,
        ).copyWith(platform: TargetPlatform.iOS),
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: RepaintBoundary(key: const ValueKey('capture'), child: child!),
        ),
        home:
            child ??
            (resume
                ? OpenBandStrengthLive.resume(
                    key: UniqueKey(),
                    repository: repo,
                    now: () => now,
                  )
                : OpenBandStrengthLive(
                    key: UniqueKey(),
                    repository: repo,
                    template: template ?? _template(),
                    now: () => now,
                  )),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      Theme.of(tester.element(find.byType(OpenBandStrengthLive))).brightness,
      brightness,
    );
  }

  Future<void> mountPaper(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double scale = 1,
  }) async {
    repo = _repo();
    repo.strengthNow = () => now;
    await repo.seedPaperLiveStrength(
      startedAt: DateTime(2026, 9, 15, 18),
      now: now,
    );
    await mount(tester, resume: true, brightness: brightness, scale: scale);
  }

  testWidgets('start arms once and resume does not re-arm', (tester) async {
    await mount(tester);
    expect(repo.strengthStartCount, 1);
    expect(
      await repo.readActiveStrengthSession(),
      isA<ActiveStrengthSession>(),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await mount(tester, resume: true);
    expect(repo.strengthStartCount, 1);
    expect(find.text('Bankdrücken'), findsOneWidget);
    expect(find.text('kcal'), findsNothing);
    expect(find.textContaining('300'), findsNothing);
  });

  testWidgets('resume without an active session does not start another', (
    tester,
  ) async {
    await mount(tester, resume: true);
    expect(repo.strengthStartCount, 0);
    expect(find.text('Keine laufende Einheit.'), findsOneWidget);
    expect(await repo.readActiveStrengthSession(), isA<NoActiveStrength>());
  });

  testWidgets('WorkoutBusy binds the live session instead of retrying start', (
    tester,
  ) async {
    await repo.startStrengthSession(_template());
    expect(repo.strengthStartCount, 1);
    await mount(
      tester,
      template: _template(
        name: 'Andere',
        exercises: const [
          PlannedExercise(
            id: 'ex-other',
            exerciseKey: 'squat',
            name: 'Kniebeuge',
            sets: [PlannedSet(id: 'o-1', reps: 5, loadKg: 80, restSec: 90)],
          ),
        ],
      ),
    );
    expect(find.text('Eine Einheit läuft bereits.'), findsNothing);
    expect(find.text('Andere'), findsNothing);
    expect(find.text('Kniebeuge'), findsNothing);
    expect(find.text('Einheit'), findsOneWidget);
    expect(find.text('Bankdrücken'), findsOneWidget);
    expect(repo.strengthStartCount, 2);
    final live =
        await repo.readActiveStrengthSession() as ActiveStrengthSession;
    expect(live.plan.name, 'Einheit');
    expect(find.text('Erneut'), findsNothing);
  });

  testWidgets('corrupt resume is retryable and leaves the source', (
    tester,
  ) async {
    repo.seedCorruptActiveStrength();
    await mount(tester, resume: true);
    expect(find.text('Einheit konnte nicht gelesen werden.'), findsOneWidget);
    expect(find.text('Erneut'), findsOneWidget);
    await tester.tap(find.text('Erneut'));
    await tester.pump();
    expect(find.text('Einheit konnte nicht gelesen werden.'), findsOneWidget);
    expect(repo.strengthStartCount, 0);
    expect(
      await repo.readActiveStrengthSession(),
      isA<CorruptActiveStrength>(),
    );
  });

  testWidgets('recordSet keeps plannedSetId, exerciseId and restSec', (
    tester,
  ) async {
    await mount(tester);
    await tester.enterText(find.byType(TextField).first, '42,5');
    await tester.tap(find.byKey(const ValueKey('confirm-a-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final live =
        await repo.readActiveStrengthSession() as ActiveStrengthSession;
    expect(live.recorded, hasLength(1));
    expect(live.recorded.single.plannedSetId, 'a-1');
    expect(live.recorded.single.exerciseId, 'ex-a');
    expect(live.recorded.single.setIndex, 1);
    expect(live.recorded.single.restSec, 90);
    expect(live.recorded.single.loadKg, 42.5);
  });

  testWidgets('custom per-device original records 10x2 as 20 and eight reps', (
    tester,
  ) async {
    final definition = _customDefinition();
    final original = OriginalLoadInput(
      value: 10,
      unit: ExerciseLoadUnit.kg,
      basis: ExerciseLoadBasis.perDevice,
      deviceCount: 2,
      repetitionBasis: ExerciseRepetitionBasis.perSide,
      side: ExerciseSetSide.both,
    );
    await mount(
      tester,
      template: _template(
        exercises: [
          PlannedExercise(
            id: 'ex-custom',
            exerciseKey: definition.id,
            name: definition.label,
            definition: definition,
            sets: [
              PlannedSet(
                id: 'custom-1',
                reps: 8,
                loadKg: 20,
                mode: PlannedSetMode.repetitions,
                load: original,
              ),
            ],
          ),
        ],
      ),
    );

    expect(find.text('kg je Hantel · Wdh. je Seite'), findsOneWidget);
    expect(find.text('Beide Seiten'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      '10',
    );
    await tester.tap(find.byKey(const ValueKey('confirm-custom-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final live =
        await repo.readActiveStrengthSession() as ActiveStrengthSession;
    final recorded = live.recorded.single;
    expect(recorded.loadKg, 20);
    expect(recorded.reps, 8);
    expect(recorded.load?.value, 10);
    expect(recorded.load?.deviceCount, 2);
    expect(recorded.load?.side, ExerciseSetSide.both);
    expect(recorded.loadKg! * recorded.reps!, 160);
    expect(recorded.definition?.id, definition.id);
  });

  testWidgets(
    'left and right sets retain one actual device and unequal loads',
    (tester) async {
      final definition = _customDefinition();
      OriginalLoadInput original(double value, ExerciseSetSide side) =>
          OriginalLoadInput(
            value: value,
            unit: ExerciseLoadUnit.kg,
            basis: ExerciseLoadBasis.perDevice,
            deviceCount: 1,
            repetitionBasis: ExerciseRepetitionBasis.perSide,
            side: side,
          );
      await mount(
        tester,
        template: _template(
          name: 'Kurztraining',
          exercises: [
            PlannedExercise(
              id: 'ex-custom',
              exerciseKey: definition.id,
              name: definition.label,
              definition: definition,
              sets: [
                PlannedSet(
                  id: 'left',
                  reps: 8,
                  loadKg: 10,
                  load: original(10, ExerciseSetSide.left),
                ),
                PlannedSet(
                  id: 'right',
                  reps: 8,
                  loadKg: 12,
                  load: original(12, ExerciseSetSide.right),
                ),
              ],
            ),
          ],
        ),
      );
      expect(find.text('Links'), findsOneWidget);
      expect(find.text('Rechts'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm-left')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const ValueKey('confirm-right')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final live =
          await repo.readActiveStrengthSession() as ActiveStrengthSession;
      expect(live.recorded.map((s) => s.loadKg), [10, 12]);
      expect(live.recorded.map((s) => s.reps), [8, 8]);
      expect(live.recorded.map((s) => s.load?.deviceCount), [1, 1]);
      expect(live.recorded.map((s) => s.load?.side), [
        ExerciseSetSide.left,
        ExerciseSetSide.right,
      ]);
    },
  );

  testWidgets(
    'unit menu converts display while preserving normalized meaning',
    (tester) async {
      final definition = _customDefinition(
        repetitionBasis: ExerciseRepetitionBasis.total,
      );
      await mount(
        tester,
        template: _template(
          name: 'Kurztraining',
          exercises: [
            PlannedExercise(
              id: 'ex-custom',
              exerciseKey: definition.id,
              name: definition.label,
              definition: definition,
              sets: [
                PlannedSet(
                  id: 'custom-lb',
                  reps: 8,
                  loadKg: 20,
                  load: OriginalLoadInput(
                    value: 10,
                    unit: ExerciseLoadUnit.kg,
                    basis: ExerciseLoadBasis.perDevice,
                    deviceCount: 2,
                    repetitionBasis: ExerciseRepetitionBasis.total,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
      await tester.tap(find.byTooltip('Übungsmenü'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Einheit').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('lb'));
      await tester.pumpAndSettle();

      expect(find.text('LB'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField).first);
      final shown = double.parse(field.controller!.text.replaceAll(',', '.'));
      expect(shown, closeTo(22.0462262185, 1e-9));
      await tester.tap(find.byKey(const ValueKey('confirm-custom-lb')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final live =
          await repo.readActiveStrengthSession() as ActiveStrengthSession;
      expect(live.recorded.single.load?.unit, ExerciseLoadUnit.lb);
      expect(live.recorded.single.loadKg, closeTo(20, 1e-9));
    },
  );

  testWidgets(
    'mixed kg and lb rows keep each original unit on reopen and record',
    (tester) async {
      final definition = _customDefinition(
        repetitionBasis: ExerciseRepetitionBasis.total,
      );
      final pounds = 10 / kKilogramsPerPound;
      OriginalLoadInput original(double value, ExerciseLoadUnit unit) =>
          OriginalLoadInput(
            value: value,
            unit: unit,
            basis: ExerciseLoadBasis.perDevice,
            deviceCount: 2,
            repetitionBasis: ExerciseRepetitionBasis.total,
          );
      await mount(
        tester,
        template: _template(
          name: 'Kurztraining',
          exercises: [
            PlannedExercise(
              id: 'ex-custom',
              exerciseKey: definition.id,
              name: definition.label,
              definition: definition,
              sets: [
                PlannedSet(
                  id: 'mixed-kg',
                  reps: 8,
                  loadKg: 20,
                  load: original(10, ExerciseLoadUnit.kg),
                ),
                PlannedSet(
                  id: 'mixed-lb',
                  reps: 8,
                  loadKg: 20,
                  load: original(pounds, ExerciseLoadUnit.lb),
                ),
              ],
            ),
          ],
        ),
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller?.text,
        '10',
      );
      expect(find.text('kg je Hantel'), findsNothing);
      expect(find.text('je Hantel'), findsOneWidget);
      expect(find.text('LAST'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('confirm-mixed-kg')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('10 kg'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller?.text,
        startsWith('22,046'),
      );
      await tester.tap(find.byKey(const ValueKey('confirm-mixed-lb')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final live =
          await repo.readActiveStrengthSession() as ActiveStrengthSession;
      expect(live.recorded.map((s) => s.load?.unit), [
        ExerciseLoadUnit.kg,
        ExerciseLoadUnit.lb,
      ]);
      expect(
        live.recorded.map((s) => s.loadKg),
        everyElement(closeTo(20, 1e-9)),
      );
    },
  );

  testWidgets(
    'future load metadata is disabled and recorded without precision loss',
    (tester) async {
      final definition = _customDefinition();
      final future = OriginalLoadInput.fromJson({
        'value': 10,
        'unit': 'futureUnit',
        'basis': 'futureBasis',
        'repetitionBasis': 'futureReps',
        'side': 'futureSide',
      });
      await mount(
        tester,
        template: _template(
          name: 'Kurztraining',
          exercises: [
            PlannedExercise(
              id: 'ex-custom',
              exerciseKey: definition.id,
              name: definition.label,
              definition: definition,
              sets: [
                PlannedSet(
                  id: 'future',
                  reps: 8,
                  loadKg: 20.123456789,
                  load: future,
                ),
              ],
            ),
          ],
        ),
      );
      expect(find.text('kg je Hantel · Wdh. je Seite'), findsNothing);
      final loadField = tester.widget<TextField>(find.byType(TextField).first);
      expect(loadField.enabled, isFalse);
      await tester.tap(find.byKey(const ValueKey('confirm-future')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final live =
          await repo.readActiveStrengthSession() as ActiveStrengthSession;
      expect(live.recorded.single.loadKg, 20.123456789);
      expect(live.recorded.single.load?.toJson(), future.toJson());
    },
  );

  testWidgets(
    'mixed live rows drop the common caption and keep legacy totals honest',
    (tester) async {
      final definition = _customDefinition();
      final typed = OriginalLoadInput(
        value: 10,
        unit: ExerciseLoadUnit.kg,
        basis: ExerciseLoadBasis.perDevice,
        deviceCount: 2,
        repetitionBasis: ExerciseRepetitionBasis.perSide,
        side: ExerciseSetSide.both,
      );
      final future = OriginalLoadInput.fromJson({
        'value': 17.25,
        'unit': 'stone',
        'basis': 'futureBasis',
      });
      await mount(
        tester,
        template: _template(
          name: 'Kurztraining',
          exercises: [
            PlannedExercise(
              id: 'ex-custom',
              exerciseKey: definition.id,
              name: definition.label,
              definition: definition,
              sets: [
                PlannedSet(id: 'typed', reps: 8, loadKg: 20, load: typed),
                const PlannedSet(id: 'legacy', reps: 8, loadKg: 20.123456789),
                PlannedSet(
                  id: 'future',
                  reps: 8,
                  loadKg: 20.123456789,
                  load: future,
                ),
              ],
            ),
          ],
        ),
      );
      expect(find.text('kg je Hantel · Wdh. je Seite'), findsNothing);
      expect(find.text('je Hantel · Wdh. je Seite'), findsOneWidget);
      expect(find.text('Gesamtgewicht'), findsOneWidget);
      expect(find.text('—'), findsWidgets);
      expect(find.text('Beide Seiten'), findsOneWidget);
      expect(find.byKey(const ValueKey('side-legacy')), findsNothing);
      expect(find.text('KG'), findsNothing);
      expect(find.text('LAST'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller?.text,
        '10',
      );

      await tester.tap(find.byTooltip('Übungsmenü'));
      await tester.pumpAndSettle();
      expect(find.text('Einheit'), findsNothing);
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('confirm-typed')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const ValueKey('confirm-legacy')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const ValueKey('confirm-future')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final live =
          await repo.readActiveStrengthSession() as ActiveStrengthSession;
      expect(live.recorded.map((s) => s.loadKg), [
        20,
        20.123456789,
        20.123456789,
      ]);
      expect(live.recorded[1].load, isNull);
      expect(live.recorded[2].load?.toJson(), future.toJson());
    },
  );

  testWidgets(
    'persisted blank stays untyped while an original-backed blank stays typed',
    (tester) async {
      final definition = _customDefinition();
      await mount(
        tester,
        template: _template(
          name: 'Kurztraining',
          exercises: [
            PlannedExercise(
              id: 'ex-custom',
              exerciseKey: definition.id,
              name: definition.label,
              definition: definition,
              sets: [const PlannedSet(id: 'legacy-blank', reps: 8)],
            ),
          ],
        ),
      );

      expect(find.text('kg je Hantel · Wdh. je Seite'), findsNothing);
      expect(find.text('Beide Seiten'), findsNothing);
      expect(find.text('KG'), findsNothing);
      expect(find.text('LAST'), findsOneWidget);
      expect(find.byKey(const ValueKey('side-legacy-blank')), findsNothing);
      await tester.tap(find.byTooltip('Übungsmenü'));
      await tester.pumpAndSettle();
      expect(find.text('Einheit'), findsNothing);
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-legacy-blank')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      var live =
          await repo.readActiveStrengthSession() as ActiveStrengthSession;
      expect(live.recorded.single.load, isNull);
      expect(live.recorded.single.loadKg, isNull);

      repo = _repo();
      repo.strengthNow = () => now;
      final typedBlank = OriginalLoadInput(
        unit: ExerciseLoadUnit.kg,
        basis: ExerciseLoadBasis.perDevice,
        deviceCount: 2,
        repetitionBasis: ExerciseRepetitionBasis.perSide,
        side: ExerciseSetSide.both,
      );
      await mount(
        tester,
        template: _template(
          name: 'Kurztraining',
          exercises: [
            PlannedExercise(
              id: 'ex-custom',
              exerciseKey: definition.id,
              name: definition.label,
              definition: definition,
              sets: [PlannedSet(id: 'typed-blank', reps: 8, load: typedBlank)],
            ),
          ],
        ),
      );

      expect(find.text('kg je Hantel · Wdh. je Seite'), findsOneWidget);
      expect(find.text('Beide Seiten'), findsOneWidget);
      expect(find.byKey(const ValueKey('side-typed-blank')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm-typed-blank')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      live = await repo.readActiveStrengthSession() as ActiveStrengthSession;
      expect(live.recorded.single.load?.toJson(), typedBlank.toJson());
      expect(live.recorded.single.loadKg, isNull);
    },
  );

  testWidgets(
    'untouched historic total stays precise; an edit stores the typed value',
    (tester) async {
      final definition = _customDefinition();
      await mount(
        tester,
        template: _template(
          name: 'Kurztraining',
          exercises: [
            PlannedExercise(
              id: 'ex-custom',
              exerciseKey: definition.id,
              name: definition.label,
              definition: definition,
              sets: [
                const PlannedSet(id: 'precise', reps: 8, loadKg: 20.123456789),
              ],
            ),
          ],
        ),
      );
      expect(find.text('kg je Hantel · Wdh. je Seite'), findsNothing);
      expect(find.text('Beide Seiten'), findsNothing);
      expect(find.text('KG'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller?.text, '20,123456789');
      await tester.tap(find.byTooltip('Übungsmenü'));
      await tester.pumpAndSettle();
      expect(find.text('Einheit'), findsNothing);
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('confirm-precise')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      var live =
          await repo.readActiveStrengthSession() as ActiveStrengthSession;
      expect(live.recorded.single.loadKg, 20.123456789);
      expect(live.recorded.single.load, isNull);

      repo = _repo();
      repo.strengthNow = () => now;
      await mount(
        tester,
        template: _template(
          name: 'Kurztraining',
          exercises: [
            PlannedExercise(
              id: 'ex-custom',
              exerciseKey: definition.id,
              name: definition.label,
              definition: definition,
              sets: [
                const PlannedSet(id: 'edited', reps: 8, loadKg: 20.123456789),
              ],
            ),
          ],
        ),
      );
      await tester.enterText(find.byType(TextField).first, '21');
      await tester.tap(find.byKey(const ValueKey('confirm-edited')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      live = await repo.readActiveStrengthSession() as ActiveStrengthSession;
      expect(live.recorded.single.loadKg, 21);
      expect(live.recorded.single.load, isNull);
    },
  );

  testWidgets('previous values come from recorded history, else em dash', (
    tester,
  ) async {
    now = DateTime(2026, 9, 15, 18, 32, 14);
    await repo.seedPaperLiveStrength(
      startedAt: DateTime(2026, 9, 15, 18),
      now: now,
    );
    await mount(tester, resume: true);
    expect(find.text('60 × 8'), findsWidgets);
    expect(find.text('60 × 7'), findsOneWidget);
    expect(find.text('62,5 × 8'), findsNothing);
    expect(find.text('—'), findsWidgets);
    expect(find.text('1:24'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
  });

  testWidgets(
    'timed, bodyweight and repeated exercise blocks keep own indexes',
    (tester) async {
      final template = _template(
        exercises: const [
          PlannedExercise(
            id: 'ex-bench-a',
            exerciseKey: 'bench_press',
            name: 'Bank A',
            sets: [PlannedSet(id: 'ba-1', reps: 5, loadKg: 50, restSec: 60)],
          ),
          PlannedExercise(
            id: 'ex-plank',
            exerciseKey: 'plank',
            name: 'Plank',
            sets: [PlannedSet(id: 'pl-1', seconds: 45, restSec: 30)],
          ),
          PlannedExercise(
            id: 'ex-pull',
            exerciseKey: 'pullup',
            name: 'Klimmzug',
            sets: [PlannedSet(id: 'pu-1', reps: 8, restSec: 60)],
          ),
          PlannedExercise(
            id: 'ex-bench-b',
            exerciseKey: 'bench_press',
            name: 'Bank B',
            sets: [PlannedSet(id: 'bb-1', reps: 8, loadKg: 40, restSec: 60)],
          ),
        ],
      );
      await mount(tester, template: template);
      expect(find.text('Bank A'), findsOneWidget);
      expect(find.text('Bank B'), findsOneWidget);
      expect(find.text('SEK'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm-ba-1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      var live =
          await repo.readActiveStrengthSession() as ActiveStrengthSession;
      expect(live.recorded.single.exerciseId, 'ex-bench-a');
      expect(live.recorded.single.setIndex, 1);
      await tester.tap(find.text('Weiter'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, '40');
      await tester.tap(find.byKey(const ValueKey('confirm-pl-1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      live = await repo.readActiveStrengthSession() as ActiveStrengthSession;
      expect(live.recorded.last.exerciseId, 'ex-plank');
      expect(live.recorded.last.seconds, 40);
      expect(live.recorded.last.reps, isNull);
      await tester.tap(find.text('Weiter'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirm-pu-1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      live = await repo.readActiveStrengthSession() as ActiveStrengthSession;
      expect(live.recorded.last.exerciseId, 'ex-pull');
      expect(live.recorded.last.loadKg, isNull);
      expect(live.recorded.last.reps, 8);
      await tester.tap(find.text('Weiter'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirm-bb-1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      live = await repo.readActiveStrengthSession() as ActiveStrengthSession;
      expect(live.recorded.last.exerciseId, 'ex-bench-b');
      expect(live.recorded.last.setIndex, 1);
    },
  );

  testWidgets('failed record keeps input and completed sets; retry is exact', (
    tester,
  ) async {
    await mount(tester);
    await tester.enterText(find.byType(TextField).first, '42,5');
    repo.failStrengthWrites = true;
    await tester.tap(find.byKey(const ValueKey('confirm-a-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      '42,5',
    );
    var live = await repo.readActiveStrengthSession() as ActiveStrengthSession;
    expect(live.recorded, isEmpty);
    repo.failStrengthWrites = false;
    await tester.tap(find.text('Erneut'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    live = await repo.readActiveStrengthSession() as ActiveStrengthSession;
    expect(live.recorded, hasLength(1));
    expect(live.recorded.single.loadKg, 42.5);
    repo.failStrengthWrites = true;
    await tester.tap(find.byKey(const ValueKey('confirm-a-2')));
    await tester.pump();
    live = await repo.readActiveStrengthSession() as ActiveStrengthSession;
    expect(live.recorded, hasLength(1));
  });

  testWidgets('skip, add, rest and finish failures leave durable work', (
    tester,
  ) async {
    await mount(tester);
    repo.failStrengthWrites = true;
    await tester.tap(find.byTooltip('Übungsmenü'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Satz 1 überspringen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    var live = await repo.readActiveStrengthSession() as ActiveStrengthSession;
    expect(live.skippedPlannedSetIds, isEmpty);
    repo.failStrengthWrites = false;
    await tester.tap(find.text('Erneut'));
    await tester.pump();
    live = await repo.readActiveStrengthSession() as ActiveStrengthSession;
    expect(live.skippedPlannedSetIds, contains('a-1'));
    expect(find.text('Übersprungen'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('confirm-a-2')));
    await tester.pump();
    expect(find.text('Pause'), findsOneWidget);
    repo.failStrengthWrites = true;
    await tester.tap(find.text('+30 s'));
    await tester.pump();
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    live = await repo.readActiveStrengthSession() as ActiveStrengthSession;
    final restBefore = live.restEndsAt;
    repo.failStrengthWrites = false;
    await tester.tap(find.text('Erneut'));
    await tester.pump();
    live = await repo.readActiveStrengthSession() as ActiveStrengthSession;
    expect(
      live.restEndsAt!.difference(restBefore!),
      const Duration(seconds: 30),
    );

    repo.failStrengthWrites = true;
    await tester.tap(find.text('Weiter'));
    await tester.pump();
    live = await repo.readActiveStrengthSession() as ActiveStrengthSession;
    expect(live.restEndsAt, restBefore.add(const Duration(seconds: 30)));
    repo.failStrengthWrites = false;
    await tester.tap(find.text('Erneut'));
    await tester.pump();
    live = await repo.readActiveStrengthSession() as ActiveStrengthSession;
    expect(live.restEndsAt, isNull);
    expect(find.text('Pause'), findsNothing);

    repo.failStrengthWrites = true;
    await tester.tap(find.byTooltip('Satz hinzufügen').first);
    await tester.pump();
    live = await repo.readActiveStrengthSession() as ActiveStrengthSession;
    expect(live.added, isEmpty);
    repo.failStrengthWrites = false;
    await tester.tap(find.text('Erneut'));
    await tester.pump();
    live = await repo.readActiveStrengthSession() as ActiveStrengthSession;
    expect(live.added.single.sets.single.id, 'ex-a-extra-1');
    expect(
      live.recorded.where((s) => s.plannedSetId == 'ex-a-extra-1'),
      isEmpty,
    );

    repo.failStrengthWrites = true;
    await tester.tap(find.text('Fertig'));
    await tester.pump();
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(
      await repo.readActiveStrengthSession(),
      isA<ActiveStrengthSession>(),
    );
    repo.failStrengthWrites = false;
    await tester.tap(find.text('Erneut'));
    await tester.pump();
    expect(await repo.readActiveStrengthSession(), isA<NoActiveStrength>());
  });

  testWidgets('successful finish pops the live route', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(
          Brightness.light,
        ).copyWith(platform: TargetPlatform.iOS),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => OpenBandStrengthLive(
                    repository: repo,
                    template: _template(),
                    now: () => now,
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Bankdrücken'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('finish-live')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('open'), findsOneWidget);
    expect(find.text('Bankdrücken'), findsNothing);
    expect(await repo.readActiveStrengthSession(), isA<NoActiveStrength>());
  });

  testWidgets('+30 then snapshot read failure retries read only', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('confirm-a-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    var live = await repo.readActiveStrengthSession() as ActiveStrengthSession;
    final restBefore = live.restEndsAt!;
    expect(find.text('1:30'), findsOneWidget);
    final writes = repo.strengthWriteCount;
    repo.failStrengthReadRemaining = 1;
    await tester.tap(find.text('+30 s'));
    await tester.pump();
    expect(find.text('Speichern fehlgeschlagen'), findsNothing);
    expect(find.text('Einheit konnte nicht gelesen werden.'), findsOneWidget);
    expect(find.text('Erneut'), findsOneWidget);
    expect(find.text('1:30'), findsOneWidget);
    live = await repo.readActiveStrengthSession() as ActiveStrengthSession;
    expect(live.restEndsAt, restBefore.add(const Duration(seconds: 30)));
    expect(repo.strengthWriteCount, writes + 1);
    await tester.tap(find.text('Erneut'));
    await tester.pump();
    expect(find.text('Einheit konnte nicht gelesen werden.'), findsNothing);
    expect(find.text('2:00'), findsOneWidget);
    live = await repo.readActiveStrengthSession() as ActiveStrengthSession;
    expect(live.restEndsAt, restBefore.add(const Duration(seconds: 30)));
    expect(repo.strengthWriteCount, writes + 1);
  });

  testWidgets('failed start retry starts once nothing is active', (
    tester,
  ) async {
    repo.failStrengthStart = true;
    await mount(tester);
    expect(find.text('Einheit konnte nicht gestartet werden.'), findsOneWidget);
    expect(find.text('Erneut'), findsOneWidget);
    expect(repo.strengthStartCount, 1);
    expect(await repo.readActiveStrengthSession(), isA<NoActiveStrength>());
    repo.failStrengthStart = false;
    await tester.tap(find.text('Erneut'));
    await tester.pump();
    expect(find.text('Einheit konnte nicht gestartet werden.'), findsNothing);
    expect(find.text('Bankdrücken'), findsOneWidget);
    expect(repo.strengthStartCount, 2);
    expect(
      await repo.readActiveStrengthSession(),
      isA<ActiveStrengthSession>(),
    );
  });

  testWidgets('start that commits then fails binds without a duplicate', (
    tester,
  ) async {
    repo.failStrengthStartAfterCommit = true;
    await mount(tester);
    expect(find.text('Einheit konnte nicht gestartet werden.'), findsOneWidget);
    expect(find.text('Erneut'), findsOneWidget);
    expect(repo.strengthStartCount, 1);
    expect(
      await repo.readActiveStrengthSession(),
      isA<ActiveStrengthSession>(),
    );
    await tester.tap(find.text('Erneut'));
    await tester.pump();
    expect(find.text('Einheit konnte nicht gestartet werden.'), findsNothing);
    expect(find.text('Bankdrücken'), findsOneWidget);
    expect(repo.strengthStartCount, 1);
    expect(
      await repo.readActiveStrengthSession(),
      isA<ActiveStrengthSession>(),
    );
  });

  Future<void> mountResume(
    WidgetTester tester, {
    required AppState app,
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('de')],
          theme:
              theme ??
              openBandTheme(
                Brightness.light,
              ).copyWith(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => resumeLiveSession(context, repository: repo),
                child: const Text('resume'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('failed snapshot retry opens Alpin live, not a start', (
    tester,
  ) async {
    await repo.startStrengthSession(_template());
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    app.activeWorkout = LiveWorkoutState(
      startTime: DateTime(2026, 9, 15, 18),
      targetKcal: 300,
      type: 'weight_training',
      workoutId: 'w-strength',
    );
    repo.failStrengthReadRemaining = 1;
    await mountResume(tester, app: app);
    await tester.tap(find.text('resume'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(OpenBandStrengthLive), findsNothing);
    expect(find.text('Einheit nicht geladen'), findsOneWidget);
    expect(find.text('Aktivität konnte nicht gestartet werden.'), findsNothing);
    expect(repo.strengthStartCount, 1);
    tester.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(OpenBandStrengthLive), findsOneWidget);
    expect(find.text('Bankdrücken'), findsOneWidget);
    expect(repo.strengthStartCount, 1);
    expect(
      await repo.readActiveStrengthSession(),
      isA<ActiveStrengthSession>(),
    );
  });

  testWidgets('failed snapshot retry opens legacy live, not Alpin', (
    tester,
  ) async {
    repo.legacyActiveStrength = true;
    repo.failStrengthReadRemaining = 1;
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    app.activeWorkout = LiveWorkoutState(
      startTime: DateTime(2026, 9, 15, 18),
      targetKcal: 300,
      type: 'weight_training',
      workoutId: 'legacy-wt',
    );
    await mountResume(tester, app: app, theme: buildTheme(Brightness.light));
    await tester.tap(find.text('resume'));
    await tester.pump();
    expect(find.byType(OpenBandStrengthLive), findsNothing);
    expect(find.text('Einheit nicht geladen'), findsOneWidget);
    expect(repo.strengthStartCount, 0);
    tester.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(OpenBandStrengthLive), findsNothing);
    expect(find.byType(LiveStrength), findsOneWidget);
    expect(repo.strengthStartCount, 0);
    expect(await repo.readActiveStrengthSession(), isA<LegacyActiveStrength>());
  });

  testWidgets('bar resume on a run never reads the strength snapshot', (
    tester,
  ) async {
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    app.activeWorkout = LiveWorkoutState(
      startTime: DateTime(2026, 9, 15, 18),
      targetKcal: 300,
      type: 'running',
      workoutId: 'w-run',
    );
    repo.failStrengthReadRemaining = 1;
    await mountResume(tester, app: app, theme: buildTheme(Brightness.light));
    await tester.tap(find.text('resume'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(find.byType(OpenBandStrengthLive), findsNothing);
    expect(find.text('Einheit nicht geladen'), findsNothing);
    expect(find.byType(LiveMeasured), findsOneWidget);
    expect(repo.failStrengthReadRemaining, 1);
    expect(repo.strengthStartCount, 0);
  });

  testWidgets('activity start failure shows retryable feedback', (
    tester,
  ) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showRetryableActivityStart(context, () => retried = true),
              child: const Text('fail'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('fail'));
    await tester.pump();
    expect(
      find.text('Aktivität konnte nicht gestartet werden.'),
      findsOneWidget,
    );
    tester.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed();
    await tester.pump();
    expect(retried, isTrue);
  });

  testWidgets('double tap and finish-during-record do not overlap writes', (
    tester,
  ) async {
    await mount(tester);
    await tester.enterText(find.byType(TextField).first, '42,5');
    final hold = Completer<void>();
    repo.beforeStrengthWrite = () => hold.future;
    await tester.tap(find.byKey(const ValueKey('confirm-a-1')));
    await tester.pump();
    expect(repo.strengthWriteCount, 1);
    await tester.tap(find.byKey(const ValueKey('confirm-a-1')));
    await tester.pump();
    expect(repo.strengthWriteCount, 1);
    await tester.tap(find.byKey(const ValueKey('finish-live')));
    await tester.pump();
    expect(
      await repo.readActiveStrengthSession(),
      isA<ActiveStrengthSession>(),
    );
    hold.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    var live = await repo.readActiveStrengthSession() as ActiveStrengthSession;
    expect(live.recorded, hasLength(1));
    expect(repo.strengthWriteCount, 1);

    final restHold = Completer<void>();
    repo.beforeStrengthWrite = () => restHold.future;
    final restBefore = live.restEndsAt!;
    await tester.tap(find.text('+30 s'));
    await tester.pump();
    expect(repo.strengthWriteCount, 2);
    await tester.tap(find.text('+30 s'));
    await tester.pump();
    expect(repo.strengthWriteCount, 2);
    restHold.complete();
    await tester.pump();
    live = await repo.readActiveStrengthSession() as ActiveStrengthSession;
    expect(
      live.restEndsAt!.difference(restBefore),
      const Duration(seconds: 30),
    );

    final addHold = Completer<void>();
    repo.beforeStrengthWrite = () => addHold.future;
    await tester.tap(find.byTooltip('Satz hinzufügen').first);
    await tester.pump();
    expect(repo.strengthWriteCount, 3);
    await tester.tap(find.byTooltip('Satz hinzufügen').first);
    await tester.pump();
    expect(repo.strengthWriteCount, 3);
    addHold.complete();
    await tester.pump();
    live = await repo.readActiveStrengthSession() as ActiveStrengthSession;
    expect(live.added, hasLength(1));
    expect(live.added.single.sets, hasLength(1));
  });

  testWidgets('custom load live Paper states', (tester) async {
    final definition = _customDefinition();
    OriginalLoadInput original() => OriginalLoadInput(
      value: 10,
      unit: ExerciseLoadUnit.kg,
      basis: ExerciseLoadBasis.perDevice,
      deviceCount: 2,
      repetitionBasis: ExerciseRepetitionBasis.perSide,
      side: ExerciseSetSide.both,
    );
    final template = _template(
      name: 'Kurztraining',
      exercises: [
        PlannedExercise(
          id: 'ex-custom',
          exerciseKey: definition.id,
          name: 'Kurzhantel-Curl',
          definition: definition,
          sets: [
            for (var i = 1; i <= 3; i++)
              PlannedSet(
                id: 'custom-$i',
                reps: 8,
                loadKg: 20,
                load: original(),
              ),
          ],
        ),
      ],
    );
    for (final state in [
      ('light', Brightness.light, 393.0, 1.0, 1.0),
      ('dark', Brightness.dark, 393.0, 1.0, 1.0),
      ('375-2x', Brightness.light, 375.0, 2.0, 2.0),
    ]) {
      repo = _repo();
      repo.strengthNow = () => now;
      final sessionId = await repo.startStrengthSession(template);
      await repo.recordSet(
        sessionId,
        RecordedSet(
          exerciseKey: definition.id,
          setIndex: 1,
          reps: 8,
          loadKg: 20,
          at: now,
          plannedSetId: 'custom-1',
          exerciseId: 'ex-custom',
          load: original(),
          definition: definition,
        ),
      );
      await mount(
        tester,
        resume: true,
        brightness: state.$2,
        width: state.$3,
        scale: state.$4,
        dpr: state.$5,
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('openband_goldens/custom-load-live-${state.$1}.png'),
      );
    }
  });

  testWidgets('mixed-unit active value and unit stay legible in Paper states', (
    tester,
  ) async {
    final definition = _customDefinition(
      repetitionBasis: ExerciseRepetitionBasis.total,
    );
    OriginalLoadInput original(double value, ExerciseLoadUnit unit) =>
        OriginalLoadInput(
          value: value,
          unit: unit,
          basis: ExerciseLoadBasis.perDevice,
          deviceCount: 2,
          repetitionBasis: ExerciseRepetitionBasis.total,
        );
    final kg = original(10, ExerciseLoadUnit.kg);
    final lb = original(22, ExerciseLoadUnit.lb);
    final template = _template(
      name: 'Kurztraining',
      exercises: [
        PlannedExercise(
          id: 'ex-custom',
          exerciseKey: definition.id,
          name: 'Kurzhantel-Curl',
          definition: definition,
          sets: [
            PlannedSet(id: 'mixed-kg', reps: 8, loadKg: 20, load: kg),
            PlannedSet(
              id: 'mixed-lb',
              reps: 8,
              loadKg: 44 * kKilogramsPerPound,
              load: lb,
            ),
          ],
        ),
      ],
    );
    for (final state in [
      ('light', Brightness.light),
      ('dark', Brightness.dark),
    ]) {
      repo = _repo();
      repo.strengthNow = () => now;
      final sessionId = await repo.startStrengthSession(template);
      await repo.recordSet(
        sessionId,
        RecordedSet(
          exerciseKey: definition.id,
          setIndex: 1,
          reps: 8,
          loadKg: 20,
          at: now,
          plannedSetId: 'mixed-kg',
          exerciseId: 'ex-custom',
          load: kg,
          definition: definition,
        ),
      );
      await mount(
        tester,
        resume: true,
        brightness: state.$2,
        width: 393,
        dpr: 1,
      );
      final loadField = tester.widget<TextField>(find.byType(TextField).first);
      expect(loadField.controller?.text, '22');
      expect(loadField.decoration?.suffixText, ' lb');
      expect(loadField.decoration?.suffixStyle?.fontSize, 16);
      expect(loadField.decoration?.suffixStyle?.fontWeight, FontWeight.w700);
      expect(loadField.decoration?.contentPadding, const EdgeInsets.all(8));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'openband_goldens/custom-load-mixed-units-${state.$1}.png',
        ),
      );
    }
  });

  testWidgets('paper live light is a clean snapshot at 375@2x', (tester) async {
    now = DateTime(2026, 9, 15, 18, 32, 14);
    await mountPaper(tester);
    expect(find.text('32:14'), findsOneWidget);
    expect(find.text('1:24'), findsOneWidget);
    expect(find.text('Übersprungen'), findsNothing);
    expect(find.text('Speichern fehlgeschlagen'), findsNothing);
    expect(find.text('60 × 8'), findsWidgets);
    expect(find.text('60 × 7'), findsOneWidget);
    expect(find.text('62,5 × 8'), findsNothing);
    expect(find.text('—'), findsWidgets);
    final elapsed = tester.widget<FractionallySizedBox>(
      find.byKey(const ValueKey('rest-elapsed')),
    );
    expect(elapsed.widthFactor, closeTo(0.3, 1e-9));
    expect(elapsed.heightFactor, 1);
    expect(
      tester.getSize(find.byKey(const ValueKey('rest-elapsed'))).height,
      4,
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/strength-live-light.png'),
    );
  });

  testWidgets('paper menu captures the overlay', (tester) async {
    now = DateTime(2026, 9, 15, 18, 32, 14);
    await mountPaper(tester);
    await tester.tap(find.byTooltip('Übungsmenü').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Satz 3 überspringen'), findsOneWidget);
    expect(find.text('Bankdrücken'), findsWidgets);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/strength-menu.png'),
    );
  });

  testWidgets('paper skipped is a fresh session', (tester) async {
    now = DateTime(2026, 9, 15, 18, 32, 14);
    await mountPaper(tester);
    await tester.tap(find.byTooltip('Übungsmenü').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Satz 3 überspringen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Übersprungen'), findsOneWidget);
    expect(find.text('Satz 3 überspringen'), findsNothing);
    expect(find.text('60 × 7'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/strength-skipped.png'),
    );
  });

  Future<void> settleLiveTransition(WidgetTester tester) =>
      tester.pumpAndSettle(
        const Duration(milliseconds: 16),
        EnginePhase.sendSemanticsUpdate,
        const Duration(milliseconds: 800),
      );

  testWidgets(
    'skip sheet is gone after an ordinary transition on Bankdrücken',
    (tester) async {
      now = DateTime(2026, 9, 15, 18, 32, 14);
      await mountPaper(tester);
      final bank = find.ancestor(
        of: find.text('Bankdrücken'),
        matching: find.byType(OBExerciseBlock),
      );
      await tester.tap(
        find.descendant(of: bank, matching: find.byTooltip('Übungsmenü')),
      );
      await settleLiveTransition(tester);
      await tester.tap(find.text('Satz 3 überspringen'));
      await settleLiveTransition(tester);
      expect(find.text('Satz 3 überspringen'), findsNothing);
      expect(
        find.descendant(of: bank, matching: find.text('Übersprungen')),
        findsOneWidget,
      );
    },
  );

  testWidgets('add ink is gone after bounded settle on Bankdrücken', (
    tester,
  ) async {
    now = DateTime(2026, 9, 15, 18, 32, 14);
    await mountPaper(tester);
    final bank = find.ancestor(
      of: find.text('Bankdrücken'),
      matching: find.byType(OBExerciseBlock),
    );
    await tester.tap(
      find.descendant(of: bank, matching: find.byTooltip('Satz hinzufügen')),
    );
    await settleLiveTransition(tester);
    expect(find.descendant(of: bank, matching: find.text('5')), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('paper add is a fresh session', (tester) async {
    now = DateTime(2026, 9, 15, 18, 32, 14);
    await mountPaper(tester);
    await tester.tap(find.byTooltip('Satz hinzufügen').first);
    await tester.pump();
    expect(find.text('5'), findsOneWidget);
    expect(find.text('Übersprungen'), findsNothing);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/strength-add.png'),
    );
  });

  testWidgets(
    'paper add then Bankdrücken set 3 fail-retry writes that plannedSetId',
    (tester) async {
      now = DateTime(2026, 9, 15, 18, 32, 14);
      await mountPaper(tester);
      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text('Bankdrücken'),
            matching: find.byType(OBExerciseBlock),
          ),
          matching: find.byTooltip('Satz hinzufügen'),
        ),
      );
      await tester.pump();
      expect(find.text('5'), findsOneWidget);
      await mountPaper(tester);
      expect(find.byTooltip('Satz 3 bestätigen'), findsNWidgets(2));
      final benchConfirm = find.descendant(
        of: find.ancestor(
          of: find.text('Bankdrücken'),
          matching: find.byType(OBExerciseBlock),
        ),
        matching: find.byTooltip('Satz 3 bestätigen'),
      );
      expect(benchConfirm, findsOneWidget);
      repo.failStrengthWrites = true;
      await tester.tap(benchConfirm);
      await tester.pump();
      expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
      var live =
          await repo.readActiveStrengthSession() as ActiveStrengthSession;
      expect(
        live.recorded.map((s) => s.plannedSetId),
        isNot(contains('paper-bp-3')),
      );
      repo.failStrengthWrites = false;
      await tester.tap(find.text('Erneut'));
      await tester.pump();
      live = await repo.readActiveStrengthSession() as ActiveStrengthSession;
      expect(live.recorded.last.plannedSetId, 'paper-bp-3');
      expect(live.recorded.last.exerciseId, 'ex-paper-bench');
      expect(
        live.recorded.where((s) => s.plannedSetId == 'paper-sq-3'),
        isEmpty,
      );
      expect(find.text('Speichern fehlgeschlagen'), findsNothing);
    },
  );

  testWidgets('paper error is a fresh session', (tester) async {
    now = DateTime(2026, 9, 15, 18, 32, 14);
    await mountPaper(tester);
    repo.failStrengthWrites = true;
    await tester.tap(find.byKey(const ValueKey('confirm-paper-bp-3')));
    await tester.pump();
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(find.text('Übersprungen'), findsNothing);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/strength-error.png'),
    );
  });

  testWidgets('paper dark is an independent dark mount', (tester) async {
    now = DateTime(2026, 9, 15, 18, 32, 14);
    await mountPaper(tester, brightness: Brightness.dark);
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.dark,
    );
    expect(find.text('Übersprungen'), findsNothing);
    expect(find.text('Speichern fehlgeschlagen'), findsNothing);
    expect(find.text('1:24'), findsOneWidget);
    expect(find.text('62,5 × 8'), findsNothing);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/strength-live-dark.png'),
    );
  });

  testWidgets('375-wide TextScaler 2 keeps rest and keyboard row visible', (
    tester,
  ) async {
    now = DateTime(2026, 9, 15, 18, 32, 14);
    await mountPaper(tester, scale: 2);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('+30 s').hitTestable(), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
    expect(find.text('SATZ'), findsNothing);
    expect(find.text('ZULETZT'), findsNothing);
    expect(find.text('KG'), findsNothing);
    expect(find.text('WDH'), findsNothing);
    expect(find.text('Satz 3'), findsWidgets);
    expect(find.text('Zuletzt 60 × 7'), findsOneWidget);
    expect(find.text('kg'), findsWidgets);
    expect(find.text('Wdh.'), findsWidgets);
    expect(find.byType(FittedBox), findsNothing);
    expect(
      tester.getSize(find.text('Satz 3').first).height,
      greaterThanOrEqualTo(30),
    );
    expect(
      tester.getSize(find.text('Zuletzt 60 × 7')).height,
      greaterThanOrEqualTo(26),
    );
    final restH = tester.getSize(find.byType(OBRestTimer)).height;
    final list = tester.widget<ListView>(find.byType(ListView));
    expect((list.padding! as EdgeInsets).bottom, greaterThanOrEqualTo(restH));
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/strength-live-2x.png'),
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    final active = find.byType(TextField).first;
    await tester.ensureVisible(active);
    await tester.pump();
    expect(active.hitTestable(), findsOneWidget);
    expect(find.text('+30 s').hitTestable(), findsOneWidget);
    expect(find.text('Weiter').hitTestable(), findsOneWidget);
  });

  testWidgets('large text skipped row keeps Satz, Zuletzt and status', (
    tester,
  ) async {
    now = DateTime(2026, 9, 15, 18, 32, 14);
    await mountPaper(tester, scale: 2);
    await tester.tap(find.byTooltip('Übungsmenü').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Satz 3 überspringen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Übersprungen'), findsOneWidget);
    expect(find.text('Satz 3'), findsWidgets);
    expect(find.text('Zuletzt 60 × 7'), findsOneWidget);
    expect(find.text('SATZ'), findsNothing);
    expect(find.byType(FittedBox), findsNothing);
  });

  testWidgets(
    'empty timed plan starts live in time mode without invented duration',
    (tester) async {
      await mount(
        tester,
        template: _template(
          exercises: const [
            PlannedExercise(
              id: 'ex-plank',
              exerciseKey: 'plank',
              name: 'Plank',
              sets: [PlannedSet(id: 'pl-1', mode: PlannedSetMode.time)],
            ),
          ],
        ),
      );
      expect(find.text('SEK'), findsOneWidget);
      expect(find.text('WDH'), findsNothing);
      expect(find.text('KG'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller?.text,
        '',
      );
      await tester.tap(find.byKey(const ValueKey('confirm-pl-1')));
      await tester.pump();
      expect(find.text('Sekunden fehlen.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '40');
      await tester.tap(find.byKey(const ValueKey('confirm-pl-1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final live =
          await repo.readActiveStrengthSession() as ActiveStrengthSession;
      expect(live.recorded.single.seconds, 40);
      expect(live.recorded.single.reps, isNull);
    },
  );

  testWidgets('large text timed row uses Sek, not kg or reps', (tester) async {
    await mount(
      tester,
      scale: 2,
      template: _template(
        exercises: const [
          PlannedExercise(
            id: 'ex-plank',
            exerciseKey: 'plank',
            name: 'Plank',
            sets: [PlannedSet(id: 'pl-1', seconds: 45, restSec: 30)],
          ),
        ],
      ),
    );
    expect(find.text('Satz 1'), findsOneWidget);
    expect(find.textContaining('Zuletzt'), findsOneWidget);
    expect(find.text('Sek'), findsOneWidget);
    expect(find.text('kg'), findsNothing);
    expect(find.text('Wdh.'), findsNothing);
    expect(find.text('SATZ'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('2x keyboard reaches lower squat row above rest overlay', (
    tester,
  ) async {
    now = DateTime(2026, 9, 15, 18, 32, 14);
    await mountPaper(tester, scale: 2);
    await tester.tap(find.byTooltip('Übungsmenü').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Satz 3 überspringen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('Übungsmenü').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Satz 4 überspringen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('confirm-paper-sq-1')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    final squat = find.byKey(const ValueKey('confirm-paper-sq-1'));
    await tester.ensureVisible(squat);
    await tester.pump();
    expect(squat.hitTestable(), findsOneWidget);
    expect(find.byType(TextField).hitTestable(), findsWidgets);
    expect(find.text('+30 s').hitTestable(), findsOneWidget);
    expect(find.text('Weiter').hitTestable(), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('confirm-paper-sq-4')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    final last = find.byKey(const ValueKey('confirm-paper-sq-4'));
    await tester.ensureVisible(last);
    await tester.pump();
    expect(last.hitTestable(), findsOneWidget);
    expect(find.text('+30 s').hitTestable(), findsOneWidget);
  });

  void insetHomeIndicator(WidgetTester tester) {
    final dpr = tester.view.devicePixelRatio;
    tester.view.padding = FakeViewPadding(bottom: 34 * dpr);
    tester.view.viewPadding = FakeViewPadding(bottom: 34 * dpr);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
  }

  void expectRestMasksSafeArea(WidgetTester tester, {required double inset}) {
    final rest = tester.getRect(find.byType(OBRestTimer));
    final scaffold = tester.getRect(find.byType(Scaffold));
    final mask = tester.getRect(find.byKey(const ValueKey('rest-safe-mask')));
    expect(rest.bottom, closeTo(scaffold.bottom - inset, 0.5));
    expect(mask.top, closeTo(rest.bottom, 0.5));
    expect(mask.bottom, closeTo(scaffold.bottom, 0.5));
    expect(mask.left, closeTo(scaffold.left, 0.5));
    expect(mask.width, closeTo(scaffold.width, 0.5));
    expect(mask.height, closeTo(inset, 0.5));
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(
      (list.padding! as EdgeInsets).bottom,
      greaterThanOrEqualTo(rest.height + inset),
    );
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'rest canvas masks ${scale}x list through 34px home-indicator inset',
      (tester) async {
        now = DateTime(2026, 9, 15, 18, 32, 14);
        await mountPaper(tester, scale: scale);
        insetHomeIndicator(tester);
        await tester.pump();
        expectRestMasksSafeArea(tester, inset: 34);
        expect(find.text('+30 s').hitTestable(), findsOneWidget);
        if (scale == 2) {
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          addTearDown(tester.view.resetViewInsets);
          await tester.pump();
          expect(find.text('+30 s').hitTestable(), findsOneWidget);
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('confirm-paper-sq-1')),
            240,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pump();
          expect(
            find.byKey(const ValueKey('confirm-paper-sq-1')).hitTestable(),
            findsOneWidget,
          );
        }
      },
    );
  }

  testWidgets('missing rest denominator omits the elapsed bar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: Scaffold(
          body: OBRestTimer(
            remaining: 84,
            total: null,
            onAdd: () {},
            onSkip: () {},
          ),
        ),
      ),
    );
    expect(find.text('1:24'), findsOneWidget);
    expect(find.byKey(const ValueKey('rest-elapsed')), findsNothing);
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: Scaffold(
          body: SizedBox(
            width: 343,
            child: OBRestTimer(
              remaining: 84,
              total: 120,
              onAdd: () {},
              onSkip: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final bar = tester.widget<FractionallySizedBox>(
      find.byKey(const ValueKey('rest-elapsed')),
    );
    expect(bar.widthFactor, closeTo(0.3, 1e-9));
    expect(bar.heightFactor, 1);
    expect(
      tester.getSize(find.byKey(const ValueKey('rest-elapsed'))).height,
      4,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('rest-elapsed'))).width,
      closeTo(102.9, 0.6),
    );
  });
}
