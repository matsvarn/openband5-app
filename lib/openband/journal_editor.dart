import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../ai/journal_ai.dart' show kJournalPresetTags;
import '../data/day_label.dart';
import '../data/journal_fields.dart';
import '../state/app_state.dart';
import 'alp_tokens.dart';
import 'confirm_sheet.dart';
import 'domain.dart';
import 'journal_controls.dart';
import 'journal_fields.dart';
import 'journal_value_editor.dart';
import 'local_repository.dart';
import 'theme.dart';

const _tagLabels = <String, String>{
  'caffeine': 'Koffein',
  'alcohol': 'Alkohol',
  'late meal': 'Spätes Essen',
  'stress': 'Stress',
  'poor sleep': 'Schlecht geschlafen',
  'travel': 'Reise',
  'screens late': 'Bildschirm am Abend',
  'meds': 'Medikamente',
  'sick': 'Krank',
  'sauna': 'Sauna',
  'cold plunge': 'Eisbad',
  'social': 'Gesellig',
  'workout': 'Training',
  'rest day': 'Ruhetag',
};

String journalTagLabel(String tag) => _tagLabels[tag] ?? tag;

/// Notification/legacy route: captures [date] or local today once.
class OpenBandJournalEditorRoute extends StatefulWidget {
  final String? date;
  const OpenBandJournalEditorRoute({super.key, this.date});

  @override
  State<OpenBandJournalEditorRoute> createState() =>
      _OpenBandJournalEditorRouteState();
}

class _OpenBandJournalEditorRouteState
    extends State<OpenBandJournalEditorRoute> {
  late final String day = widget.date ?? todayLabel();

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return OpenBandJournalEditor(
      repository: LocalOpenBandRepository(app),
      day: day,
    );
  }
}

class OpenBandJournalEditor extends StatefulWidget {
  final OpenBandRepository repository;
  final String day;
  const OpenBandJournalEditor({
    super.key,
    required this.repository,
    required this.day,
  });

  @override
  State<OpenBandJournalEditor> createState() => _OpenBandJournalEditorState();
}

class _OpenBandJournalEditorState extends State<OpenBandJournalEditor> {
  late final String day = widget.day;
  JournalDaySnapshot? _base;
  Map<String, JournalMetricValue> _values = {};
  List<String> _tags = [];
  final _note = TextEditingController();
  List<JournalFieldSpec> _fields = const [];
  List<JournalFieldSpec> _allDefs = const [];
  bool _loading = true;
  bool _loadError = false;
  bool _saving = false;
  bool _reloading = false;
  bool _conflict = false;
  String? _saveError;
  String? _fieldsError;

  bool get _busy => _saving || _reloading;

  bool get _dirty {
    final base = _base;
    if (base == null) return false;
    if (_note.text != base.note) return true;
    if (!_sameTags(_tags, base.tags)) return true;
    final keys = {...base.metrics.keys, ..._values.keys};
    for (final k in keys) {
      if (base.metrics[k] != _values[k]) return true;
    }
    return false;
  }

