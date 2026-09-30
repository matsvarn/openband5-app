import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../data/day_label.dart';
import '../state/app_state.dart';
import 'calendar.dart';
import 'confirm_sheet.dart';
import 'domain.dart';
import 'health.dart' show OBSegmented;
import 'journal_controls.dart';
import 'local_repository.dart';
import 'theme.dart';

const kNutritionProteinKcal = 4.0;
const kNutritionCarbKcal = 4.0;
const kNutritionFatKcal = 9.0;
const kNutritionPercentSumTolerance = 0.05;
const kNutritionGoalsTitle = 'Ernährungsziele';

/// Decimal-only parse for this editor. Scientific/`NaN` stay raw text and
/// refuse; comma or dot, not both. Does not use [LabParse.of] (`1e2` → 100).
class NutritionGoalParse {
  final double? value;
  final bool bad;
  const NutritionGoalParse._(this.value, this.bad);
  bool get blank => value == null && !bad;

  static NutritionGoalParse of(String text) {
    final s = text.trim();
    if (s.isEmpty) return const NutritionGoalParse._(null, false);
    if (s.contains(',') && s.contains('.')) {
      return const NutritionGoalParse._(null, true);
    }
    if (!RegExp(r'^-?\d+(?:[.,]\d+)?$').hasMatch(s)) {
      return const NutritionGoalParse._(null, true);
    }
    final v = double.tryParse(s.replaceAll(',', '.'));
    if (v == null || !v.isFinite) return const NutritionGoalParse._(null, true);
    return NutritionGoalParse._(v, false);
  }
}

NutritionGoalParse parseNutritionGoalNumber(String text) =>
    NutritionGoalParse.of(text);

