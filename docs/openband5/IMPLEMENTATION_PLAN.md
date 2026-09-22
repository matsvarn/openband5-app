# OpenBand 5 release plan

Updated 22 September 2026. Mats approved the radical scope reduction following the Fable consultation. Implementation has resumed. The earlier full-product queue is preserved in `design/archive/state_checklist-20260921.json`; its unmarked names are no longer release obligations.

## Release scope

- Übersicht: stored band metrics, sleep, battery, freshness and coverage. Sleep and metric details are drill-downs; Band and Profile remain in the header. No four-tab navigation in the default production build.
- Schlaf: night detail, actual gaps, history and durable correction. Existing naps and sleep goals remain; no new planning or physiological claims.
- Band: pairing, transfer, connection, failure and recovery.
- Essential Profile, settings and data: export, backup and restore.

Training/templates, full Journal/Nutrition/intake, weight/manual VO₂max, cycle, medication, labs/glucose, coach and widget expansion are parked. Keep their code, storage, migrations, tests and explicit development access. Do not describe parking as implementation. Saved tabs, notification routes and gestures must not reopen parked flows in the release. An already-running workout must remain finishable.

## Design and acceptance

Paper file `01M2TRX5GZKAXKTSXK7D34E8AY` is canonical. Its first pages are **Release · Alpin 3** and **Bausteine · Release · Alpin 3**; older pages are archives. Designphase 2 (`01M2KDQRH0A9K3N46EWHMBF61D`) remains frozen. Preserve the Alpin tokens, existing polished components and short copy. Match the retained Paper composition closely in native Flutter. Use canonical light/dark screens and representative missing/error states; do not expand a cross-product of nearly identical artboards.

One implementation owner and one fresh reviewer. The lead owns scope, Paper, integration and acceptance. Workers implement, test and fix ordinary failures in an isolated clone. Mats additionally authorized Devin CLI SWE-2 and proportionate simplification of tests/architecture to prioritize data quality and delivery speed. Keep correctness checks; remove repeated work only with source evidence. Review actual diffs and rendered evidence before acceptance. Required checks remain:

```
~/.local/share/flutter/3.41.6/bin/flutter test --no-pub test/openband_*_test.dart
~/.local/share/flutter/3.41.6/bin/flutter analyze --no-pub lib test/openband_*.dart
python3 tool/check_design_manifest.py
```

Run targeted native checks during implementation and a release checkpoint on the dedicated iPhone 15 Pro and iPhone 13 mini simulators. Inspect every regenerated PNG. Goldens belong only in `test/openband_goldens/`; never create `test/goldens/`. Preserve all existing checks for parked features. Do not repeat passed checks without a new change or unresolved risk.

## Architecture and authority

Only `edge/`, branch `openband5/ios-device-setup`, PR1. No push, merge, publish or deploy. Preserve unrelated tracked/untracked work. `protocol/` owns bytes/decoding; `analytics/` owns algorithms; `edge/` owns flows, contracts, persistence and Bluetooth orchestration. Preserve commit-before-ACK and retained source, nullable metrics, timing/provenance and separate saving/recalculation states. No invented baselines, goals or readings.

Verified source baseline: Flutter3.41.6, app0.9.31+67, schema67, algorithm90. Protocol pin `fe1464db98b84ac4d3ce6175d54ada11356d6c62`; analytics pin `1fa8144a5e3b728ce91eeed6ecbc15d482933b44`. Reconcile pins, lock and manually maintained iOS/widget/watch metadata again at final acceptance.

Mats provided the existing full device database in Downloads for this review. Read-only inspection and isolated-copy migration/export checks are authorized. Keep databases, raw rows and real screenshots outside Git under OpenBand5Lab. This does not authorize a new live-phone or Bluetooth session. Existing physical evidence, current source tests, simulator proof and physiological validity remain distinct.

## Active continuation

Mats task: `/private/tmp/openband-release-reduction-20260921`.

Accepted commits:6284c1bd durable restore,428b9cd6 sleep/device evidence,6bb77008 reduced navigation,48eb0fe5 reduced queue. Profile/Data is now accepted and included in this commit. Evidence lives in IMPLEMENTATION_VERIFICATION.md. Nothing pushed; unrelated untracked assets remain untouched.

- Active Band owner: `band-sol`, worker16192240-a031-45ea-b389-45e26fa4e851, assignmentf725f649-3337-48a1-bb54-7ddbded9e396, sol-pi high. Isolated `band-implementation/` at6284c1bd; brief `band-fixes.txt`;30-minute deadline from00:32UTC22September. Scope: pairing parity/direct WHOOP route, truthful scan retry and FirstSync resume. Add-sensor picker remains. Lead owns integration_test, Paper, native review, manifests and commits.
- Both configured Grok attempts stalled without changes and were drained/reconciled; evidence `band-cursor-stop-evidence.json` and `band-build-stop-evidence.json`. Sol is a bounded explicit exception. Profile owner and test-finish worker are retired; final matching hashes/check results are in `profile-finish-evidence.json`. Fresh Devin SWE-2 Profile review completed without blockers; lead caught and verified the large-text layout correction. No extra diagnostic worker remains active.
- Fresh read-only Band review prompt: `band-review.txt`; launch after implementation stabilizes. Inspect actual diffs and native interactions before acceptance. Existing sleep/nap/goal paths are verified and do not need rebuilding.

Paper Release/shared pages are first; archives and Phase2 remain intact. Release has28 artboards; shared32. Pairing light3IBJ/dark56BD is designed, inspected and exported in `pairing[-dark]-paper.json`, pending native acceptance and registration. Profile3GQP/5619 and Data55UX/55Y8 are accepted. Shared Profile large facts56DX/56EA and subtitle row56B2 reuse the existing board; no new matrix.

Next: finish Band implementation/review/native verification and commit. Then reconcile all seven reduced checklist dispositions and final required checks. One integrated required gate per accepted unit; reuse matching evidence. App/widget/watch0.9.31+67, schema67, algorithm90 and full dependency pins match the lock as rechecked22September. No metadata changes expected.

The supplied device database passed isolated migration and durable restore; private evidence remains in OpenBand5Lab. It establishes capture, retained source and recorded retry, not controlled phone-kill/zero-loss trials or physiological validity. No new live hardware session. An earlier whole-suite diagnostic found three unchanged parked nutrition failures; do not claim that suite green or repeat it without cause.
