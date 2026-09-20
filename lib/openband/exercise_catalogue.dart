import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Typed exercise registry: 18 shipped presets plus stored `exercise_def` rows.
///
/// Muscle shares on presets exist only so the legacy [ExerciseDef] adapter can
/// keep drawing the same map. They are never written into `muscles_json`.
/// `loadIncrement` is a plate step, never evidence of time vs repetitions.

const kExerciseRegistryVersion = 1;

enum ExerciseCaptureMode { repetitions, time }

enum ExerciseEquipmentCategory {
  barbell,
  dumbbell,
  cable,
  bodyweight,
  machine,
}

enum ExerciseDefinitionSource { preset, stored }

/// Equipment-filter key for rows with no known category (Ohne Zuordnung).
const kExerciseEquipmentUnknown = 'unknown';

@immutable
class ExerciseCatalogueEntry {
  ExerciseCatalogueEntry({
    required this.id,
    required this.label,
    List<String> aliases = const [],
    this.mode,
    List<String> primaryMuscles = const [],
    List<String> secondaryMuscles = const [],
    this.equipment,
    required this.source,
    this.version,
    this.loadIncrement,
    Map<String, Object?> retained = const {},
  }) : aliases = _freezeStrings(aliases),
       primaryMuscles = _freezeStrings(primaryMuscles),
       secondaryMuscles = _freezeStrings(secondaryMuscles),
       retained = _freezeMap(retained);

  final String id;
  final String label;
  final List<String> aliases;
  final ExerciseCaptureMode? mode;
  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;
  final ExerciseEquipmentCategory? equipment;
  final ExerciseDefinitionSource source;
  final int? version;
  final double? loadIncrement;
  final Map<String, Object?> retained;

  bool get selectable => mode != null;

  ExerciseDefinitionSnapshot snapshot() => ExerciseDefinitionSnapshot(
    id: id,
    label: label,
    version: version,
    source: source,
    mode: mode,
    primaryMuscles: primaryMuscles,
    secondaryMuscles: secondaryMuscles,
    equipment: equipment,
    retained: retained,
  );
}

@immutable
class ExerciseCatalogue {
  const ExerciseCatalogue({
    required this.entries,
    this.unreadableCount = 0,
  });

  final List<ExerciseCatalogueEntry> entries;
  final int unreadableCount;

  ExerciseCatalogueEntry? byId(String id) {
    for (final e in entries) {
      if (e.id == id) return e;
    }
    return null;
  }
}

@immutable
class ExerciseDefinitionSnapshot {
  ExerciseDefinitionSnapshot({
    required this.id,
    required this.label,
    required this.source,
    this.version,
    this.mode,
    List<String> primaryMuscles = const [],
    List<String> secondaryMuscles = const [],
    this.equipment,
    Map<String, Object?> retained = const {},
  }) : primaryMuscles = _freezeStrings(primaryMuscles),
       secondaryMuscles = _freezeStrings(secondaryMuscles),
       retained = _freezeMap(retained);

  final String id;
  final String label;
  final ExerciseDefinitionSource source;
  final int? version;
  final ExerciseCaptureMode? mode;
  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;
  final ExerciseEquipmentCategory? equipment;
  final Map<String, Object?> retained;

