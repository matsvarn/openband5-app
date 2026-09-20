import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/journal_fields.dart';
import 'alp_tokens.dart';
import 'domain.dart';
import 'journal_value_editor.dart';
import 'theme.dart';

enum _WaterIssue { none, unread, write, refresh }

class OpenBandWaterCard extends StatefulWidget {
  final OpenBandRepository repository;
  final String day;
  final int revision;
  final FutureOr<void> Function()? onSaved;
  const OpenBandWaterCard({
    super.key,
    required this.repository,
    required this.day,
    this.revision = 0,
    this.onSaved,
  });

  @override
  State<OpenBandWaterCard> createState() => _OpenBandWaterCardState();
}

class _OpenBandWaterCardState extends State<OpenBandWaterCard> {
  static final JournalFieldSpec _spec = kJournalFieldsByKey['water_ml']!;

  int _generation = 0;
  bool _ready = false;
  bool _known = false;
  bool _busy = false;
  bool _insightsDirty = false;
  _WaterIssue _issue = _WaterIssue.none;
  double? _pendingDelta;
  double? _amount;
  JournalMetricValue? _metric;
  int _metricRev = 0;

  bool get _stacked => MediaQuery.textScalerOf(context).scale(15) > 20;

  bool _same(OpenBandRepository repo, String day, int token) =>
      mounted &&
      token == _generation &&
      identical(widget.repository, repo) &&
      widget.day == day;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant OpenBandWaterCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sameIdentity =
        identical(oldWidget.repository, widget.repository) &&
        oldWidget.day == widget.day;
    if (!sameIdentity) {
      _insightsDirty = false;
      _generation++;
      _ready = false;
      _known = false;
      _busy = false;
      _issue = _WaterIssue.none;
      _pendingDelta = null;
      _amount = null;
      _metric = null;
      _metricRev = 0;
      _load();
      return;
    }
    if (oldWidget.revision == widget.revision) return;
    _onInsightsBump();
  }

  void _onInsightsBump() {
    if (_busy || _issue == _WaterIssue.write) {
      _insightsDirty = true;
      return;
    }
    _insightsDirty = false;
    unawaited(_pullExternal());
  }

  void _flushInsights() {
    if (!mounted || !_insightsDirty) return;
    if (_busy || _issue == _WaterIssue.write) return;
    _insightsDirty = false;
    unawaited(_pullExternal());
  }

  void _coalesceIfHeld() {
    if (_busy || _issue == _WaterIssue.write) _insightsDirty = true;
  }

  Future<void> _pullExternal() async {
    final repo = widget.repository;
    final day = widget.day;
    final token = ++_generation;
    try {
      final snap = await repo.readJournalDay(day);
      if (!_same(repo, day, token)) {
        _coalesceIfHeld();
        return;
      }
      if (_busy || _issue == _WaterIssue.write) {
        _insightsDirty = true;
        return;
      }
      final metric = snap.metrics['water_ml'];
      setState(() {
        _metric = metric;
        _metricRev = snap.metricUpdatedAt['water_ml'] ?? 0;
        _amount = metric?.value;
        _issue = _WaterIssue.none;
        _pendingDelta = null;
        _ready = true;
        _known = true;
      });
    } catch (_) {
      if (!_same(repo, day, token)) {
        _coalesceIfHeld();
        return;
      }
      if (_busy || _issue == _WaterIssue.write) {
        _insightsDirty = true;
        return;
      }
      setState(() {
        _issue = _known ? _WaterIssue.refresh : _WaterIssue.unread;
        _ready = true;
      });
    }
  }

  Future<void> _load() async {
    final repo = widget.repository;
    final day = widget.day;
    final token = ++_generation;
    try {
      final snap = await repo.readJournalDay(day);
      if (!_same(repo, day, token)) return;
      final metric = snap.metrics['water_ml'];
      setState(() {
        _metric = metric;
        _metricRev = snap.metricUpdatedAt['water_ml'] ?? 0;
        _amount = metric?.value;
        _issue = _WaterIssue.none;
        _pendingDelta = null;
        _ready = true;
        _known = true;
      });
    } catch (_) {
      if (!_same(repo, day, token)) return;
      setState(() {
        _issue = _known ? _WaterIssue.refresh : _WaterIssue.unread;
        _ready = true;
      });
    }
  }

  Future<bool> _refreshAfterWrite(
    OpenBandRepository repo,
    String day,
    int token,
  ) async {
    try {
      final snap = await repo.readJournalDay(day);
      if (!_same(repo, day, token)) return false;
      final metric = snap.metrics['water_ml'];
      setState(() {
        _metric = metric;
        _metricRev = snap.metricUpdatedAt['water_ml'] ?? 0;
        _amount = metric?.value;
        _issue = _WaterIssue.none;
      });
      return true;
    } catch (_) {
      if (!_same(repo, day, token)) return false;
      setState(() => _issue = _WaterIssue.refresh);
      return false;
    }
  }

  Future<void> _afterCommit(
    OpenBandRepository repo,
    String day,
    int token,
  ) async {
    var refreshFailed = false;
    try {
      await widget.onSaved?.call();
    } catch (_) {
      refreshFailed = true;
    }
    if (!_same(repo, day, token)) return;
    final readOk = await _refreshAfterWrite(repo, day, token);
    if (!_same(repo, day, token)) return;
    if (refreshFailed || !readOk) {
      setState(() => _issue = _WaterIssue.refresh);
    }
  }

  Future<void> _retry() async {
    if (_busy) return;
    switch (_issue) {
      case _WaterIssue.write:
        final delta = _pendingDelta;
        if (delta == null) return;
        await _adjust(delta);
      case _WaterIssue.refresh:
        await _retryRead();
      case _WaterIssue.unread:
        await _load();
      case _WaterIssue.none:
        break;
    }
  }

  Future<void> _retryRead() async {
    if (_busy || !_known) {
      await _load();
      return;
    }
    final repo = widget.repository;
    final day = widget.day;
    final token = ++_generation;
    setState(() => _busy = true);
    try {
      await _afterCommit(repo, day, token);
    } finally {
      if (_same(repo, day, token)) setState(() => _busy = false);
      _flushInsights();
    }
  }

  Future<void> _adjust(double delta) async {
    if (_busy || !_ready) return;
    if (_issue == _WaterIssue.unread || _issue == _WaterIssue.refresh) return;
    if (delta < 0 && _amount == null) return;
    final repo = widget.repository;
    final day = widget.day;
    final token = ++_generation;
    setState(() {
      _busy = true;
      _pendingDelta = delta;
      _issue = _WaterIssue.none;
    });
    try {
      final committed = await repo.adjustWater(day, delta);
      if (!_same(repo, day, token)) return;
      setState(() {
        _amount = committed;
        _metric = committed == null
            ? null
            : JournalMetricValue(
                committed,
                atMinuteOfDay: _metric?.atMinuteOfDay,
              );
        _known = true;
        _pendingDelta = null;
      });
      await _afterCommit(repo, day, token);
    } catch (_) {
      if (!_same(repo, day, token)) return;
      setState(() => _issue = _WaterIssue.write);
    } finally {
      if (_same(repo, day, token)) setState(() => _busy = false);
      _flushInsights();
    }
  }

  Future<void> _openManual() async {
    if (_busy || !_ready || _issue != _WaterIssue.none) return;
    final repo = widget.repository;
    final day = widget.day;
    final token = ++_generation;
    setState(() => _busy = true);
    var expected = _metric;
    var expectedRev = _metricRev;
    try {
      final result = await showOpenBandJournalValueSheet(
        context: context,
        spec: _spec,
        metric: _metric,
        apply: (value) async {
          if (!mounted ||
              !identical(widget.repository, repo) ||
              widget.day != day ||
              token != _generation) {
            return OpenBandJournalValueApplyOutcome.stale;
          }
          try {
            await repo.patchJournalDay(
              JournalDayPatch(
                day: day,
                metrics: {'water_ml': value},
                expectedMetrics: {'water_ml': expected},
                expectedMetricUpdatedAt: {'water_ml': expectedRev},
              ),
            );
            return OpenBandJournalValueApplyOutcome.committed;
          } on JournalConflict {
            return OpenBandJournalValueApplyOutcome.conflict;
          } catch (_) {
            return OpenBandJournalValueApplyOutcome.failed;
          }
        },
        reload: () async {
          final snap = await repo.readJournalDay(day);
          expected = snap.metrics['water_ml'];
          expectedRev = snap.metricUpdatedAt['water_ml'] ?? 0;
          if (_same(repo, day, token)) {
            setState(() {
              _metric = expected;
              _metricRev = expectedRev;
              _amount = expected?.value;
              _issue = _WaterIssue.none;
              _known = true;
            });
          }
          return expected;
        },
      );
      if (!mounted) return;
      if (!_same(repo, day, token) || result == null) return;
      final follow = ++_generation;
      setState(() {
        _metric = result.value;
        _amount = result.value?.value;
        _known = true;
        _issue = _WaterIssue.none;
        _pendingDelta = null;
      });
      await _afterCommit(repo, day, follow);
    } finally {
      if (mounted && identical(widget.repository, repo) && widget.day == day) {
        setState(() => _busy = false);
      }
      _flushInsights();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final stacked = _stacked;
    final step = _spec.step.round();
    final unread = _issue == _WaterIssue.unread;
    final showRetry = _issue != _WaterIssue.none;
    final issueText = switch (_issue) {
      _WaterIssue.write => 'Speichern fehlgeschlagen',
      _WaterIssue.refresh => 'Laden fehlgeschlagen',
      _WaterIssue.unread || _WaterIssue.none => null,
    };
    final minusEnabled = _ready && !_busy && _amount != null && !showRetry;
    final plusEnabled = _ready && !_busy && !showRetry;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(AlpRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: unread || _busy || showRetry ? null : _openManual,
                  borderRadius: BorderRadius.circular(12),
                  child: stacked
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Wasser', style: _labelStyle(p)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(child: _valueRow(p, unread: unread)),
                                if (!unread)
                                  Icon(
                                    LucideIcons.chevronRight,
                                    size: 18,
                                    color: p.muted,
                                  ),
                              ],
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: Text('Wasser', style: _labelStyle(p)),
                            ),
                            _valueRow(p, unread: unread),
                            if (!unread) ...[
                              const SizedBox(width: 8),
                              Icon(
                                LucideIcons.chevronRight,
                                size: 18,
                                color: p.muted,
                              ),
                            ],
                          ],
                        ),
                ),
              ),
            ),
            if (issueText != null) ...[
              const SizedBox(height: 12),
              _inlineIssue(p, issueText),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                if (!showRetry) ...[
                  Expanded(
                    child: _deltaButton(
                      p,
                      key: const ValueKey('water-minus'),
                      label: '−$step ml',
                      filled: false,
                      enabled: minusEnabled,
                      height: stacked ? 64 : 44,
                      onPressed: minusEnabled
                          ? () => _adjust(-_spec.step)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: _deltaButton(
                    p,
                    key: ValueKey(showRetry ? 'water-retry' : 'water-plus'),
                    label: showRetry ? 'Erneut versuchen' : '+$step ml',
                    filled: true,
                    enabled: showRetry ? !_busy : plusEnabled,
                    height: stacked ? 64 : 44,
                    onPressed: showRetry
                        ? (_busy ? null : _retry)
                        : (plusEnabled ? () => _adjust(_spec.step) : null),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _labelStyle(OB p) =>
      p.text(15, weight: FontWeight.w600).copyWith(height: 20 / 15);

  Widget _inlineIssue(OB p, String text) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 24),
      child: Row(
        children: [
          Icon(LucideIcons.circleAlert, size: 18, color: p.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: p.text(13, color: p.danger).copyWith(height: 18 / 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _valueRow(OB p, {required bool unread}) {
    if (unread) {
      return Text(
        'Nicht geladen',
        textAlign: TextAlign.end,
        style: p.text(13, color: p.danger).copyWith(height: 18 / 13),
      );
    }
    if (!_ready && !_known) return const SizedBox.shrink();
    final amount = _known ? _amount : null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          amount == null ? '—' : obNumber(amount),
          style: p
              .text(28, weight: FontWeight.w700, display: true)
              .copyWith(height: 34 / 28),
        ),
        const SizedBox(width: 4),
        Text(
          'ml',
          style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
        ),
      ],
    );
  }

  Widget _deltaButton(
    OB p, {
    Key? key,
    required String label,
    required bool filled,
    required bool enabled,
    required double height,
    required VoidCallback? onPressed,
  }) {
    final background = filled ? p.ink : p.well;
    final Color foreground;
    if (filled) {
      foreground = p.dark ? p.canvas : Colors.white;
    } else if (enabled) {
      foreground = p.ink;
    } else {
      foreground = p.muted.withValues(alpha: 0.45);
    }
    final style = p
        .text(15, weight: FontWeight.w600)
        .copyWith(height: 20 / 15, color: foreground);
    return ConstrainedBox(
      key: key,
      constraints: BoxConstraints(minHeight: height),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: background,
          disabledForegroundColor: foreground,
          minimumSize: Size(44, height),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AlpRadius.well),
          ),
          textStyle: style,
        ),
        child: Text(label, textAlign: TextAlign.center, style: style),
      ),
    );
  }
}
