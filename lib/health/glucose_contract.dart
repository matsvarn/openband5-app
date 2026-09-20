// Typed glucose values for UI. Storage stays on imported_measurement;
// this file does not convert, interpolate, or invent points.

/// Plugin production unit. There is no mmol HealthDataUnit in health 12.2.1.
const String kGlucoseUnitMilligramPerDeciliter = 'MILLIGRAM_PER_DECILITER';
const String kGlucoseUnitMillimolePerLiter = 'mmol/L';

enum GlucoseUnitKind { milligramPerDeciliter, millimolePerLiter, unknown }

enum GlucoseSourceProvenance { apple, android, legacy, synthetic, unknown }

/// Honest import/read status. iOS completed/empty is never [authorizationDenied].
enum HealthMeasurementImportStatus {
  notAttempted,
  stored,
  empty,
  partial,
  authorizationUnknown,
  authorizationDenied,
  authorizationRequestFailed,
  readFailed,
  persistenceFailed,
}

class HealthMeasurementImportOutcome {
  final HealthMeasurementImportStatus status;
  final DateTime attemptedAt;

  /// Valid points accepted this pass (new, replaced, or unchanged retained).
  final int storedCount;

  /// Rows actually inserted or replaced. Unchanged reread is 0.
  final int writtenCount;
  final int invalidCount;
  final int ignoredCount;
  const HealthMeasurementImportOutcome({
    required this.status,
    required this.attemptedAt,
    this.storedCount = 0,
    this.writtenCount = 0,
    this.invalidCount = 0,
    this.ignoredCount = 0,
  });

  bool get failed =>
      status == HealthMeasurementImportStatus.authorizationDenied ||
      status == HealthMeasurementImportStatus.authorizationRequestFailed ||
      status == HealthMeasurementImportStatus.readFailed ||
      status == HealthMeasurementImportStatus.persistenceFailed;
}

class GlucoseSourceIdentity {
  final String key;
  final String sourceName;
  final String? sourceId;
  final GlucoseSourceProvenance provenance;
  const GlucoseSourceIdentity({
    required this.key,
    required this.sourceName,
    this.sourceId,
    required this.provenance,
  });

  bool get unknownIdentity =>
      provenance == GlucoseSourceProvenance.unknown ||
      key == kAppleUnknownSourceKey ||
      key == kAndroidUnknownSourceKey;

  bool get legacy => provenance == GlucoseSourceProvenance.legacy;
}

const String kAppleUnknownSourceKey = 'apple:unknown';
const String kAndroidUnknownSourceKey = 'android:unknown';
const String kLegacySourcePrefix = 'legacy:';
const String kAppleSourcePrefix = 'apple:';
const String kAndroidSourcePrefix = 'android:';
const String kSyntheticSourcePrefix = 'synthetic:';

/// Inclusive epoch-seconds Dart [DateTime] can represent. Not a physiological bound.
const int kGlucoseEpochSecMax = 8640000000000000 ~/ 1000;

String importedSourceKey({
  required bool isApple,
  required String sourceId,
  required String sourceName,
}) {
  if (isApple) {
    final id = sourceId.trim();
    if (id.isNotEmpty) return '$kAppleSourcePrefix$id';
    final name = sourceName.trim();
    if (name.isEmpty) return kAppleUnknownSourceKey;
    return '${kAppleSourcePrefix}name:$name';
  }
  final pkg = sourceName.trim();
  if (pkg.isEmpty) return kAndroidUnknownSourceKey;
  return '$kAndroidSourcePrefix$pkg';
}

String legacyImportedSourceKey(String sourceName) =>
    '$kLegacySourcePrefix$sourceName';

GlucoseSourceProvenance provenanceOfSourceKey(String key) {
  if (key.startsWith(kLegacySourcePrefix)) {
    return GlucoseSourceProvenance.legacy;
  }
  if (key.startsWith(kSyntheticSourcePrefix)) {
    return GlucoseSourceProvenance.synthetic;
  }
  if (key.startsWith(kAppleSourcePrefix)) {
    return key == kAppleUnknownSourceKey
        ? GlucoseSourceProvenance.unknown
        : GlucoseSourceProvenance.apple;
  }
  if (key.startsWith(kAndroidSourcePrefix)) {
    return key == kAndroidUnknownSourceKey
        ? GlucoseSourceProvenance.unknown
        : GlucoseSourceProvenance.android;
  }
  return GlucoseSourceProvenance.unknown;
}

