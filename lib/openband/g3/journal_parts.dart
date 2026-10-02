// G3 Journal presentation. The caller owns persistence and decides which
// questions and comparisons are supported by the repository.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'count_copy.dart';
export 'check_in.dart' show OBCheckIn, OBInlineError;
import 'band_parts.dart' show OBToggle;
import 'chrome.dart' show OBIconButton, OBPillButton;
import 'g3_theme.dart';
import 'g3_format.dart';
import 'metrics.dart' show G3LabelRow, OBChip, OBChipKind, OBMissingValue;

class OBCheckInDone extends StatelessWidget {
  const OBCheckInDone({
    super.key,
    required this.total,
    required this.answers,
    this.title = 'Für heute erledigt',
  });
  final int total;
  final List<String> answers;
  final String title;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: g.raised(radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.notebookPen, size: 20, color: g.ink),
              const SizedBox(width: 8),
              Expanded(child: Text('CHECK-IN', style: g.caps(size: 14))),
              Text('$total von $total', style: g.t(13, 17, color: g.ink2)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < total; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: g.ink,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(LucideIcons.check, size: 22, color: g.ink),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: g.t(21, 26, weight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final answer in answers) OBChip(OBChipKind.tag, answer),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Du kannst jede Antwort jederzeit ändern.',
            style: g.t(14, 19, color: g.ink2),
          ),
        ],
      ),
    );
  }
}

class OBAnswerKey extends StatelessWidget {
  const OBAnswerKey({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.rating = false,
  });
  final String label;
  final VoidCallback? onTap;
  final bool selected;
  final bool rating;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(rating ? 16 : 24),
        child: Container(
          constraints: BoxConstraints(minHeight: rating ? 58 : 44),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? g.ink : g.canvas,
            borderRadius: BorderRadius.circular(rating ? 16 : 24),
          ),
          child: Text(
            label,
            style: g.t(
              rating ? 20 : 16,
              20,
              weight: FontWeight.w700,
              color: selected ? g.onInk : g.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class OBStepper extends StatelessWidget {
  const OBStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.max = 20,
    this.unit,
  });
  final int? value;
  final int max;
  final String? unit;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Container(
      decoration: g.pressed(radius: 24),
      child: Row(
        children: [
          OBIconButton(
            icon: LucideIcons.minus,
            label: 'Weniger',
            onTap: value == null || value == 0
                ? null
                : () => onChanged(value! - 1),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (value == null)
                  const OBMissingValue(size: 24, lineHeight: 28)
                else
                  Text(
                    value == 0 ? 'Keins' : g3Count(value),
                    style: g.t(24, 28, weight: FontWeight.w700),
                  ),
                if (value != null && value! > 0 && unit != null) ...[
                  const SizedBox(width: 5),
                  Text(unit!, style: g.t(13, 18, color: g.ink2)),
                ],
              ],
            ),
          ),
          OBIconButton(
            icon: LucideIcons.plus,
            label: 'Mehr',
            onTap: value == max ? null : () => onChanged((value ?? 0) + 1),
          ),
        ],
      ),
    );
  }
}

class OBJournalEntryRow extends StatelessWidget {
  const OBJournalEntryRow({
    super.key,
    required this.title,
    required this.value,
    required this.onEdit,
    this.subtitle,
    this.icon,
    this.last = false,
  });
  final String title, value;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback onEdit;
  final bool last;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Container(
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: g.line)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: g.chip,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              icon ?? LucideIcons.notebookPen,
              size: 18,
              color: g.ink,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: g.t(15, 19, weight: FontWeight.w700)),
                if (subtitle != null)
                  Text(subtitle!, style: g.t(12, 16, color: g.muted)),
              ],
            ),
          ),
          Text(value, style: g.t(17, 21, weight: FontWeight.w700)),
          OBIconButton(
            icon: LucideIcons.pencil,
            label: '$title ändern',
            small: true,
            plain: true,
            onTap: onEdit,
          ),
        ],
      ),
    );
  }
}

