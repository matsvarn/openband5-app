import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/day_picker.dart';
import 'package:openstrap_edge/openband/g3/band_parts.dart';
import 'package:openstrap_edge/openband/g3/screens/band.dart';
import 'package:openstrap_edge/openband/g3/screens/band_restore.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/screens.dart'
    show bandStatusValuesHeading;
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
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
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
          onDevices: () async {
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

  testWidgets('Bluetooth off and no-band-found stay distinct band details', (
    tester,
  ) async {
    final stored = DateTime(2026, 9, 28, 23, 10);
    final band = BandSnapshot(
      connection: BandConnection.disconnected,
      latestStoredAt: stored,
    );
    for (final (issue, title, action) in [
      (
        OBBandIssue.bluetoothOff,
        'Bluetooth ist ausgeschaltet',
        'Bluetooth einschalten',
      ),
      (OBBandIssue.notFound, 'Kein Band in Reichweite', 'Erneut suchen'),
    ]) {
      await pump(
        tester,
        G3BandScreen(
          band: band,
          now: DateTime(2026, 9, 29, 9, 41),
          issue: issue,
          onDevices: () async {},
        ),
      );
      expect(find.text(title), findsOneWidget);
      expect(find.text(action), findsOneWidget);
      expect(find.text('BAND VERBINDEN'), findsNothing);
      expect(find.text('—'), findsWidgets);
    }
  });

  testWidgets('date sheet commits only a confirmed selection', (tester) async {
    final summary =
        jsonDecode(
              await rootBundle.loadString(
                'docs/openband5/assets/fixtures/day-summary.json',
              ),
            )
            as Map;
    final detail =
        jsonDecode(
              await rootBundle.loadString(
                'docs/openband5/assets/fixtures/sleep-detail.json',
              ),
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
    await tester.tap(find.textContaining('ansehen'));
    await tester.pumpAndSettle();
    expect(controller.selectedDay, '2026-09-16');
  });

  test('data status heading follows the selected local day', () {
    final now = DateTime(2026, 9, 18, 9, 41);
    expect(bandStatusValuesHeading('2026-09-15', now), 'WERTE FÜR 15.09.');
    expect(bandStatusValuesHeading('2026-09-18', now), 'WERTE FÜR HEUTE');
  });

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
