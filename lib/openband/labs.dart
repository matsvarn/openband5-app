import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/day_label.dart';
import '../data/lab_catalogue.dart';
import 'alp_tokens.dart';
import 'domain.dart';
import 'measurement_row.dart';
import 'synthetic_repository.dart';
import 'theme.dart';

const _labels = {
  'hemoglobin': 'Hämoglobin',
  'hematocrit': 'Hämatokrit',
  'ferritin': 'Ferritin',
  'transferrin_saturation': 'Transferrinsättigung',
  'hba1c': 'HbA1c',
  'glucose_fasting': 'Nüchternglukose',
  'insulin_fasting': 'Nüchterninsulin',
  'cholesterol_total': 'Gesamtcholesterin',
  'ldl': 'LDL',
  'hdl': 'HDL',
  'triglycerides': 'Triglyceride',
  'apob': 'ApoB',
  'tsh': 'TSH',
  'free_t4': 'Freies T4',
  'testosterone_total': 'Testosteron',
  'cortisol_am': 'Morgen-Cortisol',
  'vitamin_d': 'Vitamin D (25-OH)',
  'vitamin_b12': 'Vitamin B12',
  'folate': 'Folsäure',
  'magnesium': 'Magnesium',
  'crp_hs': 'hs-CRP',
  'alt': 'ALT',
  'ast': 'AST',
  'creatinine': 'Kreatinin',
  'egfr': 'eGFR',
};

const _categoryOrder = [
  'blood',
  'iron',
  'metabolic',
  'lipids',
  'hormones',
  'vitamins',
  'inflammation',
  'organ',
  'other',
];

const _categoryLabel = {
  'blood': 'Blutbild',
  'iron': 'Eisen',
  'metabolic': 'Stoffwechsel',
  'lipids': 'Lipide',
  'hormones': 'Hormone',
  'vitamins': 'Vitamine',
  'inflammation': 'Entzündung',
  'organ': 'Leber & Niere',
  'other': 'Sonstige',
};

String labDisplayLabel(LabMarker? m, String key) =>
    m != null && m.custom ? m.label : (_labels[key] ?? m?.label ?? key);

String labDayLabel(String day) {
  if (!isLabCalendarDay(day)) return day;
  return DateFormat('d. MMMM y', 'de_DE').format(DateTime.parse(day));
}

String labDayMonth(String day) {
  if (!isLabCalendarDay(day)) return day;
  return DateFormat('d. MMMM', 'de_DE').format(DateTime.parse(day));
}

String labDayYear(String day) {
  if (!isLabCalendarDay(day)) return day;
  return DateFormat('y', 'de_DE').format(DateTime.parse(day));
}

int _digits(LabMarker? m, double v) =>
    m?.decimals ?? (v == v.roundToDouble() ? 0 : 1);

String labFormatValue(LabDraw d, LabMarker? m) =>
    d.readable ? obNumber(d.value, digits: _digits(m, d.value)) : '—';

String? labUnreadableSemantics(LabDraw d, String label, String date) =>
    d.readable ? null : '$label, $date, unlesbar ${d.unit}';

String labReportText(LabDraw d, LabMarker? m) {
  String n(double v) => obNumber(v, digits: _digits(m, v));
  final lo = d.reportLow, hi = d.reportHigh;
  if (lo == null && hi == null) return '—';
  if (lo != null && hi != null) return '${n(lo)}–${n(hi)} ${d.unit}';
  if (lo != null) return 'ab ${n(lo)} ${d.unit}';
  return 'bis ${n(hi!)} ${d.unit}';
}

LabMarker? labResolve(LabSnapshot snap, String key) => labMarker(
  key,
  custom: [
    for (final c in snap.custom)
      LabMarker(
        key: c.key,
        label: c.label,
        unit: c.unit,
        category:
            LabCategory.values.asNameMap()[c.category] ?? LabCategory.blood,
        decimals: c.decimals,
        ranges: [
          if (c.refLow != null && c.refHigh != null)
            LabRefRange(low: c.refLow!, high: c.refHigh!),
        ],
        custom: true,
      ),
  ],
);

String? labCatalogueHint(LabMarker? m, LabDraw d, String? sex) {
  if (m == null || m.unit != d.unit) return null;
  final range = m.rangeFor(sex);
  if (range == null) return null;
  return 'Katalog ${obNumber(range.low, digits: m.decimals)}–'
      '${obNumber(range.high, digits: m.decimals)} ${m.unit}';
}

/// Stable create identity. Empty/non-latin slugs never share `custom_`.
String allocateCustomLabMarkerKey(String label, Iterable<String> taken) {
  final used = {...taken, ...kLabMarkersByKey.keys};
  final key = customLabMarkerKey(label);
  if (key != 'custom_' && !used.contains(key)) return key;
  if (key != 'custom_') return key;
  var n = 1;
  while (used.contains('custom_$n')) {
    n++;
  }
  return 'custom_$n';
}

