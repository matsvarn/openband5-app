import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'alp_tokens.dart';
import 'session.dart';
import 'theme.dart';

/// Live state of a distance activity. Pauses are explicit user intervals;
/// absent heart rate is never a pause (B19). [pausedSec] and [elapsedSec]
/// are kept apart so the saved duration cannot silently swap one for the
/// other.
class LiveRun {
  final int elapsedSec, pausedSec;
  final double? distanceM;
  final int? heartRate, zone;
  final bool paused, gps;
  const LiveRun({
    required this.elapsedSec,
    this.pausedSec = 0,
    this.distanceM,
    this.heartRate,
    this.zone,
    this.paused = false,
    this.gps = false,
  });
  int get activeSec => elapsedSec - pausedSec;
}

class OpenBandRunLive extends StatelessWidget {
  final ValueListenable<LiveRun> run;
  final String label;
  final VoidCallback? onPause, onResume, onLap, onFinish, onCollapse;
  const OpenBandRunLive({
    super.key,
    required this.run,
    this.label = 'Laufen',
    this.onPause,
    this.onResume,
    this.onLap,
    this.onFinish,
    this.onCollapse,
  });
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return ValueListenableBuilder<LiveRun>(
      valueListenable: run,
      builder: (context, r, _) => Scaffold(
        backgroundColor: p.canvas,
        appBar: AppBar(
          backgroundColor: p.canvas,
          leading: IconButton(
            tooltip: 'Einklappen',
            onPressed: onCollapse ?? () => Navigator.of(context).maybePop(),
            icon: const Icon(LucideIcons.chevronDown, size: 22),
          ),
          centerTitle: true,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: r.paused ? p.gap : p.strain,
                  shape: BoxShape.circle,
                ),
              ),
              Text(label, style: p.text(18, weight: FontWeight.w700)),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Semantics(
                label: r.gps ? 'GPS aktiv' : 'GPS nicht verfügbar',
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    spacing: 6,
                    children: [
                      Icon(
                        LucideIcons.locate,
                        size: 14,
                        color: r.gps ? p.recovery : p.gap,
                      ),
                      Text('GPS', style: p.text(13, weight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                children: [
                  OBLiveMetrics(run: r),
                  const SizedBox(height: 10),
                  Container(
                    height: 200,
                    alignment: Alignment.bottomLeft,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: p.sleepTint,
                      borderRadius: BorderRadius.circular(AlpRadius.card),
                    ),
                    child: Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: p.card,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        r.gps
                            ? 'Karte · Apple Maps'
                            : 'Karte ohne GPS nicht verfügbar',
                        style: p.text(
                          12,
                          weight: FontWeight.w600,
                          color: p.muted,
                        ),
                      ),
                    ),
                  ),
                  if (r.pausedSec > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 10, left: 4),
                      child: Text(
                        'davon ${obClock(r.pausedSec)} pausiert',
                        style: p.text(13, color: p.muted),
                      ),
                    ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  spacing: 10,
                  children: [
                    Expanded(
                      child: r.paused
                          ? OBAction(
                              'Beenden',
                              secondary: true,
                              onPressed: onFinish,
                            )
                          : OBAction(
                              'Runde',
                              secondary: true,
                              onPressed: onLap,
                            ),
                    ),
                    Expanded(
                      flex: 2,
                      child: OBAction(
                        r.paused ? 'Weiter' : 'Pause',
                        onPressed: r.paused ? onResume : onPause,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
