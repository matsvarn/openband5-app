import '../notify/tap_router.dart';
import '../state/prefs.dart';
import '../ui2/app_shell.dart';

/// G3 production surface.
///
/// Default on for production and profile builds. An explicit development
/// build passes `--dart-define=OB_RELEASE=false` and keeps the full app.
/// The synthetic gallery does not read this. Its release flag opts that
/// target into the same reduced surface.
const bool kOpenBandReleaseReduced = bool.fromEnvironment(
  'OB_RELEASE',
  defaultValue: true,
);

/// Saved shell tab. Old names remain readable after a release upgrade.
const String kOpenBandTabPref = 'ui.openband.tab';

/// The four destinations in the production shell.
const List<ShellDomain> kOpenBandReleaseDomains = <ShellDomain>[
  ShellDomain.home,
  ShellDomain.sleep,
  ShellDomain.workout,
  ShellDomain.wellness,
];

/// Known notification and tab routes in the G3 release. Unknown paths fail
/// closed, including stale payloads from a development build.
bool openBandReleaseKeepsRoute(String route) => switch (routePath(route)) {
  '/today' ||
  '/sleep' ||
  '/heart' ||
  '/body' ||
  '/workouts' ||
  kRouteProfile ||
  kRouteAlarm ||
  kRouteMovement ||
  kRouteRecovery ||
  kRouteSteps ||
  kRouteWorkoutIdle ||
  kRouteWorkoutSuggestion ||
  kRouteJournalCompose => true,
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
      1 => ShellDomain.sleep,
      2 || 3 => ShellDomain.health,
      4 => ShellDomain.workout,
      _ => ShellDomain.home,
    };
  }
  if (reduced && saved == ShellDomain.health) return ShellDomain.home;
  return saved;
}

void persistOpenBandTab({required bool reduced, required String name}) {
  if (reduced && !kOpenBandReleaseDomains.any((d) => d.name == name)) return;
  Prefs.setString(kOpenBandTabPref, name);
}
