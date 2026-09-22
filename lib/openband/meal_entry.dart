import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/day_label.dart';
import 'alp_tokens.dart';
import 'calendar.dart';
import 'confirm_sheet.dart';
import 'domain.dart';
import 'nutrition_goals.dart';
import 'settings_controls.dart';
import 'theme.dart';
import 'time.dart';

class FoodEntryRouteResult {
  final bool changed;
  final FoodEntry? removed;
  const FoodEntryRouteResult({this.changed = false, this.removed});
}

Future<FoodEntryRouteResult?> openOpenBandFoodEntry(
  BuildContext context, {
  required OpenBandRepository repository,
  required String id,
  required String day,
  bool synthetic = false,
  DateTime Function()? now,
  String? zone,
}) {
  return Navigator.of(context).push<FoodEntryRouteResult>(
    MaterialPageRoute(
      builder: (_) => OpenBandFoodEntry(
        repository: repository,
        id: id,
        day: day,
        synthetic: synthetic,
        now: now,
        zone: zone,
      ),
    ),
  );
}

class OpenBandFoodEntry extends StatefulWidget {
  final OpenBandRepository repository;
  final String id;
  final String day;
  final bool synthetic;
  final DateTime Function() now;
  final String? zone;
  // ignore: prefer_const_constructors_in_immutables
  OpenBandFoodEntry({
    super.key,
    required this.repository,
    required this.id,
    required this.day,
    this.synthetic = false,
    DateTime Function()? now,
    this.zone,
  }) : now = now ?? DateTime.now;

  @override
  State<OpenBandFoodEntry> createState() => _OpenBandFoodEntryState();
}

enum _Pane { loading, error, missing, detail, editor, nutrients }

const _meals = [
  ('breakfast', 'Frühstück'),
  ('lunch', 'Mittag'),
  ('dinner', 'Abend'),
  ('snack', 'Zwischendurch'),
];

const _nutrients = [
  (key: 'kcal', label: 'Energie', unit: 'kcal'),
  (key: 'proteinG', label: 'Eiweiß', unit: 'g'),
  (key: 'carbsG', label: 'Kohlenhydrate', unit: 'g'),
  (key: 'fatG', label: 'Fett', unit: 'g'),
  (key: 'fibreG', label: 'Ballaststoffe', unit: 'g'),
  (key: 'sugarG', label: 'Zucker', unit: 'g'),
  (key: 'satFatG', label: 'Gesättigte Fettsäuren', unit: 'g'),
  (key: 'sodiumMg', label: 'Natrium', unit: 'mg'),
  (key: 'ironMg', label: 'Eisen', unit: 'mg'),
  (key: 'calciumMg', label: 'Calcium', unit: 'mg'),
];

