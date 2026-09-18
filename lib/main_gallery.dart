import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'openband/controller.dart';
import 'openband/health.dart';
import 'openband/screens.dart';
import 'openband/synthetic_repository.dart';
import 'openband/theme.dart';
import 'openband/training.dart';
import 'ui2/app_shell.dart';

/// Separate entry point: no AppState, Bluetooth, real database or user profile.
Future<void> main() async {
  if (kReleaseMode) throw StateError('Die Galerie ist nur für Entwicklung.');
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de_DE');
  runApp(OpenBandGallery(repository: await loadGalleryRepository()));
}

Future<SyntheticOpenBandRepository> loadGalleryRepository() async {
  Future<Map> load(String name) async =>
      jsonDecode(
            await rootBundle.loadString(
              'docs/openband5/assets/fixtures/$name.json',
            ),
          )
          as Map;
  return SyntheticOpenBandRepository.fromMaps(
    await load('day-summary'),
    await load('sleep-detail'),
    activity: await load('additional-flows'),
  );
}

class OpenBandGallery extends StatefulWidget {
  final SyntheticOpenBandRepository repository;
  final bool showControls;
  final Brightness initialBrightness;
  final double? initialTextScale;
  const OpenBandGallery({
    super.key,
    required this.repository,
    this.showControls = true,
    this.initialBrightness = Brightness.light,
    this.initialTextScale,
  });
  @override
  State<OpenBandGallery> createState() => _OpenBandGalleryState();
}

class _OpenBandGalleryState extends State<OpenBandGallery> {
  late final controller = OpenBandController(
    repository: widget.repository,
    initialDay: '2026-09-15',
    band: widget.repository.band,
  );
  late bool dark = widget.initialBrightness == Brightness.dark;
  late double? scale = widget.initialTextScale;
  @override
  void initState() {
    super.initState();
    controller.refresh();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'OpenBand 5 · Synthetische Galerie',
    debugShowCheckedModeBanner: false,
    locale: const Locale('de'),
    supportedLocales: const [Locale('de')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: openBandTheme(Brightness.light),
    darkTheme: openBandTheme(Brightness.dark),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: scale == null
            ? MediaQuery.textScalerOf(context)
            : TextScaler.linear(scale!),
      ),
      child: child!,
    ),
    home: Builder(
      builder: (context) => !widget.showControls
          ? _shell(context)
          : Scaffold(
              body: Column(
                children: [
                  SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => _options(context),
                              child: const Text('Synthetische Galerie'),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Hell / Dunkel',
                            onPressed: () => setState(() => dark = !dark),
                            icon: Icon(
                              dark ? Icons.light_mode : Icons.dark_mode,
                            ),
                          ),
                          IconButton(
                            tooltip: scale == null
                                ? 'Schrift: System'
                                : 'Schrift: ${(scale! * 100).round()} %',
                            onPressed: () => setState(
                              () => scale = scale == null
                                  ? 1
                                  : scale == 1
                                  ? 1.5
                                  : scale == 1.5
                                  ? 2
                                  : null,
                            ),
                            icon: const Icon(Icons.text_fields),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      child: _shell(context),
                    ),
                  ),
                ],
              ),
            ),
    ),
  );
  Widget _shell(BuildContext context) => AppShell(
    builder: (c, domain) => domain == ShellDomain.home
        ? OpenBandOverview(
            controller: controller,
            onProfile: () => _options(context),
            onSync: () {
              widget.repository.scenario = SyntheticScenario.complete;
              controller.updateBand(widget.repository.band);
              controller.refresh();
            },
          )
        : domain == ShellDomain.wellness
        ? OpenBandHealth(controller: controller)
        : domain == ShellDomain.workout
        ? OpenBandTraining(controller: controller, onStart: (_) {})
        : Center(child: Text('${domain.label} · nächstes Arbeitspaket')),
  );

  Future<void> _options(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (c) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(
            title: Text('Nur synthetische Daten'),
            subtitle: Text(
              'Keine Verbindung zum Band oder zur persönlichen Datenbank.',
            ),
          ),
          ...SyntheticScenario.values.map(
            (scenario) => ListTile(
              title: Text(switch (scenario) {
                SyntheticScenario.dense => 'Dichte Nacht',
                SyntheticScenario.complete => 'Vollständige Nacht',
                SyntheticScenario.partial => 'Teilnacht · 24 Minuten Lücke',
                SyntheticScenario.missing => 'Keine Nacht',
                SyntheticScenario.processing => 'Auswertung läuft',
                SyntheticScenario.disconnected => 'Band getrennt',
                SyntheticScenario.interrupted => 'Übertragung unterbrochen',
                SyntheticScenario.saveFailure => 'Speichern schlägt fehl',
                SyntheticScenario.draftFailure =>
                  'Entwurf kann nicht gesichert werden',
                SyntheticScenario.calculationFailure =>
                  'Auswertung schlägt fehl',
              }),
              selected: scenario == widget.repository.scenario,
              onTap: () {
                widget.repository.scenario = scenario;
                controller.updateBand(widget.repository.band);
                controller.refresh();
                Navigator.pop(c);
              },
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Schließen'),
          ),
        ],
      ),
    ),
  );
}
