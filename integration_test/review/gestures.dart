part of 'harness.dart';

Future<void> reviewGestures(ReviewHarness h) async {
  final tester = h.tester;
  for (final brightness in Brightness.values) {
    for (final phoneActions in [true, false]) {
      var chosen = DeviceAction.none;
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          debugShowCheckedModeBanner: false,
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: openBandTheme(brightness),
          home: StatefulBuilder(
            builder: (context, setState) => BandGesturesView(
              chosen: chosen,
              supported: {
                DeviceAction.none,
                ...DeviceAction.values.where((a) => a.isInApp),
                if (phoneActions) ...{
                  DeviceAction.ringPhone,
                  DeviceAction.torch,
                },
              },
              onPick: (value) => setState(() => chosen = value),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final state = phoneActions ? 'available' : 'unavailable';
      await h.capture('gestures-$state-${brightness.name}');
      if (phoneActions) {
        await h.press('Wasser protokollieren');
        expect(chosen, DeviceAction.logWater);
        await h.capture('gestures-selected-${brightness.name}');
      }
    }
  }

  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      debugShowCheckedModeBanner: false,
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: openBandTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: BandGesturesView(
        chosen: DeviceAction.none,
        supported: {
          DeviceAction.none,
          ...DeviceAction.values.where((a) => a.isInApp),
          DeviceAction.ringPhone,
          DeviceAction.torch,
        },
        onPick: (_) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
  await h.capture('gestures-large-text');
  await h.press('Taschenlampe');
  await h.capture('gestures-large-text-scrolled');
}
