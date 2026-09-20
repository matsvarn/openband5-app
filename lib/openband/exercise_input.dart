import 'package:flutter/material.dart';

import 'exercise_catalogue.dart';
import 'exercise_load.dart';
import 'settings_controls.dart';

/// Shared original-load display and capture for the template editor and
/// live session. Normalization stays in [normalizeExerciseLoad] /
/// [resolveStoredLoadKg].
String formatOriginalLoadValue(double? value) {
  if (value == null) return '';
  if (value == value.roundToDouble()) return value.round().toString();
  final tenths = value * 10;
  if (tenths == tenths.roundToDouble()) {
    return (tenths.round() / 10).toStringAsFixed(1).replaceAll('.', ',');
  }
  var s = value.toStringAsFixed(10);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return s.replaceAll('.', ',');
}

String loadUnitLabel(ExerciseLoadUnit unit) =>
    unit == ExerciseLoadUnit.lb ? 'lb' : 'kg';

String exerciseSideLabel(ExerciseSetSide side) => switch (side) {
  ExerciseSetSide.both => 'Beide Seiten',
  ExerciseSetSide.left => 'Links',
  ExerciseSetSide.right => 'Rechts',
};

const exerciseSideChoices = <(ExerciseSetSide, String)>[
  (ExerciseSetSide.both, 'Beide Seiten'),
  (ExerciseSetSide.left, 'Links'),
  (ExerciseSetSide.right, 'Rechts'),
];

const exerciseUnitChoices = <(ExerciseLoadUnit, String)>[
  (ExerciseLoadUnit.kg, 'kg'),
  (ExerciseLoadUnit.lb, 'lb'),
];

ExerciseLoadBasis? exerciseLoadBasis({
  ExerciseDefinitionSnapshot? definition,
  OriginalLoadInput? load,
}) {
  // A present source snapshot is authoritative, including an unknown future
  // wire value retained by the decoder. Never reinterpret it using today's
  // definition.
  if (load != null) return load.basis;
  return definition?.loadBasis;
}

ExerciseRepetitionBasis? exerciseRepetitionBasis({
  ExerciseDefinitionSnapshot? definition,
  OriginalLoadInput? load,
}) {
  if (load != null) return load.repetitionBasis;
  return definition?.repetitionBasis;
}

bool _hasUnknownSemantic(Map<String, Object?> retained) =>
    retained.containsKey('basis') ||
    retained.containsKey('unit') ||
    retained.containsKey('repetitionBasis') ||
    retained.containsKey('side');

bool hasUnsupportedLoadMetadata({
  ExerciseDefinitionSnapshot? definition,
  OriginalLoadInput? load,
}) {
  if (load != null) {
    return load.basis == null || _hasUnknownSemantic(load.retained);
  }
  return definition != null &&
      (definition.retained.containsKey('loadBasis') ||
          definition.retained.containsKey('repetitionBasis'));
}

bool showsExternalLoad({
  ExerciseDefinitionSnapshot? definition,
  OriginalLoadInput? load,
  required bool timed,
  double? historicLoadKg,
}) {
  final basis = exerciseLoadBasis(definition: definition, load: load);
  switch (basis) {
    case ExerciseLoadBasis.bodyweight:
      return false;
    case ExerciseLoadBasis.assistance:
    case ExerciseLoadBasis.total:
    case ExerciseLoadBasis.perDevice:
    case ExerciseLoadBasis.addedLoad:
      return true;
    case null:
      if (timed) return historicLoadKg != null || load?.value != null;
      return true;
  }
}

/// Persisted rows are typed only when they carry original-load metadata.
/// Template drafts track their explicit typed identity separately; a persisted
/// missing load must never inherit semantics from a newer definition.
bool isTypedLoadRow({
  OriginalLoadInput? load,
  double? historicKg,
  ExerciseDefinitionSnapshot? definition,
}) => load?.basis != null;

ExerciseDefinitionSnapshot? frozenDefinition({
  required OriginalLoadInput? load,
  required bool typed,
  ExerciseDefinitionSnapshot? definition,
}) => (load != null || typed) ? definition : null;

