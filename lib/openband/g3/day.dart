// G3 day Bausteine: Für-heute note, activity row, check-in, week bars,
// night card with hypnogram, steps card.
//
// Pure presentation: strings come from the note engine / repository, values
// are nullable, deviations are decided by the caller.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../alp_tokens.dart';
import '../theme.dart' show OBChevron;
import 'chrome.dart' show OBActionSecondary, OBPillButton;
import 'g3_theme.dart';
import 'metrics.dart' show G3LabelRow, G3ValueLine, OBChip, OBChipKind;

// ---------------------------------------------------------------------------
// Für heute

enum OBNoteState { action, reminded, text, absent }

/// The only filled block on Heute. Rule-based text from the note engine;
/// [OBNoteState.absent] when an input it would name is missing.
class OBDayNote extends StatelessWidget {
  final OBNoteState state;
  final String headline, reason;

  /// Action row: "22:20 ins Bett" / "für 8h05 Schlafbedarf bis 06:54", or the
  /// reminder confirmation when [state] is reminded.
  final String? actionTitle, actionSubtitle;
  final String remindLabel;
  final VoidCallback? onRemind, onUnsubscribe;
  const OBDayNote({
    super.key,
    required this.state,
    required this.headline,
    required this.reason,
    this.actionTitle,
    this.actionSubtitle,
    this.remindLabel = 'Erinnern',
    this.onRemind,
    this.onUnsubscribe,
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    if (state == OBNoteState.absent) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: g.pressed(),
        child: Row(
          children: [
            Icon(LucideIcons.info, size: 18, color: g.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(headline, style: g.t(15, 19, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(reason, style: g.t(13, 17, color: g.ink2)),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final hasAction = state != OBNoteState.text && actionTitle != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 18, 14),
      decoration: BoxDecoration(
        color: g.note,
        borderRadius: BorderRadius.circular(AlpRadius.hero),
        boxShadow: g.noteShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('FÜR HEUTE', style: g.caps(color: g.noteMuted)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'aus deinen Werten',
                  textAlign: TextAlign.right,
                  style: g.t(12, 16, color: g.noteMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            headline,
            style: g.t(
              AlpText.noteTitle,
              26,
              weight: FontWeight.w700,
              color: g.noteInk,
              tracking: -.02,
            ),
          ),
          const SizedBox(height: 6),
          Text(reason, style: g.t(14, 19, color: g.noteInk2)),
          if (hasAction) ...[
            const SizedBox(height: 12),
            Container(
              padding: EdgeInsets.fromLTRB(
                12,
                0,
                state == OBNoteState.reminded ? 4 : 8,
                0,
              ),
              decoration: BoxDecoration(
                color: g.noteInset,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    state == OBNoteState.reminded
                        ? LucideIcons.bell
                        : LucideIcons.moon,
                    size: 20,
                    color: g.noteInk,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            actionTitle!,
                            style: g.t(
                              15,
                              19,
                              weight: FontWeight.w700,
                              color: g.noteInk,
                            ),
                          ),
                          if (actionSubtitle != null)
                            Text(
                              actionSubtitle!,
                              style: g.t(12, 16, color: g.noteMuted),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (state == OBNoteState.reminded)
                    Semantics(
                      button: true,
                      label: 'Erinnerung abbestellen',
                      excludeSemantics: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onUnsubscribe,
                        child: SizedBox(
                          width: 44,
                          height: 54,
                          child: Icon(
                            LucideIcons.check,
                            size: 18,
                            color: g.noteInk,
                          ),
                        ),
                      ),
                    )
                  else
                    Semantics(
                      button: true,
                      label: '$remindLabel: $actionTitle',
                      excludeSemantics: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onRemind,
                        child: SizedBox(
                          height: 54,
                          child: Center(
                            child: Container(
                              height: 34,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: g.noteAction,
                                borderRadius: BorderRadius.circular(17),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  remindLabel,
                                  style: g.t(
                                    14,
                                    18,
                                    weight: FontWeight.w700,
                                    color: AlpColor.ink,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Activity row

/// Minutes per zone (Z1…Z5) as a grey ramp; zero zones are left out.
class OBZoneStrip extends StatelessWidget {
  final List<int> minutes;
  const OBZoneStrip(this.minutes, {super.key});
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final shown = [
      for (final (i, m) in minutes.indexed)
        if (m > 0) (i, m),
    ];
    return SizedBox(
      height: 6,
      child: Row(
        children: [
          for (final (k, (i, m)) in shown.indexed) ...[
            if (k > 0) const SizedBox(width: 2),
            Expanded(
              flex: m,
              child: Container(
                decoration: BoxDecoration(
                  color: g.zones[i],
                  borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(k == 0 ? 3 : 0),
                    right: Radius.circular(k == shown.length - 1 ? 3 : 0),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class OBActivityRow extends StatelessWidget {
  final Widget pictogram;
  final String title, subtitle;

  /// Auto-detected and not yet confirmed: no zones, a hint instead.
  final bool unconfirmed;

  /// Formatted strain contribution ("+6,1"); null renders "—".
  final String? strain;
  final List<int>? zoneMinutes;
  final VoidCallback? onTap;
  const OBActivityRow({
    super.key,
    required this.pictogram,
    required this.title,
    required this.subtitle,
    this.unconfirmed = false,
    this.strain,
    this.zoneMinutes,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Semantics(
      button: onTap != null,
      label:
          '$title, $subtitle${unconfirmed ? ', automatisch erkannt' : ''}, Belastung ${strain ?? 'unbekannt'}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: g.raised(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: g.pressed(radius: 12, color: g.track),
                    child: pictogram,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              title,
                              style: g.t(17, 22, weight: FontWeight.w700),
                            ),
                            if (unconfirmed)
                              const OBChip(OBChipKind.tag, 'auto-erkannt'),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(subtitle, style: g.t(13, 17, color: g.ink2)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      MediaQuery.withClampedTextScaling(
                        maxScaleFactor: 1.3,
                        child: Text(
                          strain ?? '—',
                          style: g.t(
                            20,
                            24,
                            weight: FontWeight.w700,
                            color: strain == null ? g.gap : g.ink,
                            tracking: -.02,
                          ),
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text('Belastung', style: g.t(11, 14, color: g.muted)),
                    ],
                  ),
                  const SizedBox(width: 12),
                  OBChevron(size: 14, color: g.gap),
                ],
              ),
              if (unconfirmed)
                Padding(
                  padding: const EdgeInsets.only(left: 56, top: 12),
                  child: Text(
                    'Zonen nach Bestätigung',
                    style: g.t(12, 16, weight: FontWeight.w500, color: g.muted),
                  ),
                )
              else if (zoneMinutes case final z?)
                Padding(
                  padding: const EdgeInsets.only(left: 56, right: 26, top: 12),
                  child: OBZoneStrip(z),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Check-in

enum OBCheckInState { question, answered, later }

/// One journal question at a time. "Später" never penalises.
class OBCheckIn extends StatelessWidget {
  final OBCheckInState state;
  final String progress;
  final String? question, answered;
  final String laterText;
  final VoidCallback? onYes, onNo, onLater, onChange, onResume;
  const OBCheckIn({
    super.key,
    required this.state,
    required this.progress,
    this.question,
    this.answered,
    this.laterText = 'Für später gemerkt. Kein Nachteil, wenn du es auslässt.',
    this.onYes,
    this.onNo,
    this.onLater,
    this.onChange,
    this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    Widget buttons() => Row(
      children: [
        Expanded(
          child: OBActionSecondary(
            'Nein',
            onPressed: onNo,
            height: 40,
            expand: true,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OBActionSecondary(
            'Ja',
            onPressed: onYes,
            height: 40,
            expand: true,
          ),
        ),
        Semantics(
          button: true,
          label: 'Später',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onLater,
            child: SizedBox(
              width: 80,
              height: 44,
              child: Center(
                child: Text(
                  'Später',
                  style: g.t(14, 18, weight: FontWeight.w500, color: g.ink2),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        14,
        14,
        state == OBCheckInState.later ? 9 : 12,
      ),
      decoration: g.pressed(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.notebookPen, size: 16, color: g.ink),
              const SizedBox(width: 8),
              Text('CHECK-IN', style: g.caps()),
              const Spacer(),
              Text(
                progress,
                style: g.t(12, 16, weight: FontWeight.w500, color: g.ink2),
              ),
            ],
          ),
          SizedBox(height: state == OBCheckInState.later ? 7 : 12),
          if (state == OBCheckInState.later)
            Row(
              children: [
                Expanded(
                  child: Text(laterText, style: g.t(13, 17, color: g.ink2)),
                ),
                const SizedBox(width: 10),
                OBActionSecondary('Jetzt', onPressed: onResume, height: 34),
              ],
            )
          else ...[
            if (state == OBCheckInState.answered && answered != null) ...[
              Row(
                children: [
                  Icon(LucideIcons.check, size: 16, color: g.ink),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      answered!,
                      style: g.t(
                        14,
                        18,
                        weight: FontWeight.w500,
                        color: g.ink2,
                      ),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Antwort ändern',
                    excludeSemantics: true,
                    child: GestureDetector(
                      onTap: onChange,
                      child: Text(
                        'Ändern',
                        style: g.t(13, 16, weight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Text(
              question ?? '',
              style: g.t(19, 24, weight: FontWeight.w700, tracking: -.015),
            ),
            const SizedBox(height: 10),
            buttons(),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Week bars

class OBWeekBar {
  final String day;
  final double? value;

  /// Label above the bar (recovery) or below the day (sleep); null hides it.
  final String? label;
  final G3Deviation deviation;
  final bool today;
  const OBWeekBar(
    this.day,
    this.value, {
    this.label,
    this.deviation = G3Deviation.none,
    this.today = false,
  });
}

/// Seven days. Bars start at zero; a null value is a dashed slot, never a
/// short bar. [labelsBelow] puts values under the day (sleep durations).
class OBWeekBars extends StatelessWidget {
  final List<OBWeekBar> bars;

  /// Value that fills the 111 pt chart height.
  final double max;
  final (double, double)? band;
  final double? goal;
  final bool labelsBelow;

  /// Centred reason when no bar has a value ("Erholung braucht 14 Nächte").
  final String? emptyReason;
  final List<Widget> footer;
  const OBWeekBars({
    super.key,
    required this.bars,
    required this.max,
    this.band,
    this.goal,
    this.labelsBelow = false,
    this.emptyReason,
    this.footer = const [],
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    const h = 111.0;
    double y(double v) => h - (v / max).clamp(0.0, 1.0) * h;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: g.raised(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 112,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (band case (final lo, final hi))
                  Positioned(
                    left: 0,
                    right: 0,
                    top: y(hi),
                    height: y(lo) - y(hi),
                    child: ColoredBox(color: g.track),
                  ),
                Positioned.fill(
                  bottom: 1,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final b in bars)
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (b.value == null)
                                const G3Dashed(width: 24, height: 36, radius: 5)
                              else ...[
                                if (!labelsBelow && b.label != null) ...[
                                  Text(
                                    b.label!,
                                    style: g.t(
                                      12,
                                      14,
                                      weight:
                                          b.deviation != G3Deviation.none ||
                                              b.today
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: switch (b.deviation) {
                                        G3Deviation.better => g.betterText,
                                        G3Deviation.worse => g.worseText,
                                        G3Deviation.none =>
                                          b.today ? g.ink : g.ink2,
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                ],
                                Container(
                                  width: 24,
                                  height: h - y(b.value!),
                                  decoration: BoxDecoration(
                                    color:
                                        g.mark(b.deviation) ??
                                        (b.today ? g.ink : g.bar),
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(5),
                                      bottom: Radius.circular(2),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (goal != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: y(goal!).roundToDouble(),
                    child: CustomPaint(
                      size: const Size(double.infinity, 1.5),
                      painter: _DashLine(g.muted),
                    ),
                  ),
                if (emptyReason != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 26,
                    child: Text(
                      emptyReason!,
                      textAlign: TextAlign.center,
                      style: g.t(
                        13,
                        16,
                        weight: FontWeight.w500,
                        color: g.ink2,
                      ),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: h,
                  height: 1,
                  child: ColoredBox(color: g.hairline),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final b in bars)
                Expanded(
                  child: Text(
                    b.day,
                    textAlign: TextAlign.center,
                    style: g.t(
                      12,
                      16,
                      weight: b.today ? FontWeight.w700 : FontWeight.w400,
                      color: b.today ? g.ink : g.muted,
                    ),
                  ),
                ),
            ],
          ),
          if (labelsBelow)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Row(
                children: [
                  for (final b in bars)
                    Expanded(
                      child: Text(
                        b.value == null ? '—' : (b.label ?? ''),
                        textAlign: TextAlign.center,
                        style: g.t(
                          12,
                          16,
                          weight: b.today ? FontWeight.w700 : FontWeight.w500,
                          color: b.today ? g.ink : g.ink2,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (footer.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: g.line)),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 8,
                runSpacing: 4,
                children: footer,
              ),
            ),
        ],
      ),
    );
  }
}

class _DashLine extends CustomPainter {
  final Color color;
  const _DashLine(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    for (double x = 0; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, .75), Offset(x + 3, .75), p);
    }
  }

  @override
  bool shouldRepaint(_DashLine old) => old.color != color;
}

/// Footer legend: a band swatch, a deviation mark, or the dashed goal line.
class G3Legend extends StatelessWidget {
  final String text;
  final G3Deviation? mark;
  final bool goal;
  final bool band;
  const G3Legend.band(this.text, {super.key})
    : mark = null,
      goal = false,
      band = true;
  const G3Legend.mark(this.text, G3Deviation this.mark, {super.key})
    : goal = false,
      band = false;
  const G3Legend.goal(this.text, {super.key})
    : mark = null,
      goal = true,
      band = false;
  const G3Legend.text(this.text, {super.key})
    : mark = null,
      goal = false,
      band = false;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final Widget? swatch = band
        ? Container(
            width: 14,
            height: 10,
            decoration: BoxDecoration(
              color: g.track,
              border: Border.all(color: g.band),
              borderRadius: BorderRadius.circular(2),
            ),
          )
        : goal
        ? CustomPaint(size: const Size(16, 1.5), painter: _DashLine(g.muted))
        : mark != null
        ? Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: g.mark(mark!),
              borderRadius: BorderRadius.circular(2),
            ),
          )
        : null;
    final color = switch (mark) {
      G3Deviation.better => g.betterText,
      G3Deviation.worse => g.worseText,
      _ => (band || goal) ? g.ink2 : g.muted,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (swatch != null) ...[swatch, const SizedBox(width: 6)],
        Flexible(
          child: Text(
            text,
            style: g.t(
              12,
              16,
              weight: mark != null ? FontWeight.w500 : FontWeight.w400,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Night card with hypnogram

enum OBStage { wake, rem, light, deep }

class OBStageSegment {
  final OBStage stage;

  /// Minutes from the start of the time in bed.
  final double start, end;
  const OBStageSegment(this.stage, this.start, this.end);
}

enum OBNightState { full, gap, missing }

class OBNightCard extends StatelessWidget {
  final OBNightState state;
  final String? note;
  final String? asleep, subtitle;
  final List<OBStageSegment> segments;
  final double totalMinutes;

  /// Minutes without data; drawn hollow, never filled in.
  final List<(double, double)> gaps;
  final String? gapNote;
  final (String, String, String) axis;

  /// Totals per stage, e.g. (OBStage.deep, "1h08"); null renders "—".
  final List<(OBStage, String?)> totals;
  final String missingText;
  final VoidCallback? onTap;
  const OBNightCard({
    super.key,
    required this.state,
    this.note,
    this.asleep,
    this.subtitle,
    this.segments = const [],
    this.totalMinutes = 1,
    this.gaps = const [],
    this.gapNote,
    this.axis = ('', '', ''),
    this.totals = const [],
    this.missingText = 'Band in der Nacht nicht getragen oder nicht übertragen',
    this.onTap,
  });

  static String stageName(OBStage s) => switch (s) {
    OBStage.deep => 'Tief',
    OBStage.light => 'Leicht',
    OBStage.rem => 'REM',
    OBStage.wake => 'Wach',
  };

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    Color stageColor(OBStage s) => switch (s) {
      OBStage.deep => g.stageDeep,
      OBStage.light => g.stageLight,
      OBStage.rem => g.stageRem,
      OBStage.wake => g.wake,
    };
    if (state == OBNightState.missing || asleep == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: g.raised(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            G3LabelRow('NACHT', note: note ?? 'keine Daten', arrow: false),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: Text(
                    '—',
                    style: g.t(36, 42, weight: FontWeight.w700, color: g.gap),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Keine Nacht erfasst',
                      style: g.t(13, 16, color: g.ink2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            G3Dashed(
              height: 84,
              radius: 6,
              child: Center(
                child: Text(
                  missingText,
                  textAlign: TextAlign.center,
                  style: g.t(12, 16, weight: FontWeight.w500, color: g.ink2),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Semantics(
      button: onTap != null,
      label: 'Nacht: $asleep ${subtitle ?? ''}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: g.raised(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              G3LabelRow('NACHT', note: note),
              const SizedBox(height: 4),
              G3ValueLine(
                asleep!,
                g.t(36, 42, weight: FontWeight.w700, tracking: -.035),
                aside: subtitle,
                asideStyle: g.t(13, 16, color: g.ink2),
                gap: 8,
              ),
              const SizedBox(height: 12),
              OBHypnogram(
                segments: segments,
                totalMinutes: totalMinutes,
                gaps: gaps,
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final t in [axis.$1, axis.$2, axis.$3])
                    Text(t, style: g.t(12, 16, color: g.muted)),
                ],
              ),
              if (gapNote != null) ...[
                const SizedBox(height: 4),
                Text(
                  gapNote!,
                  textAlign: TextAlign.center,
                  style: g.t(12, 16, weight: FontWeight.w500, color: g.ink2),
                ),
              ],
              Container(
                margin: const EdgeInsets.only(top: 14),
                padding: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: g.line)),
                ),
                child: OBStageLegend([
                  for (final (s, v) in totals) (stageName(s), v, stageColor(s)),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OBStageLegend extends StatelessWidget {
  final List<(String, String?, Color)> items;
  const OBStageLegend(this.items, {super.key});
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, (name, value, color)) in items.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(name, style: g.t(12, 16, color: g.muted)),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  value ?? '—',
                  style: g.t(
                    16,
                    20,
                    weight: FontWeight.w700,
                    color: value == null ? g.gap : g.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Four stage lanes (Wach, REM, Leicht, Tief). Gaps stay hollow.
class OBHypnogram extends StatelessWidget {
  final List<OBStageSegment> segments;
  final double totalMinutes;
  final List<(double, double)> gaps;
  const OBHypnogram({
    super.key,
    required this.segments,
    required this.totalMinutes,
    this.gaps = const [],
  });
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return RepaintBoundary(
      child: CustomPaint(
        size: const Size(double.infinity, 84),
        painter: _HypnoPainter(segments, totalMinutes, gaps, g),
      ),
    );
  }
}

class _HypnoPainter extends CustomPainter {
  final List<OBStageSegment> segments;
  final double total;
  final List<(double, double)> gaps;
  final G3 g;
  _HypnoPainter(this.segments, this.total, this.gaps, this.g);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / total;
    const lane = {
      OBStage.wake: 0.0,
      OBStage.rem: 22.0,
      OBStage.light: 44.0,
      OBStage.deep: 66.0,
    };
    final color = {
      OBStage.wake: g.wake,
      OBStage.rem: g.stageRem,
      OBStage.light: g.stageLight,
      OBStage.deep: g.stageDeep,
    };
    for (final y in lane.values) {
      canvas.drawRRect(
        RRect.fromLTRBR(0, y, size.width, y + 18, const Radius.circular(4)),
        Paint()..color = g.hypnoLane,
      );
    }
    for (final s in segments) {
      // Split a stage around any gap; never draw into missing data.
      var pieces = [(s.start, s.end)];
      for (final (g0, g1) in gaps) {
        pieces = [
          for (final (a, b) in pieces) ...[
            if (b <= g0 || a >= g1)
              (a, b)
            else ...[
              if (a < g0) (a, g0),
              if (b > g1) (g1, b),
            ],
          ],
        ];
      }
      for (final (a, b) in pieces) {
        final w = ((b - a) * k - 1).clamp(2.0, double.infinity);
        canvas.drawRRect(
          RRect.fromLTRBR(
            a * k,
            lane[s.stage]!,
            a * k + w,
            lane[s.stage]! + 18,
            const Radius.circular(3),
          ),
          Paint()..color = color[s.stage]!,
        );
      }
    }
    for (final (g0, g1) in gaps) {
      final r = Rect.fromLTRB(g0 * k, 0, g1 * k, 84);
      canvas.drawRect(r, Paint()..color = g.canvas);
      _dashRRect(
        canvas,
        RRect.fromRectAndRadius(r.deflate(.75), const Radius.circular(4)),
        g.gap,
      );
    }
  }

  @override
  bool shouldRepaint(_HypnoPainter old) =>
      old.segments != segments ||
      old.total != total ||
      old.gaps != gaps ||
      old.g.dark != g.dark;
}

void _dashRRect(Canvas canvas, RRect r, Color color, {double width = 1.5}) {
  final paint = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width;
  for (final m in (Path()..addRRect(r)).computeMetrics()) {
    for (double d = 0; d < m.length; d += 6) {
      canvas.drawPath(m.extractPath(d, d + 3), paint);
    }
  }
}

// ---------------------------------------------------------------------------
// Steps

class OBStepsCard extends StatelessWidget {
  /// On-chip counter total; null = no transfer today.
  final int? total;
  final String note;

  /// 24 hourly counts; null = not yet reached (future) — a dot, not a bar.
  final List<int?> hourly;
  final String? goalLabel;
  final VoidCallback? onGoal;
  const OBStepsCard({
    super.key,
    required this.total,
    required this.note,
    this.hourly = const [],
    this.goalLabel = 'Ziel festlegen',
    this.onGoal,
  });
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final hours = List<int?>.generate(
      24,
      (i) => total == null || i >= hourly.length ? null : hourly[i],
    );
    final peak = hours.whereType<int>().fold(1, (a, b) => a > b ? a : b);
    return Semantics(
      label: 'Schritte ${total == null ? 'nicht übertragen' : g3Count(total)}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        decoration: g.raised(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            G3LabelRow('SCHRITTE', note: note, arrow: false),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (total == null) ...[
                  MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.3,
                    child: Text(
                      '—',
                      style: g.t(36, 42, weight: FontWeight.w700, color: g.gap),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'keine Übertragung heute',
                        style: g.t(13, 16, color: g.ink2),
                      ),
                    ),
                  ),
                ] else
                  MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.3,
                    child: Text(
                      g3Count(total),
                      style: g.t(
                        36,
                        42,
                        weight: FontWeight.w700,
                        tracking: -.035,
                      ),
                    ),
                  ),
                if (total != null && goalLabel != null) ...[
                  const SizedBox(width: 8),
                  Flexible(child: OBPillButton(goalLabel!, onPressed: onGoal)),
                ],
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 54,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final v in hours)
                    Expanded(
                      child: Center(
                        heightFactor: 1,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: v == null
                              ? Container(
                                  width: 3,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: g.band,
                                    shape: BoxShape.circle,
                                  ),
                                )
                              : Container(
                                  width: 8,
                                  height: v == 0
                                      ? 2
                                      : (v / peak * 52).roundToDouble().clamp(
                                          3.0,
                                          52.0,
                                        ),
                                  decoration: BoxDecoration(
                                    color: v == 0 ? g.band : g.ink,
                                    borderRadius: BorderRadius.circular(
                                      v == 0 ? 1 : 2,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final t in ['0', '6', '12', '18', '24'])
                  Text(t, style: g.t(12, 16, color: g.muted)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
