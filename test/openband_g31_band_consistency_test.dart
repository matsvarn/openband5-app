import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/data/auto_backup.dart';
import 'package:openstrap_edge/gestures/device_action.dart';
import 'package:openstrap_edge/l10n/app_localizations.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/state/alarm_schedule.dart';
import 'package:openstrap_edge/ui2/onboarding/profile_setup.dart';
import 'package:openstrap_edge/ui2/onboarding/welcome.dart';
import 'package:openstrap_edge/ui2/profile/alarm.dart';
import 'package:openstrap_edge/ui2/profile/data.dart';
import 'package:openstrap_edge/ui2/profile/gestures.dart';
import 'package:openstrap_edge/ui2/profile/profile.dart';
import 'package:openstrap_edge/ui2/profile/settings.dart';

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
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        supportedLocales: const [Locale('de'), Locale('en')],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: openBandTheme(Brightness.light),
        home: RepaintBoundary(key: const ValueKey('capture'), child: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('G3 settings rows show a chevron only for a destination', (
    tester,
  ) async {
    await pump(
      tester,
      Scaffold(
        body: Column(
          children: [
            const SetRow(Icons.info, Colors.black, 'Read only'),
            SetRow(Icons.settings, Colors.black, 'Open', onTap: () {}),
          ],
        ),
      ),
    );
    expect(find.bySemanticsLabel('Read only'), findsOneWidget);
    expect(find.bySemanticsLabel('Open'), findsOneWidget);
    expect(find.byType(OBChevron), findsOneWidget);
  });

  testWidgets('settings information key opens its explanation', (tester) async {
    await pump(tester, const MoreSettingsView(releaseReduced: true));
    await tester.tap(find.bySemanticsLabel('Erklärung'));
    await tester.pumpAndSettle();
    expect(find.textContaining('auf diesem Gerät gespeichert'), findsOneWidget);
  });

  testWidgets('profile header names the supplied calling tab', (tester) async {
    await pump(
      tester,
      const ProfileHomeView(
        releaseReduced: true,
        backLabel: 'Training',
        languageLabel: 'Deutsch',
      ),
    );
    expect(find.bySemanticsLabel('Zurück zu Training'), findsOneWidget);
  });

  final cases = <String, Widget>{
    'settings': MoreSettingsView(
      releaseReduced: true,
      units: 'Metrisch',
      appearance: 'System',
      onAlarm: () {},
      onNotifications: () {},
      onData: () {},
    ),
    'alarm': AlarmScreenView(
      connected: true,
      now: DateTime(2026, 9, 29, 9, 41),
      schedule: fillDefaultAlarmSchedule(const []),
      onToggleDay: (_, _) async {},
      onSetDayTime: (_, _, _) async {},
    ),
    'gestures': const BandGesturesView(
      chosen: DeviceAction.none,
      supported: {DeviceAction.none},
      releaseReduced: true,
    ),
    'edit-profile': EditProfileView(
      initial: const {'name': 'Mats', 'sex': 'm', 'height_cm': 182.0},
      onSave: (_) async {},
    ),
    'data': DataScreenView(
      cadence: BackupCadence.daily,
      lastBackupAt: DateTime(2026, 9, 28, 9, 38),
      now: DateTime(2026, 9, 29, 9, 41),
      onBackupNow: () {},
      onAutomatic: (_) {},
      onExportDatabase: () {},
      onExportEncrypted: () {},
      onExportCsv: () {},
      onImport: () {},
      onReanalyze: () {},
    ),
    'profile-setup': ProfileSetupView(onSave: (_) async {}),
    'welcome': WelcomeView(onNew: () {}, onImport: () {}),
  };

  for (final entry in cases.entries) {
    testWidgets('G3 ${entry.key} golden', (tester) async {
      await pump(tester, entry.value);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/g31-${entry.key}.png'),
      );
      expect(tester.takeException(), isNull);
    }, tags: const ['golden']);
  }
}