class _OpenBandFoodEntryState extends State<OpenBandFoodEntry> {
  _Pane _pane = _Pane.loading;
  FoodEntry? _stored;
  FoodEntry? _draft;
  FoodEntry? _acked;
  bool _busy = false;
  bool _changed = false;
  bool _saveError = false;
  bool _conflict = false;
  bool _removeError = false;
  bool _expanded = false;
  int _readSeq = 0;
  String? _timeError;
  String? _dateAttempt;
  final _name = TextEditingController();
  final _note = TextEditingController();
  final _nutrientCtrls = <String, TextEditingController>{
    for (final n in _nutrients) n.key: TextEditingController(),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant OpenBandFoodEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id ||
        oldWidget.repository != widget.repository) {
      _load();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    for (final c in _nutrientCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  String get _navDay => _stored?.date ?? widget.day;

  bool _childCurrent(int seq, OpenBandRepository repo, String id) =>
      mounted &&
      seq == _readSeq &&
      widget.repository == repo &&
      widget.id == id;

  String get _displayDate => _dateAttempt ?? (_draft ?? _stored)?.date ?? widget.day;

  DateTime? _wallClock(int? atTs) {
    if (atTs == null) return null;
    return recordedTime(
      DateTime.fromMillisecondsSinceEpoch(atTs * 1000),
      widget.zone,
    );
  }

  Future<void> _load({bool fromRetry = false}) async {
    final seq = ++_readSeq;
    final repo = widget.repository;
    final id = widget.id;
    setState(() {
      _busy = true;
      if (!fromRetry) _pane = _Pane.loading;
    });
    try {
      final result = await repo.readFoodEntry(id);
      if (!mounted || seq != _readSeq) return;
      if (result.missing) {
        setState(() {
          _busy = false;
          _stored = null;
          _draft = null;
          _pane = _Pane.missing;
        });
        return;
      }
      final current = result.current;
      if (current == null) {
        setState(() {
          _busy = false;
          _pane = _Pane.error;
        });
        return;
      }
      _applyLoaded(current);
    } catch (_) {
      if (!mounted || seq != _readSeq) return;
      setState(() {
        _busy = false;
        _pane = _Pane.error;
      });
    }
  }

  void _applyLoaded(FoodEntry current) {
    _stored = current;
    _draft = current;
    _acked = null;
    _saveError = false;
    _conflict = false;
    _removeError = false;
    _timeError = null;
    _dateAttempt = null;
    _syncEditorFields(current);
    _busy = false;
    _pane = _Pane.detail;
    setState(() {});
  }

  void _syncEditorFields(FoodEntry e) {
    _name.text = e.label;
    _note.text = e.note;
  }

  void _popRoute() {
    Navigator.pop(
      context,
      FoodEntryRouteResult(changed: _changed, removed: null),
    );
  }

  Future<void> _back() async {
    if (_busy) return;
    switch (_pane) {
      case _Pane.loading:
      case _Pane.error:
      case _Pane.missing:
      case _Pane.detail:
        _popRoute();
      case _Pane.editor:
        await _leaveEditor();
      case _Pane.nutrients:
        setState(() => _pane = _Pane.editor);
    }
  }

  bool get _editorDirty {
    final stored = _stored, draft = _draft;
    if (stored == null || draft == null) return false;
    return !foodEntriesEqual(_editorSnapshot(), stored);
  }

  FoodEntry _editorSnapshot() {
    final base = _draft ?? _stored!;
    return _copy(
      base,
      label: _name.text,
      note: _note.text,
    );
  }

  Future<void> _leaveEditor() async {
    if (_busy) return;
    if (_editorDirty) {
      final seq = _readSeq;
      final repo = widget.repository;
      final id = widget.id;
      final discard = await showOpenBandConfirmSheet(
        context: context,
        title: 'Änderungen verwerfen?',
      );
      if (discard != true || !_childCurrent(seq, repo, id)) return;
      _draft = _stored;
      if (_stored != null) _syncEditorFields(_stored!);
      _saveError = false;
      _timeError = null;
      _dateAttempt = null;
    }
    setState(() => _pane = _Pane.detail);
  }

  void _openEditor() {
    if (_busy || _stored == null) return;
    _draft = _stored;
    _acked = null;
    _saveError = false;
    _timeError = null;
    _dateAttempt = null;
    _syncEditorFields(_stored!);
    setState(() => _pane = _Pane.editor);
  }

  void _openNutrients() {
    final draft = _editorSnapshot();
    _draft = draft;
    for (final n in _nutrients) {
      _nutrientCtrls[n.key]!.text = formatNutritionGoalNumber(
        _nutrientOf(draft, n.key),
      );
    }
    setState(() => _pane = _Pane.nutrients);
  }

  void _openQuantity() {
    if (_busy) return;
    final draft = _editorSnapshot();
    _draft = draft;
    setState(() {});
    _showQuantitySheet(draft);
  }

  Future<void> _showQuantitySheet(FoodEntry baseline) async {
    final seq = _readSeq;
    final repo = widget.repository;
    final id = widget.id;
    final next = await showModalBottomSheet<FoodEntry>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _FoodQuantitySheet(baseline: baseline),
    );
    if (next == null || !_childCurrent(seq, repo, id)) return;
    setState(() => _draft = next);
  }

  Future<void> _pickMeal() async {
    if (_busy) return;
    final current = _editorSnapshot();
    final seq = _readSeq;
    final repo = widget.repository;
    final id = widget.id;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (context) {
        final p = OB.of(context);
        return Material(
          color: p.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final meal in _meals)
                    OBSettingsChoiceRow(
                      label: meal.$2,
                      selected: meal.$1 == current.meal,
                      onTap: () => Navigator.pop(context, meal.$1),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (picked == null || !_childCurrent(seq, repo, id)) return;
    setState(() => _draft = _copy(current, meal: picked));
  }

  Future<void> _pickDate() async {
    if (_busy) return;
    final current = _editorSnapshot();
    final seq = _readSeq;
    final repo = widget.repository;
    final id = widget.id;
    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _FoodDatePage(
          initial: _displayDate,
          now: widget.now(),
          synthetic: widget.synthetic,
        ),
      ),
    );
    if (picked == null || !_childCurrent(seq, repo, id)) return;
    if (picked == current.date) {
      setState(() {
        _dateAttempt = null;
        _timeError = null;
      });
      return;
    }
    final relocated = _relocateTime(current.atTs, picked);
    if (current.atTs != null && relocated == null) {
      setState(() {
        _dateAttempt = picked;
        _timeError = 'Uhrzeit ungültig';
      });
      return;
    }
    setState(() {
      _dateAttempt = null;
      _timeError = null;
      _draft = _copy(
        current,
        date: picked,
        atTs: relocated,
        clearAtTs: current.atTs == null,
      );
    });
  }

  int? _relocateTime(int? atTs, String toDay) {
    if (atTs == null) return null;
    final previous = DateTime.fromMillisecondsSinceEpoch(atTs * 1000);
    final wall = recordedTime(previous, widget.zone);
    final text =
        '${wall.hour.toString().padLeft(2, '0')}:${wall.minute.toString().padLeft(2, '0')}';
    final parsed = _foodRecordedTime(
      toDay,
      text,
      previous: previous,
      zone: widget.zone,
    );
    if (parsed == null) return null;
    return parsed.millisecondsSinceEpoch ~/ 1000;
  }

  Future<void> _pickTime() async {
    if (_busy) return;
    final current = _editorSnapshot();
    final seq = _readSeq;
    final repo = widget.repository;
    final id = widget.id;
    final targetDate = _dateAttempt ?? current.date;
    final result = await showModalBottomSheet<_FoodTimeResult>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _FoodTimeSheet(
        date: targetDate,
        initial: _wallClock(current.atTs),
        previous: current.atTs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(current.atTs! * 1000),
        zone: widget.zone,
      ),
    );
    if (result == null || !_childCurrent(seq, repo, id)) return;
    if (result.clear) {
      setState(() {
        _timeError = null;
        _dateAttempt = null;
        _draft = _copy(
          current,
          date: targetDate,
          clearAtTs: true,
        );
      });
      return;
    }
    if (result.at == null) return;
    setState(() {
      _timeError = null;
      _dateAttempt = null;
      _draft = _copy(
        current,
        date: targetDate,
        atTs: result.at!.millisecondsSinceEpoch ~/ 1000,
      );
    });
  }

