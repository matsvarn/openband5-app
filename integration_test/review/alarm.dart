part of 'harness.dart';

Future<void> reviewAlarm(ReviewHarness h) async {
  final tester = h.tester;
  Future<void> mountAlarm({
    DateTime? at,
    AlarmArmState state = AlarmArmState.none,
    bool connected = true,
    bool scheduleEnabled = true,
    bool failing = false,
    Brightness brightness = Brightness.light,
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: openBandTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: AlarmGallerySession(
          armedAt: at,
          now: galleryAlarmNow,
          state: state,
          connected: connected,
          scheduleEnabled: scheduleEnabled,
          failing: failing,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder wednesdayTime() => find.descendant(
    of: find.byKey(const ValueKey('alarm-day-2')),
    matching: find.text('07:00'),
  );

  await mountAlarm(at: galleryAlarmAt, state: AlarmArmState.storedSeconds);
  await h.capture('alarm-ready');
  await tester.tap(find.byType(CupertinoSwitch).at(2));
  await tester.pumpAndSettle();
  expect(wednesdayTime(), findsNothing);
  await tester.tap(find.byType(CupertinoSwitch).at(2));
  await tester.pumpAndSettle();
  expect(wednesdayTime(), findsOneWidget);
  await mountAlarm(
    at: galleryAlarmAt,
    state: AlarmArmState.storedSeconds,
    brightness: Brightness.dark,
  );
  await h.capture('alarm-ready-dark');
  await mountAlarm(at: galleryAlarmAt, state: AlarmArmState.unknown);
  await h.capture('alarm-light');
  await mountAlarm(
    at: galleryAlarmAt,
    state: AlarmArmState.unknown,
    brightness: Brightness.dark,
  );
  await h.capture('alarm-dark');
  await mountAlarm(at: galleryAlarmAt, state: AlarmArmState.pending);
  await h.capture('alarm-pending');
  await mountAlarm(scheduleEnabled: false);
  await h.capture('alarm-none');
  await mountAlarm(
    at: galleryAlarmAt,
    state: AlarmArmState.allSlotsInactive,
    scheduleEnabled: false,
  );
  await h.capture('alarm-slots-inactive');
  await mountAlarm(
    at: galleryAlarmAt,
    state: AlarmArmState.allSlotsInactive,
    scheduleEnabled: false,
    brightness: Brightness.dark,
  );
  await h.capture('alarm-slots-inactive-dark');
  await mountAlarm(
    at: galleryAlarmAt,
    state: AlarmArmState.unknown,
    connected: false,
  );
  await h.capture('alarm-offline');
  await mountAlarm(
    at: galleryAlarmAt,
    state: AlarmArmState.pending,
    failing: true,
  );
  await tester.tap(find.text('Ausschalten'));
  await tester.pumpAndSettle();
  await h.capture('alarm-error');
  await mountAlarm(at: galleryAlarmAt, state: AlarmArmState.unknown);
  await tester.tap(find.bySemanticsLabel(RegExp(r'Uhrzeit Mittwoch')));
  await tester.pumpAndSettle();
  await h.capture('alarm-timepicker');
  await tester.tap(find.text('Abbrechen').first);
  await tester.pumpAndSettle();
  await mountAlarm(
    at: galleryAlarmAt,
    state: AlarmArmState.unknown,
    brightness: Brightness.dark,
  );
  await tester.tap(find.bySemanticsLabel(RegExp(r'Uhrzeit Mittwoch')));
  await tester.pumpAndSettle();
  await h.capture('alarm-timepicker-dark');
  await tester.tap(find.text('Abbrechen').first);
  await tester.pumpAndSettle();
  await mountAlarm(at: galleryAlarmAt, state: AlarmArmState.storedSeconds);
  await tester.tap(find.bySemanticsLabel(RegExp(r'Uhrzeit Mittwoch')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField).first, '88');
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  await h.capture('alarm-timepicker-input');
  await tester.tap(find.text('Abbrechen').first);
  await tester.pumpAndSettle();
  await mountAlarm(
    at: galleryAlarmAt,
    state: AlarmArmState.storedSeconds,
    scale: 2,
  );
  await h.capture('alarm-large-text');
  await tester.tap(find.bySemanticsLabel(RegExp(r'Uhrzeit Mittwoch')));
  await tester.pumpAndSettle();
  await h.capture('alarm-timepicker-large');
  await tester.tap(find.text('Abbrechen').first);
  await tester.pumpAndSettle();
  await mountAlarm(
    at: galleryAlarmAt,
    state: AlarmArmState.offPending,
    scheduleEnabled: false,
  );
  await h.capture('alarm-off-pending');
  await tester.tap(find.text('Erneut ausschalten'));
  await tester.pumpAndSettle();
  await mountAlarm(
    at: galleryAlarmAt,
    state: AlarmArmState.offPending,
    scheduleEnabled: false,
    brightness: Brightness.dark,
  );
  await h.capture('alarm-off-pending-dark');
  await mountAlarm(
    at: galleryAlarmAt,
    state: AlarmArmState.offPending,
    scheduleEnabled: false,
    connected: false,
  );
  await h.capture('alarm-off-offline');
  await mountAlarm(
    at: galleryAlarmAt,
    state: AlarmArmState.offPending,
    scheduleEnabled: false,
    failing: true,
  );
  await tester.tap(find.text('Erneut ausschalten'));
  await tester.pumpAndSettle();
  await h.capture('alarm-off-retry-error');
}
