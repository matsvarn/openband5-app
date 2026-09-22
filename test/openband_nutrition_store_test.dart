// NutritionDb ledger integrity: creation stamps, consumed-at honesty,
// and recent() identity. Isolated SQLite — no LocalDb, no rollup.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

FoodEntry _entry({
  required String id,
  String date = '2026-09-15',
  String meal = 'lunch',
  required String label,
  int? atTs,
  String? foodKey,
  double? quantity,
  String unit = 'g',
  double? kcal,
  double? proteinG,
  double? carbsG,
  double? fatG,
  double? fibreG,
  double? sugarG,
  double? satFatG,
  double? sodiumMg,
  double? ironMg,
  double? calciumMg,
  FoodSource source = FoodSource.manual,
  bool confirmed = false,
  String note = '',
  int? createdAt,
  int? updatedAt,
}) => FoodEntry(
  id: id,
  date: date,
  meal: meal,
  label: label,
  atTs: atTs,
  foodKey: foodKey,
  quantity: quantity,
  unit: unit,
  kcal: kcal,
  proteinG: proteinG,
  carbsG: carbsG,
  fatG: fatG,
  fibreG: fibreG,
  sugarG: sugarG,
  satFatG: satFatG,
  sodiumMg: sodiumMg,
  ironMg: ironMg,
  calciumMg: calciumMg,
  source: source,
  confirmed: confirmed,
  note: note,
  createdAt: createdAt,
  updatedAt: updatedAt,
);

