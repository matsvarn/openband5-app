import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../run_live.dart';
import '../chrome.dart' show OBActionPrimary, OBActionSecondary;
import '../g3_theme.dart';
import '../training_parts.dart';

/// G3 presentation over the existing durable AppState workout engine.
/// The caller still owns pause, resume, finish and recovery.
class G3LiveRun extends StatefulWidget {
  final ValueListenable<LiveRun> run;
  final String sport;
  final FutureOr<void> Function() onPause, onResume;
  final Future<void> Function() onFinish;
  final Future<void> Function()? onDiscard;
  final VoidCallback? onCollapse;
  final bool initiallyFinishing, initiallySaving, initiallyFailed;
  const G3LiveRun({
    super.key,
    required this.run,
    required this.sport,
    required this.onPause,
    required this.onResume,
    required this.onFinish,
    this.onDiscard,
    this.onCollapse,
    this.initiallyFinishing = false,
    this.initiallySaving = false,
    this.initiallyFailed = false,
  });

  @override
  State<G3LiveRun> createState() => _G3LiveRunState();
}

class _G3LiveRunState extends State<G3LiveRun> {
  late bool finishing = widget.initiallyFinishing;
  late bool saving = widget.initiallySaving;
  late bool failed = widget.initiallyFailed;
  bool changingPause = false, discarding = false;

