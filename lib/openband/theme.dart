import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/day_label.dart';
import 'alp_tokens.dart';

class OB {
  final bool dark;
  const OB(this.dark);
  factory OB.of(BuildContext context) =>
      OB(Theme.of(context).brightness == Brightness.dark);
  Color _pick(Color light, Color darkColor) => dark ? darkColor : light;
  Color get canvas => _pick(AlpColor.page, AlpColor.darkCanvas);
  Color get card => _pick(AlpColor.canvas, AlpColor.darkCard);
  Color get well => _pick(AlpColor.well, AlpColor.darkWell);
  Color get inset => _pick(AlpColor.inset, AlpColor.darkInset);
  Color get led => _pick(AlpColor.led, AlpColor.darkLed);
  Color get better => _pick(AlpColor.better, AlpColor.darkBetter);
  Color get betterMark => _pick(AlpColor.betterMark, AlpColor.darkBetter);
  Color get worse => _pick(AlpColor.worse, AlpColor.darkWorse);
  Color get worseMark => _pick(AlpColor.worseMark, AlpColor.darkWorse);
  Color get signal => _pick(AlpColor.signal, AlpColor.darkSignal);

  /// Drop shadow only — for selected chips that sit on an inset track.
  List<BoxShadow> get raised => dark
      ? const [
          BoxShadow(
            color: Color(0x99000000),
            offset: Offset(0, 1),
            blurRadius: 2,
          ),
          BoxShadow(
            color: Color(0x66000000),
            offset: Offset(0, 3),
            blurRadius: 8,
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x24000000),
            offset: Offset(0, 1),
            blurRadius: 2,
          ),
          BoxShadow(
            color: Color(0x0F000000),
            offset: Offset(0, 3),
            blurRadius: 8,
          ),
        ];

  Decoration insetDecoration({double radius = AlpRadius.card, Color? color}) =>
      OBBezel(color: color ?? inset, radius: radius, inset: true, dark: dark);

  Decoration raisedDecoration({double radius = AlpRadius.card}) =>
      OBBezel(color: card, radius: radius, inset: false, dark: dark);
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
    fontFamily: family(display: display, weight: weight),
    fontFamilyFallback: _apple ? const <String>[] : const [AlpFont.sans],
    fontSize: size,
    height: display ? 1.08 : (size >= 24 ? 1.12 : 1.36),
    fontWeight: weight,
    color: color ?? ink,
    letterSpacing: display ? -.03 * size : (size >= 24 ? -.8 : 0),
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  static bool get _apple =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Paper's G2 face. Weight selects Regular / Medium / Bold on Apple.
  static String family({
    bool display = false,
    FontWeight weight = FontWeight.w400,
  }) => _apple ? 'Helvetica Neue' : (display ? AlpFont.display : AlpFont.sans);

  /// Spaced small caps label: "ERHOLUNG ›", "NACHT FÜR NACHT".
  TextStyle label({double size = 10, Color? color}) => text(
    size,
    weight: FontWeight.w500,
    color: color ?? muted,
  ).copyWith(letterSpacing: 0.14 * size, height: 1.3);
}

