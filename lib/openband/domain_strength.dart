part of 'domain.dart';

enum PlannedSetMode { repetitions, time }

class PlannedSet {
  final String id;
  final String type;
  final int? reps, seconds, restSec;
  final double? loadKg;
  final PlannedSetMode? mode;
  final OriginalLoadInput? load;
  const PlannedSet({
    required this.id,
    this.type = 'work',
    this.reps,
    this.seconds,
    this.restSec,
    this.loadKg,
    this.mode,
    this.load,
  });

  /// Explicit mode wins. Legacy JSON without [mode] is timed only when
  /// [seconds] is actually present; otherwise prior reps behavior stands.
  PlannedSetMode? get effectiveMode {
    if (mode != null) return mode;
    if (seconds != null) return PlannedSetMode.time;
    return null;
  }

  bool get isTimed => effectiveMode == PlannedSetMode.time;

  factory PlannedSet.fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String? ?? '';
    if (id.isEmpty) {
      throw const FormatException('Planned set is missing a stable id.');
    }
    final reps = (j['reps'] as num?)?.toInt();
    final seconds = (j['seconds'] as num?)?.toInt();
    final mode = _parsePlannedSetMode(j['mode']);
    // Historical JSON without mode keeps both values. Reinterpreting
    // reps+seconds as one mode would invent a typed choice the row never had.
    if (mode != null) {
      if (reps != null && seconds != null) {
        throw const FormatException('Planned set has contradictory reps+time.');
      }
      if (mode == PlannedSetMode.repetitions && seconds != null) {
        throw const FormatException('Planned set has contradictory reps+time.');
      }
      if (mode == PlannedSetMode.time && reps != null) {
        throw const FormatException('Planned set has contradictory reps+time.');
      }
    }
    final load = _parseOriginalLoad(j['load']);
    final statedKg = _optionalFiniteLoad(j['loadKg']);
    final loadKg = load == null
        ? statedKg
        : load.basis == null
        ? statedKg
        : resolveStoredLoadKg(input: load, loadKg: statedKg);
    return PlannedSet(
      id: id,
      type: j['type'] as String? ?? 'work',
      reps: reps,
      seconds: seconds,
      restSec: (j['restSec'] as num?)?.toInt(),
      loadKg: loadKg,
      mode: mode,
      load: load,
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'reps': reps,
    'seconds': seconds,
    'restSec': restSec,
    'loadKg': loadKg,
    if (mode != null) 'mode': mode!.name,
    if (load != null) 'load': load!.toJson(),
  };
}

OriginalLoadInput? _parseOriginalLoad(Object? raw) {
  if (raw == null) return null;
  if (raw is! Map) {
    throw const FormatException('Original load is unreadable.');
  }
  return OriginalLoadInput.fromJson(Map<String, dynamic>.from(raw));
}

double? _optionalFiniteLoad(Object? raw) {
  if (raw == null) return null;
  if (raw is! num || !raw.isFinite) {
    throw const FormatException('Planned set load is unreadable.');
  }
  return raw.toDouble();
}

PlannedSetMode? _parsePlannedSetMode(Object? raw) {
  if (raw == null) return null;
  if (raw is! String) {
    throw const FormatException('Planned set mode is unreadable.');
  }
  return switch (raw) {
    'repetitions' => PlannedSetMode.repetitions,
    'time' => PlannedSetMode.time,
    _ => throw const FormatException('Planned set mode is unreadable.'),
  };
}

