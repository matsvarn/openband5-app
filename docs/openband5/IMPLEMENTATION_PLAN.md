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


**Incomplete. Continue through the queue, committing each accepted unit locally.** Only `edge/`, branch `openband5/ios-device-setup`, PR1. No push/merge/deploy, personal data, physical device or Bluetooth authority. Preserve the six unrelated untracked assets. Mats task `/private/tmp/openband-alpin-20260919`; origin-free worker clones. Lead owns Paper, integration, native review and acceptance. Keep copy short and match Paper closely.

Latest accepted commit **880d2a7** completes HRV/RHR detail, with evidence below. Previous **8560a8a** completes exercise-definition copying: required1794 tests,95-item clean analysis,127-block/649-screen manifest,14 inspected goldens and34 inspected native PNGs. Previous **bd650cc** completes latest-night comparison and retires legacy cycle screens; **0668e1e** adds twelve-month cycle-day medians. Earlier accepted units and their evidence remain in IMPLEMENTATION_VERIFICATION.md and Git. Do not rebuild them.

### Accepted unit: twelve-month cycle-day medians

Implemented and locally verified; this acceptance is committed with the unit. Required **1702 tests**, **91-item clean analysis** and manifest **126 blocks / 597 screens** passed (`build/cycle-medians-acceptance/`). All **37 changed golden PNGs** and **92 native PNGs** were inspected. Pro `build/ui-review/cycle-medians-pro-20260921` passed133.99s; mini `cycle-medians-mini-20260921` passed139.75s. Both contain46 checkpoints with matching run/frames/HTML evidence. Main, light/dark, changed end date, independent selection, gaps, missing/partial/error, actual removal/restore failure and2x scrolling/disclosure are covered. Detailed evidence: IMPLEMENTATION_VERIFICATION.md, Cycle-day medians.

Workers accepted and idle: DATA22aa37e7/320edec6 (fresh f4c51855/37a3db0b), repository754495a9/d0068d26 (fresh7db41698/3db12cb1), UIc18dd914/d1fdc029 (fresh32e77379/caeee52a). Lead inspected actual source/diff and logs. Worker clones and exact Paper exports remain under the Mats task. No active writer.

Locked behavior: fixed anchor+1 calendar boundary, twelve calendar months, whole-window paging without leap drift. Tracking enabled is the only settings gate. Starts are read as of the window end; duplicate/unreadable starts withhold grouping. Intersecting closed gaps or open inclusive ages over60 days are individually excluded; valid remainder stays labelled partial. Median needs2 distinct recorded periods per point and3 qualifying days per chart. Dense gaps and independent RHR/HRV selection/count/source are retained. Pinned analytics owns median, robustBaseline(minValid:3), mdc; zero/undefined proxy absent. No phase, sensor-error or significance claim.

Paper file01M2TRX5GZKAXKTSXK7D34E8AY, token hash a96ee6a1. Main4MX3/4N1K, canonical median4N0F/4N4Z and window4MWU/4N4Q. `cycle-medians-paper/full-index.json` has66 PNG/JSX exports:38 real variants,4 canonical artboards,16 updated root screens,6 measured large-text screens and2 history-removal screens. All changed renders inspected. Shared sourced captions stack below value/unit at2x; OBSourcedSample replaces fabricated chart dates. Source disclosure retains actual bounds, algorithm, quality and envelope metadata; grouping only when the emitted note covers every contributor.

Preview lesson: repeated tool previews sometimes omit unchanged image regions. Original Paper error renders were RGB-identical, and original golden headers contained text pixels. Inspect a full original before alleging a repaint defect. Unsupported extra-pump changes were removed; the existing keyboard capture was retained. All final source checks and native runs used the accepted source.

### Accepted unit: latest-night comparison and legacy retirement

Implemented and locally accepted; committed with this evidence. DATA six files, UI nine files, legacy seven paths and inspected goldens are in main. Registry passes **127 blocks / 637 screens**. Do not rerun the non-idempotent `register-cycle-comparison.py`.

