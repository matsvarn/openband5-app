import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'openband/controller.dart';
import 'openband/cycle.dart';
import 'openband/cycle_comparison.dart';
import 'openband/cycle_medians.dart';
import 'openband/health.dart';
import 'openband/journal.dart';
import 'openband/journal_editor.dart';
import 'openband/domain.dart';
import 'openband/nutrition_route.dart';
import 'openband/run_live.dart';
import 'openband/strength_live.dart';
import 'openband/template_editor.dart';
import 'openband/templates.dart';
import 'openband/session.dart';
import 'openband/screens.dart';
import 'openband/synthetic_repository.dart';
import 'notify/notification_prefs.dart';
import 'openband/appearance.dart';
import 'openband/notification_settings.dart';
import 'openband/theme.dart';
import 'openband/units.dart';
import 'state/units_controller.dart';
import 'theme/theme_controller.dart';
import 'openband/training.dart';
import 'compute/derivation_engine.dart' show kAlgoVersion;
import 'state/alarm_schedule.dart';
import 'ui2/app_shell.dart';
import 'ui2/onboarding/first_sync.dart';
import 'ui2/profile/alarm.dart';

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
  final repo = SyntheticOpenBandRepository.fromMaps(
    await load('day-summary'),
    await load('sleep-detail'),
    activity: await load('additional-flows'),
    run: await load('run-detail'),
  );
  await repo.seedNutritionGoals();
  repo.seedCaffeineSleepPattern('2026-09-15');
  return repo;
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
    now: () => DateTime(2026, 9, 18, 9, 41),
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
    builder: (c, domain) => switch (domain) {
      ShellDomain.home => OpenBandOverview(
        controller: controller,
        onProfile: () => _options(context),
        onNutrition: () => Navigator.of(c).push(
          MaterialPageRoute<void>(
            builder: (_) => OpenBandNutritionRoute(
              controller: controller,
              onBarcode: _syntheticBarcode,
            ),
          ),
        ),
        onSync: () {
          widget.repository.scenario = SyntheticScenario.complete;
          controller.updateBand(widget.repository.band);
          controller.refresh();
        },
      ),
      ShellDomain.health => OpenBandHealth(controller: controller),
      ShellDomain.workout => OpenBandTraining(
        controller: controller,
        onStart: (type) {
          if (type != 'running') return;
          final run = ValueNotifier(
            const LiveRun(
              elapsedSec: 962,
              distanceM: 2840,
              heartRate: 154,
              zone: 3,
              gps: true,
            ),
          );
          Navigator.of(c).push(
            MaterialPageRoute<void>(
              builder: (_) => OpenBandRunLive(
                run: run,
                onPause: () => run.value = LiveRun(
                  elapsedSec: run.value.elapsedSec,
                  pausedSec: run.value.pausedSec,
                  distanceM: run.value.distanceM,
                  heartRate: run.value.heartRate,
                  zone: run.value.zone,
                  gps: true,
                  paused: true,
                ),
                onResume: () => run.value = LiveRun(
                  elapsedSec: run.value.elapsedSec + 30,
                  pausedSec: run.value.pausedSec + 30,
                  distanceM: run.value.distanceM,
                  heartRate: run.value.heartRate,
                  zone: run.value.zone,
                  gps: true,
                ),
                onLap: () {},
                onFinish: () => Navigator.of(c).maybePop(),
              ),
            ),
          );
        },
        onOpenTemplates: () async {
          await Navigator.of(c).push(
            MaterialPageRoute<void>(
              builder: (_) => OpenBandTemplates(
                repository: widget.repository,
                synthetic: true,
                onStartTemplate: (t) => _openStrength(c, t),
                onEditTemplate: (t) => _openTemplateEditor(c, t),
              ),
            ),
          );
          controller.refresh();
        },
        onStartTemplate: (t) => _openStrength(c, t),
        onEditTemplate: (t) => _openTemplateEditor(c, t),
        onOpen: (s) => Navigator.of(c).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                OpenBandSession(repository: widget.repository, session: s),
          ),
        ),
      ),
      ShellDomain.wellness => OpenBandJournal(
        controller: controller,
        onEdit: (day) async {
          await Navigator.of(c).push(
            MaterialPageRoute<void>(
              builder: (_) => OpenBandJournalEditor(
                repository: widget.repository,
                day: day,
              ),
            ),
          );
          controller.refresh();
        },
        onNutrition: () => Navigator.of(c).push(
          MaterialPageRoute<void>(
            builder: (_) => OpenBandNutritionRoute(
              controller: controller,
              onBarcode: _syntheticBarcode,
            ),
          ),
        ),
      ),
    },
  );

  Future<void> _openStrength(BuildContext c, WorkoutTemplate t) {
    return Navigator.of(c).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            OpenBandStrengthLive(repository: widget.repository, template: t),
      ),
    );
  }

  Future<void> _openTemplateEditor(BuildContext c, WorkoutTemplate? t) async {
    await Navigator.of(c).push(
      MaterialPageRoute<WorkoutTemplate>(
        builder: (_) =>
            OpenBandTemplateEditor(repository: widget.repository, template: t),
      ),
    );
    controller.refresh();
  }

  Future<void> _syntheticBarcode(
    BuildContext ctx,
    String day,
    String meal,
  ) async {
    if (!ctx.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(ctx);
    messenger?.showSnackBar(
      SnackBar(
        content: Text('Galerie: Barcode-Scan nicht verfügbar · $meal · $day'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

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
                SyntheticScenario.missingNightHrv => 'Nacht ohne HRV-Verlauf',
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
          const ListTile(title: Text('Darstellung · synthetische Zustände')),
          ..._appearanceGalleryStates().map(
            (entry) => ListTile(
              title: Text(entry.$1),
              onTap: () {
                Navigator.pop(c);
                Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => entry.$2));
              },
            ),
          ),
          const ListTile(title: Text('Einheiten · synthetische Zustände')),
          ..._unitsGalleryStates().map(
            (entry) => ListTile(
              title: Text(entry.$1),
              onTap: () {
                Navigator.pop(c);
                Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => entry.$2));
              },
            ),
          ),
          const ListTile(
            title: Text('Erste Übertragung · synthetische Zustände'),
          ),
          ..._firstSyncGalleryStates().map(
            (entry) => ListTile(
              title: Text(entry.$1),
              onTap: () {
                Navigator.pop(c);
                Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => entry.$2()));
              },
            ),
          ),
          const ListTile(title: Text('Mitteilungen · synthetische Zustände')),
          ..._notificationGalleryStates().map(
            (entry) => ListTile(
              title: Text(entry.$1),
              onTap: () {
                Navigator.pop(c);
                Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => entry.$2));
              },
            ),
          ),
          const ListTile(title: Text('Zyklustage · synthetische Zustände')),
          ListTile(
            title: const Text('Zyklustage'),
            onTap: () {
              widget.repository.seedCycleMedianFixture();
              Navigator.pop(c);
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => OpenBandCycle(
                    repository: widget.repository,
                    day: '2026-09-15',
                    now: () => DateTime(2026, 9, 15, 9, 41),
                    synthetic: true,
                  ),
                ),
              );
            },
          ),
          ListTile(
            title: const Text('Zyklustage · Mediane'),
            onTap: () {
              widget.repository.seedCycleMedianFixture();
              Navigator.pop(c);
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => OpenBandCycleMedians(
                    repository: widget.repository,
                    day: '2026-09-15',
                    now: () => DateTime(2026, 9, 15, 9, 41),
                    synthetic: true,
                  ),
                ),
              );
            },
          ),
          ListTile(
            title: const Text('Zyklus · Vergleich'),
            onTap: () {
              widget.repository.seedCycleComparisonFixture();
              Navigator.pop(c);
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => OpenBandCycleComparison(
                    repository: widget.repository,
                    day: '2026-09-15',
                    now: () => DateTime(2026, 9, 15, 9, 41),
                    synthetic: true,
                  ),
                ),
              );
            },
          ),
          const ListTile(title: Text('Alarm · synthetische Zustände')),
          ..._alarmGalleryStates().map(
            (entry) => ListTile(
              title: Text(entry.$1),
              onTap: () {
                Navigator.pop(c);
                Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => entry.$2()));
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

final galleryFirstSyncNow = DateTime(2026, 9, 15, 9, 41);
final galleryFirstSyncStored = DateTime(2026, 9, 15, 6, 54);
final galleryFirstSyncComputed = DateTime(2026, 9, 15, 7, 12);

BandSnapshot galleryFirstSyncBand({bool receiving = true}) => BandSnapshot(
  connection: BandConnection.connected,
  transfer: receiving ? TransferState.receiving : TransferState.idle,
  latestStoredAt: galleryFirstSyncStored,
);

SetupEvaluation galleryFirstSyncEval(SetupEvalState state) => SetupEvaluation(
  day: '2026-09-15',
  currentAlgo: kAlgoVersion,
  storedAlgo: state == SetupEvalState.missing || state == SetupEvalState.stale
      ? (state == SetupEvalState.stale ? kAlgoVersion - 1 : null)
      : kAlgoVersion,
  computedAt: state == SetupEvalState.complete
      ? galleryFirstSyncComputed
      : null,
  state: state,
);

Widget firstSyncGalleryFrame({
  required Brightness brightness,
  BandSnapshot? band,
  SetupEvaluation? evaluation,
  bool bandError = false,
  bool evalError = false,
  bool receiving = true,
  SetupEvalState evalState = SetupEvalState.missing,
}) {
  final snapshot = band ?? galleryFirstSyncBand(receiving: receiving);
  final eval = evaluation ?? galleryFirstSyncEval(evalState);
  return Theme(
    data: openBandTheme(brightness),
    child: FirstSyncScreen(
      onDone: () {},
      now: () => galleryFirstSyncNow,
      synthetic: true,
      readBand: () async {
        if (bandError) throw StateError('band status unread');
        return snapshot;
      },
      readSetupEvaluation: (day) async {
        if (evalError) throw StateError('evaluation unread');
        return eval.day == day
            ? eval
            : SetupEvaluation(
                day: day,
                currentAlgo: kAlgoVersion,
                state: SetupEvalState.missing,
              );
      },
    ),
  );
}

List<(String, Widget Function())> _firstSyncGalleryStates() => [
  (
    'Erste Übertragung · Ausstehend',
    () => firstSyncGalleryFrame(brightness: Brightness.light),
  ),
  (
    'Erste Übertragung · Dunkel',
    () => firstSyncGalleryFrame(brightness: Brightness.dark),
  ),
  (
    'Erste Übertragung · Fertig',
    () => firstSyncGalleryFrame(
      brightness: Brightness.light,
      receiving: false,
      evalState: SetupEvalState.complete,
    ),
  ),
  (
    'Erste Übertragung · Teilweise',
    () => firstSyncGalleryFrame(
      brightness: Brightness.dark,
      evalState: SetupEvalState.partial,
    ),
  ),
  (
    'Erste Übertragung · Fehler',
    () => firstSyncGalleryFrame(brightness: Brightness.light, evalError: true),
  ),
];

final galleryAlarmNow = DateTime(2026, 9, 15, 9, 41);
final galleryAlarmAt = DateTime(2026, 9, 16, 7, 0);

List<AlarmScheduleEntry> galleryAlarmWeekdays() => [
  for (var w = 0; w < 5; w++)
    AlarmScheduleEntry(weekday: w, hour: 7, minute: 0, enabled: true),
];

List<AlarmScheduleEntry> galleryAlarmSchedule({bool enabled = true}) =>
    fillDefaultAlarmSchedule(enabled ? galleryAlarmWeekdays() : const []);

Widget _alarmGalleryTheme(Brightness brightness, Widget child) =>
    Theme(data: openBandTheme(brightness), child: child);

List<(String, Widget Function())> _alarmGalleryStates() => [
  (
    'Alarm · Im Band gespeichert',
    () => AlarmGallerySession(
      armedAt: galleryAlarmAt,
      state: AlarmArmState.storedSeconds,
    ),
  ),
  (
    'Alarm · Im Band gespeichert · Dunkel',
    () => _alarmGalleryTheme(
      Brightness.dark,
      AlarmGallerySession(
        armedAt: galleryAlarmAt,
        state: AlarmArmState.storedSeconds,
      ),
    ),
  ),
  (
    'Alarm · Bestätigung offen',
    () => AlarmGallerySession(
      armedAt: galleryAlarmAt,
      state: AlarmArmState.pending,
    ),
  ),
  (
    'Alarm · unbekannt',
    () => AlarmGallerySession(
      armedAt: galleryAlarmAt,
      state: AlarmArmState.unknown,
    ),
  ),
  ('Alarm · aus', () => const AlarmGallerySession(scheduleEnabled: false)),
  (
    'Alarm · Alarmplätze aus',
    () => AlarmGallerySession(
      armedAt: galleryAlarmAt,
      state: AlarmArmState.allSlotsInactive,
      scheduleEnabled: false,
    ),
  ),
  (
    'Alarm · Alarmplätze aus · Dunkel',
    () => _alarmGalleryTheme(
      Brightness.dark,
      AlarmGallerySession(
        armedAt: galleryAlarmAt,
        state: AlarmArmState.allSlotsInactive,
        scheduleEnabled: false,
      ),
    ),
  ),
  (
    'Alarm · Ausschalten offen',
    () => AlarmGallerySession(
      armedAt: galleryAlarmAt,
      state: AlarmArmState.offPending,
      scheduleEnabled: false,
    ),
  ),
  (
    'Alarm · Ausschalten offen · Dunkel',
    () => _alarmGalleryTheme(
      Brightness.dark,
      AlarmGallerySession(
        armedAt: galleryAlarmAt,
        state: AlarmArmState.offPending,
        scheduleEnabled: false,
      ),
    ),
  ),
  (
    'Alarm · Ausschalten offen · getrennt',
    () => AlarmGallerySession(
      armedAt: galleryAlarmAt,
      state: AlarmArmState.offPending,
      scheduleEnabled: false,
      connected: false,
    ),
  ),
  (
    'Alarm · Erneut ausschalten Fehler',
    () => AlarmGallerySession(
      armedAt: galleryAlarmAt,
      state: AlarmArmState.offPending,
      scheduleEnabled: false,
      failing: true,
    ),
  ),
  (
    'Alarm · getrennt',
    () => AlarmGallerySession(
      armedAt: galleryAlarmAt,
      state: AlarmArmState.unknown,
      connected: false,
    ),
  ),
  (
    'Alarm · Fehler',
    () => AlarmGallerySession(
      armedAt: galleryAlarmAt,
      state: AlarmArmState.pending,
      failing: true,
    ),
  ),
];

/// Isolated synthetic host: toggles and times update the visible schedule.
/// Production [AlarmScreen] still owns the real band/AppState.
class AlarmGallerySession extends StatefulWidget {
  final DateTime? armedAt;
  final AlarmArmState state;
  final bool connected;
  final bool scheduleEnabled;
  final bool failing;
  final DateTime? now;
  const AlarmGallerySession({
    super.key,
    this.armedAt,
    this.state = AlarmArmState.none,
    this.connected = true,
    this.scheduleEnabled = true,
    this.failing = false,
    this.now,
  });

  @override
  State<AlarmGallerySession> createState() => _AlarmGallerySessionState();
}

class _AlarmGallerySessionState extends State<AlarmGallerySession> {
  late DateTime? armedAt = widget.armedAt;
  late AlarmArmState state = widget.state;
  late List<AlarmScheduleEntry> schedule = galleryAlarmSchedule(
    enabled: widget.scheduleEnabled,
  );

  Future<void> _write() async {
    if (widget.failing) throw Exception('Schreiben fehlgeschlagen');
  }

  Future<void> _toggle(int weekday, bool enabled) async {
    await _write();
    setState(() {
      schedule = [
        for (final day in schedule)
          if (day.weekday == weekday) day.copyWith(enabled: enabled) else day,
      ];
    });
  }

  Future<void> _setTime(int weekday, int hour, int minute) async {
    await _write();
    setState(() {
      schedule = [
        for (final day in schedule)
          if (day.weekday == weekday)
            day.copyWith(hour: hour, minute: minute)
          else
            day,
      ];
    });
  }

  Future<void> _cancel() async {
    await _write();
    setState(() {
      state = AlarmArmState.offPending;
      schedule = galleryAlarmSchedule(enabled: false);
    });
  }

  @override
  Widget build(BuildContext context) => AlarmScreenView(
    armedAt: armedAt,
    now: widget.now ?? galleryAlarmNow,
    state: state,
    connected: widget.connected,
    schedule: schedule,
    synthetic: true,
    onToggleDay: _toggle,
    onSetDayTime: _setTime,
    onTest: armedAt == null ? null : _write,
    onCancel: _cancel,
  );
}

List<(String, Widget)> _appearanceGalleryStates() {
  return [
    (
      'Darstellung · System',
      const AppearanceSettingsView(
        selected: AppThemeChoice.system,
        synthetic: true,
      ),
    ),
    (
      'Darstellung · Dunkel',
      Theme(
        data: openBandTheme(Brightness.dark),
        child: const AppearanceSettingsView(
          selected: AppThemeChoice.dark,
          synthetic: true,
        ),
      ),
    ),
    (
      'Darstellung · Speichern fehlgeschlagen',
      AppearanceGallerySession(failing: true),
    ),
    (
      'Darstellung · Speichern fehlgeschlagen · Dunkel',
      Theme(
        data: openBandTheme(Brightness.dark),
        child: AppearanceSettingsView(
          selected: AppThemeChoice.dark,
          synthetic: true,
          saveError: 'Speichern fehlgeschlagen',
          onRetry: () {},
        ),
      ),
    ),
  ];
}

List<(String, Widget)> _unitsGalleryStates() {
  return [
    (
      'Einheiten · Metrisch',
      const UnitsSettingsView(selected: UnitSystem.metric, synthetic: true),
    ),
    (
      'Einheiten · Imperial',
      const UnitsSettingsView(selected: UnitSystem.imperial, synthetic: true),
    ),
    (
      'Einheiten · Dunkel',
      Theme(
        data: openBandTheme(Brightness.dark),
        child: const UnitsSettingsView(
          selected: UnitSystem.metric,
          synthetic: true,
        ),
      ),
    ),
    (
      'Einheiten · Imperial · Dunkel',
      Theme(
        data: openBandTheme(Brightness.dark),
        child: const UnitsSettingsView(
          selected: UnitSystem.imperial,
          synthetic: true,
        ),
      ),
    ),
    (
      'Einheiten · Speichern fehlgeschlagen',
      UnitsGallerySession(failing: true),
    ),
    (
      'Einheiten · Speichern fehlgeschlagen · Dunkel',
      Theme(
        data: openBandTheme(Brightness.dark),
        child: UnitsSettingsView(
          selected: UnitSystem.metric,
          synthetic: true,
          saveError: 'Speichern fehlgeschlagen',
          onRetry: () {},
        ),
      ),
    ),
  ];
}

/// Isolated host so gallery retry uses [UnitsController] without real prefs.
class UnitsGallerySession extends StatefulWidget {
  final UnitSystem initial;
  final bool failing;
  const UnitsGallerySession({
    super.key,
    this.initial = UnitSystem.metric,
    this.failing = false,
  });

  @override
  State<UnitsGallerySession> createState() => _UnitsGallerySessionState();
}

class _UnitsGallerySessionState extends State<UnitsGallerySession> {
  late final UnitsController units;
  late bool failNext = widget.failing;

  @override
  void initState() {
    super.initState();
    units = UnitsController.seed(
      widget.initial,
      persist: (_) async {
        if (failNext) {
          failNext = false;
          throw Exception('disk full');
        }
        return true;
      },
    );
  }

  @override
  void dispose() {
    units.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      UnitsSettings(controller: units, synthetic: true);
}

/// Isolated host so gallery retry uses [ThemeController] and the page
/// palette follows [ThemeController.effective], not the outer gallery mode.
class AppearanceGallerySession extends StatefulWidget {
  final AppThemeChoice initial;
  final bool failing;
  const AppearanceGallerySession({
    super.key,
    this.initial = AppThemeChoice.system,
    this.failing = false,
  });

  @override
  State<AppearanceGallerySession> createState() =>
      _AppearanceGallerySessionState();
}

class _AppearanceGallerySessionState extends State<AppearanceGallerySession> {
  late final ThemeController theme;
  late bool failNext = widget.failing;

  @override
  void initState() {
    super.initState();
    theme = ThemeController.seed(
      widget.initial,
      Brightness.light,
      persist: (_) async {
        if (failNext) {
          failNext = false;
          throw Exception('disk full');
        }
        return true;
      },
    );
  }

  @override
  void dispose() {
    theme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: theme,
    builder: (context, _) => Theme(
      data: openBandTheme(theme.effective),
      child: AppearanceSettings(controller: theme, synthetic: true),
    ),
  );
}

List<(String, Widget)> _notificationGalleryStates() {
  Future<void> ok(_) async {}
  return [
    (
      'Mitteilungen · hell',
      NotificationSettingsView(
        synthetic: true,
        prefs: openBandPaperNotificationPrefs,
        onChanged: ok,
      ),
    ),
    (
      'Mitteilungen · dunkel',
      Theme(
        data: openBandTheme(Brightness.dark),
        child: NotificationSettingsView(
          synthetic: true,
          prefs: openBandPaperNotificationPrefs,
          onChanged: ok,
        ),
      ),
    ),
    (
      'Mitteilungen · laden',
      const NotificationSettingsView(
        synthetic: true,
        loaded: false,
        granted: null,
      ),
    ),
    (
      'Mitteilungen · nicht erlaubt',
      NotificationSettingsView(
        synthetic: true,
        granted: false,
        prefs: openBandPaperNotificationPrefs,
        onChanged: ok,
        onRequestPermission: () {},
      ),
    ),
    (
      'Mitteilungen · Fehler',
      NotificationSettingsView(
        synthetic: true,
        prefs: const NotificationPrefs(waterEnabled: true),
        saveError: 'Speichern fehlgeschlagen',
        onChanged: ok,
        onRetrySave: () {},
      ),
    ),
    (
      'Mitteilungen · Anwenden fehlgeschlagen',
      NotificationSettingsView(
        synthetic: true,
        prefs: const NotificationPrefs(
          waterEnabled: true,
          healthEnabled: false,
        ),
        applyError: 'Gespeichert. Anwenden fehlgeschlagen',
        onChanged: ok,
        onRetryApply: () {},
      ),
    ),
    (
      'Mitteilungen · Ruhezeit',
      NotificationSettingsView(
        synthetic: true,
        prefs: const NotificationPrefs(
          quietEnabled: true,
          quietStartMin: 22 * 60,
          quietEndMin: 7 * 60,
          waterEnabled: true,
        ),
        onChanged: ok,
      ),
    ),
    (
      'Mitteilungen · Auswahl',
      NotificationSettingsView(
        synthetic: true,
        prefs: openBandPaperNotificationPrefs,
        onChanged: ok,
      ),
    ),
  ];
}