bool showsSideControl({
  ExerciseDefinitionSnapshot? definition,
  OriginalLoadInput? load,
}) =>
    !hasUnsupportedLoadMetadata(definition: definition, load: load) &&
    exerciseRepetitionBasis(definition: definition, load: load) ==
        ExerciseRepetitionBasis.perSide;

bool showsUnitChoice({
  ExerciseDefinitionSnapshot? definition,
  OriginalLoadInput? load,
}) {
  if (hasUnsupportedLoadMetadata(definition: definition, load: load)) {
    return false;
  }
  final basis = exerciseLoadBasis(definition: definition, load: load);
  return basis == ExerciseLoadBasis.total ||
      basis == ExerciseLoadBasis.perDevice ||
      basis == ExerciseLoadBasis.addedLoad ||
      basis == ExerciseLoadBasis.assistance;
}

/// Stored unit for headings. Unknown originals stay unit-less; legacy totals
/// are kg. A chosen unit only applies to typed/known originals.
ExerciseLoadUnit? storedLoadUnit({
  OriginalLoadInput? load,
  required bool typed,
  double? historicKg,
  ExerciseLoadUnit? chosen,
}) {
  if (load != null &&
      (load.basis == null || _hasUnknownSemantic(load.retained))) {
    return null;
  }
  if (typed || load != null) return chosen ?? load?.unit;
  if (historicKg != null) return ExerciseLoadUnit.kg;
  return null;
}

/// Concise 13/18 caption. Unknown rows return null and keep the current layout.
String? exerciseLoadCaption({
  ExerciseDefinitionSnapshot? definition,
  OriginalLoadInput? load,
  ExerciseLoadUnit? unit,
  bool includeUnit = true,
}) {
  if (hasUnsupportedLoadMetadata(definition: definition, load: load)) {
    return null;
  }
  final basis = exerciseLoadBasis(definition: definition, load: load);
  final repetition = exerciseRepetitionBasis(
    definition: definition,
    load: load,
  );
  final resolvedUnit = unit ?? load?.unit ?? ExerciseLoadUnit.kg;
  final unitLabel = loadUnitLabel(resolvedUnit);
  final parts = <String>[];
  switch (basis) {
    case ExerciseLoadBasis.perDevice:
      final device = definition?.equipment == ExerciseEquipmentCategory.dumbbell
          ? 'Hantel'
          : 'Gerät';
      parts.add(includeUnit ? '$unitLabel je $device' : 'je $device');
    case ExerciseLoadBasis.assistance:
      parts.add(includeUnit ? '$unitLabel Unterstützung' : 'Unterstützung');
    case ExerciseLoadBasis.total:
      if (includeUnit) parts.add(unitLabel);
    case ExerciseLoadBasis.addedLoad:
      parts.add(includeUnit ? '$unitLabel Zusatzgewicht' : 'Zusatzgewicht');
    case ExerciseLoadBasis.bodyweight:
    case null:
      break;
  }
  if (repetition == ExerciseRepetitionBasis.perSide) {
    parts.add('Wdh. je Seite');
  }
  if (parts.isEmpty) return null;
  return parts.join(' · ');
}

class ExerciseLoadRowView {
  const ExerciseLoadRowView({
    this.load,
    this.typed = false,
    this.historicKg,
    this.chosenUnit,
  });
  final OriginalLoadInput? load;
  final bool typed;
  final double? historicKg;
  final ExerciseLoadUnit? chosenUnit;
}

class ExerciseBlockLoadLabels {
  const ExerciseBlockLoadLabels({
    required this.caption,
    required this.mixedSemantics,
    required this.mixedUnits,
    required this.loadHeader,
  });
  final String? caption;
  final bool mixedSemantics;
  final bool mixedUnits;
  final String loadHeader;
}

String _rowSemanticsKey({
  required ExerciseDefinitionSnapshot? definition,
  required ExerciseLoadRowView row,
}) {
  final def = frozenDefinition(
    load: row.load,
    typed: row.typed,
    definition: definition,
  );
  if (hasUnsupportedLoadMetadata(definition: def, load: row.load)) {
    return 'unsupported';
  }
  final basis =
      exerciseLoadBasis(definition: def, load: row.load) ??
      (row.historicKg != null ? ExerciseLoadBasis.total : null);
  final repetition =
      exerciseRepetitionBasis(definition: def, load: row.load) ??
      ExerciseRepetitionBasis.total;
  return '${basis?.name ?? 'none'}|${repetition.name}';
}

