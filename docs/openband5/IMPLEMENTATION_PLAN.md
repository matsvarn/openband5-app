# OpenBand 5 implementation plan

Current continuation: 21 September 2026. Alpin 3 in Paper file `01M2TRX5GZKAXKTSXK7D34E8AY` is canonical. Designphase 2, `01M2KDQRH0A9K3N46EWHMBF61D`, is a frozen archive. Flutter remains the UI framework. Local Swift integrations remain responsible for iOS capabilities where appropriate.

## Alpin continuation

The current assignments, accepted commits, evidence and next unit are in **Active continuation** below. The queue is `design/state_checklist.json`; unmarked archive states require source, route and Paper reconciliation before rebuilding. Accepted unit evidence is in `IMPLEMENTATION_VERIFICATION.md`. Earlier handoffs remain in Git history.

Work only in edge on `openband5/ios-device-setup`. No push, merge, deploy, personal-data access, physical-device review or Bluetooth operation is authorized. Preserve unrelated assets. Lead owns Paper and acceptance; isolated Mats workers own implementation and ordinary test/debug loops. Every unit needs an inspected native render, required checks and a local commit. Paper and Flutter should match closely; remove redundant explanations while preserving source, timing and uncertainty.

## Architecture and retained work

| Concern | Decision and present implementation |
| --- | --- |
| Packages | Keep `openstrap_edge`, `openstrap_protocol`, `openstrap_analytics`. Bytes/record decoding belong in `protocol`; metric algorithms in `analytics`; sessions, persistence, jobs and UI in `edge`. |
| State | Keep Provider, `AppState`, existing BLE engine and Sqflite. `OpenBandController` owns selected-day reads and correction progress. No new state library. |
| Storage | Schema **65**, additive migration and same-version repair. Durable sleep drafts, correction revisions and calculation jobs (52); workout templates, meal drafts and frozen session-detail snapshots (53); user lap marks (54); durable nap recalculation jobs and original bounds (55); optional sleep-goal periods (56); per-result lab report bounds (57); template pin/archive (58); durable live strength state (59); custom-field visibility (60); dated nutrition targets (61); exercise registry provenance (62); original strength load and definition snapshots (63); imported measurement source/timing, receipts and exclusions (64). full medication plan revisions (65). Original records remain retained. |
| Algorithms | Version **90** invalidates prior derivation output after generation-aware dispatch changes. Existing analytics run in isolates. No new physiological algorithm in UI or repository. |
| Read boundary | `LocalOpenBandRepository` translates the legacy repository and persisted day payload into typed values. It refuses malformed day payloads and prevents today's legacy fallback from borrowing a different night's values. Legacy screens retain their existing adapter until their package migrates. |
| UI | Four-tab shell is active and all four tabs render the OpenBand (Alpin) screens: Übersicht, Gesundheit, Training (Quick-Start, templates, live strength, live run, session detail), Journal (mood, yes/no habits, pattern card) with Ernährung · Tag (meal drafts, food search). Design contract: `docs/openband5/design/` (tokens.json, blocks.json, README) mirrored by `lib/openband/alp_tokens.dart`; Paper file `01M2TRX5GZKAXKTSXK7D34E8AY`. Legacy screens remain only as detail destinations (activity picker, journal editor, profile, onboarding). |
| Existing fixes | Retain local onboarding Back/pairing, birth-date profile/recalculation, signing and widget changes. All implementation uses this working tree, including untracked files. Baseline backup is outside Git. |
| Dependencies | Flutter **3.41.6**, Dart **3.11.4**. Inter Tight (OFL) added as the display face; Tabler Icons 3.46.0 (MIT) bundled as SVG for sport pictograms; `flutter_map` now used for the consent-gated live route map. Protocol `fe1464db98b84ac4d3ce6175d54ada11356d6c62`; analytics `1fa8144a5e3b728ce91eeed6ecbc15d482933b44`. Protocol/analytics pins unchanged. The later development setup adds the Flutter SDK integration-test dependency and its lock entries; existing package versions stay unchanged. Inter added as a bundled font with OFL; existing Lucide package reused. |

Confirmed blockers addressed for this flow:

- Database replay and substrate dispatch identify Gen5 before legacy R24 decoding. Identified optical/deep-buffer records cannot fall through as Gen4 biometrics. The pinned protocol already supplies the typed discriminator; no duplicate byte decoder was added.
- The automatic three-day substrate pruning and v20 archive thinning paths are disabled under the OpenBand retention policy. Existing lost source cannot be recovered by this change. Retention is currently unbounded; measurement and a user-visible archive/export policy are WP14.
- A confirmed sleep correction commits override, revision, pending job and draft deletion atomically. The transaction itself returns the receipt. Failure leaves the draft; calculation failure leaves the correction and previous result.
- Calculation verifies its correction revision again inside the result/series transaction. An old foreground/background result cannot replace a newer correction. Reopened `calculating` jobs become `pending`; selected pending jobs resume, failed jobs require explicit retry. Jobs for other days wait until selected.
- Strict correction recalculation must produce a fresh complete day with the requested window. Missing source or a failed compute phase produces a failed job, never a false success. Commit-before-ACK is unchanged.

Remaining correctness work is explicit: verify Gen5 v18 channel meaning and firmware variants; reconcile legacy contaminated results where originals survive; measure archive growth; prove physical interruption/recovery. Decoder dispatch tests do not establish WHOOP measurement validity.

## Navigation, dates and typed contracts

Four tabs: **Übersicht · Gesundheit · Training · Journal**. Each has a keyed, lazy Navigator retained in an IndexedStack. Pushed details hide the tab bar as in Paper; back returns to the original stack and scroll position. Tab choice and selected local day persist independently. Legacy saved tab indices migrate to the new tab names. Nutrition is a Journal child; profile and band remain secondary destinations.

The selected day belongs to the shell/controller. Calendar selection is staged until “Tag ansehen”; cancellation changes nothing. A night belongs to its wake day. A draft captures that day and never changes at midnight or after an unrelated date selection. Older asynchronous reads cannot replace a newer selection. Persisted day writes remain ordered. Historical screens never borrow today's recovery or a previous night's sleep.

External notifications/intents retain the existing allowlisted route dispatcher and select the appropriate tab before pushing. Unknown payloads open Übersicht without writing. Object-specific restoration, missing-object screens, and day propagation into every legacy Journal/Training/Health editor are migration requirements for WP4/WP6/WP8–WP12, not completed shell features. Legacy roots may still use their own today/period context; opening them does not overwrite the shared selected day.

| Contract | Fields / ownership |
| --- | --- |
| `OpenBandDay` | Local day; one `SleepNight`; recovery, strain, HRV, resting-HR and steps; correction; step intervals; intake; calculation timestamp; explicit synthetic flag. Same snapshot feeds overview and details. |
| `DayMetric` | Nullable value, typed readiness, optional reason and persisted comparison baseline. Current readiness distinguishes available, partial, processing, missing, unreliable and unsupported. WP4 will distinguish insufficient history from insufficient coverage structurally and add the full versioned method/unit/source-window descriptor required by B163. |
| `BandSnapshot` | Connection, transfer, battery and its observation time, durable stored-through cursor, independent receipt time. The latter stays absent when storage cannot establish it. A BLE receive timestamp is not a storage receipt. |
| `SleepNight` / `NightSegment` | Explicit onset/wake instants, recording zone when known, duration/composition, dated history and time-bounded segments. Null stage means unobserved interval. Never interpolate a gap. |
| `SleepDraft` | Stable ID, immutable wake-day key, onset/wake and recording zone. Draft writes are serialized. Existing recording-zone absence is disclosed; no invented zone metadata. DST-invalid wall times are refused; ambiguous times retain a known offset or require correction. |
| `SleepCorrection` | Stable operation ID, revision, saved time, requested bounds and independent pending/calculating/complete/failed state. Automatic restore is also a durable calculation job. |
| `StepInterval` / `DayIntake` | Actual time bounds/counts; nullable energy and water. Known energy plus unmeasured food is a lower bound, not a complete total. Missing intervals remain missing. |

No screen interprets storage maps or computes an alternative recovery/sleep score. The sleep ring uses time in bed as denominator and sleep duration in its center; recovery remains 0–100, strain 0–21. Baselines come from the result for the selected day, not the latest global average.

## Shared components and Paper references

