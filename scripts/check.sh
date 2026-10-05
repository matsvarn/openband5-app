#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
export PATH="${FLUTTER_HOME:-$HOME/.local/share/flutter/3.41.6}/bin:$PATH"
if ! command -v flutter >/dev/null 2>&1; then
  echo 'Install Flutter 3.41.6 on this machine first; see docs/openband5/DEVELOPMENT.md.' >&2
  exit 1
fi
if [[ "$(flutter --version | head -n 1)" != 'Flutter 3.41.6 '* ]]; then
  echo 'This checkout requires Flutter 3.41.6. Set FLUTTER_HOME to that SDK directory.' >&2
  exit 1
fi
bash .github/scripts/check_sibling_pins.sh
flutter analyze --no-pub
flutter test --no-pub --concurrency=1 --reporter=expanded
