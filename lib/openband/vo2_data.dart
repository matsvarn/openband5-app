// Typed manual VO2max. Callers never see SQLite maps.
//
// A stored number is user-entered ml/kg/min. The optional method is whatever
// the user typed; it is not a verified measurement. There is no fitness band,
// estimate, or substitute scalar. Missing, deleted, and unreadable are
// separate facts on the list and detail results.

const String kVo2Unit = 'ml/kg/min';
const String kVo2Origin = 'user-entered';

/// Civil `YYYY-MM-DD` that exists on the Gregorian calendar.
bool isVo2CivilDay(String day) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) return false;
  final p = day.split('-').map(int.parse).toList();
  final d = DateTime(p[0], p[1], p[2]);
  return d.year == p[0] && d.month == p[1] && d.day == p[2];
}

/// Blank becomes absent. Surrounding whitespace is not part of the method.
String? normalizeVo2Method(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  return trimmed;
}

bool isVo2EntryId(String id) => id.isNotEmpty && id == id.trim();

/// Finite and strictly positive. No upper bound is invented here.
bool isVo2Value(double value) => value.isFinite && value > 0;

/// One stored revision. [deleted] still carries the payload it removed.
class Vo2Revision {
  const Vo2Revision({
    required this.id,
    required this.revision,
    required this.measuredOn,
    required this.valueMlKgMin,
    required this.declaredMethod,
    required this.createdAt,
    required this.updatedAt,
    required this.deleted,
    this.origin = kVo2Origin,
    this.unit = kVo2Unit,
  });

  final String id;
  final int revision;
  final String measuredOn;
  final double valueMlKgMin;
  final String? declaredMethod;
  final int createdAt;
  final int updatedAt;
  final bool deleted;
  final String origin;
  final String unit;

  bool sameStored(Vo2Revision other) =>
      id == other.id &&
      revision == other.revision &&
      measuredOn == other.measuredOn &&
      valueMlKgMin == other.valueMlKgMin &&
      declaredMethod == other.declaredMethod &&
      createdAt == other.createdAt &&
      updatedAt == other.updatedAt &&
      deleted == other.deleted &&
      origin == other.origin &&
      unit == other.unit;
}

/// Null when the row is not a canonical revision. Never a zero or a stand-in day.
Vo2Revision? tryParseVo2Row(Map<String, Object?> row) {
  final id = row['id'];
  if (id is! String || !isVo2EntryId(id)) return null;
  final revision = _whole(row['revision']);
  if (revision == null || revision < 1) return null;
  final measuredOn = row['measured_on'];
  if (measuredOn is! String || !isVo2CivilDay(measuredOn)) return null;
  final value = _positive(row['value_ml_kg_min']);
  if (value == null) return null;
  if (!_canonicalMethod(row['declared_method'])) return null;
  final createdAt = _whole(row['created_at']);
  final updatedAt = _whole(row['updated_at']);
  if (createdAt == null || updatedAt == null || updatedAt < createdAt) {
    return null;
  }
  final deleted = _bit(row['deleted']);
  if (deleted == null) return null;
  if (row['origin'] != kVo2Origin || row['unit'] != kVo2Unit) return null;
  return Vo2Revision(
    id: id,
    revision: revision,
    measuredOn: measuredOn,
    valueMlKgMin: value,
    declaredMethod: row['declared_method'] as String?,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deleted: deleted,
  );
}

enum Vo2RejectReason { invalid, missing }

sealed class Vo2WriteResult {
  const Vo2WriteResult();
}

class Vo2Committed extends Vo2WriteResult {
  const Vo2Committed(this.revision, {this.retry = false});

  final Vo2Revision revision;

  /// The next revision was already stored for this same base and payload.
  final bool retry;
}

class Vo2WriteConflict extends Vo2WriteResult {
  const Vo2WriteConflict({this.head, this.headCorrupt = false});

  /// Readable current head, when there is one. A corrupt head stays null.
  final Vo2Revision? head;
  final bool headCorrupt;
}

class Vo2WriteRejected extends Vo2WriteResult {
  const Vo2WriteRejected(this.reason);

  final Vo2RejectReason reason;
}

class Vo2ListEntry {
  const Vo2ListEntry({
    required this.id,
    required this.head,
    required this.corrupt,
  });

  final String id;

  /// Null when the current head itself cannot be read. Not an older revision.
  final Vo2Revision? head;
  final bool corrupt;
}

class Vo2List {
  const Vo2List({
    required this.entries,
    required this.corruptCount,
    required this.rowCount,
  });

  /// Id order, including deleted heads.
  final List<Vo2ListEntry> entries;
  final int corruptCount;
  final int rowCount;

  bool get isEmptyStore => rowCount == 0;
}

class Vo2RevisionSlot {
  const Vo2RevisionSlot({
    required this.revision,
    required this.value,
    required this.corrupt,
  });

  /// Null when the stored revision number itself is unreadable.
  final int? revision;
  final Vo2Revision? value;
  final bool corrupt;
}

class Vo2Detail {
  const Vo2Detail({
    required this.id,
    required this.head,
    required this.missing,
    required this.headCorrupt,
    required this.revisions,
    required this.corruptRevisionCount,
  });

  final String id;
  final Vo2Revision? head;
  final bool missing;
  final bool headCorrupt;

  /// Revision order. A corrupt slot keeps its place and carries no stand-in.
  final List<Vo2RevisionSlot> revisions;
  final int corruptRevisionCount;
}

/// Integral value SQLite can store as INTEGER.
///
/// `9223372036854775808.0.toInt()` is int64 max, and that max converts back to
/// the same double, so a `toDouble` round-trip still accepts 2^63. Doubles at
/// or above 2^63 are rejected. A stored INTEGER comes back as [int], including
/// int64 max; SQLite already turns `1.0` into `1`.
int? _whole(Object? raw) {
  if (raw is int) {
    if (raw < -9223372036854775808 || raw > 9223372036854775807) return null;
    return raw;
  }
  if (raw is! double || !raw.isFinite) return null;
  if (raw >= 9223372036854775808.0) return null;
  if (raw != raw.roundToDouble()) return null;
  final n = raw.toInt();
  if (n.toDouble() != raw) return null;
  return n;
}

double? _positive(Object? raw) {
  if (raw is! num) return null;
  final value = raw.toDouble();
  if (!value.isFinite || value <= 0) return null;
  return value;
}

bool? _bit(Object? raw) {
  final n = _whole(raw);
  if (n == 0) return false;
  if (n == 1) return true;
  return null;
}

/// Null is absent. Any other non-canonical method fails the row.
bool _canonicalMethod(Object? raw) {
  if (raw == null) return true;
  if (raw is! String || raw.isEmpty || raw != raw.trim()) return false;
  return true;
}
