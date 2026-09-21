import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../data/day_label.dart';
import 'alp_tokens.dart';
import 'calendar.dart';
import 'domain.dart';
import 'journal_controls.dart';
import 'settings_controls.dart';
import 'theme.dart';

enum _Vo2RouteResult { committed }

const _vo2InfoParagraphs = [
  'Quelle: Eigener Eintrag · ml/kg/min',
  'Datum und Methode: laut Eingabe.',
  'Einordnung: kein Referenzbereich hinterlegt.',
];

Future<Object?> _showVo2Info(BuildContext context) => showOpenBandJournalInfo(
  context,
  title: 'Über VO₂max',
  paragraphs: _vo2InfoParagraphs,
);

/// Manual, dated VO2max entries. The screen only renders the typed manual
/// repository contract and does not estimate or classify a reading.
class OpenBandVo2 extends StatefulWidget {
  const OpenBandVo2({
    super.key,
    required this.repository,
    required this.endDay,
    this.now = DateTime.now,
  });

  final OpenBandRepository repository;
  final String endDay;
  final DateTime Function() now;

  static Future<void> push(
    BuildContext context, {
    required OpenBandRepository repository,
    required String endDay,
    DateTime Function() now = DateTime.now,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) =>
          OpenBandVo2(repository: repository, endDay: endDay, now: now),
    ),
  );

  @override
  State<OpenBandVo2> createState() => _OpenBandVo2State();
}

class _OpenBandVo2State extends State<OpenBandVo2> {
  int _generation = 0;
  Vo2List? _list;
  bool _loading = true;
  bool _readError = false;
  bool _savedRefreshError = false;

  @override
  void initState() {
    super.initState();
    if (!isVo2CivilDay(widget.endDay)) {
      throw ArgumentError.value(
        widget.endDay,
        'endDay',
        'Expected YYYY-MM-DD.',
      );
    }
    _load();
  }

