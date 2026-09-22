#!/usr/bin/env python3
"""Zero-loss capture verification on a pulled OpenBand 5 device database.

Read-only. Answers, with numbers, the question the interruption trial asks:
"did the pipeline lose anything the band sent?"

  1. decoded_onehz integrity — count, span, duplicate rec_ts, counter gaps.
  2. raw_blob — inflate every batch (gzip of u16le-length-prefixed inner
     frames), verify every blobbed record also exists decoded (the commit-
     before-ACK invariant: the blob is written inside the commit transaction,
     so a blobbed record with no decoded row means the commit itself lost it).
  3. sync_ledger hygiene — acked_at < created_at violations, split at the
     fix-install boundary (first raw_blob.captured_at).
  4. band_backlog — the persisted GET_DATA_RANGE read cursor.
  5. Coverage honesty — largest rec_ts gaps (interruptions must be gaps, not
     fabricated fills).
  6. day_result — algo_version spread and build-provenance presence.

Usage: verify_capture.py <path-to-openstrap.db>
"""

import gzip
import sqlite3
import struct
import sys


def q1(db, sql, args=()):
    return db.execute(sql, args).fetchone()


def main(path):
    db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    db.row_factory = sqlite3.Row
    problems = []

    print(f"== {path}")

    # ── 1. decoded_onehz ─────────────────────────────────────────────────
    n, lo, hi = q1(db, "SELECT COUNT(*), MIN(rec_ts), MAX(rec_ts) "
                       "FROM decoded_onehz")
    dup = q1(db, "SELECT COUNT(*) FROM (SELECT rec_ts FROM decoded_onehz "
                 "GROUP BY rec_ts HAVING COUNT(*) > 1)")[0]
    fams = db.execute("SELECT device_family, COUNT(*) FROM decoded_onehz "
                      "GROUP BY device_family").fetchall()
    print(f"decoded_onehz: {n} rows, rec_ts {lo}..{hi}, dup rec_ts={dup}")
    print("  device_family:", {r[0]: r[1] for r in fams})
    if dup:
        problems.append(f"{dup} duplicate rec_ts rows")

    # counter gaps (gen5 counters are contiguous per charge epoch)
    gaps = db.execute(
        "SELECT counter, rec_ts FROM decoded_onehz "
        "WHERE counter IS NOT NULL ORDER BY counter").fetchall()
    n_gaps = 0
    for a, b in zip(gaps, gaps[1:]):
        d = b[0] - a[0]
        if d > 1:
            n_gaps += 1
    print(f"  counter sequence: {len(gaps)} stamped, {n_gaps} forward gaps")

    # ── 2. raw_blob ──────────────────────────────────────────────────────
    try:
        batches = db.execute(
            "SELECT device_id, first_counter, last_counter, first_ts, "
            "last_ts, n, codec, payload, captured_at FROM raw_blob "
            "ORDER BY first_counter").fetchall()
    except sqlite3.OperationalError:
        batches = []
    if not batches:
        print("raw_blob: ABSENT or empty — no replay store on this copy")
    else:
        print(f"raw_blob: {len(batches)} batches")
    blob_records = 0
    blob_counters = []
    blob_ts = []
    codec_bad = 0
    for b in batches:
        if b["codec"] != 1:
            codec_bad += 1
            continue
        raw = gzip.decompress(b["payload"])
        i = 0
        while i + 2 <= len(raw):
            ln = raw[i] | (raw[i + 1] << 8)
            if ln <= 0 or i + 2 + ln > len(raw):
                problems.append(f"blob {b['first_counter']}: truncated frame "
                                f"at offset {i}")
                break
            fr = raw[i + 2:i + 2 + ln]
            blob_records += 1
            if len(fr) >= 11:
                blob_counters.append(
                    struct.unpack_from("<I", fr, 3)[0])
                blob_ts.append(struct.unpack_from("<I", fr, 7)[0])
            i += 2 + ln
    # declared n vs parsed count, per batch
    for b in batches:
        if b["codec"] != 1:
            continue
        raw = gzip.decompress(b["payload"])
        cnt = 0
        i = 0
        while i + 2 <= len(raw):
            ln = raw[i] | (raw[i + 1] << 8)
            if ln <= 0 or i + 2 + ln > len(raw):
                break
            cnt += 1
            i += 2 + ln
        if cnt != b["n"]:
            problems.append(f"blob batch {b['first_counter']}: declared n="
                            f"{b['n']} but {cnt} frames inflate")
    print(f"  parsed {blob_records} records from blobs; "
          f"declared n sum={sum(b['n'] for b in batches)}")
    if codec_bad:
        problems.append(f"{codec_bad} blob batches with unknown codec")

    # every blobbed ts must exist decoded (commit-before-ACK)
    if blob_ts:
        ts_set = set(r[0] for r in db.execute(
            "SELECT rec_ts FROM decoded_onehz WHERE rec_ts BETWEEN ? AND ?",
            (min(blob_ts), max(blob_ts))))
        missing_ts = [t for t in blob_ts if t not in ts_set]
        print(f"  blob ts range {min(blob_ts)}..{max(blob_ts)}: "
              f"{len(missing_ts)} of {len(blob_ts)} NOT in decoded_onehz")
        if missing_ts:
            problems.append(f"{len(missing_ts)} blobbed records never "
                            f"decoded (commit lost them)")

    # ── 3. sync_ledger violations ────────────────────────────────────────
    try:
        fix_ts = q1(db, "SELECT MIN(captured_at) FROM raw_blob")[0]
        tot = q1(db, "SELECT COUNT(*) FROM sync_ledger WHERE "
                     "acked_at IS NOT NULL AND created_at IS NOT NULL AND "
                     "acked_at < created_at")[0]
        post = q1(db, "SELECT COUNT(*) FROM sync_ledger WHERE "
                      "acked_at IS NOT NULL AND created_at IS NOT NULL AND "
                      "acked_at < created_at AND created_at >= ?",
                  (fix_ts or 2**62,))[0]
        mx = q1(db, "SELECT MAX(created_at) FROM sync_ledger WHERE "
                    "acked_at IS NOT NULL AND created_at IS NOT NULL AND "
                    "acked_at < created_at")[0]
        print(f"sync_ledger ack<created violations: {tot} total, "
              f"{post} since fix boundary "
              f"({fix_ts}), latest violating created_at={mx}")
        if post:
            problems.append(f"{post} ledger violations AFTER the fix")
    except sqlite3.OperationalError as e:
        print(f"sync_ledger: {e}")

    # ── 4. band_backlog cursor ───────────────────────────────────────────
    try:
        cols = {r[1] for r in db.execute("PRAGMA table_info(band_backlog)")}
        if not cols:
            raise sqlite3.OperationalError("no table")
        cur = [c for c in ("read_page", "raw_old_page",
                           "current_read_ts", "trim_ts") if c in cols]
        sel = "ts, used, wrap_count, device_family" + (
            ", " + ", ".join(cur) if cur else "")
        rows = db.execute(
            f"SELECT {sel} FROM band_backlog ORDER BY ts DESC LIMIT 3"
        ).fetchall()
        print(f"band_backlog: {len(rows)} latest rows; "
              f"cursor columns {'present' if len(cur) == 4 else 'ABSENT'}")
        for r in rows:
            print("   ", dict(r))
    except sqlite3.OperationalError:
        print("band_backlog: table absent (pre-cursor build)")

    # ── 5. coverage honesty — biggest rec_ts gaps ────────────────────────
    gaps = db.execute(
        "SELECT rec_ts, LEAD(rec_ts) OVER (ORDER BY rec_ts) - rec_ts AS gap "
        "FROM decoded_onehz").fetchall()
    big = sorted((g[1] for g in gaps if g[1] and g[1] > 300), reverse=True)[:8]
    print(f"rec_ts gaps >5 min: top {big}")

    # ── 6. day_result provenance ─────────────────────────────────────────
    vers = db.execute("SELECT algo_version, COUNT(*) FROM day_result "
                      "GROUP BY algo_version ORDER BY algo_version").fetchall()
    prov = q1(db, "SELECT COUNT(*) FROM day_result WHERE payload_json "
                  "LIKE '%\"build\"%'")[0]
    print(f"day_result versions: {[(r[0], r[1]) for r in vers]}; "
          f"{prov} carry a build-provenance block")

    print("\n== VERDICT:", "CLEAN" if not problems else
          f"{len(problems)} problem(s)")
    for p in problems:
        print("  !!", p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]) if len(sys.argv) > 1 else
                print("usage: verify_capture.py <db>"))
