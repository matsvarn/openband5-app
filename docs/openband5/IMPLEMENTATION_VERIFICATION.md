# First-flow implementation evidence

17 September 2026. This records the local working tree, including the pre-existing onboarding, profile and signing fixes. Nothing was pushed, published or released. See [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) for scope and [IMPLEMENTATION_COVERAGE.json](IMPLEMENTATION_COVERAGE.json) for all design assignments.

## Result and proof boundaries

The production route now runs **Übersicht → date confirmation → Schlaf → edit → preview → confirmed local save → recalculation → updated Schlaf/Übersicht**. The controller, real SQLite repository and existing AppState calculation pipeline are connected. Corrections and drafts persist; errors distinguish failed save from failed calculation. The remaining app redesign is deliberately tracked as partial/deferred, not reported as 583 implemented screens.

| Evidence | Result | What it establishes |
| --- | --- | --- |
| Flutter analysis | `flutter analyze --no-pub`: no issues | Static checks on the complete dirty working tree. |
| Full required serial suite | `flutter test --no-pub --concurrency=1 --reporter=expanded`: **3,721 passed, 453 skipped, 1 failed** | Regression coverage across this package. The suite is not fully green on macOS. |
| Known full-suite failure | `health_workout_export_delete_gate_test.dart`, “a failed delete does not write a duplicate on top of it” | Unchanged baseline failure: the test assumes a non-Apple host while the exporter takes its Apple branch on macOS. Neither test nor exporter changed here. Prior baseline: 3,676 passed / 453 skipped / same failure. |
| New first-flow tests | **45 passed**, ordinary non-update run across the seven `openband_*_test.dart` files | Widget behavior, local persistence, actual synthetic-input calculation, exact-day reads, failure and revision contracts. Details below. |
| Visual regression | **21 PNGs** in `test/openband_goldens/`; ordinary comparison run after generation | Deterministic Flutter renders, with loaded Inter and Lucide. These are synthetic test renders, not phone screenshots or physiological evidence. |
| Dependency guard | `.github/scripts/check_sibling_pins.sh`: full hashes match lock | Protocol and analytics pins unchanged. The pin guard reports that it could not perform remote staleness checks; DEVELOPMENT.md records the possible missing GNU timeout cause. The subsequent development-setup change adds only SDK integration-test dependencies and their native test plugin to the lockfiles. |
| Preservation | 170 baseline dirty/untracked files accounted for; none missing; 164 byte-identical | Five existing dirty source/test files were extended for the product implementation; the pre-existing development guide was updated for the subsequent review setup. Original onboarding/profile/signing work remains. The baseline archive/hashes stay outside Git. |
| Diff and coverage | `git diff --check`; all 591 inventory IDs match exactly; 166 backend IDs and 153 flows mapped | Whitespace hygiene and exhaustive scope assignment. Mapping does not assert implementation completeness. |
| iPhone build | Signed **profile**, main entry point, Flutter 3.41.6, OpenBand 5 0.9.29 (65); deep strict code-signature verification | Native compilation and signing. Existing team, bundle and widget configuration retained. |
| Simulator build | Debug `lib/main_gallery.dart`, iOS simulator | The independent gallery entry point compiles for iOS. It does not use the production database or Bluetooth. |
| Physical install | Updated existing installation on the connected iPhone 15 Pro through `devicectl`, without uninstalling | Local installation and launch are recorded separately below. No TestFlight/App Store action. |
| Physical visual evidence | Mats supplied the first-build overview screenshot | Real phone rendering and stored values were visible. It exposed issues corrected below. It is not acceptance of the later visual fixes. |
| Hosted CI | Not run for this working tree | Previous published CI evidence does not cover these changes. |
| WHOOP Bluetooth recovery | **Not verified** | No destructive command, firmware change or experimental R22 flag enabled. |
| Physiological validity | **Not evaluated** | Fixture clipping, algorithm execution and a native build do not validate sensor channels or sleep stages. |

The final Paper-to-native pass was followed by the full serial suite and clean analysis. It changes presentation and interaction tests; the production calculation, persistence and protocol contracts are unchanged.

## Focused regression coverage

| File | Cases | Observable behavior |
| --- | ---: | --- |
| `openband_flow_test.dart` | 20 | Full correction/return path; separate save and calculation retries; calendar confirm/cancel; 44-point iOS targets and labels; accessible missing intervals; iOS edge-back retains draft; tab stacks retain sleep route; light/dark states; 375×812 at 2× text with a 300-point keyboard inset. Also covers keyboard Next/Done, draft-write failure/retry, explicit keep/discard, large calendar and steps chips, completed return and automatic restore. Reduced motion is enabled in the render cases; the edge-back case uses normal iOS transitions. |
| `openband_sleep_storage_test.dart` | 6 | SQLite reopen, stable duplicate receipt, failed transaction retains draft, failed calculation/automatic restore, retained source, stale revision refuses result and series writes, pending recovery after interrupted calculation. |
| `openband_recalculation_test.dart` | 5 | Actual AppState/DerivationEngine recalculation against 28,800 synthetic Gen4 seconds; corrected 450-minute bed window and durable completion; missing-source failure; exact selected day and its own baselines; nullable/lower-bound intake; primary battery timestamp versus committed cursor. |
| `openband_gen5_dispatch_test.dart` | 1 | Synthetic v20 optical-buffer bytes that resemble legacy R24 never become biometrics in replay or database ingestion; original bytes remain archived. This is decoder dispatch proof, not validation of Gen5 optical channels. |
| `openband_controller_test.dart` | 2 | Out-of-order day reads cannot replace newer selection; a newer correction queues behind an older calculation and wins after failure. |
| `openband_synthetic_test.dart` | 6 | Approved fixture totals, corrected bounds, unobserved interval preservation, historical independence, memory-only failures and persistence simulation. |
| `openband_time_test.dart` | 5 | Recorded-zone times, spring DST refusal, ambiguous autumn offset handling, invalid clock fields, and sub-minute gap formatting. |

No test imports private phone measurements. The real calculation integration uses synthetic Gen4 rows deliberately; it does not masquerade as a WHOOP 5 capture test.

## Visual review and the phone feedback

Paper was read, not edited. Main references: `1V0-0` / `1Y8-0`, `2B9-0`, `2EM-0`, `2HU-0`, `22Q-0` / `25K-0` / `28E-0` / `IA-0`, `AF2-1`, and correction `JN-0` → `L1-0` → `M8-0` → `NG-0` / `OT-0`, with `1GDD-0` for save failure.

Changes after Mats's phone screenshot:

- Night summaries occupy one full-width row at normal text size; bed time sits left and awake minutes right. Larger text can wrap naturally.
- Schritte uses the compact number/timestamp/chart layout, nutrition and water chips, and a right chevron. Each control opens the corresponding selected-day details. No decorative data is presented as a measured curve when intervals are absent.
- Historical HRV and resting-HR cards read their stored daily baselines. A missing baseline is still explicitly missing.
- Short sleep intervals keep their true widths. Connectors are omitted when both adjacent bars cannot support them at this scale, reducing the dense vertical comb. The interval list retains every original value and gap.
- Gaps smaller than a minute show “<1 Min.”; they no longer appear as “0 Min. ohne Daten”. Compact overview gap context sits above the chart.
- Small coloured text uses stronger text colours rather than the pale chart palette. Error cards and correction actions have explicit separation.

Inspected renders include complete/dense light and dark, interrupted dark, missing light, partial sleep, correction preview, save/calculation failures and large text. The gallery adds state, appearance and 1×/1.5×/2× text controls. Screenshots are reviewed against Paper for layout/semantics and then checked as stable regression baselines; no claim of pixel-identical Paper export comparison is made.

The subsequent Paper-to-native pass also:

- Replaced the generic calendar sheet with the approved full route and an actual selected-night preview. Selection remains staged until confirmation.
- Matched the 120×40 steps chart, compact 44-point actions and tab-bar density; corrected dark REM to Paper's `#839DCC`.
- Unified wrapping page headers; rebuilt compact correction preview, pending, failure and completed layouts around the existing durable workflow. Keyboard Next goes directly to the end field; Done dismisses it.
- Kept the phase sheet close control visible above its scrolling interval list. Larger text can wrap interval labels, chips, headings and time fields.
- Added native draft-write failure, keep/discard, retry, selected-history, return/restore and 2× calendar/editor coverage. Two new deterministic goldens cover date selection and the completed receipt.

The [four-state Paper/before/after comparison](assets/review-20260917/index.html) retains original PNGs and a SHA-256 source manifest. Before is the previous simulator review (already after the first phone-feedback fixes); after is the passing 11:54 native run. Data/date and explicit synthetic provenance differ from Paper examples. This is a visual review, not a pixel identity claim.