  @override
  void didUpdateWidget(covariant OpenBandVo2 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository) ||
        oldWidget.endDay != widget.endDay) {
      if (!isVo2CivilDay(widget.endDay)) {
        throw ArgumentError.value(
          widget.endDay,
          'endDay',
          'Expected YYYY-MM-DD.',
        );
      }
      _generation++;
      _list = null;
      _loading = true;
      _readError = false;
      _savedRefreshError = false;
      _load();
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<bool> _load({bool afterCommit = false}) async {
    final generation = ++_generation;
    final repository = widget.repository;
    final endDay = widget.endDay;
    setState(() {
      _list = null;
      _loading = true;
      _readError = false;
      _savedRefreshError = false;
    });
    try {
      final list = await repository.readVo2Entries();
      if (!mounted ||
          generation != _generation ||
          !identical(repository, widget.repository) ||
          endDay != widget.endDay) {
        return false;
      }
      setState(() {
        _list = list;
        _loading = false;
      });
      return true;
    } catch (_) {
      if (!mounted ||
          generation != _generation ||
          !identical(repository, widget.repository) ||
          endDay != widget.endDay) {
        return false;
      }
      setState(() {
        _loading = false;
        if (afterCommit) {
          _savedRefreshError = true;
        } else {
          _readError = true;
        }
      });
      return false;
    }
  }

  DateTime get _latestDraftDay {
    final contextDay = DateTime.parse(widget.endDay);
    final clock = widget.now();
    final today = DateTime(clock.year, clock.month, clock.day);
    return contextDay.isBefore(today) ? contextDay : today;
  }

  List<Vo2Revision> _visible(Vo2List list, {required bool deleted}) {
    final rows = <Vo2Revision>[];
    for (final entry in list.entries) {
      final head = entry.head;
      if (head == null ||
          head.deleted != deleted ||
          head.measuredOn.compareTo(widget.endDay) > 0) {
        continue;
      }
      rows.add(head);
    }
    rows.sort((a, b) {
      final byDay = b.measuredOn.compareTo(a.measuredOn);
      return byDay != 0 ? byDay : a.id.compareTo(b.id);
    });
    return rows;
  }

  Future<void> _add() async {
    final result = await _showOpenBandVo2Editor(
      context: context,
      repository: widget.repository,
      initialDay: dayLabelOf(_latestDraftDay),
      lastDate: _latestDraftDay,
      now: widget.now,
      newId: const Uuid().v4(),
    );
    if (!mounted) return;
    await _load(afterCommit: result == _Vo2RouteResult.committed);
  }

  Future<void> _edit(Vo2Revision entry) async {
    final repository = widget.repository;
    Vo2Detail detail;
    try {
      detail = await repository.readVo2Entry(entry.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Eintrag konnte nicht geladen werden.')),
        );
      }
      return;
    }
    if (!mounted || !identical(repository, widget.repository)) return;
    final head = detail.head;
    if (detail.missing || detail.headCorrupt || head == null || head.deleted) {
      await _load();
      return;
    }
    final result = await _showOpenBandVo2Editor(
      context: context,
      repository: repository,
      existing: head,
      initialDetail: detail,
      initialDay: head.measuredOn,
      lastDate: _latestDraftDay,
      now: widget.now,
    );
    if (!mounted) return;
    await _load(afterCommit: result == _Vo2RouteResult.committed);
  }

  Future<void> _openRemoved(Vo2Revision entry) async {
    final result = await Navigator.of(context).push<_Vo2RouteResult>(
      MaterialPageRoute(
        builder: (_) => _Vo2RemovedPage(
          repository: widget.repository,
          initial: entry,
          now: widget.now,
        ),
      ),
    );
    if (!mounted) return;
    await _load(afterCommit: result == _Vo2RouteResult.committed);
  }

  void _showInfo() => _showVo2Info(context);

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: ListView(
          key: const ValueKey('vo2-scroll'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            OBPageHeader(
              title: 'VO₂max',
              subtitle: '',
              onInfo: _showInfo,
              infoLabel: 'Über VO₂max',
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_readError)
              _issueCard('Einträge konnten nicht geladen werden.', _load)
            else if (_savedRefreshError)
              ..._committedButUnavailable(p)
            else if (_list != null)
              ..._content(p, _list!),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(OB p, Vo2List list) {
    final active = _visible(list, deleted: false);
    final removed = _visible(list, deleted: true);
    final latest = active.isEmpty ? null : active.first;
    return [
      _hero(p, latest, unreadable: latest == null && list.corruptCount > 0),
      if (latest == null) ...[
        const SizedBox(height: 12),
        OBAction(
          'Eintragen',
          key: const ValueKey('vo2-add-empty'),
          ink: true,
          onPressed: _add,
        ),
      ],
      if (latest != null) ...[
        const SizedBox(height: 12),
        _sectionHeading(p, 'Einträge', add: true),
        const SizedBox(height: 10),
        _entryList(active, removed: false),
      ],
      if (list.corruptCount > 0 && latest != null) ...[
        const SizedBox(height: 10),
        OBCard(
          child: Text(
            '${list.corruptCount} ${list.corruptCount == 1 ? 'Eintrag' : 'Einträge'} nicht lesbar',
            key: const ValueKey('vo2-unreadable-count'),
            style: p.text(13, color: p.muted),
          ),
        ),
      ],
      if (removed.isNotEmpty) ...[
        const SizedBox(height: 12),
        _sectionHeading(p, 'Entfernt'),
        const SizedBox(height: 10),
        _entryList(removed, removed: true),
      ],
    ];
  }

  List<Widget> _committedButUnavailable(OB p) => [
    _hero(p, null, unreadable: false, showStatus: false),
    const SizedBox(height: 12),
    _issueCard(
      'Gespeichert. Einträge konnten nicht aktualisiert werden.',
      () => _load(afterCommit: true),
    ),
  ];

  Widget _hero(
    OB p,
    Vo2Revision? latest, {
    required bool unreadable,
    bool showStatus = true,
  }) {
    final content = OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (latest != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Eingetragen',
                    style: p
                        .text(13, weight: FontWeight.w600, color: p.muted)
                        .copyWith(height: 18 / 13),
                  ),
                ),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(LucideIcons.pencil, size: 18, color: p.muted),
                ),
              ],
            ),
          if (latest != null) const SizedBox(height: 6),
          _Vo2ValueLine(
            value: latest == null ? '—' : _vo2Number(latest.valueMlKgMin),
            valueSize: 44,
            valueWeight: FontWeight.w800,
            valueLineHeight: 46 / 44,
            valueKey: const ValueKey('vo2-hero-value'),
            unitKey: const ValueKey('vo2-hero-unit'),
          ),
          if (latest != null) ...[
            const SizedBox(height: 6),
            Text(
              '${_shortDate(latest.measuredOn, widget.now())} · ${latest.declaredMethod ?? 'Methode —'}',
              style: p
                  .text(13, weight: FontWeight.w600, color: p.muted)
                  .copyWith(height: 18 / 13),
            ),
          ] else if (showStatus) ...[
            const SizedBox(height: 6),
            Text(
              unreadable ? 'Eintrag nicht lesbar' : 'Noch keine Einträge',
              style: p
                  .text(13, weight: FontWeight.w600, color: p.muted)
                  .copyWith(height: 18 / 13),
            ),
          ],
        ],
      ),
    );
    if (latest == null) return content;
    return Semantics(
      button: true,
      label:
          'Eintrag vom ${_longDate(latest.measuredOn, widget.now())} bearbeiten',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('vo2-hero-edit'),
          borderRadius: BorderRadius.circular(AlpRadius.card),
          onTap: () => _edit(latest),
          child: content,
        ),
      ),
    );
  }

  Widget _sectionHeading(OB p, String title, {bool add = false}) =>
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: p
                      .text(20, weight: FontWeight.w700, display: true)
                      .copyWith(height: 24 / 20),
                ),
              ),
              if (add)
                SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton(
                    key: const ValueKey('vo2-add'),
                    tooltip: 'Eintrag hinzufügen',
                    onPressed: _add,
                    icon: Icon(LucideIcons.plus, color: p.ink),
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _entryList(List<Vo2Revision> entries, {required bool removed}) =>
      Container(
        decoration: BoxDecoration(
          color: OB.of(context).card,
          borderRadius: BorderRadius.circular(AlpRadius.card),
        ),
        child: Column(
          children: [
            for (final (index, entry) in entries.indexed) ...[
              if (index > 0)
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  color: OB.of(context).line,
                ),
              OBSettingsValueRow(
                key: ValueKey(
                  removed ? 'vo2-removed-${entry.id}' : 'vo2-entry-${entry.id}',
                ),
                label: _longDate(entry.measuredOn, widget.now()),
                value: _vo2Number(entry.valueMlKgMin),
                labelWeight: FontWeight.w400,
                valueWeight: FontWeight.w500,
                mutedValue: true,
                chevron: true,
                onTap: () => removed ? _openRemoved(entry) : _edit(entry),
              ),
            ],
          ],
        ),
      );

  Widget _issueCard(String message, Future<bool> Function() retry) => OBCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          message,
          style: OB.of(context).text(14, color: OB.of(context).danger),
        ),
        const SizedBox(height: 8),
        OBAction(
          'Erneut',
          key: const ValueKey('vo2-read-retry'),
          secondary: true,
          ink: true,
          onPressed: retry,
        ),
      ],
    ),
  );
}

