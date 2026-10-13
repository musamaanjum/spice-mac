#!/usr/bin/env bash
#
# upgrade-libusb.sh — replace the bundled libusb with a current arm64 build while
# preserving the framework/install name expected by spice-client-glib and usbredir.
#
# Run AFTER scripts/fetch-sysroot.sh, then rebuild the app. Fetching the sysroot
# again will replace this generated framework binary with the pinned copy.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FW="$ROOT/Frameworks"
USB_FW="$FW/usb-1.0.0.framework"
USB_BIN="$USB_FW/Versions/A/usb-1.0.0"
HEADER="$ROOT/ThirdParty/CocoaSpice/Sources/CocoaSpice/ExternalHeaders/libusb-1.0/libusb.h"
VER="1.0.30"
SHA256="fea36f34f9156400209595e300840767ab1a385ede1dc7ee893015aea9c6dbaf"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

log() { printf '\033[1;34m[upgrade-libusb]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[upgrade-libusb] error:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -m)" = "arm64" ] || die "this framework build is Apple-Silicon only"
[ -f "$USB_BIN" ] || die "usb-1.0.0.framework not found — run fetch-sysroot.sh first"
command -v xcrun >/dev/null 2>&1 || die "Xcode command-line tools are required"

cd "$WORK"
log "downloading libusb $VER source"
curl -fL --retry 5 --retry-delay 2 --retry-all-errors --connect-timeout 20 \
    -o libusb.tar.bz2 \
    "https://github.com/libusb/libusb/releases/download/v$VER/libusb-$VER.tar.bz2"
echo "$SHA256  libusb.tar.bz2" | shasum -a 256 -c - \
    || die "source checksum mismatch — aborting"
tar xjf libusb.tar.bz2
cd "libusb-$VER"

log "applying Tahoe isochronous endpoint-query workaround"
patch -p1 --forward < "$ROOT/ThirdParty/libusb-tahoe-isochronous.patch"
"$ROOT/scripts/test-libusb-pipe-properties.sh" "$PWD/libusb/os/darwin_usb.c"

log "configuring + building arm64 dylib"
# Xcode 27's SDK advertises pipe2(), but our macOS 11+ deployment target and
# current Tahoe runtime do not provide it. Autoconf's link-only check accepts
# the weak import and libusb then calls NULL during startup. Use pipe()+fcntl().
ac_cv_func_pipe2=no \
./configure \
    --disable-static \
    --enable-shared \
    --prefix="$WORK/out" \
    CFLAGS="-arch arm64 -O2 -mmacosx-version-min=11.0" \
    LDFLAGS="-arch arm64 -mmacosx-version-min=11.0" \
    >"$WORK/configure.log"
make -j"$(sysctl -n hw.ncpu)" >"$WORK/build.log" 2>&1 \
    || { tail -30 "$WORK/build.log" >&2; die "build failed"; }

BUILT="$PWD/libusb/.libs/libusb-1.0.0.dylib"
[ -f "$BUILT" ] || die "built dylib not found"
[ "$(lipo -archs "$BUILT")" = "arm64" ] || die "built dylib is not arm64"
"$ROOT/scripts/test-libusb-runtime.sh" "$BUILT"

# Keep the framework identity used by the existing native dependency closure.
STAGED="$WORK/usb-1.0.0"
cp "$BUILT" "$STAGED"
install_name_tool -id '@rpath/usb-1.0.0.framework/usb-1.0.0' "$STAGED"

# ABI gate: every libusb function imported by the two consumers must exist in
# the replacement before the staged framework is touched.
log "verifying spice-client-glib/usbredirhost ABI compatibility"
CONSUMERS=(
    "$FW/spice-client-glib-2.0.8.framework/Versions/A/spice-client-glib-2.0.8"
    "$FW/usbredirhost.1.framework/Versions/A/usbredirhost.1"
)
for consumer in "${CONSUMERS[@]}"; do
    [ -f "$consumer" ] || die "missing ABI consumer: $consumer"
done
imported="$(
    for consumer in "${CONSUMERS[@]}"; do nm -u "$consumer"; done \
        | awk '/^_libusb_/ { print $1 }' | sort -u
)"
exported="$(nm -gU "$STAGED" | awk '$2 ~ /^[TDSBR]$/ { print $3 }' | sort -u)"
missing="$(comm -23 <(printf '%s\n' "$imported") <(printf '%s\n' "$exported"))"
if [ -n "$missing" ]; then
    printf '%s\n' "$missing" | sed 's/^/  MISSING: /' >&2
    die "replacement does not satisfy the existing libusb ABI"
fi

log "installing libusb $VER into the staged framework"
cp "$STAGED" "$USB_BIN"
# The release header contains a few whitespace-only line endings; normalize them
# so the vendored copy continues to pass this repository's diff hygiene check.
sed -E 's/[[:space:]]+$//' "$PWD/libusb/libusb.h" >"$HEADER"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VER" \
    "$USB_FW/Versions/A/Resources/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 12037" \
    "$USB_FW/Versions/A/Resources/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :SpiceMacTahoeIsochronousWorkaround" \
    "$USB_FW/Versions/A/Resources/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :SpiceMacTahoeIsochronousWorkaround bool true" \
    "$USB_FW/Versions/A/Resources/Info.plist"

codesign --force --sign - "$USB_FW"
codesign --verify --strict "$USB_FW"

actual_id="$(otool -D "$USB_BIN" | tail -1)"
[ "$actual_id" = '@rpath/usb-1.0.0.framework/usb-1.0.0' ] \
    || die "unexpected framework install name: $actual_id"

log "done — libusb $VER installed; run scripts/build-app.sh to rebuild SpiceMac.app"
