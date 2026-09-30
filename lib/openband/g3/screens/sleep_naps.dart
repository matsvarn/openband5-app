import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../data/day_label.dart';
import '../../controller.dart';
import '../../domain.dart';
import '../../naps.dart';
import '../../tab_bar.dart' show kOBTabBarContentInset;
import '../chrome.dart' as chrome;
import '../g3_format.dart';
import '../g3_theme.dart';
import '../metrics.dart' show G3LabelRow, OBMissingValue;
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

  void _info() => chrome.showOBInfoSheet(
    context,
    title: 'Nickerchen',
    paragraphs: const [
      'Das Band schätzt Schlaf am Tag aus Puls und Bewegung. Kurzes Dösen kann fehlen. Eigene Einträge sind gekennzeichnet.',
    ],
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
        child: chrome.G3DetailPage(
          bottomInset: kOBTabBarContentInset,
          header: chrome.OBPageHeader.detail(
            title: 'NICKERCHEN',
            domain: G3Domain.sleep,
            subtitle: g3DayLong(DateTime.parse(selected)),
            backLabel: 'Schlaf',
            onBack: () => Navigator.of(context).pop(),
            onTrailing: _info,
          ),
          fullWidthSection: Column(
            children: [
              FutureBuilder<List<NapDay>>(
                future: _week,
                builder: (context, snapshot) {
                  Widget inset(Widget child) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: child,
                  );
                  if (snapshot.hasError) {
                    return inset(
                      chrome.OBErrorBlock(
                        title: 'Nickerchen nicht geladen',
                        reason: 'Bitte erneut versuchen.',
                        onRetry: _reload,
                      ),
                    );
                  }
                  final days = snapshot.data;
                  if (days == null) {
                    return inset(
                      const Center(child: CircularProgressIndicator.adaptive()),
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
                      inset(
                        chrome.OBPanel(
                          hero: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const G3LabelRow(
                                'NICKERCHEN',
                                domain: G3Domain.sleep,
                                glyph: LucideIcons.moon,
                                note: 'letzte 7 Tage',
                              ),
                              const SizedBox(height: 8),
                              if (total == 0 && sessions.isEmpty)
                                Row(
                                  children: [
                                    const OBMissingValue(
                                      size: 34,
                                      lineHeight: 39,
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Keine Nickerchen',
                                      style: g.t(
                                        17,
                                        22,
                                        weight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                )
                              else
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.end,
                                  spacing: 10,
                                  children: [
                                    total == null
                                        ? const OBMissingValue(
                                            size: 92,
                                            lineHeight: 98,
                                          )
                                        : Text(
                                            obSleepDuration(total),
                                            style: g.t(
                                              92,
                                              98,
                                              weight: FontWeight.w700,
                                            ),
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
                      ),
                      const SizedBox(height: 14),
                      inset(
                        chrome.OBActionPrimary(
                          'Nickerchen eintragen',
                          expand: true,
                          onPressed: () => _edit(),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        inset(OBInlineNotice(text: _error!)),
                      ],
                      if (days.first.job?.state == CorrectionState.pending ||
                          days.first.job?.state == CorrectionState.failed) ...[
                        const SizedBox(height: 12),
                        inset(
                          OBInlineNotice(
                            text: 'Gespeichert · Auswertung offen',
                            action:
                                days.first.job?.state == CorrectionState.failed
                                ? 'Erneut auswerten'
                                : null,
                            onAction: () => _retry(days.first),
                          ),
                        ),
                      ],
                      if (sessions.isEmpty && total == 0) ...[
                        const SizedBox(height: 14),
                        inset(
                          chrome.OBEmptyState(
                            title: 'Wie erkannt wird',
                            reason:
                                'Das Band erkennt Schlaf am Tag aus Puls und Bewegung. Kurzes Dösen kann fehlen, dann trag es ein.',
                            action: 'Methode',
                            onAction: _info,
                          ),
                        ),
                      ] else ...[
                        const chrome.OBSectionHeader(
                          'HEUTE',
                          domain: G3Domain.sleep,
                        ),
                        if (days.first.sessions.isEmpty)
                          inset(
                            chrome.OBListRow(
                              icon: LucideIcons.moon,
                              title: days.first.judged
                                  ? 'Noch keins'
                                  : 'Noch nicht beurteilbar',
                              subtitle: days.first.judged
                                  ? 'Noch keins erkannt'
                                  : 'Daten fehlen',
                              onTap: () => _edit(),
                            ),
                          )
                        else
                          for (final nap in days.first.sessions) ...[
                            inset(_row(days.first.day, nap)),
                            const SizedBox(height: 8),
                          ],
                        if (sessions.any((s) => s.day != selected)) ...[
                          const chrome.OBSectionHeader(
                            'LETZTE 7 TAGE',
                            domain: G3Domain.sleep,
                          ),
                          for (final item in sessions.where(
                            (s) => s.day != selected,
                          )) ...[
                            inset(_row(item.day, item.nap)),
                            const SizedBox(height: 8),
                          ],
                        ],
                      ],
                      for (final day in days)
                        for (final rejected in day.rejected)
                          inset(
                            chrome.OBLink(
                              '${obSleepClock(rejected.start)}–${obSleepClock(rejected.end)} wiederherstellen',
                              onTap: () => _restore(day.day, rejected),
                            ),
                          ),
                    ],
                  );
                },
              ),
              chrome.OBFooterStamp.dataThrough(
                storedAt: widget.controller.band.latestStoredAt,
                now: widget.controller.now(),
                synthetic: widget.controller.day?.synthetic == true,
              ),
            ],
          ),
          children: const [],
        ),
      ),
    );
  }

  Widget _row(String day, NapSession nap) {
    final label = g3DayShort(DateTime.parse(day));
    final time = '${obSleepClock(nap.start)}–${obSleepClock(nap.end)}';
    return chrome.OBListRow(
      icon: LucideIcons.moon,
      title: '$label · $time',
      subtitle: nap.source == NapSource.manual
          ? 'eingetragen'
          : 'auto-erkannt${nap.durationMin == null ? '' : ' · ${g3Duration(nap.durationMin)} gelegen'}',
      value: obSleepDuration(nap.durationMin),
      onTap: () => _edit(day: day, session: nap),
    );
  }
}
