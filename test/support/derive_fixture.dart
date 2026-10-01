import 'dart:convert';
import 'dart:math' as math;

import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final idempotenceProfile = PersonalProfile(
  birthDate: DateTime(1990, 5, 15),
  weightKg: 76,
  heightCm: 179,
  sex: 'm',
);
const fixtureDays = ['2026-09-13', '2026-09-14', '2026-09-15'];

Future<void> seedDeriveFixture(Database db) async {
  // Adapt the synthetic ADC/HR/RR row generator from
  // test/two_device_fixture_test.dart (fixtures/two_device_day.json).
  // Its constant movement and eight-hour extent are insufficient here:
  // use three civil days, quiet 22:00–06:00 nights, walking and exercise,
  // gen5 cumulative steps, and RR beats on their actual accumulated timeline.
  // Historical, distinct synthetic inputs make readiness's trailing baseline
  // usable on the FIRST run; no warm-up derivation conceals initial drift.
  final firstDay = DateTime.parse(fixtureDays.first);
  for (var i = 0; i < 28; i++) {
    final date = dayLabelOf(firstDay.subtract(Duration(days: 28 - i)));
    final hrv = 43.0 + (i % 11) * 2.1;
    final rhr = 54.0 + (i % 7);
    final readiness = 55.0 + (i % 13) * 2;
    final resp = 13.0 + (i % 9) * .3;
    final temp = 29700.0 + (i % 7) * 100;
    await LocalDb.putDayResult(
      dayId: date,
      algoVersion: kAlgoVersion,
      payloadJson: jsonEncode({
        'scalars': {
          'readiness': readiness,
          'rmssd': hrv,
          'rhr': rhr,
          'resp_rate': resp,
          'skin_temp_adc': temp,
        },
      }),
      windowJson: '{}',
      finalized: true,
      rmssd: hrv,
      rhr: rhr,
      readiness: readiness,
      source: 'band',
      deviceFamily: 'gen5',
      series: {
        'readiness': readiness,
        'rmssd': hrv,
        'ln_rmssd': math.log(hrv),
        'rhr': rhr,
        'resp_rate': resp,
        'skin_temp_adc': temp,
      },
    );
  }

  final start = firstDay.millisecondsSinceEpoch ~/ 1000;
  // The oldest fixture day stays within the 48h finalization horizon, so
  // BOTH heavy/force passes actually recompute all three source days.
  final end = DateTime(2026, 9, 15, 19).millisecondsSinceEpoch ~/ 1000;
  var steps = 0;
  var batch = db.batch();
  var pending = 0;
  Future<void> flush() async {
    await batch.commit(noResult: true);
    batch = db.batch();
    pending = 0;
  }

  for (var t = start; t < end; t++) {
    final local = DateTime.fromMillisecondsSinceEpoch(t * 1000);
    final sleep = local.hour >= 22 || local.hour < 6;
    final walking = local.hour == 12;
    final exercise = local.hour == 17;
    if (walking || exercise) steps += 2;
    final movement = sleep
        ? .002
        : exercise
        ? .35
        : walking
        ? .15
        : .012;
    final hr =
        ((sleep
                    ? 56
                    : exercise
                    ? 148
                    : walking
                    ? 103
                    : 74) +
                3 * math.sin((t - start) / 37) +
                (local.day - 13))
            .round();
    batch.insert('decoded_onehz', {
      'device_id': '',
      'ts_ms': t * 1000,
      'rec_ts': t,
      'counter': t - start,
      'hr': hr,
      'ax': movement * math.sin(t / 2),
      'ay': 0.0,
      'az': 1 + movement,
      'dyn_accel_g': movement,
      'skin_temp_raw': (30000 + 160 * math.sin(t / 1800)).round(),
      'device_family': 'gen5',
      'step_count': steps % 65536,
      'step_cadence': walking || exercise ? 120 : 0,
      'on_wrist': 1,
      'hr_valid': 1,
    });
    if (++pending >= 4000) await flush();
  }
  await flush();

  var beatMs = start * 1000;
  var beat = 0;
  final perSecond = <int, int>{};
  while (beatMs < end * 1000) {
    final local = DateTime.fromMillisecondsSinceEpoch(beatMs);
    final sleeping = local.hour >= 22 || local.hour < 6;
    // Respiratory sinus variation at 0.25 Hz, plus slower modulation. The
    // beat's timestamp advances by its RR, unlike one beat per fixed second.
    final rr =
        (1000 +
                55 * math.sin(beatMs / 1000 * math.pi / 2) +
                20 * math.sin(beat * .17))
            .round();
    if (sleeping) {
      final sec = beatMs ~/ 1000;
      final index = perSecond.update(sec, (v) => v + 1, ifAbsent: () => 0);
      batch.insert('decoded_rr', {
        'device_id': '',
        'ts_ms': sec * 1000,
        'rec_ts': sec,
        'beat_index': index,
        'rr_ts_ms': beatMs,
        'rr_ms': rr,
        'device_family': 'gen5',
      });
      if (++pending >= 4000) await flush();
    }
    beatMs += rr;
    beat++;
  }
  await flush();

  await db.insert('sessions', {
    'id': 'synthetic-exercise',
    'start_ts': DateTime(2026, 9, 14, 17).millisecondsSinceEpoch ~/ 1000,
    'end_ts': DateTime(2026, 9, 14, 18).millisecondsSinceEpoch ~/ 1000,
    'type': 'run',
    'status': 'done',
    'source': 'manual',
    'created_at': 1,
  });
}
