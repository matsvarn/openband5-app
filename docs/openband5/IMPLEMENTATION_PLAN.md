# OpenBand 5 release plan

Updated 29 September 2026. Mats approved the G3 expansion. It reverses part of the 22 September scope reduction. The reduced-release record is kept below under "Previous reduced release"; the archived full-product queue stays in `design/archive/state_checklist-20260921.json`.

## Scope · G3 "Tagesblatt"

Ranked by daily value × how well the captured data supports it. Evidence: the 28 September capability audit (private, `OpenBand5Lab/scope-20260928/AUDIT.md`) and the Mobbin boards on Paper page `G3 · Referenzen · Mobbin`.

### Wave 1 · this pass

| # | Module | Shows | Data | Owner of new work | Absence and refusal |
|---|---|---|---|---|---|
| 1 | Heute | Lead Erholung on the personal range, Schlaf and Belastung, "Für heute" note with one action, activities, check-in, week strip, night, body values, steps | Existing `day_result` / `metric_series` | edge | Erholung shows "Basis: noch N Nächte" until 14 prior nights. The note appears only when every input it names exists. |
| 2 | Training & Belastung | Auto-detected activities with confirm/change, activity result (HR trace with gaps, zones by % HR reserve, Belastung contribution, Pulserholung, optical share), manual add, live session, weekly load | 1 Hz HR, motion, on-chip counter; `autoDetectWorkouts`, `trainingZones`, `hrRecovery`, `banisterTrimp`, `ctlAtlTsb` | edge | Zones and strain state the usable optical share and refuse on thin coverage. Pulserholung needs a clean tail. No distance, pace or calories from the band. |
| 3 | Verlauf | 7/30/90-day trend per metric with the personal band; reached from every metric and the week strip | `metric_series` | edge | Gaps stay gaps. Fewer than 7 values: "noch N Tage". |
| 4 | Schlaf+ | Regularity (SRI), social jetlag, sleep debt, bedtime suggestion feeding the note and reminder | Existing crossday sleep analytics | edge | No personal sleep need, no need. Regularity needs 7 scored nights. |
| 5 | Journal | One-question check-in on Heute, Journal tab with history and patterns | Manual entries; existing `associations` | edge | Patterns withheld until the algorithm's paired-day minimum, with the remaining count. "Später" carries no penalty; no streaks. |
| 6 | Widgets | Home Screen, Lock Screen, Live Activity for a running session in the G3 language | App-group snapshot; existing WidgetKit extension | edge / iOS | Stale data shows "—" and "Daten bis HH:MM". No watch complication. |
| 7 | Körper | Skin-temperature deviation over time; weight (manual or Health import) | `skin_temp_z`; `observation`, `imported_measurement` | edge | Temperature needs three prior nights and is a deviation from your normal, never body temperature. No cycle claims. |

Wave 1 needs no analytics or protocol change. If any analytics output changes, bump `kAlgoVersion` with a deliberate, reviewed sibling pin.

### Wave 2 · after wave 1 is installed

Atmen (paced breathing with live RR; device proof required), Apple Health export acceptance, strength templates and exercise library, Beobachtungen (anomaly/illness flags; longitudinal evaluation first, never a push).

### Parked

Ernährung, Zyklus, Medikamente, Labor/Glukose, Coach and manual VO₂max remain behind development access (`OB_RELEASE=false`). Keep their code, storage, migrations and tests. Saved tabs, notification routes and gestures must not reopen them in the release.

### Refused

SpO₂ percentage, estimated VO₂max, a daytime stress score (the parked sleep-only stress index is not shipped), smart wake by sleep phase, cycle phase from temperature, and any vessel or waveform-morphology claim. The captured data does not support them.

## Design decisions (29 September)

- Direction **G3 · Tagesblatt**: sample on Paper page `G3 · Richtung · Probe`. One lead number per screen, a second ink level, the "Für heute" note as the only filled block, dark designed separately.
- Colour marks only values outside the personal normal range: green family better, amber family worse. Neutral inside the range and without a trusted baseline. The live LED stays green.
- Navigation: floating tab bar **Heute · Schlaf · Training · Journal**. Band and Profil stay in the header. Verlauf opens from each metric and the week strip.
- "Für heute" is rule-based (no LLM). The bedtime reminder is opt-in and goes through `NotificationCenter.emit`.
- Tokens: `tokens.json` is the code source of truth. The Paper file's existing `alp` names still hold the archived Alpin 3 values; G3 only adds new `alp` names and never rewrites existing ones, so archive pages keep their look.

## Design and acceptance

Paper file `01M2TRX5GZKAXKTSXK7D34E8AY` is canonical; G3 pages are named `G3 · …`, components on `Bausteine · G3`. Designphase 2 stays frozen and is mined read-only. Each shipped screen gets canonical light and dark plus its real missing, partial, error and scrolled states — no cross-product of near-identical artboards. Short German copy.

Native Flutter in `edge` matches Paper through `tool/paper_refs.py` / `tool/g2_review.py` and is checked with `--real` against a pulled phone database. Goldens only in `test/openband_goldens/`; inspect every regenerated PNG. Required checks:

```
~/.local/share/flutter/3.41.6/bin/flutter test --no-pub test/openband_*_test.dart
~/.local/share/flutter/3.41.6/bin/flutter analyze --no-pub lib test/openband_*.dart
python3 tool/check_design_manifest.py
```

Plus the iPhone 15 Pro and iPhone 13 mini simulator runs (`tool/ui_review.py`) at the release checkpoint.

Delivery is a stack of focused PRs on `openband5/g2-design`, each independently reviewed by a fresh reviewer and fixed until clean, CI green on the exact head. No merge. The final signed build is installed in place on the owner's iPhone with WAL-aware pre/post copies; `verify_capture.py` must stay CLEAN and `replay_check.dart` must exit 0.

Hard limits are unchanged: commit-before-ACK, REPLACE on `rec_ts` and the boundary-collision rule, idempotent derivation, additive/idempotent/cheap migrations, never fabricate, no firmware, experimental R22, force-trim or pointer-manipulation commands, and personal data only under `~/Library/Application Support/OpenBand5Lab`.

Out of scope and unproven: the interruption trial (CAPTURE_TRIAL.md) and the upstream protocol fold-ins (#57/#58/#59/#61/#68/#69).

## Source baseline

Verified 28 September on `openband5/g2-design` at `e7e83137`: Flutter 3.41.6, app 0.9.31+67, schema 68, algorithm 98, protocol pin `2c1bf3c51579b3212f3046af0f1be8d8ba4a0040`, analytics pin `2503ca127f78847def0db6f363f000431789d254`; pins and lock agree. PR stack #1 ← #3 ← #2; #2 CI `test` green on that head.

## Previous reduced release (22 September)

The reduced release (Übersicht, Schlaf, Band, essential Profile/Data) was locally verified and installed as signed 0.9.31+67 on the owner's iPhone; G2 · Gerät then replaced its visuals. Accepted units, check counts and device evidence are in IMPLEMENTATION_VERIFICATION.md. That record establishes capture, retained source and recorded retry, not zero-loss trials or physiological validity.
