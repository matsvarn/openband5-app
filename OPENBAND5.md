# OpenBand 5

> Release scope approved 21 September 2026: daily band data, sleep, Band and essential Profile/settings/data. Secondary modules remain preserved behind development access. The current scope, queue and acceptance process are in [IMPLEMENTATION_PLAN.md](docs/openband5/IMPLEMENTATION_PLAN.md); the previous full-product checklist is archived.

A subscription-free app for WHOOP 5.0. An independent [OpenStrap](https://github.com/OpenStrap) fork owned by Mats, focused on iPhone and the WHOOP 5.0 hardware he already owns.

The aim is reliable access to the band's useful data, understandable insights, and an app that can be personalized. The official WHOOP subscription is already inactive. Direct Bluetooth is therefore the primary connection.

## Start with trustworthy recording

The first useful result is a night of data that survives disconnection and app relaunch, with visible coverage and clear reasons for unavailable metrics.

A redesigned recovery screen cannot repair missing or misinterpreted sensor records. The audit found a reproducible decoder overlap, a short data-retention window, and WHOOP 5-specific limits in the current analytics. Those determine the order of work.

### 1. Establish a reliable WHOOP 5.0 recording

- Fix the replay path that can pass identified Gen5 optical buffers into a Gen4 biometric decoder. Exercise the public database insertion path with synthetic input and prove that no false biometric row is stored.
- Keep captured source data available for later algorithm comparisons. Design an explicit local archive and export policy before a multi-week trial. Measure storage and battery cost. Upstream normally retains decoded inputs for three days, so it is insufficient as the sole research archive.
- Review the beat-axis correction proposed in upstream PR #365. Verify the problem and the effect of the proposed timing adjustment before bringing it into the fork.
- Surface the last successfully stored band timestamp, missing intervals, unknown record types, sync failures, and metric refusal reasons. A recent connection is not evidence of fresh data.
- Test the owner's exact WHOOP 5.0 model and firmware on a physical iPhone. Record firmware, packet versions, and packet-count behavior privately.

Acceptance is a 24- to 72-hour collection trial with documented gaps, successful interrupted-sync recovery, and an export that can be replayed. This is a proposed acceptance exercise, not a completed result.

### 2. Make the daily iPhone experience useful

Use the first recording to choose which information belongs on Today. Prioritize useful sleep duration, resting heart rate, activity, battery, data freshness, and a clear explanation when an insight is unavailable. Show measurement method and source where comparison needs them.

Research and review a few focused screen directions before implementing a redesign. Personalization should start with useful cards, units, goals, notifications, and a way to correct a falsely detected sleep session. Keep existing storage and analytics ownership intact.

### 3. Improve algorithms with an evaluation set

Collect multiple nights and repeatable rest/exercise sessions. Keep original inputs, derived results, algorithm version, firmware version, and manual labels separate.

For heart rate and beat intervals, compare synchronized recordings with an ECG-derived reference such as a Polar H10. This is an optional next tool, not a prerequisite purchase. An Apple Watch can offer a practical comparison, but neither its scores nor WHOOP's scores are ground truth for every metric. Sleep-stage accuracy requires stronger labels such as polysomnography. A sleep diary can help evaluate timing, not reliably label REM and deep sleep.

Keep a held-out evaluation set. Personal tuning on the same nights used for evaluation does not demonstrate improvement. Retain conservative refusal when evidence is weak. SDNN and RMSSD measure different properties; do not relabel one as the other or substitute it into recovery merely because it looks stable.

Each meaningful output change needs a new algorithm version and a deliberate sibling-package pin. Compare accuracy, missingness, battery use, and runtime, not just whether the score looks plausible.

## Keep the fork small

| Repository | Responsibility |
|---|---|
| [openband5-app](https://github.com/matsvarn/openband5-app) | Flutter UI, iOS integration, Bluetooth session management, storage, pipeline orchestration |
| [openband5-protocol](https://github.com/matsvarn/openband5-protocol) | Frames, commands, record decoding |
| [openband5-analytics](https://github.com/matsvarn/openband5-analytics) | Pure Dart algorithms and evaluation tests |
| [openband5-research](https://github.com/matsvarn/openband5-research) | Protocol notes and laboratory reference tools |

Keep internal Dart package names and upstream history. Scope new product work to WHOOP 5.0 without deleting all other adapters before there is a concrete reason. Pull useful upstream fixes selectively. The app pins full package commit hashes and resolves them from the fork repositories.

The optional backend is not needed for Bluetooth, storage, or on-device calculations. No server deployment is part of this setup. The standalone icons package is not a direct app dependency at the audited revision. Both remain local references.

## What this project cannot promise yet

Bluetooth access does not expose every sensor sample in a documented, usable form. Some metrics are device-computed, some fields are uncertain, and some sensor modes change persistent device configuration. The current research client was primarily tested on WHOOP 4.0. Do not treat it as a verified WHOOP 5.0 capture tool.

Do not enable experimental R22/deep-buffer firmware flags to pursue "all data". The protocol source describes a persistent flag with no proven undo. The first collection should use the normal WHOOP 5.0 stream. Firmware compatibility, background collection, and physiological accuracy remain physical-device questions.

## Current delivery

The initial fork setup establishes the project name, package remotes, pinned toolchain, local signing template, private lab-data directory, and source audit. It removes the inherited Firebase project configuration. Launcher branding is updated for iPhone; a full in-app copy/design pass is future work.

See [the audit](docs/openband5/AUDIT.md) for evidence and [the development guide](docs/openband5/DEVELOPMENT.md) for commands and remaining prerequisites. Preserve the upstream MIT notices. OpenBand 5 is independent of both OpenStrap and WHOOP.