  factory ExerciseDefinitionSnapshot.fromJson(Map<String, dynamic> j) {
    final id = _requireExactId(j['id']);
    final label = _optionalString(j['label']);
    if (label == null) {
      throw const FormatException('Exercise definition snapshot is unreadable.');
    }
    final retained = Map<String, Object?>.from(_snapshotRetained(j));
    ExerciseEquipmentCategory? equipment;
    if (j.containsKey('equipment')) {
      final raw = j['equipment'];
      if (raw != null && raw is! String) {
        throw const FormatException(
          'Exercise definition snapshot is unreadable.',
        );
      }
      equipment = _parseEquipment(raw);
      if (equipment == null && raw is String && raw.isNotEmpty) {
        retained['equipment'] = raw;
      }
    }
    return ExerciseDefinitionSnapshot(
      id: id,
      label: label,
      source: _requireSource(j['source']),
      version: _optionalVersion(j['version']),
      mode: _parseMode(j['mode']),
      primaryMuscles: _stringList(j['primaryMuscles']),
      secondaryMuscles: _stringList(j['secondaryMuscles']),
      equipment: equipment,
      retained: retained,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'source': source.name,
    if (version != null) 'version': version,
    if (mode != null) 'mode': mode!.name,
    'primaryMuscles': primaryMuscles,
    'secondaryMuscles': secondaryMuscles,
    if (equipment != null) 'equipment': equipment!.name,
    if (retained.isNotEmpty) 'retained': retained,
  };
}

@immutable
class ExercisePreset {
  const ExercisePreset({
    required this.id,
    required this.labelDe,
    required this.labelEn,
    this.aliases = const [],
    required this.mode,
    required this.primaryMuscles,
    this.secondaryMuscles = const [],
    this.equipment,
    required this.loadIncrement,
    required this.legacyMuscleShares,
  });

  final String id;
  final String labelDe;
  final String labelEn;
  final List<String> aliases;
  final ExerciseCaptureMode mode;
  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;
  final ExerciseEquipmentCategory? equipment;
  final double loadIncrement;
  final Map<String, double> legacyMuscleShares;

