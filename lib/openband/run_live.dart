import 'package:flutter/material.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;

import 'session.dart';
import 'theme.dart';

/// Live state of a distance activity. Pauses are explicit user intervals;
/// absent heart rate is never a pause (B19). [pausedSec] and [elapsedSec]
/// are kept apart so the saved duration cannot silently swap one for the
/// other.
class LiveRun {
  final int elapsedSec, pausedSec, laps;
  final double? distanceM;
  final int? heartRate, zone;
  final double? strain;
  final ana.HeartRateZoneSet? zoneSet;
  final int? maxHrSeen;
  final int? averageHr;
  final DateTime? startedAt;
  final bool paused, gps;
  const LiveRun({
    required this.elapsedSec,
    this.pausedSec = 0,
    this.laps = 0,
    this.distanceM,
    this.heartRate,
    this.zone,
    this.strain,
    this.zoneSet,
    this.maxHrSeen,
    this.averageHr,
    this.startedAt,
    this.paused = false,
    this.gps = false,
  });
  int get activeSec => elapsedSec - pausedSec;
}

class OBLiveMetrics extends StatelessWidget {
  final LiveRun run;
  const OBLiveMetrics({super.key, required this.run});
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final r = run;
    Widget metric(String value, String label, {Color? color}) => Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: p.text(
              26,
              weight: FontWeight.w800,
              display: true,
              color: color,
            ),
          ),
          Text(
            label,
            style: p.text(12, weight: FontWeight.w600, color: p.muted),
          ),
        ],
      ),
    );
    return OBCard(
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 16),
      child: Column(
        spacing: 12,
        children: [
          Column(
            children: [
              Text(
                r.distanceM == null
                    ? '—'
                    : obNumber(r.distanceM! / 1000, digits: 2),
                style: p.text(64, weight: FontWeight.w800, display: true),
              ),
              Text(
                'km',
                style: p.text(14, weight: FontWeight.w600, color: p.muted),
              ),
              if (r.laps > 0)
                Container(
                  height: 24,
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.well,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Runde ${r.laps}',
                    style: p.text(13, weight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          Row(
            children: [
              metric(obClock(r.activeSec), 'Zeit'),
              metric(obPace(r.distanceM, r.activeSec), 'Tempo /km'),
              metric(
                r.heartRate == null
                    ? '—'
                    : '${r.heartRate}${r.zone == null ? '' : ' · Z${r.zone}'}',
                'Puls',
                color: r.heartRate == null ? p.gap : p.pulse,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
