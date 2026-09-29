import 'package:flutter/material.dart';

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

class OBSleepLead extends StatelessWidget {
  const OBSleepLead({
    super.key,
    required this.minutes,
    required this.goalMinutes,
    this.onGoal,
  });
  final double? minutes;
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
                ? null
                : 'Ziel ${obSleepDuration(goalMinutes)}',
          ),
          const SizedBox(height: 8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 12,
            runSpacing: 4,
            children: [
              MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.2,
                child: Text(
                  obSleepDuration(minutes),
                  style: g.t(72, 76, weight: FontWeight.w700, tracking: -.045),
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
                              : '·'} ${difference.abs()} Min.',
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
          ] else
            Text(
              'Keine Nacht erkannt. Nichts wird geschätzt.',
              style: g.t(13, 18, color: g.ink2),
            ),
          if (goalMinutes == null && onGoal != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OBPillButton('Ziel festlegen', onPressed: onGoal),
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

class OBSleepWindows extends StatelessWidget {
  const OBSleepWindows({
    super.key,
    required this.windows,
    required this.regularity,
    this.gate,
    this.onTap,
  });
  final List<OBSleepWindow> windows;
  final double? regularity;
  final String? gate;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return OBPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          G3LabelRow(
            'REGELMÄSSIGKEIT',
            note: regularity == null
                ? 'im Aufbau'
                : windows.isEmpty
                ? null
                : '${windows.length} Nächte',
          ),
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
                  'SRI · 0 bis 100',
                  style: g.t(12, 16, color: g.ink2),
                ),
              ),
            ],
          ),
          if (gate != null) Text(gate!, style: g.t(12, 16, color: g.ink2)),
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
          Padding(
            padding: const EdgeInsets.only(left: 42, top: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final label in ['22:00', '02:00', '06:00'])
                  Text(label, style: g.t(10, 14, color: g.muted)),
              ],
            ),
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
                obSleepDuration(minutes),
                style: g.t(34, 40, weight: FontWeight.w700),
              ),
              if (minutes != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    'später an freien Tagen',
                    style: g.t(12, 16, color: g.ink2),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            gate ??
                'Schlafmitte an Arbeitstagen gegenüber Sa und So, ohne Kalender.',
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

class OBSleepDebt extends StatelessWidget {
  const OBSleepDebt({
    super.key,
    this.minutes,
    this.freeMinutes,
    this.usualMinutes,
    this.gate,
    this.onTap,
  });
  final double? minutes, freeMinutes, usualMinutes;
  final String? gate;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return OBPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          G3LabelRow('SCHLAFSCHULD', note: 'frei gegen üblich'),
          const SizedBox(height: 5),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 8,
            children: [
              Text(
                obSleepDuration(minutes),
                style: g.t(34, 40, weight: FontWeight.w700),
              ),
              if (minutes != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    'weniger als in freien Nächten',
                    style: g.t(12, 16, color: g.ink2),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _fact(context, 'Frei · p75', freeMinutes),
          _fact(context, 'Üblich · Median', usualMinutes),
          const SizedBox(height: 10),
          Text(
            gate ?? 'Perzentil freien Schlafs, kein gemessener Bedarf.',
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
}

class OBPlanBreakdown extends StatelessWidget {
  const OBPlanBreakdown({
    super.key,
    this.goal,
    this.bonus,
    this.napCredit,
    this.napsIncomplete = false,
    this.need,
    this.efficiency,
    this.wake,
    this.bedtime,
  });
  final double? goal, bonus, napCredit, need, efficiency;
  final bool napsIncomplete;
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
          G3LabelRow('RECHNUNG', note: bedtime == null ? null : 'Schätzung'),
          row('Eigenes Schlafziel', obSleepDuration(goal)),
          Divider(height: 1, color: g.line),
          row(
            'Belastung heute',
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
            'Übliche Schlafeffizienz',
            efficiency == null ? '—' : '${(efficiency! * 100).round()} %',
          ),
          Divider(height: 1, color: g.line),
          row('Aufstehen, üblich', obSleepClock(wake)),
          Divider(height: 2, thickness: 2, color: g.ink),
          row('Ins Bett', obSleepClock(bedtime), strong: true),
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
    this.action,
    this.onAction,
  });
  final String text;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: g.pressed(),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: g.t(13, 17, color: g.ink2)),
          ),
          if (action != null && onAction != null)
            TextButton(
              onPressed: onAction,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(action!),
                  const SizedBox(width: 3),
                  OBChevron(size: 12),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
