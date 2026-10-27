#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
UNIVERSAL="${2:-}"
APP="build/Kove.app"
DEPLOYMENT=14.0

echo "Building Kove ($CONFIG)…"

bin_for() {
    swift build -c "$CONFIG" --triple "$1" >/dev/null
    swift build -c "$CONFIG" --triple "$1" --show-bin-path
}

if [ "$UNIVERSAL" = "--universal" ]; then
    # Two single-arch builds lipo'd together: `swift build --arch arm64 --arch
    # x86_64` would be shorter but needs xcbuild, which only full Xcode ships.
    ARM_DIR="$(bin_for "arm64-apple-macosx${DEPLOYMENT}")"
    X86_DIR="$(bin_for "x86_64-apple-macosx${DEPLOYMENT}")"
    mkdir -p build
    lipo -create "$ARM_DIR/Kove" "$X86_DIR/Kove" -output build/Kove-universal
    BIN="build/Kove-universal"
else
    BIN="$(bin_for "$(uname -m)-apple-macosx${DEPLOYMENT}")/Kove"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Kove"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Menu bar glyph (template image: black mask + @2x/@3x for Retina).
cp Resources/StatusIcon.png Resources/StatusIcon@2x.png Resources/StatusIcon@3x.png \
    "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature. Rebuilding changes the signature, so macOS may ask again
# for Automation permission ("Kove wants to control Music").
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/Kove"))"
echo "Run with: open $APP"
