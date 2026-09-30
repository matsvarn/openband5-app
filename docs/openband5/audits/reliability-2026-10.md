# Capture reliability audit · October 2026

Scope: why the WHOOP 5.0 band could not be reached from 29.09 23:54 to 30.09 13:28, and how the app detects, reports and recovers from a silent or unreachable band. Base `openband5/g31-paper` at `61dcdd29` (app 0.9.34, schema 68, algorithm 98). All times are local (CEST). Evidence is private and stays under `~/Library/Application Support/OpenBand5Lab`: the pre/post device copies of 30 September, their `openstrap_sync.log` field logs, and the band's own event and console records that the app stored or logged when the backlog came in. This report contains times and counts only.

## Result

No data was lost. The band recorded the whole night and handed over the backlog after it came back. The 13-hour outage was **band-side**: after a supervision-timeout disconnect the band did not become connectable again until it was double-tapped. The app is not the cause, and the restore-central/Dart contention hypothesis is refuted as a cause. The phone held a pending connect for most of the outage, and an iPhone restart did not help.

The contention is real at the **recovery** moment. When the band finally became reachable at 13:18:34, the phone got a link within the same second and the app threw it away 15 s later. The next working link came at 13:28:27, about 10 minutes later. Two mechanisms explain this, and both are fixed here (F1, F2). The native restore central and the headless path wrote nothing to the field log, so what the restore central did can only be inferred. That gap is also fixed (F3, F4).

## Evidence sources and their limits

| Source | Covers | Limit |
| --- | --- | --- |
| `band_events` (DB copies 20:27 and 22:46) | Band event log for the whole night, drained at 13:28–13:44 | Event 11/12 are named BLE_CONNECTION_UP/DOWN only in `research/decode_events.py` (empirical), not in the protocol constants |
| Band console (`[CONSOLE gen5]` lines in the field log, drained with the backlog) | The band's own firmware log, chunked; timestamps are chunk flush times (±30 s) | Fragments; parts of lines are missing |
| `sync_ledger`, `band_backlog`, `decoded_onehz` | Every committed batch, read cursor, stored seconds | App-side only when connected |
| `openstrap_sync.log` (0.9.33, then 0.9.34) | App side from **30.09 09:53:02** | No iOS field log existed before `b0da2895` (30.09 09:51). The 0.9.33 log lost lines: appends were not serialised until `f2070cd2`. `…foregroundIntent=t2026-2026-09-30T11:48:45` shows two lines overwriting each other. A missing line is not proof of a missing event. |
| Native restore manager | — | NSLog only; nothing reached the field log |

## Timeline

| Time | Source | What happened |
| --- | --- | --- |
| 29.09 20:03:06 / :12 | band events 12 → 11 | Ordinary drop and reconnect (6 s) |
| 23:11:13, 23:41:13 | `band_backlog` | 30-minute history syncs over the live link |
| 23:41:29 | `sync_ledger`, `decoded_onehz` | Last acknowledged batch; read cursor `current_read_ts` = 23:41:29 |
| 23:50:28–23:54:12 | band console | "BLE_CMD: Command Link Valid" about once a minute: the app's keep-alive was still arriving |
| 23:53:22 | `band_events.captured_at` | Last event received live (STRAP_CONDITION_REPORT) |
| 23:53:28 | band console | Sleep flag STILL → WAKE (movement) |
| 23:54:10 | band event 11 | Connection-up event without a preceding down |
| 23:54:15 | band event 12 | Connection down |
| ≈23:54:20 | band console | `BLE DM: Connection 1 ATTS_HANDLE_VALUE_CNF error 168` |
| ≈23:54:33 | band console | `Disconnected reason 0x8 conn id 1`, then `…vertising after disconnect`. 0x08 is a link-supervision timeout: the band stopped hearing the phone at the link layer. On every other disconnect the same line reads "Restart advertising after disconnect". |
| 23:54 → 30.09 13:18 | band events | **No connection event for 804 minutes**, the longest disconnected span in the database. The band kept recording: 81 condition reports, 4 WRIST_OFF/ON pairs, the 07:15 alarm, no BOOT, no RTC_LOST. Backlog peaked at 3,268 pages behind. |
| 30.09 09:09 | install | 0.9.33 installed (no field log yet) |
| 09:53:02 → 13:18:36 | field log | 27 foreground leases, 14 logged "Timed out after 20s", 5 "Backgrounded — no live connection; armed iOS restore recovery", 3 session starts. Leases lasted up to 1,445 s for a 20 s connect: the process was suspended with the connect pending. The pending CoreBluetooth connect stays armed while suspended, so the phone was listening for the band almost continuously. |
| — | Mats (outside the logs) | iPhone restart and Bluetooth toggle did not help; a 75 s Mac scan saw no WHOOP; no other app held the band; green LED blinking |
| 13:18:34 | band events 14, 14, 11 | DOUBLE_TAP, then connection up in the same second |
| 13:18:36 | band console; field log | Band: "Connected to conn id 1". App: foreground lease 20 released (held since 12:54:30) with no session logged |
| ≈13:18:51 | band console | `Disconnected reason 0x13`: the **central** ended the link after about 15 s |
| 13:28:26–13:28:30 | field log; band console | Lease 21, WHOOP 5 detected, "Connected + subscribed"; `[BACKLOG] … current_read=2026-09-29T23:41:29` |
| 13:28:33 | field log | `[MEMFAULT] strap volunteered its first crash/diagnostic chunk (244 B)`, contents not decodable here |
| 13:28:33 → 13:44:32 | `sync_ledger` | Backlog drained; pages behind fell to near zero |

