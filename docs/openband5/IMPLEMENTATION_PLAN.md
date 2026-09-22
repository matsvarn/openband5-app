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

## Acceptance and continuation

The approved reduced release is locally verified and ready for review. All seven current checklist outcomes have evidence-backed dispositions. The historical full-product archive remains parked, not completed by relabeling.

Accepted commits:3e0558cd compact Profile/Data,6284c1bd durable restore,428b9cd6 sleep/device evidence,6bb77008 reduced navigation,48eb0fe5 reduced queue. The final Band/acceptance unit is recorded in the commit containing this update. Nothing pushed; unrelated untracked assets remain untouched.

No implementation worker is active. Mats task `/private/tmp/openband-release-reduction-20260921` retains bounded worker reports, fresh Devin SWE-2 reviews, integrated hashes and check logs. Both stalled Grok workers and earlier timed-out owners were drained/reconciled. Band source corrections were returned to Sol and inspected by the lead. Durable details are in IMPLEMENTATION_VERIFICATION.md.

Final required checks:2226 OpenBand tests,115-target analysis,59-block/28-screen manifest and diff check pass. All12 changed/new Band goldens were inspected. Band Pro/mini runs passed;32 PNGs inspected,26 accepted after six replacements. Prior accepted navigation, sleep, Profile/Data and restore evidence is retained without repeating identical checks. Paper has28 representative Release boards and32 shared boards; archives and Phase2 remain intact.

App/widget/watch0.9.31+67, schema67, algorithm90 and full dependency pins match source/lock as rechecked22September. No release metadata drift remains. No further in-scope implementation is queued. Publishing or a future physical-device session requires separate authority. Mats subsequently authorized the22September installation: signed release artifact256982f4 is installed as0.9.31+67 on the connected iPhone, with fresh backup, physical schema54→67 migration, retained data/preferences and launch/relaunch checks. See IMPLEMENTATION_VERIFICATION.md and private `OpenBand5Lab/device-install-20260922-256982f4` evidence.

The supplied device database passed isolated migration and durable restore; private evidence remains in OpenBand5Lab. It establishes capture, retained source and recorded retry, not controlled phone-kill/zero-loss trials or physiological validity. An earlier whole-suite diagnostic found three unchanged parked nutrition failures; the full suite is not claimed green. That proof statement describes the earlier database review. The subsequently authorized install/session above establishes launch, migration and short continued-storage observation; it does not establish a zero-loss or physiological trial.
