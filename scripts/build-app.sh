#!/usr/bin/env bash
#
# build-app.sh — build SpiceMac via SwiftPM and assemble a runnable SpiceMac.app.
#
# Requirements:
#   * Full Xcode (the Metal toolchain compiles CocoaSpice's shader; Command Line
#     Tools alone cannot build the app).
#   * Native SPICE frameworks staged under ./Frameworks (run scripts/fetch-sysroot.sh).
#
# Environment overrides:
#   CONFIG=release|debug            (default: release)
#   SIGN_IDENTITY="Developer ID Application: …"   (default: "-" ad-hoc)
#   HARDENED=1                      sign with hardened runtime + entitlements
#   SPICEMAC_BUILD_DIR=/path        separate output directory (default: ./build)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP_NAME="SpiceMac"
OUT="${SPICEMAC_BUILD_DIR:-$ROOT/build}"
APP="$OUT/$APP_NAME.app"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

log() { printf '\033[1;34m[build-app]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[build-app] error:\033[0m %s\n' "$*" >&2; exit 1; }

# --- Preconditions (fail fast — don't produce a broken app) ----------------
# Full Xcode must be selected (Command Line Tools alone can't build this).
if ! xcode-select -p 2>/dev/null | grep -q "Xcode.app"; then
    die "full Xcode is not selected (got: $(xcode-select -p 2>/dev/null)).
         Fix: sudo xcode-select -s /Applications/Xcode.app   (or run scripts/doctor.sh)"
fi
# The Metal toolchain (a separate component on Xcode 26) compiles CocoaSpice's
# shader. If it's missing the app builds but the display never renders — so fail
# HERE rather than ship a silently-broken bundle. Override with ALLOW_NO_METAL=1.
if [ "${ALLOW_NO_METAL:-0}" != "1" ] && ! xcrun -sdk macosx metal --version >/dev/null 2>&1; then
    die "the Metal toolchain is not installed (xcrun metal failed).
         Fix: xcodebuild -downloadComponent MetalToolchain
         (or set ALLOW_NO_METAL=1 to build a non-rendering app anyway)"
fi

shopt -s nullglob
# Only the frameworks the client actually loads (the runtime closure, computed via
# `otool -L` over the built binary). This DELIBERATELY excludes the rest of the UTM
# sysroot — most importantly the GPL-2.0 QEMU frameworks (qemu-*-softmmu, qemu-img)
# plus spice-server, swtpm, virglrenderer, slirp, MoltenVK/vulkan/epoxy — which the
# SPICE *client* never loads and which would attach GPL obligations (and ~390 MB of
# dead weight) to the distributed .app. Re-verify after changing with:
#   otool -L build/SpiceMac.app/Contents/MacOS/SpiceMac  (and recurse over frameworks)
RUNTIME_FRAMEWORKS=(
    glib-2.0.0 gobject-2.0.0 gio-2.0.0 gmodule-2.0.0 ffi.8 intl.8 iconv.2
    spice-client-glib-2.0.8
    gstreamer-1.0.0 gstbase-1.0.0 gstapp-1.0.0 gstaudio-1.0.0 gstvideo-1.0.0
    gstpbutils-1.0.0 gsttag-1.0.0
    phodav-3.0.0 soup-3.0.0
    usb-1.0.0 usbredirhost.1 usbredirparser.1
    json-glib-1.0.0 pixman-1.0 jpeg.62 opus.0
    crypto.1.1 ssl.1.1
)
[ -d "Frameworks/glib-2.0.0.framework" ] \
    || die "Frameworks/ not staged — run scripts/fetch-sysroot.sh first."

# --- Build -----------------------------------------------------------------
log "swift build -c $CONFIG"
swift build -c "$CONFIG"
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"
[ -x "$BIN_PATH/$APP_NAME" ] || die "built executable not found at $BIN_PATH/$APP_NAME"

# --- Assemble .app ---------------------------------------------------------
log "assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
GIT_COMMIT="$(git rev-parse --short=12 HEAD 2>/dev/null || true)"
if [ -n "$GIT_COMMIT" ]; then
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        GIT_COMMIT="$GIT_COMMIT-dirty"
    fi
    /usr/libexec/PlistBuddy -c "Add :SpiceMacGitCommit string $GIT_COMMIT" "$APP/Contents/Info.plist"
    log "  git commit: $GIT_COMMIT"
