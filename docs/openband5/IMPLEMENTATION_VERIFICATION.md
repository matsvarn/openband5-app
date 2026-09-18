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