Future<_Vo2RouteResult?> _showOpenBandVo2Editor({
  required BuildContext context,
  required OpenBandRepository repository,
  required String initialDay,
  required DateTime lastDate,
  required DateTime Function() now,
  Vo2Revision? existing,
  Vo2Detail? initialDetail,
  String? newId,
}) {
  assert(existing != null || newId != null);
  return showModalBottomSheet<_Vo2RouteResult>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x52000000),
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _Vo2Editor(
      repository: repository,
      initialDay: initialDay,
      lastDate: lastDate,
      now: now,
      existing: existing,
      initialDetail: initialDetail,
      newId: newId,
    ),
  );
}

enum _Vo2FailedAction { save, remove }

enum _Vo2HeadIssue { missing, corrupt, readFailed }

String _vo2HeadIssueText(_Vo2HeadIssue issue) => switch (issue) {
  _Vo2HeadIssue.missing => 'Eintrag nicht gefunden',
  _Vo2HeadIssue.corrupt => 'Eintrag nicht lesbar',
  _Vo2HeadIssue.readFailed => 'Laden fehlgeschlagen',
};

class _Vo2Editor extends StatefulWidget {
  const _Vo2Editor({
    required this.repository,
    required this.initialDay,
    required this.lastDate,
    required this.now,
    this.existing,
    this.initialDetail,
    this.newId,
  });

