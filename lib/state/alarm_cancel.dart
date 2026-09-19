// Single-isolate alarm ownership, shared by foreground and headless.
// The JSON record is authoritative; legacy epoch/schedule rows are migration
// inputs only. Observation never changes desired intent (especially off).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ble/ble_engine.dart';
import '../ble/ble_state.dart';
import '../sync/headless_gate.dart';
import '../data/day_label.dart';
import '../notify/notification_center.dart';
import '../notify/notification_event.dart';
import '../notify/notification_prefs.dart';
import '../notify/notification_service.dart';
import '../notify/tap_router.dart';
import 'alarm_schedule.dart';

enum AlarmDesired { off, manual, weekly }

class AlarmIntent {
  final int generation;
  final AlarmDesired desired;
  final int? manualEpoch;
  final int? manualAtMs;
  final List<AlarmScheduleEntry> schedule;
  final int? armedEpoch;
  final bool confirmed;
  final bool disableWritten;
  final bool applied;
  const AlarmIntent({
    required this.generation,
    required this.desired,
    this.manualEpoch,
    this.manualAtMs,
    this.schedule = const [],
    this.armedEpoch,
    this.confirmed = false,
    this.disableWritten = false,
    this.applied = false,
  });

  DateTime? next(DateTime now) => switch (desired) {
    AlarmDesired.off => null,
    AlarmDesired.manual =>
      manualEpoch != null && manualEpoch! > now.millisecondsSinceEpoch ~/ 1000
          ? DateTime.fromMillisecondsSinceEpoch(
              manualAtMs ?? manualEpoch! * 1000,
            )
          : null,
    AlarmDesired.weekly => nextAlarmOccurrence(schedule, now),
  };

  /// Command completion supplies only what it learned. In particular, an ACK
  /// is neither SET confirmation nor evidence revoking an intervening event.
  /// Current protocol events cannot supply true: both 56 and 59 are history.
  AlarmIntent observed({
    int? epoch,
    bool? confirmed,
    bool? disableWritten,
    bool? applied,
  }) => AlarmIntent(
    generation: generation,
    desired: desired,
    manualEpoch: manualEpoch,
    manualAtMs: manualAtMs,
    schedule: schedule,
    armedEpoch: epoch,
    confirmed: confirmed ?? this.confirmed,
    disableWritten: disableWritten ?? this.disableWritten,
    applied: applied ?? this.applied,
  );

  String encode() => jsonEncode({
    'generation': generation,
    'desired': desired.name,
    'manual': manualEpoch,
    'manualMs': manualAtMs,
    'armed': armedEpoch,
    'confirmed': confirmed,
    'written': disableWritten,
    'applied': applied,
    'schedule': [
      for (final e in schedule)
        {
          'weekday': e.weekday,
          'hour': e.hour,
          'minute': e.minute,
          'enabled': e.enabled ? 1 : 0,
        },
    ],
  });
  factory AlarmIntent.decode(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return AlarmIntent(
      generation: j['generation'] as int,
      desired: AlarmDesired.values.byName(j['desired'] as String),
      manualEpoch: j['manual'] as int?,
      manualAtMs: j['manualMs'] as int?,
      armedEpoch: j['armed'] as int?,
      // Older builds inferred confirmation from uncorrelated event 56.
      // That persisted flag is not trustworthy evidence of this arm.
      confirmed: false,
      disableWritten: j['written'] == true,
      applied: j['applied'] == true,
      schedule: [
        for (final e in j['schedule'] as List)
          AlarmScheduleEntry.fromRow(Map<String, Object?>.from(e as Map)),
      ],
    );
  }
}

/// One persistence reducer and one whole-operation radio queue. Explicit
/// choices reserve their order synchronously, before any await. Automatic
/// work and observations inherit a generation, never create a new one.
/// An already-issued write cannot be recalled; the newer queued intent runs
/// after it. Persistence is serialized independently so off is durable even
/// while an older SET is held in clock preparation / command response.
class AlarmOwner {
  static const intentKey = 'alarm_desired_v1';
  static Future<void> _storage = Future.value();
  static Future<void> _radio = Future.value();
  static int _revision = 0;
  static ({BleEngine engine, int generation, AlarmReadback value})?
  _verification;

  static AlarmReadback readbackFor(BleEngine engine, int? generation) {
    final v = _verification;
    return v != null &&
            identical(v.engine, engine) &&
            v.generation == generation &&
            v.value.isCurrent
        ? v.value
        : const AlarmReadback.unknown();
  }

  @visibleForTesting
  static Future<bool> Function(SharedPreferences, String, String)? debugWrite;

