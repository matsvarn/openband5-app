import 'package:flutter/material.dart';

import 'domain.dart';
import 'theme.dart';

class OpenBandSleepGoal extends StatefulWidget {
  final OpenBandRepository repository;
  final String day;
  final bool synthetic;
  const OpenBandSleepGoal({
    super.key,
    required this.repository,
    required this.day,
    this.synthetic = false,
  });
  @override
  State<OpenBandSleepGoal> createState() => _OpenBandSleepGoalState();
}

class _OpenBandSleepGoalState extends State<OpenBandSleepGoal> {
  late Future<SleepGoalSnapshot> _data = _read();
  int? _draft;
  String? _error;
  Future<void> Function()? _retry;
  bool _busy = false;

  Future<SleepGoalSnapshot> _read() =>
      widget.repository.readSleepGoal(widget.day).then((s) {
        _draft = s.targetMinutes;
        return s;
      });

  void _reload() {
    setState(() {
      _busy = false;
      _error = null;
      _retry = null;
      _data = _read();
    });
  }

  void _set(int minutes) => setState(
    () => _draft = minutes.clamp(kSleepGoalMinMinutes, kSleepGoalMaxMinutes),
  );

  Future<void> _run(Future<void> Function() write) async {
    setState(() {
      _busy = true;
      _error = null;
      _retry = null;
    });
    try {
      await write();
      if (mounted) _reload();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Speichern fehlgeschlagen';
          _retry = () => _run(write);
        });
      }
    }
  }

  Future<void> _save() {
    final minutes = _draft!;
    return _run(() => widget.repository.saveSleepGoal(widget.day, minutes));
  }

  Future<void> _confirmRemove() async {
    if (_busy) return;
    setState(() => _busy = true);
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Ziel entfernen?'),
        content: Text('Ab ${obDate(widget.day)} gilt kein eigenes Ziel.'),
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
    if (!mounted) return;
    if (yes != true) {
      setState(() => _busy = false);
      return;
    }
    await _run(() => widget.repository.clearSleepGoal(widget.day));
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: FutureBuilder<SleepGoalSnapshot>(
          future: _data,
          builder: (context, snapshot) {
            final goal = snapshot.data;
            final changed =
                goal != null && _draft != null && _draft != goal.targetMinutes;
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    children: [
                      OBPageHeader(
                        title: 'Schlafziel',
                        backText: 'Schlaf',
                        subtitle: 'Ab ${obDate(widget.day)}',
                        infoLabel: 'Schlafziel',
                        onInfo: () => _goalInfo(context, widget.day),
                        bottom: 15,
                      ),
                      if (snapshot.hasError)
                        OBAction('Erneut laden', ink: true, onPressed: _reload)
                      else if (goal == null)
                        const Center(
                          child: CircularProgressIndicator.adaptive(),
                        )
                      else ...[
                        if (_error != null) ...[
                          Text(
                            _error!,
                            style: p
                                .text(14, color: p.danger)
                                .copyWith(height: 18 / 14),
                          ),
                          const SizedBox(height: 12),
                          OBAction(
                            'Erneut versuchen',
                            ink: true,
                            onPressed: _busy || _retry == null ? null : _retry,
                          ),
                          const SizedBox(height: 12),
                        ],
                        _goalCard(p),
                        const SizedBox(height: 10),
                        _estimateCard(p, goal.weekendEstimate),
                        if (goal.targetMinutes != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: TextButton(
                              onPressed: _busy ? null : _confirmRemove,
                              style: TextButton.styleFrom(
                                foregroundColor: p.muted,
                                minimumSize: const Size.fromHeight(48),
                                textStyle: p
                                    .text(14, weight: FontWeight.w500)
                                    .copyWith(height: 18 / 14),
                              ),
                              child: const Text('Ziel entfernen'),
                            ),
                          ),
                        if (widget.synthetic)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              'Synthetische Daten',
                              textAlign: TextAlign.center,
                              style: p
                                  .text(12, color: p.muted)
                                  .copyWith(height: 18 / 12),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                if (goal != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
                    child: SizedBox(
                      height: 54,
                      child: OBAction(
                        'Speichern',
                        ink: true,
                        onPressed: _busy || !changed ? null : _save,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _goalCard(OB p) {
    final draft = _draft;
    Widget step(String label, int delta) => Expanded(
      child: OBAction(
        label,
        secondary: true,
        onPressed: _busy || draft == null ? null : () => _set(draft + delta),
      ),
    );
    return OBCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 18,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 6,
            children: [
              Text(
                'EIGENES ZIEL',
                style: p.label(size: 10).copyWith(height: 12 / 10),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  obDuration(draft),
                  key: const ValueKey('sleep-goal-value'),
                  style: p
                      .text(
                        64,
                        weight: FontWeight.w700,
                        color: draft == null ? p.gap : p.ink,
                      )
                      .copyWith(height: 66 / 64, letterSpacing: -.04 * 64),
                ),
              ),
            ],
          ),
          if (draft == null)
            Text(
              'Tippe auf die Skala, um ein Ziel festzulegen.',
              style: p.text(12, color: p.muted).copyWith(height: 16 / 12),
            ),
          _GoalScale(minutes: draft, onChanged: _busy ? null : _set),
          Row(
            spacing: 10,
            children: [step('– 15 Min.', -15), step('+ 15 Min.', 15)],
          ),
        ],
      ),
    );
  }

  Widget _estimateCard(OB p, WeekendSleepEstimate? estimate) => Semantics(
    button: true,
    label: 'Wochenend-Schätzung',
    value: _estimateLabel(estimate),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _estimateInfo(context, estimate),
      child: ExcludeSemantics(
        child: OBCard.inset(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            spacing: 12,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      'Wochenend-Schätzung',
                      style: p
                          .text(15, weight: FontWeight.w700)
                          .copyWith(height: 20 / 15),
                    ),
                    Text(
                      estimate == null
                          ? 'Noch kein Wert – zu wenige Wochenend-Nächte.'
                          : 'Stand ${obDate(estimate.asOfDay)}',
                      style: p
                          .text(12, color: p.muted)
                          .copyWith(height: 16 / 12),
                    ),
                  ],
                ),
              ),
              Text(
                estimate == null ? '—' : obDuration(estimate.osdHours * 60),
                style: p
                    .text(
                      22,
                      weight: FontWeight.w700,
                      color: estimate == null ? p.gap : p.ink,
                    )
                    .copyWith(height: 26 / 22),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 5–10 h goal scale in 15-minute steps. Goals outside the scale keep their
/// value; only the handle stops at the end.
class _GoalScale extends StatelessWidget {
  static const int low = 300, high = 600, stepMinutes = 15;
  final int? minutes;
  final ValueChanged<int>? onChanged;
  const _GoalScale({required this.minutes, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final labelStyle = p
        .text(10, weight: FontWeight.w500, color: p.muted)
        .copyWith(height: 12 / 10);
    return LayoutBuilder(
      builder: (context, box) {
        void pick(double dx) {
          final t = (dx / box.maxWidth).clamp(0.0, 1.0);
          final steps = ((high - low) / stepMinutes * t).round();
          onChanged?.call(low + steps * stepMinutes);
        }

        final value = minutes;
        int bound(int m) => m.clamp(kSleepGoalMinMinutes, kSleepGoalMaxMinutes);
        final up = value == null ? low : bound(value + stepMinutes);
        final down = value == null ? null : bound(value - stepMinutes);
        final change = onChanged;
        return Semantics(
          container: true,
          slider: true,
          label: 'Schlafziel',
          value: value == null ? '' : obDuration(value),
          increasedValue: value == null ? '' : obDuration(up),
          decreasedValue: down == null ? '' : obDuration(down),
          onIncrease: change == null ? null : () => change(up),
          onDecrease: change == null || down == null
              ? null
              : () => change(down),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 4,
              children: [
                GestureDetector(
                  key: const ValueKey('sleep-goal-scale'),
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => pick(d.localPosition.dx),
                  onHorizontalDragUpdate: (d) => pick(d.localPosition.dx),
                  child: CustomPaint(
                    size: const Size.fromHeight(40),
                    painter: _GoalScalePainter(
                      t: value == null
                          ? null
                          : ((value - low) / (high - low)).clamp(0.0, 1.0),
                      p: p,
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (final (i, label) in const [
                      '5 h',
                      '6',
                      '7',
                      '8',
                      '9',
                      '10 h',
                    ].indexed)
                      Expanded(
                        flex: i == 0 || i == 5 ? 1 : 2,
                        child: Text(
                          label,
                          textAlign: i == 0
                              ? TextAlign.left
                              : i == 5
                              ? TextAlign.right
                              : TextAlign.center,
                          softWrap: false,
                          overflow: TextOverflow.visible,
                          style: labelStyle,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GoalScalePainter extends CustomPainter {
  final double? t;
  final OB p;
  _GoalScalePainter({required this.t, required this.p});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final track = RRect.fromLTRBR(0, 14, w, 26, const Radius.circular(6));
    canvas.drawRRect(track, Paint()..color = p.line);
    final tick = Paint()
      ..strokeWidth = 1.5
      ..color = p.muted;
    for (var h = 0; h <= 5; h++) {
      final x = (w * h / 5).clamp(.75, w - .75);
      canvas.drawLine(Offset(x, 32), Offset(x, h.isEven ? 40 : 36), tick);
    }
    final at = t;
    if (at == null) return;
    final x = (w * at).clamp(12.0, w - 12);
    canvas.save();
    canvas.clipRRect(track);
    canvas.drawRect(Rect.fromLTRB(0, 14, x, 26), Paint()..color = p.ink);
    canvas.restore();
    final handle = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(x, 20), width: 24, height: 36),
      const Radius.circular(8),
    );
    canvas.drawRRect(handle, Paint()..color = p.card);
    canvas.drawRRect(
      handle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = p.ink,
    );
    final grip = Paint()
      ..strokeWidth = 1.2
      ..color = p.gap;
    for (final dx in const [-4.0, 0.0, 4.0]) {
      canvas.drawLine(Offset(x + dx, 12), Offset(x + dx, 28), grip);
    }
  }

  @override
  bool shouldRepaint(_GoalScalePainter old) => old.t != t || old.p != p;
}

String _estimateLabel(WeekendSleepEstimate? estimate) {
  if (estimate == null) return '—';
  return '${obDuration(estimate.osdHours * 60)} · Stand ${obDate(estimate.asOfDay)}';
}

Future<void> _goalInfo(
  BuildContext context,
  String day,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (c) {
    final p = OB.of(c);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Schlafziel', style: p.text(18, weight: FontWeight.w600)),
            const SizedBox(height: 12),
            Text(
              'Gilt ab dem gewählten Aufwachtag. Die Nacht vom Vortag auf ${obDate(day)} gehört zu diesem Tag.',
              style: p.text(14),
            ),
            const SizedBox(height: 12),
            Text(
              'Die Wochenend-Schätzung ist das 75. Perzentil der Wochenendnächte, kein eigenes Ziel.',
              style: p.text(14),
            ),
            const SizedBox(height: 16),
            OBAction('Schließen', onPressed: () => Navigator.pop(c)),
          ],
        ),
      ),
    );
  },
);

Future<void> _estimateInfo(
  BuildContext context,
  WeekendSleepEstimate? estimate,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (c) {
    final p = OB.of(c);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Wochenend-Schätzung',
              style: p.text(18, weight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              '75. Perzentil der Wochenendnächte. Keine Messung des Schlafbedarfs.',
              style: p.text(14),
            ),
            if (estimate != null) ...[
              const SizedBox(height: 12),
              Text(
                'Stand ${obDate(estimate.asOfDay)}',
                style: p.text(14, color: p.muted),
              ),
              if (estimate.note != null) ...[
                const SizedBox(height: 8),
                Text(estimate.note!, style: p.text(13, color: p.muted)),
              ],
            ],
            const SizedBox(height: 16),
            OBAction('Schließen', onPressed: () => Navigator.pop(c)),
          ],
        ),
      ),
    );
  },
);
