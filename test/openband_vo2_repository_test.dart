import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/vo2_store.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

SyntheticOpenBandRepository _synthetic() =>
    SyntheticOpenBandRepository.fromMaps(
      jsonDecode(
            File(
              'docs/openband5/assets/fixtures/day-summary.json',
            ).readAsStringSync(),
          )
          as Map,
      jsonDecode(
            File(
              'docs/openband5/assets/fixtures/sleep-detail.json',
            ).readAsStringSync(),
          )
          as Map,
    );

Vo2Revision _stored(Vo2WriteResult result) {
  expect(result, isA<Vo2Committed>());
  final committed = result as Vo2Committed;
  expect(committed.retry, isFalse);
  return committed.revision;
}

void _contract(OpenBandRepository Function() current) {
  test('create edit remove restore retries and conflicts', () async {
    final repo = current();
    const id = 'vo2-1';
    final before = DateTime.now().millisecondsSinceEpoch;
    final created = _stored(
      await repo.createVo2Entry(
        id: id,
        measuredOn: '2026-09-14',
        valueMlKgMin: 42,
        declaredMethod: '  Spiroergometrie  ',
      ),
    );
    final after = DateTime.now().millisecondsSinceEpoch;
    expect(created.revision, 1);
    expect(created.measuredOn, '2026-09-14');
    expect(created.valueMlKgMin, 42);
    expect(created.declaredMethod, 'Spiroergometrie');
    expect(created.deleted, isFalse);
    expect(created.origin, kVo2Origin);
    expect(created.unit, kVo2Unit);
    expect(created.createdAt, inInclusiveRange(before, after));
    expect(created.updatedAt, created.createdAt);

    final again = await repo.createVo2Entry(
      id: id,
      measuredOn: '2026-09-14',
      valueMlKgMin: 42,
      declaredMethod: 'Spiroergometrie',
    );
    expect(again, isA<Vo2Committed>());
    expect((again as Vo2Committed).retry, isTrue);
    expect(again.revision.sameStored(created), isTrue);
    expect((await repo.readVo2Entry(id)).revisions, hasLength(1));

    final clash = await repo.createVo2Entry(
      id: id,
      measuredOn: '2026-09-14',
      valueMlKgMin: 43,
      declaredMethod: 'Spiroergometrie',
    );
    expect(clash, isA<Vo2WriteConflict>());
    final clashHead = clash as Vo2WriteConflict;
    expect(clashHead.headCorrupt, isFalse);
    expect(clashHead.head?.sameStored(created), isTrue);

    final edited = _stored(
      await repo.editVo2Entry(
        id: id,
        expectedRevision: 1,
        measuredOn: '2026-09-01',
        valueMlKgMin: 180.5,
        declaredMethod: 'Feldtest',
      ),
    );
    expect(edited.revision, 2);
    expect(edited.measuredOn, '2026-09-01');
    expect(edited.valueMlKgMin, 180.5);
    expect(edited.declaredMethod, 'Feldtest');
    expect(edited.createdAt, created.createdAt);
    expect(edited.updatedAt, greaterThan(created.updatedAt));
    expect(edited.origin, kVo2Origin);
    expect(edited.unit, kVo2Unit);
    expect(edited.deleted, isFalse);

    final editRetry = await repo.editVo2Entry(
      id: id,
      expectedRevision: 1,
      measuredOn: '2026-09-01',
      valueMlKgMin: 180.5,
      declaredMethod: 'Feldtest',
    );
    expect(editRetry, isA<Vo2Committed>());
    expect((editRetry as Vo2Committed).retry, isTrue);
    expect(editRetry.revision.sameStored(edited), isTrue);

    final stale = await repo.editVo2Entry(
      id: id,
      expectedRevision: 1,
      measuredOn: '2026-09-02',
      valueMlKgMin: 50,
    );
    expect(stale, isA<Vo2WriteConflict>());
    expect((stale as Vo2WriteConflict).head?.sameStored(edited), isTrue);
    expect((await repo.readVo2Entry(id)).revisions, hasLength(2));

    final removed = _stored(
      await repo.removeVo2Entry(id: id, expectedRevision: 2),
    );
    expect(removed.revision, 3);
    expect(removed.deleted, isTrue);
    expect(removed.measuredOn, edited.measuredOn);
    expect(removed.valueMlKgMin, edited.valueMlKgMin);
    expect(removed.declaredMethod, edited.declaredMethod);
    expect(removed.createdAt, created.createdAt);
    expect(removed.origin, kVo2Origin);
    expect(removed.unit, kVo2Unit);
    final whileDeleted = await repo.readVo2Entries();
    expect(whileDeleted.isEmptyStore, isFalse);
    expect(whileDeleted.entries.single.head?.sameStored(removed), isTrue);

    final removeRetry = await repo.removeVo2Entry(id: id, expectedRevision: 2);
    expect(removeRetry, isA<Vo2Committed>());
    expect((removeRetry as Vo2Committed).retry, isTrue);
    expect(removeRetry.revision.sameStored(removed), isTrue);
    expect(
      await repo.removeVo2Entry(id: id, expectedRevision: 3),
      isA<Vo2WriteConflict>(),
    );

    final restored = _stored(
      await repo.restoreVo2Entry(id: id, expectedRevision: 3),
    );
    expect(restored.revision, 4);
    expect(restored.deleted, isFalse);
    expect(restored.measuredOn, removed.measuredOn);
    expect(restored.valueMlKgMin, removed.valueMlKgMin);
    expect(restored.declaredMethod, removed.declaredMethod);
    expect(restored.createdAt, created.createdAt);
    expect(restored.origin, kVo2Origin);
    expect(restored.unit, kVo2Unit);

    final restoreRetry = await repo.restoreVo2Entry(
      id: id,
      expectedRevision: 3,
    );
    expect(restoreRetry, isA<Vo2Committed>());
    expect((restoreRetry as Vo2Committed).retry, isTrue);
    expect(restoreRetry.revision.sameStored(restored), isTrue);
    expect(
      await repo.restoreVo2Entry(id: id, expectedRevision: 4),
      isA<Vo2WriteConflict>(),
    );

    final detail = await repo.readVo2Entry(id);
    expect(detail.missing, isFalse);
    expect(detail.headCorrupt, isFalse);
    expect(detail.corruptRevisionCount, 0);
    expect(detail.revisions, hasLength(4));
    expect(detail.head?.sameStored(restored), isTrue);
    expect(detail.revisions.first.value?.sameStored(created), isTrue);
    final list = await repo.readVo2Entries();
    expect(list.rowCount, 4);
    expect(list.corruptCount, 0);
    expect(list.entries.single.head?.sameStored(restored), isTrue);
  });

  test('blank method is stored absent and a label is not a verified test', () async {
    final repo = current();
    final created = _stored(
      await repo.createVo2Entry(
        id: 'method',
        measuredOn: '2026-09-14',
        valueMlKgMin: 42,
        declaredMethod: '   ',
      ),
    );
    expect(created.declaredMethod, isNull);
    final labeled = _stored(
      await repo.editVo2Entry(
        id: 'method',
        expectedRevision: 1,
        measuredOn: '2026-09-14',
        valueMlKgMin: 42,
        declaredMethod: 'not-a-lab',
      ),
    );
    expect(labeled.declaredMethod, 'not-a-lab');
    final cleared = _stored(
      await repo.editVo2Entry(
        id: 'method',
        expectedRevision: 2,
        measuredOn: '2026-09-14',
        valueMlKgMin: 42,
      ),
    );
    expect(cleared.declaredMethod, isNull);
    expect(cleared.origin, kVo2Origin);
    expect(cleared.unit, kVo2Unit);
    expect(cleared.createdAt, created.createdAt);
  });

  test('finite positive values and real civil dates only', () async {
    final repo = current();
    final rejected = <Future<Vo2WriteResult> Function()>[
      () => repo.createVo2Entry(
        id: ' bad',
        measuredOn: '2026-09-14',
        valueMlKgMin: 42,
      ),
      () => repo.createVo2Entry(
        id: '',
        measuredOn: '2026-09-14',
        valueMlKgMin: 42,
      ),
      () => repo.createVo2Entry(
        id: 'zero',
        measuredOn: '2026-09-14',
        valueMlKgMin: 0,
      ),
      () => repo.createVo2Entry(
        id: 'neg',
        measuredOn: '2026-09-14',
        valueMlKgMin: -1,
      ),
      () => repo.createVo2Entry(
        id: 'nan',
        measuredOn: '2026-09-14',
        valueMlKgMin: double.nan,
      ),
      () => repo.createVo2Entry(
        id: 'inf',
        measuredOn: '2026-09-14',
        valueMlKgMin: double.infinity,
      ),
      () => repo.createVo2Entry(
        id: 'leap',
        measuredOn: '2026-02-29',
        valueMlKgMin: 42,
      ),
      () => repo.createVo2Entry(
        id: 'month',
        measuredOn: '2026-09-31',
        valueMlKgMin: 42,
      ),
      () => repo.editVo2Entry(
        id: 'nope',
        expectedRevision: 0,
        measuredOn: '2026-09-14',
        valueMlKgMin: 42,
      ),
      () => repo.removeVo2Entry(id: 'nope', expectedRevision: 0),
    ];
    for (final call in rejected) {
      final result = await call();
      expect(result, isA<Vo2WriteRejected>());
      expect((result as Vo2WriteRejected).reason, Vo2RejectReason.invalid);
    }
    expect((await repo.readVo2Entries()).isEmptyStore, isTrue);

    final missing = await repo.editVo2Entry(
      id: 'nope',
      expectedRevision: 1,
      measuredOn: '2026-09-14',
      valueMlKgMin: 42,
    );
    expect(missing, isA<Vo2WriteRejected>());
    expect((missing as Vo2WriteRejected).reason, Vo2RejectReason.missing);
    final absent = await repo.readVo2Entry('nope');
    expect(absent.missing, isTrue);
    expect(absent.head, isNull);
    expect(absent.headCorrupt, isFalse);
    expect(absent.revisions, isEmpty);
    expect((await repo.readVo2Entry(' nope')).missing, isTrue);

    final big = _stored(
      await repo.createVo2Entry(
        id: 'big',
        measuredOn: '2024-02-29',
        valueMlKgMin: 10000,
      ),
    );
    expect(big.measuredOn, '2024-02-29');
    expect(big.valueMlKgMin, 10000);
    expect(big.declaredMethod, isNull);
    final reread = await repo.readVo2Entry('big');
    expect(reread.head?.sameStored(big), isTrue);
  });

  test('same-day ids stay distinct and later dates stay listed', () async {
    final repo = current();
    final first = _stored(
      await repo.createVo2Entry(
        id: 'vo2-b',
        measuredOn: '2026-09-14',
        valueMlKgMin: 42,
        declaredMethod: 'Spiroergometrie',
      ),
    );
    final second = _stored(
      await repo.createVo2Entry(
        id: 'vo2-a',
        measuredOn: '2026-09-14',
        valueMlKgMin: 42,
        declaredMethod: 'Spiroergometrie',
      ),
    );
    final later = _stored(
      await repo.createVo2Entry(
        id: 'vo2-c',
        measuredOn: '2026-12-31',
        valueMlKgMin: 41,
      ),
    );
    final removed = _stored(
      await repo.removeVo2Entry(id: 'vo2-b', expectedRevision: first.revision),
    );
    final list = await repo.readVo2Entries();
    expect(list.entries.map((e) => e.id), ['vo2-a', 'vo2-b', 'vo2-c']);
    expect(list.entries[0].head?.sameStored(second), isTrue);
    expect(list.entries[1].head?.sameStored(removed), isTrue);
    expect(list.entries[1].head?.deleted, isTrue);
    expect(list.entries[2].head?.sameStored(later), isTrue);
    expect(
      list.entries.where((e) => e.head?.measuredOn == '2026-09-14'),
      hasLength(2),
    );
  });

  test('restore against an active same-value edit is a conflict', () async {
    final repo = current();
    const id = 'same';
    final created = _stored(
      await repo.createVo2Entry(
        id: id,
        measuredOn: '2026-09-14',
        valueMlKgMin: 42,
        declaredMethod: 'Spiroergometrie',
      ),
    );
    final edited = _stored(
      await repo.editVo2Entry(
        id: id,
        expectedRevision: created.revision,
        measuredOn: '2026-09-14',
        valueMlKgMin: 42,
        declaredMethod: 'Spiroergometrie',
      ),
    );
    expect(edited.revision, created.revision + 1);
    expect(edited.deleted, isFalse);
    expect(edited.measuredOn, created.measuredOn);
    expect(edited.valueMlKgMin, created.valueMlKgMin);
    expect(edited.declaredMethod, created.declaredMethod);

    final restore = await repo.restoreVo2Entry(
      id: id,
      expectedRevision: created.revision,
    );
    expect(restore, isA<Vo2WriteConflict>());
    final conflict = restore as Vo2WriteConflict;
    expect(conflict.headCorrupt, isFalse);
    expect(conflict.head?.sameStored(edited), isTrue);
    final detail = await repo.readVo2Entry(id);
    expect(detail.revisions, hasLength(2));
    expect(detail.head?.deleted, isFalse);
    expect(detail.head?.valueMlKgMin, 42);
    expect(detail.head?.declaredMethod, 'Spiroergometrie');
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('synthetic', () {
    late SyntheticOpenBandRepository repo;
    setUp(() => repo = _synthetic());
    _contract(() => repo);

    test('resting heart rate and journal weight are not VO2', () async {
      final day = await repo.readDay('2026-09-15');
      expect(day.restingHr.value, 54);
      expect((await repo.readVo2Entries()).isEmptyStore, isTrue);

      repo.seedJournalEditor(filled: true);
      repo.seedWeightHistory();
      expect((await repo.readVo2Entries()).isEmptyStore, isTrue);
      final before = await repo.readWeightHistory('2026-09-15', 7);
      expect(before.entries, isNotEmpty);

      repo.seedVo2Paper();
      final after = await repo.readWeightHistory('2026-09-15', 7);
      expect(after.latest?.value, before.latest?.value);
      expect(after.entries, hasLength(before.entries.length));
      final list = await repo.readVo2Entries();
      final head = list.entries.single.head!;
      expect(head.valueMlKgMin, kSyntheticVo2PaperValue);
      expect(head.declaredMethod, kSyntheticVo2PaperMethod);
      expect(head.measuredOn, kSyntheticVo2PaperDay);
      expect(head.deleted, isFalse);
      expect(head.origin, kVo2Origin);
      expect(head.unit, kVo2Unit);
    });

    test('removed paper seed restores the same payload', () async {
      repo.seedVo2Paper(removed: true);
      final head = (await repo.readVo2Entries()).entries.single.head!;
      expect(head.deleted, isTrue);
      expect(head.valueMlKgMin, 42);
      expect(head.declaredMethod, 'Spiroergometrie');
      expect(head.measuredOn, '2026-09-14');
      final restored = _stored(
        await repo.restoreVo2Entry(
          id: kSyntheticVo2PaperId,
          expectedRevision: head.revision,
        ),
      );
      expect(restored.deleted, isFalse);
      expect(restored.valueMlKgMin, 42);
      expect(restored.declaredMethod, 'Spiroergometrie');
      expect(restored.measuredOn, '2026-09-14');
      expect(restored.createdAt, head.createdAt);
    });

    test('corrupt paper head does not fall back to 42.0', () async {
      repo.seedVo2Paper(corruptHead: true);
      final kept = _stored(
        await repo.createVo2Entry(
          id: 'vo2-kept',
          measuredOn: '2026-09-14',
          valueMlKgMin: 55,
        ),
      );
      final list = await repo.readVo2Entries();
      expect(list.isEmptyStore, isFalse);
      expect(list.corruptCount, 1);
      final paper = list.entries.singleWhere(
        (e) => e.id == kSyntheticVo2PaperId,
      );
      expect(paper.corrupt, isTrue);
      expect(paper.head, isNull);
      expect(
        list.entries.singleWhere((e) => e.id == 'vo2-kept').head?.sameStored(
          kept,
        ),
        isTrue,
      );
      final detail = await repo.readVo2Entry(kSyntheticVo2PaperId);
      expect(detail.missing, isFalse);
      expect(detail.headCorrupt, isTrue);
      expect(detail.head, isNull);
      expect(detail.revisions.first.value?.valueMlKgMin, 42);
      expect(detail.revisions.last.corrupt, isTrue);
      expect(detail.revisions.last.value, isNull);
      expect(detail.corruptRevisionCount, 1);

      final write = await repo.editVo2Entry(
        id: kSyntheticVo2PaperId,
        expectedRevision: 1,
        measuredOn: '2026-09-14',
        valueMlKgMin: 50,
      );
      expect(write, isA<Vo2WriteConflict>());
      expect((write as Vo2WriteConflict).headCorrupt, isTrue);
      expect(write.head, isNull);
      expect(
        (await repo.readVo2Entry(kSyntheticVo2PaperId)).revisions,
        hasLength(2),
      );
    });

    test('restore of an active same-value edit is a conflict', () async {
      var now = DateTime(2026, 9, 21, 8);
      repo.vo2Now = () => now;
      final created = _stored(
        await repo.createVo2Entry(
          id: 'same',
          measuredOn: '2026-09-14',
          valueMlKgMin: 42,
          declaredMethod: 'Spiroergometrie',
        ),
      );
      expect(created.createdAt, now.millisecondsSinceEpoch);
      now = DateTime(2026, 9, 21, 9);
      final edited = _stored(
        await repo.editVo2Entry(
          id: 'same',
          expectedRevision: 1,
          measuredOn: '2026-09-14',
          valueMlKgMin: 42,
          declaredMethod: 'Spiroergometrie',
        ),
      );
      expect(edited.revision, 2);
      expect(edited.updatedAt, now.millisecondsSinceEpoch);
      expect(edited.createdAt, created.createdAt);

      final restore = await repo.restoreVo2Entry(
        id: 'same',
        expectedRevision: 1,
      );
      expect(restore, isA<Vo2WriteConflict>());
      final conflict = restore as Vo2WriteConflict;
      expect(conflict.headCorrupt, isFalse);
      expect(conflict.head?.sameStored(edited), isTrue);
      final detail = await repo.readVo2Entry('same');
      expect(detail.revisions, hasLength(2));
      expect(detail.head?.deleted, isFalse);
      expect(detail.head?.valueMlKgMin, 42);

      now = DateTime(2026, 9, 21, 7);
      final bumped = _stored(
        await repo.editVo2Entry(
          id: 'same',
          expectedRevision: 2,
          measuredOn: '2026-09-14',
          valueMlKgMin: 43,
          declaredMethod: 'Spiroergometrie',
        ),
      );
      expect(bumped.updatedAt, edited.updatedAt + 1);
      expect(bumped.createdAt, created.createdAt);
      now = DateTime(2026, 9, 21, 12);
      final retry = await repo.editVo2Entry(
        id: 'same',
        expectedRevision: 2,
        measuredOn: '2026-09-14',
        valueMlKgMin: 43,
        declaredMethod: 'Spiroergometrie',
      );
      expect(retry, isA<Vo2Committed>());
      expect((retry as Vo2Committed).retry, isTrue);
      expect(retry.revision.sameStored(bumped), isTrue);
      expect((await repo.readVo2Entry('same')).revisions, hasLength(3));
    });

    test('read and write failures stay errors', () async {
      repo.failVo2Write = true;
      await expectLater(
        repo.createVo2Entry(
          id: 'x',
          measuredOn: '2026-09-14',
          valueMlKgMin: 42,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'synthetic vo2 save failure',
          ),
        ),
      );
      repo.failVo2Write = false;
      expect((await repo.readVo2Entries()).isEmptyStore, isTrue);

      repo.seedVo2Paper();
      repo.failVo2Read = true;
      await expectLater(
        repo.readVo2Entries(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'synthetic vo2 read failure',
          ),
        ),
      );
      await expectLater(
        repo.readVo2Entry(kSyntheticVo2PaperId),
        throwsA(isA<StateError>()),
      );
      repo.failVo2Read = false;
      repo.failVo2Write = true;
      await expectLater(
        repo.editVo2Entry(
          id: kSyntheticVo2PaperId,
          expectedRevision: 1,
          measuredOn: '2026-09-14',
          valueMlKgMin: 43,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'synthetic vo2 save failure',
          ),
        ),
      );
      repo.failVo2Write = false;
      final detail = await repo.readVo2Entry(kSyntheticVo2PaperId);
      expect(detail.revisions, hasLength(1));
      expect(detail.head?.valueMlKgMin, 42);
    });
  });

  group('SQLite', () {
    late AppState app;
    late LocalOpenBandRepository repo;
    const dbName = 'openband_vo2_repository_test.db';

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      await LocalDb.close();
      LocalDb.dbName = dbName;
      final dir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase('$dir/$dbName');
      app = AppState.forTesting();
      app.user = {'weight_kg': 75, 'resting_hr': 54};
      repo = LocalOpenBandRepository(app);
    });

    tearDown(() async {
      app.dispose();
      await LocalDb.close();
    });

    _contract(() => repo);

    test('profile weight and resting heart rate are not entries', () async {
      expect(app.user?['weight_kg'], 75);
      expect(app.user?['resting_hr'], 54);
      expect((await repo.readVo2Entries()).isEmptyStore, isTrue);
      expect((await repo.readWeightHistory('2026-09-15', 7)).entries, isEmpty);

      await repo.createVo2Entry(
        id: 'vo2-paper',
        measuredOn: '2026-09-14',
        valueMlKgMin: 42,
        declaredMethod: 'Spiroergometrie',
      );
      expect(app.user?['weight_kg'], 75);
      expect(app.user?['resting_hr'], 54);
      expect((await repo.readWeightHistory('2026-09-15', 7)).entries, isEmpty);
      final head = (await repo.readVo2Entries()).entries.single.head!;
      expect(head.valueMlKgMin, 42);
      expect(head.declaredMethod, 'Spiroergometrie');
      expect(head.measuredOn, '2026-09-14');
      expect(head.origin, kVo2Origin);
      expect(head.unit, kVo2Unit);
    });

    test('corrupt head does not fall back to an older value', () async {
      final created = _stored(
        await repo.createVo2Entry(
          id: 'bad',
          measuredOn: '2026-09-14',
          valueMlKgMin: 42,
          declaredMethod: 'Spiroergometrie',
        ),
      );
      final kept = _stored(
        await repo.createVo2Entry(
          id: 'ok',
          measuredOn: '2026-09-14',
          valueMlKgMin: 55,
        ),
      );
      final db = await LocalDb.instance;
      await db.insert(kManualVo2Table, {
        'id': 'bad',
        'revision': 2,
        'measured_on': 'not-a-day',
        'value_ml_kg_min': 99,
        'declared_method': 'Spiroergometrie',
        'created_at': created.createdAt,
        'updated_at': created.updatedAt + 1,
        'deleted': 0,
        'origin': kVo2Origin,
        'unit': kVo2Unit,
      });

      final list = await repo.readVo2Entries();
      expect(list.corruptCount, 1);
      expect(list.rowCount, 3);
      final bad = list.entries.singleWhere((e) => e.id == 'bad');
      expect(bad.corrupt, isTrue);
      expect(bad.head, isNull);
      expect(
        list.entries.singleWhere((e) => e.id == 'ok').head?.sameStored(kept),
        isTrue,
      );
      final detail = await repo.readVo2Entry('bad');
      expect(detail.head, isNull);
      expect(detail.headCorrupt, isTrue);
      expect(detail.missing, isFalse);
      expect(detail.revisions, hasLength(2));
      expect(detail.revisions.first.value?.valueMlKgMin, 42);
      expect(detail.revisions.last.corrupt, isTrue);
      expect(detail.revisions.last.value, isNull);
      expect(detail.corruptRevisionCount, 1);

      final writes = <Future<Vo2WriteResult> Function()>[
        () => repo.editVo2Entry(
          id: 'bad',
          expectedRevision: 1,
          measuredOn: '2026-09-14',
          valueMlKgMin: 50,
        ),
        () => repo.removeVo2Entry(id: 'bad', expectedRevision: 1),
        () => repo.restoreVo2Entry(id: 'bad', expectedRevision: 1),
      ];
      for (final call in writes) {
        final write = await call();
        expect(write, isA<Vo2WriteConflict>());
        expect((write as Vo2WriteConflict).headCorrupt, isTrue);
        expect(write.head, isNull);
      }
      expect((await repo.readVo2Entry('bad')).revisions, hasLength(2));
    });

    test('detail returns every revision across a chain page', () async {
      const id = 'long';
      var revision = _stored(
        await repo.createVo2Entry(
          id: id,
          measuredOn: '2026-09-14',
          valueMlKgMin: 1,
        ),
      );
      for (var next = 2; next <= 33; next++) {
        revision = _stored(
          await repo.editVo2Entry(
            id: id,
            expectedRevision: next - 1,
            measuredOn: '2026-09-14',
            valueMlKgMin: next.toDouble(),
          ),
        );
      }
      expect(revision.revision, 33);
      final detail = await repo.readVo2Entry(id);
      expect(detail.revisions, hasLength(33));
      expect(detail.corruptRevisionCount, 0);
      expect(detail.head?.revision, 33);
      expect(detail.head?.valueMlKgMin, 33);
      expect(detail.revisions[31].value?.revision, 32);
      expect(detail.revisions[32].value?.revision, 33);
      final list = await repo.readVo2Entries();
      expect(list.rowCount, 33);
      expect(list.entries.single.head?.revision, 33);
    });
  });
}
