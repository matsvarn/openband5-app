// Wellness/gallery journal controls. The date-bound editor now lives in
// `lib/openband/journal_editor.dart`.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/journal_fields.dart';
import '../../l10n/app_localizations.dart';
import '../ui2.dart';

/// The 1–5 self-report. Five faces, not ten: a ten-point self-report is not
/// ten distinguishable states, and the extra resolution is noise a rank
/// correlation then has to see through.
class MoodPicker extends StatelessWidget {
  const MoodPicker({super.key, this.value, required this.onChanged});

  final int? value;

  /// Null means "clear it". A mis-tap used to be permanent: every face wrote a
  /// mood and none of them could write absence back, so the only way out of a
  /// mood you never meant to log was to pick a different wrong one. Tapping
  /// the selected face again takes it back to not-answered — the same rule the
  /// [FieldStepper] uses when it steps down off zero.
  final ValueChanged<int?> onChanged;

  static const _faces = [
    LucideIcons.frown,
    LucideIcons.annoyed,
    LucideIcons.meh,
    LucideIcons.smile,
    LucideIcons.laugh,
  ];
  static const _tints = [C.red, C.orange, C.yellow, C.green, C.green];

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l?.journalComposeHowAreYouFeeling ?? 'How are you feeling?',
            style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: S.x1),
          Text(
            value == null
                ? (l?.journalComposeNotAnsweredYet ?? 'Not answered yet')
                : (l?.journalComposeMoodOfFive(value!) ??
                    'Mood $value of 5 · tap it again to clear'),
            style: F.cap.copyWith(color: p.ink3),
          ),
          const SizedBox(height: S.x4),
          Row(
            children: [
              for (var i = 0; i < 5; i++) ...[
                Expanded(
                  child: Pressable(
                    semanticLabel: value == i + 1
                        ? (l?.journalComposeMoodOfFiveSelected(i + 1) ??
                            'Mood ${i + 1} of 5, selected. Activate to clear.')
                        : (l?.journalComposeMoodOfFiveLabel(i + 1) ??
                            'Mood ${i + 1} of 5'),
                    onTap: () => onChanged(value == i + 1 ? null : i + 1),
                    child: AnimatedContainer(
                      duration: motion(c, Motion.base),
                      height: S.tap,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: R.rMd,
                        color: value == i + 1
                            ? p.fill(_tints[i])
                            : p.wash(_tints[i]),
                      ),
                      child: Icon(
                        _faces[i],
                        size: 22,
                        color: value == i + 1 ? p.inkOnFill : p.on(_tints[i]),
                      ),
                    ),
                  ),
                ),
                if (i < 4) const SizedBox(width: S.x2),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// One journal field as a stepper. Handles ratings and doses from the same
/// spec — the difference is only the step size and the ceiling.
class FieldStepper extends StatelessWidget {
  const FieldStepper({
    super.key,
    required this.spec,
    required this.value,
    required this.onChanged,
    this.atMin,
    this.onTime,
  });

  final JournalFieldSpec spec;

  /// Null means the field was left blank, which is NOT zero: "no caffeine
  /// today" is a logged zero, "did not say" is an absence.
  final double? value;
  final ValueChanged<double?> onChanged;

  /// The LAST occurrence, in local minutes past midnight. Null = not said.
  final int? atMin;

  /// Non-null on a field whose spec says timing matters. The row only offers
  /// it once a dose exists — an hour on its own is not a measurement.
  final VoidCallback? onTime;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final v = value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(spec.label, style: F.body.copyWith(color: p.ink)),
                Text(
                  v == null
                      ? (l?.journalComposeNotLogged ?? 'Not logged')
                      : spec.formatWithUnit(v),
                  style: F.over.copyWith(color: p.ink3),
                ),
                if (v != null && v > 0 && onTime != null)
                  Pressable(
                    semanticLabel:
                        l?.journalComposeWhenWasLastField(spec.label) ??
                        'When was the last ${spec.label}',
                    onTap: onTime,
                    child: Text(
                      atMin == null
                          ? (l?.journalComposeAddTimeOfLastOne ??
                                'Add the time of the last one')
                          : (l?.journalComposeLastAt(
                                  formatMinuteOfDay(atMin!),
                                ) ??
                                'Last at ${formatMinuteOfDay(atMin!)}'),
                      style: F.over.copyWith(color: p.on(C.blue)),
                    ),
                  ),
              ],
            ),
          ),
          _Step(
            icon: LucideIcons.minus,
            enabled: v != null,
            onTap: () {
              final next = (v ?? 0) - spec.step;
              onChanged(next <= 0 ? (v == 0 ? null : 0) : next);
            },
          ),
          const SizedBox(width: S.x2),
          _Step(
            icon: LucideIcons.plus,
            enabled: v == null || v < spec.max,
            onTap: () =>
                onChanged(((v ?? 0) + spec.step).clamp(0, spec.max).toDouble()),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.enabled, required this.onTap});
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    return Pressable(
      semanticLabel: icon == LucideIcons.plus
          ? (l?.journalComposeIncrease ?? 'Increase')
          : (l?.journalComposeDecrease ?? 'Decrease'),
      onTap: enabled ? onTap : null,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: p.card2, borderRadius: R.rSm),
        child: Icon(icon, size: 16, color: enabled ? p.ink2 : p.ink3),
      ),
    );
  }
}