  final OpenBandRepository repository;
  final String initialDay;
  final DateTime lastDate;
  final DateTime Function() now;
  final Vo2Revision? existing;
  final Vo2Detail? initialDetail;
  final String? newId;

  @override
  State<_Vo2Editor> createState() => _Vo2EditorState();
}

class _Vo2EditorState extends State<_Vo2Editor> {
  late Vo2Revision? _base = widget.existing;
  late Vo2Detail? _detail = widget.initialDetail;
  late String _day = widget.initialDay;
  late final TextEditingController _value = TextEditingController(
    text: _base == null ? '' : _editableNumber(_base!.valueMlKgMin),
  );
  late final TextEditingController _method = TextEditingController(
    text: _base?.declaredMethod ?? '',
  );
  bool _busy = false;
  bool _conflict = false;
  _Vo2HeadIssue? _headIssue;
  _Vo2FailedAction? _failedAction;
  String? _validation;

  @override
  void dispose() {
    _value.dispose();
    _method.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    if (_busy) return;
    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _Vo2DatePage(
          initial: DateTime.parse(_day),
          lastDate: widget.lastDate,
          now: widget.now(),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _day = picked);
  }

  Future<void> _history() async {
    if (_busy || _base == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _Vo2HistoryPage(
          repository: widget.repository,
          id: _base!.id,
          now: widget.now,
          initial: _detail,
        ),
      ),
    );
  }

  ({double value, String? method})? _draft() {
    final raw = _value.text.trim().replaceAll(',', '.');
    final parsed = double.tryParse(raw);
    if (parsed == null || !parsed.isFinite || parsed <= 0) {
      setState(() => _validation = 'Wert muss eine positive Zahl sein.');
      return null;
    }
    return (value: parsed, method: _method.text);
  }

  Future<void> _save() async {
    if (_busy || _headIssue != null) return;
    final draft = _draft();
    if (draft == null) return;
    setState(() {
      _busy = true;
      _validation = null;
      _conflict = false;
      _headIssue = null;
      _failedAction = null;
    });
    try {
      final result = _base == null
          ? await widget.repository.createVo2Entry(
              id: widget.newId!,
              measuredOn: _day,
              valueMlKgMin: draft.value,
              declaredMethod: draft.method,
            )
          : await widget.repository.editVo2Entry(
              id: _base!.id,
              expectedRevision: _base!.revision,
              measuredOn: _day,
              valueMlKgMin: draft.value,
              declaredMethod: draft.method,
            );
      if (!mounted) return;
      if (result is Vo2Committed) {
        Navigator.pop(context, _Vo2RouteResult.committed);
        return;
      }
      setState(() {
        _busy = false;
        if (result is Vo2WriteConflict) {
          _conflict = true;
        } else {
          _failedAction = _Vo2FailedAction.save;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failedAction = _Vo2FailedAction.save;
      });
    }
  }

  Future<void> _remove() async {
    if (_busy || _base == null || _headIssue != null) return;
    setState(() {
      _busy = true;
      _validation = null;
      _conflict = false;
      _headIssue = null;
      _failedAction = null;
    });
    try {
      final result = await widget.repository.removeVo2Entry(
        id: _base!.id,
        expectedRevision: _base!.revision,
      );
      if (!mounted) return;
      if (result is Vo2Committed) {
        Navigator.pop(context, _Vo2RouteResult.committed);
        return;
      }
      setState(() {
        _busy = false;
        if (result is Vo2WriteConflict) {
          _conflict = true;
        } else {
          _failedAction = _Vo2FailedAction.remove;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failedAction = _Vo2FailedAction.remove;
      });
    }
  }

  Future<void> _reload() async {
    if (_busy) return;
    final id = _base?.id ?? widget.newId;
    if (id == null) return;
    setState(() {
      _busy = true;
      _headIssue = null;
    });
    try {
      final detail = await widget.repository.readVo2Entry(id);
      if (!mounted) return;
      final head = detail.head;
      if (detail.missing || detail.headCorrupt || head == null) {
        setState(() {
          _busy = false;
          _conflict = false;
          _headIssue = detail.missing
              ? _Vo2HeadIssue.missing
              : _Vo2HeadIssue.corrupt;
        });
        return;
      }
      if (head.deleted) {
        Navigator.pop(context);
        return;
      }
      setState(() {
        _busy = false;
        _base = head;
        _detail = detail;
        _day = head.measuredOn;
        _value.text = _editableNumber(head.valueMlKgMin);
        _method.text = head.declaredMethod ?? '';
        _conflict = false;
        _headIssue = null;
        _failedAction = null;
        _validation = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _conflict = false;
        _headIssue = _Vo2HeadIssue.readFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final media = MediaQuery.of(context);
    final effectiveBottom = math.max(
      media.viewPadding.bottom,
      media.padding.bottom,
    );
    final sheetBottom = 20.0 + math.max(34.0, effectiveBottom);
    return PopScope(
      canPop: !_busy,
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: LayoutBuilder(
          builder: (context, constraints) => Material(
            key: const ValueKey('vo2-editor'),
            color: p.card,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AlpRadius.card),
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: constraints.maxHeight),
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, sheetBottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sheetHeader(p),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 16),
                            _label(p, 'Wert'),
                            const SizedBox(height: 6),
                            _valueField(p),
                            const SizedBox(height: 16),
                            _label(p, 'Datum'),
                            const SizedBox(height: 6),
                            _dateField(p),
                            const SizedBox(height: 16),
                            _label(p, 'Methode · optional'),
                            const SizedBox(height: 6),
                            _methodField(p),
                            if (_base != null) ...[
                              const SizedBox(height: 16),
                              OBSettingsValueRow(
                                key: const ValueKey('vo2-history'),
                                label: 'Änderungen',
                                value: '',
                                labelWeight: FontWeight.w400,
                                chevron: true,
                                onTap: _history,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (_validation != null) ...[
                      const SizedBox(height: 12),
                      Text(_validation!, style: p.text(14, color: p.danger)),
                    ],
                    if (_conflict ||
                        _headIssue != null ||
                        _failedAction != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _headIssue != null
                            ? _vo2HeadIssueText(_headIssue!)
                            : _conflict
                            ? 'Eintrag wurde geändert'
                            : _failedAction == _Vo2FailedAction.remove
                            ? 'Entfernen fehlgeschlagen'
                            : 'Speichern fehlgeschlagen',
                        key: const ValueKey('vo2-editor-error'),
                        style: p.text(14, color: p.danger),
                      ),
                    ],
                    const SizedBox(height: 16),
                    OBAction(
                      _conflict || _headIssue != null
                          ? 'Neu laden'
                          : _failedAction != null
                          ? 'Erneut versuchen'
                          : 'Speichern',
                      key: const ValueKey('vo2-save'),
                      ink: true,
                      onPressed: _busy
                          ? null
                          : _conflict || _headIssue != null
                          ? _reload
                          : _failedAction == _Vo2FailedAction.remove
                          ? _remove
                          : _save,
                    ),
                    if (_base != null) ...[
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 44,
                        child: TextButton(
                          key: const ValueKey('vo2-remove'),
                          onPressed: _busy || _conflict || _headIssue != null
                              ? null
                              : _remove,
                          style: TextButton.styleFrom(
                            foregroundColor: p.danger,
                          ),
                          child: const Text('Eintrag entfernen'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheetHeader(OB p) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 44),
    child: Row(
      children: [
        Expanded(
          child: Text(
            'VO₂max',
            style: p
                .text(18, weight: FontWeight.w600)
                .copyWith(height: 24 / 18),
          ),
        ),
        SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
            tooltip: 'Schließen',
            onPressed: _busy ? null : () => Navigator.pop(context),
            padding: EdgeInsets.zero,
            icon: Icon(LucideIcons.x, size: 20, color: p.ink),
          ),
        ),
      ],
    ),
  );

  Widget _label(OB p, String text) => Text(
    text,
    style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
  );

  Widget _well(OB p, Widget child, {double minHeight = 48}) => DecoratedBox(
    decoration: BoxDecoration(
      color: p.well,
      borderRadius: BorderRadius.circular(AlpRadius.well),
    ),
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    ),
  );

  Widget _valueField(OB p) => _well(
    p,
    Row(
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('vo2-value-input'),
            controller: _value,
            enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,eE+\-]')),
            ],
            style: p
                .text(28, weight: FontWeight.w700, display: true)
                .copyWith(height: 34 / 28),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(kVo2Unit, style: p.text(15, color: p.muted)),
      ],
    ),
    minHeight: 56,
  );

  Widget _dateField(OB p) => Semantics(
    button: true,
    label: 'Datum, ${_fullDate(_day)}',
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('vo2-date-input'),
        borderRadius: BorderRadius.circular(AlpRadius.well),
        onTap: _busy ? null : _pickDate,
        child: _well(
          p,
          Row(
            children: [
              Expanded(child: Text(_fullDate(_day), style: p.text(15))),
              Icon(LucideIcons.calendarDays, size: 18, color: p.muted),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _methodField(OB p) => _well(
    p,
    TextField(
      key: const ValueKey('vo2-method-input'),
      controller: _method,
      enabled: !_busy,
      textCapitalization: TextCapitalization.sentences,
      style: p.text(15),
      decoration: const InputDecoration(
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
    ),
  );
}

class _Vo2DatePage extends StatefulWidget {
  const _Vo2DatePage({
    required this.initial,
    required this.lastDate,
    required this.now,
  });

  final DateTime initial;
  final DateTime lastDate;
  final DateTime now;

  @override
  State<_Vo2DatePage> createState() => _Vo2DatePageState();
}

class _Vo2DatePageState extends State<_Vo2DatePage> {
  late DateTime selected = DateTime(
    widget.initial.year,
    widget.initial.month,
    widget.initial.day,
  );
  late DateTime month = DateTime(selected.year, selected.month);

  bool get _canGoPrev =>
      !DateTime(month.year, month.month - 1).isBefore(DateTime(1));

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final day = dayLabelOf(selected);
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: ListView(
          key: const ValueKey('vo2-calendar'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const OBPageHeader(title: 'Datum', subtitle: ''),
            OBCard(
              padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
              child: OBCalendar(
                month: month,
                selected: selected,
                now: widget.now,
                lastDate: widget.lastDate,
                onSelect: (date) => setState(() {
                  selected = DateTime(date.year, date.month, date.day);
                  month = DateTime(date.year, date.month);
                }),
                onPrevMonth: _canGoPrev
                    ? () => setState(
                        () => month = DateTime(month.year, month.month - 1),
                      )
                    : null,
                onNextMonth: () => setState(
                  () => month = DateTime(month.year, month.month + 1),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OBAction(
              '${obDate(day)} übernehmen',
              key: const ValueKey('vo2-date-apply'),
              ink: true,
              onPressed: () => Navigator.pop(context, day),
            ),
          ],
        ),
      ),
    );
  }
}

class _Vo2RemovedPage extends StatefulWidget {
  const _Vo2RemovedPage({
    required this.repository,
    required this.initial,
    required this.now,
  });

  final OpenBandRepository repository;
  final Vo2Revision initial;
  final DateTime Function() now;

  @override
  State<_Vo2RemovedPage> createState() => _Vo2RemovedPageState();
}

class _Vo2RemovedPageState extends State<_Vo2RemovedPage> {
  late Vo2Revision _head = widget.initial;
  Vo2Detail? _detail;
  bool _loading = true;
  _Vo2HeadIssue? _headIssue;
  bool _busy = false;
  bool _conflict = false;
  bool _writeError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _headIssue = null;
    });
    try {
      final detail = await widget.repository.readVo2Entry(widget.initial.id);
      if (!mounted) return;
      final head = detail.head;
      if (detail.missing || detail.headCorrupt || head == null) {
        setState(() {
          _loading = false;
          _headIssue = detail.missing
              ? _Vo2HeadIssue.missing
              : _Vo2HeadIssue.corrupt;
        });
        return;
      }
      if (!head.deleted) {
        Navigator.pop(context);
        return;
      }
      setState(() {
        _loading = false;
        _detail = detail;
        _head = head;
        _headIssue = null;
        _conflict = false;
        _writeError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _headIssue = _Vo2HeadIssue.readFailed;
      });
    }
  }

  Future<void> _restore() async {
    if (_busy || _headIssue != null) return;
    setState(() {
      _busy = true;
      _writeError = false;
      _conflict = false;
      _headIssue = null;
    });
    try {
      final result = await widget.repository.restoreVo2Entry(
        id: _head.id,
        expectedRevision: _head.revision,
      );
      if (!mounted) return;
      if (result is Vo2Committed) {
        Navigator.pop(context, _Vo2RouteResult.committed);
        return;
      }
      setState(() {
        _busy = false;
        if (result is Vo2WriteConflict) {
          _conflict = true;
        } else {
          _writeError = true;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _writeError = true;
      });
    }
  }

  Future<void> _reload() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _headIssue = null;
    });
    try {
      final detail = await widget.repository.readVo2Entry(_head.id);
      if (!mounted) return;
      final head = detail.head;
      if (detail.missing || detail.headCorrupt || head == null) {
        setState(() {
          _busy = false;
          _conflict = false;
          _headIssue = detail.missing
              ? _Vo2HeadIssue.missing
              : _Vo2HeadIssue.corrupt;
        });
        return;
      }
      if (!head.deleted) {
        Navigator.pop(context);
        return;
      }
      setState(() {
        _busy = false;
        _head = head;
        _detail = detail;
        _headIssue = null;
        _conflict = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _conflict = false;
        _headIssue = _Vo2HeadIssue.readFailed;
      });
    }
  }

  Future<void> _history() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _Vo2HistoryPage(
          repository: widget.repository,
          id: _head.id,
          now: widget.now,
          initial: _detail,
        ),
      ),
    );
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
            const OBPageHeader(title: 'VO₂max', subtitle: ''),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_headIssue != null)
              _removedIssue(p, _vo2HeadIssueText(_headIssue!), _load)
            else ...[
              OBCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Entfernt',
                      style: p
                          .text(13, weight: FontWeight.w600, color: p.muted)
                          .copyWith(height: 18 / 13),
                    ),
                    const SizedBox(height: 6),
                    _Vo2ValueLine(
                      value: _vo2Number(_head.valueMlKgMin),
                      valueSize: 44,
                      valueWeight: FontWeight.w800,
                      valueLineHeight: 46 / 44,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_shortDate(_head.measuredOn, widget.now())} · ${_head.declaredMethod ?? 'Methode —'}',
                      style: p
                          .text(13, weight: FontWeight.w600, color: p.muted)
                          .copyWith(height: 18 / 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OBSettingsValueRow(
                key: const ValueKey('vo2-removed-history'),
                label: 'Änderungen',
                value: '',
                labelWeight: FontWeight.w400,
                chevron: true,
                onTap: _history,
              ),
              if (_conflict || _writeError) ...[
                const SizedBox(height: 12),
                Text(
                  _conflict
                      ? 'Eintrag wurde geändert'
                      : 'Wiederherstellen fehlgeschlagen',
                  style: p.text(14, color: p.danger),
                ),
              ],
              const SizedBox(height: 12),
              OBAction(
                _conflict
                    ? 'Neu laden'
                    : _writeError
                    ? 'Erneut versuchen'
                    : 'Wiederherstellen',
                key: const ValueKey('vo2-restore'),
                ink: true,
                onPressed: _busy
                    ? null
                    : _conflict
                    ? _reload
                    : _restore,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _removedIssue(OB p, String text, Future<void> Function() retry) =>
      OBCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(text, style: p.text(14, color: p.danger)),
            const SizedBox(height: 8),
            OBAction('Erneut', secondary: true, ink: true, onPressed: retry),
          ],
        ),
      );
}

