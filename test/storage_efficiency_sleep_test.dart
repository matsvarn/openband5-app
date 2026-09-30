import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/compute/derive_prepare.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/data/db.dart';

SleepSessionCandidate candidate(List<String> stages, {int onset = 0}) =>
  SleepSessionCandidate(dayId: '2026-01-05', confidence: 0.9,
    flags: const [], sleepJson: {'tst_sec': stages.length},
    hypnoStages: stages, sleepOnsetSec: onset,
    sleepOffsetSec: onset + stages.length);

void main() {
  for (final entry in <String, List<String>>{
    'empty': [], 'single run': List.filled(34000, 'light'),
    'long night': [...List.filled(12000, 'light'), ...List.filled(9000, 'deep'),
      ...List.filled(4000, 'wake'), ...List.filled(9000, 'rem')],
  }.entries) {
    test('${entry.key} round-trips exactly through the storage JSON', () {
      final original = candidate(entry.value);
      final stored = jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>;
      expect(stored['hypno_stages'], isA<String>());
      expect(() => stored['hypno_stages'] as List?, throwsA(isA<TypeError>()));
      final read = SleepSessionCandidate.fromJson(stored);
      expect(read.hypnoStages, original.hypnoStages);
      expect(read.toJson(), original.toJson());
      if (entry.value.length > 1000) {
        expect(jsonEncode(stored).length, lessThan(jsonEncode(entry.value).length ~/ 100));
      }
    });
  }
  test('legacy list remains readable; unknown or invalid runs fail loudly', () {
    final original = candidate(['wake', 'light', 'deep', 'rem']);
    final legacy = {...original.toJson(), 'hypno_stages': original.hypnoStages};
    expect(SleepSessionCandidate.fromJson(legacy).hypnoStages, original.hypnoStages);
    for (final stages in ['rle2:[]', 'rle1:{}', 'rle1:[["rem",0]]']) {
      expect(() => SleepSessionCandidate.fromJson({...legacy, 'hypno_stages': stages}),
        throwsFormatException);
    }
  });

  test('real derivation reuses encoded and legacy cached candidates identically', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('ob5-sleep-');
    await databaseFactory.setDatabasesPath(temp.path);
    final onset = DateTime(2026, 1, 5, 1).millisecondsSinceEpoch ~/ 1000;
    final original = candidate([...List.filled(60, 'light'), ...List.filled(60, 'deep')], onset: onset);
    final results = <String>[];
    try {
      for (final encoded in [false, true]) {
        LocalDb.dbName = encoded ? 'encoded.db' : 'legacy.db';
        final db = await LocalDb.instance;
        await db.transaction((txn) async {
          final batch = txn.batch();
          for (var i = 0; i < 120; i++) {
            batch.insert('decoded_onehz', {'rec_ts': onset + i,
              'ts_ms': (onset + i) * 1000, 'counter': i + 1,
              'hr': 60, 'ax': 0, 'ay': 0, 'az': 1});
          }
          await batch.commit(noResult: true);
        });
        await LocalDb.putDayResult(dayId: original.dayId, algoVersion: kAlgoVersion,
          payloadJson: '{}', windowJson: '{}', finalized: true);
        final payload = original.toJson();
        if (!encoded) payload['hypno_stages'] = original.hypnoStages;
        final stored = jsonEncode(payload);
        await LocalDb.putSleepSessionCandidate(dayId: original.dayId,
          algoVersion: kAlgoVersion, payloadJson: stored);
        expect(await DerivationEngine().runDays(const PersonalProfile(), {original.dayId}, force: true), 1);
        // No staging overwrite: this is a cached-candidate derive.
        expect((await LocalDb.sleepSessionCandidate(original.dayId, kAlgoVersion))!['payload_json'], stored);
        results.add((await LocalDb.dayResult(original.dayId))!['payload_json'] as String);
        await LocalDb.close();
      }
      expect(results[1], results[0]);
    } finally {
      await LocalDb.close();
      await temp.delete(recursive: true);
    }
  });
}
