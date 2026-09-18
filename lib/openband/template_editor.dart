import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'alp_tokens.dart';
import 'domain.dart';
import 'theme.dart';

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
  final TextEditingController name;
  final List<_SetDraft> sets;
  _ExerciseDraft(this.id, this.key, String label, this.sets)
    : name = TextEditingController(text: label);
}

class _SetDraft {
  final String id;
  final bool timed;
  final TextEditingController count, load;
  _SetDraft(this.id, {required this.timed, int? count, double? load})
    : count = TextEditingController(text: count?.toString() ?? ''),
      load = TextEditingController(
        text: load == null ? '' : obNumber(load, digits: 1),
      );
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
            count: s.seconds ?? s.reps,
            load: s.loadKg,
          ),
      ]),
  ];
  late final String _id =
      widget.template?.id ?? 'tpl-${DateTime.now().millisecondsSinceEpoch}';
  bool _saving = false;
  String? _error;
  int _seq = 0;

  String _next(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  void _addExercise({bool timed = false}) => setState(() {
    final id = _next('ex');
    _exercises.add(
      _ExerciseDraft(id, id, '', [
        for (var i = 0; i < 3; i++) _SetDraft(_next('set'), timed: timed),
      ]),
    );
  });

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      _exercises.isNotEmpty &&
      _exercises.every(
        (e) => e.name.text.trim().isNotEmpty && e.sets.isNotEmpty,
      );

  Future<void> _save() async {
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
                exerciseKey: e.key == e.id
                    ? e.name.text.trim().toLowerCase().replaceAll(
                        RegExp(r'[^a-z0-9äöüß]+'),
                        '_',
                      )
                    : e.key,
                name: e.name.text.trim(),
                sets: [
                  for (final s in e.sets)
                    PlannedSet(
                      id: s.id,
                      reps: s.timed ? null : int.tryParse(s.count.text),
                      seconds: s.timed ? int.tryParse(s.count.text) : null,
                      loadKg: double.tryParse(s.load.text.replaceAll(',', '.')),
                      restSec: 90,
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
          _error = 'Speichern schlägt fehl. Alle Eingaben bleiben erhalten.';
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
                      onPressed: () => setState(
                        () => e.sets.add(
                          _SetDraft(_next('set'), timed: e.sets.first.timed),
                        ),
                      ),
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
