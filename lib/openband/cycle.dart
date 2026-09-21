import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/day_label.dart';
import 'alp_tokens.dart';
import 'calendar.dart';
import 'confirm_sheet.dart';
import 'cycle_measurements.dart';
import 'cycle_observations.dart';
import 'domain.dart';
import 'journal_controls.dart';
import 'settings_controls.dart';
import 'theme.dart';
import 'undo_notice.dart';

const kCycleObservationTags = [
  'cramps',
  'headache',
  'bloating',
  'fatigue',
  'low mood',
  'acne',
  'tender breasts',
  'nausea',
];

const kCycleObservationLabels = {
  'cramps': 'Krämpfe',
  'headache': 'Kopfschmerzen',
  'bloating': 'Blähungen',
  'fatigue': 'Müdigkeit',
  'low mood': 'Stimmungstief',
  'acne': 'Akne',
  'tender breasts': 'Brustempfindlichkeit',
  'nausea': 'Übelkeit',
};

const _kInfoTitle = 'Zyklus';
const _kInfoBody =
    'Die Zeitschätzung nutzt den Median deiner eingetragenen Abstände. '
    'Die Spanne zeigt deren bisherige Streuung.\n\n'
    'Fehlende Einträge können die Schätzung verändern. '
    'Abstände über 60 Tage bleiben offen. Ein Eisprung wird nicht bestimmt.';

class OpenBandCycle extends StatefulWidget {
  final OpenBandRepository repository;
  final String day;
  final DateTime Function()? now;
  final bool synthetic;
  final bool settingsOnly;

  const OpenBandCycle({
    super.key,
    required this.repository,
    required this.day,
    this.now,
    this.synthetic = false,
    this.settingsOnly = false,
  });

  static Future<void> push(
    BuildContext context, {
    required OpenBandRepository repository,
    required String day,
    DateTime Function()? now,
    bool synthetic = false,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => OpenBandCycle(
          repository: repository,
          day: day,
          now: now,
          synthetic: synthetic,
        ),
      ),
    );
  }

  static Future<void> pushSettings(
    BuildContext context, {
    required OpenBandRepository repository,
    required String day,
    DateTime Function()? now,
    bool synthetic = false,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => OpenBandCycle(
          repository: repository,
          day: day,
          now: now,
          synthetic: synthetic,
          settingsOnly: true,
        ),
      ),
    );
  }

  @override
  State<OpenBandCycle> createState() => _OpenBandCycleState();
}

