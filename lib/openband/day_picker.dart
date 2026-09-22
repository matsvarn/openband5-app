import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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
              'Ein gefüllter Punkt zeigt einen gespeicherten Schlafwert. Die Nacht gehört zum Tag des Aufwachens. Deine Auswahl gilt erst nach „Tag ansehen“. Fehlende Werte bleiben offen.',
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
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            OBPageHeader(
              title: 'Datum wählen',
              backText: 'Abbrechen',
              subtitle: widget.controller.day?.synthetic == true
                  ? 'Synthetische Daten'
                  : 'Gespeicherte Nächte',
              backLabel: 'Abbrechen',
              onInfo: _info,
              infoLabel: 'Gespeicherte Schlafwerte',
            ),
            OBCard(
              padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.moon, size: 16, color: p.sleep),
                      const SizedBox(width: 8),
                      Text(
                        'Schlaf',
                        style: p.text(13, weight: FontWeight.w500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
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
                          nights: snapshot.data ?? const {},
                          onSelect: _select,
                          onPrevMonth: () => setState(
                            () => month = DateTime(month.year, month.month - 1),
                          ),
                          onNextMonth: () => setState(
                            () => month = DateTime(month.year, month.month + 1),
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
                  const SizedBox(height: 8),
                  Text(
                    'Gefüllter Punkt: Schlafwert vorhanden.',
                    style: p.text(12, color: p.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FutureBuilder<OpenBandDay>(
              future: preview,
              builder: (c, snapshot) {
                final ready = snapshot.connectionState == ConnectionState.done;
                final night = ready ? snapshot.data?.sleep : null;
                return Semantics(
                  liveRegion: true,
                  child: OBCard(
                    child: Row(
                      children: [
                        Icon(LucideIcons.moon, color: p.sleep, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Nacht zum ${obDate(dayLabelOf(selected))}',
                                style: p.text(14, weight: FontWeight.w500),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                !ready
                                    ? 'Wird geladen …'
                                    : snapshot.hasError
                                    ? 'Schlafwert konnte nicht geladen werden.'
                                    : night?.duration.value == null
                                    ? 'Kein gespeicherter Schlafwert'
                                    : 'Schlafdauer · ${obDuration(night!.duration.value)}',
                                style: p.text(12, color: p.muted),
                              ),
                              if (snapshot.hasError)
                                TextButton(
                                  onPressed: () => _select(selected),
                                  child: const Text('Erneut laden'),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            OBAction(
              '${obDate(dayLabelOf(selected))} ansehen',
              onPressed: () => Navigator.pop(context, dayLabelOf(selected)),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => _select(DateTime(now.year, now.month, now.day)),
              child: const Text('Zu heute'),
            ),
          ],
        ),
      ),
    );
  }
}
