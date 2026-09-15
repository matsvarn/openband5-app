# Bootstrap verification

Checked on 2026-09-15 with Flutter 3.41.6 and Dart 3.11.4.

## Changes checked

The bootstrap changes the app/launcher name, package repository URLs, optional Firebase configuration, service URL examples, and project documentation. It keeps the same protocol and analytics commit pins, database schema, algorithm version, and Bluetooth behavior.

- App `flutter pub get` succeeded. The lock diff contains only the two package repository URLs; resolved commit hashes are unchanged.
- App pin guard passed the pubspec/lock consistency checks. Its optional remote-staleness probe warned because `timeout` is unavailable in this macOS shell. Direct Git reads confirmed protocol main matches the pin and analytics main is ahead as documented in the audit.
- App `flutter analyze --no-pub` passed after the edits.
- `plutil -lint ios/Runner/Info.plist` passed after the launcher-name edit.
- Analytics dependency resolution, `dart analyze --fatal-infos`, and its full test suite passed after the fork-URL edit: 633 passed, 6 skipped.
- Protocol was unchanged and its previously completed checks passed: 611 passed, 4 skipped.
- `git diff --check` passed in both changed repositories.
- Git confirms `.env` and `ios/Config/Signing.xcconfig` are ignored. The private capture directories are outside every repository.

The Flutter app test command was attempted on the initial source and stopped in the native `objective_c` hook before running tests. The underlying Xcode SDK lookup fails until the user accepts the Xcode license. No app-suite pass, iOS build, signing, device connection, or overnight reliability is claimed.

The Firebase stub is compile-checked. Runtime behavior on iPhone remains unverified. The existing startup catches an unconfigured Firebase result and continues, and the native collection flags remain disabled.

The initial GitHub Actions dispatch on the newly created fork returned 404. Hosted status after publication is recorded in the session handoff; a published commit alone does not establish executed CI.
