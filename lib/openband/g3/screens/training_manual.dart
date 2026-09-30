import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../compute/manual_session.dart';
import '../../../health/health_export.dart';
import '../../../ui2/screens/home_screen.dart' show repoOf;
import '../../../ui2/screens/log_workout.dart' show appOf;
import '../../domain.dart';
import '../chrome.dart' show OBActionPrimary, OBListRow;
import '../g3_theme.dart';
import '../training_parts.dart';

/// The same manual-session writer and overlap policy used by LogWorkout.
/// No pre-save score is displayed: the repository can score only when it saves.
class G3ManualSaved {
  final String id, sport;
  final DateTime start;
  const G3ManualSaved(this.id, this.sport, this.start);
}

class G3ManualFlow extends StatefulWidget {
  final DateTime Function() now;
  final OpenBandRepository? recentRepository;
  final int initialStep;
  final DateTime? initialStart, initialEnd;
  final List<SessionSpan>? initialSpans;
  const G3ManualFlow({
    super.key,
    this.now = DateTime.now,
    this.recentRepository,
    this.initialStep = 0,
    this.initialStart,
    this.initialEnd,
    this.initialSpans,
  });

  @override
  State<G3ManualFlow> createState() => _G3ManualFlowState();
}

class _G3ManualFlowState extends State<G3ManualFlow> {
  static const sports = trainingSports;
  late int step = widget.initialStep;
  String sport = 'yoga';
  late DateTime start, end;
  late List<SessionSpan> spans = widget.initialSpans ?? const [];
  List<String> recentSports = const [];
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final now = widget.now();
    end = widget.initialEnd ?? DateTime(now.year, now.month, now.day, now.hour);
    start = widget.initialStart ?? end.subtract(const Duration(minutes: 40));
    _readRecentSports();
  }

  Future<void> _readRecentSports() async {
    final repository = widget.recentRepository;
    if (repository == null) return;
    try {
      final days = g3DaysEnding(
        DateFormat('yyyy-MM-dd').format(widget.now()),
        7,
      );
      final activities =
          (await Future.wait([
              for (final day in days) repository.readActivities(day),
            ])).expand((day) => day).toList()
            ..sort((a, b) => b.start.compareTo(a.start));
      final seen = <String>{};
      final recent = <String>[];
      for (final activity in activities) {
        if (sports.contains(activity.sport) && seen.add(activity.sport)) {
          recent.add(activity.sport);
          if (recent.length == 4) break;
        }
      }
      if (mounted) setState(() => recentSports = recent);
    } catch (_) {
      // Recent sports are optional; the full sport catalogue remains available.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.initialSpans == null) _readSpans();
  }

  Future<void> _readSpans() async {
    try {
      final loaded = await repoOf(context)?.savedSessionSpans();
      if (mounted && loaded != null) setState(() => spans = loaded);
    } catch (_) {
      // The repository validates again on save; an unreadable preview is no permission.
    }
  }

  ManualWindowError? get invalid => validateManualWindow(
    startSec: start.millisecondsSinceEpoch ~/ 1000,
    endSec: end.millisecondsSinceEpoch ~/ 1000,
    nowSec: widget.now().millisecondsSinceEpoch ~/ 1000,
    existing: spans,
    editingId: manualSessionId(start.millisecondsSinceEpoch ~/ 1000),
  );

  Future<void> _pickDay() async {
    final day = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: widget.now(),
      initialDate: start,
    );
    if (day == null || !mounted) return;
    final span = end.difference(start);
    setState(() {
      start = DateTime(day.year, day.month, day.day, start.hour, start.minute);
      end = start.add(span);
    });
  }

  Future<void> _pickTime(bool beginning) async {
    final at = beginning ? start : end;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(at),
    );
    if (time == null || !mounted) return;
    setState(() {
      if (beginning) {
        final span = end.difference(start);
        start = DateTime(
          start.year,
          start.month,
          start.day,
          time.hour,
          time.minute,
        );
        end = start.add(span);
      } else {
        end = DateTime(
          start.year,
          start.month,
          start.day,
          time.hour,
          time.minute,
        );
        if (!end.isAfter(start)) {
          end = DateTime(
            start.year,
            start.month,
            start.day + 1,
            time.hour,
            time.minute,
          );
        }
      }
    });
  }

  Future<void> _save() async {
    final writer = repoOf(context);
    final app = appOf(context);
    if (writer == null || invalid != null || saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final result = await writer.logManualWorkout(
        startTs: start.millisecondsSinceEpoch ~/ 1000,
        endTs: end.millisecondsSinceEpoch ~/ 1000,
        type: sport,
      );
      await HealthExporter.exportWorkoutId(result['workout_id'] as String?);
      app?.insightsRevision.value++;
      if (!mounted) return;
      Navigator.of(
        context,
      ).pop(G3ManualSaved(result['workout_id'] as String, sport, start));
    } on ManualWindowException catch (e) {
      if (!mounted) return;
      await _readSpans();
      if (mounted) {
        setState(() {
          saving = false;
          error = _windowError(e.error);
          step = 1;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'Speichern fehlgeschlagen. Erneut versuchen.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final status = invalid;
    return Scaffold(
      backgroundColor: g.page,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 48,
                    child: IconButton(
                      tooltip: step > 0 ? 'Zurück' : 'Abbrechen',
                      onPressed: saving
                          ? null
                          : () {
                              if (step > 0) {
                                setState(() => step--);
                              } else {
                                Navigator.of(context).maybePop();
                              }
                            },
                      icon: Icon(
                        step > 0 ? LucideIcons.chevronLeft : LucideIcons.x,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'NACHTRAGEN',
                            maxLines: 1,
                            softWrap: false,
                            style: g.caps(size: 17),
                          ),
                        ),
                        Text(
                          'Schritt ${step + 1} von 3',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: g.t(13, 17, color: g.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 22),
              Expanded(
                child: ListView(
                  children: [
                    if (step == 0) ...[
                      if (recentSports.isNotEmpty) ...[
                        Text('ZULETZT', style: g.caps(color: g.muted)),
                        const SizedBox(height: 8),
                        _sports(context, recentSports),
                        const SizedBox(height: 24),
                      ],
                      Text('ALLE SPORTARTEN', style: g.caps(color: g.muted)),
                      const SizedBox(height: 8),
                      _sports(
                        context,
                        sports
                            .where((value) => !recentSports.contains(value))
                            .toList(),
                      ),
                    ] else if (step == 1) ...[
                      Text('ZEITRAUM', style: g.caps(color: g.muted)),
                      const SizedBox(height: 8),
                      _timeRow(
                        context,
                        'Tag',
                        DateFormat('EEEE, d. MMMM', 'de_DE').format(start),
                        _pickDay,
                      ),
                      _timeRow(
                        context,
                        'Beginn',
                        DateFormat.Hm('de_DE').format(start),
                        () => _pickTime(true),
                      ),
                      _timeRow(
                        context,
                        'Ende',
                        DateFormat.Hm('de_DE').format(end),
                        () => _pickTime(false),
                      ),
                      const SizedBox(height: 18),
                      _panel(
                        context,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Bandpuls im Zeitraum', style: g.caps()),
                            const SizedBox(height: 6),
                            Text('—', style: g.t(28, 34, color: g.gap)),
                            Text(
                              'Die Verfügbarkeit wird beim Speichern geprüft. Lücken bleiben leer.',
                              style: g.t(13, 18, color: g.ink2),
                            ),
                          ],
                        ),
                      ),
                      if (status != null || error != null) ...[
                        const SizedBox(height: 12),
                        _panel(
                          context,
                          Text(
                            error ?? _windowError(status!),
                            style: g.t(15, 20, weight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ] else if (status ==
                        ManualWindowError.overlapsExisting) ...[
                      _panel(
                        context,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Zeitraum schon erfasst',
                              style: g.t(17, 22, weight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Diese Zeit überschneidet sich mit einer gespeicherten Einheit. Zweimal dieselbe Zeit wird nicht gespeichert.',
                              style: g.t(13, 18, color: g.ink2),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Text('PRÜFEN', style: g.caps(color: g.muted)),
                      const SizedBox(height: 8),
                      _panel(
                        context,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              trainingSport(sport),
                              style: g.t(24, 30, weight: FontWeight.w700),
                            ),
                            Text(
                              '${DateFormat('d. MMMM', 'de_DE').format(start)} · ${DateFormat.Hm('de_DE').format(start)}–${DateFormat.Hm('de_DE').format(end)}',
                              style: g.t(14, 20, color: g.ink2),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              '${end.difference(start).inMinutes} Min. · Belastung —',
                              style: g.t(17, 22, weight: FontWeight.w700),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'Belastung und Zonen nur mit gespeicherten Bandwerten.',
                              style: g.t(13, 18, color: g.ink2),
                            ),
                          ],
                        ),
                      ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(error!, style: g.t(14, 18)),
                        ),
                    ],
                  ],
                ),
              ),
              if (step == 2 && status == ManualWindowError.overlapsExisting)
                OBActionPrimary(
                  'Zeit ändern',
                  onPressed: () => setState(() => step = 1),
                  expand: true,
                )
              else
                OBActionPrimary(
                  saving
                      ? 'Wird gespeichert …'
                      : step == 0
                      ? 'Weiter mit ${trainingSport(sport)}'
                      : step == 1
                      ? 'Weiter'
                      : 'Speichern',
                  onPressed: saving || (step == 1 && status != null)
                      ? null
                      : step == 2
                      ? _save
                      : () => setState(() {
                          step++;
                          error = null;
                        }),
                  expand: true,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sports(BuildContext context, List<String> list) => GridView.count(
    crossAxisCount: 4,
    childAspectRatio: .9,
    crossAxisSpacing: 8,
    mainAxisSpacing: 8,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    children: [
      for (final value in list)
        InkWell(
          onTap: () => setState(() => sport = value),
          child: Container(
            decoration: sport == value
                ? BoxDecoration(
                    color: G3.of(context).ink,
                    borderRadius: BorderRadius.circular(18),
                  )
                : G3.of(context).raised(),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                trainingSportIcon(
                  value,
                  color: sport == value
                      ? G3.of(context).canvas
                      : G3.of(context).ink,
                ),
                const SizedBox(height: 7),
                Text(
                  trainingSport(value),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: G3
                      .of(context)
                      .t(
                        12,
                        16,
                        color: sport == value
                            ? G3.of(context).canvas
                            : G3.of(context).ink,
                        weight: sport == value
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

Widget _panel(BuildContext context, Widget content) => Container(
  padding: const EdgeInsets.all(18),
  decoration: G3.of(context).raised(),
  child: content,
);

Widget _timeRow(
  BuildContext context,
  String label,
  String value,
  VoidCallback tap,
) {
  return OBListRow(
    title: label,
    value: value,
    icon: label == 'Tag' ? LucideIcons.calendarDays : LucideIcons.clock3,
    onTap: tap,
  );
}

String _windowError(ManualWindowError error) => switch (error) {
  ManualWindowError.overlapsExisting =>
    'Überschneidung mit einer gespeicherten Einheit. Zeitraum ändern.',
  ManualWindowError.inFuture => 'Das Ende liegt in der Zukunft.',
  ManualWindowError.endNotAfterStart => 'Das Ende muss nach dem Beginn liegen.',
  ManualWindowError.tooShort =>
    'Die Einheit muss mindestens eine Minute dauern.',
  ManualWindowError.tooLong => 'Der Zeitraum ist länger als 24 Stunden.',
};
