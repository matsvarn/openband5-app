import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/day_label.dart';
import 'alp_tokens.dart';

class OB {
  final bool dark;
  const OB(this.dark);
  factory OB.of(BuildContext context) =>
      OB(Theme.of(context).brightness == Brightness.dark);
  Color _pick(Color light, Color darkColor) => dark ? darkColor : light;
  Color get canvas => _pick(AlpColor.well, AlpColor.darkCanvas);
  Color get card => _pick(AlpColor.canvas, AlpColor.darkCard);
  Color get well => _pick(AlpColor.well, AlpColor.darkWell);
  Color get ink => _pick(AlpColor.ink, AlpColor.darkInk);
  Color get muted => _pick(AlpColor.muted, AlpColor.darkMuted);
  Color get line => _pick(AlpColor.line, AlpColor.darkLine);
  Color get action => _pick(AlpColor.action, AlpColor.darkAction);
  Color get sleep => _pick(AlpColor.sleep, AlpColor.darkSleep);
  Color get sleepTint => _pick(AlpColor.sleepTint, AlpColor.darkSleepTint);
  Color get recovery => _pick(AlpColor.recovery, AlpColor.darkRecovery);
  Color get recoveryTint =>
      _pick(AlpColor.recoveryTint, AlpColor.darkRecoveryTint);
  Color get strain => _pick(AlpColor.strain, AlpColor.darkStrain);
  Color get strainTint => _pick(AlpColor.strainTint, AlpColor.darkStrainTint);
  Color get pulse => _pick(AlpColor.pulse, AlpColor.darkPulse);
  Color get pulseTint => _pick(AlpColor.pulseTint, AlpColor.darkPulseTint);
  Color get food => _pick(AlpColor.food, AlpColor.darkFood);
  Color get foodTint => _pick(AlpColor.foodTint, AlpColor.darkFoodTint);
  Color get gap => _pick(AlpColor.gap, AlpColor.darkGap);
  Color get warning => _pick(AlpColor.warning, AlpColor.darkWarning);
  Color get warningTint =>
      _pick(AlpColor.warningTint, AlpColor.darkWarningTint);
  Color get danger => _pick(AlpColor.danger, AlpColor.darkDanger);
  Color get dangerTint => _pick(AlpColor.dangerTint, AlpColor.darkDangerTint);
  Color get stageDeep => _pick(AlpColor.stageDeep, AlpColor.darkStageDeep);
  Color get stageLight => _pick(AlpColor.stageLight, AlpColor.darkStageLight);
  Color get stageRem => _pick(AlpColor.stageRem, AlpColor.darkStageRem);
  Color get wake => _pick(AlpColor.wake, AlpColor.darkWake);
  Color get sleepText => dark ? sleep : AlpColor.sleepText;
  Color get recoveryText => dark ? recovery : AlpColor.recoveryText;
  Color get strainText => dark ? strain : AlpColor.strainText;
  Color get pulseText => dark ? pulse : AlpColor.pulseText;
  Color get foodText => dark ? food : AlpColor.foodText;
  Color smallText(Color metric) => switch (metric) {
    _ when metric == sleep => sleepText,
    _ when metric == recovery => recoveryText,
    _ when metric == strain => strainText,
    _ when metric == pulse => pulseText,
    _ when metric == food => foodText,
    _ => metric,
  };
  TextStyle text(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color? color,
    bool display = false,
  }) => TextStyle(
    fontFamily: display ? AlpFont.display : AlpFont.sans,
    fontSize: size,
    height: display ? 1.08 : (size >= 24 ? 1.12 : 1.36),
    fontWeight: weight,
    color: color ?? ink,
    letterSpacing: display ? -.03 * size : (size >= 24 ? -.8 : 0),
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

ThemeData openBandTheme(Brightness brightness) {
  final p = OB(brightness == Brightness.dark);
  final base = ThemeData(
    brightness: brightness,
    useMaterial3: true,
    fontFamily: AlpFont.sans,
    colorScheme: ColorScheme.fromSeed(
      seedColor: p.action,
      brightness: brightness,
      surface: p.card,
    ),
  );
  return base.copyWith(
    scaffoldBackgroundColor: p.canvas,
    textTheme: base.textTheme.apply(bodyColor: p.ink, displayColor: p.ink),
    appBarTheme: AppBarTheme(
      backgroundColor: p.canvas,
      foregroundColor: p.ink,
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: p.text(18, weight: FontWeight.w600),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        foregroundColor: p.action,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AlpRadius.card),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.action,
        foregroundColor: p.dark ? p.canvas : Colors.white,
        minimumSize: const Size(44, 44),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AlpRadius.row),
        ),
        textStyle: p.text(15, weight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.action,
        minimumSize: const Size(44, 44),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: p.text(14, weight: FontWeight.w500),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.iOS: _AccessibleTransitions(
          CupertinoPageTransitionsBuilder(),
        ),
        TargetPlatform.macOS: _AccessibleTransitions(
          CupertinoPageTransitionsBuilder(),
        ),
        TargetPlatform.android: _AccessibleTransitions(
          FadeUpwardsPageTransitionsBuilder(),
        ),
      },
    ),
  );
}

