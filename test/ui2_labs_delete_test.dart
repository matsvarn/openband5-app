// LABS, REMOVABLE — OpenBand Laborwerte.
//
// Removing a RESULT destroys a reading. Removing a MARKER is refused while
// it still labels one.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/data/lab_catalogue.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/labs.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';

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
);

Future<void> _pump(WidgetTester t, SyntheticOpenBandRepository repo) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('de')],
      theme: openBandTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: OpenBandLabs(
        repository: repo,
        now: () => DateTime(2026, 9, 18, 9, 41),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('de_DE'));

  testWidgets('the confirm names the reading, and cancel keeps it', (t) async {
    final repo = _repo();
    await _pump(t, repo);
    await t.tap(find.byKey(const ValueKey('lab-ferritin')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('lab-hist-2026-09-15')));
    await t.pumpAndSettle();
    await t.tap(find.text('Wert entfernen'));
    await t.pumpAndSettle();
    expect(find.textContaining('52'), findsWidgets);
    await t.tap(find.text('Abbrechen'));
    await t.pumpAndSettle();
    final snap = await repo.readLabs();
    expect(
      snap.results.where(
        (r) => r.marker == 'ferritin' && r.takenOn == '2026-09-15',
      ),
      isNotEmpty,
    );
  });

  testWidgets('a removed result leaves the store and the screen', (t) async {
    final repo = _repo();
    await _pump(t, repo);
    await t.tap(find.byKey(const ValueKey('lab-ferritin')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('lab-hist-2026-09-15')));
    await t.pumpAndSettle();
    await t.tap(find.text('Wert entfernen'));
    await t.pumpAndSettle();
    await t.tap(find.text('Wert entfernen').last);
    await t.pumpAndSettle();
    expect(
      (await repo.readLabs()).results.where(
        (r) => r.marker == 'ferritin' && r.takenOn == '2026-09-15',
      ),
      isEmpty,
    );
  });

  testWidgets('a marker is refused while it still labels a reading', (t) async {
    final repo = _repo();
    await repo.saveLabMarkerDef(
      const LabMarkerDef(
        key: 'custom_kupfer',
        label: 'Kupfer',
        unit: 'µg/dL',
        category: 'other',
        decimals: 1,
      ),
    );
    await repo.saveLabDraw(
      const LabDraw(
        marker: 'custom_kupfer',
        takenOn: '2026-09-15',
        value: 90,
        unit: 'µg/dL',
      ),
    );
    await _pump(t, repo);
    await t.tap(find.text('Eigene Marker'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Kupfer entfernen'));
    await t.pumpAndSettle();
    expect(find.text('Kupfer entfernen?'), findsNothing);
    expect(find.textContaining('hat noch Ergebnisse'), findsOneWidget);
    expect((await repo.readLabs()).custom, isNotEmpty);
  });

  testWidgets('an empty custom marker can be removed', (t) async {
    final repo = _repo();
    await repo.saveLabMarkerDef(
      const LabMarkerDef(
        key: 'custom_kupfer',
        label: 'Kupfer',
        unit: 'µg/dL',
        category: 'other',
        decimals: 1,
      ),
    );
    await _pump(t, repo);
    await t.tap(find.text('Eigene Marker'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Kupfer entfernen'));
    await t.pumpAndSettle();
    expect(find.text('Kupfer entfernen?'), findsOneWidget);
    await t.tap(find.text('Entfernen'));
    await t.pumpAndSettle();
    expect((await repo.readLabs()).custom, isEmpty);
  });

  test('builtin catalogue is unchanged', () {
    expect(kLabMarkersByKey['ferritin']!.unit, 'ng/mL');
  });
}
