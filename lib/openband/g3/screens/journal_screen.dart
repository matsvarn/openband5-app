import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../data/day_label.dart';
import '../../../data/journal_fields.dart';
import '../../../state/app_state.dart';
import '../../controller.dart';
import '../../day_picker.dart';
import '../../domain.dart';
import '../../local_repository.dart';
import '../../journal_fields.dart' show journalFieldIcon;
import '../../tab_bar.dart' show kOBTabBarContentInset;
import '../chrome.dart'
    show
        OBActionPrimary,
        OBActionSecondary,
        OBBandCapsule,
        OBBandState,
        G3DetailPage,
        OBListRow,
        OBLink,
        OBPageHeader,
        OBPanel,
        OBPillButton,
        OBSectionHeader,
        OBSegmented,
        OBSyncKind,
        OBSyncState,
        OBSheet,
        showOBInfoSheet;
import '../count_copy.dart';
import '../check_in.dart' show OBCheckIn, OBInlineError, g3CheckInCopy;
import '../g3_format.dart';
import '../g3_theme.dart';
import '../journal_parts.dart' hide OBCheckIn, OBInlineError;
import '../metrics.dart' show OBMissingValue;

const _questions = <_Question>[
  _Question('alcohol_evening', 'Alkohol', _Answer.yesNo),
  _Question('caffeine_late', 'Koffein nach 14 Uhr', _Answer.yesNo),
  _Question('mood', 'Stimmung', _Answer.scale),
  _Question('', 'Notiz', _Answer.note),
];

String _patternFooter(G3JournalPattern result) {
  final p = result.pattern;
  if (p.kind == CaffeineSleepPatternKind.meaningful ||
      p.kind == CaffeineSleepPatternKind.nonmeaningful) {
    return '${p.pairedN} Tag-Nacht-${g3CountNoun(p.pairedN, 'Paar', 'Paare')} · Vergleich berechnet';
  }
  if (result.refusalGate == G3PatternRefusalGate.paired) {
    return '${p.pairedN} von ${result.pairedMinimum} ${g3CountNoun(result.pairedMinimum, 'Paar', 'Paaren')} · noch ${result.remaining}';
  }
  if (result.refusalGate == G3PatternRefusalGate.side &&
      result.yesNights != null &&
      result.noNights != null) {
    final yes = result.yesNights! < result.perSideMinimum
        ? '${result.yesNights} von ${result.perSideMinimum} nötig'
        : '${p.yesNights} vorhanden';
    final no = result.noNights! < result.perSideMinimum
        ? '${result.noNights} von ${result.perSideMinimum} nötig'
        : '${p.noNights} vorhanden';
    return '${p.pairedN} ${g3CountNoun(p.pairedN, 'Paar', 'Paare')} · Ja $yes · Nein $no';
  }
  if (result.historyNeed case final history?) {
    return '${history.have} von ${history.need} ${g3CountNoun(history.need, 'Paar', 'Paaren')} für den Test';
  }
  return '${p.pairedN} ${g3CountNoun(p.pairedN, 'Paar', 'Paare')} · Ja ${result.yesNights ?? '—'} · Nein ${result.noNights ?? '—'}';
}

String _nightsOrDash(int? count) =>
    count == null ? '—' : '$count ${g3CountNoun(count, 'Nacht', 'Nächte')}';

String _ratingFooter(_Question question) {
  final copy = g3CheckInCopy(question.key, question.title);
  if (copy.low == '1' && copy.high == '5') return 'Skala 1–5';
  return '1 ${copy.low} · 5 ${copy.high}';
}

enum _Answer { yesNo, amount, scale, note }

enum JournalAnswerSaveResult { saved, failed, conflict }

class _Question {
  const _Question(this.key, this.title, this.kind, {this.checkIn, this.target});
  final String key, title;
  final _Answer kind;
  final G3CheckInQuestion? checkIn;
  final String? target;
  String get prompt => g3CheckInCopy(key, title).question;
}

class G3JournalScreen extends StatefulWidget {
  const G3JournalScreen({
    super.key,
    required this.controller,
    this.onEdit,
    this.onProfile,
    this.onBand,
    this.onBack,
    this.scrollController,
  });
  final OpenBandController controller;
  final FutureOr<void> Function(String day)? onEdit;
  final VoidCallback? onProfile;
  final VoidCallback? onBand;
  final VoidCallback? onBack;
  final ScrollController? scrollController;
  @override
  State<G3JournalScreen> createState() => _G3JournalScreenState();
}

class _G3JournalScreenState extends State<G3JournalScreen> {
  late final ScrollController _scrollController =
      widget.scrollController ?? ScrollController();
  G3CheckIn? _checkIn;
  JournalDaySnapshot? _today;
  List<JournalDaySnapshot> _history = const [];
  G3JournalPattern? _pattern;
  bool _loading = true, _saving = false, _editing = false;
  bool _patternLoading = true, _patternFailed = false;
  String? _readError, _refreshError;
  String? _loadedDay;
  int _serial = 0, _position = 0;
  final Map<String, Object?> _drafts = {};
  final Map<String, String> _saveErrors = {};

