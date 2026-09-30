import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/day_label.dart';
import 'domain.dart';
import 'glucose_chart.dart';
import 'journal_controls.dart';
import 'settings_controls.dart';
import 'synthetic_repository.dart';
import 'theme.dart';

const _infoTitle = 'Glukosewerte';
const kGlucoseHeroLimit = 1;
const kGlucoseHistoryPage = 200;

String glucoseInfoBody([TargetPlatform? platform]) {
  final store = platform == TargetPlatform.android
      ? 'Health Connect'
      : 'Apple Health';
  return 'Messwerte aus $store, getrennt nach Quelle. OpenBand misst Glukose nicht.\n'
      'Wert und Einheit stammen aus dem gespeicherten Datensatz. Punkte sind einzelne Messungen; Lücken bleiben offen.\n'
      '„Importiert“ bezeichnet das Speichern in OpenBand, „Abgefragt“ die letzte Health-Abfrage. Ein leeres Ergebnis bestätigt oder widerlegt keinen Lesezugriff.\n'
      'Ausgeschlossene Quellen werden nicht angezeigt oder neu übernommen. Gespeicherte Messungen bleiben im Verlauf.';
}

String glucoseUnitLabel(String rawUnit) {
  switch (glucoseUnitKind(rawUnit)) {
    case GlucoseUnitKind.milligramPerDeciliter:
      return 'mg/dL';
    case GlucoseUnitKind.millimolePerLiter:
      return 'mmol/L';
    case GlucoseUnitKind.unknown:
      return rawUnit;
  }
}

const _syntheticFixtureSourceName = 'Sensor-App (synthetisch) via Apple Health';

String glucoseSourceTitle(GlucoseSourceIdentity source) {
  if (source.unknownIdentity) return 'Unbekannte Quelle';
  final name = source.sourceName.trim();
  if (name.isEmpty) return 'Unbekannte Quelle';
  if (source.provenance == GlucoseSourceProvenance.synthetic &&
      name == _syntheticFixtureSourceName) {
    return 'Sensor-App';
  }
  return name;
}

String? glucoseProviderLabel(GlucoseSourceIdentity source) {
  switch (source.provenance) {
    case GlucoseSourceProvenance.apple:
    case GlucoseSourceProvenance.synthetic:
      return 'Apple Health';
    case GlucoseSourceProvenance.android:
      return 'Health Connect';
    case GlucoseSourceProvenance.legacy:
    case GlucoseSourceProvenance.unknown:
      return null;
  }
}

String glucoseSourceLine(
  GlucoseSourceIdentity? source, {
  TargetPlatform? platform,
  bool excluded = false,
}) {
  if (source == null) {
    return platform == TargetPlatform.android
        ? 'Health Connect'
        : 'Apple Health';
  }
  final title = glucoseSourceTitle(source);
  if (excluded) return '$title · Ausgeblendet';
  final provider = glucoseProviderLabel(source);
  if (provider == null || provider == title) return title;
  return '$title · $provider';
}

const _deShortMonths = [
  'Jan.',
  'Feb.',
  'März',
  'Apr.',
  'Mai',
  'Juni',
  'Juli',
  'Aug.',
  'Sep.',
  'Okt.',
  'Nov.',
  'Dez.',
];

String glucoseStamp(DateTime? at, {DateTime? now}) {
  if (at == null) return '—';
  final local = _glucoseLocal(at);
  final month = _deShortMonths[local.month - 1];
  final date = local.year != _glucoseClock(now).year
      ? '${local.day}. $month ${local.year}'
      : '${local.day}. $month';
  return '$date, ${obTime(local)}';
}

String _glucoseCalendarDate(DateTime at, DateTime? now) =>
    _glucoseObDate(dayLabelOf(at), now);

String _glucoseObDate(String day, DateTime? now) {
  final labeled = obDate(day);
  final year = DateTime.parse(day).year;
  if (year == _glucoseClock(now).year) return labeled;
  return '$labeled $year';
}

DateTime _glucoseLocal(DateTime at) => at.isUtc ? at.toLocal() : at;

DateTime _glucoseClock(DateTime? now) => _glucoseLocal(now ?? DateTime.now());

String glucoseValueLabel(GlucoseReading reading) {
  final value = reading.value;
  final digits = reading.unitKind == GlucoseUnitKind.millimolePerLiter
      ? 1
      : (value == value.roundToDouble() ? 0 : 1);
  final fixed = obNumber(value, digits: digits);
  if (value != 0 && (_glucoseFixedLooksZero(fixed) || fixed.length > 12)) {
    return _glucoseScientific(value);
  }
  return fixed;
}

