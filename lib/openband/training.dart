import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'alp_tokens.dart';
import 'controller.dart';
import 'domain.dart';
import 'theme.dart';

class OpenBandTraining extends StatelessWidget {
  final OpenBandController controller;
  final ValueChanged<String>? onStart;
  final ValueChanged<TrainingSession>? onOpen;
  const OpenBandTraining({
    super.key,
    required this.controller,
    this.onStart,
    this.onOpen,
  });
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final p = OB.of(context);
      return ColoredBox(
        color: p.canvas,
        child: ListView(
          key: const PageStorageKey('openband.training'),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                'Training',
                style: p.text(30, weight: FontWeight.w800, display: true),
              ),
            ),
            const SizedBox(height: 12),
            OBQuickStart(onStart: onStart),
            const SizedBox(height: 10),
            FutureBuilder<List<TrainingSession>>(
              key: ValueKey('sessions-${controller.selectedDay}'),
              future: controller.repository.readSessions(
                controller.selectedDay,
                30,
              ),
              builder: (context, snapshot) {
                final sessions = snapshot.data;
                if (snapshot.hasError) {
                  return OBCard(
                    child: Text(
                      'Einheiten konnten nicht geladen werden.',
                      style: p.text(14, color: p.danger),
                    ),
                  );
                }
                if (sessions == null) return const SizedBox(height: 200);
                final week = openBandDaysEnding(controller.selectedDay, 7);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 10,
                  children: [
                    OBWeekBars(
                      days: week,
                      sessions: sessions.where((s) => !s.live).toList(),
                    ),
                    if (sessions.isEmpty)
                      OBCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 4,
                          children: [
                            Text(
                              'Noch keine Einheiten',
                              style: p.text(15, weight: FontWeight.w600),
                            ),
                            Text(
                              'In den letzten 30 Tagen wurde nichts erfasst. Erkannte Einheiten des Bands erscheinen hier nach der Übertragung.',
                              style: p.text(14, color: p.muted),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                        child: Text(
                          'Zuletzt',
                          style: p.text(
                            20,
                            weight: FontWeight.w700,
                            display: true,
                          ),
                        ),
                      ),
                      OBCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        child: Column(
                          children: [
                            for (final (i, s) in sessions.indexed)
                              _SessionRow(
                                session: s,
                                divider: i > 0,
                                onTap: onOpen == null ? null : () => onOpen!(s),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      );
    },
  );
}

({String label, IconData icon}) obSport(String type) => switch (type) {
  'running' ||
  'treadmill' ||
  'sprinting' => (label: 'Laufen', icon: LucideIcons.footprints),
  'walking' || 'dog_walking' => (label: 'Gehen', icon: LucideIcons.footprints),
  'hiking' => (label: 'Wandern', icon: LucideIcons.mountainSnow),
  'cycling' ||
  'indoor_bike' ||
  'mountain_biking' => (label: 'Rad', icon: LucideIcons.bike),
  'swimming' => (label: 'Schwimmen', icon: LucideIcons.waves),
  'rowing' || 'kayaking' => (label: 'Rudern', icon: LucideIcons.sailboat),
  'weight_training' ||
  'powerlifting' ||
  'kettlebell' ||
  'functional' ||
  'crossfit' => (label: 'Kraft', icon: LucideIcons.dumbbell),
  'hiit' ||
  'track_intervals' ||
  'jump_rope' => (label: 'Intervalle', icon: LucideIcons.timer),
  'yoga' ||
  'pilates' ||
  'tai_chi' => (label: 'Yoga', icon: LucideIcons.flower2),
  'breathwork' || 'meditation' => (label: 'Atmen', icon: LucideIcons.wind),
  _ => (label: 'Aktivität', icon: LucideIcons.activity),
};

class OBQuickStart extends StatelessWidget {
  final ValueChanged<String>? onStart;
  const OBQuickStart({super.key, this.onStart});
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    Widget tile(
      String label,
      IconData icon,
      Color fg,
      Color bg,
      String? type,
    ) => Expanded(
      child: Semantics(
        button: true,
        label: type == null ? 'Weitere Aktivitäten' : '$label starten',
        child: InkWell(
          onTap: onStart == null ? null : () => onStart!(type ?? ''),
          borderRadius: BorderRadius.circular(AlpRadius.row),
          child: ExcludeSemantics(
            child: Container(
              height: 96,
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(AlpRadius.row),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 8,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, size: 20, color: fg),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: p.text(13, weight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Row(
      spacing: 8,
      children: [
        tile(
          'Kraft',
          LucideIcons.dumbbell,
          p.strain,
          p.strainTint,
          'weight_training',
        ),
        tile(
          'Laufen',
          LucideIcons.footprints,
          p.strain,
          p.strainTint,
          'running',
        ),
        tile('Rad', LucideIcons.bike, p.strain, p.strainTint, 'cycling'),
        tile('Mehr', LucideIcons.plus, p.ink, p.well, null),
      ],
    );
  }
}

class OBWeekBars extends StatelessWidget {
  final List<String> days;
  final List<TrainingSession> sessions;
  const OBWeekBars({super.key, required this.days, required this.sessions});
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final minutes = {for (final d in days) d: 0};
    var unknown = false, count = 0;
    for (final s in sessions) {
      if (!minutes.containsKey(s.day)) continue;
      count++;
      if (s.durationMin == null) {
        unknown = true;
      } else {
        minutes[s.day] = minutes[s.day]! + s.durationMin!;
      }
    }
    final total = minutes.values.fold(0, (a, b) => a + b);
    final max = minutes.values.fold(0, (a, b) => a > b ? a : b);
    return OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Letzte 7 Tage',
                  style: p.text(13, weight: FontWeight.w600, color: p.muted),
                ),
              ),
              Text(
                count == 0
                    ? 'keine Einheit'
                    : '$count ${count == 1 ? 'Einheit' : 'Einheiten'}',
                style: p.text(13, weight: FontWeight.w500, color: p.muted),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                count == 0 ? '—' : '${unknown ? 'mind. ' : ''}$total',
                style: p.text(28, weight: FontWeight.w800, display: true),
              ),
              const SizedBox(width: 4),
              Text(
                'Min.',
                style: p.text(14, weight: FontWeight.w500, color: p.muted),
              ),
              if (unknown) ...[
                const SizedBox(width: 10),
                Text(
                  'Dauer teils unbekannt',
                  style: p.text(13, weight: FontWeight.w600, color: p.muted),
                ),
              ],
            ],
          ),
          Semantics(
            label:
                'Trainingsminuten je Tag: ${days.map((d) => '${DateFormat('EEE', 'de_DE').format(DateTime.parse(d))} ${minutes[d]}').join(', ')}',
            child: ExcludeSemantics(
              child: SizedBox(
                height: 80,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  spacing: 6,
                  children: [
                    for (final (i, d) in days.indexed)
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          spacing: 6,
                          children: [
                            Container(
                              height: max == 0 ? 4 : 4 + 48 * minutes[d]! / max,
                              decoration: BoxDecoration(
                                color: minutes[d]! > 0 ? p.strain : null,
                                border: i == days.length - 1 && minutes[d] == 0
                                    ? Border.all(color: p.gap, width: 1.5)
                                    : minutes[d] == 0
                                    ? Border.all(color: p.line, width: 1.5)
                                    : null,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            Text(
                              DateFormat(
                                'EEEEE',
                                'de_DE',
                              ).format(DateTime.parse(d)),
                              style: p.text(
                                11,
                                weight: FontWeight.w600,
                                color: p.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  final TrainingSession session;
  final bool divider;
  final VoidCallback? onTap;
  const _SessionRow({required this.session, required this.divider, this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final sport = obSport(session.type);
    final facts = [
      if (session.live)
        'läuft'
      else if (session.durationMin case final m?)
        '$m Min.',
      if (session.strain case final s?) 'Belastung ${obNumber(s, digits: 1)}',
    ];
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        decoration: divider
            ? BoxDecoration(
                border: Border(top: BorderSide(color: p.line)),
              )
            : null,
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: p.strainTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(sport.icon, size: 18, color: p.strain),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sport.label, style: p.text(15, weight: FontWeight.w600)),
                  Text(
                    facts.isEmpty ? 'ohne Messwerte' : facts.join(' · '),
                    style: p.text(13, color: p.muted),
                  ),
                ],
              ),
            ),
            Text(
              obDayTitle(session.day),
              style: p.text(13, weight: FontWeight.w500, color: p.muted),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Icon(LucideIcons.chevronRight, size: 16, color: p.gap),
            ],
          ],
        ),
      ),
    );
  }
}