class _OpenBandCycleState extends State<OpenBandCycle> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  int _identity = 0;
  late String _day = widget.day;
  CycleSnapshot? _snapshot;
  bool _loading = true;
  bool _readError = false;
  String? _refreshError;
  CycleStart? _undoStart;
  bool _undoBusy = false;
  int _gen = 0;

  OpenBandRepository get _repo => widget.repository;
  DateTime _now() => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    if (!widget.settingsOnly) unawaited(_load());
  }

  @override
  void didUpdateWidget(OpenBandCycle oldWidget) {
    super.didUpdateWidget(oldWidget);
    final repoChanged = !identical(oldWidget.repository, widget.repository);
    final dayChanged = oldWidget.day != widget.day;
    if (repoChanged || dayChanged) {
      _resetDay(widget.day);
      if (!widget.settingsOnly) unawaited(_load());
    }
  }

  void _resetDay(String day) {
    _identity++;
    _gen++;
    _day = day;
    _snapshot = null;
    _undoStart = null;
    _undoBusy = false;
    _refreshError = null;
    _messenger.currentState?.removeCurrentSnackBar();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final gen = ++_gen;
    final day = _day;
    final repo = _repo;
    setState(() {
      _loading = true;
      _readError = false;
    });
    try {
      final snap = await repo.readCycle(day, now: _now());
      if (!mounted || gen != _gen || !identical(repo, _repo) || _day != day) {
        return;
      }
      setState(() {
        _snapshot = snap;
        _loading = false;
        _readError = false;
      });
    } catch (_) {
      if (!mounted || gen != _gen || !identical(repo, _repo) || _day != day) {
        return;
      }
      setState(() {
        _loading = false;
        _readError = true;
      });
    }
  }

  void _info() =>
      showOpenBandJournalInfo(context, title: _kInfoTitle, body: _kInfoBody);

  Future<void> _pickDay() async {
    final identity = _identity;
    final picked = await pickOpenBandCycleDay(
      context,
      selected: _day,
      now: _now(),
      synthetic: widget.synthetic,
    );
    if (picked == null || !mounted || identity != _identity || picked == _day) {
      return;
    }
    setState(() => _resetDay(picked));
    await _load();
  }

  CycleSnapshot? get _boundSnapshot {
    final snap = _snapshot;
    if (snap == null || snap.day != _day) return null;
    return snap;
  }

  CycleStart? _startOn(String day) {
    final starts = _boundSnapshot?.starts;
    if (starts == null) return null;
    for (final start in starts) {
      if (start.date == day) return start;
    }
    return null;
  }

  CycleObservation? _observationOn(String day) {
    final rows = _boundSnapshot?.observations;
    if (rows == null) return null;
    for (final row in rows) {
      if (row.date == day) return row;
    }
    return null;
  }

  Future<void> _openStart({CycleStart? existing}) async {
    final identity = _identity;
    final repo = _repo;
    final day = existing?.date ?? _day;
    final removed = await Navigator.of(context).push<_CycleRemovedStart>(
      MaterialPageRoute(
        builder: (_) => _CycleStartEditor(
          repository: repo,
          day: day,
          existing: existing,
          now: _now,
          synthetic: widget.synthetic,
        ),
      ),
    );
    if (!mounted || identity != _identity) return;
    if (removed != null) {
      setState(() {
        _undoStart = removed.start;
        if (removed.refreshFailed) {
          _refreshError = 'Entfernt · Aktualisieren fehlgeschlagen';
        }
      });
      _showUndo();
    }
    await _load();
  }

  Future<void> _openObservation({CycleObservation? existing}) async {
    final repo = _repo;
    final day = existing?.date ?? _day;
    final identity = _identity;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _CycleObservationEditor(
          repository: repo,
          day: day,
          existing: existing,
          now: _now,
          synthetic: widget.synthetic,
        ),
      ),
    );
    if (mounted && identity == _identity) await _load();
  }

  Future<void> _openMeasurements() async {
    await OpenBandCycleMeasurements.push(
      context,
      repository: _repo,
      day: _day,
      now: _now,
      synthetic: widget.synthetic,
    );
    if (mounted) await _load();
  }

  Future<void> _openObservations() async {
    await OpenBandCycleObservations.push(
      context,
      repository: _repo,
      day: _day,
      now: _now,
      synthetic: widget.synthetic,
    );
    if (mounted) await _load();
  }

  Future<void> _openHistory() async {
    var identity = _identity;
    final repo = _repo;
    _CycleHistoryResult? pending;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _CycleHistory(
          repository: repo,
          onReturn: (result) => pending = result,
          day: _day,
          now: _now,
          synthetic: widget.synthetic,
          onDay: (day) {
            if (mounted &&
                identity == _identity &&
                identical(repo, _repo) &&
                day != _day) {
              setState(() => _resetDay(day));
              identity = _identity;
            }
          },
        ),
      ),
    );
    if (!mounted || identity != _identity || !identical(repo, _repo)) return;
    final receipt = pending;
    if (receipt != null && !receipt.isEmpty) {
      setState(() {
        _undoStart = receipt.start;
        _refreshError = receipt.refreshError;
      });
    }
    _showUndo();
    await _load();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => OpenBandCycleSettings(
          repository: _repo,
          now: _now,
          synthetic: widget.synthetic,
        ),
      ),
    );
    if (mounted) await _load();
  }

  void _showUndo() {
    final start = _undoStart;
    if (!mounted || start == null) return;
    _showCycleNotice(
      context,
      messenger: _messenger.currentState,
      message: 'Beginn ${_undoDate(start.date)} entfernt',
      action: 'Rückgängig',
      onAction: () => unawaited(_restore()),
    );
  }

  Future<void> _restore() async {
    final start = _undoStart;
    if (!mounted || start == null || _undoBusy) return;
    final identity = _identity;
    final repo = _repo;
    _messenger.currentState?.removeCurrentSnackBar();
    setState(() => _undoBusy = true);
    try {
      final result = await repo.restoreCycleStart(start, now: _now());
      if (!mounted || identity != _identity || !identical(repo, _repo)) return;
      if (result.conflict) {
        setState(() {
          _undoBusy = false;
          _undoStart = null;
        });
        _showMessage(
          'Beginn wurde geändert',
          action: 'Neu laden',
          onAction: _reloadAfterConflict,
        );
        return;
      }
      if (!result.committed) {
        setState(() => _undoBusy = false);
        _showMessage(
          'Wiederherstellen fehlgeschlagen',
          action: 'Erneut',
          onAction: _restore,
        );
        return;
      }
      if (result.contextRefreshFailed) {
        setState(() {
          _undoBusy = false;
          _refreshError = 'Aktualisieren fehlgeschlagen';
          _undoStart = null;
        });
        await _load();
        return;
      }
      setState(() {
        _undoStart = null;
        _undoBusy = false;
        _refreshError = null;
      });
      await _load();
    } catch (_) {
      if (!mounted || identity != _identity || !identical(repo, _repo)) return;
      setState(() => _undoBusy = false);
      _showMessage(
        'Wiederherstellen fehlgeschlagen',
        action: 'Erneut',
        onAction: _restore,
      );
    }
  }

  Future<void> _reloadAfterConflict() async {
    if (!mounted) return;
    _undoStart = null;
    _messenger.currentState?.removeCurrentSnackBar();
    await _load();
  }

  void _showMessage(String message, {String? action, VoidCallback? onAction}) {
    if (!mounted || action == null || onAction == null) return;
    _showCycleNotice(
      context,
      messenger: _messenger.currentState,
      message: message,
      action: action,
      onAction: onAction,
    );
  }

  Future<void> _retryRefresh() async {
    if (!mounted) return;
    final identity = _identity;
    final repo = _repo;
    try {
      await repo.refreshCycleContext();
      if (!mounted || identity != _identity || !identical(repo, _repo)) return;
      setState(() => _refreshError = null);
      await _load();
    } catch (_) {
      if (!mounted || identity != _identity || !identical(repo, _repo)) return;
      // Keep the committed removal/restoration receipt on retry failure.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.settingsOnly) {
      return OpenBandCycleSettings(
        repository: _repo,
        now: _now,
        synthetic: widget.synthetic,
      );
    }
    final p = OB.of(context);
    final snap = _boundSnapshot;
    final startToday = _startOn(_day);
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return ScaffoldMessenger(
      key: _messenger,
      child: Scaffold(
        backgroundColor: p.canvas,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: ListView(
            key: const ValueKey('cycle-overview'),
            padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + inset),
            children: [
              OBPageHeader(title: 'Zyklus', subtitle: '', onInfo: _info),
              _CycleDayRow(day: _day, onPick: _pickDay),
              const SizedBox(height: 12),
              if (_readError)
                OBSettingsErrorCard(
                  message: 'Daten nicht geladen',
                  retryLabel: 'Erneut versuchen',
                  onRetry: _load,
                )
              else if (_loading && snap == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator.adaptive()),
                )
              else ...[
                _CycleSummaryCard(snapshot: snap),
                if (_refreshError != null) ...[
                  const SizedBox(height: 12),
                  OBSettingsErrorCard(
                    message: _refreshError!.startsWith('Entfernt')
                        ? _refreshError!
                        : 'Wiederhergestellt · $_refreshError',
                    retryLabel: 'Erneut versuchen',
                    onRetry: _retryRefresh,
                  ),
                ],
                const SizedBox(height: 12),
                OBCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      OBSettingsValueRow(
                        label: startToday == null
                            ? 'Beginn eintragen'
                            : 'Beginn bearbeiten',
                        value: '',
                        chevron: true,
                        onTap: () => _openStart(existing: startToday),
                      ),
                      OBSettingsValueRow(
                        label: 'Beobachtung festhalten',
                        value: '',
                        chevron: true,
                        onTap: () =>
                            _openObservation(existing: _observationOn(_day)),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              OBCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    OBSettingsValueRow(
                      label: 'Messwerte',
                      value: '',
                      chevron: true,
                      onTap: _openMeasurements,
                    ),
                    OBSettingsValueRow(
                      label: 'Beobachtungen',
                      value: '',
                      chevron: true,
                      onTap: _openObservations,
                    ),
                    OBSettingsValueRow(
                      label: 'Verlauf',
                      value: '',
                      chevron: true,
                      onTap: _openHistory,
                    ),
                    OBSettingsValueRow(
                      label: 'Einstellungen',
                      value: '',
                      chevron: true,
                      onTap: _openSettings,
                    ),
                  ],
                ),
              ),
              if (widget.synthetic) const _CycleSyntheticFooter(),
            ],
          ),
        ),
      ),
    );
  }
}

