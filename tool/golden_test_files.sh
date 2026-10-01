#!/usr/bin/env bash
# Print the test files the golden lane has to load, one per line.
#
#   bash tool/golden_test_files.sh
#
# The golden lane exists to compare pixels; the Ubuntu shards already run
# every test body, goldens included, with an image comparator that accepts.
# So this list must contain every file that compares pixels, or a golden image
# is never checked. A test file that mentions neither 'golden' nor
# matchesGoldenFile can still get a pixel comparison or the tag from a shared
# helper or from dart_test.yaml; if any tracked Dart file other than a test
# file carries either marker, or a dart_test.yaml exists, the list falls back
# to every test file.
#
# Fails when a test file calls matchesGoldenFile without mentioning the tag:
# that comparison would never run with the exact comparator.
set -euo pipefail
export LC_ALL=C

cd "$(dirname "$0")/.."
tag="['\"]golden['\"]"

all=$(find test -name '*_test.dart' | sort)
tagged=$(grep -lE "$tag" $all | sort || true)
comparing=$(grep -l matchesGoldenFile $all | sort || true)

untagged=$(comm -13 <(printf '%s\n' "$tagged") <(printf '%s\n' "$comparing"))
if [[ -n $untagged ]]; then
  echo "matchesGoldenFile without a golden tag in:" >&2
  echo "$untagged" >&2
  exit 1
fi

elsewhere=$( (git ls-files '*.dart' | grep -vE '^test/.*_test\.dart$' |
  xargs grep -lE "$tag|matchesGoldenFile" || true
  git ls-files '*dart_test.yaml') | sort)
if [[ -n $elsewhere ]]; then
  echo "golden marker or test config outside test files; loading every test file:" >&2
  echo "$elsewhere" >&2
  echo "$all"
  exit 0
fi

if [[ -z $tagged ]]; then
  echo "no golden test files found" >&2
  exit 1
fi
echo "$tagged"
