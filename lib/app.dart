import 'dart:async';
import 'openband/controller.dart';
import 'openband/domain.dart';
import 'openband/local_repository.dart';
import 'openband/health.dart';
import 'openband/journal.dart';
import 'openband/journal_editor.dart';
import 'openband/cycle.dart';
import 'openband/medication.dart';
import 'openband/nutrition_route.dart';
import 'openband/run_live.dart';
import 'openband/release_scope.dart';
import 'openband/screens.dart';
import 'openband/session.dart';
import 'openband/strength_live.dart';
import 'openband/template_editor.dart';
import 'openband/templates.dart';
import 'openband/training.dart';
import 'openband/theme.dart' show openBandTheme;
import 'data/day_label.dart';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import 'ai/briefing.dart' show BriefingPeriod;
import 'coach/coach_config.dart';
import 'l10n/app_localizations.dart';
import 'notify/notification_service.dart';
import 'notify/tap_router.dart';
import 'state/app_state.dart';
import 'state/locale_controller.dart';
import 'state/prefs.dart';
import 'telemetry/telemetry_service.dart';
import 'theme/theme_controller.dart';
import 'theme/theme_switcher.dart';
import 'widget/widget_service.dart';
import 'ui2/activity/catalogue.dart';
import 'ui2/activity/live.dart';
import 'ui2/activity/tiles.dart' show mapTilesAllowed;
import 'ui2/onboarding/first_sync.dart';
import 'ui2/onboarding/pairing.dart' show OnboardingBypass;
import 'ui2/onboarding/profile_setup.dart';
import 'ui2/pairing/device_picker.dart';
import 'ui2/onboarding/splash.dart';
import 'ui2/onboarding/welcome.dart';
import 'ui2/profile/alarm.dart';
import 'ui2/profile/profile.dart';
import 'ui2/screens/ai_briefing.dart';
import 'ui2/screens/calm_breathing.dart';
import 'ui2/screens/what_changed.dart';
import 'ui2/screens/log_workout.dart';
import 'ui2/screens/log_food.dart';
import 'ui2/screens/workout_screen.dart';
import 'ui2/ui2.dart';

class OpenStrapApp extends StatefulWidget {
  const OpenStrapApp({super.key});
  @override
  State<OpenStrapApp> createState() => _OpenStrapAppState();
}

