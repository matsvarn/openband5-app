import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'alp_tokens.dart';
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
  late Future<SleepGoalSnapshot> _data = widget.repository.readSleepGoal(
    widget.day,
  );
  String? _error;
  bool _busy = false;

  void _reload() {
    setState(() {
      _busy = false;
      _error = null;
      _data = widget.repository.readSleepGoal(widget.day);
    });
  }

  Future<void> _edit(SleepGoalSnapshot snapshot) async {
    if (_busy) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => OpenBandSleepGoalEditor(
          repository: widget.repository,
          day: widget.day,
          targetMinutes: snapshot.targetMinutes,
          synthetic: widget.synthetic,
        ),
      ),
    );
    if (saved == true && mounted) _reload();
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
    await _runRemove();
  }

  Future<void> _retryRemove() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    await _runRemove();
  }

  Future<void> _runRemove() async {
    try {
      await widget.repository.clearSleepGoal(widget.day);
      if (mounted) _reload();
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
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: FutureBuilder<SleepGoalSnapshot>(
          future: _data,
          builder: (context, snapshot) {
            final goal = snapshot.data;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                OBPageHeader(
                  title: 'Schlafziel',
                  subtitle: 'Ab ${obDate(widget.day)}',
                  infoLabel: 'Schlafziel',
                  onInfo: () => _goalInfo(context, widget.day),
                ),
                if (snapshot.hasError)
                  OBAction('Erneut laden', ink: true, onPressed: _reload)
                else if (goal == null)
                  const Center(child: CircularProgressIndicator.adaptive())
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
                      onPressed: _busy ? null : _retryRemove,
                    ),
                    const SizedBox(height: 12),
                  ],
                  OBCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 16,
                      children: [
                        Text(
                          'Eigenes Ziel',
                          style: p
                              .text(17, weight: FontWeight.w600)
                              .copyWith(height: 22 / 17),
                        ),
                        Text(
                          _goalDuration(goal.targetMinutes?.toDouble()),
                          style: p
                              .text(48, weight: FontWeight.w700, display: true)
                              .copyWith(height: 54 / 48, letterSpacing: 0),
                        ),
                        OBAction(
                          goal.targetMinutes == null
                              ? 'Ziel festlegen'
                              : 'Ändern',
                          ink: true,
                          onPressed: _busy ? null : () => _edit(goal),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 76),
                    child: Semantics(
                      button: true,
                      label: 'Wochenend-Schätzung',
                      value: _estimateLabel(goal.weekendEstimate),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () =>
                            _estimateInfo(context, goal.weekendEstimate),
                        child: ExcludeSemantics(
                          child: OBCard(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              spacing: 12,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    spacing: 4,
                                    children: [
                                      Text(
                                        'Wochenend-Schätzung',
                                        style: p
                                            .text(17, weight: FontWeight.w600)
                                            .copyWith(height: 22 / 17),
                                      ),
                                      Text(
                                        _estimateLabel(goal.weekendEstimate),
                                        style: p
                                            .text(13, color: p.muted)
                                            .copyWith(height: 16 / 13),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  LucideIcons.info,
                                  size: 20,
                                  color: p.muted,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (goal.targetMinutes != null) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: TextButton(
                        onPressed: _busy ? null : _confirmRemove,
                        style: TextButton.styleFrom(
                          foregroundColor: p.muted,
                          minimumSize: const Size.fromHeight(48),
                          textStyle: p
                              .text(14, color: p.muted)
                              .copyWith(height: 18 / 14),
                        ),
                        child: const Text('Ziel entfernen'),
                      ),
                    ),
                  ],
                  if (widget.synthetic) ...[
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(
                        'Synthetische Daten',
                        style: p
                            .text(12, color: p.muted)
                            .copyWith(height: 18 / 12),
                      ),
                    ),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class OpenBandSleepGoalEditor extends StatefulWidget {
  final OpenBandRepository repository;
  final String day;
  final int? targetMinutes;
  final bool synthetic;
  const OpenBandSleepGoalEditor({
    super.key,
    required this.repository,
    required this.day,
    this.targetMinutes,
    this.synthetic = false,
  });
  @override
  State<OpenBandSleepGoalEditor> createState() =>
      _OpenBandSleepGoalEditorState();
}

class _OpenBandSleepGoalEditorState extends State<OpenBandSleepGoalEditor> {
  late final hours = TextEditingController(
    text: widget.targetMinutes == null ? '' : '${widget.targetMinutes! ~/ 60}',
  );
  late final minutes = TextEditingController(
    text: widget.targetMinutes == null ? '' : '${widget.targetMinutes! % 60}',
  );
  bool busy = false;
  String? error;

  int? get _minutes => sleepGoalMinutesFromFields(hours.text, minutes.text);

  @override
  void dispose() {
    hours.dispose();
    minutes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _minutes;
    if (busy || value == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.saveSleepGoal(widget.day, value);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Speichern fehlgeschlagen';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    InputDecoration deco() => InputDecoration(
      isDense: true,
      filled: true,
      fillColor: p.well,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AlpRadius.well),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.all(14),
    );
    final fieldStyle = p
        .text(28, weight: FontWeight.w600, display: true)
        .copyWith(height: 34 / 28, letterSpacing: 0);
    final labelStyle = p.text(13, color: p.muted).copyWith(height: 16 / 13);
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            OBPageHeader(
              title: 'Schlafziel bearbeiten',
              subtitle: 'Ab ${obDate(widget.day)}',
            ),
            if (error != null) ...[
              Text(
                error!,
                style: p.text(14, color: p.danger).copyWith(height: 18 / 14),
              ),
              const SizedBox(height: 12),
            ],
            OBCard(
              padding: const EdgeInsets.all(20),
              child: Row(
                spacing: 12,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 6,
                      children: [
                        Text('Stunden', style: labelStyle),
                        TextField(
                          key: const ValueKey('sleep-goal-hours'),
                          controller: hours,
                          keyboardType: TextInputType.number,
                          enabled: !busy,
                          style: fieldStyle,
                          decoration: deco(),
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 6,
                      children: [
                        Text('Minuten', style: labelStyle),
                        TextField(
                          key: const ValueKey('sleep-goal-minutes'),
                          controller: minutes,
                          keyboardType: TextInputType.number,
                          enabled: !busy,
                          style: fieldStyle,
                          decoration: deco(),
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            OBAction(
              'Speichern',
              ink: true,
              onPressed: busy || _minutes == null ? null : _save,
            ),
            if (widget.synthetic) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.all(4),
                child: Text(
                  'Synthetische Daten',
                  style: p.text(12, color: p.muted).copyWith(height: 18 / 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _goalDuration(num? minutes) {
  if (minutes == null) return '—';
  final m = minutes.round();
  return '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')}';
}

String _estimateLabel(WeekendSleepEstimate? estimate) {
  if (estimate == null) return '—';
  return '${_goalDuration(estimate.osdHours * 60)} · Stand ${obDate(estimate.asOfDay)}';
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
