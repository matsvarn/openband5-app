import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _day = '2026-09-15';

FoodEntry _oats({
  String id = 'saved-oats',
  int? atTs,
  double? quantity,
  double kcal = 380,
  FoodSource source = FoodSource.manual,
  String? sourceCode,
  bool confirmed = true,
  int? createdAt = 1_000,
  int? updatedAt = 1_000,
}) => FoodEntry(
  id: id,
  date: _day,
  meal: 'breakfast',
  label: 'Haferflocken mit Milch',
  atTs: atTs,
  foodKey: 'oats',
  quantity: quantity,
  unit: 'g',
  kcal: kcal,
  proteinG: 18,
  carbsG: 56,
  fatG: 12,
  fibreG: 8.1,
  sugarG: 0.9,
  satFatG: 1.1,
  sodiumMg: 4,
  ironMg: 3.4,
  calciumMg: 42,
  source: source,
  sourceCode: sourceCode ?? source.name,
  confirmed: confirmed,
  note: 'pack',
  createdAt: createdAt,
  updatedAt: updatedAt,
);

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('synthetic', () {
    late SyntheticOpenBandRepository repo;
    setUp(() => repo = _synthetic());
    _lifecycle(() => repo, sqlite: false);
  });

  group('SQLite', () {
    late AppState app;
    late LocalOpenBandRepository repo;
    const dbName = 'openband_meal_lifecycle_test.db';

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

    _lifecycle(() => repo, sqlite: true);

    test('reopen keeps full snapshot, unknown source, and null consumed-at', () async {
      final saved = await repo.restoreFoodEntry(
        _oats(source: FoodSource.unknown, sourceCode: 'crowd-guess', quantity: 80.5),
      );
      expect(saved.saved, isTrue);
      await LocalDb.close();
      repo = LocalOpenBandRepository(app);
      final back = await repo.readFoodEntry('saved-oats');
      expect(back.saved, isTrue);
      expect(back.current!.quantity, 80.5);
      expect(back.current!.kcal, 380);
      expect(back.current!.proteinG, 18);
      expect(back.current!.ironMg, 3.4);
      expect(back.current!.calciumMg, 42);
      expect(back.current!.source, FoodSource.unknown);
      expect(back.current!.sourceCode, 'crowd-guess');
      expect(back.current!.atTs, isNull);
      expect(back.current!.createdAt, 1_000);
      expect(back.current!.note, 'pack');
    });

    test('concurrent saves against one snapshot: one saved, one conflict', () async {
      expect((await repo.restoreFoodEntry(_oats())).saved, isTrue);
      final first = (await repo.readFoodEntry('saved-oats')).current!;
      final results = await Future.wait([
        repo.saveFoodEntry(
          first,
          _oats(
            kcal: 390,
            createdAt: first.createdAt,
            updatedAt: first.updatedAt,
          ),
        ),
        repo.saveFoodEntry(
          first,
          _oats(
            kcal: 410,
            createdAt: first.createdAt,
            updatedAt: first.updatedAt,
          ),
        ),
      ]);
      expect(results.where((r) => r.saved).length, 1);
      expect(results.where((r) => r.conflict).length, 1);
      final live = (await repo.readFoodEntry('saved-oats')).current!;
      expect(live.kcal, anyOf(390, 410));
      expect(results.firstWhere((r) => r.conflict).current!.kcal, live.kcal);
    });

    test('raw old draft JSON commits from read without a second save', () async {
      await LocalDb.putOpenBandMealDraft({
        'draft_id': 'raw-old',
        'day_id': _day,
        'meal': 'dinner',
        'entries_json': jsonEncode([
          {
            'id': 'raw-rice',
            'label': 'Reis',
            'quantity': 180,
            'unit': 'g',
            'kcal': 300,
            'proteinG': null,
            'carbsG': 65,
            'fatG': null,
            'foodKey': 'rice',
          },
        ]),
        'updated_at': 1,
      });
      final retained = await repo.readMealDraft(_day, 'dinner');
      expect(retained, isNotNull);
      expect(retained!.id, 'raw-old');
      expect(retained.entries.single.source, isNull);
      expect(retained.entries.single.fibreG, isNull);
      expect(await repo.commitMealDraft(retained), MealDraftCommitResult.saved);
      final saved = (await repo.readFoodEntry('raw-rice')).current!;
      expect(saved.source, FoodSource.manual);
      expect(saved.confirmed, isTrue);
      expect(saved.kcal, 300);
      expect(saved.fibreG, isNull);
      expect(await repo.readMealDraft(_day, 'dinner'), isNull);
    });
  });
}

