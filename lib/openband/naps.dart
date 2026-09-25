import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../compute/nap_edits.dart';
import '../data/day_label.dart';
import 'controller.dart';
import 'day_picker.dart';
import 'domain.dart';
import 'theme.dart';
import 'time.dart';

class OpenBandNaps extends StatefulWidget {
  final OpenBandController controller;
  const OpenBandNaps({super.key, required this.controller});
  @override
  State<OpenBandNaps> createState() => _OpenBandNapsState();
}

class _OpenBandNapsState extends State<OpenBandNaps> {
  NapDay? _naps;
  Object? _error;
  bool _loading = true;
  bool _restoring = false;
  bool _restoreFailed = false;
  int _read = 0;
  late String _shownDay = controller.selectedDay;

  OpenBandController get controller => widget.controller;
  String get day => controller.selectedDay;

  void _stepDay(int offset) {
    final selected = DateTime.parse(day);
    controller.selectDay(
      dayLabelOf(
        DateTime(selected.year, selected.month, selected.day + offset),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    controller.addListener(_onController);
    _load(retryPending: true);
  }

  @override
  void dispose() {
    controller.removeListener(_onController);
    super.dispose();
  }

  void _onController() {
    if (!mounted) return;
    if (controller.selectedDay != _shownDay) {
      setState(() {
        _shownDay = controller.selectedDay;
        _naps = null;
        _error = null;
        _loading = true;
        _restoreFailed = false;
      });
      _load(retryPending: true);
    } else {
      _load();
    }
  }

  Future<void> _load({bool retryPending = false}) async {
    final token = ++_read;
    final date = controller.selectedDay;
    try {
      final naps = await controller.repository.readNaps(date);
      if (!mounted || token != _read) return;
      setState(() {
        _naps = naps;
        _loading = false;
        _error = null;
        _shownDay = date;
      });
      if (retryPending &&
          naps.job?.state == CorrectionState.pending &&
          !controller.napCalculating) {
        await controller.calculateNaps(day: date, revision: naps.job!.revision);
      }
    } catch (e) {
      if (!mounted || token != _read) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _openEditor([NapSession? session]) async {
    final date = day;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            OpenBandNapEditor(controller: controller, original: session),
      ),
    );
    if (mounted && controller.selectedDay == date) await _load();
  }

  Future<void> _restore(NapSession rejected) async {
    if (_restoring) return;
    final originalDay = day;
    setState(() {
      _restoring = true;
      _restoreFailed = false;
    });
    try {
      final revision = await controller.repository.restoreNap(
        day: originalDay,
        rejected: rejected,
      );
      await controller.calculateNaps(day: originalDay, revision: revision);
      if (mounted && controller.selectedDay == originalDay) await _load();
    } catch (_) {
      if (mounted && controller.selectedDay == originalDay) {
        setState(() => _restoreFailed = true);
        await _load();
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Future<void> _retry() async {
    final job = _naps?.job;
    if (job == null) return;
    await controller.calculateNaps(day: day, revision: job.revision);
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final p = OB.of(context);
      final naps = _naps;
      final failed =
          naps?.job?.state == CorrectionState.failed ||
          controller.napCalculationErrors.containsKey(day);
      final pending =
          naps?.job?.state == CorrectionState.pending ||
          naps?.job?.state == CorrectionState.calculating ||
          controller.napCalculating;
      final open = failed || pending;
      final selected = DateTime.parse(day);
      final today = day == todayLabel(controller.now());
      final dateLabel =
          '${DateFormat('EEE', 'de_DE').format(selected).replaceAll('.', '')} '
          '${DateFormat('dd.MM', 'de_DE').format(selected)}';
      return Scaffold(
        backgroundColor: p.canvas,
        bottomNavigationBar: naps == null || _error != null
            ? null
            : SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: OBAction(
                    'Nickerchen ergänzen',
                    secondary: true,
                    ink: true,
                    icon: LucideIcons.plus,
                    onPressed: () => _openEditor(),
                  ),
                ),
              ),
        body: SafeArea(
          child: ListView(
            key: PageStorageKey('openband.naps.$day'),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              OBPageHeader(
                title: 'Nickerchen',
                backText: 'Schlaf',
                subtitle: '',
                bottom: 2,
                onInfo: () => _napInfo(context, naps),
                infoLabel: 'Quelle und Zeitzone',
              ),
              Center(
                child: OBDayPill(
                  label: dateLabel,
                  onTap: () => chooseOpenBandDay(context, controller),
                  onPrevious: () => _stepDay(-1),
                  onNext: today ? null : () => _stepDay(1),
                ),
              ),
              const SizedBox(height: 24),
              if (_error != null)
                OBAction('Daten erneut laden', onPressed: _load)
              else if (_loading && naps == null)
                const Center(child: CircularProgressIndicator.adaptive())
              else if (naps != null) ...[
                OBCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TAGSÜBER GESCHLAFEN', style: p.label(size: 11)),
                      const SizedBox(height: 8),
                      _total(p, naps),
                      if (!naps.judged) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Noch nicht bestimmbar',
                          style: p
                              .text(13, color: p.muted)
                              .copyWith(height: 16 / 13),
                        ),
                      ] else if (naps.sessions.isEmpty && !open) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Keine Nickerchen erkannt',
                          style: p
                              .text(13, color: p.muted)
                              .copyWith(height: 16 / 13),
                        ),
                      ],
                      if (naps.sessions.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _NapTimeline(day: day, sessions: naps.sessions),
                      ],
                      if (naps.recordingTimezone == null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Gerätezeit',
                          style: p
                              .text(13, color: p.muted)
                              .copyWith(height: 16 / 13),
                        ),
                      ],
                    ],
                  ),
                ),
                if (open) ...[
                  const SizedBox(height: 12),
                  OBCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Gespeichert · Auswertung offen',
                          style: p
                              .text(15, weight: FontWeight.w600)
                              .copyWith(height: 18 / 15),
                        ),
                        if (failed && !controller.napCalculating) ...[
                          const SizedBox(height: 12),
                          Material(
                            color: p.well,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              onTap: _retry,
                              borderRadius: BorderRadius.circular(14),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 44,
                                ),
                                child: Center(
                                  child: Text(
                                    'Erneut auswerten',
                                    style: p
                                        .text(14, weight: FontWeight.w600)
                                        .copyWith(height: 18 / 14),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (_restoreFailed) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Wiederherstellen fehlgeschlagen.',
                    style: p.text(13, color: p.danger),
                  ),
                ],
                if (naps.sessions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  OBCard(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final session in naps.sessions)
                          _NapRow(
                            session: session,
                            onTap: () => _openEditor(session),
                          ),
                      ],
                    ),
                  ),
                ],
                if (naps.sessions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'Erkannt stammt aus der Aufzeichnung. Manuell kennzeichnet eigene Einträge.',
                      style: p
                          .text(12, color: p.muted)
                          .copyWith(height: 18 / 12),
                    ),
                  ),
                ],
                if (naps.rejected.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  OBCard(
                    child: Column(
                      children: [
                        for (final rejected in naps.rejected)
                          _RemovedRow(
                            session: rejected,
                            busy: _restoring,
                            onRestore: () => _restore(rejected),
                          ),
                      ],
                    ),
                  ),
                ],
                if (controller.day?.synthetic == true)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                    child: Text(
                      'Synthetische Daten',
                      style: p
                          .text(12, color: p.muted)
                          .copyWith(height: 18 / 12),
                    ),
                  ),
              ],
            ],
          ),
        ),
      );
    },
  );

  Widget _total(OB p, NapDay naps) {
    final total = naps.totalMin;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          total == null ? '—' : '$total',
          style: p
              .text(48, weight: FontWeight.w700, display: true)
              .copyWith(height: 54 / 48),
        ),
        const SizedBox(width: 8),
        Text(
          'Min.',
          style: p.text(16, color: p.muted).copyWith(height: 20 / 16),
        ),
      ],
    );
  }
}