class PlannedExercise {
  final String id, exerciseKey, name;
  final List<PlannedSet> sets;
  final String note;
  final ExerciseDefinitionSnapshot? definition;
  const PlannedExercise({
    required this.id,
    required this.exerciseKey,
    required this.name,
    required this.sets,
    this.note = '',
    this.definition,
  });
  factory PlannedExercise.fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String? ?? '';
    final exerciseKey = j['exerciseKey'] as String? ?? '';
    final name = j['name'] as String? ?? '';
    if (id.isEmpty || exerciseKey.isEmpty || name.isEmpty) {
      throw const FormatException('Planned exercise is missing identity.');
    }
    final rawSets = j['sets'];
    if (rawSets is! List || rawSets.isEmpty) {
      throw const FormatException('Planned exercise has no sets.');
    }
    final rawDefinition = j['definition'];
    ExerciseDefinitionSnapshot? definition;
    if (rawDefinition != null) {
      if (rawDefinition is! Map) {
        throw const FormatException('Exercise definition snapshot is unreadable.');
      }
      definition = ExerciseDefinitionSnapshot.fromJson(
        Map<String, dynamic>.from(rawDefinition),
      );
      if (definition.id != exerciseKey) {
        throw const FormatException(
          'Exercise definition snapshot is unreadable.',
        );
      }
    }
    return PlannedExercise(
      id: id,
      exerciseKey: exerciseKey,
      name: name,
      sets: [
        for (final s in rawSets) PlannedSet.fromJson(s as Map<String, dynamic>),
      ],
      note: j['note'] as String? ?? '',
      definition: definition,
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'exerciseKey': exerciseKey,
    'name': name,
    'sets': [for (final s in sets) s.toJson()],
    'note': note,
    if (definition != null) 'definition': definition!.toJson(),
  };
}

/// A plan. Confirming a set records a strength_set row. Editing the template
/// never changes a recorded session (B23).
class WorkoutTemplate {
  final String id, name;
  final int version;
  final List<PlannedExercise> exercises;
  final DateTime updatedAt;
  const WorkoutTemplate({
    required this.id,
    required this.name,
    required this.version,
    required this.exercises,
    required this.updatedAt,
  });
  int get workSets => exercises.fold(
    0,
    (n, e) => n + e.sets.where((s) => s.type == 'work').length,
  );

  factory WorkoutTemplate.fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String? ?? '';
    final name = j['name'] as String? ?? '';
    final version = (j['version'] as num?)?.toInt();
    final updatedAtMs = (j['updatedAtMs'] as num?)?.toInt();
    final rawExercises = j['exercises'];
    if (id.isEmpty ||
        name.isEmpty ||
        version == null ||
        updatedAtMs == null ||
        rawExercises is! List ||
        rawExercises.isEmpty) {
      throw const FormatException('Strength plan snapshot is unreadable.');
    }
    final exercises = [
      for (final e in rawExercises)
        PlannedExercise.fromJson(e as Map<String, dynamic>),
    ];
    final ids = <String>{};
    for (final e in exercises) {
      if (!ids.add(e.id)) {
        throw const FormatException('Strength plan has duplicate exercise ids.');
      }
      for (final s in e.sets) {
        if (!ids.add(s.id)) {
          throw const FormatException('Strength plan has duplicate set ids.');
        }
      }
    }
    return WorkoutTemplate(
      id: id,
      name: name,
      version: version,
      exercises: exercises,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'version': version,
    'exercises': [for (final e in exercises) e.toJson()],
    'updatedAtMs': updatedAt.millisecondsSinceEpoch,
  };
}

/// Current plan + added sets as 1-based indexes within each exercise block.
typedef StrengthPlanSlot = ({
  String plannedSetId,
  String exerciseKey,
  String exerciseId,
  int setIndex,
  bool timed,
});

List<StrengthPlanSlot> strengthPlanSlots(
  WorkoutTemplate plan,
  List<PlannedExercise> added,
) {
  final counts = <String, int>{};
  final out = <StrengthPlanSlot>[];
  void walk(List<PlannedExercise> exercises) {
    for (final e in exercises) {
      var n = counts[e.id] ?? 0;
      for (final s in e.sets) {
        n++;
        out.add((
          plannedSetId: s.id,
          exerciseKey: e.exerciseKey,
          exerciseId: e.id,
          setIndex: n,
          timed: s.isTimed,
        ));
      }
      counts[e.id] = n;
    }
  }

  walk(plan.exercises);
  walk(added);
  return out;
}

