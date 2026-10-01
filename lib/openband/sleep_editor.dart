import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';
import '../data/day_label.dart';
import 'controller.dart';
import 'domain.dart';
import 'theme.dart';
import 'time.dart';
import 'g3/chrome.dart' as g3_chrome;
import 'g3/g3_theme.dart';
import 'g3/g3_format.dart';
import 'g3/metrics.dart' show G3LabelRow;

String _g3ClockOrDash(DateTime? time) => time == null ? '—' : g3Clock(time);

double _windowScaleX(int minute, double width, {required bool g3}) {
  final afterEightPm = minute >= 20 * 60 ? minute - 20 * 60 : minute + 4 * 60;
  return width * (afterEightPm / ((g3 ? 14 : 12) * 60)).clamp(0.0, 1.0);
}

class SleepEditor extends StatefulWidget {
  final OpenBandController controller;
  final VoidCallback? onReturnToOverview;
  final bool g3;
  final SleepCorrection? initialReceipt;
  final String? initialSaveError;
  const SleepEditor({
    super.key,
    required this.controller,
    this.onReturnToOverview,
    this.g3 = false,
    this.initialReceipt,
    this.initialSaveError,
  });
  @override
  State<SleepEditor> createState() => _SleepEditorState();
}

class _WindowScalePainter extends CustomPainter {
  final OB p;
  final DateTime start, end;
  final DateTime? originalStart, originalEnd;
  final bool g3;
  const _WindowScalePainter({
    required this.p,
    required this.start,
    required this.end,
    required this.originalStart,
    required this.originalEnd,
    this.g3 = false,
  });

