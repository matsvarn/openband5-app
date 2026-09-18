import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openband5_profile_rederive_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });
  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  test(
    'a birth date refreshes finalized retained days and clearing removes estimates',
    () async {
      final db = await LocalDb.instance;
      final batch = db.batch();
      for (var day = 10; day <= 11; day++) {
        final start = DateTime(2026, 4, day, 9).millisecondsSinceEpoch ~/ 1000;
        for (var i = 0; i < 7200; i++) {
          batch.insert('decoded_onehz', {
            'device_id': '',
            'ts_ms': (start + i) * 1000,
            'rec_ts': start + i,
            'counter': day * 10000 + i,
            'hr': 100 + i % 7,
            'ax': 0.05 * (i % 60) / 60,
            'ay': 0.05 * (i % 30) / 30,
            'az': 0.98,
            'device_family': 'gen4',
          });
        }
      }
      await batch.commit(noResult: true);
      const missing = PersonalProfile(
        weightKg: 72,
        heightCm: 178,
        sex: 'm',
        restingHrManual: 55,
      );
      final engine = DerivationEngine();
      expect(await engine.run(missing), 2);
      expect(
        await LocalDb.metricValueOn('2026-04-10', 'calories_total'),
        isNull,
      );
      await db.update('day_result', {'finalized': 1});
      final profile = PersonalProfile(
        birthDate: DateTime(1990, 4, 11),
        weightKg: 72,
        heightCm: 178,
        sex: 'm',
        restingHrManual: 55,
      );
      // A fresh engine models reopening after the profile has been saved.
      expect(await DerivationEngine().run(profile), 2);
      final before = await LocalDb.metricValueOn(
        '2026-04-10',
        'calories_total',
      );
      final birthday = await LocalDb.metricValueOn(
        '2026-04-11',
        'calories_total',
      );
      expect(before, isNotNull);
      expect(birthday, isNotNull);
      expect(
        birthday,
        isNot(closeTo(before!, 0.0001)),
        reason: 'identical recordings on either side use different ages',
      );
      await db.update('day_result', {'finalized': 1});
      expect(
        await DerivationEngine().run(profile),
        0,
        reason: 'unchanged details do not repeatedly reopen finalized days',
      );
      expect(await DerivationEngine().run(missing), 2);
      expect(
        await LocalDb.metricValueOn('2026-04-10', 'calories_total'),
        isNull,
      );
      expect(
        await LocalDb.metricValueOn('2026-04-11', 'calories_total'),
        isNull,
      );
    },
  );
}
