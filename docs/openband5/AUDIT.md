# OpenBand 5 source audit

Audited on 2026-09-15. This is a bounded source and local-test audit, not a complete security assessment or a hardware validation.

## Baseline

| Component | Upstream revision |
|---|---|
| App | `974a0440acb5b7ccd8ad525475afc372a674e6e8` |
| Protocol, also the app's pin | `fe1464db98b84ac4d3ce6175d54ada11356d6c62` |
| Analytics pin used by the app | `1fa8144a5e3b728ce91eeed6ecbc15d482933b44` |
| Analytics checkout main | `2a0bea11ebba4b4d8ec16348a6ab430b9a4e0184` |
| Research | `c6be09c4021546e4693dcf74da25d7b793ff8a40` |
| App versions | `0.9.29+65`, algorithm `87`, database schema `51` |
| Toolchain | Flutter `3.41.6`, Dart `3.11.4` |

The analytics checkout is ahead of the app's pin. A direct Git diff found a README change and a dispersion-guard extraction with tests. The app keeps its existing pin. No local path overrides are active.

## Findings that determine the first milestone

### 1. Identified Gen5 optical records can reach the Gen4 replay decoder

The live path recognizes Gen5 deep buffers and archives them. The database fallback maps `Gen5HistorySample`, but then falls through to `FirmwareAwareR24Decoder` for other identified Gen5 records.

A synthetic 2128-byte v20 optical-buffer fixture was accepted by both real protocol decoders. The Gen5 decoder returned `Gen5OpticalBuffer`; the legacy decoder returned `R24`, with HR 60 and gravity `[0, 0, 1]` manufactured by bytes placed at its offsets. This proves overlapping decoder acceptance. Source inspection shows the database fallback can call both in that order. Database insertion was not exercised because the app test runner is blocked by Xcode setup.

Next repair: keep recognized, non-biometric Gen5 records out of the biometric fallback and test observable database rows through a public insertion API. Preserve legitimate Gen4 decoding and the original bytes. Consider moving the duplicate Gen5 sample mapping to an existing lower shared layer if the fix earns that change.