Locked behavior: each metric selects its own latest actual stored night inside the displayed twelve-month window. The preceding21 civil-day reference excludes latest and includes day−21; at least2 nights, possibly before the displayed year. Same-cycle-day references need3 earlier eligible recorded periods inside the year. References abstain independently. Exact algorithm90; analytics owns mean/z. Zero-SD z stays absent. Long or unreadable starts withhold cycle assignment without hiding valid night measurements. No phase/fertility claims. Global coverage counts include the displayed year union the selected prior21 ranges, never unused padding.

DATA author **dd91d838/062660bf** and fresh reviewer **9c164361/c8056eee** are accepted and idle. Lead inspected source, tests and actual logs:43 comparison tests,93 existing cycle tests, six-file analysis pass. Production hashes unchanged after final focused tests. Evidence: `cycle-comparison-data-evidence/` and `cycle-comparison-ui-dependency-snapshot.json` under the Mats task.

UI author **7a901672** owns `cycle-comparison-ui-clone`. Initial53efbf20 and correction89ee65a6 are integrated. Lead returned and verified fixes for long-interval Tag captions, source-envelope grouping, coverage disclosure, root back navigation tests, precise date-control assertions, and equal estimate bounds. Actual correction logs show55 root tests,32 comparison/shared-info tests and clean scoped analysis. All36 changed golden PNGs were inspected; small320 now has explicit settled top/bottom images. Final assignments **7bdbdfea/c3084730** are accepted and integrated: three focused evidence cases, valid prior-window fixture dates and method disclosure bottom/source actions. Actual logs show35 comparison/shared-info tests and the corrected missing-bounds test pass. Author is idle.

Fresh UI review **65c21037/88c550b9** found no product defect in the frozen22-file combined snapshot. Read-only review did not execute checks. It verified source grouping, async guards, selection preservation, shared-info compatibility and legacy removal. Reviewer gaps: missing sleep bounds, unassigned latest/excluded counts, and method-sheet bottom capture stopping before source actions. These are closed. Fresh delta review **be70ebe7** accepted formatting/back-navigation/date scoping. Its suggested unequal card dates after a different anchor are optional: the main fixture already asserts independent15/14Sept dates, while the confirmed1Sept fixture correctly has both metrics on1Sept. No assertion was weakened. Snapshot hashes are in `cycle-comparison-review-snapshot.json`.

Legacy author **b71eb2e6/d2eff283** is idle; lead inspected the seven-file deletion diff and logs. CycleTab and its analytical history are removed; OpenBand raw history, getCycle/rough_night/crossday remain. Scoped analysis passes. Affected tests28 pass/88 intentional absent-golden skips/1 pre-existing gallery inventory failure. Lead reproduced `FirstSyncView`/`OBSetupStatusCard` omission independently on unchanged0668e1e (`cycle-legacy-tokens-baseline.log`). No assertion weakened. Discovery4380a3a0 verified that these are existing OpenBand route/block coverage, not ui2 gallery cells. Author2411f71f added only the two documented exclusions; all10 tokens tests pass. Actual diff/log inspected and integrated.

Paper file01M2TRX5GZKAXKTSXK7D34E8AY, tokens a96ee6a1. `cycle-comparison-paper/full-index.json` contains64 exact PNG/JSX exports, all inspected. Canonical cards4PO7/4PTT; main4PP4/4PUL;375px2x4PZ9/4Q1K; source actions4RMG/4RMX; coverage info4SKJ/4SMW/4SP9/4SQU. New roots4T22/4T47 use the actual comparison fixture estimate25.Sept. Full-scroll Paper roots retain header/footer. Spacing, type, contrast, alignment and fit inspected in both modes.

First Pro capture `build/ui-review/cycle-comparison-pro-20260921` failed only at a broad test date finder matching three legitimate texts. Five emitted PNGs were inspected. Author corrected it to the keyed year control plus both metric dates. This failed run is not acceptance. Required suite1778 passed, final three focused cases passed, required95-item analysis clean. Pro v2 PASS98.09s,54 PNGs and run/frames/HTML all inspected. Mini PASS154.95s,54 PNGs inspected. All108 native PNGs/run/frames/HTML inspected. Checklist and evidence updated; Manifest127/637 passed; committed as **bd650cc**. Continue B65 below.

