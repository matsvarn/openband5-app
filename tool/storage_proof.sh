#!/bin/zsh
set -eu
export PATH="$HOME/.local/share/flutter/3.41.6/bin:$PATH"
export TZ=Europe/Berlin
export OB5_BASELINE_RESULTS="${OB5_BASELINE_RESULTS:-/tmp/ob5-storage/bench-results-2026-09-30T22-21-13.595968Z.md}"
quiet_seconds=0
wait_seconds=0
export OB5_PROOF_TIMING_CONTENTION=not_observed_at_launch
while (( quiet_seconds < 20 && wait_seconds < 120 )); do
  if pgrep -f '[f]lutter_tools.snapshot (test|analyze|build)' >/dev/null; then
    quiet_seconds=0
  else
    quiet_seconds=$((quiet_seconds + 1))
  fi
  sleep 1
  wait_seconds=$((wait_seconds + 1))
done
if (( quiet_seconds < 20 )); then
  export OB5_PROOF_TIMING_CONTENTION=possibly_contended
fi
exec flutter test --no-pub tool/storage_proof_test.dart --reporter expanded