| Component / behavior | Reference | Implementation and remaining scope |
| --- | --- | --- |
| Overview, rings, metric cards | `1V0-0`, `1Y8-0`, `3YL-0` | `screens.dart`, `charts.dart`; light/dark, gaps, readiness, dense nights. Lower feed/customization `8OM-1`, `11QX-0`, `LUP-0` are still WP1/WP6/WP9. |
| Steps, nutrition/water chips | `1V0-0`, `1Y8-0` | `daily_activity.dart`; selected-day values, real available spans, drill-down sheets. Full step analytics WP4; entry workflows WP8/WP9. No invented sparkline when spans are absent. |
| Date route / empty / historic | `AF2-1`, `AJS-1`, `3R2-0` | `day_picker.dart`; full-screen calendar, actual sleep-day availability and selected-night preview, Monday-first layout, confirm/cancel. Recovery/strain selectors remain WP4; no inferred availability from sleep. |
| Band state / gaps | `2B9-0`, `2EM-0`, `2HU-0`, board `766-0` | Independent connection/storage/readiness, accessible gap values. Actual recovery protocol WP3. |
| Sleep and phases | `22Q-0`, `25K-0`, `28E-0`, `IA-0`, `16RN-0` | Working sleep route, stage summary/interval sheet, history, metrics and correction. Full B135 hub/session separation, planning, `19QM-0` and `16UZ-0` scroll continuations, night physiological curves and metric switching remain WP4/WP5. |
| Edit → preview → receipt → result | `JN-0`, `L1-0`, `M8-0`, `NG-0`, `OT-0` | `sleep_editor.dart`; distinct save/recalculation, durable draft, actual revision result. Shared wrapping header, compact time fields, actual duration delta, original timeline plus edited bounds in preview; separate pending/failure/completed receipts and return/restore actions. |
| Invalid / save failure / restore | `1GDQ-0`, `1GDD-0`, `6B2-0`, `15O-0` | Validation, retry, retained draft/correction, automatic restore, zone-aware times. Unknown original recording zone remains visible as unknown. |
| Typography / navigation / large text | `73C-0`, `CS8-0`, `7J6-0`, `6HX-0`, `7NI-0`, `6LV-0` | Shared Inter tokens, Lucide, 16 outer/14 card padding, 20 radius, 12 card gap, 44-point actions, wrapping and scrolling. Dedicated readable small-text colours; reduced-motion route transitions. |

The saved Bevel/WHOOP research in [DESIGN_RESEARCH.md](DESIGN_RESEARCH.md) and the reviewed flow files inform interactions. Approved OpenBand Paper remains the visual target. Historical Bevel “old” flows do not create parallel product screens.

## Dependency-ordered packages

Each package must pass implementation, visual, automated and physical checks separately. `primary_package` in the coverage file gives one owner for overlapping backend requirements; `packages` lists consumers. Cross-cutting B162–B166 are shared obligations, not hundreds of separate projects.

