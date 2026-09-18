import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'alp_tokens.dart';
import 'controller.dart';
import 'domain.dart';
import 'theme.dart';

class OpenBandJournal extends StatefulWidget {
  final OpenBandController controller;
  final ValueChanged<String>? onEdit;
  final VoidCallback? onNutrition;
  const OpenBandJournal({
    super.key,
    required this.controller,
    this.onEdit,
    this.onNutrition,
  });
  @override
  State<OpenBandJournal> createState() => _OpenBandJournalState();
}

class _OpenBandJournalState extends State<OpenBandJournal> {
  late Future<List<JournalEntry>> _entries = _load();
  String? _loadedDay;
  bool _saving = false;
  String? _saveError;

  Future<List<JournalEntry>> _load() {
    _loadedDay = widget.controller.selectedDay;
    return widget.controller.repository.readJournal(_loadedDay!);
  }

  Future<void> _write(String key, double value) async {
    final day = widget.controller.selectedDay;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.controller.repository.writeJournal(day, key, value);
    } catch (_) {
      _saveError = 'Antwort konnte nicht gespeichert werden.';
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _entries = _load();
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final p = OB.of(context);
      final c = widget.controller;
      if (_loadedDay != c.selectedDay) _entries = _load();
      final day = c.day;
      return ColoredBox(
        color: p.canvas,
        child: ListView(
          key: const PageStorageKey('openband.journal'),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                'Journal',
                style: p.text(30, weight: FontWeight.w800, display: true),
              ),
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<JournalEntry>>(
              future: _entries,
              builder: (context, snapshot) {
                final byKey = {
                  for (final e in snapshot.data ?? const <JournalEntry>[])
                    e.key: e.value,
                };
                return OBCheckinCard(
                  mood: byKey['mood'],
                  entries: byKey,
                  busy: _saving || !snapshot.hasData,
                  error: snapshot.hasError
                      ? 'Journal konnte nicht geladen werden.'
                      : _saveError,
                  onMood: (v) => _write('mood', v),
                  onAnswer: (key, yes) => _write(key, yes ? 1 : 0),
                  onEdit: widget.onEdit,
                );
              },
            ),
            const SizedBox(height: 10),
            if (day != null)
              _NutritionRow(intake: day.intake, onTap: widget.onNutrition),
          ],
        ),
      );
    },
  );
}

const _moodLabels = ['Erschöpft', 'Müde', 'Okay', 'Gut', 'Sehr gut'];

class OBCheckinCard extends StatelessWidget {
  final double? mood;
  final Map<String, double> entries;
  final bool busy;
  final String? error;
  final ValueChanged<double> onMood;
  final void Function(String key, bool yes) onAnswer;
  final ValueChanged<String>? onEdit;
  const OBCheckinCard({
    super.key,
    required this.mood,
    required this.entries,
    required this.busy,
    this.error,
    required this.onMood,
    required this.onAnswer,
    this.onEdit,
  });
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Wie fühlst du dich?',
            style: p.text(15, weight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Row(
            spacing: 8,
            children: [
              for (var i = 1; i <= 5; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: mood == i,
                    label: _moodLabels[i - 1],
                    child: InkWell(
                      onTap: busy ? null : () => onMood(i.toDouble()),
                      borderRadius: BorderRadius.circular(14),
                      child: ExcludeSemantics(
                        child: Container(
                          height: 56,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: mood == i ? p.food : p.well,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            '$i',
                            style: p.text(
                              18,
                              weight: FontWeight.w700,
                              display: true,
                              color: mood == i ? p.card : p.ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            error ??
                (mood == null
                    ? 'Noch keine Antwort'
                    : _moodLabels[mood!.round().clamp(1, 5) - 1]),
            style: p.text(
              13,
              weight: FontWeight.w600,
              color: error != null
                  ? p.danger
                  : mood == null
                  ? p.muted
                  : p.foodText,
            ),
          ),
          const SizedBox(height: 12),
          for (final (key, label, icon) in [
            ('caffeine_late', 'Koffein nach 14 Uhr', LucideIcons.coffee),
            ('alcohol_evening', 'Alkohol am Abend', LucideIcons.wine),
            ('read_before_bed', 'Gelesen', LucideIcons.bookOpen),
          ])
            OBHabitRow(
              label: label,
              icon: icon,
              answer: switch (entries[key]) {
                null => null,
                final v => v >= .5,
              },
              busy: busy,
              onAnswer: (yes) => onAnswer(key, yes),
            ),
          if (onEdit != null)
            _HabitRow(
              label: 'Weitere Angaben',
              icon: LucideIcons.listPlus,
              value: switch ([
                'caffeine_mg',
                'alcohol_units',
                'screens_min',
              ].where(entries.containsKey).length) {
                0 => null,
                final n => '$n erfasst',
              },
              onTap: () => onEdit!(''),
            ),
        ],
      ),
    );
  }
}

class OBHabitRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool? answer;
  final bool busy;
  final ValueChanged<bool> onAnswer;
  const OBHabitRow({
    super.key,
    required this.label,
    required this.icon,
    required this.answer,
    required this.busy,
    required this.onAnswer,
  });
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    Widget pill(String text, bool yes) {
      final selected = answer == yes;
      return Semantics(
        button: true,
        selected: selected,
        label: '$label: $text',
        child: InkWell(
          onTap: busy ? null : () => onAnswer(yes),
          borderRadius: BorderRadius.circular(16),
          child: ExcludeSemantics(
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? p.ink : p.well,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                text,
                style: p.text(
                  13,
                  weight: FontWeight.w600,
                  color: selected ? p.card : p.ink,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 56,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.well,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: p.ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: p.text(15, weight: FontWeight.w500)),
          ),
          pill('Ja', true),
          const SizedBox(width: 6),
          pill('Nein', false),
        ],
      ),
    );
  }
}

class _HabitRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? value;
  final VoidCallback? onTap;
  const _HabitRow({
    required this.label,
    required this.icon,
    required this.value,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: p.line)),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: p.well,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 16, color: p.ink),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: p.text(15, weight: FontWeight.w500)),
            ),
            Text(
              value ?? '—',
              style: p.text(
                15,
                weight: FontWeight.w600,
                color: value == null ? p.muted : p.ink,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Icon(LucideIcons.chevronRight, size: 16, color: p.gap),
            ],
          ],
        ),
      ),
    );
  }
}

class _NutritionRow extends StatelessWidget {
  final DayIntake intake;
  final VoidCallback? onTap;
  const _NutritionRow({required this.intake, this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AlpRadius.card),
      child: OBCard(
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: p.foodTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(LucideIcons.utensils, size: 18, color: p.food),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ernährung', style: p.text(15, weight: FontWeight.w600)),
                  Text(
                    intake.kcal == null && intake.waterMl == null
                        ? 'Noch nichts erfasst'
                        : [
                            if (intake.kcal case final k?)
                              '${obNumber(k)} kcal',
                            if (intake.waterMl case final w?)
                              '${obNumber(w / 1000, digits: 2)} l Wasser',
                          ].join(' · '),
                    style: p.text(13, color: p.muted),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(LucideIcons.chevronRight, size: 16, color: p.gap),
          ],
        ),
      ),
    );
  }
}