fi
cp "$BIN_PATH/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

# App icon (CFBundleIconFile=AppIcon). Regenerate with scripts/make-icon.sh.
[ -f "$ROOT/Resources/AppIcon.icns" ] && cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# SwiftPM resource bundles (e.g. the compiled Metal shader for the renderer).
# SwiftPM resource bundles go in Contents/Resources (CocoaSpice's renderer loads
# CocoaSpice_CocoaSpiceRenderer.bundle from mainBundle.resourceURL).
for bundle in "$BIN_PATH"/*.bundle; do
    cp -R "$bundle" "$APP/Contents/Resources/"
done

# SwiftPM does NOT compile .metal resources (only Xcode's build system does), so
# compile the CocoaSpice shader into default.metallib inside the renderer bundle —
# newDefaultLibraryWithBundle: needs it, or the display cannot render.
RENDERER_DIR="$ROOT/ThirdParty/CocoaSpice/Sources/CocoaSpiceRenderer"
RES_BUNDLE="$APP/Contents/Resources/CocoaSpice_CocoaSpiceRenderer.bundle"
if [ -f "$RENDERER_DIR/CSShaders.metal" ] && [ -d "$RES_BUNDLE" ]; then
    # Xcode-generated macOS bundles keep resources in Contents/Resources,
    # whereas bundles produced by `swift build` use a flat layout. Metal's
    # newDefaultLibraryWithBundle: searches Bundle.resourceURL, so install the
    # library there rather than assuming the bundle root.
    if [ -d "$RES_BUNDLE/Contents/Resources" ]; then
        METAL_RESOURCES="$RES_BUNDLE/Contents/Resources"
    else
        METAL_RESOURCES="$RES_BUNDLE"
    fi
    log "compiling Metal shader → default.metallib"
    if xcrun -sdk macosx metal -I "$RENDERER_DIR" -c "$RENDERER_DIR/CSShaders.metal" -o "$WORK/CSShaders.air" 2>"$WORK/metal.log" \
       && xcrun -sdk macosx metallib "$WORK/CSShaders.air" -o "$METAL_RESOURCES/default.metallib" 2>>"$WORK/metal.log"; then
        rm -f "$RES_BUNDLE/CSShaders.metal" "$METAL_RESOURCES/CSShaders.metal" # raw source not needed at runtime
        # A flat SwiftPM resource bundle has no Info.plist, so add one to make
        # it a valid bundle. Preserve Xcode's Contents/Info.plist when present.
        if [ ! -f "$RES_BUNDLE/Contents/Info.plist" ]; then
            cat > "$RES_BUNDLE/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>org.spicemac.CocoaSpiceRenderer.resources</string>
  <key>CFBundleName</key><string>CocoaSpiceRenderer</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
</dict></plist>
PLIST
        fi
        log "  default.metallib OK"
    elif [ "${ALLOW_NO_METAL:-0}" = "1" ]; then
        log "WARNING: Metal shader compile failed but ALLOW_NO_METAL=1 — display will NOT render."
        sed 's/^/         metal: /' "$WORK/metal.log" 2>/dev/null | tail -2
    else
        sed 's/^/         metal: /' "$WORK/metal.log" 2>/dev/null | tail -3 >&2
        die "Metal shader compile failed — the app would not render the display.
         Fix: xcodebuild -downloadComponent MetalToolchain   (or ALLOW_NO_METAL=1 to ship a non-rendering app)"
    fi
else
    log "WARNING: renderer shader not found; display rendering may not work"
fi

# Native SPICE frameworks — allowlist only (see RUNTIME_FRAMEWORKS above).
for name in "${RUNTIME_FRAMEWORKS[@]}"; do
    fw="Frameworks/$name.framework"
    [ -d "$fw" ] || die "missing required framework: $fw (re-run fetch-sysroot.sh)"
    cp -R "$fw" "$APP/Contents/Frameworks/"
done

# --- License notices -------------------------------------------------------
# A distributed binary must carry the LGPL-2.1/Apache-2.0/OpenSSL/BSD/MIT texts and
# attribution WITH the .app (LGPL-2.1 §6/§1, Apache-2.0 §4(a), OpenSSL/BSD/MIT
# binary-redistribution clauses). Ship the verbatim texts + attribution in-bundle.
log "bundling license notices"
LIC_DST="$APP/Contents/Resources/Licenses"
mkdir -p "$LIC_DST"
cp "$ROOT/licenses/"*.txt "$LIC_DST/"
cp "$ROOT/THIRD-PARTY-LICENSES.txt" "$APP/Contents/Resources/"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"

# --- Strip build-host rpath ------------------------------------------------
# SwiftPM bakes an absolute Xcode toolchain LC_RPATH into the binary. It is unused
# at runtime (all libswift* resolve from the OS dyld shared cache via /usr/lib/swift),
# but it leaks a machine-specific path; drop it so the bundle is host-agnostic. The
# app is (re-)signed below, so this stays sealed.
XCODE_SWIFT_RPATH="$(otool -l "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null \
    | awk '/LC_RPATH/{f=1} f&&/path /{print $2; f=0}' \
    | grep -m1 'Xcode.*Toolchains.*swift' || true)"
if [ -n "$XCODE_SWIFT_RPATH" ]; then
    install_name_tool -delete_rpath "$XCODE_SWIFT_RPATH" "$APP/Contents/MacOS/$APP_NAME" \
        2>/dev/null && log "  stripped host rpath: $XCODE_SWIFT_RPATH" || true
fi

# --- Sign ------------------------------------------------------------------
# Catch SDK/runtime incompatibilities in the actual bundled USB library before
# sealing or packaging the app. This initializes libusb without device capture.
log "checking bundled libusb startup"
"$ROOT/scripts/test-libusb-runtime.sh" \
    "$APP/Contents/Frameworks/usb-1.0.0.framework/Versions/A/usb-1.0.0"

SIGN_ARGS=(--force --sign "$SIGN_IDENTITY")
if [ "$SIGN_IDENTITY" = "-" ]; then
    SIGN_ARGS+=(--timestamp=none)
else
    SIGN_ARGS+=(--timestamp)
fi

APP_SIGN_ARGS=("${SIGN_ARGS[@]}")
if [ "${HARDENED:-0}" = "1" ]; then
    APP_SIGN_ARGS+=(--options runtime --entitlements "$ROOT/Resources/$APP_NAME.entitlements")
fi

log "signing frameworks (identity: $SIGN_IDENTITY)"
# Sign nested code first (deepest first), then the app.
find "$APP/Contents/Frameworks" -type d -name "*.framework" -print0 |
    while IFS= read -r -d '' fw; do
        codesign "${SIGN_ARGS[@]}" "$fw" 2>/dev/null || codesign "${SIGN_ARGS[@]}" "$fw"
    done
# SwiftPM resource bundles are data-only flat bundles (Info.plist and resources
# live at their root). Current codesign rejects signing that layout directly as
# "unsealed contents present in the bundle root". They contain no executable
# code and are sealed by the outer app signature below, so only sign frameworks
# here.

log "signing app"
codesign "${APP_SIGN_ARGS[@]}" "$APP"

log "verifying"
codesign --verify --deep --strict --verbose=2 "$APP" || log "WARNING: codesign verification reported issues"

log "done → $APP"
log "run with: open \"$APP\"   (or pass a file: open -a \"$APP\" connection.vv)"

# --- Package for distribution ----------------------------------------------
# Use ditto (NOT plain zip): the bundle has ~78 symlinks (framework Versions/Current
# links) and nested ad-hoc code signatures that plain zip mangles. Publish the
# SHA-256 in the release notes — for an unsigned/un-notarized download it is the
# only integrity signal users get.
if [ "${PACKAGE:-1}" = "1" ]; then
    ZIP="$OUT/$APP_NAME.app.zip"
    rm -f "$ZIP" "$ZIP.sha256"
    log "packaging → $ZIP"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
    ( cd "$OUT" && shasum -a 256 "$APP_NAME.app.zip" | tee "$APP_NAME.app.zip.sha256" )
    log "SHA-256 written → $ZIP.sha256 (publish this in the release notes)"
fi
