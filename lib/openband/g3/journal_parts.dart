// G3 Journal presentation. The caller owns persistence and decides which
// questions and comparisons are supported by the repository.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'g3_theme.dart';

class OBCheckIn extends StatelessWidget {
  const OBCheckIn({
    super.key,
    required this.title,
    required this.index,
    required this.total,
    required this.answer,
    required this.onLater,
    this.error,
    this.onRetry,
  });
  final String title;
  final int index, total;
  final Widget answer;
  final VoidCallback onLater;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: g.pressed(radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.notebookPen, size: 20, color: g.ink),
              const SizedBox(width: 8),
              Expanded(child: Text('CHECK-IN', style: g.caps(size: 14))),
              Text('$index von $total', style: g.t(13, 17, color: g.ink2)),
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
                      color: i < index ? g.ink : g.track,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Text(title, style: g.t(21, 25, weight: FontWeight.w700)),
          const SizedBox(height: 12),
          answer,
          if (error != null) ...[
            const SizedBox(height: 12),
            OBInlineError(message: error!, onRetry: onRetry),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onLater,
              child: Text(
                'Später',
                style: g.t(14, 18, weight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OBCheckInDone extends StatelessWidget {
  const OBCheckInDone({super.key, required this.total});
  final int total;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: g.raised(radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CHECK-IN', style: g.caps()),
          const SizedBox(height: 12),
          Text(
            'Für heute erledigt',
            style: g.t(21, 26, weight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '$total von $total Antworten gespeichert. Du kannst jede Antwort ändern.',
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
    this.icon,
  });
  final String label;
  final VoidCallback? onTap;
  final bool selected;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? g.ink : g.canvas,
            borderRadius: BorderRadius.circular(24),
          ),
          child: icon == null
              ? Text(
                  label,
                  style: g.t(
                    16,
                    20,
                    weight: FontWeight.w700,
                    color: selected ? g.onInk : g.ink,
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 22, color: selected ? g.onInk : g.ink),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: g.t(
                        12,
                        15,
                        weight: FontWeight.w700,
                        color: selected ? g.onInk : g.ink,
                      ),
                    ),
                  ],
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
  });
  final int? value;
  final int max;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Row(
      children: [
        IconButton(
          tooltip: 'Weniger',
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          onPressed: value == null || value == 0
              ? null
              : () => onChanged(value! - 1),
          icon: const Icon(LucideIcons.minus),
        ),
        Expanded(
          child: Text(
            value == null
                ? '—'
                : value == 0
                ? 'Keins'
                : '$value',
            textAlign: TextAlign.center,
            style: g.t(24, 28, weight: FontWeight.w700),
          ),
        ),
        IconButton(
          tooltip: 'Mehr',
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          onPressed: value == max ? null : () => onChanged((value ?? 0) + 1),
          icon: const Icon(LucideIcons.plus),
        ),
      ],
    );
  }
}

class OBInlineError extends StatelessWidget {
  const OBInlineError({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: g.pressed(),
      child: Row(
        children: [
          Icon(LucideIcons.triangleAlert, size: 18, color: g.ink),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: g.t(13, 17))),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: const Text('Erneut speichern'),
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
  });
  final String title, value;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
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
          Text(value, style: g.t(15, 19, weight: FontWeight.w700)),
          IconButton(
            tooltip: '$title ändern',
            onPressed: onEdit,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: Icon(LucideIcons.pencil, size: 18, color: g.muted),
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
  });
  final String title, summary;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
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
                  Text(title, style: g.t(15, 19, weight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(summary, style: g.t(12, 16, color: g.muted)),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, color: g.muted, size: 18),
          ],
        ),
      ),
    );
  }
}

class OBPatternProgress extends StatelessWidget {
  const OBPatternProgress({super.key, required this.have, required this.need});
  final int have, need;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: [
        for (var i = 0; i < need; i++)
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: i < have ? g.ink : g.track,
              borderRadius: BorderRadius.circular(3),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(label, style: g.t(14, 18, weight: FontWeight.w700)),
          ),
          Expanded(
            child: count == null || minimum == null
                ? Text('—', style: g.t(14, 18, color: g.muted))
                : OBPatternProgress(
                    have: count!.clamp(0, minimum!),
                    need: minimum!,
                  ),
          ),
          const SizedBox(width: 8),
          Text(
            count == null || minimum == null
                ? '—'
                : count! < minimum!
                ? '$count von $minimum nötig'
                : '$count vorhanden',
            style: g.t(13, 17, color: g.ink2),
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
  });
  final String title, detail;
  final int? have;
  final int need;
  final String? footer;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: g.raised(radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('ERSTER VERGLEICH', style: g.caps()),
          const SizedBox(height: 18),
          Text(title, style: g.t(23, 27, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(detail, style: g.t(14, 19, color: g.ink2)),
          const SizedBox(height: 20),
          if (have != null)
            OBPatternProgress(have: have!.clamp(0, need), need: need),
          const SizedBox(height: 12),
          Text(
            footer ??
                (have == null
                    ? '—'
                    : '$have von $need Tagen · noch ${(need - have!).clamp(0, need)}'),
            style: g.t(13, 17, weight: FontWeight.w700),
          ),
        ],
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
  });
  final String title, subtitle;
  final bool active;
  final ValueChanged<bool>? onChanged;
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
            Switch.adaptive(value: active, onChanged: onChanged),
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
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: g.canvas,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: g.hairline),
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
    this.bandLow,
    this.bandHigh,
  });
  final List<double> withAnswer, withoutAnswer;
  final double min, max;
  final double? bandLow, bandHigh;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Semantics(
      label:
          '${withAnswer.length} und ${withoutAnswer.length} beobachtete Nächte',
      child: RepaintBoundary(
        child: SizedBox(
          height: 112,
          child: CustomPaint(
            painter: _PatternDots(
              g,
              withAnswer,
              withoutAnswer,
              min,
              max,
              bandLow,
              bandHigh,
            ),
          ),
        ),
      ),
    );
  }
}

class _PatternDots extends CustomPainter {
  const _PatternDots(
    this.g,
    this.yes,
    this.no,
    this.min,
    this.max,
    this.low,
    this.high,
  );
  final G3 g;
  final List<double> yes, no;
  final double min, max;
  final double? low, high;
  double _x(double v, double w) => ((v - min) / (max - min)).clamp(0, 1) * w;
  @override
  void paint(Canvas canvas, Size size) {
    if (max <= min) return;
    final w = size.width - 12;
    if (low != null && high != null && high! > low!) {
      canvas.drawRect(
        Rect.fromLTWH(
          6 + _x(low!, w),
          0,
          _x(high!, w) - _x(low!, w),
          size.height,
        ),
        Paint()..color = g.band,
      );
    }
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
      old.max != max ||
      old.low != low ||
      old.high != high;
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
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: Switch.adaptive(value: value, onChanged: onChanged),
  );
}