bool _glucoseFixedLooksZero(String fixed) {
  for (var i = 0; i < fixed.length; i++) {
    final c = fixed.codeUnitAt(i);
    if (c >= 49 && c <= 57) return false;
  }
  return true;
}

String _glucoseScientific(double value) {
  return value
      .toStringAsExponential(1)
      .replaceFirst('.', ',')
      .replaceFirst('e+', 'e');
}

String _choiceLabel(
  GlucoseSourceIdentity source,
  List<GlucoseSourceIdentity> all,
) {
  final title = glucoseSourceTitle(source);
  final same = [
    for (final s in all)
      if (glucoseSourceTitle(s) == title) s,
  ];
  if (same.length < 2) return title;
  final extra = source.sourceId?.trim();
  if (extra != null && extra.isNotEmpty) return '$title · $extra';
  return '$title · ${source.key}';
}

List<({DateTime at, double value})> glucosePlotReadings(GlucoseSnapshot snap) {
  if (snap.selectedExcluded) return const [];
  final latest = snap.history.isEmpty ? null : snap.history.first;
  if (latest != null && latest.unitKind == GlucoseUnitKind.unknown) {
    return const [];
  }
  final points = [
    for (final r in snap.series)
      if (r.plottable) (at: r.measuredAt, value: r.value),
  ]..sort((a, b) => a.at.compareTo(b.at));
  if (points.isEmpty) return const [];
  final last = points.last.at;
  final start = DateTime(last.year, last.month, last.day);
  final end = DateTime(last.year, last.month, last.day + 1);
  return [
    for (final p in points)
      if (!p.at.isBefore(start) && p.at.isBefore(end)) p,
  ];
}

class OpenBandGlucose extends StatefulWidget {
  final OpenBandRepository repository;
  final DateTime Function()? now;
  final bool synthetic;
  final String? sourceKey;
  const OpenBandGlucose({
    super.key,
    required this.repository,
    this.now,
    this.synthetic = false,
    this.sourceKey,
  });

  static Future<void> push(
    BuildContext context, {
    required OpenBandRepository repository,
    DateTime Function()? now,
    bool synthetic = false,
    String? sourceKey,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => OpenBandGlucose(
        repository: repository,
        now: now,
        synthetic: synthetic,
        sourceKey: sourceKey,
      ),
    ),
  );

  @override
  State<OpenBandGlucose> createState() => _OpenBandGlucoseState();
}

class _OpenBandGlucoseState extends State<OpenBandGlucose> {
  int _token = 0;
  String? _wantedKey;
  GlucoseSnapshot? _snap;
  bool _loading = true;
  bool _storeError = false;
  bool _reading = false;
  HealthMeasurementImportStatus? _importStatus;

  bool get _synthetic =>
      widget.synthetic || widget.repository is SyntheticOpenBandRepository;

  @override
  void initState() {
    super.initState();
    _wantedKey = widget.sourceKey;
    _load();
  }

