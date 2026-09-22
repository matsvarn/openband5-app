import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/day_label.dart';
import 'alp_tokens.dart';
import 'confirm_sheet.dart';
import 'domain.dart';
import 'health.dart' show OBSegmented;
import 'journal_controls.dart';
import 'notification_settings.dart';
import 'settings_controls.dart';
import 'theme.dart';
import 'time.dart';
import 'time_picker.dart';

const _kMedInfoTitle = 'Einträge und Pläne';
const _kMedInfoBody =
    'Ein fehlender Eintrag sagt nicht, ob du ein Medikament genommen hast.\n\n'
    'Planänderungen gelten ab dem Speichern. Frühere Pläne werden nur angezeigt, wenn sie gespeichert sind.\n\n'
    'Zeiten folgen der Ortszeit des Telefons. Bei einer nicht eindeutigen Uhrzeit durch die Zeitumstellung wird keine Erinnerung geplant.\n\n'
    'Erinnerungen hängen von den Systemeinstellungen ab. OpenBand prüft keine Dosierung oder Wechselwirkungen.';

const _kWeekdays = [
  'Montag',
  'Dienstag',
  'Mittwoch',
  'Donnerstag',
  'Freitag',
  'Samstag',
  'Sonntag',
];
const _kWeekdayShort = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

class OpenBandMedications extends StatefulWidget {
  final OpenBandRepository repository;
  final String day;
  final DateTime Function()? now;
  final bool synthetic;

  const OpenBandMedications({
    super.key,
    required this.repository,
    required this.day,
    this.now,
    this.synthetic = false,
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
        builder: (_) => OpenBandMedications(
          repository: repository,
          day: day,
          now: now,
          synthetic: synthetic,
        ),
      ),
    );
  }

  @override
  State<OpenBandMedications> createState() => _OpenBandMedicationsState();
}

class _OpenBandMedicationsState extends State<OpenBandMedications> {
  late String _day = widget.day;
  MedicationDay? _snapshot;
  List<MedicationPlan>? _plans;
  bool _loading = true;
  bool _readError = false;
  bool _saved = false;
  bool _remindersFailed = false;
  int _gen = 0;

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool keepSaved = false}) async {
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _readError = false;
      if (!keepSaved) _saved = false;
    });
    MedicationDay? day;
    List<MedicationPlan>? plans;
    var dayFailed = false;
    var plansFailed = false;
    try {
      day = await widget.repository.readMedicationDay(_day, now: _now());
    } catch (_) {
      dayFailed = true;
    }
    try {
      plans = await widget.repository.readMedicationPlans(activeOnly: false);
    } catch (_) {
      plansFailed = true;
    }
    if (!mounted || gen != _gen) return;
    setState(() {
      _loading = false;
      if (dayFailed) {
        _readError = true;
      } else {
        _snapshot = day;
        _readError = false;
      }
      if (!plansFailed) _plans = plans;
    });
  }

  Future<void> _pickDay() async {
    final current = DateTime.parse(_day);
    final clock = _now();
    final picked = await showDatePicker(
      context: context,
      locale: const Locale('de'),
      initialDate: current,
      firstDate: DateTime(clock.year - 20),
      lastDate: DateTime(clock.year + 2, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() => _day = dayLabelOf(picked));
    await _load();
  }

  Future<void> _openRecord(MedicationDayEntry entry) async {
    final outcome = await Navigator.of(context).push<_MedWriteOutcome>(
      MaterialPageRoute(
        builder: (_) => _MedicationRecord(
          repository: widget.repository,
          entry: entry,
          now: _now,
          synthetic: widget.synthetic,
        ),
      ),
    );
    if (!mounted || outcome == null) return;
    setState(() {
      _saved = true;
      _remindersFailed = outcome.remindersFailed;
    });
    await _load(keepSaved: true);
  }

  Future<void> _openHistory() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _MedicationHistory(
          repository: widget.repository,
          day: _day,
          now: _now,
          synthetic: widget.synthetic,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openPlans() async {
    final outcome = await Navigator.of(context).push<_MedWriteOutcome>(
      MaterialPageRoute(
        builder: (_) => _MedicationPlans(
          repository: widget.repository,
          now: _now,
          synthetic: widget.synthetic,
        ),
      ),
    );
    if (!mounted) return;
    if (outcome != null) {
      setState(() => _remindersFailed = outcome.remindersFailed);
    }
    await _load();
  }

  Future<void> _openEditor({MedicationPlan? plan}) async {
    final outcome = await Navigator.of(context).push<_MedWriteOutcome>(
      MaterialPageRoute(
        builder: (_) => _MedicationPlanEditor(
          repository: widget.repository,
          plan: plan,
          now: _now,
          synthetic: widget.synthetic,
        ),
      ),
    );
    if (!mounted || outcome == null) return;
    setState(() => _remindersFailed = outcome.remindersFailed);
    await _load();
  }

  Future<void> _retryReminders() async {
    try {
      await widget.repository.refreshMedicationReminders();
      if (!mounted) return;
      setState(() => _remindersFailed = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _remindersFailed = true);
    }
  }

  void _info() => showOpenBandJournalInfo(
    context,
    title: _kMedInfoTitle,
    body: _kMedInfoBody,
  );

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final entries = [...?_snapshot?.entries]
      ..sort((a, b) {
        final t = a.slotMin.compareTo(b.slotMin);
        return t != 0 ? t : a.key.compareTo(b.key);
      });
    final today = dayLabelOf(_now());
    final plans = _plans;
    final noPlans = plans != null && plans.isEmpty;
    final noSlot = plans != null && plans.isNotEmpty && entries.isEmpty;
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: ListView(
          key: const ValueKey('medication-main'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            OBPageHeader(
              title: 'Medikamente',
              subtitle: '',
              onInfo: _info,
            ),
            const SizedBox(height: 0),
            _MedDateRow(day: _day, now: _now(), onPick: _pickDay),
            const SizedBox(height: 12),
            if (_remindersFailed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _MedWarning(
                  'Gespeichert · Erinnerungen nicht aktualisiert',
                  action: 'Erneut versuchen',
                  onAction: _retryReminders,
                ),
              ),
            if (_snapshot != null && _snapshot!.unreadableCount > 0)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: _MedWarning('Nicht alle Einträge lesbar'),
              ),
            if (_readError)
              _MedErrorCard(
                'Medikamente konnten nicht geladen werden.',
                onRetry: _load,
                saved: _saved,
              )
            else if (_loading && _snapshot == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator.adaptive()),
              )
            else if (noPlans && entries.isEmpty)
              const _MedEmptyCard('Keine Medikamente')
            else if (noSlot || entries.isEmpty)
              const _MedEmptyCard('Keine Einnahme geplant')
            else
              OBCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (i, e) in entries.indexed) ...[
                      if (i > 0) const _MedHairline(),
                      _MedDoseRow(
                        entry: e,
                        today: today,
                        onTap: () => _openRecord(e),
                      ),
                    ],
                  ],
                ),
              ),
            if (!_readError) ...[
              const SizedBox(height: 12),
              OBCard(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    OBSettingsValueRow(
                      label: 'Verlauf',
                      value: '',
                      chevron: true,
                      onTap: _openHistory,
                    ),
                    OBSettingsValueRow(
                      label: 'Pläne verwalten',
                      value: '',
                      chevron: true,
                      onTap: _openPlans,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OBAction(
                'Medikament hinzufügen',
                ink: true,
                onPressed: () => _openEditor(),
              ),
            ],
            if (widget.synthetic) const _MedSyntheticFooter(),
          ],
        ),
      ),
    );
  }
}