  String? _targetText(String key, String targetDay, String openDay) {
    if (openDay != dayLabelOf(widget.controller.now())) {
      final day = g3DayShort(DateTime.parse(targetDay));
      return key == 'alcohol_evening' ? '$day · abends' : day;
    }
    if (targetDay == openDay) return null;
    return g3CheckInCopy(key, key).target ??
        g3DayShort(DateTime.parse(targetDay));
  }

  _Question _typedQuestion(G3CheckInQuestion question, String openDay) {
    final preset = question.key == kG3CheckInNoteKey
        ? _questions.last
        : _questions.where((q) => q.key == question.key).firstOrNull;
    final title = preset?.title ?? question.label;
    return _Question(
      question.key,
      title,
      switch (question.kind) {
        G3CheckInKind.yesNo => _Answer.yesNo,
        G3CheckInKind.quantity => _Answer.amount,
        G3CheckInKind.rating => _Answer.scale,
        G3CheckInKind.freeNote => _Answer.note,
      },
      checkIn: question,
      target: _targetText(question.key, question.targetDay, openDay),
    );
  }

  List<_Question> _questionsFor(
    JournalDaySnapshot? snap, {
    bool history = false,
  }) {
    final openDay = widget.controller.selectedDay;
    return [
      if (history || _checkIn == null)
        ..._questions
      else
        for (final question in _checkIn!.questions)
          _typedQuestion(question, openDay),
      if (snap != null)
        for (final f in snap.fields)
          if (f.custom && !f.hidden)
            _Question(f.key, f.label, switch (f.kind) {
              JournalFieldKind.yesNo => _Answer.yesNo,
              JournalFieldKind.rating => _Answer.scale,
              JournalFieldKind.dose ||
              JournalFieldKind.duration => _Answer.amount,
            }, target: history ? null : _targetText(f.key, openDay, openDay)),
    ];
  }

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
    if (widget.scrollController == null) _scrollController.dispose();
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
      _refreshError = null;
      _saveErrors.clear();
      _saving = false;
      _checkIn = null;
      _today = null;
      _pattern = null;
      _patternLoading = true;
      _patternFailed = false;
      _position = 0;
      _drafts.clear();
    });
    try {
      final repo = widget.controller.repository;
      final date = DateTime.parse(day);
      final days = [1, 2, 3, 4, 5]
          .map((n) => dayLabelOf(DateTime(date.year, date.month, date.day - n)))
          .toList();
      final checkIn = await repo.readCheckIn(day);
      final data = await Future.wait([
        repo.readJournalDay(day),
        for (final d in days) repo.readJournalDay(d),
      ]);
      if (!mounted || id != _serial) return;
      setState(() {
        _checkIn = checkIn;
        _today = data.first;
        _history = data.skip(1).toList();
        _loading = false;
        _position = _nextUnanswered(data.first, _questionsFor(data.first), -1);
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
    if (mounted && id == _serial) {
      setState(() {
        _patternLoading = true;
        _patternFailed = false;
      });
    }
    try {
      final pattern = await widget.controller.repository.readJournalPattern(
        day,
        30,
      );
      if (mounted && id == _serial) {
        setState(() {
          _pattern = pattern;
          _patternLoading = false;
          _patternFailed = false;
        });
      }
    } catch (_) {
      if (mounted && id == _serial) {
        setState(() {
          _patternLoading = false;
          _patternFailed = true;
        });
      }
    }
  }

  bool _answered(JournalDaySnapshot snap, _Question q) => q.checkIn != null
      ? q.checkIn!.answer != null
      : q.kind == _Answer.note
      ? snap.note.trim().isNotEmpty
      : snap.metrics[q.key] != null;

  int _nextUnanswered(
    JournalDaySnapshot snap,
    List<_Question> questions,
    int after,
  ) {
    for (var step = 1; step <= questions.length; step++) {
      final index = (after + step) % questions.length;
      if (!_answered(snap, questions[index])) return index;
    }
    return 0;
  }

  Object? _inputValue(JournalDaySnapshot snap, _Question q) {
    if (q.checkIn?.answer case G3YesNoAnswer answer) {
      return answer.value ? 1 : 0;
    }
    if (q.checkIn?.answer case G3QuantityAnswer answer) {
      return answer.value;
    }
    if (q.checkIn?.answer case G3RatingAnswer answer) {
      return answer.value;
    }
    if (q.checkIn?.answer case G3FreeNoteAnswer answer) {
      return answer.value;
    }
    if (q.checkIn != null) return null;
    return q.kind == _Answer.note ? snap.note : snap.metrics[q.key]?.value;
  }

  String _value(JournalDaySnapshot snap, _Question q) {
    if (q.kind == _Answer.note) {
      final note = _inputValue(snap, q) as String?;
      return note == null || note.trim().isEmpty ? '—' : note;
    }
    final raw = _inputValue(snap, q);
    final v = raw is num ? raw.toDouble() : null;
    if (v == null) return '—';
    if (q.kind == _Answer.yesNo) {
      return v == 1
          ? 'Ja'
          : v == 0
          ? 'Nein'
          : '—';
    }
    if (q.kind == _Answer.amount) {
      if (v == 0) return 'Keins';
      final field =
          q.checkIn?.field ??
          snap.fields.where((f) => f.key == q.key).firstOrNull;
      return field?.formatWithUnit(v) ?? '—';
    }
    return v == v.roundToDouble() && v >= 1 && v <= 5
        ? '${v.round()} von 5'
        : '—';
  }

  Future<JournalAnswerSaveResult> _save(_Question q, Object? value) async {
    final base = _today;
    if (base == null || _saving) return JournalAnswerSaveResult.failed;
    final saveSerial = _serial;
    final targetDay = q.checkIn?.targetDay ?? base.day;
    final wasCurrent = !_editing && _questionsFor(base)[_position].key == q.key;
    setState(() {
      _drafts[q.key] = value;
      _saveErrors.remove(q.key);
      _refreshError = null;
      _saving = true;
    });
    try {
      final repo = widget.controller.repository;
      if (q.checkIn != null && value != null) {
        final answer = switch (q.kind) {
          _Answer.yesNo => G3YesNoAnswer(value == 1),
          _Answer.amount => G3QuantityAnswer((value as num).toDouble()),
          _Answer.scale => G3RatingAnswer((value as num).toInt()),
          _Answer.note => G3FreeNoteAnswer(value as String),
        };
        await repo.answerCheckIn(base.day, q.key, answer);
      } else {
        // The typed API has no delete operation or custom-question key.
        final target = targetDay == base.day
            ? base
            : await repo.readJournalDay(targetDay);
        final patch = q.kind == _Answer.note
            ? JournalDayPatch.fromBase(target, note: value as String? ?? '')
            : JournalDayPatch.fromBase(
                target,
                metrics: {
                  q.key: value == null
                      ? null
                      : JournalMetricValue((value as num).toDouble()),
                },
              );
        await repo.patchJournalDay(patch);
      }
      if (!mounted ||
          saveSerial != _serial ||
          widget.controller.selectedDay != base.day) {
        return JournalAnswerSaveResult.saved;
      }
      late final JournalDaySnapshot updated;
      late final G3CheckIn updatedCheckIn;
      JournalDaySnapshot? updatedTarget;
      try {
        updatedCheckIn = await repo.readCheckIn(base.day);
        updated = await repo.readJournalDay(base.day);
        if (targetDay != base.day) {
          updatedTarget = await repo.readJournalDay(targetDay);
        }
      } catch (_) {
        if (mounted && widget.controller.selectedDay == base.day) {
          setState(() {
            _saving = false;
            _drafts.remove(q.key);
            _refreshError =
                'Antwort gespeichert. Ansicht konnte nicht aktualisiert werden.';
          });
        }
        return JournalAnswerSaveResult.saved;
      }
      if (!mounted ||
          saveSerial != _serial ||
          widget.controller.selectedDay != base.day) {
        return JournalAnswerSaveResult.saved;
      }
      setState(() {
        _checkIn = updatedCheckIn;
        _today = updated;
        if (updatedTarget != null) {
          _history = [
            for (final row in _history)
              if (row.day == targetDay) updatedTarget else row,
          ];
        }
        _saving = false;
        _drafts.remove(q.key);
        _saveErrors.remove(q.key);
        _refreshError = null;
        if (wasCurrent) {
          _position = _nextUnanswered(
            updated,
            _questionsFor(updated),
            _position,
          );
        } else {
          _position = _nextUnanswered(updated, _questionsFor(updated), -1);
        }
      });
      if (q.key == 'caffeine_late') {
        try {
          final pattern = await widget.controller.repository.readJournalPattern(
            base.day,
            30,
          );
          if (mounted &&
              saveSerial == _serial &&
              widget.controller.selectedDay == base.day) {
            setState(() => _pattern = pattern);
          }
        } catch (_) {
          /* Keep the old pattern result until a read succeeds. */
        }
      }
      return JournalAnswerSaveResult.saved;
    } on JournalConflict {
      if (mounted &&
          saveSerial == _serial &&
          widget.controller.selectedDay == base.day) {
        setState(() {
          _saving = false;
          _drafts.remove(q.key);
          _saveErrors[q.key] =
              'Antwort inzwischen geändert. Neu laden und erneut wählen.';
        });
      }
      return JournalAnswerSaveResult.conflict;
    } catch (_) {
      if (mounted &&
          saveSerial == _serial &&
          widget.controller.selectedDay == base.day) {
        setState(() {
          _saving = false;
          _saveErrors[q.key] =
              'Speichern fehlgeschlagen. Deine Auswahl bleibt erhalten.';
        });
      }
      return JournalAnswerSaveResult.failed;
    }
  }

  void _next() {
    final snap = _today!;
    final questions = _questionsFor(snap);
    final key = questions[_position].key;
    setState(() {
      _position = _nextUnanswered(snap, questions, _position);
      _drafts.remove(key);
      _saveErrors.remove(key);
      _refreshError = null;
    });
  }

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
    final draft = _drafts[q.key];
    switch (q.kind) {
      case _Answer.yesNo:
        return Row(
          children: [
            for (final (i, text) in [(0, 'Nein'), (1, 'Ja')]) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: OBAnswerKey(
                  label: text,
                  selected: draft == i,
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
                  rating: true,
                  selected: draft == i,
                  onTap: _saving ? null : () => _save(q, i),
                ),
              ),
            ],
          ],
        );
      case _Answer.amount:
        final field =
            q.checkIn?.field ??
            _today?.fields.where((f) => f.key == q.key).firstOrNull;
        final step = field?.step ?? 1;
        final value = draft is num
            ? draft.toDouble()
            : _today == null
            ? null
            : _inputValue(_today!, q) as num?;
        final current = value == null ? null : (value / step).round();
        return Column(
          children: [
            OBStepper(
              value: current,
              max: ((field?.max ?? 20) / step).floor(),
              unit: field?.unit,
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
          initial: draft as String? ?? '',
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
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? .55 : .35,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => G3JournalAnswerSheet._(
        question: q,
        previous: _value(snap, q),
        initial: _inputValue(snap, q),
        field:
            q.checkIn?.field ??
            snap.fields.where((f) => f.key == q.key).firstOrNull,
        onSave: (value) async {
          return _save(q, value);
        },
        onReload: _load,
      ),
    );
    if (mounted) {
      setState(() {
        _editing = false;
        _drafts.remove(q.key);
        _saveErrors.remove(q.key);
      });
    }
  }

  List<String> _historyChips(JournalDaySnapshot day) => [
    for (final q in _questionsFor(day, history: true))
      if (_answered(day, q))
        q.kind == _Answer.note
            ? 'Notiz'
            : '${q.key == 'caffeine_late' ? 'Koffein' : q.title}: ${_value(day, q)}',
  ];

  Widget _historyRow(JournalDaySnapshot row, String selectedDay) {
    final chips = _historyChips(row);
    final selected = DateTime.parse(selectedDay);
    final yesterday = dayLabelOf(
      DateTime(selected.year, selected.month, selected.day - 1),
    );
    final date = DateTime.parse(row.day);
    return OBJournalDayRow(
      title: '${row.day == yesterday ? 'Gestern · ' : ''}${g3DayShort(date)}',
      summary: null,
      chips: chips,
      count: chips.isEmpty
          ? null
          : '${chips.length} von ${_questionsFor(row, history: true).length}',
      onTap: () async {
        await widget.onEdit?.call(row.day);
        if (mounted) _load();
      },
    );
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
    final currentDraft = _drafts[current.key];
    final currentError = _refreshError ?? _saveErrors[current.key];
    final pattern = _pattern;
    final band = widget.controller.band;
    final storedAt = band.latestStoredAt;
    final openDayIsToday = day == dayLabelOf(widget.controller.now());
    final sectionDay = openDayIsToday
        ? 'HEUTE'
        : g3DayShort(DateTime.parse(day)).toUpperCase();
    final compactDate = g3DayShort(DateTime.parse(day));
    return ColoredBox(
      color: g.page,
      child: AnimatedBuilder(
        animation: _scrollController,
        builder: (context, _) => Stack(
          children: [
            ListView(
              controller: _scrollController,
              key: const PageStorageKey('g3.journal'),
              padding: const EdgeInsets.only(bottom: kOBTabBarContentInset),
              children: [
                if (widget.onBack != null)
                  OBPageHeader.detail(
                    title: 'JOURNAL',
                    domain: G3Domain.neutral,
                    subtitle: g3DayLong(DateTime.parse(day)),
                    backLabel: 'Journal',
                    onBack: widget.onBack,
                    onTrailing: () => showOBInfoSheet(
                      context,
                      title: 'Journal verstehen',
                      paragraphs: [
                        'Alkohol, Koffein und die Notiz gehören zum Vortag. Stimmung und eigene Fragen gelten für den ausgewählten Tag. Fehlende Antworten bleiben offen.',
                      ],
                    ),
                  )
                else
                  OBPageHeader.hub(
                    title: 'Journal',
                    subtitle: g3DayLong(DateTime.parse(day)),
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
                    onTitle: () =>
                        chooseOpenBandDay(context, widget.controller),
                  ),
                OBSyncState.dataThrough(
                  kind: storedAt == null
                      ? OBSyncKind.never
                      : band.connection == BandConnection.connected
                      ? OBSyncKind.live
                      : OBSyncKind.stale,
                  storedAt: storedAt,
                  now: widget.controller.now(),
                  synthetic: widget.controller.day?.synthetic == true,
                ),
                OBSectionHeader(
                  sectionDay,
                  trailing: OBLink('Anpassen', onTap: _openCustomize),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _readError != null
                      ? OBInlineError(
                          message: _readError!,
                          onRetry: _load,
                          retryLabel: 'Neu laden',
                        )
                      : snap != null && count == questions.length
                      ? OBCheckInDone(
                          total: questions.length,
                          title: openDayIsToday
                              ? 'Für heute erledigt'
                              : 'Für diesen Tag erledigt',
                          answers: [
                            for (final q in questions)
                              q.kind == _Answer.note
                                  ? 'Notiz'
                                  : '${q.key == 'caffeine_late' ? 'Koffein' : q.title}: ${_value(snap, q)}',
                          ],
                        )
                      : OBCheckIn(
                          title: current.prompt,
                          target: current.target,
                          index: count + 1,
                          total: questions.length,
                          answer: _answer(current),
                          onLater: _next,
                          inlineLater: current.kind == _Answer.yesNo,
                          footerLabel: current.kind == _Answer.scale
                              ? _ratingFooter(current)
                              : null,
                          error: _editing ? null : currentError,
                          retryLabel:
                              _refreshError != null || currentDraft == null
                              ? 'Neu laden'
                              : 'Erneut speichern',
                          onRetry: _editing || currentError == null
                              ? null
                              : _refreshError != null || currentDraft == null
                              ? _load
                              : () => _save(current, currentDraft),
                        ),
                ),
                const OBSectionHeader('BEANTWORTET'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: snap == null || count == 0
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: g.pressed(radius: 18),
                          child: Text(
                            'Noch nichts beantwortet. Auslassen kostet nichts.',
                            style: g.t(13, 17, color: g.ink2),
                          ),
                        )
                      : OBPanel(
                          child: Column(
                            children: [
                              for (final q in questions)
                                if (_answered(snap, q))
                                  OBJournalEntryRow(
                                    title: q.title,
                                    value: _value(snap, q),
                                    subtitle: q.kind == _Answer.note
                                        ? openDayIsToday
                                              ? 'zu gestern'
                                              : g3DayShort(
                                                  DateTime.parse(
                                                    q.checkIn?.targetDay ?? day,
                                                  ),
                                                )
                                        : q.key == 'alcohol_evening'
                                        ? openDayIsToday
                                              ? 'gestern Abend'
                                              : g3DayShort(
                                                  DateTime.parse(
                                                    q.checkIn?.targetDay ?? day,
                                                  ),
                                                )
                                        : q.key == 'caffeine_late'
                                        ? openDayIsToday
                                              ? 'gestern'
                                              : g3DayShort(
                                                  DateTime.parse(
                                                    q.checkIn?.targetDay ?? day,
                                                  ),
                                                )
                                        : openDayIsToday
                                        ? 'heute'
                                        : g3DayShort(
                                            DateTime.parse(
                                              q.checkIn?.targetDay ?? day,
                                            ),
                                          ),
                                    icon: q.kind == _Answer.note
                                        ? LucideIcons.stickyNote
                                        : q.kind == _Answer.scale
                                        ? LucideIcons.smile
                                        : journalFieldIcon(
                                            q.checkIn?.field ??
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
                        for (final row in _history) _historyRow(row, day),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: pattern == null && _patternLoading
                      ? OBPatternCard(
                          title: 'Vergleich wird geladen',
                          detail: '',
                          have: null,
                          need: null,
                          loading: true,
                        )
                      : pattern == null && _patternFailed
                      ? OBPatternCard(
                          title: '—',
                          detail: 'Vergleich konnte nicht geladen werden.',
                          have: null,
                          need: null,
                          onRetry: () => _loadPattern(day, _serial),
                        )
                      : pattern != null
                      ? OBPatternCard(
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
                          have:
                              pattern.historyNeed?.have ??
                              pattern.pattern.pairedN,
                          need:
                              pattern.historyNeed?.need ??
                              pattern.pairedMinimum,
                          footer: _patternFooter(pattern),
                          partial: pattern.pattern.partial,
                          onOpen: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  G3JournalPatternScreen(pattern: pattern),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
            if (_scrollController.initialScrollOffset > 300 ||
                (_scrollController.hasClients &&
                    _scrollController.offset > 300))
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ColoredBox(
                  color: g.page,
                  child: OBPageHeader.compact(
                    title: 'Journal',
                    subtitle:
                        '$compactDate${widget.controller.day?.synthetic == true ? ' · Synthetische Daten' : ''}',
                    band: OBBandCapsule(
                      state: band.connection == BandConnection.connected
                          ? OBBandState.live
                          : storedAt == null
                          ? OBBandState.none
                          : OBBandState.off,
                      battery: band.batteryPercent,
                      small: true,
                      onTap: widget.onBand,
                    ),
                    onProfile: widget.onProfile,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Focused destination for a Journal notification or a selected past day.
class G3JournalComposeRoute extends StatefulWidget {
  const G3JournalComposeRoute({super.key, this.repository, this.day});
  final OpenBandRepository? repository;
  final String? day;

  @override
  State<G3JournalComposeRoute> createState() => _G3JournalComposeRouteState();
}

class _G3JournalComposeRouteState extends State<G3JournalComposeRoute> {
  OpenBandController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= OpenBandController(
      repository:
          widget.repository ??
          LocalOpenBandRepository(context.read<AppState>()),
      initialDay: widget.day ?? todayLabel(),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: G3JournalScreen(
      controller: _controller!,
      onBack: () => Navigator.of(context).pop(),
      onEdit: (day) => _controller!.selectDay(day),
    ),
  );
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
      Text(
        'Freitext, optional. Wird nicht ausgewertet.',
        style: G3.of(context).t(13, 17, color: G3.of(context).ink2),
      ),
      const SizedBox(height: 8),
      OBTextField(controller: _text, label: 'Notiz (optional)', maxLines: 3),
      const SizedBox(height: 8),
      OBActionPrimary(
        'Speichern',
        onPressed: widget.busy ? null : () => widget.onSave(_text.text),
      ),
    ],
  );
}

class G3JournalPatternScreen extends StatelessWidget {
  const G3JournalPatternScreen({super.key, required this.pattern});
  final G3JournalPattern pattern;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final p = pattern.pattern;
    final ready =
        p.kind == CaffeineSleepPatternKind.meaningful ||
        p.kind == CaffeineSleepPatternKind.nonmeaningful;
    final meaningful = p.kind == CaffeineSleepPatternKind.meaningful;
    final minutes = p.delta?.round();
    return Scaffold(
      backgroundColor: g.page,
      body: SafeArea(
        bottom: false,
        child: G3DetailPage(
          bottomInset: kOBTabBarContentInset,
          header: OBPageHeader.detail(
            title: 'MUSTER',
            domain: G3Domain.neutral,
            subtitle: 'Koffein nach 14 Uhr · Einschlafen',
            backLabel: 'Journal',
            onBack: () => Navigator.pop(context),
            onTrailing: () => showOBInfoSheet(
              context,
              title: 'Muster verstehen',
              paragraphs: [
                'Koffein nach 14 Uhr wird mit dem Einschlafen in der folgenden Nacht verglichen. Dafür braucht es mindestens ${pattern.pairedMinimum} Tag-Nacht-Paare und je ${pattern.perSideMinimum} Nächte mit Ja und Nein. Ein Vergleich beweist keine Ursache.',
              ],
            ),
          ),
          children: [
            OBPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('KOFFEIN · EINSCHLAFEN', style: g.caps()),
                      ),
                      Text(
                        ready
                            ? '${p.pairedN} Tag-Nacht-${g3CountNoun(p.pairedN, 'Paar', 'Paare')}'
                            : 'noch nicht möglich',
                        style: g.t(13, 17, color: g.muted),
                      ),
                    ],
                  ),
                  if (p.partial) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Teilweise auswertbar',
                      style: g.t(13, 17, color: g.muted),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (meaningful && minutes != null) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          g3Signed(minutes),
                          style: g.t(72, 72, weight: FontWeight.w700),
                        ),
                        const SizedBox(width: 6),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Min.',
                            style: g.t(17, 20, color: g.muted),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Ja gegen Nein',
                          style: g.t(13, 17, weight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Nach Tagen mit Koffein nach 14 Uhr hast du im Mittel ${g3Duration(minutes.abs())} ${minutes >= 0 ? 'länger' : 'kürzer'} zum Einschlafen gebraucht.',
                      style: g.t(17, 22, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_nightsOrDash(p.yesNights)} vs. ${_nightsOrDash(p.noNights)} · kein Beweis für Ursache',
                      style: g.t(13, 17, color: g.ink2),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        SizedBox(
                          width: 88,
                          child: const OBMissingValue(size: 64, lineHeight: 72),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ready
                                    ? 'Kein klares Muster'
                                    : 'Noch kein Muster',
                                style: g.t(17, 21, weight: FontWeight.w700),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                ready
                                    ? 'Der Vergleich zeigt keinen ausreichend klaren Zusammenhang.'
                                    : switch (pattern.refusalGate) {
                                        G3PatternRefusalGate.paired =>
                                          'Für den Vergleich fehlen Tag-Nacht-Paare: ${p.pairedN} von ${pattern.pairedMinimum} vorhanden.',
                                        G3PatternRefusalGate.side =>
                                          'Für den Vergleich braucht es je ${pattern.perSideMinimum} ${g3CountNoun(pattern.perSideMinimum, 'Nacht', 'Nächte')} mit Ja und Nein.',
                                        G3PatternRefusalGate.history =>
                                          'Für den statistischen Vergleich fehlen Tag-Nacht-Paare: ${pattern.historyNeed!.have} von ${pattern.historyNeed!.need} nötig.',
                                        null =>
                                          'Ein Vergleich ist noch nicht möglich.',
                                      },
                                style: g.t(13, 17, color: g.ink2),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (!ready) ...[
                    const SizedBox(height: 16),
                    OBPatternProgress(
                      have: (pattern.historyNeed?.have ?? p.pairedN).clamp(
                        0,
                        pattern.historyNeed?.need ?? pattern.pairedMinimum,
                      ),
                      need: pattern.historyNeed?.need ?? pattern.pairedMinimum,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _patternFooter(pattern),
                      style: g.t(13, 17, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    Divider(color: g.hairline),
                    OBPatternGateRow(
                      label: 'Ja',
                      count: pattern.yesNights,
                      minimum: pattern.perSideMinimum,
                    ),
                    OBPatternGateRow(
                      label: 'Nein',
                      count: pattern.noNights,
                      minimum: pattern.perSideMinimum,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            OBPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'So wird geprüft',
                    style: g.t(17, 21, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${CaffeineSleepPattern.infoComparison} ${CaffeineSleepPattern.infoEligibility} ${CaffeineSleepPattern.infoCausation}',
                    style: g.t(14, 19, color: g.ink2),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('ANDERE FRAGEN', style: g.caps(color: g.muted)),
            const SizedBox(height: 8),
            OBPanel(
              child: Row(
                children: [
                  const Icon(LucideIcons.notebookPen, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Alkohol, Stimmung, Notiz',
                          style: g.t(15, 19, weight: FontWeight.w700),
                        ),
                        Text(
                          'werden noch nicht verglichen',
                          style: g.t(12, 16, color: g.muted),
                        ),
                      ],
                    ),
                  ),
                  const OBMissingValue(size: 15, lineHeight: 19),
                ],
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
    final active = custom.where((f) => !f.hidden).toList();
    final hidden = custom.where((f) => f.hidden).toList();
    return Scaffold(
      backgroundColor: g.page,
      body: SafeArea(
        bottom: false,
        child: G3DetailPage(
          bottomInset: kOBTabBarContentInset,
          header: OBPageHeader.detail(
            title: 'ANPASSEN',
            domain: G3Domain.neutral,
            subtitle: 'Fragen im Check-in',
            backLabel: 'Journal',
            onBack: () => Navigator.pop(context),
            onTrailing: () => showOBInfoSheet(
              context,
              title: 'Fragen anpassen',
              paragraphs: [
                'Eigene Fragen lassen sich ausblenden und wieder einblenden. Gespeicherte Antworten bleiben erhalten. Neue Fragen zählen ab heute und werden nicht mit Schlafnächten verglichen.',
              ],
            ),
          ),
          children: [
            Text(
              'Der Check-in stellt diese Fragen, eine nach der anderen.',
              style: g.t(14, 19, color: g.ink2),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text('IM CHECK-IN', style: g.caps(color: g.muted)),
                ),
                Text(
                  '${_questions.length + active.length} Fragen',
                  style: g.t(13, 16, color: g.ink2),
                ),
              ],
            ),
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
                          ? 'Skala 1–5 · heute'
                          : q.key == 'alcohol_evening'
                          ? 'Ja / Nein · zu gestern Abend'
                          : 'Ja / Nein · zu gestern',
                      active: true,
                      onChanged: null,
                      icon: q.kind == _Answer.note
                          ? LucideIcons.stickyNote
                          : q.kind == _Answer.scale
                          ? LucideIcons.smile
                          : q.key == 'alcohol_evening'
                          ? LucideIcons.wine
                          : LucideIcons.coffee,
                    ),
                  for (final f in active)
                    OBQuestionRow(
                      title: f.label,
                      subtitle: switch (f.kind) {
                        JournalFieldKind.yesNo => 'Ja / Nein · eigene Frage',
                        JournalFieldKind.rating => 'Skala 1–5 · eigene Frage',
                        JournalFieldKind.dose => 'Anzahl · eigene Frage',
                        JournalFieldKind.duration => 'Dauer · eigene Frage',
                      },
                      active: true,
                      onChanged: (on) => _toggle(f, on),
                    ),
                ],
              ),
            ),
            if (hidden.isNotEmpty) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text('AUSGEBLENDET', style: g.caps(color: g.muted)),
                  ),
                  Text('${hidden.length}', style: g.t(13, 16, color: g.ink2)),
                ],
              ),
              const SizedBox(height: 8),
              OBPanel(
                child: Column(
                  children: [
                    for (final f in hidden)
                      OBQuestionRow(
                        title: f.label,
                        subtitle: 'Ausgeblendet · Antworten bleiben erhalten',
                        active: false,
                        onChanged: (on) => _toggle(f, on),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Ausgeblendete Fragen behalten ihre Antworten. Einblenden zählt weiter.',
                style: g.t(12, 16, color: g.muted),
              ),
            ],
            const SizedBox(height: 18),
            if (_error != null) OBInlineError(message: _error!, onRetry: _load),
            OBListRow(
              icon: LucideIcons.plus,
              title: 'Eigene Frage',
              subtitle: 'Name und Antwortart festlegen',
              onTap: () async {
                await showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  barrierColor: Colors.black.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? .55
                        : .35,
                  ),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  builder: (_) =>
                      G3JournalNewQuestionSheet(repository: widget.repository),
                );
                if (mounted) _load();
              },
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
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: OBSheet(
          title: 'Eigene Frage',
          subtitle:
              'Zählt ab heute. Eigene Fragen werden noch nicht mit Nächten verglichen.',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('NAME', style: g.caps(color: g.muted)),
              const SizedBox(height: 6),
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: g.pressed(radius: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _name,
                        maxLength: 32,
                        style: g.t(17, 22, weight: FontWeight.w500),
                        decoration: const InputDecoration(
                          hintText: 'Name der Frage',
                          border: InputBorder.none,
                          counterText: '',
                          isDense: true,
                        ),
                      ),
                    ),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _name,
                      builder: (_, value, _) => Text(
                        '${value.text.characters.length} / 32',
                        style: g.t(11, 14, color: g.muted),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('ANTWORT', style: g.caps(color: g.muted)),
              const SizedBox(height: 6),
              OBSegmented(
                items: const ['Ja / Nein', 'Anzahl', 'Skala 1–5'],
                selected: switch (_kind) {
                  JournalFieldKind.yesNo => 0,
                  JournalFieldKind.dose => 1,
                  JournalFieldKind.rating => 2,
                  JournalFieldKind.duration => 1,
                },
                expand: true,
                onChanged: _busy
                    ? null
                    : (index) => setState(
                        () => _kind = [
                          JournalFieldKind.yesNo,
                          JournalFieldKind.dose,
                          JournalFieldKind.rating,
                        ][index],
                      ),
              ),
              const SizedBox(height: 16),
              Text('SO ERSCHEINT SIE', style: g.caps(color: g.muted)),
              const SizedBox(height: 6),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _name,
                builder: (context, value, _) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: g.pressed(radius: 14),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.notebookPen, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          value.text.trim().isEmpty
                              ? 'Deine Frage'
                              : value.text.trim(),
                          style: g.t(15, 19, weight: FontWeight.w700),
                        ),
                      ),
                      Text(switch (_kind) {
                        JournalFieldKind.yesNo => 'Nein · Ja',
                        JournalFieldKind.dose => '0 · 1 · 2',
                        JournalFieldKind.rating => '1–5',
                        JournalFieldKind.duration => 'Minuten',
                      }, style: g.t(13, 17, color: g.ink2)),
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                OBInlineError(message: _error!),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OBActionSecondary(
                      'Abbrechen',
                      expand: true,
                      onPressed: _busy ? null : () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OBActionPrimary(
                      'Hinzufügen',
                      expand: true,
                      onPressed: _busy ? null : _save,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class G3JournalAnswerSheet extends StatefulWidget {
  G3JournalAnswerSheet.forField({
    super.key,
    required JournalFieldSpec definition,
    required this.previous,
    required this.initial,
    required this.onSave,
  }) : onReload = null,
       field = definition,
       _question = _Question(
         definition.key,
         definition.label,
         switch (definition.kind) {
           JournalFieldKind.yesNo => _Answer.yesNo,
           JournalFieldKind.rating => _Answer.scale,
           JournalFieldKind.dose || JournalFieldKind.duration => _Answer.amount,
         },
       );

  const G3JournalAnswerSheet._({
    required _Question question,
    required this.previous,
    required this.initial,
    required this.field,
    required this.onSave,
    required this.onReload,
  }) : _question = question;
  final _Question _question;
  final String previous;
  final Object? initial;
  final JournalFieldSpec? field;
  final Future<JournalAnswerSaveResult> Function(Object?) onSave;
  final Future<void> Function()? onReload;
  @override
  State<G3JournalAnswerSheet> createState() => _AnswerEditSheetState();
}

class _AnswerEditSheetState extends State<G3JournalAnswerSheet> {
  Object? _draft;
  late final TextEditingController _note;
  bool _saving = false;
  bool _needsReload = false;
  Object? _attempted;
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
      _attempted = value;
    });
    final result = await widget.onSave(value);
    if (!mounted) return;
    if (result == JournalAnswerSaveResult.saved) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _saving = false;
      _needsReload = result == JournalAnswerSaveResult.conflict;
      _error = _needsReload
          ? 'Antwort inzwischen geändert. Neu laden und erneut wählen.'
          : 'Speichern fehlgeschlagen. Deine Auswahl bleibt erhalten.';
    });
  }

  void _reload() {
    Navigator.pop(context);
    widget.onReload?.call();
  }

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final q = widget._question;
    final step = widget.field?.step ?? 1;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: OBSheet(
          title: q.title,
          subtitle: 'Gespeicherte Antwort ändern',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                          rating: true,
                          selected:
                              _draft == value || _draft == value.toDouble(),
                          onTap: _saving
                              ? null
                              : () => setState(() => _draft = value),
                        ),
                      ),
                    ],
                  ],
                ),
              if (q.kind == _Answer.amount)
                OBStepper(
                  value: _draft is num
                      ? ((_draft as num).toDouble() / step).round()
                      : null,
                  max: ((widget.field?.max ?? 20) / step).floor(),
                  unit: widget.field?.unit,
                  onChanged: (v) => setState(() => _draft = v * step),
                ),
              if (q.kind == _Answer.note)
                OBTextField(controller: _note, label: 'Notiz', maxLines: 3),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'vorher: ${widget.previous}',
                      style: g.t(14, 18, color: g.muted),
                    ),
                  ),
                  if (q.kind == _Answer.amount)
                    OBPillButton(
                      'Keins',
                      onPressed: _saving
                          ? null
                          : () => setState(() => _draft = 0),
                    ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                OBInlineError(
                  message: _error!,
                  retryLabel: _needsReload ? 'Neu laden' : 'Erneut speichern',
                  onRetry: _needsReload ? _reload : () => _commit(_attempted),
                ),
              ],
              const SizedBox(height: 8),
              Divider(color: g.hairline),
              Row(
                children: [
                  OBActionSecondary(
                    'Antwort löschen',
                    height: 40,
                    onPressed: _saving ? null : () => _commit(null),
                  ),
                  const SizedBox(width: 8),
                  const Spacer(),
                  Text(
                    'Frage wird wieder offen',
                    style: g.t(12, 16, color: g.muted),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OBActionSecondary(
                      'Abbrechen',
                      expand: true,
                      onPressed: _saving ? null : () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OBActionPrimary(
                      'Speichern',
                      expand: true,
                      onPressed:
                          _saving || (q.kind != _Answer.note && _draft == null)
                          ? null
                          : () => _commit(
                              q.kind == _Answer.note ? _note.text : _draft,
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
