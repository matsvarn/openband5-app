import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/notify/notification_event.dart';
import 'package:openstrap_edge/notify/notification_prefs.dart';
import 'package:openstrap_edge/notify/notification_service.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final svc = NotificationService.instance;
  const tzChannel = MethodChannel('flutter_timezone');
  Future<String?> Function() tzLookup = () async => 'Europe/Berlin';

  void installTzMock() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(tzChannel, (call) async {
      if (call.method != 'getLocalTimezone') return null;
      return tzLookup();
    });
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    svc.invalidatePermissionCache();
    svc.debugRequestPermission = null;
    svc.debugProbePermission = null;
    svc.debugCancel = null;
    svc.debugZonedSchedule = null;
    tzLookup = () async => 'Europe/Berlin';
    installTzMock();
  });

  tearDown(() {
    svc.invalidatePermissionCache();
    svc.debugRequestPermission = null;
    svc.debugProbePermission = null;
    svc.debugCancel = null;
    svc.debugZonedSchedule = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(tzChannel, null);
  });

  Future<void> armDaily() => svc.scheduleDaily(
        id: NotificationService.idWindDown,
        category: NotifCategory.reminders,
        title: 't',
        body: 'b',
        hour: 22,
        minute: 0,
      );

  Future<void> armOnce() => svc.scheduleOnce(
        id: NotificationService.idWeeklyRecap,
        category: NotifCategory.reminders,
        title: 't',
        body: 'b',
        at: DateTime.now().add(const Duration(hours: 1)),
      );

  group('plugin schedule/cancel boundary', () {
    test('cancel swallows by default and throws when reporting', () async {
      svc.debugCancel = (_) async {
        throw Exception('plugin cancel failed');
      };
      await svc.cancel(NotificationService.idWeeklyRecap);
      await expectLater(
        svc.reportingScheduleFailures(
          () => svc.cancel(NotificationService.idWeeklyRecap),
        ),
        throwsA(
          predicate((e) => '$e'.contains('plugin cancel failed')),
        ),
      );
    });

    test('zonedSchedule swallows by default and throws when reporting',
        () async {
      svc.debugProbePermission = () async => true;
      svc.debugRequestPermission = () async => true;
      svc.debugZonedSchedule = () async {
        throw Exception('zonedSchedule failed');
      };
      await armDaily();
      await armOnce();
      await expectLater(
        svc.reportingScheduleFailures(armDaily),
        throwsA(
          predicate((e) => '$e'.contains('zonedSchedule failed')),
        ),
      );
      await expectLater(
        svc.reportingScheduleFailures(armOnce),
        throwsA(
          predicate((e) => '$e'.contains('zonedSchedule failed')),
        ),
      );
    });

    test('overlapping background cancel stays best-effort while strict throws',
        () async {
      final pluginGate = Completer<void>();
      var inFlight = 0;
      svc.debugCancel = (_) async {
        inFlight++;
        await pluginGate.future;
        throw Exception('plugin cancel failed');
      };

      final strict = svc.reportingScheduleFailures(
        () => svc.cancel(NotificationService.idWeeklyRecap),
      );
      final background = svc.cancel(NotificationService.idWindDown);
      expect(inFlight, 2);
      final strictDone = expectLater(
        strict,
        throwsA(
          predicate((e) => '$e'.contains('plugin cancel failed')),
        ),
      );
      pluginGate.complete();
      await strictDone;
      await background;
    });

    test('unreadable permission throws on strict schedule, denial skips',
        () async {
      var armed = 0;
      svc.debugZonedSchedule = () async {
        armed++;
      };

      svc.debugProbePermission = () async {
        throw Exception('permission unreadable');
      };
      await armDaily();
      await armOnce();
      await expectLater(
        svc.reportingScheduleFailures(armDaily),
        throwsA(
          predicate((e) => '$e'.contains('permission unreadable')),
        ),
      );
      await expectLater(
        svc.reportingScheduleFailures(armOnce),
        throwsA(
          predicate((e) => '$e'.contains('permission unreadable')),
        ),
      );
      await expectLater(
        svc.reportingScheduleFailures(
          () => svc.scheduleWeekly(
            id: NotificationService.idWeeklyRecap,
            category: NotifCategory.reminders,
            title: 't',
            body: 'b',
            weekday: DateTime.sunday,
            hour: 18,
            minute: 0,
          ),
        ),
        throwsA(
          predicate((e) => '$e'.contains('permission unreadable')),
        ),
      );
      expect(armed, 0);

      svc.debugProbePermission = () async => null;
      await armDaily();
      await expectLater(
        svc.reportingScheduleFailures(armDaily),
        throwsA(isA<StateError>()),
      );
      expect(armed, 0);

      svc.debugProbePermission = () async => false;
      await armDaily();
      await svc.reportingScheduleFailures(armDaily);
      expect(armed, 0);

      svc.debugProbePermission = () async => true;
      await svc.reportingScheduleFailures(armDaily);
      expect(armed, 1);
    });

    test('timezone lookup failure is strict after a successful resolve',
        () async {
      svc.debugProbePermission = () async => true;
      var armed = 0;
      svc.debugZonedSchedule = () async {
        armed++;
      };

      tzLookup = () async => 'Europe/Berlin';
      await svc.reportingScheduleFailures(armDaily);
      expect(tz.local.name, 'Europe/Berlin');
      expect(armed, 1);

      tzLookup = () async {
        throw PlatformException(
          code: 'unavailable',
          message: 'timezone lookup failed',
        );
      };
      await expectLater(
        svc.reportingScheduleFailures(armDaily),
        throwsA(
          predicate((e) => '$e'.contains('timezone lookup failed')),
        ),
      );
      expect(armed, 1);
      await svc.ensureTimezone();
      await armDaily();
    });
  });

  test('strict refresh surfaces a database open failure', () async {
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    await expectLater(app.refreshAiReminders(), throwsA(isA<Object>()));
    await app.debugEnsureRemindersScheduled();
  });

  group('AppState sqlite schedule pass', () {
    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      LocalDb.dbName = 'openstrap_notif_apply_strict.db';
      final dir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
    });

    tearDownAll(() async {
      await LocalDb.close();
      final dir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
    });

    test('plugin cancel failure propagates from refreshAiReminders', () async {
      svc.debugCancel = (_) async {
        throw Exception('plugin cancel failed');
      };
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await expectLater(
        app.refreshAiReminders(),
        throwsA(
          predicate((e) => '$e'.contains('plugin cancel failed')),
        ),
      );
      await app.debugEnsureRemindersScheduled();
    });

    test('missing crossday payload is empty, not apply failure', () async {
      svc.debugCancel = (_) async {};
      svc.debugZonedSchedule = () async {};
      svc.debugProbePermission = () async => true;
      svc.debugRequestPermission = () async => true;
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await app.refreshAiReminders();
    });

    test('corrupt crossday payload surfaces on strict refresh', () async {
      await LocalDb.putBaseline('crossday', '{not-json');
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await expectLater(app.refreshAiReminders(), throwsA(isA<FormatException>()));
      await app.debugEnsureRemindersScheduled();
      await LocalDb.putBaseline('crossday', '{}');
    });

    test('battery kick is not a fake apply failure', () async {
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await app.refreshBatteryThreshold(
        const NotificationPrefs(batteryAlertPct: 20),
      );
    });

    test('water reminder with passed prefs is local configure only', () async {
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await app.armWaterReminder(
        const NotificationPrefs(waterEnabled: true, waterIntervalMin: 60),
      );
    });

    test('unreadable permission after a successful read fails strict refresh',
        () async {
      await LocalDb.putBaseline('crossday', '{}');
      await const NotificationPrefs(waterEnabled: true).save();
      svc.debugCancel = (_) async {};
      var armed = 0;
      svc.debugZonedSchedule = () async {
        armed++;
      };

      svc.debugProbePermission = () async => true;
      expect(await svc.readPermissionStatus(), isTrue);

      svc.debugProbePermission = () async {
        throw Exception('permission unreadable');
      };
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await expectLater(
        app.refreshAiReminders(),
        throwsA(
          predicate((e) => '$e'.contains('permission unreadable')),
        ),
      );
      expect(armed, 0);
      await app.debugEnsureRemindersScheduled();
      expect(armed, 0);

      svc.debugProbePermission = () async => true;
      expect(await svc.readPermissionStatus(), isTrue);
      svc.debugProbePermission = () async => null;
      await expectLater(app.refreshAiReminders(), throwsA(isA<StateError>()));
      expect(armed, 0);
      await app.debugEnsureRemindersScheduled();
      expect(armed, 0);
    });

    test('known denial after a successful read is an intentional skip',
        () async {
      await LocalDb.putBaseline('crossday', '{}');
      await const NotificationPrefs(waterEnabled: true).save();
      svc.debugCancel = (_) async {};
      var armed = 0;
      svc.debugZonedSchedule = () async {
        armed++;
      };

      svc.debugProbePermission = () async => true;
      expect(await svc.readPermissionStatus(), isTrue);
      svc.debugProbePermission = () async => false;

      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await app.refreshAiReminders();
      expect(armed, 0);
    });

    test('timezone lookup failure after a successful resolve fails strict refresh',
        () async {
      await LocalDb.putBaseline('crossday', '{}');
      await const NotificationPrefs(waterEnabled: true).save();
      svc.debugCancel = (_) async {};
      var armed = 0;
      svc.debugZonedSchedule = () async {
        armed++;
      };
      svc.debugProbePermission = () async => true;
      svc.debugRequestPermission = () async => true;

      tzLookup = () async => 'Europe/Berlin';
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await app.refreshAiReminders();
      expect(tz.local.name, 'Europe/Berlin');
      expect(armed, greaterThan(0));
      final afterOk = armed;

      tzLookup = () async {
        throw PlatformException(
          code: 'unavailable',
          message: 'timezone lookup failed',
        );
      };
      await expectLater(
        app.refreshAiReminders(),
        throwsA(
          predicate((e) => '$e'.contains('timezone lookup failed')),
        ),
      );
      expect(armed, afterOk);
      await app.debugEnsureRemindersScheduled();
    });
  });
}
