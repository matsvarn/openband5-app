import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../domain.dart';
import '../chrome.dart'
    show
        OBActionPrimary,
        OBActionSecondary,
        OBErrorBlock,
        OBLink,
        OBListRow,
        OBSheet;
import '../g3_format.dart';
import '../g3_theme.dart';
import '../metrics.dart' show OBMissingValue;
import '../sleep_parts.dart';

/// Goal editing is a sheet over the current night. Reads and writes use the
/// same versioned goal repository as the former full-screen editor.
class G3SleepGoalSheet extends StatefulWidget {
  const G3SleepGoalSheet({
    super.key,
    required this.repository,
    required this.day,
    this.onTonight,
  });
  final OpenBandRepository repository;
  final String day;
  final VoidCallback? onTonight;

  static Future<void> show(
    BuildContext context,
    OpenBandRepository repository,
    String day, {
    VoidCallback? onTonight,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.black.withValues(alpha: .32),
    backgroundColor: Colors.transparent,
    builder: (_) => G3SleepGoalSheet(
      repository: repository,
      day: day,
      onTonight: onTonight,
    ),
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
    if (_draft == null) {
      try {
        final nights = (await _history)
            .where((point) => point.value != null)
            .toList();
        if (nights.length == 7) {
          final average =
              nights.map((point) => point.value!).reduce((a, b) => a + b) / 7;
          _draft = average.round().clamp(
            kSleepGoalMinMinutes,
            kSleepGoalMaxMinutes,
          );
        }
      } catch (_) {
        // A missing history keeps the goal unselected.
      }
    }
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
    final yes = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (dialog) => OBSheet(
        title: 'Ziel entfernen?',
        confirmLabel: 'Entfernen',
        onCancel: () => Navigator.of(dialog).pop(false),
        onConfirm: () => Navigator.of(dialog).pop(true),
        child: const Text('Ab diesem Tag gilt kein eigenes Schlafziel.'),
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

  Future<void> _chooseGoal() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheet) => OBSheet(
        title: 'Ziel wählen',
        child: SizedBox(
          height: 360,
          child: ListView.builder(
            itemCount: 21,
            itemBuilder: (context, index) {
              final minutes = 300 + index * 15;
              return OBListRow(
                icon: LucideIcons.moon,
                title: g3Duration(minutes),
                onTap: () => Navigator.of(sheet).pop(minutes),
              );
            },
          ),
        ),
      ),
    );
    if (mounted && selected != null) _set(selected);
  }

  void _showHistory(List<MetricPoint> points) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => OBSheet(
      title: 'Letzte 7 Nächte',
      child: Column(
        children: [
          for (final point in points)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(child: Text(g3DayShort(DateTime.parse(point.day)))),
                  Text(obSleepDuration(point.value)),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: FutureBuilder<SleepGoalSnapshot>(
        future: _goal,
        builder: (context, snapshot) {
          final saved = snapshot.data?.targetMinutes;
          return OBSheet(
            title: saved == null ? 'Schlafziel festlegen' : 'Schlafziel',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  saved == null
                      ? 'Noch kein Ziel. Es zeigt nur den Abstand deiner Nächte. Bedarf und Bettzeit rechnen ohne Ziel.'
                      : 'Vergleiche deine Nächte mit deinem eigenen Ziel.',
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
                      ? const OBMissingValue(size: 52, lineHeight: 58)
                      : snapshot.data == null
                      ? const CircularProgressIndicator.adaptive()
                      : _draft == null
                      ? OBActionSecondary(
                          'Ziel wählen',
                          onPressed: _busy ? null : _chooseGoal,
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
                        ? points.map((p) => p.value!).reduce((a, b) => a + b) /
                              7
                        : null;
                    return Row(
                      children: [
                        Expanded(
                          child: Text(
                            average == null
                                ? 'Ø — · noch keine 7 Nächte'
                                : saved == null
                                ? 'Start: dein Ø der letzten 7 Nächte'
                                : 'Ø ${obSleepDuration(average)} in 7 Nächten',
                            style: g.t(
                              13,
                              17,
                              weight: FontWeight.w600,
                              color: g.ink2,
                            ),
                          ),
                        ),
                        if (average != null)
                          OBLink('Verlauf', onTap: () => _showHistory(points)),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OBActionSecondary(
                        g3Signed(-15, unit: 'Min.'),
                        expand: true,
                        onPressed: _busy || _draft == null
                            ? null
                            : () => _set(_draft! - 15),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OBActionSecondary(
                        g3Signed(15, unit: 'Min.'),
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
                if (widget.onTonight != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OBLink(
                      'Heute Nacht',
                      onTap: () {
                        Navigator.of(context).pop();
                        widget.onTonight!();
                      },
                    ),
                  ),
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
                        saved == null ? 'Ziel speichern' : 'Speichern',
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
                  OBActionSecondary(
                    'Schlafziel entfernen',
                    expand: true,
                    onPressed: _busy ? null : _remove,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
