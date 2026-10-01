#!/usr/bin/env bash
# Print the test files the golden lane has to load, one per line: every test
# file that calls matchesGoldenFile.
#
#   bash tool/golden_test_files.sh
#
# The Ubuntu shards run every test with an image comparator that accepts, so
# the golden lane only has to compare pixels. It runs every test in these
# files, tagged or not, so a comparison counts no matter how its test is
# tagged.
#
# Fails when matchesGoldenFile appears in any other tracked Dart file: a
# shared helper's callers do not name it, so this list could not find them.
# Name such a helper here before introducing one.
set -euo pipefail
export LC_ALL=C

cd "$(dirname "$0")/.."

helpers=$(git ls-files '*.dart' | grep -vE '^test/.*_test\.dart$' |
  xargs grep -l matchesGoldenFile || true)
if [[ -n $helpers ]]; then
  echo "matchesGoldenFile outside test files; the golden lane cannot find their callers:" >&2
  echo "$helpers" >&2
  exit 1
fi

files=$(find test -name '*_test.dart' -print0 |
  xargs -0 grep -l matchesGoldenFile | sort || true)
if [[ -z $files ]]; then
  echo "no test file calls matchesGoldenFile" >&2
  exit 1
fi
echo "$files"