### Accepted unit: B65 exercise-definition copy

Implemented and locally verified; this record is committed with the unit. Same-library copy flow preserves source, selection/filter context and saved results after refresh failure. New UUID, known typed metadata only, direct `copiedFrom` provenance, unknown semantics unset. Archive/edit remain open.

Author **3baa7617/cb4dfd1d**, final evidence correction **48568f07**, fresh reader **e1a6d863/8593185c** are idle and accepted. Lead reviewed actual diff/source and SQLite tests. Required **1794tests**,95-item analysis and manifest127/649 passed; final stronger selection assertion passed separately. **14goldens and34nativePNGs all inspected**. Pro `exercise-copy-pro-20260921` PASS95.25s; mini `exercise-copy-mini-20260921` PASS122.27s; run/frames/index reconciled. Logs `build/exercise-copy-acceptance/`. Twenty exact Paper references in task `exercise-copy-paper/index.json`. See IMPLEMENTATION_VERIFICATION.md for the full evidence. Initial independent snapshot caught intermediate formatting cleanup; completed-artifact review supersedes it. Snapshot/hash records remain in the task directory.

### Accepted unit: HRV/RHR detail parity and stored-source honesty

Accepted commit `880d2a7`. All callers use the new typed night-scalar family; stale/failed/unproven receipts withhold current values and retain prior provenance in Info. Same stored algorithm anchors7/30/90 history, including corrupt selected payloads. Baseline comparison needs explicit trusted status. Shared leading rows and grouped InfoSheet are extended without parallel implementations. Archive RHR7/30 dispositions are reconciled; broader A05 baseline/quality and A08 method requirements remain explicitly partial.

Required suite1891 passed;99-item analysis clean; manifest127/690. All14 new goldens and all72 native PNGs inspected. Pro36 checkpoints PASS123.03s; mini36 PASS114.27s. Evidence `build/night-scalar-acceptance/`, `build/ui-review/night-scalar-{pro,mini}-20260921-v2`, and IMPLEMENTATION_VERIFICATION.md. All43 Paper exports inspected under task `hrv-detail-paper/`. User-requested14px seven-night bars are included;30/90 unchanged. No code changes after checks. Authors4c5b8d20/c7b808c6,dd7c77bd/c9bda793,a91d57a5/49f52d7b are idle; independent reviews0c8eda6a/38aa7b23,6e2589de/b908e823 and lead corrections closed all current-unit findings. Final source/golden hashes and prior-writer reconciliation remain in the Mats task.

### Completed unit: shared HRV/RHR cards and history

Accepted local commit `1ede5d1`. Required1930 tests and100-item analysis passed; final navigation helper19 tests and integration analysis clean; manifest127/690. All44 changed/new goldens and38 native PNGs inspected. Pro v4 passed23 checkpoints83.18s; mini passed15 affected checkpoints95.49s with all interactions retained. Paper24 card and4 trend exports inspected. Sources, worker findings, failed-run diagnostics and evidence paths are in IMPLEMENTATION_VERIFICATION.md and task night-card-*. No push. Checklist keeps full Health hub and method/quality entries partial.

### Completed unit: adaptive Sleep-stage legend

Accepted local commit `bb6b306f`.1944 tests,102-item clean analysis,manifest127/691;7goldens and16native PNGs inspected. Pro74.52s/mini84.68s pass8 checkpoints each. Source unchanged after fresh review4205877a/9929aa57. Author2cc483bf/fe06127e and test-only61dcf632/deea423b accepted. Paper includes393normal,375normal,3752x light/dark and actual Sleep legends. Details in IMPLEMENTATION_VERIFICATION.md. Full Sleep-page parity and320px2x pre-existing hero/time-axis overflows remain open.

