// checkSyncStaleness must not spend its 12-hour cooldown on a notification the
// shared gate dropped.
//
// The "your band hasn't synced" event is NotifCategory.device / normal
// priority, so NotificationCenter.emit refuses it whenever the device category
// is off or the wake lands inside quiet hours — and emit DROPS, it never
// queues. Writing the cooldown before the emit meant the backstop went silent
// for another 12 hours over a notification nobody ever saw. The headless wake
// this runs from is typically an overnight one, i.e. exactly the refused case.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_protocol/openstrap_protocol.dart' show EventId;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/notify/notification_center.dart';
import 'package:openstrap_edge/notify/notification_event.dart';
import 'package:openstrap_edge/notify/notification_service.dart';
import 'package:openstrap_edge/ble/ios_ble_restore.dart';
import 'package:openstrap_edge/sync/band_ownership.dart';
import 'package:openstrap_edge/sync/file_log.dart';
import 'package:openstrap_edge/sync/ios_bg_task.dart';
import 'package:openstrap_edge/sync/background_sync.dart';

const _kCooldown = 'last_staleness_notified_ms';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_bgsync_staleness_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  var now = DateTime(2026, 9, 30, 9, 45);
  final events = <NotificationEvent>[];
  final logs = <String>[];
  final prompts = <bool>[];
  setUp(() async {
    now = DateTime(2026, 9, 30, 9, 45);
    events.clear();
    logs.clear();
    prompts.clear();
    SharedPreferences.setMockInitialValues({
      'notif_device': true,
      'notif_quiet_enabled': false,
    });
    syncStalenessNow = () => now;
    syncWristOffSpans = LocalDb.wristOffSpans;
    syncChargingSpans = LocalDb.chargingSpans;
    backgroundSyncLogSink = (line) async {
      logs.add(line);
    };
    NotificationCenter.instance.presentSink =
        (event, {bool allowPermissionPrompt = true}) async {
          events.add(event);
          prompts.add(allowPermissionPrompt);
          return true;
        };
    final db = await LocalDb.instance;
    await db.delete('band_events');
    await db.delete('notif_fired');
  });
  tearDown(() {
    syncStalenessNow = DateTime.now;
    syncWristOffSpans = LocalDb.wristOffSpans;
    syncChargingSpans = LocalDb.chargingSpans;
    backgroundSyncLogSink = FileLog.write;
    NotificationCenter.instance.presentSink =
        NotificationService.instance.presentEvent;
    BandOwnership.resetForTest();
    IosBleRestore.foregroundActive = false;
    IosBgTask.foregroundPull = null;
  });

  Future<int> cursor(DateTime at) async {
    final sec = at.millisecondsSinceEpoch ~/ 1000;
    await LocalDb.setCursor('rec_ts_hw', '$sec');
    return sec;
  }

  test(
    'three hours triggers German local-time copy through the gate',
    () async {
      final sec = await cursor(DateTime(2026, 9, 30, 6, 45));
      await checkSyncStaleness();
      expect(events, hasLength(1));
      expect(events.single.title, 'Keine neuen Banddaten');
      expect(
        events.single.body,
        'Seit 06:45 Uhr kam nichts mehr an. '
        'Doppeltippe auf das Band und öffne OpenBand.',
      );
      expect(
        events.single.dedupeKey,
        'sync_stale:$sec:${now.millisecondsSinceEpoch ~/ 1000 ~/ (12 * 3600)}',
      );
      expect(events.single.priority, NotifPriority.normal);
      expect(prompts, [false]);
    },
  );

  test('older local date is included in the notification', () async {
    await cursor(DateTime(2026, 9, 26, 23, 15));
    await checkSyncStaleness();
    expect(
      events.single.body,
      'Seit 26.09., 23:15 Uhr kam nichts mehr an. '
      'Doppeltippe auf das Band und öffne OpenBand.',
    );
  });

  test(
    'same stall can notify twice on one day, never within 12 hours',
    () async {
      now = DateTime(2026, 9, 30, 0, 15);
      await cursor(DateTime(2026, 9, 26, 20));
      await checkSyncStaleness();
      now = now.add(const Duration(hours: 12) - const Duration(seconds: 1));
      await checkSyncStaleness();
      expect(events, hasLength(1));
      now = now.add(const Duration(seconds: 1));
      await checkSyncStaleness();
      expect(events, hasLength(2));
      expect(events.map((e) => e.dedupeKey).toSet(), hasLength(2));
    },
  );

  for (final offWrist in [true, false]) {
    test(
      '${offWrist ? "off wrist" : "charging"} span reaching now suppresses stale alert',
      () async {
        final lo = await cursor(now.subtract(const Duration(days: 4)));
        final hi = now.millisecondsSinceEpoch ~/ 1000;
        var queried = false;
        Future<List<List<int>>> spans(
          int start,
          int end, {
          required String deviceId,
        }) async {
          queried = true;
          expect([start, end], [lo, hi]);
          expect(deviceId, LocalDb.kPrimaryDeviceId);
          return [
            [lo, hi],
          ];
        }

        if (offWrist) {
          syncWristOffSpans = spans;
        } else {
          syncChargingSpans = spans;
        }
        await checkSyncStaleness();
        expect(events, isEmpty);
        expect(queried, isTrue);
        expect(logs, contains(contains(offWrist ? 'off wrist' : 'charging')));
        expect(
          (await SharedPreferences.getInstance()).getInt(_kCooldown),
          isNull,
        );
      },
    );
  }

  for (final offWrist in [true, false]) {
    test(
      'persisted unterminated ${offWrist ? "wrist-off" : "charging"} state suppresses alert',
      () async {
        final lo = await cursor(now.subtract(const Duration(days: 4)));
        final db = await LocalDb.instance;
        await db.insert('band_events', {
          'device_id': LocalDb.kPrimaryDeviceId,
          'hex': 'synthetic-state',
          'event_id': offWrist ? EventId.wristOff : EventId.chargingOn,
          'name': 'synthetic',
          'ts': lo - 60,
          'captured_at': lo,
        });
        await checkSyncStaleness();
        expect(events, isEmpty);
      },
    );
  }

  test('ended off-wrist and charging spans do not suppress', () async {
    final lo = await cursor(now.subtract(const Duration(days: 4)));
    syncWristOffSpans = (start, end, {required deviceId}) async => [
      [lo, end - 1],
    ];
    syncChargingSpans = (start, end, {required deviceId}) async => [
      [lo, end - 1],
    ];
    await checkSyncStaleness();
    expect(events, hasLength(1));
  });

  test(
    'headless ownership skip still checks staleness without prompting',
    () async {
      await cursor(now.subtract(const Duration(days: 4)));
      BandOwnership.markForegroundIntent(true);
      expect(await runHeadlessSync(), isTrue);
      expect(events, hasLength(1));
      expect(prompts, [false]);
    },
  );

  for (final pullThrows in [false, true]) {
    test(
      'iOS foreground pull ${pullThrows ? "failure" : "completion"} still checks staleness',
      () async {
        await cursor(now.subtract(const Duration(days: 4)));
        IosBleRestore.foregroundActive = true;
        var pulled = false;
        IosBgTask.foregroundPull = () async {
          pulled = true;
          expect(events, isEmpty);
          if (pullThrows) throw StateError('synthetic pull failure');
        };
        expect(await IosBgTask.debugRun(syncOnly: true), isTrue);
        expect(pulled, isTrue);
        expect(events, hasLength(1));
        expect(prompts, [false]);
      },
    );
  }

  test('a dropped staleness alert leaves the cooldown unspent', () async {
    // Device notifications switched off — the same early return quiet hours
    // takes, without depending on the wall clock the test happens to run at.
    SharedPreferences.setMockInitialValues({'notif_device': false});
    // Four days since the last record: well past the notify tier.
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await LocalDb.setCursor('rec_ts_hw', '${nowSec - 4 * 24 * 3600}');

    await checkSyncStaleness();

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getInt(_kCooldown), isNull,
        reason: 'the cooldown belongs to an alert that was actually shown');
  });

  test('a band that has never synced is not stale', () async {
    SharedPreferences.setMockInitialValues({});
    await LocalDb.setCursor('rec_ts_hw', '0');
    await checkSyncStaleness();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getInt(_kCooldown), isNull);
  });
}