class OpenBandLabs extends StatefulWidget {
  final OpenBandRepository repository;
  final DateTime Function() now;
  const OpenBandLabs({
    super.key,
    required this.repository,
    this.now = DateTime.now,
  });

  static Future<void> push(
    BuildContext context, {
    required OpenBandRepository repository,
    DateTime Function() now = DateTime.now,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => OpenBandLabs(repository: repository, now: now),
    ),
  );

  @override
  State<OpenBandLabs> createState() => _OpenBandLabsState();
}

class _OpenBandLabsState extends State<OpenBandLabs> {
  LabSnapshot? _snap;
  bool _loading = true, _error = false;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final g = ++_gen;
    setState(() {
      _loading = _snap == null;
      _error = false;
    });
    try {
      final snap = await widget.repository.readLabs();
      if (!mounted || g != _gen) return;
      setState(() {
        _snap = snap;
        _loading = false;
        _error = false;
      });
    } catch (_) {
      if (!mounted || g != _gen) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _openDetail(String marker) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => OpenBandLabDetail(
          repository: widget.repository,
          now: widget.now,
          marker: marker,
        ),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _add() async {
    final chosen = await _chooseMarker(context, widget.repository, _snap);
    if (chosen == null || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => OpenBandLabEditor(
          repository: widget.repository,
          now: widget.now,
          marker: chosen,
        ),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final snap = _snap;
    final latest = <String, LabDraw>{};
    if (snap != null) {
      for (final r in snap.results) {
        latest.putIfAbsent(r.marker, () => r);
      }
    }
    final rows = latest.values.toList()
      ..sort((a, b) {
        final la = labDisplayLabel(labResolve(snap!, a.marker), a.marker);
        final lb = labDisplayLabel(labResolve(snap, b.marker), b.marker);
        return la.compareTo(lb);
      });
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            OBPageHeader(
              title: 'Laborwerte',
              subtitle: '',
              onInfo: () => _labInfo(
                context,
                'Quelle und Bereich',
                'Werte stammen aus dem Laborbericht, nicht vom Band. '
                    'Der Befundbereich ist der auf dem Bericht. '
                    'Ein Katalogbereich gilt nur bei passender Einheit und bekanntem Geschlecht.',
              ),
              infoLabel: 'Quelle und Bereich',
            ),
            if (_error)
              OBCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Laborwerte nicht geladen.', style: p.text(14)),
                    const SizedBox(height: 8),
                    OBAction('Erneut laden', ink: true, onPressed: _load),
                  ],
                ),
              )
            else if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator.adaptive()),
              )
            else if (rows.isEmpty) ...[
              OBCard(
                key: const ValueKey('lab-empty'),
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 92),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Keine Laborwerte',
                        style: p
                            .text(20, weight: FontWeight.w600)
                            .copyWith(height: 26 / 20),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OBAction('Wert hinzufügen', ink: true, onPressed: _add),
            ] else ...[
              OBCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final r in rows)
                      OBMeasurementRow(
                        key: ValueKey('lab-${r.marker}'),
                        label: labDisplayLabel(
                          labResolve(snap!, r.marker),
                          r.marker,
                        ),
                        date: labDayLabel(r.takenOn),
                        value: labFormatValue(r, labResolve(snap, r.marker)),
                        unit: r.unit,
                        semanticLabel: labUnreadableSemantics(
                          r,
                          labDisplayLabel(
                            labResolve(snap, r.marker),
                            r.marker,
                          ),
                          labDayLabel(r.takenOn),
                        ),
                        onTap: () => _openDetail(r.marker),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OBAction('Wert hinzufügen', ink: true, onPressed: _add),
            ],
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => OpenBandLabMarkers(
                      repository: widget.repository,
                    ),
                  ),
                );
                if (mounted) _load();
              },
              borderRadius: BorderRadius.circular(AlpRadius.card),
              child: OBCard(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 36),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Eigene Marker',
                          style: p
                              .text(17, weight: FontWeight.w600)
                              .copyWith(height: 22 / 17),
                        ),
                      ),
                      Icon(LucideIcons.chevronRight, size: 16, color: p.gap),
                    ],
                  ),
                ),
              ),
            ),
            _synthNote(context, widget.repository),
          ],
        ),
      ),
    );
  }
}

class OpenBandLabDetail extends StatefulWidget {
  final OpenBandRepository repository;
  final DateTime Function() now;
  final String marker;
  const OpenBandLabDetail({
    super.key,
    required this.repository,
    required this.now,
    required this.marker,
  });
  @override
  State<OpenBandLabDetail> createState() => _OpenBandLabDetailState();
}

