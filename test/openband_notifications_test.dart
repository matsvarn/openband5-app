import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/notify/notification_prefs.dart';
import 'package:openstrap_edge/notify/notification_service.dart';
import 'package:openstrap_edge/openband/notification_settings.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpView(
    WidgetTester tester, {
    NotificationPrefs prefs = const NotificationPrefs(),
    bool loaded = true,
    bool? granted = true,
    bool busy = false,
    bool relaySupported = false,
    bool synthetic = false,
    String? loadError,
    String? permissionError,
    String? saveError,
    String? applyError,
    void Function(NotificationPrefs Function(NotificationPrefs))? onEdit,
    Future<void> Function(NotificationPrefs)? onChanged,
    VoidCallback? onRequestPermission,
    VoidCallback? onOpenRelay,
    VoidCallback? onRetryLoad,
    VoidCallback? onRetryPermission,
    VoidCallback? onRetrySave,
    VoidCallback? onRetryApply,
    double scale = 1,
    double width = 393,
    double height = 2400,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        locale: const Locale('de'),
        debugShowCheckedModeBanner: false,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(
          Brightness.light,
        ).copyWith(platform: TargetPlatform.iOS),
        darkTheme: openBandTheme(
          Brightness.dark,
        ).copyWith(platform: TargetPlatform.iOS),
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('capture'),
          child: Theme(
            data: openBandTheme(
              brightness,
            ).copyWith(platform: TargetPlatform.iOS),
            child: NotificationSettingsView(
              prefs: prefs,
              loaded: loaded,
              granted: granted,
              busy: busy,
              relaySupported: relaySupported,
              synthetic: synthetic,
              loadError: loadError,
              permissionError: permissionError,
              saveError: saveError,
              applyError: applyError,
              onEdit: onEdit,
              onChanged: onChanged,
              onRequestPermission: onRequestPermission,
              onOpenRelay: onOpenRelay,
              onRetryLoad: onRetryLoad,
              onRetryPermission: onRetryPermission,
              onRetrySave: onRetrySave,
              onRetryApply: onRetryApply,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> revealNotification(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();
  }

  Future<void> tapSwitch(WidgetTester tester, Key key) async {
    final switchFinder = find.descendant(
      of: find.byKey(key),
      matching: find.byType(CupertinoSwitch),
    );
    await revealNotification(tester, switchFinder);
    await tester.tap(switchFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> openChoice(WidgetTester tester, Key row) async {
    await revealNotification(tester, find.byKey(row));
    await tester.tap(find.byKey(row));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notification-choice')), findsOneWidget);
  }

  Future<void> pumpHost(
    WidgetTester tester, {
    Future<NotificationPrefs> Function()? loadPrefs,
    Future<void> Function(NotificationPrefs)? persistPrefs,
    Future<bool> Function()? readPermission,
    Future<bool> Function()? requestPermission,
    Future<void> Function()? openSystemSettings,
    Future<void> Function()? onRefreshReminders,
    Future<void> Function(NotificationPrefs)? onArmWater,
    Future<void> Function(NotificationPrefs)? onRefreshBattery,
    bool? relaySupported,
    bool useServicePermission = false,
    AppState? appState,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 2400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final home = NotificationSettings(
      loadPrefs: loadPrefs,
      persistPrefs: persistPrefs,
      readPermission: useServicePermission
          ? null
          : (readPermission ?? () async => true),
      requestPermission: requestPermission,
      openSystemSettings: openSystemSettings,
      onRefreshReminders: appState != null
          ? null
          : (onRefreshReminders ?? () async {}),
      onArmWater: appState != null ? null : (onArmWater ?? (_) async {}),
      onRefreshBattery: appState != null
          ? null
          : (onRefreshBattery ?? (_) async {}),
      relaySupported: relaySupported ?? false,
    );
    Widget app = MaterialApp(
      key: UniqueKey(),
      locale: const Locale('de'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('de')],
      theme: openBandTheme(
        Brightness.light,
      ).copyWith(platform: TargetPlatform.iOS),
      home: home,
    );
    if (appState != null) {
      app = ChangeNotifierProvider<AppState>.value(value: appState, child: app);
    }
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  testWidgets('loading does not show denied or default switches', (
    tester,
  ) async {
    await pumpView(tester, loaded: false, granted: false);
    expect(find.byKey(const ValueKey('notification-loading')), findsOneWidget);
    expect(find.text('Mitteilungen nicht erlaubt'), findsNothing);
    expect(find.text('Erlauben'), findsNothing);
    expect(find.text('Auffällige Werte'), findsNothing);
    expect(find.text('Ruhezeiten'), findsNothing);
    expect(find.byType(CupertinoSwitch), findsNothing);
  });

  testWidgets('loading frame completes with a finite pump', (tester) async {
    await pumpView(tester, loaded: false, granted: null);
    expect(find.byKey(const ValueKey('notification-loading')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(const ValueKey('notification-loading')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('denied is one row and stays truthful', (tester) async {
    var asked = 0;
    await pumpView(
      tester,
      granted: false,
      onRequestPermission: () => asked++,
      onChanged: (_) async {},
    );
    expect(find.byKey(const ValueKey('notification-denied')), findsOneWidget);
    expect(find.text('Mitteilungen nicht erlaubt'), findsOneWidget);
    expect(find.text('Erlauben'), findsOneWidget);
    expect(find.text('Auffällige Werte'), findsOneWidget);
    await tester.tap(find.text('Erlauben'));
    expect(asked, 1);
  });

  testWidgets('every retained setting field is present', (tester) async {
    await pumpView(
      tester,
      prefs: const NotificationPrefs(waterEnabled: true),
      relaySupported: true,
      onChanged: (_) async {},
    );
    for (final key in [
      'notif-health',
      'notif-device',
      'notif-battery',
      'notif-alarm-latch',
      'notif-alarm-night',
      'notif-recovery',
      'notif-weekly',
      'notif-autodetect',
      'notif-movement',
      'notif-winddown',
      'notif-steps',
      'notif-meds',
      'notif-checkin',
      'notif-water',
      'notif-water-interval',
      'notification-relay',
      'notif-quiet',
      'quiet-start',
      'quiet-end',
      'notif-critical',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }
    for (final label in [
      'Auffällige Werte',
      'Bandstatus',
      'Warnen unter',
      'Alarmfehler',
      'Abends ohne Alarm',
      'Erholung bereit',
      'Wochenrückblick',
      'Erkannte Aktivitäten',
      'Bewegung',
      'Schlafenszeit',
      'Schrittziel',
      'Medikamente',
      'Tages-Check-in',
      'Wasser',
      'Abstand',
      'Bei App-Mitteilungen vibrieren',
      'Zeitraum',
      'Wichtige Hinweise zulassen',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('Ruhezeiten'), findsWidgets);
    expect(find.text('22:00'), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);
    expect(find.text('15 %'), findsOneWidget);
    expect(find.text('2h'), findsOneWidget);
  });

  testWidgets('conditional battery and water rows follow their switches', (
    tester,
  ) async {
    await pumpView(
      tester,
      prefs: const NotificationPrefs(deviceEnabled: false, waterEnabled: false),
      onChanged: (_) async {},
    );
    expect(find.byKey(const ValueKey('notif-battery')), findsNothing);
    expect(find.byKey(const ValueKey('notif-water-interval')), findsNothing);
    await pumpView(
      tester,
      prefs: const NotificationPrefs(deviceEnabled: true, waterEnabled: true),
      onChanged: (_) async {},
    );
    expect(find.byKey(const ValueKey('notif-battery')), findsOneWidget);
    expect(find.byKey(const ValueKey('notif-water-interval')), findsOneWidget);
  });

  testWidgets(
    'battery and water open a choice sheet; dismiss keeps the value',
    (tester) async {
      NotificationPrefs? last;
      await pumpView(
        tester,
        prefs: const NotificationPrefs(waterEnabled: true),
        onChanged: (next) async => last = next,
      );
      expect(find.text('15 %'), findsOneWidget);
      await openChoice(tester, const ValueKey('notif-battery'));
      expect(find.text('15 %'), findsWidgets);
      expect(find.text('20 %'), findsOneWidget);
      expect(find.text('40 %'), findsOneWidget);
      await tester.tapAt(const Offset(200, 24));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('notification-choice')), findsNothing);
      expect(last, isNull);
      expect(find.text('15 %'), findsOneWidget);

      await openChoice(tester, const ValueKey('notif-battery'));
      await tester.tap(find.byKey(const ValueKey('notification-choice-20')));
      await tester.pumpAndSettle();
      expect(last?.batteryAlertPct, 20);

      last = null;
      await pumpView(
        tester,
        prefs: const NotificationPrefs(waterEnabled: true, batteryAlertPct: 20),
        onChanged: (next) async => last = next,
      );
      expect(find.text('2h'), findsOneWidget);
      await openChoice(tester, const ValueKey('notif-water-interval'));
      await tester.tapAt(const Offset(200, 24));
      await tester.pumpAndSettle();
      expect(last, isNull);
      expect(find.text('2h'), findsOneWidget);
      await openChoice(tester, const ValueKey('notif-water-interval'));
      await tester.tap(find.byKey(const ValueKey('notification-choice-180')));
      await tester.pumpAndSettle();
      expect(last?.waterIntervalMin, 180);
    },
  );

  testWidgets('choice sheet stays usable in dark and at 2x', (tester) async {
    NotificationPrefs? last;
    await pumpView(
      tester,
      prefs: const NotificationPrefs(waterEnabled: true),
      onChanged: (_) async {},
      brightness: Brightness.dark,
    );
    await openChoice(tester, const ValueKey('notif-battery'));
    expect(find.text('40 %'), findsOneWidget);
    await tester.tapAt(const Offset(200, 24));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notification-choice')), findsNothing);

    await pumpView(
      tester,
      prefs: const NotificationPrefs(waterEnabled: true),
      onChanged: (next) async => last = next,
      scale: 2,
      width: 375,
      height: 812,
    );
    await openChoice(tester, const ValueKey('notif-battery'));
    await revealNotification(
      tester,
      find.byKey(const ValueKey('notification-choice-40')),
    );
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('notification-choice-40')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('notification-choice-40')));
    await tester.pumpAndSettle();
    expect(last?.batteryAlertPct, 40);
  });

  testWidgets('Android relay is present and iOS omits it', (tester) async {
    await pumpView(
      tester,
      relaySupported: true,
      onOpenRelay: () {},
      onChanged: (_) async {},
    );
    expect(find.byKey(const ValueKey('notification-relay')), findsOneWidget);
    await pumpView(tester, relaySupported: false, onChanged: (_) async {});
    expect(find.byKey(const ValueKey('notification-relay')), findsNothing);
  });

  testWidgets('synthetic label is gallery-only', (tester) async {
    await pumpView(tester, synthetic: true, onChanged: (_) async {});
    expect(find.text('Synthetische Daten'), findsOneWidget);
    await pumpView(tester, synthetic: false, onChanged: (_) async {});
    expect(find.text('Synthetische Daten'), findsNothing);
  });

  testWidgets('quiet hours wrap midnight and cancel leaves the value', (
    tester,
  ) async {
    NotificationPrefs? last;
    await pumpView(
      tester,
      prefs: const NotificationPrefs(
        quietStartMin: 22 * 60,
        quietEndMin: 7 * 60,
      ),
      onChanged: (next) async => last = next,
    );
    expect(find.text('22:00'), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('quiet-start')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey('quiet-start')));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(last, isNull);
    expect(find.text('22:00'), findsOneWidget);
  });

  testWidgets('small 2x layout keeps controls reachable', (tester) async {
    NotificationPrefs? last;
    final previousHitTestPolicy = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() {
      WidgetController.hitTestWarningShouldBeFatal = previousHitTestPolicy;
    });
    await pumpView(
      tester,
      prefs: const NotificationPrefs(waterEnabled: true),
      relaySupported: true,
      onChanged: (next) async => last = next,
      scale: 2,
      width: 375,
      height: 812,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Auffällige Werte'), findsOneWidget);
    expect(find.byType(CupertinoSwitch), findsWidgets);

    await revealNotification(
      tester,
      find.byKey(const ValueKey('notif-battery')),
    );
    expect(
      tester.getTopLeft(find.text('Warnen unter')).dx,
      tester.getTopLeft(find.text('Bandstatus')).dx,
    );
    expect(
      tester.getTopLeft(find.text('15 %')).dx,
      tester.getTopLeft(find.text('Warnen unter')).dx,
    );

    await openChoice(tester, const ValueKey('notif-battery'));
    await revealNotification(
      tester,
      find.byKey(const ValueKey('notification-choice-40')),
    );
    await tester.tap(find.byKey(const ValueKey('notification-choice-40')));
    await tester.pumpAndSettle();
    expect(last?.batteryAlertPct, 40);

    await revealNotification(
      tester,
      find.byKey(const ValueKey('notif-water-interval')),
    );
    expect(
      tester.getTopLeft(find.text('Abstand')).dx,
      tester.getTopLeft(find.text('Wasser')).dx,
    );
    expect(
      tester.getTopLeft(find.text('2h')).dx,
      tester.getTopLeft(find.text('Abstand')).dx,
    );

    await openChoice(tester, const ValueKey('notif-water-interval'));
    await revealNotification(
      tester,
      find.byKey(const ValueKey('notification-choice-180')),
    );
    await tester.tap(find.byKey(const ValueKey('notification-choice-180')));
    await tester.pumpAndSettle();
    expect(last?.waterIntervalMin, 180);

    await revealNotification(tester, find.byKey(const ValueKey('quiet-start')));
    expect(find.byKey(const ValueKey('quiet-start')), findsOneWidget);
    expect(find.byKey(const ValueKey('quiet-end')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quiet-start')));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(last?.quietStartMin, 22 * 60);
  });

  testWidgets('load failure shows concise copy and retry reloads', (
    tester,
  ) async {
    var loads = 0;
    await pumpHost(
      tester,
      loadPrefs: () async {
        loads++;
        if (loads == 1) throw Exception('prefs unreadable');
        return const NotificationPrefs();
      },
    );
    expect(find.text('Laden fehlgeschlagen'), findsOneWidget);
    expect(find.textContaining('prefs unreadable'), findsNothing);
    expect(find.text('Auffällige Werte'), findsNothing);
    expect(find.text('Erneut'), findsOneWidget);
    await tester.tap(find.text('Erneut'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(loads, 2);
    expect(find.text('Laden fehlgeschlagen'), findsNothing);
    expect(find.text('Auffällige Werte'), findsOneWidget);
  });

  testWidgets('retry load denied-to-granted applies committed prefs', (
    tester,
  ) async {
    var loads = 0;
    var granted = false;
    final applied = <NotificationPrefs>[];
    var reminders = 0;
    await pumpHost(
      tester,
      loadPrefs: () async {
        loads++;
        if (loads == 1) throw Exception('prefs unreadable');
        return const NotificationPrefs(
          waterEnabled: true,
          remindersEnabled: true,
        );
      },
      readPermission: () async => granted,
      onRefreshReminders: () async => reminders++,
      onArmWater: (prefs) async => applied.add(prefs),
      onRefreshBattery: (prefs) async => applied.add(prefs),
    );
    expect(find.text('Laden fehlgeschlagen'), findsOneWidget);
    expect(find.text('Mitteilungen nicht erlaubt'), findsNothing);
    expect(reminders, 0);
    granted = true;
    await tester.tap(find.text('Erneut'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(loads, 2);
    expect(find.text('Laden fehlgeschlagen'), findsNothing);
    expect(find.text('Auffällige Werte'), findsOneWidget);
    expect(find.text('Mitteilungen nicht erlaubt'), findsNothing);
    expect(reminders, 1);
    expect(applied, isNotEmpty);
    expect(applied.last.remindersEnabled, isTrue);
  });

  testWidgets('save failure keeps the previous value and offers retry', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'notif_health': true});
    final persisted = <bool>[];
    await pumpHost(
      tester,
      loadPrefs: NotificationPrefs.load,
      persistPrefs: (prefs) async {
        persisted.add(prefs.healthEnabled);
        throw Exception('disk full');
      },
    );
    expect(find.text('Auffällige Werte'), findsOneWidget);
    await tapSwitch(tester, const ValueKey('notif-health'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('notification-error')), findsOneWidget);
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(find.textContaining('disk full'), findsNothing);
    expect(
      find.textContaining('Gespeichert. Anwenden fehlgeschlagen'),
      findsNothing,
    );
    expect(find.text('Erneut'), findsOneWidget);
    final retry = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Erneut'),
    );
    expect(retry.style!.foregroundColor!.resolve(const {}), OB(false).ink);
    final switchWidget = tester.widget<CupertinoSwitch>(
      find.descendant(
        of: find.byKey(const ValueKey('notif-health')),
        matching: find.byType(CupertinoSwitch),
      ),
    );
    expect(switchWidget.value, isTrue);
    expect(persisted, [false]);
    final stored = await NotificationPrefs.load();
    expect(stored.healthEnabled, isTrue);
  });

  testWidgets('choice save failure keeps the previous value and retry writes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'notif_battery_pct': 15});
    var fail = true;
    final persisted = <int>[];
    await pumpHost(
      tester,
      loadPrefs: NotificationPrefs.load,
      persistPrefs: (prefs) async {
        persisted.add(prefs.batteryAlertPct);
        if (fail) throw Exception('disk full');
        await prefs.save();
      },
    );
    await tester.ensureVisible(find.byKey(const ValueKey('notif-battery')));
    await tester.tap(find.byKey(const ValueKey('notif-battery')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notification-choice-20')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notification-error')), findsOneWidget);
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(find.textContaining('disk full'), findsNothing);
    expect(find.text('15 %'), findsOneWidget);
    expect(persisted, [20]);
    fail = false;
    await tester.tap(find.text('Erneut'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notification-error')), findsNothing);
    expect(find.text('20 %'), findsOneWidget);
    final stored = await NotificationPrefs.load();
    expect(stored.batteryAlertPct, 20);
  });

  testWidgets('refresh failure after save shows saved value plus apply error', (
    tester,
  ) async {
    NotificationPrefs? saved;
    var refresh = 0;
    await pumpHost(
      tester,
      loadPrefs: () async => const NotificationPrefs(),
      persistPrefs: (prefs) async => saved = prefs,
      onRefreshReminders: () async {
        refresh++;
        throw Exception('schedule failed');
      },
    );
    await tapSwitch(tester, const ValueKey('notif-health'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(saved?.healthEnabled, isFalse);
    final switchWidget = tester.widget<CupertinoSwitch>(
      find.descendant(
        of: find.byKey(const ValueKey('notif-health')),
        matching: find.byType(CupertinoSwitch),
      ),
    );
    expect(switchWidget.value, isFalse);
    expect(
      find.textContaining('Gespeichert. Anwenden fehlgeschlagen'),
      findsOneWidget,
    );
    expect(find.textContaining('schedule failed'), findsNothing);
    expect(
      find.byKey(const ValueKey('notification-apply-error')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('notification-error')), findsNothing);
    expect(refresh, 1);
    await tester.tap(find.text('Erneut'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(refresh, 2);
  });

  testWidgets('preference persistence writes every retained field', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpHost(
      tester,
      loadPrefs: NotificationPrefs.load,
      persistPrefs: (prefs) => prefs.save(),
    );
    Future<void> toggle(Key key) async {
      await tapSwitch(tester, key);
    }

    await toggle(const ValueKey('notif-health'));
    await tester.ensureVisible(find.byKey(const ValueKey('notif-battery')));
    await tester.tap(find.byKey(const ValueKey('notif-battery')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notification-choice-20')));
    await tester.pumpAndSettle();
    await toggle(const ValueKey('notif-device'));
    await toggle(const ValueKey('notif-alarm-latch'));
    await toggle(const ValueKey('notif-alarm-night'));
    await toggle(const ValueKey('notif-recovery'));
    await toggle(const ValueKey('notif-weekly'));
    await toggle(const ValueKey('notif-autodetect'));
    await toggle(const ValueKey('notif-movement'));
    await toggle(const ValueKey('notif-winddown'));
    await toggle(const ValueKey('notif-steps'));
    await toggle(const ValueKey('notif-meds'));
    await toggle(const ValueKey('notif-checkin'));
    await toggle(const ValueKey('notif-water'));
    await tester.ensureVisible(
      find.byKey(const ValueKey('notif-water-interval')),
    );
    await tester.tap(find.byKey(const ValueKey('notif-water-interval')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notification-choice-180')));
    await tester.pumpAndSettle();
    await toggle(const ValueKey('notif-quiet'));
    await toggle(const ValueKey('notif-critical'));
    final stored = await NotificationPrefs.load();
    expect(stored.healthEnabled, isFalse);
    expect(stored.batteryAlertPct, 20);
    expect(stored.deviceEnabled, isFalse);
    expect(stored.alarmLatchFailedEnabled, isFalse);
    expect(stored.alarmNightCheckEnabled, isFalse);
    expect(stored.recoveryEnabled, isFalse);
    expect(stored.remindersEnabled, isFalse);
    expect(stored.autoDetectEnabled, isFalse);
    expect(stored.movementEnabled, isTrue);
    expect(stored.windDownEnabled, isTrue);
    expect(stored.stepGoalEnabled, isFalse);
    expect(stored.medsEnabled, isTrue);
    expect(stored.checkInEnabled, isTrue);
    expect(stored.waterEnabled, isTrue);
    expect(stored.waterIntervalMin, 180);
    expect(stored.quietEnabled, isFalse);
    expect(stored.quietStartMin, 22 * 60);
    expect(stored.quietEndMin, 7 * 60);
    expect(stored.criticalOverridesQuiet, isFalse);
  });

  testWidgets('busy serializes edits so the second toggle is not lost', (
    tester,
  ) async {
    final persistGate = Completer<void>();
    final saved = <NotificationPrefs>[];
    await pumpHost(
      tester,
      loadPrefs: () async => const NotificationPrefs(),
      persistPrefs: (prefs) async {
        saved.add(prefs);
        if (saved.length == 1) await persistGate.future;
      },
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('notif-health')),
        matching: find.byType(CupertinoSwitch),
      ),
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('notif-device')),
        matching: find.byType(CupertinoSwitch),
      ),
    );
    await tester.pump();
    expect(saved, isNotEmpty);
    persistGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(saved.last.healthEnabled, isFalse);
    expect(saved.last.deviceEnabled, isFalse);
    final health = tester.widget<CupertinoSwitch>(
      find.descendant(
        of: find.byKey(const ValueKey('notif-health')),
        matching: find.byType(CupertinoSwitch),
      ),
    );
    final device = tester.widget<CupertinoSwitch>(
      find.descendant(
        of: find.byKey(const ValueKey('notif-device')),
        matching: find.byType(CupertinoSwitch),
      ),
    );
    expect(health.value, isFalse);
    expect(device.value, isFalse);
  });

  testWidgets('held persist after disposal still applies the saved prefs', (
    tester,
  ) async {
    final persistGate = Completer<void>();
    final saved = <NotificationPrefs>[];
    final applied = <NotificationPrefs>[];
    var reminders = 0;
    var battery = 0;
    await pumpHost(
      tester,
      loadPrefs: () async => const NotificationPrefs(),
      persistPrefs: (prefs) async {
        saved.add(prefs);
        await persistGate.future;
      },
      onRefreshReminders: () async => reminders++,
      onArmWater: (prefs) async => applied.add(prefs),
      onRefreshBattery: (prefs) async => battery++,
    );
    await tapSwitch(tester, const ValueKey('notif-health'));
    expect(saved, isNotEmpty);
    expect(reminders, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    persistGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(saved.single.healthEnabled, isFalse);
    expect(reminders, 1);
    expect(battery, 1);
    expect(applied, isNotEmpty);
    expect(applied.single.healthEnabled, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'held persist apply failure after disposal is not an uncaught error',
    (tester) async {
      final persistGate = Completer<void>();
      var reminders = 0;
      await pumpHost(
        tester,
        loadPrefs: () async => const NotificationPrefs(),
        persistPrefs: (prefs) async {
          await persistGate.future;
        },
        onRefreshReminders: () async {
          reminders++;
          throw Exception('schedule failed');
        },
      );
      await tapSwitch(tester, const ValueKey('notif-health'));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      persistGate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(reminders, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('held persist after disposal still flushes a queued edit', (
    tester,
  ) async {
    final persistGate = Completer<void>();
    final saved = <NotificationPrefs>[];
    final applied = <NotificationPrefs>[];
    await pumpHost(
      tester,
      loadPrefs: () async => const NotificationPrefs(),
      persistPrefs: (prefs) async {
        saved.add(prefs);
        if (saved.length == 1) await persistGate.future;
      },
      onRefreshReminders: () async {},
      onArmWater: (prefs) async => applied.add(prefs),
      onRefreshBattery: (_) async {},
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('notif-health')),
        matching: find.byType(CupertinoSwitch),
      ),
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('notif-device')),
        matching: find.byType(CupertinoSwitch),
      ),
    );
    await tester.pump();
    expect(saved, isNotEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    persistGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(saved.last.healthEnabled, isFalse);
    expect(saved.last.deviceEnabled, isFalse);
    expect(applied, isNotEmpty);
    expect(applied.last.healthEnabled, isFalse);
    expect(applied.last.deviceEnabled, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'thrown permission query is unknown, not denied, and prefs remain',
    (tester) async {
      var probes = 0;
      await pumpHost(
        tester,
        loadPrefs: () async => const NotificationPrefs(),
        readPermission: () async {
          probes++;
          if (probes == 1) throw Exception('query failed');
          return true;
        },
      );
      expect(find.text('Auffällige Werte'), findsOneWidget);
      expect(find.byType(CupertinoSwitch), findsWidgets);
      expect(find.text('Mitteilungen nicht erlaubt'), findsNothing);
      expect(find.byKey(const ValueKey('notification-denied')), findsNothing);
      expect(
        find.byKey(const ValueKey('notification-permission-error')),
        findsOneWidget,
      );
      expect(find.text('Mitteilungen-Status unbekannt'), findsOneWidget);
      expect(find.textContaining('query failed'), findsNothing);
      await tester.tap(find.text('Erneut'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(probes, 2);
      expect(
        find.byKey(const ValueKey('notification-permission-error')),
        findsNothing,
      );
      expect(find.text('Mitteilungen nicht erlaubt'), findsNothing);
    },
  );

  testWidgets('resume permission failure is unknown, not denied', (
    tester,
  ) async {
    var probes = 0;
    await pumpHost(
      tester,
      loadPrefs: () async => const NotificationPrefs(),
      readPermission: () async {
        probes++;
        if (probes == 1) return true;
        throw Exception('probe failed');
      },
    );
    expect(find.text('Auffällige Werte'), findsOneWidget);
    expect(find.text('Mitteilungen nicht erlaubt'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(probes, greaterThan(1));
    expect(find.text('Auffällige Werte'), findsOneWidget);
    expect(find.text('Mitteilungen nicht erlaubt'), findsNothing);
    expect(
      find.byKey(const ValueKey('notification-permission-error')),
      findsOneWidget,
    );
    expect(find.text('Mitteilungen-Status unbekannt'), findsOneWidget);
    expect(find.textContaining('probe failed'), findsNothing);
  });

  testWidgets(
    'permission denial opens system settings when request stays false',
    (tester) async {
      var opened = 0;
      var requested = 0;
      await pumpHost(
        tester,
        loadPrefs: () async => const NotificationPrefs(),
        readPermission: () async => false,
        requestPermission: () async {
          requested++;
          return false;
        },
        openSystemSettings: () async => opened++,
      );
      expect(find.text('Mitteilungen nicht erlaubt'), findsOneWidget);
      await tester.tap(find.text('Erlauben'));
      await tester.pumpAndSettle();
      expect(requested, 1);
      expect(opened, 1);
      expect(find.text('Mitteilungen nicht erlaubt'), findsOneWidget);
    },
  );

  testWidgets('request grant applies committed prefs', (tester) async {
    final applied = <NotificationPrefs>[];
    var reminders = 0;
    await pumpHost(
      tester,
      loadPrefs: () async =>
          const NotificationPrefs(waterEnabled: true, remindersEnabled: true),
      readPermission: () async => false,
      requestPermission: () async => true,
      onRefreshReminders: () async => reminders++,
      onArmWater: (prefs) async => applied.add(prefs),
      onRefreshBattery: (prefs) async => applied.add(prefs),
    );
    expect(find.text('Mitteilungen nicht erlaubt'), findsOneWidget);
    expect(reminders, 0);
    expect(applied, isEmpty);
    await tester.tap(find.text('Erlauben'));
    await tester.pumpAndSettle();
    expect(find.text('Mitteilungen nicht erlaubt'), findsNothing);
    expect(find.byKey(const ValueKey('notification-denied')), findsNothing);
    expect(reminders, 1);
    expect(applied, isNotEmpty);
    expect(applied.last.waterEnabled, isTrue);
    expect(applied.last.remindersEnabled, isTrue);
  });

  testWidgets('denied resume grant applies committed prefs', (tester) async {
    var granted = false;
    final applied = <NotificationPrefs>[];
    var reminders = 0;
    await pumpHost(
      tester,
      loadPrefs: () async =>
          const NotificationPrefs(waterEnabled: true, remindersEnabled: true),
      readPermission: () async => granted,
      onRefreshReminders: () async => reminders++,
      onArmWater: (prefs) async => applied.add(prefs),
      onRefreshBattery: (prefs) async => applied.add(prefs),
    );
    expect(find.text('Mitteilungen nicht erlaubt'), findsOneWidget);
    expect(reminders, 0);
    granted = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Mitteilungen nicht erlaubt'), findsNothing);
    expect(reminders, 1);
    expect(applied.last.waterEnabled, isTrue);
    expect(applied.last.remindersEnabled, isTrue);
  });

  testWidgets('resume grant after disposal still applies committed prefs', (
    tester,
  ) async {
    final resumeProbe = Completer<bool>();
    addTearDown(() {
      if (!resumeProbe.isCompleted) resumeProbe.complete(false);
    });
    var reads = 0;
    final applied = <NotificationPrefs>[];
    var reminders = 0;
    await pumpHost(
      tester,
      loadPrefs: () async =>
          const NotificationPrefs(waterEnabled: true, remindersEnabled: true),
      readPermission: () async {
        reads++;
        if (reads == 1) return false;
        return resumeProbe.future;
      },
      onRefreshReminders: () async => reminders++,
      onArmWater: (prefs) async => applied.add(prefs),
      onRefreshBattery: (prefs) async => applied.add(prefs),
    );
    expect(find.text('Mitteilungen nicht erlaubt'), findsOneWidget);
    expect(reminders, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(reminders, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    resumeProbe.complete(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(reminders, 1);
    expect(applied, isNotEmpty);
    expect(applied.last.remindersEnabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('grant apply failure is apply error and retry reapplies', (
    tester,
  ) async {
    var fail = true;
    var reminders = 0;
    await pumpHost(
      tester,
      loadPrefs: () async => const NotificationPrefs(waterEnabled: true),
      readPermission: () async => false,
      requestPermission: () async => true,
      onRefreshReminders: () async {
        reminders++;
        if (fail) throw Exception('schedule failed');
      },
    );
    await tester.tap(find.text('Erlauben'));
    await tester.pumpAndSettle();
    expect(find.text('Mitteilungen nicht erlaubt'), findsNothing);
    expect(find.byKey(const ValueKey('notification-denied')), findsNothing);
    expect(
      find.byKey(const ValueKey('notification-apply-error')),
      findsOneWidget,
    );
    expect(find.text('Gespeichert. Anwenden fehlgeschlagen'), findsOneWidget);
    expect(find.textContaining('schedule failed'), findsNothing);
    expect(reminders, 1);
    fail = false;
    await tester.tap(find.text('Erneut'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('notification-apply-error')),
      findsNothing,
    );
    expect(reminders, 2);
  });

  testWidgets('denied and unknown do not apply committed prefs', (
    tester,
  ) async {
    final applied = <NotificationPrefs>[];
    var reminders = 0;
    await pumpHost(
      tester,
      loadPrefs: () async => const NotificationPrefs(waterEnabled: true),
      readPermission: () async => false,
      requestPermission: () async => false,
      openSystemSettings: () async {},
      onRefreshReminders: () async => reminders++,
      onArmWater: (prefs) async => applied.add(prefs),
      onRefreshBattery: (prefs) async => applied.add(prefs),
    );
    expect(reminders, 0);
    expect(applied, isEmpty);
    await tester.tap(find.text('Erlauben'));
    await tester.pumpAndSettle();
    expect(find.text('Mitteilungen nicht erlaubt'), findsOneWidget);
    expect(reminders, 0);
    expect(applied, isEmpty);

    await pumpHost(
      tester,
      loadPrefs: () async => const NotificationPrefs(waterEnabled: true),
      readPermission: () async {
        throw Exception('query failed');
      },
      onRefreshReminders: () async => reminders++,
      onArmWater: (prefs) async => applied.add(prefs),
      onRefreshBattery: (prefs) async => applied.add(prefs),
    );
    expect(find.text('Mitteilungen-Status unbekannt'), findsOneWidget);
    expect(reminders, 0);
    expect(applied, isEmpty);
  });

  testWidgets('grant during in-flight save applies the saved prefs not older', (
    tester,
  ) async {
    var granted = false;
    final persistGate = Completer<void>();
    addTearDown(() {
      if (!persistGate.isCompleted) persistGate.complete();
    });
    final applied = <NotificationPrefs>[];
    await pumpHost(
      tester,
      loadPrefs: () async => const NotificationPrefs(),
      readPermission: () async => granted,
      persistPrefs: (prefs) async {
        await persistGate.future;
      },
      onRefreshReminders: () async {},
      onArmWater: (prefs) async => applied.add(prefs),
      onRefreshBattery: (prefs) async => applied.add(prefs),
    );
    await tapSwitch(tester, const ValueKey('notif-health'));
    await tester.pump();
    expect(applied, isEmpty);
    granted = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(applied, isEmpty);
    persistGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(applied, isNotEmpty);
    expect(applied.any((p) => p.healthEnabled), isFalse);
    expect(applied.last.healthEnabled, isFalse);
  });

  testWidgets('info explains quiet hours without claiming total silence', (
    tester,
  ) async {
    await pumpView(tester, onChanged: (_) async {});
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Wecker auf dem Band bleibt'), findsOneWidget);
    expect(
      find.textContaining('Nicht jede Mitteilung wird stummgeschaltet'),
      findsOneWidget,
    );
    expect(find.textContaining('Selbst eintragen'), findsNothing);
    expect(find.textContaining('Dein Eintrag bleibt erhalten'), findsNothing);
  });

  testWidgets('direct toggle after failed save mutates the visible switch', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'notif_health': true});
    final persisted = <bool>[];
    var fail = true;
    await pumpHost(
      tester,
      loadPrefs: NotificationPrefs.load,
      persistPrefs: (prefs) async {
        persisted.add(prefs.healthEnabled);
        if (fail) throw Exception('disk full');
        await prefs.save();
      },
    );
    await tapSwitch(tester, const ValueKey('notif-health'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('notification-error')), findsOneWidget);
    var switchWidget = tester.widget<CupertinoSwitch>(
      find.descendant(
        of: find.byKey(const ValueKey('notif-health')),
        matching: find.byType(CupertinoSwitch),
      ),
    );
    expect(switchWidget.value, isTrue);
    fail = false;
    await tapSwitch(tester, const ValueKey('notif-health'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    switchWidget = tester.widget<CupertinoSwitch>(
      find.descendant(
        of: find.byKey(const ValueKey('notif-health')),
        matching: find.byType(CupertinoSwitch),
      ),
    );
    expect(switchWidget.value, isFalse);
    expect(persisted, [false, false]);
    expect(find.byKey(const ValueKey('notification-error')), findsNothing);
    final stored = await NotificationPrefs.load();
    expect(stored.healthEnabled, isFalse);
  });

  testWidgets('queued edit after apply failure is persisted', (tester) async {
    final applyGate = Completer<void>();
    final saved = <NotificationPrefs>[];
    var refresh = 0;
    await pumpHost(
      tester,
      loadPrefs: () async => const NotificationPrefs(),
      persistPrefs: (prefs) async => saved.add(prefs),
      onRefreshReminders: () async {
        refresh++;
        if (refresh == 1) {
          await applyGate.future;
          throw Exception('schedule failed');
        }
        throw Exception('schedule failed');
      },
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('notif-health')),
        matching: find.byType(CupertinoSwitch),
      ),
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('notif-device')),
        matching: find.byType(CupertinoSwitch),
      ),
    );
    await tester.pump();
    expect(saved, isNotEmpty);
    applyGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(saved.last.healthEnabled, isFalse);
    expect(saved.last.deviceEnabled, isFalse);
    expect(
      find.byKey(const ValueKey('notification-apply-error')),
      findsOneWidget,
    );
    expect(find.text('Gespeichert. Anwenden fehlgeschlagen'), findsOneWidget);
    expect(find.textContaining('schedule failed'), findsNothing);
    await tester.tap(find.text('Erneut'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(refresh, 3);
  });

  testWidgets('same-frame edits plus failed apply then retry', (tester) async {
    final persistGate = Completer<void>();
    final saved = <NotificationPrefs>[];
    var refresh = 0;
    await pumpHost(
      tester,
      loadPrefs: () async => const NotificationPrefs(),
      persistPrefs: (prefs) async {
        saved.add(prefs);
        if (saved.length == 1) await persistGate.future;
      },
      onRefreshReminders: () async {
        refresh++;
        throw Exception('schedule failed');
      },
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('notif-health')),
        matching: find.byType(CupertinoSwitch),
      ),
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('notif-device')),
        matching: find.byType(CupertinoSwitch),
      ),
    );
    await tester.pump();
    persistGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(saved.last.healthEnabled, isFalse);
    expect(saved.last.deviceEnabled, isFalse);
    expect(
      find.byKey(const ValueKey('notification-apply-error')),
      findsOneWidget,
    );
    expect(find.text('Gespeichert. Anwenden fehlgeschlagen'), findsOneWidget);
    expect(find.textContaining('schedule failed'), findsNothing);
    final beforeRetry = refresh;
    await tester.tap(find.text('Erneut'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(refresh, greaterThan(beforeRetry));
    expect(saved.last.healthEnabled, isFalse);
    expect(saved.last.deviceEnabled, isFalse);
  });

  testWidgets('service probe throw is unknown, not denied', (tester) async {
    final svc = NotificationService.instance;
    svc.invalidatePermissionCache();
    svc.debugProbePermission = () async {
      throw Exception('plugin failed');
    };
    addTearDown(() {
      svc.debugProbePermission = null;
      svc.debugRequestPermission = null;
      svc.invalidatePermissionCache();
    });
    await pumpHost(
      tester,
      loadPrefs: () async => const NotificationPrefs(),
      useServicePermission: true,
    );
    expect(find.text('Auffällige Werte'), findsOneWidget);
    expect(find.text('Mitteilungen nicht erlaubt'), findsNothing);
    expect(find.byKey(const ValueKey('notification-denied')), findsNothing);
    expect(
      find.byKey(const ValueKey('notification-permission-error')),
      findsOneWidget,
    );
    expect(find.text('Mitteilungen-Status unbekannt'), findsOneWidget);
    expect(find.textContaining('plugin failed'), findsNothing);
  });

  testWidgets('service null OS response is unknown, not denied', (
    tester,
  ) async {
    final svc = NotificationService.instance;
    svc.invalidatePermissionCache();
    svc.debugProbePermission = () async => null;
    addTearDown(() {
      svc.debugProbePermission = null;
      svc.invalidatePermissionCache();
    });
    await pumpHost(
      tester,
      loadPrefs: () async => const NotificationPrefs(),
      useServicePermission: true,
    );
    expect(find.text('Auffällige Werte'), findsOneWidget);
    expect(find.text('Mitteilungen nicht erlaubt'), findsNothing);
    expect(
      find.byKey(const ValueKey('notification-permission-error')),
      findsOneWidget,
    );
    expect(find.text('Mitteilungen-Status unbekannt'), findsOneWidget);
    expect(
      find.textContaining('notification permission unknown'),
      findsNothing,
    );
  });

  testWidgets('stale permission request cannot overwrite a newer resume', (
    tester,
  ) async {
    final allowRequest = Completer<bool>();
    final resumeProbe = Completer<bool>();
    var reads = 0;
    await pumpHost(
      tester,
      loadPrefs: () async => const NotificationPrefs(),
      readPermission: () async {
        reads++;
        if (reads == 1) return false;
        return resumeProbe.future;
      },
      requestPermission: () => allowRequest.future,
      openSystemSettings: () async {},
    );
    expect(find.text('Mitteilungen nicht erlaubt'), findsOneWidget);
    await tester.tap(find.text('Erlauben'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    resumeProbe.complete(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    allowRequest.complete(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Mitteilungen nicht erlaubt'), findsNothing);
    expect(find.byKey(const ValueKey('notification-denied')), findsNothing);
    expect(
      find.byKey(const ValueKey('notification-permission-error')),
      findsNothing,
    );
  });

  testWidgets(
    'request grant is not dropped when a denied resume invalidated generation',
    (tester) async {
      final allowRequest = Completer<bool>();
      addTearDown(() {
        if (!allowRequest.isCompleted) allowRequest.complete(false);
      });
      var granted = false;
      final applied = <NotificationPrefs>[];
      var reminders = 0;
      await pumpHost(
        tester,
        loadPrefs: () async =>
            const NotificationPrefs(waterEnabled: true, remindersEnabled: true),
        readPermission: () async => granted,
        requestPermission: () => allowRequest.future,
        openSystemSettings: () async {},
        onRefreshReminders: () async => reminders++,
        onArmWater: (prefs) async => applied.add(prefs),
        onRefreshBattery: (prefs) async => applied.add(prefs),
      );
      expect(find.text('Mitteilungen nicht erlaubt'), findsOneWidget);
      expect(reminders, 0);
      await tester.tap(find.text('Erlauben'));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Mitteilungen nicht erlaubt'), findsOneWidget);
      expect(reminders, 0);
      granted = true;
      allowRequest.complete(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Mitteilungen nicht erlaubt'), findsNothing);
      expect(find.byKey(const ValueKey('notification-denied')), findsNothing);
      expect(reminders, 1);
      expect(applied, isNotEmpty);
      expect(applied.last.remindersEnabled, isTrue);
    },
  );

  testWidgets('held reread cannot overwrite a newer resume observation', (
    tester,
  ) async {
    Future<void> resume() async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    }

    Future<void> race({
      required Object stale,
      required bool newer,
      required bool expectDenied,
      bool expectUnknown = false,
    }) async {
      final allowRequest = Completer<bool>();
      final reread = Completer<bool>();
      addTearDown(() {
        if (!allowRequest.isCompleted) allowRequest.complete(false);
        if (!reread.isCompleted) {
          if (stale is bool) {
            reread.complete(stale);
          } else {
            reread.completeError(stale);
          }
        }
      });
      var reads = 0;
      await pumpHost(
        tester,
        loadPrefs: () async => const NotificationPrefs(),
        readPermission: () async {
          reads++;
          if (reads == 1 || reads == 2) return false;
          if (reads == 3) return reread.future;
          return newer;
        },
        requestPermission: () => allowRequest.future,
        openSystemSettings: () async {},
      );
      expect(find.text('Mitteilungen nicht erlaubt'), findsOneWidget);
      await tester.tap(find.text('Erlauben'));
      await tester.pump();
      await resume();
      await tester.pump(const Duration(milliseconds: 50));
      allowRequest.complete(true);
      await tester.pump();
      expect(reads, 3);
      await resume();
      await tester.pump(const Duration(milliseconds: 50));
      if (stale is bool) {
        reread.complete(stale);
      } else {
        reread.completeError(stale);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      if (expectDenied) {
        expect(find.text('Mitteilungen nicht erlaubt'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('notification-denied')),
          findsOneWidget,
        );
      } else {
        expect(find.text('Mitteilungen nicht erlaubt'), findsNothing);
        expect(find.byKey(const ValueKey('notification-denied')), findsNothing);
      }
      expect(
        find.byKey(const ValueKey('notification-permission-error')),
        expectUnknown ? findsOneWidget : findsNothing,
      );
    }

    await race(stale: false, newer: true, expectDenied: false);
    await race(
      stale: Exception('stale probe failed'),
      newer: true,
      expectDenied: false,
    );
    await race(stale: true, newer: false, expectDenied: true);
  });

  testWidgets('saved quiet wrap midnight retains actual semantics', (
    tester,
  ) async {
    NotificationPrefs? wrapSaved;
    await pumpHost(
      tester,
      loadPrefs: () async => const NotificationPrefs(
        quietEnabled: true,
        quietStartMin: 22 * 60,
        quietEndMin: 7 * 60,
      ),
      persistPrefs: (prefs) async => wrapSaved = prefs,
    );
    expect(find.text('22:00'), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);
    await tapSwitch(tester, const ValueKey('notif-health'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(wrapSaved, isNotNull);
    expect(wrapSaved!.quietStartMin, 22 * 60);
    expect(wrapSaved!.quietEndMin, 7 * 60);
    expect(wrapSaved!.inQuietHours(23 * 60), isTrue);
    expect(wrapSaved!.inQuietHours(2 * 60), isTrue);
    expect(wrapSaved!.inQuietHours(7 * 60), isFalse);
  });

  testWidgets('saved quiet start=end retains empty-window semantics', (
    tester,
  ) async {
    NotificationPrefs? equalSaved;
    await pumpHost(
      tester,
      loadPrefs: () async => const NotificationPrefs(
        quietEnabled: true,
        quietStartMin: 8 * 60,
        quietEndMin: 8 * 60,
      ),
      persistPrefs: (prefs) async => equalSaved = prefs,
    );
    expect(find.text('08:00'), findsNWidgets(2));
    await tapSwitch(tester, const ValueKey('notif-health'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(equalSaved, isNotNull);
    expect(equalSaved!.quietStartMin, 8 * 60);
    expect(equalSaved!.quietEndMin, 8 * 60);
    expect(equalSaved!.inQuietHours(8 * 60), isFalse);
    expect(equalSaved!.inQuietHours(0), isFalse);
  });

  testWidgets('plugin cancel failure reaches settings apply error', (
    tester,
  ) async {
    final svc = NotificationService.instance;
    svc.debugCancel = (_) async {
      throw Exception('plugin cancel failed');
    };
    addTearDown(() {
      svc.debugCancel = null;
      svc.invalidatePermissionCache();
    });
    NotificationPrefs? saved;
    await pumpHost(
      tester,
      loadPrefs: () async => const NotificationPrefs(),
      persistPrefs: (prefs) async => saved = prefs,
      onRefreshReminders: () => svc.reportingScheduleFailures(
        () => svc.cancel(NotificationService.idWeeklyRecap),
      ),
    );
    await tapSwitch(tester, const ValueKey('notif-health'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(saved?.healthEnabled, isFalse);
    expect(
      find.textContaining('Gespeichert. Anwenden fehlgeschlagen'),
      findsOneWidget,
    );
    expect(find.textContaining('plugin cancel failed'), findsNothing);
    expect(
      find.byKey(const ValueKey('notification-apply-error')),
      findsOneWidget,
    );
  });

  testWidgets('Paper notification frames', (tester) async {
    Future<void> pumpPaper({
      Brightness brightness = Brightness.light,
      bool? granted = true,
    }) {
      return pumpView(
        tester,
        prefs: openBandPaperNotificationPrefs,
        granted: granted,
        synthetic: true,
        onChanged: (_) async {},
        onRequestPermission: granted == false ? () {} : null,
        brightness: brightness,
        height: 1400,
      );
    }

    await pumpPaper();
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/notifications-light.png'),
    );
    await pumpPaper(brightness: Brightness.dark);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/notifications-dark.png'),
    );
    await pumpPaper(granted: false);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/notifications-denied.png'),
    );

    Future<void> pumpChoice({Brightness brightness = Brightness.light}) async {
      await pumpView(
        tester,
        prefs: openBandPaperNotificationPrefs,
        synthetic: true,
        onChanged: (_) async {},
        brightness: brightness,
        height: 852,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('notif-battery')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('notif-battery')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('notification-choice')), findsOneWidget);
    }

    await pumpChoice();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/notifications-choice.png'),
    );
    await pumpChoice(brightness: Brightness.dark);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/notifications-choice-dark.png'),
    );
  });
}
