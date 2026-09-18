# OpenBand 5 implementation plan

Updated 17 September 2026. Paper file `01M2KDQRH0A9K3N46EWHMBF61D` is approved; Direction A, Tagesbild, is canonical. Flutter remains the UI framework. Local Swift integrations remain responsible for iOS capabilities where appropriate. No device experiment has established a reason to replace Flutter.

[IMPLEMENTATION_COVERAGE.json](IMPLEMENTATION_COVERAGE.json) assigns all **591 artboards: 583 iPhone views and eight reference boards**, all **153 reviewed flows** and **B01–B166** to reusable work packages. A mapping is a scope assignment, not an implementation claim. [IMPLEMENTATION_VERIFICATION.md](IMPLEMENTATION_VERIFICATION.md) records evidence separately. The approved designs supersede the earlier “not an implementation clearance” language retained in the design research.

## Architecture and retained work

| Concern | Decision and present implementation |
| --- | --- |
| Packages | Keep `openstrap_edge`, `openstrap_protocol`, `openstrap_analytics`. Bytes/record decoding belong in `protocol`; metric algorithms in `analytics`; sessions, persistence, jobs and UI in `edge`. |
| State | Keep Provider, `AppState`, existing BLE engine and Sqflite. `OpenBandController` owns selected-day reads and correction progress. No new state library. |
| Storage | Schema **52**, additive migration and same-version repair. Durable sleep drafts, correction revisions and calculation jobs. Original records remain retained. |
| Algorithms | Version **89** invalidates prior derivation output after generation-aware dispatch changes. Existing analytics run in isolates. No new physiological algorithm in UI or repository. |
| Read boundary | `LocalOpenBandRepository` translates the legacy repository and persisted day payload into typed values. It refuses malformed day payloads and prevents today's legacy fallback from borrowing a different night's values. Legacy screens retain their existing adapter until their package migrates. |
| UI | Four-tab shell is active. Overview, date selection, sleep correction and receipt use the new Inter/Lucide components. Existing Health, Training, Journal, profile and onboarding remain functional destinations; their full Paper redesign is deferred explicitly. |
| Existing fixes | Retain local onboarding Back/pairing, birth-date profile/recalculation, signing and widget changes. All implementation uses this working tree, including untracked files. Baseline backup is outside Git. |
| Dependencies | Flutter **3.41.6**, Dart **3.11.4**. Protocol `fe1464db98b84ac4d3ce6175d54ada11356d6c62`; analytics `1fa8144a5e3b728ce91eeed6ecbc15d482933b44`. Protocol/analytics pins unchanged. The later development setup adds the Flutter SDK integration-test dependency and its lock entries; existing package versions stay unchanged. Inter added as a bundled font with OFL; existing Lucide package reused. |

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