class _OpenStrapAppState extends State<OpenStrapApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Hand the BYOK provider config to AppState (briefing generation + the
    // key-aware AI notification schedule live there).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppState>().attachCoachConfig(context.read<CoachConfig>());

      final app = context.read<AppState>();
      if (app.isPaired) app.openSession();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    // Keep the app in sync with the OS when the user is on "System".
    context.read<ThemeController>().updatePlatformBrightness(
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final app = context.read<AppState>();
    if (state == AppLifecycleState.resumed) {
      // The user may have flipped our notification switch either way in OS
      // Settings while we were backgrounded. Drop the cached authorization
      // decision so the next present/schedule re-reads reality — a denial used
      // to latch for the whole process, silencing every notification and
      // scheduled reminder until a full app restart.
      NotificationService.instance.invalidatePermissionCache();
      // A background relaunch while the phone was locked cannot read the
      // keychain, so the BYOK key can be missing from an otherwise healthy
      // process. Coming to the foreground means the phone is unlocked — take
      // the chance to read it. No-op unless a key is known to exist and is
      // currently unreadable.
      unawaited(context.read<CoachConfig>().refreshKeyOnResume());
      app.maybeFinishFromLiveActivity();
      unawaited(app.maybeStopBreathingFromLiveActivity());
      app.refreshAppStatus(); // re-check OTA + admin banner on every foreground
      app.runCadenceChecks(); // evening wind-down / weekly recap nudges (best-effort)
      // A Siri "start breathing" App Intent may have just foregrounded an
      // already-running process (openAppWhenRun doesn't guarantee a fresh
      // launch) — the constructor-time check alone would miss that case.
      unawaited(app.checkPendingSiriRoute());
      // Backups run on foreground, when due — there is no background scheduler
      // that works on both platforms, and a schedule that claims "daily" while
      // delivering whenever the OS feels like it is worse than one that is
      // honest about when it fires.
      unawaited(app.runBackupIfDue());
      // Re-publish the widget snapshot. `has_data` is decided WHEN THE
      // SNAPSHOT IS WRITTEN (WidgetService.push evaluates isStale there), and
      // the widget process never runs Dart — so a snapshot written while fresh
      // stays `has_data: true` forever, and the staleness rule can only ever
      // fire if something re-evaluates it. Foreground is the one moment we
      // know the app is alive and the numbers may have aged: it is cheap (one
      // repository read) and it is what stops a week-old readiness sitting on
      // a lock screen looking current.
      unawaited(WidgetService.refresh(app.repo));
      if (app.isPaired) app.openSession();
    } else if (state == AppLifecycleState.paused) {
      // Backgrounded: hand the band to the iOS restore path so it can wake-and-drain
      // in the background (no-op on Android, where the foreground service holds it).
      app.pauseForBackground();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    final locale = context.watch<LocaleController>();
    return MaterialApp(
      title: 'OpenBand 5',
      debugShowCheckedModeBanner: false,
      // The palette is the design system's, the CHOICE is still the user's.
      theme: openBandTheme(Brightness.light),
      darkTheme: openBandTheme(Brightness.dark),
      themeMode: theme.materialThemeMode,
      locale: locale.locale, // null = follow the OS locale
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Runs even when `locale:` above has a user override — Flutter still
      // calls this callback, just with [locale.locale] as the sole
      // "device" candidate instead of the real device list, so an override
      // resolves through the same language-match path below and comes back
      // unchanged (LocaleController only ever holds a bare language code
      // that's already in supportedLocales). Flutter's own default
      // resolution falls back to supportedLocales.first when nothing
      // matches — which is whichever language sorts first alphabetically
      // among our .arb files (currently German), not English. Match by
      // language only (none of our locales carry a country/script code)
      // and fall back to English explicitly instead of leaving that to
      // alphabetical luck.
      localeListResolutionCallback: (deviceLocales, supported) {
        for (final deviceLocale in deviceLocales ?? const <Locale>[]) {
          for (final s in supported) {
            if (s.languageCode == deviceLocale.languageCode) return s;
          }
        }
        return const Locale('en');
      },
      builder: (context, child) =>
          ThemeSwitchOverlay(key: themeSwitchKey, child: child!),
      navigatorObservers: [TelemetryNavigatorObserver()],
      home: const _Gate(),
    );
  }
}

// ══════════════════ THE ONBOARDING GATE ══════════════════

/// The gate, as a pure function of its inputs. Onboarding order bugs are
/// the ones users hit exactly once and never forgive, so this is testable
/// without a band, a database or a widget tree.
///
/// [AppRoute.pairing] short-circuits before AppState ever looks at the
/// profile, so a skipped pairing falls through to profile setup rather than
/// straight to the shell — we still want the four numbers.
///
/// [onboarded] is the difference between "has never had a band" and "has no
/// band right now". `AppState.route` only knows the second: a user who forgets
/// their strap after months of use goes `isPaired == false` →
/// [AppRoute.pairing], and `pairingSkipped` is false for anyone who actually
/// paired, so they landed in FIRST-RUN onboarding with all their data behind
/// it and "Skip for now" as the only way back. Onboarding happens once.
AppRoute resolveRoute(
  AppRoute route, {
  required bool pairingSkipped,
  required bool firstSyncSeen,
  required bool profileSeen,
  bool onboarded = false,
}) {
  var r = route;
  if (onboarded &&
      (r == AppRoute.pairing ||
          r == AppRoute.firstSync ||
          r == AppRoute.profile)) {
    return AppRoute.shell;
  }
  if (r == AppRoute.pairing && pairingSkipped) r = AppRoute.profile;
  if (r == AppRoute.profile && profileSeen) return AppRoute.shell;
  // A real pairing shows the first-sync step once; a skipped one does not.
  if (r == AppRoute.profile && !pairingSkipped && !firstSyncSeen) {
    return AppRoute.firstSync;
  }
  return r;
}

/// One-way latch: this install has reached the app itself at least once.
///
/// Kept here rather than on [OnboardingBypass] because it is not a bypass —
/// nothing was skipped. It is the record that onboarding HAPPENED, which is
/// the only thing that distinguishes a lost band from a first run.
const String _kOnboarded = 'onboard.completed';

bool get _onboarded => Prefs.getBool(_kOnboarded, false);
void _markOnboarded() {
  if (!_onboarded) Prefs.setBool(_kOnboarded, true);
}

/// Telemetry-only: the last AppRoute we logged, so the gate's build (which
/// also re-runs on a plain theme flip) doesn't double-log.
AppRoute? _telemetryLastRoute;

class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    // SELECT, not watch: rebuild only when the ROUTE actually changes (rare) —
    // not on every ~1 Hz AppState tick (live HR, log lines). Watching the whole
    // AppState here used to repaint the entire home stack every second, which
    // starved the background BLE connection on long idle stretches.
    final raw = context.select<AppState, AppRoute>((a) => a.route);
    return ValueListenableBuilder<int>(
      valueListenable: OnboardingBypass.revision,
      builder: (context, _, _) {
        final route = resolveRoute(
          raw,
          pairingSkipped: OnboardingBypass.pairingSkipped,
          firstSyncSeen: OnboardingBypass.firstSyncSeen,
          profileSeen: OnboardingBypass.profileSeen,
          onboarded: _onboarded,
        );
        if (route != _telemetryLastRoute) {
          _telemetryLastRoute = route;
          TelemetryService.instance.setContext('app_route', route.name);
          TelemetryService.instance.breadcrumb('route: ${route.name}');
        }
        final Widget resolved = switch (route) {
          // Underlay while the boot splash covers the loading phase — and what
          // the user lands on if the splash's safety cap fires before init
          // completes.
          AppRoute.loading => const _Loading(),
          AppRoute.failed => const _InitFailed(),
          AppRoute.welcome => const WelcomeScreen(),
          AppRoute.pairing => DevicePickerScreen(
            onBack: () => context.read<AppState>().returnToWelcome(),
            onSkip: () => OnboardingBypass.mark(OnboardingBypass.kPairing),
          ),
          AppRoute.firstSync => FirstSyncScreen(
            onDone: () => OnboardingBypass.mark(OnboardingBypass.kFirstSync),
          ),
          AppRoute.profile => ProfileSetupScreen(
            onDone: () => OnboardingBypass.mark(OnboardingBypass.kProfile),
          ),
          AppRoute.shell => const _Shell(),
        };
        // Cold-start splash: covers the whole loading phase and cross-fades out
        // the instant AppState finishes initializing, even mid-play. Shown once
        // per launch; BootSplash latches itself off after.
        return BootSplash(ready: route != AppRoute.loading, child: resolved);
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Scaffold(
      backgroundColor: p.bg,
      body: Center(child: CircularProgressIndicator(color: p.on(C.green))),
    );
  }
}

/// Start-up threw. The one screen whose job is to not be a spinner.
///
/// It names the failure with the actual message rather than a friendlier guess,
/// says the data is still on the device (it is — nothing here deletes, and an
/// unopenable database rebuilds itself in `LocalDb`), and offers the retry.
class _InitFailed extends StatelessWidget {
  const _InitFailed();
  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final app = c.watch<AppState>();
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'OpenStrap could not start',
                  style: F.t2.copyWith(color: p.ink),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your data is still on this device — nothing was deleted. '
                  'This is a start-up step failing, and it will fail the same '
                  'way each launch until it is fixed.',
                  style: F.body.copyWith(color: p.ink2, height: 1.5),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.card2,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SelectableText(
                    app.initError ?? 'No error was recorded.',
                    style: F.cap.copyWith(color: p.ink2),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: app.retryInit,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════ THE SHELL ══════════════════

/// A notification's tab index → the domain that now owns that content.
///
/// The indices come from `tap_router.dart`, which still speaks the old
/// five-tab vocabulary (Today · Sleep · Heart · Body · Workouts). Sleep, Heart
/// and Body all folded into Health, so three of the five collapse onto one
/// destination. Payloads from older builds keep working, which is the whole
/// point — a notification is scheduled days before it is tapped.
ShellDomain domainForTab(int tab) => switch (tab) {
  1 || 2 || 3 => ShellDomain.health,
  4 => ShellDomain.workout,
  _ => ShellDomain.home,
};

/// A deep-link sub-screen route → the domain it belongs to.
///
/// Every `kRoute*` in `tap_router.dart` is here, and unknown routes fall back
/// to Home rather than crashing a cold launch on a payload from an older
/// build.
ShellDomain domainForRoute(String route) => switch (routePath(route)) {
  kRouteAiMorning || kRouteAiEvening => ShellDomain.home,
  kRouteJournalCompose || kRouteBreathing => ShellDomain.wellness,
  // Water is a journal field that lives on Nutrition — that is the tab
  // behind the log screen, and where a "back" from it should land.
  kRouteWater => ShellDomain.wellness,
  // The medication reminder. Journal owns the canonical medications screen;
  // back from it lands on Journal, same as water → Nutrition over wellness.
  kRouteMeds => ShellDomain.wellness,
  // The movement/sedentary nudges. Today (Home) is where the steps/rings
  // they point at live; there is no move screen to push, so
  // screenForRoute returns null for it — same shape as /meds below.
  kRouteMovement => ShellDomain.home,
  // Recovery-ready and step-goal notes. Both are about what already lives
  // on Today, and neither has a screen of its own to push.
  kRouteRecovery => ShellDomain.home,
  kRouteSteps => ShellDomain.home,
  kRouteWorkoutSuggestion => ShellDomain.workout,
  // The forgotten-workout nudge. The Workouts tab is the destination
  // itself — the live session bar with its finish control is pinned to
  // the shell there — so screenForRoute stays null for it.
  kRouteWorkoutIdle => ShellDomain.workout,
  // Emitted by the battery forecast (`app_state.dart`) and the weekly
  // recap (`notification_center.dart`), and declared in `tap_router`
  // alongside every other deep link — see the note below.
  kRouteProfile => ShellDomain.home,
  // The two alarm safety notifications. Reached the same way as the
  // battery/band alerts above — Profile lives on Home.
  kRouteAlarm => ShellDomain.home,
  // No recap screen exists. Health is where a week of sleep, strain and
  // recovery actually lives, so it is the nearest true destination — but
  // the notification promises a REPORT, and until one is built the honest
  // fix is upstream, in what that notification claims.
  kRouteRecap => ShellDomain.health,
  _ => ShellDomain.home,
};

// `/profile` and `/recap` are declared in `tap_router.dart` alongside every
// other deep link. They used to be private literals here, which is exactly why
// both landed on Home: absent from tap_router's table, they produced no screen
// request, so the shell fell back to the tab index and never consulted
// [domainForRoute] at all.

/// The focused screen a deep link pushes on top of its domain, when one
/// exists. Null means the domain itself is the destination.
///
/// `/workouts/suggestion` used to be in that list, and it was the one route
/// where the fallback was a broken promise: "Tap to log it" landed on the
/// plain Workouts tab, because the screen that could log it was deleted with
/// `lib/ui/workouts/` and nothing read `workout_suggestions`. There is a
/// destination again, and confirming on it writes a real session.
///
/// `/ai/*` used to be in that list too. It now lands on the briefing itself,
/// which also carries the exact snapshot that was sent to produce it.
Future<void> _nutritionBarcode(BuildContext context, String day, String meal) =>
    LogFoodSheet.show(context, date: day, meal: meal);

/// A reduced release has only Home. Retained screens stay gated in
/// [releaseScreenForRoute]; a parked route still pushes nothing.
/// A full development build keeps [domainForRoute].
ShellDomain releaseDomainForRoute(String route, {required bool reduced}) {
  if (reduced) return ShellDomain.home;
  return domainForRoute(route);
}

ShellDomain releaseDomainForTab(int tab, {required bool reduced}) {
  final domain = domainForTab(tab);
  if (reduced && domain != ShellDomain.home) return ShellDomain.home;
  return domain;
}

Widget? releaseScreenForRoute(
  String route, {
  required bool reduced,
  OpenBandRepository? repository,
}) {
  if (reduced && !openBandReleaseKeepsRoute(route)) return null;
  return screenForRoute(route, repository: repository);
}

Widget? screenForRoute(String route, {OpenBandRepository? repository}) =>
    switch (routePath(route)) {
      kRouteAiMorning => const AiBriefingScreen(period: BriefingPeriod.morning),
      kRouteAiEvening => const AiBriefingScreen(period: BriefingPeriod.evening),
      kRouteJournalCompose => const OpenBandJournalEditorRoute(),
      kRouteBreathing => const CalmBreathing(),
      // The hydration reminder lands on Nutrition, where the water tile carries
      // its own − / + and is beside the food it belongs with. There used to be
      // a whole screen for this one field; it was reachable ONLY from here,
      // which is how the tile that everybody actually used stayed add-only for
      // so long — the thing that could clear a value was behind a notification.
      kRouteWater => OpenBandNutritionRoute(
        date: todayLabel(),
        onBarcode: _nutritionBarcode,
      ),
      // Same shape as water: a focused screen pushed over Journal. Missing or
      // ended plans open the canonical day without mutating — the screen reads.
      kRouteMeds =>
        repository == null
            ? null
            : OpenBandMedications(repository: repository, day: todayLabel()),
      // The detected bout, with the three answers to it: log it, adjust the
      // times first, or say it never happened.
      kRouteWorkoutSuggestion => WorkoutSuggestionScreen(
        focusId: routeId(route),
      ),
      // Battery, band and sources all live behind this one.
      kRouteProfile => const ProfileHome(),
      // The alarm safety notifications land where either can actually be
      // fixed — the schedule itself.
      kRouteAlarm => const AlarmScreen(),
      // The weekly recap used to land on the Health tab and push nothing,
      // because there was no recap screen to push. There is now: the sweep's
      // findings, which the app has been computing every night and delivering
      // only as a notification you could dismiss into nothing.
      kRouteRecap => const WhatChangedScreen(),
      _ => null,
    };

class _Shell extends StatefulWidget {
  const _Shell();
  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  late ShellDomain _domain = _restoredDomain();
  final _shellKey = GlobalKey<AppShellState>();
  late final OpenBandController _day;
  late final LocalOpenBandRepository _dailyRepository;
  int _insightsRevision = -1;
  Object? _lastBandState;
  bool? _lastDeriving;

  ShellDomain _restoredDomain() => shellDomainForRestore(
    reduced: kOpenBandReleaseReduced,
    savedName: Prefs.getString(kOpenBandTabPref, ''),
    legacyTab: Prefs.getInt(Prefs.shellTab, 0),
  );

  void _sourceChanged() {
    final app = _app!;
    final processing = app.deriving || app.derivePending;
    if (_insightsRevision != app.insightsRevision.value ||
        _lastDeriving != processing) {
      _lastDeriving = processing;
      _insightsRevision = app.insightsRevision.value;
      unawaited(_day.refresh());
    }
    final state = (
      app.status,
      app.device.batteryPct,
      app.lastRecordAt,
      app.syncingNow,
    );
    if (state != _lastBandState) {
      _lastBandState = state;
      unawaited(_readBand());
    }
  }

  Future<void> _readBand() async {
    try {
      final band = await _dailyRepository.readBand();
      if (mounted) _day.updateBand(band);
    } catch (_) {
      // A failed status read must not replace the last known observation.
    }
  }

  AppState? _app;

  @override
  void initState() {
    super.initState();
    // A tapped notification asks for a tab via AppState.navRequest. Jump there,
    // then clear the request so it isn't replayed on rebuild.
    _app = context.read<AppState>();
    _dailyRepository = LocalOpenBandRepository(_app!);
    final savedDay = Prefs.getString('ui.openband.day', todayLabel());
    _day = OpenBandController(
      repository: _dailyRepository,
      initialDay:
          RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(savedDay) &&
              DateTime.tryParse(savedDay) != null &&
              dayLabelOf(DateTime.parse(savedDay)) == savedDay
          ? savedDay
          : todayLabel(),
      persistDay: (day) async => Prefs.setString('ui.openband.day', day),
    );
    _app!.addListener(_sourceChanged);
    _app!.insightsRevision.addListener(_sourceChanged);
    _sourceChanged();
    _day.refresh().then((_) {
      if (!mounted) return;
      final correction = _day.day?.correction;
      if (correction != null &&
          (correction.state == CorrectionState.pending ||
              correction.state == CorrectionState.calculating)) {
        unawaited(_day.calculate(correction));
      }
    });
    _app!.navRequest.addListener(_consumeSoon);
    _app!.screenRequest.addListener(_consumeSoon);
    // Cold launch from a tapped notification: the route may already be set
    // before this shell mounted (so the listener never fired). Consume it once
    // attached.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Reaching the shell IS the end of onboarding. Latched here rather than
      // at the pairing screen because an install that upgraded into this build
      // never saw one.
      _markOnboarded();
      _consume();
    });
  }

  bool _pending = false;

  /// Both requests come from ONE tap and are written one after the other, so
  /// whichever listener fires second used to win — and which one that is
  /// inverts between a warm tap (screen, then nav) and a cold launch (the
  /// post-frame callback, in whatever order it reads them). A `/breathing`
  /// notification therefore landed on Wellness or on Home depending on
  /// whether the app happened to be running. Read the pair together, once
  /// both have landed.
  void _consumeSoon() {
    if (_pending) return;
    _pending = true;
    scheduleMicrotask(() {
      _pending = false;
      _consume();
    });
  }

  void _consume() {
    final app = _app;
    // Leave the request standing if there is no shell to act on it — the next
    // one consumes it in its post-frame callback rather than finding it eaten.
    if (app == null || !mounted) return;
    final s = app.screenRequest.value;
    final tab = app.navRequest.value;
    app.screenRequest.value = null;
    app.navRequest.value = -1;
    // A screen route carries its own domain; the tab index alongside it is
    // the base the payload was built with, not a second destination.
    if (s != null && s.isNotEmpty) {
      final domain = releaseDomainForRoute(s, reduced: kOpenBandReleaseReduced);
      _go(domain);
      final screen = releaseScreenForRoute(
        s,
        reduced: kOpenBandReleaseReduced,
        repository: _day.repository,
      );
      if (screen != null) {
        _shellKey.currentState?.open(domain, screen);
      }
      return;
    }
    if (tab >= 0) {
      _go(releaseDomainForTab(tab, reduced: kOpenBandReleaseReduced));
    }
  }

  void _go(ShellDomain d) {
    if (kOpenBandReleaseReduced && d != ShellDomain.home) {
      d = ShellDomain.home;
    }
    _domain = d;
    _shellKey.currentState?.select(d);
    persistOpenBandTab(reduced: kOpenBandReleaseReduced, name: d.name);
  }

  @override
  void dispose() {
    _app?.removeListener(_sourceChanged);
    _app?.insightsRevision.removeListener(_sourceChanged);
    _day.dispose();
    _app?.navRequest.removeListener(_consumeSoon);
    _app?.screenRequest.removeListener(_consumeSoon);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // SELECT, not watch: a bool that flips twice a workout, not the ~1 Hz
    // AppState tick.
    final live = context.select<AppState, bool>((a) => a.activeWorkout != null);
    final reduced = kOpenBandReleaseReduced;
    return AppShell(
      key: _shellKey,
      initial: _domain,
      domains: reduced ? kOpenBandReleaseDomains : null,
      banner: live
          ? _LiveSessionBar(
              repository: _day.repository,
              onFinished: _day.refresh,
            )
          : null,
      onSelect: (d) {
        _domain = d;
        persistOpenBandTab(reduced: reduced, name: d.name);
        if (d == ShellDomain.health) unawaited(_day.refresh());
      },
      builder: (c, d) => switch (d) {
        ShellDomain.home => OpenBandOverview(
          controller: _day,
          reduced: reduced,
          onProfile: () => Navigator.of(
            c,
          ).push(MaterialPageRoute<void>(builder: (_) => const ProfileHome())),
          onJournal: reduced ? null : () => _go(ShellDomain.wellness),
          onNutrition: reduced
              ? null
              : () => Navigator.of(c).push(
                  MaterialPageRoute<void>(
                    builder: (_) => OpenBandNutritionRoute(
                      controller: _day,
                      onBarcode: _nutritionBarcode,
                    ),
                  ),
                ),
          onTraining: reduced ? null : () => _go(ShellDomain.workout),
          onSync: () => _app!.openSession(),
        ),
        ShellDomain.health => OpenBandHealth(controller: _day),
        ShellDomain.workout => OpenBandTraining(
          controller: _day,
          onStart: (type) => _startActivity(c, type),
          onOpenTemplates: () async {
            await Navigator.of(c).push(
              MaterialPageRoute<void>(
                builder: (_) => OpenBandTemplates(
                  repository: _day.repository,
                  onStartTemplate: (t) => _openStrength(c, t),
                  onEditTemplate: (t) => _openTemplateEditor(c, t),
                ),
              ),
            );
            _day.refresh();
          },
          onStartTemplate: (t) => _openStrength(c, t),
          onEditTemplate: (t) => _openTemplateEditor(c, t),
          onOpen: (s) => Navigator.of(c).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  OpenBandSession(repository: _day.repository, session: s),
            ),
          ),
        ),
        ShellDomain.wellness => OpenBandJournal(
          controller: _day,
          onEdit: (day) async {
            await Navigator.of(c).push(
              MaterialPageRoute<void>(
                builder: (_) => OpenBandJournalEditor(
                  repository: _day.repository,
                  day: day,
                ),
              ),
            );
          },
          onNutrition: () => Navigator.of(c).push(
            MaterialPageRoute<void>(
              builder: (_) => OpenBandNutritionRoute(
                controller: _day,
                onBarcode: _nutritionBarcode,
              ),
            ),
          ),
          onCycle: () => OpenBandCycle.push(
            c,
            repository: _day.repository,
            day: _day.selectedDay,
            now: _day.now,
            synthetic: _day.day?.synthetic == true,
          ),
        ),
      },
    );
  }

  Future<void> _openStrength(BuildContext c, WorkoutTemplate t) {
    return Navigator.of(c).push(
      MaterialPageRoute<void>(
        builder: (_) => OpenBandStrengthLive(
          repository: _day.repository,
          template: t,
          onFinished: _day.refresh,
        ),
      ),
    );
  }

  Future<void> _openTemplateEditor(BuildContext c, WorkoutTemplate? t) async {
    await Navigator.of(c).push(
      MaterialPageRoute<WorkoutTemplate>(
        builder: (_) =>
            OpenBandTemplateEditor(repository: _day.repository, template: t),
      ),
    );
    _day.refresh();
  }

  /// Quick-Start entry. Running opens the OpenBand live screen on the single
  /// AppState live engine; every other type goes through the existing picker
  /// so its setup (weight, privacy, GPS consent) stays in one place.
  Future<void> _startActivity(BuildContext c, String type) async {
    final app = _app;
    if (app == null) return;
    if (type != 'running') {
      await Navigator.of(
        c,
      ).push(MaterialPageRoute<void>(builder: (_) => const WorkoutScreen()));
      return;
    }
    if (app.activeWorkout == null) {
      try {
        await app.startWorkout(type: 'running');
      } catch (_) {
        if (c.mounted) {
          showRetryableActivityStart(
            c,
            () => unawaited(_startActivity(c, type)),
          );
        }
        return;
      }
    }
    if (app.activeWorkout == null) {
      if (c.mounted) {
        showRetryableActivityStart(c, () => unawaited(_startActivity(c, type)));
      }
      return;
    }
    if (!c.mounted) return;
    final feed = _LiveRunFeed(app);
    await Navigator.of(c).push(
      MaterialPageRoute<void>(
        builder: (_) => OpenBandRunLive(
          run: feed,
          tracker: app.routeTracker,
          mapAllowed: mapTilesAllowed,
          onPause: feed.pause,
          onResume: feed.resume,
          onLap: () {
            if (feed.value.paused) return;
            final v = feed.value;
            final id = app.activeWorkout?.workoutId;
            if (id == null) return;
            unawaited(
              _day.repository.recordLap(
                id,
                Lap(
                  index: v.laps + 1,
                  elapsedSec: v.elapsedSec,
                  pausedSec: v.pausedSec,
                  distanceM: v.distanceM,
                  at: DateTime.now(),
                ),
              ),
            );
            feed.markLap();
          },
          onFinish: () async {
            await app.stopWorkout();
            _day.refresh();
            if (c.mounted) Navigator.of(c).maybePop();
          },
        ),
      ),
    );
    feed.dispose();
  }
}

