import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Exact kilogram-per-pound factor. Strength load conversion lives here, not
/// in body-mass unit settings.
const kKilogramsPerPound = 0.45359237;

enum ExerciseLoadBasis { total, perDevice, bodyweight, addedLoad, assistance }

enum ExerciseLoadUnit { kg, lb }

enum ExerciseRepetitionBasis { total, perSide }

enum ExerciseSetSide { both, left, right }

/// Original typed load capture. [loadKg] on the set stays the normalized
/// external total; this is the input that produced it.
@immutable
class OriginalLoadInput {
  OriginalLoadInput({
    this.value,
    this.unit,
    this.basis,
    this.deviceCount,
    this.repetitionBasis,
    this.side,
    Map<String, Object?> retained = const {},
  }) : retained = _freezeMap(retained);

  final double? value;
  final ExerciseLoadUnit? unit;
  final ExerciseLoadBasis? basis;
  final int? deviceCount;
  final ExerciseRepetitionBasis? repetitionBasis;
  final ExerciseSetSide? side;
  final Map<String, Object?> retained;

  factory OriginalLoadInput.fromJson(Map<String, dynamic> j) {
    final retained = Map<String, Object?>.from(_loadRetained(j));
    final unit = _parseUnit(j['unit'], retained);
    final basis = _parseBasis(j['basis'], retained);
    final repetitionBasis = _parseRepetitionBasis(j['repetitionBasis'], retained);
    final side = _parseSide(j['side'], retained);
    return OriginalLoadInput(
      value: _optionalFinite(j['value'], 'Original load value is unreadable.'),
      unit: unit,
      basis: basis,
      deviceCount: _optionalPositiveInt(
        j['deviceCount'],
        'Original load device count is unreadable.',
      ),
      repetitionBasis: repetitionBasis,
      side: side,
      retained: retained,
    );
  }

  Map<String, dynamic> toJson() => {
    'value': value,
    if (unit != null) 'unit': unit!.name,
    if (basis != null) 'basis': basis!.name,
    if (deviceCount != null) 'deviceCount': deviceCount,
    if (repetitionBasis != null) 'repetitionBasis': repetitionBasis!.name,
    if (side != null) 'side': side!.name,
    if (retained.isNotEmpty) 'retained': retained,
  };

  String encode() => jsonEncode(toJson());

  static OriginalLoadInput decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Original load is unreadable.');
    }
    return OriginalLoadInput.fromJson(Map<String, dynamic>.from(decoded));
  }
}

double kilogramsFromLoadUnit(double value, ExerciseLoadUnit unit) {
  _requireFinite(value, 'value');
  return switch (unit) {
    ExerciseLoadUnit.kg => value,
    ExerciseLoadUnit.lb => value * kKilogramsPerPound,
  };
}

/// Normalized external total in kilograms, or null when external load is
/// unknown (bodyweight, assistance, or an absent value).
///
/// One implementation: per-device multiplies input kilograms by the actual
/// device count. Repetition basis and side never multiply this total.
double? normalizeExerciseLoad(OriginalLoadInput input) {
  _validateOriginalLoad(input, requireKnownBasis: false);
  final basis = input.basis;
  if (basis == null) {
    throw const FormatException('Original load basis is unknown.');
  }
  switch (basis) {
    case ExerciseLoadBasis.bodyweight:
    case ExerciseLoadBasis.assistance:
      return null;
    case ExerciseLoadBasis.total:
    case ExerciseLoadBasis.addedLoad:
      return _requireNormalizedFinite(_inputKilograms(input));
    case ExerciseLoadBasis.perDevice:
      final kg = _inputKilograms(input);
      if (kg == null) return null;
      final count = input.deviceCount;
      if (count == null) {
        throw const FormatException('Original load device count is required.');
      }
      return _requireNormalizedFinite(kg * count);
  }
}

/// Persist boundary: metadata wins for a new total; a stated [loadKg] must
/// match. Absent metadata keeps the historic total unchanged.
double? resolveStoredLoadKg({
  OriginalLoadInput? input,
  double? loadKg,
}) {
  if (loadKg != null) _requireFinite(loadKg, 'loadKg');
  if (input == null) return loadKg;
  _validateOriginalLoad(input, requireKnownBasis: true);
  final normalized = normalizeExerciseLoad(input);
  if (loadKg != null && normalized != loadKg) {
    throw const FormatException('Recorded load contradicts original input.');
  }
  return normalized;
}

/// Decode optional stored `load_json`. Absent JSON keeps the historic total.
/// Unknown future basis also keeps the historic total instead of inventing one.
double? resolveLoadKgFromStoredJson({
  Object? loadJson,
  double? loadKg,
}) {
  if (loadJson == null) return loadKg;
  if (loadJson is! String || loadJson.isEmpty) {
    throw const FormatException('Original load is unreadable.');
  }
  final input = OriginalLoadInput.decode(loadJson);
  if (input.basis == null) {
    if (loadKg != null) _requireFinite(loadKg, 'loadKg');
    return loadKg;
  }
  return resolveStoredLoadKg(input: input, loadKg: loadKg);
}

void requireOriginalLoad(OriginalLoadInput input) =>
    _validateOriginalLoad(input, requireKnownBasis: true);

