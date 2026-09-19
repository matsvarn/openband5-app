import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:intl/intl.dart';
import '../data/day_label.dart';
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
    final count = DateTime(month.year, month.month + 1, 0).day;
    final offset = (month.weekday - 1) % 7;
    final large = MediaQuery.textScalerOf(context).scale(14) > 20;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            OBPageHeader(
              title: 'Datum wählen',
              subtitle: widget.controller.day?.synthetic == true
                  ? 'Synthetische Daten'
                  : 'Gespeicherte Nächte',
              backLabel: 'Abbrechen',
              onInfo: _info,
              infoLabel: 'Gespeicherte Schlafwerte',
            ),
            OBCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Vorheriger Monat',
                        onPressed: () => setState(
                          () => month = DateTime(month.year, month.month - 1),
                        ),
                        icon: const Icon(LucideIcons.chevronLeft, size: 18),
                      ),
                      Expanded(
                        child: TextButton(
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              locale: const Locale('de'),
                              initialDate: selected,
                              firstDate: DateTime(2000),
                              lastDate: now,
                            );
                            if (date != null && mounted) _select(date);
                          },
                          child: Text(
                            DateFormat('MMMM yyyy', 'de_DE').format(month),
                            textAlign: TextAlign.center,
                            style: p.text(15, weight: FontWeight.w600),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Nächster Monat',
                        onPressed:
                            !DateTime(month.year, month.month + 1).isBefore(now)
                            ? null
                            : () => setState(
                                () => month = DateTime(
                                  month.year,
                                  month.month + 1,
                                ),
                              ),
                        icon: const Icon(LucideIcons.chevronRight, size: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
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
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (final label in ['M', 'D', 'M', 'D', 'F', 'S', 'S'])
                        Expanded(
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: p.text(12, color: p.muted),
                          ),
                        ),
                    ],
                  ),
                  FutureBuilder<Set<String>>(
                    future: days,
                    builder: (c, snapshot) => Column(
                      children: [
                        for (
                          var row = 0;
                          row < (count + offset + 6) ~/ 7;
                          row++
                        )
                          Row(
                            children: [
                              for (var col = 0; col < 7; col++)
                                Expanded(
                                  child: Builder(
                                    builder: (c) {
                                      final n = row * 7 + col - offset + 1;
                                      if (n < 1 || n > count) {
                                        return SizedBox(
                                          height: large ? 64 : 50,
                                        );
                                      }
                                      final date = DateTime(
                                        month.year,
                                        month.month,
                                        n,
                                      );
                                      final day = dayLabelOf(date);
                                      final chosen =
                                          day == dayLabelOf(selected);
                                      final future = date.isAfter(now);
                                      final stored =
                                          snapshot.data?.contains(day) == true;
                                      return Semantics(
                                        selected: chosen,
                                        label:
                                            '${DateFormat('EEEE, d. MMMM yyyy', 'de_DE').format(date)}${stored ? ', Schlafwert vorhanden' : ''}',
                                        child: TextButton(
                                          onPressed: future
                                              ? null
                                              : () => _select(date),
                                          style: TextButton.styleFrom(
                                            padding: EdgeInsets.zero,
                                            minimumSize: Size(
                                              44,
                                              large ? 64 : 50,
                                            ),
                                            backgroundColor: chosen
                                                ? p.action.withValues(
                                                    alpha: .09,
                                                  )
                                                : null,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                          child: ExcludeSemantics(
                                            child: Column(
                                              children: [
                                                Text(
                                                  '$n',
                                                  style: p.text(
                                                    14,
                                                    weight: chosen
                                                        ? FontWeight.w600
                                                        : FontWeight.w400,
                                                    color: future
                                                        ? p.muted
                                                        : p.ink,
                                                  ),
                                                ),
                                                SizedBox(
                                                  height: 8,
                                                  child: Center(
                                                    child: Container(
                                                      width: 4,
                                                      height: 4,
                                                      decoration: BoxDecoration(
                                                        shape: BoxShape.circle,
                                                        color: stored
                                                            ? p.sleep
                                                            : Colors
                                                                  .transparent,
                                                        border:
                                                            !stored &&
                                                                !future &&
                                                                snapshot.hasData
                                                            ? Border.all(
                                                                color: p.muted,
                                                                width: .5,
                                                              )
                                                            : null,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                            ],
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
