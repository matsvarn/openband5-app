// Shared G3 check-in card and copy. Callers own answers, persistence and
// the target day; the question never embeds a relative day such as 'gestern'.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'chrome.dart' show OBPillButton;
import 'g3_theme.dart';

typedef G3CheckInCopy = ({
  String question,
  String? target,
  String low,
  String high,
});

/// A question without a relative day in its title; [target] supplies that day.
G3CheckInCopy g3CheckInCopy(String key, String title) => switch (key) {
  'alcohol_evening' => (
    question: 'Alkohol am Abend?',
    target: 'zu gestern Abend',
    low: '1',
    high: '5',
  ),
  'caffeine_late' => (
    question: 'Koffein nach 14 Uhr?',
    target: 'zu gestern',
    low: '1',
    high: '5',
  ),
  'alcohol_units' => (
    question: 'Wie viel Alkohol?',
    target: 'zu gestern Abend',
    low: '1',
    high: '5',
  ),
  'journal_note' || '' => (
    question: 'Noch etwas zum Tag?',
    target: 'zu gestern',
    low: '1',
    high: '5',
  ),
  'mood' => (
    question: 'Wie ist deine Stimmung?',
    target: null,
    low: 'schlecht',
    high: 'gut',
  ),
  'sleep_quality' => (
    question: 'Wie hast du geschlafen?',
    target: null,
    low: 'schlecht',
    high: 'gut',
  ),
  'energy' => (
    question: 'Wie viel Energie hast du?',
    target: null,
    low: 'wenig',
    high: 'viel',
  ),
  'stress' => (
    question: 'Wie gestresst bist du?',
    target: null,
    low: 'wenig',
    high: 'sehr',
  ),
  _ => (
    question: title.endsWith('?') ? title : '$title?',
    target: null,
    low: '1',
    high: '5',
  ),
};

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
    this.retryLabel = 'Erneut speichern',
    this.inlineLater = false,
    this.footerLabel,
    this.target,
    this.answered,
    this.onChange,
    this.later = false,
    this.laterText = 'Für später gemerkt. Kein Nachteil, wenn du es auslässt.',
    this.onResume,
  });
  final String title;
  final int index, total;
  final Widget answer;
  final VoidCallback onLater;
  final String? error;
  final VoidCallback? onRetry;
  final String retryLabel;
  final bool inlineLater;
  final String? footerLabel;
  final String? target, answered;
  final VoidCallback? onChange, onResume;
  final bool later;
  final String laterText;

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
                      color: i < index - 1
                          ? g.ink
                          : i == index - 1
                          ? g.dark
                                ? g.ink2
                                : g.ink2.withValues(alpha: .45)
                          : g.band,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          if (later) ...[
            Text(laterText, style: g.t(13, 17, color: g.ink2)),
            if (onResume != null)
              Align(
                alignment: Alignment.centerRight,
                child: OBPillButton('Jetzt', onPressed: onResume),
              ),
          ] else ...[
            if (answered != null) ...[
              Row(
                children: [
                  const Icon(LucideIcons.check, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(answered!, style: g.t(14, 18, color: g.ink2)),
                  ),
                  if (onChange != null)
                    OBPillButton('Ändern', onPressed: onChange),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Text(title, style: g.t(19, 24, weight: FontWeight.w700)),
            if (target != null)
              Text(target!, style: g.t(12, 16, color: g.ink2)),
            const SizedBox(height: 12),
            if (inlineLater)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: answer),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: onLater,
                      style: TextButton.styleFrom(
                        foregroundColor: g.ink,
                        minimumSize: const Size(44, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        textStyle: g.t(13, 18, weight: FontWeight.w700),
                      ),
                      child: const Text('Später', maxLines: 1, softWrap: false),
                    ),
                  ],
                ),
              )
            else
              answer,
            if (error != null) ...[
              const SizedBox(height: 12),
              OBInlineError(
                message: error!,
                onRetry: onRetry,
                retryLabel: retryLabel,
              ),
            ],
            if (!inlineLater)
              Row(
                children: [
                  if (footerLabel != null)
                    Expanded(
                      child: Text(
                        footerLabel!,
                        style: g.t(12, 16, color: g.muted),
                      ),
                    )
                  else
                    const Spacer(),
                  OBPillButton('Später', onPressed: onLater),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

class OBInlineError extends StatelessWidget {
  const OBInlineError({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Erneut speichern',
  });
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;
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
          if (onRetry != null) OBPillButton(retryLabel, onPressed: onRetry),
        ],
      ),
    );
  }
}
