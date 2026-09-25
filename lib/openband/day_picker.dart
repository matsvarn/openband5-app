import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/day_label.dart';
import 'calendar.dart';
import 'controller.dart';
import 'domain.dart';
import 'theme.dart';

Future<void> chooseOpenBandDay(
  BuildContext context,
  OpenBandController controller,
) async {
  final selected = await Navigator.of(
    context,
  ).push<String>(MaterialPageRoute(builder: (_) => _DayPicker(controller)));
  if (selected != null) await controller.selectDay(selected);
}

class _DayPicker extends StatefulWidget {
  final OpenBandController controller;
  const _DayPicker(this.controller);
  @override
  State<_DayPicker> createState() => _DayPickerState();
}

class _DayPickerState extends State<_DayPicker> {
  late DateTime selected = DateTime.parse(widget.controller.selectedDay);
  late DateTime month = DateTime(selected.year, selected.month);
  late Future<Set<String>> days = widget.controller.repository.sleepDays();
  late Future<OpenBandDay> preview = widget.controller.repository.readDay(
    dayLabelOf(selected),
  );

  void _select(DateTime date) => setState(() {
    selected = date;
    month = DateTime(date.year, date.month);
    preview = widget.controller.repository.readDay(dayLabelOf(date));
  });

  void _info() => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Gespeicherte Nächte',
              style: OB.of(c).text(18, weight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Text(
              'Ein gefüllter Punkt zeigt einen gespeicherten Schlafwert. Die Nacht gehört zum Tag des Aufwachens. Deine Auswahl gilt erst nach Bestätigung. Fehlende Werte bleiben offen.',
            ),
            const SizedBox(height: 12),
            OBAction(
              'Schließen',
              secondary: true,
              onPressed: () => Navigator.pop(c),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final now = widget.controller.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedDay = dayLabelOf(selected);
    final previous = DateTime(selected.year, selected.month, selected.day - 1);
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OBPageHeader(
                title: 'Datum wählen',
                backText: 'Abbrechen',
                subtitle: 'Gespeicherte Nächte',
                backLabel: 'Abbrechen',
                onInfo: _info,
                infoLabel: 'Gespeicherte Schlafwerte',
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                children: [
                  OBCard(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FutureBuilder<Set<String>>(
                          future: days,
                          builder: (c, snapshot) => Column(
                            children: [
                              OBCalendar(
                                month: month,
                                selected: selected,
                                now: now,
                                allowFuture: false,
                                showAvailability: true,
                                instrumentHeader: true,
                                nights: snapshot.data ?? const {},
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
                              if (snapshot.hasError)
                                TextButton(
                                  onPressed: () => setState(
                                    () => days = widget.controller.repository
                                        .sleepDays(),
                                  ),
                                  child: const Text('Datenpunkte erneut laden'),
                                ),
                            ],
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
                        child: OBCard.inset(
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
                                          DateFormat(
                                            'EEEE, d. MMMM',
                                            'de_DE',
                                          ).format(selected),
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
                                              : night?.duration.value == null
                                              ? 'Kein gespeicherter Schlafwert'
                                              : 'Schlaf · Nacht ${DateFormat('E', 'de_DE').format(previous)} → ${DateFormat('E', 'de_DE').format(selected)}',
                                          style: p.text(12, color: p.muted),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    night?.duration.value == null
                                        ? '—'
                                        : obDuration(night!.duration.value),
                                    style: p.text(
                                      22,
                                      weight: FontWeight.w700,
                                      display: true,
                                    ),
                                  ),
                                ],
                              ),
                              if (snapshot.hasError)
                                TextButton(
                                  onPressed: () => _select(selected),
                                  child: const Text('Erneut laden'),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  if (widget.controller.day?.synthetic == true) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Synthetische Daten',
                      textAlign: TextAlign.center,
                      style: p.text(12, color: p.muted),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                10,
                16,
                MediaQuery.paddingOf(context).bottom,
              ),
              child: OBAction(
                selectedDay == dayLabelOf(today)
                    ? 'Zu heute'
                    : '${obDate(selectedDay)} ansehen',
                secondary: selectedDay == dayLabelOf(today),
                onPressed: () => Navigator.pop(context, selectedDay),
              ),
            ),
          ],
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