  ExerciseCatalogueEntry get asEntry => ExerciseCatalogueEntry(
    id: id,
    label: labelDe,
    aliases: [labelEn, ...aliases],
    mode: mode,
    primaryMuscles: primaryMuscles,
    secondaryMuscles: secondaryMuscles,
    equipment: equipment,
    source: ExerciseDefinitionSource.preset,
    version: kExerciseRegistryVersion,
    loadIncrement: loadIncrement,
  );
}

const kExercisePresets = <ExercisePreset>[
  ExercisePreset(
    id: 'bench_press',
    labelDe: 'Bankdrücken',
    labelEn: 'Bench press',
    mode: ExerciseCaptureMode.repetitions,
    primaryMuscles: ['chest'],
    secondaryMuscles: ['triceps', 'shoulders'],
    equipment: ExerciseEquipmentCategory.barbell,
    loadIncrement: 2.5,
    legacyMuscleShares: {'chest': .6, 'triceps': .25, 'shoulders': .15},
  ),
  ExercisePreset(
    id: 'incline_db_press',
    labelDe: 'Schrägbankdrücken',
    labelEn: 'Incline DB press',
    aliases: ['Incline dumbbell press'],
    mode: ExerciseCaptureMode.repetitions,
    primaryMuscles: ['chest'],
    secondaryMuscles: ['shoulders', 'triceps'],
    equipment: ExerciseEquipmentCategory.dumbbell,
    loadIncrement: 2,
    legacyMuscleShares: {'chest': .5, 'shoulders': .3, 'triceps': .2},
  ),
  ExercisePreset(
    id: 'cable_fly',
    labelDe: 'Kabelzug-Flys',
    labelEn: 'Cable fly',
    mode: ExerciseCaptureMode.repetitions,
    primaryMuscles: ['chest'],
    secondaryMuscles: ['shoulders'],
    equipment: ExerciseEquipmentCategory.cable,
    loadIncrement: 2.5,
    legacyMuscleShares: {'chest': .8, 'shoulders': .2},
  ),
  ExercisePreset(
    id: 'overhead_press',
    labelDe: 'Schulterdrücken',
    labelEn: 'Overhead press',
    mode: ExerciseCaptureMode.repetitions,
    primaryMuscles: ['shoulders'],
    secondaryMuscles: ['triceps', 'core'],
    loadIncrement: 2.5,
    legacyMuscleShares: {'shoulders': .6, 'triceps': .3, 'core': .1},
  ),
  ExercisePreset(
    id: 'triceps_pushdown',
    labelDe: 'Trizepsdrücken',
    labelEn: 'Triceps pushdown',
    mode: ExerciseCaptureMode.repetitions,
    primaryMuscles: ['triceps'],
    equipment: ExerciseEquipmentCategory.cable,
    loadIncrement: 2.5,
    legacyMuscleShares: {'triceps': 1.0},
  ),
  ExercisePreset(
    id: 'overhead_extension',
    labelDe: 'Überkopf-Extension',
    labelEn: 'Overhead extension',
    mode: ExerciseCaptureMode.repetitions,
    primaryMuscles: ['triceps'],
    loadIncrement: 2.5,
    legacyMuscleShares: {'triceps': 1.0},
  ),
  ExercisePreset(
    id: 'barbell_row',
    labelDe: 'Langhantelrudern',
    labelEn: 'Barbell row',
    mode: ExerciseCaptureMode.repetitions,
    primaryMuscles: ['back'],
    secondaryMuscles: ['biceps', 'core'],
    equipment: ExerciseEquipmentCategory.barbell,
    loadIncrement: 2.5,
    legacyMuscleShares: {'back': .65, 'biceps': .25, 'core': .1},
  ),
  ExercisePreset(
    id: 'lat_pulldown',
    labelDe: 'Latzug',
    labelEn: 'Lat pulldown',
    mode: ExerciseCaptureMode.repetitions,
    primaryMuscles: ['back'],
    secondaryMuscles: ['biceps'],
    equipment: ExerciseEquipmentCategory.cable,
    loadIncrement: 2.5,
    legacyMuscleShares: {'back': .7, 'biceps': .3},
  ),
  ExercisePreset(
    id: 'pull_up',
    labelDe: 'Klimmzug',
    labelEn: 'Pull-up',
    aliases: ['Pull up'],
    mode: ExerciseCaptureMode.repetitions,
    primaryMuscles: ['back'],
    secondaryMuscles: ['biceps', 'core'],
    equipment: ExerciseEquipmentCategory.bodyweight,
    loadIncrement: 2.5,
    legacyMuscleShares: {'back': .65, 'biceps': .25, 'core': .1},
  ),
  ExercisePreset(
    id: 'barbell_curl',
    labelDe: 'Langhantelcurl',
    labelEn: 'Barbell curl',
    mode: ExerciseCaptureMode.repetitions,
    primaryMuscles: ['biceps'],
    equipment: ExerciseEquipmentCategory.barbell,
    loadIncrement: 2.5,
    legacyMuscleShares: {'biceps': 1.0},
  ),
  ExercisePreset(
    id: 'back_squat',
    labelDe: 'Kniebeuge',
    labelEn: 'Back squat',
    mode: ExerciseCaptureMode.repetitions,
    primaryMuscles: ['legs'],
    secondaryMuscles: ['glutes', 'core'],
    equipment: ExerciseEquipmentCategory.barbell,
    loadIncrement: 2.5,
    legacyMuscleShares: {'legs': .65, 'glutes': .25, 'core': .1},
  ),
  ExercisePreset(
    id: 'front_squat',
    labelDe: 'Frontkniebeuge',
    labelEn: 'Front squat',
    mode: ExerciseCaptureMode.repetitions,
    primaryMuscles: ['legs'],
    secondaryMuscles: ['glutes', 'core'],
    equipment: ExerciseEquipmentCategory.barbell,
    loadIncrement: 2.5,
    legacyMuscleShares: {'legs': .6, 'glutes': .2, 'core': .2},
  ),
  ExercisePreset(
    id: 'deadlift',
    labelDe: 'Kreuzheben',
    labelEn: 'Deadlift',
    mode: ExerciseCaptureMode.repetitions,
    primaryMuscles: ['back'],
    secondaryMuscles: ['legs', 'glutes', 'core'],
    equipment: ExerciseEquipmentCategory.barbell,
    loadIncrement: 2.5,
    legacyMuscleShares: {'back': .35, 'legs': .3, 'glutes': .3, 'core': .05},
  ),
  ExercisePreset(
    id: 'romanian_deadlift',
    labelDe: 'Rumänisches Kreuzheben',
    labelEn: 'Romanian deadlift',
    mode: ExerciseCaptureMode.repetitions,
    primaryMuscles: ['glutes'],
    secondaryMuscles: ['legs', 'back'],
    equipment: ExerciseEquipmentCategory.barbell,
    loadIncrement: 2.5,
    legacyMuscleShares: {'glutes': .45, 'legs': .35, 'back': .2},
  ),
  ExercisePreset(
    id: 'hip_thrust',
    labelDe: 'Hüftstoßen',
    labelEn: 'Hip thrust',
    mode: ExerciseCaptureMode.repetitions,
    primaryMuscles: ['glutes'],
    secondaryMuscles: ['legs'],
    loadIncrement: 2.5,
    legacyMuscleShares: {'glutes': .8, 'legs': .2},
  ),
  ExercisePreset(
    id: 'leg_press',
    labelDe: 'Beinpresse',
    labelEn: 'Leg press',
    mode: ExerciseCaptureMode.repetitions,
    primaryMuscles: ['legs'],
    secondaryMuscles: ['glutes'],
    equipment: ExerciseEquipmentCategory.machine,
    loadIncrement: 2.5,
    legacyMuscleShares: {'legs': .75, 'glutes': .25},
  ),
  ExercisePreset(
    id: 'plank',
    labelDe: 'Unterarmstütz',
    labelEn: 'Plank',
    aliases: ['Planke'],
    mode: ExerciseCaptureMode.time,
    primaryMuscles: ['core'],
    equipment: ExerciseEquipmentCategory.bodyweight,
    loadIncrement: 0,
    legacyMuscleShares: {'core': 1.0},
  ),
  ExercisePreset(
    id: 'hanging_leg_raise',
    labelDe: 'Hängendes Beinheben',
    labelEn: 'Hanging leg raise',
    mode: ExerciseCaptureMode.repetitions,
    primaryMuscles: ['core'],
    equipment: ExerciseEquipmentCategory.bodyweight,
    loadIncrement: 0,
    legacyMuscleShares: {'core': 1.0},
  ),
];

final Map<String, ExercisePreset> _presetsById = {
  for (final e in kExercisePresets) e.id: e,
};

ExercisePreset? exercisePresetById(String id) => _presetsById[id];

ExerciseCatalogue assembleExerciseCatalogue(
  Iterable<Map<String, Object?>> rows,
) {
  final byId = <String, ExerciseCatalogueEntry>{
    for (final e in kExercisePresets) e.id: e.asEntry,
  };
  final extra = <ExerciseCatalogueEntry>[];
  var unreadable = 0;
  for (final row in rows) {
    try {
      final parsed = parseStoredExerciseDef(row);
      if (byId.containsKey(parsed.id)) {
        byId[parsed.id] = parsed;
      } else {
        extra.add(parsed);
      }
    } on FormatException {
      unreadable++;
      final key = row['key'];
      if (key is String && key.isNotEmpty) byId.remove(key);
    } on TypeError {
      unreadable++;
      final key = row['key'];
      if (key is String && key.isNotEmpty) byId.remove(key);
    }
  }
  return ExerciseCatalogue(
    entries: [...byId.values, ...extra],
    unreadableCount: unreadable,
  );
}

ExerciseCatalogueEntry parseStoredExerciseDef(Map<String, Object?> row) {
  final id = _requireExactId(row['key']);
  final columnLabel = _optionalString(row['label']);
  final columnEquipment = _optionalString(row['equipment']) ?? '';
  final definition = _decodeDefinitionJson(row['definition_json']);

  var jsonHasEquipment = false;
  Object? jsonEquipmentRaw;
  if (definition != null && definition.containsKey('equipment')) {
    jsonHasEquipment = true;
    jsonEquipmentRaw = definition['equipment'];
  }
  if (jsonHasEquipment && jsonEquipmentRaw != null && jsonEquipmentRaw is! String) {
    throw const FormatException('Exercise definition is unreadable.');
  }
  final jsonEquipment =
      jsonHasEquipment ? _parseEquipment(jsonEquipmentRaw) : null;
  final columnCategory = _parseEquipment(columnEquipment);

  final retained = <String, Object?>{
    if (row['muscles_json'] != null) 'muscles_json': row['muscles_json'],
    if (row['unilateral'] != null) 'unilateral': row['unilateral'],
    if (row['custom'] != null) 'custom': row['custom'],
    if (row['created_at'] != null) 'created_at': row['created_at'],
    if (definition != null) ..._retainedFrom(definition, _definitionKnownKeys),
  };
  if (jsonHasEquipment) {
    if (jsonEquipment == null &&
        jsonEquipmentRaw is String &&
        jsonEquipmentRaw.isNotEmpty) {
      retained['equipment'] = jsonEquipmentRaw;
    }
  } else if (columnEquipment.isNotEmpty) {
    retained['equipment'] = columnEquipment;
  }
  if (row['source'] != null) retained['source'] = row['source'];
  final definitionSource = definition?['source'];
  if (definitionSource != null && definitionSource != retained['source']) {
    if (retained.containsKey('source')) {
      retained['definition_source'] = definitionSource;
    } else {
      retained['source'] = definitionSource;
    }
  }

  final labelDe = _optionalString(definition?['labelDe']);
  final jsonLabel = _optionalString(definition?['label']);
  final label = labelDe ?? jsonLabel ?? columnLabel;
  if (label == null || label.isEmpty) {
    throw const FormatException('Exercise definition is unreadable.');
  }
  final labelEn = _optionalString(definition?['labelEn']);

  return ExerciseCatalogueEntry(
    id: id,
    label: label,
    aliases: [
      ..._stringList(definition?['aliases']),
      ?labelEn,
    ],
    mode: definition == null ? null : _parseMode(definition['mode']),
    primaryMuscles: _stringList(definition?['primaryMuscles']),
    secondaryMuscles: _stringList(definition?['secondaryMuscles']),
    equipment: jsonHasEquipment ? jsonEquipment : columnCategory,
    source: ExerciseDefinitionSource.stored,
    version:
        _optionalVersion(row['version']) ??
        _optionalVersion(definition?['version']),
    loadIncrement: _optionalLoadIncrement(definition?['loadIncrement']),
    retained: retained,
  );
}

List<ExerciseCatalogueEntry> filterExerciseCatalogue(
  Iterable<ExerciseCatalogueEntry> entries, {
  String query = '',
  Set<String> muscles = const {},
  Set<String> equipment = const {},
}) {
  final q = _fold(query.trim());
  return [
    for (final e in entries)
      if (_matchesQuery(e, q) &&
          _matchesMuscles(e, muscles) &&
          _matchesEquipment(e, equipment))
        e,
  ];
}

const _definitionKnownKeys = {
  'id',
  'label',
  'labelDe',
  'labelEn',
  'aliases',
  'mode',
  'primaryMuscles',
  'secondaryMuscles',
  'equipment',
  'source',
  'version',
  'loadIncrement',
};

const _snapshotKnownKeys = {
  'id',
  'label',
  'source',
  'version',
  'mode',
  'primaryMuscles',
  'secondaryMuscles',
  'equipment',
  'retained',
};

bool _matchesQuery(ExerciseCatalogueEntry e, String q) {
  if (q.isEmpty) return true;
  if (_fold(e.id).contains(q) || _fold(e.label).contains(q)) return true;
  for (final alias in e.aliases) {
    if (_fold(alias).contains(q)) return true;
  }
  return false;
}

bool _matchesMuscles(ExerciseCatalogueEntry e, Set<String> muscles) {
  if (muscles.isEmpty) return true;
  for (final m in muscles) {
    if (e.primaryMuscles.contains(m) || e.secondaryMuscles.contains(m)) {
      return true;
    }
  }
  return false;
}

bool _matchesEquipment(ExerciseCatalogueEntry e, Set<String> equipment) {
  if (equipment.isEmpty) return true;
  final name = e.equipment?.name ?? kExerciseEquipmentUnknown;
  return equipment.contains(name);
}

String _fold(String s) => s.toLowerCase().replaceAll('ä', 'a').replaceAll(
  'ö',
  'o',
).replaceAll('ü', 'u').replaceAll('ß', 'ss');

ExerciseCaptureMode? _parseMode(Object? raw) {
  if (raw == null) return null;
  if (raw is! String) {
    throw const FormatException('Exercise definition mode is unreadable.');
  }
  return switch (raw) {
    'repetitions' => ExerciseCaptureMode.repetitions,
    'time' => ExerciseCaptureMode.time,
    _ => throw const FormatException('Exercise definition mode is unreadable.'),
  };
}

ExerciseEquipmentCategory? _parseEquipment(Object? raw) {
  if (raw == null) return null;
  if (raw is! String || raw.isEmpty) return null;
  return switch (raw) {
    'barbell' => ExerciseEquipmentCategory.barbell,
    'dumbbell' => ExerciseEquipmentCategory.dumbbell,
    'cable' => ExerciseEquipmentCategory.cable,
    'bodyweight' => ExerciseEquipmentCategory.bodyweight,
    'machine' => ExerciseEquipmentCategory.machine,
    _ => null,
  };
}

ExerciseDefinitionSource _requireSource(Object? raw) {
  if (raw == 'preset') return ExerciseDefinitionSource.preset;
  if (raw == 'stored') return ExerciseDefinitionSource.stored;
  throw const FormatException('Exercise definition snapshot is unreadable.');
}

List<String> _stringList(Object? raw) {
  if (raw == null) return const [];
  if (raw is! List) {
    throw const FormatException('Exercise definition is unreadable.');
  }
  final out = <String>[];
  for (final v in raw) {
    if (v is! String || v.isEmpty) {
      throw const FormatException('Exercise definition is unreadable.');
    }
    out.add(v);
  }
  return out;
}

Map<String, Object?> _retainedFrom(
  Map<String, dynamic> raw,
  Set<String> known,
) {
  final out = <String, Object?>{};
  raw.forEach((key, value) {
    if (!known.contains(key)) out[key] = value;
  });
  return out;
}

Map<String, Object?> _snapshotRetained(Map<String, dynamic> j) {
  final out = <String, Object?>{};
  if (j.containsKey('retained')) {
    final nested = j['retained'];
    if (nested is! Map) {
      throw const FormatException('Exercise definition snapshot is unreadable.');
    }
    nested.forEach((key, value) {
      if (key is! String) {
        throw const FormatException(
          'Exercise definition snapshot is unreadable.',
        );
      }
      out[key] = value;
    });
  }
  j.forEach((key, value) {
    if (!_snapshotKnownKeys.contains(key)) out[key] = value;
  });
  return out;
}

Map<String, dynamic>? _decodeDefinitionJson(Object? raw) {
  if (raw == null) return null;
  if (raw is! String) {
    throw const FormatException('Exercise definition is unreadable.');
  }
  if (raw.isEmpty) return null;
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw const FormatException('Exercise definition is unreadable.');
  }
  return Map<String, dynamic>.from(decoded);
}

