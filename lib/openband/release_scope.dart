import '../notify/tap_router.dart';
import '../state/prefs.dart';
import '../ui2/app_shell.dart';

/// Reduced first-release surface.
///
/// Default on for production and profile builds. An explicit development
/// build passes `--dart-define=OB_RELEASE=false` and keeps the full app.
/// The synthetic gallery does not read this. Its release flag opts that
/// target into the same reduced surface.
const bool kOpenBandReleaseReduced = bool.fromEnvironment(
  'OB_RELEASE',
  defaultValue: true,
);

/// Saved shell tab. A reduced launch shows Home and leaves the stored
/// name alone, so a later full build still restores Training or Journal.
const String kOpenBandTabPref = 'ui.openband.tab';

/// The release shell. One home domain, no bottom bar.
const List<ShellDomain> kOpenBandReleaseDomains = <ShellDomain>[
  ShellDomain.home,
];

/// Routes that still open a retained screen, or land on Home without
/// pushing one. `/today` is the alarm-fired and stale-sync reminder,
/// `/heart` is the health exception, and [kRouteWorkoutIdle] is the active
/// session. The detected-workout review stays parked.
bool openBandReleaseKeepsRoute(String route) => switch (routePath(route)) {
  kRouteProfile ||
  kRouteAlarm ||
  kRouteMovement ||
  kRouteRecovery ||
  kRouteSteps ||
  '/today' ||
  '/heart' ||
  kRouteWorkoutIdle => true,
  _ => false,
};

/// Whether a reduced release must neither present nor arm [route].
///
/// Null routes stay: they are band alerts with no parked screen. Saved
/// preferences are not part of this decision. Pass [reduced] so a
/// development build and tests can keep the full schedule.
bool openBandReleaseParksRoute(String? route, {required bool reduced}) {
  if (!reduced) return false;
  if (route == null || route.isEmpty) return false;
  return !openBandReleaseKeepsRoute(route);
}

ShellDomain shellDomainForRestore({
  required bool reduced,
  required String savedName,
  required int legacyTab,
}) {
  ShellDomain saved = ShellDomain.home;
  var named = false;
  for (final domain in ShellDomain.values) {
    if (domain.name == savedName) {
      saved = domain;
      named = true;
      break;
    }
  }
  if (!named) {
    saved = switch (legacyTab) {
      1 => ShellDomain.health,
      2 || 4 => ShellDomain.wellness,
      3 => ShellDomain.workout,
      _ => ShellDomain.home,
    };
  }
  if (reduced) return ShellDomain.home;
  return saved;
}

void persistOpenBandTab({required bool reduced, required String name}) {
  if (reduced) return;
  Prefs.setString(kOpenBandTabPref, name);
}
