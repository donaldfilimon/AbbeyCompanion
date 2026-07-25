# Shared toolchain resolution for AbbeyCompanion scripts.
# Source:  source "$(dirname "$0")/lib.sh" && abbey_use_swift
#
# SwiftData (@Query / @Model macros) ships only with Apple's Xcode toolchain.
# Open-source snapshots (swiftly main-snapshot / 6.5-dev) do NOT include
# libSwiftDataMacros — both CLI and Xcode → Toolchains → Snapshot fail with
# "unknown attribute 'Query'".
#
# This project pins `.swift-version` to `xcode` so `swiftly`-managed PATH `swift`
# resolves to XcodeDefault while your global default can stay on a snapshot.

abbey_resolve_xcode_dev() {
  local candidate="${DEVELOPER_DIR:-/Applications/Xcode-27.0.0-beta.4.app/Contents/Developer}"
  if [[ -d "$candidate" ]]; then
    printf '%s' "$candidate"
    return 0
  fi
  candidate="$(xcode-select -p 2>/dev/null || true)"
  if [[ -n "$candidate" && -d "$candidate" ]]; then
    printf '%s' "$candidate"
    return 0
  fi
  return 1
}

abbey_swift_is_xcode() {
  local bin="$1"
  case "$bin" in
    */XcodeDefault.xctoolchain/usr/bin/swift) return 0 ;;
  esac
  # swiftly "xcode" shim still lives under ~/.swiftly/bin — probe the driver.
  local ver
  ver="$("$bin" --version 2>&1 || true)"
  case "$ver" in
    *"swiftlang-6.4"*|*"Swift version 6.4 "*) return 0 ;;
  esac
  # Xcode 27 betas report 6.4; accept "Xcode" in version string as a soft signal.
  if [[ "$ver" == *"(swiftlang-"* ]] && [[ "$ver" != *"-dev"* ]]; then
    return 0
  fi
  return 1
}

abbey_use_swift() {
  local xcode_dev swift_bin path_swift
  xcode_dev="$(abbey_resolve_xcode_dev)" || {
    echo "error: Xcode Developer directory not found. Install Xcode 27 or set DEVELOPER_DIR." >&2
    exit 1
  }
  export DEVELOPER_DIR="$xcode_dev"
  # Snapshots break SwiftData macros — never honor TOOLCHAINS for this package.
  unset TOOLCHAINS

  path_swift="$(command -v swift 2>/dev/null || true)"
  if [[ -n "$path_swift" ]] && abbey_swift_is_xcode "$path_swift"; then
    ABBEY_SWIFT="$path_swift"
    return 0
  fi

  swift_bin="${xcode_dev}/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
  if [[ ! -x "$swift_bin" ]]; then
    echo "error: Xcode Swift not found at $swift_bin" >&2
    exit 1
  fi

  if [[ -n "$path_swift" ]]; then
    echo "note: PATH swift ('$path_swift') is not Xcode's — using XcodeDefault for SwiftData macros." >&2
    echo "      Pin this repo with: swiftly use xcode   (writes .swift-version)" >&2
    echo "      In Xcode: Toolchains → Xcode Default (not a Development Snapshot)." >&2
  fi

  export PATH="$(dirname "$swift_bin"):/usr/bin:/bin:/usr/sbin:/sbin"
  ABBEY_SWIFT="$swift_bin"
}

# Back-compat alias used by older script snippets.
abbey_use_xcode_swift() { abbey_use_swift; }
