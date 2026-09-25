// Your data — getting it out, keeping a copy, bringing one back.
//
// Everything here was already written, tested, and reachable from nothing.
// `csv_export.dart`, `LocalDb.exportCopy`, `auto_backup.dart` and the four
// importers all existed; the only code that read the whole database out of
// the app was the UPLOAD path. So the app told the user to "export first"
// immediately before the one destructive action in it, and there was no
// export; and the automatic backup defaulted to off with no way to turn it
// on, which made the foreground hook a permanent no-op and the new-phone
// story "you don't have one".
//
// A local-first app whose data cannot leave is not local-first, it is trapped.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/auto_backup.dart';
import '../../data/csv_export.dart';
import '../../data/db.dart';
import '../../import/backup_crypto.dart';
import '../../l10n/app_localizations.dart';
import '../../openband/release_scope.dart';
import '../../openband/theme.dart';
import '../../state/app_state.dart';
import '../activity/share.dart' show shareOrigin;
import '../onboarding/welcome.dart'
    show
        ImportOutcome,
        ImportReport,
        PassphraseCancelled,
        askBackupPassphrase,
        runImport;
import '../screens/home_screen.dart' show dbRebuiltCard;
import '../ui2.dart';
import 'phone_import.dart';
import 'profile.dart';

/// What an action has to say for itself: the line to show, and whether it is a
/// failure. Without the second half every outcome rendered as "Done ✓".
typedef _Note = (String text, bool failed);

class DataScreen extends StatefulWidget {
  final bool releaseReduced;

  const DataScreen({super.key, this.releaseReduced = kOpenBandReleaseReduced});