class _Vo2HistoryPage extends StatefulWidget {
  const _Vo2HistoryPage({
    required this.repository,
    required this.id,
    required this.now,
    this.initial,
  });

  final OpenBandRepository repository;
  final String id;
  final DateTime Function() now;
  final Vo2Detail? initial;

  @override
  State<_Vo2HistoryPage> createState() => _Vo2HistoryPageState();
}

class _Vo2HistoryPageState extends State<_Vo2HistoryPage> {
  Vo2Detail? _detail;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _detail = widget.initial;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final detail = await widget.repository.readVo2Entry(widget.id);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final slots =
        _detail?.revisions.reversed.toList() ?? const <Vo2RevisionSlot>[];
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: ListView(
          key: const ValueKey('vo2-history-page'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            OBPageHeader(
              title: 'Änderungen',
              subtitle: '',
              onInfo: () => _showVo2Info(context),
              infoLabel: 'Über VO₂max',
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error)
              OBCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Änderungen konnten nicht geladen werden.',
                      style: p.text(14, color: p.danger),
                    ),
                    const SizedBox(height: 8),
                    OBAction(
                      'Erneut',
                      secondary: true,
                      ink: true,
                      onPressed: _load,
                    ),
                  ],
                ),
              )
            else
              for (final (index, slot) in slots.indexed) ...[
                if (index > 0) const SizedBox(height: 10),
                _revisionCard(p, slot),
              ],
          ],
        ),
      ),
    );
  }

  Widget _revisionCard(OB p, Vo2RevisionSlot slot) {
    final revision = slot.value;
    if (revision == null) {
      return OBCard(
        child: Text(
          slot.revision == null
              ? 'Änderung nicht lesbar'
              : 'Änderung ${slot.revision} nicht lesbar',
          style: p.text(14, color: p.muted),
        ),
      );
    }
    return OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _revisionTimestamp(revision.updatedAt, widget.now()),
            style: p.text(13, weight: FontWeight.w600, color: p.muted),
          ),
          const SizedBox(height: 6),
          _Vo2ValueLine(
            value: _vo2Number(revision.valueMlKgMin),
            valueSize: 28,
            valueWeight: FontWeight.w700,
            valueLineHeight: 34 / 28,
          ),
          const SizedBox(height: 6),
          Text(
            '${revision.deleted ? 'Entfernt' : 'Wert'} vom ${_shortDate(revision.measuredOn, widget.now())} · ${revision.declaredMethod ?? 'Methode —'}',
            style: p.text(13, weight: FontWeight.w600, color: p.muted),
          ),
        ],
      ),
    );
  }
}