class OpenBandCycleSettings extends StatefulWidget {
  final OpenBandRepository repository;
  final DateTime Function() now;
  final bool synthetic;

  const OpenBandCycleSettings({
    super.key,
    required this.repository,
    required this.now,
    this.synthetic = false,
  });

  @override
  State<OpenBandCycleSettings> createState() => _OpenBandCycleSettingsState();
}

class _OpenBandCycleSettingsState extends State<OpenBandCycleSettings> {
  CycleSettings? _settings;
  bool _loading = true;
  bool _readError = false;
  bool _busy = false;
  String? _error;
  CycleSettings? _retry;
  int _gen = 0;

  bool get _locked => _busy || (_error != null && _retry == null);

  @override
  void didUpdateWidget(OpenBandCycleSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository)) {
      _settings = null;
      _retry = null;
      _busy = false;
      unawaited(_load());
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final gen = ++_gen;
    final repo = widget.repository;
    setState(() {
      _loading = true;
      _readError = false;
      _error = null;
    });
    try {
      final settings = await repo.readCycleSettings();
      if (!mounted || gen != _gen || !identical(repo, widget.repository)) {
        return;
      }
      setState(() {
        _settings = settings;
        _loading = false;
        _readError = false;
      });
    } catch (_) {
      if (!mounted || gen != _gen || !identical(repo, widget.repository)) {
        return;
      }
      setState(() {
        _loading = false;
        _readError = true;
      });
    }
  }

  Future<void> _persist(CycleSettings desired) async {
    if (_busy) return;
    final repo = widget.repository;
    setState(() {
      _busy = true;
      _error = null;
      _retry = desired;
    });
    try {
      final result = await repo.saveCycleSettings(desired);
      if (!mounted || !identical(repo, widget.repository)) return;
      if (!result.committed) {
        setState(() {
          _busy = false;
          _error = 'Speichern fehlgeschlagen';
        });
        return;
      }
      if (result.contextRefreshFailed) {
        setState(() {
          _settings = result.settings ?? desired;
          _busy = false;
          _error = 'Aktualisieren fehlgeschlagen';
          _retry = null;
        });
        return;
      }
      try {
        final latest = await repo.readCycleSettings();
        if (!mounted || !identical(repo, widget.repository)) return;
        setState(() {
          _settings = latest;
          _busy = false;
          _retry = null;
        });
      } catch (_) {
        if (!mounted || !identical(repo, widget.repository)) return;
        setState(() {
          _settings = result.settings ?? desired;
          _busy = false;
          _error = 'Daten nicht geladen';
          _retry = null;
        });
      }
    } catch (_) {
      if (!mounted || !identical(repo, widget.repository)) return;
      setState(() {
        _busy = false;
        _error = 'Speichern fehlgeschlagen';
      });
    }
  }

  Future<void> _retryFailed() async {
    if (_busy) return;
    final pending = _retry;
    if (pending != null) {
      await _persist(pending);
      return;
    }
    final repo = widget.repository;
    var needsRefresh = _error == 'Aktualisieren fehlgeschlagen';
    setState(() => _busy = true);
    try {
      if (needsRefresh) {
        await repo.refreshCycleContext();
        if (!mounted || !identical(repo, widget.repository)) return;
        needsRefresh = false;
      }
      final latest = await repo.readCycleSettings();
      if (!mounted || !identical(repo, widget.repository)) return;
      setState(() {
        _settings = latest;
        _busy = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted || !identical(repo, widget.repository)) return;
      setState(() {
        _busy = false;
        _error = needsRefresh
            ? 'Aktualisieren fehlgeschlagen'
            : 'Daten nicht geladen';
      });
    }
  }

  Future<void> _pickSituation() async {
    final current = _settings;
    final repo = widget.repository;
    if (current == null || _locked) return;
    final selected = switch (current.situation) {
      CycleSituation.cycling => 1,
      CycleSituation.contraception => 2,
      CycleSituation.none => 3,
      null => 0,
    };
    final picked = await showOpenBandSettingsChoiceSheet<int>(
      context: context,
      title: 'Situation',
      selected: selected,
      choices: const [
        (0, 'Keine Angabe'),
        (1, 'Natürlicher Zyklus'),
        (2, 'Hormonelle Verhütung'),
        (3, 'Aktuell kein Zyklus'),
      ],
    );
    if (picked == null ||
        !mounted ||
        !identical(repo, widget.repository) ||
        picked == selected) {
      return;
    }
    final situation = switch (picked) {
      1 => CycleSituation.cycling,
      2 => CycleSituation.contraception,
      3 => CycleSituation.none,
      _ => null,
    };
    await _persist(
      CycleSettings(
        enabled: current.enabled,
        estimatesEnabled: current.estimatesEnabled,
        situation: situation,
        lengthReviewEnabled: current.lengthReviewEnabled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final settings = _settings;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      backgroundColor: p.canvas,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: ListView(
          key: const ValueKey('cycle-settings'),
          padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + inset),
          children: [
            OBPageHeader(
              title: 'Zyklus',
              subtitle: '',
              onInfo: () => showOpenBandJournalInfo(
                context,
                title: _kInfoTitle,
                body: _kInfoBody,
              ),
            ),
            if (_readError)
              OBSettingsErrorCard(
                message: 'Daten nicht geladen',
                retryLabel: 'Erneut versuchen',
                onRetry: _load,
              )
            else if (_loading && settings == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator.adaptive()),
              )
            else if (settings != null) ...[
              OBCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: OBSettingsToggleRow(
                  label: 'Zyklus im Journal',
                  value: settings.enabled,
                  interactive: !_locked,
                  onToggle: _locked
                      ? null
                      : () => _persist(
                          CycleSettings(
                            enabled: !settings.enabled,
                            estimatesEnabled: settings.estimatesEnabled,
                            situation: settings.situation,
                            lengthReviewEnabled: settings.lengthReviewEnabled,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              OBCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    OBSettingsToggleRow(
                      label: 'Zeitschätzung',
                      value: settings.estimatesEnabled,
                      interactive: !_locked,
                      onToggle: _locked
                          ? null
                          : () => _persist(
                              CycleSettings(
                                enabled: settings.enabled,
                                estimatesEnabled: !settings.estimatesEnabled,
                                situation: settings.situation,
                                lengthReviewEnabled:
                                    settings.lengthReviewEnabled,
                              ),
                            ),
                    ),
                    OBSettingsValueRow(
                      label: 'Situation',
                      value: cycleSituationLabel(settings.situation),
                      chevron: true,
                      onTap: _locked ? null : _pickSituation,
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _CycleErrorStrip(
                  _retry == null ? 'Gespeichert · $_error' : _error!,
                ),
                const SizedBox(height: 12),
                OBAction(
                  'Erneut versuchen',
                  ink: true,
                  onPressed: _busy ? null : _retryFailed,
                ),
              ],
            ],
            if (widget.synthetic) const _CycleSyntheticFooter(),
          ],
        ),
      ),
    );
  }
}

class _CycleStartEditor extends StatefulWidget {
  final OpenBandRepository repository;
  final String day;
  final CycleStart? existing;
  final DateTime Function() now;
  final bool synthetic;

  const _CycleStartEditor({
    required this.repository,
    required this.day,
    required this.existing,
    required this.now,
    required this.synthetic,
  });

  @override
  State<_CycleStartEditor> createState() => _CycleStartEditorState();
}

class _CycleStartEditorState extends State<_CycleStartEditor> {
  late String _date = widget.existing?.date ?? widget.day;
  late final TextEditingController _note = TextEditingController(
    text: widget.existing?.note ?? '',
  );
  bool _busy = false;
  bool _committed = false;
  String? _error;
  bool _conflict = false;
  _CycleSaveStage _stage = _CycleSaveStage.write;
  CycleStart? _expected;
  int _token = 0;

  bool get _locked => _busy || _committed;

  @override
  void initState() {
    super.initState();
    _expected = widget.existing;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  CycleStart _draft() => CycleStart(
    date: _date,
    kind: _expected?.kind ?? kCycleStartKind,
    note: _noteValue(_expected?.note, _note.text),
  );

  Future<void> _pickDate() async {
    if (_locked) return;
    final picked = await pickOpenBandCycleDay(
      context,
      selected: _date,
      now: widget.now(),
      synthetic: widget.synthetic,
    );
    if (picked == null || !mounted || picked == _date) return;
    setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (_busy) return;
    final token = ++_token;
    final repo = widget.repository;
    final desired = _draft();
    setState(() => _busy = true);
    try {
      if (_stage == _CycleSaveStage.refresh) {
        await repo.refreshCycleContext();
        if (!mounted ||
            token != _token ||
            !identical(repo, widget.repository)) {
          return;
        }
        _stage = _CycleSaveStage.read;
      }
      if (_stage == _CycleSaveStage.read) {
        await repo.readCycle(desired.date, now: widget.now());
        if (!mounted ||
            token != _token ||
            !identical(repo, widget.repository)) {
          return;
        }
        Navigator.pop(context);
        return;
      }
      final result = await repo.saveCycleStart(
        desired,
        expected: _expected,
        now: widget.now(),
      );
      if (!mounted || token != _token || !identical(repo, widget.repository)) {
        return;
      }
      if (result.conflict) {
        setState(() {
          _busy = false;
          _conflict = true;
          _error = 'Eintrag wurde geändert';
        });
        return;
      }
      if (!result.committed) {
        setState(() {
          _busy = false;
          _error = 'Speichern fehlgeschlagen';
        });
        return;
      }
      _committed = true;
      if (result.contextRefreshFailed) {
        setState(() {
          _stage = _CycleSaveStage.refresh;
          _busy = false;
          _error = 'Aktualisieren fehlgeschlagen';
        });
        return;
      }
      _stage = _CycleSaveStage.read;
      try {
        await repo.readCycle(desired.date, now: widget.now());
        if (!mounted ||
            token != _token ||
            !identical(repo, widget.repository)) {
          return;
        }
        Navigator.pop(context);
      } catch (_) {
        if (!mounted || token != _token) return;
        setState(() {
          _busy = false;
          _error = 'Daten nicht geladen';
        });
      }
    } catch (_) {
      if (!mounted || token != _token) return;
      setState(() {
        _busy = false;
        _error = _committed
            ? (_stage == _CycleSaveStage.refresh
                  ? 'Aktualisieren fehlgeschlagen'
                  : 'Daten nicht geladen')
            : 'Speichern fehlgeschlagen';
      });
    }
  }

  Future<void> _reloadConflict() async {
    if (_busy) return;
    final repo = widget.repository;
    setState(() => _busy = true);
    try {
      // A move conflict reloads its source, never adopts the destination CAS.
      final sourceDate = _expected?.date ?? _date;
      final now = widget.now();
      final snap = await repo.readCycle(cycleTodayLabel(now), now: now);
      if (!mounted || !identical(repo, widget.repository)) return;
      CycleStart? current;
      for (final start in snap.starts) {
        if (start.date == sourceDate) current = start;
      }
      if (_expected != null && current == null) {
        if (snap.unreadableStarts) {
          setState(() {
            _busy = false;
            _error = 'Daten nicht geladen';
          });
        } else {
          // The original edit source was deleted or moved elsewhere. Never
          // turn this editor into a create at A or an overwrite at B.
          Navigator.pop(context);
        }
        return;
      }
      setState(() {
        _date = sourceDate;
        _note.text = current?.note ?? '';
        _expected = current;
        _conflict = false;
        _error = null;
        _busy = false;
        _stage = _CycleSaveStage.write;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Daten nicht geladen';
      });
    }
  }

  Future<void> _remove() async {
    final expected = _expected;
    if (expected == null || _locked) return;
    final ok = await showOpenBandConfirmSheet(
      context: context,
      title: 'Beginn ${_historyDate(expected.date)} entfernen?',
      confirmLabel: 'Entfernen',
      cancelLabel: 'Abbrechen',
    );
    if (ok != true || !mounted) return;
    final token = ++_token;
    final repo = widget.repository;
    setState(() => _busy = true);
    try {
      final result = await repo.removeCycleStart(expected);
      if (!mounted || token != _token || !identical(repo, widget.repository)) {
        return;
      }
      if (result.conflict) {
        setState(() {
          _busy = false;
          _conflict = true;
          _error = 'Eintrag wurde geändert';
        });
        return;
      }
      if (!result.committed) {
        setState(() {
          _busy = false;
          _error = 'Speichern fehlgeschlagen';
        });
        return;
      }
      Navigator.pop(
        context,
        _CycleRemovedStart(
          expected,
          refreshFailed: result.contextRefreshFailed,
        ),
      );
    } catch (_) {
      if (!mounted || token != _token) return;
      setState(() {
        _busy = false;
        _error = 'Speichern fehlgeschlagen';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      backgroundColor: p.canvas,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: ListView(
          key: const ValueKey('cycle-start'),
          padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + inset),
          children: [
            const OBPageHeader(title: 'Beginn', subtitle: ''),
            OBCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: OBSettingsValueRow(
                label: 'Datum',
                value: _valueDate(_date),
                chevron: !_committed,
                onTap: _locked ? null : _pickDate,
              ),
            ),
            const SizedBox(height: 12),
            _CycleNoteField(
              controller: _note,
              enabled: !_locked,
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _CycleErrorStrip(_committed ? 'Gespeichert · $_error' : _error!),
              if (_conflict) ...[
                const SizedBox(height: 12),
                OBAction(
                  'Neu laden',
                  ink: true,
                  secondary: true,
                  onPressed: _busy ? null : _reloadConflict,
                ),
              ],
            ],
            const SizedBox(height: 12),
            OBAction(
              _committed ? 'Erneut versuchen' : 'Speichern',
              ink: true,
              onPressed: _busy ? null : _save,
            ),
            if (_expected != null && !_committed) ...[
              const SizedBox(height: 12),
              OBAction(
                'Entfernen',
                ink: true,
                secondary: true,
                destructive: true,
                onPressed: _busy ? null : _remove,
              ),
            ],
            if (widget.synthetic) const _CycleSyntheticFooter(),
          ],
        ),
      ),
    );
  }
}

class _CycleObservationEditor extends StatefulWidget {
  final OpenBandRepository repository;
  final String day;
  final CycleObservation? existing;
  final DateTime Function() now;
  final bool synthetic;

  const _CycleObservationEditor({
    required this.repository,
    required this.day,
    required this.existing,
    required this.now,
    required this.synthetic,
  });

  @override
  State<_CycleObservationEditor> createState() =>
      _CycleObservationEditorState();
}

class _CycleObservationEditorState extends State<_CycleObservationEditor> {
  late String _date = widget.existing?.date ?? widget.day;
  late List<String> _tags = [...?widget.existing?.tags];
  late final TextEditingController _note = TextEditingController(
    text: widget.existing?.note ?? '',
  );
  bool _busy = false;
  bool _committed = false;
  String? _error;
  bool _conflict = false;
  _CycleSaveStage _stage = _CycleSaveStage.write;
  CycleObservation? _expected;
  int _token = 0;

  bool get _locked => _busy || _committed;
  bool get _dateFixed =>
      _committed || widget.existing != null || _expected != null;

  @override
  void initState() {
    super.initState();
    _expected = widget.existing;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Iterable<String> get _unknownTags sync* {
    for (final tag in _tags) {
      if (!kCycleObservationTags.contains(tag)) yield tag;
    }
  }

  void _toggle(String tag) {
    if (_locked) return;
    setState(() {
      if (_tags.contains(tag)) {
        _tags = [
          for (final t in _tags)
            if (t != tag) t,
        ];
      } else {
        _tags = [..._tags, tag];
      }
    });
  }

  CycleObservation _draft() {
    final text = _note.text;
    return CycleObservation(
      date: _date,
      tags: List.unmodifiable(_tags),
      note: _noteValue(_expected?.note, text),
      updatedAt: _expected?.updatedAt,
    );
  }

  Future<void> _pickDate() async {
    if (_locked || _dateFixed) return;
    final picked = await pickOpenBandCycleDay(
      context,
      selected: _date,
      now: widget.now(),
      synthetic: widget.synthetic,
    );
    if (picked == null || !mounted || picked == _date) return;
    await _adoptDate(picked);
  }

  Future<void> _adoptDate(String day) async {
    final repo = widget.repository;
    setState(() => _busy = true);
    try {
      final snap = await repo.readCycle(day, now: widget.now());
      if (!mounted || !identical(repo, widget.repository)) return;
      CycleObservation? current;
      for (final row in snap.observations) {
        if (row.date == day) current = row;
      }
      setState(() {
        _date = day;
        _expected = current;
        if (current != null) {
          _tags = [...current.tags];
          _note.text = current.note ?? '';
        }
        _error = null;
        _conflict = false;
        _stage = _CycleSaveStage.write;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Daten nicht geladen';
      });
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    final token = ++_token;
    final repo = widget.repository;
    final desired = _draft();
    setState(() => _busy = true);
    try {
      if (_stage == _CycleSaveStage.refresh) {
        await repo.refreshCycleContext();
        if (!mounted ||
            token != _token ||
            !identical(repo, widget.repository)) {
          return;
        }
        _stage = _CycleSaveStage.read;
      }
      if (_stage == _CycleSaveStage.read) {
        await repo.readCycle(desired.date, now: widget.now());
        if (!mounted ||
            token != _token ||
            !identical(repo, widget.repository)) {
          return;
        }
        Navigator.pop(context);
        return;
      }
      final result = await repo.saveCycleObservation(
        desired,
        expected: _expected,
        now: widget.now(),
      );
      if (!mounted || token != _token || !identical(repo, widget.repository)) {
        return;
      }
      if (result.conflict) {
        setState(() {
          _busy = false;
          _conflict = true;
          _error = 'Eintrag wurde geändert';
        });
        return;
      }
      if (!result.committed) {
        setState(() {
          _busy = false;
          _error = 'Speichern fehlgeschlagen';
        });
        return;
      }
      _committed = true;
      if (result.contextRefreshFailed) {
        setState(() {
          _stage = _CycleSaveStage.refresh;
          _busy = false;
          _error = 'Aktualisieren fehlgeschlagen';
        });
        return;
      }
      _stage = _CycleSaveStage.read;
      try {
        await repo.readCycle(desired.date, now: widget.now());
        if (!mounted ||
            token != _token ||
            !identical(repo, widget.repository)) {
          return;
        }
        Navigator.pop(context);
      } catch (_) {
        if (!mounted || token != _token) return;
        setState(() {
          _busy = false;
          _error = 'Daten nicht geladen';
        });
      }
    } catch (_) {
      if (!mounted || token != _token) return;
      setState(() {
        _busy = false;
        _error = _committed
            ? (_stage == _CycleSaveStage.refresh
                  ? 'Aktualisieren fehlgeschlagen'
                  : 'Daten nicht geladen')
            : 'Speichern fehlgeschlagen';
      });
    }
  }

  Future<void> _reloadConflict() async {
    if (_busy) return;
    final repo = widget.repository;
    setState(() => _busy = true);
    try {
      final snap = await repo.readCycle(_date, now: widget.now());
      if (!mounted || !identical(repo, widget.repository)) return;
      CycleObservation? current;
      for (final row in snap.observations) {
        if (row.date == _date) current = row;
      }
      setState(() {
        _tags = [...?current?.tags];
        _note.text = current?.note ?? '';
        _expected = current;
        _conflict = false;
        _error = null;
        _busy = false;
        _stage = _CycleSaveStage.write;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Daten nicht geladen';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final tags = [...kCycleObservationTags, ..._unknownTags];
    return Scaffold(
      backgroundColor: p.canvas,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: ListView(
          key: const ValueKey('cycle-observation'),
          padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + inset),
          children: [
            const OBPageHeader(title: 'Beobachtung', subtitle: ''),
            OBCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: OBSettingsValueRow(
                label: 'Datum',
                value: _valueDate(_date),
                chevron: !_dateFixed,
                onTap: _locked || _dateFixed ? null : _pickDate,
              ),
            ),
            const SizedBox(height: 12),
            OBCard(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
              child: Column(
                children: [
                  for (final tag in tags)
                    OBSettingsChoiceRow(
                      label: kCycleObservationLabels[tag] ?? tag,
                      selected: _tags.contains(tag),
                      onTap: _locked ? null : () => _toggle(tag),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _CycleNoteField(
              controller: _note,
              enabled: !_locked,
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _CycleErrorStrip(_committed ? 'Gespeichert · $_error' : _error!),
              if (_conflict) ...[
                const SizedBox(height: 12),
                OBAction(
                  'Neu laden',
                  ink: true,
                  secondary: true,
                  onPressed: _busy ? null : _reloadConflict,
                ),
              ],
            ],
            const SizedBox(height: 12),
            OBAction(
              _committed ? 'Erneut versuchen' : 'Speichern',
              ink: true,
              onPressed: _busy ? null : _save,
            ),
            if (widget.synthetic) const _CycleSyntheticFooter(),
          ],
        ),
      ),
    );
  }
}

class _CycleHistoryResult {
  const _CycleHistoryResult(this.start, this.refreshError);
  final CycleStart? start;
  final String? refreshError;
  bool get isEmpty => start == null && refreshError == null;
}

class _CycleHistory extends StatefulWidget {
  final ValueChanged<_CycleHistoryResult> onReturn;
  final OpenBandRepository repository;
  final String day;
  final DateTime Function() now;
  final bool synthetic;
  final ValueChanged<String>? onDay;

  const _CycleHistory({
    required this.onReturn,
    required this.repository,
    required this.day,
    required this.now,
    required this.synthetic,
    this.onDay,
  });

  @override
  State<_CycleHistory> createState() => _CycleHistoryState();
}

class _CycleHistoryState extends State<_CycleHistory> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  late String _day = widget.day;
  CycleSnapshot? _snapshot;
  bool _loading = true;
  bool _readError = false;
  String? _refreshError;
  CycleStart? _undoStart;
  bool _undoBusy = false;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final gen = ++_gen;
    final day = _day;
    final repo = widget.repository;
    setState(() {
      _loading = true;
      _readError = false;
      _snapshot = null;
    });
    try {
      final snap = await repo.readCycle(day, now: widget.now());
      if (!mounted ||
          gen != _gen ||
          _day != day ||
          !identical(repo, widget.repository)) {
        return;
      }
      setState(() {
        _snapshot = snap;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || gen != _gen || _day != day) return;
      setState(() {
        _loading = false;
        _readError = true;
      });
    }
  }

  Future<void> _pickDay() async {
    final picked = await pickOpenBandCycleDay(
      context,
      selected: _day,
      now: widget.now(),
      synthetic: widget.synthetic,
    );
    if (picked == null || !mounted || picked == _day) return;
    setState(() {
      _day = picked;
      _snapshot = null;
    });
    widget.onDay?.call(picked);
    await _load();
  }

  Future<void> _open(_HistoryRow row) async {
    if (row.start != null) {
      final removed = await Navigator.of(context).push<_CycleRemovedStart>(
        MaterialPageRoute(
          builder: (_) => _CycleStartEditor(
            repository: widget.repository,
            day: row.date,
            existing: row.start,
            now: widget.now,
            synthetic: widget.synthetic,
          ),
        ),
      );
      if (removed != null && mounted) {
        setState(() {
          _undoStart = removed.start;
          if (removed.refreshFailed) {
            _refreshError = 'Entfernt · Aktualisieren fehlgeschlagen';
          }
        });
        _showUndo();
      }
    } else {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _CycleObservationEditor(
            repository: widget.repository,
            day: row.date,
            existing: row.observation,
            now: widget.now,
            synthetic: widget.synthetic,
          ),
        ),
      );
    }
    if (mounted) await _load();
  }

  void _showUndo() {
    final start = _undoStart;
    if (!mounted || start == null) return;
    _showCycleNotice(
      context,
      messenger: _messenger.currentState,
      message: 'Beginn ${_undoDate(start.date)} entfernt',
      action: 'Rückgängig',
      onAction: () => unawaited(_restore()),
    );
  }

  Future<void> _restore() async {
    final start = _undoStart;
    if (!mounted || start == null || _undoBusy) return;
    final repo = widget.repository;
    _messenger.currentState?.removeCurrentSnackBar();
    setState(() => _undoBusy = true);
    try {
      final result = await repo.restoreCycleStart(start, now: widget.now());
      if (!mounted || !identical(repo, widget.repository)) return;
      if (result.conflict) {
        setState(() {
          _undoBusy = false;
          _undoStart = null;
        });
        _showMessage(
          'Beginn wurde geändert',
          action: 'Neu laden',
          onAction: () {
            _undoStart = null;
            _messenger.currentState?.removeCurrentSnackBar();
            unawaited(_load());
          },
        );
        return;
      }
      if (!result.committed) {
        setState(() => _undoBusy = false);
        _showMessage(
          'Wiederherstellen fehlgeschlagen',
          action: 'Erneut',
          onAction: _restore,
        );
        return;
      }
      if (result.contextRefreshFailed) {
        setState(() {
          _undoBusy = false;
          _refreshError = 'Aktualisieren fehlgeschlagen';
          _undoStart = null;
        });
        await _load();
        return;
      }
      setState(() {
        _undoStart = null;
        _undoBusy = false;
        _refreshError = null;
      });
      await _load();
    } catch (_) {
      if (!mounted) return;
      setState(() => _undoBusy = false);
      _showMessage(
        'Wiederherstellen fehlgeschlagen',
        action: 'Erneut',
        onAction: _restore,
      );
    }
  }

  void _showMessage(String message, {String? action, VoidCallback? onAction}) {
    if (!mounted || action == null || onAction == null) return;
    _showCycleNotice(
      context,
      messenger: _messenger.currentState,
      message: message,
      action: action,
      onAction: onAction,
    );
  }

  Future<void> _retryRefresh() async {
    if (!mounted) return;
    final repo = widget.repository;
    try {
      await repo.refreshCycleContext();
      if (!mounted || !identical(repo, widget.repository)) return;
      setState(() => _refreshError = null);
      await _load();
    } catch (_) {
      if (!mounted || !identical(repo, widget.repository)) return;
      // Preserve the committed receipt; retry is refresh-only.
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final rows = _historyRows(_snapshot);
    return PopScope<void>(
      canPop: !_undoBusy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) return;
        final receipt = _CycleHistoryResult(_undoStart, _refreshError);
        if (!receipt.isEmpty) widget.onReturn(receipt);
      },
      child: ScaffoldMessenger(
        key: _messenger,
        child: Scaffold(
          backgroundColor: p.canvas,
          body: SafeArea(
            child: ListView(
              key: const ValueKey('cycle-history'),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                OBPageHeader(
                  title: 'Verlauf',
                  subtitle: '',
                  onInfo: () => showOpenBandJournalInfo(
                    context,
                    title: _kInfoTitle,
                    body: _kInfoBody,
                  ),
                ),
                _CycleDayRow(day: _day, onPick: _pickDay),
                const SizedBox(height: 12),
                if (_readError)
                  OBSettingsErrorCard(
                    message: 'Daten nicht geladen',
                    retryLabel: 'Erneut versuchen',
                    onRetry: _load,
                  )
                else if (_loading && _snapshot == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator.adaptive()),
                  )
                else ...[
                  if (_refreshError != null) ...[
                    OBSettingsErrorCard(
                      message: _refreshError!.startsWith('Entfernt')
                          ? _refreshError!
                          : 'Wiederhergestellt · $_refreshError',
                      retryLabel: 'Erneut versuchen',
                      onRetry: _retryRefresh,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (rows.isEmpty && (_snapshot?.unreadableCount ?? 0) == 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 12,
                      ),
                      child: Text(
                        'Keine Einträge',
                        style: p
                            .text(13, color: p.muted)
                            .copyWith(height: 18 / 13),
                      ),
                    )
                  else ...[
                    if ((_snapshot?.unreadableCount ?? 0) > 0) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          'Einträge teilweise lesbar',
                          style: p
                              .text(13, color: p.muted)
                              .copyWith(height: 18 / 13),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (rows.isNotEmpty)
                      OBCard(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          children: [
                            for (final row in rows)
                              OBSettingsValueRow(
                                label: _historyDate(row.date),
                                value: row.label,
                                chevron: true,
                                onTap: () => _open(row),
                              ),
                          ],
                        ),
                      ),
                  ],
                ],
                if (widget.synthetic) const _CycleSyntheticFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CycleSummaryCard extends StatelessWidget {
  final CycleSnapshot? snapshot;
  const _CycleSummaryCard({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final snap = snapshot;
    final untrustedStarts = snap?.unreadableStarts ?? false;
    final latest = untrustedStarts ? null : snap?.latestStart;
    final estimate = snap?.estimate;
    final showEstimate =
        !untrustedStarts && estimate != null && _showsEstimate(estimate);
    final partialObservations =
        !untrustedStarts && (snap?.unreadableCount ?? 0) > 0;
    return OBCard(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            untrustedStarts || snap?.cycleDay == null
                ? '—'
                : 'Tag ${snap!.cycleDay}',
            style: p
                .text(48, weight: FontWeight.w700, display: true)
                .copyWith(height: 52 / 48, letterSpacing: -0.04 * 48),
          ),
          const SizedBox(height: 4),
          Text(
            untrustedStarts
                ? 'Einträge teilweise lesbar'
                : latest == null
                ? 'Noch kein Beginn'
                : 'Beginn · ${_historyDate(latest.date)}',
            style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
          ),
          if (partialObservations) ...[
            const SizedBox(height: 4),
            Text(
              'Einträge teilweise lesbar',
              style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
            ),
          ],
          if (showEstimate) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Divider(height: 1, thickness: 1, color: p.line),
            ),
            const SizedBox(height: 16),
            Text(
              estimate.availability == CycleEstimateAvailability.available
                  ? 'Nächster Beginn · geschätzt'
                  : 'Schätzung offen',
              style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
            ),
            const SizedBox(height: 6),
            Text(
              _estimateValue(estimate),
              style: p
                  .text(28, weight: FontWeight.w700, display: true)
                  .copyWith(height: 34 / 28, letterSpacing: -0.02 * 28),
            ),
            const SizedBox(height: 6),
            Text(
              _estimateReason(estimate),
              style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
            ),
          ],
        ],
      ),
    );
  }
}

class _CycleDayRow extends StatelessWidget {
  final String day;
  final VoidCallback onPick;
  const _CycleDayRow({required this.day, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _headingDate(day),
                style: p
                    .text(24, weight: FontWeight.w700, display: true)
                    .copyWith(height: 30 / 24),
              ),
            ),
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                tooltip: 'Datum',
                onPressed: onPick,
                padding: EdgeInsets.zero,
                icon: Icon(LucideIcons.calendar, size: 20, color: p.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CycleNoteField extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;
  const _CycleNoteField({
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return OBCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Notiz',
            style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('cycle-note'),
            controller: controller,
            enabled: enabled,
            minLines: 1,
            maxLines: 4,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            style: p.text(16).copyWith(height: 24 / 16, color: p.ink),
            cursorColor: p.ink,
            decoration: InputDecoration(
              hintText: '—',
              hintStyle: p.text(16, color: p.muted).copyWith(height: 24 / 16),
              filled: true,
              fillColor: p.well,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AlpRadius.well),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 12,
                horizontal: 16,
              ),
            ),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _CycleRemovedStart {
  const _CycleRemovedStart(this.start, {this.refreshFailed = false});
  final CycleStart start;
  final bool refreshFailed;
}

class _CycleErrorStrip extends StatelessWidget {
  final String message;
  const _CycleErrorStrip(this.message);

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.dangerTint,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(14),
      child: Text(
        message,
        style: p.text(14, color: p.danger).copyWith(height: 20 / 14),
      ),
    );
  }
}

class _CycleSyntheticFooter extends StatelessWidget {
  const _CycleSyntheticFooter();

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 12),
      child: Text(
        'Synthetische Daten',
        style: p.text(12, color: p.muted).copyWith(height: 18 / 12),
      ),
    );
  }
}

class _HistoryRow {
  _HistoryRow.start(CycleStart this.start)
    : date = start.date,
      label = start.contributes ? 'Beginn' : start.kind,
      observation = null;
  _HistoryRow.observation(CycleObservation this.observation)
    : date = observation.date,
      label = _observationLabel(observation),
      start = null;

  final String date;
  final String label;
  final CycleStart? start;
  final CycleObservation? observation;
}

enum _CycleSaveStage { write, refresh, read }

String cycleSituationLabel(CycleSituation? situation) => switch (situation) {
  CycleSituation.cycling => 'Natürlicher Zyklus',
  CycleSituation.contraception => 'Hormonelle Verhütung',
  CycleSituation.none => 'Aktuell kein Zyklus',
  null => 'Keine Angabe',
};

String _headingDate(String day) =>
    DateFormat('EEE, d. MMM', 'de_DE').format(DateTime.parse(day));

String _historyDate(String day) =>
    DateFormat('d. MMMM', 'de_DE').format(DateTime.parse(day));

String _undoDate(String day) =>
    DateFormat('d. MMM', 'de_DE').format(DateTime.parse(day));

void _showCycleNotice(
  BuildContext context, {
  required String message,
  required String action,
  required VoidCallback onAction,
  required ScaffoldMessengerState? messenger,
}) {
  if (!context.mounted || messenger == null) return;
  showOpenBandUndoNotice(
    context: context,
    messenger: messenger,
    message: message,
    primaryLabel: action,
    onPrimary: () {
      if (context.mounted && ModalRoute.of(context)?.isCurrent == true) {
        onAction();
      }
    },
  );
}

String _valueDate(String day) =>
    DateFormat('d. MMM y', 'de_DE').format(DateTime.parse(day));

String? _noteValue(String? original, String text) {
  if (text == (original ?? '')) return original;
  return text.isEmpty ? null : text;
}

String _observationLabel(CycleObservation observation) {
  for (final tag in kCycleObservationTags) {
    if (observation.tags.contains(tag)) {
      return kCycleObservationLabels[tag] ?? tag;
    }
  }
  if (observation.tags.isNotEmpty) return observation.tags.first;
  return 'Notiz';
}

bool _showsEstimate(CycleEstimate estimate) {
  switch (estimate.reason) {
    case CycleEstimateReason.estimatesDisabled:
    case CycleEstimateReason.trackingDisabled:
    case CycleEstimateReason.situationNone:
    case CycleEstimateReason.missingStarts:
    case CycleEstimateReason.unreadableStarts:
      return false;
    case CycleEstimateReason.availableRange:
    case CycleEstimateReason.availablePoint:
    case CycleEstimateReason.gapExceedsSixtyDays:
    case CycleEstimateReason.staleOpen:
      return true;
  }
}

String _estimateValue(CycleEstimate estimate) {
  if (estimate.availability != CycleEstimateAvailability.available) return '—';
  if (estimate.from != null && estimate.to != null) {
    final from = DateTime.parse(estimate.from!);
    final to = DateTime.parse(estimate.to!);
    if (from.year == to.year && from.month == to.month) {
      return '${from.day}.–${DateFormat('d. MMM', 'de_DE').format(to)}';
    }
    return '${DateFormat('d. MMM', 'de_DE').format(from)}–${DateFormat('d. MMM', 'de_DE').format(to)}';
  }
  if (estimate.point == null) return '—';
  return DateFormat('d. MMM', 'de_DE').format(DateTime.parse(estimate.point!));
}

String _estimateReason(CycleEstimate estimate) {
  switch (estimate.reason) {
    case CycleEstimateReason.availableRange:
    case CycleEstimateReason.availablePoint:
      final n = estimate.gapCount;
      return n == 1 ? '1 bisheriger Abstand' : '$n bisherige Abstände';
    case CycleEstimateReason.gapExceedsSixtyDays:
      return 'Abstand über 60 Tage';
    case CycleEstimateReason.unreadableStarts:
      return 'Starts nicht lesbar';
    case CycleEstimateReason.staleOpen:
      return 'Liegt zurück';
    case CycleEstimateReason.missingStarts:
      return 'Noch zu wenige Starts';
    case CycleEstimateReason.estimatesDisabled:
    case CycleEstimateReason.trackingDisabled:
    case CycleEstimateReason.situationNone:
      return '';
  }
}

List<_HistoryRow> _historyRows(CycleSnapshot? snap) {
  if (snap == null) return const [];
  final rows = <_HistoryRow>[
    for (final observation in snap.observations)
      _HistoryRow.observation(observation),
    for (final start in snap.starts) _HistoryRow.start(start),
  ];
  rows.sort((a, b) {
    final byDate = b.date.compareTo(a.date);
    if (byDate != 0) return byDate;
    if (a.observation != null && b.start != null) return -1;
    if (a.start != null && b.observation != null) return 1;
    return 0;
  });
  return rows;
}

Future<String?> pickOpenBandCycleDay(
  BuildContext context, {
  required String selected,
  required DateTime now,
  bool synthetic = false,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) =>
          _CycleDayPicker(selected: selected, now: now, synthetic: synthetic),
    ),
  );
}

