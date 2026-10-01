#!/usr/bin/env bash
# Print the test files the golden lane has to load, one per line.
#
#   bash tool/golden_test_files.sh
#
# The Ubuntu shards drop golden-tagged tests with `--exclude-tags golden`, so
# this list must contain every file with such a test, or the test runs
# nowhere. A tag is a string literal, so a test file that mentions neither
# 'golden' nor matchesGoldenFile cannot carry the tag through its own source.
# If the literal or a pixel comparison appears in any other Dart file (a
# shared helper, an imported integration-test part, lib/), a test could get
# the tag from there, and the list falls back to every test file.
#
# Fails when a test file calls matchesGoldenFile without mentioning the tag:
# that comparison would run on Ubuntu, where the masters cannot match.
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

elsewhere=$(grep -rlE "$tag|matchesGoldenFile" test integration_test lib \
  --include='*.dart' | grep -vE '^test/.*_test\.dart$' || true)
if [[ -n $elsewhere ]]; then
  echo "golden tag or comparison outside test files; loading every test file:" >&2
  echo "$elsewhere" >&2
  echo "$all"
  exit 0
fi

if [[ -z $tagged ]]; then
  echo "no golden test files found" >&2
  exit 1
fi
echo "$tagged"
