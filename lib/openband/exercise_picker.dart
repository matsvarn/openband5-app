import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'alp_tokens.dart';
import 'confirm_sheet.dart';
import 'domain.dart';
import 'exercise_definition_editor.dart';
import 'journal_controls.dart';
import 'settings_controls.dart';
import 'theme.dart';

const _equipmentOrder = [
  'barbell',
  'dumbbell',
  'cable',
  'machine',
  'bodyweight',
  kExerciseEquipmentUnknown,
];

const _equipmentLabels = {
  'barbell': 'Langhantel',
  'dumbbell': 'Kurzhanteln',
  'cable': 'Kabelzug',
  'machine': 'Maschine',
  'bodyweight': 'Eigengewicht',
  'other': 'Andere / ohne Zuordnung',
  kExerciseEquipmentUnknown: 'Ohne Zuordnung',
};

String _muscleLabel(String id) => exerciseMuscleLabel(id);

String _equipmentLabel(String? id) {
  if (id == null || id.isEmpty) return '—';
  return _equipmentLabels[id] ?? id;
}

String _modeLabel(ExerciseCaptureMode? mode) => switch (mode) {
  ExerciseCaptureMode.repetitions => 'Wiederholungen',
  ExerciseCaptureMode.time => 'Haltezeit',
  null => 'Nicht festgelegt',
};

String? _sourceLabel(ExerciseCatalogueEntry entry) {
  if (entry.source == ExerciseDefinitionSource.preset) return 'OpenBand';
  final custom = entry.retained['custom'];
  if (custom == 1 || custom == true || custom == '1') return 'Eigene Übung';
  final explicit = entry.retained['source'];
  if (explicit == 'custom') return 'Eigene Übung';
  if (explicit == 'import' || explicit == 'imported') return 'Importiert';
  return null;
}

String _joinLabels(Iterable<String> ids, String Function(String) labelOf) {
  final parts = [for (final id in ids) labelOf(id)];
  if (parts.isEmpty) return '—';
  return parts.join(', ');
}

String _rowSubtitle(ExerciseCatalogueEntry entry, {required bool inPlan}) {
  final custom = customExerciseLibrarySubtitle(entry);
  if (custom != null) {
    if (inPlan) return '$custom\nIm Plan';
    return custom;
  }
  final parts = <String>[
    if (entry.equipment != null) _equipmentLabel(entry.equipment!.name),
    if (entry.mode != null) _modeLabel(entry.mode) else 'Erfassungsart offen',
    if (inPlan) 'Im Plan',
  ];
  return parts.join(' · ');
}

String _addLabel(int n) =>
    n == 1 ? '1 Übung hinzufügen' : '$n Übungen hinzufügen';

/// Detail pop value. Select/deselect stay distinct from a saved copy.
class ExercisePickerDetailResult {
  const ExercisePickerDetailResult._({this.selected, this.created});
  const ExercisePickerDetailResult.select() : this._(selected: true);
  const ExercisePickerDetailResult.deselect() : this._(selected: false);
  const ExercisePickerDetailResult.created(ExerciseCatalogueEntry entry)
    : this._(created: entry);

  final bool? selected;
  final ExerciseCatalogueEntry? created;
}

