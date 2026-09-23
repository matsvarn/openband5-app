import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:openstrap_edge/app.dart';
import 'package:openstrap_edge/coach/coach_config.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/locale_controller.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/state/units_controller.dart';
import 'package:openstrap_edge/sync/paired_device.dart';
import 'package:openstrap_edge/theme/theme_controller.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:openstrap_edge/ui2/onboarding/first_sync.dart';
import 'package:openstrap_edge/ui2/onboarding/pairing.dart';
import 'package:openstrap_edge/ui2/onboarding/profile_setup.dart';
import 'package:openstrap_edge/ui2/onboarding/welcome.dart';
import 'package:openstrap_edge/ui2/pairing/device_picker.dart';
import 'package:openstrap_edge/ui2/profile/devices.dart' show RePair;

class _PairingApp extends AppState {
  final bool failFirst;
  int pairAttempts = 0;

  _PairingApp({this.failFirst = false}) : super.forTesting();

  @override
  Future<bool> accessorySetupSupported() async => true;

  @override
  Future<void> pairViaAccessorySetup({String? serial}) async {
    pairAttempts++;
    if (failFirst && pairAttempts == 1) {
      throw StateError('Session failed after accessory authorization');
    }
    paired = PairedDevice('test-band', null);
    notifyListeners();
  }
}

Future<void> _pumpApp(WidgetTester tester, AppState app) async {
  SharedPreferences.setMockInitialValues({});
  // Prefs caches its SharedPreferences instance; without the reset each test
  // would read the bypass flags the previous test wrote.
  Prefs.debugReset();
  await Prefs.ensureLoaded();
  tester.view.physicalSize = const Size(1170, 3600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  app.initialized = true;
  final theme = ThemeController.seed(AppThemeChoice.light, Brightness.light);
  final locale = LocaleController.seed('en');
  final units = UnitsController.seed(UnitSystem.metric);
  final coach = CoachConfig();
  addTearDown(app.dispose);
  addTearDown(theme.dispose);
  addTearDown(locale.dispose);
  addTearDown(units.dispose);
  addTearDown(coach.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider<LocaleController>.value(value: locale),
        ChangeNotifierProvider<UnitsController>.value(value: units),
        ChangeNotifierProvider<CoachConfig>.value(value: coach),
      ],
      child: const OpenStrapApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting();
  });

  testWidgets('first-run pairing can go back to welcome', (tester) async {
    await _pumpApp(tester, AppState.forTesting());
    expect(find.byType(WelcomeScreen), findsOneWidget);

    await tester.tap(find.text('Set up my band'));
    await tester.pumpAndSettle();
    expect(find.byType(PairingScreen), findsOneWidget);
    expect(find.byType(DevicePickerScreen), findsNothing);

    await tester.tap(find.byType(OBChevron).first);
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(PairingScreen), findsNothing);
  });

  for (final failFirst in [false, true]) {
    testWidgets(
      'direct pairing advances after persistence (retry: $failFirst)',
      (tester) async {
        final app = _PairingApp(failFirst: failFirst);
        await _pumpApp(tester, app);
        await tester.tap(find.text('Set up my band'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Connect'));
        await tester.pumpAndSettle();
        if (failFirst) {
          expect(find.text('Pairing did not complete'), findsOneWidget);
          await tester.tap(find.text('Try again'));
          await tester.pumpAndSettle();
        }
        expect(find.byType(PairingScreen), findsNothing);
        expect(find.byType(FirstSyncScreen), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (w) => w is OBChevron && w.direction == AxisDirection.left,
          ),
          findsNothing,
        );
        expect(app.isPaired, isTrue);
        expect(app.pairAttempts, failFirst ? 2 : 1);
        await tester.tap(find.text('Continue to profile'));
        await tester.pumpAndSettle();
        expect(find.byType(ProfileSetupScreen), findsOneWidget);
      },
    );
  }

  testWidgets('re-pair retains one pushed-route pop after Continue', (
    tester,
  ) async {
    final app = _PairingApp();
    await _pumpApp(tester, app);
    Navigator.of(
      tester.element(find.byType(WelcomeScreen)),
    ).push(MaterialPageRoute<void>(builder: (_) => const RePair()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Paired'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.byType(PairingScreen), findsNothing);
    expect(find.byType(RePair), findsNothing);
    expect(find.byType(FirstSyncScreen), findsOneWidget);
    expect(app.pairAttempts, 1);
  });
}