  bool get _nutrientsValid {
    for (final n in _nutrients) {
      final parsed = parseNutritionGoalNumber(_nutrientCtrls[n.key]!.text);
      if (parsed.bad) return false;
      if (parsed.value != null && parsed.value! < 0) return false;
    }
    return true;
  }

  bool get _nutrientsChanged {
    final draft = _draft ?? _stored;
    if (draft == null) return false;
    for (final n in _nutrients) {
      final parsed = parseNutritionGoalNumber(_nutrientCtrls[n.key]!.text);
      if (parsed.value != _nutrientOf(draft, n.key)) return true;
    }
    return false;
  }

  void _applyNutrients({bool confirmPhoto = false}) {
    if (_busy || !_nutrientsValid) return;
    var next = _editorSnapshot();
    double? read(String key) {
      final parsed = parseNutritionGoalNumber(_nutrientCtrls[key]!.text);
      return parsed.value;
    }

    next = _copy(
      next,
      kcal: read('kcal'),
      proteinG: read('proteinG'),
      carbsG: read('carbsG'),
      fatG: read('fatG'),
      fibreG: read('fibreG'),
      sugarG: read('sugarG'),
      satFatG: read('satFatG'),
      sodiumMg: read('sodiumMg'),
      ironMg: read('ironMg'),
      calciumMg: read('calciumMg'),
      clearKcal: read('kcal') == null,
      clearProtein: read('proteinG') == null,
      clearCarbs: read('carbsG') == null,
      clearFat: read('fatG') == null,
      clearFibre: read('fibreG') == null,
      clearSugar: read('sugarG') == null,
      clearSatFat: read('satFatG') == null,
      clearSodium: read('sodiumMg') == null,
      clearIron: read('ironMg') == null,
      clearCalcium: read('calciumMg') == null,
      confirmed: confirmPhoto ? true : null,
    );
    setState(() {
      _draft = next;
      _pane = _Pane.editor;
    });
  }

  bool get _photoUnconfirmed {
    final e = _draft ?? _stored;
    return e != null && e.source == FoodSource.photo && !e.confirmed;
  }

  bool get _canSave {
    if (_busy || _conflict) return false;
    if (_timeError != null || _dateAttempt != null) return false;
    final next = _editorSnapshot();
    if (next.label.trim().isEmpty) return false;
    final stored = _stored;
    if (stored != null && foodEntriesEqual(next, stored)) return false;
    if (_acked != null && foodEntriesEqual(next, _acked!)) return false;
    return true;
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final expected = _stored;
    if (expected == null) return;
    final next = _editorSnapshot();
    final seq = _readSeq;
    setState(() {
      _busy = true;
      _saveError = false;
      _draft = next;
    });
    try {
      final result = await widget.repository.saveFoodEntry(expected, next);
      if (!mounted || seq != _readSeq) return;
      if (result.saved) {
        final current = result.current;
        if (current == null) {
          setState(() {
            _busy = false;
            _saveError = true;
          });
          return;
        }
        setState(() {
          _busy = false;
          _stored = current;
          _draft = current;
          _acked = current;
          _changed = true;
          _saveError = false;
          _conflict = false;
          _syncEditorFields(current);
          _pane = _Pane.detail;
        });
        return;
      }
      setState(() {
        _busy = false;
        _conflict = true;
      });
    } catch (_) {
      if (!mounted || seq != _readSeq) return;
      setState(() {
        _busy = false;
        _saveError = true;
      });
    }
  }

  Future<void> _reloadConflict() async {
    if (_busy) return;
    if (_editorDirty) {
      final discard = await showOpenBandConfirmSheet(
        context: context,
        title: 'Änderungen verwerfen?',
      );
      if (discard != true || !mounted) return;
    }
    await _load(fromRetry: true);
  }

