# Develop OpenBand 5 on iPhone

Use Flutter 3.41.6 and Dart 3.11.4. These versions match the app's checked-in CI configuration. Keep the current CocoaPods integration until a separate toolchain upgrade is justified.

## Fast UI development and native review

Run from `edge`, using the pinned SDK. These commands target dedicated **OpenBand Review** simulators, never the physical phone. They reuse the production OpenBand widgets with the clearly labelled synthetic repository.

```sh
# Keep this process attached; press r after a Dart edit for hot reload.
python3 tool/ui_review.py gallery

# Review the reduced release on native iOS and export screenshots + accessibility text.
python3 tool/ui_review.py capture

# The smaller 375×812 device, including large-text states.
python3 tool/ui_review.py capture --small

# Cheap behavior and deterministic render checks before another native run.
flutter test --no-pub test/openband_flow_test.dart
```

### Paper diff for the G2 screens

`tool/g2_review.py` renders the reduced release with the synthetic fixture, in Helvetica Neue like iOS, and compares it with the G2 frames exported from Paper ("OpenBand 5 · Designphase 3", pages *G2 · Gerät · Screens* and *G2 · Gerät · Dunkel*). A run takes a few seconds.

```sh
python3 tool/paper_refs.py        # refresh docs/openband5/design/paper-g2/ from Paper Desktop (read-only)
python3 tool/g2_review.py         # all known frames, light and dark
python3 tool/g2_review.py 02 --dark
```

Each frame writes `build/g2-review/<mode>/<frame>.png` as four panels: Paper, app, a 50 % onion overlay and a red diff. The printed score is the share of pixels below the status bar that differ; use it to see whether an edit moved closer, and read the sheet for what to change. Helvetica Neue is split out of the macOS system collection into `~/Library/Caches/openband5-g2-fonts` and is never committed. Paper frames use their own fixture dates and times (for example DI 22.09), so text-only differences in dates remain. Frames are added to the map in `tool/g2_review_test.dart` as their screens are matched.

`python3 tool/g2_review.py --real` renders the same frames from a copy of the newest database pulled with `tool/pull_device_db.sh` (or `--real PATH` to a pulled `Documents` folder, `--day YYYY-MM-DD` for another day). It uses the production local repository on a temporary copy, so the pulled file is never written. The PNGs are personal data and go to `OpenBand5Lab/ui-review-real/<timestamp>/`, never into the repository; nothing is compared with Paper. Use it before an install to catch what the synthetic fixture cannot: corrected nights, days on mixed algorithm versions, provisional baselines, missing values. Helvetica Neue has no "→"; iOS draws it from a fallback font, the test renderer shows a box.

The runner creates/reuses an iPhone 15 Pro (393×852) or iPhone 13 mini (375×812) on the already installed iOS 26.5 runtime. The gallery supports state, light/dark and text-size changes; its default text scaling follows the OS. The workspace also includes **OpenBand 5: synthetic UI (hot reload)** for editor-driven hot reload and Flutter Inspector.

`capture` uses Flutter's SDK `integration_test` package and real iOS rendering. At each checkpoint a temporary loopback-only helper asks `simctl` for the whole display, so the native keyboard and status bar are included. The helper accepts only screenshot names, runs only for this review, and closes afterward. A direct `flutter drive` invocation without the runner falls back to app-surface captures and labels that limitation in `frames.json`. The default `release` flow covers the reduced product, including representative light/dark, missing/error and larger-text states. Use `--flow all` for the archived full-product journey, or a named flow for an affected feature. Each capture waits for the requested Flutter frame to rasterize before the native display checkpoint. The test entry point hides the gallery controls so captures have the product's actual viewport. No AppState, real database, Bluetooth, analytics evaluation or personal data is initialized.

Each run gets its own `build/ui-review/<timestamp>/` directory with:

- Native PNGs and a local `index.html` contact sheet for quick visual inspection.
- `frames.json`: screen labels, native logical dimensions, pixel ratio, keyboard inset and accessible content.
- `run.json`: device/runtime, duration and success/failure. A screenshot existing does not mean the test passed.

Review the matching Paper screens alongside these captures. The ordinary widget golden check detects unintended changes cheaply; it does not judge whether a newly approved baseline matches Paper. Keep large/dense, missing/partial, error and scrolled states in the review as features grow.

The integration driver uses the SDK's supported screenshot/test path, so it does not need the Device Hub GUI. The SDK test package adds development-only dependencies and its native integration-test plugin; protocol/analytics and other existing dependency versions remain pinned. [Flutter integration-test documentation](https://docs.flutter.dev/testing/integration-tests).

### Verified on this setup, 17 September 2026

