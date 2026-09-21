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

- Lead: Paper organization and reduced compositions; private database evidence; repository docs/manifests; integration and native acceptance.
- Discovery `release-map` (`e26e8514`, assignment `e4c2e778`) complete read-only. Report in the task's workers directory. Key findings: water/energy affordances survive nullable callbacks; saved tabs/intents and three gesture actions need gating; retain active-session finish; export already uses a complete VACUUM snapshot.
- Navigation committed as6bb77008: navigation-finish (`a0baa466`, assignment877c4fa1) corrected retained alert routes and returned passing checks. Lead integrated and reviewed the changes; stale active-session notification copy was corrected. Earlier stopped workers are drained and recorded in the private task directory.
- Current implementation owner: `restore-sol` (`9017e301`, assignmentf295d6eb), configured sol-pi high in isolated `implementation/`; durable database restore, receipt and synthetic test/debug loop. Sol is an explicit bounded exception justified by the correctness-sensitive family merge and a stalled Grok attempt. The Grok restore-owner7f1de9a2 was stopped/drained with no storage edits (`restore-stop-evidence.json`). Lead owns main integration/native/Paper. No overlapping writers.
- Fresh reviewer: Devin CLI `swe-2-high`, read-only navigation review complete; accepted findings returned to the implementation owner; prompt/diff/report/export under `devin-navigation-review*` and `release-review.txt` in the task directory. This explicit user-authorized route is outside the current Mats CLI profile catalog; no routing configuration changed. The local model catalog lists it Free. Inspect actual findings and final diff before acceptance.
- Read-only discovery `release-map` assignment `014a769c` found two retained setup gaps: failed DevicePicker scan also renders empty results; FirstSync interruption lacks a resume action. Lead verified both source paths. Fix them after navigation/restore. Existing sleep/nap/goal and source-retention flows have source/test evidence; do not rebuild them.
- Devin efficiency audit complete (`devin-efficiency-followup.log`). Adopt the small release capture flow already being implemented. Do not blindly reuse a simulator binary: the capture server port is currently compiled into it. Do not remove capture settling or serialized DB tests without proving their callers/isolation. No broad framework rewrite.

Latest accepted implementation: `bcc9a90e` (dated VO₂max and import receipts). Consultation record: `482215ec`. Earlier accepted work and its limitations remain in `IMPLEMENTATION_VERIFICATION.md` and Git history. Do not rebuild it. The interrupted nutrition worker's partial clone from the old task remains unaccepted and must not be integrated.

Paper first pages contain 24 artboards and 32 shared block boards; other pages are labelled Archiv. Profile and Data have compact light/dark compositions. The active manifest has 58 blocks and 26 representative screen registrations (including two logical destinations); its source check passes. Shared-board positions use measured rendered heights to avoid overlap. Release/shared canvas arrangements and representative light/dark designs were visually inspected. Messwerte uses the canonical 44-point header controls. Overview now uses the fixture’s actual stage ring, omits unavailable baselines/temperature and drops decorative chart guides. Native Pro51.5s and mini63.85s release runs passed; all20PNGs inspected. Mini2x lower content and focused Pro missing/error followups passed and were inspected. The lead's apparent missing-status-bar finding was an image-preview misreading: direct bitmap inspection confirms the native bar in every flagged original PNG. No production SafeArea fix or capture retry mechanism is justified. SWE-2's speculative transient-inset diagnosis is rejected. The active outcome queue is `design/state_checklist.json`.

Private evidence: two exports found; the newest schema54 export passes SQLite quick_check and contains retained Gen5/beat/raw/sync records. Inspecting a database establishes stored results, not every interruption sequence or physiological validity. Private-copy migration54→67 and full snapshot export passed. Original hash is unchanged. Restore retained decoded_onehz/decoded_rr/raw_archive/sleep_override, but omitted the saved correction/job and alarm schedule. Discovery report18483d03 identifies further omitted durable tables. The next data unit must fix these omissions and preserve destination edits. Private inventory: `OpenBand5Lab/release-review-20260921/roundtrip-inventory.json`; harness and log in the Mats task. Do not claim restore complete yet.

Next: finish durable restore and private-copy roundtrip, then compact Profile/Data and the two verified Band setup gaps. Reuse the accepted navigation/Paper work. Final release checks and local commits remain required; no push.
