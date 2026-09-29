import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../data/day_label.dart';
import '../../../data/journal_fields.dart';
import '../../controller.dart';
import '../../domain.dart';
import '../../journal_controls.dart' show kJournalMoodIcons;
import '../../journal_fields.dart' show journalFieldIcon;
import '../../tab_bar.dart' show kOBTabBarContentInset;
import '../chrome.dart'
    show
        OBBandCapsule,
        OBBandState,
        OBPageHeader,
        OBPanel,
        OBSectionHeader,
        OBSyncKind,
        OBSyncState;
import '../g3_theme.dart';
import '../journal_parts.dart';

const _questions = <_Question>[
  _Question(
    'alcohol_evening',
    'Gestern Abend Alkohol?',
    'Alkohol',
    _Answer.yesNo,
  ),
  _Question(
    'caffeine_late',
    'Koffein nach 14 Uhr?',
    'Koffein nach 14 Uhr',
    _Answer.yesNo,
  ),
  _Question('mood', 'Wie ist deine Stimmung heute?', 'Stimmung', _Answer.scale),
  _Question('', 'Möchtest du etwas notieren?', 'Notiz', _Answer.note),
];

String _patternFooter(G3JournalPattern result, {int? perSideMinimum}) {
  final p = result.pattern;
  if (p.kind == CaffeineSleepPatternKind.meaningful ||
      p.kind == CaffeineSleepPatternKind.nonmeaningful) {
    return '${p.pairedN} Tag-Nacht-Paare · Vergleich berechnet';
  }
  if (p.pairedN < result.pairedMinimum) {
    return '${p.pairedN} von ${result.pairedMinimum} Paaren · noch ${result.remaining}';
  }
  final history = RegExp(
    r'^need_history:have=(\d+),need=(\d+)$',
  ).firstMatch(p.note ?? '');
  if (history != null) {
    return '${history.group(1)} von ${history.group(2)} Paaren für den Test';
  }
  if (perSideMinimum != null && p.yesNights != null && p.noNights != null) {
    final yes = p.yesNights! < perSideMinimum
        ? '${p.yesNights} von $perSideMinimum nötig'
        : '${p.yesNights} vorhanden';
    final no = p.noNights! < perSideMinimum
        ? '${p.noNights} von $perSideMinimum nötig'
        : '${p.noNights} vorhanden';
    return '${p.pairedN} Paare · Ja $yes · Nein $no';
  }
  return '${p.pairedN} Paare · Ja ${p.yesNights ?? '—'} · Nein ${p.noNights ?? '—'}';
}

enum _Answer { yesNo, amount, scale, note }

class _Question {
  const _Question(this.key, this.prompt, this.title, this.kind);
  final String key, prompt, title;
  final _Answer kind;
}

class G3JournalScreen extends StatefulWidget {
  const G3JournalScreen({
    super.key,
    required this.controller,
    this.onEdit,
    this.onProfile,
    this.onBand,
  });
  final OpenBandController controller;
  final FutureOr<void> Function(String day)? onEdit;
  final VoidCallback? onProfile;
  final VoidCallback? onBand;
  @override
  State<G3JournalScreen> createState() => _G3JournalScreenState();
}

class _G3JournalScreenState extends State<G3JournalScreen> {
  JournalDaySnapshot? _today;
  List<JournalDaySnapshot> _history = const [];
  G3JournalPattern? _pattern;
  bool _loading = true, _saving = false, _editing = false;
  String? _readError, _saveError;
  String? _loadedDay;
  int _serial = 0, _position = 0;
  Object? _draft;