- iPhone 15 Pro, 393×852: 56 full-display checkpoints passed in **128.42 s** including build and flow execution (`build/ui-review/20260917-115451/`).
- iPhone 13 mini, 375×812: the same 25 checkpoints passed in **95.54 s** (`build/ui-review/20260917-111856/`). Scrolling to actions is exercised on the shorter display; a missed tap is a hard failure.
- Captures include the actual iOS keyboard. The 15 Pro reported a **335-point** keyboard inset. Accessibility exports contain the displayed labels and values, not empty placeholders.
- An actual gallery Dart edit hot-reloaded **one library in 713 ms** (46 ms compilation, 76 ms reload, 83 ms reassembly), without reinstalling. This is one measured iteration, not a performance guarantee.
- Analysis is clean. The full macOS suite after adding the SDK test package remains **3,721 passed / 453 skipped / one unchanged Health-export platform failure**.

The Flutter 3.41.6 debug launcher emits `Target native_assets required define SdkRoot but it was not provided` on this Xcode 27 setup after the build. App launch and the measured hot reload still succeed; do not treat this warning as a failed run or change SDK/native-asset settings without a reproduced failure. Existing localization warnings belong to the untranslated legacy surfaces, not the new German first flow.

### Physical phone sessions

Use the real phone for production data, AccessorySetupKit/Bluetooth, permission sheets, VoiceOver and other native behavior. Keep it separate from the synthetic simulator loop. An attached debug session is useful while developing; profile/release is needed for realistic relaunch/background checks.

Xcode 27 can capture the connected phone directly even when Device Hub screen mirroring does not work:

```sh
xcrun devicectl device capture screenshot \
  --device DEVICE_ID \
  --destination "/absolute/path/outside/git/openband-review.png" \
  --timeout 25
```

This command captures the **foreground app**, not a specified bundle. Run it only while OpenBand is visibly foreground during an agreed review session. Keep physical captures under `~/Library/Application Support/OpenBand5Lab/ui-review-phone`, not in fixtures or committed golden files. The 23 September G2 session captured six real app screens there; see [the dated verification](IMPLEMENTATION_VERIFICATION.md). A screenshot alone does not prove Bluetooth recovery or physiological accuracy.

The Device Hub automation timeout remains a limitation for direct Mac-driven exploratory phone interaction. Do not install another Xcode, change the Flutter version or add a third-party mobile automation stack until the native test/inspection path has a concrete unmet requirement.

## Open the local workspace

Open `/Users/matsvarnskuhler/Projects/Personal/openstrap/openband5.code-workspace` in Cursor or VS Code. Install the recommended Dart and Flutter editor extensions when prompted. The workspace selects the installed SDK and adds it to new integrated terminals.

For a normal terminal session:

```sh
export PATH="$HOME/.local/share/flutter/3.41.6/bin:$PATH"
cd /Users/matsvarnskuhler/Projects/Personal/openstrap/edge
flutter --version
```

The workspace root contains sibling repositories. `origin` is Mats's fork. `upstream` is OpenStrap and has a disabled push URL. Bootstrap work is preserved on `openband5/bootstrap`; `main` holds the published setup. No global shell settings were changed.

## Current Xcode setup

Xcode 27.0, its license and first-launch setup are complete. CocoaPods 1.17.0 works. iOS 26.5 and 27.0 simulator runtimes are installed; the review runner selects 26.5. Signed device builds and simulator builds with Flutter 3.41.6 have passed. Xcode 27 uses Device Hub in place of the former standalone Simulator app; its GUI automation currently times out on this host.

```sh
xcodebuild -version
flutter doctor -v
flutter devices
```

## Configure iPhone signing

Connect the iPhone to the Mac, trust the computer, and enable Developer Mode when iOS requests it. Use a physical iPhone for Bluetooth tests.

The local ignored file `ios/Config/Signing.xcconfig` already contains:

```xcconfig
APP_BUNDLE_IDENTIFIER = dev.matsvarn.openband5
APP_WIDGET_BUNDLE_IDENTIFIER = $(APP_BUNDLE_IDENTIFIER).OpenStrapWidget
APP_GROUP_IDENTIFIER = group.dev.matsvarn.openband5
APPLE_DEVELOPMENT_TEAM =
```

Set `APPLE_DEVELOPMENT_TEAM` to your own team. Register matching app IDs and the App Group. Check the Runner and widget targets, including HealthKit and background capabilities. Keep personal signing values in this ignored file.

The iPhone build includes the app and widget. Mats has no paired Apple Watch, so Runner does not depend on or embed the inherited Watch companion. Its source and separate target remain available for future Watch work. A physical iPhone build does not require registering an Apple Watch.

