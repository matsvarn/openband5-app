import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/day_label.dart';
import 'controller.dart';
import 'domain.dart';
import 'health.dart' show OBSegmented;
import 'scale.dart';
import 'journal_controls.dart';
import 'calendar_line.dart';
import 'night_signals.dart';
import 'screens.dart'
    show
        obMetricComparisonStatus,
        obTemperatureNumber,
        obVerdictMark,
        obVerdictText;
import 'settings_controls.dart';
import 'sleep_editor.dart';
import 'theme.dart';
import 'time.dart';

typedef OpenBandNightScalarRead =
    Future<NightScalarDetail> Function(
      OpenBandRepository repository,
      MetricKey key,
      String day,
      int nights,
    );

enum _BaselineTone { none, untrusted, provisional, stale, trusted }

_BaselineTone _baselineTone(StoredNightBaseline? baseline) {
  if (baseline?.value == null) return _BaselineTone.none;
  return switch ((baseline!.status ?? '').trim().toLowerCase()) {
    'trusted' => _BaselineTone.trusted,
    'provisional' => _BaselineTone.provisional,
    'stale' => _BaselineTone.stale,
    _ => _BaselineTone.untrusted,
  };
}

bool _comparisonValid(NightScalarDetail detail) {
  if (detail.withheld) return false;
  if (detail.value == null || detail.baseline?.value == null) return false;
  switch (detail.state) {
    case NightScalarState.current:
      break;
    case NightScalarState.partial:
    case NightScalarState.older:
    case NightScalarState.pending:
    case NightScalarState.failed:
    case NightScalarState.missing:
    case NightScalarState.unreadable:
    case NightScalarState.unknown:
    case NightScalarState.outdated:
      return false;
  }
  return _baselineTone(detail.baseline) == _BaselineTone.trusted;
}

String? _sleepOriginLabel(String? source) {
  final value = source?.trim().toLowerCase();
  if (value == null || value.isEmpty) return null;
  return switch (value) {
    'auto' || 'auto_fallback' => 'Schlaf automatisch',
    'manual' => 'Schlaf manuell',
    'confirmed' => 'Schlaf bestätigt',
    _ => null,
  };
}

String? _deviceFamilyLabel(String? family) {
  final value = family?.trim().toLowerCase();
  if (value == null || value.isEmpty) return null;
  return switch (value) {
    'gen5' || 'whoop5' || 'whoop 5' || 'whoop 5.0' => 'WHOOP 5.0',
    'gen4' || 'whoop4' || 'whoop 4' || 'whoop 4.0' => 'WHOOP 4.0',
    _ => null,
  };
}

String? _baselineStatusLabel(String? status) {
  final value = status?.trim().toLowerCase();
  if (value == null || value.isEmpty) return null;
  return switch (value) {
    'trusted' => 'Verlässlich',
    'provisional' => 'vorläufig',
    'stale' => 'veraltet',
    'calibrating' => 'Kalibrierung',
    _ => null,
  };
}

class OpenBandNightScalarDetail extends StatefulWidget {
  final OpenBandController controller;
  final MetricKey metricKey;
  final String label;
  final String unit;
  final IconData icon;
  final Color Function(OB) color;
  final Color Function(OB) tint;
  final OpenBandNightScalarRead? read;
  final int digits;
  final String? backText;

  const OpenBandNightScalarDetail({
    super.key,
    required this.controller,
    required this.metricKey,
    required this.label,
    required this.unit,
    required this.icon,
    required this.color,
    required this.tint,
    this.read,
    this.digits = 0,
    this.backText,
  }) : assert(digits >= 0);

  @override
  State<OpenBandNightScalarDetail> createState() =>
      _OpenBandNightScalarDetailState();
}

class _OpenBandNightScalarDetailState extends State<OpenBandNightScalarDetail> {
  static const _nightOptions = [7, 30, 90];
  int _nights = 30;
  int _gen = 0;
  NightScalarDetail? _snapshot;
  OpenBandRepository? _loadedRepo;
  OpenBandController? _loadedController;
  OpenBandNightScalarRead? _loadedRead;
  bool _loading = true;
  bool _error = false;
  String? _heardDay;
  bool _heardCalculating = false;
  bool _heardNapCalculating = false;
  bool _heardLoading = false;
  OpenBandDay? _heardDayData;
  Object? _heardLoadError;

  OpenBandRepository get _repo => widget.controller.repository;

  @override
  void initState() {
    super.initState();
    _syncHeard();
    widget.controller.addListener(_onController);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(OpenBandNightScalarDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onController);
      _syncHeard();
      widget.controller.addListener(_onController);
    }
    if (!identical(oldWidget.controller, widget.controller) ||
        !identical(
          oldWidget.controller.repository,
          widget.controller.repository,
        ) ||
        oldWidget.metricKey != widget.metricKey ||
        oldWidget.read != widget.read) {
      _invalidateVisibleSnapshot();
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _gen++;
    super.dispose();
  }

  void _syncHeard() {
    final controller = widget.controller;
    _heardDay = controller.selectedDay;
    _heardCalculating = controller.calculating;
    _heardNapCalculating = controller.napCalculating;
    _heardLoading = controller.loading;
    _heardDayData = controller.day;
    _heardLoadError = controller.loadError;
  }

