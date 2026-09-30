import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../data/day_label.dart';
import 'g3/g3_format.dart';
import 'g3/g3_theme.dart';
import 'g3/chrome.dart' as chrome;
import 'calendar.dart';
import 'controller.dart';
import 'domain.dart';
import 'theme.dart';

Future<void> chooseOpenBandDay(
  BuildContext context,
  OpenBandController controller,
) async {
  final selected = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.black.withValues(alpha: .38),
    backgroundColor: Colors.transparent,
    builder: (_) =>
        FractionallySizedBox(heightFactor: 1, child: _DayPicker(controller)),
  );
  if (selected != null) await controller.selectDay(selected);
}

class _DayPicker extends StatefulWidget {
  final OpenBandController controller;
  const _DayPicker(this.controller);
  @override
  State<_DayPicker> createState() => _DayPickerState();
}

class _DayPickerState extends State<_DayPicker> {
  final GlobalKey _selectedCellKey = GlobalKey();
  late DateTime selected = DateTime.parse(widget.controller.selectedDay);
  late DateTime month = DateTime(selected.year, selected.month);
  late Future<Set<String>> days = widget.controller.repository.sleepDays();
  late Future<OpenBandDay> preview = widget.controller.repository.readDay(
    dayLabelOf(selected),
  );

  @override
  void initState() {
    super.initState();
    _revealSelected();
  }

  void _revealSelected() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || MediaQuery.textScalerOf(context).scale(15) <= 22) return;
    final cell = _selectedCellKey.currentContext;
    if (cell != null) {
      Scrollable.ensureVisible(cell, alignment: .8);
    }
  });

  void _select(DateTime date) {
    setState(() {
      selected = date;
      month = DateTime(date.year, date.month);
      preview = widget.controller.repository.readDay(dayLabelOf(date));
    });
    _revealSelected();
  }

  void _info() => showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (c) => SafeArea(
      child: chrome.OBInfoSheet(
        title: 'Gespeicherte Nächte',
        paragraphs: const [
          'Ein gefüllter Punkt zeigt einen gespeicherten Schlafwert. Die Nacht gehört zum Tag des Aufwachens. Deine Auswahl gilt erst nach Bestätigung. Fehlende Werte bleiben offen.',
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final g = G3.of(context);
    final now = widget.controller.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedDay = dayLabelOf(selected);
    final largeText = MediaQuery.textScalerOf(context).scale(15) > 22;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: chrome.OBSheet(
          title: 'Datum wählen',
          child: Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Gespeicherte Nächte',
                        style: p.text(14, color: p.muted),
                      ),
                    ),
                    chrome.OBIconButton(
                      icon: LucideIcons.info,
                      label: 'Gespeicherte Schlafwerte',
                      onTap: _info,
                      small: true,
                    ),
                  ],
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(0, largeText ? 0 : 10, 0, 32),
                    children: [
                      chrome.OBPanel(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          largeText ? 8 : 14,
                          16,
                          largeText ? 8 : 16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FutureBuilder<OpenBandDay>(
                              future: preview,
                              builder: (c, selectedSnapshot) => FutureBuilder<Set<String>>(
                                future: days,
                                builder: (c, snapshot) => Column(
                                  children: [
                                    MediaQuery(
                                      data: MediaQuery.of(context).copyWith(
                                        textScaler: largeText
                                            ? const TextScaler.linear(1.5)
                                            : MediaQuery.textScalerOf(context),
                                      ),
                                      child: OBCalendar(
                                        month: month,
                                        selected: selected,
                                        now: now,
                                        allowFuture: false,
                                        showAvailability: true,
                                        instrumentHeader: true,
                                        selectedCellKey: _selectedCellKey,
                                        nights: {
                                          ...?snapshot.data,
                                          // The preview and calendar must agree even
                                          // when a stored day is absent from the
                                          // repository's bulk availability index.
                                          if (selectedSnapshot
                                                  .data
                                                  ?.sleep
                                                  .duration
                                                  .value !=
                                              null)
                                            selectedDay,
                                        },
                                        onSelect: _select,
                                        onPrevMonth: () => setState(
                                          () => month = DateTime(
                                            month.year,
                                            month.month - 1,
                                          ),
                                        ),
                                        onNextMonth: () => setState(
                                          () => month = DateTime(
                                            month.year,
                                            month.month + 1,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (snapshot.hasError)
                                      chrome.OBLink(
                                        'Datenpunkte erneut laden',
                                        onTap: () => setState(
                                          () => days = widget
                                              .controller
                                              .repository
                                              .sleepDays(),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 16,
                              runSpacing: 8,
                              children: [
                                _AvailabilityLegend(
                                  filled: true,
                                  label: 'Schlafwert vorhanden',
                                ),
                                _AvailabilityLegend(
                                  filled: false,
                                  label: 'kein Schlafwert',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      FutureBuilder<OpenBandDay>(
                        future: preview,
                        builder: (c, snapshot) {
                          final ready =
                              snapshot.connectionState == ConnectionState.done;
                          final night = ready ? snapshot.data?.sleep : null;
                          return Semantics(
                            liveRegion: true,
                            child: chrome.OBPanel(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              g3DayLong(selected),
                                              style: p.text(
                                                15,
                                                weight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              !ready
                                                  ? 'Wird geladen …'
                                                  : snapshot.hasError
                                                  ? 'Schlafwert konnte nicht geladen werden.'
                                                  : night?.duration.value ==
                                                        null
                                                  ? 'Kein gespeicherter Schlafwert'
                                                  : 'Schlaf · ${g3NightOf(selected)}',
                                              style: p.text(12, color: p.muted),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        night?.duration.value == null
                                            ? '—'
                                            : g3Duration(
                                                night!.duration.value!.round(),
                                              ),
                                        style: p.text(
                                          22,
                                          weight: FontWeight.w700,
                                          display: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (snapshot.hasError)
                                    chrome.OBLink(
                                      'Erneut laden',
                                      onTap: () => _select(selected),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                if (widget.controller.day?.synthetic == true)
                  Text(
                    'SYNTHETISCHE DATEN',
                    textAlign: TextAlign.center,
                    style: g.caps(color: g.muted, size: 11),
                  ),
                const SizedBox(height: 10),
                if (largeText) ...[
                  chrome.OBActionSecondary(
                    'Zu heute',
                    expand: true,
                    onPressed: () => Navigator.pop(context, dayLabelOf(today)),
                  ),
                  const SizedBox(height: 10),
                  chrome.OBActionPrimary(
                    'Ansehen',
                    expand: true,
                    onPressed: () => Navigator.pop(context, selectedDay),
                  ),
                ] else
                  Row(
                    children: [
                      Expanded(
                        child: chrome.OBActionSecondary(
                          'Zu heute',
                          expand: true,
                          onPressed: () =>
                              Navigator.pop(context, dayLabelOf(today)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: chrome.OBActionPrimary(
                          'Ansehen',
                          expand: true,
                          onPressed: () => Navigator.pop(context, selectedDay),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AvailabilityLegend extends StatelessWidget {
  final bool filled;
  final String label;

  const _AvailabilityLegend({required this.filled, required this.label});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? p.ink : Colors.transparent,
            border: filled ? null : Border.all(color: p.muted),
          ),
        ),
        const SizedBox(width: 7),
        Text(label, style: p.text(11, color: p.muted)),
      ],
    );
  }
}