/// Common caption only when every visible row shares one known interpretation.
ExerciseBlockLoadLabels exerciseBlockLoadLabels({
  ExerciseDefinitionSnapshot? definition,
  required List<ExerciseLoadRowView> rows,
}) {
  if (rows.isEmpty) {
    return const ExerciseBlockLoadLabels(
      caption: null,
      mixedSemantics: false,
      mixedUnits: false,
      loadHeader: 'KG',
    );
  }
  final keys = {
    for (final row in rows) _rowSemanticsKey(definition: definition, row: row),
  };
  final mixedSemantics = keys.length > 1;
  final units = {
    for (final row in rows)
      storedLoadUnit(
        load: row.load,
        typed: row.typed,
        historicKg: row.historicKg,
        chosen: row.chosenUnit,
      ),
  };
  final known = units.whereType<ExerciseLoadUnit>().toSet();
  final mixedUnits =
      known.length > 1 || (units.contains(null) && known.isNotEmpty);
  final loadHeader = !mixedUnits && known.length == 1
      ? loadUnitLabel(known.single).toUpperCase()
      : 'LAST';
  if (mixedSemantics) {
    return ExerciseBlockLoadLabels(
      caption: null,
      mixedSemantics: true,
      mixedUnits: mixedUnits,
      loadHeader: loadHeader,
    );
  }
  final first = rows.first;
  final def = frozenDefinition(
    load: first.load,
    typed: first.typed,
    definition: definition,
  );
  return ExerciseBlockLoadLabels(
    caption: exerciseLoadCaption(
      definition: def,
      load: first.load,
      unit: known.length == 1 ? known.single : null,
      includeUnit: !mixedUnits,
    ),
    mixedSemantics: false,
    mixedUnits: mixedUnits,
    loadHeader: loadHeader,
  );
}

/// Per-row basis caption for mixed blocks. Uniform blocks omit this copy.
String? exerciseRowLoadCaption({
  ExerciseDefinitionSnapshot? definition,
  OriginalLoadInput? load,
  bool typed = false,
  double? historicLoadKg,
}) {
  final def = frozenDefinition(
    load: load,
    typed: typed,
    definition: definition,
  );
  if (hasUnsupportedLoadMetadata(definition: def, load: load)) return '—';
  final basis =
      exerciseLoadBasis(definition: def, load: load) ??
      (historicLoadKg != null ? ExerciseLoadBasis.total : null);
  if (basis == ExerciseLoadBasis.total) {
    final repetition = exerciseRepetitionBasis(definition: def, load: load);
    return repetition == ExerciseRepetitionBasis.perSide
        ? 'Gesamtgewicht · Wdh. je Seite'
        : 'Gesamtgewicht';
  }
  return exerciseLoadCaption(definition: def, load: load, includeUnit: false);
}

int? actualDeviceCount({
  required ExerciseLoadBasis? basis,
  int? definitionCount,
  int? existingCount,
  ExerciseSetSide? existingSide,
  required ExerciseSetSide side,
}) {
  if (basis != ExerciseLoadBasis.perDevice) return null;
  // Untouched source metadata wins over a later/default definition count.
  if (existingCount != null && (existingSide ?? ExerciseSetSide.both) == side) {
    return existingCount;
  }
  if (side == ExerciseSetSide.left || side == ExerciseSetSide.right) return 1;
  return definitionCount ?? existingCount;
}

bool capturesOriginalLoad({
  required bool typed,
  OriginalLoadInput? existing,
  ExerciseDefinitionSnapshot? definition,
}) {
  if (hasUnsupportedLoadMetadata(definition: definition, load: existing)) {
    return false;
  }
  return typed || existing?.basis != null;
}

