import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/openband/exercise_load.dart';

void main() {
  test('total and addedLoad store input kilograms', () {
    final total = OriginalLoadInput(
      value: 20,
      unit: ExerciseLoadUnit.kg,
      basis: ExerciseLoadBasis.total,
      repetitionBasis: ExerciseRepetitionBasis.total,
    );
    expect(normalizeExerciseLoad(total), 20);
    expect(resolveStoredLoadKg(input: total, loadKg: 20), 20);

    final added = OriginalLoadInput(
      value: 10,
      unit: ExerciseLoadUnit.kg,
      basis: ExerciseLoadBasis.addedLoad,
    );
    expect(normalizeExerciseLoad(added), 10);
    expect(resolveStoredLoadKg(input: added), 10);
  });

  test('two dumbbells 10kg each are 20kg total, volume 160 not 320', () {
    final input = OriginalLoadInput(
      value: 10,
      unit: ExerciseLoadUnit.kg,
      basis: ExerciseLoadBasis.perDevice,
      deviceCount: 2,
      repetitionBasis: ExerciseRepetitionBasis.perSide,
      side: ExerciseSetSide.both,
    );
    expect(normalizeExerciseLoad(input), 20);
    expect(20 * 8, 160);
    expect(normalizeExerciseLoad(input)! * 8, isNot(320));
  });

  test('left and right sets each use actual count 1', () {
    OriginalLoadInput side(ExerciseSetSide side) => OriginalLoadInput(
      value: 10,
      unit: ExerciseLoadUnit.kg,
      basis: ExerciseLoadBasis.perDevice,
      deviceCount: 1,
      repetitionBasis: ExerciseRepetitionBasis.perSide,
      side: side,
    );
    expect(normalizeExerciseLoad(side(ExerciseSetSide.left)), 10);
    expect(normalizeExerciseLoad(side(ExerciseSetSide.right)), 10);
    expect(
      normalizeExerciseLoad(side(ExerciseSetSide.left))! +
          normalizeExerciseLoad(side(ExerciseSetSide.right))!,
      20,
    );
  });

  test('pounds convert once into kilograms', () {
    final input = OriginalLoadInput(
      value: 10,
      unit: ExerciseLoadUnit.lb,
      basis: ExerciseLoadBasis.perDevice,
      deviceCount: 2,
    );
    expect(normalizeExerciseLoad(input), 10 * kKilogramsPerPound * 2);
    expect(kilogramsFromLoadUnit(10, ExerciseLoadUnit.lb), 10 * kKilogramsPerPound);
  });

  test('explicit zero stays known zero; null stays null', () {
    final zero = OriginalLoadInput(
      value: 0,
      unit: ExerciseLoadUnit.kg,
      basis: ExerciseLoadBasis.total,
    );
    expect(normalizeExerciseLoad(zero), 0);
    expect(resolveStoredLoadKg(input: zero, loadKg: 0), 0);

    final unknown = OriginalLoadInput(basis: ExerciseLoadBasis.total);
    expect(normalizeExerciseLoad(unknown), isNull);
    expect(resolveStoredLoadKg(input: unknown), isNull);
    expect(resolveStoredLoadKg(loadKg: 62.55), 62.55);
  });

  test('bodyweight and assistance do not claim lifted load', () {
    final body = OriginalLoadInput(basis: ExerciseLoadBasis.bodyweight);
    expect(normalizeExerciseLoad(body), isNull);
    expect(resolveStoredLoadKg(input: body), isNull);

    final help = OriginalLoadInput(
      value: 15,
      unit: ExerciseLoadUnit.kg,
      basis: ExerciseLoadBasis.assistance,
    );
    expect(help.value, 15);
    expect(normalizeExerciseLoad(help), isNull);
    expect(
      () => resolveStoredLoadKg(input: help, loadKg: 15),
      throwsA(isA<FormatException>()),
    );

    final blank = OriginalLoadInput(
      basis: ExerciseLoadBasis.assistance,
      unit: ExerciseLoadUnit.kg,
    );
    expect(blank.value, isNull);
    expect(normalizeExerciseLoad(blank), isNull);
    expect(resolveStoredLoadKg(input: blank), isNull);
    expect(
      () => normalizeExerciseLoad(
        OriginalLoadInput(
          value: 0,
          unit: ExerciseLoadUnit.kg,
          basis: ExerciseLoadBasis.assistance,
        ),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('contradictory total and metadata are rejected', () {
    final input = OriginalLoadInput(
      value: 10,
      unit: ExerciseLoadUnit.kg,
      basis: ExerciseLoadBasis.perDevice,
      deviceCount: 2,
    );
    expect(
      () => resolveStoredLoadKg(input: input, loadKg: 10),
      throwsA(isA<FormatException>()),
    );
  });

  test('fractional device counts are not truncated', () {
    expect(
      () => OriginalLoadInput.fromJson({
        'value': 10,
        'unit': 'kg',
        'basis': 'perDevice',
        'deviceCount': 1.5,
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => OriginalLoadInput.fromJson({
        'value': 10,
        'unit': 'kg',
        'basis': 'perDevice',
        'deviceCount': 0,
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('non-finite values are rejected', () {
    expect(
      () => OriginalLoadInput.fromJson({
        'value': double.nan,
        'unit': 'kg',
        'basis': 'total',
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => OriginalLoadInput.fromJson({
        'value': double.infinity,
        'unit': 'kg',
        'basis': 'total',
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => kilogramsFromLoadUnit(double.nan, ExerciseLoadUnit.kg),
      throwsArgumentError,
    );
  });

  test('future wire enums stay in retained metadata', () {
    var input = OriginalLoadInput.fromJson({
      'value': 10,
      'unit': 'stone',
      'basis': 'band',
      'repetitionBasis': 'perCluster',
      'side': 'lead',
      'mystery': true,
    });
    expect(input.unit, isNull);
    expect(input.basis, isNull);
    expect(input.repetitionBasis, isNull);
    expect(input.side, isNull);
    expect(input.retained['unit'], 'stone');
    expect(input.retained['basis'], 'band');
    expect(input.retained['repetitionBasis'], 'perCluster');
    expect(input.retained['side'], 'lead');
    expect(input.retained['mystery'], isTrue);
    for (var i = 0; i < 3; i++) {
      input = OriginalLoadInput.fromJson(input.toJson());
    }
    expect(input.retained['basis'], 'band');
    expect(input.retained['mystery'], isTrue);
    expect(input.retained.containsKey('retained'), isFalse);
  });

  test('legacy rows without metadata keep the stored total', () {
    expect(resolveStoredLoadKg(loadKg: 10), 10);
    expect(resolveStoredLoadKg(), isNull);
  });

  test('perDevice overflow is not stored as Infinity', () {
    expect(
      () => normalizeExerciseLoad(
        OriginalLoadInput(
          value: 1e308,
          unit: ExerciseLoadUnit.kg,
          basis: ExerciseLoadBasis.perDevice,
          deviceCount: 10,
        ),
      ),
      throwsArgumentError,
    );
  });
}
