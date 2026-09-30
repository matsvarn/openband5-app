import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import 'action_sheet.dart';
import 'domain.dart';
import 'exercise_input.dart';
import 'exercise_picker.dart';
import 'theme.dart';

String _newId() => const Uuid().v4();

String _loadFieldText(double? kg) {
  if (kg == null) return '';
  final tenths = kg * 10;
  if (tenths == tenths.roundToDouble()) {
    return (tenths.round() / 10).toStringAsFixed(1).replaceAll('.', ',');
  }
  var s = kg.toStringAsFixed(10);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return s.replaceAll('.', ',');
}

({int? value, bool bad}) _parseCount(String raw, {required bool timed}) {
  final s = raw.trim();
  if (s.isEmpty) return (value: null, bad: false);
  final v = int.tryParse(s);
  if (v == null || (timed ? v <= 0 : v < 0)) return (value: null, bad: true);
  return (value: v, bad: false);
}

({double? value, bool bad}) _parseLoadText(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return (value: null, bad: false);
  if (RegExp(r'\s').hasMatch(s)) return (value: null, bad: true);
  final String ascii;
  if (RegExp(r'^\d{1,3}(?:\.\d{3})+,\d+$').hasMatch(s)) {
    ascii = s.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'^\d+,\d+$').hasMatch(s)) {
    ascii = s.replaceAll(',', '.');
  } else if (RegExp(r'^\d+\.\d+$').hasMatch(s) ||
      RegExp(r'^\d+$').hasMatch(s)) {
    ascii = s;
  } else {
    return (value: null, bad: true);
  }
  final v = double.tryParse(ascii);
  if (v == null || !v.isFinite || v < 0) return (value: null, bad: true);
  return (value: v, bad: false);
}

/// Create or edit a [WorkoutTemplate] (B23). Saving is atomic and bumps the
/// version; a failed save keeps every field. Recorded sessions are untouched.
class OpenBandTemplateEditor extends StatefulWidget {
  final OpenBandRepository repository;
  final WorkoutTemplate? template;
  const OpenBandTemplateEditor({
    super.key,
    required this.repository,
    this.template,
  });
  @override
  State<OpenBandTemplateEditor> createState() => _OpenBandTemplateEditorState();
}

class _ExerciseDraft {
  final String id, key;
  final String note;
  final TextEditingController name;
  final List<_SetDraft> sets;
  final ExerciseDefinitionSnapshot? definition;
  _ExerciseDraft(
    this.id,
    this.key,
    String label,
    this.sets, {
    this.note = '',
    this.definition,
  }) : name = TextEditingController(text: label);
}

class _SetDraft {
  final String id;
  final bool timed;
  final String type;
  final int? restSec;
  final double? storedLoad;
  final PlannedSetMode? mode;
  final int? retainedReps;
  final int? retainedSeconds;
  final OriginalLoadInput? original;
  final bool typed;
  ExerciseLoadUnit unit;
  ExerciseSetSide side;
  bool loadChanged = false;
  bool semanticsChanged = false;
  final TextEditingController count, load;
  _SetDraft(
    this.id, {
    required this.timed,
    this.type = 'work',
    this.restSec,
    this.mode,
    this.retainedReps,
    this.retainedSeconds,
    this.original,
    bool typed = false,
    ExerciseLoadUnit? unit,
    this.side = ExerciseSetSide.both,
    int? count,
    double? load,
  }) : storedLoad = load,
       typed = typed || original?.basis != null,
       unit = unit ?? original?.unit ?? ExerciseLoadUnit.kg,
       count = TextEditingController(text: count?.toString() ?? ''),
       load = TextEditingController(
         text: (typed || original?.basis != null)
             ? formatOriginalLoadValue(original?.value)
             : _loadFieldText(load),
       );
}