  void _onController() {
    final controller = widget.controller;
    final dayChanged = controller.selectedDay != _heardDay;
    final loadingStarted = !_heardLoading && controller.loading;
    final refreshSettled = _heardLoading && !controller.loading;
    final calculationStarted =
        (!_heardCalculating && controller.calculating) ||
        (!_heardNapCalculating && controller.napCalculating);
    final calculationSettled =
        (_heardCalculating && !controller.calculating) ||
        (_heardNapCalculating && !controller.napCalculating);
    final dayDataChanged =
        !identical(controller.day, _heardDayData) ||
        !identical(controller.loadError, _heardLoadError);
    _syncHeard();

    // A controller refresh or calculation invalidates the visible snapshot at
    // once. Wait for the controller read to settle before issuing our typed
    // read, so an old hero/history can never masquerade as the new result.
    if (dayChanged || loadingStarted || calculationStarted) {
      _invalidateVisibleSnapshot();
    }
    if (controller.loading ||
        controller.calculating ||
        controller.napCalculating) {
      return;
    }
    if (dayChanged || refreshSettled || calculationSettled || dayDataChanged) {
      unawaited(_load());
    }
  }

  void _invalidateVisibleSnapshot() {
    _gen++;
    if (!mounted) return;
    setState(() {
      _snapshot = null;
      _loadedRepo = null;
      _loadedController = null;
      _loadedRead = null;
      _loading = true;
      _error = false;
    });
  }

  bool _same(
    int gen,
    OpenBandRepository repo,
    MetricKey key,
    String day,
    int nights,
  ) =>
      mounted &&
      gen == _gen &&
      identical(repo, _repo) &&
      widget.metricKey == key &&
      widget.controller.selectedDay == day &&
      _nights == nights;

  Future<void> _load() async {
    final gen = ++_gen;
    final repo = _repo;
    final key = widget.metricKey;
    final day = widget.controller.selectedDay;
    final nights = _nights;
    final identityChanged =
        _snapshot != null &&
        (_snapshot!.day != day ||
            _snapshot!.nights != nights ||
            _snapshot!.key != nightScalarMetricOf(key) ||
            !identical(_loadedRepo, repo) ||
            !identical(_loadedController, widget.controller) ||
            _loadedRead != widget.read);
    if (identityChanged || _snapshot == null) {
      if (mounted) {
        setState(() {
          if (identityChanged) {
            _snapshot = null;
            _loadedRepo = null;
            _loadedController = null;
            _loadedRead = null;
          }
          _loading = true;
          _error = false;
        });
      }
    } else if (mounted) {
      setState(() => _loading = true);
    }
    try {
      final read =
          widget.read ??
          (repository, k, d, n) => repository.readNightScalarDetail(k, d, n);
      final snap = await read(repo, key, day, nights);
      if (!_same(gen, repo, key, day, nights)) return;
      setState(() {
        _snapshot = snap;
        _loadedRepo = repo;
        _loadedController = widget.controller;
        _loadedRead = widget.read;
        _loading = false;
        _error = false;
      });
    } catch (_) {
      if (!_same(gen, repo, key, day, nights)) return;
      setState(() {
        _snapshot = null;
        _loadedRepo = null;
        _loadedController = null;
        _loadedRead = null;
        _loading = false;
        _error = true;
      });
    }
  }

  bool get _temperature => widget.metricKey == MetricKey.skinTemperature;

  String get _storedKindLabel => switch (widget.metricKey) {
    MetricKey.hrv => 'RMSSD',
    MetricKey.restingHr => 'Ruhepuls',
    MetricKey.respiration => 'Atemfrequenz',
    MetricKey.skinTemperature => 'Hauttemperatur',
    MetricKey.recovery ||
    MetricKey.sleepDuration ||
    MetricKey.strain => widget.label,
  };

  NightSignalKind get _overnightKind => switch (widget.metricKey) {
    MetricKey.hrv => NightSignalKind.hrv,
    MetricKey.restingHr => NightSignalKind.pulse,
    MetricKey.respiration => NightSignalKind.respiration,
    MetricKey.skinTemperature ||
    MetricKey.recovery ||
    MetricKey.sleepDuration ||
    MetricKey.strain => throw StateError(
      'Night scalar overnight is HRV, resting pulse, or respiration only.',
    ),
  };

  bool get _calcOverlay =>
      _loading &&
      (widget.controller.calculating || widget.controller.napCalculating);

