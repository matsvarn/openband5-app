// Step one of onboarding.
//
// Two things happen here and they are deliberately equal in weight: setting up
// a band, and bringing your history with you. Import is not a settings page
// you find six months later — a health app that starts at zero on day one is
// a health app you delete on day three.
//
// An import that silently drops rows is worse than one that refuses them, so
// [ImportOutcome] carries what the source cost us and [WelcomeView] renders it.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../import/backup_crypto.dart';
import '../../import/import_container.dart';
import '../../import/journal_csv_import.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../../openband/alp_tokens.dart';
import '../../openband/theme.dart';
import '../ui2.dart';
import 'pairing.dart' show OnboardingBypass;

/// What an import actually achieved, including what it could NOT use.
class ImportOutcome {
  final String source;
  final int days;

  /// Sessions written. A vendor export whose workouts CSV is the only file
  /// selected lands 60 of these and 0 days, and reporting only the days made
  /// that read as an import that did nothing.
  final int workouts;

  /// Days present in the source that were NOT written because this device
  /// already holds a measured day for that date. Never overwritten, and never
  /// silently dropped from the report either.
  final int skippedDays;

  /// Rows whose day had already been derived and pruned before they arrived.
  final int lateRows;

  /// Dates the source presented out of order — folded in as context for the
  /// following day, but never derived in their own right.
  final int strandedDays;

  /// Source tables SQLite reported as corrupt while reading a `.noopbak`
  /// (unreadable pages, not a schema mismatch — see `_isCorruptPageError`).
  /// Every OTHER table still imported; this only names what could not be
  /// read, so a heart-rate stream that came back empty doesn't read as a
  /// complete one.
  final Set<String> corruptTables;

  /// Journal days written by the hand-entered CSV path (csv-reimport). Its own
  /// counter: those rows REPLACE the journal for the dates they name, which is
  /// a different promise from "a day the band measured is never overwritten",
  /// and folding them into [days] would hide that.
  final int journalRows;

  /// Journal CSV lines that were REJECTED, never clamped — "line 12: note is
  /// 40122 characters". Shown up to a cap, because a validation the user
  /// cannot see is a silent drop.
  final List<String> rejectedRows;

  final String? error;

  /// The rows landed and the cross-day rebuild over them threw. Not an error:
  /// the data is in the database, the summaries built from it are not.
  final String? rollupError;

  /// Part of a mixed selection could not be read while the rest imported.
  final String? readError;

  /// Accepted `manual_vo2` revision rows. Not days, and not entry ids.
  final int vo2Revisions;

  /// Entry ids left untouched because the local chain diverged.
  final int vo2ConflictIds;

  /// Entry ids left untouched because the source chain could not be read.
  final int vo2CorruptIds;

  /// True when at least one source file had a `manual_vo2` table. An old
  /// backup that lacks the table is false, which is different from a present
  /// table whose counts are zero.
  final bool vo2TablePresent;

  /// Durable backup rows handled by the preserve-local restore path.
  final int restoredRows;
  final int unchangedRows;
  final int restoreConflicts;
  final int unreadableRows;
  final int pendingRecalculations;

  const ImportOutcome({
    required this.source,
    this.days = 0,
    this.workouts = 0,
    this.skippedDays = 0,
    this.lateRows = 0,
    this.strandedDays = 0,
    this.corruptTables = const {},
    this.journalRows = 0,
    this.rejectedRows = const [],
    this.error,
    this.rollupError,
    this.readError,
    this.vo2Revisions = 0,
    this.vo2ConflictIds = 0,
    this.vo2CorruptIds = 0,
    this.vo2TablePresent = false,
    this.restoredRows = 0,
    this.unchangedRows = 0,
    this.restoreConflicts = 0,
    this.unreadableRows = 0,
    this.pendingRecalculations = 0,
  });

  bool get lostSomething =>
      lateRows > 0 || strandedDays > 0 || corruptTables.isNotEmpty;

  /// Nothing at all landed. A zero under a green tick is a no-op that reads as
  /// a success, which is the one thing an import report must never do.
  /// Accepted VO2 revisions count. A backup that only carried those still
  /// brought history in.
  bool get nothingLanded =>
      days == 0 &&
      workouts == 0 &&
      skippedDays == 0 &&
      journalRows == 0 &&
      vo2Revisions == 0 &&
      restoredRows == 0;
}

/// Raised when an encrypted backup was picked and the user closed the
/// passphrase prompt. Not a failure to report as one — they cancelled.
class PassphraseCancelled implements Exception {}

