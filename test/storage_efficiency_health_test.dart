import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';

void main() {
  late Directory temp;
  final calls = <String>[];
  final start = DateTime.utc(2026, 1, 1);
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    temp = await Directory.systemTemp.createTemp('ob5-health-');
    await databaseFactory.setDatabasesPath(temp.path);
    LocalDb.dbName = 'test.db';
    calls.clear();
    LocalDb.debugIntegrityCheck = (statement) async {
      calls.add(statement);
      return ['ok'];
    };
  });
  tearDown(() async {
    LocalDb.debugIntegrityCheck = null;
    await LocalDb.close();
    await temp.delete(recursive: true);
  });

  test(
    'daily quick and weekly full gates persist across database reopen',
    () async {
      expect((await LocalDb.schemaHealth(now: start))['ok'], isTrue);
      expect(calls, ['PRAGMA integrity_check']);
      await LocalDb.close();
      expect(
        (await LocalDb.schemaHealth(
          now: start.add(const Duration(hours: 23)),
        ))['ok'],
        isTrue,
      );
      expect(calls.length, 1);
      expect(
        (await LocalDb.schemaHealth(
          now: start.add(const Duration(hours: 24)),
        ))['ok'],
        isTrue,
      );
      expect(calls, ['PRAGMA integrity_check', 'PRAGMA quick_check']);
      await LocalDb.schemaHealth(now: start.add(const Duration(hours: 47)));
      expect(calls.length, 2);
      await LocalDb.schemaHealth(
        now: start.add(const Duration(days: 6, hours: 23)),
      );
      expect(calls.last, 'PRAGMA quick_check');
      await LocalDb.schemaHealth(now: start.add(const Duration(days: 7)));
      expect(calls, [
        'PRAGMA integrity_check',
        'PRAGMA quick_check',
        'PRAGMA quick_check',
        'PRAGMA integrity_check',
      ]);
      final payload = jsonDecode(
        (await LocalDb.computeFreshness(
              LocalDb.kIntegrityHealthKey,
            ))!['payload_json']
            as String,
      );
      expect(
        payload['checked_at_ms'],
        start.add(const Duration(days: 7)).millisecondsSinceEpoch,
      );
      expect(payload['full_checked_at_ms'], payload['checked_at_ms']);
      expect(payload['result'], ['ok']);
    },
  );

  test(
    'schema presence stays live even when the integrity verdict is cached',
    () async {
      expect((await LocalDb.schemaHealth(now: start))['ok'], isTrue);
      final db = await LocalDb.instance;
      await db.execute('DROP TABLE observation');
      final health = await LocalDb.schemaHealth(
        now: start.add(const Duration(minutes: 1)),
      );
      expect(health['ok'], isFalse);
      expect(health['missing_tables'], contains('observation'));
      expect(health['integrity_ok'], isTrue);
      expect(calls.length, 1);
    },
  );

  test(
    'a full-check failure survives reopen and a weaker quick-check success',
    () async {
      LocalDb.debugIntegrityCheck = (statement) async {
        calls.add(statement);
        return calls.length == 1 ? ['index mismatch'] : ['ok'];
      };
      expect((await LocalDb.schemaHealth(now: start))['integrity_ok'], isFalse);
      await LocalDb.close();
      expect(
        (await LocalDb.schemaHealth(
          now: start.add(const Duration(hours: 1)),
        ))['integrity_ok'],
        isFalse,
      );
      expect(calls.length, 1);
      expect(
        (await LocalDb.schemaHealth(
          now: start.add(const Duration(days: 1)),
        ))['integrity_ok'],
        isFalse,
      );
      expect(calls.last, 'PRAGMA quick_check');
      expect(
        (await LocalDb.schemaHealth(
          now: start.add(const Duration(days: 7)),
        ))['integrity_ok'],
        isTrue,
      );
      expect(calls.last, 'PRAGMA integrity_check');
    },
  );

  test(
    'a daily failure clears only after a later successful eligible check',
    () async {
      LocalDb.debugIntegrityCheck = (statement) async {
        calls.add(statement);
        return calls.length == 2 ? ['page mismatch'] : ['ok'];
      };
      await LocalDb.schemaHealth(now: start);
      expect(
        (await LocalDb.schemaHealth(
          now: start.add(const Duration(days: 1)),
        ))['integrity_ok'],
        isFalse,
      );
      await LocalDb.close();
      expect(
        (await LocalDb.schemaHealth(
          now: start.add(const Duration(hours: 47)),
        ))['integrity_ok'],
        isFalse,
      );
      expect(calls.length, 2);
      expect(
        (await LocalDb.schemaHealth(
          now: start.add(const Duration(days: 2)),
        ))['integrity_ok'],
        isTrue,
      );
    },
  );

  test('concurrent callers share one scheduled check', () async {
    await Future.wait([
      LocalDb.schemaHealth(now: start),
      LocalDb.schemaHealth(now: start),
    ]);
    expect(calls, ['PRAGMA integrity_check']);
  });

  test(
    'missing bookkeeping table is reported without requiring the cache',
    () async {
      final db = await LocalDb.instance;
      await db.execute('DROP TABLE compute_freshness');
      final health = await LocalDb.schemaHealth(now: start);
      expect(health['ok'], isFalse);
      expect(health['missing_tables'], contains('compute_freshness'));
      expect(health['integrity_ok'], isTrue);
    },
  );
}
