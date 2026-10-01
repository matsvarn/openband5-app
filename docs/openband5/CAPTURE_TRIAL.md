# Interruption trial — the controlled zero-loss proof

The capture claim is "a night of data that survives disconnection and app relaunch". This runbook is its scripted proof. Run it against a signed release build installed in place on the owner's iPhone. Pulled databases, logs and screenshots go to `~/Library/Application Support/OpenBand5Lab/trial-<date>/` and never into Git. No band command beyond the app's normal sync is sent: no firmware, R22, force-trim or pointer command.

Record every result, including a failure, as a finding. Do not retest until it passes.

## Roles and timing

The operator (Mac) runs every command. Mats does the physical steps. The four interruptions take about 2 h 30 min; the overnight capture runs until the next morning.

| Step | Mats does | Duration |
| --- | --- | --- |
| I1 Out of range | Walks away with the band, leaves the unlocked phone at the Mac, and stays far enough away that the link drops (another floor or outside) | 20 min |
| I2 Bluetooth off | Back at the phone: opens OpenBand; while the transfer runs, Control Centre → Bluetooth off, waits 30 s, Bluetooth on | 2 min |
| — | Walks away again to build a backlog | 10 min |
| I3 Force-quit | Back at the phone: opens OpenBand; while the transfer runs, swipes the app away, waits 10 s, reopens it | 2 min |
| — | Walks away again | 10 min |
| I4 Lock | Back at the phone: opens OpenBand; while the transfer runs, locks the phone and leaves it locked | 60 min |
| Night | Wears the band as usual; the phone stays on the night stand, app not force-quit | overnight |

"While the transfer runs" means the Band screen shows data arriving (the backlog after 10–20 min apart takes tens of seconds). If the transfer has already finished, note it and carry on; the interruption then tests an idle link, not a transfer.

## Setup (operator)

```sh
cd <edge worktree>
LAB="$HOME/Library/Application Support/OpenBand5Lab"
DEVICE="iPhone von Mats"; BUNDLE=dev.matsvarn.openband5
git rev-parse HEAD                      # the build commit, recorded with the result
xcrun devicectl device info processes --device "$DEVICE" | grep -i openband   # OpenBand PID only
```

1. Stop **only** the OpenBand process (`xcrun devicectl device process terminate --device "$DEVICE" --pid <pid>`), then pull the before copy: `tool/pull_device_db.sh trial-pre`. The script copies Documents (db, -wal, -shm) plus the field log from `Library/Application Support`.
2. `sqlite3 "<pre>/Documents/openstrap.db" "PRAGMA integrity_check"` must print `ok`.
3. Relaunch: `xcrun devicectl device process launch --device "$DEVICE" $BUNDLE`. Wait until the Band screen shows connected, then record the trial start: `echo "T0=$(date +%s)" >> "$LAB/trial-<date>/times.txt"`.
4. Write each interruption's start and end (`date +%s`) into `trial-<date>/times.txt` while Mats performs it.

## What the field log must show

`openstrap_sync.log` from the after pull, per interruption:

| Interruption | Required lines |
| --- | --- |
| I1 | Always: `[LINK] down reason=…` near the I1 start, later `[LINK] reachable again after …, <n> failed attempts` (n may be 0 when one pending connect simply completed), then `Backlog drained`/`Reconnect backlog drained`. If n > 0: also `[LINK] unreachable since <near the I1 start>`. If the phone locked or the app went to the background while the band was away: also `[LINK] background pending connect (up to 20 min)` or one of the arm lines (`[ble-restore] armed pending connect …`, `Backgrounded — no live connection; armed iOS restore recovery`). |
| I2 | `[LINK] down …` at the toggle, a reconnect within about 1 min of Bluetooth on, backlog drained; no `Session start failed` loop |
| I3 | `===== SESSION START =====` after relaunch, `[BACKLOG] … current_read=` continuing from the last committed second, backlog drained |
| I4 | Either `[bgsync]`/`[ble-restore]` lines with a completed or skipped headless drain, or the live link held (`Backgrounded — holding live connection`). On unlock a sync resumes; no lease stays held without a session. |
| All | No `[LINK] connect attempt took …` without a later `reachable again`; no `syncDone watchdog fired` unless followed by a successful reconnect |

A missing required line is a finding, even if the data checks pass. A conditional line is required only when its condition happened; note which conditions applied.

## If the band stops connecting

This applies during the trial or at any other time, whenever reconnects keep failing for more than about 5 minutes while the band is on the wrist. The 29–30 September outage showed that only the band's side of the story says why (audit `audits/reliability-2026-10.md`).

1. Note the time. Leave OpenBand running; do not force-quit it or toggle Bluetooth.
2. If a second phone or the Mac is at hand, scan with nRF Connect for 60 s and note whether a WHOOP advertisement appears, and its name and whether it is connectable.
3. Double-tap the band and note the time to the second.
4. Scan again for 60 s.
5. Once the band is back, let the backlog finish, then pull with `tool/pull_device_db.sh incident`. The band's console lines and events 11/12 arrive with the backlog; `[LINK]` and `[ble-restore]` lines give the phone's side.

## After the trial — verify, don't eyeball

After the night, record the window end first: `echo "T1=$(( $(date +%s) - 900 ))" >> "$LAB/trial-<date>/times.txt"`. The 15 minutes keep seconds still waiting in band flash out of the loss check. Then stop only the OpenBand process and pull `tool/pull_device_db.sh trial-post`. Then:

