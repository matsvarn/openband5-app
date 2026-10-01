// G3 value Bausteine: lead metric, secondary metric, body row, metric card,
// stat row, day value row, chips and the shared linear scale.
//
// Pure presentation. Every value is nullable and renders as "—" when absent;
// the state (normal/better/worse/plain/building/missing) and any deviation
// come from the caller — no widget decides a baseline or computes a metric.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme.dart' show OBChevron;
import '../alp_tokens.dart' show AlpRadius;
import 'chrome.dart' show OBPanel;
import 'count_copy.dart';
import 'g3_theme.dart';

// ---------------------------------------------------------------------------
// Scale

class G3Tick {
  final double at;
  final String label;
  final bool strong;
  const G3Tick(this.at, this.label, {this.strong = false});
}

/// Labelled linear scale: pressed track, optional grey normal band, median
/// notch, value pointer. Paper places inner labels 8 pt left of their value.
class G3Scale extends StatelessWidget {
  final G3Domain domain;
  final double min, max;
  final double? value, median;
  final (double, double)? band;
  final List<G3Tick> ticks;
  final Color? pointer;
  final double trackHeight, pointerHeight, top, labelSize;
  const G3Scale({
    super.key,
    this.domain = G3Domain.neutral,
    required this.min,
    required this.max,
    this.value,
    this.band,
    this.median,
    this.ticks = const [],
    this.pointer,
    this.trackHeight = 10,
    this.pointerHeight = 24,
    this.top = 7,
    this.labelSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    const inset = 4.5; // half the 5 pt pointer plus its 2 pt halo
    final trackTop = top + 2;
    final labelTop = trackTop + trackHeight + 11;
    final labelHeight = MediaQuery.textScalerOf(
      context,
    ).scale(16).ceilToDouble();
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        double x(double v) =>
            inset + ((v - min) / (max - min)).clamp(0.0, 1.0) * (w - 2 * inset);
        final v = value?.isFinite == true ? value : null;
        return SizedBox(
          height: ticks.isEmpty
              ? top + trackHeight + pointerHeight / 2
              : labelTop + labelHeight,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: inset,
                right: inset,
                top: trackTop,
                height: trackHeight,
                child: DecoratedBox(
                  decoration: g.pressed(
                    radius: trackHeight / 2,
                    color: g.track,
                  ),
                ),
              ),
              if (band case (final lo, final hi))
                if (lo.isFinite && hi.isFinite)
                  Positioned(
                    left: x(lo),
                    width: x(hi) - x(lo),
                    top: trackTop,
                    height: trackHeight,
                    child: ColoredBox(
                      key: const ValueKey('scale-normal-band'),
                      color: g.normalBand(domain),
                    ),
                  ),
              if (median?.isFinite == true)
                Positioned(
                  left: x(median!) - .75,
                  width: 1.5,
                  top: trackTop,
                  height: trackHeight,
                  child: ColoredBox(color: g.canvas),
                ),
              if (v != null)
                Positioned(
                  left: x(v) - 2.5,
                  top: trackTop + trackHeight / 2 - pointerHeight / 2,
                  width: 5,
                  height: pointerHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: pointer ?? g.ink,
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: [BoxShadow(color: g.canvas, spreadRadius: 2)],
                    ),
                  ),
                ),
              for (final t in ticks)
                if (t.at.isFinite)
                  Positioned(
                    left: t.at == min
                        ? inset
                        : (t.at == max ? null : x(t.at) - 8),
                    right: t.at == max ? inset : null,
                    top: labelTop,
                    width: t.at == min || t.at == max
                        ? w / 2
                        : (w - x(t.at) + 8).clamp(0.0, w),
                    child: Text(
                      t.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      textAlign: t.at == max ? TextAlign.right : TextAlign.left,
                      style: g.t(
                        labelSize,
                        16,
                        weight: t.strong ? FontWeight.w500 : FontWeight.w400,
                        color: t.strong ? g.ink2 : g.muted,
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

/// "ERHOLUNG ›" on the left, a muted note on the right.
class G3LabelRow extends StatelessWidget {
  final G3Domain domain;
  final IconData? glyph;
  final String label;
  final String? note;
  final VoidCallback? onTap;
  // Kept until area callers migrate; it can suppress, never create, an arrow.
  final bool arrow;
  const G3LabelRow(
    this.label, {
    super.key,
    this.domain = G3Domain.neutral,
    this.glyph,
    this.note,
    this.onTap,
    this.arrow = true,
  });
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    // Label left, note right; under large text the note drops below.
    return GestureDetector(
      behavior: onTap == null
          ? HitTestBehavior.deferToChild
          : HitTestBehavior.opaque,
      onTap: onTap,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (glyph != null) ...[
                Icon(glyph, size: 16, color: g.domainHue(domain)),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(label, style: g.caps(color: g.domainHue(domain))),
              ),
              if (onTap != null && arrow) ...[
                const SizedBox(width: 4),
                OBChevron(size: 12, color: g.muted),
              ],
            ],
          ),
          if (note != null) Text(note!, style: g.t(13, 16, color: g.muted)),
        ],
      ),
    );
  }
}

