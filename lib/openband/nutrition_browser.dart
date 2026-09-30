import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import 'alp_tokens.dart';
import 'domain.dart';
import 'settings_controls.dart';
import 'theme.dart';

const obMeals = [
  ('breakfast', 'Frühstück'),
  ('lunch', 'Mittag'),
  ('dinner', 'Abend'),
  ('snack', 'Zwischendurch'),
];

Future<MealDraftSaveResult> saveOpenBandMealDraftCas(
  OpenBandRepository repository, {
  required MealDraft? expected,
  required MealDraft draft,
}) => repository.compareAndSaveMealDraft(expected: expected, draft: draft);

MealDraftEntry mealDraftEntryFromFood(FoodEntry e, String id) => MealDraftEntry(
  id: id,
  label: e.label,
  quantity: e.quantity,
  unit: e.unit,
  kcal: e.kcal,
  proteinG: e.proteinG,
  carbsG: e.carbsG,
  fatG: e.fatG,
  fibreG: e.fibreG,
  sugarG: e.sugarG,
  satFatG: e.satFatG,
  sodiumMg: e.sodiumMg,
  ironMg: e.ironMg,
  calciumMg: e.calciumMg,
  foodKey: e.foodKey,
  source: e.source,
  sourceCode: e.sourceCode,
  confirmed: e.confirmed,
  note: e.note,
);

String newOpenBandDraftEntryId() => const Uuid().v4();

String nutritionWeekRangeLabel(List<String> days) {
  if (days.isEmpty) return '';
  final start = DateTime.parse(days.first);
  final end = DateTime.parse(days.last);
  final endText = obDate(days.last);
  if (start.year == end.year && start.month == end.month) {
    return '${start.day}.–$endText';
  }
  return '${obDate(days.first)} – $endText';
}

String nutritionWeekDayLabel(String day) {
  final dt = DateTime.parse(day);
  final weekday = DateFormat('E', 'de_DE').format(dt).replaceAll('.', '');
  return '$weekday ${dt.day}.';
}

String nutritionUnknownKcalLabel(int count) {
  if (count <= 0) return '';
  return count == 1 ? '1 Eintrag ohne kcal' : '$count Einträge ohne kcal';
}

Future<String?> showOpenBandMealPicker(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    isScrollControlled: true,
    builder: (context) => const OpenBandMealPickerSheet(),
  );
}

class OpenBandMealPickerSheet extends StatelessWidget {
  const OpenBandMealPickerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final media = MediaQuery.of(context);
    final safeBottom = media.viewPadding.bottom > media.padding.bottom
        ? media.viewPadding.bottom
        : media.padding.bottom;
    final bottom = safeBottom > 34 ? safeBottom : 34.0;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height),
      child: Material(
        color: p.card,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AlpRadius.card),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Mahlzeit wählen',
                        style: p
                            .text(18, weight: FontWeight.w600)
                            .copyWith(height: 24 / 18),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: IconButton(
                        tooltip: 'Schließen',
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 44,
                          height: 44,
                        ),
                        icon: Icon(LucideIcons.x, size: 20, color: p.ink),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (key, label) in obMeals)
                        OBSettingsChoiceRow(
                          label: label,
                          selected: false,
                          onTap: () => Navigator.pop(context, key),
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
  }
}

class OpenBandNutritionWeek extends StatelessWidget {
  final List<NutritionDay> days;
  final ValueChanged<String>? onOpenDay;
  const OpenBandNutritionWeek({super.key, required this.days, this.onOpenDay});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    var maxKcal = 0.0;
    for (final day in days) {
      final v = day.kcal.value;
      if (v != null && v.isFinite && v > maxKcal) maxKcal = v;
    }
    return OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Erfasste Energie',
                  style: p
                      .text(15, weight: FontWeight.w600)
                      .copyWith(height: 20 / 15),
                ),
              ),
              Text(
                'kcal',
                style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
              ),
            ],
          ),
          for (final day in days)
            _WeekEnergyRow(
              day: day,
              maxKcal: maxKcal,
              onTap: onOpenDay == null ? null : () => onOpenDay!(day.date),
            ),
        ],
      ),
    );
  }
}

class _WeekEnergyRow extends StatelessWidget {
  final NutritionDay day;
  final double maxKcal;
  final VoidCallback? onTap;
  const _WeekEnergyRow({required this.day, required this.maxKcal, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final kcal = day.kcal.value;
    final unknown = day.kcal.unknown;
    final empty = day.entries.isEmpty;
    final bar = kcal != null && kcal.isFinite && kcal > 0 && maxKcal > 0
        ? kcal / maxKcal
        : 0.0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('week-row-${day.date}'),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 50,
                child: Text(
                  nutritionWeekDayLabel(day.date),
                  style: p.text(14).copyWith(height: 20 / 14),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: empty
                    ? Text(
                        'Keine Einträge',
                        style: p
                            .text(13, color: p.muted)
                            .copyWith(height: 18 / 13),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 6,
                        children: [
                          if (bar > 0)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                height: 8,
                                width: double.infinity,
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: bar.clamp(0.0, 1.0),
                                  child: ColoredBox(
                                    key: ValueKey('week-bar-${day.date}'),
                                    color: p.ink,
                                  ),
                                ),
                              ),
                            ),
                          if (unknown > 0)
                            Text(
                              nutritionUnknownKcalLabel(unknown),
                              style: p
                                  .text(12, color: p.muted)
                                  .copyWith(height: 16 / 12),
                            ),
                        ],
                      ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 64,
                child: Text(
                  kcal == null ? '—' : obNumber(kcal),
                  textAlign: TextAlign.right,
                  style: p
                      .text(15, weight: FontWeight.w600)
                      .copyWith(height: 20 / 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OpenBandRecentFoods extends StatelessWidget {
  final List<FoodEntry> foods;
  final ValueChanged<FoodEntry>? onReuse;
  const OpenBandRecentFoods({super.key, required this.foods, this.onReuse});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 12),
            child: Text(
              'Zuletzt verwendet',
              style: p
                  .text(15, weight: FontWeight.w600)
                  .copyWith(height: 20 / 15),
            ),
          ),
          if (foods.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Keine Einträge',
                style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
              ),
            ),
          for (final e in foods)
            OpenBandFoodEnergyRow(
              id: e.id,
              label: e.label,
              kcal: e.kcal,
              onTap: onReuse == null ? null : () => onReuse!(e),
            ),
        ],
      ),
    );
  }
}