String _requireExactId(Object? raw) {
  if (raw is! String || raw.isEmpty) {
    throw const FormatException('Exercise definition is unreadable.');
  }
  return raw;
}

String? _optionalString(Object? raw) {
  if (raw == null) return null;
  if (raw is! String) {
    throw const FormatException('Exercise definition is unreadable.');
  }
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _optionalVersion(Object? raw) {
  if (raw == null) return null;
  if (raw is! num || !raw.isFinite || raw != raw.truncateToDouble() || raw < 0) {
    throw const FormatException('Exercise definition is unreadable.');
  }
  return raw.toInt();
}

double? _optionalLoadIncrement(Object? raw) {
  if (raw == null) return null;
  if (raw is! num || !raw.isFinite || raw < 0) {
    throw const FormatException('Exercise definition is unreadable.');
  }
  return raw.toDouble();
}

List<String> _freezeStrings(Iterable<String> raw) =>
    List.unmodifiable(List<String>.from(raw));

Map<String, Object?> _freezeMap(Map<String, Object?> raw) =>
    Map<String, Object?>.unmodifiable({
      for (final e in raw.entries) e.key: _freezeJson(e.value),
    });

Object? _freezeJson(Object? value) {
  if (value is Map) {
    return Map<String, Object?>.unmodifiable({
      for (final e in value.entries)
        if (e.key is String) e.key as String: _freezeJson(e.value),
    });
  }
  if (value is List) {
    return List<Object?>.unmodifiable([
      for (final item in value) _freezeJson(item),
    ]);
  }
  return value;
}
