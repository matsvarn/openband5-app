// Tests for the on-device wake alarm:
//   - the exact SET_ALARM_TIME byte layouts: the REV-1 9-byte form (the one
//     gen4 firmware executes — pinned against the official app's wire capture
//     and our own on-device fire, 2026-08-19), the gen5 rich 21-byte slot-1
//     body, the reference-only rich/short forms, and the RUN/DISABLE bodies
//     (AlarmPayloads),
//   - the strap-event confirmation state machine (AlarmConfirmation), and
//   - the arm/run decision made on the correlated reply's alarm-status byte,
//     driven over the engine's fake-link seam.
// No radio and no DB — everything here is deterministic.

import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/ble_engine.dart';
import 'package:openstrap_edge/ble/ble_state.dart';
import 'package:openstrap_edge/state/alarm_schedule.dart' show alarmLatchFailed;
import 'package:openstrap_edge/state/alarm_cancel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openstrap_edge/sync/sync_policy.dart' show ClockRef;
import 'package:openstrap_protocol/openstrap_protocol.dart' as proto;

/// A gen5 link with no radio behind it, plus the seq of every command written.
/// Same seam as `command_correlation_test.dart`: the reply is injected from
/// INSIDE the write, i.e. before the write call returns, which is the ordering
/// the correlation contract demands and the one a fast strap produces.
class _Link {
  final logs = <String>[];
  final written = <({int seq, int opcode})>[];
  late final BleEngine engine;

  _Link({proto.Decoded? Function(int seq, int opcode)? replyTo}) {
    engine = BleEngine(onRecord: (_, _) async {}, onState: (_) {}, log: logs.add);
    engine.debugInstallFakeLink(
      band: proto.BandProfile.gen5,
      onWrite: (frame) async {
        final inner = proto.parseFrame(frame, profile: proto.BandProfile.gen5)!.inner;
        written.add((seq: inner[1], opcode: inner[2]));
        final reply = replyTo?.call(inner[1], inner[2]);
        if (reply != null) engine.debugAbsorbDecoded(reply);
        return true;
      },
    );
  }

  bool logged(String needle) => logs.any((l) => l.contains(needle));
}