Known remaining visual scope: lower overview feed/customization; full sleep hub/session distinction and physiological curve detail; remaining legacy tab roots. These have explicit work-package owners. The complete-state headline says “Schlaf ansehen” rather than fabricating the design's comparison when no validated historical comparison is available.

## Native execution and remaining device checks

The available device is the owner's iPhone 15 Pro. Signed debug and profile builds succeeded; the final installed target is `lib/main.dart`, not the synthetic gallery. Build/install commands and tool JSON are retained locally under `/tmp/openband5-implementation-20260917/` (`ios-profile-final.log`, `device-install-final.json`, `device-launch-final.json`). After adding the SDK integration-test dependencies, the production main entry point was rebuilt in profile mode and passed deep strict code-signature verification again (`ios-profile-dev-setup.log`, 79.4-second Xcode build); this tooling-only rebuild was not reinstalled on the phone. The development archive is outside Git and may be removed by OS temporary-file cleanup.

Xcode 27's Device Hub UI repeatedly timed out through native automation. A subsequent development-setup investigation found and exercised the direct `devicectl device capture screenshot` command; GUI mirroring is therefore not required for physical screenshots. It captures the current foreground app, so production phone review remains an explicit session.

The new `tool/ui_review.py capture` runner bypasses Device Hub for automated simulator review. It drives the real Flutter widgets with isolated synthetic inputs and captures the **whole simulated display**, including native status bar and keyboard. Flutter's own screenshot hook was insufficient for that last requirement. The passing iPhone 15 Pro run produced 25 PNGs in 109 seconds (build + execution), with a real 393×852 viewport, 335-point native keyboard inset and populated semantics. Evidence is under `build/ui-review/20260917-111347/`. The 375×812 iPhone 13 mini run also passed: 25 captures in 95.54 seconds under `build/ui-review/20260917-111856/`. A real edit hot-reloaded one gallery library in 713 ms. See DEVELOPMENT.md for reproduction. The initial tooling failures remain in local logs and are not counted as acceptance.

Real VoiceOver speech/focus order, Bold Text/Increase Contrast, production lock/background transitions, measured frame pacing during real sync, physical interruption recovery and physiological validity remain unverified. Native simulator screenshots establish more than widget-only captures but do not substitute for those outcomes.

Next: **WP3 physical WHOOP 5.0 capture and sync recovery**, using retained originals and private lab storage. Check firmware-specific channel interpretation, commit/ACK sequence, disconnect/relaunch, source completeness and archive growth before expanding metric claims. Then WP4 establishes the full shared metric detail contract.

## 19 September 2026 · Alpin Nickerchen

Stored nap results and durable manual edits now share a typed production flow. Add, edit, remove, restore and recalculation retry preserve source bounds and saved edits; no-result and unjudged days remain distinct. Schema55 adds independent revisioned nap jobs. Legacy nap destination removed.

Required checks:166 OpenBand tests passed; analyzer and design manifest passed (79 blocks,47 screens). Additional65 affected storage, derivation, repair and legacy-caller checks passed. All25 changed/new goldens inspected. Final synthetic native runs passed on iPhone15Pro and iPhone13mini,107 PNGs each; every PNG inspected. Evidence: `build/ui-review/naps-final-20260919` and `build/ui-review/naps-mini-final-20260919`, including run.json/frames.json/index.html. Paper list/editor/state variants compared directly with native renders. Shared page header, ink actions and paired time wells use canonical dimensions.

The initial rejected nap layout and failed unknown-state fixture are superseded by those final runs. Remaining older2x stage-legend/tab wrapping and redundant sleep/calendar copy are recorded in the continuation queue. No personal data, physical phone, Bluetooth or physiological validation was used.

## Schlafziel — 19 September 2026

Optional dated user targets are persisted separately from the stored weekend p75 estimate. Schema56 preserves target history and explicit removal boundaries. Estimate reads require exact selected day, current algorithm and valid source metadata; no default target or learned sleep requirement is invented. The editor retains values after save failure.

191 OpenBand tests passed; required analyzer and design manifest passed (79 blocks,53 screens). All8 new goal goldens and the changed sleep-hub golden inspected. Synthetic native runs passed: iPhone15Pro `build/ui-review/sleep-goal-20260919` (113 PNGs) and iPhone13mini `build/ui-review/sleep-goal-mini-20260919` (117 PNGs); every PNG inspected, with run.json/frames.json/index.html checked. Mini adds filled, dark and2x editors plus estimate disclosure. Goal screens match canonical Paper layout and controls; large text expands deliberately. Existing sleep-stage legend and tab-label wrapping remain in their owning queue units. No physical-device or physiological proof.

## Labor — 19 September 2026

Typed lab history, add/edit/remove and custom markers now open from Gesundheit. Schema57 stores optional per-result report bounds; catalogue guidance remains separate. Atomic writes refuse new-row/custom-key collisions, retain values after failure, and export report bounds in CSV. The superseded legacy lab destination is removed. Shared measurement rows match Paper; shared metric values stack at large text instead of overflowing.

218 OpenBand tests,48 affected storage/CSV/legacy checks, analyzer and design manifest passed (80 blocks,64 screens). All15 new lab goldens inspected. Synthetic native runs passed: iPhone15Pro `build/ui-review/labs-v3-20260919` (138 PNGs) and iPhone13mini `build/ui-review/labs-mini-v3-20260919` (139 PNGs). Every PNG inspected; run.json/frames.json/index.html checked, including native keyboard insets, light/dark, CRUD, failure/retry, missing bounds and2x. Paper list/detail/editor/custom-marker/state exports compared with native renders. Earlier failed runs are not acceptance evidence.

Existing whole-health-hub differences from Paper,2x metric-title/stage-legend/tab wrapping and older sleep/calendar copy remain queued; this unit accepts the new lab flow and its shared measurement block. No personal data, physical device, Bluetooth or physiological proof.

## Journal field persistence — 19 September 2026

An inline answer previously called the full-day replacement API with one key, deleting other answers and dose times. Production writeJournal now uses an atomic single-field transaction. Existing timestamps survive value-only edits; new fields have no invented time. Full-day replacement retains its explicit contract. No schema or UI change.

Independent review inspected the actual SQLite path. Main240 OpenBand and affected journal tests passed (including10 new storage regressions and12 existing metric-store checks); analyzer and design manifest passed. New-key insert, existing update, independent concurrent fields, invalid inputs and separate SQLite INSERT/UPDATE aborts exercise the production adapter. No simulator rerun for this storage-only repair; no physical-device proof.

## Alpin notifications and shared time picker — 19 September 2026

Production settings now use the Alpin notification flow. Typed preferences preserve ordered writes; permission unknown/denied, persistence failure and application failure are separate states. The shared stock input picker uses Alpin typography/palette and validates actual clock values. Both alarm and quiet-hours callers use it. The superseded notification UI was removed.

- Required OpenBand suite plus affected notification/AppState tests: **328 passed** (`notifications-final-12h-tests.log` in `/tmp/openband-alpin-20260919/check-logs`). Analyzer: no issues, including integration and affected tests. Manifest: **84 blocks, 73 real screens**.
- **11 new PNG goldens**, every image inspected: five notification, four German24h picker, two English12h picker. Real PM→AM selection and invalid-hour refusal tested.
- Native synthetic captures: `build/ui-review/notifications-picker-final-20260919` (iPhone15Pro,162 PNGs,368s) and `build/ui-review/notifications-picker-mini-final-20260919` (iPhone13mini,162 PNGs,530s). Both passed; every PNG inspected, run/frames/index inventories reconciled. Notification light/dark/denied/unknown/loading, retained save retry, application failure, choices, quiet-time input/invalid keyboard and2x text included. Earlier failed runs are not acceptance evidence.
- Paper canonical picker3NGR/3NI7/3NUJ and real screens3NJF/3NNQ inspected against measured native geometry; notifications3L8J/3LCD/3LEZ, choices3MDT/3MGR and errors3MZ0/3N2G. Exact exports remain in the private task directory.

No physical-device delivery, Bluetooth behavior or physiological validity claim. Older hub2x legends/navigation labels and legacy dialogs remain queued; inspecting their captures does not accept them as complete.

## Alpin alarm ownership and configuration readback — 19 September 2026

Alarm state now follows a durable intent generation and correlated band configuration readback. Historical56/59 events cannot confirm the current request. Unknown device-clock mapping remains unknown; cancellation requires all six slots inactive. Foreground/background ownership is serialized and revocable. Failed replacement retains the prior possibly stored alarm. Only an actual current command failure/rejection may notify; validity is checked again after notification queue work.

Main required OpenBand plus affected alarm/AppState/BLE/headless/notification suites: **589 passed**. Required analyzer plus affected files: **33 items, no issues**. Final enabled-control fixture repair: **36 passed**. Manifest: **84 blocks,77 real screens**. All8 new alarm goldens and5 changed notification goldens inspected. Existing bytes/decoding and analytics pins unchanged.

