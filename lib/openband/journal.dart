import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/journal_fields.dart';
import 'alp_tokens.dart';
import 'controller.dart';
import 'domain.dart';
import 'journal_controls.dart';
import 'cycle.dart';
import 'medication.dart';
import 'nutrition.dart';
import 'theme.dart';
import '../ui2/profile/profile.dart' show SetRow;

const _kPatternNights = 30;

class OpenBandJournal extends StatefulWidget {
  final OpenBandController controller;
  final FutureOr<void> Function(String day)? onEdit;
  final FutureOr<void> Function()? onNutrition;
  final FutureOr<void> Function()? onCycle;
  const OpenBandJournal({
    super.key,
    required this.controller,
    this.onEdit,
    this.onNutrition,
    this.onCycle,
  });
  @override
  State<OpenBandJournal> createState() => _OpenBandJournalState();
}

class _OpenBandJournalState extends State<OpenBandJournal> {
  String? _loadedDay;
  JournalDaySnapshot? _base;
  Map<String, JournalMetricValue> _values = {};
  bool _loading = true;
  bool _loadError = false;
  bool _conflict = false;
  bool _saving = false;
  String? _saveError;
  Future<DayMeals>? _meals;
  Object? _mealsError;
  Future<NutritionTargetSnapshot>? _targets;
  Object? _targetsError;
  Future<CaffeineSleepPattern>? _pattern;
  Object? _patternError;
  bool? _cycleEnabled;
  bool _cycleReadError = false;
  OpenBandDay? _cycleSeenDay;
  int _journalSeq = 0;
  int _mealsSeq = 0;
  int _targetsSeq = 0;
  int _patternSeq = 0;
  int _cycleSeq = 0;
  int _writeSeq = 0;

