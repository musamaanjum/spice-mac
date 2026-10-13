#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/spice-key-delivery.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
swiftc -emit-library -emit-module -module-name CocoaSpice \
    "$ROOT/Tests/GuestKeyDelivery/CocoaSpice.swift" -o "$CHECK_DIR/libCocoaSpice.dylib"
swiftc -emit-library -emit-module -module-name SpiceInputMap \
    "$ROOT/Packages/SpiceInputMap/Sources/SpiceInputMap/"*.swift -o "$CHECK_DIR/libSpiceInputMap.dylib"
swiftc -I "$CHECK_DIR" -L "$CHECK_DIR" -lCocoaSpice -lSpiceInputMap \
    -Xlinker -rpath -Xlinker "$CHECK_DIR" \
    "$ROOT/Sources/SpiceMac/GuestKeyboardCapture.swift" \
    "$ROOT/Packages/SpiceController/Sources/SpiceController/SpiceInputRouter.swift" \
    "$ROOT/Tests/GuestKeyDelivery/main.swift" -o "$CHECK_DIR/guestkeycheck"
"$CHECK_DIR/guestkeycheck"