  @override
  void didUpdateWidget(covariant OpenBandGlucose oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository) ||
        oldWidget.sourceKey != widget.sourceKey) {
      setState(() => _abandon(key: widget.sourceKey));
      _load();
    }
  }

  void _abandon({String? key}) {
    _token++;
    _wantedKey = key;
    _snap = null;
    _loading = true;
    _storeError = false;
    _reading = false;
    _importStatus = null;
  }

  Future<void> _load() async {
    final token = ++_token;
    final key = _wantedKey;
    setState(() {
      _loading = _snap == null;
      if (_snap == null) _storeError = false;
    });
    try {
      final snap = await widget.repository.readGlucose(
        sourceKey: key,
        limit: kGlucoseHeroLimit,
      );
      if (!mounted || token != _token) return;
      setState(() {
        _snap = snap;
        _loading = false;
        _storeError = false;
        _importStatus = null;
        _wantedKey ??= snap.selected?.key;
      });
    } catch (_) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _storeError = true;
      });
    }
  }

  Future<void> _import() async {
    if (_reading) return;
    final token = ++_token;
    final key = _wantedKey;
    setState(() => _reading = true);
    try {
      final result = await widget.repository.importGlucose(
        now: widget.now?.call(),
      );
      if (!mounted || token != _token) return;
      final outcome = result.outcome;
      setState(() {
        _importStatus = outcome.status;
        _storeError = false;
        final snap = result.snapshot;
        if (!result.refreshFailed &&
            snap != null &&
            _snapshotForKey(snap, key)) {
          _snap = snap;
          _wantedKey ??= snap.selected?.key;
        }
      });
      if (outcome.failed && !result.refreshFailed) {
        setState(() => _reading = false);
        return;
      }
      try {
        final fresh = await widget.repository.readGlucose(
          sourceKey: key,
          limit: kGlucoseHeroLimit,
        );
        if (!mounted || token != _token) return;
        setState(() {
          _snap = fresh;
          _reading = false;
          _storeError = false;
          _importStatus = null;
          _wantedKey ??= fresh.selected?.key;
        });
      } catch (_) {
        if (!mounted || token != _token) return;
        setState(() {
          _reading = false;
          _storeError = true;
          if (!outcome.failed) _importStatus = null;
        });
      }
    } catch (_) {
      if (!mounted || token != _token) return;
      setState(() {
        _reading = false;
        _storeError = true;
      });
    }
  }

  void _info() {
    final snap = _snap;
    var body = glucoseInfoBody(Theme.of(context).platform);
    if (snap != null && _partial(snap)) {
      final bits = <String>[
        if (snap.unreadableCount > 0) '${snap.unreadableCount} unlesbar',
        if (snap.attempt.invalidCount > 0) '${snap.attempt.invalidCount} ungültig',
        if (snap.attempt.ignoredCount > 0) '${snap.attempt.ignoredCount} ignoriert',
      ];
      if (bits.isNotEmpty) body = '$body\n${bits.join(' · ')}';
    }
    showOpenBandJournalInfo(context, title: _infoTitle, body: body);
  }

  Future<void> _openSource() async {
    final snap = _snap;
    if (snap == null) return;
    final sources = [for (final s in snap.sources) s.source];
    if (sources.isEmpty) return;
    String? key = sources.length == 1
        ? sources.first.key
        : await showOpenBandSettingsChoiceSheet<String>(
            context: context,
            title: 'Quelle',
            selected: snap.selected?.key,
            choices: [
              for (final s in sources) (s.key, _choiceLabel(s, sources)),
            ],
          );
    if (!mounted || key == null) return;
    _wantedKey = key;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => OpenBandGlucoseSource(
          repository: widget.repository,
          sourceKey: key,
          now: widget.now,
          synthetic: _synthetic,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openHistory() async {
    final key = _wantedKey ?? _snap?.selected?.key;
    if (key == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => OpenBandGlucoseHistory(
          repository: widget.repository,
          sourceKey: key,
          now: widget.now,
          synthetic: _synthetic,
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final snap = _snap;
    final waiting = _loading && snap == null && !_storeError;
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            OBPageHeader(
              title: 'Glukose',
              subtitle: '',
              onInfo: _info,
              infoLabel: 'Glukosewerte',
            ),
            if (waiting)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator.adaptive()),
              )
            else if (_storeError && snap == null)
              OBSettingsErrorCard(
                key: const ValueKey('glucose-error'),
                message: 'Lesen fehlgeschlagen',
                retryLabel: 'Erneut',
                onRetry: _reading ? null : _load,
              )
            else if (snap != null) ...[
              _GlucoseHero(snap: snap, now: widget.now?.call()),
              if (_bannerError(snap) != null) ...[
                const SizedBox(height: 12),
                OBSettingsErrorCard(
                  key: const ValueKey('glucose-error'),
                  message: _bannerError(snap)!,
                  retryLabel: 'Erneut',
                  onRetry: _reading ? null : _retry,
                ),
              ],
              if (_showChart(snap)) ...[
                const SizedBox(height: 12),
                OBGlucoseChart(
                  readings: glucosePlotReadings(snap),
                  unit: _chartUnit(snap),
                ),
              ],
              if (_emptyCopy(snap) != null) ...[
                const SizedBox(height: 12),
                OBCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 16,
                    children: [
                      Text(
                        _emptyCopy(snap)!,
                        style: p
                            .text(15, color: p.muted)
                            .copyWith(height: 20 / 15),
                      ),
                      OBAction(
                        'Jetzt lesen',
                        key: const ValueKey('glucose-lesen'),
                        ink: true,
                        onPressed: _reading ? null : _import,
                      ),
                    ],
                  ),
                ),
              ],
              if (snap.sources.isNotEmpty) ...[
                const SizedBox(height: 12),
                _GlucoseGroup(
                  children: [
                    OBSettingsValueRow(
                      key: const ValueKey('glucose-quelle'),
                      label: 'Quelle',
                      value: snap.selected == null
                          ? '—'
                          : glucoseSourceTitle(snap.selected!),
                      chevron: true,
                      onTap: _openSource,
                    ),
                    OBSettingsValueRow(
                      key: const ValueKey('glucose-messungen'),
                      label: 'Messungen',
                      value: '${_readingCount(snap)}',
                      chevron: true,
                      onTap: _openHistory,
                    ),
                  ],
                ),
              ],
              if (_synthetic) const _GlucoseSyntheticNote(),
            ],
          ],
        ),
      ),
    );
  }

  VoidCallback get _retry {
    if (_storeError) return _load;
    return _import;
  }

  String? _bannerError(GlucoseSnapshot snap) {
    if (_storeError) return 'Lesen fehlgeschlagen';
    final status = _importStatus ?? snap.attempt.status;
    return _attemptFailed(status) ? _statusCopy(status) : null;
  }

  String? _emptyCopy(GlucoseSnapshot snap) {
    if (snap.history.isNotEmpty) return null;
    final status = _importStatus ?? snap.attempt.status;
    if (_attemptFailed(status)) return null;
    if (status == HealthMeasurementImportStatus.empty) {
      return 'Keine Werte gelesen';
    }
    return 'Keine Werte gespeichert';
  }
}

