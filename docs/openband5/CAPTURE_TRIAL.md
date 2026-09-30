# Interruption-trial runbook — the controlled zero-loss proof

The capture claim is "a night of data that survives disconnection and app
relaunch." This is the scripted version of that claim. Run it against the
build that carries durable `raw_blob` + cursor persistence (algo 92+).

## Setup

- iPhone with the build under test installed; WHOOP 5.0 charged and worn.
- Note the pre-trial state: `sqlite3 <db> "SELECT MAX(rec_ts) FROM
  decoded_onehz"` and the newest `band_backlog` row (if the cursor columns
  exist).

## The four interruptions

Do each during an ACTIVE sync (the transfer progress visible), unless noted:

1. **Bluetooth off** — Control Centre BT off mid-transfer, wait 30 s, BT on.
   Expect: reconnect, resume from the last committed counter, no re-flood.
2. **Force-quit** — swipe-kill the app mid-transfer, relaunch.
   Expect: reconnect + resume; committed data survives.
3. **Lock/background 1 h** — lock the phone mid-transfer for an hour.
   Expect: the headless gate (`HeadlessSyncGate.tryRun`) either completes or
   cleanly skips; on unlock, normal sync resumes. No stuck latch.
4. **Out of range** — leave the band out of BLE range ≥20 min, return.
   Expect: reconnect, drain resumes.

Then let one normal overnight capture run.

## After the trial — verify, don't eyeball

Pull the database (devicectl app data container → `Documents/openstrap.db`)
into `~/Library/Application Support/OpenBand5Lab/<trial-date>/` and run:

```sh
python3 tool/verify_capture.py <db>
dart run tool/replay_check.dart <db>
```

Pass criteria — all of them, not most:

- `verify_capture.py` verdict CLEAN: no duplicate `rec_ts`, every blobbed
  record decoded, no ledger violations created after the fix boundary, no
  truncated blob frames.
- `replay_check.dart` exit 0: every replayed second matches its stored row —
  hr, centi-°C skin temp, step count — and no replayed second lacks a row.
- Coverage honesty: the interruption windows appear as `rec_ts` GAPS in the
  gap list — gaps are the honest record of a lost link; a filled gap would
  mean fabrication, which is worse than loss.
- `band_backlog` gained a row per connect; `wrap_count` did not advance
  during the trial; `current_read_ts`/`read_page` moved monotonically.
- Strain/readiness for trial days show real values or honest absence — never
  a gap-spanning invention.

## What to record

Per `IMPLEMENTATION_VERIFICATION.md` convention: trial date, build commit,
each interruption's time and observed reconnect behavior, the verifier
outputs verbatim, and any failure as a FINDING, not a retest-until-pass.