ThemeData openBandTheme(Brightness brightness) {
  final p = OB(brightness == Brightness.dark);
  final base = ThemeData(
    brightness: brightness,
    useMaterial3: true,
    fontFamily: OB.family(),
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
      backgroundColor: p.canvas,
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
        foregroundColor: p.dark ? p.canvas : p.card,
        minimumSize: const Size(44, 44),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        elevation: 0,
        shape: const StadiumBorder(),
        textStyle: p.text(15, weight: FontWeight.w700),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStatePropertyAll(p.card),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.ink : p.inset,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
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

  /// The parent screen's title, shown in the back pill like iOS does.
  final String? backText;
  final VoidCallback? onBack, onInfo, onDate;
  final bool showBack;
  final String infoLabel;
  final IconData infoIcon;

  /// Space under the header; Paper puts a day pill 4 pt below it.
  final double bottom;
  const OBPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.backLabel = 'Zurück',
    this.backText,
    this.onBack,
    this.showBack = true,
    this.onInfo,
    this.onDate,
    this.infoLabel = 'Information',
    this.infoIcon = LucideIcons.info,
    this.bottom = 12,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    // Paper G2: 36 pt raised keys (44 pt hit area) either side of a spaced
    // caps title.
    Widget key(String tooltip, VoidCallback onTap, Widget child) => OBKey(
      tooltip: tooltip,
      height: 36,
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: SizedBox.square(dimension: 36, child: Center(child: child)),
    );
    final headingStyle = p
        .text(12, weight: FontWeight.w500)
        .copyWith(height: 16 / 12, letterSpacing: .16 * 12);
    final heading = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title.toUpperCase(),
          semanticsLabel: title,
          textAlign: TextAlign.center,
          style: headingStyle,
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: p.text(11, color: p.muted).copyWith(height: 14 / 11),
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
    final backAction = onBack ?? () => Navigator.maybePop(context);
    final chevron = OBChevron(
      direction: AxisDirection.left,
      size: 18,
      color: p.ink,
    );
    final back = !showBack
        ? const SizedBox(width: 44, height: 44)
        : backText == null
        ? key(backLabel, backAction, chevron)
        : Semantics(
            button: true,
            label: backLabel,
            excludeSemantics: true,
            child: OBKey(
              tooltip: backLabel,
              height: 36,
              onTap: backAction,
              padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 4,
                children: [
                  chevron,
                  Text(
                    backText!,
                    maxLines: 1,
                    style: p
                        .text(14, weight: FontWeight.w700)
                        .copyWith(height: 18 / 14),
                  ),
                ],
              ),
            ),
          );
    final info = onInfo == null
        ? const SizedBox(width: 44, height: 44)
        : key(
            infoLabel,
            onInfo!,
            infoIcon == LucideIcons.info
                ? Text(
                    'i',
                    style: p
                        .text(15, weight: FontWeight.w700)
                        .copyWith(height: 18 / 15),
                  )
                : Icon(infoIcon, size: 18, color: p.ink),
          );
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const control = 44.0;
          const laneGap = 12.0;
          final centerLane = (constraints.maxWidth - control * 2 - laneGap * 2)
              .clamp(0.0, double.infinity);
          var longest = 0.0;
          for (final word in title.toUpperCase().split(RegExp(r'\s+'))) {
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
                  height: 52,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [back, info],
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(width: double.infinity, child: titled(heading)),
              ],
            );
          }
          return ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
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

String obDayTitle(String day, [DateTime? now]) => day == todayLabel(now)
    ? 'Heute'
    : DateFormat('EEE, d. MMM', 'de_DE').format(DateTime.parse(day));
String obTime(DateTime? time) =>
    time == null ? '—' : DateFormat('HH:mm', 'de_DE').format(time);

/// A raised panel, or with [inset] a pressed-in surface for refused and
/// missing values.
class OBCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool inset;
  const OBCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.inset = false,
  });
  const OBCard.inset({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  }) : inset = true;
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Container(
      decoration: inset ? p.insetDecoration() : p.raisedDecoration(),
      padding: padding,
      child: child,
    );
  }
}

/// Status LED: lit when [on], a dark socket otherwise.
class OBLed extends StatelessWidget {
  final bool on;
  final Color? color;
  final double size;
  const OBLed({super.key, required this.on, this.color, this.size = 8});
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final lit = color ?? p.led;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? lit : p.gap,
        boxShadow: on
            ? [BoxShadow(color: lit.withValues(alpha: .6), blurRadius: 6)]
            : null,
      ),
    );
  }
}

/// A raised round or pill key. Every tappable surface in the language.
/// Day stepper under a page header (Paper G2): previous, the day, next.
/// A null [onNext] greys the arrow out (today has no next day). The visual
/// pill is 40 pt; every target keeps a 44 pt hit area.
class OBDayPill extends StatelessWidget {
  final String label;
  final VoidCallback? onPrevious, onNext, onTap;
  const OBDayPill({
    super.key,
    required this.label,
    this.onPrevious,
    this.onNext,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    Widget arrow(AxisDirection direction, VoidCallback? onPressed, String tip) =>
        Semantics(
          button: true,
          enabled: onPressed != null,
          label: tip,
          excludeSemantics: true,
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 40,
              height: 44,
              child: Center(
                child: OBChevron(
                  direction: direction,
                  color: onPressed == null ? p.gap : p.ink,
                ),
              ),
            ),
          ),
        );
    return SizedBox(
      height: 44,
      child: Stack(
        children: [
          Positioned.fill(
            top: 2,
            bottom: 2,
            child: DecoratedBox(decoration: p.raisedDecoration(radius: 20)),
          ),
          Material(
            type: MaterialType.transparency,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                arrow(AxisDirection.left, onPrevious, 'Vorheriger Tag'),
                InkWell(
                  onTap: onTap,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: p
                            .text(13, weight: FontWeight.w700)
                            .copyWith(height: 16 / 13),
                      ),
                    ),
                  ),
                ),
                arrow(AxisDirection.right, onNext, 'Nächster Tag'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class OBKey extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final String? tooltip;
  final double height;
  final EdgeInsetsGeometry padding;
  final bool pressed;
  const OBKey({
    super.key,
    required this.child,
    this.onTap,
    this.tooltip,
    this.height = 44,
    this.padding = const EdgeInsets.symmetric(horizontal: 14),
    this.pressed = false,
  });
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final radius = BorderRadius.circular(height / 2);
    Widget key = Container(
      height: height,
      constraints: BoxConstraints(minWidth: height),
      decoration: pressed
          ? p.insetDecoration(radius: height / 2)
          : p.raisedDecoration(radius: height / 2),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: padding,
            child: Center(widthFactor: 1, child: child),
          ),
        ),
      ),
    );
    if (height < 44) {
      key = SizedBox(
        width: padding == EdgeInsets.zero ? 44 : null,
        height: 44,
        child: Center(child: key),
      );
    }
    if (tooltip != null) key = Tooltip(message: tooltip!, child: key);
    return key;
  }
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
    final enabled = onPressed != null;
    final background = !enabled ? p.inset : (secondary ? p.card : p.ink);
    final foreground = !enabled
        ? p.muted
        : secondary
        ? (destructive ? p.danger : p.ink)
        : (p.dark ? p.canvas : p.card);
    final labelStyle = p
        .text(15, weight: FontWeight.w700)
        .copyWith(height: 18 / 15, color: foreground);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: enabled ? p.raised : null,
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: background,
            foregroundColor: foreground,
            disabledBackgroundColor: background,
            disabledForegroundColor: foreground,
            minimumSize: Size(48, secondary ? 48 : 52),
            elevation: 0,
            shape: const StadiumBorder(),
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

