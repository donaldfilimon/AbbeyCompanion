#!/usr/bin/env bash
# Run AbbeyCompanion with a complete SwiftPM toolchain (Xcode), ignoring a
# partial ~/…/swift-project build that may shadow `swift` on PATH.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

XCODE_DEV="${DEVELOPER_DIR:-/Applications/Xcode-27.0.0-beta.4.app/Contents/Developer}"
if [[ ! -d "$XCODE_DEV" ]]; then
  XCODE_DEV="$(xcode-select -p 2>/dev/null || true)"
fi
SWIFT_BIN="${XCODE_DEV}/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
if [[ ! -x "$SWIFT_BIN" ]]; then
  echo "error: Xcode Swift not found at $SWIFT_BIN" >&2
  exit 1
fi

export DEVELOPER_DIR="$XCODE_DEV"
export PATH="$(dirname "$SWIFT_BIN"):/usr/bin:/bin:/usr/sbin:/sbin"
unset TOOLCHAINS

exec "$SWIFT_BIN" run --package-path "$ROOT" "$@"