void _lifecycle(
  OpenBandRepository Function() current, {
  required bool sqlite,
}) {
  test('full snapshot survives restore, nutrient edit, delete, restore', () async {
    final repo = current();
    final original = _oats(quantity: 80.5);
    expect((await repo.restoreFoodEntry(original)).saved, isTrue);
    final read = await repo.readFoodEntry(original.id);
    expect(read.current!.atTs, isNull);
    expect(read.current!.quantity, 80.5);
    expect(read.current!.fibreG, 8.1);
    expect(read.current!.sourceCode, 'manual');

    await Future<void>.delayed(const Duration(milliseconds: 5));
    final edited = _oats(
      quantity: 80.5,
      kcal: 400,
      createdAt: read.current!.createdAt,
      updatedAt: read.current!.updatedAt,
    );
    final saved = await repo.saveFoodEntry(read.current!, edited);
    expect(saved.saved, isTrue);
    expect(saved.current!.kcal, 400);
    expect(saved.current!.atTs, isNull);
    expect(saved.current!.quantity, 80.5);
    expect(saved.current!.createdAt, original.createdAt);
    expect(saved.current!.updatedAt, greaterThan(original.updatedAt!));

    final removed = await repo.removeFoodEntry(saved.current!);
    expect(removed.saved, isTrue);
    expect((await repo.readFoodEntry(original.id)).missing, isTrue);

    final restored = await repo.restoreFoodEntry(saved.current!);
    expect(restored.saved, isTrue);
    expect(restored.current!.kcal, 400);
    expect(restored.current!.createdAt, saved.current!.createdAt);
    expect(restored.current!.updatedAt, saved.current!.updatedAt);
    expect(restored.current!.atTs, isNull);
  });

  test('stale save and delete do not overwrite an intervening edit', () async {
    final repo = current();
    expect((await repo.restoreFoodEntry(_oats())).saved, isTrue);
    final first = (await repo.readFoodEntry('saved-oats')).current!;
    final second = await repo.saveFoodEntry(
      first,
      _oats(kcal: 390, createdAt: first.createdAt, updatedAt: first.updatedAt),
    );
    expect(second.saved, isTrue);

    final staleSave = await repo.saveFoodEntry(
      first,
      _oats(kcal: 410, createdAt: first.createdAt, updatedAt: first.updatedAt),
    );
    expect(staleSave.conflict, isTrue);
    expect(staleSave.current!.kcal, 390);

    final staleDelete = await repo.removeFoodEntry(first);
    expect(staleDelete.conflict, isTrue);
    expect(staleDelete.current!.kcal, 390);
    expect((await repo.readFoodEntry('saved-oats')).current!.kcal, 390);
  });

  test('restore is insert, equal no-op, or conflict — never replace', () async {
    final repo = current();
    final snapshot = _oats();
    expect((await repo.restoreFoodEntry(snapshot)).saved, isTrue);
    final equal = await repo.restoreFoodEntry(snapshot);
    expect(equal.saved, isTrue);
    expect(equal.current!.updatedAt, snapshot.updatedAt);

    await Future<void>.delayed(const Duration(milliseconds: 5));
    final live = (await repo.readFoodEntry(snapshot.id)).current!;
    final changed = await repo.saveFoodEntry(
      live,
      _oats(kcal: 410, createdAt: live.createdAt, updatedAt: live.updatedAt),
    );
    expect(changed.saved, isTrue);

    final clash = await repo.restoreFoodEntry(snapshot);
    expect(clash.conflict, isTrue);
    expect(clash.current!.kcal, 410);

    expect((await repo.removeFoodEntry(changed.current!)).saved, isTrue);
    final missing = await repo.restoreFoodEntry(snapshot);
    expect(missing.saved, isTrue);
    expect(missing.current!.kcal, 380);
    expect(missing.current!.createdAt, snapshot.createdAt);
  });

  test('draft commit preserves nutrients/source and rolls back on id collision', () async {
    final repo = current();
    final prior = _oats(id: 'e2', kcal: 180, createdAt: 50, updatedAt: 50);
    expect((await repo.restoreFoodEntry(prior)).saved, isTrue);
    final draft = MealDraft(
      id: 'd1',
      day: _day,
      meal: 'dinner',
      entries: [
        const MealDraftEntry(
          id: 'e1',
          label: 'Reis',
          kcal: 300,
          carbsG: 65,
          fibreG: 1.2,
          source: FoodSource.barcode,
          sourceCode: 'barcode',
          confirmed: true,
        ),
        const MealDraftEntry(id: 'e2', label: 'Tofu', kcal: 200, proteinG: 18),
      ],
      updatedAt: DateTime(2026, 9, 15, 19),
    );
    await repo.saveMealDraft(draft);
    expect((await repo.readFoodEntry('e2')).current?.kcal, 180);
    final collided = await repo.commitMealDraft(draft);
    expect(collided, MealDraftCommitResult.conflict);
    expect((await repo.readFoodEntry('e2')).current!.kcal, 180);
    expect(await repo.readMealDraft(_day, 'dinner'), isNotNull);
    expect((await repo.readFoodEntry('e1')).missing, isTrue);

    final clean = MealDraft(
      id: 'd1',
      day: _day,
      meal: 'dinner',
      entries: const [
        MealDraftEntry(
          id: 'e1',
          label: 'Reis',
          quantity: 180.25,
          kcal: 300,
          carbsG: 65,
          fibreG: 1.2,
          ironMg: 0.8,
          source: FoodSource.barcode,
          sourceCode: 'barcode',
          confirmed: true,
        ),
      ],
      updatedAt: DateTime(2026, 9, 15, 19),
    );
    await repo.saveMealDraft(clean);
    expect(await repo.commitMealDraft(clean), MealDraftCommitResult.saved);
    final rice = (await repo.readFoodEntry('e1')).current!;
    expect(rice.quantity, 180.25);
    expect(rice.fibreG, 1.2);
    expect(rice.ironMg, 0.8);
    expect(rice.source, FoodSource.barcode);
    expect(rice.atTs, isNull);
    expect(await repo.readMealDraft(_day, 'dinner'), isNull);

    expect(await repo.commitMealDraft(clean), MealDraftCommitResult.saved);
    final replay = (await repo.readFoodEntry('e1')).current!;
    expect(replay.createdAt, rice.createdAt);
    expect(replay.updatedAt, rice.updatedAt);
  });

  test('replay after delete does not resurrect; never-saved draft cannot insert', () async {
    final repo = current();
    final draft = MealDraft(
      id: 'replay-d',
      day: _day,
      meal: 'dinner',
      entries: const [
        MealDraftEntry(
          id: 'keep-rice',
          label: 'Reis',
          kcal: 300,
          carbsG: 65,
          source: FoodSource.barcode,
          sourceCode: 'barcode',
          confirmed: true,
        ),
        MealDraftEntry(
          id: 'gone-tofu',
          label: 'Tofu',
          kcal: 180,
          proteinG: 18,
          source: FoodSource.manual,
          sourceCode: 'manual',
          confirmed: true,
        ),
      ],
      updatedAt: DateTime(2026, 9, 15, 19),
    );
    await repo.saveMealDraft(draft);
    expect(await repo.commitMealDraft(draft), MealDraftCommitResult.saved);
    final kept = (await repo.readFoodEntry('keep-rice')).current!;
    final gone = (await repo.readFoodEntry('gone-tofu')).current!;
    expect((await repo.removeFoodEntry(gone)).saved, isTrue);
    final replayed = await repo.commitMealDraft(draft);
    expect(replayed, MealDraftCommitResult.conflict);
    expect((await repo.readFoodEntry('gone-tofu')).missing, isTrue);
    final still = (await repo.readFoodEntry('keep-rice')).current!;
    expect(still.kcal, 300);
    expect(still.createdAt, kept.createdAt);
    expect(still.updatedAt, kept.updatedAt);
    expect(await repo.readMealDraft(_day, 'dinner'), isNull);

    final ghost = MealDraft(
      id: 'ghost',
      day: _day,
      meal: 'snack',
      entries: const [
        MealDraftEntry(id: 'ghost-1', label: 'Ghost', kcal: 10),
      ],
      updatedAt: DateTime(2026, 9, 15, 20),
    );
    expect(await repo.commitMealDraft(ghost), MealDraftCommitResult.conflict);
    expect((await repo.readFoodEntry('ghost-1')).missing, isTrue);
    expect(
      (await repo.readFoodEntry('keep-rice')).current!.updatedAt,
      kept.updatedAt,
    );
  });

  test('old draft JSON commits as UI-manual without fabricating nutrients', () async {
    final repo = current();
    final old = MealDraftEntry.fromJson({
      'id': 'legacy-rice',
      'label': 'Reis',
      'quantity': 180,
      'unit': 'g',
      'kcal': 300,
      'proteinG': null,
      'carbsG': 65,
      'fatG': null,
      'foodKey': 'rice',
    });
    final draft = MealDraft(
      id: 'legacy',
      day: _day,
      meal: 'dinner',
      entries: [old],
      updatedAt: DateTime(2026, 9, 15, 19),
    );
    await repo.saveMealDraft(draft);
    final retained = await repo.readMealDraft(_day, 'dinner');
    expect(retained, isNotNull);
    expect(retained!.entries.single.source, isNull);
    expect(retained.entries.single.fibreG, isNull);
    expect(await repo.commitMealDraft(retained), MealDraftCommitResult.saved);
    final saved = (await repo.readFoodEntry('legacy-rice')).current!;
    expect(saved.source, FoodSource.manual);
    expect(saved.confirmed, isTrue);
    expect(saved.fibreG, isNull);
    expect(saved.atTs, isNull);
  });

  test('photo unconfirmed is stripped; confirmed photo keeps numbers', () async {
    final repo = current();
    final raw = MealDraft(
      id: 'photo',
      day: _day,
      meal: 'lunch',
      entries: const [
        MealDraftEntry(
          id: 'photo-1',
          label: 'Rice, chicken',
          kcal: 720,
          proteinG: 40,
          source: FoodSource.photo,
          sourceCode: 'photo',
          confirmed: false,
        ),
      ],
      updatedAt: DateTime(2026, 9, 15, 12),
    );
    await repo.saveMealDraft(raw);
    expect(await repo.commitMealDraft(raw), MealDraftCommitResult.saved);
    final stripped = (await repo.readFoodEntry('photo-1')).current!;
    expect(stripped.source, FoodSource.photo);
    expect(stripped.kcal, isNull);
    expect(stripped.proteinG, isNull);

    final ok = MealDraft(
      id: 'photo-ok',
      day: _day,
      meal: 'lunch',
      entries: const [
        MealDraftEntry(
          id: 'photo-2',
          label: 'Rice, chicken',
          kcal: 520,
          proteinG: 38,
          source: FoodSource.photo,
          sourceCode: 'photo',
          confirmed: true,
        ),
      ],
      updatedAt: DateTime(2026, 9, 15, 12),
    );
    await repo.saveMealDraft(ok);
    expect(await repo.commitMealDraft(ok), MealDraftCommitResult.saved);
    final kept = (await repo.readFoodEntry('photo-2')).current!;
    expect(kept.kcal, 520);
    expect(kept.proteinG, 38);
  });

  test('known photo plus conflicting manual wire strips on original commit', () async {
    final repo = current();
    const entry = MealDraftEntry(
      id: 'photo-mismatch',
      label: 'Rice',
      quantity: 80,
      kcal: 123,
      proteinG: 10,
      source: FoodSource.photo,
      sourceCode: 'manual',
      confirmed: false,
    );
    final draft = MealDraft(
      id: 'pm',
      day: _day,
      meal: 'lunch',
      entries: const [entry],
      updatedAt: DateTime(2026, 9, 15, 12),
    );
    await repo.saveMealDraft(draft);
    final retained = await repo.readMealDraft(_day, 'lunch');
    expect(retained, isNotNull);
    expect(retained!.entries.single.source, FoodSource.photo);
    expect(retained.entries.single.sourceCode, 'photo');
    expect(await repo.commitMealDraft(draft), MealDraftCommitResult.saved);
    final saved = (await repo.readFoodEntry('photo-mismatch')).current!;
    expect(saved.source, FoodSource.photo);
    expect(saved.sourceCode, 'photo');
    expect(saved.kcal, isNull);
    expect(saved.proteinG, isNull);
    expect(saved.quantity, isNull);
  });

  test('mismatched pair reads canonical wire and roundtripped commit succeeds', () async {
    final repo = current();
    const entry = MealDraftEntry(
      id: 'rt-photo',
      label: 'Rice',
      quantity: 80,
      kcal: 123,
      proteinG: 10,
      source: FoodSource.photo,
      sourceCode: 'manual',
      confirmed: false,
    );
    final draft = MealDraft(
      id: 'rt',
      day: _day,
      meal: 'lunch',
      entries: const [entry],
      updatedAt: DateTime(2026, 9, 15, 12),
    );
    await repo.saveMealDraft(draft);
    final retained = await repo.readMealDraft(_day, 'lunch');
    expect(retained, isNotNull);
    expect(retained!.entries.single.source, FoodSource.photo);
    expect(retained.entries.single.sourceCode, 'photo');
    expect(retained.entries.single.quantity, 80);
    expect(await repo.commitMealDraft(retained), MealDraftCommitResult.saved);
    expect(await repo.commitMealDraft(draft), MealDraftCommitResult.saved);
    final saved = (await repo.readFoodEntry('rt-photo')).current!;
    expect(saved.source, FoodSource.photo);
    expect(saved.sourceCode, 'photo');
    expect(saved.kcal, isNull);
    expect(saved.quantity, isNull);
  });

  test('known manual plus conflicting photo wire commits as manual', () async {
    final repo = current();
    const entry = MealDraftEntry(
      id: 'manual-mismatch',
      label: 'Rice',
      kcal: 123,
      source: FoodSource.manual,
      sourceCode: 'photo',
      confirmed: false,
    );
    final draft = MealDraft(
      id: 'mm',
      day: _day,
      meal: 'lunch',
      entries: const [entry],
      updatedAt: DateTime(2026, 9, 15, 12),
    );
    await repo.saveMealDraft(draft);
    expect(
      (await repo.readMealDraft(_day, 'lunch'))!.entries.single.source,
      FoodSource.manual,
    );
    expect(await repo.commitMealDraft(draft), MealDraftCommitResult.saved);
    final saved = (await repo.readFoodEntry('manual-mismatch')).current!;
    expect(saved.source, FoodSource.manual);
    expect(saved.sourceCode, 'manual');
    expect(saved.kcal, 123);
  });

  test('search portion keeps definition source and does not invent kcal', () async {
    final repo = current();
    if (sqlite) {
      final db = await LocalDb.instance;
      await NutritionDb.putFoodDef(db, {
        'key': 'oats',
        'label': 'Haferflocken',
        'brand': '',
        'serving_g': 60,
        'kcal_100': 372,
        'protein_g_100': 13.5,
        'fibre_g_100': 10.6,
        'iron_mg_100': 4.7,
        'source': 'verified',
      });
    }
    final hits = await repo.searchFoods('hafer');
    expect(hits, isNotEmpty);
    final oats = hits.firstWhere((h) => h.key == 'oats');
    expect(oats.fibreG100, 10.6);
    expect(oats.ironMg100, 4.7);
    expect(oats.source, FoodSource.verified);
    final portion = oats.portion('p-oats', 80);
    expect(portion.kcal, closeTo(297.6, 1e-9));
    expect(portion.sugarG, isNull);
    expect(portion.source, FoodSource.verified);
    final draft = MealDraft(
      id: 'portion',
      day: _day,
      meal: 'breakfast',
      entries: [portion],
      updatedAt: DateTime(2026, 9, 15, 8),
    );
    await repo.saveMealDraft(draft);
    expect(await repo.commitMealDraft(draft), MealDraftCommitResult.saved);
    final saved = (await repo.readFoodEntry('p-oats')).current!;
    expect(saved.source, FoodSource.verified);
    expect(saved.fibreG, closeTo(8.48, 1e-9));
    expect(saved.sugarG, isNull);
  });

  test('DST-local seven-day window keeps missing, zero, and partial days', () async {
    final repo = current();
    Future<void> put(FoodEntry e) async {
      expect((await repo.restoreFoodEntry(e)).saved, isTrue);
    }

    await put(
      const FoodEntry(
        id: 'd25',
        date: '2026-03-25',
        meal: 'lunch',
        label: 'A',
        kcal: 420,
        createdAt: 1,
        updatedAt: 1,
      ),
    );
    await put(
      const FoodEntry(
        id: 'd29a',
        date: '2026-03-29',
        meal: 'lunch',
        label: 'B',
        kcal: 780,
        createdAt: 2,
        updatedAt: 2,
      ),
    );
    await put(
      const FoodEntry(
        id: 'd29b',
        date: '2026-03-29',
        meal: 'dinner',
        label: 'C',
        createdAt: 3,
        updatedAt: 3,
      ),
    );
    await put(
      const FoodEntry(
        id: 'd31',
        date: '2026-03-31',
        meal: 'lunch',
        label: 'Water',
        kcal: 0,
        createdAt: 4,
        updatedAt: 4,
      ),
    );
    final window = await repo.readNutritionWindow('2026-03-31');
    expect(window.days.map((d) => d.date), [
      '2026-03-25',
      '2026-03-26',
      '2026-03-27',
      '2026-03-28',
      '2026-03-29',
      '2026-03-30',
      '2026-03-31',
    ]);
    expect(window.days[0].kcal.value, 420);
    expect(window.days[1].entries, isEmpty);
    expect(window.days[1].kcal.value, isNull);
    expect(window.days[4].kcal.value, 780);
    expect(window.days[4].kcal.unknown, 1);
    expect(window.days[5].kcal.value, isNull);
    expect(window.days[6].kcal.value, 0);
    expect(window.days[6].kcal.known, 1);
  });

  test('readMeals orders null consumed-at first then atTs, not mixed-unit coalesce', () async {
    final repo = current();
    const day = '2026-09-16';
    Future<void> put(FoodEntry e) async {
      expect((await repo.restoreFoodEntry(e)).saved, isTrue);
    }

    await put(
      const FoodEntry(
        id: 'late-eaten',
        date: day,
        meal: 'lunch',
        label: 'Reis',
        atTs: 200,
        kcal: 300,
        createdAt: 2,
        updatedAt: 2,
      ),
    );
    await put(
      const FoodEntry(
        id: 'ledger-only',
        date: day,
        meal: 'lunch',
        label: 'Water',
        createdAt: 9000,
        updatedAt: 9000,
      ),
    );
    await put(
      const FoodEntry(
        id: 'early-eaten',
        date: day,
        meal: 'lunch',
        label: 'Oats',
        atTs: 100,
        kcal: 380,
        createdAt: 8000,
        updatedAt: 8000,
      ),
    );
    final meals = await repo.readMeals(day);
    expect(meals.entries.map((e) => e.id), [
      'ledger-only',
      'early-eaten',
      'late-eaten',
    ]);
    expect(meals.entries[0].atTs, isNull);
    expect(meals.entries[1].atTs, 100);
    expect(meals.entries[2].atTs, 200);
  });

  test('recent identity follows foodKey then label/source, not lexical id', () async {
    final repo = current();
    Future<void> put(FoodEntry e) async {
      expect((await repo.restoreFoodEntry(e)).saved, isTrue);
    }

    await put(
      const FoodEntry(
        id: 'zzz',
        date: _day,
        meal: 'lunch',
        label: 'Oats',
        foodKey: 'oats',
        createdAt: 100,
        updatedAt: 100,
      ),
    );
    await put(
      const FoodEntry(
        id: 'aaa',
        date: _day,
        meal: 'lunch',
        label: 'Oats',
        foodKey: 'oats',
        createdAt: 200,
        updatedAt: 200,
      ),
    );
    await put(
      const FoodEntry(
        id: 'm',
        date: _day,
        meal: 'lunch',
        label: 'Milk',
        foodKey: 'milk',
        createdAt: 50,
        updatedAt: 50,
      ),
    );
    await put(
      const FoodEntry(
        id: 'n',
        date: _day,
        meal: 'lunch',
        label: 'Nuts',
        foodKey: 'nuts',
        createdAt: 50,
        updatedAt: 50,
      ),
    );
    await put(
      const FoodEntry(
        id: 'bare',
        date: _day,
        meal: 'lunch',
        label: 'Oats',
        createdAt: 300,
        updatedAt: 300,
      ),
    );
    final recents = await repo.readRecentFoods();
    expect(recents.map((e) => e.id), containsAllInOrder(['bare', 'aaa']));
    expect(recents.where((e) => e.foodKey == 'oats').map((e) => e.id), ['aaa']);
    expect(recents.map((e) => e.id).where((id) => id == 'm' || id == 'n'), ['m', 'n']);
  });

  test('read missing is conflict, write exceptions stay distinct', () async {
    final repo = current();
    expect((await repo.readFoodEntry('nope')).missing, isTrue);
    expect(
      () => repo.saveFoodEntry(
        _oats(),
        const FoodEntry(
          id: 'saved-oats',
          date: '2026-02-30',
          meal: 'breakfast',
          label: 'X',
        ),
      ),
      throwsArgumentError,
    );
    if (!sqlite) {
      final synthetic = repo as SyntheticOpenBandRepository;
      synthetic.failFoodRead = true;
      await expectLater(repo.readFoodEntry('saved-oats'), throwsStateError);
      synthetic.failFoodRead = false;
      synthetic.failFoodWrite = true;
      await expectLater(repo.restoreFoodEntry(_oats()), throwsStateError);
    }
  });

  test('same-stamp different-nutrient CAS still conflicts', () async {
    final repo = current();
    expect(
      (await repo.restoreFoodEntry(_oats(kcal: 380, createdAt: 50, updatedAt: 50)))
          .saved,
      isTrue,
    );
    final other = _oats(kcal: 410, createdAt: 50, updatedAt: 50);
    final staleSave = await repo.saveFoodEntry(
      other,
      _oats(kcal: 500, createdAt: 50, updatedAt: 50),
    );
    expect(staleSave.conflict, isTrue);
    expect(staleSave.current!.kcal, 380);
    final staleDelete = await repo.removeFoodEntry(other);
    expect(staleDelete.conflict, isTrue);
    expect((await repo.readFoodEntry('saved-oats')).current!.kcal, 380);
    expect((await repo.readFoodEntry('saved-oats')).current!.updatedAt, 50);
  });

  test('save and restore strip unconfirmed photo numbers', () async {
    final repo = current();
    const unconfirmed = FoodEntry(
      id: 'photo-direct',
      date: _day,
      meal: 'lunch',
      label: 'Rice, chicken',
      quantity: 300,
      kcal: 720,
      proteinG: 40,
      source: FoodSource.photo,
      sourceCode: 'photo',
      confirmed: false,
      createdAt: 9,
      updatedAt: 9,
    );
    expect((await repo.restoreFoodEntry(unconfirmed)).saved, isTrue);
    final restored = (await repo.readFoodEntry('photo-direct')).current!;
    expect(restored.source, FoodSource.photo);
    expect(restored.kcal, isNull);
    expect(restored.proteinG, isNull);
    expect(restored.quantity, isNull);
    expect(restored.createdAt, 9);
    expect(restored.updatedAt, 9);

    const confirmed = FoodEntry(
      id: 'photo-edit',
      date: _day,
      meal: 'lunch',
      label: 'Rice, chicken',
      kcal: 520,
      proteinG: 38,
      source: FoodSource.photo,
      sourceCode: 'photo',
      confirmed: true,
      createdAt: 11,
      updatedAt: 11,
    );
    expect((await repo.restoreFoodEntry(confirmed)).saved, isTrue);
    final live = (await repo.readFoodEntry('photo-edit')).current!;
    final saved = await repo.saveFoodEntry(
      live,
      FoodEntry(
        id: live.id,
        date: live.date,
        meal: live.meal,
        label: live.label,
        kcal: 720,
        proteinG: 40,
        source: FoodSource.photo,
        sourceCode: 'photo',
        confirmed: false,
        createdAt: live.createdAt,
        updatedAt: live.updatedAt,
      ),
    );
    expect(saved.saved, isTrue);
    expect(saved.current!.source, FoodSource.photo);
    expect(saved.current!.kcal, isNull);
    expect(saved.current!.proteinG, isNull);
    expect(saved.current!.createdAt, 11);
  });

  test('unknown-source draft commit keeps exact wire', () async {
    final repo = current();
    final draft = MealDraft(
      id: 'unk',
      day: _day,
      meal: 'lunch',
      entries: const [
        MealDraftEntry(
          id: 'unk-1',
          label: 'Guess',
          kcal: 200,
          source: FoodSource.unknown,
          sourceCode: 'crowd-guess',
          confirmed: true,
        ),
      ],
      updatedAt: DateTime(2026, 9, 15, 12),
    );
    await repo.saveMealDraft(draft);
    expect(await repo.commitMealDraft(draft), MealDraftCommitResult.saved);
    final saved = (await repo.readFoodEntry('unk-1')).current!;
    expect(saved.source, FoodSource.unknown);
    expect(saved.sourceCode, 'crowd-guess');
    expect(saved.kcal, 200);
    expect(saved.atTs, isNull);
  });

  test('discard then stale commit refuses insert', () async {
    final repo = current();
    final draft = MealDraft(
      id: 'disc',
      day: _day,
      meal: 'dinner',
      entries: const [
        MealDraftEntry(id: 'disc-1', label: 'Reis', kcal: 10),
      ],
      updatedAt: DateTime(2026, 9, 15, 19),
    );
    await repo.saveMealDraft(draft);
    await repo.discardMealDraft(draft.id);
    expect(await repo.readMealDraft(_day, 'dinner'), isNull);
    expect(await repo.commitMealDraft(draft), MealDraftCommitResult.conflict);
    expect((await repo.readFoodEntry('disc-1')).missing, isTrue);
  });

  test('empty draft id is refused on save and commit', () async {
    final repo = current();
    final empty = MealDraft(
      id: '',
      day: _day,
      meal: 'dinner',
      entries: const [
        MealDraftEntry(id: 'empty-id-e', label: 'X', kcal: 1),
      ],
      updatedAt: DateTime(2026, 9, 15, 19),
    );
    expect(() => repo.saveMealDraft(empty), throwsArgumentError);
    expect(() => repo.commitMealDraft(empty), throwsArgumentError);
    expect(
      () => repo.saveMealDraft(
        MealDraft(
          id: '  ',
          day: _day,
          meal: 'dinner',
          entries: empty.entries,
          updatedAt: empty.updatedAt,
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => repo.commitMealDraft(
        MealDraft(
          id: '  ',
          day: _day,
          meal: 'dinner',
          entries: empty.entries,
          updatedAt: empty.updatedAt,
        ),
      ),
      throwsArgumentError,
    );
    expect((await repo.readFoodEntry('empty-id-e')).missing, isTrue);
  });
}