class _MedWriteOutcome {
  const _MedWriteOutcome({this.remindersFailed = false});
  final bool remindersFailed;
}

class _MedicationRecord extends StatefulWidget {
  final OpenBandRepository repository;
  final MedicationDayEntry entry;
  final DateTime Function() now;
  final bool synthetic;
  const _MedicationRecord({
    required this.repository,
    required this.entry,
    required this.now,
    required this.synthetic,
  });
  @override
  State<_MedicationRecord> createState() => _MedicationRecordState();
}

class _MedicationRecordState extends State<_MedicationRecord> {
  late int _selected = switch (widget.entry.status) {
    MedicationSlotStatus.taken => 0,
    MedicationSlotStatus.skipped => 1,
    _ => -1,
  };
  late DateTime? _takenAt = widget.entry.takenAt;
  late final DateTime? _originalTaken = widget.entry.takenAt;
  late int _civilYear;
  late int _civilMonth;
  late int _civilDay;
  late int _hour;
  late int _minute;
  late bool _offsetUnknown;
  var _clockDirty = false;
  late final _note = TextEditingController(text: widget.entry.note);
  bool _saving = false;
  String? _error;
  String? _timeError;

  bool get _stored =>
      widget.entry.status == MedicationSlotStatus.taken ||
      widget.entry.status == MedicationSlotStatus.skipped;

  @override
  void initState() {
    super.initState();
    final shown = medicationTakenDisplay(widget.entry);
    if (shown != null) {
      _civilYear = shown.year;
      _civilMonth = shown.month;
      _civilDay = shown.day;
      _hour = shown.hour;
      _minute = shown.minute;
      _offsetUnknown = shown.offsetUnknown;
    } else {
      final n = widget.now();
      _civilYear = n.year;
      _civilMonth = n.month;
      _civilDay = n.day;
      _hour = n.hour;
      _minute = n.minute;
      _offsetUnknown = false;
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _armTakenClock(DateTime n) {
    _civilYear = n.year;
    _civilMonth = n.month;
    _civilDay = n.day;
    _hour = n.hour;
    _minute = n.minute;
    _offsetUnknown = false;
    _clockDirty = true;
    _takenAt = resolveMedicationTakenAt(
          year: n.year,
          month: n.month,
          day: n.day,
          hour: n.hour,
          minute: n.minute,
        ) ??
        n;
  }

  void _select(int i) {
    setState(() {
      _error = null;
      _timeError = null;
      if (_selected == i) {
        _selected = -1;
        return;
      }
      _selected = i;
      if (i == 0 && _takenAt == null) _armTakenClock(widget.now());
    });
  }

  Future<void> _pickTakenDate() async {
    final clock = widget.now();
    final last = DateTime(clock.year, clock.month, clock.day);
    var initial = DateTime(_civilYear, _civilMonth, _civilDay);
    if (initial.isAfter(last)) initial = last;
    final first = DateTime(clock.year - 20);
    if (initial.isBefore(first)) initial = first;
    final picked = await showDatePicker(
      context: context,
      locale: const Locale('de'),
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked == null || !mounted) return;
    _applyTakenClock(
      year: picked.year,
      month: picked.month,
      day: picked.day,
      hour: _hour,
      minute: _minute,
    );
  }

  Future<void> _pickTakenTime() async {
    final picked = await showOpenBandTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _hour, minute: _minute),
    );
    if (picked == null || !mounted) return;
    _applyTakenClock(
      year: _civilYear,
      month: _civilMonth,
      day: _civilDay,
      hour: picked.hour,
      minute: picked.minute,
    );
  }

  void _applyTakenClock({
    required int year,
    required int month,
    required int day,
    required int hour,
    required int minute,
  }) {
    final parsed = resolveMedicationTakenAt(
      year: year,
      month: month,
      day: day,
      hour: hour,
      minute: minute,
      previous: _originalTaken,
    );
    if (parsed == null) {
      setState(() {
        _civilYear = year;
        _civilMonth = month;
        _civilDay = day;
        _hour = hour;
        _minute = minute;
        _clockDirty = true;
        _timeError = 'Uhrzeit nicht eindeutig';
      });
      return;
    }
    setState(() {
      _civilYear = year;
      _civilMonth = month;
      _civilDay = day;
      _hour = hour;
      _minute = minute;
      _takenAt = parsed;
      _clockDirty = true;
      _offsetUnknown = false;
      _timeError = null;
    });
  }

