import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/l10n/app_localizations.dart';
import 'package:openstrap_edge/main_gallery.dart';
import 'package:openstrap_edge/openband/alp_tokens.dart';
import 'package:openstrap_edge/openband/settings_controls.dart';
import 'package:openstrap_edge/openband/theme.dart';
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
    final icons = FontLoader('packages/lucide_icons_flutter/Lucide')
      ..addFont(
        rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
      );
    await icons.load();
  });

  final now = DateTime(2026, 9, 18, 9, 41);
  final armedAt = DateTime(2026, 9, 19, 7, 0);
  final schedule = fillDefaultAlarmSchedule(const [
    AlarmScheduleEntry(weekday: 5, hour: 7, minute: 0, enabled: true),
    AlarmScheduleEntry(weekday: 2, hour: 6, minute: 30, enabled: true),
  ]);

  Future<void> mount(
    WidgetTester tester, {
    DateTime? at,
    AlarmArmState state = AlarmArmState.none,
    bool connected = true,
    List<AlarmScheduleEntry>? days,
    Brightness brightness = Brightness.light,
    double width = 393,
    double scale = 1,
    Future<void> Function(int weekday, bool enabled)? onToggleDay,
    Future<void> Function(int weekday, int hour, int minute)? onSetDayTime,
    Future<void> Function()? onTest,
    Future<void> Function()? onCancel,
    DateTime? clock,
    bool synthetic = false,
    Locale locale = const Locale('de'),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, width == 375 ? 812 : 852);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: openBandTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: AlarmScreenView(
            armedAt: at,
            now: clock ?? now,
            state: state,
            connected: connected,
            schedule: days ?? schedule,
            synthetic: synthetic,
            onToggleDay: onToggleDay,
            onSetDayTime: onSetDayTime,
            onTest: onTest,
            onCancel: onCancel,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('none shows Nächster Alarm, not two emdashes', (tester) async {
    await mount(tester, onToggleDay: (_, _) async {});
    expect(find.text('Nächster Alarm'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('alarm-hero-time'))).data,
      '—',
    );
    expect(find.text('Aus'), findsWidgets);
    expect(find.text('06:30'), findsOneWidget);
    expect(find.text('Am Band bestätigt'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no epoch is Aus even if the view state is stale confirmed', (
    tester,
  ) async {
    await mount(
      tester,
      state: AlarmArmState.confirmed,
      onToggleDay: (_, _) async {},
    );
    expect(find.text('Aus'), findsWidgets);
    expect(find.text('Am Band bestätigt'), findsNothing);
  });

  testWidgets('confirmed labels the latch, pending and unknown do not', (
    tester,
  ) async {
    await mount(
      tester,
      at: armedAt,
      state: AlarmArmState.confirmed,
      onTest: () async {},
      onCancel: () async {},
    );
    expect(find.text('07:00'), findsWidgets);
    expect(find.text('Am Band bestätigt'), findsOneWidget);
    expect(find.text('Bestätigung offen'), findsNothing);

    await mount(
      tester,
      at: armedAt,
      state: AlarmArmState.pending,
      onTest: () async {},
      onCancel: () async {},
    );
    expect(find.text('Bestätigung offen'), findsOneWidget);
    expect(find.text('Am Band bestätigt'), findsNothing);

    await mount(
      tester,
      at: armedAt,
      state: AlarmArmState.unknown,
      onTest: () async {},
      onCancel: () async {},
    );
    expect(find.text('Bestätigung offen'), findsOneWidget);
    expect(find.text('Am Band bestätigt'), findsNothing);
    expect(AlarmScreenView.stateLabel(AlarmArmState.unknown), isNot(contains('Confirmed')));
    expect(AlarmScreenView.stateLabel(AlarmArmState.pending), isNot(contains('Confirmed')));
    expect(
      AlarmScreenView.stateLabel(AlarmArmState.confirmed),
      contains('Confirmed'),
    );
  });

  testWidgets('offline says not connected even when confirmed, schedule readable', (
    tester,
  ) async {
    var toggles = 0;
    var times = 0;
    var tests = 0;
    var cancels = 0;
    await mount(
      tester,
      at: armedAt,
      state: AlarmArmState.confirmed,
      connected: false,
      onToggleDay: (_, _) async => toggles++,
      onSetDayTime: (_, _, _) async => times++,
      onTest: () async => tests++,
      onCancel: () async => cancels++,
    );
    expect(find.text('Nicht verbunden'), findsOneWidget);
    expect(find.text('Am Band bestätigt'), findsOneWidget);
    expect(find.text('06:30'), findsOneWidget);
    expect(find.text('Samstag'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'Mittwoch, 06:30')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'Uhrzeit Mittwoch 06:30')),
      findsOneWidget,
    );
    final sw = tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch).first);
    expect(sw.onChanged, isNull);
    await tester.tap(find.byType(CupertinoSwitch).at(2));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel(RegExp(r'Uhrzeit Mittwoch')));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsNothing);
    await tester.tap(find.text('Vibration testen'));
    await tester.pump();
    await tester.tap(find.text('Ausschalten'));
    await tester.pump();
    expect(toggles, 0);
    expect(times, 0);
    expect(tests, 0);
    expect(cancels, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('off day shows emdash and keeps the stored time off screen', (
    tester,
  ) async {
    await mount(
      tester,
      days: fillDefaultAlarmSchedule(const [
        AlarmScheduleEntry(weekday: 0, hour: 5, minute: 45, enabled: false),
        AlarmScheduleEntry(weekday: 1, hour: 6, minute: 15, enabled: true),
      ]),
      onToggleDay: (_, _) async {},
      onSetDayTime: (_, _, _) async {},
    );
    expect(find.text('06:15'), findsOneWidget);
    expect(find.text('05:45'), findsNothing);
    expect(find.text('—'), findsWidgets);
    expect(find.bySemanticsLabel(RegExp(r'Uhrzeit Montag')), findsNothing);
    expect(find.bySemanticsLabel(RegExp(r'Uhrzeit Dienstag 06:15')), findsOneWidget);
  });

  testWidgets('fr and es keep ARB labels; en stays Paper English', (
    tester,
  ) async {
    final fr = await AppLocalizations.delegate.load(const Locale('fr'));
    final es = await AppLocalizations.delegate.load(const Locale('es'));

    await mount(
      tester,
      locale: const Locale('fr'),
      at: armedAt,
      state: AlarmArmState.confirmed,
      connected: false,
      onTest: () async {},
      onCancel: () async {},
    );
    expect(find.text(fr.alarmHeadlineConfirmed), findsOneWidget);
    expect(find.text(fr.alarmNotConnectedTitle), findsOneWidget);
    expect(find.text(fr.alarmCancelTheAlarm), findsOneWidget);
    expect(find.text(fr.alarmTestTheBuzz), findsOneWidget);
    expect(find.text('Confirmed on the band'), findsNothing);
    expect(find.text('Turn off'), findsNothing);

    await tester.tap(find.byTooltip(fr.alarmNavTitle));
    await tester.pumpAndSettle();
    expect(find.text(fr.alarmDetailConfirmed), findsOneWidget);
    expect(find.text(fr.alarmNotConnectedBody), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await mount(
      tester,
      locale: const Locale('es'),
      at: armedAt,
      state: AlarmArmState.unknown,
      onTest: () async {},
      onCancel: () async {},
    );
    expect(find.text(es.alarmHeadlineUnknown), findsOneWidget);
    expect(find.text(es.alarmCancelTheAlarm), findsOneWidget);
    expect(find.text('Confirmation pending'), findsNothing);

    await mount(
      tester,
      locale: const Locale('en'),
      at: armedAt,
      state: AlarmArmState.confirmed,
      connected: false,
      onTest: () async {},
      onCancel: () async {},
    );
    expect(find.text('Confirmed on the band'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text('Turn off'), findsOneWidget);
    expect(find.text('Next alarm'), findsNothing);
    expect(find.text('The band has this alarm'), findsNothing);
    expect(find.text('Cancel the alarm'), findsNothing);

    await mount(
      tester,
      locale: const Locale('fr'),
      onToggleDay: (_, _) async {},
    );
    expect(find.text(fr.alarmHeadlineNone), findsOneWidget);
    expect(find.text('Next alarm'), findsNothing);
  });

  testWidgets('toggle, picker, test and cancel run; failures surface', (
    tester,
  ) async {
    final toggles = <(int, bool)>[];
    final times = <(int, int, int)>[];
    var tests = 0;
    var cancels = 0;
    await mount(
      tester,
      at: armedAt,
      state: AlarmArmState.confirmed,
      onToggleDay: (w, e) async => toggles.add((w, e)),
      onSetDayTime: (w, h, m) async => times.add((w, h, m)),
      onTest: () async => tests++,
      onCancel: () async => cancels++,
    );

    await tester.tap(find.byType(CupertinoSwitch).at(2));
    await tester.pumpAndSettle();
    expect(toggles, [(2, false)]);
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(find.bySemanticsLabel(RegExp(r'Uhrzeit Mittwoch')));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(times, isNotEmpty);
    expect(times.single.$1, 2);
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(find.text('Vibration testen'));
    await tester.pumpAndSettle();
    expect(tests, 1);
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(find.text('Ausschalten'));
    await tester.pumpAndSettle();
    expect(cancels, 1);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('every callback failure is reported, including day toggle', (
    tester,
  ) async {
    await mount(
      tester,
      at: armedAt,
      state: AlarmArmState.pending,
      onToggleDay: (_, _) async => throw Exception('Tag nicht geschrieben'),
      onSetDayTime: (_, _, _) async =>
          throw Exception('Uhrzeit nicht geschrieben'),
      onTest: () async => throw Exception('Vibration fehlgeschlagen'),
      onCancel: () async => throw Exception('Ausschalten fehlgeschlagen'),
    );

    await tester.tap(find.byType(CupertinoSwitch).first);
    await tester.pumpAndSettle();
    expect(find.text('Tag nicht geschrieben'), findsOneWidget);

    ScaffoldMessenger.of(
      tester.element(find.byType(AlarmScreenView)),
    ).clearSnackBars();
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel(RegExp(r'Uhrzeit Mittwoch')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Uhrzeit nicht geschrieben'), findsOneWidget);

    ScaffoldMessenger.of(
      tester.element(find.byType(AlarmScreenView)),
    ).clearSnackBars();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Vibration testen'));
    await tester.pumpAndSettle();
    expect(find.text('Vibration fehlgeschlagen'), findsOneWidget);

    ScaffoldMessenger.of(
      tester.element(find.byType(AlarmScreenView)),
    ).clearSnackBars();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ausschalten'));
    await tester.pumpAndSettle();
    expect(find.text('Ausschalten fehlgeschlagen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('busy guard blocks a second write', (tester) async {
    var toggles = 0;
    var times = 0;
    var tests = 0;
    var cancels = 0;
    final hold = Completer<void>();
    await mount(
      tester,
      at: armedAt,
      state: AlarmArmState.confirmed,
      onToggleDay: (_, _) async {
        toggles++;
        await hold.future;
      },
      onSetDayTime: (_, _, _) async => times++,
      onTest: () async => tests++,
      onCancel: () async => cancels++,
    );
    await tester.tap(find.byType(CupertinoSwitch).at(2));
    await tester.pump();
    await tester.tap(find.byType(CupertinoSwitch).at(5));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel(RegExp(r'Uhrzeit Mittwoch')));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsNothing);
    await tester.tap(find.text('Vibration testen'));
    await tester.pump();
    await tester.tap(find.text('Ausschalten'));
    await tester.pump();
    expect(toggles, 1);
    expect(times, 0);
    expect(tests, 0);
    expect(cancels, 0);
    hold.complete();
    await tester.pumpAndSettle();
    expect(toggles, 1);
    expect(times, 0);
    expect(tests, 0);
    expect(cancels, 0);
  });

  testWidgets('synthetic label is gallery-only', (tester) async {
    await mount(tester);
    expect(find.text('Synthetische Daten'), findsNothing);
    await mount(tester, synthetic: true);
    expect(find.text('Synthetische Daten'), findsOneWidget);
  });

  testWidgets('info sheet states confirmation once, for the current latch', (
    tester,
  ) async {
    Future<void> open() async {
      await tester.tap(find.byTooltip('Alarm: Plan und Bestätigung'));
      await tester.pumpAndSettle();
    }

    await mount(
      tester,
      at: armedAt,
      state: AlarmArmState.confirmed,
      onTest: () async {},
      onCancel: () async {},
    );
    await open();
    expect(
      find.text('Der Wochenplan bestimmt den nächsten Alarm am Band.'),
      findsOneWidget,
    );
    expect(find.text('Das Band hat diesen Alarm bestätigt.'), findsOneWidget);
    expect(
      find.textContaining('Zum Ändern ist eine Verbindung nötig'),
      findsOneWidget,
    );
    expect(find.textContaining('Bestätigung steht noch aus'), findsNothing);
    expect(find.textContaining('keine aktuelle Bestätigung'), findsNothing);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();

    await mount(
      tester,
      at: armedAt,
      state: AlarmArmState.pending,
      onTest: () async {},
      onCancel: () async {},
    );
    await open();
    expect(
      find.text('Der Alarm wurde gesendet. Die Bestätigung steht noch aus.'),
      findsOneWidget,
    );
    expect(find.text('Das Band hat diesen Alarm bestätigt.'), findsNothing);
    expect(find.textContaining('keine aktuelle Bestätigung'), findsNothing);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();

    await mount(
      tester,
      at: armedAt,
      state: AlarmArmState.unknown,
      onTest: () async {},
      onCancel: () async {},
    );
    await open();
    expect(
      find.text(
        'Zu diesem gespeicherten Termin liegt keine aktuelle Bestätigung vor.',
      ),
      findsOneWidget,
    );
    expect(find.text('Das Band hat diesen Alarm bestätigt.'), findsNothing);
    expect(find.textContaining('Bestätigung steht noch aus'), findsNothing);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();

    await mount(tester, onToggleDay: (_, _) async {});
    await open();
    expect(find.text('Das Band hat diesen Alarm bestätigt.'), findsNothing);
    expect(find.textContaining('Bestätigung steht noch aus'), findsNothing);
    expect(find.textContaining('keine aktuelle Bestätigung'), findsNothing);
    expect(
      find.text('Der Wochenplan bestimmt den nächsten Alarm am Band.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Zum Ändern ist eine Verbindung nötig'),
      findsOneWidget,
    );
  });

  testWidgets('large text on a small width stays usable', (tester) async {
    var toggled = false;
    await mount(
      tester,
      at: armedAt,
      state: AlarmArmState.confirmed,
      width: 375,
      scale: 2,
      onToggleDay: (_, _) async => toggled = true,
      onSetDayTime: (_, _, _) async {},
      onTest: () async {},
      onCancel: () async {},
    );
    expect(tester.takeException(), isNull);

    double labelX(int day, String name) => tester
        .getTopLeft(
          find.descendant(
            of: find.byKey(ValueKey('alarm-day-$day')),
            matching: find.text(name),
          ),
        )
        .dx;
    double wellX(int day, String time) {
      final text = find.descendant(
        of: find.byKey(ValueKey('alarm-day-$day')),
        matching: find.text(time),
      );
      return tester
          .getTopLeft(
            find
                .ancestor(of: text, matching: find.byType(DecoratedBox))
                .first,
          )
          .dx;
    }

    expect(labelX(0, 'Montag'), labelX(1, 'Dienstag'));
    expect(labelX(0, 'Montag'), labelX(2, 'Mittwoch'));
    expect(wellX(0, '—'), wellX(1, '—'));
    expect(wellX(0, '—'), wellX(2, '06:30'));
    expect(labelX(0, 'Montag'), wellX(0, '—'));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('alarm-day-0'))).dx,
      tester.getTopLeft(find.byKey(const ValueKey('alarm-day-2'))).dx,
    );

    await tester.scrollUntilVisible(
      find.text('Ausschalten'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ausschalten'));
    await tester.pumpAndSettle();
    final mondaySwitch = find.descendant(
      of: find.byKey(const ValueKey('alarm-day-0')),
      matching: find.byType(CupertinoSwitch),
    );
    await tester.scrollUntilVisible(
      mondaySwitch,
      -300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(mondaySwitch);
    await tester.pumpAndSettle();
    expect(toggled, isTrue);

    final wednesdayTime = find.bySemanticsLabel(RegExp(r'Uhrzeit Mittwoch'));
    await tester.scrollUntilVisible(
      wednesdayTime,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(wednesdayTime);
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('Abbrechen').first);
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('civil day delta stays 1 across a 23-hour spring-forward', () {
    final from = DateTime(2026, 3, 28, 22, 0);
    final to = DateTime(2026, 3, 29, 7, 0);
    expect(AlarmScreenView.civilDayDelta(from, to), 1);
    expect(AlarmScreenView.whichDay(to, from, null), 'Morgen');
  });

  testWidgets('spring-forward next calendar day is tomorrow in semantics', (
    tester,
  ) async {
    await mount(
      tester,
      at: DateTime(2026, 3, 29, 7, 0),
      clock: DateTime(2026, 3, 28, 22, 0),
      state: AlarmArmState.confirmed,
      onTest: () async {},
      onCancel: () async {},
    );
    expect(find.text('Sonntag 29.03.'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Sonntag 29.03.*Morgen')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('Später heute')), findsNothing);
  });

  testWidgets('weekly card has no row dividers', (tester) async {
    await mount(
      tester,
      at: armedAt,
      state: AlarmArmState.confirmed,
      onTest: () async {},
      onCancel: () async {},
    );
    expect(find.byType(Divider), findsNothing);
  });

  testWidgets('gallery session updates toggle and keeps stored time', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: openBandTheme(Brightness.light),
        home: AlarmGallerySession(
          armedAt: armedAt,
          state: AlarmArmState.confirmed,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('06:30'), findsOneWidget);
    await tester.tap(find.byType(CupertinoSwitch).at(2));
    await tester.pumpAndSettle();
    expect(find.text('06:30'), findsNothing);
    await tester.tap(find.byType(CupertinoSwitch).at(2));
    await tester.pumpAndSettle();
    expect(find.text('06:30'), findsOneWidget);
    expect(find.text('Synthetische Daten'), findsOneWidget);
  });

  testWidgets('gallery aus fixture has no enabled days', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: openBandTheme(Brightness.light),
        home: const AlarmGallerySession(scheduleEnabled: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nächster Alarm'), findsOneWidget);
    expect(find.text('06:30'), findsNothing);
    expect(find.text('07:00'), findsNothing);
    expect(
      tester
          .widgetList<CupertinoSwitch>(find.byType(CupertinoSwitch))
          .every((s) => !s.value),
      isTrue,
    );
  });

  testWidgets('shared switch contrast is distinct in light and dark', (
    tester,
  ) async {
    Future<CupertinoSwitch> pumpSwitch({
      required Brightness brightness,
      required bool value,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: openBandTheme(brightness),
          home: Scaffold(
            body: ListView(
              children: [
                OBSettingsToggleRow(
                  label: 'Test',
                  value: value,
                  interactive: true,
                  onToggle: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(OBSettingsToggleRow)).height, 56);
      return tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch));
    }

    final lightOn = await pumpSwitch(brightness: Brightness.light, value: true);
    expect(lightOn.activeTrackColor, AlpColor.ink);
    expect(lightOn.thumbColor, AlpColor.canvas);

    final lightOff = await pumpSwitch(
      brightness: Brightness.light,
      value: false,
    );
    expect(lightOff.inactiveTrackColor, AlpColor.line);
    expect(lightOff.inactiveThumbColor, AlpColor.canvas);

    final darkOn = await pumpSwitch(brightness: Brightness.dark, value: true);
    expect(darkOn.activeTrackColor, AlpColor.darkInk);
    expect(darkOn.thumbColor, AlpColor.darkCanvas);
    expect(darkOn.activeTrackColor, isNot(darkOn.thumbColor));

    final darkOff = await pumpSwitch(brightness: Brightness.dark, value: false);
    expect(darkOff.inactiveTrackColor, AlpColor.darkLine);
    expect(darkOff.inactiveThumbColor, AlpColor.darkInk);
    expect(darkOff.inactiveTrackColor, isNot(darkOff.inactiveThumbColor));
  });

  for (final brightness in Brightness.values) {
    testWidgets('renders ${brightness.name} without overflow', (tester) async {
      await mount(
        tester,
        at: armedAt,
        state: AlarmArmState.confirmed,
        brightness: brightness,
        onTest: () async {},
        onCancel: () async {},
        onToggleDay: (_, _) async {},
        onSetDayTime: (_, _, _) async {},
      );
      expect(find.text('Alarm'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