class _OpenBandTemplateEditorState extends State<OpenBandTemplateEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.template?.name ?? '',
  );
  late final List<_ExerciseDraft> _exercises = [
    for (final e in widget.template?.exercises ?? const <PlannedExercise>[])
      _ExerciseDraft(
        e.id,
        e.exerciseKey,
        e.name,
        [
          for (final s in e.sets)
            _SetDraft(
              s.id,
              timed: s.isTimed,
              type: s.type,
              restSec: s.restSec,
              mode: s.mode,
              retainedReps: s.mode == null && s.isTimed ? s.reps : null,
              retainedSeconds: s.mode == null && !s.isTimed ? s.seconds : null,
              count: s.isTimed ? s.seconds : s.reps,
              load: s.loadKg,
              original: s.load,
              typed: s.load?.basis != null,
              side: s.load?.side ?? ExerciseSetSide.both,
            ),
        ],
        note: e.note,
        definition: e.definition,
      ),
  ];
  late final String _id = widget.template?.id ?? _newId();
  bool _saving = false;
  bool _adding = false;
  String? _error;

  _ExerciseDraft _draftFromCatalogue(ExerciseCatalogueEntry entry) {
    final timed = entry.mode == ExerciseCaptureMode.time;
    return _ExerciseDraft(_newId(), entry.id, entry.label, [
      _SetDraft(
        _newId(),
        timed: timed,
        mode: timed ? PlannedSetMode.time : PlannedSetMode.repetitions,
        typed: entry.loadBasis != null,
      ),
    ], definition: entry.snapshot());
  }

  Future<void> _showAdd() async {
    if (_adding || _saving) return;
    _adding = true;
    try {
      final choice = await showAddExerciseSheet(context);
      if (!mounted || choice == null) return;
      switch (choice) {
        case AddExerciseChoice.library:
          await _addFromLibrary();
        case AddExerciseChoice.custom:
          await _addFromLibrary(
            createOnOpen: true,
            initialCreateMode: ExerciseCaptureMode.repetitions,
          );
        case AddExerciseChoice.customTimed:
          await _addFromLibrary(
            createOnOpen: true,
            initialCreateMode: ExerciseCaptureMode.time,
          );
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _addFromLibrary({
    bool createOnOpen = false,
    ExerciseCaptureMode? initialCreateMode,
  }) async {
    final picked = await Navigator.of(context)
        .push<List<ExerciseCatalogueEntry>>(
          MaterialPageRoute(
            builder: (_) => OpenBandExercisePicker(
              repository: widget.repository,
              existingExerciseIds: {for (final e in _exercises) e.key},
              createOnOpen: createOnOpen,
              initialCreateMode: initialCreateMode,
            ),
          ),
        );
    if (!mounted || picked == null || picked.isEmpty) return;
    setState(() {
      for (final entry in picked) {
        _exercises.add(_draftFromCatalogue(entry));
      }
    });
  }

  void _addSet(_ExerciseDraft exercise) {
    final last = exercise.sets.last;
    exercise.sets.add(
      _SetDraft(
        _newId(),
        timed: last.timed,
        type: last.type,
        restSec: last.restSec,
        mode:
            last.mode ??
            (last.timed ? PlannedSetMode.time : PlannedSetMode.repetitions),
        typed: last.typed || exercise.definition?.loadBasis != null,
        unit: last.unit,
        side: last.side,
      ),
    );
  }

  bool _mixedLegacy(_SetDraft s) =>
      s.timed && s.mode == null && s.retainedReps != null;

  bool _countInvalid(_SetDraft s) {
    final parsed = _parseCount(s.count.text, timed: s.timed);
    if (parsed.bad) return true;
    // Ambiguous historic reps+seconds cannot go blank; that would reopen as reps.
    if (_mixedLegacy(s) && parsed.value == null) return true;
    return false;
  }

  ExerciseDefinitionSnapshot? _frozen(_ExerciseDraft e, _SetDraft s) =>
      frozenDefinition(
        load: s.original,
        typed: s.typed,
        definition: e.definition,
      );

  ExerciseBlockLoadLabels _loadLabels(_ExerciseDraft e) =>
      exerciseBlockLoadLabels(
        definition: e.definition,
        rows: [
          for (final s in e.sets)
            ExerciseLoadRowView(
              load: s.original,
              typed: s.typed,
              historicKg: s.storedLoad,
              chosenUnit: s.unit,
            ),
        ],
      );

  bool _showsLoad(_ExerciseDraft e, _SetDraft s) => showsExternalLoad(
    definition: _frozen(e, s),
    load: s.original,
    timed: s.timed,
    historicLoadKg: s.storedLoad,
  );

  bool _showsSide(_ExerciseDraft e, _SetDraft s) =>
      showsSideControl(definition: _frozen(e, s), load: s.original);

  bool _loadInvalid(_ExerciseDraft e, _SetDraft s) {
    if (!_showsLoad(e, s)) return false;
    final parsed = _parseLoadText(s.load.text);
    if (parsed.bad) return true;
    if (!capturesOriginalLoad(
      typed: s.typed,
      existing: s.original,
      definition: _frozen(e, s),
    )) {
      return false;
    }
    try {
      captureOriginalLoad(
        definition: e.definition,
        existing: s.original,
        typed: s.typed,
        value: parsed.value,
        unit: s.unit,
        side: s.side,
      );
    } catch (_) {
      return true;
    }
    return false;
  }

  bool get _valid {
    if (_name.text.trim().isEmpty || _exercises.isEmpty) return false;
    for (final e in _exercises) {
      if (e.name.text.trim().isEmpty || e.sets.isEmpty) return false;
      for (final s in e.sets) {
        if (_countInvalid(s)) return false;
        if (_loadInvalid(e, s)) return false;
      }
    }
    return true;
  }

  String? _durationError(_SetDraft s) {
    if (_mixedLegacy(s) &&
        _parseCount(s.count.text, timed: true).value == null) {
      return 'Dauer fehlt.';
    }
    return null;
  }

  double? _historicLoad(_SetDraft s, {required bool showLoad}) {
    if (s.timed && !showLoad) return s.storedLoad;
    final text = s.load.text.trim();
    if (text.isEmpty) return null;
    if (s.storedLoad != null && text == _loadFieldText(s.storedLoad)) {
      return s.storedLoad;
    }
    final parsed = _parseLoadText(s.load.text);
    return parsed.bad ? null : parsed.value;
  }

  PlannedSet _savedSet(_SetDraft s, _ExerciseDraft e) {
    final count = _parseCount(s.count.text, timed: s.timed).value;
    final reps = s.timed ? s.retainedReps : count;
    final seconds = s.timed ? count : s.retainedSeconds;
    var mode = s.mode;
    // Legacy time-only (no mode, no retained reps): clearing seconds must
    // keep time identity. Historic reps+seconds stays modeless and cannot
    // save a blank duration.
    if (mode == null && s.timed && s.retainedReps == null && seconds == null) {
      mode = PlannedSetMode.time;
    }
    final showLoad = _showsLoad(e, s);
    final parsed = showLoad
        ? _parseLoadText(s.load.text)
        : (value: null, bad: false);
    final OriginalLoadInput? captured;
    final double? loadKg;
    if (s.original != null && !s.loadChanged && !s.semanticsChanged) {
      captured = s.original;
      loadKg = s.storedLoad;
    } else if (hasUnsupportedLoadMetadata(
      definition: _frozen(e, s),
      load: s.original,
    )) {
      captured = s.original;
      loadKg = s.storedLoad;
    } else if (capturesOriginalLoad(
      typed: s.typed,
      existing: s.original,
      definition: e.definition,
    )) {
      captured = captureOriginalLoad(
        definition: e.definition,
        existing: s.original,
        typed: s.typed,
        value: parsed.value,
        unit: s.unit,
        side: s.side,
      );
      loadKg = resolvedLoadKg(captured, null);
    } else {
      captured = s.original;
      loadKg = _historicLoad(s, showLoad: showLoad);
    }
    return PlannedSet(
      id: s.id,
      type: s.type,
      reps: reps,
      seconds: seconds,
      loadKg: loadKg,
      restSec: s.restSec,
      mode: mode,
      load: captured,
    );
  }

  Future<void> _save() async {
    if (!_valid) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.repository.saveTemplate(
        WorkoutTemplate(
          id: _id,
          name: _name.text,
          version: widget.template?.version ?? 0,
          exercises: [
            for (final e in _exercises)
              PlannedExercise(
                id: e.id,
                exerciseKey: e.key,
                name: e.name.text.trim(),
                note: e.note,
                definition: e.definition,
                sets: [for (final s in e.sets) _savedSet(s, e)],
              ),
          ],
          updatedAt: DateTime.now(),
        ),
      );
      if (mounted) Navigator.of(context).pop(saved);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Speichern fehlgeschlagen.';
        });
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    for (final e in _exercises) {
      e.name.dispose();
      for (final s in e.sets) {
        s.count.dispose();
        s.load.dispose();
      }
    }
    super.dispose();
  }

  Widget _exerciseNameField(
    OB p,
    _ExerciseDraft e, {
    required InputDecoration nameDeco,
  }) {
    final caption = _loadLabels(e).caption;
    if (caption == null) {
      return TextField(
        controller: e.name,
        onChanged: (_) => setState(() {}),
        style: p.text(15, weight: FontWeight.w600).copyWith(height: 20 / 15),
        decoration: nameDeco,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.well,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: e.name,
              onChanged: (_) => setState(() {}),
              style: p
                  .text(15, weight: FontWeight.w600)
                  .copyWith(height: 20 / 15),
              decoration: InputDecoration(
                hintText: 'Übung',
                hintStyle: p.text(16, color: p.muted).copyWith(height: 22 / 16),
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              caption,
              style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickSide(_SetDraft s) async {
    final picked = await showExerciseInputChoice<ExerciseSetSide>(
      context: context,
      title: 'Seite',
      choices: exerciseSideChoices,
      selected: s.side,
    );
    if (!mounted || picked == null || picked == s.side) return;
    setState(() {
      s.side = picked;
      s.semanticsChanged = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    InputDecoration wellDeco({
      required String hint,
      EdgeInsetsGeometry padding = const EdgeInsets.all(10),
    }) => InputDecoration(
      hintText: hint,
      hintStyle: p.text(16, color: p.muted).copyWith(height: 22 / 16),
      isDense: true,
      filled: true,
      fillColor: p.well,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding: padding,
    );
    return Scaffold(
      backgroundColor: p.well,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OBPageHeader(
                title: widget.template == null
                    ? 'Neue Vorlage'
                    : 'Vorlage bearbeiten',
                subtitle: '',
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  OBCard(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 32),
                      child: TextField(
                        controller: _name,
                        onChanged: (_) => setState(() {}),
                        style: p
                            .text(20, weight: FontWeight.w700, display: true)
                            .copyWith(height: 27 / 20),
                        decoration: const InputDecoration(
                          hintText: 'Name der Vorlage',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final (ei, e) in _exercises.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: OBCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      minHeight: 44,
                                    ),
                                    child: _exerciseNameField(
                                      p,
                                      e,
                                      nameDeco: wellDeco(hint: 'Übung'),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: IconButton(
                                    tooltip: 'Übung entfernen',
                                    onPressed: () =>
                                        setState(() => _exercises.removeAt(ei)),
                                    padding: EdgeInsets.zero,
                                    icon: Icon(
                                      LucideIcons.trash2,
                                      size: 18,
                                      color: p.danger,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            for (final (si, s) in e.sets.indexed) ...[
                              MediaQuery.withClampedTextScaling(
                                maxScaleFactor: 1.3,
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 28,
                                      child: Text(
                                        '${si + 1}',
                                        style: p
                                            .text(
                                              14,
                                              weight: FontWeight.w700,
                                              display: true,
                                              color: p.muted,
                                            )
                                            .copyWith(height: 19 / 14),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (_showsLoad(e, s)) ...[
                                      Expanded(
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            minHeight: 48,
                                          ),
                                          child: TextField(
                                            controller: s.load,
                                            enabled:
                                                !hasUnsupportedLoadMetadata(
                                                  definition: _frozen(e, s),
                                                  load: s.original,
                                                ),
                                            onChanged: (_) => setState(
                                              () => s.loadChanged = true,
                                            ),
                                            keyboardType:
                                                const TextInputType.numberWithOptions(
                                                  decimal: true,
                                                ),
                                            textAlign: TextAlign.center,
                                            style: p
                                                .text(16)
                                                .copyWith(height: 22 / 16),
                                            decoration: wellDeco(
                                              hint: loadUnitLabel(s.unit),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 12,
                                                  ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Expanded(
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          minHeight: 48,
                                        ),
                                        child: TextField(
                                          controller: s.count,
                                          onChanged: (_) => setState(() {}),
                                          keyboardType: TextInputType.number,
                                          textAlign: TextAlign.center,
                                          style: p
                                              .text(16)
                                              .copyWith(height: 22 / 16),
                                          decoration: wellDeco(
                                            hint: s.timed ? 'Sek.' : 'Wdh.',
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      key: ValueKey('set-remove-${s.id}'),
                                      width: 44,
                                      height: 44,
                                      child: IconButton(
                                        tooltip: 'Satz ${si + 1} entfernen',
                                        onPressed: e.sets.length == 1
                                            ? null
                                            : () => setState(
                                                () => e.sets.removeAt(si),
                                              ),
                                        padding: EdgeInsets.zero,
                                        icon: Icon(
                                          LucideIcons.minus,
                                          size: 18,
                                          color: p.muted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_loadLabels(e).mixedSemantics ||
                                  _showsSide(e, s))
                                InkWell(
                                  key: _showsSide(e, s)
                                      ? ValueKey('side-${s.id}')
                                      : null,
                                  onTap: _showsSide(e, s)
                                      ? () => _pickSide(s)
                                      : null,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: _showsSide(e, s) ? 44 : 24,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        left: 36,
                                        right: 12,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (_loadLabels(e).mixedSemantics)
                                            Text(
                                              exerciseRowLoadCaption(
                                                    definition: e.definition,
                                                    load: s.original,
                                                    typed: s.typed,
                                                    historicLoadKg:
                                                        s.storedLoad,
                                                  ) ??
                                                  '',
                                              style: p
                                                  .text(
                                                    13,
                                                    weight: FontWeight.w500,
                                                    color: p.muted,
                                                  )
                                                  .copyWith(height: 18 / 13),
                                            ),
                                          if (_showsSide(e, s))
                                            Row(
                                              children: [
                                                Text(
                                                  exerciseSideLabel(s.side),
                                                  style: p
                                                      .text(13)
                                                      .copyWith(
                                                        height: 18 / 13,
                                                      ),
                                                ),
                                                const SizedBox(width: 6),
                                                Icon(
                                                  LucideIcons.chevronDown,
                                                  size: 16,
                                                  color: p.muted,
                                                ),
                                              ],
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              if (_durationError(s) case final err?) ...[
                                const SizedBox(height: 4),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(width: 36),
                                    if (_showsLoad(e, s)) ...[
                                      const Expanded(child: SizedBox.shrink()),
                                      const SizedBox(width: 8),
                                    ],
                                    Expanded(
                                      child: Text(
                                        err,
                                        style: p
                                            .text(12, color: p.danger)
                                            .copyWith(height: 16 / 12),
                                      ),
                                    ),
                                    const SizedBox(width: 52),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 8),
                            ],
                            InkWell(
                              onTap: () => setState(() => _addSet(e)),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 44,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        LucideIcons.plus,
                                        size: 16,
                                        color: p.ink,
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          'Satz hinzufügen',
                                          style: p
                                              .text(14, weight: FontWeight.w600)
                                              .copyWith(height: 19 / 14),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  OBAction(
                    'Übung hinzufügen',
                    secondary: true,
                    ink: true,
                    onPressed: _adding || _saving ? null : _showAdd,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error case final err?)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        err,
                        style: p.text(
                          13,
                          weight: FontWeight.w600,
                          color: p.danger,
                        ),
                      ),
                    ),
                  OBAction(
                    _saving ? 'Wird gespeichert…' : 'Vorlage speichern',
                    ink: true,
                    onPressed: _valid && !_saving ? _save : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