Sources: [database fallback](https://github.com/OpenStrap/edge/blob/974a0440acb5b7ccd8ad525475afc372a674e6e8/lib/data/db.dart#L5187), [Gen5 v20 decoder](https://github.com/OpenStrap/protocol/blob/fe1464db98b84ac4d3ce6175d54ada11356d6c62/lib/src/gen5_records.dart#L882), [legacy plausibility fallback](https://github.com/OpenStrap/protocol/blob/fe1464db98b84ac4d3ce6175d54ada11356d6c62/lib/src/records.dart#L306).

### 2. The current retention policy does not support a durable research archive

`rawRetentionDays` is three. Incomplete days delay pruning, but the hold is capped at 14 days. Old `undecodable_rec_v20` archives are reduced to one in 60. Thus "store locally" does not mean that every original record remains available for future algorithm work.

Open issue #244 describes an older pruning path. The current `dayResultIds` already excludes skipped and partial results, so that issue's original mechanism should not be reported as wholly unchanged. The current bounded retention policy is still a real mismatch with this fork's data-ownership goal.

Next work: design explicit retention and complete export, measure growth, and record archive completeness. Do not simply remove all storage limits or promise every optical sample.

Sources: [retention constant](https://github.com/OpenStrap/edge/blob/974a0440acb5b7ccd8ad525475afc372a674e6e8/lib/compute/derivation_engine.dart#L1809), [prune policy](https://github.com/OpenStrap/edge/blob/974a0440acb5b7ccd8ad525475afc372a674e6e8/lib/compute/derivation_engine.dart#L5294), [complete-day filter](https://github.com/OpenStrap/edge/blob/974a0440acb5b7ccd8ad525475afc372a674e6e8/lib/data/db.dart#L7424), [v20 archive thinning](https://github.com/OpenStrap/edge/blob/974a0440acb5b7ccd8ad525475afc372a674e6e8/lib/data/db.dart#L6398).

### 3. WHOOP 5.0 inputs do not yet support every headline insight

The pinned HRV implementation rejects RMSSD and pNN50 when its successive-difference quality statistic crosses an empirical floor. Its comments report this problem on WHOOP 5 data. This is a data-dependent refusal, not a universal device-disable switch. The Gen5 temperature calibration has no settled-temperature band and therefore abstains. These missing drivers can reduce or prevent readiness output.

Do not remove the refusal to make the dashboard look complete. Verify the available beat and temperature data on Mats's band. Stable output alone does not prove physiological validity. SDNN is a separate metric, not a drop-in replacement for RMSSD.

The sleep stager includes an author-reported evaluation, but its underlying external evaluation corpus is absent from the checkout. That evidence does not establish accuracy on Mats's WHOOP 5.0. Published component methods are not validation of the combined product.

Sources: [HRV quality floor](https://github.com/OpenStrap/analytics/blob/1fa8144a5e3b728ce91eeed6ecbc15d482933b44/lib/src/onehz/clinical/hrv_time.dart#L1), [temperature calibration](https://github.com/OpenStrap/analytics/blob/1fa8144a5e3b728ce91eeed6ecbc15d482933b44/lib/src/onehz/wellness/temp_circadian.dart#L94), [readiness](https://github.com/OpenStrap/analytics/blob/1fa8144a5e3b728ce91eeed6ecbc15d482933b44/lib/src/onehz/wellness/readiness_composite.dart), [sleep stager](https://github.com/OpenStrap/analytics/blob/1fa8144a5e3b728ce91eeed6ecbc15d482933b44/lib/src/onehz/sleep/cardio_stager.dart).

### 4. Beat timing and sync completeness need targeted verification

[Upstream PR #365](https://github.com/OpenStrap/edge/pull/365) is open and unmerged at this audit. It proposes a repair for non-monotonic modeled beat timestamps and an algorithm-version bump. Its Actions run was `action_required`, so the PR text's passing-test claim is not a passing hosted run from this audit. Review the timing model and consumer behavior before importing it.

Issue #286's claim that live consumers discard every timestamp is also stale. Current `_decodeLiveRr` passes packet timestamps into correction. Empty records, duplicates, and cross-packet adjacency still deserve targeted tests; retaining a timestamp is not proof of a complete beat clock.

History ingestion implements commit-before-ACK. Preserve that ordering. The packet-count gate permits limited slack after retries, and the durability upgrade to SQLite `FULL` is best-effort with a downgrade log. Both warrant observation during a physical interrupted-sync trial. Neither was shown to lose Mats's data in this audit.

Sources: [current live RR path](https://github.com/OpenStrap/edge/blob/974a0440acb5b7ccd8ad525475afc372a674e6e8/lib/data/local_repository_impl.dart#L4186), [commit and ACK](https://github.com/OpenStrap/edge/blob/974a0440acb5b7ccd8ad525475afc372a674e6e8/lib/ble/ble_engine.dart#L6019), [durability read-back](https://github.com/OpenStrap/edge/blob/974a0440acb5b7ccd8ad525475afc372a674e6e8/lib/data/db.dart#L3097).

### 5. Own the service configuration before installing a fork

The inherited `firebase_options.dart` says "Dummy version" but contains concrete project identifiers. Native collection flags and application consent guards are present; this audit did not observe a data transmission. The bootstrap replaces these options with an explicitly unconfigured implementation, which the existing optional-initialization path handles. Backend and companion URLs are blank.

No separate server is needed for the primary experience. The backend repository is optional. The icon repository is not a direct app dependency and no license file was found there, so it is retained as a reference rather than included as a new distributable dependency.

### 6. iPhone background behavior is part of the product constraint

The app uses Core Bluetooth restoration and opportunistic background tasks. An iOS simulator does not verify the WHOOP Bluetooth integration. Apple's relaunch rules also distinguish system termination from a user force quit. Test those cases separately on a physical iPhone, with a release/profile build that can launch normally from the home screen.

Sources: [Apple restoration rules](https://developer.apple.com/documentation/technotes/tn3115-bluetooth-state-restoration-app-relaunch-rules), [upstream iOS setup](../../guides/IOS_INSTALLATION.md), [Flutter iOS setup](https://docs.flutter.dev/platform-integration/ios/setup).

## Source access and hardware boundaries

Normal WHOOP 5 history includes a decoded per-second stream and reported beat intervals. Some raw optical/IMU records have decoders, but safely obtaining every possible raw sensor channel is not established. The R22/deep-buffer helper can change persistent configuration, and the protocol source says the apparent undo is not valid. Do not enable it as a routine setup step.

The research Python client's own README says its hardware testing was on WHOOP 4.0. Its offline self-test is useful, but it does not qualify the client for WHOOP 5.0 history extraction.

The official WHOOP developer API exposes scored sleep, recovery, cycles, and workouts rather than a general raw PPG/IMU transport. That makes it useful for optional comparison/import, not the main route to this subscription-free product. [API contract](https://developer.whoop.com/api/), [persistent Gen5 configuration](https://github.com/OpenStrap/protocol/blob/fe1464db98b84ac4d3ce6175d54ada11356d6c62/lib/src/commands.dart#L813).

## Verification performed

| Check | Result |
|---|---|
| Four public GitHub forks and parent relationships | Created and read back under `matsvarn/openband5-*` |
| Flutter SDK | Installed 3.41.6, reports Dart 3.11.4 |
| Protocol `dart analyze --fatal-infos` | Passed |
| Protocol `dart test --reporter=expanded` | 611 passed, 4 skipped |
| Analytics main `dart analyze --fatal-infos` | Passed |
| Analytics main `dart test --reporter=expanded` | 633 passed, 6 skipped |
| Upstream app dependency pins | Both lock entries agree with pubspec |
| Upstream app localization generation and `flutter analyze` | Passed |
| App `flutter test --concurrency=1 --reporter=expanded` | Blocked before tests by native `objective_c` build hook |
| Root cause of native test block | `xcrun --sdk macosx --show-sdk-path` exits 69 because Xcode license is unaccepted |
| Research `python3 research_playground.py selftest` | All 14 assertions passed |
| Synthetic Gen5 decoder-overlap probe | Reproduced with real protocol functions |
| Physical iPhone/WHOOP 5.0, battery, firmware, overnight capture | Not performed |
| iOS build/signing, TestFlight, health-data export | Not verified |
| GitHub Actions | Dispatch returned 404 on the fresh fork; no hosted run claimed |

Skipped protocol/analytics tests need external captures. They do not count as passed hardware evidence. No personal captures or health records were created, uploaded, or added to the fork. Source-audit workers were read-only; the lead checked critical code and executed the tests above.

Bootstrap verification after the fork configuration edits is recorded in `VERIFICATION.md`.
