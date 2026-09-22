import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'action_sheet.dart';
import 'alp_tokens.dart';
import 'controller.dart';
import 'domain.dart';
import 'theme.dart';

class OpenBandTraining extends StatelessWidget {
  final OpenBandController controller;
  final ValueChanged<String>? onStart;
  final Future<void> Function(WorkoutTemplate)? onStartTemplate;
  final Future<void> Function(WorkoutTemplate?)? onEditTemplate;
  final VoidCallback? onOpenTemplates;
  final ValueChanged<TrainingSession>? onOpen;
  const OpenBandTraining({
    super.key,
    required this.controller,
    this.onStart,
    this.onStartTemplate,
    this.onEditTemplate,
    this.onOpenTemplates,
    this.onOpen,
  });
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final p = OB.of(context);
      return ColoredBox(
        color: p.canvas,
        child: ListView(
          key: const PageStorageKey('openband.training'),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Training',
                      style: p.text(30, weight: FontWeight.w800, display: true),
                    ),
                  ),
                  if (onOpenTemplates != null)
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: Material(
                        color: p.card,
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: IconButton(
                          tooltip: 'Vorlagen',
                          onPressed: onOpenTemplates,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 44,
                            height: 44,
                          ),
                          icon: Icon(LucideIcons.list, size: 20, color: p.ink),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            OBQuickStart(onStart: onStart),
            const SizedBox(height: 10),
            _HubTemplate(
              controller: controller,
              onStart: onStartTemplate,
              onEdit: onEditTemplate,
            ),
            FutureBuilder<List<TrainingSession>>(
              key: ValueKey('sessions-${controller.selectedDay}'),
              future: controller.repository.readSessions(
                controller.selectedDay,
                30,
              ),
              builder: (context, snapshot) {
                final sessions = snapshot.data;
                if (snapshot.hasError) {
                  return OBCard(
                    child: Text(
                      'Einheiten konnten nicht geladen werden.',
                      style: p.text(14, color: p.danger),
                    ),
                  );
                }
                if (sessions == null) return const SizedBox(height: 200);
                final week = openBandDaysEnding(controller.selectedDay, 7);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 10,
                  children: [
                    OBWeekBars(
                      days: week,
                      sessions: sessions.where((s) => !s.live).toList(),
                    ),
                    FutureBuilder<MuscleLoad>(
                      key: ValueKey('muscles-${controller.selectedDay}'),
                      future: controller.repository.readMuscleLoad(
                        controller.selectedDay,
                        7,
                      ),
                      builder: (context, snap) => snap.data == null
                          ? const SizedBox.shrink()
                          : OBMuscleBars(load: snap.data!),
                    ),
                    if (sessions.isEmpty)
                      OBCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 4,
                          children: [
                            Text(
                              'Noch keine Einheiten',
                              style: p.text(15, weight: FontWeight.w600),
                            ),
                            Text(
                              'Letzte 30 Tage',
                              style: p.text(13, color: p.muted),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                        child: Text(
                          'Zuletzt',
                          style: p.text(
                            20,
                            weight: FontWeight.w700,
                            display: true,
                          ),
                        ),
                      ),
                      OBCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        child: Column(
                          children: [
                            for (final (i, s) in sessions.indexed)
                              _SessionRow(
                                session: s,
                                divider: i > 0,
                                onTap: onOpen == null ? null : () => onOpen!(s),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      );
    },
  );
}

({String label, String icon}) obSport(String type) => switch (type) {
  'running' || 'treadmill' || 'sprinting' => (label: 'Laufen', icon: 'run'),
  'walking' || 'dog_walking' => (label: 'Gehen', icon: 'walk'),
  'hiking' => (label: 'Wandern', icon: 'trekking'),
  'cycling' ||
  'indoor_bike' ||
  'mountain_biking' => (label: 'Rad', icon: 'bike'),
  'swimming' => (label: 'Schwimmen', icon: 'swimming'),
  'rowing' || 'kayaking' => (label: 'Rudern', icon: 'kayak'),
  'weight_training' ||
  'powerlifting' ||
  'kettlebell' ||
  'functional' ||
  'crossfit' => (label: 'Kraft', icon: 'barbell'),
  'hiit' ||
  'track_intervals' ||
  'jump_rope' => (label: 'Intervalle', icon: 'jump-rope'),
  'yoga' || 'pilates' || 'tai_chi' => (label: 'Yoga', icon: 'yoga'),
  'football' => (label: 'Fußball', icon: 'ball-football'),
  'tennis' => (label: 'Tennis', icon: 'ball-tennis'),
  'basketball' => (label: 'Basketball', icon: 'ball-basketball'),
  'volleyball' => (label: 'Volleyball', icon: 'ball-volleyball'),
  'golf' => (label: 'Golf', icon: 'golf'),
  'boxing' || 'martial_arts' => (label: 'Kampfsport', icon: 'karate'),
  'climbing' => (label: 'Klettern', icon: 'mountain'),
  'skiing' => (label: 'Ski', icon: 'ski-jumping'),
  'skating' => (label: 'Eislaufen', icon: 'ice-skating'),
  'horse_riding' => (label: 'Reiten', icon: 'horse'),
  _ => (label: 'Aktivität', icon: 'stretching'),
};

/// Tabler outline glyph from assets/icons/sport (MIT, 3.46.0), same 24-grid
/// and 2 px stroke as Lucide; `currentColor` is replaced by [color].
class OBSportIcon extends StatelessWidget {
  final String name;
  final double size;
  final Color color;
  const OBSportIcon(
    this.name, {
    super.key,
    this.size = 20,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/icons/sport/$name.svg',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
  );
}

class OBQuickStart extends StatelessWidget {
  final ValueChanged<String>? onStart;
  const OBQuickStart({super.key, this.onStart});
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    Widget tile(String label, Widget icon, Color fg, Color bg, String? type) =>
        Expanded(
          child: Semantics(
            button: true,
            label: type == null ? 'Weitere Aktivitäten' : '$label starten',
            child: InkWell(
              onTap: onStart == null ? null : () => onStart!(type ?? ''),
              borderRadius: BorderRadius.circular(AlpRadius.row),
              child: ExcludeSemantics(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 96),
                  decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(AlpRadius.row),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    spacing: 8,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: icon,
                      ),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: p.text(13, weight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
    return Row(
      spacing: 8,
      children: [
        tile(
          'Kraft',
          OBSportIcon('barbell', color: p.strain),
          p.strain,
          p.strainTint,
          'weight_training',
        ),
        tile(
          'Laufen',
          OBSportIcon('run', color: p.strain),
          p.strain,
          p.strainTint,
          'running',
        ),
        tile(
          'Rad',
          OBSportIcon('bike', color: p.strain),
          p.strain,
          p.strainTint,
          'cycling',
        ),
        tile(
          'Mehr',
          Icon(LucideIcons.plus, size: 20, color: p.ink),
          p.ink,
          p.well,
          null,
        ),
      ],
    );
  }
}

class OBWeekBars extends StatelessWidget {
  final List<String> days;
  final List<TrainingSession> sessions;
  const OBWeekBars({super.key, required this.days, required this.sessions});
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final minutes = {for (final d in days) d: 0};
    var unknown = false, count = 0;
    for (final s in sessions) {
      if (!minutes.containsKey(s.day)) continue;
      count++;
      if (s.durationMin == null) {
        unknown = true;
      } else {
        minutes[s.day] = minutes[s.day]! + s.durationMin!;
      }
    }
    final total = minutes.values.fold(0, (a, b) => a + b);
    final max = minutes.values.fold(0, (a, b) => a > b ? a : b);
    return OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Letzte 7 Tage',
                  style: p.text(13, weight: FontWeight.w600, color: p.muted),
                ),
              ),
              Text(
                count == 0
                    ? 'keine Einheit'
                    : '$count ${count == 1 ? 'Einheit' : 'Einheiten'}',
                style: p.text(13, weight: FontWeight.w500, color: p.muted),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                count == 0 ? '—' : '${unknown ? 'mind. ' : ''}$total',
                style: p.text(28, weight: FontWeight.w800, display: true),
              ),
              const SizedBox(width: 4),
              Text(
                'Min.',
                style: p.text(14, weight: FontWeight.w500, color: p.muted),
              ),
              if (unknown) ...[
                const SizedBox(width: 10),
                Text(
                  'Dauer teils unbekannt',
                  style: p.text(13, weight: FontWeight.w600, color: p.muted),
                ),
              ],
            ],
          ),
          Semantics(
            label:
                'Trainingsminuten je Tag: ${days.map((d) => '${DateFormat('EEE', 'de_DE').format(DateTime.parse(d))} ${minutes[d]}').join(', ')}',
            child: ExcludeSemantics(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 80),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  spacing: 6,
                  children: [
                    for (final (i, d) in days.indexed)
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          spacing: 6,
                          children: [
                            Container(
                              height: max == 0 ? 4 : 4 + 48 * minutes[d]! / max,
                              decoration: BoxDecoration(
                                color: minutes[d]! > 0 ? p.strain : null,
                                border: i == days.length - 1 && minutes[d] == 0
                                    ? Border.all(color: p.gap, width: 1.5)
                                    : minutes[d] == 0
                                    ? Border.all(color: p.line, width: 1.5)
                                    : null,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            Text(
                              DateFormat(
                                'EEEEE',
                                'de_DE',
                              ).format(DateTime.parse(d)),
                              style: p.text(
                                11,
                                weight: FontWeight.w600,
                                color: p.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  final TrainingSession session;
  final bool divider;
  final VoidCallback? onTap;
  const _SessionRow({required this.session, required this.divider, this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final sport = obSport(session.type);
    final facts = [
      if (session.live)
        'läuft'
      else if (session.durationMin case final m?)
        '$m Min.',
      if (session.strain case final s?) 'Belastung ${obNumber(s, digits: 1)}',
    ];
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        decoration: divider
            ? BoxDecoration(
                border: Border(top: BorderSide(color: p.line)),
              )
            : null,
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: p.strainTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: OBSportIcon(sport.icon, size: 18, color: p.strain),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sport.label, style: p.text(15, weight: FontWeight.w600)),
                  Text(
                    facts.isEmpty ? 'ohne Messwerte' : facts.join(' · '),
                    style: p.text(13, color: p.muted),
                  ),
                ],
              ),
            ),
            Text(
              obDayTitle(session.day),
              style: p.text(13, weight: FontWeight.w500, color: p.muted),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Icon(LucideIcons.chevronRight, size: 16, color: p.gap),
            ],
          ],
        ),
      ),
    );
  }
}

class _HubTemplate extends StatefulWidget {
  final OpenBandController controller;
  final Future<void> Function(WorkoutTemplate)? onStart;
  final Future<void> Function(WorkoutTemplate?)? onEdit;
  const _HubTemplate({required this.controller, this.onStart, this.onEdit});
  @override
  State<_HubTemplate> createState() => _HubTemplateState();
}

class _HubTemplateState extends State<_HubTemplate> {
  List<WorkoutTemplate>? _templates;
  String? _pinnedId;
  Object? _error;
  bool _busy = false;
  int _load = 0;

  OpenBandRepository get _repo => widget.controller.repository;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final token = ++_load;
    try {
      final templates = await _repo.readTemplates();
      final pin = await _repo.readPinnedTemplateId();
      if (!mounted || token != _load) return;
      setState(() {
        _templates = templates;
        _pinnedId = pin;
        _error = null;
      });
    } catch (e) {
      if (!mounted || token != _load) return;
      setState(() => _error = e);
    }
  }

  Future<void> _start(WorkoutTemplate template) async {
    if (_busy || widget.onStart == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onStart!(template);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _menu(WorkoutTemplate template) async {
    if (_busy) return;
    final pinned = template.id == _pinnedId;
    final choice = await showTemplateActionSheet(
      context,
      template: template,
      pinned: pinned,
    );
    if (!mounted || choice == null) return;
    if (choice == TemplateMenuChoice.edit) {
      await widget.onEdit?.call(template);
      if (mounted) await _reload();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      switch (choice) {
        case TemplateMenuChoice.duplicate:
          await _repo.saveTemplate(copyWorkoutTemplate(template));
        case TemplateMenuChoice.pin:
          await _repo.pinTemplate(template.id);
        case TemplateMenuChoice.unpin:
          await _repo.pinTemplate(null);
        case TemplateMenuChoice.archive:
          await _repo.archiveTemplate(template.id);
        case TemplateMenuChoice.edit:
          break;
      }
      await _reload();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = switch (choice) {
            TemplateMenuChoice.duplicate => 'Speichern fehlgeschlagen',
            TemplateMenuChoice.archive => 'Archivieren fehlgeschlagen',
            _ => 'Anheften fehlgeschlagen',
          },
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final templates = _templates;
    if (_error != null && templates == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            Text(
              'Vorlagen konnten nicht geladen werden.',
              style: p.text(14, color: p.danger).copyWith(height: 18 / 14),
            ),
            OBAction(
              'Erneut laden',
              ink: true,
              onPressed: _busy ? null : _reload,
            ),
          ],
        ),
      );
    }
    if (templates == null) return const SizedBox.shrink();
    final featured = featuredTemplate(templates, _pinnedId);
    if (featured == null && _error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          if (_error != null) ...[
            Text(
              _error is String
                  ? _error! as String
                  : 'Vorlagen konnten nicht geladen werden.',
              style: p.text(14, color: p.danger).copyWith(height: 18 / 14),
            ),
            OBAction(
              'Erneut versuchen',
              ink: true,
              onPressed: _busy ? null : _reload,
            ),
          ],
          if (featured != null)
            OBTemplateRow(
              template: featured,
              pinned: featured.id == _pinnedId,
              busy: _busy,
              onStart: widget.onStart == null ? null : _start,
              onMenu: _menu,
            ),
        ],
      ),
    );
  }
}

class OBTemplateRow extends StatelessWidget {
  final WorkoutTemplate template;
  final bool pinned;
  final bool busy;
  final Future<void> Function(WorkoutTemplate)? onStart;
  final Future<void> Function(WorkoutTemplate)? onMenu;
  const OBTemplateRow({
    super.key,
    required this.template,
    this.pinned = false,
    this.busy = false,
    this.onStart,
    this.onMenu,
  });
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final nameStyle = p
        .text(15, weight: FontWeight.w600)
        .copyWith(height: 20 / 15);
    final startStyle = p
        .text(14, weight: FontWeight.w600)
        .copyWith(height: 18 / 14, color: p.dark ? p.canvas : Colors.white);
    Widget nameBlock({required bool stack}) => Align(
      alignment: Alignment.centerLeft,
      child: Stack(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 4,
            children: [
              Padding(
                padding: pinned
                    ? const EdgeInsets.only(right: 20)
                    : EdgeInsets.zero,
                child: Text(
                  template.name,
                  maxLines: stack ? 4 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: nameStyle,
                ),
              ),
              Text(
                obExerciseCount(template.exercises.length),
                style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
              ),
            ],
          ),
          if (pinned)
            Positioned(
              top: 2,
              right: 0,
              child: Icon(
                LucideIcons.pin,
                size: 14,
                color: p.muted,
                semanticLabel: 'Angeheftet',
              ),
            ),
        ],
      ),
    );
    Widget start({required bool wide}) => Semantics(
      button: true,
      enabled: !busy && onStart != null,
      label: 'Starten',
      child: ExcludeSemantics(
        child: SizedBox(
          width: wide ? double.infinity : 76,
          height: wide ? null : 44,
          child: FilledButton(
            onPressed: busy || onStart == null
                ? null
                : () => onStart!(template),
            style: FilledButton.styleFrom(
              backgroundColor: p.ink,
              foregroundColor: p.dark ? p.canvas : Colors.white,
              disabledBackgroundColor: p.ink.withValues(alpha: 0.4),
              minimumSize: Size(wide ? 44 : 76, 44),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: startStyle,
            ),
            child: busy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator.adaptive(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(p.card),
                    ),
                  )
                : Text('Starten', style: startStyle),
          ),
        ),
      ),
    );
    final more = SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        tooltip: 'Aktionen',
        onPressed: busy || onMenu == null ? null : () => onMenu!(template),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        icon: Icon(LucideIcons.ellipsis, size: 20, color: p.ink),
      ),
    );
    return Semantics(
      container: true,
      label: pinned ? '${template.name}, angeheftet' : template.name,
      child: Material(
        color: p.card,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 88),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: LayoutBuilder(
              builder: (context, c) {
                final stack = _templateRowShouldStack(
                  width: c.maxWidth,
                  name: template.name,
                  style: nameStyle,
                  scaler: scaler,
                  pinned: pinned,
                  textDirection: Directionality.of(context),
                );
                if (stack) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 10,
                    children: [
                      nameBlock(stack: true),
                      Row(
                        spacing: 10,
                        children: [
                          Expanded(child: start(wide: true)),
                          more,
                        ],
                      ),
                    ],
                  );
                }
                return Row(
                  spacing: 10,
                  children: [
                    Expanded(child: nameBlock(stack: false)),
                    start(wide: false),
                    more,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

bool _templateRowShouldStack({
  required double width,
  required String name,
  required TextStyle style,
  required TextScaler scaler,
  required bool pinned,
  required ui.TextDirection textDirection,
}) {
  if (scaler.scale(14) > 20) return true;
  const trailing = 76.0 + 10 + 44;
  const gap = 10.0;
  final nameMax = width - trailing - gap - (pinned ? 20 : 0);
  if (!(nameMax > 0)) return true;
  final painter = TextPainter(textDirection: textDirection, textScaler: scaler);
  try {
    for (final word in name.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      painter.text = TextSpan(text: word, style: style);
      painter.layout();
      if (painter.width > nameMax) return true;
    }
    return false;
  } finally {
    painter.dispose();
  }
}

class OBMuscleBars extends StatelessWidget {
  final MuscleLoad load;
  const OBMuscleBars({super.key, required this.load});
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final entries = load.setsByMuscle.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty && load.unmapped == 0) return const SizedBox.shrink();
    final max = entries.isEmpty ? 0 : entries.first.value;
    return OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sätze je Muskelgruppe',
                  style: p.text(13, weight: FontWeight.w600, color: p.muted),
                ),
              ),
              Text(
                'Letzte 7 Tage',
                style: p.text(13, weight: FontWeight.w500, color: p.muted),
              ),
            ],
          ),
          for (final e in entries.take(6))
            Row(
              children: [
                SizedBox(
                  width: 84,
                  child: Text(
                    e.key,
                    style: p.text(14, weight: FontWeight.w500),
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 10,
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: p.well,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: FractionallySizedBox(
                      widthFactor: max == 0 ? 0 : e.value / max,
                      child: Container(
                        decoration: BoxDecoration(
                          color: p.strain,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    '${e.value}',
                    textAlign: TextAlign.right,
                    style: p.text(14, weight: FontWeight.w700, display: true),
                  ),
                ),
              ],
            ),
          if (load.unmapped > 0)
            Text(
              '${load.unmapped} ${load.unmapped == 1 ? 'Satz' : 'Sätze'} ohne Muskelzuordnung',
              style: p.text(12, color: p.muted),
            ),
        ],
      ),
    );
  }
}