| Package | Dependencies | Status / acceptance gate |
| --- | --- | --- |
| **WP0 · contracts and components** | — | **First-flow foundation implemented.** Typed values, honest missing states, retained source and durable mutation lifecycle. Whole-app metric descriptors and remaining mutation families stay partial. |
| **WP1 · shell and day context** | WP0 | **Four-tab foundation implemented.** Independent stacks/day persistence/returns; existing roots retained. Complete Paper home feed, card customization, missing-object routes and global legacy day migration remain deferred within WP1. |
| **WP2 · overview and sleep correction** | WP0, WP1 | **Functional first flow implemented.** Save/retry/relaunch and recalculation integration tested; representative visual states reviewed. Full sleep-related design families below remain assigned, not declared complete. |
| **WP3 · WHOOP capture and recovery** | WP0–WP2 | **Next.** Retain pairing fixes; onboarding must end in a real commit receipt. Verify firmware/channel decoding and physical disconnect, app interruption and resumed capture without loss/duplication. No fake percent, calibration counter or ACK before commit. B01/B02/B04/B104/B146/B155. |
| **WP4 · metrics and detail system** | WP3, WP0 | **Queued.** Versioned unit/method/source/coverage descriptor and reusable gapped curves, comparison, explanation. Recovery/HRV/RHR/steps/night detail families share this. No invented score or daytime stress windows. B41/B43/B117–B119/B135/B137/B139–B142/B147–B152/B163. |
| WP5 · sleep planning and extras | WP2, WP4 | Deferred. Separate main sleep hub, session, naps/manual sleep, duration/share/need and goals. Repair wrong-night need before exposing attainment (B136/B137). No automatic goal without a defined rule. B31/B45/B106/B131. |
| WP6 · training | WP1, WP4 | Deferred. Live and recorded sessions; persistent live chip/resumption; atomic finish, draft retained on failure (B138); correct HRR post-exercise window (B19). |
| WP7 · templates and exercises | WP6 | Deferred. Stable exercise/template identities, equipment and ordering, duplicate/undo and editing flows. Photo OCR B37 remains optional/P2. |
| WP8 · nutrition | WP0, WP1 | Deferred. Journal child, date-bound food drafts, confirmed atomic entries, lower-bound totals, source and unknown nutrients. OFF/photo/OCR only after explicit provider/consent decisions (B05–B07/B13–B15). |
| WP9 · journal and patterns | WP0, WP1 | Deferred. Check-in/water, drafts and history; no automatic daily answers (B130); unify competing evaluation paths (B93). |
| WP10 · meds, cycle, breathing, labs | WP1, WP4 | Deferred. Separate persisted logs, timers and source-backed manual/import values. No fertility/ovulation; >60-day cycle gaps block prediction (B157). Timer from monotonic active time (B166). |
| WP11 · sources, Health and band | WP3 | Deferred. Provenance, import and strict recalculation errors (B53/B61), connection management and band-confirmed alarm. Free weekday cannot leave old alarm armed (B45/B131). |
| WP12 · settings and external entries | WP1 | Deferred. System/light/dark theme across remaining surfaces (B144), settings drafts, missing objects, widget/intents (B134), units/method changes; unknown freshness stays unknown. Legal drafts require product review (B132). |
| WP13 · optional assistance | WP4 | Deferred. Coach/photo/support/template assistance only with explicit local/external boundaries. Repair deletion completeness (B68). No subscription/account/paywall; Bevel flow 002 is deliberately rejected. |
| **WP14 · archive and export** | WP3 | Deferred, explicit owner for 16 archive designs and B160. Measure current unbounded retention growth/battery; design reviewed archive/export budget. Full backup includes retained originals, DB and manifest, reports missing parts. CSV is not raw PPG. No silent pruning to solve disk growth. |

All other B-IDs are listed individually in the coverage file against these packages and retain their acceptance criteria from [DESIGN_BACKEND.md](DESIGN_BACKEND.md). No designed flow is dropped because it was not required for this first implementation.

## First-flow acceptance and backend status

| Requirement | Acceptance | Current status |
| --- | --- | --- |
| B04, B146 | Connection, transfer, battery observation, stored frontier, coverage and per-metric readiness remain independent; disconnected results stay visible. | Implemented for first-flow adapter/UI; richer readiness taxonomy and physical frontier proof remain WP3/WP4. |
| B54 | One persisted selected local day; staged calendar; no borrowing another day's night or future history; immutable draft day. | Implemented and regression tested. Other legacy feature editors await migration. |
| B90 | Dense overview with correctly scaled rings, meaningful cards and actual actions. | Core through Steps implemented; entire lower feed/live chip/customization remains WP1/WP6/WP9. |
| B117, B118 | One night representation, proportional stages, accessible gaps, correction without raw mutation. | First route implemented. Full night curves/method metadata and current session detail depth remain WP4. No copied “old” Bevel screen. |
| B135, B137, B148 | Duration is not a sleep score; dated history and distinct time-window editing; need/goal not fabricated. | Duration/history/edit implemented. Separate full hub/session, planning and share/need detail remain WP4/WP5. |
| B155, B166 | JN → L1 → durable M8 → NG or OT; failed saves retain draft, failed calculation retains correction; stale result cannot win. | Implemented; real SQLite/AppState calculation, failure, reopen, duplicate save and revision tests. |
| B163 | Overview/chart/detail use the same typed snapshot and semantics; absent intervals remain explicit. | First-flow snapshot implemented; full cross-metric versioned descriptor remains WP4. |
| B164 | Actions open the displayed item/day; return restores selected day/location; sheets/keyboard respect safe areas. | First-flow navigation, sheets, draft/retry and per-tab stacks implemented/tested. Legacy/deep-object routes remain scoped above. |
| B165 | Paper density/light/dark, readable small text, 44-point targets, larger text and accessible interval values. | Rendered tests and reference review; native VoiceOver/Bold Text/Increase Contrast still require device interaction. |
| B160 | Source remains available for recalculation and export; failures do not claim complete archive. | Retention safety implemented. Archive UI, growth measurements and complete export remain WP14. |

