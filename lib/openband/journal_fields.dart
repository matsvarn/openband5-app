import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/journal_fields.dart';
import 'alp_tokens.dart';
import 'domain.dart';
import 'journal_controls.dart';
import 'settings_controls.dart';
import 'synthetic_repository.dart';
import 'theme.dart';

String journalFieldTitle(JournalFieldSpec spec) => switch (spec.key) {
  'mood' => 'Stimmung',
  'sleep_quality' => 'Schlafqualität',
  'energy' => 'Energie',
  'stress' => 'Stress',
  'soreness' => 'Muskelkater',
  'water_ml' => 'Wasser',
  'caffeine_mg' => 'Koffein',
  'alcohol_units' => 'Alkohol',
  'caffeine_late' => 'Koffein nach 14 Uhr',
  'alcohol_evening' => 'Alkohol am Abend',
  'read_before_bed' => 'Vorm Schlafen gelesen',
  'screens_min' => 'Bildschirm vorm Schlafen',
  'weight_kg' => 'Gewicht',
  _ => spec.label,
};

String journalFieldKindLabel(JournalFieldKind kind) => switch (kind) {
  JournalFieldKind.rating => 'Bewertung',
  JournalFieldKind.dose => 'Menge',
  JournalFieldKind.duration => 'Dauer',
  JournalFieldKind.yesNo => 'Ja / Nein',
};

String journalFieldUnitLabel(JournalFieldSpec spec) {
  if (spec.kind == JournalFieldKind.duration &&
      (spec.unit == 'min' || spec.unit == 'Min.')) {
    return 'Min.';
  }
  return spec.unit;
}

String journalFieldKindMeta(JournalFieldSpec spec) {
  final kind = journalFieldKindLabel(spec.kind);
  final unit = journalFieldUnitLabel(spec);
  if (unit.isEmpty) return kind;
  return '$kind · $unit';
}

String journalMetricEditableText(double value) {
  if (value == value.roundToDouble()) return value.round().toString();
  return value.toString();
}

/// Finite values in `[0, spec.max]`. Matches the prepared field ceiling;
/// does not clamp. Null means the value can be applied.
String? journalMetricRangeError(JournalFieldSpec spec, double value) {
  if (!value.isFinite) return 'Wert ist keine Zahl.';
  if (value < 0 || value > spec.max) {
    final unit = journalFieldUnitLabel(spec);
    final range = '0–${spec.format(spec.max)}';
    final title = journalFieldTitle(spec);
    return unit.isEmpty ? '$title: $range' : '$title: $range $unit';
  }
  return null;
}

String journalMinuteLabel(int minuteOfDay) {
  final m = minuteOfDay.clamp(0, 24 * 60 - 1);
  final h = (m ~/ 60).toString().padLeft(2, '0');
  final min = (m % 60).toString().padLeft(2, '0');
  return '$h:$min';
}

IconData journalFieldIcon(JournalFieldSpec spec) => switch (spec.key) {
  'caffeine_late' || 'caffeine_mg' => LucideIcons.coffee,
  'alcohol_evening' || 'alcohol_units' => LucideIcons.wine,
  'read_before_bed' => LucideIcons.bookOpen,
  'water_ml' => LucideIcons.droplet,
  'screens_min' => LucideIcons.smartphone,
  'weight_kg' => LucideIcons.scale,
  _ => switch (spec.kind) {
    JournalFieldKind.yesNo => LucideIcons.circleDot,
    JournalFieldKind.duration => LucideIcons.timer,
    JournalFieldKind.dose => LucideIcons.flaskConical,
    JournalFieldKind.rating => LucideIcons.gauge,
  },
};

class OpenBandJournalFields extends StatefulWidget {
  final OpenBandRepository repository;
  final String day;
  const OpenBandJournalFields({
    super.key,
    required this.repository,
    required this.day,
  });

  @override
  State<OpenBandJournalFields> createState() => _OpenBandJournalFieldsState();
}

class _OpenBandJournalFieldsState extends State<OpenBandJournalFields> {
  List<JournalFieldSpec> _all = const [];
  bool _loading = true;
  bool _loadError = false;
  bool _savedRefreshError = false;
  String? _actionError;
  bool _busy = false;