  OpenBandController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onController);
    _reload(_c.selectedDay);
  }

  @override
  void didUpdateWidget(OpenBandJournal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
      _cycleEnabled = null;
      _cycleReadError = false;
      _cycleSeenDay = _c.day;
      _reload(_c.selectedDay);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onController);
    super.dispose();
  }

  void _onController() {
    final day = _c.selectedDay;
    if (_loadedDay != day) {
      _cycleSeenDay = _c.day;
      _reload(day);
      return;
    }
    if (!identical(_cycleSeenDay, _c.day)) {
      _cycleSeenDay = _c.day;
      unawaited(_loadCycle(day, ++_cycleSeq));
    }
  }

  Future<void> _reload(
    String day, {
    bool journal = true,
    bool meals = true,
    bool targets = true,
    bool pattern = true,
    bool cycle = true,
  }) {
    final dayChanged = _loadedDay != day;
    _loadedDay = day;
    final tasks = <Future<void>>[];
    if (journal) {
      final seq = ++_journalSeq;
      _writeSeq++;
      _loading = true;
      _loadError = false;
      _conflict = false;
      _saveError = null;
      _saving = false;
      if (dayChanged) {
        _base = null;
        _values = {};
      }
      tasks.add(_loadJournal(day, seq));
    }
    if (meals) {
      final seq = ++_mealsSeq;
      _meals = null;
      _mealsError = null;
      tasks.add(_loadMeals(day, seq));
    }
    if (targets) {
      final seq = ++_targetsSeq;
      _targets = null;
      _targetsError = null;
      tasks.add(_loadTargets(day, seq));
    }
    if (pattern) {
      final seq = ++_patternSeq;
      _pattern = null;
      _patternError = null;
      tasks.add(_loadPattern(day, seq));
    }
    if (cycle) {
      final seq = ++_cycleSeq;
      tasks.add(_loadCycle(day, seq));
    }
    if (mounted) setState(() {});
    return Future.wait(tasks);
  }

  Future<void> _loadCycle(String day, int seq) async {
    final repo = _c.repository;
    try {
      final settings = await repo.readCycleSettings();
      if (!mounted ||
          seq != _cycleSeq ||
          _loadedDay != day ||
          !identical(repo, _c.repository)) {
        return;
      }
      setState(() {
        _cycleEnabled = settings.enabled;
        _cycleReadError = false;
      });
    } catch (_) {
      if (!mounted ||
          seq != _cycleSeq ||
          _loadedDay != day ||
          !identical(repo, _c.repository)) {
        return;
      }
      // A failed read is not an opt-out. Keep the last acknowledged setting.
      setState(() => _cycleReadError = true);
    }
  }

  Future<void> _loadJournal(String day, int seq) async {
    try {
      final snap = await _c.repository.readJournalDay(day);
      if (!mounted || seq != _journalSeq || _loadedDay != day) return;
      setState(() {
        _base = snap;
        _values = {...snap.metrics};
        _loading = false;
        _loadError = false;
      });
    } catch (_) {
      if (!mounted || seq != _journalSeq || _loadedDay != day) return;
      setState(() {
        _loading = false;
        _loadError = true;
      });
    }
  }

  Future<void> _loadMeals(String day, int seq) async {
    try {
      final future = _c.repository.readMeals(day);
      if (!mounted || seq != _mealsSeq || _loadedDay != day) return;
      setState(() {
        _meals = future;
        _mealsError = null;
      });
      await future;
    } catch (e) {
      if (!mounted || seq != _mealsSeq || _loadedDay != day) return;
      setState(() {
        _meals = null;
        _mealsError = e;
      });
    }
  }

  Future<void> _loadTargets(String day, int seq) async {
    try {
      final future = _c.repository.readNutritionTargets(day);
      if (!mounted || seq != _targetsSeq || _loadedDay != day) return;
      setState(() {
        _targets = future;
        _targetsError = null;
      });
      await future;
    } catch (e) {
      if (!mounted || seq != _targetsSeq || _loadedDay != day) return;
      setState(() {
        _targets = null;
        _targetsError = e;
      });
    }
  }

  Future<void> _loadPattern(String day, int seq) async {
    try {
      final future = _c.repository.readCaffeineSleepPattern(
        day,
        _kPatternNights,
      );
      if (!mounted || seq != _patternSeq || _loadedDay != day) return;
      setState(() {
        _pattern = future;
        _patternError = null;
      });
      await future;
    } catch (e) {
      if (!mounted || seq != _patternSeq || _loadedDay != day) return;
      setState(() {
        _pattern = null;
        _patternError = e;
      });
    }
  }

  JournalMetricValue? _metric(String key) => _values[key];

  int? _mood() {
    final v = _metric('mood')?.value;
    if (v == null) return null;
    final n = v.round();
    if (n < 1 || n > 5 || v != n) return null;
    return n;
  }

  bool? _yesNo(String key) {
    final v = _metric(key)?.value;
    if (v == 1) return true;
    if (v == 0) return false;
    return null;
  }

  Future<void> _write(String key, JournalMetricValue? next) async {
    final day = _loadedDay;
    final base = _base;
    if (day == null ||
        base == null ||
        base.day != day ||
        _saving ||
        _loading ||
        _loadError ||
        _conflict) {
      return;
    }
    final writeSeq = ++_writeSeq;
    setState(() {
      _saving = true;
      _conflict = false;
      _saveError = null;
    });
    try {
      await _c.repository.patchJournalDay(
        JournalDayPatch.fromBase(base, metrics: {key: next}),
      );
      if (!mounted || writeSeq != _writeSeq) return;
      if (_loadedDay != day) {
        setState(() => _saving = false);
        return;
      }
      setState(() {
        if (next == null) {
          _values.remove(key);
        } else {
          _values[key] = next;
        }
      });
      try {
        final snap = await _c.repository.readJournalDay(day);
        if (!mounted || writeSeq != _writeSeq) return;
        if (_loadedDay != day) {
          setState(() => _saving = false);
          return;
        }
        setState(() {
          _base = snap;
          _values = {...snap.metrics};
          _saving = false;
          _loadError = false;
          _conflict = false;
        });
        if (key == CaffeineSleepPattern.field) {
          await _loadPattern(day, ++_patternSeq);
        }
      } catch (_) {
        if (!mounted || writeSeq != _writeSeq) return;
        setState(() {
          _saving = false;
          if (_loadedDay == day) _loadError = true;
        });
      }
    } on JournalConflict {
      if (!mounted || writeSeq != _writeSeq) return;
      setState(() {
        _saving = false;
        if (_loadedDay == day) {
          _conflict = true;
          _saveError = null;
        }
      });
    } catch (_) {
      if (!mounted || writeSeq != _writeSeq) return;
      setState(() {
        _saving = false;
        if (_loadedDay == day) {
          _saveError = 'Speichern fehlgeschlagen.';
        }
      });
    }
  }

  Future<void> _openEditor() async {
    final onEdit = widget.onEdit;
    if (onEdit == null || _saving) return;
    final day = _c.selectedDay;
    await onEdit(day);
    if (!mounted || _loadedDay != day || _saving) return;
    await _reload(day, meals: false, targets: false);
  }

  Future<void> _openNutrition() async {
    final onNutrition = widget.onNutrition;
    if (onNutrition == null) return;
    final day = _c.selectedDay;
    await onNutrition();
    if (!mounted || _loadedDay != day) return;
    await _reload(day, journal: false, pattern: false);
  }

  Future<void> _openCycle() async {
    final day = _c.selectedDay;
    final onCycle = widget.onCycle;
    if (onCycle != null) {
      await onCycle();
    } else {
      await OpenBandCycle.push(
        context,
        repository: _c.repository,
        day: day,
        now: _c.now,
        synthetic: _c.day?.synthetic == true,
      );
    }
    if (!mounted || _loadedDay != day) return;
    await _reload(
      day,
      journal: false,
      meals: false,
      targets: false,
      pattern: false,
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) {
      final p = OB.of(context);
      return ColoredBox(
        color: p.canvas,
        child: ListView(
          key: const PageStorageKey('openband.journal'),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Journal',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: p
                          .text(30, weight: FontWeight.w800, display: true)
                          .copyWith(height: 34 / 30),
                    ),
                  ),
                  if (widget.onEdit != null)
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: IconButton(
                        key: const ValueKey('journal-edit'),
                        tooltip: 'Journal bearbeiten',
                        onPressed: _saving ? null : _openEditor,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 44,
                          height: 44,
                        ),
                        icon: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: p.card,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            LucideIcons.slidersHorizontal,
                            size: 20,
                            color: p.ink,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            OBCheckinCard(
              mood: _mood(),
              caffeineLate: _yesNo('caffeine_late'),
              alcoholEvening: _yesNo('alcohol_evening'),
              readBeforeBed: _yesNo('read_before_bed'),
              busy: _saving || _loading || _conflict || _loadError,
              error: _loadError
                  ? 'Journal nicht geladen.'
                  : _conflict
                  ? 'Antwort inzwischen geändert.'
                  : _saveError,
              onMood: (v) => _write(
                'mood',
                v == null ? null : JournalMetricValue(v.toDouble()),
              ),
              onCaffeine: (v) => _write(
                'caffeine_late',
                v == null ? null : JournalMetricValue(v ? 1 : 0),
              ),
              onAlcohol: (v) => _write(
                'alcohol_evening',
                v == null ? null : JournalMetricValue(v ? 1 : 0),
              ),
              onRead: (v) => _write(
                'read_before_bed',
                v == null ? null : JournalMetricValue(v ? 1 : 0),
              ),
              onRetry: _loadError || _conflict
                  ? () => _reload(_c.selectedDay, meals: false, targets: false)
                  : null,
              retryLabel: _conflict ? 'Neu laden' : null,
            ),
            const SizedBox(height: 10),
            _HubNutrition(
              meals: _meals,
              mealsError: _mealsError,
              targets: _targets,
              targetsError: _targetsError,
              onTap: widget.onNutrition == null ? null : _openNutrition,
              onRetry: () =>
                  _reload(_c.selectedDay, journal: false, pattern: false),
            ),
            const SizedBox(height: 10),
            _HubPattern(
              future: _pattern,
              error: _patternError,
              onRetry: () => _reload(
                _c.selectedDay,
                journal: false,
                meals: false,
                targets: false,
              ),
            ),
            const SizedBox(height: 10),
            OBCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: SetRow(
                LucideIcons.pill,
                OB.of(context).muted,
                'Medikamente',
                key: const ValueKey('medication-journal'),
                onTap: () => OpenBandMedications.push(
                  context,
                  repository: _c.repository,
                  day: _c.selectedDay,
                  now: _c.now,
                  synthetic: _c.day?.synthetic == true,
                ),
              ),
            ),
            if (_cycleEnabled == true || _cycleReadError) ...[
              const SizedBox(height: 10),
              OBCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                child: SetRow(
                  LucideIcons.droplet,
                  OB.of(context).muted,
                  'Zyklus',
                  key: const ValueKey('cycle-journal'),
                  value: _cycleReadError ? '—' : '',
                  sub: _cycleReadError ? 'Daten nicht geladen' : '',
                  onTap: _cycleReadError
                      ? () => _loadCycle(_c.selectedDay, ++_cycleSeq)
                      : _openCycle,
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

class OBCheckinCard extends StatelessWidget {
  final int? mood;
  final bool? caffeineLate, alcoholEvening, readBeforeBed;
  final bool busy;
  final String? error;
  final ValueChanged<int?> onMood;
  final ValueChanged<bool?> onCaffeine, onAlcohol, onRead;
  final VoidCallback? onRetry;
  final String? retryLabel;
  const OBCheckinCard({
    super.key,
    required this.mood,
    required this.caffeineLate,
    required this.alcoholEvening,
    required this.readBeforeBed,
    required this.busy,
    this.error,
    required this.onMood,
    required this.onCaffeine,
    required this.onAlcohol,
    required this.onRead,
    this.onRetry,
    this.retryLabel,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    Widget habit({
      required String label,
      required IconData icon,
      required bool? value,
      required ValueChanged<bool?> onChanged,
    }) => DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.line)),
      ),
      child: OBJournalYesNo(
        label: label,
        icon: icon,
        value: value,
        enabled: !busy,
        onChanged: onChanged,
      ),
    );
    return OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Wie fühlst du dich?',
            style: p
                .text(15, weight: FontWeight.w600)
                .copyWith(height: 20 / 15),
          ),
          const SizedBox(height: 12),
          IgnorePointer(
            ignoring: busy,
            child: OBJournalMoodScale(value: mood, onChanged: onMood),
          ),
          const SizedBox(height: 12),
          habit(
            label: 'Koffein nach 14 Uhr',
            icon: LucideIcons.coffee,
            value: caffeineLate,
            onChanged: onCaffeine,
          ),
          habit(
            label: 'Alkohol',
            icon: LucideIcons.wine,
            value: alcoholEvening,
            onChanged: onAlcohol,
          ),
          habit(
            label: 'Abends gelesen',
            icon: LucideIcons.bookOpen,
            value: readBeforeBed,
            onChanged: onRead,
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error!,
              style: p.text(13, color: p.danger).copyWith(height: 18 / 13),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              OBAction(
                retryLabel ?? CaffeineSleepPattern.retryLabel,
                ink: true,
                onPressed: onRetry,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _HubNutrition extends StatelessWidget {
  final Future<DayMeals>? meals;
  final Object? mealsError;
  final Future<NutritionTargetSnapshot>? targets;
  final Object? targetsError;
  final FutureOr<void> Function()? onTap;
  final VoidCallback? onRetry;
  const _HubNutrition({
    required this.meals,
    required this.mealsError,
    required this.targets,
    required this.targetsError,
    this.onTap,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    if (mealsError != null) {
      return OBCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Text(
              'Einträge konnten nicht geladen werden.',
              style: p.text(15).copyWith(height: 21 / 15),
            ),
            OBAction(
              CaffeineSleepPattern.retryLabel,
              ink: true,
              onPressed: onRetry,
            ),
          ],
        ),
      );
    }
    return FutureBuilder<DayMeals>(
      future: meals,
      builder: (context, mealSnap) {
        if (!mealSnap.hasData) {
          return const SizedBox.shrink();
        }
        return FutureBuilder<NutritionTargetSnapshot>(
          future: targets,
          builder: (context, targetSnap) {
            if (targetsError == null && !targetSnap.hasData) {
              return const SizedBox.shrink();
            }
            final NutritionTargetValues? values = targetsError != null
                ? null
                : targetSnap.data?.values;
            final card = OBMacroBars(
              meals: mealSnap.data!,
              targets: values,
              targetsUnavailable: targetsError != null,
            );
            final tappable = onTap == null
                ? card
                : Semantics(
                    button: true,
                    label: 'Ernährung',
                    child: InkWell(
                      onTap: onTap,
                      borderRadius: BorderRadius.circular(AlpRadius.card),
                      child: card,
                    ),
                  );
            if (targetsError == null) return tappable;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                OBCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: [
                      Text(
                        'Ziele konnten nicht geladen werden.',
                        style: p.text(15).copyWith(height: 21 / 15),
                      ),
                      OBAction(
                        CaffeineSleepPattern.retryLabel,
                        ink: true,
                        onPressed: onRetry,
                      ),
                    ],
                  ),
                ),
                tappable,
              ],
            );
          },
        );
      },
    );
  }
}