bool _largeGoalType(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(15) > 20;

/// Paper 3VOC/3VWA: visible hyphenated break at 2x. Soft hyphen does not paint.
String nutritionGoalsTitle(BuildContext context) => _largeGoalType(context)
    ? 'Ernährungs-\nziele'
    : kNutritionGoalsTitle;

String formatNutritionGoalNumber(double? value) {
  if (value == null) return '';
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.round().toString();
  }
  var s = value.toString();
  if (s.contains('e') || s.contains('E')) {
    s = value.toStringAsFixed(12);
    while (s.contains('.') && s.endsWith('0')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  return s.replaceAll('.', ',');
}

double? nutritionMacroKcal({
  required double? proteinG,
  required double? carbohydrateG,
  required double? fatG,
}) {
  if (proteinG == null || carbohydrateG == null || fatG == null) return null;
  return proteinG * kNutritionProteinKcal +
      carbohydrateG * kNutritionCarbKcal +
      fatG * kNutritionFatKcal;
}

double? nutritionPercentOf(double? grams, double? energy, double kcalPerG) {
  if (grams == null || energy == null || !energy.isFinite || energy <= 0) {
    return null;
  }
  return grams * kcalPerG / energy * 100;
}

double? nutritionGramsOf(double? percent, double? energy, double kcalPerG) {
  if (percent == null || energy == null || !energy.isFinite || energy <= 0) {
    return null;
  }
  return percent / 100 * energy / kcalPerG;
}

bool nutritionPercentSumOk(double a, double b, double c) =>
    (a + b + c - 100).abs() <= kNutritionPercentSumTolerance;

bool nutritionValuesEqual(NutritionTargetValues a, NutritionTargetValues b) =>
    a.energyKcal == b.energyKcal &&
    a.proteinG == b.proteinG &&
    a.carbohydrateG == b.carbohydrateG &&
    a.fatG == b.fatG;

bool _stackGoalInputs(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(15) > 20 ||
    MediaQuery.sizeOf(context).width < 360;

String _kcalLabel(double? value) {
  if (value == null) return '—';
  return '${obNumber(value)} kcal';
}

String _gramLabel(double? value) {
  if (value == null) return '—';
  return '${obNumber(value, digits: value == value.roundToDouble() ? 0 : 2)} g';
}

Future<void> openOpenBandNutritionGoals(
  BuildContext context, {
  required OpenBandRepository repository,
  required String day,
  DateTime Function()? now,
  bool synthetic = false,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => OpenBandNutritionGoals(
        repository: repository,
        day: day,
        now: now,
        synthetic: synthetic,
      ),
    ),
  );
}

class OpenBandNutritionGoalsRoute extends StatelessWidget {
  final String? date;
  const OpenBandNutritionGoalsRoute({super.key, this.date});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return OpenBandNutritionGoals(
      repository: LocalOpenBandRepository(app),
      day: date ?? todayLabel(),
    );
  }
}

class OpenBandNutritionGoals extends StatefulWidget {
  final OpenBandRepository repository;
  final String day;
  final DateTime Function()? now;
  final bool synthetic;
  const OpenBandNutritionGoals({
    super.key,
    required this.repository,
    required this.day,
    this.now,
    this.synthetic = false,
  });

  @override
  State<OpenBandNutritionGoals> createState() => _OpenBandNutritionGoalsState();
}

enum _RemovalIssue { conflict, failed }

class _OpenBandNutritionGoalsState extends State<OpenBandNutritionGoals> {
  NutritionTargetSnapshot? _snap;
  Object? _error;
  _RemovalIssue? _removalIssue;
  String? _removalDay;
  int? _removalRevision;
  bool _loading = true;
  bool _busy = false;

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap = await widget.repository.readNutritionTargets(widget.day);
      if (!mounted) return;
      setState(() {
        _snap = snap;
        _loading = false;
        _removalIssue = null;
        _removalDay = null;
        _removalRevision = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
        _snap = null;
      });
    }
  }

  Future<void> _edit({
    String? day,
    NutritionTargetValues? draft,
  }) async {
    if (_busy) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => OpenBandNutritionGoalsEditor(
          repository: widget.repository,
          day: day ?? widget.day,
          now: _now,
          synthetic: widget.synthetic,
          draft: draft,
        ),
      ),
    );
    if (saved == true && mounted) _load();
  }

  Future<void> _history() async {
    if (_busy) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => OpenBandNutritionGoalHistory(
          repository: widget.repository,
          day: widget.day,
          now: _now,
          synthetic: widget.synthetic,
          current: _snap?.values,
        ),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _reloadRemoval() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final snap = await widget.repository.readNutritionTargets(widget.day);
      if (!mounted) return;
      setState(() {
        _snap = snap;
        _busy = false;
        _error = null;
        _removalIssue = null;
        _removalDay = null;
        _removalRevision = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    if (_busy) return;
    final day = _removalDay ?? widget.day;
    final yes = await showOpenBandConfirmSheet(
      context: context,
      title: 'Ziele entfernen?',
      body: 'Ab ${obDate(day)}',
      confirmLabel: 'Entfernen',
      cancelLabel: 'Abbrechen',
    );
    if (yes != true || !mounted) return;
    _removalDay ??= widget.day;
    _removalRevision ??= _snap?.day == widget.day ? _snap?.revision : null;
    setState(() => _busy = true);
    try {
      final result = await widget.repository.clearNutritionTargets(
        _removalDay!,
        expectedRevision: _removalRevision,
      );
      if (!mounted) return;
      if (result.conflict) {
        setState(() {
          _busy = false;
          _removalIssue = _RemovalIssue.conflict;
        });
        return;
      }
      setState(() {
        _busy = false;
        _removalIssue = null;
        _removalDay = null;
        _removalRevision = null;
      });
      await _load();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _removalIssue = _RemovalIssue.failed;
      });
    }
  }

  void _info() => showOpenBandJournalInfo(
    context,
    title: nutritionGoalsTitle(context),
    body:
        'Eigene Tagesziele, keine Bedarfsschätzung.\n'
        'Änderungen gelten ab dem gewählten Datum. Leere Felder haben kein Ziel.\n'
        'Die Energie aus Makros kann vom Energieziel abweichen.',
  );

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final snap = _snap;
    final hasGoal = snap != null && snap.origin != null && snap.values.hasAny;
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            OBPageHeader(
              title: nutritionGoalsTitle(context),
              subtitle: '',
              onInfo: _info,
              infoLabel: 'Ernährungsziele',
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(child: CircularProgressIndicator.adaptive()),
              )
            else if (_error != null)
              OBCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Ziele nicht geladen',
                      style: p.text(13, color: p.danger).copyWith(height: 18 / 13),
                    ),
                    const SizedBox(height: 12),
                    _textAction(
                      'Erneut',
                      onPressed: _load,
                      color: p.ink,
                      weight: FontWeight.w600,
                    ),
                  ],
                ),
              )
            else if (!hasGoal) ...[
              OBCard(
                padding: const EdgeInsets.fromLTRB(14, 20, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Keine Ziele',
                      style: p
                          .text(18, weight: FontWeight.w600)
                          .copyWith(height: 24 / 18),
                    ),
                    const SizedBox(height: 20),
                    OBAction(
                      'Ziele festlegen',
                      ink: true,
                      onPressed: _busy ? null : () => _edit(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _linkRow('Verlauf', onTap: _busy ? null : _history),
            ] else ...[
              OBCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      snap.origin == NutritionTargetOrigin.legacyUndated
                          ? 'Ohne Startdatum'
                          : 'Ab ${obDate(snap.effectiveDay!)}',
                      style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          snap.values.energyKcal == null
                              ? '—'
                              : obNumber(snap.values.energyKcal),
                          style: p
                              .text(44, weight: FontWeight.w700, display: true)
                              .copyWith(height: 48 / 44),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'kcal',
                          style: p.text(15, color: p.muted).copyWith(height: 20 / 15),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _macrosRow(snap.values),
                    const SizedBox(height: 12),
                    OBAction(
                      'Ändern',
                      ink: true,
                      onPressed: _busy ? null : () => _edit(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _linkRow('Verlauf', onTap: _busy ? null : _history),
              const SizedBox(height: 12),
              if (_removalIssue != null) ...[
                Text(
                  _removalIssue == _RemovalIssue.conflict
                      ? 'Ziele inzwischen geändert.'
                      : 'Entfernen fehlgeschlagen.',
                  style: p.text(13, color: p.danger).copyWith(height: 18 / 13),
                ),
                const SizedBox(height: 8),
                OBAction(
                  _removalIssue == _RemovalIssue.conflict
                      ? 'Neu laden'
                      : 'Erneut',
                  ink: true,
                  onPressed: _busy
                      ? null
                      : (_removalIssue == _RemovalIssue.conflict
                            ? _reloadRemoval
                            : _clear),
                ),
              ] else
                _textAction(
                  'Ziele entfernen',
                  onPressed: _busy ? null : _clear,
                  color: p.muted,
                ),
            ],
            if (widget.synthetic) ...[
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Synthetische Daten',
                  style: p.text(12, color: p.muted).copyWith(height: 18 / 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _macrosRow(NutritionTargetValues v) {
    if (_largeGoalType(context)) {
      return Column(
        children: [
          _overviewMacroLine('Eiweiß', v.proteinG),
          _overviewMacroLine('Kohlenhydrate', v.carbohydrateG),
          _overviewMacroLine('Fett', v.fatG),
        ],
      );
    }
    return Row(
      children: [
        _macroCol('Eiweiß', v.proteinG),
        const SizedBox(width: 12),
        _macroCol('Kohlenhydrate', v.carbohydrateG),
        const SizedBox(width: 12),
        _macroCol('Fett', v.fatG),
      ],
    );
  }

  Widget _overviewMacroLine(String label, double? grams) {
    final p = OB.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: p.text(12, color: p.muted).copyWith(height: 18 / 12),
            ),
          ),
          Text(_gramLabel(grams), style: p.text(15).copyWith(height: 20 / 15)),
        ],
      ),
    );
  }

  Widget _macroCol(String label, double? grams) {
    final p = OB.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: p.text(12, color: p.muted).copyWith(height: 18 / 12)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                grams == null ? '—' : obNumber(grams, digits: grams == grams.roundToDouble() ? 0 : 2),
                style: p
                    .text(20, weight: FontWeight.w700, display: true)
                    .copyWith(height: 26 / 20),
              ),
              const SizedBox(width: 4),
              Text('g', style: p.text(13, color: p.muted).copyWith(height: 18 / 13)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _linkRow(String label, {VoidCallback? onTap}) {
    final p = OB.of(context);
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(LucideIcons.history, size: 20, color: p.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label, style: p.text(15).copyWith(height: 20 / 15)),
                ),
                Icon(LucideIcons.chevronRight, size: 18, color: p.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _textAction(
    String label, {
    required VoidCallback? onPressed,
    required Color color,
    FontWeight weight = FontWeight.w400,
  }) {
    return SizedBox(
      height: 44,
      width: double.infinity,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: color,
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 44),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: OB
              .of(context)
              .text(15, weight: weight, color: color)
              .copyWith(height: 20 / 15),
        ),
      ),
    );
  }
}

