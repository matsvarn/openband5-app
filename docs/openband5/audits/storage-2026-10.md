# Storage and efficiency audit, October 2026

Scope: `edge` at `61dcdd29` (branch `openband5/g31-paper`), schema 68, algorithm 98. Evidence is a copy of the phone database pulled on 30 September 2026 after the 0.9.34 install (335,822,848 bytes, 1,149,981 decoded seconds, 12,078 raw batches, 16 local days from 15 to 30 September) and `growth_log.csv` from the lab folder. This report contains counts, sizes, timings and query plans only.

Line references point at `61dcdd29` unless marked otherwise.

## Summary

- **Size.** The phone database copy shrinks from 335.8 MB to 256.7 MB (−79.1 MB, −23.6 %) after the one-off steps, with every decoded second, beat, raw batch and current result retained and bit-identical. Growth falls from 20.1 to 17.7 MB a day, and derived data stops growing with days × algorithm bumps.
- **Projection.** One year: 8.5–10.7 GB before, 6.8 GB after. Three years: 28–47 GB before, 19.9 GB after. The remaining growth is source data; the largest further lever (keeping only recent days decoded, re-decoding older days from `raw_blob`) is a decision below and would reach about 2.9 GB a year.
- **Time.** On a copy of the phone database, on the Mac: start-up DB work before `initialized` 0.7–2.6 s → 0.05–0.3 s; the post-sync freshness refresh 86–508 ms → 17–24 ms; one forced day 6–18 s → 4.8–6.2 s; the full integrity check (2–13 s, on every launch) now runs at most weekly, with a daily `quick_check` and a 7 ms cached answer otherwise. The post-sync light derive (about 8 s on the Mac) and the full re-derivation (about 37 s) did not measurably change.
- **Proof.** The migrated copy passes `integrity_check`, `verify_capture.py` (CLEAN) and `replay_check.dart` (exit 0, 605,732/605,732 seconds matched); re-derivation reproduces every day's result of the old code except the recorded schema number.

## Method

- Sizes: SQLite `dbstat` on a writable copy (`sqlite3` 3.54.0). Table sizes include interior pages. Index sizes are listed separately and added to their table in the growth table.
- Growth per day: rows whose record time falls in the seven complete local days from 23 to 29 September, divided by seven, multiplied by the table's measured bytes per row (table plus its indexes). The growth log gives an independent file-level rate: 177.8 MB on 23 September 08:19 to 335.7 MB on 30 September 22:48, which is 20.8 MB per day including two algorithm bumps.
- Time: `tool/storage_bench_test.dart` under `flutter test` on the macOS host (sqflite FFI), each operation on a fresh copy, three repeats, Stopwatch wall clock, SQL trace through `sqflite_common`'s logger with `EXPLAIN QUERY PLAN` for the top statements. Individual queries were also timed with the `sqlite3` CLI (`.timer on`). The OS page cache was warm after the first repeat and was not flushed. These are Mac timings; the phone was not used.
- Prototypes of each size reduction ran on separate copies and were measured with `dbstat` before and after `VACUUM`.

## Where the bytes are

| Object | Bytes | Rows | Purpose |
|---|---:|---:|---|
| `decoded_onehz` | 145,412,096 | 1,149,981 | Derivation input (1 Hz substrate), sample facade, workout HR, Health export |
| `idx_decoded_onehz_rects` (rec_ts, counter) | 23,662,592 | | Every time-range read; derivation paging |
| PK autoindex (device_id, ts_ms) | 21,016,576 | | REPLACE key, boundary guards |
| `raw_blob` | 37,675,008 | 12,078 | Retained raw source; `replay_check`, `verify_capture`, schema-68 recovery |
| `decoded_rr` + PK + `idx_decoded_rr_rects` | 25,108,480 + 10,940,416 + 8,990,720 | 562,767 | Beat intervals for derivation and the night-beats screen |
| `sleep_session_candidates` | 15,097,856 | 84 | Derivation cache: sleep candidate per day and algorithm version |
| `samples` + PK + `idx_samples_ts` | 5,971,968 + 3,993,600 + 3,248,128 | 219,981 | Legacy dual-write; fallback only when the decoded range is empty |
| `raw_archive` + PK + `idx_raw_archive_captured` | 7,995,392 + 6,885,376 + 1,052,672 | 37,306 | Undecodable/identified records kept as hex for later redrive |
| `day_result` | 8,175,616 | 146 | Served day bundles; all versions 87–98 kept |
| `sync_ledger` + PK | 3,342,336 + 815,104 | 23,813 | Sync diagnostics; `verify_capture` ACK ordering |
| `band_events`, `events` (with indexes) | 2,260,992, 1,519,616 | 11,189, 11,168 | Wear/charge transitions for naps; event list |
| `wake_day_features` | 745,472 | 129 | Derivation cache: waking features per day and version |
| Everything else | < 1.2 MB | | |

