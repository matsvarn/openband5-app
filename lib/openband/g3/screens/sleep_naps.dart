import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../data/day_label.dart';
import '../../controller.dart';
import '../../domain.dart';
import '../../naps.dart';
import '../../tab_bar.dart' show kOBTabBarContentInset;
import '../chrome.dart' as chrome;
import '../g3_theme.dart';
import '../sleep_parts.dart';

class G3SleepNaps extends StatefulWidget {
  const G3SleepNaps({super.key, required this.controller});
  final OpenBandController controller;
  @override
  State<G3SleepNaps> createState() => _G3SleepNapsState();
}

class _G3SleepNapsState extends State<G3SleepNaps> {
  late Future<List<NapDay>> _week = _readWeek();
  String? _error;

  void _info() => showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Nickerchen'),
      content: const Text(
        'Das Band schätzt Schlaf am Tag aus Puls und Bewegung. Kurzes Dösen kann fehlen. Eigene Einträge sind gekennzeichnet.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(),
          child: const Text('Schließen'),
        ),
      ],
    ),
  );

  Future<List<NapDay>> _readWeek() {
    final end = DateTime.parse(widget.controller.selectedDay);
    return Future.wait([
      for (var i = 0; i < 7; i++)
        widget.controller.repository.readNaps(
          dayLabelOf(DateTime(end.year, end.month, end.day - i)),
        ),
    ]);
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_reload);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    final next = _readWeek();
    setState(() {
      _week = next;
    });
  }

  Future<void> _edit({String? day, NapSession? session}) async {
    if (day != null && day != widget.controller.selectedDay) {
      widget.controller.selectDay(day);
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black.withValues(alpha: .32),
      backgroundColor: Colors.transparent,
      builder: (_) => OpenBandNapEditor(
        controller: widget.controller,
        original: session,
        g3Sheet: true,
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _restore(String day, NapSession session) async {
    try {
      final revision = await widget.controller.repository.restoreNap(
        day: day,
        rejected: session,
      );
      await widget.controller.calculateNaps(day: day, revision: revision);
      if (mounted) _reload();
    } catch (_) {
      if (mounted) setState(() => _error = 'Wiederherstellen fehlgeschlagen.');
    }
  }

  Future<void> _retry(NapDay naps) async {
    final job = naps.job;
    if (job == null) return;
    await widget.controller.calculateNaps(
      day: naps.day,
      revision: job.revision,
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final selected = widget.controller.selectedDay;
    return Scaffold(
      backgroundColor: g.page,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, kOBTabBarContentInset),
          children: [
            chrome.OBPageHeader.detail(
              title: 'NICKERCHEN',
              subtitle: DateFormat(
                'EEEE, dd. MMMM',
                'de_DE',
              ).format(DateTime.parse(selected)),
              backLabel: 'Schlaf',
              onBack: () => Navigator.of(context).pop(),
              onTrailing: _info,
            ),
            const SizedBox(height: 18),
            FutureBuilder<List<NapDay>>(
              future: _week,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return chrome.OBErrorBlock(
                    title: 'Nickerchen nicht geladen',
                    reason: 'Bitte erneut versuchen.',
                    onRetry: _reload,
                  );
                }
                final days = snapshot.data;
                if (days == null) {
                  return const Center(
                    child: CircularProgressIndicator.adaptive(),
                  );
                }
                final sessions = [
                  for (final day in days)
                    for (final session in day.sessions)
                      (day: day.day, nap: session),
                ];
                final complete = days.every(
                  (d) => d.judged && d.totalMin != null,
                );
                final total = complete
                    ? days.fold<int>(0, (sum, d) => sum + d.totalMin!)
                    : null;
                final shown = sessions
                    .where((s) => s.nap.durationMin != null)
                    .length;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    chrome.OBPanel(
                      hero: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('NICKERCHEN', style: g.caps()),
                              const Spacer(),
                              Text(
                                'letzte 7 Tage',
                                style: g.t(12, 16, color: g.muted),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (total == 0 && sessions.isEmpty)
                            Row(
                              children: [
                                Container(
                                  width: 60,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: g.gap,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Keine Nickerchen',
                                  style: g.t(17, 22, weight: FontWeight.w700),
                                ),
                              ],
                            )
                          else
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.end,
                              spacing: 10,
                              children: [
                                Text(
                                  obSleepDuration(total),
                                  style: g.t(92, 98, weight: FontWeight.w700),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: SizedBox(
                                    width: 90,
                                    child: Text(
                                      complete
                                          ? 'Schlaf in $shown Nickerchen'
                                          : '7 Tage noch nicht vollständig',
                                      style: g.t(14, 19, color: g.ink2),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          if (total == 0 && sessions.isEmpty)
                            Text(
                              'In 7 Tagen keins erkannt oder eingetragen.',
                              style: g.t(14, 19, color: g.ink2),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    chrome.OBActionPrimary(
                      'Nickerchen eintragen',
                      expand: true,
                      onPressed: () => _edit(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      OBInlineNotice(text: _error!),
                    ],
                    if (days.first.job?.state == CorrectionState.pending ||
                        days.first.job?.state == CorrectionState.failed) ...[
                      const SizedBox(height: 12),
                      OBInlineNotice(
                        text: 'Gespeichert · Auswertung offen',
                        action: days.first.job?.state == CorrectionState.failed
                            ? 'Erneut auswerten'
                            : null,
                        onAction: () => _retry(days.first),
                      ),
                    ],
                    if (sessions.isEmpty && total == 0) ...[
                      const SizedBox(height: 14),
                      chrome.OBEmptyState(
                        title: 'Wie erkannt wird',
                        reason:
                            'Das Band erkennt Schlaf am Tag aus Puls und Bewegung. Kurzes Dösen kann fehlen, dann trag es ein.',
                        action: 'Methode',
                        onAction: _info,
                      ),
                    ] else ...[
                      const SizedBox(height: 18),
                      Text('HEUTE', style: g.caps(color: g.muted)),
                      const SizedBox(height: 8),
                      if (days.first.sessions.isEmpty)
                        chrome.OBListRow(
                          icon: LucideIcons.moon,
                          title: days.first.judged
                              ? 'Noch keins'
                              : 'Noch nicht beurteilbar',
                          subtitle: days.first.judged
                              ? 'Daten bis ${obSleepClock(widget.controller.band.latestStoredAt)}'
                              : 'Daten fehlen',
                          onTap: () => _edit(),
                        )
                      else
                        for (final nap in days.first.sessions) ...[
                          _row(days.first.day, nap),
                          const SizedBox(height: 8),
                        ],
                      if (sessions.any((s) => s.day != selected)) ...[
                        const SizedBox(height: 18),
                        Text('LETZTE 7 TAGE', style: g.caps(color: g.muted)),
                        const SizedBox(height: 8),
                        for (final item in sessions.where(
                          (s) => s.day != selected,
                        )) ...[
                          _row(item.day, item.nap),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ],
                    for (final day in days)
                      for (final rejected in day.rejected)
                        TextButton(
                          onPressed: () => _restore(day.day, rejected),
                          child: Text(
                            '${obSleepClock(rejected.start)}–${obSleepClock(rejected.end)} wiederherstellen',
                          ),
                        ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String day, NapSession nap) {
    final label = DateFormat(
      'EE dd.MM',
      'de_DE',
    ).format(DateTime.parse(day)).replaceFirst('.', '');
    final time = '${obSleepClock(nap.start)}–${obSleepClock(nap.end)}';
    return chrome.OBListRow(
      icon: LucideIcons.moon,
      title: '$label · $time',
      subtitle: nap.source == NapSource.manual
          ? 'eingetragen'
          : 'auto-erkannt${nap.durationMin == null ? '' : ' · ${nap.durationMin} Min. gelegen'}',
      value: obSleepDuration(nap.durationMin),
      onTap: () => _edit(day: day, session: nap),
    );
  }
}