  Future<void> _save({required MedicationEntryAnswer answer}) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final taken = answer == MedicationEntryAnswer.taken
          ? (!_clockDirty && _originalTaken != null ? _originalTaken : _takenAt)
          : null;
      final result = await widget.repository.saveMedicationEntry(
        MedicationEntryDraft(
          key: widget.entry.key,
          date: widget.entry.date,
          slotMin: widget.entry.slotMin,
          answer: answer,
          takenAt: taken,
          note: _note.text.trim(),
        ),
        now: widget.now(),
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        _MedWriteOutcome(remindersFailed: result.remindersFailed),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Speichern fehlgeschlagen';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final e = widget.entry;
    final copy = _entryCopy(e);
    final dose = _doseText(e.snapshotDoseValue, e.snapshotDoseUnit);
    final canSave = _selected >= 0 && _timeError == null;
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: ListView(
          key: const ValueKey('medication-record'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const OBPageHeader(title: 'Einnahme', subtitle: ''),
            OBCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    copy.title,
                    style: p
                        .text(28, weight: FontWeight.w700, display: true)
                        .copyWith(height: 34 / 28),
                  ),
                  if (dose != null) ...[
                    const SizedBox(height: 6),
                    Text(dose, style: p.text(15).copyWith(height: 20 / 15)),
                  ],
                  if (copy.missing != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      copy.missing!,
                      style: p.text(13).copyWith(height: 18 / 13),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    '${DateFormat('d. MMM', 'de_DE').format(DateTime.parse(e.date))} · geplant ${e.timeLabel}',
                    style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
                  ),
                  if (copy.tag != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      copy.tag!,
                      style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            OBSegmented(
              labels: const ['Genommen', 'Ausgelassen'],
              selected: _selected,
              onChanged: _select,
            ),
            if (_selected == 0) ...[
              const SizedBox(height: 12),
              _TakenWhenRow(
                year: _civilYear,
                month: _civilMonth,
                day: _civilDay,
                hour: _hour,
                minute: _minute,
                offsetUnknown: _offsetUnknown,
                onDate: _pickTakenDate,
                onTime: _pickTakenTime,
              ),
              if (_timeError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _timeError!,
                    style: p.text(14, color: p.danger).copyWith(height: 20 / 14),
                  ),
                ),
            ],
            const SizedBox(height: 12),
            _MedNoteField(controller: _note),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _MedSaveError(_error!),
            ],
            const SizedBox(height: 12),
            OBAction(
              'Speichern',
              ink: true,
              onPressed: canSave && !_saving
                  ? () => _save(
                      answer: _selected == 0
                          ? MedicationEntryAnswer.taken
                          : MedicationEntryAnswer.skipped,
                    )
                  : null,
            ),
            if (_stored) ...[
              const SizedBox(height: 12),
              OBAction(
                'Eintrag entfernen',
                ink: true,
                secondary: true,
                onPressed: _saving
                    ? null
                    : () => _save(answer: MedicationEntryAnswer.clear),
              ),
            ],
            if (widget.synthetic) const _MedSyntheticFooter(),
          ],
        ),
      ),
    );
  }
}

class _MedicationHistory extends StatefulWidget {
  final OpenBandRepository repository;
  final String day;
  final DateTime Function() now;
  final bool synthetic;
  const _MedicationHistory({
    required this.repository,
    required this.day,
    required this.now,
    required this.synthetic,
  });
  @override
  State<_MedicationHistory> createState() => _MedicationHistoryState();
}

class _MedicationHistoryState extends State<_MedicationHistory> {
  final _entries = <MedicationDayEntry>[];
  final _seen = <String>{};
  String? _from;
  var _unreadable = 0;
  var _loading = true;
  var _error = false;
  var _loadingOlder = false;
  var _olderError = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadInitial());
  }

  String _shift(String day, int days) {
    final d = DateTime.parse(day);
    return dayLabelOf(DateTime(d.year, d.month, d.day + days));
  }

  String _id(MedicationDayEntry e) => '${e.key}|${e.date}|${e.slotMin}';

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    final to = widget.day;
    final from = _shift(to, -29);
    try {
      final hist = await widget.repository.readMedicationHistory(
        from,
        to,
        now: widget.now(),
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _from = hist.fromDay;
        _unreadable = hist.unreadableCount;
        for (final e in hist.entries) {
          final id = _id(e);
          if (_seen.add(id)) _entries.add(e);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _loadOlder() async {
    final from = _from;
    if (from == null || _loadingOlder) return;
    setState(() {
      _loadingOlder = true;
      _olderError = false;
    });
    final to = _shift(from, -1);
    final nextFrom = _shift(to, -29);
    try {
      final hist = await widget.repository.readMedicationHistory(
        nextFrom,
        to,
        now: widget.now(),
      );
      if (!mounted) return;
      setState(() {
        _loadingOlder = false;
        _from = hist.fromDay;
        _unreadable += hist.unreadableCount;
        for (final e in hist.entries) {
          final id = _id(e);
          if (_seen.add(id)) _entries.add(e);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingOlder = false;
        _olderError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final today = dayLabelOf(widget.now());
    final groups = <String, List<MedicationDayEntry>>{};
    for (final e in _entries) {
      (groups[e.date] ??= []).add(e);
    }
    final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final list in groups.values) {
      list.sort((a, b) {
        final t = a.slotMin.compareTo(b.slotMin);
        return t != 0 ? t : a.key.compareTo(b.key);
      });
    }
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: ListView(
          key: const ValueKey('medication-history'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            OBPageHeader(
              title: 'Verlauf',
              subtitle: '',
              onInfo: () => showOpenBandJournalInfo(
                context,
                title: _kMedInfoTitle,
                body: _kMedInfoBody,
              ),
            ),
            if (_unreadable > 0)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: _MedWarning('Nicht alle Einträge lesbar'),
              ),
            if (_error && _entries.isEmpty)
              _MedErrorCard(
                'Medikamente konnten nicht geladen werden.',
                onRetry: _loadInitial,
              )
            else if (_loading && _entries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator.adaptive()),
              )
            else if (!_loading && _entries.isEmpty)
              const _MedEmptyCard('Keine Einträge')
            else ...[
              for (final day in days) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 12, top: 8),
                  child: Text(
                    _historyDayTitle(day, widget.now()),
                    style: p
                        .text(20, weight: FontWeight.w700, display: true)
                        .copyWith(height: 26 / 20),
                  ),
                ),
                OBCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final (i, e) in groups[day]!.indexed) ...[
                        if (i > 0) const _MedHairline(),
                        _MedDoseRow(entry: e, today: today),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (_olderError)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _MedErrorCard(
                    'Medikamente konnten nicht geladen werden.',
                    onRetry: _loadOlder,
                  ),
                ),
              OBAction(
                'Ältere Einträge',
                ink: true,
                secondary: true,
                onPressed: _loadingOlder ? null : _loadOlder,
              ),
            ],
            if (widget.synthetic) const _MedSyntheticFooter(),
          ],
        ),
      ),
    );
  }
}