/// The waking day 06:00–22:00 as a ticked track with each stored nap drawn
/// at its real clock position.
class _NapTimeline extends StatelessWidget {
  final String day;
  final List<NapSession> sessions;
  const _NapTimeline({required this.day, required this.sessions});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final d = DateTime.parse(day);
    final from = DateTime(d.year, d.month, d.day, 6);
    final to = DateTime(d.year, d.month, d.day, 22);
    final caption = p.text(10, weight: FontWeight.w500, color: p.muted);
    return ExcludeSemantics(
      child: Column(
        children: [
          SizedBox(
            height: 34,
            width: double.infinity,
            child: CustomPaint(
              painter: _NapTimelinePainter(p, from, to, sessions),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('06:00', style: caption),
              Text('14:00', style: caption),
              Text('22:00', style: caption),
            ],
          ),
        ],
      ),
    );
  }
}

class _NapTimelinePainter extends CustomPainter {
  final OB p;
  final DateTime from, to;
  final List<NapSession> sessions;
  _NapTimelinePainter(this.p, this.from, this.to, this.sessions);

  @override
  void paint(Canvas canvas, Size size) {
    final span = to.difference(from).inSeconds.toDouble();
    double x(DateTime t) =>
        (t.difference(from).inSeconds / span).clamp(0.0, 1.0) * size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 8, size.width, 14),
        const Radius.circular(4),
      ),
      Paint()..color = p.line,
    );
    for (final s in sessions) {
      final x0 = x(s.start), x1 = x(s.end);
      if (x1 <= x0) continue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x0, 8, x1 < x0 + 3 ? x0 + 3 : x1, 22),
          const Radius.circular(2),
        ),
        Paint()..color = p.ink,
      );
    }
    final tick = Paint()..color = p.muted;
    for (var i = 0; i <= 4; i++) {
      final tx = (size.width - 1) * i / 4 + .5;
      final major = i % 2 == 0;
      tick.strokeWidth = major ? 1.4 : 1;
      canvas.drawLine(Offset(tx, 26), Offset(tx, major ? 34 : 30), tick);
    }
  }

  @override
  bool shouldRepaint(_NapTimelinePainter old) =>
      old.sessions != sessions || old.p.dark != p.dark;
}