  Future<void> _remove() async {
    if (_busy || _stored == null) return;
    final expected = _stored!;
    final seq = _readSeq;
    final repo = widget.repository;
    final id = widget.id;
    final confirm = await showOpenBandConfirmSheet(
      context: context,
      title: 'Eintrag entfernen?',
      confirmLabel: 'Entfernen',
      cancelLabel: 'Abbrechen',
    );
    if (confirm != true || !_childCurrent(seq, repo, id)) return;
    setState(() {
      _busy = true;
      _removeError = false;
    });
    try {
      final result = await repo.removeFoodEntry(expected);
      if (!_childCurrent(seq, repo, id)) return;
      if (result.saved) {
        final receipt = result.current ?? expected;
        if (!mounted) return;
        Navigator.pop(
          context,
          FoodEntryRouteResult(changed: true, removed: receipt),
        );
        return;
      }
      setState(() {
        _busy = false;
        _conflict = true;
        _removeError = true;
      });
    } catch (_) {
      if (!_childCurrent(seq, repo, id)) return;
      setState(() {
        _busy = false;
        _removeError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: p.canvas,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _header(p),
              ),
              Expanded(child: _body(p)),
              if (_pane == _Pane.editor || _pane == _Pane.nutrients)
                _bottomBar(p),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(OB p) {
    final day = _navDay;
    switch (_pane) {
      case _Pane.editor:
        return OBPageHeader(
          title: 'Eintrag bearbeiten',
          subtitle: obDate(day),
          onBack: _busy ? null : _back,
        );
      case _Pane.nutrients:
        return OBPageHeader(
          title: 'Nährwerte',
          subtitle: _name.text.trim().isEmpty
              ? (_draft ?? _stored)?.label ?? ''
              : _name.text.trim(),
          onBack: _busy ? null : _back,
        );
      default:
        return OBPageHeader(
          title: 'Eintrag',
          subtitle: isLabCalendarDay(day) ? obDate(day) : day,
          onBack: _busy ? null : _back,
          onInfo: _pane == _Pane.detail && !_busy ? _openEditor : null,
          infoLabel: 'Bearbeiten',
          infoIcon: LucideIcons.pencil,
        );
    }
  }

  Widget _body(OB p) {
    final Widget child;
    switch (_pane) {
      case _Pane.loading:
        child = const Center(child: CircularProgressIndicator.adaptive());
      case _Pane.error:
        child = _statusCard(
          p,
          title: 'Eintrag nicht geladen',
          icon: LucideIcons.circleAlert,
          danger: true,
          action: 'Erneut versuchen',
          onAction: _busy ? null : () => _load(fromRetry: true),
        );
      case _Pane.missing:
        child = _statusCard(
          p,
          title: 'Eintrag nicht gefunden',
          icon: LucideIcons.info,
        );
      case _Pane.detail:
        child = _detail(p);
      case _Pane.editor:
        child = _editor(p);
      case _Pane.nutrients:
        child = _nutrientEditor(p);
    }
    return KeyedSubtree(
      key: ValueKey('food-body-${widget.id}-${_pane.name}'),
      child: child,
    );
  }

  Widget _statusCard(
    OB p, {
    required String title,
    required IconData icon,
    bool danger = false,
    String? action,
    VoidCallback? onAction,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        OBCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: danger ? p.danger : p.muted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: p
                          .text(15, weight: FontWeight.w600)
                          .copyWith(height: 20 / 15),
                    ),
                  ),
                ],
              ),
              if (action != null) ...[
                const SizedBox(height: 16),
                OBAction(action, ink: true, onPressed: onAction),
              ],
            ],
          ),
        ),
        if (widget.synthetic) _syntheticCaption(p),
      ],
    );
  }

  Widget _detail(OB p) {
    final e = _stored!;
    final kcal = _displayNutrient(e, e.kcal);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        OBCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _mealLabel(e.meal),
                style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
              ),
              const SizedBox(height: 12),
              Text(
                e.label,
                style: p
                    .text(30, weight: FontWeight.w700, display: true)
                    .copyWith(height: 34 / 30),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    _qty(kcal),
                    style: p
                        .text(48, weight: FontWeight.w700, display: true)
                        .copyWith(height: 52 / 48),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'kcal',
                    style: p.text(15, color: p.muted).copyWith(height: 20 / 15),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _macroSummary(p, e),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        OBCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              _metaRow(p, 'Menge', _quantityLabel(e)),
              Divider(height: 1, thickness: 1, color: p.line),
              _metaRow(p, 'Uhrzeit', _timeLabel(e, widget.zone)),
              Divider(height: 1, thickness: 1, color: p.line),
              _metaRow(
                p,
                'Quelle',
                _sourceLabel(e),
                semantics: e.source == FoodSource.unknown
                    ? 'Quelle Unbekannt ${e.sourceCode}'
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        OBCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 56),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Weitere Nährwerte',
                              style: p.text(15).copyWith(height: 20 / 15),
                            ),
                          ),
                          Icon(
                            _expanded
                                ? LucideIcons.chevronDown
                                : LucideIcons.chevronRight,
                            size: 18,
                            color: p.muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_expanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    children: [
                      for (final n in _nutrients.skip(4)) ...[
                        Divider(height: 1, thickness: 1, color: p.line),
                        _metaRow(
                          p,
                          n.label,
                          _unitValue(
                            _displayNutrient(e, _nutrientOf(e, n.key)),
                            n.unit,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_removeError || (_conflict && _pane == _Pane.detail)) ...[
          Row(
            children: [
              Icon(LucideIcons.circleAlert, size: 20, color: p.danger),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _conflict
                      ? 'Eintrag wurde geändert'
                      : 'Speichern fehlgeschlagen',
                  style: p.text(14, color: p.danger).copyWith(height: 20 / 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_conflict)
            OBAction(
              'Neu laden',
              ink: true,
              onPressed: _busy ? null : () => _load(fromRetry: true),
            )
          else
            const SizedBox.shrink(),
          const SizedBox(height: 12),
        ],
        SizedBox(
          height: 48,
          child: TextButton(
            key: const ValueKey('food-entry-remove'),
            onPressed: _busy ? null : _remove,
            child: Text(
              'Eintrag entfernen',
              style: p
                  .text(15, weight: FontWeight.w600, color: p.danger)
                  .copyWith(height: 20 / 15),
            ),
          ),
        ),
        if (widget.synthetic) _syntheticCaption(p),
      ],
    );
  }

  Widget _macroSummary(OB p, FoodEntry e) {
    final macros = [
      ('Eiweiß', _displayNutrient(e, e.proteinG)),
      ('Fett', _displayNutrient(e, e.fatG)),
      ('Kohlenhydrate', _displayNutrient(e, e.carbsG)),
    ];
    final labelStyle = p.text(12, color: p.muted).copyWith(height: 16 / 12);
    final valueStyle = p.text(17, weight: FontWeight.w600).copyWith(height: 22 / 17);
    if (_stack(context)) {
      return Column(
        children: [
          for (final (i, macro) in macros.indexed) ...[
            if (i > 0) const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text(macro.$1, style: labelStyle)),
                const SizedBox(width: 12),
                Text(_grams(macro.$2), style: valueStyle),
              ],
            ),
          ],
        ],
      );
    }
    return Row(
      children: [
        for (final (i, macro) in macros.indexed) ...[
          if (i > 0) const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(macro.$1, style: labelStyle),
                const SizedBox(height: 4),
                Text(_grams(macro.$2), style: valueStyle),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _editor(OB p) {
    final draft = _editorSnapshot();
    final stacked = _stack(context);
    final kcal = _qty(draft.kcal);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        OBCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Lebensmittel',
                style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('food-entry-name'),
                controller: _name,
                enabled: !_busy,
                style: p.text(17).copyWith(height: 24 / 17),
                cursorColor: p.ink,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        OBCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              _choiceRow(
                p,
                label: 'Mahlzeit',
                value: _mealLabel(draft.meal),
                stacked: stacked,
                onTap: _busy ? null : _pickMeal,
              ),
              Divider(height: 1, thickness: 1, color: p.line),
              _choiceRow(
                p,
                label: 'Datum',
                value: obDate(_dateAttempt ?? draft.date),
                stacked: stacked,
                onTap: _busy ? null : _pickDate,
              ),
              Divider(height: 1, thickness: 1, color: p.line),
              _choiceRow(
                p,
                label: 'Menge',
                value: _quantityLabel(draft),
                stacked: stacked,
                onTap: _busy ? null : _openQuantity,
              ),
              Divider(height: 1, thickness: 1, color: p.line),
              _choiceRow(
                p,
                label: 'Uhrzeit',
                value: _timeLabel(draft, widget.zone),
                stacked: stacked,
                onTap: _busy ? null : _pickTime,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Material(
          color: p.card,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _busy ? null : _openNutrients,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 72),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: stacked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nährwerte',
                            style: p.text(15).copyWith(height: 20 / 15),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(
                                kcal,
                                style: p
                                    .text(
                                      28,
                                      weight: FontWeight.w700,
                                      display: true,
                                    )
                                    .copyWith(height: 34 / 28),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'kcal',
                                style: p
                                    .text(13, color: p.muted)
                                    .copyWith(height: 18 / 13),
                              ),
                              const Spacer(),
                              Icon(
                                LucideIcons.chevronRight,
                                size: 16,
                                color: p.muted,
                              ),
                            ],
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Nährwerte',
                              style: p.text(15).copyWith(height: 20 / 15),
                            ),
                          ),
                          Text(
                            kcal,
                            style: p
                                .text(28, weight: FontWeight.w700, display: true)
                                .copyWith(height: 34 / 28),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'kcal',
                            style: p
                                .text(13, color: p.muted)
                                .copyWith(height: 18 / 13),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            LucideIcons.chevronRight,
                            size: 16,
                            color: p.muted,
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        OBCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Notiz',
                style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('food-entry-note'),
                controller: _note,
                enabled: !_busy,
                minLines: 2,
                maxLines: 4,
                style: p
                    .text(15, color: _note.text.isEmpty ? p.muted : p.ink)
                    .copyWith(height: 20 / 15),
                cursorColor: p.ink,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintText: '—',
                  hintStyle: p.text(15, color: p.muted).copyWith(height: 20 / 15),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
        if (widget.synthetic) _syntheticCaption(p),
      ],
    );
  }

  Widget _nutrientEditor(OB p) {
    final stacked = _stack(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (_photoUnconfirmed) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
            child: Text(
              'Foto · unbestätigt',
              style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
            ),
          ),
          const SizedBox(height: 12),
        ],
        OBCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              for (var i = 0; i < _nutrients.length; i++) ...[
                if (i > 0) Divider(height: 1, thickness: 1, color: p.line),
                _FoodNutrientRow(
                  label: _nutrients[i].label,
                  unit: _nutrients[i].unit,
                  controller: _nutrientCtrls[_nutrients[i].key]!,
                  stacked: stacked,
                  enabled: !_busy,
                  fieldKey: ValueKey('food-nutrient-${_nutrients[i].key}'),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _bottomBar(OB p) {
    final error = _timeError ??
        (_saveError
            ? 'Speichern fehlgeschlagen'
            : _conflict
            ? 'Eintrag wurde geändert'
            : null);
    final confirmPhoto = _pane == _Pane.nutrients && _photoUnconfirmed;
    final action = _pane == _Pane.nutrients
        ? OBAction(
            confirmPhoto ? 'Werte bestätigen' : 'Übernehmen',
            ink: true,
            onPressed: !_busy && _nutrientsValid
                ? (confirmPhoto
                      ? () => _applyNutrients(confirmPhoto: true)
                      : (_nutrientsChanged ? _applyNutrients : null))
                : null,
          )
        : _conflict
        ? OBAction(
            'Neu laden',
            ink: true,
            onPressed: _busy ? null : _reloadConflict,
          )
        : KeyedSubtree(
            key: const ValueKey('food-entry-save'),
            child: OBAction(
              _saveError ? 'Erneut versuchen' : 'Speichern',
              ink: true,
              onPressed: _canSave ? _save : null,
            ),
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 12),
                child: Row(
                  children: [
                    Icon(LucideIcons.circleAlert, size: 20, color: p.danger),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        error,
                        style: p
                            .text(14, color: p.danger)
                            .copyWith(height: 20 / 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          action,
        ],
      ),
    );
  }

  Widget _metaRow(OB p, String label, String value, {String? semantics}) {
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          Expanded(child: Text(label, style: p.text(15).copyWith(height: 20 / 15))),
          Text(value, style: p.text(15).copyWith(height: 20 / 15)),
        ],
      ),
    );
    if (semantics == null) return row;
    return Semantics(
      container: true,
      label: semantics,
      child: ExcludeSemantics(child: row),
    );
  }

  Widget _choiceRow(
    OB p, {
    required String label,
    required String value,
    required bool stacked,
    VoidCallback? onTap,
  }) {
    final chevron = Icon(LucideIcons.chevronRight, size: 16, color: p.muted);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: stacked
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: p.text(15).copyWith(height: 20 / 15)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              value,
                              style: p.text(15).copyWith(height: 20 / 15),
                            ),
                          ),
                          chevron,
                        ],
                      ),
                    ],
                  ),
                )
              : Row(
                  children: [
                    Expanded(
                      child: Text(label, style: p.text(15).copyWith(height: 20 / 15)),
                    ),
                    Text(value, style: p.text(15).copyWith(height: 20 / 15)),
                    const SizedBox(width: 12),
                    chevron,
                  ],
                ),
        ),
      ),
    );
  }

  Widget _syntheticCaption(OB p) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Center(
      child: Text(
        'Synthetische Daten',
        style: p.text(12, color: p.muted).copyWith(height: 18 / 12),
      ),
    ),
  );
}