The canonical synthetic example is **23:10–06:54**, 464 minutes in bed, 438 asleep, 26 awake. Editing to **23:25–06:54** produces a 449-minute window; the fixture clips to 428 asleep/21 awake. This is a deterministic UI fixture, not physiological restaging evidence. Partial coverage retains 24 missing minutes; short gaps display “<1 Min.” rather than rounding to zero.

## Implementation, visual and device tracking

[IMPLEMENTATION_VERIFICATION.md](IMPLEMENTATION_VERIFICATION.md) contains commands, result counts, screenshot locations and limits. The coverage JSON stores these tracks per package and per artboard. `partial` is intentional: implementing a shared flow does not complete every associated artboard or downstream backend requirement.

The development gallery is `lib/main_gallery.dart`, enabled only outside release builds. Run `flutter run -t lib/main_gallery.dart` with the pinned SDK. It creates only an in-memory synthetic repository; it does not initialize the production app, BLE or database. Complete, dense, partial, missing, processing, disconnected, interrupted, draft-write failure, save-failure and calculation-failure scenarios share approved fixtures. Theme and text scaling are selectable. Real phone screenshots and databases remain outside committed fixtures.

The first-flow Paper-to-native pass is recorded in the [visual comparison](assets/review-20260917/index.html). Its 56 native checkpoints per device include calendar confirmation, both keyboard fields, draft keep/discard, retries, pending/completed receipts and return/restore. This does not close the deferred full sleep hub, lower feed or metric families.

The next dependency-ordered package is **WP3: physical WHOOP 5.0 capture and interruption/recovery**, followed by WP4's shared metric details. This implementation does not authorize firmware changes, persistent experimental flags, destructive band commands, publishing or release.

## Active continuation · 21 September 2026

Authority: edge/, branch openband5/ios-device-setup, PR1. No push, merge, deploy, personal-data, physical-device or Bluetooth authority. Preserve six unrelated untracked assets. Mats task `/private/tmp/openband-alpin-20260919`; workers use origin-free isolated clones. Minimal visible copy and near-exact Paper/native parity are required. **The redesign remains incomplete; continue through the queue.**

Latest accepted commit **9f78b21**, cycle logging/settings/history; medication plans/entries18f4379. Earlier glucose5295d34, checklist aliasesffe4706, custom exercise/original loadc2b71a1, library06523ff, sleep plan1550b9b and nutrition parent/week/waterf0d60b4 are accepted. Evidence is in IMPLEMENTATION_VERIFICATION.md. Do not rebuild these units.

### Accepted raw cycle unit

Committed **9f78b21**: logging/settings/history. Required1493 tests and82-item analysis passed; DATA53 (America/Los_Angeles), UI54, Journal102 and affected runtime suites passed. All41 goldens inspected. Pro73frames PASS129.4s; final mini73frames PASS228.23s. All final146 PNGs plus preceding mini73 and failed-run evidence inspected. Exact logs, Paper44variants and worker IDs are in IMPLEMENTATION_VERIFICATION.md and task cycle-paper/. Eight raw-state dispositions do not close analytical scope. Previous workers idle; failed93be99fb,4446d397,26860258,78dabe62 are reconciled/retired.

### Measured cycle history acceptance

Implementation and review complete; commit pending. DATA44 tests in America/Los_Angeles; UI25, raw cycle54 and health6 passed. Required1562 tests and85-item analysis passed. All26 changed goldens inspected, including the corrected Material/Lucide isolated-point fixture. Pro42 native frames PASS87.09s; mini42 PASS130.8s, all84 PNGs and run metadata inspected. Production source hashes match both simulator runs. No physical or physiological proof.

Paper35 exports/index are in task cycle-measurements-paper/. Canonical4HA5 and main4HBH/4HG7;32 new real variants, canonical and2 cycle entry exports. Refreshed four info exports after fixing16 Paper footer copies to canonical48min/15–18 type. All16 renders inspected. Registry acceptance records implementation; exact source timing and missing quality remain in disclosure.

