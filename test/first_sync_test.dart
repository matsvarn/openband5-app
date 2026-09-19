// Erste Übertragung — the onboarding step between pairing and profile.
//
// Rows report observed connection, stored frontier, and today's current-algo
// evaluation. Continue never blocks on sync progress.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:openstrap_edge/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/ui2/onboarding/first_sync.dart';

Widget _frame(Widget child, {Locale locale = const Locale('de')}) =>
    MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('de'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: openBandTheme(Brightness.light),
      home: child,
    );

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

final _now = DateTime(2026, 9, 15, 9, 41);
final _stored = DateTime(2026, 9, 15, 6, 54);
final _computed = DateTime(2026, 9, 15, 7, 12);

BandSnapshot _receiving() => BandSnapshot(
  connection: BandConnection.connected,
  transfer: TransferState.receiving,
  latestStoredAt: _stored,
);

SetupEvaluation _eval(SetupEvalState state) => SetupEvaluation(
  day: '2026-09-15',
  currentAlgo: kAlgoVersion,
  storedAlgo: state == SetupEvalState.missing ? null : kAlgoVersion,
  computedAt: state == SetupEvalState.complete ? _computed : null,
  state: state,
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting();
  });

  testWidgets(
    'a receiving transfer shows the stored frontier, not evaluation',
    (tester) async {
      var done = false;
      await tester.pumpWidget(
        _frame(
          FirstSyncScreen(
            onDone: () => done = true,
            now: () => _now,
            readBand: () async => _receiving(),
            readSetupEvaluation: (_) async => _eval(SetupEvalState.missing),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Erste Übertragung'), findsOneWidget);
      expect(find.text('Schritt 2 von 3'), findsOneWidget);
      expect(find.text('Verbindung'), findsOneWidget);
      expect(find.text('Auf dem iPhone'), findsOneWidget);
      expect(find.text('Auswertung heute'), findsOneWidget);
      expect(find.text('Verbunden'), findsOneWidget);
      expect(find.text('bis 06:54'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(find.text('Das Band erzählt von der letzten Nacht'), findsNothing);
      expect(find.text('Nacht wird gelesen'), findsNothing);

      await tester.tap(find.text('Weiter zum Profil'));
      await tester.pump();
      expect(done, isTrue);
      await _unmount(tester);
    },
  );

  testWidgets('an idle band with nothing stored shows three dashes', (
    tester,
  ) async {
    var done = false;
    await tester.pumpWidget(
      _frame(
        FirstSyncScreen(
          onDone: () => done = true,
          now: () => _now,
          readBand: () async => const BandSnapshot(),
          readSetupEvaluation: (_) async => _eval(SetupEvalState.missing),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('—'), findsNWidgets(3));
    await tester.tap(find.text('Weiter zum Profil'));
    await tester.pump();
    expect(done, isTrue);
    await _unmount(tester);
  });

  testWidgets('a stored cursor without a current evaluation is not complete', (
    tester,
  ) async {
    await tester.pumpWidget(
      _frame(
        FirstSyncScreen(
          onDone: () {},
          now: () => _now,
          readBand: () async => _receiving(),
          readSetupEvaluation: (_) async => _eval(SetupEvalState.missing),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('07:12'), findsNothing);
    expect(find.text('bis 06:54'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('pending and failed jobs use honest labels', (tester) async {
    await tester.pumpWidget(
      _frame(
        FirstSyncView(
          now: _now,
          onDone: () {},
          band: _receiving(),
          evaluation: _eval(SetupEvalState.pending),
        ),
      ),
    );
    expect(find.text('Ausstehend'), findsOneWidget);
    await tester.pumpWidget(
      _frame(
        FirstSyncView(
          now: _now,
          onDone: () {},
          band: _receiving(),
          evaluation: _eval(SetupEvalState.failed),
        ),
      ),
    );
    expect(find.text('Fehlgeschlagen'), findsOneWidget);
  });

  testWidgets('complete evaluation shows computed_at, not the cursor', (
    tester,
  ) async {
    await tester.pumpWidget(
      _frame(
        FirstSyncView(
          now: _now,
          onDone: () {},
          band: BandSnapshot(
            connection: BandConnection.connected,
            transfer: TransferState.idle,
            latestStoredAt: _stored,
          ),
          evaluation: _eval(SetupEvalState.complete),
        ),
      ),
    );
    expect(find.text('07:12'), findsOneWidget);
    expect(find.text('bis 06:54'), findsOneWidget);
  });

  testWidgets('continue works on empty, partial and read failure', (
    tester,
  ) async {
    for (final child in [
      FirstSyncView(
        now: _now,
        onDone: () {},
        evaluation: _eval(SetupEvalState.missing),
      ),
      FirstSyncView(
        now: _now,
        onDone: () {},
        band: _receiving(),
        evaluation: _eval(SetupEvalState.partial),
      ),
      FirstSyncView(
        now: _now,
        onDone: () {},
        band: _receiving(),
        evalError: true,
      ),
    ]) {
      var done = false;
      await tester.pumpWidget(
        _frame(
          FirstSyncView(
            now: child.now,
            onDone: () => done = true,
            band: child.band,
            evaluation: child.evaluation,
            evalError: child.evalError,
          ),
        ),
      );
      await tester.tap(find.text('Weiter zum Profil'));
      await tester.pump();
      expect(done, isTrue);
    }
  });

  testWidgets('eval read failure keeps band rows and shows retry', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      _frame(
        FirstSyncScreen(
          onDone: () {},
          now: () => _now,
          readBand: () async => _receiving(),
          readSetupEvaluation: (_) async {
            retries++;
            throw StateError('eval unread');
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Verbunden'), findsOneWidget);
    expect(find.text('bis 06:54'), findsOneWidget);
    expect(find.text('Auswertung nicht geladen'), findsOneWidget);
    expect(find.text('Bandstatus nicht geladen'), findsNothing);
    await tester.tap(find.text('Erneut'));
    await tester.pump();
    expect(retries, greaterThan(1));
    await _unmount(tester);
  });

  testWidgets('band read failure does not claim disconnected', (tester) async {
    await tester.pumpWidget(
      _frame(
        FirstSyncScreen(
          onDone: () {},
          now: () => _now,
          readBand: () async => throw StateError('band unread'),
          readSetupEvaluation: (_) async => _eval(SetupEvalState.complete),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Verbunden'), findsNothing);
    expect(find.text('Bandstatus nicht geladen'), findsOneWidget);
    expect(find.text('07:12'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('partial injection throws instead of a silent mixed read', (
    tester,
  ) async {
    await tester.pumpWidget(
      _frame(
        FirstSyncScreen(
          onDone: () {},
          readBand: () async => const BandSnapshot(),
        ),
      ),
    );
    expect(tester.takeException(), isA<StateError>());
  });

  testWidgets('a later poll cannot keep yesterday evaluation', (tester) async {
    var now = DateTime(2026, 9, 15, 23, 59);
    final yesterday = Completer<SetupEvaluation>();
    final days = <String>[];
    await tester.pumpWidget(
      _frame(
        FirstSyncScreen(
          onDone: () {},
          now: () => now,
          readBand: () async => _receiving(),
          readSetupEvaluation: (day) async {
            days.add(day);
            if (day == '2026-09-15') return yesterday.future;
            return SetupEvaluation(
              day: day,
              currentAlgo: kAlgoVersion,
              state: SetupEvalState.missing,
            );
          },
        ),
      ),
    );
    await tester.pump();
    now = DateTime(2026, 9, 16, 0, 1);
    await tester.pump(const Duration(seconds: 3));
    yesterday.complete(_eval(SetupEvalState.complete));
    await tester.pump();
    expect(find.text('07:12'), findsNothing);
    expect(days, contains('2026-09-16'));
    await _unmount(tester);
  });

  testWidgets('a same-day read longer than one poll still publishes once', (
    tester,
  ) async {
    final slow = Completer<SetupEvaluation>();
    var inflight = 0;
    var maxInflight = 0;
    var done = false;
    await tester.pumpWidget(
      _frame(
        FirstSyncScreen(
          onDone: () => done = true,
          now: () => _now,
          readBand: () async => _receiving(),
          readSetupEvaluation: (_) async {
            inflight++;
            if (inflight > maxInflight) maxInflight = inflight;
            try {
              if (!slow.isCompleted) return await slow.future;
              return _eval(SetupEvalState.complete);
            } finally {
              inflight--;
            }
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('07:12'), findsNothing);
    expect(maxInflight, 1);
    await tester.tap(find.text('Weiter zum Profil'));
    await tester.pump();
    expect(done, isTrue);
    slow.complete(_eval(SetupEvalState.complete));
    await tester.pump();
    expect(find.text('07:12'), findsOneWidget);
    expect(maxInflight, 1);
    await _unmount(tester);
  });

  testWidgets('band is shown before a delayed evaluation completes', (
    tester,
  ) async {
    final slow = Completer<SetupEvaluation>();
    var inflight = 0;
    var maxInflight = 0;
    var done = false;
    await tester.pumpWidget(
      _frame(
        FirstSyncScreen(
          onDone: () => done = true,
          now: () => _now,
          readBand: () async => _receiving(),
          readSetupEvaluation: (_) async {
            inflight++;
            if (inflight > maxInflight) maxInflight = inflight;
            try {
              return await slow.future;
            } finally {
              inflight--;
            }
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Verbunden'), findsOneWidget);
    expect(find.text('bis 06:54'), findsOneWidget);
    expect(find.text('07:12'), findsNothing);
    expect(find.text('—'), findsOneWidget);
    expect(maxInflight, 1);
    await tester.tap(find.text('Weiter zum Profil'));
    await tester.pump();
    expect(done, isTrue);
    slow.complete(_eval(SetupEvalState.complete));
    await tester.pump();
    expect(find.text('07:12'), findsOneWidget);
    expect(find.text('bis 06:54'), findsOneWidget);
    expect(maxInflight, 1);
    await _unmount(tester);
  });

  testWidgets('English locale uses the English continue label', (tester) async {
    var done = false;
    await tester.pumpWidget(
      _frame(
        FirstSyncView(now: _now, onDone: () => done = true, band: _receiving()),
        locale: const Locale('en'),
      ),
    );
    expect(find.text('First transfer'), findsOneWidget);
    await tester.tap(find.text('Continue to profile'));
    await tester.pump();
    expect(done, isTrue);
  });

  testWidgets('non-today stored frontier includes the date', (tester) async {
    await tester.pumpWidget(
      _frame(
        FirstSyncView(
          now: _now,
          onDone: () {},
          band: BandSnapshot(
            connection: BandConnection.connected,
            latestStoredAt: DateTime(2026, 9, 14, 22, 10),
          ),
        ),
      ),
    );
    expect(find.textContaining('14.9.'), findsOneWidget);
    expect(find.textContaining('22:10'), findsOneWidget);
  });
}