`PRAGMA page_size` 4096, `page_count` 81,988, `freelist_count` 0, `auto_vacuum` 0 (none), `journal_mode` wal, `user_version` 68. The pulled `-wal` file was empty.

### Growth per day (23–29 September)

| Table (with indexes) | Bytes per row | Rows per day | MB per day |
|---|---:|---:|---:|
| `decoded_onehz` | 165 | 69,805 | 11.54 |
| `raw_blob` | 3,163 | 1,413 | 4.47 |
| `decoded_rr` | 80 | 31,852 | 2.55 |
| `raw_archive` | 427 | 2,269 | 0.97 |
| `sync_ledger` | 175 | 1,469 | 0.26 |
| `band_events`, `events`, `band_battery`, `band_backlog`, `device_coverage` | | | 0.29 |
| **Source and ledger total** | | | **20.08** |

Derived storage grows differently. Every algorithm bump re-derives every stored day and keeps the old rows next to the new ones. At algorithm 98 one day costs 179 KB of sleep candidate, 89 KB of `day_result` and 8 KB of wake features: 276 KB per day and version. The database held 12 versions (87–98); 12.3 MB of `sleep_session_candidates` and 6.7 MB of `day_result` belonged to superseded versions. This part grows with days × bumps, not with days.

### Duplicated, dead and oversized storage

- **`raw_blob` pages are half empty.** 9,176 leaf pages hold 12,078 batches of about 2.1 KB each. Two batches do not fit in a 4 KB page, so 12,153,947 bytes (32 % of the table) are unused space inside pages. The payload itself compresses 2.78×. Measured alternatives: gzip level 9 per batch saves 3 %, hourly regrouping saves 9 %, xz saves 32 %.
- **`raw_blob` versus `decoded_onehz`.** Since 22 September every decoded second is also in `raw_blob` (`verify_capture`: 0 of 605,732 blob records missing from `decoded_onehz`; `replay_check`: 0 HR, skin temperature and step mismatches). The decoded rows are therefore a rebuildable cache of `raw_blob` for those days, at 14.1 MB per day against 4.5 MB per day of raw. Before 22 September `decoded_onehz` is the only source.
- **`samples` duplicates `decoded_onehz`.** All 219,981 rows have a `decoded_onehz` row at the same (device_id, ts_ms); 219,857 carry the same HR, 124 differ (the old IGNORE/REPLACE drift), 120 decoded twins have a null HR. The writer stopped on 18 September (`db.dart:5780` now writes `samples` only for records that cannot become 1 Hz rows). `samplesInRange` reads `samples` only when the decoded query returns nothing, so no duplicated second can ever be served from it. 13.2 MB, no growth.
- **`decoded_onehz` stores six exact decimals as 8-byte reals.** `ax`, `ay`, `az`, `temp_ch2_c`, `temp_ch3_c`, `dyn_accel_g` (and also `skin_temp_c`, `signal_quality_logvar`) hold values that are exactly `k / 10000` for every one of the 1,149,981 rows (`x = CAST(ROUND(x*10000) AS INTEGER)/10000.0` holds everywhere). `device_id` is `''` and `source` is null on every row; `device_family` is `'gen5'` on every row.
- **`decoded_rr.rr_ts_ms` equals `ts_ms`** on all 562,767 rows (6 bytes per beat).
- **`raw_archive` stores bytes as hex text** and its PK `(device_id, hex)` copies the whole hex string into the autoindex: 427 bytes per 76-byte record.
- **Unused indexes.** No query has a `first_ts` bound on `raw_blob`, so `idx_raw_blob_ts` (`db.dart:8005`) only duplicates the PK's device prefix. No reader orders or filters `raw_archive` by `captured_at` (`idx_raw_archive_captured`, `db.dart:9186`). `idx_day_result_day` (`db.dart:6089`) is identical to the `day_result` PK. Together 1.2 MB, about 0.1 MB per day.
- **`sleep_session_candidates.hypno_stages`** is one string per second of the sleep search window (about 34,000 strings, 179 KB per row). A lossless run-length form of the same list is 1.3 KB (measured over the 15 algorithm-98 rows).
- **No dead tables** among the large ones. `raw_records` is empty (dormant legacy ledger, recreated empty by the open repair). `dataHistoryDays` (`db.dart:10878`, an 827 ms full scan) has no production caller.

### Free pages, WAL and vacuum