class _FoodTimeResult {
  final DateTime? at;
  final bool clear;
  const _FoodTimeResult({this.at, this.clear = false});
}

class _FoodSheetScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final Key? scrollKey;
  final VoidCallback? onApply;
  final String? clearLabel;
  final VoidCallback? onClear;
  final String? error;
  const _FoodSheetScaffold({
    required this.title,
    required this.body,
    this.scrollKey,
    this.onApply,
    this.clearLabel,
    this.onClear,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final media = MediaQuery.of(context);
    final inset = media.viewInsets.bottom;
    final scale = media.textScaler.scale(1);
    final applyMin = max(48.0, 32 * scale);
    final clearMin = max(44.0, 32 * scale);
    final header = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: p.text(18, weight: FontWeight.w600).copyWith(height: 24 / 18),
            ),
          ),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              tooltip: 'Schließen',
              onPressed: () => Navigator.pop(context),
              padding: EdgeInsets.zero,
              icon: Icon(LucideIcons.x, size: 20, color: p.ink),
            ),
          ),
        ],
      ),
    );
    final footer = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null) ...[
          Row(
            children: [
              Icon(LucideIcons.circleAlert, size: 20, color: p.danger),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  error!,
                  style: p.text(14, color: p.danger).copyWith(height: 20 / 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: applyMin),
          child: OBAction('Übernehmen', ink: true, onPressed: onApply),
        ),
        if (clearLabel != null)
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: clearMin),
            child: TextButton(
              onPressed: onClear,
              style: TextButton.styleFrom(
                minimumSize: Size(44, clearMin),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                clearLabel!,
                style: p.text(15, color: p.danger).copyWith(height: 20 / 15),
              ),
            ),
          ),
      ],
    );
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: constraints.maxHeight),
              child: Material(
                color: p.card,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AlpRadius.card),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    16,
                    20,
                    max(12.0, media.padding.bottom),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      header,
                      const SizedBox(height: 16),
                      Flexible(
                        child: KeyedSubtree(
                          key: scrollKey,
                          child: SingleChildScrollView(child: body),
                        ),
                      ),
                      const SizedBox(height: 16),
                      footer,
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FoodTimeSheet extends StatefulWidget {
  final String date;
  final DateTime? initial;
  final DateTime? previous;
  final String? zone;
  const _FoodTimeSheet({
    required this.date,
    required this.initial,
    this.previous,
    this.zone,
  });

  @override
  State<_FoodTimeSheet> createState() => _FoodTimeSheetState();
}