/// A COMMAND_RESPONSE carrying the doc-07 alarm/haptics status byte, decoded by
/// the REAL protocol parser so the test asserts on the wire layout rather than
/// on a hand-written field map: `[0x24][strap seq][opcode][echoed seq][result]`
/// then body `[revision][alarm status]`.
proto.Decoded _alarmReply(
  int opcode,
  int seq,
  int alarmStatus, {
  int outer = 1,
  int revision = 3,
}) {
  final inner = Uint8List.fromList(
      [0x24, 0x55, opcode, seq, outer, revision, alarmStatus]);
  final r =
      proto.parseCommandResponse(inner, profile: proto.BandProfile.gen5)!;
  return proto.Decoded('cmd_response', {'opcode': r.opcode, ...r.decoded});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(BleEngine.resetBandClaimForTest);
  tearDown(BleEngine.resetBandClaimForTest);

  group('AlarmPayloads byte layout', () {
    // A hand-computed vector:
    //   sec    = 0x01020304 = 16909060  → LE [04 03 02 01]
    //   subsec = (500 * 32768) ~/ 1000 = 16384 = 0x4000 → LE [00 40]
    final when = DateTime.fromMillisecondsSinceEpoch(16909060 * 1000 + 500,
        isUtc: true);

    test('subsecOf uses the 1/32768 s formula', () {
      expect(AlarmPayloads.subsecOf(when), 16384);
      // 0 ms → 0 subsec; 999 ms → the top of the range.
      expect(
          AlarmPayloads.subsecOf(
              DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true)),
          0);
      expect(
          AlarmPayloads.subsecOf(
              DateTime.fromMillisecondsSinceEpoch(1999, isUtc: true)),
          (999 * 32768) ~/ 1000);
    });

    test('rev1 (9B, the gen4 arm form) = 0x01 + u32 sec LE + u16 subsec + u16 mode', () {
      final p = AlarmPayloads.rev1(when);
      expect(p.length, 9);
      expect(p, <int>[
        0x01, // rev-1 form marker
        0x04, 0x03, 0x02, 0x01, // sec LE
        0x00, 0x40, // subsec LE (16384)
        0x00, 0x00, // haptic-mode (stock wake buzz)
      ]);
    });

    test('rev1 matches the official WHOOP app wire capture byte-for-byte', () {
      // btsnoop of the official app arming a real WHOOP 4.0 (noop PR #535):
      // epoch 1781912880 = 0x6A35D530 → [01, 30, D5, 35, 6A, 00, 00, 00, 00].
      // The same 9-byte shape fired OUR band on-device (fw 41.17.4,
      // 2026-08-19 18:55:00: events 60+57 stamped at the armed second). This
      // is the app-parity anchor: keep the payload byte-for-byte what the
      // official app sends.
      final p = AlarmPayloads.rev1(
          DateTime.fromMillisecondsSinceEpoch(1781912880 * 1000, isUtc: true));
      expect(p, <int>[0x01, 0x30, 0xD5, 0x35, 0x6A, 0x00, 0x00, 0x00, 0x00]);
    });

    test('rich (20B, gen4 reference only — execution is fw-dependent) layout', () {
      final p = AlarmPayloads.rich(when);
      expect(p.length, 20);
      expect(p, <int>[
        0x04, // rich-form marker
        0x00, // index
        0x04, 0x03, 0x02, 0x01, // sec LE
        0x00, 0x40, // subsec LE (16384)
        47, 152, 0, 0, 0, 0, 0, 0, // 8 waveform effects
        0, 0, // loop control u16 LE
        7, // overall loop
        30, // duration seconds
      ]);
    });

    test('rich honours a custom index + custom 12-byte haptics', () {
      final custom = List<int>.generate(12, (i) => i + 1);
      final p = AlarmPayloads.rich(when, index: 3, haptics: custom);
      expect(p[0], 0x04);
      expect(p[1], 3);
      expect(p.sublist(8), custom);
    });

    test('simple (7B) = rev1 minus the haptic-mode u16 (same frame once padded)', () {
      final p = AlarmPayloads.simple(when);
      expect(p.length, 7);
      expect(p, <int>[0x01, 0x04, 0x03, 0x02, 0x01, 0x00, 0x40]);
    });

    test('setPayloadForBand: gen4 rev1 (9B), gen5 index1 rich (21B)', () {
      final g4 = AlarmPayloads.setPayloadForBand(when, isGen5: false);
      // gen4 = the rev-1 form, byte-identical to AlarmPayloads.rev1 — the
      // official app's wire form (see AlarmPayloads for the firmware
      // evidence).
      expect(g4, AlarmPayloads.rev1(when));
      expect(g4.length, 9);
      expect(g4[0], 0x01);
      // gen5: the full composed 21-byte body, exact bytes in field order.
      expect(AlarmPayloads.setPayloadForBand(when, isGen5: true), <int>[
        0x04, // rich-form marker
        0x01, // slot 1 (index 0 is rejected on gen5)
        0x04, 0x03, 0x02, 0x01, // sec LE
        0x00, 0x40, // subsec LE (16384)
        47, 152, 0, 0, 0, 0, 0, 0, // 8 waveform effects
        0, 0, // loop control u16 LE
        7, // overall loop
        30, // duration seconds
        0, // crescendo flag, off by default
      ]);
      expect(
        AlarmPayloads.setPayloadForBand(when, isGen5: true, crescendo: 1).last,
        1,
      );
      // Gen5 ignores a caller-supplied index so slot 0 cannot be armed by accident.
      expect(
        AlarmPayloads.setPayloadForBand(when, isGen5: true, index: 0)[1],
        0x01,
      );
    });

    test('gen5 Maverick buzz is a short Find-band-style pulse', () {
      expect(AlarmPayloads.gen5MaverickBuzz(),
          <int>[0x01, 47, 152, 0, 0, 0, 0, 0, 0, 0, 0, 1]);
      expect(AlarmPayloads.gen5MaverickBuzz(overallLoop: 7).last, 7);
    });

    test('RUN_ALARM + DISABLE_ALARM bodies are both [0x01]', () {
      expect(AlarmPayloads.runNow, <int>[0x01]);
      expect(AlarmPayloads.disable, <int>[0x01]);
    });

    test('default haptics match the stock wake-buzz pattern', () {
      expect(AlarmPayloads.defaultHaptics,
          <int>[47, 152, 0, 0, 0, 0, 0, 0, 0, 0, 7, 30]);
    });
  });

  group('AlarmPayloads.toStrapFrame (RTC-frame arming)', () {
    // Wall-clock target with a non-zero sub-second so we can assert it survives.
    final wall = DateTime.fromMillisecondsSinceEpoch(1750000000 * 1000 + 250,
        isUtc: true);

    test('uncorrelated (drift 0) → wall target unchanged', () {
      expect(AlarmPayloads.toStrapFrame(wall, 0).millisecondsSinceEpoch,
          wall.millisecondsSinceEpoch);
    });

    test('strap RTC behind wall (drift +90) → armed epoch = wall − 90', () {
      final r = AlarmPayloads.toStrapFrame(wall, 90);
      expect(r.millisecondsSinceEpoch ~/ 1000, 1750000000 - 90);
      // whole-second shift keeps the sub-second remainder intact
      expect(AlarmPayloads.subsecOf(r), AlarmPayloads.subsecOf(wall));
    });

    test('strap RTC ahead of wall (drift −30) → armed epoch = wall + 30', () {
      expect(AlarmPayloads.toStrapFrame(wall, -30).millisecondsSinceEpoch ~/ 1000,
          1750000000 + 30);
    });

    test('rev1() encodes the strap-frame epoch, not the raw wall epoch', () {
      // On a strap whose RTC is 90s behind, arming the raw wall epoch would fire
      // 90s late (or never, for a large offset); the shipped gen4 payload must
      // carry the shifted (wall − drift) seconds. Mirrors engine.setAlarm.
      final p = AlarmPayloads.rev1(AlarmPayloads.toStrapFrame(wall, 90));
      final sec = p[1] | (p[2] << 8) | (p[3] << 16) | (p[4] << 24);
      expect(sec, 1750000000 - 90);
    });
  });

  group('ClockRef.driftSec + reconnect fallback (stale-correlation guard)', () {
    final wall = DateTime.fromMillisecondsSinceEpoch(1750000000 * 1000,
        isUtc: true);

    test('driftSec = wall − device (positive when the strap RTC is behind)', () {
      expect(const ClockRef(device: 1000, wall: 1090).driftSec, 90);
      expect(const ClockRef(device: 1100, wall: 1070).driftSec, -30);
      expect(const ClockRef(device: 1000, wall: 1000).driftSec, 0);
    });

    test('no correlation yet (just after reconnect) → drift 0 → raw wall epoch', () {
      // On reconnect _clockRef is nulled until THIS session's GET_CLOCK reply, so
      // the arm must fall back to the raw epoch rather than reuse the previous
      // session's offset. This mirrors engine.setAlarm's `_clockRef?.driftSec ?? 0`.
      const ClockRef? ref = null;
      final driftSec = ref?.driftSec ?? 0;
      expect(driftSec, 0);
      expect(
          AlarmPayloads.toStrapFrame(wall, driftSec).millisecondsSinceEpoch ~/ 1000,
          1750000000);
    });

    test('correlated session → arms in the strap frame using the offset', () {
      const ref = ClockRef(device: 1749999910, wall: 1750000000); // strap 90s behind
      final driftSec = ref.driftSec; // 90
      expect(driftSec, 90);
      expect(
          AlarmPayloads.toStrapFrame(wall, driftSec).millisecondsSinceEpoch ~/ 1000,
          1750000000 - 90);
    });
  });

  group('AlarmConfirmation state machine', () {
    test('event ids match the protocol EventId names', () {
      expect(AlarmConfirmation.kEvtSet, proto.EventId.strapDrivenAlarmSet);
      expect(AlarmConfirmation.kEvtStrapExecuted,
          proto.EventId.strapDrivenAlarmExecuted);
      expect(AlarmConfirmation.kEvtAppExecuted,
          proto.EventId.appDrivenAlarmExecuted);
      expect(AlarmConfirmation.kEvtDisabled,
          proto.EventId.strapDrivenAlarmDisabled);
      expect(AlarmConfirmation.kEvtHapticsFired, proto.EventId.hapticsFired);
    });

    test('a fresh alarm is neither pending nor confirmed', () {
      final a = AlarmConfirmation();
      expect(a.confirmed, isFalse);
      expect(a.isPending(0), isFalse);
      expect(a.isUnconfirmed(0), isFalse);
    });

    test('after SET → PENDING inside the grace window, then UNCONFIRMED', () {
      final a = AlarmConfirmation(graceMs: 6000);
      a.set(1750000000, 0);
      expect(a.confirmed, isFalse);
      expect(a.isPending(0), isTrue);
      expect(a.isPending(5999), isTrue);
      expect(a.isUnconfirmed(5999), isFalse);
      // grace elapsed with no confirm event → soft-warning state.
      expect(a.isPending(6000), isFalse);
      expect(a.isUnconfirmed(6000), isTrue);
    });

    test('event 56 cannot prove the current arm even after SET', () {
      final a = AlarmConfirmation(graceMs: 6000);
      a.set(1750000000, 0);
      final eff = a.onEvent(AlarmConfirmation.kEvtSet, 100);
      expect(eff, AlarmEffect.uncertain);
      expect(a.confirmed, isFalse);
      expect(a.lastEventId, 56);
      expect(a.isPending(10000), isFalse);
      expect(a.isUnconfirmed(10000), isTrue);
    });

    test('events 57/58 mark FIRED with a timestamp', () {
      for (final id in [
        AlarmConfirmation.kEvtStrapExecuted,
        AlarmConfirmation.kEvtAppExecuted,
      ]) {
        final a = AlarmConfirmation();
        a.set(1750000000, 0);
        final eff = a.onEvent(id, 4242);
        expect(eff, AlarmEffect.fired);
        expect(a.firedAt, 4242);
        expect(a.lastEventId, id);
      }
    });

    test('historical event 59 lowers confidence but cannot clear the alarm', () {
      final a = AlarmConfirmation();
      a.set(1750000000, 0);
      a.onEvent(AlarmConfirmation.kEvtSet, 10);
      final eff = a.onEvent(AlarmConfirmation.kEvtDisabled, 20);
      expect(eff, AlarmEffect.uncertain);
      expect(a.confirmed, isFalse);
      expect(a.targetEpoch, 1750000000);
      expect(a.lastEventId, 59);
      expect(a.isDisableOutstanding, isFalse,
          reason: 'unsolicited 59 does not invent a local off request');
    });

    test('requestDisable keeps the last armed instant', () {
      final a = AlarmConfirmation();
      a.set(1750000000, 0);
      a.onEvent(AlarmConfirmation.kEvtSet, 10);
      a.requestDisable(20);
      expect(a.targetEpoch, 1750000000);
      expect(a.confirmed, isFalse);
      expect(a.isDisableOutstanding, isTrue);
      expect(a.disableWritten, isFalse);
    });

    test('event 59 after written requestDisable is still uncorrelated', () {
      final a = AlarmConfirmation();
      a.set(1750000000, 0);
      a.requestDisable(10);
      a.markDisableWritten();
      final eff = a.onEvent(AlarmConfirmation.kEvtDisabled, 20);
      expect(eff, AlarmEffect.uncertain);
      expect(a.confirmed, isFalse);
      expect(a.targetEpoch, 1750000000);
      expect(a.isDisableOutstanding, isTrue);
      expect(a.lastEventId, 59);
    });

    test('local disable() does not invent event 59', () {
      final a = AlarmConfirmation();
      a.set(1750000000, 0);
      a.disable();
      expect(a.targetEpoch, isNull);
      expect(a.lastEventId, isNull);
      expect(a.isDisableOutstanding, isFalse);
    });

    test('a late 59 after a newer SET is ignored', () {
      final a = AlarmConfirmation();
      a.set(1750000000, 1);
      a.requestDisable(10);
      a.set(1750003600, 20); // SET superseded disable
      a.onEvent(AlarmConfirmation.kEvtSet, 21);
      expect(a.confirmed, isFalse);
      final eff = a.onEvent(
        AlarmConfirmation.kEvtDisabled,
        30,
        eventTsSec: 15,
      );
      expect(eff, AlarmEffect.uncertain);
      expect(a.targetEpoch, 1750003600);
      expect(a.confirmed, isFalse, reason: 'SET confirmation becomes uncertain');
    });

    test('an ambiguous late 59 after SET-superseded disable abstains', () {
      final a = AlarmConfirmation();
      a.set(1750000000, 1);
      a.requestDisable(10);
      a.set(1750003600, 20);
      expect(a.onEvent(AlarmConfirmation.kEvtDisabled, 30), AlarmEffect.uncertain);
      expect(a.targetEpoch, 1750003600);
      expect(a.confirmed, isFalse);
    });

    test('strap-clock 59 far after phone SET still abstains', () {
      // eventTsSec is strap RTC seconds; setAtMs is phone wall ms. A 2s
      // comparison would treat this live-looking stamp as current.
      final setAtMs = 1750003600 * 1000;
      final a = AlarmConfirmation();
      a.set(1750000000, 1);
      a.requestDisable(10);
      a.set(1750003600, setAtMs);
      final liveSkewTs = 1750003600 + 90; // strap 90s ahead of the SET epoch
      final eff = a.onEvent(
        AlarmConfirmation.kEvtDisabled,
        setAtMs + 5000,
        eventTsSec: liveSkewTs,
      );
      expect(eff, AlarmEffect.uncertain);
      expect(a.targetEpoch, 1750003600);
      expect(a.confirmed, isFalse);
    });

    test('restored superseded marker abstains a live-looking 59', () {
      final a = AlarmConfirmation();
      a.set(1785003600, 1785003600 * 1000);
      a.markDisableSuperseded();
      final eff = a.onEvent(
        AlarmConfirmation.kEvtDisabled,
        1785003700 * 1000,
        eventTsSec: 1785003690,
      );
      expect(eff, AlarmEffect.uncertain);
      expect(a.targetEpoch, 1785003600);
      expect(a.confirmed, isFalse);
    });

    test('59 before this DISABLE is written stays unknown', () {
      final a = AlarmConfirmation();
      a.set(1750000000, 1);
      a.requestDisable(10);
      a.set(1750003600, 20);
      a.requestDisable(40);
      final eff = a.onEvent(
        AlarmConfirmation.kEvtDisabled,
        50,
        eventTsSec: 1750003700,
      );
      expect(eff, AlarmEffect.uncertain);
      expect(a.isDisableOutstanding, isTrue);
      expect(a.targetEpoch, 1750003600);
    });

    test('59 after this DISABLE was written cannot prove off', () {
      final a = AlarmConfirmation();
      a.set(1750000000, 1);
      a.requestDisable(40);
      a.markDisableWritten();
      final eff = a.onEvent(AlarmConfirmation.kEvtDisabled, 50);
      expect(eff, AlarmEffect.uncertain);
      expect(a.isDisableOutstanding, isTrue);
      expect(a.targetEpoch, 1750000000);
    });

    test('an unrelated event returns null and changes nothing', () {
      final a = AlarmConfirmation();
      a.set(1750000000, 0);
      expect(a.onEvent(proto.EventId.wristOn, 5), isNull);
      expect(a.confirmed, isFalse);
      expect(a.targetEpoch, 1750000000);
    });
  });

  group('alarmLatchFailed (actual command failure gate)', () {
    for (final kind in AlarmCommandFailure.values) {
      test('$kind only while current and enabled', () {
        var current = true;
        final failure = AlarmFailure(kind, stillCurrent: () => current);
        expect(alarmLatchFailed(failure, enabled: true, currentGeneration: true), isTrue);
        expect(alarmLatchFailed(failure, enabled: false, currentGeneration: true), isFalse);
        expect(alarmLatchFailed(failure, enabled: true, currentGeneration: false), isFalse);
        current = false;
        expect(alarmLatchFailed(failure, enabled: true, currentGeneration: true), isFalse);
      });
    }
    test('unknown/no evidence never alerts', () {
      expect(alarmLatchFailed(null, enabled: true, currentGeneration: true), isFalse);
    });
  });


  // the SET_ALARM_TIME reply carries a haptics/alarm
  // status byte "in addition to the ordinary outer command result — check
  // both". Before this, the engine treated a successful WRITE as an armed
  // alarm, so a strap that answered `invalid alarm time` left the app showing
  // a wake alarm that did not exist on the band.
  group('engine wiring — an arm is judged on the strap\'s reply', () {
    final wake = DateTime.fromMillisecondsSinceEpoch(1750000000 * 1000);

    test('a rejected alarm time returns null — nothing to persist', () async {
      final link = _Link(
        replyTo: (seq, opcode) => opcode == proto.Cmd.setAlarmTime
            ? _alarmReply(opcode, seq, proto.AlarmStatus.invalidAlarmTime)
            : null,
      );

      expect(await link.engine.setAlarm(wake), isNull,
          reason: 'the strap refused it; there is no alarm on the band');
      expect(link.logged('arm REJECTED'), isTrue);
      expect(link.logged('invalid_alarm_time'), isTrue,
          reason: 'the status name is the whole diagnostic');
      expect(link.engine.pendingCommandCount, 0);
    });

    test('a SUCCESS outer result does not override a rejecting status byte',
        () async {
      // The reply above already carries outer result 1 — the point of the doc's
      // "check both" is that this combination exists on the wire.
      final link = _Link(
        replyTo: (seq, opcode) => opcode == proto.Cmd.setAlarmTime
            ? _alarmReply(opcode, seq, proto.AlarmStatus.invalidAlarmId,
                outer: 1)
            : null,
      );
      expect(await link.engine.setAlarm(wake), isNull);
      expect(link.logged('invalid_alarm_id'), isTrue);
    });

    test('an accepted arm returns the armed time and logs the status', () async {
      final link = _Link(
        replyTo: (seq, opcode) => opcode == proto.Cmd.setAlarmTime
            ? _alarmReply(opcode, seq, proto.AlarmStatus.validInputPattern)
            : null,
      );

      expect(await link.engine.setAlarm(wake), wake);
      expect(link.logged('arm accepted'), isTrue);
      expect(link.logged('valid_input_pattern'), isTrue);
    });

    test('a FAILURE outer result rejects the arm even with no status byte',
        () async {
      final link = _Link(
        replyTo: (seq, opcode) => opcode == proto.Cmd.setAlarmTime
            ? proto.Decoded('cmd_response', {
                'opcode': opcode,
                'req_seq': seq,
                'cmd_status': CommandAwaiter.statusFailure,
              })
            : null,
      );
      expect(await link.engine.setAlarm(wake), isNull);
      expect(link.logged('arm REJECTED'), isTrue);
    });

    test('an unanswered arm still arms, logged as unconfirmed', () {
      // Correlation is new and unproven on every strap: a band that does not
      // echo the originating sequence must not lose its wake alarm. The arm
      // costs at most the awaiter's single 5 s timeout, with no resend.
      fakeAsync((async) {
        final link = _Link(); // writes succeed, nothing ever answers
        DateTime? armed;
        var done = false;
        link.engine.setAlarm(wake).then((v) {
          armed = v;
          done = true;
        });

        async.elapse(const Duration(seconds: 4));
        expect(done, isFalse, reason: 'still waiting on the reply');
        async.elapse(const Duration(seconds: 2));

        expect(done, isTrue);
        expect(armed, wake, reason: 'an unanswered read-back is not a refusal');
        expect(link.logged('arm UNCONFIRMED'), isTrue);
        expect(link.engine.pendingCommandCount, 0);
      });
    });

    test('a failed write is still the only silent null', () async {
      final link = _Link();
      link.engine.debugWriteHook = (_) async => false;
      expect(await link.engine.setAlarm(wake), isNull);
      expect(link.logged('arm REJECTED'), isFalse,
          reason: 'nothing was refused — nothing was ever sent');
      expect(link.engine.pendingCommandCount, 0,
          reason: 'a write that never went out leaves no observer behind');
    });
  });

  group('engine wiring — DISABLE is judged on the write, not as band-off', () {
    proto.Decoded disableReply(int seq, int opcode, {int outer = 1}) =>
        proto.Decoded('cmd_response', {
          'opcode': opcode,
          'req_seq': seq,
          'cmd_status': outer,
        });

    test('a failed write is writeFailed, not off', () async {
      final link = _Link();
      link.engine.debugWriteHook = (_) async => false;
      expect(await link.engine.disableAlarm(), AlarmDisableOutcome.writeFailed);
      expect(link.engine.pendingCommandCount, 0);
    });

    test('a strap refusal is rejected, not off', () async {
      final link = _Link(
        replyTo: (seq, opcode) => opcode == proto.Cmd.disableAlarm
            ? disableReply(seq, opcode, outer: CommandAwaiter.statusFailure)
            : null,
      );
      expect(await link.engine.disableAlarm(), AlarmDisableOutcome.rejected);
      expect(link.logged('disable REJECTED'), isTrue);
    });

    test('an accepted write is written, still not event 59', () async {
      final link = _Link(
        replyTo: (seq, opcode) => opcode == proto.Cmd.disableAlarm
            ? disableReply(seq, opcode)
            : null,
      );
      expect(await link.engine.disableAlarm(), AlarmDisableOutcome.written);
      expect(link.logged('Band-off remains unconfirmed'), isTrue);
      expect(link.logged('event 59 is uncorrelated'), isTrue);
    });

    test('an unanswered write is noReply, not confirmed-off', () {
      fakeAsync((async) {
        final link = _Link();
        AlarmDisableOutcome? outcome;
        var done = false;
        link.engine.disableAlarm().then((v) {
          outcome = v;
          done = true;
        });
        async.elapse(const Duration(seconds: 4));
        expect(done, isFalse);
        async.elapse(const Duration(seconds: 2));
        expect(done, isTrue);
        expect(outcome, AlarmDisableOutcome.noReply);
        expect(link.logged('disable UNCONFIRMED'), isTrue);
      });
    });
  });

  group('shared alarm runner disable is not strap-off', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      AlarmOwner.resetForTest();
    });
    proto.Decoded disableReply(int seq, int opcode) => proto.Decoded(
          'cmd_response',
          {
            'opcode': opcode,
            'req_seq': seq,
            'cmd_status': CommandAwaiter.statusSuccess,
          },
        );

    test('all-off with an armed epoch sends DISABLE and returns written', () async {
      final link = _Link(
        replyTo: (seq, opcode) => opcode == proto.Cmd.disableAlarm
            ? disableReply(seq, opcode)
            : null,
      );
      await AlarmOwner.choose(AlarmDesired.off);
      expect(await AlarmOwner.reconcile(link.engine), AlarmDisableOutcome.written);
      expect((await AlarmOwner.load()).desired, AlarmDesired.off);
    });

    test('all-off retries DISABLE when outstanding even with no epoch', () async {
      final link = _Link(
        replyTo: (seq, opcode) => opcode == proto.Cmd.disableAlarm
            ? disableReply(seq, opcode)
            : null,
      );
      await AlarmOwner.choose(AlarmDesired.off);
      await AlarmOwner.reconcile(link.engine);
      expect(await AlarmOwner.reconcile(link.engine), AlarmDisableOutcome.written);
    });

    test('all-off with no epoch and no outstanding does not send DISABLE', () async {
      final link = _Link();
      await AlarmOwner.initialize(const []);
      expect(await AlarmOwner.reconcile(link.engine), isNull);
      expect(link.written, isEmpty);
    });

    test('a failed DISABLE does not report written', () async {
      final link = _Link();
      link.engine.debugWriteHook = (_) async => false;
      await AlarmOwner.choose(AlarmDesired.off);
      expect(await AlarmOwner.reconcile(link.engine), AlarmDisableOutcome.writeFailed);
      expect((await AlarmOwner.load()).desired, AlarmDesired.off);
    });
  });
}