class _OpenBandLabDetailState extends State<OpenBandLabDetail> {
  LabSnapshot? _snap;
  bool _loading = true, _error = false;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final g = ++_gen;
    try {
      final snap = await widget.repository.readLabs();
      if (!mounted || g != _gen) return;
      setState(() {
        _snap = snap;
        _loading = false;
        _error = false;
      });
    } catch (_) {
      if (!mounted || g != _gen) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _edit(LabDraw draw, LabMarker? marker) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => OpenBandLabEditor(
          repository: widget.repository,
          now: widget.now,
          marker: marker ??
              LabMarker(
                key: draw.marker,
                label: draw.marker,
                unit: draw.unit,
                category: LabCategory.blood,
              ),
          existing: draw,
        ),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final snap = _snap;
    final history = [
      for (final r in snap?.results ?? const <LabDraw>[])
        if (r.marker == widget.marker) r,
    ];
    final marker = snap == null ? null : labResolve(snap, widget.marker);
    final title = labDisplayLabel(marker, widget.marker);
    final latest = history.isEmpty ? null : history.first;
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            OBPageHeader(
              title: title,
              subtitle: '',
              onInfo: () => _labInfo(
                context,
                'Befundbereich',
                'Angezeigt wird der Bereich auf dem Bericht, wenn er erfasst wurde. '
                    'Ohne Angabe bleibt er unbekannt. Ein Katalogbereich ist getrennt '
                    'und nur bei passender Einheit und bekanntem Geschlecht sichtbar.',
              ),
              infoLabel: 'Befundbereich',
            ),
            if (_error)
              OBCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Verlauf nicht geladen.', style: p.text(14)),
                    const SizedBox(height: 8),
                    OBAction('Erneut laden', ink: true, onPressed: _load),
                  ],
                ),
              )
            else if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator.adaptive()),
              )
            else if (latest == null)
              OBCard(child: Text('Keine Werte.', style: p.text(14)))
            else ...[
              OBCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 8,
                  children: [
                    Text(
                      labDayLabel(latest.takenOn),
                      style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      spacing: 8,
                      children: [
                        Text(
                          labFormatValue(latest, marker),
                          semanticsLabel: latest.readable ? null : 'unlesbar',
                          style: p
                              .text(48, weight: FontWeight.w700, display: true)
                              .copyWith(height: 56 / 48),
                        ),
                        Text(
                          latest.unit,
                          style: p
                              .text(17, color: p.muted)
                              .copyWith(height: 22 / 17),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: OBMeasurementRow.stacks(context)
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              spacing: 4,
                              children: [
                                Text(
                                  'Befundbereich',
                                  style: p
                                      .text(13, color: p.muted)
                                      .copyWith(height: 18 / 13),
                                ),
                                Text(
                                  labReportText(latest, marker),
                                  style: p.text(13).copyWith(height: 18 / 13),
                                ),
                              ],
                            )
                          : Row(
                              spacing: 12,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Befundbereich',
                                  style: p
                                      .text(13, color: p.muted)
                                      .copyWith(height: 18 / 13),
                                ),
                                Flexible(
                                  child: Text(
                                    labReportText(latest, marker),
                                    textAlign: TextAlign.end,
                                    style: p.text(13).copyWith(height: 18 / 13),
                                  ),
                                ),
                              ],
                            ),
                    ),
                    if (labCatalogueHint(marker, latest, snap?.sex)
                        case final hint?)
                      Text(hint, style: p.text(13, color: p.muted)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OBCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final r in history)
                      OBMeasurementRow(
                        key: ValueKey('lab-hist-${r.takenOn}'),
                        label: labDayMonth(r.takenOn),
                        date: labDayYear(r.takenOn),
                        value: labFormatValue(r, marker),
                        unit: r.unit,
                        semanticLabel: labUnreadableSemantics(
                          r,
                          labDayMonth(r.takenOn),
                          labDayYear(r.takenOn),
                        ),
                        onTap: () => _edit(r, marker),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OBAction(
                'Wert hinzufügen',
                ink: true,
                onPressed: marker == null
                    ? null
                    : () async {
                        await Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => OpenBandLabEditor(
                              repository: widget.repository,
                              now: widget.now,
                              marker: marker,
                            ),
                          ),
                        );
                        if (mounted) _load();
                      },
              ),
            ],
            _synthNote(context, widget.repository),
          ],
        ),
      ),
    );
  }
}

class OpenBandLabEditor extends StatefulWidget {
  final OpenBandRepository repository;
  final DateTime Function() now;
  final LabMarker marker;
  final LabDraw? existing;
  const OpenBandLabEditor({
    super.key,
    required this.repository,
    required this.now,
    required this.marker,
    this.existing,
  });
  @override
  State<OpenBandLabEditor> createState() => _OpenBandLabEditorState();
}

