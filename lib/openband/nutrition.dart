import 'dart:async';

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

class OpenBandNutrition extends StatefulWidget {
  final OpenBandController controller;
  final FutureOr<void> Function(String meal)? onAdd;
  const OpenBandNutrition({super.key, required this.controller, this.onAdd});
  @override
  State<OpenBandNutrition> createState() => _OpenBandNutritionState();
}

class _OpenBandNutritionState extends State<OpenBandNutrition> {
  late String _day = controller.selectedDay;
  DayMeals? _meals;
  Object? _mealsError;
  NutritionTargetValues? _targets;
  bool _targetsReady = false;
  bool _targetsUnavailable = false;
  bool _targetsLoading = true;
  int _mealRead = 0;
  int _targetRead = 0;

  OpenBandController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onController);
    _loadMeals(_day);
    _loadTargets(_day);
  }

  @override
  void didUpdateWidget(covariant OpenBandNutrition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == controller) return;
    oldWidget.controller.removeListener(_onController);
    controller.addListener(_onController);
    _syncDay();
  }

  @override
  void dispose() {
    controller.removeListener(_onController);
    super.dispose();
  }

  void _onController() {
    if (!mounted) return;
    if (controller.selectedDay != _day) {
      _syncDay();
      return;
    }
    setState(() {});
  }

  void _syncDay() {
    final day = controller.selectedDay;
    setState(() {
      _day = day;
      _meals = null;
      _mealsError = null;
      _targets = null;
      _targetsReady = false;
      _targetsUnavailable = false;
      _targetsLoading = true;
    });
    _loadMeals(day);
    _loadTargets(day);
  }

  bool _live(int token, int current, String day) =>
      mounted && token == current && controller.selectedDay == day;

  Future<void> _loadMeals(String day) async {
    final token = ++_mealRead;
    try {
      final meals = await controller.repository.readMeals(day);
      if (!_live(token, _mealRead, day)) return;
      setState(() {
        _meals = meals;
        _mealsError = null;
      });
    } catch (e) {
      if (!_live(token, _mealRead, day)) return;
      setState(() {
        _meals = null;
        _mealsError = e;
      });
    }
  }

  Future<void> _loadTargets(String day) async {
    final token = ++_targetRead;
    try {
      final snap = await controller.repository.readNutritionTargets(day);
      if (!_live(token, _targetRead, day)) return;
      setState(() {
        _targets = snap.values;
        _targetsReady = true;
        _targetsUnavailable = false;
        _targetsLoading = false;
      });
    } catch (_) {
      if (!_live(token, _targetRead, day)) return;
      setState(() {
        _targets = null;
        _targetsReady = false;
        _targetsUnavailable = true;
        _targetsLoading = false;
      });
    }
  }

  Future<void> _retryTargets() async {
    if (_targetsLoading) return;
    final day = controller.selectedDay;
    setState(() => _targetsLoading = true);
    await _loadTargets(day);
  }

  Future<void> _openGoals() async {
    final day = controller.selectedDay;
    await openOpenBandNutritionGoals(
      context,
      repository: controller.repository,
      day: day,
      now: controller.day?.synthetic == true
          ? () => DateTime(2026, 9, 15, 9, 41)
          : controller.now,
      synthetic: controller.day?.synthetic == true,
    );
    if (!mounted || controller.selectedDay != day) return;
    await _loadTargets(day);
  }

  Future<void> _onAdd(String meal) async {
    final day = controller.selectedDay;
    await widget.onAdd?.call(meal);
    if (!mounted || controller.selectedDay != day) return;
    await _loadMeals(day);
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final meals = _meals;
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        backgroundColor: p.canvas,
        title: Text('Ernährung', style: p.text(18, weight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Ernährungsziele',
            onPressed: _openGoals,
            icon: Icon(LucideIcons.settings, size: 20, color: p.ink),
          ),
        ],
      ),
      body: _mealsError != null
          ? Center(
              child: Text(
                'Einträge konnten nicht geladen werden.',
                style: p.text(14, color: p.danger),
              ),
            )
          : meals == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 12),
                  child: Text(
                    obDayTitle(meals.day),
                    style: p.text(30, weight: FontWeight.w800, display: true),
                  ),
                ),
                if (_targetsUnavailable || _targetsReady) ...[
                  OBMacroBars(
                    meals: meals,
                    targets: _targetsUnavailable ? null : _targets,
                    targetsUnavailable: _targetsUnavailable,
                  ),
                  if (_targetsUnavailable)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _targetsLoading ? null : _retryTargets,
                        style: TextButton.styleFrom(
                          foregroundColor: p.ink,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(44, 44),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Erneut',
                          style: p.text(13, weight: FontWeight.w600),
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                ],
                for (final (key, label) in obMeals)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: OBMealSection(
                      meal: key,
                      label: label,
                      entries: meals.entries
                          .where((e) => e.meal == key)
                          .toList(),
                      onAdd: widget.onAdd == null ? null : () => _onAdd(key),
                    ),
                  ),
              ],
            ),
    );
  }
}

