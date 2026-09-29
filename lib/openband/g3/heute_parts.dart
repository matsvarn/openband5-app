// Heute-only parts. The typed G3 check-in asks yes/no, 1–5 ratings, counts
// (with an explicit "Keins") and a free note, some about yesterday. The
// shared OBCheckIn Baustein has no place for the answer's day (its progress
// label overflows at 200 % text), so Heute renders every kind in
// [OBCheckInAsk], the same Baustein language with a "zu gestern" line.
// ponytail: the Journal's check-in parts (OBStepper, OBTextField) are not on
// this stack; swap the count and note controls for them at integration.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'chrome.dart' show OBActionSecondary;
import 'g3_theme.dart';

/// Question copy for a check-in key; the day it belongs to is shown apart
/// ("zu gestern"), so questions do not say "gestern" themselves.
String heuteCheckInQuestion(String key, String title) {
  final rating = heuteRatingCopy(key).question;
  return switch (key) {
    'alcohol_evening' => 'Alkohol am Abend?',
    'caffeine_late' => 'Koffein nach 14 Uhr?',
    'alcohol_units' => 'Wie viel Alkohol?',
    'journal_note' => 'Noch etwas zum Tag?',
    _ => rating == key ? '$title?' : rating,
  };
}

/// Question and end labels for a check-in rating key.
({String question, String low, String high}) heuteRatingCopy(
  String key,
) => switch (key) {
  'mood' => (question: 'Wie ist deine Stimmung?', low: 'schlecht', high: 'gut'),
  'sleep_quality' => (
    question: 'Wie hast du geschlafen?',
    low: 'schlecht',
    high: 'gut',
  ),
  'energy' => (
    question: 'Wie viel Energie hast du?',
    low: 'wenig',
    high: 'viel',
  ),
  'stress' => (question: 'Wie gestresst bist du?', low: 'wenig', high: 'sehr'),
  _ => (question: key, low: '1', high: '5'),
};

/// One check-in question in the Heute card: header with progress (and the
/// answer's day when it is not the selected day), the last answer with its
/// change action, the question, an answer control and "Später", which never
/// penalises.
class OBCheckInAsk extends StatelessWidget {
  final String progress, question;

  /// The answer's day when it is not the selected day ("zu gestern").
  final String? target;

  /// The previous answer ("Stimmung: 4 von 5"), with its change action.
  final String? answered;
  final VoidCallback? onChange;
  final Widget answer;
  final VoidCallback? onLater;
  const OBCheckInAsk({
    super.key,
    required this.progress,
    required this.question,
    required this.answer,
    this.target,
    this.answered,
    this.onChange,
    this.onLater,
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
      decoration: g.pressed(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.notebookPen, size: 16, color: g.ink),
              const SizedBox(width: 8),
              Text('CHECK-IN', style: g.caps()),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  progress,
                  textAlign: TextAlign.right,
                  style: g.t(12, 16, weight: FontWeight.w500, color: g.ink2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (answered != null) ...[
            Row(
              children: [
                Icon(LucideIcons.check, size: 16, color: g.ink),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    answered!,
                    style: g.t(14, 18, weight: FontWeight.w500, color: g.ink2),
                  ),
                ),
                if (onChange != null)
                  Semantics(
                    button: true,
                    label: 'Antwort ändern',
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onChange,
                      child: SizedBox(
                        height: 44,
                        child: Center(
                          child: Text(
                            'Ändern',
                            style: g.t(13, 16, weight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
          ],
          Text(
            question,
            style: g.t(19, 24, weight: FontWeight.w700, tracking: -.015),
          ),
          if (target != null) ...[
            const SizedBox(height: 2),
            Text(
              target!,
              style: g.t(13, 17, weight: FontWeight.w500, color: g.ink2),
            ),
          ],
          const SizedBox(height: 10),
          answer,
          Align(
            alignment: Alignment.centerRight,
            child: Semantics(
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
                      style: g.t(
                        14,
                        18,
                        weight: FontWeight.w500,
                        color: g.ink2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Nein / Ja, the keys of the shared OBCheckIn Baustein.
class OBYesNoKeys extends StatelessWidget {
  final VoidCallback? onYes, onNo;
  const OBYesNoKeys({super.key, this.onYes, this.onNo});

  @override
  Widget build(BuildContext context) => Row(
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
    ],
  );
}

/// 1…[max] keys with the end labels under them.
class OBRatingKeys extends StatelessWidget {
  final String question, low, high;
  final int max;
  final ValueChanged<int>? onRate;
  const OBRatingKeys({
    super.key,
    required this.question,
    required this.low,
    required this.high,
    this.max = 5,
    this.onRate,
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var i = 1; i <= max; i++) ...[
              if (i > 1) const SizedBox(width: 6),
              Expanded(
                child: Semantics(
                  label: '$question $i von $max',
                  excludeSemantics: true,
                  button: true,
                  child: OBActionSecondary(
                    '$i',
                    height: 40,
                    expand: true,
                    onPressed: onRate == null ? null : () => onRate!(i),
                  ),
                ),
              ),
            ],
          ],
        ),
        Row(
          children: [
            Text(low, style: g.t(12, 16, color: g.muted)),
            const Spacer(),
            Text(high, style: g.t(12, 16, color: g.muted)),
          ],
        ),
      ],
    );
  }
}

/// A count with an explicit "Keins" (0): minus, the value, plus, and
/// "Speichern" once a value is chosen. Null is unanswered, never zero.
class OBCountAnswer extends StatelessWidget {
  final int? value;
  final int max;
  final String unit;
  final ValueChanged<int> onChanged;
  final VoidCallback? onSave;
  const OBCountAnswer({
    super.key,
    required this.value,
    required this.onChanged,
    this.max = 20,
    this.unit = '',
    this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final v = value;
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 44,
            decoration: g.pressed(radius: 22),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Weniger',
                  onPressed: v == null || v == 0
                      ? null
                      : () => onChanged(v - 1),
                  icon: Icon(LucideIcons.minus, size: 18, color: g.ink),
                ),
                Expanded(
                  child: Text(
                    v == null
                        ? '—'
                        : v == 0
                        ? 'Keins'
                        : unit.isEmpty
                        ? '$v'
                        : '$v $unit',
                    textAlign: TextAlign.center,
                    style: g.t(17, 22, weight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Mehr',
                  onPressed: v == max ? null : () => onChanged((v ?? -1) + 1),
                  icon: Icon(LucideIcons.plus, size: 18, color: g.ink),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        OBActionSecondary(
          'Speichern',
          height: 44,
          onPressed: v == null ? null : onSave,
        ),
      ],
    );
  }
}

/// The free check-in note with its save action.
class OBNoteAnswer extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onSave;
  const OBNoteAnswer({super.key, required this.controller, this.onSave});

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: g.pressed(radius: 14),
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              style: g.t(15, 20),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Notiz',
                hintStyle: g.t(15, 20, color: g.muted),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        ListenableBuilder(
          listenable: controller,
          builder: (_, _) => OBActionSecondary(
            'Speichern',
            height: 44,
            onPressed: controller.text.trim().isEmpty ? null : onSave,
          ),
        ),
      ],
    );
  }
}