  List<_Question> _questionsFor(JournalDaySnapshot? snap) => [
    ..._questions,
    if (snap != null)
      for (final f in snap.fields)
        if (f.custom && !f.hidden)
          _Question(f.key, f.label, f.label, switch (f.kind) {
            JournalFieldKind.yesNo => _Answer.yesNo,
            JournalFieldKind.rating => _Answer.scale,
            JournalFieldKind.dose ||
            JournalFieldKind.duration => _Answer.amount,
          }),
  ];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _load();
  }

  @override
  void didUpdateWidget(covariant G3JournalScreen old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _load();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (_loadedDay != widget.controller.selectedDay) _load();
  }

  Future<void> _load() async {
    final day = widget.controller.selectedDay;
    final id = ++_serial;
    _loadedDay = day;
    setState(() {
      _loading = true;
      _readError = null;
      _saveError = null;
      _today = null;
      _pattern = null;
      _position = 0;
      _draft = null;
    });
    try {
      final repo = widget.controller.repository;
      final date = DateTime.parse(day);
      final days = [1, 2, 3]
          .map((n) => dayLabelOf(DateTime(date.year, date.month, date.day - n)))
          .toList();
      final data = await Future.wait([
        repo.readJournalDay(day),
        for (final d in days) repo.readJournalDay(d),
      ]);
      if (!mounted || id != _serial) return;
      setState(() {
        _today = data.first;
        _history = data.skip(1).toList();
        _loading = false;
        final next = _questionsFor(
          data.first,
        ).indexWhere((q) => !_answered(data.first, q));
        _position = next < 0 ? 0 : next;
      });
      unawaited(_loadPattern(day, id));
    } catch (_) {
      if (!mounted || id != _serial) return;
      setState(() {
        _loading = false;
        _readError = 'Journal konnte nicht geladen werden.';
      });
    }
  }

  Future<void> _loadPattern(String day, int id) async {
    try {
      final pattern = await widget.controller.repository.readJournalPattern(
        day,
        30,
      );
      if (mounted && id == _serial) setState(() => _pattern = pattern);
    } catch (_) {
      // The unknown card remains "—"; a failed read is not zero pairs.
    }
  }

  bool _answered(JournalDaySnapshot snap, _Question q) => q.kind == _Answer.note
      ? snap.note.trim().isNotEmpty
      : snap.metrics[q.key] != null;
  String _value(JournalDaySnapshot snap, _Question q) {
    if (q.kind == _Answer.note) {
      return snap.note.trim().isEmpty ? '—' : snap.note;
    }
    final v = snap.metrics[q.key]?.value;
    if (v == null) return '—';
    if (q.kind == _Answer.yesNo) {
      return v == 1
          ? 'Ja'
          : v == 0
          ? 'Nein'
          : '—';
    }
    if (q.kind == _Answer.amount) {
      final field = snap.fields.where((f) => f.key == q.key).firstOrNull;
      return field?.formatWithUnit(v) ?? '—';
    }
    return v == v.roundToDouble() && v >= 1 && v <= 5
        ? '${v.round()} / 5'
        : '—';
  }

  Future<void> _save(_Question q, Object? value) async {
    final base = _today;
    if (base == null || _saving) return;
    setState(() {
      _draft = value;
      _saveError = null;
      _saving = true;
    });
    try {
      final patch = q.kind == _Answer.note
          ? JournalDayPatch.fromBase(base, note: value as String? ?? '')
          : JournalDayPatch.fromBase(
              base,
              metrics: {
                q.key: value == null
                    ? null
                    : JournalMetricValue((value as num).toDouble()),
              },
            );
      await widget.controller.repository.patchJournalDay(patch);
      final updated = await widget.controller.repository.readJournalDay(
        base.day,
      );
      if (!mounted || widget.controller.selectedDay != base.day) return;
      setState(() {
        _today = updated;
        _saving = false;
        _draft = null;
        _saveError = null;
        _position = (_position + 1) % _questionsFor(updated).length;
      });
      if (q.key == 'caffeine_late') {
        try {
          final pattern = await widget.controller.repository.readJournalPattern(
            base.day,
            30,
          );
          if (mounted && widget.controller.selectedDay == base.day) {
            setState(() => _pattern = pattern);
          }
        } catch (_) {
          /* Keep the old pattern result until a read succeeds. */
        }
      }
    } on JournalConflict {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError =
              'Antwort inzwischen geändert. Neu laden und erneut wählen.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError =
              'Speichern fehlgeschlagen. Deine Auswahl bleibt erhalten.';
        });
      }
    }
  }

  void _next() => setState(() {
    _position = (_position + 1) % _questionsFor(_today).length;
    _draft = null;
    _saveError = null;
  });

  Future<void> _openCustomize() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            G3JournalCustomize(repository: widget.controller.repository),
      ),
    );
    if (mounted) _load();
  }

  Widget _answer(_Question q) {
    switch (q.kind) {
      case _Answer.yesNo:
        return Row(
          children: [
            for (final (i, text) in [(0, 'Nein'), (1, 'Ja')]) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: OBAnswerKey(
                  label: text,
                  selected: _draft == i,
                  onTap: _saving ? null : () => _save(q, i),
                ),
              ),
            ],
          ],
        );
      case _Answer.scale:
        return Row(
          children: [
            for (var i = 1; i <= 5; i++) ...[
              if (i > 1) const SizedBox(width: 5),
              Expanded(
                child: OBAnswerKey(
                  label: '$i',
                  icon: kJournalMoodIcons[i - 1],
                  selected: _draft == i,
                  onTap: _saving ? null : () => _save(q, i),
                ),
              ),
            ],
          ],
        );
      case _Answer.amount:
        final field = _today?.fields.where((f) => f.key == q.key).firstOrNull;
        final step = field?.step ?? 1;
        final value = _draft is num
            ? (_draft as num).toDouble()
            : _today?.metrics[q.key]?.value;
        final current = value == null ? null : (value / step).round();
        return Column(
          children: [
            OBStepper(
              value: current,
              max: ((field?.max ?? 20) / step).floor(),
              onChanged: (v) => _save(q, v * step),
            ),
            OBAnswerKey(
              label: 'Keins',
              selected: current == 0,
              onTap: _saving ? null : () => _save(q, 0),
            ),
          ],
        );
      case _Answer.note:
        return _NoteAnswer(
          initial: _draft as String? ?? '',
          busy: _saving,
          onSave: (v) => _save(q, v),
        );
    }
  }

  Future<void> _edit(_Question q) async {
    final snap = _today;
    if (snap == null) return;
    setState(() => _editing = true);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: G3.of(context).canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => G3JournalAnswerSheet._(
        question: q,
        previous: _value(snap, q),
        initial: q.kind == _Answer.note
            ? snap.note
            : snap.metrics[q.key]?.value,
        field: snap.fields.where((f) => f.key == q.key).firstOrNull,
        onSave: (value) async {
          await _save(q, value);
          return _saveError == null;
        },
      ),
    );
    if (mounted) setState(() => _editing = false);
  }

  String _historySummary(JournalDaySnapshot day) {
    final answered = _questionsFor(
      day,
    ).where((q) => _answered(day, q)).toList();
    if (answered.isEmpty) return 'Nichts eingetragen';
    return answered.map((q) => '${q.title}: ${_value(day, q)}').join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final day = widget.controller.selectedDay;
    final snap = _today;
    final questions = _questionsFor(snap);
    final count = snap == null
        ? 0
        : questions.where((q) => _answered(snap, q)).length;
    final current = questions[_position.clamp(0, questions.length - 1)];
    final pattern = _pattern;
    final band = widget.controller.band;
    final storedAt = band.latestStoredAt;
    return ColoredBox(
      color: g.page,
      child: ListView(
        key: const PageStorageKey('g3.journal'),
        padding: const EdgeInsets.only(top: 20, bottom: kOBTabBarContentInset),
        children: [
          OBPageHeader.hub(
            title: 'Journal',
            subtitle: DateFormat(
              'EEEE, d. MMMM',
              'de_DE',
            ).format(DateTime.parse(day)),
            band: OBBandCapsule(
              state: band.connection == BandConnection.connected
                  ? OBBandState.live
                  : storedAt == null
                  ? OBBandState.none
                  : OBBandState.off,
              battery: band.batteryPercent,
              onTap: widget.onBand,
            ),
            onProfile: widget.onProfile,
            onTitle: () async {
              final chosen = await showDatePicker(
                context: context,
                initialDate: DateTime.parse(day),
                firstDate: DateTime(2020),
                lastDate: widget.controller.now(),
              );
              if (chosen != null) {
                await widget.controller.selectDay(dayLabelOf(chosen));
              }
            },
          ),
          OBSyncState(
            kind: storedAt == null
                ? OBSyncKind.never
                : band.connection == BandConnection.connected
                ? OBSyncKind.live
                : OBSyncKind.stale,
            text: storedAt == null
                ? 'Datenstand unbekannt'
                : 'Daten bis ${DateFormat('HH:mm').format(storedAt)}',
            synthetic: widget.controller.day?.synthetic == true,
          ),
          OBSectionHeader(
            'HEUTE',
            trailing: TextButton(
              onPressed: _openCustomize,
              child: Text(
                'Anpassen ›',
                style: g.t(13, 17, weight: FontWeight.w700),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _readError != null
                ? OBInlineError(message: _readError!, onRetry: _load)
                : snap != null && count == questions.length
                ? OBCheckInDone(total: questions.length)
                : OBCheckIn(
                    title: current.prompt,
                    index: _position + 1,
                    total: questions.length,
                    answer: _answer(current),
                    onLater: _next,
                    error: _editing ? null : _saveError,
                    onRetry: _editing || _saveError == null || _draft == null
                        ? null
                        : () => _save(current, _draft),
                  ),
          ),
          OBSectionHeader(
            'HEUTE BEANTWORTET',
            trailing: Text(
              '$count von ${questions.length}',
              style: g.t(13, 17, color: g.ink2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OBPanel(
              child: snap == null || count == 0
                  ? Text(
                      'Noch nichts beantwortet. Auslassen kostet nichts.',
                      style: g.t(14, 19, color: g.ink2),
                    )
                  : Column(
                      children: [
                        for (final q in questions)
                          if (_answered(snap, q))
                            OBJournalEntryRow(
                              title: q.title,
                              value: _value(snap, q),
                              icon: q.kind == _Answer.note
                                  ? LucideIcons.fileText
                                  : journalFieldIcon(
                                      snap.fields.firstWhere(
                                        (f) => f.key == q.key,
                                      ),
                                    ),
                              onEdit: () => _edit(q),
                            ),
                      ],
                    ),
            ),
          ),
          const OBSectionHeader('FRÜHERE TAGE'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OBPanel(
              child: Column(
                children: [
                  for (final row in _history)
                    OBJournalDayRow(
                      title: DateFormat(
                        'EEE, dd.MM',
                        'de_DE',
                      ).format(DateTime.parse(row.day)),
                      summary: _historySummary(row),
                      onTap: () async {
                        await widget.onEdit?.call(row.day);
                        if (mounted) _load();
                      },
                    ),
                ],
              ),
            ),
          ),
          const OBSectionHeader('MUSTER'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: InkWell(
              onTap: pattern == null
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            G3JournalPatternScreen(pattern: pattern),
                      ),
                    ),
              child: pattern == null
                  ? OBPatternCard(
                      title: '—',
                      detail: 'Vergleich konnte nicht geladen werden.',
                      have: null,
                      need: 8,
                    )
                  : OBPatternCard(
                      title: switch (pattern.pattern.kind) {
                        CaffeineSleepPatternKind.meaningful =>
                          'Koffein und Einschlafen',
                        CaffeineSleepPatternKind.nonmeaningful =>
                          'Kein klares Muster',
                        CaffeineSleepPatternKind.insufficient =>
                          'Noch zu wenige Nächte',
                        CaffeineSleepPatternKind.unavailable =>
                          'Noch kein Vergleich',
                      },
                      detail: 'Koffein nach 14 Uhr · folgende Nacht',
                      have: pattern.pattern.pairedN,
                      need: pattern.pairedMinimum,
                      footer: _patternFooter(pattern),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteAnswer extends StatefulWidget {
  const _NoteAnswer({
    required this.initial,
    required this.busy,
    required this.onSave,
  });
  final String initial;
  final bool busy;
  final ValueChanged<String> onSave;
  @override
  State<_NoteAnswer> createState() => _NoteAnswerState();
}

class _NoteAnswerState extends State<_NoteAnswer> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial,
  );
  @override
  void didUpdateWidget(covariant _NoteAnswer old) {
    super.didUpdateWidget(old);
    if (old.initial != widget.initial && _text.text != widget.initial) {
      _text.text = widget.initial;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      OBTextField(controller: _text, label: 'Notiz (optional)', maxLines: 3),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: widget.busy ? null : () => widget.onSave(_text.text),
        child: const Text('Speichern'),
      ),
    ],
  );
}

class G3JournalPatternScreen extends StatelessWidget {
  const G3JournalPatternScreen({
    super.key,
    required this.pattern,
    this.perSideMinimum,
  });
  final G3JournalPattern pattern;
  final int? perSideMinimum;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final p = pattern.pattern;
    final ready =
        p.kind == CaffeineSleepPatternKind.meaningful ||
        p.kind == CaffeineSleepPatternKind.nonmeaningful;
    return Scaffold(
      backgroundColor: g.page,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
          children: [
            OBPageHeader.detail(
              title: 'MUSTER',
              subtitle: 'Koffein und folgende Nacht',
              backLabel: 'Journal',
              onBack: () => Navigator.pop(context),
            ),
            const SizedBox(height: 24),
            OBPatternCard(
              title: ready
                  ? (p.kind == CaffeineSleepPatternKind.meaningful
                        ? 'Ein Zusammenhang'
                        : 'Kein klares Muster')
                  : 'Noch kein Muster',
              detail: ready
                  ? 'Koffein nach 14 Uhr und Einschlafdauer'
                  : 'Ein Vergleich braucht bestätigte Nächte mit Antwort und Einschlafdauer.',
              have: p.pairedN,
              need: pattern.pairedMinimum,
              footer: _patternFooter(pattern, perSideMinimum: perSideMinimum),
            ),
            const SizedBox(height: 20),
            OBPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('KOFFEIN NACH 14 UHR', style: g.caps()),
                  const SizedBox(height: 8),
                  Text(
                    '${p.pairedN} Tag-Nacht-Paare',
                    style: g.t(17, 22, weight: FontWeight.w700),
                  ),
                  if (p.yesNights != null && p.noNights != null)
                    Text(
                      'Ja ${p.yesNights} · Nein ${p.noNights}',
                      style: g.t(14, 19, color: g.ink2),
                    ),
                  if (!ready) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Je Gruppe',
                      style: g.t(14, 18, weight: FontWeight.w700),
                    ),
                    OBPatternGateRow(
                      label: 'Ja',
                      count: p.yesNights,
                      minimum: perSideMinimum,
                    ),
                    OBPatternGateRow(
                      label: 'Nein',
                      count: p.noNights,
                      minimum: perSideMinimum,
                    ),
                  ],
                  if (ready && p.delta != null)
                    Text(
                      '${p.delta!.toStringAsFixed(1)} Min. Unterschied bei der Einschlafdauer',
                      style: g.t(14, 19),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            OBPanel(
              child: Text(
                'Ein Zusammenhang belegt keine Ursache. Es zählen nur Tage mit Antwort und bestätigter folgender Nacht.',
                style: g.t(14, 19),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class G3JournalCustomize extends StatefulWidget {
  const G3JournalCustomize({super.key, required this.repository});
  final OpenBandRepository repository;
  @override
  State<G3JournalCustomize> createState() => _G3JournalCustomizeState();
}

class _G3JournalCustomizeState extends State<G3JournalCustomize> {
  List<JournalFieldSpec>? _fields;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final fields = await widget.repository.listJournalFields(
        includeHidden: true,
      );
      if (mounted) {
        setState(() {
          _fields = fields;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Fragen nicht geladen.');
    }
  }

  Future<void> _toggle(JournalFieldSpec field, bool active) async {
    try {
      if (active) {
        await widget.repository.restoreJournalField(field.key);
      } else {
        await widget.repository.hideJournalField(field.key);
      }
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = 'Änderung fehlgeschlagen.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final custom =
        _fields?.where((f) => f.custom).toList() ?? const <JournalFieldSpec>[];
    return Scaffold(
      backgroundColor: g.page,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 36),
          children: [
            OBPageHeader.detail(
              title: 'ANPASSEN',
              subtitle: 'Fragen im Journal',
              backLabel: 'Journal',
              onBack: () => Navigator.pop(context),
            ),
            const SizedBox(height: 24),
            Text(
              'Deine Fragen bleiben gespeichert, auch wenn du sie ausblendest.',
              style: g.t(14, 19, color: g.ink2),
            ),
            const SizedBox(height: 18),
            Text('IM CHECK-IN', style: g.caps(color: g.muted)),
            const SizedBox(height: 8),
            OBPanel(
              child: Column(
                children: [
                  for (final q in _questions)
                    OBQuestionRow(
                      title: q.title,
                      subtitle: q.kind == _Answer.note
                          ? 'Freitext · wird nicht verglichen'
                          : q.kind == _Answer.scale
                          ? 'Skala 1–5'
                          : 'Ja / Nein',
                      active: true,
                      onChanged: null,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('EIGENE FRAGEN', style: g.caps(color: g.muted)),
            const SizedBox(height: 8),
            if (_error != null) OBInlineError(message: _error!, onRetry: _load),
            OBPanel(
              child: Column(
                children: [
                  for (final f in custom)
                    OBQuestionRow(
                      title: f.label,
                      subtitle: f.hidden
                          ? 'Ausgeblendet · Antworten bleiben erhalten'
                          : f.kind.name,
                      active: !f.hidden,
                      onChanged: (on) => _toggle(f, on),
                    ),
                  ListTile(
                    leading: const Icon(LucideIcons.plus),
                    title: const Text('Eigene Frage'),
                    subtitle: const Text('Name und Antwortart festlegen'),
                    onTap: () async {
                      await showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => G3JournalNewQuestionSheet(
                          repository: widget.repository,
                        ),
                      );
                      if (mounted) _load();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class G3JournalNewQuestionSheet extends StatefulWidget {
  const G3JournalNewQuestionSheet({
    super.key,
    required this.repository,
    this.initialName = '',
  });
  final OpenBandRepository repository;
  final String initialName;
  @override
  State<G3JournalNewQuestionSheet> createState() => _NewQuestionState();
}

class _NewQuestionState extends State<G3JournalNewQuestionSheet> {
  late final _name = TextEditingController(text: widget.initialName);
  JournalFieldKind _kind = JournalFieldKind.yesNo;
  String? _error;
  bool _busy = false;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Name fehlt.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.createJournalField(
        JournalFieldSpec(
          key: newCustomJournalFieldKey(),
          label: _name.text.trim(),
          kind: _kind,
          unit: _kind == JournalFieldKind.dose ? 'Anzahl' : '',
          max: _kind == JournalFieldKind.rating
              ? 5
              : _kind == JournalFieldKind.dose
              ? 20
              : 1,
          step: 1,
          custom: true,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Frage konnte nicht gespeichert werden.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Eigene Frage', style: g.t(22, 27, weight: FontWeight.w700)),
            const SizedBox(height: 18),
            OBTextField(controller: _name, label: 'Name'),
            const SizedBox(height: 12),
            DropdownButtonFormField<JournalFieldKind>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Antwortart'),
              items: const [
                DropdownMenuItem(
                  value: JournalFieldKind.yesNo,
                  child: Text('Ja / Nein'),
                ),
                DropdownMenuItem(
                  value: JournalFieldKind.dose,
                  child: Text('Anzahl'),
                ),
                DropdownMenuItem(
                  value: JournalFieldKind.rating,
                  child: Text('Skala 1–5'),
                ),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _kind = v);
              },
            ),
            if (_error != null) OBInlineError(message: _error!),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: const Text('Frage speichern'),
            ),
          ],
        ),
      ),
    );
  }
}

class G3JournalAnswerSheet extends StatefulWidget {
  const G3JournalAnswerSheet._({
    required _Question question,
    required this.previous,
    required this.initial,
    required this.field,
    required this.onSave,
  }) : _question = question;
  final _Question _question;
  final String previous;
  final Object? initial;
  final JournalFieldSpec? field;
  final Future<bool> Function(Object?) onSave;
  @override
  State<G3JournalAnswerSheet> createState() => _AnswerEditSheetState();
}

class _AnswerEditSheetState extends State<G3JournalAnswerSheet> {
  Object? _draft;
  late final TextEditingController _note;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
    _note = TextEditingController(
      text: widget.initial is String ? widget.initial as String : '',
    );
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _commit(Object? value) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await widget.onSave(value);
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _saving = false;
      _error = 'Speichern fehlgeschlagen. Deine Auswahl bleibt erhalten.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final q = widget._question;
    final step = widget.field?.step ?? 1;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          10,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.center,
              child: Container(
                width: 38,
                height: 5,
                decoration: BoxDecoration(
                  color: g.gap,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    q.title,
                    style: g.t(22, 27, weight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Schließen',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(LucideIcons.x),
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'vorher: ${widget.previous}',
              style: g.t(14, 18, color: g.muted),
            ),
            const SizedBox(height: 20),
            if (q.kind == _Answer.yesNo)
              Row(
                children: [
                  for (final (value, label) in [(0, 'Nein'), (1, 'Ja')]) ...[
                    if (value > 0) const SizedBox(width: 8),
                    Expanded(
                      child: OBAnswerKey(
                        label: label,
                        selected: _draft == value,
                        onTap: _saving
                            ? null
                            : () => setState(() => _draft = value),
                      ),
                    ),
                  ],
                ],
              ),
            if (q.kind == _Answer.scale)
              Row(
                children: [
                  for (var value = 1; value <= 5; value++) ...[
                    if (value > 1) const SizedBox(width: 5),
                    Expanded(
                      child: OBAnswerKey(
                        label: '$value',
                        icon: kJournalMoodIcons[value - 1],
                        selected: _draft == value || _draft == value.toDouble(),
                        onTap: _saving
                            ? null
                            : () => setState(() => _draft = value),
                      ),
                    ),
                  ],
                ],
              ),
            if (q.kind == _Answer.amount)
              Column(
                children: [
                  OBStepper(
                    value: _draft is num
                        ? ((_draft as num).toDouble() / step).round()
                        : null,
                    max: ((widget.field?.max ?? 20) / step).floor(),
                    onChanged: (v) => setState(() => _draft = v * step),
                  ),
                  OBAnswerKey(
                    label: 'Keins',
                    selected: _draft == 0,
                    onTap: () => setState(() => _draft = 0),
                  ),
                ],
              ),
            if (q.kind == _Answer.note)
              OBTextField(controller: _note, label: 'Notiz', maxLines: 3),
            if (_error != null) ...[
              const SizedBox(height: 12),
              OBInlineError(
                message: _error!,
                onRetry: () =>
                    _commit(q.kind == _Answer.note ? _note.text : _draft),
              ),
            ],
            const SizedBox(height: 12),
            TextButton(
              onPressed: _saving ? null : () => _commit(null),
              child: const Text('Antwort löschen'),
            ),
            FilledButton(
              onPressed: _saving || (q.kind != _Answer.note && _draft == null)
                  ? null
                  : () => _commit(q.kind == _Answer.note ? _note.text : _draft),
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }
}
