#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
swiftc "$ROOT/Sources/SpiceMac/Preferences.swift" "$ROOT/scripts/check-resolution.swift" -o "$WORK/resolutioncheck"
"$WORK/resolutioncheck"
