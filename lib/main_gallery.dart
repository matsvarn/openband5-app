import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'openband/controller.dart';
import 'openband/cycle.dart';
import 'openband/cycle_comparison.dart';
import 'openband/cycle_medians.dart';
import 'openband/health.dart';
import 'openband/g3/screens/journal_screen.dart';
import 'openband/journal.dart';
import 'openband/journal_editor.dart';
import 'openband/domain.dart';
import 'openband/g3/screens/band.dart';
import 'openband/g3/chrome.dart' show showOBInfoSheet;
import 'openband/nutrition_route.dart';
import 'openband/run_live.dart';
import 'openband/session.dart';
import 'openband/exercise_picker.dart';
import 'openband/template_editor.dart';
import 'openband/strength_live.dart';
import 'openband/training.dart';
import 'openband/templates.dart';
import 'openband/release_scope.dart';
import 'openband/g3/screens/heute.dart';
import 'openband/g3/screens/heute_routes.dart';
import 'openband/screens.dart';
import 'openband/g3/screens/sleep.dart';
import 'openband/synthetic_repository.dart';
import 'notify/notification_prefs.dart';
import 'openband/appearance.dart';
import 'openband/notification_settings.dart';
import 'openband/theme.dart';
import 'openband/units.dart';
import 'state/units_controller.dart';
import 'theme/theme_controller.dart';
import 'openband/g3/screens/training_screen.dart';
import 'openband/g3/screens/training_live.dart';
import 'openband/g3/screens/training_manual.dart';
import 'compute/derivation_engine.dart' show kAlgoVersion;
import 'data/auto_backup.dart' show BackupCadence;
import 'state/alarm_schedule.dart';
import 'ui2/app_shell.dart';
import 'ui2/onboarding/first_sync.dart';
import 'ui2/onboarding/welcome.dart' show ImportOutcome;
import 'ui2/profile/alarm.dart';
import 'ui2/profile/data.dart';
import 'ui2/profile/profile.dart';
import 'ui2/profile/settings.dart' show MoreSettingsView;

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

  /// Full gallery by default. The release scenario uses the same reduced
  /// surface as a production build, without a personal database or Bluetooth.
  final bool releaseReduced;
  const OpenBandGallery({
    super.key,
    required this.repository,
    this.showControls = true,
    this.initialBrightness = Brightness.light,
    this.initialTextScale,
    this.releaseReduced = false,
  });
  @override
  State<OpenBandGallery> createState() => _OpenBandGalleryState();
}

class _OpenBandGalleryState extends State<OpenBandGallery> {
  final _heuteReminder = MemoryHeuteReminder();
  static const _day = '2026-09-15', _g3Day = '2026-09-29';
  static final _dayNow = DateTime(2026, 9, 18, 9, 41);
  static final _g3Now = DateTime(2026, 9, 29, 9, 41);
  DateTime _clock = _dayNow;
  late final controller = OpenBandController(
    repository: widget.repository,
    initialDay: _day,
    band: widget.repository.band,
    now: () => _clock,
  );

