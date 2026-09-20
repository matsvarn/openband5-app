import 'package:flutter/material.dart';

import 'domain.dart';
import 'journal_controls.dart';
import 'settings_controls.dart';
import 'theme.dart';

const kExerciseMuscleIds = [
  'chest',
  'back',
  'shoulders',
  'biceps',
  'triceps',
  'legs',
  'glutes',
  'core',
  'forearms',
];

const kExerciseMuscleLabels = {
  'chest': 'Brust',
  'back': 'Rücken',
  'shoulders': 'Schultern',
  'biceps': 'Bizeps',
  'triceps': 'Trizeps',
  'legs': 'Beine',
  'glutes': 'Po',
  'core': 'Rumpf',
  'forearms': 'Unterarm',
};

const _equipmentChoices = <(ExerciseEquipmentCategory, String)>[
  (ExerciseEquipmentCategory.barbell, 'Langhantel'),
  (ExerciseEquipmentCategory.dumbbell, 'Kurzhantel'),
  (ExerciseEquipmentCategory.cable, 'Kabelzug'),
  (ExerciseEquipmentCategory.machine, 'Maschine'),
  (ExerciseEquipmentCategory.bodyweight, 'Eigengewicht'),
  (ExerciseEquipmentCategory.other, 'Andere / ohne Zuordnung'),
];

const _modeChoices = <(ExerciseCaptureMode, String)>[
  (ExerciseCaptureMode.repetitions, 'Wiederholungen'),
  (ExerciseCaptureMode.time, 'Haltezeit'),
];

const _repetitionChoices = <(ExerciseRepetitionBasis, String)>[
  (ExerciseRepetitionBasis.total, 'Gesamt'),
  (ExerciseRepetitionBasis.perSide, 'Je Seite'),
];

String exerciseMuscleLabel(String id) => kExerciseMuscleLabels[id] ?? id;

String _joinMuscles(Iterable<String> ids) {
  final parts = [for (final id in ids) exerciseMuscleLabel(id)];
  if (parts.isEmpty) return '—';
  return parts.join(', ');
}

String _equipmentLabel(ExerciseEquipmentCategory equipment) {
  for (final choice in _equipmentChoices) {
    if (choice.$1 == equipment) return choice.$2;
  }
  return equipment.name;
}

String _modeLabel(ExerciseCaptureMode mode) => switch (mode) {
  ExerciseCaptureMode.repetitions => 'Wiederholungen',
  ExerciseCaptureMode.time => 'Haltezeit',
};

String loadBasisChoiceLabel(
  ExerciseLoadBasis basis,
  ExerciseEquipmentCategory? equipment,
) => switch (basis) {
  ExerciseLoadBasis.total => 'Gesamtgewicht',
  ExerciseLoadBasis.perDevice =>
    equipment == ExerciseEquipmentCategory.dumbbell ? 'Je Hantel' : 'Je Gerät',
  ExerciseLoadBasis.bodyweight => 'Eigengewicht',
  ExerciseLoadBasis.addedLoad => 'Zusatzgewicht',
  ExerciseLoadBasis.assistance => 'Unterstützung',
};

String deviceCountRowLabel(ExerciseEquipmentCategory? equipment) =>
    equipment == ExerciseEquipmentCategory.dumbbell
    ? 'Anzahl Hanteln'
    : 'Anzahl Geräte';

List<(ExerciseLoadBasis, String)> loadBasisChoices(
  ExerciseEquipmentCategory? equipment,
) => [
  (ExerciseLoadBasis.total, 'Gesamtgewicht'),
  (
    ExerciseLoadBasis.perDevice,
    equipment == ExerciseEquipmentCategory.dumbbell ? 'Je Hantel' : 'Je Gerät',
  ),
  (ExerciseLoadBasis.bodyweight, 'Eigengewicht'),
  (ExerciseLoadBasis.addedLoad, 'Zusatzgewicht'),
  (ExerciseLoadBasis.assistance, 'Unterstützung'),
];