class _NapRow extends StatelessWidget {
  final NapSession session;
  final VoidCallback onTap;
  const _NapRow({required this.session, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final time = '${obTime(session.start)}–${obTime(session.end)}';
    final duration = session.durationMin == null
        ? '—'
        : '${session.durationMin} Min.';
    final source = session.source == NapSource.manual ? 'Manuell' : 'Erkannt';
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final trailing = 72.0 * scale.clamp(1, 2.5);
            final stack =
                constraints.maxWidth < 36 + 12 + 140 * scale + trailing;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  key: ValueKey('nap-icon-${session.startTs}'),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: p.sleepTint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(LucideIcons.moon, size: 20, color: p.sleep),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        time,
                        style: p
                            .text(17, weight: FontWeight.w600)
                            .copyWith(height: 22 / 17),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        source,
                        style: p
                            .text(13, color: p.muted)
                            .copyWith(height: 18 / 13),
                      ),
                      if (stack) ...[
                        const SizedBox(height: 4),
                        Text(
                          duration,
                          key: ValueKey('nap-duration-${session.startTs}'),
                          style: p
                              .text(17, weight: FontWeight.w700, display: true)
                              .copyWith(height: 22 / 17),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!stack)
                  Text(
                    duration,
                    key: ValueKey('nap-duration-${session.startTs}'),
                    style: p
                        .text(17, weight: FontWeight.w700, display: true)
                        .copyWith(height: 22 / 17),
                  ),
                const SizedBox(width: 12),
                Icon(LucideIcons.chevronRight, size: 16, color: p.muted),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RemovedRow extends StatelessWidget {
  final NapSession session;
  final VoidCallback onRestore;
  final bool busy;
  const _RemovedRow({
    required this.session,
    required this.onRestore,
    this.busy = false,
  });
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${obTime(session.start)}–${obTime(session.end)}',
              style: p.text(14, color: p.muted),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: busy ? null : onRestore,
            child: const Text('Wiederherstellen'),
          ),
        ],
      ),
    );
  }
}

Future<void> _napInfo(
  BuildContext context,
  NapDay? naps,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (c) {
    final p = OB.of(c);
    final zone = naps?.recordingTimezone;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Nickerchen', style: p.text(18, weight: FontWeight.w600)),
            const SizedBox(height: 16),
            Text(
              'Erkannt stammt aus der Aufzeichnung. Manuell hast du ergänzt.',
              style: p.text(14),
            ),
            const SizedBox(height: 12),
            Text(
              zone == null
                  ? 'Zeiten in Gerätezeit. Die Aufzeichnungszone ist unbekannt.'
                  : 'Aufzeichnungszone: $zone.',
              style: p.text(14),
            ),
            if (naps?.judged == false) ...[
              const SizedBox(height: 12),
              Text(
                'Die Messung reicht nicht, um Nickerchen zu beurteilen. Ein Eintrag ändert das nicht.',
                style: p.text(14),
              ),
            ],
            const SizedBox(height: 16),
            OBAction('Schließen', onPressed: () => Navigator.pop(c)),
          ],
        ),
      ),
    );
  },
);