class OpenBandGlucoseSource extends StatefulWidget {
  final OpenBandRepository repository;
  final String sourceKey;
  final DateTime Function()? now;
  final bool synthetic;
  const OpenBandGlucoseSource({
    super.key,
    required this.repository,
    required this.sourceKey,
    this.now,
    this.synthetic = false,
  });

  @override
  State<OpenBandGlucoseSource> createState() => _OpenBandGlucoseSourceState();
}

class _OpenBandGlucoseSourceState extends State<OpenBandGlucoseSource> {
  int _token = 0;
  GlucoseSnapshot? _snap;
  bool _loading = true;
  bool _storeError = false;
  bool _reading = false;
  bool _toggling = false;
  bool? _retryIncluded;
  bool _toggleError = false;
  HealthMeasurementImportStatus? _importStatus;

  bool get _synthetic =>
      widget.synthetic || widget.repository is SyntheticOpenBandRepository;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant OpenBandGlucoseSource oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository) ||
        oldWidget.sourceKey != widget.sourceKey) {
      setState(_abandon);
      _load();
    }
  }

  void _abandon() {
    _token++;
    _snap = null;
    _loading = true;
    _storeError = false;
    _reading = false;
    _toggling = false;
    _retryIncluded = null;
    _toggleError = false;
    _importStatus = null;
  }

  Future<void> _load() async {
    final token = ++_token;
    final key = widget.sourceKey;
    setState(() {
      _loading = _snap == null;
      _toggleError = false;
    });
    try {
      final snap = await widget.repository.readGlucose(
        sourceKey: key,
        limit: kGlucoseHeroLimit,
      );
      if (!mounted || token != _token) return;
      setState(() {
        _snap = snap;
        _loading = false;
        _storeError = false;
        _toggling = false;
        _importStatus = null;
      });
    } catch (_) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _storeError = true;
        _toggling = false;
      });
    }
  }

  Future<void> _import() async {
    if (_reading) return;
    final token = ++_token;
    final key = widget.sourceKey;
    setState(() => _reading = true);
    try {
      final result = await widget.repository.importGlucose(
        now: widget.now?.call(),
      );
      if (!mounted || token != _token) return;
      final outcome = result.outcome;
      setState(() {
        _importStatus = outcome.status;
        _storeError = false;
        final snap = result.snapshot;
        if (!result.refreshFailed &&
            snap != null &&
            _snapshotForKey(snap, key)) {
          _snap = snap;
        }
      });
      if (outcome.failed && !result.refreshFailed) {
        setState(() => _reading = false);
        return;
      }
      try {
        final fresh = await widget.repository.readGlucose(
          sourceKey: key,
          limit: kGlucoseHeroLimit,
        );
        if (!mounted || token != _token) return;
        setState(() {
          _snap = fresh;
          _reading = false;
          _storeError = false;
          _importStatus = null;
        });
      } catch (_) {
        if (!mounted || token != _token) return;
        setState(() {
          _reading = false;
          _storeError = true;
          if (!outcome.failed) _importStatus = null;
        });
      }
    } catch (_) {
      if (!mounted || token != _token) return;
      setState(() {
        _reading = false;
        _storeError = true;
      });
    }
  }

  Future<void> _setIncluded(bool included) async {
    if (_toggling) return;
    final token = ++_token;
    setState(() {
      _toggling = true;
      _toggleError = false;
      _retryIncluded = included;
    });
    try {
      await widget.repository.setGlucoseSourceIncluded(
        widget.sourceKey,
        included: included,
      );
      if (!mounted || token != _token) return;
      await _load();
    } catch (_) {
      if (!mounted || token != _token) return;
      setState(() {
        _toggling = false;
        _toggleError = true;
      });
    }
  }

  GlucoseSourceInventoryItem? _item(GlucoseSnapshot snap) {
    for (final s in snap.sources) {
      if (s.source.key == widget.sourceKey) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final snap = _snap;
    final item = snap == null ? null : _item(snap);
    final source = item?.source ?? snap?.selected;
    final waiting = _loading && snap == null && !_storeError;
    final included = !(item?.excluded ?? snap?.selectedExcluded ?? false);
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            OBPageHeader(
              title: 'Quelle',
              subtitle: '',
              onInfo: () => showOpenBandJournalInfo(
                context,
                title: _infoTitle,
                body: _sourceInfo(
                  source,
                  snap,
                  Theme.of(context).platform,
                ),
              ),
              infoLabel: 'Glukosewerte',
            ),
            if (waiting)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator.adaptive()),
              )
            else if (_storeError && source == null)
              OBSettingsErrorCard(
                key: const ValueKey('glucose-error'),
                message: 'Lesen fehlgeschlagen',
                retryLabel: 'Erneut',
                onRetry: _reading ? null : _load,
              )
            else if (source != null) ...[
              OBCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: Text(
                        glucoseSourceTitle(source),
                        style: p
                            .text(17, weight: FontWeight.w600)
                            .copyWith(height: 22 / 17),
                      ),
                    ),
                    if ((glucoseProviderLabel(source) ??
                            _legacyIdentity(source))
                        case final provider?)
                      Text(
                        provider,
                        style: p
                            .text(13, color: p.muted)
                            .copyWith(height: 18 / 13),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _GlucoseGroup(
                children: [
                  OBSettingsValueRow(
                    label: 'Letzte Messung',
                    value: glucoseStamp(
                      item?.lastMeasuredAt ?? snap?.lastMeasuredAt,
                      now: widget.now?.call(),
                    ),
                    interactive: false,
                  ),
                  OBSettingsValueRow(
                    label: 'Importiert',
                    value: glucoseStamp(
                      item?.lastImportedAt ?? snap?.lastImportedAt,
                      now: widget.now?.call(),
                    ),
                    interactive: false,
                  ),
                  OBSettingsValueRow(
                    label: 'Abgefragt',
                    value: glucoseStamp(
                      snap?.attempt.attemptedAt,
                      now: widget.now?.call(),
                    ),
                    interactive: false,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OBCard(
                padding: EdgeInsets.zero,
                child: OBSettingsToggleRow(
                  key: const ValueKey('glucose-verwenden'),
                  label: 'Verwenden',
                  value: included,
                  interactive: !_toggling && !_reading,
                  onToggle: _toggling || _reading
                      ? null
                      : () => _setIncluded(!included),
                ),
              ),
              if (_toggleError) ...[
                const SizedBox(height: 12),
                OBSettingsErrorCard(
                  key: const ValueKey('glucose-toggle-error'),
                  message: 'Speichern fehlgeschlagen',
                  retryLabel: 'Erneut',
                  onRetry: _retryIncluded == null
                      ? null
                      : () => _setIncluded(_retryIncluded!),
                ),
              ],
              const SizedBox(height: 12),
              OBAction(
                'Jetzt lesen',
                key: const ValueKey('glucose-lesen'),
                ink: true,
                onPressed: _reading || _toggling ? null : _import,
              ),
              if (_sourceError) ...[
                const SizedBox(height: 12),
                OBSettingsErrorCard(
                  key: const ValueKey('glucose-error'),
                  message: _sourceErrorMessage,
                  retryLabel: 'Erneut',
                  onRetry: _reading
                      ? null
                      : (_storeError ? _load : _import),
                ),
              ],
              if (_synthetic) const _GlucoseSyntheticNote(),
            ],
          ],
        ),
      ),
    );
  }

  bool get _sourceError {
    if (_storeError) return true;
    final status = _importStatus ?? _snap?.attempt.status;
    return status != null && _attemptFailed(status);
  }

  String get _sourceErrorMessage {
    if (_storeError) return 'Lesen fehlgeschlagen';
    return _statusCopy(_importStatus ?? _snap?.attempt.status);
  }
}