/// Build original input from the visible field. Unknown future metadata is
/// returned unchanged. Historic rows without a known basis stay metadata-free.
OriginalLoadInput? captureOriginalLoad({
  required ExerciseDefinitionSnapshot? definition,
  required OriginalLoadInput? existing,
  required bool typed,
  required double? value,
  required ExerciseLoadUnit unit,
  required ExerciseSetSide side,
}) {
  if (!capturesOriginalLoad(
    typed: typed,
    existing: existing,
    definition: definition,
  )) {
    return existing;
  }
  final basis = existing != null ? existing.basis : definition?.loadBasis;
  if (basis == null) return existing;
  final repetition = existing != null
      ? existing.repetitionBasis
      : definition?.repetitionBasis;
  final sideValue = repetition == ExerciseRepetitionBasis.perSide
      ? side
      : existing?.side;
  final retained = existing?.retained ?? const <String, Object?>{};
  final storedUnit = basis == ExerciseLoadBasis.bodyweight ? null : unit;
  switch (basis) {
    case ExerciseLoadBasis.bodyweight:
      return OriginalLoadInput(
        basis: basis,
        repetitionBasis: repetition,
        side: sideValue,
        retained: retained,
      );
    case ExerciseLoadBasis.assistance:
      return OriginalLoadInput(
        value: value,
        unit: storedUnit,
        basis: basis,
        repetitionBasis: repetition,
        side: sideValue,
        retained: retained,
      );
    case ExerciseLoadBasis.perDevice:
      return OriginalLoadInput(
        value: value,
        unit: storedUnit,
        basis: basis,
        deviceCount: actualDeviceCount(
          basis: basis,
          definitionCount: definition?.deviceCount,
          existingCount: existing?.deviceCount,
          existingSide: existing?.side,
          side: sideValue ?? ExerciseSetSide.both,
        ),
        repetitionBasis: repetition,
        side: sideValue,
        retained: retained,
      );
    case ExerciseLoadBasis.total:
    case ExerciseLoadBasis.addedLoad:
      return OriginalLoadInput(
        value: value,
        unit: storedUnit,
        basis: basis,
        repetitionBasis: repetition,
        side: sideValue,
        retained: retained,
      );
  }
}

double? resolvedLoadKg(OriginalLoadInput? input, double? historicKg) {
  if (input == null || input.basis == null) return historicKg;
  return resolveStoredLoadKg(input: input);
}

bool originalLoadsComparable({
  required OriginalLoadInput? previous,
  required OriginalLoadInput? current,
  ExerciseDefinitionSnapshot? definition,
}) {
  if (hasUnsupportedLoadMetadata(definition: definition, load: current) ||
      hasUnsupportedLoadMetadata(load: previous)) {
    return false;
  }
  final currentBasis = exerciseLoadBasis(definition: definition, load: current);
  final previousLoad = previous;
  if (previousLoad == null) return currentBasis == null;
  final previousBasis = previousLoad.basis;
  if (currentBasis == null || previousBasis == null) {
    return currentBasis == null && previousBasis == null;
  }
  if (previousBasis != currentBasis) return false;
  final currentRepetitions = exerciseRepetitionBasis(
    definition: definition,
    load: current,
  );
  if (previousLoad.repetitionBasis != currentRepetitions) return false;
  if (currentRepetitions == ExerciseRepetitionBasis.perSide &&
      previousLoad.side != current?.side) {
    return false;
  }
  if (currentBasis == ExerciseLoadBasis.perDevice &&
      previousLoad.deviceCount != current?.deviceCount) {
    return false;
  }
  return true;
}

String? displayOriginalLoad({
  OriginalLoadInput? load,
  double? historicKg,
  required bool typed,
}) {
  if (load != null && load.basis == null) return null;
  if (capturesOriginalLoad(typed: typed, existing: load)) {
    return formatOriginalLoadValue(load?.value);
  }
  return null;
}

double convertLoadValue(
  double value,
  ExerciseLoadUnit from,
  ExerciseLoadUnit to,
) {
  if (from == to) return value;
  return from == ExerciseLoadUnit.kg
      ? value / kKilogramsPerPound
      : value * kKilogramsPerPound;
}

Future<T?> showExerciseInputChoice<T>({
  required BuildContext context,
  required String title,
  required List<(T, String)> choices,
  required T selected,
}) => showOpenBandSettingsChoiceSheet<T>(
  context: context,
  title: title,
  choices: choices,
  selected: selected,
  barrierColor: const Color(0x52000000),
);
