# Retention tiers — design (decided 2026-09-22, implementation deferred)

## Decision

Three tiers, age-bounded by the DATA EDGE (newest stored day), never the wall
clock — a multi-day flash backfill must not count as old data:

| tier | age behind data edge | keeps | loses |
|---|---|---|---|
| 1 | ≤ 30 days | `decoded_onehz` + `decoded_rr` + `raw_records` + `raw_blob` | nothing |
| 2 | ≤ 90 days | `raw_blob` only | `decoded_onehz`, `decoded_rr`, `raw_records` |
| 3 | > 90 days | `day_result` + `metric_series` (derived) | all raw |

`raw_archive` (undecodable/unknown-version records) is never pruned in ANY tier
— it is the small, irreplaceable forensic store, and tier 3 needs it to answer
"what did the band send that we couldn't read?" forever.

## Why this shape

- `raw_blob` (~5 MB/day measured on the 9e58f5d8 build) is the cheap replay
  substrate: 90 days of full field-level replayability ≈ 450 MB, versus ~2 GB
  for keeping `decoded_onehz` that long. Tier 2 exists precisely because the
  blob is the cost-efficient deep-history form.
- `decoded_onehz` beyond 30 days is a convenience copy: everything in it can
  be re-produced from the blob by `decodeSubstrate` (verified field-for-field
  by `tool/replay_check.dart`), and no shipped reader needs 1 Hz older than
  the baseline windows (28 days) it consumes.
- Tier 3 keeps the honest product surface: every number the UI ever showed
  (`day_result` immutably versioned + `metric_series`) survives; only the
  ability to RE-derive is shed — and by then the day's own bundle has been
  stable for months.

## What must be true before implementing

1. **Measure first.** A week of the current build tells the real growth rate:
   `decoded_onehz` + `raw_blob` bytes/day, `raw_records` slope, per-day
   `raw_archive` trickle. The 30/90 numbers were picked before that data
   existed; re-confirm them against measured growth, not against the
   estimate. (Tool: `tool/verify_capture.py` reports counts; `du`/`page_count`
   on the pulled DB gives bytes.)
2. **Never prune an underived day** — the existing rule already applies per
   tier boundary: a day without a complete, non-partial `day_result` keeps its
   raw regardless of age. Tier transitions delete in oldest-first order inside
   one transaction, and a deleted day's `decoded_rr` beats go with it (the
   eviction-cascade rule).
3. **The blob tier needs a re-decode entry point** that reads `raw_blob` back
   into `decoded_onehz` for a day range (the restore path for a day that must
   be re-derived after tier-2 pruning). `rawBlobRecords()` already pages by
   counter; the write-back is `commitSyncBatch`'s own decode path. Do NOT add
   this until the policy ships — it is the only piece that turns "replayable"
   into "replayed".
4. **Export before prune.** A day crossing tier 2→3 must already be in the
   user's last `auto_backup`/`export`, or the prune must produce the export
   itself. Pruning a day nobody can reproduce elsewhere is the only
   irreversible step in the design.

## Non-goals

- No force-trim of band flash (dangerous opcode, unchanged).
- No cap on `raw_archive`, `band_events`, `band_backlog`, `sync_ledger` —
  these are the audit trail; their growth is bounded by connect frequency, not
  data rate.
- No separate "importance" tiers (e.g. keep-workout-days-forever) until
  measured growth says the flat policy is insufficient.