String? customExerciseLibrarySubtitle(ExerciseCatalogueEntry entry) {
  final hasTyped =
      entry.loadBasis != null ||
      entry.deviceCount != null ||
      entry.repetitionBasis != null;
  if (!hasTyped) return null;
  final line1 = <String>[];
  if (entry.loadBasis == ExerciseLoadBasis.perDevice &&
      entry.deviceCount != null) {
    final n = entry.deviceCount!;
    final noun = entry.equipment == ExerciseEquipmentCategory.dumbbell
        ? (n == 1 ? 'Hantel' : 'Hanteln')
        : (n == 1 ? 'Gerät' : 'Geräte');
    line1.add('$n $noun');
    line1.add(
      entry.equipment == ExerciseEquipmentCategory.dumbbell
          ? 'je Hantel'
          : 'je Gerät',
    );
  } else if (entry.loadBasis != null) {
    line1.add(loadBasisChoiceLabel(entry.loadBasis!, entry.equipment));
  }
  final line2 = <String>[];
  if (entry.mode == ExerciseCaptureMode.repetitions &&
      entry.repetitionBasis != null) {
    line2.add(
      entry.repetitionBasis == ExerciseRepetitionBasis.perSide
          ? 'Wdh. je Seite'
          : 'Wdh. gesamt',
    );
  } else if (entry.mode == ExerciseCaptureMode.time) {
    line2.add('Haltezeit');
  }
  final lines = [
    if (line1.isNotEmpty) line1.join(' · '),
    if (line2.isNotEmpty) line2.join(' · '),
  ];
  if (lines.isEmpty) return null;
  return lines.join('\n');
}

/// Typed custom-definition editor. Pops the saved [ExerciseCatalogueEntry],
/// or null on cancel. One id is allocated for the whole form lifetime.
class OpenBandExerciseDefinitionEditor extends StatefulWidget {
  const OpenBandExerciseDefinitionEditor({
    super.key,
    required this.repository,
    this.initialMode,
  });

  final OpenBandRepository repository;
  final ExerciseCaptureMode? initialMode;

  @override
  State<OpenBandExerciseDefinitionEditor> createState() =>
      _OpenBandExerciseDefinitionEditorState();
}