Synthetic native runs: `build/ui-review/alarm-owner-final-20260919` (iPhone15Pro,170 PNGs,370.95s) and `build/ui-review/alarm-owner-mini-final-20260919` (iPhone13mini,170 PNGs,539.84s). Both passed. Every PNG inspected; all170 frames, PNGs and index entries reconcile per run. Light/dark, pending/offline, retry failure, inactive slots, invalid time input, keyboard and2x text included. Alarm date, hero spacing, status icon, schedule controls and states compared with exact Paper exports. Existing unrelated hub/legend/tab/legacy-dialog differences remain in their owning queue units.

Independent ownership/race reviews and lead source/diff inspection completed. Tests establish state-machine behavior and simulator appearance, not physical BLE delivery, alarm firing or physiological validity.


## Alpin appearance · 19 September 2026

Explicit System/Hell/Dunkel replaces hidden cycling. ThemeController serializes persistence and applies every durable success; failed writes keep the last saved choice. Pending saves pin the route, errors allow retry, and System follows actual platform brightness. Appearance and notification choices/errors reuse shared controls.

Main required OpenBand suite: **314 passed**; analyzer **28 items, clean**; manifest **85 blocks /81 screens**. Fresh independent review c42e95e0 checked the navigation pin, live-theme harness and shared retry extraction. Lead inspected actual production diff and all five committed appearance PNGs. The header remains unchanged; its back action is temporarily inert during a pending save.

Native Pro `build/ui-review/appearance-final-20260919` passed in380.24s; mini `build/ui-review/appearance-mini-final-20260919` passed in564.56s. **180 PNGs per run, every PNG inspected**, filenames reconcile with frames.json and index.html. Actual save failure/retry, dark selection, System→OS dark and reopen were exercised; static light/dark/error and2x frames also reviewed. No personal data, physical device or Bluetooth proof.

Paper3O01/3O17/3OSU/3OTU and shared3MCG/3N1Y reviewed against the native output. Status-bar frames now explicitly reserve58px, fixing a clipped Paper page top without changing the app. Exact final export: `/tmp/openband-alpin-20260919/appearance-paper-final-jsx.json`. The broader hub/layout backlog remains open.


## Alpin first sync · 19 September 2026

Connection, committed band frontier and today’s evaluation are independent. Evaluation requires the current local day and algorithm version; pending/failed sleep or nap recalculation cannot be masked by an unrelated newer result. Partial, unavailable and read-error states retain Continue. Slow reads use one flight and one queued refresh; midnight drops the old day’s result. Band status publishes without waiting for evaluation.

Main required OpenBand and affected onboarding suites: **349 passed**. Analyzer: **31 items, clean**. Manifest: **86 blocks /86 screens**. Lead inspected source and actual diff; fresh reviewer49f6ae5c verified current-job joins, failure precedence and async fixes. All six new goldens inspected.

Native synthetic Pro `build/ui-review/first-sync-v2-20260919` passed (381.82s); final mini `build/ui-review/first-sync-mini-final-20260919` passed (584.65s). **188 PNGs each, every PNG inspected**, frames and index inventories reconciled. Pro captured the same visual fixtures before the final nonvisual async/job correction; final mini and349 source/widget tests cover that correction. The earlier failed first-sync-final run is excluded. Light/dark, complete/partial/error/retry, disclosure and2x text reviewed against Paper3IBK/3P4K/3P6A/3P7I/3P8X/3PTN and canonical3PAB. Exact export: `/tmp/openband-alpin-20260919/first-sync-v3-jsx.json`.

Older hub/legend/navigation/dialog/copy issues remain queued. Simulator data are synthetic; no physical-device, Bluetooth delivery or physiological proof is claimed.


## Alpin template actions and durable live strength · 19 September 2026

Schema58 adds persistent template pin/archive; schema59 stores the live strength snapshot and rest state. The Alpin list, actions and live screen are reachable from the production hub and resume bar. Planned-set and exercise identities survive recording, skipping and added sets. Previous values come from recorded history. Failed writes retain input and completed sets; read failure after a committed mutation retries only the read. Finish uses the existing atomic session finalization; algorithm and protocol responsibilities are unchanged.

Lead inspected the integrated source/diff and fresh independent reviews. Required final OpenBand suite: **423 passed**; analyzer **32 items, clean**. Earlier affected manual-session/AppState suites also passed (477 combined tests before final visual-only repairs). Manifest: **89 blocks /99 screens**, schema59 reconciled. All **20 changed/new PNG goldens** inspected. Final footer regression covers real34-point bottom insets and keyboard scroll at2x text; no content leaks below the rest card.

Native synthetic Pro `build/ui-review/training-v6-20260919` passed in422.42s; mini `build/ui-review/training-v6-mini-20260919` passed in628.42s. **207 PNGs per run, every PNG inspected**; names reconcile with frames.json and index.html. New template list/menu/pin and strength light/dark/error/retry/resume/skip/add/rest/large-text states match the reviewed Paper blocks. Prior v1–v5 runs are diagnostic, not final acceptance.

Paper templates3MNS/3MP6/3MQE/3MX9/3MT7/3MV8 and strength3FLY/3N6K/3OGV/3OLU/3OV4/3OZE/3O3E/3O80/3PFE/3PSH/3PT3 were rendered and compared. Full template editing/catalogue, completed-session detail and remaining training flows remain open. Existing older hub, tab, stage-legend, copy and dark action contrast defects remain queued. Simulator proof does not establish physical Bluetooth behavior or physiological validity.


## Alpin units · 19 September 2026

Explicit metric/imperial selection replaces hidden cycling. Examples convert fixed, clearly labelled example inputs; saved measurements remain unchanged. UnitsController serializes durable writes and applies each success. Failure retains the last saved choice; retry and reopen use the production controller. Pending saves pin the route.

Lead inspected the integrated source/diff and fresh review4f200028/9c4e8fa0. Required OpenBand plus controller suite: **452 passed**. Final focused unit/controller/capture-helper checks: **33 passed**. Analyzer: **34 items, clean**. Manifest: **90 blocks /107 screens**. All **nine new golden PNGs** inspected. The native capture helper correlates the newly requested frame with its exact raster timing rather than accepting an older timing batch.

Native synthetic Pro `build/ui-review/units-v4-20260919` passed in378.48s; mini `build/ui-review/units-v4-mini-20260919` passed in599.19s. **219 PNGs per run, every PNG inspected**; names reconcile with frames.json and index.html. Light/dark, metric/imperial, save failure/retry/reopen and2x text reviewed against Paper3UHD/3UIZ/3UKA/3UM1/3UNC/3UON/3UQ6/3URH and canonical preview3UID. Exact exports: units-v1-jsx.json and units-large-v1-jsx.json in the private task directory. Earlier v1–v3 runs are diagnostic only.

Reviewing older gallery screens does not close their outstanding hub/layout/copy work. No physical-device, Bluetooth or physiological proof is claimed.


## Template edit preservation · 19 September 2026

Saving a renamed or edited template now retains notes, set types, rest times, timed loads, exact stored fractional loads and existing identities. New objects use distinct UUIDs; duplicate labels do not merge history. Invalid counts/loads retain the draft and refuse save. A timed set cannot silently become a repetition set when its duration is blank. Save-error copy is shortened to “Speichern fehlgeschlagen.”

Accepted worker8d08132c/67dbddcb after independent reviews and lead inspection; final copy repair46f7d796. Main required OpenBand suite **451 passed**, analyzer **34 items, clean**, manifest **90 blocks /107 screens**. Twelve focused fidelity tests include recorded-session isolation, locale decimals, failed-save retry and missing values. No golden regenerated. Full catalogue, note/type/rest controls and the Alpin editor redesign remain open; this is a data-preservation repair. Native synthetic Pro `build/ui-review/template-fidelity-20260919` passed in378.03s;219 frames/PNGs/index entries reconcile. The affected edit/create PNGs were inspected directly. Existing layouts were retained; this does not accept the pending editor redesign. No physical-device or physiological proof.


## Alpin daily Journal editor and custom fields · 20 September 2026

Schema60 adds durable custom-field visibility while preserving identities and history. The production editor saves only dirty values against their captured day/revisions; note/tags use the same conflict discipline. Unknown, zero and explicit false remain distinct. Typed amount/time editing preserves precision. Custom fields can be created, hidden and restored. A committed mutation followed by read failure retries the read. Legacy editor and field-manager destinations are migrated. Coach journal proposals now validate before confirmation and retain omitted fields.