class _MedicationPlans extends StatefulWidget {
  final OpenBandRepository repository;
  final DateTime Function() now;
  final bool synthetic;
  const _MedicationPlans({
    required this.repository,
    required this.now,
    required this.synthetic,
  });
  @override
  State<_MedicationPlans> createState() => _MedicationPlansState();
}

class _MedicationPlansState extends State<_MedicationPlans> {
  List<MedicationPlan>? _plans;
  var _loading = true;
  var _error = false;
  var _remindersFailed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final plans = await widget.repository.readMedicationPlans(activeOnly: false);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _plans = plans;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _openEditor({MedicationPlan? plan}) async {
    final outcome = await Navigator.of(context).push<_MedWriteOutcome>(
      MaterialPageRoute(
        builder: (_) => _MedicationPlanEditor(
          repository: widget.repository,
          plan: plan,
          now: widget.now,
          synthetic: widget.synthetic,
        ),
      ),
    );
    if (!mounted) return;
    if (outcome != null) {
      setState(() => _remindersFailed = outcome.remindersFailed);
    }
    await _load();
  }

  Future<void> _openEnded(List<MedicationPlan> ended) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _MedicationEnded(
          plans: ended,
          onOpen: (plan) => _openEditor(plan: plan),
          onAdd: () => _openEditor(),
          synthetic: widget.synthetic,
        ),
      ),
    );
    if (mounted) await _load();
  }

  void _openReminders() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => NotificationSettings(
          synthetic: widget.synthetic,
          loadPrefs: widget.synthetic
              ? () async => openBandPaperNotificationPrefs
              : null,
          readPermission: widget.synthetic ? () async => true : null,
          persistPrefs: widget.synthetic ? (_) async {} : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final plans = _plans ?? const <MedicationPlan>[];
    final active = [for (final plan in plans) if (plan.active) plan];
    final ended = [for (final plan in plans) if (!plan.active) plan];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.pop(
          context,
          _remindersFailed
              ? const _MedWriteOutcome(remindersFailed: true)
              : null,
        );
      },
      child: Scaffold(
        backgroundColor: p.canvas,
        body: SafeArea(
          child: ListView(
            key: const ValueKey('medication-plans'),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              OBPageHeader(
                title: 'Pläne',
                subtitle: '',
                onInfo: () => showOpenBandJournalInfo(
                  context,
                  title: _kMedInfoTitle,
                  body: _kMedInfoBody,
                ),
              ),
              if (_remindersFailed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _MedWarning(
                    'Gespeichert · Erinnerungen nicht aktualisiert',
                    action: 'Erneut versuchen',
                    onAction: () async {
                      try {
                        await widget.repository.refreshMedicationReminders();
                        if (mounted) setState(() => _remindersFailed = false);
                      } catch (_) {}
                    },
                  ),
                ),
              if (_error)
                _MedErrorCard(
                  'Medikamente konnten nicht geladen werden.',
                  onRetry: _load,
                )
              else if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator.adaptive()),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 12),
                  child: Text(
                    'Aktiv',
                    style: p
                        .text(20, weight: FontWeight.w700, display: true)
                        .copyWith(height: 26 / 20),
                  ),
                ),
                if (active.isEmpty)
                  const _MedEmptyCard('Keine Medikamente')
                else
                  OBCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final (i, plan) in active.indexed) ...[
                          if (i > 0) const _MedHairline(),
                          _MedPlanRow(
                            plan: plan,
                            onTap: () => _openEditor(plan: plan),
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                OBCard(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      OBSettingsValueRow(
                        label: 'Erinnerungen',
                        value: '',
                        chevron: true,
                        onTap: _openReminders,
                      ),
                      OBSettingsValueRow(
                        label: 'Beendete Pläne',
                        value: '',
                        chevron: true,
                        onTap: () => _openEnded(ended),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                OBAction(
                  'Medikament hinzufügen',
                  ink: true,
                  onPressed: () => _openEditor(),
                ),
              ],
              if (widget.synthetic) const _MedSyntheticFooter(),
            ],
          ),
        ),
      ),
    );
  }
}

class _MedicationEnded extends StatelessWidget {
  final List<MedicationPlan> plans;
  final ValueChanged<MedicationPlan> onOpen;
  final VoidCallback onAdd;
  final bool synthetic;
  const _MedicationEnded({
    required this.plans,
    required this.onOpen,
    required this.onAdd,
    required this.synthetic,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: ListView(
          key: const ValueKey('medication-ended'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            OBPageHeader(
              title: 'Beendete Pläne',
              subtitle: '',
              onInfo: () => showOpenBandJournalInfo(
                context,
                title: _kMedInfoTitle,
                body: _kMedInfoBody,
              ),
            ),
            if (plans.isEmpty)
              const _MedEmptyCard('Keine Medikamente')
            else
              OBCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (i, plan) in plans.indexed) ...[
                      if (i > 0) const _MedHairline(),
                      _MedPlanRow(plan: plan, onTap: () => onOpen(plan)),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 12),
            OBAction(
              'Medikament hinzufügen',
              ink: true,
              onPressed: onAdd,
            ),
            if (synthetic) const _MedSyntheticFooter(),
          ],
        ),
      ),
    );
  }
}

