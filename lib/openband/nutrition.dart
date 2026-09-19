import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'alp_tokens.dart';
import 'controller.dart';
import 'domain.dart';
import 'nutrition_goals.dart';
import 'theme.dart';

const obMeals = [
  ('breakfast', 'Frühstück'),
  ('lunch', 'Mittag'),
  ('dinner', 'Abend'),
  ('snack', 'Zwischendurch'),
];

class OpenBandNutrition extends StatelessWidget {
  final OpenBandController controller;
  final ValueChanged<String>? onAdd;
  const OpenBandNutrition({super.key, required this.controller, this.onAdd});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final p = OB.of(context);
      return Scaffold(
        backgroundColor: p.canvas,
        appBar: AppBar(
          backgroundColor: p.canvas,
          title: Text('Ernährung', style: p.text(18, weight: FontWeight.w600)),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'Ernährungsziele',
              onPressed: () => openOpenBandNutritionGoals(
                context,
                repository: controller.repository,
                day: controller.selectedDay,
                now: controller.day?.synthetic == true
                    ? () => DateTime(2026, 9, 15, 9, 41)
                    : controller.now,
                synthetic: controller.day?.synthetic == true,
              ),
              icon: Icon(LucideIcons.settings, size: 20, color: p.ink),
            ),
          ],
        ),
        body: FutureBuilder<DayMeals>(
          future: controller.repository.readMeals(controller.selectedDay),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Einträge konnten nicht geladen werden.',
                  style: p.text(14, color: p.danger),
                ),
              );
            }
            final meals = snapshot.data;
            if (meals == null) return const SizedBox.shrink();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 12),
                  child: Text(
                    obDayTitle(meals.day),
                    style: p.text(30, weight: FontWeight.w800, display: true),
                  ),
                ),
                OBMacroBars(meals: meals),
                const SizedBox(height: 10),
                for (final (key, label) in obMeals)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: OBMealSection(
                      meal: key,
                      label: label,
                      entries: meals.entries
                          .where((e) => e.meal == key)
                          .toList(),
                      onAdd: onAdd == null ? null : () => onAdd!(key),
                    ),
                  ),
              ],
            );
          },
        ),
      );
    },
  );
}

String _sum(NutrientSum s, {int digits = 0}) =>
    s.value == null ? '—' : obNumber(s.value, digits: digits);

class OBMacroBars extends StatelessWidget {
  final DayMeals meals;
  const OBMacroBars({super.key, required this.meals});
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final unknown = meals.kcal.unknown;
    Widget macro(String label, NutrientSum s, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          Text(
            label,
            style: p.text(12, weight: FontWeight.w600, color: p.muted),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _sum(s),
                style: p.text(20, weight: FontWeight.w800, display: true),
              ),
              const SizedBox(width: 2),
              Text(
                'g',
                style: p.text(12, weight: FontWeight.w500, color: p.muted),
              ),
            ],
          ),
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: s.value == null ? p.well : color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
    return OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _sum(meals.kcal),
                style: p.text(34, weight: FontWeight.w800, display: true),
              ),
              const SizedBox(width: 4),
              Text(
                'kcal',
                style: p.text(14, weight: FontWeight.w500, color: p.muted),
              ),
              if (unknown > 0) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$unknown ${unknown == 1 ? 'Eintrag' : 'Einträge'} ohne Nährwerte',
                    style: p.text(13, weight: FontWeight.w600, color: p.muted),
                  ),
                ),
              ],
            ],
          ),
          Row(
            spacing: 12,
            children: [
              macro('Eiweiß', meals.proteinG, p.pulse),
              macro('Kohlenhydrate', meals.carbsG, p.strain),
              macro('Fett', meals.fatG, p.food),
            ],
          ),
        ],
      ),
    );
  }
}