Then complete Health respiration/temperature source-aware detail/hub, dated body/manual-VO2/rhythm/history; then B69. A08 reader7ccf5ea2/3849aed4 completed: reuse CSV/VACUUM/osbk/import, CoachConfig and WidgetService. Missing archive-manifest/share-result, Alpin setup and widget readiness remain real work. Six shipping widget/watch configs match0.9.31/67; three RunnerTests configs are now reconciled0.9.31/67. User-authorized faster workflow groups shared work, isolates writers, filters changed native captures and reuses unchanged evidence; no acceptance gates dropped.

Next-Health source audit7e7bba46/21e26145 confirms stored nightly `scalars.resp_rate` with RSA envelope provenance; do not average the day curve or use the legacy0.5 confidence fallback. Band `skin_temp_z` is SD, but WHOOP imports put Celsius in the same payload key: preserve source/unit and never mix that history. Published values must stay anchored to result version; do not follow the audit suggestion to reuse unversioned metric_series blindly. Manual VO2 has no existing writer after checking profile/journal/lab/import stores; a real dated manual-entry contract/write path remains in-scope. Weight comes from dated journal_metric.weight_kg and existing patch/delete; profile weight is not a measurement. Exact source/test references in the task report. No physiological algorithm change is authorized.

Health follow-up eebcc70b is read and remains advisory. Reuse night-scalar receipt/history assembly, extending exhaustive metric mappings; respiratory scalar/baseline come from payload, temperature has no comparable ADC baseline. Lead rejects the proposal to always plot SD: selected imported Celsius must retain a Celsius history of the same source quantity, with incompatible-unit nights visible as gaps and disclosed. Missing selected input must not borrow a prior headline. Signed temperature needs a line chart; positive HRV/RHR/resp bars keep zero origin. Respiration can open its real stored night curve; temperature has no supported overnight curve and must not route to pulse. Exact presentation/default-unit policy remains to settle in Paper before data/UI implementation.

B69 archive discovery **c2978810/d8067a37** is complete; no implementation assigned. Archive status must be separate from frozen definitions, with monotonic CAS version across edit/archive/restore and explicit null historical-version handling. Existing templates require an archive marker and deliberate continue-or-replace. B123 replacement clears incompatible load semantics, never converts or relabels them; reps↔time clears count fields. Preserve live/history snapshots. Backup restore currently REPLACEs entire exercise rows and may overwrite status/version; resolve that interaction explicitly. Do not mark B69 complete without the template path.

### Remaining supported queue

- Training: list actions/editor already accepted **ad82c97/daa5c0e**. New/saved archive aliases map to existing editor/list; save-failure Paper state still needed. Open: definition metadata editing/archiveB69, template reorder/replace/superset/load-following, historyB20/B81, non-run starts reaching legacy WorkoutScreen. Discovery **c2978810/db1b579a**, alias **f56f12cd**.
- Nutrition search/manual/barcode/photo/Health/recipes/favorites/custom foods/day close; journal ordering/pins/timed; A08 import/export/coach/widgets; overview feed/customization/live chip; full sleep/health/HRV parity. Labs/custom markers and interrupted-transfer aliases already reconciled. A missing repository method alone is not a reason to defer.
- A08 source audits **29205901/dfc6d24c** and **58488304/e58ec49e**: real CSV/database writers exist. Range DB export omits raw_archive/raw_records and cannot claim originals. Preserve unknown timestamps/undecodable records; share-sheet return does not prove a saved file. Storage-full, originals export and incomplete-removal flows remain open.
- Release source: app0.9.31+67, schema66, algo90; protocolfe1464db98b84ac4d3ce6175d54ada11356d6c62 and analytics1fa8144a5e3b728ce91eeed6ecbc15d482933b44 match lock. Six shipping widget/watch configs0.9.31/67; three RunnerTests configs now match0.9.31/67. Required checks use Flutter3.41.6, manifest and native gallery; goldens only test/openband_goldens, never test/goldens.

