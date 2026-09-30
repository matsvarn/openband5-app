import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../domain.dart';
import '../training.dart' show OBSportIcon;
import 'chrome.dart' show OBLink, OBPanel;
import 'count_copy.dart';
import 'g3_format.dart' show g3Signed;
import 'g3_theme.dart';
import 'metrics.dart'
    show G3LabelRow, G3Scale, G3Tick, OBChip, OBChipKind, OBMissingValue;

const trainingSports = <String>[
  'running',
  'cycling',
  'walking',
  'hiking',
  'weight_training',
  'swimming',
  'yoga',
  'tennis',
  'intervals',
  'stretching',
  'soccer',
  'rowing',
  'climbing',
  'skiing',
  'martial_arts',
  'other',
];

String trainingSport(String sport) => switch (sport) {
  'running' => 'Lauf',
  'cycling' => 'Rad',
  'hiking' => 'Wandern',
  'walking' => 'Gehen',
  'tennis' => 'Tennis',
  'intervals' => 'Intervalle',
  'stretching' => 'Dehnen',
  'soccer' || 'football' => 'Fußball',
  'rowing' => 'Rudern',
  'climbing' => 'Klettern',
  'skiing' => 'Ski',
  'martial_arts' => 'Kampfsport',
  'swimming' => 'Schwimmen',
  'yoga' => 'Yoga',
  'strength' || 'weightlifting' || 'weight_training' => 'Kraft',
  _ => sport == 'other' ? 'Sonstiges' : 'Aktivität',
};

String trainingSportIconName(String sport) => switch (sport) {
  'running' => 'run',
  'walking' => 'walk',
  'cycling' => 'bike',
  'hiking' => 'trekking',
  'tennis' => 'ball-tennis',
  'swimming' => 'swimming',
  'strength' || 'weightlifting' || 'weight_training' => 'barbell',
  'yoga' => 'yoga',
  'intervals' => 'jump-rope',
  'stretching' => 'stretching',
  'soccer' || 'football' => 'ball-football',
  'rowing' => 'kayak',
  'climbing' => 'mountain',
  'skiing' => 'ski-jumping',
  'martial_arts' => 'karate',
  _ => '',
};

Widget trainingSportIcon(
  String sport, {
  double size = 24,
  required Color color,
}) {
  if (sport == 'yoga') {
    return Icon(LucideIcons.flower2, size: size, color: color);
  }
  final name = trainingSportIconName(sport);
  return name.isEmpty
      ? Icon(LucideIcons.activity, size: size, color: color)
      : OBSportIcon(name, size: size, color: color);
}