GlucoseSourceIdentity glucoseSourceFromStored({
  String? sourceKey,
  String? sourceId,
  required String sourceName,
}) {
  final key = (sourceKey == null || sourceKey.isEmpty)
      ? legacyImportedSourceKey(sourceName)
      : sourceKey;
  final id = sourceId?.trim();
  return GlucoseSourceIdentity(
    key: key,
    sourceName: sourceName,
    sourceId: (id == null || id.isEmpty) ? null : id,
    provenance: provenanceOfSourceKey(key),
  );
}

GlucoseUnitKind glucoseUnitKind(String rawUnit) {
  final u = rawUnit.trim();
  if (u == kGlucoseUnitMilligramPerDeciliter ||
      u.toLowerCase() == 'mg/dl' ||
      u == 'mg/dL') {
    return GlucoseUnitKind.milligramPerDeciliter;
  }
  if (u == kGlucoseUnitMillimolePerLiter ||
      u.toLowerCase() == 'mmol/l' ||
      u.toLowerCase() == 'millimole_per_liter') {
    return GlucoseUnitKind.millimolePerLiter;
  }
  return GlucoseUnitKind.unknown;
}

class GlucoseReading {
  final String uuid;
  final DateTime measuredAt;
  final double value;
  final String rawUnit;
  final GlucoseUnitKind unitKind;
  final GlucoseSourceIdentity source;
  final DateTime? importedAt;
  const GlucoseReading({
    required this.uuid,
    required this.measuredAt,
    required this.value,
    required this.rawUnit,
    required this.unitKind,
    required this.source,
    this.importedAt,
  });

  bool get plottable =>
      value.isFinite && unitKind != GlucoseUnitKind.unknown;
}

class GlucoseSourceInventoryItem {
  final GlucoseSourceIdentity source;
  final bool excluded;
  final DateTime? lastMeasuredAt;
  final DateTime? lastImportedAt;
  final int readingCount;
  const GlucoseSourceInventoryItem({
    required this.source,
    required this.excluded,
    this.lastMeasuredAt,
    this.lastImportedAt,
    this.readingCount = 0,
  });
}

class GlucoseAttempt {
  final HealthMeasurementImportStatus status;
  final DateTime? attemptedAt;
  final int storedCount;
  final int writtenCount;
  final int invalidCount;
  final int ignoredCount;
  const GlucoseAttempt({
    this.status = HealthMeasurementImportStatus.notAttempted,
    this.attemptedAt,
    this.storedCount = 0,
    this.writtenCount = 0,
    this.invalidCount = 0,
    this.ignoredCount = 0,
  });

  static const none = GlucoseAttempt();
}

class GlucoseSnapshot {
  final GlucoseSourceIdentity? selected;
  final bool selectedExcluded;
  final List<GlucoseSourceInventoryItem> sources;
  final List<GlucoseReading> history;
  final List<GlucoseReading> series;
  final GlucoseAttempt attempt;
  final DateTime? lastMeasuredAt;
  final DateTime? lastImportedAt;
  /// More readable history exists beyond [history]. Not stored-row count.
  final bool truncated;
  final int unreadableCount;
  const GlucoseSnapshot({
    this.selected,
    this.selectedExcluded = false,
    this.sources = const [],
    this.history = const [],
    this.series = const [],
    this.attempt = GlucoseAttempt.none,
    this.lastMeasuredAt,
    this.lastImportedAt,
    this.truncated = false,
    this.unreadableCount = 0,
  });
}

/// [outcome] is the durable import result even when snapshot refresh fails.
/// [snapshot] is omitted on [refreshFailed]; that is not an empty history.
class GlucoseImportResult {
  final HealthMeasurementImportOutcome outcome;
  final GlucoseSnapshot? snapshot;
  final bool refreshFailed;
  const GlucoseImportResult({
    required this.outcome,
    this.snapshot,
    this.refreshFailed = false,
  });
}

