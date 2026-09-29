import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/day_label.dart';
import '../domain.dart';
import '../scale.dart';
import '../theme.dart' show OBLed, obTime;
import 'g3_theme.dart';

class OBSettingsGroup extends StatelessWidget {
  final List<Widget> children;
  const OBSettingsGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Container(
      decoration: g.raised(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, color: g.hairline),
            children[i],
          ],
        ],
      ),
    );
  }
}

class OBSettingsRow extends StatelessWidget {
  final String label;
  final String? detail;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;
  const OBSettingsRow({
    super.key,
    required this.label,
    this.detail,
    this.value,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: g.t(15, 20, weight: FontWeight.w600)),
                if (detail != null)
                  Text(detail!, style: g.t(12, 17, color: g.muted)),
              ],
            ),
          ),
          if (value != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                value!,
                textAlign: TextAlign.end,
                style: g.t(14, 19, color: g.muted),
              ),
            ),
          ],
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          if (onTap != null && trailing == null) ...[
            const SizedBox(width: 8),
            Icon(LucideIcons.chevronRight, size: 16, color: g.muted),
          ],
        ],
      ),
    );
    return Semantics(
      button: onTap != null,
      label: [label, detail, value].whereType<String>().join(', '),
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

class OBStepProgress extends StatelessWidget {
  final int step;
  const OBStepProgress({super.key, required this.step});

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('SCHRITT $step VON 3', style: g.caps(color: g.muted)),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 1; i <= 3; i++) ...[
              if (i > 1) const SizedBox(width: 6),
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= step ? g.ink : g.track,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class OBFrontierCard extends StatelessWidget {
  final DateTime? storedAt;
  final DateTime now;
  final String? caption;
  const OBFrontierCard({
    super.key,
    required this.storedAt,
    required this.now,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final stored = storedAt;
    final sameDay =
        stored != null &&
        dayLabelOf(stored) == todayLabel(now) &&
        !stored.isAfter(now);
    final midnight = DateTime(now.year, now.month, now.day);
    final elapsed = now.difference(midnight).inMinutes;
    final storedMinute = sameDay ? stored.difference(midnight).inMinutes : 0;
    final age = sameDay ? now.difference(stored).inMinutes : 0;
    final ageText = age >= 60
        ? '${age ~/ 60} h ${(age % 60).toString().padLeft(2, '0')}'
        : '$age Min.';
    return Container(
      decoration: g.raised(),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('AUF DEM IPHONE', style: g.caps()),
          const SizedBox(height: 8),
          Text(
            stored == null ? '—' : 'bis ${obTime(stored)}',
            style: g.t(40, 44, weight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (sameDay && elapsed > 0) ...[
            OBScale(
              min: 0,
              max: elapsed.toDouble(),
              value: storedMinute.toDouble(),
              fill: g.ink,
              mark: g.canvas,
              markEdge: g.ink,
              ticks: 3,
              labels: (
                '00:00',
                'bis ${obTime(stored)}',
                'jetzt ${obTime(now)}',
              ),
              semanticsLabel: 'Gespeicherte Banddaten bis ${obTime(stored)}',
            ),
            const SizedBox(height: 8),
          ],
          Text(
            caption ??
                (stored == null
                    ? 'Noch keine bestätigten Banddaten gespeichert.'
                    : sameDay
                    ? 'letzter Wert vor $ageText'
                    : 'Zuletzt bestätigter Datenstand. Noch ausstehende Banddaten sind unbekannt.'),
            style: g.t(13, 19, color: g.muted),
          ),
        ],
      ),
    );
  }
}

class OBBandHero extends StatelessWidget {
  final BandSnapshot band;
  final DateTime now;
  final VoidCallback? onStatus;
  const OBBandHero({
    super.key,
    required this.band,
    required this.now,
    this.onStatus,
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final stored = band.latestStoredAt;
    final connected = band.connection == BandConnection.connected;
    final freshness = stored == null
        ? 'Noch keine Banddaten'
        : '${dayLabelOf(stored) == todayLabel(now) ? 'heute' : 'vom ${stored.day}.${stored.month}.'} · ${obTime(stored)}';
    return Container(
      decoration: g.raised(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('DATEN BIS', style: g.caps())),
              OBLed(on: connected, size: 8),
              const SizedBox(width: 7),
              Text(
                connected ? 'Verbunden' : 'Nicht verbunden',
                style: g.t(14, 18, weight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(
            button: onStatus != null,
            label: 'Daten bis ${obTime(stored)}. Datenstand öffnen',
            child: InkWell(
              onTap: onStatus,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  obTime(stored),
                  style: g.t(84, 90, weight: FontWeight.w700),
                ),
              ),
            ),
          ),
          Text(freshness, style: g.t(14, 20, color: g.muted)),
          const SizedBox(height: 20),
          Text('LETZTE 24 STUNDEN', style: g.caps(color: g.muted)),
          const SizedBox(height: 8),
          Text(
            'Abdeckung — · keine 24-Stunden-Aufzeichnung verfügbar',
            style: g.t(13, 19, color: g.muted),
          ),
          const SizedBox(height: 20),
          Divider(height: 1, color: g.hairline),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _HeroFact(
                  'AKKU',
                  band.batteryPercent == null
                      ? '—'
                      : '${band.batteryPercent} %',
                ),
              ),
              Expanded(
                child: _HeroFact(
                  'AUSSTEHEND',
                  '—',
                  detail: 'Band-Rückstand unbekannt',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroFact extends StatelessWidget {
  final String label, value;
  final String? detail;
  const _HeroFact(this.label, this.value, {this.detail});
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: g.caps()),
        Text(value, style: g.t(30, 36, weight: FontWeight.w700)),
        if (detail != null) Text(detail!, style: g.t(12, 17, color: g.muted)),
      ],
    );
  }
}
