#!/usr/bin/env bash
# Headless smoke: build, test, and assert the AbbeyCompanion binary exists.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

abbey_use_swift

"$ABBEY_SWIFT" build --package-path "$ROOT"
"$ABBEY_SWIFT" test --package-path "$ROOT"

BIN="$(find "$ROOT/.build" -type f -name AbbeyCompanion -perm -111 2>/dev/null | head -1)"
[[ -n "$BIN" ]] || { echo "error: AbbeyCompanion binary not found under .build" >&2; exit 1; }
echo "smoke OK — binary: $BIN (swift: $ABBEY_SWIFT)"
file "$BIN"