- `auto_vacuum` is off and `freelist_count` is 0, so deleted rows become reusable pages and the file never shrinks. `vacuumIfBloated` (`db.dart:15944`) runs a full `VACUUM` once a launch after a foreground heavy derive when at least 64 MiB are free; no prune currently frees that much.
- A full `VACUUM` of the copy took 3.7 s and saved 11.3 MB (fragmentation). With 8 KB or 16 KB pages it saved 22.7 MB and 22.9 MB, mostly `raw_blob` slack, but changing the page size requires leaving WAL mode for the duration.
- WAL: no `wal_autocheckpoint` (default 1,000 pages) and no `journal_size_limit`, so the `-wal` file stays at its largest size until the connection closes. The harness saw 4.1 MB after a full re-derive or 50 batch commits. A `VACUUM` in WAL mode writes the whole database into the WAL.
- Sync commits run with `synchronous=FULL` (`db.dart:5691`) and everything else with `NORMAL`. That is correct for commit-before-ACK and is not changed.

## Time

All numbers are from the harness on the Mac (`bench-results` 30 September 21:31 UTC) unless marked CLI. The harness run overlapped other Flutter test runs, so absolute numbers carry contention; the before/after comparison below was repeated in a quiet state.

| Operation | Median | Max | Notes |
|---|---:|---:|---|
| `LocalDb.instance` open (schema 68, no migration) | 73 ms | 76 ms | |
| Start-up DB sequence before `initialized = true` | 272 ms | 2,786 ms | 92 % of it is `refreshComputeFreshness` |
| AppState + repositories to rendered Heute | 159 ms | 417 ms | Heute reads are cheap: `readDay` 65 ms, all others under 40 ms |
| Deferred start-up `schemaHealth` | 13,386 ms | 13,415 ms | Full `PRAGMA integrity_check`, holds the only connection |
| Derive one day (forced) | 15,942 ms | 18,927 ms | |
| Full re-derivation, 16 days | 49,463 ms | 54,078 ms | |
| Post-sync light derive | 14,060 ms | 14,532 ms | Runs after every drain |
| Post-sync `refreshComputeFreshness` | 644 ms | 998 ms | |
| `commitSyncBatch` (50 real batches) | 25 ms | 2,236 ms | The outlier is a WAL checkpoint inside `COMMIT` |

Heaviest statements (summed over the harness run):

| Statement | Calls | Total | Max | Plan and cause |
|---|---:|---:|---:|---|
| `SELECT MIN(rec_ts), MAX(rec_ts) FROM decoded_onehz WHERE rec_ts > ? AND source IS NULL` (`firstAndLastRecordTs`, `db.dart:10139`) | 9 | 64,481 ms | 11,611 ms | `SEARCH … USING INDEX idx_decoded_onehz_rects (rec_ts>?)`. `source` is not in the index and a combined MIN+MAX cannot use SQLite's min/max shortcut, so every one of the 1.15 M table rows is fetched. CLI: 1,558 ms; the same values through two `ORDER BY rec_ts … LIMIT 1` lookups: 0.06 ms. Called on every derive through `decodedRecTsMaxByDay`. |
| Derivation page load `SELECT … FROM decoded_onehz WHERE rec_ts BETWEEN … ORDER BY rec_ts, counter LIMIT 2000` | 5,586 | 38,657 ms | | Index range, 7 ms per 2,000-row page. A one-day derive reads 200,539 rows for an 88,000-second day because three overlapping windows are loaded separately. |
| `PRAGMA integrity_check` | 3 | 28,685 ms | 13,404 ms | CLI: `integrity_check` 1,185 ms warm, `quick_check` 427 ms warm (2,659 ms cold). |
| `decoded_rr` range read | 5,766 | 12,845 ms | 151 ms | Index range. |
| `INSERT OR REPLACE INTO sleep_session_candidates` / `SELECT *` | 45 / 48 | 6,758 / 3,404 ms | 2,573 / 1,901 ms | 179 KB JSON per row. |
| `SELECT COUNT(*) FROM decoded_rr` / `samples` / `decoded_onehz` | 6 / 6 / 12 | 3,356 / 1,026 / 150 ms | 1,788 / 646 / 132 ms | Full covering-index scans from `rawStats()` inside `refreshComputeFreshness`. CLI: first `COUNT(*)` on `decoded_onehz` 579 ms. The counts are written to the `capture` freshness row and never read. |
| `band_events` state lookup `WHERE device_id = ? AND ts < ? AND event_id IN (…) ORDER BY ts DESC LIMIT ?` | 108 | 2,326 ms | 403 ms | PK search by device, then `USE TEMP B-TREE FOR ORDER BY`. |

### Before and after

Old code on the unmodified copy, new code on the migrated and compacted copy, alternated twice (A B A B), plus one quieter old-code run. Other Flutter jobs from parallel work ran on the same Mac during all runs, so ranges are shown.

