import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _day = '2026-09-15';
const _otherDay = '2026-09-14';

SyntheticOpenBandRepository _synthetic() =>
    SyntheticOpenBandRepository.fromMaps(
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

MealDraftEntry _rich({
  String id = 'e-oats',
  String label = 'Haferflocken',
  double? quantity = 80.5,
  double? kcal = 299.46,
  double? proteinG = 10.8675,
  double? ironMg = 3.7835,
  double? fibreG = 8.533,
  FoodSource? source = FoodSource.unknown,
  String? sourceCode = 'crowd-guess',
  bool? confirmed = true,
  String? note = 'pack',
  int? atTs,
  int? createdAt,
  int? updatedAt,
}) => MealDraftEntry(
  id: id,
  label: label,
  quantity: quantity,
  kcal: kcal,
  proteinG: proteinG,
  carbsG: 47.2535,
  fatG: 5.635,
  fibreG: fibreG,
  sugarG: 0.9,
  satFatG: 1.1,
  sodiumMg: 4,
  ironMg: ironMg,
  calciumMg: 42.25,
  foodKey: 'oats',
  source: source,
  sourceCode: sourceCode,
  confirmed: confirmed,
  note: note,
  atTs: atTs,
  createdAt: createdAt,
  updatedAt: updatedAt,
);

MealDraft _draft({
  String id = 'd-dinner',
  String day = _day,
  String meal = 'dinner',
  List<MealDraftEntry>? entries,
  DateTime? updatedAt,
}) => MealDraft(
  id: id,
  day: day,
  meal: meal,
  entries: entries ?? [_rich()],
  updatedAt: updatedAt ?? DateTime(2026, 9, 15, 19),
);

void _expectRich(MealDraftEntry e, {String id = 'e-oats'}) {
  expect(e.id, id);
  expect(e.label, 'Haferflocken');
  expect(e.quantity, 80.5);
  expect(e.kcal, 299.46);
  expect(e.proteinG, 10.8675);
  expect(e.carbsG, 47.2535);
  expect(e.fatG, 5.635);
  expect(e.fibreG, 8.533);
  expect(e.sugarG, 0.9);
  expect(e.satFatG, 1.1);
  expect(e.sodiumMg, 4);
  expect(e.ironMg, 3.7835);
  expect(e.calciumMg, 42.25);
  expect(e.foodKey, 'oats');
  expect(e.source, FoodSource.unknown);
  expect(e.sourceCode, 'crowd-guess');
  expect(e.confirmed, isTrue);
  expect(e.note, 'pack');
  expect(e.atTs, isNull);
  expect(e.createdAt, isNull);
  expect(e.updatedAt, isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('synthetic', () {
    late SyntheticOpenBandRepository repo;
    setUp(() => repo = _synthetic());
    _cas(() => repo, sqlite: false);
  });

  group('SQLite', () {
    late AppState app;
    late LocalOpenBandRepository repo;
    const dbName = 'openband_draft_cas_test.db';

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      await LocalDb.close();
      LocalDb.dbName = dbName;
      final dir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase('$dir/$dbName');
      SharedPreferences.setMockInitialValues({});
      app = AppState.forTesting();
      repo = LocalOpenBandRepository(app);
    });

    tearDown(() async {
      app.dispose();
      await LocalDb.close();
    });

    _cas(() => repo, sqlite: true);

    test('reopen keeps full precision, unknown source, and null stamps', () async {
      expect(
        await repo.compareAndSaveMealDraft(expected: null, draft: _draft()),
        MealDraftSaveResult.saved,
      );
      await LocalDb.close();
      repo = LocalOpenBandRepository(app);
      final back = await repo.readMealDraft(_day, 'dinner');
      expect(back, isNotNull);
      expect(back!.id, 'd-dinner');
      _expectRich(back.entries.single);
    });

    test('concurrent edits against one snapshot: one saved, one conflict', () async {
      expect(
        await repo.compareAndSaveMealDraft(expected: null, draft: _draft()),
        MealDraftSaveResult.saved,
      );
      final first = (await repo.readMealDraft(_day, 'dinner'))!;
      final results = await Future.wait([
        repo.compareAndSaveMealDraft(
          expected: first,
          draft: _draft(entries: [_rich(kcal: 310.1)], updatedAt: first.updatedAt),
        ),
        repo.compareAndSaveMealDraft(
          expected: first,
          draft: _draft(entries: [_rich(kcal: 410.2)], updatedAt: first.updatedAt),
        ),
      ]);
      expect(results.where((r) => r == MealDraftSaveResult.saved).length, 1);
      expect(results.where((r) => r == MealDraftSaveResult.conflict).length, 1);
      final live = (await repo.readMealDraft(_day, 'dinner'))!;
      expect(live.entries.single.kcal, anyOf(310.1, 410.2));
      expect(live.id, first.id);
      expect(live.entries.single.sourceCode, 'crowd-guess');
      expect(live.entries.single.quantity, 80.5);
      expect(
        live.updatedAt.millisecondsSinceEpoch,
        greaterThan(first.updatedAt.millisecondsSinceEpoch),
      );
    });

    test('legacy omitted optional keys match a reread; source stays exact', () async {
      await LocalDb.putOpenBandMealDraft({
        'draft_id': 'raw-old',
        'day_id': _day,
        'meal': 'dinner',
        'entries_json': jsonEncode([
          {
            'id': 'raw-rice',
            'label': 'Reis',
            'quantity': 180,
            'kcal': 300,
            'carbsG': 65,
            'foodKey': 'rice',
            'source': 'crowd-guess',
          },
        ]),
        'updated_at': 1,
      });
      final retained = await repo.readMealDraft(_day, 'dinner');
      expect(retained, isNotNull);
      expect(retained!.entries.single.unit, 'g');
      expect(retained.entries.single.proteinG, isNull);
      expect(retained.entries.single.fibreG, isNull);
      expect(retained.entries.single.source, FoodSource.unknown);
      expect(retained.entries.single.sourceCode, 'crowd-guess');
      expect(
        await repo.compareAndSaveMealDraft(
          expected: retained,
          draft: MealDraft(
            id: retained.id,
            day: retained.day,
            meal: retained.meal,
            entries: [
              MealDraftEntry(
                id: 'raw-rice',
                label: 'Reis',
                quantity: 180.25,
                kcal: 300,
                carbsG: 65,
                foodKey: 'rice',
                source: FoodSource.unknown,
                sourceCode: 'crowd-guess',
              ),
            ],
            updatedAt: retained.updatedAt,
          ),
        ),
        MealDraftSaveResult.saved,
      );
      final live = (await repo.readMealDraft(_day, 'dinner'))!;
      expect(live.entries.single.quantity, 180.25);
      expect(live.entries.single.kcal, 300);
      expect(live.entries.single.proteinG, isNull);
      expect(live.entries.single.sourceCode, 'crowd-guess');
      expect(
        live.updatedAt.millisecondsSinceEpoch,
        greaterThan(retained.updatedAt.millisecondsSinceEpoch),
      );
    });

    test('corrupt entries JSON does not save', () async {
      await LocalDb.putOpenBandMealDraft({
        'draft_id': 'bad',
        'day_id': _day,
        'meal': 'dinner',
        'entries_json': '{"not":"a list"}',
        'updated_at': 1,
      });
      final expected = MealDraft(
        id: 'bad',
        day: _day,
        meal: 'dinner',
        entries: [_rich()],
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1),
      );
      await expectLater(
        repo.compareAndSaveMealDraft(expected: expected, draft: expected),
        throwsA(isA<FormatException>()),
      );
      final row = await LocalDb.openBandMealDraft(_day, 'dinner');
      expect(row!['draft_id'], 'bad');
      expect(row['entries_json'], '{"not":"a list"}');
      expect(row['updated_at'], 1);
    });
  });
}

