// Cycle post-log context: atomic invalidation, durable queue, source-match
// reject, empty-todo refresh, rollback, restart, no fabricated no-data.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/compute/derive_scheduler.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openband_cycle_context_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    LocalDb.onCycleContextInvalidated = null;
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  setUp(() async {
    LocalDb.onCycleContextInvalidated = null;
    LocalDb.debugBeforeCycleLogImportInvalidate = null;
    LocalDb.debugAfterImportedTable = null;
    final db = await LocalDb.instance;
    for (final table in [
      'cycle_log',
      'baselines',
      'compute_jobs',
      'day_result',
      'decoded_onehz',
      'sync_cursor',
    ]) {
      try {
        await db.delete(table);
      } catch (_) {}
    }
  });

  Future<void> seedStaleCrossday() async {
    await LocalDb.putBaseline('crossday', jsonEncode({'stale': true}));
    await LocalDb.putBaseline(
      'crossday_input',
      jsonEncode({
        'algo_version': kAlgoVersion,
        'days': [
          {'date': '2026-01-01'},
        ],
      }),
    );
  }

  test('start write invalidates output and enqueues in the same transaction',
      () async {
    await seedStaleCrossday();
    await LocalDb.putCycleLog('2026-06-01', 'start');
    expect(await LocalDb.baseline('crossday'), isNull);
    expect(await LocalDb.baseline('crossday_input'), isNotNull);
    final queued = await LocalDb.computeJobs(state: 'queued');
    expect(
      queued.any((j) => j['reason'] == LocalDb.kCycleContextJobReason),
      isTrue,
    );
    expect(await LocalDb.cycleStartDates(), ['2026-06-01']);
  });

  test('note-only change does not delete the crossday artifact', () async {
    await LocalDb.putCycleLog('2026-06-01', 'start', note: 'a');
    await seedStaleCrossday();
    final db = await LocalDb.instance;
    await db.delete('compute_jobs');
    await LocalDb.putCycleLog('2026-06-01', 'start', note: 'b');
    expect(await LocalDb.baseline('crossday'), isNotNull);
    expect(await LocalDb.computeJobs(state: 'queued'), isEmpty);
    expect((await LocalDb.cycleLogs()).single['note'], 'b');
  });

  test('malformed and future dates are refused at the write boundary', () async {
    await seedStaleCrossday();
    await expectLater(
      LocalDb.putCycleLog('2026-02-30', 'start'),
      throwsArgumentError,
    );
    await expectLater(
      LocalDb.putCycleLog('not-a-date', 'start'),
      throwsArgumentError,
    );
    final future = DateTime.now().add(const Duration(days: 3));
    final label =
        '${future.year.toString().padLeft(4, '0')}-'
        '${future.month.toString().padLeft(2, '0')}-'
        '${future.day.toString().padLeft(2, '0')}';
    await expectLater(LocalDb.putCycleLog(label, 'start'), throwsArgumentError);
    expect(await LocalDb.cycleLogs(), isEmpty);
    expect(await LocalDb.baseline('crossday'), isNotNull);
  });

  test('old in-flight source is rejected and does not resurrect stale output',
      () async {
    await LocalDb.putCycleLog('2026-06-01', 'start');
    final captured = await LocalDb.cycleStartDates();
    await LocalDb.putCycleLog('2026-06-29', 'start');
    expect(await LocalDb.baseline('crossday'), isNull);
    final wrote = await LocalDb.commitCrossDayIfStartsUnchanged(
      payloadJson: jsonEncode({'from': 'obsolete'}),
      expectedStarts: captured,
    );
    expect(wrote, isFalse);
    expect(await LocalDb.baseline('crossday'), isNull);
    expect(
      await LocalDb.commitCrossDayIfStartsUnchanged(
        payloadJson: jsonEncode({'from': 'current'}),
        expectedStarts: await LocalDb.cycleStartDates(),
      ),
      isTrue,
    );
    expect(
      jsonDecode((await LocalDb.baseline('crossday'))!['payload_json'] as String),
      {'from': 'current'},
    );
  });

  test('a cycle write during a running job leaves queued refresh work',
      () async {
    final db = await LocalDb.instance;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('compute_jobs', {
      'id': 'derive_heavy_running',
      'type': 'derive_heavy',
      'scope': 'derive',
      'priority': 200,
      'state': 'running',
      'reason': 'capture_settled',
      'attempts': 1,
      'created_at': now,
      'updated_at': now,
    });
    await LocalDb.putCycleLog('2026-06-01', 'start');
    final running = await LocalDb.computeJobs(state: 'running');
    final queued = await LocalDb.computeJobs(state: 'queued');
    expect(running.single['id'], 'derive_heavy_running');
    expect(
      queued.any(
        (j) =>
            j['type'] == 'derive_heavy' &&
            j['reason'] == LocalDb.kCycleContextJobReason,
      ),
      isTrue,
    );
  });

  test('transaction rollback preserves both log and prior artifact', () async {
    await seedStaleCrossday();
    final db = await LocalDb.instance;
    try {
      await db.transaction((txn) async {
        await txn.insert('cycle_log', {
          'date': '2026-06-01',
          'kind': 'start',
        });
        await LocalDb.invalidateCycleContext(txn);
        throw StateError('rollback');
      });
    } on StateError catch (e) {
      expect(e.message, 'rollback');
    }
    expect(await LocalDb.cycleLogs(), isEmpty);
    expect(await LocalDb.baseline('crossday'), isNotNull);
    expect(await LocalDb.computeJobs(), isEmpty);
  });

  test('restart requeues a running cycle-context job', () async {
    await LocalDb.enqueueDeriveJob(
      type: 'derive_heavy',
      reason: LocalDb.kCycleContextJobReason,
    );
    final claimed = await LocalDb.takeNextComputeJob();
    expect(claimed!['state'], 'running');
    expect(claimed['reason'], LocalDb.kCycleContextJobReason);
    await LocalDb.recoverComputeJobs();
    final queued = await LocalDb.computeJobs(state: 'queued');
    expect(queued, isNotEmpty);
    expect(queued.single['reason'], LocalDb.kCycleContextJobReason);
  });

  test('no data leaves unavailable, never stale success', () async {
    await seedStaleCrossday();
    final db = await LocalDb.instance;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.delete('baselines', where: 'key = ?', whereArgs: ['crossday']);
    await db.insert('compute_jobs', {
      'id': 'derive_heavy_cycle',
      'type': 'derive_heavy',
      'scope': 'derive',
      'priority': 200,
      'state': 'running',
      'reason': LocalDb.kCycleContextJobReason,
      'attempts': 1,
      'created_at': now,
      'updated_at': now,
    });
    final engine = DerivationEngine();
    expect(await engine.run(const PersonalProfile()), 0);
    expect(engine.debugCrossDayPasses, 1);
    expect(await LocalDb.baseline('crossday'), isNull);
    expect(await LocalDb.baseline('crossday_input'), isNotNull);
  });

  test('no per-day todo still refreshes context', () async {
    final day = DateTime(2026, 4, 10, 12);
    final recTs = day.millisecondsSinceEpoch ~/ 1000;
    final db = await LocalDb.instance;
    await db.insert('decoded_onehz', {
      'device_id': '',
      'ts_ms': recTs * 1000,
      'rec_ts': recTs,
      'counter': 1,
      'hr': 60,
    });
    await LocalDb.putDayResult(
      dayId: '2026-04-10',
      algoVersion: kAlgoVersion,
      payloadJson: jsonEncode({
        'scalars': {'rhr': 55},
      }),
      windowJson: '{}',
      finalized: true,
    );
    await LocalDb.setCursor(
      'derived_profile_signature',
      jsonEncode(const PersonalProfile().toMap()),
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('compute_jobs', {
      'id': 'derive_heavy_cycle',
      'type': 'derive_heavy',
      'scope': 'derive',
      'priority': 200,
      'state': 'running',
      'reason': LocalDb.kCycleContextJobReason,
      'attempts': 1,
      'created_at': now,
      'updated_at': now,
    });
    await LocalDb.putBaseline('crossday', jsonEncode({'stale': true}));
    await db.delete('baselines', where: 'key = ?', whereArgs: ['crossday']);
    final engine = DerivationEngine();
    expect(await engine.run(const PersonalProfile(), heavy: true), 0);
    expect(
      engine.debugCrossDayPasses,
      greaterThan(0),
      reason: 'cycle-context job must run crossday with an empty per-day todo',
    );
    expect(await LocalDb.baseline('crossday'), isNull);
  });

  test('failed cycle-context job stays explicit and can be requeued', () async {
    await LocalDb.enqueueDeriveJob(
      type: 'derive_heavy',
      reason: LocalDb.kCycleContextJobReason,
    );
    final claimed = await LocalDb.takeNextComputeJob();
    await LocalDb.failComputeJob(
      claimed!['id'].toString(),
      'boom',
      preserveReason: true,
    );
    final failed = await LocalDb.computeJobs(state: 'failed');
    expect(failed.single['reason'], LocalDb.kCycleContextJobReason);
    await LocalDb.requeueFailedCycleContextJobs();
    final queued = await LocalDb.computeJobs(state: 'queued');
    expect(queued.single['reason'], LocalDb.kCycleContextJobReason);
  });

  test('successor job id does not collide with a same-millisecond running job',
      () async {
    final db = await LocalDb.instance;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('compute_jobs', {
      'id': 'derive_heavy_$now',
      'type': 'derive_heavy',
      'scope': 'derive',
      'priority': 200,
      'state': 'running',
      'reason': 'capture_settled',
      'attempts': 1,
      'created_at': now,
      'updated_at': now,
    });
    await LocalDb.enqueueDeriveJob(
      type: 'derive_heavy',
      reason: LocalDb.kCycleContextJobReason,
    );
    final queued = await LocalDb.computeJobs(state: 'queued');
    final running = await LocalDb.computeJobs(state: 'running');
    expect(queued, hasLength(1));
    expect(running.single['id'], 'derive_heavy_$now');
    expect(queued.single['id'], isNot(running.single['id']));
    expect(queued.single['reason'], LocalDb.kCycleContextJobReason);
  });

  test('deleteDays invalidates only when a contributing start is removed',
      () async {
    await LocalDb.putCycleLog('2026-06-01', 'start');
    await seedStaleCrossday();
    final db = await LocalDb.instance;
    await db.delete('compute_jobs');
    await LocalDb.deleteDays({'2026-06-02'});
    expect(await LocalDb.baseline('crossday'), isNotNull);
    expect(await LocalDb.computeJobs(state: 'queued'), isEmpty);

    await LocalDb.deleteDays({'2026-06-01'});
    expect(await LocalDb.baseline('crossday'), isNull);
    expect(await LocalDb.cycleStartDates(), isEmpty);
    expect(
      (await LocalDb.computeJobs(state: 'queued')).any(
        (j) => j['reason'] == LocalDb.kCycleContextJobReason,
      ),
      isTrue,
    );
  });

  test('importFromDbFile invalidates only when the start set changes',
      () async {
    await LocalDb.putCycleLog('2026-06-01', 'start', note: 'keep');
    await seedStaleCrossday();
    final dir = await databaseFactory.getDatabasesPath();
    final samePath = p.join(dir, 'cycle_import_same.db');
    await databaseFactory.deleteDatabase(samePath);
    final same = await databaseFactory.openDatabase(samePath);
    await same.execute(
      'CREATE TABLE cycle_log (date TEXT PRIMARY KEY, kind TEXT NOT NULL, note TEXT)',
    );
    await same.insert('cycle_log', {
      'date': '2026-06-01',
      'kind': 'start',
      'note': 'imported-note',
    });
    await same.close();
    final db = await LocalDb.instance;
    await db.delete('compute_jobs');
    await LocalDb.importFromDbFile(samePath);
    expect(
      await LocalDb.baseline('crossday'),
      isNotNull,
      reason: 'note-only import must not drop crossday',
    );
    expect(await LocalDb.computeJobs(state: 'queued'), isEmpty);

    final addPath = p.join(dir, 'cycle_import_add.db');
    await databaseFactory.deleteDatabase(addPath);
    final add = await databaseFactory.openDatabase(addPath);
    await add.execute(
      'CREATE TABLE cycle_log (date TEXT PRIMARY KEY, kind TEXT NOT NULL, note TEXT)',
    );
    await add.insert('cycle_log', {'date': '2026-06-01', 'kind': 'start'});
    await add.insert('cycle_log', {'date': '2026-06-29', 'kind': 'start'});
    await add.close();
    await LocalDb.importFromDbFile(addPath);
    expect(await LocalDb.baseline('crossday'), isNull);
    expect(await LocalDb.cycleStartDates(), ['2026-06-01', '2026-06-29']);
    expect(
      (await LocalDb.computeJobs(state: 'queued')).any(
        (j) => j['reason'] == LocalDb.kCycleContextJobReason,
      ),
      isTrue,
    );
  });

  Future<String> cycleAndBaselinesImportDb({
    required String name,
    required List<Map<String, Object?>> starts,
    required List<Map<String, Object?>> baselines,
  }) async {
    final dir = await databaseFactory.getDatabasesPath();
    final path = p.join(dir, name);
    await databaseFactory.deleteDatabase(path);
    final src = await databaseFactory.openDatabase(path);
    await src.execute(
      'CREATE TABLE cycle_log (date TEXT PRIMARY KEY, kind TEXT NOT NULL, note TEXT)',
    );
    await src.execute(
      'CREATE TABLE baselines (key TEXT PRIMARY KEY, payload_json TEXT NOT NULL, updated_at INTEGER NOT NULL)',
    );
    for (final row in starts) {
      await src.insert('cycle_log', row);
    }
    for (final row in baselines) {
      await src.insert('baselines', row);
    }
    await src.close();
    return path;
  }

  test('imported crossday/cache cannot resurrect after cycle_log merge',
      () async {
    await LocalDb.putCycleLog('2026-06-01', 'start');
    await seedStaleCrossday();
    await LocalDb.putBaseline('rolling_artifact', jsonEncode({'local': true}));
    final db = await LocalDb.instance;
    await db.delete('compute_jobs');
    final now = DateTime.now().millisecondsSinceEpoch;
    final path = await cycleAndBaselinesImportDb(
      name: 'cycle_import_baselines.db',
      starts: [
        {'date': '2026-06-01', 'kind': 'start'},
        {'date': '2026-06-29', 'kind': 'start'},
      ],
      baselines: [
        {
          'key': 'crossday',
          'payload_json': jsonEncode({'foreign': true}),
          'updated_at': now,
        },
        {
          'key': 'crossday_input',
          'payload_json': jsonEncode({'foreign_input': true}),
          'updated_at': now,
        },
        {
          'key': 'rolling_artifact',
          'payload_json': jsonEncode({'foreign_roll': true}),
          'updated_at': now,
        },
      ],
    );
    await LocalDb.importFromDbFile(path);
    expect(await LocalDb.cycleStartDates(), ['2026-06-01', '2026-06-29']);
    expect(
      await LocalDb.baseline('crossday'),
      isNull,
      reason: 'foreign crossday must not replace invalidated local output',
    );
    expect(
      jsonDecode(
        (await LocalDb.baseline('crossday_input'))!['payload_json'] as String,
      ),
      isNot(containsPair('foreign_input', true)),
      reason: 'foreign crossday_input must not mask local day_result provenance',
    );
    expect(
      jsonDecode(
        (await LocalDb.baseline('rolling_artifact'))!['payload_json'] as String,
      ),
      {'foreign_roll': true},
    );
    expect(
      (await LocalDb.computeJobs(state: 'queued')).any(
        (j) => j['reason'] == LocalDb.kCycleContextJobReason,
      ),
      isTrue,
    );
  });

  test('foreign crossday is not installed even without a start-set change',
      () async {
    await LocalDb.putCycleLog('2026-06-01', 'start');
    await seedStaleCrossday();
    final db = await LocalDb.instance;
    await db.delete('compute_jobs');
    final now = DateTime.now().millisecondsSinceEpoch;
    final path = await cycleAndBaselinesImportDb(
      name: 'cycle_import_foreign_only.db',
      starts: [
        {'date': '2026-06-01', 'kind': 'start', 'note': 'same'},
      ],
      baselines: [
        {
          'key': 'crossday',
          'payload_json': jsonEncode({'foreign': true}),
          'updated_at': now,
        },
      ],
    );
    await LocalDb.importFromDbFile(path);
    expect(
      jsonDecode((await LocalDb.baseline('crossday'))!['payload_json'] as String),
      {'stale': true},
      reason: 'local derived output stays; foreign must not masquerade',
    );
    expect(await LocalDb.computeJobs(state: 'queued'), isEmpty);
  });

  Future<String> cycleImportDb(
    String name,
    List<Map<String, Object?>> rows,
  ) async {
    final dir = await databaseFactory.getDatabasesPath();
    final path = p.join(dir, name);
    await databaseFactory.deleteDatabase(path);
    final src = await databaseFactory.openDatabase(path);
    await src.execute(
      'CREATE TABLE cycle_log (date TEXT PRIMARY KEY, kind TEXT NOT NULL, note TEXT)',
    );
    for (final row in rows) {
      await src.insert('cycle_log', row);
    }
    await src.close();
    return path;
  }

  test('invalidation failure rolls back imported starts and prior artifact',
      () async {
    await LocalDb.putCycleLog('2026-06-01', 'start');
    await seedStaleCrossday();
    final db = await LocalDb.instance;
    await db.delete('compute_jobs');
    LocalDb.debugBeforeCycleLogImportInvalidate = (_) async {
      throw StateError('invalidate fail');
    };
    final path = await cycleImportDb('cycle_import_fail_inv.db', [
      {'date': '2026-06-01', 'kind': 'start'},
      {'date': '2026-06-29', 'kind': 'start'},
    ]);
    await expectLater(
      LocalDb.importFromDbFile(path),
      throwsStateError,
    );
    expect(await LocalDb.cycleStartDates(), ['2026-06-01']);
    expect(await LocalDb.baseline('crossday'), isNotNull);
    expect(await LocalDb.computeJobs(), isEmpty);
  });

  test('later import failure cannot undo committed cycle invalidation',
      () async {
    await LocalDb.putCycleLog('2026-06-01', 'start');
    await seedStaleCrossday();
    final db = await LocalDb.instance;
    await db.delete('compute_jobs');
    LocalDb.debugAfterImportedTable = (table) async {
      if (table == 'cycle_log') throw StateError('later table');
    };
    final path = await cycleImportDb('cycle_import_later_fail.db', [
      {'date': '2026-06-01', 'kind': 'start'},
      {'date': '2026-06-29', 'kind': 'start'},
    ]);
    await expectLater(
      LocalDb.importFromDbFile(path),
      throwsStateError,
    );
    expect(await LocalDb.cycleStartDates(), ['2026-06-01', '2026-06-29']);
    expect(await LocalDb.baseline('crossday'), isNull);
    expect(
      (await LocalDb.computeJobs(state: 'queued')).any(
        (j) => j['reason'] == LocalDb.kCycleContextJobReason,
      ),
      isTrue,
    );
  });

  test('failed cycle-context jobs are retried on recoverComputeJobs',
      () async {
    await LocalDb.enqueueDeriveJob(
      type: 'derive_heavy',
      reason: LocalDb.kCycleContextJobReason,
    );
    final claimed = await LocalDb.takeNextComputeJob();
    await LocalDb.failComputeJob(
      claimed!['id'].toString(),
      'boom',
      preserveReason: true,
    );
    await LocalDb.recoverComputeJobs();
    final queued = await LocalDb.computeJobs(state: 'queued');
    expect(queued.single['reason'], LocalDb.kCycleContextJobReason);
  });

  Future<void> until(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 2),
    String? message,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    if (!condition()) {
      fail(message ?? 'timed out waiting for condition');
    }
  }

  Future<void> untilAsync(
    Future<bool> Function() condition, {
    Duration timeout = const Duration(seconds: 3),
    String? message,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail(message ?? 'timed out waiting for condition');
  }

  test('disposed scheduler does not rearm after wake', () async {
    var runs = 0;
    final s = DeriveScheduler(
      run: ({required DeriveJobKind kind}) async => runs++,
      log: (_) {},
      onChanged: () {},
      heavySettle: Duration.zero,
      lightSettle: Duration.zero,
    );
    await LocalDb.enqueueDeriveJob(
      type: 'derive_heavy',
      reason: LocalDb.kCycleContextJobReason,
    );
    s.dispose();
    await s.wakeQueuedWork();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(runs, 0);
  });

  test('wake during a held snapshot still arms the new durable job', () async {
    var runs = 0;
    final hold = Completer<void>();
    var holds = 0;
    final s = DeriveScheduler(
      run: ({required DeriveJobKind kind}) async => runs++,
      log: (_) {},
      onChanged: () {},
      heavySettle: Duration.zero,
      lightSettle: Duration.zero,
    );
    addTearDown(s.dispose);
    s.debugHoldSnapshot = () async {
      holds++;
      if (holds == 1) await hold.future;
    };
    final first = s.wakeQueuedWork();
    await until(() => holds == 1);
    await LocalDb.enqueueDeriveJob(
      type: 'derive_heavy',
      reason: LocalDb.kCycleContextJobReason,
    );
    final second = s.wakeQueuedWork();
    hold.complete();
    await Future.wait([first, second]);
    await until(() => runs == 1);
    expect(runs, 1);
  });

  test('dispose during drain snapshot requeues and does not run', () async {
    var runs = 0;
    final hold = Completer<void>();
    var holds = 0;
    final s = DeriveScheduler(
      run: ({required DeriveJobKind kind}) async => runs++,
      log: (_) {},
      onChanged: () {},
      heavySettle: Duration.zero,
      lightSettle: Duration.zero,
    );
    s.debugHoldSnapshot = () async {
      holds++;
      if (holds >= 2) await hold.future;
    };
    await LocalDb.enqueueDeriveJob(
      type: 'derive_heavy',
      reason: LocalDb.kCycleContextJobReason,
    );
    unawaited(s.wakeQueuedWork());
    await until(() => s.running);
    s.dispose();
    hold.complete();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(runs, 0);
    expect(s.running, isFalse);
    final queued = await LocalDb.computeJobs(state: 'queued');
    expect(queued, isNotEmpty);
  });

  test('in-flight crossday discards stale output and leaves a successor',
      () async {
    await LocalDb.putCycleLog('2026-06-01', 'start');
    await LocalDb.putBaseline('crossday', jsonEncode({'stale': true}));
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await LocalDb.putBaseline(
      'crossday_input',
      jsonEncode({
        'algo_version': kAlgoVersion,
        'built_for_day': todayLabel(),
        'input_read_started_at_ms': nowMs,
        'days': [
          {'date': '2026-01-01', 'rhr': 55.0},
          {'date': '2026-01-02', 'rhr': 56.0},
          {'date': '2026-01-03', 'rhr': 57.0, 'is_today': true},
        ],
      }),
    );
    final db = await LocalDb.instance;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.delete('compute_jobs');
    await db.insert('compute_jobs', {
      'id': 'derive_heavy_inflight',
      'type': 'derive_heavy',
      'scope': 'derive',
      'priority': 200,
      'state': 'running',
      'reason': 'capture_settled',
      'attempts': 1,
      'created_at': now,
      'updated_at': now,
    });
    final engine = DerivationEngine();
    engine.debugAfterCrossDayCapture = () async {
      await LocalDb.putCycleLog('2026-06-29', 'start');
    };
    await engine.debugRunCrossDay(const PersonalProfile());
    expect(
      await LocalDb.baseline('crossday'),
      isNull,
      reason: 'obsolete in-flight result must not publish',
    );
    await LocalDb.completeComputeJob('derive_heavy_inflight');
    final queued = await LocalDb.computeJobs(state: 'queued');
    expect(
      queued.any((j) => j['reason'] == LocalDb.kCycleContextJobReason),
      isTrue,
      reason: 'start write during compute must leave refresh work',
    );
  });

  test('deleteDays drops input cache when day sources change', () async {
    await LocalDb.putDayResult(
      dayId: '2026-04-10',
      algoVersion: kAlgoVersion,
      payloadJson: jsonEncode({
        'scalars': {'rhr': 55},
      }),
      windowJson: '{}',
      finalized: true,
    );
    await LocalDb.putCycleLog('2026-04-10', 'start');
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await LocalDb.putBaseline(
      'crossday_input',
      jsonEncode({
        'algo_version': kAlgoVersion,
        'built_for_day': todayLabel(),
        'input_read_started_at_ms': nowMs,
        'source_rev': 0,
        'days': [
          {'date': '2026-04-08', 'rhr': 50.0},
          {'date': '2026-04-09', 'rhr': 51.0},
          {'date': '2026-04-10', 'rhr': 55.0, 'is_today': true},
        ],
      }),
    );
    await LocalDb.putBaseline('crossday', jsonEncode({'stale': true}));
    await LocalDb.deleteDays({'2026-04-10'});
    expect(await LocalDb.baseline('crossday'), isNull);
    expect(await LocalDb.baseline('crossday_input'), isNull);
    expect(await LocalDb.crossDaySourceRevision(), greaterThan(0));
  });

  test('busy engine requeues the cycle job instead of completing it', () async {
    var attempts = 0;
    final s = DeriveScheduler(
      run: ({required DeriveJobKind kind}) async {
        attempts++;
        throw const DerivationBusy();
      },
      log: (_) {},
      onChanged: () {},
      heavySettle: Duration.zero,
      lightSettle: Duration.zero,
    );
    await LocalDb.enqueueDeriveJob(
      type: 'derive_heavy',
      reason: LocalDb.kCycleContextJobReason,
    );
    unawaited(s.wakeQueuedWork());
    await until(() => attempts >= 1);
    s.dispose();
    expect(attempts, greaterThan(0));
    expect(await LocalDb.computeJobs(state: 'failed'), isEmpty);
    expect(
      (await LocalDb.computeJobs(state: 'queued')).any(
        (j) => j['reason'] == LocalDb.kCycleContextJobReason,
      ),
      isTrue,
    );
  });

  test('derivation throw fails the job instead of deleting it', () async {
    final s = DeriveScheduler(
      run: ({required DeriveJobKind kind}) async {
        throw StateError('crossday boom');
      },
      log: (_) {},
      onChanged: () {},
      heavySettle: Duration.zero,
      lightSettle: Duration.zero,
    );
    addTearDown(s.dispose);
    await LocalDb.enqueueDeriveJob(
      type: 'derive_heavy',
      reason: LocalDb.kCycleContextJobReason,
    );
    await s.wakeQueuedWork();
    await until(
      () => true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(await LocalDb.computeJobs(state: 'queued'), isEmpty);
    final failed = await LocalDb.computeJobs(state: 'failed');
    expect(failed.single['reason'], LocalDb.kCycleContextJobReason);
  });

  test('import interruption cannot install foreign cache; job survives reopen',
      () async {
    await LocalDb.putDayResult(
      dayId: '2026-04-10',
      algoVersion: kAlgoVersion,
      payloadJson: jsonEncode({
        'scalars': {'rhr': 10},
      }),
      windowJson: '{}',
      finalized: true,
    );
    await LocalDb.putDayResult(
      dayId: '2026-04-11',
      algoVersion: kAlgoVersion,
      payloadJson: jsonEncode({
        'scalars': {'rhr': 11},
      }),
      windowJson: '{}',
      finalized: true,
    );
    await LocalDb.putCycleLog('2026-04-01', 'start');
    final localTen = await LocalDb.dayResult('2026-04-10');
    LocalDb.debugAfterImportedTable = (table) async {
      if (table == 'baselines') throw StateError('interrupt');
    };
    final dir = await databaseFactory.getDatabasesPath();
    final path = p.join(dir, 'cycle_import_interrupt.db');
    await databaseFactory.deleteDatabase(path);
    final src = await databaseFactory.openDatabase(path);
    await src.execute(
      'CREATE TABLE cycle_log (date TEXT PRIMARY KEY, kind TEXT NOT NULL, note TEXT)',
    );
    await src.execute(
      'CREATE TABLE day_result (day_id TEXT NOT NULL, algo_version INTEGER NOT NULL, payload_json TEXT NOT NULL, window_json TEXT, computed_at INTEGER, finalized INTEGER, skipped INTEGER, partial INTEGER, rhr REAL, rmssd REAL, readiness REAL, PRIMARY KEY(day_id, algo_version))',
    );
    await src.execute(
      'CREATE TABLE baselines (key TEXT PRIMARY KEY, payload_json TEXT NOT NULL, updated_at INTEGER NOT NULL)',
    );
    await src.insert('cycle_log', {'date': '2026-04-01', 'kind': 'start'});
    await src.insert('cycle_log', {'date': '2026-04-20', 'kind': 'start'});
    await src.insert('day_result', {
      'day_id': '2026-04-10',
      'algo_version': kAlgoVersion,
      'payload_json': jsonEncode({
        'scalars': {'rhr': 99},
      }),
      'window_json': '{}',
      'computed_at': 1,
      'finalized': 1,
      'skipped': 0,
      'partial': 0,
      'rhr': 99.0,
    });
    final now = DateTime.now().millisecondsSinceEpoch;
    await src.insert('baselines', {
      'key': 'crossday',
      'payload_json': jsonEncode({
        'foreign': true,
        'algo_version': kAlgoVersion,
        'built_for_day': todayLabel(),
      }),
      'updated_at': now,
    });
    await src.insert('baselines', {
      'key': 'crossday_input',
      'payload_json': jsonEncode({
        'algo_version': kAlgoVersion,
        'built_for_day': todayLabel(),
        'input_read_started_at_ms': now,
        'days': [
          {'date': '2026-04-08'},
          {'date': '2026-04-09'},
          {'date': '2026-04-10'},
        ],
      }),
      'updated_at': now,
    });
    await src.close();
    await expectLater(LocalDb.importFromDbFile(path), throwsStateError);
    await LocalDb.close();
    final reopened = await LocalDb.instance;
    expect(reopened.isOpen, isTrue);
    expect(
      jsonDecode((await LocalDb.dayResult('2026-04-10'))!['payload_json'] as String),
      jsonDecode(localTen!['payload_json'] as String),
    );
    expect(await LocalDb.baseline('crossday'), isNull);
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    app.debugDeriveScheduler.debugSettle = Duration.zero;
    await app.debugDeriveScheduler.init();
    await untilAsync(
      () async {
        final jobs = await LocalDb.computeJobs();
        return !jobs.any(
          (j) =>
              j['reason'] == LocalDb.kCycleContextJobReason &&
              (j['state'] == 'queued' || j['state'] == 'running'),
        );
      },
      message: 'cycle job still queued/running after scheduler init',
    );
    app.debugDeriveScheduler.dispose();
    expect(await LocalDb.baseline('crossday'), isNull);
    expect(
      jsonDecode((await LocalDb.dayResult('2026-04-10'))!['payload_json'] as String),
      jsonDecode(localTen['payload_json'] as String),
    );
  });

  test('stale input rebuild cannot publish after putDayResult',
      () async {
    for (final day in ['2026-04-08', '2026-04-09', '2026-04-10']) {
      await LocalDb.putDayResult(
        dayId: day,
        algoVersion: kAlgoVersion,
        payloadJson: jsonEncode({
          'scalars': {'rhr': 50.0},
        }),
        windowJson: '{}',
        finalized: true,
        rhr: 50,
      );
    }
    final hold = Completer<void>();
    var readOld = false;
    final older = DerivationEngine();
    older.debugAfterCrossDayInputRead = () async {
      readOld = true;
      await hold.future;
    };
    final olderRun = older.debugRunCrossDay(const PersonalProfile());
    await until(() => readOld);
    await LocalDb.putDayResult(
      dayId: '2026-04-10',
      algoVersion: kAlgoVersion,
      payloadJson: jsonEncode({
        'scalars': {'rhr': 99.0},
      }),
      windowJson: '{}',
      finalized: true,
      rhr: 99,
    );
    await DerivationEngine().debugRunCrossDay(const PersonalProfile());
    hold.complete();
    await olderRun;
    final input = await LocalDb.baseline('crossday_input');
    expect(input, isNotNull);
    final payload =
        jsonDecode(input!['payload_json'] as String) as Map<String, dynamic>;
    expect(payload['source_rev'], await LocalDb.crossDaySourceRevision());
    final days = (payload['days'] as List).whereType<Map>();
    final ten = days.firstWhere((d) => d['date'] == '2026-04-10');
    expect(
      ten['rhr'],
      99,
      reason: 'older in-flight input must not restore pre-putDayResult days',
    );
  });

  test('malformed or absent source_rev is unusable once revision is nonzero',
      () async {
    await LocalDb.putDayResult(
      dayId: '2026-04-10',
      algoVersion: kAlgoVersion,
      payloadJson: jsonEncode({
        'scalars': {'rhr': 55.0},
      }),
      windowJson: '{}',
      finalized: true,
      rhr: 55,
    );
    final rev = await LocalDb.crossDaySourceRevision();
    expect(rev, greaterThan(0));
    final today = todayLabel();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final days = [
      {'date': '2026-01-01', 'rhr': 1.0},
      {'date': '2026-01-02', 'rhr': 2.0},
      {'date': '2026-01-03', 'rhr': 3.0, 'is_today': true},
    ];
    Map<String, dynamic> envelope({Object? sourceRev, bool includeRev = true}) {
      return {
        'algo_version': kAlgoVersion,
        'built_for_day': today,
        'input_read_started_at_ms': nowMs,
        'days': days,
        if (includeRev) 'source_rev': sourceRev,
      };
    }

    int? usable(Object decoded, {int? at}) =>
        DerivationEngine.crossDayInputReadStartedAtMs(
          decoded,
          today,
          nowMs: nowMs,
          sourceRev: at ?? rev,
        );

    expect(
      usable(envelope(includeRev: false), at: 0),
      nowMs,
      reason: 'absent key is legacy rev0 only',
    );
    expect(
      usable(envelope(sourceRev: null), at: 0),
      isNull,
      reason: 'present null is unreadable even at rev0',
    );
    expect(usable(envelope(includeRev: false)), isNull);
    expect(usable(envelope(sourceRev: null)), isNull);
    expect(usable(envelope(sourceRev: '1')), isNull);
    expect(usable(envelope(sourceRev: 1.5)), isNull);
    expect(usable(envelope(sourceRev: 0)), isNull);
    expect(usable(envelope(sourceRev: rev)), nowMs);

    await LocalDb.putBaseline(
      'crossday_input',
      jsonEncode(envelope(includeRev: false)),
    );
    await DerivationEngine().debugRunCrossDay(const PersonalProfile());
    final stored = await LocalDb.baseline('crossday_input');
    if (stored != null) {
      final payload =
          jsonDecode(stored['payload_json'] as String) as Map<String, dynamic>;
      expect(
        (payload['days'] as List).length,
        isNot(3),
        reason: 'absent rev under nonzero fence must not keep the planted 3-day cache',
      );
    }
  });
}
