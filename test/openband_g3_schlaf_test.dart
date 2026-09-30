import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/notify/notification_center.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/g3/screens/sleep_reminder.dart';
import 'package:openstrap_edge/openband/g3/screens/sleep_goal.dart';
import 'package:openstrap_edge/openband/g3/sleep_parts.dart';
import 'package:openstrap_edge/openband/sleep_editor.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart' show openBandTheme;

void main() {
  setUpAll(() async {
    await initializeDateFormatting('de_DE');
    for (final (family, path) in [
      ('Inter', 'assets/fonts/Inter/Inter.ttf'),
      ('Inter Tight', 'assets/fonts/InterTight/InterTight[wght].ttf'),
    ]) {
      await (FontLoader(family)..addFont(
            Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
          ))
          .load();
    }
    await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
          rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
        ))
        .load();
  });

  test(
    'bedtime reminder keeps the one-shot only for its day and plan',
    () async {
      final reminder = MemorySleepBedtimeReminder();
      final bedtime = DateTime(2026, 9, 29, 22, 18);
      final at = sleepReminderAt(bedtime);
      expect(at, DateTime(2026, 9, 29, 22, 5));
      expect(
        await reminder.arm(at, '2026-09-29', 'Bettzeit'),
        BedtimeReminderResult.scheduled,
      );
      expect(
        await reminder.reconcile(
          today: '2026-09-29',
          planLoaded: true,
          bedtime: bedtime,
        ),
        isFalse,
      );
      expect(
        await reminder.reconcile(
          today: '2026-09-29',
          planLoaded: true,
          bedtime: bedtime.add(const Duration(minutes: 10)),
        ),
        isTrue,
      );
      expect(reminder.current, isNull);
      await reminder.arm(at, '2026-09-29', 'Bettzeit');
      expect(
        await reminder.reconcile(today: '2026-09-30', planLoaded: false),
        isTrue,
      );
      expect(reminder.cancellations, 2);
      await reminder.arm(at, '2026-09-29', 'Bettzeit');
      expect(
        await reminder.reconcile(today: '2026-09-29', planLoaded: true),
        isTrue,
      );
      reminder.result = BedtimeReminderResult.denied;
      expect(
        await reminder.arm(at, '2026-09-29', 'Bettzeit'),
        BedtimeReminderResult.denied,
      );
      expect(reminder.current, isNull);
    },
  );

  testWidgets('no-goal sleep lead offers setup without a goal delta', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: Scaffold(
          body: OBSleepLead(minutes: 438, goalMinutes: null, onGoal: () {}),
        ),
      ),
    );
    expect(find.text('Ziel festlegen'), findsOneWidget);
    expect(find.textContaining('unter deinem Ziel'), findsNothing);
    expect(find.textContaining('über deinem Ziel'), findsNothing);
    expect(find.textContaining('Ziel 7h'), findsNothing);
  });

  testWidgets('bedtime compares clock times across successive nights', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: Scaffold(
          body: OBBedtimeLead(
            bedtime: DateTime(2026, 9, 29, 22, 18),
            wake: DateTime(2026, 9, 30, 6, 54),
            lastOnset: DateTime(2026, 9, 28, 23, 10),
            lastWake: DateTime(2026, 9, 29, 6, 54),
          ),
        ),
      ),
    );
    expect(find.text('22:20'), findsOneWidget);
    expect(find.textContaining('50 Min. früher'), findsOneWidget);
    expect(find.text('22:00'), findsOneWidget);
  });

  testWidgets('bedtime lead stays usable at narrow large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: const Scaffold(
            body: SingleChildScrollView(
              child: OBBedtimeLead(bedtime: null, wake: null),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Kein Vorschlag'), findsOneWidget);
  });

  testWidgets('goal write failure keeps the selected draft for retry', (
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
    final repo = SyntheticOpenBandRepository.fromMaps(summary, detail);
    repo.failSleepGoalWrite = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  G3SleepGoalSheet.show(context, repo, '2026-09-29'),
              child: const Text('Ziel öffnen'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ziel öffnen'));
    await tester.pumpAndSettle();
    expect(find.text('Ziel wählen'), findsOneWidget);
    await tester.tap(find.text('Ziel wählen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5h').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ziel speichern'));
    await tester.pumpAndSettle();
    expect(find.text('5h'), findsOneWidget);
    expect(
      find.textContaining('Deine Auswahl bleibt erhalten'),
      findsOneWidget,
    );
    repo.failSleepGoalWrite = false;
    await tester.tap(find.text('Erneut speichern'));
    await tester.pumpAndSettle();
    expect((await repo.readSleepGoal('2026-09-29')).targetMinutes, 300);
  });

  testWidgets('no-goal lead light and dark', tags: const ['golden'], (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    for (final dark in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: openBandTheme(dark ? Brightness.dark : Brightness.light),
          home: Scaffold(
            body: RepaintBoundary(
              key: const ValueKey('lead'),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: OBSleepLead(
                  minutes: 438,
                  goalMinutes: null,
                  onGoal: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(const ValueKey('lead')),
        matchesGoldenFile(
          'openband_goldens/g3-schlaf-no-goal-${dark ? 'dark' : 'light'}.png',
        ),
      );
    }
  });

  testWidgets(
    'correction editor names the recorded window',
    tags: const ['golden'],
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
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
        scenario: SyntheticScenario.g3Sample,
      );
      final controller = OpenBandController(
        repository: repo,
        initialDay: '2026-09-29',
        now: () => DateTime(2026, 9, 29, 9, 41),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      await tester.pumpWidget(
        MaterialApp(
          theme: openBandTheme(Brightness.light),
          home: RepaintBoundary(
            key: const ValueKey('correction'),
            child: SleepEditor(controller: controller, g3: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Band hat aufgezeichnet 23:10–06:54'), findsOneWidget);
      expect(find.text('Nacht zu Di 29.09'), findsOneWidget);
      expect(find.text('7h44'), findsOneWidget);
      await expectLater(
        find.byKey(const ValueKey('correction')),
        matchesGoldenFile('openband_goldens/g3-schlaf-correction-edit.png'),
      );
    },
  );
}