/// An absent scalar at the same type size as the value it replaces.
class OBMissingValue extends StatelessWidget {
  final double size;
  final double? lineHeight;
  const OBMissingValue({super.key, required this.size, this.lineHeight});

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Text(
        '—',
        style: g.t(
          size,
          lineHeight ?? size + 4,
          weight: FontWeight.w700,
          color: g.gap,
        ),
      ),
    );
  }
}

/// Big value with a small aside on the same baseline ("7h18 −27 Min.");
/// the aside wraps under Dynamic Type instead of clipping.
class G3ValueLine extends StatelessWidget {
  final String value;
  final TextStyle style;
  final String? aside;
  final TextStyle? asideStyle;
  final double gap;
  const G3ValueLine(
    this.value,
    this.style, {
    super.key,
    this.aside,
    this.asideStyle,
    this.gap = 6,
  });
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Text(value, style: style),
      ),
      if (aside != null) ...[
        SizedBox(width: gap),
        Flexible(child: Text(aside!, style: asideStyle)),
      ],
    ],
  );
}

// ---------------------------------------------------------------------------
// Chip

enum OBChipKind { delta, better, worse, tag, basis }

class OBChip extends StatelessWidget {
  final OBChipKind kind;
  final String text;

  /// Arrow for delta chips: true = up, false = down, null = none.
  final bool? up;

