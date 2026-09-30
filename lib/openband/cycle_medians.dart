import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'cycle.dart';
import 'domain.dart';
import 'health.dart';
import 'journal_controls.dart';
import 'settings_controls.dart';
import 'theme.dart';
import 'undo_notice.dart';

const _kInfoTitle = 'Zyklustage';
const _kInfoIntro =
    'Mediane vergleichen denselben Tag ab einem eingetragenen Beginn. '
    'Jeder Punkt braucht Nächte aus zwei Zyklen; die Kurve mindestens drei '
    'solche Tage.\n\n'
    'Abstände und laufende Zyklen über 60 Tage werden ausgelassen. '
    'Die Zuordnung beschreibt keine Zyklusphase.';
const _kLineSep = '\u2028';
const _kQualityDisclaimer =
    'Qualitätswerte sind gespeicherte Scores, keine Fehlerspannen.';
const _kMdcDisclaimer =
    'Ein statistischer Schätzwert, keine gemessene Sensorabweichung.';

class OpenBandCycleMedians extends StatefulWidget {
  final OpenBandRepository repository;
  final String day;
  final DateTime Function()? now;
  final bool synthetic;
  final ValueChanged<OpenBandCycleHistoryResult>? onReturn;

  const OpenBandCycleMedians({
    super.key,
    required this.repository,
    required this.day,
    this.now,
    this.synthetic = false,
    this.onReturn,
  });

  static Future<OpenBandCycleHistoryResult?> push(
    BuildContext context, {
    required OpenBandRepository repository,
    required String day,
    DateTime Function()? now,
    bool synthetic = false,
  }) async {
    OpenBandCycleHistoryResult? pending;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => OpenBandCycleMedians(
          repository: repository,
          day: day,
          now: now,
          synthetic: synthetic,
          onReturn: (result) => pending = result,
        ),
      ),
    );
    return pending;
  }

  @override
  State<OpenBandCycleMedians> createState() => _OpenBandCycleMediansState();
}

