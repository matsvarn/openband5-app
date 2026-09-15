# Develop OpenBand 5 on iPhone

Use Flutter 3.41.6 and Dart 3.11.4. These versions match the app's checked-in CI configuration. Keep the current CocoaPods integration until a separate toolchain upgrade is justified.

## Open the local workspace

Open `/Users/matsvarnskuhler/Projects/Personal/openstrap/openband5.code-workspace` in Cursor or VS Code. Install the recommended Dart and Flutter editor extensions when prompted. The workspace selects the installed SDK and adds it to new integrated terminals.

For a normal terminal session:

```sh
export PATH="$HOME/.local/share/flutter/3.41.6/bin:$PATH"
cd /Users/matsvarnskuhler/Projects/Personal/openstrap/edge
flutter --version
```

The workspace root contains sibling repositories. `origin` is Mats's fork. `upstream` is OpenStrap and has a disabled push URL. Bootstrap work is preserved on `openband5/bootstrap`; `main` holds the published setup. No global shell settings were changed.

## Complete Xcode setup

Xcode 27.0 is installed at `/Applications/Xcode.app`, but its license was unaccepted during setup. Open Xcode and review/accept the license yourself. Finish any required first-launch components, then run:

```sh
xcrun --sdk macosx --show-sdk-path
xcodebuild -version
pod --version
flutter doctor -v
flutter devices
```

CocoaPods 1.17.0 is installed but also refuses to run until the Xcode license is accepted. Simulator runtimes and Xcode 27 compatibility with this pinned Flutter version remain unverified. Do not interpret installation as a successful app build.

## Configure iPhone signing

Connect the iPhone to the Mac, trust the computer, and enable Developer Mode when iOS requests it. Use a physical iPhone for Bluetooth tests.

The local ignored file `ios/Config/Signing.xcconfig` already contains:

```xcconfig
APP_BUNDLE_IDENTIFIER = dev.matsvarn.openband5
APP_WIDGET_BUNDLE_IDENTIFIER = $(APP_BUNDLE_IDENTIFIER).OpenStrapWidget
APP_GROUP_IDENTIFIER = group.dev.matsvarn.openband5
APPLE_DEVELOPMENT_TEAM =
```

Set `APPLE_DEVELOPMENT_TEAM` to your own team. Register matching app IDs and the App Group. Check the Runner, widget, and Watch targets, including HealthKit and background capabilities. Keep personal signing values in this ignored file.

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

Replace `DEVICE_ID` with the ID returned by `flutter devices`. A debug installation is not the acceptance build for background and home-screen relaunch tests.

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
