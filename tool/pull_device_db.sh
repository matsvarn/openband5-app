#!/usr/bin/env bash
# pull_device_db.sh — pull the app's FULL Documents container (db + -wal + -shm)
# into a timestamped dir under OpenBand5Lab and append one line to growth_log.csv.
#
# WHY the whole dir: the DB runs WAL. Copying openstrap.db alone snapshots an
# arbitrary checkpoint — recent writes (schema repairs, sync batches) still sit
# in -wal and silently don't appear. That exact miss once reported absent
# band_backlog cursor columns on a build that had already written them.
#
# Usage: tool/pull_device_db.sh [label]     # DEVICE env overrides the phone name
set -euo pipefail

DEVICE="${DEVICE:-iPhone von Mats}"
BUNDLE="dev.matsvarn.openband5"
ROOT="$HOME/Library/Application Support/OpenBand5Lab"
label="${1:-pull}"
stamp="$(date +%Y%m%d-%H%M%S)"
dest="$ROOT/device-${stamp}-${label}"

mkdir -p "$dest"
xcrun devicectl device copy from \
  --device "$DEVICE" \
  --source Documents \
  --destination "$dest/Documents" \
  --domain-type appDataContainer \
  --domain-identifier "$BUNDLE" >/dev/null

db="$dest/Documents/openstrap.db"
if [[ ! -f "$db" ]]; then
  echo "no openstrap.db in pulled container — app not installed/launched?" >&2
  exit 1
fi
# Touching the db with sqlite applies -wal to reads.
stats="$(python3 - "$db" <<'PY'
import sqlite3, sys, os
db = sys.argv[1]
con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
def q(sql):
    try: return con.execute(sql).fetchone()[0]
    except Exception: return None
rows   = q("SELECT COUNT(*) FROM decoded_onehz")
rmin   = q("SELECT MIN(rec_ts) FROM decoded_onehz")
rmax   = q("SELECT MAX(rec_ts) FROM decoded_onehz")
batches= q("SELECT COUNT(*) FROM raw_blob")
brecs  = q("SELECT COALESCE(SUM(n),0) FROM raw_blob")
days   = q("SELECT COUNT(DISTINCT day_id) FROM day_result")
print(f"{os.path.getsize(db)},{rows},{batches},{brecs},{rmin},{rmax},{days}")
PY
)"

log="$ROOT/growth_log.csv"
[[ -f "$log" ]] || echo "stamp,label,db_bytes,decoded_rows,blob_batches,blob_records,rec_ts_min,rec_ts_max,day_results" > "$log"
echo "${stamp},${label},${stats}" >> "$log"

echo "pulled → $db"
echo "growth_log: ${stamp},${label},${stats}"