Unauthorized remote journal branch was deleted earlier with explicit exact-head authorization and read-back. No other remote writes. Historical detailed continuation snapshot is in task `continuation-before-compaction-20260921-0700.md`; accepted evidence remains in IMPLEMENTATION_VERIFICATION.md/Git. Continue until evidence-backed checklist dispositions and all supported flows are implemented, verified and locally committed.

### Completed unit: respiration

Accepted local commit `2c98e0d3`.1971 tests,103-item clean analysis,127/703manifest,14goldens and46nativePNGs inspected. Independent DATA/UI reviews closed, source and actualdiff accepted. Pro72.71s/mini95.48s; testhost SafeArea fix has two filtered replacementcaptures each Pro62.4s/mini66.94s with all interactions retained. Evidence in IMPLEMENTATION_VERIFICATION.md and build/respiration-acceptance. Authors ff054eb1/965b44e3 and c3e786b2/d643adbb+83c43ea2 idle. No pushes.

Next: exact-result source storage prerequisite, then source-aware temperature. Canonical Paper temperature line4YO1 and lightdraft4YPE inspected; dark4YSR/4YTK are clones awaiting refinement. These temperature designs are not accepted implementation or registered screens yet. Full Health and remainingqueue stay open.

### Completed unit: native version metadata

Accepted local commit `47be2c31`. RunnerTests threeconfigurations match0.9.31/67; shippingwidget/watch already matched. Six-line pbxproj change reviewed,plutil lint and independent target/configparse passed.1944tests,101-item analysis and127/691manifest pass. Evidence in IMPLEMENTATION_VERIFICATION.md and build/version-metadata-acceptance. Release archive/physical validation remain separate.

### Completed unit: exact-result source persistence

Accepted with this commit. Schema66 adds nullable day_result.source beside the exact versioned payload; every putDayResult writes it atomically, including null/partial/empty-series cases. Old rows stay unknown. Never infer units from the date-only metric_series_version stamp. No analytics, pins, source-retention or BLE behavior changed.

Author6f6a25fd/65f3e30a+130c3231 accepted. Lead inspected actual diff/source and six SQLite cases. Fresh independent reader ac307e90/f9fbfdab found no blocker; prior Pi generic abort and Cursor connection timeout produced no accepted reviews, both were reconciled after process-liveness checks. Required1977 tests,103-item clean analysis,74 affected DB tests and127/703 manifest passed. Evidence build/day-result-source-acceptance and IMPLEMENTATION_VERIFICATION.md. Nonvisual unit; no new golden/native run needed.

### Active unit: source-aware temperature

DATA worker2c066aed/8d7c33c3, GrokPi900s, temperature-data-clone; sole writer night_scalar_data/domain/local_repository/synthetic_repository plus two night-scalar data/repository tests. Read-only schema66 dependency supplied. Paper lead owns integration and UI brief. No UI worker yet.

Paper24 inspected refs and exact JSX/PNG exports: task temperature-paper/index.json. Canonical line4YO1/4YSR, card4ZQX/4ZR8; SD4YPE/4YTK, Celsius4Z21/4Z4A, unknown4YXJ/4YZS, large4Z7P/4Z9Y, missing4ZEV/4ZG4, partial4ZHD/4ZJM, error4ZLV/4ZOE, Info4ZRP/4ZTY/4ZW7/4ZXG/4ZYP/500X. All spacing/type/contrast/alignment/fit inspected, including stacked large header and source. Unregistered until implementation accepted.

Known exact band source means SD; whoop_export means Celsius; cloud/unknown/conflict stays unknown. Legacy imported:true plus explicitwhoop_export can identify Celsius; null band source cannot proveSD. Preserve both source channels. Unknown-unit raw values remain in Info; hero/card show—. History uses selected storedalgo and sameknownquantity, incompatible samples stay gaps with disclosed counts. No ADC baseline or overnight temperature route. Synthetic14of30 fixture is explicit. Continue UI delegation, independent review, required checks/native/golden inspection, local commit, then remaining Health/B69/queue.