class OBSportTile extends StatelessWidget {
  final String sport;
  final bool selected;
  final VoidCallback onTap;
  const OBSportTile({
    super.key,
    required this.sport,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '${trainingSport(sport)} wählen',
      child: Material(
        color: selected ? g.ink : g.canvas,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            constraints: const BoxConstraints(minHeight: 76),
            padding: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? g.ink : g.line),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                trainingSportIcon(
                  sport,
                  size: 25,
                  color: selected ? g.canvas : g.ink,
                ),
                const SizedBox(height: 5),
                Text(
                  trainingSport(sport),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: g.t(
                    12,
                    15,
                    color: selected ? g.canvas : g.ink,
                    weight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String trainingNumber(double? value, {bool signed = false}) =>
    value == null || !value.isFinite
    ? '—'
    : signed
    ? g3Signed(value, digits: 1)
    : g3Number(value, digits: 1);

class OBTrainingLoad extends StatelessWidget {
  final G3WeeklyLoad? load;
  final VoidCallback? onMethod;
  const OBTrainingLoad({super.key, required this.load, this.onMethod});

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final acute = load?.atl, usual = load?.ctl;
    final ready =
        acute != null && acute.isFinite && usual != null && usual.isFinite;
    final have = load?.daysHave, need = load?.daysNeed;
    final building =
        !ready &&
        load?.refusalNote?.startsWith('need_baseline') == true &&
        have != null &&
        need != null &&
        need > 0;
    Widget column(String label, double? value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: g.caps(color: g.muted)),
          const SizedBox(height: 5),
          if (value == null)
            const OBMissingValue(size: 36, lineHeight: 40)
          else
            Text(
              trainingNumber(value).replaceAll(',0', ''),
              style: g.t(36, 40, weight: FontWeight.w700),
            ),
        ],
      ),
    );
    return OBPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('TRAININGSLAST', style: g.caps()),
          const SizedBox(height: 12),
          Row(
            children: [
              column('AKUT · 7 TAGE', ready ? acute : null),
              SizedBox(height: 55, child: VerticalDivider(color: g.line)),
              column('GEWOHNT · 6 WOCHEN', ready ? usual : null),
            ],
          ),
          if (ready) ...[
            const SizedBox(height: 12),
            Text(
              acute > usual
                  ? 'Letzte Woche mehr als gewohnt.'
                  : acute < usual
                  ? 'Letzte Woche weniger als gewohnt.'
                  : 'Letzte Woche wie gewohnt.',
              style: g.t(14, 18, weight: FontWeight.w700),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Text(
              building
                  ? 'Noch keine Trainingslast'
                  : 'Trainingslast noch nicht berechnet',
              style: g.t(15, 19, weight: FontWeight.w700),
            ),
            if (building) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  for (var i = 0; i < need; i++)
                    Expanded(
                      child: Container(
                        height: 22,
                        margin: EdgeInsets.only(right: i == need - 1 ? 0 : 4),
                        decoration: BoxDecoration(
                          color: i < have ? g.ink : g.track,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                '$have von $need ${g3CountNoun(need, 'Tag', 'Tagen')} · noch ${(need - have).clamp(0, need)} ${g3CountNoun((need - have).clamp(0, need), 'Tag', 'Tage')}',
                style: g.t(12, 16, color: g.ink2),
              ),
            ],
          ],
          if (onMethod != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OBLink('Methode', onTap: onMethod!),
            ),
          ],
        ],
      ),
    );
  }
}

class OBLoadLead extends StatelessWidget {
  final double? value;
  final String? countTime;
  final VoidCallback? onTap;
  const OBLoadLead({
    super.key,
    required this.value,
    this.countTime,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Semantics(
      button: onTap != null,
      label: onTap == null
          ? 'Belastung ${trainingNumber(value)}'
          : 'Belastung ${trainingNumber(value)}, Verlauf öffnen',
      child: GestureDetector(
        onTap: onTap,
        child: OBPanel(
          hero: true,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              G3LabelRow('BELASTUNG', onTap: onTap),
              const SizedBox(height: 3),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (value == null)
                    const OBMissingValue(size: 92, lineHeight: 84)
                  else
                    Text(
                      trainingNumber(value),
                      style: g.t(92, 84, weight: FontWeight.w700),
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (countTime != null) ...[
                            const OBChip(OBChipKind.tag, 'Tag läuft'),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              G3Scale(
                min: 0,
                max: 21,
                value: value,
                ticks: const [G3Tick(0, '0'), G3Tick(21, '21')],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OBSessionMiniBar extends StatelessWidget {
  final String sport;
  final String elapsed;
  final int? heartRate, zone;
  final bool paused;
  final VoidCallback onTap;
  const OBSessionMiniBar({
    super.key,
    required this.sport,
    required this.elapsed,
    this.heartRate,
    this.zone,
    this.paused = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Semantics(
        button: true,
        label:
            '$sport ${paused ? 'pausiert' : 'läuft'} seit $elapsed, Einheit öffnen',
        child: Material(
          color: g.note,
          borderRadius: BorderRadius.circular(26),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(26),
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: g.noteInset,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    alignment: Alignment.center,
                    child: trainingSportIcon(sport, size: 20, color: g.noteInk),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${trainingSport(sport)} ${paused ? 'pausiert' : 'läuft'} · $elapsed',
                          style: g.t(
                            14,
                            18,
                            color: g.noteInk,
                            weight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          paused
                              ? 'Puls zählt nicht mit'
                              : heartRate == null
                              ? 'Kein verlässlicher Puls'
                              : '$heartRate /min${zone == null ? '' : ' · ${zone == 0 ? 'unter Zone 1' : 'Zone $zone'}'}',
                          style: g.t(12, 15, color: g.noteMuted),
                        ),
                      ],
                    ),
                  ),
                  Icon(LucideIcons.chevronUp, size: 18, color: g.noteInk),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
