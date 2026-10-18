#!/bin/bash
# SPDX-License-Identifier: MIT
# Uses temporary files; never opens, claims, resets, or redirects a USB device.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/spice-usb-diagnostics.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
swiftc "$ROOT/Sources/SpiceMac/DiagnosticLog.swift" \
    "$ROOT/Tests/USBDiagnostics/main.swift" -o "$CHECK_DIR/usbdiagnosticscheck"
"$CHECK_DIR/usbdiagnosticscheck"

HEADERS="$ROOT/ThirdParty/CocoaSpice/Sources/CocoaSpice/ExternalHeaders"
xcrun clang -fobjc-arc -DWITH_USB_SUPPORT -Wno-nullability-completeness \
    -I "$ROOT/ThirdParty/CocoaSpice/Sources/CocoaSpice/include" \
    -I "$HEADERS" -I "$HEADERS/glib-2.0" -I "$HEADERS/gstreamer-1.0" \
    -I "$HEADERS/libusb-1.0" -I "$HEADERS/spice-1" -I "$HEADERS/spice-client-glib-2.0" \
    -F "$ROOT/Frameworks" -framework Foundation -framework glib-2.0.0 \
    -framework spice-client-glib-2.0.8 -framework usb-1.0.0 \
    -Wl,-rpath,"$ROOT/Frameworks" \
    "$ROOT/Tests/USBDiagnostics/native.m" -o "$CHECK_DIR/nativecheck"
"$CHECK_DIR/nativecheck"