  String _heroStatus(NightScalarDetail snap) {
    if (_temperature) {
      switch (snap.state) {
        case NightScalarState.pending:
          return kNightScalarPendingLabel;
        case NightScalarState.failed:
          return kNightScalarFailedLabel;
        case NightScalarState.unknown:
        case NightScalarState.outdated:
          return kNightScalarOpenLabel;
        case NightScalarState.missing:
          return 'Noch kein Nachtwert';
        case NightScalarState.unreadable:
          return 'Nachtwert nicht lesbar';
        case NightScalarState.partial:
          return 'Unvollständige Nacht';
        case NightScalarState.older:
          return 'Ältere Berechnung';
        case NightScalarState.current:
          return switch (snap.unit) {
            NightScalarUnit.sd => 'Relative Abweichung',
            NightScalarUnit.celsius => 'Importiert',
            NightScalarUnit.unknown => kNightScalarUnknownUnitLabel,
            null =>
              snap.value == null
                  ? 'Noch kein Nachtwert'
                  : kNightScalarUnknownUnitLabel,
          };
      }
    }
    switch (snap.state) {
      case NightScalarState.pending:
        return kNightScalarPendingLabel;
      case NightScalarState.failed:
        return 'Auswertung fehlgeschlagen';
      case NightScalarState.unknown:
      case NightScalarState.outdated:
        return kNightScalarOpenLabel;
      case NightScalarState.missing:
        return 'Noch kein Nachtwert';
      case NightScalarState.unreadable:
        return 'Nachtwert nicht lesbar';
      case NightScalarState.partial:
        return 'Unvollständige Nacht';
      case NightScalarState.older:
        return 'Ältere Berechnung';
      case NightScalarState.current:
        switch (_baselineTone(snap.baseline)) {
          case _BaselineTone.trusted:
            return obMetricComparisonStatus(
              snap.value!,
              snap.baseline!.value!,
              digits: widget.digits,
            );
          case _BaselineTone.provisional:
            return 'Vorläufige Basis';
          case _BaselineTone.stale:
            return 'Basis veraltet';
          case _BaselineTone.none:
          case _BaselineTone.untrusted:
            return 'Basis noch offen';
        }
    }
  }

  String _nightLabel() {
    final selected = widget.controller.selectedDay;
    if (_temperature) return obDayTitle(selected);
    final today = dayLabelOf(widget.controller.now());
    return selected == today ? 'Nacht auf heute' : obDayTitle(selected);
  }

  String _windowValue(NightScalarDetail? snap) {
    if (snap == null || snap.withheld || snap.window == null) {
      return '—';
    }
    final start = recordedTime(snap.window!.start, snap.recordingTimezone);
    final end = recordedTime(snap.window!.end, snap.recordingTimezone);
    return '${obTime(start)}–${obTime(end)}';
  }

  String _baselineValue(NightScalarDetail? snap) {
    if (snap == null || snap.withheld || snap.baseline?.value == null) {
      return '—';
    }
    return '${_metricNumber(snap.baseline!.value)} ${widget.unit}';
  }

  Future<void> _info({required bool baselineOnly}) async {
    final gen = _gen;
    final repo = _repo;
    final key = widget.metricKey;
    final day = widget.controller.selectedDay;
    final nights = _nights;
    final snap = _snapshot;
    final withheld = snap != null && snap.withheld;
    final title = baselineOnly
        ? 'Persönliche Basis'
        : withheld
        ? 'Auswertung'
        : 'Über ${widget.label}';
    final result = await showOpenBandJournalInfo(
      context,
      title: title,
      body: '',
      paragraphs: baselineOnly
          ? _baselineParagraphs(snap)
          : _headerParagraphs(snap),
      primaryAction: !baselineOnly && withheld
          ? const OBInfoSheetAction(id: 'sleep', label: 'Schlaf ansehen')
          : null,
    );
    if (result == null || !_same(gen, repo, key, day, nights)) return;
    if (result == 'sleep' && mounted) await _openCorrection();
  }

  List<String> _headerParagraphs(NightScalarDetail? snap) {
    if (_error) return ['Nachtwerte konnten nicht geladen werden.'];
    if (snap == null) return ['Die Nachtwerte werden geladen.'];
    if (_temperature) return _temperatureParagraphs(snap);
    if (snap.withheld) return _withheldParagraphs(snap);
    final first = <String>[
      '$_storedKindLabel · gespeicherter Wert',
      if (_windowInfo(snap) != null) _windowInfo(snap)!,
      if (snap.partial || snap.state == NightScalarState.partial)
        'Unvollständige Nacht.',
      if (snap.olderCalculation || snap.state == NightScalarState.older)
        'Ältere Berechnung.',
      if (snap.state == NightScalarState.missing) 'Noch kein Nachtwert.',
      if (snap.state == NightScalarState.unreadable) 'Nachtwert nicht lesbar.',
    ];
    final second = <String>[
      if (_sourceInfo(snap) != null) _sourceInfo(snap)!,
      if (_envelopeInfo(snap) != null) _envelopeInfo(snap)!,
      if (snap.computedAt != null)
        'Berechnet am ${DateFormat('d. MMMM, HH:mm', 'de_DE').format(snap.computedAt!.toLocal())}',
      if (snap.algoVersion != null) 'Algorithmus ${snap.algoVersion}',
    ];
    final third = <String>[];
    if (snap.baseline?.value != null) {
      final n = snap.baseline!.nValid;
      third.add(
        [
          'Basis ${_metricNumber(snap.baseline!.value)} ${widget.unit}',
          if (n != null) '$n gültige Nächte',
        ].join(' · '),
      );
      final status = _baselineStatusLabel(snap.baseline!.status);
      if (status != null) third.add('Status: $status');
    }
    final imports = _importInfo(snap);
    if (imports != null) third.add(imports);
    return [
      first.join('\n'),
      if (second.isNotEmpty) second.join('\n'),
      if (third.isNotEmpty) third.join('\n'),
    ];
  }

