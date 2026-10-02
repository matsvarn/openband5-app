#!/bin/zsh
# Run from the repository root. Never launches another Flutter command while
# an existing test/analyze/build command is visible on this host.
set -eu
export PATH="$HOME/.local/share/flutter/3.41.6/bin:$PATH"
export TZ=Europe/Berlin
export OB5_BENCH_DB="${OB5_BENCH_DB:-/tmp/ob5-storage/orig.db}"
quiet_seconds=0
while (( quiet_seconds < 20 )); do
  if pgrep -f '[f]lutter_tools.snapshot (test|analyze|build)' >/dev/null; then
    quiet_seconds=0
  else
    quiet_seconds=$((quiet_seconds + 1))
  fi
  sleep 1
done
exec flutter test --no-pub tool/storage_bench_test.dart --reporter expanded