class OBPageHeader extends StatelessWidget {
  final String title, subtitle;
  final String backLabel;
  final VoidCallback? onBack, onInfo, onDate;
  final String infoLabel;
  final IconData infoIcon;
  const OBPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.backLabel = 'Zurück',
    this.onBack,
    this.onInfo,
    this.onDate,
    this.infoLabel = 'Information',
    this.infoIcon = LucideIcons.info,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    Widget circle(IconData icon, String tooltip, VoidCallback onPressed) =>
        SizedBox(
          width: 44,
          height: 44,
          child: Material(
            color: p.card,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: IconButton(
              tooltip: tooltip,
              onPressed: onPressed,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              icon: Icon(icon, size: 20, color: p.ink),
            ),
          ),
        );
    final headingStyle = p
        .text(18, weight: FontWeight.w600)
        .copyWith(height: 24 / 18);
    final heading = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, textAlign: TextAlign.center, style: headingStyle),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: p.text(12, color: p.muted).copyWith(height: 16 / 12),
          ),
        ],
      ],
    );
    Widget titled(Widget child) => onDate == null
        ? child
        : TextButton(
            onPressed: onDate,
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            child: child,
          );
    final back = circle(
      LucideIcons.chevronLeft,
      backLabel,
      onBack ?? () => Navigator.maybePop(context),
    );
    final info = onInfo == null
        ? const SizedBox(width: 44, height: 44)
        : circle(infoIcon, infoLabel, onInfo!);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const control = 44.0;
          const laneGap = 12.0;
          final centerLane = (constraints.maxWidth - control * 2 - laneGap * 2)
              .clamp(0.0, double.infinity);
          var longest = 0.0;
          for (final word in title.split(RegExp(r'\s+'))) {
            if (word.isEmpty) continue;
            final painter = TextPainter(
              text: TextSpan(text: word, style: headingStyle),
              textDirection: direction,
              textScaler: scaler,
              maxLines: 1,
            )..layout();
            if (painter.width > longest) longest = painter.width;
            painter.dispose();
          }
          if (longest > centerLane) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 44,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [back, info],
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: titled(heading),
                ),
              ],
            );
          }
          return ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 50),
            child: Row(
              children: [
                back,
                const SizedBox(width: laneGap),
                Expanded(child: titled(heading)),
                const SizedBox(width: laneGap),
                info,
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AccessibleTransitions extends PageTransitionsBuilder {
  final PageTransitionsBuilder standard;
  const _AccessibleTransitions(this.standard);
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => MediaQuery.disableAnimationsOf(context)
      ? child
      : standard.buildTransitions(
          route,
          context,
          animation,
          secondaryAnimation,
          child,
        );
}

String obGapMinutes(num minutes) =>
    minutes < 1 ? '<1 Min.' : '${obNumber(minutes.ceil())} Min.';

String obDuration(num? minutes) {
  if (minutes == null) return '—';
  final m = minutes.round();
  return '${m ~/ 60}h${(m % 60).toString().padLeft(2, '0')}';
}

String obNumber(num? value, {int digits = 0}) => value == null
    ? '—'
    : NumberFormat.decimalPatternDigits(
        locale: 'de_DE',
        decimalDigits: digits,
      ).format(value);
String obDate(String day) =>
    DateFormat('d. MMMM', 'de_DE').format(DateTime.parse(day));
List<String> openBandDaysEnding(String endDay, int nights) {
  final end = DateTime.parse(endDay);
  return [
    for (var i = nights - 1; i >= 0; i--)
      dayLabelOf(DateTime(end.year, end.month, end.day - i)),
  ];
}

String obDayTitle(String day) => day == todayLabel()
    ? 'Heute'
    : DateFormat('EEE, d. MMM', 'de_DE').format(DateTime.parse(day));
String obTime(DateTime? time) =>
    time == null ? '—' : DateFormat('HH:mm', 'de_DE').format(time);

class OBCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const OBCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: OB.of(context).card,
      borderRadius: BorderRadius.circular(AlpRadius.card),
    ),
    padding: padding,
    child: child,
  );
}

/// Icon + title + body + optional fix line, on a white card — the onboarding
/// status card (import report, pairing advice).
class OBNoticeCard extends StatelessWidget {
  final String title, body;
  final String? fix;
  final IconData icon;
  const OBNoticeCard(
    this.title,
    this.body, {
    super.key,
    this.fix,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: p.action),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: p.text(15, weight: FontWeight.w600)),
              ),
            ],
          ),
          Text(body, style: p.text(14, color: p.muted)),
          if (fix != null)
            Text(
              fix!,
              style: p.text(13, weight: FontWeight.w600, color: p.action),
            ),
        ],
      ),
    );
  }
}