class _OpenBandCycleMediansState extends State<OpenBandCycleMedians> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  int _gen = 0;
  int _mutate = 0;
  late String _anchorEnd;
  int _page = 0;
  CycleMediansSnapshot? _snapshot;
  bool _loading = true;
  bool _readError = false;
  int? _rhrSlot;
  int? _hrvSlot;
  CycleStart? _undoStart;
  bool _undoBusy = false;
  String? _refreshError;

  OpenBandRepository get _repo => widget.repository;
  DateTime _now() => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _anchorEnd = _clampAnchor(widget.day, _now());
    unawaited(_load());
  }

  @override
  void didUpdateWidget(OpenBandCycleMedians oldWidget) {
    super.didUpdateWidget(oldWidget);
    final repoChanged = !identical(oldWidget.repository, widget.repository);
    final dayChanged = oldWidget.day != widget.day;
    if (repoChanged || dayChanged) {
      setState(() {
        _mutate++;
        _anchorEnd = _clampAnchor(widget.day, _now());
        _page = 0;
        _snapshot = null;
        _rhrSlot = null;
        _hrvSlot = null;
        _readError = false;
        _loading = true;
        _undoStart = null;
        _undoBusy = false;
        _refreshError = null;
      });
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    final gen = ++_gen;
    final day = widget.day;
    final repo = _repo;
    final anchor = _anchorEnd;
    final page = _page;
    setState(() {
      _loading = true;
      _readError = false;
      _snapshot = null;
      _rhrSlot = null;
      _hrvSlot = null;
    });
    try {
      final snap = await repo.readCycleMedians(
        anchor,
        pageOffset: page,
        now: _now(),
      );
      if (!_same(gen, repo, day, anchor, page)) return;
      setState(() {
        _snapshot = snap;
        _loading = false;
        _readError = false;
      });
    } catch (_) {
      if (!_same(gen, repo, day, anchor, page)) return;
      setState(() {
        _loading = false;
        _readError = true;
        _snapshot = null;
        _rhrSlot = null;
        _hrvSlot = null;
      });
    }
  }

  bool _same(
    int gen,
    OpenBandRepository repo,
    String day,
    String anchor,
    int page,
  ) =>
      mounted &&
      gen == _gen &&
      identical(repo, _repo) &&
      widget.day == day &&
      _anchorEnd == anchor &&
      _page == page;

  CycleMedianWindow? _safeWindow({String? anchor, int? page}) {
    try {
      return cycleMedianWindow(
        anchorEnd: anchor ?? _anchorEnd,
        pageOffset: page ?? _page,
      );
    } on ArgumentError {
      return null;
    }
  }

  bool _canAcceptAnchor(String day) =>
      _safeWindow(anchor: day, page: 0) != null;

  bool _canPage(int page) {
    if (page < 0) return false;
    return _safeWindow(page: page) != null;
  }

  void _pageBy(int delta) {
    if (_undoBusy) return;
    final next = _page + delta;
    if (next < 0 || !_canPage(next)) return;
    setState(() => _page = next);
    unawaited(_load());
  }

  Future<void> _pickEnd() async {
    if (_undoBusy) return;
    final gen = _gen;
    final repo = _repo;
    final day = widget.day;
    final current = _anchorEnd;
    final page = _page;
    final picked = await pickOpenBandCycleDay(
      context,
      selected: _anchorEnd,
      now: _now(),
      synthetic: widget.synthetic,
      title: 'Enddatum',
    );
    if (picked == null || !_same(gen, repo, day, current, page)) return;
    if (!_canAcceptAnchor(picked)) return;
    if (picked == _anchorEnd && _page == 0) return;
    setState(() {
      _anchorEnd = picked;
      _page = 0;
    });
    await _load();
  }

  void _info() => showOpenBandJournalInfo(
    context,
    title: _kInfoTitle,
    body: _infoBody(_snapshot, _rhrSlot, _hrvSlot),
  );

  Future<void> _openSettings() async {
    if (_undoBusy) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => OpenBandCycleSettings(
          repository: _repo,
          now: _now,
          synthetic: widget.synthetic,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openHistory() async {
    if (_undoBusy) return;
    final gen = _gen;
    final repo = _repo;
    final day = widget.day;
    final receipt = await OpenBandCycleHistory.push(
      context,
      repository: repo,
      day: widget.day,
      now: _now,
      synthetic: widget.synthetic,
    );
    if (!mounted ||
        gen != _gen ||
        !identical(repo, _repo) ||
        widget.day != day) {
      return;
    }
    if (receipt != null && !receipt.isEmpty) {
      setState(() {
        _undoStart = receipt.start;
        _refreshError = receipt.refreshError;
      });
    }
    _showUndo();
    await _load();
  }

  void _showUndo() {
    final start = _undoStart;
    if (!mounted || start == null) return;
    final messenger = _messenger.currentState;
    if (messenger == null) return;
    showOpenBandUndoNotice(
      context: context,
      messenger: messenger,
      message:
          'Beginn ${DateFormat('d. MMM', 'de_DE').format(DateTime.parse(start.date))} entfernt',
      primaryLabel: 'Rückgängig',
      onPrimary: () {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          unawaited(_restore());
        }
      },
    );
  }

  bool _mutationLive(int mutate, OpenBandRepository repo, String day) =>
      mounted &&
      mutate == _mutate &&
      identical(repo, _repo) &&
      widget.day == day;

  Future<void> _restore() async {
    final start = _undoStart;
    if (!mounted || start == null || _undoBusy) return;
    final mutate = _mutate;
    final repo = _repo;
    final day = widget.day;
    _messenger.currentState?.removeCurrentSnackBar();
    setState(() => _undoBusy = true);
    try {
      final result = await repo.restoreCycleStart(start, now: _now());
      if (!_mutationLive(mutate, repo, day)) return;
      if (result.conflict) {
        setState(() {
          _undoBusy = false;
          _undoStart = null;
        });
        _showNotice('Beginn wurde geändert', 'Neu laden', () {
          if (mounted) unawaited(_load());
        });
        return;
      }
      if (!result.committed) {
        setState(() => _undoBusy = false);
        _showNotice('Wiederherstellen fehlgeschlagen', 'Erneut', () {
          if (mounted) unawaited(_restore());
        });
        return;
      }
      if (result.contextRefreshFailed) {
        setState(() {
          _undoBusy = false;
          _refreshError = 'Aktualisieren fehlgeschlagen';
          _undoStart = null;
        });
        await _load();
        return;
      }
      setState(() {
        _undoStart = null;
        _undoBusy = false;
        _refreshError = null;
      });
      await _load();
    } catch (_) {
      if (!_mutationLive(mutate, repo, day)) return;
      setState(() => _undoBusy = false);
      _showNotice('Wiederherstellen fehlgeschlagen', 'Erneut', () {
        if (mounted) unawaited(_restore());
      });
    }
  }

  void _showNotice(String message, String action, VoidCallback onAction) {
    if (!mounted) return;
    final messenger = _messenger.currentState;
    if (messenger == null) return;
    showOpenBandUndoNotice(
      context: context,
      messenger: messenger,
      message: message,
      primaryLabel: action,
      onPrimary: () {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          onAction();
        }
      },
    );
  }

  Future<void> _retryRefresh() async {
    if (!mounted || _undoBusy) return;
    final mutate = _mutate;
    final repo = _repo;
    final day = widget.day;
    try {
      await repo.refreshCycleContext();
      if (!_mutationLive(mutate, repo, day)) return;
      setState(() => _refreshError = null);
      await _load();
    } catch (_) {
      if (!_mutationLive(mutate, repo, day)) return;
      // Keep the committed removal/restoration receipt on retry failure.
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return ScaffoldMessenger(
      key: _messenger,
      child: PopScope(
        canPop: !_undoBusy,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) return;
          final receipt = OpenBandCycleHistoryResult(_undoStart, _refreshError);
          if (!receipt.isEmpty) widget.onReturn?.call(receipt);
        },
        child: Scaffold(
          key: const ValueKey('cycle-medians'),
          backgroundColor: p.canvas,
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                OBPageHeader(title: 'Zyklustage', subtitle: '', onInfo: _info),
                ..._body(p),
                if (widget.synthetic) const _MediansSyntheticFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(OB p) {
    final window = _snapshot?.window ?? _safeWindow();
    final children = <Widget>[
      if (window != null)
        OBWindowPager(
          startLabel: _windowDay(window.startDay),
          endLabel: _windowDay(window.endDay),
          earlierEnabled: !_undoBusy && _canPage(_page + 1),
          laterEnabled: !_undoBusy && _page > 0,
          onEarlier: () => _pageBy(1),
          onLater: () => _pageBy(-1),
          onCenter: _undoBusy ? null : _pickEnd,
          earlierKey: const ValueKey('cycle-medians-earlier'),
          laterKey: const ValueKey('cycle-medians-later'),
          centerKey: const ValueKey('cycle-medians-window'),
        ),
    ];
    if (_refreshError != null) {
      children.addAll([
        const SizedBox(height: 12),
        OBSettingsErrorCard(
          message: _refreshError!.startsWith('Entfernt')
              ? _refreshError!
              : 'Wiederhergestellt · $_refreshError',
          retryLabel: 'Erneut versuchen',
          onRetry: _undoBusy ? null : _retryRefresh,
        ),
      ]);
    }
    if (_readError) {
      children.addAll([
        const SizedBox(height: 12),
        OBSettingsErrorCard(
          message: 'Daten nicht geladen',
          retryLabel: 'Erneut versuchen',
          onRetry: _undoBusy ? null : _load,
        ),
      ]);
      return children;
    }
    if (_loading && _snapshot == null) {
      children.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator.adaptive()),
        ),
      );
      return children;
    }
    final snap = _snapshot;
    if (snap == null) return children;
    switch (snap.reason) {
      case CycleMediansReason.trackingDisabled:
        children.addAll([
          const SizedBox(height: 12),
          _notice('Zyklustracking aus', 'Einstellungen', _openSettings),
        ]);
      case CycleMediansReason.emptyStarts:
        children.addAll([
          const SizedBox(height: 12),
          _notice('Kein Zyklusbeginn', 'Zum Zyklus', () {
            Navigator.maybePop(context);
          }),
        ]);
      case CycleMediansReason.unreadableStarts:
        children.addAll([
          const SizedBox(height: 12),
          _notice(
            'Beginn nicht lesbar',
            'Zum Verlauf',
            () => unawaited(_openHistory()),
          ),
        ]);
      case CycleMediansReason.longPeriods:
        children.addAll([
          const SizedBox(height: 12),
          _mutedNotice('Abstände über 60 Tage', size: 14, height: 20),
          const SizedBox(height: 12),
          ..._metricCards(p, snap, assigned: false),
        ]);
      case CycleMediansReason.insufficientDays:
      case CycleMediansReason.available:
        if (snap.partial) {
          children.addAll([
            const SizedBox(height: 12),
            _mutedNotice('Teilweise ausgewertet', size: 13, height: 18),
          ]);
        }
        children.addAll([
          const SizedBox(height: 12),
          ..._metricCards(p, snap, assigned: true),
        ]);
    }
    return children;
  }

  List<Widget> _metricCards(
    OB p,
    CycleMediansSnapshot snap, {
    required bool assigned,
  }) {
    return [
      _metricCard(
        p,
        label: 'Ruhepuls',
        unit: 'bpm',
        color: p.pulse,
        tint: p.pulseTint,
        series: snap.rhr,
        slot: _rhrSlot,
        plotKey: const ValueKey('cycle-medians-rhr-plot'),
        assigned: assigned,
        onSelect: (i) => setState(() => _rhrSlot = i),
      ),
      const SizedBox(height: 12),
      _metricCard(
        p,
        label: 'HRV',
        unit: 'ms',
        color: p.recovery,
        tint: p.recoveryTint,
        series: snap.hrv,
        slot: _hrvSlot,
        plotKey: const ValueKey('cycle-medians-hrv-plot'),
        assigned: assigned,
        onSelect: (i) => setState(() => _hrvSlot = i),
      ),
    ];
  }

  Widget _metricCard(
    OB p, {
    required String label,
    required String unit,
    required Color color,
    required Color tint,
    required CycleMedianSeries series,
    required int? slot,
    required Key plotKey,
    required bool assigned,
    required ValueChanged<int> onSelect,
  }) {
    if (!assigned) {
      return OBTrendCard.sourced(
        label: label,
        unit: unit,
        icon: LucideIcons.activity,
        color: color,
        tint: tint,
        points: const [OBSourcedSample(caption: 'Nicht zugeordnet')],
        selectedIndex: 0,
      );
    }
    if (!series.available) {
      return OBTrendCard.sourced(
        label: label,
        unit: unit,
        icon: LucideIcons.activity,
        color: color,
        tint: tint,
        points: const [OBSourcedSample(caption: 'Zu wenige Nächte')],
        selectedIndex: 0,
      );
    }
    final points = [
      for (final point in series.points)
        OBSourcedSample(
          value: point.median,
          caption: 'Median · Tag ${point.cycleDay}',
          semantics: 'Tag ${point.cycleDay}',
        ),
    ];
    final index = slot != null && slot >= 0 && slot < points.length
        ? slot
        : points.length - 1;
    final selected = series.points[index];
    return OBTrendCard.sourced(
      label: label,
      unit: unit,
      icon: LucideIcons.activity,
      color: color,
      tint: tint,
      points: points,
      coverage: _cycleCount(selected.contributingPeriodCount),
      axisStart: 'Tag 1',
      axisEnd: 'Tag ${series.points.last.cycleDay}',
      selectedIndex: index,
      plotKey: plotKey,
      onSelect: onSelect,
    );
  }

  Widget _notice(String message, String action, VoidCallback onAction) {
    final p = OB.of(context);
    return OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: p.text(14, color: p.muted).copyWith(height: 18.2 / 14),
          ),
          const SizedBox(height: 8),
          OBAction(action, secondary: true, ink: true, onPressed: onAction),
        ],
      ),
    );
  }

  Widget _mutedNotice(
    String message, {
    required double size,
    required double height,
  }) {
    final p = OB.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        message,
        style: p.text(size, color: p.muted).copyWith(height: height / size),
      ),
    );
  }
}