  List<String> _temperatureParagraphs(NightScalarDetail snap) {
    String raw(double value, NightScalarUnit? unit) {
      final number = obNumber(value, digits: 1);
      return switch (unit) {
        NightScalarUnit.sd => '$number SD',
        NightScalarUnit.celsius => '$number °C',
        NightScalarUnit.unknown || null => number,
      };
    }

    final stored = snap.storedForInfo ?? snap.value;
    final first = snap.withheld
        ? [
            _heroStatus(snap),
            if (stored != null) 'Gespeicherter Wert: ${raw(stored, snap.unit)}',
          ].join('\n')
        : switch (snap.unit) {
            NightScalarUnit.sd =>
              'Relative Abweichung in Standardabweichungen (SD), keine Temperatur in °C.',
            NightScalarUnit.celsius =>
              'Hauttemperatur in °C · importierter Wert',
            NightScalarUnit.unknown =>
              stored == null
                  ? 'Die Einheit ist nicht belegt.'
                  : 'Gespeicherter Wert: ${raw(stored, null)}\nDie Einheit ist nicht belegt.',
            null =>
              snap.state == NightScalarState.missing
                  ? 'Noch kein Nachtwert.'
                  : 'Die Einheit ist nicht belegt.',
          };
    final sources = _temperatureSourceInfo(snap);
    final family = _deviceFamilyLabel(snap.deviceFamily);
    final provenance = [?sources, ?family].join(' · ');
    final metadata = <String>[
      if (provenance.isNotEmpty) provenance,
      if (snap.computedAt != null)
        'Berechnet am ${DateFormat('d. MMMM, HH:mm', 'de_DE').format(snap.computedAt!.toLocal())}',
      if (snap.algoVersion != null) 'Algorithmus ${snap.algoVersion}',
    ];
    final exclusions = <String>[];
    if (snap.unit != NightScalarUnit.unknown && snap.counts.excludedUnit > 0) {
      exclusions.add(
        '${snap.counts.excludedUnit} ${snap.counts.excludedUnit == 1 ? 'Nacht' : 'Nächte'} mit anderer oder unbekannter Einheit ausgeschlossen.',
      );
      final conflicts = <String>{};
      for (final night in snap.history) {
        final result = night.resultSource?.trim();
        final payload = night.payloadSource?.trim();
        if (result != null &&
            result.isNotEmpty &&
            payload != null &&
            payload.isNotEmpty &&
            result != payload) {
          conflicts.add('${_sourceLabel(result)} / ${_sourceLabel(payload)}');
        }
      }
      if (conflicts.isNotEmpty) {
        exclusions.add('Quellenkonflikt: ${conflicts.join(', ')}');
      }
    }
    final otherExcluded =
        snap.counts.excludedVersion +
        snap.counts.excludedSkipped +
        snap.counts.excludedUnversioned +
        snap.counts.unreadable;
    if (otherExcluded > 0) {
      exclusions.add(
        '$otherExcluded ${otherExcluded == 1 ? 'Nacht' : 'Nächte'} wegen unvollständiger oder nicht vergleichbarer Daten ausgeschlossen.',
      );
    }
    return [
      first,
      if (metadata.isNotEmpty) metadata.join('\n'),
      if (exclusions.isNotEmpty) exclusions.join('\n'),
    ];
  }

  String? _temperatureSourceInfo(NightScalarDetail snap) {
    final result = snap.resultSource?.trim();
    final payload = snap.payloadSource?.trim();
    final hasResult = result != null && result.isNotEmpty;
    final hasPayload = payload != null && payload.isNotEmpty;
    if (!hasResult && !hasPayload) return null;
    if (hasResult && hasPayload && result != payload) {
      return 'Quellen: ${_sourceLabel(result)} / ${_sourceLabel(payload)}';
    }
    return _sourceLabel(hasResult ? result : payload!);
  }

  String _temperatureSourceValue(NightScalarDetail? snap) {
    if (snap == null) return '—';
    final result = snap.resultSource?.trim();
    final payload = snap.payloadSource?.trim();
    if (result != null &&
        result.isNotEmpty &&
        payload != null &&
        payload.isNotEmpty &&
        result != payload) {
      return 'Uneindeutig';
    }
    final source = result?.isNotEmpty == true ? result : payload;
    return source == null || source.isEmpty ? '—' : _sourceLabel(source);
  }

  List<String> _withheldParagraphs(NightScalarDetail snap) {
    final status = switch (snap.state) {
      NightScalarState.pending => 'Auswertung läuft.',
      NightScalarState.failed => 'Auswertung fehlgeschlagen.',
      NightScalarState.unknown ||
      NightScalarState.outdated => 'Auswertung offen.',
      NightScalarState.current ||
      NightScalarState.older ||
      NightScalarState.partial ||
      NightScalarState.missing ||
      NightScalarState.unreadable => 'Auswertung offen.',
    };
    final stored = snap.storedForInfo;
    final first = stored == null
        ? status
        : '$status\nZuletzt gespeichert: ${_metricNumber(stored)} ${widget.unit}';
    final meta = <String>[
      if (_windowInfo(snap) != null) _windowInfo(snap)!,
      if (_sourceInfo(snap) != null) _sourceInfo(snap)!,
      if (_envelopeInfo(snap) != null) _envelopeInfo(snap)!,
      if (snap.computedAt != null)
        'Berechnet am ${DateFormat('d. MMMM, HH:mm', 'de_DE').format(snap.computedAt!.toLocal())}',
      if (snap.algoVersion != null) 'Algorithmus ${snap.algoVersion}',
    ];
    final previousBaseline = <String>[
      if (snap.baseline?.value != null)
        'Vorherige Basis ${_metricNumber(snap.baseline!.value)} ${widget.unit}',
      if (snap.baseline?.nValid != null)
        '${snap.baseline!.nValid} gültige Nächte',
      if (_baselineStatusLabel(snap.baseline?.status) case final status?)
        'Vorheriger Status: $status',
    ];
    return [
      first,
      if (meta.isNotEmpty) meta.join('\n'),
      if (previousBaseline.isNotEmpty) previousBaseline.join('\n'),
    ];
  }

