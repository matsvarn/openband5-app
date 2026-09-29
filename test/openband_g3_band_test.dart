import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_protocol/openstrap_protocol.dart' as proto;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 9, 29, 12);
  final nowSec = now.millisecondsSinceEpoch ~/ 1000;
  late AppState app;
  late LocalOpenBandRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDb.close();
    LocalDb.dbName = 'openband_g3_band_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase('$dir/${LocalDb.dbName}');
    app = AppState.forTesting();
    repo = LocalOpenBandRepository(app, diagnosticsNow: () => now);
  });
  tearDown(() async {
    app.dispose();
    await LocalDb.close();
  });

  test('absent stored inputs stay absent, including first receipt', () async {
    final result = await repo.readBandDiagnostics();
    expect(result.model, isNull);
    expect(result.firmwareVersion, isNull);
    expect(result.deviceFamily, isNull);
    expect(result.lastStoredSampleAt, isNull);
    expect(result.backlog, isNull);
    expect(result.coverage, isNull);
    expect(result.battery, isNull);
    expect(await repo.readFirstTransferReceipt(), isNull);
  });

  test(
    'stored band state exposes pages, retained seconds and wrist-off events',
    () async {
      final db = await LocalDb.instance;
      await LocalDb.upsertDevice(adapterId: 'gen5', label: 'serial-123');
      await LocalDb.setCursor('rec_ts_hw', '${nowSec - 20}');
      await LocalDb.putBandBacklog(
        ts: nowSec - 300,
        written: 10,
        readPage: 7,
        trimPage: 5,
        capacity: 100,
        currentReadTs: nowSec - 3600,
        deviceFamily: 'gen5',
      );
      await db.insert('band_battery', {
        'device_id': '',
        'ts': nowSec - 60,
        'battery_pct': 67.4,
        'charging': 0,
        'source': 'hello',
      });
      for (final (counter, ts, device, source) in [
        (1, nowSec - 3600, '', null),
        (2, nowSec - 3599, '', null),
        (3, nowSec - 90000, '', null),
        (4, nowSec - 3500, 'other', 'other'),
      ]) {
        await db.insert('decoded_onehz', {
          'device_id': device,
          'ts_ms': ts * 1000,
          'rec_ts': ts,
          'counter': counter,
          'source': source,
        });
      }
      var result = await repo.readBandDiagnostics();
      expect(result.deviceFamily, 'gen5');
      expect(result.model, isNull); // Serial/family are not an exact model.
      expect(
        result.firmwareVersion,
        isNull,
      ); // HELLO firmware is not persisted.
      expect(
        result.lastStoredSampleAt,
        DateTime.fromMillisecondsSinceEpoch((nowSec - 20) * 1000),
      );
      expect(result.backlog!.heldPages, 5);
      expect(result.backlog!.unreadPages, 3);
      expect(result.coverage!.recordedSeconds, 2);
      expect(result.coverage!.coveragePercent, isNull);
      expect(result.coverage!.wristOffIntervals, isNull);
      expect(result.battery!.percent, 67);
      expect(result.battery!.charging, false);

      for (final (hex, id, ts) in [
        ('off', proto.EventId.wristOff, nowSec - 1800),
        ('on', proto.EventId.wristOn, nowSec - 1200),
      ]) {
        await db.insert('band_events', {
          'device_id': '',
          'hex': hex,
          'event_id': id,
          'name': hex,
          'ts': ts,
          'captured_at': ts,
        });
      }
      result = await repo.readBandDiagnostics();
      expect(result.coverage!.coveragePercent, isNull);
      expect(result.coverage!.wristOffIntervals, hasLength(1));
      expect(
        result.coverage!.wristOffIntervals!.single.start,
        DateTime.fromMillisecondsSinceEpoch((nowSec - 1800) * 1000),
      );
      expect(
        result.coverage!.wristOffIntervals!.single.end,
        DateTime.fromMillisecondsSinceEpoch((nowSec - 1200) * 1000),
      );
    },
  );

  test(
    'ring cursor ambiguity and generic batch ACK do not invent time receipt',
    () async {
      await LocalDb.putBandBacklog(
        ts: nowSec,
        written: 12,
        readPage: 12,
        trimPage: 12,
        capacity: 100,
      );
      final result = await repo.readBandDiagnostics();
      expect(result.backlog!.heldPages, isNull);
      expect(result.backlog!.unreadPages, isNull);
      await LocalDb.upsertSyncLedgerEntry(
        chunkId: 'batch:abc',
        kind: 'historical_batch',
        status: 'acked',
        ackedAt: now.millisecondsSinceEpoch,
        metaPatch: {'range_oldest': nowSec - 3600, 'range_newest': nowSec},
      );
      expect(await repo.readFirstTransferReceipt(), isNull);
    },
  );

  test('wrist-off events survive absent retained one-hertz rows', () async {
    final db = await LocalDb.instance;
    await db.insert('band_events', {
      'device_id': '',
      'hex': 'stored-off',
      'event_id': proto.EventId.wristOff,
      'name': 'wrist_off',
      'ts': nowSec - 300,
      'captured_at': nowSec - 300,
    });
    final result = await repo.readBandDiagnostics();
    expect(result.coverage!.recordedSeconds, isNull);
    expect(result.coverage!.coveragePercent, isNull);
    expect(result.coverage!.wristOffIntervals, hasLength(1));
    expect(result.coverage!.wristOffIntervals!.single.end, now);
  });

  test('synthetic band projection refuses unsupported detail', () async {
    Map<String, dynamic> fixture(String name) => Map<String, dynamic>.from(
      jsonDecode(
            File('docs/openband5/assets/fixtures/$name').readAsStringSync(),
          )
          as Map,
    );
    final synthetic = SyntheticOpenBandRepository.fromMaps(
      fixture('day-summary.json'),
      fixture('sleep-detail.json'),
      scenario: SyntheticScenario.g3Sample,
    );
    final result = await synthetic.readBandDiagnostics();
    expect(result.deviceFamily, 'gen5');
    expect(result.lastStoredSampleAt, DateTime(2026, 9, 29, 9, 38));
    expect(result.coverage, isNull);
    expect(result.backlog, isNull);
    expect(result.model, isNull);
    expect(result.firmwareVersion, isNull);
    expect(await synthetic.readFirstTransferReceipt(), isNull);
  });
}