Coverage of 23:41:30 → 13:20: 47,127 of 49,111 seconds stored. The gaps over 60 s begin at a band WRIST_OFF (01:09, 09:17, 10:34), plus 09:55–09:57. The record counter over the same window is contiguous: 47,127 seconds, 0 missing counters (CAPTURE_TRIAL.md query Z1 on the 22:48 copy). The band records no seconds while off the wrist, so the gaps are not loss.

## Causes considered

| # | Hypothesis | Verdict | Evidence | What would separate it next time |
| --- | --- | --- | --- | --- |
| H1 | Native restore central and Dart reconnect loop contend and keep the band away | **Refuted as the outage cause; confirmed at recovery (F1/F2)** | A central cannot stop a peripheral advertising. The band logged no connection for 13 h. The iPhone restart, which kills both centrals, did not help. The Mac could not see the band either. | — |
| H2 | Another central held the band (one-central rule, `research/PROTOCOL.md` §1.1) | Refuted | Band console: disconnect, then advertising restarted; no connection-up for 804 min | — |
| H3 | iPhone Bluetooth stack or bond cache wedged | Unlikely | Restart and toggle did not help; an independent Mac scan was also negative | Scan from a second phone (nRF Connect) during the outage |
| H4 | Band firmware stopped advertising, or advertised non-connectably, after the 0x08 drop until a user interaction | **Most likely** | No connection events; Mac scan negative; the pending iPhone connect completed in the same second as the double tap; a Memfault chunk was volunteered at reconnect | Next time: double-tap before anything else and note the exact time. Scan with nRF Connect before and after the tap. Keep the Memfault chunk (collected, not decodable here). |
| H5 | Band advertised only directed / to its filter-accept list | Cannot be separated from H4 | A Mac scan would miss directed advertising, but the bonded iPhone should still have connected | BLE sniffer, or a second phone scan showing whether any advertisement exists |
| H6 | Range / RF | Unlikely | Band worn, phone nearby, 13 h without a single connection | — |
| H7 | Battery or charging | Refuted | 60 % charge, not charging, condition reports every 10 min | — |
| H8 | Clock / flash | Refuted | No RTC_LOST or BOOT event; read cursor intact at 23:41:29; `wrap_count` 14 unchanged | — |

The supervision timeout at 23:54 itself is unexplained. The band logged an ATT confirmation error (168) 13 s before the drop. The phone side of that moment has no log.

## Findings

P0 = data loss or invariant break · P1 = keeps the app from recovering or diagnosing · P2 = misleading or slow · P3 = hygiene. "Fixed" means fixed on this branch with a test that failed before.

### P0

None. Commit-before-ACK held: the backlog after 13:28 committed every batch before its ACK, `verify_capture.py` was CLEAN and `replay_check.dart` exited 0 on all four 30.09 copies (IMPLEMENTATION_VERIFICATION.md).

### P1