class _CycleDayPicker extends StatefulWidget {
  final String selected;
  final DateTime now;
  final bool synthetic;
  const _CycleDayPicker({
    required this.selected,
    required this.now,
    this.synthetic = false,
  });

  @override
  State<_CycleDayPicker> createState() => _CycleDayPickerState();
}

class _CycleDayPickerState extends State<_CycleDayPicker> {
  late DateTime selected;
  late DateTime month;

  @override
  void initState() {
    super.initState();
    final day = cycleDateIsAfterToday(widget.selected, widget.now)
        ? cycleTodayLabel(widget.now)
        : widget.selected;
    selected = DateTime.parse(day);
    month = DateTime(selected.year, selected.month);
  }

  void _commit() {
    final day = dayLabelOf(selected);
    if (cycleDateIsAfterToday(day, widget.now)) return;
    Navigator.pop(context, day);
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const OBPageHeader(title: 'Datum', subtitle: ''),
            OBCard(
              padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
              child: OBCalendar(
                month: month,
                selected: selected,
                now: widget.now,
                onSelect: (day) => setState(() {
                  selected = day;
                  month = DateTime(day.year, day.month);
                }),
                onPrevMonth: () => setState(
                  () => month = DateTime(month.year, month.month - 1),
                ),
                onNextMonth: () => setState(
                  () => month = DateTime(month.year, month.month + 1),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OBAction('Übernehmen', ink: true, onPressed: _commit),
            if (widget.synthetic) const _CycleSyntheticFooter(),
          ],
        ),
      ),
    );
  }
}