  Future<void> _changePause(bool paused) async {
    if (changingPause) return;
    setState(() => changingPause = true);
    try {
      await (paused ? widget.onPause() : widget.onResume());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pause konnte nicht gespeichert werden.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => changingPause = false);
    }
  }

  Future<void> _discard() async {
    if (saving || discarding || widget.onDiscard == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Einheit verwerfen?'),
        content: const Text('Diese Einheit wird nicht gespeichert.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Verwerfen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => discarding = true);
    try {
      await widget.onDiscard!();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Einheit konnte nicht verworfen werden.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => discarding = false);
    }
  }

  Future<void> _save() async {
    if (saving) return;
    setState(() {
      saving = true;
      failed = false;
    });
    try {
      await widget.onFinish();
      if (mounted) {
        setState(() {
          saving = false;
          finishing = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          failed = true;
          finishing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<LiveRun>(
    valueListenable: widget.run,
    builder: (context, run, _) {
      final g = G3.of(context);
      final hr = run.heartRate;
      final zone = hr == null ? null : run.zone;
      final started = run.paused ? 'PAUSIERT' : 'LÄUFT';
      final set = run.zoneSet;
      final canZone = zone != null && set != null;
      final active = run.activeSec.clamp(0, 1 << 30);
      if (failed) return _failure(context, run);
      return Scaffold(
        backgroundColor: g.page,
        body: Stack(
          children: [
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Einheit einklappen',
                          onPressed:
                              widget.onCollapse ??
                              () => Navigator.of(context).maybePop(),
                          icon: const Icon(LucideIcons.chevronDown),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '${trainingSport(widget.sport).toUpperCase()} · $started',
                                  maxLines: 1,
                                  softWrap: false,
                                  style: g.caps(size: 16),
                                ),
                              ),
                              Text(
                                run.startedAt == null
                                    ? 'auf dem iPhone'
                                    : 'seit ${run.startedAt!.hour.toString().padLeft(2, '0')}:${run.startedAt!.minute.toString().padLeft(2, '0')}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: g.t(12, 16, color: g.muted),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                    const SizedBox(height: 42),
                    Row(
                      children: [
                        Text('PULS', style: g.caps(color: g.muted)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            hr == null
                                ? 'Kein verlässlicher Bandpuls'
                                : 'vom Band',
                            textAlign: TextAlign.right,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: g.t(13, 17, color: g.ink2),
                          ),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            hr?.toString() ?? '—',
                            style: g.t(
                              112,
                              120,
                              weight: FontWeight.w700,
                              color: hr == null || run.paused ? g.gap : g.ink,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 18, left: 6),
                            child: Text(
                              '/min',
                              style: g.t(22, 26, color: g.ink2),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (run.paused) ...[
                      Text(
                        'Puls zählt nicht mit',
                        style: g.t(15, 20, color: g.ink2),
                      ),
                    ] else if (hr == null) ...[
                      Text(
                        'Band fester anlegen und auf einen stabilen Puls warten.',
                        style: g.t(15, 20, color: g.ink2),
                      ),
                    ] else if (canZone && zone == 0) ...[
                      Text(
                        'unter Zone 1',
                        style: g.t(20, 26, weight: FontWeight.w700),
                      ),
                    ] else if (canZone && zone >= 1 && zone <= 5) ...[
                      Row(
                        children: [
                          Text(
                            'Zone $zone',
                            style: g.t(24, 29, weight: FontWeight.w700),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _zoneCaption(run, zone),
                            style: g.t(15, 20, color: g.ink2),
                          ),
                        ],
                      ),
                    ] else
                      Text(
                        'Zonen: Grundlage unbekannt',
                        style: g.t(14, 19, color: g.ink2),
                      ),
                    const SizedBox(height: 14),
                    _liveZoneMeter(context, run, canZone: canZone),
                    const SizedBox(height: 38),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: g.raised(),
                      child: Row(
                        children: [
                          _stat(
                            context,
                            'DAUER',
                            _clock(active),
                            'aktive Zeit',
                          ),
                          _stat(
                            context,
                            'BELASTUNG',
                            trainingNumber(run.strain, signed: true),
                            run.paused
                                ? 'bisher'
                                : hr == null
                                ? 'wartet auf Signal'
                                : 'bisher',
                          ),
                          if (run.averageHr case final average?)
                            _stat(
                              context,
                              'Ø PULS',
                              average.toString(),
                              run.maxHrSeen == null
                                  ? '/min'
                                  : 'max ${run.maxHrSeen}',
                            ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: OBActionSecondary(
                            run.paused ? 'Fortsetzen' : 'Pause',
                            onPressed: changingPause
                                ? null
                                : () => _changePause(!run.paused),
                            expand: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OBActionPrimary(
                            'Beenden',
                            onPressed: () => setState(() => finishing = true),
                            expand: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (finishing) Positioned.fill(child: _finishSheet(context, run)),
          ],
        ),
      );
    },
  );

  Widget _finishSheet(BuildContext context, LiveRun run) {
    final g = G3.of(context);
    return ColoredBox(
      color: const Color(0x66000000),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 26),
          decoration: BoxDecoration(
            color: g.canvas,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 5,
                    decoration: BoxDecoration(
                      color: g.gap,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Training beenden?',
                        style: g.t(24, 29, weight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Weiter trainieren',
                      onPressed: saving
                          ? null
                          : () => setState(() => finishing = false),
                      icon: const Icon(LucideIcons.x),
                    ),
                  ],
                ),
                Text(
                  'Zonen und Pulserholung werden nach dem Speichern berechnet.',
                  style: g.t(14, 20, color: g.ink2),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: g.raised(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          trainingSportIcon(
                            widget.sport,
                            size: 26,
                            color: g.ink,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            trainingSport(widget.sport),
                            style: g.t(21, 26, weight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _stat(
                            context,
                            'DAUER',
                            '${(run.activeSec / 60).round()} Min.',
                            '',
                          ),
                          _stat(
                            context,
                            'BELASTUNG',
                            trainingNumber(run.strain, signed: true),
                            '',
                          ),
                          if (run.averageHr case final average?)
                            _stat(
                              context,
                              'Ø PULS',
                              average.toString(),
                              run.maxHrSeen == null
                                  ? '/min'
                                  : 'max ${run.maxHrSeen}',
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OBActionSecondary(
                        'Weiter trainieren',
                        onPressed: saving
                            ? null
                            : () => setState(() => finishing = false),
                        expand: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OBActionPrimary(
                        saving ? 'Speichert …' : 'Speichern',
                        onPressed: saving ? null : _save,
                        expand: true,
                      ),
                    ),
                  ],
                ),
                if (widget.onDiscard != null) ...[
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: saving || discarding ? null : _discard,
                    child: const Text('Verwerfen'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _failure(BuildContext context, LiveRun run) {
    final g = G3.of(context);
    return Scaffold(
      backgroundColor: g.page,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextButton.icon(
                onPressed:
                    widget.onCollapse ?? () => Navigator.of(context).maybePop(),
                icon: const Icon(LucideIcons.chevronLeft),
                label: const Text('Training'),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: g.pressed(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Noch nicht gespeichert',
                      style: g.t(21, 26, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Die Einheit bleibt auf diesem iPhone. Versuche das Speichern erneut.',
                      style: g.t(15, 21, color: g.ink2),
                    ),
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        OBActionPrimary(
                          'Erneut speichern',
                          onPressed: saving ? null : _save,
                        ),
                        const SizedBox(width: 8),
                        OBActionSecondary(
                          'Später',
                          onPressed: saving
                              ? null
                              : widget.onCollapse ??
                                    () => Navigator.of(context).maybePop(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: g.raised(),
                child: Row(
                  children: [
                    _stat(
                      context,
                      'DAUER',
                      '${(run.activeSec / 60).round()} Min.',
                      '',
                    ),
                    _stat(
                      context,
                      'BELASTUNG',
                      trainingNumber(run.strain, signed: true),
                      '',
                    ),
                    if (run.averageHr case final average?)
                      _stat(
                        context,
                        'Ø PULS',
                        average.toString(),
                        run.maxHrSeen == null ? '/min' : 'max ${run.maxHrSeen}',
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _liveZoneMeter(
  BuildContext context,
  LiveRun run, {
  required bool canZone,
}) {
  final g = G3.of(context);
  final showZone = canZone && !run.paused;
  final set = showZone ? run.zoneSet : null;
  final first = set?.zones.first.lower;
  final last = set?.zones.last.upper;
  final fraction =
      !showZone ||
          run.heartRate == null ||
          first == null ||
          last == null ||
          last <= first
      ? null
      : ((run.heartRate! - first) / (last - first)).clamp(0.0, 1.0);
  return Column(
    children: [
      SizedBox(
        height: 25,
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 7,
                child: Row(
                  children: [
                    for (var i = 0; i < 5; i++) ...[
                      if (i > 0) const SizedBox(width: 3),
                      Expanded(
                        child: Container(
                          height: 10,
                          decoration: BoxDecoration(
                            color: showZone ? g.zones[i] : g.track,
                            border: showZone ? null : Border.all(color: g.gap),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (fraction != null)
                Positioned(
                  left: (fraction * (box.maxWidth - 5)).clamp(
                    0.0,
                    box.maxWidth - 5,
                  ),
                  top: 0,
                  child: Container(
                    width: 5,
                    height: 24,
                    decoration: BoxDecoration(
                      color: g.ink,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: g.page, width: 1),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      Row(
        children: [
          for (var i = 1; i <= 5; i++)
            Expanded(
              child: Text(
                'Z$i',
                textAlign: TextAlign.center,
                style: g.t(
                  12,
                  16,
                  weight: showZone && run.zone == i
                      ? FontWeight.w700
                      : FontWeight.w400,
                  color: showZone && run.zone == i ? g.ink : g.muted,
                ),
              ),
            ),
        ],
      ),
    ],
  );
}

String _zoneCaption(LiveRun run, int zone) {
  final set = run.zoneSet!;
  final band = set.zones[zone - 1];
  final bpm = zone == 5
      ? 'ab ${band.lower.round()} /min'
      : '${band.lower.round()}–${band.upper.round()} /min';
  final basis = switch (set.source) {
    'karvonen' => '% Pulsreserve',
    'tanaka' || 'observed' => '% HFmax',
    _ => null,
  };
  if (basis == null) return bpm;
  return '$bpm · ${(band.lowerPct * 100).round()}–${(band.upperPct * 100).round()} $basis';
}

String _clock(int sec) =>
    '${(sec ~/ 60).toString().padLeft(2, '0')}:${(sec % 60).toString().padLeft(2, '0')}';

Widget _stat(BuildContext context, String label, String value, String sub) {
  final g = G3.of(context);
  return Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: g.caps(color: g.muted, size: 11)),
        const SizedBox(height: 5),
        Text(
          value,
          style: g.t(
            26,
            31,
            weight: FontWeight.w700,
            color: value == '—' ? g.gap : g.ink,
          ),
        ),
        Text(sub, style: g.t(12, 16, color: g.ink2)),
      ],
    ),
  );
}
