#!/usr/bin/env bash
# Exercise actual libusb initialization/event handling. No interface is claimed,
# no kernel driver is detached, and no device is reset or redirected.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIBRARY="${1:?usage: test-libusb-runtime.sh <libusb dylib>}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A pipe2 import is unsafe for the macOS 11+ deployment target even if the
# machine performing this check happens to run macOS 27 or later.
if nm -u "$LIBRARY" | awk '{print $NF}' | grep -qx '_pipe2'; then
    echo 'libusb runtime check failed: pipe2 is unavailable on supported macOS versions' >&2
    exit 1
fi

xcrun clang -std=c11 -Wall -Wextra -Werror \
    -I "$ROOT/ThirdParty/CocoaSpice/Sources/CocoaSpice/ExternalHeaders/libusb-1.0" \
    "$ROOT/Tests/USBRuntime/main.c" -o "$WORK/check"
"$WORK/check" "$LIBRARY"