  List<String> _baselineParagraphs(NightScalarDetail? snap) {
    final baseline = snap?.baseline;
    if (baseline?.value == null) return ['Basis noch offen.'];
    final lines = <String>[
      '${snap!.withheld ? 'Vorherige Basis' : 'Basis'} ${_metricNumber(baseline!.value)} ${widget.unit}',
      if (baseline.nValid != null) '${baseline.nValid} gültige Nächte',
    ];
    final status = _baselineStatusLabel(baseline.status);
    if (status != null) {
      lines.add('${snap.withheld ? 'Vorheriger Status' : 'Status'}: $status');
    }
    return [lines.join('\n')];
  }

  String? _windowInfo(NightScalarDetail snap) {
    final window = snap.window;
    if (window == null) return null;
    final start = recordedTime(window.start, snap.recordingTimezone);
    final end = recordedTime(window.end, snap.recordingTimezone);
    final sameMonth = start.month == end.month && start.year == end.year;
    final range = sameMonth
        ? '${DateFormat('d.', 'de_DE').format(start)}–${DateFormat('d. MMMM', 'de_DE').format(end)}'
        : '${DateFormat('d. MMMM', 'de_DE').format(start)} – ${DateFormat('d. MMMM', 'de_DE').format(end)}';
    return '$range · ${obTime(start)}–${obTime(end)}';
  }

  String _sourceLabel(String source) {
    return switch (source.trim().toLowerCase()) {
      'band' => 'Band',
      'whoop_export' || 'whoop-export' => 'WHOOP-Export',
      'cloud_v2' || 'cloud' => 'Cloud-Import',
      'apple_health' || 'healthkit' => 'Apple Health',
      'health_connect' => 'Health Connect',
      'manual' => 'Manueller Import',
      _ => 'Import',
    };
  }

  String? _sourceInfo(NightScalarDetail snap) {
    final sleep = _sleepOriginLabel(snap.sleepSource);
    final family = _deviceFamilyLabel(snap.deviceFamily);
    final vendor = snap.vendorSource?.trim();
    final parts = <String>[
      ?sleep,
      if (vendor != null && vendor.isNotEmpty) _sourceLabel(vendor),
      ?family,
    ];
    return parts.isEmpty ? null : parts.toSet().join(' · ');
  }

  String? _envelopeInfo(NightScalarDetail snap) {
    final envelope = snap.envelope;
    if (envelope == null || envelope.isEmpty) return null;
    final parts = <String>[];
    final tier = envelope.tier?.trim();
    if (tier != null && tier.isNotEmpty) parts.add('Stufe $tier');
    final confidence = envelope.confidence;
    if (confidence != null && confidence.isFinite) {
      parts.add('Qualitätswert ${_metadataNumber(confidence)} / 1');
    }
    final inputs = envelope.inputsUsed;
    if (inputs != null && inputs.isNotEmpty) {
      parts.add('Eingaben ${inputs.join(', ')}');
    }
    final note = envelope.note?.trim();
    if (note != null && note.isNotEmpty) parts.add('Hinweis: $note');
    final brpm = envelope.brpm;
    if (brpm != null && brpm.isFinite) {
      parts.add('RSA-Atemfrequenz ${_metricNumber(brpm)} ${widget.unit}');
    }
    final peakHz = envelope.peakHz;
    if (peakHz != null && peakHz.isFinite) {
      parts.add('Spektralspitze ${_metadataNumber(peakHz)} Hz');
    }
    final power = envelope.power;
    if (power != null && power.isFinite) {
      parts.add('Spektralleistung ${_metadataNumber(power)}');
    }
    final source = envelope.source?.trim();
    if (source != null && source.isNotEmpty) parts.add('Methode $source');
    return parts.isEmpty ? null : parts.join('\n');
  }

  String _metricNumber(double? value) => obNumber(value, digits: widget.digits);

  String _metadataNumber(double value) {
    var formatted = obNumber(value, digits: 3);
    while (formatted.contains(',') && formatted.endsWith('0')) {
      formatted = formatted.substring(0, formatted.length - 1);
    }
    if (formatted.endsWith(',')) {
      formatted = formatted.substring(0, formatted.length - 1);
    }
    return formatted;
  }

  String? _importInfo(NightScalarDetail snap) {
    if (snap.counts.imported <= 0 && snap.counts.sources.isEmpty) return null;
    final parts = <String>[];
    if (snap.counts.imported > 0) {
      parts.add('${snap.counts.imported} importiert');
    }
    if (snap.counts.sources.isNotEmpty) {
      final displayCounts = <String, int>{};
      for (final source in snap.counts.sources.entries) {
        final label = _sourceLabel(source.key);
        displayCounts[label] = (displayCounts[label] ?? 0) + source.value;
      }
      parts.add(
        displayCounts.entries.map((e) => '${e.key} ${e.value}').join(', '),
      );
    }
    return parts.join(' · ');
  }

