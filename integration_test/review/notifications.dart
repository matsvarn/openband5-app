part of 'harness.dart';

Future<void> reviewNotifications(ReviewHarness h) async {
  final tester = h.tester;
  Future<void> revealNotification(Finder target) async {
    final scrollable = find.byType(Scrollable).last;
    if (target.evaluate().isEmpty) {
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pumpAndSettle();
    }
    await tester.scrollUntilVisible(target, 200, scrollable: scrollable);
    await tester.pumpAndSettle();
  }

  Future<void> mountNotifications({
    required Brightness brightness,
    bool loaded = true,
    bool? granted = true,
    String? saveError,
    String? applyError,
    String? permissionError,
    NotificationPrefs prefs = openBandPaperNotificationPrefs,
    double? scale,
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
          ).copyWith(textScaler: TextScaler.linear(scale ?? 1)),
          child: child!,
        ),
        home: NotificationSettingsView(
          synthetic: true,
          loaded: loaded,
          granted: granted,
          prefs: prefs,
          saveError: saveError,
          applyError: applyError,
          permissionError: permissionError,
          onChanged: (_) async {},
          onRequestPermission: () {},
          onRetrySave: saveError == null ? null : () {},
          onRetryApply: applyError == null ? null : () {},
          onRetryPermission: permissionError == null ? null : () {},
        ),
      ),
    );
    if (loaded) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 350));
    }
  }

  for (final brightness in Brightness.values) {
    await mountNotifications(brightness: brightness);
    await h.capture('notifications-${brightness.name}');
  }
  await mountNotifications(
    brightness: Brightness.light,
    loaded: false,
    granted: null,
  );
  await h.capture('notifications-loading');
  await mountNotifications(brightness: Brightness.light, granted: false);
  await h.capture('notifications-denied');
  await mountNotifications(
    brightness: Brightness.light,
    saveError: 'Speichern fehlgeschlagen',
  );
  await h.capture('notifications-error');
  await mountNotifications(
    brightness: Brightness.light,
    applyError: 'Gespeichert. Anwenden fehlgeschlagen',
  );
  await h.capture('notifications-apply-error');
  await mountNotifications(
    brightness: Brightness.dark,
    applyError: 'Gespeichert. Anwenden fehlgeschlagen',
  );
  await h.capture('notifications-apply-error-dark');
  await mountNotifications(
    brightness: Brightness.light,
    permissionError: 'internal',
  );
  await h.capture('notifications-permission-unknown');
  await mountNotifications(brightness: Brightness.light);
  await revealNotification(find.byKey(const ValueKey('quiet-start')));
  await tester.tap(find.byKey(const ValueKey('quiet-start')));
  await tester.pumpAndSettle();
  await h.capture('notifications-quiet-time');
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await mountNotifications(brightness: Brightness.dark);
  await revealNotification(find.byKey(const ValueKey('quiet-start')));
  await tester.tap(find.byKey(const ValueKey('quiet-start')));
  await tester.pumpAndSettle();
  await h.capture('notifications-quiet-time-dark');
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await mountNotifications(brightness: Brightness.light);
  await revealNotification(find.byKey(const ValueKey('quiet-start')));
  await tester.tap(find.byKey(const ValueKey('quiet-start')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField).first, '88');
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  await h.capture('notifications-quiet-time-input');
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await mountNotifications(brightness: Brightness.light, scale: 2);
  await revealNotification(find.byKey(const ValueKey('quiet-start')));
  await tester.tap(find.byKey(const ValueKey('quiet-start')));
  await tester.pumpAndSettle();
  await h.capture('notifications-quiet-time-large');
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await mountNotifications(brightness: Brightness.light);
  await revealNotification(find.byKey(const ValueKey('notif-battery')));
  await tester.tap(find.byKey(const ValueKey('notif-battery')));
  await tester.pumpAndSettle();
  await h.capture('notifications-choice');
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await mountNotifications(brightness: Brightness.dark);
  await revealNotification(find.byKey(const ValueKey('notif-battery')));
  await tester.tap(find.byKey(const ValueKey('notif-battery')));
  await tester.pumpAndSettle();
  await h.capture('notifications-choice-dark');
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await mountNotifications(brightness: Brightness.light, scale: 2);
  await revealNotification(find.byKey(const ValueKey('notif-battery')));
  await tester.tap(find.byKey(const ValueKey('notif-battery')));
  await tester.pumpAndSettle();
  await h.capture('notifications-choice-large');

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  var live = openBandPaperNotificationPrefs;
  final applied = <NotificationPrefs>[];
  var reminders = 0;
  var failSave = false;

  Future<void> mountLive({
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
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            alwaysUse24HourFormat: true,
          ),
          child: child!,
        ),
        home: NotificationSettings(
          synthetic: true,
          loadPrefs: () async => live,
          persistPrefs: (prefs) async {
            if (failSave) throw Exception('disk full');
            live = prefs;
          },
          readPermission: () async => true,
          onRefreshReminders: () async => reminders++,
          onArmWater: (prefs) async => applied.add(prefs),
          onRefreshBattery: (prefs) async => applied.add(prefs),
          relaySupported: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  CupertinoSwitch notifSwitch(Key key) {
    return tester.widget<CupertinoSwitch>(
      find.descendant(
        of: find.byKey(key),
        matching: find.byType(CupertinoSwitch),
      ),
    );
  }

  Future<void> tapLiveSwitch(Key key) async {
    final sw = find.descendant(
      of: find.byKey(key),
      matching: find.byType(CupertinoSwitch),
    );
    await revealNotification(sw);
    await tester.pumpAndSettle();
    await tester.tap(sw);
    await tester.pumpAndSettle();
  }

  await mountLive();
  expect(notifSwitch(const ValueKey('notif-health')).value, isTrue);
  final remindersBeforeToggle = reminders;
  await tapLiveSwitch(const ValueKey('notif-health'));
  expect(live.healthEnabled, isFalse);
  expect(notifSwitch(const ValueKey('notif-health')).value, isFalse);
  expect(reminders, greaterThan(remindersBeforeToggle));
  expect(applied, isNotEmpty);
  expect(applied.last.healthEnabled, isFalse);

  await revealNotification(find.byKey(const ValueKey('notif-battery')));
  await tester.tap(find.byKey(const ValueKey('notif-battery')));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('notification-choice')), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('notification-choice-25')));
  await tester.pumpAndSettle();
  expect(live.batteryAlertPct, 25);
  expect(find.text('25 %'), findsOneWidget);
  expect(applied.last.batteryAlertPct, 25);

  await tester.tap(find.byKey(const ValueKey('notif-battery')));
  await tester.pumpAndSettle();
  expect(
    tester
        .getSemantics(find.byKey(const ValueKey('notification-choice-25')))
        .flagsCollection
        .isSelected
        .toBoolOrNull(),
    isTrue,
  );
  expect(
    tester
        .getSemantics(find.byKey(const ValueKey('notification-choice-20')))
        .flagsCollection
        .isSelected
        .toBoolOrNull(),
    isNot(true),
  );
  await tester.tapAt(const Offset(20, 150));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('notification-choice')), findsNothing);
  expect(live.batteryAlertPct, 25);

  await revealNotification(find.byKey(const ValueKey('notif-water-interval')));
  await tester.tap(find.byKey(const ValueKey('notif-water-interval')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('notification-choice-180')));
  await tester.pumpAndSettle();
  expect(live.waterIntervalMin, 180);
  expect(find.text('3h'), findsOneWidget);
  expect(applied.last.waterIntervalMin, 180);

  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('quiet-start')),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(find.byKey(const ValueKey('quiet-start')));
  await tester.pumpAndSettle();
  expect(find.byType(TimePickerDialog), findsOneWidget);
  expect(find.byIcon(Icons.keyboard_outlined), findsNothing);
  await tester.enterText(find.byType(TextFormField).first, '21');
  await tester.enterText(find.byType(TextFormField).last, '30');
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  expect(live.quietStartMin, 21 * 60 + 30);
  expect(find.text('21:30'), findsOneWidget);
  expect(applied.last.quietStartMin, 21 * 60 + 30);

  await h.capture('notifications-live');

  failSave = true;
  final remindersBeforeFail = reminders;
  await tapLiveSwitch(const ValueKey('notif-health'));
  expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
  expect(notifSwitch(const ValueKey('notif-health')).value, isFalse);
  expect(live.healthEnabled, isFalse);
  expect(live.batteryAlertPct, 25);
  expect(reminders, remindersBeforeFail);
  await h.capture('notifications-live-save-failure');
  failSave = false;
  await tester.tap(find.text('Erneut'));
  await tester.pumpAndSettle();
  expect(find.text('Speichern fehlgeschlagen'), findsNothing);
  expect(live.healthEnabled, isTrue);
  expect(notifSwitch(const ValueKey('notif-health')).value, isTrue);
  expect(applied.last.healthEnabled, isTrue);
  expect(reminders, greaterThan(remindersBeforeFail));
  await h.capture('notifications-live-save-retry');

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await mountLive(scale: 2);
  expect(find.text('25 %'), findsOneWidget);
  await h.capture('notifications-live-large');
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('quiet-start')),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
  expect(find.text('21:30'), findsOneWidget);
  await h.capture('notifications-live-large-quiet');
}