  @override
  State<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends State<DataScreen> {
  bool _busy = false;
  String? _note;

  /// Whether [_note] is a failure. Every outcome used to render as "Done" with
  /// a green check — a thrown FileSystemException from the export included.
  bool _noteFailed = false;
  ImportOutcome? _outcome;

  void _say(String s, {bool failed = false}) {
    if (mounted) {
      setState(() {
        _note = s;
        _noteFailed = failed;
      });
    }
  }

  /// Run [job] with the screen locked, reporting whatever it says or throws.
  ///
  /// Every action on this screen is slow, destructive-adjacent or both, and a
  /// second tap while one is running would race the first over the same files.
  Future<void> _run(Future<_Note> Function() job) async {
    if (_busy) return;
    final failedMessage = AppLocalizations.of(context)?.dataFailed;
    setState(() {
      _busy = true;
      _note = null;
      _outcome = null;
    });
    try {
      final (text, failed) = await job();
      _say(text, failed: failed);
    } on PassphraseCancelled {
      // Closing the passphrase prompt is a decision. "Failed:" over it would
      // report the user's own choice back to them as a fault.
    } catch (e) {
      if (mounted) {
        _say(failedMessage?.call(e.toString()) ?? 'Failed: $e', failed: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<_Note> _exportCsv() async {
    final l = AppLocalizations.of(context);
    final created = _exportCreated(context);
    // Read before the export runs: an anchor taken after a multi-second await
    // may be measuring a screen the user has already left.
    final origin = shareOrigin(context);
    final res = await exportCsvFiles(kCsvExportSets);
    if (res.paths.isEmpty) {
      return res.hasFailures
          ? (
              l?.dataNothingExportedFailed(res.failed.join(', ')) ??
                  'Nothing exported (${res.failed.join(', ')} failed).',
              true,
            )
          : (l?.dataNothingToExportYet ?? 'Nothing to export yet.', false);
    }
    await Share.shareXFiles(
      [for (final p in res.paths) XFile(p)],
      subject: 'OpenStrap export',
      sharePositionOrigin: origin,
    );
    final failed = res.hasFailures
        ? ' ${l?.dataSetsFailed(res.failed.length, res.failed.join(', ')) ?? '${res.failed.length} set(s) failed: ${res.failed.join(', ')}.'}'
        : '';
    return ('$created$failed', res.hasFailures);
  }

  Future<_Note> _exportDb() async {
    final created = _exportCreated(context);
    final origin = shareOrigin(context);
    // VACUUM INTO — a transactionally consistent snapshot, not a file copy.
    final path = await LocalDb.exportCopy();
    await Share.shareXFiles(
      [XFile(path)],
      subject: 'OpenStrap database',
      sharePositionOrigin: origin,
    );
    return (created, false);
  }

  /// The same VACUUM'd snapshot as [_exportDb], sealed with AES-256-GCM under
  /// a key derived from a passphrase this app never stores.
  ///
  /// The plaintext intermediate is deleted whatever happens: an encrypted
  /// backup that leaves a readable copy of the whole health record in the
  /// share directory has encrypted nothing.
  Future<_Note> _exportEncrypted() async {
    final pass = await askBackupPassphrase(context, creating: true);
    if (pass == null) return ('', false); // cancelled
    if (!mounted) return ('', false);
    final created = _exportCreated(context);
    final origin = shareOrigin(context);
    final plain = await LocalDb.exportCopy();
    final dest = '$plain.osbk';
    try {
      // 210 000 PBKDF2 rounds is seconds of solid CPU. On the UI isolate that
      // is a frozen app; nothing in the crypto path touches a plugin, which is
      // what makes the worker legal.
      await Isolate.run(() => encryptBackupFile(File(plain), File(dest), pass));
    } finally {
      try {
        await File(plain).delete();
      } catch (_) {}
    }
    await Share.shareXFiles(
      [XFile(dest)],
      subject: 'OpenStrap encrypted backup',
      sharePositionOrigin: origin,
    );
    return (created, false);
  }

  Future<_Note> _reanalyze(AppState app) async {
    final l = AppLocalizations.of(context);
    final n = await app.reanalyzeAll();
    return (
      l?.dataDaysReanalyzed(n) ?? '$n day${n == 1 ? '' : 's'} re-analyzed.',
      false,
    );
  }

  Future<_Note> _backupNow(AppState app) async {
    final l = AppLocalizations.of(context);
    final outcome = await app.runBackupNow();
    if (outcome.error != null) {
      return (
        l?.dataBackupFailed(outcome.error!) ??
            'Backup failed: ${outcome.error}',
        true,
      );
    }
    if (!outcome.succeeded) {
      return (l?.dataBackupSkipped ?? 'Backup skipped.', false);
    }
    return (
      l?.dataBackedUpTo(outcome.path!) ?? 'Backed up to ${outcome.path}',
      false,
    );
  }

  Future<_Note> _import(AppState app) async {
    final l = AppLocalizations.of(context);
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withReadStream: false,
      );
    } catch (e) {
      return (
        l?.dataCouldNotOpenPicker(e.toString()) ??
            'Could not open the file picker: $e',
        true,
      );
    }
    final paths = (picked?.files ?? const [])
        .map((f) => f.path)
        .whereType<String>()
        .toList();
    // cancelled — not a failure, say nothing
    if (paths.isEmpty) return ('', false);
    if (!mounted) return ('', false);
    final outcome = await runImport(
      app,
      paths,
      askPassphrase: () {
        if (!mounted) return Future<String?>.value();
        return askBackupPassphrase(context);
      },
    );
    if (mounted) setState(() => _outcome = outcome);
    return ('', false);
  }

  Future<_Note> _setCadence(AppState app) async {
    return _setCadenceTo(app, _nextCadence(app.backupCadence));
  }

  Future<_Note> _setCadenceTo(AppState app, BackupCadence next) async {
    final de = Localizations.localeOf(context).languageCode == 'de';
    final outcome = await app.setBackupCadence(next);
    if (outcome == null) {
      return (
        de ? 'Automatische Sicherung aus' : 'Automatic backup off',
        false,
      );
    }
    if (outcome.error != null) {
      return (
        de
            ? 'Backup fehlgeschlagen: ${outcome.error}'
            : 'Backup failed: ${outcome.error}',
        true,
      );
    }
    if (!outcome.succeeded) {
      return (de ? 'Backup übersprungen.' : 'Backup skipped.', true);
    }
    return (de ? 'Sicherung erstellt' : 'Backup created', false);
  }

  @override
  Widget build(BuildContext c) {
    final app = c.watch<AppState>();
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final last = app.lastBackupAt;
    final o = _outcome;
    final rebuilt = dbRebuiltCard(app.dbRebuild);
    if (widget.releaseReduced) {
      return DataScreenView(
        cadence: app.backupCadence,
        lastBackupAt: last,
        busy: _busy,
        note: _note,
        noteFailed: _noteFailed,
        outcome: o,
        rebuilt: rebuilt,
        importRollupError: app.importRollupError,
        reanalyzeProgress: app.reanalyzeProgress,
        reanalyzing: app.reanalyzing,
        onExportDatabase: _busy ? null : () => _run(_exportDb),
        onExportEncrypted: _busy ? null : () => _run(_exportEncrypted),
        onExportCsv: _busy ? null : () => _run(_exportCsv),
        onAutomatic: _busy
            ? null
            : (enabled) => _run(
                () => _setCadenceTo(
                  app,
                  enabled ? BackupCadence.daily : BackupCadence.off,
                ),
              ),
        onBackupNow: _busy ? null : () => _run(() => _backupNow(app)),
        onImport: _busy ? null : () => _run(() => _import(app)),
        onReanalyze: _busy || app.reanalyzing
            ? null
            : () => _run(() => _reanalyze(app)),
      );
    }
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.x4),
              child: NavBar(l?.dataNavTitle ?? 'Your data'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
                children: [
                  // Home shows this too, on the launch it happened. It belongs
                  // here as well because this is the screen someone opens when
                  // they notice their food log is empty, and it is the only
                  // screen where the card is ALSO an instruction: "Import a
                  // file" three rows down reads the quarantined file back.
                  // (It is named `openstrap.db.unopenable-<ms>`, not `.db` —
                  // `runImport` matches that shape explicitly, because routing
                  // on the suffix alone sent a SQLite file into the vendor-CSV
                  // importer.)
                  if (rebuilt != null) ...[
                    rebuilt,
                    const SizedBox(height: S.x5),
                  ],
                  settingsGroup(c, l?.dataExportGroup ?? 'Export', [
                    SetRow(
                      LucideIcons.fileSpreadsheet,
                      C.green,
                      l?.dataExportSpreadsheets ?? 'Export as spreadsheets',
                      // export-provenance: the daily file now carries `source`
                      // and `algo_version` per day, so an imported vendor
                      // snapshot and a day derived from 1 Hz rows stop being
                      // byte-identical. An empty source cell is unknown
                      // provenance — never back-filled to 'band'.
                      sub:
                          l?.dataExportSpreadsheetsSub(kCsvExportSets.length) ??
                          '${kCsvExportSets.length} CSV files — daily metrics, '
                              'workouts, sleep, journal, labs, and everything you '
                              'typed in. Each day carries where it came from and '
                              'which algorithm version scored it',
                      onTap: _busy ? null : () => _run(_exportCsv),
                    ),
                    SetRow(
                      LucideIcons.database,
                      C.blue,
                      l?.dataExportDatabase ?? 'Export the database',
                      sub:
                          l?.dataExportDatabaseSub ??
                          'One .db file. Lossless, and the only format that '
                              'restores onto another phone. Readable by anything '
                              'that opens SQLite — including anyone who gets the '
                              'file',
                      onTap: _busy ? null : () => _run(_exportDb),
                    ),
                    SetRow(
                      LucideIcons.lock,
                      C.purple,
                      l?.dataExportEncrypted ?? 'Export an encrypted backup',
                      sub:
                          l?.dataExportEncryptedSub ??
                          'The same complete copy, sealed with a passphrase, '
                              'for somewhere like iCloud. Forget the passphrase '
                              'and that file is gone — there is no recovery, '
                              'because there is no account holding a key',
                      onTap: _busy ? null : () => _run(_exportEncrypted),
                    ),
                  ]),
                  const SizedBox(height: S.x5),
                  settingsGroup(c, l?.dataAutoBackupGroup ?? 'Automatic backup', [
                    SetRow(
                      LucideIcons.calendarClock,
                      C.purple,
                      l?.dataHowOften ?? 'How often',
                      // Unencrypted, and it says so. The encrypted format is
                      // new and its restore path has not yet run green against
                      // a file written by an older build — defaulting the
                      // automatic copy to a format that might not open is
                      // worse than the plaintext it replaced.
                      sub:
                          l?.dataHowOftenSub(kBackupDirName, kBackupsKept) ??
                          'Writes a compressed, unencrypted copy to '
                              '$kBackupDirName, keeping the last $kBackupsKept',
                      value: app.backupCadence.label,
                      onTap: _busy ? null : () => _run(() => _setCadence(app)),
                    ),
                    SetRow(
                      LucideIcons.clock,
                      C.n500,
                      l?.dataLastBackup ?? 'Last backup',
                      value: last == null
                          ? (l?.dataNever ?? 'Never')
                          : _stamp(last),
                      chevron: false,
                    ),
                    SetRow(
                      LucideIcons.hardDriveDownload,
                      C.teal,
                      l?.dataBackUpNow ?? 'Back up now',
                      onTap: _busy ? null : () => _run(() => _backupNow(app)),
                    ),
                  ]),
                  const SizedBox(height: S.x5),
                  settingsGroup(c, l?.dataBringDataInGroup ?? 'Bring data in', [
                    SetRow(
                      LucideIcons.upload,
                      C.orange,
                      l?.dataImportFile ?? 'Import a file',
                      sub:
                          l?.dataImportFileSub ??
                          'An OpenStrap backup (encrypted or not), a journal '
                              'CSV you edited, a raw sensor export, or a vendor '
                              'CSV. Days this band already measured are never '
                              'overwritten',
                      onTap: _busy ? null : () => _run(() => _import(app)),
                    ),
                    // Progressive disclosure: two health-store reads, each with
                    // its own consent and its own ceiling, behind one row rather
                    // than two more rows on this screen.
                    SetRow(
                      LucideIcons.smartphone,
                      C.blue,
                      l?.dataFromYourPhone ?? 'From your phone',
                      sub:
                          l?.dataFromYourPhoneSub ??
                          'Resting heart rate, blood pressure, glucose and '
                              'body temperature',
                      onTap: _busy
                          ? null
                          : () => goto(
                              c,
                              PhoneImport(
                                releaseReduced: widget.releaseReduced,
                              ),
                            ),
                    ),
                  ]),
                  const SizedBox(height: S.x5),
                  settingsGroup(c, l?.dataRebuildGroup ?? 'Rebuild', [
                    // The engine puts days on hold after a ≥3 h timezone jump
                    // "until Re-analyze data runs" — and nothing in the app ran
                    // it. A flight abroad quietly stopped days updating with no
                    // control anywhere to release them.
                    SetRow(
                      LucideIcons.refreshCcw,
                      C.blue,
                      l?.dataReanalyzeEverything ?? 'Re-analyze everything',
                      sub:
                          l?.dataReanalyzeEverythingSub ??
                          'Scores every day again from what is stored. Needed '
                              'after a long-haul flight, and after an import that '
                              'landed days out of order',
                      value: app.reanalyzeProgress,
                      onTap: _busy || app.reanalyzing
                          ? null
                          : () => _run(() => _reanalyze(app)),
                    ),
                  ]),
                  if (_busy) ...[
                    const SizedBox(height: S.x6),
                    Center(
                      child: CircularProgressIndicator(color: p.on(C.blue)),
                    ),
                  ],
                  if (_note != null && _note!.isNotEmpty) ...[
                    const SizedBox(height: S.x5),
                    StatusCard(
                      _noteFailed
                          ? (l?.dataThatDidNotWork ?? 'That did not work')
                          : (l?.actionDone ?? 'Done'),
                      _note!,
                      icon: _noteFailed
                          ? LucideIcons.triangleAlert
                          : LucideIcons.check,
                    ),
                  ],
                  if (app.importRollupError != null) ...[
                    const SizedBox(height: S.x5),
                    StatusCard(
                      l?.welcomeSummariesDidNotTitle ??
                          'The days landed, the summaries did not',
                      l?.dataSummariesDidNotBodyShort(
                            '${app.importRollupError}',
                          ) ??
                          'Every imported row is in the database, but rebuilding the '
                              'cross-day summaries over them threw '
                              '(${app.importRollupError}), so trends and insights '
                              'still describe the data you had before.',
                      fix:
                          l?.dataReanalyzeEverything ?? 'Re-analyze everything',
                      icon: LucideIcons.triangleAlert,
                      onFix: _busy ? null : () => _run(() => _reanalyze(app)),
                    ),
                  ],
                  // The onboarding report, not a second copy of it. This
                  // screen used to render its own paraphrase, which had already
                  // drifted: it lost the rollup error entirely and stated the
                  // loss counts in one run-on sentence.
                  if (o != null) ...[
                    const SizedBox(height: S.x5),
                    ImportReport(o),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Production composition for the reduced Data screen. Gallery and widget
/// tests inject bounded callbacks; this view never opens a database or plugin.
class DataScreenView extends StatelessWidget {
  final BackupCadence cadence;
  final DateTime? lastBackupAt;
  final bool busy, noteFailed, reanalyzing;
  final String? note, importRollupError, reanalyzeProgress;
  final ImportOutcome? outcome;
  final Widget? rebuilt;
  final VoidCallback? onExportDatabase,
      onExportEncrypted,
      onExportCsv,
      onCadence,
      onBackupNow,
      onImport,
      onReanalyze;
  final ValueChanged<bool>? onAutomatic;

  const DataScreenView({
    super.key,
    this.cadence = BackupCadence.off,
    this.lastBackupAt,
    this.busy = false,
    this.noteFailed = false,
    this.reanalyzing = false,
    this.note,
    this.importRollupError,
    this.reanalyzeProgress,
    this.outcome,
    this.rebuilt,
    this.onExportDatabase,
    this.onExportEncrypted,
    this.onExportCsv,
    this.onCadence,
    this.onAutomatic,
    this.onBackupNow,
    this.onImport,
    this.onReanalyze,
  });

  @override
  Widget build(BuildContext c) {
    final p = OB.of(c);
    final l = AppLocalizations.of(c);
    final de = Localizations.localeOf(c).languageCode == 'de';
    return Scaffold(
      key: const ValueKey('data-screen'),
      backgroundColor: p.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OBPageHeader(
                title: de ? 'Daten & Sicherung' : 'Data & backup',
                subtitle: '',
                backText: de ? 'Profil' : 'Profile',
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                children: [
                  if (rebuilt != null) ...[
                    rebuilt!,
                    const SizedBox(height: 12),
                  ],
                  _sectionLabel(p, de ? 'Sicherung' : 'Backup'),
                  OBCard(
                    child: Column(
                      children: [
                        Pressable(
                          key: const ValueKey('data-backup-cadence'),
                          onTap: onAutomatic == null
                              ? onCadence
                              : () =>
                                    onAutomatic!(cadence == BackupCadence.off),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        de
                                            ? 'Automatisch sichern'
                                            : 'Automatic backup',
                                        style: p.text(
                                          15,
                                          weight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        de
                                            ? 'Unverschlüsselt · $kBackupsKept lokale Kopien'
                                            : 'Unencrypted · $kBackupsKept local copies',
                                        style: p.text(12, color: p.muted),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch.adaptive(
                                  value: cadence != BackupCadence.off,
                                  onChanged:
                                      onAutomatic ??
                                      (onCadence == null
                                          ? null
                                          : (_) => onCadence!()),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Divider(color: p.line, height: 1),
                        _paperRow(
                          p,
                          de ? 'Letzte Sicherung' : 'Last backup',
                          value: lastBackupAt == null
                              ? '—'
                              : _stamp(lastBackupAt!),
                          key: const ValueKey('data-last-backup'),
                        ),
                        Divider(color: p.line, height: 1),
                        _paperRow(
                          p,
                          de
                              ? 'Sicherung jetzt erstellen'
                              : 'Create backup now',
                          key: const ValueKey('data-backup-now'),
                          onTap: onBackupNow,
                        ),
                      ],
                    ),
                  ),
                  _sectionLabel(p, 'Export'),
                  OBCard(
                    child: Column(
                      children: [
                        _paperRow(
                          p,
                          de ? 'Datenbank exportieren' : 'Export database',
                          sub:
                              '.db · ${de ? 'unverschlüsselt' : 'unencrypted'}',
                          key: const ValueKey('data-export-database'),
                          onTap: onExportDatabase,
                        ),
                        Divider(color: p.line, height: 1),
                        _paperRow(
                          p,
                          de ? 'Verschlüsselt exportieren' : 'Export encrypted',
                          sub: de ? 'Mit Passwort' : 'With password',
                          key: const ValueKey('data-export-encrypted'),
                          onTap: onExportEncrypted,
                        ),
                        Divider(color: p.line, height: 1),
                        _paperRow(
                          p,
                          de ? 'CSV exportieren' : 'Export CSV',
                          sub: de
                              ? 'Messwerte · keine vollständige Sicherung'
                              : 'Measurements · not a complete backup',
                          key: const ValueKey('data-export-csv'),
                          onTap: onExportCsv,
                        ),
                      ],
                    ),
                  ),
                  _sectionLabel(p, de ? 'Werkzeuge' : 'Tools'),
                  Row(
                    children: [
                      Expanded(
                        child: _toolCard(
                          p,
                          LucideIcons.upload,
                          de ? 'Datei importieren' : 'Import file',
                          key: const ValueKey('data-import-file'),
                          onTap: onImport,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _toolCard(
                          p,
                          LucideIcons.refreshCcw,
                          de ? 'Neu berechnen' : 'Recalculate',
                          key: const ValueKey('data-reanalyze'),
                          onTap: reanalyzing ? null : onReanalyze,
                        ),
                      ),
                    ],
                  ),
                  if (reanalyzeProgress != null)
                    Text(reanalyzeProgress!, style: p.text(12, color: p.muted)),
                  if (busy) ...[
                    const SizedBox(height: 20),
                    Center(child: CircularProgressIndicator(color: p.action)),
                  ],
                  if (note != null && note!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    StatusCard(
                      noteFailed
                          ? (l?.dataThatDidNotWork ??
                                (de
                                    ? 'Das hat nicht geklappt'
                                    : 'That did not work'))
                          : (l?.actionDone ?? (de ? 'Erledigt' : 'Done')),
                      note!,
                      key: const ValueKey('data-action-receipt'),
                      icon: noteFailed
                          ? LucideIcons.triangleAlert
                          : LucideIcons.check,
                    ),
                  ],
                  if (importRollupError != null) ...[
                    const SizedBox(height: 12),
                    StatusCard(
                      l?.welcomeSummariesDidNotTitle ??
                          'The days landed, the summaries did not',
                      l?.dataSummariesDidNotBodyShort(importRollupError!) ??
                          'Imported rows were stored, but summaries could not be rebuilt.',
                      icon: LucideIcons.triangleAlert,
                      onFix: onReanalyze,
                      fix:
                          l?.dataReanalyzeEverything ?? 'Re-analyze everything',
                    ),
                  ],
                  if (outcome != null) ...[
                    const SizedBox(height: 12),
                    ImportReport(outcome!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(OB p, String label) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 0, 8),
    child: Text(label.toUpperCase(), style: p.label(size: 11)),
  );

  Widget _paperRow(
    OB p,
    String title, {
    String? sub,
    String? value,
    Key? key,
    VoidCallback? onTap,
  }) => Pressable(
    key: key,
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 50),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: p.text(15, weight: FontWeight.w600)),
                  if (sub != null) Text(sub, style: p.text(12, color: p.muted)),
                ],
              ),
            ),
            if (value != null)
              Flexible(
                child: Text(value, style: p.text(14, color: p.muted)),
              ),
            if (onTap != null) ...[
              const SizedBox(width: 10),
              Text('›', style: p.text(17, color: p.gap)),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _toolCard(
    OB p,
    IconData icon,
    String title, {
    Key? key,
    VoidCallback? onTap,
  }) => Pressable(
    key: key,
    onTap: onTap,
    child: OBCard(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: p.ink),
            const SizedBox(height: 12),
            Text(title, style: p.text(15, weight: FontWeight.w600)),
          ],
        ),
      ),
    ),
  );
}

String _exportCreated(BuildContext c) =>
    Localizations.localeOf(c).languageCode == 'de'
    ? 'Export erstellt'
    : 'Export created';

/// Off → Daily → Weekly → Off. Three states cycle in a row; a picker for three
/// options is a sheet nobody needs.
BackupCadence _nextCadence(BackupCadence c) =>
    BackupCadence.values[(c.index + 1) % BackupCadence.values.length];

String _stamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}
