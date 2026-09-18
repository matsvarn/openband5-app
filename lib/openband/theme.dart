import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class OB {
  final bool dark;
  const OB(this.dark);
  factory OB.of(BuildContext context) =>
      OB(Theme.of(context).brightness == Brightness.dark);
  Color get canvas => Color(dark ? 0xFF101318 : 0xFFF5F6F9);
  Color get card => Color(dark ? 0xFF1C2027 : 0xFFFFFFFF);
  Color get ink => Color(dark ? 0xFFF0F2F6 : 0xFF243149);
  Color get muted => Color(dark ? 0xFFAFB8C8 : 0xFF58657A);
  Color get line => Color(dark ? 0xFF343B47 : 0xFFE6EAF0);
  Color get action => Color(dark ? 0xFF9DBDFA : 0xFF285CCB);
  Color get sleep => Color(dark ? 0xFFA8BFF0 : 0xFF617FCE);
  Color get recovery => Color(dark ? 0xFF89B6A5 : 0xFF388A77);
  Color get strain => Color(dark ? 0xFFE3B76C : 0xFFB77E26);
  Color get pulse => Color(dark ? 0xFFE597AE : 0xFFB54F72);
  Color get rem => Color(dark ? 0xFF839DCC : 0xFFACBDE9);
  Color get deep => Color(dark ? 0xFFC5AEDF : 0xFF7865AD);
  Color get sleepText => dark ? sleep : const Color(0xFF4F68AE);
  Color get recoveryText => dark ? recovery : const Color(0xFF2D7463);
  Color get strainText => dark ? strain : const Color(0xFF926018);
  TextStyle text(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color? color,
  }) => TextStyle(
    fontFamily: 'Inter',
    fontSize: size,
    height: size >= 24 ? 1.12 : 1.36,
    fontWeight: weight,
    color: color ?? ink,
    letterSpacing: size >= 24 ? -.8 : 0,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

ThemeData openBandTheme(Brightness brightness) {
  final p = OB(brightness == Brightness.dark);
  final base = ThemeData(
    brightness: brightness,
    useMaterial3: true,
    fontFamily: 'Inter',
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.action,
        foregroundColor: p.dark ? p.canvas : Colors.white,
        minimumSize: const Size(44, 44),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
      borderRadius: BorderRadius.circular(20),
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
              backgroundColor: OB.of(context).action.withValues(alpha: .06),
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