class OBAction extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool secondary;
  final bool destructive;
  final bool ink;
  final IconData? icon;
  const OBAction(
    this.label, {
    super.key,
    this.onPressed,
    this.secondary = false,
    this.destructive = false,
    this.ink = false,
    this.icon,
  });
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    if (!ink) {
      return SizedBox(
        width: double.infinity,
        child: secondary
            ? FilledButton.tonal(
                style: FilledButton.styleFrom(
                  backgroundColor: p.card,
                  foregroundColor: destructive ? p.danger : p.action,
                ),
                onPressed: onPressed,
                child: Text(label, textAlign: TextAlign.center),
              )
            : FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: p.action,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: p.action.withValues(alpha: 0.4),
                  disabledForegroundColor: Colors.white,
                ),
                onPressed: onPressed,
                child: Text(label, textAlign: TextAlign.center),
              ),
      );
    }
    final background = secondary ? p.card : p.ink;
    final foreground = secondary
        ? (destructive ? p.danger : p.ink)
        : (p.dark ? p.canvas : Colors.white);
    final labelStyle = p
        .text(15, weight: FontWeight.w600)
        .copyWith(height: 18 / 15, color: foreground);
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: background.withValues(alpha: 0.4),
          disabledForegroundColor: foreground,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: labelStyle,
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: labelStyle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Beginn/Ende time control. Wraps the clock onto its own line when the
/// scaled value no longer fits beside the label — a fixed-width row clips
/// "23:25" at 2× text.
class OBTimeField extends StatelessWidget {
  final String label;
  final String? dateText;
  final VoidCallback? onDate;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final Key? fieldKey;
  final String value;
  final bool enabled;
  final String? semanticsLabel;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction textInputAction;
  final bool well;
  const OBTimeField({
    super.key,
    required this.label,
    required this.value,
    this.dateText,
    this.onDate,
    this.controller,
    this.focusNode,
    this.fieldKey,
    this.enabled = true,
    this.semanticsLabel,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction = TextInputAction.next,
    this.well = false,
  });
  const OBTimeField.well({
    super.key,
    required this.label,
    required this.value,
    this.dateText,
    this.onDate,
    this.controller,
    this.focusNode,
    this.fieldKey,
    this.enabled = true,
    this.semanticsLabel,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction = TextInputAction.next,
  }) : well = true;

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    if (well) return _well(p);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final timeWidth = (110.0 * scale).clamp(110.0, 240.0);
    final style = p.text(24, weight: FontWeight.w700, display: true);
    final clock = enabled && controller != null
        ? Semantics(
            label: semanticsLabel,
            child: SizedBox(
              width: timeWidth,
              child: TextField(
                key: fieldKey,
                controller: controller,
                focusNode: focusNode,
                keyboardType: TextInputType.datetime,
                textInputAction: textInputAction,
                textAlign: TextAlign.end,
                style: style,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  hintText: 'HH:mm',
                  hintStyle: style.copyWith(color: p.muted),
                ),
                onChanged: onChanged,
                onSubmitted: onSubmitted,
              ),
            ),
          )
        : Text(value, style: style);
    final labelColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: p.text(13, weight: FontWeight.w600, color: p.muted),
        ),
        if (dateText != null) ...[
          const SizedBox(height: 4),
          if (enabled && onDate != null)
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 0),
                minimumSize: const Size(44, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                alignment: Alignment.centerLeft,
              ),
              onPressed: onDate,
              child: Text(dateText!, style: p.text(12, color: p.action)),
            )
          else
            Text(dateText!, style: p.text(12, color: p.muted)),
        ],
      ],
    );
    final trailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        clock,
        const SizedBox(width: 6),
        Icon(LucideIcons.chevronRight, size: 14, color: p.gap),
      ],
    );
    return OBCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fits = constraints.maxWidth >= timeWidth + 140;
          if (fits) {
            return Row(
              children: [
                Expanded(child: labelColumn),
                trailing,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              labelColumn,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: trailing),
            ],
          );
        },
      ),
    );
  }

  Widget _well(OB p) {
    final style = p
        .text(28, weight: FontWeight.w600, display: true)
        .copyWith(height: 34 / 28);
    final clock = enabled && controller != null
        ? Semantics(
            label: semanticsLabel,
            child: TextField(
              key: fieldKey,
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              keyboardType: TextInputType.datetime,
              textInputAction: textInputAction,
              style: style,
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: 'HH:mm',
                hintStyle: style.copyWith(color: p.muted),
              ),
              onChanged: onChanged,
              onSubmitted: onSubmitted,
            ),
          )
        : Text(value, style: style);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: p.text(13, color: p.muted).copyWith(height: 16 / 13),
        ),
        if (dateText != null) ...[
          const SizedBox(height: 4),
          if (enabled && onDate != null)
            TextButton(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                alignment: Alignment.centerLeft,
              ),
              onPressed: onDate,
              child: Text(dateText!, style: p.text(12, color: p.action)),
            )
          else
            Text(dateText!, style: p.text(12, color: p.muted)),
        ],
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: p.well,
            borderRadius: BorderRadius.circular(AlpRadius.well),
          ),
          padding: const EdgeInsets.all(14),
          child: clock,
        ),
      ],
    );
  }
}