  List<JournalFieldSpec> get _customActive => [
    for (final f in _all)
      if (f.custom && !f.hidden) f,
  ];
  List<JournalFieldSpec> get _hidden => [
    for (final f in _all)
      if (f.custom && f.hidden) f,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool afterSave = false}) async {
    setState(() {
      if (!afterSave) {
        _loading = true;
        _loadError = false;
      }
      _actionError = null;
    });
    try {
      final all = await widget.repository.listJournalFields(
        includeHidden: true,
      );
      if (!mounted) return;
      setState(() {
        _all = all;
        _loading = false;
        _loadError = false;
        _savedRefreshError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (afterSave) {
          _savedRefreshError = true;
        } else if (_all.isEmpty) {
          _loadError = true;
        } else {
          _actionError = 'Liste nicht geladen.';
        }
      });
    }
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<JournalFieldSpec>(
      MaterialPageRoute(
        builder: (_) => OpenBandJournalFieldCreate(
          repository: widget.repository,
          day: widget.day,
        ),
      ),
    );
    if (!mounted) return;
    if (created != null) {
      setState(() {
        _all = [
          for (final f in _all)
            if (f.key != created.key) f,
          created,
        ];
      });
    }
    await _load(afterSave: created != null);
  }

  Future<void> _openHidden() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => OpenBandJournalHiddenFields(
          repository: widget.repository,
          day: widget.day,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _showDetail(JournalFieldSpec spec) async {
    final hidden = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _FieldDetailSheet(spec: spec, hidden: spec.hidden),
    );
    if (hidden != true || !mounted || _busy) return;
    setState(() => _busy = true);
    try {
      if (spec.hidden) {
        await widget.repository.restoreJournalField(spec.key);
      } else {
        await widget.repository.hideJournalField(spec.key);
      }
      if (!mounted) return;
      await _load();
    } catch (_) {
      if (mounted) {
        setState(
          () => _actionError = spec.hidden
              ? 'Feld nicht eingeblendet.'
              : 'Feld nicht ausgeblendet.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final custom = _customActive;
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OBPageHeader(
                title: 'Eigene Felder',
                subtitle: '',
                onInfo: () => showOpenBandJournalInfo(
                  context,
                  title: 'Eigene Felder',
                  body:
                      'Ausgeblendete Felder bleiben im Verlauf. Du kannst sie wieder einblenden.',
                ),
              ),
            ),
            Expanded(
              child: ListView(
                cacheExtent: 4000,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  if (_loadError)
                    OBCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 8,
                        children: [
                          Text(
                            'Felder nicht geladen',
                            style: p.text(14, color: p.danger),
                          ),
                          OBAction('Erneut', ink: true, onPressed: _load),
                        ],
                      ),
                    )
                  else if (_loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Center(
                        child: CircularProgressIndicator.adaptive(),
                      ),
                    )
                  else ...[
                    if (custom.isNotEmpty)
                      OBCard(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                        child: Column(
                          children: [
                            for (final (i, f) in custom.indexed)
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  border: i > 0
                                      ? Border(top: BorderSide(color: p.line))
                                      : null,
                                ),
                                child: _FieldRow(
                                  spec: f,
                                  onTap: _busy ? null : () => _showDetail(f),
                                ),
                              ),
                          ],
                        ),
                      )
                    else
                      OBCard(
                        child: Text(
                          'Keine eigenen Felder.',
                          style: p.text(15, color: p.muted),
                        ),
                      ),
                    const SizedBox(height: 12),
                    OBAction(
                      'Feld hinzufügen',
                      ink: true,
                      onPressed: _busy ? null : _openCreate,
                    ),
                    const SizedBox(height: 12),
                    _NavRow(
                      label: 'Ausgeblendet',
                      value: '${_hidden.length}',
                      onTap: _busy ? null : _openHidden,
                    ),
                    if (_savedRefreshError) ...[
                      const SizedBox(height: 12),
                      OBCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 8,
                          children: [
                            Text(
                              'Feld gespeichert. Liste nicht geladen.',
                              style: p.text(14, color: p.danger),
                            ),
                            OBAction(
                              'Erneut',
                              ink: true,
                              onPressed: () => _load(afterSave: true),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_actionError != null) ...[
                      const SizedBox(height: 12),
                      Text(_actionError!, style: p.text(14, color: p.danger)),
                    ],
                    const SizedBox(height: 12),
                    _synthNote(context, widget.repository),
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

class OpenBandJournalHiddenFields extends StatefulWidget {
  final OpenBandRepository repository;
  final String day;
  const OpenBandJournalHiddenFields({
    super.key,
    required this.repository,
    required this.day,
  });

  @override
  State<OpenBandJournalHiddenFields> createState() =>
      _OpenBandJournalHiddenFieldsState();
}

class _OpenBandJournalHiddenFieldsState
    extends State<OpenBandJournalHiddenFields> {
  List<JournalFieldSpec> _hidden = const [];
  bool _loading = true;
  bool _error = false;
  bool _busy = false;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
      _actionError = null;
    });
    try {
      final all = await widget.repository.listJournalFields(
        includeHidden: true,
      );
      if (!mounted) return;
      setState(() {
        _hidden = [
          for (final f in all)
            if (f.custom && f.hidden) f,
        ];
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

  Future<void> _restore(JournalFieldSpec spec) async {
    final restore = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _FieldDetailSheet(spec: spec, hidden: true),
    );
    if (restore != true || !mounted || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.repository.restoreJournalField(spec.key);
      if (!mounted) return;
      await _load();
    } catch (_) {
      if (mounted) {
        setState(() => _actionError = 'Feld nicht eingeblendet.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OBPageHeader(
                title: 'Ausgeblendet',
                subtitle: '',
                onInfo: () => showOpenBandJournalInfo(
                  context,
                  title: 'Ausgeblendet',
                  body:
                      'Ausgeblendete Felder bleiben im Verlauf. Du kannst sie wieder einblenden.',
                ),
              ),
            ),
            Expanded(
              child: ListView(
                cacheExtent: 4000,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  if (_error)
                    OBCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 8,
                        children: [
                          Text(
                            'Ausgeblendete Felder nicht geladen',
                            style: p.text(14, color: p.danger),
                          ),
                          OBAction('Erneut', ink: true, onPressed: _load),
                        ],
                      ),
                    )
                  else if (_loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Center(
                        child: CircularProgressIndicator.adaptive(),
                      ),
                    )
                  else if (_hidden.isEmpty)
                    OBCard(
                      child: Text(
                        'Keine ausgeblendeten Felder.',
                        style: p.text(15, color: p.muted),
                      ),
                    )
                  else
                    OBCard(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                      child: Column(
                        children: [
                          for (final (i, f) in _hidden.indexed)
                            DecoratedBox(
                              decoration: BoxDecoration(
                                border: i > 0
                                    ? Border(top: BorderSide(color: p.line))
                                    : null,
                              ),
                              child: _FieldRow(
                                spec: f,
                                onTap: _busy ? null : () => _restore(f),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (_actionError != null) ...[
                    const SizedBox(height: 12),
                    Text(_actionError!, style: p.text(14, color: p.danger)),
                  ],
                  const SizedBox(height: 12),
                  _synthNote(context, widget.repository),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OpenBandJournalFieldCreate extends StatefulWidget {
  final OpenBandRepository repository;
  final String day;
  const OpenBandJournalFieldCreate({
    super.key,
    required this.repository,
    required this.day,
  });

  @override
  State<OpenBandJournalFieldCreate> createState() =>
      _OpenBandJournalFieldCreateState();
}

class _OpenBandJournalFieldCreateState
    extends State<OpenBandJournalFieldCreate> {
  final _name = TextEditingController();
  final _unit = TextEditingController(text: 'mg');
  final _step = TextEditingController(text: '50');
  final _max = TextEditingController(text: '1000');
  JournalFieldKind _kind = JournalFieldKind.dose;
  bool _hasTime = true;
  bool _busy = false;
  bool _committed = false;
  JournalFieldSpec? _created;
  String? _error;
  bool _listError = false;

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _step.dispose();
    _max.dispose();
    super.dispose();
  }

  void _applyKind(JournalFieldKind kind) {
    setState(() {
      _kind = kind;
      switch (kind) {
        case JournalFieldKind.rating:
          _unit.text = '';
          _step.text = '1';
          _max.text = '5';
          _hasTime = false;
        case JournalFieldKind.dose:
          if (_unit.text.trim().isEmpty) _unit.text = 'mg';
          _step.text = '50';
          _max.text = '1000';
        case JournalFieldKind.duration:
          _unit.text = 'min';
          _step.text = '5';
          _max.text = '120';
          _hasTime = false;
        case JournalFieldKind.yesNo:
          _unit.text = '';
          _step.text = '1';
          _max.text = '1';
          _hasTime = false;
      }
    });
  }

  Future<void> _pickKind() async {
    final picked = await showModalBottomSheet<JournalFieldKind>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _KindSheet(selected: _kind),
    );
    if (picked != null && mounted) _applyKind(picked);
  }

  Future<void> _save() async {
    if (_busy || _committed) return;
    final label = _name.text.trim();
    if (label.isEmpty) {
      setState(() => _error = 'Name fehlt.');
      return;
    }
    final step = double.tryParse(_step.text.replaceAll(',', '.'));
    final max = double.tryParse(_max.text.replaceAll(',', '.'));
    if (step == null || max == null) {
      setState(() => _error = 'Schrittweite oder Obergrenze ist keine Zahl.');
      return;
    }
    JournalFieldSpec spec;
    try {
      spec = preparedCustomJournalField(
        JournalFieldSpec(
          key: newCustomJournalFieldKey(),
          label: label,
          kind: _kind,
          unit: _unit.text,
          max: max,
          step: step,
          hasTime: _hasTime,
          custom: true,
        ),
      );
    } on ArgumentError catch (e) {
      setState(() => _error = e.message?.toString() ?? 'Angabe ungültig.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _listError = false;
    });
    try {
      final created = await widget.repository.createJournalField(spec);
      _committed = true;
      _created = created;
      try {
        await widget.repository.listJournalFields(includeHidden: true);
        if (!mounted) return;
        Navigator.pop(context, created);
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _listError = true;
          _busy = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Feld nicht gespeichert.';
      });
    }
  }

  Future<void> _retryList() async {
    if (_busy || _created == null) return;
    setState(() => _busy = true);
    try {
      await widget.repository.listJournalFields(includeHidden: true);
      if (!mounted) return;
      Navigator.pop(context, _created);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _listError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final ratingLike =
        _kind == JournalFieldKind.rating || _kind == JournalFieldKind.yesNo;
    return PopScope(
      canPop: !_committed && !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _busy) return;
        Navigator.pop(context, _created);
      },
      child: Scaffold(
        backgroundColor: p.canvas,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: OBPageHeader(
                  title: 'Feld hinzufügen',
                  subtitle: '',
                  onInfo: () => showOpenBandJournalInfo(
                    context,
                    title: 'Feld hinzufügen',
                    body:
                        'Die Feldart lässt sich nach dem Speichern nicht ändern.',
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  cacheExtent: 4000,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    OBCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 16,
                        children: [
                          _LabeledWell(
                            label: 'Name',
                            child: TextField(
                              key: const ValueKey('journal-field-name'),
                              controller: _name,
                              enabled: !_committed,
                              style: p.text(15).copyWith(height: 20 / 15),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                hintText: 'Magnesium',
                              ),
                            ),
                          ),
                          _LabeledWell(
                            label: 'Art',
                            onTap: _committed ? null : _pickKind,
                            child: Text(
                              journalFieldKindLabel(_kind),
                              style: p.text(15).copyWith(height: 20 / 15),
                            ),
                          ),
                          if (!ratingLike) ...[
                            _LabeledWell(
                              label: 'Einheit',
                              child: TextField(
                                key: const ValueKey('journal-field-unit'),
                                controller: _unit,
                                enabled: !_committed,
                                style: p.text(15).copyWith(height: 20 / 15),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  hintText: 'mg',
                                ),
                              ),
                            ),
                            _LabeledWell(
                              label: 'Schrittweite',
                              child: TextField(
                                key: const ValueKey('journal-field-step'),
                                controller: _step,
                                enabled: !_committed,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.,]'),
                                  ),
                                ],
                                style: p.text(15).copyWith(height: 20 / 15),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                              ),
                            ),
                            _LabeledWell(
                              label: 'Obergrenze',
                              child: TextField(
                                key: const ValueKey('journal-field-max'),
                                controller: _max,
                                enabled: !_committed,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.,]'),
                                  ),
                                ],
                                style: p.text(15).copyWith(height: 20 / 15),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                              ),
                            ),
                            OBSettingsToggleRow(
                              label: 'Uhrzeit erfassen',
                              value: _hasTime,
                              interactive: !_committed,
                              onToggle: _committed
                                  ? null
                                  : () => setState(() => _hasTime = !_hasTime),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: p.text(14, color: p.danger)),
                    ],
                    if (_listError) ...[
                      const SizedBox(height: 12),
                      OBCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 8,
                          children: [
                            Text(
                              'Feld gespeichert. Liste nicht geladen.',
                              style: p.text(14, color: p.danger),
                            ),
                            OBAction(
                              'Erneut',
                              ink: true,
                              onPressed: _busy ? null : _retryList,
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (!_committed)
                      OBAction(
                        'Speichern',
                        ink: true,
                        onPressed: _busy ? null : _save,
                      ),
                    const SizedBox(height: 12),
                    _synthNote(context, widget.repository),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KindSheet extends StatelessWidget {
  final JournalFieldKind selected;
  const _KindSheet({required this.selected});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
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
                      'Art',
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
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final kind in JournalFieldKind.values)
                  OBJournalChip(
                    label: journalFieldKindLabel(kind),
                    selected: kind == selected,
                    onTap: () => Navigator.pop(context, kind),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            OBAction(
              'Übernehmen',
              ink: true,
              onPressed: () => Navigator.pop(context, selected),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldDetailSheet extends StatelessWidget {
  final JournalFieldSpec spec;
  final bool hidden;
  const _FieldDetailSheet({required this.spec, required this.hidden});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    Widget meta(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: p.text(15, weight: FontWeight.w500)),
          ),
          Text(value, style: p.text(15, weight: FontWeight.w600)),
        ],
      ),
    );
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
                      journalFieldTitle(spec),
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
            meta('Art', journalFieldKindLabel(spec.kind)),
            if (journalFieldUnitLabel(spec).isNotEmpty)
              meta('Einheit', journalFieldUnitLabel(spec)),
            if (!spec.isYesNo && !spec.isRating) ...[
              meta(
                'Schrittweite',
                spec.step == spec.step.roundToDouble()
                    ? spec.step.round().toString()
                    : spec.step.toString(),
              ),
              meta(
                'Obergrenze',
                spec.max == spec.max.roundToDouble()
                    ? spec.max.round().toString()
                    : spec.max.toString(),
              ),
            ],
            meta('Uhrzeit', spec.hasTime ? 'Ja' : 'Nein'),
            const SizedBox(height: 8),
            OBAction(
              hidden ? 'Einblenden' : 'Ausblenden',
              ink: true,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  final JournalFieldSpec spec;
  final VoidCallback? onTap;
  const _FieldRow({required this.spec, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return InkWell(
      key: ValueKey('journal-field-${spec.key}'),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 4,
                children: [
                  Text(
                    journalFieldTitle(spec),
                    style: p
                        .text(15, weight: FontWeight.w600)
                        .copyWith(height: 20 / 15),
                  ),
                  Text(
                    journalFieldKindMeta(spec),
                    style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 18, color: p.muted),
          ],
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;
  const _NavRow({required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return InkWell(
      key: const ValueKey('journal-fields-hidden'),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(label, style: p.text(14).copyWith(height: 19 / 14)),
              ),
              Text(
                value,
                style: p.text(14, color: p.muted).copyWith(height: 19 / 14),
              ),
              const SizedBox(width: 12),
              Icon(LucideIcons.chevronRight, size: 18, color: p.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _LabeledWell extends StatelessWidget {
  final String label;
  final Widget child;
  final VoidCallback? onTap;
  const _LabeledWell({required this.label, required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final well = DecoratedBox(
      decoration: BoxDecoration(
        color: p.well,
        borderRadius: BorderRadius.circular(AlpRadius.well),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Align(alignment: Alignment.centerLeft, child: child),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Text(
          label,
          style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
        ),
        if (onTap == null)
          well
        else
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AlpRadius.well),
              child: well,
            ),
          ),
      ],
    );
  }
}

Widget _synthNote(BuildContext context, OpenBandRepository repository) {
  if (repository is! SyntheticOpenBandRepository) {
    return const SizedBox.shrink();
  }
  final p = OB.of(context);
  return Text(
    'Synthetische Daten',
    style: p.text(12, color: p.muted).copyWith(height: 17 / 12),
  );
}