  Future<void> _openCorrection() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SleepEditor(controller: widget.controller),
      ),
    );
  }

  void _openNight() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => OpenBandNightSignals(
          repository: widget.controller.repository,
          day: widget.controller.selectedDay,
          initial: _overnightKind,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    // G2: night values are ink; only Erholung carries the signal colour.
    final color = p.ink;
    final snap = _snapshot;
    return Scaffold(
      key: const ValueKey('night-scalar-detail'),
      backgroundColor: p.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OBPageHeader(
                title: widget.label,
                backText: widget.backText,
                subtitle: '',
                onInfo: () => _info(baselineOnly: false),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  if (_error)
                    OBSettingsErrorCard(
                      message: 'Nachtwerte konnten nicht geladen werden.',
                      retryLabel: 'Erneut',
                      onRetry: () => unawaited(_load()),
                    )
                  else ...[
                    _hero(p, color, snap),
                    if (!_temperature ||
                        snap?.hasComparableQuantity == true) ...[
                      const SizedBox(height: 12),
                      OBSegmented(
                        labels: const ['7 Nächte', '30 Nächte', '90 Nächte'],
                        selected: _nightOptions.indexOf(_nights),
                        onChanged: (i) {
                          setState(() => _nights = _nightOptions[i]);
                          unawaited(_load());
                        },
                      ),
                      const SizedBox(height: 12),
                      _chartCard(p, color, snap),
                    ],
                    const SizedBox(height: 12),
                    _rows(p, snap),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero(OB p, Color color, NightScalarDetail? snap) {
    final overlay = _calcOverlay;
    final value = overlay ? null : snap?.value;
    final status = overlay
        ? kNightScalarPendingLabel
        : snap == null
        ? ''
        : _heroStatus(snap);
    final compared = !overlay && snap != null && _comparisonValid(snap);
    final verdict = compared ? _verdict(snap) : null;
    final scale = _heroScale(snap, value, mark: obVerdictMark(p, verdict));
    return OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_nightLabel().toUpperCase(), style: p.label()),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _temperature
                    ? obTemperatureNumber(value, snap?.unit)
                    : _metricNumber(value),
                style: p
                    .text(
                      56,
                      weight: FontWeight.w700,
                      display: true,
                      color: value == null ? p.gap : p.ink,
                    )
                    .copyWith(height: 58 / 56),
              ),
              const SizedBox(width: 4),
              Visibility(
                visible: value != null,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: Text(
                  _temperature
                      ? switch (snap?.unit) {
                          NightScalarUnit.sd => 'SD',
                          NightScalarUnit.celsius => '°C',
                          NightScalarUnit.unknown || null => '',
                        }
                      : widget.unit,
                  style: p
                      .text(14, weight: FontWeight.w500, color: p.muted)
                      .copyWith(height: 18 / 14),
                ),
              ),
            ],
          ),
          if (status.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              status,
              style: p
                  .text(
                    13,
                    weight: compared && verdict != MetricVerdict.normal
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: compared
                        ? obVerdictText(p, verdict) ?? p.ink
                        : p.muted,
                  )
                  .copyWith(height: 18 / 13),
            ),
          ],
          if (scale != null) ...[const SizedBox(height: 10), scale],
        ],
      ),
    );
  }

  /// The value on a scale spanning the observed nights. No range is
  /// assumed: with fewer than three stored nights there is no scale.
  MetricVerdict? _verdict(NightScalarDetail snap) => metricVerdict(
    widget.metricKey,
    snap.value,
    snap.baseline?.value,
    snap.baseline?.spread,
  );

  Widget? _heroScale(NightScalarDetail? snap, double? value, {Color? mark}) {
    if (snap == null || value == null || _temperature) return null;
    final seen = [
      for (final n in snap.history)
        if (n.value != null) n.value!,
    ];
    if (seen.length < 3) return null;
    final tone = _baselineTone(snap.baseline);
    final base =
        !snap.withheld &&
            (tone == _BaselineTone.trusted ||
                tone == _BaselineTone.provisional ||
                tone == _BaselineTone.stale)
        ? snap.baseline?.value
        : null;
    final all = [...seen, value, ?base];
    final lo = all.reduce(math.min), hi = all.reduce(math.max);
    final pad = math.max((hi - lo) * .15, 1.0);
    final min = (lo - pad).floorToDouble(), max = (hi + pad).ceilToDouble();
    String n(double v) => obNumber(v, digits: widget.digits);
    return OBScale(
      min: min,
      max: max,
      value: value,
      target: base,
      mark: mark,
      labels: (
        n(min),
        base == null ? '${seen.length} Nächte' : 'Basis ${n(base)}',
        n(max),
      ),
    );
  }

  Widget _chartCard(OB p, Color color, NightScalarDetail? snap) {
    final loaded = snap != null && !_loading;
    final partialBars = loaded
        ? snap.history
              .where((night) => night.partial && night.value != null)
              .length
        : 0;
    final count = !loaded
        ? ''
        : partialBars > 0
        ? '${snap.counts.compared} von ${snap.nights} · teils unvollständig'
        : '${snap.counts.compared} von ${snap.nights} Nächten';
    final days = openBandDaysEnding(widget.controller.selectedDay, _nights);
    final wrap = MediaQuery.textScalerOf(context).scale(15) > 20;
    final withheld = snap != null && snap.withheld;
    final showChart = loaded && snap.history.any((b) => b.value != null);
    final tone = _baselineTone(snap?.baseline);
    final showBaseline =
        loaded &&
        !withheld &&
        snap.baseline?.value != null &&
        (tone == _BaselineTone.trusted ||
            tone == _BaselineTone.provisional ||
            tone == _BaselineTone.stale);
    final titleStyle = p
        .text(13, weight: FontWeight.w600, color: p.muted)
        .copyWith(height: 18 / 13);
    final countStyle = p
        .text(13, weight: FontWeight.w500, color: p.muted)
        .copyWith(height: 18 / 13);
    return OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          wrap
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nacht für Nacht', style: titleStyle),
                    if (count.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(count, style: countStyle),
                    ],
                  ],
                )
              : Row(
                  children: [
                    Text('Nacht für Nacht', style: titleStyle),
                    if (count.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          count,
                          textAlign: TextAlign.end,
                          style: countStyle,
                        ),
                      ),
                    ],
                  ],
                ),
          const SizedBox(height: 10),
          if (_temperature && snap?.unit?.isKnown == true)
            OBCalendarLine(
              values: [for (final night in snap!.history) night.value],
              days: _nights,
              zeroCentered: snap.unit == NightScalarUnit.sd,
              visible: showChart,
            )
          else
            NightScalarChart(
              bars: [
                for (final row
                    in snap?.history ?? const <NightScalarHistoryNight>[])
                  (day: row.day, value: row.value),
              ],
              nights: _nights,
              baseline: showBaseline ? snap.baseline!.value : null,
              color: color,
              newest: loaded && _comparisonValid(snap)
                  ? obVerdictMark(p, _verdict(snap))
                  : null,
              visible: showChart,
            ),
          const SizedBox(height: 10),
          _footer(
            p,
            color,
            days.first,
            days.last,
            showBaseline ? snap.baseline!.value : null,
            tone,
            wrap,
          ),
        ],
      ),
    );
  }

  Widget _footer(
    OB p,
    Color color,
    String start,
    String end,
    double? baseline,
    _BaselineTone tone,
    bool wrap,
  ) {
    final startLabel = DateFormat(
      'd. MMM',
      'de_DE',
    ).format(DateTime.parse(start));
    final endLabel = DateFormat('d. MMM', 'de_DE').format(DateTime.parse(end));
    final dateStyle = p
        .text(12, weight: FontWeight.w500, color: p.muted)
        .copyWith(height: 16 / 12);
    final qualifier = switch (tone) {
      _BaselineTone.provisional => ' · vorläufig',
      _BaselineTone.stale => ' · veraltet',
      _BaselineTone.trusted ||
      _BaselineTone.none ||
      _BaselineTone.untrusted => '',
    };
    final basisText = baseline == null
        ? null
        : 'Basis ${_metricNumber(baseline)}\u00A0${widget.unit}$qualifier';
    final basisStyle = p
        .text(12, weight: FontWeight.w600, color: p.smallText(color))
        .copyWith(height: 16 / 12);
    Widget layout({required bool stacked}) {
      final startChild = Text(startLabel, style: dateStyle);
      final endChild = Text(endLabel, style: dateStyle);
      final basis = basisText == null
          ? null
          : Text(basisText, style: basisStyle);
      if (stacked) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(child: startChild),
                Flexible(child: endChild),
              ],
            ),
            if (basis != null) ...[const SizedBox(height: 8), basis],
          ],
        );
      }
      return Row(
        children: [
          startChild,
          const Spacer(),
          ?basis,
          const Spacer(),
          endChild,
        ],
      );
    }

    if (wrap || basisText == null) return layout(stacked: wrap);
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        double widthOf(String text, TextStyle style) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width;
        }

        const gap = 8.0;
        final needed =
            widthOf(startLabel, dateStyle) +
            widthOf(endLabel, dateStyle) +
            widthOf(basisText, basisStyle) +
            2 * gap;
        return layout(stacked: needed > constraints.maxWidth);
      },
    );
  }

  Widget _rows(OB p, NightScalarDetail? snap) {
    if (_temperature) {
      return OBCard(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: OBSettingsValueRow(
          leading: _tile(p.well, p.ink, LucideIcons.info),
          label: 'Quelle',
          value: _temperatureSourceValue(snap),
          chevron: true,
          mutedValue: true,
          onTap: () => _info(baselineOnly: false),
        ),
      );
    }
    final locked =
        _loading ||
        widget.controller.calculating ||
        widget.controller.napCalculating ||
        (snap != null &&
            (snap.withheld || snap.state == NightScalarState.unreadable));
    return OBCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          OBSettingsValueRow(
            leading: _tile(p.sleepTint, p.sleep, LucideIcons.moon),
            label: 'Nachtverlauf',
            value: _windowValue(snap),
            chevron: !locked,
            mutedValue: true,
            onTap: locked ? null : _openNight,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(height: 1, color: p.line),
          ),
          OBSettingsValueRow(
            leading: _tile(p.well, p.ink, LucideIcons.info),
            label: 'Persönliche Basis',
            value: _baselineValue(snap),
            chevron: true,
            mutedValue: true,
            onTap: () => _info(baselineOnly: true),
          ),
        ],
      ),
    );
  }

  Widget _tile(Color bg, Color fg, IconData icon) => SizedBox(
    width: 28,
    height: 36,
    child: Icon(icon, size: 18, color: OB.of(context).ink),
  );
}

