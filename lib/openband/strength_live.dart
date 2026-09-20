import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'alp_tokens.dart';
import 'domain.dart';
import 'exercise_input.dart';
import 'settings_controls.dart';
import 'theme.dart';

/// Live strength session started from a template snapshot, or resumed from
/// the durable runtime. Confirming a set records it immediately.
class OpenBandStrengthLive extends StatefulWidget {
  final OpenBandRepository repository;
  final WorkoutTemplate? template;
  final bool resume;
  final VoidCallback? onFinished;
  final DateTime Function() now;

  /// Start the [template] once. Do not use this to reopen a running session.
  const OpenBandStrengthLive({
    super.key,
    required this.repository,
    required WorkoutTemplate this.template,
    this.onFinished,
    this.now = DateTime.now,
  }) : resume = false;

  /// Bind the already-running Alpin session. Never calls start.
  const OpenBandStrengthLive.resume({
    super.key,
    required this.repository,
    this.onFinished,
    this.now = DateTime.now,
  }) : template = null,
       resume = true;

  @override
  State<OpenBandStrengthLive> createState() => _OpenBandStrengthLiveState();
}

class _OpenBandStrengthLiveState extends State<OpenBandStrengthLive> {
  ActiveStrengthRuntime? _runtime;
  Map<String, RecordedSet> _previous = const {};
  final Map<String, TextEditingController> _load = {}, _reps = {};
  final Map<String, ExerciseLoadUnit> _unit = {};
  final Map<String, ExerciseSetSide> _side = {};
  final GlobalKey _restBox = GlobalKey();
  double _restH = 0;
  Timer? _tick;
  String? _error;
  Future<void> Function()? _retry;
  bool _busy = false;
  int _guardDepth = 0;
  bool _startAttempted = false;
  bool _finishing = false;

