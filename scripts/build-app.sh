#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
CONFIGURATION="${1:-release}"
SCRATCH="${NABIRA_BUILD_DIR:-/tmp/nabira-spm-build}"

# SwiftUI macros in recent SDKs require the platform plugins shipped with Xcode.
# Choose tools for this process without changing the system's xcode-select setting.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    NABIRA_DEVELOPER_DIR="$(xcode-select -p)"
    if [[ ! -d "$NABIRA_DEVELOPER_DIR/Platforms/MacOSX.platform" ]]; then
        NABIRA_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    fi
    export DEVELOPER_DIR="$NABIRA_DEVELOPER_DIR"
fi
if [[ "$DEVELOPER_DIR" == *.app ]]; then
    export DEVELOPER_DIR="$DEVELOPER_DIR/Contents/Developer"
fi
if [[ ! -d "$DEVELOPER_DIR/Platforms/MacOSX.platform" ]]; then
    print -u2 'Nabira requires full Xcode. Set DEVELOPER_DIR to Xcode.app/Contents/Developer.'
    exit 1
fi
xcrun swift build --package-path "$ROOT" --scratch-path "$SCRATCH" -c "$CONFIGURATION"

STAGE="$(mktemp -d /tmp/nabira-app.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Nabira.app"
FINAL_APP="$ROOT/dist/Nabira.app"
BIN="$SCRATCH/$CONFIGURATION/Nabira"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Nabira"
cp -R "$SCRATCH/$CONFIGURATION/Nabira_Nabira.bundle" "$APP/Contents/Resources/"

ICONSET="$STAGE/AppIcon.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$ROOT/assets/branding/nabira-app-icon.png" \
        --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE_SIZE=$((SIZE * 2))
    sips -z "$DOUBLE_SIZE" "$DOUBLE_SIZE" "$ROOT/assets/branding/nabira-app-icon.png" \
        --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Clear dict" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string Nabira" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.nabira.app" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string Nabira" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Nabira" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 1.0.0" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 14.0" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSHumanReadableCopyright string 'Copyright © 2026 Nabira'" "$APP/Contents/Info.plist"
xattr -cr "$APP"
SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:--}"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    # Keep the local development build recognizable to macOS privacy services
    # after its executable changes. A certificate-signed release gets its
    # normal designated requirement from the signing identity instead.
    codesign --force --deep --sign - \
        --identifier com.nabira.app \
        --requirements '=designated => identifier "com.nabira.app"' \
        "$APP"
else
    codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP"
fi
mkdir -p "$ROOT/dist"
rm -rf "$FINAL_APP"
ditto --noextattr --noqtn "$APP" "$FINAL_APP"
echo "$FINAL_APP"
