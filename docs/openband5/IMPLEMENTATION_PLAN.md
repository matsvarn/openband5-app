# OpenBand 5 implementation plan

Current continuation: 20 September 2026. Alpin 3 in Paper file `01M2TRX5GZKAXKTSXK7D34E8AY` is canonical. Designphase 2, `01M2KDQRH0A9K3N46EWHMBF61D`, is a frozen archive. Flutter remains the UI framework. Local Swift integrations remain responsible for iOS capabilities where appropriate.

## Alpin continuation

The current assignments, accepted commits, evidence and next unit are in **Active continuation** below. The queue is `design/state_checklist.json`; unmarked archive states require source, route and Paper reconciliation before rebuilding. Accepted unit evidence is in `IMPLEMENTATION_VERIFICATION.md`. Earlier handoffs remain in Git history.

Work only in edge on `openband5/ios-device-setup`. No push, merge, deploy, personal-data access, physical-device review or Bluetooth operation is authorized. Preserve unrelated assets. Lead owns Paper and acceptance; isolated Mats workers own implementation and ordinary test/debug loops. Every unit needs an inspected native render, required checks and a local commit. Paper and Flutter should match closely; remove redundant explanations while preserving source, timing and uncertainty.

## Architecture and retained work

| Concern | Decision and present implementation |
| --- | --- |
| Packages | Keep `openstrap_edge`, `openstrap_protocol`, `openstrap_analytics`. Bytes/record decoding belong in `protocol`; metric algorithms in `analytics`; sessions, persistence, jobs and UI in `edge`. |
| State | Keep Provider, `AppState`, existing BLE engine and Sqflite. `OpenBandController` owns selected-day reads and correction progress. No new state library. |
| Storage | Schema **61**, additive migration and same-version repair. Durable sleep drafts, correction revisions and calculation jobs (52); workout templates, meal drafts and frozen session-detail snapshots (53); user lap marks (54); durable nap recalculation jobs and original bounds (55); optional sleep-goal periods (56); per-result lab report bounds (57); template pin/archive (58); durable live strength state (59); custom-field visibility (60); dated nutrition targets (61). Original records remain retained. |
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

## Active continuation · 20 September 2026, 15:04

Lead owns main, Paper, integration and acceptance. Edge only, branch `openband5/ios-device-setup`. No push/deployment/personal data/physical device/Bluetooth authority. Preserve six unrelated untracked assets. Mats task `/private/tmp/openband-alpin-20260919`. Minimal copy and near-exact Paper/native parity required.

Accepted commits: `2080b03` saved-food editing/recovery, `01d6786` atomic retained-draft/water contracts (864 required tests), `87b0fc3` overview queue reconciliation, `a1078f9` all33 sleep queue items reconciled with source/archive, genuine open requirements retained. Earlier version reconciliation69aca3d, Journal080d971, dated goalsada1ff8.

Nutrition-parent UI accepted and staged for local commit: nutrition.dart/browser.dart/route.dart, water.dart, shared journal_value_editor.dart, selector health.dart, production app/gallery/historicalSteps routes; superseded NutritionScreen deleted. Worker diffs inspected. Selector17 PNGs, water12 PNGs, sharedJournal2 PNGs, browser8 PNGs inspected. Parent10 PNGs regenerated after footer correction and all inspected; legacy nutrition2 PNGs migrated and inspected. 38-state nativePro PASS108.4s, everyPNG inspected at build/ui-review/nutrition-parent-pro-final-20260920. Real Journal return, light/dark, 2x, errors, water keyboard/conflict/retry and retained-draft failed-save covered. 949 required tests pass;57-item analyzer clean. Mini v2 PASS145.97s,38PNGs all inspected; first mini attempt failed before PNG. Both run/frames/index receipts match. Pro footer uses actual viewPadding; latest max(padding,viewPadding) correction changes injected test media only; mini proves final source.

Assignments:
- Parent1e1df9dd/18a7dd0c idle, Sol; final source integrated. 55 focused tests initially; integrated20parenttests pass after footer fix. Fresh reviewer05626f6d/f0ced7d3 exposed concurrent removal resurrection, expiring retry and busy/day identity issues; all corrected and regression covered.
- Browser249f7732/4203519c idle, Sol; final footer fix integrated,16tests/analyze pass,8PNGs unchanged. Prior routine writers ec5e3849 and10047a52 timed out, liveness and detached test groups reconciled and retired.
- Water377f8258/f367166a idle;68tests/analyze pass. Prior independent21326217/044c8369 review closed. Shared amount/time normal side by side, 2x stacked. Read-after-write failures never replay mutation.
- Routesbd5f96e5/8e1d19c3 idle, integrated;52focused route/revision/router tests pass. Token inventory test has pre-existing FirstSyncView/OBSetupStatusCard omissions, proven against unchanged baseline. Two fresh route readers timed out with no report; not treated as no-findings.
- Capture57d452f0/071fbdc7 idle; integrated38frames, real Gallery/Journal navigation and shared caffeine sheet. No worker native access.
- Discovery651a8551/6489e4a4 idle, report read: today-only versioned forecast, user goal separate; B136 scores old night against tonight need and must not be exposed. Prior A01/A02/A08/nutrition audit reports in task state.

Paper: file01M2TRX5GZKAXKTSXK7D34E8AY, archive frozen. Canonical day433T/43ID,week3ZYY/401D,library403Q/40H3,picker43W3/4411; meal3FKF/44H9,large44BN/44I8/scrolled44NR/44RX; water42ZV/4381/manual43HS/43QQ; Journal3Q5H/44W4/44WP. New persistent feedback44XD/44XM/44XT normal/dark/large inspected. Paper week status/header repaired with nonshrinking58px status row/full-width header; synthetic annotation removed from product content. Manifest116blocks265screens passes. Compact375 light/dark Paper4528/456E also inspected; macro rows stack to preserve legibility. Full failed-save Paper states44Y4/44ZZ added and inspected; large action alignment corrected at canonical44XT. Register checklist acceptance only after integrated gates. Legacy-test worker0f91d6ff/8b2871d7 idle;3focused tests pass, actual diff and two PNGs inspected and integrated.

Next: commit accepted nutrition parent unit, then implement stored sleep requirement/planning with Paper-first design and delegated implementation. Eight nutrition/water checklist states now have acceptance evidence. Continue remaining supported queue.

Remaining includes nutrition search/manual/barcode/photo/Health/recipes/favorites/customfoods, draft row edit/portions/aggregate nutrients/day close; Journal datedpairs/order/pin/timeddrinks; training catalogue/customUUID/archive/templates/history; A08import/export/coach/widgets; glucose permission/error distinctions, cycle flags, medication history; A01lowerfeed/customization/livechip. SOL is stored; learned need/bedtime version/day alignment needs work; SpO2 producer disabled. Genuine unmet requirements stay open.

Authority incident closed: user-authorized exact-head deletion of origin/openband5/journal-custom-fields at987b9e920754eb66f7e34264c85f3497d2950562 verified absent. Retired worker7da2faf5 never resumes. No other remote writes.

Release source0.9.31+67,algo90,schema61; protocolfe1464db98b84ac4d3ce6175d54ada11356d6c62,analytics1fa8144a5e3b728ce91eeed6ecbc15d482933b44 match lock. SDK ~/.local/share/flutter/3.41.6/bin/flutter. Widget/watch versions reconciled; final readiness open. Never create test/goldens; approved PNGs belong test/openband_goldens. Synthetic Pro/mini proof only.