Future<void> _seed(
  Database db, {
  required String id,
  required String label,
  String date = '2026-09-15',
  String meal = 'lunch',
  int? atTs,
  String? foodKey,
  String source = 'manual',
  required int createdAt,
  int? updatedAt,
}) => db.insert('food_entry', {
  'id': id,
  'date': date,
  'at_ts': atTs,
  'meal': meal,
  'food_key': foodKey,
  'label': label,
  'unit': 'g',
  'source': source,
  'confirmed': 0,
  'note': '',
  'created_at': createdAt,
  'updated_at': updatedAt ?? createdAt,
});

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (d, _) => createNutritionTables(d),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('put keeps created_at and sets a write timestamp', () async {
    await NutritionDb.put(
      db,
      _entry(id: 'e1', label: 'Oats', kcal: 150, confirmed: true),
    );
    final first = (await NutritionDb.entriesForDay(db, '2026-09-15')).single;
    expect(first.createdAt, isNotNull);
    expect(first.updatedAt, first.createdAt);

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await NutritionDb.put(
      db,
      _entry(id: 'e1', label: 'Oats with milk', kcal: 220, confirmed: true),
    );
    final edited = (await NutritionDb.entriesForDay(db, '2026-09-15')).single;
    expect(edited.label, 'Oats with milk');
    expect(edited.kcal, 220);
    expect(edited.createdAt, first.createdAt);
    expect(edited.updatedAt, greaterThan(first.updatedAt!));
  });

  test('putFoodDef keeps created_at across a REPLACE', () async {
    await NutritionDb.putFoodDef(db, {
      'key': 'oats',
      'label': 'Oats',
      'brand': 'A',
      'kcal_100': 372,
      'protein_g_100': 13.5,
      'iron_mg_100': 4.7,
      'source': 'barcode',
    });
    final created =
        (await NutritionDb.foodDef(db, 'oats'))!['created_at'] as int;

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await NutritionDb.putFoodDef(db, {
      'key': 'oats',
      'label': 'Rolled oats',
      'brand': 'B',
      'kcal_100': 370,
      'protein_g_100': 13.5,
      'iron_mg_100': 4.7,
      'created_at': created + 99_000,
      'source': 'barcode',
    });
    final back = (await NutritionDb.foodDef(db, 'oats'))!;
    expect(back['label'], 'Rolled oats');
    expect(back['created_at'], created);
    expect(back['iron_mg_100'], 4.7);
  });

  test('putFoodDef without a label fails and writes no row', () async {
    await expectLater(
      NutritionDb.putFoodDef(db, {
        'key': 'nolabel',
        'kcal_100': 100,
      }),
      throwsA(isA<DatabaseException>()),
    );
    expect(await NutritionDb.foodDef(db, 'nolabel'), isNull);
    expect(await db.query('food_def'), isEmpty);
  });

  test(
    'saved entry round-trips null consumed-at, every nutrient, and source',
    () async {
      const saved = FoodEntry(
        id: 'saved-1',
        date: '2026-09-15',
        meal: 'dinner',
        label: 'Haferflocken',
        foodKey: 'oats',
        quantity: 80,
        unit: 'g',
        kcal: 298,
        proteinG: 10.8,
        carbsG: 50.4,
        fatG: 5.6,
        fibreG: 8.1,
        sugarG: 0.9,
        satFatG: 1.1,
        sodiumMg: 4,
        ironMg: 3.4,
        calciumMg: 42,
        source: FoodSource.barcode,
        confirmed: true,
        note: 'pack',
      );
      expect(saved.atTs, isNull);
      await NutritionDb.put(db, saved);
      final back = (await NutritionDb.entriesForDay(db, '2026-09-15')).single;
      expect(back.atTs, isNull);
      expect(back.foodKey, 'oats');
      expect(back.quantity, 80);
      expect(back.unit, 'g');
      expect(back.kcal, 298);
      expect(back.proteinG, 10.8);
      expect(back.carbsG, 50.4);
      expect(back.fatG, 5.6);
      expect(back.fibreG, 8.1);
      expect(back.sugarG, 0.9);
      expect(back.satFatG, 1.1);
      expect(back.sodiumMg, 4);
      expect(back.ironMg, 3.4);
      expect(back.calciumMg, 42);
      expect(back.source, FoodSource.barcode);
      expect(back.confirmed, isTrue);
      expect(back.note, 'pack');
      expect(back.createdAt, isNotNull);
      expect(back.updatedAt, isNotNull);
    },
  );

  test('constructor and photo sanitise keep ledger stamps and leave atTs null',
      () {
    final src = _entry(
      id: 'p1',
      label: 'Rice, chicken',
      kcal: 720,
      proteinG: 40,
      fibreG: 6,
      source: FoodSource.photo,
      createdAt: 1_000,
      updatedAt: 2_000,
    );
    expect(src.atTs, isNull);
    final clean = src.sanitised;
    expect(clean.atTs, isNull);
    expect(clean.kcal, isNull);
    expect(clean.proteinG, isNull);
    expect(clean.fibreG, isNull);
    expect(clean.label, 'Rice, chicken');
    expect(clean.createdAt, 1_000);
    expect(clean.updatedAt, 2_000);

    final edited = FoodEntry(
      id: src.id,
      date: src.date,
      meal: src.meal,
      label: 'Rice',
      atTs: src.atTs,
      foodKey: src.foodKey,
      quantity: src.quantity,
      unit: src.unit,
      kcal: 500,
      proteinG: src.proteinG,
      fibreG: src.fibreG,
      source: src.source,
      confirmed: true,
      note: src.note,
      createdAt: src.createdAt,
      updatedAt: src.updatedAt,
    );
    expect(edited.atTs, isNull);
    expect(edited.createdAt, 1_000);
    expect(edited.updatedAt, 2_000);
    expect(edited.proteinG, 40);
    expect(edited.fibreG, 6);
    expect(edited.source, FoodSource.photo);
  });

  test('put does not invent a consumed-at from the selected day', () async {
    await NutritionDb.put(
      db,
      _entry(id: 'bare', date: '2026-09-15', label: 'Snack'),
    );
    final row = (await db.query('food_entry')).single;
    expect(row['at_ts'], isNull);
    expect((await NutritionDb.entriesForDay(db, '2026-09-15')).single.atTs,
        isNull);
  });

  test('recent keeps the same label under two food keys', () async {
    await _seed(
      db,
      id: 'a',
      label: 'Oats',
      foodKey: 'oats-a',
      createdAt: 100,
    );
    await _seed(
      db,
      id: 'b',
      label: 'Oats',
      foodKey: 'oats-b',
      createdAt: 200,
    );
    final recents = await NutritionDb.recent(db);
    expect(recents.map((e) => e.foodKey), ['oats-b', 'oats-a']);
  });

  test('recent picks latest created_at, not lexical MAX(id)', () async {
    await _seed(
      db,
      id: 'zzz',
      label: 'Oats',
      foodKey: 'oats',
      createdAt: 100,
    );
    await _seed(
      db,
      id: 'aaa',
      label: 'Oats',
      foodKey: 'oats',
      createdAt: 200,
    );
    final recents = await NutritionDb.recent(db);
    expect(recents, hasLength(1));
    expect(recents.single.id, 'aaa');
    expect(recents.single.createdAt, 200);
  });

  test('recent tie-break is stable on id when created_at matches', () async {
    await _seed(db, id: 'm', label: 'Milk', foodKey: 'milk', createdAt: 50);
    await _seed(db, id: 'n', label: 'Nuts', foodKey: 'nuts', createdAt: 50);
    await _seed(
      db,
      id: 'z-old',
      label: 'Milk',
      foodKey: 'milk',
      createdAt: 50,
    );
    final recents = await NutritionDb.recent(db);
    expect(recents.map((e) => e.id), ['m', 'n']);
  });

  test('recent keeps a keyed row distinct from an unkeyed same label', () async {
    await _seed(
      db,
      id: 'keyed',
      label: 'Oats',
      foodKey: 'oats',
      createdAt: 100,
    );
    await _seed(
      db,
      id: 'bare',
      label: 'Oats',
      createdAt: 200,
    );
    final recents = await NutritionDb.recent(db);
    expect(recents.map((e) => e.id), ['bare', 'keyed']);
  });

  test('recent does not fuse label and source across a delimiter', () async {
    await _seed(
      db,
      id: 'concat',
      label: 'Soup\u001fphoto',
      source: 'manual',
      createdAt: 100,
    );
    await _seed(
      db,
      id: 'fields',
      label: 'Soup',
      source: 'photo',
      createdAt: 200,
    );
    final recents = await NutritionDb.recent(db);
    expect(recents.map((e) => e.id), ['fields', 'concat']);
  });

  test('recent without food_key groups by label and source', () async {
    await _seed(
      db,
      id: 's1',
      label: 'Soup',
      source: 'manual',
      createdAt: 100,
    );
    await _seed(
      db,
      id: 's2',
      label: 'Soup',
      source: 'manual',
      createdAt: 300,
    );
    await _seed(
      db,
      id: 's3',
      label: 'Soup',
      source: 'photo',
      createdAt: 200,
    );
    final recents = await NutritionDb.recent(db);
    expect(recents.map((e) => e.id), ['s2', 's3']);
  });

  test('recent respects limit after distinct', () async {
    for (var i = 0; i < 5; i++) {
      await _seed(
        db,
        id: 'k$i',
        label: 'Food $i',
        foodKey: 'k$i',
        createdAt: i * 10,
      );
    }
    final recents = await NutritionDb.recent(db, limit: 3);
    expect(recents.map((e) => e.id), ['k4', 'k3', 'k2']);
  });

  Future<(FoodEntry, String)> roundtripSource(String wire) async {
    final path =
        '${await databaseFactory.getDatabasesPath()}/nutrition_src_$wire.db';
    await databaseFactory.deleteDatabase(path);
    final disk = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (d, _) => createNutritionTables(d),
      ),
    );
    await _seed(
      disk,
      id: 'src',
      label: 'Mystery',
      source: wire,
      createdAt: 1,
    );
    final read = (await NutritionDb.entriesForDay(disk, '2026-09-15')).single;
    await NutritionDb.put(disk, read);
    await disk.close();
    final reopened = await databaseFactory.openDatabase(path);
    addTearDown(() async {
      await reopened.close();
      await databaseFactory.deleteDatabase(path);
    });
    final back = (await NutritionDb.entriesForDay(reopened, '2026-09-15')).single;
    final stored =
        (await reopened.query('food_entry')).single['source'] as String;
    return (back, stored);
  }

  test('unknown plus photo wire is photo and drops unconfirmed kcal on put',
      () async {
    const sneak = FoodEntry(
      id: 'sneak',
      date: '2026-09-15',
      meal: 'lunch',
      label: 'Rice',
      kcal: 720,
      proteinG: 40,
      source: FoodSource.unknown,
      sourceCode: 'photo',
    );
    expect(sneak.source, FoodSource.photo);
    expect(sneak.sourceCode, 'photo');
    expect(sneak.sanitised.kcal, isNull);
    await NutritionDb.put(db, sneak);
    final back = (await NutritionDb.entriesForDay(db, '2026-09-15')).single;
    expect(back.source, FoodSource.photo);
    expect(back.sourceCode, 'photo');
    expect(back.kcal, isNull);
    expect(back.proteinG, isNull);
    final row = (await db.query('food_entry')).single;
    expect(row['source'], 'photo');
    expect(row['kcal'], isNull);
  });

  test('unknown plus manual wire is manual and keeps confirmed numbers',
      () async {
    await NutritionDb.put(
      db,
      const FoodEntry(
        id: 'typed-manual',
        date: '2026-09-15',
        meal: 'lunch',
        label: 'Oats',
        kcal: 150,
        source: FoodSource.unknown,
        sourceCode: 'manual',
        confirmed: true,
      ),
    );
    final back = (await NutritionDb.entriesForDay(db, '2026-09-15')).single;
    expect(back.source, FoodSource.manual);
    expect(back.sourceCode, 'manual');
    expect(back.kcal, 150);
  });

  test('unknown source stays typed unknown with its exact code after '
      'read, put, and reopen', () async {
    final (back, stored) = await roundtripSource('crowd-guess');
    expect(back.source, FoodSource.unknown);
    expect(back.sourceCode, 'crowd-guess');
    expect(stored, 'crowd-guess');
  });

  test('empty source code is unknown and retained after read, put, reopen',
      () async {
    final (back, stored) = await roundtripSource('');
    expect(back.source, FoodSource.unknown);
    expect(back.sourceCode, '');
    expect(stored, '');
  });

  test('manual source stays manual after read, put, reopen', () async {
    final (back, stored) = await roundtripSource('manual');
    expect(back.source, FoodSource.manual);
    expect(back.sourceCode, 'manual');
    expect(stored, 'manual');
  });

  test('photo source stays photo after read, put, reopen', () async {
    final (back, stored) = await roundtripSource('photo');
    expect(back.source, FoodSource.photo);
    expect(back.sourceCode, 'photo');
    expect(stored, 'photo');
  });
}