class OpenBandNutritionGoalsEditor extends StatefulWidget {
  final OpenBandRepository repository;
  final String day;
  final DateTime Function() now;
  final bool synthetic;
  final NutritionTargetValues? draft;
  const OpenBandNutritionGoalsEditor({
    super.key,
    required this.repository,
    required this.day,
    required this.now,
    this.synthetic = false,
    this.draft,
  });

  @override
  State<OpenBandNutritionGoalsEditor> createState() =>
      _OpenBandNutritionGoalsEditorState();
}

class _OpenBandNutritionGoalsEditorState
    extends State<OpenBandNutritionGoalsEditor> {
  late String _day = widget.day;
  NutritionTargetValues _canonical = const NutritionTargetValues();
  NutritionTargetValues _stored = const NutritionTargetValues();
  int? _revision;
  bool _hadGoals = false;
  bool _percent = false;
  bool _loading = true;
  bool _dateReadError = false;
  bool _saving = false;
  bool _committed = false;
  bool _conflict = false;
  bool _saveError = false;
  String? _percentError;
  final _energy = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();

  bool get _dirty => !nutritionValuesEqual(_canonical, _stored);

  bool get _dateMoved => _day != widget.day;

  bool get _pendingWrite => _dirty || _dateMoved;

  bool get _energyOk {
    final p = parseNutritionGoalNumber(_energy.text);
    if (p.bad) return false;
    if (p.value == null) return true;
    return p.value!.isFinite && p.value! > 0;
  }

  @override
  void initState() {
    super.initState();
    if (widget.draft != null) _canonical = widget.draft!;
    _fillControllers();
    _loadDate(_day, keepDraft: widget.draft != null);
  }

  @override
  void dispose() {
    _energy.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fat.dispose();
    super.dispose();
  }

  void _fillControllers() {
    _energy.text = formatNutritionGoalNumber(_canonical.energyKcal);
    if (_percent) {
      final e = _canonical.energyKcal;
      _protein.text = formatNutritionGoalNumber(
        nutritionPercentOf(_canonical.proteinG, e, kNutritionProteinKcal),
      );
      _carbs.text = formatNutritionGoalNumber(
        nutritionPercentOf(_canonical.carbohydrateG, e, kNutritionCarbKcal),
      );
      _fat.text = formatNutritionGoalNumber(
        nutritionPercentOf(_canonical.fatG, e, kNutritionFatKcal),
      );
    } else {
      _protein.text = formatNutritionGoalNumber(_canonical.proteinG);
      _carbs.text = formatNutritionGoalNumber(_canonical.carbohydrateG);
      _fat.text = formatNutritionGoalNumber(_canonical.fatG);
    }
  }

  Future<void> _loadDate(String day, {required bool keepDraft}) async {
    setState(() {
      _loading = true;
      _dateReadError = false;
      _conflict = false;
      _saveError = false;
      _percentError = null;
    });
    try {
      final snap = await widget.repository.readNutritionTargets(day);
      if (!mounted) return;
      setState(() {
        _day = day;
        _revision = snap.revision;
        _stored = snap.values;
        _hadGoals = snap.origin != null && snap.values.hasAny;
        if (!keepDraft) {
          _canonical = snap.values;
          _fillControllers();
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _day = day;
        _loading = false;
        _dateReadError = true;
      });
    }
  }

  Future<void> _pickDate() async {
    if (_saving || _committed) return;
    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _GoalDatePage(
          initial: _day,
          now: widget.now(),
          synthetic: widget.synthetic,
        ),
      ),
    );
    if (picked == null || !mounted || picked == _day) return;
    await _loadDate(picked, keepDraft: true);
  }

  void _toggle(int i) {
    if (_saving || _committed) return;
    final toPercent = i == 1;
    if (toPercent == _percent) return;
    if (toPercent) {
      final e = parseNutritionGoalNumber(_energy.text);
      if (e.bad || e.value == null || e.value! <= 0) return;
    }
    setState(() {
      _percent = toPercent;
      _percentError = null;
      _fillControllers();
    });
  }

  NutritionTargetValues? _parseGramsDraft() {
    final e = parseNutritionGoalNumber(_energy.text);
    final p = parseNutritionGoalNumber(_protein.text);
    final c = parseNutritionGoalNumber(_carbs.text);
    final f = parseNutritionGoalNumber(_fat.text);
    if (e.bad || p.bad || c.bad || f.bad) return null;
    if (e.value != null && (!e.value!.isFinite || e.value! <= 0)) return null;
    if (p.value != null && (!p.value!.isFinite || p.value! < 0)) return null;
    if (c.value != null && (!c.value!.isFinite || c.value! < 0)) return null;
    if (f.value != null && (!f.value!.isFinite || f.value! < 0)) return null;
    return NutritionTargetValues(
      energyKcal: e.value,
      proteinG: p.value,
      carbohydrateG: c.value,
      fatG: f.value,
    );
  }

  bool _applyEnergy(String raw) {
    final parsed = parseNutritionGoalNumber(raw);
    if (parsed.bad) return false;
    final energy = parsed.value;
    if (energy != null && (!energy.isFinite || energy <= 0)) return false;
    if (_percent) {
      final pp = parseNutritionGoalNumber(_protein.text);
      final cp = parseNutritionGoalNumber(_carbs.text);
      final fp = parseNutritionGoalNumber(_fat.text);
      if (pp.bad || cp.bad || fp.bad) return false;
      _canonical = NutritionTargetValues(
        energyKcal: energy,
        proteinG: nutritionGramsOf(pp.value, energy, kNutritionProteinKcal),
        carbohydrateG: nutritionGramsOf(cp.value, energy, kNutritionCarbKcal),
        fatG: nutritionGramsOf(fp.value, energy, kNutritionFatKcal),
      );
    } else {
      _canonical = NutritionTargetValues(
        energyKcal: energy,
        proteinG: _canonical.proteinG,
        carbohydrateG: _canonical.carbohydrateG,
        fatG: _canonical.fatG,
      );
    }
    return true;
  }

  bool _applyMacro(int which, String raw) {
    final parsed = parseNutritionGoalNumber(raw);
    if (parsed.bad) return false;
    final v = parsed.value;
    if (v != null && !v.isFinite) return false;
    if (_percent) {
      if (v != null && v < 0) return false;
      final e = _canonical.energyKcal;
      double? grams;
      if (v != null) {
        grams = nutritionGramsOf(
          v,
          e,
          which == 0
              ? kNutritionProteinKcal
              : which == 1
              ? kNutritionCarbKcal
              : kNutritionFatKcal,
        );
      }
      _canonical = NutritionTargetValues(
        energyKcal: _canonical.energyKcal,
        proteinG: which == 0 ? grams : _canonical.proteinG,
        carbohydrateG: which == 1 ? grams : _canonical.carbohydrateG,
        fatG: which == 2 ? grams : _canonical.fatG,
      );
    } else {
      if (v != null && v < 0) return false;
      _canonical = NutritionTargetValues(
        energyKcal: _canonical.energyKcal,
        proteinG: which == 0 ? v : _canonical.proteinG,
        carbohydrateG: which == 1 ? v : _canonical.carbohydrateG,
        fatG: which == 2 ? v : _canonical.fatG,
      );
    }
    return true;
  }

  void _onEnergy(String raw) {
    if (_saving || _committed) return;
    setState(() {
      _conflict = false;
      _saveError = false;
      _percentError = null;
      _applyEnergy(raw);
    });
  }

  void _onMacro(int which, String raw) {
    if (_saving || _committed) return;
    setState(() {
      _conflict = false;
      _saveError = false;
      _percentError = null;
      _applyMacro(which, raw);
    });
  }

  bool get _unchangedEmptyStart =>
      !_hadGoals && !_canonical.hasAny && !_stored.hasAny;

  bool get _canAttemptSave =>
      !_saving &&
      !_committed &&
      !_dateReadError &&
      !_unchangedEmptyStart &&
      (_pendingWrite || _hadGoals && !_canonical.hasAny);

  Future<void> _leave() async {
    if (_saving) return;
    if (_committed || !_pendingWrite) {
      Navigator.pop(context, _committed);
      return;
    }
    final discard = await showOpenBandConfirmSheet(
      context: context,
      title: 'Änderungen verwerfen?',
    );
    if (discard == true && mounted) Navigator.pop(context, false);
  }

  Future<void> _save() async {
    if (!_canAttemptSave) return;
    setState(() {
      _saveError = false;
      _conflict = false;
      _percentError = null;
    });
    if (_percent) {
      final e = parseNutritionGoalNumber(_energy.text);
      final p = parseNutritionGoalNumber(_protein.text);
      final c = parseNutritionGoalNumber(_carbs.text);
      final f = parseNutritionGoalNumber(_fat.text);
      if (e.bad ||
          p.bad ||
          c.bad ||
          f.bad ||
          e.value == null ||
          e.value! <= 0 ||
          p.value == null ||
          c.value == null ||
          f.value == null) {
        setState(() => _percentError = 'Die Summe muss 100 % ergeben.');
        return;
      }
      if (!nutritionPercentSumOk(p.value!, c.value!, f.value!)) {
        setState(() => _percentError = 'Die Summe muss 100 % ergeben.');
        return;
      }
    } else {
      if (_parseGramsDraft() == null) return;
    }
    setState(() => _saving = true);
    try {
      final result = _canonical.hasAny
          ? await widget.repository.saveNutritionTargets(
              _day,
              _canonical,
              expectedRevision: _revision,
            )
          : await widget.repository.clearNutritionTargets(
              _day,
              expectedRevision: _revision,
            );
      if (!mounted) return;
      if (result.conflict) {
        setState(() {
          _saving = false;
          _conflict = true;
        });
        return;
      }
      _committed = true;
      try {
        await widget.repository.readNutritionTargets(_day);
        if (!mounted) return;
        Navigator.pop(context, true);
        return;
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _dateReadError = true;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = true;
      });
    }
  }

  Future<void> _reloadConflict() async {
    if (_saving) return;
    if (_dirty) {
      final discard = await showOpenBandConfirmSheet(
        context: context,
        title: 'Änderungen verwerfen?',
        confirmLabel: 'Verwerfen und neu laden',
      );
      if (discard != true || !mounted) return;
    }
    await _loadDate(_day, keepDraft: false);
  }

  String get _footerMakros {
    if (_percent) {
      final p = parseNutritionGoalNumber(_protein.text);
      final c = parseNutritionGoalNumber(_carbs.text);
      final f = parseNutritionGoalNumber(_fat.text);
      if (p.value == null || c.value == null || f.value == null) return '—';
      final sum = p.value! + c.value! + f.value!;
      final n = sum == sum.roundToDouble()
          ? obNumber(sum)
          : obNumber(sum, digits: 0);
      return '${sum == sum.roundToDouble() ? n : formatNutritionGoalNumber(sum)} %';
    }
    final kcal = nutritionMacroKcal(
      proteinG: _canonical.proteinG,
      carbohydrateG: _canonical.carbohydrateG,
      fatG: _canonical.fatG,
    );
    return _kcalLabel(kcal);
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final stacked = _stackGoalInputs(context);
    final percentReady = _energyOk &&
        parseNutritionGoalNumber(_energy.text).value != null;
    return PopScope(
      canPop: !_saving && (!_pendingWrite || _committed),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: p.canvas,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              OBPageHeader(
                title: nutritionGoalsTitle(context),
                subtitle: '',
                onBack: _saving ? null : _leave,
                onInfo: () => showOpenBandJournalInfo(
                  context,
                  title: nutritionGoalsTitle(context),
                  body:
                      'Eigene Tagesziele, keine Bedarfsschätzung.\n'
                      'Änderungen gelten ab dem gewählten Datum. Leere Felder haben kein Ziel.\n'
                      'Die Energie aus Makros kann vom Energieziel abweichen.',
                ),
                infoLabel: 'Ernährungsziele',
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Center(child: CircularProgressIndicator.adaptive()),
                )
              else ...[
                _dateRow(p, stacked),
                const SizedBox(height: 12),
                _energyCard(p, stacked),
                const SizedBox(height: 12),
                _macrosCard(p, stacked, percentReady),
                const SizedBox(height: 12),
                if (_saveError) ...[
                  Text(
                    'Speichern fehlgeschlagen',
                    style: p.text(13, color: p.danger).copyWith(height: 18 / 13),
                  ),
                  const SizedBox(height: 12),
                  OBAction(
                    'Erneut speichern',
                    ink: true,
                    onPressed: _saving ? null : _save,
                  ),
                ] else if (_conflict) ...[
                  Text(
                    'Ziele wurden inzwischen geändert.',
                    style: p.text(13, color: p.danger).copyWith(height: 18 / 13),
                  ),
                  const SizedBox(height: 12),
                  OBAction(
                    'Neu laden',
                    ink: true,
                    secondary: true,
                    onPressed: _saving ? null : _reloadConflict,
                  ),
                  const SizedBox(height: 12),
                  OBAction(
                    'Speichern',
                    ink: true,
                    onPressed: _canAttemptSave ? _save : null,
                  ),
                ] else if (_dateReadError && _committed) ...[
                  OBCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ziele nicht geladen',
                          style: p
                              .text(13, color: p.danger)
                              .copyWith(height: 18 / 13),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () async {
                            try {
                              await widget.repository.readNutritionTargets(_day);
                              if (!context.mounted) return;
                              Navigator.pop(context, true);
                            } catch (_) {}
                          },
                          child: Text(
                            'Erneut',
                            style: p.text(15, weight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (_dateReadError) ...[
                  OBCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ziele nicht geladen',
                          style: p
                              .text(13, color: p.danger)
                              .copyWith(height: 18 / 13),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => _loadDate(_day, keepDraft: true),
                          child: Text(
                            'Erneut',
                            style: p.text(15, weight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else
                  KeyedSubtree(
                    key: const ValueKey('nutrition-goal-save'),
                    child: OBAction(
                      'Speichern',
                      ink: true,
                      onPressed: _canAttemptSave ? _save : null,
                    ),
                  ),
                if (widget.synthetic) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      'Synthetische Daten',
                      style: p.text(12, color: p.muted).copyWith(height: 18 / 12),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _dateRow(OB p, bool stacked) {
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _saving || _committed ? null : _pickDate,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: stacked
              ? Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gültig ab',
                        style: p.text(15).copyWith(height: 20 / 15),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              obDate(_day),
                              style: p
                                  .text(15, weight: FontWeight.w600)
                                  .copyWith(height: 20 / 15),
                            ),
                          ),
                          Icon(LucideIcons.chevronRight, size: 18, color: p.muted),
                        ],
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Gültig ab',
                          style: p.text(15).copyWith(height: 20 / 15),
                        ),
                      ),
                      Text(
                        obDate(_day),
                        style: p
                            .text(15, weight: FontWeight.w600)
                            .copyWith(height: 20 / 15),
                      ),
                      const SizedBox(width: 12),
                      Icon(LucideIcons.chevronRight, size: 18, color: p.muted),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _energyCard(OB p, bool stacked) {
    return OBCard(
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Energie',
                  style: p.text(15, weight: FontWeight.w600).copyWith(height: 20 / 15),
                ),
                const SizedBox(height: 8),
                _GoalNumberField(
                  controller: _energy,
                  unit: 'kcal',
                  stacked: true,
                  enabled: !_saving && !_committed,
                  semanticsLabel: 'Energie',
                  fieldKey: const ValueKey('nutrition-goal-energy'),
                  onChanged: _onEnergy,
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Text(
                    'Energie',
                    style: p
                        .text(15, weight: FontWeight.w600)
                        .copyWith(height: 20 / 15),
                  ),
                ),
                _GoalNumberField(
                  controller: _energy,
                  unit: 'kcal',
                  stacked: false,
                  enabled: !_saving && !_committed,
                  semanticsLabel: 'Energie',
                  fieldKey: const ValueKey('nutrition-goal-energy'),
                  onChanged: _onEnergy,
                ),
              ],
            ),
    );
  }

  Widget _macrosCard(OB p, bool stacked, bool percentReady) {
    Widget row(String label, TextEditingController c, int which, Key key) {
      final field = _GoalNumberField(
        controller: c,
        unit: _percent ? '%' : 'g',
        stacked: stacked,
        enabled: !_saving && !_committed,
        semanticsLabel: label,
        fieldKey: key,
        onChanged: (raw) => _onMacro(which, raw),
      );
      if (stacked) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: p.text(15, weight: FontWeight.w600).copyWith(height: 20 / 15),
            ),
            const SizedBox(height: 8),
            field,
          ],
        );
      }
      return SizedBox(
        height: 56,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: p.text(15, weight: FontWeight.w600).copyWith(height: 20 / 15),
              ),
            ),
            field,
          ],
        ),
      );
    }

    return OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Text(
                  'Makronährstoffe',
                  maxLines: 1,
                  softWrap: false,
                  style: p
                      .text(15, weight: FontWeight.w600)
                      .copyWith(height: 20 / 15),
                ),
                OBSegmented(
                  compact: true,
                  labels: const ['g', '%'],
                  selected: _percent ? 1 : 0,
                  enabled: [
                    !_saving && !_committed,
                    percentReady && !_saving && !_committed,
                  ],
                  onChanged: _toggle,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          row('Eiweiß', _protein, 0, const ValueKey('nutrition-goal-protein')),
          const SizedBox(height: 12),
          row(
            'Kohlenhydrate',
            _carbs,
            1,
            const ValueKey('nutrition-goal-carbs'),
          ),
          const SizedBox(height: 12),
          row('Fett', _fat, 2, const ValueKey('nutrition-goal-fat')),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: p.line)),
            ),
            padding: const EdgeInsets.only(top: 12),
            constraints: const BoxConstraints(minHeight: 32),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _percent ? 'Summe' : 'Makros',
                    style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
                  ),
                ),
                Text(_footerMakros, style: p.text(13).copyWith(height: 18 / 13)),
              ],
            ),
          ),
          if (_percentError != null) ...[
            const SizedBox(height: 8),
            Text(
              _percentError!,
              style: p.text(13, color: p.danger).copyWith(height: 18 / 13),
            ),
          ],
        ],
      ),
    );
  }
}