Lead inspected critical source and integrated diff after storage/UI/coach workers and independent combined review656161f1/2a4335c4. Final required OpenBand plus affected coach/timeline/field/storage/wellness suites: **653 passed**. Analyzer: **40 items, clean**, plus clean focused integration analysis. Manifest: **99 blocks /150 screens**. All **15 new golden PNGs** inspected. Schema60, algorithm90 and full sibling pins verified; no algorithm/decoder changes.

Full v3 synthetic native Pro passed439.21s and mini684.40s with251 exact captures each; all34 Journal PNGs per device inspected. Mini inspection found scrolling sheet chrome despite functional success. The final repair pins title/close and Apply while only tag content scrolls; widget coverage includes375×812 and320×812 at2x with keyboard. The existing capture runner now supports explicit --flow journal through source-preserving extraction; full mode remains the default, and exact raster synchronization is unchanged.

Final Pro `build/ui-review/journal-editor-v4-20260920` passed109.9s and mini `build/ui-review/journal-editor-v4-mini-20260920` passed143.73s. **37 PNGs each, every PNG inspected**, with exact run/frames/index reconciliation and flow=journal. Includes light/dark, missing data, error/retry/conflict, custom-field creation/hide/read recovery, tags/custom keyboard, 2x and nutrition-entry navigation. Paper keyboard3XOL was reconciled to the actual375-point viewport and rendered again; final export journal-tags-keyboard-final-jsx.json. Normal3PAS/dark3PL2, sheets, fields, info3X8S/3XDK/3XIC and large3X3O/3X6U use registered canonical blocks.

This completes the daily editor and custom create/hide/restore unit. Journal hub/pattern parity, ordering/pinning, editable definitions/icons, timed mood moments and drink events/products remain open. Existing nutrition day/search/draft layouts remain assigned to later units. Simulator proof uses isolated synthetic data; no personal-data, physical-device, Bluetooth or physiological proof.


## Alpin dated nutrition targets · 20 September 2026

Schema61 stores optional dated energy and macro targets with exact-date revision checks. Empty boundaries remove effective targets while retaining earlier/future history. Legacy undated preferences apply only today; malformed stored values use the read-error state and retain source bytes. Zero grams remains explicit. The gram/percent editor preserves precision across view switches, rescales only on an explicit energy edit in percent mode, and refuses invalid input. Removal conflicts reload without writing; committed changes followed by read failure retry only the read. Legacy target readers/writer now use the dated contract.

Lead inspected actual storage, repository, UI and integration diffs. Owner355d9bf6 completed implementation and repairs; independent reviewer5ae460eb accepted final removal and decode corrections in921291f4/d65516fe. Final main required OpenBand suite plus revision reload: **604 passed**; affected coach/timeline/wellness suites: **64 passed**. Analyzer **43 items, clean**. Manifest **103 blocks /181 screens**, diff check clean. All **19 new goal golden PNGs** and **three changed calendar/nutrition PNGs** inspected. No algorithm/decoder or dependency-pin change; app0.9.31+67, algorithm90.

Final focused synthetic Pro `build/ui-review/nutrition-goals-v2-20260920` passed172.3s and mini `build/ui-review/nutrition-goals-v2-mini-20260920` passed235.49s. **64 PNGs each, every PNG inspected**, exact run/frames/index reconciliation. Pro precedes the final backend-only corruption correction; mini uses final source. Includes normal/dark, empty, calendar, invalid/error/conflict/retry, retained history and2x editor/info. Shared compact selector retains its visual dimensions with a44-point interactive area. Paper normal3USS/3UWK, dark3UUU/3V00, large3VOC/3VWA, calendars3W90/3WAH, removal3XQA/3XRR/3XTI/3XV2 and info variants match the inspected render. Exact exports retained in the task directory: nutrition-goals-v5-jsx.json, nutrition-goals-unchanged-jsx.json, nutrition-info-final-jsx.json, nutrition-clear-errors-jsx.json, calendar-native-parity-jsx.json.

Fibre and other nutrient targets, minimum/maximum semantics, whole Journal hub/day parity and the food lifecycle remain open. Existing Journal and food-entry captures establish navigation/regression coverage, not acceptance of their pending redesign. No personal data, physical-device, Bluetooth or physiological proof.


## Alpin Journal hub and shared controls · 20 September 2026

The selected-day hub displays durable mood and nullable habits, and compares stored caffeine answers with the following night's stored sleep-onset latency through the pinned analytics producer. A single SQLite snapshot applies current algorithm and correction-receipt gates. Missing, insufficient, nonmeaningful, partial and failed reads remain distinct. Inline saves and subsequent reloads have separate states; committed values survive a read failure, and the editor is guarded while saving. Superseded pattern summary APIs were removed.

