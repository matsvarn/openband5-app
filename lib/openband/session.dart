import 'package:flutter/material.dart';

import 'domain.dart';
import 'theme.dart';
import 'training.dart';

String obClock(int? seconds) {
  if (seconds == null) return '—';
  final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60, s = seconds % 60;
  return h > 0
      ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
      : '$m:${s.toString().padLeft(2, '0')}';
}

String obPace(double? meters, int? seconds) {
  if (meters == null || seconds == null || meters <= 0) return '—';
  return obClock((seconds / (meters / 1000)).round());
}

class OpenBandSession extends StatelessWidget {
  final OpenBandRepository repository;
  final TrainingSession session;
  const OpenBandSession({
    super.key,
    required this.repository,
    required this.session,
  });
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final sport = obSport(session.type);
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        backgroundColor: p.canvas,
        centerTitle: true,
        title: Column(
          children: [
            Text(sport.label, style: p.text(18, weight: FontWeight.w600)),
            Text(
              '${obDayTitle(session.day)} · ${obTime(session.start)}',
              style: p.text(12, color: p.muted),
            ),
          ],
        ),
      ),
      body: FutureBuilder<SessionDetail?>(
        future: repository.readSessionDetail(session.id),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Details konnten nicht geladen werden.',
                style: p.text(14, color: p.danger),
              ),
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox.shrink();
          }
          final d = snapshot.data;
          if (d == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  session.live
                      ? 'Die Einheit läuft noch. Details gibt es nach dem Ende.'
                      : 'Für diese Einheit sind keine Details gespeichert.',
                  textAlign: TextAlign.center,
                  style: p.text(14, color: p.muted),
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              OBSessionSummary(detail: d),
              if (d.zoneSec case final z? when z.any((s) => s > 0)) ...[
                const SizedBox(height: 10),
                OBZoneBars(zoneSec: z, avgHr: d.avgHr, maxHr: d.maxHr),
              ],
              if (d.splits.isNotEmpty) ...[
                const SizedBox(height: 10),
                OBSplitCard(splits: d.splits),
              ],
              if (d.laps.isNotEmpty) ...[
                const SizedBox(height: 10),
                OBLapCard(laps: d.laps),
              ],
              if (d.hrr60 != null || d.hrr120 != null) ...[
                const SizedBox(height: 10),
                OBCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Puls nach Ende',
                          style: p.text(15, weight: FontWeight.w600),
                        ),
                      ),
                      for (final (label, v) in [
                        ('60 s', d.hrr60),
                        ('120 s', d.hrr120),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                v == null ? '—' : '−$v',
                                style: p.text(
                                  20,
                                  weight: FontWeight.w800,
                                  display: true,
                                  color: p.pulse,
                                ),
                              ),
                              Text(
                                label,
                                style: p.text(
                                  12,
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
              ],
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Auswertung v${d.algoVersion}'
                  '${d.hrCoveredSec == null || d.durationSec == null ? '' : ' · Puls ${(d.hrCoveredSec! / 60).round()} von ${(d.durationSec! / 60).round()} Min.'}',
                  style: p.text(12, color: p.muted),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class OBSessionSummary extends StatelessWidget {
  final SessionDetail detail;
  const OBSessionSummary({super.key, required this.detail});
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final d = detail;
    Widget fact(String value, String label, {Color? color}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: p.text(
              20,
              weight: FontWeight.w700,
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
    final hero = d.distanceM != null
        ? (obNumber(d.distanceM! / 1000, digits: 2), 'km')
        : (obClock(d.durationSec), 'Dauer');
    return OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                hero.$1,
                style: p.text(34, weight: FontWeight.w800, display: true),
              ),
              const SizedBox(width: 6),
              Text(
                hero.$2,
                style: p.text(14, weight: FontWeight.w500, color: p.muted),
              ),
              const Spacer(),
              if (d.strain case final s?)
                Container(
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.strainTint,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Text(
                    'Belastung ${obNumber(s, digits: 1)}',
                    style: p.text(
                      13,
                      weight: FontWeight.w600,
                      color: p.strainText,
                    ),
                  ),
                ),
            ],
          ),
          Row(
            children: [
              if (d.distanceM != null) fact(obClock(d.durationSec), 'Zeit'),
              if (d.distanceM != null)
                fact(obPace(d.distanceM, d.durationSec), 'Tempo /km'),
              fact(
                d.avgHr == null ? '—' : obNumber(d.avgHr),
                'Puls Ø',
                color: d.avgHr == null ? p.gap : null,
              ),
              fact(
                d.kcal == null ? '—' : obNumber(d.kcal),
                'kcal',
                color: d.kcal == null ? p.gap : null,
              ),
            ],
          ),
          if (d.pauseSec case final ps? when ps > 0)
            Text(
              'davon ${obClock(ps)} pausiert',
              style: p.text(12, color: p.muted),
            ),
        ],
      ),
    );
  }
}