Workers idle and accepted: DATA285927ad/ca29c006; DATA reviewer933a2428/26459769; UIffd7073a/c5385695 and fixture repair4a14fc1c; capturee4ab2cff/23dda6e6; fresh reviewer44686273/459a5b36. Lead reviewed source, diffs, reports, logs and images. No unresolved finding for this unit. Legacy CycleTab/getCycle remains until analytical outcomes/callers/tests migrate.

Next: commit complete measured-night unit, then design and delegate remaining cycle analytical outcomes. No next-unit code or Paper design yet. Discoverye68e0ada/eeee6340 is available in task worker reports.

### Next cycle analytical unit

Discovery e68e0ada/343bee3a andff87cc30 read. Use existing pinned analytics median, robustBaseline(minValid3), mdc and z; no new metric algorithms in edge. Retain actual-cycle RHR/HRV, same-cycle-day medians with at least2cycles per point and3eligible points, per-point counts, actual latest metric day, preceding21calendar-day and same-day-in3prior-cycles comparisons, optional observed-gap history. No skin_temp_z relabeling, textbook phase, fertility inference or unsourced24/38 clinical guides. Preserve dense missing slots and civil-day arithmetic. Paper contract/design and implementation assignment remain pending.

Source correction: v90 rhr column is nocturnal low30 mean, but rmssd scalar may fall back from session RMSSD to NREM or whole-window HRV. Do not assume the column is always measured nightly HRV. Inspect rmssd_sleep_session envelope and actual sleep.window/window_json epoch bounds; retain source and timing, refuse ambiguous fallback. Exact-algo day_result only; skip partial/skipped/imported/corrupt and incomplete correction jobs. Caffeine reader query pattern is reusable, but its manual/confirmed-only requirement is too restrictive for cycle. Do not use max-version recentDayResults or oldest-n metricSeries.

Legacy observation counts use only days with nonempty tags as denominator, require3starts, include open-cycle days while claiming completed cycles, and clamp day22+ into week4. Preserve counts and honest missingness; use civil weeks and label open-ended groups truthfully. Note-only/absent entries do not mean no symptoms. Migrate supported outcomes/tests before deleting legacy destinations and getCycle; rough_night SleepDetail reachability needs recheck. Coach writes already use atomic raw storage.

### Remaining queue and known sources

Training auditc2978810/db1b579a is complete. Template list edit/duplicate/pin/archive and template-save-error already exist with Paper/tests; reconcile aliases. Definition copyB65 needs new UUID metadata-only draft plus copiedFrom, no copied history/loads. Definition management/archiveB69 has CASupdate but no UI/archive storage. Template editor reorder/replace/superset/load-to-following remain. Training historyB20/B81 has session queries but no filtered route. Non-run starts still reach legacy WorkoutScreen. Implement supported outcomes, not deferrals.

Also open: nutrition search/manual/barcode/photo/Health/recipes/favorites/customfoods/day close; journal ordering/pins/timed; A08 import/export/coach/widgets; overview lower feed/customization/live chip; full sleep and health/HRV hub parity. Labs/custom-marker and interrupted-transfer alias are reconciled. Dispositions are not blanket completion. Check source/Paper/tests before rebuilding unmarked states. Remove dead Home/Health/Wellness graph only after helpers/callers/tests migrate.

A08 audits29205901/dfc6d24c and58488304/e58ec49e: real CSV/database writers exist. Range DB export omits raw_archive/raw_records and cannot be called an originals archive. Preserve unknown timestamps/undecodable records. Share-sheet completion is not saved-file proof. Storage-full, originals export, incomplete removal, coach and widgets remain supported open work. Copy auditbcea9869: trim redundant instructions, retain source/uncertainty/save-vs-refresh facts.

Release source0.9.31+67, schema65, algorithm90. Protocolfe1464db98b84ac4d3ce6175d54ada11356d6c62 and analytics1fa8144a5e3b728ce91eeed6ecbc15d482933b44 match lock. Six shipping widget/watch configs0.9.31/67; three RunnerTests configs0.9.29/65 need final reconciliation. Flutter ~/.local/share/flutter/3.41.6/bin/flutter. Final release audit remains open.

Unauthorized journal-custom-fields remote was deleted earlier with explicit exact-head authority and read-back. No other remote writes.