The shared yes/no control has a44-point hit area. Macro cards show known sums, optional real dated targets and incomplete-entry counts; target-read failure is distinct from unset targets. The caller awaits goal editing and reloads the captured day, rejecting stale reads. Fixed tab labels preserve body text scaling. Info-sheet header, close and footer remain fixed while the body scrolls. Inter optical size follows the rendered body size (clamped to the bundled font's14..32 range); this resolves the 2x line-wrap mismatch without hard breaks or global font changes.

Lead inspected actual critical source and diffs after owner repairs. Independent pattern reviewd24c81de/e587e873, async review1684d012/2047a929 and shared-chrome review099e5693/aad2c13d informed acceptance. Final main required OpenBand suite **674 passed**; analyzer **46 items, clean**, including integration. Manifest **103 blocks /210 screens**. All **49 changed/new golden PNGs** inspected, including final optical-size repairs. Schema61, algorithm90 and full dependency pins unchanged.

Final synthetic native Pro `build/ui-review/20260920-journal-hub-pro-final` passed **101.88s** and mini `build/ui-review/20260920-journal-hub-mini-final` passed **150.07s**. **46 PNGs each; every PNG inspected**, with exact run/frames/index reconciliation. Captures cover light/dark, 2x top and scrolled content, complete info paragraphs above the fixed footer, missing/partial/error/conflict and recovery. Paper3G8R/3NBJ,3YQF/3YWT,3GAO,3TXE/3U2N,4069/40BJ and registered variants match inspected native hierarchy, spacing and typography. Final shared-chrome export: journal-shared-chrome-v5-jsx.json in the private task directory.

The dated answer/night/value list, question ordering and definition editing, timed mood/drink events, and the full nutrition day/week/library lifecycle remain open. This unit does not accept the existing whole nutrition page. No personal data, physical-device, Bluetooth or physiological proof.


## Nutrition ledger and recent-food integrity · 20 September 2026

Food-entry and definition updates retain original creation timestamps in the same SQLite transaction as the full write. Consumed-at remains nullable and distinct from ledger time. Recent foods now select the latest actual entry by creation time with deterministic ties, grouping by stored food key or the separate label/source fields. Unknown and empty source codes round-trip unchanged. Known photo wire codes canonicalize before sanitisation, so unconfirmed photo numbers cannot bypass the store gate.

Owner5a28be4b/416bfc0f implemented the two-file repair and cdb5c040 completed **79 affected tests** plus clean caller analysis. Lead inspected actual source, full diff and test evidence. Fresh independent reviewer099e5693/dc766b68 accepted final source handling and recents. Main integrated required OpenBand suite **693 passed**, analyzer **47 items, clean**, manifest **103 blocks /210 screens**, diff check clean. No UI, golden, schema, algorithm or dependency changes; no new native capture warranted. Saved-entry lifecycle and legacy source labels remain for the following user-flow unit.


## iOS widget and watch version reconciliation · 20 September 2026

The widget extension and watch app now match app `0.9.31+67` in Debug, Release and Profile: two targets, six configurations. Runner keeps Flutter-derived build metadata. RunnerTests retains its existing test-bundle version; no shipped target relies on it. Schema61, algorithm90 and full protocol/analytics pins match their source and lockfile values.

Owner a13e645e/b25488e5 changed exactly twelve setting lines in the Xcode project. Lead inspected the actual diff, target/configuration mapping and underlying logs. Required OpenBand suite **693 passed**, analyzer **46 items, clean**, manifest **103 blocks /210 screens**, and plist validation passed in the isolated clone. No Dart source, dependency, UI or golden changes. Native compilation will be checked in the next food-flow simulator build; this metadata repair alone is not final release readiness. Evidence: `build/version-metadata-reconcile/` in the private worker clone.


## Alpin saved food and retained draft lifecycle · 20 September 2026

Saved foods now have production detail/edit, ten-nutrient editing, quantity/time, removal confirmation and exact Undo. Full snapshot compare-and-set retains source codes, confirmation, notes, creation stamps and precision. Unknown consumed time remains absent; unchanged time Apply preserves stored seconds. Unconfirmed photo values require explicit confirmation. Draft commits require matching retained input; replay cannot recreate a deleted row. Saved writes and subsequent failed reads have separate retry paths. Cross-date edits retain Undo against the entry date while returning to the original viewed day.

Lead reviewed actual store/repository/UI/integration diffs and independent reviews. Backend owner abe47645/e2098ce6, independent d6618094/90783610; leaf9a7f20c7 and parente3da6ef1, independent315105c6/48263f70. Native inspection found and corrected pane scroll reuse, summary spacing, large-text macro layout, unsafe sheet height and Undo wrapping/alignment. Sheet chrome uses actual safe-area constraints; only content scrolls. Capture helper now waits for real keyboard dismissal between scenarios and verifies full controls, not just labels.

Final required OpenBand suite **810 passed**; analyzer **51 items, clean**. Final capture-only corrections also pass scoped analysis and4 transition tests. Manifest **110 blocks /246 screens**, diff check clean. All **31 new golden PNGs** inspected, including every regenerated revision. Schema61, algorithm90, app0.9.31+67 and full dependency pins unchanged; manifest schema metadata corrected to61 from source.

Synthetic native Pro `build/ui-review/nutrition-entry-pro-v4-20260920` passed **139.71s**; mini `build/ui-review/nutrition-entry-mini-v5-20260920` passed **189.56s**. **53 PNGs each; every PNG inspected**, exact run/frames/index reconciliation. Includes light/dark, missing/unknown/zero, read/write failure, conflict/retry, actual parent edit/remove/Undo, retained draft failure/missing/conflict, 2x and keyboard. Pro393×852 and mini375×812; real keyboard insets335/308 and344/317 respectively. Paper food/editor/nutrients/quantity/time/draft variants and shared blocks are registered. Normal Undo is56pt with right-aligned intrinsic action; large actions move below the message.

This accepts the saved-row lifecycle and retained-draft save/recovery. It does not accept the old whole-day backdrop, legacy nutrition route, draft row editing/Undo/portions, aggregate meal nutrients, food search creation, photo acquisition, week/library or hydration. Those remain explicit next units. No physical-device, personal-data, Bluetooth or physiological proof; no remote writes.

## Nutrition retained-draft and water contracts · 20 September 2026

`compareAndSaveMealDraft` atomically compares the occupied day/meal slot and full typed entry snapshot before creating or updating it. A reused draft ID cannot replace another slot. Revisions advance even within one millisecond; invalid input, corrupt retained JSON and conflicts do not overwrite data. SQLite and synthetic implementations preserve source codes, unknown nutrients and numeric precision. `adjustWater` uses the existing atomic journal delta, preserves missing versus zero, clamps to the existing field limit and returns the committed amount. No schema, algorithm or dependency change. These contracts support the following nutrition UI unit; they do not establish new screen acceptance.

Lead inspected the diff and tests; fresh review `d730eb16/cd26baf2` found no further CAS defects after correction of ID collision and revision monotonicity. Water contract independent review `315105c6/2d312562` was accepted earlier. Integrated checks using Flutter 3.41.6: **864 OpenBand tests passed**, analysis of **52 items clean**, manifest **110 blocks / 246 screens**, and `git diff --check` clean. Logs: `/private/tmp/openband-alpin-20260919/nutrition-draft-water-contract-main-{tests,analyze}.log`. The two new contract suites add54 cases to the prior810. No UI pixels changed in this unit; no new simulator, physical-device or physiological proof is claimed.


## 20 September 2026 · Coming-night sleep plan

`Schlaf → Heute Nacht` now presents the stored estimate and evening plan for the coming night. It keeps the prior night's measurements and the user's chosen goal separate. The goal link uses the following wake-day; returning preserves the original selected day. Missing values, contributions, stale inputs, unreadable artifacts and failed reads have distinct states. No historical forecast ledger or attainment percentage is invented.

The producer captures `input_read_started_at_ms` immediately before reading its90 source rows and retains it through cache reuse and output. The typed reader reconciles the complete stored `recent[]` list with current served rows and relevant saved-edit jobs in one SQLite transaction. Sparse dates are not converted to a calendar window. Same-second changes remain detectable. Missing provenance is explicitly unknown; wrong-day/version and corrupt values are withheld. This is orchestration metadata, with no analytics formula or numeric output change; algorithm90/schema61/pins and0.9.31+67 remain unchanged.

Paper canonical summary45AL and schedule45AS plus20 screen variants are registered. Shared `OBSettingsValueRow` replaces the private notification row and supplies the goal row. The sleep parent consumes a remaining top inset once. Shared Paper info-body width and action radius now match Flutter. Minimal visible copy, with source details in the info sheet.

- Required `flutter test --no-pub test/openband_*_test.dart`: **1002 passed**.
- Required `flutter analyze --no-pub lib test/openband_*.dart`: **60 items, clean**.
- Affected crossday freshness/pipeline tests: **45 passed**; integration analyzer clean.
- Manifest: **118 blocks,285 screens**, valid. Twelve new sleep-plan goldens inspected individually through full-size/contact renders and committed under `test/openband_goldens/`.
- Native Pro: `build/ui-review/sleep-plan-pro-final-20260920`,62.92s; mini: `build/ui-review/sleep-plan-mini-final-20260920`,78.55s. Both pass23 captured states. All46 final PNGs inspected, frame/PNG/index receipts match. The2x check shows the full goal card within safe bounds and taps through/back.

Lead reviewed actual worker diffs and source. Independent freshness review76db988c/04a82c70 confirmed input-window/stamp/source/job handling. Its non-today-nap finding was rejected: `crossday_pipeline.dart` reads only `_todayNum(days, 'nap_min')`; main-night debt/OSD inputs do not consume old naps. Changed served rows still invalidate by computed_at. Three timed-out read reviews produced no report and were not counted as no-findings; process groups were absent and assignments retired. Initial native proof caught an outdated text assertion, top-inset overlap and a clipped2x capture; those were corrected before acceptance.

This proves synthetic local/simulator behavior, not hardware capture or physiological accuracy. Old uninstantiated Home/Health/Wellness → MetricDetail/SleepDetail code remains part of the global dead-UI retirement queue. Remaining checklist requirements stay open. Nothing was pushed.


## 20 September 2026 · Exercise library and template selection

The Alpin template editor now opens a typed catalogue of18 stable presets and stored exercise definitions. Search uses German labels and aliases; muscle/equipment filters retain hidden selections. Details and selection have separate controls. Adding an already-present exercise requires confirmation. Confirming creates one empty planned set per selected definition, with new position IDs and immutable definition snapshots; saving the template remains a separate write. Missing mode stays unknown/unselectable, corrupt stored rows are labelled partial, and read failure has retry. No preset muscle fractions are seeded into storage.

Schema62 adds exercise definition source/version/JSON with additive upgrade and same-version repair. Algorithm90, dependency pins and app0.9.31+67 are unchanged. The legacy catalogue adapter now reads the canonical preset registry. The shared action sheet moved out of training and callers migrated. Existing ad hoc entry remains reachable pending custom-definition migration. Legacy mixed reps+seconds and precise loads remain intact; clearing its duration blocks save with one short field error. Empty explicit timed plans remain valid.

Lead inspected actual source/diffs and independent findings. Data owner a67282aa/5bf92d7c and fresh reviewer edf5dbcb/a721ea9e; UI owner9d5b9a14/46059d30 and fresh reviewer765979ab/3e7942dd. The independent mixed-legacy finding was corrected and tested. Timed-out UI review ed2beb6d had no report and was retired, not accepted as a clean review. Capture66a8fb65/fc2de64c corrected native IME reattachment and made the large-text check reveal/tap the final control rather than only its label.

- Required OpenBand suite: **1045 passed**. Required analysis plus integration test: **63 items, clean**. Later capture-only changes passed scoped analysis.
- Additional owner checks:20 catalogue,35 live-strength, affected storage/schema/fidelity suites. No physics/algorithm change.
- Manifest: **120 blocks,315 screens**, schema metadata62. Twenty changed golden PNGs inspected, including every regenerated revision, under `test/openband_goldens/`.
- Native Pro `build/ui-review/exercise-picker-pro-accepted-20260920`: **93.13s**,26 states. Mini `build/ui-review/exercise-picker-mini-accepted-20260920`: **116.30s**,26 states. **All52 final PNGs inspected**; run/frames/index reconciled. Includes light/dark, missing/partial/error/unknown, repeat selection, save/reopen, legacy duration failure/recovery and2x scroll/control taps. Earlier failed runs and all their PNGs were inspected, and superseded.
- Paper row45ZY and add sheet46JW, selected45ZZ/dark462O, filter469R, details46DV, error/partial/unknown variants, parent4739 and large-text variants registered. Large-text line breaks and button heights reconciled with native. Shared confirmation Paper copies now match32% scrim and12+34 safe bottom inset. Exact final JSX exports are in `/private/tmp/openband-alpin-20260919/exercise-picker-paper/`.

This accepts existing/preset selection into templates. B26 custom definition creation/load-basis semantics, live target selection, deeper template actions and exercise history remain open. Per-template corruption isolation remains genuine integrity work; existing all-or-error reads were not silently weakened. Synthetic simulator evidence is separate from physical-device, Bluetooth and physiological proof. Nothing was pushed.


## 20 September 2026 · Custom exercise definitions and original load semantics

The library now creates durable custom definitions with explicit equipment, capture mode, load basis, device count and repetition basis. Muscle roles are optional and disjoint. Saving returns to the current filtered library unselected; hidden creation has an explicit reveal action. Legacy quick-add callers use the same editor. Shared settings choice/count controls replace private variants.

Templates and live sets retain original values, units and frozen definitions.10kg per2 devices normalizes to20kg;8 repetitions per side remain8, yielding160 external volume. Left/right records use1 device. Bodyweight and assistance never fabricate external load. Persisted metadata-free rows do not inherit current definition semantics, and unchanged precise legacy values round-trip without rounding. Mixed units/bases have explicit row labels. Recorded retry returns the committed row before validating a changed retry payload. Legacy writes retain omitted original metadata and reject contradictions atomically.

Schema63 adds original-load and frozen-definition JSON to strength_set with additive upgrade and same-version repair. CSV preserves load_kg and adds six original fields. Algorithm90, full dependency pins and app0.9.31+67 are unchanged. Definition management, copy/archive, live catalogue selection and deeper template actions remain open.

Lead inspected actual production/test diffs and independent review findings. Data7e8d757e/325f9262 and review0bfabf7f/b0dd160f; UI76e44b3a/32c87a12 and review0f2c1a92/e833d6a2; load e23a15fe/83525b49 plus suffix2cf18d1e and independent52cd9347/a341e898. Test successorab53b16d/2f865ab9 migrated the actual creation/selection flow and schema expectation; its out-of-scope strength golden failure was resolved by the already-reviewed main golden. Uncertain timed-out workers were reconciled and retired, never counted as clean reviews.

- Required OpenBand suite: **1134 passed**. Required analysis plus integration test: **68 items, clean**. Additional CSV suite: **22 passed**.
- Manifest: **121 blocks,351 screens**, schema63. All **51 new/changed golden PNGs** inspected, including every regenerated revision; committed under test/openband_goldens.
- Final native definition Pro `build/ui-review/custom-exercise-pro-settled-20260920`:129.47s; mini `custom-exercise-mini-settled-20260920`:154.84s.23 states each.
- Final native load Pro `build/ui-review/custom-load-pro-final-20260920`:134.72s; mini `custom-load-mini-final-20260920`:154.78s.23 states each. **All92 final PNGs inspected**; run/frames/index reconciled. Actual controls, retry, keyboard, settled2x top and scrolled states, unknown/blank data, bodyweight/assistance and mixed units/bases exercised. Every earlier failed/superseded capture PNG was also inspected.
- Paper definition47SX/47WB, count48L1/48NV, plan48R1/48SX, live48V9/48ZU, mixed units49SD/49UR, mixed bases49X5/49ZJ, assistance4A1X/4A4B and all required variants registered. Canonical count49OR/49OZ, shared settings rows and live heading ink reconciled. Exact exports: `/private/tmp/openband-alpin-20260919/custom-exercise-paper/`.

This is local and synthetic simulator proof. No personal-data, physical-device, Bluetooth or physiological claim. Nothing pushed.


## Glucose · 21 September 2026

Stored Health glucose is reachable from Gesundheit and PhoneImport through one Alpin flow: original source/unit, latest reading, actual points from the complete latest local day, paged history, manual read and durable exclusion/restoration. Exclusion preserves history and rejects new imports for that source. Empty query, unknown iOS authorization, request/read/write failures and saved-import/failed-refresh are separate states. The old raw PhoneImport glucose display is removed; the other three imported kinds remain.

Schema64 adds nullable measurement import/source fields and durable per-kind receipts/source settings, with same-version repair and backup inclusion. Legacy import timing remains unknown. Source inventory is independent of the bounded visible window. Corrupt lookahead rows, numeric timestamps and import stamps remain partial without removing readable siblings; explicit legacy keys and fallback names match consistently. Timestamp/UUID ties select the same newest unit across SQL, synthetic data, hero and plot. Unknown newest unit or an unrepresentable chart/day range leaves the plot absent. No unit conversion, interpolation, physiological target, new algorithm or sibling change.

Paper Designphase3:24 light/dark, empty, partial, excluded, error and375/2x variants registered in blocks.json, canonical chart4BDG and Health entry4BAP. Real UI reuses shared header, card, setting rows, toggle, action, error card and info sheet. Explanations remain behind info; source/timing/partial indicators stay visible. Older-year dates include the year and use the local view clock. Large finite values and unknown raw units wrap at readable sizes, without shrinking accessibility text.

Verification with Flutter3.41.6:

- Required `flutter test --no-pub test/openband_*_test.dart`: **1241 passed**.
- Required `flutter analyze --no-pub lib test/openband_*.dart integration_test/openband_review_test.dart`: **72 items, no issues**.
- Affected Health import, paged DB import/export, import safety, no-op backup, imported baseline exclusion and CSV export suites: **81 passed**.
- Manifest: **122 blocks /375 screens**; schema64. `git diff --check` clean.
- Worker focused DATA:71 tests/10-file analysis; UI33 tests/scoped analysis; chart14 tests/scoped analysis. Lead inspected source/diffs and regression evidence. Fresh independent Grok review117689d3 found no remaining consequential defects in the correction set; earlier findings were returned to the responsible workers. Final unreachable count-helper deletion was separately reviewed and analyzed; it changes no exercised behavior.
- **22 new goldens** under test/openband_goldens/: every PNG inspected, including dark, missing, partial, store-read failure and375/2x extreme-value/source/chart layouts. No test/goldens directory created.
- Native Pro `build/ui-review/glucose-pro-final-20260921`: **34 frames, PASS128.23s**, iPhone15Pro393×852, final DATA71/UI33/chart source. Mini `build/ui-review/glucose-mini-ui33-20260921`: **34 frames, PASS142.53s**, iPhone13mini375×812, UI33 and identical chart/fixture with DATA62 before the later corrupt-input corrections. The final Pro covers the integrated data corrections. All68 PNGs, both run.json/frames.json and indexes inspected; actual navigation, exclusion/restoration, empty query, retries, retained result after failed refresh, disclosure scrolling and large-text controls exercised. Native headers verified against actual PNG pixels where contact-sheet display was ambiguous.
- Earlier harness runs failed on offscreen lazy children and a non-interactive toggle wrapper. Fixed the real scroll/hit-test targets; did not relax assertions or widen timeouts. No UI defect remains from those failures.

Synthetic simulator and temp-SQLite proof only. Actual Health provider permission/read behavior, physical Bluetooth and physiological validity were not exercised. App0.9.31+67, algorithm90 and full dependency pins remain unchanged and match the lockfile. No push/merge/deploy.

## Checklist alias reconciliation · 21 September 2026

A05 Eigener Marker and A08 Übertragung · unterbrochen reuse accepted lab-editor and overview-sync implementations. Read-only Mats worker e68e0ada/4e134dc6 traced production routes, registered Phase 3 nodes, tests and existing native artifacts. Lead inspected save/collision/failure source, interrupted-state mapping and resume action, successful run metadata, and actual labs-custom-marker / overview-interrupted-light PNGs. The prior Labor and notifications entries retain the full light/dark, mini and failure-state evidence.

The A08 archive full page is intentionally consolidated into the canonical overview row. This does not establish pixel parity with the frozen archive or physical Bluetooth recovery. Other transfer states remain open. Documentation-only change after glucose commit 5295d34; no generated images or production code changed. JSON/design-manifest and whitespace checks passed.

## Medication plans and entries · 21 September 2026

Journal and `/meds` now open the same Alpin flow: dated entries, create/edit/end/restart plans, weekday schedules, intake/skip/clear, retained history and reminder settings. The obsolete Wellness medication destination and mutable legacy APIs are removed. Unknown answers stay open; there is no inferred adherence or missed-dose verdict. Read failure, partial unreadable rows, no plans and no scheduled entry are distinct.

Schema65 adds full plan revisions effective at the recorded civil date/time and absolute instant. Migration captures only the current head at migration time; it does not invent earlier schedules. New entries freeze original name, amount, unit and kind. Legacy missing snapshots/offsets remain missing, with current-name/UTC disclosure when needed. Revisions preserve earlier same-day slots and retained doses after end/restart. DST gaps/folds are unavailable and never silently rescheduled. Invalid wire values and missing revision heads remain unreadable without double-counting or backdating. CSV/backup retain revisions and nullable original metadata.

Dose write and receipt share one transaction. A reminder failure after commit returns a saved-but-not-refreshed result; retry refreshes reminders without replaying the write. Notifications and the band buzzer consume the same resolved slots; unknown input preserves prior arms and reports failure. Unpaired app init/resume also rearms phone reminders. OS cancel-then-arm is not atomic; failure remains visible. Coach mutations trigger the same refresh. No physical delivery or Bluetooth operation was exercised.

Lead inspected actual source/diffs and independently reviewed findings. DATA d1b383b9/d91c65ac passed80 affected checks; fresh af275e45/ba695a26 confirmed the corrected transaction, civil cutoff and corruption behavior. UI84a5a4f4/e100e76a passed34 checks; Journal regeneration98aea98c passed18. Runtime1710b473/dd391fa7 and61ae975e passed its affected checks; independent bf9bb1b9/d7b85b27 source review found no remaining consequential defects (reviewer test execution unavailable). Shared f27b860e/53d68aa8 passed11 checks. Capture9742215d/013b8546 added actual2x save-control interactions. Test compatibility854b48c4/3c3f98c0 replaced stale schema64 assertions with current schema plus feature floors, retaining row/column checks. Failed/uncertain workers were drained, reconciled and retired; no success was inferred from their exits.

- Required OpenBand suite: **1339 passed**. Required analysis: **76 items, no issues**. Logs `/private/tmp/openband-alpin-20260919/medication-integrated-required-final.log` and `medication-integrated-analyze-accepted.log`.
- Additional integrated coach/CSV/store/model/schema/prompts/buzzer/timeline suites: **117 passed**, `medication-integrated-affected.log`. Capture analyzer and Python compilation passed. Manifest **123 blocks /425 screens**, schema65; whitespace check clean.
- **41 changed golden PNGs** inspected:21 medication,18 Journal and2 shared headers. All committed under `test/openband_goldens/`; `test/goldens/` remains absent.
- Native Pro `build/ui-review/medications-pro-final`: **45 frames, PASS125.17s**,393×852. Mini `build/ui-review/medications-mini-accepted`: **47 frames, PASS151.0s**,375×812. **All92 final PNGs inspected**; both run/frames/index sets match exactly. Light/dark, missing/partial/error, history, orphan metadata, end/restart, DST, save/refresh retry, keyboard,2x and scrolled controls exercised. Mini adds2x record save and editor validation; Pro uses the identical final production UI. Earlier failed harness captures were inspected and superseded.
- Paper Phase3:50 real screen variants, canonical medication row4BLJ and shared header/value-row variants registered. Main4BLV, editor4BNU, entry4BQS, history4BT8, plans4BUZ, weekdays4C1Y. All corresponding changed renders inspected for spacing, typography, contrast, alignment and fit. Native/Paper headers, history ordering, original UTC time and large editor were reconciled. Exact55 exports/index: `/private/tmp/openband-alpin-20260919/medication-paper/`.

Synthetic SQLite/simulator evidence only; no personal data, hardware or physiological proof. App0.9.31+67, algorithm90 and full protocol/analytics pins remain unchanged and match lockfile. All six shipping widget/watch configurations remain0.9.31/67. No remote writes.

## Cycle logging, settings and entry history · 21 September 2026

Journal and the cycle route share one Alpin flow for selected-day logging, start creation/move/edit/removal/undo, observations, history and settings. Unknown, empty, unreadable starts, failed read, conflicting edit, failed save and saved-but-refresh-failed states are distinct. Canonical versioned preferences retain either legacy off choice until an acknowledged save. No default cycle, phase, fertility claim or invented interval. The optional date estimate uses existing pinned analytics median/MAD over civil-day gaps and refuses gaps over60days. Historical as-of reads exclude later entries before corruption classification; unreadable starts withhold the cycle day even when estimates are disabled.

Raw mutations use expected-record conflict checks and retain unknown tags/fields. Reload adopts the original conflicting record, including note and tags. Undo belongs to the originating screen and survives visiting history. Saved receipts remain visible after refresh failure; retry does not replay the mutation. Acknowledged profile writes serialize and roll back optimistic state after failure. The shared nutrition Undo notice is extracted without changing its visual/interaction contract. The note field dismisses the keyboard through an actual outside tap, keeping Save reachable at2x. The final small-screen copy pass replaces the long display label with Stimmungstief while retaining the low mood storage key.

Start-set changes invalidate cross-day outputs and queue durable work in the same SQLite transaction, including coach, import and deletion paths. Note-only/observation changes do not trigger heavy recalculation. Day-result changes advance a non-imported source revision and invalidate dependent input/output atomically. Publication checks revision and start-set identity. Present-null stamps are invalid; legacy absent stamps are accepted only at revision0. Scheduler busy/failed work remains queued or retryable, and claimed reasons cannot be overwritten during coalescing. Refresh acknowledgment means work was requested, not that calculation finished. No protocol or analytics behavior changed. Three sleep-plan fixtures now explicitly assert invalidation and republish the same old artifact to test the retained stale/unknown/race outcomes.

Lead inspected actual source/diffs and check logs. DATA a169581a/1fb382fe passed53 focused checks under America/Los_Angeles. Runtime fe311c1c/b59eee58 passed affected suites, including strict stamp, actual scheduler, busy/reopen and AppState paths. Fresh Grok reviews92088ab8/ff5e36d4,1280176d/aedeab17 and3bf18934/25923525 findings were adjudicated and corrected. Focused Astra reviewf861e368/48d54619 covered the consequential crash-consistency question; its queue/import/delete/day-write findings were repaired and verified. UI e0fd2ece/26093b5e passed54 tests and clean scoped analysis. Journal102 checks passed earlier with the same final Journal source. Shared Undo d2854227/3d0554ea passed3 nutrition plus16 undo/failure/2x checks. Fixture worker59bec819/f886add6 passed27 sleep-plan checks. Failed/uncertain workers were reconciled and retired.

- Required final OpenBand tests: **1493 passed**. Analysis including the integration harness: **82 items, no issues**. Logs build/cycle-checks/openband-label-final.log and openband-label-final-analyze.log.
- Additional runtime suites passed116 with2 missing-fixture skips, then61 freshness/cycle,47 actual scheduler and28 strict-stamp context cases across successive repairs. Evidence in build/cycle-checks and the isolated cycle-runtime-clone. No success inferred from worker process exits.
- All41 changed golden PNGs inspected,23 cycle and18 Journal. Final copy changed only2 observation PNGs; both inspected again. Regenerated start PNGs were byte-identical. Goldens remain in test/openband_goldens; test/goldens was not created.
- Pro build/ui-review/cycle-pro-complete:73 frames, PASS129.4s,393×852. Mini build/ui-review/cycle-mini-complete:73 frames, PASS209.45s,375×812. All146 PNGs and matching run/frames/index files inspected. Actual navigation, saved settings, read/save/refresh retry, conflicting reload, removal/undo/restore, keyboard dismissal, long-note save and2x controls passed. Final copy-only mini run cycle-mini-label-final: **73 frames, PASS228.23s**. All73 additional PNGs and run/frames/index inspected; long label fits at2x and actual long-note save passes. Pro production behavior is identical except the shortened observation label.
- Paper Phase3:44 real cycle variants,2 canonical summaries and4 Journal entry/error variants. All changed renders inspected for spacing, typography, contrast, alignment and fit. Canonical summary4EOH/4G45, main4EI2, observation4EQI, history4F9V, and shared headers/rows/Undo registered. All20 affected existing Journal variants include the cycle row. Final375px observation headers use the existing shared stacked layout. Exact50 exports/index in /private/tmp/openband-alpin-20260919/cycle-paper. Manifest124 blocks/471 screens.

Raw logging/settings/history closes the eight matching archive states only. Measured cycle history, comparisons, observed-gap review and observation counts remain open; retain legacy CycleTab/getCycle until those supported outcomes and callers/tests migrate. Synthetic SQLite/simulator proof only. No personal data, physical device, Bluetooth, physiological validation or remote writes. App0.9.31+67, schema65, algorithm90 and pinned sibling commits remain unchanged.

## Cycle measured night history · 21 September 2026

`Zyklus → Messwerte` now reads stored nights for the selected cycle. Closed cycles stop before the next logged start; an open cycle stops at the selected day. The last120 civil nights remain dense, with actual cycle-day labels when clipped. RHR and session RMSSD retain independent last readings, original absolute sleep windows, stored quality scores or unknown quality, and algorithm version. Disclosure gives the selected metric's source; an empty slot has no invented source.

The repository queries exact algorithm90 results and correction/job state in one transaction. Partial, skipped, imported, corrupt and uncompleted correction results do not become valid readings. Manual/confirmed bounds must match the active correction and its completed receipt; results older than that receipt are refused. Corrupt sibling metrics and confidence are distinguished. Database failures retry; no starts, disabled tracking, unreadable starts and a removed selected cycle have separate actions. No schema, dependency or algorithm version changes.

Paper Phase3 canonical `4HA5-0`, main `4HBH-0` / `4HG7-0`;35 exact exports in `/private/tmp/openband-alpin-20260919/cycle-measurements-paper/` cover32 new real variants, canonical block and two cycle-entry variants. All rendered and inspected. Sixteen existing info-sheet footer copies were brought back to the canonical action's48-point minimum,6-point padding and15/18 typography; all16 corrected renders inspected. Shared Flutter action unchanged. `OBTrendCard.sourced` extends the existing card/painter. Missing slots break lines and remain selectable; isolated points render, no smoothing or invented baseline. Legacy finite headline now matches its painter.

Verification with Flutter3.41.6:

- Required `flutter test --no-pub test/openband_*_test.dart`: **1562 passed**. `flutter analyze --no-pub lib test/openband_*.dart integration_test/openband_review_test.dart`: **85 items, no issues**. Logs in task `cycle-measurements-required-{test,analyze}.log`.
- DATA contract/store **44 passed** under `TZ=America/Los_Angeles`; six-file analysis clean. Includes civil/DST boundaries, selection removal, revisions, bounds, corruption and independent metric provenance. Logs `cycle-measurements-data-clone/build/cycle-measurements-checks/`.
- UI **25**, existing raw cycle **54**, health **6** passed. All26 changed/regenerated golden PNGs inspected. Isolated-first fixture needed two visual repairs, finally Material ancestor plus Lucide and a complete canvas; final focused25 passed again, analysis clean (`/tmp/cycle-measurements-isolated-material.log`). No production changes after the required suite/native source snapshot.
- `python3 tool/ui_review.py capture --flow cycle-measurements` and dedicated `--small`: **42 checkpoints each**. `build/ui-review/cycle-measurements-pro-first` PASS87.09s and `cycle-measurements-mini-first` PASS130.8s. All84 PNGs, `run.json`, `frames.json` and HTML indexes inspected. Main/dark, picker, prior cycle, gap selection, single point, empty/partial/error/retry, disabled/settings, unreadable/deleted selection,120-night clipping and375px2x scrolling/source disclosure included. Production source hashes match both runs (`cycle-measurements-native-source.json`).
- Independent DATA reviewer933a2428/26459769 and fresh UI reviewer44686273/459a5b36 closed named findings. Lead inspected actual source/diff and evidence. UI workerffd7073a corrected stale reload/picker handling and card-scoped assertions; capture workere4ab2cff corrected offscreen taps. Final test-fixture repair4a14fc1c inspected by lead.

Synthetic simulator and fixture evidence only. No personal database, physical device, Bluetooth or physiological validation. Cross-cycle medians/comparisons, observation counts and optional gap history remain open. Legacy analytical destinations remain until their supported behavior migrates. This unit does not complete the redesign.

## Cycle recorded observation counts · 21 September 2026

`Zyklus → Beobachtungen` groups saved observation tags into seven-day windows from each recorded start. It includes the open cycle and requires three contributing starts. Only tagged dates enter the denominator; note-only and missing dates are not symptom-free answers. Same-date rows union their tags. Day30 stays in its own29–35 group. Unknown tags remain visible; unreadable starts withhold grouping, while readable partial observations keep their counts with a notice. No repository, schema, algorithm or dependency changes.

Paper Phase3 main4JXR/dark4K1A and24 real variants are registered using existing shared blocks. All24 new renders and16 updated cycle navigation renders inspected. Exact26 exports/index in `/private/tmp/openband-alpin-20260919/cycle-observations-paper/`. Card bottom14 and historical same-year labels were corrected before integration. Info stays behind disclosure; main count rows are noninteractive.

- Required OpenBand tests: **1591 passed** (`cycle-observations-full-tests.log`). Required analysis: **86 items, no issues** (`cycle-observations-analyze.log`). Final harness analysis also clean. Manifest **125 blocks/527 screens**; whitespace check clean; `test/goldens/` absent.
- DATA worker745f8555 final7bcf9f34: **12 contract tests under America/Los_Angeles**, scoped analysis clean. UI workercd945f6e initial88304a74: **17 UI tests** and **54 existing cycle tests**. Lead read actual source/diff and inspected all **24 changed golden PNGs**.
- Fresh reviewer813ba56c/b8e890df found no remaining UI defects and explicitly closed the earlier clipped final-bucket and duplicate-date findings against final source. Lead independently verified helper hash4e1e0659b62d4a9b856dd7db5772c253202f69de0a4f2338d068d32d4ade6a9b.
- Native capture `--flow cycle-observations`: **29 checkpoints on each simulator**. Pro `build/ui-review/cycle-observations-final-20260921` PASS71.95s,393×852; mini `cycle-observations-mini-final-20260921` PASS99.13s,375×812. **All58 final PNGs**, run.json, frames.json and HTML indexes inspected. Includes root/back, week5, empty, partial, retry, insufficient, disabled/settings, unreadable, light/dark sheets and2x top/bottom. Lead returned initial screenshot gaps to UI worker; final4cd17e46 explicitly scrolls the info body to its end with the close action pinned. Earlier38 v1 frames were also inspected, superseded for complete coverage. Production source unchanged after required checks; final artifact hashes in task `cycle-observations-accepted-artifacts.json`.

Synthetic fixture/simulator evidence only. No personal data, physical device, Bluetooth or physiological validation. Cross-cycle medians/comparisons and optional gap history remain open; legacy cycle analytics stays until migrated. Nothing pushed.


## Cycle optional recorded-gap history · 21 September 2026

`Zyklus → Abstände` exposes the existing optional gap history and its saved display setting. Bars count civil calendar days between contributing recorded starts, excluding the current open interval. At least12 closed gaps are required; any gap over60 days or duplicate/unreadable starts withholds the result. Missing observation tags do not invalidate starts. Tracking disabled, display disabled, insufficient history, unreadable starts and database failure have separate actions. No clinical reference bands, invented coverage or default opt-in. Newest-first groups contain at most12 intervals; the final older group can contain one. Same-month groups use distinct day ranges, and one day is labelled Tag.

The shared `OBTrendCard.sourced` adds a zero-origin bar variant with actual interval selection, capped width, a centered single-bar label, accessible adjustment and large-text wrapping. The existing line path is preserved. Saving the display setting and successful refresh remain separate; a failed refresh retains the committed setting and offers retry. No repository storage, schema, algorithm, dependency or app-version changes.

Paper Phase3 main4L7S/dark4LBD; canonical bars4MOQ/dark4MQG.38 real screen exports and3 canonical exports in `/private/tmp/openband-alpin-20260919/cycle-gaps-paper/` were refreshed after final visual inspection.32 new real screens registered;16 existing cycle navigation variants updated and inspected. Corrections include the exact Lucide ruler, intrinsic value/unit alignment, large-text date wrapping, chooser safe-area padding/barrier, and disabled switches after committed refresh failure. Full scroll canvases retain complete page tops and footers.

- Required Flutter3.41.6 OpenBand suite: **1620 passed** (`cycle-gaps-full-tests.log`). Required analysis: **88 items, no issues** (`cycle-gaps-analyze.log`). Manifest **125 blocks/559 screens**. No `test/goldens/` directory.
- DATA028914dc/43e86447: **14 contract tests** under America/Los_Angeles and scoped analysis pass. UI24b4cd30/f48cc4f3: **15 UI tests**, scoped analysis pass. Existing root suite **54 passed** after regeneration. Lead inspected every one of30 new and23 regenerated root PNGs;43 PNGs changed or added. Final harness-only followup13a46fd3 scoped analysis passes.
- Fresh reviewer45c7ce11 reviewed DATA113c4ef0 and UIdbb1caa0. No remaining production findings. The drag expectation was repaired by the responsible worker; lead verified actual final source and changes.
- `python3 tool/ui_review.py capture --flow cycle-gaps --output build/ui-review/cycle-gaps-20260921`: **32 checkpoints, PASS71.92s**, dedicated iPhone15Pro393×852. `--small --output build/ui-review/cycle-gaps-mini-20260921`: **32 checkpoints, PASS108.74s**, dedicated iPhone13mini375×812. **All64 native PNGs**, run.json, frames.json and HTML indexes inspected. Root/back, selected32-day interval, older single interval, chooser, missing/disabled/insufficient/unreadable/long-gap/error/retry, settings save/refresh failure, light/dark,2x top/bottom and both complete scrollable info bodies covered. Final source unchanged after required checks and these runs; hashes in task `cycle-gaps-accepted-artifacts.json`.

Synthetic fixture/simulator proof only. Cross-cycle medians/comparisons and their legacy destinations remain open. No personal data, physical-device, Bluetooth or physiological validation. Nothing pushed.
