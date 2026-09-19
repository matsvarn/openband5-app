import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/day_label.dart';
import 'theme.dart';

const _weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

/// Canonical Paper 3HPT month grid. Sleep availability dots are optional;
/// goal dates omit them. Future days stay tappable only when [allowFuture].
class OBCalendar extends StatelessWidget {
  final DateTime month;
  final DateTime selected;
  final DateTime now;
  final bool allowFuture;
  final bool showAvailability;
  final Set<String> nights;
  final ValueChanged<DateTime> onSelect;
  final VoidCallback? onPrevMonth;
  final VoidCallback? onNextMonth;

  const OBCalendar({
    super.key,
    required this.month,
    required this.selected,
    required this.now,
    required this.onSelect,
    this.allowFuture = false,
    this.showAvailability = false,
    this.nights = const {},
    this.onPrevMonth,
    this.onNextMonth,
  });

  bool get _canGoNext {
    if (allowFuture) return true;
    final next = DateTime(month.year, month.month + 1);
    return !next.isAfter(DateTime(now.year, now.month));
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final cellH = (44.0 * scale).clamp(44.0, 88.0);
    final count = DateTime(month.year, month.month + 1, 0).day;
    final offset = (DateTime(month.year, month.month, 1).weekday - 1) % 7;
    final rows = (count + offset + 6) ~/ 7;
    final today = DateTime(now.year, now.month, now.day);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                tooltip: 'Vorheriger Monat',
                onPressed: onPrevMonth,
                padding: EdgeInsets.zero,
                icon: Icon(LucideIcons.chevronLeft, size: 18, color: p.ink),
              ),
            ),
            Expanded(
              child: Text(
                DateFormat('MMMM yyyy', 'de_DE').format(month),
                textAlign: TextAlign.center,
                style: p.text(17, weight: FontWeight.w600).copyWith(height: 20 / 17),
              ),
            ),
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                tooltip: 'Nächster Monat',
                onPressed: _canGoNext ? onNextMonth : null,
                padding: EdgeInsets.zero,
                icon: Icon(
                  LucideIcons.chevronRight,
                  size: 18,
                  color: _canGoNext ? p.ink : p.muted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final label in _weekdays)
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: p.text(11, color: p.muted).copyWith(height: 14 / 11),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (var row = 0; row < rows; row++) ...[
          if (row > 0) const SizedBox(height: 2),
          SizedBox(
            height: cellH,
            child: Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: _cell(
                      context,
                      p,
                      n: row * 7 + col - offset + 1,
                      count: count,
                      today: today,
                      cellH: cellH,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _cell(
    BuildContext context,
    OB p, {
    required int n,
    required int count,
    required DateTime today,
    required double cellH,
  }) {
    if (n < 1 || n > count) return const SizedBox.expand();
    final date = DateTime(month.year, month.month, n);
    final day = dayLabelOf(date);
    final chosen = day == dayLabelOf(selected);
    final isToday = day == dayLabelOf(today);
    final future = date.isAfter(today);
    final blocked = future && !allowFuture;
    final stored = nights.contains(day);
    final ink = blocked ? p.muted : (chosen ? p.card : p.ink);
    return Semantics(
      selected: chosen,
      button: true,
      enabled: !blocked,
      label:
          '${DateFormat('EEEE, d. MMMM yyyy', 'de_DE').format(date)}'
          '${showAvailability && stored ? ', Schlafwert vorhanden' : ''}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1.5),
        child: Material(
          color: chosen ? p.ink : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: !chosen && isToday
                ? BorderSide(color: p.ink, width: 1.5)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: blocked ? null : () => onSelect(date),
            child: ExcludeSemantics(
              child: SizedBox(
                height: cellH,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$n',
                      style: p
                          .text(
                            16,
                            weight: chosen ? FontWeight.w600 : FontWeight.w400,
                            color: ink,
                          )
                          .copyWith(height: 20 / 16),
                    ),
                    if (showAvailability)
                      SizedBox(
                        height: 8,
                        child: Center(
                          child: Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: stored ? p.sleep : Colors.transparent,
                              border: !stored && !future
                                  ? Border.all(color: p.muted, width: 0.5)
                                  : null,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
