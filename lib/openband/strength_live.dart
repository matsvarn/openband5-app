import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'alp_tokens.dart';
import 'domain.dart';
import 'theme.dart';

/// Live strength session started from a template. The template is copied
/// into a snapshot at start; confirming a set records it immediately, so a
/// crash loses at most the set being typed.
class OpenBandStrengthLive extends StatefulWidget {
  final OpenBandRepository repository;
  final WorkoutTemplate template;
  final VoidCallback? onFinished;
  final DateTime Function() now;
  const OpenBandStrengthLive({
    super.key,
    required this.repository,
    required this.template,
    this.onFinished,
    this.now = DateTime.now,
  });
  @override
  State<OpenBandStrengthLive> createState() => _OpenBandStrengthLiveState();
}

class _OpenBandStrengthLiveState extends State<OpenBandStrengthLive> {
  String? _sessionId;
  late final DateTime _startedAt = widget.now();
  final Set<String> _done = {};
  final Map<String, TextEditingController> _load = {}, _reps = {};
  Timer? _tick;
  DateTime? _restUntil;
  int _restTotal = 0;
  String? _error;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    for (final e in widget.template.exercises) {
      for (final s in e.sets) {
        _load[s.id] = TextEditingController(
          text: s.loadKg == null ? '' : obNumber(s.loadKg, digits: 1),
        );
        _reps[s.id] = TextEditingController(
          text: (s.reps ?? s.seconds)?.toString() ?? '',
        );
      }
    }
    widget.repository
        .startStrengthSession(widget.template)
        .then((id) => mounted ? setState(() => _sessionId = id) : null)
        .catchError((Object _) {
          if (mounted) {
            setState(() => _error = 'Einheit konnte nicht gestartet werden.');
          }
        });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    for (final c in [..._load.values, ..._reps.values]) {
      c.dispose();
    }
    super.dispose();
  }

  PlannedSet? get _active {
    for (final e in widget.template.exercises) {
      for (final s in e.sets) {
        if (!_done.contains(s.id)) return s;
      }
    }
    return null;
  }

  Future<void> _confirm(PlannedExercise e, PlannedSet s, int index) async {
    final id = _sessionId;
    if (id == null) return;
    final load = double.tryParse(_load[s.id]!.text.replaceAll(',', '.'));
    final count = int.tryParse(_reps[s.id]!.text);
    if (count == null) {
      setState(() => _error = 'Wiederholungen oder Sekunden fehlen.');
      return;
    }
    try {
      await widget.repository.recordSet(
        id,
        RecordedSet(
          exerciseKey: e.exerciseKey,
          setIndex: index,
          reps: s.seconds == null ? count : null,
          seconds: s.seconds == null ? null : count,
          loadKg: load,
          at: widget.now(),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Satz konnte nicht gespeichert werden.');
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _error = null;
      _done.add(s.id);
      if (s.restSec case final r? when _active != null) {
        _restTotal = r;
        _restUntil = widget.now().add(Duration(seconds: r));
      } else {
        _restUntil = null;
      }
    });
  }

  Future<void> _finish() async {
    final id = _sessionId;
    if (id == null) return;
    setState(() => _finishing = true);
    try {
      await widget.repository.finishStrengthSession(id);
      widget.onFinished?.call();
      if (mounted) Navigator.of(context).maybePop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _finishing = false;
          _error = 'Einheit konnte nicht beendet werden.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final elapsed = widget.now().difference(_startedAt);
    final active = _active;
    final rest = _restUntil?.difference(widget.now()).inSeconds;
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        backgroundColor: p.canvas,
        leading: IconButton(
          tooltip: 'Einklappen',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(LucideIcons.chevronDown, size: 22),
        ),
        centerTitle: true,
        title: Column(
          children: [
            Text(
              widget.template.name,
              style: p.text(16, weight: FontWeight.w600),
            ),
            Text(
              _clock(elapsed.inSeconds),
              style: p.text(
                13,
                weight: FontWeight.w700,
                display: true,
                color: p.strainText,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _sessionId == null || _finishing ? null : _finish,
            child: const Text('Fertig'),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 4, 16, rest != null ? 120 : 24),
        children: [
          if (_error case final err?)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                err,
                style: p.text(13, weight: FontWeight.w600, color: p.danger),
              ),
            ),
          for (final e in widget.template.exercises)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OBExerciseBlock(
                exercise: e,
                done: _done,
                activeSetId: active?.id,
                load: _load,
                reps: _reps,
                onConfirm: (s, i) => _confirm(e, s, i),
              ),
            ),
        ],
      ),
      bottomSheet: rest == null || rest <= 0 || _restTotal == 0
          ? null
          : OBRestTimer(
              remaining: rest,
              total: _restTotal,
              onAdd: () => setState(() {
                _restUntil = _restUntil!.add(const Duration(seconds: 30));
                _restTotal += 30;
              }),
              onSkip: () => setState(() => _restUntil = null),
            ),
    );
  }
}