class OpenBandGlucoseHistory extends StatefulWidget {
  final OpenBandRepository repository;
  final String sourceKey;
  final DateTime Function()? now;
  final bool synthetic;
  const OpenBandGlucoseHistory({
    super.key,
    required this.repository,
    required this.sourceKey,
    this.now,
    this.synthetic = false,
  });

  @override
  State<OpenBandGlucoseHistory> createState() => _OpenBandGlucoseHistoryState();
}

class _OpenBandGlucoseHistoryState extends State<OpenBandGlucoseHistory> {
  int _token = 0;
  int _limit = kGlucoseHistoryPage;
  GlucoseSnapshot? _snap;
  bool _loading = true;
  bool _storeError = false;
  bool _loadingMore = false;

  bool get _synthetic =>
      widget.synthetic || widget.repository is SyntheticOpenBandRepository;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant OpenBandGlucoseHistory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository) ||
        oldWidget.sourceKey != widget.sourceKey) {
      setState(() {
        _token++;
        _limit = kGlucoseHistoryPage;
        _snap = null;
        _loading = true;
        _storeError = false;
        _loadingMore = false;
      });
      _load();
    }
  }

  Future<void> _load({bool more = false}) async {
    final token = ++_token;
    final limit = more ? _limit + kGlucoseHistoryPage : _limit;
    setState(() {
      if (!more) _loading = _snap == null;
      _loadingMore = more;
    });
    try {
      final snap = await widget.repository.readGlucose(
        sourceKey: widget.sourceKey,
        limit: limit,
      );
      if (!mounted || token != _token) return;
      setState(() {
        _snap = snap;
        _limit = limit;
        _loading = false;
        _loadingMore = false;
        _storeError = false;
      });
    } catch (_) {
      if (!mounted || token != _token) return;
      setState(() {
        _limit = limit;
        _loading = false;
        _loadingMore = false;
        _storeError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final snap = _snap;
    final waiting = _loading && snap == null && !_storeError;
    final groups = snap == null
        ? const <_HistoryGroup>[]
        : _groups(snap, Theme.of(context).platform, widget.now?.call());
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
              sliver: SliverToBoxAdapter(
                child: OBPageHeader(title: 'Messungen', subtitle: ''),
              ),
            ),
            if (waiting)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator.adaptive()),
                ),
              )
            else if (_storeError && snap == null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverToBoxAdapter(
                  child: OBSettingsErrorCard(
                    key: const ValueKey('glucose-error'),
                    message: 'Lesen fehlgeschlagen',
                    retryLabel: 'Erneut',
                    onRetry: _loadingMore ? null : () => _load(),
                  ),
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                sliver: SliverList.builder(
                  itemCount: groups.length,
                  itemBuilder: (context, i) {
                    final group = groups[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          OBCard(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              spacing: 4,
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  child: Text(
                                    group.date,
                                    style: p
                                        .text(17, weight: FontWeight.w600)
                                        .copyWith(height: 22 / 17),
                                  ),
                                ),
                                SizedBox(
                                  width: double.infinity,
                                  child: Text(
                                    group.source,
                                    style: p
                                        .text(13, color: p.muted)
                                        .copyWith(height: 18 / 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _GlucoseGroup(
                            children: [
                              for (final row in group.rows)
                                OBSettingsValueRow(
                                  label: obTime(_glucoseLocal(row.measuredAt)),
                                  value:
                                      '${glucoseValueLabel(row)} ${glucoseUnitLabel(row.rawUnit)}',
                                  interactive: false,
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (snap?.truncated == true)
                        OBAction(
                          'Mehr laden',
                          key: const ValueKey('glucose-mehr'),
                          ink: true,
                          secondary: true,
                          onPressed: _loadingMore || _storeError
                              ? null
                              : () => _load(more: true),
                        ),
                      if (_storeError) ...[
                        if (snap?.truncated == true) const SizedBox(height: 12),
                        OBSettingsErrorCard(
                          key: const ValueKey('glucose-error'),
                          message: 'Lesen fehlgeschlagen',
                          retryLabel: 'Erneut',
                          onRetry: _loadingMore ? null : () => _load(),
                        ),
                      ],
                      if (_synthetic)
                        _GlucoseSyntheticNote(
                          padding: EdgeInsets.fromLTRB(
                            4,
                            (snap?.truncated == true || _storeError) ? 12 : 0,
                            4,
                            0,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HistoryGroup {
  final String date;
  final String source;
  final List<GlucoseReading> rows;
  const _HistoryGroup({
    required this.date,
    required this.source,
    required this.rows,
  });
}

List<_HistoryGroup> _groups(
  GlucoseSnapshot snap,
  TargetPlatform platform,
  DateTime? now,
) {
  final out = <_HistoryGroup>[];
  String? current;
  final rows = <GlucoseReading>[];
  void flush() {
    final day = current;
    if (day == null || rows.isEmpty) return;
    final date = _glucoseObDate(day, now);
    out.add(
      _HistoryGroup(
        date: date,
        source: glucoseSourceLine(snap.selected, platform: platform),
        rows: List.of(rows),
      ),
    );
    rows.clear();
  }

  for (final r in snap.history) {
    final day = dayLabelOf(r.measuredAt);
    if (current != day) {
      flush();
      current = day;
    }
    rows.add(r);
  }
  flush();
  return out;
}

class _GlucoseHero extends StatelessWidget {
  final GlucoseSnapshot snap;
  final DateTime? now;
  const _GlucoseHero({required this.snap, this.now});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final latest = snap.history.isEmpty ? null : snap.history.first;
    final excluded = snap.selectedExcluded;
    final missing = latest == null;
    final date = missing
        ? 'Letzte Messung'
        : _glucoseCalendarDate(latest.measuredAt, now);
    final time = missing ? '' : obTime(_glucoseLocal(latest.measuredAt));
    final value = excluded || missing ? '—' : glucoseValueLabel(latest);
    final unit = latest == null ? null : glucoseUnitLabel(latest.rawUnit);
    final note = excluded
        ? null
        : (_partial(snap) ? 'Teilweise lesbar' : null);
    return OBCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    date,
                    style: p
                        .text(14, weight: FontWeight.w500, color: p.muted)
                        .copyWith(height: 20 / 14),
                  ),
                ),
                if (time.isNotEmpty)
                  Text(
                    time,
                    style: p
                        .text(14, color: p.muted)
                        .copyWith(height: 20 / 14),
                  ),
              ],
            ),
          ),
          _GlucoseHeroValue(value: value, unit: unit, missing: missing),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 24),
            child: Row(
              children: [
                Icon(LucideIcons.droplet, size: 16, color: p.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    glucoseSourceLine(
                      snap.selected,
                      platform: Theme.of(context).platform,
                      excluded: excluded,
                    ),
                    style: p
                        .text(13, color: p.muted)
                        .copyWith(height: 18 / 13),
                  ),
                ),
              ],
            ),
          ),
          if (note != null)
            Text(
              note,
              style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
            ),
        ],
      ),
    );
  }
}

class _GlucoseHeroValue extends StatelessWidget {
  final String value;
  final String? unit;
  final bool missing;
  const _GlucoseHeroValue({
    required this.value,
    required this.unit,
    required this.missing,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final unitText = unit != null && unit!.isNotEmpty && !missing ? unit : null;
    final valueStyle = p
        .text(48, weight: FontWeight.w800, display: true)
        .copyWith(
          height: 52 / 48,
          letterSpacing: -0.025 * 48,
        );
    final compactStyle = p
        .text(32, weight: FontWeight.w800, display: true)
        .copyWith(
          height: 36 / 32,
          letterSpacing: -0.025 * 32,
        );
    final unitStyle = p.text(15, color: p.muted).copyWith(height: 20 / 15);
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(value, style: valueStyle),
        if (unitText != null) ...[
          const SizedBox(width: 8),
          Text(unitText, style: unitStyle),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth) return row;
        final scaler = MediaQuery.textScalerOf(context);
        final dir = Directionality.of(context);
        final valueWidth = _glucoseTextWidth(value, valueStyle, scaler, dir);
        final unitWidth = unitText == null
            ? 0.0
            : _glucoseTextWidth(unitText, unitStyle, scaler, dir);
        final rowWidth =
            valueWidth + (unitText == null ? 0.0 : 8 + unitWidth);
        if (rowWidth <= constraints.maxWidth) return row;
        final valueStyleUsed =
            valueWidth > constraints.maxWidth ? compactStyle : valueStyle;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: Text(
                value,
                style: valueStyleUsed,
                softWrap: true,
              ),
            ),
            if (unitText != null)
              SizedBox(
                width: double.infinity,
                child: Text(
                  unitText,
                  style: unitStyle,
                  softWrap: true,
                ),
              ),
          ],
        );
      },
    );
  }
}

