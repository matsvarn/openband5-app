import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/l10n/app_localizations.dart';
import 'package:openstrap_edge/notify/notification_prefs.dart';
import 'package:openstrap_edge/openband/alp_tokens.dart';
import 'package:openstrap_edge/openband/notification_settings.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/openband/time_picker.dart';
import 'package:openstrap_edge/state/alarm_schedule.dart';
import 'package:openstrap_edge/ui2/profile/alarm.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    for (final (family, path) in [
      ('Inter', 'assets/fonts/Inter/Inter.ttf'),
      ('Inter Tight', 'assets/fonts/InterTight/InterTight[wght].ttf'),
    ]) {
      final loader = FontLoader(family)
        ..addFont(
          Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
        );
      await loader.load();
    }
  });

  const materialPurple = Color(0xFF6750A4);

  Future<ValueNotifier<TimeOfDay?>> openPicker(
    WidgetTester tester, {
    TimeOfDay initial = const TimeOfDay(hour: 22, minute: 0),
    Brightness brightness = Brightness.light,
    double scale = 1,
    double width = 393,
    double height = 852,
    Locale locale = const Locale('de'),
    bool always24 = true,
    double keyboard = 0,
  }) async {
    final picked = ValueNotifier<TimeOfDay?>(
      const TimeOfDay(hour: 99, minute: 99),
    );
    addTearDown(picked.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        debugShowCheckedModeBanner: false,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: openBandTheme(brightness).copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            alwaysUse24HourFormat: always24,
            viewInsets: EdgeInsets.only(bottom: keyboard),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked.value = await showOpenBandTimePicker(
                  context: context,
                  initialTime: initial,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return picked;
  }

  Rect largest(WidgetTester tester, Finder finder) {
    var best = Rect.zero;
    for (final element in finder.evaluate()) {
      final rect = tester.getRect(find.byWidget(element.widget));
      if (rect.width * rect.height > best.width * best.height) {
        best = rect;
      }
    }
    return best;
  }

  TimePickerThemeData pickerTheme(WidgetTester tester) =>
      TimePickerTheme.of(tester.element(find.byType(TimePickerDialog)));

  Color resolve(Color? color, Set<WidgetState> states) =>
      WidgetStateProperty.resolveAs<Color>(color!, states);

  Color periodFill(WidgetTester tester, String label) {
    return tester
        .widget<Material>(
          find.ancestor(of: find.text(label), matching: find.byType(Material)).first,
        )
        .color!;
  }

  testWidgets('inputOnly uses Alpin card/well/ink and never Material purple', (
    tester,
  ) async {
    await openPicker(tester);
    final theme = pickerTheme(tester);
    final scheme = Theme.of(tester.element(find.byType(TimePickerDialog)));
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.byIcon(Icons.keyboard_outlined), findsNothing);
    expect(find.byIcon(Icons.access_time), findsNothing);
    expect(find.text('Uhrzeit eingeben'), findsOneWidget);
    expect(theme.backgroundColor, AlpColor.canvas);
    expect(theme.hourMinuteColor, AlpColor.well);
    expect(theme.hourMinuteTextColor, AlpColor.ink);
    expect(theme.helpTextStyle?.color, AlpColor.muted);
    expect(theme.helpTextStyle?.fontFamily, AlpFont.sans);
    expect(theme.helpTextStyle?.fontSize, 14);
    expect(theme.hourMinuteTextStyle?.fontSize, 48);
    expect(scheme.colorScheme.surfaceTint, Colors.transparent);
    expect(scheme.dialogTheme.surfaceTintColor, Colors.transparent);
    expect(scheme.colorScheme.primary, isNot(materialPurple));
    expect(scheme.colorScheme.tertiary, isNot(materialPurple));
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
  });

  testWidgets('dark fields stay well with ink text', (tester) async {
    await openPicker(tester, brightness: Brightness.dark);
    final theme = pickerTheme(tester);
    expect(theme.backgroundColor, AlpColor.darkCard);
    expect(theme.hourMinuteColor, AlpColor.darkWell);
    expect(theme.hourMinuteTextColor, AlpColor.darkInk);
    expect(theme.helpTextStyle?.color, AlpColor.darkMuted);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
  });

  testWidgets('typed confirm writes the time and cancel keeps the old value', (
    tester,
  ) async {
    final picked = await openPicker(tester);
    expect(find.text('22'), findsWidgets);
    expect(find.text('00'), findsWidgets);
    await tester.enterText(find.byType(TextFormField).first, '21');
    await tester.enterText(find.byType(TextFormField).last, '30');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(picked.value, const TimeOfDay(hour: 21, minute: 30));

    final cancelled = await openPicker(tester);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(cancelled.value, isNull);
    expect(find.byType(TimePickerDialog), findsNothing);
  });

  testWidgets('invalid input stays open and shows the stock error', (
    tester,
  ) async {
    final picked = await openPicker(tester);
    await tester.enterText(find.byType(TextFormField).first, '88');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    expect(find.text('Geben Sie eine gültige Uhrzeit ein'), findsOneWidget);
    expect(picked.value, const TimeOfDay(hour: 99, minute: 99));
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(picked.value, isNull);
  });

  testWidgets('locale and 24h request stay with the platform', (tester) async {
    await openPicker(tester);
    expect(find.text('22'), findsWidgets);
    expect(find.text('AM'), findsNothing);
    expect(find.text('PM'), findsNothing);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();

    await openPicker(tester, locale: const Locale('en'), always24: false);
    expect(find.text('10'), findsWidgets);
    expect(find.text('PM'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('en 12h PM 22 toggles to AM 10 with distinct period colors', (
    tester,
  ) async {
    final picked = await openPicker(
      tester,
      locale: const Locale('en'),
      always24: false,
    );
    final theme = pickerTheme(tester);
    expect(resolve(theme.dayPeriodColor, {WidgetState.selected}), AlpColor.ink);
    expect(resolve(theme.dayPeriodColor, const {}), AlpColor.well);
    expect(
      resolve(theme.dayPeriodTextColor, {WidgetState.selected}),
      AlpColor.canvas,
    );
    expect(resolve(theme.dayPeriodTextColor, const {}), AlpColor.ink);
    expect(periodFill(tester, 'PM'), AlpColor.ink);
    expect(periodFill(tester, 'AM'), AlpColor.well);
    expect(periodFill(tester, 'PM'), isNot(periodFill(tester, 'AM')));
    await tester.tap(find.text('AM'));
    await tester.pumpAndSettle();
    expect(periodFill(tester, 'AM'), AlpColor.ink);
    expect(periodFill(tester, 'PM'), AlpColor.well);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(picked.value, const TimeOfDay(hour: 10, minute: 0));
  });

  testWidgets('en 12h dark selected period uses card on ink', (tester) async {
    await openPicker(
      tester,
      locale: const Locale('en'),
      always24: false,
      brightness: Brightness.dark,
    );
    final theme = pickerTheme(tester);
    expect(
      resolve(theme.dayPeriodColor, {WidgetState.selected}),
      AlpColor.darkInk,
    );
    expect(resolve(theme.dayPeriodColor, const {}), AlpColor.darkWell);
    expect(
      resolve(theme.dayPeriodTextColor, {WidgetState.selected}),
      AlpColor.darkCard,
    );
    expect(resolve(theme.dayPeriodTextColor, const {}), AlpColor.darkInk);
    expect(periodFill(tester, 'PM'), AlpColor.darkInk);
    expect(periodFill(tester, 'AM'), AlpColor.darkWell);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('375 2x with keyboard keeps fields and actions reachable', (
    tester,
  ) async {
    final previous = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() {
      WidgetController.hitTestWarningShouldBeFatal = previous;
    });
    final picked = await openPicker(
      tester,
      width: 375,
      height: 812,
      scale: 2,
      keyboard: 336,
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(TextFormField), findsNWidgets(2));
    await tester.enterText(find.byType(TextFormField).first, '07');
    await tester.enterText(find.byType(TextFormField).last, '05');
    final cancel = find.text('Abbrechen');
    await tester.ensureVisible(cancel);
    await tester.pumpAndSettle();
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(picked.value, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification and alarm open inputOnly with restored time', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        debugShowCheckedModeBanner: false,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: openBandTheme(Brightness.light),
        home: NotificationSettingsView(
          prefs: const NotificationPrefs(quietStartMin: 22 * 60),
          loaded: true,
          granted: true,
          onChanged: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('quiet-start')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey('quiet-start')));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.byIcon(Icons.keyboard_outlined), findsNothing);
    expect(find.text('22'), findsWidgets);
    expect(pickerTheme(tester).hourMinuteColor, AlpColor.well);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();

    final schedule = fillDefaultAlarmSchedule(const [
      AlarmScheduleEntry(weekday: 2, hour: 6, minute: 30, enabled: true),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        debugShowCheckedModeBanner: false,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: openBandTheme(Brightness.light),
        home: Scaffold(
          body: AlarmScreenView(
            armedAt: DateTime(2026, 9, 19, 7),
            now: DateTime(2026, 9, 18, 9, 41),
            state: AlarmArmState.storedSeconds,
            connected: true,
            schedule: schedule,
            onSetDayTime: (_, _, _) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp(r'Uhrzeit Mittwoch')));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('06'), findsWidgets);
    expect(find.text('30'), findsWidgets);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
  });

  testWidgets('Paper time-picker goldens', (tester) async {
    Future<void> capture(
      String name, {
      Brightness brightness = Brightness.light,
      double scale = 1,
      Future<void> Function()? before,
    }) async {
      await openPicker(tester, brightness: brightness, scale: scale);
      await before?.call();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('openband_goldens/$name.png'),
      );
      await tester.tap(find.text('Abbrechen').first);
      await tester.pumpAndSettle();
    }

    await capture('time-picker-light');
    await capture('time-picker-dark', brightness: Brightness.dark);
    await capture(
      'time-picker-invalid',
      before: () async {
        await tester.enterText(find.byType(TextFormField).first, '88');
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
      },
    );
    await capture('time-picker-large', scale: 2);
  });

  testWidgets('en 12h time-picker goldens', (tester) async {
    Future<void> capture(String name, Brightness brightness) async {
      await openPicker(
        tester,
        locale: const Locale('en'),
        always24: false,
        brightness: brightness,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('openband_goldens/$name.png'),
      );
      await tester.tap(find.text('Cancel').first);
      await tester.pumpAndSettle();
    }

    await capture('time-picker-en-12h-light', Brightness.light);
    await capture('time-picker-en-12h-dark', Brightness.dark);
  });

  testWidgets('stock inputOnly geometry at 393x852 1x', (tester) async {
    await openPicker(tester);
    final card = largest(
      tester,
      find.descendant(
        of: find.byType(TimePickerDialog),
        matching: find.byType(Material),
      ),
    );
    final help = tester.getRect(find.text('Uhrzeit eingeben'));
    final hour = tester.getRect(find.byType(TextFormField).first);
    final minute = tester.getRect(find.byType(TextFormField).last);
    final cancel = tester.getRect(find.text('Abbrechen'));
    final ok = tester.getRect(find.text('OK'));
    final theme = pickerTheme(tester);
    final shape = theme.shape! as RoundedRectangleBorder;
    debugPrint(
      'time-picker inputOnly 393x852@1x '
      'card=${card.size}@${card.topLeft} '
      'help=${help.size}@${help.topLeft} '
      'hour=${hour.size}@${hour.topLeft} '
      'minute=${minute.size}@${minute.topLeft} '
      'cancel=${cancel.size}@${cancel.topLeft} '
      'ok=${ok.size}@${ok.topLeft} '
      'shape=${shape.borderRadius} '
      'bg=${theme.backgroundColor} '
      'well=${theme.hourMinuteColor} '
      'ink=${theme.hourMinuteTextColor} '
      'helpColor=${theme.helpTextStyle?.color} '
      'helpSize=${theme.helpTextStyle?.fontSize} '
      'fieldSize=${theme.hourMinuteTextStyle?.fontSize}',
    );
    expect(card.size, const Size(296, 264));
    expect(hour.size, const Size(112, 72));
    expect(minute.size, const Size(112, 72));
    expect(shape.borderRadius, BorderRadius.circular(AlpRadius.card));
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
  });
}
