# Code-quality audit · October 2026

Scope: app and UI code of `edge` — `lib/openband/**`, `lib/ui2/**`, `lib/app*.dart`, `lib/main*.dart`, `lib/state`, `lib/theme`, `lib/widget`, `lib/notify`, `lib/health`, `lib/cloud`, `lib/models`, `lib/l10n` and the other non-BLE, non-storage directories, plus `pubspec.yaml` dependencies (not the protocol/analytics pins) and `analysis_options.yaml`. Base `openband5/g31-paper` at `61dcdd29`. `lib/ble/**`, `lib/sync/**` (reliability), `lib/data/**`, `lib/compute/**` (storage), `.github/**`, `integration_test/**` and golden tooling (test suite) belong to three parallel audits; findings there are listed for their owners at the end.

Goal: smaller code that is easier to change, with no behaviour change. This report is the read-only audit. The same branch implements the behaviour-preserving part; everything else is under [Decisions for Mats](#decisions-for-mats).

## Method

- Baseline at `61dcdd29`: `flutter analyze` clean, `python3 tool/check_design_manifest.py` → `ok: 207 blocks, 155 screens`, Paper harness `python3 tool/g3_review.py g31-` scored 18 frames (light 8.58–12.29 %, dark 5.93–9.89 %). The full harness run (`python3 tool/g3_review.py`) produced 292 frame scores and 38 failing harness tests on the base itself.
- Dead code: every public top-level declaration in the owned directories (980 in `lib/openband`, 1,101 elsewhere) was enumerated with the Dart analyzer's `parseString` AST, then counted by exact identifier (word boundary) across `lib/`, `test/`, `tool/`, `integration_test/`, `ios/`, `android/` and the design registries (`docs/openband5/design/blocks.json`, `paper-g3/frames.json`, `paper-g3/screens/*.json`), excluding the declaration's own span. The import/export/part graph was resolved from `lib/main.dart`, `lib/main_gallery.dart`, `lib/app*.dart`, `lib/notify/*` and `tool/g3_screens/*`. A declaration counts as dead only if no entry point constructs or calls it. Anything named by `blocks.json`, the Paper registries or the synthetic gallery counts as live. The analyzer's `unreachable_from_main` lint was tried and has no owned hits, but it only covers entry libraries, so it cannot confirm or refute the grep results. In this branch the proof is the deletion itself: each removal must leave `flutter analyze` clean.
- Parked modules (nutrition, cycle, medication, labs/glucose, coach, manual VO₂max) stay live: they run behind `--dart-define=OB_RELEASE=false` (`lib/openband/release_scope.dart:11`) and the plan keeps their code.
- Duplication: side-by-side reading of each G3 Baustein against screen-local widgets. Formatter merges were judged by comparing the implementations for all inputs: rounding, sign, null, non-finite values and locale.
- Structure: line counts of every `lib/**/*.dart`; AST measurement of `build()` length and syntactic widget depth; scan for non-const top-level and static state.
- Dependencies: `flutter pub outdated` (+`--json`), `dart pub outdated --show-all`, a `package:<name>/` import census per directory, native-registration check for zero-import packages, OSV batch query of all 206 resolved hosted package versions.
- Lints: each candidate enabled alone in a scratch checkout, `flutter analyze --no-pub lib test`, violations counted and a sample inspected for real bugs; `dart fix --dry-run` for bulk-fix availability.

Everything here is source and analyzer evidence. Nothing was run on a simulator or the phone.

## Findings

| ID | Rank | Finding | Evidence (short) | Action |
|---|---|---|---|---|
| DC-1 | P1 | Legacy `ui2` screen cluster (Home, Health, Wellness and their details) is unreachable | See [DC-1](#dc-1--legacy-ui2-screen-cluster-p1) | Delete in this branch |
| DC-2 | P1 | 380 localization keys have no consumer (1,043 after DC-1/DC-4) | `\.key\b` has zero hits outside `lib/l10n` | Delete from the six ARBs in this branch |
| DEP-1 | P1 | `cupertino_icons` and `fl_chart` are unused direct dependencies | 0 imports in lib/test/tool/integration_test; no native registration; scratch removal analyzed clean | Remove in this branch |
| DC-3 | P2 | Orphaned v2 cloud-import cluster | `lib/cloud/cloud_import.dart` (312) is imported only by `test/import_data_safety_test.dart:20`; `backend_client.dart` (146) only by it | Delete in this branch |
| DC-4 | P2 | `lib/openband` dead options, adapters and helpers (~255 lines) | DOB-01…10 below | Delete in this branch |
| DC-5 | P2 | Unused payload adapters and `AppState` members | `RecordsData`, `StrainData`, `TrendsData` (`lib/models/payloads.dart:355,445,507`); 15 `AppState` members with zero references | Delete in this branch |
| DUP-1 | P1 | The day screen can combine two derivation snapshots | [DUP-1](#dup-1--day-reads-can-mix-snapshots-p1) | Decision; storage co-owner |
| DUP-2 | P1 | Headline and trend values for the same day come from two stores | [DUP-2](#dup-2--headline-and-trend-use-separate-stores-p1) | Decision; storage co-owner |
| DUP-3 | P3 | Literal yes/no key row duplicated between Bausteine | `g3/day.dart:463–483` vs `OBYesNoKeys` `g3/heute_parts.dart:164–184` (18 identical lines) | Merge in this branch |
| DUP-4 | P3 | Byte-identical clock and plural helpers | `today_note.dart:17–18`, `cycle_medians.dart:972–973` vs `g3Clock`; hand-rolled singular/plural in `cycle_comparison.dart:710–713`, `cycle_observations.dart:413–421` vs `g3CountNoun` | Merge in this branch |
| DUP-5 | P2 | Check-in card exists three times and has diverged | `G3CheckInPreview` `g3/day.dart:439–597`, `OBCheckInAsk` `heute_parts.dart:31–155`, `OBCheckIn` `check_in.dart:74–230` | Decision (visual) |
| DUP-6 | P2 | Screen-local stat cells re-implement `OBStatRow` | `g3/screens/sleep.dart:750–818` `_nightFacts`; `g3/screens/training_live.dart:641–667` `_stat` | Decision (visual) |
| DUP-7 | P2 | Parallel formatter catalogue outside `g3_format.dart` | 25 formatter sites; none identical for all inputs | Decision (copy) |
| STR-1 | P2 | 32 owned files over 1,500 lines | [Structure](#3-structure) | Split three with an obvious seam in this branch |
| STR-2 | P2 | Business logic in widgets | Top ten below | Report; move when the feature is next edited |
| STR-3 | P2 | Telemetry futures escape their `try/catch` | `lib/telemetry/telemetry_service.dart:84–86,154,175,214,225,236,360` | Decision (fixing changes failure behaviour) |
| LINT-1 | P2 | Cheap guards with zero or one hit | `cancel_subscriptions` 0, `close_sinks` 0, `strict-casts` 1 in lib/test, 1 more in `tool/` | Enable the first two in this branch; `strict-casts` after the tooling fix |
| DEP-2 | P2 | 28 direct packages have newer resolvable majors | `flutter pub outdated`; no OSV advisory for any resolved version | Decision per package |
| STR-4 | P3 | 72 `build()` bodies over 150 lines | Top: `sleep_editor.dart:511` (542 lines, depth 11) | Report |
| STR-5 | P3 | Process-wide mutable state | 13 sites, all intentional services | Report only |
| LINT-2 | P3 | Style lints would raise 971 / 393 / 182 diagnostics | `avoid_redundant_argument_values`, `directives_ordering`, `prefer_const_constructors` | Defer |

No P0 was found in owned code that a user can reach. STRUCT-01 in the working notes, an even-count median that shows 60.00 instead of 50.00 for `[40, 60]` in `lib/ui2/screens/investigate.dart:1113`, was reproduced with a widget probe. It sits inside the unreachable DC-1 cluster, so no build shows it; deleting DC-1 removes it.

## 1. Dead code

### DC-1 · legacy ui2 screen cluster (P1)

The OpenBand shell (`lib/app.dart:746–960`) and the gallery (`lib/main_gallery.dart:229–352`) build OpenBand/G3 screens for every domain, including development builds. Notification routes use `G3MetricDetail` and `G3AllMetrics` (`lib/app.dart:470–535`). No code outside their own files constructs the three ui2 roots:

```
rg -n '\b(HomeScreen|HealthScreen|WellnessScreen)\(' lib tool integration_test   → own declarations only
```

Every other screen in the cluster is constructed only from inside it:

| Screen | Only constructors outside its file | Lines |
|---|---|---:|
| `SleepDetail` (`ui2/screens/sleep_detail.dart`) | `wellness_screen.dart:394`, `home_screen.dart:1589`, `metric_detail.dart:1537` | 1,806 |
| `HealthScreen` (`health_screen.dart`) | none | 1,425 |
| `MetricDetail` (`metric_detail.dart:626–1821`) | `home_screen.dart:1687,1728,1768,1790`; `health_screen.dart:719,1063,1217,1228,1400` | 1,196 |
| `Investigate` (`investigate.dart`) | `health_screen`, `metric_detail`, `sleep_detail`, `readiness_detail`, `beats` | 1,147 |
| `WellnessScreen`, `JournalFindings` (`wellness_screen.dart:35–592,751–1073`) | none / `wellness_screen.dart:559` | 881 |
| `Beats` (`beats.dart`) | `metric_detail.dart:926,1538` | 787 |
| `CircadianDetail` (`circadian_detail.dart`) | `health_screen.dart:1092,1120` | 720 |
| `HomeScreen` (`home_screen.dart:1236–1933`) | none | 698 |
| `ReadinessDetail` (`readiness_detail.dart`) | `home_screen.dart:1587,1608` | 442 |
| `DayStepsDetail` (`day_steps.dart:234–468`) | `metric_detail.dart:946,1539` | 235 |

About 9,300 source lines. Tests still construct them, which is why the analyzer is clean. Stays live and must be kept: `home_screen.dart:1–1235` helpers (`repoOf`, `unitsOf`, `HomeData`; `training_manual.dart:7` imports them), the spec/chrome parts of `metric_detail.dart` used by the component gallery (`DayNav`, `Legend`, `MonoTable`, `investigateRow`), `DriverRow` (`gallery.dart:572`), `rough_night.dart`, `driver_breakdown.dart`, `DayTimeline`, `MonthGrid`, `bandLabel` (`day_steps.dart:469–489`). The `mascot_wellness` images stay: besides `WellnessScreen:199`, `test/start_session_card_test.dart:99` renders them through the live `StartCard`.

### DC-2 · unused localization keys (P1)

`l10n.yaml` generates from `lib/l10n/app_en.arb`. The generated `app_localizations*.dart` files are not tracked. For each key, `\.KEY\b` (including null-aware access) has zero hits outside `lib/l10n` across code, tests, tools, native code and registries. Examples: `appTitle`, `actionSettings`, `pairingFindMyBand`, `alarmArmedFor`, `profileSetupAgeLabel`, `devicePickerPrivacyNote`. At the base that is 3,826 tracked ARB lines across six locales, plus ~4,200 generated lines. Recounted after DC-1, DC-3 and DC-4, 1,043 of the 2,425 English keys have no consumer; this branch removes them with their `@key` metadata from all six ARBs (10,887 ARB lines). Every removed key was checked again with `\.(key)\b` over `lib`, `test`, `tool` and `integration_test`: 0 hits.

### DC-3 · orphaned cloud import (P2)

`lib/cloud/cloud_import.dart` (312) and `lib/cloud/backend_client.dart` (146) sit outside the import closure of both entry points and the tools. `AppState.completeCloudOnboard` (`app_state.dart:445–454`) has no caller. The welcome import uses `runImport`, not `CloudImporter`. `BACKEND_URL` is read only by this cluster. `CompanionClient` and `COMPANION_URL` stay.

### DC-4 · lib/openband (P2/P3)

All 109 files are imported from a live entry point; the dead code is inside them.

| ID | Site | Proof | Lines |
|---|---|---|---:|
| DOB-01 | `OBHrTrace` `showSignalStrip`/`showExplanation`/`showZoneBands`/`showZoneLabels` (`g3/charts.dart:72–75` and branches) plus `zoneTintsFor`, `zoneTints`, `loadZoneTints` (`g3/g3_theme.dart:165–198`) | six calls (`training_screen.dart:1100`, `specimens.dart:826`, four tests); `rg 'showSignalStrip:\|showExplanation:\|showZoneBands:\|showZoneLabels:'` → 0 | ~110 |
| DOB-02 | `OpenBandJournalEditorRoute` (`journal_editor.dart:40–62`), `OpenBandNutritionGoalsRoute` (`nutrition_goals.dart:138–150`) | only own declarations; journal uses `G3JournalComposeRoute` (`app.dart:498`) | 36 |
| DOB-03 | `G2SyncState` pending mode (`screens.dart:1707–1812`) | single call `screens.dart:127` never passes `actionState`/`showStoredTime`/`pendingLabel` | 24 |
| DOB-04 | `OBPatternDotPlot.bandLow/bandHigh` (`g3/journal_parts.dart:652–653,703–713`) | `rg 'bandLow:\|bandHigh:'` → 0 | 22 |
| DOB-05 | `OpenBandCycle.pushSettings` (`cycle.dart:86–104`) | one match, the declaration | 19 |
| DOB-06 | `OBRatingKeys.showLegend` (`g3/heute_parts.dart:186–241`) | only call passes `false` (`heute.dart:1232`) | 16 |
| DOB-07 | `OBTrendCard.format` (`health.dart:861…1262`) | 13 calls, none pass `format` | 15 |
| DOB-08 | `requireOriginalLoad`, `kNightScalarPaperSkinTempCOffset`, `kHeuteSports`, `heuteCheckInQuestion`, `heuteRatingCopy` | zero references | 10 |
| DOB-09 | `SyntheticOpenBandRepository.failSetupEvaluation` (`synthetic_repository.dart:142,3302`) | never set | 4 |
| DOB-10 | `SleepDraft.timeInBed` (`domain.dart:389`) | zero references | 2 |

Kept because a registry, the gallery or a test names them. These are dead in the app, listed in Decisions: `MetricRing`, `NightChart` (`charts.dart`), `OBCheckInAsk`, `OpenBandRunLive`, `OBPatternDotPlot`, `OBMetricCard`, `G3CheckInPreview`. Also kept: generated tokens `AlpText.micro/cardTitle`, `AlpSpace.s14/16/24/32/48` (`alp_tokens.dart` is generated from `tokens.json`), and the reserved `FirstTransferReceipt` contract (`g3_data.dart:87–105`).

### DC-5 · app layer (P2/P3)

- `lib/models/payloads.dart`: `RecordsData` (355–404), `StrainData` (445–477), `TrendsData` (507–560) have zero references (137 lines); `SleepData.stagesBeta` (440) is always `true` and never read.
- `lib/state/app_state.dart`: zero-reference members `companionUrl`, `companionConfigured`, `setCompanionUrl`, `completeCloudOnboard`, `healthIsApple`, `exportWorkoutToHealth`, `debugHasLiveConsumer`, `briefingUpdated`, `testBuzzPattern`, `clearAlarm`, `bluetoothReady`, `breathingStartedAt`, `breathingTarget`, `buzzSessionComplete`, `routeTracker` (94 lines). Write-only `logLines` (251) and `consentChosen` (886) need a closer look and are not deleted.
- Zero references: `driverAbsenceCard` (`ui2/screens/driver_breakdown.dart:549`, 38), `splitUnit` (`home_screen.dart:90`), `kLightStageColor`, `confidenceRingAlpha` (`theme/tokens.dart:16,392`), `glucoseAttemptFromReceipt` (`health/glucose_contract.dart:516`), `lib/debug/debug_mode.dart` (no importer; `DEBUG_MODE` has no effect).
- Assets: eight sport SVGs (`bow`, `fish`, `ping-pong`, `sailboat`, `stretching-2`, `sword`, `treadmill`, `wheelchair`; 4,398 bytes) have no producer. `OBSportIcon` loads `$name.svg` only for ids produced by `obSport` (`training.dart:199–228`) and `g3Sports` (`g3/sport.dart:12–29`); `treadmill` maps to `run`.
- Test-only helpers (P3, not deleted): `buildVertices` (`gps/route_math.dart:146`), `seedEntryFromLegacyEpoch` (`state/alarm_schedule.dart:125`), `intervalPattern` (`stress/breath_phases.dart:177`), `gallerySessions`, `nightSignalHasUncoveredInterval`, `sleepGoalMinutesFromFields`, and nine Paper fixture constants. `JournalAiEngine` / `mergeJournalEntry` belong to the parked coach.
- Feature flags: no owned environment flag is constant-dead. `OB_RELEASE`, `COMPANION_URL`, `APP_GROUP_IDENTIFIER` and the contribution flag are all overridable; prefs-backed booleans are read in supported flows.

## 2. Duplication

### DUP-1 · day reads can mix snapshots (P1)

`LocalOpenBandRepository.readDay` snapshots `day_result`, correction and job state in one transaction (`lib/openband/local_repository.dart:1259–1303`) and builds the night cards from it (`:1304–1380`). After the transaction it calls `getDaySleep`, `getDayHeart`, `getDayStrain` and `getDaySteps` independently (`:1398–1408`) and reads sleep history (`:1423–1429`). Each of those reselects the served `day_result` (`lib/data/local_repository_impl.dart:100–104`, `db.dart:10621–10631`). If a derivation commits between the snapshot and those reads, one `OpenBandDay` combines the old hypnogram and correction state with the new duration and Erholung. Source-proven interleaving, not reproduced. It does not fabricate a value, and the next reload is consistent. It still breaks §3.8 "one source per concern" for the screen. Fixing it changes observable output under concurrency, so it is a decision (the storage audit owns the reader side).

### DUP-2 · headline and trend use separate stores (P1)

Headline steps come from `getDaySteps` → bundle `steps.value` (`local_repository.dart:1402,1497–1503`); the steps trend comes from unversioned `metric_series` (`_g3Steps`, `:368–377`). Sleep and Erholung follow the same split through `readMetricHistory` (`:2617–2642`). `day_result` is capped at `kAlgoVersion`; `metricSeries` is not (`db.dart:13440–13454`). After a downgrade, or during an in-place recompute, the headline and the trend for the same date can differ. Nightly HRV/RHR/respiration/temperature already use the typed `day_result` path (`:2622–2630`). Decision, with the storage audit.

The legacy `DayStepsDetail` also showed two different step totals (`total` vs `dayTotal`, `ui2/screens/day_steps.dart:317–404`); it is part of DC-1 and is deleted with it.

### DUP-3, DUP-4 · safe merges (P3)

- `G3CheckInPreview.buttons` (`g3/day.dart:463–483`) repeats `OBYesNoKeys` line for line (two `Expanded` `OBActionSecondary`, Nein/Ja, height 40, gap 8). Use `OBYesNoKeys` and keep "Später" as the row's other child.
- `today_note.dart:17–18` and `cycle_medians.dart:972–973` pad `DateTime.hour/minute` exactly like `g3Clock` (`g3_format.dart:33,40`). Use `g3Clock`.
- `cycle_comparison.dart:710–713` and `cycle_observations.dart:413–421` choose the German singular exactly when `count == 1`, like `g3CountNoun` (`count_copy.dart:1–2`). Use it, keeping each full string unchanged.

### DUP-5…7 · merges that change pixels or copy (P2)

- Check-in card: `OBCheckIn` (padding 18, icon 18, title 18/22) vs `G3CheckInPreview` and `OBCheckInAsk` (padding 16/14, icon 16, title 19/24, different "later" placement). Production Heute uses `OBCheckIn` (`heute.dart:1211`); the other two only feed specimens and `blocks.json:1173,1183,1196,2144–2153`. Unifying saves 180–260 lines but changes Paper blocks.
- Stat cells: `_nightFacts` (`g3/screens/sleep.dart:750–818`) differs from `OBStatRow` (`g3/metrics.dart:1150–1240`) in label size 10 vs 11, padding 10 vs 14, divider, per-cell mini scale and text-scale clamp 1.3. `_stat` in `training_live.dart:641–667` uses 26/31 values and no card.
- Dashed painters: `_DashPainter` (`g3_theme.dart:321`), `_DashedTrack` (`band_parts.dart:857`), `_DashLine` (`day.dart:829`) differ in dash length (3 vs 4), radius and bounds.
- `OBPanel` vs `OBCard` (padding 18 vs 14, link hit-testing); `OBToggle` vs `_OBSettingsSwitch` (46×28 custom vs `CupertinoSwitch` 51×31).
- Formatters: `g3_format.dart` has no unsigned number, grouped count, elapsed-seconds, unit or plural helper. `obDuration` (`theme.dart:431`) prints `0h30` where `g3Duration` prints `30 Min.`. `obNumber` groups thousands where `g3Number` does not. `g3Number(0.04, digits: 1, signed: true)` gives `+0,0` where `g3Signed` gives `0,0`. No other formatter pair is identical for all inputs, so none is merged here. `g3Number`/`g3Count` live in `g3_theme.dart:280–298` rather than `g3_format.dart`; moving them is possible but removes no lines.
- Colour literals: `OB.stageDeep` (`theme.dart:81`), `G3.hypnoLane` (`g3_theme.dart:69`) and the neutral zone endpoints repeat `AlpColor` values. They are separate semantic roles, so aliasing them is a token decision.

## 3. Structure

Owned files over 1,500 lines at the base (lines):

| File | Lines | Seam |
|---|---:|---|
| `state/app_state.dart` | 7,448 | `LiveWorkoutState` 7063–7448 → part file |
| `openband/synthetic_repository.dart` | 5,702 | one stateful adapter; fixture helpers 5497–5702 only |
| `openband/local_repository.dart` | 5,024 | one class (118–4753); no behaviour-preserving split |
| `openband/screens.dart` | 3,379 | `OpenBandSleep` and its widgets 2181–3379 → part file |
| `ui2/profile/devices.dart` | 2,779 | `DeviceDetail` 1763–2779 |
| `openband/domain.dart` | 2,619 | strength-template types 723–1108 → part file |
| `ui2/profile/gallery.dart` | 2,439 | poster/flows 1848–2439 |
| `ui2/grammar.dart` | 2,434 | `ChartFrame` 1907–2342 |
| `ui2/activity/live.dart` | 2,424 | per-sport live widgets 1114–2424 |
| `openband/medication.dart` | 2,384 | plans/editors 864–1731 |
| `openband/cycle.dart` | 2,358 | history 1554–2358 |
| `openband/nutrition.dart` | 2,226 | `OBMacroBars`, `OBMealSection` 1260–1706 |
| `openband/strength_live.dart` | 2,191 | exercise block/set row/rest timer 889–1991 |
| `ui2/workout_screen.dart` | 2,136 | history loading 1725–2136 |
| `ui2/screens/metric_detail.dart` | 2,097 | shrinks to ~900 with DC-1 |
| `ui2/activity/summary.dart` | 2,094 | result/statistics types 102–640 |
| `openband/meal_entry.dart` | 2,061 | sheets 1356–2061 |
| `openband/health.dart` | 1,981 | sourced trend chart 842–1789 |
| `openband/g3/chrome.dart` | 1,953 | actions/segments/sheets 1120–1601 |
| `ui2/screens/home_screen.dart` | 1,933 | shrinks to ~1,235 with DC-1 |
| `openband/g3/screens/journal_screen.dart` | 1,929 | customise/answer sheets 1321–1929 |
| `ui2/screens/sleep_detail.dart` | 1,806 | deleted with DC-1 |
| `openband/g3/screens/training_screen.dart` | 1,780 | `G3ActivityScreen` 729–1293 |
| `openband/night_scalar_detail.dart` | 1,775 | chart painters 1495–1775 |
| `openband/labs.dart` | 1,765 | marker editor 1065–1581 |
| `openband/nutrition_goals.dart` | 1,759 | goals editor 594–1432 |
| `openband/g3/screens/heute.dart` | 1,727 | reminder types 37–156 only |
| `ui2/profile/profile.dart` | 1,623 | helper rows 46–369 |
| `ui2/profile/settings.dart` | 1,612 | `EditProfile` 1004–1422 |
| `openband/vo2.dart` | 1,566 | removed/history pages 1044–1439 |
| `openband/sleep_editor.dart` | 1,548 | painters 42–171 only |
| `health/health_export.dart` | 1,509 | no large seam |

Dart privacy is per library, so the cheap split that keeps every private reference working is a `part` file. `tool/check_design_manifest.py` looks for a class in the file named by `blocks.json`, so moving a registered class also updates its manifest path.

Longest `build()` bodies: `sleep_editor.dart:511` 542 lines (widget depth 11), `notification_settings.dart:513` 487, `g3/screens/verlauf.dart:268` 365, `template_editor.dart:507` 360, `ui2/profile/data.dart:590` 358, `g3/screens/journal_screen.dart:673` 342, `g3/screens/training_screen.dart:951` 341, `openband/metric_detail.dart:217` 324. Depth over 10: `day_picker.dart:83` (12), `sleep_editor.dart:511` (11), `labs.dart:1340` (11). 72 bodies exceed 150 lines.

Business logic in widgets, top ten: suggestion confirm/export policy in `ui2/screens/log_workout.dart:142–208`; tombstone-then-delete in `ui2/screens/workout_screen.dart:632–657`; NutritionDb reads and the barcode network lookup in `log_food.dart:119–210`; civil-day relocation and acknowledged writes in `meal_entry.dart:395–577`; baseline ±1.253·spread and deltas in `night_scalar_detail.dart:950–1140`; hero mean/latest in `ui2/screens/metric_detail.dart:1104–1115`; interval/lap extrema in `ui2/activity/summary.dart:1263–1561` (the 90 % threshold is `ponytail:`-marked); request composition and week-strip projection in `g3/screens/heute.dart:307–1436`; plus two inside DC-1 (`sleep_detail.dart:1120–1370`, `investigate.dart:1073–1115`). Move each into its `*_data.dart`/repository seam when the feature is next edited. None is a proven wrong value outside DC-1.

Shared mutable state: `LiveDraft._current` (`ui2/activity/live.dart:242`), `OnboardingBypass.revision` (`ui2/onboarding/pairing.dart:44`), `AppColors.active` (`theme/tokens.dart:176`), `Prefs._sp`, `HealthExporter.shared`, three notification singletons, telemetry, screen-wake and widget caches. Each is an intentional app-lifetime service; no cross-screen leak was shown.

STR-3: telemetry calls Firebase futures inside a synchronous `try/catch` (`telemetry_service.dart:84–86,154,175,214,225,236,360`), so a rejected future escapes it. The resolved `firebase_analytics` 12.5.0 `logEvent` is async. The repo has no Firebase config (`ios/Runner/GoogleService-Info.plist` is absent) and `main.dart:39–47` continues without Firebase, so this is latent. Fixing it changes failure behaviour, so it is a decision.

## 4. Dependencies

- Unused: `cupertino_icons` (`pubspec.yaml:22`) and `fl_chart` (`:503`). Zero `package:` imports in any directory, no `CupertinoIcons` use, no native registration (both are pure Dart). Removing them also drops the transitive `equatable`. In a scratch checkout, removal resolved and analyzed clean.
- `flutter_lints` (config) and `flutter_launcher_icons` (build tool) have no imports by design. `workmanager` stays deliberately (it cancels legacy tasks). No other direct or dev dependency is unused.
- Security: an OSV batch query over all 206 resolved hosted versions returned no advisory; `pub outdated --json` flags none. Git sibling pins and SDK packages are outside OSV matching.
- Outdated: 28 direct packages have a newer resolvable version, most behind a major bound (`flutter_blue_plus` ^1 → 2.3.13, `flutter_local_notifications` 18 → 22, `health` 12 → 13, `share_plus` 10 → 13, `file_picker` 8 → 13, `device_info_plus` 10 → 13, `home_widget` 0.6 → 0.10, `timezone` 0.9 → 0.11). Within current bounds only patch/minor updates are available: `archive` 4.3.0, the Firebase set, `gpt_markdown` 1.3.0, `lucide_icons_flutter` 3.1.20, `mobile_scanner` 7.4.2, `flutter_secure_storage` 10.3.4. Flutter 3.41.6 / Dart 3.11.4 blocks `sqflite` 2.4.4, `sqflite_common_ffi` 2.4.3 (Dart ^3.12), `cupertino_icons` 2.0 and `test` 1.32 (test_api pin); `clock` and `intl` are pinned by `flutter_test`/`flutter_localizations`. The deliberate `sqflite_common` 2.5.8 pin (`pubspec.yaml:622–627`) also blocks the sqflite line.
- The comment at `pubspec.yaml:562` says `device_info_plus` is capped below 11 by `health`. `health` 12.2.1 actually allows `>=9 <12`. Corrected in this branch.

## 5. Lints

Baseline: 0 issues with `flutter_lints` 6.0.0, which already enables `use_build_context_synchronously`, `avoid_print` and `no_leading_underscores_for_local_identifiers` (0 hits each).

| Candidate | Total | Owned lib | Other lib | Tests | Notes |
|---|---:|---:|---:|---:|---|
| `cancel_subscriptions` | 0 | 0 | 0 | 0 | free guard |
| `close_sinks` | 0 | 0 | 0 | 0 | free guard |
| `strict-casts` | 1 | 1 | 0 | 0 | `telemetry_service.dart:354`, one explicit type; whole-repo analysis adds `tool/g3_review_test.dart:165` |
| `always_declare_return_types` | 1 | 0 | 0 | 1 | test only |
| `only_throw_errors` | 4 | 4 | 0 | 0 | rethrows of caught `Object`; not bugs |
| `prefer_final_locals` | 17 | 14 | 2 | 1 | style; touches other owners' files |
| `unnecessary_lambdas` | 38 | 23 | 2 | 13 | style; tear-offs change callback identity |
| `avoid_dynamic_calls` | 49 | 21 | 0 | 28 | JSON boundaries; no crash shown |
| `unawaited_futures` | 61 | 45 | 3 | 13 | reloads and route futures; no new bug in sample |
| `strict-raw-types` | 73 | 15 | 11 | 47 | typed boundary pass |
| `strict-inference` | 79 | 20 | 31 | 28 | typed boundary pass |
| `prefer_const_constructors` | 182 | 33 | 0 | 149 | style |
| `discarded_futures` | 263 | 223 | 12 | 28 | finds STR-3; the rest mostly intentional |
| `directives_ordering` | 393 | 182 | 30 | 181 | style |
| `avoid_catches_without_on_clauses` | 934 | 612 | 316 | 6 | best-effort catches, mostly deliberate |
| `avoid_redundant_argument_values` | 971 | 199 | 106 | 666 | style |
| `unreachable_from_main` | 1 | 0 | 0 | 1 | entry libraries only |

Enabled in this branch: `cancel_subscriptions` and `close_sinks`, which cost nothing and catch leaked streams and sinks in new code. `strict-casts` also flags `tool/g3_review_test.dart:165`, where a `Map<dynamic, dynamic>` from JSON is spread into a `Map<String, dynamic>`. That file is Paper harness tooling owned by the test-suite audit, so `strict-casts` waits until that line has an explicit cast; the lib change is then `params[k] = v as Object` at `telemetry_service.dart:354`. Worth a focused follow-up: `unawaited_futures` (61 sites to triage one by one) and `discarded_futures` (it found STR-3). The rest are style, or large boundary passes that belong to their own change.

## Decisions for Mats

1. **Registry-only widgets.** `MetricRing`, `NightChart`, `OBCheckInAsk`, `G3CheckInPreview`, `OBMetricCard`, `OBPatternDotPlot` and `OpenBandRunLive` are never built by the app. They exist for `blocks.json` blocks, Paper specimens or tests. Removing them means removing their manifest blocks and Paper registry entries (fewer than 207 blocks). Recommendation: retire the ones whose Paper block is superseded by a G3.1 component (`OBCheckInAsk`, `G3CheckInPreview` → `OBCheckIn`; `MetricRing`, `NightChart` → G3 charts). That needs your call on the design manifest.
2. **Check-in card and stat cells (DUP-5, DUP-6).** Unify on `OBCheckIn` and `OBStatRow`; 180–260 and 45–85 lines. Pixel changes on Schlaf and the check-in specimens.
3. **Day snapshot and headline/trend source (DUP-1, DUP-2).** One `day_result` projection for every value on the day screen and in its trends. Changes what is shown during a recompute or after a downgrade. Needs the storage owner.
4. **Formatter contract (DUP-7).** Decide whether `obDuration`, `obNumber` and the day labels adopt the G3 forms. `0h30` → `30 Min.` and grouped thousands are copy changes.
5. **Telemetry error handling (STR-3).** Route the Firebase futures through a `catchError` that does not report back to Firebase. Latent while Firebase is unconfigured.
6. **Dependency majors (DEP-2).** Upgrade one package per change, each checked on the phone: `flutter_blue_plus` 2, `flutter_local_notifications` 22, `health` 13 + `device_info_plus` 13, `share_plus`/`file_picker`. The sqflite line waits for Flutter ≥ 3.44.
7. **Large-file splits beyond this branch.** `local_repository.dart` (5,024) and `synthetic_repository.dart` (5,702) are one class each. Shrinking them means splitting the `OpenBandRepository` interface by feature, which is an API redesign.
8. **Test-only helpers (DC-5 last bullet).** Delete each helper together with the tests that only exercise it, or keep them as seams.

## For other owners

- Storage (`lib/data`, `lib/compute`): DUP-1 and DUP-2 need a coherent served-row projection and a policy for versioned `metric_series`. `putMetricSeriesValue` (`data/db.dart:13419`) has no caller. Large files: `data/db.dart` 16,071, `compute/derivation_engine.dart` 9,073, `data/local_repository_impl.dart` 4,531, `compute/onehz_pipeline.dart` 1,955, `compute/substrate.dart` 1,513.
- Reliability (`lib/ble`, `lib/sync`): `ble/ble_engine.dart` 8,619, `ble/ble_state.dart` 2,082, `ble/adapters/_registry.dart` 1,674. Lint counts in their code: `discarded_futures` 12, `unawaited_futures` 3, `strict-inference` 31, `avoid_catches_without_on_clauses` 316. The native background arm/start futures at `state/app_state.dart:2786,2789` are unawaited; ownership of their failure handling sits with reliability.
- Test suite: `tool/g3_review_test.dart:165` blocks `strict-casts` (see LINT-1). `test/ui2_home_health_golden_test.dart` covered only DC-1 screens and is deleted; it had no tracked PNGs. `test/hrs_link_test.dart:31` `kBpmOnlyWithContact` is unreachable. The full Paper harness run fails 38 tests on the base; the cause is unexamined.

### Retired Ponytail ceilings

These comments belonged to the deleted legacy screen cluster. They are retained
here as historical simplification notes; the reads they describe no longer run.

```dart
// Retired from lib/ui2/screens/circadian_detail.dart
// ponytail: N bundle reads per open. If this ever feels slow, the fix is a
// `sleepWindows({days})` repo method that reads onset/offset without the
// payload, not a smaller number here.
// Retired from lib/ui2/screens/circadian_detail.dart
    // ponytail: 7 more bundle decodes on a screen that already does 42. If
    // this screen ever feels slow the fix is one repo method that reads
    // `daytime_hrv` without the payload, not a smaller week.
// Retired from lib/ui2/screens/investigate.dart
  // ponytail: N bundle reads per open, same shape as the actogram's. If this
  // ever feels slow the fix is a repo method that reads `cvhr_per_hour` and
  // `analyzed_hours` without the payload, not a shorter window — the window is
  // the gate.
```