class _OpenBandLabEditorState extends State<OpenBandLabEditor> {
  late LabMarker _marker = widget.marker;
  late final _value = TextEditingController(
    text: widget.existing == null || !widget.existing!.readable
        ? ''
        : labFormatValue(widget.existing!, widget.marker).replaceAll('.', ','),
  );
  late final _unit = TextEditingController(
    text: widget.existing?.unit ?? widget.marker.unit,
  );
  late String _takenOn =
      widget.existing?.takenOn ?? dayLabelOf(widget.now());
  late final _low = TextEditingController(
    text: _boundText(widget.existing?.reportLow),
  );
  late final _high = TextEditingController(
    text: _boundText(widget.existing?.reportHigh),
  );
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  bool _busy = false, _dirty = false;
  String? _error;

  static String _boundText(double? v) =>
      v == null ? '' : obNumber(v, digits: v == v.roundToDouble() ? 0 : 1);

  @override
  void initState() {
    super.initState();
    _dirty = false;
    for (final c in [_value, _unit, _low, _high, _note]) {
      c.addListener(() => setState(() => _dirty = true));
    }
  }

  @override
  void dispose() {
    _value.dispose();
    _unit.dispose();
    _low.dispose();
    _high.dispose();
    _note.dispose();
    super.dispose();
  }

  LabDraw? _draft() {
    final v = LabParse.of(_value.text);
    final low = LabParse.of(_low.text);
    final high = LabParse.of(_high.text);
    if (v.bad || v.value == null) return null;
    if (labBoundsError(low, high) != null) return null;
    if (!isLabCalendarDay(_takenOn) || _unit.text.trim().isEmpty) return null;
    return LabDraw(
      marker: _marker.key,
      takenOn: _takenOn,
      value: v.value!,
      unit: _unit.text.trim(),
      note: _note.text.trim(),
      reportLow: low.value,
      reportHigh: high.value,
      extras: widget.existing?.extras ?? const {},
    );
  }

  String? _validate() {
    final v = LabParse.of(_value.text);
    if (v.blank || v.bad || v.value == null) {
      return 'Wert muss eine Zahl sein.';
    }
    if (_unit.text.trim().isEmpty) return 'Einheit fehlt.';
    if (!isLabCalendarDay(_takenOn)) return 'Datum ist ungültig.';
    return labBoundsError(LabParse.of(_low.text), LabParse.of(_high.text));
  }

  Future<void> _pickDate() async {
    final current = isLabCalendarDay(_takenOn)
        ? DateTime.parse(_takenOn)
        : widget.now();
    final picked = await showDatePicker(
      context: context,
      locale: const Locale('de'),
      initialDate: current,
      firstDate: DateTime(current.year - 20),
      lastDate: widget.now().add(const Duration(days: 1)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _takenOn = dayLabelOf(picked);
      _dirty = true;
    });
  }

  Future<void> _pickMarker() async {
    final snap = await widget.repository.readLabs();
    if (!mounted) return;
    final chosen = await _chooseMarker(context, widget.repository, snap);
    if (chosen == null || !mounted) return;
    setState(() {
      _marker = chosen;
      if (widget.existing == null && _unit.text == widget.marker.unit) {
        _unit.text = chosen.unit;
      }
      _dirty = true;
    });
  }