  bool get _locked => _busy || _finishing;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    unawaited(_open());
  }

  @override
  void dispose() {
    _tick?.cancel();
    for (final c in [..._load.values, ..._reps.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _open() async {
    if (widget.resume) {
      _retry = _readExisting;
      await _readExisting();
      return;
    }
    _retry = _recoverStart;
    if (_startAttempted) {
      await _recoverStart();
      return;
    }
    _startAttempted = true;
    await _startOnce();
  }

  Future<void> _startOnce() async {
    final template = widget.template;
    if (template == null) {
      _show('Einheit konnte nicht gestartet werden.');
      return;
    }
    _retry = _recoverStart;
    await _guard(() async {
      try {
        await widget.repository.startStrengthSession(template);
      } on WorkoutBusy {
        _retry = _readExisting;
        await _readExisting();
        return;
      }
      _retry = _readExisting;
      await _readExisting();
    }, failed: 'Einheit konnte nicht gestartet werden.');
  }

  /// Read first. Start only when nothing is active. Never replay a start
  /// whose write may already have committed.
  Future<void> _recoverStart() async {
    final template = widget.template;
    if (template == null) {
      _retry = _readExisting;
      await _readExisting();
      return;
    }
    _retry = _recoverStart;
    var snapshot = false;
    ActiveStrengthRuntime? runtime;
    await _guard(() async {
      runtime = await widget.repository.readActiveStrengthSession();
      snapshot = true;
    }, failed: 'Einheit konnte nicht gelesen werden.');
    if (!snapshot || !mounted) {
      _retry = _recoverStart;
      return;
    }
    switch (runtime!) {
      case ActiveStrengthSession():
        await _bind(runtime as ActiveStrengthSession);
      case CorruptActiveStrength():
      case LegacyActiveStrength():
        if (!mounted) return;
        setState(() {
          _runtime = runtime;
          _error = 'Einheit konnte nicht gelesen werden.';
          _retry = _readExisting;
        });
      case NoActiveStrength():
        await _startOnce();
    }
  }

  Future<void> _readExisting() async {
    _retry = _readExisting;
    await _guard(() async {
      final runtime = await widget.repository.readActiveStrengthSession();
      if (!mounted) return;
      switch (runtime) {
        case NoActiveStrength():
          setState(() {
            _runtime = runtime;
            _error = null;
            _retry = null;
          });
        case CorruptActiveStrength():
          setState(() {
            _runtime = runtime;
            _error = 'Einheit konnte nicht gelesen werden.';
            _retry = _readExisting;
          });
        case LegacyActiveStrength():
          setState(() {
            _runtime = runtime;
            _error = 'Einheit konnte nicht gelesen werden.';
            _retry = _readExisting;
          });
        case ActiveStrengthSession():
          await _bind(runtime);
      }
    }, failed: 'Einheit konnte nicht gelesen werden.');
  }

  Future<void> _bind(ActiveStrengthSession session) async {
    Map<String, RecordedSet> previous = const {};
    try {
      previous = await widget.repository.readPreviousStrengthSets(
        session.sessionId,
      );
    } catch (_) {
      previous = const {};
    }
    if (!mounted) return;
    _ensureControllers(session);
    setState(() {
      _runtime = session;
      _previous = previous;
      _error = null;
      _retry = null;
    });
  }

  void _ensureControllers(ActiveStrengthSession session) {
    for (final e in [...session.plan.exercises, ...session.added]) {
      for (final s in e.sets) {
        _unit.putIfAbsent(s.id, () => s.load?.unit ?? ExerciseLoadUnit.kg);
        _side.putIfAbsent(s.id, () => s.load?.side ?? ExerciseSetSide.both);
        _load.putIfAbsent(
          s.id,
          () => TextEditingController(text: _setLoadText(s)),
        );
        _reps.putIfAbsent(
          s.id,
          () => TextEditingController(
            text: (s.reps ?? s.seconds)?.toString() ?? '',
          ),
        );
      }
    }
  }

  Future<void> _guard(
    Future<void> Function() op, {
    required String failed,
  }) async {
    if (_guardDepth == 0 && _locked) return;
    final mine = _guardDepth == 0;
    _guardDepth++;
    if (mine && mounted) setState(() => _busy = true);
    try {
      await op();
    } catch (_) {
      _show(failed);
    } finally {
      _guardDepth--;
      if (mine && mounted) setState(() => _busy = false);
    }
  }

  void _show(String error) {
    if (!mounted) return;
    setState(() => _error = error);
  }

  Future<void> _run(
    Future<void> Function() op, {
    String failed = 'Speichern fehlgeschlagen',
  }) async {
    if (_locked) return;
    _retry = () => _run(op, failed: failed);
    await _guard(() async {
      await op();
      _retry = _readExisting;
      await _readExisting();
    }, failed: failed);
  }

  ActiveStrengthSession? get _session => switch (_runtime) {
    final ActiveStrengthSession s => s,
    _ => null,
  };

  OBLiveRow? get _active {
    final session = _session;
    if (session == null) return null;
    for (final block in _blocksFor(session, _previous)) {
      for (final row in block.rows) {
        if (row.recorded == null && !row.skipped) return row;
      }
    }
    return null;
  }

  Future<void> _confirm(OBLiveRow row) async {
    final session = _session;
    if (session == null) return;
    final showLoad = showsExternalLoad(
      definition: frozenDefinition(
        load: row.set.load,
        typed: isTypedLoadRow(
          load: row.set.load,
          historicKg: row.set.loadKg,
          definition: row.exercise.definition,
        ),
        definition: row.exercise.definition,
      ),
      load: row.set.load,
      timed: row.slot.timed,
      historicLoadKg: row.set.loadKg,
    );
    final typed = isTypedLoadRow(
      load: row.set.load,
      historicKg: row.set.loadKg,
      definition: row.exercise.definition,
    );
    final def = frozenDefinition(
      load: row.set.load,
      typed: typed,
      definition: row.exercise.definition,
    );
    final unsupported = hasUnsupportedLoadMetadata(
      definition: def,
      load: row.set.load,
    );
    ({double? value, bool bad}) parsed = (value: null, bad: false);
    if (showLoad && !unsupported) {
      parsed = _parseLoad(_load[row.set.id]?.text ?? '');
      if (parsed.bad) {
        _show('Gewicht ist keine Zahl.');
        return;
      }
    }
    final count = int.tryParse((_reps[row.set.id]?.text ?? '').trim());
    if (count == null) {
      _show(
        row.slot.timed
            ? 'Sekunden fehlen.'
            : 'Wiederholungen oder Sekunden fehlen.',
      );
      return;
    }
    final chosenUnit =
        _unit[row.set.id] ?? row.set.load?.unit ?? ExerciseLoadUnit.kg;
    final chosenSide =
        _side[row.set.id] ?? row.set.load?.side ?? ExerciseSetSide.both;
    final source = row.set.load;
    final displayText = _load[row.set.id]?.text ?? '';
    final unchangedOriginal =
        source != null &&
        !unsupported &&
        (source.unit ?? ExerciseLoadUnit.kg) == chosenUnit &&
        (source.side ?? ExerciseSetSide.both) == chosenSide &&
        (!showLoad || displayText == formatOriginalLoadValue(source.value));
    final unchangedHistoric =
        !capturesOriginalLoad(
          typed: typed,
          existing: source,
          definition: def,
        ) &&
        source == null &&
        row.set.loadKg != null &&
        displayText == formatOriginalLoadValue(row.set.loadKg);
    OriginalLoadInput? captured;
    try {
      captured = unchangedOriginal
          ? source
          : captureOriginalLoad(
              definition: row.exercise.definition,
              existing: source,
              typed: typed,
              value: parsed.value,
              unit: chosenUnit,
              side: chosenSide,
            );
    } catch (_) {
      _show('Gewicht ist keine Zahl.');
      return;
    }
    final loadKg = unsupported || unchangedOriginal || unchangedHistoric
        ? row.set.loadKg
        : captured == null || captured.basis == null
        ? parsed.value
        : resolvedLoadKg(captured, null);
    final recorded = RecordedSet(
      exerciseKey: row.exercise.exerciseKey,
      setIndex: row.slot.setIndex,
      reps: row.slot.timed ? null : count,
      seconds: row.slot.timed ? count : null,
      loadKg: loadKg,
      at: widget.now(),
      plannedSetId: row.set.id,
      exerciseId: row.exercise.id,
      restSec: row.set.restSec,
      load: captured,
      definition: row.exercise.definition,
    );
    await _run(() => widget.repository.recordSet(session.sessionId, recorded));
  }

  Future<void> _skip(OBLiveRow row) async {
    final session = _session;
    if (session == null) return;
    await _run(
      () => widget.repository.skipPlannedSet(session.sessionId, row.set.id),
    );
  }

  Future<void> _add(PlannedExercise exercise) async {
    final session = _session;
    if (session == null) return;
    final id = _newSetId(session, exercise.id);
    final last = [
      for (final e in [...session.plan.exercises, ...session.added])
        if (e.id == exercise.id) ...e.sets,
    ].lastOrNull;
    final added = PlannedSet(
      id: id,
      type: last?.type ?? 'work',
      reps: last?.reps,
      seconds: last?.seconds,
      restSec: last?.restSec,
      loadKg: last?.loadKg,
      mode: last?.mode,
      load: last?.load,
    );
    await _run(
      () => widget.repository.addPlannedSet(session.sessionId, exercise, added),
    );
  }

  Future<void> _extendRest() async {
    final session = _session;
    if (session == null) return;
    await _run(() => widget.repository.extendRest(session.sessionId));
  }

  Future<void> _skipRest() async {
    final session = _session;
    if (session == null) return;
    await _run(() => widget.repository.skipRest(session.sessionId));
  }

  Future<void> _finish() async {
    final session = _session;
    if (session == null || _locked) return;
    setState(() => _finishing = true);
    _retry = _finish;
    try {
      await widget.repository.finishStrengthSession(session.sessionId);
      widget.onFinished?.call();
      if (mounted) Navigator.of(context).maybePop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _finishing = false;
        _error = 'Speichern fehlgeschlagen';
      });
    }
  }

  Future<void> _openMenu(_LiveBlock block) async {
    if (_locked) return;
    final next = block.rows.cast<OBLiveRow?>().firstWhere(
      (r) => r!.recorded == null && !r.skipped,
      orElse: () => null,
    );
    final unitChoice =
        block.rows.every((r) {
          if (r.recorded != null) return true;
          final typed = isTypedLoadRow(
            load: r.set.load,
            historicKg: r.set.loadKg,
            definition: block.exercise.definition,
          );
          return showsUnitChoice(
            definition: frozenDefinition(
              load: r.set.load,
              typed: typed,
              definition: block.exercise.definition,
            ),
            load: r.set.load,
          );
        }) &&
        block.rows.every((r) => r.recorded == null) &&
        block.rows.any(
          (r) =>
              r.set.load?.basis != null ||
              (r.set.load == null &&
                  r.set.loadKg == null &&
                  block.exercise.definition?.loadBasis != null),
        );
    if (next == null && !unitChoice) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: OB.of(context).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AlpRadius.card),
        ),
      ),
      builder: (ctx) {
        final p = OB.of(ctx);
        final unit = next == null
            ? ExerciseLoadUnit.kg
            : _unit[next.set.id] ?? next.set.load?.unit ?? ExerciseLoadUnit.kg;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  block.exercise.name,
                  style: p
                      .text(18, weight: FontWeight.w600)
                      .copyWith(height: 24 / 18),
                ),
                const SizedBox(height: 12),
                if (next != null)
                  SizedBox(
                    height: 48,
                    width: double.infinity,
                    child: InkWell(
                      onTap: () => Navigator.pop(ctx, 'skip'),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Satz ${next.slot.setIndex} überspringen',
                          style: p.text(15).copyWith(height: 20 / 15),
                        ),
                      ),
                    ),
                  ),
                if (unitChoice)
                  SizedBox(
                    height: 48,
                    width: double.infinity,
                    child: InkWell(
                      onTap: () => Navigator.pop(ctx, 'unit'),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Einheit',
                              style: p.text(15).copyWith(height: 20 / 15),
                            ),
                          ),
                          Text(
                            loadUnitLabel(unit),
                            style: p
                                .text(15, color: p.muted)
                                .copyWith(height: 20 / 15),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted) return;
    if (choice == 'skip' && next != null) {
      await _skip(next);
      return;
    }
    if (choice == 'unit') {
      final picked = await showExerciseInputChoice<ExerciseLoadUnit>(
        context: context,
        title: 'Einheit',
        choices: exerciseUnitChoices,
        selected: next == null
            ? ExerciseLoadUnit.kg
            : _unit[next.set.id] ?? next.set.load?.unit ?? ExerciseLoadUnit.kg,
      );
      if (!mounted || picked == null) return;
      _changeUnit(block, picked);
    }
  }

  void _changeUnit(_LiveBlock block, ExerciseLoadUnit picked) {
    var changed = false;
    for (final row in block.rows) {
      final typed = isTypedLoadRow(
        load: row.set.load,
        historicKg: row.set.loadKg,
        definition: block.exercise.definition,
      );
      final def = frozenDefinition(
        load: row.set.load,
        typed: typed,
        definition: block.exercise.definition,
      );
      if (row.recorded != null ||
          hasUnsupportedLoadMetadata(definition: def, load: row.set.load) ||
          !showsUnitChoice(definition: def, load: row.set.load)) {
        continue;
      }
      final prior =
          _unit[row.set.id] ?? row.set.load?.unit ?? ExerciseLoadUnit.kg;
      if (picked == prior) continue;
      final controller = _load[row.set.id];
      final parsed = _parseLoad(controller?.text ?? '');
      if (!parsed.bad && parsed.value != null && controller != null) {
        controller.text = formatOriginalLoadValue(
          convertLoadValue(parsed.value!, prior, picked),
        );
      }
      _unit[row.set.id] = picked;
      changed = true;
    }
    if (changed) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final now = widget.now();
    final session = _session;
    final rest = session == null ? null : _restView(session, now);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final restBottom = keyboard > 0 ? 8.0 : safeBottom;
    final stacked = _largeText(context);
    final restBar = rest == null
        ? 0.0
        : (stacked && _restH > 0
              ? _restH
              : 4 +
                    math.max(
                      56.0,
                      MediaQuery.textScalerOf(context).scale(56) +
                          (stacked
                              ? MediaQuery.textScalerOf(context).scale(48)
                              : 0),
                    ));
    final restReserve = rest == null ? 24.0 : restBar + restBottom + 16;
    if (rest != null && stacked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final box = _restBox.currentContext?.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return;
        if ((box.size.height - _restH).abs() < 0.5) return;
        setState(() => _restH = box.size.height);
      });
    }
    final elapsed = session == null
        ? Duration.zero
        : now.difference(session.startedAt);
    final locked = _locked;
    return Scaffold(
      backgroundColor: p.canvas,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: _LiveBar(
                    title: session?.plan.name ?? '',
                    elapsed: elapsed.isNegative ? 0 : elapsed.inSeconds,
                    finishing: locked || session == null,
                    onCollapse: () => Navigator.of(context).maybePop(),
                    onFinish: _finish,
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, restReserve),
                    children: [
                      if (_error case final err?)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: OBSettingsErrorCard(
                            message: err,
                            retryLabel: 'Erneut',
                            onRetry: _retry == null || locked
                                ? null
                                : () => unawaited(_retry!()),
                          ),
                        ),
                      ..._body(p, session, locked: locked),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (rest != null) ...[
            if (restBottom > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: restBottom,
                child: ColoredBox(
                  key: const ValueKey('rest-safe-mask'),
                  color: p.canvas,
                ),
              ),
            Positioned(
              left: 16,
              right: 16,
              bottom: restBottom,
              child: KeyedSubtree(
                key: _restBox,
                child: OBRestTimer(
                  remaining: rest.remaining,
                  total: rest.total,
                  enabled: !locked,
                  onAdd: _extendRest,
                  onSkip: _skipRest,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickSide(OBLiveRow row) async {
    if (_locked) return;
    if (row.recorded != null || row.skipped) return;
    final current =
        _side[row.set.id] ?? row.set.load?.side ?? ExerciseSetSide.both;
    final picked = await showExerciseInputChoice<ExerciseSetSide>(
      context: context,
      title: 'Seite',
      choices: exerciseSideChoices,
      selected: current,
    );
    if (!mounted || picked == null) return;
    setState(() => _side[row.set.id] = picked);
  }

  List<Widget> _body(
    OB p,
    ActiveStrengthSession? session, {
    required bool locked,
  }) {
    if (_runtime is NoActiveStrength) {
      return [
        Text('Keine laufende Einheit.', style: p.text(14, color: p.muted)),
      ];
    }
    if (session == null) {
      if (_error != null) return const [];
      return const [Center(child: CircularProgressIndicator.adaptive())];
    }
    final activeId = _active?.set.id;
    return [
      for (final block in _blocksFor(session, _previous))
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: OBExerciseBlock(
            exercise: block.exercise,
            rows: block.rows,
            activeSetId: activeId,
            load: _load,
            reps: _reps,
            unit: _unit,
            side: _side,
            onConfirm: _confirm,
            onSide: _pickSide,
            enabled: !locked,
            onMenu: locked || block.complete ? null : () => _openMenu(block),
            onAdd: locked ? null : () => _add(block.exercise),
          ),
        ),
    ];
  }
}

class _LiveBar extends StatelessWidget {
  final String title;
  final int elapsed;
  final bool finishing;
  final VoidCallback onCollapse, onFinish;
  const _LiveBar({
    required this.title,
    required this.elapsed,
    required this.finishing,
    required this.onCollapse,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final stacked = _largeText(context);
    final title = Text(
      this.title,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: p
          .text(18, weight: FontWeight.w700, display: true)
          .copyWith(height: 22 / 18, letterSpacing: -0.36),
    );
    final elapsedRow = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: p.strain, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          _elapsedClock(elapsed),
          style: p
              .text(14, weight: FontWeight.w600, display: true, color: p.muted)
              .copyWith(height: 18 / 14, letterSpacing: 0.28),
        ),
      ],
    );
    final collapse = _CircleIcon(
      tooltip: 'Einklappen',
      icon: LucideIcons.chevronDown,
      onPressed: onCollapse,
    );
    final done = SizedBox(
      height: 44,
      child: FilledButton(
        onPressed: finishing ? null : onFinish,
        style: FilledButton.styleFrom(
          backgroundColor: p.ink,
          foregroundColor: p.dark ? p.canvas : Colors.white,
          disabledBackgroundColor: p.ink.withValues(alpha: 0.4),
          disabledForegroundColor: p.dark ? p.canvas : Colors.white,
          animationDuration: Duration.zero,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(60),
          ),
          textStyle: p
              .text(
                15,
                weight: FontWeight.w600,
                color: p.dark ? p.canvas : Colors.white,
              )
              .copyWith(height: 18 / 15),
        ),
        child: const Text('Fertig', key: ValueKey('finish-live')),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: stacked
          ? Column(
              children: [
                Row(children: [collapse, const Spacer(), done]),
                title,
                const SizedBox(height: 4),
                elapsedRow,
              ],
            )
          : Row(
              children: [
                collapse,
                Expanded(
                  child: Column(
                    children: [title, const SizedBox(height: 1), elapsedRow],
                  ),
                ),
                done,
              ],
            ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  const _CircleIcon({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return SizedBox(
      width: 44,
      height: 44,
      child: Material(
        color: p.card,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
          icon: Icon(icon, size: 20, color: p.ink),
        ),
      ),
    );
  }
}

class OBExerciseBlock extends StatelessWidget {
  final PlannedExercise exercise;
  final List<OBLiveRow> rows;
  final String? activeSetId;
  final Map<String, TextEditingController> load, reps;
  final Map<String, ExerciseSetSide> side;
  final Map<String, ExerciseLoadUnit> unit;
  final ValueChanged<OBLiveRow> onConfirm;
  final ValueChanged<OBLiveRow>? onSide;
  final VoidCallback? onMenu, onAdd;
  final bool enabled;
  const OBExerciseBlock({
    super.key,
    required this.exercise,
    required this.rows,
    required this.activeSetId,
    required this.load,
    required this.reps,
    required this.unit,
    required this.side,
    required this.onConfirm,
    this.onSide,
    this.onMenu,
    this.onAdd,
    this.enabled = true,
  });

  Widget _addSetButton(OB p, VoidCallback? onAdd) {
    return Material(
      color: p.well,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onAdd,
        borderRadius: BorderRadius.circular(12),
        child: Tooltip(
          message: 'Satz hinzufügen',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.plus, size: 16, color: p.ink),
              const SizedBox(width: 6),
              Text(
                'Satz',
                style: p
                    .text(14, weight: FontWeight.w600)
                    .copyWith(height: 18 / 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final timed = rows.any((r) => r.slot.timed);
    final showLoad = rows.any((r) {
      final loadInput = r.recorded?.load ?? r.set.load;
      final kg = r.recorded?.loadKg ?? r.set.loadKg;
      final typed = isTypedLoadRow(
        load: loadInput,
        historicKg: kg,
        definition: exercise.definition,
      );
      return showsExternalLoad(
        definition: frozenDefinition(
          load: loadInput,
          typed: typed,
          definition: exercise.definition,
        ),
        load: loadInput,
        timed: r.slot.timed,
        historicLoadKg: kg,
      );
    });
    final large = _largeText(context);
    final labels = exerciseBlockLoadLabels(
      definition: exercise.definition,
      rows: [
        for (final r in rows)
          ExerciseLoadRowView(
            load: r.recorded?.load ?? r.set.load,
            typed: isTypedLoadRow(
              load: r.recorded?.load ?? r.set.load,
              historicKg: r.recorded?.loadKg ?? r.set.loadKg,
              definition: exercise.definition,
            ),
            historicKg: r.recorded?.loadKg ?? r.set.loadKg,
            chosenUnit:
                unit[r.set.id] ?? r.recorded?.load?.unit ?? r.set.load?.unit,
          ),
      ],
    );
    final mixedUnits = labels.mixedUnits;
    final loadHeader = labels.loadHeader;
    final caption = labels.caption;
    final subtitle = (caption != null && caption.isNotEmpty)
        ? caption
        : _exerciseSubtitle(exercise);
    Widget head(String t, {double? width, int flex = 0}) {
      final text = Text(
        t,
        textAlign: width == null ? TextAlign.left : TextAlign.center,
        maxLines: 1,
        style: p
            .text(11, weight: FontWeight.w600, color: p.muted)
            .copyWith(height: 14 / 11, letterSpacing: 0.44),
      );
      if (flex > 0) return Expanded(child: text);
      return SizedBox(
        width: width,
        child: FittedBox(fit: BoxFit.scaleDown, child: text),
      );
    }

    return OBCard(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exercise.name,
                        style: p
                            .text(16, weight: FontWeight.w600, color: p.ink)
                            .copyWith(height: 20 / 16),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: p
                              .text(13, weight: FontWeight.w500, color: p.muted)
                              .copyWith(height: 18 / 13),
                        ),
                    ],
                  ),
                ),
                if (onMenu != null)
                  IconButton(
                    tooltip: 'Übungsmenü',
                    onPressed: onMenu,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                    icon: Icon(LucideIcons.ellipsis, size: 20, color: p.muted),
                  ),
              ],
            ),
          ),
          if (!large)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 24),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    head('SATZ', width: 36),
                    head('ZULETZT', flex: 1),
                    if (timed && showLoad) ...[
                      head(loadHeader, width: 76),
                      head('SEK', width: 64),
                    ] else if (timed) ...[
                      head('SEK', width: 76),
                      head('', width: 64),
                    ] else if (showLoad) ...[
                      head(loadHeader, width: 76),
                      head('WDH', width: 64),
                    ] else
                      head('WDH', width: 64),
                    SizedBox(
                      width: 44,
                      child: Icon(LucideIcons.check, size: 14, color: p.muted),
                    ),
                  ],
                ),
              ),
            ),
          for (final row in rows)
            _SetRow(
              row: row,
              state: row.skipped
                  ? _SetState.skipped
                  : row.recorded != null
                  ? _SetState.done
                  : row.set.id == activeSetId
                  ? _SetState.active
                  : _SetState.planned,
              load: load[row.set.id],
              reps: reps[row.set.id],
              unit:
                  unit[row.set.id] ??
                  row.recorded?.load?.unit ??
                  row.set.load?.unit ??
                  ExerciseLoadUnit.kg,
              side:
                  side[row.set.id] ??
                  row.recorded?.load?.side ??
                  row.set.load?.side ??
                  ExerciseSetSide.both,
              enabled: enabled,
              showUnitInValue: mixedUnits,
              mixedSemantics: labels.mixedSemantics,
              onConfirm: () => onConfirm(row),
              onSide: onSide == null ? null : () => onSide!(row),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
            child: large
                ? SizedBox(
                    width: double.infinity,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 40),
                      child: _addSetButton(p, onAdd),
                    ),
                  )
                : SizedBox(
                    height: 40,
                    width: double.infinity,
                    child: _addSetButton(p, onAdd),
                  ),
          ),
        ],
      ),
    );
  }
}