class OpenBandNapEditor extends StatefulWidget {
  final OpenBandController controller;
  final NapSession? original;
  const OpenBandNapEditor({super.key, required this.controller, this.original});
  @override
  State<OpenBandNapEditor> createState() => _OpenBandNapEditorState();
}

class _OpenBandNapEditorState extends State<OpenBandNapEditor> {
  late final String day = widget.controller.selectedDay;
  final startText = TextEditingController();
  final endText = TextEditingController();
  final endFocus = FocusNode();
  DateTime? start, end;
  String? zone;
  String? error;
  Object? primeError;
  bool busy = false, saveFailed = false, priming = true;

  bool get editing => widget.original != null;

  @override
  void initState() {
    super.initState();
    _prime();
  }

  Future<void> _prime() async {
    setState(() {
      priming = true;
      primeError = null;
    });
    try {
      final naps = await widget.controller.repository.readNaps(day);
      if (!mounted) return;
      zone = naps.recordingTimezone;
      final original = widget.original;
      final civil = DateTime.parse(day);
      start =
          original?.start ??
          parseRecordedTime(
            civil,
            '16:00',
            zone: zone,
            previous: original?.start,
          );
      end =
          original?.end ??
          parseRecordedTime(civil, '16:30', zone: zone, previous: start);
      if (start == null || end == null) {
        throw const FormatException('Uhrzeit prüfen. Zeitumstellung beachten.');
      }
      startText.text = obTime(start);
      endText.text = obTime(end);
      setState(() {
        priming = false;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        priming = false;
        primeError = e;
      });
    }
  }

  @override
  void dispose() {
    startText.dispose();
    endText.dispose();
    endFocus.dispose();
    super.dispose();
  }