class _HubPattern extends StatelessWidget {
  final Future<CaffeineSleepPattern>? future;
  final Object? error;
  final VoidCallback? onRetry;
  const _HubPattern({required this.future, this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return OBPatternCard(error: true, onRetry: onRetry);
    }
    return FutureBuilder<CaffeineSleepPattern>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return OBPatternCard(error: true, onRetry: onRetry);
        }
        return OBPatternCard(pattern: snapshot.data);
      },
    );
  }
}

class OBPatternCard extends StatelessWidget {
  final CaffeineSleepPattern? pattern;
  final bool error;
  final VoidCallback? onRetry;
  const OBPatternCard({
    super.key,
    this.pattern,
    this.error = false,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final s = pattern;
    Widget info() => SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        tooltip: 'Information',
        onPressed: s == null
            ? null
            : () => showOpenBandJournalInfo(
                context,
                title: CaffeineSleepPattern.infoTitle,
                body: _patternInfoBody(s),
              ),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        icon: Icon(LucideIcons.info, size: 20, color: p.muted),
      ),
    );
    Widget header() {
      final opsz = MediaQuery.textScalerOf(context).scale(15).clamp(14.0, 32.0);
      return Row(
        children: [
          Expanded(
            child: Text(
              CaffeineSleepPattern.title,
              style: p
                  .text(15, weight: FontWeight.w600)
                  .copyWith(
                    height: 20 / 15,
                    fontVariations: [FontVariation('opsz', opsz)],
                  ),
            ),
          ),
          info(),
        ],
      );
    }