/// Adapts the AppState tick to a [LiveRun]. Pauses are the user's; the
/// banked pause seconds and the current pause start live here, never inferred
/// from a missing heart rate.
class _LiveRunFeed extends ValueNotifier<LiveRun> {
  final AppState app;
  int _pausedSec = 0;
  int _laps = 0;
  DateTime? _pausedAt;
  _LiveRunFeed(this.app) : super(const LiveRun(elapsedSec: 0)) {
    app.addListener(_update);
    _update();
  }
  void _update() {
    final w = app.activeWorkout;
    if (w == null) return;
    final now = DateTime.now();
    final inPause = _pausedAt == null
        ? 0
        : now.difference(_pausedAt!).inSeconds;
    final km = app.liveDistanceKm;
    value = LiveRun(
      elapsedSec: now.difference(w.startTime).inSeconds,
      pausedSec: _pausedSec + inPause,
      laps: _laps,
      distanceM: km == null ? null : km * 1000,
      heartRate: app.liveHr,
      zone: app.liveZone,
      paused: _pausedAt != null,
      gps: app.routeTracking,
    );
  }

  void pause() {
    _pausedAt ??= DateTime.now();
    _update();
  }

  void markLap() {
    _laps++;
    _update();
  }

  void resume() {
    if (_pausedAt case final at?) {
      _pausedSec += DateTime.now().difference(at).inSeconds;
      _pausedAt = null;
    }
    _update();
  }