class _FoodTimeSheetState extends State<_FoodTimeSheet> {
  late final TextEditingController _time;
  String? _error;

  @override
  void initState() {
    super.initState();
    _time = TextEditingController(
      text: widget.initial == null ? '' : obTime(widget.initial),
    );
  }

  @override
  void dispose() {
    _time.dispose();
    super.dispose();
  }

  void _apply() {
    final parsed = _foodRecordedTime(
      widget.date,
      _time.text,
      previous: widget.previous ?? widget.initial,
      zone: widget.zone,
    );
    if (parsed == null) {
      setState(() => _error = 'Uhrzeit ungültig');
      return;
    }
    Navigator.pop(context, _FoodTimeResult(at: parsed));
  }

  @override
  Widget build(BuildContext context) {
    return _FoodSheetScaffold(
      title: 'Uhrzeit',
      scrollKey: const ValueKey('food-time-scroll'),
      onApply: _time.text.trim().isEmpty ? null : _apply,
      clearLabel: widget.initial == null ? null : 'Uhrzeit entfernen',
      onClear: () => Navigator.pop(context, const _FoodTimeResult(clear: true)),
      error: _error,
      body: OBTimeField.well(
        label: obDate(widget.date),
        value: _time.text,
        controller: _time,
        fieldKey: const ValueKey('food-time'),
        semanticsLabel: 'Uhrzeit',
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) {
          if (_time.text.trim().isNotEmpty) _apply();
        },
      ),
    );
  }
}