For the inherited full application, an Apple Developer team that can provision its App Groups and extensions is the straightforward path. A free Personal Team has limits and is not a verified substitute for this configuration. If avoiding a developer membership is required, scope a reduced app target separately before stripping entitlements or extensions. [Apple membership comparison](https://developer.apple.com/support/compare-memberships/).

Open the workspace:

```sh
open ios/Runner.xcworkspace
```

## Resolve dependencies and check the build

The app uses full commit pins from Mats's protocol and analytics forks. Keep `pubspec_overrides.yaml` absent for baseline and release checks.

```sh
flutter pub get
flutter gen-l10n
bash .github/scripts/check_sibling_pins.sh
flutter analyze
flutter test --concurrency=1 --reporter=expanded
flutter build ios --release --no-codesign --dart-define-from-file=.env
```

The pin guard can warn on macOS if the GNU `timeout` utility is absent. Its pubspec/lock consistency check still executes. Compare upstream revisions separately rather than treating the warning as a network diagnosis.

Use the release launch configuration for normal home-screen use and overnight collection. Use debug while attached to Flutter/Xcode:

```sh
flutter run --release -d DEVICE_ID --dart-define-from-file=.env
```

Replace `DEVICE_ID` with the ID returned by `flutter devices`. On a new developer team, use this device-specific command for the first signed build so Xcode can register the connected iPhone and create its development profiles. A generic `flutter build ios` can report that the team has no registered devices. A debug installation is not the acceptance build for background and home-screen relaunch tests.

## Develop across packages

Keep the Dart package names `openstrap_protocol` and `openstrap_analytics`. They are internal import names, not product branding.

For a temporary local protocol/analytics experiment, the upstream-supported override is:

```yaml
dependency_overrides:
  openstrap_protocol:
    path: ../protocol
  openstrap_analytics:
    path: ../analytics
```

Put it in the app's ignored `pubspec_overrides.yaml` only for that experiment. It makes the app consume sibling checkouts, including analytics changes beyond the pinned version. Remove it and run `flutter pub get` before a release or CI comparison. Never commit a path-resolved `pubspec.lock`.

When promoting a package change, commit and push that package first, then pin the exact commit in the app and regenerate the lock. Update the algorithm version if output changes. Keep upstream fixes in focused commits that can be reviewed independently of app styling.

## Connect the WHOOP 5.0

1. Record the exact model and firmware privately. A WHOOP MG result is not automatically WHOOP 5.0 evidence.
2. Keep the official WHOOP app disconnected while OpenBand 5 owns the Bluetooth connection. Upstream warns that firmware changes from the official app can alter compatibility.
3. Charge the band and use its documented pairing mode. Pair through the app's existing WHOOP 5 path.
4. Inspect identity, record versions, latest stored timestamp, sync completion, and unknown records. Start with the normal stream.
5. After local build and data-retention work, run a 24- to 72-hour trial. Cover screen lock, out-of-range recovery, Bluetooth off/on, interrupted transfer, app relaunch, and a user force quit followed by manual launch.
6. Compare the persisted database and an exported replay after each interruption. Confirm that incomplete transfers are not acknowledged as complete.

Do not use the Python research client's `sync`, `live --force-optical`, firmware flags, reset, or trim commands as an assumed WHOOP 5 setup path. Its offline `selftest` needs no Bluetooth and has already passed.

## Keep laboratory data outside Git

The setup created private directories under:

```text
~/Library/Application Support/OpenBand5Lab/
  captures/
  backups/
  exports/
```

Store original captures, exported databases, firmware identifiers, and reference-device recordings there. These directories have owner-only permissions. They are an output location, not an automatic backup system. Create backups through SQLite's backup/export path so an active WAL file is not lost.

Record capture time, clock alignment, firmware, app commit, algorithm version, expected duration, and gaps with each experiment. Keep a separate immutable original before recomputing metrics. Do not enable upstream telemetry or HealthKit exports during initial experiments. Enable those integrations deliberately after their output is checked.

The inherited Firebase project options were removed. The existing initialization catches the unconfigured result and continues. If remote telemetry is later needed, configure a separate owned project and review both native and Dart collection settings. Blank backend/companion URLs alone do not disable Firebase.

## Add reference equipment only when the experiment needs it

The initial kit is the Mac, a physical iPhone, the existing WHOOP 5.0, and its charger. An iOS GATT inspector can help with service discovery, but close it before the app's connection test.

For HR/RR comparisons, a Polar H10 can provide ECG-derived beat intervals through its documented SDK. Use a separate controlled recording and align clocks. It does not validate sleep stages or recovery scores. [Polar research tools](https://www.polar.com/en/science/research-tools), [Polar BLE SDK](https://github.com/polarofficial/polar-ble-sdk).

A BLE packet sniffer is a later troubleshooting tool if app logs and a reproducible failure do not answer a specific protocol question. It is not required for the first app build.
