import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
  Color get sleepText => dark ? sleep : const Color(0xFF4F68AE);
  Color get recoveryText => dark ? recovery : const Color(0xFF2D7463);
  Color get strainText => dark ? strain : const Color(0xFF926018);
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(AlpRadius.card)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.action,
        foregroundColor: p.dark ? p.canvas : Colors.white,
        minimumSize: const Size(44, 44),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AlpRadius.row)),
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
  const OBPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.backLabel = 'Zurück',
    this.onBack,
    this.onInfo,
    this.onDate,
    this.infoLabel = 'Information',
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final heading = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: p.text(18, weight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: p.text(12, color: p.muted),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 12),
      child: Row(
        children: [
          IconButton(
            tooltip: backLabel,
            onPressed: onBack ?? () => Navigator.maybePop(context),
            icon: const Icon(LucideIcons.chevronLeft, size: 20),
          ),
          Expanded(
            child: onDate == null
                ? heading
                : TextButton(
                    onPressed: onDate,
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    child: heading,
                  ),
          ),
          if (onInfo == null)
            const SizedBox(width: 44)
          else
            IconButton(
              tooltip: infoLabel,
              onPressed: onInfo,
              icon: Icon(LucideIcons.info, size: 20, color: p.muted),
            ),
        ],
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

class OBAction extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool secondary;
  const OBAction(
    this.label, {
    super.key,
    this.onPressed,
    this.secondary = false,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: secondary
        ? FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: OB.of(context).card,
              foregroundColor: OB.of(context).action,
            ),
            onPressed: onPressed,
            child: Text(label, textAlign: TextAlign.center),
          )
        : FilledButton(
            onPressed: onPressed,
            child: Text(label, textAlign: TextAlign.center),
          ),
  );
}