bool _stackFilterTriggers(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(14) > 19;

/// Library picker. Pops `[List<ExerciseCatalogueEntry>]` on confirm, or null.
class OpenBandExercisePicker extends StatefulWidget {
  const OpenBandExercisePicker({
    super.key,
    required this.repository,
    this.existingExerciseIds = const {},
    this.createOnOpen = false,
    this.initialCreateMode,
  });

  final OpenBandRepository repository;
  final Set<String> existingExerciseIds;
  final bool createOnOpen;
  final ExerciseCaptureMode? initialCreateMode;

  @override
  State<OpenBandExercisePicker> createState() => _OpenBandExercisePickerState();
}

class _OpenBandExercisePickerState extends State<OpenBandExercisePicker> {
  final _query = TextEditingController();
  final _selected = <String>{};
  Set<String> _muscles = {};
  Set<String> _equipment = {};
  ExerciseCatalogue? _catalogue;
  bool _loading = true;
  bool _error = false;
  bool _busy = false;
  bool _toggling = false;
  bool _refreshError = false;
  bool _openedCreate = false;
  ExerciseCatalogueEntry? _hiddenCreated;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    setState(() {
      _loading = true;
      _error = false;
      _refreshError = false;
    });
    try {
      final catalogue = await widget.repository.readExerciseCatalogue();
      if (!mounted || token != _loadToken) return;
      setState(() {
        _catalogue = catalogue;
        _loading = false;
        _error = false;
      });
      _scheduleCreateOnOpen();
    } catch (_) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _loading = false;
        _error = true;
        _catalogue = null;
      });
    }
  }

  void _scheduleCreateOnOpen() {
    if (!widget.createOnOpen || _openedCreate) return;
    _openedCreate = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _error) return;
      _openCreate(initialMode: widget.initialCreateMode);
    });
  }

  ExerciseCatalogue _retainKnown(
    ExerciseCatalogue? current,
    ExerciseCatalogueEntry known,
  ) {
    final entries = current?.entries ?? const <ExerciseCatalogueEntry>[];
    if (entries.any((e) => e.id == known.id)) {
      return current ?? ExerciseCatalogue(entries: entries);
    }
    return ExerciseCatalogue(
      entries: [...entries, known],
      unreadableCount: current?.unreadableCount ?? 0,
    );
  }

  Future<void> _reloadCatalogue({ExerciseCatalogueEntry? known}) async {
    final token = ++_loadToken;
    try {
      final catalogue = await widget.repository.readExerciseCatalogue();
      if (!mounted || token != _loadToken) return;
      setState(() {
        _catalogue = catalogue;
        _error = false;
        _refreshError = false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        if (known != null) {
          _catalogue = _retainKnown(_catalogue, known);
        }
        _refreshError = true;
        _loading = false;
        _error = false;
      });
    }
  }

  bool _entryVisible(ExerciseCatalogueEntry entry) {
    return filterExerciseCatalogue(
      [entry],
      query: _query.text,
      muscles: _muscles,
      equipment: _equipment,
    ).isNotEmpty;
  }

  void _dropHiddenIfVisible() {
    final hidden = _hiddenCreated;
    if (hidden != null && _entryVisible(hidden)) {
      _hiddenCreated = null;
    }
  }

  void _reveal(ExerciseCatalogueEntry entry) {
    setState(() {
      if (filterExerciseCatalogue([entry], query: _query.text).isEmpty) {
        _query.text = entry.label;
      }
      if (filterExerciseCatalogue(
        [entry],
        query: _query.text,
        muscles: _muscles,
      ).isEmpty) {
        _muscles = {};
      }
      if (filterExerciseCatalogue(
        [entry],
        query: _query.text,
        muscles: _muscles,
        equipment: _equipment,
      ).isEmpty) {
        _equipment = {};
      }
      _hiddenCreated = null;
    });
  }

  Future<void> _openCreate({ExerciseCaptureMode? initialMode}) async {
    if (_busy || _error) return;
    final created = await Navigator.of(context).push<ExerciseCatalogueEntry>(
      MaterialPageRoute(
        builder: (_) => OpenBandExerciseDefinitionEditor(
          repository: widget.repository,
          initialMode: initialMode,
        ),
      ),
    );
    if (!mounted || created == null) return;
    await _acceptCreated(created);
  }

  List<ExerciseCatalogueEntry> get _visible {
    final catalogue = _catalogue;
    if (catalogue == null) return const [];
    final visible = filterExerciseCatalogue(
      catalogue.entries,
      query: _query.text,
      muscles: _muscles,
      equipment: _equipment,
    );
    return [
      ...visible,
    ]..sort((a, b) => a.label.compareTo(b.label));
  }

  int get _hiddenSelected {
    final visible = {for (final e in _visible) e.id};
    var n = 0;
    for (final id in _selected) {
      if (!visible.contains(id)) n++;
    }
    return n;
  }

  String get _countLine {
    final visible = _visible.length;
    final parts = <String>[obExerciseCount(visible)];
    final unreadable = _catalogue?.unreadableCount ?? 0;
    if (unreadable > 0) {
      parts.add(
        unreadable == 1 ? '1 nicht lesbar' : '$unreadable nicht lesbar',
      );
    }
    final hidden = _hiddenSelected;
    if (hidden > 0) {
      parts.add(hidden == 1 ? '1 Auswahl außerhalb' : '$hidden Auswahl außerhalb');
    }
    return parts.join(' · ');
  }

  Future<void> _toggle(ExerciseCatalogueEntry entry) async {
    if (!entry.selectable || _busy || _toggling) return;
    _toggling = true;
    try {
      if (_selected.contains(entry.id)) {
        setState(() => _selected.remove(entry.id));
        return;
      }
      if (widget.existingExerciseIds.contains(entry.id)) {
        final ok = await showOpenBandConfirmSheet(
          context: context,
          title: 'Übung erneut hinzufügen?',
          confirmLabel: 'Hinzufügen',
          cancelLabel: 'Abbrechen',
        );
        if (!mounted || ok != true) return;
      }
      setState(() => _selected.add(entry.id));
    } finally {
      _toggling = false;
    }
  }

  Future<void> _acceptCreated(ExerciseCatalogueEntry created) async {
    await _reloadCatalogue(known: created);
    if (!mounted) return;
    final current = _catalogue?.byId(created.id) ?? created;
    setState(() {
      _hiddenCreated = _entryVisible(current) ? null : current;
    });
  }

  Future<void> _openDetail(ExerciseCatalogueEntry entry) async {
    final result = await Navigator.of(context).push<ExercisePickerDetailResult>(
      MaterialPageRoute(
        builder: (_) => _ExerciseDetailPage(
          repository: widget.repository,
          entry: entry,
          selected: _selected.contains(entry.id),
        ),
      ),
    );
    if (!mounted || result == null) return;
    final created = result.created;
    if (created != null) {
      await _acceptCreated(created);
      return;
    }
    if (result.selected == true) {
      if (!_selected.contains(entry.id)) await _toggle(entry);
    } else if (result.selected == false) {
      setState(() => _selected.remove(entry.id));
    }
  }

  Future<void> _openFilter() async {
    final applied = await Navigator.of(context).push<(Set<String>, Set<String>)>(
      MaterialPageRoute(
        builder: (_) => _ExerciseFilterPage(
          muscles: {..._muscles},
          equipment: {..._equipment},
        ),
      ),
    );
    if (!mounted || applied == null) return;
    setState(() {
      _muscles = applied.$1;
      _equipment = applied.$2;
      _dropHiddenIfVisible();
    });
  }

  void _clearSearch() => setState(() {
    _query.clear();
    _dropHiddenIfVisible();
  });

  void _confirm() {
    if (_busy || _selected.isEmpty || _catalogue == null) return;
    setState(() => _busy = true);
    final picked = [
      for (final e in _catalogue!.entries)
        if (_selected.contains(e.id)) e,
    ];
    Navigator.of(context).pop(picked);
  }

  String _muscleTriggerLabel() {
    if (_muscles.length == 1) return _muscleLabel(_muscles.single);
    return 'Muskelgruppen';
  }

  String _equipmentTriggerLabel() {
    if (_equipment.length == 1) return _equipmentLabel(_equipment.single);
    return 'Geräte';
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final loaded = !_loading && !_error && _catalogue != null;
    final catalogueEmpty = loaded && _catalogue!.entries.isEmpty;
    final emptyCatalogueCard = loaded && catalogueEmpty && _query.text.isEmpty;
    final searchMiss =
        loaded && _visible.isEmpty && !emptyCatalogueCard && _query.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: p.well,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OBPageHeader(
                title: 'Übungen',
                subtitle: '',
                onInfo: loaded ? _openCreate : null,
                infoIcon: LucideIcons.plus,
                infoLabel: 'Eigene Übung',
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  if (!_error) ...[
                    _SearchField(
                      controller: _query,
                      enabled: loaded,
                      onChanged: (_) => setState(_dropHiddenIfVisible),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (loaded) ...[
                    _FilterTriggers(
                      muscleLabel: _muscleTriggerLabel(),
                      equipmentLabel: _equipmentTriggerLabel(),
                      musclesActive: _muscles.isNotEmpty,
                      equipmentActive: _equipment.isNotEmpty,
                      onMuscles: _openFilter,
                      onEquipment: _openFilter,
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                      child: Text(
                        _countLine,
                        style: p
                            .text(13, color: p.muted)
                            .copyWith(height: 18 / 13),
                      ),
                    ),
                    if (_refreshError) ...[
                      const SizedBox(height: 12),
                      OBSettingsErrorCard(
                        key: const ValueKey('exercise-refresh-error'),
                        message: 'Aktualisieren fehlgeschlagen',
                        retryLabel: 'Erneut laden',
                        onRetry: () => _reloadCatalogue(),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (_visible.isNotEmpty)
                      OBCard(
                        padding: EdgeInsets.zero,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AlpRadius.card),
                          child: Column(
                            children: [
                              for (final e in _visible)
                                _ExerciseRow(
                                  entry: e,
                                  selected: _selected.contains(e.id),
                                  inPlan: widget.existingExerciseIds.contains(
                                    e.id,
                                  ),
                                  onOpen: () => _openDetail(e),
                                  onToggle: () => _toggle(e),
                                ),
                            ],
                          ),
                        ),
                      )
                    else
                      OBCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 24,
                        ),
                        child: Text(
                          emptyCatalogueCard
                              ? 'Keine Übungen'
                              : 'Keine Übungen gefunden',
                          style: p
                              .text(17, weight: FontWeight.w600)
                              .copyWith(height: 24 / 17),
                        ),
                      ),
                  ] else if (_error)
                    OBCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 24,
                      ),
                      child: Text(
                        'Bibliothek nicht geladen',
                        style: p
                            .text(17, weight: FontWeight.w600)
                            .copyWith(height: 24 / 17),
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Center(
                        child: CircularProgressIndicator.adaptive(),
                      ),
                    ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.45,
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                children: [
                  if (_hiddenCreated != null) ...[
                    _HiddenCreatedNotice(
                      key: const ValueKey('custom-exercise-saved'),
                      label: _hiddenCreated!.label,
                      onShow: () => _reveal(_hiddenCreated!),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_error)
                    OBAction('Erneut laden', ink: true, onPressed: _load)
                  else if (searchMiss)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OBAction(
                          key: const ValueKey('exercise-create-search'),
                          'Übung erstellen',
                          ink: true,
                          onPressed: _openCreate,
                        ),
                        const SizedBox(height: 8),
                        OBAction(
                          'Suche löschen',
                          ink: true,
                          secondary: true,
                          onPressed: _clearSearch,
                        ),
                      ],
                    )
                  else
                    OBAction(
                      _addLabel(_selected.length),
                      ink: true,
                      onPressed: !loaded || _selected.isEmpty || _busy
                          ? null
                          : _confirm,
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

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;
  const _SearchField({
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(LucideIcons.search, size: 20, color: p.muted),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const ValueKey('exercise-search'),
                  controller: controller,
                  enabled: enabled,
                  onChanged: onChanged,
                  style: p.text(15).copyWith(height: 20 / 15),
                  decoration: InputDecoration(
                    hintText: 'Übung suchen',
                    hintStyle: p
                        .text(15, color: p.muted)
                        .copyWith(height: 20 / 15),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterTriggers extends StatelessWidget {
  final String muscleLabel;
  final String equipmentLabel;
  final bool musclesActive;
  final bool equipmentActive;
  final VoidCallback onMuscles;
  final VoidCallback onEquipment;
  const _FilterTriggers({
    required this.muscleLabel,
    required this.equipmentLabel,
    required this.musclesActive,
    required this.equipmentActive,
    required this.onMuscles,
    required this.onEquipment,
  });

  @override
  Widget build(BuildContext context) {
    final stacked = _stackFilterTriggers(context);
    final muscles = _FilterTrigger(
      key: const ValueKey('exercise-filter-muscles'),
      label: muscleLabel,
      active: musclesActive,
      onTap: onMuscles,
    );
    final equipment = _FilterTrigger(
      key: const ValueKey('exercise-filter-equipment'),
      label: equipmentLabel,
      active: equipmentActive,
      onTap: onEquipment,
    );
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [muscles, const SizedBox(height: 8), equipment],
      );
    }
    return Row(
      children: [
        Expanded(child: muscles),
        const SizedBox(width: 8),
        Expanded(child: equipment),
      ],
    );
  }
}

class _FilterTrigger extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _FilterTrigger({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Material(
      color: active ? p.ink : p.card,
      borderRadius: BorderRadius.circular(AlpRadius.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: p
                    .text(14)
                    .copyWith(
                      height: 19 / 14,
                      color: active ? p.card : p.ink,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  final ExerciseCatalogueEntry entry;
  final bool selected;
  final bool inPlan;
  final VoidCallback onOpen;
  final VoidCallback onToggle;
  const _ExerciseRow({
    required this.entry,
    required this.selected,
    required this.inPlan,
    required this.onOpen,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final subtitle = _rowSubtitle(entry, inPlan: inPlan);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 76),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                key: ValueKey('exercise-open-${entry.id}'),
                onTap: onOpen,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.label,
                      style: p
                          .text(15, weight: FontWeight.w600)
                          .copyWith(height: 20 / 15),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: p
                            .text(13, color: p.muted)
                            .copyWith(height: 18 / 13),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 44,
              height: 44,
              child: Material(
                color: selected ? p.ink : p.well,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: IconButton(
                  key: ValueKey('exercise-select-${entry.id}'),
                  tooltip: 'Auswahl ${entry.label}',
                  onPressed: entry.selectable ? onToggle : null,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                  icon: Icon(
                    selected ? LucideIcons.check : LucideIcons.plus,
                    size: 20,
                    color: selected
                        ? (p.dark ? p.canvas : Colors.white)
                        : p.ink,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseFilterPage extends StatefulWidget {
  final Set<String> muscles;
  final Set<String> equipment;
  const _ExerciseFilterPage({required this.muscles, required this.equipment});

  @override
  State<_ExerciseFilterPage> createState() => _ExerciseFilterPageState();
}

class _ExerciseFilterPageState extends State<_ExerciseFilterPage> {
  late final Set<String> _muscles = {...widget.muscles};
  late final Set<String> _equipment = {...widget.equipment};

  void _toggle(Set<String> target, String id) {
    setState(() {
      if (target.contains(id)) {
        target.remove(id);
      } else {
        target.add(id);
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
              child: OBPageHeader(title: 'Filter', subtitle: ''),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  _FilterGroup(
                    title: 'Muskelgruppen',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final id in kExerciseMuscleIds)
                          OBJournalChip(
                            key: ValueKey('filter-muscle-$id'),
                            label: _muscleLabel(id),
                            selected: _muscles.contains(id),
                            onTap: () => _toggle(_muscles, id),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FilterGroup(
                    title: 'Geräte',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final id in _equipmentOrder)
                          OBJournalChip(
                            key: ValueKey('filter-equipment-$id'),
                            label: _equipmentLabel(id),
                            selected: _equipment.contains(id),
                            onTap: () => _toggle(_equipment, id),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: TextButton(
                        onPressed: () => setState(() {
                          _muscles.clear();
                          _equipment.clear();
                        }),
                        child: Text(
                          'Zurücksetzen',
                          textAlign: TextAlign.center,
                          style: p.text(14).copyWith(height: 19 / 14, color: p.ink),
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
                'Filter anwenden',
                ink: true,
                onPressed: () =>
                    Navigator.of(context).pop((_muscles, _equipment)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterGroup extends StatelessWidget {
  final String title;
  final Widget child;
  const _FilterGroup({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return OBCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: p.text(15, weight: FontWeight.w600).copyWith(height: 20 / 15),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _ExerciseDetailPage extends StatelessWidget {
  final OpenBandRepository repository;
  final ExerciseCatalogueEntry entry;
  final bool selected;
  const _ExerciseDetailPage({
    required this.repository,
    required this.entry,
    required this.selected,
  });

  Future<void> _copy(BuildContext context) async {
    final created = await Navigator.of(context).push<ExerciseCatalogueEntry>(
      MaterialPageRoute(
        builder: (_) => OpenBandExerciseDefinitionEditor(
          repository: repository,
          copyFrom: entry,
        ),
      ),
    );
    if (!context.mounted || created == null) return;
    Navigator.of(context).pop(ExercisePickerDetailResult.created(created));
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final rows = [
      ('Gerät', _equipmentLabel(entry.equipment?.name)),
      ('Erfassung', _modeLabel(entry.mode)),
      if (entry.loadBasis != null)
        (
          'Gewichtsangabe',
          loadBasisChoiceLabel(entry.loadBasis!, entry.equipment),
        ),
      if (entry.deviceCount != null)
        (deviceCountRowLabel(entry.equipment), '${entry.deviceCount}'),
      if (entry.mode == ExerciseCaptureMode.repetitions &&
          entry.repetitionBasis != null)
        (
          'Wiederholungen',
          entry.repetitionBasis == ExerciseRepetitionBasis.perSide
              ? 'Je Seite'
              : 'Gesamt',
        ),
      ('Primär', _joinLabels(entry.primaryMuscles, _muscleLabel)),
      ('Sekundär', _joinLabels(entry.secondaryMuscles, _muscleLabel)),
    ];
    return Scaffold(
      backgroundColor: p.well,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OBPageHeader(
                key: const ValueKey('exercise-copy'),
                title: 'Übung',
                subtitle: '',
                onInfo: () => _copy(context),
                infoIcon: LucideIcons.copy,
                infoLabel: 'Kopieren',
              ),
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
                          entry.label,
                          style: p
                              .text(28, weight: FontWeight.w700, display: true)
                              .copyWith(height: 34 / 28),
                        ),
                        if (_sourceLabel(entry) case final source?) ...[
                          const SizedBox(height: 8),
                          Text(
                            source,
                            style: p
                                .text(13, color: p.muted)
                                .copyWith(height: 18 / 13),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  OBCard(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        for (final (i, row) in rows.indexed) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: p.line,
                              indent: 20,
                              endIndent: 20,
                            ),
                          OBSettingsValueRow(
                            label: row.$1,
                            value: row.$2,
                            comfortable: true,
                            interactive: false,
                            chevron: false,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: OBAction(
                selected ? 'Auswahl entfernen' : 'Auswählen',
                ink: true,
                onPressed: selected
                    ? () => Navigator.of(context).pop(
                        const ExercisePickerDetailResult.deselect(),
                      )
                    : !entry.selectable
                    ? null
                    : () => Navigator.of(context).pop(
                        const ExercisePickerDetailResult.select(),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HiddenCreatedNotice extends StatelessWidget {
  final String label;
  final VoidCallback onShow;
  const _HiddenCreatedNotice({
    super.key,
    required this.label,
    required this.onShow,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final stacked = MediaQuery.textScalerOf(context).scale(15) > 20;
    final name = Text(
      label,
      style: p.text(15, weight: FontWeight.w500).copyWith(height: 20 / 15),
    );
    final action = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onShow,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Align(
            alignment: stacked
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: Text(
              'Anzeigen',
              style: p
                  .text(15, weight: FontWeight.w600)
                  .copyWith(height: 20 / 15),
            ),
          ),
        ),
      ),
    );
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [name, action],
                )
              : Row(
                  children: [
                    Expanded(child: name),
                    const SizedBox(width: 12),
                    action,
                  ],
                ),
        ),
      ),
    );
  }
}