/// Shortest passphrase we will write a file with. Not a policy for its own
/// sake: PBKDF2 buys time against a guess, and four characters is guessed
/// before the derivation finishes no matter how many iterations it runs.
const int kMinPassphraseChars = 8;

/// Ask for the passphrase. Null when the user closed it.
///
/// [creating] switches this between the two halves of the same promise.
/// Writing a file asks twice and says out loud that a forgotten passphrase is
/// the end of that backup; opening one asks once. There is deliberately NO
/// hint field and NO recovery code: both would make it feel safer while being
/// the thing that lets someone else open the file.
Future<String?> askBackupPassphrase(BuildContext c, {bool creating = false}) =>
    showDialog<String>(
      context: c,
      builder: (_) => _PassphraseDialog(creating: creating),
    );

class _PassphraseDialog extends StatefulWidget {
  const _PassphraseDialog({required this.creating});
  final bool creating;

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _submit() {
    final l = AppLocalizations.of(context);
    final v = _a.text;
    if (widget.creating) {
      if (v.length < kMinPassphraseChars) {
        setState(
          () => _error =
              l?.welcomePassphraseTooShort(kMinPassphraseChars) ??
              'At least $kMinPassphraseChars characters.',
        );
        return;
      }
      if (v != _b.text) {
        setState(
          () =>
              _error = l?.welcomePassphraseMismatch ?? 'The two do not match.',
        );
        return;
      }
    } else if (v.isEmpty) {
      setState(
        () => _error = l?.welcomePassphraseEmpty ?? 'Enter the passphrase.',
      );
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext c) {
    final creating = widget.creating;
    final l = AppLocalizations.of(c);
    return AlertDialog(
      title: Text(
        creating
            ? (l?.welcomeChoosePassphrase ?? 'Choose a passphrase')
            : (l?.welcomePassphrase ?? 'Passphrase'),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            creating
                // Both halves, in the same breath. The second half is not a
                // warning bolted onto a feature — it IS the feature: nothing can
                // open this file without the passphrase, including us, because
                // there is no account and no server holding a key.
                ? (l?.welcomePassphraseCreateNote ??
                      'The file is unreadable without it. And a forgotten passphrase '
                          'means that backup is gone — there is no recovery, because '
                          'there is no account and no server holding a key. That is the '
                          'same thing that keeps it private.')
                : (l?.welcomePassphraseOpenNote ??
                      'The one you chose when this backup was written.'),
          ),
          const SizedBox(height: S.x4),
          TextField(
            controller: _a,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l?.welcomePassphrase ?? 'Passphrase',
            ),
            onSubmitted: creating ? null : (_) => _submit(),
          ),
          if (creating) ...[
            const SizedBox(height: S.x3),
            TextField(
              controller: _b,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l?.welcomeRepeatIt ?? 'Repeat it',
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: S.x3),
            Text(_error!, style: F.cap.copyWith(color: P.of(c).on(C.red))),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(c).pop(),
          child: Text(l?.actionCancel ?? 'Cancel'),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(
            creating
                ? (l?.welcomeEncrypt ?? 'Encrypt')
                : (l?.welcomeUnlock ?? 'Unlock'),
          ),
        ),
      ],
    );
  }
}

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _busy = false;
  ImportOutcome? _outcome;

  Future<void> _import() async {
    final app = context.read<AppState>();
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withReadStream: false,
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => _outcome = ImportOutcome(source: 'File picker', error: '$e'),
        );
      }
      return;
    }
    final paths = (picked?.files ?? const [])
        .map((f) => f.path)
        .whereType<String>()
        .toList();
    if (paths.isEmpty) return; // cancelled — not a failure, say nothing

    setState(() {
      _busy = true;
      _outcome = null;
    });
    try {
      final outcome = await runImport(
        app,
        paths,
        askPassphrase: () => askBackupPassphrase(context),
      );
      if (!mounted) return;
      setState(() => _outcome = outcome);
      // Anything that landed counts as bringing history in — a workouts-only
      // vendor export writes sessions and no days, and the gate used to sit
      // there as though the import had not happened.
      if (!outcome.nothingLanded) await app.completeImportOnboard();
    } on PassphraseCancelled {
      // Closing the prompt is a decision, not a failure. Say nothing.
    } catch (e) {
      if (mounted) {
        setState(() => _outcome = ImportOutcome(source: 'Import', error: '$e'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => WelcomeView(
    busy: _busy,
    outcome: _outcome,
    onNew: () => context.read<AppState>().chooseNewUser(),
    onImport: _import,
    onSkip: () => OnboardingBypass.mark(OnboardingBypass.kPairing),
  );
}

/// Route [paths] to the importer that understands them and normalise the
/// result. Pure enough to test: the only collaborator is [AppState]'s import
/// surface.
Future<ImportOutcome> runImport(
  AppState app,
  List<String> paths, {
  Future<String?> Function()? askPassphrase,
  @visibleForTesting
  Future<JournalImportResult> Function(String path)? debugReadJournal,
}) async {
  final readJournal = debugReadJournal ?? importJournalCsvFile;
  // An encrypted backup is identified by its MAGIC, not its extension: it comes
  // back off iCloud Drive or a mail attachment with whatever name that round
  // trip gave it, and routing a ciphertext into the vendor-CSV importer would
  // report "nothing in it this app could use" for a file that is the user's
  // entire history.
  final decrypted = <String>[];
  final sources = <String>[];
  var days = 0, workouts = 0, skipped = 0, late = 0, stranded = 0;
  var journalRows = 0;
  var vo2Revisions = 0, vo2Conflicts = 0, vo2Corrupt = 0;
  var restoredRows = 0, unchangedRows = 0, restoreConflicts = 0;
  var unreadableRows = 0, pendingRecalculations = 0;
  var vo2TablePresent = false;
  final corruptTables = <String>{};
  final rejected = <String>[];
  String? rollupError;
  String? cryptoError;

  final plain = <String>[];
  for (final p in paths) {
    if (!await isEncryptedBackup(p)) {
      plain.add(p);
      continue;
    }
    if (askPassphrase == null) {
      cryptoError =
          'That file is an encrypted backup. Open it from '
          'Settings → Your data, where the passphrase can be asked for.';
      continue;
    }
    final pass = await askPassphrase();
    if (pass == null) {
      // Shred here, not in the `finally` below. The picker is multi-select, so
      // an EARLIER encrypted file in the same selection may already be sitting
      // in the temp directory as the whole health record in plaintext — and
      // this throw jumps past the try/finally that would normally delete it,
      // because that try has not been entered yet. Cancelling the second
      // passphrase prompt used to leave the first backup decrypted on disk.
      for (final d in decrypted) {
        try {
          await File(d).delete();
        } catch (_) {}
      }
      throw PassphraseCancelled();
    }
    try {
      decrypted.add(await decryptToTemp(p, pass));
    } on BackupFormatException catch (e) {
      // ONE message for a wrong passphrase and a tampered file, because GCM
      // cannot tell them apart and pretending otherwise would be a guess.
      cryptoError = e.message;
    }
  }

  // EVERY group runs, not the first one that matches. The picker is
  // multi-select and this used to return inside the winning branch, so a
  // backup selected alongside a vendor CSV imported the backup and threw the
  // CSV away without a word.
  final db = [...plain.where(_isDbBackup), ...decrypted];
  // Raw-vs-vendor is decided by what the file HOLDS, not by what it is called.
  // See [isNoopExport]: routing on the extension sent NOOP's raw-sensor `.csv`
  // to the vendor importer and WHOOP's `.zip` to the NOOP one — both files
  // fine, both refused, both with advice for the other file.
  final raw = <String>[];
  final csv = <String>[];
  for (final p in plain) {
    if (_isDbBackup(p)) continue;
    (await isNoopExport(p) ? raw : csv).add(p);
  }

  if (decrypted.isNotEmpty) sources.add('Encrypted backup');
  if (plain.any(_isDbBackup)) sources.add('OpenStrap backup');
  final backupFailures = <Object>[];
  var backupsRead = 0;
  try {
    for (final p in db) {
      try {
        final receipt = await app.importEdgeBackup(p);
        backupsRead++;
        days += receipt.days;
        if (receipt.vo2TablePresent) {
          vo2TablePresent = true;
          vo2Revisions += receipt.insertedRevisions;
          vo2Conflicts += receipt.conflictIds;
          vo2Corrupt += receipt.corruptIds;
        }
        restoredRows += receipt.restoredRows;
        unchangedRows += receipt.unchangedRows;
        restoreConflicts += receipt.restoreConflicts;
        unreadableRows += receipt.unreadableRows;
        pendingRecalculations += receipt.pendingRecalculations;
        // The rows are in and the rollup rebuild threw. The receipt is the
        // backup result. A later file must not wipe an earlier failure.
        rollupError ??= receipt.recalculationError;
        if (receipt.readError != null) backupFailures.add(receipt.readError!);
      } catch (e) {
        // A later file that cannot be read must not discard a backup that
        // already committed, and must not skip the files after it.
        backupFailures.add(e);
      }
    }
  } finally {
    // The decrypted copy is the whole health record in plaintext. It exists
    // for the length of one import and no longer — leaving it in the temp
    // directory would undo the reason the backup was encrypted.
    for (final p in decrypted) {
      try {
        await File(p).delete();
      } catch (_) {}
    }
  }
  var rawRead = 0;
  if (raw.isNotEmpty) {
    sources.add('Raw sensor export');
    for (final p in raw) {
      try {
        days += await app.importNoopCsv(p);
        rawRead++;
        final r = app.lastNoopImport;
        if (r != null) {
          late += r.lateRows;
          stranded += r.strandedDates.length;
          corruptTables.addAll(r.corruptTables);
        }
      } catch (e) {
        // The call did not return a day count. Do not read [lastNoopImport]:
        // that would re-count an earlier file, or rows this attempt did not
        // finish proving.
        backupFailures.add(e);
      }
    }
  }
  // csv-reimport: OUR OWN journal export, coming back after a spreadsheet edit.
  // Routed on the header signature rather than the filename — `parseJournalCsv`
  // reads and validates the whole file before a single row is written, so a
  // file that is not one throws without touching the database and falls
  // through to the vendor importer below.
  final vendor = <String>[];
  var journalRead = 0;
  for (final p in csv) {
    // Only a TEXT file can be a journal export, and `importJournalCsvFile`
    // reads it as a string. Vendor exports arrive here as ZIPs now that routing
    // is by content, and reading one as a string is #199 all over again — it
    // comes back as `FileSystemException: Failed to decode data using encoding
    // 'utf-8'`, which no catch below was going to turn into advice. The vendor
    // path unwraps archives (and gzip) properly, so hand them straight over.
    final ImportContainer kind;
    try {
      kind = await sniffFile(p);
    } catch (e) {
      backupFailures.add(e);
      continue;
    }
    if (kind != ImportContainer.text) {
      vendor.add(p);
      continue;
    }
    try {
      final r = await readJournal(p);
      journalRows += r.imported;
      journalRead++;
      // This one writes straight to the journal store rather than through
      // AppState, so it has to raise the signal itself — every other importer
      // here does it from its AppState method.
      if (r.imported > 0) app.bumpInsights();
      rejected.addAll(r.rejected.map((x) => x.toString()));
      if (!sources.contains('Journal CSV')) sources.add('Journal CSV');
    } on JournalCsvFormatException {
      vendor.add(p);
    } on FormatException {
      // Text, but not UTF-8 — a latin1/cp1252 CSV out of a spreadsheet. The
      // sniff above cannot see that, and the vendor importer decodes leniently.
      vendor.add(p);
    } catch (e) {
      backupFailures.add(e);
    }
  }

  String? readError;
  var vendorRead = 0;
  if (vendor.isNotEmpty) {
    // The catch-all group: anything that is not a backup or a raw export is
    // handed to the vendor importer, so it is also where junk in a mixed
    // selection lands.
    try {
      days += await app.importWhoopCsvs(vendor);
      vendorRead++;
      sources.add('Vendor CSV export');
      final r = app.lastWhoopImport;
      if (r != null) {
        workouts += r.workouts;
        skipped += r.skippedExistingDays;
      }
    } catch (e) {
      backupFailures.add(e);
    }
  }

  // Every selected source failed: still an error, not an empty success.
  // A backup that already returned its receipt is kept, and the later failure
  // is named beside it.
  final landed =
      backupsRead > 0 || rawRead > 0 || journalRead > 0 || vendorRead > 0;
  if (backupFailures.isNotEmpty && !landed && cryptoError == null) {
    if (backupFailures.length == 1) throw backupFailures.first;
    throw FileSystemException(backupFailures.map((e) => '$e').join('\n'));
  }
  if (backupFailures.isNotEmpty) {
    readError = backupFailures.map((e) => '$e').join('\n');
  }

  return ImportOutcome(
    source: sources.isEmpty ? 'Nothing selected' : sources.join(' + '),
    days: days,
    workouts: workouts,
    skippedDays: skipped,
    lateRows: late,
    strandedDays: stranded,
    corruptTables: corruptTables,
    journalRows: journalRows,
    rejectedRows: rejected,
    rollupError: rollupError,
    vo2Revisions: vo2Revisions,
    vo2ConflictIds: vo2Conflicts,
    vo2CorruptIds: vo2Corrupt,
    vo2TablePresent: vo2TablePresent,
    restoredRows: restoredRows,
    unchangedRows: unchangedRows,
    restoreConflicts: restoreConflicts,
    unreadableRows: unreadableRows,
    pendingRecalculations: pendingRecalculations,
    // A file that would not decrypt is reported the same way a file that would
    // not parse is: named, alongside whatever else did land.
    readError: readError ?? cryptoError,
  );
}

/// True when [path] starts with the encrypted-backup magic. Four bytes, so a
/// mis-picked file costs one read and not a key derivation.
Future<bool> isEncryptedBackup(String path) async {
  try {
    final raf = await File(path).open();
    try {
      return _sameBytes(await raf.read(kBackupMagic.length), kBackupMagic);
    } finally {
      await raf.close();
    }
  } catch (_) {
    return false;
  }
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Decrypt [path] into the temp directory and return the plaintext path.
///
/// PBKDF2 at 210 000 iterations is a multi-second block by design, so it runs
/// on a worker isolate — on the UI isolate it is a frozen app that looks
/// crashed. Nothing here touches a plugin, which is what makes that legal.
Future<String> decryptToTemp(String path, String passphrase) async {
  final tmp = await getTemporaryDirectory();
  final dest =
      '${tmp.path}/restore-${DateTime.now().millisecondsSinceEpoch}.db';
  await Isolate.run(
    () => decryptBackupFile(File(path), File(dest), passphrase),
  );
  return dest;
}

bool _isDbBackup(String path) {
  final p = path.toLowerCase();
  // `.db.unopenable-<ms>` is what a corrupt-database rebuild quarantines the
  // old file as, and the rebuilt card points the user straight at it. Matching
  // only the `.db` suffix handed that SQLite file to the vendor-CSV importer.
  // `.db.gz` is what the app's own automatic backup writes (auto_backup.dart's
  // kBackupExtension). Leaving it out sent a user restoring their own backup
  // down the vendor-CSV path, which is the one import that has to work.
  return p.endsWith('.db') ||
      p.endsWith('.db.gz') ||
      p.contains('.db.unopenable-');
}

class WelcomeView extends StatelessWidget {
  final bool busy;
  final ImportOutcome? outcome;
  final VoidCallback onNew;
  final VoidCallback onImport;
  final VoidCallback? onSkip;

  const WelcomeView({
    super.key,
    required this.onNew,
    required this.onImport,
    this.busy = false,
    this.outcome,
    this.onSkip,
  });

  @override
  Widget build(BuildContext c) {
    final p = OB.of(c);
    final l = AppLocalizations.of(c);
    final o = outcome;
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 32, 16, 32),
          children: [
            Icon(LucideIcons.activity, size: 40, color: p.action),
            const SizedBox(height: 20),
            Text(
              l?.welcomeHeadline ?? 'Your band, decoded here',
              style: p.text(30, weight: FontWeight.w800, display: true),
            ),
            const SizedBox(height: 12),
            Text(
              l?.welcomeSubhead ??
                  'Every number is computed on this phone from the raw signal.',
              style: p.text(15, color: p.muted),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: p.recoveryTint,
                      borderRadius: BorderRadius.circular(AlpRadius.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.shieldCheck,
                          size: 14,
                          color: p.recoveryText,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            l?.pillLocalNoCloud ?? 'Local · no cloud',
                            style: p.text(
                              13,
                              weight: FontWeight.w600,
                              color: p.recoveryText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            OBAction(
              l?.welcomeSetUpMyBand ?? 'Band verbinden',
              onPressed: busy ? null : onNew,
            ),
            const SizedBox(height: 12),
            OBAction(
              busy
                  ? (l?.welcomeImporting ?? 'Importing…')
                  : (l?.welcomeBringMyHistoryFirst ?? 'Daten importieren'),
              secondary: true,
              onPressed: busy ? null : onImport,
            ),
            if (onSkip != null) ...[
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: busy ? null : onSkip,
                  child: Text(
                    'Später verbinden',
                    style: p.text(14, weight: FontWeight.w500, color: p.muted),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              // Was: "imported days are marked as imported — they are never
              // mixed into days this app measured itself". There is no source
              // column on day_result or metric_series, two of the four
              // importers write no marker at all, and imported values do feed
              // the same rolling baselines. What IS true is the half that
              // protects data: no import overwrites a day this band measured.
              l?.welcomeImportFooterNote ??
                  'Raw sensor exports, an OpenStrap backup (encrypted or not), '
                      'or a vendor CSV. '
                      'Imported days sit alongside days this app measured and feed '
                      'the same baselines — but a day the band already measured is '
                      'never overwritten.',
              style: p.text(13, color: p.muted),
            ),
            if (busy) ...[
              const SizedBox(height: 24),
              Center(child: CircularProgressIndicator(color: p.action)),
            ],
            if (o != null) ...[const SizedBox(height: 24), ImportReport(o)],
          ],
        ),
      ),
    );
  }
}

/// What the import got, and what it could not use. The second half is the
/// point — "imported 412 days" beside a silently dropped fortnight is a lie
/// of omission.
class ImportReport extends StatelessWidget {
  final ImportOutcome o;
  const ImportReport(this.o, {super.key});

  @override
  Widget build(BuildContext c) {
    final p = OB.of(c);
    final l = AppLocalizations.of(c);
    if (o.error != null) {
      final source = _sourceLabel(l);
      return OBNoticeCard(
        l?.welcomeSourceCouldNotBeRead(source) ?? '$source could not be read',
        o.error!,
        fix: l?.actionTryAnotherFile ?? 'Try another file',
        icon: LucideIcons.triangleAlert,
      );
    }
    final showLegacy =
        o.days > 0 ||
        o.journalRows > 0 ||
        o.workouts > 0 ||
        o.skippedDays > 0;
    final vo2 = _vo2Cards(p, l);
    final showRestore = o.restoredRows > 0 ||
        o.unchangedRows > 0 ||
        o.restoreConflicts > 0 ||
        o.unreadableRows > 0 ||
        o.pendingRecalculations > 0;
    if (o.readError != null && !showLegacy && vo2.isEmpty && !showRestore) {
      return _incompleteRead(l);
    }
    // A zero is not a success. Same tick, same words, nothing in the database.
    // A present VO2 table still has something to say when nothing else landed:
    // no new changes, or the ids that were not imported.
    if (!showLegacy && vo2.isEmpty && !showRestore) {
      return OBNoticeCard(
        l?.welcomeNothingWasImported ?? 'Nothing was imported',
        // Every row refused is its own answer to "why is it empty?", and it
        // has to survive the empty case or the validation is invisible.
        o.rejectedRows.isNotEmpty
            ? (l?.welcomeEveryRowRefused(_rejects(o)) ??
                  'Every row was refused: ${_rejects(o)}')
            : o.readError ??
                  (l?.welcomeNothingUsableInFile ??
                      'The file was read but there was nothing in it this app could '
                          'use, or every day in it was one this band had already '
                          'measured.'),
        fix: l?.actionTryAnotherFile ?? 'Try another file',
        icon: LucideIcons.fileWarning,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showLegacy) _legacyCard(p, l),
        if (showRestore) ...[
          if (showLegacy) const SizedBox(height: 12),
          _restoreCard(p, l, Localizations.localeOf(c).languageCode == 'de'),
        ],
        if (vo2.isNotEmpty) ...[
          if (showLegacy || showRestore) const SizedBox(height: 12),
          ...vo2,
        ],
        // REJECTED, never clamped. A row outside its declared range is not
        // salvageable by trimming it — that would store a value the user never
        // wrote — so it is refused by line number and the other 300 land.
        if (o.rejectedRows.isNotEmpty) ...[
          const SizedBox(height: 12),
          OBNoticeCard(
            l?.welcomeRowsRefused(o.rejectedRows.length) ??
                '${o.rejectedRows.length} '
                    'row${o.rejectedRows.length == 1 ? ' was' : 's were'} refused',
            l?.welcomeRejectedDetail(_rejects(o)) ??
                '${_rejects(o)} Nothing was trimmed to fit — fix those lines and '
                    'import again.',
            icon: LucideIcons.fileWarning,
          ),
        ],
        if (o.readError != null) ...[
          const SizedBox(height: 12),
          _incompleteRead(l),
        ],
        if (o.rollupError != null) ...[
          const SizedBox(height: 12),
          OBNoticeCard(
            l?.welcomeSummariesDidNotTitle ??
                'The days landed, the summaries did not',
            l?.welcomeSummariesDidNotBody('${o.rollupError}') ??
                'Every imported row is in the database, but rebuilding the cross-day '
                    'summaries over them threw (${o.rollupError}), so trends and '
                    'insights still describe the data you had before. Re-analyze '
                    'everything from Your data rebuilds them.',
            icon: LucideIcons.triangleAlert,
          ),
        ],
        if (o.lostSomething) ...[
          const SizedBox(height: 12),
          OBNoticeCard(
            l?.welcomePartOfFileNotUsedTitle ??
                'Part of that file could not be used',
            [
              if (o.strandedDays > 0)
                l?.welcomeStrandedDays(o.strandedDays) ??
                    '${o.strandedDays} day${o.strandedDays == 1 ? '' : 's'} arrived '
                        'out of order and were only used as context for the day '
                        'that followed.',
              if (o.lateRows > 0)
                l?.welcomeLateRows(o.lateRows) ??
                    '${o.lateRows} row${o.lateRows == 1 ? '' : 's'} arrived after '
                        'their day had already been scored and closed.',
              if (o.corruptTables.isNotEmpty)
                '${o.corruptTables.join(', ')} could not be read — SQLite '
                    'reported the file itself as corrupted for those tables. '
                    'Every other table imported normally.',
            ].join(' '),
            fix: o.corruptTables.isNotEmpty
                ? (l?.actionTryAnotherFile ?? 'Try another file')
                : (l?.welcomeExportAgainInDateOrder ??
                      'Export again in date order'),
            icon: LucideIcons.fileWarning,
          ),
        ],
      ],
    );
  }

  Widget _legacyCard(OB p, AppLocalizations? l) {
    final workouts =
        l?.welcomeWorkoutsCount(o.workouts) ??
        '${o.workouts} workout${o.workouts == 1 ? '' : 's'}';
    final skipped =
        l?.welcomeDaysAlreadyMeasured(o.skippedDays) ??
        '${o.skippedDays} day${o.skippedDays == 1 ? '' : 's'} already measured '
            'here and left alone';
    // A journal CSV writes no days, so the old headline read "0 days imported"
    // over a successful import of 300 notes. A workouts-only file then fell
    // through to that same headline and read "0 journal days written".
    final String headline;
    var workoutInHeadline = false;
    var skippedInHeadline = false;
    if (o.days > 0) {
      headline =
          l?.welcomeDaysImported(o.days) ??
          '${o.days} day${o.days == 1 ? '' : 's'} imported';
    } else if (o.journalRows > 0) {
      headline =
          l?.welcomeJournalDaysWritten(o.journalRows) ??
          '${o.journalRows} journal '
              'day${o.journalRows == 1 ? '' : 's'} written';
    } else if (o.workouts > 0) {
      headline = workouts;
      workoutInHeadline = true;
    } else {
      headline = skipped;
      skippedInHeadline = true;
    }
    final also = [
      if (o.workouts > 0 && !workoutInHeadline) workouts,
      if (o.skippedDays > 0 && !skippedInHeadline) skipped,
    ];
    return OBCard(
      child: Row(
        children: [
          if (o.readError == null) ...[
            Icon(LucideIcons.check, size: 20, color: p.recovery),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(headline, style: p.text(15, weight: FontWeight.w600)),
                Text(_sourceLabel(l), style: p.text(12, color: p.muted)),
                if (also.isNotEmpty)
                  Text(also.join(' · '), style: p.text(12, color: p.muted)),
                if (o.days > 0 && o.journalRows > 0)
                  Text(
                    l?.welcomeJournalDaysReplaced(o.journalRows) ??
                        '${o.journalRows} journal '
                            'day${o.journalRows == 1 ? '' : 's'} replaced',
                    style: p.text(12, color: p.muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _restoreCard(OB p, AppLocalizations? l, bool de) {
    final withheld = o.restoreConflicts > 0 || o.unreadableRows > 0;
    final title = o.restoredRows > 0
        ? withheld
              ? (de ? 'Teilweise importiert' : 'Partially imported')
              : (de ? 'Importiert' : 'Imported')
        : withheld
        ? (de ? 'Nicht übernommen' : 'Not imported')
        : (de ? 'Unverändert' : 'Unchanged');
    String count(int n, String one, String many) => n == 1 ? one : '$n $many';
    final lines = <String>[
      if (o.restoredRows > 0)
        count(
          o.restoredRows,
          de ? '1 Eintrag gespeichert' : '1 entry saved',
          de ? 'Einträge gespeichert' : 'entries saved',
        ),
      if (o.unchangedRows > 0)
        count(
          o.unchangedRows,
          de ? '1 unverändert' : '1 unchanged',
          de ? 'unverändert' : 'unchanged',
        ),
      if (o.restoreConflicts > 0)
        count(
          o.restoreConflicts,
          de
              ? '1 Konflikt · lokal beibehalten'
              : '1 conflict · local version kept',
          de
              ? 'Konflikte · lokal beibehalten'
              : 'conflicts · local versions kept',
        ),
      if (o.unreadableRows > 0)
        count(
          o.unreadableRows,
          de ? '1 Eintrag nicht lesbar' : '1 entry unreadable',
          de ? 'Einträge nicht lesbar' : 'entries unreadable',
        ),
      if (o.pendingRecalculations > 0)
        count(
          o.pendingRecalculations,
          de
              ? '1 Neuberechnung ausstehend'
              : '1 recalculation pending',
          de
              ? 'Neuberechnungen ausstehend'
              : 'recalculations pending',
        ),
    ];
    return _primaryCard(
      p,
      l,
      title: title,
      body: [
        for (final line in lines)
          Text(line, style: _receiptLine(p, 15, 21)),
      ],
    );
  }

  List<Widget> _vo2Cards(OB p, AppLocalizations? l) {
    if (!o.vo2TablePresent) return const [];
    final accepted = o.vo2Revisions;
    final conflict = o.vo2ConflictIds;
    final corrupt = o.vo2CorruptIds;
    final withheld = conflict > 0 || corrupt > 0;
    final interrupted = o.readError != null;
    final lines = _withheldLines(p, l, conflict, corrupt);
    if (accepted == 0 && !withheld) {
      // An interrupted read is not "VO₂max unchanged".
      if (interrupted) return const [];
      return [
        _primaryCard(
          p,
          l,
          title: l?.welcomeVo2Unchanged ?? 'VO₂max unchanged',
          body: const [],
        ),
      ];
    }
    if (accepted == 0) {
      return [
        _primaryCard(
          p,
          l,
          title: l?.welcomeVo2NotImportedTitle ?? 'Not imported',
          body: lines,
          bodyGap: 4,
        ),
      ];
    }
    return [
      _primaryCard(
        p,
        l,
        title: withheld || interrupted
            ? (l?.welcomeVo2PartialTitle ?? 'Partially imported')
            : (l?.welcomeVo2ImportedTitle ?? 'Imported'),
        body: [
          Text(
            l?.welcomeVo2Accepted(accepted) ??
                (accepted == 1
                    ? '1 VO₂max change accepted'
                    : '$accepted VO₂max changes accepted'),
            style: _receiptLine(p, 15, 21),
          ),
        ],
      ),
      if (withheld) ...[
        const SizedBox(height: 12),
        OBCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l?.welcomeVo2NotImportedTitle ?? 'Not imported',
                style: _receiptLine(p, 14, 20, weight: FontWeight.w600),
              ),
              for (var i = 0; i < lines.length; i++) ...[
                SizedBox(height: i == 0 ? 8 : 4),
                lines[i],
              ],
            ],
          ),
        ),
      ],
    ];
  }

  Widget _incompleteRead(AppLocalizations? l) {
    return OBNoticeCard(
      l?.welcomeImportIncomplete ?? 'Import incomplete',
      o.readError!,
      icon: LucideIcons.fileWarning,
    );
  }

  String _sourceLabel(AppLocalizations? l) {
    return o.source
        .replaceAll(
          'Encrypted backup',
          l?.welcomeSourceEncrypted ?? 'Encrypted backup',
        )
        .replaceAll(
          'OpenStrap backup',
          l?.welcomeSourceOpenBand ?? 'OpenBand backup',
        );
  }

  Widget _primaryCard(
    OB p,
    AppLocalizations? l, {
    required String title,
    required List<Widget> body,
    double bodyGap = 0,
  }) {
    return OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: _receiptLine(p, 18, 24, weight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(_sourceLabel(l), style: _receiptLine(p, 13, 18, color: p.muted)),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (var i = 0; i < body.length; i++) ...[
              if (i > 0 && bodyGap > 0) SizedBox(height: bodyGap),
              body[i],
            ],
          ],
        ],
      ),
    );
  }

  List<Widget> _withheldLines(
    OB p,
    AppLocalizations? l,
    int conflict,
    int corrupt,
  ) {
    final style = _receiptLine(p, 14, 20);
    return [
      if (conflict > 0)
        Text(
          l?.welcomeVo2Conflicts(conflict) ??
              (conflict == 1
                  ? '1 VO₂max conflict'
                  : '$conflict VO₂max conflicts'),
          style: style,
        ),
      if (corrupt > 0)
        Text(
          l?.welcomeVo2Unreadable(corrupt) ??
              (corrupt == 1
                  ? '1 VO₂max entry unreadable'
                  : '$corrupt VO₂max entries unreadable'),
          style: style,
        ),
    ];
  }
}

TextStyle _receiptLine(
  OB p,
  double size,
  double linePx, {
  FontWeight weight = FontWeight.w400,
  Color? color,
}) {
  return p
      .text(size, weight: weight, color: color)
      .copyWith(height: linePx / size);
}

/// The first few refusals, with a count for the rest. Six is where a
/// StatusCard stops being read.
String _rejects(ImportOutcome o) {
  final shown = o.rejectedRows.take(6).join('; ');
  final more = o.rejectedRows.length - 6;
  return more > 0 ? '$shown; and $more more.' : '$shown.';
}