class _GoalNumberField extends StatelessWidget {
  final TextEditingController controller;
  final String unit;
  final bool stacked;
  final bool enabled;
  final String semanticsLabel;
  final Key fieldKey;
  final ValueChanged<String> onChanged;
  const _GoalNumberField({
    required this.controller,
    required this.unit,
    required this.stacked,
    required this.enabled,
    required this.semanticsLabel,
    required this.fieldKey,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    const valueSize = 28.0;
    const valueHeight = 34.0;
    const unitSize = 13.0;
    const unitHeight = 18.0;
    final empty = controller.text.isEmpty;
    final style = p
        .text(valueSize, weight: FontWeight.w700, display: true)
        .copyWith(
          height: valueHeight / valueSize,
          color: empty ? p.muted : p.ink,
        );
    return Container(
      width: stacked ? double.infinity : 146,
      constraints: BoxConstraints(minHeight: stacked ? 90 : 56),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: p.well,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Semantics(
              label: semanticsLabel,
              textField: true,
              child: TextField(
                key: fieldKey,
                controller: controller,
                enabled: enabled,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textAlign: TextAlign.end,
                style: style,
                cursorColor: p.ink,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintText: '—',
                  hintStyle: style.copyWith(color: p.muted),
                ),
                onChanged: onChanged,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            unit,
            style: p
                .text(unitSize, color: p.muted)
                .copyWith(height: unitHeight / unitSize),
          ),
        ],
      ),
    );
  }
}