  DateTime _dateOf(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  DateTime? _parse(DateTime date, String text, {DateTime? previous}) =>
      parseRecordedTime(date, text, zone: zone, previous: previous);

  bool _update() {
    if (start == null) return false;
    final parsedStart = _parse(
      _dateOf(start!),
      startText.text,
      previous: start,
    );
    var parsedEnd = parsedStart == null
        ? null
        : _parse(_dateOf(start!), endText.text, previous: parsedStart);
    String? issue;
    if (parsedStart == null || parsedEnd == null) {
      issue = 'Uhrzeit prüfen. Zeitumstellung beachten.';
    } else {
      if (!parsedEnd.isAfter(parsedStart)) {
        final next = DateTime(
          parsedStart.year,
          parsedStart.month,
          parsedStart.day + 1,
        );
        parsedEnd = _parse(next, endText.text, previous: parsedStart);
      }
      if (parsedEnd == null || !parsedEnd.isAfter(parsedStart)) {
        issue = 'Ende nach Beginn.';
      } else {
        final s = parsedStart.millisecondsSinceEpoch ~/ 1000;
        final e = parsedEnd.millisecondsSinceEpoch ~/ 1000;
        if (!manualNapWindowIsValid(s, e)) {
          issue = '5 Minuten bis 6 Stunden.';
        }
      }
    }
    if (issue != null) {
      setState(() => error = issue);
      return false;
    }
    setState(() {
      start = parsedStart;
      end = parsedEnd;
      error = null;
    });
    return true;
  }

  String get _durationLabel {
    if (start == null || end == null || !end!.isAfter(start!)) return '—';
    return '${end!.difference(start!).inMinutes} Minuten';
  }

  Future<void> _save() async {
    if (busy || !_update()) return;
    setState(() {
      busy = true;
      saveFailed = false;
    });
    try {
      final revision = editing
          ? await widget.controller.repository.editNap(
              day: day,
              original: widget.original!,
              start: start!,
              end: end!,
            )
          : await widget.controller.repository.addNap(
              day: day,
              start: start!,
              end: end!,
            );
      if (!mounted) return;
      setState(() => busy = false);
      Navigator.pop(context);
      await widget.controller.calculateNaps(day: day, revision: revision);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        saveFailed = true;
        error = e is ArgumentError
            ? e.message?.toString()
            : 'Speichern fehlgeschlagen.';
      });
    }
  }

  Future<void> _remove() async {
    final original = widget.original;
    if (original == null || busy) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          '${obTime(original.start)}–${obTime(original.end)} entfernen?',
        ),
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
    if (yes != true || !mounted) return;
    setState(() => busy = true);
    try {
      final revision = await widget.controller.repository.removeNap(
        day: day,
        session: original,
      );
      if (!mounted) return;
      Navigator.pop(context);
      await widget.controller.calculateNaps(day: day, revision: revision);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Konnte nicht entfernt werden.';
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
        child: priming
            ? const Center(child: CircularProgressIndicator.adaptive())
            : primeError != null
            ? Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OBPageHeader(
                      title: editing
                          ? 'Nickerchen bearbeiten'
                          : 'Nickerchen ergänzen',
                      backText: 'Nickerchen',
                      subtitle: obDate(day),
                    ),
                    Text(
                      'Laden fehlgeschlagen.',
                      style: p.text(14, color: p.danger),
                    ),
                    const SizedBox(height: 12),
                    OBAction('Erneut laden', onPressed: _prime),
                    const SizedBox(height: 12),
                    OBAction(
                      'Zurück',
                      secondary: true,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  OBPageHeader(
                    title: editing
                        ? 'Nickerchen bearbeiten'
                        : 'Nickerchen ergänzen',
                    backText: 'Nickerchen',
                    subtitle: obDate(day),
                    onInfo: () => _napInfo(
                      context,
                      NapDay(day: day, recordingTimezone: zone),
                    ),
                    infoLabel: 'Quelle und Zeitzone',
                  ),
                  OBCard(
                    padding: const EdgeInsets.all(20),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final scale = MediaQuery.textScalerOf(context).scale(1);
                        final stack = constraints.maxWidth < 220 * scale;
                        final startWell = OBTimeField.well(
                          label: 'Beginn',
                          dateText:
                              start != null &&
                                  end != null &&
                                  dayLabelOf(end!) != dayLabelOf(start!)
                              ? obDate(dayLabelOf(start!))
                              : null,
                          controller: startText,
                          fieldKey: const ValueKey('nap-start'),
                          value: obTime(start),
                          enabled: !busy,
                          semanticsLabel: 'Beginn',
                          onChanged: (_) => _update(),
                          onSubmitted: (_) {
                            _update();
                            endFocus.requestFocus();
                          },
                        );
                        final endWell = OBTimeField.well(
                          label: 'Ende',
                          dateText:
                              start != null &&
                                  end != null &&
                                  dayLabelOf(end!) != dayLabelOf(start!)
                              ? obDate(dayLabelOf(end!))
                              : null,
                          controller: endText,
                          focusNode: endFocus,
                          fieldKey: const ValueKey('nap-end'),
                          value: obTime(end),
                          enabled: !busy,
                          semanticsLabel: 'Ende',
                          textInputAction: TextInputAction.done,
                          onChanged: (_) => _update(),
                          onSubmitted: (_) => _update(),
                        );
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (stack) ...[
                              startWell,
                              const SizedBox(height: 12),
                              endWell,
                            ] else
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: startWell),
                                  const SizedBox(width: 12),
                                  Expanded(child: endWell),
                                ],
                              ),
                            const SizedBox(height: 16),
                            Text(
                              _durationLabel,
                              style: p
                                  .text(14, color: p.muted)
                                  .copyWith(height: 20 / 14),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!, style: p.text(13, color: p.danger)),
                  ],
                  const SizedBox(height: 12),
                  OBAction(
                    busy
                        ? 'Wird gespeichert …'
                        : saveFailed
                        ? 'Erneut speichern'
                        : editing
                        ? 'Änderungen speichern'
                        : 'Speichern',
                    ink: true,
                    onPressed: busy ? null : _save,
                  ),
                  if (editing) ...[
                    const SizedBox(height: 12),
                    OBAction(
                      'Nickerchen entfernen',
                      secondary: true,
                      destructive: true,
                      ink: true,
                      onPressed: busy ? null : _remove,
                    ),
                  ],
                  if (zone == null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                      child: Text(
                        'Gerätezeit',
                        style: p
                            .text(13, color: p.muted)
                            .copyWith(height: 19 / 13),
                      ),
                    ),
                  if (widget.controller.day?.synthetic == true)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                      child: Text(
                        'Synthetische Daten',
                        style: p
                            .text(12, color: p.muted)
                            .copyWith(height: 18 / 12),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
