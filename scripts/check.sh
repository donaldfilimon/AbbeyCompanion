#!/usr/bin/env bash
# Build + test AbbeyCompanion with an Xcode-backed Swift (SwiftData macros).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

abbey_use_swift

"$ABBEY_SWIFT" build --package-path "$ROOT"
"$ABBEY_SWIFT" test --package-path "$ROOT"
echo "OK — build + CoreAIToolsTests + AbbeyCoreTests + AbbeyCompanionKitTests (via $ABBEY_SWIFT)"