**F1 · A restore wake during the reconnect loop drops the link the OS just delivered.** Fixed.
`lib/ble/ios_ble_restore.dart:31-47`, `lib/sync/background_sync.dart:81-88`, `lib/sync/band_ownership.dart:57`, `lib/state/app_state.dart:5302`, `ios/Runner/BleRestoreManager.swift:273-292`.
While `AppState._reconnect` runs it holds foreground intent, and `tryAcquireHeadless()` then always returns null (throwaway probe: `BandOwnership.markForegroundIntent(true)` → `tryAcquireHeadless() == null`, passed). So a restore wake runs `runHeadlessSync`, which skips at once; the handler then sends `syncDone`. With `foregroundActive` set it sends `syncDone` without even trying. Native `syncDone` cancels the restore central's connection and marks the band idle-after-sync, so it is not re-armed until the next disconnect edge. If no flutter_blue_plus connection holds the peripheral at that moment, iOS drops the physical link. The 13:18 sequence matches: link at :34, lease released at :36, central-initiated disconnect (0x13) at about :51, next link 10 min later.
Fix: a wake that cannot drain because the foreground session owns or wants the band waits, bounded to 40 s, until an engine holds the band link, then acknowledges. The outcome is logged.

**F2 · An overdue connect timeout cancels a connect that succeeded while the app was suspended.** Fixed.
`lib/ble/ble_engine.dart:2393-2413`. flutter_blue_plus 1.36.8 implements `connect(timeout:)` as a Dart `Future.timeout` (`bluetooth_device.dart:153-160`) and on timeout issues a platform disconnect. iOS freezes the timer while suspended: leases lasted up to 1,445 s for a 20 s timeout. On resume the timer fires first, and a link that came up during the suspension is treated as a failure.
Fix: on timeout, ask the system whether the band is connected (`FlutterBluePlus.systemDevices`). If it is, re-attach once with a 5 s connect instead of failing. Every attempt that overran its timeout is logged as "the process was suspended during it".

**F3 · Native restore activity never reaches the field log.** Fixed.
`ios/Runner/BleRestoreManager.swift` uses only NSLog: arm and skip reasons, `willRestoreState`, `didConnect`, `didDisconnect`, the watchdog. The audit question "what did native restore do" cannot be answered from any existing log.
Fix: every native line is forwarded over the channel, with its native timestamp, into `openstrap_sync.log` as `[ble-restore] …`, buffered until Flutter is ready.

**F4 · Headless sync decisions never reach the field log.** Fixed.
`lib/sync/background_sync.dart` logs "skipped — foreground … owns the band", "strap not reachable this cycle" and lease acquisition through `debugPrint` only.

### P2

**F5 · No record of when the band became unreachable, for how long, or how many attempts failed.** Fixed (log only).
`lib/ble/ble_engine.dart:3983-4008` logs one `Link down (reason=…)` line; failed attempts log a bare exception. The log now carries `[LINK] down …`, `[LINK] unreachable since …`, a progress line every 10th failed attempt, and `[LINK] reachable again after …, n failed attempts`.

**F6 · False "band likely rebooted" lines flood the log.** Fixed.
`lib/ble/ble_engine.dart:4802` feeds one `CounterRegressionDetector` (`lib/ble/ble_state.dart:574`) with every historical record. WHOOP 5 interleaves record versions 24 and 26, which share one counter space (both present at counter 23834122). One normal drain (13:28:47–13:44) logged 1,509 regressions, and the band did not reboot. This is also about 0.3 MB of log per drain. Fix: regressions are judged per record version.

**F7 · Field log too short for an overnight incident.** Fixed.
`lib/sync/file_log.dart:24` rotates at 2 MB into one `.1` file. At the measured 1.8 MB per 13 h the pair keeps about a day. Raised to 6 MB. Together with F6 that is about three days.

**F8 · Nothing outside the app says the band has been silent for hours.** Not built: decision for Mats (D1).
`lib/sync/sync_policy.dart:729-730`: the in-app quiet tier starts at 12 h, and the OS notification only at 48 h. The 13-hour outage produced no notification.

**F9 · The unreachable copy recommends actions that did not help.** Owner: code quality (`lib/openband/g3/screens/band.dart:276`); decision D2.
The card says "Bluetooth … aus- und wieder einschalten. Band kurz auf das Ladegerät legen." The Bluetooth toggle and an iPhone restart did not help. The one observed recovery followed a double tap on the band (n = 1).

**F10 · "Band nicht erreichbar" shows only the last attempt, not since when.** Owner: code quality (`lib/openband/g3/screens/band.dart:270`) and storage (`lib/data/models.dart:372`, `DeviceState.lastConnectFailedAt`).
The first failure of an episode is overwritten by every later attempt. F5 logs "unreachable since"; showing it on the card needs a field on `DeviceState` and the card copy.