class _Vo2ValueLine extends StatelessWidget {
  const _Vo2ValueLine({
    required this.value,
    required this.valueSize,
    required this.valueWeight,
    required this.valueLineHeight,
    this.valueKey,
    this.unitKey,
  });

  final String value;
  final double valueSize;
  final FontWeight valueWeight;
  final double valueLineHeight;
  final Key? valueKey;
  final Key? unitKey;

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final valueStyle = p
        .text(valueSize, weight: valueWeight, display: true)
        .copyWith(height: valueLineHeight);
    final unitStyle = p
        .text(14, weight: FontWeight.w500, color: p.muted)
        .copyWith(height: 18 / 14);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);

    double widthOf(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final valueWidth = widthOf(value, valueStyle);
        final unitWidth = widthOf(kVo2Unit, unitStyle);
        final largeText = scaler.scale(14) > 20;
        final stacked =
            largeText || valueWidth + 4 + unitWidth > constraints.maxWidth;
        final number = Text(
          value,
          maxLines: 1,
          softWrap: false,
          style: valueStyle,
        );
        if (!stacked) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                key: valueKey,
                maxLines: 1,
                softWrap: false,
                style: valueStyle,
              ),
              const SizedBox(width: 4),
              Text(kVo2Unit, key: unitKey, style: unitStyle),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              key: valueKey,
              width: constraints.maxWidth,
              child: FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: number,
              ),
            ),
            Text(kVo2Unit, key: unitKey, style: unitStyle),
          ],
        );
      },
    );
  }
}

String _vo2Number(double value) => obNumber(value, digits: 1);

String _revisionTimestamp(int updatedAt, DateTime now) {
  try {
    final updated = DateTime.fromMillisecondsSinceEpoch(updatedAt);
    return '${_shortDate(dayLabelOf(updated), now)} · ${DateFormat('HH:mm', 'de_DE').format(updated)}';
  } on ArgumentError {
    return '—';
  }
}

String _editableNumber(double value) {
  var text = value.toString();
  if (text.endsWith('.0')) text = text.substring(0, text.length - 2);
  return text.replaceAll('.', ',');
}

String _shortDate(String day, DateTime now) {
  final date = DateTime.parse(day);
  return DateFormat(
    date.year == now.year ? 'd. MMM' : 'd. MMM y',
    'de_DE',
  ).format(date);
}

String _longDate(String day, DateTime now) {
  final date = DateTime.parse(day);
  return DateFormat(
    date.year == now.year ? 'd. MMMM' : 'd. MMMM y',
    'de_DE',
  ).format(date);
}

String _fullDate(String day) =>
    DateFormat('d. MMMM y', 'de_DE').format(DateTime.parse(day));