class NightScalarChart extends StatelessWidget {
  final List<({String day, double? value})> bars;
  final int nights;
  final double? baseline;
  final Color color;

  /// Verdict colour for the newest night's bar; null keeps [color].
  final Color? newest;
  final bool visible;
  const NightScalarChart({
    super.key,
    required this.bars,
    required this.nights,
    required this.color,
    this.newest,
    this.baseline,
    this.visible = true,
  });

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final t = ((scaler.scale(12) / 12) - 1).clamp(0.0, 1.0);
    final height = 120 + 40 * t;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Visibility(
        visible: visible,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        child: CustomPaint(
          key: const ValueKey('night-scalar-chart'),
          painter: NightScalarBarsPainter(
            newest: newest,
            bars: bars,
            nights: nights,
            baseline: baseline,
            color: color,
            axisColor: OB.of(context).muted,
            textScaler: scaler,
          ),
        ),
      ),
    );
  }
}

/// Quiet zero-origin bars. Paper 333×120: left 26, plot y 8..108, 14px at 7
/// slots, 6px at 30, shrinking 90 (slot×0.65). Large: 160 / left 42 / y 24..140.
class NightScalarBarsPainter extends CustomPainter {
  final List<({String day, double? value})> bars;
  final int nights;
  final double? baseline;
  final Color color;
  final Color? newest;
  final Color axisColor;
  final TextScaler textScaler;