String _clock(int seconds) {
  final m = seconds ~/ 60, s = seconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

class OBExerciseBlock extends StatelessWidget {
  final PlannedExercise exercise;
  final Set<String> done;
  final String? activeSetId;
  final Map<String, TextEditingController> load, reps;
  final void Function(PlannedSet set, int index) onConfirm;
  const OBExerciseBlock({
    super.key,
    required this.exercise,
    required this.done,
    required this.activeSetId,
    required this.load,
    required this.reps,
    required this.onConfirm,
  });
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final timed = exercise.sets.any((s) => s.seconds != null);
    Widget head(
      String t, {
      double? width,
      TextAlign align = TextAlign.center,
    }) => SizedBox(
      width: width,
      child: Text(
        t,
        textAlign: align,
        style: p.text(11, weight: FontWeight.w600, color: p.muted),
      ),
    );
    return OBCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  exercise.name,
                  style: p.text(15, weight: FontWeight.w600),
                ),
              ),
              Text(
                '${done.where((id) => exercise.sets.any((s) => s.id == id)).length} / ${exercise.sets.length}',
                style: p.text(13, weight: FontWeight.w600, color: p.muted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              head('SATZ', width: 40, align: TextAlign.left),
              Expanded(child: head(timed ? '' : 'KG')),
              Expanded(child: head(timed ? 'SEK' : 'WDH')),
              head('', width: 44),
            ],
          ),
          for (final (i, s) in exercise.sets.indexed)
            _SetRow(
              index: i + 1,
              set: s,
              state: done.contains(s.id)
                  ? _SetState.done
                  : s.id == activeSetId
                  ? _SetState.active
                  : _SetState.planned,
              timed: timed,
              load: load[s.id]!,
              reps: reps[s.id]!,
              onConfirm: () => onConfirm(s, i + 1),
            ),
        ],
      ),
    );
  }
}

enum _SetState { done, active, planned }

class _SetRow extends StatelessWidget {
  final int index;
  final PlannedSet set;
  final _SetState state;
  final bool timed;
  final TextEditingController load, reps;
  final VoidCallback onConfirm;
  const _SetRow({
    required this.index,
    required this.set,
    required this.state,
    required this.timed,
    required this.load,
    required this.reps,
    required this.onConfirm,
  });
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final muted = state == _SetState.planned;
    Widget field(TextEditingController c, {bool enabled = true}) => Container(
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: state == _SetState.done ? Colors.transparent : p.well,
        borderRadius: BorderRadius.circular(10),
        border: state == _SetState.active
            ? Border.all(color: p.action, width: 1.5)
            : null,
      ),
      alignment: Alignment.center,
      child: state == _SetState.done
          ? Text(
              c.text.isEmpty ? '—' : c.text,
              style: p.text(15, weight: FontWeight.w700, display: true),
            )
          : TextField(
              controller: c,
              enabled: enabled && state == _SetState.active,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: p.text(
                15,
                weight: FontWeight.w700,
                display: true,
                color: muted ? p.muted : p.ink,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
    );
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: state == _SetState.done ? p.recoveryTint : null,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              '$index',
              style: p.text(
                14,
                weight: FontWeight.w700,
                display: true,
                color: muted ? p.muted : p.ink,
              ),
            ),
          ),
          Expanded(child: timed ? const SizedBox() : field(load)),
          Expanded(child: field(reps)),
          SizedBox(
            width: 44,
            child: state == _SetState.done
                ? Icon(LucideIcons.check, size: 20, color: p.recovery)
                : IconButton(
                    tooltip: 'Satz $index bestätigen',
                    onPressed: state == _SetState.active ? onConfirm : null,
                    icon: Icon(
                      LucideIcons.check,
                      size: 20,
                      color: state == _SetState.active ? p.action : p.gap,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class OBRestTimer extends StatelessWidget {
  final int remaining, total;
  final VoidCallback onAdd, onSkip;
  const OBRestTimer({
    super.key,
    required this.remaining,
    required this.total,
    required this.onAdd,
    required this.onSkip,
  });
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(AlpRadius.card),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
                child: Row(
                  children: [
                    Text(
                      'Pause',
                      style: p.text(
                        13,
                        weight: FontWeight.w600,
                        color: p.muted,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _clock(remaining),
                      style: p.text(
                        22,
                        weight: FontWeight.w800,
                        display: true,
                        color: p.strainText,
                      ),
                    ),
                    const Spacer(),
                    TextButton(onPressed: onAdd, child: const Text('+30 s')),
                    FilledButton.tonal(
                      onPressed: onSkip,
                      child: const Text('Weiter'),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 4,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: total == 0
                        ? 0
                        : (remaining / total).clamp(0.0, 1.0),
                    child: ColoredBox(color: p.strain),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