    if (error) {
      return OBCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            header(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                Text(
                  CaffeineSleepPattern.loadError,
                  style: p.text(15).copyWith(height: 21 / 15),
                ),
                OBAction(
                  CaffeineSleepPattern.retryLabel,
                  ink: true,
                  onPressed: onRetry,
                ),
              ],
            ),
          ],
        ),
      );
    }
    if (s == null) return const SizedBox.shrink();
    final Widget body = switch (s.kind) {
      CaffeineSleepPatternKind.meaningful => _meaningfulBody(context, p, s),
      CaffeineSleepPatternKind.nonmeaningful => _statusBody(
        p,
        CaffeineSleepPattern.noClearPattern,
        '${s.pairedN} ${CaffeineSleepPattern.nightsWithEntry}',
      ),
      CaffeineSleepPatternKind.insufficient => _statusBody(
        p,
        CaffeineSleepPattern.tooFewNights,
        '${s.pairedN} ${CaffeineSleepPattern.nightsWithEntry}',
      ),
      CaffeineSleepPatternKind.unavailable => _statusBody(
        p,
        CaffeineSleepPattern.unavailableTitle,
        CaffeineSleepPattern.unavailableDetail,
      ),
    };
    return OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          header(),
          body,
          if (s.partial)
            Text(
              CaffeineSleepPattern.partialLabel,
              style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
            ),
        ],
      ),
    );
  }

  Widget _statusBody(OB p, String title, String detail) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Text(
          title,
          style: p.text(17, weight: FontWeight.w600).copyWith(height: 24 / 17),
        ),
        Text(
          detail,
          style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
        ),
      ],
    ),
  );

  Widget _meaningfulBody(BuildContext context, OB p, CaffeineSleepPattern s) {
    final nightStyle = p.text(13, color: p.muted).copyWith(height: 18 / 13);
    final comparisonStyle = p
        .text(13, color: p.muted)
        .copyWith(height: 18 / 13);
    final stacked =
        MediaQuery.textScalerOf(context).scale(13) > 20 ||
        MediaQuery.sizeOf(context).width < 360;
    final delta = Text(
      _patternDeltaLabel(s.delta),
      style: p
          .text(34, weight: FontWeight.w700, display: true)
          .copyWith(height: 40 / 34),
    );
    final comparison = Text(
      CaffeineSleepPattern.comparisonLabel,
      style: comparisonStyle,
    );
    final ja = Text('Ja · ${s.yesNights} Nächte', style: nightStyle);
    final nein = Text('Nein · ${s.noNights} Nächte', style: nightStyle);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [delta, comparison],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  delta,
                  const SizedBox(width: 12),
                  Expanded(child: comparison),
                ],
              ),
        stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [ja, nein],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [ja, nein],
              ),
      ],
    );
  }
}

String _patternDeltaLabel(double? delta) {
  if (delta == null || !delta.isFinite) return '—';
  final digits = delta == delta.roundToDouble() ? 0 : 1;
  final magnitude = obNumber(delta.abs(), digits: digits);
  if (delta > 0) return '+$magnitude Min.';
  if (delta < 0) return '−$magnitude Min.';
  return '$magnitude Min.';
}

String _patternInfoBody(CaffeineSleepPattern s) {
  final windowStart = openBandDaysEnding(s.endDay, s.nights).first;
  final start = DateFormat(
    'd. MMMM',
    'de_DE',
  ).format(DateTime.parse(windowStart));
  final end = DateFormat('d. MMMM', 'de_DE').format(DateTime.parse(s.endDay));
  final n = s.pairedN;
  return '$start–$end · $n Nächte\n'
      '${CaffeineSleepPattern.infoComparison}\n'
      '${CaffeineSleepPattern.infoEligibility}\n'
      '${CaffeineSleepPattern.infoCausation}';
}