class _MedicationPlanEditor extends StatefulWidget {
  final OpenBandRepository repository;
  final MedicationPlan? plan;
  final DateTime Function() now;
  final bool synthetic;
  const _MedicationPlanEditor({
    required this.repository,
    required this.plan,
    required this.now,
    required this.synthetic,
  });
  @override
  State<_MedicationPlanEditor> createState() => _MedicationPlanEditorState();
}

class _MedicationPlanEditorState extends State<_MedicationPlanEditor> {
  late final bool _create = widget.plan == null || widget.plan!.key.isEmpty;
  late final String? _key = _create ? null : widget.plan!.key;
  late final _name = TextEditingController(text: widget.plan?.name ?? '');
  late final double? _storedDose = widget.plan?.doseValue;
  late final String _doseSeed =
      _storedDose == null ? '' : _formatDoseValue(_storedDose);
  late final _dose = TextEditingController(text: _doseSeed);
  late final _unit = TextEditingController(text: widget.plan?.doseUnit ?? '');
  late final _note = TextEditingController(text: widget.plan?.note ?? '');
  late MedicationKind _kind = widget.plan?.kind ?? MedicationKind.medication;
  late List<MedicationScheduleSlot> _schedule = [
    ...?widget.plan?.schedule,
  ];
  late final bool _ended = widget.plan?.active == false;
  var _dirty = false;
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    _unit.dispose();
    _note.dispose();
    super.dispose();
  }

  void _mark() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty || _saving) return true;
    final discard = await showOpenBandConfirmSheet(
      context: context,
      title: 'Änderungen verwerfen?',
    );
    return discard == true;
  }

  MedicationPlanDraft _draft({required bool active}) {
    final doseRaw = _dose.text.trim();
    final double? dose;
    if (doseRaw.isEmpty) {
      dose = null;
    } else if (doseRaw == _doseSeed && _storedDose != null) {
      dose = _storedDose;
    } else {
      dose = double.tryParse(doseRaw.replaceAll(',', '.'));
    }
    final unit = _unit.text.trim();
    return MedicationPlanDraft(
      create: _create,
      key: _key,
      name: _name.text,
      doseValue: dose,
      doseUnit: unit.isEmpty ? null : unit,
      kind: _kind,
      note: _note.text,
      schedule: _schedule,
      active: active,
    );
  }

  String? _doseError() {
    final raw = _dose.text.trim();
    if (raw.isEmpty) return null;
    final value = double.tryParse(raw.replaceAll(',', '.'));
    if (value == null || !value.isFinite || value <= 0) return 'Menge ungültig';
    return null;
  }

  Future<void> _save({required bool active}) async {
    if (_saving) return;
    final doseError = _doseError();
    if (doseError != null) {
      setState(() => _error = doseError);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.repository.saveMedicationPlan(
        _draft(active: active),
        now: widget.now(),
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        _MedWriteOutcome(remindersFailed: result.remindersFailed),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Speichern fehlgeschlagen';
      });
    }
  }

  Future<void> _end() async {
    if (_saving || _key == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.repository.endMedicationPlan(
        _key,
        now: widget.now(),
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        _MedWriteOutcome(remindersFailed: result.remindersFailed),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Speichern fehlgeschlagen';
      });
    }
  }

  Future<void> _restart() async {
    if (_saving || _key == null) return;
    await _save(active: true);
  }

  Future<void> _editSlot(int? index) async {
    final initial = index == null
        ? const MedicationScheduleSlot(minuteOfDay: 8 * 60)
        : _schedule[index];
    final slot = await Navigator.of(context).push<MedicationScheduleSlot>(
      MaterialPageRoute(
        builder: (_) => _MedicationTimeEditor(
          slot: initial,
          takenMinutes: {
            for (final (i, s) in _schedule.indexed)
              if (i != index) s.minuteOfDay,
          },
          synthetic: widget.synthetic,
        ),
      ),
    );
    if (slot == null || !mounted) return;
    setState(() {
      _dirty = true;
      if (index == null) {
        _schedule = [..._schedule, slot];
      } else {
        _schedule = [..._schedule]..[index] = slot;
      }
    });
  }

  Future<void> _pickKind() async {
    final chosen = await showModalBottomSheet<MedicationKind>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final p = OB.of(context);
        return Material(
          color: p.card,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AlpRadius.card),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final kind in MedicationKind.values)
                    OBSettingsChoiceRow(
                      label: _kindLabel(kind),
                      selected: kind == _kind,
                      onTap: () => Navigator.pop(context, kind),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (chosen == null || !mounted) return;
    setState(() {
      _kind = chosen;
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final title = _create
        ? 'Medikament hinzufügen'
        : _ended
        ? 'Plan fortsetzen'
        : 'Plan bearbeiten';
    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!await _confirmLeave()) return;
        if (context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: p.canvas,
        body: SafeArea(
          child: ListView(
            key: const ValueKey('medication-editor'),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              OBPageHeader(
                title: title,
                subtitle: '',
                onBack: () async {
                  if (_dirty && !await _confirmLeave()) return;
                  if (context.mounted) Navigator.pop(context);
                },
              ),
              OBCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _MedLabeledField(
                      label: 'Name',
                      child: TextField(
                        key: const ValueKey('medication-name'),
                        controller: _name,
                        style: p.text(17).copyWith(height: 22 / 17),
                        decoration: _wellDecoration(p),
                        onChanged: (_) => _mark(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Builder(
                      builder: (context) {
                        final menge = _MedLabeledField(
                          label: 'Menge · optional',
                          child: TextField(
                            key: const ValueKey('medication-dose'),
                            controller: _dose,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            style: p.text(20).copyWith(height: 24 / 20),
                            decoration: _wellDecoration(p),
                            onChanged: (_) => _mark(),
                          ),
                        );
                        final einheit = _MedLabeledField(
                          label: 'Einheit',
                          child: TextField(
                            key: const ValueKey('medication-unit'),
                            controller: _unit,
                            style: p.text(17).copyWith(height: 24 / 17),
                            decoration: _wellDecoration(p),
                            onChanged: (_) => _mark(),
                          ),
                        );
                        if (_medStack(context)) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              menge,
                              const SizedBox(height: 12),
                              einheit,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: menge),
                            const SizedBox(width: 12),
                            SizedBox(width: 112, child: einheit),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    OBSettingsValueRow(
                      label: 'Art',
                      value: _kindLabel(_kind),
                      chevron: true,
                      mutedValue: true,
                      onTap: _pickKind,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OBCard(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    for (final (i, slot) in _schedule.indexed)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _editSlot(i),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 64),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 14,
                              ),
                              child: _medStack(context)
                                  ? Wrap(
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      spacing: 12,
                                      runSpacing: 4,
                                      children: [
                                        Text(
                                          medicationTimeLabel(slot.minuteOfDay),
                                          style: p
                                              .text(
                                                24,
                                                weight: FontWeight.w600,
                                                display: true,
                                              )
                                              .copyWith(height: 30 / 24),
                                        ),
                                        Text(
                                          _slotDays(slot),
                                          style: p
                                              .text(14, color: p.muted)
                                              .copyWith(height: 20 / 14),
                                        ),
                                        Icon(
                                          LucideIcons.chevronRight,
                                          size: 18,
                                          color: p.muted,
                                        ),
                                      ],
                                    )
                                  : Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            medicationTimeLabel(
                                              slot.minuteOfDay,
                                            ),
                                            style: p
                                                .text(
                                                  24,
                                                  weight: FontWeight.w600,
                                                  display: true,
                                                )
                                                .copyWith(height: 30 / 24),
                                          ),
                                        ),
                                        Text(
                                          _slotDays(slot),
                                          style: p
                                              .text(14, color: p.muted)
                                              .copyWith(height: 20 / 14),
                                        ),
                                        const SizedBox(width: 8),
                                        Icon(
                                          LucideIcons.chevronRight,
                                          size: 18,
                                          color: p.muted,
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _editSlot(null),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 14,
                            ),
                            child: Row(
                              children: [
                                Icon(LucideIcons.plus, size: 20, color: p.ink),
                                const SizedBox(width: 10),
                                Text(
                                  'Zeit hinzufügen',
                                  style: p
                                      .text(15, weight: FontWeight.w500)
                                      .copyWith(height: 20 / 15),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _MedNoteField(controller: _note, onChanged: (_) => _mark()),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _MedSaveError(_error!),
              ],
              const SizedBox(height: 12),
              if (_ended)
                OBAction(
                  'Plan fortsetzen',
                  ink: true,
                  onPressed: _saving ? null : _restart,
                )
              else
                OBAction(
                  'Speichern',
                  ink: true,
                  onPressed: _saving ? null : () => _save(active: true),
                ),
              if (!_create && !_ended) ...[
                const SizedBox(height: 12),
                OBAction(
                  'Plan beenden',
                  ink: true,
                  secondary: true,
                  destructive: true,
                  onPressed: _saving ? null : _end,
                ),
              ],
              if (widget.synthetic) const _MedSyntheticFooter(),
            ],
          ),
        ),
      ),
    );
  }
}

class _MedicationTimeEditor extends StatefulWidget {
  final MedicationScheduleSlot slot;
  final Set<int> takenMinutes;
  final bool synthetic;
  const _MedicationTimeEditor({
    required this.slot,
    required this.takenMinutes,
    required this.synthetic,
  });
  @override
  State<_MedicationTimeEditor> createState() => _MedicationTimeEditorState();
}

class _MedicationTimeEditorState extends State<_MedicationTimeEditor> {
  late int _minute = widget.slot.minuteOfDay;
  late Set<int> _days = widget.slot.weekdays.isEmpty
      ? {1, 2, 3, 4, 5, 6, 7}
      : {...widget.slot.weekdays};
  String? _error;

  List<int> _wiredDays() {
    if (_days.length == 7) return const [];
    return (_days.toList()..sort());
  }

  void _discard() {
    Navigator.pop(context);
  }

  void _confirm() {
    if (_days.isEmpty) {
      setState(() => _error = 'Mindestens ein Wochentag.');
      return;
    }
    if (widget.takenMinutes.contains(_minute)) {
      setState(() => _error = 'Zeit ist bereits vorhanden.');
      return;
    }
    Navigator.pop(
      context,
      MedicationScheduleSlot(minuteOfDay: _minute, weekdays: _wiredDays()),
    );
  }

  Future<void> _pickTime() async {
    final picked = await showOpenBandTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _minute ~/ 60, minute: _minute % 60),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _minute = picked.hour * 60 + picked.minute;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: ListView(
          key: const ValueKey('medication-time'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            OBPageHeader(title: 'Zeit', subtitle: '', onBack: _discard),
              OBCard(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: _medStack(context)
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Uhrzeit',
                            style: p.text(15).copyWith(height: 20 / 15),
                          ),
                          const SizedBox(height: 12),
                          _TimeWell(
                            label: medicationTimeLabel(_minute),
                            onTap: _pickTime,
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Uhrzeit',
                              style: p.text(15).copyWith(height: 20 / 15),
                            ),
                          ),
                          _TimeWell(
                            label: medicationTimeLabel(_minute),
                            onTap: _pickTime,
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              OBCard(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    for (var i = 1; i <= 7; i++)
                      OBSettingsToggleRow(
                        label: _kWeekdays[i - 1],
                        value: _days.contains(i),
                        onToggle: () => setState(() {
                          if (_days.contains(i)) {
                            _days = {..._days}..remove(i);
                          } else {
                            _days = {..._days, i};
                          }
                          _error = null;
                        }),
                      ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _MedSaveError(_error!),
              ],
              const SizedBox(height: 12),
              OBAction('Speichern', ink: true, onPressed: _confirm),
              if (widget.synthetic) const _MedSyntheticFooter(),
            ],
          ),
        ),
    );
  }
}