enum _SetState { done, active, planned, skipped }

class _SetRow extends StatelessWidget {
  final OBLiveRow row;
  final _SetState state;
  final TextEditingController? load, reps;
  final ExerciseLoadUnit unit;
  final ExerciseSetSide side;
  final VoidCallback onConfirm;
  final VoidCallback? onSide;
  final bool enabled;
  final bool showUnitInValue;
  final bool mixedSemantics;
  const _SetRow({
    required this.row,
    required this.state,
    required this.load,
    required this.reps,
    required this.unit,
    required this.side,
    required this.onConfirm,
    this.onSide,
    this.enabled = true,
    this.showUnitInValue = false,
    this.mixedSemantics = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final timed = row.slot.timed;
    final muted = state == _SetState.planned;
    final ink = muted ? p.muted : p.ink;
    if (_largeText(context)) {
      return _stacked(context, p, timed: timed, ink: ink);
    }
    final rowLoad = row.recorded?.load ?? row.set.load;
    final rowKg = row.recorded?.loadKg ?? row.set.loadKg;
    final typed = isTypedLoadRow(
      load: rowLoad,
      historicKg: rowKg,
      definition: row.exercise.definition,
    );
    final def = frozenDefinition(
      load: rowLoad,
      typed: typed,
      definition: row.exercise.definition,
    );
    final showLoad = showsExternalLoad(
      definition: def,
      load: rowLoad,
      timed: timed,
      historicLoadKg: rowKg,
    );
    final showSide =
        state != _SetState.skipped &&
        showsSideControl(definition: def, load: rowLoad);
    final rowCaption = mixedSemantics
        ? exerciseRowLoadCaption(
            definition: row.exercise.definition,
            load: rowLoad,
            typed: typed,
            historicLoadKg: rowKg,
          )
        : null;
    final loadEditable = !hasUnsupportedLoadMetadata(
      definition: def,
      load: row.set.load,
    );
    final previous = _livePreviousLabel(
      previous: row.previous,
      current: row.set,
      definition: row.exercise.definition,
      timed: timed,
      currentUnit: unit,
    );
    Widget number(String t, {double width = 76, Color? color}) => SizedBox(
      width: width,
      child: Text(
        t,
        textAlign: TextAlign.center,
        style: p
            .text(
              16,
              weight: FontWeight.w700,
              display: true,
              color: color ?? ink,
            )
            .copyWith(height: 20 / 16),
      ),
    );
    Widget field({
      required TextEditingController? controller,
      required double width,
      required bool bordered,
      bool decimal = true,
      bool editable = true,
      bool showUnit = false,
    }) {
      final h = math.max(36.0, MediaQuery.textScalerOf(context).scale(36));
      return SizedBox(
        width: width,
        child: Center(
          child: Container(
            width: width - 8,
            constraints: BoxConstraints(minHeight: h),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.well,
              borderRadius: BorderRadius.circular(10),
              border: bordered ? Border.all(color: p.ink, width: 1.5) : null,
            ),
            child: TextField(
              key: ValueKey('field-${row.set.id}-$width'),
              controller: controller,
              enabled: state == _SetState.active && enabled && editable,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.numberWithOptions(decimal: decimal),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  decimal ? RegExp(r'[\d,.\-]') : RegExp(r'\d'),
                ),
              ],
              style: p
                  .text(16, weight: FontWeight.w700, display: true)
                  .copyWith(height: 20 / 16),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                suffixText: showUnit ? ' ${loadUnitLabel(unit)}' : null,
                suffixStyle: p
                    .text(16, weight: FontWeight.w700, display: true)
                    .copyWith(height: 20 / 16),
                contentPadding: showUnit
                    ? const EdgeInsets.fromLTRB(8, 8, 8, 8)
                    : const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ),
      );
    }

    Widget check() {
      final Color fill;
      final Color mark;
      switch (state) {
        case _SetState.done:
          fill = p.recovery;
          mark = Colors.white;
        case _SetState.active:
          fill = p.ink;
          mark = p.dark ? p.canvas : Colors.white;
        case _SetState.planned:
        case _SetState.skipped:
          fill = p.well;
          mark = p.gap;
      }
      return SizedBox(
        width: 44,
        height: 44,
        child: IconButton(
          key: ValueKey('confirm-${row.set.id}'),
          tooltip: 'Satz ${row.slot.setIndex} bestätigen',
          onPressed: state == _SetState.active && enabled ? onConfirm : null,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
          icon: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(LucideIcons.check, size: 16, color: mark),
          ),
        ),
      );
    }