class OBMealSection extends StatelessWidget {
  final String meal, label;
  final List<MealEntry> entries;
  final VoidCallback? onAdd;
  const OBMealSection({
    super.key,
    required this.meal,
    required this.label,
    required this.entries,
    this.onAdd,
  });
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final known = entries.where((e) => e.kcal != null).toList();
    final total = known.isEmpty
        ? null
        : known.fold<double>(0, (a, e) => a + e.kcal!);
    return OBCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: p.text(15, weight: FontWeight.w600)),
              ),
              Text(
                total == null
                    ? '—'
                    : '${known.length < entries.length ? 'mind. ' : ''}${obNumber(total)} kcal',
                style: p.text(13, weight: FontWeight.w600, color: p.muted),
              ),
              IconButton(
                tooltip: '$label ergänzen',
                onPressed: onAdd,
                icon: Icon(LucideIcons.plus, size: 20, color: p.action),
              ),
            ],
          ),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Noch nichts erfasst',
                  style: p.text(13, color: p.muted),
                ),
              ),
            ),
          for (final e in entries)
            Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: p.line)),
              ),
              child: Row(
                children: [
                  Expanded(child: Text(e.label, style: p.text(15))),
                  if (e.kcal != null) ...[
                    for (final (v, c) in [
                      (e.proteinG, p.pulseText),
                      (e.carbsG, p.strainText),
                      (e.fatG, p.foodText),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          v == null ? '—' : obNumber(v),
                          style: p.text(12, weight: FontWeight.w600, color: c),
                        ),
                      ),
                    const SizedBox(width: 12),
                  ],
                  Text(
                    e.kcal == null ? '—' : obNumber(e.kcal),
                    style: p.text(15, weight: FontWeight.w700, display: true),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Stages entries for one meal and saves them atomically (B05). The picker
/// that fills the draft is the host's; this widget owns preview and commit.
class OBMealDraftSheet extends StatefulWidget {
  final OpenBandRepository repository;
  final MealDraft draft;
  const OBMealDraftSheet({
    super.key,
    required this.repository,
    required this.draft,
  });
  @override
  State<OBMealDraftSheet> createState() => _OBMealDraftSheetState();
}

class _OBMealDraftSheetState extends State<OBMealDraftSheet> {
  bool _saving = false;
  String? _error;

  Future<void> _commit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.commitMealDraft(widget.draft);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Speichern schlägt fehl. Der Entwurf bleibt erhalten.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final d = widget.draft;
    final label = obMeals.firstWhere((m) => m.$1 == d.meal).$2;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Text(
              '$label · ${d.entries.length} ${d.entries.length == 1 ? 'Eintrag' : 'Einträge'}',
              style: p.text(18, weight: FontWeight.w700, display: true),
            ),
            for (final e in d.entries)
              Row(
                children: [
                  Expanded(child: Text(e.label, style: p.text(15))),
                  Text(
                    e.kcal == null ? '—' : '${obNumber(e.kcal)} kcal',
                    style: p.text(15, weight: FontWeight.w600),
                  ),
                ],
              ),
            if (_error case final err?)
              Text(
                err,
                style: p.text(13, weight: FontWeight.w600, color: p.danger),
              ),
            OBAction(
              _saving ? 'Wird gespeichert…' : 'Speichern',
              onPressed: _saving || d.entries.isEmpty ? null : _commit,
            ),
            OBAction(
              'Entwurf behalten',
              secondary: true,
              onPressed: _saving
                  ? null
                  : () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool?> showOpenBandMealDraft(
  BuildContext context,
  OpenBandRepository repository,
  MealDraft draft,
) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(AlpRadius.card)),
  ),
  builder: (_) => OBMealDraftSheet(repository: repository, draft: draft),
);

/// Search the local food dictionary and stage portions into a [MealDraft].
/// Returns the updated draft when the user confirms, null when dismissed.
class OBFoodSearchSheet extends StatefulWidget {
  final OpenBandRepository repository;
  final MealDraft draft;
  const OBFoodSearchSheet({
    super.key,
    required this.repository,
    required this.draft,
  });
  @override
  State<OBFoodSearchSheet> createState() => _OBFoodSearchSheetState();
}

class _OBFoodSearchSheetState extends State<OBFoodSearchSheet> {
  final _query = TextEditingController();
  late final List<MealDraftEntry> _entries = [...widget.draft.entries];
  List<FoodHit> _hits = const [];
  bool _searching = false;

  Future<void> _search(String q) async {
    setState(() => _searching = true);
    final hits = await widget.repository.searchFoods(q);
    if (!mounted || _query.text != q) return;
    setState(() {
      _hits = hits;
      _searching = false;
    });
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final label = obMeals.firstWhere((m) => m.$1 == widget.draft.meal).$2;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Text(
              '$label ergänzen',
              style: p.text(18, weight: FontWeight.w700, display: true),
            ),
            TextField(
              controller: _query,
              autofocus: true,
              onChanged: _search,
              decoration: InputDecoration(
                hintText: 'Lebensmittel suchen',
                prefixIcon: const Icon(LucideIcons.search, size: 18),
                filled: true,
                fillColor: p.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AlpRadius.row),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (_hits.isEmpty && _query.text.isNotEmpty && !_searching)
              Text(
                'Nichts gefunden. Eigene Lebensmittel lassen sich im Profil anlegen.',
                style: p.text(13, color: p.muted),
              ),
            for (final h in _hits.take(6))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  h.label,
                  style: p.text(15, weight: FontWeight.w500),
                ),
                subtitle: Text(
                  [
                    if (h.brand.isNotEmpty) h.brand,
                    h.kcal100 == null
                        ? 'ohne Nährwerte'
                        : '${obNumber(h.kcal100)} kcal / 100 g',
                  ].join(' · '),
                  style: p.text(12, color: p.muted),
                ),
                trailing: Icon(LucideIcons.plus, size: 20, color: p.action),
                onTap: () => setState(() {
                  _entries.add(
                    h.portion(
                      '${widget.draft.id}-${_entries.length + 1}',
                      h.servingG ?? 100,
                    ),
                  );
                }),
              ),
            if (_entries.isNotEmpty)
              Text(
                '${_entries.length} im Entwurf: ${_entries.map((e) => e.label).join(', ')}',
                style: p.text(13, weight: FontWeight.w600),
              ),
            OBAction(
              'Übernehmen',
              onPressed: _entries.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(
                      MealDraft(
                        id: widget.draft.id,
                        day: widget.draft.day,
                        meal: widget.draft.meal,
                        entries: _entries,
                        updatedAt: DateTime.now(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