class _MedDateRow extends StatelessWidget {
  final String day;
  final DateTime now;
  final VoidCallback onPick;
  const _MedDateRow({required this.day, required this.now, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final date = DateTime.parse(day);
    final fmt = date.year == now.year
        ? DateFormat('EEE, d. MMM', 'de_DE')
        : DateFormat('EEE, d. MMM y', 'de_DE');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            Expanded(
              child: Text(
                fmt.format(date),
                style: p
                    .text(24, weight: FontWeight.w700, display: true)
                    .copyWith(height: 30 / 24),
              ),
            ),
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                key: const ValueKey('medication-date'),
                tooltip: 'Datum',
                onPressed: onPick,
                icon: Icon(LucideIcons.calendar, size: 20, color: p.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MedDoseRow extends StatelessWidget {
  final MedicationDayEntry entry;
  final String today;
  final VoidCallback? onTap;
  const _MedDoseRow({required this.entry, required this.today, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final stacked = _medStack(context);
    final copy = _entryCopy(entry);
    final dose = _doseText(entry.snapshotDoseValue, entry.snapshotDoseUnit);
    final status = _statusLabel(entry, today);
    final unavailable = entry.status == MedicationSlotStatus.unavailable;
    final time = Text(
      entry.timeLabel,
      style: p
          .text(18, weight: FontWeight.w600, display: true)
          .copyWith(
            height: 22 / 18,
            fontVariations: const [FontVariation('wght', 650)],
          ),
    );
    final chevron = SizedBox(
      width: 24,
      child: Align(
        alignment: Alignment.centerRight,
        child: Icon(LucideIcons.chevronRight, size: 18, color: p.muted),
      ),
    );
    final name = Text(
      copy.title,
      style: p.text(16, weight: FontWeight.w600).copyWith(height: 21 / 16),
    );
    final detailStyle = p.text(13, color: p.muted).copyWith(height: 18 / 13);
    final detail = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (unavailable) ...[
          if (dose != null) Text(dose, style: detailStyle),
          if (copy.missing != null) Text(copy.missing!, style: detailStyle),
          Text(status, style: detailStyle),
        ] else
          Text(
            [
              ?dose,
              ?copy.missing,
              ?copy.tag,
              status,
            ].join(' · '),
            style: detailStyle,
          ),
      ],
    );
    final body = stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: time),
                  chevron,
                ],
              ),
              const SizedBox(height: 8),
              name,
              const SizedBox(height: 3),
              detail,
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(width: 52, child: time),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    name,
                    const SizedBox(height: 3),
                    detail,
                  ],
                ),
              ),
              chevron,
            ],
          );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 80),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: body,
          ),
        ),
      ),
    );
  }
}

