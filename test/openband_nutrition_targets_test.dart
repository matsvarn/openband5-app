import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/nutrition_targets.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const example = NutritionTargetValues(
    energyKcal: 2000,
    proteinG: 125,
    carbohydrateG: 240,
    fatG: 60,
  );

  String shift(String day, int days) {
    final parts = day.split('-').map(int.parse).toList();
    return dayLabelOf(
      DateTime(parts[0], parts[1], parts[2]).add(Duration(days: days)),
    );
  }

  void expectValues(NutritionTargetValues a, NutritionTargetValues b) {
    expect(a.energyKcal, b.energyKcal);
    expect(a.proteinG, b.proteinG);
    expect(a.carbohydrateG, b.carbohydrateG);
    expect(a.fatG, b.fatG);
  }

  group('typed contract', () {
    test(
      'rejects invalid dates, nonfinite/negative values, and zero energy',
      () {
        expect(isNutritionTargetDay('2026-09-15'), isTrue);
        expect(isNutritionTargetDay('2026-02-30'), isFalse);
        expect(isNutritionTargetDay('2026-9-15'), isFalse);
        expect(isNutritionTargetDay('2026-09-15T00:00:00Z'), isFalse);
        expect(isNutritionTargetDay(''), isFalse);

        expect(
          () => requireNutritionTargetValues(
            const NutritionTargetValues(energyKcal: 0),
          ),
          throwsArgumentError,
        );
        expect(
          () => requireNutritionTargetValues(
            const NutritionTargetValues(energyKcal: -1),
          ),
          throwsArgumentError,
        );
        expect(
          () => requireNutritionTargetValues(
            const NutritionTargetValues(energyKcal: double.nan),
          ),
          throwsArgumentError,
        );
        expect(
          () => requireNutritionTargetValues(
            const NutritionTargetValues(proteinG: -0.1),
          ),
          throwsArgumentError,
        );
        expect(
          () => requireNutritionTargetValues(
            const NutritionTargetValues(carbohydrateG: double.infinity),
          ),
          throwsArgumentError,
        );
        requireNutritionTargetValues(const NutritionTargetValues(proteinG: 0));
        requireNutritionTargetValues(example);
      },
    );

    test('legacyUndated must not invent an effectiveDay', () {
      expect(
        () => NutritionTargetSnapshot(
          day: '2026-09-15',
          origin: NutritionTargetOrigin.legacyUndated,
          effectiveDay: '2026-09-15',
          values: const NutritionTargetValues(energyKcal: 2000),
        ),
        throwsA(isA<AssertionError>()),
      );
      const undated = NutritionTargetSnapshot(
        day: '2026-09-15',
        origin: NutritionTargetOrigin.legacyUndated,
        values: NutritionTargetValues(energyKcal: 2000),
      );
      expect(undated.effectiveDay, isNull);
      expect(undated.revision, isNull);
    });

    test('legacy decode never clamps; present invalid values refuse', () {
      expect(decodeOptionalEnergy(2000), 2000);
      expect(decodeOptionalEnergy(2000.0), 2000);
      expect(decodeOptionalEnergy(null), isNull);
      expect(() => decodeOptionalEnergy(0), throwsA(isA<FormatException>()));
      expect(() => decodeOptionalEnergy(-10), throwsA(isA<FormatException>()));
      expect(
        () => decodeOptionalEnergy('2000'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => decodeOptionalEnergy(double.nan),
        throwsA(isA<FormatException>()),
      );
      expect(decodeOptionalGrams(0), 0);
      expect(decodeOptionalGrams(null), isNull);
      expect(() => decodeOptionalGrams(-1), throwsA(isA<FormatException>()));
      expect(() => decodeOptionalGrams('125'), throwsA(isA<FormatException>()));
      expect(() => decodeOptionalGrams(true), throwsA(isA<FormatException>()));
    });
  });

  group('SQLite', () {
    late AppState app;
    late LocalOpenBandRepository repository;
    const dbName = 'openband_nutrition_targets_test.db';

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
      repository = LocalOpenBandRepository(app);
    });

    tearDown(() async {
      app.dispose();
      await LocalDb.close();
    });

    Future<void> seedLegacy(String json) async {
      SharedPreferences.setMockInitialValues({kLegacyProfilePrefsKey: json});
    }

    test(
      'unknown source and no goal stay empty; reading does not mutate',
      () async {
        final today = todayLabel();
        final snapshot = await repository.readNutritionTargets(today);
        expect(snapshot.origin, isNull);
        expect(snapshot.effectiveDay, isNull);
        expect(snapshot.revision, isNull);
        expect(snapshot.values.hasAny, isFalse);
        expect(await LocalDb.nutritionTargetPeriods(), isEmpty);
        expect(await repository.listNutritionTargetChanges(), isEmpty);
      },
    );

    test('save, list, inherit, close/reopen, and future boundary', () async {
      const day = '2026-09-15';
      final saved = await repository.saveNutritionTargets(day, example);
      expect(saved.saved, isTrue);
      expect(saved.row!.revision, 1);
      expect(saved.row!.validFromDay, day);
      expectValues(saved.row!.values, example);

      var snapshot = await repository.readNutritionTargets(day);
      expect(snapshot.origin, NutritionTargetOrigin.dated);
      expect(snapshot.effectiveDay, day);
      expect(snapshot.revision, 1);
      expectValues(snapshot.values, example);
      final inherited = await repository.readNutritionTargets('2026-09-16');
      expectValues(inherited.values, example);
      expect(inherited.origin, NutritionTargetOrigin.dated);
      expect(inherited.effectiveDay, day);
      expect(inherited.revision, isNull);
      expect(
        (await repository.readNutritionTargets('2026-09-14')).origin,
        isNull,
      );

      final later = await repository.saveNutritionTargets(
        '2026-09-20',
        const NutritionTargetValues(energyKcal: 1800, proteinG: 0),
      );
      expect(later.saved, isTrue);
      expect(
        (await repository.readNutritionTargets(day)).values.energyKcal,
        2000,
      );
      expect(
        (await repository.readNutritionTargets('2026-09-21')).values.energyKcal,
        1800,
      );
      expect(
        (await repository.readNutritionTargets('2026-09-21')).values.proteinG,
        0,
      );

      final listed = await repository.listNutritionTargetChanges();
      expect(listed.map((c) => c.validFromDay), [day, '2026-09-20']);

      await LocalDb.close();
      snapshot = await repository.readNutritionTargets(day);
      expect(snapshot.revision, 1);
      expectValues(snapshot.values, example);
    });

    test(
      'clear writes a dated empty boundary and does not erase earlier history',
      () async {
        const earlier = '2026-09-10';
        const day = '2026-09-15';
        await repository.saveNutritionTargets(earlier, example);
        final cleared = await repository.clearNutritionTargets(day);
        expect(cleared.saved, isTrue);
        expect(cleared.row!.values.hasAny, isFalse);
        expect(cleared.row!.revision, 1);

        expectValues(
          (await repository.readNutritionTargets('2026-09-14')).values,
          example,
        );
        final after = await repository.readNutritionTargets(day);
        expect(after.origin, NutritionTargetOrigin.dated);
        expect(after.effectiveDay, day);
        expect(after.values.hasAny, isFalse);
        expect(
          (await repository.readNutritionTargets('2026-09-16')).values.hasAny,
          isFalse,
        );
        expect(
          (await repository.listNutritionTargetChanges()).map(
            (c) => c.validFromDay,
          ),
          [earlier, day],
        );
      },
    );

    test(
      'same-date CAS distinguishes absent from existing empty and preserves the row',
      () async {
        const day = '2026-09-15';
        final first = await repository.saveNutritionTargets(day, example);
        expect(first.saved, isTrue);

        final clash = await repository.saveNutritionTargets(
          day,
          const NutritionTargetValues(energyKcal: 1600),
        );
        expect(clash.conflict, isTrue);
        expectValues(clash.row!.values, example);
        expect(clash.row!.revision, 1);
        expectValues(
          (await repository.readNutritionTargets(day)).values,
          example,
        );

        final updated = await repository.saveNutritionTargets(
          day,
          const NutritionTargetValues(energyKcal: 1600, fatG: 50),
          expectedRevision: 1,
        );
        expect(updated.saved, isTrue);
        expect(updated.row!.revision, 2);
        expect(updated.row!.values.energyKcal, 1600);
        expect(updated.row!.createdAt, first.row!.createdAt);

        final stale = await repository.saveNutritionTargets(
          day,
          example,
          expectedRevision: 1,
        );
        expect(stale.conflict, isTrue);
        expect(stale.row!.revision, 2);
        expect(stale.row!.values.energyKcal, 1600);

        const other = '2026-09-16';
        await repository.clearNutritionTargets(other);
        final emptyClash = await repository.saveNutritionTargets(
          other,
          example,
        );
        expect(emptyClash.conflict, isTrue);
        expect(emptyClash.row!.values.hasAny, isFalse);
        expect(emptyClash.row!.revision, 1);

        final absentExpected = await repository.saveNutritionTargets(
          '2026-09-17',
          example,
          expectedRevision: 1,
        );
        expect(absentExpected.conflict, isTrue);
        expect(absentExpected.row, isNull);
        expect(await LocalDb.nutritionTargetPeriodOn('2026-09-17'), isNull);
      },
    );

    test(
      'transaction failure rolls back and leaves prior periods and prefs',
      () async {
        const day = '2026-09-15';
        final blob = jsonEncode({
          kLegacyEnergyTargetKey: 2000,
          kLegacyProteinTargetKey: 125,
          'name': 'kept',
        });
        await seedLegacy(blob);
        await repository.saveNutritionTargets(day, example);
        final db = await LocalDb.instance;
        await db.execute('''
        CREATE TRIGGER fail_nutrition_target
        BEFORE INSERT ON nutrition_target_period
        BEGIN SELECT RAISE(ABORT, 'synthetic full disk'); END
      ''');
        await expectLater(
          repository.saveNutritionTargets(
            '2026-09-20',
            const NutritionTargetValues(energyKcal: 1800),
          ),
          throwsA(anything),
        );
        expect(
          (await repository.listNutritionTargetChanges()).map(
            (c) => c.validFromDay,
          ),
          [day],
        );
        expectValues(
          (await repository.readNutritionTargets(day)).values,
          example,
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(kLegacyProfilePrefsKey), blob);
      },
    );

    test(
      'legacy undated applies today only; dated empty suppresses it',
      () async {
        final today = todayLabel();
        final past = shift(today, -1);
        final future = shift(today, 1);
        final blob = jsonEncode({
          kLegacyEnergyTargetKey: 2000,
          kLegacyProteinTargetKey: 125,
          'name': 'kept',
        });
        await seedLegacy(blob);

        final todaySnap = await repository.readNutritionTargets(today);
        expect(todaySnap.origin, NutritionTargetOrigin.legacyUndated);
        expect(todaySnap.effectiveDay, isNull);
        expect(todaySnap.revision, isNull);
        expect(todaySnap.values.energyKcal, 2000);
        expect(todaySnap.values.proteinG, 125);
        expect(todaySnap.values.carbohydrateG, isNull);
        expect(todaySnap.values.fatG, isNull);

        expect((await repository.readNutritionTargets(past)).origin, isNull);
        expect((await repository.readNutritionTargets(future)).origin, isNull);
        expect(await LocalDb.nutritionTargetPeriods(), isEmpty);

        await repository.clearNutritionTargets(today);
        final cleared = await repository.readNutritionTargets(today);
        expect(cleared.origin, NutritionTargetOrigin.dated);
        expect(cleared.values.hasAny, isFalse);
        expect((await repository.readNutritionTargets(past)).origin, isNull);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(kLegacyProfilePrefsKey), blob);
      },
    );

    test(
      'inherited dated values keep revision null; own row shares values+revision',
      () async {
        const start = '2026-09-10';
        const later = '2026-09-15';
        await repository.saveNutritionTargets(start, example);
        final own = await repository.readNutritionTargets(start);
        expect(own.origin, NutritionTargetOrigin.dated);
        expect(own.effectiveDay, start);
        expect(own.revision, 1);
        expectValues(own.values, example);

        final inherited = await repository.readNutritionTargets(later);
        expect(inherited.origin, NutritionTargetOrigin.dated);
        expect(inherited.effectiveDay, start);
        expect(inherited.revision, isNull);
        expectValues(inherited.values, example);
      },
    );

    test('corrupt prefs blob throws and does not use stale app.user', () async {
      final today = todayLabel();
      const blob = '{not-json';
      app.user = {kLegacyEnergyTargetKey: 2000, kLegacyProteinTargetKey: 125};
      SharedPreferences.setMockInitialValues({kLegacyProfilePrefsKey: blob});
      await expectLater(
        repository.readNutritionTargets(today),
        throwsA(isA<FormatException>()),
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          kLegacyProfilePrefsKey,
        ),
        blob,
      );
      expect(await LocalDb.nutritionTargetPeriods(), isEmpty);
    });

    test('non-map prefs blob throws and does not use stale app.user', () async {
      final today = todayLabel();
      final blob = jsonEncode(['kcal_target', 2000]);
      app.user = {kLegacyEnergyTargetKey: 2000};
      SharedPreferences.setMockInitialValues({kLegacyProfilePrefsKey: blob});
      await expectLater(
        repository.readNutritionTargets(today),
        throwsA(isA<FormatException>()),
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          kLegacyProfilePrefsKey,
        ),
        blob,
      );
      expect(await LocalDb.nutritionTargetPeriods(), isEmpty);
    });

    test(
      'absent prefs key may use in-memory app.user for today only',
      () async {
        final today = todayLabel();
        app.user = {kLegacyEnergyTargetKey: 1800, kLegacyProteinTargetKey: 90};
        final snapshot = await repository.readNutritionTargets(today);
        expect(snapshot.origin, NutritionTargetOrigin.legacyUndated);
        expect(snapshot.effectiveDay, isNull);
        expect(snapshot.revision, isNull);
        expect(snapshot.values.energyKcal, 1800);
        expect(snapshot.values.proteinG, 90);
        expect(
          (await repository.readNutritionTargets(shift(today, -1))).origin,
          isNull,
        );
      },
    );

    test('invalid legacy values throw and prefs bytes stay put', () async {
      final today = todayLabel();
      final blob = jsonEncode({
        kLegacyEnergyTargetKey: -100,
        kLegacyProteinTargetKey: 'high',
        'step_goal': 8000,
      });
      await seedLegacy(blob);
      await expectLater(
        repository.readNutritionTargets(today),
        throwsA(isA<FormatException>()),
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          kLegacyProfilePrefsKey,
        ),
        blob,
      );
    });

    test('legacy null keys stay genuinely unset', () async {
      final today = todayLabel();
      await seedLegacy(
        jsonEncode({
          kLegacyEnergyTargetKey: null,
          kLegacyProteinTargetKey: null,
          'step_goal': 8000,
        }),
      );
      final snapshot = await repository.readNutritionTargets(today);
      expect(snapshot.origin, isNull);
      expect(snapshot.values.hasAny, isFalse);
    });

    test('legacy zero grams are retained as an explicit target', () async {
      final today = todayLabel();
      await seedLegacy(jsonEncode({kLegacyProteinTargetKey: 0}));
      final snapshot = await repository.readNutritionTargets(today);
      expect(snapshot.origin, NutritionTargetOrigin.legacyUndated);
      expect(snapshot.values.proteinG, 0);
      expect(snapshot.values.energyKcal, isNull);
    });

    test('legacy energy 0 is not a clear sentinel and refuses', () async {
      final today = todayLabel();
      final blob = jsonEncode({kLegacyEnergyTargetKey: 0});
      await seedLegacy(blob);
      await expectLater(
        repository.readNutritionTargets(today),
        throwsA(isA<FormatException>()),
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          kLegacyProfilePrefsKey,
        ),
        blob,
      );
    });

    test('dated invalid non-null fields refuse and keep the row', () async {
      const day = '2026-09-15';
      final db = await LocalDb.instance;
      await db.insert(kNutritionTargetPeriodTable, {
        'valid_from_day': day,
        'energy_kcal': double.infinity,
        'protein_g': 125,
        'carbs_g': null,
        'fat_g': null,
        'revision': 1,
        'created_at': 0,
        'updated_at': 0,
      });
      await expectLater(
        repository.readNutritionTargets(day),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        repository.listNutritionTargetChanges(),
        throwsA(isA<FormatException>()),
      );
      final row = await LocalDb.nutritionTargetPeriodOn(day);
      expect(row, isNotNull);
      expect(row!['protein_g'], 125);
    });

    test('invalid writes and dates never create rows', () async {
      await expectLater(
        repository.saveNutritionTargets('2026-02-30', example),
        throwsArgumentError,
      );
      await expectLater(
        repository.saveNutritionTargets(
          '2026-09-15',
          const NutritionTargetValues(energyKcal: 0),
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.saveNutritionTargets(
          '2026-09-15',
          const NutritionTargetValues(fatG: -1),
        ),
        throwsArgumentError,
      );
      expect(await LocalDb.nutritionTargetPeriods(), isEmpty);
    });

    test(
      'pre-migration upgrade from 59 creates 63 without fabricating 60',
      () async {
        expect(LocalDb.schemaVersion, 63);
        await LocalDb.close();
        final oldName = 'nutrition_targets_from_59.db';
        final oldPath = p.join(
          await databaseFactory.getDatabasesPath(),
          oldName,
        );
        await databaseFactory.deleteDatabase(oldPath);
        final old = await databaseFactory.openDatabase(
          oldPath,
          options: OpenDatabaseOptions(
            version: 59,
            onCreate: (db, _) async {
              await db.execute('CREATE TABLE marker (id INTEGER PRIMARY KEY)');
              await db.insert('marker', {'id': 1});
            },
          ),
        );
        await old.close();
        LocalDb.dbName = oldName;
        final upgraded = await LocalDb.instance;
        expect(
          (await upgraded.rawQuery('PRAGMA user_version')).first.values.first,
          63,
        );
        expect(
          await upgraded.rawQuery(
            "SELECT 1 FROM sqlite_master WHERE type='table' "
            "AND name='nutrition_target_period'",
          ),
          isNotEmpty,
        );
        expect(await upgraded.query('journal_field_def'), isEmpty);
        expect(await upgraded.query('marker'), hasLength(1));
        await LocalDb.close();
        await databaseFactory.deleteDatabase(oldPath);
        LocalDb.dbName = dbName;
      },
    );

    test('backup copy retains dated goals', () async {
      const day = '2026-09-15';
      await repository.saveNutritionTargets(day, example);
      final db = await LocalDb.instance;
      final dest = p.join(
        await databaseFactory.getDatabasesPath(),
        'nutrition_targets_backup.db',
      );
      await databaseFactory.deleteDatabase(dest);
      await db.execute('VACUUM INTO ?', [dest]);
      final copy = await databaseFactory.openDatabase(
        dest,
        options: OpenDatabaseOptions(readOnly: true),
      );
      final rows = await copy.query(kNutritionTargetPeriodTable);
      expect(rows, hasLength(1));
      expect(rows.first['valid_from_day'], day);
      expect(rows.first['energy_kcal'], 2000);
      expect(rows.first['protein_g'], 125);
      expect(rows.first['carbs_g'], 240);
      expect(rows.first['fat_g'], 60);
      await copy.close();
      await databaseFactory.deleteDatabase(dest);
    });
  });

  group('synthetic adapter parity', () {
    late SyntheticOpenBandRepository repo;

    setUp(() {
      repo = SyntheticOpenBandRepository.fromMaps(
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
    });

    test(
      'dated save, inherit, future, clear, CAS, and list match SQLite',
      () async {
        const day = '2026-09-15';
        final saved = await repo.saveNutritionTargets(day, example);
        expect(saved.saved, isTrue);
        expect(saved.row!.revision, 1);
        expectValues((await repo.readNutritionTargets(day)).values, example);
        expect((await repo.readNutritionTargets(day)).revision, 1);
        expect((await repo.readNutritionTargets('2026-09-14')).origin, isNull);
        final inherited = await repo.readNutritionTargets('2026-09-16');
        expect(inherited.values.energyKcal, 2000);
        expect(inherited.effectiveDay, day);
        expect(inherited.revision, isNull);

        await repo.saveNutritionTargets(
          '2026-09-20',
          const NutritionTargetValues(energyKcal: 1800),
        );
        expect((await repo.readNutritionTargets(day)).values.energyKcal, 2000);
        expect(
          (await repo.readNutritionTargets('2026-09-21')).values.energyKcal,
          1800,
        );

        final clash = await repo.saveNutritionTargets(
          day,
          const NutritionTargetValues(energyKcal: 1600),
        );
        expect(clash.conflict, isTrue);
        expect(clash.row!.revision, 1);

        await repo.clearNutritionTargets(day, expectedRevision: 1);
        expect((await repo.readNutritionTargets(day)).values.hasAny, isFalse);
        expect((await repo.readNutritionTargets('2026-09-14')).origin, isNull);
        expect(
          (await repo.listNutritionTargetChanges()).map((c) => c.validFromDay),
          [day, '2026-09-20'],
        );
      },
    );

    test('legacy today-vs-history and empty boundary match SQLite', () async {
      repo.nutritionToday = () => '2026-09-15';
      repo.legacyUndatedProfile = {
        kLegacyEnergyTargetKey: 2000,
        kLegacyProteinTargetKey: 125,
      };
      final today = await repo.readNutritionTargets('2026-09-15');
      expect(today.origin, NutritionTargetOrigin.legacyUndated);
      expect(today.effectiveDay, isNull);
      expect(today.revision, isNull);
      expect(today.values.energyKcal, 2000);
      expect((await repo.readNutritionTargets('2026-09-14')).origin, isNull);
      expect((await repo.readNutritionTargets('2026-09-16')).origin, isNull);

      await repo.clearNutritionTargets('2026-09-15');
      expect(
        (await repo.readNutritionTargets('2026-09-15')).origin,
        NutritionTargetOrigin.dated,
      );
      expect(
        (await repo.readNutritionTargets('2026-09-15')).values.hasAny,
        isFalse,
      );
      expect(repo.legacyUndatedProfile![kLegacyEnergyTargetKey], 2000);
    });

    test('failed write leaves prior periods; invalid values throw', () async {
      const day = '2026-09-15';
      await repo.saveNutritionTargets(day, example);
      repo.failNutritionTargetWrite = true;
      await expectLater(
        repo.saveNutritionTargets(
          '2026-09-20',
          const NutritionTargetValues(energyKcal: 1800),
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        (await repo.listNutritionTargetChanges()).single.validFromDay,
        day,
      );
      repo.failNutritionTargetWrite = false;
      await expectLater(
        repo.saveNutritionTargets('2026-02-30', example),
        throwsArgumentError,
      );
      await expectLater(
        repo.saveNutritionTargets(
          day,
          const NutritionTargetValues(energyKcal: 0),
          expectedRevision: 1,
        ),
        throwsArgumentError,
      );
      expect((await repo.readNutritionTargets(day)).values.energyKcal, 2000);
    });
  });
}
