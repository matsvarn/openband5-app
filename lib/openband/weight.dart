import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/day_label.dart';
import '../data/journal_fields.dart';
import 'calendar.dart';
import 'calendar_line.dart';
import 'domain.dart';
import 'health.dart' show OBSegmented;
import 'journal_controls.dart';
import 'journal_value_editor.dart';
import 'settings_controls.dart';
import 'theme.dart';

/// Dated, manually entered Journal weight. This screen never reads profile
/// weight and never manufactures values for missing calendar days.
class OpenBandWeight extends StatefulWidget {
  const OpenBandWeight({
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
          OpenBandWeight(repository: repository, endDay: endDay, now: now),
    ),
  );

  @override
  State<OpenBandWeight> createState() => _OpenBandWeightState();
}

class _OpenBandWeightState extends State<OpenBandWeight> {
  static final JournalFieldSpec _spec =
      kJournalFieldsByKey[kWeightJournalField]!;

  int _days = 7;
  int _generation = 0;
  WeightHistory? _history;
  bool _loading = true;
  bool _readError = false;
  bool _savedRefreshError = false;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    requireWeightHistoryDay(widget.endDay);
    _load();
  }

  @override
  void didUpdateWidget(covariant OpenBandWeight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository) ||
        oldWidget.endDay != widget.endDay) {
      _generation++;
      _history = null;
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

  Future<bool> _load({
    bool afterCommit = false,
    bool discardExisting = false,
  }) async {
    final generation = ++_generation;
    final repository = widget.repository;
    final day = widget.endDay;
    final days = _days;
    setState(() {
      if (afterCommit || discardExisting) _history = null;
      _loading = true;
      if (!afterCommit) _readError = false;
      _savedRefreshError = false;
      _actionError = null;
    });
    try {
      final history = await repository.readWeightHistory(day, days);
      if (!mounted ||
          generation != _generation ||
          !identical(repository, widget.repository) ||
          day != widget.endDay ||
          days != _days) {
        return false;
      }
      setState(() {
        _history = history;
        _loading = false;
        _readError = false;
        _savedRefreshError = false;
      });
      return true;
    } catch (_) {
      if (!mounted ||
          generation != _generation ||
          !identical(repository, widget.repository) ||
          day != widget.endDay ||
          days != _days) {
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

  void _selectDays(int index) {
    final days = const [7, 30, 90][index];
    if (days == _days) return;
    setState(() {
      _days = days;
      _loading = true;
      _readError = false;
      _savedRefreshError = false;
    });
    _load();
  }

  DateTime get _lastDate {
    final end = DateTime.parse(widget.endDay);
    final now = widget.now();
    final today = DateTime(now.year, now.month, now.day);
    return end.isBefore(today) ? end : today;
  }

  Future<void> _add() async {
    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _WeightDatePage(
          initial: _lastDate,
          now: widget.now(),
          lastDate: _lastDate,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _edit(picked);
  }

  Future<void> _edit(String day) async {
    final repository = widget.repository;
    JournalDaySnapshot base;
    try {
      base = await repository.readJournalDay(day);
    } catch (_) {
      if (mounted) {
        setState(() => _actionError = 'Eintrag konnte nicht geladen werden.');
      }
      return;
    }
    if (!mounted || !identical(repository, widget.repository)) return;
    var currentBase = base;
    final existing = base.metrics[kWeightJournalField];
    final result = await showOpenBandJournalValueSheet(
      context: context,
      spec: _spec,
      metric: existing,
      contextLabel: _dateLabel(day),
      showRemove: existing != null,
      apply: (value) async {
        if (!mounted || !identical(repository, widget.repository)) {
          return OpenBandJournalValueApplyOutcome.stale;
        }
        try {
          await repository.patchJournalDay(
            JournalDayPatch.fromBase(
              currentBase,
              metrics: {kWeightJournalField: value},
            ),
          );
          if (mounted) setState(() => _actionError = null);
          return OpenBandJournalValueApplyOutcome.committed;
        } on JournalConflict {
          return OpenBandJournalValueApplyOutcome.conflict;
        } catch (_) {
          return OpenBandJournalValueApplyOutcome.failed;
        }
      },
      reload: () async {
        currentBase = await repository.readJournalDay(day);
        return currentBase.metrics[kWeightJournalField];
      },
    );
    if (!mounted || !identical(repository, widget.repository)) return;
    // The editor may close after an external writer won a conflict. Always
    // reread, and withhold the old snapshot if that read fails. A non-null
    // result means our own patch committed, so keep its distinct error state.
    await _load(afterCommit: result != null, discardExisting: true);
  }

  List<WeightEntry> _entries(WeightHistory history) {
    return history.entries;
  }

  WeightEntry? _latest(WeightHistory history) => history.latest;

  String _dateLabel(String day) {
    final date = DateTime.parse(day);
    final includeYear = date.year != widget.now().year;
    return DateFormat(
      includeYear ? 'd. MMMM y' : 'd. MMMM',
      'de_DE',
    ).format(date);
  }

  String _shortDate(String day) => DateFormat(
    DateTime.parse(day).year == widget.now().year ? 'd. MMM' : 'd. MMM y',
    'de_DE',
  ).format(DateTime.parse(day));

  String _kg(double value) => '${obNumber(value, digits: 1)} kg';

  void _showInfo() => showOpenBandJournalInfo(
    context,
    title: 'Über Gewicht',
    paragraphs: const [
      'Quelle: Journal · eingegebene Werte',
      'Der Trend glättet die Einträge mit 7 Tagen Halbwertszeit. Tage ohne Eintrag bleiben Lücken.',
    ],
  );

  void _showDataStatus(WeightHistory history) => showOpenBandJournalInfo(
    context,
    title: 'Hinweise zu den Einträgen',
    paragraphs: [
      if (history.invalidCount > 0)
        '${history.invalidCount} ${history.invalidCount == 1 ? 'Wert liegt' : 'Werte liegen'} außerhalb des gültigen Bereichs und ${history.invalidCount == 1 ? 'wird' : 'werden'} im Trend nicht berücksichtigt.',
      if (history.unreadableCount > 0)
        '${history.unreadableCount} ${history.unreadableCount == 1 ? 'Eintrag konnte' : 'Einträge konnten'} nicht gelesen werden.',
    ],
  );

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: ListView(
          key: const ValueKey('weight-scroll'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            OBPageHeader(
              title: 'Gewicht',
              subtitle: '',
              onInfo: _showInfo,
              infoLabel: 'Über Gewicht',
            ),
            if (_loading && _history == null)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_readError && _history == null)
              _issueCard('Einträge konnten nicht geladen werden.', _load)
            else if (_savedRefreshError && _history == null)
              ..._unavailableAfterCommit(p)
            else if (_history != null)
              ..._content(p, _history!),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(OB p, WeightHistory history) {
    final entries = _entries(history);
    final latest = _latest(history);
    final corruptOnly = latest == null && history.unreadableCount > 0;
    return [
      _latestCard(p, latest, corruptOnly: corruptOnly),
      if (latest == null) ...[
        const SizedBox(height: 12),
        OBAction('Eintragen', ink: true, onPressed: _add),
      ],
      if (latest != null) ...[
        const SizedBox(height: 12),
        OBSegmented(
          labels: const ['7 Tage', '30 Tage', '90 Tage'],
          selected: const [7, 30, 90].indexOf(_days),
          onChanged: _selectDays,
        ),
      ],
      if (_loading) ...[
        const SizedBox(height: 24),
        const Center(child: CircularProgressIndicator()),
      ] else if (_readError) ...[
        const SizedBox(height: 12),
        _issueCard('Einträge konnten nicht geladen werden.', _load),
      ],
      if (!_loading && !_readError && latest != null) ...[
        const SizedBox(height: 12),
        OBCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _chartHeading(p, entries),
              const SizedBox(height: 10),
              OBCalendarLine(values: history.trend, days: _days),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _shortDate(history.window.first),
                      style: p.text(12, color: p.muted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _shortDate(history.window.last),
                      textAlign: TextAlign.end,
                      style: p.text(12, color: p.muted),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
      if (!_loading &&
          !_readError &&
          latest != null &&
          (history.invalidCount > 0 || history.unreadableCount > 0)) ...[
        const SizedBox(height: 10),
        Row(
          key: const ValueKey('weight-partial-status'),
          children: [
            Expanded(
              child: Text(
                [
                  if (history.invalidCount > 0)
                    '${history.invalidCount} ${history.invalidCount == 1 ? 'Wert' : 'Werte'} ausgeschlossen',
                  if (history.unreadableCount > 0)
                    '${history.unreadableCount} ${history.unreadableCount == 1 ? 'Eintrag' : 'Einträge'} unlesbar',
                ].join(' · '),
                style: p.text(13, color: p.muted),
              ),
            ),
            IconButton(
              key: const ValueKey('weight-partial-info'),
              tooltip: 'Details zu den Einträgen',
              onPressed: () => _showDataStatus(history),
              icon: Icon(LucideIcons.info, size: 18, color: p.muted),
            ),
          ],
        ),
      ],
      if (_actionError != null) ...[
        const SizedBox(height: 10),
        Text(_actionError!, style: p.text(14, color: p.danger)),
      ],
      if (!_loading && !_readError && latest != null) ...[
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Einträge',
                    style: p
                        .text(20, weight: FontWeight.w700, display: true)
                        .copyWith(height: 24 / 20),
                  ),
                ),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton(
                    key: const ValueKey('weight-add'),
                    tooltip: 'Eintrag hinzufügen',
                    onPressed: _add,
                    icon: Icon(LucideIcons.plus, color: p.action),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (entries.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                for (final (index, entry) in entries.indexed) ...[
                  if (index > 0)
                    Container(
                      height: 1,
                      margin: const EdgeInsets.symmetric(horizontal: 14),
                      color: p.line,
                    ),
                  _entryRow(entry),
                ],
              ],
            ),
          ),
        ],
      ],
    ];
  }

  List<Widget> _unavailableAfterCommit(OB p) => [
    _latestCard(p, null, corruptOnly: false, showMissingStatus: false),
    const SizedBox(height: 12),
    _issueCard(
      'Gespeichert. Verlauf konnte nicht aktualisiert werden.',
      () => _load(afterCommit: true),
    ),
  ];

  Widget _chartHeading(OB p, List<WeightEntry> entries) {
    final title = Text(
      'Trend',
      style: p.text(13, weight: FontWeight.w600, color: p.muted),
    );
    final count = Text(
      '${entries.where((e) => e.usableForTrend).length} Einträge',
      style: p.text(13, weight: FontWeight.w500, color: p.muted),
    );
    if (MediaQuery.textScalerOf(context).scale(13) > 20) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [title, const SizedBox(height: 4), count],
      );
    }
    return Row(
      children: [
        Expanded(child: title),
        count,
      ],
    );
  }

  Widget _latestCard(
    OB p,
    WeightEntry? latest, {
    required bool corruptOnly,
    bool showMissingStatus = true,
  }) {
    final card = OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.scale, size: 16, color: p.ink),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  latest == null
                      ? 'Journal'
                      : 'Journal · ${_shortDate(latest.day)}',
                  style: p.text(13, weight: FontWeight.w600, color: p.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  latest == null ? '—' : obNumber(latest.value, digits: 1),
                  style: p
                      .text(44, weight: FontWeight.w800, display: true)
                      .copyWith(height: 46 / 44),
                ),
              ),
              if (latest != null) ...[
                const SizedBox(width: 4),
                Text('kg', style: p.text(14, color: p.muted)),
              ],
            ],
          ),
          if (latest == null && showMissingStatus) ...[
            const SizedBox(height: 6),
            Text(
              corruptOnly ? 'Einträge nicht lesbar' : 'Noch keine Einträge',
              style: p.text(13, weight: FontWeight.w600, color: p.muted),
            ),
          ] else if (latest != null && !latest.usableForTrend) ...[
            const SizedBox(height: 6),
            Text('Vom Trend ausgeschlossen', style: p.text(13, color: p.muted)),
          ],
        ],
      ),
    );
    if (latest == null) return card;
    return Semantics(
      button: true,
      label: 'Eintrag vom ${_dateLabel(latest.day)} bearbeiten',
      child: InkWell(
        key: const ValueKey('weight-latest-edit'),
        borderRadius: BorderRadius.circular(24),
        onTap: () => _edit(latest.day),
        child: card,
      ),
    );
  }

  Widget _entryRow(WeightEntry entry) {
    return OBSettingsValueRow(
      key: ValueKey('weight-entry-${entry.day}'),
      label: _dateLabel(entry.day),
      value: _kg(entry.value),
      labelWeight: FontWeight.w400,
      valueWeight: FontWeight.w500,
      mutedValue: true,
      chevron: true,
      onTap: () => _edit(entry.day),
    );
  }

  Widget _issueCard(String message, Future<bool> Function() retry) {
    final p = OB.of(context);
    return OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(message, style: p.text(14, color: p.danger)),
          const SizedBox(height: 8),
          OBAction('Erneut', secondary: true, ink: true, onPressed: retry),
        ],
      ),
    );
  }
}

class _WeightDatePage extends StatefulWidget {
  const _WeightDatePage({
    required this.initial,
    required this.now,
    required this.lastDate,
  });

  final DateTime initial;
  final DateTime now;
  final DateTime lastDate;

  @override
  State<_WeightDatePage> createState() => _WeightDatePageState();
}

class _WeightDatePageState extends State<_WeightDatePage> {
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
              ink: true,
              onPressed: () => Navigator.pop(context, day),
            ),
          ],
        ),
      ),
    );
  }
}