class _OpenBandExerciseDefinitionEditorState
    extends State<OpenBandExerciseDefinitionEditor> {
  late final String _id = newCustomExerciseId();
  final _label = TextEditingController();
  ExerciseEquipmentCategory? _equipment;
  ExerciseCaptureMode? _mode;
  ExerciseLoadBasis? _loadBasis;
  int? _deviceCount;
  ExerciseRepetitionBasis? _repetitionBasis;
  final _primary = <String>{};
  final _secondary = <String>{};
  bool _busy = false;
  bool _saveError = false;
  bool _conflicted = false;
  ExerciseCatalogueEntry? _conflict;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  bool get _weightReady => _equipment != null && _mode != null;

  bool get _canSave {
    if (_label.text.trim().isEmpty) return false;
    if (_equipment == null || _mode == null || _loadBasis == null) return false;
    if (_loadBasis == ExerciseLoadBasis.perDevice) {
      if (_deviceCount == null || _deviceCount! < 1) return false;
    } else if (_deviceCount != null) {
      return false;
    }
    if (_mode == ExerciseCaptureMode.repetitions) {
      if (_repetitionBasis == null) return false;
    } else if (_repetitionBasis != null) {
      return false;
    }
    return true;
  }

  CustomExerciseDraft get _draft => CustomExerciseDraft(
    id: _id,
    label: _label.text.trim(),
    mode: _mode!,
    equipment: _equipment!,
    loadBasis: _loadBasis!,
    deviceCount: _loadBasis == ExerciseLoadBasis.perDevice
        ? _deviceCount
        : null,
    repetitionBasis: _mode == ExerciseCaptureMode.repetitions
        ? _repetitionBasis
        : null,
    primaryMuscles: _primary.toList(),
    secondaryMuscles: _secondary.toList(),
  );

  void _setEquipment(ExerciseEquipmentCategory equipment) {
    setState(() => _equipment = equipment);
  }

  void _setMode(ExerciseCaptureMode mode) {
    setState(() {
      _mode = mode;
      if (mode == ExerciseCaptureMode.time) {
        _repetitionBasis = null;
      }
    });
  }

  void _setLoadBasis(ExerciseLoadBasis basis) {
    setState(() {
      _loadBasis = basis;
      if (basis != ExerciseLoadBasis.perDevice) {
        _deviceCount = null;
      }
    });
  }

  Future<void> _pickEquipment() async {
    if (_busy) return;
    final picked = await showOpenBandSettingsChoiceSheet(
      context: context,
      title: 'Gerät',
      choices: _equipmentChoices,
      selected: _equipment,
      barrierColor: const Color(0x52000000),
      sheetKey: const ValueKey('custom-exercise-equipment-sheet'),
      choiceKey: (value) => ValueKey('custom-exercise-equipment-${value.name}'),
    );
    if (!mounted || picked == null) return;
    _setEquipment(picked);
  }

  Future<void> _pickMode() async {
    if (_busy) return;
    final picked = await showOpenBandSettingsChoiceSheet(
      context: context,
      title: 'Erfassung',
      choices: _modeChoices,
      selected: _mode,
      barrierColor: const Color(0x52000000),
      sheetKey: const ValueKey('custom-exercise-mode-sheet'),
      choiceKey: (value) => ValueKey('custom-exercise-mode-${value.name}'),
    );
    if (!mounted || picked == null) return;
    _setMode(picked);
  }

  Future<void> _pickLoadBasis() async {
    if (_busy || !_weightReady) return;
    final picked = await showOpenBandSettingsChoiceSheet(
      context: context,
      title: 'Gewichtsangabe',
      choices: loadBasisChoices(_equipment),
      selected: _loadBasis,
      barrierColor: const Color(0x52000000),
      sheetKey: const ValueKey('custom-exercise-load-sheet'),
      choiceKey: (value) => ValueKey('custom-exercise-load-${value.name}'),
    );
    if (!mounted || picked == null) return;
    _setLoadBasis(picked);
  }

  Future<void> _pickCount() async {
    if (_busy || _loadBasis != ExerciseLoadBasis.perDevice) return;
    final picked = await showOpenBandSettingsCountSheet(
      context: context,
      title: deviceCountRowLabel(_equipment),
      value: _deviceCount,
      sheetKey: const ValueKey('custom-exercise-count-sheet'),
    );
    if (!mounted || picked == null) return;
    setState(() => _deviceCount = picked);
  }

  Future<void> _pickRepetition() async {
    if (_busy || _mode != ExerciseCaptureMode.repetitions) return;
    final picked = await showOpenBandSettingsChoiceSheet(
      context: context,
      title: 'Wiederholungen',
      choices: _repetitionChoices,
      selected: _repetitionBasis,
      barrierColor: const Color(0x52000000),
      sheetKey: const ValueKey('custom-exercise-reps-sheet'),
      choiceKey: (value) => ValueKey('custom-exercise-reps-${value.name}'),
    );
    if (!mounted || picked == null) return;
    setState(() => _repetitionBasis = picked);
  }

  Future<void> _pickMuscles({required bool primary}) async {
    if (_busy) return;
    final selected = primary ? {..._primary} : {..._secondary};
    final applied = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute(
        builder: (_) => _MuscleRolePage(
          primary: primary,
          selected: selected,
        ),
      ),
    );
    if (!mounted || applied == null) return;
    setState(() {
      if (primary) {
        _primary
          ..clear()
          ..addAll(applied);
        _secondary.removeAll(applied);
      } else {
        _secondary
          ..clear()
          ..addAll(applied);
        _primary.removeAll(applied);
      }
    });
  }

  Future<void> _save() async {
    if (_busy || !_canSave) return;
    setState(() {
      _busy = true;
      _saveError = false;
      _conflicted = false;
      _conflict = null;
    });
    CustomExerciseWriteResult result;
    try {
      result = await widget.repository.createCustomExercise(_draft);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _saveError = true;
      });
      return;
    }
    if (!mounted) return;
    if (result.saved && result.current != null) {
      Navigator.of(context).pop(result.current);
      return;
    }
    setState(() {
      _busy = false;
      if (result.conflict) {
        _conflicted = true;
        _conflict = result.current;
        _saveError = false;
      } else {
        _saveError = true;
      }
    });
  }

  void _info() {
    showOpenBandJournalInfo(
      context,
      title: 'Eigene Übung',
      body:
          'Je Hantel ist das Gewicht einer einzelnen Hantel, nicht die Summe.\n'
          'Je Seite sind Wiederholungen für eine Seite, nicht die Summe beider Seiten.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Scaffold(
      backgroundColor: p.well,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OBPageHeader(
                title: 'Eigene Übung',
                subtitle: '',
                onInfo: _info,
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  OBCard(
                    padding: const EdgeInsets.all(14),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 32),
                      child: TextField(
                        key: const ValueKey('custom-exercise-name'),
                        controller: _label,
                        enabled: !_busy,
                        onChanged: (_) => setState(() {}),
                        style: p
                            .text(20, weight: FontWeight.w700, display: true)
                            .copyWith(height: 27 / 20),
                        decoration: InputDecoration(
                          hintText: 'Name der Übung',
                          hintStyle: p
                              .text(
                                20,
                                weight: FontWeight.w700,
                                display: true,
                                color: p.muted,
                              )
                              .copyWith(height: 27 / 20),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OBCard(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        OBSettingsValueRow(
                          key: const ValueKey('custom-exercise-equipment'),
                          label: 'Gerät',
                          value: _equipment == null
                              ? 'Auswählen'
                              : _equipmentLabel(_equipment!),
                          comfortable: true,
                          chevron: true,
                          mutedValue: _equipment == null,
                          interactive: !_busy,
                          onTap: _busy ? null : _pickEquipment,
                        ),
                        OBSettingsValueRow(
                          key: const ValueKey('custom-exercise-mode'),
                          label: 'Erfassung',
                          value: _mode == null
                              ? 'Auswählen'
                              : _modeLabel(_mode!),
                          comfortable: true,
                          chevron: true,
                          mutedValue: _mode == null,
                          interactive: !_busy,
                          onTap: _busy ? null : _pickMode,
                        ),
                        if (_weightReady) ...[
                          OBSettingsValueRow(
                            key: const ValueKey('custom-exercise-load'),
                            label: 'Gewichtsangabe',
                            value: _loadBasis == null
                                ? 'Auswählen'
                                : loadBasisChoiceLabel(_loadBasis!, _equipment),
                            comfortable: true,
                            chevron: true,
                            mutedValue: _loadBasis == null,
                            interactive: !_busy,
                            onTap: _busy ? null : _pickLoadBasis,
                          ),
                          if (_loadBasis == ExerciseLoadBasis.perDevice)
                            OBSettingsValueRow(
                              key: const ValueKey('custom-exercise-count'),
                              label: deviceCountRowLabel(_equipment),
                              value: _deviceCount == null
                                  ? 'Auswählen'
                                  : '$_deviceCount',
                              comfortable: true,
                              chevron: true,
                              mutedValue: _deviceCount == null,
                              interactive: !_busy,
                              onTap: _busy ? null : _pickCount,
                            ),
                          if (_mode == ExerciseCaptureMode.repetitions)
                            OBSettingsValueRow(
                              key: const ValueKey('custom-exercise-reps'),
                              label: 'Wiederholungen',
                              value: _repetitionBasis == null
                                  ? 'Auswählen'
                                  : _repetitionBasis ==
                                        ExerciseRepetitionBasis.perSide
                                  ? 'Je Seite'
                                  : 'Gesamt',
                              comfortable: true,
                              chevron: true,
                              mutedValue: _repetitionBasis == null,
                              interactive: !_busy,
                              onTap: _busy ? null : _pickRepetition,
                            ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  OBCard(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                          child: Text(
                            'Muskelgruppen',
                            style: p
                                .text(13, color: p.muted)
                                .copyWith(height: 18 / 13),
                          ),
                        ),
                        OBSettingsValueRow(
                          key: const ValueKey('custom-exercise-primary'),
                          label: 'Primär',
                          value: _joinMuscles(_primary),
                          comfortable: true,
                          chevron: true,
                          interactive: !_busy,
                          onTap: _busy
                              ? null
                              : () => _pickMuscles(primary: true),
                        ),
                        OBSettingsValueRow(
                          key: const ValueKey('custom-exercise-secondary'),
                          label: 'Sekundär',
                          value: _joinMuscles(_secondary),
                          comfortable: true,
                          chevron: true,
                          interactive: !_busy,
                          onTap: _busy
                              ? null
                              : () => _pickMuscles(primary: false),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_saveError) ...[
                    Text(
                      'Speichern fehlgeschlagen',
                      style: p
                          .text(14, color: p.danger)
                          .copyWith(height: 20 / 14),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_conflicted) ...[
                    Text(
                      _conflict == null
                          ? 'Übung existiert bereits'
                          : 'Konflikt: ${_conflict!.label}',
                      style: p
                          .text(14, color: p.danger)
                          .copyWith(height: 20 / 14),
                    ),
                    const SizedBox(height: 16),
                    OBAction(
                      'Zurück',
                      ink: true,
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                  ] else
                    OBAction(
                      key: const ValueKey('custom-exercise-save'),
                      _saveError ? 'Erneut speichern' : 'Übung speichern',
                      ink: true,
                      onPressed: _busy || !_canSave ? null : _save,
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

class _MuscleRolePage extends StatefulWidget {
  final bool primary;
  final Set<String> selected;
  const _MuscleRolePage({
    required this.primary,
    required this.selected,
  });

  @override
  State<_MuscleRolePage> createState() => _MuscleRolePageState();
}

class _MuscleRolePageState extends State<_MuscleRolePage> {
  late final Set<String> _selected = {...widget.selected};

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Scaffold(
      backgroundColor: p.well,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: OBPageHeader(title: 'Muskelgruppen', subtitle: ''),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  OBCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.primary ? 'Primär' : 'Sekundär',
                          key: const ValueKey('custom-muscle-role'),
                          style: p
                              .text(15, weight: FontWeight.w600)
                              .copyWith(height: 20 / 15),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final id in kExerciseMuscleIds)
                              OBJournalChip(
                                key: ValueKey('custom-muscle-$id'),
                                label: exerciseMuscleLabel(id),
                                selected: _selected.contains(id),
                                onTap: () => _toggle(id),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: TextButton(
                        onPressed: () => setState(() => _selected.clear()),
                        child: Text(
                          'Zurücksetzen',
                          textAlign: TextAlign.center,
                          style: p.text(14).copyWith(
                            height: 19 / 14,
                            color: p.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: OBAction(
                'Übernehmen',
                ink: true,
                onPressed: () => Navigator.of(context).pop(_selected),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