GlucoseSnapshot buildGlucoseSnapshot({
  required List<Map<String, dynamic>> rows,
  required List<Map<String, dynamic>> settings,
  required Map<String, dynamic>? receipt,
  String? sourceKey,
  int? limit,
}) {
  var unreadable = 0;
  final storedByKey = <String, int>{};
  final importedByKey = <String, DateTime>{};
  final readings = <GlucoseReading>[];
  for (final row in rows) {
    final key = glucoseStoredSourceKey(row);
    if (key == null) {
      unreadable++;
      continue;
    }
    storedByKey[key] = (storedByKey[key] ?? 0) + 1;
    if (glucoseImportedAtMalformed(row['imported_at'])) unreadable++;
    final imported = _dateTimeFromEpochSeconds(row['imported_at']);
    if (imported != null) {
      final prevImported = importedByKey[key];
      if (prevImported == null || imported.isAfter(prevImported)) {
        importedByKey[key] = imported;
      }
    }
    try {
      final reading = glucoseReadingFromStored(row);
      if (reading == null) {
        unreadable++;
        continue;
      }
      readings.add(reading);
    } catch (_) {
      unreadable++;
    }
  }

  final excluded = <String>{};
  for (final s in settings) {
    final key = _healthIdentityText(s['source_key']);
    if (key == null) {
      if (s['source_key'] != null) unreadable++;
      continue;
    }
    if (key.isEmpty) continue;
    if (_storedFlag(s['excluded'])) excluded.add(key);
  }

  final byKey = <String, GlucoseSourceInventoryItem>{};
  for (final s in settings) {
    final key = _healthIdentityText(s['source_key']);
    if (key == null || key.isEmpty) continue;
    byKey[key] = GlucoseSourceInventoryItem(
      source: glucoseSourceFromStored(sourceKey: key, sourceName: ''),
      excluded: excluded.contains(key),
      lastImportedAt: importedByKey[key],
      readingCount: storedByKey[key] ?? 0,
    );
  }
  for (final r in readings) {
    final prev = byKey[r.source.key];
    final lastMeasured = prev?.lastMeasuredAt;
    final newer = lastMeasured == null || r.measuredAt.isAfter(lastMeasured);
    byKey[r.source.key] = GlucoseSourceInventoryItem(
      source: newer ? r.source : prev!.source,
      excluded: excluded.contains(r.source.key),
      lastMeasuredAt: newer ? r.measuredAt : lastMeasured,
      lastImportedAt: importedByKey[r.source.key],
      readingCount: storedByKey[r.source.key] ?? (prev?.readingCount ?? 0),
    );
  }
  for (final e in storedByKey.entries) {
    byKey.putIfAbsent(
      e.key,
      () => GlucoseSourceInventoryItem(
        source: glucoseSourceFromStored(sourceKey: e.key, sourceName: ''),
        excluded: excluded.contains(e.key),
        lastImportedAt: importedByKey[e.key],
        readingCount: e.value,
      ),
    );
  }

  final sources = byKey.values.toList()
    ..sort((a, b) => a.source.key.compareTo(b.source.key));

  String? selectedKey = sourceKey;
  if (selectedKey == null) {
    final included = [
      for (final s in sources)
        if (!s.excluded) s.source.key,
    ];
    selectedKey = included.isNotEmpty
        ? included.first
        : (sources.isEmpty ? null : sources.first.source.key);
  }
  final selectedItem = selectedKey == null ? null : byKey[selectedKey];
  final selected = selectedKey == null
      ? null
      : (selectedItem?.source ??
          glucoseSourceFromStored(sourceKey: selectedKey, sourceName: ''));
  final selectedExcluded =
      selectedKey != null && excluded.contains(selectedKey);

  final forSource = [
    for (final r in readings)
      if (r.source.key == selectedKey) r,
  ]..sort(compareGlucoseNewestFirst);

  final history = limit == null ? forSource : forSource.take(limit).toList();

  final decoded = _glucoseAttemptFromReceipt(receipt);
  return assembleBoundedGlucoseSnapshot(
    sources: sources,
    history: history,
    dayReadings: forSource,
    receiptAttempt: decoded,
    selected: selected,
    selectedKey: selectedKey,
    selectedExcluded: selectedExcluded,
    truncated: limit != null && forSource.length > history.length,
    unreadableCount: unreadable + decoded.unreadable,
  );
}