  static bool _sameTags(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    return a.toSet().containsAll(b);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load({bool discardDraft = false}) async {
    setState(() {
      _loading = _base == null;
      if (_base == null) _loadError = false;
    });
    try {
      final snap = await widget.repository.readJournalDay(day);
      if (!mounted) return;
      final apply = discardDraft || _base == null;
      setState(() {
        _base = snap;
        _fields = [for (final f in snap.fields) f];
        _allDefs = [for (final f in snap.fields) f];
        if (apply) {
          _values = {...snap.metrics};
          _tags = [...snap.tags];
          _note.text = snap.note;
        }
        _loading = false;
        _loadError = false;
        _conflict = false;
        _saveError = null;
      });
      unawaited(_refreshDefs());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = true;
      });
    }
  }

  Future<void> _refreshDefs() async {
    try {
      final all = await widget.repository.listJournalFields(
        includeHidden: true,
      );
      if (!mounted) return;
      setState(() {
        _allDefs = all;
        _fields = [
          for (final f in all)
            if (!f.hidden) f,
        ];
        _fieldsError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _fieldsError = 'Felder nicht geladen.';
      });
    }
  }

  List<JournalFieldSpec> _specsFor(bool Function(JournalFieldSpec) where) {
    final byKey = <String, JournalFieldSpec>{
      for (final f in kJournalFields) f.key: f,
      for (final f in _allDefs) f.key: f,
    };
    final seen = <String>{};
    final out = <JournalFieldSpec>[];
    void add(JournalFieldSpec spec) {
      if (!where(spec) || !seen.add(spec.key)) return;
      out.add(spec);
    }

    for (final f in kJournalFields) {
      add(byKey[f.key] ?? f);
    }
    for (final f in _fields) {
      add(byKey[f.key] ?? f);
    }
    for (final key in _values.keys) {
      final spec = byKey[key];
      if (spec != null && spec.hidden && _values[key] != _base?.metrics[key]) {
        add(spec);
      }
    }
    return out;
  }

  bool _isHiddenDraft(JournalFieldSpec spec) {
    if (!spec.hidden) return false;
    final base = _base?.metrics[spec.key];
    return _values[spec.key] != base;
  }

  String _formatValue(JournalFieldSpec spec, JournalMetricValue? metric) {
    if (metric == null) return '—';
    if (spec.isRating) {
      return '${spec.format(metric.value)} / ${spec.max.round()}';
    }
    if (spec.kind == JournalFieldKind.duration) {
      return '${spec.format(metric.value)} Min.';
    }
    var text = spec.unit.isEmpty
        ? spec.format(metric.value)
        : '${spec.format(metric.value)} ${journalFieldUnitLabel(spec)}';
    if (spec.hasTime && metric.atMinuteOfDay != null) {
      text = '$text · ${journalMinuteLabel(metric.atMinuteOfDay!)}';
    }
    return text;
  }

  void _setMetric(String key, JournalMetricValue? value) {
    if (_busy) return;
    setState(() {
      if (value == null) {
        _values.remove(key);
      } else {
        _values[key] = value;
      }
      _conflict = false;
      _saveError = null;
    });
  }

  Future<void> _leave() async {
    if (_busy) return;
    if (!_dirty) {
      Navigator.pop(context);
      return;
    }
    final discard = await showOpenBandConfirmSheet(
      context: context,
      title: 'Änderungen verwerfen?',
    );
    if (discard == true && mounted) Navigator.pop(context);
  }

  Future<void> _save() async {
    final base = _base;
    if (base == null || _busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _saving = true;
      _saveError = null;
      _conflict = false;
    });
    var popped = false;
    try {
      final metrics = <String, JournalMetricValue?>{};
      for (final k in {...base.metrics.keys, ..._values.keys}) {
        if (base.metrics[k] != _values[k]) {
          metrics[k] = _values[k];
        }
      }
      List<String>? tags;
      if (!_sameTags(_tags, base.tags)) tags = [..._tags];
      final notePatch = _note.text == base.note ? null : _note.text;
      if (metrics.isNotEmpty || tags != null || notePatch != null) {
        await widget.repository.patchJournalDay(
          JournalDayPatch.fromBase(
            base,
            metrics: metrics,
            tags: tags,
            note: notePatch,
          ),
        );
      }
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pop(context, true);
        popped = true;
      }
    } on JournalConflict {
      if (!mounted) return;
      setState(() => _conflict = true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saveError = 'Speichern fehlgeschlagen');
    } finally {
      if (!popped && mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reloadConflict() async {
    if (_busy) return;
    if (_dirty) {
      final discard = await showOpenBandConfirmSheet(
        context: context,
        title: 'Änderungen verwerfen?',
        confirmLabel: 'Verwerfen und neu laden',
      );
      if (discard != true || !mounted) return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _reloading = true);
    try {
      await _load(discardDraft: true);
    } finally {
      if (mounted) setState(() => _reloading = false);
    }
  }

  Future<void> _openFields() async {
    if (_busy) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            OpenBandJournalFields(repository: widget.repository, day: day),
      ),
    );
    if (!mounted) return;
    await _refreshDefs();
  }

  Future<void> _openRating(JournalFieldSpec spec) async {
    if (_busy) return;
    final current = _values[spec.key];
    final result = await showModalBottomSheet<_SheetResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _RatingSheet(spec: spec, metric: current),
    );
    if (!mounted || result == null) return;
    _setMetric(spec.key, result.value);
  }

  Future<void> _openValue(JournalFieldSpec spec) async {
    if (_busy) return;
    final current = _values[spec.key];
    final result = await showOpenBandJournalValueSheet(
      context: context,
      spec: spec,
      metric: current,
    );
    if (!mounted || result == null) return;
    _setMetric(spec.key, result.value);
  }

  Future<void> _openTags() async {
    if (_busy) return;
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _TagsSheet(selected: _tags),
    );
    if (!mounted || result == null) return;
    setState(() {
      _tags = result;
      _conflict = false;
      _saveError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return PopScope(
      canPop: !_dirty && !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: p.canvas,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: OBPageHeader(
                  title: 'Tagesjournal',
                  subtitle: obDate(day),
                  onBack: _busy
                      ? null
                      : () {
                          _leave();
                        },
                  onInfo: _busy
                      ? null
                      : () => showOpenBandJournalInfo(
                          context,
                          title: 'Tagesjournal',
                          body:
                              'Felder gelten für diesen Kalendertag. Eine Menge behält die letzte Uhrzeit, bis du sie änderst.',
                        ),
                ),
              ),
              Expanded(
                child: _loading && _base == null
                    ? const Center(child: CircularProgressIndicator.adaptive())
                    : _loadError && _base == null
                    ? ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        children: [
                          OBCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              spacing: 8,
                              children: [
                                Text(
                                  'Journal nicht geladen',
                                  style: p.text(14, color: p.danger),
                                ),
                                OBAction(
                                  'Erneut',
                                  ink: true,
                                  secondary: true,
                                  onPressed: _load,
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : IgnorePointer(
                        ignoring: _busy,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _MoodCard(
                                value: _values['mood']?.value.round(),
                                onChanged: (v) => _setMetric(
                                  'mood',
                                  v == null
                                      ? null
                                      : JournalMetricValue(
                                          v.toDouble(),
                                          atMinuteOfDay:
                                              _values['mood']?.atMinuteOfDay,
                                        ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              _groupCard(
                                context,
                                _specsFor(
                                  (s) =>
                                      s.key != 'mood' &&
                                      s.kind == JournalFieldKind.rating,
                                ),
                                (spec) => _MetricRow(
                                  spec: spec,
                                  value: _formatValue(spec, _values[spec.key]),
                                  hiddenDraft: _isHiddenDraft(spec),
                                  onTap: () => _openRating(spec),
                                ),
                              ),
                              const SizedBox(height: 12),
                              _groupCard(
                                context,
                                _specsFor(
                                  (s) => s.kind == JournalFieldKind.yesNo,
                                ),
                                (spec) => OBJournalYesNo(
                                  label: journalFieldTitle(spec),
                                  icon: journalFieldIcon(spec),
                                  value: switch (_values[spec.key]?.value) {
                                    null => null,
                                    final v => v >= 0.5,
                                  },
                                  hiddenDraft: _isHiddenDraft(spec),
                                  enabled: !_busy,
                                  onChanged: (yes) => _setMetric(
                                    spec.key,
                                    yes == null
                                        ? null
                                        : JournalMetricValue(
                                            yes ? 1 : 0,
                                            atMinuteOfDay: _values[spec.key]
                                                ?.atMinuteOfDay,
                                          ),
                                  ),
                                ),
                                insetDividers: true,
                              ),
                              const SizedBox(height: 12),
                              _groupCard(
                                context,
                                _specsFor(
                                  (s) =>
                                      s.kind == JournalFieldKind.dose ||
                                      s.kind == JournalFieldKind.duration,
                                ),
                                (spec) => _MetricRow(
                                  spec: spec,
                                  value: _formatValue(spec, _values[spec.key]),
                                  hiddenDraft: _isHiddenDraft(spec),
                                  onTap: () => _openValue(spec),
                                ),
                              ),
                              const SizedBox(height: 12),
                              _NoteCard(
                                controller: _note,
                                enabled: !_busy,
                                onChanged: (_) => setState(() {}),
                              ),
                              const SizedBox(height: 12),
                              _TagsRow(tags: _tags, onTap: _openTags),
                              const SizedBox(height: 12),
                              _NavCard(
                                label: 'Eigene Felder',
                                onTap: _openFields,
                              ),
                              if (_fieldsError != null) ...[
                                const SizedBox(height: 12),
                                OBCard(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    spacing: 8,
                                    children: [
                                      Text(
                                        _fieldsError!,
                                        style: p.text(14, color: p.danger),
                                      ),
                                      OBAction(
                                        'Erneut',
                                        ink: true,
                                        onPressed: _refreshDefs,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
              ),
              if (_base != null)
                ColoredBox(
                  color: p.canvas,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 8,
                      children: [
                        if (_loadError)
                          Text(
                            'Laden fehlgeschlagen',
                            style: p.text(14, color: p.danger),
                          ),
                        if (_saveError != null)
                          Text(_saveError!, style: p.text(14, color: p.danger)),
                        if (_conflict) ...[
                          Text(
                            'Eintrag wurde inzwischen geändert.',
                            style: p.text(14, color: p.danger),
                          ),
                          OBAction(
                            'Neu laden',
                            ink: true,
                            onPressed: _busy ? null : _reloadConflict,
                          ),
                        ] else
                          OBAction(
                            key: const ValueKey('journal-save'),
                            'Speichern',
                            ink: true,
                            onPressed: _busy ? null : _save,
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _groupCard(
    BuildContext context,
    List<JournalFieldSpec> specs,
    Widget Function(JournalFieldSpec) row, {
    bool insetDividers = false,
  }) {
    if (specs.isEmpty) return const SizedBox.shrink();
    final p = OB.of(context);
    return OBCard(
      padding: insetDividers
          ? const EdgeInsets.fromLTRB(14, 4, 14, 4)
          : const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, spec) in specs.indexed)
            DecoratedBox(
              decoration: BoxDecoration(
                border: insetDividers && i > 0
                    ? Border(top: BorderSide(color: p.line))
                    : null,
              ),
              child: row(spec),
            ),
        ],
      ),
    );
  }
}

class _MoodCard extends StatelessWidget {
  final int? value;
  final ValueChanged<int?> onChanged;
  const _MoodCard({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Text('Stimmung', style: p.text(15, weight: FontWeight.w600)),
          OBJournalMoodScale(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final JournalFieldSpec spec;
  final String value;
  final bool hiddenDraft;
  final VoidCallback onTap;
  const _MetricRow({
    required this.spec,
    required this.value,
    required this.hiddenDraft,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final missing = value == '—';
    final stacked =
        MediaQuery.textScalerOf(context).scale(15) > 20 ||
        MediaQuery.sizeOf(context).width < 360;
    final label = Text(
      journalFieldTitle(spec),
      style: p.text(15, weight: FontWeight.w500).copyWith(height: 20 / 15),
    );
    final trailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            value,
            textAlign: stacked || hiddenDraft ? TextAlign.start : TextAlign.end,
            style: p
                .text(15, weight: FontWeight.w600)
                .copyWith(height: 20 / 15, color: missing ? p.muted : p.ink),
          ),
        ),
        const SizedBox(width: 4),
        Icon(LucideIcons.chevronRight, size: 18, color: p.muted),
      ],
    );
    return InkWell(
      onTap: onTap,
      child: stacked || hiddenDraft
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  label,
                  if (hiddenDraft)
                    Text('Ausgeblendet', style: p.text(12, color: p.muted)),
                  const SizedBox(height: 8),
                  trailing,
                ],
              ),
            )
          : SizedBox(
              height: 56,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: label),
                  trailing,
                ],
              ),
            ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool enabled;
  const _NoteCard({
    required this.controller,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Text(
            'Notiz',
            style: p
                .text(15, weight: FontWeight.w600)
                .copyWith(height: 20 / 15),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: p.well,
              borderRadius: BorderRadius.circular(AlpRadius.well),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 96),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  key: const ValueKey('journal-note'),
                  controller: controller,
                  enabled: enabled,
                  readOnly: !enabled,
                  minLines: 3,
                  maxLines: 8,
                  onChanged: onChanged,
                  style: p.text(15).copyWith(height: 22 / 15),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    hintText: '—',
                    hintStyle: p
                        .text(15, color: p.muted)
                        .copyWith(height: 22 / 15),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TagsRow extends StatelessWidget {
  final List<String> tags;
  final VoidCallback onTap;
  const _TagsRow({required this.tags, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final trailingText = tags.isEmpty
        ? '—'
        : tags.map(journalTagLabel).join(', ');
    final stacked =
        MediaQuery.textScalerOf(context).scale(15) > 20 ||
        MediaQuery.sizeOf(context).width < 360;
    final label = Text(
      'Tags',
      style: p.text(15, weight: FontWeight.w500).copyWith(height: 20 / 15),
    );
    final value = Text(
      trailingText,
      textAlign: stacked ? TextAlign.start : TextAlign.end,
      style: p
          .text(15, weight: FontWeight.w600)
          .copyWith(height: 20 / 15, color: tags.isEmpty ? p.muted : p.ink),
    );
    final chevron = Icon(LucideIcons.chevronRight, size: 18, color: p.muted);
    return Material(
      key: const ValueKey('journal-tags-row'),
      color: p.card,
      borderRadius: BorderRadius.circular(AlpRadius.card),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: stacked
            ? Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 8,
                  children: [
                    label,
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: value),
                        const SizedBox(width: 4),
                        chevron,
                      ],
                    ),
                  ],
                ),
              )
            : ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 18,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: label),
                      Flexible(child: value),
                      const SizedBox(width: 4),
                      chevron,
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _NavCard extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _NavCard({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(AlpRadius.card),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: p.text(15, weight: FontWeight.w500),
                  ),
                ),
                Icon(LucideIcons.chevronRight, size: 18, color: p.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetResult {
  final JournalMetricValue? value;
  const _SheetResult(this.value);
}

class _RatingSheet extends StatefulWidget {
  final JournalFieldSpec spec;
  final JournalMetricValue? metric;
  const _RatingSheet({required this.spec, required this.metric});

  @override
  State<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<_RatingSheet> {
  late int? _value = widget.metric?.value.round();

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final max = widget.spec.max.round().clamp(1, 10);
    return Material(
      color: p.card,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AlpRadius.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          12 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      journalFieldTitle(widget.spec),
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
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(LucideIcons.x, size: 20, color: p.ink),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (var i = 1; i <= max; i++) ...[
                  if (i > 1) const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _value = i),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _value == i ? p.ink : p.well,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '$i',
                          style: p.text(
                            18,
                            weight: FontWeight.w700,
                            display: true,
                            color: _value == i ? p.card : p.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Gering', style: p.text(13, color: p.muted)),
                const Spacer(),
                Text('Hoch', style: p.text(13, color: p.muted)),
              ],
            ),
            const SizedBox(height: 16),
            OBAction(
              'Übernehmen',
              ink: true,
              onPressed: _value == null
                  ? null
                  : () => Navigator.pop(
                      context,
                      _SheetResult(
                        JournalMetricValue(
                          _value!.toDouble(),
                          atMinuteOfDay: widget.metric?.atMinuteOfDay,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context, const _SheetResult(null)),
              child: Text('Wert entfernen', style: p.text(15, color: p.danger)),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagsSheet extends StatefulWidget {
  final List<String> selected;
  const _TagsSheet({required this.selected});

  @override
  State<_TagsSheet> createState() => _TagsSheetState();
}

class _TagsSheetState extends State<_TagsSheet> {
  late final List<String> _selected = [...widget.selected];
  final _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _toggle(String tag) {
    setState(() {
      if (_selected.contains(tag)) {
        _selected.remove(tag);
      } else {
        _selected.add(tag);
      }
    });
  }

  void _addCustom() {
    final text = _custom.text.trim();
    if (text.isEmpty) return;
    if (!_selected.contains(text)) {
      setState(() => _selected.add(text));
    }
    _custom.clear();
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final extras = [
      for (final t in _selected)
        if (!kJournalPresetTags.contains(t)) t,
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Material(
        key: const ValueKey('journal-tags-sheet'),
        color: p.card,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AlpRadius.card),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: (media.size.height - keyboard) * 0.85,
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              math.max(12.0, media.padding.bottom),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Tags',
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
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(LucideIcons.x, size: 20, color: p.ink),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final tag in [
                              ...kJournalPresetTags,
                              ...extras,
                            ])
                              OBJournalChip(
                                label: journalTagLabel(tag),
                                selected: _selected.contains(tag),
                                onTap: () => _toggle(tag),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: p.well,
                                  borderRadius: BorderRadius.circular(
                                    AlpRadius.well,
                                  ),
                                ),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minHeight: 48,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                    child: TextField(
                                      key: const ValueKey('journal-tag-custom'),
                                      controller: _custom,
                                      onSubmitted: (_) => _addCustom(),
                                      decoration: InputDecoration(
                                        border: InputBorder.none,
                                        hintText: 'Neuer Tag',
                                        hintStyle: p.text(15, color: p.muted),
                                      ),
                                      style: p.text(15),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 44,
                              height: 44,
                              child: IconButton(
                                tooltip: 'Tag hinzufügen',
                                onPressed: _addCustom,
                                icon: Icon(
                                  LucideIcons.plus,
                                  size: 20,
                                  color: p.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                OBAction(
                  'Übernehmen',
                  ink: true,
                  onPressed: () => Navigator.pop(context, [..._selected]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