  /// The G3 scenarios hold 29.09 only: the gallery clock and the selected
  /// day follow them so Heute shows that day as today with its note and
  /// check-in. Other scenarios keep the 18.09 clock.
  void _useScenario(SyntheticScenario scenario) {
    widget.repository.scenario = scenario;
    final g3 =
        scenario == SyntheticScenario.g3Sample ||
        scenario == SyntheticScenario.g3Building;
    _clock = g3 ? _g3Now : _dayNow;
    controller.updateBand(widget.repository.band);
    if (g3 && controller.selectedDay != _g3Day) {
      controller.selectDay(_g3Day);
    } else if (!g3 && controller.selectedDay == _g3Day) {
      controller.selectDay(_day);
    } else {
      controller.refresh();
    }
  }

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
    domains: widget.releaseReduced ? kOpenBandReleaseDomains : null,
    releaseStyle: widget.releaseReduced,
    onSelect: (domain) {
      if (domain == ShellDomain.health) controller.refresh();
    },
    builder: (c, domain) => switch (domain) {
      ShellDomain.home => OpenBandHeute(
        controller: controller,
        reminder: _heuteReminder,
        onProfile: widget.releaseReduced
            ? () => _openSyntheticProfile(c, backLabel: 'Heute')
            : () => _options(context),
        onBand: () => showBandStatus(c, controller, null),
        onConnect: () => _useScenario(SyntheticScenario.g3Sample),
        onOpenMetric: (m) => openHeuteMetric(c, controller, m),
        onOpenActivity: (activity) =>
            openHeuteActivity(c, controller, activity),
      ),
      ShellDomain.health => OpenBandHealth(controller: controller),
      ShellDomain.sleep => G3SleepScreen(
        controller: controller,
        asTab: true,
        onBand: () => showBandStatus(c, controller, null),
        onProfile: () => _openSyntheticProfile(c, backLabel: 'Schlaf'),
      ),
      ShellDomain.workout =>
        !widget.releaseReduced
            ? Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => pushFullScreen(
                        c,
                        MaterialPageRoute<void>(
                          builder: (_) => OpenBandExercisePicker(
                            repository: widget.repository,
                          ),
                        ),
                      ),
                      child: const Text('Übungsbibliothek'),
                    ),
                  ),
                  Expanded(
                    child: OpenBandTraining(
                      controller: controller,
                      onStart: (type) => type == 'weight_training'
                          ? _openGalleryTemplates(c)
                          : _openSyntheticRun(c, type),
                      onStartTemplate: (template) => _openStrength(c, template),
                      onEditTemplate: (template) =>
                          _openTemplateEditor(c, template),
                      onOpenTemplates: () => _openGalleryTemplates(c),
                      onOpen: (session) => pushFullScreen(
                        c,
                        MaterialPageRoute<void>(
                          builder: (_) => OpenBandSession(
                            repository: widget.repository,
                            session: session,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : G3TrainingScreen(
                controller: controller,
                onProfile: () =>
                    _openSyntheticProfile(c, backLabel: 'Training'),
                onStart: (type) {
                  if (type != 'running') return;
                  _openSyntheticRun(c, type);
                },
                onManual: () async {
                  await pushFullScreen<G3ManualSaved>(
                    c,
                    MaterialPageRoute<G3ManualSaved>(
                      builder: (_) => G3ManualFlow(
                        recentRepository: widget.repository,
                        now: () => _clock,
                        initialSpans: const [],
                      ),
                    ),
                  );
                },
              ),
      ShellDomain.wellness =>
        widget.releaseReduced
            ? G3JournalScreen(
                controller: controller,
                onBand: () => showBandStatus(c, controller, null),
                onProfile: () => _openSyntheticProfile(c, backLabel: 'Journal'),
                onEdit: (day) async {
                  await Navigator.of(c).push(
                    MaterialPageRoute<void>(
                      builder: (_) => G3JournalComposeRoute(
                        repository: widget.repository,
                        day: day,
                      ),
                    ),
                  );
                  controller.refresh();
                },
              )
            : OpenBandJournal(
                controller: controller,
                releaseReduced: widget.releaseReduced,
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

  Future<void> _openGalleryTemplates(BuildContext c) => pushFullScreen(
    c,
    MaterialPageRoute<void>(
      builder: (_) => OpenBandTemplates(
        repository: widget.repository,
        onStartTemplate: (template) => _openStrength(c, template),
        onEditTemplate: (template) => _openTemplateEditor(c, template),
        synthetic: true,
      ),
    ),
  );

  void _openSyntheticRun(BuildContext c, String type) {
    final zoneSet = ana.HeartRateZones.zonesFromMaxHr(186, source: 'tanaka');
    final run = ValueNotifier(
      LiveRun(
        elapsedSec: 962,
        distanceM: type == 'running' ? 2840 : null,
        heartRate: 141,
        zone: zoneSet.zoneNumber(141),
        zoneSet: zoneSet,
        strain: 3.8,
        maxHrSeen: 158,
        averageHr: 136,
        gps: type == 'running',
      ),
    );
    pushFullScreen(
      c,
      MaterialPageRoute<void>(
        builder: (_) => G3LiveRun(
          run: run,
          sport: type,
          onPause: () => run.value = LiveRun(
            elapsedSec: run.value.elapsedSec,
            pausedSec: run.value.pausedSec,
            distanceM: run.value.distanceM,
            heartRate: run.value.heartRate,
            zone: run.value.zone,
            zoneSet: run.value.zoneSet,
            strain: run.value.strain,
            maxHrSeen: run.value.maxHrSeen,
            averageHr: run.value.averageHr,
            gps: run.value.gps,
            paused: true,
          ),
          onResume: () => run.value = LiveRun(
            elapsedSec: run.value.elapsedSec + 30,
            pausedSec: run.value.pausedSec + 30,
            distanceM: run.value.distanceM,
            heartRate: run.value.heartRate,
            zone: run.value.zone,
            zoneSet: run.value.zoneSet,
            strain: run.value.strain,
            maxHrSeen: run.value.maxHrSeen,
            averageHr: run.value.averageHr,
            gps: run.value.gps,
          ),
          onFinish: () async {
            Navigator.of(c, rootNavigator: true).maybePop();
          },
          onDiscard: () async {
            Navigator.of(c, rootNavigator: true).maybePop();
          },
        ),
      ),
    );
  }

  Future<void> _openStrength(BuildContext c, WorkoutTemplate t) {
    return pushFullScreen(
      c,
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

  void _openSyntheticProfile(
    BuildContext context, {
    String backLabel = 'Heute',
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (profileContext) => ProfileHomeView(
          releaseReduced: true,
          backLabel: backLabel,
          stats: const ProfileStats(
            name: 'Mats',
            sources: 1,
            storageBytes: 4509715661,
          ),
          user: const {
            'name': 'Mats',
            'birth_date': '1995-09-21',
            'height_cm': 182.0,
            'weight_kg': 78.4,
          },
          band: widget.repository.band,
          bandName: 'WHOOP 5.0',
          languageLabel: 'Deutsch',
          onLanguage: () => showOBInfoSheet(
            profileContext,
            title: 'Sprache',
            paragraphs: const [
              'Die synthetische Galerie zeigt Deutsch. Die App bietet die Sprachauswahl im Profil.',
            ],
          ),
          onBand: () => Navigator.of(profileContext).push(
            MaterialPageRoute<void>(
              builder: (_) => G3BandScreen(
                band: widget.repository.band,
                now: DateTime(2026, 9, 18, 9, 41),
                databaseSize: '4,2 GB',
              ),
            ),
          ),
          onData: () => _openSyntheticData(profileContext),
          onNotifications: () => Navigator.of(profileContext).push(
            MaterialPageRoute<void>(
              builder: (_) => NotificationSettingsView(
                synthetic: true,
                prefs: openBandPaperNotificationPrefs,
                onChanged: (_) async {},
              ),
            ),
          ),
          onSettings: () => Navigator.of(profileContext).push(
            MaterialPageRoute<void>(
              builder: (_) => const MoreSettingsView(releaseReduced: true),
            ),
          ),
        ),
      ),
    );
  }

  void _openSyntheticData(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const _SyntheticDataHost()));
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
                SyntheticScenario.g3Sample => 'G3 · Tagesblatt',
                SyntheticScenario.g3Building => 'G3 · Basis im Aufbau',
              }),
              selected: scenario == widget.repository.scenario,
              onTap: () {
                _useScenario(scenario);
                Navigator.pop(c);
              },
            ),
          ),
          const ListTile(title: Text('Profil & Daten · synthetische Zustände')),
          ListTile(
            key: const ValueKey('gallery-profile'),
            title: const Text('Profil · reduziert'),
            onTap: () {
              Navigator.pop(c);
              _openSyntheticProfile(context);
            },
          ),
          ListTile(
            key: const ValueKey('gallery-data'),
            title: const Text('Daten & Sicherung · reduziert'),
            onTap: () {
              Navigator.pop(c);
              _openSyntheticData(context);
            },
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
          if (!widget.releaseReduced)
            const ListTile(title: Text('Zyklustage · synthetische Zustände')),
          if (!widget.releaseReduced)
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
          if (!widget.releaseReduced)
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
          if (!widget.releaseReduced)
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
          if (!widget.releaseReduced)
            const ListTile(title: Text('Übungen · synthetische Zustände')),
          if (!widget.releaseReduced)
            ListTile(
              title: const Text('Übung · Kopieren'),
              onTap: () async {
                Navigator.pop(c);
                await widget.repository.createCustomExercise(
                  CustomExerciseDraft(
                    id: 'gallery-curl',
                    label: 'Kurzhantel-Curl',
                    mode: ExerciseCaptureMode.repetitions,
                    equipment: ExerciseEquipmentCategory.dumbbell,
                    loadBasis: ExerciseLoadBasis.perDevice,
                    deviceCount: 2,
                    repetitionBasis: ExerciseRepetitionBasis.perSide,
                    primaryMuscles: const ['biceps'],
                    secondaryMuscles: const ['forearms'],
                  ),
                );
                if (!context.mounted) return;
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        OpenBandExercisePicker(repository: widget.repository),
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

/// Stateful synthetic collaborator for the production Data composition. It
/// never opens a database, share sheet, picker, or personal storage.
class _SyntheticDataHost extends StatefulWidget {
  const _SyntheticDataHost();

  @override
  State<_SyntheticDataHost> createState() => _SyntheticDataHostState();
}

class _SyntheticDataHostState extends State<_SyntheticDataHost> {
  BackupCadence _cadence = BackupCadence.off;
  DateTime? _lastBackupAt;
  String? _note;
  bool _failed = false;
  bool _databaseFailedOnce = false;
  ImportOutcome? _outcome;

  void _receipt(String text, {bool failed = false}) {
    setState(() {
      _note = text;
      _failed = failed;
      _outcome = null;
    });
  }

  void _exportDatabase() {
    if (!_databaseFailedOnce) {
      _databaseFailedOnce = true;
      _receipt(
        'Export konnte nicht erstellt werden: synthetischer Schreibfehler.',
        failed: true,
      );
      return;
    }
    _receipt('Export erstellt');
  }

  void _cycleCadence() {
    setState(() {
      _cadence = BackupCadence
          .values[(_cadence.index + 1) % BackupCadence.values.length];
      _note = _cadence == BackupCadence.off
          ? 'Automatische Sicherung aus'
          : 'Sicherung erstellt';
      _failed = false;
      _outcome = null;
      if (_cadence != BackupCadence.off) {
        _lastBackupAt = DateTime(2026, 9, 18, 9, 41);
      }
    });
  }

  void _backup() {
    setState(() {
      _lastBackupAt = DateTime(2026, 9, 18, 9, 41);
      _note = 'Sicherung erstellt';
      _failed = false;
      _outcome = null;
    });
  }

  void _import() {
    setState(() {
      _note = null;
      _failed = false;
      _outcome = const ImportOutcome(source: 'Synthetische Sicherung', days: 3);
    });
  }

  @override
  Widget build(BuildContext context) => DataScreenView(
    cadence: _cadence,
    lastBackupAt: _lastBackupAt,
    note: _note,
    noteFailed: _failed,
    outcome: _outcome,
    onExportDatabase: _exportDatabase,
    onExportEncrypted: () => _receipt('Export erstellt'),
    onExportCsv: () => _receipt('Export erstellt'),
    onCadence: _cycleCadence,
    onBackupNow: _backup,
    onImport: _import,
    onReanalyze: () => _receipt('3 Tage neu berechnet'),
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