/// Local midnight .. next local midnight. Uses `DateTime(y, m, d+1)`, not 86400.
/// Null when next midnight is not a representable [DateTime] — no invented end.
({DateTime start, DateTime end})? glucoseLocalDayWindow(DateTime measuredAt) {
  try {
    final local = measuredAt.isUtc ? measuredAt.toLocal() : measuredAt;
    return (
      start: DateTime(local.year, local.month, local.day),
      end: DateTime(local.year, local.month, local.day + 1),
    );
  } catch (_) {
    return null;
  }
}

/// Newest measurement first, then UUID descending. Shared by production SQL
/// consumers and the synthetic snapshot so hero, history, and series agree.
int compareGlucoseNewestFirst(GlucoseReading a, GlucoseReading b) {
  final byTime = b.measuredAt.compareTo(a.measuredAt);
  if (byTime != 0) return byTime;
  return b.uuid.compareTo(a.uuid);
}

List<GlucoseReading> glucoseSeriesFromLatestDay(
  List<GlucoseReading> selectedNewestFirst, {
  required bool excluded,
}) {
  if (excluded || selectedNewestFirst.isEmpty) return const [];
  final latest = selectedNewestFirst.first;
  if (!latest.plottable) return const [];
  final day = glucoseLocalDayWindow(latest.measuredAt);
  if (day == null) return const [];
  final unit = latest.unitKind;
  return [
    for (final r in selectedNewestFirst)
      if (!r.measuredAt.isBefore(day.start) &&
          r.measuredAt.isBefore(day.end) &&
          r.plottable &&
          r.unitKind == unit)
        r,
  ];
}

GlucoseSnapshot assembleBoundedGlucoseSnapshot({
  required List<GlucoseSourceInventoryItem> sources,
  required List<GlucoseReading> history,
  required List<GlucoseReading> dayReadings,
  required ({GlucoseAttempt attempt, int unreadable}) receiptAttempt,
  required GlucoseSourceIdentity? selected,
  required String? selectedKey,
  required bool selectedExcluded,
  required bool truncated,
  required int unreadableCount,
}) {
  GlucoseSourceInventoryItem? selectedItem;
  if (selectedKey != null) {
    for (final s in sources) {
      if (s.source.key == selectedKey) {
        selectedItem = s;
        break;
      }
    }
  }
  return GlucoseSnapshot(
    selected: selected,
    selectedExcluded: selectedExcluded,
    sources: sources,
    history: history,
    series: glucoseSeriesFromLatestDay(
      dayReadings,
      excluded: selectedExcluded,
    ),
    attempt: receiptAttempt.attempt,
    lastMeasuredAt: selectedItem?.lastMeasuredAt,
    lastImportedAt: selectedItem?.lastImportedAt,
    truncated: truncated,
    unreadableCount: unreadableCount,
  );
}

/// Stored identity key, or null when the row cannot name a source honestly.
String? glucoseStoredSourceKey(Map<String, dynamic> row) {
  final key = _healthIdentityText(row['source_key']);
  if (key != null && key.isNotEmpty) return key;
  if (row['source_key'] != null && key == null) return null;
  final name = _healthIdentityText(row['source']);
  if (name == null) return null;
  return legacyImportedSourceKey(name);
}

