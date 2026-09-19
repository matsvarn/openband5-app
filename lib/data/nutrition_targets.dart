// Dated optional nutrition targets — decode and boundary checks.
//
// Persistence lives in LocalDb (`nutrition_target_period`). This file owns
// untyped-source decoding so present invalid legacy / SQLite values refuse
// rather than becoming unset, and so writes reject bad numbers before a row
// is touched. No calorie recommendation, learned requirement, or default lives
// here.

/// Existing SharedPreferences profile blob. Read-only for this unit.
const kLegacyProfilePrefsKey = 'local_profile_json';

/// Undated energy key inside [kLegacyProfilePrefsKey]. No date, no fat/carb.
const kLegacyEnergyTargetKey = 'kcal_target';

/// Undated protein key inside [kLegacyProfilePrefsKey]. No date, no fat/carb.
const kLegacyProteinTargetKey = 'protein_target';

const kNutritionTargetPeriodTable = 'nutrition_target_period';

/// Strict local calendar day `YYYY-MM-DD`. Not a UTC timestamp.
bool isNutritionTargetDay(String day) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) return false;
  final p = day.split('-').map(int.parse).toList();
  final d = DateTime(p[0], p[1], p[2]);
  return d.year == p[0] && d.month == p[1] && d.day == p[2];
}

void requireNutritionTargetDay(String day) {
  if (!isNutritionTargetDay(day)) {
    throw ArgumentError.value(
      day,
      'day',
      'Expected a local YYYY-MM-DD calendar date.',
    );
  }
}

/// Finite positive energy when set. Null is unset. Present 0 is not a clear;
/// the historical writer cleared with blank → null.
double? decodeOptionalEnergy(Object? raw) {
  if (raw == null) return null;
  if (raw is! num || !raw.isFinite || raw <= 0) {
    throw const FormatException('Stored nutrition energy is unreadable.');
  }
  return raw.toDouble();
}

/// Finite nonnegative grams when set. Zero is an explicit user value.
double? decodeOptionalGrams(Object? raw) {
  if (raw == null) return null;
  if (raw is! num || !raw.isFinite || raw < 0) {
    throw const FormatException('Stored nutrition grams are unreadable.');
  }
  return raw.toDouble();
}

void requireOptionalEnergy(double? value, String name) {
  if (value == null) return;
  if (!value.isFinite || value <= 0) {
    throw ArgumentError.value(
      value,
      name,
      'Energy must be a finite positive value when set.',
    );
  }
}

void requireOptionalGrams(double? value, String name) {
  if (value == null) return;
  if (!value.isFinite || value < 0) {
    throw ArgumentError.value(
      value,
      name,
      'Gram targets must be finite and nonnegative when set.',
    );
  }
}

void requireNutritionTargetNumbers({
  double? energyKcal,
  double? proteinG,
  double? carbohydrateG,
  double? fatG,
}) {
  requireOptionalEnergy(energyKcal, 'energyKcal');
  requireOptionalGrams(proteinG, 'proteinG');
  requireOptionalGrams(carbohydrateG, 'carbohydrateG');
  requireOptionalGrams(fatG, 'fatG');
}