  @override
  void dispose() {
    app.removeListener(_update);
    super.dispose();
  }
}

/// The way back into a session that is running while its screen is not on
/// screen — minimised, or left behind when the app was killed and relaunched.
///
/// Without it, leaving the live screen orphaned the session: `activeWorkout`
/// stayed open, every later workout was refused, and the only control that
/// could end it was the iOS Live Activity's Finish button. Android had
/// nothing at all.
///
/// No clock: the elapsed time would be stale the moment it was painted, and a
/// per-second rebuild of the whole shell to keep one number honest is not a
/// trade worth making. The number is on the screen this taps through to.
class _LiveSessionBar extends StatelessWidget {
  final OpenBandRepository repository;
  final VoidCallback? onFinished;
  const _LiveSessionBar({required this.repository, this.onFinished});

  /// The activity behind the open session.
  ///
  /// The draft FIRST (it carries the private flag and the entered weight), but
  /// `activeWorkout.type` as the fallback — a session started by the gesture
  /// path creates no draft, and neither does one rehydrated from a `sessions`
  /// row after a crash. Keying on the draft alone meant both of those left the
  /// workout open with no way to reach or end it, and `startWorkout` refuses
  /// every later workout while one is open.
  static Activity? _activityFor(AppState app) =>
      activityByName(LiveDraft.current?.activityKey ?? app.activeWorkout?.type);

