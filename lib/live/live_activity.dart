// Workout Live Activity channel. Values absent from the live stream stay null.
import 'package:flutter/services.dart';

enum LiveSignal { live, weak, none }

class LiveActivity {
  static const MethodChannel _ch = MethodChannel('openstrap/live_activity');
  static const Duration hrMaxAge = Duration(seconds: 5);
  static bool _active = false;

  static bool get isActive => _active;

  static String _sportName(String sport) => switch (sport) {
    'running' || 'treadmill' || 'sprinting' => 'Lauf',
    'walking' || 'dog_walking' => 'Gehen',
    'cycling' || 'indoor_bike' || 'mountain_biking' => 'Radfahrt',
    'weight_training' || 'powerlifting' || 'functional' => 'Krafttraining',
    'other' => 'Aktivität',
    _ => sport.replaceAll('_', ' '),
  };

  static Map<String, Object?> startPayload({
    required DateTime startedAt,
    required String sport,
  }) => {
    'name': _sportName(sport),
    'startedAtMs': startedAt.millisecondsSinceEpoch,
    'hr': null,
    'hrSampleAtMs': null,
    'signal': LiveSignal.none.name,
    'zone': null,
    'zoneLowPct': null,
    'zoneHighPct': null,
    'zoneBasis': null,
    'zoneBasisBpm': null,
    'elapsedSeconds': 0,
    'paused': false,
    'strain': null,
  };

  static Map<String, Object?> updatePayload({
    required int? hr,
    required DateTime? hrSampleAt,
    required LiveSignal signal,
    required int? zone,
    required double? zoneLowPct,
    required double? zoneHighPct,
    required String? zoneBasis,
    required int? zoneBasisBpm,
    required Duration elapsed,
    bool paused = false,
    required double? strain,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final fresh =
        !paused &&
        signal == LiveSignal.live &&
        hr != null &&
        hr > 0 &&
        hrSampleAt != null &&
        !hrSampleAt.isAfter(at) &&
        at.difference(hrSampleAt) <= hrMaxAge;
    final hasBasis = zoneBasis != null && zoneBasisBpm != null;
    final validZone =
        fresh &&
        zone != null &&
        zone >= 1 &&
        zone <= 5 &&
        zoneLowPct != null &&
        zoneHighPct != null &&
        hasBasis;
    return {
      'hr': fresh ? hr : null,
      'hrSampleAtMs': fresh ? hrSampleAt.millisecondsSinceEpoch : null,
      'signal': paused
          ? LiveSignal.none.name
          : fresh
          ? LiveSignal.live.name
          : (signal == LiveSignal.none
                ? LiveSignal.none.name
                : LiveSignal.weak.name),
      'zone': validZone ? zone : null,
      'zoneLowPct': validZone ? zoneLowPct : null,
      'zoneHighPct': validZone ? zoneHighPct : null,
      'zoneBasis': hasBasis ? zoneBasis : null,
      'zoneBasisBpm': hasBasis ? zoneBasisBpm : null,
      'elapsedSeconds': elapsed.inSeconds < 0 ? 0 : elapsed.inSeconds,
      'paused': paused,
      'strain': strain,
    };
  }

  static Future<void> start({
    required DateTime startedAt,
    required String sport,
  }) async {
    try {
      await _ch.invokeMethod(
        'start',
        startPayload(startedAt: startedAt, sport: sport),
      );
      _active = true;
    } catch (_) {
      /* Unsupported platform. */
    }
  }

  static Future<void> update({
    required int? hr,
    required DateTime? hrSampleAt,
    required LiveSignal signal,
    required int? zone,
    required double? zoneLowPct,
    required double? zoneHighPct,
    required String? zoneBasis,
    required int? zoneBasisBpm,
    required Duration elapsed,
    bool paused = false,
    required double? strain,
  }) async {
    try {
      await _ch.invokeMethod(
        'update',
        updatePayload(
          hr: hr,
          hrSampleAt: hrSampleAt,
          signal: signal,
          zone: zone,
          zoneLowPct: zoneLowPct,
          zoneHighPct: zoneHighPct,
          zoneBasis: zoneBasis,
          zoneBasisBpm: zoneBasisBpm,
          elapsed: elapsed,
          paused: paused,
          strain: strain,
        ),
      );
    } catch (_) {}
  }

  static Future<void> end() async {
    try {
      await _ch.invokeMethod('end');
    } catch (_) {}
    _active = false;
  }
}
