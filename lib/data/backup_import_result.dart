import 'vo2_store.dart';

/// What one database backup changed.
///
/// [days] is distinct `day_result` days written. VO2 revisions are not days,
/// and conflict or corrupt ids are not revisions. A missing `manual_vo2`
/// table is [vo2TablePresent] false. A present table with zeros is a no-op.
class BackupImportReceipt {
  const BackupImportReceipt({
    required this.days,
    required this.vo2TablePresent,
    required this.insertedRevisions,
    required this.conflictIds,
    required this.corruptIds,
    this.recalculationError,
    this.readError,
  }) : assert(days >= 0),
       assert(insertedRevisions >= 0),
       assert(conflictIds >= 0),
       assert(corruptIds >= 0),
       assert(
         vo2TablePresent ||
             (insertedRevisions == 0 && conflictIds == 0 && corruptIds == 0),
       );

  /// Store counts from `importFromDbFile`. Missing VO2 keys mean the source
  /// has no `manual_vo2` table. They are not zeros.
  factory BackupImportReceipt.fromCounts(
    Map<String, int> counts, {
    String? recalculationError,
    String? readError,
  }) {
    final present = counts.containsKey(kManualVo2Table);
    return BackupImportReceipt(
      days: counts['_days'] ?? 0,
      vo2TablePresent: present,
      insertedRevisions: present ? counts[kManualVo2Table] ?? 0 : 0,
      conflictIds: present ? counts['${kManualVo2Table}_conflict'] ?? 0 : 0,
      corruptIds: present ? counts['${kManualVo2Table}_corrupt'] ?? 0 : 0,
      recalculationError: recalculationError,
      readError: readError,
    );
  }

  final int days;
  final bool vo2TablePresent;
  final int insertedRevisions;
  final int conflictIds;
  final int corruptIds;

  /// Rows were written and the cross-day rebuild threw. Null when that
  /// rebuild finished. Distinct from [readError].
  final String? recalculationError;

  /// A later read failed after [days] and the VO2 counts had already committed.
  /// Null when the file was read through. This is not a recalc failure.
  final String? readError;

  bool get recalculationFailed => recalculationError != null;

  bool get readInterrupted => readError != null;
}

/// A user import stopped after at least one committed write or finished table.
///
/// [counts] is only what had committed. [cause] is the original failure.
/// An unreadable file that committed nothing does not use this type.
class PartialImportException implements Exception {
  PartialImportException(Map<String, int> counts, this.cause)
    : counts = Map.unmodifiable(Map<String, int>.from(counts));

  final Map<String, int> counts;
  final Object cause;

  @override
  String toString() => '$cause';
}
