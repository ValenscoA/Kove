#!/bin/bash
#
# Builds a distributable disk image:  Tools/make-dmg.sh [version]
#
#   CODESIGN_IDENTITY  "Developer ID Application: Name (TEAMID)" to sign for
#                      distribution; defaults to ad-hoc (local use only).
#   APPLE_ID / APPLE_PASSWORD / APPLE_TEAM_ID
#                      when all three are set the image is notarized and stapled.
#
# Output: build/Kove-<version>.dmg

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)}"
APP="build/Kove.app"
DMG="build/Kove-${VERSION}.dmg"
IDENTITY="${CODESIGN_IDENTITY:--}"

echo "==> Building Kove ${VERSION}"
# Universal (arm64 + x86_64) when Xcode is available; native otherwise.
./build.sh release --universal >/dev/null

echo "==> Signing ($IDENTITY)"
if [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP"
else
    # Hardened runtime + timestamp are required for notarization.
    codesign --force --options runtime --timestamp \
        --sign "$IDENTITY" "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"

if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_PASSWORD:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
    echo "==> Notarizing"
    ZIP="build/Kove-notarize.zip"
    /usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
else
    echo "==> Skipping notarization (no APPLE_ID / APPLE_PASSWORD / APPLE_TEAM_ID)"
fi

echo "==> Staging"
STAGE="build/dmg-stage"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# Volume icon, when the tooling is available (SetFile ships with the CLT).
if command -v SetFile >/dev/null 2>&1; then
    cp Resources/AppIcon.icns "$STAGE/.VolumeIcon.icns"
    SetFile -c icnC "$STAGE/.VolumeIcon.icns"
    SetFile -a C "$STAGE" || true
fi

cat > "$STAGE/Install.txt" <<TXT
Kove ${VERSION}

Drag Kove to the Applications folder, then open it from there.

Kove lives in the menu bar (no Dock icon). It asks once for permission to
control Apple Music. Command Code usage needs a key from \`cmd login\`.

If macOS refuses to open it ("Apple could not verify..."), the build was not
signed with a Developer ID: right-click Kove -> Open, or run

    xattr -dr com.apple.quarantine /Applications/Kove.app
TXT

echo "==> Creating disk image"
hdiutil create \
    -volname "Kove ${VERSION}" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG" >/dev/null

rm -rf "$STAGE"

echo "==> Verifying"
hdiutil verify "$DMG" >/dev/null
shasum -a 256 "$DMG" | tee "${DMG}.sha256"

echo
echo "Built ${DMG} ($(du -h "$DMG" | cut -f1))"
