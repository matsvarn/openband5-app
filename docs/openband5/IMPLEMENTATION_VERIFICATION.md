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
