#!/usr/bin/env bash
# Test the actual patched Darwin query function with IOKit calls replaced by
# in-process mocks. This never opens, claims, or redirects a physical USB device.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${1:?usage: test-libusb-pipe-properties.sh <libusb/os/darwin_usb.c>}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

python3 - "$SOURCE" "$WORK/pipe-query-under-test.inc" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
start = source.index('struct darwin_pipe_properties {')
end = source.index('\n#if defined(ENABLE_LOGGING)', start)
Path(sys.argv[2]).write_text(source[start:end])
PY
xcrun clang -std=c11 -Wall -Wextra -Werror -Wno-deprecated-declarations \
    -I "$WORK" "$ROOT/Tests/USBPipeProperties/main.c" -o "$WORK/check"
"$WORK/check"