({GlucoseAttempt attempt, int unreadable}) _glucoseAttemptFromReceipt(
  Map<String, dynamic>? receipt,
) {
  if (receipt == null) {
    return (attempt: GlucoseAttempt.none, unreadable: 0);
  }
  var unreadable = 0;
  final name = _healthIdentityText(receipt['outcome']);
  HealthMeasurementImportStatus status;
  if (name == null) {
    unreadable++;
    status = HealthMeasurementImportStatus.partial;
  } else {
    status = HealthMeasurementImportStatus.partial;
    var matched = false;
    for (final s in HealthMeasurementImportStatus.values) {
      if (s.name == name) {
        status = s;
        matched = true;
        break;
      }
    }
    if (!matched) unreadable++;
  }
  final rawAttempt = receipt['last_attempt_at'];
  final attemptedAt = _dateTimeFromEpochSeconds(rawAttempt);
  if (rawAttempt != null && attemptedAt == null) unreadable++;

  int count(Object? v) {
    if (v == null) return 0;
    if (v is num && v.isFinite) return v.toInt();
    if (v is String) {
      final n = num.tryParse(v.trim());
      if (n != null && n.isFinite) return n.toInt();
    }
    unreadable++;
    return 0;
  }

  return (
    attempt: GlucoseAttempt(
      status: status,
      attemptedAt: attemptedAt,
      storedCount: count(receipt['stored_count']),
      writtenCount: count(receipt['written_count']),
      invalidCount: count(receipt['invalid_count']),
      ignoredCount: count(receipt['ignored_count']),
    ),
    unreadable: unreadable,
  );
}

GlucoseAttempt glucoseAttemptFromReceipt(Map<String, dynamic>? receipt) =>
    decodeGlucoseReceipt(receipt).attempt;

({GlucoseAttempt attempt, int unreadable}) decodeGlucoseReceipt(
  Map<String, dynamic>? receipt,
) =>
    _glucoseAttemptFromReceipt(receipt);

GlucoseReading? glucoseReadingFromStored(Map<String, dynamic> row) {
  final uuid = _healthIdentityText(row['uuid']);
  if (uuid == null || uuid.isEmpty) return null;
  final measuredAt = _dateTimeFromEpochSeconds(row['ts']);
  if (measuredAt == null) return null;
  final value = _storedNum(row['value'])?.toDouble();
  if (value == null || !value.isFinite) return null;
  if (row['source_key'] != null && _healthIdentityText(row['source_key']) == null) {
    return null;
  }
  if (row['source_id'] != null && _healthIdentityText(row['source_id']) == null) {
    return null;
  }
  if (row['source'] != null && _healthIdentityText(row['source']) == null) {
    return null;
  }
  final unit = row['unit'] is String ? row['unit'] as String : '';
  final sourceName = _healthIdentityText(row['source']) ?? '';
  return GlucoseReading(
    uuid: uuid,
    measuredAt: measuredAt,
    value: value,
    rawUnit: unit,
    unitKind: glucoseUnitKind(unit),
    source: glucoseSourceFromStored(
      sourceKey: _healthIdentityText(row['source_key']),
      sourceId: _healthIdentityText(row['source_id']),
      sourceName: sourceName,
    ),
    importedAt: _dateTimeFromEpochSeconds(row['imported_at']),
  );
}

num? _storedNum(Object? v) {
  if (v == null) return null;
  if (v is num) return v.isFinite ? v : null;
  if (v is String) {
    final n = num.tryParse(v.trim());
    return n != null && n.isFinite ? n : null;
  }
  return null;
}

/// Authentic Health identity strings only. Numbers/bools are not source IDs.
String? _healthIdentityText(Object? v) => v is String ? v : null;

bool _storedFlag(Object? v) {
  if (v is num) return v.toInt() == 1;
  if (v is String) {
    final s = v.trim().toLowerCase();
    return s == '1' || s == 'true';
  }
  return false;
}

/// Present corrupt import stamp. Null/absent is legacy, not malformed.
bool glucoseImportedAtMalformed(Object? v) {
  if (v == null) return false;
  return _dateTimeFromEpochSeconds(v) == null;
}

/// Seconds that Dart [DateTime] can represent. Not a physiological bound.
DateTime? glucoseDateTimeFromEpochSeconds(Object? v) =>
    _dateTimeFromEpochSeconds(v);

DateTime? _dateTimeFromEpochSeconds(Object? v) {
  final n = _storedNum(v);
  if (n == null) return null;
  final sec = n.toInt();
  if (sec < -kGlucoseEpochSecMax || sec > kGlucoseEpochSecMax) return null;
  try {
    return DateTime.fromMillisecondsSinceEpoch(sec * 1000);
  } catch (_) {
    return null;
  }
}