void _cas(OpenBandRepository Function() current, {required bool sqlite}) {
  test('absent create then reread keeps full snapshot', () async {
    final repo = current();
    expect(await repo.readMealDraft(_day, 'dinner'), isNull);
    expect(
      await repo.compareAndSaveMealDraft(expected: null, draft: _draft()),
      MealDraftSaveResult.saved,
    );
    final stored = await repo.readMealDraft(_day, 'dinner');
    expect(stored, isNotNull);
    expect(stored!.id, 'd-dinner');
    expect(stored.day, _day);
    expect(stored.meal, 'dinner');
    _expectRich(stored.entries.single);
  });

  test('stale absent contender conflicts and writes nothing', () async {
    final repo = current();
    expect(
      await repo.compareAndSaveMealDraft(expected: null, draft: _draft()),
      MealDraftSaveResult.saved,
    );
    final prior = (await repo.readMealDraft(_day, 'dinner'))!;
    expect(
      await repo.compareAndSaveMealDraft(
        expected: null,
        draft: _draft(
          id: 'd-other',
          entries: [_rich(id: 'e-other', label: 'Tofu', kcal: 180)],
        ),
      ),
      MealDraftSaveResult.conflict,
    );
    final held = (await repo.readMealDraft(_day, 'dinner'))!;
    expect(held.id, prior.id);
    expect(held.updatedAt, prior.updatedAt);
    _expectRich(held.entries.single);
  });

  test('exact edit preserves precision, unknown nutrients, source, confirmed, note', () async {
    final repo = current();
    expect(
      await repo.compareAndSaveMealDraft(expected: null, draft: _draft()),
      MealDraftSaveResult.saved,
    );
    final expected = (await repo.readMealDraft(_day, 'dinner'))!;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final next = _draft(
      entries: [
        _rich(
          quantity: 90.25,
          kcal: 335.394,
          ironMg: 4.2431875,
          note: 'rewe',
        ),
      ],
      updatedAt: expected.updatedAt,
    );
    expect(
      await repo.compareAndSaveMealDraft(expected: expected, draft: next),
      MealDraftSaveResult.saved,
    );
    final stored = (await repo.readMealDraft(_day, 'dinner'))!;
    expect(stored.id, expected.id);
    expect(stored.entries.single.quantity, 90.25);
    expect(stored.entries.single.kcal, 335.394);
    expect(stored.entries.single.ironMg, 4.2431875);
    expect(stored.entries.single.fibreG, 8.533);
    expect(stored.entries.single.source, FoodSource.unknown);
    expect(stored.entries.single.sourceCode, 'crowd-guess');
    expect(stored.entries.single.confirmed, isTrue);
    expect(stored.entries.single.note, 'rewe');
    expect(stored.entries.single.atTs, isNull);
    expect(stored.updatedAt.millisecondsSinceEpoch,
        isNot(expected.updatedAt.millisecondsSinceEpoch));
  });

  test('same-id different entry conflicts and keeps prior snapshot', () async {
    final repo = current();
    expect(
      await repo.compareAndSaveMealDraft(expected: null, draft: _draft()),
      MealDraftSaveResult.saved,
    );
    final prior = (await repo.readMealDraft(_day, 'dinner'))!;
    final stale = MealDraft(
      id: prior.id,
      day: prior.day,
      meal: prior.meal,
      entries: [_rich(label: 'Tofu', kcal: 180, proteinG: 18, fibreG: null)],
      updatedAt: prior.updatedAt,
    );
    expect(
      await repo.compareAndSaveMealDraft(
        expected: stale,
        draft: _draft(entries: [_rich(kcal: 10)], updatedAt: prior.updatedAt),
      ),
      MealDraftSaveResult.conflict,
    );
    final held = (await repo.readMealDraft(_day, 'dinner'))!;
    expect(held.updatedAt, prior.updatedAt);
    _expectRich(held.entries.single);
  });

  test('changed timestamp/revision conflicts', () async {
    final repo = current();
    expect(
      await repo.compareAndSaveMealDraft(expected: null, draft: _draft()),
      MealDraftSaveResult.saved,
    );
    final prior = (await repo.readMealDraft(_day, 'dinner'))!;
    final stale = MealDraft(
      id: prior.id,
      day: prior.day,
      meal: prior.meal,
      entries: prior.entries,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        prior.updatedAt.millisecondsSinceEpoch - 1,
      ),
    );
    expect(
      await repo.compareAndSaveMealDraft(
        expected: stale,
        draft: _draft(entries: [_rich(kcal: 10)], updatedAt: stale.updatedAt),
      ),
      MealDraftSaveResult.conflict,
    );
    final held = (await repo.readMealDraft(_day, 'dinner'))!;
    expect(held.updatedAt, prior.updatedAt);
    _expectRich(held.entries.single);
  });

  test('slot identity refusal does not write', () async {
    final repo = current();
    expect(
      await repo.compareAndSaveMealDraft(expected: null, draft: _draft()),
      MealDraftSaveResult.saved,
    );
    final prior = (await repo.readMealDraft(_day, 'dinner'))!;
    expect(
      () => repo.compareAndSaveMealDraft(
        expected: prior,
        draft: _draft(meal: 'lunch', updatedAt: prior.updatedAt),
      ),
      throwsArgumentError,
    );
    expect(
      () => repo.compareAndSaveMealDraft(
        expected: prior,
        draft: _draft(day: _otherDay, updatedAt: prior.updatedAt),
      ),
      throwsArgumentError,
    );
    final held = (await repo.readMealDraft(_day, 'dinner'))!;
    expect(held.updatedAt, prior.updatedAt);
    _expectRich(held.entries.single);
    expect(await repo.readMealDraft(_day, 'lunch'), isNull);
    expect(await repo.readMealDraft(_otherDay, 'dinner'), isNull);
  });

  test('expected present on empty slot conflicts', () async {
    final repo = current();
    final ghost = _draft();
    expect(
      await repo.compareAndSaveMealDraft(expected: ghost, draft: ghost),
      MealDraftSaveResult.conflict,
    );
    expect(await repo.readMealDraft(_day, 'dinner'), isNull);
  });

  test('failure leaves saved prior snapshot intact', () async {
    final repo = current();
    expect(
      await repo.compareAndSaveMealDraft(expected: null, draft: _draft()),
      MealDraftSaveResult.saved,
    );
    final prior = (await repo.readMealDraft(_day, 'dinner'))!;
    expect(
      () => repo.compareAndSaveMealDraft(
        expected: prior,
        draft: _draft(
          entries: [_rich(kcal: -1)],
          updatedAt: prior.updatedAt,
        ),
      ),
      throwsArgumentError,
    );
    if (!sqlite) {
      final synthetic = repo as SyntheticOpenBandRepository;
      synthetic.failFoodWrite = true;
      await expectLater(
        repo.compareAndSaveMealDraft(
          expected: prior,
          draft: _draft(entries: [_rich(kcal: 10)], updatedAt: prior.updatedAt),
        ),
        throwsStateError,
      );
      synthetic.failFoodWrite = false;
    }
    final held = (await repo.readMealDraft(_day, 'dinner'))!;
    expect(held.updatedAt, prior.updatedAt);
    _expectRich(held.entries.single);
  });

  test('separate slots are independent', () async {
    final repo = current();
    expect(
      await repo.compareAndSaveMealDraft(expected: null, draft: _draft()),
      MealDraftSaveResult.saved,
    );
    expect(
      await repo.compareAndSaveMealDraft(
        expected: null,
        draft: _draft(
          id: 'd-breakfast',
          meal: 'breakfast',
          entries: [
            _rich(id: 'e-coffee', label: 'Kaffee', kcal: 5, fibreG: null),
          ],
        ),
      ),
      MealDraftSaveResult.saved,
    );
    final dinner = (await repo.readMealDraft(_day, 'dinner'))!;
    final breakfast = (await repo.readMealDraft(_day, 'breakfast'))!;
    expect(
      await repo.compareAndSaveMealDraft(
        expected: breakfast,
        draft: _draft(
          id: breakfast.id,
          meal: 'breakfast',
          entries: [
            _rich(id: 'e-coffee', label: 'Kaffee', kcal: 8, fibreG: null),
          ],
          updatedAt: breakfast.updatedAt,
        ),
      ),
      MealDraftSaveResult.saved,
    );
    expect(
      await repo.compareAndSaveMealDraft(
        expected: null,
        draft: _draft(id: 'd-clash', meal: 'dinner'),
      ),
      MealDraftSaveResult.conflict,
    );
    final dinnerHeld = (await repo.readMealDraft(_day, 'dinner'))!;
    expect(dinnerHeld.updatedAt, dinner.updatedAt);
    _expectRich(dinnerHeld.entries.single);
    final breakfastLive = (await repo.readMealDraft(_day, 'breakfast'))!;
    expect(breakfastLive.entries.single.kcal, 8);
    expect(breakfastLive.entries.single.label, 'Kaffee');
  });

  test('create with existing id in another slot conflicts and preserves both', () async {
    final repo = current();
    expect(
      await repo.compareAndSaveMealDraft(
        expected: null,
        draft: _draft(id: 'shared', meal: 'breakfast'),
      ),
      MealDraftSaveResult.saved,
    );
    final breakfast = (await repo.readMealDraft(_day, 'breakfast'))!;
    expect(
      await repo.compareAndSaveMealDraft(
        expected: null,
        draft: _draft(id: 'shared', meal: 'dinner'),
      ),
      MealDraftSaveResult.conflict,
    );
    final breakfastHeld = (await repo.readMealDraft(_day, 'breakfast'))!;
    expect(breakfastHeld.id, 'shared');
    expect(breakfastHeld.updatedAt, breakfast.updatedAt);
    _expectRich(breakfastHeld.entries.single);
    expect(await repo.readMealDraft(_day, 'dinner'), isNull);
  });

  test('id change colliding with another slot conflicts and preserves both', () async {
    final repo = current();
    expect(
      await repo.compareAndSaveMealDraft(
        expected: null,
        draft: _draft(id: 'd-breakfast', meal: 'breakfast'),
      ),
      MealDraftSaveResult.saved,
    );
    expect(
      await repo.compareAndSaveMealDraft(
        expected: null,
        draft: _draft(id: 'd-dinner', meal: 'dinner'),
      ),
      MealDraftSaveResult.saved,
    );
    final breakfast = (await repo.readMealDraft(_day, 'breakfast'))!;
    final dinner = (await repo.readMealDraft(_day, 'dinner'))!;
    expect(
      await repo.compareAndSaveMealDraft(
        expected: dinner,
        draft: _draft(
          id: 'd-breakfast',
          meal: 'dinner',
          entries: [_rich(kcal: 10)],
          updatedAt: dinner.updatedAt,
        ),
      ),
      MealDraftSaveResult.conflict,
    );
    final breakfastHeld = (await repo.readMealDraft(_day, 'breakfast'))!;
    final dinnerHeld = (await repo.readMealDraft(_day, 'dinner'))!;
    expect(breakfastHeld.id, 'd-breakfast');
    expect(breakfastHeld.updatedAt, breakfast.updatedAt);
    _expectRich(breakfastHeld.entries.single);
    expect(dinnerHeld.id, 'd-dinner');
    expect(dinnerHeld.updatedAt, dinner.updatedAt);
    _expectRich(dinnerHeld.entries.single);
  });

  test('successive writes advance revision; stale prior revision conflicts', () async {
    final repo = current();
    expect(
      await repo.compareAndSaveMealDraft(expected: null, draft: _draft()),
      MealDraftSaveResult.saved,
    );
    final v1 = (await repo.readMealDraft(_day, 'dinner'))!;
    expect(
      await repo.compareAndSaveMealDraft(
        expected: v1,
        draft: _draft(entries: [_rich(kcal: 310.1)], updatedAt: v1.updatedAt),
      ),
      MealDraftSaveResult.saved,
    );
    final v2 = (await repo.readMealDraft(_day, 'dinner'))!;
    expect(
      v2.updatedAt.millisecondsSinceEpoch,
      greaterThan(v1.updatedAt.millisecondsSinceEpoch),
    );
    expect(v2.entries.single.kcal, 310.1);
    expect(
      await repo.compareAndSaveMealDraft(
        expected: v2,
        draft: _draft(entries: [_rich(kcal: 320.2)], updatedAt: v2.updatedAt),
      ),
      MealDraftSaveResult.saved,
    );
    final v3 = (await repo.readMealDraft(_day, 'dinner'))!;
    expect(
      v3.updatedAt.millisecondsSinceEpoch,
      greaterThan(v2.updatedAt.millisecondsSinceEpoch),
    );
    expect(v3.entries.single.kcal, 320.2);
    expect(
      await repo.compareAndSaveMealDraft(
        expected: v1,
        draft: _draft(entries: [_rich(kcal: 1)], updatedAt: v1.updatedAt),
      ),
      MealDraftSaveResult.conflict,
    );
    expect(
      await repo.compareAndSaveMealDraft(
        expected: v2,
        draft: _draft(entries: [_rich(kcal: 1)], updatedAt: v2.updatedAt),
      ),
      MealDraftSaveResult.conflict,
    );
    final held = (await repo.readMealDraft(_day, 'dinner'))!;
    expect(held.updatedAt, v3.updatedAt);
    expect(held.entries.single.kcal, 320.2);
    expect(held.entries.single.quantity, 80.5);
    expect(held.entries.single.sourceCode, 'crowd-guess');
  });

  test('nonempty ids, unique entry ids, and nutrient rules stay enforced', () async {
    final repo = current();
    expect(
      () => repo.compareAndSaveMealDraft(
        expected: null,
        draft: _draft(id: ''),
      ),
      throwsArgumentError,
    );
    expect(
      () => repo.compareAndSaveMealDraft(
        expected: null,
        draft: _draft(id: '  '),
      ),
      throwsArgumentError,
    );
    expect(
      () => repo.compareAndSaveMealDraft(
        expected: null,
        draft: _draft(meal: ''),
      ),
      throwsArgumentError,
    );
    expect(
      () => repo.compareAndSaveMealDraft(
        expected: null,
        draft: _draft(
          entries: [
            _rich(id: 'dup'),
            _rich(id: 'dup', label: 'Tofu'),
          ],
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => repo.compareAndSaveMealDraft(
        expected: null,
        draft: _draft(entries: [_rich(kcal: -0.1)]),
      ),
      throwsArgumentError,
    );
    expect(await repo.readMealDraft(_day, 'dinner'), isNull);
  });

  test('commit still requires the exact retained draft and refuses replay', () async {
    final repo = current();
    expect(
      await repo.compareAndSaveMealDraft(expected: null, draft: _draft()),
      MealDraftSaveResult.saved,
    );
    final retained = (await repo.readMealDraft(_day, 'dinner'))!;
    expect(await repo.commitMealDraft(retained), MealDraftCommitResult.saved);
    expect(await repo.readMealDraft(_day, 'dinner'), isNull);
    expect(await repo.commitMealDraft(retained), MealDraftCommitResult.saved);
    final saved = (await repo.readFoodEntry('e-oats')).current!;
    expect(saved.quantity, 80.5);
    expect(saved.kcal, 299.46);
    expect(saved.ironMg, 3.7835);
    expect(saved.source, FoodSource.unknown);
    expect(saved.sourceCode, 'crowd-guess');
    expect(saved.note, 'pack');
    expect((await repo.removeFoodEntry(saved)).saved, isTrue);
    expect(await repo.commitMealDraft(retained), MealDraftCommitResult.conflict);
    expect((await repo.readFoodEntry('e-oats')).missing, isTrue);

    expect(
      await repo.compareAndSaveMealDraft(
        expected: null,
        draft: _draft(id: 'd2', entries: [_rich(id: 'e2')]),
      ),
      MealDraftSaveResult.saved,
    );
    final second = (await repo.readMealDraft(_day, 'dinner'))!;
    expect(
      await repo.compareAndSaveMealDraft(
        expected: second,
        draft: _draft(
          id: second.id,
          entries: [_rich(id: 'e2', kcal: 250)],
          updatedAt: second.updatedAt,
        ),
      ),
      MealDraftSaveResult.saved,
    );
    expect(await repo.commitMealDraft(second), MealDraftCommitResult.conflict);
    expect(await repo.readMealDraft(_day, 'dinner'), isNotNull);
    expect((await repo.readFoodEntry('e2')).missing, isTrue);

    final live = (await repo.readMealDraft(_day, 'dinner'))!;
    await repo.discardMealDraft(live.id);
    expect(await repo.readMealDraft(_day, 'dinner'), isNull);
    expect(await repo.commitMealDraft(live), MealDraftCommitResult.conflict);
  });

  if (!sqlite) {
    test('concurrent edits against one snapshot: one saved, one conflict', () async {
      final repo = current();
      expect(
        await repo.compareAndSaveMealDraft(expected: null, draft: _draft()),
        MealDraftSaveResult.saved,
      );
      final first = (await repo.readMealDraft(_day, 'dinner'))!;
      final results = await Future.wait([
        repo.compareAndSaveMealDraft(
          expected: first,
          draft: _draft(
            entries: [_rich(kcal: 310.1)],
            updatedAt: first.updatedAt,
          ),
        ),
        repo.compareAndSaveMealDraft(
          expected: first,
          draft: _draft(
            entries: [_rich(kcal: 410.2)],
            updatedAt: first.updatedAt,
          ),
        ),
      ]);
      expect(results.where((r) => r == MealDraftSaveResult.saved).length, 1);
      expect(
        results.where((r) => r == MealDraftSaveResult.conflict).length,
        1,
      );
      final live = (await repo.readMealDraft(_day, 'dinner'))!;
      expect(live.entries.single.kcal, anyOf(310.1, 410.2));
      expect(
        live.updatedAt.millisecondsSinceEpoch,
        greaterThan(first.updatedAt.millisecondsSinceEpoch),
      );
    });
  }
}
