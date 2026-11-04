#!/usr/bin/env bash
# Manual DMG distribution. No uploading, appcast, upstream credentials or updater.
# Optional: SIGNING_IDENTITY="Developer ID Application: ..." NOTARY_PROFILE="..."
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
ARCH="${1:-native}"
IDENTITY="${SIGNING_IDENTITY:-}"
PROFILE="${NOTARY_PROFILE:-}"
if [ -n "$PROFILE" ] && [ -z "$IDENTITY" ]; then
    echo "NOTARY_PROFILE requires your own SIGNING_IDENTITY." >&2; exit 2
fi
"$ROOT/scripts/build-app.sh" release "$ARCH"
APP="$ROOT/build/LuMate.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$ROOT/build/LuMate-$VERSION-$ARCH.dmg"
STAGE="$(mktemp -d "$ROOT/build/.dmg-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

if [ -n "$IDENTITY" ]; then
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/MacOS/agentpet"
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
    codesign --verify --deep --strict "$APP"
fi
if [ -n "$PROFILE" ]; then
    ditto -c -k --keepParent "$APP" "$STAGE/app.zip"
    xcrun notarytool submit "$STAGE/app.zip" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
fi
mkdir "$STAGE/contents"
ditto "$APP" "$STAGE/contents/LuMate.app"
ln -s /Applications "$STAGE/contents/Applications"
cp "$ROOT/LICENSE" "$STAGE/contents/LICENSE"
hdiutil create -volname "LuMate" -srcfolder "$STAGE/contents" -ov -format UDZO "$STAGE/distribution.dmg"
if [ -n "$IDENTITY" ]; then
    codesign --force --timestamp --sign "$IDENTITY" "$STAGE/distribution.dmg"
fi
if [ -n "$PROFILE" ]; then
    xcrun notarytool submit "$STAGE/distribution.dmg" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "$STAGE/distribution.dmg"
    xcrun stapler validate "$STAGE/distribution.dmg"
fi
mv -f "$STAGE/distribution.dmg" "$DMG"
echo "DMG: $DMG"
shasum -a 256 "$DMG"
if [ -z "$PROFILE" ]; then
    echo "Not notarized: this build is not a friction-free distribution build for other Macs."
    echo "Use your own Developer ID and notarization profile for trusted distribution."
fi