class OBJournalDayRow extends StatelessWidget {
  const OBJournalDayRow({
    super.key,
    required this.title,
    required this.summary,
    required this.onTap,
    this.chips = const [],
    this.count,
  });
  final String title;
  final String? summary;
  final VoidCallback onTap;
  final List<String> chips;
  final String? count;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: g.hairline)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: g.t(
                            15,
                            19,
                            weight: FontWeight.w700,
                            color: chips.isEmpty ? g.muted : g.ink,
                          ),
                        ),
                      ),
                      if (count != null)
                        Text(count!, style: g.t(12, 16, color: g.muted)),
                    ],
                  ),
                  if (summary != null || chips.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    if (chips.isEmpty)
                      Text(summary!, style: g.t(13, 17, color: g.muted))
                    else
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: [
                          for (final chip in chips)
                            OBChip(OBChipKind.tag, chip),
                        ],
                      ),
                  ],
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, color: g.gap, size: 14),
          ],
        ),
      ),
    );
  }
}

class OBPatternProgress extends StatelessWidget {
  const OBPatternProgress({
    super.key,
    required this.have,
    required this.need,
    this.height = 22,
  });
  final int have, need;
  final double height;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Row(
      children: [
        for (var i = 0; i < need; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == need - 1 ? 0 : 6),
              child: Container(
                height: height,
                decoration: BoxDecoration(
                  color: i < have ? g.ink : g.page,
                  border: i < have ? null : Border.all(color: g.gap),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class OBPatternGateRow extends StatelessWidget {
  const OBPatternGateRow({
    super.key,
    required this.label,
    required this.count,
    required this.minimum,
  });
  final String label;
  final int? count;
  final int? minimum;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 360;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: narrow ? 90 : 145,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: g.t(14, 18, weight: FontWeight.w700)),
                Text(
                  label == 'Ja'
                      ? 'Koffein nach 14 Uhr'
                      : 'kein Koffein nach 14 Uhr',
                  style: g.t(12, 16, color: g.muted),
                ),
              ],
            ),
          ),
          SizedBox(
            width: narrow ? 66 : 96,
            child: count == null || minimum == null
                ? const OBMissingValue(size: 14, lineHeight: 18)
                : OBPatternProgress(
                    have: count!.clamp(0, minimum!),
                    need: minimum!,
                    height: 14,
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: count == null || minimum == null
                ? const Align(
                    alignment: Alignment.centerRight,
                    child: OBMissingValue(size: 13, lineHeight: 17),
                  )
                : Text(
                    count! < minimum!
                        ? '$count von $minimum'
                        : '$count · genug',
                    textAlign: TextAlign.end,
                    style: g.t(13, 17, color: g.ink2),
                  ),
          ),
        ],
      ),
    );
  }
}

class OBPatternCard extends StatelessWidget {
  const OBPatternCard({
    super.key,
    required this.title,
    required this.detail,
    required this.have,
    required this.need,
    this.footer,
    this.showFooter = true,
    this.loading = false,
    this.onRetry,
    this.partial = false,
    this.onOpen,
    this.relation,
  });
  final String title, detail;
  final Widget? relation;
  final int? have;
  final int? need;
  final String? footer;
  final bool loading, partial, showFooter;
  final VoidCallback? onRetry;
  final VoidCallback? onOpen;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final awaiting = have != null && need != null && have! < need!;
    return InkWell(
      onTap: onOpen,
      child: Container(
        padding: kG3CardPadding,
        decoration: g.raised(radius: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            G3LabelRow(
              'MUSTER',
              domain: G3Domain.neutral,
              onTap: onOpen,
              note: relation != null && !partial
                  ? null
                  : loading
                  ? 'wird geladen'
                  : onRetry != null
                  ? 'nicht verfügbar'
                  : partial
                  ? 'Teilweise auswertbar'
                  : awaiting
                  ? 'noch kein Vergleich'
                  : title,
            ),
            SizedBox(height: relation == null ? 12 : 8),
            if (loading)
              Row(
                children: [
                  SizedBox(
                    width: 18,
                    child: Text('…', style: g.t(18, 19, color: g.ink2)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Vergleich wird geladen.',
                      style: g.t(14, 19, color: g.ink2),
                    ),
                  ),
                ],
              )
            else if (onRetry != null)
              Row(
                children: [
                  Icon(LucideIcons.triangleAlert, size: 18, color: g.ink),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(detail, style: g.t(14, 19, color: g.ink2)),
                  ),
                  OBPillButton('Erneut', onPressed: onRetry),
                ],
              )
            else if (relation != null) ...[
              relation!,
              const SizedBox(height: 4),
              Text(
                '$title · $have von $need Paaren',
                style: g.t(14, 18, weight: FontWeight.w500),
              ),
            ] else if (awaiting)
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$have', style: g.t(56, 56, weight: FontWeight.w700)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'von $need Tag-Nacht-${g3CountNoun(need!, 'Paar', 'Paaren')}',
                            style: g.t(15, 19, weight: FontWeight.w700),
                          ),
                          Text(detail, style: g.t(13, 17, color: g.ink2)),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            else ...[
              if (have == null)
                const OBMissingValue(size: 23, lineHeight: 27)
              else
                Text(title, style: g.t(23, 27, weight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(detail, style: g.t(14, 19, color: g.ink2)),
            ],
            if (relation == null &&
                !loading &&
                onRetry == null &&
                have != null &&
                need != null) ...[
              const SizedBox(height: 16),
              OBPatternProgress(have: have!.clamp(0, need!), need: need!),
            ],
            if (showFooter && !loading && onRetry == null) ...[
              SizedBox(height: relation == null ? 10 : 2),
              Text(
                footer ??
                    (have == null || need == null
                        ? '—'
                        : '$have von $need ${g3CountNoun(need!, 'Paar', 'Paaren')} · noch ${(need! - have!).clamp(0, need!)}'),
                style: g.t(13, 17, color: g.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class OBQuestionRow extends StatelessWidget {
  const OBQuestionRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.active,
    required this.onChanged,
    this.icon = LucideIcons.notebookPen,
  });
  final String title, subtitle;
  final bool active;
  final ValueChanged<bool>? onChanged;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: g.hairline)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: g.track,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: g.ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: g.t(15, 19, weight: FontWeight.w700)),
                Text(subtitle, style: g.t(12, 16, color: g.muted)),
              ],
            ),
          ),
          if (onChanged != null)
            OBSwitch(value: active, onChanged: onChanged!, label: title),
        ],
      ),
    );
  }
}

