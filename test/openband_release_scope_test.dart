import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/app.dart';
import 'package:openstrap_edge/data/auto_backup.dart';
import 'package:openstrap_edge/notify/fired_keys.dart';
import 'package:openstrap_edge/notify/notification_center.dart';
import 'package:openstrap_edge/notify/notification_event.dart';
import 'package:openstrap_edge/notify/notification_prefs.dart';
import 'package:openstrap_edge/gestures/device_action.dart';
import 'package:openstrap_edge/gestures/gesture_dispatcher.dart';
import 'package:openstrap_edge/gestures/gesture_settings.dart';
import 'package:openstrap_edge/main_gallery.dart';
import 'package:openstrap_edge/notify/tap_router.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/health.dart';
import 'package:openstrap_edge/openband/release_scope.dart';
import 'package:openstrap_edge/openband/screens.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/profile/alarm.dart';
import 'package:openstrap_edge/ui2/profile/data.dart';
import 'package:openstrap_edge/ui2/profile/gestures.dart';
import 'package:openstrap_edge/ui2/profile/profile.dart';
import 'package:openstrap_edge/ui2/profile/settings.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _BackupWriteStore extends SharedPreferencesStorePlatform {
  _BackupWriteStore(this.inner, {required this.throwOnWrite});

  final SharedPreferencesStorePlatform inner;
  final bool throwOnWrite;

  @override
  Future<bool> clear() => inner.clear();
  @override
  Future<Map<String, Object>> getAll() => inner.getAll();
  @override
  Future<bool> remove(String key) => inner.remove(key);
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (throwOnWrite) throw StateError('storage unavailable');
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('de_DE');
  });

  test('the release switch defaults to the reduced surface', () {
    expect(kOpenBandReleaseReduced, isTrue);
  });

  test('a saved training or journal tab stays stored and opens home', () async {
    SharedPreferences.setMockInitialValues({kOpenBandTabPref: 'workout'});
    Prefs.debugReset();
    await Prefs.ensureLoaded();
    expect(
      shellDomainForRestore(reduced: true, savedName: 'workout', legacyTab: 0),
      ShellDomain.home,
    );
    expect(
      shellDomainForRestore(reduced: true, savedName: '', legacyTab: 4),
      ShellDomain.home,
    );
    expect(
      shellDomainForRestore(
        reduced: false,
        savedName: 'wellness',
        legacyTab: 0,
      ),
      ShellDomain.wellness,
    );
    persistOpenBandTab(reduced: true, name: 'home');
    expect(Prefs.getString(kOpenBandTabPref, ''), 'workout');
    persistOpenBandTab(reduced: false, name: 'home');
    expect(Prefs.getString(kOpenBandTabPref, ''), 'home');
  });

  test('parked routes and old tabs stay home; profile and alarm stay', () {
    expect(
      releaseDomainForRoute(kRouteJournalCompose, reduced: true),
      ShellDomain.home,
    );
    expect(releaseScreenForRoute(kRouteJournalCompose, reduced: true), isNull);
    expect(releaseScreenForRoute(kRouteWater, reduced: true), isNull);
    expect(
      releaseScreenForRoute(kRouteWorkoutSuggestion, reduced: true),
      isNull,
    );
    expect(releaseScreenForRoute(kRouteRecap, reduced: true), isNull);
    expect(releaseScreenForRoute('/nope', reduced: true), isNull);
    expect(releaseDomainForTab(4, reduced: true), ShellDomain.home);
    expect(releaseDomainForTab(1, reduced: true), ShellDomain.home);
    expect(
      releaseScreenForRoute(kRouteProfile, reduced: true),
      isA<ProfileHome>(),
    );
    expect(
      releaseScreenForRoute(kRouteAlarm, reduced: true),
      isA<AlarmScreen>(),
    );
    expect(
      releaseDomainForRoute(kRouteMovement, reduced: true),
      ShellDomain.home,
    );
    expect(openBandReleaseKeepsRoute('/today'), isTrue);
    expect(openBandReleaseKeepsRoute('/heart'), isTrue);
    expect(openBandReleaseKeepsRoute('$kRouteWorkoutIdle?id=w1'), isTrue);
    expect(openBandReleaseKeepsRoute(kRouteWorkoutSuggestion), isFalse);
    expect(openBandReleaseParksRoute('/today', reduced: true), isFalse);
    expect(openBandReleaseParksRoute('/heart', reduced: true), isFalse);
    expect(
      openBandReleaseParksRoute(kRouteWorkoutIdle, reduced: true),
      isFalse,
    );
    expect(
      openBandReleaseParksRoute(
        workoutSuggestionRoute('2026-09-15:1750000000'),
        reduced: true,
      ),
      isTrue,
    );
    expect(releaseDomainForRoute('/today', reduced: true), ShellDomain.home);
    expect(releaseDomainForRoute('/heart', reduced: true), ShellDomain.home);
    expect(
      releaseDomainForRoute(kRouteWorkoutIdle, reduced: true),
      ShellDomain.home,
    );
    expect(
      releaseDomainForRoute(kRouteProfile, reduced: true),
      ShellDomain.home,
    );
    expect(releaseScreenForRoute('/today', reduced: true), isNull);
    expect(releaseScreenForRoute('/heart', reduced: true), isNull);
    expect(releaseScreenForRoute(kRouteWorkoutIdle, reduced: true), isNull);
    expect(
      releaseScreenForRoute(kRouteJournalCompose, reduced: false),
      isNotNull,
    );
    expect(
      releaseDomainForRoute(kRouteWorkoutIdle, reduced: false),
      ShellDomain.workout,
    );
    expect(
      releaseDomainForRoute(kRouteJournalCompose, reduced: false),
      ShellDomain.wellness,
    );
    expect(releaseDomainForTab(4, reduced: false), ShellDomain.workout);
  });

  test('a parked gesture does not run and does not rewrite the saved id', () {
    final settings = GestureSettings()..doubleTap = DeviceAction.logWater;
    var water = 0;
    var workouts = 0;
    final logs = <String>[];
    final parked = GestureDispatcher(
      settings: settings,
      log: logs.add,
      onLogWater: () async => water++,
      onWorkoutToggle: () async => workouts++,
      releaseReduced: true,
    );
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    parked.onEvent(14, now, '');
    expect(water, 0);
    expect(workouts, 0);
    expect(settings.doubleTap, DeviceAction.logWater);
    expect(logs.single, contains('inactive'));

    final open = GestureDispatcher(
      settings: settings,
      onLogWater: () async => water++,
      releaseReduced: false,
    );
    open.onEvent(14, now, '');
    expect(water, 1);
  });

  test('a native gesture still runs when the release is reduced', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('openstrap/device_actions'),
          (call) async => call.method == 'perform',
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('openstrap/device_actions'),
            null,
          ),
    );
    final settings = GestureSettings()..doubleTap = DeviceAction.ringPhone;
    final logs = <String>[];
    GestureDispatcher(
      settings: settings,
      log: logs.add,
      releaseReduced: true,
    ).onEvent(14, DateTime.now().millisecondsSinceEpoch ~/ 1000, '');
    expect(settings.doubleTap, DeviceAction.ringPhone);
    expect(logs.single, contains(DeviceAction.ringPhone.id));
    await Future<void>.delayed(Duration.zero);
  });

  testWidgets('saved parked gesture stays visible and cannot be chosen again', (
    tester,
  ) async {
    DeviceAction chosen = DeviceAction.logWater;
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: BandGesturesView(
          chosen: chosen,
          supported: {
            DeviceAction.none,
            DeviceAction.logWater,
            DeviceAction.workoutToggle,
            DeviceAction.markMoment,
            DeviceAction.ringPhone,
          },
          releaseReduced: true,
          onPick: (action) => chosen = action,
        ),
      ),
    );
    expect(find.text('Log water'), findsOneWidget);
    expect(
      find.text('Saved. It does nothing in this version.'),
      findsOneWidget,
    );
    expect(find.text('Start / stop workout'), findsNothing);
    expect(find.text('Mark a moment'), findsNothing);
    expect(find.text('Ring my phone'), findsOneWidget);
    await tester.tap(find.text('Log water'));
    await tester.pump();
    expect(chosen, DeviceAction.logWater);
    await tester.tap(find.text('Ring my phone'));
    await tester.pump();
    expect(chosen, DeviceAction.ringPhone);
  });

  testWidgets('reduced shell has no bottom nav and keeps a finish control', (
    tester,
  ) async {
    final key = GlobalKey<AppShellState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: AppShell(
          key: key,
          initial: ShellDomain.workout,
          domains: kOpenBandReleaseDomains,
          banner: const Text('Session beenden'),
          builder: (_, domain) => Text(domain.name),
        ),
      ),
    );
    expect(find.text('home'), findsOneWidget);
    expect(find.text('Training'), findsNothing);
    expect(find.text('Journal'), findsNothing);
    expect(find.text('Session beenden'), findsOneWidget);
    key.currentState!.open(ShellDomain.workout, const Text('Training starten'));
    await tester.pump();
    expect(find.text('Training starten'), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('stored stage minutes are the only night summary', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: const OBStageLegend(
          night: SleepNight(deepMinutes: 68),
          onlyStored: true,
        ),
      ),
    );
    expect(find.text('Tief'), findsOneWidget);
    expect(find.text('REM'), findsNothing);
    expect(find.text('Leicht'), findsNothing);
    expect(find.text('Wach'), findsNothing);
    expect(find.text('Im Bett'), findsNothing);
  });

  void phone(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.reset);
  }

  testWidgets('reduced Messwerte is the four stored cards', (tester) async {
    final repo = _repo()..scenario = SyntheticScenario.complete;
    final controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-15',
      band: repo.band,
      now: () => DateTime(2026, 9, 18, 9, 41),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    phone(tester);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(Brightness.light),
        home: Scaffold(
          body: OpenBandHealth(controller: controller, bandMetricsOnly: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Messwerte'), findsOneWidget);
    expect(find.text('HRV'), findsOneWidget);
    expect(find.text('Ruhepuls'), findsOneWidget);
    expect(find.text('Atemfrequenz'), findsOneWidget);
    expect(find.text('Hauttemperatur'), findsOneWidget);
    expect(find.text('7 Nächte'), findsNothing);
    expect(find.text('Laborwerte'), findsNothing);
    expect(find.text('Glukose'), findsNothing);
    expect(find.text('Gewicht'), findsNothing);
  });

  testWidgets('reduced overview hides parked actions and opens Messwerte', (
    tester,
  ) async {
    final repo = _repo();
    final controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-15',
      band: repo.band,
      now: () => DateTime(2026, 9, 18, 9, 41),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    phone(tester);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(Brightness.light),
        home: AppShell(
          domains: kOpenBandReleaseDomains,
          builder: (_, _) => OpenBandOverview(
            controller: controller,
            reduced: true,
            onJournal: () {},
            onTraining: () {},
            onNutrition: () {},
            onSync: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dein Journal'), findsNothing);
    expect(find.text('Training'), findsNothing);
    expect(find.text('Wasser'), findsNothing);
    expect(find.text('Energie'), findsNothing);
    expect(find.text('DEINE NACHT'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Alle Messwerte'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Alle Messwerte'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('SCHRITTE'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('SCHRITTE'), findsOneWidget);
    expect(find.text('Wasser'), findsNothing);
    final messwerte = tester.getRect(
      find.byKey(const ValueKey('alle-messwerte')),
    );
    final steps = tester.getRect(find.text('SCHRITTE'));
    expect(steps.top, greaterThanOrEqualTo(messwerte.bottom + 12));
    await tester.tap(find.byKey(const ValueKey('alle-messwerte')));
    await tester.pumpAndSettle();
    expect(find.text('Messwerte'), findsOneWidget);
    expect(find.text('7 Nächte'), findsNothing);
    expect(find.byTooltip('Zurück'), findsOneWidget);
  });

  testWidgets('reduced overview at large text stays on the release surface', (
    tester,
  ) async {
    phone(tester);
    final repo = _repo();
    final controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-15',
      band: repo.band,
      now: () => DateTime(2026, 9, 18, 9, 41),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: AppShell(
          domains: kOpenBandReleaseDomains,
          builder: (_, _) => OpenBandOverview(
            controller: controller,
            reduced: true,
            onSync: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Alle Messwerte'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Alle Messwerte'), findsOneWidget);
    expect(find.text('Wasser'), findsNothing);
    expect(find.text('Training'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a missing night does not invent stage totals', (tester) async {
    final repo = _repo()..scenario = SyntheticScenario.missing;
    final controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-15',
      band: repo.band,
      now: () => DateTime(2026, 9, 18, 9, 41),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    phone(tester);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(Brightness.light),
        home: Scaffold(
          body: OpenBandOverview(controller: controller, reduced: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tief'), findsNothing);
    expect(find.text('REM'), findsNothing);
    expect(find.text('Alle Messwerte'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced Profile is the compact production composition', (
    tester,
  ) async {
    phone(tester);
    var edit = 0, devices = 0, data = 0, settings = 0, language = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        supportedLocales: const [Locale('de')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: openBandTheme(Brightness.light),
        home: ProfileHomeView(
          releaseReduced: true,
          stats: const ProfileStats(
            name: 'Mats',
            sources: 1,
            storageBytes: 4200000,
          ),
          user: const {
            'name': 'Mats',
            'birth_date': '1995-09-21',
            'height_cm': 182.0,
            'weight_kg': 78.4,
          },
          band: const BandSnapshot(
            connection: BandConnection.connected,
            batteryPercent: 64,
          ),
          bandName: 'WHOOP 5.0',
          languageLabel: 'Deutsch',
          onEdit: () => edit++,
          onDevices: () => devices++,
          onData: () => data++,
          onSettings: () => settings++,
          onLanguage: () => language++,
        ),
      ),
    );
    expect(find.byKey(const ValueKey('profile-screen')), findsOneWidget);
    expect(find.text('Profil'), findsOneWidget);
    expect(find.text('Daten & Sicherung'), findsOneWidget);
    expect(find.text('Einstellungen'), findsOneWidget);
    expect(find.text('Sprache'), findsOneWidget);
    expect(find.text('Meine Geräte'), findsNothing);
    expect(find.text('Community'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('profile-identity')));
    await tester.tap(find.byKey(const ValueKey('profile-band')));
    await tester.tap(find.byKey(const ValueKey('profile-data')));
    await tester.tap(find.byKey(const ValueKey('profile-settings')));
    await tester.tap(find.byKey(const ValueKey('profile-language')));
    expect((edit, devices, data, settings, language), (1, 1, 1, 1, 1));
  });

  testWidgets('large text stacks complete band facts into aligned rows', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        supportedLocales: const [Locale('de')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: openBandTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: ProfileHomeView(
          releaseReduced: true,
          stats: const ProfileStats(storageBytes: 4509715661),
          band: BandSnapshot(
            connection: BandConnection.connected,
            batteryPercent: 64,
            latestStoredAt: DateTime(2026, 9, 18, 7, 42),
          ),
          bandName: 'WHOOP 5.0',
          languageLabel: 'Deutsch',
        ),
      ),
    );

    final values = [find.text('07:42'), find.text('—'), find.text('4,2 GB')];
    final labels = [
      find.text('Datenstand'),
      find.text('Gespeichert'),
      find.text('Archiv'),
    ];
    for (var i = 0; i < values.length; i++) {
      expect(values[i], findsOneWidget);
      expect(labels[i], findsOneWidget);
      final value = tester.getRect(values[i]);
      final label = tester.getRect(labels[i]);
      expect(value.left, lessThan(label.left));
      if (i > 0) {
        expect(value.top, greaterThan(tester.getRect(values[i - 1]).top));
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed band observation is not presented as no band', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        supportedLocales: const [Locale('de')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: openBandTheme(Brightness.light),
        home: const ProfileHomeView(
          releaseReduced: true,
          stats: ProfileStats(bandReadFailed: true),
          languageLabel: 'Deutsch',
        ),
      ),
    );
    expect(find.textContaining('Bandstatus nicht verfügbar'), findsOneWidget);
    expect(find.text('Kein Band verbunden'), findsNothing);
  });

  testWidgets(
    'failed band refresh retains observations without saying connected',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          supportedLocales: const [Locale('de')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: openBandTheme(Brightness.light),
          home: ProfileHomeView(
            releaseReduced: true,
            stats: const ProfileStats(
              storageBytes: 4200000,
              bandReadFailed: true,
            ),
            band: BandSnapshot(
              connection: BandConnection.connected,
              batteryPercent: 64,
              latestStoredAt: DateTime(2026, 9, 18, 7, 42),
            ),
            bandName: 'WHOOP 5.0',
            languageLabel: 'Deutsch',
          ),
        ),
      );

      expect(find.text('Bandstatus nicht verfügbar'), findsOneWidget);
      expect(find.text('Verbunden'), findsNothing);
      expect(find.text('64'), findsOneWidget);
      expect(find.text('07:42'), findsOneWidget);
    },
  );

  testWidgets('reduced Data exposes only retained actions and receipts', (
    tester,
  ) async {
    phone(tester);
    var hits = 0;
    void hit() => hits++;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        supportedLocales: const [Locale('de')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: openBandTheme(Brightness.light),
        home: DataScreenView(
          cadence: BackupCadence.weekly,
          note: 'Export erstellt',
          onExportDatabase: hit,
          onExportEncrypted: hit,
          onExportCsv: hit,
          onCadence: hit,
          onBackupNow: hit,
          onImport: hit,
          onReanalyze: hit,
        ),
      ),
    );
    expect(find.byKey(const ValueKey('data-screen')), findsOneWidget);
    expect(find.text('Wöchentlich'), findsOneWidget);
    expect(find.text('Von eurem Telefon'), findsNothing);
    expect(find.byKey(const ValueKey('data-action-receipt')), findsOneWidget);
    for (final key in const [
      'data-export-database',
      'data-export-encrypted',
      'data-export-csv',
      'data-backup-cadence',
      'data-backup-now',
      'data-import-file',
      'data-reanalyze',
    ]) {
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pump();
    }
    expect(hits, 7);
    expect(tester.takeException(), isNull);
  });

  test(
    'backup cadence reports unavailable persistence and keeps prior choice',
    () async {
      Prefs.debugReset();
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await expectLater(
        app.setBackupCadence(BackupCadence.daily),
        throwsA(isA<StateError>()),
      );
      expect(app.backupCadence, BackupCadence.off);
      SharedPreferences.setMockInitialValues({});
      Prefs.debugReset();
      await Prefs.ensureLoaded();
    },
  );

  for (final throwOnWrite in [false, true]) {
    test(
      'refused cadence ${throwOnWrite ? 'throw' : 'false'} restores cache and skips backup',
      () async {
        SharedPreferences.setMockInitialValues({
          Prefs.backupCadence: BackupCadence.weekly.name,
        });
        Prefs.debugReset();
        await Prefs.ensureLoaded();
        final platform = SharedPreferencesStorePlatform.instance;
        SharedPreferencesStorePlatform.instance = _BackupWriteStore(
          platform,
          throwOnWrite: throwOnWrite,
        );
        addTearDown(() => SharedPreferencesStorePlatform.instance = platform);
        final app = AppState.forTesting();
        addTearDown(app.dispose);
        var attempts = 0;
        app.debugRunBackupNow = () async {
          attempts++;
          return const BackupOutcome(path: '/must-not-run');
        };

        await expectLater(
          app.setBackupCadence(BackupCadence.daily),
          throwsA(isA<StateError>()),
        );

        expect(app.backupCadence, BackupCadence.weekly);
        expect(
          (await SharedPreferences.getInstance()).getString(
            Prefs.backupCadence,
          ),
          BackupCadence.weekly.name,
        );
        expect(attempts, 0);
      },
    );
  }

  test(
    'saved cadence survives an immediate backup failure and reports it once',
    () async {
      SharedPreferences.setMockInitialValues({Prefs.backupCadence: 'off'});
      Prefs.debugReset();
      await Prefs.ensureLoaded();
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      var attempts = 0;
      app.debugRunBackupNow = () async {
        attempts++;
        return const BackupOutcome(error: 'disk full');
      };

      final outcome = await app.setBackupCadence(BackupCadence.daily);

      expect(attempts, 1);
      expect(app.backupCadence, BackupCadence.daily);
      expect(outcome?.error, 'disk full');
    },
  );

  test('successful cadence change exposes the created backup', () async {
    SharedPreferences.setMockInitialValues({Prefs.backupCadence: 'off'});
    Prefs.debugReset();
    await Prefs.ensureLoaded();
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    var attempts = 0;
    app.debugRunBackupNow = () async {
      attempts++;
      return const BackupOutcome(path: '/synthetic/backup.db.gz');
    };

    final outcome = await app.setBackupCadence(BackupCadence.weekly);

    expect(attempts, 1);
    expect(app.backupCadence, BackupCadence.weekly);
    expect(outcome?.path, '/synthetic/backup.db.gz');
    expect(app.lastBackupAt, isNotNull);
  });

  testWidgets('settings hides cycle and the component gallery', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        theme: buildTheme(Brightness.light),
        home: const MoreSettingsView(
          version: '0.9.31 (67)',
          devMode: true,
          releaseReduced: true,
        ),
      ),
    );
    expect(find.text('Cycle'), findsNothing);
    expect(find.text('Component gallery'), findsNothing);
    expect(find.text('Look barcodes up online'), findsNothing);
    expect(find.text('Alarm'), findsOneWidget);
    expect(find.text('Export, backup, import'), findsOneWidget);
  });

  testWidgets('notification settings do not offer parked flows', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(Brightness.light),
        home: const NotificationSettingsView(releaseReduced: true),
      ),
    );
    expect(find.byKey(const ValueKey('notif-winddown')), findsNothing);
    expect(find.byKey(const ValueKey('notif-water')), findsNothing);
    expect(find.byKey(const ValueKey('notif-meds')), findsNothing);
    expect(find.byKey(const ValueKey('notif-checkin')), findsNothing);
    expect(find.byKey(const ValueKey('notif-weekly')), findsNothing);
    expect(find.byKey(const ValueKey('notif-autodetect')), findsNothing);
    expect(find.byKey(const ValueKey('notif-steps')), findsOneWidget);
    expect(find.byKey(const ValueKey('notif-recovery')), findsOneWidget);
    expect(find.byKey(const ValueKey('notif-alarm-latch')), findsOneWidget);
  });

  testWidgets('reduced gallery opens Profile and deterministic Data receipts', (
    tester,
  ) async {
    phone(tester);
    final repository = (await tester.runAsync(loadGalleryRepository))!;
    await tester.pumpWidget(
      OpenBandGallery(
        repository: repository,
        showControls: false,
        releaseReduced: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Profil'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-screen')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('profile-data')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('data-screen')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('data-export-database')));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('data-action-receipt')),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      find.text(
        'Export konnte nicht erstellt werden: synthetischer Schreibfehler.',
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('data-export-database')),
    );
    await tester.tap(find.byKey(const ValueKey('data-export-database')));
    await tester.pump();
    expect(find.text('Export erstellt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the synthetic gallery keeps four tabs until release is asked', (
    tester,
  ) async {
    phone(tester);
    final repository = (await tester.runAsync(loadGalleryRepository))!;
    await tester.pumpWidget(
      OpenBandGallery(repository: repository, showControls: false),
    );
    await tester.pumpAndSettle();
    expect(find.text('Übersicht'), findsOneWidget);
    expect(find.text('Gesundheit'), findsOneWidget);
    expect(find.text('Training'), findsOneWidget);
    expect(find.text('Journal'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Wasser'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Wasser'), findsWidgets);

    await tester.pumpWidget(
      OpenBandGallery(
        repository: repository,
        showControls: false,
        releaseReduced: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Training'), findsNothing);
    expect(find.text('Journal'), findsNothing);
    expect(find.text('Wasser'), findsNothing);
    expect(find.text('Alle Messwerte'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('parked notification emits do not fire or claim the key', () async {
    SharedPreferences.setMockInitialValues({});
    await const NotificationPrefs(
      quietEnabled: false,
      recoveryEnabled: true,
      stepGoalEnabled: true,
      autoDetectEnabled: true,
    ).save();
    final center = NotificationCenter.instance;
    final previousReduced = center.releaseReduced;
    final previousSink = center.presentSink;
    final shown = <String>[];
    center.presentSink = (event, {bool allowPermissionPrompt = true}) async {
      shown.add(event.dedupeKey);
      return true;
    };
    addTearDown(() {
      center.releaseReduced = previousReduced;
      center.presentSink = previousSink;
    });
    center.releaseReduced = true;
    NotificationEvent event({
      required String key,
      required NotifCategory category,
      required String route,
      NotifPriority priority = NotifPriority.normal,
    }) => NotificationEvent(
      dedupeKey: key,
      category: category,
      priority: priority,
      title: key,
      body: 'b',
      date: '2026-09-15',
      route: route,
    );
    final workout = event(
      key: '2026-09-15:auto',
      category: NotifCategory.reminders,
      route: kRouteWorkoutSuggestion,
    );
    expect(await center.emit(workout), isFalse);
    expect(shown, isEmpty);
    expect(
      await center.emit(
        event(
          key: '2026-09-15:recovery',
          category: NotifCategory.recovery,
          route: kRouteRecovery,
        ),
      ),
      isTrue,
    );
    expect(
      await center.emit(
        event(
          key: '2026-09-15:steps',
          category: NotifCategory.reminders,
          route: kRouteSteps,
        ),
      ),
      isTrue,
    );
    expect(
      await center.emit(
        event(
          key: '2026-09-15:alarm',
          category: NotifCategory.reminders,
          route: kRouteAlarm,
          priority: NotifPriority.critical,
        ),
      ),
      isTrue,
    );
    center.releaseReduced = false;
    expect(await center.emit(workout), isTrue);
    expect(shown, [
      '2026-09-15:recovery',
      '2026-09-15:steps',
      '2026-09-15:alarm',
      '2026-09-15:auto',
    ]);
  });

  test(
    'kept reminder routes emit and a parked workout suggestion claims nothing',
    () async {
      SharedPreferences.setMockInitialValues({});
      await const NotificationPrefs(quietEnabled: false).save();
      final center = NotificationCenter.instance;
      final previousReduced = center.releaseReduced;
      final previousSink = center.presentSink;
      final shown = <String>[];
      center.presentSink = (event, {bool allowPermissionPrompt = true}) async {
        shown.add(event.dedupeKey);
        return true;
      };
      addTearDown(() {
        center.releaseReduced = previousReduced;
        center.presentSink = previousSink;
      });
      center.releaseReduced = true;
      const store = FiredKeyStore();
      const suggestionId = '2026-09-15:1750000000';
      const suggestionKey = '$suggestionId:auto_workout';
      final parked = NotificationEvent(
        dedupeKey: suggestionKey,
        category: NotifCategory.reminders,
        priority: NotifPriority.normal,
        title: 'Did you work out?',
        body: 'We spotted ~20 min of elevated activity. Tap to log it.',
        date: '2026-09-15',
        route: workoutSuggestionRoute(suggestionId),
      );
      expect(await center.emit(parked, allowPermissionPrompt: false), isFalse);
      expect(await store.hasFired(suggestionKey), isFalse);
      expect(shown, isEmpty);

      Future<bool> emitReal(NotificationEvent event) =>
          center.emit(event, allowPermissionPrompt: false);
      expect(
        await emitReal(
          const NotificationEvent(
            dedupeKey: 'alarm_fired:1750000000',
            category: NotifCategory.reminders,
            priority: NotifPriority.critical,
            title: 'Alarm',
            body: 'Your strap alarm just fired.',
            date: '2026-09-15',
            route: '/today',
          ),
        ),
        isTrue,
      );
      expect(
        await emitReal(
          const NotificationEvent(
            dedupeKey: '2026-09-15:sync_stale',
            category: NotifCategory.device,
            priority: NotifPriority.normal,
            title: "Your band hasn't synced in a while",
            body:
                'No new data for about 12 hours. Open OpenStrap to '
                'reconnect — background sync may have stalled.',
            date: '2026-09-15',
            route: '/today',
          ),
        ),
        isTrue,
      );
      expect(
        await emitReal(
          const NotificationEvent(
            dedupeKey: '2026-09-15:exception:medical',
            category: NotifCategory.health,
            priority: NotifPriority.critical,
            title: 'Something changed',
            body: 'A health exception needs a look.',
            date: '2026-09-15',
            route: '/heart',
          ),
        ),
        isTrue,
      );
      expect(
        await emitReal(
          const NotificationEvent(
            dedupeKey: 'w123:workout_idle',
            category: NotifCategory.reminders,
            priority: NotifPriority.normal,
            title: 'Still working out?',
            body:
                'Nothing above resting effort has been recorded. If the '
                'session is over, open the app to finish it.',
            date: '2026-09-15',
            route: kRouteWorkoutIdle,
          ),
        ),
        isTrue,
      );
      expect(await store.hasFired(suggestionKey), isFalse);
      expect(await store.hasFired('alarm_fired:1750000000'), isTrue);
      expect(await store.hasFired('2026-09-15:sync_stale'), isTrue);
      expect(await store.hasFired('2026-09-15:exception:medical'), isTrue);
      expect(await store.hasFired('w123:workout_idle'), isTrue);
      expect(shown, [
        'alarm_fired:1750000000',
        '2026-09-15:sync_stale',
        '2026-09-15:exception:medical',
        'w123:workout_idle',
      ]);
      expect(await center.emit(parked, allowPermissionPrompt: false), isFalse);
      expect(shown, hasLength(4));
    },
  );
}

SyntheticOpenBandRepository _repo() => SyntheticOpenBandRepository.fromMaps(
  jsonDecode(
        File(
          'docs/openband5/assets/fixtures/day-summary.json',
        ).readAsStringSync(),
      )
      as Map,
  jsonDecode(
        File(
          'docs/openband5/assets/fixtures/sleep-detail.json',
        ).readAsStringSync(),
      )
      as Map,
  activity:
      jsonDecode(
            File(
              'docs/openband5/assets/fixtures/additional-flows.json',
            ).readAsStringSync(),
          )
          as Map,
);
