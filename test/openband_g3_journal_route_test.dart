import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/app.dart' show screenForRoute;
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('de_DE'));

  testWidgets('journal compose deep link saves to the target day and returns', (
    tester,
  ) async {
    final repo = SyntheticOpenBandRepository.fromMaps(
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
    )..failCaffeineSleepPattern = true;
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      screenForRoute('/journal/compose', repository: repo)!,
                ),
              ),
              child: const Text('Öffnen'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
    expect(find.text('Alkohol am Abend?'), findsOneWidget);
    expect(find.text('zu gestern Abend'), findsOneWidget);
    await tester.tap(find.text('Nein').first);
    await tester.pumpAndSettle();
    final selectedDay = todayLabel();
    final targetDay = g3CheckInTargetDay(selectedDay, 'alcohol_evening');
    expect(
      (await repo.readJournalDay(targetDay)).metrics['alcohol_evening']?.value,
      0,
    );
    expect(
      (await repo.readJournalDay(selectedDay)).metrics['alcohol_evening'],
      isNull,
    );
    await tester.tap(find.bySemanticsLabel('Zurück zu Journal'));
    await tester.pumpAndSettle();
    expect(find.text('Öffnen'), findsOneWidget);
  });
}