class OBTextField extends StatelessWidget {
  const OBTextField({
    super.key,
    required this.controller,
    required this.label,
    this.maxLines = 1,
  });
  final TextEditingController controller;
  final String label;
  final int maxLines;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Semantics(
      textField: true,
      label: label,
      child: Container(
        constraints: BoxConstraints(minHeight: maxLines > 1 ? 92 : 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: g.raised(radius: 14),
        child: TextField(
          controller: controller,
          maxLines: maxLines,
          style: g.t(15, 20),
          decoration: InputDecoration.collapsed(hintText: label),
        ),
      ),
    );
  }
}

/// A neutral distribution view. Only pass observed values; no interpolation.
class OBPatternDotPlot extends StatelessWidget {
  const OBPatternDotPlot({
    super.key,
    required this.withAnswer,
    required this.withoutAnswer,
    required this.min,
    required this.max,
  });
  final List<double> withAnswer, withoutAnswer;
  final double min, max;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Semantics(
      label:
          '${withAnswer.length} ${g3CountNoun(withAnswer.length, 'beobachtete Nacht', 'beobachtete Nächte')} mit Ja und ${withoutAnswer.length} ${g3CountNoun(withoutAnswer.length, 'beobachtete Nacht', 'beobachtete Nächte')} mit Nein',
      child: RepaintBoundary(
        child: SizedBox(
          height: 112,
          child: CustomPaint(
            painter: _PatternDots(g, withAnswer, withoutAnswer, min, max),
          ),
        ),
      ),
    );
  }
}

class _PatternDots extends CustomPainter {
  const _PatternDots(this.g, this.yes, this.no, this.min, this.max);
  final G3 g;
  final List<double> yes, no;
  final double min, max;
  double _x(double v, double w) => ((v - min) / (max - min)).clamp(0, 1) * w;
  @override
  void paint(Canvas canvas, Size size) {
    if (max <= min) return;
    final w = size.width - 12;
    final paint = Paint()..color = g.ink;
    for (final (row, values) in [(0, yes), (1, no)]) {
      for (var i = 0; i < values.length; i++) {
        final v = values[i];
        if (!v.isFinite) continue;
        canvas.drawCircle(
          Offset(6 + _x(v, w), row * 52 + 14 + (i % 5) * 7),
          2.5,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PatternDots old) =>
      old.g.dark != g.dark ||
      old.yes != yes ||
      old.no != no ||
      old.min != min ||
      old.max != max;
}

class OBSwitch extends StatelessWidget {
  const OBSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) =>
      OBToggle(value: value, onChanged: onChanged, label: label);
}
