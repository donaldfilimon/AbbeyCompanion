#!/usr/bin/env bash
# Build + test AbbeyCompanion with Xcode’s Swift 6.4 toolchain.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

XCODE_DEV="${DEVELOPER_DIR:-/Applications/Xcode-27.0.0-beta.4.app/Contents/Developer}"
if [[ ! -d "$XCODE_DEV" ]]; then
  XCODE_DEV="$(xcode-select -p 2>/dev/null || true)"
fi
SWIFT_BIN="${XCODE_DEV}/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
[[ -x "$SWIFT_BIN" ]] || { echo "error: Xcode Swift not found at $SWIFT_BIN" >&2; exit 1; }

export DEVELOPER_DIR="$XCODE_DEV"
export PATH="$(dirname "$SWIFT_BIN"):/usr/bin:/bin:/usr/sbin:/sbin"
unset TOOLCHAINS

"$SWIFT_BIN" build --package-path "$ROOT"
"$SWIFT_BIN" test --package-path "$ROOT"
echo "OK — build + AbbeyCoreTests"