class OpenBandNutritionGoalHistory extends StatefulWidget {
  final OpenBandRepository repository;
  final String day;
  final DateTime Function() now;
  final bool synthetic;
  final NutritionTargetValues? current;
  const OpenBandNutritionGoalHistory({
    super.key,
    required this.repository,
    required this.day,
    required this.now,
    this.synthetic = false,
    this.current,
  });

  @override
  State<OpenBandNutritionGoalHistory> createState() =>
      _OpenBandNutritionGoalHistoryState();
}

class _OpenBandNutritionGoalHistoryState
    extends State<OpenBandNutritionGoalHistory> {
  List<NutritionTargetChange>? _rows;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final rows = await widget.repository.listNutritionTargetChanges();
      if (!mounted) return;
      setState(() => _rows = rows.reversed.toList());
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = true);
    }
  }

  Future<void> _open(NutritionTargetChange row) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => OpenBandNutritionGoalsEditor(
          repository: widget.repository,
          day: row.validFromDay,
          now: widget.now,
          synthetic: widget.synthetic,
        ),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _plan() async {
    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _GoalDatePage(
          initial: widget.day,
          now: widget.now(),
          synthetic: widget.synthetic,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => OpenBandNutritionGoalsEditor(
          repository: widget.repository,
          day: picked,
          now: widget.now,
          synthetic: widget.synthetic,
          draft: widget.current,
        ),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final today = dayLabelOf(widget.now());
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const OBPageHeader(title: 'Zielverlauf', subtitle: ''),
            if (_error != null)
              OBCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Ziele nicht geladen',
                      style: p.text(13, color: p.danger).copyWith(height: 18 / 13),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 44,
                      width: double.infinity,
                      child: TextButton(
                        onPressed: _load,
                        style: TextButton.styleFrom(
                          foregroundColor: p.ink,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(44, 44),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Erneut',
                          textAlign: TextAlign.center,
                          style: p
                              .text(15, weight: FontWeight.w600)
                              .copyWith(height: 20 / 15),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (_rows == null)
              const Center(child: CircularProgressIndicator.adaptive())
            else ...[
              for (final row in _rows!) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _HistoryCard(
                    row: row,
                    planned: row.validFromDay.compareTo(today) > 0,
                    onTap: () => _open(row),
                  ),
                ),
              ],
              OBAction(
                'Änderung planen',
                ink: true,
                onPressed: _plan,
              ),
            ],
            if (widget.synthetic) ...[
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Synthetische Daten',
                  style: p.text(12, color: p.muted).copyWith(height: 18 / 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final NutritionTargetChange row;
  final bool planned;
  final VoidCallback onTap;
  const _HistoryCard({
    required this.row,
    required this.planned,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final v = row.values;
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      obDate(row.validFromDay),
                      style: p
                          .text(15, weight: FontWeight.w600)
                          .copyWith(height: 20 / 15),
                    ),
                  ),
                  if (planned) ...[
                    const SizedBox(width: 12),
                    Text(
                      'Geplant',
                      style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
                    ),
                  ],
                  const SizedBox(width: 12),
                  Icon(LucideIcons.chevronRight, size: 18, color: p.muted),
                ],
              ),
              const SizedBox(height: 12),
              if (!v.hasAny)
                Text(
                  'Keine Ziele',
                  style: p
                      .text(28, weight: FontWeight.w700, display: true)
                      .copyWith(height: 34 / 28),
                )
              else ...[
                Text(
                  _kcalLabel(v.energyKcal),
                  style: p
                      .text(28, weight: FontWeight.w700, display: true)
                      .copyWith(height: 34 / 28),
                ),
                const SizedBox(height: 12),
                _histMacro('Eiweiß', _gramLabel(v.proteinG)),
                _histMacro('Kohlenhydrate', _gramLabel(v.carbohydrateG)),
                _histMacro('Fett', _gramLabel(v.fatG)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _histMacro(String label, String value) {
    return Builder(
      builder: (context) {
        final p = OB.of(context);
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: p.text(12, color: p.muted).copyWith(height: 18 / 12),
                ),
              ),
              Text(value, style: p.text(15).copyWith(height: 20 / 15)),
            ],
          ),
        );
      },
    );
  }
}

