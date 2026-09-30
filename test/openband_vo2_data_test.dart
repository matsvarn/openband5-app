import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/openband/vo2_data.dart';

void main() {
  test('a civil day is accepted and an impossible one is not', () {
    expect(isVo2CivilDay('2026-09-14'), isTrue);
    expect(isVo2CivilDay('2024-02-29'), isTrue);
    expect(isVo2CivilDay('2025-02-29'), isFalse);
    expect(isVo2CivilDay('2026-02-31'), isFalse);
    expect(isVo2CivilDay('2026-9-14'), isFalse);
    expect(isVo2CivilDay('14.09.2026'), isFalse);
  });

  test('value must be finite and positive, with no invented ceiling', () {
    expect(isVo2Value(42), isTrue);
    expect(isVo2Value(42.5), isTrue);
    expect(isVo2Value(250), isTrue);
    expect(isVo2Value(0), isFalse);
    expect(isVo2Value(-1), isFalse);
    expect(isVo2Value(double.nan), isFalse);
    expect(isVo2Value(double.infinity), isFalse);
  });

  test('blank method is absent and surrounding space is not stored', () {
    expect(normalizeVo2Method(null), isNull);
    expect(normalizeVo2Method(''), isNull);
    expect(normalizeVo2Method('   '), isNull);
    expect(normalizeVo2Method('  Spiroergometrie  '), 'Spiroergometrie');
  });

  test('a malformed row is not a zero or a stand-in date', () {
    final parsed = tryParseVo2Row({
      'id': 'e1',
      'revision': 1,
      'measured_on': 'yesterday',
      'value_ml_kg_min': 0,
      'declared_method': null,
      'created_at': 1,
      'updated_at': 1,
      'deleted': 0,
      'origin': kVo2Origin,
      'unit': kVo2Unit,
    });
    expect(parsed, isNull);
  });

  test('1e100 is not a revision or a timestamp, and 1.0 still is', () {
    const saturated = 9223372036854775807;
    expect(1e100.toInt(), saturated);
    final hugeRevision = tryParseVo2Row({
      'id': 'e1',
      'revision': 1e100,
      'measured_on': '2026-09-14',
      'value_ml_kg_min': 42,
      'declared_method': null,
      'created_at': 1,
      'updated_at': 1,
      'deleted': 0,
      'origin': kVo2Origin,
      'unit': kVo2Unit,
    });
    expect(hugeRevision, isNull);
    final hugeTime = tryParseVo2Row({
      'id': 'e1',
      'revision': 1,
      'measured_on': '2026-09-14',
      'value_ml_kg_min': 42,
      'declared_method': null,
      'created_at': 1e100,
      'updated_at': 1e100,
      'deleted': 0,
      'origin': kVo2Origin,
      'unit': kVo2Unit,
    });
    expect(hugeTime, isNull);
    final one = tryParseVo2Row({
      'id': 'e1',
      'revision': 1.0,
      'measured_on': '2026-09-14',
      'value_ml_kg_min': 42,
      'declared_method': null,
      'created_at': 1.0,
      'updated_at': 1.0,
      'deleted': 0,
      'origin': kVo2Origin,
      'unit': kVo2Unit,
    });
    expect(one?.revision, 1);
    expect(one?.createdAt, 1);
    expect(one?.updatedAt, 1);
    expect(one?.revision, isNot(saturated));
  });

  test('2^63 is not a revision or a timestamp', () {
    final two63 = 9223372036854775808.0;
    final saturated = two63.toInt();
    expect(two63 == saturated.toDouble(), isTrue);
    expect(saturated, 9223372036854775807);
    expect(
      tryParseVo2Row({
        'id': 'e1',
        'revision': two63,
        'measured_on': '2026-09-14',
        'value_ml_kg_min': 42,
        'declared_method': null,
        'created_at': 1,
        'updated_at': 1,
        'deleted': 0,
        'origin': kVo2Origin,
        'unit': kVo2Unit,
      }),
      isNull,
    );
    expect(
      tryParseVo2Row({
        'id': 'e1',
        'revision': 1,
        'measured_on': '2026-09-14',
        'value_ml_kg_min': 42,
        'declared_method': null,
        'created_at': two63,
        'updated_at': two63,
        'deleted': 0,
        'origin': kVo2Origin,
        'unit': kVo2Unit,
      }),
      isNull,
    );
    final maxInt = tryParseVo2Row({
      'id': 'e1',
      'revision': 9223372036854775807,
      'measured_on': '2026-09-14',
      'value_ml_kg_min': 42,
      'declared_method': null,
      'created_at': 1,
      'updated_at': 1,
      'deleted': 0,
      'origin': kVo2Origin,
      'unit': kVo2Unit,
    });
    expect(maxInt?.revision, 9223372036854775807);
  });

  test('wrong origin or unit does not become user-entered', () {
    expect(
      tryParseVo2Row({
        'id': 'e1',
        'revision': 1,
        'measured_on': '2026-09-14',
        'value_ml_kg_min': 42,
        'declared_method': null,
        'created_at': 1,
        'updated_at': 1,
        'deleted': 0,
        'origin': 'estimated',
        'unit': kVo2Unit,
      }),
      isNull,
    );
    expect(
      tryParseVo2Row({
        'id': 'e1',
        'revision': 1,
        'measured_on': '2026-09-14',
        'value_ml_kg_min': 42,
        'declared_method': null,
        'created_at': 1,
        'updated_at': 1,
        'deleted': 0,
        'origin': kVo2Origin,
        'unit': 'L/min',
      }),
      isNull,
    );
  });

  test('a deleted revision keeps the value it removed', () {
    const head = Vo2Revision(
      id: 'e1',
      revision: 2,
      measuredOn: '2026-09-14',
      valueMlKgMin: 42.5,
      declaredMethod: 'Spiroergometrie',
      createdAt: 10,
      updatedAt: 20,
      deleted: true,
    );
    expect(head.valueMlKgMin, 42.5);
    expect(head.deleted, isTrue);
  });
}
