#!/usr/bin/env bash
# Run AbbeyCompanion with an Xcode-backed Swift (SwiftData macros).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

abbey_use_swift

exec "$ABBEY_SWIFT" run --package-path "$ROOT" "$@"
