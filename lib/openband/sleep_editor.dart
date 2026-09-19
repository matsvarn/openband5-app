import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';
import '../data/day_label.dart';
import 'controller.dart';
import 'charts.dart';
import 'domain.dart';
import 'theme.dart';
import 'time.dart';

class SleepEditor extends StatefulWidget {
  final OpenBandController controller;
  const SleepEditor({super.key, required this.controller});
  @override
  State<SleepEditor> createState() => _SleepEditorState();
}

class _SleepEditorState extends State<SleepEditor> {
  late final String day = widget.controller.selectedDay;
  late final SleepNight original =
      widget.controller.day?.sleep ?? const SleepNight();
  final startText = TextEditingController(), endText = TextEditingController();
  final endFocus = FocusNode();
  SleepDraft? draft;
  SleepCorrection? receipt;
  bool preview = false, busy = false, loading = true, changed = false;
  bool saveFailed = false;
  String? error, draftError;
  Future<void> _draftWrite = Future.value();
  int _draftVersion = 0;
  @override
  void initState() {
    super.initState();
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
        startText.text = obTime(draft!.onset);
        endText.text = obTime(draft!.wake);
        changed = stored != null;
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
      obTime(current),
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
    if (preview) {
      setState(() => preview = false);
      return;
    }
    if (!changed) {
      Navigator.pop(context);
      return;
    }
    await _draftWrite;
    if (!mounted) return;
    final action = await showDialog<String>(
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
          error = 'Speichern fehlgeschlagen. Dein Entwurf bleibt erhalten.';
        });
      }
    }
  }

  void _showDetails() {
    final edit = draft;
    if (edit == null) return;
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
          : saveFailed
          ? 'Nicht gespeichert'
          : preview
          ? 'Änderung prüfen'
          : 'Schlafzeiten ändern';
      return PopScope(
        canPop: !busy && !preview && draftError == null || receipt != null,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _leave();
        },
        child: Scaffold(
          backgroundColor: p.canvas,
          body: SafeArea(
            child: loading
                ? const Center(child: CircularProgressIndicator.adaptive())
                : draft == null
                ? Center(
                    child: OBAction('Entwurf erneut laden', onPressed: _load),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OBPageHeader(
                          title: title,
                          subtitle:
                              '${original.onset == null ? '' : '${original.onset!.day}./'}${obDate(day)}${widget.controller.day?.synthetic == true ? ' · Synthetische Daten' : ''}',
                          onBack: _leave,
                          onInfo: _showDetails,
                          infoLabel: 'Zeitfenster und Auswertung',
                        ),
                        if (completed) _resultCard() else _windowCard(),
                        const SizedBox(height: 12),
                        if (error != null) ...[
                          Semantics(
                            liveRegion: true,
                            child: OBCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        LucideIcons.circleX,
                                        size: 18,
                                        color: p.danger,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          saveFailed
                                              ? 'Änderung nicht gespeichert'
                                              : 'Zeitfenster prüfen',
                                          style: p.text(
                                            14,
                                            weight: FontWeight.w500,
                                            color: p.danger,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    error!,
                                    style: p.text(13, color: p.muted),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (draftError != null && receipt == null) ...[
                          Semantics(
                            liveRegion: true,
                            child: OBCard(
                              child: Column(
                                children: [
                                  Text(draftError!, style: p.text(13)),
                                  TextButton(
                                    onPressed: _persistDraft,
                                    child: const Text('Entwurf erneut sichern'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (receipt == null) ...[
                          if (preview) ...[
                            OBAction(
                              busy
                                  ? 'Wird gespeichert …'
                                  : saveFailed
                                  ? 'Erneut speichern'
                                  : 'Schlafzeiten speichern',
                              onPressed: busy ? null : _save,
                            ),
                            const SizedBox(height: 12),
                            OBAction(
                              'Weiter bearbeiten',
                              secondary: true,
                              onPressed: busy
                                  ? null
                                  : () => setState(() {
                                      preview = false;
                                      saveFailed = false;
                                      error = null;
                                    }),
                            ),
                            const SizedBox(height: 12),
                            OBCard(
                              child: _actionRow(
                                'Änderung verwerfen',
                                LucideIcons.trash2,
                                p.danger,
                                busy ? null : _discard,
                              ),
                            ),
                          ] else ...[
                            OBCard(
                              child: _actionRow(
                                'Zeitzone',
                                LucideIcons.clock3,
                                p.action,
                                _showDetails,
                                value: draft!.recordingTimezone == null
                                    ? 'Nicht gespeichert'
                                    : '${draft!.recordingTimezone!.split('/').last} · ${draft!.onset.timeZoneName}',
                              ),
                            ),
                            const SizedBox(height: 12),
                            OBAction(
                              'Änderung ansehen',
                              onPressed: () {
                                if (_update()) {
                                  FocusScope.of(context).unfocus();
                                  setState(() => preview = true);
                                } else {
                                  endFocus.requestFocus();
                                }
                              },
                            ),
                            const SizedBox(height: 12),
                            OBAction(
                              'Abbrechen',
                              secondary: true,
                              onPressed: _leave,
                            ),
                          ],
                        ] else ...[
                          if (!completed) ...[
                            Semantics(
                              liveRegion: true,
                              child: OBCard(
                                child: Column(
                                  children: [
                                    _statusRow(
                                      'Zeiten gespeichert',
                                      '${obTime(receipt!.onset)}–${obTime(receipt!.wake)}',
                                      LucideIcons.circleCheck,
                                      p.recoveryText,
                                    ),
                                    _statusRow(
                                      'Schlaf & Erholung',
                                      failed
                                          ? 'Unterbrochen'
                                          : 'Wird berechnet',
                                      failed
                                          ? LucideIcons.pause
                                          : LucideIcons.refreshCw,
                                      failed ? p.strainText : p.action,
                                    ),
                                    _statusRow(
                                      'Vorheriger Schlaf',
                                      obDuration(original.duration.value),
                                      LucideIcons.clock3,
                                      p.muted,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${obTime(receipt!.savedAt)} auf dem iPhone gespeichert',
                                      style: p.text(12, color: p.muted),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (failed ||
                              !completed && !widget.controller.calculating) ...[
                            OBAction(
                              'Auswertung erneut starten',
                              onPressed: () => widget.controller.calculate(
                                actual ?? receipt!,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ] else ...[
                            OBAction(
                              'Nacht ansehen',
                              onPressed: () => Navigator.pop(context),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (completed) ...[
                            OBAction(
                              'Zeiten erneut ändern',
                              secondary: true,
                              onPressed: () =>
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute<void>(
                                      builder: (_) => SleepEditor(
                                        controller: widget.controller,
                                      ),
                                    ),
                                  ),
                            ),
                            const SizedBox(height: 12),
                            OBCard(
                              child: _actionRow(
                                'Automatische Zeiten wiederherstellen',
                                LucideIcons.refreshCw,
                                p.action,
                              () async {
                                final restored = await restoreAutomaticSleep(
                                  context,
                                  widget.controller,
                                  day,
                                );
                                if (restored && context.mounted) {
                                  Navigator.pop(context);
                                }
                              },
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          OBAction(
                            'Zur Übersicht',
                            secondary: true,
                            onPressed: () => Navigator.of(
                              context,
                            ).popUntil((route) => route.isFirst),
                          ),
                        ],
                      ],
                    ),
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
    final delta = original.bedMinutes == null
        ? null
        : draft!.timeInBed.inMinutes - original.bedMinutes!;
    return OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      obDuration(draft!.timeInBed.inMinutes),
                      style: p.text(
                        34,
                        weight: FontWeight.w800,
                        display: true,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'im Bett',
                      style: p.text(
                        13,
                        weight: FontWeight.w600,
                        color: p.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (delta != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: p.sleep.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    '${delta < 0
                        ? '−'
                        : delta > 0
                        ? '+'
                        : ''}${obNumber(delta.abs())} Min.',
                    style: p.text(13, color: p.sleepText),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _timeField(true),
          const SizedBox(height: 10),
          _timeField(false),
          if (original.segments.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: p.well,
                borderRadius: BorderRadius.circular(16),
              ),
              child: NightChart(
                night: original,
                labels: false,
                showGapCaption: false,
                selectedOnset: draft!.onset,
                selectedWake: draft!.wake,
              ),
            ),
          ],
          if (receipt == null && !saveFailed) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text('Bisher', style: p.text(12, color: p.muted)),
                  Text(
                    '${obTime(original.onset)}–${obTime(original.wake)} · ${obDuration(original.bedMinutes)}',
                    style: p.text(13),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _resultCard() {
    final p = OB.of(context);
    final night = widget.controller.day!.sleep;
    return Semantics(
      liveRegion: true,
      child: OBCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              obDuration(night.duration.value),
              style: p.text(34, weight: FontWeight.w800, display: true),
            ),
            const SizedBox(height: 4),
            Text('Schlaf', style: p.text(13, color: p.muted)),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(LucideIcons.checkCheck, size: 18, color: p.recoveryText),
                const SizedBox(width: 8),
                Text(
                  'Zeiten korrigiert',
                  style: p.text(14, color: p.recoveryText),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _statusRow(
              'Zeit im Bett',
              obDuration(night.bedMinutes),
              LucideIcons.bed,
              p.sleep,
            ),
            _statusRow(
              'Wach',
              '${obNumber(night.awakeMinutes)} Min.',
              LucideIcons.sun,
              p.strainText,
            ),
            _statusRow(
              'Zeitfenster',
              '${obTime(receipt!.onset)}–${obTime(receipt!.wake)}',
              LucideIcons.clock3,
              p.action,
            ),
            const SizedBox(height: 8),
            Text(
              'Schlaf neu ausgewertet · ${obTime(receipt!.savedAt)} gespeichert',
              style: p.text(12, color: p.muted),
            ),
          ],
        ),
      ),
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

  Widget _timeField(bool start) {
    final p = OB.of(context);
    final value = start ? draft!.onset : draft!.wake;
    final enabled = receipt == null && !preview && !busy;
    return OBCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  start ? 'Eingeschlafen' : 'Aufgewacht',
                  style: p.text(
                    13,
                    weight: FontWeight.w600,
                    color: p.muted,
                  ),
                ),
                const SizedBox(height: 4),
                if (enabled)
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      alignment: Alignment.centerLeft,
                    ),
                    onPressed: () => _date(start),
                    child: Text(
                      obDate(dayLabelOf(value)),
                      style: p.text(12, color: p.action),
                    ),
                  )
                else
                  Text(
                    obDate(dayLabelOf(value)),
                    style: p.text(12, color: p.muted),
                  ),
              ],
            ),
          ),
          if (enabled)
            Semantics(
              label: start ? 'Beginn der Nacht' : 'Ende der Nacht',
              child: SizedBox(
                width: 110,
                child: TextField(
                  key: ValueKey(start ? 'sleep-onset' : 'sleep-wake'),
                  controller: start ? startText : endText,
                  focusNode: start ? null : endFocus,
                  keyboardType: TextInputType.datetime,
                  textInputAction: start
                      ? TextInputAction.next
                      : TextInputAction.done,
                  textAlign: TextAlign.end,
                  style: p.text(
                    24,
                    weight: FontWeight.w700,
                    display: true,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                    hintText: 'HH:mm',
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
            )
          else
            Text(
              obTime(value),
              style: p.text(24, weight: FontWeight.w700, display: true),
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
  String day,
) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Korrektur zurücknehmen?'),
      content: const Text(
        'Die automatische Erkennung wird wieder verwendet. Deine Originaldaten bleiben erhalten; Schlaf und Erholung werden neu berechnet.',
      ),
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