class _FoodQuantitySheet extends StatefulWidget {
  final FoodEntry baseline;
  const _FoodQuantitySheet({required this.baseline});

  @override
  State<_FoodQuantitySheet> createState() => _FoodQuantitySheetState();
}

class _FoodQuantitySheetState extends State<_FoodQuantitySheet> {
  late final TextEditingController _amount;
  late final TextEditingController _unit;
  bool _scale = false;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: formatNutritionGoalNumber(widget.baseline.quantity),
    );
    _unit = TextEditingController(text: widget.baseline.unit);
  }

  @override
  void dispose() {
    _amount.dispose();
    _unit.dispose();
    super.dispose();
  }

  bool get _canScale {
    final original = widget.baseline.quantity;
    if (original == null || original <= 0) return false;
    return _unit.text.trim() == widget.baseline.unit;
  }

  bool get _amountOk {
    final parsed = parseNutritionGoalNumber(_amount.text);
    if (parsed.bad || parsed.value == null) return false;
    if (parsed.value! < 0) return false;
    return _unit.text.trim().isNotEmpty;
  }

  void _apply({bool clear = false}) {
    final amount = clear
        ? null
        : parseNutritionGoalNumber(_amount.text).value;
    final unit = _unit.text.trim().isEmpty
        ? widget.baseline.unit
        : _unit.text.trim();
    var next = _copy(
      widget.baseline,
      quantity: amount,
      unit: unit,
      clearQuantity: amount == null,
    );
    if (!clear && _scale && _canScale && amount != null) {
      final factor = amount / widget.baseline.quantity!;
      double? scale(double? value) => value == null ? null : value * factor;
      next = _copy(
        next,
        kcal: scale(widget.baseline.kcal),
        proteinG: scale(widget.baseline.proteinG),
        carbsG: scale(widget.baseline.carbsG),
        fatG: scale(widget.baseline.fatG),
        fibreG: scale(widget.baseline.fibreG),
        sugarG: scale(widget.baseline.sugarG),
        satFatG: scale(widget.baseline.satFatG),
        sodiumMg: scale(widget.baseline.sodiumMg),
        ironMg: scale(widget.baseline.ironMg),
        calciumMg: scale(widget.baseline.calciumMg),
      );
    }
    Navigator.pop(context, next);
  }

  Widget _well({required Widget child}) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return Container(
      constraints: BoxConstraints(minHeight: max(56.0, 16 + 34 * scale)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: OB.of(context).well,
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.centerLeft,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final stacked = _stack(context);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final style = p
        .text(28, weight: FontWeight.w700, display: true)
        .copyWith(height: 34 / 28);
    final empty = _amount.text.isEmpty;
    final amountField = _well(
      child: Semantics(
        label: 'Menge',
        textField: true,
        child: TextField(
          key: const ValueKey('food-qty-amount'),
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: style.copyWith(color: empty ? p.muted : p.ink),
          cursorColor: p.ink,
          decoration: InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
            hintText: '—',
            hintStyle: style.copyWith(color: p.muted),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ),
    );
    final unitField = _well(
      child: TextField(
        key: const ValueKey('food-qty-unit'),
        controller: _unit,
        style: style,
        cursorColor: p.ink,
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: (_) {
          if (_unit.text.trim() != widget.baseline.unit) _scale = false;
          setState(() {});
        },
      ),
    );
    return _FoodSheetScaffold(
      title: 'Menge',
      scrollKey: const ValueKey('food-qty-scroll'),
      onApply: _amountOk ? () => _apply() : null,
      clearLabel: widget.baseline.quantity == null ? null : 'Menge entfernen',
      onClear: () => _apply(clear: true),
      body: Column(
        children: [
          if (stacked) ...[
            amountField,
            const SizedBox(height: 12),
            unitField,
          ] else
            Row(
              children: [
                Expanded(child: amountField),
                const SizedBox(width: 12),
                Expanded(child: unitField),
              ],
            ),
          if (_canScale) ...[
            const SizedBox(height: 16),
            KeyedSubtree(
              key: const ValueKey('food-qty-scale'),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: max(48.0, 32 * scale)),
                child: OBSettingsChoiceRow(
                  label: 'Nährwerte anpassen',
                  selected: _scale,
                  onTap: () => setState(() => _scale = !_scale),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FoodDatePage extends StatefulWidget {
  final String initial;
  final DateTime now;
  final bool synthetic;
  const _FoodDatePage({
    required this.initial,
    required this.now,
    required this.synthetic,
  });

  @override
  State<_FoodDatePage> createState() => _FoodDatePageState();
}

class _FoodDatePageState extends State<_FoodDatePage> {
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
            const OBPageHeader(title: 'Datum', subtitle: ''),
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

class _FoodNutrientRow extends StatelessWidget {
  final String label, unit;
  final TextEditingController controller;
  final bool stacked, enabled;
  final Key fieldKey;
  final ValueChanged<String> onChanged;
  const _FoodNutrientRow({
    required this.label,
    required this.unit,
    required this.controller,
    required this.stacked,
    required this.enabled,
    required this.fieldKey,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    const valueSize = 24.0;
    const valueHeight = 28.0;
    final empty = controller.text.isEmpty;
    final style = p
        .text(valueSize, weight: FontWeight.w600, display: true)
        .copyWith(
          height: valueHeight / valueSize,
          color: empty ? p.muted : p.ink,
        );
    final well = Container(
      width: stacked ? double.infinity : 118,
      constraints: BoxConstraints(minHeight: stacked ? 72 : 44),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
              label: label,
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
          if (unit.isNotEmpty) ...[
            const SizedBox(width: 6),
            SizedBox(
              width: stacked ? null : 24,
              child: Text(
                unit,
                style: p.text(12, color: p.muted).copyWith(height: 16 / 12),
              ),
            ),
          ],
        ],
      ),
    );
    final title = Text(label, style: p.text(15).copyWith(height: 20 / 15));
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: stacked ? 56 : 56),
      child: stacked
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  const SizedBox(height: 8),
                  well,
                ],
              ),
            )
          : Row(
              children: [
                Expanded(child: title),
                well,
              ],
            ),
    );
  }
}

bool _stack(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(15) > 20 ||
    MediaQuery.sizeOf(context).width < 360;

String _mealLabel(String meal) {
  for (final e in _meals) {
    if (e.$1 == meal) return e.$2;
  }
  return meal;
}

String _sourceLabel(FoodEntry e) {
  if (e.source == FoodSource.photo && !e.confirmed) {
    return 'Foto · unbestätigt';
  }
  return switch (e.source) {
    FoodSource.manual => 'Manuell',
    FoodSource.verified => 'Geprüft',
    FoodSource.barcode => 'Barcode',
    FoodSource.repeat => 'Wiederholt',
    FoodSource.photo => 'Foto',
    FoodSource.unknown => 'Unbekannt',
  };
}

double? _displayNutrient(FoodEntry e, double? value) =>
    e.source == FoodSource.photo && !e.confirmed ? null : value;

DateTime? _foodRecordedTime(
  String date,
  String text, {
  DateTime? previous,
  String? zone,
}) {
  final parsed = parseRecordedTime(
    DateTime.parse(date),
    text,
    previous: previous,
    zone: zone,
  );
  if (parsed == null) return null;
  if (previous == null) return parsed;
  final wall = recordedTime(previous, zone);
  if (parsed.hour != wall.hour || parsed.minute != wall.minute) {
    return parsed;
  }
  return parsed.add(Duration(seconds: wall.second));
}

String _qty(double? value) =>
    value == null ? '—' : formatNutritionGoalNumber(value);

String _grams(double? value) => value == null ? '—' : '${_qty(value)} g';

String _unitValue(double? value, String unit) =>
    value == null ? '—' : '${_qty(value)} $unit';

String _quantityLabel(FoodEntry e) =>
    e.quantity == null ? '—' : '${_qty(e.quantity)} ${e.unit}';

String _timeLabel(FoodEntry e, [String? zone]) {
  if (e.atTs == null) return '—';
  return obTime(
    recordedTime(
      DateTime.fromMillisecondsSinceEpoch(e.atTs! * 1000),
      zone,
    ),
  );
}

double? _nutrientOf(FoodEntry e, String key) => switch (key) {
  'kcal' => e.kcal,
  'proteinG' => e.proteinG,
  'carbsG' => e.carbsG,
  'fatG' => e.fatG,
  'fibreG' => e.fibreG,
  'sugarG' => e.sugarG,
  'satFatG' => e.satFatG,
  'sodiumMg' => e.sodiumMg,
  'ironMg' => e.ironMg,
  'calciumMg' => e.calciumMg,
  _ => null,
};

FoodEntry _copy(
  FoodEntry e, {
  String? date,
  String? meal,
  String? label,
  int? atTs,
  bool clearAtTs = false,
  double? quantity,
  bool clearQuantity = false,
  String? unit,
  double? kcal,
  bool clearKcal = false,
  double? proteinG,
  bool clearProtein = false,
  double? carbsG,
  bool clearCarbs = false,
  double? fatG,
  bool clearFat = false,
  double? fibreG,
  bool clearFibre = false,
  double? sugarG,
  bool clearSugar = false,
  double? satFatG,
  bool clearSatFat = false,
  double? sodiumMg,
  bool clearSodium = false,
  double? ironMg,
  bool clearIron = false,
  double? calciumMg,
  bool clearCalcium = false,
  String? note,
  bool? confirmed,
}) => FoodEntry(
  id: e.id,
  date: date ?? e.date,
  meal: meal ?? e.meal,
  label: label ?? e.label,
  atTs: clearAtTs ? null : (atTs ?? e.atTs),
  foodKey: e.foodKey,
  quantity: clearQuantity ? null : (quantity ?? e.quantity),
  unit: unit ?? e.unit,
  kcal: clearKcal ? null : (kcal ?? e.kcal),
  proteinG: clearProtein ? null : (proteinG ?? e.proteinG),
  carbsG: clearCarbs ? null : (carbsG ?? e.carbsG),
  fatG: clearFat ? null : (fatG ?? e.fatG),
  fibreG: clearFibre ? null : (fibreG ?? e.fibreG),
  sugarG: clearSugar ? null : (sugarG ?? e.sugarG),
  satFatG: clearSatFat ? null : (satFatG ?? e.satFatG),
  sodiumMg: clearSodium ? null : (sodiumMg ?? e.sodiumMg),
  ironMg: clearIron ? null : (ironMg ?? e.ironMg),
  calciumMg: clearCalcium ? null : (calciumMg ?? e.calciumMg),
  source: e.source,
  sourceCode: e.sourceCode,
  confirmed: confirmed ?? e.confirmed,
  note: note ?? e.note,
  createdAt: e.createdAt,
  updatedAt: e.updatedAt,
);