double _glucoseTextWidth(
  String text,
  TextStyle style,
  TextScaler scaler,
  TextDirection dir,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: dir,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

class _GlucoseGroup extends StatelessWidget {
  final List<Widget> children;
  const _GlucoseGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return OBCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: p.line,
                indent: 14,
                endIndent: 14,
              ),
            child,
          ],
        ],
      ),
    );
  }
}

class _GlucoseSyntheticNote extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  const _GlucoseSyntheticNote({
    this.padding = const EdgeInsets.fromLTRB(4, 12, 4, 0),
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Padding(
      padding: padding,
      child: Text(
        key: const ValueKey('glucose-synthetic'),
        'Synthetische Daten',
        style: p.text(12, color: p.muted).copyWith(height: 18 / 12),
      ),
    );
  }
}

bool _partial(GlucoseSnapshot snap) =>
    snap.attempt.status == HealthMeasurementImportStatus.partial ||
    snap.unreadableCount > 0;

bool _attemptFailed(HealthMeasurementImportStatus status) =>
    status == HealthMeasurementImportStatus.authorizationDenied ||
    status == HealthMeasurementImportStatus.authorizationRequestFailed ||
    status == HealthMeasurementImportStatus.readFailed ||
    status == HealthMeasurementImportStatus.persistenceFailed;

