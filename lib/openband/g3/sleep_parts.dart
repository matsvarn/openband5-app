import 'package:flutter/material.dart';

import '../domain.dart' show NightSignalReading, NightSignalSeries;
import '../theme.dart' show OBChevron;
import 'chrome.dart' show OBPanel, OBPillButton;
import 'g3_theme.dart';
import 'metrics.dart' show G3LabelRow;

String obSleepDuration(num? minutes) {
  if (minutes == null) return '—';
  final value = minutes.round();
  return value >= 60
      ? '${value ~/ 60}h${(value % 60).toString().padLeft(2, '0')}'
      : '$value Min.';
}

String obSleepClock(DateTime? time) => time == null
    ? '—'
    : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

DateTime? roundedSleepBedtime(DateTime? value) {
  if (value == null) return null;
  return DateTime(
    value.year,
    value.month,
    value.day,
    value.hour,
    (value.minute / 5).round() * 5,
  );
}

String sleepDebtDirection(double minutes) => minutes > 0
    ? 'weniger als in freien Nächten'
    : minutes < 0
    ? 'mehr als in freien Nächten'
    : 'gleich lang wie in freien Nächten';

bool _onDebtScale(double? minutes) =>
    minutes != null && minutes >= 360 && minutes <= 540;

class OBSleepClockAxis extends StatelessWidget {
  const OBSleepClockAxis({
    super.key,
    required this.startHour,
    required this.endHour,
    this.leftInset = 0,
    this.labels = const ['22:00', '02:00', '06:00'],
  });
  final int startHour, endHour;
  final double leftInset;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final length = (endHour - startHour + 24) % 24 * 60;
    return Padding(
      padding: EdgeInsets.only(left: leftInset),
      child: LayoutBuilder(
        builder: (context, box) => SizedBox(
          height: 17,
          child: Stack(
            children: [
              for (final label in labels)
                Positioned(
                  left:
                      (((int.parse(label.substring(0, 2)) - startHour + 24) %
                                      24 *
                                      60 /
                                      length) *
                                  box.maxWidth -
                              22)
                          .clamp(0.0, box.maxWidth - 44),
                  width: 44,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: g.t(10, 14, color: g.muted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class OBBedtimeLead extends StatelessWidget {
  const OBBedtimeLead({
    super.key,
    required this.bedtime,
    required this.wake,
    this.lastOnset,
    this.lastWake,
    this.strainOpen = false,
    this.noFreeNight = false,
  });
  final DateTime? bedtime, wake, lastOnset, lastWake;
  final bool strainOpen;
  final bool noFreeNight;

  DateTime? get _roundedBedtime => roundedSleepBedtime(bedtime);

  double _position(DateTime time) {
    final minute = time.hour * 60 + time.minute;
    final afterNine = minute >= 21 * 60 ? minute - 21 * 60 : minute + 3 * 60;
    return (afterNine / (12 * 60)).clamp(0.0, 1.0);
  }

  Widget _track(
    G3 g,
    String label,
    DateTime? start,
    DateTime? end,
    bool today,
  ) {
    final valid = start != null && end != null && end.isAfter(start);
    final left = valid ? _position(start) : 0.0;
    final right = valid ? _position(end) : 0.0;
    return Row(
      children: [
        SizedBox(
          width: 58,
          child: Text(
            label,
            style: g.t(12, 16, color: today ? g.ink : g.muted),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => SizedBox(
              height: 10,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: g.pressed(radius: 5, color: g.track),
                    ),
                  ),
                  if (valid && right > left)
                    Positioned(
                      left: left * box.maxWidth,
                      width: (right - left) * box.maxWidth,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        decoration: g.pressed(
                          radius: 5,
                          color: today ? g.ink : g.bar,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final shown = _roundedBedtime;
    final earlier = shown == null || lastOnset == null
        ? null
        : ((lastOnset!.hour * 60 +
                      lastOnset!.minute -
                      shown.hour * 60 -
                      shown.minute +
                      720) %
                  1440) -
              720;
    return OBPanel(
      hero: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('INS BETT', style: g.caps()),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  shown == null
                      ? 'Kein Vorschlag'
                      : strainOpen
                      ? 'Schätzung · Belastung läuft'
                      : 'Schätzung',
                  textAlign: TextAlign.end,
                  style: g.t(12, 16, color: g.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (noFreeNight) ...[
            Container(width: 60, height: 6, color: g.gap),
            const SizedBox(height: 14),
            Text(
              'Noch keine freie Nacht',
              style: g.t(17, 22, weight: FontWeight.w700),
            ),
            const SizedBox(height: 5),
            Text(
              'Ohne freie Nacht kein Bedarf und keine Bettzeit.',
              style: g.t(13, 18, color: g.ink2),
            ),
          ] else
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 10,
              children: [
                MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.2,
                  child: Text(
                    obSleepClock(shown),
                    style: g.t(
                      68,
                      72,
                      weight: FontWeight.w700,
                      tracking: -.045,
                    ),
                  ),
                ),
                if (wake != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Text(
                      'bis ${obSleepClock(wake)}${earlier == null ? '' : '\n${earlier.abs()} Min. ${earlier >= 0 ? 'früher' : 'später'}'}',
                      style: g.t(13, 18, color: g.ink2),
                    ),
                  ),
              ],
            ),
          if (shown != null && wake != null) ...[
            const SizedBox(height: 18),
            _track(g, 'Heute', shown, wake, true),
            const SizedBox(height: 12),
            _track(g, 'Gestern', lastOnset, lastWake, false),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 58),
              child: const OBSleepClockAxis(startHour: 21, endHour: 9),
            ),
          ],
        ],
      ),
    );
  }
}

class OBSleepLead extends StatelessWidget {
  const OBSleepLead({
    super.key,
    required this.minutes,
    required this.goalMinutes,
    this.bedMinutes,
    this.onGoal,
  });
  final double? minutes;
  final double? bedMinutes;
  final int? goalMinutes;
  final VoidCallback? onGoal;

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final difference = minutes == null || goalMinutes == null
        ? null
        : (minutes! - goalMinutes!).round();
    return OBPanel(
      hero: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          G3LabelRow(
            'SCHLAF',
            note: goalMinutes == null
                ? 'kein Ziel'
                : 'Ziel ${obSleepDuration(goalMinutes)}',
          ),
          const SizedBox(height: 8),
          if (minutes == null) ...[
            Row(
              children: [
                Container(
                  width: 60,
                  height: 6,
                  decoration: BoxDecoration(
                    color: g.gap,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Keine Nacht erkannt',
                  style: g.t(17, 22, weight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Das Band fand kein Schlaffenster.',
              style: g.t(13, 17, color: g.ink2),
            ),
          ] else ...[
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 12,
              runSpacing: 4,
              children: [
                MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.2,
                  child: Text(
                    obSleepDuration(minutes),
                    style: g.t(
                      72,
                      76,
                      weight: FontWeight.w700,
                      tracking: -.045,
                    ),
                  ),
                ),
                if (difference != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: g.chip,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Text(
                            '${difference < 0
                                ? '↓'
                                : difference > 0
                                ? '↑'
                                : '·'} ${obSleepDuration(difference.abs())}',
                            style: g.t(13, 16, weight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          difference < 0
                              ? 'unter deinem Ziel'
                              : difference > 0
                              ? 'über deinem Ziel'
                              : 'dein Ziel erreicht',
                          style: g.t(13, 17, color: g.ink2),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          if (minutes != null) ...[
            const SizedBox(height: 15),
            LayoutBuilder(
              builder: (context, box) {
                final width = box.maxWidth;
                final fill = (minutes! / 600).clamp(0.0, 1.0) * width;
                final target = goalMinutes == null
                    ? null
                    : (goalMinutes! / 600).clamp(0.0, 1.0) * width;
                return SizedBox(
                  height: 24,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 7,
                        child: Container(
                          height: 10,
                          decoration: g.pressed(radius: 5, color: g.track),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: 7,
                        width: fill,
                        child: Container(
                          height: 10,
                          decoration: BoxDecoration(
                            color: g.ink,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                      if (target != null)
                        Positioned(
                          left: target - 1,
                          top: 0,
                          child: Container(width: 2, height: 24, color: g.ink),
                        ),
                    ],
                  ),
                );
              },
            ),
            Row(
              children: [
                Text('0 h', style: g.t(12, 16, color: g.muted)),
                const Spacer(),
                if (goalMinutes != null)
                  Text(
                    'Ziel ${obSleepDuration(goalMinutes)}',
                    style: g.t(12, 16, color: g.ink2),
                  ),
                const Spacer(),
                Text('10 h', style: g.t(12, 16, color: g.muted)),
              ],
            ),
          ],
          if (goalMinutes == null && onGoal != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                OBPillButton('Ziel festlegen', onPressed: onGoal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'zeigt, wie weit du davon weg bist',
                    style: g.t(12, 16, color: g.muted),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

typedef OBSleepWindow = ({
  String day,
  DateTime? start,
  DateTime? end,
  double? minutes,
});

class OBSriLead extends StatelessWidget {
  const OBSriLead({super.key, this.value, this.gate});
  final double? value;
  final String? gate;

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return OBPanel(
      hero: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          G3LabelRow(
            'SRI',
            note: value == null ? 'im Aufbau' : 'aus 7 Nächten',
          ),
          const SizedBox(height: 7),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 8,
            children: [
              Text(
                value == null ? '—' : value!.round().toString(),
                style: g.t(72, 76, weight: FontWeight.w700),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('von 100', style: g.t(14, 19, color: g.ink2)),
              ),
            ],
          ),
          Text(
            gate ?? 'SRI reicht von −100 bis 100 · 100 = jeden Tag gleich',
            style: g.t(13, 18, color: g.ink2),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, box) => SizedBox(
              height: 23,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 7,
                    child: Container(
                      height: 9,
                      decoration: g.pressed(radius: 5),
                    ),
                  ),
                  if (value != null)
                    Positioned(
                      left:
                          ((value! + 100) / 200).clamp(0.0, 1.0) *
                          (box.maxWidth - 3),
                      child: Container(width: 3, height: 23, color: g.ink),
                    ),
                ],
              ),
            ),
          ),
          Row(
            children: [
              Text('−100', style: g.t(12, 16, color: g.muted)),
              const Spacer(),
              Text('0', style: g.t(12, 16, color: g.muted)),
              const Spacer(),
              Text('100', style: g.t(12, 16, color: g.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

class OBSleepWindows extends StatelessWidget {
  const OBSleepWindows({
    super.key,
    required this.windows,
    required this.regularity,
    this.gate,
    this.onTap,
    this.detail = false,
  });
  final List<OBSleepWindow> windows;
  final double? regularity;
  final String? gate;
  final VoidCallback? onTap;
  final bool detail;

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return OBPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          G3LabelRow(
            detail ? 'IM BETT JE NACHT' : 'REGELMÄSSIGKEIT',
            note: regularity == null
                ? gate == null
                      ? 'nicht für diesen Tag'
                      : 'Basis im Aufbau'
                : windows.isEmpty
                ? null
                : '${windows.length} Nächte',
          ),
          if (!detail) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  regularity == null ? '—' : regularity!.round().toString(),
                  style: g.t(38, 42, weight: FontWeight.w700),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    'SRI · −100 bis 100',
                    style: g.t(12, 16, color: g.ink2),
                  ),
                ),
              ],
            ),
            if (regularity == null)
              Text(
                gate ?? 'Für diesen Tag keine Auswertung gespeichert.',
                style: g.t(12, 16, color: g.ink2),
              ),
          ],
          const SizedBox(height: 10),
          for (final window in windows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 42,
                    child: Text(window.day, style: g.t(12, 16, color: g.muted)),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) {
                        if (window.start == null || window.end == null) {
                          return const G3Dashed(height: 10, radius: 5);
                        }
                        double position(DateTime t) {
                          final m = t.hour * 60 + t.minute;
                          return ((m < 12 * 60 ? m + 24 * 60 : m) - 21 * 60) /
                              (13 * 60) *
                              box.maxWidth;
                        }

                        final left = position(
                          window.start!,
                        ).clamp(0.0, box.maxWidth);
                        final right = position(
                          window.end!,
                        ).clamp(0.0, box.maxWidth);
                        return SizedBox(
                          height: 10,
                          child: Stack(
                            children: [
                              Positioned(
                                left: 0,
                                right: 0,
                                top: 4,
                                child: Container(height: 1, color: g.hairline),
                              ),
                              if (right > left)
                                Positioned(
                                  left: left,
                                  width: right - left,
                                  child: Container(
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: window.day == 'Heute'
                                          ? g.ink
                                          : g.bar,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: OBSleepClockAxis(startHour: 21, endHour: 10, leftInset: 42),
          ),
          if (onTap != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: onTap, child: const Text('Ansehen')),
            ),
        ],
      ),
    );
  }
}

class OBSocialJetlag extends StatelessWidget {
  const OBSocialJetlag({super.key, this.minutes, this.gate, this.onTap});
  final double? minutes;
  final String? gate;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return OBPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          G3LabelRow('SOZIALE ZEITVERSCHIEBUNG', note: '7 Nächte'),
          const SizedBox(height: 6),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 8,
            children: [
              Text(
                obSleepDuration(minutes?.abs()),
                style: g.t(34, 40, weight: FontWeight.w700),
              ),
              if (minutes != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    minutes! < 0
                        ? 'früher an freien Tagen'
                        : 'später an freien Tagen',
                    style: g.t(12, 16, color: g.ink2),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            gate ??
                (minutes == null
                    ? 'Für diesen Tag keine Auswertung gespeichert.'
                    : 'Schlafmitte an Arbeitstagen gegenüber Sa und So, ohne Kalender.'),
            style: g.t(12, 16, color: g.ink2),
          ),
          if (onTap != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: onTap, child: const Text('Methode')),
            ),
        ],
      ),
    );
  }
}

class OBSleepDebtLead extends StatelessWidget {
  const OBSleepDebtLead({super.key, this.minutes});
  final double? minutes;

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final rounded = minutes?.round();
    return OBPanel(
      hero: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          G3LabelRow('SCHLAFSCHULD', note: '3 Wochen'),
          const SizedBox(height: 8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 12,
            children: [
              Text(
                obSleepDuration(rounded?.abs()),
                style: g.t(72, 76, weight: FontWeight.w700),
              ),
              if (minutes != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: SizedBox(
                    width: 105,
                    child: Text(
                      sleepDebtDirection(minutes!),
                      style: g.t(13, 18, color: g.ink2),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class OBSleepDebt extends StatelessWidget {
  const OBSleepDebt({
    super.key,
    this.minutes,
    this.freeMinutes,
    this.usualMinutes,
    this.gate,
    this.onTap,
    this.detail = false,
  });
  final double? minutes, freeMinutes, usualMinutes;
  final String? gate;
  final VoidCallback? onTap;
  final bool detail;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return OBPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          G3LabelRow(
            detail ? 'FREI UND ÜBLICH' : 'SCHLAFSCHULD',
            note: detail ? 'Stunden Schlaf' : 'frei gegen üblich',
          ),
          if (!detail) ...[
            const SizedBox(height: 5),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 8,
              children: [
                Text(
                  obSleepDuration(minutes?.abs()),
                  style: g.t(34, 40, weight: FontWeight.w700),
                ),
                if (minutes != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      sleepDebtDirection(minutes!),
                      style: g.t(12, 16, color: g.ink2),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          _fact(context, 'Frei · p75', freeMinutes),
          _fact(context, 'Üblich · Median', usualMinutes),
          if (_onDebtScale(freeMinutes) || _onDebtScale(usualMinutes)) ...[
            const SizedBox(height: 8),
            _debtTrack(g, freeMinutes, hollow: true),
            const SizedBox(height: 8),
            _debtTrack(g, usualMinutes, hollow: false),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final label in ['6 h', '7 h', '8 h', '9 h'])
                  Text(label, style: g.t(10, 14, color: g.muted)),
              ],
            ),
          ],
          if ((freeMinutes != null && !_onDebtScale(freeMinutes)) ||
              (usualMinutes != null && !_onDebtScale(usualMinutes)))
            Text(
              'Wert außerhalb der Skala 6–9 h.',
              style: g.t(12, 16, color: g.muted),
            ),
          const SizedBox(height: 10),
          Text(
            gate ??
                (minutes == null
                    ? 'Für diesen Tag keine Auswertung gespeichert.'
                    : 'Perzentil freien Schlafs, kein gemessener Bedarf.'),
            style: g.t(12, 16, color: g.ink2),
          ),
          if (onTap != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: onTap, child: const Text('Methode')),
            ),
        ],
      ),
    );
  }

  Widget _fact(BuildContext context, String label, double? minutes) {
    final g = G3.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: g.t(13, 17, color: g.ink2)),
          ),
          Text(
            obSleepDuration(minutes),
            style: g.t(15, 19, weight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _debtTrack(G3 g, double? minutes, {required bool hollow}) {
    return LayoutBuilder(
      builder: (context, box) {
        final x = minutes == null || minutes < 360 || minutes > 540
            ? null
            : ((minutes - 360) / 180) * (box.maxWidth - 12);
        return SizedBox(
          height: 12,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 5,
                child: Container(height: 1, color: g.hairline),
              ),
              if (x != null)
                Positioned(
                  left: x,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hollow ? g.canvas : g.ink,
                      border: Border.all(color: g.ink, width: 2),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class OBPlanBreakdown extends StatelessWidget {
  const OBPlanBreakdown({
    super.key,
    this.baseline,
    this.debt,
    this.bonus,
    this.napCredit,
    this.napsIncomplete = false,
    this.strainOpen = false,
    this.need,
    this.efficiency,
    this.wake,
    this.bedtime,
  });
  final double? baseline, debt, bonus, napCredit, need, efficiency;
  final bool napsIncomplete;
  final bool strainOpen;
  final DateTime? wake, bedtime;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    Widget row(String name, String value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: g.t(
                14,
                18,
                weight: strong ? FontWeight.w700 : FontWeight.w400,
                color: strong ? g.ink : g.ink2,
              ),
            ),
          ),
          Text(value, style: g.t(15, 19, weight: FontWeight.w700)),
        ],
      ),
    );
    return OBPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          G3LabelRow(
            'RECHNUNG',
            note: bedtime == null
                ? null
                : 'gerundet von ${obSleepClock(bedtime)}',
          ),
          row('Freie Nächte · p75', obSleepDuration(baseline)),
          Divider(height: 1, color: g.line),
          row(
            'Schlafschuld, positiv',
            obSleepDuration(
              debt == null
                  ? null
                  : debt! > 0
                  ? debt
                  : 0,
            ),
          ),
          Divider(height: 1, color: g.line),
          row(
            strainOpen ? 'Belastung heute, läuft' : 'Belastung heute',
            bonus == null ? '—' : '+ ${obSleepDuration(bonus)}',
          ),
          Divider(height: 1, color: g.line),
          row(
            'Nickerchen heute',
            napsIncomplete
                ? 'unvollständig'
                : napCredit == null
                ? '—'
                : '− ${obSleepDuration(napCredit)}',
          ),
          Divider(height: 2, thickness: 2, color: g.ink),
          row('Geschätzter Bedarf', obSleepDuration(need), strong: true),
          Divider(height: 1, color: g.line),
          row(
            '÷ übliche Schlafeffizienz',
            efficiency == null || efficiency! <= 0 || need == null
                ? '—'
                : '${obSleepDuration(need! / efficiency!)} im Bett',
          ),
          Divider(height: 1, color: g.line),
          row('Aufstehen, üblich', obSleepClock(wake)),
          Divider(height: 2, thickness: 2, color: g.ink),
          row(
            'Ins Bett',
            obSleepClock(roundedSleepBedtime(bedtime)),
            strong: true,
          ),
          if (napsIncomplete)
            Text(
              'Nickerchen heute noch offen, nicht abgezogen.',
              style: g.t(12, 16, color: g.ink2),
            ),
        ],
      ),
    );
  }
}

class OBInlineNotice extends StatelessWidget {
  const OBInlineNotice({
    super.key,
    required this.text,
    this.subtitle,
    this.icon,
    this.action,
    this.onAction,
    this.actionChevron = true,
  });
  final String text;
  final String? subtitle;
  final IconData? icon;
  final String? action;
  final VoidCallback? onAction;
  final bool actionChevron;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: g.pressed(),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: g.ink),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: g.t(
                    subtitle == null ? 13 : 15,
                    subtitle == null ? 17 : 19,
                    weight: subtitle == null
                        ? FontWeight.w400
                        : FontWeight.w700,
                    color: subtitle == null ? g.ink2 : g.ink,
                  ),
                ),
                if (subtitle != null)
                  Text(subtitle!, style: g.t(13, 17, color: g.ink2)),
              ],
            ),
          ),
          if (action != null && onAction != null)
            TextButton(
              onPressed: onAction,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(action!),
                  if (actionChevron) ...[
                    const SizedBox(width: 3),
                    OBChevron(size: 12),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One recorded night signal. Null readings and intervals beyond the stored
/// connecting cadence break the stroke instead of interpolating a value.
class OBNightTrace extends StatelessWidget {
  const OBNightTrace({
    super.key,
    required this.series,
    required this.start,
    required this.end,
  });
  final NightSignalSeries series;
  final DateTime start, end;

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label:
              'Nachtverlauf mit ${series.readings.where((r) => r.value != null).length} gespeicherten Messpunkten. Lücken bleiben leer.',
          child: RepaintBoundary(
            child: SizedBox(
              height: 180,
              child: CustomPaint(
                painter: _NightTracePainter(
                  series.readings,
                  start,
                  end,
                  series.maxConnectingGap,
                  g.ink,
                  g.hairline,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(obSleepClock(start), style: g.t(11, 15, color: g.muted)),
            Text(
              obSleepClock(start.add(end.difference(start) ~/ 2)),
              style: g.t(11, 15, color: g.muted),
            ),
            Text(obSleepClock(end), style: g.t(11, 15, color: g.muted)),
          ],
        ),
      ],
    );
  }
}

class _NightTracePainter extends CustomPainter {
  const _NightTracePainter(
    this.readings,
    this.start,
    this.end,
    this.maxGap,
    this.ink,
    this.grid,
  );
  final List<NightSignalReading> readings;
  final DateTime start, end;
  final Duration? maxGap;
  final Color ink, grid;

  @override
  void paint(Canvas canvas, Size size) {
    final duration = end.difference(start).inMilliseconds;
    if (duration <= 0) return;
    final valid = readings
        .where(
          (r) => r.value != null && r.at.isAfter(start) && r.at.isBefore(end),
        )
        .toList();
    if (valid.isEmpty) return;
    final values = valid.map((r) => r.value!).toList();
    var low = values.reduce((a, b) => a < b ? a : b);
    var high = values.reduce((a, b) => a > b ? a : b);
    if (low == high) {
      low -= 1;
      high += 1;
    }
    final span = high - low;
    for (var i = 0; i < 3; i++) {
      final y = 15 + i * (size.height - 30) / 2;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = grid
          ..strokeWidth = 1,
      );
    }
    Offset point(NightSignalReading r) => Offset(
      r.at.difference(start).inMilliseconds / duration * size.width,
      15 + (high - r.value!) / span * (size.height - 30),
    );
    final line = Paint()
      ..color = ink
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    NightSignalReading? previous;
    var path = Path();
    for (final r in readings) {
      if (r.value == null || r.at.isBefore(start) || r.at.isAfter(end)) {
        canvas.drawPath(path, line);
        path = Path();
        previous = null;
        continue;
      }
      final p = point(r);
      if (previous == null ||
          maxGap == null ||
          r.at.difference(previous.at) > maxGap!) {
        canvas.drawPath(path, line);
        path = Path()..moveTo(p.dx, p.dy);
        canvas.drawCircle(p, 1.6, Paint()..color = ink);
      } else {
        path.lineTo(p.dx, p.dy);
      }
      previous = r;
    }
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(_NightTracePainter old) =>
      old.readings != readings ||
      old.start != start ||
      old.end != end ||
      old.maxGap != maxGap ||
      old.ink != ink ||
      old.grid != grid;
}
