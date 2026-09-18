// Stored personal details and dated calculation inputs. Missing fields keep
// the metrics that depend on them unavailable.

/// A calendar date, not an instant. Reject normalized dates such as February 31.
DateTime? parseBirthDate(Object? value) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return null;
  }
  final parts = value.split('-').map(int.parse).toList();
  final date = DateTime(parts[0], parts[1], parts[2]);
  return date.year == parts[0] && date.month == parts[1] && date.day == parts[2]
      ? date
      : null;
}

String birthDateString(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

int? ageOnDate(DateTime? birthDate, DateTime at) {
  if (birthDate == null) return null;
  final date = at.toLocal();
  var years = date.year - birthDate.year;
  if (date.month < birthDate.month ||
      (date.month == birthDate.month && date.day < birthDate.day)) {
    years--;
  }
  return years < 0 ? null : years;
}

/// Stored personal details. A legacy numeric age cannot establish a birth date.
class PersonalProfile {
  final DateTime? birthDate;
  final double? weightKg;
  final double? heightCm;
  final String? sex;
  final int? restingHrManual;

  const PersonalProfile({
    this.birthDate,
    this.weightKg,
    this.heightCm,
    this.sex,
    this.restingHrManual,
  });

  factory PersonalProfile.fromMap(Map<String, dynamic>? m) => PersonalProfile(
    birthDate: parseBirthDate(m?['birth_date']),
    weightKg: (m?['weight_kg'] as num?)?.toDouble(),
    heightCm: (m?['height_cm'] as num?)?.toDouble(),
    sex: (m?['sex'] as String?)?.toLowerCase(),
    restingHrManual: (m?['resting_hr'] as num?)?.round(),
  );

  Profile forDate(DateTime at) => Profile(
    ageYears: ageOnDate(birthDate, at),
    weightKg: weightKg,
    heightCm: heightCm,
    sex: sex,
    restingHrManual: restingHrManual,
  );

  bool get isComplete => forDate(DateTime.now()).isComplete;

  Map<String, dynamic> toMap() => {
    if (birthDate != null) 'birth_date': birthDateString(birthDate!),
    if (weightKg != null) 'weight_kg': weightKg,
    if (heightCm != null) 'height_cm': heightCm,
    if (sex != null) 'sex': sex,
    if (restingHrManual != null) 'resting_hr': restingHrManual,
  };
}

/// Calculation inputs resolved for a particular day or workout. Never persist
/// this age as the user's personal profile.
class Profile {
  final int? ageYears;
  final double? weightKg;
  final double? heightCm;
  final String? sex; // 'm' | 'f' (lowercase; matches the AppState profile map)
  final int? restingHrManual; // optional user-supplied RHR

  const Profile({
    this.ageYears,
    this.weightKg,
    this.heightCm,
    this.sex,
    this.restingHrManual,
  });

  Map<String, dynamic> toMap() => {
    if (ageYears != null) 'age': ageYears,
    if (weightKg != null) 'weight_kg': weightKg,
    if (heightCm != null) 'height_cm': heightCm,
    if (sex != null) 'sex': sex,
    if (restingHrManual != null) 'resting_hr': restingHrManual,
  };

  // NO `hrMaxTanaka` HERE. It was `208 − 0.7·age` inlined on the profile, which
  // made the HR ceiling a property of the ATHLETE alone — and the app then
  // carried four of them (this one, `220−age` twice, and `(220−age)+25`), so
  // one user's zone timeline and that same day's session zone bands were banded
  // off different ceilings with nothing on screen saying so.
  //
  // The one definition is `compute/hr_max.dart`'s `estimatedMaxHr(age, family)`
  // and it takes the STRAP as well: what a band can read at intensity is a
  // property of its sensor, so an uncalibrated or unstamped strap gets no
  // ceiling rather than gen4's. Callers resolve it at the layer that knows
  // which device measured the window and pass it down. (TS-03a)

  bool get isComplete =>
      ageYears != null && weightKg != null && heightCm != null && sex != null;

  /// The anchors Keytel (2005) needs to turn heart rate into kcal: age, body
  /// mass and sex. Height is not one of them, so it is deliberately absent
  /// here — gating calories on [isComplete] would refuse to score a profile
  /// that has everything the formula actually reads.
  ///
  /// The one definition of "can we cost this session in calories", shared by
  /// the live tick and the substrate re-score. They used to disagree: the
  /// re-score refused to guess while the live tick silently substituted a
  /// 30-year-old 70 kg male, so an unfinished profile produced a confident
  /// kcal number that was simply somebody else's.
  bool get hasCalorieAnchors =>
      ageYears != null && weightKg != null && sex != null;
}

/// Normalise every sex spelling the app can persist onto the three names the
/// analytics coefficient tables key on: 'male' | 'female' | 'nonbinary'.
///
/// Two writers disagree. Onboarding (`profile_setup_screen`) stores 'm'/'f';
/// the profile screen offers 'male'/'female'/'other'. Every scored path — day
/// calories, TRIMP, the live tick, a manually logged session — has to land on
/// the same coefficient block for the same stored value, or one field of one
/// profile scores as two different people. It happened: TRIMP tested `== 'f'`
/// while the calorie path accepted 'female' too, so a profile written by the
/// profile screen got female calories and male TRIMP.
///
/// 'other' and anything unrecognised map to `nonbinary`, which the analytics
/// tables define as the mean of the two published sex constants rather than a
/// guess at one of them.
String workoutSex(String? sex) {
  switch ((sex ?? '').toLowerCase()) {
    case 'm':
    case 'male':
      return 'male';
    case 'f':
    case 'female':
      return 'female';
    default:
      return 'nonbinary';
  }
}