  Future<void> _resume(BuildContext c) async {
    await resumeLiveSession(c, repository: repository, onFinished: onFinished);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final app = c.read<AppState>();
    final a = _activityFor(app);
    // A session the app is holding but this build cannot draw — an older
    // build's type key, say. Never nothing: the bar is the ONLY control that
    // can end an open session, and hiding it left the workout open forever
    // with every later one refused. Offer the one action that is certainly
    // right rather than a button that opens the wrong screen.
    if (a == null) {
      return Container(
        decoration: BoxDecoration(
          color: p.card,
          border: Border(top: BorderSide(color: p.line)),
        ),
        child: Pressable(
          semanticLabel: 'Finish the session that is still running',
          onTap: () => app.stopWorkout(),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: S.x4,
              vertical: S.x3,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Session running — tap to finish',
                    style: F.body.copyWith(color: p.ink),
                  ),
                ),
                Icon(LucideIcons.square, size: 18, color: p.ink3),
              ],
            ),
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: p.card,
        border: Border(top: BorderSide(color: p.line)),
      ),
      child: Pressable(
        semanticLabel: 'Back to your ${a.name.toLowerCase()} session',
        onTap: () => _resume(c),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: p.wash(a.color),
                  borderRadius: R.rSm,
                ),
                child: Icon(a.icon, size: 16, color: p.on(a.color)),
              ),
              const SizedBox(width: S.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.name,
                      style: F.body.copyWith(
                        color: p.ink,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Session running',
                      style: F.over.copyWith(color: p.ink3),
                    ),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronUp, size: 20, color: p.ink3),
            ],
          ),
        ),
      ),
    );
  }
}