bool _snapshotForKey(GlucoseSnapshot snap, String? key) {
  if (key == null) return true;
  return snap.selected?.key == key;
}

String _statusCopy(HealthMeasurementImportStatus? status) => switch (status) {
  HealthMeasurementImportStatus.authorizationDenied => 'Kein Zugriff',
  HealthMeasurementImportStatus.authorizationRequestFailed =>
    'Freigabe fehlgeschlagen',
  HealthMeasurementImportStatus.persistenceFailed => 'Speichern fehlgeschlagen',
  _ => 'Lesen fehlgeschlagen',
};

bool _showChart(GlucoseSnapshot snap) {
  if (snap.selectedExcluded) return false;
  return glucosePlotReadings(snap).isNotEmpty;
}

String _chartUnit(GlucoseSnapshot snap) {
  for (final r in snap.series) {
    if (r.plottable) return glucoseUnitLabel(r.rawUnit);
  }
  return '';
}

int _readingCount(GlucoseSnapshot snap) {
  final key = snap.selected?.key;
  if (key != null) {
    for (final s in snap.sources) {
      if (s.source.key == key) return s.readingCount;
    }
  }
  return snap.history.length;
}

String _sourceInfo(
  GlucoseSourceIdentity? source,
  GlucoseSnapshot? snap,
  TargetPlatform platform,
) {
  var body = glucoseInfoBody(platform);
  final bits = <String>[
    if (source != null && source.legacy && source.sourceName.trim().isNotEmpty)
      source.sourceName.trim(),
    if (source != null &&
        source.unknownIdentity &&
        source.sourceName.trim().isNotEmpty)
      source.sourceName.trim(),
    if (source?.sourceId != null && source!.sourceId!.trim().isNotEmpty)
      source.sourceId!.trim(),
    if (snap != null && _partial(snap)) ...[
      if (snap.unreadableCount > 0) '${snap.unreadableCount} unlesbar',
      if (snap.attempt.invalidCount > 0) '${snap.attempt.invalidCount} ungültig',
      if (snap.attempt.ignoredCount > 0) '${snap.attempt.ignoredCount} ignoriert',
    ],
  ];
  if (bits.isNotEmpty) body = '$body\n${bits.join(' · ')}';
  return body;
}

String? _legacyIdentity(GlucoseSourceIdentity source) {
  if (!source.unknownIdentity && !source.legacy) return null;
  final name = source.sourceName.trim();
  if (name.isEmpty) return null;
  if (name.toLowerCase() == 'unknown app') return null;
  return name;
}