class OpenBandFoodEnergyRow extends StatelessWidget {
  final String id, label;
  final double? kcal;
  final VoidCallback? onTap;
  const OpenBandFoodEnergyRow({
    super.key,
    required this.id,
    required this.label,
    this.kcal,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final large = MediaQuery.textScalerOf(context).scale(15) > 20;
    final energy = kcal == null ? '—' : '${obNumber(kcal)} kcal';
    final labelStyle = p
        .text(14, weight: FontWeight.w500)
        .copyWith(height: 20 / 14);
    final energyStyle = p
        .text(
          14,
          weight: FontWeight.w700,
          display: true,
          color: kcal == null ? p.muted : p.ink,
        )
        .copyWith(height: 18 / 14);
    final Widget body;
    if (large) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          Text(label, style: labelStyle),
          Text(energy, style: energyStyle),
        ],
      );
    } else {
      body = Row(
        children: [
          Expanded(child: Text(label, style: labelStyle)),
          const SizedBox(width: 12),
          SizedBox(
            width: 64,
            child: Text(energy, textAlign: TextAlign.right, style: energyStyle),
          ),
        ],
      );
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('food-row-$id'),
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: large ? 96 : 48),
          alignment: large ? Alignment.topLeft : Alignment.centerLeft,
          padding: large
              ? const EdgeInsets.symmetric(vertical: 12)
              : EdgeInsets.zero,
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: p.line)),
          ),
          child: body,
        ),
      ),
    );
  }
}

class OpenBandNutritionFooter extends StatelessWidget {
  final VoidCallback? onSearch;
  final VoidCallback? onBarcode;
  final VoidCallback? onAdd;
  const OpenBandNutritionFooter({
    super.key,
    this.onSearch,
    this.onBarcode,
    this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final large = MediaQuery.textScalerOf(context).scale(15) > 20;
    final media = MediaQuery.of(context);
    final effectiveBottom = media.padding.bottom > media.viewPadding.bottom
        ? media.padding.bottom
        : media.viewPadding.bottom;
    final padBottom = effectiveBottom > 12 ? effectiveBottom : 12.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, padBottom),
      child: Material(
        color: p.card,
        elevation: 0,
        shadowColor: const Color(0x14131B2E),
        borderRadius: BorderRadius.circular(26),
        child: Container(
          constraints: BoxConstraints(minHeight: large ? 60 : 52),
          padding: const EdgeInsets.only(left: 16, right: 6),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(26),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14131B2E),
                offset: Offset(0, 4),
                blurRadius: 20,
              ),
            ],
          ),
          child: Row(
            spacing: 10,
            children: [
              Icon(LucideIcons.search, size: 18, color: p.muted),
              Expanded(
                child: InkWell(
                  key: const ValueKey('nutrition-search'),
                  onTap: onSearch,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        large ? 'Suchen' : 'Lebensmittel suchen',
                        style: p
                            .text(15, weight: FontWeight.w500, color: p.muted)
                            .copyWith(height: 20 / 15),
                      ),
                    ),
                  ),
                ),
              ),
              _FooterCircle(
                key: const ValueKey('nutrition-barcode'),
                tooltip: 'Barcode',
                background: p.well,
                icon: LucideIcons.scanLine,
                color: p.ink,
                onPressed: onBarcode,
              ),
              _FooterCircle(
                key: const ValueKey('nutrition-add'),
                tooltip: 'Hinzufügen',
                background: p.ink,
                icon: LucideIcons.plus,
                color: p.dark ? p.canvas : p.card,
                onPressed: onAdd,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FooterCircle extends StatelessWidget {
  final String tooltip;
  final Color background, color;
  final IconData icon;
  final VoidCallback? onPressed;
  const _FooterCircle({
    super.key,
    required this.tooltip,
    required this.background,
    required this.icon,
    required this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            child: Center(
              child: Material(
                color: background,
                shape: const CircleBorder(),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(icon, size: 18, color: color),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OpenBandNutritionError extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const OpenBandNutritionError({
    super.key,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: p.text(14, color: p.danger)),
          if (onRetry != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: p.ink,
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text('Erneut', style: p.text(13, weight: FontWeight.w600)),
            ),
          ],
        ],
      ),
    );
  }
}