String? _strengthExerciseId(String? id) =>
    (id == null || id.isEmpty) ? null : id;

bool _onePriorStrengthBlock(List<RecordedSet> priors) {
  final ids = <String>{};
  final anonIndex = <int>{};
  var anonymous = 0;
  for (final s in priors) {
    final id = _strengthExerciseId(s.exerciseId);
    if (id == null) {
      anonymous++;
      if (!anonIndex.add(s.setIndex)) return false;
    } else {
      ids.add(id);
    }
  }
  if (ids.length > 1) return false;
  if (ids.length == 1) return anonymous == 0;
  return anonymous > 0;
}

/// Prefer [RecordedSet.exerciseId] + index inside the latest prior session.
/// Copied/new plan ids fall back to [exerciseKey] + index only when that key
/// has one current block and one prior block. Duplicate legacy rows omit.
Map<String, RecordedSet> previousStrengthSetsFromLatest({
  required List<StrengthPlanSlot> slots,
  required Map<String, List<RecordedSet>> latestByExercise,
}) {
  final currentIds = <String, Set<String>>{};
  for (final slot in slots) {
    (currentIds[slot.exerciseKey] ??= {}).add(slot.exerciseId);
  }
  final out = <String, RecordedSet>{};
  for (final slot in slots) {
    final priors = latestByExercise[slot.exerciseKey] ?? const <RecordedSet>[];
    RecordedSet? picked;
    final slotId = _strengthExerciseId(slot.exerciseId);
    if (slotId != null) {
      final matches = [
        for (final s in priors)
          if (_strengthExerciseId(s.exerciseId) == slotId &&
              s.setIndex == slot.setIndex)
            s,
      ];
      if (matches.length == 1) picked = matches.single;
    }
    if (picked == null &&
        (currentIds[slot.exerciseKey]?.length ?? 0) == 1 &&
        _onePriorStrengthBlock(priors)) {
      final matches = [
        for (final s in priors)
          if (s.setIndex == slot.setIndex) s,
      ];
      if (matches.length == 1) picked = matches.single;
    }
    if (picked == null) continue;
    final compatible = slot.timed ? picked.seconds != null : picked.reps != null;
    if (!compatible) continue;
    out[slot.plannedSetId] = picked;
  }
  return out;
}

/// Another workout is already live. Start is refused; read the active
/// strength state instead of opening a second session.
class WorkoutBusy implements Exception {
  const WorkoutBusy();
  @override
  String toString() => 'Eine Einheit läuft bereits.';
}

/// Durable Alpin strength runtime: none, a readable live plan, or a live
/// row whose snapshot cannot be shown without fabricating a plan.
sealed class ActiveStrengthRuntime {
  const ActiveStrengthRuntime();
}

final class NoActiveStrength extends ActiveStrengthRuntime {
  const NoActiveStrength();
}

final class CorruptActiveStrength extends ActiveStrengthRuntime {
  final String sessionId;
  const CorruptActiveStrength(this.sessionId);
}

/// Live `weight_training` without an Alpin snapshot. Resume through the
/// existing live engine; do not invent a plan or start another session.
final class LegacyActiveStrength extends ActiveStrengthRuntime {
  final String sessionId;
  const LegacyActiveStrength(this.sessionId);
}

final class ActiveStrengthSession extends ActiveStrengthRuntime {
  final String sessionId;
  final WorkoutTemplate plan;
  final List<RecordedSet> recorded;
  final Set<String> skippedPlannedSetIds;
  final List<PlannedExercise> added;
  final DateTime startedAt;
  final DateTime? restEndsAt;
  const ActiveStrengthSession({
    required this.sessionId,
    required this.plan,
    required this.recorded,
    required this.skippedPlannedSetIds,
    required this.added,
    required this.startedAt,
    this.restEndsAt,
  });

  /// Stored rest end. Null after an explicit skip. Never derived from now.
  DateTime? restUntil() => restEndsAt;
}