String _nutritionQty(double? value) {
  if (value == null || !value.isFinite) return '—';
  if (value == value.roundToDouble()) return obNumber(value);
  var text = obNumber(value, digits: 2);
  if (text.contains(',')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    if (text.endsWith(',')) text = text.substring(0, text.length - 1);
  }
  return text;
}

int _missingShownNutrientCount(DayMeals meals) {
  var n = 0;
  for (final e in meals.entries) {
    if (e.kcal == null ||
        e.proteinG == null ||
        e.fatG == null ||
        e.carbsG == null) {
      n++;
    }
  }
  return n;
}

String _macroGramsLine(NutrientSum sum, double? target) {
  final actual = _nutritionQty(sum.value);
  if (target == null || !target.isFinite) return '$actual g';
  return '$actual / ${_nutritionQty(target)} g';
}

String _missingNutrientLabel(int count) =>
    '$count ${count == 1 ? 'Eintrag' : 'Einträge'} unvollständig';

bool _positiveTarget(double? value) =>
    value != null && value.isFinite && value > 0;

bool _savedGramTarget(double? value) => value != null && value.isFinite;

bool _largeMacroType(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(15) > 20;

const _kMacroColGap = 10.0;
const _kMacroPairGap = 4.0;
const _kMacroHeaderGap = 12.0;
const _kMacroKcalUnitGap = 6.0;

TextStyle _macroLabelStyle(OB p) =>
    p.text(12, weight: FontWeight.w600, color: p.muted).copyWith(height: 16 / 12);

TextStyle _macroValueStyle(OB p) => p
    .text(13, weight: FontWeight.w700, display: true)
    .copyWith(
      height: 16 / 13,
      letterSpacing: 0,
      fontFeatures: const [FontFeature.proportionalFigures()],
    );

double _macroPaintWidth(
  String text,
  TextStyle style, {
  required TextScaler scaler,
  required Locale locale,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
    locale: locale,
  )..layout();
  return painter.width;
}

bool _macroRowFitsThree({
  required double maxWidth,
  required List<(String label, String value)> items,
  required TextStyle labelStyle,
  required TextStyle valueStyle,
  required TextScaler scaler,
  required Locale locale,
}) {
  if (items.isEmpty) return true;
  final columnWidth =
      (maxWidth - _kMacroColGap * (items.length - 1)) / items.length;
  if (columnWidth <= 0) return false;
  for (final (label, value) in items) {
    final needed =
        _macroPaintWidth(label, labelStyle, scaler: scaler, locale: locale) +
        _kMacroPairGap +
        _macroPaintWidth(value, valueStyle, scaler: scaler, locale: locale);
    if (needed > columnWidth) return false;
  }
  return true;
}

bool _macroHeaderFits({
  required double maxWidth,
  required String kcal,
  required String ziel,
  required TextStyle kcalStyle,
  required TextStyle unitStyle,
  required TextStyle zielStyle,
  required TextScaler scaler,
  required Locale locale,
}) {
  final kcalWidth =
      _macroPaintWidth(kcal, kcalStyle, scaler: scaler, locale: locale) +
      _kMacroKcalUnitGap +
      _macroPaintWidth('kcal', unitStyle, scaler: scaler, locale: locale);
  final zielWidth = _macroPaintWidth(
    ziel,
    zielStyle,
    scaler: scaler,
    locale: locale,
  );
  return kcalWidth + _kMacroHeaderGap + zielWidth <= maxWidth;
}

class OBMacroBars extends StatelessWidget {
  final DayMeals meals;
  final NutritionTargetValues? targets;
  final bool targetsUnavailable;
  const OBMacroBars({
    super.key,
    required this.meals,
    this.targets,
    this.targetsUnavailable = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final t = targetsUnavailable
        ? const NutritionTargetValues()
        : targets ?? const NutritionTargetValues();
    final large = _largeMacroType(context);
    final energyTarget = _positiveTarget(t.energyKcal) ? t.energyKcal : null;
    final energyLabel = targetsUnavailable
        ? 'Ziel —'
        : energyTarget == null
        ? 'Kein Ziel'
        : 'Ziel ${_nutritionQty(energyTarget)}';
    final missing = _missingShownNutrientCount(meals);
    final labelStyle = _macroLabelStyle(p);
    final valueStyle = _macroValueStyle(p);
    final macros = [
      (
        name: 'protein',
        label: 'Eiweiß',
        semantic: 'Eiweiß',
        sum: meals.proteinG,
        target: t.proteinG,
        color: p.pulse,
      ),
      (
        name: 'fat',
        label: 'Fett',
        semantic: 'Fett',
        sum: meals.fatG,
        target: t.fatG,
        color: p.food,
      ),
      (
        name: 'carbs',
        label: large ? 'Kohlenhydrate' : 'KH',
        semantic: 'Kohlenhydrate',
        sum: meals.carbsG,
        target: t.carbohydrateG,
        color: p.strain,
      ),
    ];
    final headline = p
        .text(34, weight: FontWeight.w800, display: true)
        .copyWith(height: 36 / 34);
    final unitStyle = p
        .text(14, weight: FontWeight.w500, color: p.muted)
        .copyWith(height: 18 / 14);
    final zielStyle = p
        .text(13, weight: FontWeight.w600, color: p.muted)
        .copyWith(height: 18 / 13);
    final missingStyle = p.text(12, color: p.muted).copyWith(height: 16 / 12);
    final semantics = [
      '${_nutritionQty(meals.kcal.value)} kcal',
      energyLabel,
      for (final m in macros)
        '${m.semantic} ${_macroGramsLine(m.sum, _savedGramTarget(m.target) ? m.target : null)}',
      if (missing > 0) _missingNutrientLabel(missing),
    ].join('. ');

    Widget column({
      required String name,
      required String label,
      required NutrientSum sum,
      required double? target,
      required Color color,
    }) {
      final saved = _savedGramTarget(target);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(label, style: labelStyle),
              const SizedBox(width: _kMacroPairGap),
              Expanded(
                child: Text(
                  _macroGramsLine(sum, saved ? target : null),
                  textAlign: TextAlign.right,
                  style: valueStyle,
                ),
              ),
            ],
          ),
          if (saved)
            _MacroFillTrack(
              name: name,
              height: 6,
              radius: 3,
              fillColor: color,
              actual: sum.value,
              target: target,
            ),
        ],
      );
    }

    return Semantics(
      container: true,
      label: semantics,
      child: ExcludeSemantics(
        child: OBCard(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scaler = MediaQuery.textScalerOf(context);
              final locale = Localizations.localeOf(context);
              final kcalText = _nutritionQty(meals.kcal.value);
              final headerBeside =
                  !large &&
                  _macroHeaderFits(
                    maxWidth: constraints.maxWidth,
                    kcal: kcalText,
                    ziel: energyLabel,
                    kcalStyle: headline,
                    unitStyle: unitStyle,
                    zielStyle: zielStyle,
                    scaler: scaler,
                    locale: locale,
                  );
              final stacked =
                  large ||
                  !_macroRowFitsThree(
                    maxWidth: constraints.maxWidth,
                    items: [
                      for (final m in macros)
                        (
                          m.label,
                          _macroGramsLine(
                            m.sum,
                            _savedGramTarget(m.target) ? m.target : null,
                          ),
                        ),
                    ],
                    labelStyle: labelStyle,
                    valueStyle: valueStyle,
                    scaler: scaler,
                    locale: locale,
                  );
              final kcalRow = Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(kcalText, style: headline),
                  const SizedBox(width: _kMacroKcalUnitGap),
                  Text('kcal', style: unitStyle),
                ],
              );
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  if (headerBeside)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        kcalRow,
                        Expanded(
                          child: Text(
                            energyLabel,
                            textAlign: TextAlign.right,
                            style: zielStyle,
                          ),
                        ),
                      ],
                    )
                  else
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 8,
                      children: [
                        kcalRow,
                        Text(energyLabel, style: zielStyle),
                      ],
                    ),
                  if (energyTarget != null)
                    _MacroFillTrack(
                      name: 'energy',
                      height: 8,
                      radius: 4,
                      fillColor: p.ink,
                      actual: meals.kcal.value,
                      target: energyTarget,
                    ),
                  if (stacked)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 12,
                      children: [
                        for (final m in macros)
                          column(
                            name: m.name,
                            label: m.label,
                            sum: m.sum,
                            target: m.target,
                            color: m.color,
                          ),
                      ],
                    )
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: _kMacroColGap,
                      children: [
                        for (final m in macros)
                          Expanded(
                            child: column(
                              name: m.name,
                              label: m.label,
                              sum: m.sum,
                              target: m.target,
                              color: m.color,
                            ),
                          ),
                      ],
                    ),
                  if (missing > 0)
                    Text(_missingNutrientLabel(missing), style: missingStyle),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MacroFillTrack extends StatelessWidget {
  final String name;
  final double height;
  final double radius;
  final Color fillColor;
  final double? actual;
  final double? target;
  const _MacroFillTrack({
    required this.name,
    required this.height,
    required this.radius,
    required this.fillColor,
    required this.actual,
    required this.target,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final canFill =
        actual != null &&
        actual!.isFinite &&
        target != null &&
        target!.isFinite &&
        target! > 0;
    final factor = canFill ? (actual! / target!).clamp(0.0, 1.0) : 0.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        key: ValueKey('macro-$name-track'),
        height: height,
        width: double.infinity,
        child: ColoredBox(
          color: p.well,
          child: LayoutBuilder(
            builder: (context, constraints) => Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                key: ValueKey('macro-$name-fill'),
                width: constraints.maxWidth * factor,
                height: height,
                child: ColoredBox(color: fillColor),
              ),
            ),
          ),
        ),
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
