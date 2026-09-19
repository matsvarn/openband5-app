import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'openband/controller.dart';
import 'openband/health.dart';
import 'openband/journal.dart';
import 'openband/domain.dart';
import 'openband/nutrition.dart';
import 'openband/run_live.dart';
import 'openband/strength_live.dart';
import 'openband/template_editor.dart';
import 'openband/session.dart';
import 'openband/screens.dart';
import 'openband/synthetic_repository.dart';
import 'openband/theme.dart';
import 'openband/training.dart';
import 'state/alarm_schedule.dart';
import 'ui2/app_shell.dart';
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
  return SyntheticOpenBandRepository.fromMaps(
    await load('day-summary'),
    await load('sleep-detail'),
    activity: await load('additional-flows'),
    run: await load('run-detail'),
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
        onStartTemplate: (t) => Navigator.of(c).push(
          MaterialPageRoute<void>(
            builder: (_) => OpenBandStrengthLive(
              repository: widget.repository,
              template: t,
            ),
          ),
        ),
        onEditTemplate: (t) async {
          await Navigator.of(c).push(
            MaterialPageRoute<WorkoutTemplate>(
              builder: (_) => OpenBandTemplateEditor(
                repository: widget.repository,
                template: t,
              ),
            ),
          );
          controller.refresh();
        },
        onOpen: (s) => Navigator.of(c).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                OpenBandSession(repository: widget.repository, session: s),
          ),
        ),
      ),
      ShellDomain.wellness => OpenBandJournal(
        controller: controller,
        onNutrition: () => Navigator.of(c).push(
          MaterialPageRoute<void>(
            builder: (ctx) => OpenBandNutrition(
              controller: controller,
              onAdd: (meal) => _addFood(ctx, meal),
            ),
          ),
        ),
      ),
    },
  );

  Future<void> _addFood(BuildContext ctx, String meal) async {
    final day = controller.selectedDay;
    final existing = await widget.repository.readMealDraft(day, meal);
    if (!ctx.mounted) return;
    final draft = await showModalBottomSheet<MealDraft>(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => OBFoodSearchSheet(
        repository: widget.repository,
        draft:
            existing ??
            MealDraft(
              id: 'draft-$day-$meal',
              day: day,
              meal: meal,
              entries: const [],
              updatedAt: DateTime.now(),
            ),
      ),
    );
    if (draft == null || !ctx.mounted) return;
    await widget.repository.saveMealDraft(draft);
    if (!ctx.mounted) return;
    final saved = await showOpenBandMealDraft(ctx, widget.repository, draft);
    if (saved == true) controller.refresh();
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
          const ListTile(title: Text('Alarm · synthetische Zustände')),
          ..._alarmGalleryStates().map(
            (entry) => ListTile(
              title: Text(entry.$1),
              onTap: () {
                Navigator.pop(c);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => entry.$2()),
                );
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

final galleryAlarmNow = DateTime(2026, 9, 18, 9, 41);
final galleryAlarmAt = DateTime(2026, 9, 19, 7, 0);

List<AlarmScheduleEntry> galleryAlarmSchedule({bool enabled = true}) =>
    fillDefaultAlarmSchedule(
      enabled
          ? const [
              AlarmScheduleEntry(weekday: 5, hour: 7, minute: 0, enabled: true),
              AlarmScheduleEntry(
                weekday: 2,
                hour: 6,
                minute: 30,
                enabled: true,
              ),
            ]
          : const [],
    );

List<(String, Widget Function())> _alarmGalleryStates() => [
      (
        'Alarm · bestätigt',
        () => AlarmGallerySession(
          armedAt: galleryAlarmAt,
          state: AlarmArmState.confirmed,
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
      (
        'Alarm · aus',
        () => const AlarmGallerySession(
          scheduleEnabled: false,
        ),
      ),
      (
        'Alarm · getrennt',
        () => AlarmGallerySession(
          armedAt: galleryAlarmAt,
          state: AlarmArmState.confirmed,
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
  late List<AlarmScheduleEntry> schedule =
      galleryAlarmSchedule(enabled: widget.scheduleEnabled);

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
      armedAt = null;
      state = AlarmArmState.none;
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
