#!/usr/bin/env bash
# Build a local app bundle. Optional output directory keeps validation away from a running app.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
CONFIG="${1:-debug}"
ARCH="${2:-native}"
OUTPUT_DIR="${3:-$ROOT/build}"
case "$OUTPUT_DIR" in
    /*) ;;
    *) echo "Output directory must be an absolute path" >&2; exit 2 ;;
esac
case "$CONFIG" in
    debug) NAME="AgentPet Local Dev"; IDENTIFIER="local.agentpet.dev"; DISPLAY_NAME="智能桌宠（开发版）"; DEVELOPMENT=true ;;
    release) NAME="AgentPet Local"; IDENTIFIER="local.agentpet"; DISPLAY_NAME="智能桌宠"; DEVELOPMENT=false ;;
    *) echo "Usage: $0 [debug|release] [native|universal] [absolute-output-directory]" >&2; exit 2 ;;
esac
case "$ARCH" in
    native) ARCHS=(--arch "$(uname -m)") ;;
    universal) ARCHS=(--arch arm64 --arch x86_64) ;;
    *) echo "Architecture must be native or universal" >&2; exit 2 ;;
esac

echo "正在构建 $DISPLAY_NAME ($CONFIG, $ARCH)..."
"$ROOT/scripts/swiftpm.sh" build -c "$CONFIG" "${ARCHS[@]}"
BINDIR="$("$ROOT/scripts/swiftpm.sh" build -c "$CONFIG" "${ARCHS[@]}" --show-bin-path)"
mkdir -p "$OUTPUT_DIR"
STAGE="$(mktemp -d "$OUTPUT_DIR/.app-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$OUTPUT_DIR/$NAME.app"
STAGED="$STAGE/$NAME.app"
mkdir -p "$STAGED/Contents/MacOS" "$STAGED/Contents/Resources"
cp "$BINDIR/agentpet" "$STAGED/Contents/MacOS/agentpet"
cp "$ROOT/scripts/AppInfo.plist" "$STAGED/Contents/Info.plist"
PLIST="$STAGED/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $IDENTIFIER" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $DISPLAY_NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $DISPLAY_NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :AgentPetDevelopmentBuild $DEVELOPMENT" "$PLIST"
if [ -f "$ROOT/scripts/AppIcon.icns" ]; then
    cp "$ROOT/scripts/AppIcon.icns" "$STAGED/Contents/Resources/AppIcon.icns"
fi
for lproj in "$ROOT/Localizations/"*.lproj; do
    [ ! -d "$lproj" ] || cp -R "$lproj" "$STAGED/Contents/Resources/"
done

# Ship dependency notices with the local binary as well as with its source checkout.
NOTICES="$STAGED/Contents/Resources/ThirdPartyNotices"
mkdir -p "$NOTICES"
cp "$ROOT/LICENSE" "$NOTICES/AGENTPET-LICENSE"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$NOTICES/"
cp "$ROOT/Vendor/AGENT-SPEED-LICENSE" "$ROOT/Vendor/AGENT-SPEED-UPSTREAM.md" "$NOTICES/"
cp "$ROOT/Vendor/CZstd/LICENSE" "$NOTICES/ZSTD-LICENSE"
cp "$ROOT/Vendor/CZstd/VENDOR.md" "$NOTICES/ZSTD-UPSTREAM.md"

# Local ad-hoc signing, not Developer ID distribution or notarization.
# A signing/build failure never replaces the last working application.
codesign --force --sign - "$STAGED"
codesign --verify --deep --strict "$STAGED"
if [ -e "$APP" ]; then mv "$APP" "$STAGE/previous.app"; fi
if ! mv "$STAGED" "$APP"; then
    [ ! -e "$STAGE/previous.app" ] || mv "$STAGE/previous.app" "$APP"
    exit 1
fi
echo "构建完成：$APP"
