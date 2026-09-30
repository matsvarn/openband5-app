// Cycle settings persistence: canonical flags, failed prefs ack, overlapping
// profile patches, off keeps logs, no second enable preference.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/openband/cycle_data.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _WriteOutcomeStore extends SharedPreferencesStorePlatform {
  _WriteOutcomeStore(this._inner);
  final SharedPreferencesStorePlatform _inner;
  bool allowWrites = true;
  bool throwOnWrite = false;

  @override
  Future<bool> clear() => _inner.clear();
  @override
  Future<Map<String, Object>> getAll() => _inner.getAll();
  @override
  Future<bool> remove(String key) => _inner.remove(key);
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (throwOnWrite) throw StateError('disk');
    if (!allowWrites) return false;
    return _inner.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openband_cycle_runtime_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Prefs.debugReset();
    await Prefs.ensureLoaded();
    final db = await LocalDb.instance;
    await db.delete('cycle_log');
    await db.delete('compute_jobs');
  });

  Map<String, Object?> profile({
    int? version,
    bool? track,
    bool? estimates,
    String? repro,
    bool? lengthReview,
    String? name,
  }) =>
      {
        'name': ?name,
        'cycle_preferences_version': ?version,
        'track_cycle': ?track,
        'cycle_estimates': ?estimates,
        'repro_state': ?repro,
        'cycle_length_review': ?lengthReview,
      };

  group('canonical legacy flag combinations', () {
    test('version 1 uses track_cycle alone', () async {
      SharedPreferences.setMockInitialValues({
        'cycle_tracking_enabled': false,
      });
      Prefs.debugReset();
      await Prefs.ensureLoaded();
      final app = AppState.forTesting()
        ..user = profile(version: 1, track: true);
      addTearDown(app.dispose);
      expect((await app.readCycleSettings()).enabled, isTrue);
      expect(app.cycleTrackingEnabled, isTrue);

      app.user = profile(version: 1, track: false);
      expect((await app.readCycleSettings()).enabled, isFalse);
    });

    test('before version 1, both old flags must be true', () async {
      for (final case_ in [
        (legacy: true, track: true, enabled: true),
        (legacy: true, track: false, enabled: false),
        (legacy: false, track: true, enabled: false),
        (legacy: false, track: false, enabled: false),
      ]) {
        SharedPreferences.setMockInitialValues({
          'cycle_tracking_enabled': case_.legacy,
        });
        Prefs.debugReset();
        await Prefs.ensureLoaded();
        final app = AppState.forTesting()
          ..user = profile(track: case_.track);
        addTearDown(app.dispose);
        expect(
          (await app.readCycleSettings()).enabled,
          case_.enabled,
          reason: 'legacy=${case_.legacy} track=${case_.track}',
        );
      }
    });

    test('new estimates default false; null/none situation remains', () async {
      final app = AppState.forTesting()
        ..user = profile(version: 1, track: true);
      addTearDown(app.dispose);
      var s = await app.readCycleSettings();
      expect(s.estimatesEnabled, isFalse);
      expect(s.situation, isNull);
      expect(s.lengthReviewEnabled, isFalse);

      app.user = profile(
        version: 1,
        track: true,
        estimates: true,
        repro: 'none',
        lengthReview: true,
      );
      s = await app.readCycleSettings();
      expect(s.estimatesEnabled, isTrue);
      expect(s.situation, CycleSituation.none);
      expect(s.lengthReviewEnabled, isTrue);
    });

    test('absent profile is unreadable, not intentionally off', () {
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      expect(app.readCycleSettings, throwsFormatException);
    });

    test('legacy getter does not throw on uninitialized profile', () {
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      expect(() => app.cycleTrackingEnabled, returnsNormally);
      expect(app.cycleTrackingEnabled, isFalse);
    });

    test('unreadable profile does not crash or persist a saved off', () async {
      final app = AppState.forTesting()
        ..user = {'cycle_preferences_version': 1, 'track_cycle': 'yes'};
      addTearDown(app.dispose);
      expect(() => app.cycleTrackingEnabled, returnsNormally);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('local_profile_json'), isNull);
      expect(prefs.getBool('cycle_tracking_enabled'), isNull);
    });

    test('unreadable keeps last readable enabled rather than collapsing off', () {
      final app = AppState.forTesting()
        ..user = profile(version: 1, track: true);
      addTearDown(app.dispose);
      expect(app.cycleTrackingEnabled, isTrue);
      app.user = {'cycle_preferences_version': 1, 'track_cycle': 2};
      expect(app.cycleTrackingEnabled, isTrue);
    });
  });

  group('saveCycleSettings persistence', () {
    test('writes version 1 fields and not a second enable preference', () async {
      SharedPreferences.setMockInitialValues({
        'cycle_tracking_enabled': false,
      });
      Prefs.debugReset();
      await Prefs.ensureLoaded();
      final app = AppState.forTesting()
        ..user = profile(track: false, name: 'Ada');
      addTearDown(app.dispose);
      await app.saveCycleSettings(
        const CycleSettings(
          enabled: true,
          estimatesEnabled: false,
          situation: CycleSituation.cycling,
          lengthReviewEnabled: false,
        ),
      );
      expect(app.user!['cycle_preferences_version'], 1);
      expect(app.user!['track_cycle'], isTrue);
      expect(app.user!['cycle_estimates'], isFalse);
      expect(app.user!['repro_state'], 'cycling');
      expect(app.user!['name'], 'Ada');
      expect(Prefs.getBool('cycle_tracking_enabled', true), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('cycle_tracking_enabled'), isFalse);
      expect(app.cycleTrackingEnabled, isTrue);
    });

    Future<_WriteOutcomeStore> installWriteStore() async {
      final inner = SharedPreferencesStorePlatform.instance;
      final store = _WriteOutcomeStore(inner);
      SharedPreferencesStorePlatform.instance = store;
      addTearDown(() => SharedPreferencesStorePlatform.instance = inner);
      return store;
    }

    Future<void> expectProfileNotCommitted({
      required AppState app,
      required Map<String, Object?> original,
    }) async {
      expect(app.user!['track_cycle'], isFalse);
      expect(app.user!['name'], 'Ada');
      final live = await SharedPreferences.getInstance();
      expect(
        jsonDecode(live.getString('local_profile_json')!),
        original,
      );
      SharedPreferences.resetStatic();
      Prefs.debugReset();
      final reloaded = await SharedPreferences.getInstance();
      expect(
        jsonDecode(reloaded.getString('local_profile_json')!),
        original,
        reason: 'next initialization must not see the failed write',
      );
    }

    test('failed prefs acknowledgement does not look committed', () async {
      final original = profile(version: 1, track: false, name: 'Ada');
      SharedPreferences.setMockInitialValues({
        'local_profile_json': jsonEncode(original),
      });
      Prefs.debugReset();
      await Prefs.ensureLoaded();
      final store = await installWriteStore();
      final app = AppState.forTesting()..user = Map<String, dynamic>.from(original);
      addTearDown(app.dispose);
      store.allowWrites = false;
      await expectLater(
        app.saveCycleSettings(
          const CycleSettings(
            enabled: true,
            estimatesEnabled: false,
            lengthReviewEnabled: false,
          ),
        ),
        throwsStateError,
      );
      await expectProfileNotCommitted(app: app, original: original);
    });

    test('thrown persistence does not look committed', () async {
      final original = profile(version: 1, track: false, name: 'Ada');
      SharedPreferences.setMockInitialValues({
        'local_profile_json': jsonEncode(original),
      });
      Prefs.debugReset();
      await Prefs.ensureLoaded();
      final store = await installWriteStore();
      final app = AppState.forTesting()..user = Map<String, dynamic>.from(original);
      addTearDown(app.dispose);
      store.throwOnWrite = true;
      await expectLater(
        app.saveCycleSettings(
          const CycleSettings(
            enabled: true,
            estimatesEnabled: false,
            lengthReviewEnabled: false,
          ),
        ),
        throwsStateError,
      );
      await expectProfileNotCommitted(app: app, original: original);
    });

    test('overlapping patches cannot lose unrelated fields', () async {
      final app = AppState.forTesting()
        ..user = profile(version: 1, track: false, name: 'Ada');
      addTearDown(app.dispose);
      final releaseFirst = Completer<void>();
      var writes = 0;
      app.debugBeforeProfileWrite = (_) async {
        writes++;
        if (writes == 1) await releaseFirst.future;
      };
      final first = app.updateProfile({'track_cycle': true});
      final second = app.updateProfile({'name': 'Bea'});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      releaseFirst.complete();
      await Future.wait([first, second]);
      expect(app.user!['track_cycle'], isTrue);
      expect(app.user!['name'], 'Bea');
      expect(app.user!['cycle_preferences_version'], 1);
    });

    test('off keeps all logs', () async {
      await LocalDb.putCycleLog('2026-06-01', 'start', note: 'keep');
      final app = AppState.forTesting()
        ..user = profile(version: 1, track: true);
      addTearDown(app.dispose);
      await app.saveCycleSettings(
        const CycleSettings(
          enabled: false,
          estimatesEnabled: false,
          lengthReviewEnabled: false,
        ),
      );
      final logs = await LocalDb.cycleLogs();
      expect(logs.single['date'], '2026-06-01');
      expect(logs.single['note'], 'keep');
    });

    test('setCycleTrackingEnabled delegates canonical save', () async {
      final app = AppState.forTesting()
        ..user = profile(track: false, estimates: true, repro: 'cycling');
      addTearDown(app.dispose);
      await app.setCycleTrackingEnabled(true);
      expect(app.user!['cycle_preferences_version'], 1);
      expect(app.user!['track_cycle'], isTrue);
      expect(app.user!['cycle_estimates'], isTrue);
      expect(app.user!['repro_state'], 'cycling');
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool('cycle_tracking_enabled'),
        isNull,
        reason: 'must not write a second enable preference',
      );
    });

    test('birth-date validation is preserved', () async {
      final app = AppState.forTesting()..user = {'name': 'Ada'};
      addTearDown(app.dispose);
      await expectLater(
        app.updateProfile({'birth_date': '1990-02-31'}),
        throwsFormatException,
      );
      expect(app.user, {'name': 'Ada'});
    });

    test('public refreshCycleContext propagates wake failure', () async {
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      final db = await LocalDb.instance;
      await db.execute('DROP TABLE compute_jobs');
      await expectLater(
        app.refreshCycleContext(),
        throwsA(isA<DatabaseException>()),
      );
      await LocalDb.close();
      final dir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
    });

    test('callback wake failure is not unhandled after commit', () async {
      final errors = <Object>[];
      await runZonedGuarded(() async {
        final app = AppState.forTesting();
        addTearDown(app.dispose);
        await LocalDb.close();
        LocalDb.onCycleContextInvalidated?.call();
        await Future<void>.delayed(Duration.zero);
      }, (e, _) => errors.add(e));
      expect(errors, isEmpty);
    });

    test('refreshCycleContext does not enqueue without a start-set change',
        () async {
      final app = AppState.forTesting()
        ..user = profile(version: 1, track: true);
      addTearDown(app.dispose);
      await app.saveCycleSettings(
        const CycleSettings(
          enabled: true,
          estimatesEnabled: false,
          lengthReviewEnabled: false,
        ),
      );
      await LocalDb.putCycleLog('2026-06-01', 'start', note: 'a');
      final db = await LocalDb.instance;
      await db.delete('compute_jobs');
      await LocalDb.putCycleLog('2026-06-01', 'start', note: 'b');
      await LocalDb.putCycleSymptoms('2026-06-01', ['cramp']);
      await app.refreshCycleContext();
      expect(
        await LocalDb.computeJobs(),
        isEmpty,
        reason: 'note/observation/settings must not create cycle-heavy work',
      );
    });

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

    test('production scheduler records durable compute error without dropping source',
        () async {
      await LocalDb.putCycleLog('2026-06-01', 'start');
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      app.debugDeriveEngine.debugAfterCrossDayCapture = () async {
        throw StateError('crossday boom');
      };
      await LocalDb.enqueueDeriveJob(
        type: 'derive_heavy',
        reason: LocalDb.kCycleContextJobReason,
      );
      await app.debugDeriveScheduler.debugDrain();
      final failed = await LocalDb.computeJobs(state: 'failed');
      expect(
        failed.any((j) => j['reason'] == LocalDb.kCycleContextJobReason),
        isTrue,
        reason: 'durable compute error must remain a failed cycle job',
      );
      expect(await LocalDb.computeJobs(state: 'queued'), isEmpty);
      expect(await LocalDb.cycleStartDates(), ['2026-06-01']);
      expect(await LocalDb.baseline('crossday'), isNull);
    });

    test('engine contention keeps successor then it runs',
        () async {
      final hold = Completer<void>();
      var locked = false;
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      app.debugDeriveEngine.debugBeforeRun = () async {
        if (locked) return;
        locked = true;
        await hold.future;
      };
      final first = app.debugDeriveEngine.run(
        const PersonalProfile(),
        heavy: true,
      );
      await untilAsync(
        () async => app.debugDeriveEngine.running,
        message: 'engine never took the process lock',
      );
      await LocalDb.enqueueDeriveJob(
        type: 'derive_heavy',
        reason: LocalDb.kCycleContextJobReason,
      );
      await app.debugDeriveScheduler.debugDrain();
      expect(
        (await LocalDb.computeJobs(state: 'queued')).any(
          (j) => j['reason'] == LocalDb.kCycleContextJobReason,
        ),
        isTrue,
        reason: 'busy drain must requeue the cycle job, not complete it',
      );
      expect(await LocalDb.computeJobs(state: 'failed'), isEmpty);
      hold.complete();
      await first;
      app.debugDeriveEngine.debugBeforeRun = null;
      await app.debugDeriveScheduler.debugDrain();
      expect(
        (await LocalDb.computeJobs()).any(
          (j) => j['reason'] == LocalDb.kCycleContextJobReason,
        ),
        isFalse,
        reason: 'after the lock is free the successor must be consumed',
      );
      expect(app.debugDeriveEngine.debugCrossDayPasses, greaterThan(0));
    });
  });
}