```sh
PRE="<pre>/Documents/openstrap.db"; POST="<post>/Documents/openstrap.db"
T0=$(sed -n 's/^T0=//p' "$LAB/trial-<date>/times.txt"); T1=$(sed -n 's/^T1=//p' "$LAB/trial-<date>/times.txt")
: "${T0:?T0 not recorded}" "${T1:?T1 not recorded}"   # stop here rather than query an empty window
sqlite3 "$POST" "PRAGMA integrity_check"                  # ok
python3 tool/key_retention.py "$PRE" "$POST"               # RETAINED, exit 0
python3 tool/verify_capture.py "$POST"                     # VERDICT: CLEAN
dart run tool/replay_check.dart "$POST"                    # exit 0
```

Run the queries below on a scratch copy of the after database, or with `?mode=ro`. `T0` is the relaunch time. `T1` is the start of the after pull minus 15 min, so that the last seconds still waiting in band flash don't count as loss.

Bind both times first. sqlite3 treats an unbound `:T0`/`:T1` as NULL and still exits 0, which makes every query below look clean on an empty window. Save the block as `zero_loss.sql` and run it like this:

```sh
cp "$POST" /tmp/trial-post.db   # scratch copy; the pull stays untouched
sqlite3 /tmp/trial-post.db ".param set :T0 $T0" ".param set :T1 $T1" ".read zero_loss.sql"
```

```sql
-- Z1 Zero loss: every second the band counted between T0 and T1 is stored.
--    Walk in time order. Within one counter epoch the counter rises by 1 per
--    stored second, so a forward jump is lost seconds. A counter that goes
--    backwards starts a new epoch (band reboot) and is counted, not treated as loss.
WITH w AS (SELECT counter, LAG(counter) OVER (ORDER BY rec_ts) pc
           FROM decoded_onehz WHERE rec_ts BETWEEN :T0 AND :T1)
SELECT COUNT(*) AS seconds,
       COALESCE(SUM(CASE WHEN counter - pc > 1 THEN counter - pc - 1 END), 0) AS missing,
       COALESCE(SUM(counter - pc > 1), 0) AS holes,
       COALESCE(SUM(counter < pc), 0) AS epoch_resets
FROM w;                                                     -- missing = 0

-- Z2 No duplicates inside the window.
SELECT COUNT(*) - COUNT(DISTINCT rec_ts) FROM decoded_onehz
 WHERE rec_ts BETWEEN :T0 AND :T1;                         -- 0

-- Z3 Ledger state of the trial's batches (informational). The ledger has no
--    commit timestamp, so it cannot show commit-before-ACK; that order is pinned
--    by test/ble_safe_trim_test.dart, and a violation would show up as loss in Z1.
--    Expect only 'acked'; anything else names a batch that is still stuck.
SELECT status, COUNT(*) FROM sync_ledger
 WHERE created_at >= :T0 * 1000 GROUP BY status;

-- Z4 The band handed everything over: newest cursor at the live edge,
--    flash never wrapped during the trial.
SELECT datetime(ts,'unixepoch','localtime'), read_page, trim_page, wrap_count,
       datetime(current_read_ts,'unixepoch','localtime')
FROM band_backlog WHERE ts >= :T0 ORDER BY ts;
-- one row per connect; wrap_count constant; read_page/current_read_ts never go back;
-- the last current_read_ts is within minutes of the pull.

-- Z5 The band's own view of each interruption (events 11/12 = connection up/down).
SELECT datetime(ts,'unixepoch','localtime'), event_id, name FROM band_events
 WHERE ts BETWEEN :T0 AND :T1 AND event_id IN (9,10,11,12,14) ORDER BY ts;

-- Z6 Coverage honesty: gaps over 60 s. Each must start at a band WRIST_OFF
--    (Z5) or lie inside a recorded interruption window; nothing fills them.
WITH g AS (SELECT rec_ts, LAG(rec_ts) OVER (ORDER BY rec_ts) p FROM decoded_onehz
           WHERE rec_ts BETWEEN :T0 AND :T1)
SELECT datetime(p,'unixepoch','localtime'), datetime(rec_ts,'unixepoch','localtime'), rec_ts - p
FROM g WHERE rec_ts - p > 60 ORDER BY p;
```

Pass criteria, all of them:

- integrity `ok` on both copies; `key_retention.py` RETAINED; `verify_capture.py` CLEAN; `replay_check.dart` exit 0.
- Z1 `seconds > 0` and `missing = 0` (zero seconds means the window was not bound or not read), Z2 `0`, Z3 only `acked`, Z4 at least one row and as described.
- Z6: every gap is explained by a WRIST_OFF or is absent. An interruption normally leaves **no** gap, because the band stores to flash and the backlog fills the time on reconnect. A gap that a later drain did not fill is loss, and Z1 must show it.
- Every required log line above is present.
- Strain, recovery and sleep for the trial days show real values or honest absence, never a value bridging a gap.

## What to record

In `IMPLEMENTATION_VERIFICATION.md`, record the trial date, build commit, each interruption's start and end time, the reconnect time observed in the log (`reachable again after …`), the verifier outputs verbatim, the Z1–Z6 results, and every failure as a finding. Keep `times.txt`, both pulls and the outputs under `OpenBand5Lab/trial-<date>/`.
