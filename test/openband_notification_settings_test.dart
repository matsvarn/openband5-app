import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/notify/notification_prefs.dart';
import 'package:openstrap_edge/openband/notification_settings.dart';
import 'package:openstrap_edge/openband/settings_controls.dart';
import 'package:openstrap_edge/openband/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('notification choice still uses notification-choice keys', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 2400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(Brightness.light).copyWith(
          platform: TargetPlatform.iOS,
        ),
        home: NotificationSettingsView(
          prefs: const NotificationPrefs(deviceEnabled: true),
          onEdit: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('notif-battery')));
    await tester.tap(find.byKey(const ValueKey('notif-battery')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notification-choice')), findsOneWidget);
    expect(find.byKey(const ValueKey('notification-choice-20')), findsOneWidget);
    expect(find.byType(OBSettingsChoiceSheet<int>), findsOneWidget);
  });

  testWidgets('generic choice sheet returns the typed value', (tester) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                picked = await showOpenBandSettingsChoiceSheet<String>(
                  context: context,
                  title: 'Gerät',
                  choices: const [('a', 'Eins'), ('b', 'Zwei')],
                  selected: 'a',
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
    await tester.tap(find.text('Zwei'));
    await tester.pumpAndSettle();
    expect(picked, 'b');
  });
}