class _MedPlanRow extends StatelessWidget {
  final MedicationPlan plan;
  final VoidCallback onTap;
  const _MedPlanRow({required this.plan, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final dose = _doseText(plan.doseValue, plan.doseUnit);
    final schedule = _planSchedule(plan);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 80),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.name,
                        style: p
                            .text(16, weight: FontWeight.w600)
                            .copyWith(height: 21 / 16),
                      ),
                      if (dose != null || schedule.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          [
                            ?dose,
                            if (schedule.isNotEmpty) schedule,
                          ].join(' · '),
                          style: p
                              .text(13, color: p.muted)
                              .copyWith(height: 18 / 13),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(
                  width: 24,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Icon(LucideIcons.chevronRight, size: 18, color: p.muted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TakenWhenRow extends StatelessWidget {
  final int year;
  final int month;
  final int day;
  final int hour;
  final int minute;
  final bool offsetUnknown;
  final VoidCallback onDate;
  final VoidCallback onTime;
  const _TakenWhenRow({
    required this.year,
    required this.month,
    required this.day,
    required this.hour,
    required this.minute,
    required this.offsetUnknown,
    required this.onDate,
    required this.onTime,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final stacked = _medStack(context);
    final date = InkWell(
      key: const ValueKey('medication-taken-date'),
      onTap: onDate,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            DateFormat('d. MMM y', 'de_DE').format(DateTime(year, month, day)),
            style: p.text(15).copyWith(height: 20 / 15),
          ),
        ),
      ),
    );
    final clock = medicationTimeLabel(hour * 60 + minute);
    final time = _TimeWell(
      label: offsetUnknown ? '$clock UTC' : clock,
      onTap: onTime,
    );
    final zone = offsetUnknown
        ? Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Zeitzone nicht gespeichert',
              style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
            ),
          )
        : const SizedBox.shrink();
    return OBCard(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [date, const SizedBox(height: 12), time, zone],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: date),
                    time,
                  ],
                ),
                zone,
              ],
            ),
    );
  }
}

class _TimeWell extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _TimeWell({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Material(
      color: p.well,
      borderRadius: BorderRadius.circular(AlpRadius.well),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AlpRadius.well),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52, minWidth: 104),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Center(
              child: Text(
                label,
                style: p
                    .text(24, weight: FontWeight.w600, display: true)
                    .copyWith(height: 28 / 24),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MedNoteField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  const _MedNoteField({required this.controller, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return OBCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Notiz · optional',
            style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('medication-note'),
            controller: controller,
            minLines: 1,
            maxLines: 4,
            style: p.text(16).copyWith(height: 24 / 16),
            decoration: _wellDecoration(p, hint: '—'),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _MedLabeledField extends StatelessWidget {
  final String label;
  final Widget child;
  const _MedLabeledField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: p.text(13, color: p.muted).copyWith(height: 18 / 13)),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _MedEmptyCard extends StatelessWidget {
  final String label;
  const _MedEmptyCard(this.label);

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return OBCard(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Row(
          children: [
            Icon(LucideIcons.pill, size: 24, color: p.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: p.text(17, weight: FontWeight.w600).copyWith(height: 23 / 17),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MedErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final bool saved;
  const _MedErrorCard(this.message, {required this.onRetry, this.saved = false});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return OBCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (saved)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Gespeichert',
                style: p.text(15, weight: FontWeight.w600).copyWith(height: 21 / 15),
              ),
            ),
          Text(message, style: p.text(15).copyWith(height: 21 / 15)),
          const SizedBox(height: 12),
          OBAction('Erneut versuchen', ink: true, onPressed: onRetry),
        ],
      ),
    );
  }
}

class _MedWarning extends StatelessWidget {
  final String message;
  final String? action;
  final VoidCallback? onAction;
  const _MedWarning(this.message, {this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.warningTint,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            message,
            style: p.text(14, color: p.warning).copyWith(height: 20 / 14),
          ),
          if (action != null && onAction != null) ...[
            const SizedBox(height: 10),
            OBAction(action!, ink: true, secondary: true, onPressed: onAction),
          ],
        ],
      ),
    );
  }
}

