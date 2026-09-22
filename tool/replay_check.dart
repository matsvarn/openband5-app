// Bounded raw-replay check: prove `raw_blob` actually re-derives the seconds
// it stores — the retention is only worth its cost if the replay path is
// exercised once.
//
// Reads a pulled device DB (read-only), inflates every raw_blob batch
// (gzip, u16le-length-prefixed inner frames — same layout `rawBlobRecords`
// emits), decodes them through the ONE decode point (`decodeSubstrate`), and
// diffs the replayed fields against the `decoded_onehz` row at the same
// rec_ts. Reports per-field mismatch counts and the worst offenders.
//
// Run: dart run tool/replay_check.dart /path/to/openstrap.db
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';

import 'package:openstrap_edge/compute/substrate.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/replay_check.dart <db>');
    exit(2);
  }
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    args[0],
    options: OpenDatabaseOptions(readOnly: true),
  );

  final blobs = await db.query('raw_blob', orderBy: 'first_counter');
  print('raw_blob batches: ${blobs.length}');

  // Inflate all batches → hex lines → one decode pass.
  final hexes = <String>[];
  var declared = 0;
  for (final b in blobs) {
    declared += (b['n'] as num).toInt();
    final payload = b['payload'];
    if ((b['codec'] as num) != 1 || payload is! Uint8List) {
      print('  !! batch ${b['first_counter']}: codec ${b['codec']} — skipped');
      continue;
    }
    final raw = gzip.decode(payload);
    var i = 0;
    while (i + 2 <= raw.length) {
      final len = raw[i] | (raw[i + 1] << 8);
      if (len <= 0 || i + 2 + len > raw.length) break;
      hexes.add([
        for (final x in raw.sublist(i + 2, i + 2 + len))
          x.toRadixString(16).padLeft(2, '0'),
      ].join());
      i += 2 + len;
    }
  }
  print('inflated ${hexes.length} frames (declared $declared)');

  final sub = decodeSubstrate(hexes);
  print('decoded substrate: ${sub.length} s '
      '(${hexes.length - sub.length} frames refused/dropped)');

  // Join on rec_ts against decoded_onehz.
  var matched = 0;
  var hrDiff = 0, tempDiff = 0, stepDiff = 0, absentInStore = 0;
  final examples = <String>[];
  for (var i = 0; i < sub.length; i++) {
    final rows = await db.query('decoded_onehz',
        where: 'rec_ts = ?', whereArgs: [sub.tsSec[i]], limit: 1);
    if (rows.isEmpty) {
      absentInStore++;
      continue;
    }
    matched++;
    final r = rows.single;
    // hr: substrate drops implausible values to 0; stored keeps raw too.
    final storedHr = (r['hr'] as num?)?.toInt() ?? 0;
    if (sub.hr[i] != 0 && storedHr != sub.hr[i]) {
      hrDiff++;
      if (examples.length < 8) {
        examples.add('ts ${sub.tsSec[i]}: hr stored=$storedHr '
            'replayed=${sub.hr[i]}');
      }
    }
    // skin temp: stored skin_temp_c (°C) vs replayed centi-°C. BOTH
    // directions count: a stored value with a replayed 0 is the loss the
    // _Rec.gen5 fix exists to remove, not a non-diff.
    final storedC = (r['skin_temp_c'] as num?)?.toDouble();
    final replayedCenti = sub.skinTemp[i];
    if ((storedC != null) != (replayedCenti != 0)) {
      tempDiff++;
      if (examples.length < 8) {
        examples.add('ts ${sub.tsSec[i]}: temp_c stored=$storedC '
            'replayed=${replayedCenti / 100} (presence disagree)');
      }
    } else if (storedC != null &&
        (storedC * 100 - replayedCenti).abs() > 1) {
      tempDiff++;
      if (examples.length < 8) {
        examples.add('ts ${sub.tsSec[i]}: temp_c stored=$storedC '
            'replayed=${replayedCenti / 100}');
      }
    }
    final storedSteps = (r['step_count'] as num?)?.toInt();
    final replayedSteps = sub.stepCount[i] < 0 ? null : sub.stepCount[i];
    if (storedSteps != null && replayedSteps != null &&
        storedSteps != replayedSteps) {
      stepDiff++;
    }
  }

  print('matched $matched/${sub.length} replayed seconds to stored rows');
  print('  hr mismatches:      $hrDiff');
  print('  skin-temp mismatch: $tempDiff  (c stored vs centi replayed)');
  print('  step mismatches:    $stepDiff');
  print('  replayed seconds with NO stored row: $absentInStore '
      '(commit-before-ACK violation if >0)');
  for (final e in examples) {
    print('   !! $e');
  }
  await db.close();
  exit(absentInStore > 0 || hrDiff > 0 || tempDiff > 0 ? 1 : 0);
}
