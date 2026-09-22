import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/openband/medication_data.dart';

void main() {
  test('missing amount is unknown, never as-directed copy', () {
    const draft = MedicationPlanDraft(create: true, name: 'X');
    expect(draft.doseValue, isNull);
    expect(draft.doseUnit, isNull);
    requireMedicationPlanDraft(draft);
    expect(draft.name, isNot(contains('directed')));
  });

  test('new identity is a UUID, not a name slug', () {
    final id = newMedicationPlanId();
    expect(id, isNot(startsWith('custom_')));
    expect(id, contains('-'));
    expect(id.length, greaterThan(8));
  });
}
