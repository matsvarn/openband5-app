import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:openstrap_edge/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/models/payloads.dart';
import 'package:openstrap_edge/widget/widget_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, Object?> written;
  late int sampleAt;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openband_g3_widgets_snapshot_test.db';
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
  });
  tearDownAll(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
  });
  setUp(() async {
    written = {};
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('home_widget'), (
      call,
    ) async {
      if (call.method == 'saveWidgetData') {
        final args = (call.arguments as Map).cast<String, Object?>();
        written[args['id'] as String] = args['data'];
      }
      if (call.method == 'getWidgetData') return -1;
      return true;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('openstrap/ios_config'),
      (call) async => call.method == 'appGroupIdentifier' ? 'group.test' : null,
    );
    await WidgetService.clear();
    written.clear();
    final db = await LocalDb.instance;
    await db.delete('day_result');
    await db.delete('sleep_goal_period');
    await db.delete('sync_cursor', where: 'name = ?', whereArgs: ['rec_ts_hw']);
    final now = DateTime.now();
    sampleAt =
        DateTime(now.year, now.month, now.day, 9, 38).millisecondsSinceEpoch ~/
        1000;
    await db.insert('sync_cursor', {
      'name': 'rec_ts_hw',
      'value': '$sampleAt',
      'updated_at': sampleAt,
    });
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('home_widget'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('openstrap/ios_config'),
      null,
    );
  });

  TodayData today({Object? readiness = 74, String? note}) =>
      TodayData.fromJson({
        'daily': {
          'readiness': readiness is num
              ? {'value': readiness}
              : {'value': '—', 'note': note},
          'strain': {'value': 9.4},
        },
        'sleep': {
          'duration_min': {'value': 438},
          'need_min': {'value': 465},
        },
        'status': {
          'today_day': todayLabel(),
          'overnight_day': todayLabel(),
          'overnight_state': 'ready',
          'activity_state': 'ready',
        },
      });

  test(
    'publishes committed sample time and trusted stored personal range',
    () async {
      await LocalDb.putSleepGoalPeriod(
        validFromDay: todayLabel(),
        minutes: 475,
      );
      await LocalDb.putDayResult(
        dayId: todayLabel(),
        algoVersion: kAlgoVersion,
        payloadJson: jsonEncode({
          'baselines': {
            'recovery': {'status': 'trusted', 'baseline': 69.0, 'spread': 8.0},
          },
        }),
        windowJson: '{}',
      );
      await WidgetService.push(today());
      expect(written['g3_sample_at'], sampleAt);
      expect(written['g3_recovery_low'], closeTo(58.976, 0.001));
      expect(written['g3_recovery_high'], closeTo(79.024, 0.001));
      expect(written['g3_recovery_median'], 69.0);
      expect(written['g3_sleep_goal_min'], 475);
      expect(written['g3_has_snapshot'], true);
      expect(written['g3_never_connected'], false);
    },
  );

  test('building baseline publishes counts and no invented range', () async {
    await WidgetService.push(
      today(readiness: null, note: 'need_baseline:have=9,need=14'),
    );
    expect(written['readiness'], -1);
    expect(written['g3_baseline_have'], 9);
    expect(written['g3_baseline_need'], 14);
    expect(written['g3_recovery_low'], -1.0);
    expect(written['g3_sleep_goal_min'], -1);
  });

  test(
    'keeps the stored sample date when today has no derived values',
    () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final stored =
          DateTime(
            yesterday.year,
            yesterday.month,
            yesterday.day,
            23,
            10,
          ).millisecondsSinceEpoch ~/
          1000;
      final db = await LocalDb.instance;
      await db.update(
        'sync_cursor',
        {'value': '$stored'},
        where: 'name = ?',
        whereArgs: ['rec_ts_hw'],
      );
      await WidgetService.push(TodayData.fromJson({'daily': const {}}));
      expect(written['g3_sample_at'], stored);
      expect(written['g3_has_snapshot'], false);
      expect(written['g3_never_connected'], false);
      expect(written['has_data'], false);
    },
  );
}
