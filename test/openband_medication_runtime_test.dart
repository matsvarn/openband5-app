// Medication runtime: typed /meds route, reminder policy, unknown vs empty,
// revision-aware instants, DST omit, saved-vs-rearm, serial schedule.
// No real plugin, Bluetooth, or Health calls — temp SQLite + debug hooks.

import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ai/ai_prefs.dart';
import 'package:openstrap_edge/app.dart';
import 'package:openstrap_edge/coach/coach_config.dart';
import 'package:openstrap_edge/coach/coach_engine.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/data/med_store.dart';
import 'package:openstrap_edge/notify/notification_center.dart';
import 'package:openstrap_edge/notify/notification_prefs.dart';
import 'package:openstrap_edge/notify/notification_service.dart';
import 'package:openstrap_edge/notify/tap_router.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/openband/release_scope.dart';
import 'package:openstrap_edge/openband/medication.dart';
import 'package:openstrap_edge/openband/medication_data.dart';
import 'package:openstrap_edge/openband/nutrition_route.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/ui2/app_shell.dart' show ShellDomain;
import 'package:openstrap_edge/ui2/screens/day_timeline.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

MedReminderInstant _instant(
  DateTime at, {
  String key = 'a',
  String? date,
  int? slotMin,
}) =>
    (
      key: key,
      date: date ??
          '${at.year.toString().padLeft(4, '0')}-'
              '${at.month.toString().padLeft(2, '0')}-'
              '${at.day.toString().padLeft(2, '0')}',
      slotMin: slotMin ?? at.hour * 60 + at.minute,
      at: at,
    );

Future<Database> _openMedDb(String name) async {
  final path = p.join(await databaseFactory.getDatabasesPath(), name);
  await databaseFactory.deleteDatabase(path);
  final db = await databaseFactory.openDatabase(path);
  await createMedTables(db, now: DateTime(2026, 3, 1, 8));
  return db;
}

