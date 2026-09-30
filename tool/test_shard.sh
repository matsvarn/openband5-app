#!/usr/bin/env bash
# Run one file-level shard of the unit/widget suite.
#
#   bash tool/test_shard.sh INDEX TOTAL [flutter test args...]
#
# Files are sorted and dealt round-robin, so every test file lands in exactly
# one shard and the split does not depend on the host. Unlike
# `flutter test --total-shards`, which splits tests inside each file, a shard
# only compiles its own files.
set -euo pipefail

index=$1
total=$2
shift 2

if ! [[ $index =~ ^[0-9]+$ && $total =~ ^[1-9][0-9]*$ ]] || ((index >= total)); then
  echo "usage: $0 INDEX TOTAL [flutter test args...] (0 <= INDEX < TOTAL)" >&2
  exit 64
fi

cd "$(dirname "$0")/.."
files=()
while IFS= read -r file; do
  files+=("$file")
done < <(find test -name '*_test.dart' | LC_ALL=C sort |
  awk -v n="$total" -v i="$index" '(NR - 1) % n == i')

if ((${#files[@]} == 0)); then
  echo "shard $index of $total has no test files" >&2
  exit 1
fi

echo "shard $index of $total: ${#files[@]} files"
exec flutter test --no-pub "$@" "${files[@]}"