  const NightScalarBarsPainter({
    required this.bars,
    required this.nights,
    required this.color,
    this.newest,
    required this.axisColor,
    required this.textScaler,
    this.baseline,
  });

  static const double baselineAlpha = 0.5;
  static const double baselineStrokeWidth = 1.5;

  static double slotWidth(double plotWidth, int nights) =>
      nights <= 0 ? plotWidth : plotWidth / nights;

  static double barWidth(double plotWidth, int nights) {
    final slot = slotWidth(plotWidth, nights);
    final cap = nights == 7 ? 14.0 : 6.0;
    return math.min(cap, math.max(1.0, slot * 0.65));
  }

  static double barLeft(
    int index,
    int nights,
    double left,
    double plotWidth,
    double width,
  ) {
    final slot = slotWidth(plotWidth, nights);
    return left + (index + 0.5) * slot - width / 2;
  }

  double get _axisFont => textScaler.scale(12);

  double _axisMax() {
    var hi = 0.0;
    for (final bar in bars) {
      final v = bar.value;
      if (v != null && v > hi) hi = v;
    }
    if (baseline != null && baseline! > hi) hi = baseline!;
    if (hi <= 0) return 10;
    return (hi / 10).ceil() * 10;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final max = _axisMax();
    final maxLabel = obNumber(max);
    final labelStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 12,
      height: 1,
      color: axisColor,
    );
    final maxPainter = TextPainter(
      text: TextSpan(text: maxLabel, style: labelStyle),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    final zeroPainter = TextPainter(
      text: TextSpan(text: '0', style: labelStyle),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    final t = ((_axisFont / 12) - 1).clamp(0.0, 1.0);
    final plotTop = 8 + 16 * t;
    final plotBottom = 108 + 32 * t;
    final left = math.max(26.0, maxPainter.width + 10);
    final plotWidth = math.max(0.0, size.width - left);
    maxPainter.paint(canvas, Offset(0, plotTop + 5 - maxPainter.height));
    zeroPainter.paint(
      canvas,
      Offset(math.max(0, left - 19), plotBottom + 4 - zeroPainter.height / 2),
    );
    maxPainter.dispose();
    zeroPainter.dispose();

    double y(double v) => plotBottom - (v / max) * (plotBottom - plotTop);

    if (baseline != null) {
      final yy = y(baseline!);
      canvas.drawLine(
        Offset(left, yy),
        Offset(size.width, yy),
        Paint()
          ..color = color.withValues(alpha: baselineAlpha)
          ..strokeWidth = baselineStrokeWidth,
      );
    }
    if (bars.isEmpty || plotWidth <= 0) return;
    final n = nights > 0 ? nights : bars.length;
    final width = barWidth(plotWidth, n);
    final radius = Radius.circular(width / 2);
    final paint = Paint()..color = color;
    final count = math.min(bars.length, n);
    final last = Paint()..color = newest ?? color;
    for (var i = 0; i < count; i++) {
      final value = bars[i].value;
      if (value == null) continue;
      final x = barLeft(i, n, left, plotWidth, width);
      final top = y(value);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x, top, x + width, plotBottom),
          radius,
        ),
        i == count - 1 ? last : paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant NightScalarBarsPainter old) =>
      old.bars != bars ||
      old.nights != nights ||
      old.baseline != baseline ||
      old.color != color ||
      old.newest != newest ||
      old.axisColor != axisColor ||
      old.textScaler != textScaler;
}