  Future<bool> _leave() async {
    if (_busy) return false;
    if (!_dirty) return true;
    final action = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Änderungen verwerfen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, 'stay'),
            child: const Text('Weiter bearbeiten'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, 'discard'),
            child: const Text('Verwerfen'),
          ),
        ],
      ),
    );
    return action == 'discard';
  }

  Future<void> _save({bool replaceExisting = false}) async {
    if (_busy) return;
    final issue = _validate();
    if (issue != null) {
      setState(() => _error = issue);
      return;
    }
    final draw = _draft();
    if (draw == null) {
      setState(() => _error = 'Wert unvollständig.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.saveLabDraw(
        draw,
        replacing: widget.existing,
        replaceExisting: replaceExisting,
      );
      if (!mounted) return;
      Navigator.pop(context);
    } on LabDrawCollision {
      if (!mounted) return;
      setState(() => _busy = false);
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Wert überschreiben?'),
          content: Text(
            'Für ${labDisplayLabel(_marker, _marker.key)} am '
            '${labDayLabel(_takenOn)} gibt es bereits einen Wert.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Abbrechen'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Überschreiben'),
            ),
          ],
        ),
      );
      if (ok == true && mounted) await _save(replaceExisting: true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Speichern fehlgeschlagen';
        });
      }
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null || _busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Wert entfernen'),
        content: Text(
          '${labDisplayLabel(_marker, existing.marker)}, '
          '${labDayLabel(existing.takenOn)}, '
          '${labFormatValue(existing, _marker)} ${existing.unit}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Wert entfernen'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.deleteLabDraw(existing.marker, existing.takenOn);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Nicht entfernt.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final stacked = OBMeasurementRow.stacks(context);
    InputDecoration well({String? hint}) => InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: p.well,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AlpRadius.well),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.all(14),
      constraints: const BoxConstraints(minHeight: 48),
    );
    Widget field(String label, Widget child) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Text(label, style: p.text(13, color: p.muted).copyWith(height: 18 / 13)),
        child,
      ],
    );
    final valueField = TextField(
      key: const ValueKey('lab-value'),
      controller: _value,
      enabled: !_busy,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: p.text(20).copyWith(height: 24 / 20),
      decoration: well(hint: 'Wert'),
    );
    final unitField = TextField(
      key: const ValueKey('lab-unit'),
      controller: _unit,
      enabled: !_busy,
      style: p.text(17).copyWith(height: 24 / 17),
      decoration: well(hint: 'Einheit'),
    );
    return PopScope(
      canPop: !_dirty && !_busy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _busy) return;
        if (await _leave() && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: p.canvas,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              OBPageHeader(
                title: widget.existing == null
                    ? 'Wert hinzufügen'
                    : 'Wert bearbeiten',
                subtitle: '',
                onBack: () async {
                  if (await _leave() && context.mounted) {
                    Navigator.pop(context);
                  }
                },
                onInfo: () => _labInfo(
                  context,
                  'Befundbereich',
                  'Optional der Bereich auf dem Bericht. Leer bedeutet unbekannt. '
                      'Eine Grenze allein ist zulässig.',
                ),
                infoLabel: 'Befundbereich',
              ),
              OBCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 16,
                  children: [
                    field(
                      'Marker',
                      InkWell(
                        onTap: _busy ? null : _pickMarker,
                        child: Container(
                          key: const ValueKey('lab-marker'),
                          width: double.infinity,
                          constraints: const BoxConstraints(minHeight: 48),
                          padding: const EdgeInsets.all(14),
                          alignment: Alignment.centerLeft,
                          decoration: BoxDecoration(
                            color: p.well,
                            borderRadius: BorderRadius.circular(AlpRadius.well),
                          ),
                          child: Text(
                            labDisplayLabel(_marker, _marker.key),
                            style: p.text(17).copyWith(height: 22 / 17),
                          ),
                        ),
                      ),
                    ),
                    stacked
                        ? Column(
                            spacing: 16,
                            children: [
                              field('Wert', valueField),
                              field('Einheit', unitField),
                            ],
                          )
                        : Row(
                            spacing: 12,
                            children: [
                              Expanded(child: field('Wert', valueField)),
                              SizedBox(
                                width: 112,
                                child: field('Einheit', unitField),
                              ),
                            ],
                          ),
                    field(
                      'Datum',
                      InkWell(
                        onTap: _busy ? null : _pickDate,
                        child: Container(
                          key: const ValueKey('lab-date'),
                          width: double.infinity,
                          constraints: const BoxConstraints(minHeight: 48),
                          padding: const EdgeInsets.all(14),
                          alignment: Alignment.centerLeft,
                          decoration: BoxDecoration(
                            color: p.well,
                            borderRadius: BorderRadius.circular(AlpRadius.well),
                          ),
                          child: Text(
                            labDayLabel(_takenOn),
                            style: p.text(17).copyWith(height: 22 / 17),
                          ),
                        ),
                      ),
                    ),
                    field(
                      'Befundbereich · optional',
                      Row(
                        spacing: 8,
                        children: [
                          Expanded(
                            child: TextField(
                              key: const ValueKey('lab-low'),
                              controller: _low,
                              enabled: !_busy,
                              style: p.text(17).copyWith(height: 22 / 17),
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: well(hint: '—'),
                            ),
                          ),
                          Text(
                            'bis',
                            style: p.text(17, color: p.muted).copyWith(height: 22 / 17),
                          ),
                          Expanded(
                            child: TextField(
                              key: const ValueKey('lab-high'),
                              controller: _high,
                              enabled: !_busy,
                              style: p.text(17).copyWith(height: 22 / 17),
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: well(hint: '—'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    field(
                      'Notiz · optional',
                      TextField(
                        key: const ValueKey('lab-note'),
                        controller: _note,
                        enabled: !_busy,
                        decoration: well(),
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _labErrorBanner(context, _error!),
              ],
              const SizedBox(height: 12),
              OBAction(
                _error == 'Speichern fehlgeschlagen'
                    ? 'Erneut speichern'
                    : 'Speichern',
                ink: true,
                onPressed: _busy ? null : _save,
              ),
              if (widget.existing != null) ...[
                const SizedBox(height: 12),
                OBAction(
                  'Wert entfernen',
                  ink: true,
                  secondary: true,
                  destructive: true,
                  onPressed: _busy ? null : _delete,
                ),
              ],
              _synthNote(context, widget.repository),
            ],
          ),
        ),
      ),
    );
  }
}

class OpenBandLabMarkers extends StatefulWidget {
  final OpenBandRepository repository;
  const OpenBandLabMarkers({super.key, required this.repository});
  @override
  State<OpenBandLabMarkers> createState() => _OpenBandLabMarkersState();
}

class _OpenBandLabMarkersState extends State<OpenBandLabMarkers> {
  LabSnapshot? _snap;
  bool _error = false;
  int _gen = 0;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final g = ++_gen;
    try {
      final snap = await widget.repository.readLabs();
      if (!mounted || g != _gen) return;
      setState(() {
        _snap = snap;
        _error = false;
      });
    } catch (_) {
      if (!mounted || g != _gen) return;
      setState(() => _error = true);
    }
  }

  Future<void> _edit([LabMarkerDef? def]) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => OpenBandLabMarkerEditor(
          repository: widget.repository,
          existing: def,
        ),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _remove(LabMarkerDef def) async {
    final held =
        _snap?.results.where((r) => r.marker == def.key).length ?? 0;
    if (held > 0) {
      setState(() => _message = '${def.label} hat noch Ergebnisse.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${def.label} entfernen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Entfernen'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.repository.deleteLabMarkerDef(def.key);
      await _load();
    } catch (_) {
      if (mounted) {
        setState(() => _message = '${def.label} hat noch Ergebnisse.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final mine = _snap?.custom ?? const <LabMarkerDef>[];
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const OBPageHeader(title: 'Eigene Marker', subtitle: ''),
            if (_error)
              OBCard(
                child: Column(
                  children: [
                    Text('Marker nicht geladen.', style: p.text(14)),
                    OBAction('Erneut laden', ink: true, onPressed: _load),
                  ],
                ),
              )
            else if (mine.isEmpty)
              OBCard(child: Text('Keine eigenen Marker.', style: p.text(14)))
            else
              OBCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (i, m) in mine.indexed) ...[
                      if (i > 0) Divider(height: 1, color: p.line),
                      ListTile(
                        title: Text(
                          m.label,
                          style: p.text(17, weight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${m.unit} · ${_categoryLabel[m.category] ?? m.category}',
                          style: p.text(13, color: p.muted),
                        ),
                        onTap: () => _edit(m),
                        trailing: IconButton(
                          tooltip: '${m.label} entfernen',
                          onPressed: () => _remove(m),
                          icon: Icon(LucideIcons.trash2, size: 18, color: p.muted),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!, style: p.text(13, color: p.danger)),
            ],
            const SizedBox(height: 12),
            OBAction('Marker anlegen', ink: true, onPressed: () => _edit()),
            _synthNote(context, widget.repository),
          ],
        ),
      ),
    );
  }
}

class OpenBandLabMarkerEditor extends StatefulWidget {
  final OpenBandRepository repository;
  final LabMarkerDef? existing;
  const OpenBandLabMarkerEditor({
    super.key,
    required this.repository,
    this.existing,
  });
  @override
  State<OpenBandLabMarkerEditor> createState() =>
      _OpenBandLabMarkerEditorState();
}

class _OpenBandLabMarkerEditorState extends State<OpenBandLabMarkerEditor> {
  late final _name = TextEditingController(
    text: widget.existing?.label ?? '',
  );
  late final _unit = TextEditingController(text: widget.existing?.unit ?? '');
  late String _category = widget.existing?.category ?? 'other';
  late final _decimals = TextEditingController(
    text: '${widget.existing?.decimals ?? 1}',
  );
  late final _low = TextEditingController(
    text: widget.existing?.refLow == null
        ? ''
        : obNumber(widget.existing!.refLow, digits: 1),
  );
  late final _high = TextEditingController(
    text: widget.existing?.refHigh == null
        ? ''
        : obNumber(widget.existing!.refHigh, digits: 1),
  );
  bool _busy = false, _dirty = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _unit, _decimals, _low, _high]) {
      c.addListener(() => setState(() => _dirty = true));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _decimals.dispose();
    _low.dispose();
    _high.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final label = _name.text.trim();
    final unit = _unit.text.trim();
    final low = LabParse.of(_low.text);
    final high = LabParse.of(_high.text);
    final decimals = int.tryParse(_decimals.text.trim());
    if (label.isEmpty || unit.isEmpty) {
      setState(() => _error = 'Name und Einheit braucht der Marker.');
      return;
    }
    if (decimals == null || decimals < 0 || decimals > 3) {
      setState(() => _error = 'Genauigkeit 0–3.');
      return;
    }
    final bounds = labBoundsError(low, high);
    if (bounds != null) {
      setState(() => _error = bounds);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final snap = await widget.repository.readLabs();
      if (!mounted) return;
      final creating = widget.existing == null;
      final key = widget.existing?.key ??
          allocateCustomLabMarkerKey(label, snap.custom.map((c) => c.key));
      if (creating) {
        if (kLabMarkersByKey.containsKey(key) ||
            !key.startsWith('custom_') ||
            key == 'custom_') {
          setState(() {
            _busy = false;
            _error = 'Dieser Name ist reserviert.';
          });
          return;
        }
        if (snap.custom.any((c) => c.key == key)) {
          setState(() {
            _busy = false;
            _error = 'Name ist vergeben.';
          });
          return;
        }
      }
      await widget.repository.saveLabMarkerDef(
        LabMarkerDef(
          key: key,
          label: label,
          unit: unit,
          category: _category,
          decimals: decimals,
          refLow: low.value,
          refHigh: high.value,
          createdAt: widget.existing?.createdAt ?? 0,
        ),
        create: creating,
      );
      if (mounted) Navigator.pop(context);
    } on LabMarkerCollision {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Name ist vergeben.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Speichern fehlgeschlagen';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    InputDecoration well({String? hint}) => InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: p.well,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AlpRadius.well),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.all(14),
      constraints: const BoxConstraints(minHeight: 48),
    );
    Widget defField(String label, Widget child) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Text(
          label,
          style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
        ),
        child,
      ],
    );
    return PopScope(
      canPop: !_dirty && !_busy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _busy) return;
        if (!_dirty) {
          Navigator.pop(context);
          return;
        }
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Änderungen verwerfen?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Weiter bearbeiten'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Verwerfen'),
              ),
            ],
          ),
        );
        if (ok == true && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: p.canvas,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              const OBPageHeader(title: 'Eigener Marker', subtitle: ''),
              OBCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 16,
                  children: [
                    defField(
                      'Name',
                      TextField(
                        key: const ValueKey('lab-def-name'),
                        controller: _name,
                        enabled: !_busy,
                        style: p.text(17).copyWith(height: 22 / 17),
                        decoration: well(),
                      ),
                    ),
                    OBMeasurementRow.stacks(context)
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: 16,
                            children: [
                              defField(
                                'Nachkommastellen',
                                TextField(
                                  key: const ValueKey('lab-def-decimals'),
                                  controller: _decimals,
                                  enabled: !_busy,
                                  keyboardType: TextInputType.number,
                                  style: p
                                      .text(20, weight: FontWeight.w600)
                                      .copyWith(height: 24 / 20),
                                  decoration: well(),
                                ),
                              ),
                              defField(
                                'Einheit',
                                TextField(
                                  key: const ValueKey('lab-def-unit'),
                                  controller: _unit,
                                  enabled: !_busy,
                                  style: p.text(17).copyWith(height: 24 / 17),
                                  decoration: well(),
                                ),
                              ),
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 12,
                            children: [
                              Expanded(
                                child: defField(
                                  'Nachkommastellen',
                                  TextField(
                                    key: const ValueKey('lab-def-decimals'),
                                    controller: _decimals,
                                    enabled: !_busy,
                                    keyboardType: TextInputType.number,
                                    style: p
                                        .text(20, weight: FontWeight.w600)
                                        .copyWith(height: 24 / 20),
                                    decoration: well(),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 112,
                                child: defField(
                                  'Einheit',
                                  TextField(
                                    key: const ValueKey('lab-def-unit'),
                                    controller: _unit,
                                    enabled: !_busy,
                                    style: p.text(17).copyWith(height: 24 / 17),
                                    decoration: well(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                    defField(
                      'Kategorie',
                      InkWell(
                        onTap: _busy
                            ? null
                            : () async {
                                final v = await showModalBottomSheet<String>(
                                  context: context,
                                  builder: (c) => SafeArea(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        for (final id in _categoryOrder)
                                          ListTile(
                                            title: Text(_categoryLabel[id]!),
                                            onTap: () => Navigator.pop(c, id),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                                if (v == null || !mounted) return;
                                setState(() {
                                  _category = v;
                                  _dirty = true;
                                });
                              },
                        child: Container(
                          key: const ValueKey('lab-def-category'),
                          constraints: const BoxConstraints(minHeight: 48),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: p.well,
                            borderRadius: BorderRadius.circular(AlpRadius.well),
                          ),
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _categoryLabel[_category]!,
                            style: p.text(17).copyWith(height: 22 / 17),
                          ),
                        ),
                      ),
                    ),
                    defField(
                      'Referenzbereich · optional',
                      Row(
                        spacing: 8,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _low,
                              enabled: !_busy,
                              style: p.text(17).copyWith(height: 22 / 17),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: well(hint: '—'),
                            ),
                          ),
                          Text(
                            'bis',
                            style: p
                                .text(17, color: p.muted)
                                .copyWith(height: 22 / 17),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _high,
                              enabled: !_busy,
                              style: p.text(17).copyWith(height: 22 / 17),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: well(hint: '—'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _labErrorBanner(context, _error!),
              ],
              const SizedBox(height: 12),
              OBAction(
                _error == 'Speichern fehlgeschlagen'
                    ? 'Erneut speichern'
                    : 'Speichern',
                ink: true,
                onPressed: _busy ? null : _save,
              ),
              _synthNote(context, widget.repository),
            ],
          ),
        ),
      ),
    );
  }
}

Future<LabMarker?> _chooseMarker(
  BuildContext context,
  OpenBandRepository repository,
  LabSnapshot? snap,
) async {
  snap ??= await repository.readLabs();
  if (!context.mounted) return null;
  return Navigator.of(context).push<LabMarker>(
    MaterialPageRoute(
      builder: (_) => _LabChooser(snapshot: snap!),
    ),
  );
}

class _LabChooser extends StatefulWidget {
  final LabSnapshot snapshot;
  const _LabChooser({required this.snapshot});
  @override
  State<_LabChooser> createState() => _LabChooserState();
}

class _LabChooserState extends State<_LabChooser> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final custom = [
      for (final c in widget.snapshot.custom)
        LabMarker(
          key: c.key,
          label: c.label,
          unit: c.unit,
          category:
              LabCategory.values.asNameMap()[c.category] ?? LabCategory.blood,
          decimals: c.decimals,
          custom: true,
        ),
    ];
    bool match(LabMarker m) {
      if (_q.isEmpty) return true;
      final q = _q.toLowerCase();
      return labDisplayLabel(m, m.key).toLowerCase().contains(q) ||
          m.unit.toLowerCase().contains(q) ||
          m.key.contains(q);
    }

    final grouped = <String, List<LabMarker>>{};
    for (final m in kLabMarkers) {
      if (!match(m)) continue;
      (grouped[m.category.name] ??= []).add(m);
    }
    for (final m in custom) {
      if (!match(m)) continue;
      final def = widget.snapshot.custom.firstWhere((c) => c.key == m.key);
      (grouped[def.category] ??= []).add(m);
    }
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: OBPageHeader(title: 'Marker', subtitle: ''),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                key: const ValueKey('lab-search'),
                autofocus: true,
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: 'Suchen',
                  prefixIcon: const Icon(LucideIcons.search, size: 18),
                  filled: true,
                  fillColor: p.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AlpRadius.well),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  for (final id in _categoryOrder)
                    if (grouped[id] case final list?) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                        child: Text(
                          _categoryLabel[id]!,
                          style: p.text(13, color: p.muted),
                        ),
                      ),
                      OBCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (final (i, m) in list.indexed) ...[
                              if (i > 0) Divider(height: 1, color: p.line),
                              ListTile(
                                title: Text(
                                  labDisplayLabel(m, m.key),
                                  style: p.text(17, weight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  m.unit,
                                  style: p.text(13, color: p.muted),
                                ),
                                onTap: () => Navigator.pop(context, m),
                              ),
                            ],
                          ],
                        ),
                      ),
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

void _labInfo(BuildContext context, String title, String body) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (c) {
        final p = OB.of(c);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: p.text(18, weight: FontWeight.w600)),
                const SizedBox(height: 12),
                Text(body, style: p.text(14, color: p.muted)),
                const SizedBox(height: 12),
                OBAction('Schließen', ink: true, onPressed: () => Navigator.pop(c)),
              ],
            ),
          ),
        );
      },
    );

Widget _labErrorBanner(BuildContext context, String message) {
  final p = OB.of(context);
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: p.dangerTint,
      borderRadius: BorderRadius.circular(AlpRadius.well),
    ),
    child: Text(
      message,
      style: p.text(14, color: p.danger).copyWith(height: 20 / 14),
    ),
  );
}

Widget _synthNote(BuildContext context, OpenBandRepository repository) {
  if (repository is! SyntheticOpenBandRepository) {
    return const SizedBox.shrink();
  }
  final p = OB.of(context);
  return Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Text(
      'Synthetische Daten',
      style: p.text(12, color: p.muted).copyWith(height: 16 / 12),
    ),
  );
}
