import 'package:flutter/material.dart';

import 'alp_tokens.dart';
import 'theme.dart';

ThemeData openBandTimePickerTheme(BuildContext context) {
  final p = OB.of(context);
  final base = Theme.of(context);
  final action = TextButton.styleFrom(foregroundColor: p.ink);
  final fieldRadius = BorderRadius.circular(8);
  Color selected(Set<WidgetState> states, Color active, Color idle) =>
      states.contains(WidgetState.selected) ? active : idle;
  return base.copyWith(
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AlpRadius.card),
      ),
    ),
    colorScheme: base.colorScheme.copyWith(
      primary: p.ink,
      onPrimary: p.card,
      primaryContainer: p.well,
      onPrimaryContainer: p.ink,
      secondary: p.ink,
      onSecondary: p.card,
      tertiary: p.ink,
      onTertiary: p.card,
      tertiaryContainer: p.well,
      onTertiaryContainer: p.ink,
      surface: p.card,
      onSurface: p.ink,
      onSurfaceVariant: p.muted,
      surfaceContainerHigh: p.card,
      surfaceContainerHighest: p.well,
      outline: p.line,
      error: p.danger,
      onError: p.card,
      surfaceTint: Colors.transparent,
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: p.card,
      hourMinuteColor: p.well,
      hourMinuteTextColor: p.ink,
      hourMinuteTextStyle: p.text(48, color: p.ink),
      hourMinuteShape: RoundedRectangleBorder(borderRadius: fieldRadius),
      dayPeriodColor: WidgetStateColor.resolveWith(
        (states) => selected(states, p.ink, p.well),
      ),
      dayPeriodTextColor: WidgetStateColor.resolveWith(
        (states) => selected(states, p.card, p.ink),
      ),
      dayPeriodBorderSide: BorderSide(color: p.line),
      helpTextStyle: p.text(AlpText.body, color: p.muted),
      cancelButtonStyle: action,
      confirmButtonStyle: action,
      timeSelectorSeparatorColor: WidgetStatePropertyAll(p.ink),
      timeSelectorSeparatorTextStyle: WidgetStatePropertyAll(
        p.text(48, color: p.ink),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AlpRadius.card),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: p.well,
        focusColor: p.well,
        contentPadding: EdgeInsets.zero,
        hintStyle: p.text(48, color: p.muted),
        enabledBorder: OutlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: const BorderSide(color: Colors.transparent),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: const BorderSide(color: Colors.transparent),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: BorderSide(color: p.danger, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: BorderSide(color: p.danger, width: 2),
        ),
        errorStyle: const TextStyle(fontSize: 0, height: 1),
      ),
    ),
  );
}

Future<TimeOfDay?> showOpenBandTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) {
  return showTimePicker(
    context: context,
    initialTime: initialTime,
    initialEntryMode: TimePickerEntryMode.inputOnly,
    builder: (context, child) => Theme(
      data: openBandTimePickerTheme(context),
      child: child!,
    ),
  );
}
