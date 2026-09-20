import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';

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

void main() {
  const oats = FoodHit(
    key: 'oats',
    label: 'Haferflocken',
    servingG: 80,
    kcal100: 372,
    proteinG100: 13.5,
    carbsG100: 58.7,
    fatG100: 7,
    fibreG100: 10.6,
    ironMg100: 4.7,
    source: FoodSource.barcode,
    sourceCode: 'barcode',
  );

  test('decodeFoodSource keeps exact unknown and empty wire', () {
    expect(decodeFoodSource(null), (source: FoodSource.manual, code: 'manual'));
    expect(decodeFoodSource('manual'), (source: FoodSource.manual, code: 'manual'));
    expect(decodeFoodSource('photo'), (source: FoodSource.photo, code: 'photo'));
    expect(
      decodeFoodSource('crowd-guess'),
      (source: FoodSource.unknown, code: 'crowd-guess'),
    );
    expect(decodeFoodSource(''), (source: FoodSource.unknown, code: ''));
  });

  test('unknown plus photo wire is photo before sanitise', () {
    const sneak = FoodEntry(
      id: 'sneak',
      date: '2026-09-15',
      meal: 'lunch',
      label: 'Rice',
      kcal: 720,
      source: FoodSource.unknown,
      sourceCode: 'photo',
    );
    expect(sneak.source, FoodSource.photo);
    expect(sneak.sourceCode, 'photo');
    expect(sneak.sanitised.kcal, isNull);
  });

  test('old draft JSON does not fabricate source, time, or nutrients', () {
    final parsed = MealDraftEntry.fromJson({
      'id': 'e1',
      'label': 'Reis',
      'quantity': 180,
      'unit': 'g',
      'kcal': 300,
      'proteinG': null,
      'carbsG': 65,
      'fatG': null,
      'foodKey': 'rice',
    });
    expect(parsed.source, isNull);
    expect(parsed.sourceCode, isNull);
    expect(parsed.confirmed, isNull);
    expect(parsed.note, isNull);
    expect(parsed.atTs, isNull);
    expect(parsed.fibreG, isNull);
    expect(parsed.ironMg, isNull);
    expect(parsed.toJson().containsKey('source'), isFalse);
    expect(parsed.toJson().containsKey('fibreG'), isFalse);
    expect(parsed.toJson()['carbsG'], 65);
  });

  test('explicit draft source and precise quantities survive JSON', () {
    const entry = MealDraftEntry(
      id: 'e2',
      label: 'Haferflocken',
      quantity: 80.5,
      kcal: 299.46,
      ironMg: 3.7835,
      source: FoodSource.barcode,
      sourceCode: 'barcode',
      confirmed: true,
      note: 'pack',
    );
    final back = MealDraftEntry.fromJson(
      jsonDecode(jsonEncode(entry.toJson())) as Map<String, dynamic>,
    );
    expect(back, entry);
    expect(back.quantity, 80.5);
    expect(back.ironMg, 3.7835);
  });

  test('known photo plus conflicting manual wire is photo before sanitise', () {
    const entry = MealDraftEntry(
      id: 'p',
      label: 'Rice',
      quantity: 80,
      kcal: 123,
      proteinG: 10,
      source: FoodSource.photo,
      sourceCode: 'manual',
      confirmed: false,
    );
    expect(entry.toJson()['source'], 'photo');
    final mapped = foodEntryFromDraft(
      MealDraft(
        id: 'd',
        day: '2026-09-15',
        meal: 'lunch',
        entries: const [entry],
        updatedAt: DateTime(2026, 9, 15, 12),
      ),
      entry,
    );
    expect(mapped.source, FoodSource.photo);
    expect(mapped.sourceCode, 'photo');
    expect(mapped.sanitised.kcal, isNull);
    expect(mapped.sanitised.proteinG, isNull);
    expect(mapped.sanitised.quantity, isNull);
  });

  test('known manual plus conflicting photo wire stays manual', () {
    const entry = MealDraftEntry(
      id: 'm',
      label: 'Rice',
      kcal: 123,
      source: FoodSource.manual,
      sourceCode: 'photo',
      confirmed: false,
    );
    expect(entry.toJson()['source'], 'manual');
    final mapped = foodEntryFromDraft(
      MealDraft(
        id: 'd',
        day: '2026-09-15',
        meal: 'lunch',
        entries: const [entry],
        updatedAt: DateTime(2026, 9, 15, 12),
      ),
      entry,
    );
    expect(mapped.source, FoodSource.manual);
    expect(mapped.sourceCode, 'manual');
    expect(mapped.sanitised.kcal, 123);
  });

  test('FoodHit.portion canonicalizes known source over default manual wire', () {
    const sneak = FoodHit(
      key: 'snap',
      label: 'Foto',
      source: FoodSource.photo,
    );
    expect(sneak.sourceCode, 'manual');
    final portion = sneak.portion('p1', 80);
    expect(portion.source, FoodSource.photo);
    expect(portion.sourceCode, 'photo');
    expect(portion.toJson()['source'], 'photo');
  });

  test('UI-manual draft commit mapping stays manual and confirmed', () {
    final draft = MealDraft(
      id: 'd',
      day: '2026-09-15',
      meal: 'dinner',
      entries: [MealDraftEntry(id: 'e1', label: 'Reis', kcal: 300, carbsG: 65)],
      updatedAt: DateTime(2026, 9, 15, 19),
    );
    final mapped = foodEntryFromDraft(draft, draft.entries.single);
    expect(mapped.source, FoodSource.manual);
    expect(mapped.sourceCode, 'manual');
    expect(mapped.confirmed, isTrue);
    expect(mapped.kcal, 300);
    expect(mapped.fibreG, isNull);
    expect(mapped.atTs, isNull);
  });

  test('portion scales only known per100 nutrients and keeps definition source', () {
    final portion = oats.portion('p1', 80.5);
    expect(portion.foodKey, 'oats');
    expect(portion.quantity, 80.5);
    expect(portion.kcal, closeTo(372 * 80.5 / 100, 1e-9));
    expect(portion.proteinG, closeTo(13.5 * 80.5 / 100, 1e-9));
    expect(portion.fibreG, closeTo(10.6 * 80.5 / 100, 1e-9));
    expect(portion.ironMg, closeTo(4.7 * 80.5 / 100, 1e-9));
    expect(portion.sugarG, isNull);
    expect(portion.calciumMg, isNull);
    expect(portion.source, FoodSource.barcode);
    expect(portion.sourceCode, 'barcode');
    const coffee = FoodHit(key: 'coffee', label: 'Kaffee');
    final black = coffee.portion('c1', 200);
    expect(black.kcal, isNull);
    expect(black.source, FoodSource.manual);
  });

  test('foodEntriesEqual uses every persisted field including source wire', () {
    const a = FoodEntry(
      id: 's1',
      date: '2026-09-15',
      meal: 'breakfast',
      label: 'Haferflocken mit Milch',
      quantity: 80.5,
      kcal: 380,
      proteinG: 18,
      carbsG: 56,
      fatG: 12,
      fibreG: 8,
      source: FoodSource.unknown,
      sourceCode: 'crowd-guess',
      confirmed: true,
      createdAt: 10,
      updatedAt: 20,
    );
    expect(foodEntriesEqual(a, a), isTrue);
    expect(
      foodEntriesEqual(
        a,
        FoodEntry(
          id: a.id,
          date: a.date,
          meal: a.meal,
          label: a.label,
          quantity: a.quantity,
          kcal: a.kcal,
          proteinG: a.proteinG,
          carbsG: a.carbsG,
          fatG: a.fatG,
          fibreG: a.fibreG,
          source: FoodSource.unknown,
          sourceCode: 'crowd-guess',
          confirmed: true,
          createdAt: 10,
          updatedAt: 21,
        ),
      ),
      isFalse,
    );
    expect(
      foodEntriesEqual(
        a,
        FoodEntry(
          id: a.id,
          date: a.date,
          meal: a.meal,
          label: a.label,
          quantity: a.quantity,
          kcal: a.kcal,
          proteinG: a.proteinG,
          carbsG: a.carbsG,
          fatG: a.fatG,
          fibreG: a.fibreG,
          source: FoodSource.unknown,
          sourceCode: 'other',
          confirmed: true,
          createdAt: 10,
          updatedAt: 20,
        ),
      ),
      isFalse,
    );
    expect(
      foodEntriesEqual(
        a,
        FoodEntry(
          id: a.id,
          date: a.date,
          meal: a.meal,
          label: a.label,
          quantity: a.quantity,
          kcal: 381,
          proteinG: a.proteinG,
          carbsG: a.carbsG,
          fatG: a.fatG,
          fibreG: a.fibreG,
          source: FoodSource.unknown,
          sourceCode: 'crowd-guess',
          confirmed: true,
          createdAt: 10,
          updatedAt: 20,
        ),
        ledger: false,
      ),
      isFalse,
    );
  });

  test('write validation allows absent optionals and refuses invalid amounts', () {
    requireFoodEntryWrite(
      const FoodEntry(
        id: 'ok',
        date: '2026-09-15',
        meal: 'snack',
        label: 'Kaffee',
        source: FoodSource.unknown,
        sourceCode: '',
      ),
    );
    expect(
      () => requireFoodEntryWrite(
        const FoodEntry(
          id: '',
          date: '2026-09-15',
          meal: 'snack',
          label: 'Kaffee',
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => requireFoodEntryWrite(
        const FoodEntry(
          id: 'bad',
          date: '2026-02-30',
          meal: 'snack',
          label: 'Kaffee',
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => requireFoodEntryWrite(
        const FoodEntry(
          id: 'bad',
          date: '2026-09-15',
          meal: 'snack',
          label: 'Kaffee',
          kcal: -1,
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => requireFoodEntryWrite(
        const FoodEntry(
          id: 'bad',
          date: '2026-09-15',
          meal: 'snack',
          label: 'Kaffee',
          quantity: double.nan,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('const MealEntry and FoodHit callers keep compiling with defaults', () {
    const meal = MealEntry(id: 'm2', meal: 'breakfast', label: 'Kaffee');
    const hit = FoodHit(key: 'coffee', label: 'Kaffee schwarz', servingG: 200);
    expect(meal.source, FoodSource.manual);
    expect(meal.fibreG, isNull);
    expect(hit.source, FoodSource.manual);
    expect(hit.fibreG100, isNull);
  });

  test('synthetic window uses raw day sums and keeps empty days', () async {
    final repo = _repo();
    repo.nutritionToday = () => '2026-09-20';
    repo.seedFoodEntry(
      const FoodEntry(
        id: 'a',
        date: '2026-09-09',
        meal: 'lunch',
        label: 'A',
        kcal: 420,
        createdAt: 1,
        updatedAt: 1,
      ),
    );
    repo.seedFoodEntry(
      const FoodEntry(
        id: 'b',
        date: '2026-09-10',
        meal: 'lunch',
        label: 'B',
        kcal: 780,
        createdAt: 2,
        updatedAt: 2,
      ),
    );
    repo.seedFoodEntry(
      const FoodEntry(
        id: 'b-miss',
        date: '2026-09-10',
        meal: 'dinner',
        label: 'C',
        createdAt: 3,
        updatedAt: 3,
      ),
    );
    repo.seedFoodEntry(
      const FoodEntry(
        id: 'zero',
        date: '2026-09-12',
        meal: 'lunch',
        label: 'Water',
        kcal: 0,
        createdAt: 4,
        updatedAt: 4,
      ),
    );
    final window = await repo.readNutritionWindow('2026-09-15');
    expect(window.days.map((d) => d.date), [
      '2026-09-09',
      '2026-09-10',
      '2026-09-11',
      '2026-09-12',
      '2026-09-13',
      '2026-09-14',
      '2026-09-15',
    ]);
    expect(window.days[0].kcal.value, 420);
    expect(window.days[0].kcal.unknown, 0);
    expect(window.days[1].kcal.value, 780);
    expect(window.days[1].kcal.unknown, 1);
    expect(window.days[2].entries, isEmpty);
    expect(window.days[2].kcal.value, isNull);
    expect(window.days[3].kcal.value, 0);
    expect(window.days[3].kcal.known, 1);
    expect(window.meanKcal.value, isNull);
  });
}