class _MedSaveError extends StatelessWidget {
  final String message;
  const _MedSaveError(this.message);

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.dangerTint,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      child: Row(
        children: [
          Icon(LucideIcons.circleAlert, size: 18, color: p.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: p.text(14, color: p.danger).copyWith(height: 20 / 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _MedHairline extends StatelessWidget {
  const _MedHairline();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Divider(height: 1, thickness: 1, color: OB.of(context).line),
  );
}

class _MedSyntheticFooter extends StatelessWidget {
  const _MedSyntheticFooter();
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

InputDecoration _wellDecoration(OB p, {String? hint}) => InputDecoration(
  hintText: hint,
  hintStyle: p.text(16, color: p.muted).copyWith(height: 24 / 16),
  filled: true,
  fillColor: p.well,
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AlpRadius.well),
    borderSide: BorderSide.none,
  ),
  contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
);

bool _medStack(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(18) > 22;

({String title, String? tag, String? missing}) _entryCopy(MedicationDayEntry e) {
  final snap = e.snapshotLabel?.trim();
  final doseMissing =
      e.snapshotDoseValue == null &&
      (e.snapshotDoseUnit == null || e.snapshotDoseUnit!.trim().isEmpty);
  if (snap != null && snap.isNotEmpty) {
    return (title: snap, tag: null, missing: null);
  }
  final current = e.currentName?.trim();
  if (current != null && current.isNotEmpty) {
    return (
      title: current,
      tag: 'aktueller Name',
      missing: doseMissing ? 'Menge nicht gespeichert' : null,
    );
  }
  return (
    title: 'Medikament',
    tag: null,
    missing: doseMissing
        ? 'Name und Menge nicht gespeichert'
        : 'Name nicht gespeichert',
  );
}

String _formatDoseValue(double value) {
  if (!value.isFinite) return '';
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.round().toString();
  }
  return value.toString().replaceAll('.', ',');
}

String? _doseText(double? value, String? unit) {
  if (value == null && (unit == null || unit.isEmpty)) return null;
  final n = value == null ? null : _formatDoseValue(value);
  if (n != null && unit != null && unit.isNotEmpty) return '$n $unit';
  return n ?? unit;
}

String _statusLabel(MedicationDayEntry e, String today) {
  switch (e.status) {
    case MedicationSlotStatus.taken:
      final shown = medicationTakenDisplay(e);
      if (shown == null) return 'Genommen';
      final clock = medicationTimeLabel(shown.hour * 60 + shown.minute);
      if (shown.offsetUnknown) return 'Genommen $clock UTC';
      return 'Genommen $clock';
    case MedicationSlotStatus.skipped:
      return 'Ausgelassen';
    case MedicationSlotStatus.upcoming:
      return 'Später';
    case MedicationSlotStatus.unavailable:
      return 'Uhrzeit nicht eindeutig';
    case MedicationSlotStatus.unknown:
      return e.date.compareTo(today) < 0 ? 'Kein Eintrag' : 'Offen';
  }
}

String _kindLabel(MedicationKind kind) =>
    kind == MedicationKind.supplement ? 'Supplement' : 'Medikament';

String _slotDays(MedicationScheduleSlot slot) {
  if (slot.weekdays.isEmpty || slot.weekdays.length == 7) return 'Täglich';
  final days = [...slot.weekdays]..sort();
  return days.map((d) => _kWeekdayShort[d - 1]).join(', ');
}

String _planSchedule(MedicationPlan plan) {
  if (plan.schedule.isEmpty) return '';
  return [
    for (final s in plan.schedule)
      '${_slotDays(s)} ${medicationTimeLabel(s.minuteOfDay)}',
  ].join(', ');
}

String _historyDayTitle(String day, DateTime now) {
  final date = DateTime.parse(day);
  final fmt = date.year == now.year
      ? DateFormat('d. MMM', 'de_DE')
      : DateFormat('d. MMM y', 'de_DE');
  return fmt.format(date);
}

/// Civil day + HH:mm into [parseRecordedTime]. Never constructs a wall
/// DateTime(y, m, d, h, m) before validation — that normalizes DST gaps.
DateTime? resolveMedicationTakenAt({
  required int year,
  required int month,
  required int day,
  required int hour,
  required int minute,
  DateTime? previous,
  String? zone,
}) {
  final civil = DateTime(year, month, day);
  return parseRecordedTime(
    civil,
    medicationTimeLabel(hour * 60 + minute),
    previous: previous,
    zone: zone,
  );
}

/// Original saved local clock when [MedicationDayEntry.takenUtcOffsetMinutes]
/// is known. Unknown offset uses UTC digits and [offsetUnknown]; callers must
/// label that clock UTC and must not treat the phone timezone as recorded.
({int year, int month, int day, int hour, int minute, bool offsetUnknown})?
medicationTakenDisplay(MedicationDayEntry e) {
  final at = e.takenAt;
  if (at == null) return null;
  final offset = e.takenUtcOffsetMinutes;
  final wall = offset == null
      ? at.toUtc()
      : at.toUtc().add(Duration(minutes: offset));
  return (
    year: wall.year,
    month: wall.month,
    day: wall.day,
    hour: wall.hour,
    minute: wall.minute,
    offsetUnknown: offset == null,
  );
}
