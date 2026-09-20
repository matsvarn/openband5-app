import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/exercise_input.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/template_editor.dart';
import 'package:openstrap_edge/openband/theme.dart';

ExerciseDefinitionSnapshot _definition({
  ExerciseEquipmentCategory equipment = ExerciseEquipmentCategory.dumbbell,
  ExerciseLoadBasis basis = ExerciseLoadBasis.perDevice,
  int? count = 2,
  ExerciseRepetitionBasis? repetitions = ExerciseRepetitionBasis.perSide,
  Map<String, Object?> retained = const {},
}) => ExerciseDefinitionSnapshot(
  id: 'custom-curl',
  label: 'Kurzhantel-Curl',
  source: ExerciseDefinitionSource.stored,
  version: 1,
  mode: ExerciseCaptureMode.repetitions,
  equipment: equipment,
  loadBasis: basis,
  deviceCount: count,
  repetitionBasis: repetitions,
  retained: retained,
);

void main() {
  test(
    '10 kg per two devices normalizes to 20 without doubling repetitions',
    () {
      final load = captureOriginalLoad(
        definition: _definition(),
        existing: null,
        typed: true,
        value: 10,
        unit: ExerciseLoadUnit.kg,
        side: ExerciseSetSide.both,
      )!;

      expect(load.value, 10);
      expect(load.deviceCount, 2);
      expect(load.repetitionBasis, ExerciseRepetitionBasis.perSide);
      expect(load.side, ExerciseSetSide.both);
      expect(resolvedLoadKg(load, null), 20);
      const reps = 8;
      expect(resolvedLoadKg(load, null)! * reps, 160);
    },
  );

  test(
    'left and right use one actual device and preserve their actual side',
    () {
      final definition = _definition();
      for (final (side, value) in [
        (ExerciseSetSide.left, 10.0),
        (ExerciseSetSide.right, 12.0),
      ]) {
        final load = captureOriginalLoad(
          definition: definition,
          existing: null,
          typed: true,
          value: value,
          unit: ExerciseLoadUnit.kg,
          side: side,
        )!;
        expect(load.side, side);
        expect(load.deviceCount, 1);
        expect(resolvedLoadKg(load, null), value);
      }
    },
  );

  test('untouched source count wins over the definition default', () {
    final source = OriginalLoadInput(
      value: 10,
      unit: ExerciseLoadUnit.kg,
      basis: ExerciseLoadBasis.perDevice,
      deviceCount: 3,
      repetitionBasis: ExerciseRepetitionBasis.perSide,
      side: ExerciseSetSide.both,
    );
    final untouched = captureOriginalLoad(
      definition: _definition(count: 2),
      existing: source,
      typed: true,
      value: 10,
      unit: ExerciseLoadUnit.kg,
      side: ExerciseSetSide.both,
    )!;
    expect(untouched.deviceCount, 3);
    expect(resolvedLoadKg(untouched, null), 30);

    final changedSide = captureOriginalLoad(
      definition: _definition(count: 2),
      existing: source,
      typed: true,
      value: 10,
      unit: ExerciseLoadUnit.kg,
      side: ExerciseSetSide.left,
    )!;
    expect(changedSide.deviceCount, 1);
    expect(resolvedLoadKg(changedSide, null), 10);
  });

  test('null, explicit zero, assistance, and bodyweight remain distinct', () {
    OriginalLoadInput capture(ExerciseLoadBasis basis, double? value) =>
        captureOriginalLoad(
          definition: _definition(
            basis: basis,
            count: basis == ExerciseLoadBasis.perDevice ? 2 : null,
            repetitions: ExerciseRepetitionBasis.total,
          ),
          existing: null,
          typed: true,
          value: value,
          unit: ExerciseLoadUnit.kg,
          side: ExerciseSetSide.both,
        )!;

    final typedBlank = capture(ExerciseLoadBasis.total, null);
    expect(typedBlank.value, isNull);
    expect(typedBlank.unit, ExerciseLoadUnit.kg);
    expect(typedBlank.basis, ExerciseLoadBasis.total);
    expect(typedBlank.repetitionBasis, ExerciseRepetitionBasis.total);
    expect(resolvedLoadKg(typedBlank, null), isNull);
    expect(resolvedLoadKg(capture(ExerciseLoadBasis.total, 0), null), 0);
    final assistance = capture(ExerciseLoadBasis.assistance, 15);
    expect(assistance.value, 15);
    expect(resolvedLoadKg(assistance, null), isNull);
    expect(
      () => resolvedLoadKg(capture(ExerciseLoadBasis.assistance, 0), null),
      throwsFormatException,
    );
    final bodyweight = capture(ExerciseLoadBasis.bodyweight, null);
    expect(bodyweight.value, isNull);
    expect(bodyweight.unit, isNull);
    expect(resolvedLoadKg(bodyweight, null), isNull);
  });

  test('captions name added load and non-dumbbell devices precisely', () {
    expect(
      exerciseLoadCaption(definition: _definition()),
      'kg je Hantel · Wdh. je Seite',
    );
    expect(
      exerciseLoadCaption(
        definition: _definition(equipment: ExerciseEquipmentCategory.machine),
      ),
      'kg je Gerät · Wdh. je Seite',
    );
    expect(
      exerciseLoadCaption(
        definition: _definition(
          basis: ExerciseLoadBasis.addedLoad,
          count: null,
          repetitions: ExerciseRepetitionBasis.total,
        ),
      ),
      'kg Zusatzgewicht',
    );
  });

  test(
    'lb conversion preserves meaning and precise historic totals stay literal',
    () {
      final pounds = convertLoadValue(
        10,
        ExerciseLoadUnit.kg,
        ExerciseLoadUnit.lb,
      );
      final load = OriginalLoadInput(
        value: pounds,
        unit: ExerciseLoadUnit.lb,
        basis: ExerciseLoadBasis.perDevice,
        deviceCount: 2,
        repetitionBasis: ExerciseRepetitionBasis.total,
      );
      expect(resolvedLoadKg(load, null), closeTo(20, 1e-10));
      expect(resolvedLoadKg(null, 20.123456789), 20.123456789);
    },
  );

  test('future metadata is retained, not captioned, edited, or compared', () {
    final future = OriginalLoadInput.fromJson({
      'value': 17.25,
      'unit': 'stone',
      'basis': 'futureBasis',
      'repetitionBasis': 'futureReps',
      'side': 'futureSide',
      'future': {'v': 2},
    });
    final definition = _definition();

    expect(
      hasUnsupportedLoadMetadata(definition: definition, load: future),
      isTrue,
    );
    expect(exerciseLoadBasis(definition: definition, load: future), isNull);
    expect(exerciseLoadCaption(definition: definition, load: future), isNull);
    expect(showsSideControl(definition: definition, load: future), isFalse);
    expect(showsUnitChoice(definition: definition, load: future), isFalse);
    expect(
      captureOriginalLoad(
        definition: definition,
        existing: future,
        typed: true,
        value: 99,
        unit: ExerciseLoadUnit.kg,
        side: ExerciseSetSide.left,
      ),
      same(future),
    );
    expect(
      originalLoadsComparable(
        previous: future,
        current: null,
        definition: definition,
      ),
      isFalse,
    );
    expect(future.toJson()['retained'], containsPair('basis', 'futureBasis'));
  });

  test('legacy totals never inherit definition basis, side, or unit', () {
    final definition = _definition();
    const rows = [
      ExerciseLoadRowView(historicKg: 20, typed: false),
      ExerciseLoadRowView(historicKg: 20, typed: false),
    ];
    expect(
      frozenDefinition(load: null, typed: false, definition: definition),
      isNull,
    );
    expect(isTypedLoadRow(historicKg: 20, definition: definition), isFalse);
    expect(isTypedLoadRow(definition: definition), isFalse);
    expect(
      storedLoadUnit(load: null, typed: false, chosen: ExerciseLoadUnit.kg),
      isNull,
    );
    final blankLabels = exerciseBlockLoadLabels(
      definition: definition,
      rows: const [ExerciseLoadRowView()],
    );
    expect(blankLabels.caption, isNull);
    expect(blankLabels.loadHeader, 'LAST');
    expect(
      showsSideControl(
        definition: frozenDefinition(
          load: null,
          typed: false,
          definition: definition,
        ),
        load: null,
      ),
      isFalse,
    );
    expect(
      showsUnitChoice(
        definition: frozenDefinition(
          load: null,
          typed: false,
          definition: definition,
        ),
        load: null,
      ),
      isFalse,
    );
    final labels = exerciseBlockLoadLabels(definition: definition, rows: rows);
    expect(labels.caption, isNull);
    expect(labels.mixedSemantics, isFalse);
    expect(labels.loadHeader, 'KG');
    expect(
      exerciseRowLoadCaption(
        definition: definition,
        typed: false,
        historicLoadKg: 20,
      ),
      'Gesamtgewicht',
    );
  });

  test('mixed basis omits the common caption and labels each row', () {
    final definition = _definition();
    final perDevice = OriginalLoadInput(
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
    final labels = exerciseBlockLoadLabels(
      definition: definition,
      rows: [
        ExerciseLoadRowView(load: perDevice, typed: true),
        const ExerciseLoadRowView(historicKg: 20, typed: false),
        ExerciseLoadRowView(load: future, historicKg: 20.123456789),
      ],
    );
    expect(labels.caption, isNull);
    expect(labels.mixedSemantics, isTrue);
    expect(labels.loadHeader, 'LAST');
    expect(
      exerciseRowLoadCaption(
        definition: definition,
        load: perDevice,
        typed: true,
      ),
      'je Hantel · Wdh. je Seite',
    );
    expect(
      exerciseRowLoadCaption(
        definition: definition,
        typed: false,
        historicLoadKg: 20,
      ),
      'Gesamtgewicht',
    );
    expect(
      exerciseRowLoadCaption(
        definition: definition,
        load: future,
        historicLoadKg: 20.123456789,
      ),
      '—',
    );
    expect(
      storedLoadUnit(load: future, typed: false, historicKg: 20.123456789),
      isNull,
    );
    expect(
      storedLoadUnit(load: null, typed: false, historicKg: 20),
      ExerciseLoadUnit.kg,
    );
  });

  test('mixed units with one basis keep LAST and a unit-free caption', () {
    final definition = _definition(repetitions: ExerciseRepetitionBasis.total);
    final kg = OriginalLoadInput(
      value: 10,
      unit: ExerciseLoadUnit.kg,
      basis: ExerciseLoadBasis.perDevice,
      deviceCount: 2,
      repetitionBasis: ExerciseRepetitionBasis.total,
    );
    final lb = OriginalLoadInput(
      value: 10 / kKilogramsPerPound,
      unit: ExerciseLoadUnit.lb,
      basis: ExerciseLoadBasis.perDevice,
      deviceCount: 2,
      repetitionBasis: ExerciseRepetitionBasis.total,
    );
    final labels = exerciseBlockLoadLabels(
      definition: definition,
      rows: [
        ExerciseLoadRowView(load: kg, typed: true, chosenUnit: kg.unit),
        ExerciseLoadRowView(load: lb, typed: true, chosenUnit: lb.unit),
      ],
    );
    expect(labels.caption, 'je Hantel');
    expect(labels.mixedSemantics, isFalse);
    expect(labels.mixedUnits, isTrue);
    expect(labels.loadHeader, 'LAST');
  });

  test('new typed drafts may still use the frozen definition', () {
    final definition = _definition();
    expect(
      exerciseBlockLoadLabels(
        definition: definition,
        rows: const [ExerciseLoadRowView(typed: true)],
      ).caption,
      'kg je Hantel · Wdh. je Seite',
    );
    expect(
      showsSideControl(
        definition: frozenDefinition(
          load: null,
          typed: true,
          definition: definition,
        ),
        load: null,
      ),
      isTrue,
    );
  });

  test(
    'previous labels abstain across side, repetition, or count semantics',
    () {
      OriginalLoadInput load({
        ExerciseRepetitionBasis reps = ExerciseRepetitionBasis.perSide,
        ExerciseSetSide? side = ExerciseSetSide.both,
        int count = 2,
      }) => OriginalLoadInput(
        value: 10,
        unit: ExerciseLoadUnit.kg,
        basis: ExerciseLoadBasis.perDevice,
        deviceCount: count,
        repetitionBasis: reps,
        side: side,
      );

      expect(
        originalLoadsComparable(
          previous: load(side: ExerciseSetSide.left, count: 1),
          current: load(side: ExerciseSetSide.right, count: 1),
          definition: _definition(),
        ),
        isFalse,
      );
      expect(
        originalLoadsComparable(
          previous: load(count: 1),
          current: load(count: 2),
          definition: _definition(),
        ),
        isFalse,
      );
      expect(
        originalLoadsComparable(
          previous: load(reps: ExerciseRepetitionBasis.total, side: null),
          current: load(),
          definition: _definition(),
        ),
        isFalse,
      );
      expect(
        originalLoadsComparable(
          previous: load(),
          current: load(),
          definition: _definition(),
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'template mixed rows caption each set and leave legacy totals untouched',
    (tester) async {
      final repo = SyntheticOpenBandRepository.fromMaps(
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
      final definition = _definition();
      final perDevice = OriginalLoadInput(
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
      final original = await repo.saveTemplate(
        WorkoutTemplate(
          id: 'tpl-mixed-basis',
          name: 'Gemischt',
          version: 1,
          exercises: [
            PlannedExercise(
              id: 'ex-mixed',
              exerciseKey: definition.id,
              name: definition.label,
              definition: definition,
              sets: [
                PlannedSet(id: 'typed', reps: 8, loadKg: 20, load: perDevice),
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
          updatedAt: DateTime(2026, 9, 20),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('de')],
          theme: openBandTheme(Brightness.light),
          home: OpenBandTemplateEditor(repository: repo, template: original),
        ),
      );
      await tester.pump();

      expect(find.text('kg je Hantel · Wdh. je Seite'), findsNothing);
      expect(find.text('je Hantel · Wdh. je Seite'), findsOneWidget);
      expect(find.text('Gesamtgewicht'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(find.text('Beide Seiten'), findsOneWidget);
      expect(find.byKey(const ValueKey('side-legacy')), findsNothing);
      expect(find.byKey(const ValueKey('side-future')), findsNothing);
      expect(find.widgetWithText(TextField, '20,123456789'), findsWidgets);

      await tester.tap(find.text('Vorlage speichern'));
      await tester.pumpAndSettle();
      final saved = (await repo.readTemplates()).firstWhere(
        (t) => t.id == 'tpl-mixed-basis',
      );
      expect(saved.exercises.single.sets[0].load?.toJson(), perDevice.toJson());
      expect(saved.exercises.single.sets[1].load, isNull);
      expect(saved.exercises.single.sets[1].loadKg, 20.123456789);
      expect(saved.exercises.single.sets[2].load?.toJson(), future.toJson());
      expect(saved.exercises.single.sets[2].loadKg, 20.123456789);
    },
  );
}