void _validateOriginalLoad(
  OriginalLoadInput input, {
  required bool requireKnownBasis,
}) {
  if (input.value != null) _requireFinite(input.value!, 'value');
  if (input.value != null && input.value! < 0) {
    throw ArgumentError.value(input.value, 'value');
  }
  if (input.deviceCount != null && input.deviceCount! < 1) {
    throw ArgumentError.value(input.deviceCount, 'deviceCount');
  }
  final basis = input.basis;
  if (basis == null) {
    if (requireKnownBasis) {
      throw const FormatException('Original load basis is unknown.');
    }
    return;
  }
  switch (basis) {
    case ExerciseLoadBasis.bodyweight:
      if (input.value != null || input.unit != null || input.deviceCount != null) {
        throw const FormatException('Bodyweight has no external load input.');
      }
    case ExerciseLoadBasis.assistance:
      if (input.deviceCount != null) {
        throw const FormatException('Assistance has no device count.');
      }
      if (input.value == null) {
        return;
      }
      if (input.value! <= 0) {
        throw const FormatException('Assistance needs a positive original load.');
      }
      if (input.unit == null) {
        throw const FormatException('Original load unit is unreadable.');
      }
    case ExerciseLoadBasis.perDevice:
      if (input.deviceCount == null) {
        throw const FormatException('Original load device count is required.');
      }
      if (input.value != null && input.unit == null) {
        throw const FormatException('Original load unit is unreadable.');
      }
    case ExerciseLoadBasis.total:
    case ExerciseLoadBasis.addedLoad:
      if (input.deviceCount != null) {
        throw const FormatException('Device count does not apply to this load basis.');
      }
      if (input.value != null && input.unit == null) {
        throw const FormatException('Original load unit is unreadable.');
      }
  }
}

double? _inputKilograms(OriginalLoadInput input) {
  final value = input.value;
  if (value == null) return null;
  final unit = input.unit;
  if (unit == null) {
    throw const FormatException('Original load unit is unreadable.');
  }
  return kilogramsFromLoadUnit(value, unit);
}

void _requireFinite(double value, String name) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, name);
  }
}

double? _requireNormalizedFinite(double? value) {
  if (value != null && !value.isFinite) {
    throw ArgumentError.value(value, 'loadKg');
  }
  return value;
}

const _loadKnownKeys = {
  'value',
  'unit',
  'basis',
  'deviceCount',
  'repetitionBasis',
  'side',
  'retained',
};

Map<String, Object?> _loadRetained(Map<String, dynamic> j) {
  final out = <String, Object?>{};
  if (j.containsKey('retained')) {
    final nested = j['retained'];
    if (nested is! Map) {
      throw const FormatException('Original load is unreadable.');
    }
    nested.forEach((key, value) {
      if (key is! String) {
        throw const FormatException('Original load is unreadable.');
      }
      out[key] = value;
    });
  }
  j.forEach((key, value) {
    if (!_loadKnownKeys.contains(key)) out[key] = value;
  });
  return out;
}

ExerciseLoadUnit? _parseUnit(Object? raw, Map<String, Object?> retained) {
  if (raw == null) return null;
  if (raw is! String) {
    throw const FormatException('Original load unit is unreadable.');
  }
  return switch (raw) {
    'kg' => ExerciseLoadUnit.kg,
    'lb' => ExerciseLoadUnit.lb,
    _ => _retainUnknown(retained, 'unit', raw),
  };
}

ExerciseLoadBasis? _parseBasis(Object? raw, Map<String, Object?> retained) {
  if (raw == null) return null;
  if (raw is! String) {
    throw const FormatException('Original load basis is unreadable.');
  }
  return switch (raw) {
    'total' => ExerciseLoadBasis.total,
    'perDevice' => ExerciseLoadBasis.perDevice,
    'bodyweight' => ExerciseLoadBasis.bodyweight,
    'addedLoad' => ExerciseLoadBasis.addedLoad,
    'assistance' => ExerciseLoadBasis.assistance,
    _ => _retainUnknown(retained, 'basis', raw),
  };
}

ExerciseRepetitionBasis? _parseRepetitionBasis(
  Object? raw,
  Map<String, Object?> retained,
) {
  if (raw == null) return null;
  if (raw is! String) {
    throw const FormatException('Original repetition basis is unreadable.');
  }
  return switch (raw) {
    'total' => ExerciseRepetitionBasis.total,
    'perSide' => ExerciseRepetitionBasis.perSide,
    _ => _retainUnknown(retained, 'repetitionBasis', raw),
  };
}

ExerciseSetSide? _parseSide(Object? raw, Map<String, Object?> retained) {
  if (raw == null) return null;
  if (raw is! String) {
    throw const FormatException('Original load side is unreadable.');
  }
  return switch (raw) {
    'both' => ExerciseSetSide.both,
    'left' => ExerciseSetSide.left,
    'right' => ExerciseSetSide.right,
    _ => _retainUnknown(retained, 'side', raw),
  };
}

Never? _retainUnknown(Map<String, Object?> retained, String key, String raw) {
  if (raw.isEmpty) {
    throw const FormatException('Original load is unreadable.');
  }
  retained[key] = raw;
  return null;
}

double? _optionalFinite(Object? raw, String message) {
  if (raw == null) return null;
  if (raw is! num || !raw.isFinite) {
    throw FormatException(message);
  }
  return raw.toDouble();
}

int? _optionalPositiveInt(Object? raw, String message) {
  if (raw == null) return null;
  if (raw is! num ||
      !raw.isFinite ||
      raw != raw.truncateToDouble() ||
      raw < 1) {
    throw FormatException(message);
  }
  return raw.toInt();
}

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