class _MediansSyntheticFooter extends StatelessWidget {
  const _MediansSyntheticFooter();

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

String _clampAnchor(String day, DateTime now) =>
    cycleDateIsAfterToday(day, now) ? cycleTodayLabel(now) : day;

String _windowDay(String day) =>
    DateFormat('d. MMM y', 'de_DE').format(DateTime.parse(day));

String _cycleCount(int n) => n == 1 ? '1 Zyklus' : '$n Zyklen';

String _infoBody(CycleMediansSnapshot? snap, int? rhrSlot, int? hrvSlot) {
  if (snap == null) return _kInfoIntro;
  final parts = <String>[_kInfoIntro];
  final partial = _partialInfo(snap);
  if (partial != null) parts.add(partial);
  final rhrPoint = _selectedPoint(snap.rhr, rhrSlot);
  final hrvPoint = _selectedPoint(snap.hrv, hrvSlot);
  final rhrCs = rhrPoint?.contributors ?? const <CycleMedianContributor>[];
  final hrvCs = hrvPoint?.contributors ?? const <CycleMedianContributor>[];
  final cross = _coveringNote([...rhrCs, ...hrvCs]);
  final rhrCover = cross ?? _coveringNote(rhrCs);
  final hrvCover = cross ?? _coveringNote(hrvCs);
  final shared =
      rhrCover != null && hrvCover != null && rhrCover.text == hrvCover.text
      ? rhrCover
      : null;
  if (rhrPoint != null) {
    parts.add(
      _seriesParagraph(
        'Ruhepuls',
        'bpm',
        rhrPoint,
        snap.window.endDay,
        cover: rhrCover,
      ),
    );
    if (rhrCover != null && shared == null) parts.add(rhrCover.text);
  }
  if (hrvPoint != null) {
    parts.add(
      _seriesParagraph(
        'HRV',
        'ms',
        hrvPoint,
        snap.window.endDay,
        cover: hrvCover,
      ),
    );
    if (hrvCover != null && shared == null) parts.add(hrvCover.text);
  }
  if (shared != null) {
    parts.add(shared.text);
  } else if (rhrCover == null && hrvCover == null) {
    parts.add(_kQualityDisclaimer);
  }
  final mdc = _mdcParagraph(snap);
  if (mdc != null) parts.add(mdc);
  return parts.join('\n\n');
}

CycleMedianPoint? _selectedPoint(CycleMedianSeries series, int? slot) {
  if (!series.available || series.points.isEmpty) return null;
  final index = slot != null && slot >= 0 && slot < series.points.length
      ? slot
      : series.points.length - 1;
  return series.points[index];
}

class _WindowCover {
  const _WindowCover({required this.text, required this.coversAlgo});
  final String text;
  final bool coversAlgo;
}

String _seriesParagraph(
  String label,
  String unit,
  CycleMedianPoint point,
  String asOfDay, {
  required _WindowCover? cover,
}) {
  final medianText = point.median == null ? '—' : obNumber(point.median);
  final header = '$label · Tag ${point.cycleDay} · $medianText $unit';
  final contributors = point.contributors;
  if (contributors.isEmpty) return header;
  final values = [for (final c in contributors) c.metric.value];
  final qualities = [for (final c in contributors) _quality(c.metric)];
  final valuesEqual = values.every((v) => v == values.first);
  final qualityEqual = qualities.every((q) => q == qualities.first);
  final coverWindow = cover != null;
  final coverAlgo = cover?.coversAlgo ?? false;
  final envelopesEqual = _envelopesEqual(contributors);
  final lines = <String>[header];
  final compact =
      valuesEqual && qualityEqual && coverWindow && coverAlgo && envelopesEqual;
  if (compact) {
    for (final c in contributors) {
      lines.add(
        '${_civilDay(c.nightDay, asOfDay)} · Beginn ${_civilDay(c.startDay, asOfDay)}',
      );
    }
    lines.add('Jeweils ${obNumber(values.first)} $unit · ${qualities.first}');
    final grouped = _envelopeLabels(contributors.first);
    if (grouped.isNotEmpty) lines.add(grouped.join(' · '));
    return lines.join(_kLineSep);
  }
  for (final c in contributors) {
    lines.add(
      _contributorLine(
        c,
        unit,
        asOfDay,
        includeWindow: !coverWindow,
        includeAlgo: !coverAlgo,
      ),
    );
  }
  return lines.join(_kLineSep);
}

String _contributorLine(
  CycleMedianContributor c,
  String unit,
  String asOfDay, {
  required bool includeWindow,
  required bool includeAlgo,
}) {
  final bits = <String>[
    '${_civilDay(c.nightDay, asOfDay)} · Beginn ${_civilDay(c.startDay, asOfDay)}',
    '${obNumber(c.metric.value)} $unit',
  ];
  if (includeWindow) {
    final window = _windowUtc(c.sleepStart, c.sleepEnd, asOfDay);
    if (window != null) bits.add(window);
  }
  bits.addAll(_envelopeLabels(c));
  bits.add(_quality(c.metric));
  if (includeAlgo) bits.add('Algorithmus ${c.algoVersion}');
  return bits.join(' · ');
}

List<String> _envelopeLabels(CycleMedianContributor c) {
  final bits = <String>[];
  final source = c.sleepSource?.trim();
  if (source != null && source.isNotEmpty) {
    bits.add(switch (source) {
      'auto' => 'Schlaf: automatisch',
      'manual' => 'Schlaf: manuell',
      'confirmed' => 'Schlaf: bestätigt',
      _ => 'Schlafquelle: $source',
    });
  }
  final note = c.metric.note?.trim();
  if (note != null && note.isNotEmpty) bits.add('Hinweis: $note');
  final tier = c.metric.tier?.trim();
  if (tier != null && tier.isNotEmpty) bits.add('Stufe: $tier');
  if (c.metric.inputsUsed.isNotEmpty) {
    bits.add(
      'Eingaben: ${[for (final key in c.metric.inputsUsed) _inputLabel(key)].join(', ')}',
    );
  }
  return bits;
}

String _inputLabel(String key) => switch (key) {
  'hr_1hz' => 'Puls (1 Hz)',
  'sleep_window' => 'Schlaffenster',
  'rr_sleep_window' => 'RR-Intervalle im Schlaffenster',
  _ => key,
};

bool _envelopesEqual(List<CycleMedianContributor> contributors) {
  if (contributors.length <= 1) return true;
  String key(CycleMedianContributor c) => _envelopeLabels(c).join('\u0001');
  final first = key(contributors.first);
  return contributors.every((c) => key(c) == first);
}

_WindowCover? _coveringNote(List<CycleMedianContributor> contributors) {
  if (contributors.isEmpty) return null;
  if (!_sharedRelativeWindow(contributors)) return null;
  final times = _vortagClock(contributors.first);
  if (times == null) return null;
  final algos = {for (final c in contributors) c.algoVersion};
  final coversAlgo = algos.length == 1;
  final buf = StringBuffer(
    'Die gezeigten Nächte reichen jeweils vom Vortag, ${times.$1} '
    'bis zum genannten Datum, ${times.$2} UTC.',
  );
  if (coversAlgo) {
    buf.write(' Algorithmus ${algos.single}.');
  }
  buf.write(' $_kQualityDisclaimer');
  return _WindowCover(text: buf.toString(), coversAlgo: coversAlgo);
}

bool _sharedRelativeWindow(List<CycleMedianContributor> contributors) {
  if (contributors.isEmpty) return false;
  final first = _relativeWindow(contributors.first);
  if (first == null) return false;
  for (final c in contributors.skip(1)) {
    final rel = _relativeWindow(c);
    if (rel != first) return false;
  }
  return true;
}

(String, String)? _vortagClock(CycleMedianContributor c) {
  final start = c.sleepStart?.toUtc();
  final end = c.sleepEnd?.toUtc();
  if (start == null || end == null) return null;
  final named = DateTime.utc(
    int.parse(c.nightDay.substring(0, 4)),
    int.parse(c.nightDay.substring(5, 7)),
    int.parse(c.nightDay.substring(8, 10)),
  );
  final prev = named.subtract(const Duration(days: 1));
  if (start.year != prev.year ||
      start.month != prev.month ||
      start.day != prev.day) {
    return null;
  }
  if (end.year != named.year ||
      end.month != named.month ||
      end.day != named.day) {
    return null;
  }
  return (_hhmm(start), _hhmm(end));
}

(int, int, int, int)? _relativeWindow(CycleMedianContributor c) {
  final start = c.sleepStart?.toUtc();
  final end = c.sleepEnd?.toUtc();
  if (start == null || end == null || !end.isAfter(start)) return null;
  final named = DateTime.utc(
    int.parse(c.nightDay.substring(0, 4)),
    int.parse(c.nightDay.substring(5, 7)),
    int.parse(c.nightDay.substring(8, 10)),
  );
  return (
    start.difference(named).inMinutes,
    start.hour * 60 + start.minute,
    end.difference(named).inMinutes,
    end.hour * 60 + end.minute,
  );
}

String? _mdcParagraph(CycleMediansSnapshot snap) {
  final pieces = <String>[
    ?_mdcPiece('Ruhepuls', 'bpm', snap.rhr),
    ?_mdcPiece('HRV', 'ms', snap.hrv),
  ];
  if (pieces.isEmpty) return null;
  return 'Robustes Streuungsmaß (MDC): ${pieces.join('; ')}. $_kMdcDisclaimer';
}

String? _mdcPiece(String name, String unit, CycleMedianSeries series) {
  if (series.spread.sampleCount <= 0 && !series.available) return null;
  final proxy = series.spread.proxy;
  final n = series.spread.sampleCount;
  final value = proxy == null || !proxy.isFinite || proxy <= 0
      ? '—'
      : obNumber(proxy, digits: proxy == proxy.roundToDouble() ? 0 : 1);
  final nights = n == 1 ? '1 Nacht' : '$n Nächten';
  return '$name $value $unit aus $nights';
}

String? _partialInfo(CycleMediansSnapshot snap) {
  if (!snap.partial) return null;
  final parts = <String>[];
  if (snap.excludedPeriodCount > 0) {
    parts.add(
      snap.excludedPeriodCount == 1
          ? '1 Zyklus ausgelassen'
          : '${snap.excludedPeriodCount} Zyklen ausgelassen',
    );
  }
  if (snap.unreadableNightCount > 0) {
    parts.add(
      snap.unreadableNightCount == 1
          ? '1 Nacht nicht lesbar'
          : '${snap.unreadableNightCount} Nächte nicht lesbar',
    );
  }
  if (snap.excludedNightCount > 0) {
    parts.add(
      snap.excludedNightCount == 1
          ? '1 Nacht ausgelassen'
          : '${snap.excludedNightCount} Nächte ausgelassen',
    );
  }
  if (parts.isEmpty) return null;
  return '${parts.join('. ')}.';
}

String _civilDay(String day, String asOfDay) {
  final date = DateTime.parse(day);
  final asOf = DateTime.parse(asOfDay);
  final fmt = date.year == asOf.year ? 'd. MMM' : 'd. MMM y';
  return DateFormat(fmt, 'de_DE').format(date);
}

String? _windowUtc(DateTime? start, DateTime? end, String asOfDay) {
  if (start == null || end == null || !end.isAfter(start)) return null;
  final from = start.toUtc();
  final to = end.toUtc();
  final asOfYear = DateTime.parse(asOfDay).year;
  final needYear =
      from.year != to.year || from.year != asOfYear || to.year != asOfYear;
  String stamp(DateTime at) {
    final date = DateTime(at.year, at.month, at.day);
    final day = DateFormat(
      needYear ? 'd. MMM y' : 'd. MMM',
      'de_DE',
    ).format(date);
    return '$day, ${_hhmm(at)}';
  }

  if (from.year == to.year && from.month == to.month && from.day == to.day) {
    return '${stamp(from)}–${_hhmm(to)} UTC';
  }
  return '${stamp(from)}–${stamp(to)} UTC';
}

String _hhmm(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

String _quality(CycleNightMetric metric) {
  if (metric.confidenceUnreadable) return 'Qualitätswert —';
  final confidence = metric.confidence;
  if (confidence == null || !confidence.isFinite) return 'Qualitätswert —';
  final digits = confidence == confidence.roundToDouble() ? 0 : 2;
  return 'Qualitätswert ${obNumber(confidence, digits: digits)} / 1';
}
