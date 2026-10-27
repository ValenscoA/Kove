#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
UNIVERSAL="${2:-}"
APP="build/Kove.app"

# A universal binary needs xcbuild, which only full Xcode provides — the Command
# Line Tools alone can build for the host architecture only.
ARCHS=()
if [ "$UNIVERSAL" = "--universal" ]; then
    ARCHS=(--arch arm64 --arch x86_64)
    if ! swift build -c "$CONFIG" "${ARCHS[@]}" >/dev/null 2>&1; then
        echo "Universal build unavailable (needs full Xcode); building for this Mac only."
        ARCHS=()
    fi
fi

echo "Building Kove ($CONFIG)…"
swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/Kove"

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