    String shownLoad(OriginalLoadInput? original, double? kg) {
      final value = _setLoadTextFrom(original, kg);
      if (!showUnitInValue || value.isEmpty) return value;
      if (hasUnsupportedLoadMetadata(load: original)) return value;
      return '$value ${loadUnitLabel(original?.unit ?? unit)}';
    }

    final values = switch (state) {
      _SetState.done => (
        load: shownLoad(row.recorded?.load, row.recorded?.loadKg),
        count: (row.recorded?.reps ?? row.recorded?.seconds)?.toString() ?? '—',
      ),
      _SetState.planned => (
        load: shownLoad(row.set.load, row.set.loadKg),
        count: (row.set.reps ?? row.set.seconds)?.toString() ?? '',
      ),
      _SetState.active || _SetState.skipped => (load: '', count: ''),
    };

    final rowBody = ColoredBox(
      color: state == _SetState.done ? p.recoveryTint : Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: state == _SetState.active ? 48 : 44,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  '${row.slot.setIndex}',
                  style: p
                      .text(
                        15,
                        weight: FontWeight.w700,
                        display: true,
                        color: ink,
                      )
                      .copyWith(height: 18 / 15),
                ),
              ),
              Expanded(
                child: Text(
                  previous,
                  style: p
                      .text(
                        13,
                        weight: state == _SetState.skipped
                            ? FontWeight.w400
                            : FontWeight.w500,
                        color: state == _SetState.skipped ? p.ink : p.muted,
                      )
                      .copyWith(height: 18 / 13),
                ),
              ),
              if (state == _SetState.skipped)
                SizedBox(
                  width: 184,
                  child: Text(
                    'Übersprungen',
                    textAlign: TextAlign.center,
                    style: p.text(13).copyWith(height: 18 / 13),
                  ),
                )
              else ...[
                if (timed && showLoad) ...[
                  if (state == _SetState.active)
                    field(
                      controller: load,
                      width: 76,
                      bordered: true,
                      editable: loadEditable,
                      showUnit: showUnitInValue,
                    )
                  else
                    number(values.load.isEmpty ? '—' : values.load),
                  if (state == _SetState.active)
                    field(
                      controller: reps,
                      width: 64,
                      bordered: false,
                      decimal: false,
                    )
                  else
                    number(
                      values.count.isEmpty ? '—' : values.count,
                      width: 64,
                    ),
                ] else if (timed) ...[
                  if (state == _SetState.active)
                    field(
                      controller: reps,
                      width: 76,
                      bordered: true,
                      decimal: false,
                    )
                  else
                    number(values.count.isEmpty ? '—' : values.count),
                  const SizedBox(width: 64),
                ] else if (showLoad) ...[
                  if (state == _SetState.active)
                    field(
                      controller: load,
                      width: 76,
                      bordered: true,
                      editable: loadEditable,
                      showUnit: showUnitInValue,
                    )
                  else
                    number(values.load.isEmpty ? '—' : values.load),
                  if (state == _SetState.active)
                    field(
                      controller: reps,
                      width: 64,
                      bordered: false,
                      decimal: false,
                    )
                  else
                    number(
                      values.count.isEmpty ? '—' : values.count,
                      width: 64,
                    ),
                ] else ...[
                  if (state == _SetState.active)
                    field(
                      controller: reps,
                      width: 64,
                      bordered: true,
                      decimal: false,
                    )
                  else
                    number(
                      values.count.isEmpty ? '—' : values.count,
                      width: 64,
                    ),
                ],
                check(),
              ],
            ],
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        rowBody,
        if (rowCaption != null || showSide)
          _sideRow(
            p,
            interactive: state == _SetState.active && showSide,
            caption: rowCaption,
            showSide: showSide,
          ),
      ],
    );
  }

  Widget _sideRow(
    OB p, {
    required bool interactive,
    String? caption,
    bool showSide = true,
  }) {
    final captionStyle = p
        .text(13, weight: FontWeight.w500, color: p.muted)
        .copyWith(height: 18 / 13);
    final label = exerciseSideLabel(side);
    final sideChild = Row(
      children: [
        Text(
          label,
          style: p
              .text(13, color: interactive ? p.ink : p.muted)
              .copyWith(height: 18 / 13),
        ),
        if (interactive) ...[
          const SizedBox(width: 6),
          Icon(LucideIcons.chevronDown, size: 16, color: p.muted),
        ],
      ],
    );
    final child = caption == null
        ? sideChild
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(caption, style: captionStyle),
              if (showSide) sideChild,
            ],
          );
    return Padding(
      padding: const EdgeInsets.only(left: 50),
      child: interactive
          ? InkWell(
              key: ValueKey('side-${row.set.id}'),
              onTap: enabled && showSide ? onSide : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: caption == null
                        ? EdgeInsets.zero
                        : const EdgeInsets.symmetric(vertical: 4),
                    child: child,
                  ),
                ),
              ),
            )
          : ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: caption != null && showSide ? 44 : 24,
              ),
              child: Align(alignment: Alignment.centerLeft, child: child),
            ),
    );
  }

  Widget _stacked(
    BuildContext context,
    OB p, {
    required bool timed,
    required Color ink,
  }) {
    final scaler = MediaQuery.textScalerOf(context);
    final valueH = scaler.scale(32);
    final previous =
        'Zuletzt ${_livePreviousLabel(previous: row.previous, current: row.set, definition: row.exercise.definition, timed: timed, currentUnit: unit)}';
    final rowLoad = row.recorded?.load ?? row.set.load;
    final rowKg = row.recorded?.loadKg ?? row.set.loadKg;
    final typed = isTypedLoadRow(
      load: rowLoad,
      historicKg: rowKg,
      definition: row.exercise.definition,
    );
    final def = frozenDefinition(
      load: rowLoad,
      typed: typed,
      definition: row.exercise.definition,
    );
    final showLoad = showsExternalLoad(
      definition: def,
      load: rowLoad,
      timed: timed,
      historicLoadKg: rowKg,
    );
    final showSide =
        state != _SetState.skipped &&
        showsSideControl(definition: def, load: rowLoad);
    final rowCaption = mixedSemantics
        ? exerciseRowLoadCaption(
            definition: row.exercise.definition,
            load: rowLoad,
            typed: typed,
            historicLoadKg: rowKg,
          )
        : null;
    final loadEditable = !hasUnsupportedLoadMetadata(
      definition: def,
      load: row.set.load,
    );
    final values = switch (state) {
      _SetState.done => (
        load: _setLoadTextFrom(row.recorded?.load, row.recorded?.loadKg),
        count: (row.recorded?.reps ?? row.recorded?.seconds)?.toString() ?? '—',
      ),
      _SetState.planned => (
        load: _setLoadTextFrom(row.set.load, row.set.loadKg),
        count: (row.set.reps ?? row.set.seconds)?.toString() ?? '',
      ),
      _SetState.active || _SetState.skipped => (load: '', count: ''),
    };
    Widget well({required Widget child, required bool bordered}) {
      return Container(
        constraints: BoxConstraints(minHeight: valueH),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: p.well,
          borderRadius: BorderRadius.circular(10),
          border: bordered ? Border.all(color: p.ink, width: 1.5) : null,
        ),
        child: child,
      );
    }

    Widget valueText(String t) => Text(
      t,
      textAlign: TextAlign.center,
      style: p
          .text(16, weight: FontWeight.w700, display: true, color: ink)
          .copyWith(height: 40 / 32),
    );

    Widget field({
      required TextEditingController? controller,
      required bool bordered,
      required String kind,
      bool decimal = true,
      bool editable = true,
    }) {
      return well(
        bordered: bordered,
        child: TextField(
          key: ValueKey('field-${row.set.id}-$kind'),
          controller: controller,
          enabled: state == _SetState.active && enabled && editable,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.numberWithOptions(decimal: decimal),
          inputFormatters: [
            FilteringTextInputFormatter.allow(
              decimal ? RegExp(r'[\d,.\-]') : RegExp(r'\d'),
            ),
          ],
          style: p
              .text(16, weight: FontWeight.w700, display: true)
              .copyWith(height: 40 / 32),
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 8),
          ),
        ),
      );
    }

    Widget labeled(String label, Widget value) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: p.text(10, color: p.muted).copyWith(height: 28 / 20),
            ),
            const SizedBox(height: 6),
            value,
          ],
        ),
      );
    }

    Widget check() {
      final Color fill;
      final Color mark;
      switch (state) {
        case _SetState.done:
          fill = p.recovery;
          mark = Colors.white;
        case _SetState.active:
          fill = p.ink;
          mark = p.dark ? p.canvas : Colors.white;
        case _SetState.planned:
        case _SetState.skipped:
          fill = p.well;
          mark = p.gap;
      }
      return SizedBox(
        width: 44,
        height: valueH,
        child: Center(
          child: SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              key: ValueKey('confirm-${row.set.id}'),
              tooltip: 'Satz ${row.slot.setIndex} bestätigen',
              onPressed: state == _SetState.active && enabled
                  ? onConfirm
                  : null,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              icon: Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(LucideIcons.check, size: 16, color: mark),
              ),
            ),
          ),
        ),
      );
    }

    final List<Widget> cells;
    if (state == _SetState.skipped) {
      cells = [
        Expanded(
          child: Text(
            'Übersprungen',
            textAlign: TextAlign.center,
            style: p.text(13).copyWith(height: 18 / 13),
          ),
        ),
      ];
    } else if (timed && showLoad) {
      final loadText = values.load.isEmpty ? '—' : values.load;
      final count = values.count.isEmpty ? '—' : values.count;
      cells = [
        labeled(
          loadUnitLabel(unit),
          state == _SetState.active
              ? field(
                  controller: load,
                  bordered: true,
                  kind: 'kg',
                  editable: loadEditable,
                )
              : well(bordered: true, child: valueText(loadText)),
        ),
        labeled(
          'Sek',
          state == _SetState.active
              ? field(
                  controller: reps,
                  bordered: false,
                  kind: 'sek',
                  decimal: false,
                )
              : well(bordered: false, child: valueText(count)),
        ),
      ];
    } else if (timed) {
      final count = values.count.isEmpty ? '—' : values.count;
      cells = [
        labeled(
          'Sek',
          state == _SetState.active
              ? field(
                  controller: reps,
                  bordered: true,
                  kind: 'sek',
                  decimal: false,
                )
              : well(bordered: true, child: valueText(count)),
        ),
      ];
    } else if (showLoad) {
      final loadText = values.load.isEmpty ? '—' : values.load;
      final count = values.count.isEmpty ? '—' : values.count;
      cells = [
        labeled(
          loadUnitLabel(unit),
          state == _SetState.active
              ? field(
                  controller: load,
                  bordered: true,
                  kind: 'kg',
                  editable: loadEditable,
                )
              : well(bordered: true, child: valueText(loadText)),
        ),
        labeled(
          'Wdh.',
          state == _SetState.active
              ? field(
                  controller: reps,
                  bordered: false,
                  kind: 'wdh',
                  decimal: false,
                )
              : well(bordered: false, child: valueText(count)),
        ),
      ];
    } else {
      final count = values.count.isEmpty ? '—' : values.count;
      cells = [
        labeled(
          'Wdh.',
          state == _SetState.active
              ? field(
                  controller: reps,
                  bordered: true,
                  kind: 'wdh',
                  decimal: false,
                )
              : well(bordered: true, child: valueText(count)),
        ),
      ];
    }

    return ColoredBox(
      color: state == _SetState.done ? p.recoveryTint : Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Satz ${row.slot.setIndex}',
                    style: p
                        .text(
                          15,
                          weight: FontWeight.w700,
                          display: true,
                          color: ink,
                        )
                        .copyWith(height: 36 / 30),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    previous,
                    textAlign: TextAlign.end,
                    style: p
                        .text(
                          13,
                          weight: FontWeight.w500,
                          color: state == _SetState.skipped ? p.ink : p.muted,
                        )
                        .copyWith(height: 36 / 26),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < cells.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  cells[i],
                ],
                const SizedBox(width: 12),
                check(),
              ],
            ),
            if (rowCaption != null || showSide) ...[
              const SizedBox(height: 8),
              _sideRow(
                p,
                interactive: state == _SetState.active && showSide,
                caption: rowCaption,
                showSide: showSide,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class OBRestTimer extends StatelessWidget {
  final int remaining;
  final int? total;
  final bool enabled;
  final VoidCallback onAdd, onSkip;
  const OBRestTimer({
    super.key,
    required this.remaining,
    required this.total,
    required this.onAdd,
    required this.onSkip,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final stacked = _largeText(context);
    final showProgress = total != null && total! > 0;
    final factor = showProgress
        ? (1 - remaining / total!).clamp(0.0, 1.0)
        : 0.0;
    Widget pill(String label, VoidCallback onTap) => Material(
      color: p.well,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Center(
              child: Text(
                label,
                style: p
                    .text(14, weight: FontWeight.w600)
                    .copyWith(height: 18 / 14),
              ),
            ),
          ),
        ),
      ),
    );
    final clock = Text(
      _restClock(remaining),
      style: p
          .text(24, weight: FontWeight.w800, display: true)
          .copyWith(height: 28 / 24, letterSpacing: -0.48),
    );
    final pause = Text(
      'Pause',
      style: p
          .text(14, weight: FontWeight.w600, color: p.muted)
          .copyWith(height: 18 / 14),
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        pill('+30 s', onAdd),
        const SizedBox(width: 8),
        pill('Weiter', onSkip),
      ],
    );
    return Material(
      color: p.card,
      elevation: 0,
      shadowColor: Colors.transparent,
      borderRadius: BorderRadius.circular(AlpRadius.row),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AlpRadius.row),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.only(left: 16, right: 8),
                child: stacked
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(child: pause),
                                clock,
                              ],
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: actions,
                            ),
                          ],
                        ),
                      )
                    : Row(
                        children: [
                          Expanded(child: pause),
                          clock,
                          const SizedBox(width: 12),
                          actions,
                        ],
                      ),
              ),
            ),
            if (showProgress)
              SizedBox(
                height: 4,
                width: double.infinity,
                child: ColoredBox(
                  color: p.well,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      key: const ValueKey('rest-elapsed'),
                      widthFactor: factor,
                      heightFactor: 1,
                      child: ColoredBox(color: p.strain),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LiveBlock {
  final PlannedExercise exercise;
  final List<OBLiveRow> rows;
  const _LiveBlock({required this.exercise, required this.rows});
  bool get complete =>
      rows.isNotEmpty && rows.every((r) => r.recorded != null || r.skipped);
}

class OBLiveRow {
  final PlannedExercise exercise;
  final PlannedSet set;
  final StrengthPlanSlot slot;
  final RecordedSet? recorded;
  final RecordedSet? previous;
  final bool skipped;
  const OBLiveRow({
    required this.exercise,
    required this.set,
    required this.slot,
    required this.recorded,
    required this.previous,
    required this.skipped,
  });
}

List<_LiveBlock> _blocksFor(
  ActiveStrengthSession session,
  Map<String, RecordedSet> previous,
) {
  final setById = <String, PlannedSet>{
    for (final e in [...session.plan.exercises, ...session.added])
      for (final s in e.sets) s.id: s,
  };
  final meta = <String, PlannedExercise>{
    for (final e in [...session.plan.exercises, ...session.added]) e.id: e,
  };
  final recorded = {
    for (final s in session.recorded)
      if (s.plannedSetId != null && s.plannedSetId!.isNotEmpty)
        s.plannedSetId!: s,
  };
  final grouped = <String, List<StrengthPlanSlot>>{};
  final order = <String>[];
  for (final slot in strengthPlanSlots(session.plan, session.added)) {
    if (!grouped.containsKey(slot.exerciseId)) order.add(slot.exerciseId);
    (grouped[slot.exerciseId] ??= []).add(slot);
  }
  return [
    for (final id in order)
      if (meta[id] case final exercise?)
        _LiveBlock(
          exercise: exercise,
          rows: [
            for (final slot in grouped[id]!)
              if (setById[slot.plannedSetId] case final set?)
                OBLiveRow(
                  exercise: exercise,
                  set: set,
                  slot: slot,
                  recorded: recorded[slot.plannedSetId],
                  previous: previous[slot.plannedSetId],
                  skipped: session.skippedPlannedSetIds.contains(
                    slot.plannedSetId,
                  ),
                ),
          ],
        ),
  ];
}

({int remaining, int? total})? _restView(
  ActiveStrengthSession session,
  DateTime now,
) {
  final until = session.restEndsAt;
  if (until == null || !until.isAfter(now)) return null;
  final remaining = until.difference(now).inSeconds;
  if (remaining <= 0) return null;
  int? total;
  if (session.recorded case final recorded when recorded.isNotEmpty) {
    final last = recorded.last;
    if (last.restSec != null && last.restSec! > 0) {
      final span = until.difference(last.at).inSeconds;
      if (span > 0) total = span;
    }
  }
  return (remaining: remaining, total: total);
}

String _newSetId(ActiveStrengthSession session, String exerciseId) {
  final used = {
    for (final slot in strengthPlanSlots(session.plan, session.added))
      slot.plannedSetId,
  };
  var n = 1;
  while (used.contains('$exerciseId-extra-$n')) {
    n++;
  }
  return '$exerciseId-extra-$n';
}

bool _largeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1) > 1.3;

String _exerciseSubtitle(PlannedExercise exercise) {
  final rest = [
    for (final s in exercise.sets)
      if (s.restSec != null) s.restSec!,
  ].firstOrNull;
  final pause = rest == null ? null : 'Pause ${_restClock(rest)}';
  final note = exercise.note.trim();
  if (note.isEmpty) return pause ?? '';
  if (pause == null) return note;
  return '$note · $pause';
}

String _previousLabel(RecordedSet? prior, bool timed) {
  if (prior == null) return '—';
  if (timed) {
    if (prior.seconds == null) return '—';
    return prior.loadKg == null
        ? '${prior.seconds}'
        : '${_loadText(prior.loadKg)} × ${prior.seconds}';
  }
  if (prior.reps == null) return '—';
  return prior.loadKg == null
      ? '${prior.reps}'
      : '${_loadText(prior.loadKg)} × ${prior.reps}';
}

String _setLoadText(PlannedSet s) => _setLoadTextFrom(s.load, s.loadKg);

String _setLoadTextFrom(OriginalLoadInput? load, double? loadKg) {
  final original = displayOriginalLoad(
    load: load,
    historicKg: loadKg,
    typed: load?.basis != null,
  );
  if (original != null) return original;
  return formatOriginalLoadValue(loadKg);
}

String _livePreviousLabel({
  required RecordedSet? previous,
  required PlannedSet current,
  ExerciseDefinitionSnapshot? definition,
  required bool timed,
  required ExerciseLoadUnit currentUnit,
}) {
  if (previous == null) return '—';
  if (!originalLoadsComparable(
    previous: previous.load,
    current: current.load,
    definition: definition,
  )) {
    return '—';
  }
  final prevBasis = previous.load?.basis;
  if (prevBasis != null) {
    final count = timed ? previous.seconds : previous.reps;
    if (count == null) return '—';
    if (prevBasis == ExerciseLoadBasis.bodyweight) return '$count';
    final value = previous.load?.value;
    if (value == null) return '$count';
    var shown = formatOriginalLoadValue(value);
    final prevUnit = previous.load?.unit;
    if (prevUnit != null && prevUnit != currentUnit) {
      shown = '$shown ${loadUnitLabel(prevUnit)}';
    }
    return '$shown × $count';
  }
  return _previousLabel(previous, timed);
}

String _loadText(double? kg) {
  if (kg == null) return '';
  final digits = kg == kg.roundToDouble() ? 0 : 1;
  return obNumber(kg, digits: digits);
}

({double? value, bool bad}) _parseLoad(String text) {
  final s = text.trim().replaceAll(RegExp(r'[\s\u00a0]'), '');
  if (s.isEmpty) return (value: null, bad: false);
  if (s.contains(',') && s.contains('.')) return (value: null, bad: true);
  final v = double.tryParse(s.replaceAll(',', '.'));
  if (v == null || !v.isFinite) return (value: null, bad: true);
  return (value: v, bad: false);
}

String _elapsedClock(int seconds) {
  final m = seconds < 0 ? 0 : seconds ~/ 60;
  final s = seconds < 0 ? 0 : seconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

String _restClock(int seconds) {
  final n = seconds < 0 ? 0 : seconds;
  return '${n ~/ 60}:${(n % 60).toString().padLeft(2, '0')}';
}