| Operation | Old code | New code |
|---|---:|---:|
| Start-up DB sequence (median per run) | 0.28 / 0.94 / 2.58 s | 0.05 / 0.31 s |
| `refreshComputeFreshness` at start-up | 258 / 715 / 2,343 ms | 17 / 189 ms |
| `refreshComputeFreshness` after a sync | 83 / 86 / 508 ms | 18 / 25 ms |
| AppState + repositories to rendered Heute | 132 / 136 / 140 ms | 123 / 158 ms |
| Derive one day (forced) | 6.1 / 16.1 / 18.1 s | 4.8 / 6.2 s |
| Post-sync light derive | 7.3 / 8.1 / 15.2 s | 8.1 / 9.0 s |
| Full re-derivation, 16 days | 36.6 / 37.5 / 50.2 s | 36.7 / 49.0 s |
| `schemaHealth` on a fresh copy (first check is always the full one) | 2.0 / 8.1 / 10.1 s | 2.3 / 11.6 s |
| `schemaHealth` on a later launch the same day | same as above | 6.8 ms (cached; measured by the implementation's timing test) |
| `commitSyncBatch` median | 4.5 / 4.8 / 25.7 ms | 8.1 / 11.7 ms |
| Span query `firstAndLastRecordTs` | 1,483 ms | 0.6 ms (same process, same copy) |

Per-drain battery cost is therefore dominated by the light derive itself: 4.3–4.7 s of it is SQL time reading 199,424 decoded rows (2.3× the day, from three overlapping windows); the rest is the isolate computation. See the decision on derivation reads.

Background drain cost per batch: the ACK-gating `commitSyncBatch` itself is 25 ms median. The expensive part is what follows each drain: a light derive (14 s on the Mac, most of it the span query above) and `refreshComputeFreshness` (0.6 s).

## Findings

No P0 (data-loss or invariant) defect was found in the storage layer.

| Rank | Finding | Evidence | Where |
|---|---|---|---|
| P1 | Derive span query fetches every decoded row on every derive | 11.6 s max, 64.5 s over 9 calls; 1.56 s CLI; 0.06 ms rewritten | `db.dart:10139` |
| P1 | Superseded derivation caches are never pruned: the pruning call sits behind OpenBand's keep-all-source early return | 12 versions per day kept; 12.3 MB of candidates and 0.6 MB of wake features superseded | `derivation_engine.dart:5746`, `:5761` |
| P1 | Superseded `day_result` versions are kept forever; together with the caches, derived storage grows with days × bumps | 276 KB per day and version; 6.7 MB superseded now; 2.9 GB after one year at one bump a week | `db.dart:10520` (writer); no pruning exists |
| P1 | `refreshComputeFreshness` runs three full-index `COUNT(*)` scans and a combined MIN/MAX on start-up and after every derive, for counts nobody reads | 231–2,601 ms at start-up, 535–998 ms after each drain | `db.dart:13809`, `:12955` |
| P1 | `schemaHealth` runs a full `integrity_check` on every launch (the 24 h guard is in memory) and blocks the connection | 1.9–13.4 s per launch | `db.dart:13239`; caller `app_state.dart:2749`, `:3144` |
| P1 | Six REAL columns store exact 4-decimal values in 8 bytes | 145.4 → 106.5 MB table after re-encoding and `VACUUM`; −2.4 MB per day | `db.dart:8513` writer |
| P2 | Sleep candidates store one string per second | 179 KB → 1.3 KB per row; the 2.6 s write and 1.9 s read | `derive_prepare.dart:203`, `db.dart:14251` |
| P2 | Legacy `samples` duplicates `decoded_onehz` | 13.2 MB, 0 rows served | `db.dart:10080` fallback |
| P2 | WAL file never truncated | 4.1 MB after routine work; a `VACUUM` fills it to the database size | `db.dart:590` |
| P2 | `band_events` state lookups sort in a temp b-tree | 2.3 s per full re-derive | `db.dart:5393`, `:5401` |
| P2 | `raw_blob` page slack | 12.2 MB now, 32 % of each day's raw growth | 4 KB page size |
| P3 | Three unused indexes | 1.2 MB, 0.1 MB per day | `db.dart:8005`, `:9186`, `:6089` |
| P3 | `raw_archive` hex text and hex primary key | 427 B per 76-byte record, 1 MB per day | `db.dart:9174` |
| P3 | `decoded_rr.rr_ts_ms` duplicates `ts_ms` | 3.4 MB now | |
| P3 | Redundant derivation reads: three overlapping windows per day | 200,539 rows read for one 88,000-second day | `derivation_engine.dart:2805`, `:2852`, `:2863` |
| P3 | `dataHistoryDays` full scan has no production caller | 827 ms CLI | `db.dart:10878` |

## What the P0 rules allow

| Reduction | Invariant touched | Why it still holds |
|---|---|---|
| Re-encode six `decoded_onehz` columns as exact scaled integers with a per-row `onehz_enc` flag | Raw source retained (§3.9); REPLACE on the record second (§3.2); migrations cheap (§3.11) | The stored value is exactly recoverable (the writer and the background conversion only encode a row when every value round-trips; the read path divides in SQL, which is the same IEEE division). Rows keep their key and REPLACE semantics. The schema change is one `ADD COLUMN` (10 ms on the copy); the rewrite runs outside the migration in bounded, resumable transactions. `verify_capture.py` and `replay_check.dart` do not read the six columns. |
| Prune superseded `sleep_session_candidates`, `wake_day_features` (keep 2 newest per day) | Idempotent derivation (§4.2) | Current-version readers use the exact current version; the newest-version freshness read keeps its row. Versions above this build's algorithm are never touched. |
| Prune superseded `day_result` (keep 2 newest ≤ current, the newest complete one, and any newer build's rows) | Versioned immutable results (§3.4) | Served reads take the greatest version ≤ `kAlgoVersion`; derivation fallbacks read the previous real output; both are kept. Source data is untouched, so any current result can be recomputed. |
| Delete `samples` rows that have a primary-source `decoded_onehz` twin | Raw source retained | The fallback reader never serves a second that has a decoded row; rows without a twin stay. |
| Run-length encode stored sleep stages | Idempotent derivation | Lossless; the in-memory list is identical, so derivation output is unchanged. An older build fails loudly on the new form instead of misreading it. |
| One `VACUUM` after the re-encoding, then `wal_checkpoint(TRUNCATE)` | Commit before ACK (§3.1) | Same gate as today: foreground, after a heavy derive, no live session, once per launch. `VACUUM` is atomic; a kill mid-way leaves the old file. |
| Not built: regroup or recompress `raw_blob` | Raw source retained; verify tools key on batches | Would change batch keys and lose per-commit evidence. |
| Not built: drop decoded rows that `raw_blob` can rebuild | Raw source retained; invariant 9 | Changes the derivation input path; see decisions. |

`tool/verify_capture.py` reads `decoded_onehz.rec_ts`, `counter`, `device_family`, `signal_quality_logvar`, `raw_blob` and `sync_ledger`; `tool/replay_check.dart` reads `raw_blob` and `decoded_onehz` HR, skin temperature and steps. None of those columns change representation.

## Implemented in this branch

| Commit | Change | Finding |
|---|---|---|
| `fc7527b5` | `pruneSupersededIntermediates` moves into `_runStorageHousekeeping` (every derive, errors swallowed); new `pruneSupersededDayResults` keeps the 2 newest versions ≤ `kAlgoVersion`, the newest complete one, and every newer build's rows | P1 superseded caches and results |
| `be02d59b` | `refreshComputeFreshness` reads one `MAX(rec_ts)`; the unread counts are no longer written | P1 freshness |
| `10e128ef` | Schema 69: `decoded_onehz.onehz_enc`. The canonical writer stores the six columns as exact scaled integers when every value round-trips; `decodedOneHzProjection` decodes them in the substrate read; `compactLegacyOneHz` converts history in 2,000-row transactions within a 1 s budget per derive, with a rowid cursor committed in the same transaction; when done it requests one `VACUUM`; `vacuumIfBloated` honours the request and truncates the WAL; `journal_size_limit` 16 MB | P1 encoding, P2 WAL |
| `125e55db`, `92f41611` | `pruneDuplicateSamples` deletes `samples` rows with a primary-source decoded twin, in bounded batches; it keeps rescanning because an import of an old backup can bring new twins | P2 samples |
| `cb2fdda5` | Sleep candidates store `hypno_stages` as `rle1:` run lengths; legacy lists still parse; an older build rejects the string instead of misreading it | P2 candidates |
| `bd54410b` | Span queries (`firstAndLastRecordTs`, `rawStats`, `dataHistoryDays`) use two index-ordered `LIMIT 1` seeks in one statement | P1 span query |
| `e4b5f5a5` | `schemaHealth` persists its verdict: `quick_check` at most daily, full `integrity_check` at most weekly across launches; a failed full check is only cleared by a later full success | P1 integrity check |
| `c3df760e` | `idx_band_events_device_ts (device_id, ts)`; both state lookups now avoid the temp b-tree | P2 band events |
| `f1185cd0` | Drops `idx_day_result_day` and `idx_raw_blob_ts` and removes them from the creators. `idx_raw_archive_captured` stays: the (disabled) archive thinning filters on `captured_at` | P3 indexes |
| `10bee5ae` | Full exports (`exportCopy`, used by manual export, auto backup and the health uploader) and selected-day exports decode the six columns back to physical units in one transaction on the destination and delete the file on failure, so an older build importing them reads correct values. Measured on the compacted copy: export 2.25 s, of which 1.27 s is the decode | Review round 1 |
| `f07f26b1` | A successful `VACUUM` restarts unfinished rowid walks (`onehz_compact`, `samples_deduplicate`), because `VACUUM` may renumber rowids | Review round 1 |
| `1e434e68`, `90377ca3`, `19043622` | Migration timing, interrupted-batch rollback, WAL reclamation and real-copy timing tests | |
| `192be73b`, `f3c74ea9` | `tool/storage_bench_test.dart` (timings) and `tool/storage_proof_test.dart` (proof on a copy) | |

`kAlgoVersion` stays 98. Derivation reads identical values, so no result changes (see the proof below). The schema number moves to 69, which the build-provenance block records.

Rollback: sqflite has no downgrade handler here, so a build older than this one would open a migrated database and read the six scaled columns without dividing. Roll back by restoring the pre-install backup, as the install procedure already does, never by installing an older build over a migrated database.

## Decisions for Mats

None of these is built. Each rewrites or drops retained source, or changes the derivation input path.

| Proposal | Saving | Cost and risk | Invariant |
|---|---|---|---|
| **Keep decoded rows only for recent days where `raw_blob` exists; re-decode older days from `raw_blob` when a derivation needs them** | After this branch `decoded_onehz` + `decoded_rr` cost 11.7 MB a day against 4.5 MB of `raw_blob`. Projection: 6.8 → 2.9 GB after one year, 19.9 → 7.4 GB after three (30 days kept decoded) | A second substrate source for derivation. `replay_check` proves HR, skin temperature and steps only; every column the derivation reads needs the same proof. An algorithm bump re-decodes every old day (about 70,000 frames per stored day). Days before 22 September have no raw and stay decoded | Raw source retained (holds: `raw_blob` is the source); §3.9 prune only fully derived days; §3.8 one decode point (`decodeSubstrate` is already it) |
| Store `raw_archive` bytes as BLOB with a hash key instead of hex text with a hex key | Estimated 0.7 MB a day (427 B per record today; a 76-byte BLOB plus a hash key is estimated at about 130 B, not measured) | Rewrites retained source rows; redrive and restore paths change | Raw source retained |
| Larger page size (8 or 16 KB) through a one-off `VACUUM` outside WAL mode | 22.7–22.9 MB now; ends the 32 % slack of each day's `raw_blob` (about 1.4 MB a day) | The phone must switch journal mode for the length of the rewrite; needs twice the file size free | None directly; commit-before-ACK waits for the rewrite |
| Regroup `raw_blob` batches (hourly) and/or a stronger codec | 9 % (gzip, hourly) to 32 % (xz) of the payload, plus the page slack | Batch keys and per-commit capture times disappear; `verify_capture.py` and the retention check key on them; xz needs a native codec | Raw source retained; commit-before-ACK evidence |
| Scale `skin_temp_c` and `signal_quality_logvar` too | About 0.8 MB a day | `lib/openband/local_repository.dart:599` and `tool/verify_capture.py` read them in SQL; needs the code-quality owner | None |
| Drop `decoded_rr.rr_ts_ms` (equal to `ts_ms` on every row) | 3.4 MB now, about 0.2 MB a day | Readers switch columns; table rebuild | §3.2 cascade unchanged |
| Load one window per day in derivation instead of three overlapping ones | Up to about half of the derivation read time (200,539 rows read for an 88,000-second day) | Touches the derivation input assembly; output must stay identical | Idempotent derivation |

## Projection

Assumptions: 69,805 decoded seconds a day (measured wear), 20.08 MB a day of source and ledger, 276 KB per day and algorithm version of derived data before this change; after it, 17.72 MB a day of source and ledger and 98 KB per day and version with at most two versions kept. Bump rate is an assumption: once a week or once a month (the last two weeks saw eleven).

| Scenario | 1 year, weekly bumps | 1 year, monthly bumps | 3 years, weekly | 3 years, monthly |
|---|---:|---:|---:|---:|
| As at `61dcdd29` | 10.7 GB | 8.5 GB | 47.0 GB | 28.4 GB |
| Version pruning only (2 kept) | 7.8 GB | 7.8 GB | 22.9 GB | 22.9 GB |
| + run-length sleep stages | 7.7 GB | 7.7 GB | 22.5 GB | 22.5 GB |
| + six-column encoding, `samples` cleanup, `VACUUM` (this branch) | 6.8 GB | 6.8 GB | 19.9 GB | 19.9 GB |
| + decision: decoded rows kept for 30 days, older days from `raw_blob` | 2.9 GB | 2.9 GB | 7.4 GB | 7.4 GB |

Formula: start size + source growth × days + derived versions. Without pruning each bump adds 276 KB × the days stored at that moment, so the derived part grows quadratically; with pruning it is at most two versions per day. The last row keeps 30 days of decoded rows (11.7 MB a day) and 4.5 MB a day of `raw_blob` plus 1.5 MB a day of other tables for older days. `raw_blob` page slack (about 1.4 MB a day) is included in every row.

## Proof on a copy of the phone database

`tool/storage_proof_test.dart` on a fresh copy of the phone database, with this branch at `19043622` (results: private lab note, not committed):

| Check | Result |
|---|---|
| Migration 68 → 69 through `LocalDb` | 311 ms (160 ms in a separate timing test); `user_version` 69; schema equals a fresh install |
| One-off steps | `compactLegacyOneHz` 7 calls, 1.50 s, max 299 ms per call, 1,149,981 rows; `pruneDuplicateSamples` 110 calls, 0.30 s, 219,981 rows; `pruneSupersededIntermediates` 6 ms, 123 rows; `pruneSupersededDayResults` 2 ms, 65 rows; `VACUUM` 985 ms, 29.8 MB freelist |
| Size | 335,822,848 → 256,716,800 bytes; `decoded_onehz` 145.4 → 106.2 MB; `sleep_session_candidates` 15.1 → 4.9 MB (2.3 MB after re-deriving 98 in run-length form); `day_result` 8.2 → 2.5 MB; `samples` 13.2 MB → 0 |
| Interrupted conversion (close after 3 passes, reopen, finish) | same end state, 0 value mismatches |
| `integrity_check` | ok |
| `decoded_onehz` keys / `decoded_rr` keys / `raw_blob` keys | 0 missing, 0 extra each |
| `raw_blob` columns including payload bytes | 0 mismatches |
| `decoded_onehz` values through the production read (27 columns) | 0 mismatches |
| `decoded_rr` values (9 columns) | 0 mismatches |
| `day_result` algorithm 98 (all 12 columns) | 0 mismatches, 0 missing |
| `day_result` pruned keys | 65 rows of versions 87–96, all allowed by the policy; 0 unauthorised |
| Sleep candidates / wake features pruned keys | 58 / 65 rows, all allowed; algorithm-98 rows present |
| Re-derivation of all 16 days on the new code | Every day differs from the old code's re-derivation only in `build.schema_version` (68 → 69); with that field restored, all 16 old hashes reproduce exactly. New code on the compacted copy equals new code on an unmodified copy byte for byte |
| `tool/verify_capture.py` | CLEAN: 1,149,981 rows, 0 duplicate seconds, 0 of 605,732 blob records missing, 0 ledger violations since the fix boundary |
| `tool/replay_check.dart` | exit 0: 605,732/605,732 seconds matched, 0 HR, skin-temperature and step mismatches |

The comparison with the unmodified original uses a separate read-only copy; the original under OpenBand5Lab was never opened.

## Findings for other owners

- Code quality (`lib/state/app_state.dart:3144`): `_lastSchemaHealthCheckAt` is in memory, so the 24 h throttle resets on every launch. This branch moves the throttle into `LocalDb.schemaHealth`; the in-memory guard can go.
- Code quality: `dataHistoryDays` (`app_state.dart:2602` → `db.dart:10878`) has no production caller and costs 827 ms when called.
- Reliability (`lib/ble/**`): `raw_blob` batch size follows the sync commit, about 2.1 KB compressed. Two of them do not fit a 4 KB page. Combining two consecutive commits into one blob is not possible without delaying the ACK, so the slack stays unless the page size changes.
- Code quality (`lib/openband/local_repository.dart:599`): the optical-coverage query reads `signal_quality_logvar` from every row of a day (9 ms per day on the copy). Fine today; it scales with days shown.

## Follow-up: one calculation per day screen, and idempotent derivation

Branch `openband5/audit-storage-2` on top of `b9affc44`. Source: code-quality audit DUP-1/DUP-2 (decision 2 on PR #21) and test-suite audit (#19).

### Reproduced

`test/day_consistency_test.dart` (commit `64ae055a`) failed 5 of 8 tests on `b9affc44`:

| Case | Reproduction | Observed |
|---|---|---|
| DUP-1 | A new calculation commits after `readDay`'s snapshot transaction (`lib/openband/local_repository.dart:1258`) and before its later reads `getDaySleep/Heart/Strain/Steps` (`:1398–1408`, each re-selecting the served row through `LocalRepositoryImpl._bundle`, `lib/data/local_repository_impl.dart:100`) | One `OpenBandDay` with duration, onset/wake, recovery, strain, steps and source from calculation B, but segments, HRV, RHR, respiration, temperature and `calculatedAt` from calculation A |
| DUP-2, partial row | Served row is partial; `putDayResult` writes `metric_series` only for complete rows | Headline 420 min / 80 / 9 / 9,000 steps, history and trend 360 / 60 / 4 / 3,000 |
| DUP-2, newer build | `metric_series` written with a row above `kAlgoVersion` | Headline from the served row, history from the newer build |
| DUP-2, series-only writes | A `metric_series` value without a matching `day_result` (import, direct write) | Strain history 12 against headline 4; sleep history and week strip 500 against headline 360 |

Trend readers read unversioned `metric_series`: `readMetricHistory` (`:2617–2642`), `_g3Steps` (`:368–377`), `readDay`'s `tst_min` history (`:1423`), and through them `readTrend`, `readWeekStrip`, `readWeeklyLoad` and the sleep-latency pattern (`:2204`).

### Fixed

- `627280d4`: `readDay` builds every calculation-backed field from its one snapshot transaction, through pure formatters extracted from `getDaySleep/Heart/Strain/Steps` (output formatting unchanged; the public methods remain thin wrappers). History, trend, week-strip and weekly-load points come from `LocalDb.servedDaySeries`, the same served row as the headline (greatest version ≤ `kAlgoVersion`, partial rows included as today, skipped rows a gap). Derivation keeps reading `metric_series`, so its output is unchanged. On the migrated copy of the phone database the served projection equals `metric_series` for all 9 keys on all 16 days (0 differences), so no trend value changes on current data.
- `627280d4`, `bbfe002c`: separate reader calls on one screen use the calculation `readDay` saw for that day (a per-day pin of algorithm version and `computed_at`). If that row has been replaced, the reader returns processing or a gap, never the newer value. Readers wait for an in-flight `readDay` of the same day, because `OpenBandDayController.refresh` notifies listeners before it reads; without that wait Heute's week strips stayed empty after every sync (reproduced: expected 420, got null).
- 365 days of served points: 9.3–9.9 ms on the Mac (synthetic 80 KB payloads).

Remaining edge: Verlauf's detail loader reads the trend before its own `readDay` (`lib/openband/g3/screens/verlauf.dart:230–236`). A day pinned earlier and replaced since can show a gap there, not a mix, until the next refresh. Reordering those two calls is a screen change for the code-quality owner.

### Idempotent derivation

`test/derive_idempotence_test.dart` (CI) runs the production derivation twice on a synthetic three-day fixture with 28 baseline days (readiness, sleep, strain and HRV all non-null) and compares 69 tables. Excluded fields: execution clocks (`computed_at`, `updated_at`, `created_at`, `fired_at`, cross-day `built_at_epoch` / `input_read_started_at_ms`) and the cross-day publication fence (`crossday_source_rev.v`, `source_rev`), which `putDayResult` increments on every write and whose documentation calls it orchestration eligibility, not analytics output (`lib/data/db.dart:14269`). `tool/derive_idempotence_test.dart` does the same on a copy of the 30 September database (local only).

| Comparison | Result |
|---|---|
| Real copy, full pass twice (16 days) and light pass twice | 69 tables, 0 differing rows (155 s) |
| Synthetic, light rerun after a full pass | 0 differing rows |
| Synthetic, first against second full pass | **Differs**: readiness, strain, skin-temperature z (and their baselines, curves, wake features) for the two later days |
| Synthetic, second against third full pass | **Differs**: Erholung baseline of the last day |

Cause: `DerivationEngine.run` loads `_BaselineHistoryCache` once per pass (`lib/compute/derivation_engine.dart:2483`) and derives the to-do days in up to three parallel lanes. A day derived in a pass never sees the outputs of days derived earlier in the same pass; the next pass does. Already-derived histories (the phone today) are stable, but after an algorithm bump a re-derived day's baselines are built from the previous version's values for the days before it, and a fresh multi-day history needs several passes to settle. Both full-pass tests stay as strict assertions, skipped with that reason, until the decision below.

### Decisions for Mats (follow-up)

| Decision | Options | Cost |
|---|---|---|
| Baseline history inside one derivation pass | (a) derive the to-do days in date order and refresh the baseline cache after each day; (b) repeat the pass until no output changes | Either changes derivation output for multi-day passes, so it needs a `kAlgoVersion` bump and a re-derivation. (a) loses the three-lane parallelism of a full re-derivation (measured 37 s for 16 days on the Mac with parallelism); (b) multiplies its run time by the number of passes |
| 30-day decoded window | Kept for later, as agreed: a few more weeks of measured growth on the schema-69 layout first | — |

## Not proven

- No iPhone measurement: all timings are macOS FFI on a warm page cache, with unrelated Flutter jobs on the same machine. Phone timings, battery drain and thermal behaviour are not measured.
- The one-off conversion and `VACUUM` have not run on the phone. On the Mac they took 1.5 s and 1.0 s; the phone is slower and the `VACUUM` needs roughly the file size free.
- Growth after this branch (17.7 MB a day) is computed from measured bytes per row, not observed over days on the phone.
- A build older than this one must not be installed over a migrated database; there is no downgrade guard in sqflite here. Exports are decoded to physical units so they import anywhere (round-1 review fix).
- Bump frequency in the projection is an assumption.
- Physiological validity is unchanged and not assessed.
