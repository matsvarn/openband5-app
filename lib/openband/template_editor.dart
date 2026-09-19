import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import 'alp_tokens.dart';
import 'domain.dart';
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

double? _savedLoad(_SetDraft s) {
  if (s.timed) return s.storedLoad;
  final text = s.load.text.trim();
  if (text.isEmpty) return null;
  if (s.storedLoad != null && text == _loadFieldText(s.storedLoad)) {
    return s.storedLoad;
  }
  final parsed = _parseLoadText(s.load.text);
  return parsed.bad ? null : parsed.value;
}

({int? value, bool bad}) _parseCount(String raw, {required bool timed}) {
  final s = raw.trim();
  if (s.isEmpty) return (value: null, bad: timed);
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
  _ExerciseDraft(this.id, this.key, String label, this.sets, {this.note = ''})
    : name = TextEditingController(text: label);
}

class _SetDraft {
  final String id;
  final bool timed;
  final String type;
  final int? restSec;
  final double? storedLoad;
  final TextEditingController count, load;
  _SetDraft(
    this.id, {
    required this.timed,
    this.type = 'work',
    this.restSec,
    int? count,
    double? load,
  }) : storedLoad = load,
       count = TextEditingController(text: count?.toString() ?? ''),
       load = TextEditingController(text: _loadFieldText(load));
}

class _OpenBandTemplateEditorState extends State<OpenBandTemplateEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.template?.name ?? '',
  );
  late final List<_ExerciseDraft> _exercises = [
    for (final e in widget.template?.exercises ?? const <PlannedExercise>[])
      _ExerciseDraft(e.id, e.exerciseKey, e.name, [
        for (final s in e.sets)
          _SetDraft(
            s.id,
            timed: s.seconds != null,
            type: s.type,
            restSec: s.restSec,
            count: s.seconds ?? s.reps,
            load: s.loadKg,
          ),
      ], note: e.note),
  ];
  late final String _id = widget.template?.id ?? _newId();
  bool _saving = false;
  String? _error;

  void _addExercise({bool timed = false}) => setState(() {
    _exercises.add(
      _ExerciseDraft(_newId(), _newId(), '', [
        for (var i = 0; i < 3; i++)
          _SetDraft(_newId(), timed: timed, restSec: 90),
      ]),
    );
  });

  void _addSet(_ExerciseDraft exercise) {
    final last = exercise.sets.last;
    exercise.sets.add(
      _SetDraft(
        _newId(),
        timed: last.timed,
        type: last.type,
        restSec: last.restSec,
      ),
    );
  }

  bool get _valid {
    if (_name.text.trim().isEmpty || _exercises.isEmpty) return false;
    for (final e in _exercises) {
      if (e.name.text.trim().isEmpty || e.sets.isEmpty) return false;
      for (final s in e.sets) {
        if (_parseCount(s.count.text, timed: s.timed).bad) return false;
        if (!s.timed && _parseLoadText(s.load.text).bad) return false;
      }
    }
    return true;
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
                sets: [
                  for (final s in e.sets)
                    PlannedSet(
                      id: s.id,
                      type: s.type,
                      reps: s.timed
                          ? null
                          : _parseCount(s.count.text, timed: false).value,
                      seconds: s.timed
                          ? _parseCount(s.count.text, timed: true).value
                          : null,
                      loadKg: _savedLoad(s),
                      restSec: s.restSec,
                    ),
                ],
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

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    InputDecoration deco(String hint) => InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: p.well,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        backgroundColor: p.canvas,
        centerTitle: true,
        title: Text(
          widget.template == null ? 'Neue Vorlage' : 'Vorlage bearbeiten',
          style: p.text(18, weight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
        children: [
          OBCard(
            child: TextField(
              controller: _name,
              onChanged: (_) => setState(() {}),
              style: p.text(20, weight: FontWeight.w700, display: true),
              decoration: const InputDecoration(
                hintText: 'Name der Vorlage',
                border: InputBorder.none,
                isDense: true,
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
                  spacing: 8,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: e.name,
                            onChanged: (_) => setState(() {}),
                            style: p.text(15, weight: FontWeight.w600),
                            decoration: deco('Übung'),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Übung entfernen',
                          onPressed: () =>
                              setState(() => _exercises.removeAt(ei)),
                          icon: Icon(
                            LucideIcons.trash2,
                            size: 18,
                            color: p.danger,
                          ),
                        ),
                      ],
                    ),
                    for (final (si, s) in e.sets.indexed)
                      Row(
                        spacing: 8,
                        children: [
                          SizedBox(
                            width: 28,
                            child: Text(
                              '${si + 1}',
                              style: p.text(
                                14,
                                weight: FontWeight.w700,
                                display: true,
                                color: p.muted,
                              ),
                            ),
                          ),
                          if (!s.timed)
                            Expanded(
                              child: TextField(
                                controller: s.load,
                                onChanged: (_) => setState(() {}),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                textAlign: TextAlign.center,
                                decoration: deco('kg'),
                              ),
                            ),
                          Expanded(
                            child: TextField(
                              controller: s.count,
                              onChanged: (_) => setState(() {}),
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              decoration: deco(s.timed ? 'Sek.' : 'Wdh.'),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Satz ${si + 1} entfernen',
                            onPressed: e.sets.length == 1
                                ? null
                                : () => setState(() => e.sets.removeAt(si)),
                            icon: Icon(
                              LucideIcons.minus,
                              size: 18,
                              color: p.muted,
                            ),
                          ),
                        ],
                      ),
                    TextButton.icon(
                      onPressed: () => setState(() => _addSet(e)),
                      icon: const Icon(LucideIcons.plus, size: 16),
                      label: const Text('Satz hinzufügen'),
                    ),
                  ],
                ),
              ),
            ),
          Row(
            spacing: 10,
            children: [
              Expanded(
                child: OBAction(
                  'Übung hinzufügen',
                  secondary: true,
                  onPressed: _addExercise,
                ),
              ),
              Expanded(
                child: OBAction(
                  'Zeitübung hinzufügen',
                  secondary: true,
                  onPressed: () => _addExercise(timed: true),
                ),
              ),
            ],
          ),
          if (_error case final err?)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                err,
                style: p.text(13, weight: FontWeight.w600, color: p.danger),
              ),
            ),
        ],
      ),
      bottomSheet: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(AlpRadius.card),
            ),
            child: OBAction(
              _saving ? 'Wird gespeichert…' : 'Vorlage speichern',
              onPressed: _valid && !_saving ? _save : null,
            ),
          ),
        ),
      ),
    );
  }
}