  /// Keeps the neutral chip visible when it sits directly on the page.
  final bool onPage;
  const OBChip(this.kind, this.text, {super.key, this.up, this.onPage = false});

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final (bg, fg) = switch (kind) {
      OBChipKind.delta => (g.chip, g.ink),
      OBChipKind.better => (g.betterTint, g.betterText),
      OBChipKind.worse => (g.worseTint, g.worseText),
      OBChipKind.tag => (g.chip, g.ink2),
      OBChipKind.basis => (Colors.transparent, g.ink2),
    };
    final tag = kind == OBChipKind.tag;
    final h = tag ? 20.0 : 24.0;
    final body = Container(
      height: h,
      padding: EdgeInsets.only(
        left: up == null ? 9 : 7,
        right: up == null ? 9 : 8,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(h / 2),
        border: onPage && !g.dark && kind == OBChipKind.delta
            ? Border.all(color: g.hairline)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (up != null) ...[
            Icon(
              up! ? LucideIcons.arrowUp : LucideIcons.arrowDown,
              size: 12,
              color: fg,
            ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              style: g.t(
                tag ? 11 : 13,
                16,
                weight: tag ? FontWeight.w500 : FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
    return kind == OBChipKind.basis
        ? G3Dashed(radius: h / 2, child: body)
        : body;
  }
}

// ---------------------------------------------------------------------------
// Lead metric

enum OBLeadState { normal, better, worse, plain, building, missing }

/// The one lead number per screen: value → chip and caption → scale.
///
/// [state] is decided by the caller from its stored baseline. A null [value]
/// always renders the missing state, whatever [state] says.
class OBLeadMetric extends StatelessWidget {
  final G3Domain domain;
  final IconData? glyph;
  final String label;
  final String? note;
  final OBLeadState state;
  final double? value;

  /// Presentation for values such as durations and grouped counts.
  final String? valueText;
  final int digits;
  final String? unit;

  /// Delta chip text and direction, e.g. ("6", up: true). Omitted when null.
  final String? delta;
  final bool deltaUp;
  final bool deltaChipOnPage;

  /// Plain state: the dashed basis chip text ("kein Normalbereich").
  final String? basisChip;
  final String? caption;
  final G3Scale? scale;

  /// Building: nights (or values) stored and needed.
  final int? have, need;
  final String unitNoun, unitNounDative, unitNounSingular;
  final String title, reason;

  /// Show a leading + for positive values (relative deviations).
  final bool signed;
  final VoidCallback? onTap;

  /// Detail pages with an (i) key can keep the tap without a second arrow.
  final bool showLabelArrow;

  const OBLeadMetric({
    super.key,
    this.domain = G3Domain.neutral,
    this.glyph,
    required this.label,
    required this.state,
    this.note,
    this.value,
    this.valueText,
    this.digits = 0,
    this.unit,
    this.delta,
    this.deltaUp = true,
    this.deltaChipOnPage = false,
    this.basisChip,
    this.caption,
    this.scale,
    this.have,
    this.need,
    this.unitNoun = 'Nächte',
    this.unitNounDative = 'Nächten',
    this.unitNounSingular = 'Nacht',
    this.title = 'Noch keine Werte',
    this.reason = 'Es fehlt die Nacht. Nichts wird geschätzt.',
    this.signed = false,
    this.onTap,
    this.showLabelArrow = true,
  });

  bool get _missing =>
      state == OBLeadState.missing ||
      (state == OBLeadState.building
          ? (have == null || need == null)
          : value?.isFinite != true);

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final lead = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2);
    Widget refusal(String t, String r) => Row(
      children: [
        const OBMissingValue(size: 64, lineHeight: 72),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t, style: g.t(17, 21, weight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(r, style: g.t(13, 17, color: g.ink2)),
            ],
          ),
        ),
      ],
    );

    final List<Widget> body;
    if (_missing) {
      body = [const SizedBox(height: 2), refusal(title, reason)];
    } else if (state == OBLeadState.building) {
      final left = need! - have!;
      body = [
        const SizedBox(height: 2),
        refusal(title, reason),
        const SizedBox(height: 14),
        Row(
          children: [
            for (var i = 0; i < need!; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: i < have!
                    ? Container(
                        height: 22,
                        decoration: BoxDecoration(
                          color: g.ink,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      )
                    : const G3Dashed(height: 22, radius: 6),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 8,
          children: [
            Text(
              '$have von $need ${g3CountNoun(need!, unitNounSingular, unitNounDative)}',
              style: g.t(12, 16, weight: FontWeight.w700),
            ),
            Text(
              'Basis: noch $left ${g3CountNoun(left, unitNounSingular, unitNoun)}',
              style: g.t(12, 16, weight: FontWeight.w500, color: g.ink2),
            ),
          ],
        ),
      ];
    } else {
      final dev = switch (state) {
        OBLeadState.better => G3Deviation.better,
        OBLeadState.worse => G3Deviation.worse,
        _ => G3Deviation.none,
      };
      final chip = state == OBLeadState.plain
          ? (basisChip == null ? null : OBChip(OBChipKind.basis, basisChip!))
          : (delta == null
                ? null
                : OBChip(
                    switch (dev) {
                      G3Deviation.better => OBChipKind.better,
                      G3Deviation.worse => OBChipKind.worse,
                      G3Deviation.none => OBChipKind.delta,
                    },
                    delta!,
                    up: deltaUp,
                    onPage: deltaChipOnPage,
                  ));
      final s = scale;
      body = [
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text:
                        valueText ??
                        g3Number(value, digits: digits, signed: signed),
                    style: g.lead(decimal: digits > 0),
                  ),
                  if (unit != null)
                    TextSpan(
                      text: ' $unit',
                      style: g.t(
                        17,
                        20,
                        weight: FontWeight.w500,
                        color: g.muted,
                      ),
                    ),
                ],
              ),
              textScaler: lead,
              maxLines: 1,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ?chip,
                    if (chip != null && caption != null)
                      const SizedBox(height: 6),
                    if (caption != null)
                      Text(caption!, style: g.t(13, 16, color: g.ink2)),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (s != null) ...[
          const SizedBox(height: 10),
          G3Scale(
            domain: domain,
            min: s.min,
            max: s.max,
            value: value,
            band: state == OBLeadState.plain ? null : s.band,
            median: state == OBLeadState.plain ? null : s.median,
            ticks: s.ticks,
            pointer: g.mark(dev),
          ),
        ],
      ];
    }
    return Semantics(
      container: true,
      button: onTap != null,
      label: onTap == null ? null : '$label öffnen',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            G3LabelRow(
              label,
              domain: domain,
              glyph: glyph,
              note: note,
              onTap: onTap,
              arrow: showLabelArrow,
            ),
            ...body,
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Secondary metric (Schlaf, Belastung) with a short fill scale

class OBSecondaryMetric extends StatelessWidget {
  final G3Domain domain;
  final IconData? glyph;
  final String label;

  /// Already formatted value ("7h18", "9,4"); null renders "—".
  final String? value;
  final String? aside;

  /// Fill share 0…1 of the scale; null draws no fill (unknown amount).
  final double? fill;

  /// Goal marker share 0…1 with its label, e.g. (0.775, "Ziel 7h45").
  final (double, String)? goal;
  final String start, end;
  final VoidCallback? onTap;
  const OBSecondaryMetric({
    super.key,
    this.domain = G3Domain.neutral,
    this.glyph,
    required this.label,
    required this.value,
    this.aside,
    this.fill,
    this.goal,
    required this.start,
    required this.end,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final v = value;
    return Semantics(
      container: true,
      button: onTap != null,
      label: onTap == null ? null : '$label öffnen',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            G3LabelRow(label, domain: domain, glyph: glyph, onTap: onTap),
            const SizedBox(height: 2),
            G3ValueLine(
              v ?? '—',
              g.t(
                36,
                42,
                weight: FontWeight.w700,
                color: v == null ? g.gap : g.ink,
                tracking: -.035,
              ),
              aside: aside,
              asideStyle: g.t(13, 16, weight: FontWeight.w500, color: g.muted),
            ),
            const SizedBox(height: 6),
            LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth;
                final scaler = MediaQuery.textScalerOf(context);
                final mutedStyle = g.t(12, 16, color: g.muted);
                final goalStyle = g.t(
                  12,
                  16,
                  weight: FontWeight.w500,
                  color: g.ink2,
                );
                double labelWidth(String text, TextStyle style) {
                  final painter = TextPainter(
                    text: TextSpan(text: text, style: style),
                    textDirection: Directionality.of(context),
                    textScaler: scaler,
                    maxLines: 1,
                  )..layout();
                  return painter.width;
                }

                final startWidth = labelWidth(
                  start,
                  mutedStyle,
                ).clamp(0.0, w / 2);
                final endWidth = labelWidth(end, mutedStyle).clamp(0.0, w / 2);
                // The goal label keeps [gap] to both end labels: it shifts
                // away from them and shortens; with no room left it is
                // omitted, never drawn overlapping.
                const gap = 8.0;
                final goalAt = goal?.$1;
                final goalText = goal?.$2;
                final goalSpace = (w - startWidth - endWidth - 2 * gap).clamp(
                  0.0,
                  w,
                );
                final goalWidth = goalText == null
                    ? 0.0
                    : labelWidth(goalText, goalStyle).clamp(0.0, goalSpace);
                final goalMinLeft = startWidth + gap;
                final goalMaxLeft = w - endWidth - gap - goalWidth;
                final showGoal =
                    goalText != null &&
                    goalAt?.isFinite == true &&
                    goalWidth > 0 &&
                    goalMinLeft <= goalMaxLeft;
                final goalLeft = showGoal
                    ? (w * goalAt!.clamp(0.0, 1.0) - goalWidth / 2).clamp(
                        goalMinLeft,
                        goalMaxLeft,
                      )
                    : 0.0;
                return Column(
                  children: [
                    SizedBox(
                      height: 14,
                      child: Stack(
                        children: [
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 4,
                            height: 6,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: g.track,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                          if (v != null && fill?.isFinite == true)
                            Positioned(
                              left: 0,
                              top: 4,
                              height: 6,
                              width: w * fill!.clamp(0.0, 1.0),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: g.domainHue(domain),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          if (goal case (final at, _))
                            if (at.isFinite)
                              Positioned(
                                left: w * at.clamp(0.0, 1.0) - 1,
                                top: 0,
                                width: 2,
                                height: 14,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: g.muted,
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                              ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      height: scaler.scale(16).ceilToDouble() + 2,
                      child: Stack(
                        clipBehavior: Clip.hardEdge,
                        children: [
                          Positioned(
                            left: 0,
                            width: startWidth,
                            child: Text(
                              start,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: mutedStyle,
                            ),
                          ),
                          if (showGoal)
                            Positioned(
                              left: goalLeft,
                              width: goalWidth,
                              child: Text(
                                goalText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: goalStyle,
                              ),
                            ),
                          Positioned(
                            right: 0,
                            width: endWidth,
                            child: Text(
                              end,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: mutedStyle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body row (Körper)

enum OBBodyState { range, plain, building, missing, deviation }

/// One body value with its picture. [deviation] is relative (skin
/// temperature): unitless, on kühler · normal · wärmer, never coloured.
class OBBodyRow extends StatelessWidget {
  final G3Domain domain;
  final OBBodyState state;
  final String name;
  final String? value;
  final String? unit;
  final double? at;
  final double min, max;
  final (double, double)? band;
  final String? minLabel, maxLabel;

  /// Building / missing reason under the empty track.
  final String note;
  final bool last;
  final VoidCallback? onTap;
  const OBBodyRow({
    super.key,
    this.domain = G3Domain.neutral,
    required this.state,
    required this.name,
    this.value,
    this.unit,
    this.at,
    this.min = 0,
    this.max = 1,
    this.band,
    this.minLabel,
    this.maxLabel,
    this.note = 'nicht erfasst',
    this.last = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final missing = state == OBBodyState.missing || value == null;
    const w = 128.0;
    final Widget picture;
    if (missing || state == OBBodyState.building) {
      picture = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const G3Dashed(height: 8, width: w, radius: 4),
          const SizedBox(height: 5),
          Text(
            missing ? 'nicht erfasst' : note,
            style: g.t(11, 13, weight: FontWeight.w500, color: g.ink2),
          ),
        ],
      );
    } else if (state == OBBodyState.deviation) {
      double x(double v) => ((v - min) / (max - min)).clamp(0.0, 1.0) * w;
      picture = SizedBox(
        width: w,
        height: 36,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 6,
              height: 8,
              child: DecoratedBox(
                decoration: g.pressed(radius: 4, color: g.track),
              ),
            ),
            Positioned(
              left: w / 2 - 1,
              top: 3,
              width: 2,
              height: 14,
              child: ColoredBox(color: g.muted),
            ),
            if (at?.isFinite == true)
              Positioned(
                left: x(at!) - 2,
                top: 1,
                width: 4,
                height: 18,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: g.ink,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [BoxShadow(color: g.canvas, spreadRadius: 2)],
                  ),
                ),
              ),
            for (final (l, r, t) in [
              (0.0, null, 'kühler'),
              (w / 2 - 17, null, 'normal'),
              (null, 0.0, 'wärmer'),
            ])
              Positioned(
                left: l,
                right: r,
                top: 22,
                child: Text(t, style: g.t(11, 14, color: g.muted)),
              ),
          ],
        ),
      );
    } else {
      picture = SizedBox(
        width: w,
        child: G3Scale(
          domain: domain,
          min: min,
          max: max,
          value: at?.isFinite == true ? at : null,
          band: state == OBBodyState.range ? band : null,
          trackHeight: 8,
          pointerHeight: 18,
          top: 6,
          ticks: [
            if (state == OBBodyState.range && band != null) ...[
              G3Tick(band!.$1, minLabel ?? ''),
              G3Tick(band!.$2, maxLabel ?? ''),
            ] else ...[
              G3Tick(min, minLabel ?? ''),
              G3Tick(max, maxLabel ?? ''),
            ],
          ],
        ),
      );
    }
    return Semantics(
      button: onTap != null,
      label: '$name ${missing ? 'nicht erfasst' : '$value ${unit ?? ''}'}'
          .trim(),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: last ? null : Border(bottom: BorderSide(color: g.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: g.t(
                        13,
                        16,
                        weight: FontWeight.w500,
                        color: g.ink2,
                      ),
                    ),
                    const SizedBox(height: 1),
                    MediaQuery.withClampedTextScaling(
                      maxScaleFactor: 1.3,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: missing ? '—' : value,
                              style: g.t(
                                22,
                                27,
                                weight: FontWeight.w700,
                                color: missing ? g.gap : g.ink,
                                tracking: -.02,
                              ),
                            ),
                            if (!missing && unit != null)
                              TextSpan(
                                text: ' $unit',
                                style: g.t(13, 16, color: g.muted),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              picture,
              if (onTap != null) ...[
                const SizedBox(width: 12),
                OBChevron(size: 14, color: g.gap),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stat row and day value row (Verlauf)

class OBStatRow extends StatelessWidget {
  /// (label, value, unit); a null value renders "—".
  final List<(String, String?, String?)> items;
  final G3Domain domain;
  final bool? embedded;
  const OBStatRow(
    this.items, {
    super.key,
    this.domain = G3Domain.neutral,
    this.embedded,
  });
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final inCard =
        embedded ?? context.findAncestorWidgetOfExactType<OBPanel>() != null;
    return Container(
      padding: inCard ? EdgeInsets.zero : kG3CardPadding,
      decoration: inCard
          ? null
          : BoxDecoration(
              color: g.canvas,
              borderRadius: BorderRadius.circular(AlpRadius.card),
            ),
      child: LayoutBuilder(
        builder: (context, c) {
          // CSS flex:1 with padding: equal share of the space left after padding.
          final cell = (c.maxWidth - 14 * (items.length - 1)) / items.length;
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, (label, value, unit)) in items.indexed)
                  SizedBox(
                    width: cell + (i == 0 ? 0 : 14),
                    child: Container(
                      padding: EdgeInsets.only(left: i == 0 ? 0 : 14),
                      decoration: i == 0
                          ? null
                          : BoxDecoration(
                              border: Border(left: BorderSide(color: g.line)),
                            ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label.toUpperCase(),
                            style: g.t(
                              11,
                              14,
                              weight: FontWeight.w700,
                              color: g.muted,
                              tracking: .08,
                            ),
                          ),
                          const SizedBox(height: 2),
                          MediaQuery.withClampedTextScaling(
                            maxScaleFactor: 1.3,
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: value ?? '—',
                                    style: g.t(
                                      22,
                                      27,
                                      weight: FontWeight.w700,
                                      color: value == null ? g.gap : g.ink,
                                      tracking: -.02,
                                    ),
                                  ),
                                  if (value != null && unit != null)
                                    TextSpan(
                                      text: ' $unit',
                                      style: g.t(12, 16, color: g.muted),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class OBDayValueRow extends StatelessWidget {
  final G3Domain domain;
  final String date;
  final String? note, value, unit;
  final double? share;
  final bool last, showBar;
  final VoidCallback? onTap;
  final G3Deviation? deviation;
  const OBDayValueRow({
    super.key,
    required this.date,
    required this.value,
    this.domain = G3Domain.neutral,
    this.note,
    this.unit,
    this.share,
    this.last = false,
    this.showBar = true,
    this.onTap,
    this.deviation,
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final gap = value == null;
    final barMissing = gap || share?.isFinite != true;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: g.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(date, style: g.t(15, 19, weight: FontWeight.w700)),
                  if (gap || note != null)
                    Text(
                      note ?? 'keine Daten',
                      style: g.t(12, 16, color: g.muted),
                    ),
                ],
              ),
            ),
            if (showBar) ...[
              const SizedBox(width: 12),
              if (barMissing)
                const G3Dashed(width: 110, height: 8, radius: 4)
              else
                Container(
                  width: 110,
                  height: 8,
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: g.track,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: FractionallySizedBox(
                    widthFactor: share!.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: g.domainBar(domain),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
            ],
            const SizedBox(width: 12),
            SizedBox(
              width: 64,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: value ?? '—',
                      style: g.t(
                        17,
                        21,
                        weight: FontWeight.w700,
                        color: gap
                            ? g.gap
                            : deviation == G3Deviation.worse
                            ? g.worseText
                            : deviation == G3Deviation.better
                            ? g.betterText
                            : g.ink,
                      ),
                    ),
                    if (!gap && unit != null)
                      TextSpan(
                        text: ' $unit',
                        style: g.t(12, 16, color: g.muted),
                      ),
                  ],
                ),
                textAlign: TextAlign.right,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 12),
              OBChevron(size: 12, color: g.muted),
            ],
          ],
        ),
      ),
    );
  }
}
