#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/spice-keyboard-check.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
swiftc "$ROOT/Sources/SpiceMac/GuestKeyboardCapture.swift" \
    "$ROOT/Tests/KeyboardCapture/main.swift" -o "$CHECK_DIR/keyboardcheck"
"$CHECK_DIR/keyboardcheck"
swiftc "$ROOT/Sources/SpiceMac/GuestKeyboardCapture.swift" \
    "$ROOT/Tests/NativeFullscreen/main.swift" -o "$CHECK_DIR/fullscreencheck"
"$CHECK_DIR/fullscreencheck"
