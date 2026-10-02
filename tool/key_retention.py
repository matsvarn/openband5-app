#!/usr/bin/env python3
"""Key retention between two pulled OpenBand 5 databases (read-only).

Every durable key in the BEFORE copy must still exist in the AFTER copy:

  decoded_onehz  (device_id, ts_ms)
  raw_blob       (device_id, first_counter, last_counter, first_ts, n)
  day_result     (day_id, algo_version)

Prints one line per table and exits 1 when any key is missing. Growth is
reported, never required: an interruption trial may legitimately add nothing.

Usage: key_retention.py <before/openstrap.db> <after/openstrap.db>
"""

import sqlite3
import sys

KEYS = {
    "decoded_onehz": ("device_id", "ts_ms"),
    "raw_blob": ("device_id", "first_counter", "last_counter", "first_ts", "n"),
    "day_result": ("day_id", "algo_version"),
}


def open_ro(path):
    # mode=ro still applies an existing -wal, which a pulled container carries.
    return sqlite3.connect(f"file:{path}?mode=ro", uri=True)


def keys(db, table, cols):
    return set(db.execute(f"SELECT {', '.join(cols)} FROM {table}"))


def main(before_path, after_path):
    before, after = open_ro(before_path), open_ro(after_path)
    missing_total = 0
    for table, cols in KEYS.items():
        b, a = keys(before, table, cols), keys(after, table, cols)
        missing = len(b - a)
        missing_total += missing
        print(f"{table:14} before={len(b):>9} after={len(a):>9} "
              f"missing={missing} added={len(a - b)}")
    print("RETAINED" if missing_total == 0 else f"LOST {missing_total} KEYS")
    return 0 if missing_total == 0 else 1


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1], sys.argv[2]))
