// HONESTY REGRESSION — a day-relative stamp must not outlive its day.
//
// `_refreshCrossDayInputArtifact` marks the most recent record `is_today: true`
// so today-scoped reads (`_todayNum`) can tell "today abstained" from "today has
// no row yet". That stamp is a fact ABOUT A DAY stored as a bare boolean, and it
// is written into the DURABLE `crossday_input` baseline row.
//
// The input envelope therefore has to prove both its local day and the exact
// boundary at which its day_result source read started. A missing, malformed,
// future, or prior-day boundary cannot be invented at cache/output time.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/db.dart';

void main() {
  final nowMs = DateTime(2024, 3, 2, 12).millisecondsSinceEpoch;

  Map<String, dynamic> envelope(
    String? builtFor, {
    Object? algoVersion,
    Object? readStartedAtMs,
  }) =>
      <String, dynamic>{
        'algo_version': algoVersion ?? kAlgoVersion,
        'built_for_day': ?builtFor,
        'input_read_started_at_ms': readStartedAtMs ?? nowMs,
        'days': [
          {'date': '2024-03-01', 'strain': 14.0},
          {'date': '2024-03-02', 'strain': 18.0, 'is_today': true},
        ],
      };

  bool usable(Object? candidate, String today, {int? clockMs}) =>
      DerivationEngine.crossDayArtifactUsableToday(
        candidate,
        today,
        nowMs: clockMs ?? nowMs,
      );

  group('crossDayArtifactUsableToday', () {
    test('an artifact built and read today is reusable', () {
      expect(usable(envelope('2024-03-02'), '2024-03-02'), isTrue);
    });

    test('an artifact built yesterday is not reusable today', () {
      expect(
        usable(
          envelope('2024-03-02'),
          '2024-03-03',
          clockMs: DateTime(2024, 3, 3, 12).millisecondsSinceEpoch,
        ),
        isFalse,
        reason: "a stamp that says 'today' must not be believed on a later day",
      );
    });

    test('an artifact with no day stamped is not reusable', () {
      expect(usable(envelope(null), '2024-03-02'), isFalse);
    });

    test('an artifact from an older algo version is not reusable', () {
      expect(
        usable(
          envelope('2024-03-02', algoVersion: kAlgoVersion - 1),
          '2024-03-02',
        ),
        isFalse,
      );
      for (final bad in <Object?>[
        '90',
        90.1,
        double.nan,
        double.infinity,
      ]) {
        expect(
          usable(
            envelope('2024-03-02', algoVersion: bad),
            '2024-03-02',
          ),
          isFalse,
          reason: 'algo_version $bad must fail closed without throwing',
        );
      }
    });

    test('a malformed or empty envelope is not reusable', () {
      expect(usable(null, '2024-03-02'), isFalse);
      expect(usable('not a map', '2024-03-02'), isFalse);
      expect(
        usable({
          'algo_version': kAlgoVersion,
          'built_for_day': '2024-03-02',
          'input_read_started_at_ms': nowMs,
        }, '2024-03-02'),
        isFalse,
      );
      expect(
        usable({
          'algo_version': kAlgoVersion,
          'built_for_day': '',
          'input_read_started_at_ms': nowMs,
          'days': const [],
        }, '2024-03-02'),
        isFalse,
      );
    });

    test('missing, malformed, or future source boundaries are not reusable', () {
      for (final bad in <Object?>[
        null,
        '1709380800000',
        0,
        -1,
        1.5,
        double.nan,
        double.infinity,
        nowMs + 1,
      ]) {
        final candidate = envelope(
          '2024-03-02',
          readStartedAtMs: bad,
        );
        if (bad == null) candidate.remove('input_read_started_at_ms');
        expect(
          usable(candidate, '2024-03-02'),
          isFalse,
          reason: 'bad source boundary $bad must force a rebuild',
        );
      }
    });

    test('source boundary must belong to the same local civil day', () {
      final yesterdayMs = DateTime(2024, 3, 1, 23, 59).millisecondsSinceEpoch;
      expect(
        usable(
          envelope('2024-03-02', readStartedAtMs: yesterdayMs),
          '2024-03-02',
        ),
        isFalse,
        reason: 'a read spanning midnight cannot be treated as today input',
      );
    });

    test('cache parsing returns the exact source boundary', () {
      expect(
        DerivationEngine.crossDayInputReadStartedAtMs(
          envelope('2024-03-02'),
          '2024-03-02',
          nowMs: nowMs + 1234,
        ),
        nowMs,
        reason: 'cache reuse must not replace source-read time with reuse time',
      );
      expect(
        DerivationEngine.crossDayInputReadStartedAtMs(
          envelope('2024-03-02', readStartedAtMs: nowMs.toDouble()),
          '2024-03-02',
          nowMs: nowMs + 1234,
        ),
        nowMs,
      );
    });
  });

  group('cross-day source provenance through SQLite', () {
    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      LocalDb.dbName = 'openstrap_crossday_artifact_freshness_test.db';
      final dir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
    });

    tearDownAll(() async {
      await LocalDb.close();
      final dir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
    });

    setUp(() async {
      final db = await LocalDb.instance;
      await db.delete('day_result');
      await db.delete('baselines');
    });

    Future<Map<String, dynamic>?> readEnvelope(String key) async {
      final row = await LocalDb.baseline(key);
      final raw = row?['payload_json'];
      if (raw is! String || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    }

    Future<void> seedDayResults(int count) async {
      final today = DateTime.now();
      for (var i = count - 1; i >= 0; i--) {
        final dayId = dayLabelOf(today.subtract(Duration(days: i)));
        await LocalDb.putDayResult(
          dayId: dayId,
          algoVersion: kAlgoVersion,
          payloadJson: jsonEncode({
            'scalars': {
              'rhr': 52.0 + i,
              'rmssd': 61.0,
              'readiness': 74.0,
              'strain': 9.4,
            },
            'sleep': {
              'accounting': {
                'value': {
                  'tst_sec': 25860,
                  'in_bed_sec': 28800,
                  'observed_in_bed_sec': 28000,
                },
              },
            },
          }),
          windowJson: '{}',
          finalized: true,
          rhr: 52.0 + i,
          rmssd: 61.0,
          readiness: 74.0,
        );
      }
    }

    List<Map<String, dynamic>> syntheticDays(int count) {
      final today = DateTime.now();
      return [
        for (var i = count - 1; i >= 0; i--)
          {
            'date': dayLabelOf(today.subtract(Duration(days: i))),
            'rhr': 55.0 + i,
            'rmssd': 45.0,
            'readiness': 70.0,
            'strain': 10.0,
            if (i == 0) 'is_today': true,
          },
      ];
    }

    Future<void> putCachedInput({
      required List<Map<String, dynamic>> days,
      Object? readStartedAtMs,
      bool includeStamp = true,
    }) async {
      final envelope = <String, dynamic>{
        'algo_version': kAlgoVersion,
        'source_rev': await LocalDb.crossDaySourceRevision(),
        'built_for_day': dayLabelOf(DateTime.now()),
        'days': days,
      };
      if (includeStamp) {
        envelope['input_read_started_at_ms'] = readStartedAtMs;
      }
      await LocalDb.putBaseline('crossday_input', jsonEncode(envelope));
    }

    Future<void> putOutput({Object? readStartedAtMs, bool includeStamp = true}) async {
      final envelope = <String, dynamic>{
        'algo_version': kAlgoVersion,
        'built_for_day': dayLabelOf(DateTime.now()),
        'built_at_epoch': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'n_days': 3,
        'marker': 'preexisting',
      };
      if (includeStamp) {
        envelope['input_read_started_at_ms'] = readStartedAtMs;
      }
      await LocalDb.putBaseline('crossday', jsonEncode(envelope));
    }

    int? stampOf(Map<String, dynamic>? envelope) {
      final value = envelope?['input_read_started_at_ms'];
      return value is int ? value : (value as num?)?.toInt();
    }

    int earlierTodayMs(int agoMs) {
      final now = DateTime.now();
      final nowMs = now.millisecondsSinceEpoch;
      final todayStart = DateTime(now.year, now.month, now.day)
          .millisecondsSinceEpoch;
      final candidate = nowMs - agoMs;
      return candidate > todayStart ? candidate : todayStart + 1;
    }

    const isolateTimeout = Timeout(Duration(minutes: 2));

    test('fresh build stamps the pre-query boundary onto input and output', () async {
      await seedDayResults(4);
      final beforeMs = DateTime.now().millisecondsSinceEpoch;
      await DerivationEngine().debugRunCrossDay(const PersonalProfile());
      final afterMs = DateTime.now().millisecondsSinceEpoch;

      final input = await readEnvelope('crossday_input');
      final output = await readEnvelope('crossday');
      expect(input, isNotNull, reason: 'producer must persist the input artifact');
      expect(output, isNotNull, reason: 'producer must persist the output artifact');

      final inputStamp = stampOf(input);
      final outputStamp = stampOf(output);
      expect(inputStamp, isNotNull);
      expect(
        outputStamp,
        inputStamp,
        reason: 'output must carry the input read boundary, not a later build time',
      );
      expect(inputStamp, greaterThanOrEqualTo(beforeMs));
      expect(inputStamp, lessThanOrEqualTo(afterMs));
      expect(
        (input!['days'] as List).length,
        4,
        reason: 'fresh read comes from day_result, not a cached envelope',
      );
    }, timeout: isolateTimeout);

    test('cached input reuse survives a delayed build without restamping', () async {
      await seedDayResults(5);
      final cachedStamp = earlierTodayMs(2500);
      await putCachedInput(
        days: syntheticDays(3),
        readStartedAtMs: cachedStamp,
      );

      await Future<void>.delayed(const Duration(milliseconds: 1100));
      final beforeBuild = DateTime.now().millisecondsSinceEpoch;
      await DerivationEngine().debugRunCrossDay(const PersonalProfile());
      final afterBuild = DateTime.now().millisecondsSinceEpoch;

      final input = await readEnvelope('crossday_input');
      final output = await readEnvelope('crossday');
      expect(
        stampOf(input),
        cachedStamp,
        reason: 'cache reuse must not restamp the source-read boundary',
      );
      expect(
        stampOf(output),
        cachedStamp,
        reason: 'delayed output build must not replace the cached source stamp',
      );
      expect(
        (input!['days'] as List).length,
        3,
        reason: 'accidental rebuild would have reread the 5 seeded day_result rows',
      );
      expect((output!['n_days'] as num?)?.toInt(), 3);
      final builtAt = (output['built_at_epoch'] as num).toInt();
      expect(builtAt, greaterThanOrEqualTo(beforeBuild ~/ 1000));
      expect(builtAt, lessThanOrEqualTo(afterBuild ~/ 1000 + 1));
      expect(
        cachedStamp,
        lessThanOrEqualTo(afterBuild),
        reason: 'source ms stays <= actual output build time',
      );
    }, timeout: isolateTimeout);

    test('missing legacy input stamp is rebuilt rather than accepted', () async {
      await seedDayResults(5);
      await putCachedInput(days: syntheticDays(3), includeStamp: false);

      final beforeMs = DateTime.now().millisecondsSinceEpoch;
      await DerivationEngine().debugRunCrossDay(const PersonalProfile());

      final input = await readEnvelope('crossday_input');
      final output = await readEnvelope('crossday');
      expect(
        (input!['days'] as List).length,
        5,
        reason: 'a missing stamp cannot be invented onto the cached 3-day envelope',
      );
      final rebuilt = stampOf(input);
      expect(rebuilt, isNotNull);
      expect(rebuilt, greaterThanOrEqualTo(beforeMs));
      expect(stampOf(output), rebuilt);
    }, timeout: isolateTimeout);

    test('invalid and future input stamps are rebuilt', () async {
      await seedDayResults(5);
      final futureStamp =
          DateTime.now().millisecondsSinceEpoch + const Duration(hours: 1).inMilliseconds;
      for (final bad in <Object?>[0, -1, 1.5, '1709380800000', futureStamp]) {
        await putCachedInput(days: syntheticDays(3), readStartedAtMs: bad);
        final beforeMs = DateTime.now().millisecondsSinceEpoch;
        await DerivationEngine().debugRunCrossDay(const PersonalProfile());
        final input = await readEnvelope('crossday_input');
        final output = await readEnvelope('crossday');
        expect(
          (input!['days'] as List).length,
          5,
          reason: 'bad source boundary $bad must not keep the cached 3-day envelope',
        );
        final rebuilt = stampOf(input);
        expect(rebuilt, isNotNull, reason: 'bad $bad must force a real pre-query stamp');
        expect(rebuilt, greaterThanOrEqualTo(beforeMs));
        expect(rebuilt, lessThanOrEqualTo(DateTime.now().millisecondsSinceEpoch));
        expect(rebuilt, isNot(bad));
        expect(stampOf(output), rebuilt);
      }
    }, timeout: isolateTimeout);

    test('source ms is kept even when seconds-truncated built_at is earlier', () async {
      while (DateTime.now().millisecondsSinceEpoch % 1000 < 250) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final stamp = (now ~/ 1000) * 1000 + 40;
      expect(stamp, lessThanOrEqualTo(now));
      await putCachedInput(days: syntheticDays(3), readStartedAtMs: stamp);

      await DerivationEngine().debugRunCrossDay(const PersonalProfile());
      final output = await readEnvelope('crossday');
      expect(output, isNotNull);
      expect(
        stampOf(output),
        stamp,
        reason: 'output must not restamp to built_at_epoch*1000 or nowMs',
      );
      final builtAtBound = (output!['built_at_epoch'] as num).toInt() * 1000;
      expect(
        stamp,
        lessThanOrEqualTo(DateTime.now().millisecondsSinceEpoch),
        reason: 'consumer compares the ms read stamp to nowMs, not the rounded bound',
      );
      if (builtAtBound < stamp) {
        expect(
          stampOf(output),
          isNot(builtAtBound),
          reason: 'truncated built_at bound would falsely look earlier than the source read',
        );
      }
    }, timeout: isolateTimeout);

    test('producer skip leaves preexisting output provenance untouched', () async {
      const oldStamp = 1;
      await putOutput(readStartedAtMs: oldStamp);
      await putCachedInput(
        days: syntheticDays(2),
        readStartedAtMs: earlierTodayMs(200),
      );

      await DerivationEngine().debugRunCrossDay(const PersonalProfile());

      final output = await readEnvelope('crossday');
      expect(output?['marker'], 'preexisting');
      expect(
        stampOf(output),
        oldStamp,
        reason: 'a skipped/failed producer must not invent or restamp output provenance',
      );
    }, timeout: isolateTimeout);
  });
}