class OBZoneBars extends StatelessWidget {
  final List<int> zoneSec;
  final double? avgHr;
  final int? maxHr;
  const OBZoneBars({super.key, required this.zoneSec, this.avgHr, this.maxHr});
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final zones = zoneSec.length == 6 ? zoneSec.sublist(1) : zoneSec;
    final total = zones.fold(0, (a, b) => a + b);
    final colors = [p.sleepTint, p.stageRem, p.recovery, p.strain, p.pulse];
    return OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Herzfrequenzzonen',
                  style: p.text(15, weight: FontWeight.w600),
                ),
              ),
              Text(
                '${avgHr == null ? '' : 'Ø ${obNumber(avgHr)}'}${avgHr != null && maxHr != null ? ' · ' : ''}${maxHr == null ? '' : 'max $maxHr'}',
                style: p.text(13, weight: FontWeight.w500, color: p.muted),
              ),
            ],
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: SizedBox(
              height: 14,
              width: double.infinity,
              child: Row(
                spacing: 2,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, s) in zones.indexed)
                    if (s > 0 && total > 0)
                      Expanded(
                        flex: (s * 1000 / total).round(),
                        child: ColoredBox(color: colors[i % colors.length]),
                      ),
                ],
              ),
            ),
          ),
          Row(
            children: [
              for (final (i, s) in zones.indexed)
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        'Z${i + 1}',
                        style: p.text(
                          11,
                          weight: FontWeight.w600,
                          color: p.muted,
                        ),
                      ),
                      Text(
                        obClock(s),
                        style: p.text(
                          14,
                          weight: FontWeight.w700,
                          display: true,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// User-tapped lap marks — plain rows in the split card's typographic style;
/// a lap carries no per-km comparison, so there is deliberately no bar.
class OBLapCard extends StatelessWidget {
  final List<Lap> laps;
  const OBLapCard({super.key, required this.laps});
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return OBCard(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      child: Column(
        children: [
          SizedBox(
            height: 32,
            child: Row(
              children: [
                Text(
                  'RUNDEN',
                  style: p.text(11, weight: FontWeight.w600, color: p.muted),
                ),
              ],
            ),
          ),
          for (final l in laps)
            Container(
              height: 36,
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: p.line)),
              ),
              alignment: Alignment.centerLeft,
              child: Text(
                'Runde ${l.index} · ${obClock(l.elapsedSec - l.pausedSec)} · '
                '${l.distanceM == null ? '—' : '${obNumber(l.distanceM! / 1000, digits: 2)} km'}',
                style: p.text(14, weight: FontWeight.w700, display: true),
              ),
            ),
        ],
      ),
    );
  }
}

class OBSplitCard extends StatelessWidget {
  final List<SessionSplit> splits;
  const OBSplitCard({super.key, required this.splits});
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final fastest = splits
        .map((s) => s.seconds)
        .reduce((a, b) => a < b ? a : b);
    final slowest = splits
        .map((s) => s.seconds)
        .reduce((a, b) => a > b ? a : b);
    Widget head(String t, {double? width, TextAlign align = TextAlign.left}) =>
        SizedBox(
          width: width,
          child: Text(
            t,
            textAlign: align,
            style: p.text(11, weight: FontWeight.w600, color: p.muted),
          ),
        );
    return OBCard(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      child: Column(
        children: [
          SizedBox(
            height: 32,
            child: Row(
              children: [
                head('KM', width: 40),
                Expanded(child: head('TEMPO')),
                head('PULS', width: 56, align: TextAlign.right),
              ],
            ),
          ),
          for (final s in splits)
            Container(
              height: 36,
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: p.line)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${s.km}',
                      style: p.text(14, weight: FontWeight.w700, display: true),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          flex: (s.seconds * 100 / slowest).round(),
                          child: Container(
                            height: 8,
                            decoration: BoxDecoration(
                              color: s.seconds == fastest ? p.pulse : p.strain,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        Flexible(
                          flex:
                              ((slowest - s.seconds) * 100 / slowest).round() +
                              30,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 10),
                            child: Text(
                              obClock(s.seconds),
                              style: p.text(
                                14,
                                weight: FontWeight.w700,
                                display: true,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      s.avgHr == null ? '—' : obNumber(s.avgHr),
                      textAlign: TextAlign.right,
                      style: p.text(
                        14,
                        weight: FontWeight.w600,
                        color: p.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