  static Future<T> _store<T>(Future<T> Function() body) {
    final result = _storage.then((_) => body());
    _storage = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  static bool get _active => HeadlessSyncGate.continuationAllowed;

  static Future<void> _save(SharedPreferences p, AlarmIntent value) async {
    if (!_active) throw StateError('Alarm lease revoked');
    final ok =
        await (debugWrite?.call(p, intentKey, value.encode()) ??
            p.setString(intentKey, value.encode()));
    if (!ok) throw StateError('Alarm intent not durable');
  }

  static AlarmIntent _read(
    SharedPreferences p,
    List<AlarmScheduleEntry> legacySchedule,
  ) {
    final raw = p.getString(intentKey);
    // Corrupt records fail closed; never fall back to enabled legacy rows.
    if (raw != null) return AlarmIntent.decode(raw);
    final old = AlarmCancelPrefs.read(p);
    final epoch = p.getInt('alarm_epoch');
    return AlarmIntent(
      generation:
          old != null || epoch != null || legacySchedule.any((e) => e.enabled)
          ? 1
          : 0,
      desired: old != null && !old.superseded
          ? AlarmDesired.off
          : legacySchedule.any((e) => e.enabled)
          ? AlarmDesired.weekly
          : epoch != null
          ? AlarmDesired.manual
          : AlarmDesired.off,
      manualEpoch: epoch,
      schedule: old != null && !old.superseded ? const [] : legacySchedule,
      armedEpoch: epoch,
      confirmed: false,
      disableWritten: old?.written ?? false,
    );
  }

  static Future<AlarmIntent> load({
    List<AlarmScheduleEntry> legacySchedule = const [],
  }) => _store(() async {
    final p = await SharedPreferences.getInstance();
    return _read(p, legacySchedule);
  });

  static Future<AlarmIntent> choose(
    AlarmDesired desired, {
    DateTime? when,
    List<AlarmScheduleEntry> schedule = const [],
  }) {
    if (!_active) return Future.error(StateError('Alarm lease revoked'));
    ++_revision;
    _verification = null;
    final snapshot = List<AlarmScheduleEntry>.unmodifiable(schedule);
    return _store(() async {
      final p = await SharedPreferences.getInstance();
      final old = _read(p, snapshot);
      final value = AlarmIntent(
        generation: old.generation + 1,
        desired: desired,
        manualEpoch: when == null ? null : when.millisecondsSinceEpoch ~/ 1000,
        manualAtMs: when?.millisecondsSinceEpoch,
        schedule: desired == AlarmDesired.off ? const [] : snapshot,
        armedEpoch: old.armedEpoch,
      );
      await _save(p, value);
      return value;
    });
  }

  /// Persist a legacy import before any radio operation. No subsequent caller
  /// can derive intent from leftover DB rows once this record exists.
  static Future<AlarmIntent> initialize(List<AlarmScheduleEntry> schedule) =>
      _store(() async {
        final p = await SharedPreferences.getInstance();
        final value = _read(p, schedule);
        if (p.getString(intentKey) == null) await _save(p, value);
        return value;
      });

  static Future<bool> observe(
    AlarmIntent intent, {
    int? epoch,
    bool? confirmed,
    bool? disableWritten,
    bool? applied,
  }) {
    return _reduceObservation(
      intent,
      (current) => current.observed(
        epoch: epoch,
        confirmed: confirmed,
        disableWritten: disableWritten,
        applied: applied,
      ),
    );
  }

  /// Events merge against the current observation, never a UI snapshot from
  /// before a delayed SET/DISABLE completed. They cannot erase write evidence
  /// or restore an older epoch within the same desired generation.
  static Future<bool> observeEvent(AlarmIntent intent, {bool fired = false}) =>
      _reduceObservation(intent, (current) {
        final spent =
            fired &&
            current.armedEpoch != null &&
            current.armedEpoch! <=
                DateTime.now().millisecondsSinceEpoch ~/ 1000;
        return current.observed(
          epoch: spent ? null : current.armedEpoch,
          confirmed: false,
          disableWritten: current.disableWritten,
        );
      });

  static Future<bool> _reduceObservation(
    AlarmIntent intent,
    AlarmIntent Function(AlarmIntent) reduce,
  ) {
    final revision = _revision;
    return _store(() async {
      if (!_active || revision != _revision) return false;
      final p = await SharedPreferences.getInstance();
      final current = _read(p, const []);
      if (!_active || current.generation != intent.generation) return false;
      await _save(p, reduce(current));
      return _active;
    });
  }

  /// Report an actual attempted command failure, not missing readback. The
  /// existing preference name is retained for migration; its meaning is now
  /// "alarm command error". NotificationCenter owns category/quiet-hour policy
  /// and persistent cross-isolate dedupe. No separate OS emitter or timer.
  static Future<void> _notifyFailure(
    AlarmIntent intent,
    AlarmOperationResult operation,
    int revision,
    DateTime? target,
  ) async {
    if (operation.failure == null) return;
    if (operation.readback.isCurrent &&
        operation.readback.state == AlarmReadbackState.allSlotsInactive) {
      return;
    }
    try {
      final prefs = await NotificationPrefs.load();
      if (!alarmLatchFailed(
        operation.failure,
        enabled: prefs.alarmLatchFailedEnabled,
        currentGeneration: _active && revision == _revision,
      )) {
        return;
      }
      final setting = target != null;
      final action = setting ? 'Die Alarmänderung' : 'Das Ausschalten';
      final reason = operation.failure!.kind == AlarmCommandFailure.rejected
          ? 'wurde vom Band abgelehnt.'
          : 'ist beim Schreiben fehlgeschlagen.';
      final remaining = setting ? 'Ein vorheriger Alarm' : 'Ein Alarm';
      await NotificationCenter.instance.emit(
        NotificationEvent(
          dedupeKey:
              'alarm-command-failure:${intent.generation}:'
              '${target?.millisecondsSinceEpoch ?? "off"}',
          category: NotifCategory.device,
          priority: NotifPriority.critical,
          title: 'Alarmfehler',
          body:
              '$action $reason $remaining kann weiterhin gespeichert sein. Bitte prüfen.',
          date: todayLabel(),
          route: kRouteAlarm,
          osId: NotificationService.idAlarmLatchFailed,
        ),
        allowPermissionPrompt: HeadlessSyncGate.currentLease == null,
        stillValid: () =>
            _active &&
            revision == _revision &&
            (operation.failure?.isCurrent ?? false),
      );
    } catch (_) {
      /* Notification delivery must not change alarm intent. */
    }
  }

  static Future<AlarmDisableOutcome?> reconcile(
    BleEngine engine, {
    bool force = false,
    int? generation,
  }) {
    final lease = HeadlessSyncGate.currentLease;
    final result = _radio.then((_) async {
      if (!_active) return null;
      final revision = _revision;
      final intent = await load();
      if (!_active ||
          revision != _revision ||
          (generation != null && generation != intent.generation)) {
        return null;
      }
      final next = intent.next(DateTime.now());
      if (next == null) {
        if (intent.generation == 0 && intent.armedEpoch == null) return null;
        final operation = await engine.applyAlarmIntent();
        final outcome = operation.disableOutcome;
        if (!_active || revision != _revision) return outcome;
        await _notifyFailure(intent, operation, revision, null);
        if (!_active || revision != _revision) return outcome;
        await observe(
          intent,
          epoch: intent.armedEpoch,
          confirmed: false,
          disableWritten:
              outcome == AlarmDisableOutcome.written ||
              outcome == AlarmDisableOutcome.noReply,
        );
        if (_active && revision == _revision) {
          _verification = (
            engine: engine,
            generation: intent.generation,
            value: operation.readback,
          );
        }
        return outcome;
      }
      final epoch = next.millisecondsSinceEpoch ~/ 1000;
      final readOnly = intent.applied && intent.armedEpoch == epoch;
      if (!force &&
          readOnly &&
          readbackFor(engine, intent.generation).state ==
              AlarmReadbackState.storedSeconds) {
        return null;
      }
      // A weekly rollover / retry can SET again within the same generation.
      // Retire previous confidence BEFORE radio awaits. Historical events
      // received during the attempt cannot confirm it; only current typed
      // GET evidence can establish stored configuration after completion.
      final prepared = await _reduceObservation(
        intent,
        (current) =>
            current.observed(epoch: current.armedEpoch, confirmed: false),
      );
      if (!prepared || !_active || revision != _revision) return null;
      final operation = await engine.applyAlarmIntent(
        when: next,
        readOnly: readOnly,
      );
      final armed = operation.armed;
      if (!_active || revision != _revision) return null;
      if (armed == null) {
        await _notifyFailure(intent, operation, revision, next);
        if (!_active || revision != _revision) return null;
        // Retain the previous epoch: refusing a replacement is not proof off.
        throw StateError('Alarm not set');
      }
      await observe(
        intent,
        epoch: armed.millisecondsSinceEpoch ~/ 1000,
        applied: true,
      );
      if (_active && revision == _revision) {
        _verification = (
          engine: engine,
          generation: intent.generation,
          value: operation.readback,
        );
      }
      return null;
    });
    // Timeout releases the radio runner, not an orphan's authority. Every
    // engine write checks the zone lease, including queued / post-clock writes.
    final bounded = lease == null
        ? result
        : Future.any<AlarmDisableOutcome?>([
            result,
            lease.revoked.then((_) => null),
          ]);
    _radio = bounded.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return bounded;
  }

  @visibleForTesting
  static void resetForTest() {
    _storage = Future.value();
    _radio = Future.value();
    _revision = 0;
    _verification = null;
    debugWrite = null;
  }
}

// Read-only migration decoder. No production writer may revive this token.
class AlarmCancelIntent {
  final bool written;
  final bool cancelAll;
  final bool superseded;
  const AlarmCancelIntent({
    required this.written,
    required this.cancelAll,
    this.superseded = false,
  });
}

class AlarmCancelPrefs {
  static const intentKey = 'alarm_disable_intent';
  static const supersededToken = 'superseded';
  static AlarmCancelIntent? read(SharedPreferences p) =>
      decode(p.getString(intentKey));
  static AlarmCancelIntent? decode(String? raw) => switch (raw) {
    'pending' ||
    'written' ||
    'cancel_all' ||
    'cancel_all_written' => AlarmCancelIntent(
      written: raw!.endsWith('written'),
      cancelAll: raw.startsWith('cancel_all'),
    ),
    supersededToken => const AlarmCancelIntent(
      written: false,
      cancelAll: false,
      superseded: true,
    ),
    _ => null,
  };
}