**F11 · The reconnect loop's foreground intent blocks every headless entry point.** Owner: code quality (`lib/state/app_state.dart:5302`, `:5361-5365`).
While the loop runs, BGAppRefresh/BGProcessing wakes skip headless sync as well (`lib/sync/ios_bg_task.dart:72` → `runHeadlessSync` → skipped). With F1 the restore wake now waits for the loop to take the link. It cannot shorten the loop's backoff wait (up to 36 s), because the loop lives in `AppState`. Recommended there: let a restore wake cut the backoff wait short (a one-shot "reconnect now" hook), so the link is taken over at once.

**F12 · Reconnect policy on iOS.** No change; decision D3.
`lib/ble/ble_state.dart:382` (2 s → 30 s cap, ±20 % jitter) plus the 20 s connect timeout gives one attempt about every 40–56 s in the foreground, indefinitely. It never gives up except on bond refusal, and the cap is not too far. In the background the process is suspended, and in practice there was one attempt per iOS wake (14 timeouts in 3.5 h). The CPU cost is those wakes; the radio cost of a pending CoreBluetooth connect is small. The native restore central already keeps a no-timeout pending connect between wakes. That, not the Dart loop, is what can bring the band back while the phone sleeps.

### P3

**F13 · `tool/pull_device_db.sh` copies only `Documents`.** Fixed for the trial.
Since `5402dbb7` the iOS field log lives in `Library/Application Support`, so pre/post pulls miss it. The script now also pulls `openstrap_sync.log` and `.1` from there.

**F14 · Concurrent processes can still interleave log lines.** Not fixed.
`FileLog` serialises appends within one isolate. Two processes, such as the old and new app around an in-place install at 30.09 20:27:43, still overwrite each other, because Dart appends by seeking to the end rather than with `O_APPEND`. 568 unstamped lines after 20:27, mostly at the install boundary.

**F15 · Events 11/12 are unnamed in the protocol package.** Owner: protocol repository.
They show as `EVENT_11`/`EVENT_12`. `research/decode_events.py` names them BLE_CONNECTION_UP/DOWN. These events are the single most useful outage record, so they deserve a verified name.

## Detection and reporting today

| Question | Answer |
| --- | --- |
| Connected band goes silent | Keep-alive command about once a minute (band console "Command Link Valid"). `isLinkStale` (30 s with live stream, 90 s without) is evaluated on resume and foreground catch-up only. A dead link otherwise ends with the OS supervision timeout (seconds). |
| Link lost, app in foreground | "Verbindet …" during the attempt, then "Band nicht erreichbar · Letzter Versuch HH:MM" after the first failed 20 s attempt (PR #17). |
| Link lost, app in background | Nothing visible. In-app quiet tier after 12 h without a record; OS notification after 48 h (F8). |
| Does reconnect give up? | No, except the bond-refusal pause. The iOS restore central stays armed until a wake is acknowledged; after F1 an acknowledged wake has either handed the link over or timed out. |
| Backoff too far? | No: cap 30 s. On iOS the effective rate in the background is set by process suspension, not by the policy. |
| Battery | Foreground: a connect attempt about every 40–56 s while unreachable. Background: one short CPU wake per iOS wake, plus the free pending connect. No new cost from this branch; F1 keeps the process up to 40 s longer on a restore wake that lands during the reconnect loop. |

## Decisions for Mats

- **D1 · Silent-band notification.** Proposed: one notification after 3 h without a stored record while the band was last seen on the wrist, repeated at most every 12 h, going through `NotificationCenter.emit`, and no notification during quiet hours. Today it is 48 h. User-visible behaviour, so not built.
- **D2 · Unreachable copy.** Replace "Bluetooth aus/ein … Ladegerät" with "Doppeltippe auf das Band. Hilft das nicht, leg es kurz aufs Ladegerät." It rests on one observed recovery. Recommended, because the current advice demonstrably did not help. Needs the code-quality owner.
- **D3 · iOS reconnect.** Proposed: while backgrounded, drop the Dart 20 s cycle and rely on one no-timeout pending connect. That means fewer wakes and the same radio cost, but it changes reconnect behaviour, so it needs a device trial first.
- **D4 · Evidence next time.** When the band is unreachable: note the time, then double-tap it. Before and after the tap, scan with nRF Connect on a second device. Leave the app running so the backlog brings the band console along.

## Still unproven

- Why the band did not become connectable after 23:54 (H4 vs H5), and what caused the 0x08 drop.
- F1/F2 are proven on the unit surface and by code reading. That the 13:18 drop was exactly this race rests on the band's 0x13 and the lease timing; the lossy 0.9.33 log and the missing native log cannot confirm it.
- Whether a double tap reliably restores a stuck band (n = 1).