  double _x(DateTime time, double width) {
    return _windowScaleX(time.hour * 60 + time.minute, width, g3: g3);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final track = RRect.fromLTRBR(0, 14, width, 34, const Radius.circular(6));
    canvas.drawRRect(track, Paint()..color = p.well);
    if (originalStart != null &&
        originalEnd != null &&
        _x(originalEnd!, width) > _x(originalStart!, width)) {
      canvas.drawRRect(
        RRect.fromLTRBR(
          _x(originalStart!, width),
          19,
          _x(originalEnd!, width),
          29,
          const Radius.circular(3),
        ),
        Paint()..color = p.gap,
      );
    }
    final left = _x(start, width), right = _x(end, width);
    if (right > left) {
      canvas.drawRRect(
        RRect.fromLTRBR(left, 14, right, 34, const Radius.circular(5)),
        Paint()..color = p.ink.withValues(alpha: .16),
      );
      canvas.drawRRect(
        RRect.fromLTRBR(left, 14, right, 34, const Radius.circular(5)),
        Paint()
          ..color = p.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    for (final x in [left, right]) {
      final handle = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x.clamp(8.0, width - 8), 24),
          width: 14,
          height: 34,
        ),
        const Radius.circular(5),
      );
      canvas.drawRRect(handle, Paint()..color = p.card);
      canvas.drawRRect(
        handle,
        Paint()
          ..color = p.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
    if (!g3) {
      final tick = Paint()..color = p.muted;
      for (var i = 0; i <= 4; i++) {
        final x = math.min(width - .5, math.max(.5, width * i / 4));
        canvas.drawRect(Rect.fromLTWH(x, 43, 1, i.isEven ? 5 : 3), tick);
      }
    }
  }

  @override
  bool shouldRepaint(_WindowScalePainter old) =>
      old.p != p ||
      old.start != start ||
      old.end != end ||
      old.g3 != g3 ||
      old.originalStart != originalStart ||
      old.originalEnd != originalEnd;
}

class _G3WindowAxis extends StatelessWidget {
  const _G3WindowAxis();

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return LayoutBuilder(
      builder: (context, box) => SizedBox(
        height: 22,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final hour in const [20, 0, 4, 8, 10]) ...[
              Positioned(
                left: _windowScaleX(hour * 60, box.maxWidth, g3: true) - .5,
                top: 0,
                child: Container(
                  key: ValueKey('sleep-window-tick-$hour'),
                  width: 1,
                  height: 5,
                  color: g.muted,
                ),
              ),
              if (hour != 8)
                Positioned(
                  left: (_windowScaleX(hour * 60, box.maxWidth, g3: true) - 17)
                      .clamp(0.0, box.maxWidth - 34),
                  top: 8,
                  width: 34,
                  child: Text(
                    '${hour.toString().padLeft(2, '0')}:00',
                    textAlign: TextAlign.center,
                    style: g.t(10, 14, color: g.muted),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SleepEditorState extends State<SleepEditor> {
  late final String day = widget.controller.selectedDay;
  late final SleepNight original =
      widget.controller.day?.sleep ?? const SleepNight();
  final startText = TextEditingController(), endText = TextEditingController();
  final endFocus = FocusNode();
  SleepDraft? draft;
  SleepCorrection? receipt;
  bool busy = false, loading = true, changed = false;
  bool saveFailed = false;
  String? error, draftError;
  Future<void> _draftWrite = Future.value();
  int _draftVersion = 0;
  @override
  void initState() {
    super.initState();
    receipt = widget.initialReceipt;
    _load();
  }

  Future<void> _load() async {
    try {
      final stored = await widget.controller.repository.readDraft(day);
      final end = recordedTime(
        original.wake ?? DateTime.parse('$day 07:00:00'),
        original.recordingTimezone,
      );
      final start = recordedTime(
        original.onset ?? DateTime(end.year, end.month, end.day - 1, 23),
        original.recordingTimezone,
      );
      if (!mounted) return;
      setState(() {
        draft =
            stored ??
            SleepDraft(
              id: const Uuid().v4(),
              day: day,
              onset: start,
              wake: end,
              recordingTimezone: original.recordingTimezone,
            );
        startText.text = widget.g3
            ? g3Clock(draft!.onset)
            : obTime(draft!.onset);
        endText.text = widget.g3 ? g3Clock(draft!.wake) : obTime(draft!.wake);
        changed = stored != null || widget.initialSaveError != null;
        saveFailed = widget.initialSaveError != null;
        error = widget.initialSaveError;
        loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'Der Entwurf konnte nicht geladen werden.';
          loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    startText.dispose();
    endText.dispose();
    endFocus.dispose();
    super.dispose();
  }

  DateTime? _time(DateTime date, String value) => parseRecordedTime(
    date,
    value,
    zone: draft?.recordingTimezone,
    previous: date,
  );

  bool _update() {
    if (draft == null) return false;
    final start = _time(draft!.onset, startText.text),
        end = _time(draft!.wake, endText.text);
    return _applyTimes(start, end);
  }

  bool _applyTimes(DateTime? start, DateTime? end) {
    if (draft == null) return false;
    String? issue;
    if (start == null || end == null) {
      issue =
          'Bitte eine gültige Uhrzeit eingeben, zum Beispiel 23:25. Zeitumstellungen werden berücksichtigt.';
    } else if (!end.isAfter(start)) {
      issue = 'Das Ende muss nach dem Beginn liegen.';
    } else if (dayLabelOf(end) != day) {
      issue = 'Das Ende muss zum gewählten Aufwachtag gehören.';
    } else if (end.difference(start) > const Duration(hours: 24)) {
      issue = 'Bitte ein Schlafzeitfenster von höchstens 24 Stunden wählen.';
    }
    if (issue != null) {
      setState(() => error = issue);
      return false;
    }
    setState(() {
      draft = draft!.withTimes(start!, end!);
      error = null;
      changed = true;
    });
    _persistDraft();
    return true;
  }

  void _step(bool start, int minutes) {
    final value = start ? draft!.onset : draft!.wake;
    final next = value.add(Duration(minutes: minutes));
    if (_applyTimes(start ? next : draft!.onset, start ? draft!.wake : next)) {
      (start ? startText : endText).text = widget.g3
          ? g3Clock(next)
          : obTime(next);
    }
  }

  void _persistDraft() {
    final value = draft!;
    final version = ++_draftVersion;
    _draftWrite = _draftWrite.then((_) async {
      try {
        await widget.controller.repository.saveDraft(value);
        if (mounted && version == _draftVersion) {
          setState(() => draftError = null);
        }
      } catch (_) {
        if (mounted && version == _draftVersion) {
          setState(
            () => draftError =
                'Der Entwurf ist noch nicht auf dem iPhone gesichert. Bitte geöffnet lassen und erneut versuchen.',
          );
        }
      }
    });
  }

  Future<void> _date(bool start) async {
    final current = start ? draft!.onset : draft!.wake;
    final date = await showDatePicker(
      context: context,
      locale: const Locale('de'),
      initialDate: current,
      firstDate: DateTime(current.year - 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final updated = parseRecordedTime(
      date,
      widget.g3 ? g3Clock(current) : obTime(current),
      zone: draft!.recordingTimezone,
      previous: current,
    );
    if (updated == null) {
      setState(
        () => error =
            'Diese Uhrzeit ist wegen der Zeitumstellung nicht eindeutig.',
      );
      return;
    }
    setState(
      () => draft = start
          ? draft!.withTimes(updated, draft!.wake)
          : draft!.withTimes(draft!.onset, updated),
    );
    _update();
  }

  Future<void> _leave() async {
    if (busy) return;
    if (receipt != null) {
      Navigator.pop(context);
      return;
    }
    if (!changed) {
      Navigator.pop(context);
      return;
    }
    await _draftWrite;
    if (!mounted) return;
    final Future<String?> actionFuture = widget.g3
        ? showModalBottomSheet<String>(
            context: context,
            useSafeArea: true,
            backgroundColor: Colors.transparent,
            builder: (sheet) => g3_chrome.OBSheet(
              title: 'Änderung behalten?',
              cancelLabel: 'Weiter bearbeiten',
              confirmLabel: 'Verwerfen',
              onCancel: () => Navigator.pop(sheet, 'continue'),
              onConfirm: () => Navigator.pop(sheet, 'discard'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    draftError ??
                        'Dein Entwurf bleibt für diese Nacht gespeichert. Die Schlafzeiten ändern sich erst nach deiner Bestätigung.',
                  ),
                  if (draftError == null) ...[
                    const SizedBox(height: 12),
                    g3_chrome.OBActionSecondary(
                      'Entwurf behalten',
                      expand: true,
                      onPressed: () => Navigator.pop(sheet, 'keep'),
                    ),
                  ],
                ],
              ),
            ),
          )
        : showDialog<String>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Änderung behalten?'),
              content: Text(
                draftError ??
                    'Dein Entwurf bleibt für diese Nacht gespeichert. Die Schlafzeiten ändern sich erst nach deiner Bestätigung.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, 'continue'),
                  child: const Text('Weiter bearbeiten'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(c, 'discard'),
                  child: const Text('Verwerfen'),
                ),
                if (draftError == null)
                  TextButton(
                    onPressed: () => Navigator.pop(c, 'keep'),
                    child: const Text('Entwurf behalten'),
                  ),
              ],
            ),
          );
    final action = await actionFuture;
    if (action == 'discard') {
      try {
        await widget.controller.repository.discardDraft(day);
      } catch (_) {
        if (mounted) {
          setState(() => error = 'Der Entwurf konnte nicht verworfen werden.');
        }
        return;
      }
    }
    if ((action == 'keep' || action == 'discard') && mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _save() async {
    if (busy || !_update()) return;
    setState(() {
      busy = true;
      saveFailed = false;
    });
    await _draftWrite;
    try {
      final saved = await widget.controller.save(draft!);
      if (!mounted) return;
      setState(() {
        receipt = saved;
        busy = false;
        error = null;
      });
      unawaited(widget.controller.calculate(saved));
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          saveFailed = true;
          error = 'Speichern fehlgeschlagen.';
        });
      }
    }
  }

  void _showDetails() {
    final edit = draft;
    if (edit == null) return;
    if (widget.g3) {
      g3_chrome.showOBInfoSheet(
        context,
        title: 'Zeitfenster & Auswertung',
        paragraphs: [
          'Aufzeichnungszone: ${edit.recordingTimezone ?? 'nicht gespeichert'}.',
          edit.recordingTimezone == null
              ? 'Die Zeiten werden in der aktuellen iPhone-Zeitzone angezeigt. Prüfe Beginn, Ende und Datum.'
              : 'Beginn: ${edit.onset.timeZoneName}. Ende: ${edit.wake.timeZoneName}. Zeitumstellungen bleiben berücksichtigt.',
          'Die Vorschau ändert nur das Zeitfenster. Nach dem Speichern werden die vorhandenen Messungen neu ausgewertet. Fehlende Intervalle bleiben offen.',
        ],
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Zeitfenster & Auswertung',
                style: OB.of(context).text(18, weight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Text(
                'Aufzeichnungszone: ${edit.recordingTimezone ?? 'nicht gespeichert'}.',
              ),
              const SizedBox(height: 12),
              Text(
                edit.recordingTimezone == null
                    ? 'Die Zeiten werden in der aktuellen iPhone-Zeitzone angezeigt. Prüfe Beginn, Ende und Datum.'
                    : 'Beginn: ${edit.onset.timeZoneName}. Ende: ${edit.wake.timeZoneName}. Zeitumstellungen bleiben berücksichtigt.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Die Vorschau ändert nur das Zeitfenster. Nach dem Speichern werden die vorhandenen Messungen neu ausgewertet. Fehlende Intervalle bleiben offen.',
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Schließen'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final p = OB.of(context);
      final actual = widget.controller.day?.day == day
          ? widget.controller.day?.correction
          : null;
      final completed =
          receipt != null && actual?.state == CorrectionState.complete;
      final failed =
          receipt != null &&
          (actual?.state == CorrectionState.failed ||
              widget.controller.calculationErrors.containsKey(day));
      final title = receipt != null
          ? completed
                ? 'Schlaf aktualisiert'
                : failed
                ? 'Auswertung offen'
                : 'Zeiten gespeichert'
          : 'Schlafzeiten';
      return PopScope(
        canPop: !busy && draftError == null || receipt != null,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _leave();
        },
        child: Scaffold(
          backgroundColor: widget.g3 ? G3.of(context).page : p.canvas,
          body: SafeArea(
            child: loading
                ? const Center(child: CircularProgressIndicator.adaptive())
                : draft == null
                ? Center(
                    child: widget.g3
                        ? g3_chrome.OBActionSecondary(
                            'Entwurf erneut laden',
                            onPressed: _load,
                          )
                        : OBAction('Entwurf erneut laden', onPressed: _load),
                  )
                : Stack(
                    children: [
                      SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 140),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (widget.g3)
                              g3_chrome.OBPageHeader.detail(
                                title: 'SCHLAFZEITEN',
                                domain: G3Domain.sleep,
                                subtitle: g3NightOf(draft!.wake),
                                backLabel: receipt == null
                                    ? 'Abbrechen'
                                    : 'Schlaf',
                                onBack: _leave,
                                onTrailing: _showDetails,
                              )
                            else
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                child: G2PageHeader(
                                  title: title,
                                  backText: receipt == null
                                      ? 'Abbrechen'
                                      : 'Schlaf',
                                  subtitle: receipt == null
                                      ? 'Nacht ${DateFormat('E', 'de_DE').format(draft!.onset)} → ${DateFormat('E', 'de_DE').format(draft!.wake)} ${DateFormat('dd.MM', 'de_DE').format(draft!.wake)}'
                                      : obDate(day),
                                  onBack: _leave,
                                  onInfo: _showDetails,
                                  infoLabel: 'Zeitfenster und Auswertung',
                                ),
                              ),
                            if (widget.g3) const SizedBox(height: 12),
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: widget.g3 ? 16 : 20,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (completed)
                                    _resultCard()
                                  else if (widget.g3)
                                    _g3WindowCard()
                                  else
                                    _windowCard(),
                                  const SizedBox(height: 12),
                                  if (receipt == null) ...[
                                    if (widget.g3)
                                      _g3TimePair()
                                    else
                                      Row(
                                        spacing: 10,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _timeCard(true),
                                          _timeCard(false),
                                        ],
                                      ),
                                    const SizedBox(height: 12),
                                  ],
                                  if (error != null) ...[
                                    if (widget.g3 && saveFailed)
                                      g3_chrome.OBErrorBlock(
                                        title: 'Nicht gespeichert',
                                        reason:
                                            'Die Zeiten ließen sich nicht speichern. Dein Entwurf ${g3Clock(draft!.onset)}–${g3Clock(draft!.wake)} bleibt hier.',
                                        retryLabel: 'Erneut speichern',
                                        onRetry: _save,
                                        secondaryLabel: 'Details',
                                        onSecondary: _showDetails,
                                      )
                                    else
                                      Semantics(
                                        liveRegion: true,
                                        child: widget.g3
                                            ? g3_chrome.OBPanel(
                                                child: Text(
                                                  error!,
                                                  style: G3
                                                      .of(context)
                                                      .t(14, 18),
                                                ),
                                              )
                                            : OBCard(
                                                child: Text(
                                                  error!,
                                                  style: p.text(
                                                    14,
                                                    weight: FontWeight.w500,
                                                    color: widget.g3
                                                        ? p.ink
                                                        : p.danger,
                                                  ),
                                                ),
                                              ),
                                      ),
                                    const SizedBox(height: 12),
                                  ],
                                  if (draftError != null &&
                                      receipt == null) ...[
                                    Semantics(
                                      liveRegion: true,
                                      child: widget.g3
                                          ? g3_chrome.OBPanel(
                                              child: Column(
                                                children: [
                                                  Text(
                                                    draftError!,
                                                    style: G3
                                                        .of(context)
                                                        .t(13, 17),
                                                  ),
                                                  g3_chrome.OBPillButton(
                                                    'Entwurf erneut sichern',
                                                    onPressed: _persistDraft,
                                                  ),
                                                ],
                                              ),
                                            )
                                          : OBCard(
                                              child: Column(
                                                children: [
                                                  Text(
                                                    draftError!,
                                                    style: p.text(13),
                                                  ),
                                                  TextButton(
                                                    onPressed: _persistDraft,
                                                    child: const Text(
                                                      'Entwurf erneut sichern',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  if (receipt == null) ...[
                                    if (!widget.g3) ...[
                                      OBCard.inset(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 6,
                                        ),
                                        child: TextButton(
                                          onPressed: _showDetails,
                                          style: TextButton.styleFrom(
                                            padding: EdgeInsets.zero,
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  'Zeitzone',
                                                  style: p.text(
                                                    14,
                                                    color: p.muted,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                draft!.recordingTimezone ??
                                                    'Nicht gespeichert',
                                                style: p.text(13),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                    ],
                                    Text(
                                      'Nach dem Speichern wird die Nacht neu ausgewertet. Die Rohdaten bleiben unverändert.',
                                      style: p.text(12, color: p.muted),
                                    ),
                                  ] else ...[
                                    if (!completed) ...[
                                      if (widget.g3 &&
                                          !failed &&
                                          (widget.controller.calculating ||
                                              widget.initialReceipt !=
                                                  null)) ...[
                                        const g3_chrome.OBEmptyState(
                                          icon: LucideIcons.refreshCw,
                                          title: 'Wird neu ausgewertet',
                                          reason:
                                              'Phasen, Schlafschuld, Regelmäßigkeit',
                                        ),
                                        const SizedBox(height: 12),
                                      ],
                                      Semantics(
                                        liveRegion: true,
                                        child: widget.g3
                                            ? g3_chrome.OBPanel(
                                                child: Column(
                                                  children: [
                                                    _statusRow(
                                                      'Zeiten gespeichert',
                                                      '${g3Clock(receipt!.onset)}–${g3Clock(receipt!.wake)}',
                                                      LucideIcons.circleCheck,
                                                      p.ink,
                                                    ),
                                                    _statusRow(
                                                      'Schlaf & Erholung',
                                                      failed
                                                          ? 'Unterbrochen'
                                                          : 'Wird berechnet',
                                                      failed
                                                          ? LucideIcons.pause
                                                          : LucideIcons
                                                                .refreshCw,
                                                      failed
                                                          ? p.strainText
                                                          : p.action,
                                                    ),
                                                    _statusRow(
                                                      'Vorheriger Schlaf',
                                                      g3Duration(
                                                        original.duration.value
                                                            ?.round(),
                                                      ),
                                                      LucideIcons.clock3,
                                                      p.muted,
                                                    ),
                                                  ],
                                                ),
                                              )
                                            : OBCard(
                                                child: Column(
                                                  children: [
                                                    _statusRow(
                                                      'Zeiten gespeichert',
                                                      '${obTime(receipt!.onset)}–${obTime(receipt!.wake)}',
                                                      LucideIcons.circleCheck,
                                                      p.ink,
                                                    ),
                                                    _statusRow(
                                                      'Schlaf & Erholung',
                                                      failed
                                                          ? 'Unterbrochen'
                                                          : 'Wird berechnet',
                                                      failed
                                                          ? LucideIcons.pause
                                                          : LucideIcons
                                                                .refreshCw,
                                                      failed
                                                          ? p.strainText
                                                          : p.action,
                                                    ),
                                                    _statusRow(
                                                      'Vorheriger Schlaf',
                                                      obDuration(
                                                        original.duration.value,
                                                      ),
                                                      LucideIcons.clock3,
                                                      p.muted,
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      '${obTime(receipt!.savedAt)} auf dem iPhone gespeichert',
                                                      style: p.text(
                                                        12,
                                                        color: p.muted,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                      ),
                                      const SizedBox(height: 12),
                                    ],
                                    if (widget.g3 &&
                                        !completed &&
                                        !failed &&
                                        (widget.controller.calculating ||
                                            widget.initialReceipt != null)) ...[
                                      g3_chrome.OBActionPrimary(
                                        'Wird ausgewertet …',
                                        expand: true,
                                        onPressed: null,
                                      ),
                                      const SizedBox(height: 12),
                                    ] else if (failed ||
                                        !completed &&
                                            !widget.controller.calculating) ...[
                                      if (widget.g3)
                                        g3_chrome.OBActionPrimary(
                                          'Auswertung erneut starten',
                                          expand: true,
                                          onPressed: () => widget.controller
                                              .calculate(actual ?? receipt!),
                                        )
                                      else
                                        OBAction(
                                          'Auswertung erneut starten',
                                          onPressed: () => widget.controller
                                              .calculate(actual ?? receipt!),
                                        ),
                                      const SizedBox(height: 12),
                                    ] else ...[
                                      if (widget.g3)
                                        g3_chrome.OBActionPrimary(
                                          'Nacht ansehen',
                                          expand: true,
                                          onPressed: () =>
                                              Navigator.pop(context),
                                        )
                                      else
                                        OBAction(
                                          'Nacht ansehen',
                                          onPressed: () =>
                                              Navigator.pop(context),
                                        ),
                                      const SizedBox(height: 12),
                                    ],
                                    if (completed) ...[
                                      (widget.g3
                                          ? g3_chrome.OBActionSecondary(
                                              'Zeiten erneut ändern',
                                              expand: true,
                                              onPressed: () =>
                                                  Navigator.of(
                                                    context,
                                                  ).pushReplacement(
                                                    MaterialPageRoute<void>(
                                                      builder: (_) => SleepEditor(
                                                        controller:
                                                            widget.controller,
                                                        onReturnToOverview: widget
                                                            .onReturnToOverview,
                                                        g3: true,
                                                      ),
                                                    ),
                                                  ),
                                            )
                                          : OBAction(
                                              'Zeiten erneut ändern',
                                              secondary: true,
                                              onPressed: () =>
                                                  Navigator.of(
                                                    context,
                                                  ).pushReplacement(
                                                    MaterialPageRoute<void>(
                                                      builder: (_) => SleepEditor(
                                                        controller:
                                                            widget.controller,
                                                        onReturnToOverview: widget
                                                            .onReturnToOverview,
                                                        g3: widget.g3,
                                                      ),
                                                    ),
                                                  ),
                                            )),
                                      const SizedBox(height: 12),
                                      (widget.g3
                                          ? g3_chrome.OBActionSecondary(
                                              'Automatische Zeiten wiederherstellen',
                                              icon: LucideIcons.refreshCw,
                                              expand: true,
                                              onPressed: () async {
                                                final restored =
                                                    await restoreAutomaticSleep(
                                                      context,
                                                      widget.controller,
                                                      day,
                                                      g3: true,
                                                    );
                                                if (restored &&
                                                    context.mounted) {
                                                  Navigator.pop(context);
                                                }
                                              },
                                            )
                                          : OBCard(
                                              child: _actionRow(
                                                'Automatische Zeiten wiederherstellen',
                                                LucideIcons.refreshCw,
                                                p.action,
                                                () async {
                                                  final restored =
                                                      await restoreAutomaticSleep(
                                                        context,
                                                        widget.controller,
                                                        day,
                                                      );
                                                  if (restored &&
                                                      context.mounted) {
                                                    Navigator.pop(context);
                                                  }
                                                },
                                              ),
                                            )),
                                      const SizedBox(height: 8),
                                    ],
                                    if (!widget.g3 ||
                                        completed ||
                                        failed ||
                                        !widget.controller.calculating &&
                                            widget.initialReceipt == null)
                                      (widget.g3
                                          ? g3_chrome.OBActionSecondary(
                                              'Zur Übersicht',
                                              expand: true,
                                              onPressed: () {
                                                widget.onReturnToOverview
                                                    ?.call();
                                                Navigator.of(context).popUntil(
                                                  (route) => route.isFirst,
                                                );
                                              },
                                            )
                                          : OBAction(
                                              'Zur Übersicht',
                                              secondary: true,
                                              onPressed: () {
                                                widget.onReturnToOverview
                                                    ?.call();
                                                Navigator.of(context).popUntil(
                                                  (route) => route.isFirst,
                                                );
                                              },
                                            )),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (receipt == null)
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              widget.g3 ? 16 : 20,
                              8,
                              widget.g3 ? 16 : 20,
                              22,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (widget.g3 && saveFailed)
                                  const SizedBox.shrink()
                                else if (widget.g3)
                                  g3_chrome.OBActionPrimary(
                                    busy
                                        ? 'Wird gespeichert …'
                                        : saveFailed
                                        ? 'Erneut speichern'
                                        : 'Speichern',
                                    expand: true,
                                    onPressed: busy || !changed ? null : _save,
                                  )
                                else
                                  OBAction(
                                    busy
                                        ? 'Wird gespeichert …'
                                        : saveFailed
                                        ? 'Erneut speichern'
                                        : 'Schlafzeiten speichern',
                                    onPressed: busy || !changed ? null : _save,
                                  ),
                                if (widget.g3) const SizedBox(height: 8),
                                if (widget.g3)
                                  g3_chrome.OBActionSecondary(
                                    saveFailed
                                        ? 'Entwurf verwerfen'
                                        : 'Änderung verwerfen',
                                    expand: true,
                                    onPressed: busy || !changed
                                        ? null
                                        : _discard,
                                  )
                                else
                                  TextButton(
                                    onPressed: busy || !changed
                                        ? null
                                        : _discard,
                                    child: Text(
                                      'Änderung verwerfen',
                                      style: p.text(13, color: p.muted),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      );
    },
  );

  Future<void> _discard() async {
    try {
      await _draftWrite;
      await widget.controller.repository.discardDraft(day);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Der Entwurf konnte nicht verworfen werden.');
      }
    }
  }

  Widget _windowCard() {
    final p = OB.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(10) > 15;
    final previous = Text(
      original.onset == null || original.wake == null
          ? 'vorher —'
          : 'vorher ${obTime(original.onset)} – ${obTime(original.wake)}',
      style: p.text(10, color: p.muted),
      maxLines: 1,
    );
    return OBCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          if (largeText)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ZEITFENSTER', style: p.label(size: 10)),
                previous,
              ],
            )
          else
            Row(
              children: [
                Expanded(child: Text('ZEITFENSTER', style: p.label(size: 10))),
                previous,
              ],
            ),
          SizedBox(
            height: 48,
            child: CustomPaint(
              painter: _WindowScalePainter(
                p: p,
                start: draft!.onset,
                end: draft!.wake,
                originalStart: original.onset,
                originalEnd: original.wake,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('20:00', style: p.text(10, color: p.muted)),
              Text('02:00', style: p.text(10, color: p.muted)),
              Text('08:00', style: p.text(10, color: p.muted)),
            ],
          ),
          Text(
            original.segments.isEmpty
                ? 'Für dieses Zeitfenster liegt keine Aufzeichnung vor.'
                : 'Graues Band: Aufzeichnung vorhanden.',
            style: p.text(11, color: p.muted),
          ),
        ],
      ),
    );
  }

  Widget _g3WindowCard() {
    final g = G3.of(context);
    final bed = draft!.wake.difference(draft!.onset).inMinutes;
    final previous = original.onset == null || original.wake == null
        ? null
        : original.wake!.difference(original.onset!).inMinutes;
    final originalStart = original.onset == null
        ? null
        : recordedTime(original.onset!, original.recordingTimezone);
    final originalEnd = original.wake == null
        ? null
        : recordedTime(original.wake!, original.recordingTimezone);
    final windowChanged =
        originalStart != null &&
        originalEnd != null &&
        (!draft!.onset.isAtSameMomentAs(originalStart) ||
            !draft!.wake.isAtSameMomentAs(originalEnd));
    DateTime? recordedStart, recordedEnd;
    for (final segment in original.segments) {
      if (segment.stage == null) continue;
      if (recordedStart == null || segment.start.isBefore(recordedStart)) {
        recordedStart = segment.start;
      }
      if (recordedEnd == null || segment.end.isAfter(recordedEnd)) {
        recordedEnd = segment.end;
      }
    }
    final recordedSpan = recordedStart == null || recordedEnd == null
        ? '—'
        : '${g3Clock(recordedTime(recordedStart, original.recordingTimezone))}–${g3Clock(recordedTime(recordedEnd, original.recordingTimezone))}';
    return g3_chrome.OBPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const G3LabelRow('IM BETT', domain: G3Domain.sleep, arrow: false),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${g3Duration(bed)}${windowChanged ? ' · vorher ${g3Duration(previous)}' : ''}',
                  textAlign: TextAlign.end,
                  style: g.t(13, 17, color: g.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          RepaintBoundary(
            child: SizedBox(
              key: const ValueKey('sleep-window-bar'),
              height: 43,
              child: CustomPaint(
                painter: _WindowScalePainter(
                  p: OB.of(context),
                  start: draft!.onset,
                  end: draft!.wake,
                  originalStart: original.onset,
                  originalEnd: original.wake,
                  g3: true,
                ),
              ),
            ),
          ),
          const _G3WindowAxis(),
          const SizedBox(height: 12),
          Text(
            'Band hat aufgezeichnet $recordedSpan${windowChanged ? ' · vorher ${_g3ClockOrDash(originalStart)}–${_g3ClockOrDash(originalEnd)}' : ''}',
            style: g.t(12, 16, color: g.ink2),
          ),
        ],
      ),
    );
  }

  Widget _g3TimePair() {
    final g = G3.of(context);
    return g3_chrome.OBPanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _g3TimeControl(true)),
          Container(width: 1, height: 106, color: g.line),
          const SizedBox(width: 12),
          Expanded(child: _g3TimeControl(false)),
        ],
      ),
    );
  }

  Widget _g3TimeControl(bool start) {
    final g = G3.of(context);
    final value = start ? draft!.onset : draft!.wake;
    final text = start ? startText : endText;
    final enabled = receipt == null && !busy;
    final weekday = g3Weekday(value).toUpperCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: enabled ? () => _date(start) : null,
          child: SizedBox(
            height: 28,
            child: Text(
              '${start ? 'BEGINN' : 'ENDE'} · $weekday',
              style: g.caps(color: g.muted),
            ),
          ),
        ),
        Semantics(
          label: start ? 'Beginn der Nacht' : 'Ende der Nacht',
          child: TextField(
            key: ValueKey(start ? 'sleep-onset' : 'sleep-wake'),
            controller: text,
            focusNode: start ? null : endFocus,
            enabled: enabled,
            keyboardType: TextInputType.datetime,
            textInputAction: start
                ? TextInputAction.next
                : TextInputAction.done,
            style: g.t(32, 38, weight: FontWeight.w700),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (_) => _update(),
            onSubmitted: (_) {
              _update();
              if (start) {
                endFocus.requestFocus();
              } else {
                FocusScope.of(context).unfocus();
              }
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final delta in const [-5, 5]) ...[
              Expanded(
                child: Semantics(
                  button: true,
                  enabled: enabled,
                  child: GestureDetector(
                    onTap: enabled ? () => _step(start, delta) : null,
                    child: Container(
                      height: 44,
                      alignment: Alignment.center,
                      decoration: g.raised(radius: 22),
                      child: Text(
                        g3Signed(delta, unit: 'Min.'),
                        maxLines: 1,
                        style: g.t(
                          12,
                          16,
                          weight: FontWeight.w700,
                          color: enabled ? g.ink : g.muted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (delta < 0) const SizedBox(width: 6),
            ],
          ],
        ),
      ],
    );
  }

  Widget _timeCard(bool start) {
    final p = OB.of(context);
    final value = start ? draft!.onset : draft!.wake;
    final text = start ? startText : endText;
    final enabled = receipt == null && !busy;
    final weekday = DateFormat('E', 'de_DE').format(value).toUpperCase();
    return Expanded(
      child: OBCard(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            InkWell(
              onTap: enabled ? () => _date(start) : null,
              child: Text(
                '${start ? 'BEGINN' : 'ENDE'} · $weekday',
                style: p.label(size: 10),
                maxLines: 1,
              ),
            ),
            Semantics(
              label: start ? 'Beginn der Nacht' : 'Ende der Nacht',
              child: TextField(
                key: ValueKey(start ? 'sleep-onset' : 'sleep-wake'),
                controller: text,
                focusNode: start ? null : endFocus,
                enabled: enabled,
                keyboardType: TextInputType.datetime,
                textInputAction: start
                    ? TextInputAction.next
                    : TextInputAction.done,
                style: p.text(30, weight: FontWeight.w700),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (_) => _update(),
                onSubmitted: (_) {
                  _update();
                  if (start) {
                    endFocus.requestFocus();
                  } else {
                    FocusScope.of(context).unfocus();
                  }
                },
              ),
            ),
            Row(
              spacing: 6,
              children: [
                for (final delta in const [-5, 5])
                  Expanded(
                    child: TextButton(
                      onPressed: enabled ? () => _step(start, delta) : null,
                      style: TextButton.styleFrom(
                        backgroundColor: p.well,
                        foregroundColor: p.ink,
                        minimumSize: const Size.fromHeight(34),
                        padding: EdgeInsets.zero,
                      ),
                      child: Text(delta < 0 ? '− 5' : '+ 5'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultCard() {
    final p = OB.of(context);
    final night = widget.controller.day!.sleep;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.g3
              ? g3Duration(night.duration.value?.round())
              : obDuration(night.duration.value),
          style: widget.g3
              ? G3.of(context).t(34, 39, weight: FontWeight.w700)
              : p.text(34, weight: FontWeight.w800, display: true),
        ),
        const SizedBox(height: 4),
        Text('Schlaf', style: p.text(13, color: p.muted)),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(LucideIcons.checkCheck, size: 18, color: p.led),
            const SizedBox(width: 8),
            Text('Zeiten korrigiert', style: p.text(14, color: p.ink)),
          ],
        ),
        const SizedBox(height: 8),
        _statusRow(
          'Zeit im Bett',
          widget.g3
              ? g3Duration(night.bedMinutes?.round())
              : obDuration(night.bedMinutes),
          LucideIcons.bed,
          p.sleep,
        ),
        _statusRow(
          'Wach',
          widget.g3
              ? g3Duration(night.awakeMinutes?.round())
              : '${obNumber(night.awakeMinutes)} Min.',
          LucideIcons.sun,
          p.strainText,
        ),
        _statusRow(
          'Zeitfenster',
          '${widget.g3 ? g3Clock(receipt!.onset) : obTime(receipt!.onset)}–${widget.g3 ? g3Clock(receipt!.wake) : obTime(receipt!.wake)}',
          LucideIcons.clock3,
          p.action,
        ),
        const SizedBox(height: 8),
        Text(
          'Schlaf neu ausgewertet · ${widget.g3 ? g3Clock(receipt!.savedAt) : obTime(receipt!.savedAt)} gespeichert',
          style: p.text(12, color: p.muted),
        ),
      ],
    );
    return Semantics(
      liveRegion: true,
      child: widget.g3
          ? g3_chrome.OBPanel(child: content)
          : OBCard(child: content),
    );
  }

  Widget _statusRow(String label, String value, IconData icon, Color color) {
    final p = OB.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(label, style: p.text(14)),
                Text(value, style: p.text(14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionRow(
    String label,
    IconData icon,
    Color color,
    VoidCallback? onTap, {
    String? value,
  }) {
    final p = OB.of(context);
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(padding: EdgeInsets.zero),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(label, style: p.text(14)),
                if (value != null) Text(value, style: p.text(13)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(LucideIcons.chevronRight, size: 14, color: p.gap),
        ],
      ),
    );
  }
}

Future<bool> restoreAutomaticSleep(
  BuildContext context,
  OpenBandController controller,
  String day, {
  bool g3 = false,
}) async {
  final Future<bool?> confirmation = g3
      ? showModalBottomSheet<bool>(
          context: context,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          builder: (sheet) => g3_chrome.OBSheet(
            title: 'Automatische Zeiten wiederherstellen?',
            confirmLabel: 'Wiederherstellen',
            onCancel: () => Navigator.pop(sheet, false),
            onConfirm: () => Navigator.pop(sheet, true),
            child: const Text('Schlaf und Erholung werden neu berechnet.'),
          ),
        )
      : showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Automatische Zeiten wiederherstellen?'),
            content: const Text('Schlaf und Erholung werden neu berechnet.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Abbrechen'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Wiederherstellen'),
              ),
            ],
          ),
        );
  final yes = await confirmation;
  if (yes != true) return false;
  try {
    await controller.repository.restoreAutomatic(day);
    await controller.refresh();
    return true;
  } catch (_) {
    await controller.refresh();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Die Rücknahme konnte nicht abgeschlossen werden. Bitte erneut versuchen.',
          ),
        ),
      );
    }
    return false;
  }
}
