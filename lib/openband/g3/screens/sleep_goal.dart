import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../domain.dart';
import '../chrome.dart' show OBActionPrimary, OBActionSecondary, OBErrorBlock;
import '../g3_theme.dart';
import '../sleep_parts.dart';

/// Goal editing is a sheet over the current night. Reads and writes use the
/// same versioned goal repository as the former full-screen editor.
class G3SleepGoalSheet extends StatefulWidget {
  const G3SleepGoalSheet({
    super.key,
    required this.repository,
    required this.day,
  });
  final OpenBandRepository repository;
  final String day;

  static Future<void> show(
    BuildContext context,
    OpenBandRepository repository,
    String day,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.black.withValues(alpha: .32),
    backgroundColor: Colors.transparent,
    builder: (_) => G3SleepGoalSheet(repository: repository, day: day),
  );

  @override
  State<G3SleepGoalSheet> createState() => _G3SleepGoalSheetState();
}

class _G3SleepGoalSheetState extends State<G3SleepGoalSheet> {
  late Future<SleepGoalSnapshot> _goal = _read();
  late final Future<List<MetricPoint>> _history = widget.repository
      .readMetricHistory(MetricKey.sleepDuration, widget.day, 7);
  int? _draft;
  bool _busy = false;
  String? _error;
  bool _failedRemove = false;

  Future<SleepGoalSnapshot> _read() async {
    final goal = await widget.repository.readSleepGoal(widget.day);
    _draft = goal.targetMinutes;
    return goal;
  }

  void _set(int value) => setState(
    () => _draft = value.clamp(kSleepGoalMinMinutes, kSleepGoalMaxMinutes),
  );

  Future<void> _save() async {
    final value = _draft;
    if (value == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _failedRemove = false;
    });
    try {
      await widget.repository.saveSleepGoal(widget.day, value);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error =
              'Schlafziel konnte nicht gespeichert werden. Deine Auswahl bleibt erhalten.';
        });
      }
    }
  }

  Future<void> _remove() async {
    if (_busy) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Ziel entfernen?'),
        content: const Text('Ab diesem Tag gilt kein eigenes Schlafziel.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Entfernen'),
          ),
        ],
      ),
    );
    if (!mounted || yes != true) return;
    setState(() {
      _busy = true;
      _error = null;
      _failedRemove = true;
    });
    try {
      await widget.repository.clearSleepGoal(widget.day);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error =
              'Ziel konnte nicht entfernt werden. Deine Auswahl bleibt erhalten.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      decoration: BoxDecoration(
        color: g.canvas,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: g.noteShadow,
      ),
      padding: EdgeInsets.fromLTRB(20, 8, 20, bottom + 24),
      child: FutureBuilder<SleepGoalSnapshot>(
        future: _goal,
        builder: (context, snapshot) {
          final saved = snapshot.data?.targetMinutes;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 5,
                  decoration: BoxDecoration(
                    color: g.bar,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Schlafziel',
                      style: g.t(28, 33, weight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Schließen',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(LucideIcons.x),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      backgroundColor: g.track,
                      foregroundColor: g.ink,
                    ),
                  ),
                ],
              ),
              Text(
                'Grundlage für Bedarf und Bettzeit heute Nacht.',
                style: g.t(14, 19, color: g.ink2),
              ),
              const SizedBox(height: 22),
              Text('ZIEL PRO NACHT', style: g.caps(color: g.muted)),
              const SizedBox(height: 9),
              Container(
                height: 88,
                alignment: Alignment.center,
                decoration: g.pressed(radius: 15),
                child: snapshot.hasError
                    ? Text('—', style: g.t(52, 58, weight: FontWeight.w700))
                    : snapshot.data == null
                    ? const CircularProgressIndicator.adaptive()
                    : _draft == null
                    ? DropdownButton<int>(
                        icon: const Icon(LucideIcons.chevronDown),
                        hint: Text(
                          'Ziel wählen',
                          style: g.t(21, 25, weight: FontWeight.w700),
                        ),
                        value: null,
                        items: [
                          for (var minutes = 300; minutes <= 600; minutes += 15)
                            DropdownMenuItem(
                              value: minutes,
                              child: Text(obSleepDuration(minutes)),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) {
                                if (value != null) _set(value);
                              },
                      )
                    : Text(
                        obSleepDuration(_draft),
                        key: const ValueKey('g3-sleep-goal-value'),
                        style: g.t(
                          48,
                          55,
                          weight: FontWeight.w700,
                          tracking: -.04,
                        ),
                      ),
              ),
              const SizedBox(height: 10),
              FutureBuilder<List<MetricPoint>>(
                future: _history,
                builder: (context, history) {
                  final points =
                      history.data?.where((p) => p.value != null).toList() ??
                      const <MetricPoint>[];
                  final average = points.length == 7
                      ? points.map((p) => p.value!).reduce((a, b) => a + b) / 7
                      : null;
                  return Text(
                    average == null
                        ? 'Ø — · noch keine 7 Nächte'
                        : 'Ø ${obSleepDuration(average)} in 7 Nächten',
                    style: g.t(13, 17, weight: FontWeight.w600, color: g.ink2),
                  );
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OBActionSecondary(
                      '− 15 Min.',
                      expand: true,
                      onPressed: _busy || _draft == null
                          ? null
                          : () => _set(_draft! - 15),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OBActionSecondary(
                      '+ 15 Min.',
                      expand: true,
                      onPressed: _busy || _draft == null
                          ? null
                          : () => _set(_draft! + 15),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                OBErrorBlock(
                  title: 'Speichern fehlgeschlagen',
                  reason: _error!,
                  retryLabel: _failedRemove
                      ? 'Erneut entfernen'
                      : 'Erneut speichern',
                  onRetry: _failedRemove ? _remove : _save,
                ),
              ],
              if (snapshot.hasError) ...[
                const SizedBox(height: 14),
                OBErrorBlock(
                  title: 'Schlafziel nicht geladen',
                  reason: 'Bitte erneut versuchen.',
                  onRetry: () => setState(() => _goal = _read()),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OBActionSecondary(
                      'Abbrechen',
                      expand: true,
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OBActionPrimary(
                      'Speichern',
                      expand: true,
                      onPressed:
                          _busy ||
                              snapshot.data == null ||
                              _draft == null ||
                              _draft == saved
                          ? null
                          : _save,
                    ),
                  ),
                ],
              ),
              if (saved != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : _remove,
                  child: const Text('Schlafziel entfernen'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