class _GoalDatePage extends StatefulWidget {
  final String initial;
  final DateTime now;
  final bool synthetic;
  const _GoalDatePage({
    required this.initial,
    required this.now,
    required this.synthetic,
  });

  @override
  State<_GoalDatePage> createState() => _GoalDatePageState();
}

class _GoalDatePageState extends State<_GoalDatePage> {
  late DateTime selected = DateTime.parse(widget.initial);
  late DateTime month = DateTime(selected.year, selected.month);

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final day = dayLabelOf(selected);
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const OBPageHeader(title: 'Gültig ab', subtitle: ''),
            OBCard(
              padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
              child: OBCalendar(
                month: month,
                selected: selected,
                now: widget.now,
                allowFuture: true,
                onSelect: (date) => setState(() {
                  selected = date;
                  month = DateTime(date.year, date.month);
                }),
                onPrevMonth: () => setState(
                  () => month = DateTime(month.year, month.month - 1),
                ),
                onNextMonth: () => setState(
                  () => month = DateTime(month.year, month.month + 1),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OBAction(
              '${obDate(day)} übernehmen',
              ink: true,
              onPressed: () => Navigator.pop(context, day),
            ),
            if (widget.synthetic) ...[
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Synthetische Daten',
                  style: p.text(12, color: p.muted).copyWith(height: 18 / 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