/// Resume the session the live bar is holding.
///
/// Non-sets keep their live route without a strength snapshot read. Sets and
/// unknown types wait for a real read: Active/Corrupt → Alpin resume,
/// Legacy/NoActive → the existing live engine. A thrown read is not Alpin
/// and not NoActive — Erneut calls this again.
Future<void> resumeLiveSession(
  BuildContext context, {
  required OpenBandRepository repository,
  VoidCallback? onFinished,
}) async {
  final app = context.read<AppState>();
  final draft = LiveDraft.current;
  final a = activityByName(draft?.activityKey ?? app.activeWorkout?.type);
  if (a != null && a.track != Track.sets) {
    final page = await _activityLive(app, a, draft);
    if (!context.mounted) return;
    await _pushResumedLive(context, page);
    return;
  }
  final ActiveStrengthRuntime runtime;
  try {
    runtime = await repository.readActiveStrengthSession();
  } catch (_) {
    if (context.mounted) {
      showRetryableNotice(context, 'Einheit nicht geladen', () {
        unawaited(
          resumeLiveSession(
            context,
            repository: repository,
            onFinished: onFinished,
          ),
        );
      });
    }
    return;
  }
  if (!context.mounted) return;
  switch (runtime) {
    case ActiveStrengthSession():
    case CorruptActiveStrength():
      await _pushResumedLive(
        context,
        OpenBandStrengthLive.resume(
          repository: repository,
          onFinished: onFinished,
        ),
      );
    case LegacyActiveStrength():
    case NoActiveStrength():
      if (a == null) return;
      final page = await _activityLive(app, a, draft);
      if (!context.mounted) return;
      await _pushResumedLive(context, page);
  }
}

Future<Widget> _activityLive(AppState app, Activity a, LiveDraft? draft) async {
  final history = await loadSetHistory();
  return liveFor(
    a,
    private: draft?.private ?? false,
    weightKg: draft?.weightKg,
    host: activityHost(app, history: history),
  );
}

Future<void> _pushResumedLive(BuildContext context, Widget page) async {
  if (!context.mounted) return;
  await Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => page));
}

void showRetryableNotice(
  BuildContext context,
  String message,
  VoidCallback onRetry,
) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      action: SnackBarAction(label: 'Erneut', onPressed: onRetry),
    ),
  );
}

void showRetryableActivityStart(BuildContext context, VoidCallback onRetry) {
  showRetryableNotice(
    context,
    'Aktivität konnte nicht gestartet werden.',
    onRetry,
  );
}