const _dailyEightTwenty = [
  MedicationScheduleSlot(minuteOfDay: 8 * 60, weekdays: []),
  MedicationScheduleSlot(minuteOfDay: 20 * 60, weekdays: []),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('typed /meds route', () {
    test('pushes OpenBandMedications over Journal; other routes unchanged', () {
      expect(domainForRoute(kRouteMeds), ShellDomain.wellness);
      expect(resolveTapRoute(kRouteMeds).screen, kRouteMeds);
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      final screen = screenForRoute(
        kRouteMeds,
        repository: LocalOpenBandRepository(app),
      );
      expect(screen, isA<OpenBandMedications>());
      expect((screen! as OpenBandMedications).day, isNotEmpty);
      expect(screenForRoute(kRouteWater), isA<OpenBandNutritionRoute>());
      expect(screenForRoute(kRouteJournalCompose), isNotNull);
      expect(domainForRoute(kRouteWater), ShellDomain.wellness);
      expect(resolveTapRoute('/nope').tab, 0);
      expect(resolveTapRoute('/nope').screen, isNull);
      expect(screenForRoute('/nope'), isNull);
    });
  });

  group('medReminderPlan privacy and caps', () {
    final now = DateTime(2026, 8, 20, 10);
    const on = NotificationPrefs(medsEnabled: true);

    test('caps 12, ids 2300+, lock screen names no drug', () {
      final many = [
        for (var i = 0; i < 16; i++)
          _instant(now.add(Duration(hours: i + 1)), key: 'SecretDrug$i'),
      ];
      final plan = NotificationCenter.medReminderPlan(on, many, now: now);
      expect(plan.length, NotificationService.maxMedSlots);
      for (var i = 0; i < plan.length; i++) {
        expect(plan[i].id, NotificationService.idMedsBase + i);
        expect(plan[i].title, 'Medication');
        expect(plan[i].body, 'A dose is due.');
        expect(plan[i].title, isNot(contains('SecretDrug')));
        expect(plan[i].body, isNot(contains('SecretDrug')));
        expect(plan[i].route, kRouteMeds);
      }
    });
  });

  group('unknown vs empty vs off', () {
    final svc = NotificationService.instance;
    const tzChannel = MethodChannel('flutter_timezone');
    final cancelled = <int>[];
    final now = DateTime(2026, 8, 20, 10);
    const on = NotificationPrefs(
      medsEnabled: true,
      remindersEnabled: false,
      waterEnabled: false,
      checkInEnabled: false,
      windDownEnabled: false,
      alarmNightCheckEnabled: false,
    );
    const off = NotificationPrefs(
      medsEnabled: false,
      remindersEnabled: false,
      waterEnabled: false,
      checkInEnabled: false,
      windDownEnabled: false,
      alarmNightCheckEnabled: false,
    );

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      NotificationCenter.instance.releaseReduced = false;
      cancelled.clear();
      svc.invalidatePermissionCache();
      svc.debugProbePermission = () async => true;
      svc.debugRequestPermission = () async => true;
      svc.debugCancel = (id) async => cancelled.add(id);
      svc.debugZonedSchedule = () async {};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(tzChannel, (call) async {
        if (call.method != 'getLocalTimezone') return null;
        return 'Europe/Berlin';
      });
    });

    tearDown(() {
      NotificationCenter.instance.releaseReduced = kOpenBandReleaseReduced;
      svc.debugProbePermission = null;
      svc.debugRequestPermission = null;
      svc.debugCancel = null;
      svc.debugZonedSchedule = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(tzChannel, null);
    });

    test('null instants preserve the med band', () async {
      await NotificationCenter.instance.scheduleStandingReminders(
        on,
        medInstants: [_instant(now.add(const Duration(hours: 2)))],
        now: now,
      );
      cancelled.clear();
      await NotificationCenter.instance.scheduleStandingReminders(
        on,
        medInstants: null,
        now: now,
      );
      expect(
        cancelled.where(
          (id) =>
              id >= NotificationService.idMedsBase &&
              id < NotificationService.idMedsBase +
                  NotificationService.maxMedSlots,
        ),
        isEmpty,
      );
    });

    test('known empty cancels the med band', () async {
      await NotificationCenter.instance.scheduleStandingReminders(
        on,
        medInstants: const [],
        now: now,
      );
      expect(cancelled, contains(NotificationService.idMedsBase));
    });

    test('switch off cancels even without a schedule', () async {
      await NotificationCenter.instance.scheduleStandingReminders(
        off,
        medInstants: null,
        now: now,
      );
      expect(cancelled, contains(NotificationService.idMedsBase));
    });

    test('overlapping schedules stay serial', () async {
      var depth = 0;
      var maxDepth = 0;
      svc.debugCancel = (id) async {
        depth++;
        maxDepth = max(maxDepth, depth);
        await Future<void>.delayed(const Duration(milliseconds: 8));
        cancelled.add(id);
        depth--;
      };
      await Future.wait([
        NotificationCenter.instance.scheduleStandingReminders(
          on,
          medInstants: [_instant(now.add(const Duration(hours: 1)), key: 'a')],
          now: now,
        ),
        NotificationCenter.instance.scheduleStandingReminders(
          on,
          medInstants: [_instant(now.add(const Duration(hours: 2)), key: 'b')],
          now: now,
        ),
      ]);
      expect(maxDepth, 1);
    });

    test('reduced release cancels parked ids and does not rearm them', () async {
      var armed = 0;
      svc.debugZonedSchedule = () async {
        armed++;
      };
      final enabled = NotificationPrefs(
        medsEnabled: true,
        remindersEnabled: true,
        waterEnabled: true,
        waterIntervalMin: 60,
        checkInEnabled: true,
        windDownEnabled: true,
        alarmNightCheckEnabled: false,
        movementEnabled: true,
        stepGoalEnabled: true,
        recoveryEnabled: true,
      );
      await NotificationCenter.instance.scheduleStandingReminders(
        enabled,
        bedtimeMinOfDay: 23 * 60,
        weeklyFinding: 'A week happened',
        checkInDoneToday: false,
        medInstants: null,
        armedTonight: false,
        now: DateTime(2026, 8, 20, 10),
        releaseReduced: true,
      );
      expect(cancelled, contains(NotificationService.idWeeklyRecap));
      expect(cancelled, contains(NotificationService.idWindDown));
      expect(cancelled, contains(NotificationService.idCheckIn));
      expect(cancelled, contains(NotificationService.idWaterBase));
      expect(cancelled, contains(NotificationService.idMedsBase));
      expect(cancelled, contains(NotificationService.idAlarmNightCheck));
      expect(
        cancelled,
        isNot(contains(NotificationService.idStillness)),
      );
      await NotificationCenter.instance.scheduleAiReminders(
        enabled,
        const AiPrefs(),
        aiConfigured: true,
        bedtimeMinOfDay: 23 * 60,
        journalDoneToday: false,
        sweepHeadline: 'A finding',
        releaseReduced: true,
      );
      expect(cancelled, contains(NotificationService.idMorningBrief));
      expect(cancelled, contains(NotificationService.idEveningBrief));
      expect(cancelled, contains(NotificationService.idJournalLog));
      expect(armed, 0);
    });
  });

  group('revision-aware upcoming instants', () {
    late Database db;

    setUp(() async {
      db = await _openMedDb(
        'med_runtime_${DateTime.now().microsecondsSinceEpoch}.db',
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('taken and skipped drop out; end stops future; edit moves the slot',
        () async {
      final now = DateTime(2026, 8, 20, 10);
      await MedDb.commitPlan(
        db,
        const MedicationPlanDraft(
          create: true,
          key: 'd3',
          name: 'Vitamin D',
          schedule: _dailyEightTwenty,
        ),
        now: DateTime(2026, 8, 19, 7),
      );
      var upcoming = await MedDb.upcomingReminderInstants(
        db,
        now: now,
        horizonDays: 3,
      );
      expect(
        upcoming.any((s) => s.date == '2026-08-20' && s.slotMin == 20 * 60),
        isTrue,
      );
      expect(
        upcoming.any((s) => s.date == '2026-08-20' && s.slotMin == 8 * 60),
        isFalse,
      );

      await MedDb.markDose(
        db,
        const MedicationEntryDraft(
          key: 'd3',
          date: '2026-08-20',
          slotMin: 20 * 60,
          answer: MedicationEntryAnswer.taken,
        ),
        now: DateTime(2026, 8, 20, 20, 1),
      );
      upcoming = await MedDb.upcomingReminderInstants(
        db,
        now: DateTime(2026, 8, 20, 20, 2),
        horizonDays: 3,
      );
      expect(
        upcoming.any((s) => s.date == '2026-08-20' && s.slotMin == 20 * 60),
        isFalse,
      );

      await MedDb.markDose(
        db,
        const MedicationEntryDraft(
          key: 'd3',
          date: '2026-08-21',
          slotMin: 8 * 60,
          answer: MedicationEntryAnswer.skipped,
        ),
        now: DateTime(2026, 8, 21, 8, 1),
      );
      upcoming = await MedDb.upcomingReminderInstants(
        db,
        now: DateTime(2026, 8, 21, 7),
        horizonDays: 3,
      );
      expect(
        upcoming.any((s) => s.date == '2026-08-21' && s.slotMin == 8 * 60),
        isFalse,
      );

      await MedDb.commitPlan(
        db,
        const MedicationPlanDraft(
          create: false,
          key: 'd3',
          name: 'Vitamin D',
          schedule: _dailyEightTwenty,
          active: false,
        ),
        now: DateTime(2026, 8, 21, 12),
      );
      upcoming = await MedDb.upcomingReminderInstants(
        db,
        now: DateTime(2026, 8, 21, 12),
        horizonDays: 3,
      );
      expect(upcoming, isEmpty);

      await MedDb.commitPlan(
        db,
        const MedicationPlanDraft(
          create: false,
          key: 'd3',
          name: 'Vitamin D',
          schedule: [
            MedicationScheduleSlot(minuteOfDay: 9 * 60, weekdays: []),
          ],
        ),
        now: DateTime(2026, 8, 21, 12, 5),
      );
      upcoming = await MedDb.upcomingReminderInstants(
        db,
        now: DateTime(2026, 8, 21, 12, 5),
        horizonDays: 3,
      );
      expect(upcoming.every((s) => s.slotMin == 9 * 60), isTrue);
      expect(upcoming, isNotEmpty);
    });

    test('spring gap omitted, valid 08:00 same wall; autumn fold omitted',
        () async {
      await MedDb.commitPlan(
        db,
        const MedicationPlanDraft(
          create: true,
          key: 'dst',
          name: 'DST',
          schedule: [
            MedicationScheduleSlot(minuteOfDay: 2 * 60 + 30, weekdays: []),
            MedicationScheduleSlot(minuteOfDay: 8 * 60, weekdays: []),
          ],
        ),
        now: DateTime(2026, 3, 1, 8),
      );
      const berlin = 'Europe/Berlin';
      final spring = await MedDb.upcomingReminderInstants(
        db,
        now: DateTime(2026, 3, 29, 0, 10),
        horizonDays: 3,
        zone: berlin,
      );
      expect(
        spring.any((s) => s.date == '2026-03-29' && s.slotMin == 2 * 60 + 30),
        isFalse,
        reason: 'nonexistent 02:30 must not shift',
      );
      final eight = spring.where(
        (s) => s.date == '2026-03-29' && s.slotMin == 8 * 60,
      );
      expect(eight, hasLength(1));
      expect(eight.single.at.hour, 8);
      expect(eight.single.at.minute, 0);

      final autumn = await MedDb.upcomingReminderInstants(
        db,
        now: DateTime(2026, 10, 25, 0, 10),
        horizonDays: 3,
        zone: berlin,
      );
      expect(
        autumn.any((s) => s.date == '2026-10-25' && s.slotMin == 2 * 60 + 30),
        isFalse,
        reason: 'ambiguous 02:30 must not double-fire',
      );
    });
  });

  group('committed write vs reminder refresh failure', () {
    final svc = NotificationService.instance;
    const tzChannel = MethodChannel('flutter_timezone');

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      svc.invalidatePermissionCache();
      svc.debugProbePermission = () async => true;
      svc.debugRequestPermission = () async => true;
      svc.debugCancel = (_) async {};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(tzChannel, (call) async {
        if (call.method != 'getLocalTimezone') return null;
        return 'UTC';
      });
      await LocalDb.close();
      LocalDb.dbName = 'med_runtime_apply_${DateTime.now().microsecondsSinceEpoch}.db';
      final dir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase('$dir/${LocalDb.dbName}');
    });

    tearDown(() async {
      svc.debugProbePermission = null;
      svc.debugRequestPermission = null;
      svc.debugCancel = null;
      svc.debugZonedSchedule = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(tzChannel, null);
      await LocalDb.close();
    });

    test('plugin IO error surfaces; the plan row stays', () async {
      final db = await LocalDb.instance;
      await MedDb.commitPlan(
        db,
        const MedicationPlanDraft(
          create: true,
          key: 'keep',
          name: 'Keep me',
          schedule: [
            MedicationScheduleSlot(minuteOfDay: 20 * 60, weekdays: []),
          ],
        ),
        now: DateTime(2026, 8, 20, 7),
      );
      await const NotificationPrefs(
        medsEnabled: true,
        remindersEnabled: false,
        waterEnabled: false,
        checkInEnabled: false,
        windDownEnabled: false,
        alarmNightCheckEnabled: false,
        stepGoalEnabled: false,
      ).save();
      svc.debugZonedSchedule = () async {
        throw Exception('plugin schedule failed');
      };
      final app = AppState.forTesting();
      app.debugNow = () => DateTime(2026, 8, 20, 10);
      addTearDown(app.dispose);
      await expectLater(app.refreshAiReminders(), throwsA(isA<Object>()));
      final plans = await MedDb.readPlans(db);
      expect(plans.single.name, 'Keep me');
    });

    test('coach write is durable when reminder refresh fails', () async {
      await LocalDb.instance;
      final repo = LocalRepositoryImpl(getProfileMap: () => const {});
      var refreshes = 0;
      final engine = CoachEngine(
        config: CoachConfig(),
        api: repo,
        onMedicationMutated: () async {
          refreshes++;
          throw StateError('plugin failed');
        },
      );
      final raw = await engine.debugRunTool(
        'add_medication',
        {'name': 'Vitamin D', 'time': '20:00'},
        confirm: (_) async => true,
      );
      final j = jsonDecode(raw) as Map<String, dynamic>;
      expect(j['saved'], true);
      expect(j['reminders_updated'], false);
      expect('$j', contains('plugin failed'));
      expect(refreshes, 1);
      final plans = await MedDb.readPlans(await LocalDb.instance);
      expect(plans.any((p) => p.name == 'Vitamin D'), isTrue);
    });

    test('mark_medication stays saved when reminder refresh fails', () async {
      final db = await LocalDb.instance;
      await MedDb.commitPlan(
        db,
        const MedicationPlanDraft(
          create: true,
          key: 'mark-me',
          name: 'Zinc',
          schedule: [
            MedicationScheduleSlot(minuteOfDay: 20 * 60, weekdays: []),
          ],
        ),
        now: DateTime(2026, 8, 20, 7),
      );
      final repo = LocalRepositoryImpl(getProfileMap: () => const {});
      final engine = CoachEngine(
        config: CoachConfig(),
        api: repo,
        onMedicationMutated: () async {
          throw StateError('rearm failed');
        },
      );
      final raw = await engine.debugRunTool(
        'mark_medication',
        {'name': 'Zinc', 'state': 'taken', 'date': '2026-08-20', 'time': '20:00'},
        confirm: (_) async => true,
      );
      final j = jsonDecode(raw) as Map<String, dynamic>;
      expect(j['saved'], true);
      expect(j['reminders_updated'], false);
      expect(j['reminders_error'], contains('rearm failed'));
      final day = await MedDb.readDay(
        db,
        '2026-08-20',
        now: DateTime(2026, 8, 20, 20, 1),
      );
      expect(
        day.entries.any((e) => e.status == MedicationSlotStatus.taken),
        isTrue,
      );
    });

    test('unreadable meds preserve the band then fail the refresh', () async {
      final db = await LocalDb.instance;
      await MedDb.commitPlan(
        db,
        const MedicationPlanDraft(
          create: true,
          key: 'keep',
          name: 'Keep me',
          schedule: [
            MedicationScheduleSlot(minuteOfDay: 20 * 60, weekdays: []),
          ],
        ),
        now: DateTime(2026, 8, 20, 7),
      );
      await const NotificationPrefs(
        medsEnabled: true,
        remindersEnabled: false,
        waterEnabled: false,
        checkInEnabled: false,
        windDownEnabled: false,
        alarmNightCheckEnabled: false,
        stepGoalEnabled: false,
      ).save();
      svc.debugZonedSchedule = () async {};
      final cancelled = <int>[];
      svc.debugCancel = (id) async => cancelled.add(id);
      final app = AppState.forTesting();
      app.debugNow = () => DateTime(2026, 8, 20, 10);
      addTearDown(app.dispose);
      await app.refreshAiReminders();
      await db.update('med_plan_revision', {'schedule_json': '[{}]'});
      cancelled.clear();
      await expectLater(
        app.refreshAiReminders(),
        throwsA(
          predicate((e) => '$e'.contains('Medication reminder read failed')),
        ),
      );
      expect(
        cancelled.where(
          (id) =>
              id >= NotificationService.idMedsBase &&
              id <
                  NotificationService.idMedsBase +
                      NotificationService.maxMedSlots,
        ),
        isEmpty,
        reason: 'unreadable must preserve already-armed med slots',
      );
      final heads = await db.query(
        'med_def',
        where: 'key = ?',
        whereArgs: ['keep'],
      );
      expect(heads, hasLength(1));
      expect(heads.single['label'], 'Keep me');
      expect(heads.single['active'], 1);
      await expectLater(
        MedDb.readPlans(db, activeOnly: false),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('unreadable schedule'),
          ),
        ),
      );
    });
  });

  group('unpaired resume and buzzer vs plugin failure', () {
    final svc = NotificationService.instance;
    const tzChannel = MethodChannel('flutter_timezone');

    Future<void> quietMeds({bool enabled = true}) => NotificationPrefs(
          medsEnabled: enabled,
          remindersEnabled: false,
          waterEnabled: false,
          checkInEnabled: false,
          windDownEnabled: false,
          alarmNightCheckEnabled: false,
          stepGoalEnabled: false,
        ).save();

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      svc.invalidatePermissionCache();
      svc.debugProbePermission = () async => true;
      svc.debugRequestPermission = () async => true;
      svc.debugCancel = (_) async {};
      svc.debugZonedSchedule = () async {};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(tzChannel, (call) async {
        if (call.method != 'getLocalTimezone') return null;
        return 'UTC';
      });
      await LocalDb.close();
      LocalDb.dbName =
          'med_runtime_resume_${DateTime.now().microsecondsSinceEpoch}.db';
      final dir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase('$dir/${LocalDb.dbName}');
    });

    tearDown(() async {
      svc.debugProbePermission = null;
      svc.debugRequestPermission = null;
      svc.debugCancel = null;
      svc.debugZonedSchedule = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(tzChannel, null);
      await LocalDb.close();
    });

    test('unpaired resume still renews the 3-day med window, no pair required', () async {
      final now = DateTime.now();
      final at = now.add(const Duration(hours: 2));
      await MedDb.commitPlan(
        await LocalDb.instance,
        MedicationPlanDraft(
          create: true,
          key: 'unpaired',
          name: 'Keep me',
          schedule: [
            MedicationScheduleSlot(
              minuteOfDay: at.hour * 60 + at.minute,
              weekdays: const [],
            ),
          ],
        ),
        now: now.subtract(const Duration(days: 1)),
      );
      await quietMeds();
      var scheduled = 0;
      svc.debugZonedSchedule = () async => scheduled++;
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      expect(app.isPaired, isFalse);
      await app.runCadenceChecks();
      expect(scheduled, greaterThan(0));
      expect(app.debugMedBuzzerSlotInstants, isNotEmpty);
    });

    test('ending a plan clears the buzzer even if OS cancel throws', () async {
      final now = DateTime.now();
      final at = now.add(const Duration(hours: 2));
      final db = await LocalDb.instance;
      await MedDb.commitPlan(
        db,
        MedicationPlanDraft(
          create: true,
          key: 'end-me',
          name: 'Keep me',
          schedule: [
            MedicationScheduleSlot(
              minuteOfDay: at.hour * 60 + at.minute,
              weekdays: const [],
            ),
          ],
        ),
        now: now.subtract(const Duration(hours: 1)),
      );
      await quietMeds();
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await app.refreshAiReminders();
      expect(app.debugMedBuzzerSlotInstants, isNotEmpty);
      await MedDb.commitPlan(
        db,
        MedicationPlanDraft(
          create: false,
          key: 'end-me',
          name: 'Keep me',
          schedule: [
            MedicationScheduleSlot(
              minuteOfDay: at.hour * 60 + at.minute,
              weekdays: const [],
            ),
          ],
          active: false,
        ),
        now: now,
      );
      svc.debugCancel = (_) async {
        throw Exception('plugin cancel failed');
      };
      await expectLater(app.refreshAiReminders(), throwsA(isA<Object>()));
      expect(app.debugMedBuzzerSlotInstants, isEmpty);
    });

    test('a known new plan updates the buzzer even if OS arm throws', () async {
      final now = DateTime.now();
      final first = now.add(const Duration(hours: 2));
      final second = now.add(const Duration(hours: 4));
      final db = await LocalDb.instance;
      await MedDb.commitPlan(
        db,
        MedicationPlanDraft(
          create: true,
          key: 'move',
          name: 'Keep me',
          schedule: [
            MedicationScheduleSlot(
              minuteOfDay: first.hour * 60 + first.minute,
              weekdays: const [],
            ),
          ],
        ),
        now: now.subtract(const Duration(hours: 1)),
      );
      await quietMeds();
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await app.refreshAiReminders();
      expect(app.debugMedBuzzerSlotInstants, isNotEmpty);
      await MedDb.commitPlan(
        db,
        MedicationPlanDraft(
          create: false,
          key: 'move',
          name: 'Keep me',
          schedule: [
            MedicationScheduleSlot(
              minuteOfDay: second.hour * 60 + second.minute,
              weekdays: const [],
            ),
          ],
        ),
        now: now,
      );
      svc.debugZonedSchedule = () async {
        throw Exception('plugin schedule failed');
      };
      await expectLater(app.refreshAiReminders(), throwsA(isA<Object>()));
      final armed = app.debugMedBuzzerSlotInstants;
      expect(armed, isNotEmpty);
      expect(armed.first.hour, second.hour);
      expect(armed.first.minute, second.minute);
    });

    test('prefs off clears the buzzer even if plugin cancel throws', () async {
      final now = DateTime.now();
      final at = now.add(const Duration(hours: 2));
      await MedDb.commitPlan(
        await LocalDb.instance,
        MedicationPlanDraft(
          create: true,
          key: 'off',
          name: 'Keep me',
          schedule: [
            MedicationScheduleSlot(
              minuteOfDay: at.hour * 60 + at.minute,
              weekdays: const [],
            ),
          ],
        ),
        now: now.subtract(const Duration(hours: 1)),
      );
      await quietMeds();
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await app.refreshAiReminders();
      expect(app.debugMedBuzzerSlotInstants, isNotEmpty);
      await quietMeds(enabled: false);
      svc.debugCancel = (_) async {
        throw Exception('plugin cancel failed');
      };
      await expectLater(app.refreshAiReminders(), throwsA(isA<Object>()));
      expect(app.debugMedBuzzerSlotInstants, isEmpty);
    });

    test('unknown read preserves buzzer timers', () async {
      final now = DateTime.now();
      final at = now.add(const Duration(hours: 2));
      final db = await LocalDb.instance;
      await MedDb.commitPlan(
        db,
        MedicationPlanDraft(
          create: true,
          key: 'keep',
          name: 'Keep me',
          schedule: [
            MedicationScheduleSlot(
              minuteOfDay: at.hour * 60 + at.minute,
              weekdays: const [],
            ),
          ],
        ),
        now: now.subtract(const Duration(hours: 1)),
      );
      await quietMeds();
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await app.refreshAiReminders();
      final before = List<DateTime>.from(app.debugMedBuzzerSlotInstants);
      expect(before, isNotEmpty);
      await db.update('med_plan_revision', {'schedule_json': '[{}]'});
      await expectLater(
        app.refreshAiReminders(),
        throwsA(
          predicate((e) => '$e'.contains('Medication reminder read failed')),
        ),
      );
      expect(app.debugMedBuzzerSlotInstants, before);
    });
  });

  group('timeline dose titles', () {
    test('frozen snapshot wins; unknown history is generic Medication', () {
      expect(
        medicationTimelineTitle(
          const MedicationDayEntry(
            key: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
            date: '2026-08-15',
            slotMin: 480,
            status: MedicationSlotStatus.taken,
            snapshotLabel: 'Vitamin D',
          ),
        ),
        'Vitamin D',
      );
      expect(
        medicationTimelineTitle(
          const MedicationDayEntry(
            key: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
            date: '2026-08-15',
            slotMin: 480,
            status: MedicationSlotStatus.taken,
          ),
        ),
        'Medication',
      );
      expect(
        medicationTimelineTitle(
          const MedicationDayEntry(
            key: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
            date: '2026-08-15',
            slotMin: 480,
            status: MedicationSlotStatus.taken,
            snapshotLabel: '  ',
          ),
        ),
        'Medication',
      );
    });
  });
}