/// Paper G2 bezel: raised Gehäuse or a pressed-in well.
class OBBezel extends Decoration {
  final Color color;
  final double radius;
  final bool inset;
  final bool dark;
  const OBBezel({
    required this.color,
    required this.radius,
    required this.inset,
    required this.dark,
  });

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _OBBezelPainter(this);

  @override
  bool hitTest(Size size, Offset position, {TextDirection? textDirection}) =>
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(radius),
      ).contains(position);
}

class _OBBezelPainter extends BoxPainter {
  final OBBezel d;
  _OBBezelPainter(this.d);

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration config) {
    final size = config.size;
    if (size == null || size.isEmpty) return;
    final rect = offset & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(d.radius));
    if (d.inset) {
      final lip = d.dark ? const Color(0x0DFFFFFF) : const Color(0xB3FFFFFF);
      canvas.drawRRect(rrect.shift(const Offset(0, 1)), Paint()..color = lip);
      canvas.drawRRect(rrect, Paint()..color = d.color);
      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.top, rect.width, 2),
        Paint()
          ..color = d.dark ? const Color(0x8C000000) : const Color(0x1F000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1),
      );
      canvas.restore();
      return;
    }
    final tight = d.dark ? const Color(0x99000000) : const Color(0x24000000);
    final soft = d.dark ? const Color(0x66000000) : const Color(0x0F000000);
    canvas.drawRRect(
      rrect.shift(const Offset(0, 3)),
      Paint()
        ..color = soft
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawRRect(
      rrect.shift(const Offset(0, 1)),
      Paint()
        ..color = tight
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1),
    );
    canvas.drawRRect(rrect, Paint()..color = d.color);
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawLine(
      Offset(rect.left + 1, rect.top + 0.5),
      Offset(rect.right - 1, rect.top + 0.5),
      Paint()
        ..color = d.dark ? const Color(0x0FFFFFFF) : const Color(0xE6FFFFFF)
        ..strokeWidth = 1,
    );
    canvas.restore();
  }
}

/// Paper G2 chevron: 2.5 stroke, round caps, the same path as the frames.
class OBChevron extends StatelessWidget {
  final AxisDirection direction;
  final double size;
  final Color? color;
  const OBChevron({
    super.key,
    this.direction = AxisDirection.right,
    this.size = 14,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return CustomPaint(
      size: Size.square(size),
      painter: _ChevronPainter(color ?? p.muted, direction),
    );
  }
}

class _ChevronPainter extends CustomPainter {
  final Color color;
  final AxisDirection direction;
  const _ChevronPainter(this.color, this.direction);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 * size.width / 24
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final s = size.width / 24;
    final path = Path();
    switch (direction) {
      case AxisDirection.down:
        path
          ..moveTo(6 * s, 9 * s)
          ..lineTo(12 * s, 15 * s)
          ..lineTo(18 * s, 9 * s);
      case AxisDirection.up:
        path
          ..moveTo(6 * s, 15 * s)
          ..lineTo(12 * s, 9 * s)
          ..lineTo(18 * s, 15 * s);
      case AxisDirection.left:
        path
          ..moveTo(15 * s, 6 * s)
          ..lineTo(9 * s, 12 * s)
          ..lineTo(15 * s, 18 * s);
      case AxisDirection.right:
        path
          ..moveTo(9 * s, 6 * s)
          ..lineTo(15 * s, 12 * s)
          ..lineTo(9 * s, 18 * s);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronPainter old) =>
      old.color != color || old.direction != direction;
}
