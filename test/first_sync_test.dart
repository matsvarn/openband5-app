// Erste Übertragung — the onboarding step between pairing and profile.
//
// The rows only report observed band state: a receiving transfer shows the
// stored frontier, an idle band with nothing stored shows three honest '—',
// and the continue button never blocks on sync progress.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/ui2/onboarding/first_sync.dart';

Widget _frame(Widget child) =>
    MaterialApp(theme: openBandTheme(Brightness.light), home: child);

Future<void> _unmount(WidgetTester tester) async {
  // The screen polls on a timer; unmounting disposes it so the harness does
  // not report a pending Timer at test end.
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting();
  });

  testWidgets('a receiving transfer shows the stored frontier', (tester) async {
    var done = false;
    await tester.pumpWidget(
      _frame(
        FirstSyncScreen(
          onDone: () => done = true,
          readBand: () async => BandSnapshot(
            connection: BandConnection.connected,
            transfer: TransferState.receiving,
            latestStoredAt: DateTime(2026, 9, 15, 7, 42),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Erste Übertragung'), findsOneWidget);
    expect(find.text('Nacht wird gelesen'), findsOneWidget);
    expect(find.textContaining('bis'), findsWidgets);
    expect(find.text('Verbunden'), findsOneWidget);
    expect(find.text('Auswertung'), findsOneWidget);

    await tester.tap(find.text('Weiter zum Profil'));
    await tester.pump();
    expect(done, isTrue);
    await _unmount(tester);
  });

  testWidgets('an idle band with nothing stored shows three dashes', (
    tester,
  ) async {
    var done = false;
    await tester.pumpWidget(
      _frame(
        FirstSyncScreen(
          onDone: () => done = true,
          readBand: () async => const BandSnapshot(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('—'), findsNWidgets(3));

    // The step never blocks: even with nothing received, Weiter works.
    await tester.tap(find.text('Weiter zum Profil'));
    await tester.pump();
    expect(done, isTrue);
    await _unmount(tester);
  });
}
