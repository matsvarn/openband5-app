import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/ble/ble_state.dart'
    show BandCondition, BleBlocker, bandStatusFor;
import 'package:openstrap_edge/l10n/app_localizations.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/day_picker.dart';
import 'package:openstrap_edge/openband/g3/band_parts.dart';
import 'package:openstrap_edge/openband/g3/chrome.dart' show OBPanel;
import 'package:openstrap_edge/openband/g3/screens/band.dart';
import 'package:openstrap_edge/openband/g3/screens/band_restore.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/screens.dart'
    show bandStatusValuesHeading, showBandStatus;
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/data/auto_backup.dart';
import 'package:openstrap_edge/ui2/onboarding/welcome.dart' show ImportOutcome;
import 'package:openstrap_edge/ui2/profile/data.dart';
import 'package:openstrap_edge/ui2/profile/profile.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('de_DE');
    for (final (family, path) in [
      ('Inter', 'assets/fonts/Inter/Inter.ttf'),
      (
        'packages/lucide_icons_flutter/Lucide',
        'packages/lucide_icons_flutter/assets/lucide.ttf',
      ),
    ]) {
      final loader = FontLoader(family);
      loader.addFont(
        path.startsWith('assets/')
            ? Future.value(ByteData.sublistView(File(path).readAsBytesSync()))
            : rootBundle.load(path),
      );
      await loader.load();
    }
  });
  Future<void> pump(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        supportedLocales: const [Locale('de'), Locale('en')],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: openBandTheme(Brightness.light),
        home: screen,
      ),
    );
  }

  testWidgets('band facts refuse unavailable firmware, coverage and backlog', (
    tester,
  ) async {
    await pump(
      tester,
      G3BandScreen(
        band: const BandSnapshot(connection: BandConnection.connected),
        now: DateTime(2026, 9, 29, 9, 41),
      ),
    );
    expect(find.text('Abdeckung noch nicht erfasst'), findsOneWidget);
    expect(find.text('unbekannt'), findsOneWidget);
    expect(find.text('Firmware'), findsOneWidget);
    expect(find.text('0 Min.'), findsNothing);
    expect(find.textContaining('% übertragen'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'battery scale keeps a gutter before the backlog at mini widths',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
      addTearDown(tester.view.reset);
      for (final width in [375.0, 360.0]) {
        tester.view.physicalSize = Size(width, 812);
        await pump(
          tester,
          G3BandScreen(
            key: ValueKey(width),
            band: const BandSnapshot(
              connection: BandConnection.connected,
              batteryPercent: 64,
            ),
            now: DateTime(2026, 9, 29, 9, 41),
          ),
        );
        final scaleEnd = tester.getRect(find.text('100 %'));
        final batteryBar = tester.getRect(find.byType(LinearProgressIndicator));
        final backlog = tester.getRect(find.text('unbekannt'));
        expect(backlog.left - scaleEnd.right, greaterThanOrEqualTo(16));
        expect(backlog.left - batteryBar.right, greaterThanOrEqualTo(16));
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('stored frontier and distinct device name remain truthful', (
    tester,
  ) async {
    final band = BandSnapshot(
      connection: BandConnection.connected,
      latestStoredAt: DateTime(2026, 9, 29, 9, 38),
    );
    await pump(
      tester,
      G3BandScreen(
        band: band,
        deviceName: 'Band',
        now: DateTime(2026, 9, 29, 9, 37),
      ),
    );
    expect(find.text('auf dem iPhone gespeichert'), findsOneWidget);
    expect(find.text('Datenstand unbekannt'), findsNothing);
    expect(find.text('Band'), findsNothing);
    await pump(
      tester,
      G3BandScreen(
        band: band,
        deviceName: 'WHOOP 5.0',
        now: DateTime(2026, 9, 29, 9, 37),
      ),
    );
    expect(find.text('WHOOP 5.0'), findsOneWidget);
  });

  testWidgets('stored band diagnostics replace older card observations', (
    tester,
  ) async {
    final now = DateTime(2026, 9, 29, 9, 41);
    final diagnostics = BandDiagnostics(
      deviceFamily: 'gen5',
      lastStoredSampleAt: DateTime(2026, 9, 29, 9, 38),
      battery: BandBattery(
        observedAt: DateTime(2026, 9, 29, 9, 37),
        percent: 67,
      ),
      backlog: BandBacklog(
        observedAt: DateTime(2026, 9, 29, 9, 36),
        unreadPages: 3,
        heldPages: 5,
      ),
      coverage: BandCoverage(
        start: now.subtract(const Duration(hours: 24)),
        end: now,
        recordedSeconds: 2,
        coveragePercent: null,
        wristOffIntervals: [
          BandTimeInterval(
            DateTime(2026, 9, 29, 8),
            DateTime(2026, 9, 29, 8, 10),
          ),
        ],
      ),
    );
    await pump(
      tester,
      G3BandScreen(
        band: BandSnapshot(
          connection: BandConnection.connected,
          latestStoredAt: DateTime(2026, 9, 29, 8),
          batteryPercent: 20,
        ),
        now: now,
        diagnostics: diagnostics,
      ),
    );
    expect(find.text('09:38'), findsOneWidget);
    expect(find.textContaining('67'), findsWidgets);
    expect(find.textContaining('3'), findsWidgets);
    expect(find.textContaining('Seiten ungelesen'), findsOneWidget);
    expect(find.textContaining('2 Sek. aufgezeichnet'), findsOneWidget);
    expect(find.textContaining('1 beobachtete Ablegephase'), findsOneWidget);
    expect(find.text('gen5'), findsOneWidget);
    expect(find.text('WHOOP 5.0'), findsNothing);
    expect(find.text('Firmware'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
    expect(find.text('2 %'), findsNothing);
  });

  testWidgets(
    'exact model and firmware appear only when diagnostics store them',
    (tester) async {
      await pump(
        tester,
        G3BandScreen(
          band: const BandSnapshot(connection: BandConnection.connected),
          now: DateTime(2026, 9, 29, 9, 41),
          diagnostics: const BandDiagnostics(
            model: 'Stored model',
            firmwareVersion: 'Stored firmware',
          ),
        ),
      );
      expect(find.text('Stored model'), findsWidgets);
      expect(find.text('Stored firmware'), findsOneWidget);
    },
  );

  testWidgets('diagnostics read follows band updates', (tester) async {
    final updates = ValueNotifier<int>(0);
    addTearDown(updates.dispose);
    var percent = 40;
    await pump(
      tester,
      G3BandScreen(
        band: const BandSnapshot(connection: BandConnection.connected),
        now: DateTime(2026, 9, 29, 9, 41),
        bandUpdates: updates,
        readDiagnostics: () async => BandDiagnostics(
          battery: BandBattery(
            observedAt: DateTime(2026, 9, 29, 9, 40),
            percent: percent,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('40'), findsWidgets);
    percent = 67;
    updates.value++;
    await tester.pump();
    expect(find.textContaining('67'), findsWidgets);
  });

  testWidgets('profile summary uses stored sample and battery', (tester) async {
    await pump(
      tester,
      ProfileHomeView(
        releaseReduced: true,
        languageLabel: 'Deutsch',
        stats: const ProfileStats(),
        band: const BandSnapshot(connection: BandConnection.connected),
        diagnostics: BandDiagnostics(
          lastStoredSampleAt: DateTime(2026, 9, 29, 9, 38),
          battery: BandBattery(
            observedAt: DateTime(2026, 9, 29, 9, 37),
            percent: 67,
          ),
        ),
      ),
    );
    expect(find.text('09:38'), findsOneWidget);
    expect(find.text('67 %'), findsOneWidget);
  });

  testWidgets('profile dates a stored battery reading from yesterday', (
    tester,
  ) async {
    await pump(
      tester,
      ProfileHomeView(
        releaseReduced: true,
        languageLabel: 'Deutsch',
        stats: const ProfileStats(),
        band: const BandSnapshot(connection: BandConnection.disconnected),
        now: DateTime(2026, 9, 29, 9, 41),
        diagnostics: BandDiagnostics(
          battery: BandBattery(
            observedAt: DateTime(2026, 9, 28, 9, 37),
            percent: 67,
          ),
        ),
      ),
    );
    expect(find.text('zuletzt 67 % · gestern · 09:37'), findsOneWidget);
  });

  testWidgets('profile distinguishes denied from unknown notifications', (
    tester,
  ) async {
    var opened = 0;
    Widget profile(bool? allowed) => ProfileHomeView(
      releaseReduced: true,
      stats: ProfileStats(notificationsAllowed: allowed),
      languageLabel: 'Deutsch',
      onNotifications: () => opened++,
    );
    await pump(tester, profile(null));
    expect(find.text('Mitteilungen nicht erlaubt'), findsNothing);
    await pump(tester, profile(false));
    expect(find.text('Mitteilungen nicht erlaubt'), findsOneWidget);
    await tester.tap(find.text('Erlauben'));
    expect(opened, 1);
  });

  testWidgets(
    'interrupted transfer keeps the stored frontier and a real route',
    (tester) async {
      var opened = 0;
      await pump(
        tester,
        G3BandScreen(
          band: BandSnapshot(
            connection: BandConnection.disconnected,
            transfer: TransferState.interrupted,
            latestStoredAt: DateTime(2026, 9, 29, 9, 28),
          ),
          now: DateTime(2026, 9, 29, 9, 41),
          onReconnect: () async {
            opened++;
          },
        ),
      );
      expect(find.text('Übertragung unterbrochen'), findsOneWidget);
      expect(find.text('09:28'), findsOneWidget);
      expect(
        find.text('Bereits gespeicherte Abschnitte bleiben erhalten.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Verbinden'));
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('partial restore keeps accepted, skipped and rejected separate', (
    tester,
  ) async {
    var closed = 0;
    await pump(
      tester,
      Scaffold(
        body: G3RestoreReceiptSheet(
          outcome: const ImportOutcome(
            source: 'Sicherung',
            restoredRows: 12,
            unchangedRows: 3,
            restoreConflicts: 1,
            unreadableRows: 1,
          ),
          onClose: () => closed++,
        ),
      ),
    );
    expect(find.text('12'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('1'), findsNWidgets(3));
    expect(find.text('Nicht lesbar'), findsOneWidget);
    expect(find.text('abgelehnt, nichts geschätzt'), findsOneWidget);
    await tester.tap(find.text('Fertig'));
    expect(closed, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('last good backup keeps its local day during a failed backup', (
    tester,
  ) async {
    await pump(
      tester,
      DataScreenView(
        cadence: BackupCadence.daily,
        now: DateTime(2026, 9, 29, 9, 41),
        lastBackupAt: DateTime(2026, 9, 28, 3),
        note: 'Zu wenig freier Speicher auf dem iPhone.',
        noteFailed: true,
        backupFailed: true,
        onBackupNow: () {},
      ),
    );
    expect(find.text('03:00'), findsOneWidget);
    expect(find.textContaining('gestern'), findsWidgets);
    expect(find.textContaining('Zu wenig freier Speicher'), findsOneWidget);
    expect(
      find.textContaining('Die Sicherung von gestern 03:00 bleibt erhalten.'),
      findsOneWidget,
    );
    expect(find.text('Sicherung fehlgeschlagen'), findsOneWidget);
    expect(find.byKey(const ValueKey('data-backup-now')), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('data-last-backup'))).dy,
      lessThan(tester.getTopLeft(find.text('Sicherung fehlgeschlagen')).dy),
    );
  });

  testWidgets('backup hero does not infer whether the backup was automatic', (
    tester,
  ) async {
    for (final locale in [const Locale('de'), const Locale('en')]) {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: const [Locale('de'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: DataScreenView(
            cadence: BackupCadence.daily,
            now: DateTime(2026, 9, 29, 9, 41),
            lastBackupAt: DateTime(2026, 9, 28, 3),
            onBackupNow: () {},
          ),
        ),
      );
      expect(find.text('03:00'), findsOneWidget);
      expect(find.text('automatisch'), findsNothing);
      expect(find.text('automatic'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  for (final (outcome, title) in [
    (const ImportOutcome(source: 'Sicherung', restoredRows: 3), 'Übernommen'),
    (const ImportOutcome(source: 'Sicherung', unchangedRows: 3), 'Unverändert'),
    (
      const ImportOutcome(source: 'Sicherung', unreadableRows: 1),
      'Nicht übernommen',
    ),
    (
      const ImportOutcome(
        source: 'Sicherung',
        restoredRows: 3,
        restoreConflicts: 1,
      ),
      'Teilweise übernommen',
    ),
  ]) {
    testWidgets('restore title follows outcome: $title', (tester) async {
      await pump(
        tester,
        Scaffold(
          body: G3RestoreReceiptSheet(outcome: outcome, onClose: () {}),
        ),
      );
      expect(find.byKey(const ValueKey('restore-title')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('restore-title'))).data,
        title,
      );
    });
  }

  testWidgets('restore receipt omits empty reasons group', (tester) async {
    await pump(
      tester,
      Scaffold(
        body: G3RestoreReceiptSheet(
          outcome: const ImportOutcome(source: 'Sicherung', restoredRows: 3),
          onClose: () {},
        ),
      ),
    );
    expect(find.byKey(const ValueKey('restore-reasons')), findsNothing);
    expect(find.text('Übernommen'), findsWidgets);
  });

  testWidgets('frontier names the local day of an older stored sample', (
    tester,
  ) async {
    await pump(
      tester,
      Scaffold(
        body: OBFrontierCard(
          storedAt: DateTime(2026, 9, 28, 9, 28),
          now: DateTime(2026, 9, 29, 9, 41),
        ),
      ),
    );
    expect(find.text('bis gestern · 09:28'), findsOneWidget);
    final caption = tester.getRect(find.text('letzter gespeicherter Wert'));
    final track = tester.getRect(
      find.byKey(const ValueKey('band-frontier-track')),
    );
    expect(caption.bottom, lessThan(track.top));
  });

  testWidgets('Band info explains the screen before opening Datenstand', (
    tester,
  ) async {
    var statusOpens = 0;
    await pump(
      tester,
      G3BandScreen(
        band: const BandSnapshot(connection: BandConnection.connected),
        now: DateTime(2026, 9, 29, 9, 41),
        onStatus: () => statusOpens++,
      ),
    );
    await tester.tap(find.bySemanticsLabel('Über das Band'));
    await tester.pumpAndSettle();
    expect(find.text('Über das Band'), findsOneWidget);
    expect(statusOpens, 0);
    await tester.tap(find.text('Datenstand öffnen'));
    await tester.pumpAndSettle();
    expect(statusOpens, 1);
  });

  testWidgets('band detail follows live observations and clock', (
    tester,
  ) async {
    final updates = ValueNotifier<int>(0);
    addTearDown(updates.dispose);
    var now = DateTime(2026, 9, 29, 9, 41);
    BandSnapshot current = BandSnapshot(
      connection: BandConnection.connected,
      latestStoredAt: DateTime(2026, 9, 29, 9, 38),
      batteryPercent: 64,
    );
    await pump(
      tester,
      G3BandScreen(
        band: current,
        now: now,
        clock: () => now,
        bandUpdates: updates,
        readBand: () async => current,
      ),
    );
    await tester.pump();
    expect(find.text('Verbunden'), findsOneWidget);
    now = DateTime(2026, 9, 30, 9, 41);
    current = BandSnapshot(
      connection: BandConnection.disconnected,
      latestStoredAt: DateTime(2026, 9, 29, 9, 38),
      batteryPercent: 64,
    );
    updates.value++;
    await tester.pumpAndSettle();
    expect(find.text('gestern'), findsOneWidget);
    expect(find.text('zuletzt 64 %'), findsOneWidget);
    expect(find.text('Nicht verbunden'), findsWidgets);
  });

  test('Band issue mapping does not mistake scanning for not found', () {
    expect(
      bandIssueFor(
        bandStatusFor(
          connection: 'disconnected',
          blocker: BleBlocker.adapterOff,
        ),
      )?.condition,
      BandCondition.bluetoothOff,
    );
    for (final connection in ['scanning', 'connecting', 'disconnected']) {
      expect(bandIssueFor(bandStatusFor(connection: connection)), isNull);
    }
  });

  testWidgets('Bluetooth permission fault names the phone-side block', (
    tester,
  ) async {
    var reconnects = 0;
    await pump(
      tester,
      G3BandScreen(
        band: const BandSnapshot(connection: BandConnection.disconnected),
        now: DateTime(2026, 9, 29, 9, 41),
        status: bandStatusFor(
          connection: 'disconnected',
          blocker: BleBlocker.permissionDenied,
        ),
        onReconnect: () async => reconnects++,
      ),
    );
    expect(find.text('Bluetooth ist für diese App deaktiviert'), findsWidgets);
    expect(find.textContaining('Einstellungen → OpenBand 5'), findsOneWidget);
    expect(find.text('Verbinden'), findsNothing);
    expect(find.text('Hilfe'), findsOneWidget);
    await tester.ensureVisible(find.text('Hilfe'));
    await tester.tap(find.text('Hilfe'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Zugriff auf die Bluetooth'), findsWidgets);
    expect(reconnects, 0);
  });

  testWidgets('band repair fault does not offer a plain reconnect', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.reset);
    var reconnects = 0;
    await pump(
      tester,
      G3BandScreen(
        band: const BandSnapshot(connection: BandConnection.disconnected),
        now: DateTime(2026, 9, 29, 9, 41),
        status: bandStatusFor(
          connection: 'disconnected',
          needsRepairGuide: true,
        ),
        onReconnect: () async => reconnects++,
      ),
    );
    expect(find.text('Das Band muss erneut gekoppelt werden'), findsWidgets);
    expect(find.textContaining('Bluetooth-Einstellungen'), findsOneWidget);
    expect(find.text('Verbinden'), findsNothing);
    await tester.ensureVisible(find.text('Hilfe').first);
    await tester.tap(find.text('Hilfe').first);
    await tester.pumpAndSettle();
    expect(reconnects, 0);
  });

  testWidgets('Bluetooth off opens settings help without opening devices', (
    tester,
  ) async {
    final stored = DateTime(2026, 9, 28, 23, 10);
    final band = BandSnapshot(
      connection: BandConnection.disconnected,
      latestStoredAt: stored,
    );
    var devices = 0;
    var reconnects = 0;
    await pump(
      tester,
      G3BandScreen(
        band: band,
        now: DateTime(2026, 9, 29, 9, 41),
        issue: OBBandIssue.bluetoothOff,
        onDevices: () async => devices++,
        onReconnect: () async => reconnects++,
      ),
    );
    expect(find.text('Bluetooth ist ausgeschaltet'), findsOneWidget);
    expect(find.text('Kein Band in Reichweite'), findsNothing);
    await tester.tap(find.text('Bluetooth einschalten'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('iPhone-Einstellungen einschalten'),
      findsOneWidget,
    );
    expect(devices, 0);
    expect(reconnects, 0);
  });

  testWidgets('disconnected action invokes the real reconnect callback', (
    tester,
  ) async {
    var reconnects = 0;
    var devices = 0;
    await pump(
      tester,
      G3BandScreen(
        band: const BandSnapshot(connection: BandConnection.disconnected),
        now: DateTime(2026, 9, 29, 9, 41),
        onReconnect: () async => reconnects++,
        onDevices: () async => devices++,
      ),
    );
    await tester.tap(find.text('Verbinden'));
    await tester.pump();
    expect(reconnects, 1);
    expect(devices, 0);
  });

  testWidgets('connecting has its own status and no disconnected action', (
    tester,
  ) async {
    await pump(
      tester,
      G3BandScreen(
        band: const BandSnapshot(
          connection: BandConnection.connecting,
          transfer: TransferState.receiving,
        ),
        now: DateTime(2026, 9, 29, 9, 41),
      ),
    );
    expect(find.text('Verbindet …'), findsOneWidget);
    expect(find.text('Nicht verbunden'), findsNothing);
    expect(find.text('Verbinden'), findsNothing);
  });

  testWidgets('date sheet commits only a confirmed selection', (tester) async {
    final summary =
        jsonDecode(
              File(
                'docs/openband5/assets/fixtures/day-summary.json',
              ).readAsStringSync(),
            )
            as Map;
    final detail =
        jsonDecode(
              File(
                'docs/openband5/assets/fixtures/sleep-detail.json',
              ).readAsStringSync(),
            )
            as Map;
    final repository = SyntheticOpenBandRepository.fromMaps(summary, detail);
    final controller = OpenBandController(
      repository: repository,
      initialDay: '2026-09-15',
      now: () => DateTime(2026, 9, 18, 9, 41),
    );
    addTearDown(controller.dispose);
    await pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => chooseOpenBandDay(context, controller),
            child: const Text('Datum öffnen'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Datum öffnen'));
    await tester.pumpAndSettle();
    expect(find.text('Datum wählen'), findsOneWidget);
    await tester.tap(find.text('16'));
    await tester.pumpAndSettle();
    expect(controller.selectedDay, '2026-09-15');
    await tester.tap(find.byTooltip('Schließen'));
    await tester.pumpAndSettle();
    expect(controller.selectedDay, '2026-09-15');
    await tester.tap(find.text('Datum öffnen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('16'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ansehen'));
    await tester.pumpAndSettle();
    expect(controller.selectedDay, '2026-09-16');
  });

  testWidgets('selected night dot agrees with its stored preview', (
    tester,
  ) async {
    final repository = SyntheticOpenBandRepository.fromMaps(
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
      scenario: SyntheticScenario.g3Sample,
    );
    final controller = OpenBandController(
      repository: repository,
      initialDay: '2026-09-29',
      now: () => DateTime(2026, 9, 29, 9, 41),
    );
    addTearDown(controller.dispose);
    await pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => chooseOpenBandDay(context, controller),
            child: const Text('Datum öffnen'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Datum öffnen'));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            (w.properties.label ?? '').contains(
              'Dienstag, 29. September 2026, Schlafwert vorhanden',
            ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('large text opens with the selected date above its footer', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.reset);
    final oldHitPolicy = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(
      () => WidgetController.hitTestWarningShouldBeFatal = oldHitPolicy,
    );
    final repository = SyntheticOpenBandRepository.fromMaps(
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
    );
    final controller = OpenBandController(
      repository: repository,
      initialDay: '2026-08-31',
      now: () => DateTime(2026, 8, 31, 9, 41),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: openBandTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => chooseOpenBandDay(context, controller),
              child: const Text('Datum öffnen'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Datum öffnen'));
    await tester.pumpAndSettle();
    final selectedCell = find
        .ancestor(of: find.text('31'), matching: find.byType(InkWell))
        .first;
    final lastRow = tester.getRect(selectedCell);
    final viewport = tester.getRect(find.byType(ListView).last);
    final footer = tester.getRect(find.byType(FilledButton).first);
    expect(lastRow.top, greaterThanOrEqualTo(viewport.top));
    expect(lastRow.bottom, lessThanOrEqualTo(viewport.bottom));
    expect(lastRow.bottom, lessThan(footer.top));
    expect(
      tester.getRect(find.byType(FilledButton).last).bottom,
      lessThanOrEqualTo(778),
    );
    await tester.tap(find.text('31'));
    await tester.tap(find.widgetWithText(FilledButton, 'Ansehen'));
    await tester.pumpAndSettle();
    expect(controller.selectedDay, '2026-08-31');
    expect(tester.takeException(), isNull);
  });

  testWidgets('mini safe area opens every week and both date actions', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.reset);
    final oldHitPolicy = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(
      () => WidgetController.hitTestWarningShouldBeFatal = oldHitPolicy,
    );
    final repository = SyntheticOpenBandRepository.fromMaps(
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
    );
    for (final size in [const Size(375, 812), const Size(360, 780)]) {
      tester.view.physicalSize = size;
      for (final (day, last, action) in [
        ('2026-09-29', '29', 'Ansehen'),
        ('2026-08-31', '31', 'Ansehen'),
      ]) {
        final controller = OpenBandController(
          repository: repository,
          initialDay: day,
          now: () => DateTime.parse('$day 09:41:00'),
        );
        addTearDown(controller.dispose);
        await controller.refresh();
        expect(controller.day?.synthetic, isTrue);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('de'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            theme: openBandTheme(Brightness.light),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => chooseOpenBandDay(context, controller),
                  child: const Text('Datum öffnen'),
                ),
                bottomNavigationBar: const SizedBox(height: 82),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Datum öffnen'));
        await tester.pumpAndSettle();
        final viewport = tester.getRect(find.byType(ListView).last);
        final selected = tester.getRect(find.text(last));
        final card = tester.getRect(find.byType(OBPanel).first);
        final confirm = find.widgetWithText(FilledButton, action);
        final confirmRect = tester.getRect(confirm);
        final todayRect = tester.getRect(
          find.widgetWithText(FilledButton, 'Zu heute'),
        );
        expect(
          card.top,
          greaterThanOrEqualTo(viewport.top),
          reason: '$size $day',
        );
        expect(
          card.bottom,
          lessThanOrEqualTo(viewport.bottom - 24),
          reason: '$size $day',
        );
        expect(
          selected.top,
          greaterThanOrEqualTo(viewport.top),
          reason: '$size $day',
        );
        expect(
          selected.bottom,
          lessThanOrEqualTo(viewport.bottom),
          reason: '$size $day',
        );
        expect(
          confirmRect.top,
          greaterThan(viewport.bottom),
          reason: '$size $day',
        );
        expect(
          todayRect.top,
          greaterThan(viewport.bottom),
          reason: '$size $day',
        );
        expect(
          todayRect.bottom,
          lessThanOrEqualTo(size.height - 34),
          reason: '$size $day',
        );
        expect(
          confirmRect.bottom,
          lessThanOrEqualTo(size.height - 34),
          reason: '$size $day',
        );
        await tester.tap(find.text(last));
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(controller.selectedDay, day);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('date sheet six-week mini golden', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.reset);
    final controller = OpenBandController(
      repository: SyntheticOpenBandRepository.fromMaps(
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
      ),
      initialDay: '2026-08-31',
      now: () => DateTime(2026, 8, 31, 9, 41),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: openBandTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => chooseOpenBandDay(context, controller),
              child: const Text('Datum öffnen'),
            ),
            bottomNavigationBar: const SizedBox(height: 82),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Datum öffnen'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Overlay).first,
      matchesGoldenFile('openband_goldens/g3-date-picker-mini-safe.png'),
    );
  }, tags: const ['golden']);

  testWidgets('date sheet large text golden', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.reset);
    final controller = OpenBandController(
      repository: SyntheticOpenBandRepository.fromMaps(
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
      ),
      initialDay: '2026-09-29',
      now: () => DateTime(2026, 9, 29, 9, 41),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: openBandTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => chooseOpenBandDay(context, controller),
              child: const Text('Datum öffnen'),
            ),
            bottomNavigationBar: const SizedBox(height: 82),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Datum öffnen'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Overlay).first,
      matchesGoldenFile('openband_goldens/g3-date-picker-large.png'),
    );
  }, tags: const ['golden']);

  test('data status heading follows the selected local day', () {
    final now = DateTime(2026, 9, 18, 9, 41);
    expect(bandStatusValuesHeading('2026-09-15', now), 'WERTE FÜR 15.09.');
    expect(bandStatusValuesHeading('2026-09-18', now), 'WERTE FÜR HEUTE');
  });

  testWidgets('data status sheet keeps page backlog separate from coverage', (
    tester,
  ) async {
    final summary =
        jsonDecode(
              File(
                'docs/openband5/assets/fixtures/day-summary.json',
              ).readAsStringSync(),
            )
            as Map;
    final detail =
        jsonDecode(
              File(
                'docs/openband5/assets/fixtures/sleep-detail.json',
              ).readAsStringSync(),
            )
            as Map;
    final now = DateTime(2026, 9, 29, 9, 41);
    final repository = _DiagnosticsRepository(
      summary,
      detail,
      BandDiagnostics(
        lastStoredSampleAt: DateTime(2026, 9, 29, 9, 38),
        backlog: BandBacklog(
          observedAt: DateTime(2026, 9, 29, 9, 36),
          unreadPages: 3,
        ),
        coverage: BandCoverage(
          start: now.subtract(const Duration(hours: 24)),
          end: now,
          recordedSeconds: 2,
          coveragePercent: null,
          wristOffIntervals: [
            BandTimeInterval(
              DateTime(2026, 9, 29, 8),
              DateTime(2026, 9, 29, 8, 10),
            ),
          ],
        ),
        battery: BandBattery(
          observedAt: DateTime(2026, 9, 29, 9, 37),
          percent: 67,
        ),
      ),
    );
    final controller = OpenBandController(
      repository: repository,
      initialDay: '2026-09-29',
      now: () => now,
      band: BandSnapshot(
        connection: BandConnection.connected,
        latestStoredAt: DateTime(2026, 9, 29, 8),
        batteryPercent: 20,
      ),
    );
    addTearDown(controller.dispose);
    await pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showBandStatus(context, controller, null),
            child: const Text('Datenstand öffnen'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Datenstand öffnen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('3 Bandseiten ungelesen'), findsOneWidget);
    expect(find.textContaining('Akku 67 %'), findsOneWidget);
    expect(find.textContaining('2 Sek. aufgezeichnet'), findsOneWidget);
    expect(find.textContaining('Anteil unbekannt'), findsOneWidget);
    expect(find.textContaining('1 beobachtete Ablegephase'), findsOneWidget);
    expect(find.textContaining('24 h: 100 %'), findsNothing);
    expect(find.text('letzter gespeicherter Wert vor 3 Min.'), findsOneWidget);
    expect(find.text('Noch kein Empfang'), findsNothing);
  });

  testWidgets('data status dates the stored frontier from yesterday', (
    tester,
  ) async {
    final summary =
        jsonDecode(
              File(
                'docs/openband5/assets/fixtures/day-summary.json',
              ).readAsStringSync(),
            )
            as Map;
    final detail =
        jsonDecode(
              File(
                'docs/openband5/assets/fixtures/sleep-detail.json',
              ).readAsStringSync(),
            )
            as Map;
    final controller = OpenBandController(
      repository: _DiagnosticsRepository(
        summary,
        detail,
        BandDiagnostics(lastStoredSampleAt: DateTime(2026, 9, 28, 9, 38)),
      ),
      initialDay: '2026-09-29',
      now: () => DateTime(2026, 9, 29, 9, 41),
      band: const BandSnapshot(connection: BandConnection.connected),
    );
    addTearDown(controller.dispose);
    await pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showBandStatus(context, controller, null),
            child: const Text('Datenstand öffnen'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Datenstand öffnen'));
    await tester.pumpAndSettle();
    expect(find.text('bis gestern · 09:38'), findsNWidgets(2));
  });

  testWidgets('data status scrolls past its buttons at large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(tester.view.reset);
    final summary =
        jsonDecode(
              File(
                'docs/openband5/assets/fixtures/day-summary.json',
              ).readAsStringSync(),
            )
            as Map;
    final detail =
        jsonDecode(
              File(
                'docs/openband5/assets/fixtures/sleep-detail.json',
              ).readAsStringSync(),
            )
            as Map;
    final controller = OpenBandController(
      repository: _DiagnosticsRepository(
        summary,
        detail,
        BandDiagnostics(lastStoredSampleAt: DateTime(2026, 9, 29, 9, 38)),
      ),
      initialDay: '2026-09-15',
      now: () => DateTime(2026, 9, 29, 9, 41),
      band: const BandSnapshot(connection: BandConnection.connected),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: openBandTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showBandStatus(context, controller, () {}),
              child: const Text('Datenstand öffnen'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Datenstand öffnen'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Auswertung'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    final label = tester.getRect(find.text('Auswertung'));
    final primary = tester.getRect(find.text('Übertragung fortsetzen'));
    expect(label.height, lessThan(45));
    expect(label.bottom, lessThan(primary.top));
    expect(find.textContaining('Ruhepuls ·'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('data status large text bottom golden', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(tester.view.reset);
    final controller = OpenBandController(
      repository: _DiagnosticsRepository(
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
        BandDiagnostics(lastStoredSampleAt: DateTime(2026, 9, 29, 9, 38)),
      ),
      initialDay: '2026-09-15',
      now: () => DateTime(2026, 9, 29, 9, 41),
      band: const BandSnapshot(connection: BandConnection.connected),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: openBandTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showBandStatus(context, controller, () {}),
              child: const Text('Datenstand öffnen'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Datenstand öffnen'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Auswertung'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Overlay).first,
      matchesGoldenFile('openband_goldens/g3-data-status-large-bottom.png'),
    );
  }, tags: const ['golden']);

  testWidgets('profile mini German size and navigation golden', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: openBandTheme(Brightness.light),
        home: RepaintBoundary(
          key: const ValueKey('capture'),
          child: ProfileHomeView(
            releaseReduced: true,
            stats: const ProfileStats(
              name: 'Mats',
              sources: 1,
              storageBytes: 4509715661,
            ),
            band: const BandSnapshot(connection: BandConnection.connected),
            bandName: 'WHOOP 5.0',
            languageLabel: 'Deutsch',
            now: DateTime(2026, 9, 29, 9, 41),
            onBand: () {},
            onNotifications: () {},
            onData: () {},
            onSettings: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/g3-profile-mini.png'),
    );
  }, tags: const ['golden']);

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('band $brightness golden', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 852);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          theme: openBandTheme(Brightness.light),
          darkTheme: openBandTheme(Brightness.dark),
          themeMode: brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          home: RepaintBoundary(
            key: const ValueKey('capture'),
            child: G3BandScreen(
              band: BandSnapshot(
                connection: BandConnection.connected,
                batteryPercent: 64,
                latestStoredAt: DateTime(2026, 9, 29, 9, 38),
                receivedAt: DateTime(2026, 9, 29, 9, 38),
              ),
              diagnostics: BandDiagnostics(
                deviceFamily: 'gen5',
                lastStoredSampleAt: DateTime(2026, 9, 29, 9, 38),
                battery: BandBattery(
                  observedAt: DateTime(2026, 9, 29, 9, 37),
                  percent: 67,
                ),
                backlog: BandBacklog(
                  observedAt: DateTime(2026, 9, 29, 9, 36),
                  unreadPages: 3,
                ),
                coverage: BandCoverage(
                  start: DateTime(2026, 9, 28, 9, 41),
                  end: DateTime(2026, 9, 29, 9, 41),
                  recordedSeconds: 38000,
                  coveragePercent: null,
                  wristOffIntervals: [
                    BandTimeInterval(
                      DateTime(2026, 9, 29, 8),
                      DateTime(2026, 9, 29, 8, 10),
                    ),
                  ],
                ),
              ),
              now: DateTime(2026, 9, 29, 9, 41),
              databaseSize: '4,2 GB',
              onDevices: () async {},
            ),
          ),
        ),
      );
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/g3-band-${brightness.name}.png'),
      );
    }, tags: const ['golden']);
  }
}

class _DiagnosticsRepository extends SyntheticOpenBandRepository {
  _DiagnosticsRepository(super.summary, super.detail, this.diagnostics)
    : super.fromMaps(scenario: SyntheticScenario.g3Sample);

  final BandDiagnostics diagnostics;

  @override
  Future<BandDiagnostics> readBandDiagnostics() async => diagnostics;
}
